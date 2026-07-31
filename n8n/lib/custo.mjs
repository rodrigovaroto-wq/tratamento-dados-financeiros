// Orçamento de execução — o teto de gasto que o DONO pediu, em código.
//
// Pedido literal (2026-07-31, depois do teste v31): "o sistema não deve gastar
// mais de $3 dólares por execução completa e o teto deve ficar em $5".
//
// São DUAS defesas em camadas diferentes, e a distinção importa:
//
//   • O teto de US$ 5 é configurado NA OPENAI (Settings → Projects → Limits). É
//     a defesa dura: se este código falhar em qualquer hipótese, a OpenAI recusa
//     a chamada e o pipeline registra `limite_de_gasto` com causa nomeada — foi
//     exatamente o que aconteceu no v31. Nenhuma linha daqui pode substituir
//     isso, e é bom que não possa: um teto que o próprio sistema controla é um
//     teto que um bug do próprio sistema fura.
//
//   • O teto de US$ 3 por execução é ESTE arquivo. Ele existe para o lote nunca
//     CHEGAR no limite da OpenAI, porque chegar lá é caro de outra forma: no v31
//     o teto cortou no meio do lote e 8 documentos morreram sem extração. A
//     diferença entre US$ 3 e US$ 5 é a folga que garante que quem barra o lote
//     seja este código (que explica o que fazer) e não a API (que só devolve 429).
//
// A decisão é tomada ANTES da primeira chamada, e é um NÃO INTEIRO: ou o lote
// cabe e roda todo, ou não começa. Deliberadamente não existe "roda os que
// cabem": um lote parcial deixa metade dos documentos registrados sem extração
// e a outra metade sem registro nenhum, e distinguir os dois casos depois é o
// tipo de trabalho que a doutrina (docs/01) manda não criar. Recusar antes de
// gastar não custa nada e diz o que fazer.

// Preço do gpt-4o, US$ por MILHÃO de tokens (platform.openai.com/pricing).
// ⚠️ Preço de terceiro muda sem avisar e este arquivo não tem como saber. Se a
// conta divergir do que `custoDaChamada` reporta, é AQUI que se corrige — e o
// sintoma é o orçamento parecer folgado enquanto a fatura não é.
export const PRECO_USD_POR_MILHAO = {
  'gpt-4o': { entrada: 2.5, entrada_cache: 1.25, saida: 10.0 },
  'gpt-4o-mini': { entrada: 0.15, entrada_cache: 0.075, saida: 0.6 },
};

// Teto por execução completa (pedido do dono). Menor que o teto da OpenAI de
// propósito — ver o comentário do topo.
export const TETO_EXECUCAO_USD = 3;

// Custo estimado de UM documento, usado só para decidir se o lote cabe antes de
// existir qualquer medição.
//
// De onde sai o número (docs/CUSTO_OPENAI.md): ~1k tokens de entrada por página,
// documento típico de ~10 páginas + ~2,5k do prompt de sistema ≈ 12,5k de
// entrada = US$ 0,031; saída de extração densa até MAX_OUTPUT_TOKENS/2 ≈ 8k =
// US$ 0,08. Soma ≈ US$ 0,11 — e fica em 0,15 para o estimador errar para o lado
// SEGURO (barrar um lote que caberia é um aviso; deixar passar um que não cabe é
// o v31 de novo).
//
// É estimativa declarada, não medição. `custoDaChamada` mede o real a partir do
// `usage` que a própria OpenAI devolve, e o valor medido aparece na execução do
// n8n — é com ele que este número deve ser recalibrado depois do próximo lote.
export const CUSTO_ESTIMADO_DOC_USD = 0.15;

// Custo REAL de uma chamada, a partir do bloco `usage` da resposta da OpenAI.
// Não estima nada: se o `usage` não vier, devolve null em vez de chutar — um
// custo inventado num relatório de custo é pior que um campo vazio.
export function custoDaChamada(usage, modelo) {
  const p = PRECO_USD_POR_MILHAO[modelo];
  if (!p || !usage) return null;
  const entradaTotal = Number(usage.prompt_tokens ?? usage.input_tokens ?? 0);
  const saida = Number(usage.completion_tokens ?? usage.output_tokens ?? 0);
  if (!Number.isFinite(entradaTotal) || !Number.isFinite(saida)) return null;
  // Tokens em cache custam metade (o prompt de sistema é o mesmo em toda
  // chamada, então o cache pega — ignorar isso superestimaria em ~40%).
  const cache = Number(usage.prompt_tokens_details?.cached_tokens ?? 0);
  const entradaCheia = Math.max(0, entradaTotal - cache);
  const usd =
    (entradaCheia * p.entrada + cache * p.entrada_cache + saida * p.saida) / 1_000_000;
  return Number(usd.toFixed(6));
}

// A decisão de orçamento do lote. Pura de propósito: é o que permite testá-la
// sem n8n e sem gastar um centavo.
//
// `chamadasPorDocumento` existe porque um documento mal nomeado paga o PDF DUAS
// vezes (classificação por conteúdo + extração — docs/CUSTO_OPENAI.md, medido no
// v31: 8 dos 14). O orçamento tem de contar o custo que o lote REALMENTE tem, não
// o do caso bem nomeado.
export function orcamentoDoLote({
  documentos,
  chamadasPorDocumento = 1,
  teto = TETO_EXECUCAO_USD,
  custoPorChamada = CUSTO_ESTIMADO_DOC_USD,
}) {
  const n = Number(documentos) || 0;
  // Arredonda para CIMA: meia chamada não existe, e a metade que sobra é gasto.
  const chamadas = Math.ceil(n * Math.max(1, chamadasPorDocumento));
  const estimadoUSD = Number((chamadas * custoPorChamada).toFixed(2));
  const maxDocumentos = Math.max(0, Math.floor(teto / (custoPorChamada * Math.max(1, chamadasPorDocumento))));
  const cabe = estimadoUSD <= teto;

  // A mensagem é metade do valor desta função: ela é o que o dono lê quando o
  // lote é recusado, e tem de dizer o que FAZER — não só que deu errado.
  const mensagem = cabe
    ? null
    : `Lote recusado ANTES de gastar: ${n} documento(s) = ${chamadas} chamada(s) à OpenAI ` +
      `≈ US$ ${estimadoUSD.toFixed(2)}, acima do teto de US$ ${teto.toFixed(2)} por execução. ` +
      `Envie no máximo ${maxDocumentos} documento(s) por vez (${Math.ceil(n / Math.max(1, maxDocumentos))} levas). ` +
      `Nada foi enviado à OpenAI e nada foi gravado, então reenviar não duplica nem custa. ` +
      `Se o lote precisa rodar inteiro, o teto vive em TETO_EXECUCAO_USD (n8n/lib/custo.mjs) ` +
      `— e subir ele exige subir também o teto do projeto na OpenAI, senão a API barra no meio.`;

  return { cabe, estimadoUSD, maxDocumentos, teto, chamadas, mensagem };
}
