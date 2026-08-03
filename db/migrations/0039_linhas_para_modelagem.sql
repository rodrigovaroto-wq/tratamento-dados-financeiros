-- =============================================================================
-- Migration 0039 — As linhas do caso, para a tela de Modelagem
--
-- POR QUE ISTO É FUNÇÃO E NÃO CONSULTA NO PORTAL.
--
-- A tela de Modelagem (Fase 7.3) lista as linhas extraídas do caso para o
-- analista vincular premissa a cada uma. A primeira versão fazia isso com uma
-- consulta PostgREST direta em `campo_extraido` — e `campo_extraido` NÃO TEM
-- `caso_id`: o vínculo é `campo_extraido → documento_versao → documento`. Sem o
-- embed com `!inner` e o filtro no campo aninhado, a consulta trazia as linhas de
-- TODOS os mandatos para a tela de um.
--
-- Com a RLS aberta a qualquer autenticado (decisão registrada do dono em 31/07),
-- esse tipo de erro não é barrado por nada: a consulta traz o que pediu. O escopo
-- por caso passa a ser responsabilidade de UMA função, aqui, onde um teste SQL
-- pode provar que ela não vaza — em vez de depender de um `!inner` escrito certo
-- em cada consulta nova que alguém acrescentar à tela.
--
-- É o mesmo raciocínio de `fn_aplicar_premissa_em_lote` (0038): quem sabe quais
-- linhas existem é o banco.
-- =============================================================================

create or replace function fn_linhas_para_modelagem(p_caso_id uuid)
returns table (
  secao_canonica text,
  chave          text,
  rotulo_norm    text,
  entidade       text,
  valor_ultimo   numeric,
  n_ocorrencias  bigint
)
language sql
stable
as $$
  -- Uma linha por (seção canônica, rótulo normalizado): a tela configura a LINHA
  -- LÓGICA, não cada ocorrência por período/entidade. `valor_ultimo` é o maior
  -- valor absoluto encontrado — serve só para o analista RECONHECER a conta na
  -- lista, não para cálculo, e por isso é `max(abs())` e não uma soma (somar
  -- ocorrências de períodos diferentes daria um número que não existe em lugar
  -- nenhum, e número que não existe numa tela de modelagem é convite a erro).
  select
    ce.secao_canonica,
    -- O rótulo EXIBIDO é o mais frequente entre as ocorrências; o normalizado é a
    -- identidade. Assim a tela mostra a grafia do documento e grava a chave
    -- estável que `caso_linha_premissa` usa.
    (array_agg(ce.chave order by length(ce.chave)))[1] as chave,
    fn_normalizar_texto(ce.chave) as rotulo_norm,
    max(coalesce(ce.entidade_coluna, e.razao_social)) as entidade,
    max(abs(ce.valor_num)) as valor_ultimo,
    count(*) as n_ocorrencias
  from campo_extraido ce
  join documento_versao dv on dv.id = ce.documento_versao_id
  join documento d on d.id = dv.documento_id
  left join entidade e on e.id = d.entidade_id
  where d.caso_id = p_caso_id
    and ce.valor_num is not null
  group by ce.secao_canonica, fn_normalizar_texto(ce.chave)
  order by ce.secao_canonica nulls last, 3;
$$;

comment on function fn_linhas_para_modelagem(uuid) is
  'Linhas lógicas do caso (seção canônica × rótulo normalizado) para a tela de Modelagem vincular '
  'premissas. Existe como FUNÇÃO porque campo_extraido não tem caso_id — o escopo por caso mora '
  'aqui, num lugar que o teste cobre, em vez de depender de um join escrito certo em cada consulta.';

grant execute on function fn_linhas_para_modelagem(uuid) to authenticated;
