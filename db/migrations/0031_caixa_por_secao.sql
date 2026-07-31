-- 0031 — Reconciliação do caixa: usar a SEÇÃO, que o documento já declarava
--
-- Segunda das duas pendências de PRÉ-CONDIÇÃO que apareceram no teste v31:
-- "Balanço e Fluxo de Caixa presentes, mas não foi possível localizar o
-- Caixa/Disponível do Balanço e/ou o Saldo final de caixa do Fluxo."
--
-- A causa não era rótulo ruim nem extração falha: `fn_valor_conceito_col` exige que
-- TODOS os termos apareçam como substring de `ce.chave`, e **nunca olha `ce.secao`**.
-- Contra os rótulos reais do book (test-data/book-vertentes/dados.py), duas das
-- cinco empresas não casavam nenhuma das quatro tentativas — e para uma delas o
-- dado necessário estava ali, na seção:
--
--   VT Logística: chave "Bancos Conta Movimento", secao "Disponível"
--   SPE:          chave "Caixa" (as tentativas exigiam 'equivalentes' ou 'bancos')
--
-- Sem os dois lados, `continue` => `v_n = 0` => pendência de pré-condição. Ou seja:
-- a reconciliação reclamava de dado que ela mesma não tinha procurado onde estava.
--
-- Introduz `fn_valor_conceito_secao` (gêmea de `fn_valor_conceito_col`, casando
-- contra `ce.secao` em vez de `ce.chave`) e a usa como fallback na cascata do caixa,
-- DEPOIS das buscas por rótulo. A ordem importa: rótulo é mais específico que seção,
-- e um documento que declara as duas coisas deve escolher a linha, não o grupo.
--
-- Não mexe em nenhuma outra checagem: `fn_valor_conceito_col` continua idêntica, e
-- só a cascata do caixa ganhou tentativas. Idempotente.

begin;

-- Gêmea de `fn_valor_conceito_col`, casando contra `ce.secao`. Separada em vez de
-- um parâmetro novo na original de propósito: a original é chamada de muitos
-- lugares e mudar a assinatura dela obrigaria a revisar todos — risco sem retorno.
create or replace function fn_valor_conceito_secao(
  p_documento_versao_id uuid,
  p_inclui text[],
  p_exclui text[] default '{}',
  p_entidade_coluna text default null,
  p_periodo_coluna text default null
)
returns campo_extraido
language sql
stable
as $$
  select ce.*
  from campo_extraido ce
  where ce.documento_versao_id = p_documento_versao_id
    and ce.valor_num is not null
    and ce.secao is not null
    and p_entidade_coluna is distinct from E'\x01'
    and p_periodo_coluna is distinct from E'\x01'
    and (p_entidade_coluna is null
         or fn_normalizar_texto(ce.entidade_coluna) = fn_normalizar_texto(p_entidade_coluna))
    and (p_periodo_coluna is null
         or fn_normalizar_texto(ce.periodo_coluna) = fn_normalizar_texto(p_periodo_coluna))
    and not exists (
      select 1 from unnest(p_inclui) as termo
      where fn_normalizar_texto(ce.secao) not like '%' || fn_normalizar_texto(termo) || '%'
    )
    -- O EXCLUI olha os dois: seção que casou não salva um rótulo que o exclui
    -- proíbe (ex.: seção "Disponível" com rótulo "Total do Ativo Circulante").
    and not exists (
      select 1 from unnest(p_exclui) as termo
      where fn_normalizar_texto(ce.secao) like '%' || fn_normalizar_texto(termo) || '%'
         or fn_normalizar_texto(ce.chave) like '%' || fn_normalizar_texto(termo) || '%'
    )
  order by coalesce(ce.confianca, 0) desc, length(ce.chave) asc
  limit 1;
$$;

comment on function fn_valor_conceito_secao(uuid, text[], text[], text, text) is
  'Como fn_valor_conceito_col, mas casa contra ce.secao. Fallback para rótulo que não '
  'nomeia o conceito ("Bancos Conta Movimento" debaixo de "Disponível") — 0031.';

-- Cascata do caixa com os fallbacks por seção. Corpo da 0023, três tentativas a mais.
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
  v_doc_bp    uuid;
  v_doc_fx    uuid;
  v_ver_bp    uuid;
  v_ver_fx    uuid;
  v_col_ent   text;
  v_ano       int;
  v_col_per   text;
  v_caixa     campo_extraido;
  v_saldo     campo_extraido;
  v_motivo    text;
  v_a         numeric;
  v_b         numeric;
  v_div_abs   numeric;
  v_tol       numeric;
  v_resultado text := 'ok';
  v_partes    text[] := '{}';
  v_n         int := 0;
  v_pior_abs  numeric;
  v_pior_pct  numeric;
  v_fonte_a   jsonb;
  v_fonte_b   jsonb;
begin
  v_doc_bp := fn_documento_balanco(p_caso_id, p_entidade_id, p_periodo_id);
  v_doc_fx := fn_documento_por_tipo(p_caso_id, p_entidade_id, p_periodo_id, 'FLUXO_CAIXA');

  if v_doc_bp is null or v_doc_fx is null then
    -- Fato comum e legítimo: nem toda empresa do grupo entrega DFC. Quem cobra
    -- documento faltante é o checklist do Kit Básico, não a fila de revisão.
    return fn_registrar_reconciliacao(p_caso_id, p_entidade_id, p_periodo_id,
      'caixa_bp_fluxo', 'A', coalesce(v_doc_bp, v_doc_fx), null, null,
      'documento_ausente', null, null,
      jsonb_build_object('tolerancia_abs', p_tolerancia_abs, 'tolerancia_pct', p_tolerancia_pct),
      format('Sem par para reconciliar: %s não foi entregue para esta entidade/período.',
        case when v_doc_bp is null and v_doc_fx is null then 'Balanço e Fluxo de Caixa'
             when v_doc_bp is null then 'Balanço Patrimonial' else 'Fluxo de Caixa' end));
  end if;

  v_ver_bp  := fn_versao_atual(v_doc_bp);
  v_ver_fx  := fn_versao_atual(v_doc_fx);
  v_col_ent := fn_coluna_entidade(v_ver_bp, p_entidade_id);

  foreach v_ano in array fn_anos_alvo(p_periodo_id) loop
    v_col_per := case when v_ano is null then null
                      else fn_coluna_periodo_do_ano(v_ver_bp, v_ano) end;

    -- Caixa no Balanço. "Disponível"/"Disponibilidades" é o rótulo mais comum em
    -- demonstração brasileira detalhada — a DFC do book chega a dizer, na nota,
    -- que o saldo final "confere com a rubrica Disponível do balanço".
    select * into v_caixa from fn_valor_conceito_col(v_ver_bp,
      array['caixa', 'equivalentes'], array['circulante', 'fluxo', 'inicio', 'inicial'],
      v_col_ent, v_col_per);
    if v_caixa.id is null then
      select * into v_caixa from fn_valor_conceito_col(v_ver_bp,
        array['disponibilidades'], array['circulante'], v_col_ent, v_col_per);
    end if;
    if v_caixa.id is null then
      select * into v_caixa from fn_valor_conceito_col(v_ver_bp,
        array['disponivel'], array['circulante'], v_col_ent, v_col_per);
    end if;
    if v_caixa.id is null then
      select * into v_caixa from fn_valor_conceito_col(v_ver_bp,
        array['caixa', 'bancos'], array['circulante'], v_col_ent, v_col_per);
    end if;
    -- 0031: as quatro tentativas acima olham SÓ `ce.chave`, e é isso que produzia a
    -- pendência "não foi possível localizar o Caixa/Disponível" no teste v31. Contra
    -- os rótulos reais do book:
    --
    --   Holding      "Caixa e Equivalentes de Caixa"  -> casa (1)
    --   Metalúrgica  "Disponibilidades"               -> casa (2)
    --   Componentes  "Numerário Disponível"           -> casa (3)
    --   SPE          "Caixa"                          -> NÃO casava: (1) exige
    --                                                   'equivalentes' e (4) exige 'bancos'
    --   VT Logística "Bancos Conta Movimento"         -> NÃO casava nenhuma
    --
    -- E o dado que faltava ESTAVA no documento: a `secao` da VT Logística diz
    -- "Disponível". A função nunca olhou `ce.secao`.
    if v_caixa.id is null then
      -- "Caixa" puro (SPE). Vem depois das combinações de dois termos, que são
      -- mais específicas — assim um documento que tem as duas coisas escolhe a
      -- linha certa em vez da mais genérica.
      select * into v_caixa from fn_valor_conceito_col(v_ver_bp,
        array['caixa'], array['circulante', 'fluxo', 'inicio', 'inicial', 'equivalente'],
        v_col_ent, v_col_per);
    end if;
    if v_caixa.id is null then
      -- Pela SEÇÃO do documento: é o que resolve "Bancos Conta Movimento".
      select * into v_caixa from fn_valor_conceito_secao(v_ver_bp,
        array['disponivel'], array['circulante'], v_col_ent, v_col_per);
    end if;
    if v_caixa.id is null then
      select * into v_caixa from fn_valor_conceito_secao(v_ver_bp,
        array['caixa'], array['circulante', 'fluxo'], v_col_ent, v_col_per);
    end if;

    -- Saldo final na DFC (a coluna de período da DFC é a dela, não a do BP).
    v_col_per := case when v_ano is null then null
                      else fn_coluna_periodo_do_ano(v_ver_fx, v_ano) end;
    select * into v_saldo from fn_valor_conceito_col(v_ver_fx,
      array['saldo', 'final'], array['inicial', 'inicio'], null, v_col_per);
    if v_saldo.id is null then
      select * into v_saldo from fn_valor_conceito_col(v_ver_fx,
        array['caixa', 'final'], array['inicial', 'inicio'], null, v_col_per);
    end if;
    if v_saldo.id is null then
      select * into v_saldo from fn_valor_conceito_col(v_ver_fx,
        array['caixa', 'fim'], array['inicial', 'inicio'], null, v_col_per);
    end if;

    if v_caixa.id is null or v_saldo.id is null then
      continue;
    end if;

    v_motivo := fn_motivo_escala_incomparavel(v_caixa.unidade, v_saldo.unidade,
      'o Caixa do Balanço', 'o Saldo final do Fluxo de Caixa');
    if v_motivo is not null then
      return fn_registrar_reconciliacao(p_caso_id, p_entidade_id, p_periodo_id,
        'caixa_bp_fluxo', 'A', v_doc_bp, null, null, 'precondicao_nao_satisfeita', null, null,
        jsonb_build_object('tolerancia_abs', p_tolerancia_abs, 'tolerancia_pct', p_tolerancia_pct),
        v_motivo);
    end if;

    v_a := fn_valor_em_base(v_caixa.valor_num, v_caixa.unidade);
    v_b := fn_valor_em_base(v_saldo.valor_num, v_saldo.unidade);
    v_n := v_n + 1;
    v_div_abs := abs(v_a - v_b);
    v_tol := greatest(p_tolerancia_abs * coalesce(fn_fator_escala(v_caixa.unidade), 1),
                      abs(v_a) * p_tolerancia_pct);
    if v_div_abs > v_tol then
      v_resultado := 'divergente';
      v_partes := v_partes || format('%s: Caixa no Balanço %s ("%s") vs Saldo final na DFC %s ("%s") — diferença de %s',
        coalesce(v_ano::text, 'período do documento'), v_caixa.valor_num, v_caixa.chave,
        v_saldo.valor_num, v_saldo.chave, v_div_abs);
      if v_pior_abs is null or v_div_abs > v_pior_abs then
        v_pior_abs := v_div_abs;
        v_pior_pct := case when v_a <> 0 then v_div_abs / abs(v_a) end;
      end if;
    else
      v_partes := v_partes || format('%s: confere (%s "%s" = %s "%s")',
        coalesce(v_ano::text, 'período do documento'), v_caixa.valor_num, v_caixa.chave,
        v_saldo.valor_num, v_saldo.chave);
    end if;
    v_fonte_a := jsonb_build_object('chave', v_caixa.chave, 'valor', v_caixa.valor_num,
      'unidade', v_caixa.unidade, 'documento_versao_id', v_ver_bp);
    v_fonte_b := jsonb_build_object('chave', v_saldo.chave, 'valor', v_saldo.valor_num,
      'unidade', v_saldo.unidade, 'documento_versao_id', v_ver_fx);
  end loop;

  if v_n = 0 then
    return fn_registrar_reconciliacao(p_caso_id, p_entidade_id, p_periodo_id,
      'caixa_bp_fluxo', 'A', v_doc_bp, null, null, 'precondicao_nao_satisfeita', null, null,
      jsonb_build_object('tolerancia_abs', p_tolerancia_abs, 'tolerancia_pct', p_tolerancia_pct),
      'Balanço e Fluxo de Caixa presentes, mas não foi possível localizar o Caixa/Disponível do '
      || 'Balanço e/ou o Saldo final de caixa do Fluxo (rótulos extraídos não bateram).');
  end if;

  return fn_registrar_reconciliacao(p_caso_id, p_entidade_id, p_periodo_id,
    'caixa_bp_fluxo', 'A', v_doc_bp, v_fonte_a, v_fonte_b, v_resultado, v_pior_abs, v_pior_pct,
    jsonb_build_object('tolerancia_abs', p_tolerancia_abs, 'tolerancia_pct', p_tolerancia_pct,
                       'anos_checados', v_n),
    format('Caixa do Balanço vs Saldo final do Fluxo de Caixa em %s ano(s): %s.',
           v_n, array_to_string(v_partes, '; ')));
end;
$$;

commit;
