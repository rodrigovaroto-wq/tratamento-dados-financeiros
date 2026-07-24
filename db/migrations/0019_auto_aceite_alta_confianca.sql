-- =============================================================================
-- Migration 0019 — Auto-aceite de linhas extraídas com confiança >= 95%
--
-- Pedido explícito do dono (sessão 7 cont.¹⁴): decisão de produto dele, não
-- inferência da IA — ele quer que linhas extraídas com confiança declarada
-- muito alta (>=95%) entrem como FATO automaticamente, sem exigir clique
-- manual em "aceitar" por linha (mecanismo esse que, aliás, ainda nem existe
-- na UI — só `fn_aceitar_extracao`, por documento inteiro).
--
-- Ressalva honesta (registrada aqui, não escondida): isto sobe a autonomia da
-- extração de N0 (sombra) para um N2 (auto-clear) BOUNDED — sem o golden-set
-- que `docs/01_DOUTRINA_DE_AUTONOMIA.md` normalmente exige antes de subir o
-- teto de autonomia de um estágio interpretativo. A `confianca` usada aqui é
-- a autoavaliação do PRÓPRIO modelo por linha — não foi validada contra gabarito
-- humano. Ainda assim é uma decisão explícita e registrada (não silenciosa):
-- cada auto-aceite grava `decisao`(tipo='aprovacao', autor='sistema:auto_aceite')
-- + `evento_auditoria`, exatamente como um aceite humano registraria — dá pra
-- auditar/reverter. Recomendação para o time: acompanhar a taxa de erro nas
-- linhas auto-aceitas por uma janela e ajustar o limiar (hoje 0.95, hardcoded
-- em `fn_registrar_campos_extraidos`) se a precisão real ficar abaixo do
-- esperado.
--
-- Duas partes:
--   1. `fn_registrar_campos_extraidos` (mesma assinatura de 0017): ao inserir
--      cada linha, já grava `status_aceite='aceito'`/`aceito_por`/`aceito_em`
--      quando `confianca >= 0.95`. Registra UM `decisao`+`evento_auditoria`
--      por chamada (resumindo quantas linhas foram auto-aceitas), não um por
--      linha — evita explosão de registros num documento com centenas de
--      contas.
--   2. Backfill: linhas JÁ gravadas antes desta migration, com confiança
--      >=95% e ainda pendentes, são promovidas a aceitas agora — o dono pediu
--      "habilite", não "só dali pra frente". Um `decisao` por CASO afetado
--      (a tabela exige caso_id), resumindo a promoção retroativa.
-- =============================================================================

create or replace function fn_registrar_campos_extraidos(
  p_documento_versao_id uuid,
  p_campos jsonb,
  p_nivel nivel_autonomia default 'N0',
  p_falha_motivo text default null
)
returns int
language plpgsql
as $$
declare
  v_count            int := 0;
  v_item             jsonb;
  v_valor             numeric;
  v_confianca          numeric;
  v_status_aceite      text;
  v_aceito_por         text;
  v_aceito_em          timestamptz;
  v_n_auto_aceitos     int := 0;
  v_valores_nao_zero   numeric[] := '{}';
  v_n_baixa_confianca  int := 0;
  v_max_repeticoes     int := 0;
  v_valor_repetido      numeric;
  v_documento_id       uuid;
  v_caso_id            uuid;
  v_nome_original      text;
  v_pendencia_id       uuid;
begin
  if p_campos is not null and jsonb_typeof(p_campos) = 'array' then
    for v_item in select * from jsonb_array_elements(p_campos)
    loop
      v_valor := case when (v_item->>'valor_num') ~ '^-?\d+(\.\d+)?$' then (v_item->>'valor_num')::numeric else null end;
      v_confianca := case when (v_item->>'confianca') ~ '^-?\d+(\.\d+)?$' then (v_item->>'confianca')::numeric else null end;

      -- Auto-aceite (>=95%, pedido do dono cont.¹⁴): grava já como aceito,
      -- em vez de pendente — mesmo padrão de fn_aceitar_extracao (0011), só
      -- que automático, feito na hora da extração.
      if v_confianca is not null and v_confianca >= 0.95 then
        v_status_aceite := 'aceito';
        v_aceito_por := 'sistema:auto_aceite (confiança >=95%)';
        v_aceito_em := now();
        v_n_auto_aceitos := v_n_auto_aceitos + 1;
      else
        v_status_aceite := 'pendente';
        v_aceito_por := null;
        v_aceito_em := null;
      end if;

      insert into campo_extraido
        (documento_versao_id, chave, valor_texto, valor_num, unidade, confianca,
         origem_pagina, origem_linha, nivel_autonomia, secao, secao_canonica, entidade_coluna, periodo_coluna,
         status_aceite, aceito_por, aceito_em)
      values (
        p_documento_versao_id,
        coalesce(v_item->>'chave', '(sem rótulo)'),
        v_item->>'valor_texto',
        v_valor,
        v_item->>'unidade',
        v_confianca,
        case when (v_item->>'origem_pagina') ~ '^\d+$' then (v_item->>'origem_pagina')::int else null end,
        v_item->>'origem_linha',
        p_nivel,
        v_item->>'secao',
        v_item->>'secao_canonica',
        v_item->>'entidade_coluna',
        v_item->>'periodo_coluna',
        v_status_aceite,
        v_aceito_por,
        v_aceito_em
      );
      v_count := v_count + 1;

      if v_valor is not null and v_valor <> 0 then
        v_valores_nao_zero := array_append(v_valores_nao_zero, v_valor);
      end if;
      if v_confianca is not null and v_confianca < 0.7 then
        v_n_baixa_confianca := v_n_baixa_confianca + 1;
      end if;
    end loop;
  end if;

  insert into evento_auditoria (ator, acao, entidade_ref, depois)
    values ('sistema:n8n', 'extracao_sombra', 'documento_versao:'||p_documento_versao_id,
            jsonb_build_object('campos', v_count, 'nivel', p_nivel, 'falha_motivo', p_falha_motivo, 'auto_aceitos', v_n_auto_aceitos));

  select d.id, d.caso_id, dv.nome_original into v_documento_id, v_caso_id, v_nome_original
  from documento_versao dv join documento d on d.id = dv.documento_id
  where dv.id = p_documento_versao_id;

  if v_documento_id is null then
    return v_count; -- nunca deveria acontecer (FK), mas não trava a extração por causa da guarda
  end if;

  if v_n_auto_aceitos > 0 then
    insert into decisao (caso_id, tipo, autor, motivo, payload)
      values (v_caso_id, 'aprovacao', 'sistema:auto_aceite',
        format('%s linha(s) auto-aceitas por confiança >=95%% na extração de "%s".', v_n_auto_aceitos, coalesce(v_nome_original, '?')),
        jsonb_build_object('documento_id', v_documento_id, 'documento_versao_id', p_documento_versao_id, 'n_auto_aceitos', v_n_auto_aceitos));
  end if;

  if v_count > 0 then
    -- ----- Sinal 1 (0013): mesmo valor não-zero repetido em muitas contas -----
    select v.valor, count(*) into v_valor_repetido, v_max_repeticoes
    from unnest(v_valores_nao_zero) as v(valor)
    group by v.valor
    order by count(*) desc
    limit 1;

    select id into v_pendencia_id from pendencia
      where caso_id = v_caso_id and motivo = 'extracao:padrao_suspeito:' || p_documento_versao_id and estado <> 'resolvida'
      limit 1;
    if coalesce(v_max_repeticoes, 0) >= 4 then
      if v_pendencia_id is null then
        insert into pendencia (caso_id, origem_estagio, tipo, severidade, sobrepujavel, descricao, documento_id, motivo)
          values (v_caso_id, 'extracao', 'extracao_padrao_suspeito', 'importante', true,
            format('%s contas diferentes vieram com o MESMO valor extraído (%s) — padrão típico de fabricação/'
                   'alucinação, não de dado real. Conferir a extração contra o arquivo original antes de aceitar.',
                   v_max_repeticoes, round(v_valor_repetido, 2)),
            v_documento_id, 'extracao:padrao_suspeito:' || p_documento_versao_id);
      end if;
    elsif v_pendencia_id is not null then
      update pendencia set estado = 'resolvida', resolvida_em = now(), resolvida_por = 'sistema:extracao'
        where id = v_pendencia_id;
    end if;

    -- ----- Sinal 2 (0013): parcela relevante das linhas com confiança baixa -----
    select id into v_pendencia_id from pendencia
      where caso_id = v_caso_id and motivo = 'extracao:baixa_confianca:' || p_documento_versao_id and estado <> 'resolvida'
      limit 1;
    if v_n_baixa_confianca >= 3 and v_n_baixa_confianca::numeric / v_count >= 0.3 then
      if v_pendencia_id is null then
        insert into pendencia (caso_id, origem_estagio, tipo, severidade, sobrepujavel, descricao, documento_id, motivo)
          values (v_caso_id, 'extracao', 'extracao_baixa_confianca', 'importante', true,
            format('%s de %s linhas extraídas vieram com confiança abaixo de 70%%. Revisar antes de aceitar.',
                   v_n_baixa_confianca, v_count),
            v_documento_id, 'extracao:baixa_confianca:' || p_documento_versao_id);
      end if;
    elsif v_pendencia_id is not null then
      update pendencia set estado = 'resolvida', resolvida_em = now(), resolvida_por = 'sistema:extracao'
        where id = v_pendencia_id;
    end if;
  end if;

  -- ----- Sinal 3 (0016): a própria chamada de extração falhou/veio truncada -----
  select id into v_pendencia_id from pendencia
    where caso_id = v_caso_id and motivo = 'extracao:falhou:' || p_documento_versao_id and estado <> 'resolvida'
    limit 1;
  if p_falha_motivo is not null then
    if v_pendencia_id is null then
      insert into pendencia (caso_id, origem_estagio, tipo, severidade, sobrepujavel, descricao, documento_id, motivo)
        values (v_caso_id, 'extracao', 'extracao_falhou', 'importante', true,
          format('Extração de "%s" falhou ou veio incompleta (%s linhas gravadas). Motivo: %s',
                 coalesce(v_nome_original, '?'), v_count, p_falha_motivo),
          v_documento_id, 'extracao:falhou:' || p_documento_versao_id);
    end if;
  elsif v_pendencia_id is not null then
    update pendencia set estado = 'resolvida', resolvida_em = now(), resolvida_por = 'sistema:extracao'
      where id = v_pendencia_id;
  end if;

  return v_count;
end;
$$;

-- -----------------------------------------------------------------------------
-- Backfill: linhas já gravadas ANTES desta migration, com confiança >=95% e
-- ainda pendentes, são promovidas agora (o dono pediu "habilite", não "só
-- dali pra frente"). Um `decisao` por CASO afetado.
-- -----------------------------------------------------------------------------
do $$
declare
  v_caso record;
  v_n     int;
begin
  for v_caso in
    select d.caso_id, count(*) as n
    from campo_extraido ce
    join documento_versao dv on dv.id = ce.documento_versao_id
    join documento d on d.id = dv.documento_id
    where ce.confianca >= 0.95 and ce.status_aceite <> 'aceito'
    group by d.caso_id
  loop
    update campo_extraido ce set
      status_aceite = 'aceito',
      aceito_por = 'sistema:auto_aceite (retroativo, confiança >=95%)',
      aceito_em = now()
    from documento_versao dv, documento d
    where ce.documento_versao_id = dv.id
      and dv.documento_id = d.id
      and d.caso_id = v_caso.caso_id
      and ce.confianca >= 0.95
      and ce.status_aceite <> 'aceito';

    get diagnostics v_n = row_count;

    insert into decisao (caso_id, tipo, autor, motivo, payload)
      values (v_caso.caso_id, 'aprovacao', 'sistema:auto_aceite',
        format('%s linha(s) já extraídas com confiança >=95%% promovidas retroativamente a aceitas (migration 0019).', v_n),
        jsonb_build_object('backfill', true, 'n_auto_aceitos', v_n));

    insert into evento_auditoria (ator, acao, entidade_ref, depois)
      values ('sistema:auto_aceite', 'auto_aceite_retroativo', 'caso:'||v_caso.caso_id,
        jsonb_build_object('n_auto_aceitos', v_n));
  end loop;
end $$;
