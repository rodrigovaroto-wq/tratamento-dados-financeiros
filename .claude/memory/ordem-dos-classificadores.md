---
name: ordem-dos-classificadores
description: classificarConta e classificarDemonstracao recebem os mesmos quatro argumentos em ordens diferentes
metadata:
  type: feedback
tipo: armadilha
toca:
  - portal/src/lib/statement-templates.ts
---

```js
classificarConta(estrutura, secao, chave, secaoCanonica)          // estrutura PRIMEIRO
classificarDemonstracao(secao, chave, secaoCanonica, estrutura)   // estrutura POR ÚLTIMO
```

Os quatro argumentos são os mesmos e nenhum tipo distingue a troca, então um argumento fora de
ordem não gera erro — gera classificação errada. Confira a assinatura em `portal/src/lib/statement-templates.ts`
antes de chamar qualquer um dos dois, mesmo que você "lembre" da ordem.

(Até 24/09/2026 esta memória apontava `N8N/lib/classifier.mjs`, onde nenhuma das duas funções
existe — elas moram em `statement-templates.ts`, linhas 915 e 979 nessa data. O `toca` corrigido faz
`buscar.mjs --arquivo portal/src/lib/statement-templates.ts` contar "1 ficha(s)" nesse arquivo (sem
dizer qual); quem acha esta memória é a busca por `classificarConta` ou `classificarDemonstracao`. Ele NÃO faz o portão perceber uma
mudança de assinatura: SUSPEITA só existe para ficha com `ancora`, e esta não tem — se a ordem dos
argumentos mudar, esta memória continua verde e passa a mentir. Confira a assinatura.)
