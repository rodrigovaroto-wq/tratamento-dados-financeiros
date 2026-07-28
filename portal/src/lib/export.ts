import ExcelJS from "exceljs";
import JSZip from "jszip";
import type { CampoExtraido } from "./types";
import {
  classificarConta,
  classificarDemonstracao,
  secoesDe,
  ancorasDe,
  agruparPorChaveNormalizada,
  normalizar,
  ESTRUTURA_POR_TIPO,
  BALANCO_OUTLINE,
  type EstruturaDemonstracao,
  type FamiliaDemonstracao,
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

const MESES_ABREV = ["Jan", "Fev", "Mar", "Abr", "Mai", "Jun", "Jul", "Ago", "Set", "Out", "Nov", "Dez"];
const MES_POR_NOME: Record<string, number> = {
  jan: 1, fev: 2, mar: 3, abr: 4, mai: 5, jun: 6, jul: 7, ago: 8, set: 9, out: 10, nov: 11, dez: 12,
  janeiro: 1, fevereiro: 2, marco: 3, abril: 4, maio: 5, junho: 6, julho: 7, agosto: 8,
  setembro: 9, outubro: 10, novembro: 11, dezembro: 12,
};
function mesAno(mes: number, anoTexto: string): string {
  return `${MESES_ABREV[mes - 1]}/${anoDe4Digitos(anoTexto)}`;
}

// Padroniza o período num modelo pronto e objetivo, tolerante às MUITAS notações
// que a extração produz entre contratos diferentes (cada demonstração escreve o
// período de um jeito). Robusto contra os mis-parses reais achados na auditoria:
// "02,25" NÃO é o intervalo "2002–2025" e sim Fev/2025 (mês,ano); semestre,
// mês abreviado, MM/AAAA e ISO (mesmo sem tipo=data-base) são reconhecidos. O
// que não reconhece volta como veio (nunca pior que antes).
export function formatarPeriodo(tipo: string | null, referencia: string | null): string {
  const ref = (referencia ?? "").trim();
  const t = (tipo ?? "").trim();
  if (!ref) return "—";
  const low = ref.toLowerCase();

  const ultimosMeses = ref.match(/^L(\d+)M$/i);
  if (ultimosMeses) return `Últimos ${ultimosMeses[1]} meses`;

  const anoFiscal = ref.match(/^(\d{1,2})M(\d{2,4})$/i);
  if (anoFiscal) {
    const nMeses = Number(anoFiscal[1]);
    const ano = anoDe4Digitos(anoFiscal[2]);
    return nMeses === 12 ? ano : `${nMeses} meses/${ano}`;
  }

  const trimestre = ref.match(/^(\d)T(\d{2,4})$/i);
  if (trimestre) return `${trimestre[1]}º Tri/${anoDe4Digitos(trimestre[2])}`;
  const semestre = ref.match(/^(\d)S(\d{2,4})$/i);
  if (semestre) return `${semestre[1]}º Sem/${anoDe4Digitos(semestre[2])}`;

  // Datas: ISO (independente do tipo) e BR já legível
  const iso = ref.match(/^(\d{4})-(\d{2})-(\d{2})$/);
  if (iso) return `${iso[3]}/${iso[2]}/${iso[1]}`;
  if (/^\d{2}\/\d{2}\/\d{2,4}$/.test(ref)) return ref;

  // Mês por nome/abreviação + ano: "jan/25", "dez-24", "fevereiro/2025"
  const mesNome = low.match(/^([a-zç]{3,9})[\/\-. ](\d{2,4})$/);
  if (mesNome && MES_POR_NOME[mesNome[1]] != null) return mesAno(MES_POR_NOME[mesNome[1]], mesNome[2]);

  // MM/AAAA ou MM-AAAA (mês numérico + ano de 4 dígitos): "02/2025", "12/2025"
  const mmAno = ref.match(/^(\d{1,2})[\/-](\d{4})$/);
  if (mmAno && Number(mmAno[1]) >= 1 && Number(mmAno[1]) <= 12) return mesAno(Number(mmAno[1]), mmAno[2]);

  if (t === "data-base") return formatarDataBR(ref);

  if (t === "multi" || /,/.test(ref)) {
    const toks = ref.split(",").map((p) => p.trim()).filter(Boolean);
    // "MM,AAAA"/"MM,AA" = MÊS,ANO — não um intervalo de exercícios (o mis-parse
    // "2002–2025"/"2012–2024" da auditoria). Dois sinais desambiguam:
    //   (a) mês com zero à esquerda ("02,25" → Fev/2025);
    //   (b) mês 1–12 seguido de ano de 4 dígitos ("12,2024" → Dez/2024) — uma
    //       lista de exercícios seria escrita com a MESMA largura nos dois
    //       tokens ("2012,2024" ou "12,24"), não misturada.
    // Sobra ambíguo só "NN,NN" sem zero à esquerda ("11,12"), que continua
    // tratado como exercícios (2011–2012) — a convenção do sistema para lista
    // de anos é justamente 2 dígitos (ver notação canônica em n8n/lib/extract).
    if (toks.length === 2) {
      const mes = Number(toks[0]);
      const mesComZero = /^0[1-9]$/.test(toks[0]);
      const anoCheio = /^\d{4}$/.test(toks[1]);
      if ((mesComZero && /^\d{2,4}$/.test(toks[1])) || (anoCheio && mes >= 1 && mes <= 12)) {
        return mesAno(mes, toks[1]);
      }
    }
    // Caso geral: lista de exercícios (anos).
    if (toks.every((p) => /^\d{1,4}$/.test(p))) {
      const anos = toks.map((p) => anoDe4Digitos(p));
      if (anos.length === 1) return anos[0];
      if (anos.length === 2) return `${anos[0]}–${anos[1]}`;
      return anos.join(", ");
    }
    return toks.join(", ");
  }

  if (/^\d{4}$/.test(ref)) return ref;
  if (/^\d{2}$/.test(ref)) return anoDe4Digitos(ref);

  return ref; // texto livre já descritivo (ex.: "Jan/2024 a Dez/2025") — mantém como veio
}

// Colunas de uma demonstração COMBINADA que NÃO são entidades: a de
// "Eliminações"/"Ajustes" (lançamentos que anulam saldos recíprocos) e a de
// "Combinado"/"Consolidado"/"Total" (o resultado da soma). A extração as trata
// como mais uma coluna de empresa — correto do ponto de vista do documento, mas
// no export elas não podem ser lidas como entidade: a de total DUPLICA o que as
// demais já dizem, e AV%/Δ% sobre uma coluna de ajuste é ruído. Achado no teste
// v24: a aba Combinado saiu com "Eliminações" e "Combinado" como se fossem duas
// empresas do grupo. Aqui elas continuam no export (nada se perde), mas ficam
// no FIM, rotuladas pelo que são, e sem análise vertical/horizontal.
const RE_COLUNA_AJUSTE = /^(elimina|ajuste|eliminacao)/;
const RE_COLUNA_TOTAL = /^(combinad|consolidad|total|soma)/;
export function tipoColunaNaoEntidade(entidade: string): "ajuste" | "total" | null {
  const t = normalizar(entidade);
  if (RE_COLUNA_AJUSTE.test(t)) return "ajuste";
  if (RE_COLUNA_TOTAL.test(t)) return "total";
  return null;
}

// Chave CRONOLÓGICA de um período já formatado (saída de `formatarPeriodo`).
// As colunas do export eram ordenadas por `localeCompare` do rótulo, o que é
// alfabético: "Nov/2024" vinha antes de "Out/2024" e "Dez/2024" antes de
// "Jan/2024" — além de bagunçar a leitura, isso fazia a coluna Δ% (que compara
// períodos ADJACENTES da mesma entidade) casar o par errado, reportando uma
// variação entre meses que não se sucedem. Deriva (ano, mês, dia) do rótulo;
// períodos que agregam vários exercícios entram no nível do ANO (mês 0, antes
// dos meses daquele ano) e rótulos sem âncora temporal ("Últimos 24 meses",
// texto livre) vão para o fim — nunca no meio da série.
const MES_NUM: Record<string, number> = {
  jan: 1, fev: 2, mar: 3, abr: 4, mai: 5, jun: 6, jul: 7, ago: 8, set: 9, out: 10, nov: 11, dez: 12,
};
export const CRONO_SEM_ANCORA = Number.MAX_SAFE_INTEGER;

export function chaveCronologicaPeriodo(periodoFormatado: string): number {
  const p = (periodoFormatado ?? "").trim();
  if (!p || p === "—") return CRONO_SEM_ANCORA;
  const chave = (ano: number, mes = 0, dia = 0) => ano * 10000 + mes * 100 + dia;

  const data = p.match(/^(\d{2})\/(\d{2})\/(\d{4})$/); // 15/01/2025
  if (data) return chave(Number(data[3]), Number(data[2]), Number(data[1]));

  const mesAbrev = p.match(/^([A-Za-zç]{3})\/(\d{4})$/); // Fev/2025
  if (mesAbrev) {
    const m = MES_NUM[mesAbrev[1].toLowerCase()];
    if (m) return chave(Number(mesAbrev[2]), m);
  }

  const tri = p.match(/^([1-4])º Tri\/(\d{4})$/); // 1º Tri/2025 → início do trimestre
  if (tri) return chave(Number(tri[2]), (Number(tri[1]) - 1) * 3 + 1);

  const sem = p.match(/^([12])º Sem\/(\d{4})$/); // 2º Sem/2024 → início do semestre
  if (sem) return chave(Number(sem[2]), Number(sem[1]) === 1 ? 1 : 7);

  const nMeses = p.match(/^(\d{1,2}) meses\/(\d{4})$/); // 9 meses/2024 (YTD)
  if (nMeses) return chave(Number(nMeses[2]), Number(nMeses[1]));

  if (/^\d{4}$/.test(p)) return chave(Number(p)); // exercício completo

  // Agregados de vários exercícios ("2024–2025", "2023, 2024, 2025"): entram no
  // nível do ano pelo PRIMEIRO exercício da série (ordenação determinística).
  const anos = p.match(/\b(19|20)\d{2}\b/g);
  if (anos && anos.length > 0) return chave(Number(anos[0]));

  return CRONO_SEM_ANCORA; // "Últimos 24 meses", texto livre — sempre por último
}

// Comparador de coluna: entidade (alfabética) → período (CRONOLÓGICO) → rótulo
// como desempate estável para períodos sem âncora temporal.
function compararColunas(
  a: { entidade: string; periodo: string },
  b: { entidade: string; periodo: string },
): number {
  // Entidades reais primeiro; depois a coluna de eliminações; o total por último
  // (é a leitura natural de um mapa de combinação).
  const ordem = (e: string) => {
    const t = tipoColunaNaoEntidade(e);
    return t === "ajuste" ? 1 : t === "total" ? 2 : 0;
  };
  return (
    ordem(a.entidade) - ordem(b.entidade)
    || a.entidade.localeCompare(b.entidade)
    || chaveCronologicaPeriodo(a.periodo) - chaveCronologicaPeriodo(b.periodo)
    || a.periodo.localeCompare(b.periodo)
  );
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
// DMPL/DVA têm renderização própria (nem grade classificada, nem listagem
// simples) — nomeadas para o roteamento não depender de string solta.
const ABA_DMPL = "DMPL";
const ABA_DVA = "DVA";

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
  DMPL: ABA_DMPL,
  DVA: ABA_DVA,
};
export const ORDEM_ABAS = [
  "Balanço",
  "DRE",
  "Fluxo de Caixa",
  // Depois das três demonstrações principais e antes do Combinado/Balancete:
  // é a ordem em que uma demonstração contábil publicada apresenta o conjunto
  // (BP, DRE, DFC, DMPL, DVA — Lei 6.404/76 art. 176).
  ABA_DMPL,
  ABA_DVA,
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
  DMPL: "Mutações do Patrimônio Líquido",
  DVA: "Demonstração do Valor Adicionado",
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
const ABA_PADRAO_POR_ESTRUTURA: Record<FamiliaDemonstracao, string> = {
  balanco: "Balanço",
  dre: "DRE",
  fluxo_caixa: "Fluxo de Caixa",
  dmpl: "DMPL",
  dva: "DVA",
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

// Separador de chave composta. É um caractere que NUNCA aparece num rótulo
// contábil, e é isso que se quer: com espaço simples, entidade "A B" + período
// "C" colide com entidade "A" + período "B C" (colunas distintas fundidas numa
// só). Escrito como escape, e não como o byte literal, para não deixar um
// caractere invisível no fonte.
const CHAVE_SEP = "\u0000";

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
const SUBTOTAL_INFO_FONT: Partial<ExcelJS.Font> = { italic: true, size: 8, color: { argb: "FF7C3AED" } };
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
    const naoEntidade = tipoColunaNaoEntidade(coluna.entidade) != null;
    valuePos[i] = col++;
    // AV% não se aplica a coluna de ajuste/total (ver tipoColunaNaoEntidade).
    avPos[i] = comAV && !naoEntidade ? col++ : null;
    // Δ% só entre períodos DIFERENTES da MESMA entidade, adjacentes na ordenação
    // (as colunas vêm ordenadas por entidade e depois período).
    if (!naoEntidade && i > 0 && colunas[i - 1].entidade === coluna.entidade
        && colunas[i - 1].periodo !== coluna.periodo
        && tipoColunaNaoEntidade(colunas[i - 1].entidade) == null) {
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

// Uma linha extraída é o SUBTOTAL de um agrupamento do próprio documento (e não
// uma conta)? Demonstrações reais são hierárquicas: sob "Ativo Circulante" vêm
// os agrupamentos "Disponível", "Contas a Receber", "Estoques"… cada um com o
// PRÓPRIO subtotal impresso, seguido das contas que o compõem. Sem reconhecer
// isso, o subtotal entra no bucket como se fosse conta e o `SUM` da seção soma
// o subtotal MAIS os seus componentes — dobrando tudo. Achado com dado real
// (book Vertentes): `SUM` do Ativo Circulante deu 137.865 contra 67.878
// informados = 2,03x, contaminando também AV% e todos os indicadores.
//
// A `ancoraBalanco` de statement-templates.ts só reconhece total quando o
// rótulo tem "total"/"soma" ou é feito só de palavras estruturais — não cobre
// "Disponível"/"Estoques", que são nomes de agrupamento comuns. Aqui a detecção
// é ESTRUTURAL, a partir do próprio documento, por dois sinais independentes:
//
//   (A) o rótulo da linha é IGUAL ao nome de seção (`secao`) que outras linhas
//       do mesmo documento declaram — ou seja, o documento diz que aquele nome
//       é um agrupamento, e esta linha é o total dele;
//   (B) o valor da linha é IGUAL à soma das OUTRAS linhas que compartilham a
//       mesma `secao`, em TODAS as colunas com dado — coincidência estatística
//       praticamente impossível em documento multi-coluna.
//
// Nada é descartado: a linha continua visível (marcada como subtotal informado),
// só sai da SOMA. Sem `secao` anotada, nenhum dos sinais dispara e o
// comportamento é o de antes (conservador).
function detectarSubtotaisInformados(
  camposDaAba: Array<{ campo: CampoExtraido; colKey: string }>,
): Set<string> {
  const subtotais = new Set<string>();
  const secoesDeclaradas = new Set<string>();
  for (const { campo } of camposDaAba) {
    const s = normalizar(campo.secao ?? "");
    if (s) secoesDeclaradas.add(s);
  }

  // (A) rótulo == nome de um agrupamento declarado pelo documento.
  for (const { campo } of camposDaAba) {
    const chaveNorm = normalizar(campo.chave);
    if (!chaveNorm || !secoesDeclaradas.has(chaveNorm)) continue;
    // exige que o agrupamento tenha MEMBROS (linhas cuja secao é esse nome e
    // cujo rótulo é diferente) — senão não há nada que este total duplique.
    const temMembros = camposDaAba.some(
      ({ campo: c }) => normalizar(c.secao ?? "") === chaveNorm && normalizar(c.chave) !== chaveNorm,
    );
    if (temMembros) subtotais.add(campo.id);
  }

  // (B) valor == soma dos irmãos da mesma seção, em todas as colunas com dado.
  const porSecao = new Map<string, Array<{ campo: CampoExtraido; colKey: string }>>();
  for (const item of camposDaAba) {
    const s = normalizar(item.campo.secao ?? "");
    if (!s) continue;
    if (!porSecao.has(s)) porSecao.set(s, []);
    porSecao.get(s)!.push(item);
  }
  for (const itens of porSecao.values()) {
    const porChave = new Map<string, Array<{ campo: CampoExtraido; colKey: string }>>();
    for (const it of itens) {
      const k = normalizar(it.campo.chave);
      if (!porChave.has(k)) porChave.set(k, []);
      porChave.get(k)!.push(it);
    }
    if (porChave.size < 3) continue; // precisa de >=2 componentes + o subtotal
    for (const [chaveCandidata, ocorrencias] of porChave) {
      let colunasConferidas = 0;
      let bate = true;
      const colunas = new Set(ocorrencias.map((o) => o.colKey));
      for (const colKey of colunas) {
        const cand = ocorrencias.find((o) => o.colKey === colKey)?.campo.valor_num;
        if (typeof cand !== "number") continue;
        let soma = 0;
        let n = 0;
        for (const [k, occ] of porChave) {
          if (k === chaveCandidata) continue;
          const v = occ.find((o) => o.colKey === colKey)?.campo.valor_num;
          if (typeof v === "number") { soma += v; n++; }
        }
        if (n < 2) continue;
        colunasConferidas++;
        if (Math.abs(soma - cand) > Math.max(0.01, Math.abs(cand) * 0.005)) { bate = false; break; }
      }
      if (bate && colunasConferidas > 0) {
        for (const o of ocorrencias) subtotais.add(o.campo.id);
      }
    }
  }
  return subtotais;
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
    const tipoCol = tipoColunaNaoEntidade(col.entidade);
    const sufixo = tipoCol === "ajuste" ? " (ajuste — não é entidade)"
      : tipoCol === "total" ? " (total do documento — não somar com as demais)" : "";
    cell.value = `${col.entidade} — ${col.periodo}${sufixo}`;
    cell.fill = tipoCol ? ANALISE_HEADER_FILL : HEADER_FILL;
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
    // normalizar() (acento/espaço) para que "Salários" e "Salarios", ou
    // "Duplicatas  a Receber" e "Duplicatas a Receber" (deriva de grafia entre
    // períodos/entidades da mesma empresa), caiam na MESMA linha em vez de
    // gerar dois grupos que quebram o alinhamento entidade×período.
    const chaveNorm = normalizar(campo.chave);
    if (!mapa.has(chaveNorm)) mapa.set(chaveNorm, novoGrupo(campo.chave));
    adicionarAoGrupo(mapa.get(chaveNorm)!, colKey, campo);
  };
  // Subtotais de agrupamento que o documento trouxe (ver
  // `detectarSubtotaisInformados`): ficam FORA da soma da seção — senão o
  // `SUM` conta o subtotal e os seus componentes, dobrando o total.
  const idsSubtotal = detectarSubtotaisInformados(camposDaAba);
  const subtotaisInformados = new Map<string, Map<string, GrupoConta>>(); // secaoKey → grupos

  // Classificação de cada linha, em DOIS passes.
  //
  // Passe 1: a regra de sempre (âncora / seção / palavra-chave / sugestão da IA).
  //
  // Passe 2 — CONSENSO DE IRMÃOS: demonstrações reais são hierárquicas, e a
  // `secao` que a IA anota costuma ser o nome da SUBSEÇÃO ("Estoques",
  // "Disponível", "Outras Obrigações"), que não carrega sinal de Ativo/Passivo.
  // Resultado (achado no teste v24): uma conta com vocabulário fora das listas
  // — "(-) PECLD", "Produtos em elaboração" — caía em "Contas Não
  // Classificadas" mesmo estando declaradamente sob "Estoques", e a soma da
  // seção ficava furada. Aqui a linha herda a seção dos IRMÃOS: se as outras
  // linhas do MESMO agrupamento foram classificadas, e de forma unânime, esta
  // vai para o mesmo lugar. É como um humano lê a demonstração ("está sob
  // Estoques, e o resto de Estoques é Ativo Circulante"), não depende de
  // vocabulário novo, e permanece conservador: sem irmãos classificados ou com
  // irmãos divergentes, a linha continua em "Não Classificadas".
  type Item = { campo: CampoExtraido; colKey: string };
  const classificado = new Map<string, { secaoKey: string | null; ancoraKey: string | null }>();
  const semClassificacao: Item[] = [];
  for (const item of camposDaAba) {
    const { campo } = item;
    if (campo.valor_num == null && campo.valor_texto == null) continue;
    const r = classificarConta(estrutura, campo.secao, campo.chave, campo.secao_canonica);
    classificado.set(campo.id, r);
    if (!r.secaoKey && !r.ancoraKey) semClassificacao.push(item);
  }
  if (semClassificacao.length > 0) {
    const consensoPorSecao = new Map<string, Set<string>>();
    for (const { campo } of camposDaAba) {
      const sec = normalizar(campo.secao ?? "");
      const r = classificado.get(campo.id);
      if (!sec || !r?.secaoKey) continue;
      if (!consensoPorSecao.has(sec)) consensoPorSecao.set(sec, new Set());
      consensoPorSecao.get(sec)!.add(r.secaoKey);
    }
    for (const { campo } of semClassificacao) {
      const sec = normalizar(campo.secao ?? "");
      const candidatas = sec ? consensoPorSecao.get(sec) : undefined;
      if (candidatas && candidatas.size === 1) {
        classificado.set(campo.id, { secaoKey: [...candidatas][0], ancoraKey: null });
      }
    }
  }

  for (const { campo, colKey } of camposDaAba) {
    if (campo.valor_num == null && campo.valor_texto == null) continue;
    const { secaoKey, ancoraKey } = classificado.get(campo.id) ?? { secaoKey: null, ancoraKey: null };
    if (ancoraKey) {
      if (!valoresPorAncora.has(ancoraKey)) valoresPorAncora.set(ancoraKey, novoGrupo(campo.chave));
      adicionarAoGrupo(valoresPorAncora.get(ancoraKey)!, colKey, campo);
    } else if (secaoKey && idsSubtotal.has(campo.id)) {
      if (!subtotaisInformados.has(secaoKey)) subtotaisInformados.set(secaoKey, new Map());
      bucket(subtotaisInformados.get(secaoKey)!, campo, colKey);
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
  // …e o VALOR do nó por coluna, para os indicadores só emitirem índice que
  // realmente resolve (fórmula existir não basta: os insumos podem estar
  // vazios ou o denominador zerado, e o índice sairia como linha vazia).
  const noValor = new Map<string, Map<string, number>>();
  let baseTotalRow: number | null = null; // base da AV% (Ativo Total / Receita Líquida)

  const escrever = (label: string, nivel: number, grupo: GrupoConta, opts: { negrito?: boolean; borda?: "simples" | "dupla" } = {}) => {
    const r = rowIndex++;
    escreverLinhaConta(sheet, r, label, nivel, colunas, plano.valuePos, grupo, opts, contextoPorVersao);
    linhasValor.add(r);
    return r;
  };

  // Subtotais de agrupamento que o documento trouxe: emitidos DEPOIS do range
  // do SUM (portanto fora da soma) e com estilo próprio, para o analista ver o
  // que o documento declarou sem que isso dobre o total.
  const escreverSubtotaisInformados = (secaoKey: string, nivel: number) => {
    const grupos = subtotaisInformados.get(secaoKey);
    if (!grupos) return;
    for (const g of grupos.values()) {
      const r = rowIndex++;
      const row = sheet.getRow(r);
      row.getCell(1).value = `↳ subtotal informado: ${g.label}`;
      row.getCell(1).alignment = { indent: nivel + 1 };
      row.getCell(1).font = SUBTOTAL_INFO_FONT;
      row.getCell(1).note = comoNota(
        "Subtotal de agrupamento trazido pelo próprio documento. Fica FORA da soma da seção de "
        + "propósito: somá-lo junto com as contas que ele agrega dobraria o total.",
      );
      colunas.forEach((col, i) => {
        const cell = row.getCell(plano.valuePos[i]);
        const v = valorNumDoGrupo(g, col.key);
        if (v == null) return;
        cell.value = v;
        cell.numFmt = VALOR_NUM_FMT;
        cell.font = SUBTOTAL_INFO_FONT;
      });
      linhasValor.add(r);
    }
  };

  // Linha de conferência: o total que o DOCUMENTO trouxe (extraído), logo
  // abaixo do cabeçalho. Se divergir do subtotal calculado, pinta ambas as
  // células e anota o motivo (checagem de reconciliação embutida).
  // Devolve o índice da linha, para o cabeçalho poder apontar para ela.
  const escreverConferenciaExtraido = (nivel: number, ancoraKey: string, cabecalhoIdx: number, subtotalNum: Map<string, number>): number | null => {
    const grupo = valoresPorAncora.get(ancoraKey);
    if (!grupo) return null;
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
          `Divergência: soma das contas listadas = ${vCalc.toLocaleString("pt-BR", { minimumFractionDigits: 2, maximumFractionDigits: 2 })}, `
          + `informado no documento = ${vExtraido.toLocaleString("pt-BR", { minimumFractionDigits: 2, maximumFractionDigits: 2 })}. `
          + `Causa mais comum: o documento imprime subtotais intermediários (ex.: "Disponível" acima de `
          + `"Caixa e bancos" + "Aplicações"), e a soma conta o subtotal E os seus componentes. `
          + `O valor da seção segue o que o documento informou; confira a extração contra o original.`,
        );
        // sinaliza também a célula do cabeçalho
        sheet.getRow(cabecalhoIdx).getCell(plano.valuePos[i]).fill = DIVERGENCIA_FILL;
      }
    });
    return idx;
  };

  // Linha "soma das contas listadas": a fórmula =SUM(range) sai do cabeçalho e
  // vem para cá quando o documento informou o total da seção.
  //
  // Por quê: demonstração real é hierárquica e imprime subtotais de subseção.
  // Somar as contas listadas conta o subtotal E os seus componentes — dobra o
  // total. Detectar o subtotal pela estrutura (`detectarSubtotaisInformados`)
  // resolve quando a IA anota a SUBSEÇÃO em `secao`; quando ela anota a seção de
  // topo, o subtotal impresso passa e a soma sai 2x (achado no teste v25: 36 de
  // 44 somas do Balanço divergiam, várias exatamente 2,00x).
  //
  // Então o número da seção deixa de depender de acertarmos a hierarquia: quando
  // o documento diz quanto é, o cabeçalho aponta para o que ele disse, e a nossa
  // soma vira uma LINHA DE CHECAGEM ao lado. Nada é escondido — a divergência
  // fica visível e pintada, que é o sinal útil — e AV%, Δ% e indicadores passam a
  // usar o número autoritativo em vez de um que pode estar dobrado.
  const escreverSomaCalculada = (nivel: number, rotulo: string, formulaDaColuna: (i: number) => string) => {
    const idx = rowIndex++;
    const row = sheet.getRow(idx);
    row.getCell(1).value = `↳ ${rotulo} (checagem)`;
    row.getCell(1).alignment = { indent: nivel + 1 };
    row.getCell(1).font = { italic: true, size: 9, color: { argb: "FF6B7280" } };
    row.getCell(1).note = comoNota(
      "Soma calculada por nós, para conferir contra o total que o documento informou (linha acima). "
      + "Quando as duas divergem, quase sempre é porque o documento traz subtotais intermediários, "
      + "que a soma conta duas vezes — por isso o valor da seção segue o informado, não esta soma.",
    );
    colunas.forEach((col, i) => {
      const cell = row.getCell(plano.valuePos[i]);
      cell.value = { formula: formulaDaColuna(i) } as ExcelJS.CellFormulaValue;
      cell.numFmt = VALOR_NUM_FMT;
      cell.font = { italic: true, size: 9, color: { argb: "FF6B7280" } };
    });
    return idx;
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
        // Seção SEM NENHUM DADO não é emitida — em nenhum nível. O template
        // canônico (CPC 26 / art. 178) existe para ORDENAR o que o documento
        // trouxe, não para impor linhas que o documento não tem: antes, uma
        // empresa sem Realizável LP nem Intangível ganhava linhas de subgrupo em
        // branco, e uma sem Passivo Não Circulante ganhava um "0" que nós
        // inventamos (o documento não disse zero — não disse nada).
        if (contas.length === 0 && !temAncora) return null;
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
        escreverSubtotaisInformados(no.key, no.nivel + 1);
        // Quando o documento informou o total desta seção, ELE é o número da
        // seção; a nossa soma vai para uma linha de checagem logo abaixo (ver
        // `escreverSomaCalculada`). Isso torna o total, a AV%, o Δ% e os
        // indicadores imunes a subtotal de subseção contado duas vezes.
        const informadoIdx = temAncora
          ? escreverConferenciaExtraido(no.nivel, no.key, cabIdx, temContas ? subtotalNum : new Map())
          : null;
        if (temAncora && temContas && informadoIdx != null) {
          escreverSomaCalculada(no.nivel, "soma das contas listadas",
            (i) => `SUM(${colLetra(i)}${primeira}:${colLetra(i)}${ultima})`);
        }
        const grupoAncora = temAncora ? valoresPorAncora.get(no.key)! : null;
        const row = sheet.getRow(cabIdx);
        row.getCell(1).value = no.label;
        row.getCell(1).alignment = { indent: no.nivel };
        row.font = { bold: true };
        row.fill = fill;
        colunas.forEach((col, i) => {
          const cell = row.getCell(plano.valuePos[i]);
          cell.font = { bold: true };
          const vInformado = grupoAncora ? valorNumDoGrupo(grupoAncora, col.key) : null;
          if (vInformado != null && informadoIdx != null) {
            // O documento disse quanto é: o cabeçalho APONTA para a célula do
            // valor extraído (fórmula, não valor colado — a planilha continua
            // viva e a proveniência fica a um clique).
            cell.value = { formula: `${colLetra(i)}${informadoIdx}` } as ExcelJS.CellFormulaValue;
            cell.numFmt = VALOR_NUM_FMT;
            subtotalNum.set(col.key, vInformado);
          } else if (temContas) {
            // O documento não trouxe o total desta coluna: soma as contas-folha.
            cell.value = { formula: `SUM(${colLetra(i)}${primeira}:${colLetra(i)}${ultima})` } as ExcelJS.CellFormulaValue;
            cell.numFmt = VALOR_NUM_FMT;
          }
        });
        noRow.set(no.key, cabIdx);
        noValor.set(no.key, new Map(subtotalNum));
        linhasValor.add(cabIdx);
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
      // Grupo sem nenhum filho com dado e sem total informado: não existe neste
      // documento. Devolve a linha reservada ao pool e não emite nada.
      const temAncoraPai = valoresPorAncora.has(no.key);
      if (filhosIdx.length === 0 && !temAncoraPai) {
        if (cabIdx === rowIndex - 1) rowIndex--; // nada foi escrito depois: reaproveita
        return null;
      }
      // Mesma regra do nó folha: o total que o documento informou manda, e a
      // soma dos filhos vira linha de checagem.
      const informadoPaiIdx = temAncoraPai
        ? escreverConferenciaExtraido(no.nivel, no.key, cabIdx, subtotalNum)
        : null;
      if (temAncoraPai && filhosIdx.length && informadoPaiIdx != null) {
        escreverSomaCalculada(no.nivel, "soma das seções acima",
          (i) => filhosIdx.map((r) => `${colLetra(i)}${r}`).join("+"));
      }
      const grupoAncoraPai = temAncoraPai ? valoresPorAncora.get(no.key)! : null;
      const row = sheet.getRow(cabIdx);
      row.getCell(1).value = no.label;
      row.getCell(1).alignment = { indent: no.nivel };
      row.font = { bold: true };
      row.fill = fill;
      const dupla = no.papel === "grupo";
      colunas.forEach((col, i) => {
        const cell = row.getCell(plano.valuePos[i]);
        cell.font = { bold: true };
        const vInformado = grupoAncoraPai ? valorNumDoGrupo(grupoAncoraPai, col.key) : null;
        if (vInformado != null && informadoPaiIdx != null) {
          cell.value = { formula: `${colLetra(i)}${informadoPaiIdx}` } as ExcelJS.CellFormulaValue;
          cell.numFmt = VALOR_NUM_FMT;
          subtotalNum.set(col.key, vInformado);
        } else if (filhosIdx.length) {
          cell.value = { formula: filhosIdx.map((r) => `${colLetra(i)}${r}`).join("+") } as ExcelJS.CellFormulaValue;
          cell.numFmt = VALOR_NUM_FMT;
        }
        if (dupla) cell.border = DOUBLE_TOP_BORDER;
      });
      noRow.set(no.key, cabIdx);
      noValor.set(no.key, new Map(subtotalNum));
      linhasValor.add(cabIdx);
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
      const contas = [...(contasPorSecao.get(secao.key)?.values() ?? [])];
      const temSubtotalInformado = (subtotaisInformados.get(secao.key)?.size ?? 0) > 0;
      // Seção que o documento não tem: não é emitida. O template canônico ordena
      // o que existe, não impõe blocos vazios.
      if (contas.length === 0 && !temSubtotalInformado) continue;

      // O cabeçalho da seção CARREGA O SUBTOTAL DA SEÇÃO, não só o rótulo.
      // Antes era linha só de texto — 8 linhas 100% vazias entre DRE e Fluxo de
      // Caixa ("Custos", "Despesas Operacionais", "Atividades Operacionais"…).
      // E o número é o que uma DRE real imprime: o total de custos e o total de
      // despesas operacionais são leitura de primeira ordem, distinta da cascata
      // acumulada que a âncora abaixo mostra.
      const cabIdx = rowIndex++;
      const primeira = rowIndex;
      const somaSecao = new Map<string, number>();
      for (const conta of contas) {
        escrever(conta.label, 1, conta);
        colunas.forEach((col) => {
          const v = valorNumDoGrupo(conta, col.key);
          if (v != null) somaSecao.set(col.key, (somaSecao.get(col.key) ?? 0) + v);
        });
      }
      const ultima = rowIndex - 1;
      escreverSubtotaisInformados(secao.key, 1);

      const hdr = sheet.getRow(cabIdx);
      hdr.getCell(1).value = secao.label;
      hdr.getCell(1).alignment = { indent: 0 };
      hdr.font = { bold: true };
      hdr.fill = SECAO_FILL;
      if (ultima >= primeira) {
        hdr.getCell(1).note = comoNota(
          "Total desta seção — soma das contas listadas abaixo. Não confundir com a linha de "
          + "resultado que vem depois: na DRE ela é cumulativa (traz o resultado acumulado até "
          + "ali), esta é só do bloco.",
        );
        colunas.forEach((col, i) => {
          if (somaSecao.get(col.key) == null) return;
          const cell = hdr.getCell(plano.valuePos[i]);
          cell.value = { formula: `SUM(${colLetra(i)}${primeira}:${colLetra(i)}${ultima})` } as ExcelJS.CellFormulaValue;
          cell.numFmt = VALOR_NUM_FMT;
          cell.font = { bold: true };
        });
        linhasValor.add(cabIdx);
      }
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
  // O título carrega o TOTAL do bloco por coluna. Deixa de ser linha vazia e
  // passa a responder a pergunta que o analista faz primeiro: "quanto de valor
  // está fora das seções?" — se for material, a planilha ainda não está pronta
  // para virar modelo.
  if (naoClassificados.size > 0) {
    rowIndex++; // linha em branco
    const tituloIdx = rowIndex++;
    const primeiraNC = rowIndex;
    for (const conta of naoClassificados.values()) escrever(conta.label, 1, conta);
    const ultimaNC = rowIndex - 1;
    const tituloRow = sheet.getRow(tituloIdx);
    tituloRow.getCell(1).value = "Contas Não Classificadas (revisar manualmente)";
    tituloRow.font = { bold: true, italic: true };
    tituloRow.fill = NAO_CLASSIFICADO_FILL;
    tituloRow.getCell(1).note = comoNota(
      "Contas que o classificador não colocou numa seção com segurança. O valor ao lado é o total "
      + "do bloco: quanto maior, menos a planilha está pronta para virar modelo. Nada foi "
      + "descartado — cada conta aparece abaixo com o rótulo original.",
    );
    if (ultimaNC >= primeiraNC) {
      colunas.forEach((col, i) => {
        let tem = false;
        for (const conta of naoClassificados.values()) {
          if (valorNumDoGrupo(conta, col.key) != null) { tem = true; break; }
        }
        if (!tem) return;
        const cell = tituloRow.getCell(plano.valuePos[i]);
        cell.value = { formula: `SUM(${colLetra(i)}${primeiraNC}:${colLetra(i)}${ultimaNC})` } as ExcelJS.CellFormulaValue;
        cell.numFmt = VALOR_NUM_FMT;
        cell.font = { bold: true, italic: true };
      });
    }
  }

  // ----- Camada analítica (f0/08): AV% (common-size) e Δ% (tendência). -----
  // Fórmulas transparentes sobre as MESMAS células de valor já escritas — não
  // inventam nada; a linha subjacente segue pendente/âmbar até o aceite.
  preencherAnaliseVerticalHorizontal(sheet, plano, [...linhasValor], baseTotalRow);

  // ----- Indicadores de liquidez/estrutura (Balanço) — f0/08. -----
  if (estrutura === "balanco") {
    escreverIndicadoresBalanco(sheet, plano, colunas, noRow, noValor, () => rowIndex++);
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
  noValor: Map<string, Map<string, number>>,
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
  // Valor de um nó na coluna i (null quando o nó não existe ou a coluna está
  // vazia) — é com isso que decidimos se o índice resolve de verdade.
  const val = (i: number, chave: string): number | null => {
    const v = noValor.get(chave)?.get(colunas[i].key);
    return typeof v === "number" ? v : null;
  };
  const soma = (i: number, chaves: string[]): number | null => {
    let t: number | null = null;
    for (const c of chaves) {
      const v = val(i, c);
      if (v != null) t = (t ?? 0) + v;
    }
    return t;
  };
  // Um índice só é emitido se, em ALGUMA coluna, numerador e denominador
  // existem e o denominador não é zero.
  const razaoResolve = (i: number, num: string[], den: string[]): boolean => {
    const n = soma(i, num);
    const d = soma(i, den);
    return n != null && d != null && d !== 0;
  };

  const indicadores: Array<{
    label: string; fmt: string;
    formula: (i: number) => string | null;
    resolve: (i: number) => boolean;
  }> = [
    {
      label: "Liquidez Corrente (AC ÷ PC)", fmt: RATIO_FMT,
      formula: (i) => `${cel(i, AC)}/${cel(i, PC)}`,
      resolve: (i) => razaoResolve(i, ["ativo_circulante"], ["passivo_circulante"]),
    },
    {
      label: "Liquidez Geral ((AC + Realizável LP) ÷ (PC + PNC))",
      fmt: RATIO_FMT,
      formula: (i) => {
        const ac = cel(i, AC)!;
        const rlp = cel(i, RLP);
        const num = rlp ? `(${ac}+${rlp})` : ac;
        return `${num}/(${cel(i, PC)}+${cel(i, PNC)})`;
      },
      resolve: (i) => razaoResolve(i, ["ativo_circulante", "realizavel_lp"], ["passivo_circulante", "passivo_nao_circulante"]),
    },
    {
      label: "Endividamento Geral ((PC + PNC) ÷ Ativo Total)", fmt: PCT_FMT,
      formula: (i) => `(${cel(i, PC)}+${cel(i, PNC)})/${cel(i, ATV)}`,
      resolve: (i) => razaoResolve(i, ["passivo_circulante", "passivo_nao_circulante"], ["ATIVO"]),
    },
    {
      label: "Composição do Endividamento (PC ÷ (PC + PNC))", fmt: PCT_FMT,
      formula: (i) => `${cel(i, PC)}/(${cel(i, PC)}+${cel(i, PNC)})`,
      resolve: (i) => razaoResolve(i, ["passivo_circulante"], ["passivo_circulante", "passivo_nao_circulante"]),
    },
    {
      label: "Participação de Capital de Terceiros ((PC + PNC) ÷ PL)", fmt: PCT_FMT,
      formula: (i) => `(${cel(i, PC)}+${cel(i, PNC)})/${cel(i, PL)}`,
      resolve: (i) => razaoResolve(i, ["passivo_circulante", "passivo_nao_circulante"], ["patrimonio_liquido"]),
    },
    {
      label: "Imobilização do PL ((Imob. + Invest. + Intang.) ÷ PL)",
      fmt: PCT_FMT,
      formula: (i) => {
        const partes = [cel(i, IMOB), cel(i, INV), cel(i, INT)].filter(Boolean);
        if (partes.length === 0) return null;
        return `(${partes.join("+")})/${cel(i, PL)}`;
      },
      resolve: (i) => razaoResolve(i, ["imobilizado", "investimentos", "intangivel"], ["patrimonio_liquido"]),
    },
  ];

  // Só indicadores que TÊM fórmula em pelo menos uma coluna. Um índice cujos
  // insumos não existem na extração (ex.: Imobilização do PL num combinado que
  // não detalha Imobilizado) sairia como linha 100% vazia — e linha vazia numa
  // planilha de entrega parece defeito, não parece "insumo indisponível".
  const comValor = indicadores.filter((ind) =>
    colunas.some((_, i) => ind.formula(i) != null && ind.resolve(i)));
  if (comValor.length === 0) return;

  // Sem linha de título própria (era a última linha 100% vazia do Balanço): o
  // bloco é aberto pela borda dupla e pela nota no primeiro índice. Os rótulos
  // já explicitam a fórmula de cada um, então nada se perde.
  const NOTA_BLOCO = comoNota(
    "Início do bloco de INDICADORES DE LIQUIDEZ E ESTRUTURA: índices calculados por fórmula sobre os "
    + "subtotais extraídos deste Balanço (Matarazzo/Assaf Neto; f0/08). Não são linhas do documento. "
    + "Célula vazia = insumo não disponível na extração (nunca estimado). Índices que exigem "
    + "detalhamento de conta ainda não isolado (liquidez seca/imediata, cobertura de juros, dívida "
    + "líquida/EBITDA, ciclo de caixa, ROA/ROE, Altman Z'') ficam de fora desta versão — ver f0/08. "
    + "Valores derivados de linhas ainda PENDENTES seguem pendentes até o aceite humano.",
  );

  proximaLinha(); // linha em branco separando do balanço
  comValor.forEach((ind, ordem) => {
    const r = proximaLinha();
    const row = sheet.getRow(r);
    row.getCell(1).value = ind.label;
    row.getCell(1).font = INDICADOR_LABEL_FONT;
    if (ordem === 0) {
      row.getCell(1).font = { ...INDICADOR_LABEL_FONT, bold: true };
      row.getCell(1).fill = INDICADOR_TITULO_FILL;
      row.getCell(1).note = NOTA_BLOCO;
      row.getCell(1).border = DOUBLE_TOP_BORDER;
    }
    colunas.forEach((_, i) => {
      const f = ind.formula(i);
      if (!f) return;
      const cell = row.getCell(plano.valuePos[i]);
      cell.value = { formula: `IFERROR(${f},"")` } as ExcelJS.CellFormulaValue;
      cell.numFmt = ind.fmt;
      if (ordem === 0) cell.border = DOUBLE_TOP_BORDER;
    });
  });
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
  linhas.sort((a, b) => compararColunas(a, b) || a.secao.localeCompare(b.secao));

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

// ---------------------------------------------------------------------------
// DMPL e DVA (db/migrations/0024). As duas são demonstrações inteiras, mas
// nenhuma passa pelo `construirAbaClassificada`: aquele caminho existe para
// template de seções + subtotal em FÓRMULA (Balanço/DRE/Fluxo), e nem a DMPL
// nem a DVA têm um template nosso. Aqui vale o princípio travado na sessão 10:
// o que sai é o que o documento trouxe, na ordem em que ele trouxe — nenhuma
// linha imposta, nenhum subtotal calculado por nós (anti-ancoragem, f0/07).
// Por construção, então, toda linha destas abas nasce de uma linha extraída:
// não existe aqui a classe de defeito que o invariante 8 persegue nas abas com
// template (linha em branco emitida às cegas).
// ---------------------------------------------------------------------------
interface RegistroDemonstracao {
  campo: CampoExtraido;
  ctx: ContextoVersao;
  entidade: string;
  periodo: string;
}

const MOVIMENTO_SEM_ROTULO = "(movimento não informado)";
const SECAO_SEM_ROTULO = "(sem seção informada)";

// Chave estável para alinhar o MESMO rótulo escrito com grafias diferentes
// (plural, acento, caixa) sem forçar nome canônico — o rótulo exibido é sempre
// o primeiro que apareceu, como no resto do export.
function ordemPorPrimeiraAparicao() {
  const ordem = new Map<string, string>(); // chave normalizada → rótulo exibido
  return {
    registrar(rotulo: string) {
      const k = normalizar(rotulo);
      if (!ordem.has(k)) ordem.set(k, rotulo);
      return k;
    },
    lista(): Array<[string, string]> {
      return [...ordem.entries()];
    },
  };
}

// A DMPL é uma MATRIZ: as linhas são MOVIMENTOS do exercício ("SALDOS EM 31 DE
// DEZEMBRO DE 2024", "Prejuízo líquido do exercício") e as colunas são
// COMPONENTES do PL ("Capital social", "Reserva legal", "Prejuízos acumulados",
// "Total"). Achatá-la numa listagem perderia justamente a leitura que a
// demonstração existe para dar (como cada componente do PL se moveu), então a
// aba reconstrói a matriz: um bloco por entidade×período, cabeçalho com os
// componentes, uma linha por movimento. `secao` = movimento e `chave` =
// componente é o contrato que o prompt de extração pede (n8n/lib/extract.mjs).
function construirAbaDMPL(workbook: ExcelJS.Workbook, nomeAba: string, registros: RegistroDemonstracao[]) {
  const blocos = new Map<string, { entidade: string; periodo: string; registros: RegistroDemonstracao[] }>();
  for (const reg of registros) {
    const key = `${reg.entidade}${CHAVE_SEP}${reg.periodo}`;
    if (!blocos.has(key)) blocos.set(key, { entidade: reg.entidade, periodo: reg.periodo, registros: [] });
    blocos.get(key)!.registros.push(reg);
  }

  const sheet = workbook.addWorksheet(nomeAba, { views: [{ state: "frozen", ySplit: 1 }] });
  let larguraMax = 0;

  for (const bloco of [...blocos.values()].sort(compararColunas)) {
    const componentes = ordemPorPrimeiraAparicao();
    const movimentos = ordemPorPrimeiraAparicao();
    const celulas = new Map<string, RegistroDemonstracao[]>();
    for (const reg of bloco.registros) {
      const comp = componentes.registrar(reg.campo.chave);
      const mov = movimentos.registrar(reg.campo.secao ?? MOVIMENTO_SEM_ROTULO);
      const k = `${mov}${CHAVE_SEP}${comp}`;
      if (!celulas.has(k)) celulas.set(k, []);
      celulas.get(k)!.push(reg);
    }

    const colunasComp = componentes.lista();
    larguraMax = Math.max(larguraMax, colunasComp.length + 1);

    // O título do bloco vive na MESMA linha do cabeçalho dos componentes (em
    // vez de uma linha só de título): uma linha com rótulo e nenhum valor é
    // exatamente o que o invariante 8 chama de linha vazia.
    const header = sheet.addRow([
      `Movimento — ${bloco.entidade} (${bloco.periodo})`,
      ...colunasComp.map(([, label]) => label),
    ]);
    header.font = { bold: true };
    header.eachCell((cell) => {
      cell.fill = HEADER_FILL;
      cell.alignment = { wrapText: true, vertical: "bottom" };
    });

    for (const [movKey, movLabel] of movimentos.lista()) {
      const row = sheet.addRow([movLabel]);
      let algumPendente = false;
      colunasComp.forEach(([compKey], i) => {
        const candidatos = celulas.get(`${movKey}${CHAVE_SEP}${compKey}`);
        if (!candidatos || candidatos.length === 0) return;
        const melhor = melhorCampo(candidatos.map((r) => r.campo));
        const { ctx } = candidatos.find((r) => r.campo === melhor)!;
        const cell = row.getCell(i + 2);
        cell.value = melhor.valor_num ?? melhor.valor_texto ?? null;
        if (typeof cell.value === "number") cell.numFmt = VALOR_NUM_FMT;
        cell.note = comoNota(notaProveniencia(melhor, ctx));
        if (melhor.status_aceite !== "aceito") {
          cell.fill = PENDENTE_FILL;
          algumPendente = true;
        }
      });
      // Saldo de abertura/fechamento é a moldura da demonstração — negrito e
      // filete, como sai no PDF publicado.
      if (/\bsaldos?\b/i.test(movLabel)) {
        row.font = { bold: true };
        row.eachCell((cell) => {
          cell.border = THIN_TOP_BORDER;
        });
      }
      if (algumPendente) row.font = { ...row.font, italic: true };
    }

    sheet.addRow([]); // respiro entre blocos (sem rótulo — o invariante 8 pula)
  }

  sheet.getColumn(1).width = 46;
  for (let c = 2; c <= Math.max(larguraMax, 2); c++) sheet.getColumn(c).width = 20;
}

// A DVA (CPC 09) é uma cascata de seções — geração do valor adicionado e sua
// distribuição. Não escrevemos um template dela: a demonstração é padronizada
// pelo CPC, mas não temos nenhum arquivo real para validar um, e um template
// errado ordenaria o dado errado em silêncio. A aba apresenta o que o documento
// trouxe, na ordem dele, com a seção declarada numa coluna própria — e as
// colunas de valor são entidade×período, como nas demais demonstrações.
function construirAbaDocumental(workbook: ExcelJS.Workbook, nomeAba: string, registros: RegistroDemonstracao[]) {
  const colunas = new Map<string, Coluna>();
  for (const reg of registros) {
    const key = `${reg.entidade}${CHAVE_SEP}${reg.periodo}`;
    if (!colunas.has(key)) colunas.set(key, { key, entidade: reg.entidade, periodo: reg.periodo });
  }
  const ordemColunas = [...colunas.values()].sort(compararColunas);
  const posColuna = new Map(ordemColunas.map((c, i) => [c.key, i + 3]));

  const secoes = ordemPorPrimeiraAparicao();
  const linhas = new Map<string, { secaoLabel: string; rotulo: string; porColuna: Map<string, RegistroDemonstracao[]> }>();
  for (const reg of registros) {
    const secaoKey = secoes.registrar(reg.campo.secao ?? SECAO_SEM_ROTULO);
    const k = `${secaoKey}${CHAVE_SEP}${normalizar(reg.campo.chave)}`;
    if (!linhas.has(k)) {
      linhas.set(k, {
        secaoLabel: reg.campo.secao ?? SECAO_SEM_ROTULO,
        rotulo: reg.campo.chave,
        porColuna: new Map(),
      });
    }
    const alvo = linhas.get(k)!;
    const colKey = `${reg.entidade}${CHAVE_SEP}${reg.periodo}`;
    if (!alvo.porColuna.has(colKey)) alvo.porColuna.set(colKey, []);
    alvo.porColuna.get(colKey)!.push(reg);
  }

  const sheet = workbook.addWorksheet(nomeAba, { views: [{ state: "frozen", ySplit: 1, xSplit: 2 }] });
  sheet.columns = [
    { header: "Rótulo", width: 46 },
    { header: "Seção declarada no documento", width: 32 },
    ...ordemColunas.map((c) => ({ header: `${c.entidade} — ${c.periodo}`, width: 20 })),
  ];
  sheet.getRow(1).font = { bold: true };
  sheet.getRow(1).eachCell((cell) => {
    cell.fill = HEADER_FILL;
    cell.alignment = { wrapText: true, vertical: "bottom" };
  });

  for (const linha of linhas.values()) {
    const row = sheet.addRow([linha.rotulo, linha.secaoLabel]);
    let algumPendente = false;
    for (const [colKey, regs] of linha.porColuna) {
      const pos = posColuna.get(colKey);
      if (!pos) continue;
      const melhor = melhorCampo(regs.map((r) => r.campo));
      const reg = regs.find((r) => r.campo === melhor)!;
      const cell = row.getCell(pos);
      cell.value = melhor.valor_num ?? melhor.valor_texto ?? null;
      if (typeof cell.value === "number") cell.numFmt = VALOR_NUM_FMT;
      cell.note = comoNota(notaProveniencia(melhor, reg.ctx));
      if (melhor.status_aceite !== "aceito") {
        cell.fill = PENDENTE_FILL;
        algumPendente = true;
      }
    }
    row.getCell(2).font = { size: 9, color: { argb: "FF64748B" } };
    if (/total|valor adicionado/i.test(linha.rotulo)) row.font = { bold: true };
    if (algumPendente) row.font = { ...row.font, italic: true };
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
  // DMPL/DVA (0024): nem grade classificada (não têm template) nem listagem
  // simples (perderiam a leitura da demonstração) — ver construirAbaDMPL /
  // construirAbaDocumental.
  const registrosPorAba = new Map<string, RegistroDemonstracao[]>();

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
    // `periodo_coluna` vem CRU da extração ("2024", "31/12/2024") enquanto
    // `ctx.periodo` já passou por `formatarPeriodo` — sem normalizar os dois do
    // mesmo jeito, o MESMO período aparecia em duas colunas distintas ("2024" e
    // "2024" formatado de outra fonte) e os rótulos saíam inconsistentes na
    // mesma aba. Formatar aqui colapsa a coluna e alinha a escrita.
    const periodoColuna = campo.periodo_coluna
      ? formatarPeriodo(null, campo.periodo_coluna)
      : ctx.periodo;
    // Separador improvável na chave: com espaço simples, entidade "A B" +
    // período "C" colidia com entidade "A" + período "B C" (colunas de
    // entidade×período diferentes fundidas numa só).
    const colKey = `${entidadeColuna}${CHAVE_SEP}${periodoColuna}`;
    const estrutura = ESTRUTURA_POR_ABA.get(aba);

    if (aba === ABA_DMPL || aba === ABA_DVA) {
      if (!registrosPorAba.has(aba)) registrosPorAba.set(aba, []);
      registrosPorAba.get(aba)!.push({ campo, ctx, entidade: entidadeColuna, periodo: periodoColuna });
    } else if (estrutura) {
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
    if (aba === ABA_DMPL || aba === ABA_DVA) {
      const registros = registrosPorAba.get(aba);
      if (!registros || registros.length === 0) continue;
      if (aba === ABA_DMPL) construirAbaDMPL(workbook, aba, registros);
      else construirAbaDocumental(workbook, aba, registros);
    } else if (estrutura) {
      const colunas = [...(colunasPorAba.get(aba)?.values() ?? [])].sort(compararColunas);
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
