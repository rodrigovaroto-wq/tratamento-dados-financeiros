// Suíte do hook que bloqueia o descarte de arquivo.
//
// POR QUE ELA EXISTE. Este hook é a única trava DURA do projeto, e uma trava dura erra de duas
// formas opostas, as duas caras:
//
//   • deixa passar o comando destrutivo  → trabalho não commitado some, sem desfazer (sessão 19);
//   • bloqueia o comando legítimo        → portão que reprova por ruído, que é pior que portão
//                                          nenhum. Já aconteceu: a primeira versão do hook casava
//                                          sobre o comando inteiro e bloqueou uma MENSAGEM DE
//                                          COMMIT que descrevia o próprio hook.
//
// Por isso os casos negativos (o que tem de PASSAR) são a maioria da suíte, e não um apêndice.
//
// Os comandos são montados por concatenação de propósito: escritos por extenso, este arquivo
// dispararia o próprio hook que ele testa toda vez que alguém o abrisse com uma ferramenta que
// passa o conteúdo por um shell.

import { test } from "node:test";
import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

const HOOK = join(dirname(fileURLToPath(import.meta.url)), "..", "proteger-descarte.mjs");

const G = "git ";
const CO = "check" + "out";
const RE = "rest" + "ore";

/** Roda o hook com um payload de stdin e devolve o código de saída. */
function rodar(payload) {
  try {
    execFileSync("node", [HOOK], { input: payload, stdio: ["pipe", "ignore", "ignore"] });
    return 0;
  } catch (e) {
    return e.status;
  }
}

const comComando = (command) => JSON.stringify({ tool_name: "Bash", tool_input: { command } });

const BLOQUEIA = 2;
const LIBERA = 0;

test("bloqueia o descarte de arquivo — as quatro formas que aparecem de verdade", () => {
  const destrutivos = [
    [`${G}${CO} -- portal/src/lib/export.ts`, "checkout com separador e caminho"],
    [`${G}${RE} Supabase/schema.sql`, "restore com caminho"],
    [`cd portal && ${G}${RE} src/lib/export.ts`, "restore depois de um encadeamento"],
    [`git -C portal ${RE} src/app/page.tsx`, "restore com -C"],
  ];
  for (const [cmd, rotulo] of destrutivos) {
    assert.equal(rodar(comComando(cmd)), BLOQUEIA, `devia bloquear: ${rotulo}`);
  }
});

test("não bloqueia o que é legítimo — troca de branch, unstage, e o `--` de outros comandos", () => {
  const legitimos = [
    [`${G}${CO} -b nova-branch`, "criar branch"],
    [`${G}${CO} main`, "trocar de branch"],
    [`${G}${RE} --staged arquivo.txt`, "tirar do índice não descarta a árvore"],
    [`${G}${RE} --worktree --staged x`, "a forma composta também não"],
    ["git log --oneline -- Supabase/schema.sql", "o `--` do log não é descarte"],
    ["npm test", "comando comum"],
  ];
  for (const [cmd, rotulo] of legitimos) {
    assert.equal(rodar(comComando(cmd)), LIBERA, `não devia bloquear: ${rotulo}`);
  }
});

test("não bloqueia PROSA — o falso positivo que a primeira versão cometeu", () => {
  // O caso real: a mensagem de commit que descrevia este hook. O verbo caía numa linha e a flag
  // que o inocentava, na seguinte — fora do alcance de um lookahead, porque `.` não casa quebra
  // de linha. A análise passou a ser por linha, e o caminho passou a ser exigido.
  const mensagemDeCommit =
    `git commit -F - <<EOF\n` +
    `frase citando ${G}${CO} -b, ${G}${CO} main), ${G}${RE}\n` +
    `--staged e o resto da frase\n` +
    `EOF`;
  assert.equal(rodar(comComando(mensagemDeCommit)), LIBERA, "prosa multilinha não é comando");

  assert.equal(
    rodar(comComando(`echo "o hook protege contra ${G}${RE}"`)),
    LIBERA,
    "verbo sem caminho não descarta nada",
  );
});

test("fail-open: payload degenerado libera, nunca lança", () => {
  // `JSON.parse("null")` devolve null SEM lançar — é o bug que o hook-io existe para fechar.
  // Um hook que morre com stack trace aqui vira um bloqueio acidental.
  for (const payload of ["null", "", "}{", "[]", '"texto"', "42"]) {
    assert.equal(rodar(payload), LIBERA, `payload degenerado devia liberar: ${payload || "<vazio>"}`);
  }
  assert.equal(
    rodar(JSON.stringify({ tool_name: "Read", tool_input: { file_path: "x" } })),
    LIBERA,
    "ferramenta que não é Bash não é assunto deste hook",
  );
});

test("a trava é não-vazia: sem a análise, o caso destrutivo passaria", () => {
  // Guarda contra o próprio teste envelhecer para verde. Se um dia as duas expressões deixarem de
  // casar o comando destrutivo canônico, o primeiro teste desta suíte reprova — mas este aqui diz
  // POR QUE, apontando a expressão, em vez de só acusar um código de saída errado.
  const destrutivoCanonico = `${G}${CO} -- portal/src/lib/export.ts`;
  const porCheckout = /\bgit\s+(?:-C\s+\S+\s+)?checkout\b[^|;&]*\s--\s+\S/;
  const porRestore = /\bgit\s+(?:-C\s+\S+\s+)?restore\s+(?!-)\S/;
  assert.ok(
    porCheckout.test(destrutivoCanonico) || porRestore.test(destrutivoCanonico),
    "nenhuma das duas expressões casa o comando destrutivo canônico — a trava está aberta",
  );
});
