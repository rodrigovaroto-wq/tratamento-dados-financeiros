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
| **Suítes** | n8n 194 · export 529 · e2e 46 · banco (55 migrations do zero + testes SQL) |
| **CI** | `.github/workflows/suites.yml` — push, PR e `workflow_dispatch` |

## O próximo passo: o teste de ponta a ponta

Os 38 documentos do `book-canastra` estão prontos para subir, e tudo o que barrava foi removido:

| | Estado |
|---|---|
| Orçamento | estima **US$ 1,88** (era US$ 2,46, e US$ 11,40 no estimador plano) → **passa** |
| Gasto real esperado | **~US$ 1,33** — 44% do teto de US$ 3 |
| Timeout do n8n | **desativado** (conferido pelo dono em 11/08) |
| Duração | **~23 minutos** (33s por extração no Tier 1) |

> **ANTES DE RODAR, REIMPORTE O `n8n/workflow.e1-ingestao.json`.** A execução de 12/08 recusou o
> lote com *"51 chamadas ≈ US$ 7,65"* — um número que o código deste repositório não produz desde
> 07/08 (US$ 0,15 por chamada saiu de lá). O n8n executa o JSON **importado**, e merge não
> reimporta. A partir da v3 dá para conferir da tela: a mensagem de recusa começa com
> `[orçamento v3 (2026-08-13)]` e o campo `orcamento_versao` aparece na saída do nó mesmo quando o
> lote passa. Se a versão não aparecer, o workflow importado é velho.

Gerar os PDFs: `cd test-data/book-canastra && PYTHONPATH=. python3 gerar.py`

**O que trazer de volta:** o custo REAL da OpenAI (Usage do dia — é a primeira medição de verdade
que este projeto terá, e é com ela que `CUSTO_POR_MB_USD` se recalibra), quantos dos 38 chegaram, e
o que a reconciliação abriu — em especial o erro plantado de **R$ 240 mil na planilha de mútuos**.

## O que só o dono pode fazer

1. **Aplicar as migrations novas no Supabase.** Merge não é apply: a lista de comandos está em
   `db/README.md`, e da tela "aplicada" e "não aplicada" têm a mesma aparência. Confira com:
   ```sql
   select proname from pg_proc
    where proname in ('fn_decidir_pendencia','fn_registrar_falha_execucao','fn_excluir_caso');
   ```
2. **Reimportar `n8n/workflow.e1-ingestao.json`** — mudou de novo em 13/08 (classificação em
   `gpt-4o-mini`, peso da 2ª chamada no orçamento, versão carimbada na recusa), e a execução de
   12/08 provou que o que está lá dentro ainda é de julho. **Conferência de 5 segundos depois de
   importar:** abrir o nó `Orcamento do Lote` e procurar `gpt-4o-mini` no `Montar Req Classif`, ou
   rodar e ver `orcamento_versao: "v3 (2026-08-13)"` na saída do nó.
   E, para cobrir falha de qualquer origem, importar `workflow.erros.json` e ligá-lo como
   **Error Workflow** nas Settings do Intake (`n8n/README.md`).
3. **Rodar o aceite sobre um export de verdade**: `auditar-xlsx.mts` (10 itens automáticos) +
   `docs/ACEITE.md` (10 itens humanos). É a única conferência que nenhuma automação cobre — e a que
   faltava quando o arquivo de 06/08 saiu com seis números errados e as suítes verdes.

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
