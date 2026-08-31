---
name: backtick-quebra-jscode
description: um backtick num COMENTÁRIO dentro do template de um nó Code do n8n fecha a string e quebra o JS gerado — aconteceu duas vezes
metadata:
  type: feedback
---

O gerador monta o `jsCode` de cada nó Code como template literal. Um backtick dentro de um
comentário do código do nó fecha a string e o JavaScript do nó sai quebrado. O gerador **não
parseia** o resultado — ele só concatena — então nada acusa ali: só o teste pega.

Aspas simples em contração (`e'`) têm o mesmo efeito no lado SQL.

Aconteceu duas vezes. Rode `node --test 'n8n/test/*.test.mjs'` depois de qualquer edição em
`n8n/build-workflow*.mjs`, mesmo que a mudança tenha sido "só um comentário".
