-- =============================================================================
-- Migration 0007 — Justificativa objetiva na pendência de classificação
--
-- Feedback do dono testando no N8N real: quando a classificação fica abaixo
-- do limiar, a pendência deve dizer POR QUE (não só "conf=0.5, fonte=X") —
-- uma explicação objetiva do que a IA viu (ou não viu) no documento.
--
-- Adiciona p_justificativa como parâmetro TRAILING com default (CREATE OR
-- REPLACE aceita isso sem precisar de DROP, ao contrário de mudar o tipo de
-- retorno — ver 0005/0006). A justificativa (sempre preenchida pelo prompt
-- ajustado — ver n8n/lib/openai.mjs) vai direto na descrição da pendência.
-- =============================================================================

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
