-- =============================================================================
-- Migration 0025 — Índices macroeconômicos (histórico + expectativa Focus)
--
-- Por quê: a aba de Modelagem projeta exercícios a partir de premissas, e as
-- premissas mais comuns de um plano de reestruturação são macro (inflação que
-- corrige receita e contratos, juro que define o custo da dívida). Hoje esse
-- número é digitado de memória. Aqui ele passa a vir de fonte oficial, com data
-- de coleta e conferido contra uma segunda fonte.
--
-- Duas tabelas porque são dois FATOS diferentes, e misturá-los seria o mesmo
-- erro de tratar previsão como histórico:
--   • `indice_macro_obs`          — o que ACONTECEU (série publicada, por mês).
--   • `indice_macro_expectativa`  — o que o mercado ESPERA (Focus, por ano).
-- A segunda é opinião mediana de ~150 instituições numa data — muda toda
-- semana. Sem `coletado_em` não dá para reproduzir uma projeção antiga, e um
-- modelo que não se reproduz não passa em diligência.
--
-- A observação é chaveada por (serie, data_ref, FONTE): guardar as duas fontes
-- é o que permite a conferência. Sobrescrever uma com a outra destruiria
-- justamente a evidência que autoriza chamar o dado de validado.
-- =============================================================================

create table if not exists indice_macro_serie (
  codigo         text primary key,
  nome           text not null,
  natureza       text not null check (natureza in ('taxa', 'nivel')),
  unidade        text not null,
  descricao      text,
  criado_em      timestamptz not null default now()
);

comment on column indice_macro_serie.natureza is
  'taxa = variação % do mês (o ano acumula por COMPOSIÇÃO); nivel = preço/estoque '
  'na data (o ano é o fechamento). Compor nível, ou somar taxa, é erro conceitual.';

insert into indice_macro_serie (codigo, nome, natureza, unidade, descricao) values
  ('IPCA',       'IPCA (IBGE)',                'taxa',  '% a.m.', 'Índice oficial de inflação ao consumidor.'),
  ('IGPM',       'IGP-M (FGV)',                'taxa',  '% a.m.', 'Índice geral de preços — aluguéis e contratos longos.'),
  ('INPC',       'INPC (IBGE)',                'taxa',  '% a.m.', 'Inflação de renda mais baixa — reajuste salarial.'),
  ('SELIC',      'Selic acumulada no mês',     'taxa',  '% a.m.', 'Juro básico efetivamente acumulado no mês.'),
  ('CDI',        'CDI acumulado no mês',       'taxa',  '% a.m.', 'Custo de dívida bancária / rendimento de aplicação.'),
  ('PIB',        'PIB total',                  'taxa',  '% a.a.', 'Crescimento real — só expectativa (Focus).'),
  ('CAMBIO_USD', 'Câmbio R$/US$ (venda)',      'nivel', 'R$',     'Taxa de câmbio de fechamento.')
on conflict (codigo) do nothing;

create table if not exists indice_macro_obs (
  id             uuid primary key default gen_random_uuid(),
  serie          text not null references indice_macro_serie(codigo),
  fonte          text not null,          -- 'BCB/SGS', 'IBGE/SIDRA'
  data_ref       date not null,          -- 1º dia do mês de competência
  valor          numeric not null,
  coletado_em    timestamptz not null default now(),
  unique (serie, fonte, data_ref)
);
create index if not exists idx_indice_macro_obs_serie_data on indice_macro_obs (serie, data_ref);

create table if not exists indice_macro_expectativa (
  id             uuid primary key default gen_random_uuid(),
  serie          text not null references indice_macro_serie(codigo),
  fonte          text not null default 'BCB/Focus',
  ano_ref        int  not null,
  mediana        numeric not null,
  media          numeric,
  respondentes   int,
  coletado_em    date not null,          -- data do boletim: a expectativa é datada
  registrado_em  timestamptz not null default now(),
  unique (serie, ano_ref, coletado_em)
);
create index if not exists idx_indice_macro_exp_serie_ano on indice_macro_expectativa (serie, ano_ref, coletado_em desc);

-- -----------------------------------------------------------------------------
-- Ingestão. Recebe o lote inteiro em JSON (o N8N manda o array já normalizado
-- por n8n/lib/macro.mjs) — mesma forma de `fn_registrar_campos_extraidos`.
-- Idempotente por (serie, fonte, data_ref): reprocessar não duplica, e um valor
-- REVISADO pela fonte sobrescreve o anterior (revisão de série é normal no IBGE
-- e é justamente o que se quer capturar).
-- -----------------------------------------------------------------------------
create or replace function fn_registrar_indice_macro(p_obs jsonb)
returns table (n_inseridas int, n_atualizadas int)
language plpgsql
as $$
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

create or replace function fn_registrar_expectativa_macro(p_exp jsonb)
returns int
language plpgsql
as $$
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

-- -----------------------------------------------------------------------------
-- Conferência entre fontes. Mesmo espírito da reconciliação Classe A: o fato
-- registrado é a checagem, e a divergência vira sinal — nunca uma correção
-- automática (não temos autoridade para decidir qual fonte está certa).
--
-- Tolerância em PONTOS PERCENTUAIS: os valores já são percentuais, e 0,01 p.p.
-- é arredondamento de publicação, não discordância. Mês presente em uma só das
-- fontes NÃO é divergência — o BCB publica antes do SIDRA consolidar.
-- -----------------------------------------------------------------------------
create or replace function fn_divergencias_indice_macro(p_tolerancia numeric default 0.011)
returns table (serie text, data_ref date, fonte_a text, valor_a numeric, fonte_b text, valor_b numeric, delta numeric)
language sql
stable
as $$
  select a.serie, a.data_ref, a.fonte, a.valor, b.fonte, b.valor, abs(a.valor - b.valor)
  from indice_macro_obs a
  join indice_macro_obs b
    on b.serie = a.serie and b.data_ref = a.data_ref and b.fonte > a.fonte
  where abs(a.valor - b.valor) > p_tolerancia
  order by a.data_ref desc, a.serie;
$$;

-- -----------------------------------------------------------------------------
-- Leitura para o export. Uma linha por (serie, ano) com o retorno ACUMULADO do
-- ano — composição, não soma: 12 meses de 1% dão 12,68%, não 12%.
--
-- `meses` sai junto de propósito: ano incompleto (o corrente) não pode entrar
-- numa média de 3/5/10 anos como se fosse cheio. Quem consome decide; a função
-- não esconde a informação nem descarta o ano.
--
-- A fonte preferida é o IBGE quando existe (é quem PRODUZ o IPCA/INPC); o BCB
-- entra como espelho para os meses que o SIDRA ainda não consolidou.
-- -----------------------------------------------------------------------------
create or replace function fn_indice_macro_anual(p_desde_ano int default null)
returns table (serie text, ano int, meses int, retorno numeric, natureza text)
language sql
stable
as $$
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
  -- primeiro e o último fechamento observado — compor níveis não faz sentido.
  por_ano as (
    select
      p.serie,
      extract(year from p.data_ref)::int as ano,
      count(*)::int                      as meses,
      (exp(sum(ln(1 + p.valor / 100.0))) - 1) * 100 as composto,
      min(p.data_ref)                    as primeira_data,
      max(p.data_ref)                    as ultima_data
    from preferida p
    where p_desde_ano is null or extract(year from p.data_ref)::int >= p_desde_ano
    group by p.serie, extract(year from p.data_ref)
  )
  select
    a.serie,
    a.ano,
    a.meses,
    case s.natureza
      when 'taxa' then a.composto
      else (fim.valor / nullif(ini.valor, 0) - 1) * 100
    end as retorno,
    s.natureza
  from por_ano a
  join indice_macro_serie s on s.codigo = a.serie
  left join preferida ini on ini.serie = a.serie and ini.data_ref = a.primeira_data
  left join preferida fim on fim.serie = a.serie and fim.data_ref = a.ultima_data
  order by a.serie, a.ano;
$$;

comment on function fn_indice_macro_anual is
  'Retorno acumulado por ano-calendário. Série de TAXA acumula por composição; '
  'série de NÍVEL varia entre fechamentos. `meses` revela ano incompleto — '
  'incluí-lo numa média de 3/5/10 anos como ano cheio distorce a média.';
