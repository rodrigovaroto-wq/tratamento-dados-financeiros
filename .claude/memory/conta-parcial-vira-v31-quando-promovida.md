---
name: conta-parcial-vira-v31-quando-promovida
description: uma função que cobra SÓ PARTE do custo de propósito vira "aceita lote que não cabe" no dia em que passa a decidir sozinha por documento — o comentário que a justificava continua verdadeiro e a promoção o torna irrelevante
metadata:
  type: architecture
tipo: doutrina
toca:
  - N8N/lib/custo.mjs
prova: N8N/test/*.test.mjs
---

**O caso, 13/09/2026.** `custoEstimadoPorTamanho`, para documento de TEXTO, cobra **só a entrada**
— `bytes / CARACTERES_POR_TOKEN × preço de entrada`. Isso é deliberado e o comentário dela explica
por quê: a saída de um documento de texto depende de quantos NÚMEROS ele tem, não de quantos bytes,
e quem cobria a saída mínima era o piso `CUSTO_MINIMO_CHAMADA_USD`. Enquanto essa conta servia ao
lote INTEIRO (regra tudo-ou-nada, um documento não medido derrubava todos no mesmo caminho), o piso
bastava: os documentos medidos ao lado carregavam a conta.

No dia em que o orçamento virou **documento a documento**, essa mesma função passou a decidir
sozinha o custo de um arquivo. E aí ela cobrava **46× menos** que a conta por conteúdo do mesmo
arquivo:

```
20 CSVs de 1 MB sem nenhuma linha com número contada
  conta por tamanho (o caminho "conservador"):  US$  1,31  → PASSAVA no teto de US$ 3
  conta por conteúdo, 12.000 células cada:      US$ 15,26
  a regra tudo-ou-nada, que a mudança substituiu, RECUSAVA esse lote
```

A correção que desfazia um "recusa lote que cabe" (o proxy por byte cobrando 75× o real) tinha
instalado um **"aceita lote que não cabe"** — o v31, o incidente mais caro do projeto — e os seis
invariantes escritos na mesma fatia ficaram todos verdes, porque todos usavam PDF.

## O que generalizar

**Toda conta parcial carrega uma premissa sobre quem paga o resto.** "Só a entrada, porque o piso
cobre a saída"; "sem desconto, porque o caminho cego não tem base"; "1 bloco, porque documento sem
texto vai inteiro". A premissa está certa no lugar onde a função nasceu, e **a promoção dela a
decisor autônomo não a invalida no comentário — invalida no comportamento.** O comentário continua
lá, verdadeiro e tranquilizador, descrevendo um mundo que acabou.

**A pergunta a fazer ao mover uma conta de escopo:** *o que, no escopo ANTIGO, pagava a parte que
esta função não cobra — e esse pagador ainda existe no escopo NOVO?*

**E a pergunta ao escrever o invariante:** *ele exercita os MESMOS ramos que a mudança abriu?* Os
seis invariantes da fatia só construíam documentos `formato: 'pdf'`; o buraco era no ramo de texto.
Um invariante que não visita o ramo novo tem exatamente a mesma aparência de um invariante que o
visita e não acha nada (regra 7).

## O que ficou de defesa

- toda estimativa de documento **não medido** tem piso na estimativa plana por chamada — o número
  calibrado de "não sei nada sobre este arquivo";
- o ramo de texto estima a saída por `CARACTERES_POR_CELULA_ESTIMADA` (p90 medido dos 52
  documentos dos books), como o ramo de PDF escaneado já estimava por página;
- cinco invariantes novos, medidos não-vazios, e os dois casos que faltavam na TABELA do
  `espelho-inline` — sem eles o `jsCode` gerado estourava `ReferenceError` em produção com a suíte
  inteira verde.

E a lição de processo, que é a mais barata de repetir: **quem achou isto foi a revisão adversarial,
não o autor.** O autor tinha acabado de escrever, no próprio comentário do código, que aquele
caminho "nunca subestima por construção" — uma frase que a medição do próprio repositório
desmentia (o documento mais denso do book custa US$ 0,0222 e o proxy cobra US$ 0,0153: 0,69×).
