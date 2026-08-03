-- =============================================================================
-- Migration 0035 — A moeda que a extração sempre soube e nunca gravou
--
-- Item 2 do §7.4 do material de Onboarding ("moeda capturada e descartada"), e
-- o que o próprio book já confessava em `portal/src/lib/export-modelagem.ts`:
--
--     "Hoje o modelo não separa moeda: o campo `moeda` é capturado na extração
--      e DESCARTADO (não há coluna), então uma linha em USD [soma com BRL]"
--
-- O caminho existia inteiro, menos o último metro: o schema JSON já pedia
-- `moeda` à IA (n8n/lib/extract.mjs), `normalizarMoeda` já convertia
-- "US$"/"dolar"/"usd" no ISO 'USD' desde sempre, e o valor morria no nó — nenhum
-- campo o carregava, porque não havia coluna onde pousar.
--
-- POR QUE ISTO É CARO, e não cosmético: com o erro de escala de ~496× corrigido
-- na Etapa 1, moeda era o ÚLTIMO fator multiplicativo invisível do pipeline. Uma
-- linha em dólar somada a reais não erra por pouco — erra pelo câmbio (~5x hoje),
-- silenciosamente, num book que fecha e parece impecável. É a assinatura da
-- família de falha que este projeto existe para combater: roda sem erro e
-- entrega número errado.
--
-- POR QUE POR LINHA, e não por documento: `unidade` (a escala) já é por linha
-- pela mesma razão — demonstração real MISTURA naturezas no mesmo arquivo, e a
-- herança é bloqueada nas linhas não-monetárias (percentual, LPA, quantidade).
-- Marcar "margem 12%" como BRL faria o export tratar doze por cento como doze
-- reais. Moeda segue a escala: mesma herança, mesmo bloqueio, mesmo lugar.
--
-- NOTA sobre `unidade`: o comentário da 0005 dizia `unidade text -- ex.: 'BRL',
-- 'milhares'`, confundindo escala com moeda numa coluna só. Na prática o
-- pipeline sempre gravou ESCALA ali ('milhar'/'unidade'). A 0035 não migra nada:
-- separa as duas coisas de agora em diante e deixa `unidade` significando o que
-- de fato significa. Linha antiga fica com `moeda is null` = moeda desconhecida,
-- que é a verdade sobre ela — nunca 'BRL' presumido, porque presumir moeda é
-- exatamente o erro que esta migration fecha.
-- =============================================================================

alter table campo_extraido add column if not exists moeda text;

comment on column campo_extraido.moeda is
  'Moeda ISO da linha (BRL/USD/EUR/…), herdada do documento pela extração; null = desconhecida, '
  'NUNCA presumida. Separada de `unidade`, que é a ESCALA (milhar/unidade). Somar linhas de moedas '
  'diferentes é erro pelo câmbio inteiro — ver o cabeçalho da 0035.';

-- Índice não é necessário: a moeda é lida junto da linha (sempre por
-- documento_versao_id, que já tem índice), nunca filtrada isoladamente.

-- -----------------------------------------------------------------------------
-- fn_registrar_campos_extraidos — corpo IDÊNTICO ao da 0034, com `moeda` no
-- insert. Redefinição integral porque é como o Postgres funciona (não há "alter
-- function body"), e é o padrão que este repositório já segue desde a 0005.
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
begin
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
      if v_confianca is not null and v_confianca >= 0.95 then
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
          aceito_por = 'sistema:auto_aceite (confiança >=95%, sem guarda disparada)',
          aceito_em = now()
      where documento_versao_id = p_documento_versao_id
        and confianca >= 0.95
        and status_aceite = 'pendente';

    insert into decisao (caso_id, tipo, autor, motivo, payload)
      values (v_caso_id, 'aprovacao', 'sistema:auto_aceite',
        format('%s linha(s) auto-aceitas por confiança >=95%% na extração de "%s" — nenhuma guarda disparou.',
               v_n_auto_aceitos, coalesce(v_nome_original, '?')),
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

  return v_count;
end;
$$;
grant execute on function fn_registrar_campos_extraidos(uuid, jsonb, nivel_autonomia, text) to authenticated;
