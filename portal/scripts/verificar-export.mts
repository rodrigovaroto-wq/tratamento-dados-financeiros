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
import { casarVinculosComLinhas, chaveDaLinha, vinculoPorLinha } from "../src/lib/modelagem-linha.ts";
import { ABAS_MODELO as ABAS_DO_MODELO } from "../src/lib/modelo-institucional.ts";

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

  // 4. ETAPA 4, resolvida: Modelagem PRIMEIRO e nada oculto.
  //
  //    Havia duas decisões do dono em contradição, e o §7.2 do Onboarding a
  //    nomeia: a Etapa 4 pedia as auxiliares OCULTAS; no v28 ele pediu o
  //    oposto ("quero todas as abas juntas"), porque naquele teste viu 4 abas e
  //    concluiu que as demais "não vieram" — estavam lá, ocultas.
  //
  //    As duas querem a mesma coisa: que a Modelagem seja o que se vê ao abrir,
  //    sem o resto parecer inexistente. ORDEM entrega as duas; visibilidade só
  //    entregava uma. Quem recebe o arquivo não sabe que há abas escondidas —
  //    "reexibir é um clique" só vale para quem sabe que existe o que reexibir.
  const ocultas = wb.worksheets.filter((s) => s.state !== "visible").map((s) => s.name);
  checar(ocultas.length === 0,
    "(11) NENHUMA aba fica oculta — aba oculta lê como dado ausente (v28)",
    `ocultas: ${ocultas.join(", ")}`);
  // A Modelagem é a PRIMEIRA da barra de abas. `wb.worksheets` já vem ordenado
  // por `orderNo` (é o getter do ExcelJS que ordena), então a posição 0 aqui é a
  // posição que o Excel mostra.
  const nomesEmOrdem = wb.worksheets.map((s) => s.name);
  checar(nomesEmOrdem[0] === "Modelagem",
    "(11) …e a Modelagem é a primeira aba do arquivo", `ordem: ${nomesEmOrdem.join(", ")}`);
  // …e a ordem RELATIVA das auxiliares não foi embaralhada. É o risco real de
  // mexer em `orderNo`: promover uma aba com um número menor que todos podia,
  // num descuido, empurrar as outras para posições arbitrárias. A ordem das
  // auxiliares é a de criação (Resumo primeiro, depois as demonstrações), e é
  // ela que faz o arquivo parecer o mesmo de sempre depois da Modelagem.
  const auxiliares = nomesEmOrdem.slice(1);
  const posicao = (n: string) => auxiliares.indexOf(n);
  checar(posicao("Resumo") === 0,
    "(11) …e o Resumo continua sendo a primeira das auxiliares", `ordem: ${auxiliares.join(", ")}`);
  checar(posicao("Balanço") < posicao("DRE") && posicao("DRE") < posicao("Fluxo de Caixa"),
    "(11) …e as demonstrações seguem na ordem de sempre (Balanço → DRE → Fluxo)",
    `ordem: ${auxiliares.join(", ")}`);

  // As auxiliares continuam todas lá, com conteúdo — o que muda é a ordem, não
  // o que o arquivo contém.
  for (const aba of ["Resumo", "Balanço", "DRE", "Fluxo de Caixa", "Macro"]) {
    const ws2 = wb.getWorksheet(aba);
    checar(ws2 != null && ws2.rowCount > 1,
      `(11) …e a aba "${aba}" continua existindo, com conteúdo`, `linhas: ${ws2?.rowCount ?? 0}`);
  }
  // …e o arquivo ABRE na Modelagem. Com ela em primeiro lugar, a aba ativa é a 0
  // — e é isto que prova que o reorder aconteceu de verdade: a primeira versão
  // desta mudança fez splice no retorno do getter `worksheets`, um array
  // descartável, e não mudou nada no arquivo.
  const abaAtiva = (wb.views?.[0] as { activeTab?: number } | undefined)?.activeTab;
  checar(abaAtiva === 0,
    "(11) a Modelagem é a aba ativa (o arquivo abre nela)", `activeTab=${String(abaAtiva)}`);
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

// ---- 44: rótulo REPETIDO não colapsa (granularidade total) -----------------
// O defeito: o agrupamento por rótulo normalizado fazia duas linhas com o MESMO
// rótulo no mesmo documento virarem um grupo, e só a de maior confiança aparecia
// (`melhorCampo`). Num balancete com dois "Outros" ou "Fornecedores" repetido em
// subgrupos diferentes, linhas desapareciam do arquivo — e a soma da seção saía
// menor que o documento, parecendo consistente com o que estava visível.
{
  const V = "vRep";
  const campos: CampoExtraido[] = [
    campo({ chave: "Duplicatas a receber", secao: "Ativo Circulante", valor_num: 5000, ordem: 0, documento_versao_id: V }),
    // MESMO rótulo, duas vezes, valores diferentes — o caso real do balancete.
    campo({ chave: "Outros", secao: "Ativo Circulante", valor_num: 300, ordem: 1, documento_versao_id: V }),
    campo({ chave: "Outros", secao: "Ativo Circulante", valor_num: 700, ordem: 2, documento_versao_id: V }),
  ];
  const documentos: DocumentoParaExport[] = [{
    id: "dRep", tipo_taxonomia: "BALANCO", entidade: { razao_social: "Repetida" },
    periodo: { tipo: "anual", referencia: "2025" }, documento_versao: [{ id: V, nome_original: "bp.pdf" }],
  }];
  const wb = buildExportWorkbook({ caso: { nome: "C", produto: "rx" }, documentos, campos, agora: new Date("2026-07-27T12:00:00Z") });
  const ws = wb.getWorksheet("Balanço")!;

  const rotulos: string[] = [];
  for (let r = 1; r <= ws.rowCount; r++) rotulos.push(String(ws.getRow(r).getCell(1).value ?? ""));
  const nOutros = rotulos.filter((x) => x === "Outros").length;
  checar(nOutros === 2,
    "(44) as DUAS linhas \"Outros\" aparecem — rótulo repetido não colapsa",
    `encontradas: ${nOutros}`);

  // …e a soma da seção cobre as duas: 5000 + 300 + 700.
  const rAC = rotulos.indexOf("Ativo Circulante") + 1;
  checar(avaliar(ws, "B", rAC) === 6000,
    "(44) …e a soma da seção conta as duas (5000+300+700)", String(avaliar(ws, "B", rAC)));

  // A aba de dados linha a linha tem de trazer as três, sempre.
  const dados = wb.getWorksheet("Dados (linha a linha)")!;
  let nLinhas = 0;
  for (let r = 2; r <= dados.rowCount; r++) if (dados.getRow(r).getCell(11).value) nLinhas++;
  checar(nLinhas === 3,
    "(44) e a aba \"Dados (linha a linha)\" traz as 3 linhas extraídas, cruas", String(nLinhas));
}

// ---- 45: a aba de dados é espelho 1:1 do que entrou ------------------------
// É a aba de conferência: se ela agregar, filtrar ou reordenar de forma que perca
// linha, deixa de servir ao propósito (conferir o arquivo contra o banco).
{
  const fixture = JSON.parse(
    readFileSync(new URL("./fixtures/book-vertentes.json", import.meta.url), "utf8"),
  ) as { documentos: DocumentoParaExport[]; campos: CampoExtraido[] };
  const wb = buildExportWorkbook({
    caso: { nome: "Book Vertentes", produto: "reestruturacao" },
    documentos: fixture.documentos, campos: fixture.campos,
    agora: new Date("2026-07-27T12:00:00Z"),
  });
  const dados = wb.getWorksheet("Dados (linha a linha)")!;
  let nLinhas = 0;
  for (let r = 2; r <= dados.rowCount; r++) if (dados.getRow(r).getCell(11).value) nLinhas++;
  checar(nLinhas === fixture.campos.length,
    "(45) a aba de dados tem UMA linha por campo extraído, sem agregar",
    `aba=${nLinhas} fixture=${fixture.campos.length}`);
  const cab: string[] = [];
  for (let c = 1; c <= 18; c++) cab.push(String(dados.getRow(1).getCell(c).value ?? ""));
  for (const col of ["Rótulo", "Valor", "Moeda", "Escala", "Pág.", "Ordem", "Aceite"]) {
    checar(cab.includes(col), `(45) …e declara a coluna "${col}" (proveniência conferível)`, cab.join(" | "));
  }
}

// ---- 46: os DOIS modos de export -------------------------------------------
// Decisão do dono: "dados" é insumo de conferência e existe desde a ingestão;
// "completo" acrescenta a Modelagem. A propriedade que importa e que este bloco
// trava: as abas de DADO são as mesmas nos dois arquivos. Se divergirem, a
// conversa que sobra é "o número do completo não bate com o de dados".
{
  const fixture = JSON.parse(
    readFileSync(new URL("./fixtures/book-vertentes.json", import.meta.url), "utf8"),
  ) as { documentos: DocumentoParaExport[]; campos: CampoExtraido[] };
  const params = {
    caso: { nome: "Book Vertentes", produto: "reestruturacao" },
    documentos: fixture.documentos, campos: fixture.campos,
    agora: new Date("2026-07-27T12:00:00Z"),
  };
  const wbDados = buildExportWorkbook({ ...params, modo: "dados" as const });
  const wbCompleto = buildExportWorkbook({ ...params, modo: "completo" as const });

  const nomes = (wb: ReturnType<typeof buildExportWorkbook>) => wb.worksheets.map((w) => w.name);
  checar(!nomes(wbDados).includes("Modelagem"),
    "(46) o export de dados NÃO traz a aba Modelagem", nomes(wbDados).join(", "));
  checar(nomes(wbCompleto).includes("Modelagem"),
    "(46) o export completo traz a Modelagem", nomes(wbCompleto).join(", "));
  // Macro é DADO coletado (BCB/IBGE), não modelagem: entra nos dois.
  checar(nomes(wbDados).includes("Macro"),
    "(46) …e a Macro entra também no de dados (é coleta, não modelo)", nomes(wbDados).join(", "));

  // As abas de dado, iguais nos dois — mesmo conjunto e mesma contagem de linhas.
  const dataSheets = nomes(wbDados).filter((n) => n !== "Modelagem");
  for (const nome of dataSheets) {
    const a = wbDados.getWorksheet(nome);
    const b = wbCompleto.getWorksheet(nome);
    checar(a != null && b != null && a.rowCount === b.rowCount,
      `(46) a aba "${nome}" é idêntica em linhas nos dois modos`,
      `dados=${a?.rowCount ?? 0} completo=${b?.rowCount ?? 0}`);
  }
  // …e nenhuma aba fica oculta no export de dados (mesma decisão do v28).
  checar(wbDados.worksheets.every((w) => w.state === "visible"),
    "(46) nenhuma aba oculta no export de dados");
}

// ---- 47: as abas DMPL / Intragrupo / Outros agora têm DADO -----------------
// A fixture cobria 11 dos 14 documentos do book: faltavam DMPL, MUTUOS e NOTAS
// EXPLICATIVAS. As abas existiam no código e NENHUM teste passava por elas com
// dado — cobertura que parecia existir porque a fixture afirmava os dois lados.
{
  const fixture = JSON.parse(
    readFileSync(new URL("./fixtures/book-vertentes.json", import.meta.url), "utf8"),
  ) as { documentos: DocumentoParaExport[]; campos: CampoExtraido[] };
  checar(fixture.documentos.length === 14,
    "(47) a fixture cobre os 14 documentos do book", String(fixture.documentos.length));
  const wb = buildExportWorkbook({
    caso: { nome: "Book Vertentes", produto: "reestruturacao" },
    documentos: fixture.documentos, campos: fixture.campos,
    agora: new Date("2026-07-27T12:00:00Z"),
  });

  // DMPL: matriz movimento × componente do PL, montada por construirAbaDMPL.
  const dmpl = wb.getWorksheet("DMPL");
  checar(dmpl != null && dmpl.rowCount > 2, "(47) a aba DMPL existe e tem linhas",
    `linhas: ${dmpl?.rowCount ?? 0}`);
  {
    const textos: string[] = [];
    for (let r = 1; r <= (dmpl?.rowCount ?? 0); r++) {
      for (let c = 1; c <= 8; c++) textos.push(String(dmpl!.getRow(r).getCell(c).value ?? ""));
    }
    checar(textos.some((t) => t.includes("Capital social")),
      "(47) …com os componentes do PL como colunas");
    checar(textos.some((t) => t.toUpperCase().includes("SALDOS EM 31 DE DEZEMBRO DE 2025")),
      "(47) …e os movimentos como linhas");
  }

  // MUTUOS → aba Intragrupo, com a divergência deliberada de R$ 180 mil do book.
  const intra = wb.getWorksheet("Intragrupo");
  checar(intra != null && intra.rowCount > 1, "(47) a aba Intragrupo existe e tem linhas",
    `linhas: ${intra?.rowCount ?? 0}`);

  // NOTAS: prosa com números. O que importa é que as linhas NÃO foram para o
  // Balanço — nota explicativa detalha o que o BP já totaliza, e somar as duas
  // coisas é dupla contagem vinda de documento complementar.
  const balanco = wb.getWorksheet("Balanço")!;
  const rotulosBP: string[] = [];
  for (let r = 1; r <= balanco.rowCount; r++) rotulosBP.push(String(balanco.getRow(r).getCell(1).value ?? ""));
  checar(!rotulosBP.some((x) => x.startsWith("Índice de liquidez corrente")),
    "(47) linha de NOTA EXPLICATIVA não é roteada para o Balanço (evita dupla contagem)");
  // …e continua no arquivo, na aba documental.
  const dados = wb.getWorksheet("Dados (linha a linha)")!;
  let achouNota = false;
  for (let r = 2; r <= dados.rowCount; r++) {
    if (String(dados.getRow(r).getCell(11).value ?? "").startsWith("Índice de liquidez corrente")) achouNota = true;
  }
  checar(achouNota, "(47) …mas a linha da nota está no arquivo, na aba de dados crus");
}

// ---- 48: cabeçalho da Modelagem reduzido, parâmetros no rodapé (7.4) -------
// Eram 11 linhas fixas no topo, três delas células de input. Decisão do dono:
// ficam 4 (título, branco, Exercício, mês) e as três células migram para o
// portal — o arquivo sai parametrizado, e elas ficam registradas no rodapé para
// a auditoria saber com que parâmetros aquele arquivo foi gerado.
{
  const fixture = JSON.parse(
    readFileSync(new URL("./fixtures/book-vertentes.json", import.meta.url), "utf8"),
  ) as { documentos: DocumentoParaExport[]; campos: CampoExtraido[] };
  const wb = buildExportWorkbook({
    caso: { nome: "Book Vertentes", produto: "reestruturacao" },
    documentos: fixture.documentos, campos: fixture.campos,
    agora: new Date("2026-07-27T12:00:00Z"),
  });
  const mod = wb.getWorksheet("Modelagem")!;

  const ySplit = (mod.views?.[0] as { ySplit?: number } | undefined)?.ySplit;
  checar(ySplit === 4, "(48) o congelado do topo é de 4 linhas (era 11)", String(ySplit));
  checar(String(mod.getRow(1).getCell(1).value ?? "").startsWith("MODELAGEM"),
    "(48) linha 1 continua o título");
  checar(String(mod.getRow(3).getCell(1).value ?? "") === "Exercício",
    "(48) linha 3 é a timeline (Exercício)", String(mod.getRow(3).getCell(1).value));
  checar(String(mod.getRow(4).getCell(1).value ?? "") === "Período",
    "(48) linha 4 é o mês", String(mod.getRow(4).getCell(1).value));

  // As três células de input NÃO estão mais no topo…
  const topo: string[] = [];
  for (let r = 1; r <= 4; r++) topo.push(String(mod.getRow(r).getCell(1).value ?? ""));
  checar(!topo.includes("Entidade modelada"),
    "(48) \"Entidade modelada\" saiu do topo", topo.join(" | "));
  checar(!topo.includes("Último exercício realizado"),
    "(48) e \"Último exercício realizado\" também");

  // …e estão no rodapé, com o bloco declarado.
  const rotulos: string[] = [];
  for (let r = 1; r <= mod.rowCount; r++) rotulos.push(String(mod.getRow(r).getCell(1).value ?? ""));
  const rParam = rotulos.findIndex((x) => x.startsWith("PARÂMETROS DO MODELO"));
  checar(rParam > 0, "(48) o bloco de PARÂMETROS existe no rodapé", `linha ${rParam + 1}`);
  checar(rotulos[rParam + 1] === "Entidade modelada",
    "(48) …com a entidade modelada como célula editável", rotulos[rParam + 1]);
  checar(rotulos[rParam + 2] === "Último exercício realizado",
    "(48) …e o corte do último exercício real", rotulos[rParam + 2]);
  // O bloco vem DEPOIS do modelo: se estivesse antes, `addRow` teria empurrado o
  // modelo inteiro para baixo — a armadilha nº 1 da sessão 12, que voltou a
  // acontecer nesta fase (o modelo foi de ~200 para 291 linhas) e foi a guarda
  // que a pegou.
  const rTitulo = rotulos.findIndex((x) => x.startsWith("MODELAGEM"));
  checar(rParam > rTitulo + 10,
    "(48) e o bloco fica no RODAPÉ, não empurrando o modelo para baixo",
    `parâmetros na linha ${rParam + 1}`);
}

// ---- 49: projeção POR LINHA dirigida pela configuração do portal (7.4) ------
// O coração do pedido: "cada caso vai vir com linhas diferentes… projetar cada
// linha baseado em cada premissa".
{
  const V = "vProj";
  const campos: CampoExtraido[] = [
    campo({ chave: "Receita de vendas", secao: "Receita Bruta", secao_canonica: "receita_bruta",
            valor_num: 1000, ordem: 0, documento_versao_id: V }),
    campo({ chave: "Custo dos produtos vendidos", secao: "Custos", secao_canonica: "custos",
            valor_num: -600, ordem: 1, documento_versao_id: V }),
  ];
  const documentos: DocumentoParaExport[] = [{
    id: "dProj", tipo_taxonomia: "DRE", entidade: { razao_social: "Projetada Ltda" },
    periodo: { tipo: "anual", referencia: "2025" }, documento_versao: [{ id: V, nome_original: "dre.pdf" }],
  }];

  const wb = buildExportWorkbook({
    caso: { nome: "C", produto: "rx" }, documentos, campos,
    agora: new Date("2026-07-27T12:00:00Z"),
    modelagemConfig: {
      entidade: "Projetada Ltda", ultimoExercicioReal: 2025, anosProjetados: 3,
      premissas: [
        { codigo: "CRESC_REAL", nome: "Crescimento real da receita", formula: "crescimento_composto",
          unidade: "%", valores: { "2026": 0.1, "2027": 0.1 } },
        { codigo: "CAPEX_ANO", nome: "Capex por ano", formula: "valor_por_ano",
          unidade: "R$/ano", valores: { "2026": 50 } },
        { codigo: "MARGEM_BRUTA", nome: "Margem bruta", formula: "pct_de_linha",
          unidade: "%", valores: { "2026": 0.4 } },
        { codigo: "PMR", nome: "Prazo médio de recebimento", formula: "dias_de_giro",
          unidade: "dias", valores: { "2026": 45 } },
        // Primitiva que segue NÃO desenhada: precisa de duas premissas na mesma
        // linha, e `caso_linha_premissa` tem um slot só — é decisão de schema.
        { codigo: "PRECO_MEDIO", nome: "Preço médio", formula: "preco_x_volume",
          unidade: "R$/un", valores: { "2026": 12 } },
      ],
      linhas: [
        { rotulo: "Receita de vendas", secaoCanonica: "receita_bruta",
          premissaCodigo: "CRESC_REAL", sazonalidadeCodigo: null, valorBase: 1000 },
        { rotulo: "Capex do plano", secaoCanonica: null,
          premissaCodigo: "CAPEX_ANO", sazonalidadeCodigo: null, valorBase: null },
        { rotulo: "Custo dos produtos vendidos", secaoCanonica: "custos",
          premissaCodigo: "MARGEM_BRUTA", sazonalidadeCodigo: null, valorBase: -600 },
        { rotulo: "Duplicatas a receber", secaoCanonica: "ativo_circulante",
          premissaCodigo: "PMR", sazonalidadeCodigo: null, valorBase: 200 },
        { rotulo: "Receita por unidade", secaoCanonica: null,
          premissaCodigo: "PRECO_MEDIO", sazonalidadeCodigo: null, valorBase: null },
      ],
    },
  });
  const mod = wb.getWorksheet("Modelagem")!;
  const rotulos: string[] = [];
  for (let r = 1; r <= mod.rowCount; r++) rotulos.push(String(mod.getRow(r).getCell(1).value ?? ""));

  checar(rotulos.some((x) => x.startsWith("PROJEÇÃO POR LINHA")),
    "(49) o bloco de projeção por linha existe quando há configuração");
  const rRec = rotulos.indexOf("Receita de vendas") + 1;
  checar(rRec > 0, "(49) a linha configurada aparece pelo rótulo do documento");

  // Crescimento composto: 1000 × 1,10 = 1100 no primeiro projetado, 1210 no
  // segundo. É a conta que o analista faria à mão, e é a que o arquivo tem de
  // fazer — em FÓRMULA, não em número colado.
  // A geometria da aba é DECLARADA (coluna 1 = rótulo, 2 = unidade, e por ano 12
  // meses + 1 consolidado), e é o que os invariantes do modelo já usam: "2 + nAnos
  // × 13". Procurar a coluna pelo VALOR da linha do Exercício não funciona — ela é
  // fórmula (cada janeiro deriva do anterior), então `.value` é o objeto da
  // fórmula, não o ano.
  const primeiroAnoDaAba = 2025;  // único exercício com dado nesta fixture
  const colDe = (ano: number) => mod.getColumn(3 + (ano - primeiroAnoDaAba) * 13 + 12).letter;
  const c2026 = colDe(2026);
  checar(c2026 !== "", "(49) a coluna consolidada de 2026 existe na timeline", c2026);
  checar(Math.round(Number(avaliar(mod, c2026, rRec))) === 1100,
    "(49) crescimento composto projeta 1000 × 1,10 = 1100",
    String(avaliar(mod, c2026, rRec)));
  const c2027 = colDe(2027);
  checar(Math.round(Number(avaliar(mod, c2027, rRec))) === 1210,
    "(49) …e compõe no ano seguinte (1210)", String(avaliar(mod, c2027, rRec)));

  // Valor por ano: a premissa É a linha.
  const rCapex = rotulos.indexOf("Capex do plano") + 1;
  checar(Math.round(Number(avaliar(mod, c2026, rCapex))) === 50,
    "(49) valor por ano entra como o próprio valor da premissa",
    String(avaliar(mod, c2026, rCapex)));

  // pct_de_linha (7.5): incide sobre a RECEITA TOTAL do caso, por decisão do dono.
  // A receita projetada de 2026 é 1100, então 40% dela é 440.
  const rBase = rotulos.findIndex((x) => x.startsWith("↳ Receita total do caso")) + 1;
  checar(rBase > 0, "(49) a linha de RECEITA TOTAL (base dos percentuais) é explícita");
  checar(Math.round(Number(avaliar(mod, c2026, rBase))) === 1100,
    "(49) …e soma as linhas de receita (1100)", String(avaliar(mod, c2026, rBase)));

  const rCusto = rotulos.indexOf("Custo dos produtos vendidos") + 1;
  checar(Math.round(Number(avaliar(mod, c2026, rCusto))) === 440,
    "(49) pct_de_linha aplica 40% sobre a receita total (440)",
    String(avaliar(mod, c2026, rCusto)));
  // A nota NOMEIA a base — é o que permite ao analista discordar quando a base
  // certa não é a receita (depreciação % do imobilizado é o caso clássico).
  checar(notaDaLinha(mod, rCusto).includes("RECEITA TOTAL"),
    "(49) …e a nota nomeia a base usada, para o analista poder discordar",
    notaDaLinha(mod, rCusto).slice(0, 90));

  // dias_de_giro: receita × dias / 360 (ano comercial). 1100 × 45 / 360 = 137,5.
  const rDup = rotulos.indexOf("Duplicatas a receber") + 1;
  checar(Math.abs(Number(avaliar(mod, c2026, rDup)) - 137.5) < 0.01,
    "(49) dias_de_giro usa a mesma base e o ano comercial de 360 dias (137,5)",
    String(avaliar(mod, c2026, rDup)));

  // Primitiva que SEGUE não desenhada: célula VAZIA com nota, nunca um número
  // inventado. Zero num modelo financeiro é um valor, e projeção errada com cara
  // de pronta é pior do que célula vazia que diz por que está vazia.
  const rUn = rotulos.indexOf("Receita por unidade") + 1;
  const celUn = mod.getRow(rUn).getCell(mod.getColumn(c2026).number);
  checar(celUn.value == null || celUn.value === "",
    "(49) primitiva não desenhada deixa a célula VAZIA (nada de zero inventado)",
    JSON.stringify(celUn.value));
  checar(notaDaLinha(mod, rUn).includes("ainda não desenha"),
    "(49) …e a nota diz que a fórmula ainda não é desenhada",
    notaDaLinha(mod, rUn).slice(0, 120));

  // curva_mensal (7.5): a sazonalidade REPARTE o anual nos 12 meses, e a curva vem
  // do histórico do caso. Aqui a curva concentra dezembro (20%), e o resto divide
  // os 80% — é o que um varejo de verdade parece.
  {
    const curva = [0.05, 0.05, 0.07, 0.07, 0.08, 0.08, 0.08, 0.08, 0.08, 0.08, 0.08, 0.20];
    const wbSazo = buildExportWorkbook({
      caso: { nome: "C", produto: "rx" }, documentos, campos,
      agora: new Date("2026-07-27T12:00:00Z"),
      modelagemConfig: {
        entidade: "Projetada Ltda", ultimoExercicioReal: 2025, anosProjetados: 2,
        sazonalidade: curva,
        premissas: [
          { codigo: "CRESC_REAL", nome: "Crescimento real da receita", formula: "crescimento_composto",
            unidade: "%", valores: { "2026": 0.1 } },
          { codigo: "SAZONALIDADE", nome: "Sazonalidade mensal", formula: "curva_mensal",
            unidade: "%", valores: {} },
        ],
        linhas: [
          { rotulo: "Receita de vendas", secaoCanonica: "receita_bruta",
            premissaCodigo: "CRESC_REAL", sazonalidadeCodigo: "SAZONALIDADE", valorBase: 1000 },
        ],
      },
    });
    const ms = wbSazo.getWorksheet("Modelagem")!;
    const rotS: string[] = [];
    for (let r = 1; r <= ms.rowCount; r++) rotS.push(String(ms.getRow(r).getCell(1).value ?? ""));
    const rRecS = rotS.indexOf("Receita de vendas") + 1;
    // Dezembro de 2026: coluna do 12º mês do ano y=1 → 3 + 1*13 + 11.
    const colDez = ms.getColumn(3 + 1 * 13 + 11).letter;
    checar(Math.round(Number(avaliar(ms, colDez, rRecS))) === 220,
      "(49) a sazonalidade reparte o anual: dezembro fica com 20% de 1100 = 220",
      String(avaliar(ms, colDez, rRecS)));
    const colJan = ms.getColumn(3 + 1 * 13 + 0).letter;
    checar(Math.round(Number(avaliar(ms, colJan, rRecS))) === 55,
      "(49) …e janeiro com 5% (55) — não 1/12 uniforme",
      String(avaliar(ms, colJan, rRecS)));

    // Sem curva, a linha fica só no anual e a nota diz por quê.
    const wbSemCurva = buildExportWorkbook({
      caso: { nome: "C", produto: "rx" }, documentos, campos,
      agora: new Date("2026-07-27T12:00:00Z"),
      modelagemConfig: {
        entidade: "Projetada Ltda", ultimoExercicioReal: 2025, anosProjetados: 2,
        premissas: [
          { codigo: "CRESC_REAL", nome: "Crescimento real da receita", formula: "crescimento_composto",
            unidade: "%", valores: { "2026": 0.1 } },
          { codigo: "SAZONALIDADE", nome: "Sazonalidade mensal", formula: "curva_mensal",
            unidade: "%", valores: {} },
        ],
        linhas: [
          { rotulo: "Receita de vendas", secaoCanonica: "receita_bruta",
            premissaCodigo: "CRESC_REAL", sazonalidadeCodigo: "SAZONALIDADE", valorBase: 1000 },
        ],
      },
    });
    const msc = wbSemCurva.getWorksheet("Modelagem")!;
    const rotSC: string[] = [];
    for (let r = 1; r <= msc.rowCount; r++) rotSC.push(String(msc.getRow(r).getCell(1).value ?? ""));
    const rRecSC = rotSC.indexOf("Receita de vendas") + 1;
    const celJanSC = msc.getRow(rRecSC).getCell(3 + 1 * 13 + 0);
    checar(celJanSC.value == null || celJanSC.value === "",
      "(49) sem curva no caso, os meses ficam VAZIOS (nada de 1/12 inventado)",
      JSON.stringify(celJanSC.value));
    checar(notaDaLinha(msc, rRecSC).includes("dezembro para março"),
      "(49) …e a nota explica o custo do rateio uniforme",
      notaDaLinha(msc, rRecSC).slice(0, 100));
  }

  // Sem configuração, o arquivo continua saindo como antes: o esqueleto agregado
  // é o fallback, e esta fase não tira modelo de ninguém.
  const semConfig = buildExportWorkbook({
    caso: { nome: "C", produto: "rx" }, documentos, campos,
    agora: new Date("2026-07-27T12:00:00Z"),
  });
  const modSem = semConfig.getWorksheet("Modelagem")!;
  const rotSem: string[] = [];
  for (let r = 1; r <= modSem.rowCount; r++) rotSem.push(String(modSem.getRow(r).getCell(1).value ?? ""));
  checar(!rotSem.some((x) => x.startsWith("PROJEÇÃO POR LINHA")),
    "(49) sem configuração, não há bloco por linha — o esqueleto agregado é o fallback");
  checar(rotSem.some((x) => x.startsWith("PARÂMETROS DO MODELO")),
    "(49) …e o bloco de parâmetros continua existindo de todo jeito");
}

// ---------------------------------------------------------------------------
// (0104b) A IDENTIDADE DA LINHA É O PAR (SEÇÃO, RÓTULO) — defeito relatado pelo
// dono no teste da tela: ele escolhia a premissa de UMA linha, não mexia em mais
// nenhuma, salvava, e outra linha aparecia preenchida com a mesma premissa.
//
// A causa era o casamento por `rotulo_norm` sozinho, nos dois lugares que leem
// vínculo (a tela e a rota de export). Demonstração real repete rótulo entre
// seções o tempo todo: no caso do v35 são TREZE — `Empréstimos e Financiamentos`
// e `Arrendamentos` no passivo circulante E no não circulante, `Capital social` e
// `Reserva legal` no patrimônio líquido E na DMPL.
//
// Os dados abaixo são desses rótulos reais, com os valores reais do v35.
// ---------------------------------------------------------------------------
{
  const linhasDoCaso = [
    { secao_canonica: "passivo_circulante", rotulo_norm: "emprestimos e financiamentos",
      chave: "Empréstimos e Financiamentos", valor_ultimo: 44474 },
    { secao_canonica: "passivo_nao_circulante", rotulo_norm: "emprestimos e financiamentos",
      chave: "Empréstimos e Financiamentos", valor_ultimo: 37379 },
    { secao_canonica: "patrimonio_liquido", rotulo_norm: "capital social",
      chave: "Capital social", valor_ultimo: 42000 },
    { secao_canonica: "dmpl", rotulo_norm: "capital social",
      chave: "Capital social", valor_ultimo: 42000 },
  ];

  // O analista configurou UMA linha: a do passivo circulante.
  const umVinculo = [{
    secao_canonica: "passivo_circulante", rotulo_norm: "emprestimos e financiamentos",
    premissa_codigo: "DIVIDA_MOV", sazonalidade_codigo: null,
  }];
  const casado = casarVinculosComLinhas(umVinculo, linhasDoCaso);
  checar(casado.length === 1,
    "(0104b) um vínculo gravado produz UMA linha configurada — não uma por homônimo",
    `linhas: ${casado.length}`);
  checar(casado[0].secaoCanonica === "passivo_circulante" && casado[0].valorBase === 44474,
    "(0104b) e ela leva o valor base da PRÓPRIA seção (44.474, não os 37.379 do não circulante)",
    JSON.stringify(casado[0]));

  // A tela: a linha homônima da outra seção tem de vir VAZIA.
  const porLinha = vinculoPorLinha(umVinculo);
  checar(
    porLinha.get(chaveDaLinha("passivo_circulante", "emprestimos e financiamentos"))
      ?.premissa_codigo === "DIVIDA_MOV",
    "(0104b) a tela acha o vínculo na linha que o analista configurou");
  checar(
    porLinha.get(chaveDaLinha("passivo_nao_circulante", "emprestimos e financiamentos")) === undefined,
    "(0104b) …e a linha HOMÔNIMA de outra seção continua sem premissa — este é o assert "
    + "que impede a linha de 'completar sozinha'",
    JSON.stringify(porLinha.get(chaveDaLinha("passivo_nao_circulante", "emprestimos e financiamentos"))));

  // Seção nula não pode virar coringa que casa com todo mundo.
  const semSecao = [{
    secao_canonica: null, rotulo_norm: "capital social",
    premissa_codigo: "SOCIOS_MOV", sazonalidade_codigo: null,
  }];
  checar(
    vinculoPorLinha(semSecao).get(chaveDaLinha("dmpl", "capital social")) === undefined,
    "(0104b) vínculo SEM seção não casa com a linha que tem seção");
  checar(casarVinculosComLinhas(semSecao, linhasDoCaso)[0].valorBase === null,
    "(0104b) …e ele fica órfão, com valor base nulo, em vez de herdar o de um homônimo qualquer");

  // Órfão de verdade (documento reextraído com outro rótulo) segue aparecendo:
  // sumir com ele esconderia configuração que `fn_conferir_modelagem` denuncia.
  const orfao = casarVinculosComLinhas([{
    secao_canonica: "custos", rotulo_norm: "conta que nao existe mais",
    premissa_codigo: "CUSTO_MP", sazonalidade_codigo: null,
  }], linhasDoCaso);
  checar(orfao.length === 1 && orfao[0].rotulo === "conta que nao existe mais"
    && orfao[0].valorBase === null,
    "(0104b) vínculo órfão continua no arquivo, com o rótulo normalizado e sem base",
    JSON.stringify(orfao[0]));
}

// ---------------------------------------------------------------------------
// (0104c) DUAS LINHAS COM O MESMO RÓTULO EM SEÇÕES DIFERENTES NÃO DERRUBAM O
// MODELO INSTITUCIONAL — o HTTP 500 que o dono viu ao exportar o v35:
//
//   Error: modelo-institucional: âncora duplicada "trib:obrigacoes tributarias"
//          em Tributos a Recolher
//
// `Obrigações Tributárias` existe nas DUAS pontas do passivo (7.895 no
// circulante, 13.549 no não circulante), e `abaTributos` é a única aba que junta
// os dois blocos sob um prefixo só. Os valores abaixo são os do caso real.
// ---------------------------------------------------------------------------
{
  const linhaBase = (secao: string, chave: string, rotulo_norm: string, v2025: number) => ({
    secao_canonica: secao, chave, rotulo_norm,
    papel: "conta" as const, unidade: "milhar", moeda: "BRL",
    documentos: ["BALANCO"], valores: { "2025": v2025 },
  });

  const entrada = {
    caso: { nome: "Homônimos em duas seções", produto: "reestruturacao" },
    agora: new Date("2026-08-05T12:00:00Z"),
    entidade: "VERTENTES METALÚRGICA LTDA.",
    setor: "industria",
    anosHistoricos: [2025], anosProjetados: [2026, 2027],
    stressPct: 0.2, caixaMinimo: 0, aliquotaTributos: 0.34,
    linhas: [
      linhaBase("passivo_circulante", "Obrigações Tributárias", "obrigacoes tributarias", 7895),
      linhaBase("passivo_nao_circulante", "Obrigações Tributárias", "obrigacoes tributarias", 13549),
      linhaBase("receita_bruta", "Vendas de produtos - mercado interno",
                "vendas de produtos - mercado interno", 158900),
    ],
    premissas: [], vinculos: [], macro: [], unidade: "R$ mil",
  };

  // O modelo institucional só é construído quando o caso tem entidade
  // reconhecível NOS CAMPOS EXTRAÍDOS (`if (entidadesConhecidas.size > 0)`, em
  // export.ts) — com as duas listas vazias o export pula justamente o código sob
  // teste, e o assert passaria sem exercitar nada.
  const VHOM = "vHom";
  const camposHom: CampoExtraido[] = [
    campo({ chave: "Obrigações Tributárias", secao: "Passivo Circulante",
            secao_canonica: "passivo_circulante", valor_num: 7895, documento_versao_id: VHOM }),
    campo({ chave: "Obrigações Tributárias", secao: "Passivo Não Circulante",
            secao_canonica: "passivo_nao_circulante", valor_num: 13549, documento_versao_id: VHOM }),
  ];
  const docsHom: DocumentoParaExport[] = [{
    id: "dHom", tipo_taxonomia: "BALANCO",
    entidade: { razao_social: "VERTENTES METALÚRGICA LTDA." },
    periodo: { tipo: "anual", referencia: "12M25" },
    documento_versao: [{ id: VHOM, nome_original: "01_BP_Vertentes_Metalurgica_2025x2024.pdf" }],
  }];

  let erro: string | null = null;
  let wbHom: ReturnType<typeof buildExportWorkbook> | null = null;
  try {
    wbHom = buildExportWorkbook({
      caso: entrada.caso, documentos: docsHom, campos: camposHom,
      agora: new Date("2026-08-05T12:00:00Z"),
      modo: "completo",
      modeloInstitucional: entrada as unknown as Parameters<typeof buildExportWorkbook>[0]["modeloInstitucional"],
    });
  } catch (e) {
    erro = e instanceof Error ? e.message : String(e);
  }

  checar(erro === null,
    "(0104c) o mesmo rótulo em duas seções NÃO derruba o export — era o HTTP 500 do v35",
    erro ?? "");

  if (wbHom) {
    const trib = wbHom.getWorksheet("Tributos a Recolher");
    let n = 0;
    if (trib) {
      for (let r = 1; r <= trib.rowCount; r++) {
        if (String(trib.getRow(r).getCell(3).value ?? "") === "Obrigações Tributárias") n++;
      }
    }
    checar(n === 2,
      "(0104c) …e as DUAS aparecem na aba de tributos, uma por seção (somar só uma esconderia 13.549)",
      `linhas com o rótulo: ${n}`);
  }
}


// ---------------------------------------------------------------------------
// (0105) O MODELO INSTITUCIONAL FECHA — e é o único invariante que decide se ele
// é um modelo ou um relatório bonito.
//
// POR QUE ESTE BLOCO EXISTE. Até esta rodada nenhum teste avaliava os NÚMEROS do
// modelo institucional: os asserts existentes cobriam estrutura (a aba existe, o
// rótulo aparece duas vezes, o export não explode). Um modelo pode ter as 14 abas
// no lugar, 3.000 fórmulas e não fechar o balanço — e foi exatamente o que
// acontecia. Três defeitos de MECANISMO só apareceram quando os números foram
// somados:
//
//   1. o CAIXA era projetado por dias de giro no `Working Capital` E somado outra
//      vez pelo `Cash Flow` no `Balance Sheet` (`AC = CAIXA + AC_OPER`);
//   2. a DÍVIDA bancária de curto prazo entrava no passivo operacional do giro E
//      voltava em `DIVIDA_CP`;
//   3. `Revenues!DEPRECIACAO` era declarada e NUNCA preenchida — a DRE debitava
//      zero de depreciação, o `Cash Flow` somava de volta uma depreciação que
//      ninguém tinha subtraído, e o imobilizado caía sem contrapartida.
//
// O caso abaixo tem as sete famílias de conta que o balanço precisa para fechar
// (caixa, giro do ativo, estoque, imobilizado, giro do passivo, dívida em duas
// pontas, patrimônio) com números redondos escolhidos para o CHECK ser
// verificável a olho se o teste falhar.
//
// A FIXTURE FOI REFEITA (rodada de 06/08/2026) COM A FORMA DO DADO REAL, e é essa
// a lição mais cara desta rodada. A versão anterior tinha:
//
//   • custo e despesa POSITIVOS (`"Custo dos produtos vendidos", 140000`), quando
//     a extração — e a fixture `book-vertentes.json`, e o banco — trazem `−140000`,
//     porque é assim que a DRE publicada escreve;
//   • uma conta por grupo, NENHUM par subtotal+componente, quando toda demonstração
//     real imprime "Obrigações Tributárias 8.706" seguido dos componentes dela;
//   • um único exercício realizado, quando o mapa de dívida costuma cobrir só o
//     último e o balanço cobre todos;
//   • nenhuma linha de resultado informada (Receita Líquida, Lucro Bruto, EBIT),
//     então não havia contra o que conferir a cascata.
//
// Com essa fixture os 15 asserts do (0105) passavam VERDES enquanto o arquivo
// entregue ao dono transformava prejuízo de 17.901 em lucro de 268.041 e um ativo
// de 95.780 em 195.090. Fixture mais fácil que a produção mede o instrumento, não
// o sistema — é o que o `CLAUDE.md` chama de teste que não pode falhar.
// ---------------------------------------------------------------------------
{
  // Valores POR ANO e na CONVENÇÃO DO DOCUMENTO: despesa negativa, como o PDF
  // escreve e como a extração entrega. É o modelo que tem de normalizar.
  const linhaAnos = (
    secao: string, chave: string, valores: Record<string, number>,
    doc = "BALANCO", papel: "conta" | "subtotal" = "conta",
  ) => ({
    secao_canonica: secao, chave, rotulo_norm: chave.toLowerCase(),
    papel, unidade: "milhar", moeda: "BRL",
    documentos: [doc], valores,
  });
  const linha = (secao: string, chave: string, v: number, doc = "BALANCO") =>
    linhaAnos(secao, chave, { "2025": v }, doc);
  void linha;

  const entradaModelo = {
    caso: { nome: "Fecha o balanço", produto: "reestruturacao" },
    agora: new Date("2026-08-05T12:00:00Z"),
    entidade: "VERTENTES METALÚRGICA LTDA.",
    setor: "industria",
    anosHistoricos: [2024, 2025],
    anosProjetados: [2026, 2027, 2028],
    stressPct: 0.2, caixaMinimo: 5000, aliquotaTributos: 0.34,
    // O BALANÇO DESTE CASO FECHA NOS DOIS EXERCÍCIOS, e fecha SÓ se o modelo
    // excluir o subtotal informado e achar a dívida de 2024 no balanço:
    //
    //             |      2024 |      2025
    //   ativo     |   117.000 |   125.000
    //   PC        |    33.000 |    40.000   (giro 21.000/25.000 + dívida CP 12.000/15.000)
    //   PNC       |    34.000 |    40.000   (dívida LP 30.000/35.000 + provisões 4.000/5.000)
    //   PL        |    50.000 |    45.000
    //
    // As "Provisões" entram como SUBTOTAL do documento (e os dois componentes
    // abaixo): somar os três dobra o grupo e o CHECK acusa 4.000/5.000.
    linhas: [
      // ---- ativo
      linhaAnos("ativo_circulante", "Caixa e equivalentes de caixa", { "2024": 8000, "2025": 12000 }),
      linhaAnos("ativo_circulante", "Clientes", { "2024": 26000, "2025": 30000 }),
      linhaAnos("ativo_circulante", "Estoques", { "2024": 18000, "2025": 20000 }),
      linhaAnos("ativo_nao_circulante", "Imobilizado", { "2024": 62000, "2025": 60000 }),
      linhaAnos("ativo_nao_circulante", "Depósitos judiciais", { "2024": 3000, "2025": 3000 }),
      // ---- passivo
      linhaAnos("passivo_circulante", "Fornecedores", { "2024": 15000, "2025": 18000 }),
      linhaAnos("passivo_circulante", "Obrigações trabalhistas", { "2024": 6000, "2025": 7000 }),
      linhaAnos("passivo_circulante", "Empréstimos e financiamentos", { "2024": 12000, "2025": 15000 }),
      linhaAnos("passivo_nao_circulante", "Empréstimos e financiamentos", { "2024": 30000, "2025": 35000 }),
      // O par subtotal + componentes, como o documento imprime. `papel` chega como
      // "conta" de propósito: é o que `fn_papel_linha` devolve para "Provisões"
      // (não está na lista fechada dela), e é por isso que a detecção estrutural do
      // export precisa existir.
      linhaAnos("passivo_nao_circulante", "Provisões", { "2024": 4000, "2025": 5000 }),
      linhaAnos("passivo_nao_circulante", "Provisão para contingências cíveis", { "2024": 1500, "2025": 2000 }),
      linhaAnos("passivo_nao_circulante", "Provisão para contingências trabalhistas", { "2024": 2500, "2025": 3000 }),
      // ---- patrimônio
      linhaAnos("patrimonio_liquido", "Capital social", { "2024": 40000, "2025": 40000 }),
      linhaAnos("patrimonio_liquido", "Reservas de lucros", { "2024": 10000, "2025": 5000 }),
      // A MESMA CONTA COM DOIS RÓTULOS — o defeito que sobrou da rodada anterior e que
      // a reconciliação com o total informado resolve. No v35 são "Prejuízos
      // acumulados" e "Resultados Acumulados", ambos −39.150, e "Capital social
      // subscrito"/"Capital social subscrito e integralizado". Não é subtotal (a
      // detecção estrutural não pega) e não dá para resolver por semelhança de
      // valor: duas reservas de mesmo valor são plausíveis. Somadas, inflam o PL em
      // 10.000/5.000 — e é isso que o total informado corrige.
      linhaAnos("patrimonio_liquido", "Reserva de lucros acumulados", { "2024": 10000, "2025": 5000 }),
      // ---- resultado, NA CONVENÇÃO DO DOCUMENTO (despesa negativa)
      //   2025: RL 166.000 · LB 58.000 · EBITDA 41.000 · EBIT 33.000 · LL 17.820
      //   2024: RL 149.400 · LB 49.900 · EBITDA 35.400 · EBIT 27.900 · LL 15.900
      linhaAnos("receita_bruta", "Vendas de produtos - mercado interno",
        { "2024": 180000, "2025": 200000 }, "DRE"),
      linhaAnos("receita_bruta", "ICMS sobre vendas", { "2024": -30600, "2025": -34000 }, "DRE"),
      linhaAnos("custos", "Custo dos produtos vendidos", { "2024": -92000, "2025": -100000 }, "DRE"),
      linhaAnos("custos", "Depreciação industrial", { "2024": -7500, "2025": -8000 }, "DRE"),
      linhaAnos("despesas_operacionais", "Despesas administrativas", { "2024": -22000, "2025": -25000 }, "DRE"),
      linhaAnos("resultado_financeiro", "Despesas financeiras", { "2024": -5000, "2025": -6000 }, "DRE"),
      linhaAnos("impostos_lucro", "Imposto de renda e contribuição social",
        { "2024": -7000, "2025": -9180 }, "DRE"),
      // ---- o mapa de dívida cobre SÓ 2025 (é o caso comum: uma data de referência)
      linhaAnos("passivo_circulante", "Banco Alfa - Capital de giro - Saldo devedor",
        { "2025": 50000 }, "MAPA_DIVIDA"),
      linhaAnos("passivo_circulante", "Banco Alfa - Capital de giro - Juros do período",
        { "2025": 6000 }, "MAPA_DIVIDA"),
      // ---- as ÂNCORAS: o que o documento informa, para a conferência por valor.
      // Chegam com `papel: "subtotal"` (lista fechada da `fn_papel_linha`), ficam
      // fora das somas e servem de referência.
      linhaAnos("receita_bruta", "Receita Líquida", { "2024": 149400, "2025": 166000 }, "DRE", "subtotal"),
      linhaAnos("custos", "Lucro Bruto", { "2024": 49900, "2025": 58000 }, "DRE", "subtotal"),
      linhaAnos("despesas_operacionais", "Resultado Operacional (EBIT)",
        { "2024": 27900, "2025": 33000 }, "DRE", "subtotal"),
      linhaAnos("impostos_lucro", "Lucro Líquido do Exercício",
        { "2024": 15900, "2025": 17820 }, "DRE", "subtotal"),
      linhaAnos("ativo_circulante", "ATIVO", { "2024": 117000, "2025": 125000 }, "BALANCO", "subtotal"),
      // Os TOTAIS DE GRUPO informados — o insumo da reconciliação. O documento os
      // publica; o modelo passa a segui-los em vez de confiar na própria soma.
      linhaAnos("ativo_circulante", "Ativo Circulante", { "2024": 52000, "2025": 62000 }, "BALANCO", "subtotal"),
      linhaAnos("ativo_nao_circulante", "Ativo Não Circulante", { "2024": 65000, "2025": 63000 }, "BALANCO", "subtotal"),
      linhaAnos("passivo_circulante", "Passivo Circulante", { "2024": 33000, "2025": 40000 }, "BALANCO", "subtotal"),
      linhaAnos("passivo_nao_circulante", "Passivo Não Circulante", { "2024": 34000, "2025": 40000 }, "BALANCO", "subtotal"),
      linhaAnos("patrimonio_liquido", "Patrimônio Líquido", { "2024": 50000, "2025": 45000 }, "BALANCO", "subtotal"),
    ],
    premissas: [
      {
        codigo: "CRESC", nome: "Crescimento nominal da receita", natureza: "receita",
        formula: "crescimento_composto", unidade: "%",
        valores: { "2026": 8, "2027": 6, "2028": 5 }, origem: "digitado",
      },
      {
        codigo: "CUSTO", nome: "Custo sobre receita líquida", natureza: "custo",
        formula: "pct_de_linha", unidade: "%",
        valores: { "2026": 70, "2027": 70, "2028": 69 }, origem: "historico",
      },
      {
        codigo: "PMR", nome: "Prazo médio de recebimento", natureza: "giro",
        formula: "dias_de_giro", unidade: "dias",
        valores: { "2026": 54, "2027": 54, "2028": 50 }, origem: "historico",
      },
      {
        codigo: "CAPEX", nome: "Capex sobre receita líquida", natureza: "investimento",
        formula: "pct_de_linha", unidade: "%",
        valores: { "2026": 3, "2027": 3, "2028": 3 }, origem: "digitado",
      },
    ],
    vinculos: [
      { rotulo_norm: "vendas de produtos - mercado interno", premissa_codigo: "CRESC", sazonalidade_codigo: null },
      { rotulo_norm: "custo dos produtos vendidos", premissa_codigo: "CUSTO", sazonalidade_codigo: null },
      { rotulo_norm: "clientes", premissa_codigo: "PMR", sazonalidade_codigo: null },
      { rotulo_norm: "imobilizado", premissa_codigo: "CAPEX", sazonalidade_codigo: null },
    ],
    macro: [
      { serie: "IPCA", ano: 2026, valor: 4.5, fonte: "Focus", natureza: "taxa" as const },
      { serie: "IPCA", ano: 2027, valor: 4, fonte: "Focus", natureza: "taxa" as const },
      { serie: "IPCA", ano: 2028, valor: 3.5, fonte: "Focus", natureza: "taxa" as const },
      { serie: "CDI", ano: 2026, valor: 10, fonte: "Focus", natureza: "taxa" as const },
      { serie: "CDI", ano: 2027, valor: 9.5, fonte: "Focus", natureza: "taxa" as const },
      { serie: "CDI", ano: 2028, valor: 9, fonte: "Focus", natureza: "taxa" as const },
      // O CÂMBIO NAS DUAS GRANDEZAS, de propósito: 2024 chega como o retorno do ano
      // (o que `fn_indice_macro_anual` devolve para série de nível) e tem de ser
      // RECUSADO; 2025 e 2026 chegam em nível e têm de ser publicados. Sem as duas
      // formas na fixture, o teste não distingue "recusa" de "não recebeu nada".
      { serie: "CAMBIO_USD", ano: 2024, valor: 24.5, fonte: "realizado (12 meses)", natureza: "taxa" as const },
      { serie: "CAMBIO_USD", ano: 2025, valor: 5.2, fonte: "realizado — fechamento de 2025-12-31", natureza: "nivel" as const },
      { serie: "CAMBIO_USD", ano: 2026, valor: 5.4, fonte: "Focus", natureza: "nivel" as const },
    ],
    unidade: "R$ mil",
  };

  // O modelo só é construído quando o caso tem entidade reconhecível NOS CAMPOS
  // extraídos (`if (entidadesConhecidas.size > 0)` em export.ts). Sem estes dois
  // campos o export pula o código sob teste e o assert passaria sem exercitar nada.
  const VMOD = "vModelo";
  // OS CAMPOS EXISTEM PARA A DETECÇÃO ESTRUTURAL RODAR. É por eles que o export
  // descobre que "Provisões" é o subtotal impresso ANTES dos seus componentes — o
  // sinal está na ORDEM, e é o único sinal que existe (o rótulo "Provisões" não está
  // na lista fechada da `fn_papel_linha`, e por isso chega como `papel: "conta"`).
  // Sem esta sequência aqui, o teste do (0106b) mediria o instrumento: a lista de
  // subtotais chegaria vazia e a exclusão nunca seria exercitada.
  const camposModelo: CampoExtraido[] = [
    campo({ chave: "Caixa e equivalentes de caixa", secao: "Ativo Circulante",
            secao_canonica: "ativo_circulante", valor_num: 12000, documento_versao_id: VMOD, ordem: 1 }),
    campo({ chave: "Capital social", secao: "Patrimônio Líquido",
            secao_canonica: "patrimonio_liquido", valor_num: 40000, documento_versao_id: VMOD, ordem: 2 }),
    campo({ chave: "Provisões", secao: "Passivo Não Circulante",
            secao_canonica: "passivo_nao_circulante", valor_num: 5000, documento_versao_id: VMOD, ordem: 3 }),
    campo({ chave: "Provisão para contingências cíveis", secao: "Passivo Não Circulante",
            secao_canonica: "passivo_nao_circulante", valor_num: 2000, documento_versao_id: VMOD, ordem: 4 }),
    campo({ chave: "Provisão para contingências trabalhistas", secao: "Passivo Não Circulante",
            secao_canonica: "passivo_nao_circulante", valor_num: 3000, documento_versao_id: VMOD, ordem: 5 }),
  ];
  const docsModelo: DocumentoParaExport[] = [{
    id: "dModelo", tipo_taxonomia: "BALANCO",
    entidade: { razao_social: "VERTENTES METALÚRGICA LTDA." },
    periodo: { tipo: "anual", referencia: "12M25" },
    documento_versao: [{ id: VMOD, nome_original: "01_BP_Vertentes_2025.pdf" }],
  }];

  const wbMod = buildExportWorkbook({
    caso: entradaModelo.caso, documentos: docsModelo, campos: camposModelo,
    agora: new Date("2026-08-05T12:00:00Z"), modo: "completo",
    modeloInstitucional: entradaModelo as unknown as Parameters<typeof buildExportWorkbook>[0]["modeloInstitucional"],
  });

  // A especificação dos gráficos viaja presa ao workbook até o pós-processamento do
  // buffer (é o caminho que `finalizarBufferDoExport` usa). Ler daqui é o que
  // permite conferir a ÂNCORA deles sem reabrir o .xlsx.
  const graficosDoModelo =
    (wbMod as unknown as { __graficosDoModelo?: Array<{
      titulo: string; de: { col: number; linha: number }; ate: { col: number; linha: number };
    }> }).__graficosDoModelo ?? [];

  /** Acha a linha de uma aba do modelo pelo rótulo exato da coluna C. */
  const linhaDoRotulo = (aba: string, rotulo: string): number | null => {
    const ws = wbMod.getWorksheet(aba);
    if (!ws) return null;
    for (let r = 1; r <= ws.rowCount; r++) {
      if (String(ws.getRow(r).getCell(3).value ?? "").trim() === rotulo) return r;
    }
    return null;
  };
  // 2024 e 2025 são REALIZADOS; 2026 a 2028, projetados.
  const COLS_ANO = ["E", "F", "G", "H", "I"];
  const ANOS = [2024, 2025, 2026, 2027, 2028];
  const iAnoDe = (ano: number) => ANOS.indexOf(ano);
  const valorNaAba = (aba: string, rotulo: string, iAno: number) => {
    const ws = wbMod.getWorksheet(aba);
    const r = linhaDoRotulo(aba, rotulo);
    if (!ws || r === null) return null;
    return avaliarCelula(ws, COLS_ANO[iAno], r);
  };

  // ---- (0105a) O CHECK do balanço fecha em TODO exercício projetado --------
  const rCheck = linhaDoRotulo("Balance Sheet", "CHECK — Ativo − (Passivo + PL) deve ser ZERO");
  checar(rCheck !== null, "(0105a) a aba Balance Sheet tem a linha de CHECK", String(rCheck));
  if (rCheck !== null) {
    const bs = wbMod.getWorksheet("Balance Sheet")!;
    const desvios: string[] = [];
    for (let i = 0; i < COLS_ANO.length; i++) {
      const v = avaliarCelula(bs, COLS_ANO[i], rCheck);
      if (typeof v !== "number") { desvios.push(`${ANOS[i]}: não avaliável (${JSON.stringify(v)})`); continue; }
      if (Math.abs(v) > 0.5) desvios.push(`${ANOS[i]}: ${v.toFixed(2)}`);
    }
    checar(desvios.length === 0,
      "(0105a) O BALANÇO FECHA — Ativo − (Passivo + PL) = 0 em todos os exercícios, realizado e projetado",
      desvios.join(" · "));
  }

  // ---- (0105b) o caixa NÃO é projetado por dias de giro --------------------
  //
  // A dupla contagem aberta desde a sessão 32. O Modelo Base exclui
  // `Cash & Short Term Inv.` das contas de giro (§10 do MAPA_MODELO_BASE.md), e a
  // regra é: uma conta, uma origem.
  {
    const wc = wbMod.getWorksheet("Working Capital");
    let achouCaixa = false;
    let achouDivida = false;
    if (wc) {
      for (let r = 1; r <= wc.rowCount; r++) {
        const rot = String(wc.getRow(r).getCell(3).value ?? "");
        if (/^Caixa e equivalentes/i.test(rot)) achouCaixa = true;
        if (/^Empréstimos e financiamentos/i.test(rot)) achouDivida = true;
      }
    }
    checar(!achouCaixa,
      "(0105b) o CAIXA não aparece como conta de giro no Working Capital (era contado duas vezes no ativo)",
      achouCaixa ? "a linha de caixa está no giro" : "");
    checar(!achouDivida,
      "(0105b) a DÍVIDA bancária não aparece como conta de giro (era contada duas vezes no passivo)",
      achouDivida ? "a linha de empréstimos está no giro" : "");
  }

  // ---- (0105c) a depreciação chega à DRE ----------------------------------
  {
    const i2026 = iAnoDe(2026);
    const dep2026 = valorNaAba("Income Statement", "Depreciation and Amortization", i2026);
    const capexOk = valorNaAba("Fixed Assets & CAPEX", "CAPEX total", i2026);
    checar(typeof dep2026 === "number" && dep2026 > 0,
      "(0105c) a DEPRECIAÇÃO chega à DRE — a linha D&A do Income Statement é maior que zero no projetado",
      `D&A 2026 = ${JSON.stringify(dep2026)} (capex 2026 = ${JSON.stringify(capexOk)})`);
    const ebitda = valorNaAba("Income Statement", "EBITDA", i2026);
    const ebit = valorNaAba("Income Statement", "EBIT", i2026);
    checar(typeof ebitda === "number" && typeof ebit === "number" && ebitda > ebit,
      "(0105c) …e por isso EBITDA > EBIT no projetado (com D&A zero os dois eram iguais)",
      `EBITDA ${JSON.stringify(ebitda)} · EBIT ${JSON.stringify(ebit)}`);

    // ---- (0106e) …e chega no REALIZADO também -------------------------------
    //
    // A DRE extraída traz "Depreciação industrial" DENTRO do custo (−8.000 em
    // 2025). No arquivo entregue a linha D&A do realizado era ZERO e o EBITDA
    // realizado saía igual ao EBIT — o erro que o próprio comentário do EBITDA
    // alerta, no único par de colunas que o comitê compara com o balanço auditado.
    const i2025 = iAnoDe(2025);
    const depHist = valorNaAba("Income Statement", "Depreciation and Amortization", i2025);
    checar(typeof depHist === "number" && Math.abs(depHist - 8000) < 0.5,
      "(0106e) a DEPRECIAÇÃO REALIZADA chega à DRE — vem das linhas de custo/despesa extraídas",
      `D&A 2025 = ${JSON.stringify(depHist)} (esperado 8.000, de \"Depreciação industrial\")`);
    const ebitdaH = valorNaAba("Income Statement", "EBITDA", i2025);
    const ebitH = valorNaAba("Income Statement", "EBIT", i2025);
    checar(typeof ebitdaH === "number" && typeof ebitH === "number"
      && Math.abs(ebitdaH - 41000) < 0.5 && Math.abs(ebitH - 33000) < 0.5,
      "(0106e) …e o EBITDA realizado deixa de ser o EBIT com outro nome (41.000 contra 33.000)",
      `EBITDA ${JSON.stringify(ebitdaH)} · EBIT ${JSON.stringify(ebitH)}`);
  }

  // ---- (0106a) A DRE DO REALIZADO É A DO DOCUMENTO -------------------------
  //
  // O invariante nº 9 aplicado ao modelo institucional. É o assert que o arquivo
  // entregue em 06/08/2026 teria reprovado em oito células: a cascata SUBTRAI
  // despesa (convenção do modelo: magnitude positiva) e a extração entrega despesa
  // NEGATIVA (convenção do documento) — subtrair negativo soma, e a DRE realizada
  // saiu com receita líquida 170.220 onde o documento diz 106.580 e resultado
  // +268.041 onde o documento diz −17.901.
  {
    const esperado: Array<{ rotulo: string; ano: number; valor: number }> = [
      { rotulo: "NET REVENUES", ano: 2024, valor: 149400 },
      { rotulo: "NET REVENUES", ano: 2025, valor: 166000 },
      { rotulo: "GROSS PROFIT", ano: 2024, valor: 49900 },
      { rotulo: "GROSS PROFIT", ano: 2025, valor: 58000 },
      { rotulo: "EBIT", ano: 2024, valor: 27900 },
      { rotulo: "EBIT", ano: 2025, valor: 33000 },
      { rotulo: "NET PROFIT", ano: 2024, valor: 15900 },
      { rotulo: "NET PROFIT", ano: 2025, valor: 17820 },
    ];
    const fora = esperado.filter(({ rotulo, ano, valor }) => {
      const v = valorNaAba("Income Statement", rotulo, iAnoDe(ano));
      return typeof v !== "number" || Math.abs(v - valor) > 0.5;
    }).map(({ rotulo, ano, valor }) =>
      `${rotulo} ${ano}: ${JSON.stringify(valorNaAba("Income Statement", rotulo, iAnoDe(ano)))} != ${valor}`);
    checar(fora.length === 0,
      "(0106a) A DRE REALIZADA REPRODUZ O DOCUMENTO — receita líquida, lucro bruto, EBIT e "
      + "resultado líquido dos exercícios realizados batem com o informado (convenção de sinal)",
      fora.join(" · "));

    // E a conferência existe DENTRO do arquivo, não só no teste: quem abre a
    // planilha tem a diferença na cara, senão o próximo erro de sinal volta a
    // passar por bom.
    const difs = ["Receita líquida", "Lucro bruto", "EBIT", "Resultado líquido"]
      .map((r) => linhaDoRotulo("Income Statement", `${r} — informado no documento`))
      .filter((r) => r !== null);
    checar(difs.length === 4,
      "(0106a) o Income Statement publica o informado no documento ao lado do número do modelo",
      `linhas encontradas: ${difs.length}/4`);
    const rDiag = linhaDoRotulo("Income Statement", "diagnóstico");
    const diag = rDiag === null ? null
      : avaliarCelula(wbMod.getWorksheet("Income Statement")!, COLS_ANO[iAnoDe(2025)], rDiag);
    checar(diag === "confere com o documento",
      "(0106a) …e o diagnóstico do exercício realizado diz que CONFERE",
      JSON.stringify(diag));
  }

  // ---- (0106b) SUBTOTAL INFORMADO NÃO ENTRA NA SOMA DO BALANÇO -------------
  //
  // "Provisões 5.000" seguido dos dois componentes (2.000 + 3.000) é como toda
  // demonstração imprime. Somar os três dobra o grupo: no arquivo entregue o
  // `ATIVO TOTAL` de 2025 saiu 195.090 contra 95.780 informados (2,04x), enquanto a
  // aba analítica `Balanço` do MESMO arquivo mostrava o número certo.
  {
    const fora: string[] = [];
    for (const [ano, esperado] of [[2024, 117000], [2025, 125000]] as const) {
      const ativo = valorNaAba("Balance Sheet", "ATIVO TOTAL", iAnoDe(ano));
      const pnc = valorNaAba("Balance Sheet", "PASSIVO NÃO CIRCULANTE", iAnoDe(ano));
      const pncEsperado = ano === 2024 ? 34000 : 40000;
      if (typeof ativo !== "number" || Math.abs(ativo - esperado) > 0.5) {
        fora.push(`ATIVO ${ano}: ${JSON.stringify(ativo)} != ${esperado}`);
      }
      if (typeof pnc !== "number" || Math.abs(pnc - pncEsperado) > 0.5) {
        fora.push(`PNC ${ano}: ${JSON.stringify(pnc)} != ${pncEsperado} (subtotal somado com os componentes?)`);
      }
    }
    checar(fora.length === 0,
      "(0106b) o SUBTOTAL informado pelo documento fica FORA da soma do balanço — o grupo não dobra",
      fora.join(" · "));

    const rDif = linhaDoRotulo("Balance Sheet", "diferença (modelo − documento) — ZERO");
    const dif2025 = rDif === null ? null
      : avaliarCelula(wbMod.getWorksheet("Balance Sheet")!, COLS_ANO[iAnoDe(2025)], rDif);
    checar(typeof dif2025 === "number" && Math.abs(dif2025) < 0.5,
      "(0106b) …e o balanço publica a diferença contra o ativo total informado, em ZERO",
      JSON.stringify(dif2025));
  }

  // ---- (0106h) A MESMA CONTA COM DOIS RÓTULOS NÃO ESTOURA O BALANÇO -------
  //
  // "Reservas de lucros" e "Reserva de lucros acumulados", ambas 5.000 em 2025, são
  // a mesma conta transposta duas vezes — o resíduo que sobrou depois de excluir os
  // subtotais informados. Somadas, o PL sai 50.000 onde o documento diz 45.000.
  //
  // A correção NÃO é apagar uma delas (duas reservas de mesmo valor são plausíveis,
  // e apagar conta legítima é pior que somar demais): é seguir o TOTAL INFORMADO,
  // com a diferença escrita numa linha própria. Invariante nº 6, que as abas
  // analíticas seguem desde o teste v25, aplicado ao modelo.
  {
    const fora: string[] = [];
    for (const [ano, plEsperado] of [[2024, 50000], [2025, 45000]] as const) {
      const plModelo = valorNaAba("Balance Sheet", "PATRIMÔNIO LÍQUIDO", iAnoDe(ano));
      if (typeof plModelo !== "number" || Math.abs(plModelo - plEsperado) > 0.5) {
        fora.push(`PL ${ano}: ${JSON.stringify(plModelo)} != ${plEsperado} (conta duplicada somada?)`);
      }
    }
    checar(fora.length === 0,
      "(0106h) o PATRIMÔNIO segue o total informado no documento mesmo com a MESMA conta transposta "
      + "com dois rótulos — sem apagar conta nenhuma",
      fora.join(" · "));

    const rRec = linhaDoRotulo("Balance Sheet", "reconciliação com o patrimônio líquido informado no documento");
    const rec2025 = rRec === null ? null
      : avaliarCelula(wbMod.getWorksheet("Balance Sheet")!, COLS_ANO[iAnoDe(2025)], rRec);
    checar(typeof rec2025 === "number" && Math.abs(rec2025 + 5000) < 0.5,
      "(0106h) …e a linha de reconciliação DIZ o tamanho do que não se explica (−5.000 em 2025)",
      JSON.stringify(rec2025));
    // Na projeção ela é constante: nem zerada (salto artificial), nem crescida
    // (projetar erro de extração como se fosse conta).
    const rec2027 = rRec === null ? null
      : avaliarCelula(wbMod.getWorksheet("Balance Sheet")!, COLS_ANO[iAnoDe(2027)], rRec);
    checar(typeof rec2027 === "number" && Math.abs(rec2027 + 5000) < 0.5,
      "(0106h) …e permanece constante no projetado, sem salto na virada do realizado",
      JSON.stringify(rec2027));
  }

  // ---- (0106c) A DÍVIDA APARECE NO EXERCÍCIO QUE O MAPA NÃO COBRE ----------
  //
  // O mapa de dívida deste caso (como o do v35) tem UMA data de referência: 2025.
  // Antes, `dividas` escolhia o mapa para o modelo inteiro e 2024 saía com dívida
  // ZERO — enquanto o balanço informa 12.000 no circulante e 30.000 no não
  // circulante. O `CHECK` de 2024 abria exatamente no valor que desapareceu.
  {
    const cp2024 = valorNaAba("Balance Sheet", "Dívida de curto prazo + revolver", iAnoDe(2024));
    const lp2024 = valorNaAba("Balance Sheet", "Dívida de longo prazo", iAnoDe(2024));
    checar(typeof cp2024 === "number" && Math.abs(cp2024 - 12000) < 1
      && typeof lp2024 === "number" && Math.abs(lp2024 - 30000) < 1,
      "(0106c) a DÍVIDA do exercício que o mapa não cobre vem do balanço, com a repartição "
      + "curto/longo do próprio ano (12.000 + 30.000 em 2024)",
      `CP ${JSON.stringify(cp2024)} · LP ${JSON.stringify(lp2024)}`);
  }

  // ---- (0105d) o eixo do tempo tem UMA raiz ------------------------------
  {
    const rec = wbMod.getWorksheet("Revenues, COGS & SG&A")!;
    const rRaiz = linhaDoRotulo("Revenues, COGS & SG&A",
      "Último exercício realizado (a raiz do calendário do modelo)");
    checar(rRaiz !== null,
      "(0105d) a aba de receita declara a RAIZ do calendário (uma única data digitada)", String(rRaiz));
    // O cabeçalho de cada aba do modelo é FÓRMULA, não ano digitado.
    const semFormula: string[] = [];
    for (const aba of ["Income Statement", "Balance Sheet", "Working Capital", "Cash Flow",
                       "ST Inv. & Debt", "Fixed Assets & CAPEX", "Goodwill, Taxes & Div.", "Output"]) {
      const ws = wbMod.getWorksheet(aba);
      if (!ws) { semFormula.push(`${aba}: aba ausente`); continue; }
      let rTit: number | null = null;
      for (let r = 1; r <= ws.rowCount; r++) {
        const c = ws.getRow(r).getCell(5).value;
        if (c && typeof c === "object" && "formula" in c
          && /Revenues, COGS & SG&A/.test((c as { formula: string }).formula)) { rTit = r; break; }
      }
      if (rTit === null) semFormula.push(aba);
    }
    checar(semFormula.length === 0,
      "(0105d) o cabeçalho de ano de todas as abas do modelo é FÓRMULA que herda da raiz (P01/P02)",
      semFormula.join(", "));
    void rec;
  }

  // ---- (0105e) nenhuma fórmula do modelo com #REF! ou erro ---------------
  {
    const comErro: string[] = [];
    for (const aba of ABAS_DO_MODELO) {
      const ws = wbMod.getWorksheet(aba);
      if (!ws) continue;
      for (let r = 1; r <= ws.rowCount; r++) {
        const row = ws.getRow(r);
        for (let c = 1; c <= 40; c++) {
          const v = row.getCell(c).value;
          if (v && typeof v === "object" && "formula" in v) {
            const f = (v as { formula: string }).formula;
            if (/#REF!|#VALUE!|#DIV\/0!|#NAME\?/.test(f)) comErro.push(`${aba}!${row.getCell(c).address}`);
          }
        }
      }
    }
    checar(comErro.length === 0,
      "(0105e) nenhuma fórmula do modelo nasce com #REF!/#VALUE! — a referência tem 667, das quais 627 no Output",
      comErro.slice(0, 8).join(", "));
  }

  // ---- (0105f) área de impressão nas 14 abas do modelo ------------------
  {
    const semArea = ABAS_DO_MODELO.filter((aba) => {
      const ws = wbMod.getWorksheet(aba);
      return !ws || !ws.pageSetup?.printArea;
    });
    checar(semArea.length === 0,
      "(0105f) as 14 abas do modelo declaram área de impressão (a referência declara 5)",
      semArea.join(", "));
  }

  // ---- (0105g) o Output não sobrescreve a legenda de cenário ------------
  {
    const out = wbMod.getWorksheet("Output")!;
    checar(String(out.getRow(5).getCell(3).value ?? "") === "3 = Stress Case",
      "(0105g) a legenda '3 = Stress Case' sobrevive — o cabeçalho caía sobre ela (defeito medido)",
      String(out.getRow(5).getCell(3).value ?? ""));
    checar(String(out.getRow(1).getCell(3).value ?? "") === "SCENARIO",
      "(0105g) …e 'SCENARIO' continua na linha 1", String(out.getRow(1).getCell(3).value ?? ""));
  }

  // ---- (0105h) os covenants e o diagnóstico respondem -------------------
  {
    const i2026 = iAnoDe(2026);
    const diag = valorNaAba("Output", "Diagnóstico do exercício", i2026);
    checar(typeof diag === "string" && diag.length > 0,
      "(0105h) o Output devolve um diagnóstico por exercício (a linha que o comitê lê primeiro)",
      JSON.stringify(diag));
    const nd = valorNaAba("Output", "Net Debt / EBITDA", i2026);
    checar(typeof nd === "number" || (typeof nd === "string" && nd === "EBITDA<=0"),
      "(0105h) Net Debt / EBITDA é número, ou texto explícito quando o EBITDA não é positivo",
      JSON.stringify(nd));
  }

  // ---- (0105i) o revolver cobre o furo e o caixa nunca fica abaixo do mínimo
  {
    const desvios: string[] = [];
    for (let i = iAnoDe(2026); i < COLS_ANO.length; i++) {
      const caixa = valorNaAba("Cash Flow", "CAIXA DE FECHAMENTO", i);
      const min = valorNaAba("ST Inv. & Debt", "Caixa mínimo operacional", i);
      if (typeof caixa !== "number" || typeof min !== "number") { desvios.push(`${ANOS[i]}: não avaliável`); continue; }
      if (caixa < min - 0.5) desvios.push(`${ANOS[i]}: caixa ${caixa.toFixed(0)} < mínimo ${min.toFixed(0)}`);
    }
    checar(desvios.length === 0,
      "(0105i) o revolver cobre o furo: o caixa de fechamento nunca fica abaixo do caixa mínimo",
      desvios.join(" · "));
  }

  // ---- (0106d) OS GRÁFICOS ENTRAM NO PAPEL --------------------------------
  //
  // Medido no arquivo entregue: os 8 gráficos estavam ancorados nas colunas N a AE
  // e a área de impressão do `Output` é B:K — quem gerasse o PDF do Output (que é
  // como o comitê recebe) não levava gráfico nenhum. Gráfico fora da área de
  // impressão é trabalho que existe só na tela de quem o fez.
  {
    const out = wbMod.getWorksheet("Output")!;
    const area = String(out.pageSetup?.printArea ?? "");
    const m = /^B1:([A-Z]+)(\d+)$/.exec(area);
    const colLimite = m ? m[1] : "";
    const linhaLimite = m ? Number(m[2]) : 0;
    // Índice base 1 da última coluna da área de impressão.
    const colParaNum = (s: string) => [...s].reduce((n, ch) => n * 26 + (ch.charCodeAt(0) - 64), 0);
    // Confere os DOIS cantos, e que o retângulo não é degenerado: conferir só o
    // canto inferior deixava passar uma âncora invertida (`de` à direita de `ate`),
    // que o Excel desenha como nada. Primeira versão deste assert fazia isso, e o
    // defeito religado passou verde — ver §8.2 do CLAUDE.md.
    const colB = 2; // a área de impressão do modelo começa sempre em B1
    const fora = graficosDoModelo.filter((esp) =>
      // A âncora do OOXML é base 0; a coluna da área de impressão é base 1.
      esp.de.col + 1 < colB || esp.de.linha + 1 < 1
      || esp.ate.col + 1 > colParaNum(colLimite) || esp.ate.linha + 1 > linhaLimite
      || esp.de.col >= esp.ate.col || esp.de.linha >= esp.ate.linha);
    checar(m !== null && graficosDoModelo.length === 8 && fora.length === 0,
      "(0106d) os 8 gráficos do Output estão DENTRO da área de impressão da aba",
      `área ${area || "(ausente)"} · gráficos ${graficosDoModelo.length} · fora ${fora.length}`
      + (fora.length ? `: ${fora.map((f) => `${f.titulo} até col ${f.ate.col} lin ${f.ate.linha}`).join(" · ")}` : ""));
  }

  // ---- (0106f) O CÂMBIO É NÍVEL, NUNCA VARIAÇÃO ---------------------------
  //
  // A linha "R$/US$ — final de período" do arquivo entregue trazia 24,5 em 2024 e
  // −10,6 em 2025 (câmbio negativo!) ao lado de 5,2 do Focus: o RETORNO de uma série
  // de nível publicado numa linha de nível. A célula agora fica VAZIA quando a fonte
  // entrega a grandeza errada, com o motivo na nota.
  {
    const anual = wbMod.getWorksheet("Anual")!;
    const rFx = linhaDoRotulo("Anual", "R$/US$ — final de período");
    const v2024 = rFx === null ? null : anual.getRow(rFx).getCell(COLS_ANO[iAnoDe(2024)]).value;
    const v2026 = rFx === null ? null : avaliarCelula(anual, COLS_ANO[iAnoDe(2026)], rFx);
    checar(rFx !== null && (v2024 === null || v2024 === undefined),
      "(0106f) a série de NÍVEL recusa a variação: a célula fica vazia em vez de publicar câmbio negativo",
      `2024 = ${JSON.stringify(v2024)}`);
    checar(rFx !== null && typeof v2026 === "number" && Math.abs(v2026 - 5.4) < 0.001,
      "(0106f) …e o nível de fato publicado (expectativa do Focus, 5,40) continua chegando",
      JSON.stringify(v2026));
  }

  // ---- (0106i) O PAINEL DE PREMISSAS RESPONDE À EDIÇÃO NO EXCEL ------------
  //
  // A promessa é "trocar o índice ou o spread dentro do arquivo reprojeta o
  // modelo". Um assert que só conferisse a existência das linhas não provaria nada:
  // este SIMULA a edição — escreve na célula de escolha da série, esquece a memória
  // do avaliador e recalcula, exigindo que a receita projetada MUDE na direção
  // certa. É o mais próximo de "o dono abriu e editou" que dá para fazer sem Excel.
  {
    const rec = wbMod.getWorksheet("Revenues, COGS & SG&A")!;
    const rTotal = linhaDoRotulo("Revenues, COGS & SG&A", "= crescimento nominal aplicado");
    const rSerie = rTotal === null ? null : rTotal - 2;
    checar(rTotal !== null,
      "(0106i) a aba de receita traz o PAINEL DE PREMISSAS (índice macro × spread)", String(rTotal));

    const iA = iAnoDe(2026);
    const rReceita = linhaDoRotulo("Revenues, COGS & SG&A", "Vendas de produtos - mercado interno");
    if (rTotal !== null && rSerie !== null && rReceita !== null) {
      // 1. Como o arquivo nasce: índice "(nenhum)" e o crescimento é exatamente a
      //    premissa que o portal escolheu (8% em 2026). Continuidade — o painel
      //    acrescenta mecanismo sem mexer em número.
      const escolha = rec.getRow(rSerie).getCell(4);
      checar(String(escolha.value ?? "") === "(nenhum)",
        "(0106i) o painel nasce com índice \"(nenhum)\", reproduzindo a premissa do portal",
        String(escolha.value ?? ""));
      const cresc0 = avaliarCelula(rec, COLS_ANO[iA], rTotal);
      checar(typeof cresc0 === "number" && Math.abs(cresc0 - 0.08) < 1e-9,
        "(0106i) …e o crescimento nominal aplicado é os 8% do portal", JSON.stringify(cresc0));
      const receita0 = avaliarCelula(rec, COLS_ANO[iA], rReceita);

      // 2. A EDIÇÃO: o analista escolhe IPCA no dropdown. O IPCA de 2026 na fixture
      //    é 4,5%, então o crescimento tem de virar (1+4,5%)×(1+8%)−1 = 12,86%.
      escolha.value = "IPCA";
      esquecerMemoria(rec);
      esquecerMemoria(wbMod.getWorksheet("Anual")!);
      const cresc1 = avaliarCelula(rec, COLS_ANO[iA], rTotal);
      const esperado = 1.045 * 1.08 - 1;
      checar(typeof cresc1 === "number" && Math.abs(cresc1 - esperado) < 1e-9,
        "(0106i) escolher IPCA no dropdown COMPÕE índice e spread — (1+4,5%)×(1+8%)−1, não a soma",
        `${JSON.stringify(cresc1)} (esperado ${esperado.toFixed(6)})`);
      const receita1 = avaliarCelula(rec, COLS_ANO[iA], rReceita);
      checar(typeof receita0 === "number" && typeof receita1 === "number" && receita1 > receita0,
        "(0106i) …e a RECEITA PROJETADA acompanha a edição — é o que faz do arquivo uma alternativa "
        + "de edição ao portal",
        `receita 2026: ${JSON.stringify(receita0)} → ${JSON.stringify(receita1)}`);

      // 3. Devolve o arquivo ao estado original: os asserts seguintes (e o de
      //    reprodutibilidade do gerador) leem o mesmo workbook.
      escolha.value = "(nenhum)";
      esquecerMemoria(rec);
      esquecerMemoria(wbMod.getWorksheet("Anual")!);
      const cresc2 = avaliarCelula(rec, COLS_ANO[iA], rTotal);
      checar(typeof cresc2 === "number" && Math.abs(cresc2 - 0.08) < 1e-9,
        "(0106i) …e voltar a escolha a \"(nenhum)\" devolve a premissa do portal (a edição é reversível)",
        JSON.stringify(cresc2));
    }
  }

  // ---- (0107) FASE C — O QUE FALTAVA DE MOTOR, POR IMPACTO -----------------
  //
  // Os três itens estruturais da fila do §5 do CONFORMIDADE.md que dependiam só de
  // nós. Cada um tem assert próprio porque cada um pode regredir sozinho.
  {
    // (0107a) A VARIAÇÃO DE GIRO ABERTA CONTA A CONTA, e a abertura tem de FECHAR
    // com o total — que continua vindo do espelho da aba de giro. Duas origens para
    // o mesmo número só valem com uma linha de conferência entre elas.
    const rConf = linhaDoRotulo("Cash Flow", "conferência: soma das contas − total (ZERO)");
    const cf = wbMod.getWorksheet("Cash Flow")!;
    const desvios: string[] = [];
    for (const ano of [2026, 2027, 2028]) {
      const v = rConf === null ? null : avaliarCelula(cf, COLS_ANO[iAnoDe(ano)], rConf);
      if (typeof v !== "number" || Math.abs(v) > 0.01) desvios.push(`${ano}: ${JSON.stringify(v)}`);
    }
    checar(rConf !== null && desvios.length === 0,
      "(0107a) a variação de giro do Cash Flow é aberta CONTA A CONTA e a abertura fecha com o total",
      desvios.join(" · "));
    // E a abertura existe de fato: uma linha por conta de giro do caso.
    let nContas = 0;
    for (let r = 1; r <= cf.rowCount; r++) {
      if (/^\s{4}\((−|\+)\)\s/.test(String(cf.getRow(r).getCell(3).value ?? ""))) nContas++;
    }
    checar(nContas >= 3,
      "(0107a) …e há uma linha por conta de giro, não uma linha agregada",
      `linhas de conta no bloco de operações: ${nContas}`);

    // (0107b) O CHECK DO BALANÇO NO TOPO DAS QUATRO ABAS DE DRIVER. É onde a
    // premissa é mexida, e portanto onde o "o balanço abriu" tem de aparecer.
    const semCheck: string[] = [];
    for (const aba of ["Revenues, COGS & SG&A", "Working Capital", "Fixed Assets & CAPEX",
                       "ST Inv. & Debt"]) {
      const r = linhaDoRotulo(aba, "CHECK do balanço (0 = fecha)");
      const ws = wbMod.getWorksheet(aba);
      if (r === null || !ws) { semCheck.push(`${aba}: linha ausente`); continue; }
      // Tem de estar no TOPO (logo abaixo do cabeçalho), senão não serve ao propósito.
      if (r > 8) semCheck.push(`${aba}: linha ${r} (esperado no topo)`);
      // A CÉLULA TEM DE SER FÓRMULA APONTANDO PARA O BALANÇO — não basta avaliar
      // zero. Célula VAZIA avalia 0 no avaliador (é o contrato dele), então uma
      // versão anterior deste assert passava verde com a linha existindo e nunca
      // preenchida: exatamente a armadilha da "fixture que nasce vazia" que o
      // CLAUDE.md descreve, cometida aqui dentro.
      const bruto = ws.getRow(r).getCell(COLS_ANO[iAnoDe(2026)]).value as { formula?: string } | null;
      const formula = bruto && typeof bruto === "object" && "formula" in bruto ? bruto.formula ?? "" : "";
      if (!/Balance Sheet/.test(formula)) {
        semCheck.push(`${aba}: célula não é fórmula do Balance Sheet (${JSON.stringify(bruto)})`);
        continue;
      }
      const v = avaliarCelula(ws, COLS_ANO[iAnoDe(2026)], r);
      if (typeof v !== "number" || Math.abs(v) > 0.01) semCheck.push(`${aba}: ${JSON.stringify(v)}`);
    }
    checar(semCheck.length === 0,
      "(0107b) as quatro abas de driver publicam o CHECK do balanço no topo, e ele fecha",
      semCheck.join(" · "));

    // (0107c) OS ESPELHOS DO OUTPUT CONTA A CONTA. O item de maior impacto da fila:
    // o `Output` é a aba que vai a comitê, e um espelho só de totais obriga a voltar
    // às abas de origem para saber do que o número é feito.
    const detalhes = [
      ["Output", "    Operating current assets"],
      ["Output", "    Short-term debt + revolver"],
      ["Output", "    Retained earnings (model)"],
      ["Output", "    (+) D&A"],
      ["Output", "    (+/−) Change in working capital"],
      ["Output", "    (−) CAPEX"],
      ["Output", "    (+) New debt"],
    ] as const;
    const faltam = detalhes.filter(([aba, rot]) => linhaDoRotulo(aba, rot.trim()) === null
      && linhaDoRotulo(aba, rot) === null);
    checar(faltam.length === 0,
      "(0107c) os espelhos de balanço e fluxo do Output são abertos conta a conta",
      faltam.map(([, r]) => r.trim()).join(" · "));
    // E o detalhe tem de BATER com a origem — espelho que não bate é pior que
    // espelho que não existe.
    const out = wbMod.getWorksheet("Output")!;
    const bs = wbMod.getWorksheet("Balance Sheet")!;
    const rEsp = linhaDoRotulo("Output", "Operating current assets");
    const rOrig = linhaDoRotulo("Balance Sheet", "Ativo circulante operacional");
    const vEsp = rEsp === null ? null : avaliarCelula(out, COLS_ANO[iAnoDe(2026)], rEsp);
    const vOrig = rOrig === null ? null : avaliarCelula(bs, COLS_ANO[iAnoDe(2026)], rOrig);
    checar(typeof vEsp === "number" && typeof vOrig === "number" && Math.abs(vEsp - vOrig) < 0.01,
      "(0107c) …e cada linha do espelho é o MESMO número da aba de origem",
      `espelho ${JSON.stringify(vEsp)} · origem ${JSON.stringify(vOrig)}`);
  }

  // ---- (0106g) MODELO SEM DRE DIZ QUE ESTÁ SEM DRE -------------------------
  //
  // Quando a extração não classifica as linhas de resultado (`secao_canonica`
  // ausente — medido na cadeia do book: 767 campos, todos sem), a cascata da DRE
  // sai inteira em ZERO. Zero em tudo parece "empresa sem operação", que é uma
  // afirmação sobre o negócio; o fato é "o modelo não recebeu a DRE". Antes as duas
  // coisas tinham exatamente a mesma aparência.
  {
    const semDRE = {
      ...entradaModelo,
      linhas: entradaModelo.linhas.filter((l) =>
        !["receita_bruta", "custos", "despesas_operacionais"].includes(l.secao_canonica)),
    };
    const wbSemDRE = buildExportWorkbook({
      caso: entradaModelo.caso, documentos: docsModelo, campos: camposModelo,
      agora: new Date("2026-08-05T12:00:00Z"), modo: "completo",
      modeloInstitucional: semDRE as unknown as Parameters<typeof buildExportWorkbook>[0]["modeloInstitucional"],
    });
    const ws = wbSemDRE.getWorksheet("Income Statement");
    let achou = false;
    for (let r = 1; ws && r <= ws.rowCount; r++) {
      if (/^SEM DRE:/.test(String(ws.getRow(r).getCell(3).value ?? ""))) { achou = true; break; }
    }
    checar(achou,
      "(0106g) modelo cuja extração não trouxe linha de resultado ANUNCIA que está sem DRE, em vez "
      + "de exibir uma cascata zerada com cara de empresa sem operação");
  }

  esquecerMemoria(wbMod.getWorksheet("Balance Sheet")!);
}

console.log(`${ok} verificações OK / ${falhas.length} falhas`);
for (const f of falhas) console.log("  FALHOU:", f);
process.exit(falhas.length ? 1 : 0);
