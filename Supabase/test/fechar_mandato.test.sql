-- Testes de "fechar não é excluir" (Supabase/migrations/0114).
-- Rodar via Supabase/test/run.sh (que aplica as migrations antes).
--
-- O QUE ESTE ARQUIVO PROVA, e cada asserto é uma coisa que dá para errar
-- escrevendo a função "óbvia":
--
--   1. fechar CARIMBA e não apaga — o mandato continua lá, com tudo;
--   2. fechar duas vezes NÃO reescreve quem fechou (dois cliques no botão não
--      trocam a autoria do primeiro, e não movem a data);
--   3. reabrir limpa o carimbo, e a lista de ativos volta a incluí-lo;
--   4. cada uma das duas ações deixa rastro em `evento_auditoria`;
--   5. mandato inexistente é RECUSA escrita, não exceção — a tela precisa de uma
--      frase para mostrar, e o caso pode ter sido excluído por outra pessoa
--      entre a montagem da lista e o clique.

\set ON_ERROR_STOP on

create or replace function teste_assert_fechar(p_ok boolean, p_nome text, p_detalhe text default null)
returns void language plpgsql as $$
begin
  if p_ok then
    raise notice 'ok    %', p_nome;
  else
    raise exception 'FALHOU: % %', p_nome, coalesce(' — ' || p_detalhe, '');
  end if;
end $$;

do $$
declare
  v_caso   uuid;
  v_r      jsonb;
  v_quando timestamptz;
  v_n      int;
begin
  raise notice '--- 1. fechar carimba e preserva o mandato ---';
  insert into caso (nome) values ('teste fechar mandato') returning id into v_caso;

  perform teste_assert_fechar(
    (select fechado_em is null from caso where id = v_caso),
    'mandato nasce ATIVO (fechado_em nulo)');

  v_r := fn_fechar_caso(v_caso, 'analista@oria', 'operação não aconteceu');
  perform teste_assert_fechar((v_r->>'fechado')::boolean, 'fn_fechar_caso devolve fechado');
  perform teste_assert_fechar(
    (select fechado_em is not null and fechado_por = 'analista@oria'
        and motivo_fechamento = 'operação não aconteceu' from caso where id = v_caso),
    'o carimbo guarda quem fechou, quando e por quê');
  perform teste_assert_fechar(
    (select count(*) = 1 from caso where id = v_caso),
    'FECHAR NÃO APAGA — o mandato continua na base');

  raise notice '--- 2. fechar de novo não reescreve a autoria ---';
  select fechado_em into v_quando from caso where id = v_caso;
  v_r := fn_fechar_caso(v_caso, 'outra.pessoa@oria', 'outro motivo');
  perform teste_assert_fechar((v_r->>'ja_estava')::boolean, 'a segunda chamada se declara idempotente');
  perform teste_assert_fechar(
    (select fechado_por = 'analista@oria' and fechado_em = v_quando from caso where id = v_caso),
    'quem fechou e quando continuam sendo os do PRIMEIRO fechamento');

  raise notice '--- 3. reabrir limpa o carimbo ---';
  v_r := fn_reabrir_caso(v_caso, 'analista@oria');
  perform teste_assert_fechar((v_r->>'reaberto')::boolean, 'fn_reabrir_caso devolve reaberto');
  perform teste_assert_fechar(
    (select fechado_em is null and fechado_por is null and motivo_fechamento is null
       from caso where id = v_caso),
    'o mandato volta a ser ATIVO, sem sobra do fechamento');
  v_r := fn_reabrir_caso(v_caso, 'analista@oria');
  perform teste_assert_fechar((v_r->>'ja_estava')::boolean, 'reabrir o que já está aberto é no-op declarado');

  raise notice '--- 4. as duas ações deixam rastro ---';
  select count(*) into v_n from evento_auditoria
   where entidade_ref = 'caso:'||v_caso and acao in ('caso_fechado', 'caso_reaberto');
  perform teste_assert_fechar(v_n = 2, 'fechamento e reabertura na trilha', 'eventos=' || v_n);

  raise notice '--- 5. mandato inexistente é recusa escrita ---';
  v_r := fn_fechar_caso('00000000-0000-0000-0000-000000000000', 'analista@oria');
  perform teste_assert_fechar((v_r->>'recusado')::boolean, 'fechar caso inexistente é recusa');
  perform teste_assert_fechar(
    v_r->>'motivo_recusa' is not null and v_r->>'motivo_recusa' <> '',
    'a recusa traz uma frase que a tela pode mostrar');
  v_r := fn_reabrir_caso('00000000-0000-0000-0000-000000000000', 'analista@oria');
  perform teste_assert_fechar((v_r->>'recusado')::boolean, 'reabrir caso inexistente é recusa');

  delete from caso where id = v_caso;
  raise notice 'TODOS OS TESTES DE FECHAR MANDATO PASSARAM';
end $$;

drop function teste_assert_fechar(boolean, text, text);
