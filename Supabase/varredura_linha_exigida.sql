-- =============================================================================
-- VARREDURA — migra as pendências de linha exigida para o formato POR ENTIDADE
--
-- QUANDO RODAR: depois de aplicar a `0119`, e só se você quiser que os casos
-- JÁ GRAVADOS mudem de formato agora. Sem isto nada fica órfão: a `0119` já
-- resolve a pendência de formato velho e abre as novas no primeiro recomputo
-- natural de cada caso — que acontece quando chega extração ou revisão. O que
-- este script faz é antecipar isso para o caso que está parado.
--
-- POR QUE ELE NÃO ESTÁ DENTRO DA MIGRATION (a decisão está registrada lá):
-- recomputar a completude é a única operação desta entrega que TOCA caso
-- existente, e o efeito visível é uma leva de pendências novas aparecendo de
-- uma vez na fila do painel, sem ninguém ter enviado nada. Separado, você
-- aplica a estrutura hoje e escolhe a hora da varredura — ou roda num mandato
-- só, para ver o efeito antes de soltar em todos.
--
-- É SEGURO E IDEMPOTENTE: `fn_recomputar_completude` é o que o pipeline já
-- chama a cada extração. Ela só escreve em `pendencia` (derivada), em
-- `checklist_item_status` e no `status` do caso — nenhum campo extraído,
-- nenhuma decisão humana, nenhum aceite. Rodar duas vezes dá o mesmo resultado.
--
--   -- todos os mandatos:
--   supabase db execute --file Supabase/varredura_linha_exigida.sql
--
--   -- um mandato só (troque o uuid e rode este comando no SQL Editor):
--   select fn_recomputar_completude('00000000-0000-0000-0000-000000000000'::uuid);
-- =============================================================================

do $$
declare
  v_caso record;
  v_n int := 0;
  v_antes int;
  v_depois int;
begin
  select count(*) into v_antes from pendencia
   where tipo = 'linha_exigida_ausente' and estado <> 'resolvida';

  for v_caso in select id from caso order by criado_em loop
    perform fn_recomputar_completude(v_caso.id);
    v_n := v_n + 1;
  end loop;

  select count(*) into v_depois from pendencia
   where tipo = 'linha_exigida_ausente' and estado <> 'resolvida';

  -- O NÚMERO SAI ESCRITO, e não é enfeite: é ele que responde "o que essa
  -- varredura fez com a minha fila?" sem obrigar ninguém a contar antes e
  -- depois à mão. Um salto grande aqui não é erro — é a granularidade fina
  -- enxergando o que a antiga não enxergava —, mas é o tipo de coisa que se
  -- quer saber no momento em que acontece, não uma semana depois.
  raise notice 'varredura: % caso(s) recomputado(s) — pendências de linha exigida em aberto: % antes, % depois (% a mais)',
    v_n, v_antes, v_depois, v_depois - v_antes;
end $$;
