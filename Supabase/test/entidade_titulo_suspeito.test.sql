-- =============================================================================
-- 0178 — a guarda de `fn_upsert_entidade` contra título/coluna/aba/arquivo
--        virando pessoa jurídica, medida com os NOMES REAIS do mandato AMO
--        teste 00 (regra 4 do CLAUDE.md — fixture real, não inventada)
--
-- MEDIÇÃO NÃO-VAZIA (regra 2): com a chamada a
-- `fn_entidade_nome_parece_titulo_ou_arquivo` comentada dentro de
-- `fn_upsert_entidade` (ou a própria função reescrita para sempre devolver
-- `false`), os blocos 1 e 4 abaixo reprovam — 5 asserts no total (4 do bloco
-- 1, contando "a entidade ainda existe" + "o documento continua ligado a ela"
-- + "abriu pendência" + "a pendência tem o tipo certo" para os quatro nomes
-- juntos numa contagem, e 1 do bloco 4, o idempotente). Rodado medido contra
-- o estado da 0177 (função sem a guarda): FALHOU nos dois blocos, exatamente
-- como esperado — os 4 nomes viravam entidade comum, zero pendência aberta.
-- Religada a guarda (0178), os 12 asserts deste arquivo passam.
--
-- O QUE ESTE ARQUIVO MEDE:
--   1. os 4 nomes REAIS do AMO teste 00 (Empresas, Vencidos, Status Extratos,
--      Controle Extratos Ofx — seção 12.1 do roadmap) abrem pendência
--      entidade_incorreta/entidade_nome_suspeito, SEM perder o documento
--      (a entidade continua existindo, o documento continua ligado a ela —
--      apagar perderia proveniência, e não é isso que a 0178 faz);
--   2. um nome REAL de empresa do MESMO mandato, com CNPJ, passa livre —
--      contrapositivo do "sem CNPJ" sozinho não bastar como critério;
--   3. a ARMADILHA: o balcão ambíguo (cenário já coberto por
--      `Supabase/test/alias_truncado.test.sql` bloco 3 — nome que casa com
--      DUAS empresas, "Araucaria SPE") continua nascendo e registrando
--      ambiguidade NORMALMENTE, sem a guarda nova abrir uma segunda
--      pendência — o nome dele vem do CONTEÚDO do documento, não bate o
--      léxico de título/arquivo;
--   4. idempotência: o MESMO nome suspeito, chegando de novo no mesmo caso
--      (dois documentos "Vencidos" diferentes), não abre uma segunda
--      pendência — mesmo desenho de fn_pendencia_cnpj_colide_balcao (0177) e
--      fn_pendencia_entidade_ambigua (0153).
-- =============================================================================

create or replace function teste_assert_0178(p_cond boolean, p_nome text, p_detalhe text default null)
returns void language plpgsql as $$
begin
  if p_cond then
    raise notice 'ok    %', p_nome;
  else
    raise exception 'FALHOU: % %', p_nome, coalesce(' — ' || p_detalhe, '');
  end if;
end $$;

do $$
declare
  v_caso        uuid;
  v_r           jsonb;
  v_doc_id      uuid;
  v_ent_id      uuid;
  v_pend_n      int;
  v_pend_tipo   text;
  v_pend_motivo text;
  v_ent_ok_id   uuid;
  v_pend_ok_n   int;
  v_araucaria_1 uuid; v_araucaria_2 uuid; v_balcao uuid;
  v_pend_ambigua_n  int;
  v_pend_suspeito_n int;
  v_ent_vencidos_2  uuid;
  v_pend_vencidos_n int;
  c_nomes_reais constant text[] := array[
    'Empresas', 'Vencidos', 'Status Extratos', 'Controle Extratos Ofx'];
  v_nome text;
  i int;
begin
  v_caso := (fn_upsert_caso('0178 — titulo de planilha nao e pessoa juridica'))::uuid;

  raise notice '--- 1. os 4 nomes REAIS do AMO teste 00, sem CNPJ, 1 documento cada ---';
  i := 0;
  foreach v_nome in array c_nomes_reais loop
    i := i + 1;
    v_r := fn_registrar_documento(v_caso, v_nome, 'ano', '2025', 'BALANCO', 0.9,
      'nome_arquivo', 'supabase_storage', format('s/0178-%s.pdf', i), format('%s.pdf', v_nome),
      true, format('HASH-0178-%s', i), 'ok');
    v_doc_id := (v_r->>'documento_id')::uuid;
    v_ent_id := (select entidade_id from documento where id = v_doc_id);

    perform teste_assert_0178(v_ent_id is not null,
      format('"%s": o documento continua com entidade própria (não perde proveniência)', v_nome));

    perform teste_assert_0178(
      (select razao_social from entidade where id = v_ent_id) = v_nome,
      format('"%s": a entidade nasceu com o nome tal como chegou — a guarda MARCA, não renomeia', v_nome));

    select tipo::text, motivo into v_pend_tipo, v_pend_motivo
    from pendencia where entidade_id = v_ent_id and motivo = 'entidade_nome_suspeito:' || v_ent_id
    order by criada_em desc limit 1;

    perform teste_assert_0178(v_pend_tipo = 'entidade_incorreta',
      format('"%s": abriu pendência entidade_incorreta (a mesma família da fatia 1.1)', v_nome),
      coalesce(v_pend_tipo, '(nenhuma pendência)'));

    perform teste_assert_0178(v_pend_motivo = 'entidade_nome_suspeito:' || v_ent_id,
      format('"%s": o motivo identifica a entidade, para dedupe', v_nome));
  end loop;

  raise notice '--- 2. contrapositivo: nome REAL de empresa do MESMO mandato, COM CNPJ, passa livre ---';
  v_r := fn_registrar_documento(v_caso, 'AMOBELEZA COMERCIO DIGITAL E OFFLINE LTDA', 'ano', '2025',
    'BALANCO', 0.95, 'nome_arquivo', 'supabase_storage', 's/0178-amobeleza.pdf', 'BAL.pdf',
    true, 'HASH-0178-AMO', 'ok', 0.7, null, null, '11.222.333/0001-44');
  v_ent_ok_id := (select entidade_id from documento where id = ((v_r->>'documento_id')::uuid));

  perform teste_assert_0178(
    (select razao_social from entidade where id = v_ent_ok_id) = 'AMOBELEZA COMERCIO DIGITAL E OFFLINE LTDA',
    'AMOBELEZA (com CNPJ) vira entidade própria, com o nome real');

  select count(*) into v_pend_ok_n from pendencia
   where entidade_id = v_ent_ok_id and motivo = 'entidade_nome_suspeito:' || v_ent_ok_id;
  perform teste_assert_0178(v_pend_ok_n = 0,
    'e NENHUMA pendência entidade_nome_suspeito — o CNPJ tira a AMOBELEZA da guarda antes de '
    'o léxico ser sequer avaliado');

  raise notice '--- 3. A ARMADILHA: o balcão ambíguo não bate o léxico, e continua funcionando normal ---';
  -- Mesmo cenário de Supabase/test/alias_truncado.test.sql bloco 3: um nome que
  -- casa com DUAS empresas do grupo (Araucária Bioenergia × Araucária
  -- Imobiliária) forma um balcão ambíguo — sem CNPJ, por construção (0153/0162).
  -- Se a 0178 marcasse isto como "nome suspeito", reabriria o defeito que a
  -- 0176/0177 corrigiram (entidade real sem CNPJ tratada como descartável).
  v_araucaria_1 := fn_upsert_entidade(v_caso, 'ARAUCÁRIA BIOENERGIA SPE LTDA.');
  v_araucaria_2 := fn_upsert_entidade(v_caso, 'ARAUCÁRIA IMOBILIÁRIA SPE LTDA.');
  v_balcao := fn_upsert_entidade(v_caso, 'Araucaria SPE');

  perform teste_assert_0178(
    (select razao_social from entidade where id = v_balcao) = 'Araucaria SPE',
    'o balcão nasce normalmente, com o nome que veio do conteúdo (não é título de arquivo)');

  perform teste_assert_0178(exists (
      select 1 from evento_auditoria ev
      where ev.acao = 'entidade_ambigua' and ev.entidade_ref = 'entidade:' || v_balcao),
    'e a ambiguidade dele continua sendo a ÚNICA marca — é entidade_ambigua, não título suspeito');

  select count(*) into v_pend_suspeito_n from pendencia
   where entidade_id = v_balcao and motivo = 'entidade_nome_suspeito:' || v_balcao;
  perform teste_assert_0178(v_pend_suspeito_n = 0,
    'e a guarda da 0178 NÃO abriu pendência nenhuma no balcão — "Araucaria SPE" não bate o léxico',
    format('%s pendência(s)', v_pend_suspeito_n));

  select count(*) into v_pend_ambigua_n from pendencia
   where caso_id = v_caso and tipo::text = 'entidade_incorreta' and motivo = 'entidade_ambigua:' || v_balcao;
  -- Esta pendência só nasce quando alguém chama fn_pendencia_entidade_ambigua
  -- (o diagnóstico, não fn_upsert_entidade) — aqui só confere que o evento
  -- existe (acima) e que a guarda nova não duplicou nada por cima dele.
  perform teste_assert_0178(v_pend_ambigua_n = 0 or v_pend_ambigua_n = 1,
    'nenhuma duplicação de pendência por cima do fluxo normal do balcão');

  raise notice '--- 4. idempotência: o MESMO nome suspeito, duas vezes, é UMA pendência só ---';
  v_r := fn_registrar_documento(v_caso, 'Vencidos', 'ano', '2024', 'BALANCO', 0.9,
    'nome_arquivo', 'supabase_storage', 's/0178-vencidos-2.pdf', 'vencidos2.pdf',
    true, 'HASH-0178-VENC2', 'ok');
  v_ent_vencidos_2 := (select entidade_id from documento where id = ((v_r->>'documento_id')::uuid));

  perform teste_assert_0178(
    v_ent_vencidos_2 = (select id from entidade where caso_id = v_caso and razao_social = 'Vencidos'),
    'o segundo documento "Vencidos" caiu na MESMA entidade (casamento exato canônico) — não criou outra');

  select count(*) into v_pend_vencidos_n from pendencia
   where entidade_id = v_ent_vencidos_2 and motivo = 'entidade_nome_suspeito:' || v_ent_vencidos_2;
  perform teste_assert_0178(v_pend_vencidos_n = 1,
    'e continua sendo UMA pendência só — o segundo documento não abriu outra',
    format('%s pendência(s)', v_pend_vencidos_n));

  raise notice 'TITULO SUSPEITO OK — os 4 nomes reais do AMO abrem pendência sem perder documento, '
    'o CNPJ tira a AMOBELEZA da guarda, o balcão ambíguo real não é tocado, e a marca é idempotente';
end $$;
