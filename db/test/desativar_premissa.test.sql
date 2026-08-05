-- Testes de `fn_desativar_premissa` (db/migrations/0104).
-- Rodar via db/test/run.sh (que aplica as migrations antes).
--
-- O QUE ESTES TESTES TRAVAM, e por que cada um existe:
--
--   • desativar LIMPA o vínculo linha↔premissa. Sem isso, a tela (que monta o
--     seletor a partir das ATIVAS), a conferência (que conta
--     `caso_linha_premissa` sem olhar `ativo`) e o export (que procura a
--     premissa entre as ativas e não acha) passam a ler o mesmo caso de três
--     formas diferentes, todas em silêncio;
--   • a MESMA premissa pode estar como premissa da linha E como sazonalidade
--     dela — as duas colunas são limpas, e contadas separado;
--   • a linha que fica sem as duas é APAGADA; a que ainda tem sazonalidade
--     SOBREVIVE com premissa nula ("escolhi não projetar"), que é estado
--     legítimo desde a 0038;
--   • `valores` é PRESERVADO: reativar devolve o que foi digitado;
--   • desativar o que não está ativo é RECUSA RETORNADA, não exceção;
--   • a remoção deixa rastro em `decisao`, com os números do que foi desfeito.

\set ON_ERROR_STOP on

create or replace function teste_assert_dp(p_ok boolean, p_nome text, p_detalhe text default null)
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
  v_caso uuid;
  v_r    jsonb;
  v_doc  jsonb;
  v_ver  uuid;
  v_n    int;
  v_txt  text;
begin
  v_caso := (fn_upsert_caso('Caso desativar premissa ' || clock_timestamp()::text))::uuid;

  -- Um documento com quatro contas de receita e uma de custo, para haver o que
  -- vincular. Rótulos REAIS de demonstração, não "Conta 1": rótulo inventado não
  -- exercita `fn_papel_linha`, que é a função que decide se a linha é conta.
  v_doc := fn_registrar_documento(v_caso, 'DESATIVAR PREMISSA LTDA.', 'anual', '2025',
    'DRE', 0.95, 'nome_arquivo', 'supabase_storage', 'dp/1.pdf', 'DRE 1.pdf', true,
    'HASH-DP-1', 'ok');
  v_ver := (v_doc->>'documento_versao_id')::uuid;
  perform fn_registrar_campos_extraidos(v_ver, jsonb_build_array(
    jsonb_build_object('ordem', 1, 'chave', 'Receita com venda de produtos',
                       'valor_num', '1000', 'unidade', 'milhares', 'moeda', 'BRL',
                       'confianca', '0.97', 'secao_canonica', 'receita_bruta'),
    jsonb_build_object('ordem', 2, 'chave', 'Receita com prestação de serviços',
                       'valor_num', '400', 'unidade', 'milhares', 'moeda', 'BRL',
                       'confianca', '0.97', 'secao_canonica', 'receita_bruta'),
    jsonb_build_object('ordem', 3, 'chave', 'Receita de exportação',
                       'valor_num', '250', 'unidade', 'milhares', 'moeda', 'BRL',
                       'confianca', '0.97', 'secao_canonica', 'receita_bruta'),
    jsonb_build_object('ordem', 4, 'chave', 'Matéria-prima consumida',
                       'valor_num', '600', 'unidade', 'milhares', 'moeda', 'BRL',
                       'confianca', '0.97', 'secao_canonica', 'custos')
  ), 'N2');

  raise notice '--- 1. o cenário: duas premissas ativas e a receita vinculada em lote ---';

  perform fn_ativar_premissa(v_caso, 'CRESC_NOMINAL',
    '{"2026": 8, "2027": 7}'::jsonb, 'digitado', 'teste');
  perform fn_ativar_premissa(v_caso, 'SAZONALIDADE', '{"2026": 1}'::jsonb, 'digitado', 'teste');
  perform fn_ativar_premissa(v_caso, 'CUSTO_VARIAVEL', '{"2026": 62}'::jsonb, 'digitado', 'teste');

  v_r := fn_aplicar_premissa_em_lote(v_caso, 'receita_bruta', 'CRESC_NOMINAL', 'teste', 'SAZONALIDADE');
  perform teste_assert_dp((v_r->>'n_linhas')::int = 3,
    'o lote vinculou as 3 contas de receita, com sazonalidade junto',
    format('n_linhas: %s', v_r->>'n_linhas'));
  perform fn_aplicar_premissa_em_lote(v_caso, 'custos', 'CUSTO_VARIAVEL', 'teste');

  select count(*) into v_n from caso_linha_premissa
   where caso_id = v_caso and premissa_codigo = 'CRESC_NOMINAL';
  perform teste_assert_dp(v_n = 3, 'três linhas dirigidas por CRESC_NOMINAL', format('%s', v_n));

  raise notice '--- 2. desativar LIMPA o vínculo e DIZ quantos desfez ---';

  v_r := fn_desativar_premissa(v_caso, 'CRESC_NOMINAL', 'teste');
  perform teste_assert_dp(coalesce((v_r->>'recusado')::boolean, false) = false,
    'a remoção foi aceita', v_r::text);
  perform teste_assert_dp((v_r->>'n_vinculos_desfeitos')::int = 3,
    'devolve 3 vínculos desfeitos — desfazer em silêncio seria pior que não desfazer',
    format('n_vinculos_desfeitos: %s', v_r->>'n_vinculos_desfeitos'));

  perform teste_assert_dp(
    not exists (select 1 from caso_premissa
                 where caso_id = v_caso and premissa_codigo = 'CRESC_NOMINAL' and ativo),
    'a premissa saiu de ativa');

  select count(*) into v_n from caso_linha_premissa
   where caso_id = v_caso and premissa_codigo = 'CRESC_NOMINAL';
  perform teste_assert_dp(v_n = 0,
    'NENHUMA linha continua apontando para a premissa removida — este é o assert '
    'que impede tela, conferência e export de discordarem', format('sobraram: %s', v_n));

  raise notice '--- 3. a linha SOBREVIVE enquanto tiver sazonalidade ---';

  -- As três linhas de receita tinham premissa E sazonalidade. Tirada a premissa,
  -- a decisão de curva mensal continua sendo do analista.
  select count(*) into v_n from caso_linha_premissa
   where caso_id = v_caso and sazonalidade_codigo = 'SAZONALIDADE' and premissa_codigo is null;
  perform teste_assert_dp(v_n = 3,
    'as 3 linhas continuam existindo com premissa nula e sazonalidade preservada',
    format('%s', v_n));

  raise notice '--- 4. a conferência PASSA A CONCORDAR com a tela ---';

  -- É o efeito que motivou a migration: `linhas_com_premissa` lê
  -- `caso_linha_premissa` sem olhar `ativo`. Com o vínculo limpo, as duas
  -- leituras voltam a dizer a mesma coisa.
  v_r := fn_conferir_modelagem(v_caso);
  perform teste_assert_dp((v_r->>'linhas_com_premissa')::int = 1,
    'só a linha de custo conta como configurada (a receita voltou a ficar sem premissa)',
    format('linhas_com_premissa: %s', v_r->>'linhas_com_premissa'));

  raise notice '--- 5. desativar a SAZONALIDADE limpa a outra coluna e apaga a linha ---';

  v_r := fn_desativar_premissa(v_caso, 'SAZONALIDADE', 'teste');
  perform teste_assert_dp((v_r->>'n_sazonalidades_desfeitas')::int = 3,
    'as 3 sazonalidades são contadas SEPARADO da premissa — são decisões distintas',
    format('n_sazonalidades_desfeitas: %s', v_r->>'n_sazonalidades_desfeitas'));
  perform teste_assert_dp((v_r->>'n_linhas_removidas')::int = 3,
    'e a linha que ficou sem as duas é apagada', format('%s', v_r->>'n_linhas_removidas'));

  select count(*) into v_n from caso_linha_premissa where caso_id = v_caso;
  perform teste_assert_dp(v_n = 1, 'sobra só a linha de custo', format('%s', v_n));

  raise notice '--- 6. `valores` é preservado: reativar devolve o que foi digitado ---';

  select valores->>'2026' into v_txt from caso_premissa
   where caso_id = v_caso and premissa_codigo = 'CRESC_NOMINAL';
  perform teste_assert_dp(v_txt = '8',
    'o valor de 2026 continua gravado na premissa desativada', coalesce(v_txt, '(nulo)'));

  perform fn_ativar_premissa(v_caso, 'CRESC_NOMINAL',
    '{"2026": 8, "2027": 7}'::jsonb, 'digitado', 'teste');
  perform teste_assert_dp(
    exists (select 1 from caso_premissa
             where caso_id = v_caso and premissa_codigo = 'CRESC_NOMINAL' and ativo),
    'reativar volta a ligar a mesma premissa');

  raise notice '--- 7. recusa RETORNADA, não exceção ---';

  perform fn_desativar_premissa(v_caso, 'PMR', 'teste');  -- nunca ativada
  v_r := fn_desativar_premissa(v_caso, 'PMR', 'teste');
  perform teste_assert_dp((v_r->>'recusado')::boolean,
    'remover premissa que não está ativa é RECUSADO', v_r::text);
  perform teste_assert_dp(v_r->>'motivo_recusa' like '%não está ativa%',
    'e o motivo diz o que aconteceu', v_r->>'motivo_recusa');

  v_r := fn_desativar_premissa(v_caso, 'NAO_EXISTE_NO_CATALOGO', 'teste');
  perform teste_assert_dp((v_r->>'recusado')::boolean,
    'código fora do catálogo também é recusa retornada', v_r::text);

  raise notice '--- 8. a remoção deixa rastro, com os números ---';

  select count(*) into v_n from decisao
   where caso_id = v_caso and motivo like 'Premissa%REMOVIDA%';
  perform teste_assert_dp(v_n = 2,
    'as duas remoções estão em `decisao` — alguém vai perguntar por que a receita '
    'parou de ser projetada', format('%s', v_n));

  -- Filtra pelo CÓDIGO no payload, não pelo motivo: o motivo traz o nome de
  -- exibição ("Crescimento nominal da receita"), e casar texto de rótulo é
  -- justamente o tipo de acoplamento que quebra quando alguém renomeia a
  -- premissa no catálogo.
  select payload->>'n_vinculos_desfeitos' into v_txt from decisao
   where caso_id = v_caso and payload->>'premissa' = 'CRESC_NOMINAL'
     and motivo like '%REMOVIDA%' limit 1;
  perform teste_assert_dp(v_txt = '3',
    'e o rastro guarda QUANTAS linhas a remoção desfez', coalesce(v_txt, '(nulo)'));

  raise notice 'TODOS OS TESTES DE DESATIVAR PREMISSA PASSARAM';
end $$;
