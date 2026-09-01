// Normalização de texto para casamento robusto de nomes de arquivo.
// minúsculas, sem acento, separadores (_ - .) viram espaço, espaços colapsados.

export function normalize(s) {
  if (s == null) return '';
  return String(s)
    .normalize('NFD')
    .replace(/[̀-ͯ]/g, '') // remove diacríticos (combining marks)
    .toLowerCase()
    .replace(/\.[a-z0-9]{2,4}$/i, '') // remove extensão (.pdf, .xlsx, ...)
    .replace(/[_\-.]+/g, ' ')
    .replace(/\s+/g, ' ')
    .trim();
}
