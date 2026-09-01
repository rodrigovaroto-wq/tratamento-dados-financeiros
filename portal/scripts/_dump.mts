import ExcelJS from "exceljs";
import { avaliarCelula } from "./lib/avaliar-formula.mts";
const [ARQ, ABA, ate] = [process.argv[2], process.argv[3], Number(process.argv[4] ?? 120)];
const wb = new ExcelJS.Workbook(); await wb.xlsx.readFile(ARQ);
const ws = wb.getWorksheet(ABA)!;
const COLS = (process.argv[5] ?? "E,F,G").split(",");
const rot = (r: number) => [2,3,4].map((c) => { const v = ws.getRow(r).getCell(c).value;
  return typeof v === "string" ? v : v && typeof v === "object" && "richText" in (v as object)
    ? (v as {richText:Array<{text:string}>}).richText.map((t)=>t.text).join("")
    : v && typeof v === "object" && "formula" in (v as object) ? "{f}" : v == null ? "" : String(v); })
  .filter(Boolean).join(" · ");
for (let r = 1; r <= Math.min(ate, ws.rowCount); r++) {
  const rr = rot(r);
  const vals = COLS.map((c) => { const cel = ws.getRow(r).getCell(c); if (cel.value == null) return "";
    const v = avaliarCelula(ws, c, r);
    return v === null ? "não sei" : typeof v === "number" ? v.toLocaleString("pt-BR",{maximumFractionDigits:1}) : String(v).slice(0,15); });
  if (!rr && vals.every((v) => !v)) continue;
  console.log(`${String(r).padStart(3)} ${rr.slice(0,52).padEnd(53)} ${vals.map((v)=>v.padStart(13)).join("")}`);
}
