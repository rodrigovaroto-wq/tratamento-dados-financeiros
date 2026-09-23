---
id: f1-controle-comum-0182-0183
tipo: feature
toca:
  - Supabase/migrations/0182_o_grupo_horizontal_que_a_controladora_nao_alcancava.sql
  - Supabase/migrations/0183_a_forma_de_controle_que_ninguem_declarava.sql
  - Supabase/test/entidade_controlador.test.sql
  - Supabase/test/entidade_forma_de_controle.test.sql
  - Supabase/test/instalacao_cobertura_nao_regride.test.sql
  - Supabase/test/sonda-producao.mjs
ancora:
  - Supabase/migrations/0183_a_forma_de_controle_que_ninguem_declarava.sql#public.fn_pendencia_forma_de_controle_backfill(p_caso_id
ancora_sha: 72e22f305919
substitui: []
---

# F1.7: grupo por controle comum, sem holding (migrations 0182–0183)

**Escrita em:** 21–23/09/2026 · PR #238 · **0182 aplicada em produção em 23/09; 0183 pendente.**

**O defeito que a originou** (`.claude/memory/grupo-por-controle-comum-sem-holding.md`): as 8
empresas do mandato AMO não têm holding — todos os sócios são pessoas físicas. A `0181` só modela
controle EMPRESA→EMPRESA, então `controladora_id` fica NULL nas 8 por estar certo, e esse NULL era
indistinguível de "ninguém cadastrou".

## O que cada migration entrega

- **0182** — `controlador` (pessoa física, ou jurídica externa ao perímetro) + `entidade_controlador`
  (N:N com percentual, sem temporalidade de propósito) + `fn_grupo_por_controle_comum` (fecho
  transitivo). A guarda de soma nunca deixa passar de 100 e **nunca exige 100** (conhecimento
  parcial é o estado normal). `percentual` NULL = sócio conhecido sem percentual medido, distinto de
  linha ausente = não se sabe se é sócio.
- **0183** — `entidade.forma_de_controle` (`indefinido` como default · `controlada_por_entidade` ·
  `controle_comum`), com duas guardas: `check` de coerência com `controladora_id`, e gatilho que
  exige vínculo para `controle_comum`. Um quarto rótulo (capital pulverizado) foi considerado e
  RECUSADO por falta de medição. Também carrega o gatilho que impede o marcador de cobertura da
  sonda de regredir, e o reparo dele.

## Medição (regra 2), remedida contra o código final

| Guarda | Asserts que reprovam desligada |
|---|---|
| 0182 soma (inclui mudança de `entidade_id`) | 5 de 32 |
| 0182 fecho transitivo | 3 de 32 |
| 0183 check de coerência | 4 de 24 |
| 0183 gatilho do vínculo | 4 de 24 (2 diretos, 2 por cascata) |
| 0183 backfill respeita a triagem | 1 de 24, e 1 na sonda |
| 0183 marcador não regride | 2 de 3 |

## Três coisas que só a execução revelou

1. **As duas guardas da 0183 se sobrepõem.** A cláusula `controle_comum ⇒ controladora_id IS NULL`
   do check podia ser apagada com a suíte verde: o único assert que a tocava era satisfeito pelo
   gatilho. O arranjo que faltava — entidade com controladora E vínculo — é real.
2. **O backfill repetia o ruído da 0179.** Alcançaria as 365 entidades do banco; 347 já tinham sido
   julgadas ruído. Agora exclui a triagem existente e alcança 18 (medido em produção antes de aplicar).
3. **Com o dado real, o modelo dá DOIS grupos de dois, não um de oito.** Unir os dois exigiria
   afirmar que sócios de mesmo sobrenome são um bloco familiar — juízo, não medição. O critério do
   roadmap foi revisado por isso (§12.2).

## O que depende do dono

Aplicar a 0183 em dois envios (o `alter type ... add value` sozinho primeiro) — o classificador do
Claude Code bloqueou o apply. Registrar o dado real (sócios, forma de controle) é decisão com o
contrato na mão, não código. Ver `ESTADO.md`.
