---
name: todo-em-portugues-vira-achado-do-sonar
description: a palavra portuguesa "todo" num comentário faz o Sonar abrir S1135 como se fosse marcador de tarefa — e a regra é INSENSÍVEL A MAIÚSCULAS, então "o tempo todo" basta
metadata:
  type: reference
---

A regra `S1135` ("Complete the task associated to this TODO comment") existe em todas as
linguagens que o Sonar analisa aqui — `javascript`, `typescript`, `shelldre` — e ela casa o
**texto**, não o idioma.

**E ela é INSENSÍVEL A MAIÚSCULAS.** A primeira versão desta memória dizia "em CAIXA ALTA", e por
isso não protegeu: na quinta ocorrência a frase era `"o tempo todo"`, toda em minúscula, escrita
por quem tinha acabado de criar este arquivo. Em português, `todo` é palavra corrente — não é um
padrão que dá para evitar por atenção, só por conhecer a regra.

Frases perfeitamente normais viram achado:

```
// republicar faz TODO documento já extraído perder o curto-circuito
// CADA grupo depois do primeiro tem EXATAMENTE 3 dígitos     ← esta passa
```

**Aconteceu CINCO vezes numa única sessão** (09/09/2026), em `N8N/lib/taxonomia.mjs`
("TODO documento"), `N8N/republicar.sh` ("todo mundo" — minúscula), `N8N/lib/cobertura.mjs`,
e duas vezes em `N8N/lib/segunda-contagem.mjs` — a última já DEPOIS de esta memória existir,
porque ela descrevia o gatilho errado. Cada uma custou um ciclo de CI e uma ida ao SonarCloud
para descobrir que era falso positivo.

**O conserto é reescrever, não silenciar.** `CADA`, `qualquer`, `na maior parte das vezes` —
todos dizem a mesma coisa sem colidir. Cuidado: `TODOS OS` também casa (o prefixo `todo`). Silenciar a regra seria pior: ela pega marcador de tarefa de verdade, e este
projeto não tem `TODO` em inglês espalhado justamente porque ela reclama.

**A pegadinha:** o Sonar só reporta **código novo** do PR. Então o padrão já existe em vários
arquivos antigos (`custo.test.mjs`, `workflow-sim.test.mjs`, `extract.mjs`, `classifier.mjs`) e
**não** aparece como achado — não tente "limpar" esses, é alargar o PR sem ganho. Corrija só a
linha que você escreveu.
