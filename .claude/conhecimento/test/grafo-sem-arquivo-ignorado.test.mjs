// O GRAFO NÃO PODE CITAR ARQUIVO QUE O GIT IGNORA.
//
// O DEFEITO QUE ESTE ARQUIVO EXISTE PARA PEGAR, medido em 21/09/2026 (PR #238):
// o `indexar.mjs` pulava três diretórios POR NOME (`node_modules`, `.git`,
// `.next`) e não consultava o `.gitignore`. Uma sessão rodou
// `Verificação/variacoes.mts` — que grava 51 arquivos em `Verificação/saida/`,
// gitignored — ANTES de `indexar.mjs`, que é a ordem em que o bloco de comandos
// do `CLAUDE.md` os lista. O grafo commitado saiu com 50 nós e arestas que não
// existem num checkout limpo, e o CI reprovou em "o grafo commitado diverge do
// repositório". O conteúdo do grafo dependia de quais scripts a sessão tinha
// rodado antes — um portão cujo veredito é função do estado local de quem
// commitou é a regra 7 do CLAUDE.md aplicada à própria ferramenta de memória.
//
// POR QUE ESTE TESTE OLHA O ARTEFATO, E NÃO O INDEXADOR (regra 3 — invariante
// afirma COMPORTAMENTO, não mecanismo): a afirmação aqui é "o grafo commitado
// descreve o repositório, não a máquina de quem o gerou". Ela continua verdadeira
// e continua cobrável se alguém trocar a implementação do `indexar.mjs` (lista de
// nomes, `git ls-files`, `.gitignore` lido à mão, o que for). Um teste que
// espiasse a constante `IGNORADOS` do indexador protegeria o mecanismo e deixaria
// o defeito passar pela porta do lado.
//
// MEDIÇÃO NÃO-VAZIA (regra 2), EXECUTADA em 21/09/2026: rodado contra o
// `grafo.jsonl` do commit 070b0c2 (o que quebrou o CI), este arquivo REPROVA e
// nomeia 25 caminhos distintos sob `Verificação/saida/`. Rodado contra o grafo
// corrigido (28060ee em diante), passa. O protocolo do indexador foi medido em
// separado: com a correção desligada e os 51 artefatos reais no disco, o grafo
// ganha exatamente 50 linhas.

import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { execFileSync } from "node:child_process";

const RAIZ = new URL("../../..", import.meta.url).pathname.replace(/\/$/, "");
const GRAFO = `${RAIZ}/.claude/conhecimento/grafo.jsonl`;

/** Todo caminho citado por um nó ou aresta do grafo, sem repetição. */
function caminhosDoGrafo() {
  const vistos = new Set();
  for (const linha of readFileSync(GRAFO, "utf8").split("\n")) {
    if (!linha) continue;
    const f = JSON.parse(linha).f;
    if (f) vistos.add(f);
  }
  return [...vistos].sort();
}

test("nenhum caminho do grafo é um caminho que o git ignora", () => {
  const caminhos = caminhosDoGrafo();
  assert.ok(caminhos.length > 0, "o grafo não citou caminho nenhum — leitura falhou");

  // `check-ignore --stdin -z` numa chamada só: uma por caminho custaria milhares
  // de processos. Sai com 1 quando NENHUM casa, que é o caso verde — por isso o
  // status não pode ser tratado como erro.
  let saida = "";
  try {
    saida = execFileSync("git", ["check-ignore", "--stdin", "-z"], {
      cwd: RAIZ,
      input: caminhos.join("\0"),
      encoding: "utf8",
    });
  } catch (e) {
    if (e.status === 1) saida = "";          // nenhum ignorado: o caso verde
    else throw e;
  }

  const ignorados = saida.split("\0").filter(Boolean);
  assert.deepEqual(
    ignorados,
    [],
    `o grafo cita ${ignorados.length} caminho(s) que o git ignora — eles não existem ` +
      `num checkout limpo, então o portão do CI vai acusar divergência. Apague o ` +
      `artefato gerado e rode node .claude/conhecimento/indexar.mjs de novo:\n  ` +
      ignorados.join("\n  "),
  );
});
