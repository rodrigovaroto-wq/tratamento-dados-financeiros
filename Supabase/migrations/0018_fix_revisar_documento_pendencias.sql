-- =============================================================================
-- Migration 0018 — Fix: fn_revisar_documento só resolvia UM dos 4 tipos de
-- pendência da fila de revisão (cards "não somem" ao confirmar/salvar)
--
-- Achado em produção (sessão 7 cont.¹⁴, "teste v20"): o dono clicava em
-- "Confirmar/salvar" na fila de revisão, o documento era corretamente
-- atualizado (fonte='humano', confiança=100%, `decisao`+`evento_auditoria`
-- registrados) — mas o CARD continuava aparecendo na fila, com a MESMA
-- pendência.
--
-- Causa raiz: `fn_revisar_documento` (migration 0008) só resolvia pendências
-- do tipo `classificacao_pendente`:
--   update pendencia set estado = 'resolvida', ...
--   where documento_id = p_documento_id and tipo = 'classificacao_pendente' ...
-- Mas a migration 0010 (Diagnóstico de conteúdo, E1/E2) introduziu TRÊS outros
-- tipos de pendência gerados pela MESMA fila de revisão do portal
-- (`PENDENCIA_TIPOS_DIAGNOSTICO_REVISAVEIS` em portal/src/lib/types.ts):
-- `tipo_incorreto`, `entidade_incorreta`, `periodo_incorreto` — nenhum deles
-- nunca foi adicionado ao WHERE acima. Toda vez que o diagnóstico de conteúdo
-- (não o nome do arquivo) gerava a pendência — o caso mais comum, já que o
-- diagnóstico roda sempre — confirmar pelo formulário resolvia o documento
-- mas NUNCA fechava o card.
-- =============================================================================

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

  -- FIX (0018): resolve TODOS os tipos de pendência de revisão gerados para
  -- este documento — não só `classificacao_pendente`. `tipo_incorreto`/
  -- `entidade_incorreta`/`periodo_incorreto` (migration 0010) são fechados
  -- pela MESMA ação de revisão (o formulário já reenvia tipo+entidade+período
  -- juntos), então a resolução tem que cobrir os quatro.
  update pendencia set estado = 'resolvida', resolvida_em = now(), resolvida_por = p_autor
  where documento_id = p_documento_id
    and tipo in ('classificacao_pendente', 'tipo_incorreto', 'entidade_incorreta', 'periodo_incorreto')
    and estado <> 'resolvida';

  insert into evento_auditoria (ator, acao, entidade_ref, antes, depois)
    values (p_autor, 'documento_revisado', 'documento:'||p_documento_id,
            jsonb_build_object('tipo', v_tipo_antigo),
            jsonb_build_object('tipo', v_tipo_final, 'motivo', p_motivo));

  perform fn_recomputar_completude(v_caso_id);

  return jsonb_build_object('documento_id', p_documento_id, 'tipo_taxonomia', v_tipo_final, 'mudou_tipo', v_mudou_tipo);
end;
$$;
