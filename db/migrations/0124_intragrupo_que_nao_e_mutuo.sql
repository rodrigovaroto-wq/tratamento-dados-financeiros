-- 0124 — A CONFERÊNCIA DAS LINHAS INTRAGRUPO QUE NÃO SÃO MÚTUO.
--
-- O ITEM ESTAVA ABERTO NO `ESTADO.md` COM A DIFICULDADE CERTA ESCRITA:
--
--     "A conferência das linhas intragrupo que NÃO são mútuo (conta corrente
--      rotativa, aluguel entre coligadas, rateio de despesa). Elas moram na mesma
--      planilha que a 0117 passou a conferir, mas cada uma casa com uma conta
--      DIFERENTE do balanço — e escolher errado inventa divergência. É trabalho
--      próprio."
--
-- ------------------------------------------------- A PRIMEIRA IDEIA ERA ERRADA
-- O caminho óbvio — comparar a planilha intragrupo contra o balanço, como a
-- `0117` faz com os mútuos — não serve, e a razão é dimensional. O documento que
-- a taxonomia tem para as outras naturezas é `FAT_INTRAGRUPO`, "Faturamento
-- intragrupo": é FLUXO do exercício. O balanço traz ESTOQUE na data. Comparar os
-- dois só coincide quando nada foi pago no ano — que é o que acontece no book
-- (por construção) e não é o que acontece num mandato.
--
-- No book Canastra os quatro valores batem (2.900, 5.200, 940, 1.900 aparecem no
-- faturamento E no balanço), e escrever a checagem em cima disso teria produzido
-- um teste verde sobre uma comparação sem sentido — a mesma forma de defeito que
-- a `0123` acabou de achar.
--
-- ------------------------------------------ O QUE SE CONFERE, ENTÃO: O ESPELHO
-- Todo saldo intragrupo aparece DUAS VEZES dentro do mandato: a receber no
-- balanço de quem tem o crédito, a pagar no de quem tem a obrigação. É identidade
-- contábil, não heurística, e não precisa de segundo documento nenhum — os
-- balanços que o mandato já tem bastam.
--
-- A `0123` provou a ideia num caso (os dois lados do mútuo, que se confirmaram em
-- 16.300 e apontaram a planilha como a parte errada). Esta migration a generaliza
-- para as outras naturezas.
--
-- ------------------------- E O PAREAMENTO NÃO É PELA NATUREZA, É PELO PAR DE
-- ------------------------- EMPRESAS. Isto é a resposta à dificuldade citada.
-- A tentação é agrupar por natureza (aluguel com aluguel, fornecimento com
-- fornecimento). Não funciona, e o dado do book mostra por que: **as duas pontas
-- da mesma relação são nomeadas de formas diferentes por cada empresa.**
--
--     Canastra Indústria:  "Contas a receber intragrupo - Canastra Comercial"
--     Canastra Comercial:  "Fornecedores intragrupo - Canastra Indústria"
--
-- Quem vende chama de "contas a receber"; quem compra chama de "fornecedores".
-- Pela natureza elas nunca se encontram. Pelo PAR DE EMPRESAS, encontram sempre —
-- e o que se afirma passa a ser a coisa verdadeira: *a posição líquida intragrupo
-- entre A e B tem de fechar dos dois lados*. Nenhuma linha precisa ser casada com
-- "a conta certa": a linha DIZ com quem é.
--
-- ------------------------------------------------- COMO A CONTRAPARTE É LIDA
-- Do próprio rótulo, contra a lista de entidades DO CASO. O rótulo intragrupo tem
-- a forma "<o que é> - <quem é>", e o sufixo depois do separador é o nome da
-- contraparte. Medido nos nove rótulos do book (`fn_contraparte_intragrupo`):
--
--     "Conta corrente a pagar - CN Transportes e Logística"  → CN TRANSPORTES ✓
--     "Aluguéis a pagar - Canastra Imobiliária SPE"          → SPE ✓
--     "Fornecedores intragrupo - Canastra Agroflorestal"      → AGROFLORESTAL ✓
--     "Contas a receber intragrupo - Canastra Comercial"      → COMERCIAL ✓
--     "Aluguéis a receber - terceiros"                        → (nada) ✓
--     "Fornecedores nacionais"                                → (nada) ✓
--     "Duplicatas a receber de clientes - mercado interno"     → (nada) ✓
--
-- Seis de seis intragrupo casadas com a empresa certa, três de três externas
-- corretamente ignoradas. Não é lista de palavras: é o documento nomeando a
-- contraparte e o caso sabendo quem são as suas empresas.
--
-- ----------------------------------------------------- O QUE FICA DE FORA, E POR QUÊ
--  • MÚTUO — é da `fn_reconciliar_mutuos`. Duas checagens sobre a mesma linha é
--    como as duas divergem, e a `0123` acabou de pagar essa lição.
--  • MÚTUO COM SÓCIO — não tem espelho no mandato (a contraparte é o quotista).
--  • O DOCUMENTO COMBINADO — ele não é balanço de empresa nenhuma: as linhas
--    intragrupo dele são ELIMINAÇÕES, e uma eliminação nomeia as DUAS pontas
--    ("Conta corrente CN Transportes × Canastra Indústria"). Incluí-lo contaria
--    cada relação uma terceira vez.
--  • PAR EM QUE UMA DAS DUAS EMPRESAS NÃO ENTREGOU BALANÇO — aí a falta de
--    espelho é a falta do documento, e o Portão 1 já cobra isso. Acusar
--    divergência seria transformar documento que não chegou em erro de número.
--
-- --------------------------------------------------------------------- MEDIDO
-- Canastra (extração fiel): os quatro pares fecham — Agro↔Indústria 2.900,
-- Comercial↔Indústria 5.200, SPE↔Indústria 940, Indústria↔CN Transportes 1.900.
-- ZERO pendências, que é o resultado certo para um book cuja única divergência
-- plantada é a dos mútuos. Vertentes: nada muda (a conta corrente de 1.400 e o
-- aluguel de 640 da planilha não têm par de balanço, e sem par não há checagem).

-- ---------------------------------------------------------------------------
-- A CONTRAPARTE QUE O RÓTULO NOMEIA.
--
-- Devolve a entidade DO CASO que o rótulo nomeia como contraparte, ou null.
-- `p_entidade_dona` é excluída: linha do balanço de A que nomeia A é rótulo
-- redundante, não relação intragrupo.
--
-- Os separadores cobertos são os que aparecem em documento de verdade: hífen
-- simples, travessão, "×" e "→" (os dois últimos vêm de planilha de mútuos e de
-- quadro de eliminação). O TRECHO TESTADO É O ÚLTIMO: em "Conta corrente a pagar
-- - CN Transportes" o que interessa está depois do separador, e em "A → B" o
-- destinatário também.
-- ---------------------------------------------------------------------------
create or replace function fn_contraparte_intragrupo(
  p_caso_id       uuid,
  p_chave         text,
  p_entidade_dona uuid default null
) returns uuid language sql stable as $$
  with pedacos as (
    select trim(x) as parte
    from unnest(regexp_split_to_array(coalesce(p_chave, ''), '\s+(?:-|—|–|×|x|→)\s+')) as x
    -- O primeiro pedaço é o QUE a conta é ("Conta corrente a pagar"); a
    -- contraparte está nos seguintes. Sem este corte, "Fornecedores nacionais"
    -- casaria com qualquer empresa cujo nome tivesse um token em comum.
    offset 1
  )
  select e.id
  from entidade e, pedacos p
  where e.caso_id = p_caso_id
    and (p_entidade_dona is null or e.id <> p_entidade_dona)
    and length(p.parte) >= 4
    and fn_mesma_entidade(p.parte, e.razao_social)
  limit 1;
$$;

comment on function fn_contraparte_intragrupo(uuid, text, uuid) is
  '0124: a empresa DO CASO que o rótulo nomeia como contraparte (o sufixo depois do separador), ou null. É o que permite conferir intragrupo sem adivinhar qual conta casa com qual.';

grant execute on function fn_contraparte_intragrupo(uuid, text, uuid) to authenticated;


-- ---------------------------------------------------------------------------
-- O LADO DA LINHA — crédito (ativo) ou obrigação (passivo).
--
-- A SEÇÃO CANÔNICA VEM PRIMEIRO, e o rótulo é só o desempate. `fn_lado_do_mutuo`
-- (0117) decide pelo rótulo ("a pagar" × "a receber") porque a conta de mútuo é
-- nomeada assim por convenção. Aqui não dá para contar com isso: "Fornecedores
-- intragrupo - X" é obrigação e não tem nem "a pagar" nem "a receber" no nome.
-- A seção canônica, quando existe, é a resposta direta e não depende de vocabulário.
-- ---------------------------------------------------------------------------
create or replace function fn_lado_intragrupo(p_chave text, p_secao_canonica text default null)
returns text language sql immutable as $$
  select case
    when p_secao_canonica like 'ativo%'   then 'ativo'
    when p_secao_canonica like 'passivo%' then 'passivo'
    -- Sem seção canônica, cai no critério da 0117 sobre o rótulo.
    when fn_normalizar_texto(coalesce(p_chave, '')) ~ 'a receber|a recuperar|credito' then 'ativo'
    when fn_normalizar_texto(coalesce(p_chave, '')) ~ 'a pagar|fornecedor|obrigac' then 'passivo'
    else null
  end;
$$;

comment on function fn_lado_intragrupo(text, text) is
  '0124: crédito (ativo) ou obrigação (passivo) de uma linha intragrupo. Seção canônica primeiro; rótulo só como desempate, porque "Fornecedores intragrupo - X" não diz "a pagar".';

grant execute on function fn_lado_intragrupo(text, text) to authenticated;


-- ---------------------------------------------------------------------------
-- A NATUREZA — só para a MENSAGEM, nunca para o pareamento.
--
-- Ela entra porque "os 1.900 entre Indústria e CN Transportes não fecham" é menos
-- útil que "a conta corrente entre Indústria e CN Transportes não fecha": o
-- analista precisa saber ONDE procurar. Mas ela NÃO pode ser chave de comparação,
-- e o motivo está no cabeçalho: cada ponta da mesma relação usa o vocabulário
-- dela ("contas a receber" × "fornecedores").
-- ---------------------------------------------------------------------------
create or replace function fn_natureza_intragrupo(p_chave text, p_secao text default null)
returns text language sql immutable as $$
  select case
    when fn_normalizar_texto(coalesce(p_chave, '') || ' ' || coalesce(p_secao, '')) ~ 'mutuo'
      then 'mútuo'
    when fn_normalizar_texto(coalesce(p_chave, '')) ~ 'conta corrente'  then 'conta corrente'
    when fn_normalizar_texto(coalesce(p_chave, '')) ~ 'alugue|locac|arrendament'
      then 'aluguel'
    when fn_normalizar_texto(coalesce(p_chave, '')) ~ 'frete|logistic|transport'
      then 'frete'
    when fn_normalizar_texto(coalesce(p_chave, '')) ~ 'fornecedor|compra|insumo|materia'
      then 'fornecimento'
    when fn_normalizar_texto(coalesce(p_chave, '')) ~ 'rateio|compartilh|servic|honorar'
      then 'rateio de despesa'
    else 'conta intragrupo'
  end;
$$;

comment on function fn_natureza_intragrupo(text, text) is
  '0124: a natureza da linha intragrupo, para a MENSAGEM dizer onde procurar. Não é chave de pareamento — cada ponta da relação usa o vocabulário dela.';

grant execute on function fn_natureza_intragrupo(text, text) to authenticated;


-- ---------------------------------------------------------------------------
-- A CHECAGEM: a posição intragrupo entre CADA PAR de empresas fecha dos dois lados?
-- ---------------------------------------------------------------------------
create or replace function fn_reconciliar_intragrupo(
  p_caso_id        uuid,
  p_periodo_id     uuid,
  p_tolerancia_abs numeric default 50000,
  p_tolerancia_pct numeric default 0.005
) returns jsonb language plpgsql as $$
declare
  v_ano int;
  v_par record;
  v_resultado text := 'ok';
  v_partes text[] := '{}';
  v_n int := 0;
  v_pior_abs numeric; v_pior_pct numeric;
  v_div numeric; v_tol numeric;
  v_fonte_a jsonb := '[]'::jsonb;
  v_pares_conferidos int := 0;
begin
  foreach v_ano in array fn_anos_alvo(p_periodo_id) loop
    for v_par in
      with balancos as (
        -- UM DOCUMENTO POR ENTIDADE, e `COMBINADO` fica FORA (ver o cabeçalho:
        -- as linhas intragrupo dele são eliminações, que nomeiam as duas pontas).
        select distinct on (d.entidade_id) d.id, d.entidade_id
        from documento d
        where d.caso_id = p_caso_id
          and d.tipo_taxonomia in ('BALANCO', 'BALANCETE', 'DF_AUDITADA')
          and d.entidade_id is not null
        order by d.entidade_id,
                 array_position(array['BALANCO','DF_AUDITADA','BALANCETE'], d.tipo_taxonomia),
                 d.criado_em desc
      ), linhas as (
        select
          b.entidade_id as dona,
          fn_contraparte_intragrupo(p_caso_id, ce.chave, b.entidade_id) as contraparte,
          fn_lado_intragrupo(ce.chave, ce.secao_canonica) as lado,
          fn_valor_em_base(ce.valor_num, ce.unidade) as valor_base,
          fn_natureza_intragrupo(ce.chave, ce.secao) as natureza,
          ce.chave,
          ce.unidade
        from balancos b
        join lateral (select fn_versao_atual(b.id) as ver) v on true
        join campo_extraido ce on ce.documento_versao_id = v.ver
        where ce.valor_num is not null
          and ce.valor_num <> 0
          and fn_papel_linha(ce.chave) <> 'subtotal'
          -- MÚTUO É DA OUTRA CHECAGEM. Uma linha, uma régua.
          and not fn_texto_nomeia_mutuo(ce.chave)
          and not fn_mutuo_com_socio(ce.chave, ce.secao)
          and (fn_coluna_periodo_do_ano(v.ver, v_ano) is null
               or fn_normalizar_texto(ce.periodo_coluna)
                  = fn_normalizar_texto(fn_coluna_periodo_do_ano(v.ver, v_ano)))
      ), intragrupo as (
        select * from linhas
        where contraparte is not null and lado is not null
          -- ESCALA AUSENTE NÃO SE CONVERTE, e o critério é o da 0009: sem saber a
          -- escala, afirmar "confere" seria pior que calar.
          and unidade is not null
      )
      select
        least(dona, contraparte)    as ent_a,
        greatest(dona, contraparte) as ent_b,
        sum(case when lado = 'ativo'   then abs(valor_base) else 0 end) as receber,
        sum(case when lado = 'passivo' then abs(valor_base) else 0 end) as pagar,
        count(*)::int as n_linhas,
        string_agg(distinct natureza, ', ' order by natureza) as naturezas,
        min(chave) as exemplo
      from intragrupo
      group by 1, 2
      having
        -- OS DOIS LADOS TÊM DE EXISTIR, e a exigência é sobre o par: A e B ambas
        -- com balanço no mandato. Sem isso a falta de espelho é a falta do
        -- documento — que o Portão 1 já cobra — e não erro de número.
        count(distinct dona) = 2
    loop
      v_pares_conferidos := v_pares_conferidos + 1;
      v_div := abs(v_par.receber - v_par.pagar);
      -- Tolerância em MOEDA BASE, como no resto da família (0117/0123): o mesmo
      -- número tem de significar a mesma coisa num balanço em milhar e noutro em
      -- unidade.
      v_tol := greatest(p_tolerancia_abs, greatest(v_par.receber, v_par.pagar) * p_tolerancia_pct);
      v_fonte_a := v_fonte_a || jsonb_build_array(jsonb_build_object(
        'ano', v_ano,
        'entidade_a', (select razao_social from entidade where id = v_par.ent_a),
        'entidade_b', (select razao_social from entidade where id = v_par.ent_b),
        'a_receber', v_par.receber, 'a_pagar', v_par.pagar,
        'naturezas', v_par.naturezas, 'n_linhas', v_par.n_linhas, 'exemplo', v_par.exemplo));
      if v_div > v_tol then
        v_n := v_n + 1;
        v_resultado := 'zona_cinzenta';
        v_partes := v_partes || format(
          '%s — %s × %s (%s): um lado registra %s a receber e o outro %s a pagar, diferença de %s '
          || '(em reais, já convertidas as escalas). A mesma posição intragrupo tem de fechar nos '
          || 'dois balanços; exemplo de linha: "%s"',
          v_ano,
          (select razao_social from entidade where id = v_par.ent_a),
          (select razao_social from entidade where id = v_par.ent_b),
          v_par.naturezas, round(v_par.receber), round(v_par.pagar), round(v_div), v_par.exemplo);
        if v_pior_abs is null or v_div > v_pior_abs then
          v_pior_abs := v_div;
          v_pior_pct := case when greatest(v_par.receber, v_par.pagar) <> 0
                             then v_div / greatest(v_par.receber, v_par.pagar) end;
        end if;
      end if;
    end loop;
  end loop;

  if v_pares_conferidos = 0 then
    -- SEM PENDÊNCIA, pela mesma doutrina da 0117: não haver par intragrupo com os
    -- DOIS balanços no mandato é o caso comum e correto — mandato de uma empresa
    -- só não tem intragrupo, e mandato de grupo pode não ter recebido todos os
    -- balanços. Abrir pendência aqui encheria a fila com um aviso que não pede
    -- ação, e fila assim é fila que ninguém lê.
    return fn_registrar_reconciliacao(p_caso_id, null, p_periodo_id,
      'intragrupo_espelho', 'B', null, null, null,
      'documento_ausente', null, null,
      jsonb_build_object('tolerancia_abs', p_tolerancia_abs, 'tolerancia_pct', p_tolerancia_pct),
      'Nenhum par intragrupo com os DOIS balanços no mandato: não há espelho para conferir.');
  end if;

  return fn_registrar_reconciliacao(p_caso_id, null, p_periodo_id,
    'intragrupo_espelho', 'B', null, v_fonte_a, null, v_resultado,
    v_pior_abs, v_pior_pct,
    jsonb_build_object('tolerancia_abs', p_tolerancia_abs, 'tolerancia_pct', p_tolerancia_pct,
                       'pares_conferidos', v_pares_conferidos, 'pares_divergentes', v_n),
    case when v_n = 0
      then format('Intragrupo (fora mútuo): %s par(es) de empresas conferido(s) pelo espelho — '
                  || 'todos fecham nos dois balanços.', v_pares_conferidos)
      else format('Intragrupo (fora mútuo): %s de %s par(es) de empresas NÃO fecham — %s.',
                  v_n, v_pares_conferidos, array_to_string(v_partes, '; ')) end);
end;
$$;

comment on function fn_reconciliar_intragrupo(uuid, uuid, numeric, numeric) is
  '0124: a posição intragrupo entre cada PAR de empresas fecha nos dois balanços? Pareia pelo par de empresas (a contraparte vem do rótulo), não pela natureza — cada ponta usa o vocabulário dela. Mútuo fica com fn_reconciliar_mutuos.';

grant execute on function fn_reconciliar_intragrupo(uuid, uuid, numeric, numeric) to authenticated;


-- ---------------------------------------------------------------------------
-- E ela entra no disparo por documento.
-- ---------------------------------------------------------------------------
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

  -- Mútuos (0117/0123). Pelos dois lados: quem chega por último fecha o par.
  if v_tipo in ('MUTUOS', 'BALANCO', 'COMBINADO', 'DF_AUDITADA') then
    foreach v_per in array v_periodos loop
      v_res := fn_reconciliar_mutuos(v_caso_id, v_per);
      exit when coalesce(v_res->>'resultado', '') <> 'precondicao_nao_satisfeita';
    end loop;
    v_checagens := v_checagens || jsonb_build_array(v_res);
  end if;

  -- Intragrupo FORA mútuo (0124). Disparada por balanço individual, que é a
  -- única peça de que ela precisa — não há documento par a esperar. `COMBINADO`
  -- não dispara e não é lido: as linhas intragrupo dele são eliminações.
  if v_tipo in ('BALANCO', 'BALANCETE', 'DF_AUDITADA') then
    foreach v_per in array v_periodos loop
      v_res := fn_reconciliar_intragrupo(v_caso_id, v_per);
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
  'Dispara as checagens A/B pertinentes ao tipo do documento. Ausência do documento par NÃO abre pendência (é do checklist do Kit Básico). 0117: mútuos, pelos dois lados. 0124: intragrupo fora mútuo, pelo espelho entre cada par de empresas.';

grant execute on function fn_reconciliar_por_documento(uuid) to authenticated;
