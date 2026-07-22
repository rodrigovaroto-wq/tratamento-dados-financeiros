-- =============================================================================
-- Migration 0015 — Reconciliação Cruzada, Classe B (E3, segunda fatia)
--
-- Doutrina (docs/04_RECONCILIACAO.md): Classe B = semi-objetiva (agregação/
-- período). Diferente da Classe A (identidade aritmética pura, teto N2), a B
-- compara AGREGADOS de fontes/períodos diferentes — que legitimamente podem
-- não bater ao centavo (competência vs. caixa, faturamento bruto vs. receita
-- reconhecida, recorte de período). Por isso a B fica TRAVADA em N1: banda de
-- materialidade, e qualquer divergência acima do desprezível vira REVISÃO
-- humana (zona cinzenta) — nunca auto-clear, nunca "fato".
--
-- Duas checagens (os dois exemplos canônicos de docs/04):
--   1. Receita da DRE  vs  soma do faturamento mensal (FATURAMENTO_24M).
--   2. Despesa financeira da DRE  vs  juros do mapa de dívida (MAPA_DIVIDA).
--
-- Mesma disciplina de pré-condição da Classe A (docs/02): faltou documento,
-- não deu para casar os rótulos, ou o período não recorta → PENDÊNCIA de
-- precondição, NUNCA um "OK" falso-limpo. Como a extração de FATURAMENTO_24M/
-- MAPA_DIVIDA ainda usa schema genérico de linhas (ver HANDOFF), é esperado
-- que estas checagens caiam em "precondição não satisfeita" com frequência até
-- essa extração ser refinada — é o comportamento honesto, não uma falha.
--
-- Reaproveita a infra da 0009: tabela `reconciliacao`, fn_normalizar_texto,
-- fn_versao_atual, fn_valor_conceito. Casamento chave→conceito é sempre
-- determinístico (normalização + termos), nunca LLM.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- fn_somar_conceito — soma o valor_num de TODAS as linhas de uma versão cujo
-- rótulo (normalizado) contém todos os termos de p_inclui e nenhum de p_exclui.
-- Usado para agregar (ex.: somar todas as linhas de "juros" do mapa de dívida).
-- Retorna 0 e a contagem de linhas casadas (o chamador usa a contagem p/ saber
-- se casou algo — soma 0 com 0 linhas ≠ soma 0 com linhas de fato zeradas).
-- -----------------------------------------------------------------------------
create or replace function fn_somar_conceito(
  p_documento_versao_id uuid,
  p_inclui text[],
  p_exclui text[] default '{}'
)
returns table (soma numeric, n_linhas int)
language sql
stable
as $$
  select coalesce(sum(ce.valor_num), 0)::numeric, count(*)::int
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
    );
$$;

-- -----------------------------------------------------------------------------
-- fn_somar_faturamento_ano — soma as linhas mensais de faturamento de UM ano.
-- As linhas mensais não compartilham uma palavra-chave (cada uma é um mês),
-- então o recorte é pelo ANO no rótulo ("/24", "/2024" ou "2024"), excluindo
-- linhas de total/média/acumulado (que somariam duplicado). p_ano4="2024",
-- p_ano2="24". Retorna a soma e a contagem de meses casados.
-- -----------------------------------------------------------------------------
create or replace function fn_somar_faturamento_ano(
  p_documento_versao_id uuid,
  p_ano4 text,
  p_ano2 text
)
returns table (soma numeric, n_linhas int)
language sql
stable
as $$
  select coalesce(sum(ce.valor_num), 0)::numeric, count(*)::int
  from campo_extraido ce
  where ce.documento_versao_id = p_documento_versao_id
    and ce.valor_num is not null
    and (
      position(p_ano4 in fn_normalizar_texto(ce.chave)) > 0
      or fn_normalizar_texto(ce.chave) ~ ('[/. -]' || p_ano2 || '($|[^0-9])')
    )
    and fn_normalizar_texto(ce.chave) not like '%total%'
    and fn_normalizar_texto(ce.chave) not like '%acumulad%'
    and fn_normalizar_texto(ce.chave) not like '%media%'
    and fn_normalizar_texto(ce.chave) not like '%médi%';
$$;

-- -----------------------------------------------------------------------------
-- Helper interno: registra o resultado de uma checagem Classe B (log em
-- `reconciliacao` + pendência idempotente com auto-resolução). Mesma mecânica
-- da Classe A (0009), fatorada para as duas checagens B reaproveitarem.
--   p_resultado: 'ok' | 'zona_cinzenta' | 'precondicao_nao_satisfeita'
-- 'zona_cinzenta' (B) e 'divergente' (A) geram a MESMA pendência revisável
-- (divergencia_reconciliacao) — a diferença é semântica no log.
-- -----------------------------------------------------------------------------
create or replace function fn_registrar_reconciliacao_b(
  p_caso_id       uuid,
  p_entidade_id   uuid,
  p_periodo_id    uuid,
  p_tipo          text,
  p_documento_id  uuid,
  p_fonte_a       jsonb,
  p_fonte_b       jsonb,
  p_resultado     text,
  p_divergencia_abs numeric,
  p_divergencia_pct numeric,
  p_materialidade jsonb,
  p_descricao     text
)
returns jsonb
language plpgsql
as $$
declare
  v_reconciliacao_id uuid;
  v_pendencia_id     uuid;
  v_motivo           text := 'reconciliacao:' || p_tipo;
begin
  insert into reconciliacao
    (caso_id, entidade_id, periodo_id, tipo, classe, fonte_a, fonte_b,
     precondicoes_ok, resultado, divergencia_abs, divergencia_pct, materialidade)
  values (
    p_caso_id, p_entidade_id, p_periodo_id, p_tipo, 'B', p_fonte_a, p_fonte_b,
    p_resultado <> 'precondicao_nao_satisfeita', p_resultado, p_divergencia_abs, p_divergencia_pct, p_materialidade
  )
  returning id into v_reconciliacao_id;

  select id into v_pendencia_id from pendencia
  where caso_id = p_caso_id and motivo = v_motivo
    and coalesce(entidade_id, '00000000-0000-0000-0000-000000000000'::uuid)
      = coalesce(p_entidade_id, '00000000-0000-0000-0000-000000000000'::uuid)
    and coalesce(periodo_id, '00000000-0000-0000-0000-000000000000'::uuid)
      = coalesce(p_periodo_id, '00000000-0000-0000-0000-000000000000'::uuid)
    and estado <> 'resolvida'
  limit 1;

  if p_resultado <> 'ok' then
    if v_pendencia_id is null then
      insert into pendencia
        (caso_id, origem_estagio, tipo, severidade, sobrepujavel, descricao, documento_id, entidade_id, periodo_id, motivo)
      values (
        p_caso_id, 'reconciliacao',
        case when p_resultado = 'precondicao_nao_satisfeita' then 'precondicao_nao_satisfeita' else 'divergencia_reconciliacao' end::pendencia_tipo,
        'importante', true, p_descricao, p_documento_id, p_entidade_id, p_periodo_id, v_motivo
      )
      returning id into v_pendencia_id;
    else
      update pendencia set descricao = p_descricao where id = v_pendencia_id;
    end if;
  elsif v_pendencia_id is not null then
    update pendencia set estado = 'resolvida', resolvida_em = now(), resolvida_por = 'sistema:reconciliacao'
    where id = v_pendencia_id;
  end if;

  insert into evento_auditoria (ator, acao, entidade_ref, depois)
    values ('sistema:reconciliacao', 'reconciliacao_' || p_tipo, 'reconciliacao:' || v_reconciliacao_id,
            jsonb_build_object('resultado', p_resultado, 'divergencia_abs', p_divergencia_abs));

  return jsonb_build_object(
    'reconciliacao_id', v_reconciliacao_id, 'tipo', p_tipo,
    'resultado', p_resultado, 'pendencia_id', v_pendencia_id
  );
end;
$$;

-- -----------------------------------------------------------------------------
-- Checagem B.1 — Receita da DRE vs soma do faturamento mensal do mesmo ano.
-- Base da materialidade = a receita da DRE. Banda B (mais folgada que a A):
-- piso R$ 50k E 5% da receita. Compara a RECEITA OPERACIONAL BRUTA da DRE com
-- a soma dos meses de faturamento do ano do período da DRE.
-- -----------------------------------------------------------------------------
create or replace function fn_reconciliar_receita_dre_vs_faturamento(
  p_caso_id        uuid,
  p_entidade_id    uuid,
  p_periodo_id     uuid,
  p_tolerancia_abs numeric default 50000,
  p_tolerancia_pct numeric default 0.05
)
returns jsonb
language plpgsql
as $$
declare
  v_doc_dre_id   uuid;
  v_doc_fat_id   uuid;
  v_versao_dre   uuid;
  v_versao_fat   uuid;
  v_receita      campo_extraido;
  v_periodo_ref  text;
  v_ano4         text;
  v_ano2         text;
  v_soma_fat     numeric;
  v_n_meses      int;
  v_resultado    text := 'precondicao_nao_satisfeita';
  v_div_abs      numeric;
  v_div_pct      numeric;
  v_tol_final    numeric;
  v_desc         text;
  v_fonte_a      jsonb;
  v_fonte_b      jsonb;
begin
  select d.id into v_doc_dre_id from documento d
  where d.caso_id = p_caso_id and d.tipo_taxonomia = 'DRE'
    and (p_entidade_id is null or d.entidade_id = p_entidade_id)
    and (p_periodo_id is null or d.periodo_id = p_periodo_id)
  order by d.criado_em desc limit 1;

  select d.id into v_doc_fat_id from documento d
  where d.caso_id = p_caso_id and d.tipo_taxonomia = 'FATURAMENTO_24M'
    and (p_entidade_id is null or d.entidade_id = p_entidade_id or d.entidade_id is null)
  order by d.criado_em desc limit 1;

  if v_doc_dre_id is null or v_doc_fat_id is null then
    v_desc := format('Faltam documentos para reconciliar receita: %s ausente para esta entidade/período.',
      case when v_doc_dre_id is null and v_doc_fat_id is null then 'DRE e Faturamento'
           when v_doc_dre_id is null then 'DRE' else 'Faturamento (24m)' end);
  else
    v_versao_dre := fn_versao_atual(v_doc_dre_id);
    v_versao_fat := fn_versao_atual(v_doc_fat_id);
    select referencia into v_periodo_ref from periodo where id = p_periodo_id;

    -- Ano do período da DRE (aceita "2024", "12M24", "24", "3T24", ...). Tenta
    -- 4 dígitos (19xx/20xx); senão os 2 últimos dígitos do fim da referência.
    v_ano4 := (regexp_match(coalesce(v_periodo_ref, ''), '((?:19|20)[0-9]{2})'))[1];
    if v_ano4 is not null then
      v_ano2 := right(v_ano4, 2);
    else
      v_ano2 := (regexp_match(coalesce(v_periodo_ref, ''), '([0-9]{2})[^0-9]*$'))[1];
      if v_ano2 is not null then v_ano4 := '20' || v_ano2; end if;
    end if;

    select * into v_receita from fn_valor_conceito(v_versao_dre,
      array['receita', 'bruta'], array['liquida', 'deducoes', 'deducao']);

    if v_ano4 is null then
      v_desc := 'Não foi possível identificar o ano do período da DRE para recortar o faturamento mensal.';
    elsif v_receita.id is null then
      v_desc := 'Não foi possível localizar a Receita Operacional Bruta na DRE (rótulos extraídos não bateram).';
    else
      select soma, n_linhas into v_soma_fat, v_n_meses
      from fn_somar_faturamento_ano(v_versao_fat, v_ano4, v_ano2);

      if coalesce(v_n_meses, 0) = 0 then
        v_desc := format('Não encontrei linhas de faturamento do ano %s no documento de faturamento '
          || '(recorte por período não foi possível — depende da extração do faturamento com o mês por linha).', v_ano4);
      else
        v_div_abs := abs(v_receita.valor_num - v_soma_fat);
        v_div_pct := case when v_receita.valor_num <> 0 then v_div_abs / abs(v_receita.valor_num) else null end;
        v_tol_final := greatest(p_tolerancia_abs, abs(v_receita.valor_num) * p_tolerancia_pct);
        v_resultado := case when v_div_abs <= v_tol_final then 'ok' else 'zona_cinzenta' end;
        v_desc := format('Receita Bruta da DRE (%s) vs soma de %s meses de faturamento de %s (%s): '
          || 'divergência de %s (%s%%). Classe B (revisão): faturamento e receita reconhecida podem '
          || 'divergir por competência/recorte — confira antes de concluir.',
          v_receita.valor_num, v_n_meses, v_ano4, v_soma_fat, v_div_abs, round(coalesce(v_div_pct,0)*100, 2));
        v_fonte_a := jsonb_build_object('chave', v_receita.chave, 'valor', v_receita.valor_num, 'documento_versao_id', v_receita.documento_versao_id);
        v_fonte_b := jsonb_build_object('soma_faturamento', v_soma_fat, 'n_meses', v_n_meses, 'ano', v_ano4, 'documento_versao_id', v_versao_fat);
      end if;
    end if;
  end if;

  return fn_registrar_reconciliacao_b(
    p_caso_id, p_entidade_id, p_periodo_id, 'receita_dre_vs_faturamento', coalesce(v_doc_dre_id, v_doc_fat_id),
    v_fonte_a, v_fonte_b, v_resultado, v_div_abs, v_div_pct,
    jsonb_build_object('tolerancia_abs', p_tolerancia_abs, 'tolerancia_pct', p_tolerancia_pct), v_desc);
end;
$$;

-- -----------------------------------------------------------------------------
-- Checagem B.2 — Despesa financeira da DRE vs juros do mapa de dívida.
-- Base da materialidade = a despesa financeira da DRE. Soma as linhas de
-- "juros"/"encargos" do MAPA_DIVIDA (excluindo totais). Mesma banda B.
-- -----------------------------------------------------------------------------
create or replace function fn_reconciliar_despfin_dre_vs_divida(
  p_caso_id        uuid,
  p_entidade_id    uuid,
  p_periodo_id     uuid,
  p_tolerancia_abs numeric default 50000,
  p_tolerancia_pct numeric default 0.05
)
returns jsonb
language plpgsql
as $$
declare
  v_doc_dre_id   uuid;
  v_doc_div_id   uuid;
  v_versao_dre   uuid;
  v_versao_div   uuid;
  v_despfin      campo_extraido;
  v_soma_juros   numeric;
  v_n_juros      int;
  v_resultado    text := 'precondicao_nao_satisfeita';
  v_div_abs      numeric;
  v_div_pct      numeric;
  v_tol_final    numeric;
  v_desc         text;
  v_fonte_a      jsonb;
  v_fonte_b      jsonb;
  v_despfin_abs  numeric;
begin
  select d.id into v_doc_dre_id from documento d
  where d.caso_id = p_caso_id and d.tipo_taxonomia = 'DRE'
    and (p_entidade_id is null or d.entidade_id = p_entidade_id)
    and (p_periodo_id is null or d.periodo_id = p_periodo_id)
  order by d.criado_em desc limit 1;

  select d.id into v_doc_div_id from documento d
  where d.caso_id = p_caso_id and d.tipo_taxonomia = 'MAPA_DIVIDA'
    and (p_entidade_id is null or d.entidade_id = p_entidade_id or d.entidade_id is null)
  order by d.criado_em desc limit 1;

  if v_doc_dre_id is null or v_doc_div_id is null then
    v_desc := format('Faltam documentos para reconciliar despesa financeira: %s ausente.',
      case when v_doc_dre_id is null and v_doc_div_id is null then 'DRE e Mapa de Dívida'
           when v_doc_dre_id is null then 'DRE' else 'Mapa de Dívida' end);
  else
    v_versao_dre := fn_versao_atual(v_doc_dre_id);
    v_versao_div := fn_versao_atual(v_doc_div_id);

    select * into v_despfin from fn_valor_conceito(v_versao_dre,
      array['despesas', 'financeiras'], array['receitas']);

    select soma, n_linhas into v_soma_juros, v_n_juros
    from fn_somar_conceito(v_versao_div, array['juros'], array['total']);
    if coalesce(v_n_juros, 0) = 0 then
      select soma, n_linhas into v_soma_juros, v_n_juros
      from fn_somar_conceito(v_versao_div, array['encargos'], array['total']);
    end if;

    if v_despfin.id is null then
      v_desc := 'Não foi possível localizar a Despesa Financeira na DRE (rótulos extraídos não bateram).';
    elsif coalesce(v_n_juros, 0) = 0 then
      v_desc := 'Não encontrei linhas de juros/encargos no Mapa de Dívida (depende da extração do mapa por linha).';
    else
      -- despesa financeira costuma vir negativa na DRE; compara em módulo.
      v_despfin_abs := abs(v_despfin.valor_num);
      v_div_abs := abs(v_despfin_abs - abs(v_soma_juros));
      v_div_pct := case when v_despfin_abs <> 0 then v_div_abs / v_despfin_abs else null end;
      v_tol_final := greatest(p_tolerancia_abs, v_despfin_abs * p_tolerancia_pct);
      v_resultado := case when v_div_abs <= v_tol_final then 'ok' else 'zona_cinzenta' end;
      v_desc := format('Despesa Financeira da DRE (%s) vs juros do Mapa de Dívida (%s, %s linha(s)): '
        || 'divergência de %s (%s%%). Classe B (revisão): despesa financeira inclui outros encargos além '
        || 'de juros — confira antes de concluir.',
        v_despfin.valor_num, v_soma_juros, v_n_juros, v_div_abs, round(coalesce(v_div_pct,0)*100, 2));
      v_fonte_a := jsonb_build_object('chave', v_despfin.chave, 'valor', v_despfin.valor_num, 'documento_versao_id', v_despfin.documento_versao_id);
      v_fonte_b := jsonb_build_object('soma_juros', v_soma_juros, 'n_linhas', v_n_juros, 'documento_versao_id', v_versao_div);
    end if;
  end if;

  return fn_registrar_reconciliacao_b(
    p_caso_id, p_entidade_id, p_periodo_id, 'despfin_dre_vs_divida', coalesce(v_doc_dre_id, v_doc_div_id),
    v_fonte_a, v_fonte_b, v_resultado, v_div_abs, v_div_pct,
    jsonb_build_object('tolerancia_abs', p_tolerancia_abs, 'tolerancia_pct', p_tolerancia_pct), v_desc);
end;
$$;

-- -----------------------------------------------------------------------------
-- fn_reconciliar_por_documento — redefinida (inclui A da 0009 + B nova). O N8N
-- chama isto após gravar os campos extraídos; dispara as checagens relevantes
-- ao TIPO do documento recém-processado. As checagens B precisam dos DOIS
-- documentos; disparadas por qualquer um dos lados, reaproveitam/auto-resolvem
-- a pendência quando o outro lado chega (idempotência da 0009/0015).
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

  -- Classe A (0009)
  if v_tipo = 'BALANCO' then
    v_checagens := v_checagens || jsonb_build_array(fn_reconciliar_ativo_passivo_pl(v_caso_id, v_entidade_id, v_periodo_id));
    v_checagens := v_checagens || jsonb_build_array(fn_reconciliar_caixa_bp_fluxo(v_caso_id, v_entidade_id, v_periodo_id));
  elsif v_tipo = 'FLUXO_CAIXA' then
    v_checagens := v_checagens || jsonb_build_array(fn_reconciliar_caixa_bp_fluxo(v_caso_id, v_entidade_id, v_periodo_id));
  end if;

  -- Classe B (0015)
  if v_tipo in ('DRE', 'FATURAMENTO_24M') then
    v_checagens := v_checagens || jsonb_build_array(fn_reconciliar_receita_dre_vs_faturamento(v_caso_id, v_entidade_id, v_periodo_id));
  end if;
  if v_tipo in ('DRE', 'MAPA_DIVIDA') then
    v_checagens := v_checagens || jsonb_build_array(fn_reconciliar_despfin_dre_vs_divida(v_caso_id, v_entidade_id, v_periodo_id));
  end if;

  return jsonb_build_object('executado', true, 'documento_id', p_documento_id, 'checagens', v_checagens);
end;
$$;
