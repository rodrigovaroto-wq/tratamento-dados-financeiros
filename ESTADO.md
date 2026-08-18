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
| **Última migration** | `db/migrations/0122_pergunta_em_portugues.sql` |
| **Schema materializado** | `db/schema.sql` — gerado pelo `db/test/run.sh`, conferido pelo CI |
| **Suítes** | n8n 284 · export 535 · e2e 46 · banco (67 migrations do zero + testes SQL) |
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

## Estado dos PRs (18/08, sessão 51 — leia isto antes de continuar)

| PR | O quê | Estado |
|---|---|---|
| **#133** | Barra lateral rolável, `/casos` vira Painel (8 indicadores), lista completa em `/casos/todos`, abertura animada, migration `0115` (custo do lote em `lote_execucao`) | **mergeado no `main`** |
| **#134** | Correção: "1.000 linhas extraídas" no Painel era o teto padrão do Supabase/PostgREST (`db-max-rows`), não o dado real | **mergeado no `main`** |
| **sessão 50** | Os sete itens de "o que está aberto", atacados em ordem a pedido do dono: subtotais impressos, mútuos, Modelagem, apelidos, teto de gasto, dedup e o teto de 1000 nas listas | **mergeado no `main`** (PRs #137, #139, #140, #141) |
| **sessão 51** | A aba "Perguntas ao cliente" (`/casos/[id]/perguntas`), o fim do teto de 1000 no portal e a `0122` (o texto que vai ao cliente em português) | **PR #142**, branch `claude/client-question-suggestions-ves2ty` |

**Nada da sessão 50 ficou pendente de merge** — o `main` já tem os sete itens, e a branch da sessão
51 sai dele. As migrations `0116` a `0121` **já estão aplicadas** (o dono confirmou em 18/08); o que
continua pendente daquela rodada é a reimportação do workflow e a rodada real, no quadro "O próximo
passo".

**O risco que a sessão 50 fechou, e que estava anotado aqui como "não se resolve sozinho":** as
listas de `documento` e `pendencia` do painel continuavam sujeitas ao teto de 1000 do PostgREST.
Agora elas paginam (`portal/src/lib/supabase/paginar.ts`), junto com a lista de mandatos, e o
painel avisa se o teto de segurança for atingido. **A sessão 51 terminou o serviço** — ver "O teto
de 1000 deixou de existir para o portal".

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

## O próximo passo (para quem retomar depois de 18/08, sessão 51)

**O DONO APLICOU TODAS AS MIGRATIONS DO REPOSITÓRIO** — confirmado em 18/08 (sessão 51), até a
`0121`. O banco deixou de ser o passo pendente; o que falta da sessão 50 é a REIMPORTAÇÃO do
workflow e a rodada real.

| | Passo | De quem |
|---|---|---|
| 1 | ~~Aplicar `0116` a `0121` no Supabase~~ — **feito em 18/08**. **Falta a `0122`**, escrita depois: sem ela a pergunta ao cliente sai dizendo "Na DRE de 24,25" e "16060 milhar" | dono |
| 2 | **Reimportar `n8n/workflow.e1-ingestao.json` — agora 33 nós** (o teto de gasto mudou de lugar e o dedup entrou) | dono |
| 3 | Rodar o book e trazer `lote_integro`, `cobertura_do_lote` e o `Resumo de Custo` | dono |
| 4 | Com a rodada na mão: conferir se os SUBTOTAIS IMPRESSOS passaram a chegar (é a única mudança desta rodada que só a extração real prova) e recalibrar o limiar de 0,85 com pontos reais | próxima sessão |

> **Opcional, e só isso: o `Max rows` do Supabase.** Com a `0120` aplicada, a aba "Perguntas ao
> cliente" já lista. O teto de 1000 linhas do PostgREST (*Project Settings → API → Max rows*)
> continua no padrão, e **nenhuma tela depende mais dele** — o `paginar` lê em janelas até o banco
> acabar, qualquer que seja o teto. Subi-lo só deixa cada leitura mais barata.

> **A `0118` muda o que se vê ao reenviar um arquivo.** Reenviar o MESMO PDF sem que prompt, modelo
> ou esquema tenham mudado não chama mais a OpenAI: o documento aparece no lote, sem custo e sem
> versão nova. Se a intenção era reextrair de verdade, mude o prompt (ou espere a próxima mudança
> dele) — o fingerprint muda junto e a extração volta a acontecer.

### O teto de 1000 deixou de existir para o portal (18/08, sessão 51)

Pedido do dono, literal: *"a lista pagina não deve ser restringida, remova o teto de 1000 do
PostgREST"*. O teto mora em dois lugares, e os dois foram tratados:

**1. No servidor — e lá ele é do DONO, não do repositório.** É o `db-max-rows` do PostgREST
(*painel do Supabase → Project Settings → API → Max rows*, padrão 1000). Subi-lo para 100000 remove
o teto na prática e deixa cada leitura mais barata. **Está documentado no `db/README.md`, com o
caminho exato — e é opcional**, pelo motivo abaixo.

**2. No portal — e aqui ele acabou de verdade.** Duas mudanças:

- **`paginar` deixou de depender do teto do servidor.** A parada era "página com menos linhas que a
  janela = acabou", e isso só era correto porque a janela (1000) era exatamente o teto padrão. Com
  `Max rows` abaixo de 1000, TODA página voltaria curta e a leitura pararia na primeira — o defeito
  original de volta, escondido dentro da própria defesa contra ele. Agora a leitura anda pelo número
  de linhas REALMENTE devolvidas e só termina quando uma página volta **vazia**: vale para qualquer
  teto, e custa uma requisição a mais por consulta. O teto de segurança subiu de 50 mil para **500
  mil linhas** e continua declarando (`truncado`) em vez de entregar o pedaço como se fosse o todo.
- **As leituras que ainda escapavam passaram a paginar** — e uma delas já estava a meses de
  quebrar:

| Onde | O que era truncado | Por que importa |
|---|---|---|
| `indice_macro_obs` (export) | as observações macro | **920 linhas hoje**, +72 por ano. Ao passar de 1000, o corte cairia nas MAIS RECENTES (ordem crescente por data) — e é a última observação que dá o câmbio de fechamento do ano |
| `indice_macro_expectativa` (export) | as coletas do Focus | cada coleta acrescenta linhas; truncar não deixa o arquivo sem macro, deixa com a expectativa ERRADA |
| `fn_linhas_para_modelagem` (export e tela) | as linhas do modelo | é o conteúdo das 14 abas e da seção 3 da Modelagem |
| `fn_valores_por_ano` (export) | a série histórica por conta | 400 rótulos × 3 exercícios já passam de mil; cortar aqui dá a uma conta menos anos do que ela tem |
| `caso_linha_premissa` (export e tela) | os vínculos linha→premissa | truncado, o analista reescolhe premissa de linha que já tinha uma |

Todas com **ordem total e estável** (o desempate que impede duas páginas de repetirem e omitirem a
mesma linha), e o export passou a **declarar** no cabeçalho `X-Oria-Leitura-Truncada` se algum teto
de segurança for atingido — um arquivo incompleto que não se anuncia é pior que um erro.

Ficam de fora, de propósito e por não crescerem com a mesa: catálogos (taxonomia, premissas, séries
macro, banco de perguntas), consultas de linha única e as duas listas com `limit` deliberado (barra
lateral, trilha de autonomia).

### A `0122` — o texto que vai AO CLIENTE passa a ser escrito em português (18/08, sessão 51)

**Achado rodando a aba nova sobre o book da Canastra**, e é o tipo de defeito que só aparece com
dado real na tela. As perguntas saíam assim, literal:

| Saía | Sai agora |
|---|---|
| "Na DRE de **24,25** não localizamos a linha de despesas financeiras" | "Na DRE de **2024 e 2025**…" |
| "no faturamento de **L36M**?" | "no faturamento de **2025**?" |
| "A relação de mútuos informa **16060 milhar**" | "…informa **R$ 16.060 mil**" |

Nenhuma delas está errada no DADO — `24,25` é a referência multi-ano do classificador, `L36M` é a
notação de janela móvel de `f0/03`, `16060 milhar` é a soma com a escala declarada. Estão erradas no
LEITOR, e o leitor aqui é o cliente do mandato: **este é o único texto do sistema que sai da casa**,
e ele não pode falar em chave interna.

São três consertos, e o terceiro **não é de redação**:

1. **`fn_periodo_por_extenso`** — o período na forma que cabe depois de "de"/"em": `2025`,
   `2024 e 2025`, `2023 a 2025`, `2021, 2023 e 2025` (com buraco vira lista: o intervalo afirmaria
   um exercício que o documento não traz), `2025 (1º trimestre)` e `um período de 36 meses`. Rótulo
   que não diz ano nenhum **sai como veio**.
2. **`fn_valor_pt_br`** — `R$ 16.060 mil`, com separador de milhar do país, escala em palavra, sinal
   antes da moeda (`-R$ 240 mil`) e escala desconhecida **visível**. Independe do `lc_numeric` do
   servidor.
3. **`fn_anos_texto` deixa de ler `L36M` como o ano 2036.** A regra de "dois dígitos no fim"
   (`0023`) foi escrita para `dez/25` e `12M25`; em `L36M` o que está no fim é o **tamanho da
   janela**. Duas consequências, as duas invisíveis: na `0120` o período da pergunta é escolhido
   pelo maior ano do caso, então um documento `L36M` **vencia** um 2025 real (foi exatamente o que a
   Canastra produziu); e em `fn_valores_por_ano` uma coluna `L24M` entraria no modelo como o
   exercício de 2024 — janela móvel tratada como ano fechado. Corrigir só o texto teria trocado
   `L36M` por `2036`: um ano plausível e errado.

**E o período passou a ser o DA EMPRESA de que a pergunta fala.** A sugestão é por (pergunta ×
entidade) desde a `0119` e o período não acompanhava: num grupo em que a DRE da Indústria cobre
2023–2025 e a da Comercial só 2024–2025, a pergunta sobre a Comercial citava um exercício que o
documento dela não tem — e quem recebe não reconhece o próprio documento na pergunta.

Dezesseis asserts novos em `db/test/perguntas.test.sql` (`#12`), incluindo o que vale por todos:
**nenhuma pergunta do caso publica referência crua nem nome de escala**.

### As perguntas ao cliente ganharam a ABA que faltava (18/08, sessão 51)

A `0120` construiu o motor inteiro e **nenhuma tela o chamava**: `fn_sugerir_perguntas(caso)`
devolve a pergunta pronta — com motivo, risco, impacto, os marcadores resolvidos e o nome da
empresa — e a única forma de ver uma sugestão era rodar a função no SQL Editor. Para quem usa o
produto, a `0120` não existia.

**Onde ela ficou, e por que não onde o desenho anterior previa.** O plano era abrir a pergunta
dentro do botão "Contatar o Cliente" da fila de pendências (`0109`). O dono redirecionou, e a razão
é boa: **essas perguntas são sugestões que provavelmente ainda não foram feitas a ninguém** —
pendência é decisão sobre problema já medido, sugestão é rascunho de conversa. Numa lista só, a
segunda herda a aparência de tarefa concluída da primeira. Então elas moram numa aba própria,
`/casos/[id]/perguntas`, com entrada no cabeçalho do mandato (com a contagem) e um link a partir da
pendência **depois** que ela é marcada como pedida ao cliente — que é o momento exato em que o
analista precisa do texto.

O que a aba faz, em ordem de uso:

| | |
|---|---|
| **Mostra o texto pronto** | renderizado pelo banco, com `{data_base}`/`{saldo_mutuos}` resolvidos e a empresa no prefixo. Bloco próprio, para ser lido como citação do que vai sair da casa |
| **Copia** | `BotaoCopiar` com plano B (`execCommand`) para o portal aberto fora de contexto seguro — e que **declara** quando não conseguiu, em vez de piscar "copiado" |
| **Registra o envio** | `fn_registrar_pergunta_acao`, com o texto EXATO da tela num campo oculto: é ele que a `0120` congela. Append-only — reenviar é linha nova, e não há como apagar |
| **Registra o descarte** | "Não vou perguntar" grava a decisão sem sumir com a sugestão: quem chegar depois vê que alguém já olhou |
| **Diz quem e quando** | `ja_enviada` vem do banco (casado por empresa); autor e data vêm de `caso_pergunta` |
| **Explica o porquê** | motivo, risco, impacto e o gatilho traduzido, recolhidos num `<details>` — sustentam a pergunta numa reunião, e ninguém quer relê-los para copiar um texto |

Três cuidados que não são enfeite:

- **A lista é paginada**, como todas as outras — e isto vale para função que devolve tabela como
  vale para consulta: o PostgREST corta em 1000 linhas em silêncio, e a sugestão é uma por
  (pergunta × empresa que não satisfaz) desde a `0119`. A ordem é `(prioridade, codigo,
  entidade_id)`, **total e estável**; o teste `#11` da `perguntas.test.sql` trava a propriedade que
  torna essa ordem total (o par código × empresa é único na saída) — sem ela, duas páginas repetem
  uma linha e omitem outra.
- **A tela diz, em cima, que nada foi perguntado ainda e que nada é enviado automaticamente.** Uma
  lista de textos prontos com um botão verde se parece com caixa de saída; não é. O canal continua
  sendo o analista.
- **Banco sem a `0120` aplicada não quebra nada.** A aba explica que a migration falta e mostra a
  resposta do banco; a tela do mandato perde só o número do botão. Merge não é apply, e o dono
  aplica à mão — banco atrasado é estado normal, não defeito.

### O teto de 1000 linhas: agora em TODAS as telas, e o pior deles era o export

O PR #136 tirou do teto do PostgREST as três listas do PAINEL. Faltavam as de DENTRO do mandato — e
entre elas estava a mais cara de todas: **o export baixava `campo_extraido` sem paginação**. Um
mandato com mais de mil linhas extraídas gerava um `.xlsx` faltando linhas, que abre normalmente e
parece completo. O book de teste sozinho tem ~3.000 linhas com número.

Passaram a paginar (`portal/src/lib/supabase/paginar.ts`, de mil em mil):

| Onde | O que era truncado |
|---|---|
| **`/casos/[id]/export`** | as **linhas extraídas** (o produto), os documentos e as causas de falha |
| `/casos/[id]` | documentos, fila de pendências do mandato, contagem de linhas por documento |
| `/casos/[id]/documentos/[docId]` | as linhas do documento (um razão real passa de mil sozinho) |
| `/casos/[id]/revisao` | a fila de revisão — que desde a `0119` multiplica pelo número de empresas |
| `/casos/todos` | mandatos, documentos e pendências |
| `/casos` (painel) | `lote_execucao`, que alimenta os indicadores de custo |
| `/api/intake/status` | os **contadores de progresso** da ingestão: a barra parava em mil e o lote parecia travado |
| `/casos/[id]/modelagem` | a lista que sugere entidade e último exercício |

**Toda consulta paginada ganhou desempate por `id` na ordenação** — sem ordem total e estável, duas
páginas podem repetir e omitir a mesma linha, que é um jeito pior de errar do que truncar.

Ficaram DE PROPÓSITO sem paginação, e não são defeito: a barra lateral (`limit(30)` deliberado), a
trilha de autonomia (`limit(15)`) e as consultas de linha única (`.single()`) ou de catálogo
(taxonomia, índices macro), que não crescem com a mesa.

### A 0121 — o achado que o dado real do dono entregou (18/08)

**Não veio de teste: veio da base.** Rodando o diagnóstico de entidades antes da rodada de
validação, quatro mandatos voltaram com **três linhas para a mesma empresa** —
`Canastra Industria 2025x2024x2023`, `CANASTRA INDÚSTRIA DE EMBALAGENS LTDA.` e
`Meses Canastra Industria`. A primeira e a terceira são sujeira de nome de arquivo, já corrigida na
origem em 17/08. **A segunda não é sujeira: é a razão social correta**, e continuava sendo criada
como linha nova — em mandato novo, com o workflow já reimportado.

**A causa é uma metade esquecida da `0030`.** Aquela migration ensinou `fn_registrar_documento` a
casar entidade pela forma canônica, porque o nome chega de duas fontes que escrevem diferente: o
arquivo e o diagnóstico do conteúdo. `fn_registrar_diagnostico` — que é **a segunda fonte** — ficou
comparando `lower(razao_social) = lower(nome)`. Os dois efeitos, reproduzidos em base limpa antes de
consertar:

1. **duplica a empresa** quando o documento chega sem entidade (o classificador se abstém em 6 dos
   38 do book) e o diagnóstico traz a razão social completa;
2. **abre pendência falsa** de `entidade_incorreta` entre duas grafias da mesma companhia — que
   `fn_mesma_entidade` já reconhecia como a mesma.

**Por que ficou caro agora:** antes da `0119`, entidade duplicada partia colunas do export. Depois
dela, a entidade é o **eixo** da cobrança de linha exigida — a mesma empresa é cobrada duas vezes,
abre pendência em dobro, e a `0120` gera duas perguntas ao cliente sobre a mesma coisa.

**O que deliberadamente NÃO foi feito:** limpar as entidades já duplicadas. Os quatro mandatos são
de teste (v41, V45, v46, v4x); fusão de entidades para arrumar dado de teste é trabalho que não se
paga. Corrigida a função que as produz, mandato novo nasce limpo — e a validação deve rodar num
mandato novo. Se a duplicata aparecer um dia em mandato de cliente, a fusão vira fatia própria.

### O PR #138 do Ian, incorporado com seis correções (0120)

**O que ele resolve:** o capítulo 10 do onboarding define 36 perguntas a fazer ao cliente depois que
a extração roda. Nenhuma era sistema — quando o analista clicava "Contatar o Cliente", o que
perguntar saía da cabeça dele. Agora `fn_sugerir_perguntas` devolve a pergunta pronta, com
motivo/risco/impacto e os marcadores preenchidos. O encaixe é o melhor da entrega:
`exigencia_ausente` lê a **mesma** `fn_exigencias_do_caso` da pendência — pendência e pergunta são
duas faces da mesma avaliação e não podem divergir. Escopo declarado: 11 das 36, com as outras 25
nomeadas família a família.

**As seis correções feitas na incorporação:**

| | O quê | Por quê |
|---|---|---|
| 1 | **Conflito com o `main` resolvido, e a `0120` entrou na lista de comandos** | O `#137` mergeou depois da base dele. E a migration não estava no `db/README.md` — o portão do `run.sh` reprovava. |
| 2 | **A migration voltou a ser reaplicável** | `create policy` sem `drop policy if exists`: rerodar morria em *"policy already exists"*. O resto do arquivo já era reaplicável (`create table if not exists`, `on conflict do nothing`) — só as políticas escapavam, e a casa já tem o padrão (`0009`, `0107`, `0108`, `0115`). |
| 3 | **`caso_pergunta` virou append-only de verdade** | A tabela dizia "append-only por desenho" e publicava `for all to authenticated`. Medido: `set role authenticated; delete from caso_pergunta` **apagou a linha**. Agora são duas políticas, SELECT e INSERT — o desenho do `evento_auditoria` (0003), que é onde ele já estava certo. |
| 4 | **`{data_base}`/`{ano}` deixaram de errar o exercício** | O período saía de `max(referencia)` — máximo de TEXTO. Num caso com `2025` e `L24M`, a pergunta ia ao cliente dizendo *"No balanço de **L24M**…"*: rótulo de janela móvel, não data de balanço, e nem o mais recente. Agora ordena por ano com `fn_anos_texto`. |
| 5 | **A verificação embutida deixou de ser alçapão** | `count(*) where ativo <> 11 → exception`: bastava você **desativar uma pergunta** (a coluna `ativo` existe para isso) para a reaplicação morrer. É o mesmo defeito que a `0119` teve, na mesma posição do arquivo. Agora ela confere as 11 pelo código, e o que você fizer depois vira NOTICE. |
| 6 | **A pergunta passou a nomear a empresa** | A pendência nomeia a entidade desde a `0119`; a pergunta, não — e ela é **enviada ao cliente**. Num grupo de oito balanços, *"no balanço de 2025 não localizamos Ativo Total"* não diz de qual empresa se fala. Era o reemit que ele mesmo previu quando a `0119` ainda não existia. `ja_enviada` passou a ser por entidade junto: enviar sobre a Alfa não responde pela Beta. |

Menor, também feito: índice em `caso_pergunta (caso_id, pergunta_codigo)`, que o `ja_enviada` usa a
cada sugestão.

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

1. **Aplicar a `0122`** — a única pendente. O dono confirmou em 18/08 (sessão 51) que aplicou
   todas até a `0121`; a `0122` nasceu depois, na mesma sessão, e é o que faz a pergunta ao cliente
   sair em português (período por extenso, valor em reais) e a janela móvel `L36M` parar de ser
   lida como o ano 2036. Merge continua não sendo apply,
   e da tela "aplicada" e "não aplicada" têm a mesma aparência, então a conferência de 30 segundos
   vale a pena depois de qualquer rodada nova:
   ```sql
   -- a 0122 acrescenta duas funções e muda uma:
   select fn_periodo_por_extenso('multi','23,24,25');  -- esperado: 2023 a 2025
   select fn_valor_pt_br(16060, 'milhar');             -- esperado: R$ 16.060 mil
   select fn_anos_texto('L36M');                       -- esperado: {} (antes: {2036})

   select proname from pg_proc
    where proname in ('fn_papel_linha','fn_reconciliar_mutuos','fn_lado_do_mutuo',
                      'fn_sugerir_perguntas','fn_registrar_pergunta_acao');
   -- a 0118 acrescenta coluna, não só função:
   select column_name from information_schema.columns
    where table_name = 'documento_versao' and column_name = 'fingerprint_extracao';
   -- e a 0118 exige que sobre UMA assinatura de fn_registrar_documento (a de 16 args):
   select pronargs from pg_proc where proname = 'fn_registrar_documento';
   -- a 0120 seedou 11 perguntas ativas:
   select count(*) from pergunta_catalogo where ativo;
   ```
   Com a `0120` no banco, a aba **Perguntas ao cliente** do mandato passa a listar de verdade.
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

- ~~**AS PERGUNTAS AO CLIENTE NÃO TÊM TELA**~~ — **fechado em 18/08 (sessão 51)**: elas ganharam
  uma **aba própria**, `/casos/[id]/perguntas`, com o texto pronto para copiar, o registro de envio
  por `fn_registrar_pergunta_acao` (texto congelado) e o de descarte. Ficaram FORA da fila de
  pendências por decisão do dono — sugestão que ninguém fez ainda não se mistura com decisão sobre
  problema medido. Ver "As perguntas ao cliente ganharam a ABA que faltava". **Depende da `0120`
  estar aplicada no Supabase**; sem ela a aba explica o que falta em vez de quebrar.
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
