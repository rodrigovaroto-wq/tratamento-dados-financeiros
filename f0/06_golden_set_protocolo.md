# 0.6 — Golden Set + Protocolo de Medição  ·  [PROTOCOLO v1]

**Objetivo:** o conjunto de documentos reais rotulados que permite **medir** precisão/recall
por tipo e, com isso, **subir o dial de autonomia** de forma honesta. Sem golden set, todo
estágio interpretativo fica travado em N0/N1 — não por opção, por regra.

> Lição direta do `clipping-news`: threshold só significa algo medido contra dado real.
> "Confiança do LLM" não é probabilidade calibrada — a concordância humano-máquina é.

> **Duas camadas — leia antes (fechado em 2026-07-14, dono Rodrigo Varoto):**
> 1. **O protocolo** (este documento) — dimensionamento, o que se rotula, métricas, laço de
>    calibração. **Fechado como v1**, alinhado à taxonomia v1 (0.3).
> 2. **O golden set físico** — os documentos reais rotulados. É **tarefa de execução** (exige
>    docs reais de clientes + rotulagem + controle LGPD); **não** se monta em documentação.
>    Roda em paralelo à F1, começando com os casos disponíveis e crescendo. Cada tipo só passa
>    a poder subir de dial quando acumula N suficiente rotulado — os demais ficam em N0/N1.

## Dimensionamento (fecha a crítica "30–50 docs é pouco")

- **Tipos core = os 8 do Kit Básico (0.3):** `DRE`, `BALANCO`, `FLUXO_CAIXA`, `COMBINADO`,
  `FATURAMENTO_24M`, `MUTUOS`, `FAT_INTRAGRUPO`, `CONTRATO_SOCIAL`. Tipos Variáveis entram no
  golden set conforme aparecem e acumulam volume.
- **Alvo: ~20–30 documentos rotulados por tipo core** → ordem de **~160–240 documentos** para
  cobrir o Kit Básico.
- **Ritmo de acúmulo difere por granularidade** (nuance importante):
  - Tipos **por entidade × período** (`DRE`, `BALANCO`, `FLUXO_CAIXA`) acumulam rápido — um só
    caso pode render dezenas (o caso real de referência já trouxe ~40 docs de demonstrações).
  - Tipos **por caso** (`COMBINADO`, `MUTUOS`, `FAT_INTRAGRUPO`, `CONTRATO_SOCIAL`) rendem
    ~1 por mandato → precisam de **~20 casos** para atingir o alvo. Esses ficam **mais tempo em
    N0/N1** e é esperado — não é falha.
- **Amostragem estratificada por qualidade** (usar a distribuição da seção B do baseline 0.1):
  incluir digital, PDF nativo, escaneado e foto na proporção real — senão a métrica mente
  sobre o pior caso.
- Se para algum tipo não houver ~20 exemplos, aquele tipo **permanece em N0/N1** até acumular.

## O que é rotulado (ground truth por documento)

| Campo | Descrição |
|---|---|
| `tipo_correto` | Tipo da taxonomia (0.3) |
| `entidade_correta`, `periodo_correto` | Identificadores (Mandato × Empresa × Período) |
| `assinado_correto` | Se é a versão assinada — flag `(Assinado)` da taxonomia (0.3) |
| `legibilidade` | ok / degradado / ilegível |
| `item_checklist_correto` | Item do Kit Básico ao qual pertence |
| `campos_chave` | Para tipos com extração (ex.: saldo de dívida, caixa, receita, faturamento) |
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

**Critério de pronto (DoD):**
- **Protocolo (v1, fechado):** ✅ tipos core = Kit Básico; ✅ dimensionamento (~20–30/tipo) com
  nuance de acúmulo por granularidade; ✅ métricas definidas por tipo/campo; ✅ protocolo de
  rotulagem acordado; ✅ armazenamento com controle de acesso LGPD definido; ✅ laço de
  calibração definido.
- **Golden set físico (execução — em aberto):** ⏳ montagem com N/tipo suficiente e estratificado
  por qualidade. Roda em paralelo à F1, começando com os casos disponíveis. **Não bloqueia** o
  esqueleto da F1 (que nasce em N0/N1); é pré-requisito para **subir o dial** (F4).
