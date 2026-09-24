---
name: ponytail-auditado-nao-instalar
description: o plugin ponytail 4.10.0 ("lazy senior dev") foi auditado e NÃO foi instalado — é always-on em três hooks, contradiz as regras 2, 5 e 6 e o "pedido aberto → 5 Prompts"; duas técnicas dele entraram no /rodada como texto
tipo: doutrina
toca:
  - .claude/commands/rodada.md
---

# Ponytail 4.10.0: auditado, NÃO instalado — duas técnicas entraram no `/rodada`

`DietrichGebert/ponytail` (v4.10.0, commit `e3ba2aa`) foi lido inteiro em 24/09/2026: as 6 skills
(`ponytail`, `-review`, `-audit`, `-debt`, `-gain`, `-help`), os hooks do Claude Code e as
regras. **Não foi instalado como plugin**, pelo mesmo critério que desligou o superpowers
(`superpowers-cinco-skills-vetadas.md`): exposição fixa alta mais texto que contradiz as regras.

## Por que não o plugin

**É always-on em três pontos, e o terceiro alcança os especialistas.** `SessionStart` injeta
**5.631 bytes** em toda sessão; `SubagentStart` injeta **5.448 bytes** em TODO subagente — os
sete daqui inclusive, por cima do prompt que cada um tem; `UserPromptSubmit` roda um rastreador de
modo em toda mensagem. Medido rodando os hooks do próprio repositório com `node`.

E o texto injetado contradiz as regras em trechos literais:

| Trecho do `skills/ponytail/SKILL.md` | O que contradiz aqui |
|---|---|
| *"Code first. Then at most three short lines… No essays, no feature tours, no design notes"*; *"every paragraph defending a simplification is complexity smuggled back in as prose"* | regras 5 e 6 — o comentário e a mensagem de commit carregam o defeito, a causa e o número medido; fichas e memória são prosa de propósito |
| *"ONE runnable check… No frameworks, no fixtures, no per-function suites unless asked. Trivial one-liners need no test"* | regra 2 — não pede que o check reprove com a correção desligada nem o número de asserts; e as suítes daqui SÃO por função |
| *"Complex request? Ship the lazy version and question it in the same response… Never stall on an answer you can default"* | "pedido aberto (mais de uma leitura razoável) → `5 Prompts/` primeiro, código depois" |
| convenção `# ponytail: <teto>, <quando subir>` + `/ponytail-debt` que colhe os marcadores | as fichas com `ancora`/`ancora_sha` já fazem isso e ainda descobrem sozinhas quando envelheceram |

`/ponytail-review` e `/ponytail-audit` caçam só excesso de código e declaram correção fora de
escopo; o painel do `/revisar` foi cortado de cinco para três lentes em 16/09 justamente para não
multiplicar revisores. `/ponytail-gain` mostra números de benchmark de outro repositório (e o
próprio README admite que os 80–94% originais eram em parte artefato da linha de base).

## O que foi trazido — como texto no `/rodada`, sem hook nenhum

1. **Passo 2: listar todos os chamadores antes de editar uma função** e corrigir no ponto por onde
   todos passam. É a regra "bug fix = root cause" do ponytail, aterrada no caso daqui que custou
   caro: `custoEstimadoPorTamanho` promovida a decisora (`.claude/memory/conta-parcial-vira-v31-quando-promovida.md`).
2. **Passo 3: confirmar que a função/helper/nó ainda não existe antes de planejá-lo** — o degrau 2
   da escada dele ("already in this codebase? reuse it"), apontado para o `buscar.mjs`. Duas
   implementações da mesma conta divergem sem erro, que é a lente central do projeto.

## O que esta ficha NÃO afirma

Não há portão que prove este veto: se alguém instalar o plugin, nada reprova. Versão nova do
ponytail é caso de reauditoria, e o commit que o instalar carrega a atualização desta ficha.
Não foram lidos os `benchmarks/` nem os adaptadores para outros agentes (Cursor, Codex, Gemini…),
que não se aplicam ao Claude Code.
