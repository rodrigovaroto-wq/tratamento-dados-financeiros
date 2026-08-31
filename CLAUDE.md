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
| `docs/MAPA_DE_EXECUCAO.md` | **O que falta até fechar**, em ordem, com critério de pronto |
| `docs/PRONTIDAO_POR_ESTAGIO.md` | O projeto medido contra o próprio objetivo, estágio por estágio |
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
cd portal && npm ci && cd ..
cd test-data/book-vertentes && python3 -m pip install --quiet 'reportlab==5.0.1' \
  && PYTHONPATH=. python3 gerar.py && cd ../..   # PYTHONPATH=. é obrigatório
sudo -u postgres /usr/lib/postgresql/16/bin/pg_ctl -D /var/lib/postgresql/16/main \
  -o "-c config_file=/etc/postgresql/16/main/postgresql.conf -k /tmp -p 5432" -l /tmp/pg.log start

# suítes
node --test 'n8n/test/*.test.mjs'
./portal/node_modules/.bin/tsx portal/scripts/verificar-export.mts
./portal/node_modules/.bin/tsx portal/scripts/verificar-transcricao.mts
./portal/node_modules/.bin/tsx portal/scripts/verificar-mensagem-de-falha.mts
./portal/node_modules/.bin/tsx portal/scripts/verificar-premissas-do-realizado.mts
sudo -u postgres env PGHOST=/tmp PGPORT=5432 PGUSER=postgres db/test/run.sh
E2E_PSQL="sudo -u postgres psql -h /tmp -p 5432" ./portal/node_modules/.bin/tsx test/e2e/run.mts
./portal/node_modules/.bin/tsx test/e2e/variacoes.mts

# geradores — o gerado TEM de ficar igual ao commitado (`git diff --exit-code`)
node n8n/build-workflow.mjs && node n8n/build-workflow-macro.mjs \
  && node n8n/build-workflow-diagnostico.mjs && node n8n/build-workflow-erros.mjs

# portal
cd portal && npx tsc --noEmit && npx eslint . && npx next build
```

`npx tsx` **não** serve no lugar de `./portal/node_modules/.bin/tsx`: sem o binário do lock, o
npx baixa a última versão publicada no dia.

## Orquestrar, não implementar sozinho

A sessão principal entende, decide e delega. Trabalho implementável vai para o especialista
cuja linha casa com a tarefa — os arquivos estão em `.claude/agents/`.

| Agente | Quando usar | Nível |
|---|---|---|
| `migrations-postgres` | Migration, função SQL, sonda, `db/test/*.sql` | médio |
| `n8n-workflow` | Geradores, `n8n/lib/*`, nós Code, republicação | médio |
| `portal-export` | `portal/src/**`, `export.ts`, endereços de célula | médio |
| `suites-invariantes` | Escrever um invariante novo e **medi-lo não-vazio** | médio |
| `revisor-defeito-silencioso` | Revisar um diff sob a lente central do projeto | forte |
| `estado-e-handoff` | Atualizar `ESTADO.md`, `MAPA`, memória, PR | barato |
| `explorador` | Mapear onde uma coisa mora, antes de planejar | barato |

**Nível de modelo é escolhido por despacho, nunca herdado por acidente.** Despacho paralelo
(ondas) só quando **as duas** condições valem: sem dependência entre as tarefas **e** conjuntos
de arquivos totalmente disjuntos. Quem comita é sempre a sessão principal, uma tarefa por vez,
capturando o `HEAD` na hora. Ver `docs/prompts/03-onda-paralela.md`.

## Antes de codar

Pedido aberto (mais de uma leitura razoável) → `docs/prompts/` primeiro, código depois.
Bug → causa raiz antes de qualquer correção; três correções falhas seguidas param a linha e
questionam a arquitetura, não tentam a quarta.

## Memória

`.claude/memory/INSTRUCTIONS.md` diz o que vira memória e o que não vira. Regra em uma linha:
**uma sessão futura ficaria surpresa e grata de saber disso antes de começar?** Se dá para
derivar lendo o código, não é memória.
