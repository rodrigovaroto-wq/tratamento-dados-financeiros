// O JSON PRONTO PARA PUBLICAR — comportamento do repositório, identidade da instalação.
//
// POR QUE ISTO EXISTE. Duas republicações seguidas (26/08 e 27/08) perderam a
// mesma coisa: os campos de nó que vivem FORA de `parameters`. Medido na
// segunda, contra o workflow vivo: `onError: continueRegularOutput` em 23 nós,
// `retryOnFail`/`maxTries`/`waitBetweenTries` em 11 — e, na do dia 27, o
// `multipleFiles: true` do campo de arquivo do formulário, que é o que permite
// subir mais de um documento por vez.
//
// Corrigir isso à mão é abrir 23 nós no editor e mexer na aba Settings de cada
// um. Este script faz a fusão em um comando: parte do JSON do REPOSITÓRIO (que
// é a autoridade sobre o que o workflow FAZ e COMO ele falha) e traz do
// PUBLICADO só o que pertence à instalação e não pode ser sobrescrito:
//
//   • o `id` de cada credencial — o repositório grava `REPLACE` de propósito,
//     para não guardar nada da instalação;
//   • o `path` do gatilho de formulário — ele é atribuído pelo n8n, e
//     sobrescrevê-lo TROCA A URL PÚBLICA do intake (já se perdeu uma vez assim);
//   • o `id` de cada nó e as `settings` do workflow — onde mora, entre outras
//     coisas, o `errorWorkflow` que o dono ligou à mão.
//
//   curl -s -H "X-N8N-API-KEY: $N8N_API_KEY" "$N8N_URL/api/v1/workflows/$ID" \
//     | node N8N/preparar-republicacao.mjs > publicar.json
//
//   curl -X PUT -H "X-N8N-API-KEY: $N8N_API_KEY" -H 'Content-Type: application/json' \
//     "$N8N_URL/api/v1/workflows/$ID" --data-binary @publicar.json
//
//   # e conferir o que ficou de pé, que é o passo que ninguém pode pular:
//   curl -s -H "X-N8N-API-KEY: $N8N_API_KEY" "$N8N_URL/api/v1/workflows/$ID" \
//     | node N8N/conferir-publicado.mjs
//
// O JSON sai por `JSON.stringify`, que escapa `\uXXXX` corretamente — a
// armadilha de 26/08 era o transporte do MCP DECODIFICAR esses escapes e
// transformar a chave de dedup do `Juntar Blocos` num byte NUL cru. Por `curl`
// com `--data-binary`, o byte que sai é o que este script escreveu.
import { readFileSync } from 'node:fs';
import { lerWorkflowDaEntradaPadrao, ehExecucaoDireta } from './entrada-workflow.mjs';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const RAIZ = resolve(dirname(fileURLToPath(import.meta.url)), '..');

/** O que o PUT aceita — mandar campo a mais faz o n8n recusar a requisição. */
const CAMPOS_DO_PUT = ['name', 'nodes', 'connections', 'settings'];

/**
 * IDs DE CREDENCIAL VINDOS DE FORA, por NOME — a saída para o que o vivo não conta.
 *
 * POR QUE ISTO EXISTE, e o número é medido. `prepararRepublicacao` resolve o id
 * lendo o workflow PUBLICADO, e isso funciona para a maioria: na republicação de
 * 11/09/2026 as ONZE credenciais `postgres` resolveram todas. As TRÊS
 * `httpHeaderAuth` não resolveram NENHUMA — e a divisão é por TIPO, não por nó.
 * A API pública do n8n (`GET /api/v1/workflows/:id`) não devolve a credencial
 * `httpHeaderAuth` desses nós, então não há o que ler. O resultado foi a action
 * do GitHub abortar em TRÊS execuções seguidas, no passo 4, com "sobraram 2
 * ocorrência(s) de REPLACE" — `IA Classificar` e `IA Extrair`.
 *
 * A trava que abortou estava CERTA: publicar `REPLACE` num nó ligado quebra a
 * credencial dele em produção. O que faltava era um jeito de o id chegar aqui
 * sem passar pelo vivo — e sem ser versionado, que é a razão de o repositório
 * gravar `REPLACE` desde sempre.
 *
 * A CHAVE É O NOME DA CREDENCIAL, não o nó: uma mesma credencial ("OpenAI API")
 * serve vários nós, e mapear por nó obrigaria a repetir o mesmo id N vezes —
 * cada repetição uma chance de divergir.
 *
 * Formato (JSON no ambiente, tipicamente um secret do GitHub):
 *     N8N_CRED_IDS='{"OpenAI API":"aBc123","Supabase Service (Header Auth)":"dEf456"}'
 *
 * PRECEDÊNCIA, e ela é deliberada: o VIVO ganha. Quem está publicado é a verdade
 * sobre a instalação; o mapa é a queda para quando ele se cala. Ao contrário, um
 * mapa desatualizado sobrescreveria silenciosamente a credencial certa por uma
 * que não existe mais — e o sintoma apareceria só na próxima rodada.
 *
 * ID INVÁLIDO NÃO ENTRA: `REPLACE` ou vazio no mapa é tratado como ausência, não
 * como resposta. Aceitar `REPLACE` aqui desarmaria a trava do `republicar.sh`
 * fazendo exatamente o que ela existe para impedir.
 */
export function idsDeCredencialDoAmbiente(env = process.env) {
  const cru = env.N8N_CRED_IDS;
  if (!cru || !String(cru).trim()) return {};
  let mapa;
  try {
    mapa = JSON.parse(cru);
  } catch {
    throw new Error('N8N_CRED_IDS não é JSON válido. Esperado um objeto '
      + '{"<nome da credencial>": "<id>"} — por exemplo {"OpenAI API":"aBc123"}.');
  }
  if (!mapa || typeof mapa !== 'object' || Array.isArray(mapa)) {
    throw new Error('N8N_CRED_IDS precisa ser um OBJETO {"<nome>": "<id>"}, não '
      + `${Array.isArray(mapa) ? 'uma lista' : typeof mapa}.`);
  }
  const limpo = {};
  for (const [nome, id] of Object.entries(mapa)) {
    if (typeof id === 'string' && id.trim() && id !== 'REPLACE') limpo[nome] = id.trim();
  }
  return limpo;
}

export function prepararRepublicacao(vivo, repo, { idsPorNome = {} } = {}) {
  const doVivo = new Map((vivo.nodes ?? []).map((n) => [n.name, n]));

  const nodes = (repo.nodes ?? []).map((doRepo) => {
    const oVivo = doVivo.get(doRepo.name);
    const saida = { ...doRepo };

    // O id do NÓ: preservado quando existe, para o n8n não tratar o nó como
    // novo (o que descarta o histórico de execução preso a ele).
    if (oVivo?.id) saida.id = oVivo.id;
    if (oVivo?.webhookId) saida.webhookId = oVivo.webhookId;

    // O `path` do formulário — ver o cabeçalho. É o único parâmetro que o
    // publicado manda no repositório, e não o contrário.
    if (oVivo?.parameters?.path) {
      saida.parameters = { ...doRepo.parameters, path: oVivo.parameters.path };
    }

    // As CREDENCIAIS: o tipo e o nome são do repositório, o id é da instalação.
    // Sem isto, o `REPLACE` do repositório iria para produção e o nó falharia
    // com "Credential with ID REPLACE does not exist" — que foi exatamente o
    // erro do smoke test de 27/08.
    //
    // A EXCEÇÃO medida em 11/09/2026, no `Upload Storage`: nó DESABILITADO
    // sem id na instalação. Ele não executa — então a credencial some em vez
    // de ir REPLACE: nó desligado sem credencial não falha; nó desligado COM
    // REPLACE é o que o portão do republicar.sh barra o arquivo inteiro. Um
    // nó LIGADO sem id continua recebendo o REPLACE, e o portão continua
    // abortando — a trava fica intacta onde ela é defesa.
    if (doRepo.credentials) {
      saida.credentials = {};
      for (const [tipo, cred] of Object.entries(doRepo.credentials)) {
        const idVivo = oVivo?.credentials?.[tipo]?.id;
        const nomeVivo = oVivo?.credentials?.[tipo]?.name;
        // O mapa do ambiente é a QUEDA, nunca a primeira escolha — ver o
        // cabeçalho de `idsDeCredencialDoAmbiente`.
        const idDeFora = idsPorNome[cred.name];
        if (idVivo && idVivo !== 'REPLACE') {
          saida.credentials[tipo] = { id: idVivo, name: nomeVivo ?? cred.name };
        } else if (idDeFora) {
          saida.credentials[tipo] = { id: idDeFora, name: cred.name };
        } else if (!doRepo.disabled) {
          saida.credentials[tipo] = { ...cred };
        }
      }
      if (Object.keys(saida.credentials).length === 0) delete saida.credentials;
    }
    return saida;
  });

  return {
    name: repo.name ?? vivo.name,
    nodes,
    connections: repo.connections ?? {},
    // As `settings` são da INSTALAÇÃO: é onde o dono ligou o `errorWorkflow`, e
    // sobrescrever com as do repositório o desligaria em silêncio — o defeito
    // desta família, cometido de novo em outro campo.
    settings: { ...repo.settings, ...vivo.settings },
  };
}

/** Os nós que ainda saem com `REPLACE` — o passo manual que sobra. */
export function credenciaisPendentes(pronto) {
  const pendentes = [];
  for (const n of pronto.nodes ?? []) {
    for (const [tipo, cred] of Object.entries(n.credentials ?? {})) {
      if (cred.id === 'REPLACE') pendentes.push({ no: n.name, tipo, nome: cred.name, desabilitado: !!n.disabled });
    }
  }
  return pendentes;
}

// ---------------------------------------------------------------------------

if (ehExecucaoDireta(import.meta.url)) {
  const vivo = await lerWorkflowDaEntradaPadrao([
    'uso: curl -s -H "X-N8N-API-KEY: $K" "$URL/api/v1/workflows/$ID" \\',
    '       | node N8N/preparar-republicacao.mjs > publicar.json',
    '     o JSON do workflow PUBLICADO entra pela entrada padrão; o pronto sai pela saída padrão.',
  ]);
  const repo = JSON.parse(readFileSync(resolve(RAIZ, 'N8N/workflow.e1-ingestao.json'), 'utf8'));

  const pronto = prepararRepublicacao(vivo, repo, { idsPorNome: idsDeCredencialDoAmbiente() });

  // O relatório vai para o ERRO, não para a saída: a saída é o JSON, e ela
  // costuma estar redirecionada para um arquivo.
  const pendentes = credenciaisPendentes(pronto);
  const sobreOErro = pronto.settings.errorWorkflow
    ? ` (errorWorkflow ${pronto.settings.errorWorkflow})`
    : ' — SEM errorWorkflow';
  console.error(`pronto: ${pronto.nodes.length} nós, ${Object.keys(pronto.connections).length} com conexão, `
    + `settings da instalação preservadas${sobreOErro}.`);
  if (pendentes.length) {
    console.error(`\n${pendentes.length} credencial(is) ainda em REPLACE — o passo que só o editor resolve:`);
    for (const p of pendentes) {
      console.error(`  • ${p.no} (${p.tipo}: "${p.nome}")${p.desabilitado ? ' — nó DESABILITADO, então não impede a rodada' : ' — nó HABILITADO, VAI FALHAR'}`);
    }
    // A MENSAGEM DIZ O QUE FAZER, e isso é o que faltava: nas três execuções
    // da action de 11/09 ela listava os nós pendentes e parava aí. Saber QUAIS
    // nós não diz a ninguém como destravar — e o efeito prático foi a
    // republicação ficar parada, que é o passo sem o qual a correção fica no
    // repositório e não na produção.
    const nomesUnicos = [...new Set(pendentes.filter((p) => !p.desabilitado).map((p) => p.nome))];
    if (nomesUnicos.length) {
      const exemplo = JSON.stringify(Object.fromEntries(nomesUnicos.map((n) => [n, '<id>'])));
      console.error('\nCOMO DESTRAVAR — dois caminhos, e o segundo é o que serve para automação:');
      console.error('  1. No editor do n8n, abra cada nó acima e escolha a credencial na lista.');
      console.error('     O id passa a vir do publicado e nunca mais precisa ser informado.');
      console.error('  2. Informe o id por ambiente, em N8N_CRED_IDS (um secret do GitHub):');
      console.error(`         N8N_CRED_IDS='${exemplo}'`);
      console.error('     O id aparece na URL ao abrir a credencial no n8n:');
      console.error('         .../home/credentials/<id>');
      console.error('     Vale para a API pública do n8n NÃO devolver a credencial `httpHeaderAuth`');
      console.error('     destes nós — foi o que travou a action em 11/09/2026 (as 11 credenciais');
      console.error('     `postgres` resolveram pelo publicado; as `httpHeaderAuth`, nenhuma).');
    }
  }
  console.error(`\nDepois de publicar, confira: … | node N8N/conferir-publicado.mjs`);

  process.stdout.write(`${JSON.stringify(pronto, null, 2)}\n`);
  if (CAMPOS_DO_PUT.some((c) => !(c in pronto))) process.exit(1);
}
