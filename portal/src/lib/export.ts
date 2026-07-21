import ExcelJS from "exceljs";
import type { CampoExtraido } from "./types";
import {
  classificarConta,
  secoesDe,
  ancorasDe,
  agruparPorChaveNormalizada,
  ESTRUTURA_POR_TIPO,
  type EstruturaDemonstracao,
} from "./statement-templates";

// Modo B do output (f0/07_output_spec.md): export sob demanda. Princípio
// inegociável da spec: "Dado sem aceite não é entregue como fato — no
// máximo aparece como sugestão pendente de revisão, visualmente distinta."
// Por isso TODAS as linhas aparecem (aceitas e pendentes), mas com
// status/estilo bem distintos — nada aqui vira fato silenciosamente.
//
// Balanço/Balancete/DRE/Fluxo de Caixa/Combinado saem CLASSIFICADOS por
// SEÇÃO (statement-templates.ts) — não por um template de ~15 nomes de
// conta fixos. Cada empresa nomeia as contas do jeito dela; o que é
// universal é a SEÇÃO (Ativo Circulante, Despesas Operacionais, Atividades
// de Investimento, etc.). Cada conta aparece com o rótulo ORIGINAL da
// empresa, dentro da seção certa — nada é forçado a um nome canônico, e
// nada some: o que não é classificável com segurança cai num bloco
// explícito "Contas Não Classificadas". Faturamento/Dívida/Fluxo Projetado
// continuam em listagem simples (já são, por natureza, uma série/tabela).
// O export NÃO modela nem projeta (fora do escopo, mesma spec) — nenhum
// subtotal/total é calculado por soma; só aparece se o próprio documento
// já trouxer aquela linha extraída.
//
// Função pura (sem Supabase/Next.js) para ser testável isoladamente — a rota
// (`app/casos/[id]/export/route.ts`) só busca os dados e chama esta função.

// tipo_taxonomia → nome da aba (ordem de prioridade travada em f0/07;
// Balancete/Combinado entram na mesma família estrutural do Balanço).
export const ABA_POR_TIPO: Record<string, string> = {
  BALANCO: "Balanço",
  DRE: "DRE",
  FLUXO_CAIXA: "Fluxo de Caixa",
  COMBINADO: "Combinado",
  BALANCETE: "Balancete",
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
  "Balancete",
  "Faturamento",
  "Dívida",
  "Fluxo Projetado",
  "Outros",
];
const ESTRUTURA_POR_ABA = new Map<string, EstruturaDemonstracao>(
  Object.entries(ESTRUTURA_POR_TIPO).map(([tipo, estrutura]) => [ABA_POR_TIPO[tipo], estrutura]),
);

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

// Em empate (mais de um campo casando no mesmo lugar), prefere maior
// confiança e rótulo mais curto (mais específico) — mesmo critério de
// `fn_valor_conceito` (db/migrations/0009).
function melhorCampo(campos: CampoExtraido[]): CampoExtraido {
  return [...campos].sort((a, b) => (b.confianca ?? 0) - (a.confianca ?? 0) || a.chave.length - b.chave.length)[0];
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
const NAO_CLASSIFICADO_FILL: ExcelJS.Fill = { type: "pattern", pattern: "solid", fgColor: { argb: "FFF3E8FF" } };
const THIN_TOP_BORDER: Partial<ExcelJS.Borders> = { top: { style: "thin" } };
const DOUBLE_TOP_BORDER: Partial<ExcelJS.Borders> = { top: { style: "double" } };

interface GrupoConta {
  label: string;
  porColuna: Map<string, CampoExtraido[]>; // colKey → campos casados ali (melhorCampo escolhe 1)
}

function novoGrupo(label: string): GrupoConta {
  return { label, porColuna: new Map() };
}

function adicionarAoGrupo(grupo: GrupoConta, colKey: string, campo: CampoExtraido) {
  if (!grupo.porColuna.has(colKey)) grupo.porColuna.set(colKey, []);
  grupo.porColuna.get(colKey)!.push(campo);
}

// Escreve uma linha de conta (rótulo + valor por coluna + nota de
// proveniência + estilo pendente/total) numa `sheet` já criada.
function escreverLinhaConta(
  sheet: ExcelJS.Worksheet,
  rowIndex: number,
  label: string,
  nivel: number,
  colunas: Coluna[],
  grupo: GrupoConta,
  opts: { negrito?: boolean; borda?: "simples" | "dupla" },
  contextoPorVersao: Map<string, ContextoVersao>,
  taxonomiaPorCodigo: Map<string, { label: string; versao: number }>,
) {
  const row = sheet.getRow(rowIndex);
  row.getCell(1).value = label;
  row.getCell(1).alignment = { indent: nivel };
  if (opts.negrito) row.font = { bold: true };

  colunas.forEach((col, i) => {
    const cell = row.getCell(i + 2);
    if (opts.borda === "simples") cell.border = THIN_TOP_BORDER;
    if (opts.borda === "dupla") cell.border = DOUBLE_TOP_BORDER;
    const candidatos = grupo.porColuna.get(col.key);
    if (!candidatos || candidatos.length === 0) return;
    const campo = melhorCampo(candidatos);
    cell.value = campo.valor_num ?? campo.valor_texto ?? null;
    if (typeof cell.value === "number") cell.numFmt = VALOR_NUM_FMT;
    if (campo.status_aceite !== "aceito") {
      cell.fill = PENDENTE_FILL;
      cell.font = { ...(row.font ?? {}), italic: true };
    }
    const ctx = contextoPorVersao.get(campo.documento_versao_id);
    if (ctx) {
      const tax = ctx.tipoTaxonomia ? taxonomiaPorCodigo.get(ctx.tipoTaxonomia) : undefined;
      cell.note = notaProveniencia(campo, ctx, tax?.versao ?? null);
    }
  });
}

// ----- Aba classificada por seção (Balanço/Balancete/DRE/Fluxo/Combinado) --
function construirAbaClassificada(
  workbook: ExcelJS.Workbook,
  nomeAba: string,
  estrutura: EstruturaDemonstracao,
  colunas: Coluna[],
  camposDaAba: Array<{ campo: CampoExtraido; colKey: string }>,
  contextoPorVersao: Map<string, ContextoVersao>,
  taxonomiaPorCodigo: Map<string, { label: string; versao: number }>,
) {
  const sheet = workbook.addWorksheet(nomeAba, { views: [{ state: "frozen", xSplit: 1, ySplit: 1 }] });
  sheet.getColumn(1).width = 44;
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

  const secoes = secoesDe(estrutura);
  const ancoras = ancorasDe(estrutura);

  // Classifica CADA campo extraído: ou entra numa seção (agrupado pela
  // chave normalizada — mesma conta com a mesma redação alinha na mesma
  // linha entre períodos/entidades), ou é uma âncora (subtotal/total já
  // extraído do próprio documento), ou fica em "não classificado".
  const contasPorSecao = new Map<string, Map<string, GrupoConta>>();
  secoes.forEach((s) => contasPorSecao.set(s.key, new Map()));
  const valoresPorAncora = new Map<string, GrupoConta>();
  ancoras.forEach((a) => valoresPorAncora.set(a.key, novoGrupo(a.label)));
  const naoClassificados = new Map<string, GrupoConta>();

  for (const { campo, colKey } of camposDaAba) {
    if (campo.valor_num == null && campo.valor_texto == null) continue;
    const { secaoKey, ancoraKey } = classificarConta(estrutura, campo.secao, campo.chave);
    if (ancoraKey) {
      adicionarAoGrupo(valoresPorAncora.get(ancoraKey)!, colKey, campo);
    } else if (secaoKey) {
      const mapaSecao = contasPorSecao.get(secaoKey)!;
      const chaveNorm = campo.chave.trim().toLowerCase();
      if (!mapaSecao.has(chaveNorm)) mapaSecao.set(chaveNorm, novoGrupo(campo.chave));
      adicionarAoGrupo(mapaSecao.get(chaveNorm)!, colKey, campo);
    } else {
      const chaveNorm = campo.chave.trim().toLowerCase();
      if (!naoClassificados.has(chaveNorm)) naoClassificados.set(chaveNorm, novoGrupo(campo.chave));
      adicionarAoGrupo(naoClassificados.get(chaveNorm)!, colKey, campo);
    }
  }

  let rowIndex = 2;
  const escrever = (label: string, nivel: number, grupo: GrupoConta, opts: { negrito?: boolean; borda?: "simples" | "dupla" } = {}) => {
    escreverLinhaConta(sheet, rowIndex++, label, nivel, colunas, grupo, opts, contextoPorVersao, taxonomiaPorCodigo);
  };
  const escreverHeader = (label: string, nivel: number) => {
    const row = sheet.getRow(rowIndex++);
    row.getCell(1).value = label;
    row.getCell(1).alignment = { indent: nivel };
    row.font = { bold: true };
    row.fill = SECAO_FILL;
  };

  if (estrutura === "balanco") {
    // Layout hierárquico: grupo (ATIVO / PASSIVO E PL) → seções → contas →
    // subtotal da seção → total do grupo.
    const grupos = [...new Set(secoes.map((s) => s.grupo!))];
    for (const grupoNome of grupos) {
      escreverHeader(grupoNome, 0);
      const secoesDoGrupo = secoes.filter((s) => s.grupo === grupoNome);
      for (const secao of secoesDoGrupo) {
        escreverHeader(secao.label, 1);
        const contas = [...contasPorSecao.get(secao.key)!.values()];
        for (const conta of contas) escrever(conta.label, 2, conta);
        const ancoraSecao = ancoras.find((a) => "aposSecao" in a && a.aposSecao === secao.key);
        if (ancoraSecao) escrever(ancoraSecao.label, 1, valoresPorAncora.get(ancoraSecao.key)!, { negrito: true, borda: "simples" });
      }
      const ancoraGrupo = ancoras.find((a) => "grupo" in a && a.grupo === grupoNome);
      if (ancoraGrupo) escrever(ancoraGrupo.label, 0, valoresPorAncora.get(ancoraGrupo.key)!, { negrito: true, borda: "dupla" });
    }
  } else {
    // Layout sequencial (DRE / Fluxo de Caixa): seção → contas → âncora
    // (quando a âncora não pertence a nenhuma seção específica — ex.: saldo
    // inicial/final do Fluxo — ela é escrita direto, na ordem definida).
    const aposSecaoUsadas = new Set(ancoras.filter((a) => "aposSecao" in a).map((a) => (a as { aposSecao: string }).aposSecao));
    for (const secao of secoes) {
      escreverHeader(secao.label, 0);
      const contas = [...contasPorSecao.get(secao.key)!.values()];
      for (const conta of contas) escrever(conta.label, 1, conta);
      const ancoraSecao = ancoras.find((a) => "aposSecao" in a && (a as { aposSecao: string }).aposSecao === secao.key);
      if (ancoraSecao) escrever(ancoraSecao.label, 0, valoresPorAncora.get(ancoraSecao.key)!, { negrito: true, borda: "simples" });
    }
    // Âncoras que não seguem nenhuma seção específica (ex.: variação líquida
    // de caixa, saldo inicial/final) — na ordem em que aparecem no template.
    for (const ancora of ancoras) {
      if ("aposSecao" in ancora && aposSecaoUsadas.has((ancora as { aposSecao: string }).aposSecao)) continue;
      escrever(ancora.label, 0, valoresPorAncora.get(ancora.key)!, { negrito: true, borda: "simples" });
    }
  }

  // ----- Contas Não Classificadas: nada desaparece silenciosamente. -----
  if (naoClassificados.size > 0) {
    rowIndex++; // linha em branco
    const tituloRow = sheet.getRow(rowIndex++);
    tituloRow.getCell(1).value = "Contas Não Classificadas (revisar manualmente)";
    tituloRow.font = { bold: true, italic: true };
    tituloRow.fill = NAO_CLASSIFICADO_FILL;
    for (const conta of naoClassificados.values()) escrever(conta.label, 1, conta);
  }
}

// ----- Aba simples (Faturamento/Dívida/Fluxo Projetado/Outros) -------------
// Já são, por natureza, uma série/tabela — não uma demonstração de blocos.
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
  const camposPorAba = new Map<string, Array<{ campo: CampoExtraido; colKey: string }>>();
  const linhasSimplesPorAba = new Map<string, LinhaSimples[]>();

  for (const campo of campos) {
    const ctx = contextoPorVersao.get(campo.documento_versao_id);
    if (!ctx) continue;
    const aba = (ctx.tipoTaxonomia && ABA_POR_TIPO[ctx.tipoTaxonomia]) || "Outros";
    const colKey = `${ctx.entidade} ${ctx.periodo}`;
    const estrutura = ESTRUTURA_POR_ABA.get(aba);

    if (estrutura) {
      if (!colunasPorAba.has(aba)) colunasPorAba.set(aba, new Map());
      colunasPorAba.get(aba)!.set(colKey, { key: colKey, entidade: ctx.entidade, periodo: ctx.periodo });
      if (!camposPorAba.has(aba)) camposPorAba.set(aba, []);
      camposPorAba.get(aba)!.push({ campo, colKey });
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
        "antes de entrar no modelo. Balanço/Balancete/DRE/Fluxo de Caixa/Combinado classificam " +
        "cada conta extraída por SEÇÃO (Ativo Circulante, Despesas Operacionais, etc.), mantendo " +
        "o rótulo original de cada empresa — nenhum subtotal é calculado por nós, só aparece se o " +
        "próprio documento já trouxer aquela linha. Contas que não foi possível classificar com " +
        "segurança aparecem em \"Contas Não Classificadas\", ao final de cada aba — revisar manualmente.",
    ],
  ]);
  resumo.getRow(1).font = { bold: true };
  resumo.getCell("B9").alignment = { wrapText: true };

  for (const aba of ORDEM_ABAS) {
    const estrutura = ESTRUTURA_POR_ABA.get(aba);
    if (estrutura) {
      const colunas = [...(colunasPorAba.get(aba)?.values() ?? [])].sort(
        (a, b) => a.entidade.localeCompare(b.entidade) || a.periodo.localeCompare(b.periodo),
      );
      if (colunas.length === 0) continue;
      construirAbaClassificada(
        workbook,
        aba,
        estrutura,
        colunas,
        camposPorAba.get(aba) ?? [],
        contextoPorVersao,
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

// Reexportado para eventuais consumidores que só precisem agrupar por conta
// (ex.: uma futura tela de revisão por seção no portal).
export { agruparPorChaveNormalizada };
