/**
 * Avaliador mínimo das fórmulas que o export emite, para os scripts de
 * verificação conferirem os números sem abrir o Excel.
 *
 * Cobre exatamente o que `buildExportWorkbook` gera: referências (`B12`),
 * `SUM(B4:B37)`, aritmética `+ - * /`, parênteses e `IFERROR(expr, "")`.
 * Qualquer outra função devolve null ("não sei avaliar") — é melhor um teste
 * dizer "não sei" do que afirmar 0 e passar verde por engano.
 */
import type ExcelJS from "exceljs";

export type Valor = number | string | null;

export function avaliarCelula(
  ws: ExcelJS.Worksheet,
  col: string,
  row: number,
  prof = 0,
): Valor {
  if (prof > 24) return null;
  const v = ws.getRow(row).getCell(col).value;
  if (v == null) return null;
  if (typeof v === "number") return v;
  if (typeof v === "string") return v;
  if (typeof v === "object" && "formula" in v) {
    return avaliarExpressao((v as ExcelJS.CellFormulaValue).formula, ws, prof + 1);
  }
  if (typeof v === "object" && "result" in v) {
    const r = (v as { result?: unknown }).result;
    return typeof r === "number" || typeof r === "string" ? r : null;
  }
  return null;
}

/** Avalia uma expressão de fórmula (sem o "=" inicial). */
export function avaliarExpressao(src: string, ws: ExcelJS.Worksheet, prof = 0): Valor {
  if (prof > 24) return null;
  let i = 0;
  const s = src;

  const pular = () => { while (i < s.length && s[i] === " ") i++; };

  // expr := termo (('+'|'-') termo)*
  const expr = (): Valor => {
    let acc = termo();
    for (;;) {
      pular();
      const op = s[i];
      if (op !== "+" && op !== "-") return acc;
      i++;
      const d = termo();
      if (typeof acc !== "number" || typeof d !== "number") return null;
      acc = op === "+" ? acc + d : acc - d;
    }
  };

  // termo := fator (('*'|'/') fator)*
  const termo = (): Valor => {
    let acc = fator();
    for (;;) {
      pular();
      const op = s[i];
      if (op !== "*" && op !== "/") return acc;
      i++;
      const d = fator();
      if (typeof acc !== "number" || typeof d !== "number") return null;
      if (op === "/") {
        if (d === 0) return null; // divisão por zero: é o que o IFERROR captura
        acc = acc / d;
      } else acc = acc * d;
    }
  };

  const fator = (): Valor => {
    pular();
    if (s[i] === "-") { i++; const v = fator(); return typeof v === "number" ? -v : null; }
    if (s[i] === "(") {
      i++;
      const v = expr();
      pular();
      if (s[i] === ")") i++;
      return v;
    }
    if (s[i] === '"') {
      i++;
      let t = "";
      while (i < s.length && s[i] !== '"') t += s[i++];
      i++;
      return t;
    }
    // número
    const mNum = /^[0-9]+(\.[0-9]+)?/.exec(s.slice(i));
    if (mNum) { i += mNum[0].length; return Number(mNum[0]); }

    // função ou referência
    const mId = /^([A-Za-z_][A-Za-z0-9_.]*)/.exec(s.slice(i));
    if (!mId) return null;
    const id = mId[1];
    const depoisId = i + id.length;

    if (s[depoisId] === "(") {
      i = depoisId + 1;
      const args: Valor[] = [];
      const brutos: string[] = [];
      for (;;) {
        pular();
        const inicio = i;
        // SUM aceita range: captura o texto cru do argumento também
        let nivel = 0;
        while (i < s.length) {
          const ch = s[i];
          if (ch === "(") nivel++;
          if (ch === ")") { if (nivel === 0) break; nivel--; }
          if (ch === "," && nivel === 0) break;
          if (ch === '"') { i++; while (i < s.length && s[i] !== '"') i++; }
          i++;
        }
        brutos.push(s.slice(inicio, i).trim());
        if (s[i] === ",") { i++; continue; }
        if (s[i] === ")") { i++; break; }
        break;
      }
      const nome = id.toUpperCase();
      if (nome === "SUM") {
        let t: number | null = null;
        for (const bruto of brutos) {
          const mRange = /^([A-Z]+)([0-9]+):([A-Z]+)([0-9]+)$/.exec(bruto);
          if (mRange) {
            const [, c1, r1, , r2] = mRange;
            for (let r = Number(r1); r <= Number(r2); r++) {
              const x = avaliarCelula(ws, c1, r, prof + 1);
              if (typeof x === "number") t = (t ?? 0) + x;
            }
          } else {
            const x = avaliarExpressao(bruto, ws, prof + 1);
            if (typeof x === "number") t = (t ?? 0) + x;
          }
        }
        return t;
      }
      if (nome === "IFERROR") {
        const v = avaliarExpressao(brutos[0] ?? "", ws, prof + 1);
        if (v == null) {
          const alt = brutos[1] ?? '""';
          return avaliarExpressao(alt, ws, prof + 1);
        }
        return v;
      }
      // função desconhecida: devolve os argumentos avaliados só para não travar
      void args;
      return null;
    }

    const mRef = /^([A-Z]+)([0-9]+)$/.exec(id);
    if (mRef) {
      i = depoisId;
      return avaliarCelula(ws, mRef[1], Number(mRef[2]), prof + 1);
    }
    return null;
  };

  const out = expr();
  return out;
}

/** Colunas de valor (todas menos a coluna A do rótulo). */
export function colunasDeValor(ws: ExcelJS.Worksheet): string[] {
  const cols: string[] = [];
  for (let c = 2; c <= ws.columnCount; c++) cols.push(ws.getColumn(c).letter);
  return cols;
}

/**
 * Uma linha está "100% vazia" quando NENHUMA coluna de valor tem conteúdo.
 * Zero CONTA como conteúdo: se o documento diz que a conta é 0,00, isso é
 * informação (e apagar a linha esconderia o que o arquivo declarou).
 */
export function linhaVazia(ws: ExcelJS.Worksheet, row: number): boolean {
  for (const c of colunasDeValor(ws)) {
    const v = avaliarCelula(ws, c, row);
    if (typeof v === "number") return false;
    if (typeof v === "string" && v.trim() !== "") return false;
  }
  return true;
}
