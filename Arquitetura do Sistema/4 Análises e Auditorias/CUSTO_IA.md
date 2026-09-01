# Custo da IA — onde o dinheiro vai e como reduzir sem perder qualidade

> **ESTE ARQUIVO CHAMAVA-SE `CUSTO_OPENAI.md` até 24/08/2026.** O provedor virou escolha
> (`N8N/lib/provedor.mjs`) e o padrão passou a ser o **Google (Gemini 3.5 Flash-Lite)`**. O corpo do
> documento abaixo foi escrito com os preços do `gpt-4o` e **fica como está**: as alavancas que ele
> descreve — mandar texto em vez de imagem, não pagar o PDF duas vezes, cache de prefixo, não pagar
> re-extração, agrupar a saída — são todas sobre **quantos tokens** se gasta, e nenhuma delas muda
> com quem cobra por eles. O que mudou foi o preço do token, e isso está no **último adendo**, que é
> por onde começar se a pergunta for "quanto custa hoje".

**Data:** 2026-07-27. Pergunta do dono: *"gostaria de reduzir um pouco o custo sem comprometer a
qualidade, como fazemos isso?"*

> Âncora real medida pelo dono: o **"teste v18" (16 documentos reais) custou ~US$ 3**. As estimativas
> abaixo são coerentes com essa ordem de grandeza. Confirmar preços atuais na página de pricing do
> provedor antes de decidir — eles mudam.

## Onde o dinheiro vai hoje

Por documento processado, o pipeline faz **até duas** chamadas ao `gpt-4o`:

| Chamada | Quando roda | O que envia | Peso |
|---|---|---|---|
| **Classificação por conteúdo** | só quando o NOME do arquivo não dá confiança ≥ 0,7 (`lib/classifier.mjs`) | o PDF inteiro (multimodal) + schema pequeno | input alto, output mínimo |
| **Extração linha a linha** | **sempre** | o PDF inteiro (multimodal) + prompt de sistema (~2,5k tokens) | input alto, **output alto** |

Três fatos que explicam quase toda a conta:

1. **O conteúdo do PDF domina o input.** Cada página vira tokens de imagem (~1k por página), então um
   balanço de 10 páginas custa ~10k tokens de entrada — muito mais que qualquer prompt nosso.
2. **Output custa ~4x o input.** A extração devolve centenas de linhas; é o item mais caro por token.
   Já foi otimizado: as chaves do JSON são curtas (`s`/`sc`/`k`/`vn`…), o que cortou 30-40% da saída.
3. **Documento mal nomeado paga o PDF DUAS vezes** — a chamada de classificação e a de extração
   enviam o mesmo arquivo.

## Alavancas, da maior para a menor

### 1. Enviar o PDF como TEXTO, não como imagem — economia estimada de 60-80% do input
Demonstrações geradas por sistema contábil têm **camada de texto**. Hoje mandamos as páginas como
imagem (o modelo "olha" o PDF). Extrair o texto e mandar texto puro reduz de ~10k para ~4k tokens num
documento de 10 páginas **e melhora a precisão dos números** (não há erro de leitura visual). Só vale a
imagem para documento escaneado/assinado sem camada de texto.

- **Como:** nó *Extract From File* (PDF → texto) antes do `Preparar Conteudo`, com fallback para
  imagem quando o texto vier vazio (sinal de escaneado).
- **Bônus:** o MESMO nó fecha o gap de `.docx`/`.xlsx` (hoje o conteúdo desses arquivos nem é lido —
  finding crítico da auditoria; faturamento e mútuos costumam chegar em planilha).
- **Por que não fiz agora:** muda a topologia do grafo e depende de nó/runtime da sua instância —
  não é seguro implementar às cegas. É a **próxima fatia recomendada**, com você validando ao vivo.

### 2. Não enviar o PDF duas vezes — até 50% nos documentos mal nomeados
A chamada de classificação por conteúdo é **quase redundante**: a chamada de extração já devolve, no
bloco `diagnostico`, o tipo/entidade/período do conteúdo. Dá para classificar pelo nome (barato,
determinístico), extrair, e usar o diagnóstico da própria extração como classificação — em vez de uma
chamada dedicada.

- **Cuidado:** hoje o `documento.tipo_taxonomia` é gravado ANTES da extração, e o diagnóstico compara
  contra ele para abrir pendência. Inverter essa ordem é mudança de topologia → validar ao vivo.

### 3. Cache de prompt — ~50% do prefixo, **já ativo e agora travado por teste**
A OpenAI cacheia automaticamente o prefixo do prompt (a partir de ~1024 tokens) e cobra cerca da
metade pelos tokens em cache. Nosso prompt de sistema (~2,5k tokens) é **idêntico em toda chamada** e
vem como primeira mensagem — condição exata para o cache valer. Isso paga a maior parte do custo de
tê-lo completo e explícito.

- **Invariante a não quebrar:** nada específico do documento pode entrar no prompt de sistema (nome do
  arquivo, tipo, período vão na mensagem de *user*). Um teste em `workflow-sim.test.mjs` trava isso —
  se alguém interpolar dado por documento no prefixo, o teste quebra antes de a conta subir.

### 4. Não pagar re-extração do mesmo arquivo — 100% do custo de cada reprocessamento evitável
`fn_registrar_documento` **não é idempotente por hash**: reenviar o mesmo arquivo cria um `documento`
novo e roda a extração de novo, pagando tudo outra vez. O próprio histórico registra **11 registros de
`documento` para 2 arquivos** em testes iterativos.

- **Como:** casar por `hash` antes de inserir; se o arquivo já foi extraído com sucesso, virar uma nova
  versão sem reprocessar (ou pular a chamada por um IF no N8N).
- **Status:** o lado do banco é implementável/testável aqui; o "pular a chamada" precisa de um nó no
  N8N. Fatia candidata.

### 5. Modelo mais barato na tarefa leve — ~94% daquela chamada
A classificação por conteúdo é a tarefa mais simples do pipeline (escolher um código de um enum +
entidade/período). Um modelo mini custa uma fração do `gpt-4o`. **A extração NÃO deve mudar de
modelo** — é a tarefa que exige julgamento contábil linha a linha.

- **Rede de segurança que torna isso seguro:** se a classificação errar, o `diagnostico` da extração
  (que segue no modelo forte) confere tipo/entidade/período e **abre pendência** na fila de revisão;
  confiança baixa também cai na fila. Ou seja: erro de classificação é detectado, não silencioso.
- **FEITO em 13/08/2026** (ver o adendo do fim). `MODELO_CLASSIFICACAO` e `MODELO_EXTRACAO` moram em
  `N8N/lib/custo.mjs` (mudaram de `build-workflow.mjs` quando o orçamento passou a precisar do preço
  delas). Hoje: classificação em `gpt-4o-mini`, extração em `gpt-4o`. Trocar é uma linha +
  `node N8N/build-workflow.mjs` — e um teste reprova quem apontar a EXTRAÇÃO para o modelo barato.
- **Como testar sem gastar:** rode o **kit de PDFs sintéticos** (9 arquivos pequenos) com a
  classificação em mini e confira se tipo/entidade/período saem certos. Custa centavos.

### 6. Saída: era ONDE ESTAVA O DINHEIRO — o agrupamento cortou 45%
> **Esta seção estava errada e a fatura de 13/08/2026 provou** (ver o último adendo). Ela dizia "já
> otimizada, sem corte seguro sobrando" porque olhava só a CARGA ÚTIL de cada linha. Metade da saída
> era **contexto repetido** — `s`/`sc`/`ec`/`pc`/`op` iguais em dezenas de linhas seguidas — e o
> rótulo da conta reescrito uma vez por coluna de período. A saída passou a ser AGRUPADA e caiu 45%,
> com o mesmo dado no banco.

As chaves curtas cortaram 30-40% do NOME do contexto; o agrupamento parou de REPETI-LO. O que resta
agora é carga útil de verdade: `vt` (valor como impresso) é a trilha de auditoria da conversão de
sinal/decimal; `cf` (confiança) alimenta o auto-aceite ≥95% e a guarda de baixa confiança; `op`
(página) é proveniência. Cortar qualquer um troca custo por qualidade — e, medido, cada um vale
centavos: com schema estrito não se pode OMITIR chave, então "só quando relevante" economiza ~zero.

## Falsas economias (não mexer)

- **Aumentar o intervalo de batching** não reduz custo, só a velocidade (é espaçamento, não volume).
- **Reduzir as tentativas de retry** não economiza: um 429 é rejeitado **sem cobrança** de tokens.
- **Encurtar o prompt de sistema** economiza pouco (é cacheado a ~50%) e custa qualidade de extração —
  cada instrução ali corrige um erro real observado em produção (escala, sinal, período, entidade).

## Recomendação prática

1. ~~**Agora, sem risco:** rode o kit sintético com `MODEL_CLASSIFICACAO = 'gpt-4o-mini'` e compare.~~
   **Feito em 13/08/2026.** O que falta é a conferência ao vivo: rodar o kit sintético e ver se
   tipo/entidade/período continuam saindo certos com o modelo barato.
2. **Próxima fatia (maior ganho):** PDF como texto + `.docx`/`.xlsx` via *Extract From File* —
   corta a maior parte do input **e** fecha o gap crítico de formato. Precisa de você ao vivo no N8N.
3. **Depois:** dedup por hash (não pagar reprocessamento) e, por último, fundir a classificação na
   chamada de extração.
4. **Sempre:** usar o kit sintético para qualquer experimento — é o que permite iterar por centavos em
   vez de dólares.

---

## Adendo (teste v30, 2026-07-30) — `max_tokens` é RESERVA de TPM, e isso muda a conta

14 de 14 documentos falharam com 429, incluindo notas explicativas de poucas linhas. A causa física
não era "muitos arquivos": é que a OpenAI documenta o consumo de rate limit como

> "your rate limit is calculated as the **maximum** of `max_tokens` and the estimated number of
> tokens based on the character count of your request"

Ou seja: **toda extração reserva `max_tokens` (16.384) do balde por minuto**, para um PDF de 2 KB ou
de 40 páginas — os dois pagam igual. Isso explica o único fato que não fechava com a hipótese de
cadência: por que os arquivos minúsculos também caíram.

A cadência deixa de ser opinião e passa a ser aritmética:

| | cálculo | resultado |
|---|---|---|
| Chamadas/min suportadas | TPM da conta ÷ `max_tokens` | Tier 1: 30.000 ÷ 16.384 = **1,8** |
| Intervalo mínimo | 60.000ms ÷ chamadas/min | **~33s** |
| O que estava configurado | 12s = 5 chamadas/min | **81.920 TPM — 2,7x o Tier 1** |

Com 12s (e antes com 6s) o lote **não tinha como passar no Tier 1**, e "espaçar um pouco mais" nunca
seria suficiente. `N8N/build-workflow.mjs` agora deriva o intervalo de `TPM_CONTA / MAX_OUTPUT_TOKENS`,
e um teste (`workflow-sim.test.mjs`) reprova quem mexer num dos dois sem recalcular o outro.

**As três saídas, em ordem de impacto:**

1. **Subir o tier da conta** (decisão do dono, sem código): Tier 2 do gpt-4o são 450.000 TPM → o
   intervalo cai de 33s para ~2,2s. Para o mesmo lote de 14, a diferença é 8 minutos contra 30
   segundos. É a alavanca de maior efeito e a única que não exige trade-off técnico.
2. **Reduzir `max_tokens`** (decisão de risco): a reserva cai proporcionalmente e o intervalo com ela.
   O limite existe por um bug real — resposta truncada gravava 0 linhas em silêncio (sessão 7 cont.⁷)
   —, mas hoje o truncamento é DETECTADO (`finish_reason=length` abre pendência), então o risco é
   visível em vez de silencioso. Medir antes: a maior extração observada no book tem ~140 linhas
   (≈8k tokens de saída), então 16.384 tem folga de 2x.
3. **PDF como TEXTO em vez de imagem** (a alavanca de sempre): corta 60-80% do INPUT. Não muda a
   reserva de `max_tokens`, mas reduz o outro lado da conta — e é o que faz o custo por documento cair
   junto. Continua exigindo o nó *Extract From File* no N8N vivo.

**Diagnóstico em 10 segundos:** `OPENAI_API_KEY=sk-... node N8N/diagnosticar-openai.mjs` faz uma
chamada de 1 token e diz se é crédito, cota diária ou cadência — e imprime o TPM real que a OpenAI
informa nos headers, número que até aqui era chute em todo o repositório.

---

## Adendo (teste v31, 2026-07-30) — a alavanca 2 agora está MEDIDA, e o dono a aciona sem código

A alavanca 2 acima ("não enviar o PDF duas vezes") estava estimada em "até 50% nos documentos mal
nomeados". O v31 permite medir, porque a decisão de fazer a segunda chamada é **determinística e
derivável só do nome do arquivo**: `precisa_fallback_openai = confianca < 0.7`. Rodando o classificador
nos 14 arquivos reais do teste:

| Padrão do nome | Confiança | 2ª chamada (documento inteiro, `gpt-4o`) | Qtd |
|---|---|---|---|
| `..._2025x2024.pdf` (dois anos) | 0,60 + 0,30 = **0,90** | não | 6 |
| `..._2025.pdf` (um ano isolado = sinal **fraco**, +0,05) | **0,65** | **sim** | 7 |
| `10_Faturamento_24M_...` (sem ano reconhecido) | **0,60** | **sim** | 1 |

**8 dos 14 documentos (57% do lote) pagaram o input duas vezes** — e não por serem difíceis: por
causa de um caractere no nome. O que dispara o custo é o `fraco: true` que `parsePeriodo` atribui a um
ano isolado de 4 dígitos, deliberadamente, para que nome de arquivo sozinho não pule a verificação da
IA (essa penalidade está certa e **não** deve ser removida — ver o teste
`entidade do nome NÃO altera confiança nem o limiar de fallback`).

### A consequência prática: renomear é a economia mais barata que existe aqui

Usar a notação de período de `Arquitetura do Sistema/2 Especificação/f0/03` no nome do arquivo elimina a segunda chamada, porque
`12M25`/`L24M` são sinais FORTES (+0,30) em vez de fracos (+0,05) — sem mexer em nenhum limiar:

```
08_DFC_Vertentes_Metalurgica_2025.pdf        0,65 → chama a IA
08_DFC_Vertentes_Metalurgica_12M25.pdf       0,90 → NÃO chama          ← mesma informação

10_Faturamento_24M_Vertentes_Metalurgica.pdf 0,60 → chama a IA
10_Faturamento_L24M_Vertentes_Metalurgica    0,90 → NÃO chama
```

Zero risco (a classificação por nome continua sendo conferida contra o conteúdo pelo `diagnostico` da
extração, que roda sempre), zero código, e no lote do v31 corta **8 chamadas `gpt-4o` carregando o PDF
inteiro** — a maior redução disponível hoje sem depender do N8N ao vivo.

### E o que NÃO é economia, apesar de parecer

`max_tokens: 16384` **não custa dinheiro** — só reserva TPM (ver o adendo do v30). Baixá-lo acelera o
lote, não barateia: a cobrança é sobre os tokens realmente gerados. Quem quiser reduzir gasto de
verdade mexe no INPUT (alavancas 1 e 2), não na saída.

---

## Teto de gasto em CÓDIGO (2026-07-31) — duas defesas, camadas diferentes

Pedido do dono depois do v31: **no máximo US$ 3 por execução completa, e o teto da OpenAI em US$ 5**.
São duas coisas, e confundi-las é o que faz um teto não proteger:

| Defesa | Onde vive | O que acontece quando estoura |
|---|---|---|
| **US$ 5 por projeto** | Conta da OpenAI (Settings → Projects → Limits) | a API recusa; o pipeline registra `limite_de_gasto`. Foi o v31: o teto cortou no meio do lote e **8 documentos ficaram registrados sem extração**. |
| **US$ 3 por execução** | `N8N/lib/custo.mjs` (`TETO_EXECUCAO_USD`) | o nó `Orcamento do Lote` **recusa o lote antes da primeira chamada**, com uma mensagem que diz quantos documentos mandar por leva. |

A folga entre 3 e 5 é deliberada: ela garante que quem barra o lote seja o **código** (que explica o que
fazer, e não gastou nada) e não a **API** (que devolve 429 e deixa estado pela metade). E o teto da
OpenAI continua sendo a defesa dura — um teto que o próprio sistema controla é um teto que um bug do
próprio sistema fura.

### Onde o guarda fica, e por que ali

`Classificar Nome` → **`Orcamento do Lote`** → `Preparar Conteudo`. É o último ponto em que o lote
inteiro está visível **e** nada custou ainda: cada item já sabe se `precisa_fallback_openai`, então a
contagem de chamadas é **exata** — não estimada. Contar chamadas em vez de documentos importa porque
documento mal nomeado paga o PDF duas vezes (alavanca 2 acima).

O lote é recusado **inteiro**. Não existe "roda os que cabem" de propósito: metade registrada sem
extração e metade sem registro nenhum é estado que dá mais trabalho para desfazer do que o reenvio que
a mensagem de recusa pede.

O efeito no lote real do v31, que os testes travam:

```
antes do renome:  14 documentos → 22 chamadas ≈ US$ 4,40  → RECUSADO antes de gastar
depois do renome: 14 documentos → 14 chamadas ≈ US$ 2,80  → passa
```

### Estimativa vs. medição — e como apertar o teto com honestidade

`CUSTO_ESTIMADO_DOC_USD = 0,20` (era 0,15 até 07/08/2026 — ver o adendo da medição abaixo) é
**estimativa declarada** (o cálculo está no comentário da constante), posta acima do custo medido
para errar para o lado seguro. Barrar um lote que
caberia é um aviso; deixar passar um que não cabe é o v31 de novo.

`custoDaChamada` mede o **real** a partir do bloco `usage` que a OpenAI devolve — inclusive cobrando
tokens em cache pela metade, que é material aqui porque o prompt de sistema é idêntico em toda chamada.
O valor medido sai em `Parse Extracao` (`custo_usd` + `tokens`), visível na execução do n8n. **É com ele
que a constante deve ser recalibrada depois do próximo lote** — e só então faz sentido apertar o teto.

Se `usage` não vier, `custoDaChamada` devolve `null` em vez de chutar: número inventado num relatório de
custo é pior que campo vazio.

### Diagnóstico sem terminal

`N8N/workflow.diagnostico-ia.json` (gerado por `build-workflow-diagnostico.mjs`) faz o mesmo que
`diagnosticar-openai.mjs`, mas como **workflow importável**: trigger manual, uma chamada de 1 token na
credencial `OpenAI API` que já existe, e um veredito em texto. Nasceu porque o dono não usa terminal — e
um diagnóstico que o dono não consegue rodar não diagnostica nada. Não grava em banco, não tem trigger
de relógio, e o veredito sai do **mesmo** `diagnosticarErroApi` da produção (embutido por `toString()`).


---

## Adendo (book-canastra, 2026-08-07) — a primeira MEDIÇÃO por documento, e o que ela desmentiu

Até aqui a conta de custo era uma estimativa de guardanapo confrontada com uma âncora de fatura
("o v18 custou ~US$ 3"). O `Dados de Teste/book-canastra` mudou isso: 38 documentos sintéticos, 49
páginas, 3.034 linhas com número, todos com páginas e linhas **contadas no PDF gerado**. O
`N8N/medir-custo-book.mjs` converte essa contagem em dólares usando o preço e as funções que rodam em
produção (`classifyByFilename`, `custoDaChamada`, `orcamentoDoLote`) — sem chamar a OpenAI, então
medir custa zero e pode rodar no CI.

**Custo medido do lote inteiro: US$ 1,41 em 57 chamadas.** Três coisas saíram diferentes do que este
documento afirmava:

**1. O gargalo não é a entrada, é a SAÍDA.** A extração devolve ~106 mil tokens de saída (3.034 linhas
× ~35 tokens) contra ~49 mil de entrada de imagem. A US$ 10/M contra US$ 2,50/M, a saída responde por
**~75% da conta**. Consequência direta: a alavanca nº 1 deste documento — mandar o PDF como TEXTO em
vez de imagem — economiza **5%** neste book, não os 60-80% que a seção prometia. Ela continua valendo
(e continua sendo a que fecha o gap de `.docx`/`.xlsx`), mas por qualidade de leitura e por documentos
de MUITAS páginas, não por ser a maior economia. Em documento de 1 página, o PDF é troco.

**2. Existia documento realista mais caro que a estimativa que sustenta o teto.** O livro razão (3
páginas, 461 linhas) mediu **US$ 0,1725 por chamada**, acima dos US$ 0,15. Num lote só dele, a promessa
de "no máximo US$ 3 por execução" seria quebrada em ~15%. Por isso `CUSTO_ESTIMADO_DOC_USD` foi
**recalibrado para 0,20** — que é exatamente o que o comentário da constante mandava fazer quando
houvesse medição. Efeito colateral aceito: o lote máximo cai de 20 para 15 chamadas.

**3. A estimativa plana é ruim nos dois sentidos, e isso agora está medido.** Para os 38 documentos
deste book ela projeta US$ 11,40 contra US$ 1,41 medidos — **8× para cima**, o que recusa lotes que
caberiam. E para o documento denso ela ficava para baixo, que é o item 2. Um número plano não pode
acertar os dois, porque o custo depende de **páginas e linhas**, e nenhuma das duas entra na conta.

> **A fatia seguinte, com o número que a justifica:** estimador por TAMANHO DE ARQUIVO. `Listar
> Arquivos` já conhece os bytes de cada arquivo antes de qualquer chamada, e bytes correlacionam com
> páginas e com densidade de linha. Trocar `custoPorChamada` fixo por `custoPorChamada(bytes)`
> resolveria a superestimação de 8× e a subestimação do documento denso de uma vez. Não foi feito
> agora porque muda o contrato do nó de orçamento no n8n e merece rodada própria.

**19 dos 38 documentos pagam o PDF duas vezes** — 6 porque o nome não diz o tipo (`Doc1.pdf`,
`digitalizado_20260115_0003.pdf`, `ANEXO IV - planilha final REV3.pdf`, e os três tipos que a
taxonomia não tem: imobilizado, folha e parecer de auditoria), 13 porque o nome traz **ano solto**
(`..._2025.pdf`), que é sinal fraco e não chega ao limiar de 0,70. Renomear para a notação de Arquitetura do Sistema/2 Especificação/f0/03
corta 19 chamadas — e **ainda assim o lote não cabe**: 38 × US$ 0,20 = US$ 7,60. Com kit de mandato
completo, dividir em levas não é contorno de nome mal escolhido, é a operação normal.

**A medição achou um defeito que não é de custo:** o arquivo `17_Livro_Razao_Fornecedores_...`
saía classificado como `AGING_AP` com confiança 0,90 — alta o bastante para pular a verificação da IA
e mandar um livro contábil para a aba de contas a pagar. A causa era a ordem de `ALIASES`:
`fornecedores` (uma palavra, genérica) era testado antes de `livro razao`. Corrigido, com teste que
reprova religado. O defeito só apareceu porque um book passou a ter razão **e** aging no mesmo lote.

---

## Adendo (2026-08-13) — a redução pedida pelo dono, e a recusa que era de outro workflow

**O que o dono relatou:** reexecutou o lote de 35 documentos depois das correções da sessão 42 e
recebeu *"51 chamadas ≈ US$ 7,65, acima do teto de US$ 3"* — a mesma recusa de antes. Pedido:
**reduzir o custo por chamada, para que o lote de 35 não passe de US$ 3.**

### Primeiro, o que aquela tela estava dizendo

Duas coisas que a mensagem não deixava claras e que mudam o diagnóstico:

1. **Não é limite de crédito da OpenAI.** Nada foi enviado e nada foi gasto: quem recusou foi o nó
   `Orcamento do Lote`, que decide **antes** da primeira chamada. O saldo da conta não foi tocado.
2. **Aquela recusa não podia ter saído do código deste repositório.** US$ 7,65 ÷ 51 chamadas =
   **US$ 0,15 por chamada** — a constante que vigorou até 07/08/2026. A versão em `main` desde a
   sessão 42 estima **por tamanho de arquivo** e nem cita "US$ 0,15". Ou seja: o n8n estava
   executando o **JSON importado em julho**. Merge não reimporta workflow, e da tela as duas
   versões têm exatamente a mesma aparência — as duas recusam.

Por isso a primeira mudança desta rodada não é de custo, é de **legibilidade**: a mensagem de recusa
agora começa com `[orçamento v3 (2026-08-13)]`, e `orcamento_versao` viaja com o item **mesmo quando
o lote passa**. "O workflow importado está velho" deixou de ser hipótese e virou leitura.

### As duas reduções REAIS, com o número de cada uma

| Alavanca | O que muda | Efeito no book (38 docs) |
|---|---|---|
| **Classificação em `gpt-4o-mini`** | a 2ª chamada (só nos documentos mal nomeados) sai de US$ 2,50/M de entrada para US$ 0,15/M | custo medido **US$ 1,41 → US$ 1,33** (−6%); a parte de classificação, **US$ 0,0893 → US$ 0,0054** (−94%) |
| **A 2ª chamada deixa de ser cobrada como se fosse extração** | o orçamento pesava "2 chamadas = 2× o custo"; medido, a classificação é ~13% de uma extração (mesma entrada, saída de 120 tokens contra centenas de linhas) | estimativa do guarda **US$ 2,46 → US$ 1,88** (−24%) |

É a recomendação nº 1 deste documento ("agora, sem risco") finalmente acionada, mais a correção da
última superestimação que restava no guarda. **A extração continua em `gpt-4o` e não deve mudar**: a
classificação tem rede — o `diagnostico` da própria extração confere tipo/entidade/período e abre
pendência quando diverge —, a extração não tem nada depois dela. Um teste trava as duas pontas.

### O desconto vale só onde há medição

O peso reduzido da 2ª chamada se aplica **apenas quando o tamanho dos arquivos chega ao nó**. Sem
tamanho, o guarda continua contando chamada cheia a US$ 0,20. O motivo é de evidência: a estimativa
plana é o caminho de "não sei nada sobre estes arquivos", e a única calibração que ela tem é um
incidente de dinheiro de verdade (o v31, que estourou o teto de US$ 5 da OpenAI no meio do lote).
Descontar ali com base numa proporção medida em PDF sintético seria trocar a evidência cara pela
barata. Um teste trava isso nos dois sentidos.

### Onde o lote de 35 fica agora

```
custo REAL medido (38 documentos, 57 chamadas)   US$ 1,33   ← era 1,41
estimativa do guarda, por tamanho                US$ 1,88   ← era 2,46 (teto: 3,00)
lote homogêneo denso (35× o livro razão)         US$ 3,80   → continua RECUSADO (custaria 6,04)
```

A margem contra o teto saiu de 18% para **37%**, e o caso caro continua barrado — que é a única
forma de o teto significar alguma coisa.

### O que ainda NÃO foi feito, e continua sendo a maior alavanca

**A saída responde por ~75% da conta.** Nenhuma das duas mudanças acima toca nela. As opções que
sobram, todas com trade-off que só o dono decide:

- **Não fazer a chamada de classificação** (usar o `diagnostico` da extração como classificação) —
  economia inteira dos US$ 0,0054, hoje irrelevante depois do mini. Deixou de valer o risco de
  topologia.
- **Menos linhas por documento**: extrair só as seções que o modelo usa. É corte de escopo do
  produto, não de custo — muda o que o book entrega.
- **PDF como texto**: 5% neste book (medido), não os 60-80% que a seção 1 prometia. Continua valendo
  pelo `.docx`/`.xlsx` e pela precisão, não pela economia.

---

## Adendo (2026-08-13, tarde) — a primeira fatura real, e o formato de saída que ela condenou

**A medição que mudou tudo:** o dono rodou os 14 documentos do `book-vertentes` e pagou **US$ 0,90**,
com o alvo de ficar **abaixo de US$ 0,50**. Foi a primeira fatura real confrontada com o modelo deste
documento — e o modelo estava errado por 45% para baixo.

### Onde o dinheiro estava, medido

| | US$ | Origem |
|---|---:|---|
| **Saída da extração** | **~0,76 (84%)** | ~1.180 células de valor × **~64 tokens** × US$ 10/M |
| Entrada | ~0,14 | 20 páginas de PDF + 14× prompt de sistema (2.906 tokens, cacheado a 50%) |
| Classificação (8 chamadas, `gpt-4o-mini`) | ~0,003 | irrelevante desde a troca de modelo |

O `TOKENS_POR_LINHA_EXTRAIDA = 35` deste repositório contava só a **carga útil** da linha. Os outros
~30 tokens eram **contexto repetido**: `s`, `sc`, `ec`, `pc` e `op` idênticos em dezenas de linhas
consecutivas, mais os nomes das chaves, mais o rótulo da conta reescrito **uma vez por coluna de
período**.

### O que mudou: a saída passou a ser AGRUPADA

Antes, uma entrada por (conta × coluna). Agora um **grupo** por seção, com as colunas declaradas uma
vez em `cols`, e a conta escrita uma vez com um valor por coluna:

```
antes  {"s":"ATIVO CIRCULANTE","sc":"ativo_circulante","ec":null,"pc":"31/12/2025",
        "k":"Duplicatas a receber","vt":"22.310","vn":22310,"op":1,"cf":0.96}   ← ×2, uma por ano
depois {"s":"ATIVO CIRCULANTE","sc":"ativo_circulante","op":1,
        "cols":[{"ec":null,"pc":"31/12/2025"},{"ec":null,"pc":"31/12/2024"}],
        "l":[{"k":"Duplicatas a receber","vt":["22.310","29.870"],"vn":[22310,29870],"cf":0.96}]}
```

**O resultado, medido pelo `medir-custo-book.mjs` sobre os PDFs de verdade:**

| Book | formato plano | agrupado | corte |
|---|---:|---:|---:|
| `book-vertentes` (14 docs — o que o dono rodou) | US$ 0,857 | **US$ 0,471** | **−45%** |
| `book-canastra` (38 docs) | US$ 2,226 | **US$ 1,252** | **−44%** |

O modelo do formato plano projeta US$ 0,857 contra os **US$ 0,90 da fatura** — 5% de erro, e é isso
que autoriza tratar os US$ 0,471 como projeção e não como esperança. **O alvo de US$ 0,50 está
atendido**, e a economia real deve ser um pouco maior: o medidor lê as colunas do NOME do arquivo,
então as sete colunas de empresa do balanço combinado não entram na conta dele.

### Por que isto não é troca de custo por qualidade

Nada é extraído de menos: `parseExtractionResponse` (e o nó `Parse Extracao`, com a MESMA função
embutida) achata os grupos de volta para uma linha por (conta × coluna), e `campo_extraido` fica
idêntico — mesmos valores, mesma `ordem` de leitura, mesma escala e moeda herdadas.

Três decisões de projeto que o formato exigiu, cada uma com o motivo:

1. **Célula em branco ocupa posição** (`null` no índice), nunca é omitida. Encostar valores à
   esquerda trocaria o número de 2025 pelo de 2024 — plausível e silencioso, o pior tipo de erro.
2. **Desalinhamento é falha, não palpite.** Se o modelo devolve 1 valor para 2 colunas, a conta é
   **descartada** e o motivo volta nomeado (vira pendência). Completar com `null` seria inventar.
3. **Subtotal abre grupo próprio** com `sc = NAO_CLASSIFICAVEL`. A seção canônica passou a ser do
   grupo; um subtotal misturado às contas que ele soma faria a seção ser contada duas vezes.

### E um defeito antigo que o formato conserta de graça

Documentos comparativos truncavam (`finish_reason=length`) antes de terminar de listar as contas —
6 de 16 no "teste v18". A resposta na época foi encurtar os **nomes** das chaves; era meia correção,
porque o contexto continuava sendo repetido. O documento mais pesado do `book-vertentes` usava 73%
do teto de saída e agora usa **45%**.

O `medir-custo-book.mjs` passou a **avisar, nomeando o arquivo**, quando a saída projetada passa de
80% do teto. Ele acusa um caso que ninguém tinha visto: o livro razão do `book-canastra` (461
células) fica em **109% do teto mesmo agrupado** — vai truncar, abrir pendência e ficar sem parte
dos dados. A saída para ele é extrair por **faixa de página**, que é fatia própria e não está feita.

### E como se olha o custo agora

O nó **`Resumo de Custo`**, no fim da cadeia, devolve num painel só: custo real do lote, quanto foi
extração e quanto foi classificação, o que o orçamento havia estimado, os tokens de entrada/saída/
cache e — o número que recalibra tudo — **tokens de saída por linha extraída**. Antes isso existia um
por documento no `Parse Extracao`, e saber o custo do lote exigia abrir 14 painéis e somar à mão.

---

## Adendo (2026-08-13, noite) — as três camadas contra o truncamento e a extração pela metade

A rodada completa do `book-canastra` (35 documentos, 21 minutos, US$ 0,71) respondeu a pergunta de
custo e abriu outra, maior: **das 2.893 células de valor dos PDFs, chegaram ao banco 1.139 — 39%.**

> **Nota de método:** essa rodada ainda usava o workflow ANTIGO (formato plano, sem o `Resumo de
> Custo` no canvas). Os 39% e os truncamentos são a **linha de base**, não efeito do agrupamento.

Duas famílias, com causas e correções diferentes:

| | O que aconteceu | Como falhou |
|---|---|---|
| **Truncamento** (5 documentos) | `01_Balanco_..._2025x2024x2023` tem 326 células = ~20.900 tokens de saída, contra o teto de **16.384 do gpt-4o**. Não cabia por construção. | **Alto**: `finish_reason=length` → `extracao_falhou` com a causa escrita. |
| **Sub-extração** (o resto) | `17_Livro_Razao` devolveu **99 de 461** sem estourar teto nenhum. | **Em silêncio**: o sistema registrou sucesso. |

Nenhum prompt conserta um teto físico, e nenhum modelo garante ler cada linha. A resposta são três
camadas, e só as três juntas sustentam a promessa:

### Camada 1 — saber o que o documento tem ANTES de chamar

Nó `Extrair Texto` (`extractFromFile`, nativo), entre o teto de gasto e o `Preparar Conteudo`: lê a
camada de texto do PDF na própria instância, sem IA e sem custo, e dela sai a contagem determinística
de **linhas com número**. É o insumo das outras duas.

`onError: continueRegularOutput` é o que torna a adição segura: PDF escaneado não tem camada de texto
e o nó falha nele — o documento segue como imagem e as camadas 2 e 3 se calam para ele. **O pior caso
desta mudança é o comportamento de ontem.**

> **O texto NÃO substitui o PDF na chamada, e isso é decisão, não esquecimento.** Seria mais barato,
> mas o texto de uma tabela perde o alinhamento das colunas — e foi justamente a leitura de coluna que
> passou a funcionar (o balanço combinado saiu com as 8 colunas de empresa certas). **O texto serve
> para MEDIR, não para LER.**

### Camada 2 — fatiar: nunca fazer o pedido que não cabe

`Fatiar Extracao` projeta a saída (~42 tokens por célula) e, quando ela passa de **60% do teto**,
emite um item por bloco de no máximo **234 células**. Não é "tentar de novo quando falhar".

O ponto fino é a **âncora**: o modelo continua vendo o PDF inteiro, então "extraia o bloco 2 de 3"
seria pedir que ele adivinhe onde a faixa começa. Cada bloco carrega o **texto exato** da primeira e
da última linha da faixa, lidos do PDF pelo extrator — vira instrução verificável em vez de proporção.
A instrução vai na mensagem de *user*; o prompt de sistema fica idêntico, senão o cache de prefixo
(alavanca 3) para de valer e o fatiamento pagaria o prompt duas vezes.

No `book-canastra`: **38 documentos → 41 chamadas de extração**, 3 documentos fatiados.

### Camada 3 — a guarda de cobertura

`Juntar Blocos` remonta o documento (renumerando `ordem` no conjunto e limpando linha repetida **na
emenda**, que é onde o modelo repete a âncora) e compara o que voltou com o que a camada 1 mediu.
Abaixo de **60%**, escreve o motivo em `falha_motivo` — que `fn_registrar_campos_extraidos` já
converte em pendência desde a `0016`. Sem migration: o caminho existia, faltava alguém **conferir**.

O limiar é calibrado na rodada real e erra para o lado de avisar demais: documentos sadios ficaram em
68%-90% (`02_DRE` 104/115, `22_Aging` 91/114, `06_Balanco` 74/109) e os incompletos em 21%-48%
(`17_Livro_Razao` 99/461, `15_Balancete` 77/162). Uma pendência falsa custa uma olhada; um buraco não
visto custa o mandato.

**O que a camada 3 promete, com precisão:** ela não impede o modelo de pular uma linha. Impede que
isso seja silencioso.

### O que muda no grafo, e o que não muda

`Montar Req Extracao` → **`Fatiar Extracao`** → `IA Extrair` → `Parse Extracao` → **`Juntar
Blocos`** → `Gravar Campos (Sombra)`. De `Gravar Campos` em diante **nada muda**: um item por
documento, com `campos` e `falha_motivo`, exatamente como antes.

### O custo sobe, e é para subir

Extrair o que faltava custa tokens: mais saída, mais uma passagem do prompt de sistema por bloco. A
projeção para o `book-canastra` sai de US$ 0,71 (com 39% do dado) para **~US$ 1,4 com o dado
inteiro** — menos da metade do teto de US$ 3. É o que o agrupamento comprou: folga para pagar o dado
que faltava.

### O limite que fica declarado

O `Orcamento do Lote` continua decidindo **antes** do `Extrair Texto`, então ele estima por bytes e
não sabe quantos blocos o lote terá. Isso encolhe a margem dele (ele superestima ~50%, e agora as
chamadas são mais). O conserto natural é mover o teto para depois da extração de texto — aí a
estimativa deixa de ser por byte e passa a ser por linha contada, que é determinística. É fatia
própria, e está no `ESTADO.md`.


---

## Adendo (2026-08-24) — a troca de provedor: o que caiu, o que foi recalibrado, e o que NÃO mudou

O dono pediu a troca de provedor com uma frase direta: *"essa do gpt não estou vendo vantagens do
que trocar para outras melhores"*. A escolha foi **Google, Gemini 3.5 Flash-Lite**, e ela é uma
troca de PROVEDOR, não de arquitetura: o pipeline continua mandando o PDF inteiro, numa chamada por
documento, com a saída presa a um schema.

### O número, medido e não estimado

`N8N/medir-custo-book.mjs` sobre os MESMOS 38 PDFs do `book-canastra`, só trocando a tabela de preço:

| | gpt-4o + gpt-4o-mini | Gemini 3.5 Flash-Lite | |
|---|---|---|---|
| lote inteiro (57 chamadas) | US$ 1,2932 | **US$ 0,2821** | −78% |
| documento mais caro (livro razão, 461 linhas) | US$ 0,1725 | **US$ 0,0459** | −73% |
| classificação das 19 mal nomeadas | US$ 0,0054 | US$ 0,0137 | +154% (e continua sendo 5% da conta) |

A classificação subiu porque os dois modelos passaram a ser **o mesmo**: na OpenAI havia 17× de
diferença de preço entre `gpt-4o` e `gpt-4o-mini`, e a linha Flash-Lite já entra no preço em que o
"barato" da OpenAI entrava. Rebaixar a classificação para uma geração anterior economizaria US$ 0,005
no book inteiro e reintroduziria o único erro que a separação sempre custou — um tipo errado que só
o diagnóstico pega, uma etapa adiante. A ESTRUTURA de dois modelos ficou de pé
(`MODELOS_POR_PROVEDOR`, em `N8N/lib/custo.mjs`): se um dia valer separar de novo, é uma linha.

### O que foi recalibrado, e por que os números não foram só divididos

Três constantes do guarda de orçamento eram calibradas contra o preço do `gpt-4o`:

| Constante | Antes | Depois | Como saiu |
|---|---|---|---|
| `CUSTO_ESTIMADO_DOC_USD` | 0,20 | **0,055** | 1,2× o documento mais caro MEDIDO (US$ 0,0459) — a mesma folga que 0,20 tinha sobre 0,1725 |
| `CUSTO_POR_MB_USD` | 10,5 | **2,80** | escalado por **0,266** |
| `CUSTO_MINIMO_CHAMADA_USD` | 0,012 | **0,0032** | escalado por 0,266 |

**Por que 0,266 e não 0,218.** Existem duas razões medidas e elas não são iguais: o lote inteiro caiu
0,218× e o documento mais DENSO caiu 0,266×. Divergem porque o preço da saída caiu menos que o da
entrada, e documento denso é o que gasta saída. Um escalar só não preserva as duas propriedades — e
escalar pelo agregado fazia o **lote homogêneo denso**, que é o caso que o teto existe para barrar,
passar a ser ACEITO. Trocar "recusa lote que caberia" por "aceita lote que não cabe" é o v31 de novo.
Vale a razão do denso. O custo declarado: o guarda por byte ficou ~2× acima do custo real do lote
típico (era ~1,45×), e continua muito longe de barrar trabalho — o book inteiro estima US$ 0,58
contra um teto de US$ 3.

**A estimativa por CONTEÚDO não precisou de nada.** Ela deriva do preço pela mesma
`custoDaChamada` que mede a conta real, então seguiu sozinha: estima US$ 0,29 contra US$ 0,2821
medidos — 3% acima, a mesma precisão de antes.

### O que a troca comprou em COMPORTAMENTO, e não em preço

- **O lote do v31 cabe.** Os 14 documentos que estouraram o teto de US$ 5 da OpenAI no meio da
  execução em 31/07/2026 — matando 8 sem extração — hoje estimam menos da metade do teto de US$ 3.
  Está travado por teste em `N8N/test/custo.test.mjs`.
- **O book de 38 documentos deixou de precisar de levas** pelo estimador plano (o caminho cego), se
  os nomes estiverem na notação de `Arquitetura do Sistema/2 Especificação/f0/03`.
- **A cadência mudou de gargalo, e para melhor.** Na OpenAI o intervalo entre extrações era de ~33s,
  aritmética do balde de TPM (`max_tokens` é RESERVA — ver o adendo do v30). No Google o balde de
  tokens é folgado e o limite é de CHAMADAS: o intervalo caiu para **8s**, derivado de 15 RPM
  contando que um documento mal nomeado faz DUAS chamadas. O lote de 57 chamadas passou de ~31
  minutos para ~7,6.

### O que NÃO mudou, e é o que mais importa

Nada do domínio. O prompt de sistema é o mesmo texto, o schema tem as mesmas propriedades na mesma
ordem, o achatamento dos grupos é o mesmo código, a normalização de escala e moeda é a mesma, e o
diagnóstico de erro é a mesma função — que agora reconhece também os corpos de erro do Google.

As alavancas deste documento continuam todas de pé, e a **nº 1 continua sendo a maior**: mandar o PDF
como TEXTO em vez de imagem. Medido no book com o preço novo, ela vale 3% — menos que os 5% de antes,
porque a entrada barateou mais que a saída, mas ela nunca foi só sobre custo: texto extraído não tem
erro de leitura visual de número.

### O checklist da troca — o que o código NÃO consegue conferir

1. **O teto de gasto do projeto no provedor NOVO.** Ele é configuração de conta e **não se herda**:
   a conta nova começa sem teto nenhum, e a defesa dura (a que barra quando este código falha) fica
   ausente até alguém ir lá pôr. É o único item desta lista que nenhuma suíte alcança.
2. **A credencial no n8n**, com o nome que o JSON gerado espera: `Google AI (Gemini)`, header
   `x-goog-api-key`, valor sem prefixo. Ver `N8N/README.md`.
3. **Zero-retention / DPA com o provedor novo** antes de dado real de cliente. Trocar de provedor não
   herda o acordo do anterior — ver `Arquitetura do Sistema/2 Especificação/10_DADOS_RETENCAO_E_LGPD.md` e `Arquitetura do Sistema/2 Especificação/f0/02`.
4. **Reimportar o workflow.** A versão do orçamento subiu para `v4 (2026-08-24)` e ela vai na mensagem
   de recusa justamente para isto: um n8n rodando o JSON velho recusa lotes que o código novo aceita,
   com uma mensagem que parece a mesma.

### Provar a troca sem pôr crédito

O Google tem nível gratuito da API do Gemini, e ele basta para provar a costura inteira —
credencial, corpo, leitura do PDF, schema, banco, export. Duas ressalvas que não são opcionais:

- **Só material sintético.** No nível gratuito o provedor usa o conteúdo enviado para melhorar os
  produtos dele; no pago, não. `Dados de Teste/book-canastra` (38 PDFs com gabarito) é o material certo.
- **Não é o B1.** Toda suíte deste repositório prova a ingestão sobre extração FIEL, e é por isso que
  o B1 existe. Rodar o book sintético no Gemini prova que a TROCA funciona; não prova que o sistema
  lê documento de verdade.

Antes de qualquer lote: `IA_API_KEY=... node N8N/diagnosticar-ia.mjs --modelos`. É um GET no
catálogo da conta — zero token — e responde a única coisa que nenhum teste prova: se o id do modelo
configurado existe para aquela chave.

### Voltar atrás é uma variável de ambiente

`IA_PROVEDOR=openai node N8N/build-workflow.mjs` e reimportar. A OpenAI continua inteira no catálogo
e testada — as suítes de fronteira rodam nos DOIS dialetos, e trocar a variável reexecuta a suíte
inteira contra o outro. Nenhuma linha de código muda.
