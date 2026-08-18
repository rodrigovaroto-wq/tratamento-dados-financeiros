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
| **Última migration** | `db/migrations/0120_banco_de_perguntas.sql` |
| **Schema materializado** | `db/schema.sql` — gerado pelo `db/test/run.sh`, conferido pelo CI |
| **Suítes** | n8n 284 · export 535 · e2e 46 · banco (65 migrations do zero + testes SQL) |
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
- **Os sete indicadores do painel** (escolhidos pelo dono): mandatos ativos, mandatos fechados,
  linhas extraídas, tempo médio de processamento, gasto médio de API por mandato, gasto total de
  API, pendências em aberto.
- **A abertura e a ilustração.** O painel abre com uma cena de ~3s — o sextante da marca desenhado
  em vetor próprio (a arte original NÃO é tocada), com o limbo crescendo e a constelação acendendo
  em cascata. Toca **uma vez por sessão** do navegador, **qualquer gesto corta**, e
  `prefers-reduced-motion` pula por completo. O mesmo motivo fica de fundo no painel a ~15% de
  opacidade, na goteira à direita: **gira com a rolagem** e a constelação deriva com o ponteiro.

- **O custo passou a durar (`0115`)**, e com ele veio o **oitavo indicador: cobertura da extração**.
  `lote_execucao` guarda uma linha por execução de ingestão (custo real, custo estimado, tokens,
  linhas, cobertura), gravada pelo nó novo `Gravar Uso do Lote`. A chave `(caso_id, execucao_ref)`
  é o que impede o custo de sair **dobrado**: o `Resumo de Custo` roda uma vez por ramo do lote e
  as duas passadas trazem o total inteiro.

> **PARA OS TRÊS INDICADORES NOVOS ACENDEREM, DUAS COISAS PRECISAM ACONTECER FORA DO GIT:** aplicar
> a `0115` no Supabase e **reimportar o `n8n/workflow.e1-ingestao.json`** (o n8n executa o JSON
> importado, e merge não reimporta). Sem a migration, a tela mostra um traço com a causa escrita —
> não zero. Sem a reimportação, a tabela existe e fica vazia. O **tempo médio** não depende de
> nenhuma das duas: é uma janela derivada — de
> `caso.criado_em` (gravado pelo `Upsert Caso`, no envio do intake) até o `criado_em` do último
> documento do mandato; janelas acima de 12h são contadas à parte, porque a partir daí o número
> mede espera pelo cliente, não processamento.

## Estado dos PRs (18/08, sessão 50 — leia isto antes de continuar)

| PR | O quê | Estado |
|---|---|---|
| **#133** | Barra lateral rolável, `/casos` vira Painel (8 indicadores), lista completa em `/casos/todos`, abertura animada, migration `0115` (custo do lote em `lote_execucao`) | **mergeado no `main`** |
| **#134** | Correção: "1.000 linhas extraídas" no Painel era o teto padrão do Supabase/PostgREST (`db-max-rows`), não o dado real | **aberto quando a sessão 50 começou** — https://github.com/rodrigovaroto-wq/tratamento-dados-financeiros/pull/134 |
| **sessão 50** | Os sete itens de "o que está aberto", atacados em ordem a pedido do dono: subtotais impressos, mútuos, Modelagem, apelidos, teto de gasto, dedup e o teto de 1000 nas listas | **branch `claude/handoff-next-steps-ke4omr`** |

**A branch da sessão 50 CONTÉM os dois commits do #134.** Ela foi criada a partir da ponta daquela
branch, e não do `main`, porque o item 7 mexe no mesmo arquivo (`portal/src/app/casos/page.tsx`) e
partir do `main` produziria conflito com trabalho que já estava pronto e revisado. Consequência
prática: **se o #134 for mergeado primeiro, os commits dele somem do diff desta branch sozinhos**;
se o dono preferir, dá para mergear só esta e fechar o #134 como incluído.

**O risco que a sessão 50 fechou, e que estava anotado aqui como "não se resolve sozinho":** as
listas de `documento` e `pendencia` do painel continuavam sujeitas ao teto de 1000 do PostgREST.
Agora elas paginam (`portal/src/lib/supabase/paginar.ts`), junto com a lista de mandatos, e o
painel avisa se o teto de segurança de 50 mil for atingido.

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

## O próximo passo (para quem retomar depois de 18/08, sessão 50)

**O dono já fez os dois passos que só ele pode fazer**, e disse isso nesta sessão: as migrations
até a `0115` foram aplicadas no Supabase e o workflow foi reimportado. **Mas a sessão 50 escreveu
três migrations novas (`0116`, `0117`, `0118`) e mexeu no workflow de novo** — então os dois
passos voltam a estar pendentes, agora para o que esta rodada produziu.

| | Passo | De quem |
|---|---|---|
| 1 | Aplicar `0116`, `0117`, `0118` e `0119` no Supabase (a lista de comandos está no `db/README.md`) | dono |
| 2 | **Reimportar `n8n/workflow.e1-ingestao.json` — agora 33 nós** (o teto de gasto mudou de lugar e o dedup entrou) | dono |
| 3 | Rodar o book e trazer `lote_integro`, `cobertura_do_lote` e o `Resumo de Custo` | dono |
| 4 | Com a rodada na mão: conferir se os SUBTOTAIS IMPRESSOS passaram a chegar (é a única mudança desta rodada que só a extração real prova) e recalibrar o limiar de 0,85 com pontos reais | próxima sessão |

> **A `0118` muda o que se vê ao reenviar um arquivo.** Reenviar o MESMO PDF sem que prompt, modelo
> ou esquema tenham mudado não chama mais a OpenAI: o documento aparece no lote, sem custo e sem
> versão nova. Se a intenção era reextrair de verdade, mude o prompt (ou espere a próxima mudança
> dele) — o fingerprint muda junto e a extração volta a acontecer.

### O PR #135 do Ian, incorporado com quatro correções (0119)

**O que ele resolve, e o número que prova:** a `0113` perguntava "algum documento do tipo tem a
linha?". Num grupo com oito balanços, sete sem a linha de caixa, o oitavo respondia sim e as sete
ausências sumiam — **zero pendência**. A `0119` pergunta "cada entidade que trouxe linhas desse tipo
tem a linha NELA?": sete pendências, cada uma nomeando a empresa, e a oitava limpa.

**A suspeita que eu tinha, e que a medição derrubou:** granularidade fina costuma virar máquina de
pendência falsa. Medi num banco limpo, com o fixture Vertentes (5 entidades, 14 documentos, extração
fiel): **1 pendência antes, 1 depois — idêntico**. Os dois fallbacks dele funcionam. (Na primeira
medição vi 7, mas era lixo de outro teste no mesmo caso; num banco limpo o número não se move.)

**As quatro correções feitas na incorporação:**

| | O quê | Por quê |
|---|---|---|
| 1 | **Renumerada `0116` → `0119`** | A faixa 0116-0118 foi ocupada pelo PR #136, mergeado antes. O portão de prefixo duplicado do `run.sh` reprovava — e com razão. |
| 2 | **A verificação embutida deixou de ser alçapão** | Ela abortava a migration se encontrasse qualquer `escopo_entidade` não nulo. No dia em que o dono ligasse o override do COMBINADO — que é o que o cabeçalho manda ele fazer — e reaplicasse a lista do `db/README.md`, a migration **morreria no meio por causa de uma decisão legítima dele**. Medido: a versão original aborta. Agora prova o que interessa (a coluna não tem DEFAULT) e o override vira NOTICE. |
| 3 | **A varredura saiu da migration** para `db/varredura_linha_exigida.sql` | Era a única parte que tocava caso já gravado, e o efeito visível é uma leva de pendências novas na fila do painel sem ninguém ter enviado nada. Separada, o dono aplica a estrutura hoje e escolhe a hora da varredura — ou roda num mandato só. O script diz quantas pendências entraram. |
| 4 | **`fn_exigencias_do_caso` ficou 5,9× mais rápida** | O `explain analyze` mostrou 662 ms dos 914 ms num único filtro: `fn_linhas_do_tipo` rodando uma vez por DOCUMENTO em vez de por tipo. Separar em duas CTEs não mudou nada — o Postgres achata CTE simples e empurrava o filtro de volta. Com `as materialized`: **693 ms → 116 ms** num caso de 400 documentos. |

As duas propriedades novas estão travadas em teste (`db/test/linha_exigida_entidade.test.sql`,
blocos 8 e 9), e a do `materialized` é teste de TEXTO de propósito: medir por relógio daria um teste
que falha em máquina lenta e passa com o defeito de volta em máquina rápida.

### O que a sessão 50 (18/08) fez, e o que ficou de fora

Os sete itens da lista "o que está aberto" foram atacados em ordem, a pedido do dono. O que
**entrou**:

| | O quê | Onde |
|---|---|---|
| 1 | **Subtotais impressos viram LINHA.** O prompt passou a exigir o valor impresso na linha do agrupamento ("ATIVO CIRCULANTE ... 3.961"), que antes virava só o nome da `secao` e sumia. A `0116` ensina `fn_papel_linha` a reconhecer os totais novos (topo da DRE, DVA) para eles não receberem premissa e dobrarem a conta. | `n8n/lib/extract.mjs`, `0116` |
| 2 | **A divergência de mútuos é acusada.** Checagem B nova, lado a lado (ativo × passivo), disparada pelos dois lados do par. No fixture ela acusa exatamente os R$ 180 mil que o book planta de propósito — e o teste que cobrava "zero pendências" era, ele mesmo, a prova de que a checagem faltava. No painel, a fila agora diz QUAL checagem acusou. | `0117`, `portal/src/lib/rotulos.ts` |
| 3 | **A tela de Modelagem entrou na linguagem do portal:** `<main>` aninhado (que estreitava a página dentro do layout) foi embora, as três seções viraram `carta` com âncora, e uma trilha de passos no topo diz o que falta em cada uma. Na tabela, o cabeçalho gruda e o "salvar" aparece também no topo com o aviso de alteração não salva — os dois viviam no rodapé, fora da tela justamente enquanto se edita. | `portal/src/app/casos/[id]/modelagem/` |
| 4 | **`negativas`/`societario`/`parcelamentos` saíram da lista à mão** e viraram termos da taxonomia. A remoção de palavra de tipo em `parseEntidade` varre o vocabulário palavra a palavra, então quem entra lá é removido de graça. | `n8n/lib/taxonomia.mjs` |
| 5 | **O teto de gasto decide depois do `Extrair Texto`.** Com o documento medido, a estimativa deixa de ser por byte (margem de 1,8×, que recusava lote que cabia) e passa a contar linhas e BLOCOS — exatamente os que o `Fatiar Extracao` vai gastar. Medido no book: guarda por byte US$ 0,67 contra custo real US$ 0,49; por conteúdo, US$ 0,61. Continua barrando antes de qualquer gasto. | `n8n/lib/custo.mjs`, grafo |
| 6 | **Dedup por fingerprint (a segunda metade da 0026).** Prompt+modelo+esquema viram uma impressão gravada na versão; mesmo arquivo + mesma impressão + extração que TEM linha ⇒ o grafo pula a chamada. A exigência de "ter linha" é o que impede uma extração falha de valer como feita. | `0118`, grafo |
| 7 | **As listas do painel saíram do teto de 1000** (documentos, pendências e mandatos), com paginação de mil em mil e um aviso que aparece se o teto de segurança de 50 mil for atingido. | `portal/src/lib/supabase/paginar.ts` |

O que **ficou de fora, e é honesto dizer**:

- **O item 1 não pode ser provado sem gastar crédito.** O prompt mudou e os testes travam o texto
  dele, mas se o modelo passa a devolver os totais é a rodada que responde. É o passo 4 acima.
- **A checagem de mútuos cobre MÚTUO contra MÚTUO.** Conta corrente rotativa, aluguel entre
  coligadas e rateio de despesa também moram na planilha intragrupo e continuam sem conferência —
  casar cada uma com a conta certa de cada balanço é outro problema.
- **A tela de Modelagem recebeu revisão de apresentação, não redesenho de fluxo.** A ordem dos três
  passos e o modelo de dados por trás dela continuam os mesmos.

### O book inteiro, quando houver crédito

Os 38 documentos do `book-canastra` estão prontos para subir:

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
   `db/README.md`, e da tela "aplicada" e "não aplicada" têm a mesma aparência. O dono confirmou em
   18/08 que aplicou até a `0115`. **Três estão pendentes**, todas da sessão 50: `0116` (o papel dos
   totais impressos), `0117` (a reconciliação de mútuos) e `0118` (o dedup por fingerprint —
   `documento_versao` ganha coluna). Confira com:
   ```sql
   select proname from pg_proc
    where proname in ('fn_papel_linha','fn_reconciliar_mutuos','fn_lado_do_mutuo',
                      'fn_registrar_documento');
   -- a 0118 acrescenta coluna, não só função:
   select column_name from information_schema.columns
    where table_name = 'documento_versao' and column_name = 'fingerprint_extracao';
   -- e a 0118 exige que sobre UMA assinatura de fn_registrar_documento (a de 16 args):
   select pronargs from pg_proc where proname = 'fn_registrar_documento';
   ```
2. **Reimportar `n8n/workflow.e1-ingestao.json`** — mudou de novo em 18/08, e a mudança é
   estrutural: o teto de gasto saiu do começo da corrente e o dedup entrou. **Conferência de 5
   segundos depois de importar:** o canvas tem **33 nós** (eram 31). Procure, em ordem:
   `Medir Documento` → **`Orcamento do Lote` → `Lote cabe?`** (o teto agora decide AQUI, com o
   documento já medido, e não lá no começo), `Precisa Fallback?` → `Juntar Ramos`,
   `Registrar Documento` → `Recompor Contexto` → **`Extracao ja feita?`** (o dedup) e
   **`Juntar Extraidos`** (o Merge que junta quem extraiu com quem não precisou), e na ponta direita
   `Resumo de Custo` → `Gravar Uso do Lote` → `Conferir Lote`. Dois números decidem se a rodada
   vale: `cobertura_do_lote` (se vier `null`, a camada 1 não mediu e as outras duas estão
   desligadas) e `lote_integro` do `Conferir Lote` — **falso significa documento registrado que
   nunca teve extração chamada**, e ele nomeia quais.
   E, para cobrir falha de qualquer origem, importar `workflow.erros.json` e ligá-lo como
   **Error Workflow** nas Settings do Intake (`n8n/README.md`).
3. **Rodar o aceite sobre um export de verdade**: `auditar-xlsx.mts` (10 itens automáticos) +
   `docs/ACEITE.md` (10 itens humanos). É a única conferência que nenhuma automação cobre — e a que
   faltava quando o arquivo de 06/08 saiu com seis números errados e as suítes verdes.

## O que está aberto no produto

> **Os quatro itens que abriam esta lista em 17/08 foram FECHADOS na sessão 50** (subtotais
> impressos, checagem de mútuos, tela de Modelagem e os apelidos à mão) — ver "O que a sessão 50
> fez". Dois deles com uma ressalva registrada lá: o dos subtotais só a rodada real prova, e a
> checagem de mútuos cobre mútuo contra mútuo, não a planilha intragrupo inteira.

- **A conferência das linhas intragrupo que NÃO são mútuo** (conta corrente rotativa, aluguel entre
  coligadas, rateio de despesa). Elas moram na mesma planilha que a `0117` passou a conferir, mas
  cada uma casa com uma conta diferente do balanço — e escolher errado inventa divergência. É
  trabalho próprio.
- **O item mais denso do book ainda estoura o teto de saída**: `17_Livro_Razao_Fornecedores...`
  mede 17.875 tokens (109% dos 16.384). O `Fatiar Extracao` cobre isso hoje partindo o documento;
  o que falta é o caso de o BLOCO mais denso ainda não caber — extrair por faixa de PÁGINA.

O diagnóstico completo, com evidência e prioridade, está em `docs/DIAGNOSTICO_SISTEMA_2026-08-11.md`.
Os itens que continuam de pé, em ordem de impacto:

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
