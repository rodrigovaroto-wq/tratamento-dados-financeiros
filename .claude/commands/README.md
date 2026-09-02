# Comandos de barra — de onde vieram e o que foi mexido

44 comandos importados de [`wshobson/commands`](https://github.com/wshobson/commands)
(MIT) em 02/09/2026, dos 57 que o repositório tem. São **comandos**, não skills: só
entram em contexto quando você digita `/nome`. Foi escolha deliberada — skill carrega
nome e descrição em TODA sessão, e 44 descrições genéricas competindo com os sete
agentes deste projeto viram disparo errado, não ajuda.

## As três coisas que foram alteradas na importação

**1. Os modelos, porque todos vinham desatualizados.** Os 57 fixavam `claude-sonnet-4-0`
(41) ou `claude-opus-4-1` (16). Instalados como vieram, rebaixariam o modelo em silêncio —
um comando que "às vezes fica mais burro" e ninguém sabe por quê. Remapeados preservando a
intenção do autor sobre custo × capacidade: `sonnet-4-0` → `claude-sonnet-5`, `opus-4-1` →
`claude-opus-5`. **Quando a família de modelos virar de novo, este é o lugar a atualizar:**
`grep -h '^model:' .claude/commands/*.md | sort | uniq -c`.

**2. Um aviso em 17 deles, que mandam chamar agente que não existe aqui.** `code-reviewer`,
`test-automator`, `backend-architect`, `tdd-orchestrator`, `context-manager` e companhia são
do repositório de AGENTES do mesmo autor, que não foi importado. Despacho para
`subagent_type` inexistente falha — então esses 17 abrem com um bloco dizendo isso e
apontando para os agentes reais em `.claude/agents/`.

**3. Treze ficaram de fora**, por não terem o que fazer neste projeto:

| Fora | Por quê |
|---|---|
| `k8s-manifest`, `docker-optimize` | não há Kubernetes nem Docker aqui — Vercel + Supabase + n8n |
| `langchain-agent`, `ml-pipeline` | não se usa LangChain, e não se treina modelo |
| `multi-platform`, `full-stack-feature` | um app web só |
| `api-scaffold`, `api-mock` | o portal tem duas rotas de API e elas já existem |
| `multi-agent-optimize`, `multi-agent-review`, `improve-agent` | colidem com as regras de despacho do `CLAUDE.md` e com o `revisor-defeito-silencioso` |
| `ai-assistant`, `ai-review` | genéricos demais; o `/code-review` embutido e o revisor do projeto já cobrem |

Trazer qualquer um de volta é copiar de `wshobson/commands` e refazer os passos 1 e 2.

## O que eles NÃO substituem

O `CLAUDE.md` continua sendo a autoridade sobre como se trabalha aqui — as sete regras, os
comandos canônicos, o despacho por agente. **Comando importado que contradiga o `CLAUDE.md`
perde.** Em particular: nenhum deles conhece a regra de medir invariante não-vazio, nem a de
nunca apresentar ausência como dado, e vários mandam rodar teste de um jeito que não é o
daqui.
