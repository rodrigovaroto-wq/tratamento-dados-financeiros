import ExcelJS from "exceljs";
import type { CampoExtraido } from "./types";

// Modo B do output (f0/07_output_spec.md): export sob demanda, uma aba por
// demonstração, entidades × períodos consolidados. Princípio inegociável da
// spec: "Dado sem aceite não é entregue como fato — no máximo aparece como
// sugestão pendente de revisão, visualmente distinta." Por isso TODAS as
// linhas aparecem (aceitas e pendentes), mas com status/estilo bem distintos
// — nada aqui vira fato silenciosamente. O export NÃO modela, NÃO projeta
// (fora do escopo, mesma spec) — só organiza o dado curado e rastreável.
//
// Função pura (sem Supabase/Next.js) para ser testável isoladamente — a rota
// (`app/casos/[id]/export/route.ts`) só busca os dados e chama esta função.

// Ordem de prioridade travada em f0/07 — tipo_taxonomia → nome da aba.
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

interface LinhaExport {
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

export function nomeArquivoSanitizado(nomeCaso: string) {
  return nomeCaso
    .normalize("NFD")
    .replace(/[̀-ͯ]/g, "") // remove acentos (marcas de combinação) após NFD
    .replace(/[^a-zA-Z0-9]+/g, "-")
    .replace(/(^-|-$)/g, "");
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
  const versaoParaContexto = new Map<
    string,
    { entidade: string; periodo: string; tipoTaxonomia: string | null; nomeArquivo: string }
  >();
  for (const doc of documentos) {
    for (const versao of doc.documento_versao ?? []) {
      versaoParaContexto.set(versao.id, {
        entidade: doc.entidade?.razao_social ?? "(sem entidade)",
        periodo: doc.periodo ? `${doc.periodo.tipo} ${doc.periodo.referencia}` : "(sem período)",
        tipoTaxonomia: doc.tipo_taxonomia,
        nomeArquivo: versao.nome_original ?? "(sem nome)",
      });
    }
  }

  const linhasPorAba = new Map<string, LinhaExport[]>();
  for (const campo of campos) {
    const ctx = versaoParaContexto.get(campo.documento_versao_id);
    if (!ctx) continue;
    const tax = ctx.tipoTaxonomia ? taxonomiaPorCodigo.get(ctx.tipoTaxonomia) : undefined;
    const aba = (ctx.tipoTaxonomia && ABA_POR_TIPO[ctx.tipoTaxonomia]) || "Outros";
    if (!linhasPorAba.has(aba)) linhasPorAba.set(aba, []);
    linhasPorAba.get(aba)!.push({
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
        "antes de entrar no modelo.",
    ],
  ]);
  resumo.getRow(1).font = { bold: true };
  resumo.getCell("B9").alignment = { wrapText: true };

  const PENDENTE_FILL: ExcelJS.Fill = { type: "pattern", pattern: "solid", fgColor: { argb: "FFFFF3CD" } };
  const HEADER_FILL: ExcelJS.Fill = { type: "pattern", pattern: "solid", fgColor: { argb: "FFE5E7EB" } };
  const COLUNAS = [
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

  for (const aba of ORDEM_ABAS) {
    const linhas = linhasPorAba.get(aba);
    if (!linhas || linhas.length === 0) continue;

    // Consolida entidade × período (spec): agrupa por entidade, depois período.
    linhas.sort((a, b) =>
      a.entidade.localeCompare(b.entidade) || a.periodo.localeCompare(b.periodo) || a.secao.localeCompare(b.secao),
    );

    const sheet = workbook.addWorksheet(aba, { views: [{ state: "frozen", ySplit: 1 }] });
    sheet.columns = COLUNAS;
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
        statusAceite:
          linha.statusAceite === "aceito" ? "ACEITO" : linha.statusAceite === "com_ressalva" ? "COM RESSALVA" : "PENDENTE",
        aceitoPor: linha.aceitoPor ?? "",
        aceitoEm: linha.aceitoEm ? new Date(linha.aceitoEm).toLocaleString("pt-BR") : "",
        arquivoOrigem: linha.arquivoOrigem,
        versaoTaxonomia: linha.versaoTaxonomia ?? "",
      });
      if (/total/i.test(linha.chave)) row.font = { bold: true };
      if (linha.statusAceite !== "aceito") {
        row.eachCell((cell) => {
          cell.fill = PENDENTE_FILL;
        });
        row.font = { ...row.font, italic: true };
      }
    }
  }

  return workbook;
}
