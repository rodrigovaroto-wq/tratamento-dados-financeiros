# 09 — Plano de Execução

## Sugestões de alteração adotadas (o delta desta versão)

1. **Doutrina de Autonomia** como espinha dorsal — concilia "construir tudo" com "sem brechas".
2. **Pré-condições explícitas** em toda etapa objetiva → fecha o vazamento de gates.
3. **Gate de captura + transcrição humana assistida** → enfrenta a qualidade real do input.
4. **Limites duros no Portão 2** (bloqueantes não-sobrepujáveis, teto/expiração de ressalva).
5. **Baseline quantitativo + golden set dimensionado** como entregáveis de F0.
6. **Classificação contábil e extração de linhas nascem em sombra (N0)** — medem, não decidem.
7. **Decisão build-vs-buy e dono de operação** registrados antes de construir.
8. **Roadmap = construir tudo → calibrar**, não waterfall de features.

## Plano de execução real

### F0 — Fundação (antes de qualquer construção)

| Etapa | Entregável | Critério de pronto (DoD) |
|---|---|---|
| 0.1 | **Baseline quantitativo**: casos/mês, docs/caso, distribuição de formato/qualidade, horas de retrabalho hoje, custo estimado OCR+LLM/caso | Números reais coletados de casos passados |
| 0.2 | **Decisão build-vs-buy** (1 página) + **dono de operação** nomeado | Decisão registrada e assinada |
| 0.3 | **Taxonomia documental + checklist canônico (Reestruturação)** — dono único, "bom o suficiente para começar" | v1 no Postgres + espelho Obsidian; obrigatórios vs complementares definidos |
| 0.4 | **Modelo de status + tipos/severidades de pendência + regra do Portão 2** (incl. bloqueantes não-sobrepujáveis, teto de ressalva) | Máquina de estados aprovada; regra de portão sem ambiguidade |
| 0.5 | **Schema conceitual** (caso/entidade/período/documento/versão/campo/pendência/decisão/evento/**nível de autonomia**) + **política LGPD** | Modelo conceitual revisado; sensibilidade mapeada |
| 0.6 | **Golden set dimensionado** (~20–30 docs/tipo dos tipos core) + métricas (precisão/recall por tipo) | Golden set com N/tipo suficiente e acesso controlado |

### F1 — Walking Skeleton (o workflow inteiro, magro, ponta a ponta)

- **Entregável:** todos os estágios (E1→E4 + pendências + status + portões) conectados,
  **todos em N0/N1**; 1 caso real atravessa do intake ao Portão 2.
- **Dependências:** F0 completa.
- **Riscos:** integração N8N↔Supabase; modelo de estado. **DoD:** um documento real percorre
  o fluxo inteiro; estado e auditoria reproduzíveis; nenhuma decisão interpretativa autônoma.

### F2 — Encorpar cada estágio (ainda conservador)

- **Entregável:** ingestão + gate de captura + transcrição assistida; classificação (N1);
  validação formal com pré-condições; completude (P1); extração de identificadores (N1) e de
  linhas (N0); reconciliação A (N1) / B-C (aproximação); classificação contábil (N0); export
  com aceite; fila de revisão + dashboard + painel de autonomia; Portão 2 com limites.
- **Dependências:** F1. **DoD:** cada estágio na versão completa em Modo Conservador;
  pendências tipadas corretas; portões com limites duros funcionando.

### F3 — Go-live Conservador

- **Entregável:** operação real com humano no loop no interpretativo.
- **Dependências:** F2. **DoD:** casos reais processados; concordância humano-máquina
  acumulando no golden set + logs de override.

### F4 — Calibração contínua

- **Entregável:** subir o dial estágio a estágio onde a concordância medida for alta; corrigir
  os mal calibrados; cada mudança de nível é decisão versionada/reversível.
- **Dependências:** F3 (não se calibra sem dado real). **DoD:** estágios objetivos em N2/N3;
  interpretativos ≤ seu teto; % de toque humano em queda controlada sem subir a taxa de erro.

**Ordem/dependências:** F0 é pré-requisito duro de tudo. F1 antes de F2 (integração antes de
profundidade). F3 antes de F4 (não se calibra sem dado real).

## Próximos passos a partir daqui

1. **Coletar o baseline quantitativo** (0.1) e **decidir build-vs-buy + dono** (0.2) — sem
   número e sem dono, não se começa.
2. **Fechar taxonomia + checklist de Reestruturação** (0.3) com dono responsável e critério
   "bom o suficiente".
3. **Definir status/pendências/regra de portão** (0.4) com os limites duros.
4. **Schema conceitual + política LGPD** (0.5).
5. **Montar o golden set dimensionado + métricas** (0.6).
6. **Só então** construir — começando pelo **walking skeleton** (F1), tudo em N0/N1, e depois
   encorpando (F2), com Claude Code apoiando etapa a etapa.

> **Regra de ouro:** nada de subir o dial de autonomia de um estágio interpretativo sem golden
> set e concordância medida. É o que mantém "construir tudo primeiro" à prova de erro.
