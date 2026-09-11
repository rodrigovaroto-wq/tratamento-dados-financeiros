-- =============================================================================
-- Migration 0164 — A ESTIMATIVA QUE O FILTRO OPACO ESCONDIA: fn_linhas_para_
-- modelagem (e fn_conferir_modelagem, que a embrulha) estourava o
-- statement_timeout de 8s do Supabase no caso "Teste 00" (190 documentos,
-- 7.151 linhas) — 8.168ms e 8.177ms, ambas canceladas.
--
-- O SINTOMA NÃO É "lento": é a tela de Modelagem mostrando "este caso ainda
-- não tem linha extraída com valor" para um caso que TEM 7.151 linhas — a
-- mesma classe de mentira silenciosa que a 0101 (ver o cabeçalho dela) e a
-- `.claude/memory/materialized-nao-e-enfeite.md` (fn_conflitos_do_caso, 0152)
-- já documentaram: uma consulta cancelada por timeout chega ao portal como
-- AUSÊNCIA de dado, não como erro.
--
-- CAUSA MEDIDA, por EXPLAIN (ANALYZE, BUFFERS), não suposta:
--
-- O join da CTE `ocorrencia` contra `papel_do_rotulo` (schema.sql:4873-4880,
-- desenhado pela 0101 para custar "uma vez por combinação distinta") virava
-- **Nested Loop** em vez de Hash Join. Num fixture sintético de ESCALA (190
-- documentos, 7.220 ocorrências, 800 rótulos distintos — ver a seção 3 sobre
-- por que 800 e não os 250 do fixture antigo), reproduzido localmente, fresco,
-- sem ANALYZE manual (o estado real de um caso recém-carregado):
--
--   Nested Loop  (cost=0.30..0.36 rows=1 width=288)
--                (actual time=1152.893..13551.024 rows=7220 loops=1)
--     Rows Removed by Join Filter: 43168380
--     ->  CTE Scan on bruto b_2  (cost=0.00..0.02 rows=1 width=256)
--                                (actual time=1.709..4.677 rows=7220 loops=1)
--   Execution Time: 15001.606 ms
--
-- O planner estima **rows=1** para a CTE `bruto` (real: 7.220) — a estimativa
-- erra por mais de três ordens de grandeza. A causa da estimativa quebrada:
-- o filtro `dv.id = fn_versao_com_extracao(d.id)` (0102, "só a versão
-- VIGENTE de cada documento") compara contra o retorno de uma FUNÇÃO — o
-- Postgres não sabe estimar a seletividade de uma comparação contra uma
-- função opaca, chuta um valor default baixíssimo, e a estimativa de rows=1
-- se propaga por toda CTE construída em cima de `bruto`. Com ~1 linha
-- esperada de cada lado, o planner escolhe Nested Loop — barato quando a
-- estimativa está certa, catastrófico quando a realidade é 7.220 × ~2.000
-- combinações de (chave, tipo_taxonomia, unidade).
--
-- Por que o teste de escala existente (`Supabase/test/modelagem_escala.
-- test.sql`, 14 docs / 770 ocorrências / ~250 rótulos) nunca pegou isto:
-- nessa escala o Nested Loop é ~577 mil comparações — dezenas de ms,
-- invisível dentro do teto de 8s. O defeito só aparece quando as DUAS pontas
-- do produto crescem — documentos e, principalmente, rótulos distintos (o
-- caso real, sendo demonstração financeira de verdade, não estanca em 250).
--
-- ---------------------------------------------------------------------------
-- A CORREÇÃO — candidato (a) do diagnóstico, MEDIDO, não escolhido por gosto.
--
-- O filtro opaco vira um JOIN de verdade: a "versão vigente" de cada
-- documento passa a ser uma CTE nomeada (`versao_vigente`, por `distinct on`
-- + `order by n_versao desc`, filtrada por `exists` contra campo_extraido) —
-- a MESMA regra da 0102 ("a de maior n_versao que TEM campo_extraido"),
-- só que como uma relação que o planner consegue ver e estimar, em vez de
-- uma chamada de função por linha. `bruto` passa a nascer de um JOIN por
-- igualdade de chave (documento_versao_id) contra essa CTE, não de um filtro
-- de linha por linha contra `fn_versao_com_extracao(d.id)`.
--
-- MEDIDO O DEPOIS, no MESMO caso, mesma sessão, sem ANALYZE manual entre as
-- duas medições (script de reprodução descartado ao final da sessão; refazer
-- exige só o fixture de escala descrito na seção 3):
--
--   Hash Join  (cost=386.64..788.77 rows=1 width=288)
--              (actual time=1265.925..1272.711 rows=7220 loops=1)
--     Rows Removed by Join Filter: 46760
--     ->  CTE Scan on bruto b_2  (cost=0.00..128.68 rows=6434 width=256)
--                                (actual time=3.238..3.850 rows=7220 loops=1)
--   Execution Time: 2644.811 ms
--
-- rows=1 → rows=6434 (real: 7.220 — a 15% de distância, contra três ordens
-- de grandeza de erro antes). Nested Loop → Hash Join. **15.001,6 ms → 2.644,8
-- ms — 5,7×**, e sob o teto de 8s do Supabase com folga. O Nested Loop restante
-- do plano (a CTE `pares`, self-join de sobreposição por igualdade de valor —
-- a hipótese descartada no diagnóstico como secundária) continua ali, sem
-- piorar: é pré-existente, e nesta escala custa ~1,4s dos 2,6s totais — bem
-- dentro do teto. Não é objeto desta migration.
--
-- ---------------------------------------------------------------------------
-- A CORREÇÃO NÃO MUDA O RESULTADO — provado por comparação linha a linha.
--
-- `select ... except select ...` NOS DOIS SENTIDOS, corpo velho × corpo novo,
-- rodado contra:
--   (a) os 75 casos que já existiam no banco de teste depois do `run.sh`
--       completo (todos os fixtures de todas as suítes, Vertentes e
--       Canastra inclusos);
--   (b) os três fixtures sintéticos de escala (190 docs / 300, 800 e 800
--       rótulos, construídos para este diagnóstico).
--
-- PRIMEIRA RODADA: 1 divergência em 78 casos — `dmpl / Reserva de lucros a
-- realizar` no fixture Canastra saiu com `valor_ultimo = 6834.0` no corpo
-- velho e `-6834.0` no novo. CAUSA: `(array_agg(o.valor_num order by
-- abs(o.valor_num) desc nulls last))[1]` (a "maior módulo, com o sinal", 0042)
-- não tinha desempate declarado para duas ocorrências de MESMO módulo e
-- sinal oposto — o Postgres resolve o empate pela ORDEM FÍSICA em que as
-- linhas chegam ao agregado, que depende do PLANO (por isso mudava com a
-- estratégia de junção). Isto já era uma ambiguidade latente do corpo
-- ANTERIOR (não introduzida por esta correção) — só que antes nenhuma
-- mudança de plano a expunha. Corrigida com um desempate DECLARADO (`, o.
-- valor_num desc` — prefere o valor POSITIVO em empate de módulo, que é o
-- que o corpo velho, por acidente de plano, já devolvia neste caso): depois
-- do desempate, SEGUNDA RODADA deu **0 divergências nos 78 casos**, nos dois
-- sentidos.
--
-- ---------------------------------------------------------------------------
-- O TESTE DE ESCALA NOVO — `Supabase/test/modelagem_versao_vigente_escala.
-- test.sql` — na ordem de 190 documentos / ~7.200 ocorrências / mais de 250
-- rótulos distintos (800, especificamente: foi o menor múltiplo de 100 que
-- reproduziu >8s de forma reprodutível neste hardware — 250 não reproduz,
-- 300 chega a ~2,5s sem estourar o teto, só a partir de ~700-800 o Nested
-- Loop cresce o bastante para bater o teto real do Supabase de forma
-- confiável, não como coincidência de uma rodada). É fixture de ESCALA — mede
-- TEMPO e PLANO, não prova nada sobre o conteúdo do caso real "Teste 00"
-- (regra 4 do CLAUDE.md: não inventar fixture para provar bug de produção
-- além do que dá para provar).
--
-- MEDIDO O INVARIANTE NÃO-VAZIO (regra 2): rodado com a correção DESLIGADA
-- (checkout do corpo da 0103, o filtro opaco de volta) contra o teste novo —
-- **2 dos 2 asserts do bloco de escala reprovaram** (o de tempo, por
-- `canceling statement due to statement timeout`, e o de plano, por Nested
-- Loop presente onde não deveria) — religado, os 2 passam. Ver a mensagem de
-- entrega para a transcrição exata.
--
-- ---------------------------------------------------------------------------
-- A SONDA — o que ela pode e não pode provar aqui.
--
-- `fn_instalacao_conferir` roda em produção, contra dados reais, e não pode
-- ficar cara para responder "esta migration foi aplicada?" — rodar o
-- fixture de escala inteiro dentro dela seria pagar de novo, para sempre, o
-- mesmo custo que esta migration existe para eliminar. O que ELA pode
-- provar barato, executando (não por marcador de comentário ou número de
-- migration — a auditoria desta sessão achou 19 requisitos assim, cegos a
-- regressão de comportamento):
--
--   (1) tipo=corpo, marcador='versao_vigente': o nome da CTE nova é código
--       ESTRUTURAL (o join que substitui o filtro opaco), não um comentário
--       decorativo — removê-la quebra a função, não sobra como substring
--       morta.
--   (2) tipo=comportamento: uma view PERMANENTE que EXECUTA fn_linhas_para_
--       modelagem contra um fixture fixo de dois documentos multi-versão
--       (um com reextração que CORRIGE o valor, outro com reextração em
--       andamento cuja versão nova AINDA NÃO TEM extração) e confere que a
--       versão vigente escolhida é a certa nos dois casos — exatamente a
--       regra que a 0102 escreveu e que um `versao_vigente` mal escrito
--       (a versão errada, ou um fan-out que duplica a ocorrência) quebraria
--       em silêncio. Não prova que o PLANO é bom (isso é papel do teste de
--       escala, que só roda em CI/dev) — prova que a REESCRITA preserva a
--       semântica que a 0102 existe para proteger.
-- =============================================================================

begin;

-- -----------------------------------------------------------------------------
-- (1) fn_linhas_para_modelagem — REEMITIDA INTEIRA (nunca por `replace` de
-- texto sobre pg_get_functiondef — `.claude/memory/nunca-corrigir-funcao-
-- por-replace.md`). Corpo idêntico ao anterior (0103) exceto: (i) a CTE
-- `versao_vigente` substitui o filtro `dv.id = fn_versao_com_extracao(d.id)`
-- por um join; (ii) `docs_do_caso` filtra o caso uma vez, fora do filtro por
-- linha; (iii) o desempate declarado em `valor_ultimo` (ver o cabeçalho).
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_linhas_para_modelagem(p_caso_id uuid) RETURNS TABLE(secao_canonica text, chave text, rotulo_norm text, entidade text, valor_ultimo numeric, n_ocorrencias bigint, papel text, unidade text, moeda text, documentos text[], sobreposicao_suspeita boolean)
    LANGUAGE sql STABLE
    AS $$
  -- marca-0102
  -- marca-0103
  -- marca-0164
  --
  -- AS TRÊS MARCAS FICAM. `fn_diagnostico_modelagem` (0102) confere se a
  -- correção daquela migration está instalada procurando `marca-0102` no
  -- corpo — é o teste que separa "mergeado" de "aplicado". Trocar a marca
  -- apagaria a resposta; a 0164 reemite o corpo e MANTÉM a regra da 0102
  -- ("só a versão vigente"), só muda COMO ela é expressa (join, não filtro
  -- opaco) — então as três marcas continuam verdadeiras.
  with docs_do_caso as (
    select d.id as documento_id, d.tipo_taxonomia, d.entidade_id
    from documento d
    where d.caso_id = p_caso_id
  ),
  -- 0164: A VERSÃO VIGENTE COMO JOIN, NÃO COMO FILTRO OPACO.
  --
  -- Mesma regra da 0102 ("a de maior n_versao que TEM campo_extraido"), mas
  -- como uma CTE nomeada que o planner enxerga e estima — em vez de um
  -- filtro `dv.id = fn_versao_com_extracao(d.id)` por linha, cuja
  -- seletividade o Postgres não sabe estimar (função opaca) e por isso
  -- chutava rows=1 para toda CTE construída em cima de `bruto`, mesmo a
  -- 7.220 linhas reais — a causa medida do Nested Loop que estourava os 8s
  -- do Supabase no caso "Teste 00" (190 documentos). Ver o cabeçalho.
  versao_vigente as (
    select distinct on (dv.documento_id)
           dv.documento_id, dv.id as documento_versao_id
    from documento_versao dv
    join docs_do_caso dc on dc.documento_id = dv.documento_id
    where exists (select 1 from campo_extraido ce where ce.documento_versao_id = dv.id)
    order by dv.documento_id, dv.n_versao desc
  ),
  bruto as (
    select
      ce.secao_canonica,
      ce.chave,
      fn_normalizar_texto(ce.chave) as rotulo_norm,
      coalesce(ce.entidade_coluna, e.razao_social) as entidade,
      ce.valor_num,
      ce.unidade,
      ce.moeda,
      dc.tipo_taxonomia
    from versao_vigente vv
    join docs_do_caso dc on dc.documento_id = vv.documento_id
    join campo_extraido ce on ce.documento_versao_id = vv.documento_versao_id
    left join entidade e on e.id = dc.entidade_id
    where ce.valor_num is not null
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
      -- valor da ocorrência de MAIOR MÓDULO, COM O SINAL (0042). 0164: em
      -- empate de módulo (duas ocorrências, sinais opostos), o desempate
      -- passa a ser DECLARADO (prefere o positivo) em vez de depender da
      -- ordem física em que o plano entrega as linhas — ver o cabeçalho
      -- desta migration para a divergência que expôs a ambiguidade latente.
      (array_agg(o.valor_num order by abs(o.valor_num) desc nulls last, o.valor_num desc))[1] as valor_ultimo,
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

COMMENT ON FUNCTION public.fn_linhas_para_modelagem(p_caso_id uuid) IS 'Linhas lógicas do caso para a tela de Modelagem, com PAPEL (conta/subtotal/derivado/serie_mensal), valor COM SINAL, unidade/moeda, documentos de origem e marca de sobreposição. Existe como função porque campo_extraido não tem caso_id — o escopo por caso mora aqui. 0101: papel calculado uma vez por rótulo e sobreposição por join, para caber no statement_timeout. 0102: só a versão VIGENTE de cada documento (reextração deixava a versão superada somando ocorrência e podendo ditar o valor_ultimo). 0164: a versão vigente passa a ser um JOIN nomeado (CTE versao_vigente), não um filtro por função opaca — o filtro antigo (dv.id = fn_versao_com_extracao(d.id)) fazia o planner estimar rows=1 para dezenas de milhares de linhas reais, escolhendo Nested Loop onde deveria escolher Hash Join (medido: 15,0s → 2,6s num fixture de 190 documentos/800 rótulos). Resultado idêntico ao anterior — comparado linha a linha, com except nos dois sentidos, contra 78 casos.';

-- -----------------------------------------------------------------------------
-- (2) O FIXTURE PERMANENTE "Sonda 0164" — dois documentos multi-versão, para
-- a sonda EXECUTAR a regra da 0102 através do código novo, em vez de
-- procurar marcador de texto (a auditoria desta sessão achou 19 requisitos
-- assim — cegos a uma regressão de comportamento que preserva o comentário).
--
-- Documento A: reextração que CORRIGE o valor. v1 tem campo_extraido com
-- valor 100; v2 (mais nova) tem campo_extraido com valor 250 — a vigente é
-- v2, e o valor tem de ser 250, não 350 (dobrado) nem 100 (a superada).
--
-- Documento B: reextração EM ANDAMENTO. v1 tem campo_extraido com valor
-- 777; v2 (mais nova) AINDA NÃO tem nenhum campo_extraido — a vigente
-- continua sendo v1 (a regra que fn_versao_com_extracao, e antes dela
-- fn_versao_atual, distinguem: "a mais nova" não é o mesmo que "a vigente
-- para quem lê conteúdo" nesta janela).
-- -----------------------------------------------------------------------------
insert into caso (id, nome, produto) values
  ('01640000-0000-0000-0000-000000000001'::uuid,
   'Sonda 0164 — versão vigente na modelagem (fixture da instalação, não é mandato real)',
   'reestruturacao')
on conflict (id) do nothing;

insert into documento (id, caso_id, tipo_taxonomia) values
  ('01640000-0000-0000-0000-000000000002'::uuid, '01640000-0000-0000-0000-000000000001'::uuid, 'BALANCO'),
  ('01640000-0000-0000-0000-000000000005'::uuid, '01640000-0000-0000-0000-000000000001'::uuid, 'BALANCO')
on conflict (id) do nothing;

insert into documento_versao (id, documento_id, n_versao, arquivo_ref) values
  ('01640000-0000-0000-0000-000000000003'::uuid, '01640000-0000-0000-0000-000000000002'::uuid, 1, 'sonda/0164/a1.pdf'),
  ('01640000-0000-0000-0000-000000000004'::uuid, '01640000-0000-0000-0000-000000000002'::uuid, 2, 'sonda/0164/a2.pdf'),
  ('01640000-0000-0000-0000-000000000006'::uuid, '01640000-0000-0000-0000-000000000005'::uuid, 1, 'sonda/0164/b1.pdf'),
  ('01640000-0000-0000-0000-000000000007'::uuid, '01640000-0000-0000-0000-000000000005'::uuid, 2, 'sonda/0164/b2.pdf')
on conflict (id) do nothing;

insert into campo_extraido (id, documento_versao_id, chave, valor_num, secao_canonica, unidade, moeda) values
  ('01640000-0000-0000-0000-000000000008'::uuid, '01640000-0000-0000-0000-000000000003'::uuid, 'Sonda 0164 caixa e equivalentes', 100, 'ativo_circulante', 'milhar', 'BRL'),
  ('01640000-0000-0000-0000-000000000009'::uuid, '01640000-0000-0000-0000-000000000004'::uuid, 'Sonda 0164 caixa e equivalentes', 250, 'ativo_circulante', 'milhar', 'BRL'),
  ('0164000a-0000-0000-0000-000000000010'::uuid, '01640000-0000-0000-0000-000000000006'::uuid, 'Sonda 0164 fornecedores a pagar', 777, 'passivo_circulante', 'milhar', 'BRL')
on conflict (id) do nothing;

-- -----------------------------------------------------------------------------
-- (3) A SONDA DE INSTALAÇÃO — a view abaixo EXECUTA fn_linhas_para_modelagem
-- contra o fixture acima, no modelo de instalacao_sonda_modelagem_pronta
-- (0158): só devolve 1 linha quando as DUAS regras de versão vigente batem
-- ao mesmo tempo.
-- -----------------------------------------------------------------------------
create or replace view instalacao_sonda_modelagem_versao_vigente as
select 1 as ok
where
  -- Documento A: a reextração CORRIGIU o valor — vigente é v2 (250), uma
  -- ocorrência só (não soma com a v1 superada, não duplica).
  (select l.valor_ultimo from fn_linhas_para_modelagem('01640000-0000-0000-0000-000000000001'::uuid) l
     where l.rotulo_norm = fn_normalizar_texto('Sonda 0164 caixa e equivalentes')) = 250
  and (select l.n_ocorrencias from fn_linhas_para_modelagem('01640000-0000-0000-0000-000000000001'::uuid) l
     where l.rotulo_norm = fn_normalizar_texto('Sonda 0164 caixa e equivalentes')) = 1
  -- Documento B: a reextração está EM ANDAMENTO — v2 não tem campo_extraido
  -- ainda, e a vigente continua sendo v1 (777), não desaparece nem some.
  and (select l.valor_ultimo from fn_linhas_para_modelagem('01640000-0000-0000-0000-000000000001'::uuid) l
     where l.rotulo_norm = fn_normalizar_texto('Sonda 0164 fornecedores a pagar')) = 777;

comment on view instalacao_sonda_modelagem_versao_vigente is
  '(0164) Autoteste de fn_linhas_para_modelagem, EXECUTADO contra um fixture PERMANENTE e isolado '
  '(o caso "Sonda 0164", que não é mandato real) com dois documentos multi-versão: 1 linha só se a '
  'reextração que CORRIGE o valor (v2 substitui v1, sem somar nem duplicar) e a reextração AINDA EM '
  'ANDAMENTO (v2 sem campo_extraido, a vigente continua v1) resolvem certo ao mesmo tempo. Prova que '
  'a CTE versao_vigente (0164, join que substituiu o filtro opaco fn_versao_com_extracao) preserva a '
  'regra da 0102 — não prova que o PLANO é bom (isso é papel de Supabase/test/'
  'modelagem_versao_vigente_escala.test.sql, que só roda em CI/dev): prova que a reescrita não '
  'regrediu a semântica.';

grant select on instalacao_sonda_modelagem_versao_vigente to authenticated;

-- -----------------------------------------------------------------------------
-- (4) GUARDA — confere o RESULTADO da reemissão, não a entrada.
-- -----------------------------------------------------------------------------
do $verifica0164$
declare
  v_src text;
  v_ok  boolean;
begin
  select pg_get_functiondef(p.oid) into v_src
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public' and p.proname = 'fn_linhas_para_modelagem';

  if v_src is null then
    raise exception '0164: fn_linhas_para_modelagem não existe depois da reemissão — algo abortou antes do CREATE OR REPLACE acima';
  end if;
  if position('versao_vigente' in v_src) = 0 then
    raise exception '0164: a reemissão saiu sem a CTE versao_vigente — abortado';
  end if;
  if position('marca-0102' in v_src) = 0 or position('marca-0103' in v_src) = 0 then
    raise exception '0164: a reemissão perdeu marca-0102/marca-0103 — abortado';
  end if;

  select exists(select 1 from instalacao_sonda_modelagem_versao_vigente) into v_ok;
  if not v_ok then
    raise exception '0164: a sonda de versão vigente não passou logo depois da reemissão — o fixture ou a função saíram errados';
  end if;
end $verifica0164$;

-- -----------------------------------------------------------------------------
-- (5) O CATÁLOGO DA SONDA
-- -----------------------------------------------------------------------------
insert into instalacao_requisito
  (chave, migration, tipo, objeto, marcador, criterio_seed, porque, severidade, ordem) values
  ('modelagem_versao_vigente_por_join', '0164', 'corpo', 'fn_linhas_para_modelagem',
   'versao_vigente', null,
   'fn_linhas_para_modelagem estourava os 8s do Supabase no caso "Teste 00" (190 documentos, 7.151 '
   'linhas) — medido: 15,0s num fixture de escala equivalente, Nested Loop com rows=1 estimado '
   'contra 7.220 reais, causado pelo filtro `dv.id = fn_versao_com_extracao(d.id)` (função opaca, '
   'seletividade não estimável). A CTE versao_vigente é o join estrutural que substitui o filtro — '
   'sem ela a função volta a ser código morto de tanto tempo até o timeout, e a tela volta a mostrar '
   '"caso sem linha extraída" para um caso que tem milhares.',
   'bloqueante', 620),
  ('modelagem_versao_vigente_regra_viva', '0164', 'seed', 'instalacao_sonda_modelagem_versao_vigente', null, 1,
   'Um requisito de "corpo" prova só que o texto versao_vigente está no arquivo, não que o join '
   'resolve a versão CERTA. Esta linha executa fn_linhas_para_modelagem contra um fixture de dois '
   'documentos multi-versão (reextração que corrige, reextração em andamento); ausente aqui quer '
   'dizer que a versão vigente pode ter voltado a somar/duplicar ocorrência de versão superada '
   '(o bug original da 0102) ou a sumir quando a versão mais nova ainda não tem extração.',
   'bloqueante', 621)
on conflict (chave) do update
  set migration = excluded.migration, tipo = excluded.tipo, objeto = excluded.objeto,
      marcador = excluded.marcador, criterio_seed = excluded.criterio_seed,
      porque = excluded.porque, severidade = excluded.severidade, ordem = excluded.ordem;

-- -----------------------------------------------------------------------------
-- A COBERTURA DECLARADA — até a 0164.
-- -----------------------------------------------------------------------------
update instalacao_cobertura
   set ate_migration = '0164',
       revisado_em = date '2026-09-11',
       observacao = 'Revisão de 11/09/2026: a 0164 reescreve fn_linhas_para_modelagem para trocar o '
                    'filtro opaco `dv.id = fn_versao_com_extracao(d.id)` (0102) por um join nomeado '
                    '(CTE versao_vigente), corrigindo a estimativa de cardinalidade que fazia o '
                    'planner escolher Nested Loop e estourar os 8s do Supabase no caso "Teste 00" '
                    '(190 documentos). Medido: 15,0s → 2,6s (5,7×) num fixture de escala de 190 '
                    'documentos/800 rótulos distintos, plano Nested Loop → Hash Join, estimativa de '
                    'linhas rows=1 → rows=6434 (real 7.220). Resultado comparado linha a linha (except '
                    'nos dois sentidos) contra os 75 casos do run.sh e três fixtures sintéticos: uma '
                    'divergência de sinal por empate de módulo não-determinístico (pré-existente, '
                    'exposta pela mudança de plano, não causada por ela), corrigida com desempate '
                    'declarado em valor_ultimo. Teste de escala novo em Supabase/test/'
                    'modelagem_versao_vigente_escala.test.sql (190 docs/~7.200 ocorrências/800 '
                    'rótulos > 250 do fixture antigo que mascarava o defeito): com a correção '
                    'desligada, 2 de 2 asserts do bloco de escala reprovaram (tempo e plano); '
                    'religada, os 2 passam. Sonda: corpo (versao_vigente, código estrutural, não '
                    'comentário) + comportamento executado (fixture permanente Sonda 0164, dois '
                    'documentos multi-versão) — não repete o padrão de 19 requisitos anteriores '
                    'cegos a marcador de comentário/número de migration.'
 where id;

commit;
