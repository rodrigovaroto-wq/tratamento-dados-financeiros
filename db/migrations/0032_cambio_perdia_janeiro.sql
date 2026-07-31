-- =============================================================================
-- 0032 — A variação anual do CÂMBIO perdia janeiro, todo ano
--
-- O DEFEITO. `fn_indice_macro_anual` (0025) calcula série de NÍVEL como a
-- variação entre a primeira e a última observação DENTRO do ano:
--
--     left join preferida ini on ini.data_ref = a.primeira_data   -- min DO ANO
--
-- Para a série 3698 (câmbio, fechamento MENSAL), a primeira observação do ano é
-- o fechamento de JANEIRO. Então o que era publicado como "variação de 2024"
-- era jan/2024 → dez/2024, e o movimento de dezembro/2023 para janeiro/2024
-- ficava fora da conta — todo ano, em silêncio.
--
-- A convenção correta para variação anual de um nível é entre FECHAMENTOS:
-- dez/(n−1) → dez/n. É o que qualquer relatório quer dizer com "o dólar subiu
-- X% em 2024", e é o que faz as variações anuais serem encadeáveis (o produto
-- das variações de 2023 e 2024 tem de dar a variação do biênio; com a base
-- errada, não dá).
--
-- QUANTO ERRA. Não é arredondamento. Em janeiro de 2025 o dólar caiu de 6,19
-- (fechamento de dez/2024) para 5,86: só esse mês vale −5,3 p.p., que somem da
-- variação do ano inteiro. Em janeiro de 2024 o movimento foi +2,5 p.p.. O
-- sinal do erro muda de ano para ano, então nem "erra sempre para o mesmo lado"
-- serve de consolo — e é a série que precifica dívida e receita em dólar.
--
-- O PRIMEIRO ANO DA SÉRIE. Sem o fechamento de dezembro anterior, não existe
-- variação anual — e é exatamente aí que a versão antiga inventava uma
-- (jan→dez). Agora o retorno sai NULL para esse ano: `meses` continua
-- preenchido (o ano tem observação, só não tem base de comparação), e quem lê
-- distingue "não dá para calcular" de "variou zero". Inventar a base seria
-- repetir o defeito com outra roupa.
--
-- SÉRIE DE TAXA NÃO MUDA. IPCA, IGP-M, INPC, Selic e CDI acumulam por
-- composição dentro do próprio ano; janeiro já está lá dentro. A correção é
-- cirúrgica no ramo `nivel`.
--
-- E A SUÍTE PROTEGIA O BUG: `db/test/macro.test.sql` afirmava a convenção
-- errada (esperava a variação jan→dez), então corrigir a função REPROVAVA o
-- teste. O teste foi corrigido junto, nesta mesma fatia — um invariante que
-- descreve o comportamento defeituoso é pior que nenhum, porque quem for
-- consertar acha que quebrou algo.
-- =============================================================================

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

comment on function fn_indice_macro_anual is
  'Retorno acumulado por ano-calendário. Série de TAXA acumula por composição; '
  'série de NÍVEL varia entre FECHAMENTOS (dez do ano anterior → dez do ano), '
  'e o primeiro ano da série sai com retorno NULL por não ter base. `meses` '
  'revela ano incompleto — incluí-lo numa média de 3/5/10 anos como ano cheio '
  'distorce a média.';

-- A função é recriada, então o grant da 0028 precisa ser reafirmado: um
-- `create or replace` mantém privilégios, mas esta migration também roda em
-- banco novo (db/test/run.sh aplica a sequência inteira), onde a 0028 já
-- passou. Reafirmar é idempotente e barato; descobrir em produção que a
-- consulta voltou a dar "permission denied" não é.
grant execute on function fn_indice_macro_anual(int) to authenticated;

-- -----------------------------------------------------------------------------
-- VERIFICAÇÃO EMBUTIDA — o mesmo padrão da 0028: a migration prova, no banco em
-- que roda, aquilo que ela afirma. Um caso mínimo com dois dezembros e um
-- janeiro que se move: se a base voltar a ser janeiro, o número muda e o
-- `raise exception` derruba a aplicação da migration.
-- -----------------------------------------------------------------------------
do $$
declare
  v_2025 numeric;
  v_2024 numeric;
begin
  insert into indice_macro_serie (codigo, nome, natureza, unidade, descricao)
  values ('__CHK_NIVEL', 'checagem 0032', 'nivel', 'R$', 'temporária — removida ao fim desta migration')
  on conflict (codigo) do nothing;

  -- dez/2024 = 100; jan/2025 = 110 (o mês que sumia); dez/2025 = 121.
  insert into indice_macro_obs (serie, fonte, data_ref, valor) values
    ('__CHK_NIVEL', 'BCB/SGS', date '2024-12-31', 100),
    ('__CHK_NIVEL', 'BCB/SGS', date '2025-01-31', 110),
    ('__CHK_NIVEL', 'BCB/SGS', date '2025-12-31', 121)
  on conflict do nothing;

  select retorno into v_2025 from fn_indice_macro_anual() where serie = '__CHK_NIVEL' and ano = 2025;
  select retorno into v_2024 from fn_indice_macro_anual() where serie = '__CHK_NIVEL' and ano = 2024;

  -- 121/100 − 1 = 21%. A versão antiga daria 121/110 − 1 = 10% — janeiro fora.
  if v_2025 is null or abs(v_2025 - 21) > 0.0001 then
    raise exception '0032: variação de 2025 deveria ser 21%% (dez/2024 → dez/2025), veio %', v_2025;
  end if;
  -- 2024 é o primeiro ano da série: sem base, sem variação.
  if v_2024 is not null then
    raise exception '0032: o primeiro ano da série não tem base e deveria vir NULL, veio %', v_2024;
  end if;

  delete from indice_macro_obs where serie = '__CHK_NIVEL';
  delete from indice_macro_serie where codigo = '__CHK_NIVEL';
  raise notice '0032 ok: variação anual de nível usa o fechamento do ano anterior (janeiro entra)';
end;
$$;
