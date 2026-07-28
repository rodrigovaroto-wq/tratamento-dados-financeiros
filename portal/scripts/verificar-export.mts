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
  const abasComponente = wb.worksheets.filter((s) => s.name !== "DMPL" && s.name !== "Resumo");
  checar(abasComponente.length === 0, "(10d) a DMPL não vaza para nenhuma outra aba",
    abasComponente.map((s) => s.name).join(", "));
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
    const anoBase = rAno > 0 ? ws.getRow(rAno).getCell(3).value : null;
    const anoSeg = rAno > 0 ? ws.getRow(rAno).getCell(4).value as { formula?: string } | undefined : undefined;
    checar(typeof anoBase === "number" && !!anoSeg?.formula?.includes("+1"),
      "(11) a linha do tempo deriva do primeiro exercício, não é digitada coluna a coluna",
      `linha=${rAno} base=${String(anoBase)} seguinte=${anoSeg?.formula ?? "(sem fórmula)"}`);
  }

  // 4. Abas de dado cru ficam OCULTAS, mas continuam no arquivo (o modelo
  //    aponta para elas e a proveniência não pode sumir da entrega).
  const visiveis = wb.worksheets.filter((s) => s.state === "visible").map((s) => s.name);
  const ocultas = wb.worksheets.filter((s) => s.state === "hidden").map((s) => s.name);
  checar(visiveis.includes("Modelagem") && visiveis.includes("Balanço"),
    "(11) Modelagem e as demonstrações principais ficam visíveis", visiveis.join(", "));
  checar(!visiveis.includes("Balancete") && ocultas.includes("Balancete"),
    "(11) as abas de apoio ficam ocultas — e continuam no arquivo", `visíveis: ${visiveis.join(", ")}`);
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
  const projetadas: number[] = [];
  for (let c = 3; c <= ws.columnCount; c++) {
    const v = ws.getRow(linhaAno).getCell(c).value;
    if (typeof v === "object" && v !== null && "formula" in v) projetadas.push(c);
  }
  // (a primeira coluna é digitada; as demais derivam — as projetadas são as
  //  últimas `anosProjetados`, mas para o teste basta olhar da 3ª em diante)
  const colsProjetadas = projetadas.slice(-3);
  checar(colsProjetadas.length === 3, `(14) há 3 exercícios projetados`, String(colsProjetadas.length));

  // As linhas de RESULTADO que precisam responder a premissa.
  const alvosDeTeste = [
    "Receita Líquida", "EBITDA", "Lucro/Prejuízo Líquido do Exercício",
    "Saldo final de caixa", "TOTAL DO ATIVO", "Patrimônio Líquido",
    "Necessidade (+) / sobra (−) de financiamento", "Liquidez corrente",
  ];
  const linhaDe = (rot: string) => {
    for (let r = 1; r <= ws.rowCount; r++) {
      if (String(ws.getRow(r).getCell(1).value ?? "") === rot) return r;
    }
    return -1;
  };

  const mortas: string[] = [];
  for (const c of colsProjetadas) {
    const letra = colunaLetra(c);
    const premissasDaColuna = new Set(linhasPremissa.map((r) => `${letra}${r}`));
    for (const rot of alvosDeTeste) {
      const r = linhaDe(rot);
      if (r < 0) { mortas.push(`linha ausente: ${rot}`); continue; }
      if (!alcanca(`${letra}${r}`, premissasDaColuna)) {
        mortas.push(`${letra}${r} (${rot}) não depende de nenhuma premissa de ${letra}`);
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

console.log(`${ok} verificações OK / ${falhas.length} falhas`);
for (const f of falhas) console.log("  FALHOU:", f);
process.exit(falhas.length ? 1 : 0);
