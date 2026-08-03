// Converte conteúdo de planilha em texto compacto para enviar ao LLM.
// Usado no fallback quando o arquivo é CSV/XLSX (o modelo não lê xlsx binário).

// TETO DE SEGURANÇA, NÃO DE CONVENIÊNCIA.
//
// Era 50 linhas × 25 colunas, e 50 é menos do que um documento real tem: um
// faturamento de 24 meses por 5 entidades são 120 linhas, um balancete
// analítico passa de 500. O resto ia embora com uma nota discreta no meio do
// prompt ("… (+N linhas omitidas)") que só a IA lia — o banco recebia a
// extração como se estivesse completa, e o book saía com faturamento parcial
// sem UMA pendência. É o item 1 do §7.4 do Onboarding: "perde dado de verdade".
//
// O teto continua existindo porque input é dinheiro e porque uma planilha
// absurda tem de parar em algum lugar; o que muda é (a) a ordem de grandeza,
// que agora cobre documento real, e (b) o corte deixar de ser silencioso —
// `avisoTruncamentoPlanilha` transforma o que ficou de fora em pendência.
export const MAX_LINHAS_PLANILHA = 2000;
export const MAX_COLUNAS_PLANILHA = 60;

// rows: array de objetos (uma linha = um objeto coluna→valor), como sai do
// nó "Extract From File" do N8N ou de um CSV parseado.
export function spreadsheetToText(
  rows,
  { maxRows = MAX_LINHAS_PLANILHA, maxCols = MAX_COLUNAS_PLANILHA } = {},
) {
  if (!Array.isArray(rows) || rows.length === 0) return '(planilha vazia)';
  const cols = colunasDaPlanilha(rows).slice(0, maxCols);
  const header = cols.join(' | ');
  const corpo = rows
    .slice(0, maxRows)
    .map((r) => cols.map((c) => String(r[c] ?? '')).join(' | '))
    .join('\n');
  const extra = rows.length > maxRows ? `\n… (+${rows.length - maxRows} linhas omitidas)` : '';
  return `${header}\n${corpo}${extra}`;
}

// UNIÃO das chaves, não as chaves da PRIMEIRA linha.
//
// `Object.keys(rows[0])` assume que a linha 0 declara todas as colunas. Vale
// para CSV (o cabeçalho manda), mas o "Extract From File" do N8N devolve objeto
// esparso: célula vazia não vira chave. Uma planilha cuja primeira linha de
// dados tem a coluna de 2024 em branco perdia a coluna 2024 do documento
// INTEIRO — mesma família de perda silenciosa que o teto de linhas.
//
// ORDEM: chave que parece inteiro ('2025') o JS reordena para a frente das
// textuais, então a ordem daqui não é a ordem visual do documento. Não desalinha
// nada (cabeçalho e corpo usam esta mesma lista) e não se corrige sem carregar a
// ordem original desde o parse — fica para quando o "Extract From File" entrar.
// Registrado para ninguém "consertar" achando que é bug.
export function colunasDaPlanilha(rows) {
  const vistas = new Set();
  for (const r of rows) {
    if (r && typeof r === 'object') for (const k of Object.keys(r)) vistas.add(k);
  }
  return [...vistas];
}

// O que `spreadsheetToText` deixou de fora, em texto que vira PENDÊNCIA.
//
// Devolve null quando nada foi cortado (o caso normal, e o silêncio aqui é
// legítimo). Quando corta, o texto entra em `falha_motivo` — que a 0016 já
// converte em pendência `extracao_falhou` visível no portal. Sem isto, o corte
// existia só dentro do prompt: a IA sabia, o analista não.
export function avisoTruncamentoPlanilha(
  rows,
  { maxRows = MAX_LINHAS_PLANILHA, maxCols = MAX_COLUNAS_PLANILHA } = {},
) {
  if (!Array.isArray(rows) || rows.length === 0) return null;
  const nLinhas = rows.length;
  const nColunas = colunasDaPlanilha(rows).length;
  const partes = [];
  if (nLinhas > maxRows) {
    partes.push(
      `${nLinhas - maxRows} de ${nLinhas} linhas não foram enviadas à extração `
      + `(teto de ${maxRows})`,
    );
  }
  if (nColunas > maxCols) {
    partes.push(
      `${nColunas - maxCols} de ${nColunas} colunas não foram enviadas à extração `
      + `(teto de ${maxCols})`,
    );
  }
  if (partes.length === 0) return null;
  return `Planilha maior que o teto de envio: ${partes.join('; ')}. `
    + 'A extração deste documento está INCOMPLETA — o que falta não está no banco '
    + 'nem no book. Reenvie o arquivo fatiado ou peça ao dono para elevar o teto.';
}

// CSV simples → array de objetos (separador , ou ;). Suficiente para o fallback;
// casos complexos (aspas com vírgula) o dono valida/ajusta no N8N.
export function parseCsv(texto) {
  const linhas = String(texto || '').split(/\r?\n/).filter((l) => l.trim() !== '');
  if (linhas.length === 0) return [];
  const sep = (linhas[0].match(/;/g) || []).length > (linhas[0].match(/,/g) || []).length ? ';' : ',';
  const cabecalho = linhas[0].split(sep).map((c) => c.trim());
  return linhas.slice(1).map((l) => {
    const celulas = l.split(sep);
    const obj = {};
    cabecalho.forEach((c, i) => { obj[c || `col${i}`] = (celulas[i] ?? '').trim(); });
    return obj;
  });
}
