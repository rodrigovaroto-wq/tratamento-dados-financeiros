# 0.8 — Padrão de Entrega Analítica do Output  ·  [DECISÃO v0]

**Objetivo:** definir, com base na literatura profissional de análise de demonstrações
financeiras, **como o dado tratado deve ser entregue** ao analista de RX/M&A na planilha
exportável — indo além de "linhas por seção com subtotais" (0.7) para o padrão analítico que um
modelador experiente espera encontrar já pronto.

Fundamentado no material `docs/Embasamento sobre Contabilidade` (bibliografia curada pelo dono) e
em pesquisa sobre as convenções dessas obras. Estado **v0** — entregue por camadas (ver
"Faseamento").

## Fundamentação (obras da bibliografia → o que prescrevem para a entrega)

A bibliografia é ampla; para a **entrega de dados** (não modelagem/valuation/RJ jurídica, que
`f0/07` mantém FORA do escopo) o que importa é a camada **(c) Análise de demonstrações**:

- **Fridson & Alvarez, "Financial Statement Analysis: A Practitioner's Guide"** — o analista lê
  demonstrações através de duas lentes fundamentais antes de qualquer índice: **análise vertical
  (common-size)** — cada linha como % de uma base (Ativo Total no Balanço; Receita Líquida na DRE)
  — e **análise horizontal (tendência)** — variação período-a-período. É a base do trabalho de
  crédito/distressed.
- **Matarazzo / Assaf Neto (análise de balanços, prática brasileira)** — o conjunto canônico de
  índices em PT-BR: **liquidez** (corrente, seca, geral, imediata), **estrutura de capital /
  endividamento** (endividamento geral, composição do endividamento, participação de capital de
  terceiros, imobilização do PL), **rentabilidade** (margens, ROA, ROE), **atividade** (giro do
  ativo, prazos médios PMR/PME/PMP, ciclo operacional e financeiro).
- **Penman, "Financial Statement Analysis and Security Valuation"** — reformulação
  operacional×financeiro (NOA/NFO, RNOA) e **qualidade do resultado** (accruals vs. caixa).
- **Schilit, "Financial Shenanigans"** — *red flags* de qualidade: CFO divergindo do Lucro
  Líquido; Contas a Receber crescendo mais rápido que a Receita (DSO subindo). Estes sinais já são
  parcialmente cobertos pelo motor de reconciliação (Classe A/B, `docs/04`).
- **Altman & Hotchkiss (Z-score)** — para distressed, o **Altman Z''** (mercados emergentes /
  empresas fechadas / não-manufatura): `Z'' = 3,25 + 6,56·X1 + 3,26·X2 + 6,72·X3 + 1,05·X4`, com
  X1 = Capital de Giro/Ativo, X2 = Lucros Retidos/Ativo, X3 = EBIT/Ativo, X4 = PL/Passivo Total.
  Faixas: > 2,6 seguro; 1,1–2,6 zona cinzenta; < 1,1 aflição.

## Reconciliação com a doutrina (por que isto NÃO viola `f0/07`/`docs/01`)

Análise vertical/horizontal e índices **não são projeção nem modelagem** — são **razões entre
números que o próprio documento já trouxe** (extraídos), calculadas por **fórmula Excel
transparente** (o analista vê exatamente numerador/denominador). É a mesma natureza das linhas de
**margem** já entregues (`f0/07`, emenda 2026-07-22) e da lista de "próximos passos" do handoff
("aba Indicadores/Resumo consolidada" e "Crescimento %" — explicitamente marcados como
*apresentação/fórmula sobre dado real*).

Regras inegociáveis mantidas:
1. **Nunca inventar input.** Um índice só é emitido quando as linhas que ele exige **existem** na
   extração (âncoras de seção). Faltando um insumo, o índice **não aparece** (célula vazia via
   `IFERROR`) — nunca é estimado. Índices que exigem detalhamento de conta ainda não isolado
   (Estoques, Contas a Receber, Dívida bruta, Despesa Financeira, Lucros Retidos) ficam **fora**
   desta v0 e são listados abaixo como faseamento honesto — não são preenchidos "no chute".
2. **Anti-ancoragem preservada.** Índices e %s referenciam células de linha que continuam
   PENDENTES/âmbar até o aceite humano. O índice é uma leitura derivada do dado como está — não um
   fato novo. Nenhum valor de conta vira fato sem `decisao` de aceite (Portão 2).

## O que a planilha entrega (v0 — esta fatia)

Sobre a estrutura já existente (uma aba por demonstração, contas por seção CPC/Lei 6.404 com
subtotais em fórmula):

1. **Análise Vertical (AV%)** — coluna `AV%` ao lado de cada coluna de valor no **Balanço** e na
   **DRE**. Fórmula = linha ÷ base (Balanço: TOTAL DO ATIVO; DRE: Receita Líquida). Fluxo de Caixa
   não recebe AV% (fluxos não são fração de um total — não é convenção).
2. **Análise Horizontal (Δ%)** — coluna `Δ%` entre colunas de **períodos comparáveis da MESMA
   entidade** (Balanço/DRE/Fluxo). Fórmula = (período atual − anterior) ÷ anterior.
3. **Indicadores de Liquidez e Estrutura** (bloco ao pé do Balanço, por coluna) — os índices
   computáveis a partir das âncoras de seção que o export já monta, sem depender de detalhamento
   de conta: **Liquidez Corrente**, **Liquidez Geral**, **Endividamento Geral**, **Composição do
   Endividamento**, **Participação de Capital de Terceiros**, **Imobilização do PL**. Todos em
   fórmula com `IFERROR` (célula vazia quando o insumo não existe).
4. **Margens** (Bruta/Operacional/Líquida) na DRE — já entregues (emenda de `f0/07`), mantidas.

## Faseamento honesto (fora desta v0 — exigem detalhamento de conta ou plumbing extra)

Só entram quando a extração isolar as linhas-conceito necessárias como âncoras endereçáveis
(ou com referência cruzada entre abas), para não violar a regra 1 acima:

- **Liquidez Seca / Imediata** — exigem Estoques / Disponível isolados.
- **Cobertura de juros** (EBIT/EBITDA ÷ Despesa Financeira) — exige Despesa Financeira isolada.
- **Dívida Líquida, Dívida Líquida/EBITDA, Dívida Líquida/PL** — exigem dívida bruta e caixa
  isolados (e EBITDA, que a DRE hoje não traz — D&A não vem como linha isolada, `f0/07` cont.⁴).
- **Ciclo de caixa (PMR/PME/PMP, ciclo operacional/financeiro), Giro do Ativo** — exigem Contas a
  Receber, Estoques, Fornecedores isolados + Receita/CMV.
- **ROA / ROE / RNOA** — exigem cruzar Lucro Líquido (DRE) com Ativo/PL (Balanço) da MESMA
  entidade×período (referência entre abas).
- **Altman Z''** — X2 exige Lucros Retidos isolados no PL.
- **Sinais de qualidade (Schilit/Penman): CFO vs. Lucro Líquido; Receita vs. Contas a Receber** —
  parcialmente cobertos pela reconciliação (Classe A/B); consolidar como painel é passo futuro.

**Critério de pronto (DoD) v0:** ✅ AV% no Balanço/DRE; ✅ Δ% entre períodos comparáveis;
✅ bloco de indicadores de liquidez/estrutura no Balanço; ✅ tudo em fórmula com `IFERROR`, sem
inventar insumo; ✅ faseamento do que falta documentado honestamente.
