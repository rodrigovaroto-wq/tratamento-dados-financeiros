import ExcelJS from "exceljs";
import type { CampoExtraido } from "./types";
import { casarPadrao, normalizar, TEMPLATE_POR_TIPO, type TemplateRow } from "./statement-templates";

// Modo B do output (f0/07_output_spec.md): export sob demanda. Princípio
// inegociável da spec: "Dado sem aceite não é entregue como fato — no
// máximo aparece como sugestão pendente de revisão, visualmente distinta."
// Por isso TODAS as linhas aparecem (aceitas e pendentes), mas com
// status/estilo bem distintos — nada aqui vira fato silenciosamente.
//
// Balanço/DRE/Fluxo de Caixa/Combinado saem no LAYOUT PADRÃO DE MERCADO
// dessas demonstrações (`statement-templates.ts`), com entidade×período nas
// colunas — como um analista financeiro realmente lê esses documentos, não
// uma lista achatada. Faturamento/Dívida/Fluxo Projetado continuam em
// listagem simples (já são, por natureza, uma série/tabela — não uma
// demonstração de 3 blocos com Ativo/Passivo/PL). O export NÃO modela nem
// projeta (fora do escopo, mesma spec) — só reorganiza o dado curado e
// rastreável, sem inventar nenhum número novo.
//
// Função pura (sem Supabase/Next.js) para ser testável isoladamente — a rota
// (`app/casos/[id]/export/route.ts`) só busca os dados e chama esta função.

// tipo_taxonomia → nome da aba (ordem de prioridade travada em f0/07).
export const ABA_POR_TIPO: Record<string, string> = {
  BALANCO: "Balanço",
  DRE: "DRE",
  FLUXO_CAIXA: "Fluxo de Caixa",
  COMBINADO: "Combinado",
  FATURAMENTO_24M: "Faturamento",
  MUTUOS: "Dívida",
  MAPA_DIVIDA: "Dívida",
  CONTRATO_DIVIDA: "Dívida",
  FLUXO_PROJETADO: "Fluxo Projetado",
};
export const ORDEM_ABAS = [
  "Balanço",
  "DRE",
  "Fluxo de Caixa",
  "Combinado",
  "Faturamento",
  "Dívida",
  "Fluxo Projetado",
  "Outros",
];
// Abas que saem no layout padronizado (statement-templates.ts) em vez de
// listagem simples.
const ABAS_COM_TEMPLATE = new Set(Object.keys(TEMPLATE_POR_TIPO).map((tipo) => ABA_POR_TIPO[tipo]));

export interface DocumentoParaExport {
  id: string;
  tipo_taxonomia: string | null;
  entidade: { razao_social: string } | null;
  periodo: { tipo: string; referencia: string } | null;
  documento_versao: Array<{ id: string; nome_original: string | null }> | null;
}

export interface TaxonomiaParaExport {
  codigo: string;
  documento: string;
  versao: number;
}

interface ContextoVersao {
  entidade: string;
  periodo: string;
  tipoTaxonomia: string | null;
  nomeArquivo: string;
}

interface Coluna {
  key: string;
  entidade: string;
  periodo: string;
}

export function nomeArquivoSanitizado(nomeCaso: string) {
  return nomeCaso
    .normalize("NFD")
    .replace(/[̀-ͯ]/g, "") // remove acentos (marcas de combinação) após NFD
    .replace(/[^a-zA-Z0-9]+/g, "-")
    .replace(/(^-|-$)/g, "");
}

function formatarStatus(status: string) {
  return status === "aceito" ? "ACEITO" : status === "com_ressalva" ? "COM RESSALVA" : "PENDENTE";
}

function notaProveniencia(campo: CampoExtraido, ctx: ContextoVersao, versaoTaxonomia: number | null) {
  const linhas = [
    `Rótulo original: "${campo.chave}"`,
    `Arquivo: ${ctx.nomeArquivo}`,
    campo.origem_pagina != null ? `Página: ${campo.origem_pagina}` : null,
    campo.confianca != null ? `Confiança da extração: ${Math.round(campo.confianca * 100)}%` : null,
    `Status: ${formatarStatus(campo.status_aceite)}`,
    campo.status_aceite === "aceito" && campo.aceito_por ? `Aceito por: ${campo.aceito_por}` : null,
    versaoTaxonomia != null ? `Versão da taxonomia: ${versaoTaxonomia}` : null,
  ].filter(Boolean);
  return linhas.join("\n");
}

const VALOR_NUM_FMT = "#,##0.00;(#,##0.00)";
const PENDENTE_FILL: ExcelJS.Fill = { type: "pattern", pattern: "solid", fgColor: { argb: "FFFFF3CD" } };
const HEADER_FILL: ExcelJS.Fill = { type: "pattern", pattern: "solid", fgColor: { argb: "FFE5E7EB" } };
const SECAO_FILL: ExcelJS.Fill = { type: "pattern", pattern: "solid", fgColor: { argb: "FFF3F4F6" } };
const THIN_TOP_BORDER: Partial<ExcelJS.Borders> = { top: { style: "thin" } };
const DOUBLE_TOP_BORDER: Partial<ExcelJS.Borders> = { top: { style: "double" } };

// ----- Aba padronizada (Balanço/DRE/Fluxo de Caixa/Combinado) --------------
// Layout de mercado: uma linha por conta do template (statement-templates.ts),
// uma coluna por entidade×período. Todo valor vem de casar a chave extraída
// contra o template — NUNCA um cálculo/soma feito por nós (anti-ancoragem:
// só reorganiza o que a IA já extraiu, não inventa subtotal novo).
function construirAbaPadronizada(
  workbook: ExcelJS.Workbook,
  nomeAba: string,
  template: TemplateRow[],
  colunas: Coluna[],
  camposPorColuna: Map<string, CampoExtraido[]>,
  contextoPorVersao: Map<string, ContextoVersao>,
  versaoDaColuna: Map<string, string>, // key da coluna → documento_versao_id (p/ nota de proveniência)
  taxonomiaPorCodigo: Map<string, { label: string; versao: number }>,
) {
  const sheet = workbook.addWorksheet(nomeAba, { views: [{ state: "frozen", xSplit: 1, ySplit: 1 }] });
  sheet.getColumn(1).width = 42;
  colunas.forEach((_, i) => {
    sheet.getColumn(i + 2).width = 20;
  });

  const headerRow = sheet.getRow(1);
  headerRow.getCell(1).value = "Conta";
  colunas.forEach((col, i) => {
    headerRow.getCell(i + 2).value = `${col.entidade} — ${col.periodo}`;
  });
  headerRow.font = { bold: true };
  headerRow.fill = HEADER_FILL;
  headerRow.alignment = { wrapText: true, vertical: "middle" };

  // Rastreia quais campos (por id) já foram usados por alguma linha do
  // template, por coluna — o que sobra vira o apêndice "Outras contas".
  const usadosPorColuna = new Map<string, Set<string>>();
  colunas.forEach((col) => usadosPorColuna.set(col.key, new Set()));

  let rowIndex = 2;
  for (const templateRow of template) {
    const row = sheet.getRow(rowIndex++);
    row.getCell(1).value = templateRow.label;
    row.getCell(1).alignment = { indent: templateRow.level };

    if (templateRow.kind === "header") {
      row.font = { bold: true };
      row.fill = SECAO_FILL;
      continue;
    }

    if (templateRow.kind === "subtotal") row.font = { bold: true };
    if (templateRow.kind === "total") { row.font = { bold: true }; }

    colunas.forEach((col, i) => {
      const campos = camposPorColuna.get(col.key) ?? [];
      const match = casarPadrao(campos, templateRow.patterns ?? []);
      const cell = row.getCell(i + 2);
      if (templateRow.kind === "subtotal") cell.border = THIN_TOP_BORDER;
      if (templateRow.kind === "total") cell.border = DOUBLE_TOP_BORDER;
      if (!match) return;

      usadosPorColuna.get(col.key)!.add(match.id);
      cell.value = match.valor_num ?? match.valor_texto ?? null;
      if (typeof cell.value === "number") cell.numFmt = VALOR_NUM_FMT;
      if (match.status_aceite !== "aceito") {
        cell.fill = PENDENTE_FILL;
        cell.font = { ...(row.font ?? {}), italic: true };
      }
      const versaoId = versaoDaColuna.get(col.key);
      const ctx = versaoId ? contextoPorVersao.get(versaoId) : undefined;
      if (ctx) {
        const tax = ctx.tipoTaxonomia ? taxonomiaPorCodigo.get(ctx.tipoTaxonomia) : undefined;
        cell.note = notaProveniencia(match, ctx, tax?.versao ?? null);
      }
    });
  }

  // ----- Apêndice: linhas extraídas que não bateram com nenhuma conta do
  // template — nada desaparece silenciosamente (mesma disciplina do projeto:
  // pré-condição não satisfeita vira pendência tipada, não um "OK" falso).
  const apendicePorChaveNorm = new Map<string, { label: string; porColuna: Map<string, CampoExtraido> }>();
  colunas.forEach((col) => {
    const campos = camposPorColuna.get(col.key) ?? [];
    const usados = usadosPorColuna.get(col.key)!;
    for (const campo of campos) {
      if (campo.valor_num == null || usados.has(campo.id)) continue;
      const chaveNorm = normalizar(campo.chave);
      if (!apendicePorChaveNorm.has(chaveNorm)) {
        apendicePorChaveNorm.set(chaveNorm, { label: campo.chave, porColuna: new Map() });
      }
      apendicePorChaveNorm.get(chaveNorm)!.porColuna.set(col.key, campo);
    }
  });

  if (apendicePorChaveNorm.size > 0) {
    rowIndex++; // linha em branco
    const tituloRow = sheet.getRow(rowIndex++);
    tituloRow.getCell(1).value = "Outras contas identificadas (não mapeadas ao padrão acima)";
    tituloRow.font = { bold: true, italic: true };
    tituloRow.fill = SECAO_FILL;

    for (const { label, porColuna } of apendicePorChaveNorm.values()) {
      const row = sheet.getRow(rowIndex++);
      row.getCell(1).value = label;
      colunas.forEach((col, i) => {
        const campo = porColuna.get(col.key);
        if (!campo) return;
        const cell = row.getCell(i + 2);
        cell.value = campo.valor_num ?? campo.valor_texto ?? null;
        if (typeof cell.value === "number") cell.numFmt = VALOR_NUM_FMT;
        if (campo.status_aceite !== "aceito") {
          cell.fill = PENDENTE_FILL;
          cell.font = { italic: true };
        }
        const versaoId = versaoDaColuna.get(col.key);
        const ctx = versaoId ? contextoPorVersao.get(versaoId) : undefined;
        if (ctx) {
          const tax = ctx.tipoTaxonomia ? taxonomiaPorCodigo.get(ctx.tipoTaxonomia) : undefined;
          cell.note = notaProveniencia(campo, ctx, tax?.versao ?? null);
        }
      });
    }
  }
}

// ----- Aba simples (Faturamento/Dívida/Fluxo Projetado/Outros) -------------
// Já são, por natureza, uma série/tabela — não uma demonstração de 3 blocos.
interface LinhaSimples {
  entidade: string;
  periodo: string;
  secao: string;
  chave: string;
  valorTexto: string | null;
  valorNum: number | null;
  unidade: string | null;
  pagina: number | null;
  confianca: number | null;
  statusAceite: string;
  aceitoPor: string | null;
  aceitoEm: string | null;
  arquivoOrigem: string;
  versaoTaxonomia: number | null;
}

function construirAbaSimples(workbook: ExcelJS.Workbook, nomeAba: string, linhas: LinhaSimples[]) {
  linhas.sort((a, b) =>
    a.entidade.localeCompare(b.entidade) || a.periodo.localeCompare(b.periodo) || a.secao.localeCompare(b.secao),
  );

  const sheet = workbook.addWorksheet(nomeAba, { views: [{ state: "frozen", ySplit: 1 }] });
  sheet.columns = [
    { header: "Entidade", key: "entidade", width: 26 },
    { header: "Período", key: "periodo", width: 14 },
    { header: "Seção", key: "secao", width: 24 },
    { header: "Rótulo", key: "chave", width: 34 },
    { header: "Valor", key: "valorNum", width: 16 },
    { header: "Unidade", key: "unidade", width: 10 },
    { header: "Página", key: "pagina", width: 8 },
    { header: "Confiança", key: "confianca", width: 10 },
    { header: "Status", key: "statusAceite", width: 12 },
    { header: "Aceito por", key: "aceitoPor", width: 22 },
    { header: "Aceito em", key: "aceitoEm", width: 18 },
    { header: "Arquivo de origem", key: "arquivoOrigem", width: 30 },
    { header: "Versão taxonomia", key: "versaoTaxonomia", width: 14 },
  ];
  sheet.getRow(1).font = { bold: true };
  sheet.getRow(1).fill = HEADER_FILL;

  for (const linha of linhas) {
    const row = sheet.addRow({
      entidade: linha.entidade,
      periodo: linha.periodo,
      secao: linha.secao,
      chave: linha.chave,
      valorNum: linha.valorNum ?? linha.valorTexto ?? null,
      unidade: linha.unidade ?? "",
      pagina: linha.pagina ?? "",
      confianca: linha.confianca != null ? linha.confianca : "",
      statusAceite: formatarStatus(linha.statusAceite),
      aceitoPor: linha.aceitoPor ?? "",
      aceitoEm: linha.aceitoEm ? new Date(linha.aceitoEm).toLocaleString("pt-BR") : "",
      arquivoOrigem: linha.arquivoOrigem,
      versaoTaxonomia: linha.versaoTaxonomia ?? "",
    });
    if (typeof row.getCell("valorNum").value === "number") row.getCell("valorNum").numFmt = VALOR_NUM_FMT;
    if (/total/i.test(linha.chave)) row.font = { bold: true };
    if (linha.statusAceite !== "aceito") {
      row.eachCell((cell) => {
        cell.fill = PENDENTE_FILL;
      });
      row.font = { ...row.font, italic: true };
    }
  }
}

export function buildExportWorkbook({
  caso,
  taxonomia,
  documentos,
  campos,
  agora = new Date(),
}: {
  caso: { nome: string; produto: string };
  taxonomia: TaxonomiaParaExport[];
  documentos: DocumentoParaExport[];
  campos: CampoExtraido[];
  agora?: Date;
}): ExcelJS.Workbook {
  const taxonomiaPorCodigo = new Map(taxonomia.map((t) => [t.codigo, { label: t.documento, versao: t.versao }]));

  // Mapa documento_versao_id → contexto (entidade/período/tipo/arquivo) —
  // permite juntar campo_extraido (que só sabe a versão) com o resto.
  const contextoPorVersao = new Map<string, ContextoVersao>();
  for (const doc of documentos) {
    for (const versao of doc.documento_versao ?? []) {
      contextoPorVersao.set(versao.id, {
        entidade: doc.entidade?.razao_social ?? "(sem entidade)",
        periodo: doc.periodo ? `${doc.periodo.tipo} ${doc.periodo.referencia}` : "(sem período)",
        tipoTaxonomia: doc.tipo_taxonomia,
        nomeArquivo: versao.nome_original ?? "(sem nome)",
      });
    }
  }

  // Agrupa por aba → coluna (entidade×período) → campos daquela coluna.
  const colunasPorAba = new Map<string, Map<string, Coluna>>();
  const camposPorAbaColuna = new Map<string, Map<string, CampoExtraido[]>>();
  const versaoDaColunaPorAba = new Map<string, Map<string, string>>();
  const linhasSimplesPorAba = new Map<string, LinhaSimples[]>();

  for (const campo of campos) {
    const ctx = contextoPorVersao.get(campo.documento_versao_id);
    if (!ctx) continue;
    const aba = (ctx.tipoTaxonomia && ABA_POR_TIPO[ctx.tipoTaxonomia]) || "Outros";
    const colKey = `${ctx.entidade} ${ctx.periodo}`;

    if (ABAS_COM_TEMPLATE.has(aba)) {
      if (!colunasPorAba.has(aba)) colunasPorAba.set(aba, new Map());
      if (!camposPorAbaColuna.has(aba)) camposPorAbaColuna.set(aba, new Map());
      if (!versaoDaColunaPorAba.has(aba)) versaoDaColunaPorAba.set(aba, new Map());
      colunasPorAba.get(aba)!.set(colKey, { key: colKey, entidade: ctx.entidade, periodo: ctx.periodo });
      if (!camposPorAbaColuna.get(aba)!.has(colKey)) camposPorAbaColuna.get(aba)!.set(colKey, []);
      camposPorAbaColuna.get(aba)!.get(colKey)!.push(campo);
      versaoDaColunaPorAba.get(aba)!.set(colKey, campo.documento_versao_id);
    } else {
      const tax = ctx.tipoTaxonomia ? taxonomiaPorCodigo.get(ctx.tipoTaxonomia) : undefined;
      if (!linhasSimplesPorAba.has(aba)) linhasSimplesPorAba.set(aba, []);
      linhasSimplesPorAba.get(aba)!.push({
        entidade: ctx.entidade,
        periodo: ctx.periodo,
        secao: campo.secao ?? "(sem seção)",
        chave: campo.chave,
        valorTexto: campo.valor_texto,
        valorNum: campo.valor_num,
        unidade: campo.unidade,
        pagina: campo.origem_pagina,
        confianca: campo.confianca,
        statusAceite: campo.status_aceite,
        aceitoPor: campo.aceito_por,
        aceitoEm: campo.aceito_em,
        arquivoOrigem: ctx.nomeArquivo,
        versaoTaxonomia: tax?.versao ?? null,
      });
    }
  }

  const workbook = new ExcelJS.Workbook();
  workbook.creator = "Oria — Tratamento de Dados Financeiros";
  workbook.created = agora;

  // ----- Aba Resumo (metadados do snapshot, f0/07: "data-base e versão da
  // taxonomia registradas") -----
  const resumo = workbook.addWorksheet("Resumo");
  const totalLinhas = campos.length;
  const totalAceitas = campos.filter((c) => c.status_aceite === "aceito").length;
  const versoesTaxonomia = [...new Set([...taxonomiaPorCodigo.values()].map((t) => t.versao))].sort();
  resumo.columns = [{ width: 32 }, { width: 60 }];
  resumo.addRows([
    ["Caso", caso.nome],
    ["Produto", caso.produto],
    ["Gerado em", agora.toLocaleString("pt-BR")],
    ["Linhas totais extraídas", totalLinhas],
    ["Linhas aceitas (fato)", totalAceitas],
    ["Linhas pendentes (sugestão, revisar)", totalLinhas - totalAceitas],
    ["Versão(ões) da taxonomia envolvidas", versoesTaxonomia.join(", ") || "—"],
    [""],
    [
      "Aviso",
      "Este export NÃO é modelagem financeira e não projeta nada — é dado curado e rastreável " +
        "para o time de análise trabalhar em cima (f0/07_output_spec.md). Linhas marcadas " +
        "PENDENTE ainda não passaram por aceite humano — não são fato, são sugestão a revisar " +
        "antes de entrar no modelo. Balanço/DRE/Fluxo de Caixa/Combinado seguem o layout padrão " +
        "de mercado dessas demonstrações; contas extraídas que não bateram com nenhuma linha do " +
        "padrão aparecem à parte, em \"Outras contas identificadas\", ao final de cada aba.",
    ],
  ]);
  resumo.getRow(1).font = { bold: true };
  resumo.getCell("B9").alignment = { wrapText: true };

  for (const aba of ORDEM_ABAS) {
    if (ABAS_COM_TEMPLATE.has(aba)) {
      const colunas = [...(colunasPorAba.get(aba)?.values() ?? [])].sort(
        (a, b) => a.entidade.localeCompare(b.entidade) || a.periodo.localeCompare(b.periodo),
      );
      if (colunas.length === 0) continue;
      const tipoTemplate = Object.keys(TEMPLATE_POR_TIPO).find((tipo) => ABA_POR_TIPO[tipo] === aba)!;
      construirAbaPadronizada(
        workbook,
        aba,
        TEMPLATE_POR_TIPO[tipoTemplate],
        colunas,
        camposPorAbaColuna.get(aba) ?? new Map(),
        contextoPorVersao,
        versaoDaColunaPorAba.get(aba) ?? new Map(),
        taxonomiaPorCodigo,
      );
    } else {
      const linhas = linhasSimplesPorAba.get(aba);
      if (!linhas || linhas.length === 0) continue;
      construirAbaSimples(workbook, aba, linhas);
    }
  }

  return workbook;
}
