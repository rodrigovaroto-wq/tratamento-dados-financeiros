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

export function prepararRepublicacao(vivo, repo) {
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
    if (doRepo.credentials) {
      saida.credentials = {};
      for (const [tipo, cred] of Object.entries(doRepo.credentials)) {
        const idVivo = oVivo?.credentials?.[tipo]?.id;
        const nomeVivo = oVivo?.credentials?.[tipo]?.name;
        saida.credentials[tipo] = idVivo && idVivo !== 'REPLACE'
          ? { id: idVivo, name: nomeVivo ?? cred.name }
          : { ...cred };
      }
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

  const pronto = prepararRepublicacao(vivo, repo);

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
  }
  console.error(`\nDepois de publicar, confira: … | node N8N/conferir-publicado.mjs`);

  process.stdout.write(`${JSON.stringify(pronto, null, 2)}\n`);
  if (CAMPOS_DO_PUT.some((c) => !(c in pronto))) process.exit(1);
}
