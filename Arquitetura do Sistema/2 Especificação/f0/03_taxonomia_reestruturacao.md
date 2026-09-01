# 0.3 — Taxonomia Documental + Checklist Canônico (Reestruturação)  ·  [v1 — bom o suficiente para começar]

**Objetivo:** a lista de **tipos de documento** e o **checklist canônico** de um mandato de
Reestruturação. É a fonte da verdade contra a qual a completude (Portão 1) é calculada e à qual
a classificação documento→item se ancora.

> **Dono único:** Rodrigo Varoto. Fechado como **v1 "bom o suficiente para começar"** em
> 2026-07-14, a partir da lista real de documentos dos mandatos da Oria — não consenso perfeito.
> A taxonomia é **versionada**; vive no Postgres (fonte da verdade) com espelho no Obsidian.

## Modelo de dois níveis

A taxonomia se organiza em **dois níveis de obrigatoriedade**, que é o que conecta a taxonomia
ao motor de completude:

- **Kit Básico (obrigatório):** o checklist que **não pode faltar**. É exatamente o conjunto
  que o **Portão 1 (Completude)** verifica — a ausência de qualquer item gera **pendência
  bloqueante**. Fechado e estável.
- **Variáveis (complementar):** todos os demais dados financeiros/operacionais e outras
  categorias que **variam por cliente**. O sistema **trata e cura todos quando presentes**, mas
  a ausência **não bloqueia** a completude. Lista aberta, cresce conforme os mandatos.

## Convenções de cada item

- **Código:** estável, usado no runtime (não renomear; deprecar).
- **Obrigatoriedade:** `obrigatório` (Kit Básico — falta → pendência **bloqueante**) ·
  `complementar` (Variáveis — não bloqueia).
- **Granularidade:** por `entidade`, por `período`, ou `caso` (uma vez por mandato).
- **Período:** convenção de referência dos mandatos da Oria —
  `12M25` = 12 meses de 2025 (anual); `12M24` = 12 meses de 2024;
  `1T25` = 1º trimestre de 2025; `1T26` = 1º trimestre de 2026;
  `L24M` = últimos 24 meses; `23, 24, 25` = múltiplos exercícios.
- **`(Assinado)`:** **atributo de validação formal** (assinado vs. não assinado), **não** um
  tipo de documento. Vive como flag em `documento_versao`, verificado na validação formal (E1).
- **Vigência:** janela de validade (documento mais antigo → pendência de desatualização).
- **LGPD:** `PII` marca documento com dado pessoal sensível (tratamento especial — ver 0.5).

---

## NÍVEL 1 — Kit Básico (obrigatório · verificado no Portão 1)

Conjunto mínimo que todo mandato de Reestruturação **precisa ter** para avançar. É a lista real
usada pela Oria. Falta de qualquer item → pendência bloqueante.

| Código | Documento | Granularidade | Período(s) típicos | LGPD |
|---|---|---|---|---|
| `DRE` | Demonstração de Resultado do Exercício | entidade × período | 12M25, 12M24, 1T25, 1T26 | — |
| `BALANCO` | Balanço Patrimonial | entidade × período | 12M25, 12M24, 1T25, 1T26 | — |
| `FLUXO_CAIXA` | Demonstração de Fluxo de Caixa | entidade × período | 12M25, 12M24 | — |
| `COMBINADO` | Demonstrações combinadas (grupo consolidado) | caso × período | 12M25, 12M24 | — |
| `FATURAMENTO_24M` | Série de faturamento dos últimos 24 meses | entidade (× mês) | L24M | — |
| `MUTUOS` | Relação de mútuos / posição de contas intragrupo | caso | 23, 24, 25 | — |
| `FAT_INTRAGRUPO` | Faturamento intragrupo | caso (× exercício) | 23, 24, 26 | — |
| `CONTRATO_SOCIAL` | Contrato/estatuto social registrado (ou última alteração registrada) | entidade | vigente | — |

> **Candidatos naturais à lista de bloqueantes NÃO-sobrepujáveis (0.4):** `DRE`, `BALANCO`,
> `COMBINADO`, `MUTUOS`, `CONTRATO_SOCIAL`. (Confirmar em 0.4.)

---

## NÍVEL 2 — Variáveis (complementar · não bloqueiam completude)

Dados financeiros/operacionais e demais categorias que **variam por cliente**. Tratados e
curados **quando presentes**. Lista aberta — cresce conforme os mandatos exigirem. Os códigos
abaixo são o ponto de partida (herdados do rascunho v0 + categorias usuais de reestruturação).

### Contábil / Demonstrações (detalhamento)
| Código | Documento | Granularidade | Vigência | LGPD |
|---|---|---|---|---|
| `DF_AUDITADA` | Demonstrações financeiras auditadas completas (+ notas) | entidade × ano | 3 últimos exercícios | — |
| `BALANCETE` | Balancete mensal (trial balance) analítico | entidade × mês | 12–24 meses | — |
| `RAZAO` | Livro razão / razão contábil | entidade × período | conforme pedido | — |
| `NOTAS_EXPL` | Notas explicativas | entidade × ano | acompanha DF | — |

### Dívida / Tesouraria
| Código | Documento | Granularidade | Vigência | LGPD |
|---|---|---|---|---|
| `MAPA_DIVIDA` | Mapa de dívida (credor, modalidade, saldo, taxa, vencimento, garantias) | caso (consolidado) | data-base ≤ 60 dias | — |
| `CONTRATO_DIVIDA` | Contratos de empréstimo/financiamento/debêntures | por contrato | vigente | — |
| `EXTRATO_BANCARIO` | Extratos bancários | entidade × conta × mês | 6–12 meses | — |
| `FLUXO_PROJETADO` | Fluxo de caixa projetado | caso × mês | horizonte do plano | — |
| `APLIC_FINANC` | Posição de aplicações financeiras | entidade | data-base | — |

### Operacional
| Código | Documento | Granularidade | Vigência | LGPD |
|---|---|---|---|---|
| `AGING_AR` | Aging de contas a receber | entidade | data-base ≤ 60 dias | — |
| `AGING_AP` | Aging de contas a pagar / fornecedores | entidade | data-base ≤ 60 dias | — |
| `ESTOQUE` | Posição de estoques | entidade | data-base | — |
| `CONTRATOS_COM` | Contratos relevantes com clientes/fornecedores | por contrato | vigente | — |
| `HEADCOUNT` | Headcount / folha de pagamento | entidade × mês | 3 meses | PII |

### Societário / Legal
| Código | Documento | Granularidade | Vigência | LGPD |
|---|---|---|---|---|
| `ORGANOGRAMA` | Organograma societário do grupo | caso | vigente | — |
| `CERTIDOES` | Certidões (negativas de débito, protestos, falência) | entidade | ≤ 90 dias | — |
| `CONTINGENCIAS` | Relatório de contingências / processos judiciais | caso | ≤ 90 dias | — |

### Tributário
| Código | Documento | Granularidade | Vigência | LGPD |
|---|---|---|---|---|
| `SITUACAO_FISCAL` | Situação fiscal / parcelamentos (Refis etc.) | entidade | ≤ 90 dias | — |
| `DEBITOS_TRIB` | Demonstrativo de débitos tributários | entidade | ≤ 90 dias | — |
| `SPED` | Obrigações acessórias (SPED/ECD/ECF) | entidade × ano | último exercício | — |

### Intragrupo / Partes relacionadas
| Código | Documento | Granularidade | Vigência | LGPD |
|---|---|---|---|---|
| `CONTRATOS_IC` | Contratos intercompany relevantes | por contrato | vigente | — |

### Garantias / Sócios (atenção LGPD)
| Código | Documento | Granularidade | Vigência | LGPD |
|---|---|---|---|---|
| `GARANTIAS` | Garantias prestadas (reais e fidejussórias); bens em garantia | caso | vigente | — |
| `AVAIS_FIANCAS` | Avais / fianças dos sócios | por sócio | vigente | PII |
| `DOCS_SOCIOS` | Documentos pessoais dos sócios garantidores | por sócio | vigente | **PII sensível** |

### Plano / Projeções
| Código | Documento | Granularidade | Vigência | LGPD |
|---|---|---|---|---|
| `PLANO_NEGOCIOS` | Plano de negócios / turnaround | caso | vigente | — |
| `PREMISSAS` | Premissas das projeções | caso | acompanha projeção | — |

---

## Perguntas em aberto para futuras versões (v2+)

1. As janelas de vigência dos itens variáveis batem com a prática real? (definir por item)
2. Algum item hoje `complementar` deveria subir para o Kit Básico em tipos de mandato
   específicos (ex.: `MAPA_DIVIDA` em reestruturação de dívida pura)?
3. Confirmar a lista de bloqueantes não-sobrepujáveis em 0.4 a partir do Kit Básico.

**Critério de pronto (DoD):** ✅ Kit Básico (obrigatório) fechado com granularidade e período;
✅ nível Variáveis (complementar) com ponto de partida; ✅ `(Assinado)` registrado como flag de
validação, não tipo; ✅ convenção de períodos definida; ✅ versão registrada como **v1**.