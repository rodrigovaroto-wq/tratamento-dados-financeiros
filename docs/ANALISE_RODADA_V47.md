# Análise da rodada v47 — primeira rodada real com o Gemini

**Mandato:** "Teste v47 - Grupo Canastra + Gemini API" (`caso_id 648f3251-…`)
**Execução n8n:** `7030`, 24/08/2026 20:10→20:19 UTC. **38 documentos, 0 falhas.**
**Insumo:** `test-data/book-canastra` (38 PDFs sintéticos), conferido contra o
`pdf/GABARITO.json` regerado nesta sessão.

> **Como esta análise foi feita.** Não por leitura de tela: por consulta ao banco de
> produção (`db/diagnostico_rodada.sql`, `db/pendencias_do_mandato.sql` e derivadas) e
> confronto conta a conta com o gabarito. É a regra da casa — documento não é medição.

---

## Veredito em uma linha

**A troca de provedor foi um sucesso sem ressalvas, e a rodada expôs seis defeitos que não
são do Gemini.** A extração bateu o gabarito no centavo em todos os totais conferidos, o
custo caiu 3,5× e o lote rodou em 9 minutos. Os problemas encontrados são de *classificação,
seccionamento e checagem* — quatro deles anteriores à troca, e um deles grave o bastante
para bloquear o B1.

---

## 1. O que está excelente

### 1.1 A extração acertou o gabarito, conta a conta

Conferi todos os totais materiais do book contra o `GABARITO.json`. **Nenhuma divergência.**

| Conta | Gabarito | Extraído | |
|---|---:|---:|:-:|
| Ativo Circulante Indústria 2025 | 44.022 | 44.022 | ✅ |
| Ativo Não Circulante 2025 | 93.602 | 93.602 | ✅ |
| **TOTAL DO ATIVO 2025** | **137.624** | **137.624** | ✅ |
| Total Passivo + PL 2025 | 137.624 | 137.624 | ✅ |
| Passivo Não Circulante 2025 | 29.473 | 29.473 | ✅ |
| Receita Operacional Bruta 2025 | 188.000 | 188.000 | ✅ |
| (-) Deduções da Receita Bruta 2025 | −48.128 | −48.128 | ✅ |
| Receita Operacional Líquida 2025 | 139.872 | 139.872 | ✅ |
| Dívida bancária (saldo devedor) | 52.063.000 | 52.063.000 | ✅ |
| Juros do exercício | 14.802.000 | 14.802.000 | ✅ |
| Faturamento 2023 / 2024 / 2025 | 318M / 246M / 188M | 318M / 246M / 188M | ✅ |
| Aging AR total | 28.706 | 28.706 | ✅ |
| Aging AP total | 25.734 | 25.734 | ✅ |
| Estoques total / provisão | 15.605 / −3.127 | 15.605 / −3.127 | ✅ |
| Imobilizado custo / depr. / líquido | 140.231 / −59.682 / 80.549 | 140.231 / −59.682 / 80.549 | ✅ |
| DFC caixa inicial / final | 3.621 / 825 | 3.621 / 825 | ✅ |

O balanço **fecha** (Ativo = Passivo + PL, nos três exercícios) e o DFC **amarra**
(3.082 + 304 − 6.182 = −2.796; 3.621 − 2.796 = 825). Os comparativos de 3 colunas
saíram com as 3 colunas, e os dois documentos COMBINADOS saíram com as 8 entidades
lado a lado — o achatamento de comparativo, que era risco, não aconteceu.

### 1.2 Volume de extração: 2,2× a melhor rodada anterior

| Rodada | Provedor | Linhas extraídas |
|---|---|---:|
| v41 (13/08) | OpenAI | 1.139 |
| v45 (14/08) | OpenAI | 438 |
| **v47 (24/08)** | **Gemini** | **2.460** |

2.460 pares (conta × coluna) sobre 1.081 contas distintas, em 34 dos 38 documentos.
Os 4 sem valor numérico são os que não têm número mesmo (certidões, organograma,
notas explicativas, parecer do auditor) — correto.

### 1.3 O custo caiu 3,5× e bateu a estimativa

| | Valor |
|---|---:|
| `custo_total_usd` | **US$ 0,3680** |
| `custo_estimado_usd` (previsto antes de rodar) | US$ 0,3200 |
| extração | US$ 0,3566 |
| classificação | US$ 0,0114 |
| tokens entrada / saída | 214.469 / 116.905 |
| duração do lote | ~9 min (20:10 → 20:19) |

A estimativa errou **15% para menos** — aceitável, e o erro é do lado seguro para o dono
(quem estima gasto por baixo assusta; aqui a diferença é de 5 centavos). Confere com a
tabela de preço do `n8n/lib/custo.mjs` (`0,30`/`2,50` por milhão) no sexto decimal:
`214.469 × 0,30 + 116.905 × 2,50 = 0,356603` → `0,356600` gravado. **A conta de custo
está certa.**

Comparado ao piso projetado no `docs/PROMPT_ANALISE_DA_RODADA.md` (US$ 0,2821, calculado
antes da correção do #169), o real ficou 30% acima — que é exatamente o que o #169 previu:
**o token de raciocínio apareceu na conta.** A correção estava certa.

### 1.4 As guardas que funcionaram

- **Zero falhas** em 38 documentos (`documentos_com_falha = 0`, `documentos_sem_medicao = 0`);
- as 7 pendências bloqueantes de `item_sem_conteudo` abriram e **fecharam sozinhas** quando
  o conteúdo chegou — o ciclo de vida da pendência funciona;
- o detector de padrão suspeito **disparou** (ver 2.4 — disparou errado, mas disparou);
- a `0138` **está aplicada** em produção: conferi o corpo de `fn_veredito_producao` e o
  `RAISE EXCEPTION` não está mais lá. O `ESTADO.md`, que registrava o banco na `0137`,
  estava desatualizado.

---

## 2. O que precisa ser corrigido

Em ordem de gravidade.

### 2.1 🔴 Nenhuma reconciliação rodou — e faz três rodadas que é assim

**Zero linhas em `reconciliacao` para o v47.** O mandato chegou a `completude_ok` sem que
uma única checagem de amarração fosse computada.

| Mandato | Data | Reconciliações |
|---|---|---:|
| Teste v41 | 13/08 19:28 | **73** |
| Teste v4x | 13/08 21:35 | 0 |
| Teste V45 | 14/08 | 0 |
| **Teste v47** | **24/08** | **0** |

**Isto não é do Gemini** — quebrou em 13/08, entre 19:40 e 20:57, onze dias antes da troca
de provedor. As checagens que existem justamente para pegar "Ativo ≠ Passivo + PL" não
estão sendo executadas, e o mandato **aprova mesmo assim**: a v45 chegou a `aprovado` com
zero reconciliações.

#### A causa raiz, medida na execução `7030`

O nó `Reconciliar (Classe A)` **está no canvas e rodou**. Devolveu isto:

```json
{"resultado": {"motivo": "documento não encontrado", "executado": false}}
```

**O nó Postgres do n8n substitui o item pelo resultado da query.** O
`Gravar Campos (Sombra)` devolvia só `{n_campos: 65}`, e os **dois** nós seguintes leem
`$json.documento_id`:

| Nó | Lê | Recebia | Resultado |
|---|---|---|---|
| `Registrar Diagnostico` | `$json.documento_id` | `undefined` | "documento não encontrado" |
| `Reconciliar (Classe A)` | `$json.documento_id` | `undefined` | "documento não encontrado" |

As funções eram chamadas com NULL, respondiam com um retorno **válido**, e o nó ficava
**verde**. Zero linha gravada, nenhuma tela dizendo que as checagens não rodaram.

**São dois nós quebrados, não um.** O diagnóstico (preenchimento de entidade, confirmação
de tipo e de legibilidade) também nunca rodou nesta rodada — o que está no banco veio do
`fn_registrar_documento`, lá atrás na classificação, não daqui.

É a classe exata do commit `9b9cd72` — *"O fan-out cortou o pareamento de itens, e três nós
perderam o contexto"* (13/08 21:08) —, e a janela da quebra (13/08, entre a v41 e a v42)
bate com `4b96406` *"Três camadas para o dado que não chegava"* (13/08 20:17).

**O motor está intacto.** Chamando `fn_reconciliar_por_documento` à mão sobre o
`01_Balanco_Patrimonial` da v47 (em transação revertida), ela executa as **6 checagens** e
ainda acha **dois defeitos reais** que a rodada engoliu:

| Checagem | Resultado |
|---|---|
| `secao_fecha` (a `0133`) | **divergente** |
| `ativo_passivo_pl` | ok |
| `caixa_bp_fluxo` | ok |
| `mutuos_planilha_vs_balanco` | documento_ausente |
| `intragrupo_espelho` | ok |
| `duplicidade_de_rotulo` | **divergência** |

Ou seja: não é preciso escrever nenhuma checagem nova. **É preciso religar um fio** — e a
rodada passa a acusar dois defeitos que hoje não aparecem em lugar nenhum.

O agravante continua: o book é fiel, o balanço fecha, e nada denunciaria a ausência. Num
documento real que não fechasse, o sistema aprovaria calado. **É a mesma forma da `0133`:
a cegueira foi aberta por uma mudança nossa e nenhuma tela mostra que ela existe.**

**CORRIGIDO (24/08).** `Gravar Campos (Sombra)` passa a devolver `documento_id`,
`documento_versao_id` e `diagnostico` como **colunas da própria query**, e
`Registrar Diagnostico` devolve `documento_id`. Colunas, e não `$('nó').item`: pareamento
por item já quebrou aqui uma vez (o fan-out do fatiamento), e a doutrina desde então é que
o item carrega o próprio contexto.

A trava está em `n8n/test/workflow-sim.test.mjs` e é genérica: qualquer nó que leia
`$json.X` do item de um nó Postgres anterior exige que aquele nó devolva `X` como coluna.
Conferida contra a query antiga — ela **reprova**.

### 2.2 🔴 Escala `milhao` em documento que diz "R$ mil" — erro de 1.000×

Dois documentos gravaram `unidade = 'milhao'` em **todas** as linhas, e em ambos o
cabeçalho da coluna diz literalmente **"R$ mil"**:

| Documento | Linhas | Colunas cujo rótulo diz "mil" | `unidade` gravada |
|---|---:|---:|---|
| `24_Posicao_de_Estoques` | 50 | 17 | `milhao` |
| `28_Folha_de_Pagamento` | 34 | 25 | `milhao` |

Os **valores** estão certos (TOTAL DOS ESTOQUES = 15.605, igual ao gabarito). É o
**multiplicador** que está errado: quem ler `15.605 × 10⁶` em vez de `15.605 × 10³`
inflaciona o estoque em mil vezes. É exatamente o erro que o comentário do
`db/diagnostico_rodada.sql` diz que este projeto já pagou caro.

**Agravante — a escala era do documento, não da coluna.** No mesmo `24_`, colunas
não-monetárias herdaram a escala e a moeda: `Quantidade = 1.240` e
`Custo unitário (R$) = 2.026,61` estavam gravados como `milhao`/`BRL`. Em `28_`,
`Efetivo (pessoas) = 96` idem. **279 pessoas virariam 279 milhões de pessoas** se alguém
multiplicasse.

**CORRIGIDO (24/08).** A escala passa a ser **por coluna**, que é o que a análise concluiu
ser a correção certa. Duas regras novas em `n8n/lib/extract.mjs`:

- `ehLinhaNaoMonetaria` ganha um terceiro parâmetro, a **coluna**. A regra antiga olhava só
  o rótulo da LINHA — e num documento tabular o rótulo é o mesmo nas quatro colunas, então
  ela não tinha como distinguir. Agora `Quantidade`, `Efetivo (pessoas)`, `Exercício` e
  `Custo unitário` bloqueiam a herança de escala e moeda;
- `escalaDeclaradaNaColuna` — quando a coluna declara a escala de forma inequívoca
  (`Valor (R$ mil)`), **ela manda** sobre a do documento, porque é mais específica e é onde
  a escala costuma estar escrita. Sem declaração explícita devolve `null` e nada muda:
  adivinhar aqui trocaria um erro de 1.000× por outro.

Efeito medido sobre as linhas reais da v47:

| Linha | Coluna | Antes | Depois |
|---|---|---|---|
| Bobina kraft 180 g/m² | `Valor (R$ mil)` | `milhao` | **`milhar`** |
| Bobina kraft 180 g/m² | `Quantidade` | `milhao` | **`null`** |
| Bobina kraft 180 g/m² | `Custo unitário (R$)` | `milhao` | **`null`** |
| TOTAL DOS ESTOQUES | `Valor (R$ mil)` | `milhao` | **`milhar`** |
| Produção - turno A | `Efetivo (pessoas)` | `milhao` | **`null`** |
| Produção - turno A | `Custo anual com encargos (R$ mil)` | `milhao` | **`milhar`** |

**E morreu uma cópia à mão junto.** O `naoMonet` do `build-workflow.mjs` era transcrição
manual da função da lib — e o nó Code é o que RODA. Corrigir a lib e esquecer a cópia
deixaria a suíte verde e a produção errada, que é como este repositório descreve seus dois
piores incidentes. As duas agora saem do mesmo `toString()`, e o `espelho-inline.test.mjs`
confere — ele **reprovou** quando registrei as funções sem incluí-las na tabela.

Há ainda 14 linhas com valor numérico e escala/moeda **nulas** (docs 08, 22, 23, 27) —
o outro lado do mesmo problema.

### 2.3 🟠 A confiança por linha está saturada em 1,00 — o sinal morreu

**2.460 de 2.460 linhas com `confianca = 1.00` exatamente.** Não é média: é a distribuição
inteira. O mesmo vale para a v41 (1.139/1.139) e a v45 (438/438), então **também não é do
Gemini** — é anterior.

Isso importa porque `fn_dial_permite_auto(estagio, confianca)` decide auto-aceite comparando
a confiança ao limiar do dial. Com a confiança constante em 1,00, **o limiar nunca reprova
nada**: o dial parece configurado e não filtra. É um portão de segurança desligado sem que
nenhuma tela diga isso.

Contraste: a confiança de **classificação** varia (0,90 / 0,95 / 1,00) e discrimina. É só a
de extração que está morta.

### 2.4 🟠 O detector de padrão suspeito acusou uma coluna de dimensão

Pendência aberta em `19_Faturamento_Intragrupo`:

> "4 contas diferentes, na MESMA coluna, vieram com o MESMO valor material (2023.00) —
> padrão típico de fabricação/alucinação"

**É falso positivo.** A coluna é `Exercício`, e o valor repetido é o **ano**, legitimamente
igual nas 4 linhas de 2023. Os valores monetários dessas linhas estão certos e somam certo
(1.900 + 3.400 + 720 + 1.100 = 7.120 = "Total de 2023" ✅).

**CORRIGIDO E APLICADO EM PRODUÇÃO (24/08)** — migration `0140`. Nasce
`fn_coluna_de_dimensao`, e `fn_contas_repetindo_valor` passa a ignorar colunas que rotulam
a linha em vez de medi-la.

**Medido contra as 38 versões da v47 ANTES de aplicar**, em transação revertida: o único
documento que muda de estado é o 19 (de 4 contas repetindo 2023 para 2 repetindo 1.900,
abaixo do limiar). O maior `n_contas` do lote passa a ser 3, contra um limiar de 4 — a
guarda **continua com folga, não foi silenciada**. É a diferença entre corrigir um falso
positivo e desligar a guarda, e ela tinha de ser medida, não presumida.

### 2.5 🟠 Documento COMBINADO classificado como BALANCO → entidade fantasma → 3 pendências falsas

Dois documentos gêmeos, saída oposta — **ambos com confiança 1,00**:

| Arquivo | Tipo | Confiança |
|---|---|---:|
| `13_Balanco_COMBINADO_Grupo_Canastra_2025.pdf` | **BALANCO** ❌ | 1,00 |
| `14_Balanco_COMBINADO_Grupo_Canastra_2024.pdf` | COMBINADO ✅ | 1,00 |

A justificativa do 13 descreve corretamente "um Balanço Patrimonial **Combinado**" e mesmo
assim carimba `BALANCO`. **Confiança 1,00 numa resposta errada** — reforça 2.3.

O estrago é em cadeia. A tabela `entidade` tem **7 linhas para um grupo de 6 empresas**: a
sétima é `Grupo Canastra`, sem CNPJ, criada pelo documento misclassificado. E como o
sistema passou a exigir de "Grupo Canastra" as linhas de um balanço de empresa, abriram-se
**3 das 11 pendências** do mandato (Ativo Total, Passivo + PL e Caixa e equivalentes "não
localizadas" para essa entidade que não existe). Uma classificação errada gerou três
pedidos de trabalho humano que não têm o que resolver.

**Segundo problema na mesma tabela:** os nomes não são normalizados —
`CANASTRA INDÚSTRIA DE EMBALAGENS LTDA.` convive com `Cn Transportes` e
`Canastra Imobiliaria SPE`. Dois documentos que grafem a mesma empresa de formas
diferentes viram duas entidades.

### 2.6 🟠 Os totais não recebem seção canônica — e é o que gera as pendências de "linha exigida ausente"

Achado sistemático: **linha de total/subtotal fica com `secao_canonica = null`.**

Nos documentos que têm seção (BALANCO, DRE, COMBINADO, BALANCETE, DF_AUDITADA): 1.607
linhas, **368 sem seção**. Dessas, **147 são linhas em CAIXA ALTA** — ou seja, **87% das
linhas em caixa alta (147 de 169) ficam sem seção**, contra praticamente todas as linhas
de detalhe seccionadas corretamente.

Confirmado no dado: `TOTAL DO ATIVO`, `TOTAL DO PASSIVO E DO PATRIMÔNIO LÍQUIDO`,
`RECEITA OPERACIONAL BRUTA`, `(-) DEDUÇÕES DA RECEITA BRUTA`, `RECEITA OPERACIONAL LÍQUIDA`
— todas extraídas com o valor certo, todas sem seção.

É a **causa raiz** de boa parte das 11 pendências de `linha_exigida_ausente`: a linha *está*
no banco com o valor correto, mas o localizador não a encontra porque procura por seção.
Essas linhas também caem em "Contas Não Classificadas" no export.

### 2.7 🟡 O balancete de 2025 perdeu todas as seções; o de 2024 não

Mesmo gerador, mesmo layout, anos diferentes:

| Documento | Linhas | Com seção |
|---|---:|---:|
| `15_Balancete_Analitico_…_12M25` | 155 | **0** |
| `16_Balancete_Analitico_…_12M24` | 145 | 144 |

O 16 distribuiu certinho (46 PC, 42 AC, 36 ANC, 14 PNC, 6 PL). O 15 mandou **as 155 linhas
para "sem seção"**. Não há diferença estrutural entre os dois documentos que justifique —
é **não-determinismo do seccionamento**, e é o maior bloco isolado de linhas perdidas do
lote.

### 2.8 🟡 `tipo_taxonomia` nulo gravado com confiança 0,90

`28_Folha_de_Pagamento` ficou com **tipo nulo**. A justificativa do modelo é honesta e
correta — *"tipo não contemplado nas categorias financeiras padrão da taxonomia"* — e a
pendência de `classificacao_pendente` abriu como devia. O defeito é o **número**: gravar
`confianca = 0.90` para uma resposta que é "não sei" é registrar como quase-certeza aquilo
que o próprio modelo declarou fora da taxonomia. Deveria ser confiança baixa, ou nula.

Sugestão de produto: a folha de pagamento é insumo real de análise de crédito (headcount,
custo com encargos). Vale um tipo `FOLHA_PAGAMENTO` na taxonomia.

### 2.9 🟡 Os contadores de token não incluem a classificação, mas o custo inclui

`tokens_entrada`/`tokens_saida` (214.469/116.905) explicam **exatamente** o
`custo_extracao_usd`, e só ele. Os tokens das 19 chamadas de classificação (US$ 0,0114)
não estão em lugar nenhum. Na mesma linha da tabela, "tokens" e "custo" são universos
diferentes — quem dividir custo por token vai errar.

Além disso, `cobertura` está **nula** porque `contas_nos_documentos = 0` (denominador
zerado), então o oitavo indicador do painel não tem o que mostrar. E `tokens_cache = 0`:
nenhum cache foi aproveitado em 38 chamadas.

---

## 3. As duas perguntas que a rodada existia para responder

### 3.1 Quantas chamadas o lote fez — 38 ou ~44?

**38. `documentos_fatiados = 0`.**

**O fatiamento continua nunca tendo sido visto ligado em produção** — 0 de 38 na sessão 52,
0 de 38 agora. Segue sendo o item nº 1 das onze provas do B1, e **não foi provado**.

O motivo é mensurável: a saída média foi **116.905 / 2.460 ≈ 47,5 tokens por linha**
(raciocínio incluído). Nenhum documento chegou perto do teto de 16.384.

**Mas a margem é menor do que parece.** O documento mais denso do lote é o
`01_Balanco_Patrimonial` com **308 pares**; a 47,5 tokens/linha isso projeta **~14.600
tokens de saída — 89% do teto de 16.384**, sem fatiar. Um balanço um pouco maior trunca.

> O próprio nó `Resumo de Custo` da execução `7030` publica `tokens_saida_por_linha: 47.5`
> — a média confere. Ressalva honesta: é a média do lote, não a medição do documento 01.
> A medição por documento **não é persistida** (só existe na saída do nó `Parse Extracao`,
> item a item). A projeção indica risco, não o comprova.

### 3.2 `thoughts_tokens` e `custo_usd` do `17_Livro_Razao`

**RESPONDIDA** — o dono enviou a saída do `Parse Extracao`, item a item, dos 38 documentos.

| Documento | Saída (tokens) | % do teto de 16.384 | Pares | Custo |
|---|---:|---:|---:|---:|
| `35_Demonstracoes_Contabeis` | **13.534** | **82,6%** | 285 | US$ 0,0361 |
| `01_Balanco_Patrimonial` | 10.895 | 66,5% | 308 | US$ 0,0292 |
| `17_Livro_Razao` | 10.007 | 61,1% | 198 | US$ 0,0270 |
| `15_Balancete_12M25` | 5.838 | 35,6% | 155 | US$ 0,0164 |
| soma do lote | 116.905 | — | 2.460 | US$ 0,3566 |

**E o estimador do repositório está descalibrado para o Gemini.** O
`n8n/medir-custo-book.mjs` — que roda no CI e é de onde saiu a premissa dos 17.875 —
prevê, para este mesmo book:

| | Estimado | Real | |
|---|---:|---:|---|
| saída do documento mais pesado | 17.875 (`17_Livro_Razao`) | 10.007 | **1,8× a mais** |
| documentos fatiados | 4 | **0** | |
| chamadas de extração | 44 | 38 | |

Ele erra o alvo (aponta o `17`, o real é o `35`), erra a magnitude em 1,8× e por isso
prevê fatiamento onde não há. Não é defeito novo — é o modelo de tokens de saída, herdado
do gpt-4o, aplicado a um modelo que agrupa a saída de outro jeito. **É a origem da premissa
errada que a decisão 4.1 quase seguiu**, e enquanto não for recalibrado o CI vai continuar
afirmando "109% do teto" para um documento que usa 61%.

**Duas coisas que a projeção tinha errado**, e vale registrar as duas:

1. **o documento mais caro não é o mais numeroso.** O `35` tem *menos* pares que o `01`
   (285 contra 308) e gasta *mais* saída (13.534 contra 10.895) — ele tem 13 seções
   canônicas, então cada linha carrega mais estrutura. Densidade não é contagem de linhas;
2. **o pior caso real é 82,6% do teto, não os ~89% projetados** — e não no documento que
   eu apontei. A projeção acertou a ordem de grandeza e o alerta; errou o alvo.

`thoughts_tokens` **não aparece separado**: o `Parse Extracao` já soma o raciocínio dentro
de `tokens.saida`, que é exatamente o que o #169 mandou fazer (é cobrado como saída). A
correção está funcionando — e o efeito colateral é que **não dá para separar raciocínio de
JSON** neste dado. Para a decisão 4.2 isso não muda nada (a recomendação já é manter), mas
significa que "quanto custa o pensamento" segue sem medição direta.

**A lacuna de instrumentação continua:** este detalhe só existe na saída item-a-item da
execução do n8n e **não é persistido em lugar nenhum** — some no expurgo. A decisão do teto
de saída depende de um número que o sistema não guarda.

O que dá para dizer do agregado: o raciocínio **está** sendo cobrado e **está** na conta
(o real ficou 30% acima do piso pré-#169, e a diferença é exatamente essa). O
`17_Livro_Razao` rendeu 198 pares — é o 4º mais denso, não o 1º; para a decisão do teto,
**o documento a medir é o `01_Balanco_Patrimonial` (308 pares)**, não o razão.

---

## 4. As três decisões, agora com a medição na mão

### 4.1 Subir `MAX_OUTPUT_TOKENS` de 16.384? — **Não agora. E não pelo motivo previsto.**

A premissa registrada ("o documento mais denso já pede 17.875 tokens de saída") **não se
confirmou**: o lote inteiro consumiu 116.905 tokens de saída, e a projeção do pior
documento é ~14.600. **Medir desmentiu a correção anotada** — de novo.

Com o teto atual sobrando ~11%, subi-lo agora só faria uma coisa: **enterrar de vez a única
chance de ver o fatiamento disparar numa rodada real**. E o fatiamento é prova obrigatória
do B1.

**Recomendação, agora com a medição na mão: manter 16.384.** O pior caso real do lote é o
`35_Demonstracoes_Contabeis` com 13.534 tokens — **82,6% do teto**, folga de 17%. É apertado
o bastante para vigiar e largo o bastante para não mexer agora, e subir o teto enterraria a
única chance de ver o fatiamento disparar.

O passo certo não é subir o teto: é **testar o fatiamento com um documento propositalmente
maior**, que é a prova que falta desde a sessão 52. Se um dia mexer, `TETO_SAIDA_TOKENS` em
`n8n/lib/cobertura.mjs` acompanha (há teste travando os dois).

### 4.2 Desligar o pensamento na extração? — **Não.**

O raciocínio custou ~30% do lote — cerca de **US$ 0,11 num lote de US$ 0,37**. Em troca
dele, a extração acertou o gabarito no centavo em 16 de 16 totais conferidos, com 2,2× o
volume da melhor rodada anterior. **Onze centavos por 38 documentos é o melhor negócio
desta rodada.**

Somado ao risco não verificado já anotado (se o modelo recusar `thinkingConfig`, toda
chamada vira 400), não há caso para desligar. **Decisão: manter, e tirar do backlog.**

### 4.3 Estender o `eslint` ao diretório `n8n/`? — **Sim, e continua valendo.**

Nada nesta rodada muda a avaliação: hoje o lint roda com `working-directory: portal` e os
geradores do n8n só são vistos pelo Sonar (foi assim que um import morto viveu dois
commits). É fatia própria e provavelmente acende achados antigos.

---

## 5. Ordem de trabalho sugerida

| # | Item | Seção | Por quê primeiro |
|---|---|---|---|
| ✅ | Reconciliação + diagnóstico desligados do insumo | 2.1 | **Corrigido**; falta PUBLICAR a versão do n8n |
| ✅ | Falso positivo da guarda de padrão suspeito | 2.4 | **Corrigido e aplicado** (`0140`) |
| 1 | Escala por coluna (o erro de 1.000×) | 2.2 | Erro de mil vezes; é o mais grave em aberto |
| 2 | Confiança de extração saturada em 1,00 | 2.3 | Desliga o filtro do dial sem avisar ninguém |
| 3 | Seção canônica nos totais | 2.6 | Causa de boa parte das 11 pendências de linha ausente |
| 4 | COMBINADO → BALANCO e entidade fantasma | 2.5 | 3 pendências falsas; normalizar nome de entidade junto |
| 5 | Balancete 2025 sem seção | 2.7 | 155 linhas, o maior bloco perdido |
| 6 | Tipo nulo com confiança 0,90 / tipo `FOLHA_PAGAMENTO` | 2.8 | Barato |
| 7 | Persistir tokens por documento | 3.2 | A decisão do teto depende de um número que some |
| 8 | Contadores de token vs. custo; `cobertura` nula | 2.9 | Relatório, não motor |
| 9 | `eslint` no `n8n/` | 4.3 | Fatia própria |

**Do dono, e só dele:** o teto de gasto do projeto no Google (não se herda da OpenAI — a
conta nova começa **sem teto**) e o zero-retention/DPA antes de qualquer dado real de
cliente. E a medição do `01_Balanco_Patrimonial` no `Parse Extracao`, que é o único número
desta análise que o banco não deu.

---

## 6. Correção ao `ESTADO.md`

O `ESTADO.md` registra o banco de produção na `0137`. **Medido nesta sessão:**
`fn_veredito_producao` já não contém `RAISE EXCEPTION` — a **`0138` está aplicada**. A
sonda `fn_instalacao_conferir()` respondeu **14 requisitos, todos presentes**, sem nenhum
bloqueante ausente.
