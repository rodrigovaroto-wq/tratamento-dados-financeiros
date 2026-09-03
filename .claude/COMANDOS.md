# Comandos de barra — o que existe, e de onde veio

52 comandos, importados em 02/09/2026 de repositórios de [`wshobson`](https://github.com/wshobson)
(MIT). **A primeira metade deste arquivo é o catálogo** — o que você provavelmente veio procurar.
A segunda registra a procedência e as decisões, que se leem uma vez.

> **Por que este arquivo mora em `.claude/` e não em `.claude/commands/`.** Todo `.md` dentro de
> `commands/` vira um comando de barra, e o `README.md` virava um `/README` fantasma no menu — um
> comando que, se alguém invocasse, carregaria este catálogo inteiro como prompt. Não quebrava
> nada; poluía a lista e mentia sobre o que existe.

> **O portão que importa** — todo `subagent_type` citado por um comando existe como agente
> instalado. É o que roda no CI, e é o que impede que um comando quebre no meio da tarefa de
> alguém:
> ```bash
> node .claude/verificar-comandos.mjs
> ```
> **Medido na primeira execução dele: 57 citações não resolviam, 30 nomes distintos, em 13
> comandos.** Hoje: `comandos OK`.
>
> **Conferir se o catálogo abaixo ainda bate com o diretório** (índice à mão, dano só cosmético):
> ```bash
> diff <(grep -oE '^\| `/[a-z0-9-]+`' .claude/COMANDOS.md | tr -d '|` /' | sort -u) \
>      <(ls .claude/commands/*.md | xargs -n1 basename | sed 's/\.md//' | sort)
> ```

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
| `/debug-trace` | Instrumentar: breakpoints, tracing, logs |
| `/error-analysis` | Analisar um erro e propor resolução |
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
| `/c4-architecture` | Documentar arquitetura no modelo C4 ⚠️ |
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

**⚠️ — os 13 que ORQUESTRAM.** Eles não fazem o trabalho: despacham para subagentes. Até 02/09
esses subagentes **não existiam aqui** e o comando morria em `Agent type not found` no meio da
tarefa de alguém — 57 citações quebradas, medidas pelo portão acima. **Os 30 agentes citados foram
instalados** (ver "Os agentes importados", abaixo), então hoje eles rodam. Continue preferindo os
sete agentes do projeto quando a tarefa for do projeto: o importado não conhece nenhuma das sete
regras do `CLAUDE.md`.

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

**2. O aviso nos comandos que orquestram.** O catálogo marcava 14, e estava errado em três: `/debug-trace` e `/error-analysis` não despacham para agente nenhum, e `/c4-architecture` despacha para quatro e não estava marcado. Corrigido em 02/09, quando o portão leu os arquivos em vez de acreditar no índice.

### Os agentes importados — 30, e por que a decisão de 02/09 foi revertida

**Esta seção substitui a que dizia "os agentes NÃO vieram junto".** Aquela decisão estava certa
sobre o risco e errada sobre o custo: ela deixou 13 comandos que **falham em execução**, e um
comando que falha só quando alguém o usa é pior do que comando nenhum. O dono pediu que todos
funcionem. Funcionam.

| Comando | Agentes que ele despacha |
|---|---|
| `/c4-architecture` | `c4-code`, `c4-component`, `c4-container`, `c4-context` |
| `/data-driven-feature` | `data-engineer`, `data-engineering-backend-architect` |
| `/feature-development` | `backend-development-backend-architect`, `-performance-engineer`, `-security-auditor`, `-test-automator` |
| `/full-review` | `comprehensive-review-architect-review`, `-code-reviewer`, `-security-auditor` |
| `/git-workflow` | `git-pr-workflows-code-reviewer` |
| `/incident-response` | `incident-responder`, `incident-response-debugger`, `-devops-troubleshooter` |
| `/legacy-modernize` | `framework-migration-architect-review`, `-legacy-modernizer` |
| `/performance-optimization` | `application-performance-frontend-developer`, `-observability-engineer`, `-performance-engineer` |
| `/security-hardening` | `security-scanning-security-auditor`, `threat-modeling-expert` |
| `/smart-debug` | `debugging-toolkit-debugger` |
| `/smart-fix` | `incident-response-code-reviewer`, `-debugger`, `-error-detective`, `-test-automator` |
| `/tdd-cycle` | `tdd-workflows-code-reviewer` |
| `/tdd-refactor` | `tdd-workflows-tdd-orchestrator` |

Os arquivos são `.claude/agents/importado.*.md` — o prefixo é só do NOME DO ARQUIVO, para que os
sete agentes do projeto continuem visíveis num `ls`. **Quem decide o despacho é o `name:` do
frontmatter**, que é o nome que o comando cita.

#### As quatro coisas alteradas na cópia, e por quê

1. **O nome ficou o do marketplace** (`security-scanning-security-auditor`, e não
   `security-auditor`). Feio de propósito: ele diz de qual plugin veio, e evita a escolha
   silenciosa. Os mesmos "papéis" têm CORPOS DIFERENTES conforme o plugin — o `security-auditor`
   do `backend-development` tem 41 linhas e o do `security-scanning` tem 156. Instalar um só sob o
   nome curto trocaria o agente de dois comandos sem ninguém ver.
2. **`model: inherit` virou `model: sonnet`** em 5 deles. O `CLAUDE.md` diz que nível de modelo é
   escolhido por despacho e **nunca herdado por acidente**, e `inherit` é literalmente o acidente.
   Os outros 25 já vinham com apelido explícito (`opus` 10, `sonnet` 13, `haiku` 1, `fable` 1) —
   apelido, nunca ID fixado, pelo mesmo motivo da tabela acima.
3. **A `description:` perdeu o "Use PROACTIVELY"** e ganhou, na frente, a marca dizendo que o
   agente é importado e que a revisão que vale aqui é a do `revisor-defeito-silencioso`. Sem isso
   eles competiriam com os sete agentes do projeto no despacho automático — que era exatamente o
   risco que a decisão antiga apontou, e que continua real. A marca não elimina o risco; **reduz**.
4. **Os quatro `c4-*` perderam o prefixo `c4-architecture::`** nas cinco citações do
   `/c4-architecture`. Aquela grafia é do marketplace e não resolve fora dele; o `name:` desses
   arquivos sempre foi `c4-code`, `c4-component`, `c4-container`, `c4-context`.

#### O que continua valendo da decisão antiga

O risco que ela nomeou **não sumiu**: um `code-reviewer` genérico ao lado do
`revisor-defeito-silencioso` cria dois candidatos para a mesma pergunta. A regra fica escrita, e
está também no `CLAUDE.md`:

> **Trabalho deste projeto vai para os sete agentes de `.claude/agents/`.** Os `importado.*` só
> entram por despacho explícito de um comando de barra. Nenhum deles conhece as sete regras, nem
> a régua da cobertura, nem a doutrina de nunca apresentar ausência como dado.

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
