-- FECHAR UM MANDATO É DIFERENTE DE EXCLUIR, e o portal só sabia excluir.
--
-- (Esta migration nasceu 0113 e virou 0114 em 17/08: a `0113` ficou com a
-- exigência de linha por tipo, que é trabalho mais antigo — do PR #118 — e o
-- número segue a ordem de chegada, não a de merge.)
--
-- O QUE FALTAVA, e por que não dá para derivar do que existe. `caso.status`
-- (f0/04) descreve onde o mandato está no TRABALHO — intake, em triagem, em
-- revisão, aprovado. Ele não responde a outra pergunta, que é operacional e não
-- técnica: **este mandato ainda está na mesa?** Um caso aprovado em março e um
-- caso aprovado ontem têm o mesmo status e situações opostas, e a lista de
-- mandatos crescia para sempre sem um jeito de tirar da frente o que acabou.
--
-- POR QUE NÃO USAR `status = 'aprovado'` COMO "FECHADO". Porque nem todo mandato
-- que termina termina aprovado: alguns morrem no meio (o cliente desistiu, a
-- operação não aconteceu), e forçá-los a passar por 'aprovado' para sumir da
-- lista seria mentir na trilha — 'aprovado' é uma DECISÃO com regra (Portão 2),
-- não uma gaveta.
--
-- POR QUE NÃO EXCLUIR. `fn_excluir_caso` (0108) apaga o mandato e tudo que
-- depende dele. Isso é certo para o mandato criado por engano, e errado para o
-- que foi trabalhado: o dado extraído, as pendências decididas e a trilha são o
-- registro do que a equipe fez, e uma auditoria futura pode pedi-los. Fechar
-- guarda; excluir some. As duas ações continuam existindo, lado a lado.
--
-- REVERSÍVEL DE PROPÓSITO. Fechar não destrói nada, então reabrir é só limpar o
-- carimbo — e uma ação sem volta convida a hesitar antes de usar, o que faz a
-- lista voltar a crescer.

alter table caso add column if not exists fechado_em      timestamptz;
alter table caso add column if not exists fechado_por     text;
alter table caso add column if not exists motivo_fechamento text;

comment on column caso.fechado_em is
  'Quando o mandato saiu da mesa. NULL = ativo. Não é status de trabalho (esse é `status`, f0/04): '
  'é a resposta a "ainda estamos nisso?". Fechar preserva tudo — para apagar existe fn_excluir_caso.';

-- Índice parcial: a lista da barra lateral pede SEMPRE os ativos, e eles são a
-- minoria conforme o tempo passa.
create index if not exists idx_caso_ativos on caso (criado_em desc) where fechado_em is null;

create or replace function fn_fechar_caso(p_caso_id uuid, p_autor text, p_motivo text default null)
returns jsonb
language plpgsql
as $$
declare
  v_nome text;
  v_ja   timestamptz;
begin
  select nome, fechado_em into v_nome, v_ja from caso where id = p_caso_id;
  if v_nome is null then
    return jsonb_build_object('recusado', true,
      'motivo_recusa', 'Este mandato não existe mais — talvez alguém já o tenha excluído.');
  end if;
  -- Idempotente: fechar duas vezes não reescreve quem fechou nem quando. Dois
  -- cliques no mesmo botão não podem trocar a autoria do primeiro.
  if v_ja is not null then
    return jsonb_build_object('fechado', true, 'nome', v_nome, 'fechado_em', v_ja, 'ja_estava', true);
  end if;

  update caso
     set fechado_em = now(), fechado_por = p_autor, motivo_fechamento = nullif(btrim(p_motivo), '')
   where id = p_caso_id;

  insert into evento_auditoria (ator, acao, entidade_ref, depois)
    values (p_autor, 'caso_fechado', 'caso:'||p_caso_id,
            jsonb_build_object('nome', v_nome, 'motivo', nullif(btrim(p_motivo), '')));

  return jsonb_build_object('fechado', true, 'nome', v_nome, 'fechado_em', now());
end;
$$;

comment on function fn_fechar_caso(uuid, text, text) is
  'Tira o mandato da mesa sem apagar nada. Idempotente: fechar de novo devolve o fechamento '
  'original em vez de reescrever autoria. Reversível por fn_reabrir_caso.';

create or replace function fn_reabrir_caso(p_caso_id uuid, p_autor text)
returns jsonb
language plpgsql
as $$
declare
  v_nome text;
  v_ja   timestamptz;
begin
  select nome, fechado_em into v_nome, v_ja from caso where id = p_caso_id;
  if v_nome is null then
    return jsonb_build_object('recusado', true,
      'motivo_recusa', 'Este mandato não existe mais — talvez alguém já o tenha excluído.');
  end if;
  if v_ja is null then
    return jsonb_build_object('reaberto', true, 'nome', v_nome, 'ja_estava', true);
  end if;

  update caso set fechado_em = null, fechado_por = null, motivo_fechamento = null
   where id = p_caso_id;

  insert into evento_auditoria (ator, acao, entidade_ref, antes)
    values (p_autor, 'caso_reaberto', 'caso:'||p_caso_id,
            jsonb_build_object('nome', v_nome, 'fechado_em', v_ja));

  return jsonb_build_object('reaberto', true, 'nome', v_nome);
end;
$$;

comment on function fn_reabrir_caso(uuid, text) is
  'Desfaz fn_fechar_caso. Existe para que fechar não precise de coragem: ação sem volta faz a '
  'pessoa não usar, e a lista de mandatos volta a crescer sem fim.';

grant execute on function fn_fechar_caso(uuid, text, text) to authenticated;
grant execute on function fn_reabrir_caso(uuid, text) to authenticated;
