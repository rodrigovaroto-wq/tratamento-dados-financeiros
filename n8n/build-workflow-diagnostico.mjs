// Gera o workflow de DIAGNÓSTICO da conta OpenAI.
// Rodar: node n8n/build-workflow-diagnostico.mjs → n8n/workflow.diagnostico-openai.json
//
// Por que ele existe: `n8n/diagnosticar-openai.mjs` faz o mesmo diagnóstico, mas
// exige terminal e a chave da API na mão. O dono não usa terminal e disse isso
// explicitamente ("não sei onde roda isso"). Um diagnóstico que o dono não
// consegue executar não diagnostica nada — então aqui ele é um workflow que se
// importa e se roda com um clique, reaproveitando a credencial `OpenAI API` que
// já existe no n8n dele (a MESMA da ingestão, que é o ponto: diagnosticar outra
// chave responderia a pergunta errada).
//
// O que ele faz, e o que NÃO faz:
//   • manda UMA chamada de 1 token de saída. Se a conta estiver barrada, a OpenAI
//     recusa antes de processar e o custo é ZERO;
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

import { writeFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import { diagnosticarErroApi, MAX_OUTPUT_TOKENS, TPM_CONTA } from './lib/extract.mjs';
import { custoDaChamada, PRECO_USD_POR_MILHAO, TETO_EXECUCAO_USD, CUSTO_ESTIMADO_DOC_USD } from './lib/custo.mjs';

const __dirname = dirname(fileURLToPath(import.meta.url));

const MODELO = 'gpt-4o';
const INTERVALO_EXTRACAO_MS = Math.ceil(60000 / (TPM_CONTA / MAX_OUTPUT_TOKENS));

const node = (name, type, typeVersion, parameters, x, y, extra = {}) => ({
  parameters, id: name.toLowerCase().replace(/[^a-z0-9]+/g, '-'), name, type, typeVersion, position: [x, y], ...extra,
});

// Corpo mínimo: 1 token de saída. `max_tokens: 1` reserva 1 token de TPM em vez
// dos 16.384 da extração, então esta chamada passa mesmo com o balde quase cheio
// — é exatamente o que a torna capaz de separar "cota/teto" de "cadência".
const CODE_REQ = `
return {json:{openai_body:{model:'${MODELO}',max_tokens:1,messages:[{role:'user',content:'ok'}]}}};
`.trim();

const CODE_VEREDITO = `
const diagnosticarErroApi = ${diagnosticarErroApi.toString()};
const PRECO_USD_POR_MILHAO = ${JSON.stringify(PRECO_USD_POR_MILHAO)};
const custoDaChamada = ${custoDaChamada.toString()};

const resp = $input.item.json;
// Com neverError o erro chega como CORPO, não como exceção — é a instrumentação
// da sessão 17, e é o que fez o v31 finalmente nomear a causa.
const temErro = !!(resp && resp.error);
const httpStatus = resp?.error?.status ?? resp?.statusCode ?? (temErro ? 429 : 200);

const linhas = [];
let passou = false, causa = null, motivo = null;

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
  const custo = custoDaChamada(resp?.usage, '${MODELO}');
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
linhas.push('TPM assumido da conta: ${TPM_CONTA} (TPM_CONTA em n8n/lib/extract.mjs)');
linhas.push('Reserva por extracao: ${MAX_OUTPUT_TOKENS} tokens (max_tokens e RESERVA de TPM)');
linhas.push('Logo: ' + chamadasPorMinuto.toFixed(2) + ' chamada(s)/min -> intervalo de ${INTERVALO_EXTRACAO_MS}ms');
linhas.push('Se o seu tier real for MAIOR, ajuste TPM_CONTA: o lote fica muito mais rapido.');
linhas.push('');
linhas.push('--- TETO DE GASTO POR EXECUCAO ---');
linhas.push('Teto no codigo: US$ ${TETO_EXECUCAO_USD.toFixed(2)} por execucao (TETO_EXECUCAO_USD em n8n/lib/custo.mjs)');
linhas.push('Estimativa por chamada: US$ ${CUSTO_ESTIMADO_DOC_USD.toFixed(2)}');
linhas.push('Logo o lote maximo e ' + Math.floor(${TETO_EXECUCAO_USD} / ${CUSTO_ESTIMADO_DOC_USD}) + ' chamada(s) por execucao.');
linhas.push('O teto do PROJETO na OpenAI deve ficar ACIMA disso (US$ 5), para quem barrar');
linhas.push('o lote ser este codigo (que explica o que fazer) e nao a API (que devolve 429).');

return {json:{passou, causa, http_status: httpStatus, veredito: linhas.join('\\n')}};
`.trim();

const nodes = [
  node('Rodar Diagnostico', 'n8n-nodes-base.manualTrigger', 1, {}, 240, 300),
  node('Montar Chamada Minima', 'n8n-nodes-base.code', 2, { mode: 'runOnceForEachItem', jsCode: CODE_REQ }, 460, 300),
  node('OpenAI (1 token)', 'n8n-nodes-base.httpRequest', 4.2, {
    method: 'POST',
    url: 'https://api.openai.com/v1/chat/completions',
    authentication: 'genericCredentialType',
    genericAuthType: 'httpHeaderAuth',
    sendBody: true,
    specifyBody: 'json',
    jsonBody: '={{ JSON.stringify($json.openai_body) }}',
    // Sem isto o 429 volta como AxiosError e o corpo da OpenAI — o único lugar
    // onde a causa REAL aparece — nunca chega ao veredito. É a lição do v30.
    options: { response: { response: { neverError: true } } },
  }, 680, 300, {
    credentials: { httpHeaderAuth: { id: 'REPLACE', name: 'OpenAI API' } },
  }),
  node('Veredito', 'n8n-nodes-base.code', 2, { mode: 'runOnceForEachItem', jsCode: CODE_VEREDITO }, 900, 300),
];

const workflow = {
  name: 'Oria — Diagnostico da conta OpenAI (1 token, custo ~zero)',
  nodes,
  connections: {
    'Rodar Diagnostico': { main: [[{ node: 'Montar Chamada Minima', type: 'main', index: 0 }]] },
    'Montar Chamada Minima': { main: [[{ node: 'OpenAI (1 token)', type: 'main', index: 0 }]] },
    'OpenAI (1 token)': { main: [[{ node: 'Veredito', type: 'main', index: 0 }]] },
  },
  settings: { executionOrder: 'v1' },
  meta: {
    note: 'Gerado por n8n/build-workflow-diagnostico.mjs. Usa a credencial "OpenAI API" que ja existe. '
      + 'Uma chamada de 1 token: se a conta estiver barrada o custo e zero. Nao grava nada em banco. '
      + 'O veredito sai do MESMO diagnosticarErroApi da producao (embutido por toString()).',
  },
};

const destino = join(__dirname, 'workflow.diagnostico-openai.json');
writeFileSync(destino, JSON.stringify(workflow, null, 2) + '\n');
console.log(`Escrito workflow de diagnóstico — ${nodes.length} nós`);
