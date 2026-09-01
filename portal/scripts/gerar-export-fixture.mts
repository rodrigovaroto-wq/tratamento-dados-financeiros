// Grava em disco o .xlsx que o export produz a partir do book sintético.
//
// PARA QUE ISTO EXISTE: o critério de pronto da F2 (`Arquitetura do Sistema/3 Estado e Execução/09`) é humano — "cada
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

import { mkdtempSync, readFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { buildExportWorkbook, type DocumentoParaExport } from "../src/lib/export";
import type { CampoExtraido } from "../src/lib/types";
import { entradaModeloDaFixture } from "./lib/modelo-da-fixture.mts";

const args = process.argv.slice(2);
// Sem caminho explícito no argv, o padrão NÃO é um nome fixo dentro de /tmp
// (sonar typescript:S5443) — mesmo motivo do `gerar-export-do-banco.mts`:
// nome previsível num diretório gravável por qualquer processo da máquina.
// `mkdtempSync` cria um diretório de nome imprevisível e modo 0700 (só o dono).
const saida = args.find((a) => !a.startsWith("--"))
  ?? join(mkdtempSync(join(tmpdir(), "gerar-export-fixture-")), "book-vertentes.xlsx");
// `--modo=dados` gera o export de conferência (sem Modelagem); sem a flag sai o
// completo. Os dois saem do MESMO builder, de propósito: as abas de dado têm de
// ser idênticas nos dois arquivos.
const modo = args.includes("--modo=dados") ? "dados" : "completo";

const fixture = JSON.parse(
  readFileSync(new URL("./fixtures/book-vertentes.json", import.meta.url), "utf8"),
) as { documentos: DocumentoParaExport[]; campos: CampoExtraido[] };

const wb = buildExportWorkbook({
  caso: { nome: "Book Vertentes (sintético)", produto: "reestruturacao" },
  documentos: fixture.documentos,
  campos: fixture.campos,
  agora: new Date("2026-07-27T12:00:00Z"),
  modo,
  // O MODELO INSTITUCIONAL (14 abas) montado da mesma fixture. Só no completo:
  // o modo "dados" não projeta, por decisão do dono.
  modeloInstitucional: modo === "completo"
    ? entradaModeloDaFixture(fixture, new Date("2026-07-27T12:00:00Z"))
    : undefined,
});

await wb.xlsx.writeFile(saida);

const abas = wb.worksheets.map((w) => `${w.name}${w.state === "visible" ? "" : ` (${w.state})`}`);
console.log(`Escrito: ${saida}  (modo=${modo})`);
console.log(`Abas, na ordem em que o Excel mostra: ${abas.join(" · ")}`);
console.log(`Documentos: ${fixture.documentos.length} · linhas extraídas: ${fixture.campos.length}`);
