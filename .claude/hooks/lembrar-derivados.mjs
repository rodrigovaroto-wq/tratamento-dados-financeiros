#!/usr/bin/env node
// PostToolUse(Edit|Write) — lembra o que a edição acabou de tornar desatualizado.
//
// POR QUE. Vários artefatos versionados aqui são GERADOS, e é o commitado que roda: o JSON que o
// dono importa no n8n, a fixture que as suítes leem, o `db/schema.sql` que alguém abre para
// entender o banco. Editar a fonte sem regerar o derivado deixa os dois divergirem em silêncio —
// aconteceu em 19/08, e a suíte de export reprovou comparando um export novo com um gabarito
// novo a partir de uma fixture velha.
//
// FAIL-OPEN: isto adiciona um lembrete, não impõe limite. Qualquer falha vira silêncio.

import { lerEvento } from "./hook-io.mjs";

const ev = lerEvento();
if (ev === null) process.exit(0);

const caminho = ev?.tool_input?.file_path ?? "";
if (typeof caminho !== "string" || !caminho) process.exit(0);

const regras = [
  {
    quando: /n8n\/(build-workflow[^/]*\.mjs|lib\/)/,
    aviso:
      "Você tocou a fonte dos workflows. Rode os QUATRO geradores e confira `git diff --exit-code -- n8n/`: " +
      "é o JSON commitado que o dono importa. E `node --test 'n8n/test/*.test.mjs'` — um backtick num " +
      "comentário do `jsCode` quebra o nó, e o gerador não parseia.",
  },
  {
    quando: /db\/migrations\/\d{4}_/,
    aviso:
      "Migration nova: (a) acrescente o requisito ao catálogo da sonda — o `run.sh` reprova se ele ficar " +
      "para trás; (b) rode `db/test/run.sh` e commite o `db/schema.sql` que ele reescreve; (c) o topo do " +
      "`ESTADO.md` tem de citar esta migration; (d) escrita ≠ aplicada — só a sonda responde por produção.",
  },
  {
    quando: /test-data\/[^/]+\/(motor|gerar)\.py|db\/test\/gerar_fixture/,
    aviso:
      "Você mexeu no gerador do book. As TRÊS fixtures derivadas (o `.sql` do banco, o `.json` do export e " +
      "o `GABARITO.json`) se comparam entre si — desincronizar uma faz as outras duas mentirem sobre a " +
      "terceira. Regere as três e confira o `git diff`.",
  },
  {
    quando: /portal\/src\/lib\/(export|modelo-institucional)\.ts/,
    aviso:
      "Endereço de célula é contrato: `spliceRows` na aba Macro desloca `linhaCabFocus` e cada INDEX/MATCH " +
      "passa a apontar uma linha acima; `P(i)` endereça premissa por deslocamento a partir de `rPremissas`. " +
      "Referência e conferência vão DEPOIS do bloco de premissas, nunca no meio. Rode `verificar-export.mts`.",
  },
];

const avisos = regras.filter((r) => r.quando.test(caminho)).map((r) => r.aviso);
if (!avisos.length) process.exit(0);

console.log(
  JSON.stringify({
    hookSpecificOutput: {
      hookEventName: "PostToolUse",
      additionalContext: avisos.join("\n\n"),
    },
  }),
);
process.exit(0);
