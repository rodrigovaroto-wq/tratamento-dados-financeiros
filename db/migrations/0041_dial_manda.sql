-- =============================================================================
-- Migration 0041 — O dial de autonomia volta a ser estado do sistema
--
-- A CONTRADIÇÃO QUE ISTO FECHA. `estagio_autonomia` nasce na 0001 com
-- `nivel_atual`/`teto`, é semeada na 0002, e o comentário da própria tabela diz:
-- "Nível é estado do sistema, não constante de código (docs/01)".
--
-- Na prática, até aqui:
--   • `grep -rl estagio_autonomia portal/src n8n` não retornava NADA — a tabela
--     não tinha um único leitor;
--   • o dial de `extracao_linhas_financeiras` dizia **N0** — sombra, "roda,
--     registra, NÃO influencia decisão" (docs/01);
--   • e `fn_registrar_campos_extraidos` auto-aceitava toda linha com confiança
--     >= **0.95 hardcoded**, o que a faz virar FATO no export.
--
-- O sistema declarava uma coisa e fazia outra. O cabeçalho da 0019 registra isso
-- com todas as letras ("sobe a extração de N0 para um N2 bounded, sem o
-- golden-set que docs/01 normalmente exige") — mas o dial no banco nunca foi
-- mudado, então quem consultasse o estado do sistema leria N0.
--
-- O QUE MUDA, E O QUE NÃO MUDA. Por decisão do dono: o dial passa a DECLARAR N2 e
-- o comportamento de hoje continua idêntico. Não é uma mudança de autonomia — é a
-- autonomia que já existia parando de ficar enterrada no corpo de uma função.
-- Baixar para N0 (desligando o auto-aceite) passa a ser UMA CHAMADA, sem migration
-- e sem deploy.
--
-- E `decisao_tipo` tem o valor 'mudanca_dial' desde a 0001, sem nenhum uso, ainda
-- que docs/01 diga que "toda subida de nível é uma decisão versionada e
-- reversível". A partir daqui, é.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- O LIMIAR sai do código e vira dado, por estágio.
-- 0.95 é o valor que a 0019 fixou; entra como default para o comportamento não
-- mudar em nenhum banco já existente.
-- -----------------------------------------------------------------------------
alter table estagio_autonomia add column if not exists limiar_auto_clear numeric default 0.95;

comment on column estagio_autonomia.limiar_auto_clear is
  'Confiança mínima para auto-aceite quando o estágio está em N2/N3. Era 0.95 HARDCODED em '
  'fn_registrar_campos_extraidos (0019); virou dado na 0041 para poder ser ajustado sem migration. '
  'Null = não auto-aceita, independentemente do nível.';

-- -----------------------------------------------------------------------------
-- fn_dial — a leitura única do dial. Portal, testes e a extração leem daqui.
-- -----------------------------------------------------------------------------
create or replace function fn_dial(p_estagio text)
returns jsonb
language sql
stable
as $$
  select jsonb_build_object(
    'estagio', ea.estagio,
    'nivel_atual', ea.nivel_atual,
    'teto', ea.teto,
    'limiar_auto_clear', ea.limiar_auto_clear,
    'no_teto', ea.nivel_atual = ea.teto,
    'atualizado_por', ea.atualizado_por,
    'atualizado_em', ea.atualizado_em
  )
  from estagio_autonomia ea where ea.estagio = p_estagio;
$$;

grant execute on function fn_dial(text) to authenticated;

-- -----------------------------------------------------------------------------
-- fn_mudar_dial — subir ou baixar o dial, com o teto respeitado e a decisão
-- registrada. É o que torna real o "versionada e reversível" de docs/01.
--
-- Recusa RETORNADA (padrão 0036/0037/0038): exceção desfaria o registro da
-- própria tentativa, e tentar subir acima do teto é justamente o que a trilha
-- precisa guardar.
-- -----------------------------------------------------------------------------
create or replace function fn_mudar_dial(
  p_estagio text,
  p_nivel   nivel_autonomia,
  p_autor   text,
  p_motivo  text default null,
  p_limiar  numeric default null
)
returns jsonb
language plpgsql
as $$
declare
  v_antes  jsonb;
  v_teto   nivel_autonomia;
begin
  select to_jsonb(ea), ea.teto into v_antes, v_teto
  from estagio_autonomia ea where ea.estagio = p_estagio;

  if v_antes is null then
    return jsonb_build_object('recusado', true,
      'motivo_recusa', format('Estágio "%s" não existe no dial. Os estágios são semeados na 0002 '
                              '(f0/04) — estágio novo entra por migration, não por chamada.', p_estagio));
  end if;

  -- O TETO É POR NATUREZA DO ESTÁGIO e é inegociável (docs/01, "regra de teto"):
  -- reconciliação Classe B/C e classificação contábil têm teto N1 e NUNCA viram
  -- autônomas. Recusar aqui é o que impede uma chamada de fazer o que a doutrina
  -- proíbe.
  if p_nivel > v_teto then
    insert into evento_auditoria (ator, acao, entidade_ref, depois)
      values (p_autor, 'mudanca_dial_recusada', 'estagio:'||p_estagio,
              jsonb_build_object('pedido', p_nivel, 'teto', v_teto, 'motivo_informado', p_motivo));
    return jsonb_build_object('recusado', true,
      'motivo_recusa', format('O estágio "%s" tem TETO %s e foi pedido %s. O teto é por natureza do '
                              'estágio (docs/01) e nenhuma chamada o sobrepõe — mudá-lo é decisão de '
                              'doutrina, por migration.', p_estagio, v_teto, p_nivel));
  end if;

  update estagio_autonomia
    set nivel_atual = p_nivel,
        limiar_auto_clear = coalesce(p_limiar, limiar_auto_clear),
        atualizado_por = p_autor,
        atualizado_em = now()
  where estagio = p_estagio;

  -- 'mudanca_dial' existe no enum desde a 0001 e nunca foi usado. Aqui é.
  -- `decisao` exige caso_id, e mudança de dial é GLOBAL (não é de um mandato) —
  -- então o registro append-only vai para `evento_auditoria`, que não exige caso.
  -- Registrar num caso arbitrário seria pior: faria a trilha daquele mandato
  -- afirmar uma decisão que não é dele.
  insert into evento_auditoria (ator, acao, entidade_ref, antes, depois)
    values (p_autor, 'mudanca_dial', 'estagio:'||p_estagio, v_antes,
            (select to_jsonb(ea) from estagio_autonomia ea where ea.estagio = p_estagio)
            || jsonb_build_object('motivo', p_motivo));

  return fn_dial(p_estagio);
end;
$$;

grant execute on function fn_mudar_dial(text, nivel_autonomia, text, text, numeric) to authenticated;

-- -----------------------------------------------------------------------------
-- fn_registrar_campos_extraidos — corpo da 0036 com UMA mudança de lógica: o
-- auto-aceite passa a obedecer o dial. Ver o comentário no lugar da mudança.
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
  -- 0029: o auto-aceite deixa de acontecer DENTRO do loop. Estas duas variáveis
  -- são o que permite decidir o aceite DEPOIS das guardas.
  v_guarda_disparou    boolean := false;
  -- 0041: o DIAL manda. Estas três variáveis são o que faz o auto-aceite obedecer
  -- ao estado declarado do sistema em vez do 0.95 que estava hardcoded aqui.
  v_nivel_dial         nivel_autonomia;
  v_limiar             numeric;
  v_auto_permitido     boolean;
begin
  -- Lê o dial UMA vez. `estagio_autonomia` existe desde a 0001 e, até a 0041, não
  -- tinha um único leitor: o nível dizia N0 (sombra, "não influencia decisão") e o
  -- código auto-aceitava tudo acima de 0.95, virando fato no export. Ler aqui é o
  -- que reconcilia as duas coisas.
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

      -- 0029: TODA linha entra como 'pendente'. O auto-aceite de >=95% (pedido do
      -- dono, cont.¹⁴) acontece DEPOIS das guardas — ver o bloco de promoção mais
      -- abaixo. Aceitar aqui era aceitar ANTES de saber se a extração é suspeita.
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
        -- 0035: a moeda que a extracao sempre soube e nunca gravou.
        v_item->>'moeda',
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
    -- 0029: ANTES isto era `return v_count` puro, e o efeito era o pior possível.
    -- Quando `Registrar Documento` falhava, o nó seguinte montava a requisição com
    -- `documento_versao_id = null`, a extração era EXECUTADA (dinheiro gasto) e
    -- caía aqui: a função retornava 0 com sucesso e JOGAVA FORA o `p_falha_motivo`
    -- antes do Sinal 3. Documento inexistente, chamada paga, zero pendência, zero
    -- rastro fora do log do n8n. O comentário antigo dizia "nunca deveria acontecer
    -- (FK)" — mas FK não dispara com `null`.
    --
    -- Não há `caso_id` para abrir pendência (é justamente o que falta), então o
    -- registro vai para `evento_auditoria`, que é append-only e não exige caso, e
    -- um `warning` fica no log do Postgres. A PREVENÇÃO é a montada: o nó
    -- `Montar Req Extracao` agora recusa montar requisição sem versão.
    insert into evento_auditoria (ator, acao, entidade_ref, depois)
      values ('sistema:n8n', 'extracao_orfa', 'documento_versao:'||coalesce(p_documento_versao_id::text,'null'),
              jsonb_build_object('campos_descartados', v_count, 'falha_motivo', p_falha_motivo,
                                 'porque', 'documento_versao inexistente: campos e motivo nao tinham onde ser gravados'));
    raise warning 'fn_registrar_campos_extraidos: documento_versao % inexistente; % campo(s) e o motivo "%" foram descartados',
      p_documento_versao_id, v_count, coalesce(p_falha_motivo, '(sem motivo)');
    return v_count;
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
    -- Sinal 1 refinado de novo (0034): a consulta saiu daqui para
    -- `fn_contas_repetindo_valor`, que EXCLUI os totais de grupo. Elas tinham o
    -- mesmo valor por construção — Ativo = Passivo + PL — e a guarda acusava o
    -- balanço mais correto possível: no v35, "ATIVO", "TOTAL DO ATIVO",
    -- "PASSIVO E PATRIMÔNIO LÍQUIDO" e "TOTAL DO PASSIVO E DO PATRIMÔNIO
    -- LÍQUIDO" valiam 14529 cada, e o alerta era 100% falso.
    select valor, n_contas into v_valor_repetido, v_max_repeticoes
      from fn_contas_repetindo_valor(p_documento_versao_id);

    select id into v_pendencia_id from pendencia
      where caso_id = v_caso_id and motivo = 'extracao:padrao_suspeito:' || v_documento_id and estado <> 'resolvida'
      limit 1;
    if coalesce(v_max_repeticoes, 0) >= 4 then
      v_guarda_disparou := true;
      if v_pendencia_id is null then
        insert into pendencia (caso_id, origem_estagio, tipo, severidade, sobrepujavel, descricao, documento_id, motivo)
          values (v_caso_id, 'extracao', 'extracao_padrao_suspeito', 'importante', true,
            format('%s contas diferentes, na MESMA coluna, vieram com o MESMO valor material (%s) — padrão '
                   'típico de fabricação/alucinação, não de dado real. Conferir contra o arquivo original.',
                   v_max_repeticoes, round(v_valor_repetido, 2)),
            v_documento_id, 'extracao:padrao_suspeito:' || v_documento_id);
      end if;
    elsif v_pendencia_id is not null then
      update pendencia set estado = 'resolvida', resolvida_em = now(), resolvida_por = 'sistema:extracao'
        where id = v_pendencia_id;
    end if;

    -- ----- Sinal 2 (0013): parcela relevante das linhas com confiança baixa -----
    select id into v_pendencia_id from pendencia
      where caso_id = v_caso_id and motivo = 'extracao:baixa_confianca:' || v_documento_id and estado <> 'resolvida'
      limit 1;
    if v_n_baixa_confianca >= 3 and v_n_baixa_confianca::numeric / v_count >= 0.3 then
      v_guarda_disparou := true;
      if v_pendencia_id is null then
        insert into pendencia (caso_id, origem_estagio, tipo, severidade, sobrepujavel, descricao, documento_id, motivo)
          values (v_caso_id, 'extracao', 'extracao_baixa_confianca', 'importante', true,
            format('%s de %s linhas extraídas vieram com confiança abaixo de 70%%. Revisar antes de aceitar.',
                   v_n_baixa_confianca, v_count),
            v_documento_id, 'extracao:baixa_confianca:' || v_documento_id);
      end if;
    elsif v_pendencia_id is not null then
      update pendencia set estado = 'resolvida', resolvida_em = now(), resolvida_por = 'sistema:extracao'
        where id = v_pendencia_id;
    end if;
  end if;

  -- ----- Sinal 3 (0016): a própria chamada de extração falhou/veio truncada -----
  select id into v_pendencia_id from pendencia
    where caso_id = v_caso_id and motivo = 'extracao:falhou:' || v_documento_id and estado <> 'resolvida'
    limit 1;
  -- 0029: `v_count = 0` entra na condição. A 0016 fechou "a chamada de extração
  -- falhou"; NÃO fechou "a chamada respondeu JSON válido com `linhas: []`". Nesse
  -- caso `p_falha_motivo` é nulo e `v_count` é zero, então NENHUM dos três sinais
  -- rodava: o documento ficava com tipo, confiança alta, `em_validacao`, zero linhas
  -- e zero pendências — indistinguível de um documento que legitimamente não tem
  -- números. E o pipeline PRODUZ esse estado de propósito: `.xlsx` e mime não
  -- previsto mandam uma string de aviso para a IA em vez do arquivo, pagam a chamada
  -- e recebem zero linhas. Uma cláusula aqui fecha os três casos de uma vez.
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
  -- O defeito que isto corrige: a 0027 gravava `status_aceite='aceito'` dentro do
  -- loop, para toda linha com confiança >=95%, e só DEPOIS rodava as três guardas
  -- (padrão suspeito / baixa confiança / extração falhou). Nenhuma guarda revertia
  -- o aceite. Efeito: uma extração alucinada — cujo padrão típico é justamente vir
  -- com confiança ALTA e o mesmo valor repetido em muitas contas — entrava na base
  -- como FATO ACEITO, e o Sinal 1 abria uma pendência ao lado sem desfazer nada.
  --
  -- Isso furava a anti-ancoragem, que é o princípio inegociável do projeto
  -- (docs/01, f0/06): nenhum número sugerido por IA vira fato sem aceite. Uma
  -- guarda que dispara depois do aceite não é guarda, é legenda.
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
    -- Havia linhas elegíveis, mas uma guarda disparou: ficam PENDENTES e o motivo
    -- fica registrado, para não parecer que o auto-aceite simplesmente não rodou.
    insert into evento_auditoria (ator, acao, entidade_ref, depois)
      values ('sistema:auto_aceite', 'auto_aceite_suprimido', 'documento_versao:'||p_documento_versao_id,
              jsonb_build_object('n_elegiveis', v_n_auto_aceitos,
                                 'porque', 'guarda de extracao disparou; linhas seguem pendentes de revisao humana'));
  end if;

  -- 0036: a completude é recalculada AQUI porque este é o único ponto do
  -- pipeline que roda DEPOIS da extração. `Registrar Documento` liga em paralelo
  -- para `Recomputar Completude` e para a extração, então a completude do E1 vê
  -- sempre zero linha — e nada a revisitava depois (só a revisão humana). Sem
  -- esta linha, o estado `recebido_nao_valido` e a pendência bloqueante da 0036
  -- só apareceriam quando alguém abrisse a revisão, que é exatamente a pessoa
  -- que a gente está tentando avisar.
  --
  -- Roda mesmo com v_count = 0: é justamente o caso que interessa.
  perform fn_recomputar_completude(v_caso_id);

  return v_count;
end;
$$;
grant execute on function fn_registrar_campos_extraidos(uuid, jsonb, nivel_autonomia, text) to authenticated;

-- -----------------------------------------------------------------------------
-- E O DIAL PASSA A DECLARAR O QUE O SISTEMA JÁ FAZIA.
--
-- Decisão do dono: N2. Isto NÃO muda comportamento — o auto-aceite acima de 0.95
-- já acontecia desde a 0019. O que muda é que agora está declarado, auditável, e
-- reversível por chamada.
--
-- A ressalva que a 0019 registrou continua verdadeira e vale repetir aqui: este
-- N2 é decisão de produto do dono, NÃO autonomia medida. `docs/01` exige
-- concordância contra golden set para subir dial de estágio interpretativo, e o
-- golden set físico ainda não existe (§7.4 #8 do Onboarding). Quando existir, a
-- medição confirma ou derruba este nível.
-- -----------------------------------------------------------------------------
do $$
declare v_r jsonb;
begin
  v_r := fn_mudar_dial('extracao_linhas_financeiras', 'N2', 'sistema:0041',
    'Declara no dial o auto-aceite que a 0019 já ligava no código (confiança >= 0.95). Não muda '
    'comportamento: torna explícito e reversível por chamada. NÃO é autonomia medida — o golden '
    'set físico não existe ainda, e docs/01 exige concordância medida para subir dial de estágio '
    'interpretativo.', 0.95);
  if coalesce((v_r->>'recusado')::boolean, false) then
    raise exception 'A 0041 não conseguiu declarar o dial: %', v_r->>'motivo_recusa';
  end if;
end $$;
