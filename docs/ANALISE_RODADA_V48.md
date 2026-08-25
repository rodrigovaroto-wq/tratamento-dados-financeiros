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

---

# ANEXO — Conferência linha a linha contra os PDFs

Feita com o oráculo do próprio repositório: `pdf/METRICAS.json` (a verdade declarada pelo
gerador, não medição do PDF) e `extrai.py` (lê o texto do PDF sem dependência externa).

## A.1 A extração está completa — e a métrica de cobertura engana

Primeira comparação, ingênua: `celulas_de_valor_verdade` contra células extraídas com
número deu **83,2% de cobertura**, com 12 documentos "faltando" células — o `17_Livro_Razao`
faltando 195, os balancetes ~75 cada.

**Esse número está errado, e o erro é da métrica.** `render.py` conta como "célula de valor"
**toda célula da tabela que contenha um dígito**, exceto a do rótulo. Isso inclui:

| Documento | Colunas que a verdade conta como "valor" | São valor? |
|---|---|---|
| `15/16_Balancete` | `Código` (1.1.01.001) | ❌ identificador |
| `17_Livro_Razao` | `Data` (01/12/2025), `Lançamento` (LC-2025-4000) | ❌ identificadores |
| `20_Mapa_de_Divida` | `Contrato` (CG-2021-884.117), `Vencimento`, `Taxa` | ❌ identificadores |
| `29_Extrato` | `Agência` (0341), `Conta` (12.884-7) | ❌ identificadores |

Conferido documento a documento, **o sistema pegou os valores financeiros que existem**:

| Documento | O que o PDF tem | O que o sistema extraiu | |
|---|---|---|---|
| `17_Livro_Razao` | 99 lançamentos × (Débito **ou** Crédito) + Saldo | Débito 35 + Crédito 64 + Saldo 99 = **198** | ✅ completo |
| `15_Balancete` | 78 contas × Saldo (+ D/C textual) | Saldo 78 + D/C 78 | ✅ completo |
| `29_Extrato` | 5 bancos + TOTAL = **6 saldos** | **6 saldos** (280, 214, 148, 99, 84, 825) | ✅ completo |
| `20_Mapa_de_Divida` | Saldo devedor, Juros, Saldo US$ (1 contrato) | 12 + 12 + 1 = **25** | ✅ completo |
| `27_Imobilizado` | Custo, Depreciação (7 de 9 depreciam), Líquido | 9 + 7 + 9 | ✅ completo |
| `22/23_Aging` | 8 e 7 colunas de faixa | as 8 e as 7 | ✅ completo |

**Conclusão: a cobertura real de valores financeiros é ~100%, não 83%.** O que o sistema
"não extrai" são código de conta, data, número de lançamento, agência e taxa — e **não
extrair isso está certo.**

> Fica um item de manutenção: `n8n/lib/cobertura.mjs` é calibrado contra essa mesma métrica
> inflada (`n8n/medir-regua-cobertura.mjs`). Uma régua calibrada contra um denominador que
> conta identificador como valor vai subestimar a cobertura em documento de muitas colunas.

## A.2 Os quatro documentos sem linha nenhuma: os quatro estão CERTOS

| Doc | Conteúdo | Tem valor financeiro? |
|---|---|---|
| `30_Certidoes` | Empresa, certidão, órgão, situação, validade | ❌ nenhum — só datas |
| `32_Organograma` | Controladora, controlada, participação %, país | ❌ nenhum — só percentuais societários |
| `33_Notas_Explicativas` | Texto corrido | ❌ nenhuma tabela |
| `34_Parecer_do_Auditor` | Texto corrido | ❌ nenhum número |

Extrair zero linha dos quatro é **o comportamento correto**, e a verdade do gerador
concorda (`celulas_de_valor_verdade = 0` nos quatro).

### 🔶 Mas dois deles carregam os fatos mais importantes do mandato

Não é defeito de extração — é **lacuna de escopo**, e vale mais que várias das pendências:

- **`33_Notas_Explicativas`** traz, em texto: *"o índice apurado em 31/12/2025 não atingiu o
  mínimo contratado… os saldos originalmente classificados no passivo não circulante foram
  integralmente reclassificados para o passivo circulante"*. **É a explicação de por que o
  Passivo Circulante saltou para 112.372** — e o motivo real de a empresa parecer ilíquida;
- **`34_Relatorio_do_Auditor`** traz **OPINIÃO COM RESSALVA** e **INCERTEZA RELEVANTE SOBRE
  CONTINUIDADE OPERACIONAL**.

Ressalva de auditor e quebra de covenant são exatamente o que um comitê de crédito precisa
ver primeiro, e hoje **não chegam ao portal de forma nenhuma** — nem como linha, nem como
alerta. Os documentos entram, são classificados e ficam mudos.

## A.3 As 9 pendências de "linha exigida ausente", uma a uma

| # | Pendência | Conferido no PDF | Veredito |
|---|---|---|---|
| 1-3 | `GRUPO CANASTRA`: Ativo Total, Passivo+PL, Caixa | A entidade não existe — nasceu do doc 14 misclassificado | ❌ **falsa** |
| 4 | `COMBINADO`: Caixa e equivalentes | O combinado só tem linhas de SEÇÃO (Ativo Circulante, ANC…). **Não há linha de caixa** | ✅ **legítima** |
| 5 | `DRE Comercial`: Despesa Financeira | A DRE só traz `Resultado financeiro líquido` — valor LÍQUIDO | ✅ **legítima** |
| 6 | `DRE CN Transportes`: Despesa Financeira | idem | ✅ **legítima** |
| 7 | `MAPA_DIVIDA`: Juros por contrato | **Extraído**: coluna `Juros do exercício (R$)`, 12 células | ❌ **falsa** |
| 8 | `MUTUOS`: Saldo de mútuo | **Extraído**: coluna `Saldo devedor`, 3 células (11.160 / 4.900 / 16.060) | ❌ **falsa** |
| 9 | `FAT_INTRAGRUPO`: Faturamento entre partes | **Extraído**: coluna `Valor`, 15 células | ❌ **falsa** |

### A causa das três últimas é uma só, e é estrutural

Os localizadores de 7, 8 e 9 procuram o conceito com `contra = 'chave'` — no **rótulo da
linha**:

| Conceito | Procura | Onde o dado realmente está |
|---|---|---|
| `juros_por_contrato` | "juros" na chave | coluna `Juros do exercício (R$)`; a chave é o nome do banco |
| `saldo_de_mutuo` | "mutuo" na chave | coluna `Saldo devedor`; a chave é o par mutuante/mutuária |
| `faturamento_entre_partes` | "faturamento" na chave | coluna `Valor`; a chave é "2023 - Agro para Indústria" |

**Em documento matricial o conceito é a COLUNA, não a linha.** O localizador não tem
`contra = 'coluna'`, então cobra do cliente um dado que já está no banco. **Correção:
acrescentar `contra = 'coluna'` ao localizador** — as três pendências somem juntas.

### E as três legítimas são boas perguntas

As duas de **Despesa Financeira** são o achado de negócio da rodada: as DREs da Comercial e
da CN Transportes publicam só o **resultado financeiro LÍQUIDO**, e com ele não dá para
conferir os juros do mapa de dívida — receita e despesa vêm somadas. Pedir a abertura ao
cliente é exatamente o que um analista faria.

## A.4 A conta revisada: 20 das 27 pendências são falsas

| Origem | Qtd | |
|---|---:|---|
| `secao_fecha` (razão 2,0000) | 6 | ❌ achatamento da hierarquia |
| `duplicidade_de_rotulo` (pai ≡ filho) | 6 | ❌ achatamento da hierarquia |
| `linha_exigida` da entidade fantasma | 3 | ❌ misclassificação do doc 14 |
| `linha_exigida` com conceito na coluna | 3 | ❌ localizador só olha a linha |
| `tipo_incorreto` sem divergência | 2 | ❌ corrigido pela `0142` |
| **Falso positivo** | **20** | **74% da fila** |
| `linha_exigida` legítimas | 3 | ✅ |
| `tipo_incorreto` real (doc 14) | 1 | ✅ |
| demais | 3 | ✅ |

**Quatro causas explicam as vinte.** E nenhuma delas é erro de leitura: **a extração está
correta em ~100% dos valores financeiros dos 38 documentos.**

---

# ANEXO II — A modelagem da v48, com as premissas derivadas do realizado

Aplicada em produção em 25/08 pelas funções do próprio sistema (`fn_definir_modelagem`,
`fn_ativar_premissa`, `fn_vincular_linha_premissa`), **não por INSERT à mão**.

**Configuração:** `CANASTRA INDÚSTRIA DE EMBALAGENS LTDA.`, setor `industria`, índice `IPCA`,
último exercício real **2025**, **5 anos projetados** (2026–2030).

## As premissas saíram do realizado da v48, não de outro caso

| Premissa | Valor | Conta que a produziu |
|---|---:|---|
| `CUSTO_VARIAVEL` | **97,1%** | 135.838 ÷ 139.872 |
| `SGA_PCT` | 22,4% | 31.296 ÷ 139.872 |
| `PMR` | 65 dias | 24.861 ÷ 139.872 × 365 |
| `PME` | 41 dias | 15.605 ÷ 139.872 × 365 |
| `PMP` | 77 dias | 28.634 ÷ 135.838 × 365 |
| `TAXA_DIVIDA` | **28,4%** | 14.802 ÷ 52.063 |
| `PARCELA_ONEROSA` | 36,7% | 52.063 ÷ 141.845 |
| `CRESC_NOMINAL` | 5,0 → 3,5% | IPCA (ver nota) |
| `CAPEX_PCT` | 4% | decisão de plano |
| `DIVIDA_MOV` | −8.000 → −6.000 | decisão de plano |

**Dois números contam a história do mandato sozinhos.** `CUSTO_VARIAVEL = 97,1%` significa
que o CPV consome quase toda a receita líquida antes de qualquer despesa — a empresa não
tem margem bruta para pagar SG&A, muito menos juros. E `TAXA_DIVIDA = 28,4%` é o custo
efetivo de uma dívida de 52 milhões numa empresa nessa situação.

### Três notas sobre o que NÃO foi derivado, e por quê

1. **`ALIQUOTA` não entra.** O LAIR de 2025 é **−47.974**. A regra do repositório é
   explícita: prejuízo não vira alíquota negativa — a premissa recusa e nomeia o prejuízo;
2. **`TAXA_DIVIDA` veio do MAPA_DIVIDA, não da DRE.** A DRE publica só
   `RESULTADO FINANCEIRO LÍQUIDO` (−20.712), que soma receita e despesa financeira. Usá-lo
   subestimaria a taxa. **É exatamente a pendência legítima que a análise identificou** —
   e aqui ela deixa de ser teoria: sem a abertura, a premissa teria de ser estimada;
3. **`CRESC_NOMINAL` é IPCA, e é uma escolha declarada.** A receita CAIU 318 → 246 → 188.
   Extrapolar a queda seria projetar a morte da empresa; projetar alta seria otimismo sem
   base. O IPCA é o neutro, e quem discordar troca um número numa tela.

## Conferência do sistema

`fn_conferir_modelagem` respondeu **`pronto: true`**:

| | |
|---|---:|
| Premissas ativas | 10 |
| Premissas sem valor | **0** |
| Linhas do caso | 559 |
| Linhas com premissa | 7 |
| Vínculos órfãos | **0** |
| Não projetáveis (subtotal / série mensal) | 43 / 36 |

**552 linhas sem premissa não é defeito:** o modelo projeta as linhas que dirigem o
resultado (receita, custo, SG&A, giro, capex, dívida) e carrega o resto pelo espelho. As
sete vinculadas são as sete que o modelo institucional exige.

## O que falta para fechar a verificação da planilha

Os inputs estão aplicados e o sistema declara `pronto`. **O passo seguinte é do dono:**
exportar os dois `.xlsx` pelo portal ("Exportar dados" e "Ir para a modelagem"). Com os
arquivos em mão, a auditoria é automática:

```bash
./portal/node_modules/.bin/tsx portal/scripts/auditar-xlsx.mts <arquivo.xlsx>
```

São 10 itens automáticos, mais os 10 humanos do `docs/ACEITE.md`. Só então dá para afirmar
que a planilha está como o modelo do repositório manda — e essa é a última milha que
nenhuma consulta ao banco substitui.
