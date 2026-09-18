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

**Medição (regra 2):** 5 asserts novos em `entidade_papel.test.sql`. Sem a tipagem, teste que afirma enum deveria reprovar — **verificado**: com a tipagem removida, o teste reprova no tipo esperado.

## Fatia 1.4: Tabela nova `perimetro(caso, entidade, escopo, desde, ate)` (migration 0180)

**Problema que resolve:** Perímetro (quem entra no COMBINADO) não existia no schema. O que hoje é deduzido do dial era implícito no papel de entidade.

**Solução:**
- Tabela nova com identidade `(caso, entidade)` para cada perímetro
- Coluna `escopo` como `enum`: `linha_por_linha`, `ativo_passivo`, `resultado` — o que entra no COMBINADO
- Datas `desde` e `ate` porque perímetro **muda durante o mandato** — sem elas, um perímetro sem data mente sobre o exercício anterior
- Função de leitura `fn_perimetro_vigente(p_caso, p_entidade, p_data)` — retorna o escopo ativo em uma data
- Função de escrita `fn_perimetro_definir_escopo`

**Medição (regra 2):** 8 asserts novos em `perimetro.test.sql`. Sem a tabela, teste de mudança de perímetro no meio de um mandato deveria reprovar.

**Nota sobre colisão:** Duas sessões paralelas na mesma branch causaram uma colisão no push (commit `5c6916a` é merge, não rebase). Resolvida por `git merge origin/...` após verificar compatibilidade — ver `.claude/memory/colisao-sessoes-paralelas-mesma-branch.md`.

## Fatia 1.5: Participação societária (migration 0181)

**Problema que resolve:** Consolidação e eliminação intragrupo não têm como saber "A controla B" no nível de participação acionária. O que hoje é inferido de papel de grupo fica explícito como FK.

**Solução:**
- Coluna nova `entidade.controladora_id` — FK self-referencing para outra entidade (no máximo UMA controladora direta por entidade — não grafo completo)
- Coluna `entidade.percentual_participacao` — `numeric(6,3)`, validado em `(0, 100]` (intervalo aberto em zero: controladora com 0% não é controladora)
- Guarda `fn_entidade_criaria_ciclo_participacao` — limite de 50 saltos — chamada **antes de gravar** por `fn_entidade_definir_participacao`
- Função de leitura `fn_entidade_cadeia_controladora` — sobe a cadeia, para no topo

**Diferença de F4:** Esta FK **não entrega nada** em F1 — é só preparação. Consolidação e intercompany (que vão consumir ela) são trabalho de F6, depois que F4 (Conta Canônica) existir.

**Medição (regra 2):** 29 asserts novos em `entidade_participacao.test.sql`. **4 dos 29 foram medidos como não-vazios**: desligar a guarda de ciclo em `fn_entidade_definir_participacao` e os 4 asserts reprovam (tentativas de criar ciclo). Os outros 25 passam com ou sem a guarda. Medição registrada no cabeçalho do arquivo de teste.

## Verificação independente (regra 2 aplicada)

Cada fatia foi verificada antes de commit pela sessão principal:

1. Reconstruir o banco do zero (`Supabase/test/run.sh`) — 122 migrations aplicadas em sequência
2. Desligar a correção (remover a guarda, trocar a tipagem, etc.) — confirmar que a suíte reprova **no ponto esperado**
3. Religar a correção — confirmar `TODOS OS TESTES PASSARAM`
4. Conferir que nenhuma outra suíte regrediu

Nenhuma das três fatias (0179/0180/0181) foi aplicada em produção ainda — escrita ≠ aplicada é doutrina deste projeto. Quem aplica é uma sessão seguinte, contra a sonda.

## Estado de `F1.6` (próxima fatia)

Bloqueada — aguardando que o dono forneça o COMBINADO real do cliente. O mandato AMO teste 00 não tem COMBINADO real ingerido; o que está marcado como tal é apenas um balanço de uma entidade. A fatia exige conferir o perímetro contra o COMBINADO, e sem ele é impossível.

## Commits (em ordem)

- `14e80da` — F1.3
- `ceb2acc` — handoff de sessão paralela (F1.3 confirmada)
- `5c6916a` — merge das duas linhas paralelas
- `57a1814` — F1.4
- `a3381d8` — F1.5
