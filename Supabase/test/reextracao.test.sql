-- Testes da idempotência por hash de fn_registrar_documento (Supabase/migrations/0026).
-- Rodar via Supabase/test/run.sh (que aplica as migrations antes).
--
-- A propriedade que estes testes travam: **reenviar/reextrair o MESMO arquivo não
-- suja o caso** — nem documento duplicado, nem item de checklist a mais, nem
-- cartão repetido na fila. E o inverso, igualmente importante: arquivo DIFERENTE
-- (ou sem hash) continua sendo documento novo, porque fundir dois documentos
-- distintos é o erro mais caro que esta função pode cometer.

\set ON_ERROR_STOP on

create or replace function teste_assert_rx(p_ok boolean, p_nome text, p_detalhe text default null)
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
  v_r1 jsonb; v_r2 jsonb; v_r3 jsonb; v_r4 jsonb;
  v_n int;
  v_txt text;
begin
  raise notice '--- 1. o MESMO arquivo (mesmo hash) é VERSÃO NOVA, não documento novo ---';
  v_caso := (fn_upsert_caso('Caso reextração'))::uuid;

  v_r1 := fn_registrar_documento(
    v_caso, 'Alfa Ltda.', 'anual', '2025', 'BALANCO', 0.95, 'nome_arquivo',
    'supabase_storage', 'bucket/bp.pdf', 'BP Alfa 2025.pdf', true, 'HASH-A', 'ok');
  v_r2 := fn_registrar_documento(
    v_caso, 'Alfa Ltda.', 'anual', '2025', 'BALANCO', 0.95, 'nome_arquivo',
    'supabase_storage', 'bucket/bp.pdf', 'BP Alfa 2025.pdf', true, 'HASH-A', 'ok');

  perform teste_assert_rx(
    (v_r1->>'documento_id') = (v_r2->>'documento_id'),
    'mesmo hash => MESMO documento',
    format('1=%s 2=%s', v_r1->>'documento_id', v_r2->>'documento_id'));
  perform teste_assert_rx(
    (v_r1->>'documento_versao_id') <> (v_r2->>'documento_versao_id'),
    'mesmo hash => versão NOVA (a extração anterior não é sobrescrita)');
  perform teste_assert_rx((v_r1->>'n_versao') = '1' and (v_r2->>'n_versao') = '2',
    'n_versao incrementa', format('1=%s 2=%s', v_r1->>'n_versao', v_r2->>'n_versao'));
  perform teste_assert_rx((v_r2->>'reaproveitou_documento')::boolean,
    'o retorno DIZ que reaproveitou (é o que o workflow pode usar para decidir)');

  select count(*) into v_n from documento where caso_id = v_caso;
  perform teste_assert_rx(v_n = 1, 'um arquivo = um documento no caso', format('documentos=%s', v_n));

  raise notice '--- 2. reextração não infla checklist nem fila de revisão ---';
  select count(*) into v_n from checklist_item_status
    where caso_id = v_caso and documento_id = (v_r1->>'documento_id')::uuid;
  perform teste_assert_rx(v_n = 1, 'um item de checklist, não dois', format('itens=%s', v_n));

  -- Classificação incerta duas vezes: um cartão só na fila.
  v_r3 := fn_registrar_documento(
    v_caso, 'Beta Ltda.', 'anual', '2025', null, 0.2, 'nome_arquivo',
    'supabase_storage', 'bucket/x.pdf', 'arquivo estranho.pdf', null, 'HASH-B', 'ok');
  v_r4 := fn_registrar_documento(
    v_caso, 'Beta Ltda.', 'anual', '2025', null, 0.2, 'nome_arquivo',
    'supabase_storage', 'bucket/x.pdf', 'arquivo estranho.pdf', null, 'HASH-B', 'ok');
  select count(*) into v_n from pendencia
    where documento_id = (v_r3->>'documento_id')::uuid
      and tipo = 'classificacao_pendente' and estado <> 'resolvida';
  perform teste_assert_rx(v_n = 1, 'uma pendência de classificação, não uma por reenvio',
    format('pendências=%s', v_n));

  raise notice '--- 3. a máquina NÃO desfaz a revisão do humano (anti-ancoragem) ---';
  -- O humano corrige o tipo na fila; o dono então reextrai o arquivo. Se a
  -- reextração sobrepusesse o tipo, a correção humana seria perdida em silêncio.
  perform fn_revisar_documento((v_r3->>'documento_id')::uuid, 'humano:rodrigo', 'DMPL',
                               null, null, null, 'é a DMPL, não mútuos');
  perform fn_registrar_documento(
    v_caso, 'Beta Ltda.', 'anual', '2025', 'MUTUOS', 0.9, 'openai_conteudo',
    'supabase_storage', 'bucket/x.pdf', 'arquivo estranho.pdf', null, 'HASH-B', 'ok');
  select tipo_taxonomia into v_txt from documento where id = (v_r3->>'documento_id')::uuid;
  perform teste_assert_rx(v_txt = 'DMPL',
    'tipo revisado por humano sobrevive à reextração', format('tipo=%s', v_txt));

  raise notice '--- 4. NEGATIVO: arquivo diferente continua sendo documento novo ---';
  perform fn_registrar_documento(
    v_caso, 'Alfa Ltda.', 'anual', '2024', 'BALANCO', 0.95, 'nome_arquivo',
    'supabase_storage', 'bucket/bp24.pdf', 'BP Alfa 2024.pdf', true, 'HASH-C', 'ok');
  select count(*) into v_n from documento where caso_id = v_caso;
  perform teste_assert_rx(v_n = 3, 'hash diferente => documento próprio (nada é fundido)',
    format('documentos=%s (esperado 3)', v_n));

  raise notice '--- 5. NEGATIVO: sem hash não há como afirmar que é o mesmo arquivo ---';
  -- Dois desconhecidos não são "o mesmo desconhecido": tratá-los como o mesmo
  -- documento fundiria arquivos distintos, que é o erro mais caro aqui.
  perform fn_registrar_documento(
    v_caso, 'Gama Ltda.', 'anual', '2025', 'DRE', 0.95, 'nome_arquivo',
    'supabase_storage', 'bucket/s1.pdf', 'sem hash 1.pdf', null, null, 'ok');
  perform fn_registrar_documento(
    v_caso, 'Gama Ltda.', 'anual', '2025', 'DRE', 0.95, 'nome_arquivo',
    'supabase_storage', 'bucket/s2.pdf', 'sem hash 2.pdf', null, null, 'ok');
  select count(*) into v_n from documento where caso_id = v_caso;
  perform teste_assert_rx(v_n = 5, 'hash nulo não casa (comportamento de antes)',
    format('documentos=%s (esperado 5)', v_n));

  raise notice '--- 6. UMA assinatura só (o overload morto não voltou) ---';
  -- A 0026 matou o de 14 args; a 0118 acrescentou o 16º (o fingerprint) e teve
  -- de MATAR o de 15 pelo mesmo motivo: com dois vivos, a chamada do n8n (13
  -- posicionais + o resto por nome) casa com AMBOS e o Postgres recusa com
  -- "function is not unique" — no meio de um lote real, não em teste.
  select count(*) into v_n from pg_proc where proname = 'fn_registrar_documento';
  perform teste_assert_rx(v_n = 1, 'existe exatamente UMA fn_registrar_documento',
    format('assinaturas vivas=%s', v_n));
  -- 0170: passou a 17 com o `p_cnpj`. O número muda quando a assinatura muda —
  -- é esse o trabalho deste assert. O que ele protege é a UNICIDADE acima: foi
  -- um overload vivo que derrubou um lote real com "function is not unique".
  select count(*) into v_n from pg_proc
    where proname = 'fn_registrar_documento' and pronargs = 17;
  perform teste_assert_rx(v_n = 1, 'e ela é a de 17 args (o fingerprint da 0118 + o CNPJ da 0170)',
    format('assinaturas de 17 args=%s', v_n));

  raise notice '--- 7. a reextração fica no rastro de auditoria ---';
  select count(*) into v_n from evento_auditoria
    where acao = 'documento_reextraido' and entidade_ref = 'documento:'||(v_r1->>'documento_id');
  perform teste_assert_rx(v_n = 1, 'evento próprio (documento_reextraido), não silêncio',
    format('eventos=%s', v_n));

  raise notice '--- 8. FINGERPRINT (0118): mesmo arquivo + mesmo prompt não paga de novo ---';
  -- O par (hash, fingerprint) só autoriza reaproveitar quando a versão antiga TEM
  -- linha extraída. Aqui a primeira versão recebe uma linha, e é isso que faz o
  -- segundo registro devolver a MESMA versão em vez de abrir outra.
  v_caso := (fn_upsert_caso('Caso fingerprint'))::uuid;
  v_r1 := fn_registrar_documento(
    v_caso, 'Delta Ltda.', 'anual', '2025', 'BALANCO', 0.95, 'nome_arquivo',
    'supabase_storage', 'bucket/d.pdf', 'BP Delta.pdf', true, 'HASH-D', 'ok',
    p_fingerprint_extracao => 'FP-1');
  insert into campo_extraido (documento_versao_id, chave, valor_num, unidade, confianca)
    values ((v_r1->>'documento_versao_id')::uuid, 'Caixa', 100, 'unidade', 0.99);

  v_r2 := fn_registrar_documento(
    v_caso, 'Delta Ltda.', 'anual', '2025', 'BALANCO', 0.95, 'nome_arquivo',
    'supabase_storage', 'bucket/d.pdf', 'BP Delta.pdf', true, 'HASH-D', 'ok',
    p_fingerprint_extracao => 'FP-1');
  perform teste_assert_rx((v_r2->>'reaproveitou_extracao')::boolean,
    'mesmo hash + mesmo fingerprint + já tem linha => reaproveita a extração');
  perform teste_assert_rx(
    (v_r1->>'documento_versao_id') = (v_r2->>'documento_versao_id'),
    'e NÃO cria versão nova — é a mesma versão que volta',
    format('%s vs %s', v_r1->>'documento_versao_id', v_r2->>'documento_versao_id'));
  select count(*) into v_n from documento_versao
    where documento_id = (v_r1->>'documento_id')::uuid;
  perform teste_assert_rx(v_n = 1, 'uma versão só, depois de dois registros',
    format('versões=%s', v_n));
  select count(*) into v_n from evento_auditoria
    where acao = 'documento_extracao_reaproveitada';
  perform teste_assert_rx(v_n = 1, 'o reaproveitamento fica no rastro de auditoria',
    format('eventos=%s', v_n));

  raise notice '--- 9. fingerprint DIFERENTE volta a pagar (é a reextração deliberada) ---';
  -- É o caso de o prompt ter mudado — a 0116 mexeu nele, e uma extração feita com
  -- o prompt de ontem não vale como a de hoje. Aqui tem de nascer versão nova.
  v_r3 := fn_registrar_documento(
    v_caso, 'Delta Ltda.', 'anual', '2025', 'BALANCO', 0.95, 'nome_arquivo',
    'supabase_storage', 'bucket/d.pdf', 'BP Delta.pdf', true, 'HASH-D', 'ok',
    p_fingerprint_extracao => 'FP-2');
  perform teste_assert_rx(not (v_r3->>'reaproveitou_extracao')::boolean,
    'fingerprint diferente NÃO reaproveita');
  perform teste_assert_rx((v_r3->>'reaproveitou_documento')::boolean,
    'mas continua sendo o MESMO documento (a idempotência da 0026 segue valendo)');
  perform teste_assert_rx((v_r3->>'n_versao')::int = 2, 'e a versão é a 2',
    format('n_versao=%s', v_r3->>'n_versao'));

  raise notice '--- 10. EXTRAÇÃO QUE FALHOU não vale como extração feita ---';
  -- A propriedade que impede o pior erro desta migration. A versão 3 nasce com o
  -- fingerprint FP-3 e NENHUMA linha (extração truncada/recusada). Reenviar o
  -- arquivo — que é o conserto — tem de chamar a IA de novo.
  v_r4 := fn_registrar_documento(
    v_caso, 'Delta Ltda.', 'anual', '2025', 'BALANCO', 0.95, 'nome_arquivo',
    'supabase_storage', 'bucket/d.pdf', 'BP Delta.pdf', true, 'HASH-D', 'ok',
    p_fingerprint_extracao => 'FP-3');
  perform teste_assert_rx(not (v_r4->>'reaproveitou_extracao')::boolean,
    'a versão com FP-3 nasceu sem linha nenhuma');
  v_r4 := fn_registrar_documento(
    v_caso, 'Delta Ltda.', 'anual', '2025', 'BALANCO', 0.95, 'nome_arquivo',
    'supabase_storage', 'bucket/d.pdf', 'BP Delta.pdf', true, 'HASH-D', 'ok',
    p_fingerprint_extracao => 'FP-3');
  perform teste_assert_rx(not (v_r4->>'reaproveitou_extracao')::boolean,
    'e o reenvio com o MESMO fingerprint volta a pagar a extração — sem linha, não há o que reaproveitar');

  raise notice '--- 11. sem fingerprint, o comportamento é o da 0026 ---';
  -- Workflow antigo (que não manda o campo) não pode virar reaproveitamento
  -- silencioso: fingerprint nulo nunca casa, igual a hash nulo.
  v_r4 := fn_registrar_documento(
    v_caso, 'Delta Ltda.', 'anual', '2025', 'BALANCO', 0.95, 'nome_arquivo',
    'supabase_storage', 'bucket/d.pdf', 'BP Delta.pdf', true, 'HASH-D', 'ok');
  perform teste_assert_rx(not (v_r4->>'reaproveitou_extracao')::boolean,
    'fingerprint nulo não casa');

  raise notice 'TODOS OS TESTES DE REEXTRAÇÃO PASSARAM';
end $$;
