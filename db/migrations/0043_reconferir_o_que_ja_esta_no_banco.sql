-- =============================================================================
-- Migration 0043 — Reaplicar as regras de HOJE sobre o dado que já está no banco
--
-- O QUE OS PRINTS DO v35 MOSTRARAM, e que eu quase diagnostiquei como bug novo.
-- A tela do caso trazia duas pendências:
--
--   1. "PRÉ-CONDIÇÃO — O Balanço foi encontrado, mas nenhum exercício teve os
--      DOIS lados. 2024: falta o Passivo+PL …" — e a MESMA mensagem listava
--      `"PASSIVO E PATRIMÔNIO LÍQUIDO" [entidade: —; período: 31/12/2024]` entre
--      os rótulos que a extração trouxe. Pela própria regra que a 0033 escreveu
--      ali ("se o rótulo certo está nessa lista, o defeito é o padrão de
--      casamento"), isso parece defeito vivo.
--   2. "REVISAR — 4 contas diferentes, na MESMA coluna, vieram com o MESMO valor
--      material (14529)" e outra com 35284 — que são os ATIVOs da Componentes e
--      da holding, iguais ao Passivo+PL por construção contábil.
--
-- SÓ QUE AS DUAS COISAS SÃO EXATAMENTE O QUE A 0034 FECHOU. O cabeçalho dela cita
-- a primeira mensagem palavra por palavra como o defeito que corrigiu, e a
-- segunda é o falso positivo que ela fechou excluindo os totais de grupo do
-- Sinal 1. As regras de hoje não produzem nenhuma das duas.
--
-- O DEFEITO REAL É OUTRO, E É ESTRUTURAL: pendência é ESTADO GRAVADO, e nada no
-- sistema a reavalia quando a regra muda. `fn_reconciliar_por_documento` e as
-- guardas de extração rodam UMA vez, no pipeline, depois da extração — e a
-- extração custa uma chamada de IA. Então uma migration pode corrigir a regra e
-- o portal continua mostrando, por tempo indeterminado, um achado que a regra
-- atual não faria mais. O analista vê defeito corrigido como se fosse corrente,
-- e o pior efeito não é a confusão: é que ele aprende a desconfiar da lista.
--
-- Daqui em diante isso é UMA CHAMADA, e ela NÃO GASTA IA — reaplica as regras de
-- hoje sobre os campos que já estão gravados. Se o achado persistir, é achado de
-- verdade; se sumir, era regra velha.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- fn_avaliar_guardas_extracao — os três sinais, calculados do dado GRAVADO.
--
-- Esta função é a FONTE ÚNICA dos três sinais. `fn_registrar_campos_extraidos` é
-- reemitida mais abaixo para chamá-la em vez de recalcular os limiares inline:
-- duas cópias de "≥ 4 contas repetindo" e "≥ 3 linhas e ≥ 30% abaixo de 0.70"
-- divergiriam, e a que divergisse em silêncio seria justamente a do caminho de
-- reavaliação — a que ninguém olha rodar.
--
-- Sinal 3 fica PARCIAL aqui de propósito: "a chamada falhou" depende do
-- `p_falha_motivo` que só o pipeline conhece e que não é gravado em
-- `campo_extraido`. O que dá para saber do banco é se a versão ficou VAZIA, e é
-- isso que a função devolve.
-- -----------------------------------------------------------------------------
create or replace function fn_avaliar_guardas_extracao(p_documento_versao_id uuid)
returns jsonb
language plpgsql
stable
as $$
declare
  v_n_campos      int;
  v_n_baixa       int;
  v_max_repet     int;
  v_valor_repet   numeric;
  v_rotulos       text[];
begin
  select count(*), count(*) filter (where confianca is not null and confianca < 0.7)
    into v_n_campos, v_n_baixa
  from campo_extraido where documento_versao_id = p_documento_versao_id;

  select valor, n_contas into v_valor_repet, v_max_repet
  from fn_contas_repetindo_valor(p_documento_versao_id);

  -- 0043: os RÓTULOS que repetiram entram no diagnóstico. A pendência do v35
  -- dizia "4 contas diferentes … com o MESMO valor (14529)" e não dizia QUAIS —
  -- e sem os nomes é impossível julgar, da tela, se é alucinação ou identidade
  -- contábil. Precisei abrir o banco para descobrir; ninguém mais deveria.
  if coalesce(v_max_repet, 0) >= 4 then
    select array_agg(distinct ce.chave order by ce.chave) into v_rotulos
    from campo_extraido ce
    where ce.documento_versao_id = p_documento_versao_id
      and ce.valor_num = v_valor_repet;
  end if;

  return jsonb_build_object(
    'n_campos', v_n_campos,
    'padrao_suspeito', coalesce(v_max_repet, 0) >= 4,
    'valor_repetido', v_valor_repet,
    'n_contas_repetindo', coalesce(v_max_repet, 0),
    'rotulos_repetindo', to_jsonb(coalesce(v_rotulos, array[]::text[])),
    'baixa_confianca', v_n_baixa >= 3 and v_n_campos > 0 and v_n_baixa::numeric / v_n_campos >= 0.3,
    'n_baixa_confianca', v_n_baixa,
    'vazia', v_n_campos = 0
  );
end;
$$;

grant execute on function fn_avaliar_guardas_extracao(uuid) to authenticated;

-- -----------------------------------------------------------------------------
-- fn_registrar_campos_extraidos — corpo da 0041 com os três sinais vindo da
-- função acima. NENHUM limiar muda; o que muda é onde eles moram.
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
  v_documento_id       uuid;
  v_caso_id            uuid;
  v_nome_original      text;
  v_pendencia_id       uuid;
  v_guarda_disparou    boolean := false;
  -- 0041: o DIAL manda.
  v_nivel_dial         nivel_autonomia;
  v_limiar             numeric;
  v_auto_permitido     boolean;
  -- 0043: os três sinais, calculados por fn_avaliar_guardas_extracao.
  v_g                  jsonb;
begin
  select ea.nivel_atual, ea.limiar_auto_clear into v_nivel_dial, v_limiar
  from estagio_autonomia ea where ea.estagio = 'extracao_linhas_financeiras';
  -- Sem linha no dial (banco antigo), NADA é auto-aceito. Ausência de configuração
  -- não pode virar permissão — é o default seguro que a doutrina exige.
  v_auto_permitido := v_nivel_dial in ('N2', 'N3') and v_limiar is not null;

  if p_campos is not null and jsonb_typeof(p_campos) = 'array' then
    for v_item in select * from jsonb_array_elements(p_campos)
    loop
      v_valor := case when (v_item->>'valor_num') ~ '^-?\d+(\.\d+)?$' then (v_item->>'valor_num')::numeric else null end;
      v_confianca := case when (v_item->>'confianca') ~ '^-?\d+(\.\d+)?$' then (v_item->>'confianca')::numeric else null end;

      -- 0029: TODA linha entra como 'pendente'. O auto-aceite acontece DEPOIS das
      -- guardas — aceitar aqui era aceitar ANTES de saber se a extração é suspeita.
      v_status_aceite := 'pendente';
      v_aceito_por := null;
      v_aceito_em := null;
      if v_auto_permitido and v_confianca is not null and v_confianca >= v_limiar then
        v_n_auto_aceitos := v_n_auto_aceitos + 1;  -- elegíveis; só viram aceitos se nenhuma guarda disparar
      end if;

      insert into campo_extraido
        (documento_versao_id, chave, valor_texto, valor_num, unidade, moeda, confianca,
         origem_pagina, origem_linha, ordem, nivel_autonomia, secao, secao_canonica, entidade_coluna, periodo_coluna,
         status_aceite, aceito_por, aceito_em)
      values (
        p_documento_versao_id,
        coalesce(v_item->>'chave', '(sem rótulo)'),
        v_item->>'valor_texto',
        v_valor,
        v_item->>'unidade',
        v_item->>'moeda',
        v_confianca,
        case when (v_item->>'origem_pagina') ~ '^\d+$' then (v_item->>'origem_pagina')::int else null end,
        v_item->>'origem_linha',
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
    end loop;
  end if;

  insert into evento_auditoria (ator, acao, entidade_ref, depois)
    values ('sistema:n8n', 'extracao_sombra', 'documento_versao:'||p_documento_versao_id,
            jsonb_build_object('campos', v_count, 'nivel', p_nivel, 'falha_motivo', p_falha_motivo, 'auto_aceitos', v_n_auto_aceitos));

  select d.id, d.caso_id, dv.nome_original into v_documento_id, v_caso_id, v_nome_original
  from documento_versao dv join documento d on d.id = dv.documento_id
  where dv.id = p_documento_versao_id;

  if v_documento_id is null then
    -- 0029: documento_versao inexistente. FK não dispara com `null`, a extração
    -- foi PAGA e os campos não têm onde ser gravados — então o registro vai para
    -- evento_auditoria (append-only, não exige caso) e um warning fica no log.
    insert into evento_auditoria (ator, acao, entidade_ref, depois)
      values ('sistema:n8n', 'extracao_orfa', 'documento_versao:'||coalesce(p_documento_versao_id::text,'null'),
              jsonb_build_object('campos_descartados', v_count, 'falha_motivo', p_falha_motivo,
                                 'porque', 'documento_versao inexistente: campos e motivo nao tinham onde ser gravados'));
    raise warning 'fn_registrar_campos_extraidos: documento_versao % inexistente; % campo(s) e o motivo "%" foram descartados',
      p_documento_versao_id, v_count, coalesce(p_falha_motivo, '(sem motivo)');
    return v_count;
  end if;

  -- 0043: os três sinais saem de UMA função, que o caminho de reavaliação também
  -- usa. Os limiares (≥4 contas repetindo; ≥3 linhas e ≥30% abaixo de 0.70) não
  -- mudaram — mudou o lugar onde eles são escritos, de dois para um.
  v_g := fn_avaliar_guardas_extracao(p_documento_versao_id);

  if v_count > 0 then
    -- ----- Sinal 1 (0013/0022/0034): mesmo valor material repetido em contas ---
    select id into v_pendencia_id from pendencia
      where caso_id = v_caso_id and motivo = 'extracao:padrao_suspeito:' || v_documento_id and estado <> 'resolvida'
      limit 1;
    if (v_g->>'padrao_suspeito')::boolean then
      v_guarda_disparou := true;
      if v_pendencia_id is null then
        insert into pendencia (caso_id, origem_estagio, tipo, severidade, sobrepujavel, descricao, documento_id, motivo)
          values (v_caso_id, 'extracao', 'extracao_padrao_suspeito', 'importante', true,
            format('%s contas diferentes, na MESMA coluna, vieram com o MESMO valor material (%s) — padrão '
                   'típico de fabricação/alucinação, não de dado real. Conferir contra o arquivo original. '
                   'Contas: %s',
                   v_g->>'n_contas_repetindo', round((v_g->>'valor_repetido')::numeric, 2),
                   array_to_string(array(select jsonb_array_elements_text(v_g->'rotulos_repetindo')), '; ')),
            v_documento_id, 'extracao:padrao_suspeito:' || v_documento_id);
      end if;
    elsif v_pendencia_id is not null then
      update pendencia set estado = 'resolvida', resolvida_em = now(), resolvida_por = 'sistema:extracao'
        where id = v_pendencia_id;
    end if;

    -- ----- Sinal 2 (0013): parcela relevante das linhas com confiança baixa ----
    select id into v_pendencia_id from pendencia
      where caso_id = v_caso_id and motivo = 'extracao:baixa_confianca:' || v_documento_id and estado <> 'resolvida'
      limit 1;
    if (v_g->>'baixa_confianca')::boolean then
      v_guarda_disparou := true;
      if v_pendencia_id is null then
        insert into pendencia (caso_id, origem_estagio, tipo, severidade, sobrepujavel, descricao, documento_id, motivo)
          values (v_caso_id, 'extracao', 'extracao_baixa_confianca', 'importante', true,
            format('%s de %s linhas extraídas vieram com confiança abaixo de 70%%. Revisar antes de aceitar.',
                   v_g->>'n_baixa_confianca', v_count),
            v_documento_id, 'extracao:baixa_confianca:' || v_documento_id);
      end if;
    elsif v_pendencia_id is not null then
      update pendencia set estado = 'resolvida', resolvida_em = now(), resolvida_por = 'sistema:extracao'
        where id = v_pendencia_id;
    end if;
  end if;

  -- ----- Sinal 3 (0016/0029): a chamada falhou OU respondeu vazia -------------
  select id into v_pendencia_id from pendencia
    where caso_id = v_caso_id and motivo = 'extracao:falhou:' || v_documento_id and estado <> 'resolvida'
    limit 1;
  if p_falha_motivo is not null or v_count = 0 then
    v_guarda_disparou := true;  -- extração falha/vazia nunca auto-aceita
    if v_pendencia_id is null then
      insert into pendencia (caso_id, origem_estagio, tipo, severidade, sobrepujavel, descricao, documento_id, motivo)
        values (v_caso_id, 'extracao', 'extracao_falhou', 'importante', true,
          format('Extração de "%s" falhou ou veio incompleta (%s linhas gravadas). Motivo: %s',
                 coalesce(v_nome_original, '?'), v_count,
                 coalesce(p_falha_motivo,
                          'a chamada respondeu sem erro, mas não trouxe NENHUMA linha. '
                          'Causa mais comum: formato que o pipeline ainda não converte em texto '
                          '(.xlsx/.docx) — nesses casos a IA recebe um aviso em vez do arquivo.')),
          v_documento_id, 'extracao:falhou:' || v_documento_id);
    end if;
  elsif v_pendencia_id is not null then
    update pendencia set estado = 'resolvida', resolvida_em = now(), resolvida_por = 'sistema:extracao'
      where id = v_pendencia_id;
  end if;

  -- ----- Auto-aceite (0029): DEPOIS das guardas, nunca antes -----------------
  -- Uma guarda que dispara depois do aceite não é guarda, é legenda: a 0027
  -- aceitava dentro do loop e nenhuma guarda revertia, então extração alucinada
  -- (confiança ALTA com valor repetido) entrava como FATO ACEITO. Isso furava a
  -- anti-ancoragem, que é o princípio inegociável do projeto (docs/01, f0/06).
  if v_n_auto_aceitos > 0 and not v_guarda_disparou then
    update campo_extraido
      set status_aceite = 'aceito',
          aceito_por = format('sistema:auto_aceite (dial %s, limiar %s, sem guarda disparada)',
                              v_nivel_dial, v_limiar),
          aceito_em = now()
      where documento_versao_id = p_documento_versao_id
        and confianca >= v_limiar
        and status_aceite = 'pendente';

    insert into decisao (caso_id, tipo, autor, motivo, payload)
      values (v_caso_id, 'aprovacao', 'sistema:auto_aceite',
        format('%s linha(s) auto-aceitas na extração de "%s" — dial %s, limiar %s, nenhuma guarda disparou.',
               v_n_auto_aceitos, coalesce(v_nome_original, '?'), v_nivel_dial, v_limiar),
        jsonb_build_object('documento_id', v_documento_id, 'documento_versao_id', p_documento_versao_id,
                           'n_auto_aceitos', v_n_auto_aceitos));
  elsif v_n_auto_aceitos > 0 then
    insert into evento_auditoria (ator, acao, entidade_ref, depois)
      values ('sistema:auto_aceite', 'auto_aceite_suprimido', 'documento_versao:'||p_documento_versao_id,
              jsonb_build_object('n_elegiveis', v_n_auto_aceitos,
                                 'porque', 'guarda de extracao disparou; linhas seguem pendentes de revisao humana'));
  end if;

  -- 0036: a completude é recalculada AQUI porque este é o único ponto do
  -- pipeline que roda DEPOIS da extração (o E1 chama `Recomputar Completude` em
  -- PARALELO com a extração, então a completude do E1 vê sempre zero linha).
  -- Roda mesmo com v_count = 0: é justamente o caso que interessa.
  perform fn_recomputar_completude(v_caso_id);

  return v_count;
end;
$$;

grant execute on function fn_registrar_campos_extraidos(uuid, jsonb, nivel_autonomia, text) to authenticated;

-- -----------------------------------------------------------------------------
-- fn_reavaliar_guardas_extracao — as guardas, sobre o que já está gravado.
--
-- ABRE o que a regra de hoje abriria e RESOLVE o que ela não abriria mais. Não
-- inventa e não apaga: pendência resolvida aqui fica com `resolvida_por`
-- dizendo que foi reavaliação, não revisão humana.
--
-- Sinal 3 é o único que NÃO reavalia para abrir: "a chamada falhou" mora no
-- `p_falha_motivo` do pipeline, que não está no banco. O que ele faz é RESOLVER
-- a pendência quando a versão passou a ter linhas — o caso do reenvio.
-- -----------------------------------------------------------------------------
create or replace function fn_reavaliar_guardas_extracao(p_documento_versao_id uuid, p_autor text)
returns jsonb
language plpgsql
as $$
declare
  v_g            jsonb;
  v_documento_id uuid;
  v_caso_id      uuid;
  v_pendencia_id uuid;
  v_abertas      text[] := '{}';
  v_resolvidas   text[] := '{}';
begin
  select d.id, d.caso_id into v_documento_id, v_caso_id
  from documento_versao dv join documento d on d.id = dv.documento_id
  where dv.id = p_documento_versao_id;
  if v_documento_id is null then
    return jsonb_build_object('recusado', true,
      'motivo_recusa', 'documento_versao inexistente — nada a reavaliar.');
  end if;

  v_g := fn_avaliar_guardas_extracao(p_documento_versao_id);

  -- ----- Sinal 1 -------------------------------------------------------------
  select id into v_pendencia_id from pendencia
    where caso_id = v_caso_id and motivo = 'extracao:padrao_suspeito:' || v_documento_id and estado <> 'resolvida'
    limit 1;
  if (v_g->>'padrao_suspeito')::boolean then
    if v_pendencia_id is null then
      insert into pendencia (caso_id, origem_estagio, tipo, severidade, sobrepujavel, descricao, documento_id, motivo)
        values (v_caso_id, 'extracao', 'extracao_padrao_suspeito', 'importante', true,
          format('%s contas diferentes, na MESMA coluna, vieram com o MESMO valor material (%s) — padrão '
                 'típico de fabricação/alucinação, não de dado real. Conferir contra o arquivo original. '
                 'Contas: %s',
                 v_g->>'n_contas_repetindo', round((v_g->>'valor_repetido')::numeric, 2),
                 array_to_string(array(select jsonb_array_elements_text(v_g->'rotulos_repetindo')), '; ')),
          v_documento_id, 'extracao:padrao_suspeito:' || v_documento_id);
      v_abertas := v_abertas || 'extracao_padrao_suspeito'::text;
    end if;
  elsif v_pendencia_id is not null then
    update pendencia set estado = 'resolvida', resolvida_em = now(),
                         resolvida_por = p_autor || ' (reavaliação: a regra de hoje não abriria)'
      where id = v_pendencia_id;
    v_resolvidas := v_resolvidas || 'extracao_padrao_suspeito'::text;
  end if;

  -- ----- Sinal 2 -------------------------------------------------------------
  select id into v_pendencia_id from pendencia
    where caso_id = v_caso_id and motivo = 'extracao:baixa_confianca:' || v_documento_id and estado <> 'resolvida'
    limit 1;
  if (v_g->>'baixa_confianca')::boolean then
    if v_pendencia_id is null then
      insert into pendencia (caso_id, origem_estagio, tipo, severidade, sobrepujavel, descricao, documento_id, motivo)
        values (v_caso_id, 'extracao', 'extracao_baixa_confianca', 'importante', true,
          format('%s de %s linhas extraídas vieram com confiança abaixo de 70%%. Revisar antes de aceitar.',
                 v_g->>'n_baixa_confianca', v_g->>'n_campos'),
          v_documento_id, 'extracao:baixa_confianca:' || v_documento_id);
      v_abertas := v_abertas || 'extracao_baixa_confianca'::text;
    end if;
  elsif v_pendencia_id is not null then
    update pendencia set estado = 'resolvida', resolvida_em = now(),
                         resolvida_por = p_autor || ' (reavaliação: a regra de hoje não abriria)'
      where id = v_pendencia_id;
    v_resolvidas := v_resolvidas || 'extracao_baixa_confianca'::text;
  end if;

  -- ----- Sinal 3: só RESOLVE (ver o comentário do cabeçalho) -----------------
  if not (v_g->>'vazia')::boolean then
    select id into v_pendencia_id from pendencia
      where caso_id = v_caso_id and motivo = 'extracao:falhou:' || v_documento_id and estado <> 'resolvida'
      limit 1;
    if v_pendencia_id is not null then
      update pendencia set estado = 'resolvida', resolvida_em = now(),
                           resolvida_por = p_autor || ' (reavaliação: a versão tem linhas)'
        where id = v_pendencia_id;
      v_resolvidas := v_resolvidas || 'extracao_falhou'::text;
    end if;
  end if;

  return jsonb_build_object('documento_versao_id', p_documento_versao_id,
                            'guardas', v_g,
                            'abertas', to_jsonb(v_abertas),
                            'resolvidas', to_jsonb(v_resolvidas));
end;
$$;

grant execute on function fn_reavaliar_guardas_extracao(uuid, text) to authenticated;

-- -----------------------------------------------------------------------------
-- fn_reconferir_caso — reaplica TODAS as regras de hoje no caso. Sem IA.
--
-- Reconciliação A/B por documento, guardas de extração por versão atual, e a
-- completude. É o que separa "achado de verdade" de "achado de regra velha", e é
-- barato: nenhuma chamada externa, nenhum arquivo lido de novo.
--
-- Fica em `evento_auditoria` com o resumo. Reconferir MUDA o que o analista vê
-- (pendência que estava aberta pode fechar), e mudança que ninguém registra é
-- mudança que ninguém consegue explicar depois.
-- -----------------------------------------------------------------------------
create or replace function fn_reconferir_caso(p_caso_id uuid, p_autor text default 'portal:reconferir')
returns jsonb
language plpgsql
as $$
declare
  v_doc          record;
  v_versao       uuid;
  v_n_docs       int := 0;
  v_resolvidas   int := 0;
  v_abertas      int := 0;
  v_r            jsonb;
  v_antes        int;
  v_depois       int;
  v_completude   jsonb;
begin
  if not exists (select 1 from caso where id = p_caso_id) then
    return jsonb_build_object('recusado', true,
      'motivo_recusa', format('Caso %s não existe.', p_caso_id));
  end if;

  select count(*) into v_antes from pendencia where caso_id = p_caso_id and estado <> 'resolvida';

  for v_doc in select id from documento where caso_id = p_caso_id order by criado_em loop
    v_n_docs := v_n_docs + 1;
    -- Reconciliação A/B: as próprias checagens abrem e resolvem pendência, com a
    -- regra de hoje (é o que a 0034 corrigiu e nunca foi reaplicado ao v35).
    perform fn_reconciliar_por_documento(v_doc.id);

    v_versao := fn_versao_atual(v_doc.id);
    if v_versao is not null then
      v_r := fn_reavaliar_guardas_extracao(v_versao, p_autor);
      v_resolvidas := v_resolvidas + coalesce(jsonb_array_length(v_r->'resolvidas'), 0);
      v_abertas := v_abertas + coalesce(jsonb_array_length(v_r->'abertas'), 0);
    end if;
  end loop;

  v_completude := fn_recomputar_completude(p_caso_id);

  select count(*) into v_depois from pendencia where caso_id = p_caso_id and estado <> 'resolvida';

  insert into evento_auditoria (ator, acao, entidade_ref, antes, depois)
    values (p_autor, 'reconferir_caso', 'caso:'||p_caso_id,
            jsonb_build_object('pendencias_abertas', v_antes),
            jsonb_build_object('pendencias_abertas', v_depois, 'documentos', v_n_docs,
                               'guardas_resolvidas', v_resolvidas, 'guardas_abertas', v_abertas));

  return jsonb_build_object(
    'caso_id', p_caso_id,
    'documentos_reconferidos', v_n_docs,
    'pendencias_abertas_antes', v_antes,
    'pendencias_abertas_depois', v_depois,
    'guardas_resolvidas', v_resolvidas,
    'guardas_abertas', v_abertas,
    'completude', v_completude,
    -- O NÚMERO QUE IMPORTA para quem clicou: quantos achados eram de regra velha.
    'achados_de_regra_velha', greatest(v_antes - v_depois, 0));
end;
$$;

comment on function fn_reconferir_caso(uuid, text) is
  'Reaplica as regras de HOJE (reconciliação A/B, guardas de extração, completude) sobre o dado já '
  'gravado, sem gastar chamada de IA. Existe porque pendência é estado gravado e nada a reavaliava '
  'quando uma migration corrigia a regra — o portal mostrava achado corrigido como se fosse '
  'corrente (caso real: as duas pendências do v35 que a 0034 já havia fechado).';

grant execute on function fn_reconferir_caso(uuid, text) to authenticated;
