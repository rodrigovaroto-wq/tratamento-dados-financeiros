# Mapa do Modelo Base — `docs/referencia/modelo-base.xlsx`

Fase 1 de `docs/PROMPT_ESPELHAR_MODELO_BASE.md`: **mapear antes de replicar**. Este documento
descreve as 14 abas do Modelo Base no nível em que o §7 exige — identidade, anatomia, gramática
das fórmulas, formatação, recursos e a marcação `universal` × `do setor de origem`.

O teste de pronto do mapa é o do próprio prompt: *"para reconstruir esta aba do zero, o que
exatamente eu preciso escrever?"*. Onde o mapa não responde isso, ele **declara** que não
responde (§13) em vez de resumir o que não foi lido.

**Nenhuma linha de código de produção foi alterada para produzir este mapa.**

---

## 1. Como este mapa foi medido (e como refazer a medição)

Instrumento oficial, do §6 do prompt:

```bash
python3 docs/referencia/mapear-xlsx.py docs/referencia/modelo-base.xlsx
python3 docs/referencia/mapear-xlsx.py docs/referencia/modelo-base.xlsx --aba "Balance Sheet" --celulas
```

O `mapear-xlsx.py` resolve a aba pelo `rels` (a armadilha da ordem dos `sheetN.xml`, que já
produziu número errado nesta investigação) e foi usado para **todas** as contagens deste
documento. Ele tem três limites, que não são defeito e sim escopo — e que precisaram ser
cobertos por leitura direta das partes do ZIP para a fase 1:

| Limite do instrumento | O que ficou fora | Como este mapa cobriu |
|---|---|---|
| imprime `s=123` e não decodifica `xl/styles.xml` | numFmt, negrito, cor de fonte, cor de preenchimento, bordas, recuo | leitura de `xl/styles.xml` (`cellXfs` → `fonts`/`fills`/`borders`/`numFmts`) e da paleta `indexedColors` |
| imprime `=(compartilhada si=N)` sem o texto | a fórmula real de 8.373 células (58% do total) | a mestre `<f t="shared" si=N>` tem o texto; em R1C1 mestre e filhas são idênticas por definição |
| não imprime largura de coluna, altura de linha, `outlineLevel`, `hidden`, `dimension`, gráfico, imagem, nome definido por aba | identidade e recursos | leitura de `xl/workbook.xml`, `xl/worksheets/sheetN.xml`, `xl/charts/*`, `xl/drawings/*` |

Duas ferramentas de análise **descartáveis** (scratchpad, fora do repositório) foram usadas para
isso, ambas reusando a resolução por `rels` do script oficial: uma que traduz o índice de estilo
para o que ele significa, e uma que traduz cada fórmula para **R1C1 relativa** e comprime faixas
de colunas com a mesma fórmula. A segunda é o que torna 14.504 fórmulas legíveis: uma linha de
26 colunas quase sempre é **uma** fórmula puxada à direita.

> **Se a fase 2 quiser esses dois recursos de forma permanente**, o lugar deles é dentro do
> `mapear-xlsx.py` (uma flag `--estilos` e uma `--r1c1`), não em script novo. Isso é mudança de
> ferramenta, não de produção — mas está **fora** da fase 1, que é de leitura.

### 1.1 Placar remedido nesta sessão (não copiado do §3)

```
===== docs/referencia/modelo-base.xlsx — 0.5 MB =====
nomes definidos: 1044   ex.: ['\a', '\b', '\g', '\p', '__123Graph_A', '__123Graph_A']
gráficos: 8  imagens: 1  estilos: True  tema: True
```

| # | Aba | Estado | kb | Fórmulas | …com `#REF!` | …compartilhadas | Valores fixos | Validações | Cond. | Merges | Congelado |
|---:|---|---|---:|---:|---:|---:|---:|---:|---:|---:|---|
| 1 | `Considerações` | visível | 2 | 3 | 0 | 0 | 6 | 0 | 0 | 1 | não |
| 2 | `Capa` | visível | 1 | 0 | 0 | 0 | 2 | 0 | 0 | 0 | não |
| 3 | `Output` | visível | 327 | **3.693** | **627** | 794 | 800 | 0 | 0 | 4 | não |
| 4 | `Revenues, COGS & SG&A` | visível | 75 | 664 | 4 | 485 | 128 | 0 | 0 | 0 | sim |
| 5 | `Premissas` | visível | 5 | 15 | 0 | 6 | 47 | 0 | 0 | 0 | não |
| 6 | `Income Statement` | visível | 84 | 738 | 2 | 413 | 112 | 0 | 0 | 0 | sim |
| 7 | `Balance Sheet` | visível | 113 | 1.275 | 0 | 747 | 119 | 0 | 0 | 0 | sim |
| 8 | `Working Capital` | visível | 126 | 1.631 | 0 | 1.380 | 36 | 0 | 0 | 0 | sim |
| 9 | `ST Inv. & Debt` | visível | 383 | **3.573** | 10 | 2.233 | 728 | **3** | 0 | 0 | sim |
| 10 | `Fixed Assets & CAPEX` | visível | 150 | 1.785 | 0 | 1.705 | 292 | 0 | 0 | 0 | sim |
| 11 | `Cash Flow` | visível | 79 | 692 | 0 | 118 | 74 | 0 | 0 | 0 | sim |
| 12 | `Goodwill, Taxes & Div.` | visível | 45 | 337 | 24 | 191 | 114 | 0 | 0 | 0 | sim |
| 13 | `Anual` | visível | 556 | 64 | 0 | 57 | **2.636** | 0 | 0 | 2 | sim |
| 14 | `Tributos a Recolher` | visível | 3 | 34 | 0 | 27 | 7 | 0 | 0 | 0 | não |
| | **TOTAL** | | | **14.504** | **667** | 8.373 | 5.201 | 3 | 0 | 7 | 10 de 14 |

Confere com o §3 do prompt nas duas colunas que ele mede (abas e fórmulas por aba). As colunas
novas — `#REF!`, compartilhadas, valores fixos — são desta medição e mudam o plano (§12).

### 1.2 Censo de funções — a gramática cabe em dez verbos

| Função | Ocorrências | Onde se concentra |
|---|---:|---|
| `SUM` | 1.525 | `ST Inv. & Debt` 1.289, `Output` 126 |
| `IF` | 851 | `ST Inv. & Debt` 711, `Working Capital` 34 |
| `AVERAGE` | 192 | `ST Inv. & Debt` 176 (saldo médio do ano), `Revenues` 15 |
| `CHOOSE` | 46 | o dial de cenário: `Revenues` 18, `Working Capital` 15, `Fixed Assets` 13 |
| `HLOOKUP` | 33 | só `Output`, e **todos os 33 apontam para `#REF!`** |
| `OFFSET` | 17 | `Fixed Assets` 14 (janela de depreciação), `ST Inv. & Debt` 3 |
| `EOMONTH` | 3 | `Revenues` — é o eixo do tempo inteiro |
| `ABS`, `CORREL`, `SUMPRODUCT` | 2, 2, 1 | `ST Inv. & Debt`, `Anual`, `ST Inv. & Debt` |

**Não há** `VLOOKUP`, `INDEX/MATCH`, `NPV`, `IRR`, `XIRR`, `SUMIF`, `IFERROR`, macro VBA
(`workbookPr codeName="ThisWorkbook"` sem projeto VBA), tabela dinâmica ou tabela estruturada.
**Zero fórmulas usam nome definido** (§11.1) e **zero** referenciam outra pasta de trabalho.

---

## 2. Os oito invariantes do workbook

O que vale para **todas** as abas. É a parte do motor que se replica uma vez e serve para as 14.

### 2.1 `P01 EIXO-DO-TEMPO` — todo o calendário sai de **uma** célula

A única entrada de data do modelo é **`'Revenues, COGS & SG&A'!C5`** (`Last Completed Period`,
valor `40908` = 31/12/2011). Dali:

- **para trás** (histórico): `D7:G7` = `=+EOMONTH(<coluna à direita>,-12)`
- **a âncora**: `H7` = `=C5`
- **para frente** (projeção): `I7:AC7` = `=+EOMONTH(<coluna à esquerda>,12)`

São as **3 únicas** ocorrências de `EOMONTH` no arquivo. Mudar `C5` de ano reescreve os 26 anos
de todas as abas. Consequência para o gerador: **não existe lista de anos** — existe uma data e
duas recorrências.

### 2.2 `P02 CABEÇALHO-HERDADO` — e cada aba tem seu próprio deslocamento de coluna

A linha 7 de cada aba é uma referência à linha 7 de outra, com **deslocamento fixo de coluna**.
Isso é a armadilha estrutural do arquivo: as abas **não** estão alinhadas na mesma coluna.

| Aba | Col. do rótulo | 1ª col. do eixo | Ano nela | Últ. col. | Ano | 1ª col. de projeção | De quem herda a linha 7 |
|---|---|---|---|---|---|---|---|
| `Revenues, COGS & SG&A` | B | D | 2007 | AC | 2032 | I (2012) | de `C5` (raiz) |
| `Premissas` | A | B | 2010 | J | 2018 | — (só histórico) | não herda: `=C4+1` |
| `Income Statement` | C | E | 2007 | AD | 2032 | J (2012) | `Revenues` D:AC (**+1 col**) |
| `Balance Sheet` | C | E | 2007 | AD | 2032 | J (2012) | `Revenues` D:AC (**+1 col**) |
| `Working Capital` | B | D | 2007 | AC | 2032 | I (2012) | `Revenues` D:AC (**mesma col**) |
| `ST Inv. & Debt` | B | D | 2008 | AB | 2032 | H (2012) | `Fixed Assets` D:AB (mesma col) |
| `Fixed Assets & CAPEX` | B | D | 2008 | AB | 2032 | H (2012) | `Revenues` E:AC (**−1 col**) |
| `Cash Flow` | B | D | 2008 | AB | 2032 | H (2012) | `Revenues` E:AC (**−1 col**) |
| `Goodwill, Taxes & Div.` | B | G | 2011 | AB | 2032 | H (2012) | `Revenues` (D:F **quebradas**, `=#REF!`) |
| `Output` | B | G | 2010 | AB | 2031 | — (ano inteiro, não data) | `=G$9` interno |
| `Anual` | A | B | 1994 | AL | 2030 | Q (2009) | não herda: base macro |
| `Tributos a Recolher` | — | A | 2013 | L | 2024 | — | não herda: `=A3+1` |

Três leituras obrigatórias desta tabela:

1. **`Output` usa ano inteiro (2010), as abas operacionais usam data de fim de mês (31/12/2010).**
   São dois eixos diferentes no mesmo arquivo.
2. **`Output` termina em 2031, as operacionais em 2032.** O último ano do motor não aparece no
   relatório.
3. **`Cash Flow` e `Goodwill` não têm coluna de histórico útil** — começam em 2012. O histórico
   do fluxo entra por `Beg. of the Period Cash` (`Cash Flow!H58` = `'Balance Sheet'!I13`).

### 2.3 `P03 DIAL-DE-CENÁRIO` + `P04 TRÊS-BLOCOS` — o cenário é dado, não código

- **`Output!G2`** é a única entrada: `1`, `2` ou `3` (`Base` / `Cliente` / `Stress`, rotulados em
  `Output!B3:B5` com o número ao lado em `G3:G5`).
- Cada aba de driver copia o dial na **própria célula `C3`**: `='Output'!$G$2`.
  Abas com `C3`: `Revenues, COGS & SG&A`, `Working Capital`, `Fixed Assets & CAPEX`.
- O consumo é sempre `CHOOSE($C$3, <bloco base>, <bloco cliente>, <bloco stress>)` — 46
  ocorrências.
- **`P04`**: o mesmo conjunto de linhas aparece **três vezes** na aba, um bloco por cenário, e o
  2º e o 3º nascem como `=<mesma linha do bloco anterior>` (o default é "igual ao Base";
  divergir é digitar por cima). Ver `Working Capital` 55–98 e `Fixed Assets` 103–141.
- **Guarda de coerência**: `Output!I2:L5` é um bloco `Check Scenario` que lê o `C3` **de volta**
  de cada aba (`L3` = `='Revenues, COGS & SG&A'!C3`, `L4` = `='Fixed Assets & CAPEX'!C3`,
  `L5` = `='Working Capital'!C3`). Se uma aba perder o vínculo com o dial, aparece ali.

### 2.4 `P05 TOTAL-DO-BLOCO` — a faixa é fixa, mesmo vazia

`=SUM(<primeira linha do bloco>:<última>)` sobre uma faixa de **N linhas reservadas**, com as
sobras rotuladas `Item 2`…`Item 5` e sem conteúdo. Exemplos: `Income Statement!H17` =
`=SUM(H18:H22)` (5 linhas, 2 usadas); `Balance Sheet!E20` = `=SUM(E21:E25)`;
`Fixed Assets!H10` = `=SUM(H12:H22)` (11 linhas de capex, 6 rotuladas). **A grade é de tamanho
fixo e o total nunca muda de fórmula quando uma linha entra** — é isso que faz o modelo aceitar
conta nova sem retrabalho.

### 2.5 `P18 ESPELHO-DA-CONTA` — nenhuma demonstração lê o miolo de um cálculo

Toda aba de driver (`Working Capital`, `Fixed Assets & CAPEX`, `ST Inv. & Debt`,
`Goodwill, Taxes & Div.`) começa com três blocos rotulados **`BALANCE SHEET ACCOUNTS`**,
**`INCOME STATEMENT ACCOUNTS`** e **`CASH FLOW ACCOUNTS`**, que republicam o resultado do
cálculo. `Balance Sheet`, `Income Statement` e `Cash Flow` leem **daquele espelho**, nunca da
linha onde a conta foi calculada.

É a interface do modelo, e é o que permite trocar o motor de uma conta sem tocar nas
demonstrações. Replicar isto é mais importante que replicar qualquer aba isolada.

### 2.6 `P19 RÓTULO-POR-REFERÊNCIA` — um rótulo, um lugar

O texto do rótulo de uma conta é digitado **uma vez** (no `Balance Sheet`, em geral) e as outras
abas o **referenciam**: `Working Capital!B13` = `='Balance Sheet'!C14`;
`Cash Flow!B20` = `='Working Capital'!B13`; `Output!B32` = `='Balance Sheet'!C13`.
Consequência: renomear uma conta no balanço renomeia a linha correspondente em quatro abas.

### 2.7 `P20 CONTADOR-INVISÍVEL` e `P21 SINAL-EM-COLUNA-PRÓPRIA`

- **`P20`**: `Income Statement!A7:A89` = `=+A6+1` e `ST Inv. & Debt!A7:A346` = `=1+A6`, com
  **fonte branca** (`idx9 = FFFFFF`). É um número de linha estável para referência humana, e é
  invisível na tela. `ST Inv. & Debt` reinicia a contagem em cada bloco de dívida (linha 113,
  123, 141…), o que dá "linha 8 do DEBT #1".
- **`P21`**: `Income Statement!B` carrega `+`, `(-)`, `=` como texto em coluna própria de 4,1 de
  largura, separada do rótulo (coluna C). O sinal não está no rótulo.

### 2.8 A gramática de cores — o que cada cor SIGNIFICA

A paleta é **declarada no arquivo** (`indexedColors` em `xl/styles.xml`, 64 entradas), então as
cores são exatas e não dependem de tema:

| Elemento | Cor | Significado no modelo | Exemplos de estilo |
|---|---|---|---|
| **fonte azul** | `0000FF` (`idx12`) | **entrada manual / hardcode** — número digitado por gente | `s145`, `s420`, `s341`, `s343`, `s79`, `s314` |
| fonte preta | `000000` (`idx8`) | **calculado** | `s328`, `s329`, `s338`, `s344`, `s210` |
| fonte branca | `FFFFFF` (`idx9`) | **auxiliar invisível** (contador da coluna A) | `s95`, `s226` |
| fonte cinza itálico | `808080` (`idx23`) | legenda de cenário (`Base Case`…) | `s92`, `s93` |
| fonte `0070C0` | azul institucional | nome da empresa na `Capa` | `s446` |
| preench. `DDDDDD` | cinza claro | faixa de **linha de conta** no `Output` | `s179`, `s190`, `s191`, `s609` |
| preench. `C0C0C0` | cinza médio | faixa de **subtotal** | `s182`, `s183`, `s34x` |
| preench. `969696` | cinza escuro | faixa de **total geral** (`ASSETS`, `LIABILITIES & EQUITY`) | `s194`, `s195`, `s459` |
| preench. `CCFFCC` | verde claro | **âncora do histórico** (total que vem da `Premissas`) | `s315` |
| preench. `FF0000` + fonte branca negrito | vermelho | **faixa de cabeçalho de ano** e cabeçalho da `Considerações` | `s391`, `s392`, `s396`, `s397` |
| preench. `FFFFFF` sólido | branco explícito | apaga a grade na `Premissas`/`Tributos` | `s486`–`s513`, `s548` |

Convenções de fonte, borda e formato numérico, uniformes no arquivo:

- **fonte** Arial 10 em tudo; título de aba (linha 7) Arial **12 negrito**, cor `870000`
  (`idx28`, vinho), com **borda inferior dupla** (`s17`);
- **`R$ thousand`** em itálico na linha 8, logo abaixo do título (`s41`) — a unidade é **milhar
  de reais** nas abas operacionais e **`R$ million - nominal`** no `Output` (rótulo `s396`), o
  que é rótulo, não conversão: os números do `Output` são os mesmos milhares;
- **cabeçalho de ano** (linha 7 das operacionais): `numFmt 168` =
  `[$-416]dd-mmm-yy` (locale pt-BR), centralizado, borda inferior dupla (`s1`);
- **valor monetário**: `numFmt 166` = `_(* #,##0_);_(* (#,##0);_(* "-"_);_(@_)` — contábil, sem
  decimal, negativo entre parênteses, zero como `-`;
- **percentual**: `numFmt 10` = `0.00%`, itálico, alinhado à direita (`s90`, `s443`, `s349`);
- **prazo médio (dias)**: `numFmt 212` = `_(* #,##0.0_)…` com uma decimal (`s343`, `s344`);
- **subtotal**: negrito com **borda fina em cima e embaixo** (`s32`, `s35`); **total de bloco**:
  negrito sem borda (`s31`, `s36`);
- **hierarquia por recuo, não por cor**: nível 1 sem recuo (`s18`), nível 2 `indent=1` (`s19`,
  `s20`), nível 3 `indent=2` **itálico** (`s21`), premissa `indent=1` itálico (`s25`);
- **`showGridLines=0`** em 11 das 14 abas (exceções: `Premissas`, `Cash Flow`,
  `Tributos a Recolher`) e **`zoomScale=85`** em 10;
- 96 `numFmt` customizados existem no arquivo, mas só ~15 estão em uso — o resto é sedimento das
  pastas de trabalho de origem (§11.1).

---

## 3. `Considerações` — aba 1

- **Identidade**: 1ª na ordem, visível, sem painel congelado, `showGridLines=0`, zoom 85.
  `dimension B6:F11`. Larguras: B = 38,4; C:F = 31,6. Alturas: linha 6 = 13,8; 7 = 14,4;
  8 = 13,8; **9, 10 e 11 = 77,25** (linha 11 **oculta**). Merge: `B8:F8`.
- **Anatomia**: uma matriz 3×4 em branco para texto corrido.
  - `B7:F7` — cabeçalho **vermelho, fonte branca negrito**: `Principais Premissas` |
    `Crescimento` | `Margem Ebitda` | `Investimento (Capex)` | `Capital de giro`;
  - `B8:F8` (merge) — `Cenários`, faixa cinza `C0C0C0` negrito (`s613`);
  - `B9:B11` — os três cenários **por referência**: `=Output!B3`, `=Output!B4`, e
    `B11` = `=Output!B5 & "  (Ainda a definir)"`;
  - `C9:F11` — **vazias**. É onde o analista escreve, à mão, a justificativa de cada premissa
    por cenário. As alturas de 77,25 existem para caber o texto.
- **Gramática**: 3 fórmulas, todas `P19` (rótulo por referência) — uma delas com concatenação
  literal (`& "  (Ainda a definir)"`), que é a marca de "cenário ainda não preenchido".
- **Recursos**: nenhum. Sem validação, sem formatação condicional, sem gráfico.
- **Classificação**: `universal`. Nada aqui fala de plano de saúde.

## 4. `Capa` — aba 2

- **Identidade**: 2ª, visível, `showGridLines=0`, sem zoom customizado, sem congelamento.
  `dimension C4:C6`. Coluna C = **101,1** de largura. Linha 4 = 32,4 de altura.
- **Anatomia**: duas células de texto. `C4` = **`Unimed Rio`** (nome da empresa, fonte
  `0070C0`, `s446`); `C6` = `Projeções Financeiras` (`s345`).
- **Gramática**: **zero fórmulas**. Os dois textos são digitados.
- **Recursos**: nenhum. O `image1.emf` do arquivo **não** está aqui (está no `Balance Sheet`,
  §11.3).
- **Classificação**: estrutura `universal`; o conteúdo `Unimed Rio` é **do caso**.
- **Para reconstruir**: `C4` = nome da entidade do mandato; `C6` = literal
  `Projeções Financeiras`.

## 5. `Output` — aba 3 · 3.693 fórmulas (a maior)

- **Identidade**: 3ª, visível, **aba ativa ao abrir** (`tabSelected=1`, `activeTab=2`),
  `showGridLines=0`, `dimension A1:BE217`, `outlineLevelRow=1`, sem painel congelado.
  Larguras: A = 2,33; **B = 62,4** (coluna de rótulo larga); C:F **ocultas**; G:O ≈ 12;
  **P:AB ocultas**; AD ≈ 9,1; AE:AK ≈ 11,5; AO = 16,7; **AP = 40,3**; AQ:AR = 7,4; AS:AX = 12;
  AY:AZ e BA:BB ocultas. 202 linhas com altura declarada. 4 merges: `I2:L2`, `I3:K3`, `I4:K4`,
  `I5:K5`. `Print_Area` = `Output!$B$8:$O$125`.
  - **O horizonte visível é 2010–2018** (G:O). As projeções 2019–2031 (P:AB) existem, calculam e
    estão **ocultas**. Isso casa com o §4 do prompt: o arquivo é um modelo 2010–2018.
- **Anatomia** (blocos na ordem, coluna B = rótulo, G:AB = anos inteiros 2010…2031):

  | Linhas | Bloco | O que é |
  |---|---|---|
  | 2–5 | **`SCENARIO`** + `Check Scenario` | `G2` = dial (entrada); `B3:B5`/`G3:G5` = os três cenários; `I2:L5` = leitura de volta do `C3` de três abas |
  | 8–27 | **`SUMMARY`** | Net Revenues, % Growth, EBITDA, % Growth, % Margin, Amortization Bancos, Net Profit, Capex, Current Portion of LT Debt, Long Term Debt, Revolving Leverage, Net Debt, Total Debt, e 5 índices (Net Debt/EBITDA com revolving, Total Debt/EBITDA, Variação NCG, Liquidez, (EBITDA)/(Juros+Amortização)) |
  | 29–67 | **`BALANCE SHEET`** | balanço inteiro espelhado, com rótulos por referência, e **`L67` = check** `=G48-G66` (ASSETS − LIABILITIES & EQUITY) |
  | 69–95 | **`INCOME STATEMENT`** | DRE espelhada com as margens calculadas aqui (`% Custos`, `Gross Profit Margin`, `% SG&A`, `EBITDA Margin`, `EBIT Margin`, `Net Profit Margin`) |
  | 98–125 | **`CASH FLOW`** | fluxo espelhado, linha a linha |
  | 128–206 | **`DEBT & RATIOS`** | **13 blocos de 6/7 linhas por tranche de dívida**: `Initial Amount`, `(+) Debt Increase`, `Interest Expenses`, [`FX Loss / (Gain)`], `(-) Debt Amortization`, `Final Amount` |
  | 207–215 | **`RATIOS`** | EBITDA, Total Financial Debt (`=SUM` de 12 tranches), Net Financial Debt, Current Taxes, Net Debt/LTM EBITDA, DSCR1, DSCR2, DSCR3 |
  | AD18:AK28 | tabela lateral | `Dívida total permitida a 2x` — série dos 3 cenários para o gráfico 1 |
  | AO11:BB44 | tabela lateral | **covenants**: por cenário e por índice (`Liquidez Seca`, `Net Debt / EBITDA`, `EBITDA / INTEREST EXPENSE`, `Total Debt / (EBITDA+WCC)`), com linhas `Corte Sugerido` e `Covenant Sugerido`. Alimenta os gráficos 2–8. Os rótulos são montados por concatenação: `AP13` = `=$B$25&" "&AO13` |

- **Gramática**:
  - **`P22 ESPELHO-COM-DESLOCAMENTO`**: quase toda linha é `='<Aba>'!<mesma linha, col+1>` —
    o `Output` é uma **vista**, não um cálculo. `G10` = `='Income Statement'!H24`;
    `G31` = `='Balance Sheet'!H12`; `G100` = `='Cash Flow'!G12`.
  - **eixo próprio**: `G9` = `2010` (**entrada**), `H9:AB9` = `=G9+1`; e cada bloco repete o
    cabeçalho com `=G$9` (`G30`, `G70`, `G99`, `G129`).
  - **índice = razão de duas linhas acima**: `G11` = `=(G10-F10)/F10`;
    `G14` = `=G12/G10`; `G23` = `=G21/G12`. Sempre razão de linhas da própria aba.
  - **`P23 ROLAGEM-DE-TRANCHE`** (13×): `Final Amount` = `=Initial + Increase − Amortization`;
    `Initial Amount` do ano seguinte = `=Final Amount` do anterior; e a cada 5 colunas uma
    coluna de **soma anual de trimestres** (`=SUM(J131:M131)`).
  - **`Total Financial Debt`** = `=SUM(G135,G141,G147,G153,G159,G165,G172,G179,G186,G193,G200,G206)`
    — soma explícita das 12 linhas `Final Amount`, não faixa contígua.
  - **`/1000`** nas linhas de tranche: o bloco de dívida do `Output` está em **milhão**, o resto
    do arquivo em milhar.
- **Estado real desta aba — 627 das 3.693 fórmulas estão com `#REF!`** (17%): os 33 `HLOOKUP`
  do bloco de tranches e o rótulo de cada bloco (`B130`, `B136`, `B142`… = `=#REF!`) apontam
  para uma tabela de dívida que **não existe mais** no arquivo. `DSCR2` (`L214`) também é
  `=#REF!`. **O bloco 128–206 do Modelo Base não funciona hoje.**
- **Formatação**: faixas cinza por nível (`DDDDDD` conta, `C0C0C0` subtotal, `969696` total);
  cabeçalho de ano em **vermelho com fonte branca** (`s396`/`s397`); percentual `0.0%`
  (`numFmt 169`) nas linhas `% Growth`; `numFmt 210` (`#,##0.0`) nas linhas de valor do
  `Output` — **uma decimal**, contra zero decimal das abas operacionais; `numFmt 212` nos
  índices.
- **Recursos**: **os 8 gráficos do arquivo estão todos aqui** (§11.2); nenhuma validação;
  nenhuma formatação condicional; `Print_Area B8:O125`; `vmlDrawing1.vml` (forma legada).
- **Classificação**: `universal` na estrutura inteira. Os rótulos de conta vêm por referência do
  `Balance Sheet`, então herdam a classificação de lá.

## 6. `Revenues, COGS & SG&A` — aba 4 · 664 fórmulas

**É a aba-raiz do modelo**: o eixo do tempo e o dial de cenário nascem aqui.

- **Identidade**: 4ª, visível, `showGridLines=0`, zoom 85, `dimension A2:AG86`.
  **Painel congelado `xSplit=8 ySplit=7`** (`topLeftCell I34`) — trava até a coluna H (2011) e
  até a linha 7. `outlineLevelCol=1`. Larguras: A = 3; **B = 23,1**; C = 10,9; **D:F ocultas**
  (2007–2009, `outlineLevel=1`); G:H = 11,3; I:AC = 13,4 (I:AC agrupadas, `outlineLevel=1` de
  O em diante); AG = 16,9.
- **Anatomia**:

  | Linhas | Bloco | Conteúdo |
  |---|---|---|
  | 2–5 | **cabeçalho de controle** | `A2:A4` = 1/2/3; `B2:B4` = `Base Case`/`Client Case`/`Stress Case`; `C3` = `=Output!$G$2` (o dial); **`C5` = `Last Completed Period` = 40908** (a raiz do tempo) |
  | 7–8 | título | `REVENUES` + `R$ thousand`; linha 7 = o eixo (`P01`) |
  | 10–13 | **`GROSS REVENUES`** | total (verde `CCFFCC`), e a premissa de crescimento em três linhas de cenário (11 = `Receita`/base macro, 12 = `crec`, 13 = digitado 7,0%) |
  | 23–24 | `DEVOLUÇÔES` | valor = `% Gross × receita bruta`; `% Gross` histórico calculado, projetado por `AVERAGE` dos dois últimos |
  | 27–32 | `IMPOSTOS` | `% Gross` por `CHOOSE($C$3, …)` com três linhas de cenário (30, 31, 32) |
  | 34–35 | **`RECEITA LÍQUIDA`** | `=bruta − devoluções − impostos` + `% Gross` |
  | 37–46 | **`CUSTOS`** | total = variável + fixo; `Custo Variável` = `CHOOSE(…)×receita líquida`; `% ` histórico e projetado por média; `Custo Fixo` = `=coluna anterior × (1+IPCA do Anual)` |
  | 48–55 | **`SG&A`** | mesma anatomia de CUSTOS (% da receita por cenário) |
  | 57–61 | `(+) Depreciação` e `(+) Amortização` | espelho de `Fixed Assets & CAPEX!H28` e `Goodwill…!H31` |
  | 64–65 | **`EBITDA`** e **`EBITDA Margin`** | `=RL − custos − SG&A + depreciação` |
  | 67–69 | rodapé de conferência | `I69:P69` = `=Output!I23` (Net Debt/EBITDA de volta) |

- **Gramática** (os padrões que esta aba define para as outras):
  - **`P01`** eixo do tempo (3 × `EOMONTH`);
  - **`P06 CRESCIMENTO`**: `I10` = `=H10*(1+CHOOSE($C$3,I11,I12,I13))`;
  - **`P07 PERCENTUAL-DA-RECEITA`**: `I41` = `=CHOOSE($C$3,I42,I43,I44)*(I34)`;
  - **`P10 MÉDIA-DOS-DOIS-ÚLTIMOS`**: `I24` = `=AVERAGE(G24:H24)` — é assim que a premissa
    projetada "sai do realizado";
  - **`P24 ÍNDICE-HISTÓRICO-COM-GUARDA`**: `D24` = `=IF(D10>0,D23/D10,0)` — divisão protegida
    por `IF(base>0…)`, **não** por `IFERROR`;
  - **`P16 CURVA-MACRO`**: `I11` = `=Anual!T20/100` (crescimento nominal do PIB) e
    `I46` = `=H46*(1+Anual!T41/100)` (IPCA) — a premissa **default** vem da base macro;
  - **`P25 ÂNCORA-DO-HISTÓRICO`**: `G10:H10` = `=Premissas!B9` / `=Premissas!C9`. Os dois anos
    de histórico **inteiros** vêm da aba `Premissas`, sempre com fundo verde `CCFFCC`.
- **Formatação**: linha de total com fundo verde `CCFFCC` negrito e borda (`s315`); premissa em
  itálico recuado (`s21`, `s441`); percentual `0.00%`; linhas de cenário com fonte **azul**
  quando digitadas (`s390`, `s443`) e preta quando calculadas (`s314`).
- **Recursos**: painel congelado; agrupamento de colunas (D:F histórico oculto, O:AC futuro
  agrupado); nenhuma validação, nenhum gráfico.
- **Classificação**: motor `universal`; **`Premissas` (de onde vêm 2010 e 2011) é do setor de
  origem** — ver §7. As 4 fórmulas com `#REF!` estão em `D61:G61` e `F17:G17` (linha
  `Deduções`), resíduo de uma linha apagada.

## 7. `Premissas` — aba 5 · 15 fórmulas

**A aba mais "do setor de origem" do arquivo** — e a mais simples.

- **Identidade**: 5ª, visível, **grade visível** (`showGridLines` ausente), zoom 85,
  `topLeftCell A6` (abre já rolada), sem congelamento. `dimension A1:J28`.
  **Coluna A = 77,7** de largura (rótulos longos); B:C = 14,7. Linhas 4 e 5 = 13,8.
- **Anatomia**: um DRE de operadora de saúde, com **dois anos preenchidos**.

  | Linhas | Bloco | Marcação |
  |---|---|---|
  | 1 | `Premissas` (título) | universal |
  | 3 | `Receitas` | universal |
  | 4 | anos: `B4` = 2010 e `C4` = 2011 **digitados**; `D4:J4` = `=C4+1` → 2012…2018 | universal |
  | 6–7 | `Contraprest. efetivas de plano de assist. à saúde`, `Outras receitas oper. de assist. à saúde não relac. com planos…` | **do setor de origem** |
  | 9 | `Total` = `=SUM(B6:B7)` | universal |
  | 12–16 | `Eventos conhecidos ou avisados`, `Recuperação de eventos…`, `Outras Recuperações/Ressarcimentos/Deduções`, `Variação da provisão de eventos ocorridos e não avisados`, `Outras despesas oper. de assist. à saúde…` | **do setor de origem** |
  | 18 | `Eventos indenizáveis líquidos` = `=SUM(B12:B16)` | **do setor de origem** (o nome; a mecânica de subtotal é universal) |
  | 21–24 | `Despesas de comercialização`, `Despesas administrativas`, `Outras receitas operacionais`, `Outras despesas operacionais` (= `=SUM(B25:B27)`) | universal |
  | 25–27 | `Provisão para perdas sobre créditos`, `Provisão para contingências - operacional`, `Outras` | universal |
  | 28 | `Total` = `=SUM(B21:B24)` | universal |

- **Gramática**: só `P05` (`SUM` de faixa fixa) e `=coluna anterior + 1` no cabeçalho de ano.
  Nenhum `IF`, nenhum `CHOOSE`. **Só as colunas B e C têm número** — D:J são anos sem dado.
- **Formatação**: **preenchimento branco sólido** em quase tudo (`s486`–`s513`), que é como a
  grade visível é apagada seletivamente; `numFmt 3` (`#,##0`) nos valores; `numFmt 167`
  (contábil 2 decimais) em 6 e 7; total negrito.
- **Recursos**: nenhum.
- **Classificação**: **estrutura universal, vocabulário do setor de origem.** É exatamente o
  caso do §4 do prompt: replicar a mecânica (dois anos de histórico digitado → três subtotais
  que alimentam `Revenues`), **não** os rótulos. No nosso produto o lugar deste conteúdo é o
  dado curado do caso, não uma constante no gerador.

## 8. `Income Statement` — aba 6 · 738 fórmulas

- **Identidade**: 6ª, visível, `showGridLines=0`, zoom 85, `dimension A1:AD89`.
  **Congelado `xSplit=9 ySplit=7`** (`topLeftCell J53`) — trava até I (2011). `outlineLevelCol=1`.
  Larguras: A = 1,9 (contador); **B = 4,1** (sinal); **C = 29,3** (rótulo); D = 3,3 (respiro);
  **E:G ocultas** (2007–2009); H:AD = 12,55. 13 linhas com altura reduzida (6,75/7,5) como
  **espaçadores** entre blocos: 16, 25, 34, 43, 45, 47, 52, 62, 69, 71, 80. `Print_Area B1:J82`.
- **Anatomia** — a cascata, com bloco de detalhe de 5 linhas por rubrica:

  | Linha | Item | Fórmula (R1C1 relativa) |
  |---|---|---|
  | 10 (+) | `GROSS REVENUES` | `='Revenues…'!<mesma linha, col−1>` |
  | 11–15 | detalhe (`Gross Revenues`, `Item 2`…`Item 5`) | reservado, vazio |
  | 17 (−) | `Deductions` | `=SUM(<+1>:<+5>)` |
  | 18–22 | `Vendas Canceladas`, `Impostos Diretos`, `Item 3`…`5` | espelho de `Revenues` 23 e 27 |
  | 24 (=) | **`NET REVENUES`** | `=<−14> − <−7>` |
  | 26 (−) | `COGS` | `=SUM(<+1>:<+5>)` |
  | 33 (=) | **`GROSS PROFIT`** | `=<−9> − <−7>` |
  | 35 (−) | `SG&A` | `=SUM(<+1>:<+5>)` |
  | 42 (=) | **`EBITDA`** | `=<−9> − <−7> + <+2>` |
  | 44 (−) | `Depreciation and Amortization` | `='Fixed Assets & CAPEX'!<+…>` |
  | 46 (−) | `Goodwill Amortization` | `='Goodwill, Taxes & Div.'!<+…>` |
  | 48 (+) | `Non-Cash Operating Items` | `=SUM(<+1>:<+3>)` |
  | 53 (+) | `Non-Operating Result` | `=<+1> + <+4>` (receita + despesa) |
  | 61 (=) | **`EBIT`** | `=<−19> − <−17>` |
  | 63 (+) | `Financial Result` | `=SUM(<+1>:<+4>)` |
  | 64–66 | `Financial Expenses`, `FX Gain/(Loss)`, `Financial Income` | `='ST Inv. & Debt'!H20` / `!G47` |
  | 70 (=) | **`EBT`** | `=<−9> + <−7>` |
  | 72 (−) | `Income tax ` | `=SUM(<+1>:<+2>)` |
  | 73 | `Current Taxes` | **`=-J75*J70`** — alíquota (`I75` = `0,34`) × EBT |
  | 76 (+) | `Extraordinary Items` | `=SUM(<+1>:<+2>)` |
  | 81 (=) | **`NET PROFIT`** | `=<−11> + <−9>` (histórico: `+ <−5>`) |
  | 87–89 | `DSCR1`, `DSCR2`, `DSCR3` | **rótulos sem fórmula** (placeholders) |

- **Gramática**: `P02`, `P05`, `P18` e uma **assimetria histórico × projeção** que é o padrão
  mais importante desta aba: **a mesma linha tem fórmula diferente nas colunas de histórico e
  nas de projeção**. `E42:E42` = `=E33−E35`; `F42:G42` = `=F33−F35+F44`;
  `H42:AD42` = `=H33−H34+H44`. Idem `EBIT` (61) e `NET PROFIT` (81). Motivo: no histórico
  algumas rubricas vêm da `Premissas` já líquidas.
- **Formatação**: total de bloco negrito com borda fina em cima e embaixo (`s32`, `s35`);
  histórico digitado em **azul** (`s145`, `s420`); projeção em preto (`s29`, `s52`); `numFmt 166`;
  hierarquia por recuo (`s19` nível 2, `s21` nível 3 itálico); linhas espaçadoras sem conteúdo.
- **Recursos**: painel congelado, `Print_Area`, agrupamento de colunas. Sem validação/gráfico.
- **Classificação**: `universal` inteira. Os rótulos de detalhe do histórico
  (`Fundo de reserva e Fundo de assist. de educ. e social`, linha 74) são **do setor de origem**.
- **Nota de estado**: 2 fórmulas com `#REF!` (`F17`, `G17`).

## 9. `Balance Sheet` — aba 7 · 1.275 fórmulas

**A aba central: é ela que dá nome a quase todas as contas do modelo (`P19`).**

- **Identidade**: 7ª, visível, `showGridLines=0`, zoom 85, `dimension C4:AD173`.
  **Congelado `xSplit=9 ySplit=7`** (`topLeftCell J23`). Larguras: A:B = 5;
  **C = 58,3** (rótulo, o mais largo do arquivo depois do `Output`); D = 3,55;
  **E:G ocultas**; H = 15,7; I:AD = 12,7. `Print_Area A1:K84`. Tem um **desenho**
  (`drawing2.xml`) ancorado em C73:C74 que carrega o único `image1.emf` do arquivo.
- **Anatomia**:

  | Linhas | Bloco | Fórmula do total |
  |---|---|---|
  | 10 | **`ASSETS`** | `=<+2> + <+17> + <+24>` (CA + LTA + Permanent) |
  | 12 | `Current Assets` | `=SUM(<+1>:<+8>)` |
  | 13 | `Cash & Short Term Inv.` | projeção: `='Cash Flow'!H59`; histórico: soma digitada (`=5417+112353+104210-102022`) |
  | 14–19 | 6 contas de giro do ativo | `='Working Capital'!<mesma linha −1, col −1>` |
  | 20 | `Other Non-Op. Cur. Assets` | `=SUM(<+1>:<+5>)` |
  | 27 | `Long-Term Assets` | `=SUM(<+1>:<+5>)` |
  | 34 | `Permanent` | `=SUM(<+1>:<+6>)` histórico / `<+7>` projeção |
  | 37 | `PP&E` | `='Fixed Assets & CAPEX'!<…> − <+1>` |
  | 44 | **`LIABILITIES & EQUITY`** | `=<+2> + <+19> + <+33> + <+29> + <+31>` |
  | 46 | `Current Liabilities` | `=SUM(<+1>:<+15>)` histórico / `<+1>:<+10>` projeção |
  | 47–52 | contas de giro do passivo | `='Working Capital'!<…>` |
  | 50 | `Bank Short Term` | `='ST Inv. & Debt'!<…>` |
  | 51/69 | `Tributos e contribuições a recolher - parcelamento` | `='Tributos a Recolher'!<…>` (curto e longo prazo) |
  | 63 | `Long-Term Liabilities` | `=SUM(<+1>:<+3>)` |
  | 64 | `LT Bank Debt` | `='ST Inv. & Debt'!<…>` |
  | 73 / 75 | `Minority Interest` / `Antecipated Results` | `=<coluna anterior>` |
  | 77 | `Shareholder's Equity` | `=SUM(<+1>:<+3>)` |
  | 80 | `Retained earnings` | `=<ant> + 'Income Statement'!<lucro> − <dividendos> + 'Cash Flow'!<…>` |
  | **83** | **`Mismatch`** | **`=<linha 10> − <linha 44>`** — o CHECK do balanço |
  | 89 | `Net Debt / LTM EBITDA` | rótulo sem fórmula |

- **Gramática**:
  - **`P12 CHECK`**: `E83:AD83` = `=E10−E44`, rótulo `Mismatch` em **negrito itálico
    sublinhado** com borda (`s108`). É o detector de erro do modelo, e é lido de volta por
    quatro abas: `ST Inv. & Debt!H4` = `='Balance Sheet'!J83`, `Working Capital!I4`,
    `Fixed Assets!H3`, `Cash Flow!H5`. **O mismatch é publicado no topo dos drivers** para que
    o analista veja o desequilíbrio sem sair da aba em que está mexendo.
  - **`P09 HERDA-ÚLTIMO`**: 14 linhas do balanço são `=<coluna anterior>` na projeção inteira
    (`Ativo Fiscal Diferido`, `Valores e bens`, `Conta-corrente com cooperados`, `Reserves`,
    `Capital`, `Provisões`, `Débitos diversos`…). **É a política default do modelo para conta
    que ninguém projetou: congela no último saldo.** Nunca zera, nunca extrapola.
  - **`P26 HISTÓRICO-COMO-SOMA-DIGITADA**: no histórico há fórmula com números literais
    (`=5417+112353+104210-102022`, `=25896`, `=664239`) — é a marca do papel de trabalho: a
    conciliação do balanço publicado ficou na própria célula.
- **Formatação**: `Current/Long-Term/Permanent` negrito (`s2`, `s337`); `ASSETS`/`LIABILITIES`
  negrito com borda (`s323`); histórico em **azul** só onde é digitado (`s402`) e **preto** onde
  é conciliação (`s328`, `s329`); projeção `s52`/`s29`; recuo de 1 e 2 níveis; `numFmt 166`.
- **Recursos**: painel congelado; `Print_Area`; um desenho com `image1.emf`; sem validação; sem
  formatação condicional. **Zero `#REF!`** — é a aba mais íntegra do arquivo.
- **Classificação**: estrutura `universal`; **13 rótulos são do setor de origem**:
  `Reserva Técnica`, `Créd. operações pl. de assist. à saúde`,
  `Despesas de comercialização diferidas`, `Aplicações de liquidez imediata e valores em
  trânsito`, `Conta-corrente com cooperados`, `Débitos de operações de assit. à saúde`,
  `Débitos de oper. assist. à saúde não rel. c/plano de saúde`,
  `Provisões técnicas de operações de assist. à saúde`,
  `Débitos com aquisição de carteira` (2×), `Recebimento antecipado`, `Bens destinados a venda`,
  `Empréstimos de coligadas`. **Do caso** (nem universal nem do setor):
  `Tributos e contribuições a recolher - parcelamento`.

## 10. `Working Capital` — aba 8 · 1.631 fórmulas

- **Identidade**: 8ª, visível, `showGridLines=0`, zoom 85, `dimension A2:AD101`.
  **Congelado `xSplit=8 ySplit=7`** (`topLeftCell I8`). `outlineLevelRow=1` **e**
  `outlineLevelCol=1`. Larguras: A = 3,55; **B = 31,6**; C = 9,9; **D:F ocultas**; G:AC = 10,4.
  **Linhas 10–34 agrupadas** (`outlineLevel=1`) — o miolo de cálculo é recolhível.
- **Anatomia** — quatro blocos, e o terceiro repetido 3× por cenário:

  | Linhas | Bloco | Conteúdo |
  |---|---|---|
  | 2–4 | controle | os 3 cenários (por referência ao `Revenues`), `C3` = dial, `I4:Q4` = `='Balance Sheet'!J83` (o `Mismatch`) |
  | 10–27 | **`BALANCE SHEET ACCOUNTS`** | 6 contas de ativo (13–18) e 7 de passivo (21–27), rótulo por `P19`; histórico = espelho do balanço; **projeção = `P08`** |
  | 29–33 | **`INCOME STATEMENT ACCOUNTS`** | `Net Revenues`, `COGS`, `SG&A` — as bases de giro, espelhadas do `Revenues` |
  | 35–52 | **`AVERAGE TENOR`** (ativos 37–42, passivos 46–52) | histórico calculado, projeção = `CHOOSE($C$3, …)` apontando para os 3 blocos abaixo |
  | 55–68 | bloco **`Base Case`** | 13 prazos; 1ª coluna de projeção = `=<último prazo histórico>`, resto = `=<coluna anterior>` |
  | 70–83 | bloco **`Client Case`** | `=<linha correspondente do Base>` |
  | 85–98 | bloco **`Stress Case`** | `=<linha correspondente do Client>` |
  | 100 | rodapé | fator de ajuste (`0,99773…`), digitado |

- **Gramática**:
  - **`P08 DIAS-DE-GIRO`** — o padrão central: projeção do saldo =
    `=<prazo médio do ano>/360*<conta de DRE do ano>`. Ex.: `I14` = `=I38/360*I31`
    (Reserva Técnica = prazo × Net Revenues). **A base é a linha de DRE correspondente
    (Net Revenues, COGS ou SG&A) — não a receita total do caso.**
  - **`P27 PRAZO-HISTÓRICO`**: `G38` = `=IF($G$31>0,G14/$G$31*360,)` — saldo ÷ base × 360, com
    guarda `IF(base>0)` e **`else` vazio** (a vírgula sem argumento). O prazo é *derivado do
    realizado*, não digitado.
  - **`P03`/`P04`**: `I38` = `=CHOOSE($C$3,I57,I72,I87)`.
  - **`P22 VARIAÇÃO-NO-FLUXO`** (definida aqui, consumida no `Cash Flow`): ativo →
    `=<ano−1> − <ano>`; passivo → `=<ano> − <ano−1>`. **O sinal depende do lado do balanço.**
  - **`360` é a base de dias** (não 365) — em todas as 26 linhas de prazo.
- **Formatação**: prazo em `numFmt 212` (uma decimal) — **azul** (`s343`) nos blocos de cenário
  (digitável) e **preto** (`s344`) na linha consolidada; saldo em `numFmt 166`; `Assets`/
  `Liabilities` negrito itálico (`s4`); rótulos herdados sem estilo próprio (`s0`).
- **Recursos**: painel congelado; agrupamento de linhas **e** colunas; sem validação; sem
  gráfico. Zero `#REF!`.
- **Classificação**: motor `universal`; as 13 contas são as **do setor de origem** herdadas do
  `Balance Sheet` via `P19`.
- **Achado relevante para a pendência aberta da sessão 32** (dupla contagem de caixa):
  **o Modelo Base NÃO projeta caixa por dias de giro.** As 6 contas de giro do ativo (linhas
  13–18) são `Aplicações de liquidez imediata`, `Reserva Técnica`, `Créd. operações`,
  `Despesas de comercialização diferidas`, `Títulos e créditos a receber`,
  `Outros valores e bens` — e **`Cash & Short Term Inv.` (`Balance Sheet` linha 13) está fora
  desta lista**. O caixa é projetado **só** pelo `Cash Flow` (`Balance Sheet!J13` =
  `='Cash Flow'!H59`), e a dívida **só** pelo `ST Inv. & Debt`. Cada conta tem **uma** origem.
  É a resposta que o prompt (§9) supôs que o mapa conteria.

## 11. `ST Inv. & Debt` — aba 9 · 3.573 fórmulas (a mais complexa)

- **Identidade**: 9ª, visível, `showGridLines=0`, zoom 85, `dimension A2:AK350`.
  **Congelado `xSplit=7 ySplit=7`** (`topLeftCell H8`). `outlineLevelRow=1`, `outlineLevelCol=1`.
  Larguras: A = 4,55; **B = 34,4**; **C oculta**; D:F = 10,7 (agrupadas); G = 12,4; H:AB = 10,7.
  **109 linhas com atributo de altura/oculta/outline**: 10–30 agrupadas; **67–109 ocultas**
  (as 43 linhas de `% Amt Issuance` do bloco de emissão).
- **Anatomia** — 13 faixas, 18 blocos nomeados:

  | Linhas | Bloco | Papel |
  |---|---|---|
  | 4–5 | controle | `H4:R4` = `='Balance Sheet'!J83` (`Mismatch`); `I5:O5` = 0,5…6,5 (meio-ano, para FRA) |
  | 10–15 | **`BALANCE SHEET ACCOUNTS`** | `End of the Period ST Investments`, `… Additional Leverage`, `… ST Debt`, `… LT Debt` |
  | 17–23 | **`INCOME STATEMENT ACCOUNTS`** | `Total Financial Income`, `Total Interest Expenses`, `Total FX Expense` (cash / non-cash) |
  | 25–29 | **`CASH FLOW ACCOUNTS`** | `Total FX Non-Cash Expense`, `Debt Issuance`, `Debt Amortization` |
  | 31–34 | **`END OF THE PERIOD FX`** | `BRL/USD` e `BRL/EUR` = `=Anual!S45` / `=Anual!S48` |
  | 37–47 | **`SHORT TERM INVESTMENTS - BRL`** | saldo inicial/variação/final + `Pre Curve` (%CDI), `Effective FRA`, `Effective Margin`, `Financial Income` |
  | 50–60 | **`ADDITIONAL LEVERAGE - BRL`** | o **revolver**: `REVOLVE AMOUNT`, `Minimum Cash` (`F54` = 70.000, entrada), curva, margem, `Interest Expense` |
  | 63–120 | **`DEBT ISSUANCE - BRL`** | emissão nova: 43 linhas `% Amt Issuance #0…#42`, `Periodical Standard Amortization`, `Final Balance`, `Benchmark`/`Curve`/`Mix`, `Flat Fee`, `Interest & Fee Expenses` |
  | 123–188 | **`DEBT #1…#4 - BRL`** (4 blocos de 16–18 linhas) | dívida existente por tranche |
  | 189–260 | **`FOREIGN CURRENCY DEBT #1…#4 - USD`** (4 × 18) | idem, com `FX Change`, `FX Loss/(Gain) - cash` e `- non-cash` |
  | 261–278 | **`FOREIGN CURRENCY DEBT #5 - EUR`** | idem em euro |
  | 279–340 | **`CAPEX FINANCING - BRL`** | `% CapEx Financed` × capex do `Fixed Assets`, com as mesmas 43 linhas de amortização, e a **quebra ST/LT** (`ST Bank Debt`, `LT Bank Debt`) |
  | 341–346 | **`Reconhecimento de Perdas Futuras`** | `Dívida Previdenciaria`: 7.500 amortizados a 25%/ano |

- **Gramática**:
  - **`P11 ROLAGEM-DE-SALDO`** por tranche: `Initial Balance` (ano) = `=Final Balance` (ano−1);
    `Amortization` = `=<%> × <saldo>`; `Final Balance` = `=Initial − Amortization`.
  - **`P14 AMORTIZAÇÃO-POR-SAFRA`** (43 linhas × 2 blocos): cada emissão anual tem sua própria
    linha de amortização, e a linha só começa a pagar na coluna do seu ano:
    `=IF(SUM($H127:G127)>=$H$126,0,$H$126*$F127)` — para de pagar quando o acumulado atinge o
    principal. No `CAPEX FINANCING` a variante tem o degrau final:
    `=IF(SUM(…)>=P,0,IF(P−SUM(…)<P×%,P−SUM(…),P×%))/2` (o `/2` é meio-ano de carência).
  - **`P15 CUSTO-COMPOSTO`**: `Effective Margin` = `=((1+<curva>)*(1+<margem>))-1` —
    composição, não soma. Para dívida com dois benchmarks:
    `=(((1+CDI)*(1+spread_CDI))-1)*<%CDI> + (((1+TJLP)*(1+spread_TJLP))-1)*<%TJLP>` (mix).
  - **`P28 JUROS-SOBRE-SALDO-MÉDIO`**: `=<fee> + AVERAGE(<saldo inicial>,<saldo final>) × <taxa>`
    — e no 1º ano `× <taxa>/2` ou `^((data−data_emissão)/365)` (pro rata efetivo).
  - **`P16 CURVA-MACRO` com FRA**: `=AVERAGE(Anual!<ano>:<ano+1>)/100` — a taxa do exercício é a
    média de dois anos da curva (forward de meio de ano), e o `I5:O5` = 0,5…6,5 é a régua disso.
  - **`P17 CAIXA-MÍNIMO-E-REVOLVER`**: `H51` =
    `=IF('Cash Flow'!H56+'Cash Flow'!H58 < $F$54, $F$54−('Cash Flow'!H56+'Cash Flow'!H58), 0)` —
    **se o caixa projetado fura o caixa mínimo, o modelo saca revolver automaticamente**; e o
    `Cash Flow!H59` aplica o piso: `=IF(H56+H58<$F$54_ST, $F$54_ST, H56+H58)`. É um circuito
    fechado deliberado (revolver ↔ caixa), a única quase-circularidade do modelo.
  - **`P29 CHAVE-DE-EFEITO-CAIXA`**: `D128` = `S`/`N` (validação de lista) decide se a
    amortização daquela tranche entra no fluxo: `Cash Flow!H51` =
    `='ST Inv. & Debt'!H28-(IF('ST Inv. & Debt'!D128="N",'ST Inv. & Debt'!H127,0))`.
  - **`P30 TOTAL-POR-SOMA-DE-ENDEREÇOS`**: `Total Interest Expenses` =
    `=-SUM(H60,H120,H138,H154,H170,H186,H202,H220,H238,H256,H274,H338)` — 12 endereços
    explícitos, um por bloco. **Acrescentar tranche exige editar este total** (é o preço do
    desenho por blocos).
  - `SUMPRODUCT` (1 ocorrência): `D131` = prazo médio ponderado da tranche.
- **Formatação**: entrada em **azul** (`s341`, `s343`, `s79`, `s457`, `s363`); calculado em
  preto; `%` em `0.00%`; saldo em `numFmt 166`/`174`; blocos separados por linhas vazias;
  cabeçalho de bloco negrito com borda (`s28`); a coluna F concentra as **premissas do
  instrumento** (margem, fee, % amortização, caixa mínimo, spot FX).
- **Recursos** — **as 3 únicas validações de dados do arquivo estão aqui**:

  | `sqref` | Tipo | Fórmula | O que restringe |
  |---|---|---|---|
  | `F43 F56 F180 F164 F148` | `list` | `$A$43:$A$44` | benchmark da curva (`%CDI` / `CDI+`) |
  | `F331` | `list` | `$A$331:$A$333` | benchmark do capex financing (`TJLP`…) |
  | `D128` | `list` | `"S,N"` | **`Efeito Caixa?`** da tranche (`P29`) |

  Também: painel congelado, agrupamento de linhas e colunas, `vmlDrawing2.vml`. Sem gráfico.
  10 fórmulas com `#REF!` (as menos afetadas em proporção: 0,3%).
- **Classificação**: `universal` inteira — dívida, revolver, FX e caixa mínimo não têm setor.
  **Do caso**: `Reconhecimento de Perdas Futuras` / `Dívida Previdenciaria` (341–346).

## 12. `Fixed Assets & CAPEX` — aba 10 · 1.785 fórmulas

- **Identidade**: 10ª, visível, `showGridLines=0`, zoom 85, `dimension A2:AB141`.
  **Congelado `xSplit=7 ySplit=7`** (`topLeftCell H15`). `outlineLevelRow=1`,
  `outlineLevelCol=1`. Larguras: A = 4,55; **B = 31,6**; C = 9,9; **D:E ocultas**; F:AB = 10,1.
  Linhas 10–33 e 49–75 agrupadas.
- **Anatomia** — 11 classes de ativo × 7 blocos:

  | Linhas | Bloco | Papel |
  |---|---|---|
  | 2–4 | controle | 3 cenários + `C3` = dial; `H3:O3` = `='Balance Sheet'!J83` |
  | 6 | **régua de idade** | `H6:AB6` = 1, 2, 3 … 21 (**digitados**) — é o argumento da janela de depreciação |
  | 10–24 | **`BALANCE SHEET ACCOUNTS`** | saldo bruto das 11 classes (`Terrenos`, `Edificações`, `Veículos`, `Máquinas e Equipamentos`, `Outros`, `Centro distribuição`, `Capex 7`…`Capex 11`) + `Assets Amortization` |
  | 26–28 | **`INCOME STATEMENT ACCOUNTS`** | `Depreciation` |
  | 30–33 | **`CASH FLOW ACCOUNTS`** | `CapEx`, `Depreciation` |
  | 35–47 | **`CAPEX`** | total + 11 linhas `=CHOOSE($C$3, <base>, <client>, <stress>)` |
  | 49–61 | **`DEPRECIAÇÂO CAPEX`** | 11 linhas com a janela `OFFSET` e a **vida útil em anos na coluna G** (7, 10, 10, 10, 10, 10, 1, 1, 1, 1, 1) |
  | 63–76 | **`DEPRECIAÇÂO HISTÒRICA`** | saldo herdado do balanço ÷ vida útil, constante |
  | 77–89 | **`DEPRECIAÇÂO TOTAL`** | `=<capex> + <histórica>` |
  | 91–98 | `Avaliação Patrimonial` / `Diferidos` | `Total Dep. Expense`, `% por ano`, `Prazo Amortização`, `Ágio Gerado` |
  | 101–141 | **3 blocos de cenário** (103–115, 116–128, 129–141) | `NEW CAPEX` por classe, com linha de total |

- **Gramática**:
  - **`P13 DEPRECIAÇÃO-POR-JANELA`** — o padrão mais denso do arquivo (14 `OFFSET`):
    `=SUM(OFFSET(H37,0,IF($H$6>$G51,-$G51,-H6),1,IF($H$6>$G51,$G51,H6)))*(1/$G51)`.
    Em português: *soma o capex dos últimos `min(idade, vida útil)` anos e divide pela vida
    útil*. É depreciação linear com janela deslizante, **sem tabela auxiliar** — o que explica
    por que a régua de idade (linha 6) e a vida útil (coluna G) precisam existir.
  - **`P11`**: saldo bruto = `=<ano anterior> + <capex do ano> − <baixa>`.
  - **`P04`**: `Client Case` = `=<Base>`, `Stress Case` = `=<Client>`.
  - `H92` = `=IF(G92-($G$93*$G92)<0,0,G92-($G$93*$G92))` — reavaliação com piso em zero.
- **Formatação**: capex por cenário em **azul** (`s341`) — é digitável; depreciação calculada em
  preto sobre branco sólido (`s338`); vida útil em azul na coluna G (`s144`, `s142`); totais
  negrito (`s340`); cabeçalho de bloco (`s28`).
- **Recursos**: painel congelado, agrupamento de linhas e colunas. Sem validação, sem gráfico,
  zero `#REF!`.
- **Classificação**: `universal`. Os nomes das classes (`Centro distribuição`, `Capex 7`…) são
  **placeholders genéricos**, não vocabulário de setor.

## 13. `Cash Flow` — aba 11 · 692 fórmulas

- **Identidade**: 11ª, visível, **grade visível**, zoom 85, `dimension A1:AB74`.
  **Congelado `xSplit=7 ySplit=7`** (`topLeftCell H23`). `outlineLevelCol=1`.
  **Linhas 1–4 ocultas.** Larguras: A = 1,33; **B = 29**; C = 1,44; **D:E ocultas**; F:AB ≈ 11.
  `Print_Area A1:N65`.
- **Anatomia** — o fluxo indireto:

  | Linhas | Bloco | Fórmula |
  |---|---|---|
  | 5 | controle oculto | `H5:Q5` = `='Balance Sheet'!J83` |
  | 10 | **`CASH FLOW FROM OPERATIONS`** | `=SUM(<+2>:<+9>)` |
  | 12–18 | `Net Income`, `Deferred Taxes`, `Depreciation`, `Amort. of Acquisition Goodwill`, `FX (Gain)/Loss`, `Equity Income & Others`, `Provisão Previdenciaria` | espelhos |
  | 19 | `Changes in Working Capital` | `=SUM(<+1>:<+13>)` |
  | 20–32 | 13 linhas de giro | rótulo `='Working Capital'!B13`; valor **`P22`**: ativo `=WC(ano−1)−WC(ano)`, passivo `=WC(ano)−WC(ano−1)` |
  | 34 | **`CASH FLOW FROM INVESTING`** | `=SUM(<+2>:<+5>)` |
  | 36–39 | `CAPEX` (`=-'Fixed Assets…'!H35`), `Sale of Fixed Assets`, `Investments`, `Changes in LT Assets` | |
  | 41 | **`FREE CASH FLOW`** | `=<linha 10> + <linha 34>` |
  | 43 | **`CASH FLOW FROM FINANCING`** | `=SUM(<+2>:<+11>)` |
  | 45–54 | dividendos, equity, revolver, capex lev, debt issuance/reduction, parcelamento tributário, partes relacionadas | espelhos de `Balance Sheet`, `ST Inv. & Debt`, `Goodwill` |
  | 56 | **`NET CHANGE IN CASH`** | `=<41> + <43>` |
  | 58 | `Beg. of the Period Cash` | `='Balance Sheet'!I13` (o único elo com o histórico) |
  | 59 | **`END OF PERIOD CASH & ST INV.`** | **`=IF(H56+H58 < 'ST Inv. & Debt'!$F$54, 'ST Inv. & Debt'!$F$54, H56+H58)`** — o piso do caixa mínimo |
  | 61–65 | `Required Cash`, `Short Term Investments`, `ADDITIONAL LEVERAGE Capex`, `ADDITIONAL LEVERAGE` | rótulos sem fórmula |

- **Gramática**: `P05`, `P18`, `P19`, **`P22`** (o sinal por lado do balanço) e **`P17`** (o piso
  de caixa mínimo, que fecha o circuito com o revolver).
- **Formatação**: seções em negrito com faixa (`s522`, `s524`); linhas de detalhe recuadas
  (`s486`, `s527`, `s530`); `numFmt 166`; rótulos herdados sem estilo (`s534`).
- **Recursos**: painel congelado, `Print_Area`, agrupamento de colunas, 4 linhas ocultas no
  topo. Sem validação, sem gráfico, zero `#REF!`.
- **Classificação**: `universal`; os 13 rótulos de giro herdam a classificação do
  `Balance Sheet`. **Do caso**: `Provisão Previdenciaria`,
  `Tributos e contribuições a recolher`, `Redução Partes Relacionadas`.

## 14. `Goodwill, Taxes & Div.` — aba 12 · 337 fórmulas

- **Identidade**: 12ª, visível, `showGridLines=0`, zoom 85, `dimension A7:AB71`.
  **Congelado `xSplit=7 ySplit=7`** (`topLeftCell H42`). `outlineLevelRow=1`,
  `outlineLevelCol=1`. Larguras: A = 4,9; **B = 39,1**; C = 4,9; **D:F ocultas**; G = 13,4;
  H:AB = 10,55. Linhas 10–26 agrupadas.
- **Anatomia**:

  | Linhas | Bloco | Conteúdo |
  |---|---|---|
  | 10–15 | **`BALANCE SHEET ACCOUNTS`** | `Deferred Taxes`, `Acquisition Goodwill`, `Retained Earnings`, `Dividends Payable` |
  | 17–20 | **`INCOME STATEMENT ACCOUNTS`** | `Current Taxes`, `Deferred Taxes` |
  | 22–25 | **`CASH FLOW ACCOUNTS`** | `Deferred Taxes`, `Dividends Paid` |
  | 27–32 | **`GOODWILL AMORTIZATION`** | saldo inicial, `%` por ano (7,5% → 15% → … com `=1-SUM(<anteriores>)` no último), amortização, saldo final |
  | 34–40 | **`DEFERRED TAX ASSETS`** | saldo inicial, `%` de amortização (10%), amortização, `New Deferred Taxes`, saldo final |
  | 42–48 | **`TAXES ON EBT`** | `EBT` (espelho), `Income Tax Rate` (histórico calculado, projeção **0,34 digitado**), `Deferred Tax`, `Current Income Tax`, `Effectice Tax Rate` (sic) |
  | 50–55 | **`DIVIDENDS`** | `Net Profit from Operations`, `Equity Income & Others`, `Dividends Payout` (%), `Dividends Payable` = `=IF((lucro+equity)×payout>0, (lucro+equity)×payout, 0)` |

- **Gramática**: `P11` (rolagem de saldo), `P05`, `P18`, **`P31 RESTO-PARA-FECHAR-100%`**
  (`O30` = `=1-SUM(H30:N30)` — a última parcela do cronograma é o que falta para 100%), e
  **`P32 DIVIDENDO-COM-PISO`** (`IF(...>0, ..., 0)` no histórico; sem piso na projeção,
  `N55:AB55` = `=(N52+N53)*N54`).
  `Income Tax Rate` histórico = `=G73/G70` do `Income Statement` (alíquota **realizada**);
  projeção = 0,34 digitado.
- **Formatação**: cabeçalho de bloco negrito com borda; `%` em `0.00%` azul quando digitado
  (`s51`, `s61`, `s386`); valores `numFmt 166`.
- **Recursos**: painel congelado, agrupamento; `vmlDrawing3.vml`. Sem validação, sem gráfico.
- **Estado**: **24 fórmulas com `#REF!`** (7% da aba) — `D7:F7` (cabeçalho de ano) e a linha 39
  `New Deferred Taxes` (`=$G6*('Revenues…'!#REF!+'Revenues…'!#REF!)`), que contamina o saldo
  final de imposto diferido (`I36:AB36` = `#REF!`). **O bloco de imposto diferido do Modelo
  Base está quebrado.**
- **Classificação**: `universal`.

## 15. `Anual` — aba 13 · 64 fórmulas, 2.636 valores

**É a base macro do modelo** — o equivalente exato das nossas abas `Macro` e `Macro (dados)`.

- **Identidade**: 13ª, visível, `showGridLines=0`, zoom 85 (`zoomScaleNormal=95`),
  `dimension A1:IV1337` (o `IV1337` é resíduo de formatação: **o conteúdo termina na linha
  127**). **Congelado `xSplit=11 ySplit=7`** (`topLeftCell L23`). `defaultColWidth=11,44`,
  `defaultRowHeight=10,2` (a menor do arquivo). Larguras: A = 25; **B:J ocultas** (1994–2002);
  K = 7,66; **L = 28,4**; M:AL ≈ 6,5–8,7. Merges: `W6:AD6`, `AE6:AL6`.
  `Print_Area A6:R107`.
- **Anatomia**: A = rótulo da variável, **B:AL = 1994 … 2030**, com `Q6` = `Projeções`
  (a partir de 2009 é projeção, e o estilo do cabeçalho muda: `s245` realizado → `s246`
  projetado).

  | Linhas | Grupo |
  |---|---|
  | 8–24 | **`PIB`** — crescimento real, por setor, por componente da demanda, índice, deflator, **crescimento nominal (linha 20)**, PIB em R$/US$, população, per capita |
  | 26–29 | `Atividade` — produção industrial, comércio varejista, carteira de crédito |
  | 33–37 | `Mercado de Trabalho` |
  | 39–42 | **`Inflação (% a.a.)`** — IPC-FIPE, **IPCA-IBGE (linha 41)**, IGP-M |
  | 44–48 | **`Taxa de Câmbio`** — **R$/US$ fim de período (45)**, variação, média, **R$/€ (48)** |
  | 50–60 | **`Taxa de Juros (% a.a.)`** — SELIC meta, SELIC efetiva, **CDI efetivo (53)**, **CDI fim de período (54)**, juros real por índice, TR, **TJLP (60)** |
  | 62–74 | `Contas Externas` |
  | 76–79 | `Contas Públicas` |
  | 81–94 | `Cenário Internacional` — EUA, Zona do Euro, Libor, USD/€, PIB mundial |
  | 97–100 | `Outros` — Risco País, IBOVESPA, barril de petróleo |
  | 102–107 | notas de rodapé numeradas (1 a 6), fonte da série |
  | 109–111 | **repique de câmbio** (`R$/US$ - eop`, `- média`, `Company`) usado pelo modelo |
  | 114–127 | **bloco de correlação** — `=CORREL(<receita da empresa>, <série macro>)`, com o comentário `Semelhanca entre crescimento da empresa e o crescimento do <setor>`; escolhe a série macro que melhor explica a receita |

- **Quem consome o quê** (o contrato desta aba):

  | Consumidor | Fórmula | Série |
  |---|---|---|
  | `Revenues` L11 (crescimento da receita) | `=Anual!T20/100` | crescimento nominal do PIB |
  | `Revenues` L46 (custo fixo) | `=H46*(1+Anual!T41/100)` | IPCA |
  | `ST Inv. & Debt` L33/L34 | `=Anual!S45` / `=Anual!S48` | câmbio fim de período USD / EUR |
  | `ST Inv. & Debt` L43/L56/L332 | `=AVERAGE(Anual!S54:T54)/100` | CDI (média de 2 anos = FRA) |
  | `ST Inv. & Debt` L114/L130/L333 | `=Anual!S60/100` | TJLP |
  | `ST Inv. & Debt` L196 | `=Anual!S86/100` | Libor 6 meses |
  | `ST Inv. & Debt` L199 | `=(Anual!S45-Anual!R45)/Anual!R45` | variação cambial |

- **Gramática**: `P16` (do lado do consumidor); aqui dentro, `=CORREL(...)` (2×),
  `=(1+<taxa>/100)` acumulado e `=<coluna anterior>` para estender projeção.
  **Todas as séries estão em pontos percentuais** (5,85 = 5,85%), e é por isso que **todo
  consumidor divide por 100**. Errar isso é errar por 100×.
- **Formatação**: fonte 8/9 (aba densa); cabeçalho de ano realizado × projetado com estilos
  distintos; grupos em negrito (`s248`); `numFmt` de 1 a 2 decimais; `A3` = `Voltar` (`s231`,
  um pseudo-link de navegação, sem hyperlink real).
- **Recursos**: painel congelado, 2 merges, `Print_Area`, `vmlDrawing4.vml`. Sem validação.
- **Classificação**: `universal` — é macro do Brasil, não de setor.

## 16. `Tributos a Recolher` — aba 14 · 34 fórmulas

- **Identidade**: 14ª (última), visível, **grade visível**, sem zoom customizado, sem
  congelamento. `dimension A1:L10`. Larguras: A:B = 10,3; C = 11,3; D+ = default.
- **Anatomia**: um cronograma de parcelamento tributário, **sem coluna de rótulo**.

  | Linha | Conteúdo |
  |---|---|
  | 1 | `Tributos a Recolher - Parcelamento` |
  | 3 | anos: `A3` = 2013 digitado, `B3:F3` = `=A3+1` → 2014…2018 |
  | 4 | parcela 1: 6.415 / 5.619 / 7.449 (digitados, só A:C) |
  | 5 | parcela 2: 16.987 digitado, e `C5:F5` = `=B5` (constante) |
  | 7 | **total do ano** = `=SUM(A4:A5)`, estendido de A **até L** (12 colunas) |
  | 9 | `A9` = `='Balance Sheet'!I69` — o saldo devedor do balanço (219.078) |
  | 10 | **saldo remanescente**: `A10` = `=A9-A7`, depois `=<anterior> − <total do ano>`, de A até **L** |

- **Gramática**: `P11` (rolagem de saldo) e `P05`. O consumo é nas duas pontas do passivo:
  `Balance Sheet!J51` = `='Tributos a Recolher'!A7` (curto prazo = parcela do ano) e
  `Balance Sheet!J69` = `='Tributos a Recolher'!A10` (longo prazo = remanescente).
- **Formatação**: preenchimento branco sólido (apaga a grade), `numFmt 174`/`166`, título
  negrito.
- **Recursos**: nenhum.
- **Classificação**: **do caso.** Um parcelamento tributário específico desta empresa. A
  *mecânica* (cronograma que alimenta curto e longo prazo do balanço) é universal e vale
  guardar; os valores e o número de parcelas não.
- **Defeito na referência, registrado**: os rótulos de ano param em `F3` (2018) mas as linhas 7 e
  10 calculam até **L** (2024, 12 anos), e `L10` fica **negativo (−4.249)** — o cronograma
  amortiza mais que o saldo. **É este defeito que abre o balanço da referência em 2020 e 2021**
  (§20.1). Não se replica um defeito: na fase 2 isto entra como *deliberadamente diferente*, com
  piso em zero.

---

## 17. Recursos do workbook — o que existe, e o que só parece existir

### 17.1 Nomes definidos: 1.044 no arquivo, **0 em uso**

Este é o achado que mais muda o plano. A linha do placar do §3 — *"Nomes definidos: 1.044 × 0,
ausente por completo"* — está **medindo sedimento, não funcionalidade**:

> **As categorias abaixo NÃO são disjuntas** — a soma delas passa de 1.044 porque um mesmo nome
> pode estar em duas (uma definição de relatório do Excel 4 que aponta para `#REF!`, um nome externo
> que também está quebrado). O que é disjunto, e é o que importa, são os **6 `_xlnm`** contra os
> **1.038 restantes**.

| Categoria | Quantos | O que é |
|---|---:|---|
| apontam para `#REF!` | **531** | faixa cuja aba de origem não existe mais |
| definições de relatório/macro do Excel 4 (`{#N/A,#N/A,FALSE,"model"}`) | **392** | herança do *Report Manager*, décadas atrás |
| apontam para **outra pasta de trabalho** (`[6]Comps!…`, `'PXR_6500'!…`) | **382** | vínculo com pastas que nunca vieram |
| `__123Graph_A` … | 26 | nomes de gráfico do **Lotus 1-2-3** |
| `\a`, `\b`, `\g`, `\p` | 4 | macros de tecla do Lotus |
| **`_xlnm.Print_Area`** | **6** | 5 áreas de impressão reais (`Output`, `Income Statement`, `Balance Sheet`, `Cash Flow`, `Anual`) + 1 quebrada |

- **462 nomes distintos**, 288 deles repetidos por escopo de aba (o mesmo nome definido 2 a 5
  vezes, uma por `localSheetId`) — sintoma clássico de cópia de aba entre pastas.
- **Nenhuma das 14.504 fórmulas referencia nome definido** (verificado por varredura de todos os
  identificadores de todas as fórmulas contra a lista de nomes: 0 casamentos).

**Consequência para o plano**: gerar 1.044 nomes definidos no nosso export **não aproximaria o
export do Modelo Base em nada que um analista possa apontar** — reproduziria lixo. O que tem
valor de replicação são as **5 áreas de impressão**. A fase 2 registra o resto como
*deliberadamente diferente, com motivo*.

### 17.2 Os 8 gráficos — todos no `Output`, todos de linha

Ancorados em `xl/drawings/drawing1.xml`, todos `lineChart`, todos alimentados pelas tabelas
laterais `AD18:AK28` e `AO11:BB44` do próprio `Output`:

| # | Título | Âncora (col/lin, base 0) | Séries |
|---|---|---|---|
| 1 | `Dívida com 2x Net Debt/Ebitda` | AC32 → AJ54 | 3 (um por cenário, `AE19:AK21`) |
| 2 | `Diferença Ebitda entre Cenários` | AX11 → BI24 | 3 (`AQ12:AX14`) |
| 3 | `Interest Coverage Ratio` | BR32 → CB55 | 4 (`AQ17:AW20`) |
| 4 | `Liquidez Seca` | AW45 → BK69 | 4 (`AS23:AX26`) — **uma série aponta para `Output!#REF!`** |
| 5 | `Net Debt/Ebitda` | AW70 → BK89 | 4 (`AS28:AX31`) |
| 6 | `EBITDA / INTEREST EXPENSE` | AO145 → AV165 | 4 (`AR33:AW36`) |
| 7 | `Total Debt / (EBITDA+WCC)` | AO168 → AU187 | 4 (`AR39:AW44`) |
| 8 | `Covenants Sugerido Vs Projetado (Net Debt / EBITDA)*` | BJ11 → BP23 | 2 (`AS17:AX18`) |

Padrão: **3 séries = os 3 cenários** (gráficos 1, 2), ou **4 séries = 3 cenários + o corte
sugerido do covenant** (3 a 8). Os nomes de série vêm de célula (`Output!$AP$12`), e vários
são montados por concatenação (`=$B$23&" "&AO23`).

### 17.3 A única imagem

`xl/media/image1.emf`, referenciada por `xl/drawings/drawing2.xml.rels`, ancorada no
**`Balance Sheet`** em C73:C74 (um `twoCellAnchor` de uma célula de altura). Um EMF — figura
vetorial colada, não logotipo de capa. Não carrega informação do modelo.

### 17.4 Validação de dados, formatação condicional, VML

- **Validações**: 3, todas no `ST Inv. & Debt` (§11). Nenhuma outra aba tem.
- **Formatação condicional**: **zero em todo o arquivo**. O `Mismatch` do balanço e o
  `Check Scenario` do `Output` **não** são coloridos por regra — são valores que o analista lê.
  (Nosso export tem 1 formatação condicional; é uma divergência *a nosso favor*, e é assim que
  vai para a tabela de conformidade.)
- **`vmlDrawing1..4.vml`**: formas legadas em `Output`, `ST Inv. & Debt`,
  `Goodwill, Taxes & Div.` e `Anual` — resíduo de comentário/botão de versões antigas do Excel.
- **`calcPr calcId=191029`**, `defaultThemeVersion=124226`, `codeName="ThisWorkbook"` **sem
  projeto VBA** (não é `.xlsm`).

### 17.5 Painéis congelados — a tabela completa

| Aba | `xSplit` | `ySplit` | `topLeftCell` | Última coluna travada |
|---|---:|---:|---|---|
| `Revenues, COGS & SG&A` | 8 | 7 | I34 | H (2011) |
| `Income Statement` | 9 | 7 | J53 | I (2011) |
| `Balance Sheet` | 9 | 7 | J23 | I (2011) |
| `Working Capital` | 8 | 7 | I8 | H (2011) |
| `ST Inv. & Debt` | 7 | 7 | H8 | G (2011) |
| `Fixed Assets & CAPEX` | 7 | 7 | H15 | G (2011) |
| `Cash Flow` | 7 | 7 | H23 | G (2011) |
| `Goodwill, Taxes & Div.` | 7 | 7 | H42 | G (2011) |
| `Anual` | 11 | 7 | L23 | K (2003) |
| `Considerações`, `Capa`, `Output`, `Premissas`, `Tributos a Recolher` | — | — | — | sem congelamento |

**A regra é uniforme**: congela até a **última coluna de histórico** e até a **linha 7** (o
cabeçalho de ano). O `ySplit=7` é o mesmo nas 10 abas congeladas.

---

## 18. Classificação consolidada `universal` × `do setor de origem` × `do caso` (§4)

O prompt pede a marcação binária `universal` / `do setor de origem`. O mapa encontrou um terceiro
grupo que não é nenhum dos dois — coisas específicas **deste mandato**, não do setor de saúde.
Registro os três, e para efeito da regra do §4 **`do caso` conta como não-universal: o rótulo não
se replica.**

| Bloco / elemento | Marcação | Observação |
|---|---|---|
| Eixo do tempo, dial de cenário, três blocos por cenário, espelho de contas, check do balanço, check de cenário | **universal** | é o motor; replica-se integralmente |
| Estrutura da DRE, do balanço, do fluxo indireto, do giro por dias, do capex/depreciação, da dívida por tranche, do revolver com caixa mínimo, dos impostos e dividendos | **universal** | idem |
| Base macro `Anual` (PIB, IPCA, câmbio, CDI, TJLP, Libor) e o contrato "/100" | **universal** | é macro do Brasil |
| Gramática de cores, recuos, `numFmt`, congelamento, áreas de impressão | **universal** | |
| `Premissas` linhas 6–7, 12–16, 18 (`Contraprest. efetivas…`, `Eventos conhecidos ou avisados`, `Recuperação de eventos…`, `Variação da provisão de eventos ocorridos e não avisados`, `Eventos indenizáveis líquidos`) | **do setor de origem** | vocabulário de operadora de plano de saúde |
| `Balance Sheet` / `Working Capital` / `Cash Flow` / `Output`: `Reserva Técnica`, `Créd. operações pl. de assist. à saúde`, `Despesas de comercialização diferidas`, `Aplicações de liquidez imediata e valores em trânsito`, `Conta-corrente com cooperados`, `Débitos de operações de assit. à saúde`, `Débitos de oper. assist. à saúde não rel. c/plano de saúde`, `Provisões técnicas de operações de assist. à saúde`, `Débitos com aquisição de carteira`, `Recebimento antecipado`, `Bens destinados a venda`, `Empréstimos de coligadas` | **do setor de origem** | 13 rótulos; digitados **uma vez** no `Balance Sheet` e herdados por `P19` |
| `Income Statement` L74 `Fundo de reserva e Fundo de assist. de educ. e social` | **do setor de origem** | |
| `Capa!C4` = `Unimed Rio` | **do caso** | nome da entidade |
| Aba `Tributos a Recolher` inteira + `Balance Sheet` L51/L69 | **do caso** | parcelamento tributário desta empresa |
| `ST Inv. & Debt` L341–346 `Reconhecimento de Perdas Futuras` / `Dívida Previdenciaria` | **do caso** | |
| `Cash Flow` L18/L49 `Provisão Previdenciaria`, L54 `Redução Partes Relacionadas` | **do caso** | |
| `Fixed Assets` L12–22 (`Terrenos`, `Edificações`, `Veículos`, `Máquinas e Equipamentos`, `Centro distribuição`, `Capex 7`…`11`) | **universal** | são placeholders genéricos, não setor |

**Contagem**: 14 rótulos do setor de origem e 4 blocos do caso, em **1** aba inteira
(`Tributos a Recolher`) e 5 abas parcialmente. Todo o resto é motor.

Isto confirma, com número, a hipótese (A) do §4 do prompt: **a distância que importa é de motor,
e o vocabulário de outra indústria cabe em 18 itens** — todos localizados, todos com endereço
neste mapa. Nenhuma decisão de replicação depende de resolver a ambiguidade antes: se a leitura
fosse (B), o trabalho seria o mesmo mais a cópia destes 18 itens.

---

## 19. Catálogo dos padrões nomeados (o que a fase 4 vai replicar)

| ID | Nome | Onde nasce | Onde se repete |
|---|---|---|---|
| `P01` | **EIXO-DO-TEMPO** (`EOMONTH` a partir de uma célula) | `Revenues!C5`, `D7:AC7` | herdado pelas 8 abas operacionais |
| `P02` | **CABEÇALHO-HERDADO** com deslocamento fixo de coluna | linha 7 de cada aba | 9 abas |
| `P03` | **DIAL-DE-CENÁRIO** (`C3 = Output!$G$2`, `CHOOSE($C$3,…)`) | `Output!G2` | 46 fórmulas em 3 abas |
| `P04` | **TRÊS-BLOCOS-DE-CENÁRIO** (2º e 3º nascem `=` do anterior) | `Working Capital` 55–98 | `Fixed Assets` 103–141 |
| `P05` | **TOTAL-DO-BLOCO** (`SUM` de faixa fixa com linhas reservadas) | `Income Statement` | todas |
| `P06` | **CRESCIMENTO** (`=ant*(1+premissa)`) | `Revenues!I10` | |
| `P07` | **PERCENTUAL-DA-RECEITA** (`=CHOOSE(…)*receita líquida`) | `Revenues!I41`, `I52` | |
| `P08` | **DIAS-DE-GIRO** (`=prazo/360*base do DRE`) | `Working Capital` 13–27 | |
| `P09` | **HERDA-ÚLTIMO** (`=coluna anterior`) | `Balance Sheet` (14 linhas) | política default |
| `P10` | **MÉDIA-DOS-DOIS-ÚLTIMOS** (`AVERAGE`) | `Revenues!I24` | premissa saída do realizado |
| `P11` | **ROLAGEM-DE-SALDO** (inicial + adição − baixa) | `ST Inv. & Debt`, `Fixed Assets`, `Goodwill`, `Tributos` | |
| `P12` | **CHECK** (`Mismatch`, `Check Scenario`) | `Balance Sheet!83`, `Output!67`, `Output!L3:L5` | publicado no topo de 4 drivers |
| `P13` | **DEPRECIAÇÃO-POR-JANELA** (`SUM(OFFSET(...))*(1/vida)`) | `Fixed Assets` 51–61, 97 | 14 `OFFSET` |
| `P14` | **AMORTIZAÇÃO-POR-SAFRA** (43 linhas `% Amt Issuance #k`) | `ST Inv. & Debt` 67–109, 283–325 | |
| `P15` | **CUSTO-COMPOSTO** (`((1+curva)*(1+margem))-1`, com mix) | `ST Inv. & Debt` | |
| `P16` | **CURVA-MACRO** (`Anual!<ano>/100`, FRA por `AVERAGE` de 2 anos) | `Revenues`, `ST Inv. & Debt` | |
| `P17` | **CAIXA-MÍNIMO-E-REVOLVER** (circuito fechado) | `ST Inv. & Debt!H51`, `Cash Flow!H59` | |
| `P18` | **ESPELHO-DA-CONTA** (3 blocos BS/IS/CF em cada driver) | 4 abas de driver | interface do modelo |
| `P19` | **RÓTULO-POR-REFERÊNCIA** (um rótulo, um lugar) | `Balance Sheet!C` | 4 abas |
| `P20` | **CONTADOR-INVISÍVEL** (coluna A, fonte branca) | `Income Statement`, `ST Inv. & Debt` | |
| `P21` | **SINAL-EM-COLUNA-PRÓPRIA** (`+`, `(-)`, `=`) | `Income Statement!B` | |
| `P22` | **VARIAÇÃO-DE-GIRO-NO-FLUXO** (sinal por lado do balanço) | `Cash Flow` 20–32 | |
| `P23` | **ROLAGEM-DE-TRANCHE + soma de trimestres** | `Output` 128–206 | 13 blocos (hoje `#REF!`) |
| `P24` | **ÍNDICE-HISTÓRICO-COM-GUARDA** (`IF(base>0,…,0)`) | `Revenues`, `Working Capital` | 851 `IF` |
| `P25` | **ÂNCORA-DO-HISTÓRICO** (verde `CCFFCC`, vem da `Premissas`) | `Revenues` 10, 34, 64 | |
| `P26` | **HISTÓRICO-COMO-SOMA-DIGITADA** (`=5417+112353+…`) | `Balance Sheet`, `Income Statement` | papel de trabalho na célula |
| `P27` | **PRAZO-HISTÓRICO** (`=IF(base>0,saldo/base*360,)`) | `Working Capital` 37–52 | |
| `P28` | **JUROS-SOBRE-SALDO-MÉDIO** (`AVERAGE(inicial,final)*taxa`) | `ST Inv. & Debt` | |
| `P29` | **CHAVE-DE-EFEITO-CAIXA** (`S`/`N` com validação) | `ST Inv. & Debt!D128` | lida pelo `Cash Flow` |
| `P30` | **TOTAL-POR-SOMA-DE-ENDEREÇOS** (12 endereços explícitos) | `ST Inv. & Debt` 20, 29; `Output` 209 | |
| `P31` | **RESTO-PARA-FECHAR-100%** (`=1-SUM(anteriores)`) | `Goodwill!O30` | |
| `P32` | **DIVIDENDO-COM-PISO** (`IF(...>0,...,0)`) | `Goodwill!H55` | |

---

## 20. O estado real da referência — 667 fórmulas quebradas

Não é possível ser "conforme" com um `#REF!`. Onde a referência está quebrada, a fase 2 tem de
registrar *deliberadamente diferente* e a fase 4 tem de **implementar o que a fórmula queria
fazer**, não copiá-la:

| Aba | `#REF!` | % da aba | O que está quebrado |
|---|---:|---:|---|
| `Output` | **627** | 17% | o bloco `DEBT & RATIOS` inteiro (128–206): os 33 `HLOOKUP`, os 13 rótulos de tranche e `DSCR2`. Apontavam para uma tabela de dívida que não existe mais |
| `Goodwill, Taxes & Div.` | 24 | 7% | `New Deferred Taxes` (L39) e, por contaminação, o saldo final de imposto diferido |
| `ST Inv. & Debt` | 10 | 0,3% | resíduos pontuais |
| `Revenues, COGS & SG&A` | 4 | 0,6% | `D61:G61`, `F17:G17` |
| `Income Statement` | 2 | 0,3% | `F17:G17` (linha `Deductions`) |
| demais 9 abas | 0 | — | íntegras |

### 20.1 O Modelo Base **não fecha o balanço a partir de 2020** — e a causa está rastreada

Este é o achado mais consequente do mapa, e ele sai do próprio `CHECK` da referência.
`Balance Sheet!E83:AD83` (`Mismatch` = ativo − passivo − PL), coluna por coluna:

| Colunas | Anos | `Mismatch` |
|---|---|---|
| E:R | 2007 – 2019 | **0** (fecha) |
| S | 2020 | **16.987** |
| T | 2021 | **33.974** |
| U:AC | 2022 – 2031 | **`#VALUE!`** |
| AD | 2032 | **`#DIV/0!`** |

São **duas causas independentes**, ambas confirmadas célula a célula:

1. **O desequilíbrio de 16.987 é o parcelamento tributário.** `Tributos a Recolher` amortiza uma
   parcela de **16.987/ano por 12 anos** (linhas 5 e 7, colunas A:L) contra um saldo devedor que
   só suporta 11 (`A9` = `='Balance Sheet'!I69` = 219.078). Em 2020 o passivo já foi a zero e a
   parcela continua saindo: `L10` fica **negativo (−4.249)** e o balanço abre exatamente
   16.987 em 2020 e 2 × 16.987 = 33.974 em 2021. O cronograma também rotula anos só até `F3`
   (2018) e calcula até `L` (2024) — o rótulo parou, a fórmula não.
2. **O `#VALUE!` é texto na base macro.** `Anual!AC86:AL86` (`Libor 6 meses (média)`, 2021 em
   diante) contém a **string `nd`**. `ST Inv. & Debt!S196` = `=Anual!AC86/100` → `#VALUE!`, e a
   cadeia propaga sem nenhuma guarda:

   ```
   Anual!AC86 = "nd"
     → ST!S196  Curve                       #VALUE!
     → ST!S198  Effective Margin            #VALUE!
     → ST!S202  Interest & Fee Expenses     #VALUE!   (× 5 tranches em moeda estrangeira)
     → ST!S20   Total Interest Expenses     #VALUE!
     → IS!U64   Financial Expenses          #VALUE!
     → IS!U63   Financial Result → U70 EBT → U72/U73 Income tax → U81 NET PROFIT   #VALUE!
     → BS!U80   Retained earnings → U44 LIABILITIES & EQUITY → U83 Mismatch        #VALUE!
   ```

   **Uma célula de texto na base macro apaga o resultado dos últimos 11 anos do modelo.** É a
   lição mais transferível do mapa para o nosso produto: em `Macro (dados)`, ano sem série tem
   de ser **vazio ou zero, nunca `nd`**, e o consumo tem de ter guarda.

Por que isso passou despercebido: **o horizonte visível do `Output` é 2010–2018** (colunas P:AB
ocultas, §5). O modelo quebra exatamente onde ninguém olha.

**Consequência direta para a fase 2**: dentro do horizonte publicado (2010–2018) o Modelo Base
fecha e é a régua legítima. Fora dele, **não existe conformidade a perseguir** — nossa geração
não deve copiar nem o parcelamento sem piso nem o consumo de macro sem guarda, e as duas coisas
entram como *deliberadamente diferente, com motivo escrito*.

### 20.1.1 Mais duas incoerências da referência, achadas na fase 2

Encontradas ao comparar aba a aba (`CONFORMIDADE.md`), e as duas mudam número:

1. **A base do prazo médio do passivo é medida num denominador e aplicada em outro.**
   `Working Capital!D46` = `=IF(D32>0,D21/D32*360,)` mede o prazo da conta de passivo contra o
   **CUSTO** (linha 32); `Working Capital!I21` = `=I46/360*I31` aplica o saldo projetado sobre a
   **RECEITA LÍQUIDA** (linha 31). O saldo projetado sai inflado na razão receita/custo — no próprio
   arquivo da referência, ~1,27×. Não é convenção: é defeito.
2. **A chave `Efeito Caixa?` (`D128`) não tem contrapartida.** Marcar `N` faz a amortização daquela
   tranche sair do fluxo de caixa (`Cash Flow!H51` desconta `ST!H127`) e o saldo da dívida cair
   igual — sem nada no ativo nem no patrimônio. Uma redução de passivo sem saída de caixa precisa de
   contrapartida (conversão em participação, perdão, capitalização), senão o balanço abre exatamente
   no valor reperfilado. É uma das razões pelas quais o `Mismatch` dela não é confiável.

### 20.2 Defeitos menores, registrados e **não** replicados

1. **`Revenues!H39`** contém a string `,` (uma vírgula) numa linha de percentual, onde as
   vizinhas têm `=G38/G34`. A célula foi digitada por acidente e ficou.
2. `Effectice Tax Rate` (`Goodwill!B48`) e `DEPRECIAÇÂO CAPEX` / `DEPRECIAÇÂO HISTÒRICA`
   (`Fixed Assets!B49`, `B63`) — erros de digitação nos rótulos.
3. `ST Inv. & Debt!A341` = `DívidDívida Previdenciaria` (texto duplicado).
4. `Income Statement!C11` repete o rótulo do próprio bloco (`Gross Revenues` dentro de
   `GROSS REVENUES`), com `Item 2`…`Item 5` abaixo — o primeiro item nunca foi renomeado.
5. `Considerações!B11` anuncia `Stress Case  (Ainda a definir)` — o terceiro cenário do arquivo
   de referência **nunca foi preenchido**.

---

## 21. O que este mapa cobre, e o que declara não cobrir

**Coberto para as 14 abas** (fase 1 completa): identidade (posição, estado, `dimension`, painel
congelado, largura de coluna, altura de linha relevante, ocultação e agrupamento), anatomia
(blocos com linha inicial e final), gramática das fórmulas (32 padrões nomeados, com endereço de
origem), formatação (`numFmt`, negrito/itálico, cor de fonte e de preenchimento **com o
significado de cada cor**, bordas, recuo), recursos (validações, formatação condicional, merges,
gráficos com tipo/série/âncora, imagem, nomes definidos, áreas de impressão, VML) e a
classificação `universal` / `do setor de origem` / `do caso`.

**Declarado não coberto** — e é decisão consciente, porque nada disso muda o que a fase 4
escreve:

1. **Valor célula a célula das 5.201 constantes.** O mapa registra *que* a célula é entrada
   (pela cor azul) e *o que ela alimenta*; não tabela os 2.636 números da `Anual` nem os 728 do
   `ST Inv. & Debt`. Eles são dado do caso, não motor.
2. **Cada uma das 3.693 fórmulas do `Output`, uma a uma.** O §7 pede o padrão, não a lista, e o
   `Output` são 5 padrões (`P22`, eixo próprio, índice-razão, `P23`, `P30`) aplicados em 207
   linhas. As 627 quebradas estão contadas e localizadas por bloco.
3. **Layout de impressão além da `Print_Area`** (margens, escala, orientação, cabeçalho/rodapé) —
   não lido. Se o dono imprimir o modelo, isto volta na fase 2.
4. **Conteúdo gráfico do `image1.emf`** e das 4 `vmlDrawing` — são resíduo visual sem informação
   de modelo.
5. **`Anual` linhas 114–127** (bloco de correlação): a mecânica está mapeada (`CORREL` entre a
   receita da empresa e cada série macro, para escolher a série que explica a receita), mas
   **qual série foi escolhida neste arquivo** não foi rastreada célula a célula.
6. **Comparação com o nosso export**: é a fase 2, e este documento é fase 1. Nada aqui afirma o
   que nós fazemos ou deixamos de fazer — exceto os dois pontos em que a medição do §3 do prompt
   já dava o número (nomes definidos e gráficos), onde o mapa mostra que **a interpretação do
   número mudou** (§17.1).

---

## 22. Quatro consequências deste mapa para o plano (entram na fase 3)

0. **O `CHECK` do balanço não pode ser comparado ano a ano contra a referência**, porque a
   referência só fecha até 2019 (§20.1). A régua legítima é o **horizonte publicado, 2010–2018**.
   Isso muda o teste da fase 5: o invariante a escrever em `verificar-export.mts` é *"o
   `Mismatch` fecha em todos os anos do horizonte publicado"*, e ele é **mais forte** que o do
   Modelo Base — o que é o resultado certo, não uma divergência a corrigir.


1. **A dupla contagem de caixa e de dívida (aberta desde a sessão 32) tem resposta na
   referência**, e é a do §10: **uma conta, uma origem**. No Modelo Base o caixa **não** entra
   no giro (as 6 contas de giro do ativo excluem `Cash & Short Term Inv.`), a dívida vive só no
   `ST Inv. & Debt`, e o balanço só *lê* os dois. O nosso `Working Capital` projeta todas as
   contas de `ativo_circulante` inclusive caixa — é divergência de **mecanismo**, com correção
   conhecida.
2. **O placar do §3 precisa de duas colunas novas**: `#REF!` e "em uso". Sem elas, "1.044 nomes
   definidos" e "3.693 fórmulas no `Output`" pedem trabalho que reproduziria lixo (1.044 nomes,
   0 em uso) ou fórmula quebrada (627 das 3.693). A meta honesta do `Output` é **3.066
   fórmulas** (as que funcionam) mais a reimplementação do bloco de tranches a partir do que ele
   *queria* fazer (`P23`).
3. **A ordem natural da fase 4 é a ordem do fluxo de dados, não a do tamanho do buraco**:
   `Premissas`/eixo do tempo → `Revenues` (define `P01`, `P03`, `P06`, `P07`, `P10`) →
   `Working Capital` (`P08`) → `Fixed Assets` (`P13`) → `ST Inv. & Debt` (`P11`, `P14`, `P15`,
   `P17`) → `Income Statement` → `Balance Sheet` (+ `P12`) → `Cash Flow` (`P22`) →
   `Goodwill` → `Output` (que é só vista) → `Considerações`/`Capa`. Começar pelo `Output`, que é
   o maior buraco, seria construir a vitrine antes do motor: **toda fórmula dele é referência a
   outra aba.**

---

*Fase 1 concluída para as 14 abas. Próximo passo: `docs/referencia/CONFORMIDADE.md` (fase 2),*
*que compara aba a aba contra um export real gerado por `portal/scripts/gerar-export-do-banco.mts`.*
