-- Testes de "linha exigida POR ENTIDADE" (db/migrations/0119).
-- Rodar via db/test/run.sh (que aplica as migrations antes).
--
-- As propriedades travadas:
--
--   #1  O CASO DO RODRIGO (revisão da 0113): grupo com OITO balanços, sete sem
--       a linha de caixa e um com. Na 0113 isso não acusava nada; agora abre
--       SETE pendências, cada uma nomeando a entidade, e a oitava fica limpa;
--   #2  transição: pendência no formato velho (por tipo, sem entidade) é
--       resolvida no primeiro recomputo e as novas por entidade permanecem;
--   #3  COMBINADO: no default (granularidade 'periodo' → escopo caso) nada
--       muda; com o override do dono (escopo_entidade = true), a coluna de
--       empresa sem a linha é cobrada e a outra não;
--   #4  tipo de granularidade 'caso' (MUTUOS) segue exatamente como na 0113 —
--       motivo sem sufixo, entidade_id nulo;
--   #5  fallback: balanço sem entidade nenhuma (nem entidade_id nem
--       entidade_coluna) cai no comportamento por tipo — sem pendência falsa;
--   #6  idempotência e só-leitura de campo_extraido;
--   #G  GUARDA seed × código (apontada pelo dono na revisão): os termos das
--       exigências de origem 'codigo' são conferidos contra o TEXTO VIGENTE
--       das funções de reconciliação (pg_proc.prosrc). Alguém muda um termo em
--       0023/0031/0034 e esquece o seed → este teste reprova.
--
--       O que a guarda cobre e o que não cobre, às claras:
--       • localizador contra='chave' (exceto MAPA_DIVIDA): o PAR
--         inclui,exclui tem de aparecer adjacente na função — é a forma exata
--         das chamadas fn_valor_conceito_col que o seed copiou;
--       • contra='secao'/'estrutural': o array de INCLUI tem de aparecer (o
--         exclui dessas chamadas se mistura com outros argumentos — checar o
--         par seria guarda frouxa fingindo ser justa);
--       • MAPA_DIVIDA (a função usa LIKE, não arrays): cada TERMO tem de
--         aparecer como substring;
--       • a exigência serie_mensal fica FORA: a 0023 soma meses com parser
--         próprio, não com fn_mes_do_rotulo — não há termo comparável, e
--         meia-guarda é pior que limitação declarada;
--       • a direção é seed→código: termo que SÓ existe no código (um fallback
--         novo que ninguém pôs no seed) não é pego. Limitação declarada no PR.

\set ON_ERROR_STOP on

create or replace function teste_assert_lee(p_ok boolean, p_nome text, p_detalhe text default null)
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
  v_n2 int;
  v_n_campos int;
  v_txt text;
  v_ent_ok uuid;
  v_nomes text[] := array['Aurora Alimentos Ltda', 'Boreal Transportes Ltda', 'Cedro Papel Ltda',
                          'Diamante Aco Ltda', 'Estrela Quimica Ltda', 'Farol Energia Ltda',
                          'Granito Mineracao Ltda'];
  v_nome text;
  v_i int := 0;
begin
  raise notice '--- 1. O CASO DO RODRIGO: 8 balanços, 7 sem caixa — 7 pendências nomeando as entidades ---';
  v_caso := (fn_upsert_caso('Caso grupo oito balanços'))::uuid;

  -- Sete balanços SEM a linha de caixa…
  foreach v_nome in array v_nomes loop
    v_i := v_i + 1;
    v_r := fn_registrar_documento(
      v_caso, v_nome, 'anual', '2025', 'BALANCO', 0.9, 'nome_arquivo',
      'supabase_storage', 'bucket/bp-' || v_i || '.pdf', 'BP ' || v_nome || '.pdf', true,
      'HASH-G8-' || v_i, 'ok');
    v_ver := (v_r->>'documento_versao_id')::uuid;
    perform fn_registrar_campos_extraidos(v_ver, '[
      {"chave": "TOTAL DO ATIVO",                           "valor_num": "1000", "confianca": "0.9"},
      {"chave": "TOTAL DO PASSIVO E DO PATRIMONIO LIQUIDO", "valor_num": "1000", "confianca": "0.9"},
      {"chave": "Estoques",                                 "valor_num": "1000", "confianca": "0.9"}
    ]'::jsonb, 'N0');
  end loop;

  -- …e o oitavo COM ela.
  v_r := fn_registrar_documento(
    v_caso, 'Horizonte Varejo Ltda', 'anual', '2025', 'BALANCO', 0.9, 'nome_arquivo',
    'supabase_storage', 'bucket/bp-8.pdf', 'BP Horizonte Varejo.pdf', true, 'HASH-G8-8', 'ok');
  v_ver := (v_r->>'documento_versao_id')::uuid;
  perform fn_registrar_campos_extraidos(v_ver, '[
    {"chave": "TOTAL DO ATIVO",                           "valor_num": "900", "confianca": "0.9"},
    {"chave": "TOTAL DO PASSIVO E DO PATRIMONIO LIQUIDO", "valor_num": "900", "confianca": "0.9"},
    {"chave": "Caixa e equivalentes de caixa",            "valor_num": "80",  "confianca": "0.9"}
  ]'::jsonb, 'N0');

  select count(*), count(distinct entidade_id) into v_n, v_n2 from pendencia
    where caso_id = v_caso and tipo = 'linha_exigida_ausente' and estado <> 'resolvida'
      and motivo like 'completude:linha_exigida:BALANCO:caixa_e_equivalentes:%';
  perform teste_assert_lee(v_n = 7,
    'sete balanços sem caixa abrem SETE pendências (na 0113 não abria nenhuma)', 'abriu ' || v_n);
  perform teste_assert_lee(v_n2 = 7,
    'as sete pendências apontam sete entidades DISTINTAS (entidade_id preenchido)', v_n2 || ' distintas');

  select count(*) into v_n from pendencia p
    join entidade e on e.id = p.entidade_id
    where p.caso_id = v_caso and p.tipo = 'linha_exigida_ausente' and p.estado <> 'resolvida'
      and fn_mesma_entidade(e.razao_social, 'Horizonte Varejo Ltda');
  perform teste_assert_lee(v_n = 0,
    'a oitava entidade — a que TEM a linha — fica limpa', 'abriu ' || v_n);

  select min(descricao) into v_txt from pendencia p
    join entidade e on e.id = p.entidade_id
    where p.caso_id = v_caso and p.tipo = 'linha_exigida_ausente' and p.estado <> 'resolvida'
      and fn_mesma_entidade(e.razao_social, 'Aurora Alimentos Ltda');
  perform teste_assert_lee(v_txt like '%Aurora Alimentos%' and v_txt like '%Caixa e equivalentes%',
    'a descrição NOMEIA a entidade e a linha (doutrina da 0033, agora com dono)', left(v_txt, 140));

  select count(*) into v_n from pendencia
    where caso_id = v_caso and tipo = 'linha_exigida_ausente' and estado <> 'resolvida'
      and motivo like 'completude:linha_exigida:BALANCO:%'
      and motivo not like 'completude:linha_exigida:BALANCO:caixa_e_equivalentes:%';
  perform teste_assert_lee(v_n = 0,
    'Ativo e Passivo+PL, presentes em TODAS as entidades, não são cobrados', 'abriu ' || v_n);

  raise notice '--- 2. transição: pendência do formato VELHO resolve no primeiro recomputo ---';
  insert into pendencia (caso_id, origem_estagio, tipo, severidade, sobrepujavel, descricao, motivo)
    values (v_caso, 'completude', 'linha_exigida_ausente', 'importante', true,
            'formato da 0113, sem entidade (simulando pendência anterior à 0119)',
            'completude:linha_exigida:BALANCO:caixa_e_equivalentes');
  perform fn_recomputar_completude(v_caso);
  select count(*) into v_n from pendencia
    where caso_id = v_caso and motivo = 'completude:linha_exigida:BALANCO:caixa_e_equivalentes'
      and estado <> 'resolvida';
  perform teste_assert_lee(v_n = 0, 'a pendência de formato velho é resolvida sozinha', 'sobrou ' || v_n);
  select count(*) into v_n from pendencia
    where caso_id = v_caso and tipo = 'linha_exigida_ausente' and estado <> 'resolvida'
      and motivo like 'completude:linha_exigida:BALANCO:caixa_e_equivalentes:%';
  perform teste_assert_lee(v_n = 7, '…e as sete por entidade permanecem', 'achou ' || v_n);

  raise notice '--- 6a. idempotência e só-leitura (no caso dos oito balanços) ---';
  select count(*) into v_n_campos from campo_extraido;
  perform fn_recomputar_completude(v_caso);
  perform fn_recomputar_completude(v_caso);
  select count(*) into v_n from pendencia
    where caso_id = v_caso and tipo = 'linha_exigida_ausente' and estado <> 'resolvida'
      and motivo like 'completude:linha_exigida:BALANCO:caixa_e_equivalentes:%';
  perform teste_assert_lee(v_n = 7, 'recomputar duas vezes não duplica nem some pendência', 'achou ' || v_n);
  select count(*) - v_n_campos into v_n from campo_extraido;
  perform teste_assert_lee(v_n = 0, 'campo_extraido intacto — a checagem só LÊ', 'delta ' || v_n);
end $$;

do $$
declare
  v_caso uuid;
  v_r jsonb;
  v_ver uuid;
  v_n int;
  v_ent_b uuid;
begin
  raise notice '--- 3. COMBINADO: default por caso; override do dono liga a cobrança por coluna ---';
  v_caso := (fn_upsert_caso('Caso combinado duas colunas'))::uuid;
  perform fn_upsert_entidade(v_caso, 'Alianca Textil Ltda');
  perform fn_upsert_entidade(v_caso, 'Bussola Naval Ltda');

  v_r := fn_registrar_documento(
    v_caso, 'Grupo Casca', 'anual', '2025', 'COMBINADO', 0.9, 'nome_arquivo',
    'supabase_storage', 'bucket/comb.pdf', 'Combinado Casca.pdf', true, 'HASH-COMB-1', 'ok');
  v_ver := (v_r->>'documento_versao_id')::uuid;
  -- Aliança tem caixa; Bússola não. Um documento, duas colunas de empresa.
  perform fn_registrar_campos_extraidos(v_ver, '[
    {"chave": "TOTAL DO ATIVO",                           "valor_num": "300", "confianca": "0.9", "entidade_coluna": "Alianca Textil Ltda"},
    {"chave": "TOTAL DO PASSIVO E DO PATRIMONIO LIQUIDO", "valor_num": "300", "confianca": "0.9", "entidade_coluna": "Alianca Textil Ltda"},
    {"chave": "Caixa e equivalentes de caixa",            "valor_num": "40",  "confianca": "0.9", "entidade_coluna": "Alianca Textil Ltda"},
    {"chave": "TOTAL DO ATIVO",                           "valor_num": "200", "confianca": "0.9", "entidade_coluna": "Bussola Naval Ltda"},
    {"chave": "TOTAL DO PASSIVO E DO PATRIMONIO LIQUIDO", "valor_num": "200", "confianca": "0.9", "entidade_coluna": "Bussola Naval Ltda"},
    {"chave": "Estoques",                                 "valor_num": "200", "confianca": "0.9", "entidade_coluna": "Bussola Naval Ltda"}
  ]'::jsonb, 'N0');

  select count(*) into v_n from pendencia
    where caso_id = v_caso and tipo = 'linha_exigida_ausente' and estado <> 'resolvida'
      and motivo like 'completude:linha_exigida:COMBINADO:caixa_e_equivalentes%';
  perform teste_assert_lee(v_n = 0,
    'no DEFAULT (granularidade periodo → escopo caso) o caixa da Aliança satisfaz o tipo', 'abriu ' || v_n);

  -- O DONO liga a alavanca para esta exigência…
  update taxonomia_linha_exigida set escopo_entidade = true
    where tipo_taxonomia = 'COMBINADO' and conceito = 'caixa_e_equivalentes';
  perform fn_recomputar_completude(v_caso);

  select e.id into v_ent_b from entidade e
    where e.caso_id = v_caso and fn_mesma_entidade(e.razao_social, 'Bussola Naval Ltda');
  select count(*) into v_n from pendencia
    where caso_id = v_caso and tipo = 'linha_exigida_ausente' and estado <> 'resolvida'
      and motivo like 'completude:linha_exigida:COMBINADO:caixa_e_equivalentes:%'
      and entidade_id = v_ent_b;
  perform teste_assert_lee(v_n = 1,
    'com o override, a coluna SEM caixa (Bússola) é cobrada, nomeada', 'achou ' || v_n);
  select count(*) into v_n from pendencia
    where caso_id = v_caso and tipo = 'linha_exigida_ausente' and estado <> 'resolvida'
      and motivo like 'completude:linha_exigida:COMBINADO:caixa_e_equivalentes:%'
      and (entidade_id is null or entidade_id <> v_ent_b);
  perform teste_assert_lee(v_n = 0,
    'a coluna COM caixa (Aliança) e o rótulo do grupo não são cobrados', 'abriu ' || v_n);

  -- …e desliga: a pendência da Bússola resolve sozinha no recomputo seguinte.
  update taxonomia_linha_exigida set escopo_entidade = null
    where tipo_taxonomia = 'COMBINADO' and conceito = 'caixa_e_equivalentes';
  perform fn_recomputar_completude(v_caso);
  select count(*) into v_n from pendencia
    where caso_id = v_caso and tipo = 'linha_exigida_ausente' and estado <> 'resolvida'
      and motivo like 'completude:linha_exigida:COMBINADO:%';
  perform teste_assert_lee(v_n = 0,
    'desligado o override, a pendência por coluna resolve sozinha (alavanca reversível)', 'sobrou ' || v_n);
end $$;

do $$
declare
  v_caso uuid;
  v_r jsonb;
  v_ver uuid;
  v_n int;
  v_doc uuid := gen_random_uuid();
begin
  raise notice '--- 4. granularidade CASO (MUTUOS): comportamento da 0113, intocado ---';
  v_caso := (fn_upsert_caso('Caso mutuos por caso'))::uuid;
  v_r := fn_registrar_documento(
    v_caso, 'Grupo Dinamo', 'anual', '2025', 'MUTUOS', 0.9, 'nome_arquivo',
    'supabase_storage', 'bucket/mutuos-ent.pdf', 'Mutuos Dinamo.pdf', true, 'HASH-MUT-ENT', 'ok');
  v_ver := (v_r->>'documento_versao_id')::uuid;
  perform fn_registrar_campos_extraidos(v_ver, '[
    {"chave": "Saldo com controlada Zeta", "valor_num": "150", "confianca": "0.9"}
  ]'::jsonb, 'N0');

  select count(*) into v_n from pendencia
    where caso_id = v_caso and tipo = 'linha_exigida_ausente' and estado <> 'resolvida'
      and motivo = 'completude:linha_exigida:MUTUOS:saldo_de_mutuo'
      and entidade_id is null;
  perform teste_assert_lee(v_n = 1,
    'MUTUOS (granularidade caso) cobra por caso: motivo SEM sufixo, entidade_id nulo', 'achou ' || v_n);

  raise notice '--- 5. fallback: balanço SEM entidade nenhuma não vira pendência falsa por entidade ---';
  v_caso := (fn_upsert_caso('Caso sem entidade rotulada'))::uuid;
  insert into documento (id, caso_id, entidade_id, tipo_taxonomia, status, confianca, fonte)
    values (v_doc, v_caso, null, 'BALANCO', 'valido', 0.9, 'teste');
  v_ver := gen_random_uuid();
  insert into documento_versao (id, documento_id, n_versao, arquivo_ref, nome_original, hash)
    values (v_ver, v_doc, 1, 'x', 'BP sem entidade.pdf', md5(v_ver::text));
  insert into campo_extraido (documento_versao_id, chave, valor_num, confianca) values
    (v_ver, 'TOTAL DO ATIVO',                           700, 0.9),
    (v_ver, 'TOTAL DO PASSIVO E DO PATRIMONIO LIQUIDO', 700, 0.9),
    (v_ver, 'Estoques',                                 700, 0.9);
  perform fn_recomputar_completude(v_caso);

  select count(*) into v_n from pendencia
    where caso_id = v_caso and tipo = 'linha_exigida_ausente' and estado <> 'resolvida'
      and motivo = 'completude:linha_exigida:BALANCO:caixa_e_equivalentes'
      and entidade_id is null;
  perform teste_assert_lee(v_n = 1,
    'sem eixo de entidade, cai no comportamento por tipo (0113): uma pendência, sem entidade', 'achou ' || v_n);
  select count(*) into v_n from pendencia
    where caso_id = v_caso and tipo = 'linha_exigida_ausente' and estado <> 'resolvida'
      and motivo like 'completude:linha_exigida:BALANCO:caixa_e_equivalentes:%';
  perform teste_assert_lee(v_n = 0,
    'e NENHUMA pendência por entidade inventada de rótulo ausente', 'abriu ' || v_n);
end $$;

-- =============================================================================
-- #G — A GUARDA seed × código (ponto da revisão do dono).
-- Reprova quando um termo de exigência 'codigo' deixa de existir no texto
-- VIGENTE da função de reconciliação correspondente. Cobertura e limitações
-- declaradas no cabeçalho deste arquivo.
-- =============================================================================
do $$
declare
  v_rec record;
  v_src text;
  v_alvo text;
  v_termo text;
  v_faltando text;
  v_n int := 0;
begin
  raise notice '--- G. o seed ''codigo'' confere com os termos vivos das reconciliações ---';

  -- O MAPA exigência → função precisa cobrir todo o seed 'codigo' por termos:
  -- exigência nova sem mapa reprovaria aqui, em vez de ficar sem guarda em
  -- silêncio.
  select string_agg(e.tipo_taxonomia || ':' || e.conceito, ', ') into v_faltando
  from taxonomia_linha_exigida e
  where e.origem = 'codigo' and e.checagem = 'linha_por_termos' and e.ativo
    and (e.tipo_taxonomia, e.conceito) not in (
      select m.tipo, m.conceito from (values
        ('BALANCO',     'ativo_total',          'fn_reconciliar_ativo_passivo_pl'),
        ('COMBINADO',   'ativo_total',          'fn_reconciliar_ativo_passivo_pl'),
        ('BALANCO',     'passivo_mais_pl',      'fn_reconciliar_ativo_passivo_pl'),
        ('COMBINADO',   'passivo_mais_pl',      'fn_reconciliar_ativo_passivo_pl'),
        ('BALANCO',     'caixa_e_equivalentes', 'fn_reconciliar_caixa_bp_fluxo'),
        ('COMBINADO',   'caixa_e_equivalentes', 'fn_reconciliar_caixa_bp_fluxo'),
        ('FLUXO_CAIXA', 'saldo_final_de_caixa', 'fn_reconciliar_caixa_bp_fluxo'),
        ('DRE',         'receita_bruta',        'fn_reconciliar_receita_dre_vs_faturamento'),
        ('DRE',         'despesa_financeira',   'fn_reconciliar_despfin_dre_vs_divida'),
        ('MAPA_DIVIDA', 'juros_por_contrato',   'fn_reconciliar_despfin_dre_vs_divida')
      ) m(tipo, conceito, fn));
  perform teste_assert_lee(v_faltando is null,
    'toda exigência codigo/por-termos está no mapa da guarda', v_faltando);

  for v_rec in
    select e.tipo_taxonomia, e.conceito, l.ordem, l.contra, l.termos_inclui, l.termos_exclui, m.fn
    from taxonomia_linha_exigida e
    join taxonomia_linha_localizador l on l.exigencia_id = e.id
    join (values
        ('BALANCO',     'ativo_total',          'fn_reconciliar_ativo_passivo_pl'),
        ('COMBINADO',   'ativo_total',          'fn_reconciliar_ativo_passivo_pl'),
        ('BALANCO',     'passivo_mais_pl',      'fn_reconciliar_ativo_passivo_pl'),
        ('COMBINADO',   'passivo_mais_pl',      'fn_reconciliar_ativo_passivo_pl'),
        ('BALANCO',     'caixa_e_equivalentes', 'fn_reconciliar_caixa_bp_fluxo'),
        ('COMBINADO',   'caixa_e_equivalentes', 'fn_reconciliar_caixa_bp_fluxo'),
        ('FLUXO_CAIXA', 'saldo_final_de_caixa', 'fn_reconciliar_caixa_bp_fluxo'),
        ('DRE',         'receita_bruta',        'fn_reconciliar_receita_dre_vs_faturamento'),
        ('DRE',         'despesa_financeira',   'fn_reconciliar_despfin_dre_vs_divida'),
        ('MAPA_DIVIDA', 'juros_por_contrato',   'fn_reconciliar_despfin_dre_vs_divida')
      ) m(tipo, conceito, fn)
      on m.tipo = e.tipo_taxonomia and m.conceito = e.conceito
    where e.origem = 'codigo' and e.checagem = 'linha_por_termos' and e.ativo
    order by e.tipo_taxonomia, e.conceito, l.ordem
  loop
    -- O texto VIGENTE da função, minúsculo e sem nenhum espaço — a mesma
    -- normalização é aplicada ao alvo, então 'nao circulante' vira
    -- 'naocirculante' dos dois lados.
    select regexp_replace(lower(string_agg(p.prosrc, ' ')), '\s', '', 'g') into v_src
    from pg_proc p where p.proname = v_rec.fn;
    perform teste_assert_lee(v_src is not null,
      format('a função %s existe no banco', v_rec.fn));

    if v_rec.tipo_taxonomia = 'MAPA_DIVIDA' then
      -- A função usa LIKE ('%juros%'), não arrays: cada termo como substring.
      foreach v_termo in array v_rec.termos_inclui || v_rec.termos_exclui loop
        perform teste_assert_lee(
          position(regexp_replace(lower(v_termo), '\s', '', 'g') in v_src) > 0,
          format('%s:%s #%s — termo "%s" vive em %s',
                 v_rec.tipo_taxonomia, v_rec.conceito, v_rec.ordem, v_termo, v_rec.fn));
      end loop;
    elsif v_rec.contra = 'chave' then
      -- O par inclui,exclui exatamente como a chamada que o seed copiou.
      v_alvo := regexp_replace(lower(
                  'array[''' || array_to_string(v_rec.termos_inclui, ''',''') || ''']'
                  || ',array[''' || array_to_string(v_rec.termos_exclui, ''',''') || ''']'),
                '\s', '', 'g');
      perform teste_assert_lee(position(v_alvo in v_src) > 0,
        format('%s:%s #%s — par inclui/exclui vive em %s',
               v_rec.tipo_taxonomia, v_rec.conceito, v_rec.ordem, v_rec.fn),
        v_alvo);
    else
      -- secao/estrutural: o array de INCLUI (o exclui dessas chamadas se
      -- mistura com outros argumentos — ver o cabeçalho).
      v_alvo := regexp_replace(lower(
                  'array[''' || array_to_string(v_rec.termos_inclui, ''',''') || ''']'),
                '\s', '', 'g');
      perform teste_assert_lee(position(v_alvo in v_src) > 0,
        format('%s:%s #%s (%s) — inclui vive em %s',
               v_rec.tipo_taxonomia, v_rec.conceito, v_rec.ordem, v_rec.contra, v_rec.fn),
        v_alvo);
    end if;
    v_n := v_n + 1;
  end loop;

  perform teste_assert_lee(v_n >= 20,
    'a guarda percorreu os localizadores de código (>=20)', v_n || ' conferidos');

  raise notice 'linha_exigida_entidade OK — 7/8 do caso do Rodrigo; transição de formato; COMBINADO por override reversível; MUTUOS por caso; fallback sem entidade; idempotente; guarda seed×código viva';
end $$;

drop function teste_assert_lee(boolean, text, text);
