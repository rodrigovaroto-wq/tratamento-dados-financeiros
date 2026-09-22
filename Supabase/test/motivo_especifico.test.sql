-- Testes da 0188 (Supabase/migrations/0188_o_motivo_que_a_checagem_sabia_e_nao_dizia.sql).
-- Rodar via Supabase/test/run.sh, LOGO DEPOIS das fixtures e ANTES de qualquer
-- outro teste de reconciliação: os blocos 1 e 2 exigem os dois casos de
-- fixture sem nenhuma linha de reconciliação (o bloco 0 confere e reprova
-- dizendo isto, se alguém reordenar).
--
-- O QUE ESTE ARQUIVO TRAVA, em comportamento:
--
--   1. PARTE 1, O INVARIANTE, PELO DESPACHANTE DO LOTE (fn_reconciliar_caso):
--      sobre as fixtures dos dois books com SETE perturbações (uma por
--      checagem × motivo), as linhas de `reconciliacao` — (checagem, entidade,
--      período, concluiu?, resultado, quantas) — e as pendências de
--      reconciliação — (motivo, entidade, tipo, estado; o período não, ver
--      pg_temp.retrato_pend_0188) — são
--      EXATAMENTE as que os corpos da 0187 produziam. O literal abaixo foi
--      MEDIDO em 22/09/2026 num banco montado até a 0187 com as mesmas
--      perturbações (94 grupos de linha, 9 pendências), não escrito à mão. E o
--      não-vazio: das 53 linhas com precondição, TODAS passam a ter motivo
--      específico (12 linha_nao_localizada, 15 sem_periodo_par, 26
--      unidade_divergente) — na 0187 as 53 diziam "não especificado".
--   2. PARTE 1, O MESMO INVARIANTE PELO DESPACHANTE POR DOCUMENTO
--      (fn_reconciliar_por_documento → fn_reconciliar_chaves_do_documento): o
--      md5 do retrato é o medido na 0187 (109 grupos, 10 pendências), e 58
--      linhas saem com motivo específico.
--   3. PARTE 3, A ÚNICA EXCEÇÃO DECLARADA: DRE com "JUROS E COMISSÕES
--      BANCÁRIAS" satisfaz a exigência e a checagem despfin CONCLUI; DRE só com
--      "JUROS DE APLICAÇÕES" (rótulo medido em produção) e "JUROS DE APLICAÇÕES
--      BANCÁRIAS" continua NÃO satisfazendo, com o motivo linha_nao_localizada.
--   4. PARTE 2: DRE que publica só "RESULTADO FINANCEIRO LÍQUIDO" continua com
--      a pendência ABERTA (a alternativa nunca satisfaz), mas o texto diz o que
--      a DRE traz e o que pedir; a checagem despfin diz o mesmo; a pendência
--      que já existia com o texto velho é REESCRITA pelo recompute e pela
--      reescrita dirigida; DRE só com "RESULTADO ANTES DO RESULTADO
--      FINANCEIRO" fica com o texto de sempre, byte a byte.
--
-- AS PERTURBAÇÕES NÃO SÃO FIXTURE DE BUG DE PRODUÇÃO (regra 4): as fixtures
-- limpas não têm UMA linha com precondição genérica — medido: 0 de 80 grupos
-- na 0187 —, então sem perturbar o invariante seria verificado sobre o vazio
-- (.claude/memory/fixture-nasce-vazia.md). Cada uma exercita UM ramo, e o que o
-- bloco afirma é só "o ramo muda o motivo e não muda mais nada".
--
-- Os rótulos dos blocos 3 e 4 são os LITERAIS medidos em produção
-- (22/09/2026): "JUROS E COMISSÕES BANCÁRIAS", "JUROS DE APLICAÇÕES",
-- "RESULTADO FINANCEIRO LÍQUIDO", "RESULTADO ANTES DO RESULTADO FINANCEIRO".
-- A exceção é "JUROS DE APLICAÇÕES BANCÁRIAS", sintético e dito como tal: é o
-- único jeito de exercitar o `exclui ['aplicac']` com "juros" e "bancari"
-- presentes no mesmo rótulo.
--
-- O ASSERT NÃO PARA NO PRIMEIRO ERRO: anota e segue, e o bloco final reprova
-- com a CONTAGEM (regra 2 — medir quantos asserts cada correção desligada
-- derruba). TUDO numa transação que termina em ROLLBACK, com savepoint entre
-- os blocos 1 e 2: nada vaza para os testes seguintes.

begin;

-- A CONTAGEM MORA NUMA SEQUÊNCIA, e não numa tabela: os blocos 1 e 2 terminam
-- em `rollback to savepoint`, que desfaria o INSERT de uma tabela de falhas
-- junto com o resto — e o arquivo diria "PASSARAM" com asserts reprovados
-- (medido: foi o que a primeira versão deste arquivo fez). `nextval` não volta
-- com rollback.
create temp sequence _falhas_0188;

create or replace function pg_temp.teste_assert_0188(p_ok boolean, p_nome text, p_detalhe text default null)
returns void language plpgsql as $$
begin
  if coalesce(p_ok, false) then
    raise notice 'ok    %', p_nome;
  else
    raise notice 'FALHOU: % %', p_nome, coalesce(' — ' || p_detalhe, '');
    perform nextval('pg_temp._falhas_0188');
  end if;
end $$;

-- O RETRATO do que a reconciliação produziu nos dois casos de fixture: linha
-- por (caso, checagem, entidade, período, concluiu?, resultado) com a contagem,
-- e pendência de reconciliação por (caso, motivo, entidade, período, tipo,
-- estado). SEM motivo_precondicao, de propósito: é a única coisa que a parte 1
-- pode mudar.
create or replace function pg_temp.retrato_rec_0188()
returns table(caso text, tipo text, ent text, per text, ok boolean, resultado text, n bigint)
language sql as $f$
  select case when r.caso_id = '11111111-1111-1111-1111-111111111111' then 'V' else 'C' end,
         r.tipo, coalesce(e.razao_social, '-'), coalesce(p.tipo || ':' || p.referencia, '-'),
         r.precondicoes_ok, r.resultado, count(*)
    from reconciliacao r
    left join entidade e on e.id = r.entidade_id
    left join periodo p on p.id = r.periodo_id
   where r.caso_id in ('11111111-1111-1111-1111-111111111111', '11111111-3333-3333-3333-111111111111')
   group by 1, 2, 3, 4, 5, 6;
$f$;

-- SEM o período da pendência, e isto é medido, não preguiça: em
-- fn_reconciliar_caso (0152) o laço `for v_k in select distinct entidade_id,
-- periodo_id from documento` não tem `order by`, e a pendência leva o período
-- da PRIMEIRA chave que a abriu. Num banco recém-montado e no mesmo banco uma
-- segunda vez, a pendência do Caixa da CANASTRA INDÚSTRIA saiu com anual:2025 e
-- com multi:23,24,25 — com os corpos da 0187 E com os da 0188. Qual pendência
-- abre, com que tipo e estado, é determinístico; o período carimbado nela não.
create or replace function pg_temp.retrato_pend_0188()
returns table(caso text, motivo text, ent text, tipo text, estado text, n bigint)
language sql as $f$
  select case when x.caso_id = '11111111-1111-1111-1111-111111111111' then 'V' else 'C' end,
         x.motivo, coalesce(e.razao_social, '-'), x.tipo::text, x.estado::text, count(*)
    from pendencia x
    left join entidade e on e.id = x.entidade_id
   where x.caso_id in ('11111111-1111-1111-1111-111111111111', '11111111-3333-3333-3333-111111111111')
     and x.origem_estagio = 'reconciliacao'
   group by 1, 2, 3, 4, 5;
$f$;

-- O mesmo retrato como UM texto ordenado, para caber num md5 (bloco 2).
create or replace function pg_temp.retrato_texto_0188()
returns text
language sql as $f$
  select coalesce(string_agg(l, E'\n' order by l), '')
    from (select format('R|%s|%s|%s|%s|%s|%s|%s', caso, tipo, ent, per, ok, resultado, n) as l
            from pg_temp.retrato_rec_0188()
          union all
          select format('P|%s|%s|%s|%s|%s|%s', caso, motivo, ent, tipo, estado, n)
            from pg_temp.retrato_pend_0188()) x;
$f$;

-- AS SETE PERTURBAÇÕES, uma por (checagem × motivo). Devolve quantas linhas
-- cada uma tocou: zero em qualquer posição = a fixture mudou e o bloco ficaria
-- medindo o vazio (.claude/memory/fixture-nasce-vazia.md).
create or replace function pg_temp.perturbar_0188()
returns int[]
language plpgsql as $f$
declare
  v int[] := '{}';
  n int;
begin
  -- (1) linha_nao_localizada · ativo_passivo_pl · VERTENTES IMÓVEIS SPE: nenhum
  --     rótulo nem seção reconhecível (a mesma técnica do bloco 6 de
  --     reconciliacao.test.sql).
  update campo_extraido set chave = 'XPTO ' || id::text, secao = 'BLOCO SEM NOME'
   where documento_versao_id = '55555555-0000-0000-0000-000000000005';
  get diagnostics n = row_count; v := v || n;
  -- (2) sem_periodo_par · ativo_passivo_pl · CANASTRA AGROFLORESTAL: o balanço
  --     passa a ter colunas de período, nenhuma de 2023-2025.
  update campo_extraido set periodo_coluna = '2019'
   where documento_versao_id = '55555555-3333-0000-0000-000000000004';
  get diagnostics n = row_count; v := v || n;
  -- (3) linha_nao_localizada · caixa_bp_fluxo · VERTENTES METALÚRGICA (lado do BP).
  update campo_extraido set chave = 'XPTO ' || id::text, secao = 'BLOCO SEM NOME'
   where documento_versao_id = '55555555-0000-0000-0000-000000000001'
     and (fn_normalizar_texto(chave) ~ '(caixa|disponi|numerario|bancos)'
          or fn_normalizar_texto(coalesce(secao, '')) ~ '(caixa|disponi)');
  get diagnostics n = row_count; v := v || n;
  -- (4) unidade_divergente · caixa_bp_fluxo · CANASTRA INDÚSTRIA (lado da DFC):
  --     escala que fn_fator_escala não conhece.
  update campo_extraido set unidade = 'dezena'
   where documento_versao_id = '55555555-3333-0000-0000-000000000009';
  get diagnostics n = row_count; v := v || n;
  -- (5) unidade_divergente · despfin_dre_vs_divida · VERTENTES METALÚRGICA (DRE).
  update campo_extraido set unidade = 'dezena'
   where documento_versao_id = '55555555-0000-0000-0000-000000000007'
     and fn_normalizar_texto(chave) like '%despesas financeiras%';
  get diagnostics n = row_count; v := v || n;
  -- (6) unidade_divergente · receita_dre_vs_faturamento · VERTENTES METALÚRGICA
  --     (lado do faturamento).
  update campo_extraido set unidade = 'dezena'
   where documento_versao_id = '55555555-0000-0000-0000-000000000010';
  get diagnostics n = row_count; v := v || n;
  -- (7) sem_periodo_par · receita_dre_vs_faturamento · CANASTRA INDÚSTRIA (DRE).
  update campo_extraido set periodo_coluna = '2019'
   where documento_versao_id = '55555555-3333-0000-0000-000000000008';
  get diagnostics n = row_count; v := v || n;
  return v;
end;
$f$;

-- =============================================================================
do $$
declare
  v_n int;
begin
  raise notice '--- 0. a precondição dos blocos 1 e 2: fixtures sem reconciliação ---';
  select count(*) into v_n from reconciliacao
   where caso_id in ('11111111-1111-1111-1111-111111111111', '11111111-3333-3333-3333-111111111111');
  perform pg_temp.teste_assert_0188(v_n = 0,
    'os dois casos de fixture ainda não foram reconciliados (este arquivo roda logo depois das fixtures)',
    format('%s linha(s) já em reconciliacao — reordenaram o run.sh?', v_n));
end $$;

savepoint lote;

-- =============================================================================
do $$
declare
  v_toques int[];
  v_n      int;
  v_txt    text;
  v_desc   text;
begin
  raise notice '--- 1. PARTE 1 pelo despachante do LOTE: tudo igual à 0187, só o motivo muda ---';
  v_toques := pg_temp.perturbar_0188();
  perform pg_temp.teste_assert_0188(0 <> all(v_toques),
    'as sete perturbações tocaram linha (a fixture é a que o literal mediu)', v_toques::text);

  perform fn_reconciliar_caso('11111111-1111-1111-1111-111111111111');
  perform fn_reconciliar_caso('11111111-3333-3333-3333-111111111111');

  -- O LITERAL MEDIDO NA 0187 — ver o cabeçalho.
  create temp table _esperado_rec_0188 (caso text, tipo text, ent text, per text, ok boolean,
                                        resultado text, n bigint) on commit drop;
  insert into _esperado_rec_0188 values
    ('C', 'ativo_passivo_pl', 'CANASTRA AGROFLORESTAL LTDA.', 'L36M:23,24,25', false, 'precondicao_nao_satisfeita', 1),
    ('C', 'ativo_passivo_pl', 'CANASTRA AGROFLORESTAL LTDA.', 'anual:2025', false, 'precondicao_nao_satisfeita', 1),
    ('C', 'ativo_passivo_pl', 'CANASTRA AGROFLORESTAL LTDA.', 'data-base:2025-12-31', false, 'precondicao_nao_satisfeita', 1),
    ('C', 'ativo_passivo_pl', 'CANASTRA AGROFLORESTAL LTDA.', 'multi:23,24,25', false, 'precondicao_nao_satisfeita', 1),
    ('C', 'ativo_passivo_pl', 'CANASTRA AGROFLORESTAL LTDA.', 'multi:24,25', false, 'precondicao_nao_satisfeita', 1),
    ('C', 'ativo_passivo_pl', 'CANASTRA COMERCIAL E DISTRIBUIDORA LTDA.', 'multi:24,25', true, 'ok', 1),
    ('C', 'ativo_passivo_pl', 'CANASTRA IMOBILIÁRIA SPE LTDA.', 'anual:2025', true, 'ok', 1),
    ('C', 'ativo_passivo_pl', 'CANASTRA INDÚSTRIA DE EMBALAGENS LTDA.', 'anual:2025', true, 'ok', 1),
    ('C', 'ativo_passivo_pl', 'CANASTRA INDÚSTRIA DE EMBALAGENS LTDA.', 'multi:23,24,25', true, 'ok', 1),
    ('C', 'ativo_passivo_pl', 'CANASTRA PARTICIPAÇÕES S.A.', 'anual:2025', true, 'ok', 1),
    ('C', 'ativo_passivo_pl', 'CN TRANSPORTES E LOGÍSTICA LTDA.', 'anual:2025', true, 'ok', 1),
    ('C', 'ativo_passivo_pl', 'GRUPO CANASTRA', 'anual:2025', true, 'ok', 1),
    ('C', 'caixa_bp_fluxo', 'CANASTRA AGROFLORESTAL LTDA.', 'anual:2025', false, 'precondicao_nao_satisfeita', 1),
    ('C', 'caixa_bp_fluxo', 'CANASTRA COMERCIAL E DISTRIBUIDORA LTDA.', 'multi:24,25', false, 'precondicao_nao_satisfeita', 1),
    ('C', 'caixa_bp_fluxo', 'CANASTRA IMOBILIÁRIA SPE LTDA.', 'anual:2025', false, 'precondicao_nao_satisfeita', 1),
    ('C', 'caixa_bp_fluxo', 'CANASTRA INDÚSTRIA DE EMBALAGENS LTDA.', 'L36M:23,24,25', false, 'precondicao_nao_satisfeita', 2),
    ('C', 'caixa_bp_fluxo', 'CANASTRA INDÚSTRIA DE EMBALAGENS LTDA.', 'anual:2025', false, 'precondicao_nao_satisfeita', 2),
    ('C', 'caixa_bp_fluxo', 'CANASTRA INDÚSTRIA DE EMBALAGENS LTDA.', 'data-base:2025-12-31', false, 'precondicao_nao_satisfeita', 2),
    ('C', 'caixa_bp_fluxo', 'CANASTRA INDÚSTRIA DE EMBALAGENS LTDA.', 'multi:23,24,25', false, 'precondicao_nao_satisfeita', 2),
    ('C', 'caixa_bp_fluxo', 'CANASTRA INDÚSTRIA DE EMBALAGENS LTDA.', 'multi:24,25', false, 'precondicao_nao_satisfeita', 2),
    ('C', 'caixa_bp_fluxo', 'CANASTRA PARTICIPAÇÕES S.A.', 'anual:2025', false, 'precondicao_nao_satisfeita', 1),
    ('C', 'caixa_bp_fluxo', 'CN TRANSPORTES E LOGÍSTICA LTDA.', 'anual:2025', false, 'precondicao_nao_satisfeita', 1),
    ('C', 'caixa_bp_fluxo', 'GRUPO CANASTRA', 'anual:2025', false, 'precondicao_nao_satisfeita', 1),
    ('C', 'conflito_entre_documentos', 'CANASTRA AGROFLORESTAL LTDA.', '-', true, 'ok', 1),
    ('C', 'conflito_entre_documentos', 'CANASTRA COMERCIAL E DISTRIBUIDORA LTDA.', '-', true, 'ok', 1),
    ('C', 'conflito_entre_documentos', 'CANASTRA IMOBILIÁRIA SPE LTDA.', '-', true, 'ok', 1),
    ('C', 'conflito_entre_documentos', 'CANASTRA INDÚSTRIA DE EMBALAGENS LTDA.', '-', true, 'ok', 1),
    ('C', 'conflito_entre_documentos', 'CANASTRA PARTICIPAÇÕES S.A.', '-', true, 'ok', 1),
    ('C', 'conflito_entre_documentos', 'CN TRANSPORTES E LOGÍSTICA LTDA.', '-', true, 'ok', 1),
    ('C', 'conflito_entre_documentos', 'GRUPO CANASTRA', '-', true, 'ok', 1),
    ('C', 'despfin_dre_vs_divida', 'CANASTRA INDÚSTRIA DE EMBALAGENS LTDA.', 'multi:23,24,25', false, 'precondicao_nao_satisfeita', 1),
    ('C', 'despfin_dre_vs_divida', 'GRUPO CANASTRA', 'data-base:2025-12-31', false, 'precondicao_nao_satisfeita', 1),
    ('C', 'duplicidade_de_rotulo', 'CANASTRA AGROFLORESTAL LTDA.', '-', true, 'ok', 1),
    ('C', 'duplicidade_de_rotulo', 'CANASTRA COMERCIAL E DISTRIBUIDORA LTDA.', '-', true, 'ok', 1),
    ('C', 'duplicidade_de_rotulo', 'CANASTRA IMOBILIÁRIA SPE LTDA.', '-', true, 'ok', 1),
    ('C', 'duplicidade_de_rotulo', 'CANASTRA INDÚSTRIA DE EMBALAGENS LTDA.', '-', true, 'ok', 1),
    ('C', 'duplicidade_de_rotulo', 'CANASTRA PARTICIPAÇÕES S.A.', '-', true, 'ok', 1),
    ('C', 'duplicidade_de_rotulo', 'CN TRANSPORTES E LOGÍSTICA LTDA.', '-', true, 'ok', 1),
    ('C', 'duplicidade_de_rotulo', 'GRUPO CANASTRA', '-', true, 'ok', 1),
    ('C', 'intragrupo_espelho', '-', 'anual:2025', true, 'ok', 1),
    ('C', 'intragrupo_espelho', '-', 'multi:23,24,25', true, 'ok', 1),
    ('C', 'intragrupo_espelho', '-', 'multi:24,25', true, 'ok', 1),
    ('C', 'mutuos_planilha_vs_balanco', '-', 'anual:2025', true, 'zona_cinzenta', 1),
    ('C', 'mutuos_planilha_vs_balanco', '-', 'multi:23,24,25', true, 'zona_cinzenta', 1),
    ('C', 'mutuos_planilha_vs_balanco', '-', 'multi:24,25', true, 'zona_cinzenta', 1),
    ('C', 'receita_dre_vs_faturamento', 'CANASTRA INDÚSTRIA DE EMBALAGENS LTDA.', 'L36M:23,24,25', false, 'precondicao_nao_satisfeita', 2),
    ('C', 'receita_dre_vs_faturamento', 'CANASTRA INDÚSTRIA DE EMBALAGENS LTDA.', 'anual:2025', false, 'precondicao_nao_satisfeita', 2),
    ('C', 'receita_dre_vs_faturamento', 'CANASTRA INDÚSTRIA DE EMBALAGENS LTDA.', 'data-base:2025-12-31', false, 'precondicao_nao_satisfeita', 2),
    ('C', 'receita_dre_vs_faturamento', 'CANASTRA INDÚSTRIA DE EMBALAGENS LTDA.', 'multi:23,24,25', false, 'precondicao_nao_satisfeita', 2),
    ('C', 'receita_dre_vs_faturamento', 'CANASTRA INDÚSTRIA DE EMBALAGENS LTDA.', 'multi:24,25', false, 'precondicao_nao_satisfeita', 2),
    ('V', 'ativo_passivo_pl', 'GRUPO VERTENTES', 'anual:2025', true, 'ok', 1),
    ('V', 'ativo_passivo_pl', 'VERTENTES COMPONENTES AUTOMOTIVOS LTDA.', 'anual:2025', true, 'ok', 1),
    ('V', 'ativo_passivo_pl', 'VERTENTES COMPONENTES AUTOMOTIVOS LTDA.', 'multi:24,25', true, 'ok', 1),
    ('V', 'ativo_passivo_pl', 'VERTENTES IMÓVEIS SPE LTDA.', 'L24M:24,25', false, 'precondicao_nao_satisfeita', 1),
    ('V', 'ativo_passivo_pl', 'VERTENTES IMÓVEIS SPE LTDA.', 'anual:2025', false, 'precondicao_nao_satisfeita', 1),
    ('V', 'ativo_passivo_pl', 'VERTENTES IMÓVEIS SPE LTDA.', 'data-base:2025-12-31', false, 'precondicao_nao_satisfeita', 1),
    ('V', 'ativo_passivo_pl', 'VERTENTES IMÓVEIS SPE LTDA.', 'multi:24,25', false, 'precondicao_nao_satisfeita', 1),
    ('V', 'ativo_passivo_pl', 'VERTENTES METALÚRGICA LTDA.', 'multi:24,25', true, 'ok', 1),
    ('V', 'ativo_passivo_pl', 'VERTENTES PARTICIPAÇÕES S.A.', 'multi:24,25', true, 'ok', 1),
    ('V', 'ativo_passivo_pl', 'VT LOGÍSTICA E TRANSPORTES LTDA.', 'multi:24,25', true, 'ok', 1),
    ('V', 'caixa_bp_fluxo', 'GRUPO VERTENTES', 'anual:2025', false, 'precondicao_nao_satisfeita', 1),
    ('V', 'caixa_bp_fluxo', 'VERTENTES COMPONENTES AUTOMOTIVOS LTDA.', 'anual:2025', false, 'precondicao_nao_satisfeita', 1),
    ('V', 'caixa_bp_fluxo', 'VERTENTES COMPONENTES AUTOMOTIVOS LTDA.', 'multi:24,25', false, 'precondicao_nao_satisfeita', 1),
    ('V', 'caixa_bp_fluxo', 'VERTENTES IMÓVEIS SPE LTDA.', 'multi:24,25', false, 'precondicao_nao_satisfeita', 1),
    ('V', 'caixa_bp_fluxo', 'VERTENTES METALÚRGICA LTDA.', 'L24M:24,25', false, 'precondicao_nao_satisfeita', 2),
    ('V', 'caixa_bp_fluxo', 'VERTENTES METALÚRGICA LTDA.', 'anual:2025', false, 'precondicao_nao_satisfeita', 2),
    ('V', 'caixa_bp_fluxo', 'VERTENTES METALÚRGICA LTDA.', 'data-base:2025-12-31', false, 'precondicao_nao_satisfeita', 2),
    ('V', 'caixa_bp_fluxo', 'VERTENTES METALÚRGICA LTDA.', 'multi:24,25', false, 'precondicao_nao_satisfeita', 2),
    ('V', 'caixa_bp_fluxo', 'VERTENTES PARTICIPAÇÕES S.A.', 'multi:24,25', false, 'precondicao_nao_satisfeita', 1),
    ('V', 'caixa_bp_fluxo', 'VT LOGÍSTICA E TRANSPORTES LTDA.', 'multi:24,25', false, 'precondicao_nao_satisfeita', 1),
    ('V', 'conflito_entre_documentos', 'GRUPO VERTENTES', '-', true, 'ok', 1),
    ('V', 'conflito_entre_documentos', 'VERTENTES COMPONENTES AUTOMOTIVOS LTDA.', '-', true, 'ok', 1),
    ('V', 'conflito_entre_documentos', 'VERTENTES IMÓVEIS SPE LTDA.', '-', true, 'ok', 1),
    ('V', 'conflito_entre_documentos', 'VERTENTES METALÚRGICA LTDA.', '-', true, 'ok', 1),
    ('V', 'conflito_entre_documentos', 'VERTENTES PARTICIPAÇÕES S.A.', '-', true, 'ok', 1),
    ('V', 'conflito_entre_documentos', 'VT LOGÍSTICA E TRANSPORTES LTDA.', '-', true, 'ok', 1),
    ('V', 'despfin_dre_vs_divida', 'VERTENTES METALÚRGICA LTDA.', 'L24M:24,25', false, 'precondicao_nao_satisfeita', 2),
    ('V', 'despfin_dre_vs_divida', 'VERTENTES METALÚRGICA LTDA.', 'anual:2025', false, 'precondicao_nao_satisfeita', 2),
    ('V', 'despfin_dre_vs_divida', 'VERTENTES METALÚRGICA LTDA.', 'data-base:2025-12-31', false, 'precondicao_nao_satisfeita', 2),
    ('V', 'despfin_dre_vs_divida', 'VERTENTES METALÚRGICA LTDA.', 'multi:24,25', false, 'precondicao_nao_satisfeita', 2),
    ('V', 'duplicidade_de_rotulo', 'GRUPO VERTENTES', '-', true, 'ok', 1),
    ('V', 'duplicidade_de_rotulo', 'VERTENTES COMPONENTES AUTOMOTIVOS LTDA.', '-', true, 'ok', 1),
    ('V', 'duplicidade_de_rotulo', 'VERTENTES IMÓVEIS SPE LTDA.', '-', true, 'ok', 1),
    ('V', 'duplicidade_de_rotulo', 'VERTENTES METALÚRGICA LTDA.', '-', true, 'ok', 1),
    ('V', 'duplicidade_de_rotulo', 'VERTENTES PARTICIPAÇÕES S.A.', '-', true, 'ok', 1),
    ('V', 'duplicidade_de_rotulo', 'VT LOGÍSTICA E TRANSPORTES LTDA.', '-', true, 'ok', 1),
    ('V', 'intragrupo_espelho', '-', 'anual:2025', true, 'ok', 1),
    ('V', 'intragrupo_espelho', '-', 'multi:24,25', true, 'ok', 1),
    ('V', 'mutuos_planilha_vs_balanco', '-', 'anual:2025', true, 'zona_cinzenta', 1),
    ('V', 'mutuos_planilha_vs_balanco', '-', 'multi:24,25', true, 'zona_cinzenta', 1),
    ('V', 'receita_dre_vs_faturamento', 'VERTENTES METALÚRGICA LTDA.', 'L24M:24,25', false, 'precondicao_nao_satisfeita', 2),
    ('V', 'receita_dre_vs_faturamento', 'VERTENTES METALÚRGICA LTDA.', 'anual:2025', false, 'precondicao_nao_satisfeita', 2),
    ('V', 'receita_dre_vs_faturamento', 'VERTENTES METALÚRGICA LTDA.', 'data-base:2025-12-31', false, 'precondicao_nao_satisfeita', 2),
    ('V', 'receita_dre_vs_faturamento', 'VERTENTES METALÚRGICA LTDA.', 'multi:24,25', false, 'precondicao_nao_satisfeita', 2);
  create temp table _esperado_pend_0188 (caso text, motivo text, ent text, tipo text,
                                         estado text, n bigint) on commit drop;
  insert into _esperado_pend_0188 values
    ('C', 'reconciliacao:ativo_passivo_pl', 'CANASTRA AGROFLORESTAL LTDA.', 'precondicao_nao_satisfeita', 'aberta', 1),
    ('C', 'reconciliacao:caixa_bp_fluxo', 'CANASTRA INDÚSTRIA DE EMBALAGENS LTDA.', 'precondicao_nao_satisfeita', 'aberta', 1),
    ('C', 'reconciliacao:mutuos_planilha_vs_balanco', '-', 'divergencia_reconciliacao', 'aberta', 1),
    ('C', 'reconciliacao:receita_dre_vs_faturamento', 'CANASTRA INDÚSTRIA DE EMBALAGENS LTDA.', 'precondicao_nao_satisfeita', 'aberta', 1),
    ('V', 'reconciliacao:ativo_passivo_pl', 'VERTENTES IMÓVEIS SPE LTDA.', 'precondicao_nao_satisfeita', 'aberta', 1),
    ('V', 'reconciliacao:caixa_bp_fluxo', 'VERTENTES METALÚRGICA LTDA.', 'precondicao_nao_satisfeita', 'aberta', 1),
    ('V', 'reconciliacao:despfin_dre_vs_divida', 'VERTENTES METALÚRGICA LTDA.', 'precondicao_nao_satisfeita', 'aberta', 1),
    ('V', 'reconciliacao:mutuos_planilha_vs_balanco', '-', 'divergencia_reconciliacao', 'aberta', 1),
    ('V', 'reconciliacao:receita_dre_vs_faturamento', 'VERTENTES METALÚRGICA LTDA.', 'precondicao_nao_satisfeita', 'aberta', 1);

  select count(*), string_agg(format('%s|%s|%s|%s|%s|%s|%s', caso, tipo, ent, per, ok, resultado, n), E'\n')
    into v_n, v_txt
    from ((select * from pg_temp.retrato_rec_0188() except select * from _esperado_rec_0188)
          union all
          (select * from _esperado_rec_0188 except select * from pg_temp.retrato_rec_0188())) d;
  perform pg_temp.teste_assert_0188(v_n = 0,
    'as linhas de reconciliacao (checagem, entidade, período, concluiu?, resultado, quantas) são '
    'as da 0187 — nenhuma nasceu, sumiu, ou mudou de resultado',
    format('%s diferença(s):%s%s', v_n, E'\n', v_txt));

  select count(*), string_agg(format('%s|%s|%s|%s|%s|%s', caso, motivo, ent, tipo, estado, n), E'\n')
    into v_n, v_txt
    from ((select * from pg_temp.retrato_pend_0188() except select * from _esperado_pend_0188)
          union all
          (select * from _esperado_pend_0188 except select * from pg_temp.retrato_pend_0188())) d;
  perform pg_temp.teste_assert_0188(v_n = 0,
    'e as pendências de reconciliação (quais abrem, de quem, com que tipo e estado) também',
    format('%s diferença(s):%s%s', v_n, E'\n', v_txt));

  -- O NÃO-VAZIO: o motivo que a 0187 gravava "não especificado".
  select count(*) into v_n from reconciliacao
   where caso_id in ('11111111-1111-1111-1111-111111111111', '11111111-3333-3333-3333-111111111111')
     and not precondicoes_ok and motivo_precondicao = 'precondicao_nao_satisfeita';
  perform pg_temp.teste_assert_0188(v_n = 0,
    'nenhuma das precondições perturbadas fica com o motivo genérico', format('%s genérica(s)', v_n));

  select string_agg(format('%s=%s', m, n), ' ' order by m) into v_txt
    from (select motivo_precondicao m, count(*) n from reconciliacao
           where caso_id in ('11111111-1111-1111-1111-111111111111', '11111111-3333-3333-3333-111111111111')
             and not precondicoes_ok and motivo_precondicao <> 'documento_ausente'
           group by 1) x;
  perform pg_temp.teste_assert_0188(
    v_txt = 'linha_nao_localizada=12 sem_periodo_par=15 unidade_divergente=26',
    'as 53 passam a dizer o motivo: 12 linha não localizada, 15 sem período par, 26 unidade divergente',
    coalesce(v_txt, '(nenhuma)'));

  -- Cada ramo com o SEU motivo, e não só o total certo por acaso.
  select string_agg(distinct r.tipo || ':' || r.motivo_precondicao, ' ' order by r.tipo || ':' || r.motivo_precondicao)
    into v_txt
    from reconciliacao r
   where r.caso_id in ('11111111-1111-1111-1111-111111111111', '11111111-3333-3333-3333-111111111111')
     and not r.precondicoes_ok and r.motivo_precondicao <> 'documento_ausente';
  perform pg_temp.teste_assert_0188(
    v_txt = 'ativo_passivo_pl:linha_nao_localizada ativo_passivo_pl:sem_periodo_par '
            'caixa_bp_fluxo:linha_nao_localizada caixa_bp_fluxo:unidade_divergente '
            'despfin_dre_vs_divida:unidade_divergente receita_dre_vs_faturamento:sem_periodo_par '
            'receita_dre_vs_faturamento:unidade_divergente',
    'e cada um dos sete ramos perturbados sai com o motivo DELE', coalesce(v_txt, '(nenhum)'));

  -- documento_ausente não se mexe (o CONTRATO da 0186).
  select count(*) into v_n from reconciliacao
   where caso_id in ('11111111-1111-1111-1111-111111111111', '11111111-3333-3333-3333-111111111111')
     and motivo_precondicao = 'documento_ausente';
  perform pg_temp.teste_assert_0188(v_n = 14,
    'documento_ausente continua onde estava: 14 linhas, as mesmas da 0187', format('%s', v_n));

  -- O TEXTO: motivo e remédio NA FRENTE, e o texto antigo inteiro depois.
  select descricao into v_desc from pendencia
   where caso_id = '11111111-1111-1111-1111-111111111111'
     and motivo = 'reconciliacao:ativo_passivo_pl' and estado <> 'resolvida';
  perform pg_temp.teste_assert_0188(
    v_desc like 'MOTIVO: linha não localizada%' and v_desc like '%nenhum exercício teve os DOIS lados%'
      and v_desc like '%Rótulos que a extração TROUXE%',
    'a pendência do Ativo × Passivo+PL diz o motivo e o remédio, e mantém o texto de antes',
    left(v_desc, 240));

  select descricao into v_desc from pendencia
   where caso_id = '11111111-3333-3333-3333-111111111111'
     and motivo = 'reconciliacao:ativo_passivo_pl' and estado <> 'resolvida';
  perform pg_temp.teste_assert_0188(
    v_desc like 'MOTIVO: sem período par%' and v_desc like '%coluna de período: (nenhuma deste exercício)%'
      and v_desc not like '%coluna de período: (qualquer)%',
    'sem período par: a sentinela deixa de aparecer como "(qualquer)", que era o contrário',
    left(v_desc, 400));

  select descricao into v_desc from pendencia
   where caso_id = '11111111-3333-3333-3333-111111111111'
     and motivo = 'reconciliacao:caixa_bp_fluxo' and estado <> 'resolvida';
  perform pg_temp.teste_assert_0188(
    v_desc like 'MOTIVO: unidade divergente%' and v_desc like '%não conversíveis%',
    'unidade divergente: o prefixo mais o texto de fn_motivo_escala_incomparavel', left(v_desc, 240));
end $$;

rollback to savepoint lote;
savepoint documento;

-- =============================================================================
do $$
declare
  v_toques int[];
  v_md5    text;
  v_n      int;
begin
  raise notice '--- 2. PARTE 1 pelo despachante POR DOCUMENTO: o mesmo retrato da 0187 ---';
  v_toques := pg_temp.perturbar_0188();
  perform fn_reconciliar_por_documento(d.id)
     from documento d
    where d.caso_id in ('11111111-1111-1111-1111-111111111111', '11111111-3333-3333-3333-111111111111')
    order by d.criado_em, d.id;

  v_md5 := md5(pg_temp.retrato_texto_0188());
  -- MEDIDO na 0187, mesmas perturbações, mesma ordem de documentos: 109 grupos
  -- de linha e 10 pendências.
  perform pg_temp.teste_assert_0188(v_md5 = 'd812395578bec0544c84e16072494c5d',
    'o retrato (linhas + pendências, sem o motivo) é byte a byte o da 0187',
    v_md5 || E'\n' || pg_temp.retrato_texto_0188());

  select count(*) into v_n from reconciliacao
   where caso_id in ('11111111-1111-1111-1111-111111111111', '11111111-3333-3333-3333-111111111111')
     and motivo_precondicao in ('linha_nao_localizada', 'sem_periodo_par', 'unidade_divergente');
  perform pg_temp.teste_assert_0188(v_n = 58,
    'e 58 linhas saem com motivo específico (na 0187, as 58 diziam "não especificado")',
    format('%s', v_n));
end $$;

rollback to savepoint documento;

-- =============================================================================
do $$
declare
  v_caso_pos uuid;
  v_caso_neg uuid;
  v_r        jsonb;
  v_ver      uuid;
  v_doc      uuid;
  v_ent      uuid;
  v_per      uuid;
  v_ok       boolean;
  v_bool     boolean;
  v_motivo   text;
  v_n        int;
begin
  raise notice '--- 3. PARTE 3 (a exceção declarada): "JUROS E COMISSÕES BANCÁRIAS" ---';
  v_caso_pos := (fn_upsert_caso('0188: juros bancários'))::uuid;
  v_r := fn_registrar_documento(v_caso_pos, 'JUROS BANCARIOS LTDA.', 'anual', '2025', 'DRE', 0.95,
    'nome_arquivo', 'supabase_storage', '0188/dre-pos.pdf', 'DRE POS.pdf', true, 'HASH-0188-1', 'ok');
  v_ver := (v_r->>'documento_versao_id')::uuid;
  v_doc := (v_r->>'documento_id')::uuid;
  perform fn_registrar_campos_extraidos(v_ver, jsonb_build_array(
    jsonb_build_object('ordem',0,'chave','RECEITA OPERACIONAL BRUTA','valor_num','10000','periodo_coluna','2025','unidade','unidade','confianca','0.97'),
    jsonb_build_object('ordem',1,'chave','JUROS E COMISSÕES BANCÁRIAS','valor_num','-1200','periodo_coluna','2025','unidade','unidade','confianca','0.97')
  ), 'N2');
  v_r := fn_registrar_documento(v_caso_pos, 'JUROS BANCARIOS LTDA.', 'anual', '2025', 'MAPA_DIVIDA', 0.95,
    'nome_arquivo', 'supabase_storage', '0188/div-pos.pdf', 'DIVIDA POS.pdf', true, 'HASH-0188-2', 'ok');
  perform fn_registrar_campos_extraidos((v_r->>'documento_versao_id')::uuid, jsonb_build_array(
    jsonb_build_object('ordem',0,'chave','Banco A - capital de giro - juros do exercício','valor_num','1200','unidade','unidade','confianca','0.97')
  ), 'N2');
  select entidade_id, periodo_id into v_ent, v_per from documento where id = v_doc;

  select x.satisfeita into v_bool from fn_exigencias_do_caso(v_caso_pos) x
   where x.tipo_taxonomia = 'DRE' and x.conceito = 'despesa_financeira';
  perform pg_temp.teste_assert_0188(v_bool,
    'a exigência DRE/despesa_financeira fica SATISFEITA pelo localizador ["juros","bancari"]',
    coalesce(v_bool::text, '(sem linha)'));
  select count(*) into v_n from pendencia
   where caso_id = v_caso_pos and tipo = 'linha_exigida_ausente' and estado <> 'resolvida'
     and motivo like 'completude:linha_exigida:DRE:despesa\_financeira%';
  perform pg_temp.teste_assert_0188(v_n = 0,
    'e a pendência falsa de despesa financeira NÃO abre', format('%s aberta(s)', v_n));

  perform fn_reconciliar_despfin_dre_vs_divida(v_caso_pos, v_ent, v_per);
  select precondicoes_ok, resultado into v_ok, v_motivo from reconciliacao
   where caso_id = v_caso_pos and tipo = 'despfin_dre_vs_divida' order by criado_em desc limit 1;
  perform pg_temp.teste_assert_0188(v_ok and v_motivo = 'ok',
    'e a checagem despfin CONCLUI (1.200 da DRE = 1.200 do mapa) — o espelho do seed no código',
    format('precondicoes_ok=%s resultado=%s', v_ok, v_motivo));

  -- O NEGATIVO, obrigatório.
  v_caso_neg := (fn_upsert_caso('0188: juros de aplicação'))::uuid;
  v_r := fn_registrar_documento(v_caso_neg, 'APLICACOES LTDA.', 'anual', '2025', 'DRE', 0.95,
    'nome_arquivo', 'supabase_storage', '0188/dre-neg.pdf', 'DRE NEG.pdf', true, 'HASH-0188-3', 'ok');
  v_ver := (v_r->>'documento_versao_id')::uuid;
  v_doc := (v_r->>'documento_id')::uuid;
  perform fn_registrar_campos_extraidos(v_ver, jsonb_build_array(
    jsonb_build_object('ordem',0,'chave','RECEITA OPERACIONAL BRUTA','valor_num','10000','periodo_coluna','2025','unidade','unidade','confianca','0.97'),
    jsonb_build_object('ordem',1,'chave','JUROS DE APLICAÇÕES','valor_num','300','periodo_coluna','2025','unidade','unidade','confianca','0.97'),
    jsonb_build_object('ordem',2,'chave','JUROS DE APLICAÇÕES BANCÁRIAS','valor_num','200','periodo_coluna','2025','unidade','unidade','confianca','0.97')
  ), 'N2');
  v_r := fn_registrar_documento(v_caso_neg, 'APLICACOES LTDA.', 'anual', '2025', 'MAPA_DIVIDA', 0.95,
    'nome_arquivo', 'supabase_storage', '0188/div-neg.pdf', 'DIVIDA NEG.pdf', true, 'HASH-0188-4', 'ok');
  perform fn_registrar_campos_extraidos((v_r->>'documento_versao_id')::uuid, jsonb_build_array(
    jsonb_build_object('ordem',0,'chave','Banco B - capital de giro - juros do exercício','valor_num','500','unidade','unidade','confianca','0.97')
  ), 'N2');
  select entidade_id, periodo_id into v_ent, v_per from documento where id = v_doc;

  select x.satisfeita into v_bool from fn_exigencias_do_caso(v_caso_neg) x
   where x.tipo_taxonomia = 'DRE' and x.conceito = 'despesa_financeira';
  perform pg_temp.teste_assert_0188(not v_bool,
    'NEGATIVO: "JUROS DE APLICAÇÕES" (e "…BANCÁRIAS") é receita e NÃO satisfaz a exigência',
    coalesce(v_bool::text, '(sem linha)'));
  select count(*) into v_n from pendencia
   where caso_id = v_caso_neg and tipo = 'linha_exigida_ausente' and estado = 'aberta'
     and motivo like 'completude:linha_exigida:DRE:despesa\_financeira%';
  perform pg_temp.teste_assert_0188(v_n = 1,
    '…e a pendência de despesa financeira continua abrindo', format('%s aberta(s)', v_n));

  perform fn_reconciliar_despfin_dre_vs_divida(v_caso_neg, v_ent, v_per);
  select precondicoes_ok, motivo_precondicao into v_ok, v_motivo from reconciliacao
   where caso_id = v_caso_neg and tipo = 'despfin_dre_vs_divida' order by criado_em desc limit 1;
  perform pg_temp.teste_assert_0188(not v_ok and v_motivo = 'linha_nao_localizada',
    '…e a checagem despfin NÃO conclui, com o motivo linha_nao_localizada',
    format('precondicoes_ok=%s motivo=%s', v_ok, v_motivo));
end $$;

-- =============================================================================
do $$
declare
  v_caso      uuid;
  v_caso_neg  uuid;
  v_r         jsonb;
  v_ver       uuid;
  v_doc       uuid;
  v_ent       uuid;
  v_per       uuid;
  v_ex        record;
  v_desc      text;
  v_pend      uuid;
  v_txt       text;
  v_velho     text;
  v_n         int;
begin
  raise notice '--- 4. PARTE 2: a DRE que publica só o resultado financeiro LÍQUIDO ---';
  v_caso := (fn_upsert_caso('0188: resultado financeiro liquido'))::uuid;
  v_r := fn_registrar_documento(v_caso, 'LIQUIDO LTDA.', 'anual', '2025', 'DRE', 0.95,
    'nome_arquivo', 'supabase_storage', '0188/dre-liq.pdf', 'DRE LIQ.pdf', true, 'HASH-0188-5', 'ok');
  v_ver := (v_r->>'documento_versao_id')::uuid;
  v_doc := (v_r->>'documento_id')::uuid;
  perform fn_registrar_campos_extraidos(v_ver, jsonb_build_array(
    jsonb_build_object('ordem',0,'chave','RECEITA OPERACIONAL BRUTA','valor_num','10000','periodo_coluna','2025','unidade','unidade','confianca','0.97'),
    jsonb_build_object('ordem',1,'chave','RESULTADO ANTES DO RESULTADO FINANCEIRO','valor_num','2000','periodo_coluna','2025','unidade','unidade','confianca','0.97'),
    jsonb_build_object('ordem',2,'chave','RESULTADO FINANCEIRO LÍQUIDO','valor_num','-800','periodo_coluna','2025','unidade','unidade','confianca','0.97')
  ), 'N2');
  select entidade_id, periodo_id into v_ent, v_per from documento where id = v_doc;

  select * into v_ex from fn_exigencias_do_caso(v_caso) x
   where x.tipo_taxonomia = 'DRE' and x.conceito = 'despesa_financeira';
  perform pg_temp.teste_assert_0188(not v_ex.satisfeita,
    'a alternativa NUNCA satisfaz: a linha exigida continua ausente',
    coalesce(v_ex.satisfeita::text, '(sem linha)'));
  perform pg_temp.teste_assert_0188(v_ex.alternativa_rotulo = 'RESULTADO FINANCEIRO LÍQUIDO',
    'fn_exigencias_do_caso diz o que a DRE traz no lugar (e NÃO o "resultado antes do resultado financeiro")',
    coalesce(v_ex.alternativa_rotulo, '(null)'));

  select id, descricao into v_pend, v_desc from pendencia
   where caso_id = v_caso and tipo = 'linha_exigida_ausente' and estado = 'aberta'
     and motivo like 'completude:linha_exigida:DRE:despesa\_financeira%';
  perform pg_temp.teste_assert_0188(v_pend is not null,
    'a pendência de despesa financeira continua ABERTA — a ausência é real');
  perform pg_temp.teste_assert_0188(
    v_desc like '%o documento traz "RESULTADO FINANCEIRO LÍQUIDO" no lugar%'
      and v_desc like '%pedir ao cliente a abertura do resultado financeiro%'
      and v_desc not like '%com outro rótulo%',
    'e o texto diz o que a DRE traz e o que pedir, em vez de "conferir o rótulo ou reenviar"',
    left(v_desc, 300));

  -- A pendência que JÁ EXISTIA antes da 0188 — que é o estado das 50 de
  -- produção — tem o texto velho. O recompute tem de reescrevê-lo.
  v_velho := fn_descricao_linha_exigida(v_ex.tipo_taxonomia, v_ex.entidade, v_ex.rotulo,
                                        v_ex.depende_de, v_ex.origem, null, null);
  update pendencia set descricao = v_velho where id = v_pend;
  perform fn_recomputar_completude(v_caso);
  select descricao into v_txt from pendencia where id = v_pend;
  perform pg_temp.teste_assert_0188(v_txt = v_desc,
    'o recompute REESCREVE a descrição da pendência que já estava aberta (antes só a severidade mudava)',
    left(v_txt, 200));

  -- E a reescrita dirigida da migration, sem recompute.
  update pendencia set descricao = v_velho where id = v_pend;
  v_r := fn_reescrever_recado_linha_exigida('DRE', 'despesa_financeira');
  select descricao into v_txt from pendencia where id = v_pend;
  perform pg_temp.teste_assert_0188(v_txt = v_desc,
    'a reescrita dirigida (fn_reescrever_recado_linha_exigida) leva o mesmo texto que o recompute',
    left(v_txt, 200));
  -- 1 = só esta. A do bloco 3 negativo ("JUROS DE APLICAÇÕES") está aberta e
  -- não tem alternativa: não pode ser tocada.
  perform pg_temp.teste_assert_0188((v_r->>'reescritas')::int = 1,
    '…e reescreve SÓ a que tem alternativa (a do bloco 3, sem alternativa, fica)', v_r::text);

  -- A CHECAGEM diz o mesmo recado (a pendência de reconciliação B abre neste
  -- banco: dial classe_bc influencia).
  v_r := fn_registrar_documento(v_caso, 'LIQUIDO LTDA.', 'anual', '2025', 'MAPA_DIVIDA', 0.95,
    'nome_arquivo', 'supabase_storage', '0188/div-liq.pdf', 'DIVIDA LIQ.pdf', true, 'HASH-0188-6', 'ok');
  perform fn_registrar_campos_extraidos((v_r->>'documento_versao_id')::uuid, jsonb_build_array(
    jsonb_build_object('ordem',0,'chave','Banco C - capital de giro - juros do exercício','valor_num','900','unidade','unidade','confianca','0.97')
  ), 'N2');
  perform fn_reconciliar_despfin_dre_vs_divida(v_caso, v_ent, v_per);
  select descricao into v_txt from pendencia
   where caso_id = v_caso and motivo = 'reconciliacao:despfin_dre_vs_divida' and estado <> 'resolvida';
  perform pg_temp.teste_assert_0188(
    v_txt like 'MOTIVO: linha não localizada%'
      and v_txt like '%A DRE traz "RESULTADO FINANCEIRO LÍQUIDO" no lugar%',
    'a pendência da checagem despfin diz o motivo E o que a DRE traz no lugar', left(v_txt, 400));

  -- O NEGATIVO: sem a alternativa, o texto é o de sempre, BYTE A BYTE (o da
  -- 0119/0157 — literal abaixo).
  v_caso_neg := (fn_upsert_caso('0188: resultado antes do financeiro'))::uuid;
  v_r := fn_registrar_documento(v_caso_neg, 'ANTES LTDA.', 'anual', '2025', 'DRE', 0.95,
    'nome_arquivo', 'supabase_storage', '0188/dre-antes.pdf', 'DRE ANTES.pdf', true, 'HASH-0188-7', 'ok');
  perform fn_registrar_campos_extraidos((v_r->>'documento_versao_id')::uuid, jsonb_build_array(
    jsonb_build_object('ordem',0,'chave','RECEITA OPERACIONAL BRUTA','valor_num','10000','periodo_coluna','2025','unidade','unidade','confianca','0.97'),
    jsonb_build_object('ordem',1,'chave','RESULTADO ANTES DO RESULTADO FINANCEIRO','valor_num','2000','periodo_coluna','2025','unidade','unidade','confianca','0.97')
  ), 'N2');
  select descricao into v_txt from pendencia
   where caso_id = v_caso_neg and tipo = 'linha_exigida_ausente' and estado = 'aberta'
     and motivo like 'completude:linha_exigida:DRE:despesa\_financeira%';
  perform pg_temp.teste_assert_0188(
    v_txt = 'Nos documentos de DRE da entidade "ANTES LTDA.", a linha exigida "Despesa Financeira" '
            'não foi localizada na versão vigente. Sem ela, PARA ESTA ENTIDADE: '
            'reconciliacao:despfin_dre_vs_divida (0015/0023). Conferir se o documento dela traz a '
            'linha com outro rótulo (e corrigir na revisão) ou reenviar o arquivo completo.',
    'NEGATIVO: "RESULTADO ANTES DO RESULTADO FINANCEIRO" não é alternativa, e o texto é o de antes',
    coalesce(v_txt, '(sem pendência)'));
end $$;

-- =============================================================================
do $$
declare
  v_n int;
begin
  select case when is_called then last_value else 0 end into v_n from pg_temp._falhas_0188;
  if v_n > 0 then
    raise exception 'FALHOU: % assert(s) da 0188 reprovaram — ver as linhas FALHOU acima', v_n;
  end if;
  raise notice 'TODOS OS TESTES DA 0188 (motivo específico, alternativa, juros bancários) PASSARAM';
end $$;

rollback;
