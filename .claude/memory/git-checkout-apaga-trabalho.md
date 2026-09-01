---
name: git-checkout-apaga-trabalho
description: git checkout <arquivo> para desfazer um patch de medição apaga TODO o trabalho não commitado do mesmo arquivo — copie para o scratchpad e restaure com cp
metadata:
  type: feedback
---

O fluxo obrigatório de medir um invariante não-vazio (desligar a correção, rodar, religar) leva
direto a essa armadilha, e ela cobrou uma vez na sessão 19.

`git checkout <arquivo>` e `git restore <arquivo>` restauram o arquivo **inteiro** do índice — não
só o patch de medição que você acabou de aplicar. Todo o resto do seu trabalho não commitado
naquele arquivo vai junto, sem aviso e sem desfazer.

O jeito certo:

```bash
cp Vercel/src/lib/export.ts "$SCRATCH/export.ts.bak"
#   ... aplica o patch de medição, roda a suíte, confirma que reprova ...
cp "$SCRATCH/export.ts.bak" Vercel/src/lib/export.ts
```

Existe um hook em `.claude/hooks/proteger-descarte.mjs` que bloqueia essa forma de
`git checkout`/`git restore` e explica o caminho seguro. Ele é a única trava dura do projeto —
todos os outros hooks degradam em silêncio.
