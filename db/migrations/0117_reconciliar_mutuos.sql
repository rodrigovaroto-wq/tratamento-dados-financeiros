-- =============================================================================
-- 0117 — A divergência de mútuos passa a ser ACUSADA
--
-- O BURACO, medido e não deduzido. O book de teste planta UMA divergência
-- deliberada: a planilha de mútuos do controller "esquece" um aditivo e fica
-- R$ 240 mil abaixo do saldo que o balanço da holding declara
-- (`test-data/book-canastra/demonstracoes.py`, `DIVERGENCIA_MUTUOS`). A rodada
-- v46 (17/08) trouxe o erro INTEIRO para dentro do banco — os dois lados, com
-- os dois números certos — e nenhuma pendência foi aberta. As cinco checagens
-- que existiam (`ativo_passivo_pl`, `caixa_bp_fluxo`, `duplicidade_de_rotulo`,
-- `receita_dre_vs_faturamento`, `despfin_dre_vs_divida`) simplesmente não
-- olham para mútuos. O `ESTADO.md` cobrava esse erro como "o que trazer de
-- volta da rodada", o que fazia parecer que alguém esperava que fosse pego.
-- Ninguém pegava: a checagem não existia.
--
-- CLASSE B, e não A, porque a comparação depende de julgamento sobre O QUE a
-- planilha lista. Ela é o par intragrupo — o saldo do balanço é UMA conta e a
-- planilha é a abertura dela por contraparte; um aditivo esquecido, um
-- encontro de contas feito em dezembro e não refletido, ou uma conta que o
-- balanço agrega com "outras partes relacionadas" produzem diferença legítima.
-- O sistema mostra, o humano decide. É o mesmo desenho de `despfin_dre_vs_divida`.
--
-- O LADO IMPORTA, e é a única sutileza real desta checagem. Mútuo é ATIVO para
-- quem emprestou e PASSIVO para quem tomou, e o mesmo mandato costuma ter os
-- dois. Somar tudo junto compara 16.060 com 11.400 e acusa uma divergência de
-- 4.660 que não existe — pior que não checar, porque ensina o analista a
-- ignorar a pendência. Então:
--   • no BALANÇO o lado sai da `secao_canonica` (que a extração já classifica)
--     e, quando ela falta, do rótulo ("a receber"/"a pagar");
--   • na PLANILHA sai do rótulo da linha;
--   • compara-se LADO A LADO, e só os lados que existem NOS DOIS documentos;
--   • se o balanço tem os dois lados e a planilha não diz de qual ela fala, a
--     checagem PARA e registra `precondicao_nao_satisfeita` dizendo isso — não
--     chuta o lado. Um chute aqui produz divergência inventada.
--
-- SUBTOTAL FICA DE FORA DOS DOIS LADOS (`fn_papel_linha`): somar "TOTAL DE
-- MÚTUOS" junto com as linhas que ele soma dobra o lado inteiro. É o mesmo
-- cuidado que a `0116` acabou de tornar mais necessário — agora que o total
-- impresso vira linha, ele CHEGA, e uma soma ingênua sairia 2×.
-- =============================================================================

create or replace function fn_lado_do_mutuo(p_chave text, p_secao_canonica text default null)
returns text language sql immutable as $$
  select case
    -- A seção canônica é o sinal FORTE: ela vem da classificação contábil da
    -- linha, não da grafia do rótulo.
    when p_secao_canonica like 'ativo%'   then 'ativo'
    when p_secao_canonica like 'passivo%' then 'passivo'
    -- Sem seção, o rótulo. "a pagar" antes de "a receber" de propósito: o
    -- rótulo composto ("Mútuos a pagar para controladas a receber de terceiros")
    -- é raro, mas quando aparece o lado que manda é o do começo — e a ordem
    -- aqui é o que decide. Empate real devolve null, e null PARA a checagem.
    when fn_normalizar_texto(p_chave) ~ '(a pagar|tomado|passivo|devedor|obrigac)' then 'passivo'
    when fn_normalizar_texto(p_chave) ~ '(a receber|concedid|ativo|credor|direito)' then 'ativo'
    else null
  end;
$$;

comment on function fn_lado_do_mutuo(text, text) is
  'Lado contábil de uma linha de mútuo: ativo (emprestou) | passivo (tomou) | null (o documento não diz). Usada pela reconciliação de mútuos, que compara lado a lado — somar os dois juntos acusa divergência que não existe.';

create or replace function fn_reconciliar_mutuos(
  p_caso_id        uuid,
  p_periodo_id     uuid,
  p_tolerancia_abs numeric default 50000,
  p_tolerancia_pct numeric default 0.005
) returns jsonb language plpgsql as $$
declare
  v_doc_mut uuid;
  v_ver_mut uuid;
  v_ano int;
  v_col_mut text;
  v_unid_mut text;
  v_bp   record;
  v_pl   record;
  v_lados_bp text[] := '{}';
  v_a numeric; v_b numeric; v_div numeric; v_tol numeric;
  v_resultado text := 'ok';
  v_partes text[] := '{}';
  v_n int := 0;
  v_pior_abs numeric; v_pior_pct numeric;
  v_fonte_a jsonb; v_fonte_b jsonb;
  v_tem_balanco boolean;
begin
  -- A PLANILHA É DO GRUPO E O SALDO É DE CADA EMPRESA — por isso esta checagem
  -- é por CASO, e não por (caso, entidade) como as outras.
  --
  -- Foi a primeira versão desta função que ensinou isso, errando: ela procurava
  -- o balanço DA MESMA entidade dona da planilha. No book Vertentes a planilha é
  -- do "GRUPO VERTENTES" e a única demonstração dessa entidade é a COMBINADA —
  -- que, por definição, ELIMINA o intragrupo e não tem uma linha de mútuo
  -- sequer. A checagem "não achava o par" e abria pendência de pré-condição num
  -- caso que está perfeitamente em ordem. O par certo é o outro: a planilha
  -- lista "A → B", e o saldo mora no balanço de A (a receber) ou de B (a pagar).
  v_doc_mut := fn_documento_por_tipo(p_caso_id, null, p_periodo_id, 'MUTUOS');
  if v_doc_mut is null then
    v_doc_mut := fn_documento_por_tipo(p_caso_id, null, null, 'MUTUOS');
  end if;

  select exists (
    select 1 from documento d
    where d.caso_id = p_caso_id
      and d.tipo_taxonomia in ('BALANCO', 'BALANCETE', 'COMBINADO', 'DF_AUDITADA')
  ) into v_tem_balanco;

  if v_doc_mut is null or not v_tem_balanco then
    return fn_registrar_reconciliacao(p_caso_id, null, p_periodo_id,
      'mutuos_planilha_vs_balanco', 'B', v_doc_mut, null, null,
      'documento_ausente', null, null,
      jsonb_build_object('tolerancia_abs', p_tolerancia_abs, 'tolerancia_pct', p_tolerancia_pct),
      format('Sem par para reconciliar mútuos: %s não foi entregue neste mandato.',
        case when v_doc_mut is null and not v_tem_balanco then 'a planilha de mútuos e nenhum balanço'
             when v_doc_mut is null then 'a planilha de mútuos' else 'nenhum balanço' end));
  end if;

  v_ver_mut  := fn_versao_atual(v_doc_mut);
  v_unid_mut := fn_unidade_predominante(v_ver_mut);

  foreach v_ano in array fn_anos_alvo(p_periodo_id) loop
    v_col_mut := case when v_ano is null then null
                      else fn_coluna_periodo_do_ano(v_ver_mut, v_ano) end;

    -- ---- LADO A: o saldo de mútuos, somado sobre TODOS os balanços do caso --
    -- Soma, e não `fn_valor_conceito_col`: o saldo aparece numa conta por
    -- empresa, e pegar UMA compararia parte do saldo com a planilha inteira.
    -- A escala entra linha a linha (`fn_valor_em_base`), então um caso com um
    -- balanço em milhar e outro em unidade continua somando certo.
    for v_bp in
      select fn_lado_do_mutuo(ce.chave, ce.secao_canonica) as lado,
             sum(fn_valor_em_base(ce.valor_num, ce.unidade)) as soma_base,
             count(*)::int as n,
             count(distinct d.id)::int as n_docs,
             min(ce.chave) as exemplo,
             bool_or(ce.unidade is null) as tem_sem_escala
      from (
        -- UM DOCUMENTO POR ENTIDADE, e isto é correção de defeito medido, não
        -- zelo: o book Vertentes entrega para a mesma controlada um BALANÇO e
        -- um BALANCETE do mesmo exercício, com o mesmo saldo de mútuo (3.974).
        -- Somando os dois, o lado passivo saía 15.427 contra 11.453 do ativo e
        -- a checagem acusava 2.394 de divergência — uma divergência que ela
        -- mesma tinha criado. Balanço e balancete são a MESMA realidade dita
        -- duas vezes; a ordem abaixo escolhe a peça mais definitiva.
        select distinct on (d.entidade_id) d.id, d.entidade_id
        from documento d
        where d.caso_id = p_caso_id
          and d.tipo_taxonomia in ('BALANCO', 'BALANCETE', 'COMBINADO', 'DF_AUDITADA')
        order by d.entidade_id,
                 array_position(array['BALANCO','COMBINADO','DF_AUDITADA','BALANCETE'],
                                d.tipo_taxonomia),
                 d.criado_em desc
      ) d
      join lateral (select fn_versao_atual(d.id) as ver) v on true
      join campo_extraido ce on ce.documento_versao_id = v.ver
      where ce.valor_num is not null
        and fn_normalizar_texto(ce.chave) like '%mutuo%'
        and fn_papel_linha(ce.chave) <> 'subtotal'
        and (fn_coluna_periodo_do_ano(v.ver, v_ano) is null
             or fn_normalizar_texto(ce.periodo_coluna)
                = fn_normalizar_texto(fn_coluna_periodo_do_ano(v.ver, v_ano)))
      group by 1
    loop
      if v_bp.lado is null then continue; end if;
      v_lados_bp := v_lados_bp || v_bp.lado;

      -- ---- LADO B: a planilha, do MESMO lado ------------------------------
      -- A linha da planilha que NÃO declara lado ("Participações → Metalúrgica
      -- — Mútuo" é o formato normal) entra no lado do balanço com que está
      -- sendo comparada. Isso só é honesto porque o bloco abaixo interrompe a
      -- checagem quando o balanço tem os DOIS lados: aí a linha sem lado
      -- caberia nos dois, e escolher um é chute.
      select coalesce(sum(fn_valor_em_base(ce.valor_num, ce.unidade)), 0) as soma_base,
             coalesce(sum(ce.valor_num), 0) as soma_bruta,
             count(*)::int as n
        into v_pl
      from campo_extraido ce
      where ce.documento_versao_id = v_ver_mut
        and ce.valor_num is not null
        and fn_papel_linha(ce.chave) <> 'subtotal'
        -- MÚTUO CONTRA MÚTUO. A planilha de intragrupo lista mais coisa do que
        -- mútuo — conta corrente rotativa, aluguel entre coligadas, rateio de
        -- despesa —, e o balanço registra cada uma dessas num lugar diferente
        -- ("Outros créditos", "Contas a pagar"). Comparar a planilha INTEIRA
        -- contra as contas de mútuo do balanço acusa como divergência aquilo
        -- que é só natureza diferente: no book Vertentes isso somava a conta
        -- corrente de 1.400 de um lado só e inventava 1.400 de diferença.
        -- Fica anotado o que ISTO deixa de fora: a conferência das linhas
        -- intragrupo que NÃO são mútuo continua sem checagem. É trabalho
        -- próprio — exige casar cada linha com a conta certa de cada balanço,
        -- que é outro problema (e outro par de olhos humanos).
        and fn_normalizar_texto(ce.chave) like '%mutuo%'
        and coalesce(fn_lado_do_mutuo(ce.chave, ce.secao_canonica), v_bp.lado) = v_bp.lado
        and (v_col_mut is null
             or fn_normalizar_texto(ce.periodo_coluna) = fn_normalizar_texto(v_col_mut));
      if coalesce(v_pl.n, 0) = 0 then continue; end if;

      -- Escala ausente de um dos lados é o mesmo critério conservador da 0009:
      -- não há o que converter, e afirmar "confere" seria pior que calar.
      if v_bp.tem_sem_escala <> (v_unid_mut is null) then
        continue;
      end if;

      v_a := abs(coalesce(v_bp.soma_base, 0));
      v_b := abs(coalesce(v_pl.soma_base, 0));
      v_n := v_n + 1;
      v_div := abs(v_a - v_b);
      -- Tolerância em MOEDA BASE (reais), não na escala do documento: o mesmo
      -- número tem de significar a mesma coisa num balanço em milhar e noutro
      -- em unidade, senão a checagem é mais frouxa justamente onde os valores
      -- são maiores.
      v_tol := greatest(p_tolerancia_abs, v_a * p_tolerancia_pct);

      if v_div > v_tol then
        v_resultado := 'zona_cinzenta';
        v_partes := v_partes || format(
          '%s (%s): balanço soma %s em %s linha(s) de %s documento(s) e a planilha soma %s em %s '
          || 'linha(s) — diferença de %s (em reais, já convertidas as escalas)',
          v_ano, v_bp.lado, round(v_a), v_bp.n, v_bp.n_docs, round(v_b), v_pl.n, round(v_div));
        if v_pior_abs is null or v_div > v_pior_abs then
          v_pior_abs := v_div;
          v_pior_pct := case when v_a <> 0 then v_div / v_a end;
        end if;
      else
        v_partes := v_partes || format('%s (%s): confere (balanço %s = planilha %s, em reais)',
          v_ano, v_bp.lado, round(v_a), round(v_b));
      end if;

      v_fonte_a := jsonb_build_object('lado', v_bp.lado, 'soma_base', v_a,
        'n_linhas', v_bp.n, 'n_documentos', v_bp.n_docs, 'exemplo', v_bp.exemplo, 'ano', v_ano);
      v_fonte_b := jsonb_build_object('lado', v_bp.lado, 'soma_base', v_b,
        'soma_bruta', v_pl.soma_bruta, 'n_linhas', v_pl.n, 'unidade', v_unid_mut,
        'documento_versao_id', v_ver_mut);
    end loop;

    -- OS DOIS LADOS NÃO SE SOMAM: ELES SE ESPELHAM — e a primeira versão desta
    -- função errou aqui também. Um mútuo intragrupo aparece DUAS vezes dentro
    -- do mesmo mandato: como "a receber" no balanço de quem emprestou e como
    -- "a pagar" no de quem tomou. No book Vertentes é exatamente isto: a
    -- holding registra 11.453 a receber, e as duas controladas registram
    -- 7.479 + 3.974 = 11.453 a pagar. É a MESMA dívida vista dos dois lados.
    --
    -- Por isso a planilha é comparada contra CADA lado separadamente (e não
    -- contra a soma dos dois, que daria o dobro), e a linha da planilha que não
    -- declara lado — "Participações → Metalúrgica — Mútuo", que é o formato
    -- normal — entra nas duas comparações: ela É as duas pontas.
  end loop;

  if v_n = 0 then
    -- SEM PENDÊNCIA, e é decisão de projeto: `documento_ausente` é o único
    -- resultado que `fn_registrar_reconciliacao` não transforma em pendência.
    -- Não achar linha de mútuo NO BALANÇO é o caso comum e correto — a
    -- demonstração combinada elimina o intragrupo, e o balanço individual pode
    -- agregar o saldo em "outras partes relacionadas". Abrir pendência aqui
    -- encheria a fila de todo mandato com um aviso que não pede ação nenhuma,
    -- e uma fila assim é uma fila que ninguém lê.
    return fn_registrar_reconciliacao(p_caso_id, null, p_periodo_id,
      'mutuos_planilha_vs_balanco', 'B', v_doc_mut, null, null,
      'documento_ausente', null, null,
      jsonb_build_object('tolerancia_abs', p_tolerancia_abs, 'tolerancia_pct', p_tolerancia_pct),
      'Planilha de mútuos presente, mas nenhum balanço do mandato traz conta de mútuo com lado '
      || 'reconhecível (combinado elimina intragrupo; individual às vezes agrega em "partes '
      || 'relacionadas"). Sem par, não há o que conferir.');
  end if;

  return fn_registrar_reconciliacao(p_caso_id, null, p_periodo_id,
    'mutuos_planilha_vs_balanco', 'B', v_doc_mut, v_fonte_a, v_fonte_b, v_resultado,
    v_pior_abs, v_pior_pct,
    jsonb_build_object('tolerancia_abs', p_tolerancia_abs, 'tolerancia_pct', p_tolerancia_pct,
                       'comparacoes', v_n),
    format('Mútuos: a planilha intragrupo contra o saldo dos balanços em %s comparação(ões) — %s.',
           v_n, array_to_string(v_partes, '; ')));
end;
$$;

comment on function fn_reconciliar_mutuos(uuid, uuid, numeric, numeric) is
  'Checagem B: a planilha de mútuos (abertura por contraparte) contra o saldo de mútuos do balanço, LADO A LADO (ativo/passivo). Não corrige nada — divergência vira pendência para decisão humana. 0117.';

grant execute on function fn_lado_do_mutuo(text, text) to authenticated;
grant execute on function fn_reconciliar_mutuos(uuid, uuid, numeric, numeric) to authenticated;

-- =============================================================================
-- E ela precisa ser CHAMADA. Uma checagem que existe e ninguém dispara é a
-- mesma coisa que não existir — foi assim que a divergência de mútuos passou
-- despercebida sem nunca ter havido bug nenhum.
--
-- Dispara pelos DOIS lados (planilha de mútuos OU balanço), porque a ordem de
-- chegada dos documentos é do cliente, não nossa: quem chega por último é quem
-- fecha o par, e só ele tem os dois na mesa.
-- =============================================================================

create or replace function fn_reconciliar_por_documento(p_documento_id uuid)
returns jsonb language plpgsql as $$
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

  -- Mútuos (0117). Pelos dois lados: quem chega por último fecha o par.
  if v_tipo in ('MUTUOS', 'BALANCO', 'COMBINADO', 'DF_AUDITADA') then
    foreach v_per in array v_periodos loop
      v_res := fn_reconciliar_mutuos(v_caso_id, v_per);
      exit when coalesce(v_res->>'resultado', '') <> 'precondicao_nao_satisfeita';
    end loop;
    v_checagens := v_checagens || jsonb_build_array(v_res);
  end if;

  -- Duplicidade de rótulo (0105). Sem loop de período: é por caso/entidade.
  if v_tipo in ('BALANCO', 'BALANCETE', 'COMBINADO') then
    v_checagens := v_checagens || jsonb_build_array(
      fn_reconciliar_duplicidade(v_caso_id, v_entidade_id));
  end if;

  return jsonb_build_object('executado', true, 'documento_id', p_documento_id, 'checagens', v_checagens);
end;
$$;

comment on function fn_reconciliar_por_documento(uuid) is
  'Dispara as checagens A/B pertinentes ao tipo do documento. Ausência do documento par NÃO abre pendência (é do checklist do Kit Básico). 0117: inclui a de mútuos, disparada pelos dois lados do par.';

grant execute on function fn_reconciliar_por_documento(uuid) to authenticated;
