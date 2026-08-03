// Mede o auto-aceite do dial contra um gabarito.
//
//   ./portal/node_modules/.bin/tsx portal/scripts/medir-auto-aceite.mts
//   … --extracao=/caminho/extracao.json --limiar=0.9 --nivel=N2
//
// O QUE ESTE SCRIPT RESPONDE. O dial de `extracao_linhas_financeiras` está em N2:
// toda linha com confiança >= `limiar_auto_clear` vira FATO sem passar por humano
// (0019, declarado no dial pela 0041). A pergunta que ninguém tinha como responder
// era: dessas linhas, quantas estão certas — e quantas ninguém consegue conferir?
//
// O QUE ELE NÃO RESPONDE, E É O MAIS IMPORTANTE DAQUI. Rodado no default (o
// fixture `book-vertentes.json`), o número de concordância é ~100% POR
// CONSTRUÇÃO: aquele fixture é a transcrição fiel do book feita à mão, não a saída
// da IA. Nesse modo, o script está medindo o próprio instrumento — que os pares
// conferíveis são encontrados e comparados corretamente —, NÃO a autonomia do
// modelo. Para medir autonomia, é preciso apontar `--extracao` para a saída de uma
// extração AO VIVO sobre os PDFs do book (ação do dono, CLAUDE.md).
//
// E mesmo assim o número é PISO, não equivalente de golden set: o book é o melhor
// caso possível — PDF gerado por reportlab, texto limpo, layout conhecido, sem
// scan, sem carimbo, sem coluna torta. Documento real de cliente é o outro extremo,
// e `docs/01` exige concordância medida no estrato que vai para produção antes de
// tratar N2 como autonomia medida. O golden set físico é o §7.4 #8 do Onboarding e
// não existe ainda.
//
// A MÉTRICA QUE MAIS IMPORTA não é a concordância: é a COBERTURA. Linha
// auto-aceita que nenhum gabarito consegue conferir virou fato sem que ninguém —
// humano ou teste — tenha olhado. Esse é o número a encarar.

import { readFileSync } from "node:fs";

type Campo = {
  documento_versao_id: string;
  chave: string;
  valor_num: number | null;
  periodo_coluna: string | null;
  entidade_coluna: string | null;
  confianca: number | null;
};
type Documento = {
  tipo_taxonomia: string;
  entidade?: { razao_social?: string } | null;
  documento_versao?: Array<{ id: string }> | null;
};
type Gabarito = {
  entidades: Record<string, string>;
  balanco_por_entidade: Record<string, Record<string, Record<string, number>>>;
  dre_metalurgica_2025: Record<string, number>;
  faturamento_total: Record<string, number>;
};

const arg = (nome: string) =>
  process.argv.slice(2).find((a) => a.startsWith(`--${nome}=`))?.split("=")[1];

const caminhoExtracao = arg("extracao")
  ?? new URL("./fixtures/book-vertentes.json", import.meta.url).pathname;
// O dial REAL vive no banco: `select fn_dial('extracao_linhas_financeiras')`. Aqui
// ele entra por parâmetro de propósito — o script mede o efeito de UM dial, e
// medir dois cenários ("e se o limiar fosse 0.99?") é o uso principal.
const limiar = Number(arg("limiar") ?? 0.95);
const nivel = arg("nivel") ?? "N2";
const eDoFixture = !arg("extracao");

const extracao = JSON.parse(readFileSync(caminhoExtracao, "utf8")) as {
  documentos: Documento[];
  campos: Campo[];
};
const gab = JSON.parse(
  readFileSync(new URL("../../test-data/book-vertentes/pdf/GABARITO.json", import.meta.url), "utf8"),
) as Gabarito;

// -----------------------------------------------------------------------------
// Quem é conferível, e contra o quê
// -----------------------------------------------------------------------------
const norm = (s: string) =>
  s.normalize("NFD").replace(/[\u0300-\u036f]/g, "").toLowerCase().replace(/\s+/g, " ").trim();

// Rótulo do balanço → sigla do gabarito. A lista é EXAUSTIVA de propósito: rótulo
// que não está aqui conta como NÃO CONFERÍVEL, e é isso que a métrica de cobertura
// precisa enxergar. Adivinhar por semelhança inflaria a cobertura com pares que
// ninguém verificou.
const SIGLA_BALANCO: Record<string, string> = {
  "ativo": "ATIVO",
  "total do ativo": "ATIVO",
  "ativo circulante": "AC",
  "total do ativo circulante": "AC",
  "ativo nao circulante": "ANC",
  "total do ativo nao circulante": "ANC",
  "passivo circulante": "PC",
  "total do passivo circulante": "PC",
  "passivo nao circulante": "PNC",
  "total do passivo nao circulante": "PNC",
  "patrimonio liquido": "PL",
  "total do patrimonio liquido": "PL",
};

// Razão social → chave do gabarito ("metalurgica", "holding", …).
const chaveDaEntidade = new Map<string, string>();
for (const [chave, razao] of Object.entries(gab.entidades)) chaveDaEntidade.set(norm(razao), chave);

const docPorVersao = new Map<string, Documento>();
for (const d of extracao.documentos) {
  for (const v of d.documento_versao ?? []) docPorVersao.set(v.id, d);
}

const anoDe = (periodo: string | null) => {
  if (!periodo) return null;
  const m = periodo.match(/(20\d{2})/);
  if (m) return m[1];
  // "24"/"25" abreviados aparecem em coluna de balanço comparativo.
  const m2 = periodo.match(/\b(\d{2})\b/);
  return m2 ? `20${m2[1]}` : null;
};

/** Valor que o gabarito afirma para este campo, ou null se ele não afirma nada. */
function esperadoDoGabarito(c: Campo): number | null {
  const doc = docPorVersao.get(c.documento_versao_id);
  if (!doc || c.valor_num === null) return null;
  const ano = anoDe(c.periodo_coluna);

  if (doc.tipo_taxonomia === "BALANCO") {
    const sigla = SIGLA_BALANCO[norm(c.chave)];
    // A coluna de entidade tem precedência sobre a entidade do documento: num
    // combinado, é a coluna que diz de quem é o número.
    const razao = c.entidade_coluna ?? doc.entidade?.razao_social ?? "";
    const chave = chaveDaEntidade.get(norm(razao));
    if (!sigla || !chave || !ano) return null;
    return gab.balanco_por_entidade[ano]?.[chave]?.[sigla] ?? null;
  }

  if (doc.tipo_taxonomia === "DRE" && ano === "2025") {
    const razao = doc.entidade?.razao_social ?? "";
    if (chaveDaEntidade.get(norm(razao)) !== "metalurgica") return null;
    for (const [rotulo, valor] of Object.entries(gab.dre_metalurgica_2025)) {
      if (norm(rotulo) === norm(c.chave)) return valor;
    }
    return null;
  }

  if (doc.tipo_taxonomia === "FATURAMENTO_24M") {
    // Só o TOTAL do ano é afirmado pelo gabarito; mês a mês não é.
    if (!/^total/.test(norm(c.chave))) return null;
    const anoRotulo = anoDe(c.chave) ?? ano;
    return anoRotulo ? gab.faturamento_total[anoRotulo] ?? null : null;
  }

  return null;
}

// -----------------------------------------------------------------------------
// A medição
// -----------------------------------------------------------------------------
const autoPermitido = nivel === "N2" || nivel === "N3";
const linhas = extracao.campos;

let elegiveis = 0, conferiveis = 0, concordantes = 0, semGabarito = 0;
let paraHumano = 0, conferiveisHumano = 0, concordantesHumano = 0;
const divergencias: string[] = [];

for (const c of linhas) {
  const elegivel = autoPermitido && c.confianca !== null && c.confianca >= limiar;
  const esperado = esperadoDoGabarito(c);
  // Tolerância de 1 unidade: o book é em milhares e o arredondamento do PDF é
  // legítimo. Maior que isso não é arredondamento, é erro.
  const bate = esperado !== null && c.valor_num !== null && Math.abs(c.valor_num - esperado) <= 1;

  if (elegivel) {
    elegiveis++;
    if (esperado === null) semGabarito++;
    else {
      conferiveis++;
      if (bate) concordantes++;
      else divergencias.push(`${c.chave} [${c.periodo_coluna ?? "?"}] extraído=${c.valor_num} gabarito=${esperado}`);
    }
  } else {
    paraHumano++;
    if (esperado !== null) { conferiveisHumano++; if (bate) concordantesHumano++; }
  }
}

const pct = (n: number, d: number) => (d === 0 ? "—" : `${((n / d) * 100).toFixed(1)}%`);

console.log("=== Medição do auto-aceite ===");
console.log(`extração:  ${caminhoExtracao}`);
console.log(`dial:      nível ${nivel}, limiar ${limiar}${autoPermitido ? "" : " (não auto-aceita nada)"}`);
console.log("");
console.log(`linhas na extração:            ${linhas.length}`);
console.log(`auto-aceitas pelo dial:        ${elegiveis}  (${pct(elegiveis, linhas.length)})`);
console.log(`  conferíveis contra gabarito: ${conferiveis}`);
console.log(`    concordam:                 ${concordantes}  (${pct(concordantes, conferiveis)})`);
console.log(`  SEM gabarito que confira:    ${semGabarito}  (${pct(semGabarito, elegiveis)} do auto-aceito)`);
console.log(`vão para revisão humana:       ${paraHumano}`);
console.log(`  conferíveis / concordam:     ${conferiveisHumano} / ${concordantesHumano}`);

if (divergencias.length > 0) {
  console.log("");
  console.log(`DIVERGÊNCIAS entre linha auto-aceita e gabarito (${divergencias.length}):`);
  for (const d of divergencias.slice(0, 20)) console.log(`  - ${d}`);
  if (divergencias.length > 20) console.log(`  … e ${divergencias.length - 20} outras`);
}

console.log("");
console.log("--- Como ler este número ---");
if (eDoFixture) {
  console.log(
    "ATENÇÃO: a extração medida é o FIXTURE (transcrição fiel do book, feita à mão), não a saída\n"
    + "da IA. A concordância aqui é ~100% por construção e mede o INSTRUMENTO, não a autonomia.\n"
    + "Para medir autonomia: rodar a extração ao vivo sobre test-data/book-vertentes/pdf/ e passar\n"
    + "o resultado em --extracao (ação do dono — chamada de IA custa orçamento).",
  );
}
console.log(
  `A cobertura é a métrica que decide: ${semGabarito} linha(s) auto-aceita(s) não têm gabarito que as\n`
  + "confira. Elas viraram fato sem que humano ou teste tenha olhado — é o tamanho real da aposta\n"
  + "que o dial em N2 faz. Reduzir esse número exige gabarito mais fino (golden set físico, §7.4 #8),\n"
  + "não limiar mais alto.",
);
console.log(
  "E o book é MELHOR CASO: PDF gerado, texto limpo, layout conhecido. docs/01 exige concordância\n"
  + "medida no estrato que vai para produção (documento real, escaneado, carimbado) antes de tratar\n"
  + "este N2 como autonomia MEDIDA em vez de declarada.",
);
