-- =============================================================================
-- Migration 0044 — O valor de cada linha lógica POR EXERCÍCIO
--
-- POR QUE ISTO PRECISOU EXISTIR. `fn_linhas_para_modelagem` (0039/0042) devolve
-- `valor_ultimo`, e o comentário dela diz o que aquilo é: um número para o
-- analista RECONHECER a conta na tela, não para cálculo. O modelo institucional
-- (14 abas, três demonstrações) precisa da série: o balanço de 2024 E de 2025, a
-- receita de cada exercício realizado, porque é sobre a última coluna realizada
-- que a projeção se apoia e é a variação entre colunas que dá o dia de giro
-- implícito.
--
-- O ANO VEM DE `periodo_coluna`, não do período do documento: num balanço
-- comparativo o mesmo documento tem 2024 e 2025 lado a lado, e é a COLUNA que diz
-- de quem é o número. Quando a coluna não traz ano (documento de exercício único),
-- cai para a `referencia` do período do documento — nessa ordem, porque a coluna é
-- mais específica.
--
-- DUAS OCORRÊNCIAS NO MESMO (linha, ano) acontecem de verdade: a mesma conta
-- aparece no balanço sintético e no balancete analítico do mesmo exercício. Aqui a
-- regra é MAIOR MÓDULO, com o sinal preservado — o mesmo critério do
-- `valor_ultimo` da 0042, para a tela e o modelo não discordarem sobre qual
-- ocorrência representa a linha. Somar as duas dobraria a conta.
-- =============================================================================

create or replace function fn_ano_da_coluna(p_periodo_coluna text, p_referencia text)
returns int
language sql
immutable
as $$
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
$$;

comment on function fn_ano_da_coluna(text, text) is
  'Exercício de uma ocorrência: ano da coluna de período, senão da referência do período do '
  'documento, senão dois dígitos finais + 2000. A coluna vem primeiro porque num balanço '
  'comparativo é ela que diz de qual exercício é o número.';

-- -----------------------------------------------------------------------------
-- fn_valores_por_ano — a série histórica da linha lógica, POR ENTIDADE.
--
-- O FILTRO DE ENTIDADE NÃO É OPCIONAL NA PRÁTICA, e a primeira versão desta função
-- não o tinha. O resultado, medido contra o book do grupo Vertentes: "Ativo
-- Circulante" em 2024 devolveu 3.961 — o da VT Logística — enquanto a Metalúrgica
-- tinha 67.878 no mesmo exercício. Um modelo montado sobre isso teria o ativo de
-- uma empresa com o passivo de outra: um balanço que não existe em lugar nenhum,
-- com aparência de balanço.
--
-- Com `p_entidade` nulo a função devolve o caso INTEIRO, e isso continua sendo
-- útil (conferência), mas quem monta modelo tem de passar a entidade — e o
-- gerador do modelo institucional recusa rodar sem ela.
--
-- O casamento usa `fn_mesma_entidade` (0030), a MESMA função que a reconciliação
-- usa: num combinado o cabeçalho da coluna é apelido curto ("Metalúrgica") e a
-- razão social é a completa, e igualdade exata nunca casaria.
-- -----------------------------------------------------------------------------
create or replace function fn_valores_por_ano(p_caso_id uuid, p_entidade text default null)
returns table (
  rotulo_norm text,
  secao_canonica text,
  ano int,
  valor numeric,
  n_ocorrencias bigint
)
language sql
stable
as $$
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

comment on function fn_valores_por_ano(uuid, text) is
  'Valor de cada linha lógica (rótulo normalizado × seção) por EXERCÍCIO. Existe porque o modelo '
  'institucional precisa da série histórica, e fn_linhas_para_modelagem só devolve o último valor '
  '(que serve para reconhecer a conta na tela, não para cálculo). O filtro de ENTIDADE existe porque '
  'sem ele o grupo virava uma empresa que não existe: ativo de uma com passivo de outra.';

grant execute on function fn_ano_da_coluna(text, text) to authenticated;
grant execute on function fn_valores_por_ano(uuid, text) to authenticated;
