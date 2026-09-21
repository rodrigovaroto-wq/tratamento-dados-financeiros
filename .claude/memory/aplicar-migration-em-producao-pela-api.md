---
name: aplicar-migration-em-producao-pela-api
description: como aplicar migration em produção quando a porta do Postgres não é alcançável — a API de gerenciamento aceita o arquivo inteiro, mas envolve tudo numa transação implícita, e isso quebra qualquer migration com `alter type ... add value`
metadata:
  type: operations
tipo: ambiente
toca:
  - Supabase/migrations/0179_o_papel_no_grupo_que_nunca_foi_escrito.sql
---

**MEDIDO em 18/09/2026**, aplicando as migrations `0178`–`0181` no Supabase de produção.

## O caminho que funciona

A porta 5432 não é alcançável do container (`psql` contra o pooler expira em SIGTERM; a
conexão direta é IPv6 e o ambiente é IPv4). O que funciona é a **API de gerenciamento por
HTTPS**, que passa pelo proxy:

```bash
jq -Rs '{query: .}' < Supabase/migrations/NNNN_....sql > /tmp/payload.json
curl -sS -X POST "https://api.supabase.com/v1/projects/<ref>/database/query" \
  -H "Authorization: Bearer $SUPABASE_ACCESS_TOKEN" \
  -H "Content-Type: application/json" --data-binary @/tmp/payload.json
```

Resposta `[]` = sem erro. O `jq -Rs` é o detalhe que evita quebrar o arquivo: ele escapa o SQL
inteiro como uma string JSON, sem tocar em aspas, `$$` ou acentos.

## A ARMADILHA: `alter type ... add value` precisa de DUAS chamadas

A API envolve o lote numa **transação implícita**, e o Postgres proíbe usar um rótulo de enum
recém-criado dentro da mesma transação em que ele nasceu. Uma migration que acrescenta rótulo e o
usa (a `0179` faz as duas coisas) falha com **"unsafe use of new value of enum type"** — mesmo a
migration tendo sido escrita SEM `begin;`/`commit;` justamente para evitar isso. O arquivo está
certo; quem quebra é o transporte.

A saída, sem editar a migration versionada: mandar o `alter type` sozinho numa chamada, e depois
o resto do arquivo com **apenas aquela linha comentada** (gerar a cópia com `sed` no scratchpad e
conferir com `diff` que só uma linha mudou — nunca reescrever o arquivo do repositório).

## A OUTRA ARMADILHA: backfill não sabe o que é caso de teste

O backfill da `0179` (`where papel_no_grupo is null`) abriu **365 pendências** — uma por entidade
de **todo** o banco, 70 casos, e a esmagadora maioria é caso de teste morto (`teste v13`,
`araucária test 52`, …). O número previsto para o mandato real era 13. Mediu-se antes de aplicar
e mesmo assim foi preciso resolver **347** em lote depois, com `resolvida_por =
'sessao-claude:ruido-de-caso-de-teste'` e evento `pendencias_papel_resolvidas_em_lote`.

**A lição para a próxima migration com backfill:** medir quantas linhas o `where` alcança em
PRODUÇÃO antes de escrever, não depois de aplicar — um critério pensado para um mandato (8
entidades) alcança o banco inteiro (365). Contraste: o backfill da `0178`, que exige a conjunção
sem-CNPJ + léxico + 1 documento, marcou **7** — previsto 7, conferido 7.
