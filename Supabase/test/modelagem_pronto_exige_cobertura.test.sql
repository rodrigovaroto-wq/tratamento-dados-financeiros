-- =============================================================================
-- O "PRONTO" DA MODELAGEM EXIGE COBERTURA, NÃO SÓ PARÂMETRO (0158)
--
-- O defeito medido em produção (Grupo Vertentes): parâmetros definidos, 6
-- premissas ativas com valor, vínculo em lote de 5 seções — `pronto = true`
-- com 23 de 480 linhas projetáveis cobertas. A condição da 0134 (parâmetros +
-- premissa ativa + nenhuma sem valor) nunca perguntava se ALGUMA linha real
-- do caso tinha sido vinculada — um caso com zero vínculo real, só
-- configuração órfã apontando para rótulo que não existe, já respondia
-- "pronto" antes desta migration.
--
-- O que este arquivo prova, em ordem:
--   1. parâmetros definidos e NENHUMA premissa ativa → pronto = false (regra
--      da 0134, intacta).
--   2. parâmetros + premissa com valor + UMA linha real vinculada → pronto =
--      true, e a fração nova reflete 1 de 4 — SEM contar subtotal, série
--      mensal nem derivado no denominador.
--   3. O CASO QUE A 0158 EXISTE PARA FECHAR: só vínculo ÓRFÃO (aponta para
--      rótulo que não existe no caso) → zero linha real coberta → pronto =
--      false, mesmo com premissa ativa e com valor.
--   4. vínculo órfão AO LADO de um vínculo real não bloqueia — órfão informa,
--      não impede (mesma decisão que a 0134 já toma para
--      sazonalidade_sem_curva, e pelo mesmo motivo: não deixa nenhum número
--      do book errado).
--   5. premissa ativa SEM valor continua bloqueando (guarda de regressão da
--      0134): a 0158 acrescenta uma condição, não remove as que já existiam.
-- =============================================================================

\set ON_ERROR_STOP on

create or replace function teste_assert_pc(p_ok boolean, p_nome text, p_detalhe text default null)
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
  v_caso  uuid;
  v_doc   jsonb;
  v_ver   uuid;
  v_conf  jsonb;
begin
  v_caso := (fn_upsert_caso('Caso pronto exige cobertura 0158 ' || clock_timestamp()::text))::uuid;

  -- 4 contas + 1 subtotal + 1 derivado, no mesmo documento — os padrões que
  -- fn_papel_linha já reconhece por estrutura (0034/0042), os mesmos do
  -- fixture v35.
  v_doc := fn_registrar_documento(v_caso, 'COBERTURA LTDA.', 'anual', '2025', 'BALANCO', 0.95,
    'nome_arquivo', 'supabase_storage', 'cob/balanco.pdf', 'Balanço 2025.pdf', true,
    'HASH-COBERTURA-BALANCO', 'ok');
  v_ver := (v_doc->>'documento_versao_id')::uuid;
  perform fn_registrar_campos_extraidos(v_ver, jsonb_build_array(
    jsonb_build_object('ordem', 0, 'chave', 'Caixa', 'valor_num', '100',
      'unidade', 'milhar', 'moeda', 'BRL', 'confianca', '0.95', 'secao_canonica', 'ativo_circulante'),
    jsonb_build_object('ordem', 1, 'chave', 'Contas a receber', 'valor_num', '200',
      'unidade', 'milhar', 'moeda', 'BRL', 'confianca', '0.95', 'secao_canonica', 'ativo_circulante'),
    jsonb_build_object('ordem', 2, 'chave', 'Estoques', 'valor_num', '300',
      'unidade', 'milhar', 'moeda', 'BRL', 'confianca', '0.95', 'secao_canonica', 'ativo_circulante'),
    jsonb_build_object('ordem', 3, 'chave', 'Fornecedores', 'valor_num', '150',
      'unidade', 'milhar', 'moeda', 'BRL', 'confianca', '0.95', 'secao_canonica', 'passivo_circulante'),
    jsonb_build_object('ordem', 4, 'chave', 'TOTAL DO ATIVO', 'valor_num', '600',
      'unidade', 'milhar', 'moeda', 'BRL', 'confianca', '0.95', 'secao_canonica', null),
    jsonb_build_object('ordem', 5, 'chave', 'Índice de liquidez corrente', 'valor_num', '1.5',
      'unidade', 'milhar', 'moeda', 'BRL', 'confianca', '0.95', 'secao_canonica', null)
  ));

  perform teste_assert_pc(
    (select count(*) from fn_linhas_para_modelagem(v_caso) where papel = 'conta') = 4,
    'a fixture tem 4 linhas projetáveis (conta)');
  perform teste_assert_pc(
    (select count(*) from fn_linhas_para_modelagem(v_caso) where papel = 'subtotal') = 1
      and (select count(*) from fn_linhas_para_modelagem(v_caso) where papel = 'derivado') = 1,
    'e 1 subtotal + 1 derivado, que NÃO podem entrar no denominador da fração');

  perform fn_definir_modelagem(v_caso, 'COBERTURA LTDA.', 2025, 'IPCA', 'industria', 'teste-0158', 5);

  raise notice '--- 1. parâmetros definidos, NENHUMA premissa ativa → pronto = false ---';
  v_conf := fn_conferir_modelagem(v_caso);
  perform teste_assert_pc((v_conf->>'pronto') = 'false',
    'sem premissa ativa nenhuma, o caso não está pronto (regra da 0134)', v_conf::text);
  perform teste_assert_pc((v_conf->>'linhas_do_caso')::int = 4,
    'linhas_do_caso conta só as 4 contas — não as 6 linhas totais do documento', v_conf::text);
  perform teste_assert_pc((v_conf->>'fracao_linhas_com_premissa')::numeric = 0,
    'a fração é 0 (zero real, não ausência) quando não há vínculo nenhum ainda', v_conf::text);

  raise notice '--- 2. premissa com valor + 1 linha REAL vinculada → pronto = true ---';
  perform fn_ativar_premissa(v_caso, 'CRESC_REAL', '{"2026": 0.05}'::jsonb, 'digitado', 'teste-0158');
  perform fn_vincular_linha_premissa(v_caso, 'ativo_circulante', 'Caixa', null, 'CRESC_REAL', 'teste-0158');

  v_conf := fn_conferir_modelagem(v_caso);
  perform teste_assert_pc((v_conf->>'pronto') = 'true',
    'com 1 linha real coberta, parâmetros definidos e premissa com valor, o caso está pronto',
    v_conf::text);
  perform teste_assert_pc((v_conf->>'linhas_com_premissa')::int = 1, 'exatamente 1 linha coberta', v_conf::text);
  perform teste_assert_pc((v_conf->>'fracao_linhas_com_premissa')::numeric = 0.25,
    'a fração é 1/4 = 0,25 — sobre as 4 CONTAS, não sobre as 6 linhas do documento '
    '(seria 1/6 se subtotal e derivado entrassem no denominador, que é o erro que este teste barra)',
    v_conf::text);

  raise notice '--- 3. O DEFEITO DA 0158: só vínculo ÓRFÃO, zero linha real → pronto = false ---';
  -- Remove o vínculo real e deixa só um vínculo apontando para um rótulo que
  -- não existe no caso. ANTES da 0158, isto passava: parâmetros definidos +
  -- premissa ativa com valor bastavam, e "linhas_com_premissa" nunca entrava
  -- na conta do "pronto".
  delete from caso_linha_premissa
   where caso_id = v_caso and rotulo_norm = fn_normalizar_texto('Caixa');
  perform fn_vincular_linha_premissa(v_caso, 'ativo_circulante', 'Linha Fantasma Que Nao Existe',
    null, 'CRESC_REAL', 'teste-0158');

  v_conf := fn_conferir_modelagem(v_caso);
  perform teste_assert_pc((v_conf->>'linhas_com_premissa')::int = 0,
    'zero linha real está vinculada agora (o único vínculo é órfão)', v_conf::text);
  perform teste_assert_pc((v_conf->'vinculos_orfaos') @> to_jsonb(fn_normalizar_texto('Linha Fantasma Que Nao Existe')),
    'e o vínculo órfão é NOMEADO', v_conf->>'vinculos_orfaos');
  perform teste_assert_pc((v_conf->>'premissas_ativas')::int > 0
    and (v_conf->'premissas_sem_valor') = '[]'::jsonb,
    'premissa ativa e COM valor — as três condições da 0134 sozinhas diriam "pronto"', v_conf::text);
  perform teste_assert_pc((v_conf->>'pronto') = 'false',
    'e mesmo assim NÃO está pronto — zero cobertura real, que é o defeito que a 0158 fecha',
    v_conf::text);
  perform teste_assert_pc((v_conf->>'fracao_linhas_com_premissa')::numeric = 0,
    'a fração confirma: 0 de 4', v_conf::text);

  raise notice '--- 4. vínculo órfão AO LADO de um vínculo real NÃO bloqueia (órfão informa) ---';
  perform fn_vincular_linha_premissa(v_caso, 'ativo_circulante', 'Caixa', null, 'CRESC_REAL', 'teste-0158');
  v_conf := fn_conferir_modelagem(v_caso);
  perform teste_assert_pc((v_conf->>'linhas_com_premissa')::int = 1, 'a linha real voltou a contar', v_conf::text);
  perform teste_assert_pc(jsonb_array_length(v_conf->'vinculos_orfaos') > 0,
    'o órfão da etapa 3 continua lá, nomeado', v_conf->>'vinculos_orfaos');
  perform teste_assert_pc((v_conf->>'pronto') = 'true',
    'e o caso está pronto de novo — vínculo órfão INFORMA, não bloqueia (mesmo desenho da '
    'sazonalidade_sem_curva da 0134: não deixa nenhum número do book errado)', v_conf::text);

  raise notice '--- 5. premissa ativa SEM valor continua bloqueando (guarda de regressão da 0134) ---';
  perform fn_ativar_premissa(v_caso, 'SGA_PCT', '{}'::jsonb, 'digitado', 'teste-0158');
  v_conf := fn_conferir_modelagem(v_caso);
  perform teste_assert_pc((v_conf->'premissas_sem_valor') @> '["SGA_PCT"]'::jsonb,
    'SGA_PCT ativa sem valor é nomeada', v_conf::text);
  perform teste_assert_pc((v_conf->>'pronto') = 'false',
    'e ela sozinha derruba o "pronto" mesmo com linha real coberta — a 0158 ACRESCENTA uma '
    'condição, não substitui as da 0134', v_conf::text);
end $$;

do $$ begin raise notice 'TODOS OS TESTES DO PRONTO-EXIGE-COBERTURA (0158) PASSARAM'; end $$;

drop function teste_assert_pc(boolean, text, text);
