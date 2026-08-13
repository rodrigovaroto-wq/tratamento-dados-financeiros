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
| **Suítes** | n8n 228 · export 529 · e2e 46 · banco (55 migrations do zero + testes SQL) |
| **CI** | `.github/workflows/suites.yml` — push, PR e `workflow_dispatch` |

## O próximo passo: o teste de ponta a ponta

Os 38 documentos do `book-canastra` estão prontos para subir, e tudo o que barrava foi removido:

| | Estado |
|---|---|
| Orçamento | estima **US$ 1,88** (era US$ 2,46, e US$ 11,40 no estimador plano) → **passa** |
| Gasto real esperado | **~US$ 1,25** — 42% do teto de US$ 3 (era 2,23 antes do agrupamento) |
| Timeout do n8n | **desativado** (conferido pelo dono em 11/08) |
| Duração | **~23 minutos** (33s por extração no Tier 1) |

> **ANTES DE RODAR, REIMPORTE O `n8n/workflow.e1-ingestao.json`.** A execução de 12/08 recusou o
> lote com *"51 chamadas ≈ US$ 7,65"* — um número que o código deste repositório não produz desde
> 07/08 (US$ 0,15 por chamada saiu de lá). O n8n executa o JSON **importado**, e merge não
> reimporta. A partir da v3 dá para conferir da tela: a mensagem de recusa começa com
> `[orçamento v3 (2026-08-13)]` e o campo `orcamento_versao` aparece na saída do nó mesmo quando o
> lote passa. Se a versão não aparecer, o workflow importado é velho.

Gerar os PDFs: `cd test-data/book-canastra && PYTHONPATH=. python3 gerar.py`

**O que trazer de volta:** a saída do nó **`Resumo de Custo`** (último do canvas) — ela traz o custo
real do lote, o que o orçamento estimou e os **tokens de saída por linha**, que é o número com que
`CUSTO_POR_MB_USD` e o modelo de saída se recalibram. Mais: quantos dos 38 chegaram, e o que a
reconciliação abriu — em especial o erro plantado de **R$ 240 mil na planilha de mútuos**.

### O buraco que a rodada completa abriu — e as três camadas que o fecham

A rodada do `book-canastra` (35 documentos, 21 min, US$ 0,71, no workflow ANTIGO) respondeu o custo e
abriu outra coisa: **das 2.893 células de valor dos PDFs, chegaram ao banco 1.139 — 39%**. Duas
famílias: 5 documentos TRUNCARAM (teto de 16.384 tokens de saída do gpt-4o; `01_Balanco` sozinho pede
~20.900) e o resto veio pela metade **em silêncio** (`17_Livro_Razao`: 99 de 461, sem uma pendência).

O `.xlsx` da modelagem exportado dessa rodada passa em **9 de 10** itens do auditor; o único reprovado
é o balanço não fechar por 40.169 — que é o buraco da extração chegando ao arquivo entregue.

Três camadas, no `n8n/lib/cobertura.mjs` e no grafo:

| | O que faz | Onde |
|---|---|---|
| **1. Medir antes de chamar** | lê a camada de texto do PDF na instância (sem IA, sem custo) e conta as linhas com número | nó `Extrair Texto` |
| **2. Fatiar** | acima de 60% do teto, um item por bloco de ≤234 células, cada um com o TEXTO da primeira e última linha da faixa como âncora | nó `Fatiar Extracao` |
| **3. Guarda de cobertura** | compara o que voltou com o que o documento tem; abaixo de 60% abre pendência com os dois números | nó `Juntar Blocos` |

No `book-canastra`: 38 documentos → **41 chamadas** de extração, 3 fatiados. Custo projetado com o
dado INTEIRO: **~US$ 1,4** (era 0,71 com 39% do dado) — menos da metade do teto.

> **Corrigido na execução 6164 (13/08, mesmo dia):** o fan-out corta a cadeia de `pairedItem` do
> n8n, e toda expressão `$('Outro Nó').item` rio abaixo virou `undefined` — os nós Postgres
> receberam "undefined" em Query Parameters. Agora `Fatiar Extracao` e `Juntar Blocos` declaram
> `pairedItem`, os dois ids viajam com o item, e `Gravar Campos`/`Registrar Diagnostico`/`Reconciliar`
> leem do PRÓPRIO item. **Quem for reimportar precisa da versão com essa correção.**
>
> **O que a camada 3 promete, com precisão:** ela não impede o modelo de pular uma linha. Impede que
> isso seja silencioso. E o `Extrair Texto` tem `onError: continue` — PDF escaneado não tem camada de
> texto, o nó falha nele, o documento segue como imagem e as camadas 2 e 3 se calam. **O pior caso da
> mudança é o comportamento de ontem.**

### O custo, medido e projetado (13/08/2026)

A primeira fatura real veio dos 14 documentos do `book-vertentes`: **US$ 0,90**, com alvo de US$ 0,50.
84% era saída de extração, a ~64 tokens por célula de valor — 45% acima do que este repositório
supunha. A saída passou a ser **agrupada** (uma seção por grupo, colunas declaradas uma vez, conta
escrita uma vez com um valor por coluna) e o `medir-custo-book.mjs` projeta:

| Book | formato plano | agrupado |
|---|---:|---:|
| `book-vertentes` (14 docs) | US$ 0,857 (fatura real: **0,90**) | **US$ 0,471** |
| `book-canastra` (38 docs) | US$ 2,226 | **US$ 1,252** |

~~**Aberto:** o livro razão projeta 109% do teto de saída mesmo agrupado.~~ **Fechado no mesmo dia
pelo fatiamento** (camada 2): ele vira 2 blocos de ≤234 células e nenhum deles chega perto do teto. O
`medir-custo-book.mjs` continua avisando, nomeando o arquivo, se algum documento voltar a passar de
80% do teto numa chamada — a guarda fica de pé mesmo depois de a causa conhecida sumir.

## O que só o dono pode fazer

1. **Aplicar as migrations novas no Supabase.** Merge não é apply: a lista de comandos está em
   `db/README.md`, e da tela "aplicada" e "não aplicada" têm a mesma aparência. Confira com:
   ```sql
   select proname from pg_proc
    where proname in ('fn_decidir_pendencia','fn_registrar_falha_execucao','fn_excluir_caso');
   ```
2. **Reimportar `n8n/workflow.e1-ingestao.json`** — mudou três vezes em 13/08 (classificação em
   `gpt-4o-mini`, saída agrupada, e as três camadas de cobertura). **Conferência de 5 segundos depois
   de importar:** o canvas tem **26 nós**; procure `Extrair Texto`, `Fatiar Extracao`, `Juntar Blocos`
   e, na ponta direita, `Resumo de Custo` — rodando, a saída dele traz a cobertura do lote.
   E, para cobrir falha de qualquer origem, importar `workflow.erros.json` e ligá-lo como
   **Error Workflow** nas Settings do Intake (`n8n/README.md`).
3. **Rodar o aceite sobre um export de verdade**: `auditar-xlsx.mts` (10 itens automáticos) +
   `docs/ACEITE.md` (10 itens humanos). É a única conferência que nenhuma automação cobre — e a que
   faltava quando o arquivo de 06/08 saiu com seis números errados e as suítes verdes.

## O que está aberto no produto

O diagnóstico completo, com evidência e prioridade, está em `docs/DIAGNOSTICO_SISTEMA_2026-08-11.md`.
Os itens que continuam de pé, em ordem de impacto:

- **O teto de gasto decide ANTES do `Extrair Texto`**, então estima por bytes e não sabe quantos
  blocos o lote terá. Movê-lo para depois troca a estimativa por byte (que superestima ~50%) por uma
  contagem de linhas determinística. Fatia própria.
- **A entidade sai poluída com o período** — "Canastra Industria 2025x2024x2023" na rodada real, e é
  o que gerou 15 das 22 pendências de revisão. Correção pequena em `parseEntidade`.
- **Dedup por hash** (não pagar reextração do mesmo arquivo): a `0026` descreve o que falta —
  *fingerprint* de prompt+modelo na versão e curto-circuito no grafo.
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
