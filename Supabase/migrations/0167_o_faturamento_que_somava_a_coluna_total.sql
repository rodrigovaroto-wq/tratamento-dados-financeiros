-- =============================================================================
-- 0167 — O faturamento somava a coluna "Total" JUNTO das categorias
--
-- CAUSA RAIZ, MEDIDA CÉLULA A CÉLULA no export do caso "teste 143" — e ela
-- CORRIGE uma hipótese errada que uma sessão anterior tinha registrado (a de
-- que o problema era sobreposição de datas entre dois arquivos de faturamento).
-- Não era. É um documento só.
--
-- O que o painel do dono mostrava:
--
--     "2024: Receita Bruta 74.160.836,36 vs 48 MESES de faturamento
--      144.872.009,06 — diferença de 70.711.172,70"
--
-- Quarenta e oito meses num ano. O número não é um erro de digitação: é o que a
-- função de fato contou.
--
-- O FORMATO DO DOCUMENTO. `GENERAL TABACO - FATURAMENTO 2024.pdf` é uma tabela
-- de 12 linhas (uma por mês) e QUATRO colunas de valor:
--
--     M Ê S      ANO    Saídas R$   Serviços R$   Outros R$   Total R$
--     Janeiro    2024   4.018.139,19      0,00        0,00    4.018.139,19
--     …
--
-- A extração grava CADA CÉLULA como uma linha de `campo_extraido`, com o MÊS na
-- `chave` e a CATEGORIA em `periodo_coluna`:
--
--     chave='Janeiro 2024'  periodo_coluna='Saídas R$'    valor=4.018.139,19
--     chave='Janeiro 2024'  periodo_coluna='Serviços R$'  valor=0
--     chave='Janeiro 2024'  periodo_coluna='Outros R$'    valor=0
--     chave='Janeiro 2024'  periodo_coluna='Total R$'     valor=4.018.139,19
--
-- O DEFEITO. `fn_somar_faturamento_ano` filtra por ano casando a `chave`, e
-- exclui as linhas de total com `fn_normalizar_texto(ce.chave) not like
-- '%total%'`. Mas a palavra "total" não está na CHAVE — está em
-- `periodo_coluna`. A exclusão nunca casa, e as QUATRO células de cada mês
-- entram na soma. 12 meses × 4 categorias = **48 "meses"**, exatamente o número
-- da mensagem. E como `Total = Saídas + Serviços + Outros` por construção, a
-- soma sai em DOBRO do faturamento real.
--
-- CONFERÊNCIA ARITMÉTICA, no caso real: Receita Bruta da DRE 74.160.836,36 × 2 =
-- 148.321.672,72 contra os 144.872.009,06 somados — bate em 97,7%, e o resíduo
-- de 2,3% é a diferença legítima de competência/recorte que a própria mensagem
-- da checagem já chama de "Classe B". Ou seja: tirada a duplicação, a
-- divergência que sobra é a que o contador esperaria.
--
-- A CORREÇÃO: agrupar por RÓTULO (o mês) antes de somar. Dentro de cada mês, se
-- existe uma célula cuja `periodo_coluna` diz "total", ela é a resposta — as
-- outras são a decomposição dela. Sem coluna de total (documento que só traz a
-- quebra por categoria), soma-se o que houver, que é o comportamento de hoje.
--
-- E O `n_linhas` PASSA A CONTAR MESES DE VERDADE. Ele é usado na mensagem como
-- "%s meses de faturamento" — dizer "48 meses" sobre um relatório de 12 era
-- mentira sobre a UNIDADE, não só sobre o valor. Agrupado por rótulo, ele conta
-- 12.
--
-- O QUE NÃO MUDA: o filtro de ANO (casamento por `chave`), as exclusões de
-- "acumulado" e "média", e o formato de faturamento que traz UM valor por mês
-- sem quebra por categoria — nesse, cada mês é um grupo de uma célula só, e a
-- soma do grupo é a própria célula. O book-vertentes é desse formato, e o
-- `reconciliacao.test.sql` prova que ele não mexeu.
--
-- Idempotente: `create or replace`.
-- =============================================================================

begin;

create or replace function fn_somar_faturamento_ano(
  p_documento_versao_id uuid,
  p_ano4 text,
  p_ano2 text
)
returns table(soma numeric, n_linhas integer)
language sql
stable
as $_$
  with candidatos as (
    select ce.chave, ce.periodo_coluna, ce.valor_num
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
      and fn_normalizar_texto(ce.chave) not like '%médi%'
  ),
  -- UM VALOR POR MÊS, e é aqui que mora a correção. A categoria
  -- (Saídas/Serviços/Outros/Total) mora em `periodo_coluna`, não na `chave` —
  -- a chave repete o MESMO mês nas quatro células. Se o mês tem uma célula de
  -- TOTAL, ela é a resposta; as outras três são a decomposição dela, e somar as
  -- quatro conta o mesmo dinheiro duas vezes.
  por_rotulo as (
    select
      chave,
      coalesce(
        max(valor_num) filter (where fn_normalizar_texto(periodo_coluna) like '%total%'),
        sum(valor_num)
      ) as valor
    from candidatos
    group by chave
  )
  select coalesce(sum(valor), 0)::numeric, count(*)::int from por_rotulo;
$_$;

comment on function fn_somar_faturamento_ano(uuid, text, text) is
  'Soma o faturamento de um ano, UM VALOR POR MÊS. 0167: a categoria mora em periodo_coluna '
  '(Saídas/Serviços/Outros/Total) e a chave repete o mês nas quatro — somar tudo dava 48 '
  '"meses" num relatório de 12 e o dobro do faturamento. Com coluna de total, ela manda; sem '
  'ela, soma-se a quebra.';

-- -----------------------------------------------------------------------------
-- O CATÁLOGO DA SONDA — requisito de CORPO sobre `por_rotulo`.
--
-- É o nome da CTE que carrega a correção: sem ela a função volta a somar célula
-- a célula. Identificador estrutural, não comentário — um `create or replace`
-- com o corpo velho o apaga, e a sonda vê.
-- -----------------------------------------------------------------------------
insert into instalacao_requisito
  (chave, migration, tipo, objeto, marcador, criterio_seed, porque, severidade, ordem) values
  ('faturamento_um_valor_por_mes', '0167', 'corpo', 'fn_somar_faturamento_ano',
   'por_rotulo', null,
   'Sem esta migration o faturamento anual é somado célula a célula, e um relatório mensal com '
   'as colunas Saídas/Serviços/Outros/Total soma o DOBRO do faturamento real (a coluna Total já '
   'é a soma das outras três). Medido no lote do caso "teste 143": 48 "meses" contados num ano, '
   'e a checagem contra a Receita Bruta da DRE abriu divergência em toda entidade do grupo.',
   'bloqueante', 650)
on conflict (chave) do update set
  migration = excluded.migration, tipo = excluded.tipo, objeto = excluded.objeto,
  marcador = excluded.marcador, criterio_seed = excluded.criterio_seed,
  porque = excluded.porque, severidade = excluded.severidade, ordem = excluded.ordem;

update instalacao_cobertura
   set ate_migration = '0167', revisado_em = current_date,
       observacao = 'A 0167 muda o corpo de fn_somar_faturamento_ano e nada mais — requisito de '
                    'corpo (por_rotulo) basta. O comportamento é provado no CI '
                    '(faturamento_por_mes.test.sql), com a forma de tabela do relatório real.';

commit;
