# O estágio está verde e você não confia

## Quando usar

Quando um estágio não abre pendência, não gera erro, e mesmo assim algo está errado — ou quando
você quer provar que ele está mesmo rodando. É o padrão de erro que mais custou neste projeto, e
ele nunca aparece num diff.

## Por que funciona

Um estágio desligado tem exatamente a mesma aparência de um estágio que rodou e não achou nada.
A reconciliação ficou onze dias parada em silêncio; o fatiamento nunca ligou e a régua de
cobertura nunca disparou; a tela dizia "Tudo pronto" sobre uma execução morta. Nenhum dos três
produziu uma linha de erro. Este prompt procura o **sinal positivo de execução**, em vez de
concluir a partir da ausência de achado.

## Como adaptar

- **`[ESTÁGIO]`** — o estágio sob suspeita (ex.: "a guarda de extração incompleta").

## O prompt

```
Investigue [ESTÁGIO]. A hipótese de trabalho é que ele NÃO está rodando — trate "não abriu
pendência" como ausência de evidência, nunca como evidência de ausência.

## 1. Encontre o sinal positivo

O que este estágio produz quando roda e não acha nada? Uma contagem, uma linha na trilha, uma
unidade declarada, um lote fechado? Se a resposta for "nada — ele só não abre pendência", esse é
o defeito, e a correção é fazê-lo dizer que rodou. Um estágio sem sinal positivo é inauditável
por construção.

## 2. Siga o dado de trás para frente, fronteira por fronteira

Do consumidor até a origem, instrumentando CADA fronteira entre componentes. O que já quebrou
aqui foi sempre fronteira, não lógica:
- um nó do n8n substitui o item pelo resultado da query e o campo somem (`Gravar Campos`);
- um nó monta um item novo com cinco campos e descarta o que o anterior mediu (`Montar Req
  Extracao`), e a guarda seguinte fica sem a entrada de que precisa;
- uma função existe com a assinatura certa e o corpo velho (`create or replace`).

Em cada fronteira, diga qual valor entrou e qual saiu. Não adivinhe a camada culpada.

## 3. Confira o que está NO AR, não o que está no repositório

A suíte mede o JSON do repositório. A sonda de catálogo pode ver a assinatura de uma função com o
corpo velho. Migration escrita não é migration aplicada. Diga, para este estágio, qual das três
você conferiu e como.

## 4. Uma hipótese por vez

Uma hipótese, a menor mudança possível para testá-la, nunca duas ao mesmo tempo. Se três
correções seguidas falharem, PARE e questione a arquitetura — três tentativas falhas significam
que o problema não está onde você está procurando.

## 5. Feche com um invariante medido não-vazio

Desligue a correção, rode a suíte, conte os asserts que reprovaram, religue (restaurando com `cp`,
nunca com `git checkout`). O número vai na mensagem do commit. E o invariante afirma o
COMPORTAMENTO — "o estágio declara quantos blocos leu" —, nunca o mecanismo.
```
