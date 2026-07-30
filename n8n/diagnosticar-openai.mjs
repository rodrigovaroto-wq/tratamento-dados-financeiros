// Diz, em segundos, POR QUE a OpenAI está recusando as chamadas do pipeline.
//
//   OPENAI_API_KEY=sk-... node n8n/diagnosticar-openai.mjs
//
// POR QUE EXISTE. No "teste v30" os 14 documentos falharam com uma frase que o
// N8N acrescenta a QUALQUER resposta 429 ("Try spacing your requests out using
// the batching settings under 'Options'"). Essa frase é indistinguível entre
// causas que pedem ações OPOSTAS: crédito esgotado (espaçar não resolve), cota
// diária (não resolve hoje), ou cadência por minuto (aí sim resolve). Sem saber
// qual, a rodada anterior chutou "cadência" e subiu o intervalo de 6s para 12s —
// e o problema continuou. Este script tira o chute da frente: faz UMA chamada
// mínima com a sua chave e devolve a causa classificada.
//
// CUSTO: uma requisição com `max_tokens: 1`. Se a conta estiver sem crédito, ela
// é recusada antes de gerar token nenhum — custo zero. Se estiver funcionando, o
// custo é de um token. Nunca envia documento.
//
// O diagnóstico é o MESMO usado em produção (`diagnosticarErroApi` de
// lib/extract.mjs, embutido nos nós do workflow) — de propósito: se o script diz
// "crédito esgotado", é exatamente isso que a pendência do documento vai dizer.

import { diagnosticarErroApi, DEFAULT_MODEL, OPENAI_URL } from './lib/extract.mjs';

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
  console.log('\nSe as extrações continuam falhando com 429 mesmo assim, a causa é CADÊNCIA sob carga:');
  console.log('a chamada avulsa passa, mas 14 documentos seguidos estouram o limite por minuto (TPM).');
  console.log('Nesse caso o que resolve é reduzir o TAMANHO do que é enviado — não só espaçar mais.');
  console.log('Ver docs/CUSTO_OPENAI.md (PDF como texto em vez de imagem: 60-80% menos input).');
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
