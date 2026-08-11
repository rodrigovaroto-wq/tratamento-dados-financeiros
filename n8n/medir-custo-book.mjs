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
} from './lib/custo.mjs';
import { SYSTEM_PROMPT } from './lib/extract.mjs';

const RAIZ = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const MODELO_CLASSIFICACAO = 'gpt-4o'; // espelho de build-workflow.mjs
const MODELO_EXTRACAO = 'gpt-4o';

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

// 3) A saída: cada linha financeira extraída devolve um objeto com nove chaves
//    curtas (s/sc/ec/pc/k/vt/vn/op/cf). Medido sobre o formato real: ~35 tokens
//    por linha, incluindo pontuação do JSON.
const TOKENS_POR_LINHA_EXTRAIDA = 35;

// A chamada de classificação por conteúdo manda o MESMO PDF e devolve um objeto
// minúsculo (tipo, entidade, período, confiança).
const TOKENS_SAIDA_CLASSIFICACAO = 120;

function medirDocumento(m) {
  const c = classifyByFilename(m.arquivo);
  const entradaPdf = m.paginas * TOKENS_POR_PAGINA_IMAGEM;

  const extracao = custoDaChamada({
    prompt_tokens: TOKENS_PROMPT_SISTEMA + entradaPdf,
    completion_tokens: m.linhas_com_numero * TOKENS_POR_LINHA_EXTRAIDA,
    // O prompt de sistema é idêntico em toda chamada e vem primeiro — é a
    // condição exata do cache de prefixo da OpenAI, e ignorá-lo superestimaria.
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
    completion_tokens: m.linhas_com_numero * TOKENS_POR_LINHA_EXTRAIDA,
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
    tokens_entrada: TOKENS_PROMPT_SISTEMA + entradaPdf,
    tokens_saida: m.linhas_com_numero * TOKENS_POR_LINHA_EXTRAIDA,
    usd_extracao: extracao,
    usd_classificacao: classificacao,
    usd: Number((extracao + classificacao).toFixed(6)),
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
const dobrados = medidos.filter((d) => d.chamadas === 2);
const semTipo = medidos.filter((d) => !d.tipo);

// O VEREDITO, pela função que roda em produção. `chamadasPorDocumento` não é
// suposição: é a média medida sobre os nomes de arquivo REAIS deste book.
const veredito = orcamentoDoLote({ documentos: medidos.length, chamadasPorDocumento: chamadas / medidos.length });
// E o mesmo lote depois de renomear tudo para a notação de f0/03 — uma chamada
// por documento, que é a economia que o renome compra.
const vereditoRenomeado = orcamentoDoLote({ documentos: medidos.length, chamadasPorDocumento: 1 });

if (comoJson) {
  console.log(JSON.stringify({
    livro, documentos: medidos, totalUSD, totalTexto, chamadas, veredito, vereditoRenomeado,
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

  console.log(`\n== o veredito do orçamento (lib/custo.mjs, teto de US$ ${TETO_EXECUCAO_USD})`);
  console.log(`  estimativa do guarda: ${chamadas} chamada(s) × US$ ${CUSTO_ESTIMADO_DOC_USD} = ` +
    `US$ ${veredito.estimadoUSD.toFixed(2)} → ${veredito.cabe ? 'CABE' : 'RECUSA'}`);
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

if (falhas.length) {
  console.error(`\nFALHOU — ${falhas.length} invariante(s) de custo:`);
  for (const f of falhas) console.error(`  • ${f}`);
  process.exit(1);
}
if (!comoJson) console.log('\nok — os invariantes de custo passaram.\n');
