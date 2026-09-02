# Comandos de barra — de onde vieram e o que foi mexido

52 comandos, importados em 02/09/2026 de dois repositórios do mesmo autor (MIT):

- **[`wshobson/agents`](https://github.com/wshobson/agents)** — a fonte de **50 deles**. Apesar do
  nome, hoje é um **marketplace de plugins**: 92 plugins, cada um com `agents/`, `commands/` e
  `skills/` próprios. É a versão viva.
- **[`wshobson/commands`](https://github.com/wshobson/commands)** — a fonte dos **2 restantes**
  (`data-validation`, `deploy-checklist`), que não têm sucessor no repositório novo.

## Por que a substituição valeu quase 100%

A primeira importação veio do `wshobson/commands` e foi substituída no mesmo dia, depois de
comparar os dois. O repositório novo ganha em três pontos **medidos**, não opinados:

| | `commands` (antigo) | `agents` (novo) |
|---|---|---|
| Modelo | ID fixado e **velho** — `claude-sonnet-4-0` (41) e `claude-opus-4-1` (16) | **apelido** (`sonnet`, `opus`, `haiku`, `inherit`) |
| `description:` no frontmatter | quase nenhum | 64 de 105 |
| Despacho para agente inexistente | 17 de 44 | 22 de 105, e **nenhum** dos que substituímos |

O primeiro é o que mais importa: ID fixado **envelhece em silêncio**. Na importação do repositório
antigo foi preciso remapear os 57 à mão para não rebaixar o modelo — e esse remapeamento
envelheceria de novo na próxima família. Apelido não tem esse problema, e é por isso que os dois
arquivos que sobraram do repositório antigo foram convertidos para `model: sonnet`.

**Sobraram 2, e não 0, porque `data-validation` e `deploy-checklist` não têm equivalente no
repositório novo.** Três outros tinham, e foram trocados pelo sucessor: `db-migrate` →
`sql-migrations`, `security-scan` → `security-sast`, `test-harness` → `test-generate`.

## As duas coisas alteradas na importação

**1. Todo comando ganhou `description:` explícito.** 29 não tinham, e sem ele o Claude Code deriva
a descrição da **primeira linha de conteúdo** — o que já produziu um estrago real aqui: o aviso do
item 2, inserido no topo, virou a descrição de 17 comandos e o menu passou a listar 17 vezes o
mesmo parágrafo em vez do nome de cada um. Com `description:` no frontmatter, o aviso pode ficar
onde for mais legível sem sequestrar nada.

**2. Um aviso em 14 deles, que ainda mandam despachar para agente que não existe aqui.**
`code-reviewer`, `backend-architect`, `debugger`, `test-automator`, `tdd-orchestrator` e companhia
existem no repositório novo — mas **dentro dos plugins**, e os plugins não foram instalados.

### Por que os agentes NÃO vieram junto, e é decisão revisável

Este projeto tem sete agentes próprios (`.claude/agents/`), em português, com regras que o
`CLAUDE.md` define — inclusive a de que **quem escreveu a mudança não a revisa**
(`revisor-defeito-silencioso`) e a de que **nível de modelo é escolhido por despacho, nunca
herdado por acidente**. Instalar um `code-reviewer` genérico ao lado do `revisor-defeito-silencioso`
não acrescenta cobertura: cria dois candidatos para a mesma pergunta, e o despacho passa a depender
de qual descrição casa melhor com a frase do dia. É troca ruim.

O que os agentes genéricos cobririam de verdade são lacunas (`database-optimizer`,
`performance-engineer`, `security-auditor`). **Se um dia isso fizer falta, instale o agente
específico** de `plugins/<nome>/agents/`, um a um e com o motivo escrito — não o pacote.

## O que ficou de fora, e por quê

Dos 105 comandos do repositório novo, 53 não vieram:

| Fora | Por quê |
|---|---|
| `financial-projections`, `business-case`, `market-opportunity` | **o mais perigoso da lista.** São de *startup*: projeção 3–5 anos, headcount, captação. Aqui o assunto é FP&A de reestruturação, com regras próprias (`modelo-institucional.ts`, premissas do realizado, os três cenários). O resultado sairia com cara de certo e não seria — exatamente a família de defeito que este projeto existe para não ter |
| `team-*` (9), `multi-agent-*`, `improve-agent` | colidem com as regras de despacho do `CLAUDE.md` |
| `ship`, `status`, `gen`, `find`, `certify`, `audit-chain`, `verify-receipt`, `promote-checkpoint`, `new-track`, `list-pending`, `approve-review`, `manage`, `setup`, `revert`, `implement`, `compare` | acoplados a um fluxo de trabalho próprio daquele plugin, que não é o daqui |
| `ml-pipeline`, `finetune`, `langchain-agent` | não se treina modelo nem se usa LangChain |
| `multi-platform`, `rust-project`, `arm-cortex-*` | um app web só, TypeScript e Python |
| `create-component`, `component-scaffold`, `design-system-setup` | o portal não está montando design system |
| `ai-assistant`, `ai-review` | o `/code-review` embutido e o revisor do projeto já cobrem |

Trazer qualquer um de volta é copiar de `plugins/*/commands/` e conferir os dois itens acima.

## O que eles NÃO substituem

O `CLAUDE.md` continua sendo a autoridade sobre como se trabalha aqui — as sete regras, os comandos
canônicos, o despacho por agente. **Comando importado que o contradiga perde.** Em particular:
nenhum deles conhece a regra de **medir invariante não-vazio** nem a de **nunca apresentar ausência
como dado**, e vários mandam rodar teste de um jeito que não é o daqui.
