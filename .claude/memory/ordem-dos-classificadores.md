---
name: ordem-dos-classificadores
description: classificarConta e classificarDemonstracao recebem os mesmos quatro argumentos em ordens diferentes
metadata:
  type: feedback
---

```js
classificarConta(estrutura, secao, chave, secaoCanonica)          // estrutura PRIMEIRO
classificarDemonstracao(secao, chave, secaoCanonica, estrutura)   // estrutura POR ÚLTIMO
```

Os quatro argumentos são os mesmos e nenhum tipo distingue a troca, então um argumento fora de
ordem não gera erro — gera classificação errada. Confira a assinatura em `n8n/lib/classifier.mjs`
antes de chamar qualquer um dos dois, mesmo que você "lembre" da ordem.
