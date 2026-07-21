-- =============================================================================
-- Migration 0011 — Aceite humano da extração (Portão 2 mínimo) + suporte ao
-- Export Excel (E4, primeira fatia — f0/07_output_spec.md)
--
-- Princípio inegociável (f0/07): "Nenhum número entra na base viva ou no
-- export sem uma `decisao` de aceite humano ligada. (...) Dado sem aceite não
-- é entregue como fato — no máximo aparece como sugestão pendente de revisão,
-- visualmente distinta." Até aqui, `campo_extraido` não tinha NENHUM mecanismo
-- de aceite — só existia em sombra (N0). Esta migration adiciona o aceite.
--
-- Granularidade v0 (f0/07 permite refinar o "layout fino" depois): aceite é
-- por DOCUMENTO_VERSAO inteiro (todas as linhas extraídas daquela versão de
-- uma vez), não célula a célula — é o degrau mínimo que já satisfaz o campo
-- a campo que a spec pede (`status_aceite`/`aceito_por`/`aceito_em` por
-- linha), sem construir uma UI de seleção linha-a-linha ainda.
-- =============================================================================

alter table campo_extraido
  add column if not exists status_aceite text not null default 'pendente',
  add column if not exists aceito_por    text,
  add column if not exists aceito_em     timestamptz;

alter table campo_extraido drop constraint if exists campo_extraido_status_aceite_check;
alter table campo_extraido add constraint campo_extraido_status_aceite_check
  check (status_aceite in ('pendente', 'aceito', 'com_ressalva'));

comment on column campo_extraido.status_aceite is
  'Portão 2 (E4, f0/07): pendente = sugestão N0/N1, não é fato; aceito = decisao humana ligada, entra no export como fato; com_ressalva = aceito com ressalva.';

-- -----------------------------------------------------------------------------
-- fn_aceitar_extracao — humano aceita TODAS as linhas extraídas de uma versão
-- de documento de uma vez (aceite em lote, v0). Registra `decisao` (tipo
-- aprovacao, append-only) + `evento_auditoria`. Idempotente: só toca linhas
-- ainda não aceitas.
-- -----------------------------------------------------------------------------
create or replace function fn_aceitar_extracao(
  p_documento_versao_id uuid,
  p_autor               text,
  p_motivo              text default null
)
returns jsonb
language plpgsql
as $$
declare
  v_documento_id uuid;
  v_caso_id      uuid;
  v_n_aceitos    int;
begin
  select d.id, d.caso_id into v_documento_id, v_caso_id
  from documento_versao dv
  join documento d on d.id = dv.documento_id
  where dv.id = p_documento_versao_id;

  if v_documento_id is null then
    raise exception 'documento_versao % não encontrada', p_documento_versao_id;
  end if;

  update campo_extraido
    set status_aceite = 'aceito', aceito_por = p_autor, aceito_em = now()
  where documento_versao_id = p_documento_versao_id
    and status_aceite <> 'aceito';
  get diagnostics v_n_aceitos = row_count;

  insert into decisao (caso_id, tipo, autor, motivo, payload)
    values (v_caso_id, 'aprovacao', p_autor, p_motivo,
      jsonb_build_object('documento_versao_id', p_documento_versao_id, 'n_campos_aceitos', v_n_aceitos));

  insert into evento_auditoria (ator, acao, entidade_ref, depois)
    values (p_autor, 'extracao_aceita', 'documento_versao:' || p_documento_versao_id,
      jsonb_build_object('n_campos_aceitos', v_n_aceitos, 'motivo', p_motivo));

  return jsonb_build_object('documento_versao_id', p_documento_versao_id, 'n_campos_aceitos', v_n_aceitos);
end;
$$;

grant execute on function fn_aceitar_extracao(uuid, text, text) to authenticated;
