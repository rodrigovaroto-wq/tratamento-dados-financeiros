-- =============================================================================
-- Migration 0006 — Reset forçado das funções RPC (E1 + E2)
--
-- Motivo: aplicações repetidas/parciais das migrations 0004/0005 deixaram as
-- funções em estado ambíguo (o N8N reportava "function ... does not exist"
-- mesmo com o nome existindo no banco — sinal de assinatura divergente).
--
-- Este script é seguro de rodar a qualquer momento: derruba TODAS as
-- sobrecargas existentes de cada função (não importa a assinatura atual) e
-- recria do zero, com a definição final e correta. Idempotente por construção.
-- =============================================================================

do $$
declare
  r record;
begin
  for r in
    select oid::regprocedure as sig
    from pg_proc
    where proname in (
      'fn_upsert_caso',
      'fn_registrar_documento',
      'fn_recomputar_completude',
      'fn_registrar_campos_extraidos'
    )
  loop
    execute format('drop function if exists %s', r.sig);
  end loop;
end$$;

-- -----------------------------------------------------------------------------
-- fn_upsert_caso — cria (ou reaproveita) um caso pelo nome. Retorna o id.
-- -----------------------------------------------------------------------------
create function fn_upsert_caso(p_nome text)
returns uuid
language plpgsql
as $$
declare
  v_id uuid;
begin
  select id into v_id from caso where nome = p_nome limit 1;
  if v_id is null then
    insert into caso (nome) values (p_nome) returning id into v_id;
    insert into evento_auditoria (ator, acao, entidade_ref, depois)
      values ('sistema:n8n', 'caso_criado', 'caso:'||v_id, jsonb_build_object('nome', p_nome));
  end if;
  return v_id;
end;
$$;

-- -----------------------------------------------------------------------------
-- fn_registrar_documento — registra um arquivo classificado (E1). Retorna
-- { documento_id, documento_versao_id } (jsonb).
-- -----------------------------------------------------------------------------
create function fn_registrar_documento(
  p_caso_id        uuid,
  p_entidade_nome  text,
  p_periodo_tipo   text,
  p_periodo_ref    text,
  p_tipo_taxonomia text,
  p_confianca      numeric,
  p_fonte          text,
  p_origem_arquivo origem_arquivo,
  p_arquivo_ref    text,
  p_nome_original  text,
  p_assinado       boolean,
  p_hash           text,
  p_legibilidade   legibilidade,
  p_threshold      numeric default 0.7
)
returns jsonb
language plpgsql
as $$
declare
  v_entidade_id uuid;
  v_periodo_id  uuid;
  v_documento_id uuid;
  v_versao_id   uuid;
  v_obrig obrigatoriedade;
begin
  if p_entidade_nome is not null and length(trim(p_entidade_nome)) > 0 then
    select id into v_entidade_id from entidade
      where caso_id = p_caso_id and lower(razao_social) = lower(p_entidade_nome) limit 1;
    if v_entidade_id is null then
      insert into entidade (caso_id, razao_social) values (p_caso_id, p_entidade_nome)
        returning id into v_entidade_id;
    end if;
  end if;

  if p_periodo_ref is not null and length(trim(p_periodo_ref)) > 0 then
    select id into v_periodo_id from periodo
      where caso_id = p_caso_id and tipo = coalesce(p_periodo_tipo,'outro') and referencia = p_periodo_ref limit 1;
    if v_periodo_id is null then
      insert into periodo (caso_id, tipo, referencia)
        values (p_caso_id, coalesce(p_periodo_tipo,'outro'), p_periodo_ref)
        returning id into v_periodo_id;
    end if;
  end if;

  insert into documento (caso_id, entidade_id, periodo_id, tipo_taxonomia, status)
    values (p_caso_id, v_entidade_id, v_periodo_id, p_tipo_taxonomia, 'em_validacao')
    returning id into v_documento_id;

  insert into documento_versao
    (documento_id, origem_arquivo, arquivo_ref, nome_original, assinado, hash, legibilidade)
    values (v_documento_id, coalesce(p_origem_arquivo,'supabase_storage'),
            p_arquivo_ref, p_nome_original, p_assinado, p_hash, p_legibilidade)
    returning id into v_versao_id;

  if p_tipo_taxonomia is not null then
    select obrigatoriedade into v_obrig from taxonomia_tipo_documento where codigo = p_tipo_taxonomia;
    insert into checklist_item_status
      (caso_id, entidade_id, periodo_id, tipo_taxonomia, obrigatoriedade, status, documento_id)
      values (p_caso_id, v_entidade_id, v_periodo_id, p_tipo_taxonomia,
              coalesce(v_obrig,'complementar'), 'presente', v_documento_id);
  end if;

  if p_tipo_taxonomia is null or coalesce(p_confianca,0) < p_threshold then
    insert into pendencia (caso_id, origem_estagio, tipo, severidade, sobrepujavel, descricao, documento_id)
      values (p_caso_id, 'classificacao', 'classificacao_pendente', 'importante', true,
              format('Classificação incerta (conf=%s, fonte=%s) para "%s"',
                     coalesce(p_confianca,0), coalesce(p_fonte,'?'), coalesce(p_nome_original,'?')),
              v_documento_id);
  end if;

  insert into evento_auditoria (ator, acao, entidade_ref, depois)
    values ('sistema:n8n', 'documento_registrado', 'documento:'||v_documento_id,
            jsonb_build_object('tipo', p_tipo_taxonomia, 'confianca', p_confianca, 'fonte', p_fonte));

  return jsonb_build_object('documento_id', v_documento_id, 'documento_versao_id', v_versao_id);
end;
$$;

-- -----------------------------------------------------------------------------
-- fn_recomputar_completude — (re)avalia o Portão 1 do caso vs Kit Básico.
-- -----------------------------------------------------------------------------
create function fn_recomputar_completude(p_caso_id uuid)
returns jsonb
language plpgsql
as $$
declare
  v_faltantes text[];
  v_cod text;
  v_nao_sobre boolean;
  v_status_atual caso_status;
  v_novo_status caso_status;
begin
  select array_agg(t.codigo order by t.codigo) into v_faltantes
  from taxonomia_tipo_documento t
  where t.obrigatoriedade = 'obrigatorio'
    and not exists (
      select 1 from documento d
      where d.caso_id = p_caso_id and d.tipo_taxonomia = t.codigo
    );
  v_faltantes := coalesce(v_faltantes, array[]::text[]);

  update pendencia p set estado = 'resolvida', resolvida_em = now(), resolvida_por = 'sistema:n8n'
  where p.caso_id = p_caso_id and p.tipo = 'item_faltante' and p.estado <> 'resolvida'
    and not (p.descricao = any (select 'Item obrigatório do Kit Básico ausente: '||x from unnest(v_faltantes) x));

  foreach v_cod in array v_faltantes loop
    select nao_sobrepujavel into v_nao_sobre from taxonomia_tipo_documento where codigo = v_cod;
    if not exists (
      select 1 from pendencia p
      where p.caso_id = p_caso_id and p.tipo = 'item_faltante'
        and p.estado <> 'resolvida'
        and p.descricao = 'Item obrigatório do Kit Básico ausente: '||v_cod
    ) then
      insert into pendencia (caso_id, origem_estagio, tipo, severidade, sobrepujavel, descricao)
        values (p_caso_id, 'completude', 'item_faltante', 'bloqueante',
                not coalesce(v_nao_sobre,false),
                'Item obrigatório do Kit Básico ausente: '||v_cod);
    end if;
  end loop;

  select status into v_status_atual from caso where id = p_caso_id;
  if array_length(v_faltantes,1) is null then
    v_novo_status := 'completude_ok';
  else
    v_novo_status := 'em_triagem';
  end if;

  if v_status_atual in ('intake','em_triagem','completude_ok') and v_novo_status <> v_status_atual then
    update caso set status = v_novo_status where id = p_caso_id;
    insert into evento_auditoria (ator, acao, entidade_ref, antes, depois)
      values ('sistema:n8n', 'transicao_status', 'caso:'||p_caso_id,
              jsonb_build_object('status', v_status_atual),
              jsonb_build_object('status', v_novo_status));
  end if;

  return jsonb_build_object(
    'portao1_ok', array_length(v_faltantes,1) is null,
    'faltantes', to_jsonb(v_faltantes),
    'status', v_novo_status
  );
end;
$$;

-- -----------------------------------------------------------------------------
-- fn_registrar_campos_extraidos — grava campos extraídos em SOMBRA (N0).
-- -----------------------------------------------------------------------------
create function fn_registrar_campos_extraidos(
  p_documento_versao_id uuid,
  p_campos jsonb,
  p_nivel nivel_autonomia default 'N0'
)
returns int
language plpgsql
as $$
declare
  v_count int := 0;
  v_item jsonb;
begin
  if p_campos is null or jsonb_typeof(p_campos) <> 'array' then
    return 0;
  end if;

  for v_item in select * from jsonb_array_elements(p_campos)
  loop
    insert into campo_extraido
      (documento_versao_id, chave, valor_texto, valor_num, unidade, confianca,
       origem_pagina, origem_linha, nivel_autonomia)
    values (
      p_documento_versao_id,
      coalesce(v_item->>'chave', '(sem rótulo)'),
      v_item->>'valor_texto',
      case when (v_item->>'valor_num') ~ '^-?\d+(\.\d+)?$' then (v_item->>'valor_num')::numeric else null end,
      v_item->>'unidade',
      case when (v_item->>'confianca') ~ '^-?\d+(\.\d+)?$' then (v_item->>'confianca')::numeric else null end,
      case when (v_item->>'origem_pagina') ~ '^\d+$' then (v_item->>'origem_pagina')::int else null end,
      v_item->>'origem_linha',
      p_nivel
    );
    v_count := v_count + 1;
  end loop;

  insert into evento_auditoria (ator, acao, entidade_ref, depois)
    values ('sistema:n8n', 'extracao_sombra', 'documento_versao:'||p_documento_versao_id,
            jsonb_build_object('campos', v_count, 'nivel', p_nivel));

  return v_count;
end;
$$;

-- -----------------------------------------------------------------------------
-- Verificação embutida: confirma as 4 assinaturas logo após criar.
-- -----------------------------------------------------------------------------
do $$
declare v_count int;
begin
  select count(*) into v_count from pg_proc
    where proname in ('fn_upsert_caso','fn_registrar_documento','fn_recomputar_completude','fn_registrar_campos_extraidos');
  if v_count <> 4 then
    raise exception 'Esperava 4 funções recriadas, encontrei %', v_count;
  end if;
  raise notice 'OK: 4 funções RPC recriadas com sucesso.';
end$$;
