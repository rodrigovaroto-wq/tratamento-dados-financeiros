-- =============================================================================
-- Migration 0009 — Reconciliação Cruzada, Classe A (E3, primeira fatia)
--
-- Doutrina (docs/04_RECONCILIACAO.md): Classe A = identidades aritméticas puras,
-- só roda com pré-condições satisfeitas, opera em N1 no MVP (sugestão de
-- pendência confirmada por humano — nunca escreve "fato" numa base viva).
-- Pré-condição não satisfeita → pendência tipada, nunca um "OK" falso (docs/02).
--
-- Duas checagens (os dois exemplos canônicos de docs/04):
--   1. Ativo Total = Passivo Total (exigível) + Patrimônio Líquido — no Balanço.
--   2. Caixa e equivalentes (Balanço) = Saldo final de caixa (Fluxo de Caixa).
--
-- `campo_extraido.chave` é texto livre extraído pela IA (E2, N0) — não um plano
-- de contas normalizado. O casamento chave→conceito canônico usa normalização
-- (minúsculas/sem acento) + termos obrigatórios/excludentes, NUNCA um LLM
-- (docs/04: "papel do LLM só como hipótese explicativa depois de detectado
-- deterministicamente — nunca para decidir se reconciliou").
-- =============================================================================

create extension if not exists unaccent;

-- -----------------------------------------------------------------------------
-- Tabela reconciliacao — log de toda checagem rodada (histórico/auditoria).
-- A pendência (tabela pendencia) é o estado ACIONÁVEL deduplicado; esta tabela
-- é o log append-only de cada execução (f0/05).
-- -----------------------------------------------------------------------------
create table if not exists reconciliacao (
  id              uuid primary key default gen_random_uuid(),
  caso_id         uuid not null references caso(id) on delete cascade,
  entidade_id     uuid references entidade(id),
  periodo_id      uuid references periodo(id),
  tipo            text not null,             -- 'ativo_passivo_pl' | 'caixa_bp_vs_fluxo'
  classe          text not null default 'A',
  fonte_a         jsonb,                     -- {chave, valor, documento_versao_id}
  fonte_b         jsonb,
  precondicoes_ok boolean not null,
  resultado       text not null,             -- 'ok' | 'divergente' | 'precondicao_nao_satisfeita'
  divergencia_abs numeric,
  divergencia_pct numeric,
  materialidade   jsonb,                     -- {tolerancia_abs, tolerancia_pct}
  criado_em       timestamptz not null default now()
);
create index if not exists idx_reconciliacao_caso on reconciliacao(caso_id);

alter table reconciliacao enable row level security;
drop policy if exists reconciliacao_authenticated_all on reconciliacao;
create policy reconciliacao_authenticated_all on reconciliacao
  for all to authenticated using (true) with check (true);

-- -----------------------------------------------------------------------------
-- fn_normalizar_texto — minúsculas, sem acento, espaços colapsados. Base de
-- todo casamento chave→conceito nesta migration.
-- -----------------------------------------------------------------------------
create or replace function fn_normalizar_texto(p_texto text)
returns text
language sql
immutable
as $$
  select trim(regexp_replace(lower(unaccent(coalesce(p_texto, ''))), '\s+', ' ', 'g'));
$$;

-- -----------------------------------------------------------------------------
-- fn_versao_atual — id da documento_versao mais recente de um documento.
-- -----------------------------------------------------------------------------
create or replace function fn_versao_atual(p_documento_id uuid)
returns uuid
language sql
stable
as $$
  select id from documento_versao where documento_id = p_documento_id order by n_versao desc limit 1;
$$;

-- -----------------------------------------------------------------------------
-- fn_valor_conceito — acha, dentro dos campos extraídos de UMA versão de
-- documento, a linha cuja chave (normalizada) contém TODOS os termos de
-- p_inclui e NENHUM de p_exclui. Em caso de mais de um casamento, prefere
-- maior confiança e depois a chave mais curta (mais específica/menos
-- provável de ser um subtotal). Retorna null (sem linhas) quando não casa.
-- -----------------------------------------------------------------------------
create or replace function fn_valor_conceito(
  p_documento_versao_id uuid,
  p_inclui text[],
  p_exclui text[] default '{}'
)
returns campo_extraido
language sql
stable
as $$
  select ce.*
  from campo_extraido ce
  where ce.documento_versao_id = p_documento_versao_id
    and ce.valor_num is not null
    and not exists (
      select 1 from unnest(p_inclui) as termo
      where fn_normalizar_texto(ce.chave) not like '%' || fn_normalizar_texto(termo) || '%'
    )
    and not exists (
      select 1 from unnest(p_exclui) as termo
      where fn_normalizar_texto(ce.chave) like '%' || fn_normalizar_texto(termo) || '%'
    )
  order by coalesce(ce.confianca, 0) desc, length(ce.chave) asc
  limit 1;
$$;

-- -----------------------------------------------------------------------------
-- fn_reconciliar_ativo_passivo_pl — Classe A: Ativo Total = Passivo + PL, no
-- Balanço Patrimonial classificado mais recente da entidade/período. Tenta
-- primeiro a linha combinada padrão brasileira ("Total do Passivo e do
-- Patrimônio Líquido"); se ausente, soma Passivo Total (exigível) + PL Total.
-- -----------------------------------------------------------------------------
create or replace function fn_reconciliar_ativo_passivo_pl(
  p_caso_id       uuid,
  p_entidade_id   uuid,
  p_periodo_id    uuid,
  p_tolerancia_abs numeric default 100,
  p_tolerancia_pct numeric default 0.005
)
returns jsonb
language plpgsql
as $$
declare
  v_documento_id     uuid;
  v_versao_id        uuid;
  v_ativo            campo_extraido;
  v_passivo_pl        campo_extraido;
  v_passivo          campo_extraido;
  v_pl               campo_extraido;
  v_lado_direito     numeric;
  v_precondicoes_ok  boolean := true;
  v_resultado        text;
  v_divergencia_abs  numeric;
  v_divergencia_pct  numeric;
  v_tolerancia_final numeric;
  v_motivo           text;
  v_descricao        text;
  v_reconciliacao_id uuid;
  v_pendencia_id     uuid;
begin
  select d.id into v_documento_id
  from documento d
  where d.caso_id = p_caso_id
    and d.tipo_taxonomia = 'BALANCO'
    and (p_entidade_id is null or d.entidade_id = p_entidade_id)
    and (p_periodo_id is null or d.periodo_id = p_periodo_id)
  order by d.criado_em desc
  limit 1;

  if v_documento_id is null then
    v_precondicoes_ok := false;
    v_motivo := 'Nenhum Balanço Patrimonial classificado para esta entidade/período.';
  else
    v_versao_id := fn_versao_atual(v_documento_id);

    select * into v_ativo from fn_valor_conceito(v_versao_id,
      array['ativo', 'total'], array['circulante', 'nao circulante']);

    select * into v_passivo_pl from fn_valor_conceito(v_versao_id,
      array['passivo', 'patrimonio', 'total'], array['circulante']);

    if v_passivo_pl.id is not null then
      v_lado_direito := v_passivo_pl.valor_num;
    else
      select * into v_passivo from fn_valor_conceito(v_versao_id,
        array['passivo', 'total'], array['patrimonio', 'circulante', 'nao circulante']);
      select * into v_pl from fn_valor_conceito(v_versao_id,
        array['patrimonio', 'liquido', 'total'], array['circulante']);
      if v_passivo.id is not null and v_pl.id is not null then
        v_lado_direito := v_passivo.valor_num + v_pl.valor_num;
      end if;
    end if;

    if v_ativo.id is null or v_lado_direito is null then
      v_precondicoes_ok := false;
      v_motivo := 'Não foi possível localizar, nos campos extraídos, o Ativo Total e o '
                  || 'Passivo+Patrimônio Líquido do Balanço (rótulos extraídos não bateram '
                  || 'com os padrões esperados).';
    end if;
  end if;

  if v_precondicoes_ok then
    v_divergencia_abs := abs(v_ativo.valor_num - v_lado_direito);
    v_divergencia_pct := case when v_ativo.valor_num <> 0
      then v_divergencia_abs / abs(v_ativo.valor_num) else null end;
    v_tolerancia_final := greatest(p_tolerancia_abs, abs(coalesce(v_ativo.valor_num, 0)) * p_tolerancia_pct);
    v_resultado := case when v_divergencia_abs <= v_tolerancia_final then 'ok' else 'divergente' end;
    v_descricao := format('Ativo Total (%s, "%s") vs Passivo+PL (%s): divergência de %s (%s%%).',
      v_ativo.valor_num, v_ativo.chave, v_lado_direito, v_divergencia_abs,
      round(coalesce(v_divergencia_pct, 0) * 100, 2));
  else
    v_resultado := 'precondicao_nao_satisfeita';
    v_descricao := v_motivo;
  end if;

  insert into reconciliacao
    (caso_id, entidade_id, periodo_id, tipo, classe, fonte_a, fonte_b,
     precondicoes_ok, resultado, divergencia_abs, divergencia_pct, materialidade)
  values (
    p_caso_id, p_entidade_id, p_periodo_id, 'ativo_passivo_pl', 'A',
    case when v_ativo.id is not null then
      jsonb_build_object('chave', v_ativo.chave, 'valor', v_ativo.valor_num, 'documento_versao_id', v_ativo.documento_versao_id)
    else null end,
    case when v_lado_direito is not null then jsonb_build_object('valor', v_lado_direito) else null end,
    v_precondicoes_ok, v_resultado, v_divergencia_abs, v_divergencia_pct,
    jsonb_build_object('tolerancia_abs', p_tolerancia_abs, 'tolerancia_pct', p_tolerancia_pct)
  )
  returning id into v_reconciliacao_id;

  -- Idempotência: reaproveita a pendência ABERTA da mesma checagem (mesmo
  -- caso/entidade/período) em vez de duplicar a cada nova extração/reexecução.
  select id into v_pendencia_id from pendencia
  where caso_id = p_caso_id
    and motivo = 'reconciliacao:ativo_passivo_pl'
    and coalesce(entidade_id, '00000000-0000-0000-0000-000000000000'::uuid)
      = coalesce(p_entidade_id, '00000000-0000-0000-0000-000000000000'::uuid)
    and coalesce(periodo_id, '00000000-0000-0000-0000-000000000000'::uuid)
      = coalesce(p_periodo_id, '00000000-0000-0000-0000-000000000000'::uuid)
    and estado <> 'resolvida'
  limit 1;

  if v_resultado <> 'ok' then
    if v_pendencia_id is null then
      insert into pendencia
        (caso_id, origem_estagio, tipo, severidade, sobrepujavel, descricao, documento_id, entidade_id, periodo_id, motivo)
      values (
        p_caso_id, 'reconciliacao',
        case when v_resultado = 'precondicao_nao_satisfeita' then 'precondicao_nao_satisfeita' else 'divergencia_reconciliacao' end::pendencia_tipo,
        'importante', true, v_descricao, v_documento_id, p_entidade_id, p_periodo_id, 'reconciliacao:ativo_passivo_pl'
      )
      returning id into v_pendencia_id;
    else
      update pendencia set descricao = v_descricao where id = v_pendencia_id;
    end if;
  elsif v_pendencia_id is not null then
    -- A divergência anterior deixou de existir (ex.: reextração corrigiu o
    -- número) — fecha a pendência automaticamente. Não é "fato aceito" (não
    -- escreve nenhum número numa base viva), só encerra o sintoma que sumiu.
    update pendencia set estado = 'resolvida', resolvida_em = now(), resolvida_por = 'sistema:reconciliacao'
    where id = v_pendencia_id;
  end if;

  insert into evento_auditoria (ator, acao, entidade_ref, depois)
    values ('sistema:reconciliacao', 'reconciliacao_ativo_passivo_pl', 'reconciliacao:' || v_reconciliacao_id,
            jsonb_build_object('resultado', v_resultado, 'divergencia_abs', v_divergencia_abs));

  return jsonb_build_object(
    'reconciliacao_id', v_reconciliacao_id, 'tipo', 'ativo_passivo_pl',
    'resultado', v_resultado, 'pendencia_id', v_pendencia_id
  );
end;
$$;

-- -----------------------------------------------------------------------------
-- fn_reconciliar_caixa_bp_fluxo — Classe A: Caixa e equivalentes (Balanço) =
-- Saldo final de caixa (Demonstração de Fluxo de Caixa), mesma entidade e
-- período. Pré-condição extra (docs/04: "mesma moeda"): se as duas linhas
-- extraídas trazem `unidade` preenchida e ela diverge (ex.: "R$" vs "R$ mil"),
-- NÃO compara — vira precondição não satisfeita (comparar seria falso-limpo).
-- -----------------------------------------------------------------------------
create or replace function fn_reconciliar_caixa_bp_fluxo(
  p_caso_id       uuid,
  p_entidade_id   uuid,
  p_periodo_id    uuid,
  p_tolerancia_abs numeric default 100,
  p_tolerancia_pct numeric default 0.005
)
returns jsonb
language plpgsql
as $$
declare
  v_doc_balanco_id uuid;
  v_doc_fluxo_id   uuid;
  v_versao_balanco uuid;
  v_versao_fluxo   uuid;
  v_caixa_bp       campo_extraido;
  v_saldo_fluxo    campo_extraido;
  v_precondicoes_ok boolean := true;
  v_resultado      text;
  v_divergencia_abs numeric;
  v_divergencia_pct numeric;
  v_tolerancia_final numeric;
  v_motivo         text;
  v_descricao      text;
  v_reconciliacao_id uuid;
  v_pendencia_id   uuid;
begin
  select d.id into v_doc_balanco_id
  from documento d
  where d.caso_id = p_caso_id and d.tipo_taxonomia = 'BALANCO'
    and (p_entidade_id is null or d.entidade_id = p_entidade_id)
    and (p_periodo_id is null or d.periodo_id = p_periodo_id)
  order by d.criado_em desc limit 1;

  select d.id into v_doc_fluxo_id
  from documento d
  where d.caso_id = p_caso_id and d.tipo_taxonomia = 'FLUXO_CAIXA'
    and (p_entidade_id is null or d.entidade_id = p_entidade_id)
    and (p_periodo_id is null or d.periodo_id = p_periodo_id)
  order by d.criado_em desc limit 1;

  if v_doc_balanco_id is null or v_doc_fluxo_id is null then
    v_precondicoes_ok := false;
    v_motivo := format('Faltam documentos para reconciliar: %s%s ausente para esta entidade/período.',
      case when v_doc_balanco_id is null then 'Balanço Patrimonial' else '' end,
      case when v_doc_balanco_id is null and v_doc_fluxo_id is null then ' e Fluxo de Caixa'
           when v_doc_fluxo_id is null then 'Fluxo de Caixa' else '' end);
  else
    v_versao_balanco := fn_versao_atual(v_doc_balanco_id);
    v_versao_fluxo := fn_versao_atual(v_doc_fluxo_id);

    select * into v_caixa_bp from fn_valor_conceito(v_versao_balanco,
      array['caixa', 'equivalentes'], array['circulante']);
    if v_caixa_bp.id is null then
      select * into v_caixa_bp from fn_valor_conceito(v_versao_balanco,
        array['disponibilidades'], array['circulante']);
    end if;

    select * into v_saldo_fluxo from fn_valor_conceito(v_versao_fluxo,
      array['saldo', 'final'], array['inicial']);
    if v_saldo_fluxo.id is null then
      select * into v_saldo_fluxo from fn_valor_conceito(v_versao_fluxo,
        array['caixa', 'final'], array['inicial']);
    end if;

    if v_caixa_bp.id is null or v_saldo_fluxo.id is null then
      v_precondicoes_ok := false;
      v_motivo := 'Não foi possível localizar, nos campos extraídos, o Caixa/equivalentes do '
                  || 'Balanço e/ou o Saldo final de caixa do Fluxo de Caixa.';
    elsif v_caixa_bp.unidade is not null and v_saldo_fluxo.unidade is not null
      and fn_normalizar_texto(v_caixa_bp.unidade) <> fn_normalizar_texto(v_saldo_fluxo.unidade) then
      v_precondicoes_ok := false;
      v_motivo := format('Unidades divergentes entre os documentos ("%s" vs "%s") — não dá para '
                  || 'comparar os valores com segurança sem risco de falso-limpo.',
                  v_caixa_bp.unidade, v_saldo_fluxo.unidade);
    end if;
  end if;

  if v_precondicoes_ok then
    v_divergencia_abs := abs(v_caixa_bp.valor_num - v_saldo_fluxo.valor_num);
    v_divergencia_pct := case when v_caixa_bp.valor_num <> 0
      then v_divergencia_abs / abs(v_caixa_bp.valor_num) else null end;
    v_tolerancia_final := greatest(p_tolerancia_abs, abs(coalesce(v_caixa_bp.valor_num, 0)) * p_tolerancia_pct);
    v_resultado := case when v_divergencia_abs <= v_tolerancia_final then 'ok' else 'divergente' end;
    v_descricao := format('Caixa no Balanço (%s, "%s") vs Saldo final no Fluxo de Caixa (%s, "%s"): divergência de %s (%s%%).',
      v_caixa_bp.valor_num, v_caixa_bp.chave, v_saldo_fluxo.valor_num, v_saldo_fluxo.chave,
      v_divergencia_abs, round(coalesce(v_divergencia_pct, 0) * 100, 2));
  else
    v_resultado := 'precondicao_nao_satisfeita';
    v_descricao := v_motivo;
  end if;

  insert into reconciliacao
    (caso_id, entidade_id, periodo_id, tipo, classe, fonte_a, fonte_b,
     precondicoes_ok, resultado, divergencia_abs, divergencia_pct, materialidade)
  values (
    p_caso_id, p_entidade_id, p_periodo_id, 'caixa_bp_vs_fluxo', 'A',
    case when v_caixa_bp.id is not null then
      jsonb_build_object('chave', v_caixa_bp.chave, 'valor', v_caixa_bp.valor_num, 'documento_versao_id', v_caixa_bp.documento_versao_id)
    else null end,
    case when v_saldo_fluxo.id is not null then
      jsonb_build_object('chave', v_saldo_fluxo.chave, 'valor', v_saldo_fluxo.valor_num, 'documento_versao_id', v_saldo_fluxo.documento_versao_id)
    else null end,
    v_precondicoes_ok, v_resultado, v_divergencia_abs, v_divergencia_pct,
    jsonb_build_object('tolerancia_abs', p_tolerancia_abs, 'tolerancia_pct', p_tolerancia_pct)
  )
  returning id into v_reconciliacao_id;

  select id into v_pendencia_id from pendencia
  where caso_id = p_caso_id
    and motivo = 'reconciliacao:caixa_bp_fluxo'
    and coalesce(entidade_id, '00000000-0000-0000-0000-000000000000'::uuid)
      = coalesce(p_entidade_id, '00000000-0000-0000-0000-000000000000'::uuid)
    and coalesce(periodo_id, '00000000-0000-0000-0000-000000000000'::uuid)
      = coalesce(p_periodo_id, '00000000-0000-0000-0000-000000000000'::uuid)
    and estado <> 'resolvida'
  limit 1;

  if v_resultado <> 'ok' then
    if v_pendencia_id is null then
      insert into pendencia
        (caso_id, origem_estagio, tipo, severidade, sobrepujavel, descricao, documento_id, entidade_id, periodo_id, motivo)
      values (
        p_caso_id, 'reconciliacao',
        case when v_resultado = 'precondicao_nao_satisfeita' then 'precondicao_nao_satisfeita' else 'divergencia_reconciliacao' end::pendencia_tipo,
        'importante', true, v_descricao, v_doc_balanco_id, p_entidade_id, p_periodo_id, 'reconciliacao:caixa_bp_fluxo'
      )
      returning id into v_pendencia_id;
    else
      update pendencia set descricao = v_descricao where id = v_pendencia_id;
    end if;
  elsif v_pendencia_id is not null then
    update pendencia set estado = 'resolvida', resolvida_em = now(), resolvida_por = 'sistema:reconciliacao'
    where id = v_pendencia_id;
  end if;

  insert into evento_auditoria (ator, acao, entidade_ref, depois)
    values ('sistema:reconciliacao', 'reconciliacao_caixa_bp_fluxo', 'reconciliacao:' || v_reconciliacao_id,
            jsonb_build_object('resultado', v_resultado, 'divergencia_abs', v_divergencia_abs));

  return jsonb_build_object(
    'reconciliacao_id', v_reconciliacao_id, 'tipo', 'caixa_bp_vs_fluxo',
    'resultado', v_resultado, 'pendencia_id', v_pendencia_id
  );
end;
$$;

-- -----------------------------------------------------------------------------
-- fn_reconciliar_por_documento — ponto de entrada único chamado pelo N8N logo
-- após gravar os campos extraídos (E2) de um documento: dispara as checagens
-- de Classe A relevantes ao TIPO do documento recém-processado. Só recebe o
-- documento_id (resolve caso/entidade/período sozinho) para manter o N8N
-- burro/stateless (docs/02).
-- -----------------------------------------------------------------------------
create or replace function fn_reconciliar_por_documento(p_documento_id uuid)
returns jsonb
language plpgsql
as $$
declare
  v_caso_id     uuid;
  v_entidade_id uuid;
  v_periodo_id  uuid;
  v_tipo        text;
  v_checagens   jsonb := '[]'::jsonb;
begin
  select caso_id, entidade_id, periodo_id, tipo_taxonomia
    into v_caso_id, v_entidade_id, v_periodo_id, v_tipo
  from documento where id = p_documento_id;

  if v_caso_id is null then
    return jsonb_build_object('executado', false, 'motivo', 'documento não encontrado');
  end if;

  if v_tipo = 'BALANCO' then
    v_checagens := v_checagens || jsonb_build_array(fn_reconciliar_ativo_passivo_pl(v_caso_id, v_entidade_id, v_periodo_id));
    v_checagens := v_checagens || jsonb_build_array(fn_reconciliar_caixa_bp_fluxo(v_caso_id, v_entidade_id, v_periodo_id));
  elsif v_tipo = 'FLUXO_CAIXA' then
    v_checagens := v_checagens || jsonb_build_array(fn_reconciliar_caixa_bp_fluxo(v_caso_id, v_entidade_id, v_periodo_id));
  end if;

  return jsonb_build_object('executado', true, 'documento_id', p_documento_id, 'checagens', v_checagens);
end;
$$;
