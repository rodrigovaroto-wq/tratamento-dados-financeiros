-- 0021 — Classe B: pré-condição de UNIDADE/ESCALA entre os dois documentos
-- =============================================================================
-- Achado na auditoria de endurecimento (2026-07-24): as duas checagens da
-- Classe B (0015) comparam valores de DOIS documentos DIFERENTES —
--   B.1 Receita Bruta da DRE  vs  soma do FATURAMENTO_24M
--   B.2 Despesa Financeira da DRE  vs  juros do MAPA_DIVIDA
-- — mas, ao contrário da Classe A (`fn_reconciliar_caixa_bp_fluxo`, 0009), NÃO
-- conferiam a unidade/escala das duas fontes. Se a DRE está em milhares e o
-- mapa de dívida em unidades (caso concreto: cada arquivo vem de um sistema
-- diferente, com cabeçalho de escala próprio), a comparação é entre grandezas
-- 1000x distintas: o resultado é uma "divergência" gigante sem sentido — ou,
-- pior, um falso "ok" quando os números por acaso se aproximam.
--
-- Fix: mesma pré-condição da Classe A, aplicada às duas checagens B. Quando as
-- duas escalas estão preenchidas e são diferentes, o resultado é
-- `precondicao_nao_satisfeita` com motivo explícito (nunca um número comparado
-- às cegas). Escala ausente de um dos lados não bloqueia (não há o que
-- comparar) — segue o mesmo critério conservador da 0009.
--
-- Mesmas assinaturas de 0015 (o N8N chama via fn_reconciliar_por_documento,
-- que não muda). Depende da normalização de escala feita na extração
-- (n8n/lib/extract.mjs → 'unidade' | 'milhar' | 'milhao'): com o vocabulário
-- canônico, "R$ mil" e "milhares de reais" deixam de parecer escalas
-- diferentes, então esta checagem só dispara em divergência REAL de escala.

-- -----------------------------------------------------------------------------
-- fn_unidade_predominante — a escala de uma versão de documento, inferida das
-- próprias linhas extraídas. A `unidade` é gravada por linha (herdada do
-- cabeçalho do documento na extração), então a escala do documento é a mais
-- frequente entre as linhas que a declaram. Linhas não-monetárias (percentuais,
-- lucro por ação) têm `unidade` null por construção (ver `ehLinhaNaoMonetaria`
-- em n8n/lib/extract.mjs) e portanto não distorcem a moda.
-- Retorna null quando nenhuma linha declara escala — "não sei", nunca um chute.
-- -----------------------------------------------------------------------------
create or replace function fn_unidade_predominante(p_documento_versao_id uuid)
returns text
language sql
stable
as $$
  select ce.unidade
  from campo_extraido ce
  where ce.documento_versao_id = p_documento_versao_id
    and ce.unidade is not null
    and length(trim(ce.unidade)) > 0
  group by ce.unidade
  order by count(*) desc, ce.unidade
  limit 1;
$$;

comment on function fn_unidade_predominante(uuid) is
  'Escala predominante (unidade) das linhas extraídas de uma versão de documento; null quando nenhuma linha declara escala.';

-- -----------------------------------------------------------------------------
-- Helper: as duas escalas são comparáveis? Devolve o motivo do bloqueio quando
-- NÃO são (para o chamador usar como descrição da pendência), ou null quando a
-- comparação pode seguir. Espelha a semântica da Classe A (0009): só bloqueia
-- quando AS DUAS estão preenchidas e divergem.
-- -----------------------------------------------------------------------------
create or replace function fn_motivo_escala_incomparavel(
  p_unidade_a text,
  p_unidade_b text,
  p_rotulo_a  text,
  p_rotulo_b  text
)
returns text
language sql
immutable
as $$
  select case
    when p_unidade_a is null or p_unidade_b is null then null
    when fn_normalizar_texto(p_unidade_a) = fn_normalizar_texto(p_unidade_b) then null
    else format(
      'Escalas divergentes entre os documentos: %s está em "%s" e %s está em "%s". Comparar os '
      || 'valores assim seria comparar grandezas com fator de 1000x de diferença — corrija a '
      || 'escala na extração (ou confirme o cabeçalho de cada documento) antes de reconciliar.',
      p_rotulo_a, p_unidade_a, p_rotulo_b, p_unidade_b)
  end;
$$;

-- -----------------------------------------------------------------------------
-- B.1 — Receita Bruta da DRE vs soma do faturamento mensal do ano.
-- Corpo idêntico ao de 0015 + a pré-condição de escala.
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
  v_unid_fat     text;
  v_motivo_esc   text;
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

      -- Escala das duas fontes (0021): a da linha de receita da DRE contra a
      -- predominante do documento de faturamento.
      v_unid_fat := fn_unidade_predominante(v_versao_fat);
      v_motivo_esc := fn_motivo_escala_incomparavel(
        v_receita.unidade, v_unid_fat, 'a Receita Bruta da DRE', 'o Faturamento mensal');

      if coalesce(v_n_meses, 0) = 0 then
        v_desc := format('Não encontrei linhas de faturamento do ano %s no documento de faturamento '
          || '(recorte por período não foi possível — depende da extração do faturamento com o mês por linha).', v_ano4);
      elsif v_motivo_esc is not null then
        v_desc := v_motivo_esc; -- segue 'precondicao_nao_satisfeita'
      else
        v_div_abs := abs(v_receita.valor_num - v_soma_fat);
        v_div_pct := case when v_receita.valor_num <> 0 then v_div_abs / abs(v_receita.valor_num) else null end;
        v_tol_final := greatest(p_tolerancia_abs, abs(v_receita.valor_num) * p_tolerancia_pct);
        v_resultado := case when v_div_abs <= v_tol_final then 'ok' else 'zona_cinzenta' end;
        v_desc := format('Receita Bruta da DRE (%s) vs soma de %s meses de faturamento de %s (%s): '
          || 'divergência de %s (%s%%). Classe B (revisão): faturamento e receita reconhecida podem '
          || 'divergir por competência/recorte — confira antes de concluir.',
          v_receita.valor_num, v_n_meses, v_ano4, v_soma_fat, v_div_abs, round(coalesce(v_div_pct,0)*100, 2));
        v_fonte_a := jsonb_build_object('chave', v_receita.chave, 'valor', v_receita.valor_num, 'unidade', v_receita.unidade, 'documento_versao_id', v_receita.documento_versao_id);
        v_fonte_b := jsonb_build_object('soma_faturamento', v_soma_fat, 'n_meses', v_n_meses, 'ano', v_ano4, 'unidade', v_unid_fat, 'documento_versao_id', v_versao_fat);
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
-- B.2 — Despesa Financeira da DRE vs juros do Mapa de Dívida.
-- Corpo idêntico ao de 0015 + a pré-condição de escala.
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
  v_unid_div     text;
  v_motivo_esc   text;
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

    -- Escala das duas fontes (0021).
    v_unid_div := fn_unidade_predominante(v_versao_div);
    v_motivo_esc := fn_motivo_escala_incomparavel(
      v_despfin.unidade, v_unid_div, 'a Despesa Financeira da DRE', 'o Mapa de Dívida');

    if v_despfin.id is null then
      v_desc := 'Não foi possível localizar a Despesa Financeira na DRE (rótulos extraídos não bateram).';
    elsif coalesce(v_n_juros, 0) = 0 then
      v_desc := 'Não encontrei linhas de juros/encargos no Mapa de Dívida (depende da extração do mapa por linha).';
    elsif v_motivo_esc is not null then
      v_desc := v_motivo_esc; -- segue 'precondicao_nao_satisfeita'
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
      v_fonte_a := jsonb_build_object('chave', v_despfin.chave, 'valor', v_despfin.valor_num, 'unidade', v_despfin.unidade, 'documento_versao_id', v_despfin.documento_versao_id);
      v_fonte_b := jsonb_build_object('soma_juros', v_soma_juros, 'n_linhas', v_n_juros, 'unidade', v_unid_div, 'documento_versao_id', v_versao_div);
    end if;
  end if;

  return fn_registrar_reconciliacao_b(
    p_caso_id, p_entidade_id, p_periodo_id, 'despfin_dre_vs_divida', coalesce(v_doc_dre_id, v_doc_div_id),
    v_fonte_a, v_fonte_b, v_resultado, v_div_abs, v_div_pct,
    jsonb_build_object('tolerancia_abs', p_tolerancia_abs, 'tolerancia_pct', p_tolerancia_pct), v_desc);
end;
$$;
