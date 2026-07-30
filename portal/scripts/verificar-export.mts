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
import { avaliarCelula, linhaVazia } from "./lib/avaliar-formula.mts";
import { buildExportWorkbook, chaveCronologicaPeriodo, consolidarNomesDeEntidade, tipoColunaNaoEntidade, type DocumentoParaExport } from "../src/lib/export";
import type { CampoExtraido } from "../src/lib/types";

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
    checar(crus.length === 0,
      "(11) nenhum número escrito à mão fora dos inputs — tudo é fórmula",
      crus.slice(0, 8).join(" / "));
    checar(formulas > 60, `(11) o modelo é feito de fórmula (${formulas} células)`);
    checar(inputs > 0, `(11) e tem células de input marcadas (${inputs})`);

    // 2. As fórmulas históricas apontam para as ABAS DE DADOS deste mesmo
    //    arquivo — é isso que mantém a planilha viva (corrigiu a origem, o
    //    modelo acompanha) em vez de congelar um número no modelo.
    const alvos = new Set<string>();
    for (let r = 1; r <= ws.rowCount; r++) {
      for (let c = 3; c <= ws.columnCount; c++) {
        const v = ws.getRow(r).getCell(c).value as { formula?: string } | undefined;
        const f = v?.formula;
        if (!f) continue;
        for (const m of f.matchAll(/'([^']+)'!/g)) alvos.add(m[1]);
      }
    }
    for (const aba of ["Balanço", "DRE", "Fluxo de Caixa"]) {
      checar(alvos.has(aba), `(11) o modelo puxa da aba ${aba} por referência`);
    }

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

  // 4. NENHUMA aba oculta (pedido do dono no teste v28: "quero todas as abas
  //    juntas no exportável"). Reverte a decisão do v27 — e o motivo é concreto:
  //    ele abriu o v28, viu 4 abas e concluiu que DMPL/Combinado/Balancete/
  //    Faturamento/Dívida/Intragrupo/Outros "não vieram". Estavam lá, ocultas.
  //    Aba oculta em arquivo de entrega lê-se como dado ausente.
  const ocultas = wb.worksheets.filter((s) => s.state !== "visible").map((s) => s.name);
  checar(ocultas.length === 0, "(11) nenhuma aba fica oculta na entrega", `ocultas: ${ocultas.join(", ")}`);
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
  checar(procurados > 0, "(13) o modelo faz buscas por rótulo nas abas de dados");
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
    readFileSync("/home/user/tratamento-dados-financeiros/test-data/book-vertentes/pdf/GABARITO.json", "utf8"),
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
    // Janela sem anos completos suficientes fica VAZIA em vez de inventada.
    checar(medias.every((f) => f.includes("COUNT(")),
      "(15) a janela só calcula com anos completos suficientes");
  }

  // O modelo consome o Focus: as premissas macro apontam para a aba Macro.
  const mod = wb.getWorksheet("Modelagem")!;
  const linhaDe = (rot: string) => {
    for (let r = 1; r <= mod.rowCount; r++) {
      if (String(mod.getRow(r).getCell(1).value ?? "") === rot) return r;
    }
    return -1;
  };
  const rIpca = linhaDe("Inflação esperada (IPCA — Focus)");
  const rSelic = linhaDe("Juro esperado (Selic — Focus)");
  checar(rIpca > 0 && rSelic > 0, "(15) o modelo tem premissas de IPCA e Selic");
  if (rIpca > 0) {
    const nA = Math.floor((mod.columnCount - 2) / 13);
    const f = String((mod.getRow(rIpca).getCell(3 + (nA - 1) * 13 + 12).value as { formula?: string })?.formula ?? "");
    checar(f.includes("'Macro'!"), "(15) a premissa de IPCA vem da aba Macro (Focus), não digitada", f.slice(0, 90));
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
    checar(rANC > 0 && formulas.some((f) => f.includes("Balanço")),
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

console.log(`${ok} verificações OK / ${falhas.length} falhas`);
for (const f of falhas) console.log("  FALHOU:", f);
process.exit(falhas.length ? 1 : 0);
