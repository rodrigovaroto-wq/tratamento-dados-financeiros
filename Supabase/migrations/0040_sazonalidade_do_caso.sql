-- =============================================================================
-- Migration 0040 — Sazonalidade DERIVADA do histórico do próprio caso
--
-- Decisão do dono (7.5): a curva mensal não é digitada — sai do faturamento
-- mensal que o próprio mandato entregou. O `FATURAMENTO_24M` é obrigatório no Kit
-- Básico e vem mês a mês, então a curva real da empresa já está no banco; pedir
-- para alguém digitar 12 percentuais seria pedir para reproduzir à mão um número
-- que o documento já afirma.
--
-- POR QUE ISTO É FUNÇÃO, E NO BANCO: a curva é derivada de `campo_extraido`, e
-- quem sabe quais linhas existem é o banco — a mesma razão de
-- `fn_aplicar_premissa_em_lote` (0038) e `fn_linhas_para_modelagem` (0039).
--
-- AUSÊNCIA É AUSÊNCIA. Sem documento de faturamento mensal, a função devolve
-- ZERO LINHAS — e o gerador do modelo deixa a linha sem distribuição mensal,
-- dizendo por quê. A alternativa seria ratear 1/12 por mês, e um duodécimo
-- uniforme é um número que ninguém escolheu: numa empresa de varejo, ele move
-- caixa de dezembro para março e a necessidade de capital de giro sai errada
-- justamente no mês que importa.
-- =============================================================================

create or replace function fn_sazonalidade_do_caso(p_caso_id uuid)
returns table (mes int, fracao numeric, n_observacoes bigint)
language sql
stable
as $$
  with mensal as (
    select
      -- O mês vem do RÓTULO da linha ("jan/2024"), que é como o documento
      -- imprime. Os três primeiros caracteres normalizados bastam e cobrem
      -- "jan", "Jan", "JAN" e "janeiro".
      case left(fn_normalizar_texto(ce.chave), 3)
        when 'jan' then 1  when 'fev' then 2  when 'mar' then 3
        when 'abr' then 4  when 'mai' then 5  when 'jun' then 6
        when 'jul' then 7  when 'ago' then 8  when 'set' then 9
        when 'out' then 10 when 'nov' then 11 when 'dez' then 12
      end as mes,
      abs(ce.valor_num) as valor
    from campo_extraido ce
    join documento_versao dv on dv.id = ce.documento_versao_id
    join documento d on d.id = dv.documento_id
    where d.caso_id = p_caso_id
      and d.tipo_taxonomia = 'FATURAMENTO_24M'
      and ce.valor_num is not null
      -- A linha de TOTAL não é um mês, e é o `case` acima que a exclui: "tot" não
      -- casa com mês nenhum, então `mes` fica null e o `where mes is not null`
      -- adiante a descarta. Este filtro é REDUNDANTE de propósito (defesa em
      -- profundidade para um rótulo como "Total jan-dez"), e está anotado como
      -- redundante para ninguém escrever um teste que acredite estar provando ele
      -- — foi o que aconteceu na primeira versão do teste desta função.
      and fn_normalizar_texto(ce.chave) not like 'total%'
  ),
  somado as (
    select mes, sum(valor) as valor, count(*) as n
    from mensal where mes is not null
    group by mes
  ),
  total as (select sum(valor) as t from somado)
  select s.mes,
         -- Fração do ano. Soma 1 por construção, e é isso que o gerador
         -- multiplica pelo valor anual da linha.
         case when t.t is null or t.t = 0 then null else s.valor / t.t end as fracao,
         s.n as n_observacoes
  from somado s cross join total t
  -- Só devolve curva COMPLETA: 12 meses ou nada. Curva parcial distribuiria o
  -- ano inteiro nos meses que existem, inflando cada um — pior que não ter curva.
  where (select count(*) from somado) = 12
  order by s.mes;
$$;

comment on function fn_sazonalidade_do_caso(uuid) is
  'Curva mensal (12 frações que somam 1) derivada do FATURAMENTO_24M do caso. Devolve ZERO linhas '
  'quando não há documento mensal ou quando a curva ficaria incompleta — ausência é ausência, e '
  'ratear 1/12 seria inventar um número que ninguém escolheu.';

grant execute on function fn_sazonalidade_do_caso(uuid) to authenticated;
