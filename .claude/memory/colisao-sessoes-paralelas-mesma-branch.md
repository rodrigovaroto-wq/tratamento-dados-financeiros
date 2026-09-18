---
name: colisao-sessoes-paralelas-mesma-branch
description: Como resolver quando duas sessões paralelas fazem push na mesma branch — merge é correto, nunca rebase nem force-push
metadata:
  type: architecture
---

## O que aconteceu

Duas sessões paralelas (mesmo usuário, abas diferentes do Claude Code) trabalharam na mesma branch `claude/intelligent-euler-kc7uao` em paralelo. A primeira sessão (F1.3) fez um commit e um push bem-sucedido. A segunda sessão (F1.4), despachada após a primeira, tentou fazer push e foi rejeitada com `Updates were rejected because the tip of your current branch is behind its remote counterpart` — o commit de handoff da primeira sessão tinha chegado primeiro.

## Por que **não** rebase ou force-push

- **Rebase** muda o histórico e, pior, pode mover o merge incorretamente se feito com `--force`.
- **Force-push (`-f`)** descarta trabalho da sessão paralela — exatamente o que a `CLAUDE.md` proíbe: "nunca rebase, nunca force-push".

O padrão neste projeto é um push bem-sucedido **por fatia**, tudo na sessão principal. Duas sessões paralelas violam esse padrão de uma forma que é detectável **apenas no momento do push**: ambas acreditam que vão comitar em sequência, até uma tentar fazer push.

## A solução correta: merge

```bash
# Depois que o push foi rejeitado:
git fetch origin claude/intelligent-euler-kc7uao  # trazer a versão remota
git log --oneline -1 origin/claude/intelligent-euler-kc7uao  # ver o commit paralelo
# Se o commit paralelo é compatível (não modifica os mesmos arquivos ou sua modificação não colide):
git merge origin/claude/intelligent-euler-kc7uao
# Isso cria um commit de merge que une os dois históricos
git push origin claude/intelligent-euler-kc7uao  # agora o push funciona
```

## Verificação antes de aceitar o merge

1. **Conferir que não há alterações nos mesmos arquivos**: `git diff HEAD...origin/claude/intelligent-euler-kc7uao -- <lista de arquivos da sua tarefa>`
2. **Se houver conflito real** (raridade, pois as sessões eram paralelas), resolver no arquivo e comitar a resolução.
3. **Se não houver conflito**, o merge automático é seguro e cria um histórico verdadeiro de que dois caminhos foram percorridos em paralelo.

## Por que é melhor que rebase

O merge **preserva a verdade**: o histórico diz que "duas sessões rodaram, fizeram commits incompatíveis no push, e foram unidas". Rebase apagaria esse evento e diria "foi linear o tempo todo" — mentira.

Rebase com outro objetivo (deixar commits lineares em `main` antes de merge) é um padrão legítimo de **porta de entrada** em outros projetos. Aqui a porta de entrada é "a sessão principal nunca rebaseia e só comita quando resolve divergência com `git merge`", então não há diferença aritmética: um merge se torna um commit normal no que importa (a sessão principal não divide a autoria).

## Histórico da rodada F1

```
HEAD (sessão F1.4)                a3381d8 (F1.5 — participacao)
  ↓
5c6916a (merge)                   — une as duas sessões
  ↓
57a1814 (sessão F1.4)             — F1.4: perimetro
  ↑
ceb2acc (commit de handoff F1.3)  — outra sessão confirmou F1.3
14e80da (F1.3)                    — papel_no_grupo
```

A `5c6916a` é um commit de merge legítimo. Não é "poluição de histórico"; é registro de que duas frotas aconteceram.
