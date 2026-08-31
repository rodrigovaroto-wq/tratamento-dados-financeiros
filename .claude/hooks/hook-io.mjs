// Leitura de evento de hook, à prova do bug que derruba a política de fail-open.
//
// POR QUE ESTE ARQUIVO EXISTE. `JSON.parse("null")` devolve `null` SEM lançar erro — é JSON
// válido, como "true" ou "42". Então o padrão que parece defensivo não protege:
//
//   try { ev = JSON.parse(lerStdin() || "{}") } catch { ev = {} }
//   if (ev.tool_name === "Bash")   // TypeError: Cannot read properties of null
//
// O fallback `|| "{}"` não entra (a string não é vazia) e o `catch` não roda (o parse não
// falhou). A quebra acontece uma linha depois, FORA do try/catch — e um hook que morre com stack
// trace pode trancar a sessão inteira por causa de uma ferramenta auxiliar.
//
// `typeof ev.tool_name === "string"` também não salva: o acesso à propriedade acontece antes de
// o `typeof` ver o resultado.

import { readFileSync } from "node:fs";

/** Lê o stdin bruto. NUNCA lança — qualquer falha vira string vazia. */
export function readStdinRaw() {
  try {
    return readFileSync(0, "utf8");
  } catch {
    return "";
  }
}

/**
 * Interpreta o evento. Devolve `null` tanto para JSON inválido quanto para o valor `null`
 * literal — as duas situações de falha colapsam num sinal só, e o `catch` cobre as duas de
 * graça, porque JSON.parse já devolve `null` para a entrada "null".
 */
export function parseHookEvent(raw) {
  let parsed;
  try {
    parsed = JSON.parse(raw);
  } catch {
    return null;
  }
  if (parsed === null || typeof parsed !== "object") return null;
  return parsed;
}

/** Atalho: lê e interpreta. `null` significa "nada utilizável aqui". */
export function lerEvento() {
  return parseHookEvent(readStdinRaw());
}
