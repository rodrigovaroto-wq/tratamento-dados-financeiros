# Prompts — o roteiro, não o estado

Cada arquivo aqui é um prompt colável. **Nenhum deles guarda número, PR ou nome de branch.**

Essa regra tem causa: o `docs/PROMPT_CONTINUACAO.md` original virou uma fotografia da sessão 19 —
mandava trabalhar na branch `claude/handoff-next-steps-6k88f2`, no PR #69, contra 160 testes e 32
migrations. Nada disso era verdade 50 sessões depois, e o prompt continuava mandando começar
errado. **Um prompt que cita estado envelhece; um prompt que aponta para quem mede o estado, não.**

| Prompt | Quando usar |
|---|---|
| [`00-continuacao.md`](00-continuacao.md) | Abrir uma sessão nova de trabalho autônomo |
| [`01-rodada-real.md`](01-rodada-real.md) | Depois que o dono rodou um book de verdade |
| [`02-revisao-multilente.md`](02-revisao-multilente.md) | Antes de fechar qualquer fatia não trivial |
| [`03-onda-paralela.md`](03-onda-paralela.md) | Transformar um plano em ondas de execução seguras |
| [`04-defeito-sem-erro.md`](04-defeito-sem-erro.md) | Um estágio "está verde" e você não confia |

Quem responde pelo estado, sempre: `ESTADO.md` (onde estamos) · `docs/MAPA_DE_EXECUCAO.md` (o que
falta) · `fn_instalacao_conferir()` (o banco) · `.claude/memory/MEMORY.md` (o que já custou caro).
