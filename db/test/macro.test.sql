-- Testes dos índices macro (migration 0025). Roda dentro de db/test/run.sh.
--
-- A disciplina do repositório: cada checagem tem um caso NEGATIVO provando que
-- ela ainda pega o erro real. Uma checagem que só vê o caminho feliz passa
-- verde enquanto o defeito acontece — foi assim que 36 somas erradas
-- atravessaram o teste v25.
do $$
declare
  v_ins int; v_upd int; v_n int;
  v_ret numeric; v_meses int; v_div int;
begin
  raise notice '--- 1. ingestão idempotente e revisão de série ---';

  -- Valores REAIS do IPCA (BCB/SGS, jan-mar/2026).
  select n_inseridas, n_atualizadas into v_ins, v_upd from fn_registrar_indice_macro($j$[
    {"serie":"IPCA","fonte":"BCB/SGS","data_ref":"2026-01-01","valor":0.33},
    {"serie":"IPCA","fonte":"BCB/SGS","data_ref":"2026-02-01","valor":0.70},
    {"serie":"IPCA","fonte":"BCB/SGS","data_ref":"2026-03-01","valor":0.42}
  ]$j$::jsonb);
  assert v_ins = 3 and v_upd = 0, format('esperado 3 inserções, veio %s/%s', v_ins, v_upd);
  raise notice 'ok    3 observações gravadas';

  -- Reprocessar o MESMO lote não pode duplicar nem contar como atualização:
  -- o workflow roda todo mês e sempre rebaixa uma janela que se sobrepõe.
  select n_inseridas, n_atualizadas into v_ins, v_upd from fn_registrar_indice_macro($j$[
    {"serie":"IPCA","fonte":"BCB/SGS","data_ref":"2026-01-01","valor":0.33}
  ]$j$::jsonb);
  assert v_ins = 0 and v_upd = 0, format('reprocesso deveria ser no-op, veio %s/%s', v_ins, v_upd);
  assert (select count(*) from indice_macro_obs where serie='IPCA') = 3, 'reprocesso duplicou linha';
  raise notice 'ok    reprocessar o mesmo mês é no-op (idempotente)';

  -- Mas uma REVISÃO da fonte tem de entrar (IBGE revisa série; é o que se quer capturar).
  select n_inseridas, n_atualizadas into v_ins, v_upd from fn_registrar_indice_macro($j$[
    {"serie":"IPCA","fonte":"BCB/SGS","data_ref":"2026-01-01","valor":0.35}
  ]$j$::jsonb);
  assert v_upd = 1, format('revisão deveria atualizar, veio %s', v_upd);
  assert (select valor from indice_macro_obs where serie='IPCA' and data_ref='2026-01-01' and fonte='BCB/SGS') = 0.35,
    'valor revisado não foi gravado';
  raise notice 'ok    valor revisado pela fonte sobrescreve o anterior';

  -- Série fora do catálogo é ignorada: código novo entra por migration, não pela ingestão.
  select n_inseridas into v_ins from fn_registrar_indice_macro($j$[
    {"serie":"INVENTADO","fonte":"BCB/SGS","data_ref":"2026-01-01","valor":1.0}
  ]$j$::jsonb);
  assert v_ins = 0, 'série desconhecida não pode entrar';
  raise notice 'ok    série fora do catálogo é recusada';

  raise notice '--- 2. as DUAS fontes convivem (é o que permite conferir) ---';
  perform fn_registrar_indice_macro($j$[
    {"serie":"IPCA","fonte":"IBGE/SIDRA","data_ref":"2026-01-01","valor":0.33},
    {"serie":"IPCA","fonte":"IBGE/SIDRA","data_ref":"2026-02-01","valor":0.70}
  ]$j$::jsonb);
  assert (select count(*) from indice_macro_obs where serie='IPCA' and data_ref='2026-01-01') = 2,
    'a segunda fonte sobrescreveu a primeira em vez de conviver';
  raise notice 'ok    BCB e IBGE coexistem no mesmo mês';

  -- Divergência REAL é pega: jan/2026 está 0.35 (revisado) no BCB e 0.33 no IBGE.
  select count(*) into v_div from fn_divergencias_indice_macro();
  assert v_div = 1, format('esperada 1 divergência, veio %s', v_div);
  raise notice 'ok    divergência entre fontes é detectada';

  -- …e arredondamento de publicação NÃO vira alerta (0,01 p.p.).
  perform fn_registrar_indice_macro($j$[
    {"serie":"IPCA","fonte":"BCB/SGS","data_ref":"2026-01-01","valor":0.33},
    {"serie":"IPCA","fonte":"IBGE/SIDRA","data_ref":"2026-03-01","valor":0.43}
  ]$j$::jsonb);
  select count(*) into v_div from fn_divergencias_indice_macro();
  assert v_div = 0, format('arredondamento não pode virar alerta, veio %s divergências', v_div);
  raise notice 'ok    diferença de arredondamento (0,01 p.p.) não gera alerta';

  raise notice '--- 3. o ano acumula por COMPOSIÇÃO, não por soma ---';
  delete from indice_macro_obs;
  -- 12 meses de 1% = 12,6825%, não 12%. É o erro que compõe e ninguém vê.
  insert into indice_macro_obs (serie, fonte, data_ref, valor)
  select 'IPCA', 'BCB/SGS', make_date(2024, m, 1), 1.0 from generate_series(1, 12) m;
  select retorno, meses into v_ret, v_meses from fn_indice_macro_anual() where serie='IPCA' and ano=2024;
  assert v_meses = 12, format('esperados 12 meses, veio %s', v_meses);
  assert abs(v_ret - 12.682503013196977) < 0.0001, format('composição errada: %s (soma daria 12)', v_ret);
  assert abs(v_ret - 12.0) > 0.5, 'o valor bateu com a SOMA — a composição não está sendo feita';
  raise notice 'ok    12 meses de 1%% dão 12,68%% (composto), não 12%% (somado)';

  -- Ano incompleto é marcado, não escondido nem completado.
  insert into indice_macro_obs (serie, fonte, data_ref, valor)
  select 'IPCA', 'BCB/SGS', make_date(2025, m, 1), 0.5 from generate_series(1, 4) m;
  select meses into v_meses from fn_indice_macro_anual() where serie='IPCA' and ano=2025;
  assert v_meses = 4, format('ano parcial deveria reportar 4 meses, veio %s', v_meses);
  raise notice 'ok    ano incompleto é reportado com o nº de meses (não vira ano cheio)';

  raise notice '--- 4. série de NÍVEL varia entre fechamentos (não compõe) ---';
  insert into indice_macro_obs (serie, fonte, data_ref, valor) values
    ('CAMBIO_USD','BCB/SGS','2024-01-01', 5.00),
    ('CAMBIO_USD','BCB/SGS','2024-12-01', 6.00);
  select retorno into v_ret from fn_indice_macro_anual() where serie='CAMBIO_USD' and ano=2024;
  assert abs(v_ret - 20.0) < 0.0001, format('câmbio 5,00→6,00 deveria dar 20%%, veio %s', v_ret);
  raise notice 'ok    câmbio 5,00 → 6,00 = +20%% (variação, não composição)';

  raise notice '--- 5. expectativa é DATADA (sem isso a projeção não se reproduz) ---';
  select fn_registrar_expectativa_macro($j$[
    {"serie":"IPCA","ano_ref":2026,"mediana":5.1209,"media":5.13,"respondentes":151,"coletado_em":"2026-07-24"},
    {"serie":"IPCA","ano_ref":2027,"mediana":4.50,"media":4.51,"respondentes":148,"coletado_em":"2026-07-24"}
  ]$j$::jsonb) into v_n;
  assert v_n = 2, format('esperadas 2 expectativas, veio %s', v_n);

  -- Boletim de outra semana para o MESMO ano é outro registro, não um update:
  -- é o que permite reproduzir uma projeção feita no passado.
  select fn_registrar_expectativa_macro($j$[
    {"serie":"IPCA","ano_ref":2026,"mediana":5.28,"coletado_em":"2026-07-17"}
  ]$j$::jsonb) into v_n;
  assert (select count(*) from indice_macro_expectativa where serie='IPCA' and ano_ref=2026) = 2,
    'a coleta anterior foi sobrescrita — a projeção antiga deixou de ser reproduzível';
  assert (select mediana from indice_macro_expectativa
          where serie='IPCA' and ano_ref=2026 order by coletado_em desc limit 1) = 5.1209,
    'a coleta mais recente não é a que prevalece na leitura';
  raise notice 'ok    duas coletas do mesmo ano coexistem; a mais recente prevalece';

  raise notice 'TODOS OS TESTES DE MACRO PASSARAM';
end $$;
