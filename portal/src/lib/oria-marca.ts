// A CARA DA ORIA NO ENTREGÁVEL — paleta, tipografia e o que cada cor SIGNIFICA.
//
// POR QUE ESTE ARQUIVO EXISTE, E POR QUE ELE É UMA DECISÃO E NÃO UM ACHADO.
// Procurado no repositório inteiro antes de escrever uma linha: **não existe
// paleta de marca versionada aqui**. O `globals.css` do portal tem três regras e
// nenhuma cor; não há `tailwind.config` com tokens; não há logotipo em
// `portal/public` (só os SVGs que vêm no template do Next); e a skill de marca
// (`identidade-marca-oria`) é identidade VERBAL — tom de voz, público, o que não
// escrever —, sem uma cor. A única marca visual que já existia no produto são as
// cores do próprio export (`export-estilo.ts`) e as do modelo institucional.
//
// Então esta paleta é **derivada do que já existe**, não inventada do zero:
//   • o grafite `1E293B` já era a faixa de bloco do modelo institucional;
//   • o cinza `E5E7EB` já era o `HEADER_FILL` de todas as abas de dado;
//   • o vermelho-claro `FCE4E4` já era o `DIVERGENCIA_FILL` da reconciliação;
//   • o azul `EEF2FF` já era o `ANALISE_HEADER_FILL` da camada analítica.
// O que se acrescenta é hierarquia (três níveis de faixa em vez de uma), a
// gramática de cor de FONTE — que o Modelo Base tem e nós não tínhamos — e um
// único acento institucional.
//
// A REGRA QUE GOVERNA A ESCOLHA: modelo de crédito é lido em **impressão preto e
// branco** por comitê. Cor que não sobrevive ao papel não pode carregar
// informação sozinha. Por isso toda distinção aqui é redundante — cor MAIS
// negrito, MAIS borda, MAIS recuo, MAIS o próprio texto da célula. A cor
// acelera a leitura; ela nunca é a única portadora do significado.
//
// A GRAMÁTICA DE COR DE FONTE É COPIADA DO MODELO BASE, de propósito: é
// convenção de mercado, um analista de crédito a lê sem legenda, e o Modelo Base
// a usa com rigor (medido em `docs/referencia/MAPA_MODELO_BASE.md` §2.8 — a
// paleta indexada está declarada no arquivo):
//
//   • AZUL   = número DIGITADO (entrada manual, premissa que se pode mexer)
//   • PRETO  = número CALCULADO (fórmula; mexer aqui é quebrar o modelo)
//   • VERDE  = número que vem de OUTRA ABA deste mesmo arquivo
//   • CINZA  = auxiliar / nota de rodapé
//
// A quarta (verde para referência entre abas) é acréscimo nosso: o Modelo Base
// mistura referência externa com cálculo em preto, e num arquivo de 29 abas isso
// custa tempo de quem audita.
import ExcelJS from "exceljs";

// -----------------------------------------------------------------------------
// Paleta. ARGB de 8 dígitos porque é o que o ExcelJS exige (`FF` = opaco).
// -----------------------------------------------------------------------------
export const ORIA = {
  /** Grafite institucional — faixa de seção. Já era o `FILL_BLOCO` do modelo. */
  grafite: "FF1E293B",
  /** Grafite claro — faixa de subtotal. */
  grafiteClaro: "FF475569",
  /** Cinza de apoio — faixa de linha de conta e cabeçalho de ano realizado. */
  cinza: "FFE2E8F0",
  /** Cinza mais claro — o `HEADER_FILL` que o resto do export já usa. */
  cinzaClaro: "FFF1F5F9",
  /** Acento institucional — cabeçalho de ano PROJETADO e a Capa. */
  acento: "FF0E7490",
  /** Areia — célula de ENTRADA manual (premissa que o cliente pode mexer). */
  entrada: "FFFEF3C7",
  /** Verde de conferência — check que fecha. */
  okFundo: "FFDCFCE7",
  /** Vermelho de conferência — check que NÃO fecha. */
  erroFundo: "FFFEE2E2",
  branco: "FFFFFFFF",
} as const;

/** Cor de FONTE por procedência do número. Ver o cabeçalho deste arquivo. */
export const FONTE_COR = {
  /** digitado / premissa — azul, convenção de mercado */
  entrada: "FF1D4ED8",
  /** calculado nesta aba — preto */
  calculado: "FF0F172A",
  /** vem de outra aba deste arquivo — verde */
  externo: "FF15803D",
  /** auxiliar, nota, rodapé — cinza */
  auxiliar: "FF64748B",
} as const;

/**
 * Tipografia. Arial 10 é o que o Modelo Base usa em TUDO (medido: 178 fontes no
 * `styles.xml`, e a de corpo é Arial 10) e é a fonte que sobrevive a qualquer
 * Excel, LibreOffice ou visualizador de navegador sem substituição silenciosa —
 * que muda a largura da coluna e desalinha o arquivo entregue.
 */
export const FONTE_FAMILIA = "Arial";
export const TAM_CORPO = 10;
export const TAM_TITULO_ABA = 12;
export const TAM_CAPA_TITULO = 26;

export const fonte = (o: Partial<ExcelJS.Font> = {}): Partial<ExcelJS.Font> =>
  ({ name: FONTE_FAMILIA, size: TAM_CORPO, ...o });

export const preencher = (argb: string): ExcelJS.Fill =>
  ({ type: "pattern", pattern: "solid", fgColor: { argb } });

export const FILL_SECAO = preencher(ORIA.grafite);
export const FILL_SUBTOTAL = preencher(ORIA.cinza);
export const FILL_TOTAL = preencher(ORIA.grafiteClaro);
export const FILL_ENTRADA = preencher(ORIA.entrada);
export const FILL_ANO_REALIZADO = preencher(ORIA.cinza);
export const FILL_ANO_PROJETADO = preencher(ORIA.acento);
export const FILL_OK = preencher(ORIA.okFundo);
export const FILL_ERRO = preencher(ORIA.erroFundo);

/**
 * Formatos numéricos. Contábil de verdade — negativo entre parênteses e zero
 * como travessão —, que é o que o Modelo Base usa (`numFmt 166`) e o que um
 * comitê espera. `#,##0;-#,##0` mostraria `0` onde não há dado.
 */
export const FMT = {
  valor: '_(* #,##0_);_(* (#,##0);_(* "-"_);_(@_)',
  valor2: '_(* #,##0.00_);_(* (#,##0.00);_(* "-"??_);_(@_)',
  /** uma decimal — prazo médio em dias, como o `numFmt 212` do Modelo Base */
  dias: '_(* #,##0.0_);_(* (#,##0.0);_(* "-"??_);_(@_)',
  pct: "0.0%",
  pct2: "0.00%",
  mult: '0.00"x"',
  /** o cabeçalho de ano é uma DATA (ver P01) exibida como ano */
  ano: "yyyy",
} as const;

/**
 * A legenda da gramática de cores, para escrever na aba `Considerações`.
 * Um arquivo que usa cor como informação e não explica a cor obriga quem recebe
 * a adivinhar — e adivinhar errado aqui é mexer numa fórmula achando que é
 * premissa.
 */
export const LEGENDA_CORES: ReadonlyArray<{ cor: string; fundo?: string; texto: string }> = [
  { cor: FONTE_COR.entrada, fundo: ORIA.entrada, texto: "AZUL sobre areia = premissa DIGITADA. É o que se pode mexer." },
  { cor: FONTE_COR.calculado, texto: "PRETO = calculado nesta aba por fórmula. Mexer aqui quebra o modelo." },
  { cor: FONTE_COR.externo, texto: "VERDE = vem de outra aba deste arquivo. A origem está na nota da célula." },
  { cor: FONTE_COR.auxiliar, texto: "CINZA = linha auxiliar, nota ou rodapé." },
];
