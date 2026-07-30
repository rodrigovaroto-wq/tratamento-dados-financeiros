# Custo da OpenAI — onde o dinheiro vai e como reduzir sem perder qualidade

**Data:** 2026-07-27. Pergunta do dono: *"gostaria de reduzir um pouco o custo sem comprometer a
qualidade, como fazemos isso?"*

> Âncora real medida pelo dono: o **"teste v18" (16 documentos reais) custou ~US$ 3**. As estimativas
> abaixo são coerentes com essa ordem de grandeza. Confirmar preços atuais na página de pricing da
> OpenAI antes de decidir — eles mudam.

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
- **Já preparado:** `MODEL_CLASSIFICACAO` e `MODEL_EXTRACAO` são constantes no topo de
  `n8n/build-workflow.mjs`. Trocar é **uma linha** + `node build-workflow.mjs`. Deixei as duas em
  `gpt-4o` de propósito — a decisão de qualidade é sua.
- **Como testar sem gastar:** rode o **kit de PDFs sintéticos** (9 arquivos pequenos) com a
  classificação em mini e confira se tipo/entidade/período saem certos. Custa centavos.

### 6. Saída: já otimizada, sem corte seguro sobrando
As chaves curtas já cortaram 30-40%. O que resta é **carga útil**: `vt` (valor como impresso) é a
trilha de auditoria da conversão de sinal/decimal; `cf` (confiança) alimenta o auto-aceite ≥95% e a
guarda de baixa confiança; `op` (página) é proveniência. Cortar qualquer um troca custo por qualidade
— exatamente o que você não quer.

## Falsas economias (não mexer)

- **Aumentar o intervalo de batching** não reduz custo, só a velocidade (é espaçamento, não volume).
- **Reduzir as tentativas de retry** não economiza: um 429 é rejeitado **sem cobrança** de tokens.
- **Encurtar o prompt de sistema** economiza pouco (é cacheado a ~50%) e custa qualidade de extração —
  cada instrução ali corrige um erro real observado em produção (escala, sinal, período, entidade).

## Recomendação prática

1. **Agora, sem risco:** rode o kit sintético com `MODEL_CLASSIFICACAO = 'gpt-4o-mini'` e compare.
   Se o tipo/entidade/período saírem certos, é economia direta em todo documento mal nomeado.
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
seria suficiente. `n8n/build-workflow.mjs` agora deriva o intervalo de `TPM_CONTA / MAX_OUTPUT_TOKENS`,
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

**Diagnóstico em 10 segundos:** `OPENAI_API_KEY=sk-... node n8n/diagnosticar-openai.mjs` faz uma
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

Usar a notação de período de `f0/03` no nome do arquivo elimina a segunda chamada, porque
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
