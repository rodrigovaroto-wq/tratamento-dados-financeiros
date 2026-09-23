#!/usr/bin/env node
// PostToolUse(Edit|Write) — lembra o que a edição acabou de tornar desatualizado.
//
// POR QUE. Vários artefatos versionados aqui são GERADOS, e é o commitado que roda: o JSON que o
// dono importa no n8n, a fixture que as suítes leem, o `Supabase/schema.sql` que alguém abre para
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
    // `N8N/` maiúsculo: a regex é sensível a caixa, e escrever `n8n/` deixou esta regra muda
    // desde a renomeação de agosto — medido em 16/09/2026 por `test/lembrar-derivados.test.mjs`.
    quando: /N8N\/(build-workflow[^/]*\.mjs|lib\/)/,
    aviso:
      "Você tocou a fonte dos workflows. Rode os QUATRO geradores e confira `git diff --exit-code -- N8N/`: " +
      "é o JSON commitado que o dono importa. E `node --test 'N8N/test/*.test.mjs'` — um backtick num " +
      "comentário do `jsCode` quebra o nó, e o gerador não parseia.",
  },
  {
    // Era `db/migrations/`, diretório que este repositório não tem desde a renomeação.
    quando: /Supabase\/migrations\/\d{4}_/,
    aviso:
      "Migration nova: (a) acrescente o requisito ao catálogo da sonda — o `run.sh` reprova se ele ficar " +
      "para trás; (b) rode `Supabase/test/run.sh` e commite o `Supabase/schema.sql` que ele reescreve; (c) o topo do " +
      "`ESTADO.md` tem de citar esta migration; (d) escrita ≠ aplicada — só a sonda responde por produção.",
  },
  {
    // Era `test-data/` e `db/test/`; hoje são `Dados de Teste/` e `Supabase/test/`.
    quando: /Dados de Teste\/[^/]+\/(motor|gerar)\.py|Supabase\/test\/gerar_fixture/,
    aviso:
      "Você mexeu no gerador do book. As TRÊS fixtures derivadas (o `.sql` do banco, o `.json` do export e " +
      "o `GABARITO.json`) se comparam entre si — desincronizar uma faz as outras duas mentirem sobre a " +
      "terceira. Regere as três e confira o `git diff`.",
  },
  {
    // O GRAFO DO CONHECIMENTO é derivado e versionado, e faltava aqui. MEDIDO em 21/09/2026 (PR
    // #238): uma edição de 10 linhas no `suites.yml` deslocou o número de linha de TODO passo de CI
    // abaixo dela — os nós `portao` guardam essa linha —, o grafo não foi regerado, e o CI reprovou
    // em "o grafo commitado diverge". Este hook existe exatamente para lembrar isso e não sabia que
    // o grafo existia. As entradas cobertas são as que `indexar.mjs` lê e que não são óbvias:
    // o workflow de CI, as fichas e a memória, e o HANDOFF. (Migration já tem regra própria acima.)
    //
    // FORA DE PROPÓSITO, e revisado em 23/09/2026: `MEMORY.md` e `INSTRUCTIONS.md`, que o
    // `indexar.mjs:269` exclui — avisar sobre eles era ruído. E os ARQUIVOS DE CÓDIGO, embora as
    // arestas CHAMA do grafo guardem a linha de cada chamada (uma linha a mais num `.test.mjs`
    // desloca o grafo): cobri-los faria este aviso disparar em quase toda edição, e portão que fala
    // demais é ignorado (`portao-pode-reprovar-por-ruido.md`). Esse caso o CI pega.
    quando: /\.github\/workflows\/suites\.yml$|\.claude\/conhecimento\/fichas\/[^/]+\.md$|\.claude\/memory\/(?!MEMORY\.md$|INSTRUCTIONS\.md$)[^/]+\.md$|(^|\/)HANDOFF\.md$/,
    aviso:
      "Você editou uma ENTRADA do grafo do conhecimento — `.claude/conhecimento/grafo.jsonl` é DERIVADO e " +
      "versionado. Rode `node .claude/conhecimento/indexar.mjs` e commite o grafo na MESMA passada, senão o CI " +
      "reprova em \"o grafo commitado diverge\". No `suites.yml`, até um comentário conta: os nós de portão " +
      "guardam o NÚMERO DA LINHA de cada passo, e uma linha a mais desloca todos os que vêm depois.",
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
