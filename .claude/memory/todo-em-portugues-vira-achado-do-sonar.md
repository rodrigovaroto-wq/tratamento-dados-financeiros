---
name: todo-em-portugues-vira-achado-do-sonar
description: escrever "TODO" em português (todo/toda/todos) em CAIXA ALTA num comentário faz o Sonar abrir S1135 como se fosse marcador de tarefa em inglês
metadata:
  type: reference
---

A regra `S1135` ("Complete the task associated to this TODO comment") existe em todas as
linguagens que o Sonar analisa aqui — `javascript`, `typescript`, `shelldre` — e ela casa o
**texto**, não o idioma. Este repositório é escrito em português e usa caixa alta para ênfase,
então frases perfeitamente normais viram achado:

```
// republicar faz TODO documento já extraído perder o curto-circuito
// CADA grupo depois do primeiro tem EXATAMENTE 3 dígitos     ← esta passa
```

**Aconteceu quatro vezes numa única sessão** (09/09/2026), em `N8N/lib/taxonomia.mjs`,
`N8N/republicar.sh`, `N8N/lib/cobertura.mjs` e `N8N/lib/segunda-contagem.mjs` — cada uma
custando um ciclo de CI e uma ida ao SonarCloud para descobrir que era falso positivo.

**O conserto é reescrever, não silenciar.** `CADA`, `TODOS OS`, `qualquer` — todos preservam a
ênfase sem colidir. Silenciar a regra seria pior: ela pega marcador de tarefa de verdade, e este
projeto não tem `TODO` em inglês espalhado justamente porque ela reclama.

**A pegadinha:** o Sonar só reporta **código novo** do PR. Então o padrão já existe em vários
arquivos antigos (`custo.test.mjs`, `workflow-sim.test.mjs`, `extract.mjs`, `classifier.mjs`) e
**não** aparece como achado — não tente "limpar" esses, é alargar o PR sem ganho. Corrija só a
linha que você escreveu.
