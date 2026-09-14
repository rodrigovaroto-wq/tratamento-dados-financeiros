---
name: cadencia-da-extracao-73s
description: os 73s entre extrações eram TPM ÷ (entrada do pior PDF + reserva de saída) — e em 14/09/2026, com o TPM real da conta, o PISO histórico de 6s passou a decidir, não mais essa conta
tipo: numero
toca:
  - portal/src/lib/espera-do-lote.ts
  - N8N/build-workflow.mjs
  - N8N/lib/provedor.mjs
  - N8N/lib/extract.mjs
prova: portal/scripts/verificar-mensagem-de-falha.mts
ancora: portal/src/lib/espera-do-lote.ts#SEGUNDOS_POR_DOCUMENTO
ancora_sha: 57fa4093deb5
---

# A cadência da extração ERA 73 s — hoje é 6 s, e o motivo trocou de time

**Esta ficha já foi corrigida uma vez pelo próprio portão que ela documenta.** `conferir.mjs`
marcou-a SUSPEITA em 14/09/2026 porque `SEGUNDOS_POR_DOCUMENTO` mudou de região desde a última
leitura — é a âncora fazendo exatamente o que foi desenhada para fazer.

## O que mudou, e por quê

O dono mediu o lote real da AMO (44 documentos) em **1h28**, com o TPM da conta ainda declarado
no piso do Tier 1 (30.000). Ele então confirmou o número real da conta: **500.000 TPM**. A conta
de "72,768 chamadas/min" que produzia 73 s virou:

```
chamadas por minuto = 500.000 ÷ (20.000 + 16.384) ≈ 13,74
intervalo bruto      = 60 s ÷ 13,74 ≈ 4,37 s
```

**4,37 s é MENOR que o piso histórico de 6 s** (`PISO_BATCHING_MS`, `N8N/lib/extract.mjs` — o
"teste v18", 3 de 16 documentos tomando 429 com 3s). O intervalo é o MAIOR dos três termos
(balde de tokens, limite de chamadas, piso histórico) — `N8N/build-workflow.mjs`,
`INTERVALO_EXTRACAO_MS` — e agora é o **piso** quem vence, não mais a aritmética do TPM.

**A cadência de hoje é 6 s, não porque alguém escolheu, mas porque o balde de tokens deixou de
ser o gargalo.** Se o TPM cair de novo (mudança de conta, de tier, de provedor), a conta do TPM
pode voltar a vencer — é por isso que a fórmula continua com os três termos, e não virou uma
constante.

## A conta ORIGINAL, que ainda explica o REGIME anterior

```
chamadas por minuto = TPM_DA_CONTA ÷ (tokens de ENTRADA do pior caso + max_tokens de SAÍDA)
                    = 30.000 ÷ (20.000 + 16.384) ≈ 0,825
intervalo           = 60 s ÷ 0,825 ≈ 73 s   (arredondado para cima ao segundo cheio)
```

- **30.000 TPM** era o piso declarado do Tier 1 da OpenAI — hoje `PROVEDORES.openai.tpm` é
  **500.000** (`N8N/lib/provedor.mjs`), a conta real medida pelo dono.
- **20.000 tokens de entrada** é o pior PDF já medido, de 20 páginas (`PAGINAS_MAX_MEDIDO`,
  `N8N/lib/custo.mjs`) — não mudou.
- **16.384 de saída** é `max_tokens`, RESERVA de balde — não mudou.

A classificação, que tinha a própria conta em 42 s pelo mesmo motivo, também caiu para **6 s**:
com o TPM real, as duas cadências (extração e classificação) convergem no MESMO piso — como na
era Gemini, quando as duas eram 8s por um motivo diferente (lá o gargalo era CHAMADAS).

## Por que ela já errou quatro vezes — as três primeiras em 11/09/2026, a quarta é o regime mudando

1. **8 s**, herdado do Gemini, onde o gargalo era CHAMADAS e não tokens.
2. **32,768 s** = `60 ÷ (TPM ÷ saída)`. Ignorava a ENTRADA por inteiro.
3. **73 s**, com a entrada somada — correta para o TPM que a conta declarava então (o piso do
   Tier 1), errada não na aritmética, mas na PREMISSA (a conta nunca esteve de fato no piso).
4. **6 s**, 14/09/2026 — não é correção de aritmética: é o TPM real substituindo um chute
   conservador, e o piso histórico assumindo o comando. As primeiras três eram sobre a FÓRMULA;
   esta é sobre o DADO que entra nela.

## O que muda este número

**O TPM da conta**, o **pior caso de páginas** medido, ou **`PISO_BATCHING_MS`** (o único dos
três que não depende de conta nem de provedor — é a folga mínima contra jitter de rede, medida
no "teste v18"). Os três estão declarados no piso, nos arquivos acima. Quem mexer num, mexe nos
espelhos — `N8N/test/workflow-sim.test.mjs` exige que a tela nunca prometa menos do que uma
única chamada já leva, e que a cadência nunca seja mais lenta que o que o balde de tokens OU o
piso realmente exigem; reprova se os espelhos divergirem em qualquer direção.

## O efeito, que é a parte prática

48 documentos × 6 s ≈ **5 minutos** — contra os ~58 minutos que a mesma conta dava com o TPM no
piso do Tier 1. É a mesma fórmula, o mesmo código, e o número mudou porque o DADO real da conta
mudou — não porque alguém tocou em `build-workflow.mjs`.
