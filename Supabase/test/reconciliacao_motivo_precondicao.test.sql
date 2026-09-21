-- Testes de `reconciliacao.motivo_precondicao` (Supabase/migrations/0186).
-- Rodar via Supabase/test/run.sh (que aplica as migrations antes).
--
-- O QUE ESTE ARQUIVO TRAVA: quando `fn_registrar_reconciliacao` achata o
-- resultado em `precondicao_nao_satisfeita`, o motivo VERDADEIRO — que hoje
-- se perde — passa a ficar em `motivo_precondicao`. `resultado` continua
-- exatamente o mesmo texto de sempre (quem já lê essa coluna não pode
-- quebrar); é `motivo_precondicao` que passa a distinguir os dois estados com
-- remédio oposto:
--
--   documento_ausente          — a contraparte não foi entregue. NÃO abre
--                                 pendência (é cobrança do checklist do Kit
--                                 Básico, não achado de revisão).
--   precondicao_nao_satisfeita — como MOTIVO, significa "o emissor não
--                                 especificou o motivo" (ver o CONTRATO no
--                                 cabeçalho da 0186) — NÃO prova que o
--                                 documento estava presente. ABRE pendência
--                                 por default (motivo não especificado é
--                                 achado acionável até prova em contrário).
--
-- OS CENÁRIOS 1-3 VÊM PELA COSTURA REAL — fn_upsert_caso,
-- fn_registrar_documento, fn_registrar_campos_extraidos e a própria
-- fn_reconciliar_caixa_bp_fluxo (0031) — e não por INSERT direto em
-- `reconciliacao`. O que está sob teste é o que uma checagem de verdade PASSA
-- para fn_registrar_reconciliacao, e só a costura real prova isso; escrever o
-- estado final à mão provaria só que o INSERT funciona, que ninguém duvida.
--
-- `fn_reconciliar_caixa_bp_fluxo` é a checagem escolhida porque ela já tem,
-- no próprio código (0031), os dois ramos que este arquivo precisa: chama
-- fn_registrar_reconciliacao com 'documento_ausente' quando falta a
-- contraparte, e com 'precondicao_nao_satisfeita' DIRETO (sem motivo mais
-- fino — é o caso que o CONTRATO da 0186 documenta) quando os dois documentos
-- estão presentes mas o Caixa/Disponível não foi localizado.
--
-- O CENÁRIO 4 é diferente de propósito: chama fn_registrar_reconciliacao
-- DIRETO, sem costura, porque o que ele prova é uma propriedade da PRÓPRIA
-- função (validação do vocabulário de p_resultado — achado 1 da revisão
-- independente), não o comportamento de uma checagem específica. Nenhuma
-- checagem real passa um p_resultado desconhecido de propósito; é a função
-- que tem de reprovar quando alguém (checagem futura, erro de digitação)
-- passar.

\set ON_ERROR_STOP on

create or replace function teste_assert_motivo(p_ok boolean, p_nome text, p_detalhe text default null)
returns void language plpgsql as $$
begin
  if p_ok then
    raise notice 'ok    %', p_nome;
  else
    raise exception 'FALHOU: % %', p_nome, coalesce(' — ' || p_detalhe, '');
  end if;
end $$;

-- =============================================================================
do $$
declare
  v_caso uuid;
  v_r    jsonb;
  v_ver  uuid;
  v_doc  uuid;
  v_ent  uuid;
  v_per  uuid;
  v_resultado text;
  v_motivo    text;
  v_n int;
begin
  raise notice '--- 1. BALANÇO sem FLUXO_CAIXA: motivo_precondicao = documento_ausente, SEM pendência ---';
  v_caso := (fn_upsert_caso('0186: sem a contraparte'))::uuid;

  v_r := fn_registrar_documento(v_caso, 'SEM FLUXO LTDA.', 'anual', '2025', 'BALANCO', 0.95,
    'nome_arquivo', 'supabase_storage', 'mp/bp1.pdf', 'BP SEM FLUXO.pdf', true, 'HASH-MP-1', 'ok');
  v_ver := (v_r->>'documento_versao_id')::uuid;
  v_doc := (v_r->>'documento_id')::uuid;
  perform fn_registrar_campos_extraidos(v_ver, jsonb_build_array(
    jsonb_build_object('ordem',0,'chave','Estoques','valor_num','1000','periodo_coluna','2025','confianca','0.97')
  ), 'N2');

  select entidade_id, periodo_id into v_ent, v_per from documento where id = v_doc;

  -- Nenhum FLUXO_CAIXA registrado para este caso: a checagem cai no ramo
  -- 'documento_ausente' de fn_reconciliar_caixa_bp_fluxo (0031, linha do
  -- `if v_doc_bp is null or v_doc_fx is null then`).
  v_r := fn_reconciliar_caixa_bp_fluxo(v_caso, v_ent, v_per);

  select resultado, motivo_precondicao into v_resultado, v_motivo from reconciliacao
   where caso_id = v_caso and tipo = 'caixa_bp_fluxo' order by criado_em desc limit 1;

  perform teste_assert_motivo(v_resultado = 'precondicao_nao_satisfeita',
    'resultado continua achatado em precondicao_nao_satisfeita — o vocabulário não muda',
    coalesce(v_resultado, '(null)'));
  perform teste_assert_motivo(v_motivo = 'documento_ausente',
    'e motivo_precondicao guarda o motivo verdadeiro: documento_ausente',
    coalesce(v_motivo, '(null)'));

  select count(*) into v_n from pendencia
   where caso_id = v_caso and motivo = 'reconciliacao:caixa_bp_fluxo' and estado <> 'resolvida';
  perform teste_assert_motivo(v_n = 0,
    'documento ausente continua NÃO abrindo pendência (cobrança do checklist, não da revisão)',
    format('%s pendência(s)', v_n));
end $$;

-- =============================================================================
do $$
declare
  v_caso uuid;
  v_r    jsonb;
  v_ver_bp uuid;
  v_ver_fx uuid;
  v_doc_bp uuid;
  v_ent uuid;
  v_per uuid;
  v_resultado text;
  v_motivo    text;
  v_n int;
begin
  raise notice '--- 2. BALANÇO + FLUXO_CAIXA presentes, Caixa NÃO localizável: motivo_precondicao != documento_ausente, ABRE pendência ---';
  v_caso := (fn_upsert_caso('0186: linha nao localizavel'))::uuid;

  v_r := fn_registrar_documento(v_caso, 'CAIXA ILEGIVEL LTDA.', 'anual', '2025', 'BALANCO', 0.95,
    'nome_arquivo', 'supabase_storage', 'mp/bp2.pdf', 'BP CAIXA ILEGIVEL.pdf', true, 'HASH-MP-2', 'ok');
  v_ver_bp := (v_r->>'documento_versao_id')::uuid;
  v_doc_bp := (v_r->>'documento_id')::uuid;
  -- De propósito SEM rótulo de caixa/disponível: nenhum dos localizadores de
  -- fn_reconciliar_caixa_bp_fluxo (0031) casa "Estoques" ou "Contas a Receber".
  perform fn_registrar_campos_extraidos(v_ver_bp, jsonb_build_array(
    jsonb_build_object('ordem',0,'chave','Estoques','valor_num','1000','periodo_coluna','2025','confianca','0.97'),
    jsonb_build_object('ordem',1,'chave','Contas a Receber','valor_num','2000','periodo_coluna','2025','confianca','0.97')
  ), 'N2');

  v_r := fn_registrar_documento(v_caso, 'CAIXA ILEGIVEL LTDA.', 'anual', '2025', 'FLUXO_CAIXA', 0.95,
    'nome_arquivo', 'supabase_storage', 'mp/fx2.pdf', 'DFC CAIXA ILEGIVEL.pdf', true, 'HASH-MP-3', 'ok');
  v_ver_fx := (v_r->>'documento_versao_id')::uuid;
  -- O lado da DFC TEM o saldo final — a precondição que falha é só o lado do
  -- Balanço, e é isso que a checagem tem de nomear.
  perform fn_registrar_campos_extraidos(v_ver_fx, jsonb_build_array(
    jsonb_build_object('ordem',0,'chave','Saldo final de caixa','valor_num','1000','periodo_coluna','2025','confianca','0.97')
  ), 'N2');

  select entidade_id, periodo_id into v_ent, v_per from documento where id = v_doc_bp;

  -- Os dois documentos existem: a checagem passa do `if v_doc_bp is null or
  -- v_doc_fx is null` e cai, ao fim do laço de anos, no ramo
  -- `if v_n = 0 then` de fn_reconciliar_caixa_bp_fluxo — que chama
  -- fn_registrar_reconciliacao com 'precondicao_nao_satisfeita' DIRETO.
  v_r := fn_reconciliar_caixa_bp_fluxo(v_caso, v_ent, v_per);

  select resultado, motivo_precondicao into v_resultado, v_motivo from reconciliacao
   where caso_id = v_caso and tipo = 'caixa_bp_fluxo' order by criado_em desc limit 1;

  perform teste_assert_motivo(v_resultado = 'precondicao_nao_satisfeita',
    'os dois documentos estão presentes, e resultado continua o mesmo texto de sempre',
    coalesce(v_resultado, '(null)'));
  -- CORRIGIDO após revisão independente (achado 7): este assert era frouxo —
  -- "não é documento_ausente" passa com QUALQUER outra string, inclusive um
  -- literal fora do vocabulário (o que o achado 1 mostrou fabricar
  -- 'a checagem concluiu'). O CONTRATO diz o valor exato que
  -- fn_reconciliar_caixa_bp_fluxo passa direto neste ramo (0031): afirme-o.
  perform teste_assert_motivo(v_motivo = 'precondicao_nao_satisfeita',
    'e motivo_precondicao é exatamente precondicao_nao_satisfeita — o valor que o CONTRATO diz '
    '(remédio oposto ao cenário 1: revisar a extração/localizador, não cobrar checklist)',
    coalesce(v_motivo, '(null)'));

  select count(*) into v_n from pendencia
   where caso_id = v_caso and motivo = 'reconciliacao:caixa_bp_fluxo' and estado <> 'resolvida';
  perform teste_assert_motivo(v_n = 1,
    'e, ao contrário do cenário 1, ESTA precondição ABRE pendência: documento presente é achado acionável',
    format('%s pendência(s)', v_n));
end $$;

-- =============================================================================
do $$
declare
  v_caso uuid;
  v_r    jsonb;
  v_ver_bp uuid;
  v_ver_fx uuid;
  v_doc_bp uuid;
  v_ent uuid;
  v_per uuid;
  v_resultado text;
  v_motivo    text;
begin
  raise notice '--- 3. checagem que CONCLUI: motivo_precondicao fica NULL ---';
  v_caso := (fn_upsert_caso('0186: checagem conclui'))::uuid;

  v_r := fn_registrar_documento(v_caso, 'CAIXA OK LTDA.', 'anual', '2025', 'BALANCO', 0.95,
    'nome_arquivo', 'supabase_storage', 'mp/bp3.pdf', 'BP CAIXA OK.pdf', true, 'HASH-MP-4', 'ok');
  v_ver_bp := (v_r->>'documento_versao_id')::uuid;
  v_doc_bp := (v_r->>'documento_id')::uuid;
  perform fn_registrar_campos_extraidos(v_ver_bp, jsonb_build_array(
    jsonb_build_object('ordem',0,'chave','Caixa e equivalentes de caixa','valor_num','1000','periodo_coluna','2025','confianca','0.97')
  ), 'N2');

  v_r := fn_registrar_documento(v_caso, 'CAIXA OK LTDA.', 'anual', '2025', 'FLUXO_CAIXA', 0.95,
    'nome_arquivo', 'supabase_storage', 'mp/fx3.pdf', 'DFC CAIXA OK.pdf', true, 'HASH-MP-5', 'ok');
  v_ver_fx := (v_r->>'documento_versao_id')::uuid;
  perform fn_registrar_campos_extraidos(v_ver_fx, jsonb_build_array(
    jsonb_build_object('ordem',0,'chave','Saldo final de caixa','valor_num','1000','periodo_coluna','2025','confianca','0.97')
  ), 'N2');

  select entidade_id, periodo_id into v_ent, v_per from documento where id = v_doc_bp;
  v_r := fn_reconciliar_caixa_bp_fluxo(v_caso, v_ent, v_per);

  select resultado, motivo_precondicao into v_resultado, v_motivo from reconciliacao
   where caso_id = v_caso and tipo = 'caixa_bp_fluxo' order by criado_em desc limit 1;

  perform teste_assert_motivo(v_resultado = 'ok', 'os dois lados batem: resultado = ok', coalesce(v_resultado, '(null)'));
  perform teste_assert_motivo(v_motivo is null,
    'e motivo_precondicao fica NULL — não há precondição nenhuma para nomear',
    coalesce(v_motivo, '(null)'));
end $$;

-- =============================================================================
do $$
declare
  v_caso uuid;
  v_erro boolean := false;
  v_msg  text;
  v_n    int;
begin
  raise notice '--- 4. p_resultado FORA do vocabulário: REPROVA ALTO, não fabrica sucesso (achado 1) ---';
  v_caso := (fn_upsert_caso('0186: vocabulario de resultado'))::uuid;

  -- 'linha_nao_localizado' — uma letra fora do contrato ('...ado' em vez de
  -- '...ada', que é 'linha_nao_localizada'). Chamada DIRETA de propósito (ver
  -- o cabeçalho): a validação é responsabilidade da própria função, não de
  -- quem a chama. entidade/período/documento nulos porque a exceção tem de
  -- disparar ANTES de qualquer FK ser tocada.
  begin
    perform fn_registrar_reconciliacao(v_caso, null, null, 'teste_vocabulario', 'A', null,
      null, null, 'linha_nao_localizado', null, null, null,
      'p_resultado com uma letra fora do contrato — não pode virar sucesso fabricado');
  exception when others then
    v_erro := true;
    get stacked diagnostics v_msg = message_text;
  end;

  perform teste_assert_motivo(v_erro,
    'p_resultado fora do vocabulario levanta excecao (nao vira precondicoes_ok = true fabricado)',
    coalesce(v_msg, '(nao levantou excecao nenhuma)'));

  select count(*) into v_n from reconciliacao
   where caso_id = v_caso and tipo = 'teste_vocabulario';
  perform teste_assert_motivo(v_n = 0,
    'e nao grava linha nenhuma em reconciliacao para o tipo de teste',
    format('%s linha(s) gravada(s)', v_n));
end $$;

drop function teste_assert_motivo(boolean, text, text);
