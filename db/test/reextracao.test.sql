-- Testes da idempotência por hash de fn_registrar_documento (db/migrations/0026).
-- Rodar via db/test/run.sh (que aplica as migrations antes).
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

  raise notice '--- 6. o overload morto de 14 argumentos não existe mais ---';
  select count(*) into v_n from pg_proc
    where proname = 'fn_registrar_documento' and pronargs = 14;
  perform teste_assert_rx(v_n = 0, 'só a assinatura de 15 args sobrevive',
    format('assinaturas de 14 args=%s', v_n));

  raise notice '--- 7. a reextração fica no rastro de auditoria ---';
  select count(*) into v_n from evento_auditoria
    where acao = 'documento_reextraido' and entidade_ref = 'documento:'||(v_r1->>'documento_id');
  perform teste_assert_rx(v_n = 1, 'evento próprio (documento_reextraido), não silêncio',
    format('eventos=%s', v_n));

  raise notice 'TODOS OS TESTES DE REEXTRAÇÃO PASSARAM';
end $$;
