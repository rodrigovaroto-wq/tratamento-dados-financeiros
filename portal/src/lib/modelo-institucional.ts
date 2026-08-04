import ExcelJS from "exceljs";
import { comoNota, HEADER_FILL, THIN_TOP_BORDER } from "./export-estilo";

// =============================================================================
// O MODELO INSTITUCIONAL — reconstrução do "Modelo Base" do dono, integrada aos
// dados e às premissas deste sistema.
//
// O QUE É O MODELO BASE. Um modelo de projeção de três demonstrações, de 14 abas,
// com switch de cenário, cascata de receita, capital de giro por dias de giro,
// cronograma de dívida com revolver, capex com depreciação por safra, fluxo de
// caixa indireto e um Output de métricas de crédito. É o formato que a casa usa,
// e é o alvo de fidelidade: MESMOS nomes de aba, MESMA semântica de linha, MESMO
// mecanismo de cenário.
//
// O QUE MUDA EM RELAÇÃO AO ARQUIVO DE REFERÊNCIA, e por quê:
//
//   1. OS NÚMEROS HISTÓRICOS SAEM DO BANCO, não são digitados. A aba `Premissas`
//      é montada com as linhas EXTRAÍDAS do caso (`fn_linhas_para_modelagem`),
//      com proveniência por célula. No arquivo de referência elas eram valores
//      colados — que é justamente o que este sistema existe para eliminar.
//   2. A aba `Anual` (base macro) sai de `indice_macro_obs` + Focus, versionados,
//      em vez de uma planilha de consultoria de 1994 a 2014.
//   3. A CIRCULARIDADE FOI QUEBRADA DE PROPÓSITO — ver `NOTA_CIRCULARIDADE`.
//   4. Nenhuma linha é projetada sem premissa vinculada. Onde o referência tinha
//      "Item 2/Item 3" como espaço reservado, aqui aparecem as linhas REAIS do
//      caso; linha sem premissa fica no arquivo dizendo que não é projetada.
//
// POR QUE FÓRMULA E NÃO VALOR: o arquivo é entregue para o cliente e para o
// credor mexerem. Um modelo com valores calculados fora do Excel é um relatório;
// um modelo com fórmula é um modelo. Toda projeção aqui é fórmula que aponta para
// a célula de premissa — mudar a premissa move o modelo inteiro.
// =============================================================================

// -----------------------------------------------------------------------------
// A DECISÃO DE ENGENHARIA MAIS IMPORTANTE DESTE ARQUIVO.
//
// O modelo de referência é CIRCULAR: despesa financeira → lucro → caixa →
// revolver → despesa financeira. Ele depende do cálculo iterativo do Excel
// (Arquivo → Opções → Fórmulas → Habilitar cálculo iterativo). Isso tem três
// consequências ruins para um entregável institucional:
//
//   • fora do Excel (LibreOffice, Google Sheets, visualizador do navegador) a
//     referência circular resolve para ZERO ou #VALUE! sem avisar — e quem abre
//     não sabe que está lendo um modelo que não convergiu;
//   • nenhum teste automático consegue verificar o arquivo: não há como avaliar
//     uma referência circular sem reimplementar o motor iterativo;
//   • duas pessoas com configurações diferentes de Excel leem NÚMEROS diferentes
//     do MESMO arquivo, e nada na tela denuncia.
//
// Então aqui o laço é cortado no ponto onde ele custa menos precisão: juros e
// rendimentos incidem sobre o saldo de ABERTURA do período (o que o próprio
// modelo de referência já faz na linha do revolver: `=J58*I51`, margem do período
// × revolver do período ANTERIOR). O arquivo declara isso na aba `Considerações`
// e em nota na célula, porque é uma divergência de método e quem audita precisa
// saber. Não é aproximação escondida: é escolha registrada.
// -----------------------------------------------------------------------------
const NOTA_CIRCULARIDADE =
  "Juros e rendimentos financeiros incidem sobre o saldo de ABERTURA do período. "
  + "O modelo de referência os calcula sobre a média (abertura, fechamento), o que cria "
  + "referência circular e exige cálculo iterativo do Excel. Fora do Excel, referência "
  + "circular resolve para zero SEM AVISO, e nenhum teste consegue verificar o arquivo. "
  + "A diferença é de ordem de meio período de juros e está documentada aqui de propósito.";

export const ABAS_MODELO = [
  "Considerações", "Capa", "Output", "Revenues, COGS & SG&A", "Premissas",
  "Income Statement", "Balance Sheet", "Working Capital", "ST Inv. & Debt",
  "Fixed Assets & CAPEX", "Cash Flow", "Goodwill, Taxes & Div.", "Anual",
  "Tributos a Recolher",
] as const;

// Colunas. B = sinal, C = rótulo, D = premissa/unidade, E em diante = períodos.
const COL_SINAL = 2;
const COL_ROTULO = 3;
const COL_NOTA = 4;
const COL_PRIMEIRO_ANO = 5;

const CENARIOS = ["Base Case", "Cliente Case", "Stress Case"] as const;

// Estilo. Sóbrio de propósito: modelo de crédito é lido em impressão preto e
// branco por comitê, e cor que não sobrevive ao papel não carrega informação.
const FONTE_BLOCO: Partial<ExcelJS.Font> = { bold: true, size: 11 };
const FILL_BLOCO: ExcelJS.Fill = { type: "pattern", pattern: "solid", fgColor: { argb: "FF1E293B" } };
const FONTE_BLOCO_INV: Partial<ExcelJS.Font> = { bold: true, size: 11, color: { argb: "FFFFFFFF" } };
const FILL_INPUT: ExcelJS.Fill = { type: "pattern", pattern: "solid", fgColor: { argb: "FFFFF9C4" } };
const FILL_HIST: ExcelJS.Fill = { type: "pattern", pattern: "solid", fgColor: { argb: "FFF3F4F6" } };
const FILL_CHECK_OK: ExcelJS.Fill = { type: "pattern", pattern: "solid", fgColor: { argb: "FFDCFCE7" } };
const FILL_CHECK_ERRO: ExcelJS.Fill = { type: "pattern", pattern: "solid", fgColor: { argb: "FFFEE2E2" } };
const NUM = "#,##0;(#,##0)";
const NUM2 = "#,##0.00;(#,##0.00)";
const PCT = "0.0%";
const MULT = "0.00x";

// -----------------------------------------------------------------------------
// Entrada
// -----------------------------------------------------------------------------
export interface LinhaModelo {
  secao_canonica: string | null;
  chave: string;
  rotulo_norm: string;
  papel: "conta" | "subtotal" | "derivado" | "serie_mensal";
  unidade: string | null;
  moeda: string | null;
  documentos: string[] | null;
  /** valor por ano, do histórico extraído */
  valores: Record<string, number>;
}

export interface PremissaModelo {
  codigo: string;
  nome: string;
  natureza: string;
  formula: string;
  unidade: string | null;
  valores: Record<string, number>;
  origem: string | null;
}

export interface VinculoModelo {
  rotulo_norm: string;
  premissa_codigo: string | null;
  sazonalidade_codigo: string | null;
}

export interface EntradaModeloInstitucional {
  caso: { nome: string; produto: string };
  agora: Date;
  entidade: string | null;
  setor: string | null;
  anosHistoricos: number[];
  anosProjetados: number[];
  /** haircut do cenário Stress sobre as premissas do Base (0.20 = -20%) */
  stressPct: number;
  /** caixa mínimo operacional; abaixo dele o revolver é acionado */
  caixaMinimo: number;
  aliquotaTributos: number;
  linhas: LinhaModelo[];
  premissas: PremissaModelo[];
  vinculos: VinculoModelo[];
  macro: { serie: string; ano: number; valor: number; fonte: string }[];
  /** unidade dominante das linhas (milhar/unidade), para o cabeçalho das abas */
  unidade: string;
}

// -----------------------------------------------------------------------------
// Infra de escrita. Um `Grade` por aba: escreve linha a linha, guarda a âncora de
// cada linha por chave, e sabe converter (linha, ano) em referência A1.
//
// POR QUE ÂNCORA E NÃO NÚMERO LITERAL: no export-modelagem, escrever `getRow(189)`
// no meio da montagem já criou linha fantasma e empurrou o modelo 90 linhas (duas
// vezes, em duas sessões). Aqui nenhum número de linha aparece em fórmula: só
// `g.ref("EBITDA", ano)`.
// -----------------------------------------------------------------------------
function colLetra(n: number): string {
  let s = "";
  while (n > 0) {
    const r = (n - 1) % 26;
    s = String.fromCharCode(65 + r) + s;
    n = Math.floor((n - 1) / 26);
  }
  return s;
}

class Grade {
  readonly ws: ExcelJS.Worksheet;
  private anchors = new Map<string, number>();
  private cursor = 0;
  readonly anos: number[];
  readonly nHist: number;

  constructor(wb: ExcelJS.Workbook, nome: string, anos: number[], nHist: number) {
    this.ws = wb.addWorksheet(nome);
    this.anos = anos;
    this.nHist = nHist;
    this.ws.getColumn(COL_ROTULO).width = 46;
    this.ws.getColumn(COL_NOTA).width = 22;
    for (let i = 0; i < anos.length; i++) this.ws.getColumn(COL_PRIMEIRO_ANO + i).width = 13;
    this.ws.getColumn(COL_SINAL).width = 4;
    this.ws.getColumn(1).width = 2;
  }

  /** Coluna (índice) do ano. Lança se o ano não existe — erro de programação. */
  colDoAno(ano: number): number {
    const i = this.anos.indexOf(ano);
    if (i < 0) throw new Error(`modelo-institucional: ano ${ano} fora do horizonte`);
    return COL_PRIMEIRO_ANO + i;
  }

  letraDoAno(ano: number): string { return colLetra(this.colDoAno(ano)); }
  ehProjetado(ano: number): boolean { return this.anos.indexOf(ano) >= this.nHist; }
  anoAnterior(ano: number): number | null {
    const i = this.anos.indexOf(ano);
    return i > 0 ? this.anos[i - 1] : null;
  }

  proximaLinha(): number { return this.cursor + 1; }
  pular(n = 1): void { this.cursor += n; }

  /** Registra uma linha e devolve o seu número. */
  linha(chave: string | null, opts: {
    rotulo?: string; sinal?: string; nota?: string; bloco?: boolean;
    negrito?: boolean; topo?: boolean; fmt?: string;
  } = {}): number {
    const r = ++this.cursor;
    if (chave) {
      if (this.anchors.has(chave)) {
        // Chave duplicada silenciosa faria toda fórmula apontar para a PRIMEIRA
        // linha com aquele nome — e o modelo somaria a conta errada, sem avisar.
        throw new Error(`modelo-institucional: âncora duplicada "${chave}" em ${this.ws.name}`);
      }
      this.anchors.set(chave, r);
    }
    const row = this.ws.getRow(r);
    if (opts.sinal) row.getCell(COL_SINAL).value = opts.sinal;
    if (opts.rotulo !== undefined) row.getCell(COL_ROTULO).value = opts.rotulo;
    if (opts.nota !== undefined) row.getCell(COL_NOTA).value = opts.nota;
    if (opts.bloco) {
      for (let c = COL_SINAL; c < COL_PRIMEIRO_ANO + this.anos.length; c++) {
        row.getCell(c).fill = FILL_BLOCO;
        row.getCell(c).font = FONTE_BLOCO_INV;
      }
    } else if (opts.negrito) {
      row.getCell(COL_ROTULO).font = FONTE_BLOCO;
    }
    if (opts.topo) {
      for (let c = COL_ROTULO; c < COL_PRIMEIRO_ANO + this.anos.length; c++) {
        row.getCell(c).border = THIN_TOP_BORDER;
      }
    }
    if (opts.fmt) {
      for (let i = 0; i < this.anos.length; i++) {
        row.getCell(COL_PRIMEIRO_ANO + i).numFmt = opts.fmt;
      }
    }
    return r;
  }

  tem(chave: string): boolean { return this.anchors.has(chave); }

  n(chave: string): number {
    const r = this.anchors.get(chave);
    if (r === undefined) throw new Error(`modelo-institucional: âncora "${chave}" não existe em ${this.ws.name}`);
    return r;
  }

  /** Referência A1 local: `ref("EBITDA", 2027)` → "J42". */
  ref(chave: string, ano: number, fixo: "" | "$" = ""): string {
    return `${fixo}${this.letraDoAno(ano)}${fixo}${this.n(chave)}`;
  }

  /** Referência para outra aba. O nome vai entre apóstrofos: há abas com "&". */
  static refExterna(aba: string, coluna: string, linha: number): string {
    return `'${aba.replace(/'/g, "''")}'!${coluna}${linha}`;
  }

  externa(aba: string, g: Grade, chave: string, ano: number): string {
    return Grade.refExterna(aba, g.letraDoAno(ano), g.n(chave));
  }

  /** Escreve valor/fórmula na célula (linha por chave, coluna por ano). */
  set(chave: string, ano: number, v: number | string | null, opts: {
    fmt?: string; fill?: ExcelJS.Fill; nota?: string; negrito?: boolean;
  } = {}): ExcelJS.Cell {
    const cell = this.ws.getRow(this.n(chave)).getCell(this.colDoAno(ano));
    if (typeof v === "string" && v.startsWith("=")) cell.value = { formula: v.slice(1) };
    else if (v !== null) cell.value = v;
    if (opts.fmt) cell.numFmt = opts.fmt;
    if (opts.fill) cell.fill = opts.fill;
    if (opts.negrito) cell.font = FONTE_BLOCO;
    if (opts.nota) cell.note = comoNota(opts.nota);
    return cell;
  }

  /** Célula avulsa (fora da grade de anos), por endereço absoluto. */
  celula(linha: number, col: number): ExcelJS.Cell {
    return this.ws.getRow(linha).getCell(col);
  }

  cabecalho(titulo: string, unidade: string, refAno?: (ano: number) => string): void {
    const rTit = this.linha("__titulo", { rotulo: titulo, negrito: true });
    this.ws.getRow(rTit).getCell(COL_ROTULO).font = { bold: true, size: 12 };
    for (const ano of this.anos) {
      const cell = this.ws.getRow(rTit).getCell(this.colDoAno(ano));
      cell.value = refAno ? { formula: refAno(ano).slice(1) } : ano;
      cell.font = { bold: true };
      cell.alignment = { horizontal: "right" };
      cell.fill = this.ehProjetado(ano) ? HEADER_FILL : FILL_HIST;
    }
    this.linha("__unidade", { rotulo: unidade });
    this.pular();
  }

  /** A célula do cenário: toda aba lê `Output` para não haver dois interruptores. */
  ancoraCenario(): void {
    const c = this.ws.getRow(1).getCell(COL_NOTA + 1);
    c.value = { formula: `Output!$G$2` };
    c.font = { bold: true };
    this.ws.getRow(1).getCell(COL_ROTULO).value = "Cenário ativo (1=Base, 2=Cliente, 3=Stress) →";
    this.cursor = Math.max(this.cursor, 2);
  }

  /** Endereço absoluto da célula de cenário desta aba, para usar em CHOOSE. */
  get celulaCenario(): string { return `$${colLetra(COL_NOTA + 1)}$1`; }

  congelar(chaveLinha?: string): void {
    this.ws.views = [{
      state: "frozen",
      xSplit: COL_NOTA,
      ySplit: chaveLinha ? this.n(chaveLinha) : 3,
    }];
  }
}


// -----------------------------------------------------------------------------
// ESCALA. O caso mistura unidades de verdade: o balanço vem em `milhar` e o mapa
// da dívida em `unidade` (reais). Medido no book: o passivo do modelo saiu com
// 51.300.000 ao lado de um ativo de 1.000 — a dívida em reais somada a um balanço
// em milhares, e o "modelo" mostrando alavancagem de 51 mil vezes.
//
// Então TODO valor histórico é convertido para a unidade do modelo antes de
// entrar, e a célula diz que foi convertida. Unidade desconhecida NÃO é convertida
// nem chutada: a linha entra com aviso, porque adivinhar fator de mil é a forma
// mais rápida de errar por três ordens de grandeza.
// -----------------------------------------------------------------------------
const FATOR_PARA_MILHAR: Record<string, number> = {
  milhar: 1, mil: 1, "r$ mil": 1,
  unidade: 0.001, reais: 0.001, "r$": 0.001,
  milhao: 1000, milhoes: 1000, "milhão": 1000, "milhões": 1000,
};

function fatorDeEscala(unidadeLinha: string | null, unidadeModelo: string): number | null {
  const alvo = /mil/i.test(unidadeModelo) && !/milh(a|ã)o/i.test(unidadeModelo) ? 1 : 0.001;
  if (!unidadeLinha) return null;
  const f = FATOR_PARA_MILHAR[unidadeLinha.toLowerCase().trim()];
  if (f === undefined) return null;
  return alvo === 1 ? f : f * 1000;
}

/** Valor histórico já na escala do modelo, com o aviso quando houve conversão. */
function valorNaEscala(l: LinhaModelo, ano: number, unidadeModelo: string):
  { valor: number; nota: string } | null {
  const bruto = l.valores[String(ano)];
  if (bruto === undefined) return null;
  const f = fatorDeEscala(l.unidade, unidadeModelo);
  const proveniencia = `Extraído de ${(l.documentos ?? ["?"]).join(", ")}`;
  if (f === null) {
    return {
      valor: bruto,
      nota: `${proveniencia}. ATENÇÃO: unidade "${l.unidade ?? "(não informada)"}" não reconhecida, `
        + `valor entrou SEM conversão de escala. Se esta conta estiver em reais e o modelo em `
        + `${unidadeModelo}, ela está mil vezes maior — confira antes de usar o arquivo.`,
    };
  }
  if (f === 1) return { valor: bruto, nota: `${proveniencia} · unidade ${l.unidade}.` };
  return {
    valor: bruto * f,
    nota: `${proveniencia} · CONVERTIDO de "${l.unidade}" para ${unidadeModelo} (fator ${f}). `
      + "O valor no documento é " + bruto.toLocaleString("pt-BR") + ".",
  };
}

// -----------------------------------------------------------------------------
// Classificação das linhas do caso nos blocos do modelo.
//
// O modelo tem blocos fixos (receita, dedução, custo, SG&A, e as contas de
// balanço). A `secao_canonica` da extração já resolve a maior parte; o que ela não
// resolve é DEDUÇÃO dentro de `receita_bruta` — ICMS/PIS/COFINS/IPI/devoluções
// vêm marcados como receita porque é onde eles aparecem na DRE.
//
// A lista é FECHADA e casa por palavra, não por substring solta: `"ICMS a
// recuperar"` é conta do ativo e não pode virar dedução de receita só por conter
// "ICMS". A `secao_canonica` já separa as duas, e este filtro só age DENTRO de
// `receita_bruta`.
// -----------------------------------------------------------------------------
const PADROES_DEDUCAO = [
  /\bdevolu/i, /\babatimento/i, /\bdescontos? concedidos?\b/i,
  /\bicms sobre\b/i, /\bipi sobre\b/i, /\bpis e cofins sobre\b/i, /\bpis\/cofins sobre\b/i,
  /\biss sobre\b/i, /\bimpostos? sobre vendas?\b/i, /\bdedu(ç|c)(õ|o)es\b/i,
  /\btributos sobre vendas?\b/i, /\bcancelad/i,
];

export type BlocoModelo =
  | "receita" | "deducao" | "custo" | "sga" | "resultado_financeiro" | "tributos"
  | "ativo_circulante" | "ativo_nao_circulante" | "passivo_circulante"
  | "passivo_nao_circulante" | "patrimonio_liquido" | "divida" | "capex" | "fora";

export function blocoDaLinha(l: LinhaModelo): BlocoModelo {
  const docs = l.documentos ?? [];
  if (docs.includes("MAPA_DIVIDA")) return "divida";
  switch (l.secao_canonica) {
    case "receita_bruta":
      return PADROES_DEDUCAO.some((re) => re.test(l.chave)) ? "deducao" : "receita";
    case "custos": return "custo";
    case "despesas_operacionais": return "sga";
    case "resultado_financeiro": return "resultado_financeiro";
    case "impostos_lucro": return "tributos";
    case "ativo_circulante": return "ativo_circulante";
    case "ativo_nao_circulante": return "ativo_nao_circulante";
    case "passivo_circulante": return "passivo_circulante";
    case "passivo_nao_circulante": return "passivo_nao_circulante";
    case "patrimonio_liquido": return "patrimonio_liquido";
    default: return "fora";
  }
}

// Linhas de imobilizado dentro do ANC viram classes de capex — é o que o
// `Fixed Assets & CAPEX` projeta. Lista fechada, mesma razão de sempre.
const PADROES_IMOBILIZADO = [
  /\bimobilizado\b/i, /\bedifica/i, /\bterreno/i, /\bve(í|i)culo/i, /\bm(á|a)quina/i,
  /\bequipamento/i, /\binstala(ç|c)/i, /\bm(ó|o)veis?\b/i, /\butens(í|i)lio/i,
  /\bferramenta/i, /\bfrota\b/i, /\bempilhadeira/i, /\bintang(í|i)vel/i, /\bsoftware/i,
  /\bmarcas? e patentes?\b/i,
];
const ehImobilizado = (chave: string) => PADROES_IMOBILIZADO.some((re) => re.test(chave));

// -----------------------------------------------------------------------------
// Premissa por linha: como a projeção de cada conta é escrita.
// -----------------------------------------------------------------------------
interface Ctx {
  ent: EntradaModeloInstitucional;
  anos: number[];
  nHist: number;
  premissaPorLinha: Map<string, PremissaModelo>;
  premissaPorCodigo: Map<string, PremissaModelo>;
  linhasPorBloco: Map<BlocoModelo, LinhaModelo[]>;
  /** anos com histórico, em ordem */
  hist: number[];
  proj: number[];
  ultimoHist: number;
}

function contexto(ent: EntradaModeloInstitucional): Ctx {
  const premissaPorCodigo = new Map(ent.premissas.map((p) => [p.codigo, p]));
  const premissaPorLinha = new Map<string, PremissaModelo>();
  for (const v of ent.vinculos) {
    const p = v.premissa_codigo ? premissaPorCodigo.get(v.premissa_codigo) : undefined;
    if (p) premissaPorLinha.set(v.rotulo_norm, p);
  }
  const linhasPorBloco = new Map<BlocoModelo, LinhaModelo[]>();
  for (const l of ent.linhas) {
    if (l.papel !== "conta") continue;
    const b = blocoDaLinha(l);
    if (!linhasPorBloco.has(b)) linhasPorBloco.set(b, []);
    linhasPorBloco.get(b)!.push(l);
  }
  // Ordem estável e legível: pelo rótulo. Sem isso, a ordem vem do banco e o
  // arquivo muda de forma entre duas gerações sem nada ter mudado.
  for (const lista of linhasPorBloco.values()) lista.sort((a, b) => a.chave.localeCompare(b.chave, "pt-BR"));

  const hist = [...ent.anosHistoricos].sort((a, b) => a - b);
  const proj = [...ent.anosProjetados].sort((a, b) => a - b);
  return {
    ent, anos: [...hist, ...proj], nHist: hist.length,
    premissaPorLinha, premissaPorCodigo, linhasPorBloco, hist, proj,
    ultimoHist: hist[hist.length - 1] ?? proj[0] - 1,
  };
}

const chaveLinha = (prefixo: string, l: LinhaModelo) => `${prefixo}:${l.rotulo_norm}`;

// =============================================================================
// ABA Anual — a base macro. Séries nas linhas, anos nas colunas, como no
// referência; a diferença é que aqui o dado é o `indice_macro_obs` versionado
// mais o Focus, com a FONTE de cada célula na nota.
// =============================================================================
const SERIES_MACRO: ReadonlyArray<{ codigo: string; rotulo: string }> = [
  { codigo: "PIB", rotulo: "PIB — crescimento real (% a.a.)" },
  { codigo: "IPCA", rotulo: "IPCA — IBGE (% a.a.)" },
  { codigo: "IGPM", rotulo: "IGP-M — FGV (% a.a.)" },
  { codigo: "INPC", rotulo: "INPC — IBGE (% a.a.)" },
  { codigo: "SELIC", rotulo: "Selic acumulada (% a.a.)" },
  { codigo: "CDI", rotulo: "CDI (% a.a.)" },
  { codigo: "CAMBIO_USD", rotulo: "R$/US$ — final de período" },
];

function abaAnual(wb: ExcelJS.Workbook, ctx: Ctx): Grade {
  const g = new Grade(wb, "Anual", ctx.anos, ctx.nHist);
  g.cabecalho("BASE MACROECONÔMICA", "Séries anuais — realizado (BCB/IBGE) e expectativa (Focus)");

  const porSerieAno = new Map<string, { valor: number; fonte: string }>();
  for (const m of ctx.ent.macro) porSerieAno.set(`${m.serie}|${m.ano}`, { valor: m.valor, fonte: m.fonte });

  for (const s of SERIES_MACRO) {
    g.linha(`macro:${s.codigo}`, { rotulo: s.rotulo, nota: s.codigo, fmt: NUM2 });
    for (const ano of ctx.anos) {
      const v = porSerieAno.get(`${s.codigo}|${ano}`);
      if (!v) {
        // AUSÊNCIA É AUSÊNCIA: célula vazia, e a nota diz o que falta. Repetir a
        // última observação conhecida projetaria uma expectativa que ninguém
        // publicou — e o modelo inteiro penduraria nela.
        g.set(`macro:${s.codigo}`, ano, null, {
          nota: `Sem observação nem expectativa publicada para ${s.codigo} em ${ano}. `
            + "A célula fica VAZIA de propósito: repetir o último valor conhecido seria "
            + "inventar expectativa.",
        });
        continue;
      }
      g.set(`macro:${s.codigo}`, ano, v.valor, { fmt: NUM2, nota: `Fonte: ${v.fonte}` });
    }
  }
  g.pular();
  const rNota = g.linha(null, {
    rotulo: "Realizado: BCB/IBGE (db/seed/macro_carga_inicial.sql). Projetado: mediana do Focus, "
      + "coleta mais recente. Célula vazia = sem publicação para o ano.",
  });
  g.celula(rNota, COL_ROTULO).font = { italic: true, size: 9 };
  g.congelar();
  return g;
}

// =============================================================================
// ABA Premissas — o HISTÓRICO extraído, por bloco da DRE, com proveniência.
// É a aba que substitui os valores colados do referência.
// =============================================================================
function abaPremissas(wb: ExcelJS.Workbook, ctx: Ctx): Grade {
  const g = new Grade(wb, "Premissas", ctx.hist, ctx.hist.length);
  g.cabecalho("PREMISSAS — BASE HISTÓRICA EXTRAÍDA", `Valores em ${ctx.ent.unidade}`);

  const bloco = (titulo: string, b: BlocoModelo, chaveTotal: string) => {
    g.linha(null, { rotulo: titulo, bloco: true });
    const lista = ctx.linhasPorBloco.get(b) ?? [];
    for (const l of lista) {
      g.linha(chaveLinha(b, l), { rotulo: l.chave, nota: (l.documentos ?? []).join(" · "), fmt: NUM });
      for (const ano of ctx.hist) {
        const e = valorNaEscala(l, ano, ctx.ent.unidade);
        if (!e) continue;
        g.set(chaveLinha(b, l), ano, e.valor, { fmt: NUM, fill: FILL_HIST, nota: e.nota });
      }
    }
    g.linha(chaveTotal, { rotulo: `Total ${titulo.toLowerCase()}`, negrito: true, topo: true, fmt: NUM });
    for (const ano of ctx.hist) {
      if (lista.length === 0) { g.set(chaveTotal, ano, 0, { fmt: NUM, negrito: true }); continue; }
      // Soma CÉLULA A CÉLULA e não por intervalo: intervalo pegaria qualquer linha
      // que alguém insira no meio do bloco depois. Aqui a soma é dos rótulos que
      // o sistema classificou naquele bloco, e só deles.
      const termos = lista.map((l) => g.ref(chaveLinha(b, l), ano));
      g.set(chaveTotal, ano, `=${termos.join("+")}`, { fmt: NUM, negrito: true });
    }
    g.pular();
  };

  bloco("RECEITA BRUTA", "receita", "total:receita");
  bloco("DEDUÇÕES", "deducao", "total:deducao");
  bloco("CUSTOS", "custo", "total:custo");
  bloco("DESPESAS OPERACIONAIS (SG&A)", "sga", "total:sga");
  bloco("RESULTADO FINANCEIRO", "resultado_financeiro", "total:resultado_financeiro");
  bloco("TRIBUTOS SOBRE O LUCRO", "tributos", "total:tributos");
  g.congelar();
  return g;
}

// =============================================================================
// ABA Revenues, COGS & SG&A — a cascata de receita e a formação de custo.
// Mesma mecânica do referência: cada bloco tem TRÊS linhas de premissa (Base,
// Cliente, Stress) e a linha ativa é `CHOOSE(cenário, base, cliente, stress)`.
// =============================================================================
function abaReceita(wb: ExcelJS.Workbook, ctx: Ctx, gPrem: Grade, gAnual: Grade): Grade {
  const g = new Grade(wb, "Revenues, COGS & SG&A", ctx.anos, ctx.nHist);
  g.ancoraCenario();
  g.cabecalho("RECEITA, CUSTOS E DESPESAS", `Valores em ${ctx.ent.unidade}`);
  const cen = g.celulaCenario;

  // ---- GROSS REVENUES ------------------------------------------------------
  g.linha("GROSS_REVENUES", { sinal: "+", rotulo: "GROSS REVENUES", bloco: true, fmt: NUM });
  const receitas = ctx.linhasPorBloco.get("receita") ?? [];
  for (const l of receitas) {
    const p = ctx.premissaPorLinha.get(l.rotulo_norm);
    const ch = chaveLinha("receita", l);
    g.linha(ch, { rotulo: l.chave, nota: p ? p.nome : "(sem premissa — não projetada)", fmt: NUM });
    // três linhas de cenário por conta, como no referência
    g.linha(`${ch}#base`, { rotulo: "    Base Case", fmt: PCT });
    g.linha(`${ch}#cli`, { rotulo: "    Cliente Case", fmt: PCT });
    g.linha(`${ch}#str`, { rotulo: "    Stress Case", fmt: PCT });
  }
  g.linha("RECEITA_SEM_PREMISSA", {
    rotulo: "    (contas de receita sem premissa: mantidas constantes e sinalizadas)",
  });
  g.pular();

  // ---- DEDUÇÕES ------------------------------------------------------------
  g.linha("DEDUCOES", { sinal: "(-)", rotulo: "DEDUÇÕES", bloco: true, fmt: NUM });
  const deducoes = ctx.linhasPorBloco.get("deducao") ?? [];
  for (const l of deducoes) {
    const ch = chaveLinha("deducao", l);
    g.linha(ch, { rotulo: l.chave, nota: "% da receita bruta", fmt: NUM });
    g.linha(`${ch}#pct`, { rotulo: "    % Gross", fmt: PCT });
  }
  g.pular();

  g.linha("RECEITA_LIQUIDA", { sinal: "=", rotulo: "RECEITA LÍQUIDA", negrito: true, topo: true, fmt: NUM });
  g.linha("RECEITA_LIQUIDA_PCT", { rotulo: "    % da receita bruta", fmt: PCT });
  g.pular();

  // ---- CUSTOS --------------------------------------------------------------
  g.linha("CUSTOS", { sinal: "(-)", rotulo: "CUSTOS", bloco: true, fmt: NUM });
  const custos = ctx.linhasPorBloco.get("custo") ?? [];
  for (const l of custos) {
    const ch = chaveLinha("custo", l);
    const p = ctx.premissaPorLinha.get(l.rotulo_norm);
    g.linha(ch, { rotulo: l.chave, nota: p ? p.nome : "(sem premissa)", fmt: NUM });
    g.linha(`${ch}#base`, { rotulo: "    Base Case", fmt: PCT });
    g.linha(`${ch}#cli`, { rotulo: "    Cliente Case", fmt: PCT });
    g.linha(`${ch}#str`, { rotulo: "    Stress Case", fmt: PCT });
  }
  g.linha("CUSTOS_PCT", { rotulo: "    % da receita líquida", fmt: PCT });
  g.pular();

  // ---- SG&A ----------------------------------------------------------------
  g.linha("SGA", { sinal: "(-)", rotulo: "SG&A", bloco: true, fmt: NUM });
  const sga = ctx.linhasPorBloco.get("sga") ?? [];
  for (const l of sga) {
    const ch = chaveLinha("sga", l);
    const p = ctx.premissaPorLinha.get(l.rotulo_norm);
    g.linha(ch, { rotulo: l.chave, nota: p ? p.nome : "(sem premissa)", fmt: NUM });
    g.linha(`${ch}#base`, { rotulo: "    Base Case", fmt: PCT });
    g.linha(`${ch}#cli`, { rotulo: "    Cliente Case", fmt: PCT });
    g.linha(`${ch}#str`, { rotulo: "    Stress Case", fmt: PCT });
  }
  g.linha("SGA_PCT", { rotulo: "    % da receita líquida", fmt: PCT });
  g.pular();

  g.linha("DEPRECIACAO", { sinal: "(+)", rotulo: "Depreciação (de Fixed Assets & CAPEX)", fmt: NUM });
  g.linha("EBITDA", { sinal: "=", rotulo: "EBITDA", negrito: true, topo: true, fmt: NUM });
  g.linha("EBITDA_MARGEM", { rotulo: "    Margem EBITDA (% receita líquida)", fmt: PCT });

  // ---------------------------------------------------------------- preencher
  const fmtCel = { fmt: NUM };
  for (const ano of ctx.anos) {
    const hist = !g.ehProjetado(ano);
    const ant = g.anoAnterior(ano);

    // --- receita por conta
    for (const l of receitas) {
      const ch = chaveLinha("receita", l);
      const p = ctx.premissaPorLinha.get(l.rotulo_norm);
      if (hist) {
        // Histórico aponta para a aba Premissas: UM lugar guarda o número
        // extraído, e o resto do modelo o referencia. Copiar o valor para cá
        // criaria uma segunda verdade sobre o mesmo fato.
        if (l.valores[String(ano)] !== undefined) {
          g.set(ch, ano, `=${g.externa("Premissas", gPrem, ch, ano)}`, { fmt: NUM, fill: FILL_HIST });
        }
        continue;
      }
      if (!p) {
        g.set(ch, ano, `=${g.ref(ch, ant!)}`, {
          fmt: NUM,
          nota: "Conta SEM premissa vinculada: mantida constante e listada na conferência. "
            + "O sistema não projeta o que ninguém escolheu projetar.",
        });
        continue;
      }
      const vBase = p.valores[String(ano)];
      // Premissa por ano: Base é o valor escolhido; Cliente ESPELHA o Base
      // (como no referência, `=J11`); Stress aplica o haircut declarado.
      g.set(`${ch}#base`, ano, vBase === undefined ? null : vBase / 100, {
        fmt: PCT, fill: FILL_INPUT,
        nota: vBase === undefined
          ? `Premissa "${p.nome}" sem valor para ${ano} — a projeção deste ano fica sem crescimento `
            + "e o arquivo diz isso. Preencher no portal (Modelagem)."
          : `Premissa "${p.nome}" (${p.origem ?? "digitado"}) — ${vBase}% em ${ano}.`,
      });
      g.set(`${ch}#cli`, ano, `=${g.ref(`${ch}#base`, ano)}`, { fmt: PCT });
      g.set(`${ch}#str`, ano, `=${g.ref(`${ch}#base`, ano)}*(1-${refStress()})`, { fmt: PCT });
      g.set(ch, ano,
        `=${g.ref(ch, ant!)}*(1+CHOOSE(${cen},${g.ref(`${ch}#base`, ano)},`
        + `${g.ref(`${ch}#cli`, ano)},${g.ref(`${ch}#str`, ano)}))`, fmtCel);
    }
    somaOuZero(g, "GROSS_REVENUES", ano, receitas.map((l) => g.ref(chaveLinha("receita", l), ano)), true);

    // --- deduções: % da receita bruta, travado no último histórico
    for (const l of deducoes) {
      const ch = chaveLinha("deducao", l);
      if (hist) {
        if (l.valores[String(ano)] !== undefined) {
          g.set(ch, ano, `=${g.externa("Premissas", gPrem, ch, ano)}`, { fmt: NUM, fill: FILL_HIST });
        }
        g.set(`${ch}#pct`, ano, `=IF(${g.ref("GROSS_REVENUES", ano)}<>0,${g.ref(ch, ano)}/${g.ref("GROSS_REVENUES", ano)},0)`, { fmt: PCT });
        continue;
      }
      // % do último histórico, mantido. É a convenção do referência (`=I24`) e é
      // a única honesta sem premissa própria: a carga tributária sobre venda não
      // se projeta por crescimento de receita.
      g.set(`${ch}#pct`, ano, `=${g.ref(`${ch}#pct`, ant!)}`, {
        fmt: PCT, fill: FILL_INPUT,
        nota: "Percentual da receita bruta mantido no nível do último exercício realizado. "
          + "Alterar aqui é premissa de carga tributária/devolução.",
      });
      g.set(ch, ano, `=${g.ref(`${ch}#pct`, ano)}*${g.ref("GROSS_REVENUES", ano)}`, fmtCel);
    }
    somaOuZero(g, "DEDUCOES", ano, deducoes.map((l) => g.ref(chaveLinha("deducao", l), ano)), true);

    g.set("RECEITA_LIQUIDA", ano, `=${g.ref("GROSS_REVENUES", ano)}-${g.ref("DEDUCOES", ano)}`,
      { fmt: NUM, negrito: true });
    g.set("RECEITA_LIQUIDA_PCT", ano,
      `=IF(${g.ref("GROSS_REVENUES", ano)}<>0,${g.ref("RECEITA_LIQUIDA", ano)}/${g.ref("GROSS_REVENUES", ano)},0)`,
      { fmt: PCT });

    // --- custos e SG&A: % da receita líquida (variável) ou inflação (fixo)
    for (const [bloco, lista] of [["custo", custos], ["sga", sga]] as const) {
      for (const l of lista) {
        const ch = chaveLinha(bloco, l);
        const p = ctx.premissaPorLinha.get(l.rotulo_norm);
        if (hist) {
          if (l.valores[String(ano)] !== undefined) {
            g.set(ch, ano, `=${g.externa("Premissas", gPrem, ch, ano)}`, { fmt: NUM, fill: FILL_HIST });
          }
          continue;
        }
        if (!p) {
          g.set(ch, ano, `=${g.ref(ch, ant!)}`, {
            fmt: NUM, nota: "Conta sem premissa: mantida constante e sinalizada na conferência.",
          });
          continue;
        }
        const v = p.valores[String(ano)];
        const notaP = v === undefined
          ? `Premissa "${p.nome}" sem valor para ${ano}.`
          : `Premissa "${p.nome}" (${p.origem ?? "digitado"}).`;
        if (p.formula === "pct_de_linha" || p.formula === "indice_macro" || p.formula === "crescimento_composto") {
          g.set(`${ch}#base`, ano, v === undefined ? null : v / 100, { fmt: PCT, fill: FILL_INPUT, nota: notaP });
          g.set(`${ch}#cli`, ano, `=${g.ref(`${ch}#base`, ano)}`, { fmt: PCT });
          // No STRESS, custo e despesa pioram: o haircut entra com sinal
          // invertido em relação à receita. Aplicar -20% num custo produziria um
          // cenário de estresse mais LUCRATIVO que o base, que é o erro clássico
          // de modelo de estresse feito por multiplicação cega.
          g.set(`${ch}#str`, ano, `=${g.ref(`${ch}#base`, ano)}*(1+${refStress()})`, {
            fmt: PCT,
            nota: "No Stress o custo PIORA: o haircut entra somando. Multiplicar custo por "
              + "(1-stress) faria o cenário ruim parecer melhor que o base.",
          });
        }
        if (p.formula === "pct_de_linha") {
          g.set(ch, ano,
            `=CHOOSE(${cen},${g.ref(`${ch}#base`, ano)},${g.ref(`${ch}#cli`, ano)},`
            + `${g.ref(`${ch}#str`, ano)})*${g.ref("RECEITA_LIQUIDA", ano)}`, fmtCel);
        } else if (p.formula === "indice_macro") {
          const serie = p.codigo;
          const refMacro = gAnual.tem(`macro:${serie}`)
            ? Grade.refExterna("Anual", gAnual.letraDoAno(ano), gAnual.n(`macro:${serie}`))
            : null;
          g.set(ch, ano,
            `=${g.ref(ch, ant!)}*(1+${refMacro ? `${refMacro}/100` : g.ref(`${ch}#base`, ano)})`,
            { fmt: NUM, nota: `Corrigido pela série ${serie} da aba Anual (dado versionado, não digitado).` });
        } else {
          g.set(ch, ano,
            `=${g.ref(ch, ant!)}*(1+CHOOSE(${cen},${g.ref(`${ch}#base`, ano)},`
            + `${g.ref(`${ch}#cli`, ano)},${g.ref(`${ch}#str`, ano)}))`, fmtCel);
        }
      }
    }
    somaOuZero(g, "CUSTOS", ano, custos.map((l) => g.ref(chaveLinha("custo", l), ano)), true);
    somaOuZero(g, "SGA", ano, sga.map((l) => g.ref(chaveLinha("sga", l), ano)), true);
    g.set("CUSTOS_PCT", ano, `=IF(${g.ref("RECEITA_LIQUIDA", ano)}<>0,${g.ref("CUSTOS", ano)}/${g.ref("RECEITA_LIQUIDA", ano)},0)`, { fmt: PCT });
    g.set("SGA_PCT", ano, `=IF(${g.ref("RECEITA_LIQUIDA", ano)}<>0,${g.ref("SGA", ano)}/${g.ref("RECEITA_LIQUIDA", ano)},0)`, { fmt: PCT });
  }

  return g;
}

/** Soma célula a célula, ou zero explícito quando o bloco está vazio. */
function somaOuZero(g: Grade, chave: string, ano: number, termos: string[], negrito = false) {
  if (termos.length === 0) {
    g.set(chave, ano, 0, {
      fmt: NUM, negrito,
      nota: "Nenhuma linha do caso caiu neste bloco. Zero EXPLÍCITO: célula vazia num "
        + "subtotal pareceria dado faltando, e num modelo de crédito as duas coisas têm "
        + "consequências diferentes.",
    });
    return;
  }
  // Soma por termos, não por intervalo: as linhas do bloco não são
  // necessariamente contíguas (cada conta tem 3 linhas de cenário embaixo dela),
  // e SUM de intervalo somaria os percentuais junto dos valores.
  g.set(chave, ano, `=${termos.join("+")}`, { fmt: NUM, negrito });
}

/** Referência absoluta à célula do haircut de stress (mora em Considerações). */
function refStress(): string { return `Considerações!$F$8`; }

// =============================================================================
// ABA Income Statement — a DRE completa. Todo subtotal é FÓRMULA: é o que faz o
// modelo se mover quando a premissa muda, e é o que impede o subtotal de
// discordar das partes (o defeito que a Fase 8 fechou na tela de Modelagem).
// =============================================================================
function abaDRE(wb: ExcelJS.Workbook, ctx: Ctx, gRec: Grade, gPrem: Grade, gDiv: Grade): Grade {
  const g = new Grade(wb, "Income Statement", ctx.anos, ctx.nHist);
  g.ancoraCenario();
  g.cabecalho("INCOME STATEMENT", `Valores em ${ctx.ent.unidade}`);

  g.linha("GROSS", { sinal: "+", rotulo: "GROSS REVENUES", negrito: true, fmt: NUM });
  g.linha("DEDUC", { sinal: "(-)", rotulo: "Deductions", fmt: NUM });
  g.linha("NET_REV", { sinal: "=", rotulo: "NET REVENUES", negrito: true, topo: true, fmt: NUM });
  g.pular();
  g.linha("COGS", { sinal: "(-)", rotulo: "COGS", fmt: NUM });
  g.linha("GROSS_PROFIT", { sinal: "=", rotulo: "GROSS PROFIT", negrito: true, topo: true, fmt: NUM });
  g.linha("GROSS_MARGIN", { rotulo: "    % margem bruta", fmt: PCT });
  g.pular();
  g.linha("SGA", { sinal: "(-)", rotulo: "SG&A", fmt: NUM });
  g.linha("EBITDA", { sinal: "=", rotulo: "EBITDA", negrito: true, topo: true, fmt: NUM });
  g.linha("EBITDA_MARGIN", { rotulo: "    % margem EBITDA", fmt: PCT });
  g.pular();
  g.linha("DA", { sinal: "(-)", rotulo: "Depreciation and Amortization", fmt: NUM });
  g.linha("EBIT", { sinal: "=", rotulo: "EBIT", negrito: true, topo: true, fmt: NUM });
  g.pular();
  g.linha("FIN_RESULT", { sinal: "+", rotulo: "Financial Result", fmt: NUM });
  g.linha("FIN_EXP", { rotulo: "    Financial Expenses (juros da dívida)", fmt: NUM });
  g.linha("FIN_INC", { rotulo: "    Financial Income (rendimento do caixa)", fmt: NUM });
  g.linha("FIN_OUTROS", { rotulo: "    Outros resultados financeiros (histórico)", fmt: NUM });
  g.pular();
  g.linha("EBT", { sinal: "=", rotulo: "EBT", negrito: true, topo: true, fmt: NUM });
  g.linha("TAX", { sinal: "(-)", rotulo: "Income tax", fmt: NUM });
  g.linha("TAX_RATE", { rotulo: "    Alíquota efetiva aplicada", fmt: PCT });
  g.pular();
  g.linha("NET_PROFIT", { sinal: "=", rotulo: "NET PROFIT", negrito: true, topo: true, fmt: NUM });
  g.linha("NET_MARGIN", { rotulo: "    % margem líquida", fmt: PCT });

  for (const ano of ctx.anos) {
    const hist = !g.ehProjetado(ano);
    g.set("GROSS", ano, `=${g.externa("Revenues, COGS & SG&A", gRec, "GROSS_REVENUES", ano)}`, { fmt: NUM, negrito: true });
    g.set("DEDUC", ano, `=${g.externa("Revenues, COGS & SG&A", gRec, "DEDUCOES", ano)}`, { fmt: NUM });
    g.set("NET_REV", ano, `=${g.ref("GROSS", ano)}-${g.ref("DEDUC", ano)}`, { fmt: NUM, negrito: true });
    g.set("COGS", ano, `=${g.externa("Revenues, COGS & SG&A", gRec, "CUSTOS", ano)}`, { fmt: NUM });
    g.set("GROSS_PROFIT", ano, `=${g.ref("NET_REV", ano)}-${g.ref("COGS", ano)}`, { fmt: NUM, negrito: true });
    g.set("GROSS_MARGIN", ano, `=IF(${g.ref("NET_REV", ano)}<>0,${g.ref("GROSS_PROFIT", ano)}/${g.ref("NET_REV", ano)},0)`, { fmt: PCT });
    g.set("SGA", ano, `=${g.externa("Revenues, COGS & SG&A", gRec, "SGA", ano)}`, { fmt: NUM });
    // EBITDA = lucro bruto - SG&A + depreciação que está DENTRO de custo/despesa.
    // Somar a depreciação de volta é o passo que a maioria dos modelos erra: sem
    // ele, "EBITDA" é EBIT com outro nome, e a alavancagem sai otimista.
    g.set("EBITDA", ano,
      `=${g.ref("GROSS_PROFIT", ano)}-${g.ref("SGA", ano)}+${g.externa("Revenues, COGS & SG&A", gRec, "DEPRECIACAO", ano)}`,
      { fmt: NUM, negrito: true });
    g.set("EBITDA_MARGIN", ano, `=IF(${g.ref("NET_REV", ano)}<>0,${g.ref("EBITDA", ano)}/${g.ref("NET_REV", ano)},0)`, { fmt: PCT });
    g.set("DA", ano, `=${g.externa("Revenues, COGS & SG&A", gRec, "DEPRECIACAO", ano)}`, { fmt: NUM });
    g.set("EBIT", ano, `=${g.ref("EBITDA", ano)}-${g.ref("DA", ano)}`, { fmt: NUM, negrito: true });
    g.set("FIN_RESULT", ano, `=${g.ref("FIN_EXP", ano)}+${g.ref("FIN_INC", ano)}+${g.ref("FIN_OUTROS", ano)}`, { fmt: NUM });
    g.set("EBT", ano, `=${g.ref("EBIT", ano)}+${g.ref("FIN_RESULT", ano)}`, { fmt: NUM, negrito: true });
    // TRIBUTO SÓ SOBRE LUCRO POSITIVO. Aplicar a alíquota sobre prejuízo geraria
    // "crédito" de imposto entrando como caixa — num mandato de reestruturação,
    // que é o caso de uso deste modelo, isso é o erro mais provável e o mais
    // otimista possível. Prejuízo fiscal a compensar é decisão tributária, não
    // subproduto de uma fórmula.
    g.set("TAX_RATE", ano, hist ? null : ctx.ent.aliquotaTributos, {
      fmt: PCT, fill: hist ? undefined : FILL_INPUT,
      nota: hist ? undefined
        : "Alíquota efetiva sobre o EBT POSITIVO. Prejuízo não gera crédito automático: "
          + "compensação de prejuízo fiscal é decisão tributária e entra como premissa própria.",
    });
    // RESULTADO FINANCEIRO. No realizado vem da extração (aba Premissas); no
    // projetado, da aba de dívida — juros e rendimento calculados, não repetidos.
    if (hist) {
      g.set("FIN_EXP", ano, 0, { fmt: NUM });
      g.set("FIN_INC", ano, 0, { fmt: NUM });
      g.set("FIN_OUTROS", ano, `=${g.externa("Premissas", gPrem, "total:resultado_financeiro", ano)}`, {
        fmt: NUM,
        nota: "Resultado financeiro REALIZADO, como extraído. Não é decomposto em juros e "
          + "rendimento porque o documento não decompõe — e inventar a divisão daria dois "
          + "números que não estão em documento nenhum.",
      });
      g.set("TAX", ano, `=${g.externa("Premissas", gPrem, "total:tributos", ano)}`, {
        fmt: NUM, nota: "Tributo REALIZADO, extraído da DRE.",
      });
    } else {
      g.set("FIN_EXP", ano, `=${g.externa("ST Inv. & Debt", gDiv, "DESP_FIN", ano)}`, { fmt: NUM });
      g.set("FIN_INC", ano, `=${g.externa("ST Inv. & Debt", gDiv, "REC_FIN", ano)}`, { fmt: NUM });
      g.set("FIN_OUTROS", ano, 0, {
        fmt: NUM,
        nota: "Zero no projetado: juros e rendimento já estão nas duas linhas acima. Repetir "
          + "aqui o 'outros' do histórico contaria despesa financeira duas vezes.",
      });
      g.set("TAX", ano, `=-MAX(0,${g.ref("EBT", ano)})*${g.ref("TAX_RATE", ano)}`, { fmt: NUM });
    }
    g.set("NET_PROFIT", ano, `=${g.ref("EBT", ano)}+${g.ref("TAX", ano)}`, { fmt: NUM, negrito: true });
    g.set("NET_MARGIN", ano, `=IF(${g.ref("NET_REV", ano)}<>0,${g.ref("NET_PROFIT", ano)}/${g.ref("NET_REV", ano)},0)`, { fmt: PCT });
  }
  g.congelar("__unidade");
  return g;
}

// =============================================================================
// ABA Working Capital — cada conta de giro é `dias / 360 × receita líquida`.
// 360 e não 365: é o ano comercial, que é o que os contratos e os covenants usam.
// =============================================================================
function abaCapitalGiro(wb: ExcelJS.Workbook, ctx: Ctx, gRec: Grade): Grade {
  const g = new Grade(wb, "Working Capital", ctx.anos, ctx.nHist);
  g.ancoraCenario();
  g.cabecalho("WORKING CAPITAL", `Valores em ${ctx.ent.unidade} · dias de giro sobre receita líquida`);
  const cen = g.celulaCenario;

  const ativos = (ctx.linhasPorBloco.get("ativo_circulante") ?? []).filter((l) => !ehImobilizado(l.chave));
  const passivos = ctx.linhasPorBloco.get("passivo_circulante") ?? [];

  g.linha("NET_REV", { rotulo: "Receita líquida (base dos dias de giro)", negrito: true, fmt: NUM });
  g.pular();
  g.linha(null, { rotulo: "ATIVO CIRCULANTE OPERACIONAL", bloco: true });
  for (const l of ativos) {
    const ch = chaveLinha("wc_a", l);
    g.linha(ch, { rotulo: l.chave, fmt: NUM });
    g.linha(`${ch}#dias`, { rotulo: "    dias de giro (base)", fmt: NUM2 });
    g.linha(`${ch}#diasStr`, { rotulo: "    dias de giro (stress)", fmt: NUM2 });
  }
  g.linha("TOTAL_AC", { rotulo: "Total ativo circulante operacional", negrito: true, topo: true, fmt: NUM });
  g.pular();
  g.linha(null, { rotulo: "PASSIVO CIRCULANTE OPERACIONAL", bloco: true });
  for (const l of passivos) {
    const ch = chaveLinha("wc_p", l);
    g.linha(ch, { rotulo: l.chave, fmt: NUM });
    g.linha(`${ch}#dias`, { rotulo: "    dias de giro (base)", fmt: NUM2 });
    g.linha(`${ch}#diasStr`, { rotulo: "    dias de giro (stress)", fmt: NUM2 });
  }
  g.linha("TOTAL_PC", { rotulo: "Total passivo circulante operacional", negrito: true, topo: true, fmt: NUM });
  g.pular();
  g.linha("NCG", { rotulo: "NECESSIDADE DE CAPITAL DE GIRO (AC − PC)", negrito: true, topo: true, fmt: NUM });
  g.linha("VAR_NCG", { rotulo: "Variação da NCG (efeito no caixa, sinal invertido)", fmt: NUM });

  for (const ano of ctx.anos) {
    const hist = !g.ehProjetado(ano);
    const ant = g.anoAnterior(ano);
    g.set("NET_REV", ano, `=${g.externa("Revenues, COGS & SG&A", gRec, "RECEITA_LIQUIDA", ano)}`, { fmt: NUM, negrito: true });

    for (const [pref, lista] of [["wc_a", ativos], ["wc_p", passivos]] as const) {
      for (const l of lista) {
        const ch = chaveLinha(pref, l);
        if (hist) {
          const e = valorNaEscala(l, ano, ctx.ent.unidade);
          if (e) g.set(ch, ano, e.valor, { fmt: NUM, fill: FILL_HIST, nota: e.nota });
          // Dias IMPLÍCITOS do histórico: saldo / receita × 360. É o número que o
          // analista precisa ver antes de escolher o dia projetado — sem ele, a
          // premissa de giro é palpite.
          g.set(`${ch}#dias`, ano,
            `=IF(${g.ref("NET_REV", ano)}<>0,${g.ref(ch, ano)}/${g.ref("NET_REV", ano)}*360,0)`,
            { fmt: NUM2, nota: "Dias implícitos no realizado: saldo ÷ receita líquida × 360." });
          continue;
        }
        const p = ctx.premissaPorLinha.get(l.rotulo_norm);
        const usaPremissa = p && p.formula === "dias_de_giro" && p.valores[String(ano)] !== undefined;
        g.set(`${ch}#dias`, ano, usaPremissa ? p!.valores[String(ano)] : `=${g.ref(`${ch}#dias`, ant!)}`, {
          fmt: NUM2, fill: FILL_INPUT,
          nota: usaPremissa
            ? `Premissa "${p!.nome}" (${p!.origem ?? "digitado"}).`
            : "Sem premissa de dias de giro para esta conta: mantém os dias do período anterior. "
              + "É a hipótese conservadora — o giro não melhora sozinho.",
        });
        g.set(`${ch}#diasStr`, ano, `=${g.ref(`${ch}#dias`, ano)}*(1+${refStress()}*${pref === "wc_a" ? "1" : "-1"})`, {
          fmt: NUM2,
          nota: pref === "wc_a"
            ? "No Stress o ATIVO gira MAIS DEVAGAR (recebe pior): dias sobem."
            : "No Stress o PASSIVO gira MAIS RÁPIDO (fornecedor aperta o prazo): dias caem. "
              + "Aumentar os dias do passivo no stress daria caixa de graça no cenário ruim.",
        });
        g.set(ch, ano,
          `=CHOOSE(${cen},${g.ref(`${ch}#dias`, ano)},${g.ref(`${ch}#dias`, ano)},${g.ref(`${ch}#diasStr`, ano)})`
          + `/360*${g.ref("NET_REV", ano)}`, { fmt: NUM });
      }
    }
    somaOuZero(g, "TOTAL_AC", ano, ativos.map((l) => g.ref(chaveLinha("wc_a", l), ano)), true);
    somaOuZero(g, "TOTAL_PC", ano, passivos.map((l) => g.ref(chaveLinha("wc_p", l), ano)), true);
    g.set("NCG", ano, `=${g.ref("TOTAL_AC", ano)}-${g.ref("TOTAL_PC", ano)}`, { fmt: NUM, negrito: true });
    g.set("VAR_NCG", ano, ant === null ? 0 : `=-(${g.ref("NCG", ano)}-${g.ref("NCG", ant)})`, {
      fmt: NUM,
      nota: "Sinal invertido: NCG que CRESCE consome caixa. É o erro de sinal mais comum do "
        + "fluxo indireto, e ele dobra o efeito em vez de zerá-lo.",
    });
  }
  g.congelar("__unidade");
  return g;
}

// =============================================================================
// ABA Fixed Assets & CAPEX — imobilizado por classe, capex por premissa e
// depreciação linear por safra.
//
// DIVERGÊNCIA DELIBERADA DO REFERÊNCIA: ele deprecia com
// `SUM(OFFSET(...))*(...)`, que é ilegível e quebra silenciosamente se alguém
// inserir uma coluna. Aqui a depreciação de cada ano é a soma das safras de capex
// dentro da vida útil, escrita como intervalo explícito — mesmo resultado,
// auditável a olho.
// =============================================================================
const VIDA_UTIL_PADRAO = 10;

function abaImobilizado(wb: ExcelJS.Workbook, ctx: Ctx, gRec: Grade): Grade {
  const g = new Grade(wb, "Fixed Assets & CAPEX", ctx.anos, ctx.nHist);
  g.ancoraCenario();
  g.cabecalho("FIXED ASSETS & CAPEX", `Valores em ${ctx.ent.unidade}`);
  const cen = g.celulaCenario;

  const classes = (ctx.linhasPorBloco.get("ativo_nao_circulante") ?? []).filter((l) => ehImobilizado(l.chave));

  g.linha("VIDA_UTIL", { rotulo: "Vida útil média adotada (anos)", nota: "premissa", fmt: NUM2 });
  g.pular();
  g.linha(null, { rotulo: "SALDO DO IMOBILIZADO POR CLASSE", bloco: true });
  for (const l of classes) {
    g.linha(chaveLinha("fa", l), { rotulo: l.chave, fmt: NUM });
  }
  g.linha("TOTAL_FA", { rotulo: "Imobilizado líquido total", negrito: true, topo: true, fmt: NUM });
  g.pular();
  g.linha(null, { rotulo: "CAPEX", bloco: true });
  for (const l of classes) {
    const ch = chaveLinha("capex", l);
    g.linha(ch, { rotulo: `Capex — ${l.chave}`, fmt: NUM });
    g.linha(`${ch}#pct`, { rotulo: "    % da receita líquida (base)", fmt: PCT });
  }
  g.linha("TOTAL_CAPEX", { rotulo: "CAPEX total", negrito: true, topo: true, fmt: NUM });
  g.linha("CAPEX_PCT", { rotulo: "    % da receita líquida", fmt: PCT });
  g.pular();
  g.linha("DEPREC", { rotulo: "DEPRECIAÇÃO DO PERÍODO", negrito: true, fmt: NUM });
  g.linha("DEPREC_NOTA", { rotulo: "    (linear, sobre as safras de capex dentro da vida útil)" });

  for (const ano of ctx.anos) {
    const hist = !g.ehProjetado(ano);
    const ant = g.anoAnterior(ano);
    g.set("VIDA_UTIL", ano, VIDA_UTIL_PADRAO, {
      fmt: NUM2, fill: FILL_INPUT,
      nota: "Vida útil média. Um único número por caso: abrir por classe exige laudo de vida "
        + "útil, que não existe nos documentos do Kit Básico — e inventar uma taxa por classe "
        + "daria falsa precisão.",
    });

    for (const l of classes) {
      const chFa = chaveLinha("fa", l);
      const chCx = chaveLinha("capex", l);
      if (hist) {
        const e = valorNaEscala(l, ano, ctx.ent.unidade);
        if (e) g.set(chFa, ano, e.valor, { fmt: NUM, fill: FILL_HIST, nota: e.nota });
        g.set(chCx, ano, 0, { fmt: NUM, nota: "Capex histórico não é extraível do balanço (só a variação do saldo). Zero explícito." });
        continue;
      }
      const p = ctx.premissaPorLinha.get(l.rotulo_norm);
      const pct = p && p.formula === "pct_de_linha" ? p.valores[String(ano)] : undefined;
      g.set(`${chCx}#pct`, ano, pct === undefined ? 0 : pct / 100, {
        fmt: PCT, fill: FILL_INPUT,
        nota: pct === undefined
          ? "Sem premissa de capex para esta classe: ZERO. Capex inventado é o jeito mais "
            + "rápido de fazer um modelo fechar bonito e não acontecer."
          : `Premissa "${p!.nome}".`,
      });
      g.set(chCx, ano,
        `=CHOOSE(${cen},${g.ref(`${chCx}#pct`, ano)},${g.ref(`${chCx}#pct`, ano)},`
        + `${g.ref(`${chCx}#pct`, ano)}*(1-${refStress()}))*${g.externa("Revenues, COGS & SG&A", gRec, "RECEITA_LIQUIDA", ano)}`,
        { fmt: NUM, nota: "No Stress o capex é CORTADO (é a primeira coisa que se corta numa crise de caixa)." });
      // Saldo: abertura + capex − depreciação rateada pela participação da classe.
      g.set(chFa, ano,
        `=${g.ref(chFa, ant!)}+${g.ref(chCx, ano)}-IF(${g.ref("TOTAL_FA", ant!)}<>0,`
        + `${g.ref(chFa, ant!)}/${g.ref("TOTAL_FA", ant!)}*${g.ref("DEPREC", ano)},0)`, { fmt: NUM });
    }
    somaOuZero(g, "TOTAL_FA", ano, classes.map((l) => g.ref(chaveLinha("fa", l), ano)), true);
    somaOuZero(g, "TOTAL_CAPEX", ano, classes.map((l) => g.ref(chaveLinha("capex", l), ano)), true);
    g.set("CAPEX_PCT", ano,
      `=IF(${g.externa("Revenues, COGS & SG&A", gRec, "RECEITA_LIQUIDA", ano)}<>0,`
      + `${g.ref("TOTAL_CAPEX", ano)}/${g.externa("Revenues, COGS & SG&A", gRec, "RECEITA_LIQUIDA", ano)},0)`, { fmt: PCT });

    if (hist) {
      // Depreciação histórica não é extraível do balanço de forma confiável (ela
      // está na DRE, e o rateio por classe não está em documento nenhum).
      g.set("DEPREC", ano, 0, { fmt: NUM, negrito: true, nota: "Período realizado: a depreciação vem da DRE extraída, não é reprojetada aqui." });
      continue;
    }
    // Depreciação = saldo de abertura ÷ vida útil + capex do ano ÷ vida útil ÷ 2
    // (meia safra no ano de entrada, convenção de meio-ano). Fórmula explícita.
    g.set("DEPREC", ano,
      `=IF(${g.ref("VIDA_UTIL", ano)}<=0,0,${g.ref("TOTAL_FA", ant!)}/${g.ref("VIDA_UTIL", ano)}`
      + `+${g.ref("TOTAL_CAPEX", ano)}/${g.ref("VIDA_UTIL", ano)}/2)`, {
      fmt: NUM, negrito: true,
      nota: "Linear sobre o saldo de abertura, mais meia safra do capex do ano (convenção de "
        + "meio-ano). Guarda contra vida útil zero: divisão por zero num modelo entregue vira "
        + "#DIV/0! em cascata por 12 abas.",
    });
  }
  g.congelar("__unidade");
  return g;
}

// =============================================================================
// ABA ST Inv. & Debt — o cronograma da dívida, uma tranche por linha do mapa.
// =============================================================================
function abaDivida(wb: ExcelJS.Workbook, ctx: Ctx, gAnual: Grade): Grade {
  const g = new Grade(wb, "ST Inv. & Debt", ctx.anos, ctx.nHist);
  g.ancoraCenario();
  g.cabecalho("ST INVESTMENTS & DEBT", `Valores em ${ctx.ent.unidade}`);

  // Uma tranche por linha de SALDO do mapa da dívida. As linhas de "juros do
  // exercício" do mesmo mapa NÃO viram tranche: elas são a taxa implícita, e
  // tratá-las como principal dobraria a dívida.
  const dividas = (ctx.linhasPorBloco.get("divida") ?? []).filter((l) => /saldo|principal/i.test(l.chave));
  const jurosDoMapa = (ctx.linhasPorBloco.get("divida") ?? []).filter((l) => /juros/i.test(l.chave));

  g.linha("CAIXA_MIN", { rotulo: "Caixa mínimo operacional", nota: "premissa", fmt: NUM });
  g.linha("TAXA_MEDIA", { rotulo: "Taxa média da dívida (% a.a.)", nota: "premissa/implícita", fmt: PCT });
  g.pular();
  g.linha(null, { rotulo: "TRANCHES", bloco: true });
  for (const l of dividas) {
    const ch = chaveLinha("dv", l);
    g.linha(`${ch}#ini`, { rotulo: `${l.chave} — saldo de abertura`, fmt: NUM });
    g.linha(`${ch}#amort`, { rotulo: "    amortização do período", fmt: NUM });
    g.linha(`${ch}#pct`, { rotulo: "    % amortizado no período (premissa)", fmt: PCT });
    g.linha(`${ch}#fim`, { rotulo: "    saldo de fechamento", fmt: NUM });
    g.linha(`${ch}#juros`, { rotulo: "    juros do período", fmt: NUM });
  }
  g.linha("TOTAL_DIVIDA", { rotulo: "DÍVIDA TOTAL (fechamento)", negrito: true, topo: true, fmt: NUM });
  g.linha("TOTAL_AMORT", { rotulo: "Amortização total do período", fmt: NUM });
  g.linha("TOTAL_JUROS", { rotulo: "Juros totais do período", fmt: NUM });
  g.pular();
  g.linha(null, { rotulo: "REVOLVER (dívida de tapa-buraco)", bloco: true });
  g.linha("REVOLVER_INI", { rotulo: "Revolver — saldo de abertura", fmt: NUM });
  g.linha("REVOLVER_SAQUE", { rotulo: "Saque/(amortização) do revolver", fmt: NUM });
  g.linha("REVOLVER_FIM", { rotulo: "Revolver — saldo de fechamento", negrito: true, fmt: NUM });
  g.linha("REVOLVER_JUROS", { rotulo: "Juros do revolver", fmt: NUM });
  g.pular();
  g.linha("DIVIDA_BRUTA", { rotulo: "DÍVIDA BRUTA TOTAL", negrito: true, fmt: NUM });
  g.linha("DESP_FIN", { rotulo: "Despesa financeira total (para a DRE)", negrito: true, fmt: NUM });
  g.linha("REC_FIN", { rotulo: "Receita financeira do caixa (para a DRE)", fmt: NUM });

  for (const ano of ctx.anos) {
    const hist = !g.ehProjetado(ano);
    const ant = g.anoAnterior(ano);
    g.set("CAIXA_MIN", ano, ctx.ent.caixaMinimo, { fmt: NUM, fill: FILL_INPUT });
    // Taxa média: implícita no mapa quando ele traz juros e saldo; premissa
    // quando não traz. Sem os dois, ZERO com aviso — juros inventado num modelo
    // de reestruturação é o número que decide se a empresa cabe no plano.
    const somaSaldo = dividas.reduce((s, l) => s + (l.valores[String(ctx.ultimoHist)] ?? 0), 0);
    const somaJuros = jurosDoMapa.reduce((s, l) => s + Math.abs(l.valores[String(ctx.ultimoHist)] ?? 0), 0);
    const taxaImplicita = somaSaldo > 0 ? somaJuros / somaSaldo : 0;
    // TAXA MÉDIA DA DÍVIDA, em três degraus de qualidade, nesta ordem:
    //   1. IMPLÍCITA no mapa da dívida (juros ÷ saldo) — o custo que a empresa
    //      efetivamente paga, medido no documento dela;
    //   2. o CDI da aba Anual (dado versionado), quando o mapa não traz juros —
    //      e declarado como PISO, porque dívida de empresa em reestruturação
    //      custa mais que CDI;
    //   3. zero, com aviso, quando não há nem um nem outro.
    // Nunca um número inventado: num mandato de reestruturação a taxa da dívida é
    // o que decide se a empresa cabe no plano.
    const refCDI = gAnual.tem("macro:CDI")
      ? `${Grade.refExterna("Anual", gAnual.letraDoAno(ano), gAnual.n("macro:CDI"))}/100`
      : null;
    g.set("TAXA_MEDIA", ano, taxaImplicita > 0 ? taxaImplicita : (refCDI ? `=${refCDI}` : 0), {
      fmt: PCT, fill: FILL_INPUT,
      nota: taxaImplicita > 0
        ? `Taxa IMPLÍCITA do mapa da dívida deste caso: juros ${Math.round(somaJuros)} ÷ saldo `
          + `${Math.round(somaSaldo)}. Custo medido no documento, não taxa de mercado.`
        : refCDI
          ? "O mapa da dívida não traz juros e saldo no mesmo exercício: a taxa cai para o CDI da "
            + "aba Anual (dado versionado). É PISO — dívida de empresa em reestruturação custa "
            + "mais que CDI, e este número deve ser revisto antes de ir a comitê."
          : "Sem juros no mapa da dívida e sem série de CDI: ZERO, com aviso. Preencher aqui é "
            + "premissa de custo da dívida.",
    });

    for (const l of dividas) {
      const ch = chaveLinha("dv", l);
      if (hist) {
        const e = valorNaEscala(l, ano, ctx.ent.unidade);
        if (e) g.set(`${ch}#fim`, ano, Math.abs(e.valor), { fmt: NUM, fill: FILL_HIST, nota: e.nota });
        continue;
      }
      g.set(`${ch}#ini`, ano, `=${g.ref(`${ch}#fim`, ant!)}`, { fmt: NUM });
      g.set(`${ch}#pct`, ano, 0, {
        fmt: PCT, fill: FILL_INPUT,
        nota: "Percentual do saldo amortizado no período. ZERO = dívida rolada integralmente, "
          + "que é a hipótese conservadora e explícita. O cronograma real entra aqui.",
      });
      g.set(`${ch}#amort`, ano, `=${g.ref(`${ch}#ini`, ano)}*${g.ref(`${ch}#pct`, ano)}`, { fmt: NUM });
      g.set(`${ch}#fim`, ano, `=${g.ref(`${ch}#ini`, ano)}-${g.ref(`${ch}#amort`, ano)}`, { fmt: NUM });
      // Juros sobre o saldo de ABERTURA — ver NOTA_CIRCULARIDADE.
      g.set(`${ch}#juros`, ano, `=-${g.ref(`${ch}#ini`, ano)}*${g.ref("TAXA_MEDIA", ano)}`,
        { fmt: NUM, nota: NOTA_CIRCULARIDADE });
    }
    somaOuZero(g, "TOTAL_DIVIDA", ano, dividas.map((l) => g.ref(chaveLinha("dv", l) + "#fim", ano)), true);
    somaOuZero(g, "TOTAL_AMORT", ano, dividas.map((l) => g.ref(chaveLinha("dv", l) + "#amort", ano)));
    somaOuZero(g, "TOTAL_JUROS", ano, dividas.map((l) => g.ref(chaveLinha("dv", l) + "#juros", ano)));

    if (hist) {
      for (const ch of ["REVOLVER_INI", "REVOLVER_SAQUE", "REVOLVER_FIM", "REVOLVER_JUROS"]) {
        g.set(ch, ano, 0, { fmt: NUM });
      }
    } else {
      g.set("REVOLVER_INI", ano, `=${g.ref("REVOLVER_FIM", ant!)}`, { fmt: NUM });
      // O saque é preenchido pela aba Cash Flow (é lá que se sabe o furo de
      // caixa). Aqui a linha existe e aponta para lá: uma tela, uma verdade.
      g.set("REVOLVER_FIM", ano, `=${g.ref("REVOLVER_INI", ano)}+${g.ref("REVOLVER_SAQUE", ano)}`, { fmt: NUM, negrito: true });
      g.set("REVOLVER_JUROS", ano, `=-${g.ref("REVOLVER_INI", ano)}*${g.ref("TAXA_MEDIA", ano)}`, { fmt: NUM, nota: NOTA_CIRCULARIDADE });
    }
    g.set("DIVIDA_BRUTA", ano, `=${g.ref("TOTAL_DIVIDA", ano)}+${g.ref("REVOLVER_FIM", ano)}`, { fmt: NUM, negrito: true });
    g.set("DESP_FIN", ano, `=${g.ref("TOTAL_JUROS", ano)}+${g.ref("REVOLVER_JUROS", ano)}`, { fmt: NUM, negrito: true });
  }
  g.congelar("__unidade");
  return g;
}

// =============================================================================
// ABA Cash Flow — fluxo indireto. É aqui que o furo de caixa aparece e o revolver
// é acionado: nenhuma outra aba tem informação para decidir isso.
// =============================================================================
function abaFluxo(
  wb: ExcelJS.Workbook, ctx: Ctx,
  gDRE: Grade, gWC: Grade, gFA: Grade, gDiv: Grade,
): Grade {
  const g = new Grade(wb, "Cash Flow", ctx.anos, ctx.nHist);
  g.cabecalho("CASH FLOW", `Valores em ${ctx.ent.unidade} · método indireto`);

  g.linha(null, { rotulo: "FLUXO DE CAIXA DAS OPERAÇÕES", bloco: true });
  g.linha("NET_INCOME", { sinal: "+", rotulo: "Lucro (prejuízo) líquido", fmt: NUM });
  g.linha("DEPREC", { sinal: "+", rotulo: "Depreciação e amortização", fmt: NUM });
  g.linha("VAR_NCG", { sinal: "+/-", rotulo: "Variação da necessidade de capital de giro", fmt: NUM });
  g.linha("FCO", { sinal: "=", rotulo: "CAIXA DAS OPERAÇÕES", negrito: true, topo: true, fmt: NUM });
  g.pular();
  g.linha(null, { rotulo: "FLUXO DE CAIXA DE INVESTIMENTO", bloco: true });
  g.linha("CAPEX", { sinal: "(-)", rotulo: "CAPEX", fmt: NUM });
  g.linha("FCI", { sinal: "=", rotulo: "CAIXA DE INVESTIMENTO", negrito: true, topo: true, fmt: NUM });
  g.pular();
  g.linha("FCL", { sinal: "=", rotulo: "FLUXO DE CAIXA LIVRE", negrito: true, topo: true, fmt: NUM });
  g.pular();
  g.linha(null, { rotulo: "FLUXO DE CAIXA DE FINANCIAMENTO", bloco: true });
  g.linha("AMORT", { sinal: "(-)", rotulo: "Amortização de dívida", fmt: NUM });
  g.linha("REVOLVER", { sinal: "+", rotulo: "Saque/(amortização) do revolver", fmt: NUM });
  g.linha("DIVIDENDOS", { sinal: "(-)", rotulo: "Dividendos pagos", fmt: NUM });
  g.linha("FCF", { sinal: "=", rotulo: "CAIXA DE FINANCIAMENTO", negrito: true, topo: true, fmt: NUM });
  g.pular();
  g.linha("VAR_CAIXA", { rotulo: "VARIAÇÃO DE CAIXA DO PERÍODO", negrito: true, fmt: NUM });
  g.linha("CAIXA_INI", { rotulo: "Caixa de abertura", fmt: NUM });
  g.linha("CAIXA_ANTES", { rotulo: "Caixa antes do revolver", fmt: NUM });
  g.linha("FURO", { rotulo: "Furo em relação ao caixa mínimo", fmt: NUM });
  g.linha("CAIXA_FIM", { rotulo: "CAIXA DE FECHAMENTO", negrito: true, topo: true, fmt: NUM });

  const caixaHist = (ano: number) => {
    // Caixa realizado: a soma das contas de disponibilidade extraídas.
    const contas = (ctx.linhasPorBloco.get("ativo_circulante") ?? []).filter((l) =>
      /\bcaixa\b|\bdisponív|\bdisponiv|\bbancos?\b|equivalentes|aplica(ç|c)(õ|o)es financeiras/i.test(l.chave));
    return contas.reduce((s, l) => s + (valorNaEscala(l, ano, ctx.ent.unidade)?.valor ?? 0), 0);
  };

  for (const ano of ctx.anos) {
    const hist = !g.ehProjetado(ano);
    const ant = g.anoAnterior(ano);
    if (hist) {
      for (const ch of ["NET_INCOME", "DEPREC", "VAR_NCG", "FCO", "CAPEX", "FCI", "FCL",
                        "AMORT", "REVOLVER", "DIVIDENDOS", "FCF", "VAR_CAIXA", "FURO"]) {
        g.set(ch, ano, 0, { fmt: NUM });
      }
      g.set("CAIXA_INI", ano, ant === null ? 0 : `=${g.ref("CAIXA_FIM", ant)}`, { fmt: NUM });
      g.set("CAIXA_ANTES", ano, caixaHist(ano), { fmt: NUM, fill: FILL_HIST });
      g.set("CAIXA_FIM", ano, caixaHist(ano), {
        fmt: NUM, fill: FILL_HIST, negrito: true,
        nota: "Caixa REALIZADO, soma das contas de disponibilidade extraídas do balanço. "
          + "O fluxo do período realizado não é reconstruído aqui: a DFC extraída é a fonte "
          + "dele, e reconstruir daria dois números para o mesmo fato.",
      });
      continue;
    }
    g.set("NET_INCOME", ano, `=${g.externa("Income Statement", gDRE, "NET_PROFIT", ano)}`, { fmt: NUM });
    g.set("DEPREC", ano, `=${g.externa("Fixed Assets & CAPEX", gFA, "DEPREC", ano)}`, { fmt: NUM });
    g.set("VAR_NCG", ano, `=${g.externa("Working Capital", gWC, "VAR_NCG", ano)}`, { fmt: NUM });
    g.set("FCO", ano, `=${g.ref("NET_INCOME", ano)}+${g.ref("DEPREC", ano)}+${g.ref("VAR_NCG", ano)}`, { fmt: NUM, negrito: true });
    g.set("CAPEX", ano, `=-${g.externa("Fixed Assets & CAPEX", gFA, "TOTAL_CAPEX", ano)}`, { fmt: NUM });
    g.set("FCI", ano, `=${g.ref("CAPEX", ano)}`, { fmt: NUM, negrito: true });
    g.set("FCL", ano, `=${g.ref("FCO", ano)}+${g.ref("FCI", ano)}`, { fmt: NUM, negrito: true });
    g.set("AMORT", ano, `=-${g.externa("ST Inv. & Debt", gDiv, "TOTAL_AMORT", ano)}`, { fmt: NUM });
    g.set("DIVIDENDOS", ano, 0, {
      fmt: NUM, fill: FILL_INPUT,
      nota: "Dividendos ZERO por padrão. Num mandato de reestruturação, distribuir caixa é "
        + "decisão que o plano precisa declarar — não default de planilha.",
    });
    g.set("CAIXA_INI", ano, `=${g.ref("CAIXA_FIM", ant!)}`, { fmt: NUM });
    // Caixa antes do revolver: sem o saque, para o furo ser visível.
    g.set("CAIXA_ANTES", ano,
      `=${g.ref("CAIXA_INI", ano)}+${g.ref("FCL", ano)}+${g.ref("AMORT", ano)}+${g.ref("DIVIDENDOS", ano)}`, { fmt: NUM });
    g.set("FURO", ano,
      `=MAX(0,${g.externa("ST Inv. & Debt", gDiv, "CAIXA_MIN", ano)}-${g.ref("CAIXA_ANTES", ano)})`, {
      fmt: NUM,
      nota: "Quanto falta para o caixa mínimo. É o número que o revolver cobre — e a linha que "
        + "o comitê procura primeiro.",
    });
    // O revolver saca o furo e amortiza quando há sobra, limitado ao saldo devedor.
    g.set("REVOLVER", ano,
      `=IF(${g.ref("FURO", ano)}>0,${g.ref("FURO", ano)},`
      + `-MIN(${g.externa("ST Inv. & Debt", gDiv, "REVOLVER_INI", ano)},`
      + `MAX(0,${g.ref("CAIXA_ANTES", ano)}-${g.externa("ST Inv. & Debt", gDiv, "CAIXA_MIN", ano)})))`, {
      fmt: NUM,
      nota: "Saca o furo; havendo sobra acima do caixa mínimo, amortiza o revolver até zerá-lo. "
        + "O MIN impede amortizar mais do que se deve — sem ele o revolver fica NEGATIVO e o "
        + "modelo passa a mostrar dívida como se fosse aplicação.",
    });
    g.set("FCF", ano, `=${g.ref("AMORT", ano)}+${g.ref("REVOLVER", ano)}+${g.ref("DIVIDENDOS", ano)}`, { fmt: NUM, negrito: true });
    g.set("VAR_CAIXA", ano, `=${g.ref("FCL", ano)}+${g.ref("FCF", ano)}`, { fmt: NUM, negrito: true });
    g.set("CAIXA_FIM", ano, `=${g.ref("CAIXA_INI", ano)}+${g.ref("VAR_CAIXA", ano)}`, { fmt: NUM, negrito: true });
  }
  g.congelar("__unidade");
  return g;
}

// =============================================================================
// ABA Balance Sheet — e o CHECK que decide se o modelo presta: Ativo − (Passivo +
// PL) tem de ser zero em toda coluna. Modelo que não fecha não é modelo.
// =============================================================================
function abaBalanco(
  wb: ExcelJS.Workbook, ctx: Ctx,
  gCF: Grade, gWC: Grade, gFA: Grade, gDiv: Grade, gDRE: Grade,
): Grade {
  const g = new Grade(wb, "Balance Sheet", ctx.anos, ctx.nHist);
  g.cabecalho("BALANCE SHEET", `Valores em ${ctx.ent.unidade}`);

  const anc = ctx.linhasPorBloco.get("ativo_nao_circulante") ?? [];
  const ancNaoImob = anc.filter((l) => !ehImobilizado(l.chave));
  const pnc = (ctx.linhasPorBloco.get("passivo_nao_circulante") ?? []).filter((l) => !/empr(é|e)stimo|financiamento|deb(ê|e)nture/i.test(l.chave));
  const pl = ctx.linhasPorBloco.get("patrimonio_liquido") ?? [];

  g.linha("CAIXA", { rotulo: "Caixa e equivalentes", fmt: NUM });
  g.linha("AC_OPER", { rotulo: "Ativo circulante operacional", fmt: NUM });
  g.linha("AC", { rotulo: "ATIVO CIRCULANTE", negrito: true, topo: true, fmt: NUM });
  g.pular();
  g.linha("IMOB", { rotulo: "Imobilizado e intangível", fmt: NUM });
  for (const l of ancNaoImob) g.linha(chaveLinha("anc", l), { rotulo: l.chave, fmt: NUM });
  g.linha("ANC", { rotulo: "ATIVO NÃO CIRCULANTE", negrito: true, topo: true, fmt: NUM });
  g.linha("ATIVO", { rotulo: "ATIVO TOTAL", negrito: true, topo: true, fmt: NUM });
  g.pular();
  g.linha("PC_OPER", { rotulo: "Passivo circulante operacional", fmt: NUM });
  g.linha("DIVIDA_CP", { rotulo: "Dívida de curto prazo + revolver", fmt: NUM });
  g.linha("PC", { rotulo: "PASSIVO CIRCULANTE", negrito: true, topo: true, fmt: NUM });
  g.pular();
  g.linha("DIVIDA_LP", { rotulo: "Dívida de longo prazo", fmt: NUM });
  for (const l of pnc) g.linha(chaveLinha("pnc", l), { rotulo: l.chave, fmt: NUM });
  g.linha("PNC", { rotulo: "PASSIVO NÃO CIRCULANTE", negrito: true, topo: true, fmt: NUM });
  g.pular();
  for (const l of pl) g.linha(chaveLinha("pl", l), { rotulo: l.chave, fmt: NUM });
  g.linha("LUCROS_ACUM", { rotulo: "Lucros (prejuízos) acumulados do modelo", fmt: NUM });
  g.linha("PL", { rotulo: "PATRIMÔNIO LÍQUIDO", negrito: true, topo: true, fmt: NUM });
  g.linha("PASSIVO_PL", { rotulo: "PASSIVO + PATRIMÔNIO LÍQUIDO", negrito: true, topo: true, fmt: NUM });
  g.pular();
  g.linha("CHECK", { rotulo: "CHECK — Ativo − (Passivo + PL) deve ser ZERO", negrito: true, fmt: NUM2 });
  g.linha("CHECK_TXT", { rotulo: "    diagnóstico" });

  // Proporção CP/LP da dívida: do realizado, quando dá para medir.
  const saldoCP = (ctx.linhasPorBloco.get("passivo_circulante") ?? [])
    .filter((l) => /empr(é|e)stimo|financiamento|deb(ê|e)nture|arrendamento/i.test(l.chave))
    .reduce((s, l) => s + Math.abs(l.valores[String(ctx.ultimoHist)] ?? 0), 0);
  const saldoLP = (ctx.linhasPorBloco.get("passivo_nao_circulante") ?? [])
    .filter((l) => /empr(é|e)stimo|financiamento|deb(ê|e)nture|arrendamento/i.test(l.chave))
    .reduce((s, l) => s + Math.abs(l.valores[String(ctx.ultimoHist)] ?? 0), 0);
  const fracCP = saldoCP + saldoLP > 0 ? saldoCP / (saldoCP + saldoLP) : 0.3;

  for (const ano of ctx.anos) {
    const hist = !g.ehProjetado(ano);
    const ant = g.anoAnterior(ano);
    g.set("CAIXA", ano, `=${g.externa("Cash Flow", gCF, "CAIXA_FIM", ano)}`, { fmt: NUM });
    g.set("AC_OPER", ano, `=${g.externa("Working Capital", gWC, "TOTAL_AC", ano)}`, { fmt: NUM });
    g.set("AC", ano, `=${g.ref("CAIXA", ano)}+${g.ref("AC_OPER", ano)}`, { fmt: NUM, negrito: true });
    g.set("IMOB", ano, `=${g.externa("Fixed Assets & CAPEX", gFA, "TOTAL_FA", ano)}`, { fmt: NUM });
    for (const l of ancNaoImob) {
      const ch = chaveLinha("anc", l);
      const e = valorNaEscala(l, ano, ctx.ent.unidade);
      g.set(ch, ano, hist ? (e?.valor ?? 0) : `=${g.ref(ch, ant!)}`, {
        fmt: NUM, fill: hist ? FILL_HIST : undefined,
        nota: hist ? e?.nota : "Conta não operacional mantida constante: sem premissa própria, "
          + "projetá-la por crescimento de receita seria inventar movimento.",
      });
    }
    somaOuZero(g, "ANC", ano, [g.ref("IMOB", ano), ...ancNaoImob.map((l) => g.ref(chaveLinha("anc", l), ano))], true);
    g.set("ATIVO", ano, `=${g.ref("AC", ano)}+${g.ref("ANC", ano)}`, { fmt: NUM, negrito: true });

    g.set("PC_OPER", ano, `=${g.externa("Working Capital", gWC, "TOTAL_PC", ano)}`, { fmt: NUM });
    g.set("DIVIDA_CP", ano,
      `=${g.externa("ST Inv. & Debt", gDiv, "TOTAL_DIVIDA", ano)}*${fracCP}`
      + `+${g.externa("ST Inv. & Debt", gDiv, "REVOLVER_FIM", ano)}`, {
      fmt: NUM,
      nota: `Fração de curto prazo (${(fracCP * 100).toFixed(1)}%) medida no último exercício `
        + "realizado; o revolver é integralmente curto prazo por natureza.",
    });
    g.set("PC", ano, `=${g.ref("PC_OPER", ano)}+${g.ref("DIVIDA_CP", ano)}`, { fmt: NUM, negrito: true });
    g.set("DIVIDA_LP", ano, `=${g.externa("ST Inv. & Debt", gDiv, "TOTAL_DIVIDA", ano)}*${1 - fracCP}`, { fmt: NUM });
    for (const l of pnc) {
      const ch = chaveLinha("pnc", l);
      const e = valorNaEscala(l, ano, ctx.ent.unidade);
      g.set(ch, ano, hist ? Math.abs(e?.valor ?? 0) : `=${g.ref(ch, ant!)}`,
        { fmt: NUM, fill: hist ? FILL_HIST : undefined, nota: hist ? e?.nota : undefined });
    }
    somaOuZero(g, "PNC", ano, [g.ref("DIVIDA_LP", ano), ...pnc.map((l) => g.ref(chaveLinha("pnc", l), ano))], true);
    for (const l of pl) {
      const ch = chaveLinha("pl", l);
      const e = valorNaEscala(l, ano, ctx.ent.unidade);
      g.set(ch, ano, hist ? (e?.valor ?? 0) : `=${g.ref(ch, ant!)}`,
        { fmt: NUM, fill: hist ? FILL_HIST : undefined, nota: hist ? e?.nota : undefined });
    }
    g.set("LUCROS_ACUM", ano, hist ? 0 : `=${g.ref("LUCROS_ACUM", ant!)}+${g.externa("Income Statement", gDRE, "NET_PROFIT", ano)}-${g.externa("Cash Flow", gCF, "DIVIDENDOS", ano)}`, {
      fmt: NUM,
      nota: hist ? "Zero no realizado: o PL realizado já está nas contas extraídas acima. "
        + "Somar lucro acumulado aqui contaria o mesmo patrimônio duas vezes."
        : undefined,
    });
    somaOuZero(g, "PL", ano, [...pl.map((l) => g.ref(chaveLinha("pl", l), ano)), g.ref("LUCROS_ACUM", ano)], true);
    g.set("PASSIVO_PL", ano, `=${g.ref("PC", ano)}+${g.ref("PNC", ano)}+${g.ref("PL", ano)}`, { fmt: NUM, negrito: true });

    // O CHECK. Formatação condicional não seria suficiente: o número tem de estar
    // na cara, e o diagnóstico tem de dizer o que fazer.
    const cellCheck = g.set("CHECK", ano, `=${g.ref("ATIVO", ano)}-${g.ref("PASSIVO_PL", ano)}`, {
      fmt: NUM2, negrito: true,
      nota: hist
        ? "No período REALIZADO, diferente de zero significa que a extração do balanço está "
          + "incompleta (conta não classificada em nenhum grupo) — não que o modelo está errado. "
          + "Confira a aba de dados linha a linha."
        : "No período PROJETADO tem de ser ZERO. Diferente de zero é defeito do modelo: "
          + "alguma linha de projeção não tem contrapartida.",
    });
    cellCheck.fill = FILL_CHECK_OK;
    g.set("CHECK_TXT", ano,
      `=IF(ABS(${g.ref("CHECK", ano)})<0.5,"fecha","NÃO FECHA: "&TEXT(${g.ref("CHECK", ano)},"#,##0"))`, {});
    g.ws.getRow(g.n("CHECK_TXT")).getCell(g.colDoAno(ano)).fill = FILL_CHECK_ERRO;
  }
  g.congelar("__unidade");
  return g;
}

// =============================================================================
// ABA Goodwill, Taxes & Div. — ágio, tributos diferidos e dividendos.
// =============================================================================
function abaGoodwill(wb: ExcelJS.Workbook, ctx: Ctx, gDRE: Grade, gCF: Grade): Grade {
  const g = new Grade(wb, "Goodwill, Taxes & Div.", ctx.anos, ctx.nHist);
  g.cabecalho("GOODWILL, TAXES & DIVIDENDS", `Valores em ${ctx.ent.unidade}`);

  g.linha(null, { rotulo: "TRIBUTOS SOBRE O LUCRO", bloco: true });
  g.linha("EBT", { rotulo: "EBT", fmt: NUM });
  g.linha("ALIQ", { rotulo: "Alíquota nominal", nota: "premissa", fmt: PCT });
  g.linha("TRIB", { rotulo: "Tributos do período", fmt: NUM });
  g.linha("ALIQ_EFET", { rotulo: "Alíquota EFETIVA (tributo ÷ EBT)", fmt: PCT });
  g.pular();
  g.linha(null, { rotulo: "DIVIDENDOS", bloco: true });
  g.linha("LUCRO", { rotulo: "Lucro líquido", fmt: NUM });
  g.linha("PAYOUT", { rotulo: "Payout", nota: "premissa", fmt: PCT });
  g.linha("DIV", { rotulo: "Dividendos declaráveis", fmt: NUM });
  g.linha("DIV_PAGO", { rotulo: "Dividendos efetivamente pagos (do fluxo)", fmt: NUM });
  g.pular();
  g.linha(null, { rotulo: "ÁGIO", bloco: true });
  g.linha("AGIO", { rotulo: "Ágio — saldo", fmt: NUM });
  g.linha("AGIO_AMORT", { rotulo: "Amortização do ágio", fmt: NUM });

  for (const ano of ctx.anos) {
    const hist = !g.ehProjetado(ano);
    g.set("EBT", ano, `=${g.externa("Income Statement", gDRE, "EBT", ano)}`, { fmt: NUM });
    g.set("ALIQ", ano, ctx.ent.aliquotaTributos, { fmt: PCT, fill: FILL_INPUT });
    g.set("TRIB", ano, `=${g.externa("Income Statement", gDRE, "TAX", ano)}`, { fmt: NUM });
    g.set("ALIQ_EFET", ano, `=IF(${g.ref("EBT", ano)}<>0,-${g.ref("TRIB", ano)}/${g.ref("EBT", ano)},0)`, {
      fmt: PCT,
      nota: "Alíquota efetiva. Com prejuízo, ela sai ZERO porque não há tributo sobre prejuízo "
        + "— e não negativa, que é o que apareceria se o modelo gerasse crédito automático.",
    });
    g.set("LUCRO", ano, `=${g.externa("Income Statement", gDRE, "NET_PROFIT", ano)}`, { fmt: NUM });
    g.set("PAYOUT", ano, 0, {
      fmt: PCT, fill: FILL_INPUT,
      nota: "Payout ZERO por padrão num mandato de reestruturação. Distribuir enquanto se "
        + "renegocia dívida é decisão que o plano declara.",
    });
    g.set("DIV", ano, `=MAX(0,${g.ref("LUCRO", ano)})*${g.ref("PAYOUT", ano)}`, {
      fmt: NUM, nota: "Só sobre lucro POSITIVO: prejuízo não distribui.",
    });
    g.set("DIV_PAGO", ano, `=${g.externa("Cash Flow", gCF, "DIVIDENDOS", ano)}`, { fmt: NUM });
    g.set("AGIO", ano, 0, { fmt: NUM, fill: hist ? FILL_HIST : FILL_INPUT, nota: "Sem ágio identificado nos documentos do caso." });
    g.set("AGIO_AMORT", ano, 0, { fmt: NUM });
  }
  g.congelar("__unidade");
  return g;
}

// =============================================================================
// ABA Tributos a Recolher — o parcelamento tributário, que num mandato de
// reestruturação é quase sempre a segunda maior dívida e quase nunca está no
// mapa de dívida bancária.
// =============================================================================
function abaTributos(wb: ExcelJS.Workbook, ctx: Ctx): Grade {
  const g = new Grade(wb, "Tributos a Recolher", ctx.anos, ctx.nHist);
  g.cabecalho("TRIBUTOS A RECOLHER — PARCELAMENTOS", `Valores em ${ctx.ent.unidade}`);

  const tributarios = [
    ...(ctx.linhasPorBloco.get("passivo_circulante") ?? []),
    ...(ctx.linhasPorBloco.get("passivo_nao_circulante") ?? []),
  ].filter((l) => /tribut|imposto|icms|pis|cofins|inss|fgts|irrf|iss|parcelamento|refis|previd/i.test(l.chave));

  if (tributarios.length === 0) {
    g.linha(null, {
      rotulo: "Nenhuma conta de tributo a recolher foi identificada nas linhas extraídas deste caso.",
    });
    g.linha(null, {
      rotulo: "A aba fica VAZIA de propósito — inventar um parcelamento seria pior que não ter a aba.",
    });
    return g;
  }
  for (const l of tributarios) {
    const ch = chaveLinha("trib", l);
    g.linha(ch, { rotulo: l.chave, nota: (l.documentos ?? []).join(" · "), fmt: NUM });
    g.linha(`${ch}#pct`, { rotulo: "    % pago no período (premissa)", fmt: PCT });
  }
  g.linha("TOTAL", { rotulo: "TOTAL A RECOLHER", negrito: true, topo: true, fmt: NUM });

  for (const ano of ctx.anos) {
    const hist = !g.ehProjetado(ano);
    const ant = g.anoAnterior(ano);
    for (const l of tributarios) {
      const ch = chaveLinha("trib", l);
      if (hist) {
        const e = valorNaEscala(l, ano, ctx.ent.unidade);
        if (e) g.set(ch, ano, Math.abs(e.valor), { fmt: NUM, fill: FILL_HIST, nota: e.nota });
        continue;
      }
      g.set(`${ch}#pct`, ano, 0, {
        fmt: PCT, fill: FILL_INPUT,
        nota: "Percentual do saldo pago no período. ZERO = saldo rolado, que é o que acontece "
          + "quando o parcelamento não está em dia — e é a hipótese que o plano precisa contestar "
          + "explicitamente.",
      });
      g.set(ch, ano, `=${g.ref(ch, ant!)}*(1-${g.ref(`${ch}#pct`, ano)})`, { fmt: NUM });
    }
    somaOuZero(g, "TOTAL", ano, tributarios.map((l) => g.ref(chaveLinha("trib", l), ano)), true);
  }
  g.congelar("__unidade");
  return g;
}

// =============================================================================
// ABA Output — o resumo que vai para o comitê: crescimento, margem, alavancagem,
// cobertura de juros, liquidez. E o INTERRUPTOR DE CENÁRIO, que mora aqui e só
// aqui: `G2`. Toda outra aba lê `Output!$G$2`.
//
// Dois interruptores seriam o defeito clássico: alguém muda o da aba em que está,
// o resto do modelo continua no cenário antigo, e o arquivo mostra uma mistura de
// dois cenários sem nada denunciar.
// =============================================================================
function abaOutput(
  wb: ExcelJS.Workbook, ctx: Ctx,
  gDRE: Grade, gBS: Grade, gDiv: Grade, gCF: Grade, gFA: Grade, gWC: Grade,
): Grade {
  const g = new Grade(wb, "Output", ctx.anos, ctx.nHist);

  // O interruptor, em G2 (col 7, linha 2), com validação de lista.
  g.celula(1, COL_ROTULO).value = "SCENARIO";
  g.celula(1, COL_ROTULO).font = { bold: true, size: 12 };
  const cellCen = g.celula(2, 7);
  cellCen.value = 1;
  cellCen.fill = FILL_INPUT;
  cellCen.font = { bold: true };
  cellCen.numFmt = "0";
  cellCen.dataValidation = {
    type: "whole", operator: "between", formulae: [1, 3], allowBlank: false,
    showErrorMessage: true, errorTitle: "Cenário inválido",
    error: "1 = Base Case, 2 = Cliente Case, 3 = Stress Case. Fora disso, CHOOSE devolve #VALUE! "
      + "em todas as abas — e um modelo cheio de #VALUE! é um modelo que ninguém lê.",
  };
  cellCen.note = comoNota(
    "INTERRUPTOR ÚNICO DE CENÁRIO. 1 = Base, 2 = Cliente, 3 = Stress. Todas as 13 outras abas "
    + "leem esta célula; não existe segundo interruptor, de propósito.",
  );
  g.celula(2, COL_ROTULO).value = "Cenário ativo →";
  for (let i = 0; i < CENARIOS.length; i++) {
    g.celula(3 + i, COL_ROTULO).value = `${i + 1} = ${CENARIOS[i]}`;
    g.celula(3 + i, COL_ROTULO).font = { size: 9, italic: true };
  }
  // ---- O AVISO QUE IMPEDE UM MODELO VAZIO DE PARECER UM MODELO --------------
  //
  // Medido contra a fixture: quando a extração não classifica `secao_canonica`,
  // TODO bloco do modelo fica vazio, a receita sai zero, e o arquivo entrega 14
  // abas de zeros com aparência de modelo institucional. Zero com aparência de
  // resultado é o pior defeito que este projeto pode produzir.
  //
  // Então o modelo se declara: sem receita histórica ou sem premissa vinculada,
  // a primeira coisa que se lê é o que falta e onde resolver.
  const impedimentos: string[] = [];
  const nReceita = (ctx.linhasPorBloco.get("receita") ?? []).length;
  const receitaHist = (ctx.linhasPorBloco.get("receita") ?? [])
    .reduce((acc, l) => acc + Math.abs(valorNaEscala(l, ctx.ultimoHist, ctx.ent.unidade)?.valor ?? 0), 0);
  if (nReceita === 0) {
    impedimentos.push("NENHUMA conta caiu no bloco de RECEITA. Causa quase certa: as linhas "
      + "extraídas estão sem `secao_canonica` (a classificação por seção não rodou ou o "
      + "documento não foi reconhecido). Sem receita, todo o modelo projeta zero.");
  } else if (receitaHist === 0) {
    impedimentos.push(`As ${nReceita} contas de receita não têm valor no último exercício `
      + `realizado (${ctx.ultimoHist}). A projeção parte de zero e permanece zero.`);
  }
  if (ctx.premissaPorLinha.size === 0) {
    impedimentos.push("NENHUMA conta tem premissa vinculada. Todas ficam constantes: o arquivo "
      + "mostra o último realizado repetido, não uma projeção. Vincular na seção Modelagem do portal.");
  }
  if (ctx.hist.length === 0) {
    impedimentos.push("Nenhum exercício realizado identificado para a entidade modelada. "
      + "Conferir a entidade escolhida no passo 1 da Modelagem contra as abas de dados.");
  }
  if (impedimentos.length > 0) {
    const rAviso = g.linha(null, {
      rotulo: "⚠ ESTE MODELO NÃO ESTÁ PROJETÁVEL — leia antes de usar qualquer número",
      negrito: true,
    });
    const cAviso = g.celula(rAviso, COL_ROTULO);
    cAviso.fill = FILL_CHECK_ERRO;
    cAviso.font = { bold: true, size: 12 };
    for (const texto of impedimentos) {
      const r = g.linha(null, { rotulo: `• ${texto}` });
      g.celula(r, COL_ROTULO).fill = FILL_CHECK_ERRO;
      g.celula(r, COL_ROTULO).alignment = { wrapText: true };
      g.ws.getRow(r).height = 28;
    }
    g.pular();
  }

  g.pular(4);
  g.cabecalho("OUTPUT — RESUMO PARA COMITÊ", `Valores em ${ctx.ent.unidade}`);

  g.linha(null, { rotulo: "RESULTADO", bloco: true });
  g.linha("REC_LIQ", { rotulo: "Receita líquida", fmt: NUM });
  g.linha("REC_CRESC", { rotulo: "    % crescimento", fmt: PCT });
  g.linha("EBITDA", { rotulo: "EBITDA", fmt: NUM });
  g.linha("EBITDA_MG", { rotulo: "    % margem EBITDA", fmt: PCT });
  g.linha("LUCRO", { rotulo: "Lucro (prejuízo) líquido", fmt: NUM });
  g.pular();
  g.linha(null, { rotulo: "ENDIVIDAMENTO", bloco: true });
  g.linha("DIVIDA", { rotulo: "Dívida bruta", fmt: NUM });
  g.linha("CAIXA", { rotulo: "Caixa", fmt: NUM });
  g.linha("DIV_LIQ", { rotulo: "Dívida líquida", negrito: true, fmt: NUM });
  g.linha("DIV_EBITDA", { rotulo: "Dívida líquida / EBITDA", negrito: true, fmt: MULT });
  g.linha("COBERTURA", { rotulo: "EBITDA / (juros + amortização)", fmt: MULT });
  g.pular();
  g.linha(null, { rotulo: "CAIXA E GIRO", bloco: true });
  g.linha("FCL", { rotulo: "Fluxo de caixa livre", fmt: NUM });
  g.linha("CAPEX", { rotulo: "CAPEX", fmt: NUM });
  g.linha("NCG", { rotulo: "Necessidade de capital de giro", fmt: NUM });
  g.linha("REVOLVER", { rotulo: "Revolver acionado (saldo)", fmt: NUM });
  g.linha("LIQUIDEZ", { rotulo: "Liquidez corrente", fmt: MULT });
  g.pular();
  g.linha(null, { rotulo: "CHECKS DO MODELO", bloco: true });
  g.linha("CHECK_BS", { rotulo: "Balanço fecha? (0 = sim)", fmt: NUM2 });
  g.linha("CHECK_CAIXA", { rotulo: "Caixa ≥ mínimo? (0 = sim)", fmt: NUM2 });

  for (const ano of ctx.anos) {
    const ant = g.anoAnterior(ano);
    g.set("REC_LIQ", ano, `=${g.externa("Income Statement", gDRE, "NET_REV", ano)}`, { fmt: NUM });
    g.set("REC_CRESC", ano, ant === null ? null
      : `=IF(${g.ref("REC_LIQ", ant)}<>0,${g.ref("REC_LIQ", ano)}/${g.ref("REC_LIQ", ant)}-1,0)`, { fmt: PCT });
    g.set("EBITDA", ano, `=${g.externa("Income Statement", gDRE, "EBITDA", ano)}`, { fmt: NUM });
    g.set("EBITDA_MG", ano, `=IF(${g.ref("REC_LIQ", ano)}<>0,${g.ref("EBITDA", ano)}/${g.ref("REC_LIQ", ano)},0)`, { fmt: PCT });
    g.set("LUCRO", ano, `=${g.externa("Income Statement", gDRE, "NET_PROFIT", ano)}`, { fmt: NUM });
    g.set("DIVIDA", ano, `=${g.externa("ST Inv. & Debt", gDiv, "DIVIDA_BRUTA", ano)}`, { fmt: NUM });
    g.set("CAIXA", ano, `=${g.externa("Cash Flow", gCF, "CAIXA_FIM", ano)}`, { fmt: NUM });
    g.set("DIV_LIQ", ano, `=${g.ref("DIVIDA", ano)}-${g.ref("CAIXA", ano)}`, { fmt: NUM, negrito: true });
    // Alavancagem com EBITDA negativo é ARMADILHA: -3x parece confortável e
    // significa o oposto. O IF devolve texto e o comitê lê o que está acontecendo.
    g.set("DIV_EBITDA", ano,
      `=IF(${g.ref("EBITDA", ano)}<=0,"EBITDA<=0",${g.ref("DIV_LIQ", ano)}/${g.ref("EBITDA", ano)})`, {
      fmt: MULT, negrito: true,
      nota: "Com EBITDA negativo a razão não tem significado: -3,0x parece confortável e é o "
        + "contrário. A célula diz 'EBITDA<=0' em vez de mostrar um múltiplo enganoso.",
    });
    g.set("COBERTURA", ano,
      `=IF((-${g.externa("ST Inv. & Debt", gDiv, "DESP_FIN", ano)}+`
      + `${g.externa("ST Inv. & Debt", gDiv, "TOTAL_AMORT", ano)})<=0,"sem serviço de dívida",`
      + `${g.ref("EBITDA", ano)}/(-${g.externa("ST Inv. & Debt", gDiv, "DESP_FIN", ano)}+`
      + `${g.externa("ST Inv. & Debt", gDiv, "TOTAL_AMORT", ano)}))`, { fmt: MULT });
    g.set("FCL", ano, `=${g.externa("Cash Flow", gCF, "FCL", ano)}`, { fmt: NUM });
    g.set("CAPEX", ano, `=${g.externa("Fixed Assets & CAPEX", gFA, "TOTAL_CAPEX", ano)}`, { fmt: NUM });
    g.set("NCG", ano, `=${g.externa("Working Capital", gWC, "NCG", ano)}`, { fmt: NUM });
    g.set("REVOLVER", ano, `=${g.externa("ST Inv. & Debt", gDiv, "REVOLVER_FIM", ano)}`, { fmt: NUM });
    g.set("LIQUIDEZ", ano,
      `=IF(${g.externa("Balance Sheet", gBS, "PC", ano)}<>0,`
      + `${g.externa("Balance Sheet", gBS, "AC", ano)}/${g.externa("Balance Sheet", gBS, "PC", ano)},0)`, { fmt: MULT });
    g.set("CHECK_BS", ano, `=${g.externa("Balance Sheet", gBS, "CHECK", ano)}`, { fmt: NUM2 });
    g.set("CHECK_CAIXA", ano,
      `=MIN(0,${g.externa("Cash Flow", gCF, "CAIXA_FIM", ano)}-`
      + `${g.externa("ST Inv. & Debt", gDiv, "CAIXA_MIN", ano)})`, {
      fmt: NUM2,
      nota: "Negativo significa que o revolver não cobriu o furo — ou porque o limite não foi "
        + "modelado, ou porque o cenário é insustentável. Nos dois casos é informação, não erro "
        + "a esconder.",
    });
  }
  return g;
}

// =============================================================================
// ABA Considerações — as premissas-chave e as divergências de método, na frente.
// Também é onde mora o haircut do Stress ($F$8), lido por várias abas.
// =============================================================================
function abaConsideracoes(wb: ExcelJS.Workbook, ctx: Ctx): void {
  const ws = wb.addWorksheet("Considerações");
  ws.getColumn(2).width = 34;
  ws.getColumn(3).width = 60;
  ws.getColumn(6).width = 12;
  const put = (r: number, c: number, v: ExcelJS.CellValue, font?: Partial<ExcelJS.Font>) => {
    const cell = ws.getRow(r).getCell(c);
    cell.value = v;
    if (font) cell.font = font;
    return cell;
  };
  put(2, 2, "CONSIDERAÇÕES E PREMISSAS-CHAVE", { bold: true, size: 14 });
  put(3, 2, `${ctx.ent.caso.nome} — ${ctx.ent.entidade ?? "(entidade não definida)"}`, { size: 11 });
  put(4, 2, `Gerado em ${ctx.ent.agora.toLocaleString("pt-BR")} · setor: ${ctx.ent.setor ?? "(não definido)"}`,
    { size: 9, italic: true });

  put(6, 2, "CENÁRIOS", { bold: true });
  put(7, 2, "Cenário ativo");
  const c = ws.getRow(7).getCell(3);
  c.value = { formula: `CHOOSE(Output!$G$2,"${CENARIOS[0]}","${CENARIOS[1]}","${CENARIOS[2]}")` };
  c.font = { bold: true };
  put(8, 2, "Haircut do Stress Case");
  const cellStress = ws.getRow(8).getCell(6);
  cellStress.value = ctx.ent.stressPct;
  cellStress.numFmt = PCT;
  cellStress.fill = FILL_INPUT;
  cellStress.note = comoNota(
    "HAIRCUT DO STRESS, em $F$8 — a única célula que define o cenário 3. Ela piora receita "
    + "(crescimento menor), custo (percentual maior), giro (ativo mais lento, passivo mais rápido) "
    + "e capex (corte). Aplicar o mesmo sinal em tudo é o erro que faz o cenário ruim sair melhor "
    + "que o base.",
  );
  put(8, 3, "aplicado com o SINAL CORRETO em cada linha — ver notas das células");

  put(10, 2, "PREMISSAS DO MANDATO", { bold: true });
  let r = 11;
  put(r, 2, "Alíquota de tributos"); ws.getRow(r).getCell(6).value = ctx.ent.aliquotaTributos;
  ws.getRow(r).getCell(6).numFmt = PCT; r++;
  put(r, 2, "Caixa mínimo operacional"); ws.getRow(r).getCell(6).value = ctx.ent.caixaMinimo;
  ws.getRow(r).getCell(6).numFmt = NUM; r++;
  put(r, 2, "Exercícios realizados"); put(r, 3, ctx.hist.join(", ") || "(nenhum)"); r++;
  put(r, 2, "Exercícios projetados"); put(r, 3, ctx.proj.join(", ") || "(nenhum)"); r++;
  put(r, 2, "Premissas ativas no caso"); put(r, 3, String(ctx.ent.premissas.length)); r++;
  put(r, 2, "Contas com premissa vinculada"); put(r, 3, String(ctx.premissaPorLinha.size)); r += 2;

  put(r, 2, "MÉTODO — DIVERGÊNCIAS DECLARADAS", { bold: true }); r++;
  for (const texto of [
    NOTA_CIRCULARIDADE,
    "Nenhuma linha é projetada sem premissa vinculada: conta sem premissa fica CONSTANTE e é "
    + "listada na conferência do portal. O modelo não inventa movimento.",
    "Subtotal nunca é projetado por premissa própria — ele é a soma dos componentes projetados, "
    + "célula a célula. É o que impede a mesma receita de ser contada duas vezes.",
    "Tributo incide apenas sobre lucro POSITIVO. Compensação de prejuízo fiscal é decisão "
    + "tributária e não subproduto de fórmula.",
    "Histórico não é digitado: vem da extração, com a proveniência de cada célula em nota.",
    "Depreciação: linear sobre o saldo de abertura + meia safra do capex do ano. O modelo de "
    + "referência usa SUM(OFFSET(...)), que quebra em silêncio se alguém inserir coluna.",
  ]) {
    const cell = put(r, 2, texto);
    ws.mergeCells(r, 2, r, 8);
    cell.alignment = { wrapText: true, vertical: "top" };
    ws.getRow(r).height = 30;
    r++;
  }
  ws.views = [{ state: "frozen", ySplit: 5 }];
}

function abaCapa(wb: ExcelJS.Workbook, ctx: Ctx): void {
  const ws = wb.addWorksheet("Capa");
  ws.getColumn(3).width = 70;
  ws.getRow(4).getCell(3).value = ctx.ent.entidade ?? ctx.ent.caso.nome;
  ws.getRow(4).getCell(3).font = { bold: true, size: 20 };
  ws.getRow(6).getCell(3).value = "Projeções Financeiras";
  ws.getRow(6).getCell(3).font = { size: 14 };
  ws.getRow(8).getCell(3).value = `${ctx.ent.caso.nome} · ${ctx.ent.caso.produto}`;
  ws.getRow(10).getCell(3).value = `Gerado em ${ctx.ent.agora.toLocaleDateString("pt-BR")}`;
  ws.getRow(10).getCell(3).font = { size: 10, italic: true };
  ws.getRow(12).getCell(3).value = "Oria Partners — documento de trabalho";
  ws.getRow(12).getCell(3).font = { size: 10 };
}

// =============================================================================
// Ponto de entrada
// =============================================================================
export function construirModeloInstitucional(
  workbook: ExcelJS.Workbook,
  ent: EntradaModeloInstitucional,
): void {
  if (ent.anosProjetados.length === 0) {
    throw new Error("construirModeloInstitucional: sem anos projetados — nada a modelar.");
  }
  const ctx = contexto(ent);

  // Ordem de construção = ordem de dependência das fórmulas. Cada `Grade` só pode
  // ser referenciada depois de existir, e é isso que impede uma referência a uma
  // linha que ainda não foi ancorada.
  const gAnual = abaAnual(workbook, ctx);
  const gPrem = abaPremissas(workbook, ctx);
  const gRec = abaReceita(workbook, ctx, gPrem, gAnual);
  const gDiv = abaDivida(workbook, ctx, gAnual);
  const gFA = abaImobilizado(workbook, ctx, gRec);
  const gWC = abaCapitalGiro(workbook, ctx, gRec);
  const gDRE = abaDRE(workbook, ctx, gRec, gPrem, gDiv);
  const gCF = abaFluxo(workbook, ctx, gDRE, gWC, gFA, gDiv);
  const gBS = abaBalanco(workbook, ctx, gCF, gWC, gFA, gDiv, gDRE);
  const gGW = abaGoodwill(workbook, ctx, gDRE, gCF);
  abaTributos(workbook, ctx);
  const gOut = abaOutput(workbook, ctx, gDRE, gBS, gDiv, gCF, gFA, gWC);
  abaConsideracoes(workbook, ctx);
  abaCapa(workbook, ctx);

  // ---- Costura de volta: o que só se sabe depois de o fluxo existir ---------
  // O revolver é DECIDIDO no fluxo (é lá que o furo aparece) e CONTABILIZADO na
  // dívida. A alternativa seria calcular o furo duas vezes, em duas abas, com
  // duas fórmulas que divergiriam na primeira mudança.
  for (const ano of ctx.proj) {
    gDiv.set("REVOLVER_SAQUE", ano, `=${Grade.refExterna("Cash Flow", gCF.letraDoAno(ano), gCF.n("REVOLVER"))}`, {
      fmt: NUM,
      nota: "Decidido na aba Cash Flow, onde o furo de caixa é conhecido. Uma conta, um lugar.",
    });
    // Rendimento do caixa: sobre o saldo de ABERTURA (ver NOTA_CIRCULARIDADE), e
    // só sobre o excedente ao caixa mínimo — caixa operacional mínimo não rende
    // CDI, fica em conta movimento.
    gDiv.set("REC_FIN", ano,
      `=MAX(0,${Grade.refExterna("Cash Flow", gCF.letraDoAno(ano), gCF.n("CAIXA_INI"))}-${gDiv.ref("CAIXA_MIN", ano)})`
      + `*${gDiv.ref("TAXA_MEDIA", ano)}`, {
      fmt: NUM,
      nota: "Rende só o excedente ao caixa mínimo, sobre o saldo de ABERTURA. " + NOTA_CIRCULARIDADE,
    });
  }
  for (const ano of ctx.hist) {
    gDiv.set("REC_FIN", ano, 0, { fmt: NUM });
    gDiv.set("REVOLVER_SAQUE", ano, 0, { fmt: NUM });
  }

  // ---- Ordem das abas ------------------------------------------------------
  // `workbook.worksheets` é um GETTER que devolve cópia ORDENADA: mexer no array
  // devolvido não faz nada (defeito real, sessão 12 — o assert acusou
  // `modelagem=9` depois de um `splice` que não splicou). Quem manda é `orderNo`.
  //
  // E a ordem tem de ser atribuída a TODAS as abas, não só às do modelo: numerar
  // só estas 14 deixa as abas de dado com o `orderNo` default e o Excel intercala
  // as duas famílias (medido: "Modelagem · Considerações · Resumo · Capa · Dados
  // · Output · Balanço · Revenues…"). Um modelo institucional intercalado com as
  // abas de conferência é um arquivo que ninguém navega.
  const ORDEM_MODELO = new Map(ABAS_MODELO.map((n, i) => [n as string, i + 1]));
  let proximoOutro = 100;
  for (const ws of workbook.worksheets) {
    const alvo = ws.name === "Modelagem"
      // A aba `Modelagem` agregada (Fase 7) continua sendo a primeira: é a que o
      // dono já valida ao vivo, e é dela que o modelo institucional é comparado.
      ? 0
      : ORDEM_MODELO.get(ws.name) ?? proximoOutro++;
    (ws as unknown as { orderNo: number }).orderNo = alvo;
  }

  // Recalcular ao abrir: o arquivo sai com fórmula e sem valor em cache, então sem
  // isto o Excel mostra célula vazia até alguém apertar F9.
  workbook.calcProperties = { fullCalcOnLoad: true };

  void gGW; void gOut;
}
