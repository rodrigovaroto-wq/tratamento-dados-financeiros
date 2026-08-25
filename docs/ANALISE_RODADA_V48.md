# Análise da rodada v48 — a primeira com a reconciliação religada

**Mandato:** "teste v48" (`caso_id ef3e0e11-…`). **Execução n8n:** `7037`, 24/08 22:51→23:01.
**Insumo:** os MESMOS 38 PDFs da v47, de propósito — o que muda entre as duas é só o
sistema, então toda diferença é atribuível.

> Medido por consulta ao banco de produção e ao histórico do n8n, não por leitura de tela.

---

## O veredito

**A correção do fio funcionou, e funcionou grande.** A v47 gravou ZERO reconciliações; a
v48 gravou **88**. O estágio de diagnóstico, que também estava morto, voltou junto. E a
rodada provou a tese que este repositório repete: **estágio parado não gera achado — assim
que voltou, gerou.** Só que dois terços dos primeiros achados dele eram falsos, e é isso
que esta análise trata.

| | v47 | v48 |
|---|---:|---:|
| Reconciliações | **0** | **88** |
| Pendências abertas | 11 | 27 |
| Linhas extraídas | 2.460 | 2.485 |
| Documentos fatiados | 0 | **0** |
| Custo | US$ 0,3680 | US$ 0,3732 |
| Falhas | 0 | 0 |

O salto de 11 para 27 pendências **não é regressão**: é o sistema voltando a olhar. Das 16
novas, 12 vêm de reconciliação e 4 do diagnóstico.

---

## 1. 🔴 O maior achado: a checagem de seção acusa o DOBRO, e 100% é falso

`secao_fecha` abriu **7 divergências** e 12 pendências. Todas erradas, e o número denuncia:

| Seção | Informa | Filhos somam | Razão |
|---|---:|---:|---:|
| Passivo Circulante [2025] | 112.372 | 224.744 | **2,0000** |
| Ativo Não Circulante [2024] | 95.838 | 191.676 | **2,0000** |
| Ativo Circulante [2023] | 91.594 | 183.188 | **2,0000** |
| Patrimônio Líquido [2023] | 80.533 | 161.066 | **2,0000** |
| …e mais 11 | | | **2,0000** |

**Razão exatamente 2,0000 em todas as 15 linhas conferidas.**

### A causa, e ela NÃO é a checagem

O balanço tem **três níveis**: total da seção → subtotais de grupo → folhas. Medido no
`01_Balanco`, coluna 31/12/2025:

```
Ativo Circulante  44.022        ← total da seção
  Disponível          825       ← subtotal de grupo
    Caixa             606
    Aplicações        181       606 + 181 + 38 = 825 ✓
    Numerário          38
  Contas a Receber 12.795       ← subtotal de grupo
    … 4 folhas                  24.861 + 3.845 − 9.644 − 6.267 = 12.795 ✓
  Estoques         15.605       ← subtotal de grupo
  …
825 + 12.795 + 15.605 + 7.581 + 7.216 = 44.022 ✓
```

Mas **`ce.secao` vem achatada**: TODAS as linhas — subtotais e folhas — carregam
`secao = 'Ativo Circulante'`. E `fn_papel_linha('Disponível')` devolve `conta`, não
`subtotal`. Então a checagem soma os dois níveis: `44.022 + 44.022 = 88.044`.

**A extração perdeu a hierarquia; a checagem está fazendo exatamente o que deveria com uma
árvore achatada.**

### Por que isso não foi pego antes

O `db/test/secao_fecha.test.sql` passa — o fixture do `book-vertentes` tem **dois** níveis,
não três. O defeito só aparece em documento com subtotal intermediário, que é o caso real.
E a v47 não o mostrou porque a reconciliação não rodava.

### O que eu tentei e NÃO vou entregar

Prototipei um reconstrutor de hierarquia por `ordem` + aritmética (uma linha é subtotal
quando as seguintes somam exatamente ela). Contra o `01_Balanco` ele resolveu **3 de 15**
seções — as três de `Ativo Circulante`, com diferença zero — e **não resolveu** o resto:
`Patrimônio Líquido [2024]` continuou em 2,0000, sem consumo nenhum, provavelmente porque
ali o subtotal vem DEPOIS dos filhos.

**Meio-conserto é pior que nenhum:** trocaria um falso positivo sistemático e reconhecível
(razão 2,0000 sempre) por um inconsistente. Não entra.

### A correção certa

É na **extração**: `secao` deve trazer o grupo IMEDIATO, não a seção. `Caixa` pertence a
`Disponível`, não a `Ativo Circulante`. Isso é mudança de prompt e de esquema, precisa de
rodada própria para medir, e é a próxima fatia.

**Enquanto isso, o piso honesto** — e é pequeno — é a checagem reconhecer a assinatura
(soma ≈ 2× o pai em TODAS as seções do documento) e declarar
`precondicao_nao_satisfeita: hierarquia_achatada` em vez de acusar. Recusar-se a acusar
quando não dá para conferir é a doutrina desta casa.

### E o achatamento produz DUAS famílias de falso positivo, não uma

Cruzando o HTML do portal com o banco, a checagem de **duplicidade de rótulo** é vítima do
mesmo defeito. Os "pares que podem ser a mesma conta" são, na verdade, **subtotal e seu
único filho** — que têm o mesmo valor por construção:

| Par acusado | O que realmente é | Medido no doc 12 |
|---|---|---|
| `Caixa` = `Disponível` (241) | `Disponível` é o grupo, `Caixa` o único filho | ordem 2 e 3, mesma `secao` |
| `Empréstimos` = `Financiamento imobiliário - longo prazo` (7.726) | idem | ordem 20 e 21 |
| `Lucros acumulados` = `Lucros ou Prejuízos Acumulados` | idem | recorrente em 6 documentos |

Não são rótulos duplicados. **São pai e filho, e só parecem duplicados porque a hierarquia
foi achatada.** Uma causa, duas famílias de pendência falsa.

### 🔴 E um defeito próprio: a pendência aponta para o arquivo ERRADO

A pendência que lista `Capital Social`, `Lucros ou Prejuízos Acumulados` e
`Capital social subscrito e integralizado` está anexada ao
**`20_Mapa_de_Divida_Canastra_Industria_2025.pdf`** — confirmado no banco,
`tipo_taxonomia = MAPA_DIVIDA`.

**Um mapa de dívida não tem Capital Social.** A checagem `fn_reconciliar_duplicidade` é por
(caso, entidade), não por documento, e a pendência cai no documento que por acaso a
disparou. O analista abre o arquivo indicado, procura a conta e ela não está lá — o pior
tipo de pendência, porque queima confiança na fila inteira.

**Correção:** pendência de checagem por entidade não deve carregar `documento_id`; deve
declarar-se como "vale para a entidade", que é o formato que o portal já sabe renderizar
("Vale para o caso, não para um arquivo específico").

---

## 1.b A conta que fecha a rodada: 17 das 27 pendências são falsas

| Origem | Qtd | Veredito |
|---|---:|---|
| `secao_fecha` (razão 2,0000) | 6 | ❌ achatamento |
| `duplicidade_de_rotulo` (pai ≡ filho) | 6 | ❌ achatamento |
| `linha_exigida` da entidade fantasma `GRUPO CANASTRA` | 3 | ❌ misclassificação |
| `tipo_incorreto` sem divergência | 2 | ❌ corrigido pela `0142` |
| **Subtotal de falso positivo** | **17** | **63% da fila** |
| `linha_exigida` legítimas | 6 | ✅ |
| `tipo_incorreto` real (doc 14) | 1 | ✅ |
| demais | 3 | ✅ |

**Doze das dezessete saem de UMA causa: a `secao` achatada.**

---

## 1.c A extração está certa — as checagens é que não

Conferi os totais materiais da v48 contra o `GABARITO.json`. **Nenhuma divergência:**

| Conta | Gabarito | v48 |
|---|---:|---:|
| TOTAL DO ATIVO 2025 | 137.624 | 137.624 ✅ |
| Passivo + PL 2025 | 137.624 | 137.624 ✅ |
| Ativo Circulante / Não Circulante | 44.022 / 93.602 | 44.022 / 93.602 ✅ |
| Receita Bruta / Líquida 2025 | 188.000 / 139.872 | 188.000 / 139.872 ✅ |
| DFC caixa inicial / final | 3.621 / 825 | 3.621 / 825 ✅ |
| Dívida / juros | 52.063.000 / 14.802.000 | idem ✅ |
| Aging AR | 28.706 | 28.706 ✅ |
| Estoques | 15.605 | 15.605 ✅ |
| Imobilizado custo/depr./líquido | 140.231 / −59.682 / 80.549 | idem ✅ |

**Esta é a conclusão que mais importa da comparação com o portal:** o sistema está lendo os
documentos corretamente e **apontando as questões erradas**. O dado entregue é bom; a fila
de revisão é que está poluída — e por uma causa só.

---

## 2. ✅ CORRIGIDO: `tipo_incorreto` acusava sem ter divergência

Dos 3 achados de tipo do diagnóstico, **2 eram falsos**:

| Documento | Sugerido | Registrado | Veredito |
|---|---|---|---|
| `14_Balanco_COMBINADO` | COMBINADO | BALANCO | ✅ achado real |
| `27_Composicao_do_Imobilizado` | NOTAS_EXPL | **NOTAS_EXPL** | ❌ mesmo tipo dos dois lados |
| `28_Folha_de_Pagamento` | `?` | `(nenhum)` | ❌ nada contra nada |

A condição disparava por `tipo_confirma = false` **sozinha**, e o modelo diz "não confirmo"
também quando reconhece o mesmo tipo com outro nome ou quando não sabe o que o documento é.
Nos dois casos não há nada que um humano possa fazer.

**Migration `0142`, aplicada em produção.** Medida antes de aplicar contra as três
pendências reais: mantém o achado verdadeiro e derruba os dois falsos. E o doc 28 já tinha
`classificacao_pendente` aberta em paralelo — duas pendências para o mesmo fato.

---

## 3. O COMBINADO é cara ou coroa — e isso decide o desenho

| Rodada | doc 13 (2025) | doc 14 (2024) |
|---|---|---|
| v47 | **BALANCO** ❌ | COMBINADO ✅ |
| v48 | COMBINADO ✅ | **BALANCO** ❌ |

**O erro trocou de documento.** Mesmos arquivos, mesmo modelo, ambos com **confiança 1,00**
nas duas rodadas. Não é um documento difícil: é uma moeda.

Isso confirma a decisão de desenho que eu já havia tomado — **decidir por estrutura, não
por rótulo**. Os dois documentos trazem **8 `entidade_coluna` distintas**; um balanço
individual tem uma. A evidência está no banco e custa zero token.

A boa notícia: **o diagnóstico já acusa sozinho** agora que voltou a rodar. A estrutural
transforma "acerta em metade das rodadas" em "acerta sempre".

---

## 4. ✅ Resolvido sozinho: o balancete de 2025

| | v47 | v48 |
|---|---:|---:|
| `15_Balancete` linhas sem seção | **155 de 155** | **2 de 156** |

Era **não-determinismo do modelo**, não defeito sistemático. **Não vou corrigir o que se
corrigiu sozinho** — mas fica registrado que a mesma extração pode produzir 0 ou 5 seções
no mesmo documento, o que é o mesmo fenômeno do item 3.

---

## 5. Confirmados sem mudança

| Achado | Estado na v48 |
|---|---|
| **Seção canônica nos totais** | 142 de 172 linhas em caixa alta sem seção (v47: 147/169) — **continua** |
| **Confiança saturada** | único valor observado: **1** — e **2.485 de 2.485 linhas auto-aceitas (100%)** |
| **Escala `milhao`** nos docs 24 e 28 | **continua** — a correção existe no `main` mas **não foi publicada no n8n** |
| **Entidade fantasma** `GRUPO CANASTRA` | **continua**, 7 entidades para 6 empresas, com 8 documentos |
| **Fatiamento** | **0 de 38 pela terceira vez** |

A linha das auto-aceitas é a confirmação mais limpa da `0141`: **100%**. O limiar não
excluiu uma linha sequer, agora com a trilha declarando isso.

---

## 6. Modelagem: não existe para esta rodada

`caso_modelagem = 0`, `caso_premissa = 0`. **É o esperado, não defeito:** a modelagem é
configurada na tela, não pela ingestão. Vale o registro de que os únicos quatro mandatos
com modelagem no banco (v35, v41, v4x, V45) têm todos `atualizado_por = 'roteiro:sql'` —
**nenhuma modelagem no banco foi montada pelo portal até hoje.**

---

## 7. Custo e desempenho

| | v47 | v48 |
|---|---:|---:|
| Custo real | US$ 0,3680 | US$ 0,3732 |
| Estimado | US$ 0,3200 | US$ 0,3200 |
| Tokens de saída | 116.905 | 118.990 |
| Duração | 9 min | 10 min |

Estável dentro de 1,4%. O estimador segue 15% abaixo, e segue prevendo fatiamento que não
acontece — o item do estimador descalibrado continua aberto.

---

## Fila, reordenada pela medição

| # | Item | Nota |
|---|---|---|
| 1 | **`secao` deve trazer o grupo imediato** | Resolve o item 1 na raiz e provavelmente o item 5 (seção nos totais) junto |
| 2 | **Publicar a escala no n8n** | Pronta no `main`, ainda não em produção |
| 3 | **Piso honesto do `secao_fecha`** | Declarar `hierarquia_achatada` em vez de acusar, até o item 1 |
| 4 | **COMBINADO por estrutura** | `entidade_coluna > 1` ⇒ combinado |
| 5 | **Entidade fantasma + normalização de nome** | 7 entidades para 6 empresas |
| 6 | Estimador, `FOLHA_PAGAMENTO`, persistir tokens, `eslint` no `n8n/` | Baratos |
| 7 | Confiança derivada de evidência | Fatia própria |
