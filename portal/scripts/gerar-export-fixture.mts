// Grava em disco o .xlsx que o export produz a partir do book sintético.
//
// PARA QUE ISTO EXISTE: o critério de pronto da F2 (`docs/09`) é humano — "cada
// estágio na versão completa em Modo Conservador; pendências tipadas corretas;
// portões com limites duros funcionando" — e nenhuma suíte substitui alguém
// abrindo o arquivo e conferindo contra o gabarito. Até aqui não havia como fazer
// isso sem rodar o pipeline ao vivo (dinheiro) ou subir o portal com banco: o
// `verificar-export.mts` monta o workbook em memória e não escreve nada.
//
// Custo zero e sem IA: usa a MESMA fixture das suítes
// (`portal/scripts/fixtures/book-vertentes.json`, extração fiel dos 14 PDFs
// sintéticos) e o MESMO `buildExportWorkbook` que o portal chama em produção.
//
//   ./portal/node_modules/.bin/tsx portal/scripts/gerar-export-fixture.mts [saida.xlsx]
//
// A data é FIXA (2026-07-27), como em todo gerador deste repositório: `new Date()`
// aqui faria o arquivo mudar sozinho na virada do dia e um diff de bytes acusar
// mudança onde não houve — a mesma armadilha que já deixou o CI vermelho por
// não-motivo.

import { readFileSync } from "node:fs";
import { buildExportWorkbook, type DocumentoParaExport } from "../src/lib/export";
import type { CampoExtraido } from "../src/lib/types";

const saida = process.argv[2] ?? "/tmp/book-vertentes.xlsx";

const fixture = JSON.parse(
  readFileSync(new URL("./fixtures/book-vertentes.json", import.meta.url), "utf8"),
) as { documentos: DocumentoParaExport[]; campos: CampoExtraido[] };

const wb = buildExportWorkbook({
  caso: { nome: "Book Vertentes (sintético)", produto: "reestruturacao" },
  documentos: fixture.documentos,
  campos: fixture.campos,
  agora: new Date("2026-07-27T12:00:00Z"),
});

await wb.xlsx.writeFile(saida);

const abas = wb.worksheets.map((w) => `${w.name}${w.state === "visible" ? "" : ` (${w.state})`}`);
console.log(`Escrito: ${saida}`);
console.log(`Abas, na ordem em que o Excel mostra: ${abas.join(" · ")}`);
console.log(`Documentos: ${fixture.documentos.length} · linhas extraídas: ${fixture.campos.length}`);
