#!/usr/bin/env node
// PreToolUse(Bash) — a ÚNICA trava dura deste projeto.
//
// POR QUE ELA EXISTE, e não é higiene genérica. O protocolo obrigatório de medir um invariante
// não-vazio (desligar a correção, rodar a suíte, religar) leva DIRETO ao comando que restaura um
// arquivo a partir do índice — e ele restaura o arquivo INTEIRO: todo o trabalho não commitado no
// mesmo arquivo vai junto, sem aviso e sem desfazer. Custou a sessão 19.
//
// Esta é a única exceção ao fail-open deste conjunto de hooks: aqui deixar passar é irreversível,
// e bloquear custa uma linha de comando reescrita.
//
// POR QUE A ANÁLISE É POR LINHA, E POR QUE O CAMINHO É EXIGIDO. A primeira versão casava sobre o
// comando inteiro e bloqueou uma MENSAGEM DE COMMIT que descrevia este próprio hook: o `restore`
// estava numa linha e o `--staged` que o inocentava, na seguinte — fora do alcance do lookahead,
// porque `.` não casa quebra de linha. Portão que reprova por RUÍDO é pior que portão nenhum (ver
// `.claude/memory/portao-pode-reprovar-por-ruido.md`), então cada linha passa a ser julgada
// sozinha e o descarte só conta quando há de fato um caminho na linha.
//
// LIMITAÇÃO CONHECIDA E ACEITA: prosa dentro de um heredoc que reproduza a forma exata de um
// comando destrutivo ainda bloqueia. O custo é reescrever a frase; o custo do erro oposto é
// trabalho perdido sem desfazer.

import { lerEvento } from "./hook-io.mjs";

const ev = lerEvento();
if (ev === null) process.exit(0);
if (ev.tool_name !== "Bash") process.exit(0);

const cmd = ev?.tool_input?.command ?? "";
if (typeof cmd !== "string" || !cmd) process.exit(0);

// Descarte via `checkout`: o separador `--` seguido de caminho é o que distingue o descarte de
// arquivo da troca de branch (`checkout -b x`, `checkout main`), que é legítima e comum.
const descartaPorCheckout = /\bgit\s+(?:-C\s+\S+\s+)?checkout\b[^|;&]*\s--\s+\S/;

// Descarte via `restore`: exige um caminho de verdade na MESMA linha — um token que não começa
// com `-`. Isso dispensa de uma vez as formas que não descartam a árvore (`--staged`,
// `--worktree --staged`) e o verbo solto no meio de uma frase.
const descartaPorRestore = /\bgit\s+(?:-C\s+\S+\s+)?restore\s+(?!-)\S/;

const linha = cmd
  .split("\n")
  .find((l) => descartaPorCheckout.test(l) || descartaPorRestore.test(l));

if (!linha) process.exit(0);

console.error(
  [
    "BLOQUEADO: este comando descarta o arquivo INTEIRO, não só o patch que você aplicou.",
    `  ${linha.trim()}`,
    "",
    "Restaurar um arquivo a partir do índice leva junto TODO o trabalho não commitado nele, sem",
    "aviso e sem desfazer. Foi assim que a sessão 19 perdeu trabalho ao reverter um patch de",
    "medição de invariante.",
    "",
    "O caminho seguro, e é o do protocolo:",
    '  cp <arquivo> "$SCRATCH/<arquivo>.bak"   # ANTES de desligar a correção',
    "  ...  aplica o patch, roda a suíte, conta os asserts que reprovaram  ...",
    '  cp "$SCRATCH/<arquivo>.bak" <arquivo>    # restaura só o que você mexeu',
    "",
    "Ver `.claude/memory/git-checkout-apaga-trabalho.md`.",
    "Se o descarte é mesmo o que você quer, faça pelo `cp` ou confirme com o dono.",
  ].join("\n"),
);
process.exit(2);
