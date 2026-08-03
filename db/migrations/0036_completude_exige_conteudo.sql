-- =============================================================================
-- Migration 0036 — Documento que chegou vazio para de contar como item cumprido
--
-- Itens 3 e 4 do §7.4 do material de Onboarding:
--
--   #3  "completude_ok só exige a linha do documento — 14 documentos com zero
--        linhas extraídas dão dashboard verde e book vazio."
--   #4  "fn_aceitar_extracao aceita versão com zero campos — e grava uma decisão
--        de aprovação, um aceite formal de nada."
--
-- ---------------------------------------------------------------------------
-- POR QUE NÃO BASTOU "exigir linhas extraídas em fn_recomputar_completude"
-- ---------------------------------------------------------------------------
-- A leitura literal do item seria trocar a condição do Portão 1 por "existe
-- documento COM linhas". Duas coisas impedem:
--
-- 1. ORDEM DO GRAFO. No E1, `Registrar Documento` liga em PARALELO para
--    `Recomputar Completude` e para `Montar Req Extracao`. Quando a completude é
--    calculada, a extração ainda não rodou — o número de linhas é zero para TODO
--    documento, sempre. A condição literal reprovaria o caso inteiro por um
--    motivo que é só de sequência, e nada recomputava a completude depois da
--    extração (só a revisão humana, via 0008/0018).
--
-- 2. DOUTRINA. `docs/07` separa os dois status de propósito: "Completude ≠
--    validade. Um item pode estar recebido (completude satisfeita) e ainda não
--    válido (conteúdo/qualidade reprovados) … para evitar falsa sensação de
--    completude." Colapsar as duas condições numa só apagaria a distinção que
--    existe justamente para impedir o que o item #3 descreve.
--
-- Então a 0036 usa o vocabulário que já existe, em vez de redefinir o Portão 1:
--
--   • o documento continua RECEBIDO (a completude conta que ele chegou);
--   • o item passa a `recebido_nao_valido` no checklist quando NENHUMA versão
--     daquele documento produziu uma única linha — é a coluna `status` da
--     `checklist_item_status`, que já previa `invalido` desde a 0001;
--   • e abre pendência **BLOQUEANTE NÃO-SOBREPUJÁVEL** `item_sem_conteudo`, que
--     é o que de fato trava o Portão 2. `docs/07` lista "arquivo ilegível de
--     item essencial" entre os bloqueantes que NENHUMA ressalva libera, e um
--     obrigatório do Kit Básico sem uma linha aproveitável é esse caso.
--
-- O efeito prático é o que o item #3 pede — o caso deixa de parecer pronto e não
-- pode ser aprovado — sem mentir sobre o que "completude" significa. O dashboard
-- para de mostrar ✓ verde porque o item não está mais `presente`.
--
-- 3. E A COMPLETUDE PASSA A SER RECALCULADA DEPOIS DA EXTRAÇÃO.
--    `fn_registrar_campos_extraidos` é o único ponto do pipeline que roda com o
--    resultado da extração na mão. Sem chamar a recomputação ali, o estado novo
--    só apareceria quando um humano abrisse a revisão — exatamente quem a gente
--    está tentando avisar.
-- =============================================================================

alter type pendencia_tipo add value if not exists 'item_sem_conteudo';

-- -----------------------------------------------------------------------------
-- Quantas linhas APROVEITÁVEIS o caso tem para um código da taxonomia.
--
-- Conta campos de TODAS as versões de TODOS os documentos daquele tipo: reenvio
-- do mesmo arquivo cria versão nova (0026), e o que importa para o item do
-- checklist é se ALGUMA tentativa trouxe conteúdo — não a última.
-- -----------------------------------------------------------------------------
create or replace function fn_linhas_do_tipo(p_caso_id uuid, p_codigo text)
returns bigint
language sql
stable
as $$
  select count(ce.id)
  from documento d
  join documento_versao dv on dv.documento_id = d.id
  join campo_extraido ce on ce.documento_versao_id = dv.id
  where d.caso_id = p_caso_id and d.tipo_taxonomia = p_codigo;
$$;

comment on function fn_linhas_do_tipo(uuid, text) is
  'Linhas extraídas somadas em todas as versões dos documentos de um tipo no caso. '
  'Zero com documento presente = recebido, porém sem conteúdo aproveitável (0036).';

grant execute on function fn_linhas_do_tipo(uuid, text) to authenticated;

-- -----------------------------------------------------------------------------
-- fn_recomputar_completude — agora com TRÊS estados por obrigatório
-- (corpo da 0006 reescrito; a lista de faltantes e as pendências de
-- `item_faltante` continuam idênticas, para não mexer no que já funciona).
-- -----------------------------------------------------------------------------
create or replace function fn_recomputar_completude(p_caso_id uuid)
returns jsonb
language plpgsql
as $$
declare
  v_faltantes text[];
  v_sem_conteudo text[];
  v_cod text;
  v_nao_sobre boolean;
  v_status_atual caso_status;
  v_novo_status caso_status;
  v_pend_id uuid;
begin
  -- ----- (1) obrigatório sem NENHUM documento: igual à 0006 ------------------
  select array_agg(t.codigo order by t.codigo) into v_faltantes
  from taxonomia_tipo_documento t
  where t.obrigatoriedade = 'obrigatorio'
    and not exists (
      select 1 from documento d
      where d.caso_id = p_caso_id and d.tipo_taxonomia = t.codigo
    );
  v_faltantes := coalesce(v_faltantes, array[]::text[]);

  update pendencia p set estado = 'resolvida', resolvida_em = now(), resolvida_por = 'sistema:n8n'
  where p.caso_id = p_caso_id and p.tipo = 'item_faltante' and p.estado <> 'resolvida'
    and not (p.descricao = any (select 'Item obrigatório do Kit Básico ausente: '||x from unnest(v_faltantes) x));

  foreach v_cod in array v_faltantes loop
    select nao_sobrepujavel into v_nao_sobre from taxonomia_tipo_documento where codigo = v_cod;
    if not exists (
      select 1 from pendencia p
      where p.caso_id = p_caso_id and p.tipo = 'item_faltante'
        and p.estado <> 'resolvida'
        and p.descricao = 'Item obrigatório do Kit Básico ausente: '||v_cod
    ) then
      insert into pendencia (caso_id, origem_estagio, tipo, severidade, sobrepujavel, descricao)
        values (p_caso_id, 'completude', 'item_faltante', 'bloqueante',
                not coalesce(v_nao_sobre,false),
                'Item obrigatório do Kit Básico ausente: '||v_cod);
    end if;
  end loop;

  -- ----- (2) obrigatório PRESENTE mas sem uma linha aproveitável -------------
  -- O caso do item #3: o documento chegou, a extração não trouxe nada (formato
  -- que o pipeline não converte, arquivo ilegível, chamada que falhou), e o item
  -- ficava ✓ verde. Aqui ele deixa de ficar.
  select array_agg(t.codigo order by t.codigo) into v_sem_conteudo
  from taxonomia_tipo_documento t
  where t.obrigatoriedade = 'obrigatorio'
    and exists (
      select 1 from documento d
      where d.caso_id = p_caso_id and d.tipo_taxonomia = t.codigo
    )
    and fn_linhas_do_tipo(p_caso_id, t.codigo) = 0;
  v_sem_conteudo := coalesce(v_sem_conteudo, array[]::text[]);

  -- Resolve as que passaram a ter conteúdo (a extração de uma versão nova
  -- resolve sozinha — é o caminho normal de "reenviei o arquivo certo").
  update pendencia p set estado = 'resolvida', resolvida_em = now(), resolvida_por = 'sistema:extracao'
  where p.caso_id = p_caso_id and p.tipo = 'item_sem_conteudo' and p.estado <> 'resolvida'
    and not (p.motivo = any (select 'completude:sem_conteudo:'||x from unnest(v_sem_conteudo) x));

  foreach v_cod in array v_sem_conteudo loop
    if not exists (
      select 1 from pendencia p
      where p.caso_id = p_caso_id and p.tipo = 'item_sem_conteudo'
        and p.estado <> 'resolvida' and p.motivo = 'completude:sem_conteudo:'||v_cod
    ) then
      -- BLOQUEANTE e NÃO-SOBREPUJÁVEL (sobrepujavel=false), sempre: `docs/07`
      -- põe "arquivo ilegível de item essencial" na lista fechada que nenhuma
      -- ressalva libera. Um obrigatório do Kit Básico do qual não saiu UMA linha
      -- não tem como ser aprovado "com ressalva" — não há o que ressalvar.
      insert into pendencia (caso_id, origem_estagio, tipo, severidade, sobrepujavel, descricao, motivo)
        values (p_caso_id, 'completude', 'item_sem_conteudo', 'bloqueante', false,
                format('Item obrigatório "%s" foi RECEBIDO, mas nenhuma linha foi extraída de nenhuma '
                       'versão dele: o documento existe e o book sai VAZIO nesta parte. Causas comuns: '
                       'formato que o pipeline ainda não converte (.xlsx/.docx), arquivo ilegível, ou '
                       'chamada de extração que falhou. Conferir o arquivo e reenviar — completude não '
                       'é validade (docs/07), e um obrigatório sem conteúdo não passa o Portão 2.',
                       v_cod),
                'completude:sem_conteudo:'||v_cod);
    end if;
  end loop;

  -- ----- (3) o checklist reflete os três estados -----------------------------
  -- `recebido_nao_valido` é o vocabulário de `docs/07` ("recebido_não_válido").
  -- A coluna é texto desde a 0001, com os valores no comentário; este é o quarto.
  update checklist_item_status c
    set status = case
                   when fn_linhas_do_tipo(p_caso_id, c.tipo_taxonomia) = 0 then 'recebido_nao_valido'
                   else 'presente'
                 end,
        atualizado_em = now()
  where c.caso_id = p_caso_id
    and c.documento_id is not null
    and c.status in ('presente', 'recebido_nao_valido');

  -- ----- (4) status do caso: Portão 1 continua sendo CHEGADA -----------------
  -- Não se mexe aqui de propósito. Quem trava o avanço é a pendência bloqueante
  -- acima — é assim que `docs/07` desenha o portão ("elegível ao Portão 2 se e
  -- somente se não há pendência bloqueante aberta"). Redefinir `completude_ok`
  -- para incluir conteúdo apagaria a separação completude/validade.
  select status into v_status_atual from caso where id = p_caso_id;
  if array_length(v_faltantes,1) is null then
    v_novo_status := 'completude_ok';
  else
    v_novo_status := 'em_triagem';
  end if;

  if v_status_atual in ('intake','em_triagem','completude_ok') and v_novo_status <> v_status_atual then
    update caso set status = v_novo_status where id = p_caso_id;
    insert into evento_auditoria (ator, acao, entidade_ref, antes, depois)
      values ('sistema:n8n', 'transicao_status', 'caso:'||p_caso_id,
              jsonb_build_object('status', v_status_atual),
              jsonb_build_object('status', v_novo_status));
  end if;

  return jsonb_build_object(
    'portao1_ok', array_length(v_faltantes,1) is null,
    'faltantes', to_jsonb(v_faltantes),
    -- NOVO: quem chegou e veio vazio. Sai no payload porque o nó do n8n e o
    -- portal precisam poder mostrar isso sem refazer a consulta.
    'sem_conteudo', to_jsonb(v_sem_conteudo),
    -- E o que de fato importa para o Portão 2: chegou tudo E tem conteúdo.
    'pronto_para_revisao',
      array_length(v_faltantes,1) is null and array_length(v_sem_conteudo,1) is null,
    'status', v_novo_status
  );
end;
$$;

comment on function fn_recomputar_completude(uuid) is
  'Portão 1 (chegada) + o estado novo da 0036: obrigatório RECEBIDO sem uma linha extraída vira '
  'pendência bloqueante NÃO-sobrepujável e item `recebido_nao_valido`. `portao1_ok` continua '
  'significando "chegou tudo"; `pronto_para_revisao` é chegou tudo E tem conteúdo.';

-- -----------------------------------------------------------------------------
-- fn_aceitar_extracao — recusa aceitar o vazio (item #4)
--
-- O que existia: com zero campos, o `update` não tocava nada, `v_n_aceitos`
-- ficava 0 e a função gravava, ainda assim, uma `decisao` de tipo `aprovacao`.
-- Um aceite formal de nada — e, pior, um registro que faz a trilha de auditoria
-- afirmar que um humano aprovou a extração daquele documento. Como `decisao` é
-- append-only, esse registro não sai mais de lá.
--
-- Dois casos que PARECEM iguais e não são:
--   • a versão não tem NENHUM campo  → recusa (não há o que aprovar);
--   • tem campos, todos já aceitos   → no-op idempotente, sem `decisao` nova
--     (antes, clicar duas vezes gravava duas aprovações).
-- -----------------------------------------------------------------------------
create or replace function fn_aceitar_extracao(
  p_documento_versao_id uuid,
  p_autor               text,
  p_motivo              text default null
)
returns jsonb
language plpgsql
as $$
declare
  v_documento_id uuid;
  v_caso_id      uuid;
  v_nome         text;
  v_n_campos     int;
  v_n_aceitos    int;
begin
  select d.id, d.caso_id, dv.nome_original into v_documento_id, v_caso_id, v_nome
  from documento_versao dv
  join documento d on d.id = dv.documento_id
  where dv.id = p_documento_versao_id;

  if v_documento_id is null then
    raise exception 'documento_versao % não encontrada', p_documento_versao_id;
  end if;

  select count(*) into v_n_campos from campo_extraido where documento_versao_id = p_documento_versao_id;

  if v_n_campos = 0 then
    -- RECUSA RETORNADA, não `raise exception` — e a razão é técnica, não de gosto:
    -- exceção em plpgsql desfaz TUDO o que a função fez, inclusive o registro da
    -- tentativa em `evento_auditoria`. A primeira versão desta função levantava
    -- exceção e o teste flagrou que o rastro da tentativa desaparecia junto. Como
    -- Postgres não tem transação autônoma, ou se tem a exceção, ou se tem o
    -- registro. O registro é mais valioso: a recusa já é evidente no retorno.
    --
    -- Nada é gravado como aprovação, e `recusado` sai no payload para nenhum
    -- chamador poder confundir isto com sucesso.
    insert into evento_auditoria (ator, acao, entidade_ref, depois)
      values (p_autor, 'aceite_recusado', 'documento_versao:'||p_documento_versao_id,
              jsonb_build_object('porque', 'versao sem nenhum campo extraido',
                                 'documento_id', v_documento_id, 'motivo_informado', p_motivo));
    return jsonb_build_object(
      'documento_versao_id', p_documento_versao_id,
      'n_campos_aceitos', 0,
      'recusado', true,
      'motivo_recusa', format(
        'Não há o que aceitar em "%s": esta versão não tem NENHUMA linha extraída. Aceitar aqui '
        'gravaria uma aprovação formal de nada na trilha de auditoria (e `decisao` é append-only). '
        'Veja a pendência de extração deste documento — formato não convertido, arquivo ilegível ou '
        'chamada que falhou — e reenvie o arquivo.',
        coalesce(v_nome, p_documento_versao_id::text)));
  end if;

  update campo_extraido
    set status_aceite = 'aceito', aceito_por = p_autor, aceito_em = now()
  where documento_versao_id = p_documento_versao_id
    and status_aceite <> 'aceito';
  get diagnostics v_n_aceitos = row_count;

  if v_n_aceitos = 0 then
    -- Tudo já estava aceito: não há decisão nova a registrar. O evento fica,
    -- para o clique não desaparecer do histórico.
    insert into evento_auditoria (ator, acao, entidade_ref, depois)
      values (p_autor, 'aceite_sem_efeito', 'documento_versao:'||p_documento_versao_id,
              jsonb_build_object('porque', 'todas as linhas ja estavam aceitas', 'n_campos', v_n_campos));
    return jsonb_build_object('documento_versao_id', p_documento_versao_id,
                              'n_campos_aceitos', 0, 'ja_estava_aceito', true);
  end if;

  insert into decisao (caso_id, tipo, autor, motivo, payload)
    values (v_caso_id, 'aprovacao', p_autor, p_motivo,
      jsonb_build_object('documento_versao_id', p_documento_versao_id, 'n_campos_aceitos', v_n_aceitos));

  insert into evento_auditoria (ator, acao, entidade_ref, depois)
    values (p_autor, 'extracao_aceita', 'documento_versao:' || p_documento_versao_id,
      jsonb_build_object('n_campos_aceitos', v_n_aceitos, 'motivo', p_motivo));

  return jsonb_build_object('documento_versao_id', p_documento_versao_id, 'n_campos_aceitos', v_n_aceitos);
end;
$$;

grant execute on function fn_aceitar_extracao(uuid, text, text) to authenticated;

-- -----------------------------------------------------------------------------
-- fn_registrar_campos_extraidos — corpo IDÊNTICO ao da 0035, com UMA adição:
-- recomputar a completude no fim. Ver o comentário no lugar da mudança.
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
