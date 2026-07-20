-- =============================================================================
-- Migration 0008 — Suporte de banco para o Portal (Fatia 1: dashboard + revisão)
--
-- Duas partes:
--   1. `documento` ganha confianca/fonte/justificativa (hoje só existiam soltos
--      em evento_auditoria.depois e no texto da pendência — sem coluna própria,
--      o dashboard teria que fazer parsing de jsonb/texto livre pra mostrar a
--      confiança de cada documento). fn_registrar_documento (mesma assinatura
--      de 0007 — sem DROP) passa a gravá-los.
--   2. fn_revisar_documento — o humano confirma ou corrige a classificação pela
--      fila de revisão do portal: atualiza o documento, resolve a pendência de
--      classificação, registra `decisao` (append-only) e `evento_auditoria`,
--      realoca o checklist, e recomputa a completude do caso.
-- =============================================================================

alter table documento
  add column if not exists confianca     numeric,
  add column if not exists fonte         text,
  add column if not exists justificativa text;

comment on column documento.confianca is
  'Confiança da classificação atual (nome-do-arquivo/IA/humano). 1.0 quando confirmado por humano.';
comment on column documento.fonte is
  'Origem da classificação atual: nome_arquivo | openai_conteudo | humano.';
comment on column documento.justificativa is
  'Explicação objetiva da classificação atual (da IA na origem, ou motivo informado na revisão humana).';

-- -----------------------------------------------------------------------------
-- fn_registrar_documento — mesma assinatura de 0007 (CREATE OR REPLACE sem
-- DROP); só passa a gravar confianca/fonte/justificativa também em `documento`.
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
  p_threshold      numeric default 0.7,
  p_justificativa  text default null
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

  insert into documento (caso_id, entidade_id, periodo_id, tipo_taxonomia, status, confianca, fonte, justificativa)
    values (p_caso_id, v_entidade_id, v_periodo_id, p_tipo_taxonomia, 'em_validacao', p_confianca, p_fonte, p_justificativa)
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
              format('Classificação incerta (conf=%s, fonte=%s) para "%s". Motivo: %s',
                     coalesce(p_confianca,0), coalesce(p_fonte,'?'), coalesce(p_nome_original,'?'),
                     coalesce(nullif(trim(p_justificativa), ''), 'nenhuma justificativa fornecida')),
              v_documento_id);
  end if;

  insert into evento_auditoria (ator, acao, entidade_ref, depois)
    values ('sistema:n8n', 'documento_registrado', 'documento:'||v_documento_id,
            jsonb_build_object('tipo', p_tipo_taxonomia, 'confianca', p_confianca, 'fonte', p_fonte,
                                'justificativa', p_justificativa));

  return jsonb_build_object('documento_id', v_documento_id, 'documento_versao_id', v_versao_id);
end;
$$;

-- -----------------------------------------------------------------------------
-- fn_revisar_documento — ação humana da fila de revisão do portal (N1: humano
-- confirma ou corrige a sugestão). Sempre registra `decisao` (append-only,
-- anti-ancoragem — docs/01): 'aprovacao' se nada mudou, 'correcao_classificacao'
-- se o tipo mudou. Resolve a(s) pendência(s) de classificação do documento,
-- realoca o checklist para o tipo final, e recomputa a completude do caso.
-- -----------------------------------------------------------------------------
create or replace function fn_revisar_documento(
  p_documento_id        uuid,
  p_autor               text,
  p_novo_tipo_taxonomia text default null,  -- null = mantém o tipo atual
  p_nova_entidade_nome  text default null,  -- null = mantém a entidade atual
  p_novo_periodo_tipo   text default null,
  p_novo_periodo_ref    text default null,  -- null = mantém o período atual
  p_motivo              text default null
)
returns jsonb
language plpgsql
as $$
declare
  v_caso_id     uuid;
  v_tipo_antigo text;
  v_entidade_id uuid;
  v_periodo_id  uuid;
  v_tipo_final  text;
  v_obrig       obrigatoriedade;
  v_mudou_tipo  boolean;
begin
  select caso_id, tipo_taxonomia, entidade_id, periodo_id
    into v_caso_id, v_tipo_antigo, v_entidade_id, v_periodo_id
  from documento where id = p_documento_id;

  if v_caso_id is null then
    raise exception 'documento % não encontrado', p_documento_id;
  end if;

  if p_nova_entidade_nome is not null and length(trim(p_nova_entidade_nome)) > 0 then
    select id into v_entidade_id from entidade
      where caso_id = v_caso_id and lower(razao_social) = lower(p_nova_entidade_nome) limit 1;
    if v_entidade_id is null then
      insert into entidade (caso_id, razao_social) values (v_caso_id, p_nova_entidade_nome)
        returning id into v_entidade_id;
    end if;
  end if;

  if p_novo_periodo_ref is not null and length(trim(p_novo_periodo_ref)) > 0 then
    select id into v_periodo_id from periodo
      where caso_id = v_caso_id and tipo = coalesce(p_novo_periodo_tipo,'outro') and referencia = p_novo_periodo_ref limit 1;
    if v_periodo_id is null then
      insert into periodo (caso_id, tipo, referencia)
        values (v_caso_id, coalesce(p_novo_periodo_tipo,'outro'), p_novo_periodo_ref)
        returning id into v_periodo_id;
    end if;
  end if;

  v_tipo_final := coalesce(p_novo_tipo_taxonomia, v_tipo_antigo);
  v_mudou_tipo := v_tipo_final is distinct from v_tipo_antigo;

  update documento set
    tipo_taxonomia = v_tipo_final,
    entidade_id     = v_entidade_id,
    periodo_id      = v_periodo_id,
    confianca       = 1.0,
    fonte           = 'humano',
    justificativa   = coalesce(p_motivo, justificativa)
  where id = p_documento_id;

  -- Checklist: a entrada antiga (se houver) ficaria presa ao tipo errado —
  -- remove e recria para o tipo final (idempotente: sempre reflete o estado atual).
  delete from checklist_item_status where documento_id = p_documento_id;
  if v_tipo_final is not null then
    select obrigatoriedade into v_obrig from taxonomia_tipo_documento where codigo = v_tipo_final;
    insert into checklist_item_status
      (caso_id, entidade_id, periodo_id, tipo_taxonomia, obrigatoriedade, status, documento_id)
      values (v_caso_id, v_entidade_id, v_periodo_id, v_tipo_final,
              coalesce(v_obrig,'complementar'), 'presente', p_documento_id);
  end if;

  insert into decisao (caso_id, tipo, autor, motivo, payload)
    values (v_caso_id,
            (case when v_mudou_tipo then 'correcao_classificacao' else 'aprovacao' end)::decisao_tipo,
            p_autor, p_motivo,
            jsonb_build_object('documento_id', p_documento_id, 'tipo_de', v_tipo_antigo, 'tipo_para', v_tipo_final));

  update pendencia set estado = 'resolvida', resolvida_em = now(), resolvida_por = p_autor
  where documento_id = p_documento_id and tipo = 'classificacao_pendente' and estado <> 'resolvida';

  insert into evento_auditoria (ator, acao, entidade_ref, antes, depois)
    values (p_autor, 'documento_revisado', 'documento:'||p_documento_id,
            jsonb_build_object('tipo', v_tipo_antigo),
            jsonb_build_object('tipo', v_tipo_final, 'motivo', p_motivo));

  perform fn_recomputar_completude(v_caso_id);

  return jsonb_build_object('documento_id', p_documento_id, 'tipo_taxonomia', v_tipo_final, 'mudou_tipo', v_mudou_tipo);
end;
$$;

grant execute on function fn_revisar_documento(uuid, text, text, text, text, text, text) to authenticated;
