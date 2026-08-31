---
name: medicao-reescreve-derivado
description: o protocolo `cp` protege o arquivo que você alterou, não os DERIVADOS que a suíte reescreve por baixo — medir invariante de banco deixa o db/schema.sql com o defeito ligado
metadata:
  type: feedback
---

O protocolo de medir um invariante não-vazio (copiar para o scratchpad, desligar a
correção, rodar a suíte, restaurar com `cp`) tem um buraco que só aparece no
banco: **`db/test/run.sh` REESCREVE `db/schema.sql`** a partir do banco que ele
monta. Restaurar a migration não restaura o schema.

Aconteceu em 31/08, na `0156`. A medição desligou o carimbo de `fechado_em`,
rodou o `run.sh` — que regravou o `db/schema.sql` **sem** o carimbo —, e o `cp`
devolveu só a migration. O commit levou o schema da rodada com o defeito ligado,
e o CI reprovou no passo "O schema materializado bate com as migrations",
mostrando exatamente as três linhas que faltavam.

O portão funcionou como devia: ele existe justamente porque "gerar sem conferir
deixa a fonte e o resultado divergirem em silêncio". Quem errou foi o protocolo.

**A regra que fecha isto: depois de qualquer medição que rode uma suíte, rode a
suíte MAIS UMA VEZ com tudo religado, e confira `git status` antes de commitar.**
Não basta conferir o arquivo que você alterou.

Os derivados que uma suíte reescreve neste repositório:

| Suíte | Reescreve |
|---|---|
| `db/test/run.sh` | `db/schema.sql` |
| os quatro `build-workflow*.mjs` | os 4 JSON de workflow |
| `gerar_fixture.py` / `gerar.py` | as 3 fixtures do book e o `GABARITO.json` |

Vale para qualquer um deles: medir mexendo na fonte deixa o derivado com o estado
da medição.
