---
id: f1-entidade-perimetro-participacao-0179-0181
tipo: feature
toca:
  - Supabase/migrations/0179_o_papel_no_grupo_que_nunca_foi_escrito.sql
  - Supabase/migrations/0180_o_perimetro_que_o_combinado_nao_tinha.sql
  - Supabase/migrations/0181_o_controle_que_a_entidade_nunca_registrava.sql
  - Supabase/test/entidade_papel_no_grupo.test.sql
  - Supabase/test/perimetro.test.sql
  - Supabase/test/entidade_participacao.test.sql
  - Arquitetura do Sistema/3 Estado e Execução/ARQUITETURA_ALVO_E_ROADMAP.md
ancora:
  - Arquitetura do Sistema/3 Estado e Execução/ARQUITETURA_ALVO_E_ROADMAP.md#12.2
ancora_sha: c5b5d69d0988
substitui: []
---

# F1: Entidade, Perímetro e Participação Societária — Fatias 1.3, 1.4, 1.5 (migrations 0179–0181)

**Entregue em:** 18/09/2026

**O que é:** Terceira frente de construção da F1 (Entidade e Perímetro) — três fatias complementares que estabelecem identidade forte de entidade, explicitam o perímetro de consolidação e preparam a FK de participação societária que a F4 (Conta Canônica) vai consumir.

## Fatia 1.3: `papel_no_grupo` tipado e preenchido (migration 0179)

**Problema que resolve:** A coluna `entidade.papel_no_grupo` existia desde a `0001` como `text` livre, mas estava **NULL em todas as entidades** de produção. Sem um caminho de escrita tipado, o campo nunca seria preenchido — é a regra 7 (estágio desligado parece estágio que rodou e não achou nada).

**Solução:**
- Enum com cinco valores: `holding`, `operacional`, `veiculo`, `coligada`, `fora_do_perimetro`
- Função de escrita `fn_entidade_definir_papel_no_grupo` — nunca automático, sempre humano
- Guarda de pendência `papel_no_grupo_indefinido` quando a função é chamada sem argumento (declare o motivo, não silencio)

**Medição (regra 2):** **21 asserts novos** em `Supabase/test/entidade_papel_no_grupo.test.sql`. Com a chamada nova comentada dentro de `fn_upsert_entidade` (estado equivalente ao vigente antes da 0179) — **11 dos 21 reprovaram**, medido de fato. Religada, os 21 passam.

## Fatia 1.4: Tabela nova `perimetro(caso, entidade, escopo, desde, ate)` (migration 0180)

**Problema que resolve:** Perímetro (quem entra no COMBINADO) não existia no schema. O que hoje é deduzido do dial era implícito no papel de entidade.

**Solução:**
- Tabela nova, PK `id`; `caso_id`/`entidade_id` são FKs, não uma chave composta
- Coluna `escopo` é **texto livre** (não há vocabulário fechado medido ainda — mesmo raciocínio de `periodo.tipo`; NÃO é um enum, e não há valores fixos como "linha_por_linha/ativo_passivo/resultado" — isso não existe no schema)
- Índice único parcial `perimetro_atual_unico (caso_id, entidade_id, escopo) WHERE ate IS NULL` — no máximo um intervalo "vigente" por vez, para a mesma combinação
- Datas `desde` e `ate` porque perímetro **muda durante o mandato** — trocar de escopo FECHA o intervalo anterior (não sobrescreve), porque um perímetro sem data mente sobre o exercício anterior
- Função de leitura `fn_perimetro_vigente(p_caso_id, p_escopo, p_data default current_date)` — quem está no escopo numa data
- Função de escrita `fn_perimetro_definir_escopo`

**Medição (regra 2):** **17 asserts novos** em `Supabase/test/perimetro.test.sql`. Com o fechamento do intervalo anterior desligado dentro de `fn_perimetro_definir_escopo` — **4 dos 17 reprovaram**, medido de fato (os 4 do bloco que depende do fechamento; os outros 13 passam com ou sem a correção, por razões diferentes — ver o cabeçalho do arquivo de teste). Religado, os 17 passam.

**Nota sobre colisão:** Duas sessões paralelas na mesma branch causaram uma colisão no push (commit `5c6916a` é merge, não rebase). Resolvida por `git merge origin/...` após verificar compatibilidade — ver `.claude/memory/colisao-sessoes-paralelas-mesma-branch.md`.

## Fatia 1.5: Participação societária (migration 0181)

**Problema que resolve:** Consolidação e eliminação intragrupo não têm como saber "A controla B" no nível de participação acionária. O que hoje é inferido de papel de grupo fica explícito como FK.

**Solução:**
- Coluna nova `entidade.controladora_id` — FK self-referencing para outra entidade (no máximo UMA controladora direta por entidade — não grafo completo)
- Coluna `entidade.percentual_participacao` — `numeric(6,3)`, validado em `(0, 100]` (intervalo aberto em zero: controladora com 0% não é controladora)
- Guarda `fn_entidade_criaria_ciclo_participacao` — limite de 50 saltos — chamada **antes de gravar** por `fn_entidade_definir_participacao`
- Função de leitura `fn_entidade_cadeia_controladora` — sobe a cadeia, para no topo

**Diferença de F4:** Esta FK **não entrega nada** em F1 — é só preparação. Consolidação e intercompany (que vão consumir ela) são trabalho de **F4**, conforme o roadmap ("é a fatia que destrava consolidação e intercompany", seção 12.2, fatia 1.5) — não F6.

**Medição (regra 2):** 29 asserts novos em `entidade_participacao.test.sql`. **4 dos 29 foram medidos como não-vazios**: desligar a guarda de ciclo em `fn_entidade_definir_participacao` e os 4 asserts reprovam (tentativas de criar ciclo). Os outros 25 passam com ou sem a guarda. Medição registrada no cabeçalho do arquivo de teste.

## Verificação independente (regra 2 aplicada)

Cada fatia foi verificada antes de commit pela sessão principal:

1. Reconstruir o banco do zero (`Supabase/test/run.sh`) — de 124 (antes da 0179) a 126 (depois da 0181) migrations, uma reconstrução por fatia
2. Desligar a correção (remover a guarda, trocar a tipagem, etc.) — confirmar que a suíte reprova **no ponto esperado**
3. Religar a correção — confirmar `TODOS OS TESTES PASSARAM`
4. Conferir que nenhuma outra suíte regrediu

Nenhuma das três fatias (0179/0180/0181) foi aplicada em produção ainda — escrita ≠ aplicada é doutrina deste projeto. Quem aplica é uma sessão seguinte, contra a sonda.

## Aplicação em produção (18/09/2026)

As **quatro migrations 0178–0181 foram aplicadas em produção** pela API de gerenciamento do Supabase (a porta do Postgres não é alcançável do container), conferidas objeto a objeto após cada uma. **Resultado final: 107 requisitos no catálogo, 0 ausentes**, `instalacao_cobertura.ate_migration = '0181'`. Efeito MEDIDO de cada uma, em produção — não estimado:

- `0178` (guarda de entidade fantasma): marcou **7 entidades** no banco inteiro (70 casos) — previsto 7 antes de aplicar, medindo o léxico direto no banco; conferido 7 depois. O critério frouxo, sem o léxico, alcançaria 145.
- `0179` (papel_no_grupo tipado): o backfill abriu **365 pendências** `papel_no_grupo_indefinido` — uma por entidade de TODO o banco (70 casos), não só as ~13 do mandato real. **347 foram resolvidas em lote** por decisão da sessão que aplicou, como ruído de caso de teste (`resolvida_por = 'sessao-claude:ruido-de-caso-de-teste'`, evento de auditoria `pendencias_papel_resolvidas_em_lote` com o critério registrado); **18 seguem abertas** — o mandato real `AMO teste 00` e os casos `AMOBELEZA*`. O backfill não distingue mandato real de caso de teste morto; isso é uma lição para a próxima migration com backfill, não um defeito desta.
- `0180` (perimetro novo): tabela criada, **0 linhas** — correto: ninguém declarou perímetro ainda, é decisão humana via `fn_perimetro_definir_escopo`.
- `0181` (participação com FK): estrutura pronta, `controladora_id` **NULL nas 365 entidades** — no mandato real isso está CERTO, não incompleto: o grupo não tem holding (ver seção abaixo).

**A armadilha do transporte, não do arquivo**: a API de gerenciamento envolve o lote numa transação implícita, e o Postgres recusa usar um rótulo de enum recém-criado dentro da MESMA transação em que nasceu — não é DROP/CREATE, é a regra de visibilidade de `ALTER TYPE ... ADD VALUE` dentro de transação. A `0179` acrescenta `papel_no_grupo_indefinido` e o usa no mesmo arquivo (por isso foi escrita sem `begin;`/`commit;`), mas isso não basta quando o transporte envolve tudo numa transação própria. Aplicada em DOIS passos: o `alter type` sozinho, depois o resto do arquivo com só aquela linha comentada numa cópia de scratchpad (nunca o arquivo versionado). Detalhe completo em `.claude/memory/aplicar-migration-em-producao-pela-api.md`.

## Estado de `F1.6` (próxima fatia)

**NÃO VERIFICÁVEL, por motivo estrutural — não "bloqueada esperando documento".** A investigação nos contratos sociais reais (4 de 8 entidades legíveis) mediu que o grupo é de empresas IRMÃS sob controle comum de pessoas físicas, sem holding nenhuma. "Demonstração combinada" é a forma contábil desse arranjo, não exigida em formato padrão — o cliente provavelmente nunca preparou uma, e não é isso que falta pedir. O aceite financeiro da F1 fica NÃO VERIFICADO com o motivo declarado (regra 1), e isso NÃO bloqueia o resto do roadmap. Ver `.claude/memory/grupo-por-controle-comum-sem-holding.md` e a fatia 1.7 (nascida dessa medição, documentada e não construída).

## Commits (em ordem)

- `14e80da` — F1.3
- `ceb2acc` — handoff de sessão paralela (F1.3 confirmada)
- `5c6916a` — merge das duas linhas paralelas
- `57a1814` — F1.4
- `a3381d8` — F1.5
- `eb549d0` — handoff da rodada de construção (F1.3/1.4/1.5)
- `e6e8799` — correção de números fabricados neste mesmo handoff
- `f96faaf` — achado do grupo sem holding, F1.6 não verificável, fatia 1.7 nasce
- `be9e1bf` — as 4 migrations aplicadas em produção, sonda 0 ausentes
- `15c8716` — fechamento de documentação (esta seção tinha números errados nessa passada — 4/7 em vez de 7/365 — corrigidos no commit seguinte)
