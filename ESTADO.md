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
| **Última migration** | `db/migrations/0114_mandato_fechado.sql` |
| **Schema materializado** | `db/schema.sql` — gerado pelo `db/test/run.sh`, conferido pelo CI |
| **Suítes** | n8n 275 · export 535 · e2e 46 · banco (59 migrations do zero + testes SQL) |
| **CI** | `.github/workflows/suites.yml` — push, PR e `workflow_dispatch` |

## O portal (17/08) — navegação, marca e o fim de vida do mandato

- **Barra lateral retrátil** com duas seções que não são simétricas de propósito: *Novo mandato* é
  AÇÃO (fixa, sem filhos) e *Mandatos* é LUGAR (abre e lista os **ativos**). O estado — recolhida e
  seção aberta — mora no navegador via `useSyncExternalStore`, para a barra não "piscar" no lugar
  errado a cada carga. Ela some na tela de abrir mandato, que é de tela cheia.
- **A marca entrou** (`portal/public/logo-oria*.svg`): o original do dono com o fundo creme trocado
  por transparência, **sem redesenhar nada**. O SVG EMBUTE a arte original — vetorizar exigiria
  traçar, e traçar é aproximar. Sextante no cabeçalho e no favicon; a lockup completa no login,
  onde há altura para ela.
- **Fechar ≠ excluir** (`0114`): `caso.status` diz onde o mandato está no trabalho, e não respondia
  "ainda estamos nisso?". `fechado_em` responde, preservando tudo — para apagar continua existindo
  `fn_excluir_caso`. A lista ganhou o segundo rótulo (**Ativo/Fechado**), uma descrição derivada de
  uma linha (documentos · pendências · data) e as duas ações no rodapé de cada item.

> **Para o dono:** a `0114` precisa ser aplicada no Supabase. Sem ela, a coluna não existe e a lista
> trata todo mandato como ativo — a tela não quebra, mas o botão de fechar falha.

## O portal (18/08) — a home deixou de ser a lista

- **A barra lateral rola sozinha.** O `nav` era `sticky` mas não tinha altura: com mais mandatos
  do que cabe na tela, os últimos ficavam abaixo da dobra do elemento grudado e só apareciam
  quando a PÁGINA terminava de rolar. Agora ela tem a altura da viewport abaixo do cabeçalho e a
  lista rola dentro dela, com o topo (Painel, Novo mandato, Mandatos) parado.
- **`/casos` virou o PAINEL e a lista completa foi para `/casos/todos`.** A home repetia inteira a
  lista que a barra já dá em um clique — duas telas para "o que existe", e nenhuma para *o que
  precisa de mim agora*. O painel tem três blocos: indicadores da mesa (mandatos, documentos,
  linhas extraídas, pendências e quantas bloqueiam), a **fila de pendências atravessando os
  mandatos** ordenada por severidade — que antes só existia dentro de um caso por vez —, e o que
  chegou, com as linhas de cada documento (zero linhas em vermelho).
- **A regra que saiu disso:** nenhuma função da barra lateral se repete no conteúdo. O botão
  "Novo mandato" saiu da lista completa; quem precisa dele o tem na barra, sempre visível.

## A rodada v46 (17/08) — o que ela provou e os dois defeitos que ela achou

**9 documentos, 714 linhas, US$ ~0,46.** O defeito que comeu 19 dos 35 documentos na v45 está
**morto**: todos os 9 tiveram extração chamada, e o único sem linha é a certidão negativa — que é o
resultado CERTO (`0111`). Conferido contra o gabarito do gerador:

| | |
|---|---|
| DFC | caixa inicial 3.621 e final 825 — **exatos** |
| DVA | valor adicionado a distribuir 49.110 — **exato** |
| Mútuos | planilha 16.060 (11.160 + 4.900) — **exato**, e o balanço traz 11.400: a divergência plantada de **R$ 240 mil** está no dado, dos dois lados |
| Livro razão | 99 de 99 linhas — **100%**, no documento que motivou as três camadas |
| Balancete | 78 de 78 linhas — **100%** |
| Balanço | 105 de 114 linhas (92%) · DRE 34 de 39 (87%) · DVA 13 de 16 (81%) |

**O que falta são os SUBTOTAIS IMPRESSOS** — "ATIVO CIRCULANTE", "TOTAL DO ATIVO", "RECEITA
OPERACIONAL BRUTA". Eles viraram metadado (`secao`) em vez de linha. Some-se a isso que os
subtotais de subgrupo ("Disponível") FORAM extraídos, e a soma bruta de cada seção dá **exatamente
2× a verdade**. O export já sabe descontar subtotal de subseção; o que falta é o total de topo.

### Defeito 1 — o comparativo não comparava (corrigido)

A mesma conta saía em **três linhas** do Excel, uma por exercício, com as outras colunas vazias. Duas
causas, nas duas pontas:

- **n8n:** `ordem` numerava PARES (conta × coluna) desde que a saída virou agrupada, mas a `0027` a
  define como "posição na leitura do DOCUMENTO". Agora os pares de uma conta compartilham a `ordem`
  da linha que os originou;
- **portal:** o rank que impede dois "Outros" de colapsarem era calculado por VERSÃO, então os três
  valores da mesma conta viravam ocorrência 1, 2 e 3. Agora é por versão **e coluna** — que é o que o
  comentário do próprio bloco dizia querer.

A correção do portal vale para o dado **que já está no banco**: o export da v46 sai alinhado sem
nova extração. Seis verificações novas cobrem as duas formas (agrupada e antiga), e elas reprovam o
código anterior.

### Defeito 2 — a entidade poluída (corrigido, exige reimportar)

O export da v46 mostra `Canastra Industria 2025x2024x2023` como entidade em todas as abas. A
correção está no repositório desde 17/08 (32 entidades limpas, 6 nulas, zero sujas nos 38 nomes),
mas **só entra em produção quando o workflow for reimportado**.

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

> **A rodada de 17/08 ("Teste V45") já aconteceu, e o que ela achou muda o que a próxima tem de
> provar.** Foram **438 linhas**: 19 dos 35 documentos — os centrais (Balanço, DRE, DFC, DMPL, DVA,
> balancetes, razão, faturamento) — **nunca tiveram a extração chamada**, e nada reclamou. A causa era
> topológica (duas conexões cruas no mesmo input, e só o ramo do fallback propagava), está corrigida
> com o `Juntar Ramos`, e a classe inteira ficou barrada por teste. O que a próxima rodada precisa
> trazer, além do custo: **`lote_integro` verdadeiro** no `Conferir Lote` — sem isso, qualquer número
> de cobertura está medindo só os documentos que chegaram lá.

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

### A rodada de 14/08 com o agrupamento: cobertura 39% → 58%

**1.683 linhas gravadas** contra 1.139 (+48%), ainda **sem** as camadas 2 e 3 (elas estavam
desligadas: a referência a ramo irmão não resolvia). O ganho é todo do agrupamento, e o maior efeito
foi o fim do truncamento nos dois maiores documentos:

| Documento | células | antes | agora |
|---|---:|---:|---:|
| `01_Balanco_..._2025x2024x2023` | 326 | **0** | **281 (86%)** |
| `35_Demonstracoes_Contabeis_...` | 308 | **0** | **282 (92%)** |
| `13/14_Balanco_COMBINADO` (8-9 colunas de empresa) | 70 | 57 | 57-64 (81-91%) |
| `17_Livro_Razao_Fornecedores` | 461 | 99 | **1** ← ver abaixo |

**O livro razão caiu para 1 linha, e o guarda de desalinhamento explicou por quê:** o documento tem
**três colunas de valor** (Débito, Crédito, Saldo), o modelo devolveu três valores por lançamento e
declarou `cols` VAZIA — 98 de 99 contas descartadas. O guarda agiu certo; faltava o prompt dizer que
coluna de valor **não é só período e empresa**. Corrigido em 14/08, com os cinco casos nomeados
(razão, balancete, aging, estoques, mapa de dívida) e a consequência escrita.

### A régua da cobertura estava na UNIDADE ERRADA (corrigido em 14/08)

A guarda comparava **linhas com dígito** (do texto) com **pares conta × coluna** (do banco). São
unidades diferentes, e num documento comparativo a razão passa de 100%: o `02_DRE` deu 91 pares
contra 46 linhas = **198%**. A guarda ficava cega justamente onde há mais a perder.

Agora as duas pontas estão em CONTAS:

| | |
|---|---|
| régua | **linhas de conta** — tem valor e tem identidade (rótulo, código de conta, ou linha de tabela numérica); fora cabeçalho de ano, CNPJ, data, página, CRC/CPF |
| medida | **linhas devolvidas** pela extração (era contas distintas até 17/08 — ver abaixo) |
| `02_DRE` | ~30 de 39 = **77%** — ele ESTÁ incompleto, e a régua antiga dizia 198% |

O limiar subiu de 0,60 para **0,85** porque o alvo é cobertura total: isso vai abrir pendência em
documentos que antes passavam, e é o objetivo.

### A régua calibrada contra a verdade — e a cegueira que ela escondia (17/08)

`node n8n/medir-regua-cobertura.mjs` confronta a régua com a contagem que o **gerador** do book
declara (ele sabe quantas linhas escreveu; não é outra leitura do PDF). A primeira medição, nos 38
documentos, achou o defeito que o limiar nunca resolveria:

| Documento | linhas de verdade | a régua via | |
|---|---:|---:|---|
| `17_Livro_Razao` | 99 | **3** | −97% |
| `15_Balancete` | 78 | **3** | −96% |
| `22_Aging` | 14 | **2** | −86% |
| `27_Imobilizado` | 9 | **2** | −78% |

A régua acertava as demonstrações (+2% a +4%) e **desabava nos analíticos — os que perdem dado**. E
como a guarda se cala abaixo de 20 linhas, a cegueira virava **silêncio**: o livro razão, o caso que
motivou as três camadas, nunca chegava a ser avaliado por elas. A causa: "termina em valor" pressupõe
rótulo e valor na mesma linha, e num documento de sistema contábil a linha termina em `D`/`C`, o
rótulo é código sem letra, ou o histórico é parágrafo que o leitor de PDF deixa sozinho numa linha.

A **régua v2** troca isso por "tem valor E tem identidade" (rótulo, código de conta, ou linha de
tabela numérica com dois valores ou mais). Erro absoluto médio **29% → 9%**, sem piorar um documento
sequer; os avaliados pela guarda passam de 10 para 14. O limiar **fica em 0,85**: o pior documento
honesto do book se reporta a 96%, então sobram 11 pontos de folga — e a folga é para o documento
real, que é mais sujo que o sintético. O CI roda a medição a cada push.

### E a unidade do OUTRO lado da guarda: linha, não conta distinta (17/08)

A mesma medição achou o viés oposto, e ele tinha número exato: a guarda comparava **contas distintas
gravadas** com **linhas do texto**, e num livro razão o mesmo fornecedor aparece em vários
lançamentos — 99 linhas para **66 históricos distintos**. Uma extração que não perdia NADA se
reportava em 66% e abria pendência. Foi o segundo erro de unidade da mesma guarda, na direção
contrária ao primeiro (pares × linhas dava 198%).

Agora as duas pontas são **linha**: `achatarGrupos` marca cada campo com a linha do documento que o
originou, `juntarBlocos` conta as linhas distintas depois de limpar a emenda, e o campo **não chega
ao banco** (nada de migration por causa de uma contagem interna). Uma conta com três colunas conta
uma vez; dois lançamentos do mesmo fornecedor contam dois. Bloco no formato plano antigo, sem a
marca, cai para as contas distintas — o comportamento de antes, em vez de cobertura zero. O painel do
`Resumo de Custo` passa a somar a mesma unidade, e `contas_distintas` continua saindo por documento,
porque é ela que denuncia rótulo repetido.

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
   `db/README.md`, e da tela "aplicada" e "não aplicada" têm a mesma aparência. As duas mais novas são
   a `0111` (certidão sem valor deixa de virar `extracao_falhou`) e a `0112` (`fn_conferir_lote`).
   Confira com:
   ```sql
   select proname from pg_proc
    where proname in ('fn_decidir_pendencia','fn_registrar_falha_execucao','fn_excluir_caso',
                      'fn_conferir_lote');
   ```
2. **Reimportar `n8n/workflow.e1-ingestao.json`** — mudou de novo em 17/08 (o `Juntar Ramos`, que é o
   conserto dos 19 documentos que nunca foram extraídos, e o `Conferir Lote`). **Conferência de 5
   segundos depois de importar:** o canvas tem **30 nós** e agora é uma corrente reta — 26 nós numa
   linha só, com a recusa de orçamento e o `Upload Storage` como ramos abaixo, e a classificação por
   conteúdo numa faixa própria (o desenho sai do grafo, ver `n8n/layout.mjs`). Procure `Juntar Ramos`
   (Merge, logo depois do `Precisa Fallback?`), `Fatiar Extracao`, `Juntar Blocos` e, na ponta
   direita, `Resumo de Custo` seguido do `Conferir Lote`. Dois números decidem se a rodada vale:
   `cobertura_do_lote` (se vier `null`, a camada 1 não mediu e as outras duas estão desligadas) e
   `lote_integro` do `Conferir Lote` — **falso significa documento registrado que nunca teve extração
   chamada**, e ele nomeia quais.
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
- ~~**A entidade sai poluída com o período**~~ — **fechado em 17/08.** Eram quatro famílias de
  sujeira, não uma: o comparativo de TRÊS exercícios (`2025x2024x2023`, que o regex de um `x` só não
  pegava), preposições (`Aging De Canastra`), sobra de tipo quando o apelido casado é mais curto que
  o nome do arquivo (`Composicao Imobilizado Canastra`), e nome sem tipo nenhum virando empresa
  (`Relatorio Auditor Independente`, `Iv Rev3`). Medido nos 38 nomes do book: **32 entidades limpas,
  6 nulas** (essas vão ao fallback por conteúdo, que lê a entidade do documento) e **zero sujas**.
  A remoção de palavra de tipo usa a própria taxonomia como fonte, palavra a palavra, então cresce
  sozinha. **Fica anotado:** `negativas`, `societario` e `parcelamentos` estão numa lista à mão em
  `parseEntidade` porque o apelido da taxonomia não os carrega — o lugar certo é o seed
  `db/migrations/0002`, e isso é migration.
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
