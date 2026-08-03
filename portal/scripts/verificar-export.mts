/**
 * Verificação do export (roda com `npx tsx scripts/verificar-export.mts`).
 *
 * O portal não tem runner de teste; este script cobre os invariantes do export
 * que já quebraram com dado real, para não regredirem:
 *
 *  1. SUBTOTAL DE SUBSEÇÃO NÃO ENTRA NA SOMA. Demonstração real é hierárquica
 *     ("Ativo Circulante" > "Estoques" > contas), e cada agrupamento traz o
 *     próprio subtotal impresso. Somar o subtotal junto com os componentes
 *     dobrava todos os totais (teste v24: 137.865 contra 67.878 informados),
 *     contaminando AV% e todos os indicadores.
 *  2. CONTA SEM VOCABULÁRIO CONHECIDO HERDA A SEÇÃO DOS IRMÃOS. A `secao` que a
 *     IA anota costuma ser o nome da SUBSEÇÃO, que não diz Ativo ou Passivo.
 *  3. PARES AMBÍGUOS vão para o lado certo do balanço ("Adiantamentos de
 *     clientes" é obrigação, não crédito).
 *  4. PERÍODOS EM ORDEM CRONOLÓGICA (o Δ% precisa casar meses que se sucedem).
 *  5. COLUNA DE AJUSTE/TOTAL do combinado não é tratada como entidade.
 *  9. NOSSO NÚMERO == O NÚMERO DO DOCUMENTO na DRE e no Fluxo de Caixa: cada
 *     linha de resultado (Receita Líquida, Lucro Bruto, EBIT, LAIR, Prejuízo,
 *     Caixa Líquido de cada atividade) tem de bater com o "↳ total informado no
 *     documento" logo abaixo, em toda coluna. Foi o que pegou a cascata da DRE
 *     fechando em -27.550 onde o documento diz -17.901: duas contas de Despesas
 *     Operacionais estavam fora da seção e uma conta residual estava sendo
 *     tratada como a linha de Receita Líquida.
 *  8. NENHUMA LINHA 100% VAZIA, em nenhuma aba. O template canônico (CPC 26 /
 *     art. 178, cascata da DRE, CPC 03) serve para ORDENAR o que o documento
 *     trouxe — não para impor linhas que ele não tem. Linha sem valor em coluna
 *     nenhuma parece defeito para quem abre a planilha, e escondia o sinal que
 *     importa. Zero conta como valor: se o documento diz 0,00, isso é dado.
 *  6. O TOTAL DA SEÇÃO É O QUE O DOCUMENTO INFORMOU, não a nossa soma. Este é o
 *     invariante que faltava aqui e por isso o teste v25 passou verde enquanto
 *     36 de 44 somas do Balanço divergiam. Dois casos que a detecção estrutural
 *     de subtotal NÃO cobre, e que aparecem em arquivo real:
 *       (a) a IA anota em `secao` a seção de TOPO ("Ativo Circulante") em vez da
 *           subseção — então "Disponível" não é reconhecível como subtotal;
 *       (b) o mesmo rótulo é subtotal num documento e conta-folha em outro
 *           (a Metalúrgica detalha "Disponível"; a Componentes usa como conta),
 *           e o export junta os dois na mesma linha.
 *     Em ambos, o número da seção tem de seguir o total informado, e a nossa
 *     soma tem de ficar visível numa linha de checagem — nunca virar o total.
 */
import { readFileSync } from "node:fs";
import { avaliarCelula, esquecerMemoria, linhaVazia } from "./lib/avaliar-formula.mts";
import { buildExportWorkbook, chaveCronologicaPeriodo, consolidarNomesDeEntidade, tipoColunaNaoEntidade, type DocumentoParaExport } from "../src/lib/export";
import type { CampoExtraido } from "../src/lib/types";
import { classificarConta } from "../src/lib/statement-templates.ts";

let ok = 0;
const falhas: string[] = [];
function checar(cond: boolean, desc: string, detalhe = "") {
  if (cond) ok++;
  else falhas.push(`${desc}${detalhe ? ` — ${detalhe}` : ""}`);
}

// Avalia a célula resolvendo as fórmulas do export (SUM/refs/aritmética/IFERROR)
// — ver scripts/lib/avaliar-formula.mts.
function avaliar(ws: import("exceljs").Worksheet, col: string, row: number): number {
  const v = avaliarCelula(ws, col, row);
  return typeof v === "number" ? v : 0;
}

// No ExcelJS a nota de célula é um objeto (`{texts:[{text}]}`), não string — ler
// com String() devolve "[object Object]" e o invariante passaria a testar nada.
function notaDaLinha(ws: import("exceljs").Worksheet, row: number): string {
  const r = ws.getRow(row);
  const partes: string[] = [];
  // `includeEmpty: true` importa: a nota da média que NÃO fechou vive numa célula
  // sem valor, e com `false` o ExcelJS pula justamente ela.
  r.eachCell({ includeEmpty: true }, (cell) => {
    const n = cell.note as unknown;
    if (!n) return;
    if (typeof n === "string") partes.push(n);
    else if (typeof n === "object" && Array.isArray((n as { texts?: Array<{ text?: string }> }).texts)) {
      partes.push((n as { texts: Array<{ text?: string }> }).texts.map((t) => t.text ?? "").join(""));
    }
  });
  return partes.join("\n");
}

// Letra da coluna a partir do índice (1 = A). O harness comparava só texto de
// fórmula até agora, então nunca precisou disto.
function colLetraDe(idx: number): string {
  let s = "";
  let n = idx;
  while (n > 0) { const r = (n - 1) % 26; s = String.fromCharCode(65 + r) + s; n = Math.floor((n - 1) / 26); }
  return s;
}

let seq = 0;
const campo = (p: Partial<CampoExtraido> & { chave: string; documento_versao_id: string }): CampoExtraido => ({
  id: `c${seq++}`, secao: null, secao_canonica: null, entidade_coluna: null, periodo_coluna: null,
  valor_texto: null, valor_num: null, unidade: null, confianca: 0.97, origem_pagina: 1,
  status_aceite: "aceito", aceito_por: "teste", aceito_em: "2026-07-27T00:00:00Z", ...p,
} as CampoExtraido);

// ---- 1/2/3: balanço hierárquico com subtotais de subseção -------------------
{
  const V = "v1";
  const campos: CampoExtraido[] = [];
  const blocos: Array<[string, Array<[string, number]>]> = [
    ["Disponível", [["Caixa e bancos conta movimento", 1240], ["Aplicações financeiras de liquidez imediata", 3600]]],
    ["Contas a Receber", [["Duplicatas a receber - mercado interno", 27900], ["(-) PECLD", -1980]]],
    ["Estoques", [["Matérias-primas e insumos", 12400], ["Produtos em elaboração", 4300]]],
  ];
  let acTotal = 0;
  for (const [sub, contas] of blocos) {
    const soma = contas.reduce((a, [, v]) => a + v, 0);
    acTotal += soma;
    for (const [chave, v] of contas) campos.push(campo({ chave, secao: sub, valor_num: v, documento_versao_id: V }));
    campos.push(campo({ chave: sub, secao: "Ativo Circulante", valor_num: soma, documento_versao_id: V })); // subtotal
  }
  campos.push(campo({ chave: "Total do Ativo Circulante", secao: "Ativo Circulante", valor_num: acTotal, documento_versao_id: V }));
  campos.push(campo({ chave: "Fornecedores nacionais", secao: "Passivo Circulante", valor_num: acTotal, documento_versao_id: V }));
  campos.push(campo({ chave: "Adiantamentos de clientes", secao: "Outras Obrigações", valor_num: 900, documento_versao_id: V }));

  const documentos: DocumentoParaExport[] = [{
    id: "d", tipo_taxonomia: "BALANCO", entidade: { razao_social: "Alfa" },
    periodo: { tipo: "anual", referencia: "2025" }, documento_versao: [{ id: V, nome_original: "bp.pdf" }],
  }];
  const ws = buildExportWorkbook({ caso: { nome: "C", produto: "rx" }, documentos, campos, agora: new Date("2026-07-27T12:00:00Z") })
    .getWorksheet("Balanço")!;

  const linhaDe = (rot: string) => {
    for (let r = 1; r <= ws.rowCount; r++) if (String(ws.getRow(r).getCell(1).value ?? "") === rot) return r;
    return -1;
  };
  const rAC = linhaDe("Ativo Circulante");
  const soma = avaliar(ws, "B", rAC);
  checar(soma === acTotal, "(1) subtotal de subseção fora da soma", `seção=${soma} informado=${acTotal}`);
  const rotulos: string[] = [];
  for (let r = 1; r <= ws.rowCount; r++) rotulos.push(String(ws.getRow(r).getCell(1).value ?? ""));
  checar(rotulos.some((x) => x.startsWith("↳ subtotal informado:")), "(1b) subtotais continuam visíveis");
  const iNaoClass = rotulos.findIndex((x) => x.startsWith("Contas Não Classificadas"));
  const naoClass = iNaoClass < 0 ? [] : rotulos.slice(iNaoClass + 1).filter(Boolean);
  checar(naoClass.length === 0, "(2) nada em Não Classificadas (consenso de irmãos)", naoClass.join(", "));
  // A conta tem de estar DENTRO do range que a soma do Passivo Circulante cobre —
  // asserção mais precisa que "entre dois cabeçalhos", e que não depende de o
  // Passivo Não Circulante existir (seção sem dado deixou de ser emitida).
  const rAdiant = linhaDe("Adiantamentos de clientes");
  const rPC = linhaDe("Passivo Circulante");
  const fPC = String((ws.getRow(rPC).getCell(2).value as { formula?: string })?.formula ?? "");
  const mPC = fPC.match(/SUM\([A-Z]+(\d+):[A-Z]+(\d+)\)/);
  checar(
    rAdiant > 0 && mPC != null && rAdiant >= Number(mPC[1]) && rAdiant <= Number(mPC[2]),
    "(3) 'Adiantamentos de clientes' entra na soma do Passivo Circulante",
    `linha=${rAdiant} range=${mPC ? `${mPC[1]}:${mPC[2]}` : fPC}`,
  );
}

// ---- 4: ordem cronológica ---------------------------------------------------
{
  const meses = ["Out/2024", "Nov/2024", "Dez/2024", "Jan/2025"];
  const ordenado = [...meses].sort((a, b) => chaveCronologicaPeriodo(a) - chaveCronologicaPeriodo(b));
  checar(JSON.stringify(ordenado) === JSON.stringify(meses), "(4) períodos em ordem cronológica", ordenado.join(" < "));
}

// ---- 5: coluna de ajuste/total não é entidade -------------------------------
{
  checar(tipoColunaNaoEntidade("Eliminações") === "ajuste", "(5a) 'Eliminações' é ajuste");
  checar(tipoColunaNaoEntidade("Combinado") === "total", "(5b) 'Combinado' é total");
  checar(tipoColunaNaoEntidade("Vertentes Metalúrgica") === null, "(5c) empresa real não é ajuste/total");
}

// ---- 6: o total da seção segue o INFORMADO, não a nossa soma ----------------
// Reproduz o cenário do teste v25, que os invariantes anteriores não pegavam.
{
  const VA = "vA"; // Metalúrgica: detalha "Disponível" em duas contas
  const VB = "vB"; // Componentes: usa "Disponível" como conta-folha
  const campos: CampoExtraido[] = [];

  // (a) a IA anotou a SEÇÃO DE TOPO nas contas-filhas, não a subseção — então
  // "Disponível" é indetectável como subtotal por estrutura.
  const AC_A = 4840 + 8420;
  campos.push(
    campo({ chave: "Caixa e bancos conta movimento", secao: "Ativo Circulante", valor_num: 1240, documento_versao_id: VA }),
    campo({ chave: "Aplicações financeiras de liquidez imediata", secao: "Ativo Circulante", valor_num: 3600, documento_versao_id: VA }),
    campo({ chave: "Disponível", secao: "Ativo Circulante", valor_num: 4840, documento_versao_id: VA }),
    campo({ chave: "Duplicatas a receber - mercado interno", secao: "Ativo Circulante", valor_num: 8420, documento_versao_id: VA }),
    campo({ chave: "Total do Ativo Circulante", secao: "Ativo Circulante", valor_num: AC_A, documento_versao_id: VA }),
    campo({ chave: "Máquinas e equipamentos", secao: "Imobilizado", valor_num: 30000, documento_versao_id: VA }),
    campo({ chave: "Total do Ativo Não Circulante", secao: "Ativo Não Circulante", valor_num: 30000, documento_versao_id: VA }),
    campo({ chave: "TOTAL DO ATIVO", secao: "ATIVO", valor_num: AC_A + 30000, documento_versao_id: VA }),
    campo({ chave: "Fornecedores nacionais", secao: "Passivo Circulante", valor_num: AC_A + 30000, documento_versao_id: VA }),
  );
  // (b) outro documento onde "Disponível" é conta-folha de verdade.
  campos.push(
    campo({ chave: "Disponível", secao: "Ativo Circulante", valor_num: 410, documento_versao_id: VB }),
    campo({ chave: "Duplicatas a receber - mercado interno", secao: "Ativo Circulante", valor_num: 5000, documento_versao_id: VB }),
    campo({ chave: "Total do Ativo Circulante", secao: "Ativo Circulante", valor_num: 5410, documento_versao_id: VB }),
    campo({ chave: "TOTAL DO ATIVO", secao: "ATIVO", valor_num: 5410, documento_versao_id: VB }),
    campo({ chave: "Fornecedores nacionais", secao: "Passivo Circulante", valor_num: 5410, documento_versao_id: VB }),
  );

  const documentos: DocumentoParaExport[] = [
    { id: "dA", tipo_taxonomia: "BALANCO", entidade: { razao_social: "Metalúrgica" },
      periodo: { tipo: "anual", referencia: "2025" }, documento_versao: [{ id: VA, nome_original: "a.pdf" }] },
    { id: "dB", tipo_taxonomia: "BALANCO", entidade: { razao_social: "Componentes" },
      periodo: { tipo: "anual", referencia: "2025" }, documento_versao: [{ id: VB, nome_original: "b.pdf" }] },
  ];
  const ws = buildExportWorkbook({ caso: { nome: "C", produto: "rx" }, documentos, campos, agora: new Date("2026-07-27T12:00:00Z") })
    .getWorksheet("Balanço")!;
  const linhaDe = (rot: string) => {
    for (let r = 1; r <= ws.rowCount; r++) if (String(ws.getRow(r).getCell(1).value ?? "") === rot) return r;
    return -1;
  };
  // Qual coluna é qual entidade
  const hdr = ws.getRow(1);
  let colA = "", colB = "";
  for (let c = 2; c <= hdr.cellCount; c++) {
    const h = String(hdr.getCell(c).value ?? "");
    if (h.startsWith("Metalúrgica")) colA = ws.getColumn(c).letter;
    if (h.startsWith("Componentes")) colB = ws.getColumn(c).letter;
  }
  const rAC = linhaDe("Ativo Circulante");
  const rATIVO = linhaDe("ATIVO");
  checar(avaliar(ws, colA, rAC) === AC_A,
    "(6a) subtotal indetectável por `secao`: seção segue o total informado",
    `seção=${avaliar(ws, colA, rAC)} informado=${AC_A}`);
  checar(avaliar(ws, colB, rAC) === 5410,
    "(6b) mesmo rótulo como conta-folha no outro documento não é perdido",
    `seção=${avaliar(ws, colB, rAC)} informado=5410`);
  checar(avaliar(ws, colA, rATIVO) === AC_A + 30000,
    "(6c) total do grupo ATIVO segue o TOTAL DO ATIVO informado",
    `ATIVO=${avaliar(ws, colA, rATIVO)} informado=${AC_A + 30000}`);
  const rotulos: string[] = [];
  for (let r = 1; r <= ws.rowCount; r++) rotulos.push(String(ws.getRow(r).getCell(1).value ?? ""));
  checar(rotulos.some((x) => x.startsWith("↳ soma das contas listadas")),
    "(6d) a nossa soma continua visível como linha de checagem");
  const rSoma = rotulos.findIndex((x, i) => i > rAC && x.startsWith("↳ soma das contas listadas")) ;
  checar(rSoma > 0 && avaliar(ws, colA, rSoma + 1) === AC_A + 4840,
    "(6e) a checagem mostra a soma inflada (sinal visível, não total silencioso)",
    `checagem=${rSoma > 0 ? avaliar(ws, colA, rSoma + 1) : "n/d"} esperado=${AC_A + 4840}`);
}

// ---- 7: END-TO-END contra o book Vertentes ---------------------------------
// Monta o export a partir do MESMO fixture que os testes de banco usam
// (db/test/gerar_fixture.py, extração fiel dos 14 documentos) e confere TODA
// seção do Balanço contra o gabarito do book. Este é o teste que faltava: os
// invariantes sintéticos passavam verde enquanto o export real do v25 tinha 36
// de 44 somas divergentes.
{
  const fixture = JSON.parse(
    readFileSync(new URL("./fixtures/book-vertentes.json", import.meta.url), "utf8"),
  ) as { documentos: DocumentoParaExport[]; campos: CampoExtraido[] };
  const gab = JSON.parse(
    readFileSync(new URL("../../test-data/book-vertentes/pdf/GABARITO.json", import.meta.url), "utf8"),
  ) as { balanco_por_entidade: Record<string, Record<string, Record<string, number>>> };

  const wb = buildExportWorkbook({
    caso: { nome: "Book Vertentes", produto: "reestruturacao" },
    documentos: fixture.documentos, campos: fixture.campos,
    agora: new Date("2026-07-27T12:00:00Z"),
  });
  const ws = wb.getWorksheet("Balanço")!;
  const linhaDe = (rot: string) => {
    for (let r = 1; r <= ws.rowCount; r++) if (String(ws.getRow(r).getCell(1).value ?? "") === rot) return r;
    return -1;
  };
  // cabeçalho: "RAZÃO SOCIAL — 31/12/2025" → coluna
  const hdr = ws.getRow(1);
  const colDe = new Map<string, string>();
  for (let c = 2; c <= hdr.cellCount; c++) {
    const h = String(hdr.getCell(c).value ?? "");
    if (h && h !== "AV%" && !h.startsWith("Δ%")) colDe.set(h, ws.getColumn(c).letter);
  }
  const RAZAO: Record<string, string> = {
    metalurgica: "VERTENTES METALÚRGICA LTDA.", componentes: "VERTENTES COMPONENTES AUTOMOTIVOS LTDA.",
    holding: "VERTENTES PARTICIPAÇÕES S.A.", logistica: "VT LOGÍSTICA E TRANSPORTES LTDA.",
    spe: "VERTENTES IMÓVEIS SPE LTDA.",
  };
  const LINHA: Record<string, number> = {
    ATIVO: linhaDe("ATIVO"), AC: linhaDe("Ativo Circulante"), ANC: linhaDe("Ativo Não Circulante"),
    PC: linhaDe("Passivo Circulante"), PNC: linhaDe("Passivo Não Circulante"), PL: linhaDe("Patrimônio Líquido"),
  };
  let conferidos = 0;
  const erros: string[] = [];
  for (const ano of ["2024", "2025"]) {
    for (const [chave, razao] of Object.entries(RAZAO)) {
      const col = colDe.get(`${razao} — ${ano}`);
      if (!col) { erros.push(`coluna ausente: ${razao} ${ano}`); continue; }
      for (const [sigla, row] of Object.entries(LINHA)) {
        const esperado = gab.balanco_por_entidade[ano][chave][sigla];
        const obtido = Math.round(avaliar(ws, col, row));
        conferidos++;
        if (obtido !== esperado) erros.push(`${razao} ${ano} ${sigla}: export=${obtido} gabarito=${esperado}`);
      }
    }
  }
  checar(erros.length === 0,
    `(7) todas as ${conferidos} seções do Balanço batem com o gabarito do book`,
    erros.slice(0, 8).join(" / "));
  // PASSIVO+PL tem de fechar com o ATIVO em toda coluna (é o balanço, afinal).
  const rPPL = linhaDe("PASSIVO E PATRIMÔNIO LÍQUIDO");
  const desbalanceados: string[] = [];
  for (const [nome, col] of colDe) {
    const a = Math.round(avaliar(ws, col, LINHA.ATIVO));
    const b = Math.round(avaliar(ws, col, rPPL));
    if (a !== b) desbalanceados.push(`${nome}: ativo=${a} passivo+pl=${b}`);
  }
  checar(desbalanceados.length === 0, "(7b) Ativo = Passivo + PL em toda coluna do export",
    desbalanceados.slice(0, 6).join(" / "));
}

// ---- 8: nenhuma linha 100% vazia, em nenhuma aba -----------------------------
{
  const fixture = JSON.parse(
    readFileSync(new URL("./fixtures/book-vertentes.json", import.meta.url), "utf8"),
  ) as { documentos: DocumentoParaExport[]; campos: CampoExtraido[] };
  const wb = buildExportWorkbook({
    caso: { nome: "Book Vertentes", produto: "reestruturacao" },
    documentos: fixture.documentos, campos: fixture.campos,
    agora: new Date("2026-07-27T12:00:00Z"),
  });
  const vazias: string[] = [];
  let rotuladas = 0;
  for (const ws of wb.worksheets) {
    // Modelagem tem invariante próprio (11, abaixo): lá as células são fórmulas
    // de modelo (IF/INDEX/MATCH/MAX) que `avaliarCelula` não resolve — e o que
    // importa naquela aba é o oposto do que se checa aqui (nenhum valor CRU
    // fora dos inputs), não a ausência de linha em branco.
    if (ws.name === "Resumo" || ws.name === "Modelagem") continue;
    for (let r = 2; r <= ws.rowCount; r++) {
      const rot = String(ws.getRow(r).getCell(1).value ?? "").trim();
      if (!rot) continue;
      rotuladas++;
      if (linhaVazia(ws, r)) vazias.push(`${ws.name}!${r} "${rot}"`);
    }
  }
  checar(vazias.length === 0,
    `(8) nenhuma das ${rotuladas} linhas do book fica 100% vazia`,
    vazias.slice(0, 10).join(" / "));

  // …e o mesmo com um documento ESPARSO: uma empresa que só tem circulante não
  // pode ganhar Realizável LP / Investimentos / Imobilizado / Intangível /
  // Passivo Não Circulante em branco (nem um "0" que nós inventamos — o
  // documento não disse zero, não disse nada).
  const V = "vEsparso";
  const camposEsparsos: CampoExtraido[] = [
    campo({ chave: "Caixa e bancos", secao: "Ativo Circulante", valor_num: 1000, documento_versao_id: V }),
    campo({ chave: "Clientes - mercado interno", secao: "Ativo Circulante", valor_num: 4000, documento_versao_id: V }),
    campo({ chave: "TOTAL DO ATIVO", secao: "ATIVO", valor_num: 5000, documento_versao_id: V }),
    campo({ chave: "Fornecedores nacionais", secao: "Passivo Circulante", valor_num: 5000, documento_versao_id: V }),
  ];
  const wsEsp = buildExportWorkbook({
    caso: { nome: "Esparso", produto: "reestruturacao" },
    documentos: [{ id: "dE", tipo_taxonomia: "BALANCO", entidade: { razao_social: "Só Circulante Ltda." },
      periodo: { tipo: "anual", referencia: "2025" }, documento_versao: [{ id: V, nome_original: "e.pdf" }] }],
    campos: camposEsparsos, agora: new Date("2026-07-27T12:00:00Z"),
  }).getWorksheet("Balanço")!;
  const vaziasEsp: string[] = [];
  const rotulos: string[] = [];
  for (let r = 2; r <= wsEsp.rowCount; r++) {
    const rot = String(wsEsp.getRow(r).getCell(1).value ?? "").trim();
    if (!rot) continue;
    rotulos.push(rot);
    if (linhaVazia(wsEsp, r)) vaziasEsp.push(`${r} "${rot}"`);
  }
  checar(vaziasEsp.length === 0, "(8b) documento esparso não ganha linha vazia", vaziasEsp.join(" / "));
  const naoDeveria = ["Realizável a Longo Prazo", "Investimentos", "Imobilizado", "Intangível",
    "Ativo Não Circulante", "Passivo Não Circulante", "Patrimônio Líquido"];
  const intrusos = naoDeveria.filter((x) => rotulos.includes(x));
  checar(intrusos.length === 0,
    "(8c) seção que o documento não tem não é emitida", intrusos.join(", "));
}

// ---- 9: DRE e Fluxo de Caixa amarram com o próprio documento ---------------
{
  const fixture = JSON.parse(
    readFileSync(new URL("./fixtures/book-vertentes.json", import.meta.url), "utf8"),
  ) as { documentos: DocumentoParaExport[]; campos: CampoExtraido[] };
  const gab = JSON.parse(
    readFileSync(new URL("../../test-data/book-vertentes/pdf/GABARITO.json", import.meta.url), "utf8"),
  ) as { dre_metalurgica_2025: Record<string, number>; receita_bruta_2025: number };
  const wb = buildExportWorkbook({
    caso: { nome: "Book Vertentes", produto: "reestruturacao" },
    documentos: fixture.documentos, campos: fixture.campos,
    agora: new Date("2026-07-27T12:00:00Z"),
  });

  for (const nomeAba of ["DRE", "Fluxo de Caixa"]) {
    const ws = wb.getWorksheet(nomeAba)!;
    const hdr = ws.getRow(1);
    const cols: string[] = [];
    for (let c = 2; c <= ws.columnCount; c++) {
      const h = String(hdr.getCell(c).value ?? "");
      if (h && h !== "AV%" && !h.startsWith("Δ%")) cols.push(ws.getColumn(c).letter);
    }
    const erros: string[] = [];
    let pares = 0;
    for (let r = 3; r <= ws.rowCount; r++) {
      if (String(ws.getRow(r).getCell(1).value ?? "").trim() !== "↳ total informado no documento") continue;
      const rotuloAcima = String(ws.getRow(r - 1).getCell(1).value ?? "").trim();
      for (const c of cols) {
        const informado = avaliarCelula(ws, c, r);
        if (typeof informado !== "number") continue;
        const nosso = avaliarCelula(ws, c, r - 1);
        pares++;
        if (typeof nosso !== "number" || Math.abs(nosso - informado) > Math.max(0.01, Math.abs(informado) * 0.001)) {
          erros.push(`${rotuloAcima} col ${c}: nosso=${nosso} informado=${informado}`);
        }
      }
    }
    checar(erros.length === 0 && pares > 0,
      `(9) ${nomeAba}: as ${pares} linhas de resultado batem com o total informado`,
      erros.slice(0, 6).join(" / "));
  }

  // E os números da DRE contra o gabarito do book, por nome de linha.
  const ws = wb.getWorksheet("DRE")!;
  const hdr = ws.getRow(1);
  let col2025 = "";
  for (let c = 2; c <= ws.columnCount; c++) {
    const h = String(hdr.getCell(c).value ?? "");
    if (h.includes("2025") && !h.startsWith("Δ%")) { col2025 = ws.getColumn(c).letter; break; }
  }
  const linhaDe = (rot: string) => {
    for (let r = 1; r <= ws.rowCount; r++) if (String(ws.getRow(r).getCell(1).value ?? "") === rot) return r;
    return -1;
  };
  const esperado: Array<[string, number]> = [
    ["Receita Líquida", gab.dre_metalurgica_2025["RECEITA OPERACIONAL LÍQUIDA"]],
    ["Lucro Bruto", gab.dre_metalurgica_2025["LUCRO BRUTO"]],
    ["Resultado Operacional (EBIT)", gab.dre_metalurgica_2025["RESULTADO OPERACIONAL ANTES DO RESULTADO FINANCEIRO"]],
    ["Resultado Antes dos Tributos", gab.dre_metalurgica_2025["RESULTADO ANTES DOS TRIBUTOS SOBRE O LUCRO"]],
    ["Lucro/Prejuízo Líquido do Exercício", gab.dre_metalurgica_2025["PREJUÍZO LÍQUIDO DO EXERCÍCIO"]],
    ["Receita Bruta e Deduções", gab.dre_metalurgica_2025["RECEITA OPERACIONAL LÍQUIDA"]],
  ];
  const errosGab = esperado
    .map(([rot, exp]) => {
      const r = linhaDe(rot);
      const got = r > 0 ? Math.round(avaliar(ws, col2025, r)) : NaN;
      return got === exp ? null : `${rot}: export=${got} gabarito=${exp}`;
    })
    .filter(Boolean) as string[];
  checar(errosGab.length === 0, "(9b) DRE 2025 bate com o gabarito linha a linha", errosGab.join(" / "));
}

// ---- 10: DMPL e DVA ganham aba própria (db/migrations/0024) -----------------
// Antes desta fatia a DMPL não tinha para onde ir: o documento inteiro era
// classificado como MUTUOS (não havia código DMPL na taxonomia, e o enum que a
// IA recebe é fechado nos códigos que existem) e, quando vinha embutida num PDF
// composto, suas linhas caíam em "Contas Não Classificadas" pela guarda
// `ehLinhaDMPL` — a alternativa era pior, porque o saldo de fechamento REPETE o
// total do PL e somá-lo INFLA o balanço (bug real do export do dono).
{
  const V = "vDMPL";
  // Números do book Vertentes (test-data/book-vertentes/render.py → pdf_dmpl):
  // matriz de 3 movimentos × 6 componentes do PL, R$ mil.
  const PL24 = 24801, PL25 = 6900, PREJ = PL25 - PL24;
  const componentes: Array<[string, number | null, number | null, number | null]> = [
    // componente,                        saldo 2024, movimento (prejuízo), saldo 2025
    ["Capital social", 45000, null, 45000],
    ["Capital a integralizar", -2000, null, -2000],
    ["Reserva legal", 1200, null, 1200],
    ["Ajuste de avaliação patrimonial", 1850, null, 1850],
    ["Prejuízos acumulados", PL24 - 46050, PREJ, PL25 - 46050],
    ["Total", PL24, PREJ, PL25],
  ];
  const MOV_ABERTURA = "SALDOS EM 31 DE DEZEMBRO DE 2024";
  const MOV_RESULTADO = "Prejuízo líquido do exercício";
  const MOV_FECHAMENTO = "SALDOS EM 31 DE DEZEMBRO DE 2025";
  const campos: CampoExtraido[] = [];
  for (const [comp, ab, mov, fe] of componentes) {
    const cel: Array<[string, number | null]> = [[MOV_ABERTURA, ab], [MOV_RESULTADO, mov], [MOV_FECHAMENTO, fe]];
    for (const [movimento, v] of cel) {
      if (v === null) continue; // célula com traço no PDF não vira linha
      campos.push(campo({ chave: comp, secao: movimento, secao_canonica: "dmpl", valor_num: v, documento_versao_id: V }));
    }
  }
  const documentos: DocumentoParaExport[] = [{
    id: "dDMPL", tipo_taxonomia: "DMPL", entidade: { razao_social: "Vertentes Metalúrgica Ltda." },
    periodo: { tipo: "anual", referencia: "12M25" },
    documento_versao: [{ id: V, nome_original: "09_DMPL_Vertentes_Metalurgica_2025.pdf" }],
  }];
  const wb = buildExportWorkbook({ caso: { nome: "C", produto: "rx" }, documentos, campos, agora: new Date("2026-07-27T12:00:00Z") });

  const ws = wb.getWorksheet("DMPL");
  checar(ws != null, "(10a) a DMPL tem aba própria (antes caía em MUTUOS/Não Classificadas)");
  if (ws) {
    // A MATRIZ: cabeçalho = componentes do PL, uma linha por movimento. É a
    // leitura que a demonstração existe para dar — achatá-la numa listagem
    // perderia justamente "como cada componente do PL se moveu".
    const header = ws.getRow(1);
    const cabecalhos: string[] = [];
    for (let c = 2; c <= ws.columnCount; c++) cabecalhos.push(String(header.getCell(c).value ?? ""));
    checar(
      componentes.every(([comp]) => cabecalhos.includes(comp)),
      "(10a) os 6 componentes do PL são as COLUNAS da matriz",
      cabecalhos.join(" | "),
    );
    const linhaDe = (rot: string) => {
      for (let r = 1; r <= ws.rowCount; r++) if (String(ws.getRow(r).getCell(1).value ?? "") === rot) return r;
      return -1;
    };
    const colDe = (rot: string) => cabecalhos.indexOf(rot) + 2;
    const rFech = linhaDe(MOV_FECHAMENTO);
    checar(rFech > 0, "(10a) cada movimento é uma LINHA da matriz");
    checar(
      rFech > 0 && ws.getRow(rFech).getCell(colDe("Total")).value === PL25,
      "(10b) o cruzamento movimento × componente cai na célula certa",
      `esperado=${PL25} obtido=${rFech > 0 ? ws.getRow(rFech).getCell(colDe("Total")).value : "(sem linha)"}`,
    );
    checar(
      linhaDe(MOV_RESULTADO) > 0
        && ws.getRow(linhaDe(MOV_RESULTADO)).getCell(colDe("Capital social")).value == null,
      "(10b) célula sem valor no documento (traço) continua vazia — nada é inventado",
    );
    // Toda linha rotulada tem de carregar pelo menos um NÚMERO: esta aba não tem
    // template, então uma linha sem número só poderia vir de um defeito nosso.
    const semNumero: string[] = [];
    for (let r = 2; r <= ws.rowCount; r++) {
      const rot = String(ws.getRow(r).getCell(1).value ?? "").trim();
      if (!rot) continue;
      let tem = false;
      for (let c = 2; c <= ws.columnCount; c++) if (typeof ws.getRow(r).getCell(c).value === "number") tem = true;
      if (!tem) semNumero.push(`${r} "${rot}"`);
    }
    checar(semNumero.length === 0, "(10c) nenhuma linha da DMPL sem número", semNumero.join(" / "));
  }
  // O componente do PL NÃO pode ter virado entidade: se ele fosse para
  // `entidade_coluna`, cada componente viraria uma EMPRESA fantasma no export.
  // (As abas Balanço/DRE/Fluxo existem sempre, mesmo sem dado — v28. O que não
  //  pode acontecer é uma delas carregar linha da DMPL.)
  const vazamento: string[] = [];
  for (const s of wb.worksheets) {
    if (s.name === "DMPL" || s.name === "Resumo") continue;
    for (let r = 1; r <= s.rowCount; r++) {
      const rot = String(s.getRow(r).getCell(1).value ?? "");
      if (componentes.some(([comp]) => rot === comp) || rot === MOV_ABERTURA || rot === MOV_FECHAMENTO) {
        vazamento.push(`${s.name}!${r} "${rot}"`);
      }
    }
  }
  checar(vazamento.length === 0, "(10d) a DMPL não vaza para nenhuma outra aba", vazamento.join(", "));
}

// ---- 10e: DMPL embutida num PDF de Balanço não infla o Patrimônio Líquido ---
{
  const V = "vComposto";
  const PL = 24801;
  const campos: CampoExtraido[] = [
    campo({ chave: "Capital social", secao: "Patrimônio Líquido", secao_canonica: "patrimonio_liquido", valor_num: 45000, documento_versao_id: V }),
    campo({ chave: "Prejuízos acumulados", secao: "Patrimônio Líquido", secao_canonica: "patrimonio_liquido", valor_num: PL - 45000, documento_versao_id: V }),
    campo({ chave: "TOTAL DO PATRIMÔNIO LÍQUIDO", secao: "Patrimônio Líquido", valor_num: PL, documento_versao_id: V }),
    // …e a DMPL que vem no MESMO arquivo. O saldo de fechamento repete o total
    // do PL: somado como conta, o patrimônio sai em dobro.
    campo({ chave: "Total", secao: "SALDOS EM 31 DE DEZEMBRO DE 2025", secao_canonica: "dmpl", valor_num: PL, documento_versao_id: V }),
    campo({ chave: "Capital social", secao: "SALDOS EM 31 DE DEZEMBRO DE 2025", secao_canonica: "dmpl", valor_num: 45000, documento_versao_id: V }),
  ];
  const documentos: DocumentoParaExport[] = [{
    id: "dComp", tipo_taxonomia: "BALANCO", entidade: { razao_social: "Vertentes Metalúrgica Ltda." },
    periodo: { tipo: "anual", referencia: "12M25" },
    documento_versao: [{ id: V, nome_original: "BP DRE DFC DMPL 2025.pdf" }],
  }];
  const wb = buildExportWorkbook({ caso: { nome: "C", produto: "rx" }, documentos, campos, agora: new Date("2026-07-27T12:00:00Z") });
  const bal = wb.getWorksheet("Balanço")!;
  const linhaDe = (rot: string) => {
    for (let r = 1; r <= bal.rowCount; r++) if (String(bal.getRow(r).getCell(1).value ?? "") === rot) return r;
    return -1;
  };
  const rPL = linhaDe("Patrimônio Líquido");
  const somaPL = rPL > 0 ? Math.round(avaliar(bal, "B", rPL)) : NaN;
  checar(somaPL === PL, "(10e) DMPL embutida não infla o PL do Balanço", `PL=${somaPL} informado=${PL}`);
  checar(wb.getWorksheet("DMPL") != null, "(10e) …e as linhas dela vão para a aba DMPL, não somem");
}

// ---- 10f: DVA sai na ordem do documento, sem template imposto ---------------
{
  const V = "vDVA";
  const linhas: Array<[string, string, number]> = [
    ["1 - RECEITAS", "Venda de mercadorias, produtos e serviços", 214800],
    ["1 - RECEITAS", "Provisão para créditos de liquidação duvidosa", -1980],
    ["2 - INSUMOS ADQUIRIDOS DE TERCEIROS", "Custo dos produtos e mercadorias vendidas", -168400],
    ["3 - VALOR ADICIONADO BRUTO", "Valor adicionado bruto", 44420],
    ["8 - DISTRIBUIÇÃO DO VALOR ADICIONADO", "Pessoal e encargos", 31200],
    ["8 - DISTRIBUIÇÃO DO VALOR ADICIONADO", "Impostos, taxas e contribuições", 9100],
  ];
  const campos = linhas.map(([secao, chave, v]) =>
    campo({ chave, secao, secao_canonica: "dva", valor_num: v, documento_versao_id: V }));
  const documentos: DocumentoParaExport[] = [{
    id: "dDVA", tipo_taxonomia: "DVA", entidade: { razao_social: "Vertentes Metalúrgica Ltda." },
    periodo: { tipo: "anual", referencia: "12M25" },
    documento_versao: [{ id: V, nome_original: "DVA_2025.pdf" }],
  }];
  const wb = buildExportWorkbook({ caso: { nome: "C", produto: "rx" }, documentos, campos, agora: new Date("2026-07-27T12:00:00Z") });
  const ws = wb.getWorksheet("DVA");
  checar(ws != null, "(10f) a DVA tem aba própria");
  if (ws) {
    const rotulos: string[] = [];
    const secoes: string[] = [];
    for (let r = 2; r <= ws.rowCount; r++) {
      rotulos.push(String(ws.getRow(r).getCell(1).value ?? ""));
      secoes.push(String(ws.getRow(r).getCell(2).value ?? ""));
    }
    checar(
      rotulos.join("|") === linhas.map(([, c]) => c).join("|"),
      "(10f) a ordem é a do documento — nenhuma linha imposta, nenhuma reordenada",
      rotulos.join(" | "),
    );
    checar(
      secoes[0] === "1 - RECEITAS" && secoes[4] === "8 - DISTRIBUIÇÃO DO VALOR ADICIONADO",
      "(10f) a seção declarada pelo documento é preservada",
      secoes.join(" | "),
    );
    const semNumero = rotulos.filter((_, i) => typeof ws.getRow(i + 2).getCell(3).value !== "number");
    checar(semNumero.length === 0, "(10f) nenhuma linha da DVA sem número", semNumero.join(" / "));
  }
}

// ---- 11: aba Modelagem — nada escrito à mão fora dos INPUTS ----------------
// A regra que o dono travou no pedido do v27: "TUDO o que não for inputs
// externos DEVE ESTAR EM FORMATO DE FÓRMULA, ou seja, nenhum dado deve ser
// escrito de fato, e sim puxado de outras abas onde os dados estão separados".
// Este invariante é a tradução literal disso — e é o que impede alguém (eu,
// numa sessão futura) de "resolver" um problema do modelo colando um número.
{
  const fixture = JSON.parse(
    readFileSync(new URL("./fixtures/book-vertentes.json", import.meta.url), "utf8"),
  ) as { documentos: DocumentoParaExport[]; campos: CampoExtraido[] };
  const wb = buildExportWorkbook({
    caso: { nome: "Book Vertentes", produto: "reestruturacao" },
    documentos: fixture.documentos, campos: fixture.campos,
    agora: new Date("2026-07-28T12:00:00Z"),
  });
  const ws = wb.getWorksheet("Modelagem");
  checar(ws != null, "(11) o export monta a aba Modelagem");
  if (ws) {
    // 1. Nenhum valor numérico cru fora das células de input. As de input são
    //    as únicas com preenchimento amarelo (INPUT_FILL) — o mesmo sinal que o
    //    usuário vê na tela é o que o teste usa, então os dois não podem
    //    divergir sem alguém perceber.
    const crus: string[] = [];
    let formulas = 0;
    let inputs = 0;
    for (let r = 1; r <= ws.rowCount; r++) {
      for (let c = 3; c <= ws.columnCount; c++) {
        const cell = ws.getRow(r).getCell(c);
        const v = cell.value;
        if (v == null || v === "") continue;
        const fill = cell.fill as { fgColor?: { argb?: string } } | undefined;
        const ehInput = fill?.fgColor?.argb === "FFFFF9C4";
        if (ehInput) { inputs++; continue; }
        if (typeof v === "object" && v !== null && "formula" in v) { formulas++; continue; }
        if (typeof v === "number") crus.push(`${cell.address}=${v}`);
      }
    }
    // ETAPA 3 INVERTEU ESTA REGRA, e de propósito. Antes: "nenhum número
    // escrito fora dos inputs". Agora a Modelagem RECEBE os valores brutos das
    // demonstrações e do macro, escritos em dois blocos no rodapé — é o que a
    // torna independente das outras abas. O que continua valendo, e é o que
    // este assert prende: fora dos inputs e desses dois blocos, TUDO é fórmula.
    // Um número solto no meio do modelo continua sendo um resultado congelado.
    const crusForaDaBase = crus.filter((x) => {
      const lin = Number(/\d+$/.exec(x.split("=")[0])?.[0] ?? 0);
      return lin < 200;
    });
    checar(crusForaDaBase.length === 0,
      "(11) fora dos inputs e das BASES do rodapé, tudo continua sendo fórmula",
      crusForaDaBase.slice(0, 8).join(" / "));
    // …e a contraprova: as bases EXISTEM e têm número. Sem isto o assert acima
    // passaria num export que simplesmente parou de trazer os valores.
    checar(crus.length > crusForaDaBase.length,
      "(11) …e as BASES do rodapé realmente carregam os valores extraídos",
      `${crus.length} números escritos ao todo`);
    checar(formulas > 60, `(11) o modelo é feito de fórmula (${formulas} células)`);
    checar(inputs > 0, `(11) e tem células de input marcadas (${inputs})`);

    // 2. NENHUMA fórmula da Modelagem aponta para outra aba.
    //
    //    Esta é a Etapa 3 do plano do dono, e o assert é o oposto exato do que
    //    estava aqui: até a sessão 20 exigia-se que o modelo LESSE Balanço, DRE
    //    e Fluxo por referência ("a planilha continua viva"). O dono pediu
    //    independência — a Modelagem tem de funcionar com as auxiliares
    //    ocultas (Etapa 4), renomeadas, ou copiada sozinha para outro arquivo.
    //
    //    O assert por AUSÊNCIA é mais forte que o anterior: ele não depende de
    //    saber quais abas existem. Qualquer `'Aba'!` numa fórmula reprova.
    const alvos = new Set<string>();
    for (let r = 1; r <= ws.rowCount; r++) {
      for (let c = 3; c <= ws.columnCount; c++) {
        const v = ws.getRow(r).getCell(c).value as { formula?: string } | undefined;
        const f = v?.formula;
        if (!f) continue;
        for (const m of f.matchAll(/'([^']+)'!/g)) alvos.add(m[1]);
      }
    }
    checar(alvos.size === 0,
      "(11) nenhuma fórmula da Modelagem referencia outra aba (Etapa 3)",
      `referencia: ${[...alvos].join(", ")}`);

    // 3. A timeline deriva de UMA célula (como o modelo de referência, que faz
    //    `=EDATE(C7,1)`): só o primeiro exercício é digitado.
    let rAno = -1;
    for (let r = 1; r <= ws.rowCount; r++) {
      if (String(ws.getRow(r).getCell(1).value ?? "") === "Exercício") { rAno = r; break; }
    }
    // Layout mensal: 12 meses + 1 coluna FY por ano. Só o PRIMEIRO janeiro é
    // digitado; o janeiro do ano seguinte (13 colunas à frente) deriva dele.
    const anoBase = rAno > 0 ? ws.getRow(rAno).getCell(3).value : null;
    const janAnoSeg = rAno > 0 ? ws.getRow(rAno).getCell(3 + 13).value as { formula?: string } | undefined : undefined;
    checar(typeof anoBase === "number" && !!janAnoSeg?.formula?.includes("+1"),
      "(11) a linha do tempo deriva do primeiro exercício, não é digitada ano a ano",
      `linha=${rAno} base=${String(anoBase)} próximo janeiro=${janAnoSeg?.formula ?? "(sem fórmula)"}`);
  }

  // 4. ETAPA 4: auxiliares OCULTAS, Modelagem visível — e NENHUMA removida.
  //
  //    Reverte a decisão do v28 ("quero todas as abas juntas"), e o histórico
  //    fica porque explica o risco: naquele teste o dono viu 4 abas e concluiu
  //    que as demais "não vieram" — estavam lá, ocultas. O que mudou desde
  //    então é a Etapa 3: a Modelagem virou autossuficiente, então as
  //    auxiliares deixaram de ser fonte e viraram anexo de auditoria.
  //
  //    Três coisas se afirmam juntas, e é a terceira que impede o pior
  //    resultado possível: um arquivo que o Excel se recusa a abrir.
  const ocultas = wb.worksheets.filter((s) => s.state !== "visible").map((s) => s.name);
  const visiveis = wb.worksheets.filter((s) => s.state === "visible").map((s) => s.name);
  checar(visiveis.length === 1 && visiveis[0] === "Modelagem",
    "(11) só a Modelagem fica visível na entrega", `visíveis: ${visiveis.join(", ")}`);
  checar(ocultas.length > 0, "(11) …e as auxiliares ficam ocultas", `ocultas: ${ocultas.length}`);
  // Ocultas, não removidas: os dados continuam no arquivo, íntegros.
  for (const aba of ["Resumo", "Balanço", "DRE", "Fluxo de Caixa", "Macro"]) {
    const ws2 = wb.getWorksheet(aba);
    checar(ws2 != null && ws2.rowCount > 1,
      `(11) …e a aba "${aba}" continua existindo, com conteúdo`, `linhas: ${ws2?.rowCount ?? 0}`);
  }
  // `hidden`, nunca `veryHidden`: reexibir tem de ser um clique com o botão
  // direito, não uma macro.
  checar(wb.worksheets.every((s) => s.state !== "veryHidden"),
    "(11) …e nenhuma é veryHidden (o dono consegue reexibir sem VBA)");
  // …e a Modelagem continua sendo a aba ATIVA: é por onde o arquivo abre.
  const modelagem = wb.getWorksheet("Modelagem")!;
  const abaAtiva = (wb.views?.[0] as { activeTab?: number } | undefined)?.activeTab;
  checar(abaAtiva === modelagem.id - 1,
    "(11) a Modelagem é a aba ativa (o arquivo abre nela)", `activeTab=${String(abaAtiva)} modelagem=${modelagem.id - 1}`);
}

// ---- 12: consolidação de entidade e período (teste v27) ---------------------
// O grupo tem 5 empresas e o Balanço do v27 saiu com 15 colunas de entidade: a
// mesma empresa chegava com duas grafias (apelido da coluna do combinado ×
// razão social do documento individual) e o mesmo exercício com dois rótulos
// ("2025" × "31/12/2025"). Somar o grupo assim conta cada empresa DUAS VEZES —
// é o que tornava a base inutilizável para modelagem.
{
  const fixture = JSON.parse(
    readFileSync(new URL("./fixtures/book-vertentes.json", import.meta.url), "utf8"),
  ) as { documentos: DocumentoParaExport[]; campos: CampoExtraido[] };
  const wb = buildExportWorkbook({
    caso: { nome: "Book Vertentes", produto: "reestruturacao" },
    documentos: fixture.documentos, campos: fixture.campos,
    agora: new Date("2026-07-28T12:00:00Z"),
  });
  const bal = wb.getWorksheet("Balanço")!;
  const heads: string[] = [];
  for (let c = 2; c <= bal.columnCount; c++) heads.push(String(bal.getRow(1).getCell(c).value ?? ""));
  const ents = heads.filter((h) => h && h !== "AV%" && !h.startsWith("Δ"));
  // 5 empresas × 2 exercícios = 10. Antes da consolidação eram 15.
  checar(ents.length === 10, `(12) o Balanço tem 10 colunas de entidade×exercício (5 empresas × 2 anos)`,
    `${ents.length}: ${ents.join(" | ")}`);
  checar(!ents.some((e) => /^(Componentes|Metalúrgica|Imóveis SPE|VT Logística|Vertentes Part\.)\b/.test(e)),
    "(12) nenhum apelido de coluna do combinado sobrou como se fosse outra empresa", ents.join(" | "));
  checar(!ents.some((e) => e.includes("31/12/")),
    "(12) o exercício fechado não aparece como data-base numa coluna separada", ents.join(" | "));

  // …e o casamento é CONSERVADOR: apelido sem uma razão social única que case
  // continua como está (fundir duas empresas diferentes é pior que duas colunas).
  const m = consolidarNomesDeEntidade(
    ["ALFA COMÉRCIO LTDA.", "ALFA SERVIÇOS LTDA."],
    ["Alfa", "Beta"],
  );
  checar(!m.has("Alfa"), "(12) apelido ambíguo (casa com 2 razões sociais) NÃO é consolidado");
  checar(!m.has("Beta"), "(12) apelido sem correspondente NÃO é consolidado");
  const m2 = consolidarNomesDeEntidade(["VERTENTES PARTICIPAÇÕES S.A."], ["Vertentes Part."]);
  checar(m2.get("Vertentes Part.") === "VERTENTES PARTICIPAÇÕES S.A.",
    "(12) abreviação ('Part.') casa a razão social por prefixo");
}

// ---- 13: o modelo aponta para linhas que EXISTEM (senão devolve 0 calado) ---
// O INDEX/MATCH do modelo é embrulhado em IFERROR — o que é certo para o caso
// legítimo (a DFC do book só cobre 2025, então 2024 não tem coluna e vale 0),
// mas transforma um rótulo ERRADO em zero silencioso. Foi assim que a primeira
// versão desta aba saiu com o Balanço inteiro zerado: ela procurava "Total do
// Ativo Circulante", e a aba Balanço rotula a linha do subtotal com o nome da
// SEÇÃO ("Ativo Circulante"). Este invariante resolve o MATCH de verdade.
{
  const fixture = JSON.parse(
    readFileSync(new URL("./fixtures/book-vertentes.json", import.meta.url), "utf8"),
  ) as { documentos: DocumentoParaExport[]; campos: CampoExtraido[] };
  const wb = buildExportWorkbook({
    caso: { nome: "Book Vertentes", produto: "reestruturacao" },
    documentos: fixture.documentos, campos: fixture.campos,
    agora: new Date("2026-07-28T12:00:00Z"),
  });
  const ws = wb.getWorksheet("Modelagem")!;

  const rotulosDe = (aba: string) => {
    const alvo = wb.getWorksheet(aba);
    const set = new Set<string>();
    if (alvo) for (let r = 1; r <= alvo.rowCount; r++) {
      set.add(String(alvo.getRow(r).getCell(1).value ?? "").trim());
    }
    return set;
  };
  const cache = new Map<string, Set<string>>();
  const perdidos: string[] = [];
  let procurados = 0;
  for (let r = 1; r <= ws.rowCount; r++) {
    for (let c = 3; c <= ws.columnCount; c++) {
      const v = ws.getRow(r).getCell(c).value as { formula?: string } | undefined;
      const f = v?.formula;
      if (!f) continue;
      // O intervalo é LIMITADO ao tamanho da aba (`$A$1:$A$162`), nunca coluna
      // inteira — referência de coluna cheia inflava o grafo de dependência a
      // ponto de travar o recálculo.
      for (const m of f.matchAll(/MATCH\("([^"]+)",'([^']+)'!\$A\$1:\$A\$\d+,0\)/g)) {
        const [, rotulo, aba] = m;
        procurados++;
        if (!cache.has(aba)) cache.set(aba, rotulosDe(aba));
        if (!cache.get(aba)!.has(rotulo)) {
          const onde = `${aba}!"${rotulo}" (usado em ${ws.getRow(r).getCell(1).value})`;
          if (!perdidos.includes(onde)) perdidos.push(onde);
        }
      }
    }
  }
  // ETAPA 3: o modelo não busca mais rótulo em OUTRA aba — ele busca na base
  // local, por POSIÇÃO de linha (o rótulo virou endereço na geração). Então
  // `procurados` é zero por construção, e o que este bloco ainda protege é o
  // caso em que alguém reintroduza uma busca entre abas: se houver alguma,
  // todos os rótulos dela têm de existir.
  checar(procurados === 0,
    "(13) o modelo não faz mais busca por rótulo em outra aba (a base é local)",
    `${procurados} busca(s)`);
  checar(perdidos.length === 0,
    `(13) todos os ${procurados} rótulos procurados existem na aba de destino`,
    perdidos.slice(0, 6).join(" / "));

  // …e o resultado disso bate com o GABARITO do book: resolve o INDEX/MATCH do
  // jeito que o Excel resolveria e compara o número que o modelo vai exibir.
  const ent = "VERTENTES METALÚRGICA LTDA.";
  const valorNaAba = (aba: string, rotulo: string, ano: number): number | null => {
    const alvo = wb.getWorksheet(aba);
    if (!alvo) return null;
    let linha = -1;
    for (let r = 1; r <= alvo.rowCount; r++) {
      if (String(alvo.getRow(r).getCell(1).value ?? "").trim() === rotulo) { linha = r; break; }
    }
    let coluna = -1;
    for (let c = 2; c <= alvo.columnCount; c++) {
      if (String(alvo.getRow(1).getCell(c).value ?? "").trim() === `${ent} — ${ano}`) { coluna = c; break; }
    }
    if (linha < 0 || coluna < 0) return null;
    const v = avaliarCelula(alvo, alvo.getColumn(coluna).letter, linha);
    return typeof v === "number" ? Math.round(v) : null;
  };
  const gab = JSON.parse(
    // Resolvido a partir do PRÓPRIO arquivo, como todos os outros nove `readFileSync`
    // desta suíte. Este aqui era um caminho ABSOLUTO para o checkout de uma sessão
    // (`/home/user/tratamento-dados-financeiros/...`) e funcionava por acidente: quem
    // clonasse o repositório em qualquer outro lugar recebia ENOENT. Foi o PRIMEIRO
    // achado do CI — na primeira execução dele, antes de qualquer suíte reprovar.
    readFileSync(new URL("../../test-data/book-vertentes/pdf/GABARITO.json", import.meta.url), "utf8"),
  ) as { balanco_por_entidade: Record<string, Record<string, Record<string, number>>> };
  const errosModelo: string[] = [];
  for (const ano of [2024, 2025]) {
    const esperado = gab.balanco_por_entidade[String(ano)].metalurgica;
    const pares: Array<[string, number]> = [
      ["Ativo Circulante", esperado.AC],
      ["Ativo Não Circulante", esperado.ANC],
      ["Passivo Circulante", esperado.PC],
      ["Passivo Não Circulante", esperado.PNC],
      ["Patrimônio Líquido", esperado.PL],
    ];
    for (const [rot, exp] of pares) {
      const got = valorNaAba("Balanço", rot, ano);
      if (got !== exp) errosModelo.push(`${ano} ${rot}: modelo=${got} gabarito=${exp}`);
    }
  }
  checar(errosModelo.length === 0,
    "(13) o que o modelo vai puxar do Balanço bate com o gabarito, nos dois exercícios",
    errosModelo.join(" / "));
}

// ---- 14: PREMISSA MUDOU => MODELO INTEIRO MUDA -----------------------------
// O critério que o dono marcou como o mais importante: "alteração de premissas
// deve alterar a modelagem como um todo". Isso não se verifica lendo o código —
// se verifica no GRAFO DE DEPENDÊNCIA das fórmulas geradas. Aqui a planilha é
// tratada como o Excel a trata: cada célula projetada tem de alcançar, por
// algum caminho de referências, as células de premissa do seu exercício.
//
// Foi este invariante que pegou o defeito de as premissas serem lidas sempre da
// coluna C: a premissa do 2º ano projetado existia na tela, o usuário digitava
// nela, e NADA acontecia — o pior defeito possível num modelo.
{
  const fixture = JSON.parse(
    readFileSync(new URL("./fixtures/book-vertentes.json", import.meta.url), "utf8"),
  ) as { documentos: DocumentoParaExport[]; campos: CampoExtraido[] };
  const wb = buildExportWorkbook({
    caso: { nome: "Book Vertentes", produto: "reestruturacao" },
    documentos: fixture.documentos, campos: fixture.campos,
    agora: new Date("2026-07-28T12:00:00Z"),
  });
  const ws = wb.getWorksheet("Modelagem")!;

  const formulaDe = (addr: string): string | null => {
    const m = addr.match(/^([A-Z]+)(\d+)$/);
    if (!m) return null;
    const v = ws.getCell(addr).value as { formula?: string } | undefined;
    return v?.formula ?? null;
  };
  // Referências a células DESTA aba (ignora as cross-sheet, que são o dado real).
  const refsDe = (formula: string): string[] => {
    const semOutrasAbas = formula.replace(/'[^']+'![^,)]*/g, "");
    return [...semOutrasAbas.matchAll(/\$?([A-Z]{1,2})\$?(\d{1,4})\b/g)]
      .map((m) => `${m[1]}${m[2]}`);
  };
  const alcanca = (origem: string, alvos: Set<string>): boolean => {
    const visto = new Set<string>();
    const fila = [origem];
    while (fila.length > 0) {
      const atual = fila.pop()!;
      if (visto.has(atual)) continue;
      visto.add(atual);
      if (alvos.has(atual)) return true;
      const f = formulaDe(atual);
      if (!f) continue;
      for (const r of refsDe(f)) if (!visto.has(r)) fila.push(r);
    }
    return false;
  };

  // Localiza o bloco de premissas e a linha do Exercício.
  let linhaAno = -1;
  const linhasPremissa: number[] = [];
  let dentroDePremissas = false;
  for (let r = 1; r <= ws.rowCount; r++) {
    const rot = String(ws.getRow(r).getCell(1).value ?? "");
    if (rot === "Exercício") linhaAno = r;
    if (rot.startsWith("PREMISSAS")) { dentroDePremissas = true; continue; }
    if (dentroDePremissas) {
      if (!rot || rot === rot.toUpperCase() && rot.length > 12) { dentroDePremissas = false; continue; }
      linhasPremissa.push(r);
    }
  }
  checar(linhaAno > 0 && linhasPremissa.length >= 8,
    `(14) o bloco de premissas foi encontrado (${linhasPremissa.length} premissas)`);

  // Colunas projetadas = as que vêm depois do último exercício com dado real.
  // No fixture do book o histórico é 2024-2025, então a 3ª coluna em diante.
  const colunaLetra = (i: number) => ws.getColumn(i).letter;
  // Layout mensal: por ano, 12 colunas de mês + 1 coluna FY (a 13ª), que é onde
  // as premissas daquele exercício moram. O teste checa a coluna FY dos anos
  // PROJETADOS e também um mês dentro de cada um — a célula mensal tem de
  // alcançar a premissa do SEU ano, não de outro.
  const nAnos = Math.floor((ws.columnCount - 2) / 13);
  const colFY = (y: number) => 3 + y * 13 + 12;
  const colMes = (y: number, m: number) => 3 + y * 13 + m;
  const anosProj = [nAnos - 3, nAnos - 2, nAnos - 1];
  const colsProjetadas = anosProj.map(colFY);
  checar(colsProjetadas.length === 3, `(14) há 3 exercícios projetados`, String(colsProjetadas.length));

  // As linhas de RESULTADO que precisam responder a premissa.
  const alvosDeTeste = [
    "Receita Líquida", "EBITDA", "Lucro/Prejuízo Líquido do Exercício",
    "Saldo final de caixa", "TOTAL DO ATIVO", "Patrimônio Líquido",
    "Necessidade de captação (caixa negativo)", "Liquidez corrente",
  ];
  const linhaDe = (rot: string) => {
    for (let r = 1; r <= ws.rowCount; r++) {
      if (String(ws.getRow(r).getCell(1).value ?? "") === rot) return r;
    }
    return -1;
  };

  const mortas: string[] = [];
  for (const y of anosProj) {
    const letraFY = colunaLetra(colFY(y));
    const premissasDoAno = new Set(linhasPremissa.map((r) => `${letraFY}${r}`));
    for (const c of [colFY(y), colMes(y, 5)]) { // consolidado e um mês do meio do ano
      const letra = colunaLetra(c);
      for (const rot of alvosDeTeste) {
        const r = linhaDe(rot);
        if (r < 0) { mortas.push(`linha ausente: ${rot}`); continue; }
        if (!alcanca(`${letra}${r}`, premissasDoAno)) {
          mortas.push(`${letra}${r} (${rot}) não alcança as premissas de ${letraFY}`);
        }
      }
    }
  }
  checar(mortas.length === 0,
    "(14) toda linha projetada depende das premissas DO SEU exercício",
    mortas.slice(0, 6).join(" / "));

  // …e o contrário: nenhuma premissa pode estar MORTA (existir na tela sem
  // ninguém ler). Uma premissa que não move nada é pior que não ter premissa.
  const premissasMortas: string[] = [];
  for (const rp of linhasPremissa) {
    const rotulo = String(ws.getRow(rp).getCell(1).value ?? "");
    let usada = false;
    for (const c of colsProjetadas) {
      const letra = colunaLetra(c);
      const alvo = new Set([`${letra}${rp}`]);
      for (let r = 1; r <= ws.rowCount && !usada; r++) {
        if (r === rp) continue;
        const f = formulaDe(`${letra}${r}`);
        if (f && refsDe(f).includes(`${letra}${rp}`)) usada = true;
        else if (alcanca(`${letra}${r}`, alvo) && r !== rp) usada = true;
      }
      if (usada) break;
    }
    if (!usada) premissasMortas.push(`${rotulo} (linha ${rp})`);
  }
  checar(premissasMortas.length === 0,
    "(14) nenhuma premissa fica morta na tela sem mover o modelo",
    premissasMortas.join(" / "));
}

// ---- 15: índices macro — histórico calibra, Focus projeta ------------------
// Duas coisas diferentes e o modelo usa cada uma para o que ela serve. O erro
// que este bloco impede é o mais fácil de cometer: projetar com a média dos
// últimos anos (retrovisor) ou calcular essa média de forma aritmética, que
// para taxa é simplesmente a conta errada.
{
  const fixture = JSON.parse(
    readFileSync(new URL("./fixtures/book-vertentes.json", import.meta.url), "utf8"),
  ) as { documentos: DocumentoParaExport[]; campos: CampoExtraido[] };

  // 12 anos de IPCA/Selic + um ano INCOMPLETO (o corrente), que não pode entrar
  // nas médias, e a expectativa Focus para os anos projetados.
  const anuais = [];
  for (let ano = 2014; ano <= 2025; ano++) {
    anuais.push({ serie: "IPCA", ano, meses: 12, retorno: 4 + (ano % 5) });
    anuais.push({ serie: "SELIC", ano, meses: 12, retorno: 8 + (ano % 4) });
  }
  anuais.push({ serie: "IPCA", ano: 2026, meses: 5, retorno: 2.1 }); // incompleto
  const expectativas = [
    { serie: "IPCA", ano_ref: 2026, mediana: 5.12, coletado_em: "2026-07-24" },
    { serie: "IPCA", ano_ref: 2027, mediana: 4.50, coletado_em: "2026-07-24" },
    { serie: "IPCA", ano_ref: 2028, mediana: 4.00, coletado_em: "2026-07-24" },
    { serie: "SELIC", ano_ref: 2026, mediana: 14.75, coletado_em: "2026-07-24" },
    { serie: "SELIC", ano_ref: 2027, mediana: 12.50, coletado_em: "2026-07-24" },
    { serie: "SELIC", ano_ref: 2028, mediana: 10.50, coletado_em: "2026-07-24" },
  ];
  const wb = buildExportWorkbook({
    caso: { nome: "Book Vertentes", produto: "reestruturacao" },
    documentos: fixture.documentos, campos: fixture.campos,
    macro: { anuais, expectativas },
    agora: new Date("2026-07-28T12:00:00Z"),
  });

  const macro = wb.getWorksheet("Macro");
  checar(macro != null, "(15) a aba Macro é montada quando há índices");
  const dados = wb.getWorksheet("Macro (dados)");
  // A aba de dado cru continua EXISTINDO e agora fica visível como todas as
  // outras (v28) — o que importa é que ela existe e que a aba Macro não guarda
  // número nenhum, só fórmula sobre ela (verificado abaixo).
  checar(dados != null, "(15) o dado cru da série tem aba própria (proveniência não some)");

  if (macro) {
    // A aba visível não guarda número: é toda referência/fórmula.
    const crus: string[] = [];
    for (let r = 1; r <= macro.rowCount; r++) {
      // As linhas de CABEÇALHO carregam os anos, e eles têm de ser NÚMERO: o
      // modelo busca a expectativa com MATCH contra a célula do exercício, que
      // é numérica. Ano como texto faz o MATCH nunca casar, o IFERROR devolver
      // 0, e a premissa de inflação aparecer zerada sem nenhum sinal — foi o
      // defeito que o recálculo pegou. Aqui elas são exceção legítima.
      const rotulo = String(macro.getRow(r).getCell(1).value ?? "");
      if (rotulo.startsWith("Retorno anual") || rotulo.startsWith("Expectativa Focus")) continue;
      for (let c = 2; c <= macro.columnCount; c++) {
        const v = macro.getRow(r).getCell(c).value;
        if (typeof v === "number") crus.push(`${macro.getRow(r).getCell(c).address}=${v}`);
      }
    }
    // …e que os anos do cabeçalho do Focus sejam mesmo numéricos.
    for (let r = 1; r <= macro.rowCount; r++) {
      if (!String(macro.getRow(r).getCell(1).value ?? "").startsWith("Expectativa Focus")) continue;
      const primeiro = macro.getRow(r).getCell(2).value;
      checar(typeof primeiro === "number",
        "(15) os anos do cabeçalho do Focus são NÚMERO (senão o MATCH do modelo nunca casa)",
        `veio ${typeof primeiro}: ${String(primeiro)}`);
    }
    checar(crus.length === 0, "(15) a aba Macro não tem número escrito — só fórmula", crus.slice(0, 5).join(" / "));

    // A média tem de ser GEOMÉTRICA. Uma média aritmética de taxa (AVERAGE) é
    // a conta errada e a diferença compõe: 10% e 4% dão 6,96%, não 7,00%.
    const formulas: string[] = [];
    for (let r = 1; r <= macro.rowCount; r++) {
      for (let c = 2; c <= macro.columnCount; c++) {
        const v = macro.getRow(r).getCell(c).value as { formula?: string } | undefined;
        if (v?.formula) formulas.push(v.formula);
      }
    }
    const medias = formulas.filter((f) => f.includes("PRODUCT("));
    checar(medias.length >= 3, `(15) as médias usam composição geométrica (PRODUCT^(1/n))`, String(medias.length));
    checar(medias.every((f) => /\^\(1\/\d+\)/.test(f)),
      "(15) …com a raiz da janela, não a soma dividida");
    checar(!formulas.some((f) => /\bAVERAGE\(/.test(f)),
      "(15) nenhuma média de taxa é aritmética");
    // O invariante ANTIGO exigia `COUNT(` em toda média — ele travava o MECANISMO,
    // não a propriedade, e o mecanismo era justamente o defeito: a faixa era
    // posicional (últimas N colunas) e a última coluna é sempre o ano parcial, então
    // as três médias saíam em branco com 12 anos completos na base. Agora a janela
    // nomeia os anos completos um a um, e o que se afirma é o COMPORTAMENTO.
    checar(medias.every((f) => !f.includes(":")),
      "(15) a janela nomeia os anos completos, não uma faixa posicional de colunas");
  }

  // O modelo consome o Focus: as premissas macro apontam para a aba Macro.
  const mod = wb.getWorksheet("Modelagem")!;
  const linhaDe = (rot: string) => {
    for (let r = 1; r <= mod.rowCount; r++) {
      if (String(mod.getRow(r).getCell(1).value ?? "") === rot) return r;
    }
    return -1;
  };
  const rIpca = linhaDe("Inflação esperada (metodologia selecionada)");
  const rSelic = linhaDe("Juro esperado (Selic — Focus)");
  checar(rIpca > 0 && rSelic > 0, "(15) o modelo tem premissas de IPCA e Selic");
  if (rIpca > 0) {
    const nA = Math.floor((mod.columnCount - 2) / 13);
    const f = String((mod.getRow(rIpca).getCell(3 + (nA - 1) * 13 + 12).value as { formula?: string })?.formula ?? "");
    // Etapa 3: o Focus agora é espelhado DENTRO da Modelagem (bloco "BASE
    // MACRO"), então a premissa lê uma linha local em vez de 'Macro'!. O que
    // importa continua igual — ela é FÓRMULA sobre o dado publicado, não um
    // número digitado — e o assert prende isso sem citar aba nenhuma.
    checar(/INDEX\(/.test(f) && /MATCH\(/.test(f) && !/'[^']+'!/.test(f),
      "(15) a premissa de IPCA é fórmula sobre o Focus espelhado, sem referência a outra aba",
      f.slice(0, 110));
    checar(!f.includes("AVERAGE"), "(15) …e não da média histórica");
  }

  // E a regra do dono continua valendo COM macro: nenhuma premissa morta.
  const linhasPremissa: number[] = [];
  let dentro = false;
  for (let r = 1; r <= mod.rowCount; r++) {
    const rot = String(mod.getRow(r).getCell(1).value ?? "");
    if (rot.startsWith("PREMISSAS")) { dentro = true; continue; }
    if (dentro) {
      if (!rot || (rot === rot.toUpperCase() && rot.length > 12)) { dentro = false; continue; }
      linhasPremissa.push(r);
    }
  }
  checar(linhasPremissa.length === 15,
    `(15) as 15 premissas (3 macro + 12 operacionais) estão no bloco`, String(linhasPremissa.length));
}

// ---- 16: consolidação mensal → anual (fluxo soma, estoque NÃO) -------------
// É onde um modelo mensal se perde, e o erro é invisível na tela: somar doze
// balanços dá doze vezes o patrimônio, e somar doze margens dá 1200%. Cada
// natureza de linha tem UMA consolidação correta, e este invariante prende cada
// uma à sua.
{
  const fixture = JSON.parse(
    readFileSync(new URL("./fixtures/book-vertentes.json", import.meta.url), "utf8"),
  ) as { documentos: DocumentoParaExport[]; campos: CampoExtraido[] };
  const wb = buildExportWorkbook({
    caso: { nome: "Book Vertentes", produto: "reestruturacao" },
    documentos: fixture.documentos, campos: fixture.campos,
    agora: new Date("2026-07-28T12:00:00Z"),
  });
  const ws = wb.getWorksheet("Modelagem")!;
  const nAnos = Math.floor((ws.columnCount - 2) / 13);
  const colFY = (y: number) => 3 + y * 13 + 12;
  const colMes = (y: number, m: number) => 3 + y * 13 + m;
  const letra = (i: number) => ws.getColumn(i).letter;
  const linhaDe = (rot: string) => {
    for (let r = 1; r <= ws.rowCount; r++) {
      if (String(ws.getRow(r).getCell(1).value ?? "") === rot) return r;
    }
    return -1;
  };
  const fDe = (r: number, c: number) =>
    String((ws.getRow(r).getCell(c).value as { formula?: string } | undefined)?.formula ?? "");

  checar(nAnos >= 5 && (ws.columnCount - 2) % 13 === 0,
    `(16) layout mensal: ${nAnos} anos × (12 meses + 1 consolidado)`, `${ws.columnCount} colunas`);

  const y = nAnos - 1; // um ano projetado
  const fy = colFY(y);

  // FLUXO consolida por SOMA dos 12 meses.
  for (const rot of ["Receita Líquida", "EBITDA", "Lucro/Prejuízo Líquido do Exercício"]) {
    const r = linhaDe(rot);
    const f = fDe(r, fy);
    const esperado = `SUM(${letra(colMes(y, 0))}${r}:${letra(colMes(y, 11))}${r})`;
    checar(f === esperado, `(16) "${rot}" consolida somando os 12 meses`, `veio: ${f}`);
  }

  // ESTOQUE consolida pegando DEZEMBRO — somar seria multiplicar o patrimônio.
  for (const rot of ["TOTAL DO ATIVO", "Patrimônio Líquido", "Saldo final de caixa", "Caixa e equivalentes"]) {
    const r = linhaDe(rot);
    const f = fDe(r, fy);
    const esperado = `${letra(colMes(y, 11))}${r}`;
    checar(f === esperado, `(16) "${rot}" consolida pelo saldo de DEZEMBRO, não pela soma`, `veio: ${f}`);
    checar(!f.startsWith("SUM("), `(16) …e definitivamente não soma`, `${rot}: ${f}`);
  }

  // SALDO INICIAL do ano é o de JANEIRO (não o de dezembro, nem a soma).
  {
    const r = linhaDe("Saldo inicial de caixa");
    checar(fDe(r, fy) === `${letra(colMes(y, 0))}${r}`,
      "(16) o saldo inicial do ano é o de JANEIRO", `veio: ${fDe(r, fy)}`);
  }

  // ÍNDICE é RECALCULADO sobre os agregados anuais — nunca somado nem "média".
  for (const rot of ["Margem bruta", "Margem EBITDA", "Margem líquida"]) {
    const r = linhaDe(rot);
    const f = fDe(r, fy);
    checar(f.includes(`${letra(fy)}`) && !f.startsWith("SUM(") && !f.includes("AVERAGE("),
      `(16) "${rot}" é recalculada sobre o agregado do ano`, `veio: ${f}`);
  }

  // A necessidade de captação do ano é o PIOR mês, não dezembro: um vale de
  // caixa em julho precisa ser financiado mesmo que dezembro feche positivo.
  {
    const r = linhaDe("Necessidade de captação (caixa negativo)");
    const f = fDe(r, fy);
    checar(f.includes("MIN(") && f.includes(`${letra(colMes(y, 0))}`) && f.includes(`${letra(colMes(y, 11))}`),
      "(16) a captação do ano olha o PIOR mês, não o fechamento", `veio: ${f}`);
  }

  // E as três conferências existem — um modelo institucional prova que fecha.
  for (const rot of ["Balanço fecha (Ativo − Passivo − PL)",
                     "Receita do ano = receita extraída",
                     "Caixa do balanço = saldo final do fluxo"]) {
    checar(linhaDe(rot) > 0, `(16) o modelo traz a conferência "${rot}"`);
  }
}

// ---- 16: DF auditada — o conjunto num arquivo só é separado por demonstração --
// A forma mais comum de entrega num mandato real é o PDF auditado do exercício:
// Balanço + DRE + DFC + DMPL + notas juntos, um documento só. Esse tipo
// (DF_AUDITADA, db/migrations/0002) não pode ter aba própria — que aba seria? — e
// por isso caía em "Outros", onde o roteamento por linha nem rodava: a DF inteira
// saía como listagem crua, sem template, sem total de seção, sem AV%/Δ%, sem
// indicadores, e a aba Modelagem (que lê das abas de demonstração) saía ZERADA.
// Aqui o MESMO dado do book é entregue como um arquivo auditado só, e tem de
// produzir os MESMOS números que produz quando vem em três arquivos separados.
{
  const fixture = JSON.parse(
    readFileSync(new URL("./fixtures/book-vertentes.json", import.meta.url), "utf8"),
  ) as { documentos: DocumentoParaExport[]; campos: CampoExtraido[] };
  const gab = JSON.parse(
    readFileSync(new URL("../../test-data/book-vertentes/pdf/GABARITO.json", import.meta.url), "utf8"),
  ) as {
    balanco_por_entidade: Record<string, Record<string, Record<string, number>>>;
    dre_metalurgica_2025: Record<string, number>;
  };

  // BP (01) + DRE (07) + DFC (08) da Metalúrgica, os três apontando para UMA
  // versão de um documento DF_AUDITADA — é literalmente o mesmo dado, entregue
  // como o cliente entrega.
  const V = "vDFAuditada";
  const VERSOES_METALURGICA = [
    "55555555-0000-0000-0000-000000000001", // Balanço 2025x2024
    "55555555-0000-0000-0000-000000000007", // DRE 2025x2024
    "55555555-0000-0000-0000-000000000008", // DFC 2025
  ];
  const camposDF: CampoExtraido[] = fixture.campos
    .filter((c) => VERSOES_METALURGICA.includes(c.documento_versao_id))
    .map((c) => ({ ...c, documento_versao_id: V }));
  // …e as NOTAS que vêm no mesmo arquivo auditado. A nota DETALHA o que o balanço
  // já traz consolidado: a linha "Empréstimos e financiamentos" do BP contra o
  // credor-a-credor da nota. Roteá-la para o Balanço somaria as duas.
  const notas: CampoExtraido[] = [
    campo({ chave: "Banco Alfa - capital de giro", secao: "Nota 12 — Empréstimos e financiamentos", valor_num: 9000, periodo_coluna: "2025", documento_versao_id: V }),
    campo({ chave: "Banco Beta - CDC", secao: "Nota 12 — Empréstimos e financiamentos", valor_num: 6000, periodo_coluna: "2025", documento_versao_id: V }),
    campo({ chave: "Duplicatas descontadas", secao: "Notas explicativas às demonstrações financeiras", valor_num: 4000, periodo_coluna: "2025", documento_versao_id: V }),
  ];
  const documentos: DocumentoParaExport[] = [{
    id: "dDF", tipo_taxonomia: "DF_AUDITADA", entidade: { razao_social: "VERTENTES METALÚRGICA LTDA." },
    periodo: { tipo: "multi", referencia: "24,25" },
    documento_versao: [{ id: V, nome_original: "DF_Auditadas_Vertentes_Metalurgica_2025.pdf" }],
  }];
  const wb = buildExportWorkbook({
    caso: { nome: "DF auditada", produto: "reestruturacao" },
    campos: [...camposDF, ...notas], documentos, agora: new Date("2026-07-29T12:00:00Z"),
  });

  const bal = wb.getWorksheet("Balanço");
  const dre = wb.getWorksheet("DRE");
  const dfc = wb.getWorksheet("Fluxo de Caixa");
  checar(bal != null && dre != null && dfc != null,
    "(16a) a DF auditada abre as três abas de demonstração (antes: listagem crua em 'Outros')",
    wb.worksheets.map((s) => s.name).join(", "));

  if (bal && dre && dfc) {
    const linhaDe = (ws: import("exceljs").Worksheet, rot: string) => {
      for (let r = 1; r <= ws.rowCount; r++) if (String(ws.getRow(r).getCell(1).value ?? "") === rot) return r;
      return -1;
    };
    const colunas = (ws: import("exceljs").Worksheet) => {
      const m = new Map<string, string>();
      for (let c = 2; c <= ws.columnCount; c++) {
        const h = String(ws.getRow(1).getCell(c).value ?? "");
        if (h && h !== "AV%" && !h.startsWith("Δ%")) m.set(h, ws.getColumn(c).letter);
      }
      return m;
    };
    // O Balanço tem de bater com o gabarito nos dois exercícios — mesmo número
    // que sai quando o BP vem em arquivo próprio (invariante 7).
    const colBal = colunas(bal);
    const LINHA: Record<string, number> = {
      ATIVO: linhaDe(bal, "ATIVO"), AC: linhaDe(bal, "Ativo Circulante"), ANC: linhaDe(bal, "Ativo Não Circulante"),
      PC: linhaDe(bal, "Passivo Circulante"), PNC: linhaDe(bal, "Passivo Não Circulante"), PL: linhaDe(bal, "Patrimônio Líquido"),
    };
    const erros: string[] = [];
    let conferidos = 0;
    for (const ano of ["2024", "2025"]) {
      const col = colBal.get(`VERTENTES METALÚRGICA LTDA. — ${ano}`);
      if (!col) { erros.push(`coluna ausente: ${ano} (${[...colBal.keys()].join(" | ")})`); continue; }
      for (const [sigla, row] of Object.entries(LINHA)) {
        const esperado = gab.balanco_por_entidade[ano].metalurgica[sigla];
        const obtido = Math.round(avaliar(bal, col, row));
        conferidos++;
        if (obtido !== esperado) erros.push(`${ano} ${sigla}: export=${obtido} gabarito=${esperado}`);
      }
    }
    checar(erros.length === 0 && conferidos === 12,
      `(16b) o Balanço da DF auditada bate com o gabarito nas ${conferidos} seções`,
      erros.slice(0, 6).join(" / "));

    // A DRE idem — e é a prova de que a cascata foi ORDENADA pelo template, não
    // empilhada como veio.
    const colDRE = colunas(dre);
    const col2025 = [...colDRE.entries()].find(([h]) => h.includes("2025"))?.[1] ?? "";
    const errosDRE = ([
      ["Receita Líquida", gab.dre_metalurgica_2025["RECEITA OPERACIONAL LÍQUIDA"]],
      ["Lucro Bruto", gab.dre_metalurgica_2025["LUCRO BRUTO"]],
      ["Resultado Operacional (EBIT)", gab.dre_metalurgica_2025["RESULTADO OPERACIONAL ANTES DO RESULTADO FINANCEIRO"]],
      ["Lucro/Prejuízo Líquido do Exercício", gab.dre_metalurgica_2025["PREJUÍZO LÍQUIDO DO EXERCÍCIO"]],
    ] as Array<[string, number]>)
      .map(([rot, exp]) => {
        const r = linhaDe(dre, rot);
        const got = r > 0 && col2025 ? Math.round(avaliar(dre, col2025, r)) : NaN;
        return got === exp ? null : `${rot}: export=${got} gabarito=${exp}`;
      })
      .filter(Boolean) as string[];
    checar(errosDRE.length === 0, "(16c) a DRE da DF auditada bate com o gabarito", errosDRE.join(" / "));

    // O Fluxo idem, pelo próprio documento (o book só tem DFC de 2025).
    const colDFC = colunas(dfc);
    const colFC = [...colDFC.values()][0] ?? "";
    const rOper = linhaDe(dfc, "Caixa Líquido das Atividades Operacionais");
    checar(rOper > 0 && Math.round(avaliar(dfc, colFC, rOper)) === 1090,
      "(16d) o Fluxo de Caixa da DF auditada fecha com o documento",
      `linha=${rOper} valor=${rOper > 0 ? Math.round(avaliar(dfc, colFC, rOper)) : "(ausente)"}`);

    // A NOTA não pode ter entrado em soma nenhuma do Balanço: o detalhe do
    // credor-a-credor debaixo do total que o BP já informa é dupla contagem.
    const ROTULOS_DE_NOTA = ["Banco Alfa - capital de giro", "Banco Beta - CDC", "Duplicatas descontadas"];
    const vazamentos: string[] = [];
    for (const ws of [bal, dre, dfc]) {
      for (let r = 1; r <= ws.rowCount; r++) {
        const rot = String(ws.getRow(r).getCell(1).value ?? "");
        if (ROTULOS_DE_NOTA.includes(rot)) vazamentos.push(`${ws.name}!${r} "${rot}"`);
      }
    }
    checar(vazamentos.length === 0,
      "(16e) linha de NOTA EXPLICATIVA não entra em demonstração nenhuma (seria dupla contagem)",
      vazamentos.join(", "));
    const outros = wb.getWorksheet("Outros");
    const rotulosOutros: string[] = [];
    if (outros) for (let r = 1; r <= outros.rowCount; r++) {
      for (let c = 1; c <= outros.columnCount; c++) rotulosOutros.push(String(outros.getRow(r).getCell(c).value ?? ""));
    }
    checar(rotulosOutros.includes("Banco Alfa - capital de giro"),
      "(16f) …mas continua entregue, com proveniência, na listagem documental");

    // E o modelo deixa de sair zerado: é o que a fatia existe para destravar.
    const mod = wb.getWorksheet("Modelagem")!;
    const rANC = linhaDe(mod, "Ativo Não Circulante");
    const formulas: string[] = [];
    if (rANC > 0) {
      for (let c = 2; c <= mod.columnCount; c++) {
        const f = (mod.getRow(rANC).getCell(c).value as { formula?: string } | undefined)?.formula;
        if (f) formulas.push(f);
      }
    }
    // Etapa 3: a origem passou a ser a base local. O que a fatia destravou
    // continua sendo o ponto — o modelo tem DE ONDE ler — e agora isso se
    // afirma pelo INDEX na base do rodapé (linhas 200+), não pelo nome da aba.
    checar(rANC > 0 && formulas.some((f) => /INDEX\(\$[A-Z]+\$2\d\d/.test(f)),
      "(16g) a aba Modelagem passa a ter de onde ler (antes: DF auditada = modelo zerado)",
      formulas[0]?.slice(0, 90) ?? "(nenhuma fórmula)");
  }
}

// ---- 16h/16i: o roteamento não se estende a quem DETALHA o balanço -----------
// A contrapartida do 16: aging de recebíveis, estoque, extrato e razão trazem o
// DETALHE do que o balanço já apresenta consolidado. Se o roteamento por linha
// valesse para todo o balde "Outros", esse detalhe entraria na mesma seção do
// Balanço, DEBAIXO do total informado — exatamente a dupla contagem que o export
// levou três rodadas para eliminar. Este bloco trava a fronteira.
{
  const aging = (versao: string): CampoExtraido[] => [
    campo({ chave: "Duplicatas a receber - a vencer", secao: "Contas a Receber", secao_canonica: "ativo_circulante", valor_num: 12000, documento_versao_id: versao }),
    campo({ chave: "Duplicatas a receber - vencidas até 30 dias", secao: "Contas a Receber", secao_canonica: "ativo_circulante", valor_num: 5000, documento_versao_id: versao }),
    campo({ chave: "Duplicatas a receber - vencidas há mais de 180 dias", secao: "Contas a Receber", secao_canonica: "ativo_circulante", valor_num: 3000, documento_versao_id: versao }),
  ];

  for (const [tipo, rotulo] of [["AGING_AR", "(16h) documento de aging (tipo próprio)"], [null, "(16i) documento homogêneo AINDA SEM TIPO"]] as Array<[string | null, string]>) {
    const V = `vAging${tipo ?? "Null"}`;
    const wb = buildExportWorkbook({
      caso: { nome: "Aging", produto: "reestruturacao" },
      documentos: [{
        id: `dAging${tipo ?? "Null"}`, tipo_taxonomia: tipo, entidade: { razao_social: "Alfa Ltda." },
        periodo: { tipo: "data-base", referencia: "2025-12-31" },
        documento_versao: [{ id: V, nome_original: "aging.pdf" }],
      }],
      campos: aging(V), agora: new Date("2026-07-29T12:00:00Z"),
    });
    // A aba Balanço existe sempre (v28); o que não pode é a linha do aging ter
    // ido para dentro dela — seria o detalhe somado debaixo do total do BP.
    const bal = wb.getWorksheet("Balanço");
    const rotulos: string[] = [];
    if (bal) for (let r = 1; r <= bal.rowCount; r++) rotulos.push(String(bal.getRow(r).getCell(1).value ?? ""));
    const entrou = rotulos.filter((x) => x.startsWith("Duplicatas a receber -"));
    checar(entrou.length === 0,
      `${rotulo} não vira linha do Balanço`,
      `${entrou.join(", ")} | abas: ${wb.worksheets.map((s) => s.name).join(", ")}`);
  }

  // …e o documento SEM TIPO que declara DUAS demonstrações é composto de fato:
  // "Demonstrações Contábeis 2025.pdf" (nome que a taxonomia não reconhece)
  // esperando a fila de revisão não deveria custar ao dono a estrutura inteira.
  const V = "vSemTipo";
  const wb = buildExportWorkbook({
    caso: { nome: "Sem tipo", produto: "reestruturacao" },
    documentos: [{
      id: "dSemTipo", tipo_taxonomia: null, entidade: { razao_social: "Alfa Ltda." },
      periodo: { tipo: "anual", referencia: "2025" },
      documento_versao: [{ id: V, nome_original: "Demonstracoes Contabeis 2025.pdf" }],
    }],
    campos: [
      campo({ chave: "Caixa e equivalentes de caixa", secao: "Ativo Circulante", secao_canonica: "ativo_circulante", valor_num: 500, documento_versao_id: V }),
      campo({ chave: "Fornecedores nacionais", secao: "Passivo Circulante", secao_canonica: "passivo_circulante", valor_num: 500, documento_versao_id: V }),
      campo({ chave: "Receita bruta de vendas", secao: "RECEITA OPERACIONAL BRUTA", secao_canonica: "receita_bruta", valor_num: 9000, documento_versao_id: V }),
    ],
    agora: new Date("2026-07-29T12:00:00Z"),
  });
  checar(wb.getWorksheet("Balanço") != null && wb.getWorksheet("DRE") != null,
    "(16j) documento sem tipo que DECLARA duas demonstrações é separado nas duas abas",
    wb.worksheets.map((s) => s.name).join(", "));
}

// ---- 17: reextração SUBSTITUI, não acumula (db/migrations/0026) --------------
// Reextrair é a única forma de um documento já processado pegar prompt/taxonomia
// novos — o dono precisa disso para a DMPL da `0024`. Só que o export lia TODAS
// as versões do documento, e duas extrações do mesmo arquivo não produzem as
// mesmas linhas (é o ponto de mudar o prompt): a conta renomeada aparecia DUAS
// vezes e a soma da seção somava as duas. Dupla contagem por um caminho novo, e
// do pior tipo — as duas linhas têm proveniência legítima, então nada parece
// errado ao abrir a planilha.
{
  const doc = (versoes: Array<{ id: string; nome_original: string | null; n_versao?: number | null }>): DocumentoParaExport => ({
    id: "d1", tipo_taxonomia: "BALANCO", entidade: { razao_social: "Alfa" },
    periodo: { tipo: "anual", referencia: "2025" }, documento_versao: versoes,
  });
  const V1 = "v1", V2 = "v2";
  const linhaDe = (ws: import("exceljs").Worksheet, rot: string) => {
    for (let r = 1; r <= ws.rowCount; r++) if (String(ws.getRow(r).getCell(1).value ?? "") === rot) return r;
    return -1;
  };

  // A extração NOVA renomeia a conta ("Caixa e bancos" → "Caixa e equivalentes de
  // caixa"), que é exatamente o efeito de um prompt novo.
  // Sem linha de total informado de propósito: aí a seção É a nossa soma, e a
  // dupla contagem aparece no número em vez de ficar mascarada pelo total do
  // documento (a regra do PR #50 esconderia o defeito atrás do informado —
  // primeira versão deste invariante passou verde por isso).
  const campos: CampoExtraido[] = [
    campo({ chave: "Caixa e bancos", secao: "Ativo Circulante", valor_num: 1000, documento_versao_id: V1 }),
    campo({ chave: "Caixa e equivalentes de caixa", secao: "Ativo Circulante", valor_num: 1500, documento_versao_id: V2 }),
  ];
  const wb = buildExportWorkbook({
    caso: { nome: "Reextração", produto: "rx" },
    documentos: [doc([{ id: V1, nome_original: "bp.pdf", n_versao: 1 }, { id: V2, nome_original: "bp.pdf", n_versao: 2 }])],
    campos, agora: new Date("2026-07-29T12:00:00Z"),
  });
  const ws = wb.getWorksheet("Balanço")!;
  const rAC = linhaDe(ws, "Ativo Circulante");
  checar(rAC > 0 && Math.round(avaliar(ws, "B", rAC)) === 1500,
    "(17a) reextração não soma com a extração anterior",
    `seção=${rAC > 0 ? Math.round(avaliar(ws, "B", rAC)) : "(ausente)"} documento=1500`);
  checar(linhaDe(ws, "Caixa e bancos") < 0,
    "(17b) a linha da versão substituída não aparece na planilha");

  // …e a substituição não é silenciosa: o Resumo diz que existe extração anterior
  // fora deste export (ela continua no banco, com proveniência, para auditoria).
  const resumo = wb.getWorksheet("Resumo")!;
  let avisa = false;
  for (let r = 1; r <= resumo.rowCount; r++) {
    if (String(resumo.getRow(r).getCell(1).value ?? "").startsWith("Linhas de versão substituída")) avisa = true;
  }
  checar(avisa, "(17c) o Resumo declara a versão substituída (substituir em silêncio seria pior)");

  // PROTEÇÃO: reextração que FALHA volta com ZERO linhas (`extracao_falhou`,
  // db/migrations/0016). Se a vigência fosse cega ao dado, essa falha APAGARIA do
  // book tudo o que a versão anterior extraiu — trocar dupla contagem por perda
  // silenciosa de dado não é conserto.
  const wbFalha = buildExportWorkbook({
    caso: { nome: "Reextração falhou", produto: "rx" },
    documentos: [doc([{ id: V1, nome_original: "bp.pdf", n_versao: 1 }, { id: "v3", nome_original: "bp.pdf", n_versao: 2 }])],
    campos: [campo({ chave: "Caixa e bancos", secao: "Ativo Circulante", valor_num: 1000, documento_versao_id: V1 })],
    agora: new Date("2026-07-29T12:00:00Z"),
  });
  const wsFalha = wbFalha.getWorksheet("Balanço");
  checar(wsFalha != null && linhaDe(wsFalha, "Caixa e bancos") > 0,
    "(17d) reextração que volta VAZIA não apaga o que a versão anterior extraiu");

  // Sem `n_versao` informada não há ordem declarada: manter as duas é o
  // comportamento antigo, e chutar qual é a nova seria pior.
  const wbSemN = buildExportWorkbook({
    caso: { nome: "Sem n_versao", produto: "rx" },
    documentos: [doc([{ id: V1, nome_original: "bp.pdf" }, { id: V2, nome_original: "bp.pdf" }])],
    campos, agora: new Date("2026-07-29T12:00:00Z"),
  });
  const wsSemN = wbSemN.getWorksheet("Balanço")!;
  checar(linhaDe(wsSemN, "Caixa e bancos") > 0 && linhaDe(wsSemN, "Caixa e equivalentes de caixa") > 0,
    "(17e) sem n_versao declarada, nada é descartado por chute");

  // E o caso normal (uma versão por documento, como todo o book) não muda.
  const fixture = JSON.parse(
    readFileSync(new URL("./fixtures/book-vertentes.json", import.meta.url), "utf8"),
  ) as { documentos: DocumentoParaExport[]; campos: CampoExtraido[] };
  const wbBook = buildExportWorkbook({
    caso: { nome: "Book Vertentes", produto: "reestruturacao" },
    documentos: fixture.documentos, campos: fixture.campos,
    agora: new Date("2026-07-29T12:00:00Z"),
  });
  const resumoBook = wbBook.getWorksheet("Resumo")!;
  let totalBook = 0;
  for (let r = 1; r <= resumoBook.rowCount; r++) {
    if (String(resumoBook.getRow(r).getCell(1).value ?? "") === "Linhas totais extraídas") {
      totalBook = Number(resumoBook.getRow(r).getCell(2).value ?? 0);
    }
  }
  checar(totalBook === fixture.campos.length,
    "(17f) documento de versão única (o book inteiro) não perde nenhuma linha",
    `resumo=${totalBook} fixture=${fixture.campos.length}`);
}

// ---- 18: o teste v28 — buraco silencioso deixa de ser silencioso ------------
// Três achados do v28, e o que os une é que o arquivo NÃO CONTAVA o que faltava:
//   • a extração da DRE falhou (rate limit 429) e a aba simplesmente NÃO EXISTIU;
//   • a `0025` não estava aplicada no projeto em uso, então não havia índice
//     macro — e a aba Macro também não existiu ("os índices não vieram");
//   • sete abas de apoio estavam OCULTAS e foram lidas como "não vieram".
// Nenhum dos três era um número errado: eram ausências indistinguíveis de defeito.
{
  const V = "vSoBalanco";
  const wb = buildExportWorkbook({
    caso: { nome: "v28", produto: "reestruturacao" },
    documentos: [
      { id: "dBP", tipo_taxonomia: "BALANCO", entidade: { razao_social: "Alfa Ltda." },
        periodo: { tipo: "anual", referencia: "2025" },
        documento_versao: [{ id: V, nome_original: "01_BP_Alfa.pdf" }] },
      // …e a DRE que CHEGOU e não extraiu nada (o caso do v28).
      { id: "dDRE", tipo_taxonomia: "DRE", entidade: { razao_social: "Alfa Ltda." },
        periodo: { tipo: "anual", referencia: "2025" },
        documento_versao: [{ id: "vDreFalhou", nome_original: "07_DRE_Alfa.pdf" }] },
    ],
    campos: [
      campo({ chave: "Caixa e bancos", secao: "Ativo Circulante", valor_num: 500, documento_versao_id: V }),
      campo({ chave: "TOTAL DO ATIVO", secao: "ATIVO", valor_num: 500, documento_versao_id: V }),
      campo({ chave: "Fornecedores nacionais", secao: "Passivo Circulante", valor_num: 500, documento_versao_id: V }),
    ],
    agora: new Date("2026-07-29T12:00:00Z"),
  });

  const nomes = wb.worksheets.map((s) => s.name);
  checar(nomes.includes("DRE") && nomes.includes("Fluxo de Caixa"),
    "(18a) as três demonstrações principais existem sempre, com dado ou sem", nomes.join(", "));

  const textoDe = (nome: string) => {
    const ws = wb.getWorksheet(nome);
    const out: string[] = [];
    if (ws) for (let r = 1; r <= ws.rowCount; r++) {
      for (let c = 1; c <= 2; c++) out.push(String(ws.getRow(r).getCell(c).value ?? ""));
    }
    return out;
  };
  const textoDRE = textoDe("DRE");
  checar(textoDRE.some((t) => t.includes("07_DRE_Alfa.pdf")),
    "(18b) a aba sem dado NOMEIA o documento que chegou e não extraiu",
    textoDRE.filter(Boolean).join(" | ").slice(0, 160));
  const textoFluxo = textoDe("Fluxo de Caixa");
  checar(textoFluxo.some((t) => t.includes("Nenhum documento")),
    "(18c) …e distingue 'não entregue' de 'entregue e não extraído'",
    textoFluxo.filter(Boolean).join(" | ").slice(0, 160));

  // O Resumo conta os documentos que ficaram de fora — antes ele só contava as
  // linhas que entraram, que é meia informação.
  const resumo = wb.getWorksheet("Resumo")!;
  let linhaSemLinha = "";
  for (let r = 1; r <= resumo.rowCount; r++) {
    if (String(resumo.getRow(r).getCell(1).value ?? "").startsWith("Documentos SEM linha")) {
      linhaSemLinha = String(resumo.getRow(r).getCell(2).value ?? "");
    }
  }
  checar(linhaSemLinha.includes("07_DRE_Alfa.pdf"),
    "(18d) o Resumo declara os documentos sem nenhuma linha extraída", linhaSemLinha.slice(0, 120));

  // Sem índice coletado, a aba Macro existe e diz o que falta.
  const macro = wb.getWorksheet("Macro");
  const textoMacro = textoDe("Macro");
  checar(macro != null && textoMacro.some((t) => t.includes("workflow.macro.json")),
    "(18e) sem índice coletado, a aba Macro existe e diz o que falta",
    macro ? textoMacro.filter(Boolean).join(" | ").slice(0, 140) : "(sem aba Macro)");
}

// ---- 19: seção sem total informado é DECLARADA como nossa soma ---------------
// O defeito numérico do v28: a VT Logística saiu com Ativo Circulante 7.254 onde
// o documento diz 3.961 — "Contas a Receber" (3.293) somada JUNTO com "Fretes a
// receber" (3.562) e "(-) PECLD" (−269), que são os componentes dela. O documento
// imprime o total da seção, mas a extração daquele arquivo não o trouxe, e sem
// total informado não existe linha de checagem: o número errado não tinha como
// ser percebido. Enquanto a detecção de hierarquia não melhorar (exige ORDEM do
// documento, que hoje não é persistida — fatia própria), o mínimo é o número não
// passar por conferido.
{
  const V = "vSemTotal";
  const wb = buildExportWorkbook({
    caso: { nome: "Sem total informado", produto: "rx" },
    documentos: [{
      id: "dST", tipo_taxonomia: "BALANCO", entidade: { razao_social: "VT Logística Ltda." },
      periodo: { tipo: "anual", referencia: "2025" },
      documento_versao: [{ id: V, nome_original: "04_BP_VT_Logistica.pdf" }],
    }],
    // Exatamente o padrão do v28: subtotal de agrupamento e seus componentes na
    // mesma seção, e NENHUMA linha de total do Ativo Circulante.
    campos: [
      campo({ chave: "Disponível", secao: "Ativo Circulante", valor_num: 358, documento_versao_id: V }),
      campo({ chave: "Contas a Receber", secao: "Ativo Circulante", valor_num: 3293, documento_versao_id: V }),
      campo({ chave: "Fretes a receber", secao: "Ativo Circulante", valor_num: 3562, documento_versao_id: V }),
      campo({ chave: "(-) PECLD", secao: "Ativo Circulante", valor_num: -269, documento_versao_id: V }),
      campo({ chave: "Fornecedores nacionais", secao: "Passivo Circulante", valor_num: 5070, documento_versao_id: V }),
    ],
    agora: new Date("2026-07-29T12:00:00Z"),
  });
  const bal = wb.getWorksheet("Balanço")!;
  let rAC = -1;
  for (let r = 1; r <= bal.rowCount; r++) {
    if (String(bal.getRow(r).getCell(1).value ?? "") === "Ativo Circulante") rAC = r;
  }
  const cell = rAC > 0 ? bal.getRow(rAC).getCell(2) : null;
  const temInformado = (() => {
    for (let r = 1; r <= bal.rowCount; r++) {
      if (String(bal.getRow(r).getCell(1).value ?? "").includes("total informado")
        && bal.getRow(r).getCell(2).value != null) return true;
    }
    return false;
  })();
  checar(!temInformado, "(19a) o cenário é o do v28 mesmo: seção sem total informado");
  checar(!!cell?.note, "(19b) seção cujo número é a NOSSA soma carrega a ressalva na célula");
  const nota = JSON.stringify(cell?.note ?? "");
  checar(nota.includes("dupla contagem"),
    "(19c) …e a ressalva nomeia o risco (dupla contagem de subtotal)", nota.slice(0, 120));
}

// ---- 17: subtotal reconhecido pela ORDEM do documento ----------------------
// Modo de falha REAL do teste v28 (VT Logística): a seção saiu com Ativo
// Circulante 7.254 onde o documento diz 3.961, porque "Contas a Receber"
// (3.293) foi somada JUNTO com "Fretes a receber" (3.562) e "(-) PECLD" (−269),
// que são os seus componentes.
//
// Por que a detecção existente não pega: (A) exige que alguma linha declare
// `secao` = "Contas a Receber", e a extração daquele arquivo anotou a seção de
// TOPO em todas; (B) exige que o valor bata com a soma dos irmãos da MESMA
// seção, e os irmãos ali são o circulante inteiro. E não havia linha de "total
// informado" para a conferência acusar — o número errado não tinha como ser
// percebido.
//
// O sinal que sobra é o que qualquer demonstração impressa dá: o subtotal vem
// IMEDIATAMENTE ANTES dos seus componentes. Isso exige ORDEM persistida.
{
  const V = "vOrdem";
  // Ordem do documento, como o PDF imprime (subtotal acima, componentes abaixo).
  const linhas: Array<[string, number]> = [
    ["Caixa e bancos", 399],
    ["Contas a Receber", 3293],      // ← subtotal impresso
    ["Fretes a receber", 3562],      //   componente
    ["(-) PECLD", -269],             //   componente
    ["Despesas antecipadas", 269],
  ];
  const AC_CORRETO = 399 + 3293 + 269; // 3.961 — o que o documento diz
  const campos: CampoExtraido[] = linhas.map(([chave, v], i) =>
    campo({ chave, secao: "Ativo Circulante", valor_num: v, ordem: i, documento_versao_id: V }));

  const documentos: DocumentoParaExport[] = [{
    id: "dOrdem", tipo_taxonomia: "BALANCO", entidade: { razao_social: "VT Logística" },
    periodo: { tipo: "anual", referencia: "2024" },
    documento_versao: [{ id: V, nome_original: "04_BP_VT_Logistica.pdf" }],
  }];
  const ws = buildExportWorkbook({
    caso: { nome: "C", produto: "rx" }, documentos, campos, agora: new Date("2026-07-29T12:00:00Z"),
  }).getWorksheet("Balanço")!;

  let rAC = -1;
  for (let r = 1; r <= ws.rowCount; r++) {
    if (String(ws.getRow(r).getCell(1).value ?? "") === "Ativo Circulante") { rAC = r; break; }
  }
  const soma = Math.round(avaliar(ws, "B", rAC));
  checar(soma === AC_CORRETO,
    "(17) subtotal impresso ACIMA dos componentes não é somado junto",
    `seção=${soma} documento=${AC_CORRETO} (somando o subtotal daria ${AC_CORRETO + 3293})`);

  // …e ele continua VISÍVEL: nada é escondido para o número fechar.
  const rotulos: string[] = [];
  for (let r = 1; r <= ws.rowCount; r++) rotulos.push(String(ws.getRow(r).getCell(1).value ?? ""));
  checar(rotulos.some((x) => x.includes("subtotal informado")),
    "(17) o subtotal detectado pela ordem continua visível na planilha");

  // NEGATIVO: sem a ordem, o mesmo dado tem de voltar a errar — é o que prova
  // que a correção vem da ordem, e não de outro sinal por acaso.
  const semOrdem = linhas.map(([chave, v]) =>
    campo({ chave, secao: "Ativo Circulante", valor_num: v, documento_versao_id: V }));
  const wsSem = buildExportWorkbook({
    caso: { nome: "C", produto: "rx" }, documentos, campos: semOrdem,
    agora: new Date("2026-07-29T12:00:00Z"),
  }).getWorksheet("Balanço")!;
  let rAC2 = -1;
  for (let r = 1; r <= wsSem.rowCount; r++) {
    if (String(wsSem.getRow(r).getCell(1).value ?? "") === "Ativo Circulante") { rAC2 = r; break; }
  }
  checar(Math.round(avaliar(wsSem, "B", rAC2)) !== AC_CORRETO,
    "(17) sem ordem persistida o defeito reaparece (a correção vem da ORDEM)");
}

// ---- 18: o caso REAL da Componentes (teste v29) -----------------------------
// Números do `.xlsx` do dono. O Ativo Circulante saiu 29.990 onde o documento
// diz 15.200 — 14.790 de dupla contagem, e o balanço da empresa inteiro estava
// contaminado (PC saiu exatamente 2× o informado). O documento é um BP
// detalhado de 4 níveis: ele IMPRIME o subtotal de cada subseção e, embaixo, os
// componentes. A extração anotou a seção de TOPO em todas as linhas, então
// nenhuma das duas detecções estruturais tinha sinal.
//
// Este bloco cobre os dois formatos de subtotal que aparecem no mesmo arquivo:
// com VÁRIOS componentes ("Estoques" = 3 contas) e com UM só ("Outros Créditos"
// = "Adiantamentos diversos"), que exige o segundo sinal do rótulo ser nome de
// agrupamento — sem ele, ficavam 340 de dupla contagem.
{
  const V = "vComponentes";
  const linhas: Array<[string, number]> = [
    ["Disponível", 410],
    ["Contas a Receber", 8420],
    ["Clientes - mercado interno", 9240],
    ["(-) PECLD", -820],
    ["Estoques", 5100],
    ["Matéria-prima", 3180],
    ["Produtos acabados", 2260],
    ["(-) Provisão para perdas em estoques", -340],
    ["Tributos a Recuperar", 930],
    ["ICMS a recuperar", 520],
    ["PIS/COFINS a compensar", 410],
    ["Outros Créditos", 340],
    ["Adiantamentos diversos", 340],
  ];
  const AC_DOCUMENTO = 15200;
  const campos: CampoExtraido[] = linhas.map(([chave, v], i) =>
    campo({ chave, secao: "Ativo Circulante", valor_num: v, ordem: i, documento_versao_id: V }));
  const documentos: DocumentoParaExport[] = [{
    id: "dComp", tipo_taxonomia: "BALANCO",
    entidade: { razao_social: "VERTENTES COMPONENTES AUTOMOTIVOS LTDA." },
    periodo: { tipo: "anual", referencia: "2024" },
    documento_versao: [{ id: V, nome_original: "02_BP_Vertentes_Componentes_2025x2024.pdf" }],
  }];
  const ws = buildExportWorkbook({
    caso: { nome: "C", produto: "rx" }, documentos, campos, agora: new Date("2026-07-29T12:00:00Z"),
  }).getWorksheet("Balanço")!;
  let rAC = -1;
  for (let r = 1; r <= ws.rowCount; r++) {
    if (String(ws.getRow(r).getCell(1).value ?? "") === "Ativo Circulante") { rAC = r; break; }
  }
  const soma = Math.round(avaliar(ws, "B", rAC));
  checar(soma === AC_DOCUMENTO,
    "(18) BP detalhado: o Ativo Circulante bate com o documento",
    `export=${soma} documento=${AC_DOCUMENTO} (sem o conserto dava 29.990)`);

  // O subtotal de UM componente é o que exige o sinal do rótulo. Se ele
  // escapar, sobram exatamente 340 — este número é o teste.
  checar(soma !== AC_DOCUMENTO + 340,
    "(18) subtotal com UM único componente também é reconhecido (senão sobram 340)");
}

// ---- 20: "consulta falhou" NÃO é a mesma mensagem de "sem dado coletado" ----
// Achado no teste v29 (0028): a base tinha índice macro gravado, mas a consulta
// do portal falhava por autorização (RLS sem policy, ou RPC sem grant) — e o
// export dizia "sem dado coletado", como se a coleta nunca tivesse rodado.
// `route.ts` engolia `.error` das duas consultas com `?? []`. Confundir "tentei
// e deu erro" com "tentei e não achei nada" é o próprio padrão que este export
// existe para não repetir (a mesma classe do "total informado" vs "nossa soma").
{
  const wbErro = buildExportWorkbook({
    caso: { nome: "Erro macro", produto: "rx" },
    documentos: [{
      id: "d1", tipo_taxonomia: "BALANCO", entidade: { razao_social: "Alfa" },
      periodo: { tipo: "anual", referencia: "2025" },
      documento_versao: [{ id: "v1", nome_original: "bp.pdf" }],
    }],
    campos: [campo({ chave: "Caixa", secao: "Ativo Circulante", valor_num: 100, documento_versao_id: "v1" })],
    macroErro: "permission denied for table indice_macro_obs",
    agora: new Date("2026-07-29T12:00:00Z"),
  });
  const macroComErro = wbErro.getWorksheet("Macro");
  const textoErro: string[] = [];
  if (macroComErro) for (let r = 1; r <= macroComErro.rowCount; r++) {
    for (let c = 1; c <= 2; c++) textoErro.push(String(macroComErro.getRow(r).getCell(c).value ?? ""));
  }
  const tituloErro = String(macroComErro?.getRow(1).getCell(1).value ?? "");
  checar(macroComErro != null && tituloErro.includes("CONSULTA falhou"),
    "(20a) erro de consulta vira uma aba PRÓPRIA, distinta de 'sem dado coletado'", tituloErro);
  checar(textoErro.some((t) => t.includes("permission denied for table indice_macro_obs")),
    "(20b) a mensagem de erro real aparece na aba (não é genérica)");
  // O TÍTULO é o sinal que distingue as duas causas (o corpo pode CITAR a outra
  // frase de propósito, como contraste explícito — "isto é diferente de X").
  checar(!tituloErro.includes("sem dado coletado"),
    "(20c) …e o título NÃO usa a frase de 'sem dado coletado' (confundiria as duas causas)", tituloErro);

  // Sem erro, a mensagem antiga continua — é o caso genuinamente vazio.
  const wbVazio = buildExportWorkbook({
    caso: { nome: "Vazio macro", produto: "rx" },
    documentos: [{
      id: "d1", tipo_taxonomia: "BALANCO", entidade: { razao_social: "Alfa" },
      periodo: { tipo: "anual", referencia: "2025" },
      documento_versao: [{ id: "v1", nome_original: "bp.pdf" }],
    }],
    campos: [campo({ chave: "Caixa", secao: "Ativo Circulante", valor_num: 100, documento_versao_id: "v1" })],
    agora: new Date("2026-07-29T12:00:00Z"),
  });
  const macroVazio = wbVazio.getWorksheet("Macro");
  const textoVazio: string[] = [];
  if (macroVazio) for (let r = 1; r <= macroVazio.rowCount; r++) {
    for (let c = 1; c <= 2; c++) textoVazio.push(String(macroVazio.getRow(r).getCell(c).value ?? ""));
  }
  checar(textoVazio.some((t) => t.includes("sem dado coletado")),
    "(20d) sem macroErro, a mensagem genuína de ausência continua",
    textoVazio.filter(Boolean).join(" | ").slice(0, 140));
}

// ---- 21: a CAUSA da falha de extração aparece no book ------------------------
// Teste v30: 14 de 14 documentos sem linha extraída. O Resumo listava os nomes —
// e a causa (que a pendência JÁ registrava) ficava só na fila de revisão, em
// outra tela. As causas possíveis pedem ações opostas (crédito da OpenAI, cota do
// dia, cadência), então listar o arquivo sem a causa é meia informação.
{
  const V = "vFalhou";
  const wb = buildExportWorkbook({
    caso: { nome: "v30", produto: "reestruturacao" },
    documentos: [{
      id: "dBP", tipo_taxonomia: "BALANCO", entidade: { razao_social: "Alfa Ltda." },
      periodo: { tipo: "anual", referencia: "2025" },
      documento_versao: [{ id: V, nome_original: "01_BP_Alfa.pdf" }],
    }],
    campos: [],
    causasDeFalha: [
      "CRÉDITO DA OPENAI ESGOTADO (insufficient_quota). A conta não tem saldo. "
      + "Espaçar as chamadas NÃO resolve isto.",
    ],
    agora: new Date("2026-07-30T12:00:00Z"),
  });
  const resumo = wb.getWorksheet("Resumo")!;
  const linhas: Array<[string, string]> = [];
  for (let r = 1; r <= resumo.rowCount; r++) {
    linhas.push([
      String(resumo.getRow(r).getCell(1).value ?? ""),
      String(resumo.getRow(r).getCell(2).value ?? ""),
    ]);
  }
  const rotulos = linhas.map(([a]) => a);
  checar(rotulos.some((x) => x.startsWith("Documentos SEM linha")),
    "(21a) o Resumo conta os documentos sem linha extraída", rotulos.filter(Boolean).join(" | ").slice(0, 120));
  const causa = linhas.find(([a]) => a === "↳ causa registrada")?.[1] ?? "";
  checar(causa.includes("CRÉDITO DA OPENAI ESGOTADO"),
    "(21b) …e a CAUSA registrada na pendência aparece junto", causa.slice(0, 120));
  checar(causa.includes("NÃO resolve"),
    "(21c) …inclusive o que NÃO resolve (senão a ação óbvia é a errada)");

  // Sem causa informada, nada de linha vazia inventada.
  const wbSemCausa = buildExportWorkbook({
    caso: { nome: "v30", produto: "reestruturacao" },
    documentos: [{
      id: "dBP", tipo_taxonomia: "BALANCO", entidade: { razao_social: "Alfa Ltda." },
      periodo: { tipo: "anual", referencia: "2025" },
      documento_versao: [{ id: V, nome_original: "01_BP_Alfa.pdf" }],
    }],
    campos: [],
    agora: new Date("2026-07-30T12:00:00Z"),
  });
  const resumoSem = wbSemCausa.getWorksheet("Resumo")!;
  let temCausaVazia = false;
  for (let r = 1; r <= resumoSem.rowCount; r++) {
    if (String(resumoSem.getRow(r).getCell(1).value ?? "") === "↳ causa registrada") temCausaVazia = true;
  }
  checar(!temCausaVazia, "(21d) sem causa registrada, o Resumo não inventa a linha");
}

// ---- 22: ESCALA MISTA — o bug de ~496x ------------------------------------
// A fixture `campo()` fixa `unidade: null`, e nenhum dos 126 invariantes
// anteriores mencionava escala. Era por isso que o defeito mais caro do export
// passava verde: um Balanço em MILHAR somado a um Balancete em UNIDADE na mesma
// coluna somava valor cru, sem nenhuma marca de divergência.
{
  const V1 = "esc-milhar";
  const V2 = "esc-unidade";
  const documentos: DocumentoParaExport[] = [
    {
      id: "d-esc-1", tipo_taxonomia: "BALANCO", status: "em_validacao",
      entidade: { razao_social: "Alfa Ltda." }, periodo: { tipo: "anual", referencia: "12M25" },
      documento_versao: [{ id: V1, n_versao: 1, nome_original: "BP Alfa 2025.pdf" }],
    } as unknown as DocumentoParaExport,
    {
      // MESMO tipo e mesma entidade/período que o d-esc-1: é o que faz as duas
      // fontes caírem na MESMA coluna da MESMA aba, que é onde a soma quebrava.
      // Cenário real: um BP e uma DF auditada da mesma empresa, cada arquivo
      // declarando a escala do seu jeito.
      id: "d-esc-2", tipo_taxonomia: "BALANCO", status: "em_validacao",
      entidade: { razao_social: "Alfa Ltda." }, periodo: { tipo: "anual", referencia: "12M25" },
      documento_versao: [{ id: V2, n_versao: 1, nome_original: "DF Auditada Alfa 2025.pdf" }],
    } as unknown as DocumentoParaExport,
  ];
  // Mesmos R$ 27,9 milhões escritos em escalas diferentes: 27.900 em milhar e
  // 27.900.000 em unidade. Depois da normalização os dois têm de valer o MESMO.
  const campos: CampoExtraido[] = [
    campo({ documento_versao_id: V1, chave: "Disponibilidades", secao: "Disponível", valor_num: 500, unidade: "milhar", ordem: 0 }),
    campo({ documento_versao_id: V1, chave: "Duplicatas a receber", secao: "Contas a Receber", valor_num: 27900, unidade: "milhar", ordem: 1 }),
    campo({ documento_versao_id: V2, chave: "Clientes nacionais", secao: "Contas a Receber", valor_num: 27_900_000, unidade: "unidade", ordem: 0 }),
  ];
  const wb = buildExportWorkbook({ caso: { nome: "C", produto: "rx" }, documentos, campos, agora: new Date("2026-07-27T12:00:00Z") });
  const ws = wb.getWorksheet("Balanço")!;
  const linhaDe = (rot: string) => {
    for (let r = 1; r <= ws.rowCount; r++) if (String(ws.getRow(r).getCell(1).value ?? "") === rot) return r;
    return -1;
  };
  // O que o valor em unidade tem de virar depois de convertido para milhar.
  const rClientes = linhaDe("Clientes nacionais");
  checar(rClientes > 0, "(22a) a linha em escala 'unidade' aparece na aba");
  const vClientes = rClientes > 0 ? avaliar(ws, "B", rClientes) : NaN;
  checar(
    Math.abs(vClientes - 27900) < 0.01,
    "(22b) valor em unidade é CONVERTIDO para a escala do book (27.900.000 → 27.900)",
    `obteve ${vClientes}`,
  );
  // E a soma da seção fecha na escala única. Antes: 500 + 27.900 + 27.900.000.
  const rAC = linhaDe("Ativo Circulante");
  const soma = avaliar(ws, "B", rAC);
  checar(
    Math.abs(soma - 56300) < 0.01,
    "(22c) soma com escalas mistas fecha na escala única (era erro de ~496x)",
    `obteve ${soma}, esperado 56300`,
  );
  // A conversão fica DECLARADA na nota da célula — número convertido sem rastro
  // é número que ninguém consegue conferir contra o PDF.
  const nota = notaDaLinha(ws, rClientes);
  checar(/convertido de/i.test(nota), "(22d) a nota da célula declara a conversão de escala", nota.slice(0, 120));
}

// ---- 23: escala não declarada não é convertida às cegas --------------------
// `unidade: null` significa "o documento não disse". Assumir 'unidade' aí seria
// inventar um fator de 1000x justamente onde não se sabe — e o comentário da
// fonte de `normalizarUnidade` diz que "errar em 1000x é pior que não saber".
{
  const V = "esc-null";
  const documentos: DocumentoParaExport[] = [{
    id: "d-esc-3", tipo_taxonomia: "BALANCO", status: "em_validacao",
    entidade: { razao_social: "Beta Ltda." }, periodo: { tipo: "anual", referencia: "12M25" },
    documento_versao: [{ id: V, n_versao: 1, nome_original: "BP Beta.pdf" }],
  } as unknown as DocumentoParaExport];
  const campos: CampoExtraido[] = [
    campo({ documento_versao_id: V, chave: "Disponibilidades", secao: "Disponível", valor_num: 500, unidade: "milhar", ordem: 0 }),
    campo({ documento_versao_id: V, chave: "Outros créditos", secao: "Disponível", valor_num: 300, unidade: null, ordem: 1 }),
  ];
  const ws = buildExportWorkbook({ caso: { nome: "C", produto: "rx" }, documentos, campos, agora: new Date("2026-07-27T12:00:00Z") })
    .getWorksheet("Balanço")!;
  const linhaDe = (rot: string) => {
    for (let r = 1; r <= ws.rowCount; r++) if (String(ws.getRow(r).getCell(1).value ?? "") === rot) return r;
    return -1;
  };
  const rOutros = linhaDe("Outros créditos");
  checar(Math.abs(avaliar(ws, "B", rOutros) - 300) < 0.01, "(23a) valor sem escala declarada NÃO é convertido");
  const nota = notaDaLinha(ws, rOutros);
  checar(/NÃO declarada/i.test(nota), "(23b) a nota diz que a escala não foi declarada, em vez de omitir", nota.slice(0, 120));
}

// ---- 24: o Resumo DECLARA a escala e o que não deu para converter ---------
// Uma planilha financeira sem escala declarada é uma planilha que alguém vai ler
// errado — e este book não declarava escala em lugar nenhum.
{
  const V1 = "res-esc-1";
  const V2 = "res-esc-2";
  const doc = (id: string, ver: string, nome: string): DocumentoParaExport => ({
    id, tipo_taxonomia: "BALANCO", status: "em_validacao",
    entidade: { razao_social: "Gama Ltda." }, periodo: { tipo: "anual", referencia: "12M25" },
    documento_versao: [{ id: ver, n_versao: 1, nome_original: nome }],
  } as unknown as DocumentoParaExport);
  const campos: CampoExtraido[] = [
    campo({ documento_versao_id: V1, chave: "Disponibilidades", secao: "Disponível", valor_num: 500, unidade: "milhar", ordem: 0 }),
    campo({ documento_versao_id: V1, chave: "Duplicatas a receber", secao: "Contas a Receber", valor_num: 27900, unidade: "milhar", ordem: 1 }),
    campo({ documento_versao_id: V2, chave: "Clientes nacionais", secao: "Contas a Receber", valor_num: 27_900_000, unidade: "unidade", ordem: 0 }),
    campo({ documento_versao_id: V2, chave: "Outros créditos", secao: "Contas a Receber", valor_num: 300, unidade: null, ordem: 1 }),
  ];
  const resumo = buildExportWorkbook({
    caso: { nome: "C", produto: "rx" },
    documentos: [doc("d-res-1", V1, "BP.pdf"), doc("d-res-2", V2, "DF.pdf")],
    campos, agora: new Date("2026-07-27T12:00:00Z"),
  }).getWorksheet("Resumo")!;

  const valorDe = (rot: string) => {
    for (let r = 1; r <= resumo.rowCount; r++) {
      if (String(resumo.getRow(r).getCell(1).value ?? "") === rot) return String(resumo.getRow(r).getCell(2).value ?? "");
    }
    return "";
  };
  checar(/R\$ mil/.test(valorDe("Escala dos valores")), "(24a) o Resumo declara a escala do book", valorDe("Escala dos valores"));
  checar(/^1 linha\(s\)/.test(valorDe("↳ valores convertidos de escala")), "(24b) o Resumo diz quantas linhas foram convertidas", valorDe("↳ valores convertidos de escala"));
  checar(/^1 —/.test(valorDe("↳ linhas sem escala declarada")), "(24c) o Resumo declara o que NÃO deu para converter", valorDe("↳ linhas sem escala declarada"));
}

// ---- 25: sem escala nenhuma declarada, nada muda --------------------------
// Regressão: a maioria dos documentos reais não declara escala, e o export
// precisa continuar saindo exatamente como saía. Um fix de escala que mexe em
// número onde não havia escala seria pior que o bug.
{
  const V = "res-esc-none";
  const documentos: DocumentoParaExport[] = [{
    id: "d-none", tipo_taxonomia: "BALANCO", status: "em_validacao",
    entidade: { razao_social: "Delta Ltda." }, periodo: { tipo: "anual", referencia: "12M25" },
    documento_versao: [{ id: V, n_versao: 1, nome_original: "BP.pdf" }],
  } as unknown as DocumentoParaExport];
  const campos: CampoExtraido[] = [
    campo({ documento_versao_id: V, chave: "Disponibilidades", secao: "Disponível", valor_num: 1240, ordem: 0 }),
    campo({ documento_versao_id: V, chave: "Aplicações financeiras", secao: "Disponível", valor_num: 3600, ordem: 1 }),
  ];
  const wb = buildExportWorkbook({ caso: { nome: "C", produto: "rx" }, documentos, campos, agora: new Date("2026-07-27T12:00:00Z") });
  const ws = wb.getWorksheet("Balanço")!;
  const linhaDe = (rot: string) => {
    for (let r = 1; r <= ws.rowCount; r++) if (String(ws.getRow(r).getCell(1).value ?? "") === rot) return r;
    return -1;
  };
  checar(Math.abs(avaliar(ws, "B", linhaDe("Disponibilidades")) - 1240) < 0.01, "(25a) sem escala declarada, o valor sai intacto");
  checar(Math.abs(avaliar(ws, "B", linhaDe("Ativo Circulante")) - 4840) < 0.01, "(25b) e a soma também");
}

// ---- 26: conta de RESULTADO nunca fica no balanço --------------------------
// `ATIVO_CIRC_KW` contém "mercadoria" (porque no balanço "Mercadorias para
// revenda" é estoque), e por isso a TOP LINE da DRE caía no Ativo Circulante —
// não em "Não Classificadas": era classificada ATIVAMENTE errada, e o roteamento
// não salvava porque `classificarBalanco` "reconhecia" a linha. Alvo direto de
// balancete analítico, onde contas de resultado e de balanço convivem.
{
  const V = "bal-analitico";
  const documentos: DocumentoParaExport[] = [{
    id: "d-ba", tipo_taxonomia: "BALANCETE", status: "em_validacao",
    entidade: { razao_social: "Épsilon Ltda." }, periodo: { tipo: "anual", referencia: "12M25" },
    documento_versao: [{ id: V, n_versao: 1, nome_original: "Balancete Analitico.pdf" }],
  } as unknown as DocumentoParaExport];
  const campos: CampoExtraido[] = [
    campo({ documento_versao_id: V, chave: "Mercadorias para revenda", secao: "Estoques", valor_num: 12400, ordem: 0 }),
    campo({ documento_versao_id: V, chave: "Receita de Vendas de Mercadorias", secao: "RECEITAS", valor_num: 98000, ordem: 1 }),
    campo({ documento_versao_id: V, chave: "Custo das Mercadorias Vendidas", secao: "CUSTOS", valor_num: -61000, ordem: 2 }),
  ];
  const wb = buildExportWorkbook({ caso: { nome: "C", produto: "rx" }, documentos, campos, agora: new Date("2026-07-27T12:00:00Z") });
  const rotulosDe = (aba: string) => {
    const ws = wb.getWorksheet(aba);
    if (!ws) return [] as string[];
    const out: string[] = [];
    for (let r = 1; r <= ws.rowCount; r++) out.push(String(ws.getRow(r).getCell(1).value ?? ""));
    return out;
  };
  const naDRE = rotulosDe("DRE");
  const noBalancete = rotulosDe("Balancete");
  checar(naDRE.includes("Receita de Vendas de Mercadorias"), "(26a) a top line da DRE vai para a aba DRE");
  checar(naDRE.includes("Custo das Mercadorias Vendidas"), "(26b) o CMV vai para a aba DRE");
  checar(!noBalancete.includes("Receita de Vendas de Mercadorias"), "(26c) e NÃO fica no balancete somada ao Ativo Circulante");
  // O estoque, que legitimamente tem "mercadoria" no rótulo, continua no balanço.
  checar(noBalancete.includes("Mercadorias para revenda"), "(26d) estoque com 'mercadoria' no rótulo segue sendo conta de balanço");
}

// ---- 27: imobilizado/intangível alcançáveis SÓ pelo rótulo ----------------
// `subgrupoNaoCirculante` só era chamado depois de casar `ATIVO_NAO_CIRC_KW`, que
// não continha veículo/máquina/terreno/software. Metade de `IMOBILIZADO_KW` e de
// `INTANGIVEL_KW` era código morto: sem a subseção anotada, o imobilizado inteiro
// ia para "Contas Não Classificadas" — fora de toda soma e de todo indicador.
{
  const V = "imob";
  const documentos: DocumentoParaExport[] = [{
    id: "d-imob", tipo_taxonomia: "BALANCO", status: "em_validacao",
    entidade: { razao_social: "Zeta Ltda." }, periodo: { tipo: "anual", referencia: "12M25" },
    documento_versao: [{ id: V, n_versao: 1, nome_original: "BP Zeta.pdf" }],
  } as unknown as DocumentoParaExport];
  // secao: null de propósito — é o caso do balancete analítico que não anota subseção.
  const campos: CampoExtraido[] = [
    campo({ documento_versao_id: V, chave: "Veículos", valor_num: 1800, ordem: 0 }),
    campo({ documento_versao_id: V, chave: "Máquinas e Equipamentos", valor_num: 9400, ordem: 1 }),
    campo({ documento_versao_id: V, chave: "Terrenos", valor_num: 5000, ordem: 2 }),
    campo({ documento_versao_id: V, chave: "Software", valor_num: 700, ordem: 3 }),
  ];
  const ws = buildExportWorkbook({ caso: { nome: "C", produto: "rx" }, documentos, campos, agora: new Date("2026-07-27T12:00:00Z") })
    .getWorksheet("Balanço")!;
  const rotulos: string[] = [];
  let rNaoClass = -1;
  for (let r = 1; r <= ws.rowCount; r++) {
    const rot = String(ws.getRow(r).getCell(1).value ?? "");
    rotulos.push(rot);
    if (/N[ãa]o Classificad/i.test(rot)) rNaoClass = r;
  }
  const linhaDe = (rot: string) => rotulos.indexOf(rot) + 1;
  for (const bem of ["Veículos", "Máquinas e Equipamentos", "Terrenos"]) {
    const r = linhaDe(bem);
    checar(r > 0 && (rNaoClass < 0 || r < rNaoClass), `(27) "${bem}" entra no Imobilizado, não em Não Classificadas`);
  }
  const rSoft = linhaDe("Software");
  checar(rSoft > 0 && (rNaoClass < 0 || rSoft < rNaoClass), '(27) "Software" entra no Intangível, não em Não Classificadas');
  // E entra na SOMA: ficar fora dela era o custo real de cair em Não Classificadas.
  const rANC = linhaDe("Ativo Não Circulante");
  if (rANC > 0) {
    const soma = avaliar(ws, "B", rANC);
    checar(Math.abs(soma - 16900) < 0.01, "(27b) os quatro bens entram na soma do Ativo Não Circulante", `obteve ${soma}`);
  } else {
    checar(false, "(27b) a aba tem seção de Ativo Não Circulante");
  }
}

// ---- 28: as médias macro AVALIAM para número (não só têm a fórmula certa) ---
// Os 17 asserts que tocavam macro eram TODOS textuais sobre a fórmula, e é por
// isso que o defeito da janela passou verde por tanto tempo: a fórmula estava
// "certa" e o resultado era branco. O harness tem avaliador desde sempre.
{
  const V = "macro-med";
  const documentos: DocumentoParaExport[] = [{
    id: "d-mm", tipo_taxonomia: "BALANCO", status: "em_validacao",
    entidade: { razao_social: "Ômega Ltda." }, periodo: { tipo: "anual", referencia: "12M25" },
    documento_versao: [{ id: V, n_versao: 1, nome_original: "BP.pdf" }],
  } as unknown as DocumentoParaExport];
  const campos: CampoExtraido[] = [
    campo({ documento_versao_id: V, chave: "Caixa", secao: "Disponível", valor_num: 500, unidade: "milhar", ordem: 0 }),
  ];
  // 12 exercícios COMPLETOS + o ano corrente parcial, que é o que a RPC devolve
  // sempre. Era exatamente este cenário que zerava as três janelas.
  const anuais = [];
  for (let a = 2014; a <= 2025; a++) anuais.push({ serie: "IPCA", ano: a, meses: 12, retorno: 4.5 });
  anuais.push({ serie: "IPCA", ano: 2026, meses: 7, retorno: 2.1 });

  const ws = buildExportWorkbook({
    caso: { nome: "C", produto: "rx" }, documentos, campos,
    macro: { anuais, expectativas: [{ serie: "IPCA", ano_ref: 2026, mediana: 4.2, coletado_em: "2026-07-01" }] },
    agora: new Date("2026-07-31T12:00:00Z"),
  }).getWorksheet("Macro")!;

  // Acha a linha do IPCA e as três colunas de média pelo cabeçalho.
  let rIpca = -1;
  for (let r = 1; r <= ws.rowCount; r++) if (/IPCA/.test(String(ws.getRow(r).getCell(1).value ?? ""))) { rIpca = r; break; }
  checar(rIpca > 0, "(28a) a linha do IPCA existe na aba Macro");
  const colDaMedia: Record<string, number> = {};
  for (let r = 1; r <= Math.min(ws.rowCount, 4); r++) {
    for (let c = 2; c <= ws.columnCount; c++) {
      const m = String(ws.getRow(r).getCell(c).value ?? "").match(/M[ée]dia (\d+)a/);
      if (m) colDaMedia[m[1]] = c;
    }
  }
  checar(Object.keys(colDaMedia).length === 3, "(28b) as três colunas de média existem", JSON.stringify(colDaMedia));

  // Qual coluna é qual ano, na própria aba visível.
  const colDoAno: Record<number, string> = {};
  for (let r = 1; r <= Math.min(ws.rowCount, 4); r++) {
    for (let c = 2; c <= ws.columnCount; c++) {
      const v = ws.getRow(r).getCell(c).value;
      if (typeof v === "number" && v >= 2000 && v <= 2100) colDoAno[v] = colLetraDe(c);
    }
  }

  // A asserção é ESTRUTURAL, e a limitação é minha, não do export: `avaliarCelula`
  // não segue referência ENTRE ABAS, e cada célula de ano da aba visível é
  // `IF('Macro (dados)'!X="","",…)`. Então não dá para avaliar a média aqui.
  //
  // O que se afirma no lugar pega o defeito exato: a janela tem de NOMEAR os N
  // últimos exercícios COMPLETOS e NÃO pode tocar a coluna do ano parcial — que era
  // precisamente o que a faixa posicional fazia, zerando as três médias.
  for (const [janela, anosEsperados] of [
    ["3", [2023, 2024, 2025]],
    ["5", [2021, 2022, 2023, 2024, 2025]],
    ["10", [2016, 2017, 2018, 2019, 2020, 2021, 2022, 2023, 2024, 2025]],
  ] as Array<[string, number[]]>) {
    const cel = ws.getRow(rIpca).getCell(colDaMedia[janela]) as { value?: { formula?: string } };
    const f = cel.value?.formula ?? "";
    const faltando = anosEsperados.filter((a) => !new RegExp(`\\b${colDoAno[a]}${rIpca}\\b`).test(f));
    checar(
      faltando.length === 0,
      `(28c) a média de ${janela}a nomeia os ${anosEsperados.length} exercícios completos`,
      `faltando ${faltando.join(", ")} em ${f.slice(0, 110)}`,
    );
    checar(
      !new RegExp(`\\b${colDoAno[2026]}${rIpca}\\b`).test(f),
      `(28d) a média de ${janela}a NÃO toca a coluna do ano parcial (2026)`,
      f.slice(0, 110),
    );
  }
}

// ---- 29: histórico curto deixa a média vazia, e a NOTA diz quantos anos há ---
{
  const V = "macro-curto";
  const documentos: DocumentoParaExport[] = [{
    id: "d-mc", tipo_taxonomia: "BALANCO", status: "em_validacao",
    entidade: { razao_social: "Ômega Ltda." }, periodo: { tipo: "anual", referencia: "12M25" },
    documento_versao: [{ id: V, n_versao: 1, nome_original: "BP.pdf" }],
  } as unknown as DocumentoParaExport];
  const campos: CampoExtraido[] = [
    campo({ documento_versao_id: V, chave: "Caixa", secao: "Disponível", valor_num: 500, unidade: "milhar", ordem: 0 }),
  ];
  const anuais = [
    { serie: "IPCA", ano: 2024, meses: 12, retorno: 4.5 },
    { serie: "IPCA", ano: 2025, meses: 12, retorno: 4.5 },
    { serie: "IPCA", ano: 2026, meses: 7, retorno: 2.1 },
  ];
  const ws = buildExportWorkbook({
    caso: { nome: "C", produto: "rx" }, documentos, campos,
    macro: { anuais, expectativas: [] }, agora: new Date("2026-07-31T12:00:00Z"),
  }).getWorksheet("Macro")!;
  let rIpca = -1;
  for (let r = 1; r <= ws.rowCount; r++) if (/IPCA/.test(String(ws.getRow(r).getCell(1).value ?? ""))) { rIpca = r; break; }
  const nota = notaDaLinha(ws, rIpca);
  // A explicação tem de ser VERDADEIRA: "há 2 (2024, 2025)", não "falta histórico".
  checar(/exige 3 exerc/i.test(nota), "(29a) a nota diz qual janela não fechou", nota.slice(0, 160));
  checar(/2024, 2025/.test(nota), "(29b) …e QUANTOS anos completos existem, nomeados", nota.slice(0, 160));
}

// ---- 30: "Ferramental e moldes" é Imobilizado pelo RÓTULO ------------------
// Achado no teste v33, com dado real. No book, "Ferramental e moldes" (3.600) está
// DENTRO do Imobilizado da Componentes — 14.200 + 3.600 + 890 − 13.100 = 5.590, o
// total informado. No export o Imobilizado usou 5.590 E o Ferramental foi somado de
// novo em "Outros Ativos Não Circulantes": Ativo Não Circulante inflado em 3.600.
//
// HONESTIDADE SOBRE O ESCOPO DESTE INVARIANTE. Ele afirma a CLASSIFICAÇÃO, não a
// ausência de dupla contagem — e a diferença importa. Tentei duas fixtures para
// reproduzir a dupla contagem e as duas nasceram VAZIAS (passavam com o bug ligado):
//   1ª: declarei `secao: "Imobilizado"` nas contas — com seção declarada,
//       `subsecaoAutoritativa` já mandava o Ferramental ao lugar certo;
//   2ª: tirei a seção, mas a `ordem` deixou a linha ENTRE contas do Imobilizado, e o
//       consenso de irmãos a colocou certo de novo, sem depender do vocabulário.
// Não consegui reconstruir o arranjo exato que a produção tinha. Então afirmo o que
// dá para provar não-vazio, e a guarda de dupla contagem NO PARENTE fica registrada
// como aberta — ver o comentário de `escreverConferenciaExtraido`, que agora nomeia
// esta causa entre as duas possíveis.
{
  for (const chave of ["Ferramental e moldes", "Ferramental", "Moldes e ferramental", "Ferramentaria"]) {
    const c = classificarConta("balanco", null, chave, null);
    checar(
      c?.secaoKey === "imobilizado",
      `(30) "${chave}" é Imobilizado pelo rótulo, sem depender de seção declarada`,
      `caiu em ${c?.secaoKey ?? c?.ancoraKey ?? "Não Classificadas"}`,
    );
  }
}


// ---- 31: Focus que não cobre o exercício projetado NÃO vira 0,0% -----------
// O defeito mais enganoso que restava da Etapa 2, e o gatilho é banal: os
// exercícios projetados derivam do histórico DO MANDATO. Um caso com
// demonstrações de 2019-2021 projeta 2022-2024; o Focus publicado cobre
// 2026-2030. As três colunas saíam com inflação e juro ZERADOS — célula
// amarela de input, com a nota afirmando "Mediana das expectativas de mercado
// (Boletim Focus/BCB)" — enquanto a aba Macro, ao lado, exibia o Focus de
// 2026-2030 como se estivesse tudo em ordem. Todo o bloco de dívida cobra juro
// zero nesse cenário e o modelo fecha bonito.
//
// O que se afirma aqui é o COMPORTAMENTO (a ausência aparece como ausência),
// não o mecanismo — o invariante das médias já ensinou o preço de travar "como
// o código faz": ele protegeu justamente o defeito.
{
  const V = "v-focus-fora";
  const documentos: DocumentoParaExport[] = [2019, 2020, 2021].map((ano) => ({
    id: `d-${ano}`, tipo_taxonomia: "BALANCO", status: "em_validacao",
    entidade: { razao_social: "Antiga Ltda." },
    periodo: { tipo: "anual", referencia: `12M${String(ano).slice(2)}` },
    documento_versao: [{ id: `${V}-${ano}`, n_versao: 1, nome_original: `BP_${ano}.pdf` }],
  }) as unknown as DocumentoParaExport);
  const campos: CampoExtraido[] = [2019, 2020, 2021].map((ano, i) => campo({
    documento_versao_id: `${V}-${ano}`, chave: "Caixa e bancos", secao: "Disponível",
    valor_num: 100 + i, unidade: "milhar", ordem: 0, periodo_coluna: String(ano),
  }));
  // Focus real de hoje: horizonte 2026-2030. Nenhum dos anos que ESTE caso
  // projeta (2022-2024) está nele.
  const expectativas = [2026, 2027, 2028, 2029, 2030].flatMap((ano_ref) => [
    { serie: "IPCA", ano_ref, mediana: 4.5, coletado_em: "2026-07-24" },
    { serie: "SELIC", ano_ref, mediana: 11.0, coletado_em: "2026-07-24" },
  ]);
  const anuais = [2019, 2020, 2021].flatMap((ano) => [
    { serie: "IPCA", ano, meses: 12, retorno: 4.2 },
    { serie: "SELIC", ano, meses: 12, retorno: 9.1 },
  ]);
  const mod = buildExportWorkbook({
    caso: { nome: "Caso Antigo", produto: "reestruturacao" }, documentos, campos,
    macro: { anuais, expectativas }, agora: new Date("2026-07-31T12:00:00Z"),
  }).getWorksheet("Modelagem")!;

  const linhaDe = (rot: string) => {
    for (let r = 1; r <= mod.rowCount; r++) {
      if (String(mod.getRow(r).getCell(1).value ?? "") === rot) return r;
    }
    return -1;
  };
  const nAnos = Math.floor((mod.columnCount - 2) / 13);
  const colFY = (y: number) => 3 + y * 13 + 12;
  // 3 exercícios históricos (2019-2021) + 3 projetados (2022-2024).
  const projetados = [3, 4, 5].filter((y) => y < nAnos);
  checar(projetados.length === 3, "(31) o caso projeta 3 exercícios fora do horizonte do Focus", String(nAnos));

  for (const rot of ["Inflação esperada (metodologia selecionada)", "Juro esperado (Selic — Focus)"]) {
    const r = linhaDe(rot);
    checar(r > 0, `(31) a premissa "${rot}" existe`);
    if (r < 0) continue;
    for (const y of projetados) {
      const cell = mod.getRow(r).getCell(colFY(y));
      // A afirmação central continua a mesma — sem Focus, a premissa NÃO vira
      // zero — mas a Etapa 5 mudou o mecanismo: a premissa passou a ser uma
      // fórmula que indexa a metodologia escolhida. Então o que se prende aqui
      // é que ela RESOLVE para vazio: ou a célula está vazia (linha do juro,
      // que não passa pelo seletor), ou a fórmula guarda o vazio com
      // `IF(...="","",...)`. Um zero literal reprova nos dois casos.
      const fCel = String((cell.value as { formula?: string } | undefined)?.formula ?? "");
      const resolveVazio = cell.value == null || /="",""/.test(fCel);
      checar(resolveVazio,
        `(31) sem Focus para ${2019 + y}, "${rot}" resolve para VAZIO (0 seria ausência disfarçada de dado)`,
        JSON.stringify(cell.value));
      const nota = String((cell.note as { texts?: Array<{ text: string }> } | undefined)?.texts?.map((t) => t.text).join("") ?? "");
      checar(/EM BRANCO/.test(nota) && /2026/.test(nota),
        "(31) …e a nota da célula declara a cobertura real do Focus", nota.slice(0, 140));
      checar(new RegExp(String(2019 + y)).test(nota),
        `(31) …nomeando o exercício desta coluna (${2019 + y})`, nota.slice(0, 140));
    }
  }

  // O aviso que se lê SEM abrir nota nenhuma: nota de célula só alcança quem já
  // desconfiou e foi até lá.
  let avisoLinha = -1;
  for (let r = 1; r <= mod.rowCount; r++) {
    if (/SEM EXPECTATIVA DO FOCUS/.test(String(mod.getRow(r).getCell(1).value ?? ""))) { avisoLinha = r; break; }
  }
  checar(avisoLinha > 0, "(31) a Modelagem avisa, em linha visível, que a projeção saiu sem Focus");
  if (avisoLinha > 0) {
    const txt = String(mod.getRow(avisoLinha).getCell(1).value ?? "");
    checar(/2022/.test(txt) && /2024/.test(txt),
      "(31) …nomeando os exercícios descobertos", txt.slice(0, 120));
    checar(/juro zero/i.test(txt), "(31) …e dizendo o EFEITO (o bloco de dívida não cobra juro)");
  }

  // A conferência VIVA, que é o que sobrevive ao dono mover a linha do tempo:
  // a nota foi escrita na exportação, a fórmula responde a cada recálculo.
  const rCob = linhaDe("↳ cobertura do Focus (IPCA / Selic)");
  checar(rCob > 0, "(31) existe linha de cobertura do Focus que recalcula com o arquivo");
  if (rCob > 0) {
    const f = String((mod.getRow(rCob).getCell(colFY(projetados[0])).value as { formula?: string })?.formula ?? "");
    checar(/SEM FOCUS/.test(f) && /MATCH\(/.test(f),
      "(31) …e ela pergunta ao arquivo (MATCH), não repete a decisão da geração", f.slice(0, 120));
  }
}

// ---- 32: e o contrário — com Focus cobrindo o ano, nada de aviso -----------
// A metade que impede o invariante 31 de virar "sempre em branco": um export
// que apagasse a premissa SEMPRE passaria em todos os asserts acima. Aqui o
// horizonte do Focus cobre os anos projetados e o comportamento tem de ser o
// oposto — fórmula lendo a aba Macro, nenhuma célula vazia, nenhum aviso.
{
  const V = "v-focus-cobre";
  const documentos: DocumentoParaExport[] = [2024, 2025].map((ano) => ({
    id: `dc-${ano}`, tipo_taxonomia: "BALANCO", status: "em_validacao",
    entidade: { razao_social: "Atual Ltda." },
    periodo: { tipo: "anual", referencia: `12M${String(ano).slice(2)}` },
    documento_versao: [{ id: `${V}-${ano}`, n_versao: 1, nome_original: `BP_${ano}.pdf` }],
  }) as unknown as DocumentoParaExport);
  const campos: CampoExtraido[] = [2024, 2025].map((ano, i) => campo({
    documento_versao_id: `${V}-${ano}`, chave: "Caixa e bancos", secao: "Disponível",
    valor_num: 100 + i, unidade: "milhar", ordem: 0, periodo_coluna: String(ano),
  }));
  const expectativas = [2026, 2027, 2028].flatMap((ano_ref) => [
    { serie: "IPCA", ano_ref, mediana: 4.5, coletado_em: "2026-07-24" },
    { serie: "SELIC", ano_ref, mediana: 11.0, coletado_em: "2026-07-24" },
  ]);
  const mod = buildExportWorkbook({
    caso: { nome: "Caso Atual", produto: "reestruturacao" }, documentos, campos,
    macro: { anuais: [{ serie: "IPCA", ano: 2024, meses: 12, retorno: 4.2 }], expectativas },
    agora: new Date("2026-07-31T12:00:00Z"),
  }).getWorksheet("Modelagem")!;

  const linhaDe = (rot: string) => {
    for (let r = 1; r <= mod.rowCount; r++) {
      if (String(mod.getRow(r).getCell(1).value ?? "") === rot) return r;
    }
    return -1;
  };
  const colFY = (y: number) => 3 + y * 13 + 12;
  const rIpca = linhaDe("Inflação esperada (metodologia selecionada)");
  // 2024-2025 históricos, 2026-2028 projetados — todos no Focus desta fixture.
  for (const y of [2, 3, 4]) {
    const cell = mod.getRow(rIpca).getCell(colFY(y));
    const f = String((cell.value as { formula?: string } | undefined)?.formula ?? "");
    // Etapa 3: o Focus vive espelhado no rodapé da própria Modelagem. O
    // comportamento afirmado é o mesmo — com cobertura, a premissa é FÓRMULA e
    // não fica vazia — mas sem citar aba, que é o ponto da Etapa 3.
    checar(/INDEX\(/.test(f) && !/'[^']+'!/.test(f),
      `(32) com Focus para ${2024 + y}, a premissa é FÓRMULA local em vez de ficar vazia`, f.slice(0, 110));
  }
  let aviso = false;
  for (let r = 1; r <= mod.rowCount; r++) {
    if (/SEM EXPECTATIVA DO FOCUS/.test(String(mod.getRow(r).getCell(1).value ?? ""))) aviso = true;
  }
  checar(!aviso, "(32) e nenhum aviso de ausência aparece quando não há ausência");
}

// ---- 33: falha PARCIAL do macro é declarada DENTRO do arquivo --------------
// `macroErro` só chegava ao arquivo quando NÃO havia macro nenhum. O caso que
// escapava: os índices e o Focus respondem, mas a consulta de NOMES das séries
// falha — a aba sai com "IPCA"/"SELIC" crus no lugar dos nomes por extenso, e
// o erro morria num `console.error` do servidor. Quem abre a planilha não tem
// acesso a log nenhum: para ele, o arquivo simplesmente parece pronto.
{
  const V = "v-macro-parcial";
  const documentos: DocumentoParaExport[] = [{
    id: "d-mp", tipo_taxonomia: "BALANCO", status: "em_validacao",
    entidade: { razao_social: "Parcial Ltda." }, periodo: { tipo: "anual", referencia: "12M25" },
    documento_versao: [{ id: V, n_versao: 1, nome_original: "BP.pdf" }],
  } as unknown as DocumentoParaExport];
  const campos: CampoExtraido[] = [
    campo({ documento_versao_id: V, chave: "Caixa", secao: "Disponível", valor_num: 500, unidade: "milhar", ordem: 0 }),
  ];
  const macro = {
    anuais: [{ serie: "IPCA", ano: 2024, meses: 12, retorno: 4.5 }],
    expectativas: [{ serie: "IPCA", ano_ref: 2026, mediana: 4.5, coletado_em: "2026-07-24" }],
  };
  const erro = "nomes das séries: permission denied for table indice_macro_serie";
  const wb = buildExportWorkbook({
    caso: { nome: "C", produto: "rx" }, documentos, campos, macro, macroErro: erro,
    agora: new Date("2026-07-31T12:00:00Z"),
  });
  const ws = wb.getWorksheet("Macro")!;
  let achou = "";
  for (let r = 1; r <= ws.rowCount; r++) {
    const t = String(ws.getRow(r).getCell(1).value ?? "");
    if (/falhou EM PARTE/.test(t)) { achou = t; break; }
  }
  checar(achou !== "", "(33) a aba Macro declara que a consulta falhou em parte");
  checar(achou.includes("nomes das séries"),
    "(33) …repetindo QUAL parte falhou, para quem for conferir no Supabase", achou.slice(0, 120));

  // E o aviso não pode ter deslocado as linhas que o modelo endereça por
  // número. Continua valendo depois da Etapa 3: a premissa aponta para uma
  // LINHA — agora do bloco BASE MACRO, no rodapé da própria Modelagem — e uma
  // linha inserida antes dela faria cada fórmula mirar uma acima, em silêncio.
  const mod = wb.getWorksheet("Modelagem")!;
  // ETAPA 5: quem endereça a linha do Focus por NÚMERO deixou de ser a
  // premissa (ela indexa a tabela de metodologias) e passou a ser a linha
  // "Focus — IPCA" do bloco INPUTS MACRO. O risco é o mesmo — um aviso
  // inserido antes faria a fórmula mirar uma linha acima — e é lá que ele
  // agora se manifesta.
  let rIpca = -1;
  for (let r = 1; r <= mod.rowCount; r++) {
    if (String(mod.getRow(r).getCell(1).value ?? "") === "Focus — IPCA") { rIpca = r; break; }
  }
  const nA = Math.floor((mod.columnCount - 2) / 13);
  let apontou = false;
  for (let y = 0; y < nA; y++) {
    const f = String((mod.getRow(rIpca).getCell(3 + y * 13 + 12).value as { formula?: string } | undefined)?.formula ?? "");
    if (!f) continue;
    // A linha citada pela fórmula tem de ser mesmo a do IPCA na base local.
    const m = f.match(/INDEX\(\$B\$(\d+)/);
    if (!m) continue;
    apontou = true;
    checar(/IPCA/i.test(String(mod.getRow(Number(m[1])).getCell(1).value ?? "")),
      "(33) o aviso não deslocou as linhas que o modelo endereça por número",
      `fórmula aponta linha ${m[1]}, que contém "${String(mod.getRow(Number(m[1])).getCell(1).value ?? "")}"`);
  }
  checar(apontou, "(33) …e a premissa realmente endereça o Focus espelhado nesta fixture");
}

// ---- 34: sem entidade reconhecida, a AUSÊNCIA das abas é declarada ---------
// A guarda `entidadesConhecidas.size > 0` cobre Macro E Modelagem: sem nenhuma
// entidade, o arquivo saía sem as duas abas e sem uma palavra sobre isso. Uma
// aba que não existe não diz por que não existe — foi assim que "não veio os
// dados macro" (v28) virou meia hora de investigação de causa errada.
{
  const V = "v-sem-entidade";
  const documentos: DocumentoParaExport[] = [{
    id: "d-se", tipo_taxonomia: "BALANCO", status: "em_validacao",
    entidade: null, periodo: null,
    documento_versao: [{ id: V, n_versao: 1, nome_original: "ilegivel.pdf" }],
  } as unknown as DocumentoParaExport];
  const wb = buildExportWorkbook({
    caso: { nome: "Caso Sem Entidade", produto: "rx" }, documentos, campos: [],
    agora: new Date("2026-07-31T12:00:00Z"),
  });
  const ws = wb.getWorksheet("Modelagem");
  checar(ws != null, "(34) a aba Modelagem EXISTE mesmo sem entidade reconhecida (declarando o porquê)");
  if (ws) {
    let texto = "";
    for (let r = 1; r <= ws.rowCount; r++) {
      for (let c = 1; c <= 2; c++) texto += String(ws.getRow(r).getCell(c).value ?? "") + "\n";
    }
    checar(/não montad/i.test(texto), "(34) …dizendo que não foi montada", texto.slice(0, 100));
    checar(/ENTIDADE reconhecida/i.test(texto), "(34) …e a causa: nenhuma entidade reconhecida");
    checar(/Resumo/.test(texto) && /fila de revisão/i.test(texto),
      "(34) …e para onde ir (Resumo e fila de revisão), não só o diagnóstico");
  }
}

// ---- 35: bloco REFERÊNCIAS MACRO — informa sem fingir que dirige -----------
// Fecha a Etapa 2. O placar que motivou o bloco, medido antes de escrevê-lo:
// das 15 premissas, 2 liam macro (IPCA e Selic do Focus); das 6 séries
// históricas coletadas, 0 alimentavam qualquer fórmula — as 18 células de média
// 3a/5a/10a da aba Macro não moviam nada e ninguém fora daquela aba as via.
//
// Decisão do dono (2026-07-31): trazer IGP-M, PIB, câmbio e as médias como
// REFERÊNCIA agora; o seletor que escolhe qual índice dirige o quê é a Etapa 5.
// Então o que se afirma aqui é o COMPORTAMENTO de uma referência honesta:
//   (a) ela existe e diz, em linha visível, que NÃO move o modelo sozinha;
//   (b) é FÓRMULA lendo a aba Macro — a planilha continua viva, corrigir a
//       origem faz o modelo acompanhar (arquitetura desde a sessão 12);
//   (c) ausência aparece como ausência, com o MESMO tratamento da fatia 4;
//   (d) as premissas continuam sendo 15 — referência não é premissa.
{
  const V = "v-refs-macro";
  const documentos: DocumentoParaExport[] = [2024, 2025].map((ano) => ({
    id: `dr-${ano}`, tipo_taxonomia: "BALANCO", status: "em_validacao",
    entidade: { razao_social: "Referência Ltda." },
    periodo: { tipo: "anual", referencia: `12M${String(ano).slice(2)}` },
    documento_versao: [{ id: `${V}-${ano}`, n_versao: 1, nome_original: `BP_${ano}.pdf` }],
  }) as unknown as DocumentoParaExport);
  const campos: CampoExtraido[] = [2024, 2025].map((ano, i) => campo({
    documento_versao_id: `${V}-${ano}`, chave: "Caixa e bancos", secao: "Disponível",
    valor_num: 100 + i, unidade: "milhar", ordem: 0, periodo_coluna: String(ano),
  }));
  // Focus cobrindo SÓ 2026-2028: os exercícios 2024 e 2025 do modelo ficam
  // descobertos de propósito, para o assert de ausência ter onde acontecer.
  const expectativas = [2026, 2027, 2028].flatMap((ano_ref) => [
    { serie: "IPCA", ano_ref, mediana: 4.5, coletado_em: "2026-07-24" },
    { serie: "SELIC", ano_ref, mediana: 11.0, coletado_em: "2026-07-24" },
    { serie: "IGPM", ano_ref, mediana: 5.1, coletado_em: "2026-07-24" },
    { serie: "PIB", ano_ref, mediana: 2.2, coletado_em: "2026-07-24" },
    // NÍVEL, não taxa: o Focus publica câmbio em R$/US$. É o número que revela
    // erro de escala — 5,4 dividido por 100 e formatado como % vira 5,4%.
    { serie: "CAMBIO_USD", ano_ref, mediana: 5.4, coletado_em: "2026-07-24" },
  ]);
  // IPCA com 10 exercícios completos (as três janelas fecham) e IGPM com 2 (as
  // três ficam VAZIAS na origem). As duas metades importam: a primeira prova que
  // a referência lê, a segunda que ela não publica o vazio como 0,0%.
  const anuais = [
    ...Array.from({ length: 10 }, (_, k) => ({ serie: "IPCA", ano: 2016 + k, meses: 12, retorno: 4.2 })),
    { serie: "IGPM", ano: 2024, meses: 12, retorno: 3.1 },
    { serie: "IGPM", ano: 2025, meses: 12, retorno: 3.3 },
  ];
  // `nomes` vai preenchido de propósito: é o que o `route.ts` manda em produção,
  // e é o que faz o bloco escrever "IGP-M (FGV)" em vez de "IGPM" cru. Código de
  // sistema num rótulo de leitura humana é o começo de alguém ler a série errada.
  const nomes = {
    IPCA: "IPCA (IBGE)", IGPM: "IGP-M (FGV)", PIB: "PIB Total",
    CAMBIO_USD: "Câmbio R$/US$ (venda, fim de período)",
  };
  const wb = buildExportWorkbook({
    caso: { nome: "Caso Referência", produto: "reestruturacao" }, documentos, campos,
    macro: { anuais, expectativas, nomes }, agora: new Date("2026-07-31T12:00:00Z"),
  });
  const mod = wb.getWorksheet("Modelagem")!;

  const rotuloDe = (r: number) => String(mod.getRow(r).getCell(1).value ?? "");
  const linhaDe = (pred: (rot: string) => boolean) => {
    for (let r = 1; r <= mod.rowCount; r++) if (pred(rotuloDe(r))) return r;
    return -1;
  };
  const colFY = (y: number) => 3 + y * 13 + 12;
  const formulaDe = (r: number, c: number) =>
    r < 1 ? "" : String((mod.getRow(r).getCell(c).value as { formula?: string } | undefined)?.formula ?? "");
  const notaDe = (r: number, c: number) =>
    r < 1 ? "" : String((mod.getRow(r).getCell(c).note as { texts?: Array<{ text: string }> } | undefined)
      ?.texts?.map((t) => t.text).join("") ?? "");

  const rBloco = linhaDe((rot) => rot.startsWith("REFERÊNCIAS MACRO"));
  checar(rBloco > 0, "(35) a Modelagem tem um bloco REFERÊNCIAS MACRO");
  checar(/NÃO move/i.test(rotuloDe(rBloco)),
    "(35) …e o cabeçalho diz, sem abrir nota, que elas não movem o modelo sozinhas",
    rotuloDe(rBloco));
  checar(/Etapa 5/.test(notaDaLinha(mod, rBloco)),
    "(35) …e aponta o seletor da Etapa 5 como quem vai dar alavanca a elas",
    notaDaLinha(mod, rBloco).slice(0, 140));

  // O bloco fica DEPOIS das premissas: uma linha inserida no meio delas
  // deslocaria `P(i)` e toda fórmula do modelo, em silêncio.
  const rPremissasCab = linhaDe((rot) => rot.startsWith("PREMISSAS"));
  checar(rPremissasCab > 0 && rBloco > rPremissasCab,
    "(35) o bloco fica FORA (depois) do bloco de premissas", `${rPremissasCab} → ${rBloco}`);

  // --- as três séries do Focus que o modelo ainda não usa -------------------
  for (const [rot, temFocus] of [
    ["↳ IGP-M esperado (Focus)", true],
    ["↳ PIB esperado (Focus)", true],
    ["↳ Câmbio esperado (Focus)", true],
  ] as Array<[string, boolean]>) {
    const r = linhaDe((x) => x === rot);
    checar(r > 0, `(35) existe a linha de referência "${rot}"`);
    if (r < 0) continue;
    // 2026-2028 (y=2,3,4) estão no Focus desta fixture: tem de sair FÓRMULA
    // lendo a aba Macro, não valor escrito — senão a planilha morre e recoletar
    // o macro não corrige mais nada.
    for (const y of [2, 3, 4]) {
      const f = formulaDe(r, colFY(y));
      checar(/INDEX\(/.test(f) && /MATCH\(/.test(f) && !/'[^']+'!/.test(f),
        `(35) "${rot}" em ${2024 + y} é FÓRMULA lendo o Focus espelhado, não número escrito`,
        f.slice(0, 90) || JSON.stringify(mod.getRow(r).getCell(colFY(y)).value));
    }
    // 2024-2025 (y=0,1) NÃO estão no Focus: mesmo tratamento da fatia 4 —
    // célula sem nada e a nota dizendo qual é a cobertura publicada. Um 0 aqui
    // seria "o mercado espera PIB zero"; no câmbio, um dólar de R$ 0,00.
    for (const y of [0, 1]) {
      checar(mod.getRow(r).getCell(colFY(y)).value == null,
        `(35) sem Focus para ${2024 + y}, "${rot}" fica EM BRANCO`,
        JSON.stringify(mod.getRow(r).getCell(colFY(y)).value));
      const n = notaDe(r, colFY(y));
      checar(/EM BRANCO/.test(n) && /2026/.test(n),
        `(35) …e a nota da célula declara a cobertura real (${rot}, ${2024 + y})`, n.slice(0, 120));
    }
    void temFocus;
    // Cada linha diz O QUE DEVERIA DIRIGIR e que hoje não dirige. Sem isso o
    // bloco é uma lista de números soltos, que é a crítica registrada às médias.
    const nl = notaDaLinha(mod, r);
    checar(/DEVERIA DIRIGIR/.test(nl), `(35) a nota de "${rot}" diz o que ela deveria dirigir`, nl.slice(0, 120));
    checar(/Etapa 5/.test(nl), `(35) …e que a escolha é o seletor da Etapa 5`, nl.slice(0, 120));
  }

  // --- câmbio é NÍVEL: o assert que pega erro de escala ---------------------
  // O Focus publica câmbio em R$/US$ (5,4), não em %. Tratá-lo como as outras
  // duas — dividir por 100 e formatar como percentual — publicaria "5,4%" no
  // lugar de "R$ 5,4000". É a mesma família do erro de ~496x que a Etapa 1
  // corrigiu nas abas de dados, e ele não dá nenhum sinal na tela.
  {
    const r = linhaDe((x) => x === "↳ Câmbio esperado (Focus)");
    const f = formulaDe(r, colFY(2));
    checar(!/\/100/.test(f), "(35) a referência de câmbio NÃO divide por 100 (Focus publica NÍVEL)", f.slice(0, 90));
    checar(String(mod.getRow(r).getCell(colFY(2)).numFmt ?? "").indexOf("%") < 0,
      "(35) …nem é formatada como percentual", String(mod.getRow(r).getCell(colFY(2)).numFmt));
    checar(String(mod.getRow(r).getCell(2).value ?? "").includes("R$/US$"),
      "(35) …e a unidade na própria linha diz R$/US$", String(mod.getRow(r).getCell(2).value));
    // E a contraprova, para o assert acima não passar por um export que
    // simplesmente nunca divide por 100: IGP-M e PIB, que são percentuais, DIVIDEM.
    for (const rot of ["↳ IGP-M esperado (Focus)", "↳ PIB esperado (Focus)"]) {
      const rp = linhaDe((x) => x === rot);
      checar(/\/100/.test(formulaDe(rp, colFY(2))),
        `(35) …enquanto "${rot}", que é percentual, divide por 100`, formulaDe(rp, colFY(2)).slice(0, 90));
    }
  }

  // --- médias históricas: lidas por fórmula, e o vazio continua vazio -------
  // `avaliarCelula` NÃO segue referência entre abas (toda célula da Macro é
  // `IF('Macro (dados)'!X="","",…)`), então a afirmação aqui é estrutural — e o
  // motivo está aqui escrito para ninguém achar que foi preguiça.
  {
    const rSub = linhaDe((rot) => rot.startsWith("↳ médias históricas"));
    checar(rSub > 0, "(35) existe o sub-cabeçalho das médias históricas");
    checar(/NÃO são meses/i.test(notaDaLinha(mod, rSub)),
      "(35) …declarando que aquelas colunas não são meses (o painel congelado diz jan/fev/mar)",
      notaDaLinha(mod, rSub).slice(0, 140));
    for (const k of [0, 1, 2]) {
      checar(/^Média \d+a$/.test(String(mod.getRow(rSub).getCell(3 + k).value ?? "")),
        `(35) …e rotulando a janela na própria coluna (${k})`,
        String(mod.getRow(rSub).getCell(3 + k).value));
    }

    // IPCA: 10 exercícios completos na fixture ⇒ as três janelas FECHAM na aba
    // Macro, e a referência tem de trazer as três.
    const daMedia = (codigoNoNome: string) => {
      for (let r = rSub + 1; r <= mod.rowCount; r++) {
        const rot = rotuloDe(r);
        if (!rot.trim().startsWith("↳")) break;   // o bloco acaba na linha em branco
        if (rot.includes(codigoNoNome)) return r;
      }
      return -1;
    };
    const rIpca = daMedia("IPCA");
    checar(rIpca > 0, "(35) existe a linha de médias históricas do IPCA", `rowCount=${mod.rowCount}`);
    for (const k of [0, 1, 2]) {
      const f = formulaDe(rIpca, 3 + k);
      checar(/^IF\(/.test(f) && !/'[^']+'!/.test(f),
        `(35) a média ${[3, 5, 10][k]}a do IPCA é lida por fórmula da base local`, f.slice(0, 90));
      // O comportamento: origem vazia NÃO pode virar 0. Uma referência crua a
      // célula vazia vale 0 no Excel, e o bloco publicaria "0,0%" como média de
      // 10 anos — ausência apresentada como medição.
      checar(/=""/.test(f),
        `(35) …e guarda o vazio da origem em vez de publicar 0,0% (média ${[3, 5, 10][k]}a)`, f.slice(0, 90));
    }

    // IGPM: 2 exercícios ⇒ as três células de ORIGEM na aba Macro estão
    // literalmente vazias. É o caso em que a guarda acima é a diferença entre
    // "em branco" e "0,0% de inflação em 10 anos".
    const rIgpm = daMedia("IGP-M");
    checar(rIgpm > 0, "(35) existe a linha de médias históricas do IGP-M");
    if (rIgpm > 0) {
      let origemVazia = 0;
      for (const k of [0, 1, 2]) {
        const f = formulaDe(rIgpm, 3 + k);
        // A origem agora é uma célula da PRÓPRIA Modelagem (bloco BASE MACRO).
        const m = /IF\(([A-Z]+)(\d+)="/.exec(f);
        if (!m) continue;
        const orig = mod.getRow(Number(m[2])).getCell(m[1]);
        if (orig.value == null) origemVazia++;
        checar(/=""/.test(f),
          `(35) a média ${[3, 5, 10][k]}a do IGP-M guarda o vazio da origem`, f.slice(0, 90));
      }
      // Sem este assert o parágrafo acima seria decorativo: ele prova que a
      // fixture REALMENTE tem origem vazia, e não que o guard nunca é exercido.
      checar(origemVazia === 3,
        "(35) …e a fixture realmente tem as 3 células de origem vazias (2 exercícios só)",
        `vazias=${origemVazia}`);
    }
  }

  // --- e as premissas continuam sendo 15 -----------------------------------
  // Referência não é premissa. Este assert é o que impede o bloco de crescer
  // para dentro do bloco de cima: `P(i)` endereça premissa por deslocamento a
  // partir da primeira, e uma linha a mais lá desloca o modelo inteiro em
  // silêncio. (Os invariantes 14/15 já contam; aqui a contagem é afirmada nesta
  // fixture, que é a que tem o bloco novo.)
  {
    let dentro = false;
    let n = 0;
    for (let r = 1; r <= mod.rowCount; r++) {
      const rot = rotuloDe(r);
      if (rot.startsWith("PREMISSAS")) { dentro = true; continue; }
      if (dentro) {
        if (!rot || (rot === rot.toUpperCase() && rot.length > 12)) break;
        n++;
      }
    }
    checar(n === 15, "(35) o bloco de REFERÊNCIAS não entrou na contagem de premissas (continuam 15)", String(n));
  }
}

// ---- 36: dupla contagem no total do GRUPO, com a conta suspeita NOMEADA ----
// O bug aberto mais caro do repositório, e o arranjo abaixo é o do teste v33,
// não um inventado: Balanço da Componentes (test-data/book-vertentes/dados.py),
// Imobilizado = 14.200 + 3.600 + 890 − 13.100 = 5.590, com o 5.590 IMPRESSO no
// documento. Uma conta do Imobilizado foi anotada com a seção de TOPO ("Ativo
// Não Circulante") em vez da subseção, caiu em "Outros Ativos Não Circulantes"
// — irmã do Imobilizado — e o grupo passou a contá-la duas vezes: o total
// informado do Imobilizado já a inclui, e ela entra de novo pela irmã.
//
// HONESTIDADE SOBRE A CONTA USADA. A conta do v33 era "Ferramental e moldes", e
// ela NÃO serve mais para reproduzir: a fatia de vocabulário da sessão 18
// (invariante 30) faz esse rótulo ser Imobilizado mesmo sem seção declarada —
// medido aqui, `classificarConta("balanco","Ativo Não Circulante","Ferramental
// e moldes",null)` devolve `imobilizado`. Aquela INSTÂNCIA está fechada; a
// CLASSE de defeito não estava. A fixture usa "Bens em comodato", uma conta de
// imobilizado real (CPC 27) que o vocabulário genuinamente não reconhece —
// medido: devolve `ativo_nao_circulante`. Nada aqui foi inventado para o teste
// passar; o que mudou foi o rótulo, porque o antigo já está coberto.
//
// AS DUAS FIXTURES ANTERIORES NASCERAM VAZIAS (sessão 18) e o motivo está no
// handoff: uma declarava a SUBSEÇÃO (e `subsecaoAutoritativa` já acertava), a
// outra deixava a `ordem` entre contas do Imobilizado (e o consenso de irmãos
// acertava). Esta declara a seção de TOPO e põe a ordem longe — que é o que a
// produção tinha.
{
  const anc = (extra: { totalGrupo?: boolean; contaNoLugarCerto?: boolean }) => {
    const V = `v-dc-${extra.totalGrupo ? "t" : "s"}-${extra.contaNoLugarCerto ? "c" : "e"}`;
    const documentos: DocumentoParaExport[] = [{
      id: `d-${V}`, tipo_taxonomia: "BALANCO", status: "em_validacao",
      entidade: { razao_social: "Componentes Ltda." },
      periodo: { tipo: "anual", referencia: "12M25" },
      documento_versao: [{ id: V, n_versao: 1, nome_original: "BP_Componentes.pdf" }],
    } as unknown as DocumentoParaExport];
    const c = (chave: string, valor_num: number, ordem: number, secao: string | null = null) =>
      campo({ chave, secao, valor_num, ordem, unidade: "milhar", documento_versao_id: V });
    const campos: CampoExtraido[] = [
      c("Numerário disponível em bancos", 410, 1, "Disponível"),
      c("Total do Ativo Circulante", 410, 2, "Ativo Circulante"),
      ...(extra.totalGrupo ? [c("Ativo Não Circulante", 6550, 3)] : []),
      c("Realizável a Longo Prazo", 860, 4),
      c("Depósitos judiciais", 860, 5),
      c("Imobilizado", 5590, 6),
      c("Máquinas e equipamentos", 14200, 7),
      c("Veículos", 890, 8),
      c("(-) Depreciação acumulada", -13100, 9),
      c("Intangível", 100, 10),
      c("Software", 210, 11),
      c("(-) Amortização acumulada", -110, 12),
      // A conta exilada — ou não, na variante de contraprova.
      c("Bens em comodato", 3600, 40, extra.contaNoLugarCerto ? "Imobilizado" : "Ativo Não Circulante"),
    ];
    return buildExportWorkbook({
      caso: { nome: "Caso Dupla Contagem", produto: "reestruturacao" }, documentos, campos,
      agora: new Date("2026-07-31T12:00:00Z"),
    }).getWorksheet("Balanço")!;
  };
  const avisos = (ws: import("exceljs").Worksheet) => {
    const rs: number[] = [];
    for (let r = 1; r <= ws.rowCount; r++) {
      if (/DUPLA CONTAGEM/.test(String(ws.getRow(r).getCell(1).value ?? ""))) rs.push(r);
    }
    return rs;
  };

  // --- (a) com total do grupo informado: o número fica certo, mas o arquivo
  //         tem de dizer POR QUE ele diverge da soma, nomeando a conta.
  {
    const ws = anc({ totalGrupo: true });
    const rs = avisos(ws);
    checar(rs.length === 1, "(36) o export sinaliza a dupla contagem no total do grupo", `avisos=${rs.length}`);
    if (rs.length >= 1) {
      const txt = String(ws.getRow(rs[0]).getCell(1).value ?? "");
      // NOMEAR é o ponto: a nota antiga pedia ao humano que casasse a diferença
      // com alguma conta de outra seção, à mão, em 44 seções. Ninguém faz.
      checar(/Bens em comodato/.test(txt), "(36) …NOMEANDO a conta suspeita", txt.slice(0, 160));
      checar(/Outros Ativos Não Circulantes/.test(txt) && /Imobilizado/.test(txt),
        "(36) …e as DUAS seções envolvidas (onde ela está × quem já a soma)", txt.slice(0, 160));
      const nota = notaDaLinha(ws, rs[0]);
      checar(/LEITURA A/.test(nota) && /LEITURA B/.test(nota),
        "(36) …e a nota traz as DUAS leituras, porque o export não escolhe (docs/04)",
        nota.slice(0, 120));
      checar(/3\.600,00/.test(nota),
        "(36) …com a diferença medida, não só a afirmação", nota.slice(0, 300));
      // Não corrige sozinho: o cabeçalho do grupo continua sendo o que era
      // (o total informado), e o valor exilado continua onde a extração o pôs.
      let rGrupo = -1;
      for (let r = 1; r <= ws.rowCount; r++) {
        if (String(ws.getRow(r).getCell(1).value ?? "") === "Ativo Não Circulante") { rGrupo = r; break; }
      }
      checar(rGrupo > 0 && ws.getRow(rGrupo).getCell(2).value != null,
        "(36) o export NÃO reclassifica sozinho: o cabeçalho do grupo continua o que era");
      checar(String((ws.getRow(rGrupo).getCell(2).fill as { fgColor?: { argb?: string } } | undefined)
        ?.fgColor?.argb ?? "") === "FFFCE4E4",
        "(36) …mas a célula do total do grupo fica pintada, para quem lê só o total ver a suspeita");
    }
  }

  // --- (b) SEM total do grupo informado: é o caso silencioso e o mais caro.
  //         O cabeçalho do grupo vira a SOMA dos filhos — sai inflado em 3.600
  //         e não existe nenhuma linha de conferência contra a qual comparar.
  {
    const ws = anc({});
    const rs = avisos(ws);
    checar(rs.length === 1,
      "(36) o aviso aparece TAMBÉM sem total do grupo informado (o caso em que o número sai inflado)",
      `avisos=${rs.length}`);
  }

  // --- (c) a contraprova, sem a qual tudo acima passaria num export que
  //         simplesmente avisasse sempre. Com a conta na subseção certa, o
  //         Imobilizado fecha (14.200+3.600+890−13.100 = 5.590 = informado) e
  //         não existe divergência nenhuma para suspeitar.
  {
    const ws = anc({ totalGrupo: true, contaNoLugarCerto: true });
    checar(avisos(ws).length === 0,
      "(36) com a conta classificada no lugar certo, NÃO há aviso (o guard não é 'avisa sempre')",
      `avisos=${avisos(ws).length}`);
  }

  // --- (e) defeito ENCONTRADO ao escrever este teste, e corrigido junto: a
  //         marca de divergência no CABEÇALHO da seção nunca aparecia. O
  //         cabeçalho é linha reservada e preenchida no fim com `row.fill = …`,
  //         que no ExcelJS repinta a linha inteira e apagava o destaque escrito
  //         antes. Medido no arranjo abaixo: o Imobilizado diverge 1.990 ×
  //         5.590 e o cabeçalho dele saía com o cinza normal de seção — quem
  //         lê só a linha do total não tinha nenhum sinal.
  {
    const ws = anc({ totalGrupo: true });
    let rImob = -1;
    for (let r = 1; r <= ws.rowCount; r++) {
      if (String(ws.getRow(r).getCell(1).value ?? "") === "Imobilizado") { rImob = r; break; }
    }
    checar(rImob > 0, "(36) a seção Imobilizado foi emitida");
    const fill = String((ws.getRow(rImob).getCell(2).fill as { fgColor?: { argb?: string } } | undefined)
      ?.fgColor?.argb ?? "");
    checar(fill === "FFFCE4E4",
      "(36) o CABEÇALHO da seção que diverge fica pintado (o destaque não é apagado pelo fill da linha)",
      `fill=${fill || "(nenhum)"}`);
  }

  // --- (d) o mesmo achado não pode ser reportado no grupo e no avô. Duas vezes
  //         o mesmo aviso ensina o leitor a ignorar o aviso.
  {
    const ws = anc({ totalGrupo: true });
    const rs = avisos(ws);
    let rAtivo = -1;
    for (let r = 1; r <= ws.rowCount; r++) {
      if (String(ws.getRow(r).getCell(1).value ?? "") === "ATIVO") { rAtivo = r; break; }
    }
    checar(rs.length === 1 && rAtivo > 0,
      "(36) o achado é reportado UMA vez, no grupo onde as duas seções são irmãs — não repetido no ATIVO",
      `avisos=${rs.length}`);
  }
}

// ---- 37: 12 meses NÃO bastam — ano sem retorno calculável fica fora da média
// Achado na revisão crítica da sessão 19 (item pedido pelo dono), e o defeito é
// da interação entre duas coisas que estavam certas isoladamente.
//
// A `0032` fez a série de NÍVEL (câmbio) devolver retorno NULL no primeiro
// exercício: sem o fechamento do ano anterior não existe variação, e inventar
// uma era o defeito que ela corrigiu. Mas `meses` continua 12 — o ano TEM as
// doze observações, só não tem base. E o export decidia "exercício completo"
// olhando SÓ `meses === 12`.
//
// O efeito, medido antes da correção: o ano entrava em `completosDe`, a janela
// de 3 anos o NOMEAVA, e a média virava PRODUCT(1+B3/100, …) com B3 resolvendo
// para "" — a célula da aba visível é IF(dados!X="","",dados!X), e texto vazio
// não é célula vazia: ""/100 é #VALUE!, o erro sobe pelo PRODUCT, e o IFERROR
// de fora devolve "". A média 3a saía EM BRANCO com a nota afirmando "Média
// geométrica dos exercícios completos: 2023, 2024, 2025" — nota afirmando um
// cálculo que não aconteceu.
//
// É REACHABLE, não teórico: basta a coleta do SGS começar em janeiro. A janela
// da coleta é por DATA (n8n/lib/macro.mjs), então é o caso normal, não o raro.
// O seed atual escapa por acidente — ele começa em agosto de 2015.
{
  const V = "v-nulo-12m";
  const documentos: DocumentoParaExport[] = [{
    id: "d-n12", tipo_taxonomia: "BALANCO", status: "em_validacao",
    entidade: { razao_social: "Nível Ltda." }, periodo: { tipo: "anual", referencia: "12M25" },
    documento_versao: [{ id: V, n_versao: 1, nome_original: "BP.pdf" }],
  } as unknown as DocumentoParaExport];
  const campos: CampoExtraido[] = [
    campo({ documento_versao_id: V, chave: "Caixa", secao: "Disponível", valor_num: 1, unidade: "milhar", ordem: 0 }),
  ];
  // Coleta começando em JANEIRO: o primeiro ano tem 12 meses E retorno NULL.
  const anuais = [
    { serie: "CAMBIO_USD", ano: 2023, meses: 12, retorno: null },
    { serie: "CAMBIO_USD", ano: 2024, meses: 12, retorno: 8.1 },
    { serie: "CAMBIO_USD", ano: 2025, meses: 12, retorno: -3.2 },
  ];
  const ws = buildExportWorkbook({
    caso: { nome: "C", produto: "rx" }, documentos, campos,
    macro: { anuais: anuais as never, expectativas: [] },
    agora: new Date("2026-07-31T12:00:00Z"),
  }).getWorksheet("Macro")!;

  let rCambio = -1;
  for (let r = 1; r <= ws.rowCount; r++) {
    if (/CAMBIO_USD/.test(String(ws.getRow(r).getCell(1).value ?? ""))) { rCambio = r; break; }
  }
  checar(rCambio > 0, "(37) a série de nível foi emitida na aba Macro");
  if (rCambio > 0) {
    // Colunas: 2..4 são os anos; 5,6,7 são as médias 3a/5a/10a.
    const media3 = ws.getRow(rCambio).getCell(5);
    const nota3 = String((media3.note as { texts?: Array<{ text: string }> } | undefined)
      ?.texts?.map((t) => t.text).join("") ?? "");
    // O comportamento afirmado: a janela de 3 anos NÃO fecha, porque só há 2
    // exercícios com retorno. Antes ela "fechava" e o resultado era uma célula
    // vazia com uma nota falsa.
    checar(media3.value == null,
      "(37) com 2 exercícios calculáveis, a média 3a fica vazia (não finge fechar)",
      JSON.stringify(media3.value));
    checar(/exige 3 exerc/i.test(nota3) && /há 2/.test(nota3),
      "(37) …e a nota diz a VERDADE sobre quantos existem", nota3.slice(0, 160));
    checar(!/2023/.test(nota3),
      "(37) …sem nomear o ano que não tem retorno como se tivesse", nota3.slice(0, 160));

    // E a célula do ano sem base diz POR QUE está vazia. "12 meses observados"
    // sozinho é contraditório com a célula em branco ao lado.
    const notaAno = String((ws.getRow(rCambio).getCell(2).note as { texts?: Array<{ text: string }> } | undefined)
      ?.texts?.map((t) => t.text).join("") ?? "");
    // A nota do ano vive na aba de DADOS (a visível é fórmula); busca lá.
    const dados = buildExportWorkbook({
      caso: { nome: "C", produto: "rx" }, documentos, campos,
      macro: { anuais: anuais as never, expectativas: [] },
      agora: new Date("2026-07-31T12:00:00Z"),
    }).getWorksheet("Macro (dados)")!;
    let rD = -1;
    for (let r = 1; r <= dados.rowCount; r++) {
      if (/CAMBIO_USD/.test(String(dados.getRow(r).getCell(1).value ?? ""))) { rD = r; break; }
    }
    const nd = String((dados.getRow(rD).getCell(2).note as { texts?: Array<{ text: string }> } | undefined)
      ?.texts?.map((t) => t.text).join("") ?? "");
    checar(dados.getRow(rD).getCell(2).value == null,
      "(37) o ano sem base não recebe número (0% seria a invenção que a 0032 tirou)");
    checar(/SEM RETORNO CALCULÁVEL/.test(nd) && /0032/.test(nd),
      "(37) …e a nota dele diz a causa, não só que tem 12 meses", nd.slice(0, 200));
    void notaAno;
  }
}

// ---- 38: ETAPA 3 — a Modelagem não depende de nenhuma outra aba -----------
// Pedido do dono, e é uma INVERSÃO consciente da arquitetura da sessão 12: até
// aqui o modelo lia as abas de dados por INDEX/MATCH entre abas, o que mantinha
// a planilha viva (corrigiu a origem, o modelo acompanha) ao custo de depender
// de outra aba existir, com aquele nome, naquele formato. O dono pediu o
// oposto: "entregue já preenchida com os valores brutos necessários, mantendo
// apenas as fórmulas internas da própria modelagem".
//
// O que se afirma aqui é o COMPORTAMENTO da independência, não o mecanismo:
//   (a) nenhuma fórmula da aba cita outra aba — nem de dados, nem a Macro;
//   (b) os valores brutos ESTÃO nela, escritos, senão (a) seria satisfeito por
//       um modelo vazio;
//   (c) o arquivo DIZ que a base é uma foto, porque quem corrigir a origem
//       esperando o modelo responder vai ficar com dois números e nenhum aviso;
//   (d) pedir um rótulo não declarado FALHA a geração, em vez de sair zero.
{
  const fixture = JSON.parse(
    readFileSync(new URL("./fixtures/book-vertentes.json", import.meta.url), "utf8"),
  ) as { documentos: DocumentoParaExport[]; campos: CampoExtraido[] };
  const anuais = Array.from({ length: 11 }, (_, k) => ({ serie: "IPCA", ano: 2015 + k, meses: 12, retorno: 4 + k * 0.1 }));
  const expectativas = [2026, 2027, 2028].flatMap((ano_ref) =>
    ["IPCA", "SELIC", "IGPM", "PIB", "CAMBIO_USD"].map((serie) =>
      ({ serie, ano_ref, mediana: 4.5, coletado_em: "2026-07-24" })));
  const wb = buildExportWorkbook({
    caso: { nome: "Etapa 3", produto: "reestruturacao" },
    documentos: fixture.documentos, campos: fixture.campos,
    macro: { anuais, expectativas },
    agora: new Date("2026-07-31T12:00:00Z"),
  });
  const mod = wb.getWorksheet("Modelagem")!;

  // (a) NENHUMA referência a outra aba. O assert é por AUSÊNCIA de propósito:
  // não depende de saber quais abas existem, e pega qualquer uma nova.
  const abasCitadas = new Set<string>();
  let nFormulas = 0;
  const numerosEscritos: string[] = [];
  for (let r = 1; r <= mod.rowCount; r++) {
    for (let c = 1; c <= mod.columnCount; c++) {
      const v = mod.getRow(r).getCell(c).value;
      if (v && typeof v === "object" && "formula" in v) {
        nFormulas++;
        for (const m of String((v as { formula: string }).formula).matchAll(/'([^']+)'!/g)) abasCitadas.add(m[1]);
      } else if (typeof v === "number") {
        numerosEscritos.push(`${mod.getRow(r).getCell(c).address}`);
      }
    }
  }
  checar(abasCitadas.size === 0,
    "(38) nenhuma fórmula da Modelagem referencia outra aba — nem de dados, nem a Macro",
    `cita: ${[...abasCitadas].join(", ")}`);
  checar(nFormulas > 300,
    "(38) …e ela continua sendo um modelo em fórmula (não virou tabela de números)",
    `${nFormulas} fórmulas`);

  // (b) os valores brutos estão NA ABA. Sem isto, (a) passaria numa Modelagem
  // que simplesmente parou de ler qualquer coisa.
  const rotuloDe = (r: number) => String(mod.getRow(r).getCell(1).value ?? "");
  const linhaDe = (pred: (x: string) => boolean) => {
    for (let r = 1; r <= mod.rowCount; r++) if (pred(rotuloDe(r))) return r;
    return -1;
  };
  const rBase = linhaDe((x) => x.startsWith("BASE DO MODELO"));
  const rMacro = linhaDe((x) => x.startsWith("BASE MACRO"));
  checar(rBase > 0, "(38) a Modelagem carrega o bloco BASE DO MODELO");
  checar(rMacro > rBase, "(38) …e o bloco BASE MACRO, abaixo dele", `${rBase} → ${rMacro}`);

  // Os rótulos que o modelo lê têm de estar no bloco, com número.
  for (const rot of ["DRE · Receita Líquida", "Balanço · Passivo Circulante",
                     "Fluxo de Caixa · Saldo Inicial de Caixa"]) {
    const r = linhaDe((x) => x === rot);
    checar(r > 0, `(38) a base traz "${rot}"`);
    if (r < 0) continue;
    let temNumero = false;
    for (let c = 2; c <= 12; c++) if (typeof mod.getRow(r).getCell(c).value === "number") temNumero = true;
    checar(temNumero, `(38) …com valor extraído, não em branco (${rot})`);
  }

  // (c) o arquivo declara o CUSTO da independência. Uma base que é foto e não
  // diz que é foto entrega dois números diferentes sem ninguém perceber.
  const notaBase = notaDaLinha(mod, rBase);
  checar(/FOTO/i.test(notaBase) && /EXPORTE DE NOVO/i.test(notaBase),
    "(38) o bloco diz que é uma FOTO e que corrigir a origem exige exportar de novo",
    notaBase.slice(0, 160));

  // (d) rótulo não declarado FALHA a geração. É o que impede um `hist()` novo
  // de sair como zero — e zero num modelo financeiro é um número, não um erro.
  {
    let lancou = false;
    try {
      // `buscaNaBase` só é alcançável de dentro do export; o proxy é o próprio
      // contrato: LINHAS_BASE tem de cobrir tudo que o modelo pede. Se não
      // cobrisse, o export acima já teria lançado e nenhum assert deste bloco
      // teria rodado. Registra-se aqui para o motivo não se perder.
      lancou = true;
    } catch { /* impossível */ }
    checar(lancou,
      "(38) o export inteiro rodou sem lançar — logo LINHAS_BASE cobre todo rótulo que o modelo pede");
  }
}

// ---- 39: ETAPA 5 — o seletor de inputs macro ------------------------------
// "Permitir que o usuário escolha qual conjunto de inputs macroeconômicos será
// utilizado… ao alterar a opção, toda a modelagem deve ser recalculada
// automaticamente… flexível para permitir adicionar novos tipos futuramente
// sem grandes alterações estruturais."
//
// As três exigências viram três afirmações verificáveis:
//   (a) existe UMA célula de escolha, com lista fechada;
//   (b) a premissa que dirige a projeção LÊ essa célula — é isso, e só isso,
//       que faz "trocar a opção recalcula tudo": o resto do modelo já pende da
//       premissa;
//   (c) as opções da lista são as MESMAS linhas da tabela — se fossem duas
//       listas, acrescentar uma metodologia exigiria lembrar das duas, e um dia
//       alguém escolheria uma opção que o MATCH não acha.
{
  const V = "v-seletor";
  const documentos: DocumentoParaExport[] = [2024, 2025].map((ano) => ({
    id: `ds-${ano}`, tipo_taxonomia: "BALANCO", status: "em_validacao",
    entidade: { razao_social: "Seletor Ltda." },
    periodo: { tipo: "anual", referencia: `12M${String(ano).slice(2)}` },
    documento_versao: [{ id: `${V}-${ano}`, n_versao: 1, nome_original: `BP_${ano}.pdf` }],
  }) as unknown as DocumentoParaExport);
  const campos: CampoExtraido[] = [2024, 2025].map((ano, i) => campo({
    documento_versao_id: `${V}-${ano}`, chave: "Caixa e bancos", secao: "Disponível",
    valor_num: 100 + i, unidade: "milhar", ordem: 0, periodo_coluna: String(ano),
  }));
  const anuais = Array.from({ length: 11 }, (_, k) => [
    { serie: "IPCA", ano: 2015 + k, meses: 12, retorno: 4 + k * 0.1 },
    { serie: "IGPM", ano: 2015 + k, meses: 12, retorno: 5 + k * 0.1 },
  ]).flat();
  const expectativas = [2026, 2027, 2028].flatMap((ano_ref) =>
    ["IPCA", "SELIC", "IGPM", "PIB"].map((serie) =>
      ({ serie, ano_ref, mediana: 4.5, coletado_em: "2026-07-24" })));
  const mod = buildExportWorkbook({
    caso: { nome: "Caso Seletor", produto: "reestruturacao" }, documentos, campos,
    macro: { anuais, expectativas }, agora: new Date("2026-07-31T12:00:00Z"),
  }).getWorksheet("Modelagem")!;

  const rotuloDe = (r: number) => String(mod.getRow(r).getCell(1).value ?? "");
  const linhaDe = (pred: (x: string) => boolean) => {
    for (let r = 1; r <= mod.rowCount; r++) if (pred(rotuloDe(r))) return r;
    return -1;
  };

  // (a) a célula de escolha.
  const rSel = linhaDe((x) => x === "Índice macro que dirige a projeção");
  checar(rSel > 0, "(39) existe a célula que escolhe a metodologia de inputs macro");
  const celSel = rSel > 0 ? mod.getRow(rSel).getCell(3) : null;
  const dv = celSel?.dataValidation as { type?: string; formulae?: string[] } | undefined;
  checar(dv?.type === "list" && (dv.formulae?.[0]?.length ?? 0) > 10,
    "(39) …com lista fechada (dropdown), não texto livre", JSON.stringify(dv?.formulae));
  // Marcada como INPUT: é a terceira célula que comanda o modelo, junto de
  // entidade e último exercício realizado, e tem de se parecer com elas.
  checar((celSel?.fill as { fgColor?: { argb?: string } } | undefined)?.fgColor?.argb === "FFFFF9C4",
    "(39) …e pintada como input, como as outras células que comandam o modelo");

  // (b) a premissa lê a célula. É o elo que faz "trocar recalcula tudo".
  const rPrem = linhaDe((x) => x === "Inflação esperada (metodologia selecionada)");
  checar(rPrem > 0, "(39) a premissa que dirige a projeção existe");
  const fPrem = String((mod.getRow(rPrem).getCell(3 + 4 * 13 + 12).value as { formula?: string } | undefined)?.formula ?? "");
  checar(fPrem.includes(`$C$${rSel}`),
    "(39) …e ela indexa a célula de escolha (trocar a opção recalcula o modelo)", fPrem.slice(0, 120));
  checar(/="",""/.test(fPrem),
    "(39) …guardando o vazio: metodologia sem dado deixa a premissa em branco, não em 0",
    fPrem.slice(0, 120));

  // (c) as opções são as linhas da tabela — uma lista só.
  const opcoes = (dv?.formulae?.[0] ?? "").replace(/^"|"$/g, "").split(",").filter(Boolean);
  checar(opcoes.length >= 4,
    "(39) o arquivo oferece várias metodologias", `${opcoes.length}: ${opcoes.join(" | ")}`);
  for (const opt of opcoes) {
    checar(linhaDe((x) => x === opt) > 0,
      `(39) a opção "${opt}" existe como LINHA da tabela (o MATCH acha)`);
  }
  // …e o inverso: toda linha da tabela é uma opção. Sem isto, uma metodologia
  // poderia existir na planilha e ser inalcançável pelo dropdown.
  const rTab = linhaDe((x) => x.startsWith("INPUTS MACRO"));
  checar(rTab > 0 && rTab < rPrem, "(39) a tabela de metodologias vem ANTES das premissas", `${rTab} → ${rPrem}`);
  for (let r = rTab + 1; r <= mod.rowCount; r++) {
    const rot = rotuloDe(r);
    if (!rot) break;
    checar(opcoes.includes(rot), `(39) a linha "${rot}" da tabela é oferecida no dropdown`);
  }

  // A lista cobre o que o dono pediu: Focus, médias históricas e CAGR.
  checar(opcoes.some((o) => o.startsWith("Focus")), "(39) a lista traz metodologias do Focus");
  checar(opcoes.some((o) => o.startsWith("Média histórica")), "(39) …médias históricas");
  checar(opcoes.some((o) => /CAGR/.test(o)), "(39) …e o CAGR histórico");

  // O juro NÃO passa pelo seletor: é outra pergunta.
  const rJuro = linhaDe((x) => x === "Juro esperado (Selic — Focus)");
  const fJuro = String((mod.getRow(rJuro).getCell(3 + 4 * 13 + 12).value as { formula?: string } | undefined)?.formula ?? "");
  checar(rJuro > 0 && !fJuro.includes(`$C$${rSel}`),
    "(39) o juro da dívida NÃO depende do seletor (índice que corrige preço ≠ custo da dívida)",
    fJuro.slice(0, 100));
}

// ---- 40: ETAPA 6 — o modelo RESOLVE, e o seletor move mesmo o resultado ----
// Este é o único invariante que confere NÚMERO no modelo, não estrutura. Ele
// existe porque a Etapa 6 pede "todas as fórmulas funcionando" e "validar um
// caso real do início ao fim", e nenhuma quantidade de assert sobre o TEXTO da
// fórmula responde isso: um modelo pode ter 4.000 fórmulas bem formadas e
// devolver #VALUE! em todas.
//
// A alternativa seria recalcular no LibreOffice. MEDIDO neste container: ele se
// recusa a abrir até um .xlsx mínimo de três células, e recusa igualmente o
// arquivo v35 que o dono abriu no Excel — é o ambiente. Então o avaliador do
// próprio arnês foi estendido (INDEX/MATCH/IF/N/^/comparações) e memoizado.
{
  const fixture = JSON.parse(
    readFileSync(new URL("./fixtures/book-vertentes.json", import.meta.url), "utf8"),
  ) as { documentos: DocumentoParaExport[]; campos: CampoExtraido[] };
  const anuais = Array.from({ length: 11 }, (_, k) => [
    { serie: "IPCA", ano: 2015 + k, meses: 12, retorno: 4 + k * 0.1 },
    { serie: "IGPM", ano: 2015 + k, meses: 12, retorno: 9 + k * 0.1 },
  ]).flat();
  const expectativas = [2026, 2027, 2028].flatMap((ano_ref) =>
    ["IPCA", "SELIC", "IGPM", "PIB"].map((serie) =>
      ({ serie, ano_ref, mediana: serie === "IPCA" ? 4.5 : 7.5, coletado_em: "2026-07-24" })));
  const mod = buildExportWorkbook({
    caso: { nome: "Validação final", produto: "reestruturacao" },
    documentos: fixture.documentos, campos: fixture.campos,
    macro: { anuais, expectativas }, agora: new Date("2026-07-31T12:00:00Z"),
  }).getWorksheet("Modelagem")!;

  const letra = (i: number) => mod.getColumn(i).letter;
  const nA = 5;
  const colFY = (y: number) => 3 + y * 13 + 12;
  const rotuloDe = (r: number) => String(mod.getRow(r).getCell(1).value ?? "");
  const linhaDe = (x: string) => { for (let r = 1; r <= mod.rowCount; r++) if (rotuloDe(r) === x) return r; return -1; };

  // (a) TODAS as fórmulas do modelo resolvem. `null` aqui é o avaliador dizendo
  //     "não sei" — o que, para as funções que ele cobre, significa erro de
  //     fórmula (#VALUE!, #N/A, #REF!, divisão por zero fora de IFERROR).
  let total = 0; const naoResolvem: string[] = [];
  const ultimaLinhaModelo = linhaDe("Caixa do balanço = saldo final do fluxo");
  for (let r = 1; r <= ultimaLinhaModelo; r++) {
    for (let c = 3; c <= 2 + nA * 13; c++) {
      const v = mod.getRow(r).getCell(c).value;
      if (!(v && typeof v === "object" && "formula" in v)) continue;
      total++;
      if (avaliarCelula(mod, letra(c), r) == null && naoResolvem.length < 5) {
        naoResolvem.push(`${letra(c)}${r} (${rotuloDe(r)})`);
      }
    }
  }
  checar(total > 3000, "(40) o modelo tem milhares de fórmulas para resolver", `${total}`);
  checar(naoResolvem.length === 0,
    "(40) TODAS as fórmulas do modelo resolvem (nenhuma vira erro)", naoResolvem.join(" / "));

  // (b) as CONFERÊNCIAS fecham em zero. É a prova contábil: se o balanço não
  //     fechasse, o modelo estaria errado por mais bem formado que fosse.
  const rBal = linhaDe("Balanço fecha (Ativo − Passivo − PL)");
  const rCaixa = linhaDe("Caixa do balanço = saldo final do fluxo");
  for (let y = 0; y < nA; y++) {
    for (const [nome, r] of [["Balanço fecha", rBal], ["Caixa do balanço", rCaixa]] as Array<[string, number]>) {
      const v = avaliarCelula(mod, letra(colFY(y)), r);
      checar(typeof v === "number" && Math.abs(v) < 0.01,
        `(40) "${nome}" fecha em zero no exercício ${y + 1}`, String(v));
    }
  }
  // …e a identidade, medida nas duas linhas independentes.
  for (let y = 0; y < nA; y++) {
    const a = avaliarCelula(mod, letra(colFY(y)), linhaDe("TOTAL DO ATIVO"));
    const p = avaliarCelula(mod, letra(colFY(y)), linhaDe("TOTAL DO PASSIVO E PL"));
    checar(typeof a === "number" && typeof p === "number" && Math.abs(a - p) < 0.01,
      `(40) Ativo = Passivo + PL no exercício ${y + 1}`, `${a} × ${p}`);
  }

  // (c) TROCAR A METODOLOGIA MOVE O RESULTADO. É a exigência literal da Etapa 5
  //     ("ao alterar a opção, toda a modelagem deve ser recalculada"), e é a
  //     única forma de prová-la: comparar o número antes e depois.
  const rSel = linhaDe("Índice macro que dirige a projeção");
  const rRL = linhaDe("Receita Líquida");
  const antes = avaliarCelula(mod, letra(colFY(nA - 1)), rRL);
  // Nesta fixture o IGP-M do Focus é 7,5% contra 4,5% do IPCA: a receita do
  // último exercício projetado TEM de subir.
  mod.getRow(rSel).getCell(3).value = "Focus — IGP-M";
  esquecerMemoria(mod);
  const depois = avaliarCelula(mod, letra(colFY(nA - 1)), rRL);
  checar(typeof antes === "number" && typeof depois === "number" && depois > antes * 1.01,
    "(40) trocar a metodologia no seletor RECALCULA o modelo (receita projetada muda)",
    `IPCA→${antes} | IGP-M→${depois}`);
  // E continua fechando: um seletor que quebra a identidade contábil seria pior
  // que não ter seletor.
  for (let y = 0; y < nA; y++) {
    const v = avaliarCelula(mod, letra(colFY(y)), rBal);
    checar(typeof v === "number" && Math.abs(v) < 0.01,
      `(40) …e o balanço continua fechando com a outra metodologia (exercício ${y + 1})`, String(v));
  }
  // (d) "Dado encontrado" tem de DIZER A VERDADE sobre o que existe para a
  //     entidade escolhida. Defeito real desta sessão: a primeira versão da
  //     linha (Etapa 3) checava só se a COLUNA existia na base, e depois a
  //     segunda usou `ISNUMBER(INDEX(...))` — que é VERDADEIRO para célula
  //     vazia, porque INDEX de vazio vale 0 no Excel. Nos dois casos a linha
  //     dizia "DRE+Balanço" para uma entidade sem DRE, com receita zero ao
  //     lado. `COUNT` é o idioma correto.
  {
    const rEnt = linhaDe("Entidade modelada");
    const rDado = linhaDe("Dado encontrado");
    // No book, só a Metalúrgica tem DRE; as outras quatro têm apenas Balanço.
    mod.getRow(rSel).getCell(3).value = "Focus — IPCA";
    mod.getRow(rEnt).getCell(3).value = "VERTENTES COMPONENTES AUTOMOTIVOS LTDA.";
    esquecerMemoria(mod);
    const dado = avaliarCelula(mod, letra(colFY(0)), rDado);
    const rl = avaliarCelula(mod, letra(colFY(0)), rRL);
    checar(dado === "só Balanço",
      "(40) entidade sem DRE é declarada como \"só Balanço\", não como \"DRE+Balanço\"", String(dado));
    checar(rl === 0,
      "(40) …e a receita dela é mesmo 0, que é o que a linha está avisando", String(rl));
    mod.getRow(rEnt).getCell(3).value = "VERTENTES METALÚRGICA LTDA.";
    esquecerMemoria(mod);
    checar(avaliarCelula(mod, letra(colFY(0)), rDado) === "DRE+Balanço",
      "(40) …e a entidade que tem as duas é declarada como \"DRE+Balanço\"");
  }

  // Metodologia SEM dado para o exercício deixa a premissa vazia, e o modelo
  // segue calculando (é o que o `N()` garante) em vez de virar #VALUE!.
  mod.getRow(rSel).getCell(3).value = "Média histórica 10a — IGP-M";
  esquecerMemoria(mod);
  const comMedia = avaliarCelula(mod, letra(colFY(nA - 1)), rRL);
  checar(typeof comMedia === "number",
    "(40) com a média histórica, o modelo segue resolvendo (nada de #VALUE!)", String(comMedia));
}

// ---- 41: MOEDA (db/migrations/0035) — item 2 do §7.4 do Onboarding ---------
// Até a 0035 a moeda era extraída e descartada: uma linha em USD entrava na mesma
// soma que uma em BRL, sem marca nenhuma. Erro pelo câmbio inteiro (~5x) num
// arquivo que fecha — a assinatura exata da família de falha que este projeto
// combate. Estas verificações travam as duas metades da correção: a moeda APARECE
// onde discrimina, e a soma que não é somável NÃO é emitida.
{
  const VB = "vBRL", VU = "vUSD";
  const campos: CampoExtraido[] = [
    // Operação no Brasil, em reais.
    campo({ chave: "Caixa e bancos", secao: "Ativo Circulante", valor_num: 1200, moeda: "BRL", documento_versao_id: VB }),
    campo({ chave: "Duplicatas a receber", secao: "Ativo Circulante", valor_num: 3400, moeda: "BRL", documento_versao_id: VB }),
    // Subsidiária exportadora, em dólares — MESMOS valores de propósito: sem a
    // coluna de moeda, estas linhas são indistinguíveis das de cima.
    campo({ chave: "Caixa e bancos", secao: "Ativo Circulante", valor_num: 1200, moeda: "USD", documento_versao_id: VU }),
    campo({ chave: "Duplicatas a receber", secao: "Ativo Circulante", valor_num: 3400, moeda: "USD", documento_versao_id: VU }),
  ];
  const documentos: DocumentoParaExport[] = [
    { id: "dBR", tipo_taxonomia: "BALANCO", entidade: { razao_social: "Operação BR" },
      periodo: { tipo: "anual", referencia: "2025" }, documento_versao: [{ id: VB, nome_original: "bp-br.pdf" }] },
    { id: "dUS", tipo_taxonomia: "BALANCO", entidade: { razao_social: "Export Co" },
      periodo: { tipo: "anual", referencia: "2025" }, documento_versao: [{ id: VU, nome_original: "bp-us.pdf" }] },
  ];
  const ws = buildExportWorkbook({ caso: { nome: "C", produto: "rx" }, documentos, campos, agora: new Date("2026-07-27T12:00:00Z") })
    .getWorksheet("Balanço")!;

  const cabecalhos: string[] = [];
  for (let c = 1; c <= ws.columnCount; c++) cabecalhos.push(String(ws.getRow(1).getCell(c).value ?? ""));
  const hBR = cabecalhos.find((h) => h.startsWith("Operação BR")) ?? "";
  const hUS = cabecalhos.find((h) => h.startsWith("Export Co")) ?? "";
  checar(hBR.includes("(BRL)"),
    "(41) com duas moedas no arquivo, a coluna em real DIZ que é BRL", hBR);
  checar(hUS.includes("(USD)"),
    "(41) …e a coluna em dólar DIZ que é USD — era o que faltava para o analista ver", hUS);
}

// ---- 42: coluna que MISTURA moedas não recebe soma -------------------------
// O caso grave: duas moedas dentro da MESMA coluna (mesma entidade × período).
// Nenhuma inspeção visual pega, e um SUM ali entrega um total plausível e errado.
{
  const V = "vMisto";
  const campos: CampoExtraido[] = [
    campo({ chave: "Receita mercado interno", secao: "Ativo Circulante", valor_num: 5000, moeda: "BRL", documento_versao_id: V }),
    campo({ chave: "Receita de exportação", secao: "Ativo Circulante", valor_num: 2000, moeda: "USD", documento_versao_id: V }),
  ];
  const documentos: DocumentoParaExport[] = [{
    id: "dMisto", tipo_taxonomia: "BALANCO", entidade: { razao_social: "Mista" },
    periodo: { tipo: "anual", referencia: "2025" }, documento_versao: [{ id: V, nome_original: "bp-misto.pdf" }],
  }];
  const ws = buildExportWorkbook({ caso: { nome: "C", produto: "rx" }, documentos, campos, agora: new Date("2026-07-27T12:00:00Z") })
    .getWorksheet("Balanço")!;

  const linhaDe = (rot: string) => {
    for (let r = 1; r <= ws.rowCount; r++) if (String(ws.getRow(r).getCell(1).value ?? "") === rot) return r;
    return -1;
  };
  const rAC = linhaDe("Ativo Circulante");
  const cel = ws.getRow(rAC).getCell(2);
  const temFormula = typeof cel.value === "object" && cel.value != null && "formula" in (cel.value as object);
  checar(!temFormula,
    "(42) coluna com moedas misturadas NÃO recebe fórmula de soma (7000 seria falso)",
    JSON.stringify(cel.value));
  checar(String(cel.value ?? "").includes("não somável"),
    "(42) …e a célula diz POR QUE está vazia, em vez de ficar em branco", String(cel.value));
  checar(notaDaLinha(ws, rAC).includes("BRL + USD"),
    "(42) …e a nota nomeia as duas moedas encontradas", notaDaLinha(ws, rAC).slice(0, 140));
  checar(String(ws.getRow(1).getCell(2).value ?? "").includes("MOEDAS MISTURADAS"),
    "(42) …e o cabeçalho da coluna avisa antes de o analista somar à mão",
    String(ws.getRow(1).getCell(2).value));
  // Os valores individuais continuam TODOS lá: recusar a soma não é esconder dado.
  const rotulos: string[] = [];
  for (let r = 1; r <= ws.rowCount; r++) rotulos.push(String(ws.getRow(r).getCell(1).value ?? ""));
  checar(rotulos.includes("Receita mercado interno") && rotulos.includes("Receita de exportação"),
    "(42) as duas linhas seguem visíveis — só o total foi omitido");
}

// ---- 43: book de uma moeda só não ganha ruído ------------------------------
// Rótulo redundante em toda coluna ensina o analista a não ler o cabeçalho.
{
  const V = "vSo";
  const campos: CampoExtraido[] = [
    campo({ chave: "Caixa e bancos", secao: "Ativo Circulante", valor_num: 1200, moeda: "BRL", documento_versao_id: V }),
    campo({ chave: "Duplicatas a receber", secao: "Ativo Circulante", valor_num: 3400, moeda: "BRL", documento_versao_id: V }),
  ];
  const documentos: DocumentoParaExport[] = [{
    id: "dSo", tipo_taxonomia: "BALANCO", entidade: { razao_social: "Só BRL" },
    periodo: { tipo: "anual", referencia: "2025" }, documento_versao: [{ id: V, nome_original: "bp.pdf" }],
  }];
  const ws = buildExportWorkbook({ caso: { nome: "C", produto: "rx" }, documentos, campos, agora: new Date("2026-07-27T12:00:00Z") })
    .getWorksheet("Balanço")!;
  checar(!String(ws.getRow(1).getCell(2).value ?? "").includes("(BRL)"),
    "(43) arquivo com uma moeda só não repete a moeda em cada cabeçalho",
    String(ws.getRow(1).getCell(2).value));
  const rAC = (() => {
    for (let r = 1; r <= ws.rowCount; r++) if (String(ws.getRow(r).getCell(1).value ?? "") === "Ativo Circulante") return r;
    return -1;
  })();
  checar(avaliar(ws, "B", rAC) === 4600,
    "(43) …e a soma continua sendo emitida normalmente", String(avaliar(ws, "B", rAC)));
}

console.log(`${ok} verificações OK / ${falhas.length} falhas`);
for (const f of falhas) console.log("  FALHOU:", f);
process.exit(falhas.length ? 1 : 0);
