// Suíte do hook de início de sessão — o aviso de "derivado versionado sujo".
//
// POR QUE ELA EXISTE (24/09/2026). O hook `sessao-inicio.mjs` avisa, antes de a sessão decidir
// qualquer coisa, que há derivado versionado modificado e não commitado — o JSON do workflow, as
// fixtures, o schema: o que roda é o commitado, não a fonte. A lista dele era escrita à mão e já
// tinha ficado para trás do CI: faltavam `N8N/workflow.diagnostico-ia.json` e o
// `.claude/conhecimento/grafo.jsonl`, que o `suites.yml` prende com `git diff --exit-code`. O
// aviso ficava calado exatamente sobre eles — lembrete desligado com a aparência de lembrete sem
// nada a dizer (`.claude/memory/hook-derivados-morre-calado-na-renomeacao.md`).
//
// O QUE SE AFIRMA é o cruzamento das duas pontas, não a lista: todo arquivo que o CI prende por
// `git diff --exit-code` (lido do próprio `suites.yml`) aparece no aviso quando está sujo. O hook é
// executado de verdade, numa cópia temporária do repositório com cada derivado modificado.

import { test } from "node:test";
import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { appendFileSync, mkdtempSync, readFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { fileURLToPath } from "node:url";
import { dirname, join, resolve } from "node:path";

const AQUI = dirname(fileURLToPath(import.meta.url));
const HOOK = join(AQUI, "..", "sessao-inicio.mjs");
const RAIZ = resolve(AQUI, "..", "..", "..");

/** Os caminhos que o `suites.yml` prende com `git diff --exit-code -- …` (com continuação `\`). */
function derivadosDoCi() {
  const yml = readFileSync(join(RAIZ, ".github/workflows/suites.yml"), "utf8");
  const caminhos = [];
  for (const m of yml.matchAll(/git diff --exit-code -- ((?:[^\n|]*\\\n)*[^\n|]*)/g)) {
    for (const c of m[1].replace(/\\\n/g, " ").split(/\s+/)) if (c && c !== "\\") caminhos.push(c);
  }
  // Diretório inteiro (hoje só `N8N/`): o que os geradores escrevem nele são os `workflow.*.json`.
  return caminhos.flatMap((c) => c.endsWith("/")
    ? execFileSync("git", ["ls-files", "--", `${c}workflow.*.json`], { cwd: RAIZ, encoding: "utf8" })
      .split("\n").filter(Boolean)
    : [c]);
}

test("controle positivo: o suites.yml prende ao menos os derivados que se sabe existirem", () => {
  const d = derivadosDoCi();
  for (const esperado of ["N8N/workflow.e1-ingestao.json", "Supabase/schema.sql",
    "Supabase/test/fixture_book_vertentes.sql", ".claude/conhecimento/grafo.jsonl"]) {
    assert.ok(d.includes(esperado), `o leitor do suites.yml não achou ${esperado} — ele não está lendo o que devia`);
  }
});

test("todo derivado que o CI prende aparece no aviso de início de sessão quando está sujo", () => {
  const derivados = derivadosDoCi();
  const copia = mkdtempSync(join(tmpdir(), "sessao-inicio-"));
  try {
    execFileSync("git", ["clone", "-q", "--shared", RAIZ, copia]);
    for (const d of derivados) appendFileSync(join(copia, d), "\n");
    const saida = execFileSync("node", [HOOK], { cwd: copia, input: "{}", encoding: "utf8" });
    const faltando = derivados.filter((d) => !saida.includes(d));
    assert.deepEqual(faltando, [], `derivado sujo que o aviso NÃO cita: ${faltando.join(", ")}`);
  } finally {
    rmSync(copia, { recursive: true, force: true });
  }
});
