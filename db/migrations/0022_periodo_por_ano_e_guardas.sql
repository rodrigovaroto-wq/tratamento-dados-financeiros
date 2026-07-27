-- 0022 — Período comparado por CONJUNTO DE ANOS + reconciliação tolerante a
--        granularidade + guarda de padrão suspeito sem falso positivo
-- =============================================================================
-- Rodada de correções a partir do "teste v24" (book Vertentes, 14 documentos de
-- um grupo com 5 empresas em distress). Três problemas de dado real:
--
-- 1) PENDÊNCIA DE PERÍODO FALSA (terceira vez que aparece). A 0020 passou a
--    comparar por forma canônica, o que resolveu "2025-01-15" × "15/01/2025" e
--    "2025" × "12M25". Mas continuou acusando divergência em pares que são o
--    MESMO período com GRANULARIDADE diferente:
--      registrado "anual 2025"                    × diagnóstico "data-base 2025-12-31"
--      registrado "multi janeiro/2024 a dezembro/2025" × diagnóstico "outro L24M"
--    Um balanço "em 31/12/2025" É o exercício de 2025; um mapa de dívida com
--    data-base no fim do ano idem. Agora a comparação é pelo CONJUNTO DE ANOS:
--    só vira pendência quando os dois lados declaram anos e os anos DIFEREM
--    (2024 × 2025 continua divergindo, como deve).
--
-- 2) RECONCILIAÇÃO PEDINDO DOCUMENTO QUE EXISTE. As checagens A/B casam os
--    documentos por (entidade, periodo_id) exato. Como cada documento do grupo
--    entrou com a granularidade que o próprio arquivo declara (o balanço
--    comparativo virou "multi 24,25"; o mapa de dívida "data-base 2025-12-31";
--    o faturamento "janeiro/2024 a dezembro/2025"), os periodo_id nunca
--    coincidem — e o resultado foram 11 pré-condições "Balanço/DRE/Fluxo de
--    Caixa ausente para esta entidade/período" com TODOS os documentos
--    presentes. Isto é o caso NORMAL num mandato real, não a exceção.
--    `fn_reconciliar_por_documento` passa a tentar também os períodos
--    COMPATÍVEIS (anos que se intersectam), parando na primeira checagem que
--    sai da pré-condição. As 4 checagens não mudam — a tolerância fica no
--    ponto de entrada, que é o único lugar que o N8N chama.
--
-- 3) GUARDA DE PADRÃO SUSPEITO COM FALSO POSITIVO. O sinal contava contas com o
--    mesmo valor no LOTE INTEIRO; num documento combinado (5 empresas × 2 anos)
--    o mesmo valor reaparece legitimamente em cada coluna, e valores pequenos
--    coincidem à toa — 5 alertas falsos no v24 (18,00 / 40,00 / 180,00 …).
--    Agora conta repetições DENTRO da mesma coluna (entidade × período) e só
--    olha valores materiais. Uma guarda que grita à toa é pior que não ter
--    guarda: ensina o analista a ignorar o aviso.

-- -----------------------------------------------------------------------------
-- fn_anos_periodo — conjunto de anos (4 dígitos, ordenado) implícito num
-- período, seja qual for a notação. Vazio quando a referência não ancora ano
-- nenhum (ex.: "L24M" — últimos 24 meses, sem dizer quais).
-- -----------------------------------------------------------------------------
create or replace function fn_anos_periodo(p_tipo text, p_ref text)
returns int[]
language plpgsql
immutable
as $$
declare
  canonico text := fn_periodo_canonico(p_tipo, p_ref);
  anos int[] := '{}';
  tok text;
begin
  if canonico is null then return anos; end if;
  -- anos de 4 dígitos explícitos (cobre ISO, ano isolado, listas já expandidas)
  foreach tok in array regexp_split_to_array(canonico, '[^0-9]+') loop
    if tok ~ '^(19|20)[0-9]{2}$' then
      anos := anos || (tok)::int;
    end if;
  end loop;
  select array_agg(distinct a order by a) into anos from unnest(anos) a;
  return coalesce(anos, '{}'::int[]);
end;
$$;

comment on function fn_anos_periodo(text, text) is
  'Conjunto ordenado de anos implícito num período (qualquer notação). Vazio quando a referência não ancora ano.';

-- -----------------------------------------------------------------------------
-- fn_periodos_equivalentes — os dois períodos falam do MESMO tempo?
-- Critério: mesmo conjunto de anos. Quando um dos lados não ancora ano nenhum,
-- devolve TRUE (não há como afirmar divergência — e afirmar à toa é o que
-- poluía a fila de revisão).
-- -----------------------------------------------------------------------------
create or replace function fn_periodos_equivalentes(
  p_tipo_a text, p_ref_a text, p_tipo_b text, p_ref_b text
)
returns boolean
language sql
immutable
as $$
  select case
    when fn_periodo_canonico(p_tipo_a, p_ref_a) is null
      or fn_periodo_canonico(p_tipo_b, p_ref_b) is null then true
    when fn_periodo_canonico(p_tipo_a, p_ref_a) = fn_periodo_canonico(p_tipo_b, p_ref_b) then true
    when cardinality(fn_anos_periodo(p_tipo_a, p_ref_a)) = 0
      or cardinality(fn_anos_periodo(p_tipo_b, p_ref_b)) = 0 then true
    else fn_anos_periodo(p_tipo_a, p_ref_a) = fn_anos_periodo(p_tipo_b, p_ref_b)
  end;
$$;

-- -----------------------------------------------------------------------------
-- fn_periodos_compativeis — para CASAR documentos na reconciliação: os anos se
-- intersectam? (mais frouxo que equivalência: um balanço "multi 24,25" e uma
-- DRE "12M25" tratam do mesmo exercício de 2025 e devem poder ser reconciliados).
-- -----------------------------------------------------------------------------
create or replace function fn_periodos_compativeis(p_periodo_a uuid, p_periodo_b uuid)
returns boolean
language plpgsql
stable
as $$
declare
  ta text; ra text; tb text; rb text; aa int[]; ab int[];
begin
  if p_periodo_a is null or p_periodo_b is null then return true; end if;
  if p_periodo_a = p_periodo_b then return true; end if;
  select tipo, referencia into ta, ra from periodo where id = p_periodo_a;
  select tipo, referencia into tb, rb from periodo where id = p_periodo_b;
  aa := fn_anos_periodo(ta, ra);
  ab := fn_anos_periodo(tb, rb);
  if cardinality(aa) = 0 or cardinality(ab) = 0 then return true; end if;
  return aa && ab; -- intersecção de arrays
end;
$$;

-- -----------------------------------------------------------------------------
-- fn_registrar_diagnostico — mesma assinatura de 0010/0020. Único bloco alterado:
-- o de PERÍODO, que passa a comparar por conjunto de anos (ver acima).
-- -----------------------------------------------------------------------------
create or replace function fn_registrar_diagnostico(
  p_documento_id        uuid,
  p_documento_versao_id uuid,
  p_entidade_nome        text,
  p_tipo_confirma        boolean,
  p_tipo_sugerido        text,
  p_periodo_tipo         text,
  p_periodo_referencia   text,
  p_legibilidade         legibilidade,
  p_nota_legibilidade    text,
  p_resumo               text,
  p_justificativa        text
)
returns jsonb
language plpgsql
as $$
declare
  v_caso_id            uuid;
  v_entidade_id         uuid;
  v_tipo_atual          text;
  v_periodo_id          uuid;
  v_periodo_tipo_atual  text;
  v_periodo_ref_atual   text;
  v_entidade_atual_nome text;
  v_pendencia_id        uuid;
  v_entidade_criada     boolean := false;
begin
  select caso_id, entidade_id, tipo_taxonomia, periodo_id
    into v_caso_id, v_entidade_id, v_tipo_atual, v_periodo_id
  from documento where id = p_documento_id;

  if v_caso_id is null then
    return jsonb_build_object('executado', false, 'motivo', 'documento não encontrado');
  end if;

  if v_periodo_id is not null then
    select tipo, referencia into v_periodo_tipo_atual, v_periodo_ref_atual from periodo where id = v_periodo_id;
  end if;

  -- ----- Entidade: preenche a lacuna se ainda vazia; senão só confere -----
  if p_entidade_nome is not null and length(trim(p_entidade_nome)) > 0 then
    if v_entidade_id is null then
      select id into v_entidade_id from entidade
        where caso_id = v_caso_id and lower(razao_social) = lower(trim(p_entidade_nome)) limit 1;
      if v_entidade_id is null then
        insert into entidade (caso_id, razao_social) values (v_caso_id, trim(p_entidade_nome))
          returning id into v_entidade_id;
      end if;
      update documento set entidade_id = v_entidade_id where id = p_documento_id;
      v_entidade_criada := true;
    else
      select razao_social into v_entidade_atual_nome from entidade where id = v_entidade_id;
      select id into v_pendencia_id from pendencia
        where caso_id = v_caso_id and motivo = 'diagnostico:entidade:' || p_documento_id and estado <> 'resolvida'
        limit 1;
      if lower(trim(coalesce(v_entidade_atual_nome, ''))) <> lower(trim(p_entidade_nome)) then
        if v_pendencia_id is null then
          insert into pendencia (caso_id, origem_estagio, tipo, severidade, sobrepujavel, descricao, documento_id, motivo)
            values (v_caso_id, 'diagnostico', 'entidade_incorreta', 'importante', true,
              format('Diagnóstico de conteúdo sugere entidade "%s", mas o documento está registrado com "%s".',
                     p_entidade_nome, coalesce(v_entidade_atual_nome, '(nenhuma)')),
              p_documento_id, 'diagnostico:entidade:' || p_documento_id);
        end if;
      elsif v_pendencia_id is not null then
        update pendencia set estado = 'resolvida', resolvida_em = now(), resolvida_por = 'sistema:diagnostico'
          where id = v_pendencia_id;
      end if;
    end if;
  end if;

  -- ----- Tipo: confere contra o que já está registrado -----
  select id into v_pendencia_id from pendencia
    where caso_id = v_caso_id and motivo = 'diagnostico:tipo:' || p_documento_id and estado <> 'resolvida'
    limit 1;
  if coalesce(p_tipo_confirma, true) = false
     or (p_tipo_sugerido is not null and p_tipo_sugerido is distinct from v_tipo_atual) then
    if v_pendencia_id is null then
      insert into pendencia (caso_id, origem_estagio, tipo, severidade, sobrepujavel, descricao, documento_id, motivo)
        values (v_caso_id, 'diagnostico', 'tipo_incorreto', 'importante', true,
          format('Diagnóstico de conteúdo sugere tipo "%s" (documento está registrado como "%s"). %s',
                 coalesce(p_tipo_sugerido, '?'), coalesce(v_tipo_atual, '(nenhum)'), coalesce(p_justificativa, '')),
          p_documento_id, 'diagnostico:tipo:' || p_documento_id);
    end if;
  elsif v_pendencia_id is not null then
    update pendencia set estado = 'resolvida', resolvida_em = now(), resolvida_por = 'sistema:diagnostico'
      where id = v_pendencia_id;
  end if;

  -- ----- Período: confere contra o registrado, por FORMA CANÔNICA (0020) -----
  -- Só diverge quando os períodos são canonicamente distintos — notações
  -- diferentes do MESMO período não geram mais pendência falsa.
  select id into v_pendencia_id from pendencia
    where caso_id = v_caso_id and motivo = 'diagnostico:periodo:' || p_documento_id and estado <> 'resolvida'
    limit 1;
  -- 0022: compara pelo CONJUNTO DE ANOS. "anual 2025" e "data-base 2025-12-31"
  -- são o MESMO exercício com granularidade diferente — não é divergência, é
  -- refinamento; acusar isso enchia a fila de revisão de pendência falsa.
  -- Divergência real (2024 × 2025) continua virando pendência.
  if p_periodo_referencia is not null
     and not fn_periodos_equivalentes(p_periodo_tipo, p_periodo_referencia,
                                      v_periodo_tipo_atual, v_periodo_ref_atual) then
    if v_pendencia_id is null then
      insert into pendencia (caso_id, origem_estagio, tipo, severidade, sobrepujavel, descricao, documento_id, motivo)
        values (v_caso_id, 'diagnostico', 'periodo_incorreto', 'importante', true,
          format('Diagnóstico de conteúdo sugere período "%s %s" (documento está registrado com "%s %s").',
                 p_periodo_tipo, p_periodo_referencia, coalesce(v_periodo_tipo_atual, '?'), coalesce(v_periodo_ref_atual, '(nenhum)')),
          p_documento_id, 'diagnostico:periodo:' || p_documento_id);
    end if;
  elsif v_pendencia_id is not null then
    update pendencia set estado = 'resolvida', resolvida_em = now(), resolvida_por = 'sistema:diagnostico'
      where id = v_pendencia_id;
  end if;

  -- ----- Legibilidade real do arquivo -----
  update documento_versao set legibilidade = coalesce(p_legibilidade, legibilidade), nota_legibilidade = p_nota_legibilidade
    where id = p_documento_versao_id;

  select id into v_pendencia_id from pendencia
    where caso_id = v_caso_id and motivo = 'diagnostico:legibilidade:' || p_documento_id and estado <> 'resolvida'
    limit 1;
  if p_legibilidade = 'ilegivel' then
    if v_pendencia_id is null then
      insert into pendencia (caso_id, origem_estagio, tipo, severidade, sobrepujavel, descricao, documento_id, motivo)
        values (v_caso_id, 'diagnostico', 'arquivo_ilegivel', 'importante', true,
          coalesce(p_nota_legibilidade, 'Arquivo sinalizado como ilegível pelo diagnóstico de conteúdo.'),
          p_documento_id, 'diagnostico:legibilidade:' || p_documento_id);
    end if;
  elsif v_pendencia_id is not null then
    update pendencia set estado = 'resolvida', resolvida_em = now(), resolvida_por = 'sistema:diagnostico'
      where id = v_pendencia_id;
  end if;

  -- ----- Resumo (nunca apaga um resumo anterior com uma resposta vazia) -----
  update documento set resumo = coalesce(p_resumo, resumo) where id = p_documento_id;

  insert into evento_auditoria (ator, acao, entidade_ref, depois)
    values ('sistema:diagnostico', 'diagnostico_documento', 'documento:'||p_documento_id,
      jsonb_build_object(
        'entidade', p_entidade_nome, 'tipo_confirma', p_tipo_confirma, 'tipo_sugerido', p_tipo_sugerido,
        'periodo_tipo', p_periodo_tipo, 'periodo_referencia', p_periodo_referencia,
        'legibilidade', p_legibilidade, 'resumo', p_resumo, 'justificativa', p_justificativa));

  return jsonb_build_object('executado', true, 'documento_id', p_documento_id, 'entidade_id', v_entidade_id,
    'entidade_criada', v_entidade_criada);
end;
$$;

-- -----------------------------------------------------------------------------
-- fn_registrar_campos_extraidos — mesma assinatura de 0017/0019. Único bloco
-- alterado: o Sinal 1 da guarda (padrão suspeito), agora por coluna + material.
-- -----------------------------------------------------------------------------
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

-- -----------------------------------------------------------------------------
-- fn_reconciliar_por_documento — mesma assinatura de 0015. Agora TOLERANTE À
-- GRANULARIDADE do período: além do período do próprio documento, tenta os
-- períodos COMPATÍVEIS do caso (anos que se intersectam), parando na primeira
-- checagem que sai da pré-condição. As 4 checagens A/B não mudam — a tolerância
-- fica aqui, no único ponto que o N8N chama.
--
-- Por que isso importa: num mandato real cada arquivo declara a granularidade
-- que quer (balanço comparativo "24,25", DRE "12M25", mapa de dívida com
-- data-base "2025-12-31", faturamento "janeiro/2024 a dezembro/2025"). Casar
-- por periodo_id exato fazia a reconciliação dizer "Balanço ausente para esta
-- entidade/período" com o balanço ali, presente e extraído (11 pré-condições
-- falsas no teste v24). Como as pendências são idempotentes por
-- `motivo='reconciliacao:<tipo>'`, a tentativa que dá certo AUTO-RESOLVE a
-- pendência aberta pela tentativa anterior.
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
  v_periodos    uuid[];
  v_per         uuid;
  v_res         jsonb;

begin
  select caso_id, entidade_id, periodo_id, tipo_taxonomia
    into v_caso_id, v_entidade_id, v_periodo_id, v_tipo
  from documento where id = p_documento_id;

  if v_caso_id is null then
    return jsonb_build_object('executado', false, 'motivo', 'documento não encontrado');
  end if;

  -- Candidatos: o período do próprio documento primeiro, depois os compatíveis
  -- (mesmos anos), em ordem estável.
  select array_agg(p.id order by (p.id = v_periodo_id) desc, p.referencia)
    into v_periodos
  from periodo p
  where p.caso_id = v_caso_id
    and (p.id = v_periodo_id or fn_periodos_compativeis(p.id, v_periodo_id));
  if v_periodos is null or cardinality(v_periodos) = 0 then
    v_periodos := array[v_periodo_id];
  end if;

  -- Classe A (0009)
  if v_tipo in ('BALANCO', 'BALANCETE', 'COMBINADO') then
    foreach v_per in array v_periodos loop
      v_res := fn_reconciliar_ativo_passivo_pl(v_caso_id, v_entidade_id, v_per);
      exit when coalesce(v_res->>'resultado', '') <> 'precondicao_nao_satisfeita';
    end loop;
    v_checagens := v_checagens || jsonb_build_array(v_res);
  end if;
  if v_tipo in ('BALANCO', 'BALANCETE', 'COMBINADO', 'FLUXO_CAIXA') then
    foreach v_per in array v_periodos loop
      v_res := fn_reconciliar_caixa_bp_fluxo(v_caso_id, v_entidade_id, v_per);
      exit when coalesce(v_res->>'resultado', '') <> 'precondicao_nao_satisfeita';
    end loop;
    v_checagens := v_checagens || jsonb_build_array(v_res);
  end if;

  -- Classe B (0015/0021)
  if v_tipo in ('DRE', 'FATURAMENTO_24M') then
    foreach v_per in array v_periodos loop
      v_res := fn_reconciliar_receita_dre_vs_faturamento(v_caso_id, v_entidade_id, v_per);
      exit when coalesce(v_res->>'resultado', '') <> 'precondicao_nao_satisfeita';
    end loop;
    v_checagens := v_checagens || jsonb_build_array(v_res);
  end if;
  if v_tipo in ('DRE', 'MAPA_DIVIDA') then
    foreach v_per in array v_periodos loop
      v_res := fn_reconciliar_despfin_dre_vs_divida(v_caso_id, v_entidade_id, v_per);
      exit when coalesce(v_res->>'resultado', '') <> 'precondicao_nao_satisfeita';
    end loop;
    v_checagens := v_checagens || jsonb_build_array(v_res);
  end if;

  return jsonb_build_object('executado', true, 'documento_id', p_documento_id, 'checagens', v_checagens);
end;
$$;

-- ---------------------------------------------------------------------------
-- As QUATRO checagens A/B, redefinidas com a MESMA lógica e assinatura — a
-- única mudança é o LOOKUP do documento, que passa a aceitar períodos
-- COMPATÍVEIS (anos que se intersectam) além do período exato.
--
-- Por que dentro de cada checagem e não no ponto de entrada: cada checagem
-- procura DOIS documentos que podem estar em granularidades DIFERENTES (o
-- balanço comparativo em "24,25" e o fluxo de caixa em "2025"). Tentar a
-- checagem inteira com um período por vez nunca acha os dois ao mesmo tempo —
-- foi o que o teste mostrou. A tolerância tem de estar em cada lookup.
-- ---------------------------------------------------------------------------

-- fn_reconciliar_ativo_passivo_pl: 1 lookup(s) de documento relaxado(s).
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
    and (p_periodo_id is null or d.periodo_id = p_periodo_id or fn_periodos_compativeis(d.periodo_id, p_periodo_id))
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

-- fn_reconciliar_caixa_bp_fluxo: 2 lookup(s) de documento relaxado(s).
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
    and (p_periodo_id is null or d.periodo_id = p_periodo_id or fn_periodos_compativeis(d.periodo_id, p_periodo_id))
  order by d.criado_em desc limit 1;

  select d.id into v_doc_fluxo_id
  from documento d
  where d.caso_id = p_caso_id and d.tipo_taxonomia = 'FLUXO_CAIXA'
    and (p_entidade_id is null or d.entidade_id = p_entidade_id)
    and (p_periodo_id is null or d.periodo_id = p_periodo_id or fn_periodos_compativeis(d.periodo_id, p_periodo_id))
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

-- fn_reconciliar_receita_dre_vs_faturamento: 1 lookup(s) de documento relaxado(s).
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
    and (p_periodo_id is null or d.periodo_id = p_periodo_id or fn_periodos_compativeis(d.periodo_id, p_periodo_id))
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

-- fn_reconciliar_despfin_dre_vs_divida: 1 lookup(s) de documento relaxado(s).
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
    and (p_periodo_id is null or d.periodo_id = p_periodo_id or fn_periodos_compativeis(d.periodo_id, p_periodo_id))
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
