-- 0152 — A RECONCILIAÇÃO DO LOTE NÃO É A DO DOCUMENTO REPETIDA 190 VEZES.
--
-- MEDIDO NA RODADA REAL DO `book-araucaria` (27/08/2026, execução 7172): 190
-- documentos, 13.942 linhas, e a execução ficou **1h52 de pé sem gravar uma
-- única reconciliação**, até ser cancelada à mão. Nenhum erro em lugar nenhum —
-- nem no Postgres, nem no n8n, nem na tela.
--
-- O QUE EU VI AO VIVO, e é a prova de que não era lentidão difusa:
--
--   pg_stat_activity, 22:16 UTC
--     backend 81532, ativo há 13min25, RowExclusiveLock em reconciliacao
--     query: select fn_reconciliar_por_documento('661f…'); select … (11 statements)
--     xact_start = query_start  → batch multi-statement = UMA transação implícita
--   22:23 UTC
--     backend sumiu, e reconciliacao do caso = 0 linhas  → rollback
--     backend NOVO, com 2 statements, rodando de novo
--
-- NÃO SEI DIZER se o segundo backend é retentativa ou o lote seguinte, e a
-- diferença de tamanho (11 statements contra 2) sugere que é o seguinte. Fica
-- escrito assim de propósito: o que MEDI foi a transação implícita, os locks de
-- escrita, e o zero commitado depois de 1h52 — não o mecanismo do n8n por
-- dentro, que eu não tinha como observar daqui.
--
-- E o EXPLAIN ANALYZE de UMA chamada de `fn_conflitos_do_caso`, na entidade de
-- um documento só:
--
--     Nested Loop  (actual time=9612..12350 rows=34)
--       Rows Removed by Join Filter: 6.859.127
--       CTE com_autoridade  (cost rows=1) (actual rows=2619)
--       SubPlan 1/2/3 … loops=3488 + 7149 + 7148
--     Execution Time: 12357 ms
--
-- 12,4 SEGUNDOS. E `fn_reconciliar_versoes_do_periodo` é chamada uma vez por
-- documento de nove tipos — **123 dos 190**. 25 minutos só nela.
--
-- ---------------------------------------------------------------------------
-- MAS O DEFEITO NÃO É DA 0151, E ISSO IMPORTA MAIS QUE O NÚMERO
-- ---------------------------------------------------------------------------
--
-- A 0151 foi a gota, não a causa. Contei as chaves do caso araucária:
--
--     190 documentos  →  82 pares (entidade, período) distintos
--
-- E as checagens do despachante NÃO LEEM O DOCUMENTO. Elas leem
-- (caso, entidade, período) — o documento só entrega a chave:
--
--     fn_reconciliar_ativo_passivo_pl(caso, entidade, periodo)
--     fn_reconciliar_caixa_bp_fluxo (caso, entidade, periodo)
--     fn_reconciliar_receita_dre_vs_faturamento(caso, entidade, periodo)
--     fn_reconciliar_despfin_dre_vs_divida(caso, entidade, periodo)
--     fn_reconciliar_mutuos    (caso, periodo)
--     fn_reconciliar_intragrupo(caso, periodo)
--     fn_reconciliar_duplicidade(caso, entidade)
--     fn_reconciliar_versoes_do_periodo(caso, entidade)
--
-- Então DOIS documentos com a mesma (entidade, período) produzem laços byte a
-- byte idênticos. No araucária a Araucária Serraria tem **80 documentos**: as
-- mesmas checagens rodaram 80 vezes, com os mesmos argumentos, gravando 80
-- linhas iguais em `reconciliacao`. A única checagem que é de fato POR
-- DOCUMENTO é `fn_reconciliar_arvore` — a árvore é intra-documento, e a 0133 já
-- diz isso em comentário.
--
-- Isso não apareceu em 38 documentos porque 38 documentos custam 38× pouco.
-- É o mesmo formato de defeito que este repositório já nomeou: **a conta certa
-- para o lote em que ela foi calibrada.**
--
-- O PIOR CASO ANTES DESTA MIGRATION, contado no araucária: 87 documentos
-- disparam Classe A × até 20 períodos no laço = 1.740 chamadas de
-- `fn_reconciliar_ativo_passivo_pl` para 82 pares que existem. Somando as oito
-- checagens: ~8.500 invocações e ~8.500 linhas de `reconciliacao` para um caso
-- que tem 82 chaves.
--
-- ---------------------------------------------------------------------------
-- OS TRÊS MOVIMENTOS
-- ---------------------------------------------------------------------------
--
--   1. `fn_conflitos_do_caso` deixa de ser quadrática — o par passa a nascer
--      DEPOIS do agrupamento, e não do produto cartesiano;
--   2. o ESCOPO passa a ser declarado: `fn_reconciliar_por_documento` ganha
--      `p_escopo`, e o padrão continua `'tudo'` (nada que já chamava muda);
--   3. `fn_reconciliar_caso` roda cada checagem uma vez por CHAVE.
--
-- A DEDUPLICAÇÃO É PROVADAMENTE SEM PERDA, e o argumento é curto: os
-- argumentos de cada checagem são (caso, entidade, período) e o gate do tipo.
-- Dois documentos que compartilham a chave e o gate entregam os mesmos
-- argumentos. Rodar duas vezes não produz achado novo — produz a mesma linha
-- duas vezes. O teste `reconciliacao_do_lote.test.sql` prova isso comparando o
-- CONJUNTO de resultados das duas formas.

-- =============================================================================
-- 1. `fn_conflitos_do_caso` — o par nasce depois do agrupamento
-- =============================================================================
--
-- QUATRO CAUSAS, cada uma lida no plano e cada uma com a sua correção:
--
-- (a) O SELF-JOIN ERA UM CARTESIANO. `com_autoridade` é CTE usada duas vezes,
--     então é materializada — e o planner não tem estatística de CTE: estimou
--     `rows=1` onde havia 2.619. Com 1×1, Nested Loop é o plano mais barato, e
--     ele comparou 2.619 × 2.619 = 6,86 milhões de pares para achar 34.
--
--     A correção não é forçar plano (que envelhece com o dado): é NÃO PEDIR o
--     produto. Conflito exige o mesmo conceito em DOIS documentos, e a
--     esmagadora maioria dos conceitos aparece em UM. Agrupando primeiro por
--     (seção, rótulo, entidade, exercício), sobram só os grupos com mais de um
--     documento E com dispersão acima da tolerância — e só ESSES viram par.
--
--     O PRÉ-FILTRO É CONSERVADOR POR CONSTRUÇÃO, e isto é o que o torna
--     seguro: o limiar do par é `greatest(tol_abs, |a| * tol_pct)`, que é
--     SEMPRE >= `tol_abs`. Então todo par verdadeiro tem |a−b| > tol_abs, e
--     |a−b| <= max−min do grupo. Logo `max−min > tol_abs` não descarta par
--     nenhum. O predicado completo continua sendo aplicado no par, intacto —
--     o pré-filtro só evita construir o par que não pode passar.
--
-- (b) A SUBCONSULTA DA CAPA (0146) ERA AVALIADA TRÊS VEZES POR LINHA. Ela
--     aparecia no SELECT e, por inlining do filtro, mais duas vezes no WHERE:
--     `loops=3488 + 7149 + 7148` = 17.785 varreduras de índice numa função que
--     responde uma pergunta por DOCUMENTO_VERSAO. Vira CTE própria, com uma
--     linha por versão.
--
-- (c) A AUTORIDADE ERA CALCULADA POR GRUPO, não por documento. `cross join
--     lateral fn_autoridade_do_documento(pd.documento_id)` rodava 2.619 vezes
--     para 190 documentos — e cada chamada faz três joins e mais uma
--     `fn_versao_com_extracao`. Vira CTE por documento.
--
-- (d) `fn_papel_linha` É IMUTÁVEL E CUSTAVA 4,8 s. No plano ela é Join Filter
--     com 8.729 avaliações a ~0,6 ms cada. O Postgres não memoiza função
--     imutável entre linhas, mas o argumento é (chave, tipo, unidade) e esses
--     se repetem muito num book: **8.729 linhas para 1.139 triplas distintas.**
--     Avaliada uma vez por tripla.
--
-- (e) `fn_mesma_entidade` É PLPGSQL E TINHA O MESMO FORMATO: 10.570 linhas para
--     **40 strings de entidade distintas**. Mesma correção.
--
-- ---------------------------------------------------------------------------
-- E O `MATERIALIZED` NÃO É ENFEITE — SEM ELE A CORREÇÃO NÃO ACONTECE
-- ---------------------------------------------------------------------------
--
-- ESCREVI ESTA FUNÇÃO SEM `MATERIALIZED` PRIMEIRO, E MEDI: **12.068 ms**, ou
-- seja, o mesmo custo da 0151. Não é margem de erro — é a correção não
-- acontecendo. O plano diz por quê, e vale mais que o resultado:
--
--   CTE candidatos -> Nested Loop
--     -> CTE Scan on por_documento pd (rows=2619)
--     -> GroupAggregate (rows=8 **loops=2619**)
--          -> CTE Scan on por_documento (rows=2619 loops=2619)
--
-- O Postgres 12+ INLINA CTE usada uma vez só. `grupos` era usada uma vez, então
-- foi inlinada dentro do laço — e o agrupamento que existia para MATAR o
-- cartesiano virou o cartesiano, recalculado 2.619 vezes. O mesmo aconteceu com
-- `papeis` (o `where papel = 'conta'` foi empurrado para baixo do `distinct`, e
-- `fn_papel_linha` voltou a rodar nas 8.729 linhas) e com `candidatos` (rescan
-- dentro de `autoridade`).
--
-- A LIÇÃO, e ela é da família das outras deste repositório: **agrupar antes não
-- é uma instrução, é uma intenção** — e o planner tem todo o direito de
-- desfazê-la. `MATERIALIZED` é o que transforma a intenção em barreira. Medido
-- depois: **1.813 ms**, as mesmas 34 linhas.
create or replace function fn_conflitos_do_caso(
  p_caso_id        uuid,
  p_entidade       text    default null,
  p_tolerancia_abs numeric default 100,
  p_tolerancia_pct numeric default 0.005
)
returns table (
  secao_canonica       text,
  chave                text,
  entidade             text,
  exercicio            integer,
  documento_vencedor   uuid,
  tipo_vencedor        text,
  valor_vencedor       numeric,
  documento_perdedor   uuid,
  tipo_perdedor        text,
  valor_perdedor       numeric,
  diferenca            numeric,
  decidido             boolean,
  criterio             text
)
language sql
stable
as $$
  -- 0152: o par nasce DEPOIS do agrupamento. A versão anterior pedia o produto
  -- cartesiano (6.859.127 pares comparados para achar 34, 12,4 s por chamada).
  --
  -- A versão vigente de cada documento do caso, UMA VEZ (era chamada no join e
  -- de novo dentro de fn_autoridade_do_documento).
  with versao as materialized (
    select d.id as documento_id, d.tipo_taxonomia, d.entidade_id, d.periodo_id,
           fn_versao_com_extracao(d.id) as documento_versao_id
    from documento d
    where d.caso_id = p_caso_id
  ),
  -- (b) 0146: a capa só responde quando o documento é de UMA empresa. Num
  -- documento de várias, a linha sem coluna não tem dono e fica de fora —
  -- atribuí-la à capa criaria conflito entre uma empresa e um fantasma. UMA
  -- linha por versão, em vez de uma avaliação por linha extraída.
  multi_entidade as materialized (
    select v.documento_versao_id,
           count(distinct ce.entidade_coluna) > 1 as varias
    from versao v
    left join campo_extraido ce
      on ce.documento_versao_id = v.documento_versao_id
     and ce.entidade_coluna is not null
    group by v.documento_versao_id
  ),
  -- As linhas candidatas, com os filtros baratos (índice + coluna) primeiro.
  -- `fn_papel_linha` NÃO entra aqui — ela é a cara, e entra depois de já ter
  -- sido calculada uma vez por tripla distinta.
  cru as materialized (
    select ce.id, ce.chave, ce.unidade, ce.valor_num, ce.secao_canonica,
           ce.entidade_coluna, ce.periodo_coluna,
           v.documento_id, v.tipo_taxonomia, v.documento_versao_id,
           e.razao_social, p.referencia as periodo_referencia,
           m.varias
    from versao v
    join campo_extraido ce on ce.documento_versao_id = v.documento_versao_id
    join multi_entidade m  on m.documento_versao_id = v.documento_versao_id
    left join entidade e   on e.id = v.entidade_id
    left join periodo p    on p.id = v.periodo_id
    where ce.valor_num is not null
      and ce.secao_canonica is not null
      and ce.secao_canonica <> 'NAO_CLASSIFICAVEL'
      and fn_fator_escala(ce.unidade) is not null
  ),
  -- (d) `fn_papel_linha` uma vez por tripla distinta, não uma por linha.
  papeis as materialized (
    select t.chave, t.tipo_taxonomia, t.unidade,
           fn_papel_linha(t.chave, t.tipo_taxonomia, t.unidade) as papel
    from (select distinct chave, tipo_taxonomia, unidade from cru) t
  ),
  bruto as materialized (
    select
      c.secao_canonica,
      fn_normalizar_texto(c.chave) as rotulo,
      c.chave,
      coalesce(c.entidade_coluna, case when c.varias then null else c.razao_social end) as entidade,
      coalesce(fn_exercicio_da_coluna(c.periodo_coluna),
               fn_exercicio_da_coluna(c.periodo_referencia)) as exercicio,
      fn_valor_em_base(c.valor_num, c.unidade) as valor,
      c.documento_id,
      c.tipo_taxonomia
    from cru c
    join papeis pp
      on pp.chave = c.chave
     and pp.tipo_taxonomia is not distinct from c.tipo_taxonomia
     and pp.unidade is not distinct from c.unidade
    where pp.papel = 'conta'
  ),
  -- (e) `fn_mesma_entidade` É PLPGSQL E ESTAVA SENDO CHAMADA POR LINHA. Medido
  -- no araucária: 10.570 linhas extraídas para **40 strings de entidade
  -- distintas**. É a mesma correção do `papeis` logo acima, e o mesmo defeito:
  -- função pura avaliada sobre LINHAS quando o argumento tem poucos valores.
  entidades_do_caso as materialized (
    select distinct b.entidade from bruto b where b.entidade is not null
  ),
  entidades_alvo as materialized (
    select e.entidade from entidades_do_caso e
    where p_entidade is null or fn_mesma_entidade(e.entidade, p_entidade)
  ),
  filtrado as materialized (
    select b.* from bruto b
    join entidades_alvo ea on ea.entidade = b.entidade
    where b.exercicio is not null
  ),
  -- Um valor por (conceito, exercício, entidade, DOCUMENTO). Dentro do mesmo
  -- documento a mesma conta pode aparecer em mais de uma linha (a coluna de
  -- outro exercício, uma repetição de página); o de maior módulo representa o
  -- documento, e é a regra da 0042 usada onde ela é inofensiva — aqui ela
  -- escolhe entre linhas de UMA fonte, não entre fontes que discordam.
  por_documento as materialized (
    select f.secao_canonica, f.rotulo, f.entidade, f.exercicio, f.documento_id,
           max(f.tipo_taxonomia) as tipo,
           (array_agg(f.chave order by length(f.chave)))[1] as chave,
           (array_agg(f.valor order by abs(f.valor) desc nulls last))[1] as valor
    from filtrado f
    group by f.secao_canonica, f.rotulo, f.entidade, f.exercicio, f.documento_id
  ),
  -- (a) O AGRUPAMENTO QUE MATA O CARTESIANO. Só grupo com mais de um documento
  -- e com dispersão acima do piso da tolerância pode conter par. Ver a prova de
  -- que o pré-filtro é conservador no cabeçalho.
  grupos as materialized (
    select secao_canonica, rotulo, entidade, exercicio
    from por_documento
    group by secao_canonica, rotulo, entidade, exercicio
    having count(*) > 1
       and (max(valor) - min(valor)) > p_tolerancia_abs
  ),
  candidatos as materialized (
    select pd.*
    from por_documento pd
    join grupos g
      on g.secao_canonica = pd.secao_canonica
     and g.rotulo         = pd.rotulo
     and g.entidade       is not distinct from pd.entidade
     and g.exercicio      = pd.exercicio
  ),
  -- (c) A autoridade uma vez por DOCUMENTO — e só dos documentos que sobraram.
  autoridade as materialized (
    select dd.documento_id, a.autoridade, a.motivo
    from (select distinct documento_id from candidatos) dd
    cross join lateral fn_autoridade_do_documento(dd.documento_id) a
  ),
  com_autoridade as materialized (
    select c.*, au.autoridade, au.motivo
    from candidatos c join autoridade au on au.documento_id = c.documento_id
  ),
  pares as (
    select
      a.secao_canonica, a.chave, a.entidade, a.exercicio,
      a.documento_id as doc_a, a.tipo as tipo_a, a.valor as valor_a,
      a.autoridade as aut_a, a.motivo as motivo_a,
      b.documento_id as doc_b, b.tipo as tipo_b, b.valor as valor_b,
      b.autoridade as aut_b, b.motivo as motivo_b
    from com_autoridade a
    join com_autoridade b
      on b.secao_canonica = a.secao_canonica
     and b.rotulo         = a.rotulo
     and b.entidade       is not distinct from a.entidade
     and b.exercicio      = a.exercicio
     and b.documento_id   > a.documento_id          -- par sem repetir a ordem
    where abs(a.valor - b.valor)
            > greatest(p_tolerancia_abs, abs(a.valor) * p_tolerancia_pct)
  )
  select
    p.secao_canonica,
    p.chave,
    p.entidade,
    p.exercicio,
    case when p.aut_a >= p.aut_b then p.doc_a   else p.doc_b   end,
    case when p.aut_a >= p.aut_b then p.tipo_a  else p.tipo_b  end,
    case when p.aut_a >= p.aut_b then p.valor_a else p.valor_b end,
    case when p.aut_a >= p.aut_b then p.doc_b   else p.doc_a   end,
    case when p.aut_a >= p.aut_b then p.tipo_b  else p.tipo_a  end,
    case when p.aut_a >= p.aut_b then p.valor_b else p.valor_a end,
    abs(p.valor_a - p.valor_b),
    p.aut_a <> p.aut_b,
    case when p.aut_a <> p.aut_b then
      format('%s vence: %s (autoridade %s) contra %s (autoridade %s)',
             case when p.aut_a > p.aut_b then p.tipo_a else p.tipo_b end,
             case when p.aut_a > p.aut_b then p.motivo_a else p.motivo_b end,
             greatest(p.aut_a, p.aut_b),
             case when p.aut_a > p.aut_b then p.motivo_b else p.motivo_a end,
             least(p.aut_a, p.aut_b))
    else
      format('EMPATE em autoridade %s (%s × %s): a escolha é humana — o valor '
             || 'não foi trocado, continua o de maior módulo',
             p.aut_a, p.motivo_a, p.motivo_b)
    end
  from pares p;
$$;

comment on function fn_conflitos_do_caso(uuid, text, numeric, numeric) is
  'Dois documentos do mesmo período discordando sobre a MESMA conta, com o vencedor por '
  'autoridade documental e o critério por extenso (0151). Compara na base, só entre linhas com '
  'seção canônica, papel conta e unidade conversível. `decidido = false` é empate: ninguém vence '
  'e a decisão é humana. O par nasce DEPOIS do agrupamento (0152) — a versão anterior pedia o '
  'produto cartesiano e levava 12,4 s por chamada no lote de 190 documentos.';

-- =============================================================================
-- 2. O ESCOPO PASSA A SER DECLARADO
-- =============================================================================
--
-- `p_escopo` existe para que o LOTE possa dizer o que quer, em vez de a
-- checagem ter de adivinhar. Três valores, e o padrão preserva tudo o que já
-- chamava esta função — nenhum teste e nenhum caminho existente muda:
--
--   'tudo'      (padrão) o comportamento de sempre: árvore + as oito checagens
--                de chave. É o que o portal e as suítes chamam.
--   'documento' SÓ o que é do documento — hoje, `fn_reconciliar_arvore`. É o
--                que o n8n passa na passada por documento.
--   'caso'      recusado aqui de propósito: a checagem de caso não tem
--                documento para ancorar, e fingir que tem seria o erro que a
--                0146 já cobrou. Quem faz isso é `fn_reconciliar_caso`.
--
-- O 1-argumento é DERRUBADO e recriado com default em vez de sobrecarregado:
-- duas funções com o mesmo nome, uma de um argumento e outra de dois com
-- default, é ambiguidade esperando acontecer.
-- -----------------------------------------------------------------------------
-- fn_reconciliar_chaves_do_documento — as oito checagens de chave, para UMA
-- chave (entidade, período) e um conjunto de gates de tipo.
-- -----------------------------------------------------------------------------
--
-- É o corpo que estava dentro do despachante, extraído SEM MUDANÇA DE LÓGICA
-- para poder ser chamado das duas formas — por documento (compat) e por chave
-- (o lote). O laço de período continua idêntico: tenta os períodos compatíveis
-- em ordem e para no primeiro que satisfaz a pré-condição.
--
-- POR QUE O LAÇO CONTINUA. Ele parece desperdício (até 20 iterações por
-- checagem) e não é: ele existe para ACHAR o período em que o par existe, e
-- parar no primeiro que responde. Trocá-lo por "rode em todos" mudaria o número
-- de linhas de `reconciliacao` — e mudança de contagem sem defeito medido é
-- exatamente o tipo de mexida que este repositório evita. O que a 0152 corta é
-- a REPETIÇÃO do laço, não o laço.
create or replace function fn_reconciliar_chaves_do_documento(
  p_caso_id     uuid,
  p_entidade_id uuid,
  p_periodo_id  uuid,
  p_tipo        text
)
returns jsonb language plpgsql as $$
-- 0152: extraída de fn_reconciliar_por_documento sem mudança de lógica.
-- 0151: o conflito entre documentos do mesmo período mora aqui, no fim.
declare
  v_checagens jsonb := '[]'::jsonb;
  v_periodos  uuid[];
  v_per       uuid;
  v_res       jsonb;
begin
  select array_agg(p.id order by (p.id = p_periodo_id) desc, p.referencia)
    into v_periodos
  from periodo p
  where p.caso_id = p_caso_id
    and (p.id = p_periodo_id or fn_periodos_compativeis(p.id, p_periodo_id));
  if v_periodos is null or cardinality(v_periodos) = 0 then
    v_periodos := array[p_periodo_id];
  end if;

  -- Classe A (0009)
  if p_tipo in ('BALANCO', 'BALANCETE', 'COMBINADO') then
    foreach v_per in array v_periodos loop
      v_res := fn_reconciliar_ativo_passivo_pl(p_caso_id, p_entidade_id, v_per);
      exit when coalesce(v_res->>'resultado', '') <> 'precondicao_nao_satisfeita';
    end loop;
    v_checagens := v_checagens || jsonb_build_array(v_res);
  end if;
  if p_tipo in ('BALANCO', 'BALANCETE', 'COMBINADO', 'FLUXO_CAIXA') then
    foreach v_per in array v_periodos loop
      v_res := fn_reconciliar_caixa_bp_fluxo(p_caso_id, p_entidade_id, v_per);
      exit when coalesce(v_res->>'resultado', '') <> 'precondicao_nao_satisfeita';
    end loop;
    v_checagens := v_checagens || jsonb_build_array(v_res);
  end if;

  -- Classe B (0015/0021)
  if p_tipo in ('DRE', 'FATURAMENTO_24M') then
    foreach v_per in array v_periodos loop
      v_res := fn_reconciliar_receita_dre_vs_faturamento(p_caso_id, p_entidade_id, v_per);
      exit when coalesce(v_res->>'resultado', '') <> 'precondicao_nao_satisfeita';
    end loop;
    v_checagens := v_checagens || jsonb_build_array(v_res);
  end if;
  if p_tipo in ('DRE', 'MAPA_DIVIDA') then
    foreach v_per in array v_periodos loop
      v_res := fn_reconciliar_despfin_dre_vs_divida(p_caso_id, p_entidade_id, v_per);
      exit when coalesce(v_res->>'resultado', '') <> 'precondicao_nao_satisfeita';
    end loop;
    v_checagens := v_checagens || jsonb_build_array(v_res);
  end if;

  -- Mútuos (0117/0123). Pelos dois lados: quem chega por último fecha o par.
  if p_tipo in ('MUTUOS', 'BALANCO', 'COMBINADO', 'DF_AUDITADA') then
    foreach v_per in array v_periodos loop
      v_res := fn_reconciliar_mutuos(p_caso_id, v_per);
      exit when coalesce(v_res->>'resultado', '') <> 'precondicao_nao_satisfeita';
    end loop;
    v_checagens := v_checagens || jsonb_build_array(v_res);
  end if;

  -- Intragrupo FORA mútuo (0124). Disparada por balanço individual, que é a
  -- única peça de que ela precisa — não há documento par a esperar. `COMBINADO`
  -- não dispara e não é lido: as linhas intragrupo dele são eliminações.
  if p_tipo in ('BALANCO', 'BALANCETE', 'DF_AUDITADA') then
    foreach v_per in array v_periodos loop
      v_res := fn_reconciliar_intragrupo(p_caso_id, v_per);
      exit when coalesce(v_res->>'resultado', '') <> 'precondicao_nao_satisfeita';
    end loop;
    v_checagens := v_checagens || jsonb_build_array(v_res);
  end if;

  -- Duplicidade de rótulo (0105). Sem laço de período: é por caso/entidade.
  if p_tipo in ('BALANCO', 'BALANCETE', 'COMBINADO') then
    v_checagens := v_checagens || jsonb_build_array(
      fn_reconciliar_duplicidade(p_caso_id, p_entidade_id));
  end if;

  -- Conflito entre documentos do mesmo período (0151). Sem laço de período: a
  -- checagem descobre sozinha quais exercícios existem.
  if p_tipo in ('BALANCO', 'BALANCETE', 'COMBINADO', 'DF_AUDITADA', 'DRE',
                'FLUXO_CAIXA', 'DMPL', 'DVA', 'NOTAS_EXPL') then
    v_checagens := v_checagens || jsonb_build_array(
      fn_reconciliar_versoes_do_periodo(p_caso_id, p_entidade_id));
  end if;

  return v_checagens;
end;
$$;

comment on function fn_reconciliar_chaves_do_documento(uuid, uuid, uuid, text) is
  'As oito checagens que leem (caso, entidade, período) e não o documento (0152). Extraída de '
  'fn_reconciliar_por_documento sem mudança de lógica, para que o lote possa rodá-las uma vez '
  'por CHAVE em vez de uma vez por documento.';

drop function if exists fn_reconciliar_por_documento(uuid);

create or replace function fn_reconciliar_por_documento(
  p_documento_id uuid,
  p_escopo       text default 'tudo'
)
returns jsonb language plpgsql as $$
declare
  v_caso_id     uuid;
  v_entidade_id uuid;
  v_periodo_id  uuid;
  v_tipo        text;
  v_checagens   jsonb := '[]'::jsonb;
begin
  -- 0152: o escopo passa a ser declarado. As checagens de CHAVE saíram daqui
  -- para fn_reconciliar_chaves_do_documento, porque elas leem (caso, entidade,
  -- período) e não o documento — e por isso o lote as roda uma vez por chave.
  if p_escopo not in ('tudo', 'documento') then
    raise exception 'escopo inválido: % (use ''tudo'' ou ''documento''; o escopo de caso é '
                    'fn_reconciliar_caso)', p_escopo;
  end if;

  select caso_id, entidade_id, periodo_id, tipo_taxonomia
    into v_caso_id, v_entidade_id, v_periodo_id, v_tipo
  from documento where id = p_documento_id;

  if v_caso_id is null then
    return jsonb_build_object('executado', false, 'motivo', 'documento não encontrado');
  end if;

  -- 0133: a conferência INTRA-documento. Se as seções do próprio documento não
  -- fecham, as comparações ENTRE documentos estão sendo feitas sobre números
  -- que já não se sustentam — e é melhor que a fila diga isso antes de dizer
  -- que o Ativo bate com o Passivo (que, com totais impressos dos dois lados,
  -- bate mesmo quando faltam contas no meio).
  --
  -- É A ÚNICA CHECAGEM QUE É DE FATO POR DOCUMENTO, e a 0133 já dizia isso em
  -- comentário: "sem loop de período: a árvore é INTRA-documento". As outras
  -- oito leem (caso, entidade, período) e o documento só entrega a chave.
  if v_tipo in ('BALANCO', 'BALANCETE', 'COMBINADO') then
    v_checagens := v_checagens || jsonb_build_array(fn_reconciliar_arvore(p_documento_id));
  end if;

  if p_escopo = 'tudo' then
    v_checagens := v_checagens
      || fn_reconciliar_chaves_do_documento(v_caso_id, v_entidade_id, v_periodo_id, v_tipo);
  end if;

  return jsonb_build_object('executado', true, 'documento_id', p_documento_id,
                            'escopo', p_escopo, 'checagens', v_checagens);
end;
$$;

comment on function fn_reconciliar_por_documento(uuid, text) is
  'Despachante de reconciliação de UM documento (0133/0151/0152). `p_escopo = ''documento''` roda '
  'só o que é intra-documento (a árvore); ''tudo'' (padrão) mantém o comportamento anterior e '
  'roda também as checagens de chave. Num lote, use ''documento'' aqui e fn_reconciliar_caso uma '
  'vez no fim — as checagens de chave não leem o documento, leem (caso, entidade, período).';

-- =============================================================================
-- 3. `fn_reconciliar_caso` — uma vez por chave, não uma por documento
-- =============================================================================
--
-- CADA CHECAGEM TEM A SUA PRÓPRIA CHAVE, e errar isso é não corrigir nada.
--
-- A PRIMEIRA VERSÃO DESTA FUNÇÃO ITERAVA (entidade, período, tipo) — uma chave
-- só, para as oito checagens. Medido no araucária depois de escrita: **162
-- chaves para 190 documentos**, 15% de redução. A checagem cara
-- (`fn_reconciliar_versoes_do_periodo`, 1,8 s) sairia de 123 chamadas para
-- ~130. Eu teria trocado o código sem corrigir o defeito, e a suíte teria
-- passado — porque ela prova EQUIVALÊNCIA, não custo.
--
-- O erro é de granularidade, e ele estava na minha própria análise: as oito
-- checagens não leem a mesma chave.
--
--     fn_reconciliar_versoes_do_periodo(caso, entidade) ......... 16 chaves
--     fn_reconciliar_duplicidade       (caso, entidade) ......... 15
--     fn_reconciliar_mutuos            (caso, período)  ......... 15
--     fn_reconciliar_intragrupo        (caso, período)  ......... 14
--     fn_reconciliar_ativo_passivo_pl  (caso, entidade, período) . 73
--     fn_reconciliar_caixa_bp_fluxo    (caso, entidade, período) . 73
--     fn_reconciliar_receita_...       (caso, entidade, período) . 19
--     fn_reconciliar_despfin_...       (caso, entidade, período) . 22
--
-- `fn_reconciliar_versoes_do_periodo` **não recebe período nem tipo**. Rodá-la
-- dentro de um laço que varre período e tipo é repetir a mesma chamada dezenas
-- de vezes — exatamente o defeito que esta migration existe para corrigir, um
-- nível abaixo.
--
-- Então cada checagem varre A SUA chave, com o SEU gate de tipo. São oito laços
-- em vez de um, e a repetição da forma é o preço de não mentir sobre o que cada
-- uma lê. Total: **247 invocações contra as ~8.500 de antes**, e a cara roda 16
-- vezes em vez de 123.
create or replace function fn_periodos_compativeis_array(p_caso_id uuid, p_periodo_id uuid)
returns uuid[] language sql stable as $$
  -- O array de períodos do laço, fatorado: ele é idêntico nas seis checagens
  -- que têm laço, e escrevê-lo seis vezes é como as duas contas de espera do
  -- portal divergiram.
  select coalesce(
    (select array_agg(p.id order by (p.id = p_periodo_id) desc, p.referencia)
     from periodo p
     where p.caso_id = p_caso_id
       and (p.id = p_periodo_id or fn_periodos_compativeis(p.id, p_periodo_id))),
    array[p_periodo_id]);
$$;

create or replace function fn_reconciliar_caso(p_caso_id uuid)
returns jsonb language plpgsql as $$
-- 0152: cada checagem sobre a SUA chave.
declare
  v_k          record;
  v_per        uuid;
  v_res        jsonb;
  v_checagens  jsonb := '[]'::jsonb;
  v_chamadas   int := 0;
  v_documentos int := 0;
  c_arvore     constant text[] := array['BALANCO','BALANCETE','COMBINADO'];
  c_fluxo      constant text[] := array['BALANCO','BALANCETE','COMBINADO','FLUXO_CAIXA'];
  c_receita    constant text[] := array['DRE','FATURAMENTO_24M'];
  c_despfin    constant text[] := array['DRE','MAPA_DIVIDA'];
  c_mutuos     constant text[] := array['MUTUOS','BALANCO','COMBINADO','DF_AUDITADA'];
  c_intra      constant text[] := array['BALANCO','BALANCETE','DF_AUDITADA'];
  c_conflito   constant text[] := array['BALANCO','BALANCETE','COMBINADO','DF_AUDITADA','DRE',
                                        'FLUXO_CAIXA','DMPL','DVA','NOTAS_EXPL'];
begin
  select count(*) into v_documentos from documento where caso_id = p_caso_id;

  -- ---- (entidade, período), com laço de período -----------------------------
  for v_k in select distinct d.entidade_id, d.periodo_id from documento d
             where d.caso_id = p_caso_id and d.tipo_taxonomia = any(c_arvore) loop
    foreach v_per in array fn_periodos_compativeis_array(p_caso_id, v_k.periodo_id) loop
      v_res := fn_reconciliar_ativo_passivo_pl(p_caso_id, v_k.entidade_id, v_per);
      exit when coalesce(v_res->>'resultado', '') <> 'precondicao_nao_satisfeita';
    end loop;
    v_checagens := v_checagens || jsonb_build_array(v_res); v_chamadas := v_chamadas + 1;
  end loop;

  for v_k in select distinct d.entidade_id, d.periodo_id from documento d
             where d.caso_id = p_caso_id and d.tipo_taxonomia = any(c_fluxo) loop
    foreach v_per in array fn_periodos_compativeis_array(p_caso_id, v_k.periodo_id) loop
      v_res := fn_reconciliar_caixa_bp_fluxo(p_caso_id, v_k.entidade_id, v_per);
      exit when coalesce(v_res->>'resultado', '') <> 'precondicao_nao_satisfeita';
    end loop;
    v_checagens := v_checagens || jsonb_build_array(v_res); v_chamadas := v_chamadas + 1;
  end loop;

  for v_k in select distinct d.entidade_id, d.periodo_id from documento d
             where d.caso_id = p_caso_id and d.tipo_taxonomia = any(c_receita) loop
    foreach v_per in array fn_periodos_compativeis_array(p_caso_id, v_k.periodo_id) loop
      v_res := fn_reconciliar_receita_dre_vs_faturamento(p_caso_id, v_k.entidade_id, v_per);
      exit when coalesce(v_res->>'resultado', '') <> 'precondicao_nao_satisfeita';
    end loop;
    v_checagens := v_checagens || jsonb_build_array(v_res); v_chamadas := v_chamadas + 1;
  end loop;

  for v_k in select distinct d.entidade_id, d.periodo_id from documento d
             where d.caso_id = p_caso_id and d.tipo_taxonomia = any(c_despfin) loop
    foreach v_per in array fn_periodos_compativeis_array(p_caso_id, v_k.periodo_id) loop
      v_res := fn_reconciliar_despfin_dre_vs_divida(p_caso_id, v_k.entidade_id, v_per);
      exit when coalesce(v_res->>'resultado', '') <> 'precondicao_nao_satisfeita';
    end loop;
    v_checagens := v_checagens || jsonb_build_array(v_res); v_chamadas := v_chamadas + 1;
  end loop;

  -- ---- só (período) — mútuos e intragrupo são do GRUPO, não da empresa ------
  for v_k in select distinct d.periodo_id from documento d
             where d.caso_id = p_caso_id and d.tipo_taxonomia = any(c_mutuos) loop
    foreach v_per in array fn_periodos_compativeis_array(p_caso_id, v_k.periodo_id) loop
      v_res := fn_reconciliar_mutuos(p_caso_id, v_per);
      exit when coalesce(v_res->>'resultado', '') <> 'precondicao_nao_satisfeita';
    end loop;
    v_checagens := v_checagens || jsonb_build_array(v_res); v_chamadas := v_chamadas + 1;
  end loop;

  for v_k in select distinct d.periodo_id from documento d
             where d.caso_id = p_caso_id and d.tipo_taxonomia = any(c_intra) loop
    foreach v_per in array fn_periodos_compativeis_array(p_caso_id, v_k.periodo_id) loop
      v_res := fn_reconciliar_intragrupo(p_caso_id, v_per);
      exit when coalesce(v_res->>'resultado', '') <> 'precondicao_nao_satisfeita';
    end loop;
    v_checagens := v_checagens || jsonb_build_array(v_res); v_chamadas := v_chamadas + 1;
  end loop;

  -- ---- só (entidade) — sem período nenhum ----------------------------------
  for v_k in select distinct d.entidade_id from documento d
             where d.caso_id = p_caso_id and d.tipo_taxonomia = any(c_arvore) loop
    v_checagens := v_checagens
      || jsonb_build_array(fn_reconciliar_duplicidade(p_caso_id, v_k.entidade_id));
    v_chamadas := v_chamadas + 1;
  end loop;

  for v_k in select distinct d.entidade_id from documento d
             where d.caso_id = p_caso_id and d.tipo_taxonomia = any(c_conflito) loop
    v_checagens := v_checagens
      || jsonb_build_array(fn_reconciliar_versoes_do_periodo(p_caso_id, v_k.entidade_id));
    v_chamadas := v_chamadas + 1;
  end loop;

  return jsonb_build_object(
    'executado', true, 'caso_id', p_caso_id,
    'documentos', v_documentos, 'chamadas', v_chamadas,
    'checagens', v_checagens);
end;
$$;

comment on function fn_periodos_compativeis_array(uuid, uuid) is
  'Os períodos compatíveis do caso, o do documento primeiro (0152). Fatorado das seis checagens '
  'que têm laço de período — seis cópias da mesma conta é como as duas esperas do portal '
  'divergiram.';

comment on function fn_reconciliar_caso(uuid) is
  'As checagens do caso, cada uma UMA VEZ por chave PRÓPRIA (0152): a de conflito e a de '
  'duplicidade por entidade, mútuos e intragrupo por período, as quatro de Classe A/B por '
  '(entidade, período). Medido no book-araucaria: 247 invocações contra as ~8.500 da versão por '
  'documento, e a checagem cara (1,8 s) roda 16 vezes em vez de 123. Uma chave só para as oito '
  'daria 162 — 15% de redução, que é não corrigir nada.';

grant execute on function fn_periodos_compativeis_array(uuid, uuid) to authenticated;

grant execute on function fn_reconciliar_por_documento(uuid, text) to authenticated;
grant execute on function fn_reconciliar_chaves_do_documento(uuid, uuid, uuid, text) to authenticated;
grant execute on function fn_reconciliar_caso(uuid) to authenticated;

-- =============================================================================
-- 4. A SONDA
-- =============================================================================
insert into instalacao_requisito
  (chave, migration, tipo, objeto, marcador, criterio_seed, porque, severidade, ordem) values
  ('reconciliacao_do_lote', '0152', 'funcao', 'fn_reconciliar_caso', null, null,
   'As checagens de chave voltam a rodar uma vez POR DOCUMENTO em vez de uma vez por (entidade, '
   'período): no book-araucaria são 190 execuções para 82 chaves, ~8.500 invocações e ~8.500 '
   'linhas iguais em reconciliacao. Foi o que deixou a execução 7172 de pé por 1h52 sem gravar '
   'nada — sem erro em lugar nenhum.',
   'bloqueante', 520),
  ('reconciliacao_escopo_declarado', '0152', 'corpo', 'fn_reconciliar_por_documento', '0152', null,
   'O despachante volta a rodar as checagens de CHAVE junto com a do documento, e o lote perde o '
   'jeito de pedir só a do documento. Sem o corpo novo, fn_reconciliar_caso fica instalada e o '
   'trabalho continua sendo feito 190 vezes.',
   'bloqueante', 530),
  -- A 0151 pôs a chamada no despachante; a 0152 a MOVEU para a função de chave,
  -- que é quem o lote roda. O requisito segue a chamada — um requisito que
  -- aponta para o lugar antigo vira alarme falso, que é pior que não medir.
  ('conflito_na_rodada', '0152', 'corpo', 'fn_reconciliar_chaves_do_documento', '0151', null,
   'A checagem de conflito da 0151 existe e nunca roda: quem a chama é a função de chave, que o '
   'lote executa uma vez por (entidade, período). Sem o corpo novo, fn_conflitos_do_caso fica '
   'instalada e muda — a forma de estágio parado que a rodada de 27/08 ensinou a reconhecer.',
   'bloqueante', 500),
  ('conflito_sem_cartesiano', '0152', 'corpo', 'fn_conflitos_do_caso', '0152', null,
   'A checagem de conflito volta a pedir o produto cartesiano: medido no araucária, 6.859.127 '
   'pares comparados para achar 34, e 12,4 s por chamada. Ela é chamada uma vez por entidade, '
   'então o custo não fica num canto — ele multiplica.',
   'importante', 540)
on conflict (chave) do update
  set migration = excluded.migration, tipo = excluded.tipo, objeto = excluded.objeto,
      marcador = excluded.marcador, criterio_seed = excluded.criterio_seed,
      porque = excluded.porque, severidade = excluded.severidade, ordem = excluded.ordem;

update instalacao_cobertura
   set ate_migration = '0152',
       revisado_em = date '2026-08-27',
       observacao = 'Revisão de 27/08/2026 (noite): a 0152 responde à rodada real do '
                    'book-araucaria, que ficou 1h52 de pé sem gravar uma reconciliação. As '
                    'checagens do despachante leem (caso, entidade, período) e não o documento, '
                    'então rodavam 190 vezes para 82 chaves; e fn_conflitos_do_caso pedia o '
                    'produto cartesiano (6,86 M pares para achar 34, 12,4 s por chamada). Três '
                    'requisitos novos: a reconciliação por lote, o escopo declarado no '
                    'despachante, e o conflito sem cartesiano.'
 where id;
