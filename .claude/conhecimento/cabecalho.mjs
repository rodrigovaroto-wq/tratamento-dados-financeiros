// O cabeçalho YAML simples de uma ficha ou memória (só os campos que o conhecimento usa) — sem
// dependência nova. UM parser para o `indexar.mjs` e o `verificar-comandos.mjs`.
//
// O CRLF é normalizado antes de tudo. Até 24/09/2026 o `indexar.mjs` só casava `\n`, e uma ficha
// salva em CRLF entrava no grafo sem `toca`/`prova`/`ancora`, em silêncio — o que
// `test/cabecalho.test.mjs` prova, sobre todas as fichas reais, que não acontece mais.
export function cabecalho(texto) {
  const m = /^---\n([\s\S]*?)\n---\n/.exec(String(texto).replace(/\r\n/g, "\n"));
  if (!m) return null;
  const campos = {};
  let chaveLista = null;
  for (const linha of m[1].split("\n")) {
    const item = /^\s+-\s+(.+)$/.exec(linha);
    if (item && chaveLista) { campos[chaveLista].push(item[1].trim()); continue; }
    const par = /^([a-z_]+):\s*(.*)$/.exec(linha);
    if (!par) continue;
    chaveLista = null;
    if (par[2] === "") { campos[par[1]] = []; chaveLista = par[1]; }
    else if (par[2] === "[]") campos[par[1]] = [];
    else campos[par[1]] = par[2].trim();
  }
  return campos;
}
