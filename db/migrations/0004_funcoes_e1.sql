-- =============================================================================
-- Migration 0004 — Funções (RPC) do E1 + regra de bloqueante na taxonomia
--
-- Empurra a lógica transacional multi-tabela para o Postgres (server-side), para
-- que o N8N fique STATELESS e chame uma função por passo (docs/02, trava nº 1).
-- A completude lê as regras da PRÓPRIA taxonomia (obrigatoriedade + não-sobrepujável),
-- então a tabela é a fonte única da regra do Portão 1.
-- =============================================================================

-- Marca de bloqueante não-sobrepujável na taxonomia (f0/04, lista fechada).
alter table taxonomia_tipo_documento
  add column if not exists nao_sobrepujavel boolean not null default false;

update taxonomia_tipo_documento set nao_sobrepujavel = true
  where codigo in ('DRE','BALANCO','COMBINADO','MUTUOS','CONTRATO_SOCIAL');

-- -----------------------------------------------------------------------------
-- fn_upsert_caso — cria (ou reaproveita) um caso pelo nome. Retorna o id.
-- -----------------------------------------------------------------------------
create or replace function fn_upsert_caso(p_nome text)
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
-- fn_registrar_documento — registra um arquivo classificado (E1), de forma
-- idempotente-ish por hash. Resolve entidade/período, cria documento+versão,
-- preenche checklist (provisório, N1) e gera pendência de classificação quando
-- a confiança é baixa. Retorna o documento_id.
-- -----------------------------------------------------------------------------
create or replace function fn_registrar_documento(
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
returns uuid
language plpgsql
as $$
declare
  v_entidade_id uuid;
  v_periodo_id  uuid;
  v_documento_id uuid;
  v_obrig obrigatoriedade;
begin
  -- entidade (por razão social dentro do caso)
  if p_entidade_nome is not null and length(trim(p_entidade_nome)) > 0 then
    select id into v_entidade_id from entidade
      where caso_id = p_caso_id and lower(razao_social) = lower(p_entidade_nome) limit 1;
    if v_entidade_id is null then
      insert into entidade (caso_id, razao_social) values (p_caso_id, p_entidade_nome)
        returning id into v_entidade_id;
    end if;
  end if;

  -- período (único por caso+tipo+referência)
  if p_periodo_ref is not null and length(trim(p_periodo_ref)) > 0 then
    select id into v_periodo_id from periodo
      where caso_id = p_caso_id and tipo = coalesce(p_periodo_tipo,'outro') and referencia = p_periodo_ref limit 1;
    if v_periodo_id is null then
      insert into periodo (caso_id, tipo, referencia)
        values (p_caso_id, coalesce(p_periodo_tipo,'outro'), p_periodo_ref)
        returning id into v_periodo_id;
    end if;
  end if;

  -- documento + versão
  insert into documento (caso_id, entidade_id, periodo_id, tipo_taxonomia, status)
    values (p_caso_id, v_entidade_id, v_periodo_id, p_tipo_taxonomia, 'em_validacao')
    returning id into v_documento_id;

  insert into documento_versao
    (documento_id, origem_arquivo, arquivo_ref, nome_original, assinado, hash, legibilidade)
    values (v_documento_id, coalesce(p_origem_arquivo,'supabase_storage'),
            p_arquivo_ref, p_nome_original, p_assinado, p_hash, p_legibilidade);

  -- checklist provisório (N1: sugestão; confirmação humana ajusta depois)
  if p_tipo_taxonomia is not null then
    select obrigatoriedade into v_obrig from taxonomia_tipo_documento where codigo = p_tipo_taxonomia;
    insert into checklist_item_status
      (caso_id, entidade_id, periodo_id, tipo_taxonomia, obrigatoriedade, status, documento_id)
      values (p_caso_id, v_entidade_id, v_periodo_id, p_tipo_taxonomia,
              coalesce(v_obrig,'complementar'), 'presente', v_documento_id);
  end if;

  -- pendência de classificação quando confiança baixa ou tipo desconhecido
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

  return v_documento_id;
end;
$$;

-- -----------------------------------------------------------------------------
-- fn_recomputar_completude — (re)avalia o Portão 1 do caso contra o Kit Básico.
-- Cria pendências item_faltante para obrigatórios ausentes (bloqueante; marca
-- sobrepujavel a partir da taxonomia), resolve as que passaram a existir, e
-- avança/retrocede o status do caso. Retorna jsonb com o resumo.
-- -----------------------------------------------------------------------------
create or replace function fn_recomputar_completude(p_caso_id uuid)
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
  -- Kit Básico ausente = obrigatório sem nenhum documento classificado no caso
  select array_agg(t.codigo order by t.codigo) into v_faltantes
  from taxonomia_tipo_documento t
  where t.obrigatoriedade = 'obrigatorio'
    and not exists (
      select 1 from documento d
      where d.caso_id = p_caso_id and d.tipo_taxonomia = t.codigo
    );
  v_faltantes := coalesce(v_faltantes, array[]::text[]);

  -- resolve pendências de itens que passaram a existir
  update pendencia p set estado = 'resolvida', resolvida_em = now(), resolvida_por = 'sistema:n8n'
  where p.caso_id = p_caso_id and p.tipo = 'item_faltante' and p.estado <> 'resolvida'
    and not (p.descricao = any (select 'Item obrigatório do Kit Básico ausente: '||x from unnest(v_faltantes) x));

  -- cria pendências para os que faltam (sem duplicar as ainda abertas)
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

  -- transição de status do caso (só nas transições válidas do E1)
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
