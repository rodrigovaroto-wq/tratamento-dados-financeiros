-- Testes de "certidão sem número não é extração falha" (db/migrations/0111).
-- Rodar via db/test/run.sh (que aplica as migrations antes).
--
-- O QUE ESTE ARQUIVO PROVA: o Sinal 3 de `fn_registrar_campos_extraidos`
-- ("a chamada respondeu vazia") só abre `extracao_falhou` quando ninguém disse
-- o contrário. `p_tem_dado_financeiro = false` — vindo do diagnóstico da
-- própria chamada de extração — é o único jeito de silenciar a guarda; `null`
-- (chamador antigo, workflow não reimportado) mantém o comportamento de
-- SEMPRE, para não mudar nada debaixo de quem não reimportou.
--
-- CERTIDOES é 'complementar' na taxonomia (não entra no Kit Básico), então o
-- cenário isola o Sinal 3 sem a pendência `item_sem_conteudo` (0036, que só
-- vale para obrigatório) misturada no resultado.

\set ON_ERROR_STOP on

create or replace function teste_assert_sdf(p_ok boolean, p_nome text, p_detalhe text default null)
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
  v_ver  uuid;
  v_n    int;
begin
  raise notice '--- 1. zero linhas + tem_dado_financeiro=false: NÃO abre extracao_falhou ---';
  v_caso := (fn_upsert_caso('Caso certidão sem dado'))::uuid;

  v_r := fn_registrar_documento(
    v_caso, 'Grupo Canastra', 'caso', 'vigente', 'CERTIDOES', 0.9, 'nome_arquivo',
    'supabase_storage', 'bucket/certidoes.pdf', '30_Certidoes_Negativas_Grupo_Canastra.pdf',
    true, 'HASH-CERTIDOES', 'ok');
  v_ver := (v_r->>'documento_versao_id')::uuid;

  perform fn_registrar_campos_extraidos(v_ver, '[]'::jsonb, 'N0', null, false);

  select count(*) into v_n from pendencia
    where caso_id = v_caso and tipo = 'extracao_falhou' and estado <> 'resolvida';
  perform teste_assert_sdf(v_n = 0,
    'certidão com zero linhas e tem_dado_financeiro=false não abre extracao_falhou',
    format('encontradas: %s', v_n));

  raise notice '--- 2. zero linhas + tem_dado_financeiro=null (chamador antigo): abre, como sempre ---';
  v_caso := (fn_upsert_caso('Caso balanço vazio, workflow velho'))::uuid;

  v_r := fn_registrar_documento(
    v_caso, 'Vazia Ltda.', 'anual', '2025', 'BALANCO', 0.95, 'nome_arquivo',
    'supabase_storage', 'bucket/bp.xlsx', 'BP Vazia 2025.xlsx', true, 'HASH-VAZIO-NULL', 'ok');
  v_ver := (v_r->>'documento_versao_id')::uuid;

  -- Chamada com a assinatura de 4 argumentos (workflow ainda não reimportado):
  -- `p_tem_dado_financeiro` fica no default, que é `null`.
  perform fn_registrar_campos_extraidos(v_ver, '[]'::jsonb, 'N0', null);

  select count(*) into v_n from pendencia
    where caso_id = v_caso and tipo = 'extracao_falhou' and estado <> 'resolvida';
  perform teste_assert_sdf(v_n = 1,
    'chamador que não manda o sinal continua com o comportamento de sempre (falha)',
    format('encontradas: %s', v_n));

  raise notice '--- 3. zero linhas + tem_dado_financeiro=true: continua sinal de falha real ---';
  v_caso := (fn_upsert_caso('Caso balanço vazio, IA diz que deveria ter dado'))::uuid;

  v_r := fn_registrar_documento(
    v_caso, 'Vazia Ltda.', 'anual', '2025', 'BALANCO', 0.95, 'nome_arquivo',
    'supabase_storage', 'bucket/bp.pdf', 'BP Vazia 2025.pdf', true, 'HASH-VAZIO-TRUE', 'ok');
  v_ver := (v_r->>'documento_versao_id')::uuid;

  perform fn_registrar_campos_extraidos(v_ver, '[]'::jsonb, 'N0', null, true);

  select count(*) into v_n from pendencia
    where caso_id = v_caso and tipo = 'extracao_falhou' and estado <> 'resolvida';
  perform teste_assert_sdf(v_n = 1,
    'balanço (deveria ter linha) com zero linhas continua abrindo extracao_falhou',
    format('encontradas: %s', v_n));

  raise notice '--- 4. p_falha_motivo continua mandando, mesmo com tem_dado_financeiro=false ---';
  -- A CHAMADA em si falhou (JSON truncado, erro de API) — isso não é o mesmo
  -- caso do item 1, e o motivo explícito nunca pode ser silenciado pelo sinal.
  v_caso := (fn_upsert_caso('Caso chamada truncada'))::uuid;

  v_r := fn_registrar_documento(
    v_caso, 'Grupo Canastra', 'caso', 'vigente', 'CERTIDOES', 0.9, 'nome_arquivo',
    'supabase_storage', 'bucket/certidoes2.pdf', 'certidoes2.pdf', true, 'HASH-CERTIDOES-2', 'ok');
  v_ver := (v_r->>'documento_versao_id')::uuid;

  perform fn_registrar_campos_extraidos(v_ver, '[]'::jsonb, 'N0',
    'Resposta da OpenAI truncada por limite de tokens de saida (finish_reason=length).', false);

  select count(*) into v_n from pendencia
    where caso_id = v_caso and tipo = 'extracao_falhou' and estado <> 'resolvida';
  perform teste_assert_sdf(v_n = 1,
    'p_falha_motivo explícito abre a pendência mesmo com tem_dado_financeiro=false',
    format('encontradas: %s', v_n));

  raise notice '--- 5. reprocessar o MESMO documento com dado de verdade resolve a pendência antiga ---';
  -- (a pendência é por documento_id, e um reenvio com HASH DIFERENTE cria um
  -- documento NOVO — 0026 — então quem prova o auto-resolve é reprocessar a
  -- MESMA documento_versao_id, como um retry da mesma chamada faria.)
  v_caso := (fn_upsert_caso('Caso reprocessado com dado'))::uuid;

  v_r := fn_registrar_documento(
    v_caso, 'Vazia Ltda.', 'anual', '2025', 'BALANCO', 0.95, 'nome_arquivo',
    'supabase_storage', 'bucket/bp3.xlsx', 'BP.xlsx', true, 'HASH-REEXTRAI', 'ok');
  v_ver := (v_r->>'documento_versao_id')::uuid;
  perform fn_registrar_campos_extraidos(v_ver, '[]'::jsonb, 'N0', null);

  select count(*) into v_n from pendencia
    where caso_id = v_caso and tipo = 'extracao_falhou' and estado <> 'resolvida';
  perform teste_assert_sdf(v_n = 1, 'a pendência abriu na primeira tentativa vazia');

  perform fn_registrar_campos_extraidos(v_ver, jsonb_build_array(
    jsonb_build_object('ordem', 0, 'chave', 'Caixa e equivalentes', 'valor_texto', '1.200',
                       'valor_num', '1200', 'unidade', 'milhar', 'moeda', 'BRL', 'confianca', '0.9',
                       'secao_canonica', 'ativo_circulante')
  ), 'N0', null);

  select count(*) into v_n from pendencia
    where caso_id = v_caso and tipo = 'extracao_falhou' and estado <> 'resolvida';
  perform teste_assert_sdf(v_n = 0, 'reprocessar com conteúdo resolve a pendência antiga automaticamente');

  raise notice 'TODOS OS TESTES DE DOCUMENTO SEM DADO FINANCEIRO PASSARAM';
end $$;

drop function teste_assert_sdf(boolean, text, text);
