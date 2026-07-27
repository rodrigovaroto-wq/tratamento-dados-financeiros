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
