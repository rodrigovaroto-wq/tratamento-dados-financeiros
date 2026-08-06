# Conformidade — o export da Oria contra o Modelo Base

Fase 2 de `docs/PROMPT_ESPELHAR_MODELO_BASE.md`: comparar aba a aba, com veredito.
A referência é `docs/referencia/modelo-base.xlsx`, mapeada em `MAPA_MODELO_BASE.md`.
O nosso artefato é o `.xlsx` gerado por `portal/scripts/gerar-export-do-banco.mts` contra a fixture
do caso real v35 (`db/test/fixture_modelagem_v35.sql` + `db/roteiro_modelagem_v35.sql`).

**O objetivo declarado pelo dono nesta rodada:** *idêntico ao modelo de referência em motor, com a
cara da Oria, e melhor que ele — corrigindo os defeitos dele e ficando mais equilibrado e coerente
como modelo institucional.* Toda linha desta tabela é julgada por esse critério, e não por
semelhança visual.

---

## 1. O placar, remedido nesta rodada

### 1.1 Contagem absoluta de fórmulas

| Aba | Referência | Nosso ANTES | Nosso AGORA | Δ |
|---|---:|---:|---:|---:|
| `Considerações` | 3 | 1 | 1 | — |
| `Capa` | 0 | 0 | 1 | +1 |
| `Output` | 3.693 | 101 | **397** | **+296** |
| `Revenues, COGS & SG&A` | 664 | 321 | 333 | +12 |
| `Premissas` | 15 | 6 | 6 | — |
| `Income Statement` | 738 | 108 | 114 | +6 |
| `Balance Sheet` | 1.275 | 260 | 261 | +1 |
| `Working Capital` | 1.631 | 1.231 | **1.059** | **−172** |
| `ST Inv. & Debt` | 3.573 | 236 | **441** | **+205** |
| `Fixed Assets & CAPEX` | 1.785 | 204 | **324** | **+120** |
| `Cash Flow` | 692 | 75 | 86 | +11 |
| `Goodwill, Taxes & Div.` | 337 | 36 | 42 | +6 |
| `Anual` | 64 | 0 | 5 | +5 |
| `Tributos a Recolher` | 34 | 81 | 87 | +6 |
| **TOTAL** | **14.504** | **2.660** | **3.157** | **+497** |

A queda de 172 no `Working Capital` é **correção, não regressão**: são as fórmulas de giro do
caixa e da dívida bancária, que estavam contando as mesmas contas duas vezes (§3.8).

### 1.2 A medida honesta: densidade de fórmula por coluna de ano

A contagem absoluta compara **6 colunas de ano contra 26**. O Modelo Base projeta 21 exercícios
(2012–2032) para uma empresa; o caso v35 projeta 5 (2026–2030), porque foi o que o dono configurou
na tela de Modelagem. Contagem absoluta mede horizonte, não motor.

| Aba | ref: fórmulas/coluna | nosso: fórmulas/coluna | densidade |
|---|---:|---:|---:|
| `Revenues, COGS & SG&A` | 26 | 56 | 217% |
| `Premissas` | 2 | 6 | 360% |
| `Income Statement` | 28 | 19 | 67% |
| `Balance Sheet` | 49 | 44 | 89% |
| `Working Capital` | 63 | 176 | 281% |
| `ST Inv. & Debt` | 143 | 74 | 51% |
| `Fixed Assets & CAPEX` | 71 | 54 | 76% |
| `Cash Flow` | 28 | 14 | 52% |
| `Goodwill, Taxes & Div.` | 13 | 7 | 52% |
| `Output` | 168 (139 sem os `#REF!`) | 66 | 39% (47%) |
| `Anual` | 2 | 1 | 48% |
| `Tributos a Recolher` | 3 | 14 | 512% |
| `Considerações` | 3 | 1 | 33% |
| **TOTAL** | **598** | **533** | **89%** |

**89% da densidade de fórmula do Modelo Base, por coluna.** O "temos ~20%" do §3 do prompt era,
em ~4/5, diferença de horizonte. O que sobra de motor está concentrado em quatro abas, na ordem:
`Output` (39%), `ST Inv. & Debt` (51%), `Cash Flow` (52%), `Goodwill` (52%).

### 1.3 Recursos de planilha

| Recurso | Referência | Nosso ANTES | Nosso AGORA | Veredito |
|---|---:|---:|---:|---|
| Abas do modelo | 14 | 14 | 14 | **conforme** |
| Abas de proveniência | 0 | 14 | 14 | **deliberadamente diferente** (§4.1) |
| **Gráficos** | 8 | **0** | **8** | **conforme** |
| Imagens | 1 (`.emf` no `Balance Sheet`) | 0 | 0 | **deliberadamente diferente** (§4.2) |
| Nomes definidos | 1.044 (**0 em uso**) | 0 | 14 (**14 em uso**) | **deliberadamente diferente** (§4.3) |
| Áreas de impressão | 5 | 0 | **14** | **melhor que a referência** |
| Validação de dados | 3 | 1 | **10** | **conforme + melhor** |
| Formatação condicional | 0 | 1 | **8** | **melhor que a referência** |
| Painéis congelados | 9 das 14 | 11 | **13** | **melhor que a referência** |
| Fórmulas com `#REF!`/`#VALUE!` | **667** | 0 | **0** | **melhor que a referência** |
| Balanço que fecha | até 2019 (de 26 anos) | não fechava | **todos os anos** | **melhor que a referência** |
| Tamanho do arquivo | 0,5 MB | 4,3 MB (defeito) | 0,3 MB | **corrigido** (§3.9) |

---

## 2. Conformidade por aba

Legenda: **C** conforme · **D** divergente (temos de mudar) · **X** deliberadamente diferente ·
**A** ausente.

### 2.1 `Considerações`

| Elemento | A referência faz | Nós fazemos | ✓ | Impacto |
|---|---|---|---|---|
| Matriz 3 cenários × 4 premissas | cabeçalho vermelho + 3 linhas de cenário por referência ao `Output`, células de texto em branco com 77pt de altura | **mesma anatomia**, com o fato conhecido (premissa ativa, origem) já escrito e o "(justificar aqui)" | C | — |
| Merge do cabeçalho | `B8:F8` | 10 merges (blocos de texto) | X | cosmético |
| Cenário ativo | não tem | `CHOOSE(Output!$G$2,…)` por fórmula | melhor | — |
| Divergências de método | não tem | 6 declaradas, uma por linha | melhor | — |
| Gramática de cores | não documenta | legenda das 4 cores | melhor | — |
| Haircut do Stress | não existe (o 3º cenário da referência está em branco: "Ainda a definir") | `$F$8`, a única célula que define o cenário 3 | X | — |

### 2.2 `Capa`

| Elemento | A referência faz | Nós fazemos | ✓ | Impacto |
|---|---|---|---|---|
| Conteúdo | 2 células de texto (`Unimed Rio`, `Projeções Financeiras`) | faixa institucional ORIA, entidade, produto do mandato, exercícios, cenário ativo por fórmula, legenda de cores, 4 notas de leitura | X (melhor) | — |
| Identidade visual | nenhuma | grafite `1E293B` + acento `0E7490`, Arial | **é a "cara da Oria"** | — |
| Vocabulário | nome da operadora de saúde | entidade do caso | X | §4.4 |

### 2.3 `Output` — a maior distância que resta

| Elemento | A referência faz | Nós fazemos | ✓ | Impacto |
|---|---|---|---|---|
| `SCENARIO` + dial em `G2` | `G2` = 1/2/3, legenda em `B3:B5` | idem, com validação de lista e nota | C | — |
| `Check Scenario` | `I2:L5` lê o `C3` de 3 abas | lê o dial de **4** abas + coluna "DIVERGE" | C (melhor) | estrutural |
| `SUMMARY` | 20 linhas | 9 linhas | D | estrutural |
| `BALANCE SHEET` espelhado | 39 linhas, conta a conta | 9 linhas (grupos) | D | estrutural |
| `INCOME STATEMENT` espelhado | 27 linhas | 13 linhas | D | estrutural |
| `CASH FLOW` espelhado | 28 linhas | 8 linhas | D | estrutural |
| `DEBT & RATIOS` | 13 blocos de tranche × 6 linhas — **todo em `#REF!`** | 10 linhas a partir do espelho da dívida | X | §4.5 |
| `RATIOS` | 8 índices, `DSCR2` em `#REF!` | 13 índices, **com corte de covenant e teste de rompimento ao lado** | C (melhor) | — |
| Tabelas laterais de covenant | `AO11:BB44`, 3 cenários × 4 índices, valores colados | corte por índice como premissa editável | X | — |
| 8 gráficos de linha | `AD/AO` → 8 `lineChart` | **8 `lineChart`**, 4 deles com o corte tracejado | C | — |
| Eixo do tempo | ano inteiro (2010…2031), horizonte visível 2010–2018, P:AB **ocultas** | data herdada da raiz, todas as colunas visíveis | X | §4.6 |
| Diagnóstico por exercício | não tem | linha `CHECK_TXT` com o pior problema do ano | melhor | — |

### 2.4 `Revenues, COGS & SG&A`

| Elemento | A referência faz | Nós fazemos | ✓ | Impacto |
|---|---|---|---|---|
| `P01` eixo do tempo | `C5` + 2 recorrências de `EOMONTH` | **idem** (implementado nesta rodada) | C | estrutural |
| `P03` dial | `C3 = Output!$G$2` | `E1 = Output!$G$2` | C | cosmético (endereço) |
| `P06` crescimento | `=ant*(1+CHOOSE($C$3,…))` | **idem** | C | — |
| `P07` % da receita | `=CHOOSE(…)*receita líquida` | **idem** | C | — |
| `P10` média dos dois últimos | `=AVERAGE(G24:H24)` | idem, no histórico | C | — |
| `P16` curva macro | `=Anual!T20/100` | `=N(Anual!<CDI>/100)` — **com guarda** | C (melhor) | §4.7 |
| `P25` âncora do histórico | `=Premissas!B9`, fundo verde | `='Premissas'!<linha>`, fundo cinza | C | cosmético |
| Blocos `Item 2..5` reservados | 5 linhas por rubrica, vazias | as linhas REAIS do caso | X | §4.8 |
| Custo fixo por inflação | `=ant*(1+Anual!IPCA/100)` | idem, via premissa `indice_macro` | C | — |
| Depreciação de volta no EBITDA | `+ Depreciação` na linha 57 | **corrigido nesta rodada** — a linha existia e nunca era preenchida | C | **de resultado** |

### 2.5 `Premissas`

| Elemento | A referência faz | Nós fazemos | ✓ | Impacto |
|---|---|---|---|---|
| Anos | `B4` e `C4` digitados, `D4:J4 = C4+1` | primeiro digitado, resto `=ant+1` | C | — |
| Conteúdo | DRE de operadora de saúde, 2 anos colados | as linhas EXTRAÍDAS do caso, com proveniência por célula | X | §4.4 — **é a razão de o sistema existir** |
| Subtotais | `=SUM(B6:B7)` | soma célula a célula dos rótulos classificados | C | — |
| Horizonte | 9 colunas (2010–2018), 7 sem dado | só os exercícios realizados | X | cosmético |

### 2.6 `Income Statement`

| Elemento | A referência faz | Nós fazemos | ✓ | Impacto |
|---|---|---|---|---|
| Cascata | GROSS → NET → GP → EBITDA → EBIT → EBT → NET PROFIT | **mesma cascata, mesmos nomes** | C | — |
| `P21` sinal em coluna própria | `B` com `+`, `(-)`, `=` | idem | C | — |
| `P20` contador invisível | `A` = `=A_ant+1`, fonte branca | não temos | X | cosmético — a `Grade` resolve por âncora, não por número de linha |
| Detalhe de 5 linhas por rubrica | `Item 1..5` reservados | as linhas reais do caso | X | §4.8 |
| Assimetria histórico × projeção | a MESMA linha tem fórmula diferente no histórico e na projeção (`EBITDA`, `EBIT`, `NET PROFIT`) | **temos** (resultado financeiro e tributo vêm da extração no realizado e do motor no projetado) | C | — |
| Alíquota | `=-J75*J70` (34% digitado) | `=-MAX(0,EBT)*alíquota` — **só sobre lucro positivo** | C (melhor) | de resultado |
| `DSCR1/2/3` | 3 rótulos SEM fórmula | os índices vivem no `Output`, com fórmula | X | — |

### 2.7 `Balance Sheet`

| Elemento | A referência faz | Nós fazemos | ✓ | Impacto |
|---|---|---|---|---|
| `P12` CHECK (`Mismatch`) | `=E10-E44`, negrito itálico sublinhado | `=ATIVO-PASSIVO_PL` + linha de diagnóstico em texto + **formatação condicional** | C (melhor) | — |
| CHECK publicado nos drivers | 4 abas leem `BS!J83` no topo | não fazemos | **D** | estrutural — está na fila |
| `P09` herda-último | 14 contas `=coluna anterior` | idem, para conta sem premissa | C | — |
| Caixa | `='Cash Flow'!H59` (uma origem) | idem | C | — |
| Dívida | de `ST Inv. & Debt`, dividida CP/LP | do **espelho** da aba de dívida | C (melhor) | — |
| `P26` histórico como soma digitada | `=5417+112353+104210-102022` na célula | valor extraído, com a proveniência na nota | X (melhor) | — |
| Ordem dos grupos | AC → LTA → Permanent → PC → LTL → MI → PL | AC → ANC → PC → PNC → PL | X | cosmético |
| Contrapartida do reperfilamento | não tem | `REPERFILAMENTO` no PL | melhor | **de resultado** — sem ela o balanço abre |

### 2.8 `Working Capital` — onde estava o defeito mais caro

| Elemento | A referência faz | Nós fazemos | ✓ | Impacto |
|---|---|---|---|---|
| **Caixa no giro** | **NÃO projeta caixa por dias de giro** | **corrigido nesta rodada** (era o defeito aberto desde a sessão 32) | C | **de resultado** |
| **Dívida bancária no giro** | não está no giro | **corrigido nesta rodada** — estava, e voltava por `DIVIDA_CP` | C | **de resultado** |
| `P08` dias de giro | `prazo/360 × linha de DRE` | idem, base 360 | C | — |
| Base do prazo | **incoerente**: mede o passivo contra o CUSTO (`D46`) e aplica o saldo sobre a RECEITA (`I21`) | mesma base nas duas pontas — fornecedor contra CUSTO, o resto contra RECEITA LÍQUIDA | **melhor** | **de resultado** (§4.9) |
| `P27` prazo histórico | `=IF(base>0,saldo/base*360,)` | idem | C | — |
| `P04` três blocos de cenário | 3 blocos de 13 linhas, 2º e 3º `=` do anterior | 2 linhas por conta (base e stress), `CHOOSE` escolhendo | X | cosmético — mesma semântica em 1/3 das linhas |
| Espelho `P18` | 3 blocos no topo | **implementado nesta rodada** | C | estrutural |

### 2.9 `ST Inv. & Debt` — a segunda maior distância

| Elemento | A referência faz | Nós fazemos | ✓ | Impacto |
|---|---|---|---|---|
| Espelho `P18` (BS/IS/CF) | 3 blocos, 9 linhas | **implementado**, 8 linhas | C | estrutural |
| `SHORT TERM INVESTMENTS` | saldo + curva + FRA + margem + receita financeira | **implementado** como decomposição do caixa | C | — |
| `ADDITIONAL LEVERAGE` (revolver) | curva + margem + juros, acionado por caixa mínimo | **idem**, com o circuito `P17` fechado | C | — |
| `DEBT ISSUANCE` por safra (`P14`) | 43 linhas `% Amt Issuance #k` | **implementado**: uma safra por ano projetado, com carência e prazo | C (mais legível) | — |
| `P15` custo composto | `((1+curva)*(1+margem))-1` | **idem**, e o spread é DERIVADO do custo medido no mapa | C (melhor) | — |
| `P28` juros sobre saldo médio | `AVERAGE(inicial,final)*taxa` | sobre saldo de ABERTURA | X | §4.10 (circularidade) |
| `P29` chave de efeito caixa | validação `"S,N"` em uma célula | **uma por tranche**, e com **contrapartida no PL** | C (melhor) | de resultado |
| 4 tranches BRL + 5 em moeda estrangeira | blocos fixos, com FX | uma tranche por linha de dívida do caso; câmbio publicado mas sem tranche em USD | **D** | estrutural — está na fila |
| `CAPEX FINANCING` | % do capex financiado, com cronograma | não temos | **A** | estrutural — está na fila |
| Fonte das tranches | tabela colada | mapa de dívida **ou** as linhas de dívida do balanço | melhor | **de resultado** (§4.11) |
| `P30` total por soma de endereços | 12 endereços explícitos | soma por termos explícitos | C | — |

### 2.10 `Fixed Assets & CAPEX`

| Elemento | A referência faz | Nós fazemos | ✓ | Impacto |
|---|---|---|---|---|
| Espelho `P18` | 3 blocos | **implementado** | C | estrutural |
| `P13` depreciação por janela | `SUM(OFFSET(...))*(1/vida)` com régua de idade e vida por classe | linear sobre abertura + meia safra do capex | X | §4.12 |
| Rateio da depreciação por classe | por classe, com vida própria | por participação, **com resíduo na última classe** | C (melhor) | **de resultado** (§4.13) |
| 11 classes fixas | `Terrenos`…`Capex 11` | as classes de imobilizado do caso | X | §4.8 |
| `P04` três blocos de cenário | 3 blocos de 11 linhas | `CHOOSE` com corte no stress | X | cosmético |
| Vida útil | uma por classe (coluna G) | uma média por caso | **D** | estrutural — exige laudo que o Kit Básico não tem |

### 2.11 `Cash Flow`

| Elemento | A referência faz | Nós fazemos | ✓ | Impacto |
|---|---|---|---|---|
| Fluxo indireto | FCO → FCI → FCL → FCF → variação → caixa | **mesma estrutura, mesmos nomes** | C | — |
| `P22` variação de giro | ativo `ant−atual`, passivo `atual−ant` | via `VAR_NCG` do espelho, sinal invertido | C | — |
| 13 linhas de giro individuais | uma por conta, rótulo por referência | uma linha agregada | **D** | cosmético/estrutural |
| `P17` piso do caixa mínimo | `IF(caixa<mín, mín, caixa)` | `FURO` + revolver, com o furo VISÍVEL | C (melhor) | — |
| Captação de dívida | `Debt Issuance` do `ST` | **implementada nesta rodada** | C | de resultado |
| Dividendos | `=-BS!Dividends Payable` | premissa, zero por padrão, com convenção de sinal declarada | C | — |

### 2.12 `Goodwill, Taxes & Div.`

| Elemento | A referência faz | Nós fazemos | ✓ | Impacto |
|---|---|---|---|---|
| Blocos BS/IS/CF | 3 blocos de espelho | não temos (a aba é lida diretamente) | **D** | estrutural |
| Amortização de ágio | cronograma com `P31` (resto para fechar 100%) | linhas existem, zeradas (sem ágio no caso) | C | — |
| Imposto diferido | bloco com `New Deferred Taxes` — **em `#REF!`** | não temos | X | §4.14 |
| `TAXES ON EBT` | alíquota realizada no histórico, 34% na projeção | alíquota efetiva calculada + premissa | C | — |
| `P32` dividendo com piso | `IF((lucro)*payout>0,…,0)` | `=MAX(0,lucro)*payout` | C | — |

### 2.13 `Anual`

| Elemento | A referência faz | Nós fazemos | ✓ | Impacto |
|---|---|---|---|---|
| Base macro | 90 séries do Brasil, 1994–2030, coladas de consultoria | 7 séries de `indice_macro_obs` + Focus, **versionadas, com fonte na nota** | X (melhor) | §4.15 |
| Contrato "/100" | séries em pontos percentuais, consumo divide | idem | C | — |
| **Ano sem publicação** | **texto `"nd"`** — apagou 11 exercícios do modelo | **célula VAZIA**, e todo consumo com `N()` | **melhor** | **de resultado** (§4.7) |
| Séries derivadas por fórmula | 64 fórmulas (índice base 100, correlações) | 5 (cadeia de ano + índice IPCA acumulado) | **D** | cosmético |
| TJLP, Libor, R$/EUR, CDI fim de período | tem | não temos | **A** | estrutural para dívida indexada |

### 2.14 `Tributos a Recolher`

| Elemento | A referência faz | Nós fazemos | ✓ | Impacto |
|---|---|---|---|---|
| Cronograma → duas pontas do passivo | `A7` (curto) e `A10` (longo) | uma linha por conta tributária do caso | C | — |
| **Piso do saldo** | **não tem**: paga 12 parcelas contra saldo para 11, `L10` = **−4.249**, e **abre o balanço em 2020 e 2021** | `=ant*(1-% pago)` — **não pode ficar negativo por construção** | **melhor** | **de resultado** |
| Rótulo de ano | para em 2018, a fórmula vai a 2024 | herda o eixo do tempo | melhor | — |

---

## 3. As correções desta rodada, e a prova de cada uma

Todas com teste em `portal/scripts/verificar-export.mts` que **reprova com o defeito religado** —
o requisito §8.2 do prompt. As mensagens abaixo são as reprovações reais, coladas da execução.

| # | Defeito | Onde estava | Prova |
|---|---|---|---|
| 3.1 | **Caixa contado duas vezes no ativo** (aberto desde a sessão 32) | `abaCapitalGiro` projetava todas as contas de `ativo_circulante`, inclusive caixa; `Balance Sheet` fazia `AC = CAIXA + AC_OPER` | `(0105a)` + `(0105b)` |
| 3.2 | **Dívida bancária de curto prazo contada duas vezes no passivo** | as mesmas linhas entravam em `TOTAL_PC` e voltavam em `DIVIDA_CP` | `(0105b)` |
| 3.3 | **A depreciação nunca chegava à DRE** | `Revenues!DEPRECIACAO` era declarada e nunca preenchida: `EBITDA = EBIT`, `D&A = 0`, e o fluxo somava de volta uma depreciação que a DRE não tinha debitado | `(0105c)`: *"D&A 2026 = 0 (capex 2026 = 6480)"* e *"EBITDA 39800 · EBIT 39800"* |
| 3.4 | **A dívida do balanço desaparecia** sem mapa de dívida | as tranches vinham só de `MAPA_DIVIDA`; tirar a dívida do giro (3.2) a deixou em lugar nenhum | `(0105a)`: *"2025: 50000.00 · 2026: 50000.00 …"* — exatamente os empréstimos do caso |
| 3.5 | **Rateio de depreciação não exaustivo** | com saldo anterior zero, nenhuma classe recebia depreciação e o imobilizado crescia pelo capex inteiro | `(0105a)` |
| 3.6 | **Redução de dívida sem efeito caixa sem contrapartida** | a chave `S/N` reduzia o passivo sem nada no ativo ou no PL | `(0105a)` |
| 3.7 | **Sinal do dividendo invertido no PL** | `LUCROS_ACUM` subtraía uma célula que já é negativa — distribuir dividendo AUMENTARIA o patrimônio | revisão de código; coberto por `(0105a)` quando o payout deixa de ser zero |
| 3.8 | **`Output` sobrescrevia a legenda de cenário** | `pular(4)` depois de escrever até a linha 5: o cabeçalho caía sobre "3 = Stress Case" | `(0105g)` |
| 3.9 | **O arquivo entregue saía 14× maior** | o pós-processamento das notas regravava o ZIP com o default do JSZip (`STORE`, sem compressão): 0,3 MB → 4,3 MB | medido: `0.3 MB` antes e depois da correção |
| 3.10 | **A aba `Tributos a Recolher` vazia saía sem área de impressão** | saída antecipada da função | `(0105f)` |
| 3.11 | **O script de iteração local não gerava o mesmo arquivo da rota** | ele chamava `writeFile` direto, sem o pós-processamento — eu media um arquivo que o dono nunca recebia | as duas pontas passam por `finalizarBufferDoExport` |

---

## 4. As divergências deliberadas, com motivo escrito

Nenhuma divergência sobrevive sem motivo (§2.3 do prompt).

**4.1 As 15 abas de proveniência não saem.** É o princípio de `f0/07`: dado curado e rastreável não
some da entrega. O Modelo Base não as tem porque ele começa depois do trabalho de extração.

**4.2 Sem a imagem.** O `image1.emf` da referência é uma figura vetorial colada no `Balance Sheet`,
sem informação de modelo. A identidade visual da Oria entra por cor e tipografia, não por imagem
embutida.

**4.3 Os 1.044 nomes definidos não se replicam.** Medido: **zero** deles é usado por fórmula; 531
apontam para `#REF!`, 392 são definição de relatório do **Excel 4**, 382 apontam para outra pasta de
trabalho, 26 são `__123Graph_*` do **Lotus 1-2-3**. Replicá-los seria replicar sedimento. Os 14
nossos são áreas de impressão reais, todas em uso.

**4.4 O vocabulário da operadora de saúde não se replica** (a leitura (A) do §4 do prompt). São 18
itens nomeados no §18 do mapa. A estrutura é replicada; os rótulos vêm do caso do mandato.

**4.5 O bloco `DEBT & RATIOS` não se replica como está.** 627 das fórmulas dele estão em `#REF!` —
o bloco inteiro aponta para uma tabela que não existe mais no arquivo. Replicamos o que ele
*queria* fazer, a partir do espelho da aba de dívida.

**4.6 Nenhuma coluna de projeção fica oculta.** A referência esconde 2019–2031 (`P:AB`), e é
exatamente onde ela quebra — o balanço dela não fecha a partir de 2020 e ninguém viu. Esconder
projeção calculada é esconder onde o modelo falha.

**4.7 Ano sem série macro fica VAZIO, com `N()` no consumo.** A referência guarda o texto `"nd"`, e
`=Anual!AC86/100` virou `#VALUE!` que propagou por cinco tranches em moeda estrangeira até apagar o
`NET PROFIT` e o `CHECK` do balanço de 11 exercícios.

**4.8 Sem linhas `Item 2..5` reservadas.** A referência reserva 5 linhas por rubrica e as deixa
vazias. Aqui aparecem as linhas REAIS do caso — é a diferença entre um gabarito e um modelo gerado
a partir de dado extraído. O custo é que a grade não tem tamanho fixo; o benefício é que nenhuma
linha do cliente é jogada num "Outros".

**4.9 A base do prazo médio é a mesma nas duas pontas.** A referência mede o prazo do passivo
contra o custo e aplica o saldo projetado sobre a receita — infla o passivo na razão receita/custo
(~1,27× no arquivo dela). Aqui fornecedor gira contra CUSTO nas duas pontas, o resto contra
RECEITA LÍQUIDA.

**4.10 Juros sobre o saldo de ABERTURA, não sobre a média.** A referência usa
`AVERAGE(inicial,final)`, o que cria referência circular e exige cálculo iterativo do Excel. Fora
do Excel isso resolve para zero **sem avisar**, e nenhum teste consegue verificar o arquivo. Está
declarado na `Considerações` e em nota de célula. **Esta é a divergência de método mais importante
do arquivo** e é a única que muda número de propósito.

**4.11 As tranches saem do mapa de dívida OU do balanço.** Nunca das duas: somar as duas contaria a
mesma dívida duas vezes. A origem usada está escrita no cabeçalho do bloco.

**4.12 A depreciação não usa `SUM(OFFSET(...))`.** `OFFSET` é volátil, ilegível e quebra em
silêncio se alguém inserir coluna. O resultado é o mesmo; a fórmula é auditável a olho.

**4.13 O resíduo do rateio vai para a última classe.** Garante, por construção, que a soma dos
rateios é a depreciação do período — sem isso o balanço abre no valor dela.

**4.14 Sem bloco de imposto diferido.** O da referência está quebrado (`#REF!` em `New Deferred
Taxes`), e imposto diferido exige memória fiscal que o Kit Básico não traz. Inventar cronograma de
diferido num mandato de reestruturação mexe no número que decide se a empresa cabe no plano.

**4.15 A base macro é versionada, não colada.** 7 séries de `indice_macro_obs` + Focus, com a fonte
de cada célula em nota, contra 90 séries coladas de uma consultoria em 2011.

---

## 5. O que fica na fila, por impacto

**Estrutural (muda o que o analista vê):**

1. ✅ **FEITO (Fase C)** — `Output`: espelhos de balanço e fluxo abertos conta a conta. Cada linha de
   detalhe é REFERÊNCIA à aba de origem, não soma nova: espelho e origem não podem divergir, e um
   assert (`0107c`) confere que o número do espelho é o mesmo da origem.
2. **FICA** — `ST Inv. & Debt`: tranche em moeda estrangeira e `CAPEX FINANCING`. A tranche em moeda
   exige um dado que o Kit Básico não coleta hoje (a MOEDA do contrato, por tranche): o câmbio está
   publicado, mas aplicá-lo a uma tranche sem saber se ela é em dólar seria converter dívida em real
   por engano — erro de ~5×, da mesma família do que a `0035` corrigiu. O `CAPEX FINANCING` é uma
   premissa de plano (% do capex financiado por dívida nova) e entra junto com a decisão do dono
   sobre o cronograma de amortização, que ainda está pendente.
3. ✅ **FEITO (Fase C)** — o `CHECK` do balanço publicado no topo das quatro abas de driver, com
   formatação condicional. É onde a premissa é mexida, e portanto onde "o balanço abriu" tem de
   aparecer. Assert `0107b` — e ele exige que a célula seja FÓRMULA apontando para o `Balance Sheet`,
   porque célula vazia avalia zero e a primeira versão do assert passou verde com a linha nunca
   preenchida.
4. ✅ **FEITO (Fase C)** — `Cash Flow`: variação de giro aberta em uma linha por conta, com o sinal
   por natureza (ativo que cresce consome caixa, passivo que cresce libera) e uma linha de
   conferência contra o total, que continua vindo do espelho da aba de giro. Duas origens para o
   mesmo número só valem com a conferência entre elas — assert `0107a`.
5. **FICA** — `Goodwill`: os três blocos de espelho. Só valem quando houver ágio de verdade no caso;
   hoje a aba trabalha com saldo zero e publicar espelho de zero é ruído.
6. **FICA (não é nosso)** — `Fixed Assets`: vida útil por classe depende de laudo que o Kit Básico
   não traz. Sem o laudo, o que existe é a taxa implícita medida no próprio caso.

**Cosmético:** contador invisível da coluna A (`P20`), ordem dos grupos do balanço, os três blocos
de cenário literais em vez de `CHOOSE` com duas linhas.

**Decisão do dono:** os cortes de covenant (`3,0x`, `1,2x`, `1,0x`) são patamares usuais de term
sheet, não dados do caso — entram como célula azul editável. Se houver contrato, o número certo é o
dele.

---

*Fase 2 fechada para as 14 abas. As fases 4 e 5 (replicar e provar) já entregaram as 11 correções
do §3; o que resta está no §5, na ordem de impacto.*
