// Suíte do hook que lembra o derivado que a edição acabou de tornar desatualizado.
//
// POR QUE ELA EXISTE, e o número que a justifica. MEDIDO em 16/09/2026, antes da correção:
// das cinco entradas reais abaixo, QUATRO saíam em silêncio. As regras casavam `n8n/`
// (o diretório é `N8N/`, e a regex é sensível a caixa), `db/migrations/` e `test-data/` —
// caminhos que este repositório NÃO TEM desde a renomeação de agosto: são `Supabase/migrations/`
// e `Dados de Teste/`. Só a regra do portal disparava.
//
// Isso é o modo de falha central deste projeto dentro do próprio ferramental: um lembrete
// desligado é indistinguível de um lembrete que rodou e não tinha o que dizer
// (`.claude/memory/estagio-desligado-parece-limpo.md`). O hook é fail-open e silencioso de
// propósito, então NADA acusava — não havia suíte, e o CI já rodava `.claude/hooks/test/*`.
//
// A GUARDA CONTRA A PRÓXIMA RENOMEAÇÃO é o segundo bloco: cada caminho de exemplo tem de EXISTIR
// no repositório. Foi a renomeação que matou as regras da primeira vez; um caminho de exemplo que
// deixa de existir passa a reprovar aqui, em vez de virar silêncio em produção.

import { test } from "node:test";
import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { existsSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join, resolve } from "node:path";

const AQUI = dirname(fileURLToPath(import.meta.url));
const HOOK = join(AQUI, "..", "lembrar-derivados.mjs");
const RAIZ = resolve(AQUI, "..", "..", "..");

/** Roda o hook com uma edição naquele caminho e devolve o texto do aviso (ou ""). */
function avisoPara(caminhoRelativo) {
  const saida = execFileSync("node", [HOOK], {
    input: JSON.stringify({
      hook_event_name: "PostToolUse",
      tool_name: "Edit",
      tool_input: { file_path: join(RAIZ, caminhoRelativo) },
    }),
    encoding: "utf8",
  });
  if (!saida.trim()) return "";
  return JSON.parse(saida).hookSpecificOutput.additionalContext;
}

// Um caminho REAL por regra — não um construído para ser conveniente. Os quatro primeiros são as
// quatro famílias de derivado versionado deste repositório.
const CASOS = [
  { caminho: "N8N/build-workflow.mjs", espera: /QUATRO geradores/ },
  { caminho: "N8N/lib/extract.mjs", espera: /QUATRO geradores/ },
  { caminho: "Supabase/migrations/0177_a_guarda_do_balcao_ia_so_num_sentido.sql", espera: /catálogo da sonda/ },
  { caminho: "Dados de Teste/book-vertentes/gerar.py", espera: /TRÊS fixtures/ },
  { caminho: "portal/src/lib/export.ts", espera: /Endereço de célula é contrato/ },
];

test("as cinco entradas reais disparam o aviso do seu derivado", () => {
  const mudos = CASOS.filter((c) => !c.espera.test(avisoPara(c.caminho)));
  assert.deepEqual(
    mudos.map((c) => c.caminho),
    [],
    "caminho real que o hook deixou passar em silêncio — a regra não casa o repositório de hoje",
  );
});

test("o caminho de exemplo de cada regra existe no repositório", () => {
  // É esta asserção que descobre a PRÓXIMA renomeação. Sem ela, a suíte acima continuaria verde
  // testando um caminho que ninguém mais usa.
  const sumidos = CASOS.filter((c) => !existsSync(join(RAIZ, c.caminho)));
  assert.deepEqual(sumidos.map((c) => c.caminho), [], "caminho de exemplo não existe mais");
});

test("arquivo sem derivado não gera ruído", () => {
  // Portão que fala demais é ignorado, e aí não fala nada (`portao-pode-reprovar-por-ruido.md`).
  for (const caminho of ["CLAUDE.md", "portal/src/app/page.tsx", "Supabase/test/run.sh"]) {
    assert.equal(avisoPara(caminho), "", `${caminho} não deveria gerar aviso`);
  }
});

test("evento malformado não derruba a sessão — fail-open", () => {
  for (const entrada of ["null", "", "{}", '{"tool_input":null}']) {
    const saida = execFileSync("node", [HOOK], { input: entrada, encoding: "utf8" });
    assert.equal(saida.trim(), "");
  }
});
