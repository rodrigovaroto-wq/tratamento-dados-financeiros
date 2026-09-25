-- Testes da 0194 (Supabase/migrations/0194_a_planilha_de_mutuos_que_nunca_foi_lida.sql).
-- Rodar via Supabase/test/run.sh.
--
-- O FORMATO É O DE PRODUÇÃO, MEDIDO — não inventado (regra 4). A planilha
-- MUTUOS de produção é um RETRATO de uma data: documento com período
-- `data-base 31/12/2025`, linhas com `chave` = par de empresas, `secao` NULA,
-- e o CONCEITO NA COLUNA (`periodo_coluna`): "Mutuante"/"Mutuária" (sem
-- número) e "Saldo devedor" com o valor; "TOTAL" é o subtotal. Todos os casos
-- de produção medidos (25/09/2026) têm a coluna numérica chamada "Saldo
-- devedor". É o mesmo arranjo que os dois FIXTURES do book (Vertentes,
-- Canastra) NÃO reproduzem — eles gravam `periodo_coluna` = o ANO, não o
-- cabeçalho da coluna (ver o cabeçalho da 0194), e é por isso que precisam de
-- um teste à parte em vez de reusar os fixtures existentes.
--
-- O QUE ESTE ARQUIVO TRAVA, em COMPORTAMENTO (nunca mecanismo — regra 3):
--
--   1. Planilha-retrato + balanços com conta de mútuo: a checagem CONCLUI
--      (precondicoes_ok = true) e acusa a divergência real, em reais.
--   2. Planilha corrigida para bater com o balanço: conclui `ok`.
--   3. Planilha-retrato de OUTRO ano (2024) consultada no período de 2025:
--      não conclui — `sem_periodo_par`, pendência aberta com texto que diz o
--      ano sem par.
--   4. Planilha-retrato sem coluna de saldo nenhuma: não conclui —
--      `linha_nao_localizada`.
--   5. NEGATIVO — balanço sem conta de mútuo nenhuma: continua
--      `documento_ausente`, SEM pendência (comportamento desenhado da
--      0117/0123, preservado por esta migration).
--
-- O ASSERT NÃO PARA NO PRIMEIRO ERRO: anota e segue, e o bloco final reprova
-- com a CONTAGEM (regra 2 — medir quantos asserts a guarda desligada
-- derruba).

begin;

create temp sequence _falhas_0194;

create or replace function pg_temp.teste_assert_0194(p_ok boolean, p_nome text, p_detalhe text default null)
returns void language plpgsql as $$
begin
  if coalesce(p_ok, false) then
    raise notice 'ok    %', p_nome;
  else
    raise notice 'FALHOU: % %', p_nome, coalesce(' — ' || p_detalhe, '');
    perform nextval('pg_temp._falhas_0194');
  end if;
end $$;

-- =============================================================================
-- 1 e 2. Planilha-retrato 31/12/2025 (Mutuante/Mutuária/Saldo devedor/TOTAL,
-- milhar) contra dois balanços que CONCORDAM entre si (16.300 a receber numa
-- entidade, 11.400 + 4.900 a pagar em duas outras): a checagem CONCLUI e
-- acusa os R$ 240 mil que a planilha erra (16.060 x 16.300). Corrigida a
-- planilha, conclui `ok`.
-- =============================================================================
do $$
declare
  v_caso   uuid;
  v_per    uuid; -- período da planilha (data-base 31/12/2025)
  v_doc_mut uuid;
  v_r      jsonb;
  v_ok     boolean;
  v_res    text;
  v_motivo text;
  v_num    numeric;
begin
  raise notice '--- 1/2. planilha-retrato: conclui e acusa a divergência; corrigida, conclui ok ---';
  v_caso := (fn_upsert_caso('0194: planilha-retrato contra balanços que se espelham'))::uuid;

  -- A PLANILHA — retrato de 31/12/2025, conceito na coluna (0145).
  v_r := fn_registrar_documento(v_caso, 'GRUPO RETRATO', 'data-base', '2025-12-31', 'MUTUOS', 0.96,
    'nome_arquivo', 'supabase_storage', '0194/mutuos-retrato.pdf', 'MUTUOS.pdf', true, 'HASH-0194-1', 'ok');
  v_doc_mut := (v_r->>'documento_id')::uuid;
  v_per := (select periodo_id from documento where id = v_doc_mut);
  perform fn_registrar_campos_extraidos((v_r->>'documento_versao_id')::uuid, jsonb_build_array(
    -- Colunas de NOME, sem número (como o retrato real) — não entram em
    -- comparação nenhuma (valor_num nulo), aqui só para reproduzir a forma.
    jsonb_build_object('ordem',0,'chave','RETRATO PARTICIPAÇÕES → RETRATO INDÚSTRIA','valor_texto','RETRATO PARTICIPAÇÕES S.A.','periodo_coluna','Mutuante','confianca','0.96'),
    jsonb_build_object('ordem',1,'chave','RETRATO PARTICIPAÇÕES → RETRATO INDÚSTRIA','valor_texto','RETRATO INDÚSTRIA LTDA.','periodo_coluna','Mutuária','confianca','0.96'),
    -- A coluna do SALDO — a numérica, a única que entra na soma.
    jsonb_build_object('ordem',2,'chave','RETRATO PARTICIPAÇÕES → RETRATO INDÚSTRIA','valor_num','11160','unidade','milhar','periodo_coluna','Saldo devedor','confianca','0.96'),
    jsonb_build_object('ordem',3,'chave','RETRATO PARTICIPAÇÕES → RETRATO COMERCIAL','valor_num','4900','unidade','milhar','periodo_coluna','Saldo devedor','confianca','0.96'),
    jsonb_build_object('ordem',4,'chave','TOTAL','valor_num','16060','unidade','milhar','periodo_coluna','Saldo devedor','confianca','0.96')
  ), 'N2');

  -- OS BALANÇOS — os dois lados se espelham (16.300 = 11.400 + 4.900).
  v_r := fn_registrar_documento(v_caso, 'RETRATO PARTICIPAÇÕES S.A.', 'anual', '2025', 'BALANCO', 0.97,
    'nome_arquivo', 'supabase_storage', '0194/bp-holding.pdf', 'BP HOLDING.pdf', true, 'HASH-0194-2', 'ok');
  perform fn_registrar_campos_extraidos((v_r->>'documento_versao_id')::uuid, jsonb_build_array(
    jsonb_build_object('ordem',0,'chave','Mútuos a receber - partes relacionadas','valor_num','16300','unidade','milhar','periodo_coluna','2025','confianca','0.97')
  ), 'N2');
  v_r := fn_registrar_documento(v_caso, 'RETRATO INDÚSTRIA LTDA.', 'anual', '2025', 'BALANCO', 0.97,
    'nome_arquivo', 'supabase_storage', '0194/bp-industria.pdf', 'BP INDUSTRIA.pdf', true, 'HASH-0194-3', 'ok');
  perform fn_registrar_campos_extraidos((v_r->>'documento_versao_id')::uuid, jsonb_build_array(
    jsonb_build_object('ordem',0,'chave','Mútuos a pagar - partes relacionadas','valor_num','11400','unidade','milhar','periodo_coluna','2025','confianca','0.97')
  ), 'N2');
  v_r := fn_registrar_documento(v_caso, 'RETRATO COMERCIAL LTDA.', 'anual', '2025', 'BALANCO', 0.97,
    'nome_arquivo', 'supabase_storage', '0194/bp-comercial.pdf', 'BP COMERCIAL.pdf', true, 'HASH-0194-4', 'ok');
  perform fn_registrar_campos_extraidos((v_r->>'documento_versao_id')::uuid, jsonb_build_array(
    jsonb_build_object('ordem',0,'chave','Mútuos a pagar - partes relacionadas','valor_num','4900','unidade','milhar','periodo_coluna','2025','confianca','0.97')
  ), 'N2');

  -- 1a. CONCLUI, e acusa os R$ 240 mil (16.300 x 16.060), em REAIS.
  v_r := fn_reconciliar_mutuos(v_caso, v_per);
  select precondicoes_ok, resultado, motivo_precondicao, divergencia_abs
    into v_ok, v_res, v_motivo, v_num
    from reconciliacao where id = (v_r->>'reconciliacao_id')::uuid;
  perform pg_temp.teste_assert_0194(v_ok and v_res = 'zona_cinzenta' and v_motivo is null,
    'planilha-retrato + balanços com conta de mútuo: a checagem CONCLUI (não documento_ausente)',
    format('precondicoes_ok=%s resultado=%s motivo=%s', v_ok, v_res, v_motivo));
  perform pg_temp.teste_assert_0194(v_num between 239000 and 241000,
    'e acusa a divergência real (16.300 x 16.060, em reais)', format('divergencia_abs=%s', v_num));

  select count(*) into v_num from pendencia
    where caso_id = v_caso and motivo = 'reconciliacao:mutuos_planilha_vs_balanco' and estado <> 'resolvida';
  perform pg_temp.teste_assert_0194(v_num = 1,
    'e ABRE pendência (a checagem voltando a funcionar, não uma regressão)', format('%s pendência(s)', v_num));

  -- 1b. Corrigida a planilha (11.160 -> 11.400, TOTAL -> 16.300): ok.
  update campo_extraido ce set valor_num = 11400
    from documento_versao dv where dv.documento_id = v_doc_mut and ce.documento_versao_id = dv.id
      and ce.chave = 'RETRATO PARTICIPAÇÕES → RETRATO INDÚSTRIA' and ce.periodo_coluna = 'Saldo devedor';
  update campo_extraido ce set valor_num = 16300
    from documento_versao dv where dv.documento_id = v_doc_mut and ce.documento_versao_id = dv.id
      and ce.chave = 'TOTAL';
  v_r := fn_reconciliar_mutuos(v_caso, v_per);
  select precondicoes_ok, resultado, motivo_precondicao into v_ok, v_res, v_motivo
    from reconciliacao where id = (v_r->>'reconciliacao_id')::uuid;
  perform pg_temp.teste_assert_0194(v_ok and v_res = 'ok' and v_motivo is null,
    'planilha corrigida (16.300 = 16.300): conclui ok',
    format('precondicoes_ok=%s resultado=%s motivo=%s', v_ok, v_res, v_motivo));
end $$;

-- =============================================================================
-- 3. Planilha-retrato de OUTRO ano (31/12/2024) consultada no período de
-- 2025: não conclui — sem_periodo_par, pendência aberta dizendo o ano sem par.
-- =============================================================================
do $$
declare
  v_caso uuid;
  v_r    jsonb;
  v_per_consulta uuid;
  v_ok   boolean;
  v_motivo text;
  v_desc text;
begin
  raise notice '--- 3. planilha-retrato de 2024 consultada em 2025: sem_periodo_par ---';
  v_caso := (fn_upsert_caso('0194: planilha-retrato de outro ano'))::uuid;

  -- Planilha: retrato de 31/12/2024.
  v_r := fn_registrar_documento(v_caso, 'GRUPO OUTRO ANO', 'data-base', '2024-12-31', 'MUTUOS', 0.96,
    'nome_arquivo', 'supabase_storage', '0194/mutuos-2024.pdf', 'MUTUOS 2024.pdf', true, 'HASH-0194-5', 'ok');
  perform fn_registrar_campos_extraidos((v_r->>'documento_versao_id')::uuid, jsonb_build_array(
    jsonb_build_object('ordem',0,'chave','OUTRO ANO PARTICIPAÇÕES → OUTRO ANO INDÚSTRIA','valor_num','5000','unidade','milhar','periodo_coluna','Saldo devedor','confianca','0.96')
  ), 'N2');

  -- Balanço com conta de mútuo — SÓ para 2025 (periodo_coluna='2025'), para
  -- que o ano de 2024 (sem coluna correspondente no balanço) fique com
  -- n_lados=0 e não interfira: o que este teste isola é o ano de 2025, cujo
  -- balanço TEM conta de mútuo mas a planilha não tem retrato para comparar.
  v_r := fn_registrar_documento(v_caso, 'OUTRO ANO PARTICIPAÇÕES S.A.', 'anual', '2025', 'BALANCO', 0.97,
    'nome_arquivo', 'supabase_storage', '0194/bp-outro-ano.pdf', 'BP OUTRO ANO.pdf', true, 'HASH-0194-6', 'ok');
  perform fn_registrar_campos_extraidos((v_r->>'documento_versao_id')::uuid, jsonb_build_array(
    jsonb_build_object('ordem',0,'chave','Mútuos a receber - partes relacionadas','valor_num','5200','unidade','milhar','periodo_coluna','2025','confianca','0.97')
  ), 'N2');

  -- Período de CONSULTA cobrindo 2024 e 2025 — precisa ancorar os dois anos
  -- para (a) achar a planilha de 2024 por compatibilidade e (b) o laço
  -- alcançar v_ano=2025, que é o que este teste isola.
  v_per_consulta := fn_upsert_periodo(v_caso, 'multi', '24,25');

  v_r := fn_reconciliar_mutuos(v_caso, v_per_consulta);
  select precondicoes_ok, motivo_precondicao into v_ok, v_motivo
    from reconciliacao where id = (v_r->>'reconciliacao_id')::uuid;
  perform pg_temp.teste_assert_0194(not v_ok and v_motivo = 'sem_periodo_par',
    'a planilha é retrato de 2024, o balanço tem mútuo em 2025: NÃO conclui, sem_periodo_par',
    format('precondicoes_ok=%s motivo=%s', v_ok, v_motivo));

  select descricao into v_desc from pendencia
    where caso_id = v_caso and motivo = 'reconciliacao:mutuos_planilha_vs_balanco' and estado <> 'resolvida';
  perform pg_temp.teste_assert_0194(
    v_desc like 'MOTIVO: sem período par%' and v_desc like '%2025%' and v_desc like '%2024%',
    'e o texto diz QUAL ano ficou sem par e de que data é a planilha (regra 1)', left(v_desc, 400));
end $$;

-- =============================================================================
-- 4. Planilha-retrato do próprio ano, mas SEM coluna de saldo nenhuma: não
-- conclui — linha_nao_localizada.
-- =============================================================================
do $$
declare
  v_caso uuid;
  v_r    jsonb;
  v_per  uuid;
  v_ok   boolean;
  v_motivo text;
begin
  raise notice '--- 4. planilha-retrato sem coluna de saldo: linha_nao_localizada ---';
  v_caso := (fn_upsert_caso('0194: planilha-retrato sem coluna de saldo'))::uuid;

  v_r := fn_registrar_documento(v_caso, 'GRUPO SEM SALDO', 'data-base', '2025-12-31', 'MUTUOS', 0.96,
    'nome_arquivo', 'supabase_storage', '0194/mutuos-sem-saldo.pdf', 'MUTUOS SEM SALDO.pdf', true, 'HASH-0194-7', 'ok');
  perform fn_registrar_campos_extraidos((v_r->>'documento_versao_id')::uuid, jsonb_build_array(
    -- Uma coluna numérica, mas o cabeçalho NÃO diz "saldo" — formato que o
    -- localizador da 0145 (termo 'saldo') não reconhece.
    jsonb_build_object('ordem',0,'chave','SEM SALDO PARTICIPAÇÕES → SEM SALDO INDÚSTRIA','valor_num','5000','unidade','milhar','periodo_coluna','Montante','confianca','0.96')
  ), 'N2');

  v_r := fn_registrar_documento(v_caso, 'SEM SALDO PARTICIPAÇÕES S.A.', 'anual', '2025', 'BALANCO', 0.97,
    'nome_arquivo', 'supabase_storage', '0194/bp-sem-saldo.pdf', 'BP SEM SALDO.pdf', true, 'HASH-0194-8', 'ok');
  perform fn_registrar_campos_extraidos((v_r->>'documento_versao_id')::uuid, jsonb_build_array(
    jsonb_build_object('ordem',0,'chave','Mútuos a receber - partes relacionadas','valor_num','5000','unidade','milhar','periodo_coluna','2025','confianca','0.97')
  ), 'N2');
  select periodo_id into v_per from documento where caso_id = v_caso and tipo_taxonomia = 'MUTUOS';

  v_r := fn_reconciliar_mutuos(v_caso, v_per);
  select precondicoes_ok, motivo_precondicao into v_ok, v_motivo
    from reconciliacao where id = (v_r->>'reconciliacao_id')::uuid;
  perform pg_temp.teste_assert_0194(not v_ok and v_motivo = 'linha_nao_localizada',
    'planilha-retrato do ano certo, mas sem coluna "saldo": NÃO conclui, linha_nao_localizada',
    format('precondicoes_ok=%s motivo=%s', v_ok, v_motivo));
end $$;

-- =============================================================================
-- 5. NEGATIVO — balanço sem conta de mútuo NENHUMA: continua documento_ausente,
-- SEM pendência (comportamento desenhado da 0117/0123, que esta migration
-- preserva).
-- =============================================================================
do $$
declare
  v_caso uuid;
  v_r    jsonb;
  v_per  uuid;
  v_ok   boolean;
  v_res  text;
  v_motivo text;
  v_n    int;
begin
  raise notice '--- 5. NEGATIVO: balanço sem conta de mútuo continua documento_ausente, sem pendência ---';
  v_caso := (fn_upsert_caso('0194: balanço sem conta de mútuo nenhuma'))::uuid;

  v_r := fn_registrar_documento(v_caso, 'GRUPO SEM MUTUO', 'data-base', '2025-12-31', 'MUTUOS', 0.96,
    'nome_arquivo', 'supabase_storage', '0194/mutuos-sem-conta.pdf', 'MUTUOS SEM CONTA.pdf', true, 'HASH-0194-9', 'ok');
  perform fn_registrar_campos_extraidos((v_r->>'documento_versao_id')::uuid, jsonb_build_array(
    jsonb_build_object('ordem',0,'chave','SEM MUTUO PARTICIPAÇÕES → SEM MUTUO INDÚSTRIA','valor_num','5000','unidade','milhar','periodo_coluna','Saldo devedor','confianca','0.96')
  ), 'N2');

  -- Balanço PRESENTE, mas sem conta de mútuo nenhuma (só caixa).
  v_r := fn_registrar_documento(v_caso, 'SEM MUTUO PARTICIPAÇÕES S.A.', 'anual', '2025', 'BALANCO', 0.97,
    'nome_arquivo', 'supabase_storage', '0194/bp-sem-mutuo.pdf', 'BP SEM MUTUO.pdf', true, 'HASH-0194-10', 'ok');
  perform fn_registrar_campos_extraidos((v_r->>'documento_versao_id')::uuid, jsonb_build_array(
    jsonb_build_object('ordem',0,'chave','Caixa e equivalentes','valor_num','1000','unidade','milhar','periodo_coluna','2025','confianca','0.97')
  ), 'N2');
  select periodo_id into v_per from documento where caso_id = v_caso and tipo_taxonomia = 'MUTUOS';

  v_r := fn_reconciliar_mutuos(v_caso, v_per);
  select precondicoes_ok, resultado, motivo_precondicao into v_ok, v_res, v_motivo
    from reconciliacao where id = (v_r->>'reconciliacao_id')::uuid;
  perform pg_temp.teste_assert_0194(not v_ok and v_res = 'precondicao_nao_satisfeita' and v_motivo = 'documento_ausente',
    -- `resultado` sai achatado para precondicao_nao_satisfeita (0186/0188); o
    -- valor ORIGINAL (documento_ausente) vive em motivo_precondicao — é ele
    -- quem decide, em fn_registrar_reconciliacao, que NÃO abre pendência.
    'balanço sem conta de mútuo: motivo_precondicao continua documento_ausente (comportamento preservado)',
    format('precondicoes_ok=%s resultado=%s motivo_precondicao=%s', v_ok, v_res, v_motivo));

  select count(*) into v_n from pendencia
    where caso_id = v_caso and motivo = 'reconciliacao:mutuos_planilha_vs_balanco' and estado <> 'resolvida';
  perform pg_temp.teste_assert_0194(v_n = 0,
    'e NÃO abre pendência — documento_ausente continua sendo o único motivo que não abre (0117/0123, preservado)',
    format('%s pendência(s)', v_n));
end $$;

-- =============================================================================
do $$
declare
  v_n int;
begin
  select case when is_called then last_value else 0 end into v_n from pg_temp._falhas_0194;
  if v_n > 0 then
    raise exception 'FALHOU: % assert(s) da 0194 reprovaram — ver as linhas FALHOU acima', v_n;
  end if;
  raise notice 'TODOS OS TESTES DA 0194 PASSARAM';
end $$;

rollback;
