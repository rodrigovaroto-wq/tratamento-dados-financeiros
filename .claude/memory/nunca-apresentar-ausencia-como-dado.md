---
name: nunca-apresentar-ausencia-como-dado
description: zero fabricado numa célula de premissa é indistinguível de uma medição de zero — sempre branco + nota com o motivo E o efeito
metadata:
  type: business-rule
tipo: doutrina
toca: []
---

Este arquivo é lido por quem vai auditar um número numa entrega a cliente. Um zero escrito porque
o dado não veio é uma **afirmação que ninguém fez**, e ela não tem como ser desfeita depois: quem
lê não distingue de uma medição.

A forma correta é célula em branco + nota dizendo (a) a fonte, (b) por que está vazia e (c) **o
efeito** — "o bloco de dívida cobra juro zero", não só "Focus indisponível". O efeito é a metade
que faz alguém agir.

O mesmo princípio decide o que **não** projeta: valor de decisão do caso não projeta, porque zero
seria uma afirmação que ninguém fez. E é por isso que a projeção das premissas sai do CATÁLOGO
(`natureza`/`formula`), não de uma lista em código.

Pegadinha aritmética que anda junto: **célula vazia é 0 na aritmética do Excel.** Branco resolve o
problema de honestidade da leitura humana, não o do cálculo — confira se algum caminho produz
`#VALUE!` em vez de 0, e nunca deixe um NULL virar zero no meio do caminho
(`completosDe`, as médias, a aba Macro).
