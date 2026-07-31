// Vocabulário visual compartilhado pelas abas do export.
//
// POR QUE ESTE ARQUIVO EXISTE. `export.ts` passou de 4.100 linhas, e a metade
// de baixo (aba Macro + aba Modelagem, ~1.500 linhas) não tem nada a ver com a
// metade de cima (classificação e emissão das demonstrações extraídas). Separar
// as duas exigia exatamente NOVE símbolos em comum, e todos são apresentação:
// formatos numéricos, preenchimentos e a fábrica de nota. Eles moram aqui para
// os dois módulos poderem importar sem que um dependa do outro — import
// circular entre dois arquivos de 2.000 linhas é o tipo de coisa que funciona
// até o dia em que a ordem de inicialização muda.
//
// Nada aqui tem lógica. Se um dia tiver, provavelmente está no arquivo errado.
import ExcelJS from "exceljs";

// Separador de chave composta. É um caractere que NUNCA aparece num rótulo
// contábil, e é isso que se quer: com espaço simples, entidade "A B" + período
// "C" colide com entidade "A" + período "B C" (colunas distintas fundidas numa
// só). Escrito como escape, e não como o byte literal, para não deixar um
// caractere invisível no fonte.
export const CHAVE_SEP = "\u0000";

export const VALOR_NUM_FMT = "#,##0.00;(#,##0.00)";
export const RATIO_FMT = "0.00"; // índices "x vezes" (liquidez, participação)
export const PCT_FMT = "0.0%"; // índices em % (endividamento, composição, imobilização)

export const HEADER_FILL: ExcelJS.Fill = { type: "pattern", pattern: "solid", fgColor: { argb: "FFE5E7EB" } };
export const DIVERGENCIA_FILL: ExcelJS.Fill = { type: "pattern", pattern: "solid", fgColor: { argb: "FFFCE4E4" } };
export const ANALISE_HEADER_FILL: ExcelJS.Fill = { type: "pattern", pattern: "solid", fgColor: { argb: "FFEEF2FF" } };
export const THIN_TOP_BORDER: Partial<ExcelJS.Borders> = { top: { style: "thin" } };

// Fonte compacta (8pt) + caixa de comentário ampliada (ver `ampliarNotas`,
// pós-processamento do .xlsx — a API do ExcelJS não expõe tamanho de caixa de
// nota, só o conteúdo/fonte) — as anotações tinham texto cortado ao abrir
// (pedido do dono, sessão 7 cont.¹⁵).
const NOTA_FONT: Partial<ExcelJS.Font> = { size: 8, name: "Calibri" };
export function comoNota(texto: string): ExcelJS.Comment {
  return { texts: [{ text: texto, font: NOTA_FONT }] };
}
