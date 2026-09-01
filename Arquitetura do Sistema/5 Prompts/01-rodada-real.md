# Analisar uma rodada real do book

## Quando usar

Depois que o dono rodou um book de verdade. É a rodada real que acha o que nenhuma suíte pega —
todas elas provam a ingestão sobre extração **fiel** (PDF gerado por `reportlab`, texto limpo,
layout conhecido), e documento de mandato real não é fiel.

## Por que funciona

A v48 mostrou que **20 das 27 pendências eram falsas**: a extração estava certa e quem errava eram
as checagens. E o araucária mostrou que uma rodada pode ficar 1h52 de pé sem gravar nada e **sem um
único erro em lugar nenhum**. Então este prompt separa três perguntas que é tentador fundir: o
estágio rodou? o que ele achou é verdade? e a checagem que acusou está certa?

## Como adaptar

- **`[MANDATO]`** — o nome do mandato e o número da execução no n8n.
- **`[N_DOCUMENTOS]`** — quantos documentos entraram, segundo o dono.

## O prompt

```
O dono rodou o book [MANDATO], [N_DOCUMENTOS] documentos. Analise a rodada. Não proponha correção
nenhuma antes de terminar a etapa 1.

## 1. O que de fato aconteceu, com o relógio

Monte a linha do tempo a partir do BANCO, não da tela nem do log do n8n:
- quando cada barreira do workflow foi atravessada (documentos registrados, linhas gravadas);
- `lote_execucao` — o lote FECHOU? Se está vazia, a rodada não terminou, independentemente do que
  a tela disse;
- `execucao_falha`, e as linhas de `ERROR` no log do Postgres.

Vários carimbos de tempo IDÊNTICOS ao segundo são a assinatura de uma barreira do n8n, não de
processamento — diga qual barreira.

## 2. Para CADA estágio: ele rodou, ou não achou nada?

Esta é a pergunta central deste projeto, e as duas situações têm exatamente a mesma aparência.
Para cada estágio, aponte o sinal POSITIVO de execução — uma contagem, uma unidade declarada, o
lote fechado. "Zero pendências" não é sinal de execução.

Constância é assinatura de TETO, não de leitura: cinco documentos de 258 linhas devolvendo 102,
101, 104, 102 e 102 não estão sendo lidos, estão sendo cortados.

## 3. Só então: os achados são verdadeiros?

Para cada pendência aberta, decida entre três — e a terceira é a mais comum:
1. defeito real na extração;
2. o documento é assim mesmo (e a checagem está certa em acusar);
3. **a checagem está errada.** Confira o número contra o PDF antes de mexer no extrator.

Pendência falsa que muda de nome não é correção.

## 4. As três perguntas óbvias, e o que fazer quando as três acertam

Confira, sempre, antes de investigar fundo: a migration está aplicada (a sonda, não o
`ESTADO.md`)? o workflow publicado bate com o do repositório (`conferir-publicado.mjs`)? a cota
apertou (RPD 500 é o limite)? **Quando as três respostas fáceis estão certas, a causa é
estrutural** — procure quadrático, barreira, e estágio que nunca ligou.

## 5. Entregue

Um defeito por fatia, cada um com a causa MEDIDA (não suposta) e o número de antes e depois. Todo
invariante novo medido não-vazio. E, no fim, o que a rodada seguinte tem de medir para provar que
esta correção funcionou.
```
