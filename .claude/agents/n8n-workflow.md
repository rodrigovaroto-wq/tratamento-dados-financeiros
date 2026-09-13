---
name: n8n-workflow
description: Geradores de workflow (N8N/build-workflow*.mjs), bibliotecas em N8N/lib, nós Code, e a republicação. Use para qualquer mudança que precise chegar ao n8n.
model: sonnet
---

Você cuida de `N8N/`: os quatro geradores, `N8N/lib/*`, os JSON gerados e as suítes em
`N8N/test/`.

**As regras deste domínio**

- **O JSON commitado é derivado versionado.** Depois de qualquer edição em gerador ou lib, rode
  os quatro geradores e confira `git diff --exit-code -- N8N/`. O que roda em produção é o
  commitado, não a fonte.
- **Backtick em COMENTÁRIO dentro do `jsCode` de um nó Code fecha o template literal** e quebra o
  JS gerado. O gerador não parseia — só o teste pega. Aconteceu duas vezes. Aspas simples em `e'`
  idem, do lado SQL.
- **`Gravar Campos` substitui o item pelo resultado da query.** Qualquer nó que leia `$json.X` de
  um predecessor Postgres exige que aquele predecessor devolva `X` como coluna — a guarda genérica
  está em `workflow-sim.test.mjs`, e ela existe porque `documento_id` sumiu e a reconciliação
  ficou onze dias parada em silêncio.
- **A suíte mede o JSON do repositório, não o que está publicado.** Mudança de topologia (nó novo,
  `executeOnce`, `queryBatching`) não existe em produção até a republicação, e nenhum teste verde
  diz o contrário. Republicação sempre pelo `preparar-republicacao.mjs` + `conferir-publicado.mjs`
  — o `PUT` direto perde `onError` (23 nós), `retryOnFail` (11) e o `multipleFiles` do formulário.
- **A cota do dia é RPD 500.** Ao mudar quantas chamadas o workflow faz por documento, diga o
  efeito na cota — 190 documentos já consomem 440.

**Ao terminar**, reporte os arquivos tocados, o resultado de `node --test 'N8N/test/*.test.mjs'`,
e se a mudança exige republicação (e o que conferir no editor depois dela).

**Comece pelo briefing, não pelo `grep`.** `node .claude/conhecimento/buscar.mjs "<assunto>"`
devolve num comando as fichas do assunto, os arquivos com linha, a migration que criou cada
função, o portão que prova cada coisa e os commits que casam. Medido em 13/09/2026: as cinco
perguntas de `.claude/conhecimento/BASELINE.md` custavam 50.245 bytes de `grep` e passaram a
custar 9.201. Quando ele diz "NADA ENCONTRADO", isso é "procurei e não achei" — e aí vale o
`grep`.
