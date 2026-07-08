# 0.3 — Taxonomia Documental + Checklist Canônico (Reestruturação)  ·  [DRAFT v0]

**Objetivo:** a lista fechada de **tipos de documento** e o **checklist canônico** de um
mandato de Reestruturação. É a fonte da verdade contra a qual a completude (Portão 1) é
calculada e à qual a classificação documento→item se ancora.

> **Este é o caminho crítico da F0.** Rascunho v0 abaixo para acelerar — o **dono único
> (analista sênior)** deve cortar, adicionar e ajustar obrigatoriedade. Critério de fechamento:
> **"bom o suficiente para começar"**, não consenso perfeito. A taxonomia é **versionada**;
> vive no Postgres (fonte da verdade) com espelho no Obsidian.

## Convenções de cada item

- **Código:** estável, usado no runtime (não renomear; deprecar).
- **Obrigatoriedade:** `obrigatório` (falta → pendência **bloqueante**) · `importante`
  (falta → pendência importante) · `complementar` (não bloqueia).
- **Granularidade:** por `entidade`, por `período`, ou `caso` (uma vez por mandato).
- **Vigência:** janela de validade (documento mais antigo que isso → pendência de
  desatualização).
- **LGPD:** `PII` marca documento com dado pessoal sensível (tratamento especial — ver 0.5).

## Categorias e tipos (v0)

### 1. Contábil / Demonstrações
| Código | Documento | Obrig. | Granularidade | Vigência | LGPD |
|---|---|---|---|---|---|
| `DF_AUDITADA` | Demonstrações financeiras auditadas (BP, DRE, DFC, DMPL + notas) | obrigatório | entidade × ano | 3 últimos exercícios | — |
| `DF_GERENCIAL` | Demonstrações gerenciais | importante | entidade × período | 12 meses | — |
| `BALANCETE` | Balancete mensal (trial balance) analítico | obrigatório | entidade × mês | 12–24 meses | — |
| `RAZAO` | Livro razão / razão contábil | complementar | entidade × período | conforme pedido | — |
| `NOTAS_EXPL` | Notas explicativas | importante | entidade × ano | acompanha DF | — |

### 2. Dívida / Tesouraria
| Código | Documento | Obrig. | Granularidade | Vigência | LGPD |
|---|---|---|---|---|---|
| `MAPA_DIVIDA` | Mapa de dívida (credor, modalidade, saldo, taxa, vencimento, garantias) | obrigatório | caso (consolidado) | data-base ≤ 60 dias | — |
| `CONTRATO_DIVIDA` | Contratos de empréstimo/financiamento/debêntures | obrigatório | por contrato | vigente | — |
| `EXTRATO_BANCARIO` | Extratos bancários | importante | entidade × conta × mês | 6–12 meses | — |
| `FLUXO_REALIZADO` | Fluxo de caixa realizado | obrigatório | caso × mês | 12 meses | — |
| `FLUXO_PROJETADO` | Fluxo de caixa projetado | obrigatório | caso × mês | horizonte do plano | — |
| `APLIC_FINANC` | Posição de aplicações financeiras | complementar | entidade | data-base | — |

### 3. Operacional
| Código | Documento | Obrig. | Granularidade | Vigência | LGPD |
|---|---|---|---|---|---|
| `AGING_AR` | Aging de contas a receber | obrigatório | entidade | data-base ≤ 60 dias | — |
| `AGING_AP` | Aging de contas a pagar / fornecedores | obrigatório | entidade | data-base ≤ 60 dias | — |
| `ESTOQUE` | Posição de estoques | importante | entidade | data-base | — |
| `CONTRATOS_COM` | Contratos relevantes com clientes/fornecedores | complementar | por contrato | vigente | — |
| `HEADCOUNT` | Headcount / folha de pagamento | complementar | entidade × mês | 3 meses | PII |

### 4. Societário / Legal
| Código | Documento | Obrig. | Granularidade | Vigência | LGPD |
|---|---|---|---|---|---|
| `CONTRATO_SOCIAL` | Contrato/estatuto social + alterações | obrigatório | entidade | vigente | — |
| `ORGANOGRAMA` | Organograma societário do grupo | obrigatório | caso | vigente | — |
| `CERTIDOES` | Certidões (negativas de débito, protestos, falência) | importante | entidade | ≤ 90 dias | — |
| `CONTINGENCIAS` | Relatório de contingências / processos judiciais | obrigatório | caso | ≤ 90 dias | — |

### 5. Tributário
| Código | Documento | Obrig. | Granularidade | Vigência | LGPD |
|---|---|---|---|---|---|
| `SITUACAO_FISCAL` | Situação fiscal / parcelamentos (Refis etc.) | obrigatório | entidade | ≤ 90 dias | — |
| `DEBITOS_TRIB` | Demonstrativo de débitos tributários | importante | entidade | ≤ 90 dias | — |
| `SPED` | Obrigações acessórias (SPED/ECD/ECF) | complementar | entidade × ano | último exercício | — |

### 6. Intragrupo / Partes relacionadas
| Código | Documento | Obrig. | Granularidade | Vigência | LGPD |
|---|---|---|---|---|---|
| `MUTUOS` | Contratos de mútuo e posição de contas intragrupo | obrigatório | caso | data-base | — |
| `CONTRATOS_IC` | Contratos intercompany relevantes | importante | por contrato | vigente | — |

### 7. Garantias / Sócios (atenção LGPD)
| Código | Documento | Obrig. | Granularidade | Vigência | LGPD |
|---|---|---|---|---|---|
| `GARANTIAS` | Garantias prestadas (reais e fidejussórias); bens em garantia | obrigatório | caso | vigente | — |
| `AVAIS_FIANCAS` | Avais / fianças dos sócios | importante | por sócio | vigente | PII |
| `DOCS_SOCIOS` | Documentos pessoais dos sócios garantidores | importante | por sócio | vigente | **PII sensível** |

### 8. Plano / Projeções
| Código | Documento | Obrig. | Granularidade | Vigência | LGPD |
|---|---|---|---|---|---|
| `PLANO_NEGOCIOS` | Plano de negócios / turnaround | importante | caso | vigente | — |
| `PREMISSAS` | Premissas das projeções | importante | caso | acompanha projeção | — |

## Perguntas que o dono precisa resolver ao fechar a v1

1. Quais itens `importante` deveriam subir para `obrigatório` (ou o contrário)?
2. As janelas de vigência batem com a prática real de vocês?
3. Falta algum tipo específico da carteira de reestruturação da Oria?
4. Quais itens compõem a **lista de bloqueantes não-sobrepujáveis** (0.4)? (candidatos óbvios:
   `DF_AUDITADA`, `MAPA_DIVIDA`, `BALANCETE`, `CONTINGENCIAS`, `SITUACAO_FISCAL`.)

**Critério de pronto (DoD):** tabela revisada pelo dono; obrigatoriedade e vigência definidas
por item; lista de bloqueantes não-sobrepujáveis marcada; versão registrada como v1.
