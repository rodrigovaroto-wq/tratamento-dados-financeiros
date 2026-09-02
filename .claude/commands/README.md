# Comandos de barra — o que existe, e de onde veio

52 comandos, importados em 02/09/2026 de repositórios de [`wshobson`](https://github.com/wshobson)
(MIT). **A primeira metade deste arquivo é o catálogo** — o que você provavelmente veio procurar.
A segunda registra a procedência e as decisões, que se leem uma vez.

> **Conferir se este catálogo ainda bate com o diretório** (list de baixo contra os arquivos):
> ```bash
> diff <(grep -oE '^\| `/[a-z0-9-]+`' .claude/commands/README.md | tr -d '|` /' | sort -u) \
>      <(ls .claude/commands/*.md | xargs -n1 basename | grep -v README | sed 's/\.md//' | sort)
> ```
> Saída vazia = em dia. Este arquivo é escrito à mão, então ele **pode** envelhecer — a diferença
> para o resto do repositório é que aqui envelhecer não causa dano silencioso, só uma linha a
> menos no índice.

---

## Catálogo

### Banco e migrations

| Comando | Para quê |
|---|---|
| `/sql-migrations` | Migration SQL com estratégia de zero-downtime (Postgres) |
| `/migration-observability` | Monitorar migração: CDC, métricas, o que olhar durante |
| `/data-validation` | Montar validação de dados num pipeline |
| `/data-pipeline` | Desenhar arquitetura de pipeline de dados |

### Testes e invariantes

| Comando | Para quê |
|---|---|
| `/tdd-red` | Escrever o teste que reprova primeiro |
| `/tdd-green` | Código mínimo para o teste passar |
| `/tdd-refactor` | Refatorar com a rede já verde ⚠️ |
| `/tdd-cycle` | O ciclo inteiro red-green-refactor ⚠️ |
| `/test-generate` | Gerar testes unitários para código existente |
| `/eval` | Avaliar qualidade de um plugin ou skill |

### Depuração

| Comando | Para quê |
|---|---|
| `/smart-debug` | Depurar com análise de causa raiz ⚠️ |
| `/smart-fix` | Diagnosticar e corrigir, com verificação da correção ⚠️ |
| `/debug-trace` | Instrumentar: breakpoints, tracing, logs ⚠️ |
| `/error-analysis` | Analisar um erro e propor resolução ⚠️ |
| `/error-trace` | Montar rastreamento e monitoramento de erro |
| `/incident-response` | Conduzir incidente com práticas de SRE ⚠️ |

### Segurança

| Comando | Para quê |
|---|---|
| `/security-sast` | Análise estática de vulnerabilidade no código |
| `/security-dependencies` | Vulnerabilidade nas dependências |
| `/security-hardening` | Endurecer o sistema em camadas ⚠️ |
| `/xss-scan` | Caçar XSS no front |
| `/deps-audit` | Auditar dependências (segurança + saúde) |
| `/deps-upgrade` | Subir dependência em passos seguros |
| `/compliance-check` | Conferir contra exigência regulatória (LGPD) |

### Código

| Comando | Para quê |
|---|---|
| `/refactor-clean` | Refatorar sem sobre-engenharia |
| `/tech-debt` | Inventariar dívida técnica e priorizar |
| `/code-explain` | Explicar um trecho de código |
| `/code-migrate` | Plano de migração entre framework/versão/plataforma |
| `/legacy-modernize` | Modernizar por strangler fig, em pedaços ⚠️ |
| `/full-review` | Revisão em várias dimensões ⚠️ |
| `/performance-optimization` | Otimizar performance, do profiling ao monitoramento ⚠️ |

### Portal e front

| Comando | Para quê |
|---|---|
| `/design-review` | Revisar UI existente |
| `/accessibility-audit` | Auditoria de acessibilidade |
| `/typescript-scaffold` | Esqueleto de projeto TypeScript |
| `/python-scaffold` | Esqueleto de projeto Python |

### Operação

| Comando | Para quê |
|---|---|
| `/monitor-setup` | Montar observabilidade |
| `/slo-implement` | Definir e implementar SLO |
| `/deploy-checklist` | Checklist antes de subir |
| `/config-validate` | Validar configuração |
| `/cost-optimize` | Reduzir custo de nuvem |

### Git, PR e processo

| Comando | Para quê |
|---|---|
| `/git-workflow` | Do review ao PR, com portões ⚠️ |
| `/pr-enhance` | Melhorar descrição e qualidade do PR |
| `/issue` | Resolver uma issue do GitHub |
| `/standup-notes` | Gerar notas de daily |
| `/onboard` | Onboarding de quem chega |

### Documentação e contexto

| Comando | Para quê |
|---|---|
| `/doc-generate` | Gerar documentação a partir do código |
| `/c4-architecture` | Documentar arquitetura no modelo C4 |
| `/context-save` | Salvar o contexto da sessão |
| `/context-restore` | Retomar contexto salvo |

### IA e produto

| Comando | Para quê |
|---|---|
| `/prompt-optimize` | Otimizar prompt de produção (CoT, few-shot) |
| `/feature-development` | Conduzir feature de ponta a ponta ⚠️ |
| `/data-driven-feature` | Feature guiada por métrica e A/B ⚠️ |
| `/workflow-automate` | Automatizar um fluxo repetitivo |

### As duas marcas do catálogo

**⚠️ — os 14 que orquestram.** Eles mandam despachar para agentes que **não existem aqui**
(`code-reviewer`, `backend-architect`, `debugger`…) e por isso abrem com um aviso. Use os sete
agentes deste projeto (`.claude/agents/`, listados no `CLAUDE.md`). Despacho para `subagent_type`
inexistente falha.

**Dois merecem cautela extra, e não é sobre agente ausente:** `/full-review` e `/refactor-clean`
funcionam, mas não conhecem a lente central deste projeto. A revisão daqui é a do
`revisor-defeito-silencioso` — o defeito que **não produz erro** —, e o `CLAUDE.md` manda que quem
escreveu a mudança não a revise. Use-os como segunda opinião, nunca no lugar dela.

---

## De onde vieram

- **[`wshobson/agents`](https://github.com/wshobson/agents)** — a fonte de **50 deles**. Apesar do
  nome, hoje é um **marketplace de plugins**: 92 plugins, cada um com `agents/`, `commands/` e
  `skills/` próprios. É a versão viva.
- **[`wshobson/commands`](https://github.com/wshobson/commands)** — a fonte dos **2 restantes**
  (`data-validation`, `deploy-checklist`), que não têm sucessor no repositório novo.

### Por que a substituição valeu quase 100%

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

Três tinham sucessor e foram trocados: `db-migrate` → `sql-migrations`, `security-scan` →
`security-sast`, `test-harness` → `test-generate`.

### As duas coisas alteradas na importação

**1. Todo comando ganhou `description:` explícito.** 29 não tinham, e sem ele o Claude Code deriva
a descrição da **primeira linha de conteúdo** — o que já produziu um estrago real aqui: o aviso do
item 2, inserido no topo, virou a descrição de 17 comandos, e o menu passou a listar 17 vezes o
mesmo parágrafo em vez do nome de cada um. Com `description:` no frontmatter, o aviso pode ficar
onde for mais legível sem sequestrar nada.

**2. O aviso nos 14 marcados com ⚠️ no catálogo.**

### Por que os agentes NÃO vieram junto, e é decisão revisável

Este projeto tem sete agentes próprios, em português, com regras que o `CLAUDE.md` define —
inclusive a de que **quem escreveu a mudança não a revisa** e a de que **nível de modelo é
escolhido por despacho, nunca herdado por acidente**. Instalar um `code-reviewer` genérico ao lado
do `revisor-defeito-silencioso` não acrescenta cobertura: cria dois candidatos para a mesma
pergunta, e o despacho passa a depender de qual descrição casa melhor com a frase do dia.

O que os agentes genéricos cobririam de verdade são lacunas (`database-optimizer`,
`performance-engineer`, `security-auditor`). **Se um dia isso fizer falta, instale o agente
específico** de `plugins/<nome>/agents/`, um a um e com o motivo escrito — não o pacote.

### O que ficou de fora, e por quê

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

### O que eles NÃO substituem

O `CLAUDE.md` continua sendo a autoridade sobre como se trabalha aqui — as sete regras, os comandos
canônicos, o despacho por agente. **Comando importado que o contradiga perde.** Em particular:
nenhum deles conhece a regra de **medir invariante não-vazio** nem a de **nunca apresentar ausência
como dado**, e vários mandam rodar teste de um jeito que não é o daqui.
