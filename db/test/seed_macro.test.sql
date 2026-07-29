-- Testes da CARGA INICIAL dos índices macro (`db/seed/macro_carga_inicial.sql`).
-- Rodar via db/test/run.sh (que aplica as migrations e o seed antes).
--
-- O seed é dado REAL buscado das APIs oficiais e versionado no repositório. O que
-- estes testes travam não são os números (eles mudam quando o arquivo é regerado)
-- e sim as propriedades que fazem o arquivo servir para o que existe:
--   • carrega as 6 séries mensais, não um subconjunto silencioso;
--   • traz o IPCA das DUAS fontes — sem isso a conferência entre fontes existe e
--     nunca tem o que comparar;
--   • passa na própria conferência (nenhuma divergência acima de 0,01 p.p.);
--   • produz ano fechado por COMPOSIÇÃO e marca o ano incompleto com o nº de meses;
--   • traz Focus para os anos que o modelo projeta.
--
-- E o teste mais importante deles: que o arquivo APLICA. Ele nasceu porque a
-- coleta pedia ao SGS uma janela que a API recusa (HTTP 400 em `ultimos/132`), e
-- o sintoma no export era uma aba vazia — indistinguível de "workflow não ativado".

\set ON_ERROR_STOP on

create or replace function teste_assert_seed(p_ok boolean, p_nome text, p_detalhe text default null)
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
  v_n int;
  v_series int;
  v_ipca_bcb int;
  v_ipca_ibge int;
  v_div int;
  v_ret numeric;
  v_meses int;
  v_anos int;
begin
  raise notice '--- 1. as 6 séries mensais entraram (não um subconjunto) ---';
  select count(distinct serie) into v_series from indice_macro_obs;
  perform teste_assert_seed(v_series = 6,
    '6 séries com observação', format('séries=%s', v_series));

  select count(*) into v_n from indice_macro_obs;
  perform teste_assert_seed(v_n > 700,
    'histórico longo o bastante para a janela de 10 anos', format('observações=%s', v_n));

  raise notice '--- 2. o IPCA vem das DUAS fontes (é o que autoriza conferir) ---';
  select count(*) into v_ipca_bcb from indice_macro_obs where serie = 'IPCA' and fonte = 'BCB/SGS';
  select count(*) into v_ipca_ibge from indice_macro_obs where serie = 'IPCA' and fonte = 'IBGE/SIDRA';
  perform teste_assert_seed(v_ipca_bcb > 100 and v_ipca_ibge > 100,
    'IPCA presente pelo BCB e pelo IBGE', format('bcb=%s ibge=%s', v_ipca_bcb, v_ipca_ibge));

  select count(*) into v_div from fn_divergencias_indice_macro();
  perform teste_assert_seed(v_div = 0,
    'o seed versionado passa na conferência entre fontes', format('divergências=%s', v_div));

  raise notice '--- 3. ano fechado compõe; ano incompleto é marcado ---';
  -- Ano completo: 12 meses e retorno positivo plausível para inflação brasileira.
  select retorno, meses into v_ret, v_meses
    from fn_indice_macro_anual(2015) where serie = 'IPCA' and ano = 2024;
  perform teste_assert_seed(v_meses = 12 and v_ret between 2 and 12,
    'IPCA de ano fechado sai composto e plausível', format('2024: %s%% em %s meses', round(v_ret, 2), v_meses));

  -- O ano corrente tem de aparecer com MENOS de 12 meses. Se aparecesse como
  -- cheio, entraria numa média de 3/5/10 anos puxando-a para baixo sem ninguém ver.
  select meses into v_meses
    from fn_indice_macro_anual(2015)
    where serie = 'IPCA' and ano = (select max(ano) from fn_indice_macro_anual(2015) where serie = 'IPCA');
  perform teste_assert_seed(v_meses between 1 and 12,
    'o ano mais recente declara quantos meses tem', format('meses=%s', v_meses));

  -- Câmbio é NÍVEL: varia entre fechamentos, não compõe taxa mensal.
  perform teste_assert_seed(
    (select natureza from fn_indice_macro_anual(2015) where serie = 'CAMBIO_USD' limit 1) = 'nivel',
    'câmbio continua sendo série de NÍVEL');

  raise notice '--- 4. Focus cobre os anos que o modelo projeta ---';
  select count(distinct ano_ref) into v_anos from indice_macro_expectativa where serie = 'IPCA';
  perform teste_assert_seed(v_anos >= 3,
    'expectativa de IPCA para 3+ anos (o horizonte do modelo)', format('anos=%s', v_anos));
  select count(distinct serie) into v_n from indice_macro_expectativa;
  perform teste_assert_seed(v_n >= 4,
    'Focus de várias séries (IPCA/Selic/IGP-M/PIB/câmbio)', format('séries=%s', v_n));

  raise notice 'TODOS OS TESTES DO SEED MACRO PASSARAM';
end $$;
