# 0.1 — Baseline Quantitativo  ·  [PARCIAL — dado real limitado]

**Objetivo:** dar chão de números ao projeto. Sem baseline não há como priorizar, calibrar
thresholds, dimensionar custo, nem provar que o sistema reduziu retrabalho. Preencher com
dados **reais de casos passados** de Reestruturação (não estimativas de cabeça).

**Dono:** Rodrigo Varoto. **Fonte:** 3–5 casos recentes representativos.

> **Decisão consciente (2026-07-14):** nesta rodada estruturamos a operação primeiro e
> registramos **apenas o dado real disponível** — não vamos fixar médias/custos "de cabeça".
> As seções B–E ficam como **pendentes de levantamento** (não são bloqueantes do gate F0, mas
> precisam ser preenchidas antes de calibrar thresholds e provar redução de retrabalho).

## A. Volume

| Métrica | Valor | Como medir |
|---|---|---|
| Casos de Reestruturação por ano | _pendente_ | Contagem histórica |
| Entidades por caso (média / máx) | _pendente_ | Empresas do grupo por mandato |
| Períodos por caso (média) | _pendente_ | Meses/anos de dados solicitados |
| Documentos por caso (média / máx) | **~70–100** (estimativa de trabalho) | Total de arquivos recebidos |
| Tipos de documento distintos por caso | _pendente_ (ver Kit Básico em 0.3) | Ver taxonomia (0.3) |

### Ponto de dado real — Caso de referência (1 mandato de reestruturação/turnaround)

Não é o maior nem uma média — é um mandato real usado como âncora de ordem de grandeza:

| Categoria | Qtde de arquivos |
|---|---|
| Balancetes 1º trim/2026 | 11 |
| Balancetes 1º trim/2025 | 10 |
| Faturamento 36 meses | 10 |
| DFs 2024 (9 pastas × 4 + consolidado) | 37 |
| Balanços Patrimoniais 2025 | 11 |
| Global One extras (fora das pastas) | 3 |
| **Total** | **82** |

> A estimativa de **~70–100 docs/caso** deriva deste ponto + percepção do dono. É número de
> trabalho para dimensionar, não meta nem valor final.

## B. Qualidade do input (crítico — risco nº 1)  ·  _pendente de levantamento_

> **Item aberto registrado:** a distribuição de formato (Excel nativo / PDF nativo / PDF
> escaneado / foto) **ainda não foi confirmada**. Sabe-se apenas que a **nomeação dos arquivos
> varia** (uns descritivos como "12M25 DRE Assinado.pdf", outros genéricos) — por isso o
> classificador é **híbrido** (nome do arquivo + leitura do conteúdo). Esta distribuição impacta
> diretamente a estratégia de extração e o dimensionamento do golden set (0.6).

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

> **Estado atual (2026-07-14):** ⏳ **parcial.** Seção A com ponto de dado real (caso de 82
> docs) + estimativa de trabalho (~70–100 docs/caso). Seções B–E **pendentes de levantamento**
> com dados de casos reais. Não bloqueia o gate F0, mas é pré-requisito para calibração (F4).
