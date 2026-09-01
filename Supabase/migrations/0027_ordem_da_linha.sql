-- =============================================================================
-- Migration 0027 — ORDEM da linha no documento
--
-- Achado no teste v28: o Ativo Circulante da VT Logística saiu 7.254 onde o
-- documento diz 3.961. "Contas a Receber" (3.293) foi somada JUNTO com os seus
-- componentes "Fretes a receber" (3.562) e "(-) PECLD" (−269).
--
-- As duas detecções de subtotal que já existiam no export não pegam esse caso:
-- uma exige que alguma linha declare `secao` com o nome do subtotal (a extração
-- daquele arquivo anotou a seção de TOPO em todas), e a outra exige que o valor
-- bata com a soma dos irmãos da MESMA seção (ali os irmãos são o circulante
-- inteiro). Como o documento também não trouxe a linha de total, não havia nem
-- linha de conferência: o número errado não tinha como ser percebido.
--
-- O sinal que sobra é o que TODA demonstração publicada dá — o subtotal vem
-- impresso IMEDIATAMENTE ANTES dos seus componentes. Isso exige saber a ordem,
-- e a ordem não era persistida: `campo_extraido` não tinha coluna para ela e a
-- consulta do export não ordenava (a ordem de chegada do PostgREST é arbitrária).
--
-- Assinatura da função INALTERADA (o N8N chama do mesmo jeito); só o JSON de
-- entrada passa a aceitar `ordem` por linha. Extração antiga fica com `null` e
-- nada muda para ela — só reprocessamento traz o ganho.
-- =============================================================================

alter table campo_extraido add column if not exists ordem int;

comment on column campo_extraido.ordem is
  'Posição 0-based da linha no documento, como o arquivo a imprime. Permite '
  'reconhecer subtotal impresso acima dos seus componentes (teste v28). '
  'null em extração feita antes da 0027.';

-- Índice para a consulta do export, que passa a ordenar por (versão, ordem).
create index if not exists idx_campo_extraido_versao_ordem
  on campo_extraido (documento_versao_id, ordem);

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
         origem_pagina, origem_linha, ordem, nivel_autonomia, secao, secao_canonica, entidade_coluna, periodo_coluna,
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
        -- ordem: posição da linha NO DOCUMENTO. É o sinal que permite reconhecer
        -- um subtotal impresso ACIMA dos seus componentes.
        case when (v_item->>'ordem') ~ '^\d+$' then (v_item->>'ordem')::int else null end,
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
    -- Sinal 1 refinado (0022): conta quantas contas DISTINTAS repetem o MESMO
    -- valor DENTRO DA MESMA COLUNA (entidade × período) e só considera valores
    -- MATERIAIS. Antes a contagem era sobre o lote inteiro: num documento
    -- combinado (5 empresas × 2 anos) o mesmo valor legitimamente reaparece em
    -- cada coluna, e valores pequenos (18, 40, 180) coincidem à toa — o teste
    -- v24 gerou 5 alertas falsos, que é o pior resultado possível numa guarda
    -- (o analista aprende a ignorar o aviso).
    select ce.valor_num, count(distinct ce.chave)
      into v_valor_repetido, v_max_repeticoes
    from campo_extraido ce
    where ce.documento_versao_id = p_documento_versao_id
      and ce.valor_num is not null
      and ce.valor_num <> 0
      and abs(ce.valor_num) >= (
        select greatest(coalesce(max(abs(c2.valor_num)), 0) * 0.01, 1)
        from campo_extraido c2 where c2.documento_versao_id = p_documento_versao_id
      )
    group by ce.valor_num, coalesce(ce.entidade_coluna, ''), coalesce(ce.periodo_coluna, '')
    order by count(distinct ce.chave) desc
    limit 1;

    select id into v_pendencia_id from pendencia
      where caso_id = v_caso_id and motivo = 'extracao:padrao_suspeito:' || p_documento_versao_id and estado <> 'resolvida'
      limit 1;
    if coalesce(v_max_repeticoes, 0) >= 4 then
      if v_pendencia_id is null then
        insert into pendencia (caso_id, origem_estagio, tipo, severidade, sobrepujavel, descricao, documento_id, motivo)
          values (v_caso_id, 'extracao', 'extracao_padrao_suspeito', 'importante', true,
            format('%s contas diferentes, na MESMA coluna, vieram com o MESMO valor material (%s) — padrão '
                   'típico de fabricação/alucinação, não de dado real. Conferir contra o arquivo original.',
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
