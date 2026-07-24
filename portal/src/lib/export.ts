import ExcelJS from "exceljs";
import JSZip from "jszip";
import type { CampoExtraido } from "./types";
import {
  classificarConta,
  classificarDemonstracao,
  secoesDe,
  ancorasDe,
  agruparPorChaveNormalizada,
  ESTRUTURA_POR_TIPO,
  BALANCO_OUTLINE,
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

// Padroniza o período (periodo.tipo + periodo.referencia — convenções livres
// vindas da extração: "12M25", "1T25", "L24M", "23,24,25", datas ISO/BR,
// texto livre) num modelo pronto de "períodos e intervalos", sem jargão
// técnico ("multi", "data-base") nem convenções cifradas na tela. Pedido do
// dono (sessão 7 cont.¹⁵): "simplificar e deixar mais objetiva a escrita de
// período". Nunca lança — o que não reconhece, devolve como veio (nunca pior
// que o comportamento anterior).
function anoDe4Digitos(anoTexto: string): string {
  if (anoTexto.length === 4) return anoTexto;
  const n = Number(anoTexto);
  return String(n <= 79 ? 2000 + n : 1900 + n);
}

function formatarDataBR(ref: string): string {
  const iso = ref.match(/^(\d{4})-(\d{2})-(\d{2})$/);
  return iso ? `${iso[3]}/${iso[2]}/${iso[1]}` : ref;
}

export function formatarPeriodo(tipo: string | null, referencia: string | null): string {
  const ref = (referencia ?? "").trim();
  const t = (tipo ?? "").trim();
  if (!ref) return "—";

  const ultimosMeses = ref.match(/^L(\d+)M$/i);
  if (ultimosMeses) return `Últimos ${ultimosMeses[1]} meses`;

  const anoFiscal = ref.match(/^(\d+)M(\d{2,4})$/i);
  if (anoFiscal) {
    const nMeses = Number(anoFiscal[1]);
    const ano = anoDe4Digitos(anoFiscal[2]);
    return nMeses === 12 ? ano : `${nMeses} meses/${ano}`;
  }

  const trimestre = ref.match(/^(\d)T(\d{2,4})$/i);
  if (trimestre) return `${trimestre[1]}º Tri/${anoDe4Digitos(trimestre[2])}`;

  if (t === "data-base") return formatarDataBR(ref);

  if (t === "multi" || /,/.test(ref)) {
    const anos = ref
      .split(",")
      .map((p) => p.trim())
      .filter(Boolean)
      .map((p) => (/^\d{1,4}$/.test(p) ? anoDe4Digitos(p) : p));
    if (anos.length === 2) return `${anos[0]}–${anos[1]}`;
    if (anos.length > 2) return anos.join(", ");
  }

  if (/^\d{4}$/.test(ref)) return ref;

  return ref; // texto livre já descritivo (ex.: "Jan/2024 a Dez/2025") — mantém como veio
}

// tipo_taxonomia → nome da aba (ordem de prioridade travada em f0/07;
// Balancete/Combinado entram na mesma família estrutural do Balanço).
//
// MUTUOS e FAT_INTRAGRUPO são categoria "Intragrupo" na própria taxonomia
// (db/migrations/0002) — mútuo entre empresas do grupo não é DÍVIDA externa
// (banco/financiamento, como MAPA_DIVIDA/CONTRATO_DIVIDA); misturar as duas
// na mesma aba "Dívida" era uma classificação sem sentido contábil (achado em
// produção, sessão 7 cont.¹⁴). CONTRATO_SOCIAL (Societário/Legal) também
// ganhou aba própria em vez de cair no genérico "Outros" junto com dado
// tabular não relacionado.
export const ABA_POR_TIPO: Record<string, string> = {
  BALANCO: "Balanço",
  DRE: "DRE",
  FLUXO_CAIXA: "Fluxo de Caixa",
  COMBINADO: "Combinado",
  BALANCETE: "Balancete",
  FATURAMENTO_24M: "Faturamento",
  MAPA_DIVIDA: "Dívida",
  CONTRATO_DIVIDA: "Dívida",
  MUTUOS: "Intragrupo",
  FAT_INTRAGRUPO: "Intragrupo",
  CONTRATO_SOCIAL: "Societário",
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
  "Intragrupo",
  "Societário",
  "Fluxo Projetado",
  "Outros",
];
const ESTRUTURA_POR_ABA = new Map<string, EstruturaDemonstracao>(
  Object.entries(ESTRUTURA_POR_TIPO).map(([tipo, estrutura]) => [ABA_POR_TIPO[tipo], estrutura]),
);

// tipo_taxonomia (código interno da classificação) → rótulo natural pra
// tela (dashboard, planilha do documento, fila de revisão). Pedido do dono
// (sessão 7 cont.¹⁶): nada de código cru ("FATURAMENTO_24M") na interface —
// escrita natural, do mesmo jeito que um analista falaria. Distinto de
// ABA_POR_TIPO (que agrupa MUTUOS/FAT_INTRAGRUPO numa aba só "Intragrupo" e
// MAPA_DIVIDA/CONTRATO_DIVIDA em "Dívida") — aqui cada tipo tem o próprio
// rótulo, mesmo que dois deles caiam na mesma aba do export.
const TIPO_TAXONOMIA_LABEL: Record<string, string> = {
  BALANCO: "Balanço",
  DRE: "DRE",
  FLUXO_CAIXA: "Fluxo de Caixa",
  COMBINADO: "Demonstrações Combinadas",
  BALANCETE: "Balancete",
  FATURAMENTO_24M: "Faturamento em 24 meses",
  MAPA_DIVIDA: "Mapa da Dívida",
  CONTRATO_DIVIDA: "Contrato de Dívida",
  MUTUOS: "Mútuos",
  FAT_INTRAGRUPO: "Faturamento Intragrupo",
  CONTRATO_SOCIAL: "Contrato Social",
  FLUXO_PROJETADO: "Fluxo Projetado",
};

// Tipos ainda sem rótulo explícito (fora do Kit Básico + Variáveis já
// mapeados acima) caem num fallback genérico — "EXTRATO_BANCARIO" vira
// "Extrato Bancario" em vez do código cru — nunca pior que antes, e já seguem
// a mesma linha de escrita natural quando entrar um tipo novo.
export function formatarTipoTaxonomia(codigo: string | null): string {
  if (!codigo) return "Não classificado";
  const label = TIPO_TAXONOMIA_LABEL[codigo];
  if (label) return label;
  return codigo
    .toLowerCase()
    .split("_")
    .map((palavra) => palavra.charAt(0).toUpperCase() + palavra.slice(1))
    .join(" ");
}

// Família da demonstração → aba PADRÃO para onde vai uma linha que pertence a
// essa família mas foi extraída de um documento de OUTRO tipo (um PDF de
// "Demonstrações Contábeis" completo traz Balanço + DRE + Fluxo de Caixa
// juntos). Balancete/Combinado (também família "balanco") mantêm as próprias
// abas quando o documento é desse tipo — só o que "vaza" de um documento
// composto para uma família diferente é redirecionado para estas abas.
const ABA_PADRAO_POR_ESTRUTURA: Record<EstruturaDemonstracao, string> = {
  balanco: "Balanço",
  dre: "DRE",
  fluxo_caixa: "Fluxo de Caixa",
};

export interface DocumentoParaExport {
  id: string;
  tipo_taxonomia: string | null;
  entidade: { razao_social: string } | null;
  periodo: { tipo: string; referencia: string } | null;
  documento_versao: Array<{ id: string; nome_original: string | null }> | null;
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

// Fonte compacta (8pt) + caixa de comentário ampliada (ver `ampliarNotas`,
// pós-processamento do .xlsx — a API do ExcelJS não expõe tamanho de caixa de
// nota, só o conteúdo/fonte) — as anotações tinham texto cortado ao abrir
// (pedido do dono, sessão 7 cont.¹⁵).
const NOTA_FONT: Partial<ExcelJS.Font> = { size: 8, name: "Calibri" };
function comoNota(texto: string): ExcelJS.Comment {
  return { texts: [{ text: texto, font: NOTA_FONT }] };
}

function notaProveniencia(campo: CampoExtraido, ctx: ContextoVersao) {
  const linhas = [
    `Rótulo original: "${campo.chave}"`,
    campo.entidade_coluna ? `Coluna de origem no documento: ${campo.entidade_coluna}` : null,
    `Arquivo: ${ctx.nomeArquivo}`,
    campo.origem_pagina != null ? `Página: ${campo.origem_pagina}` : null,
    campo.confianca != null ? `Confiança da extração: ${Math.round(campo.confianca * 100)}%` : null,
    `Status: ${formatarStatus(campo.status_aceite)}`,
    campo.status_aceite === "aceito" && campo.aceito_por ? `Aceito por: ${campo.aceito_por}` : null,
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
// proveniência + estilo pendente/total) numa `sheet` já criada. `valuePos[i]`
// = posição (número da coluna Excel) onde a coluna de valor `i` é escrita — as
// colunas de valor NÃO são mais contíguas (intercalam AV%/Δ%), então tudo é
// endereçado pelo plano de colunas, não por `i + 2`.
function escreverLinhaConta(
  sheet: ExcelJS.Worksheet,
  rowIndex: number,
  label: string,
  nivel: number,
  colunas: Coluna[],
  valuePos: number[],
  grupo: GrupoConta,
  opts: { negrito?: boolean; borda?: "simples" | "dupla" },
  contextoPorVersao: Map<string, ContextoVersao>,
) {
  const row = sheet.getRow(rowIndex);
  row.getCell(1).value = label;
  row.getCell(1).alignment = { indent: nivel };
  if (opts.negrito) row.font = { bold: true };

  colunas.forEach((col, i) => {
    const cell = row.getCell(valuePos[i]);
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
      cell.note = comoNota(notaProveniencia(campo, ctx));
    }
  });
}

const DIVERGENCIA_FILL: ExcelJS.Fill = { type: "pattern", pattern: "solid", fgColor: { argb: "FFFCE4E4" } };
const MARGEM_FONT: Partial<ExcelJS.Font> = { italic: true, size: 9, color: { argb: "FF2563EB" } };
// Âncora da DRE → rótulo da linha de margem (% da Receita Líquida).
const MARGEM_LABEL: Record<string, string> = {
  lucro_bruto: "Margem Bruta %",
  resultado_operacional: "Margem Operacional %",
  lucro_liquido: "Margem Líquida %",
};

// ----- Camada analítica (f0/08): análise vertical / horizontal / indicadores.
// Colunas AV% (análise vertical, common-size) e Δ% (análise horizontal, entre
// períodos comparáveis da mesma entidade) são FÓRMULAS transparentes sobre o
// dado já extraído — não projetam nem inventam número. Estilo discreto
// (cinza-azulado, menor) para não competir com os valores.
const ANALISE_FONT: Partial<ExcelJS.Font> = { italic: true, size: 9, color: { argb: "FF64748B" } };
const ANALISE_HEADER_FILL: ExcelJS.Fill = { type: "pattern", pattern: "solid", fgColor: { argb: "FFEEF2FF" } };
const AV_FMT = "0.0%";
const DELTA_FMT = "+0.0%;-0.0%;0.0%";
const RATIO_FMT = "0.00"; // índices "x vezes" (liquidez, participação)
const PCT_FMT = "0.0%"; // índices em % (endividamento, composição, imobilização)
const INDICADOR_TITULO_FILL: ExcelJS.Fill = { type: "pattern", pattern: "solid", fgColor: { argb: "FFE0E7FF" } };
const INDICADOR_LABEL_FONT: Partial<ExcelJS.Font> = { size: 10, color: { argb: "FF1E293B" } };

// Plano de colunas do relatório: as colunas de VALOR (entidade×período) não são
// mais contíguas — cada uma pode ser seguida de sua AV% e, quando comparável ao
// período anterior da MESMA entidade, de uma Δ%. Centraliza o mapeamento
// "índice da coluna de valor → coluna Excel real" para que todas as fórmulas
// (subtotais, margens, indicadores) refiram a célula certa.
interface PlanoColunas {
  valuePos: number[]; // i (coluna de valor) → nº da coluna Excel
  avPos: Array<number | null>; // i → coluna Excel da AV% (null quando não se aplica, ex.: Fluxo)
  deltas: Array<{ pos: number; atual: number; anterior: number }>; // colunas Δ%
  ultimaColuna: number;
}

function planejarColunas(colunas: Coluna[], comAV: boolean): PlanoColunas {
  const valuePos: number[] = [];
  const avPos: Array<number | null> = [];
  const deltas: Array<{ pos: number; atual: number; anterior: number }> = [];
  let col = 2; // coluna 1 = rótulo da conta
  colunas.forEach((coluna, i) => {
    valuePos[i] = col++;
    avPos[i] = comAV ? col++ : null;
    // Δ% só entre períodos DIFERENTES da MESMA entidade, adjacentes na ordenação
    // (as colunas vêm ordenadas por entidade e depois período).
    if (i > 0 && colunas[i - 1].entidade === coluna.entidade && colunas[i - 1].periodo !== coluna.periodo) {
      deltas.push({ pos: col++, atual: i, anterior: i - 1 });
    }
  });
  return { valuePos, avPos, deltas, ultimaColuna: col - 1 };
}

// valor_num "melhor" de um grupo de conta numa coluna (para conferir a soma em
// JS contra o total que o documento trouxe — a célula em si leva a FÓRMULA).
function valorNumDoGrupo(grupo: GrupoConta, colKey: string): number | null {
  const c = grupo.porColuna.get(colKey);
  if (!c || c.length === 0) return null;
  const campo = melhorCampo(c);
  return typeof campo.valor_num === "number" ? campo.valor_num : null;
}

// ----- Aba classificada por seção (Balanço/Balancete/DRE/Fluxo/Combinado) --
// Totais/subtotais NÃO são valores estáticos: são FÓRMULAS Excel (=SUM(...)),
// transparentes e recalculáveis, colocadas NO cabeçalho de cada seção/grupo
// (f0/07 evoluído nesta sessão — pedido do dono). O total que o PRÓPRIO
// documento trouxe (quando existe) aparece numa linha de conferência logo
// abaixo; se a soma calculada divergir do informado, ambos são sinalizados
// (anti-ancoragem: nada que o documento disse é perdido, e divergência vira
// sinal visível — uma checagem de reconciliação embutida).
function construirAbaClassificada(
  workbook: ExcelJS.Workbook,
  nomeAba: string,
  estrutura: EstruturaDemonstracao,
  colunas: Coluna[],
  camposDaAba: Array<{ campo: CampoExtraido; colKey: string }>,
  contextoPorVersao: Map<string, ContextoVersao>,
) {
  const sheet = workbook.addWorksheet(nomeAba, { views: [{ state: "frozen", xSplit: 1, ySplit: 1 }] });
  // AV% (análise vertical) só faz sentido onde há uma base natural (Ativo Total
  // no Balanço; Receita Líquida na DRE). No Fluxo de Caixa não há base — só Δ%.
  const comAV = estrutura !== "fluxo_caixa";
  const plano = planejarColunas(colunas, comAV);
  const colLetra = (i: number) => sheet.getColumn(plano.valuePos[i]).letter;

  sheet.getColumn(1).width = 46;
  plano.valuePos.forEach((pos) => {
    sheet.getColumn(pos).width = 18;
  });
  plano.avPos.forEach((pos) => {
    if (pos != null) sheet.getColumn(pos).width = 8;
  });
  plano.deltas.forEach((d) => {
    sheet.getColumn(d.pos).width = 12;
  });

  const headerRow = sheet.getRow(1);
  headerRow.getCell(1).value = "Conta";
  colunas.forEach((col, i) => {
    const cell = headerRow.getCell(plano.valuePos[i]);
    cell.value = `${col.entidade} — ${col.periodo}`;
    cell.fill = HEADER_FILL;
    const av = plano.avPos[i];
    if (av != null) {
      const avCell = headerRow.getCell(av);
      avCell.value = "AV%";
      avCell.fill = ANALISE_HEADER_FILL;
    }
  });
  plano.deltas.forEach((d) => {
    const cell = headerRow.getCell(d.pos);
    cell.value = `Δ% ${colunas[d.anterior].periodo}→${colunas[d.atual].periodo}`;
    cell.fill = ANALISE_HEADER_FILL;
  });
  headerRow.getCell(1).fill = HEADER_FILL;
  headerRow.font = { bold: true };
  headerRow.alignment = { wrapText: true, vertical: "middle" };

  // Classifica cada campo: conta numa seção (bucket), âncora (total que o doc
  // trouxe, por chave de nó), ou não classificado.
  const contasPorSecao = new Map<string, Map<string, GrupoConta>>();
  const valoresPorAncora = new Map<string, GrupoConta>();
  const naoClassificados = new Map<string, GrupoConta>();
  const bucket = (mapa: Map<string, GrupoConta>, campo: CampoExtraido, colKey: string) => {
    const chaveNorm = campo.chave.trim().toLowerCase();
    if (!mapa.has(chaveNorm)) mapa.set(chaveNorm, novoGrupo(campo.chave));
    adicionarAoGrupo(mapa.get(chaveNorm)!, colKey, campo);
  };
  for (const { campo, colKey } of camposDaAba) {
    if (campo.valor_num == null && campo.valor_texto == null) continue;
    const { secaoKey, ancoraKey } = classificarConta(estrutura, campo.secao, campo.chave, campo.secao_canonica);
    if (ancoraKey) {
      if (!valoresPorAncora.has(ancoraKey)) valoresPorAncora.set(ancoraKey, novoGrupo(campo.chave));
      adicionarAoGrupo(valoresPorAncora.get(ancoraKey)!, colKey, campo);
    } else if (secaoKey) {
      if (!contasPorSecao.has(secaoKey)) contasPorSecao.set(secaoKey, new Map());
      bucket(contasPorSecao.get(secaoKey)!, campo, colKey);
    } else {
      bucket(naoClassificados, campo, colKey);
    }
  }

  let rowIndex = 2;
  // Linhas monetárias elegíveis a AV%/Δ% (contas + subtotais + âncoras);
  // exclui cabeçalhos de seção sem valor, linhas de conferência e margens.
  const linhasValor = new Set<number>();
  // Balanço: nó da estrutura → linha do seu subtotal (para os indicadores).
  const noRow = new Map<string, number>();
  let baseTotalRow: number | null = null; // base da AV% (Ativo Total / Receita Líquida)

  const escrever = (label: string, nivel: number, grupo: GrupoConta, opts: { negrito?: boolean; borda?: "simples" | "dupla" } = {}) => {
    const r = rowIndex++;
    escreverLinhaConta(sheet, r, label, nivel, colunas, plano.valuePos, grupo, opts, contextoPorVersao);
    linhasValor.add(r);
    return r;
  };

  // Linha de conferência: o total que o DOCUMENTO trouxe (extraído), logo
  // abaixo do cabeçalho com a fórmula. Se divergir do subtotal calculado,
  // pinta ambas as células e anota o motivo (checagem de reconciliação).
  const escreverConferenciaExtraido = (nivel: number, ancoraKey: string, cabecalhoIdx: number, subtotalNum: Map<string, number>) => {
    const grupo = valoresPorAncora.get(ancoraKey);
    if (!grupo) return;
    const idx = rowIndex++;
    const row = sheet.getRow(idx);
    row.getCell(1).value = "↳ total informado no documento";
    row.getCell(1).alignment = { indent: nivel + 1 };
    row.getCell(1).font = { italic: true, size: 9, color: { argb: "FF6B7280" } };
    colunas.forEach((col, i) => {
      const cell = row.getCell(plano.valuePos[i]);
      const vExtraido = valorNumDoGrupo(grupo, col.key);
      if (vExtraido == null) return;
      cell.value = vExtraido;
      cell.numFmt = VALOR_NUM_FMT;
      cell.font = { italic: true, size: 9, color: { argb: "FF6B7280" } };
      const vCalc = subtotalNum.get(col.key);
      if (vCalc != null && Math.abs(vCalc - vExtraido) > Math.max(0.01, Math.abs(vExtraido) * 0.005)) {
        cell.fill = DIVERGENCIA_FILL;
        cell.note = comoNota(
          `Divergência: soma calculada = ${vCalc.toLocaleString("pt-BR", { minimumFractionDigits: 2, maximumFractionDigits: 2 })}, `
          + `informado no documento = ${vExtraido.toLocaleString("pt-BR", { minimumFractionDigits: 2, maximumFractionDigits: 2 })}. `
          + `Conferir a extração contra o arquivo original.`,
        );
        // sinaliza também a célula da fórmula (cabeçalho)
        sheet.getRow(cabecalhoIdx).getCell(plano.valuePos[i]).fill = DIVERGENCIA_FILL;
      }
    });
  };

  if (estrutura === "balanco") {
    const outline = new Map(BALANCO_OUTLINE.map((n) => [n.key, n]));
    // Emite um nó (recursivo): cabeçalho com fórmula (soma das contas-folha ou
    // dos subtotais dos filhos), contas indentadas, conferência do extraído.
    // Retorna { idx, subtotalNum } para o pai somar.
    const emitirNo = (chave: string): { idx: number; subtotalNum: Map<string, number> } | null => {
      const no = outline.get(chave)!;
      const fill = no.papel === "subsecao" ? SECAO_FILL : HEADER_FILL;
      const subtotalNum = new Map<string, number>();

      if (no.folha) {
        const contas = [...(contasPorSecao.get(no.key)?.values() ?? [])];
        const temAncora = valoresPorAncora.has(no.key);
        // Subseção CPC vazia (sem contas nem total informado) não é emitida —
        // evita 4 linhas de subgrupo em branco quando a empresa só usa uma.
        if (no.papel === "subsecao" && contas.length === 0 && !temAncora) return null;
        // reserva o cabeçalho; escreve as contas; depois preenche a fórmula.
        const cabIdx = rowIndex++;
        const primeira = rowIndex;
        for (const conta of contas) {
          escrever(conta.label, no.nivel + 1, conta);
          colunas.forEach((col) => {
            const v = valorNumDoGrupo(conta, col.key);
            if (v != null) subtotalNum.set(col.key, (subtotalNum.get(col.key) ?? 0) + v);
          });
        }
        const ultima = rowIndex - 1;
        const temContas = ultima >= primeira;
        const row = sheet.getRow(cabIdx);
        row.getCell(1).value = no.label;
        row.getCell(1).alignment = { indent: no.nivel };
        row.font = { bold: true };
        row.fill = fill;
        colunas.forEach((col, i) => {
          const cell = row.getCell(plano.valuePos[i]);
          cell.font = { bold: true };
          if (temContas) {
            // caso normal: subtotal = soma das contas-folha.
            cell.value = { formula: `SUM(${colLetra(i)}${primeira}:${colLetra(i)}${ultima})` } as ExcelJS.CellFormulaValue;
            cell.numFmt = VALOR_NUM_FMT;
          } else if (temAncora) {
            // seção que o documento trouxe SÓ como total (sem detalhar as
            // contas): não há o que somar — usa o próprio valor informado como
            // o valor da seção, senão ele ficaria órfão e o total do pai sairia
            // errado (era o "Imobilizado" em branco no balanço do dono).
            const v = valorNumDoGrupo(valoresPorAncora.get(no.key)!, col.key);
            if (v != null) {
              cell.value = v;
              cell.numFmt = VALOR_NUM_FMT;
              subtotalNum.set(col.key, v);
            }
          } else {
            // seção padrão sem nenhum dado no documento: 0 explícito (a coluna
            // fica completa, sem célula vazia solta no meio do balanço).
            cell.value = 0;
            cell.numFmt = VALOR_NUM_FMT;
          }
        });
        noRow.set(no.key, cabIdx);
        linhasValor.add(cabIdx);
        // Só mostra a linha de conferência quando REALMENTE há uma soma para
        // conferir contra o informado (senão o cabeçalho já É o informado).
        if (temAncora && temContas) escreverConferenciaExtraido(no.nivel, no.key, cabIdx, subtotalNum);
        return { idx: cabIdx, subtotalNum };
      }

      // nó pai: cabeçalho reservado, emite filhos (pula os vazios), soma os
      // cabeçalhos deles.
      const cabIdx = rowIndex++;
      const filhosIdx: number[] = [];
      for (const filho of no.filhos ?? []) {
        const r = emitirNo(filho);
        if (!r) continue;
        filhosIdx.push(r.idx);
        colunas.forEach((col) => {
          const v = r.subtotalNum.get(col.key);
          if (v != null) subtotalNum.set(col.key, (subtotalNum.get(col.key) ?? 0) + v);
        });
      }
      const row = sheet.getRow(cabIdx);
      row.getCell(1).value = no.label;
      row.getCell(1).alignment = { indent: no.nivel };
      row.font = { bold: true };
      row.fill = fill;
      const dupla = no.papel === "grupo";
      colunas.forEach((col, i) => {
        const cell = row.getCell(plano.valuePos[i]);
        cell.font = { bold: true };
        if (filhosIdx.length) {
          cell.value = { formula: filhosIdx.map((r) => `${colLetra(i)}${r}`).join("+") } as ExcelJS.CellFormulaValue;
          cell.numFmt = VALOR_NUM_FMT;
        }
        if (dupla) cell.border = DOUBLE_TOP_BORDER;
      });
      noRow.set(no.key, cabIdx);
      linhasValor.add(cabIdx);
      if (valoresPorAncora.has(no.key)) escreverConferenciaExtraido(no.nivel, no.key, cabIdx, subtotalNum);
      return { idx: cabIdx, subtotalNum };
    };

    for (const raiz of BALANCO_OUTLINE.filter((n) => n.nivel === 0)) emitirNo(raiz.key);
    baseTotalRow = noRow.get("ATIVO") ?? null;
  } else {
    // Layout sequencial (DRE / Fluxo de Caixa): seção → contas → subtotal
    // (âncora). Subtotal é FÓRMULA: DRE é cascata cumulativa (cada subtotal =
    // soma de TODAS as contas da demonstração até ali — deduções/custos/
    // despesas entram negativos, então a soma corrida dá o resultado); Fluxo
    // é soma da própria seção, com variação/saldo final derivados.
    const secoes = secoesDe(estrutura);
    const ancoras = ancorasDe(estrutura);
    const idxAncora = new Map<string, number>();
    const subtotalAncora = new Map<string, Map<string, number>>();
    let dreAncoraAnteriorIdx: number | null = null; // DRE: célula do subtotal anterior (cascata)
    const dreAcumulado = new Map<string, number>(); // DRE: subtotal numérico corrido

    for (const secao of secoes) {
      const hdr = sheet.getRow(rowIndex++);
      hdr.getCell(1).value = secao.label;
      hdr.getCell(1).alignment = { indent: 0 };
      hdr.font = { bold: true };
      hdr.fill = SECAO_FILL;
      const primeira = rowIndex;
      const contas = [...(contasPorSecao.get(secao.key)?.values() ?? [])];
      const somaSecao = new Map<string, number>();
      for (const conta of contas) {
        escrever(conta.label, 1, conta);
        colunas.forEach((col) => {
          const v = valorNumDoGrupo(conta, col.key);
          if (v != null) somaSecao.set(col.key, (somaSecao.get(col.key) ?? 0) + v);
        });
      }
      const ultima = rowIndex - 1;
      const ancoraSecao = ancoras.find((a) => "aposSecao" in a && (a as { aposSecao: string }).aposSecao === secao.key);
      if (ancoraSecao) {
        const idx = rowIndex++;
        const subtotalNum = new Map<string, number>();
        const row = sheet.getRow(idx);
        row.getCell(1).value = ancoraSecao.label;
        row.getCell(1).font = { bold: true };
        colunas.forEach((col, i) => {
          const cell = row.getCell(plano.valuePos[i]);
          cell.font = { bold: true };
          cell.border = THIN_TOP_BORDER;
          let formula: string | null = null;
          const somaSecaoFormula = ultima >= primeira ? `SUM(${colLetra(i)}${primeira}:${colLetra(i)}${ultima})` : null;
          if (estrutura === "dre") {
            // CASCATA: subtotal = subtotal anterior + soma das contas DESTA
            // seção (deduções/custos/despesas entram negativos). Referencia a
            // célula da âncora anterior — nunca re-soma linhas de subtotal já
            // escritas (evita dupla contagem).
            const prev = dreAncoraAnteriorIdx != null ? `${colLetra(i)}${dreAncoraAnteriorIdx}` : null;
            formula = prev && somaSecaoFormula ? `${prev}+${somaSecaoFormula}` : (prev ?? somaSecaoFormula);
            const acc = (dreAcumulado.get(col.key) ?? 0) + (somaSecao.get(col.key) ?? 0);
            dreAcumulado.set(col.key, acc);
            subtotalNum.set(col.key, acc);
          } else {
            // Fluxo: soma da própria seção
            formula = somaSecaoFormula;
            subtotalNum.set(col.key, somaSecao.get(col.key) ?? 0);
          }
          if (formula) {
            cell.value = { formula } as ExcelJS.CellFormulaValue;
            cell.numFmt = VALOR_NUM_FMT;
          }
        });
        idxAncora.set(ancoraSecao.key, idx);
        subtotalAncora.set(ancoraSecao.key, subtotalNum);
        linhasValor.add(idx);
        if (estrutura === "dre") dreAncoraAnteriorIdx = idx;
        if (valoresPorAncora.has(ancoraSecao.key)) escreverConferenciaExtraido(0, ancoraSecao.key, idx, subtotalNum);

        // Linha analítica de MARGEM (% da Receita Líquida) — estilo FP&A
        // (referência DelendSummary): Margem Bruta / Operacional / Líquida.
        // Fórmula por coluna (IFERROR evita divisão por zero); não projeta
        // nada, só divide dois valores já extraídos. EBITDA fica de fora aqui
        // porque a DRE não traz Depreciação/Amortização como linha isolada
        // (viria das notas/Fluxo) — não inventamos.
        const rlIdx = idxAncora.get("receita_liquida");
        if (estrutura === "dre" && rlIdx && ancoraSecao.key in MARGEM_LABEL) {
          const mIdx = rowIndex++;
          const mrow = sheet.getRow(mIdx);
          mrow.getCell(1).value = MARGEM_LABEL[ancoraSecao.key];
          mrow.getCell(1).alignment = { indent: 1 };
          mrow.getCell(1).font = MARGEM_FONT;
          colunas.forEach((col, i) => {
            const cell = mrow.getCell(plano.valuePos[i]);
            cell.value = { formula: `IFERROR(${colLetra(i)}${idx}/${colLetra(i)}${rlIdx},"")` } as ExcelJS.CellFormulaValue;
            cell.numFmt = "0.0%";
            cell.font = MARGEM_FONT;
          });
        }
      }
    }
    if (estrutura === "dre") baseTotalRow = idxAncora.get("receita_liquida") ?? null;

    // Âncoras "livres" (não presas a uma seção): Fluxo de Caixa —
    // variação líquida = soma dos 3 caixas líquidos; saldo final = saldo
    // inicial + variação; saldo inicial = só o que o documento trouxer.
    for (const ancora of ancoras) {
      if ("aposSecao" in ancora) continue;
      const idx = rowIndex++;
      const row = sheet.getRow(idx);
      row.getCell(1).value = ancora.label;
      row.getCell(1).font = { bold: true };
      const subtotalNum = new Map<string, number>();
      colunas.forEach((col, i) => {
        const cell = row.getCell(plano.valuePos[i]);
        cell.font = { bold: true };
        cell.border = THIN_TOP_BORDER;
        let formula: string | null = null;
        const cel = (k: string) => (idxAncora.has(k) ? `${colLetra(i)}${idxAncora.get(k)}` : null);
        if (ancora.key === "variacao_liquida_caixa") {
          const partes = ["caixa_operacional", "caixa_investimento", "caixa_financiamento"].map(cel).filter(Boolean);
          if (partes.length) formula = partes.join("+");
        } else if (ancora.key === "saldo_final_caixa") {
          const ini = cel("saldo_inicial_caixa");
          const varc = cel("variacao_liquida_caixa");
          if (ini && varc) formula = `${ini}+${varc}`;
        }
        if (formula) {
          cell.value = { formula } as ExcelJS.CellFormulaValue;
          cell.numFmt = VALOR_NUM_FMT;
        } else {
          // saldo inicial (ou sem fórmula possível): usa o valor extraído
          const grupo = valoresPorAncora.get(ancora.key);
          const v = grupo ? valorNumDoGrupo(grupo, col.key) : null;
          if (v != null) {
            cell.value = v;
            cell.numFmt = VALOR_NUM_FMT;
          }
        }
      });
      idxAncora.set(ancora.key, idx);
      subtotalAncora.set(ancora.key, subtotalNum);
      linhasValor.add(idx);
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

  // ----- Camada analítica (f0/08): AV% (common-size) e Δ% (tendência). -----
  // Fórmulas transparentes sobre as MESMAS células de valor já escritas — não
  // inventam nada; a linha subjacente segue pendente/âmbar até o aceite.
  preencherAnaliseVerticalHorizontal(sheet, plano, [...linhasValor], baseTotalRow);

  // ----- Indicadores de liquidez/estrutura (Balanço) — f0/08. -----
  if (estrutura === "balanco") {
    escreverIndicadoresBalanco(sheet, plano, colunas, noRow, () => rowIndex++);
  }
}

// AV% e Δ% para todas as linhas monetárias. AV% = valor ÷ base (Ativo Total ou
// Receita Líquida); Δ% = (período atual − anterior) ÷ anterior. Só escreve onde
// a(s) célula(s) de valor referida(s) têm conteúdo — nunca força um % órfão.
function preencherAnaliseVerticalHorizontal(
  sheet: ExcelJS.Worksheet,
  plano: PlanoColunas,
  linhas: number[],
  baseTotalRow: number | null,
) {
  const temValor = (r: number, pos: number) => {
    const v = sheet.getRow(r).getCell(pos).value;
    return v != null && v !== "";
  };
  for (const r of linhas) {
    // Análise vertical
    if (baseTotalRow != null) {
      plano.valuePos.forEach((vp, i) => {
        const av = plano.avPos[i];
        if (av == null || !temValor(r, vp)) return;
        const L = sheet.getColumn(vp).letter;
        const cell = sheet.getRow(r).getCell(av);
        cell.value = { formula: `IFERROR(${L}${r}/${L}${baseTotalRow},"")` } as ExcelJS.CellFormulaValue;
        cell.numFmt = AV_FMT;
        cell.font = ANALISE_FONT;
      });
    }
    // Análise horizontal
    for (const d of plano.deltas) {
      const posAt = plano.valuePos[d.atual];
      const posAn = plano.valuePos[d.anterior];
      if (!temValor(r, posAt) || !temValor(r, posAn)) continue;
      const Lat = sheet.getColumn(posAt).letter;
      const Lan = sheet.getColumn(posAn).letter;
      const cell = sheet.getRow(r).getCell(d.pos);
      cell.value = { formula: `IFERROR((${Lat}${r}-${Lan}${r})/${Lan}${r},"")` } as ExcelJS.CellFormulaValue;
      cell.numFmt = DELTA_FMT;
      cell.font = ANALISE_FONT;
    }
  }
}

// Bloco de indicadores de liquidez e estrutura de capital ao pé do Balanço
// (Matarazzo/Assaf Neto; CFI credit analysis — f0/08). Cada indicador é uma
// FÓRMULA por coluna referenciando as linhas de subtotal do próprio Balanço
// (via `noRow`), com IFERROR: se o insumo não existe, a célula fica vazia —
// nunca estimamos. Índices que exigem detalhamento de conta ainda não isolado
// (liquidez seca/imediata, cobertura de juros, dívida líquida, ciclo de caixa,
// ROA/ROE, Altman Z'') ficam de fora por ora — ver f0/08.
function escreverIndicadoresBalanco(
  sheet: ExcelJS.Worksheet,
  plano: PlanoColunas,
  colunas: Coluna[],
  noRow: Map<string, number>,
  proximaLinha: () => number,
) {
  const AC = noRow.get("ativo_circulante");
  const ATV = noRow.get("ATIVO");
  const PC = noRow.get("passivo_circulante");
  const PNC = noRow.get("passivo_nao_circulante");
  const PL = noRow.get("patrimonio_liquido");
  const RLP = noRow.get("realizavel_lp");
  const IMOB = noRow.get("imobilizado");
  const INV = noRow.get("investimentos");
  const INT = noRow.get("intangivel");
  // Sem as âncoras estruturais mínimas não há o que calcular.
  if (AC == null || ATV == null || PC == null || PNC == null || PL == null) return;

  const cel = (i: number, row: number | undefined) => (row == null ? null : `${sheet.getColumn(plano.valuePos[i]).letter}${row}`);

  const indicadores: Array<{ label: string; fmt: string; formula: (i: number) => string | null }> = [
    { label: "Liquidez Corrente (AC ÷ PC)", fmt: RATIO_FMT, formula: (i) => `${cel(i, AC)}/${cel(i, PC)}` },
    {
      label: "Liquidez Geral ((AC + Realizável LP) ÷ (PC + PNC))",
      fmt: RATIO_FMT,
      formula: (i) => {
        const ac = cel(i, AC)!;
        const rlp = cel(i, RLP);
        const num = rlp ? `(${ac}+${rlp})` : ac;
        return `${num}/(${cel(i, PC)}+${cel(i, PNC)})`;
      },
    },
    { label: "Endividamento Geral ((PC + PNC) ÷ Ativo Total)", fmt: PCT_FMT, formula: (i) => `(${cel(i, PC)}+${cel(i, PNC)})/${cel(i, ATV)}` },
    { label: "Composição do Endividamento (PC ÷ (PC + PNC))", fmt: PCT_FMT, formula: (i) => `${cel(i, PC)}/(${cel(i, PC)}+${cel(i, PNC)})` },
    { label: "Participação de Capital de Terceiros ((PC + PNC) ÷ PL)", fmt: PCT_FMT, formula: (i) => `(${cel(i, PC)}+${cel(i, PNC)})/${cel(i, PL)}` },
    {
      label: "Imobilização do PL ((Imob. + Invest. + Intang.) ÷ PL)",
      fmt: PCT_FMT,
      formula: (i) => {
        const partes = [cel(i, IMOB), cel(i, INV), cel(i, INT)].filter(Boolean);
        if (partes.length === 0) return null;
        return `(${partes.join("+")})/${cel(i, PL)}`;
      },
    },
  ];

  proximaLinha(); // linha em branco separando do balanço
  const titulo = sheet.getRow(proximaLinha());
  titulo.getCell(1).value = "Indicadores de Liquidez e Estrutura";
  titulo.font = { bold: true };
  titulo.fill = INDICADOR_TITULO_FILL;
  titulo.getCell(1).note = comoNota(
    "Índices calculados por fórmula sobre os subtotais extraídos deste Balanço (Matarazzo/Assaf Neto; "
    + "f0/08). Célula vazia = insumo não disponível na extração (nunca estimado). Índices que exigem "
    + "detalhamento de conta ainda não isolado (liquidez seca/imediata, cobertura de juros, dívida "
    + "líquida/EBITDA, ciclo de caixa, ROA/ROE, Altman Z'') ficam de fora desta versão — ver f0/08. "
    + "Valores derivados de linhas ainda PENDENTES seguem pendentes até o aceite humano.",
  );

  for (const ind of indicadores) {
    const r = proximaLinha();
    const row = sheet.getRow(r);
    row.getCell(1).value = ind.label;
    row.getCell(1).font = INDICADOR_LABEL_FONT;
    colunas.forEach((_, i) => {
      const f = ind.formula(i);
      if (!f) return;
      const cell = row.getCell(plano.valuePos[i]);
      cell.value = { formula: `IFERROR(${f},"")` } as ExcelJS.CellFormulaValue;
      cell.numFmt = ind.fmt;
    });
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
}

// Nota de proveniência da linha simples (mesmo espírito de `notaProveniencia`,
// para os campos que a v20 pediu pra tirar da grade — seção/página/unidade/
// confiança/aceito por/aceito em/arquivo continuam rastreáveis, só saem de
// coluna própria pra virar um comentário no rótulo).
function notaProvenienciaSimples(linha: LinhaSimples): string {
  const partes = [
    linha.secao !== "(sem seção)" ? `Seção: ${linha.secao}` : null,
    `Arquivo: ${linha.arquivoOrigem}`,
    linha.pagina != null ? `Página: ${linha.pagina}` : null,
    linha.unidade ? `Unidade: ${linha.unidade}` : null,
    linha.confianca != null ? `Confiança da extração: ${Math.round(linha.confianca * 100)}%` : null,
    `Status: ${formatarStatus(linha.statusAceite)}`,
    linha.statusAceite === "aceito" && linha.aceitoPor ? `Aceito por: ${linha.aceitoPor}` : null,
    linha.aceitoEm ? `Aceito em: ${new Date(linha.aceitoEm).toLocaleString("pt-BR")}` : null,
  ].filter(Boolean);
  return partes.join("\n");
}

// Colunas reduzidas ao essencial (pedido do dono, sessão 7 cont.¹⁴): a
// listagem simples (Faturamento, Dívida, Intragrupo, Societário, ...) tinha 13
// colunas — a maioria delas técnica/de rastreabilidade (seção, página,
// unidade, confiança, aceito por/em, arquivo, versão da taxonomia), poluindo
// a leitura de quem só quer ver conta × valor. Essas informações não somem —
// viram um comentário (`cell.note`) no rótulo, visível ao passar o mouse.
function construirAbaSimples(workbook: ExcelJS.Workbook, nomeAba: string, linhas: LinhaSimples[]) {
  linhas.sort((a, b) =>
    a.entidade.localeCompare(b.entidade) || a.periodo.localeCompare(b.periodo) || a.secao.localeCompare(b.secao),
  );

  const sheet = workbook.addWorksheet(nomeAba, { views: [{ state: "frozen", ySplit: 1 }] });
  sheet.columns = [
    { header: "Entidade", key: "entidade", width: 26 },
    { header: "Período", key: "periodo", width: 14 },
    { header: "Rótulo", key: "chave", width: 38 },
    { header: "Valor", key: "valorNum", width: 16 },
    { header: "Status", key: "statusAceite", width: 12 },
  ];
  sheet.getRow(1).font = { bold: true };
  sheet.getRow(1).fill = HEADER_FILL;

  for (const linha of linhas) {
    const row = sheet.addRow({
      entidade: linha.entidade,
      periodo: linha.periodo,
      chave: linha.chave,
      valorNum: linha.valorNum ?? linha.valorTexto ?? null,
      statusAceite: formatarStatus(linha.statusAceite),
    });
    row.getCell("chave").note = comoNota(notaProvenienciaSimples(linha));
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
  documentos,
  campos,
  agora = new Date(),
}: {
  caso: { nome: string; produto: string };
  documentos: DocumentoParaExport[];
  campos: CampoExtraido[];
  agora?: Date;
}): ExcelJS.Workbook {
  // Mapa documento_versao_id → contexto (entidade/período/tipo/arquivo) —
  // permite juntar campo_extraido (que só sabe a versão) com o resto.
  const contextoPorVersao = new Map<string, ContextoVersao>();
  for (const doc of documentos) {
    for (const versao of doc.documento_versao ?? []) {
      contextoPorVersao.set(versao.id, {
        entidade: doc.entidade?.razao_social ?? "(sem entidade)",
        periodo: doc.periodo ? formatarPeriodo(doc.periodo.tipo, doc.periodo.referencia) : "(sem período)",
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
    const abaDoc = (ctx.tipoTaxonomia && ABA_POR_TIPO[ctx.tipoTaxonomia]) || "Outros";
    const estruturaDoc = ESTRUTURA_POR_ABA.get(abaDoc);

    // Roteamento por LINHA (não por tipo do documento): um PDF de
    // "Demonstrações Contábeis" traz Balanço + DRE + Fluxo de Caixa no mesmo
    // arquivo, mas é UM documento de um tipo só. Se a linha pertence a uma
    // demonstração diferente da do documento, ela vai para a aba canônica
    // daquela demonstração — em vez de empilhar tudo na aba do tipo do
    // documento (o que fazia a DRE cair em "Não Classificadas" e as linhas de
    // Fluxo de Caixa vazarem para dentro do Ativo). Só reroteia entre abas
    // ESTRUTURADAS (Balanço/DRE/Fluxo); abas de série (Faturamento/Dívida/…)
    // não são tocadas. Continua N1: a linha segue pendente/âmbar até o aceite.
    let aba = abaDoc;
    if (estruturaDoc) {
      const familiaLinha = classificarDemonstracao(campo.secao, campo.chave, campo.secao_canonica, estruturaDoc);
      if (familiaLinha && familiaLinha !== estruturaDoc) {
        aba = ABA_PADRAO_POR_ESTRUTURA[familiaLinha];
      }
    }
    // Documento multi-entidade (db/migrations/0014): quando a linha traz
    // `entidade_coluna` (ex.: "Certsys Tecn" num balanço combinado com várias
    // colunas de empresa), a coluna do export é a ENTIDADE DA LINHA, não a
    // entidade principal do documento — é o que separa "Certsys Tecn"/"Part"/
    // "Com"/"Total" em colunas próprias no lugar de forçar tudo numa coluna só.
    const entidadeColuna = campo.entidade_coluna || ctx.entidade;
    // Documento comparativo (db/migrations/0017): quando a linha traz
    // `periodo_coluna` (ex.: "2023"/"2024" num balanço 2023×2024), o período da
    // COLUNA do export é o da linha, não o período único do documento — é o que
    // separa os anos em colunas próprias em vez de colapsá-los num só (perda de
    // dado). Ortogonal a entidade_coluna: a coluna final é entidade × período.
    const periodoColuna = campo.periodo_coluna || ctx.periodo;
    const colKey = `${entidadeColuna} ${periodoColuna}`;
    const estrutura = ESTRUTURA_POR_ABA.get(aba);

    if (estrutura) {
      if (!colunasPorAba.has(aba)) colunasPorAba.set(aba, new Map());
      colunasPorAba.get(aba)!.set(colKey, { key: colKey, entidade: entidadeColuna, periodo: periodoColuna });
      if (!camposPorAba.has(aba)) camposPorAba.set(aba, []);
      camposPorAba.get(aba)!.push({ campo, colKey });
    } else {
      if (!linhasSimplesPorAba.has(aba)) linhasSimplesPorAba.set(aba, []);
      linhasSimplesPorAba.get(aba)!.push({
        entidade: entidadeColuna,
        periodo: periodoColuna,
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
      });
    }
  }

  const workbook = new ExcelJS.Workbook();
  workbook.creator = "Oria — Tratamento de Dados Financeiros";
  workbook.created = agora;

  // ----- Aba Resumo (metadados do snapshot) -----
  // Pedido do dono (sessão 7 cont.¹⁵): tipo/versão de taxonomia é detalhe
  // interno de classificação, não algo que o time de análise precisa ver na
  // planilha — some daqui (e de toda nota/aviso) mas continua orientando o
  // roteamento por aba internamente (`tipo_taxonomia`/`ABA_POR_TIPO`).
  const resumo = workbook.addWorksheet("Resumo");
  const totalLinhas = campos.length;
  const totalAceitas = campos.filter((c) => c.status_aceite === "aceito").length;
  resumo.columns = [{ width: 32 }, { width: 60 }];
  resumo.addRows([
    ["Caso", caso.nome],
    ["Produto", caso.produto],
    ["Gerado em", agora.toLocaleString("pt-BR")],
    ["Linhas totais extraídas", totalLinhas],
    ["Linhas aceitas (fato)", totalAceitas],
    ["Linhas pendentes (sugestão, revisar)", totalLinhas - totalAceitas],
    [""],
    [
      "Aviso",
      "Este export NÃO é modelagem financeira e não projeta nada — é dado curado e rastreável " +
        "para o time de análise trabalhar em cima (f0/07_output_spec.md). Linhas marcadas " +
        "PENDENTE ainda não passaram por aceite humano — não são fato, são sugestão a revisar " +
        "antes de entrar no modelo. Quando um mesmo arquivo traz várias demonstrações juntas " +
        "(ex.: Balanço + DRE + Fluxo de Caixa no mesmo PDF), cada linha é encaminhada para a aba " +
        "da demonstração a que pertence — não fica tudo na aba do tipo do documento. " +
        "Balanço/Balancete/DRE/Fluxo de Caixa/Combinado classificam cada conta extraída por SEÇÃO " +
        "(Ativo Circulante, Despesas Operacionais, etc.), mantendo o rótulo original de cada " +
        "empresa — nenhum subtotal é calculado por nós, só aparece se o próprio documento já " +
        "trouxer aquela linha. Contas que não foi possível classificar com segurança aparecem em " +
        "\"Contas Não Classificadas\", ao final de cada aba — revisar manualmente.",
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
      );
    } else {
      const linhas = linhasSimplesPorAba.get(aba);
      if (!linhas || linhas.length === 0) continue;
      construirAbaSimples(workbook, aba, linhas);
    }
  }

  return workbook;
}

// ExcelJS grava a caixa de toda nota (`cell.note`) com um tamanho FIXO no XML
// VML (`width:97.8pt;height:59.1pt`, ~130×80px) — hardcoded no próprio
// pacote (`lib/xlsx/xform/comment/vml-shape-xform.js`), sem parâmetro público
// pra mudar (conferido lendo o fonte, não só o `.d.ts`). É por isso que
// anotações com texto de várias linhas apareciam cortadas ao abrir (pedido do
// dono, sessão 7 cont.¹⁵). Sem editar `node_modules`, o único jeito é
// pós-processar o .xlsx já gerado: ele é um .zip, então abrimos com JSZip
// (já vem como dependência transitiva do próprio exceljs), achamos as partes
// `xl/drawings/vmlDrawing*.vml` e trocamos a string de tamanho fixo por uma
// caixa bem maior, igual para toda nota do workbook (o hardcode do exceljs
// já é idêntico em todas — troca segura por string).
const NOTA_BOX_ANTIGA = "width:97.8pt;height:59.1pt";
const NOTA_BOX_NOVA = "width:340pt;height:170pt";

export async function ampliarNotasNoBuffer(buffer: Buffer | ArrayBuffer): Promise<Buffer> {
  const zip = await JSZip.loadAsync(buffer);
  const vmlPaths = Object.keys(zip.files).filter((p) => /^xl\/drawings\/vmlDrawing\d+\.vml$/.test(p));
  for (const path of vmlPaths) {
    const xml = await zip.file(path)!.async("string");
    if (!xml.includes(NOTA_BOX_ANTIGA)) continue;
    zip.file(path, xml.split(NOTA_BOX_ANTIGA).join(NOTA_BOX_NOVA));
  }
  return zip.generateAsync({ type: "nodebuffer" });
}

// Reexportado para eventuais consumidores que só precisem agrupar por conta
// (ex.: uma futura tela de revisão por seção no portal).
export { agruparPorChaveNormalizada };
