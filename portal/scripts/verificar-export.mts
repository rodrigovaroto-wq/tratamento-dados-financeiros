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
import { buildExportWorkbook, chaveCronologicaPeriodo, tipoColunaNaoEntidade, type DocumentoParaExport } from "../src/lib/export";
import type { CampoExtraido } from "../src/lib/types";

let ok = 0;
const falhas: string[] = [];
function checar(cond: boolean, desc: string, detalhe = "") {
  if (cond) ok++;
  else falhas.push(`${desc}${detalhe ? ` — ${detalhe}` : ""}`);
}

// Avaliador mínimo das fórmulas que o export emite numa coluna: SUM(range),
// referência simples (=B12) e soma de referências (=B4+B39). Suficiente para
// conferir os totais sem abrir o Excel.
function avaliar(ws: import("exceljs").Worksheet, col: string, row: number, prof = 0): number {
  if (prof > 12) throw new Error("fórmula recursiva");
  const cell = ws.getRow(row).getCell(col);
  const v = cell.value;
  if (typeof v === "number") return v;
  const f = (v as { formula?: string } | null)?.formula;
  if (!f) return 0;
  const mSum = f.match(/^SUM\(([A-Z]+)(\d+):([A-Z]+)(\d+)\)$/);
  if (mSum) {
    let t = 0;
    for (let r = Number(mSum[2]); r <= Number(mSum[4]); r++) t += avaliar(ws, mSum[1], r, prof + 1);
    return t;
  }
  if (/^[A-Z]+\d+(\+[A-Z]+\d+)*$/.test(f)) {
    return f.split("+").reduce((a, ref) => {
      const m = ref.match(/^([A-Z]+)(\d+)$/)!;
      return a + avaliar(ws, m[1], Number(m[2]), prof + 1);
    }, 0);
  }
  return 0;
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
  const rAdiant = linhaDe("Adiantamentos de clientes");
  const rPC = linhaDe("Passivo Circulante");
  const rPNC = linhaDe("Passivo Não Circulante");
  checar(rAdiant > rPC && rAdiant < rPNC, "(3) 'Adiantamentos de clientes' no Passivo Circulante");
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

console.log(`${ok} verificações OK / ${falhas.length} falhas`);
for (const f of falhas) console.log("  FALHOU:", f);
process.exit(falhas.length ? 1 : 0);
