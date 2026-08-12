# Estado do projeto — leia isto antes do `HANDOFF.md`

Este arquivo responde **onde o projeto está agora**. O `HANDOFF.md` responde **como chegou aqui** —
5.000 linhas de histórico sessão a sessão, que continuam valendo como referência e não precisam ser
lidas para retomar.

> **Por que os dois são arquivos separados.** O cabeçalho do `HANDOFF.md` já passou 17 PRs congelado
> em "PR #70, migrations até `0034`", e mandava quem chegava começar errado. A causa não é descuido:
> é que a parte que muda TODA rodada morava no mesmo arquivo das partes que nunca mudam, e um
> arquivo que quase nunca se edita não convida a editar nada. Aqui só há o que muda — e o
> `db/test/run.sh` reprova quando a migration mais nova não está citada abaixo.

## Onde está

| | |
|---|---|
| **Última migration** | `db/migrations/0110_remove_papel_de_usuario.sql` |
| **Schema materializado** | `db/schema.sql` — gerado pelo `db/test/run.sh`, conferido pelo CI |
| **Suítes** | n8n 180 · export 532 · e2e 46 · banco (52 migrations do zero + testes SQL) |
| **CI** | `.github/workflows/suites.yml` — push, PR e `workflow_dispatch` |

## O que o dono precisa fazer, e só ele pode

1. **Aplicar as migrations novas no Supabase.** Merge não é apply: a lista de comandos está em
   `db/README.md`, e da tela "aplicada" e "não aplicada" têm a mesma aparência.
2. **Rodar o aceite sobre um export de verdade**: `auditar-xlsx.mts` (10 itens automáticos) +
   `docs/ACEITE.md` (10 itens humanos). É a única conferência que nenhuma automação cobre, e ela
   nunca foi executada sobre um arquivo posterior ao PR #111.

## O que está aberto no produto

O diagnóstico completo, com evidência e prioridade, está em `docs/DIAGNOSTICO_SISTEMA_2026-08-11.md`.
Os itens que continuam de pé, em ordem de impacto:

- **Fixture de extração do `book-canastra`** — o book existe (PR #112, no `main`), mas ainda prova o
  gerador e o orçamento, não a ingestão sobre dado sujo. É a maior lacuna de cobertura viva.
- **Resumo dos três cenários lado a lado** — hoje o arquivo mostra um cenário por vez. Não é uma
  fórmula a mais: ver a análise no diagnóstico (§2.2 e a nota de execução).
- **Proveniência completa na aba `Premissas`** — a nota traz o documento de origem; página,
  confiança e status de aceite ficaram nas abas de dado, que saíram do arquivo de modelagem.
- **Golden set** e concordância medida — sem isso o dial de autonomia não sobe, e a F4 do
  `docs/03` não começa.
- **Modo A do `f0/07`** (base viva consultável no portal) — ou a decisão escrita de que ele não vem.

## Os comandos que funcionam

```bash
# insumo dos testes (gera pdf/ + GABARITO.json, não versionados)
cd test-data/book-vertentes && PYTHONPATH=. python3 gerar.py && cd -

node --test 'n8n/test/*.test.mjs'                                      # da RAIZ do repo
./portal/node_modules/.bin/tsx portal/scripts/verificar-export.mts
PGHOST=/tmp PGUSER=postgres PGDATABASE=postgres db/test/run.sh
PGHOST=/tmp PGUSER=postgres PGDATABASE=postgres E2E_PSQL="psql" \
  ./portal/node_modules/.bin/tsx test/e2e/run.mts
```

> `E2E_PSQL` é o **comando** do psql, não um flag: com `E2E_PSQL=1` o arnês tenta executar um binário
> chamado `1`. E o `node --test` roda da raiz — de outro diretório o glob não casa nada e a suíte diz
> "0 testes" em vez de falhar.
