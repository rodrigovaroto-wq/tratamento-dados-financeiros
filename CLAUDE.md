# Tratamento de Dados Financeiros — Oria Partners

> Memória de projeto do Claude Code. **Este arquivo é carregado em toda sessão, então ele é
> curto de propósito e não guarda número nenhum que envelhece.** Onde um número importa, ele
> aponta para quem o mede.

Pipeline que recebe documentos financeiros de mandatos de M&A/reestruturação, extrai as
demonstrações com IA, grava em Postgres/Supabase com proveniência, e exporta um book em Excel
com modelo de FP&A vivo em fórmula.

## Onde está o estado (leia nesta ordem, pare quando tiver o que precisa)

| Arquivo | Pergunta que responde |
|---|---|
| `ESTADO.md` (topo) | **Onde estamos agora** — última migration, suítes, a rodada mais recente |
| `Arquitetura do Sistema/3 Estado e Execução/MAPA_DE_EXECUCAO.md` | **O que falta até fechar**, em ordem, com critério de pronto |
| `Arquitetura do Sistema/3 Estado e Execução/PRONTIDAO_POR_ESTAGIO.md` | O projeto medido contra o próprio objetivo, estágio por estágio |
| `.claude/memory/MEMORY.md` | As lições que já custaram caro — **leia sempre, é curto** |
| `HANDOFF.md` | **Como chegou aqui** — arquivo morto, ~5.000 linhas. Não leia inteiro |

**Nenhum arquivo deste repositório é autoridade sobre o banco.** Quem responde é a sonda,
contra o banco em que você está conectado:

```sql
select chave, migration, tipo, objeto, presente, detalhe, porque
  from fn_instalacao_conferir() where not presente order by 1;
```

## As sete regras (cada uma nasceu de um defeito que chegou em produção)

1. **Nunca apresentar ausência como dado.** Zero fabricado numa premissa é indistinguível de
   uma medição de zero. Célula em branco + nota com o motivo **e o efeito** ("o bloco de dívida
   cobra juro zero"), sempre.
2. **Todo invariante novo precisa ser MEDIDO não-vazio.** Desligue a correção, rode a suíte,
   confirme que reprova, religue. O número de asserts que reprovaram vai na mensagem do commit.
3. **Invariante afirma COMPORTAMENTO, não mecanismo.** Um teste que descreve *como* o código faz
   protege o bug.
4. **Nunca inventar fixture para provar bug de produção.** Se não dá para reproduzir o arranjo
   real, diga isso no comentário e afirme só o que dá para provar.
5. **Comentário explica POR QUÊ, com o número medido junto.** "Corrige bug" não serve.
6. **Uma fatia por commit**, com mensagem que conta o defeito, a causa e a medição.
7. **Estágio que não rodou tem a mesma aparência de estágio que rodou e não achou nada.**
   Cobertura verde não é prova de execução — ver `.claude/memory/estagio-desligado-parece-limpo.md`.

## Comandos canônicos

Use exatamente estes. O CI (`.github/workflows/suites.yml`) é a lista completa e a fonte.

```bash
# preparar o container (a sessão 14 perdeu tempo nos três)
cd portal && npm ci --ignore-scripts && cd ..   # --ignore-scripts: igual ao CI
cd "Dados de Teste"/book-vertentes && python3 -m pip install --quiet 'reportlab==5.0.1' \
  && PYTHONPATH=. python3 gerar.py && cd ../..   # PYTHONPATH=. é obrigatório
sudo -u postgres /usr/lib/postgresql/16/bin/pg_ctl -D /var/lib/postgresql/16/main \
  -o "-c config_file=/etc/postgresql/16/main/postgresql.conf -k /tmp -p 5432" -l /tmp/pg.log start
# O `run.sh` roda COMO postgres e REESCREVE `Supabase/schema.sql`. Num container em que
# o repositório é do root, ele morre em "Permission denied" DEPOIS de aplicar as 101
# migrations — e nenhum `*.test.sql` chega a rodar. Custou uma passada na sessão 78.
chmod a+w Supabase Supabase/schema.sql

# suítes
node --test 'N8N/test/*.test.mjs'
./portal/node_modules/.bin/tsx portal/scripts/verificar-export.mts
./portal/node_modules/.bin/tsx portal/scripts/verificar-transcricao.mts
./portal/node_modules/.bin/tsx portal/scripts/verificar-mensagem-de-falha.mts
./portal/node_modules/.bin/tsx portal/scripts/verificar-premissas-do-realizado.mts
sudo -u postgres env PGHOST=/tmp PGPORT=5432 PGUSER=postgres Supabase/test/run.sh
CONFERIR_PSQL="sudo -u postgres psql -h /tmp -p 5432" CONFERIR_DB=tdf_test \
  node Supabase/test/conferir-chamadas.mjs
E2E_PSQL="sudo -u postgres psql -h /tmp -p 5432" ./portal/node_modules/.bin/tsx Verificação/run.mts
./portal/node_modules/.bin/tsx Verificação/variacoes.mts

# geradores — o gerado TEM de ficar igual ao commitado (`git diff --exit-code`)
node N8N/build-workflow.mjs && node N8N/build-workflow-macro.mjs \
  && node N8N/build-workflow-diagnostico.mjs && node N8N/build-workflow-erros.mjs

# portal
cd portal && ./node_modules/.bin/tsc --noEmit && ./node_modules/.bin/eslint . \
  && ./node_modules/.bin/next build
```

`npx` **não** serve no lugar de `./portal/node_modules/.bin/<bin>` — para o `tsx`, o `tsc`, o
`eslint` ou o `next`: sem o binário do lock, o npx baixa a última versão publicada no dia. Esta
regra existia aqui desde sempre e o CI a desobedecia em três linhas até 01/09 (era o que o Sonar
cobrava em `githubactions:S6505`/`S8543`). Agora os dois concordam — e é por isso que os comandos
acima têm de continuar concordando: **este bloco é espelho do CI, e espelho que fica para trás é
pior que espelho nenhum**, porque manda a próxima sessão instalar diferente do portão.

## Orquestrar, não implementar sozinho

A sessão principal entende, decide e delega. Trabalho implementável vai para o especialista
cuja linha casa com a tarefa — os arquivos estão em `.claude/agents/`.

| Agente | Quando usar | Nível |
|---|---|---|
| `migrations-postgres` | Migration, função SQL, sonda, `Supabase/test/*.sql` | médio |
| `n8n-workflow` | Geradores, `N8N/lib/*`, nós Code, republicação | médio |
| `portal-export` | `portal/src/**`, `export.ts`, endereços de célula | médio |
| `suites-invariantes` | Escrever um invariante novo e **medi-lo não-vazio** | médio |
| `revisor-defeito-silencioso` | Revisar um diff sob a lente central do projeto | forte |
| `estado-e-handoff` | Atualizar `ESTADO.md`, `MAPA`, memória, PR | barato |
| `explorador` | Mapear onde uma coisa mora, antes de planejar | barato |

Existem também **30 agentes `importado.*`** em `.claude/agents/`, e eles NÃO são desta lista: só
existem para que os 13 comandos de barra que os citam não morram em `Agent type not found`
(`.claude/COMANDOS.md`). **Trabalho do projeto vai para os sete acima**, sempre — nenhum
importado conhece as sete regras. O portão que mantém isso honesto é `node .claude/verificar-comandos.mjs`.

**Nível de modelo é escolhido por despacho, nunca herdado por acidente.** Despacho paralelo
(ondas) só quando **as duas** condições valem: sem dependência entre as tarefas **e** conjuntos
de arquivos totalmente disjuntos. Quem comita é sempre a sessão principal, uma tarefa por vez,
capturando o `HEAD` na hora. Ver `Arquitetura do Sistema/5 Prompts/03-onda-paralela.md`.

## Antes de codar

Pedido aberto (mais de uma leitura razoável) → `Arquitetura do Sistema/5 Prompts/` primeiro, código depois.
Bug → causa raiz antes de qualquer correção; três correções falhas seguidas param a linha e
questionam a arquitetura, não tentam a quarta.

## Memória

`.claude/memory/INSTRUCTIONS.md` diz o que vira memória e o que não vira. Regra em uma linha:
**uma sessão futura ficaria surpresa e grata de saber disso antes de começar?** Se dá para
derivar lendo o código, não é memória.
