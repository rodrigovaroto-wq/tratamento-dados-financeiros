# PROMPT DE CONTINUAÇÃO — execução autônoma, sem supervisão

> Cole o bloco abaixo inteiro como primeira mensagem da nova sessão. Ele é auto-contido.
> Este arquivo existe para poder ser recolado; o estado real do projeto vive no `HANDOFF.md`.

---

Você está assumindo o projeto **Tratamento de Dados Financeiros (Oria Partners)** — um pipeline que
recebe documentos financeiros de mandatos de M&A/reestruturação, extrai as demonstrações com IA,
grava em Postgres/Supabase com proveniência, e exporta um book em Excel com modelo de FP&A vivo em
fórmula.

**Você vai rodar sozinho, sem supervisão. NÃO faça perguntas — decida, execute, e registre a
decisão junto com o motivo.** Onde houver ambiguidade genuína, escolha a opção mais conservadora
(a que NÃO inventa número e a que NÃO desfaz arquitetura existente), implemente, e deixe a
alternativa registrada no `HANDOFF.md` para o dono decidir depois. Trabalhe até o fim da lista.

## 1. Antes de escrever qualquer linha

**Objetivo:** não retrabalhar o que já está feito e não repetir erro já pago.

1. Leia o **`HANDOFF.md`** inteiro até o fim da seção "Sessão 19" e a seção "Como validar". Ele é a
   fonte da verdade; este prompt é só o roteiro.
2. Confirme o estado real: `git log --oneline -12`, `git fetch origin main`, e a lista de PRs
   abertos. **Já houve sessões em paralelo neste repo** — não assuma nada sobre o `main`.
3. Trabalhe na branch **`claude/handoff-next-steps-6k88f2`**, que tem o PR **#69** aberto (draft).
   Se ele já tiver sido mergeado, comece uma branch nova a partir do `main` atualizado.
4. Prepare o container (a sessão 14 perdeu tempo nos três):

```bash
cd portal && npm install && cd ..
cd test-data/book-vertentes && pip install reportlab && PYTHONPATH=. python3 gerar.py && cd ../..
#   ^ PYTHONPATH=. é obrigatório; o GABARITO.json sai em pdf/, e sem ele o
#     verificar-export.mts morre com ENOENT (não é bug, é insumo faltando)
sudo -u postgres /usr/lib/postgresql/16/bin/pg_ctl -D /var/lib/postgresql/16/main \
  -o "-c config_file=/etc/postgresql/16/main/postgresql.conf -k /tmp -p 5432" -l /tmp/pg.log start
```

**Resultado esperado desta etapa:** você sabe dizer, em uma frase, o que está mergeado, o que está
aberto no #69, e as quatro suítes rodam limpas antes de você mudar qualquer coisa (números atuais:
n8n **160**, export **198**, db com **32 migrations**, e2e **18**).

## 2. As regras deste projeto (violá-las é o erro mais caro que existe aqui)

Estas não são preferências de estilo. Cada uma nasceu de um defeito que chegou em produção.

- **Nunca apresentar ausência como dado.** Zero fabricado numa célula de premissa é indistinguível
  de uma medição de zero. Célula em branco + nota dizendo o motivo, sempre. Se você não sabe, o
  artefato tem que dizer que não sabe — e dizer o EFEITO disso ("o bloco de dívida cobra juro zero"),
  não só o fato.
- **Todo invariante novo precisa ser MEDIDO não-vazio.** Desligue a correção, rode a suíte, confirme
  que o teste reprova, religue. Registre o número de asserts que reprovaram no commit. **Duas
  fixtures da sessão 18 nasceram vazias** (passavam com o bug ligado) e só foram pegas assim.
- **Invariante afirma COMPORTAMENTO, não mecanismo.** O invariante antigo das médias exigia `COUNT(`
  na fórmula — e o `COUNT` posicional era justamente o defeito. Um teste que descreve *como* o código
  faz protege o bug.
- **Nunca inventar fixture para provar bug de produção.** Se você não consegue reproduzir o arranjo
  real, diga isso no comentário do teste e afirme só o que dá para provar. Fixture inventada passa
  verde e engana.
- **Comentário explica POR QUÊ, com o número medido junto.** Este código é lido por quem vai auditar
  um número numa entrega a cliente. "Corrige bug" não serve; "no v33 o Imobilizado inflou 3.600
  porque o total informado já incluía o Ferramental" serve.
- **Uma fatia por commit**, com mensagem que conta o defeito, a causa e a medição.
- **Rode as QUATRO suítes antes de cada commit** (comandos na seção 6). Não existe CI: se você não
  rodar, ninguém roda.
- **Para medir não-vacuidade, copie o arquivo para o scratchpad e restaure com `cp`.** `git checkout
  <arquivo>` apaga trabalho não commitado do mesmo arquivo — aconteceu na sessão 19.

## 3. O QUE EXECUTAR — em ordem, tudo

### 3.1 Fechar a Etapa 2: bloco "REFERÊNCIAS MACRO" na Modelagem

**Objetivo.** Hoje, das 15 premissas, **2** leem macro (IPCA e Selic do Focus) e das 6 séries
históricas **0** alimentam qualquer fórmula: as 18 células de média 3a/5a/10a não movem nada. O dono
decidiu (2026-07-31, decisão registrada) **trazer IGP-M, PIB, câmbio e as médias como REFERÊNCIA
agora, e deixar o seletor que escolhe qual índice dirige o quê para a Etapa 5** — não antecipe o
seletor.

**Por que não é só "trazer as séries".** O modelo é dirigido por percentual de receita (CPV =
`RL × (1 − margem alvo)`, SG&A = `% da RL`), então IGP-M/PIB/câmbio **não têm alavanca** hoje. O bloco
é honesto sobre isso: ele informa e prepara, e cada linha DIZ o que ela deveria dirigir.

**Como fazer.**
- A infraestrutura já está commitada: `RefsMacro.mediaDe` (mapa série → `{linha, colunas}` das médias
  na aba Macro) e `RefsMacro.janelasMedia`. Só falta consumir em `construirAbaModelagem`
  (`portal/src/lib/export.ts`).
- Posição: **depois** da linha "↳ cobertura do Focus", junto das conferências. **Nunca no meio do
  bloco de premissas** — `P(i)` endereça premissa por deslocamento a partir de `rPremissas`, e uma
  linha inserida ali desloca todas as fórmulas do modelo em silêncio. A linha em branco após as
  premissas é o que encerra o bloco para o invariante que conta 15.
- Conteúdo, tudo em FÓRMULA lendo a aba Macro (nunca valor escrito — a planilha tem que continuar
  viva): IGP-M, PIB e câmbio do Focus **por exercício** (mesma mecânica de `focusMacro`, com o mesmo
  tratamento de ausência da fatia 4 — em branco + nota, jamais zero), e as médias 3a/5a/10a por série.
- Cada linha com nota dizendo (a) a fonte, (b) **o que ela deveria dirigir** e (c) que a escolha do
  índice que dirige é o seletor da Etapa 5, ainda não construído.
- Cabeçalho do bloco explícito: estas linhas **não movem o modelo sozinhas**. Uma referência que
  parece premissa é pior que nenhuma.

**Resultado esperado.** Invariante novo provando: as linhas existem, são fórmula (não valor), citam
a aba Macro, o tratamento de ausência é o mesmo da fatia 4, e a contagem de premissas **continua 15**
(as referências não são premissas). Medido não-vazio.

### 3.2 A dupla contagem no total do grupo — o bug ABERTO mais caro

**Objetivo.** No teste v33, o Imobilizado usou o **total informado** (5.590, que já inclui
"Ferramental e moldes") e o Ferramental foi somado **de novo** em "Outros Ativos Não Circulantes":
Ativo Não Circulante inflado em **3.600**, sem nada acusar. O vocabulário foi corrigido; **a guarda no
PARENTE continua aberta**: sempre que uma conta de uma seção com total informado cai numa seção irmã,
o grupo conta duas vezes e nada detecta.

**Como fazer.** Duas frentes, e a segunda é a que fecha de verdade:
1. **Detecção no parente** (`portal/src/lib/export.ts`, perto de `escreverConferenciaExtraido`):
   quando um grupo tem total informado E a soma das contas classificadas nas seções irmãs excede o
   total informado do conjunto, isso é sinal de dupla contagem. Pinte a divergência e nomeie a conta
   suspeita — **não corrija sozinho**: mostrar as duas leituras para o humano decidir é a doutrina
   (`docs/04`), corrigir automaticamente não é.
2. **A fixture.** ⚠️ **Leia isto antes de escrever teste:** duas fixtures da sessão 18 para provar
   esta dupla contagem **nasceram vazias** — uma declarava `secao` (e aí `subsecaoAutoritativa` já
   acertava), a outra tinha `ordem` entre contas do Imobilizado (e o consenso de irmãos acertava).
   Use o **arranjo real**: conta SEM `secao` declarada, `ordem` que a coloque FORA da vizinhança do
   Imobilizado, e o total informado do grupo presente. Prove que a fixture é não-vazia **desligando a
   detecção** antes de comemorar. As linhas reais estão no book sintético
   (`test-data/book-vertentes`, Balanço da Componentes: 14.200 + 3.600 + 890 − 13.100 = 5.590).

**Resultado esperado.** Um caso que hoje passa silencioso passa a ser sinalizado no arquivo, com
invariante medido não-vazio. Se depois de tentar você concluir que não dá para reproduzir sem
inventar fixture, **pare, não invente**: registre no `HANDOFF.md` o que você tentou e por que cada
tentativa nasceu vazia. Isso é resultado válido.

### 3.3 As 5 pré-condições de Ativo Total / Passivo+PL do v33

**Objetivo.** Continuam abertas. A `0030` corrigiu o casamento de COLUNA (balanços combinados); estes
são balanços INDIVIDUAIS, onde o problema é o casamento de **RÓTULO** — caminho diferente. E há uma
divergência real (Ativo 158.801 × Passivo+PL 126.673, diferença **32.128**) que pode ser a mesma
família de dupla contagem do item anterior.

**Como fazer.** Reproduza contra o book sintético, identifique se a pré-condição falha por rótulo não
reconhecido ou por ausência real de linha, e trate a causa. Se a diferença de 32.128 for a mesma
dupla contagem, diga isso explicitamente e resolva junto — não abra dois caminhos para uma causa.

**Resultado esperado.** Ou as pré-condições passam a ser satisfeitas, ou o arquivo passa a declarar
por que não são, nomeando o rótulo que não casou. Nunca ficar em silêncio.

### 3.4 CI — a alavanca mais barata contra regressão neste repositório

**Objetivo.** **Não existe CI.** As quatro suítes só rodam quando alguém lembra. Isso já custou:
defeitos que rodavam sem erro e entregavam número errado por várias sessões.

**Como fazer.** Um workflow do GitHub Actions rodando, em todo push e PR: `node --test
'n8n/test/*.test.mjs'`, os três geradores de workflow **e a verificação de que o JSON gerado está
igual ao commitado** (`git diff --exit-code` depois de gerar — é o que impede o gerado divergir da
fonte), `npx tsx portal/scripts/verificar-export.mts`, `db/test/run.sh` contra um serviço Postgres 16,
`test/e2e/run.mts`, e `tsc --noEmit` + `eslint` no portal. Cache de `npm` e as fixtures geradas com
`PYTHONPATH=. python3 gerar.py`.

**Resultado esperado.** O PR mostra verde/vermelho sozinho. Confirme que passa de verdade — CI que
falha por configuração e é ignorada é pior que CI nenhuma.

### 3.5 Análise crítica do que foi feito na sessão 19 (pedido explícito do dono)

**Objetivo.** O dono pediu, literalmente, que você **analise criticamente tudo o que foi feito hoje e
otimize/melhore o que você julgar necessário**. Não é revisão de cortesia: procure o que está errado.

**O que revisar** (commits `f66e088`, `a182c1a`, `f3cd198`, `c0106b2` — e o `git diff main...HEAD`):
- **`n8n/lib/hash.mjs`** — SHA-256 em JS puro. Reimplementação de primitiva criptográfica merece
  desconfiança: confira contra `node:crypto` em entradas que os testes não cobrem (multi-bloco
  grande, exatamente 2^29 bytes é caro demais mas pense no cálculo do comprimento em bits, entrada
  vazia, `Uint8Array` com `byteOffset` não-zero vindo de um `subarray`). **Meça o tempo** num PDF de
  ~5 MB: se o custo for relevante no lote de 14 documentos, diga o número.
- **Fatia 4 (Focus em branco)** — a célula vazia é 0 na aritmética do Excel. Verifique se existe
  algum caminho onde o vazio produz `#VALUE!` em vez de 0, e se a linha viva de cobertura sobrevive a
  o dono mover "Último exercício realizado" e o primeiro ano.
- **Fatia 5** — a linha de aviso na aba Macro é escrita antes das outras justamente para não deslocar
  `linhaCabFocus`. Confirme que **nenhum outro caminho** insere linha na aba Macro depois da captura
  dos endereços.
- **`0032` (câmbio)** — a base do ano vem da série inteira, não da filtrada por `p_desde_ano`.
  Confirme com um caso onde o filtro corta exatamente o ano-base. Verifique também o efeito do
  retorno **NULL** do primeiro ano em quem consome (`completosDe`, as médias, a aba Macro): NULL não
  pode virar zero em nenhum ponto do caminho.
- **Custo de contexto do export** — `portal/src/lib/export.ts` está enorme. Se identificar um corte
  limpo (a aba Macro e a Modelagem são candidatas naturais), faça, **desde que as suítes continuem
  verdes e nenhum endereço de célula mude**.

**Resultado esperado.** Ou você confirma que está correto, com a medição que sustenta a afirmação, ou
você corrige. Achado sem correção vira linha no `HANDOFF.md` com o motivo de não ter sido corrigido.

### 3.6 Se sobrar fôlego — nesta ordem

Só depois de 3.1 a 3.5. Cada um tem contexto detalhado no `HANDOFF.md`:

1. **Truncamento de CSV/XLSX em 50 linhas antes de ir à IA** — um faturamento de 24-36 meses perde o
   resto, em silêncio. Perde dado de verdade.
2. **`moeda` capturada e descartada** — não há coluna; USD é indistinguível de BRL na planilha. Com o
   erro de escala corrigido, este é o último fator multiplicativo invisível que sobrou.
3. **`completude_ok` só exige a linha `documento`** — 14 documentos com zero linhas dão dashboard
   verde e book vazio.
4. **`fn_aceitar_extracao` aceita versão com zero campos** e grava decisão de aprovação.
5. **Poller do upload expira em 12 min sem sinalizar**, e a recusa do orçamento (`throw` do
   `Orcamento do Lote`) só existe no log do n8n — invisível para o dono.

**NÃO faça** (é a Etapa 3+ do plano do dono, e ele valida etapa por etapa): automatizar a Modelagem
tirando as fórmulas entre abas, ocultar abas auxiliares, construir o seletor de inputs macro. E **não
reabra o RLS**: o dono decidiu manter acesso aberto a qualquer autenticado (só time interno usa).

## 4. Ao terminar

1. **Atualize o `HANDOFF.md`**: contadores das suítes, o que fechou, o que ficou aberto e por quê, e
   as armadilhas novas que você encontrou. Ele é o que a próxima sessão lê.
2. **Atualize a descrição do PR #69** (ou abra um novo, draft) com o que entrou.
3. **Deixe explícito para o dono** o que ele precisa fazer à mão: aplicar migrations (a `0032` e
   quaisquer novas, em ordem), reimportar `workflow.e1-ingestao.json` e `workflow.macro.json`, e
   conferir que o campo `hash` de `Preparar Conteudo` agora vem preenchido.
4. **Relate honestamente**: o que você não conseguiu, o que ficou meio-feito, e o que você mediu ×
   o que você supôs. Um relatório que esconde o que faltou custa a próxima sessão inteira.

## 5. Como validar (rodar SEMPRE antes de commitar)

```bash
node --test 'n8n/test/*.test.mjs'                       # 160 hoje
node n8n/build-workflow.mjs                             # regenera e COMMITA o gerado
node n8n/build-workflow-macro.mjs
node n8n/build-workflow-diagnostico.mjs
npx tsx portal/scripts/verificar-export.mts             # 198 hoje
sudo -u postgres env PGHOST=/tmp PGPORT=5432 PGUSER=postgres db/test/run.sh
E2E_PSQL="sudo -u postgres psql -h /tmp -p 5432" npx tsx test/e2e/run.mts   # 18 hoje
cd portal && npx tsc --noEmit && npx eslint . && npx next build
```

O `e2e` é a única suíte que cobre a COSTURA extração → banco → export; as outras validam seu pedaço
contra fixture escrita à mão nas duas pontas, e as duas pontas podem errar juntas.

## 6. Armadilhas conhecidas (custaram tempo real, não repita)

- **Backtick dentro dos templates de código dos nós n8n**: o gerador monta o `jsCode` como template
  literal, então um backtick num COMENTÁRIO fecha a string e o JS do nó sai quebrado. O gerador não
  parseia — só o teste pega. Aconteceu duas vezes. Aspas simples em `e'` idem.
- **Ordem de parâmetros**: `classificarConta(estrutura, secao, chave, secaoCanonica)` — estrutura
  PRIMEIRO; `classificarDemonstracao(secao, chave, secaoCanonica, estrutura)` — diferente.
- **Schema**: `entidade` e `periodo` NÃO têm `criado_em`; `periodo.tipo` é `text`, não enum; `caso`
  não tem `tipo_mandato`; `pendencia` usa `criada_em`.
- **`avaliarCelula` NÃO segue referência entre abas** — toda célula de ano da aba Macro é
  `IF('Macro (dados)'!X="","",…)`, então médias e valores da Macro não dão para avaliar por ali; use
  asserção estrutural e comente o motivo.
- **`notaDaLinha` no harness precisa de `includeEmpty: true`** — nota de célula sem valor é pulada, e
  a fatia 4 vive exatamente de notas em células vazias.
- **`git checkout <arquivo>` para desfazer um patch de medição apaga o resto do seu trabalho no mesmo
  arquivo.** Copie para o scratchpad e restaure com `cp`.
- **O `verificar-export.mts` conta premissas varrendo do cabeçalho "PREMISSAS" até a primeira linha
  vazia** — linha nova logo depois do bloco entra na contagem e reprova os invariantes 14/15.
- **`spliceRows` na aba Macro** desloca `linhaCabFocus`/`linhaFocusDe` e cada INDEX/MATCH do modelo
  passa a apontar uma linha acima, em silêncio.
