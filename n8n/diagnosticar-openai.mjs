// Diz, em segundos, POR QUE a OpenAI está recusando as chamadas do pipeline.
//
//   OPENAI_API_KEY=sk-... node n8n/diagnosticar-openai.mjs
//
// POR QUE EXISTE. No "teste v30" os 14 documentos falharam com uma frase que o
// N8N acrescenta a QUALQUER resposta 429 ("Try spacing your requests out using
// the batching settings under 'Options'"). Essa frase é indistinguível entre
// causas que pedem ações OPOSTAS:
//
//   • crédito esgotado          → recarregar (espaçar não resolve)
//   • TETO DE GASTO configurado → subir o teto do projeto/org (espaçar não resolve),
//                                 e ele NÃO aparece nas telas de Billing e Limits
//   • cota diária               → só reabre amanhã
//   • cadência por minuto       → o ÚNICO caso em que espaçar resolve
//
// Sem saber qual, a rodada anterior chutou "cadência" e subiu o intervalo de 6s
// para 12s — e o problema continuou. Este script tira o chute da frente: faz UMA
// chamada mínima com a sua chave e devolve a causa classificada.
//
// LIMITE DO SCRIPT, dito de frente: ele testa a conta AGORA. Uma chamada avulsa
// passar não descarta teto de gasto atingido no momento do lote, nem cadência sob
// carga. Quando ele diz "está respondendo normalmente", a saída explica os dois e
// aponta o que decide de fato — a execução guardada no N8N, que preservou o corpo
// real da OpenAI.
//
// CUSTO: uma requisição com `max_tokens: 1`. Se a conta estiver sem crédito, ela
// é recusada antes de gerar token nenhum — custo zero. Se estiver funcionando, o
// custo é de um token. Nunca envia documento.
//
// O diagnóstico é o MESMO usado em produção (`diagnosticarErroApi` de
// lib/extract.mjs, embutido nos nós do workflow) — de propósito: se o script diz
// "crédito esgotado", é exatamente isso que a pendência do documento vai dizer.

import { readFileSync } from 'node:fs';
import { diagnosticarErroApi, DEFAULT_MODEL, OPENAI_URL, MAX_OUTPUT_TOKENS } from './lib/extract.mjs';

// O intervalo REALMENTE gerado no workflow — lido do JSON, não reescrito aqui.
// Comparar o configurado com o que o TPM real suporta é o ponto do script; ler de
// uma segunda fonte anularia a comparação (os dois números viriam do mesmo lugar).
const INTERVALO_EXTRACAO_CONFIGURADO = (() => {
  try {
    const wf = JSON.parse(readFileSync(new URL('./workflow.e1-ingestao.json', import.meta.url), 'utf8'));
    const no = wf.nodes.find((n) => n.name === 'OpenAI Extrair');
    return no?.parameters?.options?.batching?.batch?.batchInterval ?? null;
  } catch { return null; }
})();

const chave = process.env.OPENAI_API_KEY;
if (!chave) {
  console.error('Falta OPENAI_API_KEY. Rode:  OPENAI_API_KEY=sk-... node n8n/diagnosticar-openai.mjs');
  console.error('(a mesma chave que está na credencial "OpenAI API" do N8N — é ela que precisa ser testada)');
  process.exit(2);
}

const modelo = process.argv[2] || DEFAULT_MODEL;

console.log(`Testando a conta OpenAI com o modelo ${modelo} (1 token de saída)...\n`);

let resposta;
let corpo;
try {
  resposta = await fetch(OPENAI_URL, {
    method: 'POST',
    headers: { 'content-type': 'application/json', authorization: `Bearer ${chave}` },
    body: JSON.stringify({
      model: modelo,
      max_tokens: 1,
      messages: [{ role: 'user', content: 'ok' }],
    }),
  });
  corpo = await resposta.json().catch(() => ({}));
} catch (erro) {
  console.log('FALHA DE REDE ao chegar na OpenAI (nem o servidor respondeu):');
  console.log(`  ${erro?.message ?? erro}`);
  console.log('\nSe o N8N está atrás de proxy/firewall, é aí que olhar — não é conta nem cadência.');
  process.exit(1);
}

if (resposta.ok) {
  console.log('A CONTA ESTÁ RESPONDENDO NORMALMENTE.');
  console.log(`  HTTP ${resposta.status} · modelo ${corpo?.model ?? modelo}`);
  console.log('\nUma chamada avulsa passar NÃO descarta duas causas — as duas ficam invisíveis aqui:');
  console.log('  1. TETO DE GASTO já atingido no momento do LOTE (do projeto da chave ou orçamento');
  console.log('     mensal da org). Não aparece na tela de Billing nem na de Limits do tier.');
  console.log('     Conferir: Settings → Limits E Settings → Projects → projeto da chave → Limits.');
  console.log('  2. CADÊNCIA sob carga: 1 chamada passa, 14 seguidas estouram o limite por MINUTO.');
  console.log('     A conta abaixo diz se é o caso.');
  console.log('\nO que decide de fato, sem gastar nada: abrir a execução que falhou no N8N →');
  console.log('nó "OpenAI Extrair" → Output → JSON de um item falho → ler `error.error.code`.');
  console.log('O corpo real da OpenAI está preservado ali (o n8n só sobrescreve o campo `message`).');
  // Limites do momento vêm nos headers — quando presentes, respondem de uma vez
  // qual é o teto e quanto sobrou. É a informação que a pendência nunca teve.
  const cabecalhos = [
    'x-ratelimit-limit-requests', 'x-ratelimit-remaining-requests',
    'x-ratelimit-limit-tokens', 'x-ratelimit-remaining-tokens',
    'x-ratelimit-reset-tokens',
  ].map((h) => [h, resposta.headers.get(h)]).filter(([, v]) => v);
  if (cabecalhos.length) {
    console.log('\nLimites informados pela OpenAI para esta chave/modelo:');
    for (const [h, v] of cabecalhos) console.log(`  ${h.replace('x-ratelimit-', '')}: ${v}`);
  }

  // A ARITMÉTICA, com o TPM REAL da conta em vez do palpite. A OpenAI conta o
  // consumo de rate limit como o MÁXIMO entre `max_tokens` e os tokens estimados
  // do request — então cada extração reserva `MAX_OUTPUT_TOKENS` do balde por
  // minuto, independente do tamanho do PDF. Com o teto real em mãos, dá para
  // dizer se a cadência configurada cabe ou não, e qual seria a certa.
  const tpmReal = Number(resposta.headers.get('x-ratelimit-limit-tokens'));
  if (Number.isFinite(tpmReal) && tpmReal > 0) {
    const chamadasPorMin = tpmReal / MAX_OUTPUT_TOKENS;
    const intervaloIdeal = Math.ceil(60000 / chamadasPorMin);
    console.log('\nCADÊNCIA que este TPM suporta (max_tokens da extração = '
      + `${MAX_OUTPUT_TOKENS}, que é RESERVA de TPM por chamada):`);
    console.log(`  ${chamadasPorMin.toFixed(1)} chamada(s)/min → intervalo mínimo de ${intervaloIdeal}ms`);
    if (intervaloIdeal !== INTERVALO_EXTRACAO_CONFIGURADO) {
      console.log(`\n  ⚠️  O workflow está configurado para ${INTERVALO_EXTRACAO_CONFIGURADO}ms.`);
      console.log(`  Ajuste TPM_CONTA para ${tpmReal} em n8n/build-workflow.mjs, rode`);
      console.log('  `node n8n/build-workflow.mjs` e reimporte o workflow.');
    } else {
      console.log(`\n  A configuração atual (${INTERVALO_EXTRACAO_CONFIGURADO}ms) confere com este TPM.`);
    }
  }
  process.exit(0);
}

// A resposta de erro real da OpenAI, classificada pelo MESMO código de produção.
const d = diagnosticarErroApi({ httpCode: resposta.status, ...corpo });
console.log(`CAUSA: ${d.causa}\n`);
console.log(d.motivo);
console.log('\n--- resposta bruta da OpenAI (para o registro) ---');
console.log(JSON.stringify(corpo).slice(0, 800));
const retryAfter = resposta.headers.get('retry-after');
if (retryAfter) console.log(`\nRetry-After: ${retryAfter}s`);
process.exit(1);
