---
name: avaliarcelula-nao-cruza-abas
description: avaliarCelula não segue referência entre abas, e notaDaLinha precisa de includeEmpty — as duas quebram testes do export de formas que parecem bug do código
metadata:
  type: feedback
---

Duas limitações do harness de teste do export que parecem defeito do código sob teste:

- **`avaliarCelula` NÃO segue referência entre abas.** Toda célula de ano da aba Macro é
  `IF('Macro (dados)'!X="","",…)`, então médias e valores da Macro não dão para avaliar por ali.
  Use asserção estrutural e **comente o motivo** — senão a próxima sessão tenta "consertar" o
  teste;
- **`notaDaLinha` precisa de `includeEmpty: true`.** Nota em célula sem valor é pulada por
  padrão, e a doutrina de "nunca apresentar ausência como dado" vive exatamente de notas em
  células vazias.
