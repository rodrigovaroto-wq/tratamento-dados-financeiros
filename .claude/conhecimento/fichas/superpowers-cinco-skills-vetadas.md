---
name: superpowers-cinco-skills-vetadas
description: o plugin superpowers 6.3.0 foi auditado skill por skill e DESLIGADO neste projeto — 5 das 14 contradizem as regras 1, 6 e 7, as 9 restantes somam 29,7k de on-invoke, e ele se contradiz sobre o caso exato da regra 2
tipo: doutrina
toca: []
---

# Superpowers 6.3.0: auditado skill por skill e DESLIGADO neste projeto

O plugin `superpowers@superpowers-marketplace` (v6.3.0, commit `b36e0829`) foi instalado em
16/09/2026 no escopo `user`, **auditado skill por skill contra as sete regras** antes de qualquer
uso, e **desligado neste projeto** em `.claude/settings.json` (`enabledPlugins`). Continua ativo
nos outros projetos do dono; o desligamento é só aqui.

Ele não repete o problema dos 52 comandos importados na forma: traz **14 skills, 0 agentes,
0 comandos de barra, 0 servidores MCP**.

## A conta que decidiu, e o número certo dela

A primeira versão desta ficha comparou **always-on com always-on** — ~1,5k do plugin (~688
declarados mais ~800 que o hook `SessionStart` injeta ao colar `using-superpowers/SKILL.md`
inteiro dentro de `<EXTREMELY_IMPORTANT>`) contra ~4,9k dos 19.439 bytes cortados em 16/09. Por
essa conta o plugin ganhava 3x, e **essa era a comparação errada**.

O custo do superpowers não é always-on, é **por invocação** — e a única skill always-on dele
existe para maximizar invocação: *"If you think there is even a 1% chance a skill might apply to
what you are doing, you ABSOLUTELY MUST invoke the skill… YOU DO NOT HAVE A CHOICE."* As nove
skills que sobreviveriam ao veto somam **29,7k tokens de on-invoke** (`brainstorming` 5,6k,
`writing-skills` 9,7k, `systematic-debugging` 3,4k, `test-driven-development` 3,3k,
`receiving-code-review` 2,2k, `dispatching-parallel-agents` 2,2k,
`verification-before-completion` 1,2k, `using-superpowers` 1,1k, `requesting-code-review` 1,0k),
mais ~1,5k fixos por sessão.

**Contra o que:** dessas nove, **sete duplicam** o que `/rodada`, `/revisar`, `/fechar`, os sete
agentes e o `buscar.mjs` já fazem — e fazem com a lente das sete regras, que nenhuma delas tem.
Sobram duas que cobrem vão real: `verification-before-completion` (enuncia a regra 2 corretamente)
e `receiving-code-review`. Duas skills úteis não pagam 29,7k de exposição mais um mandato de
invocar por 1% de chance. É o mesmo critério de 16/09, aplicado ao número certo.

**E o veto abaixo continua valendo**, porque desligar é reversível e a auditoria não: se alguém
religar o plugin aqui, as cinco skills desta seção seguem proibidas. Funciona porque
`using-superpowers` cede por construção: *"User instructions (CLAUDE.md, AGENTS.md, GEMINI.md,
etc, direct requests) take precedence over skills"*. O Claude Code **não desliga skill
individual** — `claude plugin disable` só opera no plugin inteiro —, então o veto por skill só
pode ser texto.

## As cinco vetadas — nunca invocar neste repositório

| Skill | O trecho literal | Regra que ele contradiz |
|---|---|---|
| `writing-plans` | `Expected: FAIL with "function not defined"`; `return expected`; `git commit -m "feat: add specific feature"` | 7 (falha por símbolo ausente não é invariante medido), 3 (teste que passa por construção afirma mecanismo), 5 e 6 (mensagem sem defeito, causa nem medição) |
| `subagent-driven-development` | `the implementer's report carries the test evidence`; `Five rounds maximum per task`; achados `minor (deferred)` num workspace que a skill manda apagar com `rm -rf` | 7 (relatório de quem escreveu o código vira prova de execução), 1 (achado descartado vira branch limpo), 6 (lote revisado como unidade única), e a política das três correções |
| `using-git-worktrees` | manda `git commit` do `.gitignore` no meio de outra fatia; baseline `npm install` + `npm test` | 6, e 7: **não existe `npm test` neste repositório** — não há `package.json` na raiz, e o `portal/package.json` só tem `dev`, `build`, `start`, `lint`. O baseline sairia verde a partir de um comando que não roda nada |
| `finishing-a-development-branch` | `git merge`, `git branch -d`, `git branch -D`, e cria PR pelo `gh` CLI | o contrato daqui é branch designada + PR draft, e **o contêiner não tem `gh`**, só ferramentas MCP do GitHub. Mesmo `npm test` falso do item acima |
| `executing-plans` | — | sem conflito próprio; sai por ser genérica e por executar à risca o gabarito vazio do `writing-plans`. A própria skill se declara inferior: *"If subagents are available, use superpowers:subagent-driven-development instead"* |

## As nove restantes — o que valeria, SE o plugin fosse religado

Elas não estão em uso: o plugin está desligado. Esta seção existe para que uma reauditoria futura
não precise refazer a leitura. `verification-before-completion` é a melhor do lote e, se algum dia
for religada, deve ser tratada como **leitura autoritativa**. `systematic-debugging`, `test-driven-development`, `brainstorming`,
`writing-skills`, `receiving-code-review`, `requesting-code-review`,
`dispatching-parallel-agents` e `using-superpowers` ficam com as emendas abaixo.

1. **`requesting-code-review` manda `Dispatch a general-purpose subagent`.** Aqui o revisor é
   `revisor-defeito-silencioso` / `/revisar`. Um `general-purpose` com template genérico aprova
   zero fabricado e estágio desligado sem piscar — e `verificar-comandos.mjs` não pegaria essa
   divergência, porque ele só cobre `subagent_type` citado por comando.
2. **`dispatching-parallel-agents` confere colisão DEPOIS** (*"Did agents edit same code?"*).
   O gate da casa é antes: sem dependência **e** arquivos totalmente disjuntos. E o Postgres
   local é estado compartilhado que nenhum recorte "por domínio" separa. O prompt de exemplo dela
   autoriza *"Adjusting test expectations if testing changed behavior"* — proibido, contra 2, 3 e 7.
3. **`writing-skills` proíbe `No narrative storytelling`** e põe teto de `<500 words`. Isso não
   alcança as fichas, a memória nem as mensagens de commit deste repositório, onde a data e o
   número medido SÃO o conteúdo ("sessões 82 e 86", "custou uma passada na sessão 78"). A parte
   dela que vale é o micro-teste com controle: *"Always include a no-guidance control. If the
   control doesn't exhibit the failure, there is nothing to fix"* — que é a regra 2 aplicada a
   texto.

Menores, do mesmo tipo: `receiving-code-review` fecha mandando responder com
`gh api .../replies`; aqui é a ferramenta MCP de resposta em thread. `brainstorming` manda
*"Explore project context — check files, docs, recent commits"*, que é `buscar.mjs` em um comando
— e ela não sabe disso.

## O desempate, que é o achado principal

**O plugin se contradiz sobre o caso exato da regra 2**, e a próxima sessão que abrir só um dos
dois arquivos vai fazer a coisa errada com convicção:

- `test-driven-development` diz *"**Test passes?** You're testing existing behavior. Fix test."*
  e lista *"Test passes immediately"* entre as red flags que exigem *"Delete code. Start over
  with TDD."*
- `verification-before-completion` diz, para o mesmo sintoma:
  *"Write → Run (pass) → **Revert fix** → Run (MUST FAIL) → Restore → Run (pass)"*

A segunda formulação **é** a regra 2. A primeira é o que fez `/tdd-green` e `/test-generate`
serem removidos em 16/09/2026. Invariante novo sobre correção que já existe em produção **passa
de primeira por construção** — isso é o esperado, não uma red flag. A prova é desligar a
correção, ver reprovar, contar os asserts, religar. "Fix test" contra código já corrigido só
tem duas saídas, e as duas são proibidas: afirmar o mecanismo da correção (regra 3) ou fabricar
um arranjo que o código real nunca produz (regra 4).

**Quando as duas divergirem, vale `verification-before-completion`.** E nenhuma das 14 pede o
número de asserts que reprovaram — essa parte da regra 2 continua sendo só nossa.

Uma tensão menor no mesmo eixo: `systematic-debugging` exige *"Create Failing Test Case … MUST
have before fixing"* sem cláusula de saída, e trata "não reproduzi" como preguiça
(*"95% of 'no root cause' cases are incomplete investigation"*). A saída da regra 4 continua
valendo por cima: se o arranjo real não se reproduz, registre a impossibilidade e afirme só o
que dá para provar.

## O que esta ficha NÃO afirma

A auditoria leu os 14 `SKILL.md`. **Não leu** os arquivos auxiliares que algumas invocam —
`implementer-prompt.md`, `task-reviewer-prompt.md`, `re-review-prompt.md`, `code-reviewer.md`,
`writing-good-tests.md`. Para as cinco vetadas isso não muda nada. Se alguma delas for
reabilitada, os auxiliares precisam ser lidos antes.

Não há portão que prove este veto nem o desligamento: se a v6.4 renomear uma skill vetada, ou se
alguém religar o plugin, nada aqui reprova.
**Versão nova do plugin é caso de reauditoria**, e o commit que a instalar carrega a atualização
desta ficha.
