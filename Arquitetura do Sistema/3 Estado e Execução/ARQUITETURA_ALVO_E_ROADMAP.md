# Arquitetura-alvo e roadmap — evolução para plataforma de inteligência financeira

**Data:** 15/09/2026 · **Base:** `main` em `de556c2` · **Origem:** derivado da
`Arquitetura do Sistema/4 Análises e Auditorias/AUDITORIA_PROFUNDA_2026-09-15.md`, cujos números
foram medidos nesta árvore.

**Princípio central:** não é um projeto novo. É a **evolução do sistema existente** até que ele
opere como plataforma profissional de inteligência financeira para M&A e reestruturação. Nada do
que funciona é descartado.

> **A base andou enquanto este arquivo era escrito.** Ele nasceu sobre `de556c2`; o `main` passou a
> `f230cff` com `0175`–`0177` antes do merge. Os números da F0 abaixo já estão corrigidos para isso.
> **A lição é do próprio roadmap:** a defasagem contra produção não é um número deste arquivo — é o
> que a sonda responde, e ela cresce a cada rodada que fecha sem aplicar. É por isso que a F0 é
> primeira e que a fatia 0.1 mede antes de corrigir.

**Este arquivo não implementa nada.** Ele decide o desenho, a ordem e os critérios objetivos de
passagem. A execução começa pela F0, cujo plano está na §9.

---

## 1. Decisão por componente existente

Legenda: KEEP · REFACTOR · REBUILD · EXTEND · DEPRECATE · REMOVE · MISSING

### 1.1 Banco / domínio

| Componente | Decisão | Justificativa |
|---|---|---|
| `campo_extraido` | **KEEP + REFACTOR de papel** | Não migrar, não reescrever. **Promover a camada de evidência imutável**. O fato canônico nasce ACIMA dela. Assim nada quebra e as 10 reconciliações migram uma a uma |
| `entidade` + `fn_cnpj_*`, `fn_fundir_entidade`, `0169`–`0174` | **KEEP + EXTEND** | 80% do trabalho de identidade já foi feito e pago caro (6 migrations, um crash em produção). Falta FK no fato, papel societário tipado, participação |
| `periodo` | **REFACTOR** | Sem semana; `periodo_coluna` carrega dois conceitos. Precisa de `granularidade`, `data_inicio`, `data_fim` |
| `secao_canonica` (16 valores) | **KEEP + EXTEND** | Certo como seção de demonstração. Nunca foi plano de contas e não deve virar um: fica como atributo da conta canônica |
| **Plano de contas canônico** | **MISSING** | A ausência central |
| `classe_contabil_catalogo` (5 de recorrência) | **KEEP, novo papel** | É normalização de EBITDA e é exatamente o que valuation precisa. Vira atributo da conta canônica |
| `taxonomia_tipo_documento` (36) | **KEEP** | Ontologia excelente e já alinhada ao alvo. Não tocar |
| `taxonomia_linha_exigida` (14 linhas, 6 tipos vivos) | **EXTEND (agressivamente)** | 27 tipos ingeridos sem exigência = 27 formas de o dado sumir sem o placar mudar |
| `taxonomia_linha_localizador` (46) | **KEEP + EXTEND** | Mecanismo bom, cobertura estreita |
| As 3 exigências `origem='proposta'` | **EXTEND (promover a `codigo`)** | São o insumo da eliminação intragrupo, declaradas mortas há meses |
| `reconciliacao` + 10 `fn_reconciliar_*` | **KEEP** | Melhor ativo do sistema. Ganha FK real e fica melhor |
| `pendencia` | **KEEP** | É o mecanismo de "inconsistência explícita". Pronto |
| `evento_auditoria` + `decisao` | **KEEP + EXTEND** | Falta registrar LEITURA, não só decisão |
| `estagio_autonomia` + `fn_mudar_dial` | **KEEP** | Autonomia graduada é rara e correta |
| `golden_*` (7 tabelas, 16 funções) | **REFACTOR** | Trocar a fonte de rótulo para `fn_veredito_producao`, mantendo as tabelas |
| `documento_fato` + 9 tipos de fato | **KEEP + EXTEND** | Semente do Diagnóstico, com trecho literal obrigatório. Subutilizado |
| `checklist_item_status` | **KEEP + EXTEND** | **Já é a matriz de perímetro** — a camada existe em 70% |
| `caso_pergunta` + `pergunta_catalogo` | **KEEP** | Human-in-the-loop estruturado |
| `premissa_catalogo` (89, 7 fórmulas) | **KEEP — é o ISA do motor** | O conjunto de instruções do motor já está catalogado e versionado |
| `caso_premissa`, `caso_linha_premissa` | **REFACTOR** | Ligam por `rotulo_norm` texto e não têm cenário |
| `caso_modelagem` | **REFACTOR** | Uma por caso, sem versão nem cenário |
| `indice_macro_*` + workflow macro | **KEEP** | Pronto |
| `instalacao_requisito` / `fn_instalacao_conferir` | **KEEP + REFACTOR** | Precisa do par externo rodando contra PRODUÇÃO |
| RLS (47 policies `USING (true)`) | **REFACTOR (adiado)** | Correto para ferramenta interna; bloqueante como plataforma. Não é da F0 |

### 1.2 n8n

| Componente | Decisão | Justificativa |
|---|---|---|
| `workflow.e1-ingestao` (40 nós) | **KEEP + EXTEND** | Funciona. Ganha nós para os tipos hoje mudos |
| 17 libs (543 testes) | **KEEP** | Encapsulam aprendizado de produção caro |
| Duplicação inline + `espelho-inline.test.mjs` | **KEEP** | Imposta pela plataforma, contida por equivalência comportamental. Dívida MITIGADA |
| 4 geradores + `git diff --exit-code` | **KEEP** | Padrão correto de derivado versionado |
| Republicação manual | **REFACTOR — urgente** | Defasada desde 02/09; memória registra perda de toggles |
| `macro`, `erros`, `diagnostico-ia` | **KEEP** | |
| `medir-fase0-denominador.mjs` | **REMOVE ou adotar** | Órfão: fora do CI e do `CLAUDE.md` |

### 1.3 Portal / export

| Componente | Decisão | Justificativa |
|---|---|---|
| Telas | **KEEP** | `tsc`/`eslint` limpos, 7 suítes verdes |
| `export.ts` (3.482) — modo dados | **KEEP** | 721 verificações, proveniência por célula |
| `modelo-institucional.ts` (6.689) | **REFACTOR profundo → vira emissor** | Não é motor; é gerador de planilha que É o modelo. A fidelidade ao Modelo Base é ativo e fica |
| `export-modelagem.ts` (2.340) | **REFACTOR** | Mesma razão |
| `avaliar-formula.mts` (630) | **KEEP → promover a portão de migração** | Prova célula a célula que o motor novo reproduz o Excel antes de trocar a fonte |
| `statement-templates.ts` | **KEEP + REFACTOR** | Passa a ler a conta canônica |
| `limite-de-envio.ts` | **KEEP** | Nasceu de HTTP 413 real |
| `/api/intake` | **KEEP (revisitar depois)** | Acoplamento deliberado e documentado |

### 1.4 Testes, CI, conhecimento, agentes

| Componente | Decisão | Justificativa |
|---|---|---|
| 26 portões / 13,9k SQL / 10,8k scripts | **KEEP — viabiliza tudo** | A regra 2 é o que torna esta cirurgia segura |
| 2 books + geradores sob `git diff` | **KEEP + EXTEND** | Falta um terceiro: **distress** (PL negativo, covenant rompido, aging, extrato) |
| Arnês de variações (25) | **KEEP + EXTEND** | Achou 5 defeitos que nenhuma outra suíte pega |
| CI (28 passos) | **KEEP + EXTEND** | Falta aplicar migration, conferir n8n publicado, Sonar Quality Gate |
| `.claude/conhecimento` | **KEEP** | Infraestrutura de sessão genuinamente boa |
| 7 agentes do projeto | **KEEP + EXTEND** | Faltam **`motor-financeiro`** e **`ontologia-contabil`** |
| 30 agentes `importado.*` + 52 comandos | **FEITO em 16/09/2026** | Removidos juntos; 7 agentes e 3 comandos escritos aqui. Procedência em `.claude/COMANDOS.md` |
| `ESTADO.md` + `HANDOFF.md` (11.587 linhas) | **REFACTOR** | Cabeçalho curto sob portão; histórico particionado |
| `PRONTIDAO_POR_ESTAGIO.md` | **REBUILD** | 35 sessões atrasado. Regerar do banco e do CI, não à mão |
| `00_VISAO_E_ESCOPO.md` | **REBUILD** | Declara escopo negativo que o próprio código já ultrapassou |

### 1.5 O que remover

~~Os 52 comandos importados + 30 agentes `importado.*`~~ — **removidos em 16/09/2026**;
`medir-fase0-denominador.mjs` se não for adotado. **Nada mais.** Não há código morto relevante: o que parece morto está DECLARADO como
não-lido, o que é honestidade, não lixo.

### 1.6 MISSING (novo de verdade)

`conta_canonica` · `fato_financeiro` · `lineage_aresta` · `cenario` · **motor de cálculo** ·
`instrumento_divida` · `credor` · `garantia` · `alavanca` · valuation · camada de apresentação ·
PPT · conversão cambial · granularidade semanal.

---

## 2. As 23 camadas, estágio real

🟢 pronto · 🟡 parcial · 🟠 embrionário · 🔴 ausente

| # | Camada | Estágio | Evidência | Decisão |
|---|---|---|---|---|
| 1 | Document/Data Ingestion | 🟢 80% | 40 nós, 4 formatos, fatiamento, orçamento por documento, fingerprint, guarda de 413 | KEEP+EXTEND |
| 2 | Extraction | 🟡 70% | schema forte, 543 testes; N2 `declarada`; 39% de falha na rodada de 190 | KEEP+EXTEND |
| 3 | Normalization | 🟡 60% | escala ✅; moeda sem FX; período sobrecarregado | REFACTOR |
| 4 | Classification | 🟠 30% | 16 seções + string; 5 classes de recorrência; dial N0 | REBUILD parcial |
| 5 | **Canonical Financial Data** | 🔴 15% | sem FK, sem `conta_id`, sem hierarquia | **REBUILD acima do existente** |
| 6 | Entity/Perimeter | 🟡 55% | `entidade`+CNPJ; **`checklist_item_status` já é a matriz** | KEEP+EXTEND |
| 7 | Provenance/Lineage | 🟡 50% | por (rótulo, seção, ano) — `0125` — mas como NOTA de célula; morre na projeção | EXTEND |
| 8 | Validation/Reconciliation | 🟢 75% | 10 funções com materialidade e precondições | KEEP+EXTEND |
| 9 | Financial Analysis / Diagnóstico | 🟠 20% | `documento_fato` + 9 fatos; `fn_diagnostico_modelagem` é de extração | EXTEND |
| 10 | Liquidity/Working Capital | 🟠 15% | `dias_de_giro` anual no Excel; **zero** 13-week/aging/extrato | MISSING (maior parte) |
| 11 | Forecast | 🟡 45% | 89 premissas, 7 fórmulas; projeção no Excel | REFACTOR |
| 12 | Integrated Financial Model | 🟡 50% | 14 abas, circularidade cortada e declarada; fora do sistema | REFACTOR→motor |
| 13 | Capital Structure | 🟠 25% | `MAPA_DIVIDA`, revolver no Excel; sem instrumento/garantia/covenant como dado | EXTEND |
| 14 | Operational Turnaround | 🔴 0% | — | **questionado — §4.3** |
| 15 | Restructuring Strategy | 🔴 5% | `haircut` só como parâmetro do Stress | MISSING |
| 16 | Valuation | 🔴 0% | 0 em código | MISSING |
| 17 | Creditor/Recovery | 🔴 0% | `credor` só como rótulo | MISSING |
| 18 | Scenario Engine | 🔴 10% | zero `cenario` no schema | MISSING |
| 19 | Stress/Red Team | 🟡 40% (em forma melhor) | 25 variantes + regra 2 + `revisor-defeito-silencioso` | **reenquadrar — §4.4** |
| 20 | Presentation Data Layer | 🔴 0% | — | MISSING |
| 21 | PPT Generation | 🔴 0% | — | MISSING |
| 22 | Governance/Audit | 🟢 70% | `evento_auditoria` append-only, `decisao`, dial, `lote_execucao` | KEEP+EXTEND |
| 23 | AI/Agent Orchestration | 🟡 60% | 7 agentes, conhecimento com grafo; frágil operacionalmente | KEEP+EXTEND |

**Em uma frase:** 1, 8 e 22 prontas; 2, 3, 6, 7, 11, 12, 19 a meio caminho; **a 5 é o buraco que
segura tudo**; 14–18, 20, 21 não existem.

---

## 3. FINAL ARCHITECTURE

```
╔══════════════════════════════════════════════════════════════════════════╗
║  L0  INGESTÃO                                            [KEEP+EXTEND]   ║
║      n8n e1-ingestao (40 nós) · 4 formatos · fatiamento · orçamento      ║
║      fingerprint · guarda de 413 · 17 libs / 543 testes                  ║
╠══════════════════════════════════════════════════════════════════════════╣
║  L1  EVIDÊNCIA  (append-only, IMUTÁVEL)                [KEEP, novo papel]║
║      campo_extraido COMO ESTÁ + documento_fato + documento_versao        ║
║      rótulo como veio · página · confiança · aceite · moeda · unidade    ║
║      >>> esta camada não muda. Ela É a prova. <<<                        ║
╠══════════════════════════════════════════════════════════════════════════╣
║  L2  RESOLUÇÃO  (estágio EXPLÍCITO, sob dial)                    [NOVO]  ║
║      evidência --> identidade: conta_id · entidade_id · periodo_id       ║
║                                pai_id · versao/restatement · moeda       ║
║      método ∈ {exata, catálogo, humana, heurística+pendência}            ║
║      >>> não resolveu => PENDÊNCIA. Nunca palpite silencioso. <<<        ║
║      reaproveita: fn_normalizar_texto, fn_radicais_rotulo, fn_cnpj_*,    ║
║                   fn_entidade_canonica, fn_periodo_canonico, o dial      ║
╠══════════════════════════════════════════════════════════════════════════╣
║  L3  CANONICAL FINANCIAL DATA                                    [NOVO]  ║
║      conta_canonica (plano de contas + secao_canonica + classe recorr.)  ║
║      fato_financeiro(conta, entidade, periodo, cenario, versao,          ║
║                      moeda, valor, evidencia_id[])                       ║
║      perimetro / consolidacao · eliminacao_intragrupo como FATO próprio  ║
║      lineage_aresta(origem -> transformação -> destino)  <-- L7 vive aqui║
╠══════════════════════════════════════════════════════════════════════════╣
║  L4  RECONCILIAÇÃO                                       [KEEP+EXTEND]   ║
║      as 10 fn_reconciliar_* de hoje, agora sobre FK real                 ║
║      + intercompany (MUTUOS/FAT_INTRAGRUPO promovidos) + consolidação    ║
╠═══════════════════════════ DATA GATE ════════════════════════════════════╣
║  L5  MOTOR DE CÁLCULO                             [NOVO — a peça-chave]  ║
║      interpretador sobre as 7 formas de premissa_catalogo:               ║
║        indice_macro · crescimento_composto · pct_de_linha · dias_de_giro ║
║        valor_por_ano · preco_x_volume · curva_mensal                     ║
║      grafo de dependências · resolve circularidade por iteração          ║
║      cenário e alavanca são PARÂMETRO · toda saída carrega lineage       ║
║      >>> fonte única da verdade aritmética do sistema <<<                ║
╠═══════════════════════════ MODEL GATE ═══════════════════════════════════╣
║  L6  CENÁRIOS E ALAVANCAS                                        [NOVO]  ║
║      cenario(id, caso, nome, base_de, autor, motivo)                     ║
║      alavanca(tipo, params, alvo, categoria ∈ {financeira, operacional}) ║
║      >>> "turnaround operacional" = categoria de alavanca, não camada <<<║
╠══════════════════════════ STRATEGY GATE ═════════════════════════════════╣
║  L7  ANÁLISE  (tudo CONSULTA o motor — nada recalcula)                   ║
║   ┌────────────────┬──────────────────┬────────────────────────────────┐ ║
║   │ Diagnóstico    │ Capital Structure│ Liquidez / 13-week             │ ║
║   │ (documento_fato│ instrumento_div. │ AGING_AP/AR · EXTRATO_BANCARIO │ ║
║   │  + índices)    │ credor·garantia  │ granularidade SEMANAL (nova)   │ ║
║   ├────────────────┼──────────────────┴────────────────────────────────┤ ║
║   │ Valuation      │ Recovery / Waterfall  (prioridade Lei 11.101)     │ ║
║   └────────────────┴───────────────────────────────────────────────────┘ ║
╠══════════════════════════ CREDITOR GATE ═════════════════════════════════╣
║  L8  PRESENTATION DATA LAYER   > é uma PROJEÇÃO, não uma camada < [NOVO] ║
║      sem estado · sem aritmética · regenerável · todo nº com fato_id     ║
╠════════════════════════ PRESENTATION GATE ═══════════════════════════════╣
║  L9  SAÍDAS                                                              ║
║      Excel (fórmula VIVA, como hoje — modelo-institucional vira emissor) ║
║      PPT · PDF · API      >>> nenhuma calcula nada <<<                   ║
╚══════════════════════════════════════════════════════════════════════════╝
   TRANSVERSAL — L10 GOVERNANÇA  [KEEP+EXTEND]
     evento_auditoria · decisao · pendencia · estagio_autonomia · dial
     lote_execucao (custo/cobertura) · fn_operacao_* · golden->veredito_producao
   TRANSVERSAL — L11 ORQUESTRAÇÃO IA/AGENTES  [KEEP+EXTEND]
     provedor.mjs · 7 agentes (+2: motor-financeiro, ontologia-contabil)
     .claude/conhecimento (grafo derivado + âncoras) · 26 portões · CI
```

**A restrição que sustenta o desenho:** L1–L4 respondem *"o que é verdade"*; L5 responde *"o que
acontece se"*; L7–L9 **só perguntam**. Nenhuma camada acima de L5 tem aritmética própria — e isso é
verificável por portão estático, não por disciplina.

---

## 4. Onde este documento discorda do desenho proposto

### 4.1 A ordem das fases estava invertida no começo

A proposta original punha Extração → Normalização/Classificação → Lineage/Reconciliação →
**Entidades/Perímetros**. A auditoria diz o contrário: **extração é o componente mais maduro** e
**reconciliação já funciona**. O que trava é identidade. E identidade de ENTIDADE vem antes da de
CONTA, porque (a) já está 80% pronta, (b) o perímetro define quais contas precisam existir, (c) sem
entidade no fato, o plano de contas não tem onde pousar num COMBINADO.

**Entidade/perímetro sobe para F1. Lineage é subproduto de F4, não fase autônoma.**

### 4.2 13-week cash flow não é fase de modelagem

Vem de **extrato bancário, aging de AP/AR, folha, calendário tributário e cronograma de dívida**, em
granularidade **semanal**, que não existe no sistema. É o insumo mais sujo que existe.

**Partir em duas:** a parte de DADOS (`AGING_AP`, `AGING_AR`, `EXTRATO_BANCARIO` — tipos que a
taxonomia já tem) entra cedo, na F2. A projeção semanal entra depois do motor. Juntas, produzem um
13-week bonito e falso.

### 4.3 "Operational Turnaround" como camada é um erro

É a camada menos orientada a dados da lista. Um motor de turnaround seria ou uma lista de
iniciativas com campos livres (CRM, não inteligência financeira) ou um modelo de operações sem dados
para alimentá-lo (não há headcount por função, capacidade, mix, margem por SKU).

**Eliminada como camada.** Turnaround operacional é um conjunto de **alavancas no motor de
cenários**, idênticas às financeiras. A diferença é o campo `categoria`, não a arquitetura. Remove
uma fase inteira sem perder nada.

### 4.4 "Stress/Red Team" deve ser reenquadrado, não construído

O repositório já tem o melhor red team disponível — e ele é de ENGENHARIA: 25 variantes de documento
sujo, a regra 2, o `revisor-defeito-silencioso`, a regra 7. O que falta é **aplicá-lo ao modelo**:
invariantes econômicos que reprovem um modelo absurdo (giro agregado impossível, margem fora de
faixa, dívida que amortiza sem caixa).

**Deixa de ser camada e vira o MODEL GATE + STRATEGY GATE.** Stress de cenário (choque de receita,
juros, câmbio) é só mais um cenário.

### 4.5 Valuation antes de recovery, e os dois depois de capital structure

Recovery DEPENDE de valuation e de estrutura de capital com prioridade e garantia. Ordem correta:
capital structure → valuation → recovery. E os três dependem do motor, não do diagnóstico.

### 4.6 O que se mantém sem ressalva

Os 10 princípios e as camadas 1–13, 15–18, 20–23. **O Princípio 8 é o mais importante dos dez** — é
ele que, transformado em restrição estrutural (P1 do PRESENTATION GATE), impede o desfecho que este
projeto já viveu uma vez com o Excel.

---

## 5. GATES

### DATA GATE — "o dado é confiável" · fecha em F6

| # | Critério | Medição |
|---|---|---|
| D1 | Repositório == produção | `fn_instalacao_conferir()` **contra produção** = 0 ausentes E `conferir-chamadas.mjs` verde contra produção E hash do workflow publicado == gerado |
| D2 | Todo fato tem identidade | `count(*) from fato_financeiro where conta_id is null or entidade_id is null or periodo_id is null` = **0** |
| D3 | Resolução nunca adivinha | 100% com `resolucao_metodo` ∈ {exata, catálogo, humana}; `heuristica` só com pendência aberta |
| D4 | Hierarquia bem-formada | todo `pai_id` fecha: Σ folhas == subtotal, ou divergência declarada; 0 ciclos |
| D5 | Ausência ≠ zero | suíte de regressão do Princípio 3 verde |
| D6 | Cobertura de tipos | todo tipo com documento ingerido tem ≥1 exigência VIVA ou está declarado `SEM_CONSUMIDOR` com motivo |
| D7 | Concordância medida | `estagio_autonomia.medicao_rodada_id` não nulo para todo estágio em N2 |
| D8 | Reconciliação fecha | Classe A sem divergência material aberta, ou pendência com dono |

**Sem D1–D4, nenhuma camada acima de L4 deve ser construída.**

### MODEL GATE — "a aritmética é auditável" · fecha em F7

| # | Critério |
|---|---|
| M1 | Motor reproduz **célula a célula** o `.xlsx` atual via `avaliar-formula.mts`, tolerância 0,01, nos dois books + caso real |
| M2 | Ativo − (Passivo+PL) = 0 em todo exercício, todo cenário, toda entidade |
| M3 | Δcaixa BP == caixa do DFC, todo período |
| M4 | 0 linhas projetadas sem `premissa_id` vinculada |
| M5 | Guarda de giro agregado: Σ dias ponderados ≤ limiar, senão pendência (**hoje 1.200 dias na fixture**) |
| M6 | Circularidade resolvida em ≤N iterações **ou** o corte está declarado na saída |
| M7 | Lineage completo: todo número projetado responde por SQL origem→transformação→premissa→utilização |
| M8 | Determinismo: mesma entrada ⇒ mesmo `.xlsx` byte a byte |

### STRATEGY GATE — "cenário e alavanca são dados" · fecha em F8

| # | Critério |
|---|---|
| S1 | Cenário é linha em tabela, versionado, com autor e motivo. **0 cenários hardcoded** |
| S2 | Cada cenário reprova M2–M4 por conta própria |
| S3 | Alavanca é dado (`tipo`, `parâmetros`, `alvo`), nunca ramo de código |
| S4 | Toda alavanca é reversível e diffável contra o Base |
| S5 | Comparação entre cenários sai do motor, nunca de recálculo em outra camada |

### CREDITOR GATE — "a recuperação é defensável" · fecha em F13

| # | Critério |
|---|---|
| C1 | Todo passivo financeiro é `instrumento_divida` com credor, garantia, prioridade e vencimento |
| C2 | Σ instrumentos == dívida do BP, ou divergência declarada com materialidade |
| C3 | Waterfall respeita prioridade legal (Lei 11.101), com a regra citável linha a linha |
| C4 | Σ recuperação por classe ≤ valor distribuível — **invariante duro** |
| C5 | Recovery rate reconciliado contra o valuation que o gerou |

### PRESENTATION GATE — "a apresentação não tem números próprios" · fecha em F15

| # | Critério |
|---|---|
| P1 | **0 aritmética fora do motor** — portão ESTÁTICO sobre a camada de apresentação |
| P2 | Todo número no deck tem `fato_id` ou `resultado_id` rastreável |
| P3 | Regenerar o deck do mesmo cenário dá o mesmo deck |
| P4 | Número no PPT == número no Excel == número no banco, conferido por suíte |
| P5 | Trocar uma premissa e regenerar move o deck inteiro |

---

## 6. DEPENDENCY GRAPH

```
                        ┌──────────────────────┐
                        │ F0 FUNDAÇÃO          │  fecha o fosso repo<->produção
                        │ deploy · escopo · ADR│  >> TUDO depende disto <<
                        └──────────┬───────────┘
          ┌────────────────────────┼────────────────────────┐
          v                        v                        v
   ┌─────────────┐         ┌──────────────┐         ┌──────────────┐
   │ F1 ENTIDADE │         │ F2 COBERTURA │         │ F3 EXTRAÇÃO  │
   │  PERÍMETRO  │         │   DE TIPOS   │         │ ESTABILIDADE │
   └──────┬──────┘         └──────┬───────┘         └──────┬───────┘
          └───────────┬───────────┘                        │
                      v                                    │
            ┌───────────────────┐                          │
            │ F4 CONTA CANÔNICA │ <-- intervenção central   │
            │  + HIERARQUIA     │                          │
            │  + RESOLUÇÃO (L2) │                          │
            └─────────┬─────────┘                          │
                      v                                    │
            ┌───────────────────┐                          │
            │ F5 LINEAGE        │ (subproduto de F4)       │
            └─────────┬─────────┘                          │
                      v                                    │
            ┌───────────────────┐                          │
            │ F6 RECONCILIAÇÃO  │ <────────────────────────┘
            │ + intercompany    │
            └─────────┬─────────┘
                ══ DATA GATE ══
                      v
            ┌───────────────────┐
            │ F7 MOTOR DE       │ <-- segunda intervenção central
            │    CÁLCULO        │
            └─────────┬─────────┘
                ══ MODEL GATE ══
          ┌───────────┼───────────┐
          v           v           v
   ┌──────────┐ ┌──────────┐ ┌──────────┐
   │ F8       │ │ F9       │ │ F10      │
   │ CENÁRIOS │ │ CAPITAL  │ │ LIQUIDEZ │  <- paralelizáveis
   │ ALAVANCAS│ │ STRUCTURE│ │ 13-WEEK  │
   └────┬─────┘ └────┬─────┘ └────┬─────┘
        │  ══ STRATEGY GATE ══    │
        └────────────┼────────────┘
                     v
        ┌───────────────────┐
        │ F11 DIAGNÓSTICO   │ (o factual sai já em F2)
        │     ANALÍTICO     │
        └─────────┬─────────┘
                  v
        ┌───────────────────┐      ┌───────────────────┐
        │ F12 VALUATION     │─────>│ F13 RECOVERY      │
        └───────────────────┘      │     WATERFALL     │
                                   └─────────┬─────────┘
                              ══ CREDITOR GATE ══
                                             v
                                   ┌───────────────────┐
                                   │ F14 RESTRUCTURING │
                                   └─────────┬─────────┘
                                             v
                                   ┌───────────────────┐
                                   │ F15 PRESENTATION  │
                                   │     DATA LAYER    │
                                   └─────────┬─────────┘
                            ══ PRESENTATION GATE ══
                                             v
                                   ┌───────────────────┐
                                   │ F16 PPT           │
                                   └───────────────────┘

   ┌──────────────────────────────────────────────────┐
   │ F17 HARDENING — CONTÍNUO, não uma fase final     │
   │ RLS · restauração · Sonar gate · proteção do main│
   └──────────────────────────────────────────────────┘
```

---

## 7. PHASE ROADMAP

Mapeamento contra a numeração originalmente proposta: F0→F0 · F1→F3 · F2→F4 · F3→F5+F6 ·
**F4→F1 (sobe)** · F5→F11 (+factual em F2) · F6→F10 (partida em dois) · F7→F7 · F8→F9 ·
**F9→eliminada (vira categoria de alavanca)** · F10→F12+F13 · F11→F8 · F12→F14 · F13→F15 ·
F14→F16 · F15→F17 (contínua).

> **Esforço:** P ≤ 1 rodada · M = 2–3 · G = 4–6 · GG > 6. Ordens de grandeza para sequenciar, não
> estimativas de prazo.

> **A passagem entre duas fases tem prompt próprio:** `5 Prompts/05-gate-de-fase.md`. Ele cobra, na
> ENTRADA, de quem a fase depende e o que ela custa em rodada paga — as duas coisas que, descobertas
> no meio, já pararam a linha por horas; e na SAÍDA, os seis veredictos com evidência. As tabelas
> abaixo trazem `Dono` e `Custo` só onde eles existem: campo vazio não se escreve.

### F0 — FUNDAÇÃO: fechar o fosso e decidir o escopo

| | |
|---|---|
| **Objetivo** | Que o sistema testado e o sistema em operação sejam o mesmo, e que o escopo pare de se contradizer |
| **Estado atual** | Repo **`0177`** (a base andou de `de556c2` para `f230cff` enquanto este plano era escrito: `0175`–`0177`), produção `0157`(+`0160`) · n8n de 02/09 · provedor divergente · `00_VISAO_E_ESCOPO` nega modelagem |
| **Gap** | **20 migrations** (era 17 em `de556c2`; o número é da sonda, não deste arquivo — ver a fatia 0.1), 1 republicação, 1 decisão de produto, 3 portões novos |
| **Dependências** | nenhuma |
| **Arquivos** | `.github/workflows/suites.yml` · `N8N/republicar.sh` · `preparar-republicacao.mjs` · `conferir-publicado.mjs` · `CLAUDE.md` · `00_VISAO_E_ESCOPO.md` · `PRONTIDAO_POR_ESTAGIO.md` |
| **Banco** | aplicar `0158`–`0177`; tabela de versão aplicada |
| **Workflows** | republicar os 4; portão de hash publicado × gerado |
| **Agentes** | `explorador`, `migrations-postgres`, `n8n-workflow`, `suites-invariantes`, `estado-e-handoff` |
| **Testes** | sonda contra PRODUÇÃO = 0 ausentes; `conferir-chamadas.mjs` contra produção; espelho `CLAUDE.md`×CI generalizado |
| **Risco** | Baixo técnico / **alto se não for feito** |
| **Impacto** | **Máximo** — sem ela nenhuma medição posterior significa nada |
| **Esforço** | **P** |
| **Entrada** | — |
| **Saída** | D1 verde |
| **Aceite** | sonda zero em produção; hash publicado == gerado; `PRONTIDAO` regerado automaticamente |
| **Aceite financeiro** | reprocessar os 75 documentos sem linha da rodada "Teste 00" e obter ≥95% com linha |
| **Aceite técnico** | CI aplica migration e falha se produção divergir; espelho cobre TODAS as categorias de portão; cada portão novo medido não-vazio |

### F1 — ENTIDADE E PERÍMETRO

| | |
|---|---|
| **Objetivo** | Entidade com identidade forte e perímetro explícito |
| **Estado** | 🟡 55% — `entidade`+CNPJ, `fn_fundir_entidade`, `checklist_item_status` |
| **Gap** | participação societária, papel tipado, escopo de consolidação, FK preparada |
| **Dep.** | F0 |
| **Banco** | `entidade.participacao`, `papel_no_grupo` enum, `perimetro(caso, entidade, escopo, desde, ate)` |
| **Testes** | estender `cnpj_identidade.test.sql`, `entidade_ambigua.test.sql`; novo `perimetro.test.sql` |
| **Risco** | Médio — mexe em código que já crashou em produção |
| **Impacto** | Alto — destrava consolidação e intercompany · **Esforço** M |
| **Saída** | toda entidade com papel e escopo; 0 `entidade_ambigua` não resolvida |
| **Aceite financeiro** | perímetro reproduz o COMBINADO do cliente, ou declara a diferença |
| **Dono** | o COMBINADO do cliente contra o qual o perímetro é conferido — sem ele o aceite financeiro não fecha |

### F2 — COBERTURA DE TIPOS: dar consumidor aos 27 tipos mudos

| | |
|---|---|
| **Objetivo** | Que nenhum tipo seja ingerido sem que alguém confira se o conteúdo chegou |
| **Estado** | 🔴 6 de 36 com exigência viva; 3 mortas |
| **Gap** | exigência + localizador para `MAPA_DIVIDA` (fino), `AGING_AP`, `AGING_AR`, `EXTRATO_BANCARIO`, `GARANTIAS`, `AVAIS_FIANCAS`, `CONTINGENCIAS`, `DEBITOS_TRIB`, `ESTOQUE`, `HEADCOUNT`; promover as 3 `proposta` |
| **Dep.** | F0 |
| **Agentes** | `migrations-postgres`, `n8n-workflow`, **`ontologia-contabil`** (novo) |
| **Testes** | `linha_exigida.test.sql` estendido; **terceiro book: distress** |
| **Risco** | Baixo — aditivo · **Impacto** Alto e subestimado · **Esforço** M |
| **Saída** | D6 verde |
| **Aceite financeiro** | mandato sem aging/extrato **não** é declarado pronto |

*Entrega lateral barata: **Diagnóstico factual** — `documento_fato` já captura covenant rompido,
continuidade operacional e ressalva. Expor numa tela custa pouco e não depende de nada adiante.*

### F3 — ESTABILIDADE E CONCORDÂNCIA DA EXTRAÇÃO

| | |
|---|---|
| **Objetivo** | Parar de perder documento por causa operacional; autonomia N2 deixar de ser declarada |
| **Estado** | 🟡 schema forte; 39% de falha na rodada de 190; `medicao_*` nulos |
| **Gap** | fallback de provedor, fila de reprocesso, concordância por veredito de produção |
| **Dep.** | F0 · **Risco** Médio (toca o dial) · **Impacto** Alto · **Esforço** M |
| **Saída** | D7 verde |
| **Aceite financeiro** | concordância ≥ limiar do estágio, **publicada como piso enviesado** |
| **Aceite técnico** | lote com falha parcial retoma sem reprocessar o que já custou |
| **Dono** | as rodadas reais — concordância se mede contra veredito de PRODUÇÃO, e só o dono dispara o formulário |
| **Custo** | rodada paga e repetida por definição (a mesma entrada, várias vezes). Estime com `N8N/medir-custo-book.mjs` e fixe o teto de rodadas ANTES de começar |

### F4 — CONTA CANÔNICA, HIERARQUIA E RESOLUÇÃO (intervenção central)

| | |
|---|---|
| **Objetivo** | Dar identidade tipada ao fato financeiro |
| **Estado** | 🔴 identidade é `(secao_canonica, rótulo_norm)`; sem hierarquia; sem FK |
| **Dep.** | **F0, F1, F2** |
| **Banco** | `conta_canonica(codigo, nome, secao_canonica, classe_recorrencia, pai, natureza)` · `fato_financeiro(conta_id, entidade_id, periodo_id, cenario_id, versao, moeda, valor, evidencia_id[], resolucao_metodo)` |
| **Agentes** | `migrations-postgres`, **`ontologia-contabil`**, `revisor-defeito-silencioso` |
| **Risco** | **Alto.** Mitigação: `campo_extraido` **não muda**; canônico acima; cada reconciliação migra sozinha com os dois caminhos rodando em paralelo até baterem |
| **Impacto** | **Máximo** — extingue a família de bugs de rótulo · **Esforço** GG |
| **Saída** | D2, D3, D4 verdes |
| **Aceite financeiro** | subtotal == Σ folhas em todo documento dos books, ou divergência declarada; **0 duplicidades por subtotal+filho** |
| **Aceite técnico** | 0 fatos sem identidade; heurística sempre com pendência; **as 10 reconciliações dão o mesmo resultado nos dois caminhos antes de o antigo sair** |

### F5 — LINEAGE EXPLÍCITO

Objetivo: "de onde veio este número" por SQL, não por nota de célula. Dep. F4. Banco:
`lineage_aresta(origem_tipo, origem_id, transformacao, destino_tipo, destino_id, regra)`. A nota do
Excel vira **render**. Risco baixo · Impacto alto (Princípio 1 completo) · Esforço M.
**Aceite financeiro:** qualquer número do 1º export responde origem, período, entidade, moeda,
transformação e regra.

### F6 — RECONCILIAÇÃO SOBRE IDENTIDADE + INTERCOMPANY

Migrar as 10 funções para FK real; `eliminacao_intragrupo` como fato próprio. Dep. F4, F5, F2.
Risco médio · Impacto alto (fecha o Princípio 2) · Esforço M. **Saída: DATA GATE completo.**
**Aceite financeiro:** o combinado das 6 empresas do book-canastra fecha com eliminação explícita;
crédito de A == débito de B.

### F7 — MOTOR DE CÁLCULO (segunda intervenção central)

| | |
|---|---|
| **Objetivo** | Trazer a aritmética da projeção para dentro do sistema |
| **Estado** | 🔴 calculada pelo Excel; **89 premissas e 7 fórmulas já catalogadas** |
| **Gap** | o interpretador — **menor do que parece**: 7 opcodes, não uma plataforma |
| **Dep.** | **DATA GATE** |
| **Arquivos** | módulo novo · `modelo-institucional.ts` vira emissor · `avaliar-formula.mts` vira portão |
| **Banco** | `resultado_calculo(cenario, conta, entidade, periodo, valor, lineage)` |
| **Agentes** | **`motor-financeiro`** (novo), `revisor-defeito-silencioso` |
| **Risco** | **Alto** — mitigado pelo portão de paridade (regra 2 aplicada a troca de arquitetura) |
| **Impacto** | **Máximo** — destrava 6 dos 15 estágios · **Esforço** GG |
| **Saída** | **MODEL GATE** |
| **Aceite financeiro** | balanço fecha em todo exercício e cenário; DFC amarra; **a guarda de giro reprova os 1.200 dias que a fixture produz hoje** |
| **Aceite técnico** | `.xlsx` continua com fórmula viva e idêntico ao atual dentro de 0,01; determinismo byte a byte |

### F8 — CENÁRIOS E ALAVANCAS

Cenário e alavanca como dado versionado. Dep. F7. Banco: `cenario`, `alavanca`, `cenario_id` em
`caso_premissa`/`caso_linha_premissa`. Risco médio · Impacto alto · Esforço G.
**Saída: STRATEGY GATE.** Aqui entram as alavancas **operacionais** — a fase "Operational
Turnaround" eliminada vive aqui, como `categoria`, sem arquitetura própria.

### F9 · F10 · F11 — paralelizáveis após o MODEL GATE

| | **F9 Capital Structure** | **F10 Liquidez/13-week** | **F11 Diagnóstico analítico** |
|---|---|---|---|
| Objetivo | Dívida como instrumento | Caixa semanal a partir do dado sujo | Índices, tendências, sinais |
| Hoje | 🟠 `MAPA_DIVIDA` + revolver no Excel | 🟠 `dias_de_giro` anual; sem semana | 🟠 9 fatos materiais (factual em F2) |
| Gap | `instrumento_divida`, `credor`, `garantia`, `covenant` | granularidade semanal + AGING/EXTRATO ligados | motor de índices sobre o canônico |
| Dep. | F7, F2 | F7, **F2** | F7, F6 |
| Risco | Médio | **Alto** — dado mais sujo | Baixo |
| Esforço | G | G | M |
| Aceite fin. | Σ instrumentos == dívida do BP ou divergência declarada | 13-week reconcilia com saldo do extrato; **nunca preenche semana ausente com zero** | índice sem base não é exibido como 0 |

### F12 → F13 → F14

| | **F12 Valuation** | **F13 Recovery** | **F14 Restructuring** |
|---|---|---|---|
| Hoje | 🔴 0% | 🔴 0% | 🔴 5% |
| Gap | DCF sobre o motor, múltiplos, ajuste de EBITDA (usa `classe_contabil_catalogo`) | waterfall por prioridade legal | alongamento, carência, haircut, new money |
| Dep. | F7, F9 | **F12, F9** | F8, F13 |
| Esforço | G | G | M |
| Aceite fin. | reconciliado com o modelo que o gerou | Σ recuperação ≤ distribuível (**invariante duro**); prioridade citável | toda alavanca reversível e diffável contra o Base |
| Saída | | **CREDITOR GATE** | |

### F15 → F16

| | **F15 Presentation Data Layer** | **F16 PPT** |
|---|---|---|
| Objetivo | Projeção sem estado sobre o motor | Geração do deck |
| Dep. | CREDITOR GATE | F15 |
| Esforço | M | P |
| Risco | **Médio — de disciplina**: se ganhar estado, vira a segunda fonte que o Princípio 8 proíbe | Baixo |
| Aceite téc. | **portão estático: 0 aritmética fora do motor** | número no PPT == Excel == banco |

*F16 é pequena PORQUE F15 foi feita direito. Se parecer grande, F15 está errada.*

### F17 — HARDENING (contínuo)

RLS por caso e papel · teste de restauração executado · Sonar com Quality Gate no CI · proteção do
`main` · registro de leitura no `evento_auditoria` · conversão cambial. **Distribuir ao longo do
roadmap** — deixar para o fim é o padrão que produz a dívida que este projeto passa o tempo pagando.

---

## 8. CRITICAL PATH, paralelização, MVP

### Critical path

```
F0 --> F1 --> F4 --> F6 --> [DATA GATE] --> F7 --> [MODEL GATE] -->
   --> F9 --> F12 --> F13 --> [CREDITOR GATE] --> F15 --> F16
       |__ F2 __|
```

Dez fases no caminho crítico. **Duas dominam o custo: F4 e F7.** Tudo mais é acessório ou
paralelizável.

### Paralelização POSSÍVEL
- **F1 ∥ F2 ∥ F3** — conjuntos de arquivos disjuntos (entidade / taxonomia / provedor). Onda
  paralela legítima pelo critério de `Arquitetura do Sistema/5 Prompts/03-onda-paralela.md`.
- **F9 ∥ F10 ∥ F11** após o MODEL GATE.
- **F5** ∥ final de F4.
- **F17** distribuída, sempre.
- **Terceiro book (distress)** ∥ qualquer coisa.

### Paralelização PROIBIDA
- **F4 com qualquer coisa que toque `campo_extraido` ou as reconciliações.** Arquivos não disjuntos;
  consequência é divergência silenciosa no núcleo.
- **F7 com F8.** Cenário é parâmetro do motor; juntos, cenário fica hardcoded dentro do motor.
- **F12 com F13.** Recovery consome valuation; paralelos, inventa o valor que distribui.
- **F15 com F16.** PPT antes da camada de apresentação lê dados por conta própria e vira a segunda
  fonte. **É o erro mais provável do roadmap inteiro**, porque PPT é o que mais se quer ver.
- **Qualquer fase com F0 aberta.**

### MVP

**F0 → F7, mais F9 e o diagnóstico factual.** É o ponto em que o sistema passa a SABER os números
que produz. Antes dele, valuation e recovery são aritmética sobre um modelo que o sistema não lê.

| Entrega | Fase |
|---|---|
| Sistema testado == implantado | F0 |
| Perímetro e entidades resolvidos | F1 |
| Nenhum tipo de documento some em silêncio | F2 |
| Dado canônico com identidade, hierarquia e lineage | F4, F5 |
| Reconciliação com intercompany | F6 |
| **Modelo dentro do sistema, com paridade provada** | F7 |
| Estrutura de capital como instrumento | F9 |
| Diagnóstico factual | F2 (lateral) |
| Excel como hoje — fórmula viva | mantido |

**Obrigatório:** F0 · F1 · F2 · F4 · F5 · F6 · F7 · governança contínua · terceiro book distress.

**Nice-to-have:** diagnóstico analítico com índices setoriais · 13-week completo (a parte de DADOS é
obrigatória; a projeção semanal não) · PPT · conversão cambial · múltiplos de mercado · comparação
entre mandatos.

**Adiar:** multi-tenancy real · API pública · comparação entre setores · integrações com ERP ·
granularidade semanal de projeção · `golden_set` reconstruído com rotulagem manual.

---

## 9. DO NOT BUILD YET

Cada linha é algo que, construído agora, ficaria **errado** ou **descartado** — não apenas "cedo".

| # | Não construir | Por quê |
|---|---|---|
| 1 | **Qualquer coisa acima do DATA GATE** | Construir sobre `(secao_canonica, rótulo_norm)` é herdar toda a família de bugs de string. Será refeito |
| 2 | **PowerPoint / geração de deck** | Sem camada de apresentação ele lê dados por conta própria e **vira a terceira fonte de números**. Viola o Princípio 8 de forma difícil de desfazer. O risco mais provável do plano |
| 3 | **Valuation** | Sem motor, é aritmética sobre números que o sistema não lê |
| 4 | **Recovery / waterfall** | Sem `instrumento_divida` com garantia e prioridade, é planilha com cara de sistema |
| 5 | **Projeção semanal do 13-week** | Semana não existe no eixo de período e os insumos não têm consumidor. Produziria um 13-week bonito e falso — o pior desfecho numa mesa de reestruturação |
| 6 | **"Motor de turnaround operacional"** | Não há dado (headcount por função, capacidade, mix). Seria CRM com nome de motor. É categoria de alavanca em F8 |
| 7 | **Camada de "Stress/Red Team" separada** | O red team já existe e é bom; falta apontá-lo ao modelo via MODEL GATE. Camada nova duplicaria um ativo |
| 8 | **Multi-tenancy / RLS por caso** | Real e documentado, mas não bloqueia o caminho crítico. Faria F4 e F7 custarem mais |
| 9 | **Reescrever `campo_extraido`** | A tentação óbvia em F4 e o erro mais caro possível: descarta a camada de evidência e a proveniência junto. Construir **acima**, nunca no lugar |
| 10 | **Golden set com rotulagem manual** | Saiu do produto por decisão do dono (PR #153). `fn_veredito_producao` é o caminho e já existe |
| 11 | **Migrar o Excel para saída de valores** | O `.xlsx` com fórmula viva é ativo comercial, não dívida. O motor muda a FONTE da verdade, não o formato da entrega |
| 12 | **Conversão cambial** | Só quando houver mandato multimoeda real. Hoje o export se recusa a totalizar — comportamento correto |
| 13 | **Novos tipos de documento** | 27 dos 36 existentes ainda não têm consumidor. Acrescentar tipo antes de F2 aumenta o silêncio |
| 14 | **Refatorar `modelo-institucional.ts` antes de F7** | Ele encolhe naturalmente quando vira emissor. Antes, é trabalho jogado fora |
| 15 | **Comparação entre mandatos / benchmark setorial** | Exige conta canônica estável entre casos. Depois de F4 é quase de graça; antes, impossível |

---

## 10. RISCOS DO ROADMAP

| # | Risco | P | Impacto | Mitigação |
|---|---|---|---|---|
| R1 | **F4 quebra o que funciona** | Média | **Crítico** | `campo_extraido` não muda; canônico acima; cada reconciliação migra sozinha com os dois caminhos em paralelo até baterem |
| R2 | **F7 não alcança paridade com o Excel** | Média | **Crítico** | `avaliar-formula.mts` como portão célula a célula ANTES de trocar a fonte. Se não bater, o Excel continua mandando e nada se perde |
| R3 | **O fosso repo↔produção reabre** | **Alta** (é o padrão: já aconteceu com a `0133`, com o n8n e com o provedor) | Alto | F0 cria portão automático. Sem automação, reabre |
| R4 | **PPT construído antes da camada de apresentação** | **Alta** — é o que todos querem ver | Alto | DO NOT BUILD #2 + portão estático P1 |
| R5 | Provedor de IA derruba rodada | **Alta** (já ocorreu: 72 documentos) | Médio | F3: fallback + retomada |
| R6 | Escopo não decidido; roadmap priorizado contra visão contraditória | Média | Alto | F0 inclui reescrever `00_VISAO_E_ESCOPO`. É decisão do dono |
| R7 | Documentação consome a capacidade | Média | Médio | F0: `PRONTIDAO` gerado, não escrito; cabeçalho sob portão |
| R8 | **Rodadas de correção pontual consomem o tempo das duas mudanças estruturais** | **Alta** — padrão visível em 8 migrations sobre a mesma causa | **Alto** | Congelar correções de identidade por string fora de F4 |
| R9 | 13-week sobre dado que não chegou | Média | Alto | F10 depende de F2. Semana ausente é pendência, nunca zero |
| R10 | Autonomia N2 nunca confirmada | Média | Médio | F3 via veredito de produção, publicando que é piso enviesado |

---

## 11. FIRST PHASE EXECUTION PLAN — F0

**Objetivo:** que o sistema testado e o sistema em operação sejam o mesmo, e que o escopo do produto
pare de se contradizer. **Nada de arquitetura nova nesta fase.**

**Entrada:** nenhuma. **Saída:** D1 verde e a decisão de escopo registrada.

### Fatia 0.1 — Inventário do fosso (medir antes de corrigir) · **FEITA em 16/09/2026**
- `fn_instalacao_conferir()` **contra produção** — 0 ausências (via API de gerenciamento do
  Supabase; a sessão não alcança a porta do Postgres direto neste ambiente).
- Migrations pendentes confirmadas por comparação de CORPO, byte a byte, não por suposição:
  `fn_entidade_aprender_cnpj` e `fn_registrar_diagnostico` bateram EXATAMENTE com a `0174` antes
  de qualquer aplicação. **O número real era 3 (`0175`–`0177`), não os 20 que uma estimativa
  anterior, errada, tinha calculado** — o total de migrations no repositório também estava errado
  (122, não 177; o 177 é só o maior número de arquivo, com um pulo de 0044 para 0100).
- Hash do workflow publicado × gerado: `conferir-publicado.mjs` alimentado com os 4 workflows
  reais via API do n8n. Achado grave: a ingestão tinha perdido `multipleFiles: true` no formulário
  (detalhado na fatia 0.3, abaixo).
- **Entregável:** tabela medida, não lembrada — ver `ESTADO.md`, linhas "Aplicadas no Supabase" e
  "Workflow PUBLICADO no n8n".
- *Risco: nenhum — foi leitura.*

### Fatia 0.2 — Aplicar as migrations pendentes · **FEITA em 16/09/2026**
- `0175`, `0176`, `0177` aplicadas EM ORDEM, sonda conferida depois de cada uma (0 ausências nas
  três vezes). Nenhuma DDL estrutural nas três — só `create or replace function` e registro no
  catálogo (`insert into instalacao_requisito`); os `insert`/`update` de dado real que aparecem
  nos arquivos moram DENTRO de corpo de função, e só rodam quando a função for chamada depois —
  não na hora de aplicar a migration. Verificado ANTES de aplicar, não suposto.
- Verificação final: corpo de `fn_entidade_aprender_cnpj` bate byte a byte com a `0177`, e
  `fn_pendencia_cnpj_colide_balcao` (nascida na `0176`) existe.
- **Entregável:** sonda com 0 ausentes — ATINGIDO.
- *Risco medido como baixo na prática: sem DDL estrutural, reversível reaplicando a versão
  anterior da função se algo saísse errado. Nada saiu.*

### Fatia 0.3 — Republicar os workflows e alinhar o provedor · **FEITA em 16/09/2026**
- Os 4 republicados: macro já batia (0 divergências, não precisou); erros e diagnóstico
  republicados com a ferramenta generalizada nesta rodada; ingestão republicada corrigindo o
  achado grave — `multipleFiles: true` void no formulário de upload (o cliente só conseguia subir
  um documento por vez). Confirmado por três fontes antes de agir: o gerador declara o campo de
  propósito, é defeito já nomeado em `.claude/memory/republicacao-do-n8n-perde-toggles.md`, e o
  JSON buscado era fresco (`updatedAt` do dia).
- **Achado no caminho:** `preparar-republicacao.mjs`/`republicar.sh` só sabiam publicar a
  ingestão — hardcoded. Generalizados com `N8N_ARQUIVO_REPO`, com o padrão preservando quem já
  automatizou sem a variável. Uma segunda trava (o script assumia gatilho de formulário em TODO
  workflow) quebrou ao tentar publicar `erros` e foi corrigida na hora — condicional à existência
  do gatilho.
- `Gravar Uso do Lote` presente no canvas — confirmado ao vivo, `disabled: false`.
- Provedor confirmado ao vivo no nó `IA Extrair`: `api.openai.com`, batendo com
  `PROVEDOR_PADRAO = 'openai'` do repositório.
- `FINGERPRINT_EXTRACAO` conferido ANTES e DEPOIS da republicação: `6f5a9374a9d2b1ae` nos dois —
  não mudou, então a próxima rodada não reprocessa nenhum documento à toa.
- **Entregável:** os 4 workflows batem 100% com o repositório — `conferir-publicado.mjs` OK nos
  quatro, verificado depois de cada publicação.
- *Risco realizado: um, achado e corrigido na hora (a trava do formulário). Nenhum PUT feito sem
  `--dry-run` antes.*

### Fatia 0.4 — Portões que impedem o fosso de reabrir (valor permanente) · **FEITA em 16/09/2026**
1. **Sonda contra produção** em agenda, não só contra o banco do CI — fecha o ponto cego de
   `sonda-so-conhece-o-catalogo-que-o-banco-tem`.
2. **Hash do workflow publicado × gerado** — estende `conferir-publicado.mjs`.
3. **Espelho `CLAUDE.md` × CI completo** — hoje o auto-check cobre só `verificar-*.mts` e
   `medir-*.mjs`; ficaram de fora `.claude/hooks/test/` e o passo de regeneração de fixtures.
   Generalizar para TODA categoria de portão.
- **Medição (regra 2):** desligar cada portão e registrar quantos asserts reprovam. Portão que nasce
  vazio não é portão.
- *Agentes: `suites-invariantes` + `revisor-defeito-silencioso`. Risco: baixo.*

### Fatia 0.5 — Reprocessar a rodada "Teste 00"
- Reprocessar os 75 documentos sem linha (73 `extracao_falhou`, 72 por billing).
- **É o primeiro dado honesto do sistema:** a primeira rodada em que o código testado é o executado.
- **Entregável:** ≥95% dos documentos com linha; o que falhar, falha por razão nova e documentada.
- *Risco: baixo. É a validação de que 0.2 e 0.3 funcionaram.*

**Achado, 16/09/2026 — o lote precisa ser dividido, e é limitação conhecida, não bug.** O dono
tentou subir os 127 arquivos do lote em uma execução só (126,6 MB). A execução `#7834` do
workflow de ingestão morreu aos 3m58s com `status: error`, `290MB` de dados de execução, e nem
a interface do n8n consegue mostrar o node/mensagem exata ("This execution's data is too large
to display") — evidência de que o processo estourou memória, não de um documento específico
corrompido (não dá para provar qual node, e por doutrina não afirmamos o que não foi medido).

**Causa provável (hipótese, não confirmada por falta de acesso ao painel):** o n8n roda no
PikaPods (`HANDOFF.md`, RAM fixa por contêiner) e mantém TODO o lote — cada item, cada binário —
na memória do processo durante a execução inteira. Um lote de 126 MB de binário mais a sobra do
Node.js pode estourar o teto de RAM do plano contratado, e o SO mata o contêiner no meio —
por isso nem um erro decente sobra para ler.

**Decisão do dono, 16/09/2026: não redesenhar o workflow agora.** As duas saídas técnicas —
(a) aumentar o plano do PikaPods (rápido, mas só empurra o teto: um lote maior no futuro estoura
de novo) e (b) reescrever o grafo para processar item a item, memória plana independente do
tamanho do lote (correção de raiz, mas é engenharia real com risco de republicação) — ficam
registradas aqui para quando isso voltar a doer. Por ora: **conviver com o limite**, dividindo
lotes grandes em partes de ~90 MB (o `caso_id` é o mesmo entre envios — `fn_upsert_caso` reaproveita
pelo nome do mandato, então dividir em vários envios não perde nem duplica nada).

### Fatia 0.6 — Decisão de escopo e estado regerado · **as duas ADRs: FEITAS em 16/09/2026**
- Reescrever `00_VISAO_E_ESCOPO.md`: o escopo negativo *"não é ferramenta de modelagem financeira"*
  precisa sair ou ser reafirmado. **É decisão do dono** — a engenharia não pode tomá-la, e o roadmap
  inteiro depende dela.
- `PRONTIDAO_POR_ESTAGIO.md` passa a ser **gerado** do banco e do CI.
- ~~Registrar as duas ADRs que governam tudo o que vem depois~~ — **FEITO**:
  `1 Visão e Doutrina/04_ADR_01_EVIDENCIA_IMUTAVEL.md` e `05_ADR_02_ARITMETICA_NO_MOTOR.md`.
  As duas trazem o estado de conformidade MEDIDO, e nenhuma se declara cumprida: a L2/L3 da
  ADR-01 é conteúdo de F1–F4, e a ADR-02 mediu a aritmética em QUATRO casas hoje (n8n 191
  linhas · 44 migrations com soma e 15 `fn_reconciliar_*` · 4 libs do portal · 30 pontos de
  fórmula no Excel). **E a ADR-02 deixa uma fronteira aberta que é do dono**: "planilha viva"
  e "toda aritmética no motor" só convivem sob uma de duas leituras, e escolher é decisão de
  produto — está escrita lá, não resolvida em silêncio.
- *Agente: `estado-e-handoff`. Risco: nenhum técnico.*

### Ordem e commits

```
0.1 --> 0.2 --> 0.3 --> 0.5
   |--> 0.4 (paralela a 0.2/0.3 — arquivos disjuntos)
   |--> 0.6 (paralela a tudo — só docs)
```

Uma fatia por commit, com a mensagem contando defeito, causa e medição (regra 6). Commit sempre pela
sessão principal, capturando o `HEAD` na hora.

### Aceite da F0

| Tipo | Critério |
|---|---|
| **Geral** | `fn_instalacao_conferir()` **em produção** devolve 0 ausentes |
| **Técnico** | hash publicado == gerado · CI falha se produção divergir · espelho `CLAUDE.md`×CI cobre todas as categorias · cada portão novo medido não-vazio |
| **Financeiro** | rodada "Teste 00" reprocessada com ≥95% dos documentos produzindo linha; a diferença de cobertura explicada documento a documento |
| **De produto** | `00_VISAO_E_ESCOPO.md` diz o que o produto é em 2026, e as duas ADRs estão registradas |

### O que a F0 explicitamente NÃO faz

Nenhuma tabela nova. Nenhuma refatoração. Nenhuma migration de arquitetura. Nenhuma camada nova.
**F0 não constrói — ela faz com que medir volte a significar alguma coisa.**
