-- =============================================================================
-- O PAINEL DE OPERAÇÃO (0135)
--
-- O que se testa aqui não é "a consulta roda": é se cada um dos QUATRO alertas
-- dispara no caso que ele existe para pegar, e — mais importante — se ele NÃO
-- dispara no lote saudável. Um painel que acende para tudo é um painel que
-- ninguém olha em duas semanas.
-- =============================================================================

create or replace function teste_assert(p_cond boolean, p_nome text, p_detalhe text default null)
returns void language plpgsql as $$
begin
  if p_cond then raise notice 'ok    %', p_nome;
  else raise exception 'FALHOU: % %', p_nome, coalesce(' — ' || p_detalhe, '');
  end if;
end $$;

do $$
declare
  v_caso uuid;
  v_al   text[];
  v_r    jsonb;
  v_n    int;
begin
  select id into v_caso from caso limit 1;
  perform teste_assert(v_caso is not null, 'há um caso no banco de teste');
  if v_caso is null then return; end if;

  delete from lote_execucao where execucao_ref like 'teste-op-%';

  raise notice '--- 1. o lote SAUDÁVEL não acende nada ---';
  insert into lote_execucao (caso_id, execucao_ref, documentos, documentos_com_falha,
      documentos_sem_medicao, custo_total_usd, custo_estimado_usd, cobertura, linhas_extraidas)
    values (v_caso, 'teste-op-ok', 10, 0, 0, 1.00, 1.20, 0.93, 500);
  select alertas into v_al from fn_operacao_lotes(30, 100) where execucao_ref = 'teste-op-ok';
  perform teste_assert(coalesce(cardinality(v_al), 0) = 0,
    'lote com cobertura medida, sem falha e dentro do custo NÃO gera alerta',
    coalesce(array_to_string(v_al, ', '), '(vazio)'));

  raise notice '--- 2. os quatro alertas, um a um ---';

  -- (a) O MAIS IMPORTANTE e o menos óbvio: cobertura NULA. Não é cobertura
  -- baixa (isso a guarda pega) — é a guarda não ter opinado sobre o lote.
  insert into lote_execucao (caso_id, execucao_ref, documentos, documentos_com_falha,
      documentos_sem_medicao, custo_total_usd, custo_estimado_usd, cobertura)
    values (v_caso, 'teste-op-sem-cobertura', 10, 0, 0, 1.00, 1.20, null);
  select alertas into v_al from fn_operacao_lotes(30, 100) where execucao_ref = 'teste-op-sem-cobertura';
  perform teste_assert('cobertura_nao_medida' = any(v_al),
    'cobertura NULA acende — a camada 1 não mediu e as outras duas estão mudas',
    coalesce(array_to_string(v_al, ', '), '(vazio)'));

  -- (b) documento com falha
  insert into lote_execucao (caso_id, execucao_ref, documentos, documentos_com_falha,
      documentos_sem_medicao, custo_total_usd, custo_estimado_usd, cobertura)
    values (v_caso, 'teste-op-falha', 10, 2, 0, 1.00, 1.20, 0.90);
  select alertas into v_al from fn_operacao_lotes(30, 100) where execucao_ref = 'teste-op-falha';
  perform teste_assert('documento_com_falha' = any(v_al),
    'documento com falha acende', coalesce(array_to_string(v_al, ', '), '(vazio)'));

  -- (c) documento sem medição — nem falha, nem sucesso
  insert into lote_execucao (caso_id, execucao_ref, documentos, documentos_com_falha,
      documentos_sem_medicao, custo_total_usd, custo_estimado_usd, cobertura)
    values (v_caso, 'teste-op-sem-medicao', 10, 0, 3, 1.00, 1.20, 0.90);
  select alertas into v_al from fn_operacao_lotes(30, 100) where execucao_ref = 'teste-op-sem-medicao';
  perform teste_assert('documento_sem_medicao' = any(v_al),
    'documento sem medição acende', coalesce(array_to_string(v_al, ', '), '(vazio)'));

  -- (d) custo acima do previsto. A régua é a razão contra a estimativa DAQUELE
  -- lote, não um teto em dólar: teto absoluto depende do tamanho do lote e
  -- envelhece na primeira mudança de preço.
  insert into lote_execucao (caso_id, execucao_ref, documentos, documentos_com_falha,
      documentos_sem_medicao, custo_total_usd, custo_estimado_usd, cobertura)
    values (v_caso, 'teste-op-caro', 10, 0, 0, 3.00, 1.00, 0.90);
  select alertas into v_al from fn_operacao_lotes(30, 100) where execucao_ref = 'teste-op-caro';
  perform teste_assert('custo_acima_do_previsto' = any(v_al),
    'custo 3x a estimativa do próprio lote acende (limiar 1,5x)',
    coalesce(array_to_string(v_al, ', '), '(vazio)'));

  -- A CONTRAPROVA DO LIMIAR. 1,4x não acende: sem isto, um alerta que dispara
  -- para qualquer variação de token viraria ruído e ninguém olharia a tela.
  insert into lote_execucao (caso_id, execucao_ref, documentos, documentos_com_falha,
      documentos_sem_medicao, custo_total_usd, custo_estimado_usd, cobertura)
    values (v_caso, 'teste-op-quase', 10, 0, 0, 1.40, 1.00, 0.90);
  select alertas into v_al from fn_operacao_lotes(30, 100) where execucao_ref = 'teste-op-quase';
  perform teste_assert(not ('custo_acima_do_previsto' = any(coalesce(v_al, '{}'))),
    '…e 1,4x NÃO acende: variação de token não é estouro de orçamento',
    coalesce(array_to_string(v_al, ', '), '(vazio)'));

  raise notice '--- 3. o resumo conta o mesmo que a listagem ---';
  v_r := fn_operacao_resumo(30);
  select count(*) into v_n from fn_operacao_lotes(30, 100000) where cardinality(alertas) > 0;
  perform teste_assert((v_r->>'lotes_com_alerta')::int = v_n,
    'o resumo e a listagem contam os mesmos lotes com alerta',
    format('resumo=%s listagem=%s', v_r->>'lotes_com_alerta', v_n));

  perform teste_assert((v_r->'por_alerta'->>'cobertura_nao_medida')::int >= 1,
    'o resumo quebra por TIPO de alerta — "3 com alerta" não diz o que fazer',
    v_r->>'por_alerta');

  raise notice '--- 4. a cobertura é MEDIANA, não média ---';
  -- Média de 0,93 / 0,90 / 0,90 / 0,90 / 0,90 seria 0,906; a mediana é 0,90.
  -- O teste fixa a mediana porque é ela que descreve o lote TÍPICO — média
  -- mistura lote de 40 documentos com lote de 1 e não descreve nenhum dos dois.
  perform teste_assert((v_r->>'cobertura_mediana')::numeric = 0.900,
    'a cobertura publicada é a mediana dos lotes que TÊM medição',
    v_r->>'cobertura_mediana');

  raise notice '--- 5. o SILÊNCIO é estado: dias desde o último lote ---';
  perform teste_assert((v_r->>'dias_desde_o_ultimo') is not null,
    'o resumo publica há quantos dias não roda nada — "0 alertas" sem execução '
    || 'nenhuma afirmaria saúde que ninguém mediu',
    v_r->>'dias_desde_o_ultimo');

  delete from lote_execucao where execucao_ref like 'teste-op-%';
  v_r := fn_operacao_resumo(30);
  perform teste_assert((v_r->>'lotes')::int = 0 and (v_r->>'ultimo_lote') is null,
    'sem execução na janela, o resumo diz ZERO e não inventa saúde',
    v_r->>'lotes');
end $$;

do $$ begin raise notice 'TODOS OS TESTES DO PAINEL DE OPERAÇÃO (0135) PASSARAM'; end $$;

drop function teste_assert(boolean, text, text);
