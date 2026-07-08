# 00 — Visão e Escopo

## Contexto

A Oria (boutique de Reestruturação e M&A) recebe documentos de clientes com um checklist
básico, gerando retrabalho, avanço prematuro com informação incompleta e erro repetitivo.
O objetivo é transformar as submissões dos clientes em uma base **organizada, validada,
auditável, reconciliada e pronta** para avançar com segurança para análise.

## Leitura crítica do plano original (as 10 camadas)

### Forte
- Separação **Camada A (intake — "o que pedir/receber/organizar")** vs **Camada B (triagem —
  "o que recebemos é suficiente, correto e confiável?")**. O valor real está na B.
- Princípio **determinístico-primeiro; LLM só na ambiguidade residual**. É o que o
  `clipping-news` já faz na prática.
- Disciplina de saída ambígua: **confiança + justificativa + trilha + override**.
- Recusa explícita de "modelagem 100% automática".
- Começar conservador e calibrar com casos reais.

### Frágil
- **10 camadas sequenciais = fantasia waterfall.** Cada camada vira um gate, cada gate vira
  um gargalo humano potencial. Na prática são ~5 estágios com 2 portões reais.
- **Pendências e status como "Camada 7/8" sequenciais** — erro estrutural. São
  **transversais**: pendência nasce em qualquer estágio; status é estado do caso, não etapa.
- **Reconciliação classificada como "média confiabilidade".** Otimismo perigoso: a maioria
  (mapa de dívida vs balanço, mútuos/intragrupo, garantias vs docs dos sócios, contrato
  social vs organograma) **não é problema de threshold** — é mapeamento e julgamento.

### Genérico demais
- **"Extração de campos estruturados simples".** "Simples" carrega o projeto inteiro. Docs
  financeiros BR (balancetes, DREs, mapas de dívida, contratos) são heterogêneos. O único
  item objetivamente barato e de alto ROI na entrada é **completude** e **identificadores**.
- **"Preparação de base para modelagem"** sem schema-alvo é caixa vazia; é consequência.

### Ambicioso demais
- Classificação contábil (recorrente/EBITDA), base para modelagem e apoio analítico **como
  automação** em horizonte próximo. Normalização de EBITDA é *o* julgamento do ofício;
  automatizar até "sugestão" cedo demais cria **viés de ancoragem** (pior que não sugerir).

### Onde a interpretação humana continua inevitável (não terceirizar para IA)
Recorrente vs não-recorrente vs extraordinário; materialidade; "mesma rubrica/mesmo evento"
em reconciliação; divergência aceitável vs bloqueante; premissas de modelagem; estratégia de
negociação com bancos (que nem deveria estar neste sistema).

## Redefinição madura

> **O que é:** um sistema de **intake governado e prontidão de dados** que recebe submissões
> de clientes e produz um **dataset estruturado, completo, formalmente válido, reconciliado
> e auditável**, com um **portão explícito de go/no-go para análise**. O produto é
> *confiança no dado + redução de retrabalho + trilha de auditoria* — não análise automática,
> não modelagem automática.

**O que o sistema É**
- Um pipeline de estados sobre documentos e dados de um *caso*.
- Um motor de completude e pendências determinístico.
- Uma camada de validação formal (o documento é o que diz ser, do período/entidade certos,
  legível e íntegro).
- Um portão de aprovação humana com auditoria.
- A fonte única da verdade do **estado** de cada caso.

**O que o sistema NÃO é (escopo negativo explícito)**
- Não é ferramenta de modelagem financeira.
- Não é motor de decisão contábil.
- Não decide estratégia de negociação.
- Não substitui o julgamento do analista — o **habilita** com dado confiável.

**Personas**
- **Analista Oria** (foco inicial): revisa extração/pendências, corrige, solicita reenvio.
- **Revisor sênior / gerente**: aprova avanço, faz override de classificação, é o único que
  autoriza "aceitar com ressalva".
- **Cliente** (fase futura): envia informação de forma guiada e vê status.

**Unidade de trabalho:** o **caso** (um mandato de reestruturação), com N **entidades**
(empresas do grupo), M **períodos**, e documentos versionados por (tipo × entidade × período).
