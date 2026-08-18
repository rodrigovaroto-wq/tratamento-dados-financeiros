-- Testes de "linha exigida por tipo de documento" (db/migrations/0113).
-- Rodar via db/test/run.sh (que aplica as migrations antes).
--
-- As propriedades travadas:
--
--   #1  balanço COMPLETO (Ativo, Passivo+PL, Caixa) não abre pendência;
--   #2  balanço no formato "sem a palavra total" ("ATIVO", "PASSIVO E
--       PATRIMÔNIO LÍQUIDO", "Disponibilidades") TAMBÉM não abre — a lição da
--       0034 vale para a exigência (localizadores estrutural/alternativos);
--   #3  balanço COM linhas mas SEM caixa abre pendência que NOMEIA a linha e o
--       depende_de, com o peso default (importante, sobrepujável);
--   #4  a linha aparece numa extração nova → a pendência resolve SOZINHA;
--   #5  documento VAZIO não abre linha_exigida (já é item_sem_conteudo da
--       0036) — sem dupla cobrança;
--   #6  exigência de origem 'proposta' (MUTUOS) cobra e se declara proposta;
--   #7  política do dono (bloqueante/não-sobrepujável) vale por linha e
--       PROPAGA para pendência já aberta;
--   #8  idempotência: recomputar de novo não duplica;
--   #9  a checagem só LÊ campo_extraido.
--
-- 0119: BALANCO passou a ser cobrado POR ENTIDADE, e o motivo ganhou o sufixo
-- da entidade. Os asserts daqui casam por PREFIXO de propósito: este arquivo
-- trava as propriedades da 0113 (existe, nomeia, resolve, política), e a
-- granularidade é travada em db/test/linha_exigida_entidade.test.sql.
--
-- Os cenários passam pela COSTURA real (registrar → extrair → recomputar),
-- como o teste da 0036: escrever o estado final na mão passaria com o defeito
-- ligado.

\set ON_ERROR_STOP on

create or replace function teste_assert_le(p_ok boolean, p_nome text, p_detalhe text default null)
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
  v_n_campos int;
  v_txt text;
  v_sev text;
  v_sobre boolean;
begin
  raise notice '--- 1. balanço completo: nenhuma pendência de linha exigida ---';
  v_caso := (fn_upsert_caso('Caso linha exigida — completo'))::uuid;
  v_r := fn_registrar_documento(
    v_caso, 'Completa Ltda.', 'anual', '2025', 'BALANCO', 0.9, 'nome_arquivo',
    'supabase_storage', 'bucket/bp-completo.pdf', 'BP Completa 2025.pdf', true, 'HASH-LE-1', 'ok');
  v_ver := (v_r->>'documento_versao_id')::uuid;
  perform fn_registrar_campos_extraidos(v_ver, '[
    {"chave": "TOTAL DO ATIVO",                              "valor_num": "1000", "confianca": "0.9", "secao": "Ativo",    "secao_canonica": "ativo_circulante"},
    {"chave": "TOTAL DO PASSIVO E DO PATRIMONIO LIQUIDO",    "valor_num": "1000", "confianca": "0.9", "secao": "Passivo",  "secao_canonica": "passivo_circulante"},
    {"chave": "Caixa e equivalentes de caixa",               "valor_num": "200",  "confianca": "0.9", "secao": "Ativo Circulante", "secao_canonica": "ativo_circulante"},
    {"chave": "Estoques",                                    "valor_num": "300",  "confianca": "0.9", "secao": "Ativo Circulante", "secao_canonica": "ativo_circulante"}
  ]'::jsonb, 'N0');

  select count(*) into v_n from pendencia
    where caso_id = v_caso and tipo = 'linha_exigida_ausente' and estado <> 'resolvida'
      and motivo like 'completude:linha_exigida:BALANCO:%';
  perform teste_assert_le(v_n = 0,
    'balanço com Ativo, Passivo+PL e Caixa não abre pendência', 'abriu ' || v_n);

  raise notice '--- 2. balanço SEM a palavra "total" também satisfaz (lição da 0034) ---';
  v_caso := (fn_upsert_caso('Caso linha exigida — estrutural'))::uuid;
  v_r := fn_registrar_documento(
    v_caso, 'Estrutural S.A.', 'anual', '2025', 'BALANCO', 0.9, 'nome_arquivo',
    'supabase_storage', 'bucket/bp-estrutural.pdf', 'BP Estrutural 2025.pdf', true, 'HASH-LE-2', 'ok');
  v_ver := (v_r->>'documento_versao_id')::uuid;
  perform fn_registrar_campos_extraidos(v_ver, '[
    {"chave": "ATIVO",                          "valor_num": "5000", "confianca": "0.9"},
    {"chave": "PASSIVO E PATRIMONIO LIQUIDO",   "valor_num": "5000", "confianca": "0.9"},
    {"chave": "Disponibilidades",               "valor_num": "700",  "confianca": "0.9"}
  ]'::jsonb, 'N0');

  select count(*) into v_n from pendencia
    where caso_id = v_caso and tipo = 'linha_exigida_ausente' and estado <> 'resolvida'
      and motivo like 'completude:linha_exigida:BALANCO:%';
  perform teste_assert_le(v_n = 0,
    'rótulos "ATIVO"/"PASSIVO E PL"/"Disponibilidades" satisfazem pelos localizadores alternativos',
    'abriu ' || v_n);

  raise notice '--- 3. balanço sem caixa: pendência NOMEIA a linha e o que depende dela ---';
  v_caso := (fn_upsert_caso('Caso linha exigida — sem caixa'))::uuid;
  v_r := fn_registrar_documento(
    v_caso, 'Sem Caixa Ltda.', 'anual', '2025', 'BALANCO', 0.9, 'nome_arquivo',
    'supabase_storage', 'bucket/bp-sem-caixa.pdf', 'BP Sem Caixa 2025.pdf', true, 'HASH-LE-3', 'ok');
  v_ver := (v_r->>'documento_versao_id')::uuid;
  perform fn_registrar_campos_extraidos(v_ver, '[
    {"chave": "TOTAL DO ATIVO",                           "valor_num": "800", "confianca": "0.9"},
    {"chave": "TOTAL DO PASSIVO E DO PATRIMONIO LIQUIDO", "valor_num": "800", "confianca": "0.9"},
    {"chave": "Estoques",                                 "valor_num": "800", "confianca": "0.9"}
  ]'::jsonb, 'N0');

  select count(*), min(descricao), min(severidade::text), bool_and(sobrepujavel)
    into v_n, v_txt, v_sev, v_sobre
  from pendencia
  where caso_id = v_caso and tipo = 'linha_exigida_ausente' and estado <> 'resolvida'
    and motivo like 'completude:linha_exigida:BALANCO:caixa_e_equivalentes%';
  perform teste_assert_le(v_n = 1, 'abre exatamente uma pendência para o caixa ausente', 'achou ' || v_n);
  perform teste_assert_le(v_txt like '%Caixa e equivalentes%',
    'a descrição NOMEIA a linha exigida (doutrina da 0033)', left(v_txt, 120));
  perform teste_assert_le(v_txt like '%caixa_bp_fluxo%',
    'a descrição publica o depende_de (o que deixa de funcionar)', left(v_txt, 120));
  perform teste_assert_le(v_sev = 'importante' and v_sobre,
    'sem decisão do dono, o peso é o de hoje: importante e sobrepujável',
    coalesce(v_sev, 'null') || '/' || coalesce(v_sobre::text, 'null'));

  select count(*) into v_n from pendencia
    where caso_id = v_caso and tipo = 'linha_exigida_ausente' and estado <> 'resolvida'
      and motivo like 'completude:linha_exigida:BALANCO:%'
      and motivo not like 'completude:linha_exigida:BALANCO:caixa_e_equivalentes%';
  perform teste_assert_le(v_n = 0,
    'Ativo e Passivo+PL presentes NÃO são cobrados', 'abriu ' || v_n || ' a mais');

  raise notice '--- 4. a linha chega numa extração nova: a pendência resolve sozinha ---';
  v_r := fn_registrar_documento(
    v_caso, 'Sem Caixa Ltda.', 'anual', '2025', 'BALANCO', 0.9, 'nome_arquivo',
    'supabase_storage', 'bucket/bp-com-caixa.pdf', 'BP Com Caixa 2025.pdf', true, 'HASH-LE-4', 'ok');
  v_ver := (v_r->>'documento_versao_id')::uuid;
  perform fn_registrar_campos_extraidos(v_ver, '[
    {"chave": "TOTAL DO ATIVO",                           "valor_num": "800", "confianca": "0.9"},
    {"chave": "TOTAL DO PASSIVO E DO PATRIMONIO LIQUIDO", "valor_num": "800", "confianca": "0.9"},
    {"chave": "Caixa e equivalentes de caixa",            "valor_num": "50",  "confianca": "0.9"}
  ]'::jsonb, 'N0');

  select count(*) into v_n from pendencia
    where caso_id = v_caso and tipo = 'linha_exigida_ausente' and estado <> 'resolvida'
      and motivo like 'completude:linha_exigida:BALANCO:caixa_e_equivalentes%';
  perform teste_assert_le(v_n = 0, 'a pendência do caixa resolve sozinha quando a linha aparece');
  select count(*) into v_n from pendencia
    where caso_id = v_caso and tipo = 'linha_exigida_ausente' and estado = 'resolvida'
      and resolvida_por = 'sistema:extracao'
      and motivo like 'completude:linha_exigida:BALANCO:caixa_e_equivalentes%';
  perform teste_assert_le(v_n = 1, '…resolvida por sistema:extracao, com rastro', 'achou ' || v_n);

  raise notice '--- 5. documento VAZIO não vira linha exigida (já é item_sem_conteudo) ---';
  v_caso := (fn_upsert_caso('Caso linha exigida — vazio'))::uuid;
  v_r := fn_registrar_documento(
    v_caso, 'Vazia Ltda.', 'anual', '2025', 'BALANCO', 0.9, 'nome_arquivo',
    'supabase_storage', 'bucket/bp-vazio.xlsx', 'BP Vazia 2025.xlsx', true, 'HASH-LE-5', 'ok');
  v_ver := (v_r->>'documento_versao_id')::uuid;
  perform fn_registrar_campos_extraidos(v_ver, '[]'::jsonb, 'N0', 'xlsx nao convertido');

  select count(*) into v_n from pendencia
    where caso_id = v_caso and tipo = 'linha_exigida_ausente' and estado <> 'resolvida';
  perform teste_assert_le(v_n = 0,
    'zero pendência de linha exigida no documento vazio (sem dupla cobrança)', 'abriu ' || v_n);
  select count(*) into v_n from pendencia
    where caso_id = v_caso and tipo = 'item_sem_conteudo' and estado <> 'resolvida';
  perform teste_assert_le(v_n = 1, 'o vazio continua sendo item_sem_conteudo (0036)', 'achou ' || v_n);

  raise notice '--- 6. exigência PROPOSTA (MUTUOS) cobra e se declara proposta ---';
  v_caso := (fn_upsert_caso('Caso linha exigida — mutuos'))::uuid;
  v_r := fn_registrar_documento(
    v_caso, 'Grupo Alfa', 'anual', '2025', 'MUTUOS', 0.9, 'nome_arquivo',
    'supabase_storage', 'bucket/mutuos.pdf', 'Mutuos 2025.pdf', true, 'HASH-LE-6', 'ok');
  v_ver := (v_r->>'documento_versao_id')::uuid;
  -- Linhas com valor, mas nenhuma com "mútuo" no rótulo.
  perform fn_registrar_campos_extraidos(v_ver, '[
    {"chave": "Saldo com controlada Beta", "valor_num": "120", "confianca": "0.9"}
  ]'::jsonb, 'N0');

  select count(*), min(descricao) into v_n, v_txt from pendencia
    where caso_id = v_caso and tipo = 'linha_exigida_ausente' and estado <> 'resolvida'
      and motivo = 'completude:linha_exigida:MUTUOS:saldo_de_mutuo';
  perform teste_assert_le(v_n = 1, 'MUTUOS sem linha de mútuo abre a pendência proposta', 'achou ' || v_n);
  perform teste_assert_le(v_txt like '%PROPOSTA%',
    'a descrição declara que a exigência é proposta (nenhuma checagem a lê hoje)', left(v_txt, 160));

  raise notice '--- 7. política do dono vale por linha e propaga para pendência aberta ---';
  -- O dono decide: caixa ausente em BALANCO passa a ser bloqueante não-sobrepujável.
  update taxonomia_linha_exigida
    set severidade = 'bloqueante', sobrepujavel = false
    where tipo_taxonomia = 'BALANCO' and conceito = 'caixa_e_equivalentes';

  v_caso := (fn_upsert_caso('Caso linha exigida — politica'))::uuid;
  v_r := fn_registrar_documento(
    v_caso, 'Politica Ltda.', 'anual', '2025', 'BALANCO', 0.9, 'nome_arquivo',
    'supabase_storage', 'bucket/bp-politica.pdf', 'BP Politica 2025.pdf', true, 'HASH-LE-7', 'ok');
  v_ver := (v_r->>'documento_versao_id')::uuid;
  perform fn_registrar_campos_extraidos(v_ver, '[
    {"chave": "TOTAL DO ATIVO",                           "valor_num": "900", "confianca": "0.9"},
    {"chave": "TOTAL DO PASSIVO E DO PATRIMONIO LIQUIDO", "valor_num": "900", "confianca": "0.9"}
  ]'::jsonb, 'N0');

  select min(severidade::text), bool_and(sobrepujavel) into v_sev, v_sobre from pendencia
    where caso_id = v_caso and tipo = 'linha_exigida_ausente' and estado <> 'resolvida'
      and motivo like 'completude:linha_exigida:BALANCO:caixa_e_equivalentes%';
  perform teste_assert_le(v_sev = 'bloqueante' and not v_sobre,
    'pendência nova nasce com a política do dono (bloqueante, não-sobrepujável)',
    coalesce(v_sev, 'null') || '/' || coalesce(v_sobre::text, 'null'));

  -- E propaga para pendência JÁ ABERTA no recomputo seguinte.
  update taxonomia_linha_exigida
    set severidade = null, sobrepujavel = null
    where tipo_taxonomia = 'BALANCO' and conceito = 'caixa_e_equivalentes';
  perform fn_recomputar_completude(v_caso);
  select min(severidade::text), bool_and(sobrepujavel) into v_sev, v_sobre from pendencia
    where caso_id = v_caso and tipo = 'linha_exigida_ausente' and estado <> 'resolvida'
      and motivo like 'completude:linha_exigida:BALANCO:caixa_e_equivalentes%';
  perform teste_assert_le(v_sev = 'importante' and v_sobre,
    'voltar a política para NULL propaga no recomputo (de volta ao default)',
    coalesce(v_sev, 'null') || '/' || coalesce(v_sobre::text, 'null'));

  raise notice '--- 8. idempotência ---';
  select count(*) into v_n_campos from campo_extraido;
  perform fn_recomputar_completude(v_caso);
  perform fn_recomputar_completude(v_caso);
  select count(*) into v_n from pendencia
    where caso_id = v_caso and tipo = 'linha_exigida_ausente' and estado <> 'resolvida'
      and motivo like 'completude:linha_exigida:BALANCO:caixa_e_equivalentes%';
  perform teste_assert_le(v_n = 1, 'recomputar de novo não duplica a pendência', 'achou ' || v_n);

  raise notice '--- 9. a checagem só LÊ campo_extraido ---';
  select count(*) - v_n_campos into v_n from campo_extraido;
  perform teste_assert_le(v_n = 0, 'nenhuma linha de campo_extraido criada/apagada pelo recomputo',
    'delta ' || v_n);

  raise notice 'linha_exigida OK — completo não cobra; estrutural satisfaz (0034); ausência nomeada com depende_de; resolve sozinha; sem dupla cobrança no vazio; proposta declarada; política do dono por linha; idempotente; só leitura';
end $$;

drop function teste_assert_le(boolean, text, text);
