// Normalização de texto para casamento robusto de nomes de arquivo.
// minúsculas, sem acento, separadores (_ - .) viram espaço, espaços colapsados.

export function normalize(s) {
  if (s == null) return '';
  return String(s)
    .normalize('NFD')
    // Escrito como escape, não como os caracteres: a faixa literal é invisível, e
    // o nó do n8n embute esta função por `toString()` — o portão de caracteres
    // invisíveis do workflow reprova o literal (24/09/2026).
    .replace(/[\u0300-\u036f]/g, '') // remove diacríticos (combining marks)
    .toLowerCase()
    .replace(/\.[a-z0-9]{2,4}$/i, '') // remove extensão (.pdf, .xlsx, ...)
    .replace(/[_\-.]+/g, ' ')
    .replace(/\s+/g, ' ')
    .trim();
}
