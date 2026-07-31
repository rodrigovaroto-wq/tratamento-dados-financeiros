-- 0029 — Extração: aceitar depois das guardas, e nunca mais um "sucesso" vazio
--
-- Quatro defeitos da mesma família — todos fazem a extração parecer bem-sucedida
-- quando não foi, e três deles são silenciosos por construção.
--
-- 1. AUTO-ACEITE ATROPELAVA AS GUARDAS (o mais grave: fura a anti-ancoragem).
--    A 0027 gravava `status_aceite='aceito'` DENTRO do loop, para toda linha com
--    confiança >=95%, e só depois rodava as três guardas. Nenhuma guarda revertia
--    o aceite. Uma extração alucinada — cujo padrão típico é vir com confiança
--    ALTA e o mesmo valor repetido em muitas contas — entrava como FATO ACEITO, e
--    o Sinal 1 abria uma pendência ao lado sem desfazer nada. Uma guarda que
--    dispara depois do aceite não é guarda, é legenda.
--    Agora: toda linha entra 'pendente'; a promoção a 'aceito' acontece no fim,
--    e só se NENHUMA das três guardas disparou. Quando havia linha elegível e a
--    guarda barrou, isso vira `evento_auditoria` — para não parecer que o
--    auto-aceite simplesmente não rodou.
--
-- 2. EXTRAÇÃO VAZIA SEM ERRO DE API NÃO GERAVA PENDÊNCIA NENHUMA.
--    A 0016 fechou "a chamada falhou". Não fechou "a chamada respondeu JSON
--    válido com `linhas: []`": aí `p_falha_motivo` é nulo e `v_count` é zero,
--    então os três sinais eram pulados. O documento ficava com tipo, confiança
--    alta, `em_validacao`, zero linhas e ZERO pendências — indistinguível de um
--    documento que legitimamente não tem números.
--    E o pipeline produz esse estado DE PROPÓSITO: `.xlsx` e mime não previsto
--    mandam para a IA uma string de aviso em vez do arquivo (build-workflow.mjs),
--    pagam a chamada e recebem zero linhas. `.xlsx` é o formato mais comum de
--    faturamento/aging/mapa de dívida.
--    Agora: `v_count = 0` entra na condição do Sinal 3, com um motivo que nomeia
--    a causa mais provável em vez de dizer só "vazio".
--
-- 3. `extracao_falhou` NUNCA FECHAVA, e não há caminho de reprocessamento.
--    A chave de idempotência era `'extracao:falhou:' || p_documento_versao_id`.
--    Reenviar o arquivo cria uma VERSÃO nova (id novo), então a extração boa
--    abria/fechava uma chave DIFERENTE e a pendência antiga ficava aberta para
--    sempre. Valia igual para `padrao_suspeito` e `baixa_confianca`, e
--    `fn_revisar_documento` (0018) não resolve nenhuma das quatro de extração —
--    ou seja, não havia ação humana capaz de fechá-las.
--    Agora as três chaves são por `documento_id`: a versão seguinte resolve a
--    pendência da anterior, que é o comportamento que "reenviar corrige" exige.
--    Inclui migração das chaves já gravadas (senão as pendências existentes
--    ficariam órfãs justamente por causa desta correção).
--
-- 4. DOCUMENTO INEXISTENTE DESCARTAVA O MOTIVO DA FALHA EM SILÊNCIO.
--    `if v_documento_id is null then return v_count;` — com o comentário "nunca
--    deveria acontecer (FK)". Mas FK não dispara com `null`, e o caminho é real:
--    quando `Registrar Documento` falha, o pipeline segue com
--    `documento_versao_id = null`, EXECUTA a extração (dinheiro gasto) e cai
--    aqui. A função retornava 0 com sucesso e jogava fora o `p_falha_motivo`
--    antes do Sinal 3. Documento inexistente, chamada paga, zero rastro.
--    Agora: `evento_auditoria` (append-only, não exige caso) + `warning`. A
--    prevenção fica no pipeline — `Montar Req Extracao` recusa montar
--    requisição sem versão, então a chamada não é mais paga.
--
-- Idempotente: `create or replace` + updates condicionais. Seguro de reaplicar.

begin;

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
-- ---------------------------------------------------------------------------
-- Migração das chaves de pendência já gravadas (defeito 3).
--
-- Sem isto, a correção da chave deixaria as pendências EXISTENTES inalcançáveis:
-- gravadas com `...:<versao_id>`, procuradas com `...:<documento_id>`. Ficariam
-- abertas para sempre — o mesmo bug, por outra porta.
--
-- `distinct on (documento_id, tipo)` porque um documento com várias versões pode
-- ter acumulado uma pendência por versão; todas viram a MESMA chave, e chave
-- repetida quebraria a busca `limit 1` (a busca acharia uma e deixaria as outras
-- abertas). Mantém a mais recente aberta e resolve as demais como duplicata.
-- ---------------------------------------------------------------------------
with alvo as (
  select p.id, p.documento_id, p.tipo, p.criada_em,
         split_part(p.motivo, ':', 1) || ':' || split_part(p.motivo, ':', 2) || ':' || p.documento_id::text as chave_nova,
         row_number() over (partition by p.documento_id, p.tipo order by p.criada_em desc) as rn
  from pendencia p
  where p.estado <> 'resolvida'
    and p.documento_id is not null
    and p.motivo ~ '^extracao:(falhou|padrao_suspeito|baixa_confianca):[0-9a-f-]{36}$'
)
update pendencia p
   set motivo = a.chave_nova,
       estado = case when a.rn = 1 then p.estado else 'resolvida' end,
       resolvida_em = case when a.rn = 1 then p.resolvida_em else now() end,
       resolvida_por = case when a.rn = 1 then p.resolvida_por else 'sistema:0029 (chave por documento; duplicata de versão)' end
  from alvo a
 where p.id = a.id
   and p.motivo <> a.chave_nova;

comment on function fn_registrar_campos_extraidos(uuid, jsonb, nivel_autonomia, text) is
  'Grava os campos extraídos (E2, sombra). Toda linha entra PENDENTE; o auto-aceite '
  'de >=95% é promovido no fim e SÓ se nenhuma guarda disparar (0029). Extração vazia '
  'conta como falha. Chaves de pendência são por documento, não por versão, para que '
  'reenviar resolva a pendência anterior.';

-- ---------------------------------------------------------------------------
-- Verificação embutida (mesmo padrão da 0028): a migration prova a si mesma.
-- ---------------------------------------------------------------------------
do $verifica$
declare
  v_caso uuid; v_r jsonb; v_ver uuid;
  v_n int; v_aceitos int; v_pend int;
begin
  insert into caso (nome) values ('0029 verificacao') returning id into v_caso;

  -- Usa fn_registrar_documento (o caminho REAL do pipeline) em vez de inserir à
  -- mão: além de não depender do schema exato das tabelas, exercita a costura que
  -- a produção usa. Hash fixo para as três versões serem do MESMO documento — é o
  -- que o defeito 3 precisa para ser testável.
  v_r := fn_registrar_documento(v_caso, 'Teste 0029', 'anual', '2025', 'BALANCO', 0.9,
    'nome_arquivo', 'supabase_storage', 'b/y.pdf', 'y.pdf', null, 'HASH-0029', 'ok');
  v_ver := (v_r->>'documento_versao_id')::uuid;

  -- (1) Padrão suspeito COM confiança 99%: antes isto entrava ACEITO. Agora não.
  v_n := fn_registrar_campos_extraidos(v_ver, jsonb_build_array(
    jsonb_build_object('chave','Conta A','valor_num','1000','confianca','0.99'),
    jsonb_build_object('chave','Conta B','valor_num','1000','confianca','0.99'),
    jsonb_build_object('chave','Conta C','valor_num','1000','confianca','0.99'),
    jsonb_build_object('chave','Conta D','valor_num','1000','confianca','0.99'),
    jsonb_build_object('chave','Conta E','valor_num','1000','confianca','0.99')
  ), 'N0', null);
  select count(*) into v_aceitos from campo_extraido
    where documento_versao_id = v_ver and status_aceite = 'aceito';
  if v_aceitos <> 0 then
    raise exception '0029: guarda disparou e % linha(s) foram aceitas mesmo assim', v_aceitos;
  end if;
  select count(*) into v_pend from pendencia
    where caso_id = v_caso and tipo = 'extracao_padrao_suspeito' and estado <> 'resolvida';
  if v_pend <> 1 then raise exception '0029: esperava 1 pendencia de padrao suspeito, achei %', v_pend; end if;
  raise notice 'ok    padrao suspeito com confianca 99%% NAO auto-aceita (era o furo na anti-ancoragem)';

  -- (2) Mesmo hash => VERSAO nova sob o mesmo documento. Extracao limpa: auto-aceite
  --     continua funcionando (o fix nao desligou o recurso).
  v_r := fn_registrar_documento(v_caso, 'Teste 0029', 'anual', '2025', 'BALANCO', 0.9,
    'nome_arquivo', 'supabase_storage', 'b/y.pdf', 'y.pdf', null, 'HASH-0029', 'ok');
  v_ver := (v_r->>'documento_versao_id')::uuid;
  v_n := fn_registrar_campos_extraidos(v_ver, jsonb_build_array(
    jsonb_build_object('chave','Caixa','valor_num','500','confianca','0.99'),
    jsonb_build_object('chave','Clientes','valor_num','2700','confianca','0.98'),
    jsonb_build_object('chave','Estoques','valor_num','1350','confianca','0.97')
  ), 'N0', null);
  select count(*) into v_aceitos from campo_extraido
    where documento_versao_id = v_ver and status_aceite = 'aceito';
  if v_aceitos <> 3 then raise exception '0029: extracao limpa deveria auto-aceitar 3, aceitou %', v_aceitos; end if;
  raise notice 'ok    extracao limpa segue auto-aceitando (o fix nao desligou o recurso)';

  -- (3) A pendencia da versao 1 foi RESOLVIDA pela versao 2 — o defeito 3. Antes a
  --     chave era por versao e a pendencia ficava aberta para sempre.
  select count(*) into v_pend from pendencia
    where caso_id = v_caso and tipo = 'extracao_padrao_suspeito' and estado <> 'resolvida';
  if v_pend <> 0 then
    raise exception '0029: a versao nova nao resolveu a pendencia da anterior (% aberta[s])', v_pend;
  end if;
  raise notice 'ok    reenviar resolve a pendencia da versao anterior (chave por documento)';

  -- (4) Extracao VAZIA sem erro de API abre pendencia. Documento diferente (hash
  --     diferente), porque aqui o que se testa e' o caso .xlsx: a IA recebe um
  --     aviso em vez do arquivo, responde JSON valido com linhas: [].
  v_r := fn_registrar_documento(v_caso, 'Teste 0029', 'anual', '2025', 'FATURAMENTO_24M', 0.9,
    'nome_arquivo', 'supabase_storage', 'b/z.xlsx', 'z.xlsx', null, 'HASH-0029-XLSX', 'ok');
  v_ver := (v_r->>'documento_versao_id')::uuid;
  v_n := fn_registrar_campos_extraidos(v_ver, '[]'::jsonb, 'N0', null);
  select count(*) into v_pend from pendencia
    where caso_id = v_caso and documento_id = (v_r->>'documento_id')::uuid
      and tipo = 'extracao_falhou' and estado <> 'resolvida';
  if v_pend <> 1 then
    raise exception '0029: extracao vazia sem erro de API nao abriu pendencia (achei %)', v_pend;
  end if;
  raise notice 'ok    "linhas: []" sem erro de API deixa de ser sucesso silencioso';

  -- (5) Documento inexistente registra em auditoria em vez de descartar o motivo.
  v_n := fn_registrar_campos_extraidos(null, '[]'::jsonb, 'N0', 'motivo que antes era jogado fora');
  select count(*) into v_n from evento_auditoria where acao = 'extracao_orfa';
  if v_n < 1 then raise exception '0029: extracao orfa nao deixou rastro em evento_auditoria'; end if;
  raise notice 'ok    extracao orfa registra o motivo em vez de descarta-lo';

  delete from caso where id = v_caso;
  raise notice 'TODAS AS VERIFICACOES DA 0029 PASSARAM';
end
$verifica$;

commit;
