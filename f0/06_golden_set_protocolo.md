# 0.6 — Golden Set + Protocolo de Medição  ·  [DRAFT v0]

**Objetivo:** o conjunto de documentos reais rotulados que permite **medir** precisão/recall
por tipo e, com isso, **subir o dial de autonomia** de forma honesta. Sem golden set, todo
estágio interpretativo fica travado em N0/N1 — não por opção, por regra.

> Lição direta do `clipping-news`: threshold só significa algo medido contra dado real.
> "Confiança do LLM" não é probabilidade calibrada — a concordância humano-máquina é.

## Dimensionamento (fecha a crítica "30–50 docs é pouco")

- **~20–30 documentos rotulados por tipo core.** Com ~8–12 tipos core da taxonomia (0.3), isso
  dá **~200–350 documentos**.
- **Amostragem estratificada por qualidade** (usar a distribuição da seção B do baseline 0.1):
  incluir digital, PDF nativo, escaneado e foto na proporção real — senão a métrica mente
  sobre o pior caso.
- Se para algum tipo não houver ~20 exemplos, aquele tipo **permanece em N0/N1** até acumular.

## O que é rotulado (ground truth por documento)

| Campo | Descrição |
|---|---|
| `tipo_correto` | Tipo da taxonomia (0.3) |
| `entidade_correta`, `periodo_correto` | Identificadores |
| `legibilidade` | ok / degradado / ilegível |
| `item_checklist_correto` | Item ao qual pertence |
| `campos_chave` | Para tipos com extração (ex.: saldo de dívida, caixa, receita) |
| `classe_contabil` (quando aplicável) | Rótulo da taxonomia contábil |

## Métricas (por tipo de documento e por campo)

| Métrica | Para quê |
|---|---|
| Precisão / Recall / F1 da **classificação** doc→tipo | Subir dial da classificação |
| Acurácia dos **identificadores** (tipo/período/entidade) | Subir dial da extração de identificadores |
| Erro de extração de **campos financeiros** (exato / dentro de tolerância) | Autorizar extração de linhas a sair de N0 |
| **Concordância humano-máquina** na classe contábil | Manter/mover classificação contábil (teto N1) |
| Taxa de **falso-positivo** de reconciliação Classe A | Subir Classe A de N1→N2 |

## Protocolo de rotulagem

1. Dois rotuladores independentes nos casos ambíguos; medir **concordância inter-avaliador**
   (se humanos discordam, a máquina não tem como acertar — mantém revisão).
2. Rótulos versionados junto da versão da taxonomia usada.
3. Golden set **congelado** por rodada de calibração; ampliado, não editado retroativamente.
4. Armazenar com **controle de acesso LGPD** (contém dados reais de clientes).

## Como o golden set governa o dial (o laço de calibração)

```
medir concordância contra golden set
        │
        ▼
concordância alta e estável no tipo X?  ──não──►  mantém nível atual
        │sim
        ▼
subir 1 nível o dial do estágio (decisão versionada/reversível)
        │
        ▼
monitorar taxa de erro em produção; regrediu? ──►  descer o dial
```

**Critério de pronto (DoD):** golden set montado com N/tipo suficiente e estratificado por
qualidade; métricas definidas por tipo/campo; protocolo de rotulagem acordado; armazenamento
com controle de acesso.
