-- 0023 — Reconciliação sem ruído: ausência de documento não é pendência,
--        escala se CONVERTE, coluna importa, e total ausente se soma
-- =============================================================================
-- Rodada do "teste v25" (book Vertentes, 14 documentos). O portal mostrou
-- **36 pendências de reconciliação**, todas de pré-condição, com o book
-- extraído corretamente. Reproduzido em `db/test/` (fixture de extração fiel →
-- 36 pendências, exatamente o que o dono viu). Cinco causas distintas, e uma
-- delas é de projeto, não de rótulo:
--
-- 1) AUSÊNCIA DE DOCUMENTO VIRAVA PENDÊNCIA — 20 das 36 (16 "Fluxo de Caixa
--    ausente" + 4 "Balanço e Fluxo de Caixa ausente"). E o fato é VERDADEIRO: o
--    book só tem DFC da Metalúrgica; as outras 4 empresas não têm DFC nenhuma.
--    Só que reconciliação não é o canal disso. Documento que falta é
--    responsabilidade do CHECKLIST do Kit Básico (`fn_recomputar_completude`),
--    que já rastreia exatamente isso, com estado e cobrança próprios. Emitir
--    também aqui (a) duplica o sinal, (b) enche a fila de revisão de itens que
--    o humano não tem como acionar — não há correção a fazer, o arquivo
--    simplesmente não foi entregue — e (c) escala com
--    nº_entidades × nº_períodos × nº_checagens, que é de onde vêm as 36.
--    Agora: a tentativa continua registrada em `reconciliacao` (a trilha de
--    auditoria não perde nada — sabemos que a checagem rodou e por que parou),
--    mas NÃO abre pendência. Pendência fica reservada para o que o humano pode
--    resolver: documento presente e dado que não amarra.
--
-- 2) O COMBINADO NÃO ERA ACEITO COMO BALANÇO — 4 pendências "Nenhum Balanço
--    Patrimonial classificado para esta entidade/período" para o GRUPO. Falso:
--    o documento 06 do book É o balanço combinado do grupo. As checagens
--    procuravam `tipo_taxonomia = 'BALANCO'` e nada mais. Agora aceitam
--    BALANCO → COMBINADO → BALANCETE, nessa ordem de preferência.
--
-- 3) COLUNA ERA IGNORADA. `fn_valor_conceito` varria a versão inteira e pegava
--    `limit 1`. Num balanço comparativo (2025 × 2024) ou combinado (5 empresas
--    em colunas) isso é sorte: comparava o Ativo de um ano contra o Passivo de
--    outro, e um desequilíbrio de 2024 passava batido porque só o primeiro
--    casamento era olhado. Agora existe `fn_valor_conceito_col`, e cada checagem
--    resolve a coluna de entidade e a de período antes de comparar — e roda uma
--    vez por ANO declarado no período, não uma vez só.
--
-- 4) TOTAL DE SEÇÃO SEM LINHA DE TOTAL — 4 pendências "Não foi possível
--    localizar a Receita Operacional Bruta na DRE". Falso: ela está lá, mas
--    como CABEÇALHO SEM VALOR ("RECEITA OPERACIONAL BRUTA" e, abaixo, "Vendas
--    de produtos - mercado interno", "- mercado externo", "Prestação de
--    serviços"). É convenção corriqueira de demonstração brasileira, não
--    defeito do arquivo. Novo `fn_soma_secao` soma as contas-folha da seção
--    quando não existe linha de total — e exclui a própria linha de total para
--    não contar duas vezes.
--
-- 5) ESCALA DIVERGENTE RECUSAVA A COMPARAÇÃO — 4 pendências. O mapa de dívida
--    do book está em REAIS e a DRE em MILHARES (de propósito: é o que acontece
--    quando cada peça vem de um sistema diferente). A 0021 acertou em não
--    comparar às cegas, mas parar é desperdício: quando AS DUAS escalas estão
--    declaradas e são conhecidas, converter é determinístico e exato. Agora
--    converte para a base (unidade) e compara; só recusa quando uma das escalas
--    é ausente ou desconhecida — aí sim não há como afirmar nada.
--
-- Resultado no fixture: 36 pendências → 0, sem nenhuma checagem ter sido
-- desligada (as 4 continuam rodando e agora produzem 'ok' com número, não
-- silêncio). Assinaturas preservadas: o N8N chama `fn_reconciliar_por_documento`
-- e não muda.

-- -----------------------------------------------------------------------------
-- fn_fator_escala — fator para levar um valor à BASE (unidade). Vocabulário
-- canônico da extração (n8n/lib/extract.mjs → 'unidade'|'milhar'|'milhao'), com
-- tolerância às formas que aparecem em cabeçalho real. Devolve null para escala
-- ausente ou desconhecida — "não sei" nunca vira 1, senão um documento em
-- milhares seria comparado como se estivesse em reais.
-- -----------------------------------------------------------------------------
create or replace function fn_fator_escala(p_unidade text)
returns numeric
language sql
immutable
as $$
  select case
    when p_unidade is null or length(trim(p_unidade)) = 0 then null
    when fn_normalizar_texto(p_unidade) in ('unidade', 'unidades', 'reais', 'real', 'r$', 'brl') then 1
    when fn_normalizar_texto(p_unidade) in ('milhar', 'milhares', 'mil', 'r$ mil') then 1000
    when fn_normalizar_texto(p_unidade) in ('milhao', 'milhoes', 'milhao de reais') then 1000000
    else null
  end;
$$;

comment on function fn_fator_escala(text) is
  'Fator multiplicativo para levar um valor à base (unidade). null quando a escala é ausente ou desconhecida.';

-- -----------------------------------------------------------------------------
-- fn_motivo_escala_incomparavel — REDEFINIDA (mesma assinatura de 0021). Antes
-- bloqueava sempre que as duas escalas divergiam. Agora só bloqueia quando não
-- há como converter: escala ausente, ou declarada em vocabulário que não
-- reconhecemos. Escalas diferentes MAS conhecidas deixam de ser bloqueio — quem
-- compara converte (ver fn_comparar_em_base).
-- -----------------------------------------------------------------------------
create or replace function fn_motivo_escala_incomparavel(
  p_unidade_a text,
  p_unidade_b text,
  p_rotulo_a  text,
  p_rotulo_b  text
)
returns text
language sql
immutable
as $$
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

-- -----------------------------------------------------------------------------
-- fn_valor_em_base — valor levado à base pela escala declarada. Quando a escala
-- é ausente/desconhecida devolve o valor cru (o chamador já checou, via
-- fn_motivo_escala_incomparavel, se pode comparar).
-- -----------------------------------------------------------------------------
create or replace function fn_valor_em_base(p_valor numeric, p_unidade text)
returns numeric
language sql
immutable
as $$
  select p_valor * coalesce(fn_fator_escala(p_unidade), 1);
$$;

-- -----------------------------------------------------------------------------
-- fn_anos_texto — conjunto de anos implícito num rótulo de COLUNA
-- (`entidade_coluna`/`periodo_coluna`) ou de linha: "2025", "2025-12",
-- "dez/25", "31/12/2024". Vazio quando não há ano.
-- -----------------------------------------------------------------------------
create or replace function fn_anos_texto(p_texto text)
returns int[]
language plpgsql
immutable
as $$
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
$$;

-- -----------------------------------------------------------------------------
-- fn_coluna_periodo_do_ano — qual `periodo_coluna` desta versão corresponde ao
-- ano pedido. Três respostas, e a distinção entre elas importa:
--   null      → o documento não tem coluna de período (coluna única): não filtra;
--   '<rótulo>'→ a coluna daquele ano;
--   E'\x01'   → o documento TEM colunas de período mas NENHUMA é daquele ano.
-- O terceiro caso é o que evita um falso divergente: a DFC do book cobre só
-- 2025, e sem esse sentinela a checagem comparava o saldo final de 2025 contra o
-- Disponível de 2024 do balanço, acusando divergência onde não há nada a comparar.
-- -----------------------------------------------------------------------------
create or replace function fn_coluna_periodo_do_ano(p_documento_versao_id uuid, p_ano int)
returns text
language plpgsql
stable
as $$
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

-- -----------------------------------------------------------------------------
-- fn_coluna_entidade — qual `entidade_coluna` desta versão corresponde à
-- entidade pedida. Três casos, nesta ordem:
--   1. coluna cujo rótulo casa com a razão social da entidade (combinado);
--   2. documento SEM colunas de entidade → null (não filtra);
--   3. documento COM colunas, nenhuma casa, e o documento está registrado NESSA
--      entidade → a coluna de total do próprio documento ("Combinado",
--      "Consolidado", "Total"), que é justamente o total daquela entidade-grupo.
-- Fora desses casos devolve o sentinela '\x01' (nenhuma coluna casa), para o
-- chamador distinguir "não filtrar" de "filtrar e não achar".
-- -----------------------------------------------------------------------------
create or replace function fn_coluna_entidade(p_documento_versao_id uuid, p_entidade_id uuid)
returns text
language plpgsql
stable
as $$
declare
  v_razao   text;
  v_col     text;
  v_tem_col boolean;
  v_dono    boolean;
begin
  select exists (
    select 1 from campo_extraido ce
    where ce.documento_versao_id = p_documento_versao_id and ce.entidade_coluna is not null
  ) into v_tem_col;
  if not v_tem_col then return null; end if;

  select e.razao_social into v_razao from entidade e where e.id = p_entidade_id;
  if v_razao is not null then
    select ce.entidade_coluna into v_col
    from campo_extraido ce
    where ce.documento_versao_id = p_documento_versao_id
      and ce.entidade_coluna is not null
      and fn_normalizar_texto(ce.entidade_coluna) = fn_normalizar_texto(v_razao)
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

-- -----------------------------------------------------------------------------
-- fn_valor_conceito_col — como `fn_valor_conceito` (0009), mas CIENTE DE COLUNA.
-- Filtra por `entidade_coluna`/`periodo_coluna` quando o argumento não é null.
-- O sentinela E'\x01' em p_entidade_coluna significa "nenhuma coluna casa com a
-- entidade" e faz a função não retornar nada (em vez de comparar a coluna
-- errada, que é o bug que isto corrige).
-- -----------------------------------------------------------------------------
create or replace function fn_valor_conceito_col(
  p_documento_versao_id uuid,
  p_inclui text[],
  p_exclui text[] default '{}',
  p_entidade_coluna text default null,
  p_periodo_coluna text default null
)
returns campo_extraido
language sql
stable
as $$
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

-- -----------------------------------------------------------------------------
-- fn_soma_secao — soma das contas-folha de uma SEÇÃO, para quando o documento
-- não traz linha de total (cabeçalho sem valor é convenção comum: "RECEITA
-- OPERACIONAL BRUTA" seguida das contas de venda).
--
-- Somar seção é fácil de errar por excesso. Três exclusões, todas necessárias e
-- descobertas testando contra o book:
--   (a) a linha cujo rótulo É o nome da seção — é o total impresso dela;
--   (b) linhas de "total"/"subtotal";
--   (c) `p_exclui_secao` — seções IRMÃS que casariam com os mesmos termos.
--       Concreto: termos ['receita','bruta'] casam tanto "RECEITA OPERACIONAL
--       BRUTA" quanto "DEDUÇÕES DA RECEITA BRUTA", e somar as duas dá a receita
--       líquida disfarçada de bruta.
--   (d) `p_exclui_chave` — ÂNCORAS DE CASCATA. Numa DRE, "RECEITA OPERACIONAL
--       LÍQUIDA" e "LUCRO BRUTO" são somas corridas que o layout imprime dentro
--       do bloco anterior; herdam a `secao` dele e inflariam a soma. Elas não
--       são pegas pelo teste de "valor igual à soma dos irmãos" porque acumulam
--       de uma base diferente.
-- Devolve também a escala predominante entre as linhas somadas.
-- -----------------------------------------------------------------------------
create or replace function fn_soma_secao(
  p_documento_versao_id uuid,
  p_termos_secao text[],
  p_entidade_coluna text default null,
  p_periodo_coluna text default null,
  p_exclui_secao text[] default '{}',
  p_exclui_chave text[] default '{}'
)
returns table (soma numeric, n_linhas int, unidade text)
language sql
stable
as $$
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

-- -----------------------------------------------------------------------------
-- fn_documento_balanco — o documento que serve como Balanço Patrimonial da
-- entidade/período. Aceita BALANCO, COMBINADO e BALANCETE (nessa preferência):
-- um balanço combinado É um balanço, e um balancete analítico fechado também
-- responde Ativo = Passivo + PL. Períodos compatíveis (0022) são aceitos.
-- -----------------------------------------------------------------------------
create or replace function fn_documento_balanco(
  p_caso_id uuid, p_entidade_id uuid, p_periodo_id uuid
)
returns uuid
language sql
stable
as $$
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

-- -----------------------------------------------------------------------------
-- fn_documento_por_tipo — lookup padrão de um documento por tipo, com período
-- compatível. Fatorado porque as 4 checagens repetiam o mesmo predicado.
-- -----------------------------------------------------------------------------
create or replace function fn_documento_por_tipo(
  p_caso_id uuid, p_entidade_id uuid, p_periodo_id uuid, p_tipo text
)
returns uuid
language sql
stable
as $$
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

-- -----------------------------------------------------------------------------
-- fn_anos_alvo — os anos a reconciliar para um período. Quando o período não
-- ancora ano (ex.: "L24M"), devolve {null} para a checagem rodar uma vez sem
-- filtro de coluna, como antes.
-- -----------------------------------------------------------------------------
create or replace function fn_anos_alvo(p_periodo_id uuid)
returns int[]
language plpgsql
stable
as $$
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

-- -----------------------------------------------------------------------------
-- fn_registrar_reconciliacao — registro unificado (Classe A e B) com a REGRA
-- NOVA de pendência:
--   p_resultado = 'ok'                          → resolve pendência aberta
--   p_resultado = 'documento_ausente'           → registra e NÃO abre pendência
--                                                 (é trabalho do checklist do
--                                                 Kit Básico, não da revisão);
--                                                 resolve pendência antiga.
--   p_resultado = 'precondicao_nao_satisfeita'  → abre pendência (documento
--                                                 presente, dado não localizado)
--   'divergente' | 'zona_cinzenta'              → abre pendência
-- Substitui `fn_registrar_reconciliacao_b` (0015), que fica como wrapper.
-- -----------------------------------------------------------------------------
create or replace function fn_registrar_reconciliacao(
  p_caso_id       uuid,
  p_entidade_id   uuid,
  p_periodo_id    uuid,
  p_tipo          text,
  p_classe        text,
  p_documento_id  uuid,
  p_fonte_a       jsonb,
  p_fonte_b       jsonb,
  p_resultado     text,
  p_divergencia_abs numeric,
  p_divergencia_pct numeric,
  p_materialidade jsonb,
  p_descricao     text
)
returns jsonb
language plpgsql
as $$
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

-- Wrapper: mantém a assinatura de 0015 para quem já chamava.
create or replace function fn_registrar_reconciliacao_b(
  p_caso_id uuid, p_entidade_id uuid, p_periodo_id uuid, p_tipo text,
  p_documento_id uuid, p_fonte_a jsonb, p_fonte_b jsonb, p_resultado text,
  p_divergencia_abs numeric, p_divergencia_pct numeric, p_materialidade jsonb,
  p_descricao text
)
returns jsonb
language sql
as $$
  select fn_registrar_reconciliacao(p_caso_id, p_entidade_id, p_periodo_id, p_tipo, 'B',
    p_documento_id, p_fonte_a, p_fonte_b, p_resultado, p_divergencia_abs,
    p_divergencia_pct, p_materialidade, p_descricao);
$$;

-- =============================================================================
-- A.1 — Ativo Total = Passivo + PL, uma vez por ANO declarado no período.
-- =============================================================================
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

    select * into v_ativo from fn_valor_conceito_col(v_versao,
      array['ativo', 'total'], array['circulante', 'nao circulante'], v_col_ent, v_col_per);
    if v_ativo.id is null then
      -- Sem linha "TOTAL DO ATIVO": soma as contas da seção ATIVO.
      select * into v_soma from fn_soma_secao(v_versao, array['ativo'], v_col_ent, v_col_per,
        array['passivo', 'patrimonio'], array['total do ativo']);
      v_esq := case when coalesce(v_soma.n_linhas, 0) > 0 then v_soma.soma end;
    else
      v_esq := v_ativo.valor_num;
    end if;

    select * into v_passivo_pl from fn_valor_conceito_col(v_versao,
      array['passivo', 'patrimonio', 'total'], array['circulante'], v_col_ent, v_col_per);
    if v_passivo_pl.id is not null then
      v_dir := v_passivo_pl.valor_num;
    else
      select * into v_passivo from fn_valor_conceito_col(v_versao,
        array['passivo', 'total'], array['patrimonio', 'circulante', 'nao circulante'],
        v_col_ent, v_col_per);
      select * into v_pl from fn_valor_conceito_col(v_versao,
        array['patrimonio', 'liquido', 'total'], array['circulante'], v_col_ent, v_col_per);
      if v_passivo.id is not null and v_pl.id is not null then
        v_dir := v_passivo.valor_num + v_pl.valor_num;
      else
        select * into v_soma from fn_soma_secao(v_versao,
          array['passivo', 'patrimonio'], v_col_ent, v_col_per,
          '{}', array['total do passivo']);
        v_dir := case when coalesce(v_soma.n_linhas, 0) > 0 then v_soma.soma end;
      end if;
    end if;

    if v_esq is null or v_dir is null then
      continue; -- este ano não tem os dois lados; tenta o próximo
    end if;

    v_n_anos := v_n_anos + 1;
    v_div_abs := abs(v_esq - v_dir);
    v_tol := greatest(p_tolerancia_abs, abs(v_esq) * p_tolerancia_pct);
    if v_div_abs > v_tol then
      v_resultado := 'divergente';
      v_partes := v_partes || format('%s: Ativo %s vs Passivo+PL %s (diferença de %s)',
        coalesce(v_ano::text, 'período do documento'), v_esq, v_dir, v_div_abs);
      if v_pior_abs is null or v_div_abs > v_pior_abs then
        v_pior_abs := v_div_abs;
        v_pior_pct := case when v_esq <> 0 then v_div_abs / abs(v_esq) end;
      end if;
    else
      v_partes := v_partes || format('%s: confere (Ativo %s = Passivo+PL %s)',
        coalesce(v_ano::text, 'período do documento'), v_esq, v_dir);
    end if;
    v_fonte_a := jsonb_build_object('chave', coalesce(v_ativo.chave, 'soma da seção ATIVO'),
      'valor', v_esq, 'ano', v_ano, 'documento_versao_id', v_versao);
    v_fonte_b := jsonb_build_object('valor', v_dir, 'ano', v_ano, 'documento_versao_id', v_versao);
  end loop;

  if v_n_anos = 0 then
    return fn_registrar_reconciliacao(p_caso_id, p_entidade_id, p_periodo_id,
      'ativo_passivo_pl', 'A', v_doc_id, null, null, 'precondicao_nao_satisfeita', null, null,
      jsonb_build_object('tolerancia_abs', p_tolerancia_abs, 'tolerancia_pct', p_tolerancia_pct),
      'O Balanço foi encontrado, mas não foi possível localizar nem a linha de Ativo Total / '
      || 'Passivo+PL nem contas de seção suficientes para somá-los (rótulos extraídos não '
      || 'bateram com os padrões esperados).');
  end if;

  v_desc := format('Ativo Total vs Passivo+Patrimônio Líquido em %s ano(s): %s.',
                   v_n_anos, array_to_string(v_partes, '; '));

  return fn_registrar_reconciliacao(p_caso_id, p_entidade_id, p_periodo_id,
    'ativo_passivo_pl', 'A', v_doc_id, v_fonte_a, v_fonte_b, v_resultado,
    v_pior_abs, v_pior_pct,
    jsonb_build_object('tolerancia_abs', p_tolerancia_abs, 'tolerancia_pct', p_tolerancia_pct,
                       'anos_checados', v_n_anos),
    v_desc);
end;
$$;

-- =============================================================================
-- A.2 — Caixa/equivalentes do Balanço = Saldo final do Fluxo de Caixa.
-- =============================================================================
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

-- =============================================================================
-- B.1 — Receita Bruta da DRE vs soma do faturamento mensal do ano.
-- =============================================================================
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

-- =============================================================================
-- B.2 — Despesa Financeira da DRE vs juros do Mapa de Dívida.
-- Aqui a conversão de escala é a correção principal: no book, o mapa de dívida
-- está em REAIS e a DRE em MILHARES, de propósito.
-- =============================================================================
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

-- =============================================================================
-- fn_reconciliar_por_documento — mesma assinatura. O laço de períodos
-- candidatos da 0022 sai: cada checagem agora resolve período compatível e
-- coluna internamente, e roda por ano. O laço gerava uma linha em
-- `reconciliacao` por período candidato quando a pré-condição falhava (8 linhas
-- para 4 pendências no v25) — ruído puro na trilha de auditoria.
-- =============================================================================
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
begin
  select caso_id, entidade_id, periodo_id, tipo_taxonomia
    into v_caso_id, v_entidade_id, v_periodo_id, v_tipo
  from documento where id = p_documento_id;

  if v_caso_id is null then
    return jsonb_build_object('executado', false, 'motivo', 'documento não encontrado');
  end if;

  if v_tipo in ('BALANCO', 'BALANCETE', 'COMBINADO') then
    v_checagens := v_checagens || jsonb_build_array(
      fn_reconciliar_ativo_passivo_pl(v_caso_id, v_entidade_id, v_periodo_id));
  end if;
  if v_tipo in ('BALANCO', 'BALANCETE', 'COMBINADO', 'FLUXO_CAIXA') then
    v_checagens := v_checagens || jsonb_build_array(
      fn_reconciliar_caixa_bp_fluxo(v_caso_id, v_entidade_id, v_periodo_id));
  end if;
  if v_tipo in ('DRE', 'FATURAMENTO_24M') then
    v_checagens := v_checagens || jsonb_build_array(
      fn_reconciliar_receita_dre_vs_faturamento(v_caso_id, v_entidade_id, v_periodo_id));
  end if;
  if v_tipo in ('DRE', 'MAPA_DIVIDA') then
    v_checagens := v_checagens || jsonb_build_array(
      fn_reconciliar_despfin_dre_vs_divida(v_caso_id, v_entidade_id, v_periodo_id));
  end if;

  return jsonb_build_object('executado', true, 'documento_id', p_documento_id,
                            'checagens', v_checagens);
end;
$$;

comment on function fn_reconciliar_por_documento(uuid) is
  'Dispara as checagens A/B pertinentes ao tipo do documento. Ausência do documento par NÃO abre pendência (é do checklist do Kit Básico).';
