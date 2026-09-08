-- Testes do RÓTULO QUE O PRÓPRIO DIAGNÓSTICO CONTESTA (Supabase/migrations/0159).
-- Rodar via Supabase/test/run.sh (que aplica as migrations antes).
--
-- O CASO REAL, do araucária (lote 7417, 03/09/2026): seis documentos
-- classificados COMBINADO pela IA com confiança 1,0, com ZERO empresas nas
-- colunas — o conjunto completo de demonstrações de UMA empresa, não um
-- combinado. O próprio diagnóstico de conteúdo abriu, sozinho, uma pendência
-- `tipo_incorreto` nos seis. Pela escala da 0151/0155:
--
--   167 (COMBINADO, tipo_incorreto aberta, assinado)                = 30+5 = 35
--   002_Balanco_Patrimonial (BALANCO, mesma empresa, mal extraído,
--     49% de cobertura, assinado)                                   = 50+5 = 55
--
-- Sem esta migration, `fn_conflitos_do_caso` resolve o conflito só pela
-- autoridade: o BALANCO mal extraído VENCE em silêncio, e ninguém sabe que o
-- rótulo do perdedor já estava contestado pelo próprio sistema.
--
-- O QUE ESTE ARQUIVO TRAVA, lado a lado — é a simetria que importa:
--
--   #1  o caso medido: COMBINADO com tipo_incorreto ABERTA não decide
--       sozinho, e o conflito contra o BALANCO fica SEM DECISÃO AUTOMÁTICA —
--       mesmo a autoridade DIFERINDO (35 × 55, não é empate numérico);
--   #2  RESOLVIDA a pendência (um humano confirma que o rótulo está certo),
--       o documento volta a decidir sozinho — sem mecanismo novo, é a mesma
--       linha do ciclo de vida que `pendencia.estado` já tem;
--   #3  um COMBINADO comum, SEM pendência nenhuma, continua decidindo
--       sozinho normalmente — é o caso que a tentativa estrutural descartada
--       (ver o cabeçalho da 0159) teria classificado errado, porque ela
--       nunca marca `entidade_coluna`;
--   #4  o espelho exato da 0155, no sentido contrário: BALANCO com VÁRIAS
--       empresas continua decidindo sozinho — é a autoridade dele que cai
--       (via `least`), não a confiança. O buraco fechado pela 0155 não pode
--       reabrir aqui.

\set ON_ERROR_STOP on

create or replace function teste_assert_rotcon(p_ok boolean, p_nome text, p_detalhe text default null)
returns void language plpgsql as $$
begin
  if p_ok then raise notice 'ok    %', p_nome;
  else raise exception 'FALHOU: % %', p_nome, coalesce(' — ' || p_detalhe, ''); end if;
end $$;

do $$
declare
  v_caso      uuid;
  v_caso2     uuid;
  v_r         jsonb;
  v_ver       uuid;
  v_doc       uuid;
  v_comb0     uuid;  -- COMBINADO com tipo_incorreto aberta — o caso medido
  v_balmal    uuid;  -- BALANCO da mesma empresa, mal extraído
  v_combok    uuid;  -- COMBINADO comum, SEM pendência — o controle negativo
  v_bal_multi uuid;  -- BALANCO, VÁRIAS empresas — o espelho da 0155
  v_bal_indiv uuid;  -- BALANCO individual, para conflitar com o de cima
  v_ds        boolean;
  v_c         record;
begin
  v_caso := (fn_upsert_caso('Caso 0159 — o rótulo que o próprio diagnóstico contesta'))::uuid;

  -- ===========================================================================
  -- FIXTURE 1 — O CASO MEDIDO: COMBINADO rotulado pela IA, e o diagnóstico de
  -- conteúdo abre `tipo_incorreto` sozinho. É o 167 do araucária: o conjunto
  -- completo de demonstrações de UMA empresa, não um combinado.
  -- ===========================================================================
  v_r := fn_registrar_documento(
    v_caso, 'Araucaria Serraria Ltda', 'anual', '2025', 'COMBINADO', 1.0, 'openai_conteudo',
    'supabase_storage', 'b/167.pdf',
    '167_Demonstracoes_Contabeis_Completas_Araucaria_Serraria_2025.pdf',
    true, 'HASH-159-COMB0', 'ok');
  v_comb0 := (v_r->>'documento_id')::uuid;
  v_ver   := (v_r->>'documento_versao_id')::uuid;
  perform fn_registrar_campos_extraidos(v_ver, '[
    {"chave": "Clientes", "valor_num": "42800", "unidade": "milhar", "confianca": "0.9",
     "secao_canonica": "ativo_circulante", "periodo_coluna": "2025"}
  ]'::jsonb, 'N0');
  -- O diagnóstico de conteúdo, como no araucária: sugere BALANCO e diz por
  -- extenso que é uma única empresa, não um combinado.
  perform fn_registrar_diagnostico(v_comb0, v_ver, 'Araucaria Serraria Ltda', false, 'BALANCO',
    'anual', '2025', 'ok', null, 'Balanço patrimonial 2025',
    'trata-se de balanço patrimonial e demonstrações de uma única empresa (não combinado)');

  -- O BALANÇO da MESMA empresa, mal extraído (poucos campos, mas autoridade
  -- de BALANCO) — o 002 do araucária. Sem diagnóstico contestando nada.
  v_r := fn_registrar_documento(
    v_caso, 'Araucaria Serraria Ltda', 'anual', '2025', 'BALANCO', 1.0, 'openai_conteudo',
    'supabase_storage', 'b/002.pdf', '002_Balanco_Patrimonial_Araucaria_Serraria_2025.pdf',
    true, 'HASH-159-BALMAL', 'ok');
  v_balmal := (v_r->>'documento_id')::uuid;
  v_ver    := (v_r->>'documento_versao_id')::uuid;
  perform fn_registrar_campos_extraidos(v_ver, '[
    {"chave": "Clientes", "valor_num": "10000", "unidade": "milhar", "confianca": "0.9",
     "secao_canonica": "ativo_circulante", "periodo_coluna": "2025"}
  ]'::jsonb, 'N0');

  -- ===========================================================================
  raise notice '--- 1. O CASO MEDIDO: COMBINADO com tipo_incorreto aberta não decide sozinho ---';
  -- ===========================================================================
  select decide_sozinho into v_ds from fn_autoridade_do_documento(v_comb0);
  perform teste_assert_rotcon(v_ds = false,
    'o COMBINADO com tipo_incorreto aberta tem decide_sozinho = false',
    'sem isso, o rótulo contestado pelo diagnóstico decide um conflito sozinho — o defeito medido');

  select decide_sozinho into v_ds from fn_autoridade_do_documento(v_balmal);
  perform teste_assert_rotcon(v_ds = true,
    'o BALANCO mal extraído, mas sem contradição de rótulo, continua decidindo sozinho',
    'a má extração é um problema à parte — esta migration não julga cobertura');

  select * into v_c
    from fn_conflitos_do_caso(v_caso, 'Araucaria Serraria Ltda')
    where chave = 'Clientes'
    limit 1;
  perform teste_assert_rotcon(v_c.decidido is false,
    'o conflito entre os dois fica SEM DECISÃO AUTOMÁTICA, mesmo a autoridade DIFERINDO (35 × 55)',
    format('decidido = %s, criterio = %s', v_c.decidido, left(v_c.criterio, 200)));
  perform teste_assert_rotcon(
    v_c.criterio like 'SEM DECISÃO AUTOMÁTICA%' and v_c.criterio like '%COMBINADO%',
    'o critério nomeia o lado contestado (COMBINADO) e diz que a escolha é humana',
    left(v_c.criterio, 200));
  perform teste_assert_rotcon(
    v_c.valor_vencedor is not null and v_c.valor_perdedor is not null,
    'os dois valores continuam gravados — nada foi apagado, mesmo sem decisão automática');

  -- ===========================================================================
  raise notice '--- 2. RESOLVIDA A PENDÊNCIA, O DOCUMENTO VOLTA A DECIDIR SOZINHO ---';
  -- ===========================================================================
  update pendencia set estado = 'resolvida', resolvida_em = now(), resolvida_por = 'teste'
   where documento_id = v_comb0 and tipo = 'tipo_incorreto';

  select decide_sozinho into v_ds from fn_autoridade_do_documento(v_comb0);
  perform teste_assert_rotcon(v_ds = true,
    'com a pendência RESOLVIDA (humano confirmou o rótulo), decide_sozinho volta a true',
    'nenhum mecanismo novo de aceitar precisa existir — é o ciclo de vida que pendencia já tem');

  -- ===========================================================================
  -- FIXTURE 2 — O CONTROLE NEGATIVO: um COMBINADO comum, sem NENHUMA pendência
  -- tipo_incorreto, continua decidindo sozinho — é o caso que a tentativa
  -- estrutural descartada (ver o cabeçalho da 0159) teria pego errado, porque
  -- este documento também não marca `entidade_coluna`.
  -- ===========================================================================
  v_r := fn_registrar_documento(
    v_caso, 'Grupo Comum 0159', 'anual', '2025', 'COMBINADO', 1.0, 'openai_conteudo',
    'supabase_storage', 'b/combok.pdf', 'Combinado_do_grupo_comum_2025.pdf',
    true, 'HASH-159-COMBOK', 'ok');
  v_combok := (v_r->>'documento_id')::uuid;
  v_ver     := (v_r->>'documento_versao_id')::uuid;
  perform fn_registrar_campos_extraidos(v_ver, '[
    {"chave": "Estoques", "valor_num": "5000", "unidade": "milhar", "confianca": "0.9",
     "secao_canonica": "ativo_circulante", "periodo_coluna": "2025"}
  ]'::jsonb, 'N0');

  select decide_sozinho into v_ds from fn_autoridade_do_documento(v_combok);
  perform teste_assert_rotcon(v_ds = true,
    'um COMBINADO comum, sem pendência tipo_incorreto, decide sozinho normalmente',
    'a ausência de entidade_coluna sozinha NÃO é motivo — foi a tentativa descartada pela 0159');

  -- ===========================================================================
  -- FIXTURE 3 — O ESPELHO EXATO DA 0155: BALANCO rotulado pela IA, VÁRIAS
  -- empresas nas colunas de verdade. O buraco fechado pela 0155 não pode
  -- reabrir por causa desta migration. CASO PRÓPRIO, para o nome da empresa
  -- não colidir por prefixo com "Araucaria Serraria" das fixtures 1/2
  -- (fn_mesma_entidade casa por subsequência de prefixo — 0153).
  -- ===========================================================================
  v_caso2 := (fn_upsert_caso('Caso 0159 — o espelho da 0155'))::uuid;

  v_r := fn_registrar_documento(
    v_caso2, 'Cambara Grupo 0159', 'anual', '2025', 'BALANCO', 1.0, 'openai_conteudo',
    'supabase_storage', 'b/053b.pdf', '053_Balanco_Patrimonial_COMBINADO_Grupo_0159_2025.pdf',
    true, 'HASH-159-BALMULTI', 'ok');
  v_bal_multi := (v_r->>'documento_id')::uuid;
  v_ver       := (v_r->>'documento_versao_id')::uuid;
  perform fn_registrar_campos_extraidos(v_ver, '[
    {"chave": "Fornecedores", "valor_num": "20000", "unidade": "milhar", "confianca": "0.9",
     "secao_canonica": "passivo_circulante", "periodo_coluna": "2025",
     "entidade_coluna": "Cambara Serraria 0159 Ltda"},
    {"chave": "Fornecedores", "valor_num": "9000", "unidade": "milhar", "confianca": "0.9",
     "secao_canonica": "passivo_circulante", "periodo_coluna": "2025",
     "entidade_coluna": "Cambara Paineis 0159 S.A."}
  ]'::jsonb, 'N0');
  -- Este documento TAMBÉM tem tipo_incorreto aberta (o diagnóstico pode
  -- discordar de qualquer tipo) — e continua decidindo sozinho, porque a
  -- regra da 0159 só olha documentos rotulados COMBINADO.
  perform fn_registrar_diagnostico(v_bal_multi, v_ver, 'Cambara Grupo 0159', false, 'COMBINADO',
    'anual', '2025', 'ok', null, 'Balanço combinado do grupo',
    'traz várias empresas nas colunas — sugere COMBINADO, não BALANCO individual');

  v_r := fn_registrar_documento(
    v_caso2, 'Cambara Serraria 0159 Ltda', 'anual', '2025', 'BALANCO', 1.0, 'openai_conteudo',
    'supabase_storage', 'b/002b.pdf', '002_Balanco_Patrimonial_Cambara_Serraria_0159_2025.pdf',
    true, 'HASH-159-BALINDIV', 'ok');
  v_bal_indiv := (v_r->>'documento_id')::uuid;
  v_ver       := (v_r->>'documento_versao_id')::uuid;
  perform fn_registrar_campos_extraidos(v_ver, '[
    {"chave": "Fornecedores", "valor_num": "20500", "unidade": "milhar", "confianca": "0.9",
     "secao_canonica": "passivo_circulante", "periodo_coluna": "2025"}
  ]'::jsonb, 'N0');

  -- ===========================================================================
  raise notice '--- 3. O ESPELHO DA 0155: BALANCO contestado pelo diagnóstico continua decidindo sozinho ---';
  -- ===========================================================================
  select decide_sozinho into v_ds from fn_autoridade_do_documento(v_bal_multi);
  perform teste_assert_rotcon(v_ds = true,
    'o combinado de verdade (rotulado BALANCO, tipo_incorreto sugerindo COMBINADO) decide sozinho',
    'é a AUTORIDADE dele que a 0155 rebaixa (least, por VÁRIAS empresas), não a confiança da 0159 '
    '— que só olha documentos rotulados COMBINADO. O buraco fechado pela 0155 não pode reabrir.');

  select decide_sozinho into v_ds from fn_autoridade_do_documento(v_bal_indiv);
  perform teste_assert_rotcon(v_ds = true,
    'o balanço individual da empresa também decide sozinho, como sempre');

  select * into v_c
    from fn_conflitos_do_caso(v_caso2, 'Cambara Serraria 0159 Ltda')
    where chave = 'Fornecedores'
    limit 1;
  perform teste_assert_rotcon(v_c.decidido is true,
    'o conflito do espelho da 0155 continua sendo DECIDIDO — a 0159 não se aplica a BALANCO',
    format('decidido = %s, criterio = %s', v_c.decidido, left(v_c.criterio, 200)));
  perform teste_assert_rotcon(
    v_c.criterio like '%vence%' and v_c.criterio not like 'SEM DECISÃO AUTOMÁTICA%',
    'e o critério continua sendo "X vence", não o texto novo desta migration',
    left(v_c.criterio, 200));
  perform teste_assert_rotcon(
    v_c.tipo_vencedor = 'BALANCO' and v_c.valor_vencedor = 20500000,
    'o individual (autoridade 55) vence do combinado de verdade (autoridade 35, teto da 0155)',
    format('vencedor = %s (%s)', v_c.tipo_vencedor, v_c.valor_vencedor));

  raise notice 'rotulo_contraditorio OK — COMBINADO contestado pelo diagnóstico não decide '
               'sozinho, resolvida a pendência ele volta a decidir, o COMBINADO comum não é '
               'afetado, e o espelho da 0155 continua decidindo';
end $$;
