-- =============================================================================
-- 0167 — o faturamento é UM VALOR POR MÊS, não uma célula por categoria
--
-- OS NÚMEROS SÃO DO RELATÓRIO REAL (regra 4): `GENERAL TABACO - FATURAMENTO
-- 2024.pdf`, do lote do caso "teste 143", lido no export que o dono enviou. A
-- forma da tabela:
--
--     M Ê S      ANO    Saídas R$   Serviços R$   Outros R$   Total R$
--     Janeiro    2024   4.018.139,19      0,00        0,00    4.018.139,19
--     Fevereiro  2024   5.110.999,06      0,00        0,00    5.110.999,06
--     Março      2024   5.250.012,21      0,00        0,00    5.250.012,21
--
-- Cada célula vira uma linha de `campo_extraido` com o MÊS na `chave` e a
-- CATEGORIA em `periodo_coluna` — quatro linhas com a chave 'Janeiro 2024'.
--
-- O QUE ESTE ARQUIVO MEDE:
--   1. três meses somam o faturamento REAL (14.379.150,46), não o dobro, e
--      `n_linhas` diz TRÊS meses, não doze células;
--   2. o formato SEM coluna de total (um valor por mês, o do book-vertentes)
--      continua somando a quebra — a correção não pode ter virado "só conta
--      quem tem coluna Total", que zeraria esse formato inteiro;
--   3. o formato com quebra e SEM total soma as categorias — é o caso
--      intermediário, e sem ele a regra "se tem total, ele manda" poderia ter
--      virado "ignore o que não for total".
-- =============================================================================

create or replace function teste_assert_fat(p_cond boolean, p_nome text, p_detalhe text default null)
returns void language plpgsql as $$
begin
  if p_cond then
    raise notice 'ok    %', p_nome;
  else
    raise exception 'FALHOU: % %', p_nome, coalesce(' — ' || p_detalhe, '');
  end if;
end $$;

do $$
declare
  v_caso  uuid;
  v_ver   uuid;
  v_r     jsonb;
  v_soma  numeric;
  v_n     int;
begin
  raise notice '--- 1. a tabela REAL da GENERAL TABACO: 3 meses, 12 células, um valor por mês ---';
  v_caso := (fn_upsert_caso('Faturamento por mês'))::uuid;

  v_r := fn_registrar_documento(v_caso, 'GENERAL TABACO NEGOCIOS E LOGISTICA LT', 'ano', '2024',
    'FATURAMENTO_24M', 0.99, 'nome_arquivo', 'supabase_storage', 's/fat2024.pdf',
    'GENERAL TABACO - FATURAMENTO 2024.pdf', true, 'HASH-FAT-POR-MES-1', 'ok');
  v_ver := (v_r->>'documento_versao_id')::uuid;

  perform fn_registrar_campos_extraidos(v_ver, jsonb_build_array(
    -- Janeiro: as QUATRO células, na ordem em que a extração as devolve.
    jsonb_build_object('ordem',0,'chave','Janeiro 2024','periodo_coluna','Serviços R$',
                       'valor_num','0','unidade','unidade','moeda','BRL','confianca','0.99'),
    jsonb_build_object('ordem',1,'chave','Janeiro 2024','periodo_coluna','Saídas R$',
                       'valor_num','4018139.19','unidade','unidade','moeda','BRL','confianca','0.99'),
    jsonb_build_object('ordem',2,'chave','Janeiro 2024','periodo_coluna','Outros R$',
                       'valor_num','0','unidade','unidade','moeda','BRL','confianca','0.99'),
    jsonb_build_object('ordem',3,'chave','Janeiro 2024','periodo_coluna','Total R$',
                       'valor_num','4018139.19','unidade','unidade','moeda','BRL','confianca','0.99'),
    -- Fevereiro
    jsonb_build_object('ordem',4,'chave','Fevereiro 2024','periodo_coluna','Total R$',
                       'valor_num','5110999.06','unidade','unidade','moeda','BRL','confianca','0.99'),
    jsonb_build_object('ordem',5,'chave','Fevereiro 2024','periodo_coluna','Outros R$',
                       'valor_num','0','unidade','unidade','moeda','BRL','confianca','0.99'),
    jsonb_build_object('ordem',6,'chave','Fevereiro 2024','periodo_coluna','Saídas R$',
                       'valor_num','5110999.06','unidade','unidade','moeda','BRL','confianca','0.99'),
    jsonb_build_object('ordem',7,'chave','Fevereiro 2024','periodo_coluna','Serviços R$',
                       'valor_num','0','unidade','unidade','moeda','BRL','confianca','0.99'),
    -- Março
    jsonb_build_object('ordem',8,'chave','Março 2024','periodo_coluna','Total R$',
                       'valor_num','5250012.21','unidade','unidade','moeda','BRL','confianca','0.99'),
    jsonb_build_object('ordem',9,'chave','Março 2024','periodo_coluna','Outros R$',
                       'valor_num','0','unidade','unidade','moeda','BRL','confianca','0.99'),
    jsonb_build_object('ordem',10,'chave','Março 2024','periodo_coluna','Serviços R$',
                       'valor_num','0','unidade','unidade','moeda','BRL','confianca','0.99'),
    jsonb_build_object('ordem',11,'chave','Março 2024','periodo_coluna','Saídas R$',
                       'valor_num','5250012.21','unidade','unidade','moeda','BRL','confianca','0.99')
  ), 'N2');

  select soma, n_linhas into v_soma, v_n from fn_somar_faturamento_ano(v_ver, '2024', '24');

  -- ESTES SÃO OS ASSERTS QUE REPROVAM COM A CORREÇÃO DESLIGADA: sem ela a soma
  -- sai 28.758.300,92 (o dobro) e n_linhas sai 12 (as células, não os meses).
  perform teste_assert_fat(v_soma = 14379150.46,
    'três meses somam o faturamento REAL, não o dobro (a coluna "Total" não entra junto das categorias)',
    format('soma=%s (esperado 14379150.46; o dobro seria 28758300.92)', v_soma));
  perform teste_assert_fat(v_n = 3,
    'e `n_linhas` conta MESES, não células — é ele que vira "%s meses de faturamento" na mensagem',
    format('n_linhas=%s (esperado 3; contando célula a célula seriam 12)', v_n));

  raise notice '--- 2. o formato de UM valor por mês (book-vertentes) não mudou ---';
  v_r := fn_registrar_documento(v_caso, 'SEM COLUNAS LTDA', 'ano', '2024',
    'FATURAMENTO_24M', 0.99, 'nome_arquivo', 'supabase_storage', 's/fatsimples.pdf',
    'FAT SIMPLES 2024.pdf', true, 'HASH-FAT-POR-MES-2', 'ok');
  v_ver := (v_r->>'documento_versao_id')::uuid;
  perform fn_registrar_campos_extraidos(v_ver, jsonb_build_array(
    jsonb_build_object('ordem',0,'chave','Faturamento Janeiro 2024','valor_num','1000',
                       'unidade','unidade','moeda','BRL','confianca','0.99'),
    jsonb_build_object('ordem',1,'chave','Faturamento Fevereiro 2024','valor_num','2000',
                       'unidade','unidade','moeda','BRL','confianca','0.99'),
    jsonb_build_object('ordem',2,'chave','Faturamento Março 2024','valor_num','3000',
                       'unidade','unidade','moeda','BRL','confianca','0.99')
  ), 'N2');

  select soma, n_linhas into v_soma, v_n from fn_somar_faturamento_ano(v_ver, '2024', '24');
  perform teste_assert_fat(v_soma = 6000 and v_n = 3,
    'um valor por mês, sem periodo_coluna nenhum: soma os três e conta três',
    format('soma=%s, n_linhas=%s (esperado 6000 / 3)', v_soma, v_n));

  raise notice '--- 3. quebra por categoria SEM coluna de total: soma as categorias ---';
  -- O caso intermediário, e ele é o contrapositivo da regra "se tem total, ele
  -- manda": aqui NÃO tem, e as três categorias precisam somar. Sem este bloco,
  -- a correção poderia ter virado "ignore tudo que não for a coluna Total" e
  -- este formato zeraria em silêncio.
  v_r := fn_registrar_documento(v_caso, 'SEM TOTAL LTDA', 'ano', '2024',
    'FATURAMENTO_24M', 0.99, 'nome_arquivo', 'supabase_storage', 's/fatsemtotal.pdf',
    'FAT SEM TOTAL 2024.pdf', true, 'HASH-FAT-POR-MES-3', 'ok');
  v_ver := (v_r->>'documento_versao_id')::uuid;
  perform fn_registrar_campos_extraidos(v_ver, jsonb_build_array(
    jsonb_build_object('ordem',0,'chave','Janeiro 2024','periodo_coluna','Saídas R$',
                       'valor_num','700','unidade','unidade','moeda','BRL','confianca','0.99'),
    jsonb_build_object('ordem',1,'chave','Janeiro 2024','periodo_coluna','Serviços R$',
                       'valor_num','300','unidade','unidade','moeda','BRL','confianca','0.99')
  ), 'N2');

  select soma, n_linhas into v_soma, v_n from fn_somar_faturamento_ano(v_ver, '2024', '24');
  perform teste_assert_fat(v_soma = 1000 and v_n = 1,
    'sem coluna de total, as categorias do mês somam — a regra não virou "só conta o total"',
    format('soma=%s, n_linhas=%s (esperado 1000 / 1)', v_soma, v_n));

  raise notice 'FATURAMENTO POR MÊS OK — a categoria mora na coluna, e o mês é a unidade';
end $$;
