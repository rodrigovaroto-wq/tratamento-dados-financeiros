---
name: teto-de-autonomia-por-natureza
description: nenhum volume de veredito sobe reconciliação Classe B/C ou classificação contábil acima de N1 — o teto é doutrina e só muda por migration
metadata:
  type: business-rule
tipo: doutrina
toca: []
---

Cada estágio tem um dial de autonomia (N0 sombra → N3 autônomo), e um **teto por natureza** que
não se negocia (`Arquitetura do Sistema/1 Visão e Doutrina/01_DOUTRINA_DE_AUTONOMIA.md`):

- determinístico objetivo: nasce N2, teto N3;
- extração de linhas/tabelas: nasce N0, teto N2;
- reconciliação Classe B/C e classificação contábil (recorrente/EBITDA): teto **N1, nunca
  autônomo**.

Três portas sobem um estágio interpretativo, e elas **não** são intercambiáveis:
`medida` (golden set cego), `medida_por_veredito` (piso enviesado — quem julgou viu o palpite
antes) e `declarada` (motivo assumido, não é medição). O assert mais importante da suíte é que
`medida_por_veredito` **nunca** vira `medida`.

A promoção automática (`0137`) alcança **N2, nunca N3**, e o freio gruda: humano que baixa o nível
de um estágio desliga a auto-promoção dele na hora; religar é `update` explícito.

**O que isso proíbe, e a tentação é real:** se um estágio não sobe, a leitura certa é que falta
evidência, não que falta permissão. Nunca afrouxe `fn_mudar_dial` para destravar alguma coisa —
foi exatamente o buraco que a `0126` fechou, e dois níveis declarados eram falsos quando ela
chegou.
