// Converte conteúdo de planilha em texto compacto para enviar ao LLM.
// Usado no fallback quando o arquivo é CSV/XLSX (o modelo não lê xlsx binário).

// rows: array de objetos (uma linha = um objeto coluna→valor), como sai do
// nó "Extract From File" do N8N ou de um CSV parseado.
export function spreadsheetToText(rows, { maxRows = 50, maxCols = 25 } = {}) {
  if (!Array.isArray(rows) || rows.length === 0) return '(planilha vazia)';
  const cols = Object.keys(rows[0]).slice(0, maxCols);
  const header = cols.join(' | ');
  const corpo = rows
    .slice(0, maxRows)
    .map((r) => cols.map((c) => String(r[c] ?? '')).join(' | '))
    .join('\n');
  const extra = rows.length > maxRows ? `\n… (+${rows.length - maxRows} linhas omitidas)` : '';
  return `${header}\n${corpo}${extra}`;
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
