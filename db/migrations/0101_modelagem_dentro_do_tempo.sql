-- =============================================================================
-- Migration 0101 — A tela de Modelagem cabe dentro do tempo do Supabase
--
-- O QUE O DONO VIU, e por que ele foi levado a acreditar em outra coisa. A seção
-- 3 anunciou "Este caso ainda não tem linha extraída com valor" num caso com 760
-- ocorrências extraídas. A causa não era dado faltando nem migration não
-- aplicada: as funções ESTOURAM O `statement_timeout` do Supabase (8 s para o
-- papel `authenticated`), a chamada volta
--
--     canceling statement due to statement timeout
--
-- e a tela — que até a véspera engolia `.error` num `?? []` — mostrava isso como
-- lista vazia. O erro agora aparece escrito; esta migration tira o motivo dele.
--
-- MEDIDO, num caso do tamanho do v35 (14 documentos, 770 ocorrências):
--
--     fn_linhas_para_modelagem   2.350 ms
--     fn_conferir_modelagem      9.344 ms   ← acima do teto, sempre cancelada
--
-- SÃO DOIS DESPERDÍCIOS, e o segundo é de outra ordem de grandeza.
--
-- 1. `fn_linhas_para_modelagem` calcula `fn_papel_linha` DUAS VEZES por
--    ocorrência — uma no valor agregado e outra dentro do `order by` do mesmo
--    `array_agg`. E `fn_papel_linha` não é barata: normaliza o texto e roda uma
--    lista fechada de regex mais três `fn_rotulo_estrutural`. Além disso, a marca
--    de sobreposição era um `exists` CORRELACIONADO sobre a própria CTE: para
--    cada linha, varredura de todas as outras, com `fn_rotulo_contido` (que faz
--    `regexp_split_to_array` + `unnest`) avaliada no meio. É O(n²) de função cara.
--
-- 2. `fn_conferir_modelagem` chama `fn_linhas_para_modelagem` CINCO VEZES — e
--    duas delas dentro de um `exists` correlacionado, isto é, **uma vez por linha
--    vinculada**. Num caso com 200 vínculos isso é a função inteira, com o seu
--    O(n²), duzentas vezes. É daí que vêm os 9 segundos.
--
-- O QUE ESTA MIGRATION NÃO MUDA: nenhum resultado. Papel, valor com sinal,
-- unidade, documentos, marca de sobreposição e todos os campos da conferência
-- saem exatamente iguais — o teste da 0042 e o da 0100 continuam valendo sem uma
-- linha alterada, e é isso que prova que a otimização não comprou velocidade com
-- comportamento.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- fn_linhas_para_modelagem — mesmo resultado, o papel calculado UMA vez.
--
-- Duas mudanças, as duas de forma e nenhuma de regra:
--
--   • uma CTE `ocorrencia` calcula `fn_papel_linha` uma vez por linha extraída, e
--     o agrupamento passa a agregar esse valor já pronto;
--   • a sobreposição vira JOIN por igualdade (mesma seção, mesmo valor, ambos
--     'conta') e só depois avalia `fn_rotulo_contido`. O planejador consegue usar
--     hash join no par (seção, valor), então a função cara roda só nos pares que
--     de fato colidem em valor — que são poucos — em vez de em todos os pares.
-- -----------------------------------------------------------------------------
create or replace function fn_linhas_para_modelagem(p_caso_id uuid)
returns table (
  secao_canonica text,
  chave          text,
  rotulo_norm    text,
  entidade       text,
  valor_ultimo   numeric,
  n_ocorrencias  bigint,
  papel          text,
  unidade        text,
  moeda          text,
  documentos     text[],
  sobreposicao_suspeita boolean
)
language sql
stable
as $$
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
  ),
  -- O PAPEL É PROPRIEDADE DO RÓTULO, NÃO DA OCORRÊNCIA.
  --
  -- `fn_papel_linha` depende só de (chave, tipo do documento, unidade) e custa
  -- ~1,6 ms por chamada — ela normaliza o texto e roda uma lista fechada de regex
  -- mais nove `fn_rotulo_estrutural`, e para uma conta comum TODOS os ramos são
  -- percorridos até o `else`. Avaliá-la por ocorrência era pagar 770 vezes por
  -- uma resposta que só tem ~250 valores distintos: 1,27 s dos 2,5 s da função
  -- inteira, no caso do tamanho do v35.
  --
  -- Aqui ela roda uma vez por combinação distinta e o resultado volta por join.
  -- É a mesma resposta: a função é `immutable`, então entrada igual dá saída
  -- igual por definição — não é cache com risco de envelhecer.
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
  -- SOBREPOSIÇÃO SUSPEITA, agora por join. Mesma regra da 0042: outra linha da
  -- MESMA seção, MESMO valor, e um rótulo descrevendo o outro de forma mais
  -- grossa (`Provisões` × `Provisão para passivo a descoberto de controlada`).
  -- A função não escolhe por ninguém: MARCA, e quem decide é o analista.
  sobrepostas as (
    select distinct b.secao_canonica, b.rotulo_norm
    from base b
    join base o
      on coalesce(o.secao_canonica, '') = coalesce(b.secao_canonica, '')
     and o.valor_ultimo = b.valor_ultimo
     and o.rotulo_norm <> b.rotulo_norm
    where b.papel = 'conta' and o.papel = 'conta'
      and (fn_rotulo_contido(o.chave, b.chave) or fn_rotulo_contido(b.chave, o.chave))
  )
  select b.secao_canonica, b.chave, b.rotulo_norm, b.entidade, b.valor_ultimo,
         b.n_ocorrencias, b.papel, b.unidade, b.moeda, b.documentos,
         (s.rotulo_norm is not null) as sobreposicao_suspeita
  from base b
  left join sobrepostas s
    on s.rotulo_norm = b.rotulo_norm
   and coalesce(s.secao_canonica, '') = coalesce(b.secao_canonica, '')
  order by b.secao_canonica nulls last, b.rotulo_norm;
$$;

comment on function fn_linhas_para_modelagem(uuid) is
  'Linhas lógicas do caso para a tela de Modelagem, com PAPEL (conta/subtotal/derivado/'
  'serie_mensal), valor COM SINAL, unidade/moeda, documentos de origem e marca de sobreposição. '
  'Existe como função porque campo_extraido não tem caso_id — o escopo por caso mora aqui. '
  '0101: papel calculado uma vez por ocorrência e sobreposição por join, para caber no '
  'statement_timeout.';

grant execute on function fn_linhas_para_modelagem(uuid) to authenticated;

-- -----------------------------------------------------------------------------
-- fn_conferir_modelagem — UMA passada pelas linhas, não cinco.
--
-- Vira `language sql` com CTEs porque é assim que a lista fica materializada uma
-- vez e reutilizada por todos os agregados. Em plpgsql cada `select ... from
-- fn_linhas_para_modelagem(...)` é uma execução nova da função, e dois deles
-- estavam dentro de `exists` correlacionado — uma execução completa POR VÍNCULO.
--
-- O resultado é campo a campo o mesmo da 0042, incluindo os detalhes que custaram
-- a acertar: `linhas_com_premissa` conta por junção e só sobre linha PROJETÁVEL
-- (vínculo antigo apontando para subtotal não infla a cobertura), e o que não é
-- projetável fica NOMEADO por papel em vez de sumir da conta.
-- -----------------------------------------------------------------------------
create or replace function fn_conferir_modelagem(p_caso_id uuid)
returns jsonb
language sql
stable
as $$
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

comment on function fn_conferir_modelagem(uuid) is
  'Conferência da modelagem do caso. 0101: uma única passada por fn_linhas_para_modelagem '
  '(antes eram cinco, duas delas dentro de exists correlacionado — uma execução completa por '
  'vínculo), o que a tirava do statement_timeout do Supabase.';

grant execute on function fn_conferir_modelagem(uuid) to authenticated;

-- -----------------------------------------------------------------------------
-- Os auxiliares da 0042 que nasceram SEM grant.
--
-- `fn_mes_do_rotulo`, `fn_papel_linha`, `fn_rotulo_contido` e `fn_papel_prioridade`
-- foram criadas na 0042 e nenhuma recebeu `grant execute`. Hoje elas funcionam
-- porque o Postgres concede EXECUTE a `public` por padrão — ou seja, o sistema
-- depende de um default que qualquer endurecimento de permissão (o tipo de coisa
-- que a 0028 já fez uma vez neste banco) desligaria, e a falha apareceria como
-- "a tela de Modelagem parou", não como "faltou um grant".
--
-- Declarar o grant é barato e tira o sistema de cima de um default.
-- -----------------------------------------------------------------------------
grant execute on function fn_mes_do_rotulo(text) to authenticated;
grant execute on function fn_papel_linha(text, text, text) to authenticated;
grant execute on function fn_rotulo_contido(text, text) to authenticated;
grant execute on function fn_papel_prioridade(text) to authenticated;
grant execute on function fn_sazonalidade_do_caso(uuid) to authenticated;
