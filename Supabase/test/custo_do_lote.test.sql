-- Testes do custo que passa a durar (Supabase/migrations/0115).
-- Rodar via Supabase/test/run.sh (que aplica as migrations antes).
--
-- O QUE ESTE ARQUIVO PROVA, e o primeiro item é a razão de a tabela existir com
-- chave composta em vez de um `insert` simples:
--
--   1. GRAVAR DUAS VEZES A MESMA EXECUÇÃO NÃO DOBRA O CUSTO. O `Resumo de Custo`
--      roda uma vez por ramo do lote e as duas passadas trazem o total inteiro;
--      sem a chave `(caso_id, execucao_ref)` todo gasto sairia 2×. É um erro
--      para CIMA, que passa por prudência e por isso ninguém questiona;
--   2. duas execuções do MESMO mandato somam (a tela "adicionar" dispara outro
--      lote, e ele custa de novo);
--   3. a cobertura é recalculada no banco, e é NULA quando não houve medição —
--      zero diria "não extraiu nada", que é uma frase diferente;
--   4. sem `execucao_ref` a função RECUSA em vez de gravar sem chave;
--   5. excluir o mandato leva o custo junto (a FK é `on delete cascade`), senão
--      o total do painel contaria mandato que não existe mais.

\set ON_ERROR_STOP on

create or replace function teste_assert_custo(p_ok boolean, p_nome text, p_detalhe text default null)
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
  v_caso  uuid;
  v_r     jsonb;
  v_total numeric;
  v_n     int;
  v_resumo jsonb := jsonb_build_object(
    'documentos', 9,
    'documentos_com_classificacao', 4,
    'documentos_fatiados', 1,
    'documentos_com_falha', 0,
    'documentos_sem_medicao', 0,
    'custo_total_usd', 0.4612,
    'custo_extracao_usd', 0.4512,
    'custo_classificacao_usd', 0.0100,
    'custo_estimado_usd', 1.88,
    'tokens', jsonb_build_object('entrada', 120000, 'saida', 45000, 'cache', 30000),
    'linhas_extraidas', 714,
    'contas_nos_documentos', 800,
    'contas_extraidas', 600,
    'orcamento_versao', 'v3 (2026-08-13)'
  );
begin
  insert into caso (nome) values ('teste custo do lote') returning id into v_caso;

  raise notice '--- 1. a mesma execução gravada duas vezes NÃO dobra o custo ---';
  v_r := fn_registrar_uso_lote(v_caso, '6164', v_resumo);
  perform teste_assert_custo((v_r->>'gravado')::boolean, 'a primeira gravação passa');

  -- A SEGUNDA PASSADA É O CASO REAL, não hipótese: o nó roda uma vez por ramo.
  v_r := fn_registrar_uso_lote(v_caso, '6164', v_resumo);
  perform teste_assert_custo((v_r->>'gravado')::boolean, 'a segunda gravação também responde gravado');

  select count(*), sum(custo_total_usd) into v_n, v_total
    from lote_execucao where caso_id = v_caso;
  perform teste_assert_custo(v_n = 1, 'UMA linha por execução, não duas', 'linhas: ' || v_n);
  perform teste_assert_custo(v_total = 0.4612,
    'o custo do mandato NÃO dobrou', 'total: ' || v_total);

  perform teste_assert_custo(
    (select tokens_saida = 45000 and tokens_entrada = 120000 and tokens_cache = 30000
       from lote_execucao where caso_id = v_caso),
    'os tokens aninhados foram lidos pelo caminho certo');
  perform teste_assert_custo(
    (select orcamento_versao = 'v3 (2026-08-13)' and custo_estimado_usd = 1.88
       from lote_execucao where caso_id = v_caso),
    'o estimado fica ao lado do real, que é o que recalibra o estimador');

  raise notice '--- 2. duas execuções do mesmo mandato somam ---';
  perform fn_registrar_uso_lote(v_caso, '6199',
    jsonb_set(v_resumo, '{custo_total_usd}', '0.1000'::jsonb));
  select count(*), sum(custo_total_usd) into v_n, v_total
    from lote_execucao where caso_id = v_caso;
  perform teste_assert_custo(v_n = 2, 'duas execuções, duas linhas');
  perform teste_assert_custo(v_total = 0.5612,
    'o gasto do mandato é a SOMA das execuções', 'total: ' || v_total);

  raise notice '--- 3. cobertura recalculada no banco, e nula quando não houve medição ---';
  perform teste_assert_custo(
    (select cobertura = 0.7500 from lote_execucao where caso_id = v_caso and execucao_ref = '6164'),
    '600 de 800 = 0,75');
  perform fn_registrar_uso_lote(v_caso, '6200',
    jsonb_set(jsonb_set(v_resumo, '{contas_nos_documentos}', '0'::jsonb),
              '{contas_extraidas}', '0'::jsonb));
  perform teste_assert_custo(
    (select cobertura is null from lote_execucao where caso_id = v_caso and execucao_ref = '6200'),
    'SEM MEDIÇÃO A COBERTURA É NULA — zero diria "não extraiu nada", que é outra frase');

  raise notice '--- 4. sem referência de execução, recusa ---';
  v_r := fn_registrar_uso_lote(v_caso, null, v_resumo);
  perform teste_assert_custo(not (v_r->>'gravado')::boolean,
    'sem execucao_ref a função RECUSA em vez de gravar sem chave de idempotência');
  v_r := fn_registrar_uso_lote(v_caso, '   ', v_resumo);
  perform teste_assert_custo(not (v_r->>'gravado')::boolean, 'espaço em branco não vale como chave');
  v_r := fn_registrar_uso_lote(null, '6164', v_resumo);
  perform teste_assert_custo(not (v_r->>'gravado')::boolean, 'sem caso, não grava');

  raise notice '--- 5. excluir o mandato leva o custo junto ---';
  perform fn_excluir_caso(v_caso, 'analista@oria');
  select count(*) into v_n from lote_execucao where caso_id = v_caso;
  perform teste_assert_custo(v_n = 0,
    'o custo some com o mandato — senão o total do painel contaria caso inexistente');

  raise notice 'TODOS OS TESTES DE CUSTO DO LOTE PASSARAM';
end $$;

drop function teste_assert_custo(boolean, text, text);
