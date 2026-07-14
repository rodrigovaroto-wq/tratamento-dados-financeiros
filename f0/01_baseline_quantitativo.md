# 0.1 — Baseline Quantitativo  ·  [PREENCHER]

**Objetivo:** dar chão de números ao projeto. Sem baseline não há como priorizar, calibrar
thresholds, dimensionar custo, nem provar que o sistema reduziu retrabalho. Preencher com
dados **reais de casos passados** de Reestruturação (não estimativas de cabeça).

**Dono:** sócio/gerente de operação. **Fonte:** 3–5 casos recentes representativos.

## A. Volume

| Métrica | Valor | Como medir |
|---|---|---|
| Casos de Reestruturação por ano | _______ | Contagem histórica |
| Entidades por caso (média / máx) | ____ / ____ | Empresas do grupo por mandato |
| Períodos por caso (média) | _______ | Meses/anos de dados solicitados |
| Documentos por caso (média / máx) | ____ / ____ | Total de arquivos recebidos |
| Tipos de documento distintos por caso | _______ | Ver taxonomia (0.3) |

## B. Qualidade do input (crítico — risco nº 1)

Amostrar ~50 documentos reais e classificar por forma de chegada e legibilidade.

| Categoria | % estimado | Observações |
|---|---|---|
| Digital nativo estruturado (Excel/CSV) | ____% | Melhor caso p/ extração |
| PDF nativo (texto selecionável) | ____% | OCR desnecessário |
| PDF escaneado (imagem) | ____% | Exige OCR; qualidade variável |
| Foto / print (WhatsApp, celular) | ____% | Pior caso; candidato a transcrição humana |
| Ilegível / corrompido / incompleto | ____% | Vai para gate de captura |

> Se digital+PDF-nativo < ~50%, o problema nº 1 é **captura**, não triagem — e o gate de
> captura + transcrição humana assistida vira prioridade máxima da F2.

## C. Retrabalho hoje (a dor que o sistema ataca)

| Métrica | Valor | Como medir |
|---|---|---|
| Horas/caso gastas hoje em organizar+validar docs (antes de analisar) | _______ | Estimativa do time |
| Nº médio de "pedir de novo" ao cliente por caso | _______ | Rodadas de reenvio |
| % de casos que avançaram e voltaram por dado incompleto/errado | _______ | Casos com retrabalho a jusante |
| Erro repetitivo mais comum | _______ | Descrição qualitativa |

## D. Custo estimado (para o business case do sistema)

| Item | Estimativa | Nota |
|---|---|---|
| Custo OCR por documento | R$ ____ | Depende do volume de escaneados (B) |
| Custo LLM por documento (classificação+extração) | R$ ____ | Ordem de grandeza; calibrar |
| Custo LLM por caso | R$ ____ | docs/caso × custo/doc |
| Custo de infra (Supabase + N8N + Vercel) / mês | R$ ____ | Planos atuais |

## E. Meta de sucesso (definir agora, medir depois)

| Indicador | Baseline (hoje) | Meta 6 meses |
|---|---|---|
| Horas/caso em organização de dados | _______ | _______ |
| Rodadas de reenvio ao cliente por caso | _______ | _______ |
| % do volume que exige toque humano | (100% no início) | _______ |
| Casos que avançam sem retrabalho posterior | _______ | _______ |

**Critério de pronto (DoD):** seções A–E preenchidas com dados de casos reais; meta de
sucesso acordada com o sócio responsável.
