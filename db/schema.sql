--
--

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: public; Type: SCHEMA; Schema: -; Owner: -
--

CREATE SCHEMA public;

--
-- Name: SCHEMA public; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON SCHEMA public IS 'standard public schema';

--
-- Name: caso_status; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.caso_status AS ENUM (
    'intake',
    'em_triagem',
    'completude_ok',
    'em_revisao',
    'aprovado',
    'pronto_para_base',
    'bloqueado',
    'aguardando_cliente'
);

--
-- Name: decisao_tipo; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.decisao_tipo AS ENUM (
    'aprovacao',
    'override',
    'ressalva',
    'mudanca_dial',
    'correcao_classificacao'
);

--
-- Name: documento_status; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.documento_status AS ENUM (
    'solicitado',
    'recebido',
    'em_validacao',
    'valido',
    'invalido',
    'recebido_nao_valido',
    'vencido'
);

--
-- Name: granularidade; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.granularidade AS ENUM (
    'caso',
    'entidade',
    'periodo',
    'entidade_periodo'
);

--
-- Name: legibilidade; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.legibilidade AS ENUM (
    'ok',
    'degradado',
    'ilegivel'
);

--
-- Name: nivel_autonomia; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.nivel_autonomia AS ENUM (
    'N0',
    'N1',
    'N2',
    'N3'
);

--
-- Name: obrigatoriedade; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.obrigatoriedade AS ENUM (
    'obrigatorio',
    'complementar'
);

--
-- Name: origem_arquivo; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.origem_arquivo AS ENUM (
    'supabase_storage',
    'sharepoint'
);

--
-- Name: pendencia_estado; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.pendencia_estado AS ENUM (
    'aberta',
    'em_correcao_interna',
    'reenviada_ao_cliente',
    'aceita_com_ressalva',
    'rejeitada',
    'resolvida'
);

--
-- Name: pendencia_severidade; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.pendencia_severidade AS ENUM (
    'bloqueante',
    'importante',
    'complementar'
);

--
-- Name: pendencia_tipo; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.pendencia_tipo AS ENUM (
    'item_faltante',
    'periodo_faltante',
    'item_vencido',
    'arquivo_ilegivel',
    'arquivo_corrompido',
    'entidade_incorreta',
    'periodo_incorreto',
    'tipo_incorreto',
    'classificacao_pendente',
    'divergencia_reconciliacao',
    'precondicao_nao_satisfeita',
    'extracao_baixa_confianca',
    'extracao_padrao_suspeito',
    'extracao_falhou',
    'item_sem_conteudo',
    'documento_nao_extraido',
    'linha_exigida_ausente'
);

--
-- Name: premissa_formula; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.premissa_formula AS ENUM (
    'indice_macro',
    'crescimento_composto',
    'pct_de_linha',
    'dias_de_giro',
    'valor_por_ano',
    'preco_x_volume',
    'curva_mensal'
);

--
-- Name: premissa_natureza; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.premissa_natureza AS ENUM (
    'macro',
    'receita',
    'custo',
    'despesa',
    'giro',
    'investimento',
    'divida',
    'tributo',
    'socios',
    'sazonalidade',
    'operacional'
);

--
-- Name: sensibilidade_lgpd; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.sensibilidade_lgpd AS ENUM (
    'nenhuma',
    'pii',
    'pii_sensivel'
);

--
-- Name: fn_aceitar_extracao(uuid, text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_aceitar_extracao(p_documento_versao_id uuid, p_autor text, p_motivo text DEFAULT NULL::text) RETURNS jsonb
    LANGUAGE plpgsql
    AS $$
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

--
-- Name: fn_ano4(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_ano4(a text) RETURNS text
    LANGUAGE sql IMMUTABLE
    AS $_$
  select case
    when a is null or a = '' then a
    when length(a) = 4 then a
    when a ~ '^\d{1,2}$' and (a)::int <= 79 then (2000 + (a)::int)::text
    when a ~ '^\d{1,2}$' then (1900 + (a)::int)::text
    else a end;
$_$;

--
-- Name: fn_ano_da_coluna(text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_ano_da_coluna(p_periodo_coluna text, p_referencia text) RETURNS integer
    LANGUAGE sql IMMUTABLE
    AS $_$
  -- Quatro dígitos que comecem com 19 ou 20, na coluna primeiro. `substring` com
  -- classe de caractere e não regexp guloso: "12M25" não pode virar 1225.
  select coalesce(
    (select (regexp_match(p_periodo_coluna, '((?:19|20)\d{2})'))[1]::int),
    (select (regexp_match(p_referencia, '((?:19|20)\d{2})'))[1]::int),
    -- "12M25"/"24,25" — dois dígitos que o repositório usa como referência curta.
    -- 2000+ é seguro para este projeto (mandato de reestruturação não tem balanço
    -- de 1925), e o teste trava o comportamento.
    (select 2000 + (regexp_match(p_referencia, '(\d{2})\s*$'))[1]::int)
  );
$_$;

--
-- Name: FUNCTION fn_ano_da_coluna(p_periodo_coluna text, p_referencia text); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.fn_ano_da_coluna(p_periodo_coluna text, p_referencia text) IS 'Exercício de uma ocorrência: ano da coluna de período, senão da referência do período do documento, senão dois dígitos finais + 2000. A coluna vem primeiro porque num balanço comparativo é ela que diz de qual exercício é o número.';

--
-- Name: fn_anos_alvo(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_anos_alvo(p_periodo_id uuid) RETURNS integer[]
    LANGUAGE plpgsql STABLE
    AS $$
declare
  t text; r text; anos int[];
begin
  if p_periodo_id is null then return array[null]::int[]; end if;
  select tipo, referencia into t, r from periodo where id = p_periodo_id;
  anos := fn_anos_periodo(t, r);
  if cardinality(coalesce(anos, '{}'::int[])) = 0 then return array[null]::int[]; end if;
  return anos;
end;
$$;

--
-- Name: fn_anos_periodo(text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_anos_periodo(p_tipo text, p_ref text) RETURNS integer[]
    LANGUAGE plpgsql IMMUTABLE
    AS $_$
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
$_$;

--
-- Name: FUNCTION fn_anos_periodo(p_tipo text, p_ref text); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.fn_anos_periodo(p_tipo text, p_ref text) IS 'Conjunto ordenado de anos implícito num período (qualquer notação). Vazio quando a referência não ancora ano.';

--
-- Name: fn_anos_texto(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_anos_texto(p_texto text) RETURNS integer[]
    LANGUAGE plpgsql IMMUTABLE
    AS $_$
declare
  anos int[] := '{}';
  tok  text;
  m    text[];
begin
  if p_texto is null then return anos; end if;
  foreach tok in array regexp_split_to_array(p_texto, '[^0-9]+') loop
    if tok ~ '^(19|20)[0-9]{2}$' then
      anos := anos || (tok)::int;
    end if;
  end loop;
  if cardinality(anos) = 0 then
    -- ano de 2 dígitos no fim ("dez/25", "12M25")
    m := regexp_match(p_texto, '([0-9]{2})[^0-9]*$');
    if m is not null then
      anos := anos || ('20' || m[1])::int;
    end if;
  end if;
  select array_agg(distinct a order by a) into anos from unnest(anos) a;
  return coalesce(anos, '{}'::int[]);
end;
$_$;

--
-- Name: fn_aplicar_premissa_em_lote(uuid, text, text, text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_aplicar_premissa_em_lote(p_caso_id uuid, p_secao_canonica text, p_premissa text, p_autor text, p_sazonalidade text DEFAULT NULL::text) RETURNS jsonb
    LANGUAGE plpgsql
    AS $$
declare
  v_n int := 0;
  v_ignoradas jsonb := '[]'::jsonb;
  v_r jsonb;
  v_linha record;
begin
  if not exists (
    select 1 from caso_premissa where caso_id = p_caso_id and premissa_codigo = p_premissa and ativo
  ) then
    return jsonb_build_object('recusado', true, 'escopo', 'premissa',
      'motivo_recusa', format('A premissa "%s" não está ativa neste caso.', p_premissa));
  end if;

  for v_linha in
    select l.secao_canonica, l.chave, l.entidade, l.papel
    from fn_linhas_para_modelagem(p_caso_id) l
    where coalesce(l.secao_canonica, '') = coalesce(p_secao_canonica, '')
  loop
    if v_linha.papel <> 'conta' then
      v_ignoradas := v_ignoradas || jsonb_build_object('linha', v_linha.chave, 'papel', v_linha.papel);
      continue;
    end if;
    v_r := fn_vincular_linha_premissa(p_caso_id, v_linha.secao_canonica, v_linha.chave,
                                      v_linha.entidade, p_premissa, p_autor, p_sazonalidade);
    if coalesce((v_r->>'recusado')::boolean, false) then
      -- Global: não adianta tentar as outras.
      if v_r->>'escopo' = 'premissa' then
        return v_r;
      end if;
      -- Por linha: registra e segue.
      --
      -- HONESTIDADE SOBRE ESTE RAMO: com a guarda lendo o papel da SEÇÃO, ele
      -- fica INALCANÇÁVEL a partir daqui — o laço só percorre linhas cujo papel
      -- na seção é 'conta', e a guarda agora responde exatamente isso para a
      -- mesma seção. Ou seja: **este ramo não está coberto por teste**, e não dá
      -- para cobrir sem religar o defeito que a migration corrige.
      --
      -- Fica assim mesmo, por uma razão: ele é a diferença entre "uma linha
      -- divergente é declarada" e "o lote inteiro cai", e a divergência volta a
      -- existir no instante em que alguém mudar um dos dois lados sem mudar o
      -- outro — que é precisamente o que aconteceu entre a 0039 e a 0042.
      v_ignoradas := v_ignoradas || jsonb_build_object(
        'linha', v_linha.chave,
        'papel', coalesce(v_r->>'papel', 'recusada'),
        'motivo', v_r->>'motivo_recusa');
      continue;
    end if;
    v_n := v_n + 1;
  end loop;

  insert into decisao (caso_id, tipo, autor, motivo, payload)
    values (p_caso_id, 'override', p_autor,
            format('Premissa "%s" aplicada em lote a %s linha(s) da seção "%s" (%s fora por papel)',
                   p_premissa, v_n, coalesce(p_secao_canonica, '(sem seção)'),
                   jsonb_array_length(v_ignoradas)),
            jsonb_build_object('premissa', p_premissa, 'secao_canonica', p_secao_canonica,
                               'n_linhas', v_n, 'sazonalidade', p_sazonalidade,
                               'ignoradas', v_ignoradas));

  return jsonb_build_object('caso_id', p_caso_id, 'secao_canonica', p_secao_canonica,
                            'premissa', p_premissa, 'n_linhas', v_n,
                            'n_ignoradas', jsonb_array_length(v_ignoradas),
                            'ignoradas', v_ignoradas);
end;
$$;

--
-- Name: fn_aprovar_caso(uuid, text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_aprovar_caso(p_caso_id uuid, p_autor text, p_motivo text DEFAULT NULL::text) RETURNS jsonb
    LANGUAGE plpgsql
    AS $$
declare
  v_aval   jsonb;
  v_status caso_status;
begin
  v_aval := fn_avaliar_portao2(p_caso_id);
  select status into v_status from caso where id = p_caso_id;

  if not (v_aval->>'elegivel')::boolean then
    insert into evento_auditoria (ator, acao, entidade_ref, depois)
      values (p_autor, 'aprovacao_recusada', 'caso:'||p_caso_id,
              jsonb_build_object('avaliacao', v_aval, 'motivo_informado', p_motivo));
    return v_aval || jsonb_build_object(
      'recusado', true,
      'motivo_recusa',
        'Este caso NÃO é elegível ao Portão 2: '
        || array_to_string(array(select jsonb_array_elements_text(v_aval->'motivos')), '; ')
        || '. A regra é determinística (f0/04) e não tem exceção por autor — resolva as '
        || 'pendências ou registre ressalva onde ela é permitida.');
  end if;

  -- Idempotente: aprovar um caso já aprovado não gera decisão nova.
  if v_status in ('aprovado', 'pronto_para_base') then
    return v_aval || jsonb_build_object('ja_aprovado', true);
  end if;

  update caso set status = 'aprovado' where id = p_caso_id;

  insert into decisao (caso_id, tipo, autor, motivo, payload)
    values (p_caso_id, 'aprovacao', p_autor,
            coalesce(p_motivo, 'Portão 2: caso aprovado'),
            jsonb_build_object('portao', 2, 'avaliacao', v_aval, 'status_anterior', v_status));

  insert into evento_auditoria (ator, acao, entidade_ref, antes, depois)
    values (p_autor, 'transicao_status', 'caso:'||p_caso_id,
            jsonb_build_object('status', v_status),
            jsonb_build_object('status', 'aprovado', 'avaliacao', v_aval));

  return v_aval || jsonb_build_object('elegivel', true, 'status_atual', 'aprovado', 'aprovado', true);
end;
$$;

--
-- Name: FUNCTION fn_aprovar_caso(p_caso_id uuid, p_autor text, p_motivo text); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.fn_aprovar_caso(p_caso_id uuid, p_autor text, p_motivo text) IS 'Portão 2 por CASO. Recusa (payload com recusado=true) quando fn_avaliar_portao2 diz que não; aprova, registra decisao+evento e transiciona para `aprovado` quando diz que sim. Sem exceção para nenhum autor: a regra de f0/04 é determinística.';

--
-- Name: fn_ativar_premissa(uuid, text, jsonb, text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_ativar_premissa(p_caso_id uuid, p_codigo text, p_valores jsonb, p_origem text, p_autor text) RETURNS jsonb
    LANGUAGE plpgsql
    AS $$
declare
  v_nome     text;
  v_natureza text;
  v_valores  jsonb := coalesce(p_valores, '{}'::jsonb);
  v_origem   text := p_origem;
  v_ano      int;
  v_anos     int;
begin
  select nome, natureza::text into v_nome, v_natureza
  from premissa_catalogo where codigo = p_codigo and ativo;
  if v_nome is null then
    insert into evento_auditoria (ator, acao, entidade_ref, depois)
      values (p_autor, 'premissa_recusada', 'caso:'||p_caso_id,
              jsonb_build_object('codigo', p_codigo, 'porque', 'codigo inexistente ou inativo no catalogo'));
    return jsonb_build_object('recusado', true,
      'motivo_recusa', format('A premissa "%s" não existe no catálogo (ou está inativa). '
                              'Premissa nova entra por semente no catálogo, não por caso.', p_codigo));
  end if;

  if v_natureza = 'macro' and v_valores = '{}'::jsonb then
    select coalesce(ultimo_exercicio_real, extract(year from now())::int) + 1,
           coalesce(anos_projetados, 5)
      into v_ano, v_anos
    from caso_modelagem where caso_id = p_caso_id;
    -- Sem parâmetros do caso ainda: usa o ano corrente + 1 e 5 anos. A tela pede
    -- os parâmetros no passo 1, mas o analista pode ativar a premissa antes, e
    -- devolver vazio aqui só empurraria o trabalho para ele.
    v_ano := coalesce(v_ano, extract(year from now())::int + 1);
    v_anos := coalesce(v_anos, 5);
    v_valores := fn_premissa_valores_sugeridos(p_codigo, v_ano, v_anos);
    if v_valores <> '{}'::jsonb then
      v_origem := 'focus';
    end if;
  end if;

  insert into caso_premissa (caso_id, premissa_codigo, valores, origem, ativo, atualizado_por, atualizado_em)
    values (p_caso_id, p_codigo, v_valores, v_origem, true, p_autor, now())
  on conflict (caso_id, premissa_codigo) do update
    set valores = excluded.valores, origem = excluded.origem, ativo = true,
        atualizado_por = excluded.atualizado_por, atualizado_em = now();

  insert into decisao (caso_id, tipo, autor, motivo, payload)
    values (p_caso_id, 'override', p_autor,
            format('Premissa "%s" ativada/ajustada na modelagem%s', v_nome,
                   case when v_origem = 'focus' then ' (valores do Focus)' else '' end),
            jsonb_build_object('premissa', p_codigo, 'valores', v_valores, 'origem', v_origem));

  return jsonb_build_object('caso_id', p_caso_id, 'premissa', p_codigo, 'ativo', true,
                            'valores', v_valores, 'origem', v_origem);
end;
$$;

--
-- Name: fn_avaliar_guardas_extracao(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_avaliar_guardas_extracao(p_documento_versao_id uuid) RETURNS jsonb
    LANGUAGE plpgsql STABLE
    AS $$
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

--
-- Name: fn_avaliar_portao2(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_avaliar_portao2(p_caso_id uuid) RETURNS jsonb
    LANGUAGE plpgsql STABLE
    AS $$
declare
  v_bloqueantes      int;
  v_nao_sobrepujavel int;
  v_ressalvas        int;
  v_rejeitadas       int;
  v_rejeitadas_ns    int;
  v_motivos          text[] := array[]::text[];
  v_status           caso_status;
begin
  select status into v_status from caso where id = p_caso_id;
  if v_status is null then
    raise exception 'caso % não encontrado', p_caso_id;
  end if;

  -- A ÚNICA condição de bloqueio: bloqueante que ninguém decidiu ainda.
  select count(*) into v_bloqueantes
  from pendencia
  where caso_id = p_caso_id and severidade = 'bloqueante'
    and estado in ('aberta', 'em_correcao_interna', 'reenviada_ao_cliente');

  -- INFORMAÇÃO, não bloqueio (0109). As três contagens abaixo não entram em
  -- `elegivel`; elas existem para a tela e para a `decisao` de aprovação
  -- dizerem sobre o que se passou por cima. Um caso aprovado com seis
  -- ressalvas continua sendo distinguível de um caso limpo — o que ele deixou
  -- de ser é impedido.
  select count(*) into v_nao_sobrepujavel
  from pendencia
  where caso_id = p_caso_id and sobrepujavel = false
    and estado in ('aberta', 'em_correcao_interna', 'reenviada_ao_cliente');

  select count(*) into v_ressalvas
  from pendencia
  where caso_id = p_caso_id and estado = 'aceita_com_ressalva';

  select count(*) filter (where true),
         count(*) filter (where sobrepujavel = false)
    into v_rejeitadas, v_rejeitadas_ns
  from pendencia
  where caso_id = p_caso_id and estado = 'rejeitada';

  if v_bloqueantes > 0 then
    v_motivos := array_append(v_motivos,
      format('%s pendência(s) BLOQUEANTE(s) sem decisão', v_bloqueantes));
  end if;

  return jsonb_build_object(
    'caso_id', p_caso_id,
    'status_atual', v_status,
    'elegivel', array_length(v_motivos, 1) is null,
    'motivos', to_jsonb(v_motivos),
    'bloqueantes_abertas', v_bloqueantes,
    'nao_sobrepujaveis_abertas', v_nao_sobrepujavel,
    'ressalvas_ativas', v_ressalvas,
    'ressalvas_expiradas', 0,
    'rejeitadas', v_rejeitadas,
    'rejeitadas_nao_sobrepujaveis', v_rejeitadas_ns,
    'teto_ressalvas', null
  );
end;
$$;

--
-- Name: FUNCTION fn_avaliar_portao2(p_caso_id uuid); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.fn_avaliar_portao2(p_caso_id uuid) IS 'Portão 2 (0109): elegível quando não há pendência BLOQUEANTE sem decisão. O teto de ressalvas e a lista fechada de f0/04 deixaram de bloquear por decisão do dono — as contagens continuam publicadas como informação, e vão gravadas dentro da decisão de aprovação.';

--
-- Name: fn_coluna_entidade(uuid, uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_coluna_entidade(p_documento_versao_id uuid, p_entidade_id uuid) RETURNS text
    LANGUAGE plpgsql
    AS $$
declare
  v_tem_col boolean;
  v_razao   text;
  v_col     text;
  v_dono    boolean;
begin
  select exists (
    select 1 from campo_extraido ce
    where ce.documento_versao_id = p_documento_versao_id and ce.entidade_coluna is not null
  ) into v_tem_col;
  if not v_tem_col then return null; end if;

  select e.razao_social into v_razao from entidade e where e.id = p_entidade_id;
  if v_razao is not null then
    -- 0030: era `fn_normalizar_texto(ce.entidade_coluna) = fn_normalizar_texto(v_razao)`.
    -- Igualdade exata nunca casa apelido de coluna com razão social completa, que é
    -- o formato NORMAL de um balanço combinado.
    select ce.entidade_coluna into v_col
    from campo_extraido ce
    where ce.documento_versao_id = p_documento_versao_id
      and ce.entidade_coluna is not null
      and fn_mesma_entidade(ce.entidade_coluna, v_razao)
    limit 1;
    if v_col is not null then return v_col; end if;
  end if;

  select (d.entidade_id = p_entidade_id) into v_dono
  from documento_versao dv join documento d on d.id = dv.documento_id
  where dv.id = p_documento_versao_id;

  if coalesce(v_dono, false) then
    -- Total do próprio documento. Mesmo vocabulário de `tipoColunaNaoEntidade`
    -- em portal/src/lib/export.ts, para o portal e o banco concordarem.
    select ce.entidade_coluna into v_col
    from campo_extraido ce
    where ce.documento_versao_id = p_documento_versao_id
      and ce.entidade_coluna is not null
      and fn_normalizar_texto(ce.entidade_coluna) ~ '^(combinad|consolidad|total|soma)'
    limit 1;
    if v_col is not null then return v_col; end if;
  end if;

  return E'\x01';
end;
$$;

--
-- Name: fn_coluna_periodo_do_ano(uuid, integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_coluna_periodo_do_ano(p_documento_versao_id uuid, p_ano integer) RETURNS text
    LANGUAGE plpgsql STABLE
    AS $$
declare
  v_col text;
  v_tem boolean;
begin
  select ce.periodo_coluna into v_col
  from campo_extraido ce
  where ce.documento_versao_id = p_documento_versao_id
    and ce.periodo_coluna is not null
    and p_ano = any (fn_anos_texto(ce.periodo_coluna))
  group by ce.periodo_coluna
  order by count(*) desc, ce.periodo_coluna
  limit 1;
  if v_col is not null then return v_col; end if;

  select exists (
    select 1 from campo_extraido ce
    where ce.documento_versao_id = p_documento_versao_id and ce.periodo_coluna is not null
  ) into v_tem;
  return case when v_tem then E'\x01' else null end;
end;
$$;

--
-- Name: fn_conferir_lote(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_conferir_lote(p_caso_id uuid) RETURNS jsonb
    LANGUAGE plpgsql
    AS $$
declare
  v_total       int;
  v_nao_extr    int := 0;
  v_d           record;
  v_nomes       text[] := array[]::text[];
begin
  if not exists (select 1 from caso where id = p_caso_id) then
    return jsonb_build_object('recusado', true,
      'motivo_recusa', format('caso %s não encontrado', p_caso_id));
  end if;

  select count(*) into v_total from documento where caso_id = p_caso_id;

  -- Resolve as que voltaram a ter extração (reprocessamento fecha sozinho).
  update pendencia p
     set estado = 'resolvida', resolvida_em = now(), resolvida_por = 'sistema:conferir_lote'
   where p.caso_id = p_caso_id
     and p.tipo = 'documento_nao_extraido'
     and p.estado <> 'resolvida'
     and not exists (
       select 1 from fn_documentos_nao_extraidos(p_caso_id) x
        where p.motivo = 'lote:nao_extraido:' || x.documento_id::text
     );

  for v_d in select * from fn_documentos_nao_extraidos(p_caso_id) loop
    v_nao_extr := v_nao_extr + 1;
    v_nomes := v_nomes || coalesce(v_d.nome_original, '(sem nome)');

    if not exists (
      select 1 from pendencia p
       where p.caso_id = p_caso_id
         and p.tipo = 'documento_nao_extraido'
         and p.estado <> 'resolvida'
         and p.motivo = 'lote:nao_extraido:' || v_d.documento_id::text
    ) then
      insert into pendencia (caso_id, origem_estagio, tipo, severidade, sobrepujavel,
                             descricao, documento_id, motivo)
        values (p_caso_id, 'extracao', 'documento_nao_extraido', 'bloqueante', false,
          format('O documento "%s" (%s) foi registrado no caso, mas a extração NUNCA foi '
                 'chamada para ele — não é extração vazia nem truncada: a chamada não '
                 'aconteceu. O book sai sem NENHUMA linha deste documento. Reprocessar o '
                 'lote; se repetir, o defeito é de roteamento no workflow (ver o log da '
                 'execução no n8n).',
                 coalesce(v_d.nome_original, '(sem nome)'),
                 coalesce(v_d.tipo_taxonomia, 'sem tipo')),
          v_d.documento_id, 'lote:nao_extraido:' || v_d.documento_id::text);
    end if;
  end loop;

  return jsonb_build_object(
    'caso_id', p_caso_id,
    'documentos_no_caso', v_total,
    'documentos_extraidos', v_total - v_nao_extr,
    'documentos_nao_extraidos', v_nao_extr,
    'nomes_nao_extraidos', to_jsonb(v_nomes),
    -- O lote só está íntegro quando TODO documento registrado passou pela
    -- extração. É a pergunta que faltava, e a resposta é um booleano só.
    'lote_integro', v_nao_extr = 0
  );
end;
$$;

--
-- Name: FUNCTION fn_conferir_lote(p_caso_id uuid); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.fn_conferir_lote(p_caso_id uuid) IS 'Conferência de FORA do caminho da extração: nomeia os documentos que o pipeline pulou e abre pendência bloqueante por documento. Existe porque as guardas de extração vivem DENTRO da extração, e não cobrem o caso de a chamada nunca ter sido feita (Teste V45: 19 de 35).';

--
-- Name: fn_conferir_modelagem(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_conferir_modelagem(p_caso_id uuid) RETURNS jsonb
    LANGUAGE sql STABLE
    AS $$
  with linhas as (
    select * from fn_linhas_para_modelagem(p_caso_id)
  ),
  contas as (
    select rotulo_norm from linhas where papel = 'conta'
  ),
  vinculadas as (
    select distinct l.rotulo_norm
    from caso_linha_premissa l
    where l.caso_id = p_caso_id and l.premissa_codigo is not null
      and l.rotulo_norm in (select rotulo_norm from contas)
  ),
  orfaos as (
    select distinct l.rotulo_norm
    from caso_linha_premissa l
    where l.caso_id = p_caso_id and l.premissa_codigo is not null
      and l.rotulo_norm not in (select rotulo_norm from linhas)
  ),
  nao_projetaveis as (
    select jsonb_object_agg(papel, n) as j
    from (select papel, count(*) as n from linhas where papel <> 'conta' group by papel) x
  ),
  premissas as (
    select count(*) filter (where ativo) as ativas,
           array_agg(premissa_codigo order by premissa_codigo)
             filter (where ativo and (valores is null or valores = '{}'::jsonb)) as sem_valor
    from caso_premissa where caso_id = p_caso_id
  ),
  param as (
    select to_jsonb(m) as j from caso_modelagem m where m.caso_id = p_caso_id
  )
  select jsonb_build_object(
    'parametros', (select j from param),
    'premissas_ativas', (select ativas from premissas),
    'premissas_sem_valor', to_jsonb(coalesce((select sem_valor from premissas), array[]::text[])),
    'linhas_do_caso', (select count(*) from contas),
    'linhas_nao_projetaveis', coalesce((select j from nao_projetaveis), '{}'::jsonb),
    'linhas_com_premissa', (select count(*) from vinculadas),
    'linhas_sem_premissa', greatest((select count(*) from contas) - (select count(*) from vinculadas), 0),
    'vinculos_orfaos', to_jsonb(coalesce(
      (select array_agg(rotulo_norm order by rotulo_norm) from orfaos), array[]::text[])),
    'pronto', (select j from param) is not null
              and (select ativas from premissas) > 0
              and coalesce(array_length((select sem_valor from premissas), 1), 0) = 0
  );
$$;

--
-- Name: FUNCTION fn_conferir_modelagem(p_caso_id uuid); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.fn_conferir_modelagem(p_caso_id uuid) IS 'Conferência da modelagem do caso. 0101: uma única passada por fn_linhas_para_modelagem (antes eram cinco, duas delas dentro de exists correlacionado — uma execução completa por vínculo), o que a tirava do statement_timeout do Supabase.';

--
-- Name: fn_contas_repetindo_valor(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_contas_repetindo_valor(p_documento_versao_id uuid) RETURNS TABLE(valor numeric, n_contas integer)
    LANGUAGE sql STABLE
    AS $$
  select ce.valor_num, count(distinct ce.chave)::int
  from campo_extraido ce
  where ce.documento_versao_id = p_documento_versao_id
    and ce.valor_num is not null
    and ce.valor_num <> 0
    -- MATERIAL: 1% do maior valor da versão. Valores pequenos (18, 40, 180)
    -- coincidem à toa e geraram os falsos da v24.
    and abs(ce.valor_num) >= (
      select greatest(coalesce(max(abs(c2.valor_num)), 0) * 0.01, 1)
      from campo_extraido c2 where c2.documento_versao_id = p_documento_versao_id
    )
    -- …e NÃO são totais de grupo. Ativo = Passivo + PL faz essas quatro linhas
    -- terem o mesmo valor por construção contábil.
    and not fn_rotulo_estrutural(ce.chave, array['ativo'])
    and not fn_rotulo_estrutural(ce.chave, array['passivo','patrimonio'])
  group by ce.valor_num, coalesce(ce.entidade_coluna, ''), coalesce(ce.periodo_coluna, '')
  order by count(distinct ce.chave) desc
  limit 1;
$$;

--
-- Name: fn_decidir_pendencia(uuid, text, text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_decidir_pendencia(p_pendencia_id uuid, p_autor text, p_decisao text, p_motivo text DEFAULT NULL::text) RETURNS jsonb
    LANGUAGE plpgsql
    AS $$
declare
  v_p       pendencia%rowtype;
  v_estado  pendencia_estado;
  v_motivo  text := nullif(trim(coalesce(p_motivo, '')), '');
  v_rotulo  text;
  v_tipo    decisao_tipo;
begin
  select * into v_p from pendencia where id = p_pendencia_id;
  if v_p.id is null then
    raise exception 'pendência % não encontrada', p_pendencia_id;
  end if;

  -- Os três botões da tela, nas palavras da tela.
  case p_decisao
    when 'contatar_cliente' then
      v_estado := 'reenviada_ao_cliente'; v_rotulo := 'Contatar o Cliente'; v_tipo := null;
    when 'prosseguir' then
      v_estado := 'aceita_com_ressalva';  v_rotulo := 'Prosseguir sem resolução'; v_tipo := 'ressalva';
    when 'nao_procede' then
      v_estado := 'rejeitada';            v_rotulo := 'Pendência não procede'; v_tipo := 'override';
    else
      return jsonb_build_object('recusado', true, 'pendencia_id', p_pendencia_id,
        'motivo_recusa', format('Decisão desconhecida: %s. São três — contatar_cliente, '
                                'prosseguir, nao_procede.', p_decisao));
  end case;

  -- Clicar de novo no mesmo botão é no-op declarado: dois cliques não viram
  -- duas decisões na trilha.
  if v_p.estado = v_estado then
    return jsonb_build_object('sem_mudanca', true, 'pendencia_id', p_pendencia_id,
                              'estado', v_estado, 'rotulo', v_rotulo,
                              'avaliacao', fn_avaliar_portao2(v_p.caso_id));
  end if;

  -- `resolvida` é do SISTEMA: ela significa "a condição que abriu a pendência
  -- deixou de valer", e um clique humano não pode afirmar isso. Trocar uma
  -- resolvida por decisão humana reescreveria o que o motor mediu.
  if v_p.estado = 'resolvida' then
    return jsonb_build_object('recusado', true, 'pendencia_id', p_pendencia_id,
      'motivo_recusa', 'Esta pendência já foi RESOLVIDA pelo próprio sistema: o problema que a '
        || 'abriu deixou de existir. Não há o que decidir sobre ela.');
  end if;

  update pendencia
     set estado        = v_estado,
         motivo        = coalesce(v_motivo, motivo),
         -- `resolvida_em`/`por` marcam QUANDO e QUEM tirou a pendência da fila.
         -- Para o estado de tratamento ficam nulos: contatar o cliente não tira
         -- nada da fila, só diz que alguém está cuidando.
         resolvida_em  = case when v_estado in ('rejeitada', 'aceita_com_ressalva') then now() else null end,
         resolvida_por = case when v_estado in ('rejeitada', 'aceita_com_ressalva') then p_autor else null end
   where id = p_pendencia_id;

  -- Decisão sobre o MÉRITO vira `decisao`; "estou cuidando" não vira, porque
  -- ninguém decidiu nada ainda.
  if v_tipo is not null then
    insert into decisao (caso_id, tipo, autor, motivo, payload)
      values (v_p.caso_id, v_tipo, p_autor, coalesce(v_motivo, v_rotulo),
              jsonb_build_object('acao', 'decidir_pendencia', 'decisao', p_decisao,
                                 'rotulo', v_rotulo, 'pendencia_id', p_pendencia_id,
                                 'tipo', v_p.tipo, 'severidade', v_p.severidade,
                                 'sobrepujavel', v_p.sobrepujavel,
                                 'estado_anterior', v_p.estado));
  end if;

  insert into evento_auditoria (ator, acao, entidade_ref, antes, depois)
    values (p_autor, 'pendencia_decidida', 'pendencia:'||p_pendencia_id,
            jsonb_build_object('estado', v_p.estado),
            jsonb_build_object('estado', v_estado, 'rotulo', v_rotulo,
                               'caso_id', v_p.caso_id, 'motivo', v_motivo));

  return jsonb_build_object('decidida', true, 'pendencia_id', p_pendencia_id,
                            'estado', v_estado, 'rotulo', v_rotulo,
                            'avaliacao', fn_avaliar_portao2(v_p.caso_id));
end;
$$;

--
-- Name: FUNCTION fn_decidir_pendencia(p_pendencia_id uuid, p_autor text, p_decisao text, p_motivo text); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.fn_decidir_pendencia(p_pendencia_id uuid, p_autor text, p_decisao text, p_motivo text) IS 'Os três botões da tela em UMA função: contatar_cliente (não libera o portão — o documento ainda não chegou), prosseguir (aceita com ressalva) e nao_procede (rejeita). Sem motivo obrigatório, sem expiração e sem teto, por decisão do dono (0109). Nada é apagado e tudo é contado.';

--
-- Name: fn_definir_modelagem(uuid, text, integer, text, text, text, integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_definir_modelagem(p_caso_id uuid, p_entidade text, p_ultimo_exercicio_real integer, p_indice_macro text, p_setor text, p_autor text, p_anos_projetados integer DEFAULT 5) RETURNS jsonb
    LANGUAGE plpgsql
    AS $$
declare
  v_antes jsonb;
begin
  if not exists (select 1 from caso where id = p_caso_id) then
    raise exception 'caso % não encontrado', p_caso_id;
  end if;

  select to_jsonb(m) into v_antes from caso_modelagem m where m.caso_id = p_caso_id;

  insert into caso_modelagem (caso_id, entidade, ultimo_exercicio_real, indice_macro, setor,
                              anos_projetados, atualizado_por, atualizado_em)
    values (p_caso_id, p_entidade, p_ultimo_exercicio_real, p_indice_macro, p_setor,
            p_anos_projetados, p_autor, now())
  on conflict (caso_id) do update
    set entidade = excluded.entidade,
        ultimo_exercicio_real = excluded.ultimo_exercicio_real,
        indice_macro = excluded.indice_macro,
        setor = excluded.setor,
        anos_projetados = excluded.anos_projetados,
        atualizado_por = excluded.atualizado_por,
        atualizado_em = now();

  -- Parâmetro de modelagem é DECISÃO DE ANÁLISE: trocar a entidade modelada ou o
  -- corte do último exercício real muda todos os números projetados do book.
  insert into evento_auditoria (ator, acao, entidade_ref, antes, depois)
    values (p_autor, 'modelagem_parametros', 'caso:'||p_caso_id, v_antes,
            (select to_jsonb(m) from caso_modelagem m where m.caso_id = p_caso_id));

  return (select to_jsonb(m) from caso_modelagem m where m.caso_id = p_caso_id);
end;
$$;

--
-- Name: fn_desativar_premissa(uuid, text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_desativar_premissa(p_caso_id uuid, p_codigo text, p_autor text) RETURNS jsonb
    LANGUAGE plpgsql
    AS $$
declare
  v_nome     text;
  v_ativa    boolean;
  v_vinculos int := 0;
  v_sazo     int := 0;
  v_orfas    int := 0;
begin
  select nome into v_nome from premissa_catalogo where codigo = p_codigo;
  if v_nome is null then
    insert into evento_auditoria (ator, acao, entidade_ref, depois)
      values (p_autor, 'premissa_recusada', 'caso:'||p_caso_id,
              jsonb_build_object('codigo', p_codigo, 'porque', 'codigo inexistente no catalogo',
                                 'acao_pedida', 'desativar'));
    return jsonb_build_object('recusado', true,
      'motivo_recusa', format('A premissa "%s" não existe no catálogo.', p_codigo));
  end if;

  select ativo into v_ativa
  from caso_premissa where caso_id = p_caso_id and premissa_codigo = p_codigo;

  -- Nunca ativada, ou já desativada. Não é exceção — é um clique que não tem o
  -- que desfazer, e a resposta precisa dizer isso em vez de fingir sucesso.
  if v_ativa is null or v_ativa = false then
    return jsonb_build_object('recusado', true,
      'motivo_recusa', format('A premissa "%s" não está ativa neste caso — não há o que remover.',
                              v_nome));
  end if;

  -- 1. O vínculo que dirige a projeção da linha.
  update caso_linha_premissa
     set premissa_codigo = null, atualizado_por = p_autor, atualizado_em = now()
   where caso_id = p_caso_id and premissa_codigo = p_codigo;
  get diagnostics v_vinculos = row_count;

  -- 2. O mesmo código usado como CURVA MENSAL da linha (natureza sazonalidade).
  update caso_linha_premissa
     set sazonalidade_codigo = null, atualizado_por = p_autor, atualizado_em = now()
   where caso_id = p_caso_id and sazonalidade_codigo = p_codigo;
  get diagnostics v_sazo = row_count;

  -- 3. Linha que ficou sem as duas não é "linha sem premissa": é linha sobre a
  -- qual não há mais decisão registrada. Mantê-la faria a trilha afirmar uma
  -- escolha que o analista desfez.
  delete from caso_linha_premissa
   where caso_id = p_caso_id and premissa_codigo is null and sazonalidade_codigo is null;
  get diagnostics v_orfas = row_count;

  update caso_premissa
     set ativo = false, atualizado_por = p_autor, atualizado_em = now()
   where caso_id = p_caso_id and premissa_codigo = p_codigo;

  -- `valores` NÃO é apagado, de propósito: reativar a premissa devolve o que já
  -- tinha sido digitado. Remover por engano custa um clique para desfazer, não
  -- cinco anos de valores redigitados.
  insert into decisao (caso_id, tipo, autor, motivo, payload)
    values (p_caso_id, 'override', p_autor,
            format('Premissa "%s" REMOVIDA da modelagem (%s vínculo(s) e %s sazonalidade(s) desfeitos)',
                   v_nome, v_vinculos, v_sazo),
            jsonb_build_object('premissa', p_codigo, 'ativo', false,
                               'n_vinculos_desfeitos', v_vinculos,
                               'n_sazonalidades_desfeitas', v_sazo,
                               'n_linhas_removidas', v_orfas));

  return jsonb_build_object(
    'caso_id', p_caso_id, 'premissa', p_codigo, 'nome', v_nome, 'ativo', false,
    'n_vinculos_desfeitos', v_vinculos,
    'n_sazonalidades_desfeitas', v_sazo,
    'n_linhas_removidas', v_orfas);
end;
$$;

--
-- Name: FUNCTION fn_desativar_premissa(p_caso_id uuid, p_codigo text, p_autor text); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.fn_desativar_premissa(p_caso_id uuid, p_codigo text, p_autor text) IS 'Desativa a premissa no caso e LIMPA os vínculos que ela dirigia (premissa e sazonalidade), devolvendo quantos foram desfeitos. Vínculo órfão faria tela, conferência e export lerem o mesmo caso de três formas diferentes. `valores` é preservado para a reativação.';

--
-- Name: fn_diagnostico_modelagem(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_diagnostico_modelagem(p_caso_id uuid) RETURNS jsonb
    LANGUAGE sql STABLE
    AS $$
  -- marca-0102
  with instalada as (
    select jsonb_object_agg(p.proname, pg_get_functiondef(p.oid) like '%marca-0102%') as j
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname in ('fn_versao_com_extracao', 'fn_linhas_para_modelagem',
                        'fn_papel_do_rotulo_no_caso', 'fn_sazonalidade_do_caso',
                        'fn_valores_por_ano', 'fn_linhas_do_tipo')
  ),
  ocorrencia as (
    select dv.id = fn_versao_com_extracao(d.id) as vigente
    from campo_extraido ce
    join documento_versao dv on dv.id = ce.documento_versao_id
    join documento d on d.id = dv.documento_id
    where d.caso_id = p_caso_id and ce.valor_num is not null
  ),
  linha as (select papel from fn_linhas_para_modelagem(p_caso_id))
  select jsonb_build_object(
    'caso_id', p_caso_id,
    'correcoes_instaladas', (select j from instalada),
    'conferir_modelagem_e_0101',
      (select pg_get_functiondef(p.oid) like '%with linhas as%'
       from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname = 'public' and p.proname = 'fn_conferir_modelagem' limit 1),
    'documentos', (select count(*) from documento where caso_id = p_caso_id),
    'documentos_com_versao_superada', (
      select count(*) from documento d
      where d.caso_id = p_caso_id
        and (select count(*) from documento_versao dv
             where dv.documento_id = d.id
               and exists (select 1 from campo_extraido ce where ce.documento_versao_id = dv.id)) > 1),
    'ocorrencias_total', (select count(*) from ocorrencia),
    'ocorrencias_vigentes', (select count(*) from ocorrencia where vigente),
    'ocorrencias_superadas', (select count(*) from ocorrencia where not vigente),
    'linhas', (select count(*) from linha),
    'linhas_projetaveis', (select count(*) from linha where papel = 'conta'),
    'linhas_por_papel', (select jsonb_object_agg(papel, n)
                         from (select papel, count(*) n from linha group by papel) x)
  );
$$;

--
-- Name: FUNCTION fn_diagnostico_modelagem(p_caso_id uuid); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.fn_diagnostico_modelagem(p_caso_id uuid) IS 'Diagnóstico da tela de Modelagem de um caso, para rodar no SQL Editor: se as correções da 0101/0102 estão INSTALADAS no banco (merge não é apply), quantas ocorrências vinham de versão superada, e quantas linhas a tela deve mostrar. Existe porque "já apliquei" e "ainda não apliquei" tinham a mesma aparência na tela.';

--
-- Name: fn_dial(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_dial(p_estagio text) RETURNS jsonb
    LANGUAGE sql STABLE
    AS $$
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

--
-- Name: fn_divergencias_indice_macro(numeric); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_divergencias_indice_macro(p_tolerancia numeric DEFAULT 0.011) RETURNS TABLE(serie text, data_ref date, fonte_a text, valor_a numeric, fonte_b text, valor_b numeric, delta numeric)
    LANGUAGE sql STABLE
    AS $$
  select a.serie, a.data_ref, a.fonte, a.valor, b.fonte, b.valor, abs(a.valor - b.valor)
  from indice_macro_obs a
  join indice_macro_obs b
    on b.serie = a.serie and b.data_ref = a.data_ref and b.fonte > a.fonte
  where abs(a.valor - b.valor) > p_tolerancia
  order by a.data_ref desc, a.serie;
$$;

--
-- Name: fn_documento_balanco(uuid, uuid, uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_documento_balanco(p_caso_id uuid, p_entidade_id uuid, p_periodo_id uuid) RETURNS uuid
    LANGUAGE sql STABLE
    AS $$
  select d.id
  from documento d
  where d.caso_id = p_caso_id
    and d.tipo_taxonomia in ('BALANCO', 'COMBINADO', 'BALANCETE')
    and (p_entidade_id is null or d.entidade_id = p_entidade_id)
    and (p_periodo_id is null or d.periodo_id = p_periodo_id
         or fn_periodos_compativeis(d.periodo_id, p_periodo_id))
  order by array_position(array['BALANCO', 'COMBINADO', 'BALANCETE'], d.tipo_taxonomia),
           d.criado_em desc
  limit 1;
$$;

--
-- Name: fn_documento_por_tipo(uuid, uuid, uuid, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_documento_por_tipo(p_caso_id uuid, p_entidade_id uuid, p_periodo_id uuid, p_tipo text) RETURNS uuid
    LANGUAGE sql STABLE
    AS $$
  select d.id
  from documento d
  where d.caso_id = p_caso_id
    and d.tipo_taxonomia = p_tipo
    and (p_entidade_id is null or d.entidade_id = p_entidade_id or d.entidade_id is null)
    and (p_periodo_id is null or d.periodo_id = p_periodo_id
         or fn_periodos_compativeis(d.periodo_id, p_periodo_id))
  order by d.criado_em desc
  limit 1;
$$;

--
-- Name: fn_documentos_nao_extraidos(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_documentos_nao_extraidos(p_caso_id uuid) RETURNS TABLE(documento_id uuid, tipo_taxonomia text, nome_original text)
    LANGUAGE sql STABLE
    AS $$
  select d.id, d.tipo_taxonomia,
         (select dv.nome_original from documento_versao dv
           where dv.documento_id = d.id order by dv.n_versao desc limit 1)
  from documento d
  where d.caso_id = p_caso_id
    and not exists (
      select 1
      from documento_versao dv
      join evento_auditoria ea
        on ea.acao = 'extracao_sombra'
       and ea.entidade_ref = 'documento_versao:' || dv.id::text
      where dv.documento_id = d.id
    )
  order by d.tipo_taxonomia, 3;
$$;

--
-- Name: FUNCTION fn_documentos_nao_extraidos(p_caso_id uuid); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.fn_documentos_nao_extraidos(p_caso_id uuid) IS 'Documentos do caso para os quais a extração NUNCA foi chamada (sem evento extracao_sombra em nenhuma versão). Zero linha com extração feita NÃO entra aqui — isso é 0111/0036.';

--
-- Name: fn_entidade_canonica(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_entidade_canonica(p_nome text) RETURNS text
    LANGUAGE sql IMMUTABLE
    AS $_$
  select nullif(
    trim(regexp_replace(
      regexp_replace(
        -- sufixos societários, no FIM do nome (é onde eles aparecem). 'spe' e
        -- 'scp' NÃO entram: em "Vertentes Imóveis SPE" a sigla faz parte do nome
        -- da sociedade de propósito específico, e tirá-la funde SPEs diferentes.
        regexp_replace(fn_normalizar_texto(p_nome),
          '\s+(ltda|limitada|s\s*a|sa|s\s*/\s*a|eireli|me|epp|mei|em recuperacao judicial|em rj)\.?\s*$',
          '', 'g'),
        '[.,;:/\\()''"-]', ' ', 'g'),
      '\s+', ' ', 'g')),
    '');
$_$;

--
-- Name: FUNCTION fn_entidade_canonica(p_nome text); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.fn_entidade_canonica(p_nome text) IS 'Forma canônica de nome de entidade para CASAMENTO: sem acento, pontuação nem sufixo societário. Não substitui razao_social, que preserva a grafia da fonte.';

--
-- Name: fn_excluir_caso(uuid, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_excluir_caso(p_caso_id uuid, p_autor text) RETURNS jsonb
    LANGUAGE plpgsql
    AS $$
declare
  v_nome  text;
  v_docs  int;
  v_campos int;
  v_pend  int;
begin
  select nome into v_nome from caso where id = p_caso_id;
  if v_nome is null then
    return jsonb_build_object('recusado', true,
      'motivo_recusa', 'Este mandato não existe mais — talvez alguém já o tenha excluído.');
  end if;

  select count(*) into v_docs from documento where caso_id = p_caso_id;
  select count(*) into v_campos from campo_extraido ce
    join documento_versao dv on dv.id = ce.documento_versao_id
    join documento d on d.id = dv.documento_id
   where d.caso_id = p_caso_id;
  select count(*) into v_pend from pendencia where caso_id = p_caso_id;

  -- A trilha ANTES do delete: se o delete falhar, sobra um registro de tentativa,
  -- que é informação; se registrássemos depois, uma falha no meio deixaria o
  -- caso apagado e nenhum rastro.
  insert into evento_auditoria (ator, acao, entidade_ref, antes)
    values (p_autor, 'caso_excluido', 'caso:'||p_caso_id,
            jsonb_build_object('nome', v_nome, 'documentos', v_docs,
                               'campos_extraidos', v_campos, 'pendencias', v_pend));

  delete from caso where id = p_caso_id;

  return jsonb_build_object('excluido', true, 'nome', v_nome,
                            'documentos', v_docs, 'campos_extraidos', v_campos,
                            'pendencias', v_pend);
end;
$$;

--
-- Name: FUNCTION fn_excluir_caso(p_caso_id uuid, p_autor text); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.fn_excluir_caso(p_caso_id uuid, p_autor text) IS 'Exclui o mandato e tudo que depende dele (cascade da 0001), devolvendo a contagem do que se perdeu. Grava a exclusão em evento_auditoria ANTES do delete — a trilha não tem FK para caso, então o rastro sobrevive ao caso.';

--
-- Name: fn_exigencias_do_caso(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_exigencias_do_caso(p_caso_id uuid) RETURNS TABLE(exigencia_id uuid, tipo_taxonomia text, conceito text, rotulo text, origem text, depende_de text[], severidade text, sobrepujavel boolean, descricao text, satisfeita boolean)
    LANGUAGE sql STABLE
    AS $$
  with tipos_com_conteudo as (
    select distinct d.tipo_taxonomia
    from documento d
    where d.caso_id = p_caso_id
      and fn_linhas_do_tipo(p_caso_id, d.tipo_taxonomia) > 0
  ),
  campos as (
    select d.tipo_taxonomia, ce.chave, ce.secao, ce.secao_canonica
    from documento d
    join campo_extraido ce on ce.documento_versao_id = fn_versao_com_extracao(d.id)
    where d.caso_id = p_caso_id
      and ce.valor_num is not null
  )
  select e.id, e.tipo_taxonomia, e.conceito, e.rotulo, e.origem, e.depende_de,
         e.severidade, e.sobrepujavel, e.descricao,
         case e.checagem
           when 'secao_presente' then exists (
             select 1 from campos c
             where c.tipo_taxonomia = e.tipo_taxonomia
               and c.secao_canonica = e.secao_canonica)
           when 'serie_mensal' then exists (
             select 1 from campos c
             where c.tipo_taxonomia = e.tipo_taxonomia
               and fn_mes_do_rotulo(c.chave) is not null)
           else exists (
             select 1
             from taxonomia_linha_localizador l, campos c
             where l.exigencia_id = e.id
               and c.tipo_taxonomia = e.tipo_taxonomia
               and case
                 when l.contra = 'estrutural' then fn_rotulo_estrutural(c.chave, l.termos_inclui)
                 else
                   not exists (
                     select 1 from unnest(l.termos_inclui) t
                     where fn_normalizar_texto(case when l.contra = 'secao'
                                               then coalesce(c.secao, '') else c.chave end)
                       not like '%' || fn_normalizar_texto(t) || '%')
                   and not exists (
                     select 1 from unnest(l.termos_exclui) t
                     where fn_normalizar_texto(case when l.contra = 'secao'
                                               then coalesce(c.secao, '') else c.chave end)
                       like '%' || fn_normalizar_texto(t) || '%')
               end)
         end as satisfeita
  from taxonomia_linha_exigida e
  join tipos_com_conteudo t on t.tipo_taxonomia = e.tipo_taxonomia
  where e.ativo;
$$;

--
-- Name: FUNCTION fn_exigencias_do_caso(p_caso_id uuid); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.fn_exigencias_do_caso(p_caso_id uuid) IS 'Exigências de linha aplicáveis ao caso (tipos presentes COM conteúdo), com satisfeita s/n. Casa contra a versão VIGENTE (0102), no formato de fn_valor_conceito (0009). Alimenta o passo 2b de fn_recomputar_completude e a tela do caso.';

--
-- Name: fn_falhas_abertas(text, timestamp with time zone); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_falhas_abertas(p_caso_nome text, p_desde timestamp with time zone) RETURNS TABLE(id uuid, etapa text, mensagem text, criado_em timestamp with time zone)
    LANGUAGE sql STABLE
    AS $$
  select f.id, f.etapa, f.mensagem, f.criado_em
  from execucao_falha f
  where f.visto_em is null
    and f.criado_em >= p_desde
    and (lower(f.caso_nome) = lower(trim(p_caso_nome))
         or f.caso_id in (select c.id from caso c where lower(c.nome) = lower(trim(p_caso_nome))))
  order by f.criado_em desc;
$$;

--
-- Name: fn_fator_escala(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_fator_escala(p_unidade text) RETURNS numeric
    LANGUAGE sql IMMUTABLE
    AS $_$
  select case
    when p_unidade is null or length(trim(p_unidade)) = 0 then null
    when fn_normalizar_texto(p_unidade) in ('unidade', 'unidades', 'reais', 'real', 'r$', 'brl') then 1
    when fn_normalizar_texto(p_unidade) in ('milhar', 'milhares', 'mil', 'r$ mil') then 1000
    when fn_normalizar_texto(p_unidade) in ('milhao', 'milhoes', 'milhao de reais') then 1000000
    else null
  end;
$_$;

--
-- Name: FUNCTION fn_fator_escala(p_unidade text); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.fn_fator_escala(p_unidade text) IS 'Fator multiplicativo para levar um valor à base (unidade). null quando a escala é ausente ou desconhecida.';

--
-- Name: fn_indice_macro_anual(integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_indice_macro_anual(p_desde_ano integer DEFAULT NULL::integer) RETURNS TABLE(serie text, ano integer, meses integer, retorno numeric, natureza text)
    LANGUAGE sql STABLE
    AS $$
  with preferida as (
    select distinct on (o.serie, o.data_ref)
      o.serie, o.data_ref, o.valor
    from indice_macro_obs o
    order by o.serie, o.data_ref,
      case o.fonte when 'IBGE/SIDRA' then 0 else 1 end
  ),
  -- Agrega uma vez por (serie, ano) e só então decide como o ano "rende",
  -- conforme a natureza da série. Pré-agregar (em vez de usar função de janela
  -- dentro de FILTER, que o Postgres recusa) mantém a intenção legível: para
  -- TAXA o ano é a composição dos meses; para NÍVEL é a variação entre o
  -- fechamento do ano anterior e o último fechamento do ano.
  por_ano as (
    select
      p.serie,
      extract(year from p.data_ref)::int as ano,
      count(*)::int                      as meses,
      (exp(sum(ln(1 + p.valor / 100.0))) - 1) * 100 as composto,
      max(p.data_ref)                    as ultima_data
    from preferida p
    where p_desde_ano is null or extract(year from p.data_ref)::int >= p_desde_ano
    group by p.serie, extract(year from p.data_ref)
  ),
  -- A BASE de cada ano para série de nível: a ÚLTIMA observação estritamente
  -- anterior ao ano. Vem de `preferida` inteira, não de `por_ano` — o filtro
  -- `p_desde_ano` corta o ano-base, e usar a série já filtrada faria o primeiro
  -- ano da janela pedida cair de novo no jan→dez. Ou seja: o recorte de leitura
  -- não pode mudar o número.
  base_anterior as (
    select
      a.serie,
      a.ano,
      (select p.valor
         from preferida p
        where p.serie = a.serie
          and p.data_ref < make_date(a.ano, 1, 1)
        order by p.data_ref desc
        limit 1) as valor
    from por_ano a
  )
  select
    a.serie,
    a.ano,
    a.meses,
    case s.natureza
      when 'taxa' then a.composto
      -- `nullif(ini.valor, 0)` continua: câmbio zero não existe, mas divisão
      -- por zero derrubaria a consulta inteira do export por causa de uma
      -- observação suja. E `ini.valor` NULL (primeiro ano da série) propaga
      -- NULL de propósito — ver o cabeçalho.
      else (fim.valor / nullif(ini.valor, 0) - 1) * 100
    end as retorno,
    s.natureza
  from por_ano a
  join indice_macro_serie s on s.codigo = a.serie
  left join base_anterior ini on ini.serie = a.serie and ini.ano = a.ano
  left join preferida fim on fim.serie = a.serie and fim.data_ref = a.ultima_data
  order by a.serie, a.ano;
$$;

--
-- Name: FUNCTION fn_indice_macro_anual(p_desde_ano integer); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.fn_indice_macro_anual(p_desde_ano integer) IS 'Retorno acumulado por ano-calendário. Série de TAXA acumula por composição; série de NÍVEL varia entre FECHAMENTOS (dez do ano anterior → dez do ano), e o primeiro ano da série sai com retorno NULL por não ter base. `meses` revela ano incompleto — incluí-lo numa média de 3/5/10 anos como ano cheio distorce a média.';

--
-- Name: fn_linhas_do_tipo(uuid, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_linhas_do_tipo(p_caso_id uuid, p_codigo text) RETURNS bigint
    LANGUAGE sql STABLE
    AS $$
  -- marca-0102
  select count(ce.id)
  from documento d
  join documento_versao dv on dv.documento_id = d.id
  join campo_extraido ce on ce.documento_versao_id = dv.id
  where d.caso_id = p_caso_id
    and d.tipo_taxonomia = p_codigo
    and dv.id = fn_versao_com_extracao(d.id);
$$;

--
-- Name: FUNCTION fn_linhas_do_tipo(p_caso_id uuid, p_codigo text); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.fn_linhas_do_tipo(p_caso_id uuid, p_codigo text) IS 'Quantas linhas extraídas o caso tem de um tipo de documento (insumo da completude, 0036). 0102: só a versão vigente — reextração dobrava a contagem e inflava a completude.';

--
-- Name: fn_linhas_para_modelagem(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_linhas_para_modelagem(p_caso_id uuid) RETURNS TABLE(secao_canonica text, chave text, rotulo_norm text, entidade text, valor_ultimo numeric, n_ocorrencias bigint, papel text, unidade text, moeda text, documentos text[], sobreposicao_suspeita boolean)
    LANGUAGE sql STABLE
    AS $$
  -- marca-0102
  -- marca-0103
  --
  -- AS DUAS MARCAS FICAM. `fn_diagnostico_modelagem` (0102) confere se a correção
  -- daquela migration está INSTALADA NO BANCO procurando `marca-0102` no corpo da
  -- função — é o teste que separa "mergeado" de "aplicado", e foi ele que pegou
  -- esta reemissão. Trocar a marca por uma nova apagaria a resposta da pergunta
  -- que ela faz; a 0103 reemite o corpo e MANTÉM o filtro de versão vigente, então
  -- a marca da 0102 continua verdadeira.
  with bruto as (
    select
      ce.secao_canonica,
      ce.chave,
      fn_normalizar_texto(ce.chave) as rotulo_norm,
      coalesce(ce.entidade_coluna, e.razao_social) as entidade,
      ce.valor_num,
      ce.unidade,
      ce.moeda,
      d.tipo_taxonomia
    from campo_extraido ce
    join documento_versao dv on dv.id = ce.documento_versao_id
    join documento d on d.id = dv.documento_id
    left join entidade e on e.id = d.entidade_id
    where d.caso_id = p_caso_id
      and ce.valor_num is not null
      -- 0102: só a versão VIGENTE de cada documento. Sem isto, cada reextração
      -- soma um jogo inteiro de ocorrências ao caso — inflando n_ocorrencias,
      -- deixando valor_ultimo vir de versão superada, e devolvendo o caso ao
      -- statement_timeout que a 0101 tinha acabado de destravar.
      and dv.id = fn_versao_com_extracao(d.id)
  ),
  -- O PAPEL É PROPRIEDADE DO RÓTULO, NÃO DA OCORRÊNCIA (0101).
  --
  -- `fn_papel_linha` depende só de (chave, tipo do documento, unidade) e custa
  -- ~1,6 ms por chamada. Avaliá-la por ocorrência era pagar 760 vezes por uma
  -- resposta que tem ~250 valores distintos. Aqui ela roda uma vez por combinação
  -- distinta e o resultado volta por join — é a mesma resposta, porque a função é
  -- `immutable`.
  papel_do_rotulo as (
    select distinct chave, tipo_taxonomia, unidade,
           fn_papel_linha(chave, tipo_taxonomia, unidade) as papel
    from (select distinct chave, tipo_taxonomia, unidade from bruto) d
  ),
  ocorrencia as (
    select b.*, p.papel
    from bruto b
    join papel_do_rotulo p
      on p.chave = b.chave
     and p.tipo_taxonomia is not distinct from b.tipo_taxonomia
     and p.unidade is not distinct from b.unidade
  ),
  base as (
    select
      o.secao_canonica,
      (array_agg(o.chave order by length(o.chave)))[1] as chave,
      o.rotulo_norm,
      max(o.entidade) as entidade,
      -- valor da ocorrência de MAIOR MÓDULO, COM O SINAL (0042).
      (array_agg(o.valor_num order by abs(o.valor_num) desc nulls last))[1] as valor_ultimo,
      count(*) as n_ocorrencias,
      max(o.unidade) as unidade,
      max(o.moeda) as moeda,
      array_agg(distinct o.tipo_taxonomia) as documentos,
      -- papel da ocorrência de MAIOR PRIORIDADE (fn_papel_prioridade): no empate
      -- entre documentos, o lado seguro é não projetar.
      (array_agg(o.papel order by fn_papel_prioridade(o.papel)))[1] as papel
    from ocorrencia o
    group by o.secao_canonica, o.rotulo_norm
  ),
  -- SOBREPOSIÇÃO SUSPEITA, por join (0101). Mesma regra da 0042: outra linha da
  -- MESMA seção, MESMO valor, e um rótulo descrevendo o outro de forma mais
  -- grossa (`Provisões` × `Provisão para passivo a descoberto de controlada`).
  -- A função não escolhe por ninguém: MARCA, e quem decide é o analista.
  -- 0103: os radicais viram coluna calculada UMA vez por linha lógica, e a
  -- contenção vira o operador `<@`. Antes `fn_rotulo_contido` era avaliada por
  -- PAR de linhas e re-tokenizava OS DOIS rótulos a cada par — com muitas
  -- colisões de valor, milhares de tokenizações dos mesmos poucos rótulos.
  base_r as (
    select b.*,
           fn_radicais_rotulo(b.chave) as radicais,
           fn_tem_palavra_longa(b.chave) as tem_longa
    from base b
  ),
  pares as (
    select b.secao_canonica, b.rotulo_norm as r1, o.rotulo_norm as r2
    from base_r b
    join base_r o
      on coalesce(o.secao_canonica, '') = coalesce(b.secao_canonica, '')
     and o.valor_ultimo = b.valor_ultimo
     -- cada par NÃO ORDENADO uma vez só (antes: duas, uma em cada direção)
     and b.rotulo_norm < o.rotulo_norm
    where b.papel = 'conta' and o.papel = 'conta'
      and ((b.tem_longa and b.radicais <@ o.radicais)
        or (o.tem_longa and o.radicais <@ b.radicais))
  ),
  sobrepostas as (
    select secao_canonica, r1 as rotulo_norm from pares
    union
    select secao_canonica, r2 from pares
  )
  select b.secao_canonica, b.chave, b.rotulo_norm, b.entidade, b.valor_ultimo,
         b.n_ocorrencias, b.papel, b.unidade, b.moeda, b.documentos,
         (s.rotulo_norm is not null) as sobreposicao_suspeita
  from base_r b
  left join sobrepostas s
    on s.rotulo_norm = b.rotulo_norm
   and coalesce(s.secao_canonica, '') = coalesce(b.secao_canonica, '')
  order by b.secao_canonica nulls last, b.rotulo_norm;
$$;

--
-- Name: FUNCTION fn_linhas_para_modelagem(p_caso_id uuid); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.fn_linhas_para_modelagem(p_caso_id uuid) IS 'Linhas lógicas do caso para a tela de Modelagem, com PAPEL (conta/subtotal/derivado/serie_mensal), valor COM SINAL, unidade/moeda, documentos de origem e marca de sobreposição. Existe como função porque campo_extraido não tem caso_id — o escopo por caso mora aqui. 0101: papel calculado uma vez por rótulo e sobreposição por join, para caber no statement_timeout. 0102: só a versão VIGENTE de cada documento (reextração deixava a versão superada somando ocorrência e podendo ditar o valor_ultimo).';

--
-- Name: fn_marcar_falha_vista(uuid, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_marcar_falha_vista(p_falha_id uuid, p_autor text) RETURNS jsonb
    LANGUAGE plpgsql
    AS $$
begin
  update execucao_falha set visto_em = now(), visto_por = p_autor
   where id = p_falha_id and visto_em is null;
  return jsonb_build_object('ok', found);
end;
$$;

--
-- Name: fn_mes_do_rotulo(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_mes_do_rotulo(p_chave text) RETURNS integer
    LANGUAGE sql IMMUTABLE
    AS $$
  with palavras as (
    select unnest(regexp_split_to_array(
      regexp_replace(fn_normalizar_texto(p_chave), '[^a-z0-9]+', ' ', 'g'), '\s+')) as w
  )
  select min(m.mes) from palavras p
  join (values
    ('jan',1),('janeiro',1),   ('fev',2),('fevereiro',2),
    ('mar',3),('marco',3),     ('abr',4),('abril',4),
    ('mai',5),('maio',5),      ('jun',6),('junho',6),
    ('jul',7),('julho',7),     ('ago',8),('agosto',8),
    ('set',9),('setembro',9),  ('out',10),('outubro',10),
    ('nov',11),('novembro',11),('dez',12),('dezembro',12)
  ) as m(nome, mes) on m.nome = p.w;
$$;

--
-- Name: FUNCTION fn_mes_do_rotulo(p_chave text); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.fn_mes_do_rotulo(p_chave text) IS 'Mês que o rótulo nomeia (1-12) ou null. Palavra inteira contra lista fechada, em qualquer posição: left(chave,3) reprovava "Faturamento Janeiro" (rótulo real da extração do v35) e um LIKE aprovaria "Marcas e patentes".';

--
-- Name: fn_mesma_entidade(text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_mesma_entidade(p_a text, p_b text) RETURNS boolean
    LANGUAGE plpgsql IMMUTABLE
    AS $$
declare
  a text := fn_entidade_canonica(p_a);
  b text := fn_entidade_canonica(p_b);
  curto text[]; longo text[];
  i int; j int; achou boolean;
begin
  if a is null or b is null then return false; end if;
  if a = b then return true; end if;

  if length(a) <= length(b) then
    curto := string_to_array(a, ' '); longo := string_to_array(b, ' ');
  else
    curto := string_to_array(b, ' '); longo := string_to_array(a, ' ');
  end if;

  -- Token significativo no lado curto (4+ chars). "vt logistica" passa por
  -- 'logistica'; um apelido "ab" não passa, e é isso que se quer.
  if not exists (select 1 from unnest(curto) t where length(t) >= 4) then
    return false;
  end if;

  j := 1;
  for i in 1 .. array_length(curto, 1) loop
    achou := false;
    while j <= array_length(longo, 1) loop
      if longo[j] like curto[i] || '%' then
        achou := true; j := j + 1; exit;
      end if;
      j := j + 1;
    end loop;
    if not achou then return false; end if;
  end loop;
  return true;
end;
$$;

--
-- Name: FUNCTION fn_mesma_entidade(p_a text, p_b text); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.fn_mesma_entidade(p_a text, p_b text) IS 'Dois nomes são a mesma entidade? Igualdade canônica ou tokens do nome curto como prefixo dos do longo, em ordem (mesmo critério de consolidarNomesDeEntidade no portal).';

--
-- Name: fn_min_motivo_rejeicao(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_min_motivo_rejeicao() RETURNS integer
    LANGUAGE sql IMMUTABLE
    AS $$ select 15; $$;

--
-- Name: FUNCTION fn_min_motivo_rejeicao(); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.fn_min_motivo_rejeicao() IS 'Mínimo de caracteres do motivo de uma rejeição de pendência. Não é estética: rejeitar libera o Portão 2 sem teto, e motivo de duas letras é o que se escreve para tirar o vermelho da tela.';

--
-- Name: fn_motivo_escala_incomparavel(text, text, text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_motivo_escala_incomparavel(p_unidade_a text, p_unidade_b text, p_rotulo_a text, p_rotulo_b text) RETURNS text
    LANGUAGE sql IMMUTABLE
    AS $$
  select case
    -- Escala ausente de um dos lados: mesmo critério conservador da 0009 — não
    -- há o que converter, mas também não há o que afirmar. Não bloqueia.
    when p_unidade_a is null or p_unidade_b is null then null
    when fn_normalizar_texto(p_unidade_a) = fn_normalizar_texto(p_unidade_b) then null
    when fn_fator_escala(p_unidade_a) is not null and fn_fator_escala(p_unidade_b) is not null then null
    else format(
      'Escalas não conversíveis entre os documentos: %s está em "%s" e %s está em "%s", e ao menos '
      || 'uma dessas escalas não é reconhecida (esperado: unidade, milhar ou milhao). Comparar assim '
      || 'arriscaria um falso "confere" — confirme o cabeçalho de escala de cada documento.',
      p_rotulo_a, p_unidade_a, p_rotulo_b, p_unidade_b)
  end;
$$;

--
-- Name: fn_mudar_dial(text, public.nivel_autonomia, text, text, numeric); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_mudar_dial(p_estagio text, p_nivel public.nivel_autonomia, p_autor text, p_motivo text DEFAULT NULL::text, p_limiar numeric DEFAULT NULL::numeric) RETURNS jsonb
    LANGUAGE plpgsql
    AS $$
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

--
-- Name: fn_normalizar_texto(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_normalizar_texto(p_texto text) RETURNS text
    LANGUAGE sql IMMUTABLE
    AS $$
  select trim(regexp_replace(lower(unaccent(coalesce(p_texto, ''))), '\s+', ' ', 'g'));
$$;

--
-- Name: fn_papel_do_rotulo_no_caso(uuid, text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_papel_do_rotulo_no_caso(p_caso_id uuid, p_rotulo_norm text, p_secao_canonica text) RETURNS text
    LANGUAGE sql STABLE
    AS $$
  -- marca-0102
  with ocorrencias as (
    select ce.secao_canonica,
           fn_papel_linha(ce.chave, d.tipo_taxonomia, ce.unidade) as papel
    from campo_extraido ce
    join documento_versao dv on dv.id = ce.documento_versao_id
    join documento d on d.id = dv.documento_id
    where d.caso_id = p_caso_id
      and ce.valor_num is not null
      and fn_normalizar_texto(ce.chave) = p_rotulo_norm
      and dv.id = fn_versao_com_extracao(d.id)
  ),
  da_secao as (
    select papel from ocorrencias
    where coalesce(secao_canonica, '') = coalesce(p_secao_canonica, '')
  )
  select coalesce(
    -- 1) o papel dentro da seção pedida — o mesmo que fn_linhas_para_modelagem
    --    mostra, porque o agrupamento é o mesmo.
    (select (array_agg(papel order by fn_papel_prioridade(papel)))[1] from da_secao),
    -- 2) e só se o rótulo não existir naquela seção, o do caso inteiro.
    (select (array_agg(papel order by fn_papel_prioridade(papel)))[1] from ocorrencias)
  );
$$;

--
-- Name: FUNCTION fn_papel_do_rotulo_no_caso(p_caso_id uuid, p_rotulo_norm text, p_secao_canonica text); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.fn_papel_do_rotulo_no_caso(p_caso_id uuid, p_rotulo_norm text, p_secao_canonica text) IS 'Papel do rótulo DENTRO DA SEÇÃO (0100), com queda para o caso inteiro só quando o rótulo não existe na seção. Tem de concordar com fn_linhas_para_modelagem — discordância entre as duas é o defeito que derrubava o "aplicar em lote". 0102: mesmo filtro de versão vigente que a tela.';

--
-- Name: fn_papel_linha(text, text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_papel_linha(p_chave text, p_tipo_taxonomia text DEFAULT NULL::text, p_unidade text DEFAULT NULL::text) RETURNS text
    LANGUAGE sql IMMUTABLE
    AS $$
  with n as (
    select fn_normalizar_texto(p_chave) as t,
           fn_tokens_estruturais(p_chave) as toks
  )
  select case
    -- ---- DERIVADO: indicador gerencial, não dinheiro ------------------------
    when (select t from n) ~ '^(indice|indices) '
      or (select t from n) ~ '^media (mensal|diaria|anual)'
      or (select t from n) ~ '^ticket medio'
      or (select t from n) ~ '^prazo medio'
      or (select t from n) ~ '^(margem|rentabilidade|retorno) '
      or (select t from n) ~ '^capital circulante liquido'
      or (select t from n) ~ '^(giro|rotacao) (de|do|da) '
      or (select t from n) ~ 'indicador gerencial'
      then 'derivado'

    -- ---- SÉRIE MENSAL: insumo da curva de sazonalidade ----------------------
    when p_tipo_taxonomia = 'FATURAMENTO_24M' and fn_mes_do_rotulo(p_chave) is not null
      then 'serie_mensal'

    -- ---- SUBTOTAL: já é a soma de outras linhas -----------------------------
    -- (a) prefixo "total"/"subtotal"/"soma"
    when (select t from n) ~ '^(total|totais|subtotal|soma) ' or (select t from n) in ('total','totais','subtotal')
      then 'subtotal'
    -- (b) o total do grupo SEM a palavra "total" (0034), agora contra os tokens
    --     já calculados. Arrays em ordem alfabética — é igualdade de array.
    when (select toks from n) in (
        array['ativo'],
        array['passivo'],
        array['patrimonio'],
        array['passivo','patrimonio'],
        array['ativo','circulante'],
        array['ativo','circulante','nao'],
        array['circulante','passivo'],
        array['circulante','nao','passivo'],
        array['longo','prazo','realizavel'])
      then 'subtotal'
    -- (c) as linhas de RESULTADO da DRE e os subtotais do Fluxo, lista fechada
    when (select t from n) in (
        'receita operacional liquida','receita liquida','receita liquida de vendas',
        'lucro bruto','prejuizo bruto',
        'resultado operacional antes do resultado financeiro',
        'resultado antes dos tributos sobre o lucro','resultado antes dos tributos',
        'lucro liquido do exercicio','prejuizo liquido do exercicio',
        'lucro liquido','prejuizo liquido','resultado do exercicio',
        'resultado financeiro liquido','resultado financeiro')
      then 'subtotal'
    when (select t from n) ~ '^caixa liquido (gerado|aplicado|gerado pelas)'
      or (select t from n) ~ '^(aumento|reducao|variacao) liquida? (de|do|da) caixa'
      then 'subtotal'

    else 'conta'
  end;
$$;

--
-- Name: FUNCTION fn_papel_linha(p_chave text, p_tipo_taxonomia text, p_unidade text); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.fn_papel_linha(p_chave text, p_tipo_taxonomia text, p_unidade text) IS 'Papel da linha na modelagem: conta | subtotal | derivado | serie_mensal. Lista FECHADA de padrões (não heurística de semelhança) porque errar para subtotal esconde conta de verdade e errar para conta deixa passar dupla contagem. 0102: tokeniza o rótulo uma vez e compara os nove grupos contra o resultado, em vez de nove chamadas a fn_rotulo_estrutural.';

--
-- Name: fn_papel_prioridade(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_papel_prioridade(p_papel text) RETURNS integer
    LANGUAGE sql IMMUTABLE
    AS $$
  select case p_papel
    when 'subtotal' then 0
    when 'serie_mensal' then 1
    when 'derivado' then 2
    else 3
  end;
$$;

--
-- Name: fn_pares_duplicados_do_caso(uuid, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_pares_duplicados_do_caso(p_caso_id uuid, p_entidade text DEFAULT NULL::text) RETURNS TABLE(secao_canonica text, rotulo_a text, rotulo_b text, colunas integer, valor numeric, radical_comum boolean)
    LANGUAGE sql STABLE
    AS $$
  with ocorrencias as (
    select
      ce.secao_canonica,
      fn_normalizar_texto(ce.chave)                as rotulo,
      coalesce(ce.entidade_coluna, e.razao_social) as ent_col,
      coalesce(ce.periodo_coluna, p.referencia)    as per_col,
      ce.valor_num,
      ce.chave,
      ce.secao,
      ce.unidade,
      d.tipo_taxonomia
    from campo_extraido ce
    join documento_versao dv on dv.id = ce.documento_versao_id
    join documento d         on d.id = dv.documento_id
    left join entidade e     on e.id = d.entidade_id
    left join periodo p      on p.id = d.periodo_id
    where d.caso_id = p_caso_id
      and ce.valor_num is not null
      and ce.valor_num <> 0
      and ce.secao_canonica is not null
      and ce.secao_canonica <> 'NAO_CLASSIFICAVEL'
      -- Só a versão VIGENTE de cada documento (0102): ocorrência de versão
      -- superada faria uma reextração parecer duplicidade.
      and dv.n_versao = (select max(dv2.n_versao) from documento_versao dv2
                          where dv2.documento_id = d.id)
      and (p_entidade is null
           or fn_mesma_entidade(coalesce(ce.entidade_coluna, e.razao_social), p_entidade))
  ),
  contas as (
    -- Subtotal e derivado ficam fora: o export já trata subtotal informado por
    -- estrutura, e cobrar de novo aqui duplicaria a fila de revisão.
    select * from ocorrencias o
    where fn_papel_linha(o.chave, o.tipo_taxonomia, o.unidade) = 'conta'
  ),
  -- Uma linha por (seção, rótulo, coluna): se o mesmo rótulo aparece em dois
  -- documentos com o mesmo valor, isso é concordância, não duplicidade.
  por_coluna as (
    select secao_canonica, rotulo, ent_col, per_col, min(chave) as chave,
           -- A SUBSEÇÃO DECLARADA pelo documento, agregada: é ela que denuncia o
           -- par subtotal × componente (ver o filtro `subtotal_de` abaixo).
           array_agg(distinct fn_normalizar_texto(coalesce(secao, ''))) as secoes,
           max(valor_num) as valor_num
    from contas
    group by secao_canonica, rotulo, ent_col, per_col
    having count(distinct valor_num) = 1
  ),
  pares as (
    select
      a.secao_canonica,
      a.rotulo as rotulo_a, b.rotulo as rotulo_b,
      min(a.chave) as chave_a, min(b.chave) as chave_b,
      count(*)     as colunas_iguais,
      max(abs(a.valor_num)) as valor,
      -- É o par SUBTOTAL × COMPONENTE? O documento diz: a subseção declarada de um
      -- é o rótulo do outro. Medido no book (extração fiel): "Obrigações
      -- Tributárias" × "Parcelamentos tributários - longo prazo", "Empréstimos e
      -- Financiamentos" × "Financiamentos - FINAME/BNDES", "Partes Relacionadas" ×
      -- "Mútuos a pagar", "Investimentos" × "Participações em outras sociedades".
      -- São grupo com UM componente, não conta duplicada — e o export já os exclui
      -- da soma pela detecção estrutural. Cobrar de novo aqui encheria a fila de
      -- revisão com o que já está resolvido, que é exatamente o que a 0023 desfez.
      bool_or(a.rotulo = any(b.secoes) or b.rotulo = any(a.secoes)) as subtotal_de,
      -- MESMA SUBSEÇÃO DECLARADA? Dois rótulos para o MESMO fato estão, por
      -- construção, no mesmo lugar da demonstração. Quando o documento os coloca em
      -- subseções diferentes, ele está dizendo que são coisas diferentes — e é o
      -- que restou de falso positivo no book depois do filtro de subtotal:
      -- "Créditos tributários - ICMS sobre ativo permanente" (Realizável a Longo
      -- Prazo) e "Veículos e empilhadeiras" (Imobilizado), ambos 3.900 nos dois
      -- exercícios. Coincidência de valor, contas distintas.
      bool_or(a.secoes && b.secoes) as mesma_subsecao,
      -- O SINAL DE SUBSEÇÃO EXISTE NESTE DOCUMENTO? Sem ele o filtro `subtotal_de`
      -- não tem como disparar, e aí "Arrendamentos" × "Arrendamentos a pagar - CPC
      -- 06 (R2)" (grupo com um componente) fica indistinguível de rótulo reescrito —
      -- os dois têm radical contido. Medido no `fixture_modelagem_v35.sql`, que não
      -- traz `secao`: era o único par que ele devolvia, e era falso positivo.
      -- Então o ramo de UMA coluna (que se sustenta no radical) exige a subseção
      -- declarada; o de DUAS colunas não precisa dela, porque ali a evidência é
      -- aritmética e independente do nome.
      bool_or(coalesce(array_to_string(a.secoes, '') || array_to_string(b.secoes, ''), '') <> '') as tem_secao
    from por_coluna a
    join por_coluna b
      on b.secao_canonica = a.secao_canonica
     and b.ent_col = a.ent_col and b.per_col = a.per_col
     and b.rotulo > a.rotulo                       -- par sem repetir a ordem
     and b.valor_num = a.valor_num                 -- idêntico ao centavo
    group by a.secao_canonica, a.rotulo, b.rotulo
  ),
  -- Uma coluna em que os dois aparecem e DISCORDAM derruba o par: contas que
  -- coincidem num ano e divergem no outro são contas diferentes, ponto.
  discordantes as (
    select a.secao_canonica, a.rotulo as rotulo_a, b.rotulo as rotulo_b
    from por_coluna a
    join por_coluna b
      on b.secao_canonica = a.secao_canonica
     and b.ent_col = a.ent_col and b.per_col = a.per_col
     and b.rotulo > a.rotulo
     and b.valor_num <> a.valor_num
  )
  select
    pr.secao_canonica,
    pr.chave_a,
    pr.chave_b,
    pr.colunas_iguais::int,
    pr.valor,
    (fn_tokens_estruturais(pr.chave_a) <@ fn_tokens_estruturais(pr.chave_b)
     or fn_tokens_estruturais(pr.chave_b) <@ fn_tokens_estruturais(pr.chave_a)) as radical_comum
  from pares pr
  where not pr.subtotal_de
    and pr.mesma_subsecao
    and not exists (
    select 1 from discordantes dc
    where dc.secao_canonica = pr.secao_canonica
      and dc.rotulo_a = pr.rotulo_a and dc.rotulo_b = pr.rotulo_b
  )
    and (pr.colunas_iguais >= 2
         or (pr.tem_secao
             and (fn_tokens_estruturais(pr.chave_a) <@ fn_tokens_estruturais(pr.chave_b)
                  or fn_tokens_estruturais(pr.chave_b) <@ fn_tokens_estruturais(pr.chave_a))))
  order by pr.valor desc, pr.secao_canonica, pr.chave_a, pr.chave_b;
$$;

--
-- Name: FUNCTION fn_pares_duplicados_do_caso(p_caso_id uuid, p_entidade text); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.fn_pares_duplicados_do_caso(p_caso_id uuid, p_entidade text) IS 'Pares de rótulos DIFERENTES, na mesma seção canônica, com valor idêntico nas mesmas colunas — candidatos a ser a MESMA conta transposta duas vezes (achado do v35: "Prejuízos acumulados" e "Resultados Acumulados", ambos -39.150). Não decide nada: alimenta a checagem de reconciliação, que abre pendência para decisão humana. Critério estreito de propósito — falso positivo aqui gasta o tempo do analista.';

--
-- Name: fn_periodo_canonico(text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_periodo_canonico(p_tipo text, p_ref text) RETURNS text
    LANGUAGE plpgsql IMMUTABLE
    AS $_$
declare
  r text := lower(trim(coalesce(p_ref, '')));
  m text[]; ano text; n int; toks text[]; t text; acc text[] := '{}';
begin
  if r = '' then return null; end if;
  r := replace(r, ' ', '');

  if r ~ '^\d{4}-\d{2}-\d{2}$' then return r; end if;                    -- ISO YYYY-MM-DD
  m := regexp_match(r, '^(\d{2})/(\d{2})/(\d{4})$');
  if m is not null then return m[3] || '-' || m[2] || '-' || m[1]; end if; -- DD/MM/YYYY
  m := regexp_match(r, '^(\d{2})/(\d{2})/(\d{2})$');
  if m is not null then return fn_ano4(m[3]) || '-' || m[2] || '-' || m[1]; end if; -- DD/MM/YY
  m := regexp_match(r, '^(\d{1,2})m(\d{2,4})$');
  if m is not null then
    ano := fn_ano4(m[2]); n := (m[1])::int;
    return case when n = 12 then ano else n || 'm' || ano end;          -- NM (12M25 → ano)
  end if;
  m := regexp_match(r, '^(\d)t(\d{2,4})$');
  if m is not null then return m[1] || 't' || fn_ano4(m[2]); end if;     -- trimestre (1T25)
  m := regexp_match(r, '^l(\d+)m$');
  if m is not null then return 'l' || m[1] || 'm'; end if;              -- últimos N meses (L24M)

  if position(',' in r) > 0 then                                        -- múltiplos exercícios
    toks := regexp_split_to_array(r, ',');
    foreach t in array toks loop
      t := trim(t);
      if t ~ '^\d{1,2}$' then t := fn_ano4(t); end if;
      if t <> '' then acc := array_append(acc, t); end if;
    end loop;
    acc := (select array_agg(x order by x) from unnest(acc) x);
    return array_to_string(acc, ',');
  end if;

  if r ~ '^\d{4}$' then return r; end if;                               -- ano 4 dígitos
  if r ~ '^\d{2}$' then return fn_ano4(r); end if;                      -- ano 2 dígitos
  return r;                                                             -- texto livre normalizado
end;
$_$;

--
-- Name: fn_periodos_compativeis(uuid, uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_periodos_compativeis(p_periodo_a uuid, p_periodo_b uuid) RETURNS boolean
    LANGUAGE plpgsql STABLE
    AS $$
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

--
-- Name: fn_periodos_equivalentes(text, text, text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_periodos_equivalentes(p_tipo_a text, p_ref_a text, p_tipo_b text, p_ref_b text) RETURNS boolean
    LANGUAGE sql IMMUTABLE
    AS $$
  select case
    when fn_periodo_canonico(p_tipo_a, p_ref_a) is null
      or fn_periodo_canonico(p_tipo_b, p_ref_b) is null then true
    when fn_periodo_canonico(p_tipo_a, p_ref_a) = fn_periodo_canonico(p_tipo_b, p_ref_b) then true
    when cardinality(fn_anos_periodo(p_tipo_a, p_ref_a)) = 0
      or cardinality(fn_anos_periodo(p_tipo_b, p_ref_b)) = 0 then true
    else fn_anos_periodo(p_tipo_a, p_ref_a) = fn_anos_periodo(p_tipo_b, p_ref_b)
  end;
$$;

--
-- Name: fn_premissa_valores_sugeridos(text, integer, integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_premissa_valores_sugeridos(p_codigo text, p_ano_inicial integer, p_anos integer DEFAULT 5) RETURNS jsonb
    LANGUAGE sql STABLE
    AS $$
  select coalesce(jsonb_object_agg(x.ano::text, x.mediana), '{}'::jsonb)
  from (
    -- Uma mediana por ano: a coleta MAIS RECENTE. `indice_macro_expectativa` é
    -- append-only por (serie, ano_ref, coletado_em) — o seed tem IPCA/2026 em
    -- duas coletas, e sem o distinct on a mais velha poderia ganhar.
    select distinct on (e.ano_ref) e.ano_ref as ano, e.mediana
    from indice_macro_expectativa e
    where e.serie = p_codigo
      and e.ano_ref between p_ano_inicial and p_ano_inicial + p_anos - 1
    order by e.ano_ref, e.coletado_em desc
  ) x;
$$;

--
-- Name: FUNCTION fn_premissa_valores_sugeridos(p_codigo text, p_ano_inicial integer, p_anos integer); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.fn_premissa_valores_sugeridos(p_codigo text, p_ano_inicial integer, p_anos integer) IS 'Valores por ano que o Focus afirma para uma premissa macro (mediana da coleta mais recente de cada ano). Ano sem expectativa publicada fica FORA — ausência é ausência.';

SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: premissa_catalogo; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.premissa_catalogo (
    codigo text NOT NULL,
    nome text NOT NULL,
    natureza public.premissa_natureza NOT NULL,
    formula public.premissa_formula NOT NULL,
    unidade text,
    aplica_em text[] DEFAULT '{}'::text[] NOT NULL,
    setores text[] DEFAULT '{}'::text[] NOT NULL,
    fonte text,
    descricao text,
    ativo boolean DEFAULT true NOT NULL
);

--
-- Name: TABLE premissa_catalogo; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.premissa_catalogo IS 'Vocabulário de premissas de projeção. Premissa nova = LINHA nova aqui, sem código novo; fórmula-tipo nova = primitiva nova no gerador. `setores` vazio = base comum a todo setor.';

--
-- Name: fn_premissas_sugeridas(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_premissas_sugeridas(p_setor text DEFAULT NULL::text) RETURNS SETOF public.premissa_catalogo
    LANGUAGE sql STABLE
    AS $$
  select *
  from premissa_catalogo
  where ativo
    and (cardinality(setores) = 0 or (p_setor is not null and p_setor = any(setores)))
  order by natureza, codigo;
$$;

--
-- Name: fn_radicais_rotulo(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_radicais_rotulo(p_chave text) RETURNS text[]
    LANGUAGE sql IMMUTABLE
    AS $$
  select coalesce((
    select array_agg(distinct left(w, 5) order by left(w, 5))
    from unnest(regexp_split_to_array(
      regexp_replace(fn_normalizar_texto(p_chave), '[^a-z0-9]+', ' ', 'g'), '\s+')) as w
    where w <> ''
  ), array[]::text[]);
$$;

--
-- Name: FUNCTION fn_radicais_rotulo(p_chave text); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.fn_radicais_rotulo(p_chave text) IS 'Radicais de 5 letras das palavras de um rótulo, ordenados e sem repetição. Extraído de fn_rotulo_contido na 0102 para ser calculado uma vez por linha lógica em vez de duas vezes por PAR de linhas comparadas.';

--
-- Name: fn_reavaliar_guardas_extracao(uuid, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_reavaliar_guardas_extracao(p_documento_versao_id uuid, p_autor text) RETURNS jsonb
    LANGUAGE plpgsql
    AS $$
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

--
-- Name: fn_recomputar_completude(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_recomputar_completude(p_caso_id uuid) RETURNS jsonb
    LANGUAGE plpgsql
    AS $$
declare
  v_faltantes text[];
  v_sem_conteudo text[];
  v_cod text;
  v_nao_sobre boolean;
  v_status_atual caso_status;
  v_novo_status caso_status;
  v_pend_id uuid;
  -- 0113: passo (2b)
  v_ex record;
  v_motivos_ausentes text[] := '{}';
  v_linhas_ausentes jsonb := '[]'::jsonb;
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

  -- ----- (2) obrigatório PRESENTE mas sem uma linha aproveitável (0036) ------
  select array_agg(t.codigo order by t.codigo) into v_sem_conteudo
  from taxonomia_tipo_documento t
  where t.obrigatoriedade = 'obrigatorio'
    and exists (
      select 1 from documento d
      where d.caso_id = p_caso_id and d.tipo_taxonomia = t.codigo
    )
    and fn_linhas_do_tipo(p_caso_id, t.codigo) = 0;
  v_sem_conteudo := coalesce(v_sem_conteudo, array[]::text[]);

  update pendencia p set estado = 'resolvida', resolvida_em = now(), resolvida_por = 'sistema:extracao'
  where p.caso_id = p_caso_id and p.tipo = 'item_sem_conteudo' and p.estado <> 'resolvida'
    and not (p.motivo = any (select 'completude:sem_conteudo:'||x from unnest(v_sem_conteudo) x));

  foreach v_cod in array v_sem_conteudo loop
    if not exists (
      select 1 from pendencia p
      where p.caso_id = p_caso_id and p.tipo = 'item_sem_conteudo'
        and p.estado <> 'resolvida' and p.motivo = 'completude:sem_conteudo:'||v_cod
    ) then
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

  -- ----- (2b) 0113: tipo presente COM conteúdo, mas sem uma LINHA exigida ----
  -- É o buraco entre a 0036 e as reconciliações: o documento chegou e rendeu
  -- linhas, só que NÃO as linhas de que o resto do sistema depende. Até aqui,
  -- isso só aparecia como `precondicao_nao_satisfeita` — mole, sobrepujável e
  -- publicada por período — e SÓ para as linhas que alguma das cinco checagens
  -- cruza. Agora a ausência é declarada na completude, NOMEANDO a linha (0033)
  -- e o que deixa de funcionar sem ela (depende_de).
  --
  -- Política por linha é do dono: severidade/sobrepujavel NULL caem em
  -- 'importante'/true — o peso que a ausência já tem hoje. Pendência existente
  -- é ATUALIZADA (descrição e política), como a 0009 faz, para uma decisão
  -- nova do dono valer sem esperar a pendência reabrir.
  for v_ex in
    select * from fn_exigencias_do_caso(p_caso_id) x where not x.satisfeita
  loop
    v_motivos_ausentes := v_motivos_ausentes
      || ('completude:linha_exigida:' || v_ex.tipo_taxonomia || ':' || v_ex.conceito);
    v_linhas_ausentes := v_linhas_ausentes || jsonb_build_object(
      'tipo', v_ex.tipo_taxonomia, 'conceito', v_ex.conceito,
      'rotulo', v_ex.rotulo, 'origem', v_ex.origem);

    select id into v_pend_id from pendencia p
    where p.caso_id = p_caso_id and p.tipo = 'linha_exigida_ausente'
      and p.estado <> 'resolvida'
      and p.motivo = 'completude:linha_exigida:' || v_ex.tipo_taxonomia || ':' || v_ex.conceito
    limit 1;

    if v_pend_id is null then
      insert into pendencia (caso_id, origem_estagio, tipo, severidade, sobrepujavel, descricao, motivo)
        values (p_caso_id, 'completude', 'linha_exigida_ausente',
                coalesce(v_ex.severidade, 'importante')::pendencia_severidade,
                coalesce(v_ex.sobrepujavel, true),
                format('O tipo %s chegou e rendeu linhas, mas a linha exigida "%s" não foi localizada '
                       'na versão vigente de nenhum documento do tipo. Sem ela: %s.%s Conferir se o '
                       'documento traz a linha com outro rótulo (e corrigir na revisão) ou reenviar o '
                       'arquivo completo.',
                       v_ex.tipo_taxonomia, v_ex.rotulo,
                       array_to_string(v_ex.depende_de, '; '),
                       case when v_ex.origem = 'proposta'
                            then ' (Exigência PROPOSTA na análise — nenhuma checagem automática a lê hoje.)'
                            else '' end),
                'completude:linha_exigida:' || v_ex.tipo_taxonomia || ':' || v_ex.conceito);
    else
      update pendencia set
        severidade   = coalesce(v_ex.severidade, 'importante')::pendencia_severidade,
        sobrepujavel = coalesce(v_ex.sobrepujavel, true)
      where id = v_pend_id;
    end if;
  end loop;

  -- A linha apareceu (versão nova, revisão que corrigiu o rótulo) — resolve
  -- sozinha, como as da 0036. Vale também para exigência desativada pelo dono.
  update pendencia p set estado = 'resolvida', resolvida_em = now(), resolvida_por = 'sistema:extracao'
  where p.caso_id = p_caso_id and p.tipo = 'linha_exigida_ausente' and p.estado <> 'resolvida'
    and not (p.motivo = any (v_motivos_ausentes));

  -- ----- (3) o checklist reflete os três estados (0036) ----------------------
  update checklist_item_status c
    set status = case
                   when fn_linhas_do_tipo(p_caso_id, c.tipo_taxonomia) = 0 then 'recebido_nao_valido'
                   else 'presente'
                 end,
        atualizado_em = now()
  where c.caso_id = p_caso_id
    and c.documento_id is not null
    and c.status in ('presente', 'recebido_nao_valido');

  -- ----- (4) status do caso: Portão 1 continua sendo CHEGADA (0036) ----------
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
    'sem_conteudo', to_jsonb(v_sem_conteudo),
    -- 0113: as linhas exigidas que faltam saem no payload (nó do n8n e portal
    -- mostram sem refazer a consulta). `pronto_para_revisao` NÃO muda:
    -- endurecê-lo com linha exigida é decisão de produto do dono, não efeito
    -- colateral desta migration.
    'linhas_exigidas_ausentes', v_linhas_ausentes,
    'pronto_para_revisao',
      array_length(v_faltantes,1) is null and array_length(v_sem_conteudo,1) is null,
    'status', v_novo_status
  );
end;
$$;

--
-- Name: FUNCTION fn_recomputar_completude(p_caso_id uuid); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.fn_recomputar_completude(p_caso_id uuid) IS 'Portão 1 (chegada) + 0036 (recebido sem conteúdo) + 0113 (passo 2b: tipo com conteúdo mas sem uma LINHA exigida — pendência linha_exigida_ausente nomeando a linha e o depende_de; severidade por linha é do dono, default importante/sobrepujável). `portao1_ok` segue significando "chegou tudo"; `pronto_para_revisao` segue chegou tudo E tem conteúdo.';

--
-- Name: fn_reconciliar_ativo_passivo_pl(uuid, uuid, uuid, numeric, numeric); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_reconciliar_ativo_passivo_pl(p_caso_id uuid, p_entidade_id uuid, p_periodo_id uuid, p_tolerancia_abs numeric DEFAULT 100, p_tolerancia_pct numeric DEFAULT 0.005) RETURNS jsonb
    LANGUAGE plpgsql
    AS $$
declare
  v_doc_id     uuid;
  v_versao     uuid;
  v_col_ent    text;
  v_ano        int;
  v_col_per    text;
  v_ativo      campo_extraido;
  v_passivo_pl campo_extraido;
  v_passivo    campo_extraido;
  v_pl         campo_extraido;
  v_esq        numeric;
  v_dir        numeric;
  v_soma       record;
  v_soma_pl    record;
  v_div_abs    numeric;
  v_tol        numeric;
  v_pior_abs   numeric := null;
  v_pior_pct   numeric := null;
  v_resultado  text := 'ok';
  v_partes     text[] := '{}';
  v_n_anos     int := 0;
  v_fonte_a    jsonb;
  v_fonte_b    jsonb;
  v_desc       text;
  v_orig_esq   text;
  v_orig_dir   text;
  v_faltas     text[] := '{}';
begin
  v_doc_id := fn_documento_balanco(p_caso_id, p_entidade_id, p_periodo_id);

  if v_doc_id is null then
    return fn_registrar_reconciliacao(p_caso_id, p_entidade_id, p_periodo_id,
      'ativo_passivo_pl', 'A', null, null, null, 'documento_ausente', null, null,
      jsonb_build_object('tolerancia_abs', p_tolerancia_abs, 'tolerancia_pct', p_tolerancia_pct),
      'Nenhum Balanço Patrimonial, Combinado ou Balancete classificado para esta '
      || 'entidade/período — nada a reconciliar (a cobrança do documento é do checklist).');
  end if;

  v_versao  := fn_versao_atual(v_doc_id);
  v_col_ent := fn_coluna_entidade(v_versao, p_entidade_id);

  foreach v_ano in array fn_anos_alvo(p_periodo_id) loop
    v_col_per := case when v_ano is null then null
                      else fn_coluna_periodo_do_ano(v_versao, v_ano) end;
    v_orig_esq := null;
    v_orig_dir := null;
    v_esq := null;
    v_dir := null;

    -- ---- lado esquerdo: ATIVO ------------------------------------------------
    -- (a) a linha que diz "total" no rótulo.
    select * into v_ativo from fn_valor_conceito_col(v_versao,
      array['ativo', 'total'], array['circulante', 'nao circulante'], v_col_ent, v_col_per);
    if v_ativo.id is not null then
      v_esq := v_ativo.valor_num;
      v_orig_esq := format('linha "%s"', v_ativo.chave);
    else
      -- (b) 0034: o rótulo ESTRUTURAL — "ATIVO", que é como a maioria dos
      -- balanços brasileiros imprime o total do grupo.
      select * into v_ativo from fn_valor_estrutural_col(v_versao,
        array['ativo'], v_col_ent, v_col_per);
      if v_ativo.id is not null then
        v_esq := v_ativo.valor_num;
        v_orig_esq := format('linha "%s" (total do grupo, sem a palavra "total")', v_ativo.chave);
      else
        -- (c) soma das contas da seção.
        select * into v_soma from fn_soma_secao(v_versao, array['ativo'], v_col_ent, v_col_per,
          array['passivo', 'patrimonio'], array['total do ativo']);
        v_esq := case when coalesce(v_soma.n_linhas, 0) > 0 then v_soma.soma end;
        v_orig_esq := case when v_esq is null then null
          else format('soma da seção ATIVO (%s linhas, sem linha de total impressa)', v_soma.n_linhas) end;
      end if;
    end if;

    -- ---- lado direito: PASSIVO + PL -----------------------------------------
    select * into v_passivo_pl from fn_valor_conceito_col(v_versao,
      array['passivo', 'patrimonio', 'total'], array['circulante'], v_col_ent, v_col_per);
    if v_passivo_pl.id is not null then
      v_dir := v_passivo_pl.valor_num;
      v_orig_dir := format('linha "%s"', v_passivo_pl.chave);
    else
      -- 0034: "PASSIVO E PATRIMÔNIO LÍQUIDO" — o rótulo do v35, que a busca com
      -- "total" não via.
      select * into v_passivo_pl from fn_valor_estrutural_col(v_versao,
        array['passivo', 'patrimonio'], v_col_ent, v_col_per);
      if v_passivo_pl.id is not null then
        v_dir := v_passivo_pl.valor_num;
        v_orig_dir := format('linha "%s" (total do grupo, sem a palavra "total")', v_passivo_pl.chave);
      else
        select * into v_passivo from fn_valor_conceito_col(v_versao,
          array['passivo', 'total'], array['patrimonio', 'circulante', 'nao circulante'],
          v_col_ent, v_col_per);
        select * into v_pl from fn_valor_conceito_col(v_versao,
          array['patrimonio', 'liquido', 'total'], array['circulante'], v_col_ent, v_col_per);
        if v_passivo.id is null then
          select * into v_passivo from fn_valor_estrutural_col(v_versao,
            array['passivo'], v_col_ent, v_col_per);
        end if;
        if v_pl.id is null then
          select * into v_pl from fn_valor_estrutural_col(v_versao,
            array['patrimonio'], v_col_ent, v_col_per);
        end if;
        if v_passivo.id is not null and v_pl.id is not null then
          v_dir := v_passivo.valor_num + v_pl.valor_num;
          v_orig_dir := format('linhas "%s" + "%s"', v_passivo.chave, v_pl.chave);
        else
          -- 0034: o fallback de soma, agora ALCANÇÁVEL. Era
          -- `fn_soma_secao(array['passivo','patrimonio'])`, que exige a seção
          -- conter os DOIS termos — e não existe seção "passivo patrimônio".
          -- As seções reais são "Passivo Circulante", "Passivo Não Circulante"
          -- e "Patrimônio Líquido", então são DUAS somas que se juntam.
          select * into v_soma from fn_soma_secao(v_versao, array['passivo'],
            v_col_ent, v_col_per, array['patrimonio'],
            array['total do passivo', 'passivo e patrimonio']);
          select * into v_soma_pl from fn_soma_secao(v_versao, array['patrimonio'],
            v_col_ent, v_col_per, '{}',
            array['total do passivo', 'passivo e patrimonio']);
          if coalesce(v_soma.n_linhas, 0) + coalesce(v_soma_pl.n_linhas, 0) > 0 then
            v_dir := coalesce(v_soma.soma, 0) + coalesce(v_soma_pl.soma, 0);
            v_orig_dir := format('soma das seções PASSIVO (%s linhas) + PL (%s linhas), sem linha de total impressa',
                                 coalesce(v_soma.n_linhas, 0), coalesce(v_soma_pl.n_linhas, 0));
          end if;
        end if;
      end if;
    end if;

    if v_esq is null or v_dir is null then
      v_faltas := v_faltas || format('%s: falta %s%s',
        coalesce(v_ano::text, 'período do documento'),
        case
          when v_esq is null and v_dir is null then 'o Ativo Total E o Passivo+PL'
          when v_esq is null then 'o Ativo Total'
          else 'o Passivo+PL'
        end,
        case
          when v_col_per is null and v_col_ent is null then ''
          else format(' (coluna de entidade: %s; coluna de período: %s)',
                      coalesce(nullif(v_col_ent, E'\x01'), '(qualquer)'),
                      coalesce(nullif(v_col_per, E'\x01'), '(qualquer)'))
        end);
      continue;
    end if;

    v_n_anos := v_n_anos + 1;
    v_div_abs := abs(v_esq - v_dir);
    v_tol := greatest(p_tolerancia_abs, abs(v_esq) * p_tolerancia_pct);
    if v_div_abs > v_tol then
      v_resultado := 'divergente';
      v_partes := v_partes || format('%s: Ativo %s [%s] vs Passivo+PL %s [%s] (diferença de %s)',
        coalesce(v_ano::text, 'período do documento'), v_esq, v_orig_esq, v_dir, v_orig_dir, v_div_abs);
      if v_pior_abs is null or v_div_abs > v_pior_abs then
        v_pior_abs := v_div_abs;
        v_pior_pct := case when v_esq <> 0 then v_div_abs / abs(v_esq) end;
      end if;
    else
      v_partes := v_partes || format('%s: confere (Ativo %s [%s] = Passivo+PL %s [%s])',
        coalesce(v_ano::text, 'período do documento'), v_esq, v_orig_esq, v_dir, v_orig_dir);
    end if;
    v_fonte_a := jsonb_build_object('chave', coalesce(v_ativo.chave, 'soma da seção ATIVO'),
      'valor', v_esq, 'ano', v_ano, 'origem', v_orig_esq, 'documento_versao_id', v_versao);
    v_fonte_b := jsonb_build_object('valor', v_dir, 'ano', v_ano, 'origem', v_orig_dir,
      'documento_versao_id', v_versao);
  end loop;

  if v_n_anos = 0 then
    return fn_registrar_reconciliacao(p_caso_id, p_entidade_id, p_periodo_id,
      'ativo_passivo_pl', 'A', v_doc_id, null, null, 'precondicao_nao_satisfeita', null, null,
      jsonb_build_object('tolerancia_abs', p_tolerancia_abs, 'tolerancia_pct', p_tolerancia_pct),
      'O Balanço foi encontrado, mas nenhum exercício teve os DOIS lados. '
      || case when array_length(v_faltas, 1) is null then ''
              else array_to_string(v_faltas, '; ') || '. ' end
      || 'Rótulos que a extração TROUXE e que poderiam ser um total: '
      || fn_rotulos_candidatos(v_versao)
      || '. Se o rótulo certo está nessa lista, o defeito é o padrão de casamento; '
      || 'se não está, a extração não trouxe a linha e o caminho é reextrair.');
  end if;

  v_desc := format('Ativo Total vs Passivo+Patrimônio Líquido em %s ano(s): %s.',
                   v_n_anos, array_to_string(v_partes, '; '));
  if array_length(v_faltas, 1) is not null then
    v_desc := v_desc || format(' Exercícios NÃO checados: %s.', array_to_string(v_faltas, '; '));
  end if;

  return fn_registrar_reconciliacao(p_caso_id, p_entidade_id, p_periodo_id,
    'ativo_passivo_pl', 'A', v_doc_id, v_fonte_a, v_fonte_b, v_resultado,
    v_pior_abs, v_pior_pct,
    jsonb_build_object('tolerancia_abs', p_tolerancia_abs, 'tolerancia_pct', p_tolerancia_pct,
                       'anos_checados', v_n_anos,
                       'anos_nao_checados', coalesce(array_length(v_faltas, 1), 0)),
    v_desc);
end;
$$;

--
-- Name: fn_reconciliar_caixa_bp_fluxo(uuid, uuid, uuid, numeric, numeric); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_reconciliar_caixa_bp_fluxo(p_caso_id uuid, p_entidade_id uuid, p_periodo_id uuid, p_tolerancia_abs numeric DEFAULT 100, p_tolerancia_pct numeric DEFAULT 0.005) RETURNS jsonb
    LANGUAGE plpgsql
    AS $$
declare
  v_doc_bp    uuid;
  v_doc_fx    uuid;
  v_ver_bp    uuid;
  v_ver_fx    uuid;
  v_col_ent   text;
  v_ano       int;
  v_col_per   text;
  v_caixa     campo_extraido;
  v_saldo     campo_extraido;
  v_motivo    text;
  v_a         numeric;
  v_b         numeric;
  v_div_abs   numeric;
  v_tol       numeric;
  v_resultado text := 'ok';
  v_partes    text[] := '{}';
  v_n         int := 0;
  v_pior_abs  numeric;
  v_pior_pct  numeric;
  v_fonte_a   jsonb;
  v_fonte_b   jsonb;
begin
  v_doc_bp := fn_documento_balanco(p_caso_id, p_entidade_id, p_periodo_id);
  v_doc_fx := fn_documento_por_tipo(p_caso_id, p_entidade_id, p_periodo_id, 'FLUXO_CAIXA');

  if v_doc_bp is null or v_doc_fx is null then
    -- Fato comum e legítimo: nem toda empresa do grupo entrega DFC. Quem cobra
    -- documento faltante é o checklist do Kit Básico, não a fila de revisão.
    return fn_registrar_reconciliacao(p_caso_id, p_entidade_id, p_periodo_id,
      'caixa_bp_fluxo', 'A', coalesce(v_doc_bp, v_doc_fx), null, null,
      'documento_ausente', null, null,
      jsonb_build_object('tolerancia_abs', p_tolerancia_abs, 'tolerancia_pct', p_tolerancia_pct),
      format('Sem par para reconciliar: %s não foi entregue para esta entidade/período.',
        case when v_doc_bp is null and v_doc_fx is null then 'Balanço e Fluxo de Caixa'
             when v_doc_bp is null then 'Balanço Patrimonial' else 'Fluxo de Caixa' end));
  end if;

  v_ver_bp  := fn_versao_atual(v_doc_bp);
  v_ver_fx  := fn_versao_atual(v_doc_fx);
  v_col_ent := fn_coluna_entidade(v_ver_bp, p_entidade_id);

  foreach v_ano in array fn_anos_alvo(p_periodo_id) loop
    v_col_per := case when v_ano is null then null
                      else fn_coluna_periodo_do_ano(v_ver_bp, v_ano) end;

    -- Caixa no Balanço. "Disponível"/"Disponibilidades" é o rótulo mais comum em
    -- demonstração brasileira detalhada — a DFC do book chega a dizer, na nota,
    -- que o saldo final "confere com a rubrica Disponível do balanço".
    select * into v_caixa from fn_valor_conceito_col(v_ver_bp,
      array['caixa', 'equivalentes'], array['circulante', 'fluxo', 'inicio', 'inicial'],
      v_col_ent, v_col_per);
    if v_caixa.id is null then
      select * into v_caixa from fn_valor_conceito_col(v_ver_bp,
        array['disponibilidades'], array['circulante'], v_col_ent, v_col_per);
    end if;
    if v_caixa.id is null then
      select * into v_caixa from fn_valor_conceito_col(v_ver_bp,
        array['disponivel'], array['circulante'], v_col_ent, v_col_per);
    end if;
    if v_caixa.id is null then
      select * into v_caixa from fn_valor_conceito_col(v_ver_bp,
        array['caixa', 'bancos'], array['circulante'], v_col_ent, v_col_per);
    end if;
    -- 0031: as quatro tentativas acima olham SÓ `ce.chave`, e é isso que produzia a
    -- pendência "não foi possível localizar o Caixa/Disponível" no teste v31. Contra
    -- os rótulos reais do book:
    --
    --   Holding      "Caixa e Equivalentes de Caixa"  -> casa (1)
    --   Metalúrgica  "Disponibilidades"               -> casa (2)
    --   Componentes  "Numerário Disponível"           -> casa (3)
    --   SPE          "Caixa"                          -> NÃO casava: (1) exige
    --                                                   'equivalentes' e (4) exige 'bancos'
    --   VT Logística "Bancos Conta Movimento"         -> NÃO casava nenhuma
    --
    -- E o dado que faltava ESTAVA no documento: a `secao` da VT Logística diz
    -- "Disponível". A função nunca olhou `ce.secao`.
    if v_caixa.id is null then
      -- "Caixa" puro (SPE). Vem depois das combinações de dois termos, que são
      -- mais específicas — assim um documento que tem as duas coisas escolhe a
      -- linha certa em vez da mais genérica.
      select * into v_caixa from fn_valor_conceito_col(v_ver_bp,
        array['caixa'], array['circulante', 'fluxo', 'inicio', 'inicial', 'equivalente'],
        v_col_ent, v_col_per);
    end if;
    if v_caixa.id is null then
      -- Pela SEÇÃO do documento: é o que resolve "Bancos Conta Movimento".
      select * into v_caixa from fn_valor_conceito_secao(v_ver_bp,
        array['disponivel'], array['circulante'], v_col_ent, v_col_per);
    end if;
    if v_caixa.id is null then
      select * into v_caixa from fn_valor_conceito_secao(v_ver_bp,
        array['caixa'], array['circulante', 'fluxo'], v_col_ent, v_col_per);
    end if;

    -- Saldo final na DFC (a coluna de período da DFC é a dela, não a do BP).
    v_col_per := case when v_ano is null then null
                      else fn_coluna_periodo_do_ano(v_ver_fx, v_ano) end;
    select * into v_saldo from fn_valor_conceito_col(v_ver_fx,
      array['saldo', 'final'], array['inicial', 'inicio'], null, v_col_per);
    if v_saldo.id is null then
      select * into v_saldo from fn_valor_conceito_col(v_ver_fx,
        array['caixa', 'final'], array['inicial', 'inicio'], null, v_col_per);
    end if;
    if v_saldo.id is null then
      select * into v_saldo from fn_valor_conceito_col(v_ver_fx,
        array['caixa', 'fim'], array['inicial', 'inicio'], null, v_col_per);
    end if;

    if v_caixa.id is null or v_saldo.id is null then
      continue;
    end if;

    v_motivo := fn_motivo_escala_incomparavel(v_caixa.unidade, v_saldo.unidade,
      'o Caixa do Balanço', 'o Saldo final do Fluxo de Caixa');
    if v_motivo is not null then
      return fn_registrar_reconciliacao(p_caso_id, p_entidade_id, p_periodo_id,
        'caixa_bp_fluxo', 'A', v_doc_bp, null, null, 'precondicao_nao_satisfeita', null, null,
        jsonb_build_object('tolerancia_abs', p_tolerancia_abs, 'tolerancia_pct', p_tolerancia_pct),
        v_motivo);
    end if;

    v_a := fn_valor_em_base(v_caixa.valor_num, v_caixa.unidade);
    v_b := fn_valor_em_base(v_saldo.valor_num, v_saldo.unidade);
    v_n := v_n + 1;
    v_div_abs := abs(v_a - v_b);
    v_tol := greatest(p_tolerancia_abs * coalesce(fn_fator_escala(v_caixa.unidade), 1),
                      abs(v_a) * p_tolerancia_pct);
    if v_div_abs > v_tol then
      v_resultado := 'divergente';
      v_partes := v_partes || format('%s: Caixa no Balanço %s ("%s") vs Saldo final na DFC %s ("%s") — diferença de %s',
        coalesce(v_ano::text, 'período do documento'), v_caixa.valor_num, v_caixa.chave,
        v_saldo.valor_num, v_saldo.chave, v_div_abs);
      if v_pior_abs is null or v_div_abs > v_pior_abs then
        v_pior_abs := v_div_abs;
        v_pior_pct := case when v_a <> 0 then v_div_abs / abs(v_a) end;
      end if;
    else
      v_partes := v_partes || format('%s: confere (%s "%s" = %s "%s")',
        coalesce(v_ano::text, 'período do documento'), v_caixa.valor_num, v_caixa.chave,
        v_saldo.valor_num, v_saldo.chave);
    end if;
    v_fonte_a := jsonb_build_object('chave', v_caixa.chave, 'valor', v_caixa.valor_num,
      'unidade', v_caixa.unidade, 'documento_versao_id', v_ver_bp);
    v_fonte_b := jsonb_build_object('chave', v_saldo.chave, 'valor', v_saldo.valor_num,
      'unidade', v_saldo.unidade, 'documento_versao_id', v_ver_fx);
  end loop;

  if v_n = 0 then
    return fn_registrar_reconciliacao(p_caso_id, p_entidade_id, p_periodo_id,
      'caixa_bp_fluxo', 'A', v_doc_bp, null, null, 'precondicao_nao_satisfeita', null, null,
      jsonb_build_object('tolerancia_abs', p_tolerancia_abs, 'tolerancia_pct', p_tolerancia_pct),
      'Balanço e Fluxo de Caixa presentes, mas não foi possível localizar o Caixa/Disponível do '
      || 'Balanço e/ou o Saldo final de caixa do Fluxo (rótulos extraídos não bateram).');
  end if;

  return fn_registrar_reconciliacao(p_caso_id, p_entidade_id, p_periodo_id,
    'caixa_bp_fluxo', 'A', v_doc_bp, v_fonte_a, v_fonte_b, v_resultado, v_pior_abs, v_pior_pct,
    jsonb_build_object('tolerancia_abs', p_tolerancia_abs, 'tolerancia_pct', p_tolerancia_pct,
                       'anos_checados', v_n),
    format('Caixa do Balanço vs Saldo final do Fluxo de Caixa em %s ano(s): %s.',
           v_n, array_to_string(v_partes, '; ')));
end;
$$;

--
-- Name: fn_reconciliar_despfin_dre_vs_divida(uuid, uuid, uuid, numeric, numeric); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_reconciliar_despfin_dre_vs_divida(p_caso_id uuid, p_entidade_id uuid, p_periodo_id uuid, p_tolerancia_abs numeric DEFAULT 50000, p_tolerancia_pct numeric DEFAULT 0.05) RETURNS jsonb
    LANGUAGE plpgsql
    AS $$
declare
  v_doc_dre uuid;
  v_doc_div uuid;
  v_ver_dre uuid;
  v_ver_div uuid;
  v_col_ent text;
  v_ano int;
  v_col_per text;
  v_despfin campo_extraido;
  v_juros   record;
  v_unid_div text;
  v_motivo text;
  v_a numeric; v_b numeric; v_div numeric; v_tol numeric;
  v_resultado text := 'ok';
  v_partes text[] := '{}';
  v_n int := 0;
  v_pior_abs numeric; v_pior_pct numeric;
  v_fonte_a jsonb; v_fonte_b jsonb;
begin
  v_doc_dre := fn_documento_por_tipo(p_caso_id, p_entidade_id, p_periodo_id, 'DRE');
  v_doc_div := fn_documento_por_tipo(p_caso_id, p_entidade_id, p_periodo_id, 'MAPA_DIVIDA');

  if v_doc_dre is null or v_doc_div is null then
    return fn_registrar_reconciliacao(p_caso_id, p_entidade_id, p_periodo_id,
      'despfin_dre_vs_divida', 'B', coalesce(v_doc_dre, v_doc_div), null, null,
      'documento_ausente', null, null,
      jsonb_build_object('tolerancia_abs', p_tolerancia_abs, 'tolerancia_pct', p_tolerancia_pct),
      format('Sem par para reconciliar despesa financeira: %s não foi entregue para esta entidade/período.',
        case when v_doc_dre is null and v_doc_div is null then 'DRE e Mapa de Dívida'
             when v_doc_dre is null then 'DRE' else 'Mapa de Dívida' end));
  end if;

  v_ver_dre  := fn_versao_atual(v_doc_dre);
  v_ver_div  := fn_versao_atual(v_doc_div);
  v_col_ent  := fn_coluna_entidade(v_ver_dre, p_entidade_id);
  v_unid_div := fn_unidade_predominante(v_ver_div);

  foreach v_ano in array fn_anos_alvo(p_periodo_id) loop
    v_col_per := case when v_ano is null then null
                      else fn_coluna_periodo_do_ano(v_ver_dre, v_ano) end;

    select * into v_despfin from fn_valor_conceito_col(v_ver_dre,
      array['despesa', 'financeira'], array['receita'], v_col_ent, v_col_per);
    if v_despfin.id is null then
      select * into v_despfin from fn_valor_conceito_col(v_ver_dre,
        array['juros', 'encargos'], array['receita', 'pagos'], v_col_ent, v_col_per);
    end if;
    if v_despfin.id is null then continue; end if;

    -- Juros do exercício no mapa: soma as linhas por contrato, excluindo o total.
    select coalesce(sum(ce.valor_num), 0)::numeric as soma, count(*)::int as n
      into v_juros
    from campo_extraido ce
    where ce.documento_versao_id = v_ver_div
      and ce.valor_num is not null
      and (fn_normalizar_texto(ce.chave) like '%juros%' or fn_normalizar_texto(ce.chave) like '%encargos%')
      and fn_normalizar_texto(ce.chave) not like 'total%'
      and fn_normalizar_texto(ce.chave) not like '%total %';
    if coalesce(v_juros.n, 0) = 0 then continue; end if;

    v_motivo := fn_motivo_escala_incomparavel(v_despfin.unidade, v_unid_div,
      'a Despesa Financeira da DRE', 'o Mapa de Dívida');
    if v_motivo is not null then
      return fn_registrar_reconciliacao(p_caso_id, p_entidade_id, p_periodo_id,
        'despfin_dre_vs_divida', 'B', v_doc_dre, null, null,
        'precondicao_nao_satisfeita', null, null,
        jsonb_build_object('tolerancia_abs', p_tolerancia_abs, 'tolerancia_pct', p_tolerancia_pct),
        v_motivo);
    end if;

    -- Comparação em VALOR ABSOLUTO: a DRE traz a despesa como negativa
    -- (dedução), o mapa traz os juros como positivos.
    v_a := abs(fn_valor_em_base(v_despfin.valor_num, v_despfin.unidade));
    v_b := abs(fn_valor_em_base(v_juros.soma, v_unid_div));
    v_n := v_n + 1;
    v_div := abs(v_a - v_b);
    v_tol := greatest(p_tolerancia_abs * coalesce(fn_fator_escala(v_despfin.unidade), 1),
                      abs(v_a) * p_tolerancia_pct);
    if v_div > v_tol then
      v_resultado := 'zona_cinzenta';
      v_partes := v_partes || format('%s: Despesa Financeira %s "%s" vs soma de %s contratos %s "%s" — diferença de %s na base',
        v_ano, v_despfin.valor_num, coalesce(v_despfin.unidade, 'sem escala'),
        v_juros.n, v_juros.soma, coalesce(v_unid_div, 'sem escala'), v_div);
      if v_pior_abs is null or v_div > v_pior_abs then
        v_pior_abs := v_div;
        v_pior_pct := case when v_a <> 0 then v_div / abs(v_a) end;
      end if;
    else
      v_partes := v_partes || format('%s: confere (Despesa Financeira %s "%s" = juros de %s contratos %s "%s", convertidos à mesma base)',
        v_ano, v_despfin.valor_num, coalesce(v_despfin.unidade, 'sem escala'),
        v_juros.n, v_juros.soma, coalesce(v_unid_div, 'sem escala'));
    end if;
    v_fonte_a := jsonb_build_object('chave', v_despfin.chave, 'valor', v_despfin.valor_num,
      'unidade', v_despfin.unidade, 'ano', v_ano, 'documento_versao_id', v_ver_dre);
    v_fonte_b := jsonb_build_object('soma_juros', v_juros.soma, 'n_contratos', v_juros.n,
      'unidade', v_unid_div, 'documento_versao_id', v_ver_div);
  end loop;

  if v_n = 0 then
    return fn_registrar_reconciliacao(p_caso_id, p_entidade_id, p_periodo_id,
      'despfin_dre_vs_divida', 'B', v_doc_dre, null, null,
      'precondicao_nao_satisfeita', null, null,
      jsonb_build_object('tolerancia_abs', p_tolerancia_abs, 'tolerancia_pct', p_tolerancia_pct),
      'DRE e Mapa de Dívida presentes, mas não foi possível localizar a Despesa Financeira da DRE '
      || 'e/ou as linhas de juros do mapa (rótulos extraídos não bateram).');
  end if;

  return fn_registrar_reconciliacao(p_caso_id, p_entidade_id, p_periodo_id,
    'despfin_dre_vs_divida', 'B', v_doc_dre, v_fonte_a, v_fonte_b, v_resultado,
    v_pior_abs, v_pior_pct,
    jsonb_build_object('tolerancia_abs', p_tolerancia_abs, 'tolerancia_pct', p_tolerancia_pct,
                       'anos_checados', v_n),
    format('Despesa Financeira da DRE vs juros do Mapa de Dívida em %s ano(s): %s.',
           v_n, array_to_string(v_partes, '; ')));
end;
$$;

--
-- Name: fn_reconciliar_duplicidade(uuid, uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_reconciliar_duplicidade(p_caso_id uuid, p_entidade_id uuid) RETURNS jsonb
    LANGUAGE plpgsql
    AS $$
declare
  v_entidade    text;
  v_pares       record;
  v_n           int := 0;
  v_total       numeric := 0;
  v_detalhe     jsonb := '[]'::jsonb;
  v_descricao   text;
  v_resultado   text;
  v_documento   uuid;
begin
  select razao_social into v_entidade from entidade where id = p_entidade_id;

  for v_pares in
    select * from fn_pares_duplicados_do_caso(p_caso_id, v_entidade)
  loop
    v_n := v_n + 1;
    v_total := v_total + v_pares.valor;
    v_detalhe := v_detalhe || jsonb_build_array(jsonb_build_object(
      'secao_canonica', v_pares.secao_canonica,
      'rotulo_a', v_pares.rotulo_a, 'rotulo_b', v_pares.rotulo_b,
      'valor', v_pares.valor, 'colunas_iguais', v_pares.colunas,
      'radical_comum', v_pares.radical_comum));
  end loop;

  -- Um documento qualquer da entidade, só para a pendência ter onde ancorar o
  -- link da tela. A duplicidade é entre documentos, então não há "o" documento.
  select d.id into v_documento
  from documento d
  where d.caso_id = p_caso_id
    and (p_entidade_id is null or d.entidade_id = p_entidade_id)
  order by d.criado_em
  limit 1;

  if v_n = 0 then
    v_resultado := 'ok';
    v_descricao := 'Nenhum par de rótulos duplicados na entidade.';
  else
    v_resultado := 'divergencia';
    v_descricao := format(
      '%s par(es) de rótulos podem ser a MESMA conta transposta duas vezes (%s no total). '
      || 'Se forem, a soma do grupo está dobrada nesse valor. Pares: %s. '
      || 'NADA foi apagado: decida qual rótulo é a conta e trate o outro na revisão.',
      v_n, to_char(v_total, 'FM999G999G999D00'),
      (select string_agg(format('%s = %s (%s)', x->>'rotulo_a', x->>'rotulo_b',
                                to_char((x->>'valor')::numeric, 'FM999G999G999D00')), '; ')
         from jsonb_array_elements(v_detalhe) x));
  end if;

  return fn_registrar_reconciliacao(
    p_caso_id, p_entidade_id, null, 'duplicidade_de_rotulo', 'A', v_documento,
    jsonb_build_object('pares', v_detalhe), null,
    v_resultado, v_total, null,
    jsonb_build_object('criterio', 'mesma secao_canonica, valor idêntico na mesma coluna, '
      || 'papel conta, e (>=2 colunas coincidentes ou radical estrutural compartilhado)'),
    v_descricao);
end;
$$;

--
-- Name: FUNCTION fn_reconciliar_duplicidade(p_caso_id uuid, p_entidade_id uuid); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.fn_reconciliar_duplicidade(p_caso_id uuid, p_entidade_id uuid) IS 'Checagem de reconciliação: acha a MESMA conta transposta com dois rótulos e abre pendência com o valor dobrado. Não apaga nem reescreve dado — decisão humana. Por caso/entidade (a duplicidade é fato da estrutura dos documentos, não de um exercício), daí periodo_id nulo.';

--
-- Name: fn_reconciliar_por_documento(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_reconciliar_por_documento(p_documento_id uuid) RETURNS jsonb
    LANGUAGE plpgsql
    AS $$
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

  -- Duplicidade de rótulo (0105). Sem loop de período: é por caso/entidade.
  if v_tipo in ('BALANCO', 'BALANCETE', 'COMBINADO') then
    v_checagens := v_checagens || jsonb_build_array(
      fn_reconciliar_duplicidade(v_caso_id, v_entidade_id));
  end if;

  return jsonb_build_object('executado', true, 'documento_id', p_documento_id, 'checagens', v_checagens);
end;
$$;

--
-- Name: FUNCTION fn_reconciliar_por_documento(p_documento_id uuid); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.fn_reconciliar_por_documento(p_documento_id uuid) IS 'Dispara as checagens A/B pertinentes ao tipo do documento. Ausência do documento par NÃO abre pendência (é do checklist do Kit Básico).';

--
-- Name: fn_reconciliar_receita_dre_vs_faturamento(uuid, uuid, uuid, numeric, numeric); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_reconciliar_receita_dre_vs_faturamento(p_caso_id uuid, p_entidade_id uuid, p_periodo_id uuid, p_tolerancia_abs numeric DEFAULT 50000, p_tolerancia_pct numeric DEFAULT 0.05) RETURNS jsonb
    LANGUAGE plpgsql
    AS $$
declare
  v_doc_dre  uuid;
  v_doc_fat  uuid;
  v_ver_dre  uuid;
  v_ver_fat  uuid;
  v_col_ent  text;
  v_ano      int;
  v_col_per  text;
  v_receita  campo_extraido;
  v_soma_sec record;
  v_val_rec  numeric;
  v_unid_rec text;
  v_chave_rec text;
  v_fat      record;
  v_unid_fat text;
  v_motivo   text;
  v_a numeric; v_b numeric; v_div numeric; v_tol numeric;
  v_resultado text := 'ok';
  v_partes text[] := '{}';
  v_n int := 0;
  v_pior_abs numeric; v_pior_pct numeric;
  v_fonte_a jsonb; v_fonte_b jsonb;
begin
  v_doc_dre := fn_documento_por_tipo(p_caso_id, p_entidade_id, p_periodo_id, 'DRE');
  v_doc_fat := fn_documento_por_tipo(p_caso_id, p_entidade_id, p_periodo_id, 'FATURAMENTO_24M');

  if v_doc_dre is null or v_doc_fat is null then
    return fn_registrar_reconciliacao(p_caso_id, p_entidade_id, p_periodo_id,
      'receita_dre_vs_faturamento', 'B', coalesce(v_doc_dre, v_doc_fat), null, null,
      'documento_ausente', null, null,
      jsonb_build_object('tolerancia_abs', p_tolerancia_abs, 'tolerancia_pct', p_tolerancia_pct),
      format('Sem par para reconciliar receita: %s não foi entregue para esta entidade/período.',
        case when v_doc_dre is null and v_doc_fat is null then 'DRE e Faturamento (24m)'
             when v_doc_dre is null then 'DRE' else 'Faturamento (24m)' end));
  end if;

  v_ver_dre  := fn_versao_atual(v_doc_dre);
  v_ver_fat  := fn_versao_atual(v_doc_fat);
  v_col_ent  := fn_coluna_entidade(v_ver_dre, p_entidade_id);
  v_unid_fat := fn_unidade_predominante(v_ver_fat);

  foreach v_ano in array fn_anos_alvo(p_periodo_id) loop
    if v_ano is null then continue; end if;   -- sem ano não há como recortar o mês
    v_col_per := fn_coluna_periodo_do_ano(v_ver_dre, v_ano);

    select * into v_receita from fn_valor_conceito_col(v_ver_dre,
      array['receita', 'bruta'], array['liquida', 'deducoes', 'deducao'], v_col_ent, v_col_per);
    if v_receita.id is not null then
      v_val_rec := v_receita.valor_num; v_unid_rec := v_receita.unidade;
      v_chave_rec := v_receita.chave;
    else
      -- "RECEITA OPERACIONAL BRUTA" costuma ser CABEÇALHO SEM VALOR: soma as
      -- contas da seção (Vendas de produtos, Prestação de serviços...).
      select * into v_soma_sec from fn_soma_secao(v_ver_dre,
        array['receita', 'bruta'], v_col_ent, v_col_per,
        array['deducoes', 'deducao'],
        array['liquida', 'lucro bruto', 'resultado', 'prejuizo']);
      if coalesce(v_soma_sec.n_linhas, 0) = 0 then continue; end if;
      v_val_rec := v_soma_sec.soma; v_unid_rec := v_soma_sec.unidade;
      v_chave_rec := format('soma de %s contas da seção Receita Bruta', v_soma_sec.n_linhas);
    end if;

    select soma, n_linhas into v_fat
    from fn_somar_faturamento_ano(v_ver_fat, v_ano::text, right(v_ano::text, 2));
    if coalesce(v_fat.n_linhas, 0) = 0 then continue; end if;

    v_motivo := fn_motivo_escala_incomparavel(v_unid_rec, v_unid_fat,
      'a Receita Bruta da DRE', 'o Faturamento mensal');
    if v_motivo is not null then
      return fn_registrar_reconciliacao(p_caso_id, p_entidade_id, p_periodo_id,
        'receita_dre_vs_faturamento', 'B', v_doc_dre, null, null,
        'precondicao_nao_satisfeita', null, null,
        jsonb_build_object('tolerancia_abs', p_tolerancia_abs, 'tolerancia_pct', p_tolerancia_pct),
        v_motivo);
    end if;

    v_a := fn_valor_em_base(v_val_rec, v_unid_rec);
    v_b := fn_valor_em_base(v_fat.soma, v_unid_fat);
    v_n := v_n + 1;
    v_div := abs(v_a - v_b);
    v_tol := greatest(p_tolerancia_abs * coalesce(fn_fator_escala(v_unid_rec), 1),
                      abs(v_a) * p_tolerancia_pct);
    if v_div > v_tol then
      v_resultado := 'zona_cinzenta';
      v_partes := v_partes || format('%s: Receita Bruta %s vs %s meses de faturamento %s — diferença de %s '
        || '(Classe B: faturamento e receita reconhecida podem divergir por competência/recorte)',
        v_ano, v_val_rec, v_fat.n_linhas, v_fat.soma, v_div);
      if v_pior_abs is null or v_div > v_pior_abs then
        v_pior_abs := v_div;
        v_pior_pct := case when v_a <> 0 then v_div / abs(v_a) end;
      end if;
    else
      v_partes := v_partes || format('%s: confere (Receita Bruta %s = soma de %s meses %s)',
        v_ano, v_val_rec, v_fat.n_linhas, v_fat.soma);
    end if;
    v_fonte_a := jsonb_build_object('chave', v_chave_rec, 'valor', v_val_rec,
      'unidade', v_unid_rec, 'ano', v_ano, 'documento_versao_id', v_ver_dre);
    v_fonte_b := jsonb_build_object('soma_faturamento', v_fat.soma, 'n_meses', v_fat.n_linhas,
      'ano', v_ano, 'unidade', v_unid_fat, 'documento_versao_id', v_ver_fat);
  end loop;

  if v_n = 0 then
    return fn_registrar_reconciliacao(p_caso_id, p_entidade_id, p_periodo_id,
      'receita_dre_vs_faturamento', 'B', v_doc_dre, null, null,
      'precondicao_nao_satisfeita', null, null,
      jsonb_build_object('tolerancia_abs', p_tolerancia_abs, 'tolerancia_pct', p_tolerancia_pct),
      'DRE e Faturamento presentes, mas não foi possível casar Receita Bruta e meses do mesmo ano '
      || '(rótulos extraídos não bateram, ou o faturamento não traz o mês por linha).');
  end if;

  return fn_registrar_reconciliacao(p_caso_id, p_entidade_id, p_periodo_id,
    'receita_dre_vs_faturamento', 'B', v_doc_dre, v_fonte_a, v_fonte_b, v_resultado,
    v_pior_abs, v_pior_pct,
    jsonb_build_object('tolerancia_abs', p_tolerancia_abs, 'tolerancia_pct', p_tolerancia_pct,
                       'anos_checados', v_n),
    format('Receita Bruta da DRE vs faturamento mensal em %s ano(s): %s.',
           v_n, array_to_string(v_partes, '; ')));
end;
$$;

--
-- Name: fn_reconferir_caso(uuid, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_reconferir_caso(p_caso_id uuid, p_autor text DEFAULT 'portal:reconferir'::text) RETURNS jsonb
    LANGUAGE plpgsql
    AS $$
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

--
-- Name: FUNCTION fn_reconferir_caso(p_caso_id uuid, p_autor text); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.fn_reconferir_caso(p_caso_id uuid, p_autor text) IS 'Reaplica as regras de HOJE (reconciliação A/B, guardas de extração, completude) sobre o dado já gravado, sem gastar chamada de IA. Existe porque pendência é estado gravado e nada a reavaliava quando uma migration corrigia a regra — o portal mostrava achado corrigido como se fosse corrente (caso real: as duas pendências do v35 que a 0034 já havia fechado).';

--
-- Name: fn_registrar_campos_extraidos(uuid, jsonb, public.nivel_autonomia, text, boolean); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_registrar_campos_extraidos(p_documento_versao_id uuid, p_campos jsonb, p_nivel public.nivel_autonomia DEFAULT 'N0'::public.nivel_autonomia, p_falha_motivo text DEFAULT NULL::text, p_tem_dado_financeiro boolean DEFAULT NULL::boolean) RETURNS integer
    LANGUAGE plpgsql
    AS $_$
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
  v_nivel_dial         nivel_autonomia;
  v_limiar             numeric;
  v_auto_permitido     boolean;
  v_g                  jsonb;
begin
  select ea.nivel_atual, ea.limiar_auto_clear into v_nivel_dial, v_limiar
  from estagio_autonomia ea where ea.estagio = 'extracao_linhas_financeiras';
  v_auto_permitido := v_nivel_dial in ('N2', 'N3') and v_limiar is not null;

  if p_campos is not null and jsonb_typeof(p_campos) = 'array' then
    for v_item in select * from jsonb_array_elements(p_campos)
    loop
      v_valor := case when (v_item->>'valor_num') ~ '^-?\d+(\.\d+)?$' then (v_item->>'valor_num')::numeric else null end;
      v_confianca := case when (v_item->>'confianca') ~ '^-?\d+(\.\d+)?$' then (v_item->>'confianca')::numeric else null end;

      v_status_aceite := 'pendente';
      v_aceito_por := null;
      v_aceito_em := null;
      if v_auto_permitido and v_confianca is not null and v_confianca >= v_limiar then
        v_n_auto_aceitos := v_n_auto_aceitos + 1;
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
            jsonb_build_object('campos', v_count, 'nivel', p_nivel, 'falha_motivo', p_falha_motivo,
                               'tem_dado_financeiro', p_tem_dado_financeiro, 'auto_aceitos', v_n_auto_aceitos));

  select d.id, d.caso_id, dv.nome_original into v_documento_id, v_caso_id, v_nome_original
  from documento_versao dv join documento d on d.id = dv.documento_id
  where dv.id = p_documento_versao_id;

  if v_documento_id is null then
    insert into evento_auditoria (ator, acao, entidade_ref, depois)
      values ('sistema:n8n', 'extracao_orfa', 'documento_versao:'||coalesce(p_documento_versao_id::text,'null'),
              jsonb_build_object('campos_descartados', v_count, 'falha_motivo', p_falha_motivo,
                                 'porque', 'documento_versao inexistente: campos e motivo nao tinham onde ser gravados'));
    raise warning 'fn_registrar_campos_extraidos: documento_versao % inexistente; % campo(s) e o motivo "%" foram descartados',
      p_documento_versao_id, v_count, coalesce(p_falha_motivo, '(sem motivo)');
    return v_count;
  end if;

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

  -- ----- Sinal 3 (0016/0029, unidade corrigida por 0111) ---------------------
  -- "veio vazia" só é sinal de FALHA quando ninguém disse o contrário. Um
  -- chamador antigo (workflow não reimportado) manda `p_tem_dado_financeiro`
  -- null, e o comportamento é IDÊNTICO ao de antes desta migration
  -- (coalesce(null, true) = true). Só o diagnóstico da própria chamada, com
  -- `false` explícito, prova que zero linhas era o resultado certo.
  select id into v_pendencia_id from pendencia
    where caso_id = v_caso_id and motivo = 'extracao:falhou:' || v_documento_id and estado <> 'resolvida'
    limit 1;
  if p_falha_motivo is not null or (v_count = 0 and coalesce(p_tem_dado_financeiro, true)) then
    v_guarda_disparou := true;
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

  perform fn_recomputar_completude(v_caso_id);

  return v_count;
end;
$_$;

--
-- Name: FUNCTION fn_registrar_campos_extraidos(p_documento_versao_id uuid, p_campos jsonb, p_nivel public.nivel_autonomia, p_falha_motivo text, p_tem_dado_financeiro boolean); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.fn_registrar_campos_extraidos(p_documento_versao_id uuid, p_campos jsonb, p_nivel public.nivel_autonomia, p_falha_motivo text, p_tem_dado_financeiro boolean) IS 'Grava campos extraídos e roda as três guardas (0043: fn_avaliar_guardas_extracao). Sinal 3 ("veio vazia") só dispara extracao_falhou quando p_tem_dado_financeiro não é explicitamente false — 0111: documento sem valor monetário por natureza (certidão, organograma, parecer de auditoria) não é falha de extração.';

--
-- Name: fn_registrar_diagnostico(uuid, uuid, text, boolean, text, text, text, public.legibilidade, text, text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_registrar_diagnostico(p_documento_id uuid, p_documento_versao_id uuid, p_entidade_nome text, p_tipo_confirma boolean, p_tipo_sugerido text, p_periodo_tipo text, p_periodo_referencia text, p_legibilidade public.legibilidade, p_nota_legibilidade text, p_resumo text, p_justificativa text) RETURNS jsonb
    LANGUAGE plpgsql
    AS $$
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

--
-- Name: fn_registrar_documento(uuid, text, text, text, text, numeric, text, public.origem_arquivo, text, text, boolean, text, public.legibilidade, numeric, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_registrar_documento(p_caso_id uuid, p_entidade_nome text, p_periodo_tipo text, p_periodo_ref text, p_tipo_taxonomia text, p_confianca numeric, p_fonte text, p_origem_arquivo public.origem_arquivo, p_arquivo_ref text, p_nome_original text, p_assinado boolean, p_hash text, p_legibilidade public.legibilidade, p_threshold numeric DEFAULT 0.7, p_justificativa text DEFAULT NULL::text) RETURNS jsonb
    LANGUAGE plpgsql
    AS $$
declare
  v_entidade_id uuid;
  v_periodo_id  uuid;
  v_documento_id uuid;
  v_versao_id   uuid;
  v_n_versao    int := 1;
  v_obrig obrigatoriedade;
  v_reaproveitou boolean := false;
begin
  -- 0030: casamento por forma CANÔNICA. Era `lower(razao_social) = lower(...)`, e
  -- desde o PR #65 a entidade vem de duas fontes que escrevem diferente ("Vertentes
  -- Metalurgica" do nome do arquivo, sem acento; "Vertentes Metalúrgica Ltda." do
  -- diagnóstico) — `lower()` não aproxima as duas e criava DUAS empresas.
  v_entidade_id := fn_upsert_entidade(p_caso_id, p_entidade_nome);

  -- 0030: idem para período. '2025' e '12M25' são o MESMO exercício; gravar cru
  -- fragmentava em duas linhas `periodo` e o documento ficava ligado a uma delas.
  v_periodo_id := fn_upsert_periodo(p_caso_id, p_periodo_tipo, p_periodo_ref);

  -- Já existe ESTE arquivo (mesmo hash) neste caso? Então é reextração/reenvio:
  -- versão nova sob o mesmo documento. Hash nulo nunca casa (ver cabeçalho).
  if p_hash is not null and length(trim(p_hash)) > 0 then
    select dv.documento_id into v_documento_id
    from documento_versao dv
    join documento d on d.id = dv.documento_id
    where d.caso_id = p_caso_id and dv.hash = p_hash
    order by dv.criada_em desc
    limit 1;
    v_reaproveitou := v_documento_id is not null;
  end if;

  if v_reaproveitou then
    select coalesce(max(n_versao), 0) + 1 into v_n_versao
      from documento_versao where documento_id = v_documento_id;
    -- A classificação da versão nova prevalece SOBRE A DO SISTEMA, nunca sobre a
    -- do humano: se alguém já revisou este documento na fila (`fonte='humano'`,
    -- `db/migrations/0008`), a reextração não desfaz a decisão dele — é a
    -- anti-ancoragem de sempre (docs/01), no sentido que importa: máquina não
    -- sobrepõe humano. Entidade/período seguem a mesma regra.
    update documento d set
      tipo_taxonomia = case when d.fonte = 'humano' then d.tipo_taxonomia else p_tipo_taxonomia end,
      entidade_id    = case when d.fonte = 'humano' then d.entidade_id else coalesce(v_entidade_id, d.entidade_id) end,
      periodo_id     = case when d.fonte = 'humano' then d.periodo_id else coalesce(v_periodo_id, d.periodo_id) end,
      confianca      = case when d.fonte = 'humano' then d.confianca else p_confianca end,
      fonte          = case when d.fonte = 'humano' then d.fonte else p_fonte end,
      justificativa  = case when d.fonte = 'humano' then d.justificativa else p_justificativa end,
      status         = case when d.fonte = 'humano' then d.status else 'em_validacao' end
    where d.id = v_documento_id;
  else
    insert into documento (caso_id, entidade_id, periodo_id, tipo_taxonomia, status, confianca, fonte, justificativa)
      values (p_caso_id, v_entidade_id, v_periodo_id, p_tipo_taxonomia, 'em_validacao', p_confianca, p_fonte, p_justificativa)
      returning id into v_documento_id;
  end if;

  insert into documento_versao
    (documento_id, n_versao, origem_arquivo, arquivo_ref, nome_original, assinado, hash, legibilidade)
    values (v_documento_id, v_n_versao, coalesce(p_origem_arquivo,'supabase_storage'),
            p_arquivo_ref, p_nome_original, p_assinado, p_hash, p_legibilidade)
    returning id into v_versao_id;

  -- Checklist: só na PRIMEIRA vez. Reextração não é documento novo — inserir de
  -- novo daria dois itens "presente" para o mesmo documento e inflaria a
  -- completude com um arquivo só (a `unique` do checklist não cobre isso porque
  -- `documento_id` faz parte da linha).
  if p_tipo_taxonomia is not null and not v_reaproveitou then
    select obrigatoriedade into v_obrig from taxonomia_tipo_documento where codigo = p_tipo_taxonomia;
    insert into checklist_item_status
      (caso_id, entidade_id, periodo_id, tipo_taxonomia, obrigatoriedade, status, documento_id)
      values (p_caso_id, v_entidade_id, v_periodo_id, p_tipo_taxonomia,
              coalesce(v_obrig,'complementar'), 'presente', v_documento_id);
  end if;

  -- Pendência de classificação incerta: idempotente por documento. Antes cada
  -- reenvio abria mais uma (documento novo, pendência nova); agora, se já existe
  -- uma aberta para este documento, ela continua sendo a mesma pendência — a
  -- reextração não multiplica cartões na fila do dono.
  if p_tipo_taxonomia is null or coalesce(p_confianca,0) < p_threshold then
    if not exists (
      select 1 from pendencia p
      where p.documento_id = v_documento_id
        and p.tipo = 'classificacao_pendente'
        and p.estado <> 'resolvida'
    ) then
      insert into pendencia (caso_id, origem_estagio, tipo, severidade, sobrepujavel, descricao, documento_id)
        values (p_caso_id, 'classificacao', 'classificacao_pendente', 'importante', true,
                format('Classificação incerta (conf=%s, fonte=%s) para "%s". Motivo: %s',
                       coalesce(p_confianca,0), coalesce(p_fonte,'?'), coalesce(p_nome_original,'?'),
                       coalesce(nullif(trim(p_justificativa), ''), 'nenhuma justificativa fornecida')),
                v_documento_id);
    end if;
  end if;

  insert into evento_auditoria (ator, acao, entidade_ref, depois)
    values ('sistema:n8n',
            case when v_reaproveitou then 'documento_reextraido' else 'documento_registrado' end,
            'documento:'||v_documento_id,
            jsonb_build_object('tipo', p_tipo_taxonomia, 'confianca', p_confianca, 'fonte', p_fonte,
                               'justificativa', p_justificativa, 'n_versao', v_n_versao,
                               'hash', p_hash));

  return jsonb_build_object(
    'documento_id', v_documento_id,
    'documento_versao_id', v_versao_id,
    'n_versao', v_n_versao,
    'reaproveitou_documento', v_reaproveitou
  );
end;
$$;

--
-- Name: FUNCTION fn_registrar_documento(p_caso_id uuid, p_entidade_nome text, p_periodo_tipo text, p_periodo_ref text, p_tipo_taxonomia text, p_confianca numeric, p_fonte text, p_origem_arquivo public.origem_arquivo, p_arquivo_ref text, p_nome_original text, p_assinado boolean, p_hash text, p_legibilidade public.legibilidade, p_threshold numeric, p_justificativa text); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.fn_registrar_documento(p_caso_id uuid, p_entidade_nome text, p_periodo_tipo text, p_periodo_ref text, p_tipo_taxonomia text, p_confianca numeric, p_fonte text, p_origem_arquivo public.origem_arquivo, p_arquivo_ref text, p_nome_original text, p_assinado boolean, p_hash text, p_legibilidade public.legibilidade, p_threshold numeric, p_justificativa text) IS 'Registra um arquivo classificado (E1). Idempotente por (caso_id, hash): o MESMO arquivo reenviado/reextraído vira nova documento_versao sob o mesmo documento (n_versao+1), sem duplicar documento, checklist nem pendência. Hash nulo não casa. Classificação da máquina não sobrepõe revisão humana (documento.fonte = ''humano'').';

--
-- Name: fn_registrar_expectativa_macro(jsonb); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_registrar_expectativa_macro(p_exp jsonb) RETURNS integer
    LANGUAGE plpgsql
    AS $$
declare v_n int := 0;
begin
  if p_exp is null or jsonb_typeof(p_exp) <> 'array' then return 0; end if;

  with dados as (
    select
      (e->>'serie')::text        as serie,
      (e->>'ano_ref')::int       as ano_ref,
      (e->>'mediana')::numeric   as mediana,
      nullif(e->>'media','')::numeric as media,
      nullif(e->>'respondentes','')::int as respondentes,
      (e->>'coletado_em')::date  as coletado_em
    from jsonb_array_elements(p_exp) as e
    where e->>'serie' is not null and e->>'ano_ref' is not null
      and e->>'mediana' is not null and e->>'coletado_em' is not null
  ),
  validos as (select d.* from dados d join indice_macro_serie s on s.codigo = d.serie),
  gravado as (
    insert into indice_macro_expectativa (serie, ano_ref, mediana, media, respondentes, coletado_em)
    select serie, ano_ref, mediana, media, respondentes, coletado_em from validos
    on conflict (serie, ano_ref, coletado_em) do update
      set mediana = excluded.mediana, media = excluded.media,
          respondentes = excluded.respondentes
    returning 1
  )
  select count(*)::int into v_n from gravado;
  return coalesce(v_n, 0);
end;
$$;

--
-- Name: fn_registrar_falha_execucao(uuid, text, text, text, jsonb); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_registrar_falha_execucao(p_caso_id uuid, p_caso_nome text, p_etapa text, p_mensagem text, p_detalhe jsonb DEFAULT NULL::jsonb) RETURNS jsonb
    LANGUAGE plpgsql
    AS $$
declare
  v_id uuid;
begin
  insert into execucao_falha (caso_id, caso_nome, etapa, mensagem, detalhe)
    values (p_caso_id, nullif(trim(coalesce(p_caso_nome, '')), ''),
            coalesce(nullif(trim(p_etapa), ''), 'desconhecida'),
            coalesce(nullif(trim(p_mensagem), ''), 'Falha sem mensagem.'),
            p_detalhe)
    returning id into v_id;

  insert into evento_auditoria (ator, acao, entidade_ref, depois)
    values ('sistema:n8n', 'falha_execucao',
            coalesce('caso:' || p_caso_id::text, 'caso_nome:' || coalesce(p_caso_nome, '?')),
            jsonb_build_object('etapa', p_etapa, 'mensagem', p_mensagem, 'detalhe', p_detalhe));

  return jsonb_build_object('falha_id', v_id, 'registrada', true);
end;
$$;

--
-- Name: FUNCTION fn_registrar_falha_execucao(p_caso_id uuid, p_caso_nome text, p_etapa text, p_mensagem text, p_detalhe jsonb); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.fn_registrar_falha_execucao(p_caso_id uuid, p_caso_nome text, p_etapa text, p_mensagem text, p_detalhe jsonb) IS 'Registra falha do pipeline para a TELA mostrar (e para a trilha guardar). Aceita caso_id nulo: a falha pode acontecer antes de o caso existir, e falha órfã é falha invisível.';

--
-- Name: fn_registrar_indice_macro(jsonb); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_registrar_indice_macro(p_obs jsonb) RETURNS TABLE(n_inseridas integer, n_atualizadas integer)
    LANGUAGE plpgsql
    AS $$
declare
  v_ins int := 0;
  v_upd int := 0;
begin
  if p_obs is null or jsonb_typeof(p_obs) <> 'array' then
    return query select 0, 0;
    return;
  end if;

  with dados as (
    select
      (o->>'serie')::text                        as serie,
      (o->>'fonte')::text                        as fonte,
      (o->>'data_ref')::date                     as data_ref,
      (o->>'valor')::numeric                     as valor
    from jsonb_array_elements(p_obs) as o
    where o->>'serie' is not null
      and o->>'data_ref' is not null
      and o->>'valor' is not null
  ),
  -- Série desconhecida é IGNORADA de propósito: um código novo tem de passar
  -- por migration (o catálogo é a fonte da verdade), não entrar pela ingestão.
  validos as (
    select d.* from dados d join indice_macro_serie s on s.codigo = d.serie
  ),
  gravado as (
    insert into indice_macro_obs (serie, fonte, data_ref, valor)
    select serie, fonte, data_ref, valor from validos
    on conflict (serie, fonte, data_ref) do update
      set valor = excluded.valor, coletado_em = now()
      where indice_macro_obs.valor is distinct from excluded.valor
    returning (xmax = 0) as inserida
  )
  select
    count(*) filter (where inserida)::int,
    count(*) filter (where not inserida)::int
  into v_ins, v_upd
  from gravado;

  return query select coalesce(v_ins, 0), coalesce(v_upd, 0);
end;
$$;

--
-- Name: fn_registrar_reconciliacao(uuid, uuid, uuid, text, text, uuid, jsonb, jsonb, text, numeric, numeric, jsonb, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_registrar_reconciliacao(p_caso_id uuid, p_entidade_id uuid, p_periodo_id uuid, p_tipo text, p_classe text, p_documento_id uuid, p_fonte_a jsonb, p_fonte_b jsonb, p_resultado text, p_divergencia_abs numeric, p_divergencia_pct numeric, p_materialidade jsonb, p_descricao text) RETURNS jsonb
    LANGUAGE plpgsql
    AS $$
declare
  v_reconciliacao_id uuid;
  v_pendencia_id     uuid;
  v_motivo           text := 'reconciliacao:' || p_tipo;
  -- 'documento_ausente' é um resultado NOSSO, para decidir a pendência; no log
  -- ele é gravado como pré-condição não satisfeita (é o que ele é).
  v_res_log          text := case when p_resultado = 'documento_ausente'
                                  then 'precondicao_nao_satisfeita' else p_resultado end;
  v_abre_pendencia   boolean := p_resultado not in ('ok', 'documento_ausente');
begin
  insert into reconciliacao
    (caso_id, entidade_id, periodo_id, tipo, classe, fonte_a, fonte_b,
     precondicoes_ok, resultado, divergencia_abs, divergencia_pct, materialidade)
  values (
    p_caso_id, p_entidade_id, p_periodo_id, p_tipo, p_classe, p_fonte_a, p_fonte_b,
    v_res_log <> 'precondicao_nao_satisfeita', v_res_log,
    p_divergencia_abs, p_divergencia_pct, p_materialidade
  )
  returning id into v_reconciliacao_id;

  select id into v_pendencia_id from pendencia
  where caso_id = p_caso_id and motivo = v_motivo
    and coalesce(entidade_id, '00000000-0000-0000-0000-000000000000'::uuid)
      = coalesce(p_entidade_id, '00000000-0000-0000-0000-000000000000'::uuid)
    -- Período COMPATÍVEL, não igual: a mesma checagem chega por dois documentos
    -- com granularidade diferente (DRE "multi 24,25" × Faturamento "L24M") e sem
    -- isso o mesmo achado abriria duas pendências.
    and (periodo_id is not distinct from p_periodo_id
         or fn_periodos_compativeis(periodo_id, p_periodo_id))
    and estado <> 'resolvida'
  order by criada_em
  limit 1;

  if v_abre_pendencia then
    if v_pendencia_id is null then
      insert into pendencia
        (caso_id, origem_estagio, tipo, severidade, sobrepujavel, descricao,
         documento_id, entidade_id, periodo_id, motivo)
      values (
        p_caso_id, 'reconciliacao',
        case when v_res_log = 'precondicao_nao_satisfeita' then 'precondicao_nao_satisfeita'
             else 'divergencia_reconciliacao' end::pendencia_tipo,
        'importante', true, p_descricao, p_documento_id, p_entidade_id, p_periodo_id, v_motivo
      )
      returning id into v_pendencia_id;
    else
      update pendencia set descricao = p_descricao where id = v_pendencia_id;
    end if;
  elsif v_pendencia_id is not null then
    -- Sumiu o sintoma (reextração corrigiu, ou a pendência era falsa e a regra
    -- nova não a emite mais): fecha. Não escreve número nenhum em base viva.
    update pendencia set estado = 'resolvida', resolvida_em = now(),
           resolvida_por = 'sistema:reconciliacao'
    where id = v_pendencia_id;
    v_pendencia_id := null;
  end if;

  insert into evento_auditoria (ator, acao, entidade_ref, depois)
    values ('sistema:reconciliacao', 'reconciliacao_' || p_tipo,
            'reconciliacao:' || v_reconciliacao_id,
            jsonb_build_object('resultado', p_resultado, 'divergencia_abs', p_divergencia_abs));

  return jsonb_build_object(
    'reconciliacao_id', v_reconciliacao_id, 'tipo', p_tipo,
    'resultado', p_resultado, 'pendencia_id', v_pendencia_id
  );
end;
$$;

--
-- Name: fn_registrar_reconciliacao_b(uuid, uuid, uuid, text, uuid, jsonb, jsonb, text, numeric, numeric, jsonb, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_registrar_reconciliacao_b(p_caso_id uuid, p_entidade_id uuid, p_periodo_id uuid, p_tipo text, p_documento_id uuid, p_fonte_a jsonb, p_fonte_b jsonb, p_resultado text, p_divergencia_abs numeric, p_divergencia_pct numeric, p_materialidade jsonb, p_descricao text) RETURNS jsonb
    LANGUAGE sql
    AS $$
  select fn_registrar_reconciliacao(p_caso_id, p_entidade_id, p_periodo_id, p_tipo, 'B',
    p_documento_id, p_fonte_a, p_fonte_b, p_resultado, p_divergencia_abs,
    p_divergencia_pct, p_materialidade, p_descricao);
$$;

--
-- Name: fn_revisar_documento(uuid, text, text, text, text, text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_revisar_documento(p_documento_id uuid, p_autor text, p_novo_tipo_taxonomia text DEFAULT NULL::text, p_nova_entidade_nome text DEFAULT NULL::text, p_novo_periodo_tipo text DEFAULT NULL::text, p_novo_periodo_ref text DEFAULT NULL::text, p_motivo text DEFAULT NULL::text) RETURNS jsonb
    LANGUAGE plpgsql
    AS $$
declare
  v_caso_id     uuid;
  v_tipo_antigo text;
  v_entidade_id uuid;
  v_periodo_id  uuid;
  v_tipo_final  text;
  v_obrig       obrigatoriedade;
  v_mudou_tipo  boolean;
begin
  select caso_id, tipo_taxonomia, entidade_id, periodo_id
    into v_caso_id, v_tipo_antigo, v_entidade_id, v_periodo_id
  from documento where id = p_documento_id;

  if v_caso_id is null then
    raise exception 'documento % não encontrado', p_documento_id;
  end if;

  if p_nova_entidade_nome is not null and length(trim(p_nova_entidade_nome)) > 0 then
    select id into v_entidade_id from entidade
      where caso_id = v_caso_id and lower(razao_social) = lower(p_nova_entidade_nome) limit 1;
    if v_entidade_id is null then
      insert into entidade (caso_id, razao_social) values (v_caso_id, p_nova_entidade_nome)
        returning id into v_entidade_id;
    end if;
  end if;

  if p_novo_periodo_ref is not null and length(trim(p_novo_periodo_ref)) > 0 then
    select id into v_periodo_id from periodo
      where caso_id = v_caso_id and tipo = coalesce(p_novo_periodo_tipo,'outro') and referencia = p_novo_periodo_ref limit 1;
    if v_periodo_id is null then
      insert into periodo (caso_id, tipo, referencia)
        values (v_caso_id, coalesce(p_novo_periodo_tipo,'outro'), p_novo_periodo_ref)
        returning id into v_periodo_id;
    end if;
  end if;

  v_tipo_final := coalesce(p_novo_tipo_taxonomia, v_tipo_antigo);
  v_mudou_tipo := v_tipo_final is distinct from v_tipo_antigo;

  update documento set
    tipo_taxonomia = v_tipo_final,
    entidade_id     = v_entidade_id,
    periodo_id      = v_periodo_id,
    confianca       = 1.0,
    fonte           = 'humano',
    justificativa   = coalesce(p_motivo, justificativa)
  where id = p_documento_id;

  -- Checklist: a entrada antiga (se houver) ficaria presa ao tipo errado —
  -- remove e recria para o tipo final (idempotente: sempre reflete o estado atual).
  delete from checklist_item_status where documento_id = p_documento_id;
  if v_tipo_final is not null then
    select obrigatoriedade into v_obrig from taxonomia_tipo_documento where codigo = v_tipo_final;
    insert into checklist_item_status
      (caso_id, entidade_id, periodo_id, tipo_taxonomia, obrigatoriedade, status, documento_id)
      values (v_caso_id, v_entidade_id, v_periodo_id, v_tipo_final,
              coalesce(v_obrig,'complementar'), 'presente', p_documento_id);
  end if;

  insert into decisao (caso_id, tipo, autor, motivo, payload)
    values (v_caso_id,
            (case when v_mudou_tipo then 'correcao_classificacao' else 'aprovacao' end)::decisao_tipo,
            p_autor, p_motivo,
            jsonb_build_object('documento_id', p_documento_id, 'tipo_de', v_tipo_antigo, 'tipo_para', v_tipo_final));

  -- FIX (0018): resolve TODOS os tipos de pendência de revisão gerados para
  -- este documento — não só `classificacao_pendente`. `tipo_incorreto`/
  -- `entidade_incorreta`/`periodo_incorreto` (migration 0010) são fechados
  -- pela MESMA ação de revisão (o formulário já reenvia tipo+entidade+período
  -- juntos), então a resolução tem que cobrir os quatro.
  update pendencia set estado = 'resolvida', resolvida_em = now(), resolvida_por = p_autor
  where documento_id = p_documento_id
    and tipo in ('classificacao_pendente', 'tipo_incorreto', 'entidade_incorreta', 'periodo_incorreto')
    and estado <> 'resolvida';

  insert into evento_auditoria (ator, acao, entidade_ref, antes, depois)
    values (p_autor, 'documento_revisado', 'documento:'||p_documento_id,
            jsonb_build_object('tipo', v_tipo_antigo),
            jsonb_build_object('tipo', v_tipo_final, 'motivo', p_motivo));

  perform fn_recomputar_completude(v_caso_id);

  return jsonb_build_object('documento_id', p_documento_id, 'tipo_taxonomia', v_tipo_final, 'mudou_tipo', v_mudou_tipo);
end;
$$;

--
-- Name: fn_rotulo_contido(text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_rotulo_contido(p_curto text, p_longo text) RETURNS boolean
    LANGUAGE sql IMMUTABLE
    AS $$
  select fn_tem_palavra_longa(p_curto)
     and fn_radicais_rotulo(p_curto) <@ fn_radicais_rotulo(p_longo);
$$;

--
-- Name: FUNCTION fn_rotulo_contido(p_curto text, p_longo text); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.fn_rotulo_contido(p_curto text, p_longo text) IS 'O primeiro rótulo é uma descrição mais grossa do segundo (radicais de 5 letras contidos, com ao menos uma palavra de 4+ letras)? Usado por sobreposicao_suspeita: valor igual sozinho acusa coincidência, e guarda que acusa coincidência é guarda que se aprende a ignorar.';

--
-- Name: fn_rotulo_estrutural(text, text[]); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_rotulo_estrutural(p_chave text, p_tokens_exigidos text[]) RETURNS boolean
    LANGUAGE sql IMMUTABLE
    AS $$
  select fn_tokens_estruturais(p_chave)
       = coalesce((select array_agg(distinct t order by t) from unnest(p_tokens_exigidos) as t),
                  array[]::text[]);
$$;

--
-- Name: FUNCTION fn_rotulo_estrutural(p_chave text, p_tokens_exigidos text[]); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.fn_rotulo_estrutural(p_chave text, p_tokens_exigidos text[]) IS 'Um rótulo É o total de um grupo quando, tiradas ligação e a palavra "total", sobram exatamente as palavras estruturais do grupo. Tradução do `soEstrutural` do classificador TypeScript (0034); desde a 0102 apoiada em fn_tokens_estruturais.';

--
-- Name: fn_rotulos_candidatos(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_rotulos_candidatos(p_documento_versao_id uuid) RETURNS text
    LANGUAGE sql STABLE
    AS $$
  with cand as (
    select distinct
      ce.chave,
      coalesce(nullif(ce.entidade_coluna, ''), '—') as ec,
      coalesce(nullif(ce.periodo_coluna, ''), '—')  as pc
    from campo_extraido ce
    where ce.documento_versao_id = p_documento_versao_id
      and ce.valor_num is not null
      and (fn_normalizar_texto(ce.chave) like '%total%'
           or fn_normalizar_texto(ce.chave) like '%ativo%'
           or fn_normalizar_texto(ce.chave) like '%passivo%'
           or fn_normalizar_texto(ce.chave) like '%patrimonio%')
    order by ce.chave
    limit 12
  )
  select case when count(*) = 0
    then 'nenhum rótulo com ativo/passivo/patrimônio/total foi extraído desta versão'
    else string_agg(format('"%s" [entidade: %s; período: %s]', chave, ec, pc), ', ' order by chave)
  end
  from cand;
$$;

--
-- Name: FUNCTION fn_rotulos_candidatos(p_documento_versao_id uuid); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.fn_rotulos_candidatos(p_documento_versao_id uuid) IS 'Rótulos extraídos que poderiam ser um total de Ativo/Passivo/PL, com a coluna de entidade/período de cada um. Existe para a pendência de pré-condição poder NOMEAR o que não casou — inclusive quando o que não casou foi a COLUNA (0033).';

--
-- Name: fn_sazonalidade_do_caso(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_sazonalidade_do_caso(p_caso_id uuid) RETURNS TABLE(mes integer, fracao numeric, n_observacoes bigint)
    LANGUAGE sql STABLE
    AS $$
  -- marca-0102
  with mensal as (
    select fn_mes_do_rotulo(ce.chave) as mes, abs(ce.valor_num) as valor
    from campo_extraido ce
    join documento_versao dv on dv.id = ce.documento_versao_id
    join documento d on d.id = dv.documento_id
    where d.caso_id = p_caso_id
      and d.tipo_taxonomia = 'FATURAMENTO_24M'
      and ce.valor_num is not null
      -- A linha de TOTAL não é um mês. Continua sendo o `fn_mes_do_rotulo` que a
      -- exclui (nenhuma palavra de mês em "TOTAL DO EXERCÍCIO"); este filtro é
      -- REDUNDANTE de propósito, para um rótulo como "Total jan-dez", e está
      -- anotado como redundante para ninguém escrever um teste acreditando estar
      -- provando ele — foi o que aconteceu na primeira versão do teste da 0040.
      and fn_normalizar_texto(ce.chave) not like 'total%'
      -- 0042: e a linha DERIVADA também não é um mês. "Média mensal" não casa
      -- palavra de mês, mas "Ticket médio por pedido 2024" tampouco deveria
      -- entrar numa curva de faturamento se algum dia casar.
      and fn_papel_linha(ce.chave, d.tipo_taxonomia, ce.unidade) <> 'derivado'
      and dv.id = fn_versao_com_extracao(d.id)
  ),
  somado as (
    select mes, sum(valor) as valor, count(*) as n
    from mensal where mes is not null
    group by mes
  ),
  total as (select sum(valor) as t from somado)
  select s.mes,
         case when t.t is null or t.t = 0 then null else s.valor / t.t end as fracao,
         s.n as n_observacoes
  from somado s cross join total t
  -- Só devolve curva COMPLETA: 12 meses ou nada. Curva parcial distribuiria o
  -- ano inteiro nos meses que existem, inflando cada um — pior que não ter curva.
  where (select count(*) from somado) = 12
  order by s.mes;
$$;

--
-- Name: FUNCTION fn_sazonalidade_do_caso(p_caso_id uuid); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.fn_sazonalidade_do_caso(p_caso_id uuid) IS 'Curva de sazonalidade DERIVADA do faturamento mensal do caso (0040), 12 meses ou nada. 0102: só a versão vigente do documento de faturamento — versão superada faria o mesmo mês entrar duas vezes e deslocaria a curva que reparte o valor anual no Excel.';

--
-- Name: fn_soma_secao(uuid, text[], text, text, text[], text[]); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_soma_secao(p_documento_versao_id uuid, p_termos_secao text[], p_entidade_coluna text DEFAULT NULL::text, p_periodo_coluna text DEFAULT NULL::text, p_exclui_secao text[] DEFAULT '{}'::text[], p_exclui_chave text[] DEFAULT '{}'::text[]) RETURNS TABLE(soma numeric, n_linhas integer, unidade text)
    LANGUAGE sql STABLE
    AS $$
  with folhas as (
    select ce.valor_num, ce.unidade
    from campo_extraido ce
    where ce.documento_versao_id = p_documento_versao_id
      and ce.valor_num is not null
      and ce.secao is not null
      and p_entidade_coluna is distinct from E'\x01'
      and p_periodo_coluna is distinct from E'\x01'
      and (p_entidade_coluna is null
           or fn_normalizar_texto(ce.entidade_coluna) = fn_normalizar_texto(p_entidade_coluna))
      and (p_periodo_coluna is null
           or fn_normalizar_texto(ce.periodo_coluna) = fn_normalizar_texto(p_periodo_coluna))
      and not exists (
        select 1 from unnest(p_termos_secao) as termo
        where fn_normalizar_texto(ce.secao) not like '%' || fn_normalizar_texto(termo) || '%'
      )
      and not exists (
        select 1 from unnest(p_exclui_secao) as termo
        where fn_normalizar_texto(ce.secao) like '%' || fn_normalizar_texto(termo) || '%'
      )
      and not exists (
        select 1 from unnest(p_exclui_chave) as termo
        where fn_normalizar_texto(ce.chave) like '%' || fn_normalizar_texto(termo) || '%'
      )
      and fn_normalizar_texto(ce.chave) <> fn_normalizar_texto(ce.secao)
      and fn_normalizar_texto(ce.chave) not like 'total%'
      and fn_normalizar_texto(ce.chave) not like 'subtotal%'
  )
  select coalesce(sum(valor_num), 0)::numeric,
         count(*)::int,
         (select f2.unidade from folhas f2 where f2.unidade is not null
          group by f2.unidade order by count(*) desc, f2.unidade limit 1)
  from folhas;
$$;

--
-- Name: fn_somar_conceito(uuid, text[], text[]); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_somar_conceito(p_documento_versao_id uuid, p_inclui text[], p_exclui text[] DEFAULT '{}'::text[]) RETURNS TABLE(soma numeric, n_linhas integer)
    LANGUAGE sql STABLE
    AS $$
  select coalesce(sum(ce.valor_num), 0)::numeric, count(*)::int
  from campo_extraido ce
  where ce.documento_versao_id = p_documento_versao_id
    and ce.valor_num is not null
    and not exists (
      select 1 from unnest(p_inclui) as termo
      where fn_normalizar_texto(ce.chave) not like '%' || fn_normalizar_texto(termo) || '%'
    )
    and not exists (
      select 1 from unnest(p_exclui) as termo
      where fn_normalizar_texto(ce.chave) like '%' || fn_normalizar_texto(termo) || '%'
    );
$$;

--
-- Name: fn_somar_faturamento_ano(uuid, text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_somar_faturamento_ano(p_documento_versao_id uuid, p_ano4 text, p_ano2 text) RETURNS TABLE(soma numeric, n_linhas integer)
    LANGUAGE sql STABLE
    AS $_$
  select coalesce(sum(ce.valor_num), 0)::numeric, count(*)::int
  from campo_extraido ce
  where ce.documento_versao_id = p_documento_versao_id
    and ce.valor_num is not null
    and (
      position(p_ano4 in fn_normalizar_texto(ce.chave)) > 0
      or fn_normalizar_texto(ce.chave) ~ ('[/. -]' || p_ano2 || '($|[^0-9])')
    )
    and fn_normalizar_texto(ce.chave) not like '%total%'
    and fn_normalizar_texto(ce.chave) not like '%acumulad%'
    and fn_normalizar_texto(ce.chave) not like '%media%'
    and fn_normalizar_texto(ce.chave) not like '%médi%';
$_$;

--
-- Name: fn_tem_palavra_longa(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_tem_palavra_longa(p_chave text) RETURNS boolean
    LANGUAGE sql IMMUTABLE
    AS $$
  select exists (
    select 1
    from unnest(regexp_split_to_array(
      regexp_replace(fn_normalizar_texto(p_chave), '[^a-z0-9]+', ' ', 'g'), '\s+')) as w
    where length(w) >= 4
  );
$$;

--
-- Name: FUNCTION fn_tem_palavra_longa(p_chave text); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.fn_tem_palavra_longa(p_chave text) IS 'O rótulo tem ao menos uma palavra de 4+ letras? Metade da regra de fn_rotulo_contido: sem isto, "de" contido em qualquer coisa marcaria sobreposição em toda linha.';

--
-- Name: fn_teto_ressalvas(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_teto_ressalvas() RETURNS integer
    LANGUAGE sql IMMUTABLE
    AS $$ select 3; $$;

--
-- Name: FUNCTION fn_teto_ressalvas(); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.fn_teto_ressalvas() IS 'Teto de pendências aceitas com ressalva ATIVAS por caso. 3 é o valor que o dono confirmou em f0/04 ("Teto de ressalvas confirmado em 3") — não é palpite deste código.';

--
-- Name: fn_tokens_estruturais(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_tokens_estruturais(p_chave text) RETURNS text[]
    LANGUAGE sql IMMUTABLE
    AS $$
  select coalesce((
    select array_agg(distinct w order by w)
    from unnest(
      regexp_split_to_array(
        regexp_replace(fn_normalizar_texto(p_chave), '[^a-z0-9]+', ' ', 'g'),
        '\s+')
    ) as w
    where w <> ''
      and w not in ('total','totais','geral','gerais','soma','somatorio','subtotal',
                    'de','do','da','dos','das','e','o','a','os','as','em','no','na',
                    'liquido','liquida','consolidado','consolidada','combinado','combinada')
  ), array[]::text[]);
$$;

--
-- Name: FUNCTION fn_tokens_estruturais(p_chave text); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.fn_tokens_estruturais(p_chave text) IS 'Palavras estruturais de um rótulo (sem ligação, ruído de rodapé e a palavra "total"), ordenadas e sem repetição. Extraída de fn_rotulo_estrutural na 0102 para ser calculada UMA vez por rótulo: fn_papel_linha comparava nove grupos e pagava nove tokenizações iguais.';

--
-- Name: fn_unidade_predominante(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_unidade_predominante(p_documento_versao_id uuid) RETURNS text
    LANGUAGE sql STABLE
    AS $$
  select ce.unidade
  from campo_extraido ce
  where ce.documento_versao_id = p_documento_versao_id
    and ce.unidade is not null
    and length(trim(ce.unidade)) > 0
  group by ce.unidade
  order by count(*) desc, ce.unidade
  limit 1;
$$;

--
-- Name: FUNCTION fn_unidade_predominante(p_documento_versao_id uuid); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.fn_unidade_predominante(p_documento_versao_id uuid) IS 'Escala predominante (unidade) das linhas extraídas de uma versão de documento; null quando nenhuma linha declara escala.';

--
-- Name: fn_upsert_caso(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_upsert_caso(p_nome text) RETURNS uuid
    LANGUAGE plpgsql
    AS $$
declare
  v_id uuid;
begin
  select id into v_id from caso where nome = p_nome limit 1;
  if v_id is null then
    insert into caso (nome) values (p_nome) returning id into v_id;
    insert into evento_auditoria (ator, acao, entidade_ref, depois)
      values ('sistema:n8n', 'caso_criado', 'caso:'||v_id, jsonb_build_object('nome', p_nome));
  end if;
  return v_id;
end;
$$;

--
-- Name: fn_upsert_entidade(uuid, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_upsert_entidade(p_caso_id uuid, p_nome text) RETURNS uuid
    LANGUAGE plpgsql
    AS $$
declare v_id uuid;
begin
  if p_nome is null or length(trim(p_nome)) = 0 then return null; end if;

  -- Casa pela forma CANÔNICA: é o que impede "Vertentes Metalurgica" (do nome do
  -- arquivo, sem acento) e "Vertentes Metalúrgica Ltda." (do diagnóstico) de virarem
  -- duas empresas. Ordena por criado_em para ser determinístico quando a base já
  -- tem duplicata de antes desta migration.
  select e.id into v_id
  from entidade e
  where e.caso_id = p_caso_id and fn_mesma_entidade(e.razao_social, p_nome)
  -- `entidade` não tem coluna de data; ordenar pela razão social torna a escolha
  -- DETERMINÍSTICA quando a base já carrega duplicata de antes desta migration.
  -- Sem ordem explícita, dois documentos do mesmo lote poderiam se ligar a linhas
  -- diferentes da mesma empresa — a duplicidade sobreviveria à própria correção.
  order by e.razao_social
  limit 1;

  if v_id is null then
    insert into entidade (caso_id, razao_social) values (p_caso_id, trim(p_nome))
      returning id into v_id;
  end if;
  return v_id;
end;
$$;

--
-- Name: FUNCTION fn_upsert_entidade(p_caso_id uuid, p_nome text); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.fn_upsert_entidade(p_caso_id uuid, p_nome text) IS 'Acha ou cria a entidade casando pela forma canônica (0030). Impede duplicata quando o nome vem do arquivo (sem acento) e do diagnóstico (com acento e sufixo).';

--
-- Name: fn_upsert_periodo(uuid, text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_upsert_periodo(p_caso_id uuid, p_tipo text, p_ref text) RETURNS uuid
    LANGUAGE plpgsql
    AS $$
declare
  v_id  uuid;
  v_can text;
begin
  if p_ref is null or length(trim(p_ref)) = 0 then return null; end if;
  v_can := fn_periodo_canonico(coalesce(p_tipo, 'outro'), p_ref);

  -- Casa por forma CANÔNICA: '2025' e '12M25' são o mesmo exercício e não podem
  -- virar duas linhas. A 0022 já canonicalizava na comparação; aqui é na ESCRITA,
  -- que é o que faz o dashboard, o checklist e o export verem um período só.
  select p.id into v_id
  from periodo p
  where p.caso_id = p_caso_id
    and fn_periodo_canonico(p.tipo, p.referencia) = v_can
  order by p.referencia
  limit 1;

  if v_id is null then
    insert into periodo (caso_id, tipo, referencia)
      values (p_caso_id, coalesce(p_tipo, 'outro'), trim(p_ref))
      returning id into v_id;
  end if;
  return v_id;
end;
$$;

--
-- Name: FUNCTION fn_upsert_periodo(p_caso_id uuid, p_tipo text, p_ref text); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.fn_upsert_periodo(p_caso_id uuid, p_tipo text, p_ref text) IS 'Acha ou cria o período casando pela forma canônica (0030). Impede que 2025 e 12M25 virem dois exercícios.';

--
-- Name: campo_extraido; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.campo_extraido (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    documento_versao_id uuid NOT NULL,
    chave text NOT NULL,
    valor_texto text,
    valor_num numeric,
    unidade text,
    confianca numeric,
    origem_pagina integer,
    origem_linha text,
    nivel_autonomia public.nivel_autonomia DEFAULT 'N0'::public.nivel_autonomia NOT NULL,
    revisado_por text,
    criado_em timestamp with time zone DEFAULT now() NOT NULL,
    secao text,
    status_aceite text DEFAULT 'pendente'::text NOT NULL,
    aceito_por text,
    aceito_em timestamp with time zone,
    secao_canonica text,
    entidade_coluna text,
    periodo_coluna text,
    ordem integer,
    moeda text,
    CONSTRAINT campo_extraido_status_aceite_check CHECK ((status_aceite = ANY (ARRAY['pendente'::text, 'aceito'::text, 'com_ressalva'::text])))
);

--
-- Name: COLUMN campo_extraido.secao; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.campo_extraido.secao IS 'Agrupador de planilha extraído pela IA (espelha a estrutura do documento original). Livre, não é enum.';

--
-- Name: COLUMN campo_extraido.status_aceite; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.campo_extraido.status_aceite IS 'Portão 2 (E4, f0/07): pendente = sugestão N0/N1, não é fato; aceito = decisao humana ligada, entra no export como fato; com_ressalva = aceito com ressalva.';

--
-- Name: COLUMN campo_extraido.secao_canonica; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.campo_extraido.secao_canonica IS 'Seção canônica SUGERIDA pela IA na extração (E2), pelo significado contábil da conta. Chaves = as de statement-templates.ts (ativo_circulante, dre custos, atividades_investimento, etc.). N1/advisory: usada só como fallback do classificador determinístico do export; nunca vira fato sem aceite humano.';

--
-- Name: COLUMN campo_extraido.entidade_coluna; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.campo_extraido.entidade_coluna IS 'Nome da coluna/entidade a que esta linha pertence, quando o documento traz várias entidades lado a lado na mesma tabela (ex.: balanço combinado "Empresa A | Empresa B | Total"). Null quando o documento é de uma entidade só (caso comum) — não confundir com documento.entidade_id, que segue sendo a entidade PRINCIPAL do documento como um todo.';

--
-- Name: COLUMN campo_extraido.periodo_coluna; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.campo_extraido.periodo_coluna IS 'Rótulo da coluna de período a que esta linha pertence, quando o documento é comparativo e traz vários períodos lado a lado na mesma tabela (ex.: "2023" e "2024"). Null quando o documento é de período único (caso comum) — aí o período vem de documento.periodo_id. Ortogonal a entidade_coluna: um documento pode ter as duas dimensões (várias empresas E vários anos).';

--
-- Name: COLUMN campo_extraido.ordem; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.campo_extraido.ordem IS 'Posição 0-based da linha no documento, como o arquivo a imprime. Permite reconhecer subtotal impresso acima dos seus componentes (teste v28). null em extração feita antes da 0027.';

--
-- Name: COLUMN campo_extraido.moeda; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.campo_extraido.moeda IS 'Moeda ISO da linha (BRL/USD/EUR/…), herdada do documento pela extração; null = desconhecida, NUNCA presumida. Separada de `unidade`, que é a ESCALA (milhar/unidade). Somar linhas de moedas diferentes é erro pelo câmbio inteiro — ver o cabeçalho da 0035.';

--
-- Name: fn_valor_conceito(uuid, text[], text[]); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_valor_conceito(p_documento_versao_id uuid, p_inclui text[], p_exclui text[] DEFAULT '{}'::text[]) RETURNS public.campo_extraido
    LANGUAGE sql STABLE
    AS $$
  select ce.*
  from campo_extraido ce
  where ce.documento_versao_id = p_documento_versao_id
    and ce.valor_num is not null
    and not exists (
      select 1 from unnest(p_inclui) as termo
      where fn_normalizar_texto(ce.chave) not like '%' || fn_normalizar_texto(termo) || '%'
    )
    and not exists (
      select 1 from unnest(p_exclui) as termo
      where fn_normalizar_texto(ce.chave) like '%' || fn_normalizar_texto(termo) || '%'
    )
  order by coalesce(ce.confianca, 0) desc, length(ce.chave) asc
  limit 1;
$$;

--
-- Name: fn_valor_conceito_col(uuid, text[], text[], text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_valor_conceito_col(p_documento_versao_id uuid, p_inclui text[], p_exclui text[] DEFAULT '{}'::text[], p_entidade_coluna text DEFAULT NULL::text, p_periodo_coluna text DEFAULT NULL::text) RETURNS public.campo_extraido
    LANGUAGE sql STABLE
    AS $$
  select ce.*
  from campo_extraido ce
  where ce.documento_versao_id = p_documento_versao_id
    and ce.valor_num is not null
    and p_entidade_coluna is distinct from E'\x01'
    and p_periodo_coluna is distinct from E'\x01'
    and (p_entidade_coluna is null
         or fn_normalizar_texto(ce.entidade_coluna) = fn_normalizar_texto(p_entidade_coluna))
    and (p_periodo_coluna is null
         or fn_normalizar_texto(ce.periodo_coluna) = fn_normalizar_texto(p_periodo_coluna))
    and not exists (
      select 1 from unnest(p_inclui) as termo
      where fn_normalizar_texto(ce.chave) not like '%' || fn_normalizar_texto(termo) || '%'
    )
    and not exists (
      select 1 from unnest(p_exclui) as termo
      where fn_normalizar_texto(ce.chave) like '%' || fn_normalizar_texto(termo) || '%'
    )
  order by coalesce(ce.confianca, 0) desc, length(ce.chave) asc
  limit 1;
$$;

--
-- Name: fn_valor_conceito_secao(uuid, text[], text[], text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_valor_conceito_secao(p_documento_versao_id uuid, p_inclui text[], p_exclui text[] DEFAULT '{}'::text[], p_entidade_coluna text DEFAULT NULL::text, p_periodo_coluna text DEFAULT NULL::text) RETURNS public.campo_extraido
    LANGUAGE sql STABLE
    AS $$
  select ce.*
  from campo_extraido ce
  where ce.documento_versao_id = p_documento_versao_id
    and ce.valor_num is not null
    and ce.secao is not null
    and p_entidade_coluna is distinct from E'\x01'
    and p_periodo_coluna is distinct from E'\x01'
    and (p_entidade_coluna is null
         or fn_normalizar_texto(ce.entidade_coluna) = fn_normalizar_texto(p_entidade_coluna))
    and (p_periodo_coluna is null
         or fn_normalizar_texto(ce.periodo_coluna) = fn_normalizar_texto(p_periodo_coluna))
    and not exists (
      select 1 from unnest(p_inclui) as termo
      where fn_normalizar_texto(ce.secao) not like '%' || fn_normalizar_texto(termo) || '%'
    )
    -- O EXCLUI olha os dois: seção que casou não salva um rótulo que o exclui
    -- proíbe (ex.: seção "Disponível" com rótulo "Total do Ativo Circulante").
    and not exists (
      select 1 from unnest(p_exclui) as termo
      where fn_normalizar_texto(ce.secao) like '%' || fn_normalizar_texto(termo) || '%'
         or fn_normalizar_texto(ce.chave) like '%' || fn_normalizar_texto(termo) || '%'
    )
  order by coalesce(ce.confianca, 0) desc, length(ce.chave) asc
  limit 1;
$$;

--
-- Name: FUNCTION fn_valor_conceito_secao(p_documento_versao_id uuid, p_inclui text[], p_exclui text[], p_entidade_coluna text, p_periodo_coluna text); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.fn_valor_conceito_secao(p_documento_versao_id uuid, p_inclui text[], p_exclui text[], p_entidade_coluna text, p_periodo_coluna text) IS 'Como fn_valor_conceito_col, mas casa contra ce.secao. Fallback para rótulo que não nomeia o conceito ("Bancos Conta Movimento" debaixo de "Disponível") — 0031.';

--
-- Name: fn_valor_em_base(numeric, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_valor_em_base(p_valor numeric, p_unidade text) RETURNS numeric
    LANGUAGE sql IMMUTABLE
    AS $$
  select p_valor * coalesce(fn_fator_escala(p_unidade), 1);
$$;

--
-- Name: fn_valor_estrutural_col(uuid, text[], text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_valor_estrutural_col(p_documento_versao_id uuid, p_tokens text[], p_entidade_coluna text DEFAULT NULL::text, p_periodo_coluna text DEFAULT NULL::text) RETURNS public.campo_extraido
    LANGUAGE sql STABLE
    AS $$
  select ce.*
  from campo_extraido ce
  where ce.documento_versao_id = p_documento_versao_id
    and ce.valor_num is not null
    and p_entidade_coluna is distinct from E'\x01'
    and p_periodo_coluna is distinct from E'\x01'
    and (p_entidade_coluna is null
         or fn_normalizar_texto(ce.entidade_coluna) = fn_normalizar_texto(p_entidade_coluna))
    and (p_periodo_coluna is null
         or fn_normalizar_texto(ce.periodo_coluna) = fn_normalizar_texto(p_periodo_coluna))
    and fn_rotulo_estrutural(ce.chave, p_tokens)
  -- Se houver mais de um (o cabeçalho do grupo E o rodapé "TOTAL DO ..."), o
  -- de MAIOR rótulo vem primeiro: é o rodapé, a linha conferida do documento.
  order by coalesce(ce.confianca, 0) desc, length(ce.chave) desc
  limit 1;
$$;

--
-- Name: fn_valores_por_ano(uuid, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_valores_por_ano(p_caso_id uuid, p_entidade text DEFAULT NULL::text) RETURNS TABLE(rotulo_norm text, secao_canonica text, ano integer, valor numeric, n_ocorrencias bigint)
    LANGUAGE sql STABLE
    AS $$
  -- marca-0102
  with ocorrencias as (
    select
      fn_normalizar_texto(ce.chave) as rotulo_norm,
      ce.secao_canonica,
      fn_ano_da_coluna(ce.periodo_coluna, p.referencia) as ano,
      ce.valor_num as valor
    from campo_extraido ce
    join documento_versao dv on dv.id = ce.documento_versao_id
    join documento d on d.id = dv.documento_id
    left join periodo p on p.id = d.periodo_id
    left join entidade e on e.id = d.entidade_id
    where d.caso_id = p_caso_id
      and ce.valor_num is not null
      and (p_entidade is null
           or fn_mesma_entidade(coalesce(ce.entidade_coluna, e.razao_social, ''), p_entidade))
      and dv.id = fn_versao_com_extracao(d.id)
  )
  select o.rotulo_norm, o.secao_canonica, o.ano,
         -- Maior módulo COM SINAL, igual à 0042. Duas grafias da mesma conta no
         -- mesmo exercício não somam: representam o mesmo saldo.
         (array_agg(o.valor order by abs(o.valor) desc))[1] as valor,
         count(*) as n_ocorrencias
  from ocorrencias o
  where o.ano is not null
  group by o.rotulo_norm, o.secao_canonica, o.ano
  order by o.rotulo_norm, o.ano;
$$;

--
-- Name: FUNCTION fn_valores_por_ano(p_caso_id uuid, p_entidade text); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.fn_valores_por_ano(p_caso_id uuid, p_entidade text) IS 'O valor de cada linha lógica por exercício — é a fonte dos números do .xlsx entregue. O filtro de entidade não é opcional (0044). 0102: só a versão vigente de cada documento, senão uma ocorrência superada de módulo maior vence a corrigida e sai no entregável.';

--
-- Name: fn_versao_atual(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_versao_atual(p_documento_id uuid) RETURNS uuid
    LANGUAGE sql STABLE
    AS $$
  select id from documento_versao where documento_id = p_documento_id order by n_versao desc limit 1;
$$;

--
-- Name: fn_versao_com_extracao(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_versao_com_extracao(p_documento_id uuid) RETURNS uuid
    LANGUAGE sql STABLE
    AS $$
  -- marca-0102
  select dv.id
  from documento_versao dv
  where dv.documento_id = p_documento_id
    and exists (select 1 from campo_extraido ce where ce.documento_versao_id = dv.id)
  order by dv.n_versao desc
  limit 1;
$$;

--
-- Name: FUNCTION fn_versao_com_extracao(p_documento_id uuid); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.fn_versao_com_extracao(p_documento_id uuid) IS 'A documento_versao VIGENTE para quem lê conteúdo: a de maior n_versao que TEM campo_extraido. Difere de fn_versao_atual (max(n_versao)) de propósito: entre fn_registrar_documento e fn_registrar_campos_extraidos a versão mais recente está vazia, e max(n_versao) puro deixaria a tela de Modelagem em branco nessa janela — o mesmo sintoma que a 0101 corrigiu.';

--
-- Name: fn_vincular_linha_premissa(uuid, text, text, text, text, text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_vincular_linha_premissa(p_caso_id uuid, p_secao_canonica text, p_rotulo text, p_entidade text, p_premissa text, p_autor text, p_sazonalidade text DEFAULT NULL::text) RETURNS jsonb
    LANGUAGE plpgsql
    AS $$
declare
  v_rotulo_norm text := fn_normalizar_texto(p_rotulo);
  v_papel text;
begin
  -- Papel primeiro (0042). Desvincular (premissa null) é SEMPRE permitido: limpar
  -- configuração antiga não pode ser bloqueado pela regra nova.
  if p_premissa is not null then
    v_papel := fn_papel_do_rotulo_no_caso(p_caso_id, v_rotulo_norm, p_secao_canonica);
    if v_papel is not null and v_papel <> 'conta' then
      return jsonb_build_object('recusado', true, 'papel', v_papel,
        'motivo_recusa', case v_papel
          when 'subtotal' then
            format('"%s" é um SUBTOTAL — já é a soma de outras linhas. No Excel ele sai como a '
                   'soma dos componentes projetados, então se move sozinho; projetá-lo por '
                   'premissa própria contaria o mesmo dinheiro duas vezes.', p_rotulo)
          when 'serie_mensal' then
            format('"%s" é uma linha da SÉRIE MENSAL de faturamento — ela alimenta a curva de '
                   'sazonalidade (que sai do próprio histórico do caso), não é uma conta a '
                   'projetar. Projetá-la contaria a receita de novo, mês a mês.', p_rotulo)
          else
            format('"%s" é um indicador DERIVADO (resultado de outras contas, não dinheiro). '
                   'Projetá-lo por premissa própria o faria divergir das linhas que o compõem.',
                   p_rotulo)
        end);
    end if;
  end if;

  if p_premissa is not null and not exists (
    select 1 from caso_premissa where caso_id = p_caso_id and premissa_codigo = p_premissa and ativo
  ) then
    return jsonb_build_object('recusado', true, 'escopo', 'premissa',
      'motivo_recusa', format('A premissa "%s" não está ATIVA neste caso. Ative-a (com valores) '
                              'antes de vincular linha — senão a linha sairia "projetada" por uma '
                              'premissa vazia, o que é projetar com zero.', p_premissa));
  end if;
  if p_sazonalidade is not null and not exists (
    select 1 from caso_premissa where caso_id = p_caso_id and premissa_codigo = p_sazonalidade and ativo
  ) then
    return jsonb_build_object('recusado', true, 'escopo', 'premissa',
      'motivo_recusa', format('A sazonalidade "%s" não está ativa neste caso.', p_sazonalidade));
  end if;

  insert into caso_linha_premissa (caso_id, secao_canonica, rotulo_norm, entidade,
                                   premissa_codigo, sazonalidade_codigo, atualizado_por, atualizado_em)
    values (p_caso_id, p_secao_canonica, v_rotulo_norm, p_entidade, p_premissa, p_sazonalidade, p_autor, now())
  on conflict (caso_id, rotulo_norm, coalesce(entidade, ''), coalesce(secao_canonica, '')) do update
    set premissa_codigo = excluded.premissa_codigo,
        sazonalidade_codigo = excluded.sazonalidade_codigo,
        atualizado_por = excluded.atualizado_por, atualizado_em = now();

  return jsonb_build_object('caso_id', p_caso_id, 'rotulo', v_rotulo_norm, 'premissa', p_premissa);
end;
$$;

--
-- Name: caso; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.caso (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    nome text NOT NULL,
    produto text DEFAULT 'reestruturacao'::text NOT NULL,
    status public.caso_status DEFAULT 'intake'::public.caso_status NOT NULL,
    criado_em timestamp with time zone DEFAULT now() NOT NULL
);

--
-- Name: caso_linha_premissa; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.caso_linha_premissa (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    caso_id uuid NOT NULL,
    secao_canonica text,
    rotulo_norm text NOT NULL,
    entidade text,
    premissa_codigo text,
    sazonalidade_codigo text,
    atualizado_por text,
    atualizado_em timestamp with time zone DEFAULT now() NOT NULL
);

--
-- Name: caso_modelagem; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.caso_modelagem (
    caso_id uuid NOT NULL,
    entidade text,
    ultimo_exercicio_real integer,
    indice_macro text,
    setor text,
    anos_projetados integer DEFAULT 5 NOT NULL,
    atualizado_por text,
    atualizado_em timestamp with time zone DEFAULT now() NOT NULL
);

--
-- Name: caso_premissa; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.caso_premissa (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    caso_id uuid NOT NULL,
    premissa_codigo text NOT NULL,
    valores jsonb DEFAULT '{}'::jsonb NOT NULL,
    origem text,
    ativo boolean DEFAULT true NOT NULL,
    atualizado_por text,
    atualizado_em timestamp with time zone DEFAULT now() NOT NULL
);

--
-- Name: checklist_item_status; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.checklist_item_status (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    caso_id uuid NOT NULL,
    entidade_id uuid,
    periodo_id uuid,
    tipo_taxonomia text NOT NULL,
    obrigatoriedade public.obrigatoriedade NOT NULL,
    status text DEFAULT 'faltante'::text NOT NULL,
    documento_id uuid,
    atualizado_em timestamp with time zone DEFAULT now() NOT NULL
);

--
-- Name: decisao; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.decisao (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    caso_id uuid NOT NULL,
    tipo public.decisao_tipo NOT NULL,
    autor text NOT NULL,
    criado_em timestamp with time zone DEFAULT now() NOT NULL,
    motivo text,
    payload jsonb
);

--
-- Name: documento; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.documento (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    caso_id uuid NOT NULL,
    entidade_id uuid,
    periodo_id uuid,
    tipo_taxonomia text,
    status public.documento_status DEFAULT 'recebido'::public.documento_status NOT NULL,
    sensibilidade_lgpd public.sensibilidade_lgpd DEFAULT 'nenhuma'::public.sensibilidade_lgpd NOT NULL,
    criado_em timestamp with time zone DEFAULT now() NOT NULL,
    confianca numeric,
    fonte text,
    justificativa text,
    resumo text
);

--
-- Name: COLUMN documento.confianca; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.documento.confianca IS 'Confiança da classificação atual (nome-do-arquivo/IA/humano). 1.0 quando confirmado por humano.';

--
-- Name: COLUMN documento.fonte; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.documento.fonte IS 'Origem da classificação atual: nome_arquivo | openai_conteudo | humano.';

--
-- Name: COLUMN documento.justificativa; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.documento.justificativa IS 'Explicação objetiva da classificação atual (da IA na origem, ou motivo informado na revisão humana).';

--
-- Name: COLUMN documento.resumo; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.documento.resumo IS 'Resumo objetivo (2-3 frases) do conteúdo do documento, gerado no diagnóstico (E2).';

--
-- Name: documento_versao; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.documento_versao (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    documento_id uuid NOT NULL,
    n_versao integer DEFAULT 1 NOT NULL,
    origem_arquivo public.origem_arquivo DEFAULT 'supabase_storage'::public.origem_arquivo NOT NULL,
    arquivo_ref text NOT NULL,
    nome_original text,
    assinado boolean,
    hash text,
    legibilidade public.legibilidade,
    criada_em timestamp with time zone DEFAULT now() NOT NULL,
    nota_legibilidade text
);

--
-- Name: COLUMN documento_versao.nota_legibilidade; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.documento_versao.nota_legibilidade IS 'Motivo objetivo quando legibilidade != ok (ex.: páginas faltando, digitalização ruim).';

--
-- Name: entidade; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.entidade (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    caso_id uuid NOT NULL,
    razao_social text NOT NULL,
    cnpj text,
    papel_no_grupo text
);

--
-- Name: estagio_autonomia; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.estagio_autonomia (
    estagio text NOT NULL,
    nivel_atual public.nivel_autonomia NOT NULL,
    teto public.nivel_autonomia NOT NULL,
    atualizado_por text,
    atualizado_em timestamp with time zone DEFAULT now() NOT NULL,
    limiar_auto_clear numeric DEFAULT 0.95
);

--
-- Name: TABLE estagio_autonomia; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.estagio_autonomia IS 'O "dial" de autonomia por estágio. Nível é estado do sistema, não constante de código (docs/01).';

--
-- Name: COLUMN estagio_autonomia.limiar_auto_clear; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.estagio_autonomia.limiar_auto_clear IS 'Confiança mínima para auto-aceite quando o estágio está em N2/N3. Era 0.95 HARDCODED em fn_registrar_campos_extraidos (0019); virou dado na 0041 para poder ser ajustado sem migration. Null = não auto-aceita, independentemente do nível.';

--
-- Name: evento_auditoria; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.evento_auditoria (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    criado_em timestamp with time zone DEFAULT now() NOT NULL,
    ator text NOT NULL,
    acao text NOT NULL,
    entidade_ref text,
    antes jsonb,
    depois jsonb
);

--
-- Name: execucao_falha; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.execucao_falha (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    caso_id uuid,
    caso_nome text,
    etapa text NOT NULL,
    mensagem text NOT NULL,
    detalhe jsonb,
    criado_em timestamp with time zone DEFAULT now() NOT NULL,
    visto_em timestamp with time zone,
    visto_por text
);

--
-- Name: TABLE execucao_falha; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.execucao_falha IS 'Falha do pipeline (n8n) que a TELA precisa mostrar. Existe porque o portal deduzia progresso de sinais positivos, e falha produz ausência — indistinguível de "ainda processando". Tabela própria e não evento_auditoria: isto é estado operacional que se marca como visto, não trilha.';

--
-- Name: indice_macro_expectativa; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.indice_macro_expectativa (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    serie text NOT NULL,
    fonte text DEFAULT 'BCB/Focus'::text NOT NULL,
    ano_ref integer NOT NULL,
    mediana numeric NOT NULL,
    media numeric,
    respondentes integer,
    coletado_em date NOT NULL,
    registrado_em timestamp with time zone DEFAULT now() NOT NULL
);

--
-- Name: indice_macro_obs; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.indice_macro_obs (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    serie text NOT NULL,
    fonte text NOT NULL,
    data_ref date NOT NULL,
    valor numeric NOT NULL,
    coletado_em timestamp with time zone DEFAULT now() NOT NULL
);

--
-- Name: indice_macro_serie; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.indice_macro_serie (
    codigo text NOT NULL,
    nome text NOT NULL,
    natureza text NOT NULL,
    unidade text NOT NULL,
    descricao text,
    criado_em timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT indice_macro_serie_natureza_check CHECK ((natureza = ANY (ARRAY['taxa'::text, 'nivel'::text])))
);

--
-- Name: COLUMN indice_macro_serie.natureza; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.indice_macro_serie.natureza IS 'taxa = variação % do mês (o ano acumula por COMPOSIÇÃO); nivel = preço/estoque na data (o ano é o fechamento). Compor nível, ou somar taxa, é erro conceitual.';

--
-- Name: pendencia; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.pendencia (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    caso_id uuid NOT NULL,
    origem_estagio text,
    tipo public.pendencia_tipo NOT NULL,
    severidade public.pendencia_severidade NOT NULL,
    estado public.pendencia_estado DEFAULT 'aberta'::public.pendencia_estado NOT NULL,
    descricao text,
    documento_id uuid,
    entidade_id uuid,
    periodo_id uuid,
    sobrepujavel boolean DEFAULT true NOT NULL,
    expira_em timestamp with time zone,
    motivo text,
    criada_em timestamp with time zone DEFAULT now() NOT NULL,
    resolvida_em timestamp with time zone,
    resolvida_por text
);

--
-- Name: periodo; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.periodo (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    caso_id uuid NOT NULL,
    tipo text NOT NULL,
    referencia text NOT NULL
);

--
-- Name: reconciliacao; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.reconciliacao (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    caso_id uuid NOT NULL,
    entidade_id uuid,
    periodo_id uuid,
    tipo text NOT NULL,
    classe text DEFAULT 'A'::text NOT NULL,
    fonte_a jsonb,
    fonte_b jsonb,
    precondicoes_ok boolean NOT NULL,
    resultado text NOT NULL,
    divergencia_abs numeric,
    divergencia_pct numeric,
    materialidade jsonb,
    criado_em timestamp with time zone DEFAULT now() NOT NULL
);

--
-- Name: taxonomia_linha_exigida; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.taxonomia_linha_exigida (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    tipo_taxonomia text NOT NULL,
    conceito text NOT NULL,
    rotulo text NOT NULL,
    checagem text NOT NULL,
    secao_canonica text,
    origem text NOT NULL,
    depende_de text[] DEFAULT '{}'::text[] NOT NULL,
    descricao text NOT NULL,
    severidade text,
    sobrepujavel boolean,
    ativo boolean DEFAULT true NOT NULL,
    versao integer DEFAULT 1 NOT NULL,
    CONSTRAINT taxonomia_linha_exigida_checagem_check CHECK ((checagem = ANY (ARRAY['linha_por_termos'::text, 'secao_presente'::text, 'serie_mensal'::text]))),
    CONSTRAINT taxonomia_linha_exigida_check CHECK (((checagem <> 'secao_presente'::text) OR (secao_canonica IS NOT NULL))),
    CONSTRAINT taxonomia_linha_exigida_origem_check CHECK ((origem = ANY (ARRAY['codigo'::text, 'proposta'::text]))),
    CONSTRAINT taxonomia_linha_exigida_severidade_check CHECK ((severidade = ANY (ARRAY['bloqueante'::text, 'importante'::text])))
);

--
-- Name: TABLE taxonomia_linha_exigida; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.taxonomia_linha_exigida IS 'Linhas/seções que um tipo de documento PRECISA ter para ser utilizável (entrega aprovada, sessão de 13/08/2026). Filha da taxonomia: a taxonomia diz QUAIS tipos são obrigatórios; esta diz O QUE cada tipo precisa conter. Lida pelo Portão 1 (fn_recomputar_completude, passo 2b).';

--
-- Name: COLUMN taxonomia_linha_exigida.checagem; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.taxonomia_linha_exigida.checagem IS 'linha_por_termos = existe linha casando algum localizador; secao_presente = existe linha com a secao_canonica; serie_mensal = existe linha cujo rótulo tem mês (fn_mes_do_rotulo, 0042).';

--
-- Name: COLUMN taxonomia_linha_exigida.origem; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.taxonomia_linha_exigida.origem IS '''codigo'' = a exigência JÁ está hardcoded numa reconciliação vigente (termos copiados literalmente de 0009/0023/0031/0034); ''proposta'' = saiu da análise do estagiário e NENHUMA checagem a lê hoje. Distinção para o revisor ver a diferença sem abrir o documento da entrega.';

--
-- Name: COLUMN taxonomia_linha_exigida.depende_de; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.taxonomia_linha_exigida.depende_de IS 'FATO, não política: qual reconciliação/indicador deixa de funcionar sem esta linha. Insumo para o dono definir severidade linha a linha.';

--
-- Name: COLUMN taxonomia_linha_exigida.severidade; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.taxonomia_linha_exigida.severidade IS 'DECISÃO DO DONO, por linha. NULL = ainda não decidida; o Portão 1 usa então ''importante'' — o mesmo peso que a ausência já tem hoje via precondicao_nao_satisfeita. A migration não endurece nada sozinha.';

--
-- Name: COLUMN taxonomia_linha_exigida.sobrepujavel; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.taxonomia_linha_exigida.sobrepujavel IS 'DECISÃO DO DONO, por linha. NULL = ainda não decidida; o Portão 1 usa então TRUE (sobrepujável, como a precondicao_nao_satisfeita de hoje).';

--
-- Name: taxonomia_linha_localizador; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.taxonomia_linha_localizador (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    exigencia_id uuid NOT NULL,
    ordem integer NOT NULL,
    contra text DEFAULT 'chave'::text NOT NULL,
    termos_inclui text[] NOT NULL,
    termos_exclui text[] DEFAULT '{}'::text[] NOT NULL,
    CONSTRAINT taxonomia_linha_localizador_contra_check CHECK ((contra = ANY (ARRAY['chave'::text, 'secao'::text, 'estrutural'::text])))
);

--
-- Name: TABLE taxonomia_linha_localizador; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.taxonomia_linha_localizador IS 'Tentativas de localização de uma exigência, em cascata (a ordem espelha o código: o caixa do BP tem 7 tentativas na 0031). Formato de fn_valor_conceito (0009): inclui/exclui por substring do texto normalizado. A exigência satisfaz-se quando QUALQUER localizador casa.';

--
-- Name: COLUMN taxonomia_linha_localizador.contra; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.taxonomia_linha_localizador.contra IS '''chave'' = casa contra ce.chave (fn_valor_conceito); ''secao'' = contra ce.secao (fn_valor_conceito_secao, 0031); ''estrutural'' = fn_rotulo_estrutural(ce.chave, termos_inclui) (0034 — igualdade de tokens estruturais; termos_exclui não se aplica).';

--
-- Name: taxonomia_tipo_documento; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.taxonomia_tipo_documento (
    codigo text NOT NULL,
    categoria text NOT NULL,
    documento text NOT NULL,
    obrigatoriedade public.obrigatoriedade NOT NULL,
    granularidade public.granularidade NOT NULL,
    vigencia text,
    sensibilidade public.sensibilidade_lgpd DEFAULT 'nenhuma'::public.sensibilidade_lgpd NOT NULL,
    versao integer DEFAULT 1 NOT NULL,
    ativo boolean DEFAULT true NOT NULL,
    nao_sobrepujavel boolean DEFAULT false NOT NULL
);

--
-- Name: TABLE taxonomia_tipo_documento; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.taxonomia_tipo_documento IS 'Taxonomia documental v1 (f0/03). Kit Básico = obrigatorio; Variáveis = complementar.';

--
-- Name: campo_extraido campo_extraido_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.campo_extraido
    ADD CONSTRAINT campo_extraido_pkey PRIMARY KEY (id);

--
-- Name: caso_linha_premissa caso_linha_premissa_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.caso_linha_premissa
    ADD CONSTRAINT caso_linha_premissa_pkey PRIMARY KEY (id);

--
-- Name: caso_modelagem caso_modelagem_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.caso_modelagem
    ADD CONSTRAINT caso_modelagem_pkey PRIMARY KEY (caso_id);

--
-- Name: caso caso_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.caso
    ADD CONSTRAINT caso_pkey PRIMARY KEY (id);

--
-- Name: caso_premissa caso_premissa_caso_id_premissa_codigo_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.caso_premissa
    ADD CONSTRAINT caso_premissa_caso_id_premissa_codigo_key UNIQUE (caso_id, premissa_codigo);

--
-- Name: caso_premissa caso_premissa_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.caso_premissa
    ADD CONSTRAINT caso_premissa_pkey PRIMARY KEY (id);

--
-- Name: checklist_item_status checklist_item_status_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.checklist_item_status
    ADD CONSTRAINT checklist_item_status_pkey PRIMARY KEY (id);

--
-- Name: decisao decisao_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.decisao
    ADD CONSTRAINT decisao_pkey PRIMARY KEY (id);

--
-- Name: documento documento_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.documento
    ADD CONSTRAINT documento_pkey PRIMARY KEY (id);

--
-- Name: documento_versao documento_versao_documento_id_n_versao_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.documento_versao
    ADD CONSTRAINT documento_versao_documento_id_n_versao_key UNIQUE (documento_id, n_versao);

--
-- Name: documento_versao documento_versao_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.documento_versao
    ADD CONSTRAINT documento_versao_pkey PRIMARY KEY (id);

--
-- Name: entidade entidade_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.entidade
    ADD CONSTRAINT entidade_pkey PRIMARY KEY (id);

--
-- Name: estagio_autonomia estagio_autonomia_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.estagio_autonomia
    ADD CONSTRAINT estagio_autonomia_pkey PRIMARY KEY (estagio);

--
-- Name: evento_auditoria evento_auditoria_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.evento_auditoria
    ADD CONSTRAINT evento_auditoria_pkey PRIMARY KEY (id);

--
-- Name: execucao_falha execucao_falha_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.execucao_falha
    ADD CONSTRAINT execucao_falha_pkey PRIMARY KEY (id);

--
-- Name: indice_macro_expectativa indice_macro_expectativa_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.indice_macro_expectativa
    ADD CONSTRAINT indice_macro_expectativa_pkey PRIMARY KEY (id);

--
-- Name: indice_macro_expectativa indice_macro_expectativa_serie_ano_ref_coletado_em_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.indice_macro_expectativa
    ADD CONSTRAINT indice_macro_expectativa_serie_ano_ref_coletado_em_key UNIQUE (serie, ano_ref, coletado_em);

--
-- Name: indice_macro_obs indice_macro_obs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.indice_macro_obs
    ADD CONSTRAINT indice_macro_obs_pkey PRIMARY KEY (id);

--
-- Name: indice_macro_obs indice_macro_obs_serie_fonte_data_ref_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.indice_macro_obs
    ADD CONSTRAINT indice_macro_obs_serie_fonte_data_ref_key UNIQUE (serie, fonte, data_ref);

--
-- Name: indice_macro_serie indice_macro_serie_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.indice_macro_serie
    ADD CONSTRAINT indice_macro_serie_pkey PRIMARY KEY (codigo);

--
-- Name: pendencia pendencia_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.pendencia
    ADD CONSTRAINT pendencia_pkey PRIMARY KEY (id);

--
-- Name: periodo periodo_caso_id_tipo_referencia_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.periodo
    ADD CONSTRAINT periodo_caso_id_tipo_referencia_key UNIQUE (caso_id, tipo, referencia);

--
-- Name: periodo periodo_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.periodo
    ADD CONSTRAINT periodo_pkey PRIMARY KEY (id);

--
-- Name: premissa_catalogo premissa_catalogo_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.premissa_catalogo
    ADD CONSTRAINT premissa_catalogo_pkey PRIMARY KEY (codigo);

--
-- Name: reconciliacao reconciliacao_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.reconciliacao
    ADD CONSTRAINT reconciliacao_pkey PRIMARY KEY (id);

--
-- Name: taxonomia_linha_exigida taxonomia_linha_exigida_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.taxonomia_linha_exigida
    ADD CONSTRAINT taxonomia_linha_exigida_pkey PRIMARY KEY (id);

--
-- Name: taxonomia_linha_exigida taxonomia_linha_exigida_tipo_taxonomia_conceito_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.taxonomia_linha_exigida
    ADD CONSTRAINT taxonomia_linha_exigida_tipo_taxonomia_conceito_key UNIQUE (tipo_taxonomia, conceito);

--
-- Name: taxonomia_linha_localizador taxonomia_linha_localizador_exigencia_id_ordem_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.taxonomia_linha_localizador
    ADD CONSTRAINT taxonomia_linha_localizador_exigencia_id_ordem_key UNIQUE (exigencia_id, ordem);

--
-- Name: taxonomia_linha_localizador taxonomia_linha_localizador_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.taxonomia_linha_localizador
    ADD CONSTRAINT taxonomia_linha_localizador_pkey PRIMARY KEY (id);

--
-- Name: taxonomia_tipo_documento taxonomia_tipo_documento_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.taxonomia_tipo_documento
    ADD CONSTRAINT taxonomia_tipo_documento_pkey PRIMARY KEY (codigo);

--
-- Name: idx_campo_docversao; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_campo_docversao ON public.campo_extraido USING btree (documento_versao_id);

--
-- Name: idx_campo_extraido_versao_ordem; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_campo_extraido_versao_ordem ON public.campo_extraido USING btree (documento_versao_id, ordem);

--
-- Name: idx_caso_linha_premissa_caso; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_caso_linha_premissa_caso ON public.caso_linha_premissa USING btree (caso_id);

--
-- Name: idx_caso_linha_premissa_unica; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_caso_linha_premissa_unica ON public.caso_linha_premissa USING btree (caso_id, rotulo_norm, COALESCE(entidade, ''::text), COALESCE(secao_canonica, ''::text));

--
-- Name: idx_caso_premissa_caso; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_caso_premissa_caso ON public.caso_premissa USING btree (caso_id);

--
-- Name: idx_checklist_caso; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_checklist_caso ON public.checklist_item_status USING btree (caso_id);

--
-- Name: idx_decisao_caso; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_decisao_caso ON public.decisao USING btree (caso_id);

--
-- Name: idx_documento_caso; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_documento_caso ON public.documento USING btree (caso_id);

--
-- Name: idx_docversao_documento; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_docversao_documento ON public.documento_versao USING btree (documento_id);

--
-- Name: idx_entidade_caso; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_entidade_caso ON public.entidade USING btree (caso_id);

--
-- Name: idx_evento_entidade_ref; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_evento_entidade_ref ON public.evento_auditoria USING btree (entidade_ref);

--
-- Name: idx_execucao_falha_caso; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_execucao_falha_caso ON public.execucao_falha USING btree (caso_id, criado_em DESC);

--
-- Name: idx_execucao_falha_nome; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_execucao_falha_nome ON public.execucao_falha USING btree (lower(caso_nome), criado_em DESC);

--
-- Name: idx_indice_macro_exp_serie_ano; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_indice_macro_exp_serie_ano ON public.indice_macro_expectativa USING btree (serie, ano_ref, coletado_em DESC);

--
-- Name: idx_indice_macro_obs_serie_data; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_indice_macro_obs_serie_data ON public.indice_macro_obs USING btree (serie, data_ref);

--
-- Name: idx_pendencia_caso; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_pendencia_caso ON public.pendencia USING btree (caso_id);

--
-- Name: idx_pendencia_estado; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_pendencia_estado ON public.pendencia USING btree (estado);

--
-- Name: idx_periodo_caso; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_periodo_caso ON public.periodo USING btree (caso_id);

--
-- Name: idx_reconciliacao_caso; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_reconciliacao_caso ON public.reconciliacao USING btree (caso_id);

--
-- Name: campo_extraido campo_extraido_documento_versao_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.campo_extraido
    ADD CONSTRAINT campo_extraido_documento_versao_id_fkey FOREIGN KEY (documento_versao_id) REFERENCES public.documento_versao(id) ON DELETE CASCADE;

--
-- Name: caso_linha_premissa caso_linha_premissa_caso_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.caso_linha_premissa
    ADD CONSTRAINT caso_linha_premissa_caso_id_fkey FOREIGN KEY (caso_id) REFERENCES public.caso(id) ON DELETE CASCADE;

--
-- Name: caso_linha_premissa caso_linha_premissa_premissa_codigo_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.caso_linha_premissa
    ADD CONSTRAINT caso_linha_premissa_premissa_codigo_fkey FOREIGN KEY (premissa_codigo) REFERENCES public.premissa_catalogo(codigo);

--
-- Name: caso_linha_premissa caso_linha_premissa_sazonalidade_codigo_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.caso_linha_premissa
    ADD CONSTRAINT caso_linha_premissa_sazonalidade_codigo_fkey FOREIGN KEY (sazonalidade_codigo) REFERENCES public.premissa_catalogo(codigo);

--
-- Name: caso_modelagem caso_modelagem_caso_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.caso_modelagem
    ADD CONSTRAINT caso_modelagem_caso_id_fkey FOREIGN KEY (caso_id) REFERENCES public.caso(id) ON DELETE CASCADE;

--
-- Name: caso_premissa caso_premissa_caso_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.caso_premissa
    ADD CONSTRAINT caso_premissa_caso_id_fkey FOREIGN KEY (caso_id) REFERENCES public.caso(id) ON DELETE CASCADE;

--
-- Name: caso_premissa caso_premissa_premissa_codigo_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.caso_premissa
    ADD CONSTRAINT caso_premissa_premissa_codigo_fkey FOREIGN KEY (premissa_codigo) REFERENCES public.premissa_catalogo(codigo);

--
-- Name: checklist_item_status checklist_item_status_caso_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.checklist_item_status
    ADD CONSTRAINT checklist_item_status_caso_id_fkey FOREIGN KEY (caso_id) REFERENCES public.caso(id) ON DELETE CASCADE;

--
-- Name: checklist_item_status checklist_item_status_documento_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.checklist_item_status
    ADD CONSTRAINT checklist_item_status_documento_id_fkey FOREIGN KEY (documento_id) REFERENCES public.documento(id);

--
-- Name: checklist_item_status checklist_item_status_entidade_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.checklist_item_status
    ADD CONSTRAINT checklist_item_status_entidade_id_fkey FOREIGN KEY (entidade_id) REFERENCES public.entidade(id);

--
-- Name: checklist_item_status checklist_item_status_periodo_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.checklist_item_status
    ADD CONSTRAINT checklist_item_status_periodo_id_fkey FOREIGN KEY (periodo_id) REFERENCES public.periodo(id);

--
-- Name: checklist_item_status checklist_item_status_tipo_taxonomia_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.checklist_item_status
    ADD CONSTRAINT checklist_item_status_tipo_taxonomia_fkey FOREIGN KEY (tipo_taxonomia) REFERENCES public.taxonomia_tipo_documento(codigo);

--
-- Name: decisao decisao_caso_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.decisao
    ADD CONSTRAINT decisao_caso_id_fkey FOREIGN KEY (caso_id) REFERENCES public.caso(id) ON DELETE CASCADE;

--
-- Name: documento documento_caso_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.documento
    ADD CONSTRAINT documento_caso_id_fkey FOREIGN KEY (caso_id) REFERENCES public.caso(id) ON DELETE CASCADE;

--
-- Name: documento documento_entidade_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.documento
    ADD CONSTRAINT documento_entidade_id_fkey FOREIGN KEY (entidade_id) REFERENCES public.entidade(id);

--
-- Name: documento documento_periodo_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.documento
    ADD CONSTRAINT documento_periodo_id_fkey FOREIGN KEY (periodo_id) REFERENCES public.periodo(id);

--
-- Name: documento documento_tipo_taxonomia_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.documento
    ADD CONSTRAINT documento_tipo_taxonomia_fkey FOREIGN KEY (tipo_taxonomia) REFERENCES public.taxonomia_tipo_documento(codigo);

--
-- Name: documento_versao documento_versao_documento_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.documento_versao
    ADD CONSTRAINT documento_versao_documento_id_fkey FOREIGN KEY (documento_id) REFERENCES public.documento(id) ON DELETE CASCADE;

--
-- Name: entidade entidade_caso_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.entidade
    ADD CONSTRAINT entidade_caso_id_fkey FOREIGN KEY (caso_id) REFERENCES public.caso(id) ON DELETE CASCADE;

--
-- Name: execucao_falha execucao_falha_caso_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.execucao_falha
    ADD CONSTRAINT execucao_falha_caso_id_fkey FOREIGN KEY (caso_id) REFERENCES public.caso(id) ON DELETE CASCADE;

--
-- Name: indice_macro_expectativa indice_macro_expectativa_serie_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.indice_macro_expectativa
    ADD CONSTRAINT indice_macro_expectativa_serie_fkey FOREIGN KEY (serie) REFERENCES public.indice_macro_serie(codigo);

--
-- Name: indice_macro_obs indice_macro_obs_serie_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.indice_macro_obs
    ADD CONSTRAINT indice_macro_obs_serie_fkey FOREIGN KEY (serie) REFERENCES public.indice_macro_serie(codigo);

--
-- Name: pendencia pendencia_caso_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.pendencia
    ADD CONSTRAINT pendencia_caso_id_fkey FOREIGN KEY (caso_id) REFERENCES public.caso(id) ON DELETE CASCADE;

--
-- Name: pendencia pendencia_documento_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.pendencia
    ADD CONSTRAINT pendencia_documento_id_fkey FOREIGN KEY (documento_id) REFERENCES public.documento(id);

--
-- Name: pendencia pendencia_entidade_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.pendencia
    ADD CONSTRAINT pendencia_entidade_id_fkey FOREIGN KEY (entidade_id) REFERENCES public.entidade(id);

--
-- Name: pendencia pendencia_periodo_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.pendencia
    ADD CONSTRAINT pendencia_periodo_id_fkey FOREIGN KEY (periodo_id) REFERENCES public.periodo(id);

--
-- Name: periodo periodo_caso_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.periodo
    ADD CONSTRAINT periodo_caso_id_fkey FOREIGN KEY (caso_id) REFERENCES public.caso(id) ON DELETE CASCADE;

--
-- Name: reconciliacao reconciliacao_caso_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.reconciliacao
    ADD CONSTRAINT reconciliacao_caso_id_fkey FOREIGN KEY (caso_id) REFERENCES public.caso(id) ON DELETE CASCADE;

--
-- Name: reconciliacao reconciliacao_entidade_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.reconciliacao
    ADD CONSTRAINT reconciliacao_entidade_id_fkey FOREIGN KEY (entidade_id) REFERENCES public.entidade(id);

--
-- Name: reconciliacao reconciliacao_periodo_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.reconciliacao
    ADD CONSTRAINT reconciliacao_periodo_id_fkey FOREIGN KEY (periodo_id) REFERENCES public.periodo(id);

--
-- Name: taxonomia_linha_exigida taxonomia_linha_exigida_tipo_taxonomia_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.taxonomia_linha_exigida
    ADD CONSTRAINT taxonomia_linha_exigida_tipo_taxonomia_fkey FOREIGN KEY (tipo_taxonomia) REFERENCES public.taxonomia_tipo_documento(codigo);

--
-- Name: taxonomia_linha_localizador taxonomia_linha_localizador_exigencia_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.taxonomia_linha_localizador
    ADD CONSTRAINT taxonomia_linha_localizador_exigencia_id_fkey FOREIGN KEY (exigencia_id) REFERENCES public.taxonomia_linha_exigida(id) ON DELETE CASCADE;

--
-- Name: campo_extraido; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.campo_extraido ENABLE ROW LEVEL SECURITY;

--
-- Name: campo_extraido campo_extraido_authenticated_all; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY campo_extraido_authenticated_all ON public.campo_extraido TO authenticated USING (true) WITH CHECK (true);

--
-- Name: caso; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.caso ENABLE ROW LEVEL SECURITY;

--
-- Name: caso caso_authenticated_all; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY caso_authenticated_all ON public.caso TO authenticated USING (true) WITH CHECK (true);

--
-- Name: caso_linha_premissa; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.caso_linha_premissa ENABLE ROW LEVEL SECURITY;

--
-- Name: caso_linha_premissa caso_linha_premissa_authenticated_all; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY caso_linha_premissa_authenticated_all ON public.caso_linha_premissa TO authenticated USING (true) WITH CHECK (true);

--
-- Name: caso_modelagem; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.caso_modelagem ENABLE ROW LEVEL SECURITY;

--
-- Name: caso_modelagem caso_modelagem_authenticated_all; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY caso_modelagem_authenticated_all ON public.caso_modelagem TO authenticated USING (true) WITH CHECK (true);

--
-- Name: caso_premissa; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.caso_premissa ENABLE ROW LEVEL SECURITY;

--
-- Name: caso_premissa caso_premissa_authenticated_all; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY caso_premissa_authenticated_all ON public.caso_premissa TO authenticated USING (true) WITH CHECK (true);

--
-- Name: checklist_item_status; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.checklist_item_status ENABLE ROW LEVEL SECURITY;

--
-- Name: checklist_item_status checklist_item_status_authenticated_all; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY checklist_item_status_authenticated_all ON public.checklist_item_status TO authenticated USING (true) WITH CHECK (true);

--
-- Name: decisao; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.decisao ENABLE ROW LEVEL SECURITY;

--
-- Name: decisao decisao_authenticated_all; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY decisao_authenticated_all ON public.decisao TO authenticated USING (true) WITH CHECK (true);

--
-- Name: documento; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.documento ENABLE ROW LEVEL SECURITY;

--
-- Name: documento documento_authenticated_all; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY documento_authenticated_all ON public.documento TO authenticated USING (true) WITH CHECK (true);

--
-- Name: documento_versao; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.documento_versao ENABLE ROW LEVEL SECURITY;

--
-- Name: documento_versao documento_versao_authenticated_all; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY documento_versao_authenticated_all ON public.documento_versao TO authenticated USING (true) WITH CHECK (true);

--
-- Name: entidade; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.entidade ENABLE ROW LEVEL SECURITY;

--
-- Name: entidade entidade_authenticated_all; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY entidade_authenticated_all ON public.entidade TO authenticated USING (true) WITH CHECK (true);

--
-- Name: estagio_autonomia; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.estagio_autonomia ENABLE ROW LEVEL SECURITY;

--
-- Name: estagio_autonomia estagio_autonomia_authenticated_all; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY estagio_autonomia_authenticated_all ON public.estagio_autonomia TO authenticated USING (true) WITH CHECK (true);

--
-- Name: evento_auditoria; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.evento_auditoria ENABLE ROW LEVEL SECURITY;

--
-- Name: evento_auditoria evento_auditoria_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY evento_auditoria_insert ON public.evento_auditoria FOR INSERT TO authenticated WITH CHECK (true);

--
-- Name: evento_auditoria evento_auditoria_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY evento_auditoria_read ON public.evento_auditoria FOR SELECT TO authenticated USING (true);

--
-- Name: execucao_falha; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.execucao_falha ENABLE ROW LEVEL SECURITY;

--
-- Name: execucao_falha execucao_falha_authenticated_all; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY execucao_falha_authenticated_all ON public.execucao_falha TO authenticated USING (true) WITH CHECK (true);

--
-- Name: indice_macro_expectativa; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.indice_macro_expectativa ENABLE ROW LEVEL SECURITY;

--
-- Name: indice_macro_expectativa indice_macro_expectativa_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY indice_macro_expectativa_read ON public.indice_macro_expectativa FOR SELECT TO authenticated USING (true);

--
-- Name: indice_macro_obs; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.indice_macro_obs ENABLE ROW LEVEL SECURITY;

--
-- Name: indice_macro_obs indice_macro_obs_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY indice_macro_obs_read ON public.indice_macro_obs FOR SELECT TO authenticated USING (true);

--
-- Name: indice_macro_serie; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.indice_macro_serie ENABLE ROW LEVEL SECURITY;

--
-- Name: indice_macro_serie indice_macro_serie_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY indice_macro_serie_read ON public.indice_macro_serie FOR SELECT TO authenticated USING (true);

--
-- Name: pendencia; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.pendencia ENABLE ROW LEVEL SECURITY;

--
-- Name: pendencia pendencia_authenticated_all; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY pendencia_authenticated_all ON public.pendencia TO authenticated USING (true) WITH CHECK (true);

--
-- Name: periodo; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.periodo ENABLE ROW LEVEL SECURITY;

--
-- Name: periodo periodo_authenticated_all; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY periodo_authenticated_all ON public.periodo TO authenticated USING (true) WITH CHECK (true);

--
-- Name: premissa_catalogo; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.premissa_catalogo ENABLE ROW LEVEL SECURITY;

--
-- Name: premissa_catalogo premissa_catalogo_authenticated_all; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY premissa_catalogo_authenticated_all ON public.premissa_catalogo TO authenticated USING (true) WITH CHECK (true);

--
-- Name: reconciliacao; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.reconciliacao ENABLE ROW LEVEL SECURITY;

--
-- Name: reconciliacao reconciliacao_authenticated_all; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY reconciliacao_authenticated_all ON public.reconciliacao TO authenticated USING (true) WITH CHECK (true);

--
-- Name: taxonomia_linha_exigida; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.taxonomia_linha_exigida ENABLE ROW LEVEL SECURITY;

--
-- Name: taxonomia_linha_exigida taxonomia_linha_exigida_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY taxonomia_linha_exigida_read ON public.taxonomia_linha_exigida FOR SELECT TO authenticated USING (true);

--
-- Name: taxonomia_linha_localizador; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.taxonomia_linha_localizador ENABLE ROW LEVEL SECURITY;

--
-- Name: taxonomia_linha_localizador taxonomia_linha_localizador_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY taxonomia_linha_localizador_read ON public.taxonomia_linha_localizador FOR SELECT TO authenticated USING (true);

--
-- Name: taxonomia_tipo_documento taxonomia_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY taxonomia_read ON public.taxonomia_tipo_documento FOR SELECT TO authenticated USING (true);

--
-- Name: taxonomia_tipo_documento; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.taxonomia_tipo_documento ENABLE ROW LEVEL SECURITY;

--
-- Name: SCHEMA public; Type: ACL; Schema: -; Owner: -
--

GRANT USAGE ON SCHEMA public TO anon;
GRANT USAGE ON SCHEMA public TO authenticated;
GRANT USAGE ON SCHEMA public TO service_role;

--
-- Name: FUNCTION fn_aceitar_extracao(p_documento_versao_id uuid, p_autor text, p_motivo text); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.fn_aceitar_extracao(p_documento_versao_id uuid, p_autor text, p_motivo text) TO authenticated;

--
-- Name: FUNCTION fn_ano_da_coluna(p_periodo_coluna text, p_referencia text); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.fn_ano_da_coluna(p_periodo_coluna text, p_referencia text) TO authenticated;

--
-- Name: FUNCTION fn_aplicar_premissa_em_lote(p_caso_id uuid, p_secao_canonica text, p_premissa text, p_autor text, p_sazonalidade text); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.fn_aplicar_premissa_em_lote(p_caso_id uuid, p_secao_canonica text, p_premissa text, p_autor text, p_sazonalidade text) TO authenticated;

--
-- Name: FUNCTION fn_aprovar_caso(p_caso_id uuid, p_autor text, p_motivo text); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.fn_aprovar_caso(p_caso_id uuid, p_autor text, p_motivo text) TO authenticated;

--
-- Name: FUNCTION fn_ativar_premissa(p_caso_id uuid, p_codigo text, p_valores jsonb, p_origem text, p_autor text); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.fn_ativar_premissa(p_caso_id uuid, p_codigo text, p_valores jsonb, p_origem text, p_autor text) TO authenticated;

--
-- Name: FUNCTION fn_avaliar_guardas_extracao(p_documento_versao_id uuid); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.fn_avaliar_guardas_extracao(p_documento_versao_id uuid) TO authenticated;

--
-- Name: FUNCTION fn_avaliar_portao2(p_caso_id uuid); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.fn_avaliar_portao2(p_caso_id uuid) TO authenticated;

--
-- Name: FUNCTION fn_conferir_lote(p_caso_id uuid); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.fn_conferir_lote(p_caso_id uuid) TO authenticated;

--
-- Name: FUNCTION fn_conferir_modelagem(p_caso_id uuid); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.fn_conferir_modelagem(p_caso_id uuid) TO authenticated;

--
-- Name: FUNCTION fn_contas_repetindo_valor(p_documento_versao_id uuid); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.fn_contas_repetindo_valor(p_documento_versao_id uuid) TO authenticated;

--
-- Name: FUNCTION fn_decidir_pendencia(p_pendencia_id uuid, p_autor text, p_decisao text, p_motivo text); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.fn_decidir_pendencia(p_pendencia_id uuid, p_autor text, p_decisao text, p_motivo text) TO authenticated;

--
-- Name: FUNCTION fn_definir_modelagem(p_caso_id uuid, p_entidade text, p_ultimo_exercicio_real integer, p_indice_macro text, p_setor text, p_autor text, p_anos_projetados integer); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.fn_definir_modelagem(p_caso_id uuid, p_entidade text, p_ultimo_exercicio_real integer, p_indice_macro text, p_setor text, p_autor text, p_anos_projetados integer) TO authenticated;

--
-- Name: FUNCTION fn_desativar_premissa(p_caso_id uuid, p_codigo text, p_autor text); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.fn_desativar_premissa(p_caso_id uuid, p_codigo text, p_autor text) TO authenticated;

--
-- Name: FUNCTION fn_diagnostico_modelagem(p_caso_id uuid); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.fn_diagnostico_modelagem(p_caso_id uuid) TO authenticated;

--
-- Name: FUNCTION fn_dial(p_estagio text); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.fn_dial(p_estagio text) TO authenticated;

--
-- Name: FUNCTION fn_documentos_nao_extraidos(p_caso_id uuid); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.fn_documentos_nao_extraidos(p_caso_id uuid) TO authenticated;

--
-- Name: FUNCTION fn_excluir_caso(p_caso_id uuid, p_autor text); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.fn_excluir_caso(p_caso_id uuid, p_autor text) TO authenticated;

--
-- Name: FUNCTION fn_exigencias_do_caso(p_caso_id uuid); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.fn_exigencias_do_caso(p_caso_id uuid) TO authenticated;

--
-- Name: FUNCTION fn_falhas_abertas(p_caso_nome text, p_desde timestamp with time zone); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.fn_falhas_abertas(p_caso_nome text, p_desde timestamp with time zone) TO authenticated;

--
-- Name: FUNCTION fn_indice_macro_anual(p_desde_ano integer); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.fn_indice_macro_anual(p_desde_ano integer) TO authenticated;

--
-- Name: FUNCTION fn_linhas_do_tipo(p_caso_id uuid, p_codigo text); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.fn_linhas_do_tipo(p_caso_id uuid, p_codigo text) TO authenticated;

--
-- Name: FUNCTION fn_linhas_para_modelagem(p_caso_id uuid); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.fn_linhas_para_modelagem(p_caso_id uuid) TO authenticated;

--
-- Name: FUNCTION fn_marcar_falha_vista(p_falha_id uuid, p_autor text); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.fn_marcar_falha_vista(p_falha_id uuid, p_autor text) TO authenticated;

--
-- Name: FUNCTION fn_mes_do_rotulo(p_chave text); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.fn_mes_do_rotulo(p_chave text) TO authenticated;

--
-- Name: FUNCTION fn_min_motivo_rejeicao(); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.fn_min_motivo_rejeicao() TO authenticated;

--
-- Name: FUNCTION fn_mudar_dial(p_estagio text, p_nivel public.nivel_autonomia, p_autor text, p_motivo text, p_limiar numeric); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.fn_mudar_dial(p_estagio text, p_nivel public.nivel_autonomia, p_autor text, p_motivo text, p_limiar numeric) TO authenticated;

--
-- Name: FUNCTION fn_papel_do_rotulo_no_caso(p_caso_id uuid, p_rotulo_norm text, p_secao_canonica text); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.fn_papel_do_rotulo_no_caso(p_caso_id uuid, p_rotulo_norm text, p_secao_canonica text) TO authenticated;

--
-- Name: FUNCTION fn_papel_linha(p_chave text, p_tipo_taxonomia text, p_unidade text); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.fn_papel_linha(p_chave text, p_tipo_taxonomia text, p_unidade text) TO authenticated;

--
-- Name: FUNCTION fn_papel_prioridade(p_papel text); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.fn_papel_prioridade(p_papel text) TO authenticated;

--
-- Name: FUNCTION fn_premissa_valores_sugeridos(p_codigo text, p_ano_inicial integer, p_anos integer); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.fn_premissa_valores_sugeridos(p_codigo text, p_ano_inicial integer, p_anos integer) TO authenticated;

--
-- Name: TABLE premissa_catalogo; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.premissa_catalogo TO anon;
GRANT ALL ON TABLE public.premissa_catalogo TO authenticated;
GRANT ALL ON TABLE public.premissa_catalogo TO service_role;

--
-- Name: FUNCTION fn_premissas_sugeridas(p_setor text); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.fn_premissas_sugeridas(p_setor text) TO authenticated;

--
-- Name: FUNCTION fn_radicais_rotulo(p_chave text); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.fn_radicais_rotulo(p_chave text) TO authenticated;

--
-- Name: FUNCTION fn_reavaliar_guardas_extracao(p_documento_versao_id uuid, p_autor text); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.fn_reavaliar_guardas_extracao(p_documento_versao_id uuid, p_autor text) TO authenticated;

--
-- Name: FUNCTION fn_reconferir_caso(p_caso_id uuid, p_autor text); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.fn_reconferir_caso(p_caso_id uuid, p_autor text) TO authenticated;

--
-- Name: FUNCTION fn_registrar_campos_extraidos(p_documento_versao_id uuid, p_campos jsonb, p_nivel public.nivel_autonomia, p_falha_motivo text, p_tem_dado_financeiro boolean); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.fn_registrar_campos_extraidos(p_documento_versao_id uuid, p_campos jsonb, p_nivel public.nivel_autonomia, p_falha_motivo text, p_tem_dado_financeiro boolean) TO authenticated;

--
-- Name: FUNCTION fn_registrar_falha_execucao(p_caso_id uuid, p_caso_nome text, p_etapa text, p_mensagem text, p_detalhe jsonb); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.fn_registrar_falha_execucao(p_caso_id uuid, p_caso_nome text, p_etapa text, p_mensagem text, p_detalhe jsonb) TO authenticated;
GRANT ALL ON FUNCTION public.fn_registrar_falha_execucao(p_caso_id uuid, p_caso_nome text, p_etapa text, p_mensagem text, p_detalhe jsonb) TO service_role;

--
-- Name: FUNCTION fn_revisar_documento(p_documento_id uuid, p_autor text, p_novo_tipo_taxonomia text, p_nova_entidade_nome text, p_novo_periodo_tipo text, p_novo_periodo_ref text, p_motivo text); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.fn_revisar_documento(p_documento_id uuid, p_autor text, p_novo_tipo_taxonomia text, p_nova_entidade_nome text, p_novo_periodo_tipo text, p_novo_periodo_ref text, p_motivo text) TO authenticated;

--
-- Name: FUNCTION fn_rotulo_contido(p_curto text, p_longo text); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.fn_rotulo_contido(p_curto text, p_longo text) TO authenticated;

--
-- Name: FUNCTION fn_rotulo_estrutural(p_chave text, p_tokens_exigidos text[]); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.fn_rotulo_estrutural(p_chave text, p_tokens_exigidos text[]) TO authenticated;

--
-- Name: FUNCTION fn_sazonalidade_do_caso(p_caso_id uuid); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.fn_sazonalidade_do_caso(p_caso_id uuid) TO authenticated;

--
-- Name: FUNCTION fn_tem_palavra_longa(p_chave text); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.fn_tem_palavra_longa(p_chave text) TO authenticated;

--
-- Name: FUNCTION fn_teto_ressalvas(); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.fn_teto_ressalvas() TO authenticated;

--
-- Name: FUNCTION fn_tokens_estruturais(p_chave text); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.fn_tokens_estruturais(p_chave text) TO authenticated;

--
-- Name: TABLE campo_extraido; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.campo_extraido TO anon;
GRANT ALL ON TABLE public.campo_extraido TO authenticated;
GRANT ALL ON TABLE public.campo_extraido TO service_role;

--
-- Name: FUNCTION fn_valor_estrutural_col(p_documento_versao_id uuid, p_tokens text[], p_entidade_coluna text, p_periodo_coluna text); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.fn_valor_estrutural_col(p_documento_versao_id uuid, p_tokens text[], p_entidade_coluna text, p_periodo_coluna text) TO authenticated;

--
-- Name: FUNCTION fn_valores_por_ano(p_caso_id uuid, p_entidade text); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.fn_valores_por_ano(p_caso_id uuid, p_entidade text) TO authenticated;

--
-- Name: FUNCTION fn_versao_com_extracao(p_documento_id uuid); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.fn_versao_com_extracao(p_documento_id uuid) TO authenticated;

--
-- Name: FUNCTION fn_vincular_linha_premissa(p_caso_id uuid, p_secao_canonica text, p_rotulo text, p_entidade text, p_premissa text, p_autor text, p_sazonalidade text); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.fn_vincular_linha_premissa(p_caso_id uuid, p_secao_canonica text, p_rotulo text, p_entidade text, p_premissa text, p_autor text, p_sazonalidade text) TO authenticated;

--
-- Name: TABLE caso; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.caso TO anon;
GRANT ALL ON TABLE public.caso TO authenticated;
GRANT ALL ON TABLE public.caso TO service_role;

--
-- Name: TABLE caso_linha_premissa; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.caso_linha_premissa TO anon;
GRANT ALL ON TABLE public.caso_linha_premissa TO authenticated;
GRANT ALL ON TABLE public.caso_linha_premissa TO service_role;

--
-- Name: TABLE caso_modelagem; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.caso_modelagem TO anon;
GRANT ALL ON TABLE public.caso_modelagem TO authenticated;
GRANT ALL ON TABLE public.caso_modelagem TO service_role;

--
-- Name: TABLE caso_premissa; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.caso_premissa TO anon;
GRANT ALL ON TABLE public.caso_premissa TO authenticated;
GRANT ALL ON TABLE public.caso_premissa TO service_role;

--
-- Name: TABLE checklist_item_status; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.checklist_item_status TO anon;
GRANT ALL ON TABLE public.checklist_item_status TO authenticated;
GRANT ALL ON TABLE public.checklist_item_status TO service_role;

--
-- Name: TABLE decisao; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.decisao TO anon;
GRANT ALL ON TABLE public.decisao TO authenticated;
GRANT ALL ON TABLE public.decisao TO service_role;

--
-- Name: TABLE documento; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.documento TO anon;
GRANT ALL ON TABLE public.documento TO authenticated;
GRANT ALL ON TABLE public.documento TO service_role;

--
-- Name: TABLE documento_versao; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.documento_versao TO anon;
GRANT ALL ON TABLE public.documento_versao TO authenticated;
GRANT ALL ON TABLE public.documento_versao TO service_role;

--
-- Name: TABLE entidade; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.entidade TO anon;
GRANT ALL ON TABLE public.entidade TO authenticated;
GRANT ALL ON TABLE public.entidade TO service_role;

--
-- Name: TABLE estagio_autonomia; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.estagio_autonomia TO anon;
GRANT ALL ON TABLE public.estagio_autonomia TO authenticated;
GRANT ALL ON TABLE public.estagio_autonomia TO service_role;

--
-- Name: TABLE evento_auditoria; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.evento_auditoria TO anon;
GRANT ALL ON TABLE public.evento_auditoria TO authenticated;
GRANT ALL ON TABLE public.evento_auditoria TO service_role;

--
-- Name: TABLE execucao_falha; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.execucao_falha TO anon;
GRANT ALL ON TABLE public.execucao_falha TO authenticated;
GRANT ALL ON TABLE public.execucao_falha TO service_role;

--
-- Name: TABLE indice_macro_expectativa; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.indice_macro_expectativa TO anon;
GRANT ALL ON TABLE public.indice_macro_expectativa TO authenticated;
GRANT ALL ON TABLE public.indice_macro_expectativa TO service_role;

--
-- Name: TABLE indice_macro_obs; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.indice_macro_obs TO anon;
GRANT ALL ON TABLE public.indice_macro_obs TO authenticated;
GRANT ALL ON TABLE public.indice_macro_obs TO service_role;

--
-- Name: TABLE indice_macro_serie; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.indice_macro_serie TO anon;
GRANT ALL ON TABLE public.indice_macro_serie TO authenticated;
GRANT ALL ON TABLE public.indice_macro_serie TO service_role;

--
-- Name: TABLE pendencia; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.pendencia TO anon;
GRANT ALL ON TABLE public.pendencia TO authenticated;
GRANT ALL ON TABLE public.pendencia TO service_role;

--
-- Name: TABLE periodo; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.periodo TO anon;
GRANT ALL ON TABLE public.periodo TO authenticated;
GRANT ALL ON TABLE public.periodo TO service_role;

--
-- Name: TABLE reconciliacao; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.reconciliacao TO anon;
GRANT ALL ON TABLE public.reconciliacao TO authenticated;
GRANT ALL ON TABLE public.reconciliacao TO service_role;

--
-- Name: TABLE taxonomia_linha_exigida; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.taxonomia_linha_exigida TO anon;
GRANT ALL ON TABLE public.taxonomia_linha_exigida TO authenticated;
GRANT ALL ON TABLE public.taxonomia_linha_exigida TO service_role;

--
-- Name: TABLE taxonomia_linha_localizador; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.taxonomia_linha_localizador TO anon;
GRANT ALL ON TABLE public.taxonomia_linha_localizador TO authenticated;
GRANT ALL ON TABLE public.taxonomia_linha_localizador TO service_role;

--
-- Name: TABLE taxonomia_tipo_documento; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.taxonomia_tipo_documento TO anon;
GRANT ALL ON TABLE public.taxonomia_tipo_documento TO authenticated;
GRANT ALL ON TABLE public.taxonomia_tipo_documento TO service_role;

--
-- Name: DEFAULT PRIVILEGES FOR SEQUENCES; Type: DEFAULT ACL; Schema: public; Owner: -
--

ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON SEQUENCES TO anon;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON SEQUENCES TO authenticated;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON SEQUENCES TO service_role;

--
-- Name: DEFAULT PRIVILEGES FOR TABLES; Type: DEFAULT ACL; Schema: public; Owner: -
--

ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON TABLES TO anon;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON TABLES TO authenticated;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON TABLES TO service_role;

--
--

