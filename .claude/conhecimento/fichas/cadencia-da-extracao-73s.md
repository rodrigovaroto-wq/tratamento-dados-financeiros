---
name: cadencia-da-extracao-73s
description: os 73s entre extrações não são escolha — são TPM ÷ (entrada do pior PDF + reserva de saída), e a conta já errou TRÊS vezes num dia só
tipo: numero
toca:
  - portal/src/lib/espera-do-lote.ts
  - N8N/build-workflow.mjs
  - N8N/lib/provedor.mjs
prova: portal/scripts/verificar-mensagem-de-falha.mts
ancora: portal/src/lib/espera-do-lote.ts#SEGUNDOS_POR_DOCUMENTO
ancora_sha: c7a9e448b0e0
---

# A cadência da extração é 73 s, e ela é consequência — não escolha

**Esta ficha existe por causa de uma medição.** Em 13/09/2026, a Etapa 1 da camada de
conhecimento mediu as cinco perguntas da linha de base contra o índice, e uma ficou PIOR pelo
briefing do que pelo `grep`: *"por que a cadência da extração é 73 s?"*. O motivo é a fronteira
exata entre o que se deriva e o que se escreve — **"73" casa em muitos lugares e nenhum deles
carrega a conta.** O índice sabe apontar o arquivo; não sabe responder. Esta ficha responde.

## A conta

```
chamadas por minuto = TPM_DA_CONTA ÷ (tokens de ENTRADA do pior caso + max_tokens de SAÍDA)
                    = 30.000 ÷ (20.000 + 16.384) ≈ 0,825
intervalo           = 60 s ÷ 0,825 ≈ 73 s   (arredondado para cima ao segundo cheio)
```

- **30.000 TPM** é o piso declarado do Tier 1 da OpenAI (`PROVEDORES.openai.tpm`,
  `N8N/lib/provedor.mjs:66`). Está no PISO de propósito: errar para o lento atrasa, errar para o
  rápido FAZ FALHAR.
- **20.000 tokens de entrada** é o pior PDF já medido, de 20 páginas (`PAGINAS_MAX_MEDIDO`,
  `N8N/lib/custo.mjs`).
- **16.384 de saída** é `max_tokens`, e ele é RESERVA: *"your rate limit is calculated as the
  maximum of max_tokens and the estimated tokens"*.

A classificação tem a própria conta e dá **42 s** — ela reserva muito menos saída
(`TOKENS_SAIDA_CLASSIFICACAO`, 120), e manda o MESMO PDF de imagem na entrada.

## Por que ela já errou três vezes — e as três em 11/09/2026

1. **8 s**, herdado do Gemini, onde o gargalo era CHAMADAS e não tokens. Com a troca de provedor
   virou mentira no mesmo instante: a tela prometia 8 minutos para um lote que levaria uma hora.
2. **32,768 s** = `60 ÷ (TPM ÷ saída)`. Ignorava a ENTRADA por inteiro. Um PDF grande sozinho já
   passava do balde, e nenhum espaçamento entre chamadas evita isso.
3. **73 s**, com a entrada somada — achado por revisão adversarial no mesmo dia.

## O que muda este número

Só duas coisas: **o TPM da conta** subir de tier, ou **o pior caso de páginas** medido crescer.
Os dois estão declarados no piso, nos arquivos acima. Quem mexer num, mexe no outro —
`N8N/test/workflow-sim.test.mjs` exige que a tela nunca prometa menos do que uma única chamada
já leva, e reprova se os dois espelhos divergirem.

## O efeito, que é a parte prática

48 documentos × 73 s ≈ **58 minutos** — é esse o número que a tela mostra antes de enviar, e é
por isso que ele é grande. Ele encolhe sozinho no dia em que o TPM declarado subir.
