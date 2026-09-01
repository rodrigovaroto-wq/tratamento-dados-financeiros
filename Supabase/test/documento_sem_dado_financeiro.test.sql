-- Testes de "certidão sem número não é extração falha" (Supabase/migrations/0111).
-- Rodar via Supabase/test/run.sh (que aplica as migrations antes).
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

-- =============================================================================
-- 0112 — a conferência de FORA: documento que o pipeline PULOU é denunciado.
--
-- Este é o modo de falha que nenhuma das três camadas de cobertura podia ver,
-- porque as três medem o que voltou de uma chamada FEITA. No "Teste V45" 19 de 35
-- documentos nunca tiveram a extração chamada, e o checklist ficou verde.
-- =============================================================================
create or replace function teste_assert_lote(p_ok boolean, p_nome text, p_detalhe text default null)
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
  raise notice '--- 6. documento registrado e NUNCA extraído é denunciado ---';
  v_caso := (fn_upsert_caso('Caso com documento pulado'))::uuid;

  -- Documento A: extração ACONTECEU (trouxe linha).
  v_r := fn_registrar_documento(
    v_caso, 'Pulada Ltda.', 'anual', '2025', 'BALANCO', 0.95, 'nome_arquivo',
    'supabase_storage', 'bucket/a.pdf', 'A_extraido.pdf', true, 'HASH-A', 'ok');
  perform fn_registrar_campos_extraidos((v_r->>'documento_versao_id')::uuid, jsonb_build_array(
    jsonb_build_object('ordem', 0, 'chave', 'Caixa', 'valor_num', '10', 'confianca', '0.9')
  ), 'N0', null);

  -- Documento B: registrado e o pipeline NUNCA chamou a extração — nada de
  -- fn_registrar_campos_extraidos. É o caso do V45, reproduzido.
  v_r := fn_registrar_documento(
    v_caso, 'Pulada Ltda.', 'anual', '2025', 'DRE', 0.95, 'nome_arquivo',
    'supabase_storage', 'bucket/b.pdf', 'B_pulado.pdf', true, 'HASH-B', 'ok');
  v_ver := (v_r->>'documento_versao_id')::uuid;

  -- ANTES da conferência: nenhuma pendência acusa o documento B. É o ponto do
  -- teste — as guardas de extração não veem o que não passou por elas.
  select count(*) into v_n from pendencia
    where caso_id = v_caso and tipo = 'extracao_falhou' and estado <> 'resolvida';
  perform teste_assert_lote(v_n = 0,
    'nenhuma guarda de extração acusou o documento pulado (é por isso que a 0112 existe)');

  v_r := fn_conferir_lote(v_caso);
  perform teste_assert_lote((v_r->>'documentos_no_caso')::int = 2, 'a conferência vê os 2 documentos', v_r::text);
  perform teste_assert_lote((v_r->>'documentos_nao_extraidos')::int = 1,
    'e nomeia UM como não extraído', v_r::text);
  perform teste_assert_lote((v_r->>'lote_integro') = 'false', 'o lote NÃO está íntegro', v_r::text);
  perform teste_assert_lote(v_r->'nomes_nao_extraidos' @> '["B_pulado.pdf"]'::jsonb,
    'e diz QUAL arquivo ficou de fora', v_r::text);

  select count(*) into v_n from pendencia
    where caso_id = v_caso and tipo = 'documento_nao_extraido' and estado <> 'resolvida'
      and severidade = 'bloqueante' and sobrepujavel = false;
  perform teste_assert_lote(v_n = 1,
    'pendência BLOQUEANTE e não-sobrepujável, uma por documento', format('encontradas: %s', v_n));

  raise notice '--- 7. idempotente, e auto-resolve quando o documento é reprocessado ---';
  v_r := fn_conferir_lote(v_caso);
  select count(*) into v_n from pendencia
    where caso_id = v_caso and tipo = 'documento_nao_extraido' and estado <> 'resolvida';
  perform teste_assert_lote(v_n = 1, 'rodar duas vezes não duplica a pendência');

  -- O reprocessamento do B: agora a extração acontece (mesmo trazendo zero linha,
  -- o que é legítimo — o que importa é que a CHAMADA existiu).
  perform fn_registrar_campos_extraidos(v_ver, '[]'::jsonb, 'N0', null, false);
  v_r := fn_conferir_lote(v_caso);
  perform teste_assert_lote((v_r->>'lote_integro') = 'true',
    'com a extração chamada, o lote fica íntegro', v_r::text);
  select count(*) into v_n from pendencia
    where caso_id = v_caso and tipo = 'documento_nao_extraido' and estado <> 'resolvida';
  perform teste_assert_lote(v_n = 0, 'e a pendência se resolve sozinha');

  raise notice '--- 8. caso inexistente é RECUSA retornada, não exceção ---';
  v_r := fn_conferir_lote('00000000-0000-0000-0000-000000000000'::uuid);
  perform teste_assert_lote((v_r->>'recusado') = 'true', 'caso inexistente devolve recusa no payload', v_r::text);

  raise notice 'TODOS OS TESTES DA CONFERENCIA DE LOTE PASSARAM';
end $$;

drop function teste_assert_lote(boolean, text, text);
