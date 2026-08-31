# Revisão multi-lente

## Quando usar

Antes de fechar qualquer fatia não trivial. Uma passada única de revisão favorece a lente que
aquele revisor usa por padrão, e neste projeto a lente que falta é sempre a mesma: o defeito que
não produz erro.

## Por que funciona

Vários especialistas estreitos, em paralelo, acham mais que um generalista — **desde que a síntese
descarte ruído em vez de concatenar**. Sem deduplicação e sem filtro por cenário de falha
concreto, quatro revisores só produzem uma lista quatro vezes mais longa e menos confiável.

## Como adaptar

- **`[ALVO]`** — o diff, o número do PR, ou `git diff main...HEAD`.

## O prompt

```
Revise [ALVO] com um painel de revisores independentes e depois sintetize num relatório único.
Não revise você mesmo primeiro — despache o painel.

## 1. Despache o painel numa mensagem só

Cada revisor vê o mesmo diff e NÃO vê o achado dos outros. Descarte a lente que não se aplica a
esta mudança em vez de forçar as cinco:

- **Defeito silencioso** (`revisor-defeito-silencioso`) — a lente obrigatória aqui. Estágio sem
  sinal positivo de execução, ausência apresentada como dado, invariante que trava mecanismo em
  vez de comportamento, derivado versionado que ficou para trás.
- **Banco** — a migration acrescenta o requisito à sonda? o teste SQL reprova com a correção
  desligada? o teto por natureza do estágio foi respeitado?
- **Chegada ao ar** — esta correção chega à produção sozinha, ou depende de um apply de migration
  / republicação de workflow / deploy que ninguém vai lembrar de fazer?
- **Fidelidade do número** — algum caminho fabrica, arredonda ou soma o que não se soma? o total
  informado está sendo somado junto com as componentes que ele já inclui?
- **TypeScript/Next** — só se o diff toca o portal.

Cada achado sai como: `arquivo:linha — severidade — a afirmação em uma frase — o cenário de falha
concreto`. **Achado sem cenário de falha não é achado, é palpite: o próprio revisor descarta.**

## 2. Sintetize

1. **Deduplique** — o mesmo problema apontado por dois revisores vira uma entrada, com a descrição
   mais afiada e a nota de quem concordou.
2. **Filtre** — confira contra o diff antes de descartar. Não aceite a alegação do revisor por fé
   em nenhuma das duas direções.
3. **Ordene** — CRÍTICO (número errado chega ao cliente, ou perda de dado) → ALTO → MÉDIO → BAIXO.

## 3. Apresente

Um relatório, o mais grave primeiro. Dizer que nada sobreviveu à síntese é um resultado válido e
útil — não é falha em achar algo.
```
