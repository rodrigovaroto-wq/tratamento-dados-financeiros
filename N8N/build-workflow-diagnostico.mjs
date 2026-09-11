// Gera o workflow de DIAGNÓSTICO da conta do provedor de IA.
// Rodar: node N8N/build-workflow-diagnostico.mjs → N8N/workflow.diagnostico-ia.json
//
// Por que ele existe: `N8N/diagnosticar-ia.mjs` faz o mesmo diagnóstico, mas
// exige terminal e a chave da API na mão. O dono não usa terminal e disse isso
// explicitamente ("não sei onde roda isso"). Um diagnóstico que o dono não
// consegue executar não diagnostica nada — então aqui ele é um workflow que se
// importa e se roda com um clique, reaproveitando a credencial que já existe no
// n8n dele (a MESMA da ingestão, que é o ponto: diagnosticar outra chave
// responderia a pergunta errada).
//
// O que ele faz, e o que NÃO faz:
//   • LISTA OS MODELOS da conta primeiro — um GET, zero token — e confere se o
//     que o workflow de ingestão usa está lá. Isto entrou em 24/08 e é a metade
//     que faltava: o id do modelo é a única coisa deste sistema que nenhum teste
//     prova (só a API do provedor valida a string), e um id errado faz TODA
//     chamada do lote voltar 404. O `--modelos` do script de terminal responde
//     isso — e o dono não usa terminal, que é o motivo de este workflow existir.
//     Deixar a checagem só na versão de terminal seria pôr a resposta onde quem
//     precisa dela não alcança;
//   • manda UMA chamada de 1 token de saída. Se a conta estiver barrada, o
//     provedor recusa antes de processar e o custo é ZERO;
//   • classifica a resposta com `diagnosticarErroApi` — o MESMO código de
//     produção, embutido por `toString()`, então o veredito daqui é o veredito que
//     o pipeline daria;
//   • mede o custo real com `custoDaChamada` e confere se a cadência configurada
//     cabe no TPM da conta;
//   • é o EXPERIMENTO DISCRIMINANTE do v31: se esta chamada mínima PASSA e o lote
//     falha com 429, então crédito e teto de gasto estão descartados (os dois
//     rejeitariam 1 token também) e o que resta é TPM sob carga.
//
// Ele não grava nada em banco nenhum e não tem trigger de relógio: só roda quando
// alguém clica. É diagnóstico, não pipeline.

import { posicionar } from './layout.mjs';
import { writeFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import { diagnosticarErroApi, MAX_OUTPUT_TOKENS, TPM_CONTA, RPM_CONTA } from './lib/extract.mjs';
import { custoDaChamada, PRECO_USD_POR_MILHAO, TETO_EXECUCAO_USD, CUSTO_ESTIMADO_DOC_USD, MODELO_EXTRACAO, MODELO_CLASSIFICACAO } from './lib/custo.mjs';
import {
  provedor, urlDaChamada, montarCorpoIA, parteDeTexto, usoDaChamada,
  modelosDoCatalogo, modelosParecidos,
} from './lib/provedor.mjs';

const __dirname = dirname(fileURLToPath(import.meta.url));

const PROV = provedor();
// O MODELO É O DA EXTRAÇÃO, e não um escolhido aqui. Diagnosticar um modelo que
// o pipeline não usa responderia a pergunta errada — limite e disponibilidade
// são POR MODELO na maioria dos provedores.
const MODELO = MODELO_EXTRACAO;
// A mesma aritmética do gerador da ingestão, e pelo mesmo motivo: o intervalo é
// o maior entre o que o balde de TOKENS permite e o que o limite de CHAMADAS
// permite. Duplicar a conta aqui faria o diagnóstico afirmar uma cadência que o
// workflow não usa.
const INTERVALO_POR_TPM_MS = Math.ceil(60000 / (TPM_CONTA / MAX_OUTPUT_TOKENS));
const INTERVALO_POR_RPM_MS = RPM_CONTA ? Math.ceil((60000 / RPM_CONTA) * 2) : 0;
const INTERVALO_EXTRACAO_MS = Math.max(INTERVALO_POR_TPM_MS, INTERVALO_POR_RPM_MS, 6000);

// Sem `position` à mão: quem desenha o canvas é `posicionar()` (N8N/layout.mjs),
// a partir das conexões.
const node = (name, type, typeVersion, parameters, extra = {}) => ({
  parameters, id: name.toLowerCase().replace(/[^a-z0-9]+/g, '-'), name, type, typeVersion, position: [0, 0], ...extra,
});

// Corpo mínimo: 1 token de saída. `max_tokens: 1` reserva 1 token de TPM em vez
// dos 16.384 da extração, então esta chamada passa mesmo com o balde quase cheio
// — é exatamente o que a torna capaz de separar "cota/teto" de "cadência".
// O corpo é montado AQUI, no build, e entra no nó como literal: ele não depende
// de nada do item. Vem de `montarCorpoIA` como todos os outros — sem schema, que
// é o que o torna mínimo de verdade.
// `esforco: 'none'` NÃO É DETALHE — sem ele esta chamada deixa de ser mínima.
//
// O Luna é modelo de RACIOCÍNIO, e o default dele é `medium`. Token de
// raciocínio é cobrado como SAÍDA e é gasto ANTES da primeira letra da resposta,
// então um teto de 1 token contra um esforço médio produz o pior dos mundos:
// centenas ou milhares de tokens cobrados, resposta VAZIA (cortada pelo teto
// antes de escrever qualquer coisa), e um veredito que passa a medir o
// truncamento em vez de medir se a conta responde. A chamada que existe para ser
// a mais barata do sistema viraria uma das mais caras — e mentiria.
//
// `none` é o único valor que torna "1 token de saída" alcançável de verdade num
// modelo que raciocina. Em provedor que não raciocina, `montarCorpoIA` ignora o
// campo (mandá-lo seria 400), então a linha é segura nos dois lados.
const CORPO_MINIMO = montarCorpoIA(PROV, {
  modelo: MODELO,
  sistema: null,
  partes: [parteDeTexto(PROV, 'ok')],
  maxTokens: 1,
  esforco: 'none',
});

const CODE_REQ = `
return {json:{ia_body:${JSON.stringify(CORPO_MINIMO)}}};
`.trim();

const CODE_VEREDITO = `
const diagnosticarErroApi = ${diagnosticarErroApi.toString()};
const PRECO_USD_POR_MILHAO = ${JSON.stringify(PRECO_USD_POR_MILHAO)};
const custoDaChamada = ${custoDaChamada.toString()};
const PROVEDOR = ${JSON.stringify(PROV)};
const usoDaChamada = ${usoDaChamada.toString()};
const modelosDoCatalogo = ${modelosDoCatalogo.toString()};
const modelosParecidos = ${modelosParecidos.toString()};
const MODELO_EXTRACAO = ${JSON.stringify(MODELO_EXTRACAO)};
const MODELO_CLASSIFICACAO = ${JSON.stringify(MODELO_CLASSIFICACAO)};

const resp = $input.item.json;
// Com neverError o erro chega como CORPO, não como exceção — é a instrumentação
// da sessão 17, e é o que fez o v31 finalmente nomear a causa.
const temErro = !!(resp && resp.error);
const httpStatus = resp?.error?.status ?? resp?.statusCode ?? (temErro ? 429 : 200);

const linhas = [];
let passou = false, causa = null, motivo = null;

// ---------------------------------------------------------------------------
// PRIMEIRO O CATÁLOGO — a checagem que custa zero e explica o 404 antes dele
// ---------------------------------------------------------------------------
//
// Vem antes de qualquer coisa no relatório porque é a única falha desta lista
// que tem conserto imediato E depende de saber o que EXISTE: "o modelo não
// existe" é meia informação; "não existe, e o que existe é isto" é a correção
// inteira.
let listaOk = false;
let modelosDaConta = [];
try {
  const respLista = $('Listar Modelos').item.json;
  modelosDaConta = modelosDoCatalogo(PROVEDOR, respLista);
  listaOk = modelosDaConta.length > 0;
} catch (e) { listaOk = false; }

const configurados = MODELO_EXTRACAO === MODELO_CLASSIFICACAO
  ? [MODELO_EXTRACAO]
  : [MODELO_EXTRACAO, MODELO_CLASSIFICACAO];
const faltando = listaOk ? configurados.filter((m) => modelosDaConta.indexOf(m) === -1) : [];

linhas.push('--- MODELOS DA CONTA (GET no catalogo, zero token) ---');
if (!listaOk) {
  linhas.push('NAO FOI POSSIVEL LISTAR os modelos desta conta.');
  linhas.push('Causa provavel: a credencial do no "Listar Modelos" nao foi selecionada,');
  linhas.push('ou a chave nao tem permissao. Sem a lista, um 404 abaixo fica sem explicacao.');
} else {
  linhas.push('A conta lista ' + modelosDaConta.length + ' modelo(s).');
  linhas.push('Configurado no workflow de ingestao: ' + configurados.join(', '));
  if (faltando.length === 0) {
    linhas.push('OK -- todos existem nesta conta. O id do modelo esta certo.');
  } else {
    linhas.push('*** PROBLEMA: ' + faltando.join(', ') + ' NAO existe(m) nesta conta. ***');
    linhas.push('Toda chamada do lote voltaria 404. O que existe de mais parecido:');
    for (const m of faltando) {
      linhas.push('  para "' + m + '": ' + (modelosParecidos(m, modelosDaConta, 5).join(', ') || '(nada parecido)'));
    }
    linhas.push('Corrija MODELOS_POR_PROVEDOR em N8N/lib/custo.mjs, rode');
    linhas.push('node N8N/build-workflow.mjs e reimporte os workflows.');
  }
}
linhas.push('');

if (temErro) {
  const d = diagnosticarErroApi({ statusCode: httpStatus, body: resp });
  causa = d.causa; motivo = d.motivo;
  linhas.push('RESULTADO: a chamada de 1 token FALHOU.');
  linhas.push('CAUSA CLASSIFICADA: ' + causa);
  linhas.push('');
  linhas.push(motivo);
  linhas.push('');
  if (causa === 'limite_de_gasto' || causa === 'sem_credito' || causa === 'limite_diario') {
    linhas.push('LEITURA: uma chamada de 1 TOKEN foi recusada. Isso descarta cadencia por');
    linhas.push('completo — nao existe "espacar mais" que resolva, porque nao ha volume aqui.');
    linhas.push('O caminho e o teto/credito da conta, e mais nada.');
  } else if (causa === 'limite_cadencia' || causa === 'limite_indeterminado') {
    linhas.push('LEITURA: 429 numa chamada de 1 token e MUITO improvavel ser cadencia.');
    linhas.push('Se o corpo da OpenAI nao veio, confirme que o no esta com neverError ligado.');
  }
} else {
  passou = true;
  const custo = custoDaChamada(usoDaChamada(PROVEDOR, resp), '${MODELO}');
  linhas.push('RESULTADO: a chamada de 1 token PASSOU. A chave e a conta respondem.');
  if (custo != null) linhas.push('Custo desta chamada: US$ ' + custo.toFixed(6));
  linhas.push('');
  linhas.push('EXPERIMENTO DISCRIMINANTE — leia com o resultado do ultimo lote:');
  linhas.push('  • se o LOTE tambem passa: nao ha nada errado com a conta.');
  linhas.push('  • se o LOTE falha com 429 e ESTA passa: credito e teto de gasto estao');
  linhas.push('    DESCARTADOS (os dois rejeitariam 1 token tambem). Sobra TPM sob carga,');
  linhas.push('    que e o que a cadencia derivada abaixo respeita.');
}

// A aritmética da cadência, para o dono conferir sem abrir código nenhum.
const chamadasPorMinuto = ${TPM_CONTA} / ${MAX_OUTPUT_TOKENS};
linhas.push('');
linhas.push('--- CADENCIA CONFIGURADA (aritmetica, nao chute) ---');
linhas.push('Provedor ativo: ${PROV.rotulo} | modelo: ${MODELO}');
linhas.push('TPM assumido da conta: ${TPM_CONTA} (tpm do provedor, em N8N/lib/provedor.mjs)');
linhas.push('RPM assumido da conta: ${RPM_CONTA === null ? 'sem limite por chamada' : RPM_CONTA}');
linhas.push('Reserva por extracao: ${MAX_OUTPUT_TOKENS} tokens (max_tokens e RESERVA de TPM)');
linhas.push('Pelo TPM: ' + chamadasPorMinuto.toFixed(2) + ' chamada(s)/min -> ${INTERVALO_POR_TPM_MS}ms');
linhas.push('Intervalo configurado (o mais restritivo dos limites): ${INTERVALO_EXTRACAO_MS}ms');
linhas.push('Se o seu tier real for MAIOR, ajuste tpm/rpm do provedor: o lote fica mais rapido.');
linhas.push('');
linhas.push('--- TETO DE GASTO POR EXECUCAO ---');
linhas.push('Teto no codigo: US$ ${TETO_EXECUCAO_USD.toFixed(2)} por execucao (TETO_EXECUCAO_USD em N8N/lib/custo.mjs)');
linhas.push('Estimativa por chamada: US$ ${CUSTO_ESTIMADO_DOC_USD.toFixed(2)}');
linhas.push('Logo o lote maximo e ' + Math.floor(${TETO_EXECUCAO_USD} / ${CUSTO_ESTIMADO_DOC_USD}) + ' chamada(s) por execucao.');
linhas.push('O teto do PROJETO no provedor deve ficar ACIMA disso (US$ 5), para quem barrar');
linhas.push('o lote ser este codigo (que explica o que fazer) e nao a API (que devolve 429).');
linhas.push('ATENCAO: teto e configuracao de CONTA, e nao se herda ao trocar de provedor.');

return {json:{passou, causa, http_status: httpStatus, veredito: linhas.join('\\n')}};
`.trim();

const nodes = [
  node('Rodar Diagnostico', 'n8n-nodes-base.manualTrigger', 1, {}),
  // GET no catálogo: nenhum token, nenhum corpo. `neverError` pela mesma razão
  // do nó de baixo — sem ele, uma chave inválida vira exceção e o veredito nunca
  // chega a dizer o que houve.
  node('Listar Modelos', 'n8n-nodes-base.httpRequest', 4.2, {
    method: 'GET',
    url: PROV.catalogo,
    authentication: 'genericCredentialType',
    genericAuthType: 'httpHeaderAuth',
    options: { response: { response: { neverError: true } } },
  }, {
    onError: 'continueRegularOutput',
    credentials: { httpHeaderAuth: { id: 'REPLACE', name: PROV.credencial } },
  }),
  node('Montar Chamada Minima', 'n8n-nodes-base.code', 2, { mode: 'runOnceForEachItem', jsCode: CODE_REQ }),
  node('IA (1 token)', 'n8n-nodes-base.httpRequest', 4.2, {
    method: 'POST',
    url: urlDaChamada(PROV, MODELO),
    authentication: 'genericCredentialType',
    genericAuthType: 'httpHeaderAuth',
    sendBody: true,
    specifyBody: 'json',
    jsonBody: '={{ JSON.stringify($json.ia_body) }}',
    // Sem isto o 429 volta como AxiosError e o corpo da OpenAI — o único lugar
    // onde a causa REAL aparece — nunca chega ao veredito. É a lição do v30.
    options: { response: { response: { neverError: true } } },
  }, {
    credentials: { httpHeaderAuth: { id: 'REPLACE', name: PROV.credencial } },
  }),
  node('Veredito', 'n8n-nodes-base.code', 2, { mode: 'runOnceForEachItem', jsCode: CODE_VEREDITO }),
];

const connections = {
  'Rodar Diagnostico': { main: [[{ node: 'Listar Modelos', type: 'main', index: 0 }]] },
  'Listar Modelos': { main: [[{ node: 'Montar Chamada Minima', type: 'main', index: 0 }]] },
  'Montar Chamada Minima': { main: [[{ node: 'IA (1 token)', type: 'main', index: 0 }]] },
  'IA (1 token)': { main: [[{ node: 'Veredito', type: 'main', index: 0 }]] },
};

// O canvas é desenhado a partir do grafo, nunca à mão (ver N8N/layout.mjs).
posicionar(nodes, connections);

const workflow = {
  name: `Oria — Diagnostico da conta ${PROV.rotulo} (1 token, custo ~zero)`,
  nodes,
  connections,
  settings: { executionOrder: 'v1' },
  meta: {
    note: 'Gerado por N8N/build-workflow-diagnostico.mjs. '
      + `Usa a credencial "${PROV.credencial}", a MESMA da ingestao. `
      + 'Lista os modelos da conta (GET, zero token) e faz UMA chamada de 1 token: se a conta '
      + 'estiver barrada o custo e zero. Nao grava nada em banco. '
      + 'O veredito sai do MESMO diagnosticarErroApi da producao (embutido por toString()).',
  },
};

const destino = join(__dirname, 'workflow.diagnostico-ia.json');
writeFileSync(destino, JSON.stringify(workflow, null, 2) + '\n');
console.log(`Escrito workflow de diagnóstico — ${nodes.length} nós`);
