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
- **Máquina do protocolo (`db/migrations/0126_golden_set.sql`, 19/08/2026):** ✅ o protocolo deixou
  de ser só documento — ver a seção final. O que continua em aberto é a rotulagem.
- **Golden set físico (execução — em aberto):** ⏳ montagem com N/tipo suficiente e estratificado
  por qualidade. Roda em paralelo à F1, começando com os casos disponíveis. **Não bloqueia** o
  esqueleto da F1 (que nasce em N0/N1); é pré-requisito para **subir o dial** (F4).

## O que deste documento virou código (`0126`, 19/08/2026)

Este protocolo ficou um mês como v1 fechada sem um lugar onde morar: `grep -ril golden` devolvia
documentação, o comentário de um script e prosa de migration. A `0126` fechou essa distância — e o
que a motivou não foi este documento, foi a **regra de ouro** do `docs/01`, que `fn_mudar_dial`
(0041) não executava: ela conferia só o teto, e subir a extração para N2 com um motivo em texto
livre era aceito.

| Deste documento | Onde está agora |
|---|---|
| "o que é rotulado" (tipo, entidade, período, assinado, legibilidade, item do checklist, campos-chave, classe contábil) | `golden_rotulo` e `golden_campo` |
| amostragem estratificada por qualidade | `golden_documento.estrato` (`digital`/`pdf_nativo`/`escaneado`/`foto`) |
| "tipos core = os 8 do Kit Básico" | **não** virou lista: sai de `obrigatoriedade = 'obrigatorio'` na taxonomia (0002), que já marcava exatamente esses oito |
| nuance de acúmulo por granularidade | `granularidade` no retorno de `fn_golden_cobertura` — tipo por CASO rende ~1 por mandato, e a demora aparece em vez de parecer negligência |
| as cinco métricas | `fn_golden_classificacao`, `fn_golden_identificadores`, `fn_golden_campos`, `fn_golden_inter_avaliador`, `fn_golden_classe_a` |
| dois rotuladores; "se humanos discordam, a máquina não tem como acertar" | `fn_golden_consenso`: campo sem consenso **sai** do placar da máquina e é contado à parte |
| "congelado por rodada; ampliado, não editado retroativamente" | `golden_rodada.congelada_em`, com gatilho — rodada congelada não aceita rótulo, não descongela e não é renomeada |
| armazenamento com controle de acesso | RLS append-only (SELECT+INSERT, nenhuma de UPDATE/DELETE) nas três tabelas de rótulo |
| o laço de calibração (o losango "concordância alta e estável?") | `fn_golden_suficiente`, consultada por `fn_mudar_dial` |

**Três coisas que este documento não decidia e a `0126` teve de decidir:**

1. **O LIMIAR de concordância.** Este protocolo dimensiona o **N** e diz "concordância alta e
   estável" sem número. O limiar entrou como **dado** (`golden_criterio.concordancia_minima`,
   default 0,95) e o default tem motivo verificável: é o `limiar_auto_clear` em vigor desde a
   `0019`. Auto-aceitar linha a 0,95 com medição abaixo de 0,95 seria apostar acima do que se sabe.
2. **Onde o portão morde.** Na subida que **alcança N2/N3** — não em toda subida. N1 é sugestão com
   revisão de 100%: cobrar medição para exibir sugestão travaria o caminho que a doutrina manda
   percorrer. Descer nunca pede nada.
3. **Golden sintético não sobe dial** (`golden_documento.origem`). Não estava previsto aqui, e é o
   que impede o portão de ser teatro: os books do repositório têm `GABARITO.json`, rotulá-los é de
   graça, e a concordância sairia ~100% por construção — medindo o instrumento, não o modelo.

**E uma lacuna deste protocolo, agora nomeada:** ele raciocina por **tipo** ("se para algum tipo não
houver ~20 exemplos, aquele tipo permanece em N0/N1"), e o dial do `f0/04` é por **estágio**.
Autonomia por (estágio × tipo) não existe no schema. Enquanto não existir, `fn_golden_suficiente`
adota a leitura conservadora — **o tipo mais fraco governa o estágio** —, que é o fechamento
default-para-humano aplicado à própria calibração. Mudar isso é decisão de modelo de dados, e não
se toma de lado.

**O que continua sendo execução, e não muda:** a rotulagem. Documento real de cliente, com controle
de acesso, ~20 por tipo core, estratificado, dois rotuladores nos casos ambíguos, rodada congelada
ao fim. Era o que este documento já dizia em 14/07 e continua verdadeiro.
