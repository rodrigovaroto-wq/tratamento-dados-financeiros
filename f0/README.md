# F0 — Fundação: kit de execução

Este diretório contém os **artefatos concretos da F0**, a fase que precede qualquer linha de
código. Nada aqui é implementação — é o que precisa estar **fechado com o time** para que a
construção do workflow (F1 em diante) não seja feita sobre premissas.

> **Regra de ouro (repetida do `docs/09_PLANO_DE_EXECUCAO.md`):** nada de código antes de
> taxonomia, modelo de status e schema conceitual fechados. A F0 existe para fechar isso.

## Como usar este kit

Cada arquivo tem um estado: **[DECISÃO]** (proposta minha, pronta para o time aprovar/editar),
**[PREENCHER]** (template que só o time pode completar com dados reais) ou **[DRAFT v0]**
(rascunho meu que acelera o time, para cortar/refinar).

| # | Artefato | Arquivo | Estado | Dono sugerido |
|---|---|---|---|---|
| 0.1 | Baseline quantitativo | `01_baseline_quantitativo.md` | [PREENCHER] | Sócio/gerente de operação |
| 0.2 | Decisão build-vs-buy + dono | `02_build_vs_buy.md` | [PREENCHER] | Sócio responsável |
| 0.3 | Taxonomia documental + checklist (Reestruturação) | `03_taxonomia_reestruturacao.md` | [DRAFT v0] | Analista sênior (dono único) |
| 0.4 | Modelo de status + pendências + regra do portão | `04_status_e_pendencias_spec.md` | [DECISÃO] | Arquiteto + sênior |
| 0.5 | Schema conceitual + política LGPD | `05_schema_conceitual.md` | [DECISÃO] | Arquiteto |
| 0.6 | Golden set + protocolo de medição | `06_golden_set_protocolo.md` | [DRAFT v0] | Analista + arquiteto |

## Ordem de execução (dependências e portões)

```
0.1 Baseline ─┐
0.2 Build/Buy ─┼─► decisão GO/NO-GO de construir ──┐
              │                                     │
0.3 Taxonomia (CAMINHO CRÍTICO) ───────────────────┼─► 0.5 Schema ─► 0.6 Golden set ─► GATE F0
              │                                     │        ▲
0.4 Status/Pendências ──────────────────────────────┘────────┘
```

- **0.1 + 0.2 primeiro.** Sem número e sem decisão de construir (e um dono nomeado), não se
  começa. Se o build-vs-buy apontar "buy", grande parte do resto muda de natureza.
- **0.3 é o caminho crítico.** É o trabalho mais difícil e mais político (analistas discordam
  sobre o que é obrigatório). Começa em paralelo com 0.1/0.2 e provavelmente é o que demora.
- **0.4 pode correr em paralelo** — é decisão de desenho, já proposta pronta neste kit.
- **0.5 depende de 0.3 e 0.4** (o schema materializa taxonomia + status).
- **0.6 depende de 0.3** (só se rotula contra uma taxonomia fechada).

## Critério de saída da F0 (GATE para F1)

A F0 está pronta para virar código quando **todos** forem verdade:

1. Baseline quantitativo preenchido com números reais de casos passados.
2. Decisão build-vs-buy registrada e assinada; **dono de operação nomeado**.
3. Taxonomia + checklist de Reestruturação v1 fechados (critério "bom o suficiente para
   começar", não "consenso perfeito").
4. Máquina de status + tipos de pendência + regra do Portão 2 aprovados.
5. Schema conceitual revisado; sensibilidade LGPD mapeada por tipo de documento.
6. Golden set montado com N/tipo suficiente e métricas definidas.

## Depois da F0 (prévia da F1)

F1 = **walking skeleton**: o workflow inteiro conectado ponta a ponta, **todos os estágios em
N0/N1** (sombra/sugestão), 1 caso real atravessando do intake ao Portão 2. Sem autonomia
interpretativa. Só então F2 encorpa cada estágio. Ver `docs/03_MVP_E_ROADMAP.md`.
