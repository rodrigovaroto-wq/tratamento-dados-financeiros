# Aceite do modelo institucional exportado

Vale para o arquivo do botão **Exportar modelagem** — as 14 abas do modelo, mais a
`Modelagem` e os índices macro. O outro botão, **Exportar dados financeiros**, entrega as
abas de dado linha a linha e tem outro propósito (conferir a extração contra os
documentos); ele não passa por este aceite porque não projeta nada.

Este documento é a **metade humana** do aceite. A outra metade é automática:

```bash
./portal/node_modules/.bin/tsx portal/scripts/auditar-xlsx.mts <arquivo.xlsx>
```

O auditor responde, sobre o arquivo pronto, tudo o que dá para responder **sem abrir o
Excel** — e sai com código 1 se qualquer item reprovar, então ele pode ser usado em script
sem ninguém precisar ler a saída. O checklist abaixo tem **só o que o auditor não consegue
ver**: se o Excel abre, se o gráfico desenha, se o dropdown reprojeta, se o PDF sai
apresentável. É curto de propósito — cada item aqui é minuto de gente, e uma lista que
ninguém termina não é controle.

## Por que a divisão é essa

As quatro suítes provam o **gerador**: elas rodam contra fixture e contra o book sintético,
e reprovam quando o código volta a errar. O auditor prova o **arquivo** — inclusive um
arquivo gerado meses atrás, ou gerado em produção com dado que nenhuma fixture tem. Foi
essa lacuna que deixou o arquivo de 06/08/2026 sair com seis defeitos de número enquanto as
quatro suítes estavam verdes: nenhuma delas olhava o arquivo entregue.

E o que sobra para gente é sobretudo **renderização** — biblioteca de escrita de `.xlsx` não
prova que o Excel aceita o que ela escreveu. Gráfico, VML de nota, área de impressão e
validação de dados são partes do OOXML em que "o arquivo está bem formado" e "o Excel abre
sem reclamar" não são a mesma afirmação.

## Antes de começar

Rode o auditor primeiro. **Item reprovado ali não se resolve no checklist** — é número lido
do arquivo, e a correção é no código (ou, no caso do resíduo, na extração). O checklist só
faz sentido sobre um arquivo que já passou nos itens automáticos.

O que o auditor cobre hoje (para não repetir aqui): as 14 abas existem · o balanço fecha em
todo exercício · a DRE do realizado reproduz o documento · o ativo total é o informado · o
modelo tem conteúdo (não é um balanço vazio que "fecha") · nenhuma fórmula nasce com
`#REF!` · o arquivo pede recálculo ao abrir · as 14 abas declaram área de impressão · o
painel de premissas compõe índice × spread · a linha de câmbio traz nível · **o resíduo de
reconciliação é imaterial** · os 8 gráficos caem dentro da área de impressão do `Output`.

> **O item do RESÍDUO é diferente dos outros, e é o que você lê primeiro quando ele
> reprova.** O modelo fecha o exercício realizado NO NÚMERO DO DOCUMENTO: cada grupo do
> balanço, os dois totais gerais e os quatro níveis da DRE têm uma linha de reconciliação
> que absorve a diferença entre a soma das contas extraídas e o total impresso. É o que
> torna o modelo utilizável — balanço que não fecha não projeta — e é também o que faz "o
> balanço fecha" e "a DRE reproduz o documento" passarem por construção. O que **não** passa
> por construção é o TAMANHO desse resíduo: ele é a medida direta da qualidade da extração
> daquele caso. Zero significa que as contas somam exatamente o que o documento imprime;
> 18% do ativo significa que os totais estão certos e a abertura por conta, por baixo deles,
> não fecha — e aí a conferência do item 9 abaixo tem de ser feita em MAIS de um número,
> porque a composição não é confiável.

> **Arquivo sem as 14 abas não é arquivo quebrado.** O botão *Exportar dados* entrega as
> abas linha a linha, sem projeção — e o auditor diz isso na primeira linha, marcando os
> itens do modelo como não aplicáveis. Nesse arquivo valem os itens do arquivo inteiro
> (fórmula com erro, recálculo ao abrir) e o checklist humano se resume aos itens 1, 2 e 10.

## Checklist (10 itens, ~15 minutos)

Marque **cada** item. Item que você não conseguiu conferir é **não conferido** — escreva
isso, não deixe em branco.

| # | O que fazer | Passa se | Falha se |
|---|---|---|---|
| 1 | Abrir o arquivo no Excel (não no Google Sheets nem no LibreOffice — o alvo é o Excel) | Abre direto | Aparece "o Excel encontrou conteúdo ilegível" / oferece reparar. **Isto é bloqueante**: o reparo remove partes silenciosamente, e o que o dono vê depois não é o que saiu daqui |
| 2 | Olhar a aba `Output` logo na abertura, **sem apertar F9** | Os números estão preenchidos | Células em branco onde deveria haver número — o `fullCalcOnLoad` não pegou nesta versão do Excel |
| 3 | Rolar o `Output` até os gráficos | Os **8** gráficos desenham, com série visível e eixo com anos | Gráfico em branco, moldura vazia, ou "não é possível exibir" |
| 4 | Abrir a aba **`Premissas`**: o `PAINEL DE MODELAGEM` no topo lista as alavancas com o endereço de cada uma. Ir a **uma** delas pelo endereço publicado e trocar o valor (o mais direto é o **dropdown** de índice macro na aba `Revenues, COGS & SG&A`, ex.: de `IPCA` para `PIB`) | O endereço leva à célula certa; o total muda, e a **receita projetada muda junto** nos anos seguintes; o valor no painel acompanha | O endereço aponta para outra coisa, o dropdown não abre, ou muda e nada se recalcula abaixo |
| 5 | No mesmo painel, digitar um **spread** diferente (ex.: `2` no lugar de `0`) | O total recompõe como `(1+índice)×(1+spread)−1` — com índice 5% e spread 2%, dá **7,1%**, não 7,0% | Deu exatamente a soma (7,0%) — a composição virou soma em algum ponto |
| 6 | Depois dos itens 4 e 5, olhar a linha `CHECK do balanço` no topo das abas de driver | Continua **zero** | Saiu de zero: a edição das premissas quebrou o balanço, e o modelo passa a mentir depois de editado |
| 7 | Trocar o **cenário** no seletor (base / otimista / conservador) | Todas as abas se movem juntas e o `CHECK` segue em zero | Alguma aba não acompanha |
| 8 | `Arquivo → Imprimir` (ou exportar PDF) com a aba `Output` selecionada | O PDF sai com os gráficos **dentro** da página, sem coluna cortada ao meio | Gráfico cortado ou fora do PDF |
| 9 | Conferir **um** número contra o PDF de origem — o que o comitê vai olhar primeiro (receita líquida do último exercício realizado) | Igual ao documento, ao centavo | Diferente. Anote a diferença e **pare o aceite** |
| 10 | Passar o olho nas abas em busca de `#REF!`, `#VALUE!`, `#DIV/0!`, `#NAME?` **na tela** (o auditor lê a fórmula; o Excel mostra o resultado) | Nenhum | Anote a célula |

## Se um item falhar

Anote **o item, a aba e a célula** e traga isso — não o print da planilha inteira. Item 1, 6
e 9 são bloqueantes: arquivo com qualquer um deles não vai a comitê.

Os itens 4 a 7 são os que só existem desde que o painel de premissas passou a ser editável
dentro do Excel. Eles são o teste da promessa: **a projeção se refaz sozinha a partir das
premissas macro, dentro do arquivo, sem voltar ao portal.** Se o item 6 falhar, é mais grave
que os outros três juntos — significa que o arquivo aceita edição e responde com número que
não fecha.

## Registro

Cole o resultado do auditor e as marcações do checklist na seção da rodada no `HANDOFF.md`.
Aceite que não deixou rastro não aconteceu — e o próximo a exportar não tem como saber o que
já foi conferido.
