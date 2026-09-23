---
name: verificador-sem-controle-positivo
description: um "nenhum encontrado" só vale se a mesma checagem PROVADAMENTE acha o que procura — cinco verificações do PR #238 responderam uma pergunta diferente da que foi feita, e três delas diziam "tudo certo"
metadata:
  type: feedback
tipo: doutrina
toca:
  - Supabase/test/medicao-denominador.test.mjs
  - Supabase/test/sonda-producao.mjs
---

**MEDIDO nas sessões de 21–23/09/2026 (PR #238).** A regra 7 do CLAUDE.md fala de estágio do
pipeline. Esta é a mesma regra aplicada à VERIFICAÇÃO que a sessão faz à mão: uma checagem que não
consegue achar o que procura devolve exatamente a mesma resposta que uma que procurou e não achou.

Os cinco casos, todos reais, todos pegos só porque alguém desconfiou da resposta:

| Checagem | Respondeu | Verdade |
|---|---|---|
| `git merge-tree` + grep por marcador de conflito | "0 conflitos" (e foi dito ao dono) | conflito em `ESTADO.md` e `grafo.jsonl` — o formato de saída do git atual não tinha o marcador procurado |
| lista de funções com `sed` minúsculo, cruzada com a F2 | "nenhuma colisão" | a única linha maiúscula, `fn_upsert_entidade` — justamente a mais arriscada — nunca foi checada |
| protocolo de medição da 0183, guarda desligada | "0 asserts reprovaram" | a migration morreu antes, o teste nem rodou |
| primeiro portão de denominador, pareando pelo 1º teste citado | "a 0179 diverge" | a 0179 estava certa; o portão pareava o arquivo errado |
| `grep -c` de assert num teste | "33 asserts" | 32 — o próprio comentário do cabeçalho citava o padrão |

**O que funcionou, e passou a ser o procedimento:** antes de acreditar num zero, rodar a mesma
checagem contra um caso em que ela TEM de achar algo. Com `fn_upsert_entidade`, o controle positivo
("o padrão acha a função na própria 0183? → 2") é o que fez o "0 nas migrations da F2" significar
alguma coisa. No script de medição, a checagem "o teste aparece no log?" é o que transformou um zero
falso em "contagem inválida". No portão de denominador, rodar contra o commit `070b0c2` — o defeito
real — é o controle positivo dele.

**E o caso de tempo, parente próximo:** ler o disco enquanto um agente em background ainda edita dá
um retrato que nunca existiu como estado final. Na 0182 isso produziu três `FALHOU:` que não eram
defeito (o agente estava restaurando o arquivo depois da medição). Só conferir depois do relatório
do agente, e conferir contra o arquivo que ele diz ter deixado.
