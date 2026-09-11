-- Teste de ESCALA da versão vigente na Modelagem (Supabase/migrations/0164).
-- Rodar via Supabase/test/run.sh (que aplica as migrations antes).
--
-- O QUE ESTE ARQUIVO TRAVA, e por que ele existe além de modelagem_escala.test.sql.
--
-- No caso "Teste 00" (190 documentos, 7.151 linhas) `fn_linhas_para_modelagem`
-- e `fn_conferir_modelagem` estouravam os 8s do `statement_timeout` do
-- Supabase — a mesma classe de defeito que `modelagem_escala.test.sql` (0101)
-- já trava, só que a CAUSA aqui é outra e o fixture daquele arquivo (14
-- documentos, ~250 rótulos distintos) NUNCA a expõe: o filtro `dv.id =
-- fn_versao_com_extracao(d.id)` (0102, "só a versão vigente") é uma FUNÇÃO
-- opaca — o planner não sabe estimar a seletividade dela, chuta `rows=1`
-- para a CTE inteira, e escolhe Nested Loop para o join que deveria ser
-- Hash Join. Nested Loop com estimativa de 1×1 é barato; a 7.220 ocorrências
-- × ~2.000+ combinações de (chave, tipo_taxonomia, unidade) é o Nested Loop
-- que estourava o teto — ver o cabeçalho da migration 0164 para o EXPLAIN
-- ANALYZE medido antes e depois.
--
-- POR QUE ESTE FIXTURE PRECISA DE MAIS DE 250 RÓTULOS DISTINTOS, e o de
-- `modelagem_escala.test.sql` não pega isto: o Nested Loop custa
-- ocorrências × combinações_distintas. Com ~250 rótulos (o teto do fixture
-- antigo) e 770 ocorrências, o produto é ~577 mil comparações — dezenas de
-- ms, invisível dentro de 8s. O caso real, sendo demonstração financeira de
-- verdade, não estanca em 250 rótulos — e é só quando as DUAS pontas
-- crescem (mais documentos E mais rótulos distintos) que o produto passa a
-- estourar o teto. MEDIDO nesta sessão, 190 documentos / 7.220 ocorrências,
-- fresco (sem ANALYZE manual entre a carga do fixture e a chamada — a
-- mesma ordem deste arquivo): a 250 rótulos o Nested Loop nem aparece
-- (estatísticas favorecem por acidente); a 800 já estoura (8,5-15,0s
-- medidos, a depender do estado de cache); a 1.000 estoura com folga
-- reprodutível (10,3-10,8s medidos em duas rodadas independentes) sem
-- aproximar-se do teto SEPARADO e NÃO CORRIGIDO por esta migration (o
-- self-join de sobreposição em `pares`, que cresce com o nº de rótulos e já
-- consome ~7,4s sozinho a 2.000 rótulos — fora do escopo da 0164, que
-- corrige só o filtro de versão vigente). 1.000 rótulos é o ponto medido
-- que reproduz o defeito ORIGINAL com folga (>25% acima do teto) sem entrar
-- na faixa onde o OUTRO gargalo, não tocado por esta migration, também
-- começaria a doer.
--
-- É fixture de ESCALA — mede TEMPO, não prova nada sobre o CONTEÚDO do
-- "Teste 00" real (regra 4 do CLAUDE.md): os rótulos e valores abaixo são
-- sintéticos, só a FORMA (nº de documentos, ocorrências, rótulos distintos)
-- reproduz a escala medida do caso real.
--
-- A MESMA ARMADILHA do statement_timeout dentro de bloco `DO` que
-- `modelagem_escala.test.sql` já documenta: `set local statement_timeout`
-- dentro de um `DO` não vale para o próprio `DO` (o cronômetro já começou
-- quando o bloco foi despachado). O teto fica FORA, no nível do psql, entre
-- os dois blocos.

\set ON_ERROR_STOP on

create or replace function teste_assert_versao_vigente_escala(p_ok boolean, p_nome text, p_detalhe text default null)
returns void language plpgsql as $$
begin
  if p_ok then
    raise notice 'ok    %', p_nome;
  else
    raise exception 'FALHOU: % %', p_nome, coalesce(' — ' || p_detalhe, '');
  end if;
end $$;

do $$
declare
  v_caso uuid;
  v_ver  uuid;
  v_r    jsonb;
  v_lote jsonb;
  v_n    int;
  v_n_docs    constant int := 190;  -- a ordem do caso real "Teste 00"
  v_n_rotulos constant int := 1000; -- >250: ver o cabeçalho para a medição
  v_linhas_por_doc constant int := 38; -- 190 x 38 ≈ 7.220, a ordem de 7.151 do caso real
  v_tipos text[] := array['BALANCO','DRE','FLUXO_CAIXA','BALANCETE','MAPA_DIVIDA',
                          'FATURAMENTO_24M','NOTAS_EXPL','MUTUOS'];
  v_secoes text[] := array['ativo_circulante','ativo_nao_circulante','passivo_circulante',
                           'passivo_nao_circulante','patrimonio_liquido','receita_bruta',
                           'custos','despesas_operacionais','atividades_operacionais',
                           'atividades_investimento','atividades_financiamento','dmpl',
                           'impostos_lucro','resultado_financeiro', null];
  v_i int := 0;
begin
  raise notice '--- 1. um caso do TAMANHO do "Teste 00": % documentos, >250 rótulos distintos ---', v_n_docs;
  -- Nome ÚNICO por execução, pela mesma razão de modelagem_escala.test.sql:
  -- fn_upsert_caso reaproveita o caso pelo nome, e um segundo run.sh no
  -- mesmo banco somaria documentos ao caso anterior.
  v_caso := (fn_upsert_caso('Escala da versão vigente ' || clock_timestamp()::text))::uuid;
  for d in 1..v_n_docs loop
    v_r := fn_registrar_documento(v_caso, 'ESCALA VIGENTE LTDA.', 'anual', '2025',
      v_tipos[1 + (d % array_length(v_tipos, 1))], 0.95,
      'nome_arquivo', 'supabase_storage', 'e/'||d||'.pdf', 'BP '||d||'.pdf', true,
      'HASH-ESCALA-VV-'||d, 'ok');
    v_ver := (v_r->>'documento_versao_id')::uuid;
    v_lote := '[]'::jsonb;
    for i in 1..v_linhas_por_doc loop
      v_i := v_i + 1;
      -- >250 rótulos DISTINTOS (v_n_rotulos): é o que o fixture antigo, com
      -- teto de 250, nunca produzia — ver o cabeçalho.
      v_lote := v_lote || jsonb_build_object(
        'ordem', i,
        'chave', 'Conta detalhada ' || ((v_i % v_n_rotulos) + 1) || ' de natureza operacional',
        'valor_num', (1000 + (v_i * 37) % 120)::text,
        'unidade', 'milhar', 'moeda', 'BRL', 'confianca', '0.97',
        'secao_canonica', v_secoes[1 + (v_i % array_length(v_secoes, 1))]);
    end loop;
    perform fn_registrar_campos_extraidos(v_ver, v_lote, 'N2');
  end loop;

  select count(*) into v_n
  from campo_extraido ce
  join documento_versao dv on dv.id = ce.documento_versao_id
  join documento d on d.id = dv.documento_id
  where d.caso_id = v_caso and ce.valor_num is not null;
  perform teste_assert_versao_vigente_escala(v_n between 7000 and 7300,
    'o caso tem ~7.220 ocorrências extraídas (a ordem das 7.151 do caso real)', v_n::text);

  perform set_config('escala_vv.caso', v_caso::text, false);
  raise notice 'fixture montada — % documentos, % rótulos distintos, caso %', v_n_docs, v_n_rotulos, v_caso;
end $$;

-- O TETO, no nível do psql — o mesmo statement_timeout real do Supabase, não
-- um número de milissegundos comparado com o relógio da máquina de CI (ver
-- o cabeçalho de modelagem_escala.test.sql para o porquê): ou cabe no teto
-- que a produção impõe, ou não cabe.
set statement_timeout = '8s';

do $$
declare
  v_caso uuid := current_setting('escala_vv.caso')::uuid;
  v_r    jsonb;
  v_n    int;
begin
  raise notice '--- 2. fn_linhas_para_modelagem cabe no teto de 8s do Supabase com >250 rótulos ---';

  select count(*) into v_n from fn_linhas_para_modelagem(v_caso);
  perform teste_assert_versao_vigente_escala(v_n > 0,
    'fn_linhas_para_modelagem responde dentro do teto, com linhas lógicas (era >8s cancelada: 0164)',
    v_n::text);

  raise notice '--- 3. fn_conferir_modelagem (embrulha a mesma chamada) também cabe ---';
  v_r := fn_conferir_modelagem(v_caso);
  perform teste_assert_versao_vigente_escala(v_r is not null and (v_r->>'linhas_do_caso')::int > 0,
    'fn_conferir_modelagem responde dentro do teto (herdava o mesmo Nested Loop: 0164)',
    coalesce(v_r::text, '(null)'));

  raise notice 'TODOS OS TESTES DE ESCALA DA VERSÃO VIGENTE PASSARAM';
end $$;

set statement_timeout = 0;
