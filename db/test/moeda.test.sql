-- Testes da moeda por linha (db/migrations/0035).
-- Rodar via db/test/run.sh (que aplica as migrations antes).
--
-- A propriedade que estes testes travam: **a moeda que a extração declara chega
-- ao banco, linha por linha, e nunca é presumida**. Item 2 do §7.4 do material
-- de Onboarding — `moeda` era normalizada no nó e jogada fora por não haver
-- coluna, e o book somava USD com BRL como se fossem a mesma grandeza. Com o
-- erro de escala de ~496× já corrigido, era o último fator multiplicativo
-- invisível do pipeline: erra pelo câmbio inteiro, num arquivo que fecha.
--
-- Por que testar isto no BANCO e não só na lib: a lib prova que o nó calcula a
-- moeda; só o banco prova que ela sobrevive ao INSERT. O gap entre "a função
-- calcula" e "a coluna recebe" é exatamente onde este dado morreu por meses.

\set ON_ERROR_STOP on

create or replace function teste_assert_moeda(p_ok boolean, p_nome text, p_detalhe text default null)
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
  v_r jsonb;
  v_ver uuid;
  v_n int;
  v_txt text;
begin
  raise notice '--- 1. a moeda declarada por linha chega à coluna ---';
  v_caso := (fn_upsert_caso('Caso moeda'))::uuid;
  v_r := fn_registrar_documento(
    v_caso, 'Export Co Ltda.', 'anual', '2025', 'DRE', 0.95, 'nome_arquivo',
    'supabase_storage', 'bucket/dre-usd.pdf', 'DRE Export Co 2025 (USD).pdf', true, 'HASH-USD', 'ok');
  v_ver := (v_r->>'documento_versao_id')::uuid;

  perform fn_registrar_campos_extraidos(v_ver, jsonb_build_array(
    jsonb_build_object('ordem', 0, 'chave', 'Receita de exportação', 'valor_texto', '2.400',
                       'valor_num', '2400', 'unidade', 'milhar', 'moeda', 'USD', 'confianca', '0.97',
                       'secao_canonica', 'receita_bruta'),
    jsonb_build_object('ordem', 1, 'chave', 'Custo dos produtos vendidos', 'valor_texto', '(1.500)',
                       'valor_num', '-1500', 'unidade', 'milhar', 'moeda', 'USD', 'confianca', '0.96',
                       'secao_canonica', 'custos')
  ));

  select count(*) into v_n from campo_extraido where documento_versao_id = v_ver and moeda = 'USD';
  perform teste_assert_moeda(v_n = 2, 'as duas linhas em USD gravaram moeda USD',
    format('esperado 2, veio %s', v_n));

  select count(*) into v_n from campo_extraido where documento_versao_id = v_ver and moeda is null;
  perform teste_assert_moeda(v_n = 0, 'nenhuma linha perdeu a moeda no caminho');

  raise notice '--- 2. escala e moeda são coisas SEPARADAS na mesma linha ---';
  -- O comentário da 0005 dizia `unidade text -- ex.: BRL, milhares`, confundindo
  -- as duas numa coluna só. Se voltarem a se confundir, um documento "em milhares
  -- de dólares" perde uma das duas informações — e as duas são multiplicativas.
  select unidade || '/' || moeda into v_txt from campo_extraido
    where documento_versao_id = v_ver and chave = 'Receita de exportação';
  perform teste_assert_moeda(v_txt = 'milhar/USD',
    'a mesma linha carrega escala (milhar) E moeda (USD)', coalesce(v_txt, '(null)'));

  raise notice '--- 3. moeda ausente fica NULL — nunca BRL presumido ---';
  v_r := fn_registrar_documento(
    v_caso, 'Sem Moeda Ltda.', 'anual', '2025', 'BALANCO', 0.95, 'nome_arquivo',
    'supabase_storage', 'bucket/bp.pdf', 'BP Sem Moeda 2025.pdf', true, 'HASH-SEMMOEDA', 'ok');
  v_ver := (v_r->>'documento_versao_id')::uuid;

  perform fn_registrar_campos_extraidos(v_ver, jsonb_build_array(
    jsonb_build_object('ordem', 0, 'chave', 'Caixa e equivalentes', 'valor_texto', '100',
                       'valor_num', '100', 'unidade', 'milhar', 'confianca', '0.9',
                       'secao_canonica', 'ativo_circulante')
  ));

  select moeda into v_txt from campo_extraido where documento_versao_id = v_ver;
  perform teste_assert_moeda(v_txt is null,
    'documento sem moeda declarada grava NULL (desconhecida), não um palpite',
    coalesce(v_txt, '(null)'));

  raise notice '--- 4. duas moedas coexistem no MESMO caso sem se misturar ---';
  -- É o cenário real que motivou o item: subsidiária exportadora em USD ao lado
  -- das operações em BRL, no mesmo mandato. Antes da 0035 as linhas eram
  -- indistinguíveis; o export somava e o book fechava errado por ~5x.
  v_r := fn_registrar_documento(
    v_caso, 'Operação BR Ltda.', 'anual', '2025', 'DRE', 0.95, 'nome_arquivo',
    'supabase_storage', 'bucket/dre-brl.pdf', 'DRE Operacao BR 2025.pdf', true, 'HASH-BRL', 'ok');
  v_ver := (v_r->>'documento_versao_id')::uuid;

  perform fn_registrar_campos_extraidos(v_ver, jsonb_build_array(
    -- MESMO valor numérico da linha em USD acima, de propósito: sem a coluna de
    -- moeda, estas duas linhas são a mesma coisa para qualquer soma.
    jsonb_build_object('ordem', 0, 'chave', 'Receita líquida', 'valor_texto', '2.400',
                       'valor_num', '2400', 'unidade', 'milhar', 'moeda', 'BRL', 'confianca', '0.97',
                       'secao_canonica', 'receita_bruta')
  ));

  select count(distinct moeda) into v_n
    from campo_extraido ce
    join documento_versao dv on dv.id = ce.documento_versao_id
    join documento d on d.id = dv.documento_id
    where d.caso_id = v_caso and ce.moeda is not null;
  perform teste_assert_moeda(v_n = 2,
    'o caso tem DUAS moedas distintas registradas, e dá para saber disso por consulta',
    format('moedas distintas: %s', v_n));

  select count(*) into v_n
    from campo_extraido ce
    join documento_versao dv on dv.id = ce.documento_versao_id
    join documento d on d.id = dv.documento_id
    where d.caso_id = v_caso and ce.valor_num = 2400;
  perform teste_assert_moeda(v_n = 2,
    'as duas linhas de 2400 existem — o que as distingue é SÓ a moeda',
    format('linhas com 2400: %s', v_n));

  raise notice 'TODOS OS TESTES DE MOEDA PASSARAM';
end $$;
