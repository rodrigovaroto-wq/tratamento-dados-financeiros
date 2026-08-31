---
name: derivado-versionado-precisa-de-git-diff
description: quem roda é o arquivo commitado, não a fonte que o gera — todo derivado versionado precisa de git diff --exit-code no CI
metadata:
  type: architecture
---

Vários artefatos versionados aqui são **gerados**: os 4 JSON de workflow do n8n, as 3 fixtures do
book (`fixture_book_vertentes.sql`, `book-vertentes.json`, `GABARITO.json`), a do canastra, e o
`db/schema.sql`. Sem um portão que regere e compare, o commitado diverge da fonte em silêncio —
e **é o commitado que roda**: o JSON que o dono importa no n8n, a fixture que as suítes leem, o
schema que alguém abre para entender o banco.

Aconteceu de verdade, em 19/08: uma correção no `motor.py` mudou o SQL e o GABARITO, o JSON ficou
para trás, e a suíte de export reprovou em 5 itens comparando o export **novo** com um gabarito
**novo** a partir de uma fixture **velha**. As três pontas se comparam entre si — desincronizar
uma faz as outras duas mentirem sobre a terceira.

Corolário que é a versão perigosa do mesmo defeito: **a correção certa no repositório não
conserta a produção.** Um gerador corrigido sem republicação é documentação.
