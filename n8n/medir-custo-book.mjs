// Quanto CUSTA rodar um book inteiro — medido no artefato, sem gastar um centavo.
//
// POR QUE ESTE SCRIPT EXISTE. O teto de gasto (`lib/custo.mjs`) decide com UM
// número: US$ 0,15 por chamada, declarado como estimativa. Esse número nunca foi
// confrontado com documento nenhum — ele saiu de uma conta de guardanapo em
// `docs/CUSTO_OPENAI.md` ("~10 páginas, ~1k tokens por página"). Um book de 38
// documentos com 49 páginas é a primeira oportunidade de perguntar: a estimativa
// erra para o lado SEGURO em cada documento, ou existe documento que custa mais
// do que ela admite? Se existir, o teto de US$ 3 mente — e mente para o lado
// perigoso, que é o de deixar o lote começar e morrer no meio (o incidente v31).
//
// O que ele NÃO faz: chamar a OpenAI. Tudo aqui é aritmética sobre (a) o que o
// gerador mediu no PDF (`pdf/METRICAS.json`: páginas, caracteres, linhas com
// número) e (b) o preço e as funções que rodam em produção — o mesmo
// `classifyByFilename` que decide se o documento paga o PDF duas vezes, o mesmo
// `custoDaChamada` que converte tokens em dólares, o mesmo `orcamentoDoLote` que
// aceita ou recusa o lote.
//
//   node n8n/medir-custo-book.mjs                       # book-canastra
//   node n8n/medir-custo-book.mjs test-data/book-vertentes/pdf
//   node n8n/medir-custo-book.mjs --json                # saída para script
//
// Sai com código 1 quando um INVARIANTE quebra (documento acima da estimativa,
// ou lote sem métricas), não quando o lote é grande: lote grande é resultado,
// não erro.

import { readFileSync, existsSync } from 'node:fs';
import { resolve, dirname, basename } from 'node:path';
import { fileURLToPath } from 'node:url';

import { classifyByFilename } from './lib/classifier.mjs';
import {
  custoDaChamada,
  orcamentoDoLote,
  CUSTO_ESTIMADO_DOC_USD,
  TETO_EXECUCAO_USD,
  // Os modelos vêm da FONTE, não de um espelho. Eles eram duas constantes
  // copiadas à mão aqui com o comentário "espelho de build-workflow.mjs" — e um
  // espelho de preço é a última coisa que se quer manter à mão num script cujo
  // propósito é medir preço.
  MODELO_CLASSIFICACAO,
  MODELO_EXTRACAO,
} from './lib/custo.mjs';
import { SYSTEM_PROMPT, MAX_OUTPUT_TOKENS } from './lib/extract.mjs';

const RAIZ = resolve(dirname(fileURLToPath(import.meta.url)), '..');

// ---------------------------------------------------------------------------
// As três conversões que transformam um PDF em tokens. Cada uma tem fonte
// declarada, porque estimativa sem procedência é chute com casas decimais.
// ---------------------------------------------------------------------------

// 1) Prompt de sistema: o texto REAL, não um número lembrado. ~4 caracteres por
//    token é a razão média do tokenizador do gpt-4o em português.
const CARACTERES_POR_TOKEN = 4;
const TOKENS_PROMPT_SISTEMA = Math.ceil(SYSTEM_PROMPT.length / CARACTERES_POR_TOKEN);

// 2) O PDF como IMAGEM (é o que o pipeline faz hoje): ~1.000 tokens por página
//    — docs/CUSTO_OPENAI.md, "cada página vira tokens de imagem".
const TOKENS_POR_PAGINA_IMAGEM = 1000;

// 3) A saída, e este é o número que dominava a conta.
//
//    RECALIBRADO DE 35 PARA 64 EM 13/08/2026, PELA PRIMEIRA FATURA REAL. O dono
//    rodou os 14 documentos do book-vertentes (1.180 linhas com número) e pagou
//    **US$ 0,90**; descontada a entrada (~US$ 0,14 de PDF + prompt cacheado),
//    sobram ~US$ 0,76 de saída = ~76.000 tokens = **64 por linha**. O 35 antigo
//    contava só a carga útil (rótulo + valor + confiança) e ignorava o CONTEXTO
//    repetido em cada linha (s/sc/ec/pc/op) e os próprios nomes das chaves.
//
//    Errar 45% para BAIXO aqui não é detalhe: era o número que dizia "o book
//    custa US$ 1,41" quando ele custava mais de 2 — e estimativa que erra para
//    baixo é a que deixa o lote começar e morrer no meio (o incidente v31).
const TOKENS_POR_LINHA_PLANO = 64;

// E o formato que roda HOJE: uma seção por grupo, as colunas declaradas uma vez,
// e a conta escrita uma vez com um valor por coluna. Os três números saem da
// mesma medição de caracteres do formato real (JSON.stringify / 4):
//   • cabeçalho do grupo (s + sc + op + cols + a sintaxe): ~30
//   • conta (rótulo + confiança + sintaxe), sem nenhum valor: ~26
//   • cada valor da conta (um vt + um vn): ~9
const TOKENS_CABECALHO_GRUPO = 30;
const TOKENS_CONTA_BASE = 26;
const TOKENS_POR_VALOR = 9;

// Quantas contas cabem num grupo, em média. Não é medido no PDF (o gerador não
// marca seções): é a razão observada nos books — um balanço tem ~8 seções e
// ~50 contas por coluna, e cada subtotal abre grupo próprio. Declarado como
// suposição porque ele só afeta o custo do CABEÇALHO, que é ~5% da saída.
const CONTAS_POR_GRUPO = 8;

// Colunas de valor do documento, LIDAS DO NOME do arquivo pela mesma
// `classifyByFilename` da produção: "2025x2024x2023" são três colunas de
// período, "12M25" é uma. O limite fica declarado: colunas de EMPRESA (o balanço
// combinado tem sete) não aparecem no nome, então este medidor SUBESTIMA a
// economia justamente nos documentos onde ela é maior.
function colunasDoDocumento(c) {
  const ref = c?.periodo?.referencia;
  if (typeof ref !== 'string') return 1;
  const partes = ref.split(',').filter(Boolean);
  return partes.length > 1 ? partes.length : 1;
}

function tokensDeSaida(linhas, colunas) {
  const contas = Math.max(1, Math.ceil(linhas / colunas));
  const grupos = Math.max(1, Math.ceil(contas / CONTAS_POR_GRUPO));
  return grupos * TOKENS_CABECALHO_GRUPO + contas * (TOKENS_CONTA_BASE + colunas * TOKENS_POR_VALOR);
}

// A chamada de classificação por conteúdo manda o MESMO PDF e devolve um objeto
// minúsculo (tipo, entidade, período, confiança).
const TOKENS_SAIDA_CLASSIFICACAO = 120;

function medirDocumento(m) {
  const c = classifyByFilename(m.arquivo);
  const entradaPdf = m.paginas * TOKENS_POR_PAGINA_IMAGEM;
  const colunas = colunasDoDocumento(c);
  const saida = tokensDeSaida(m.linhas_com_numero, colunas);
  const saidaPlana = m.linhas_com_numero * TOKENS_POR_LINHA_PLANO;

  const extracao = custoDaChamada({
    prompt_tokens: TOKENS_PROMPT_SISTEMA + entradaPdf,
    completion_tokens: saida,
    // O prompt de sistema é idêntico em toda chamada e vem primeiro — é a
    // condição exata do cache de prefixo da OpenAI, e ignorá-lo superestimaria.
    prompt_tokens_details: { cached_tokens: TOKENS_PROMPT_SISTEMA },
  }, MODELO_EXTRACAO);

  // O que o MESMO documento custava no formato plano, para a economia do
  // agrupamento ser um número medido e não uma promessa.
  const extracaoPlana = custoDaChamada({
    prompt_tokens: TOKENS_PROMPT_SISTEMA + entradaPdf,
    completion_tokens: saidaPlana,
    prompt_tokens_details: { cached_tokens: TOKENS_PROMPT_SISTEMA },
  }, MODELO_EXTRACAO);

  const classificacao = c.precisa_fallback_openai
    ? custoDaChamada({
      prompt_tokens: entradaPdf + 400,
      completion_tokens: TOKENS_SAIDA_CLASSIFICACAO,
    }, MODELO_CLASSIFICACAO)
    : 0;

  // O que o mesmo documento custaria se o PDF fosse enviado como TEXTO (a
  // alavanca nº 1 de docs/CUSTO_OPENAI.md). Só medida, nunca aplicada aqui.
  const entradaTexto = Math.ceil(m.caracteres / CARACTERES_POR_TOKEN);
  const comoTexto = custoDaChamada({
    prompt_tokens: TOKENS_PROMPT_SISTEMA + entradaTexto,
    completion_tokens: saida,
    prompt_tokens_details: { cached_tokens: TOKENS_PROMPT_SISTEMA },
  }, MODELO_EXTRACAO);

  return {
    arquivo: m.arquivo,
    tipo: c.tipo_taxonomia,
    periodo: c.periodo ? `${c.periodo.tipo} ${c.periodo.referencia}` : null,
    confianca: c.confianca,
    chamadas: c.precisa_fallback_openai ? 2 : 1,
    paginas: m.paginas,
    linhas: m.linhas_com_numero,
    colunas,
    tokens_entrada: TOKENS_PROMPT_SISTEMA + entradaPdf,
    tokens_saida: saida,
    tokens_saida_plano: saidaPlana,
    usd_extracao: extracao,
    usd_classificacao: classificacao,
    usd: Number((extracao + classificacao).toFixed(6)),
    usd_no_formato_plano: Number((extracaoPlana + classificacao).toFixed(6)),
    usd_se_pdf_fosse_texto: Number((comoTexto + classificacao).toFixed(6)),
  };
}

function usd(v) {
  return `US$ ${v.toFixed(4)}`;
}

// ---------------------------------------------------------------------------
const args = process.argv.slice(2);
const comoJson = args.includes('--json');
const dir = resolve(RAIZ, args.find((a) => !a.startsWith('--')) ?? 'test-data/book-canastra/pdf');
const caminhoMetricas = resolve(dir, 'METRICAS.json');

if (!existsSync(caminhoMetricas)) {
  console.error(
    `Não achei ${caminhoMetricas}.\n` +
    'O book precisa ser gerado antes — ele é que mede páginas e linhas de cada PDF:\n' +
    `  cd ${basename(dirname(caminhoMetricas)) === 'pdf' ? dirname(dir) : dir} && PYTHONPATH=. python3 gerar.py`);
  process.exit(1);
}

const { livro, documentos } = JSON.parse(readFileSync(caminhoMetricas, 'utf8'));
const medidos = documentos.map(medirDocumento);

const totalUSD = Number(medidos.reduce((s, d) => s + d.usd, 0).toFixed(4));
const totalTexto = Number(medidos.reduce((s, d) => s + d.usd_se_pdf_fosse_texto, 0).toFixed(4));
const chamadas = medidos.reduce((s, d) => s + d.chamadas, 0);
const totalPlano = Number(medidos.reduce((s, d) => s + d.usd_no_formato_plano, 0).toFixed(4));
const totalSaida = medidos.reduce((s, d) => s + d.tokens_saida, 0);
const totalSaidaPlano = medidos.reduce((s, d) => s + d.tokens_saida_plano, 0);
const maisPesado = medidos.reduce((a, b) => (b.tokens_saida > a.tokens_saida ? b : a));
const dobrados = medidos.filter((d) => d.chamadas === 2);
const semTipo = medidos.filter((d) => !d.tipo);

// O VEREDITO, pela função que roda em produção. `chamadasPorDocumento` não é
// suposição: é a média medida sobre os nomes de arquivo REAIS deste book.
//
// E os BYTES vão junto, que é o que faz este veredito ser o mesmo da produção.
// Sem eles o script caía na estimativa plana e imprimia "RECUSA" para um lote
// que o `Orcamento do Lote` ACEITA desde a sessão 42 — um medidor que mente
// sobre a máquina que ele mede é pior que nenhum, e foi ele que sustentou parte
// da confusão de 12/08.
const bytesDoLote = documentos.reduce((s, d) => s + (Number(d.bytes) || 0), 0);
const veredito = orcamentoDoLote({
  documentos: medidos.length,
  chamadasPorDocumento: chamadas / medidos.length,
  bytes: bytesDoLote > 0 ? bytesDoLote : null,
});
// E o mesmo lote depois de renomear tudo para a notação de f0/03 — uma chamada
// por documento, que é a economia que o renome compra.
const vereditoRenomeado = orcamentoDoLote({
  documentos: medidos.length,
  chamadasPorDocumento: 1,
  bytes: bytesDoLote > 0 ? bytesDoLote : null,
});
// O veredito PLANO continua sendo impresso ao lado: é o que acontece quando o
// tamanho do arquivo não chega até o nó (metadado do n8n em modo filesystem,
// por exemplo), e a diferença entre os dois é a medida do que a estimativa por
// tamanho comprou.
const vereditoPlano = orcamentoDoLote({ documentos: medidos.length, chamadasPorDocumento: chamadas / medidos.length });

if (comoJson) {
  console.log(JSON.stringify({
    livro, documentos: medidos, totalUSD, totalTexto, totalPlano, totalSaida, totalSaidaPlano, chamadas, bytesDoLote,
    veredito, vereditoRenomeado, vereditoPlano,
  }, null, 2));
} else {
  console.log(`\n== custo medido do ${livro} — ${medidos.length} documentos, ` +
    `${medidos.reduce((s, d) => s + d.paginas, 0)} páginas, ` +
    `${medidos.reduce((s, d) => s + d.linhas, 0)} linhas com número\n`);
  const larg = Math.max(...medidos.map((d) => d.arquivo.length));
  console.log(`${'arquivo'.padEnd(larg)}  tipo             conf  ch  pág  linhas    US$`);
  console.log('-'.repeat(larg + 46));
  for (const d of [...medidos].sort((a, b) => b.usd - a.usd)) {
    console.log(
      `${d.arquivo.padEnd(larg)}  ${(d.tipo ?? '—').padEnd(15)}  ` +
      `${d.confianca.toFixed(2)}  ${d.chamadas === 2 ? '2×' : ' 1'}  ` +
      `${String(d.paginas).padStart(3)}  ${String(d.linhas).padStart(6)}  ${d.usd.toFixed(4)}`);
  }
  console.log('-'.repeat(larg + 46));
  console.log(`\nCusto medido do lote inteiro: ${usd(totalUSD)} em ${chamadas} chamadas.`);
  console.log(`  • ${dobrados.length} documento(s) pagam o PDF DUAS vezes ` +
    `(nome não resolve tipo+período com confiança ≥ 0,70), somando ` +
    `${usd(dobrados.reduce((s, d) => s + d.usd_classificacao, 0))} só de classificação.`);
  if (semTipo.length) {
    console.log(`  • ${semTipo.length} sem tipo nenhum pelo nome: ` +
      semTipo.map((d) => d.arquivo).join(', '));
  }
  console.log(`  • se o PDF fosse enviado como TEXTO em vez de imagem: ${usd(totalTexto)} ` +
    `(${(100 - totalTexto / totalUSD * 100).toFixed(0)}% menos) — a alavanca nº 1 de docs/CUSTO_OPENAI.md.`);
  console.log(`  • no formato PLANO (uma entrada por conta × coluna, até 13/08/2026): ${usd(totalPlano)} ` +
    `— o agrupamento cortou ${(100 - totalUSD / totalPlano * 100).toFixed(0)}% ` +
    `(${totalSaida.toLocaleString('pt-BR')} tokens de saída contra ${totalSaidaPlano.toLocaleString('pt-BR')}).`);
  console.log(`  • saída do documento mais pesado: ${maisPesado.tokens_saida.toLocaleString('pt-BR')} tokens ` +
    `(${(maisPesado.tokens_saida / MAX_OUTPUT_TOKENS * 100).toFixed(0)}% do teto de ${MAX_OUTPUT_TOKENS.toLocaleString('pt-BR')}) ` +
    `— ${maisPesado.arquivo}; no formato plano seriam ${maisPesado.tokens_saida_plano.toLocaleString('pt-BR')} ` +
    `(${(maisPesado.tokens_saida_plano / MAX_OUTPUT_TOKENS * 100).toFixed(0)}%).`);

  console.log(`\n== o veredito do orçamento ${veredito.versao} (lib/custo.mjs, teto de US$ ${TETO_EXECUCAO_USD})`);
  console.log(`  estimativa do guarda: ${(bytesDoLote / 1024).toFixed(0)} KB × US$ 10,5/MB × ` +
    `fator ${veredito.fatorCusto} (${chamadas} chamadas, a 2ª pesa ${veredito.fatorCusto === 1 ? '—' : 'pouco'}) = ` +
    `US$ ${veredito.estimadoUSD.toFixed(2)} → ${veredito.cabe ? 'CABE' : 'RECUSA'}`);
  console.log(`  sem o tamanho (plano): ${chamadas} chamada(s) × US$ ${CUSTO_ESTIMADO_DOC_USD} = ` +
    `US$ ${vereditoPlano.estimadoUSD.toFixed(2)} → ${vereditoPlano.cabe ? 'CABE' : 'RECUSA'}`);
  console.log(`  custo MEDIDO:        ${usd(totalUSD)} ` +
    `(o guarda ${veredito.estimadoUSD >= totalUSD ? 'superestima' : 'SUBESTIMA'} em ` +
    `${(Math.abs(veredito.estimadoUSD - totalUSD) / totalUSD * 100).toFixed(0)}%)`);
  if (veredito.mensagem) {
    console.log(`\n  ${veredito.mensagem.replace(/\. /g, '.\n  ')}`);
  }
  console.log(`\n  Depois de renomear tudo para a notação de f0/03 (12M25, 25x24, L36M): ` +
    `${chamadas} → ${medidos.length} chamadas, ` +
    `US$ ${vereditoRenomeado.estimadoUSD.toFixed(2)} → ` +
    `${vereditoRenomeado.cabe ? 'CABE' : `ainda RECUSA (máx. ${vereditoRenomeado.maxDocumentos} por leva)`}`);
}

// ---------------------------------------------------------------------------
// OS INVARIANTES. São eles que fazem deste script um controle e não um relatório.
// ---------------------------------------------------------------------------
const falhas = [];

// 1. Nenhum documento pode custar mais que a estimativa por chamada do guarda.
//    Se custar, o teto de US$ 3 está calibrado com um número que não cobre o
//    documento mais caro do lote, e a recusa vai acontecer NA API, no meio.
for (const d of medidos) {
  const porChamada = d.usd / d.chamadas;
  if (porChamada > CUSTO_ESTIMADO_DOC_USD) {
    falhas.push(
      `${d.arquivo}: ${usd(porChamada)} por chamada, acima da estimativa de ` +
      `US$ ${CUSTO_ESTIMADO_DOC_USD} que sustenta o teto (${d.paginas} páginas, ${d.linhas} linhas)`);
  }
}

// 2. Métrica faltando é medição inválida, não "custo zero".
for (const d of medidos) {
  if (!(d.usd > 0) || !(d.paginas > 0)) {
    falhas.push(`${d.arquivo}: métrica ausente ou zerada (páginas=${d.paginas}, US$=${d.usd})`);
  }
}

// 3. TRUNCAMENTO: a saída de um documento não cabe no teto de tokens do modelo.
//    Isto NÃO derruba o script, e a escolha é deliberada — não existe correção
//    disponível nesta fatia (16.384 é o teto de saída do gpt-4o, não uma
//    configuração nossa; a saída é dividir o documento em faixas de página, que
//    é mudança de topologia). Mas também não pode ficar em silêncio: é a
//    família de defeito do "teste v18", em que 6 de 16 documentos voltaram com o
//    JSON cortado. Aparece nomeado, com o número, em toda execução do CI.
const arriscados = medidos
  .filter((d) => d.tokens_saida > MAX_OUTPUT_TOKENS * 0.8)
  .sort((a, b) => b.tokens_saida - a.tokens_saida);
if (arriscados.length && !comoJson) {
  console.log(`\nATENÇÃO — ${arriscados.length} documento(s) perto ou acima do teto de saída ` +
    `de ${MAX_OUTPUT_TOKENS.toLocaleString('pt-BR')} tokens. Acima de 100% a resposta vem truncada ` +
    `(finish_reason=length): abre pendência, não perde em silêncio, mas o documento fica sem parte ` +
    `dos dados. A saída é extrair por faixa de página — fatia própria, não feita.`);
  for (const d of arriscados) {
    console.log(`  • ${d.arquivo}: ${d.tokens_saida.toLocaleString('pt-BR')} tokens ` +
      `(${(d.tokens_saida / MAX_OUTPUT_TOKENS * 100).toFixed(0)}% do teto) — ` +
      `${d.linhas} células de valor em ${d.colunas} coluna(s)`);
  }
}

if (falhas.length) {
  console.error(`\nFALHOU — ${falhas.length} invariante(s) de custo:`);
  for (const f of falhas) console.error(`  • ${f}`);
  process.exit(1);
}
if (!comoJson) console.log('\nok — os invariantes de custo passaram.\n');
