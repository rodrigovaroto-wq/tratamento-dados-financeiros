-- Testes do COMBINADO RECONHECIDO PELA ESTRUTURA (Supabase/migrations/0155).
-- Rodar via Supabase/test/run.sh (que aplica as migrations antes).
--
-- POR QUE ESTE ARQUIVO EXISTE. Pela terceira vez nesta rodada, uma correção que
-- muda número passou pela suíte inteira SEM UMA LINHA DE TESTE NOVA. Não é
-- sinal de segurança — é sinal de que ninguém media aquilo. O que se mede aqui
-- é a escala de autoridade da `0151` contra a classificação REAL que a IA dá a
-- um balanço combinado.
--
-- O CASO REAL, do `book-araucaria` (27/08/2026), com os cinco combinados do
-- grupo classificados pela IA com confiança 1,0:
--
--   053_Balanco_Patrimonial_COMBINADO_..._2025 → BALANCO    (15 empresas)
--   054_Balanco_Patrimonial_COMBINADO_..._2024 → BALANCO    (15 empresas)
--   055_Balanco_Patrimonial_COMBINADO_..._2023 → BALANCO    (15 empresas)
--   056_Balanco_Patrimonial_COMBINADO_..._2022 → COMBINADO  (14 empresas)
--   057_Balanco_Patrimonial_COMBINADO_..._2021 → BALANCO    (14 empresas)
--
-- As propriedades travadas:
--
--   #1  o critério é ESTRUTURAL e tem borda: DUAS ou mais empresas distintas
--       nas colunas. Um comparativo multi-ano de UMA empresa também declara
--       `entidade_coluna`, e rebaixá-lo transformaria todo balanço comparativo
--       em peça derivada;
--   #2  O DEFEITO RELIGADO: um BALANCO com várias empresas PERDE do balanço
--       individual da empresa. Sem a 0155 os dois valem 50 e o resultado é
--       EMPATE — e empate, pela 0151, mantém o valor de maior módulo, que é o
--       combinado inflado. O assert diz os dois números;
--   #3  `least` SÓ ABAIXA: um RAZAO (autoridade 10) com várias empresas
--       continua valendo 10, não sobe para 30;
--   #4  o motivo diz POR EXTENSO que a autoridade foi limitada, e por quê —
--       sem isso o analista lê um número que não sabe de onde veio;
--   #5  os ajustes de assinado (+5) e preliminar (−25) continuam valendo DEPOIS
--       do teto, que é o que faz o combinado preliminar cair para 10.

\set ON_ERROR_STOP on

create or replace function teste_assert_comb(p_ok boolean, p_nome text, p_detalhe text default null)
returns void language plpgsql as $$
begin
  if p_ok then raise notice 'ok    %', p_nome;
  else raise exception 'FALHOU: % %', p_nome, coalesce(' — ' || p_detalhe, ''); end if;
end $$;

do $$
declare
  v_caso    uuid;
  v_r       jsonb;
  v_ver     uuid;
  v_comb    uuid;
  v_indiv   uuid;
  v_multi   uuid;
  v_razao   uuid;
  v_prelim  uuid;
  v_a_comb  int; v_a_indiv int; v_a_multi int; v_a_razao int; v_a_prelim int;
  v_motivo  text;
begin
  v_caso := (fn_upsert_caso('Caso 0155 — o combinado pela estrutura'))::uuid;

  -- O COMBINADO DO GRUPO, classificado como BALANCO — que é o que a IA faz em
  -- quatro de cada cinco. Três empresas nas colunas.
  v_r := fn_registrar_documento(
    v_caso, 'Grupo Araucária', 'anual', '2025', 'BALANCO', 1.0, 'openai_conteudo',
    'supabase_storage', 'b/053.pdf', '053_Balanco_Patrimonial_COMBINADO_Grupo_Araucaria_2025.pdf',
    false, 'HASH-155-COMB', 'ok');
  v_comb := (v_r->>'documento_id')::uuid;
  v_ver  := (v_r->>'documento_versao_id')::uuid;
  perform fn_registrar_campos_extraidos(v_ver, '[
    {"chave": "Clientes", "valor_num": "42800", "unidade": "milhar", "confianca": "0.9",
     "secao_canonica": "ativo_circulante", "periodo_coluna": "2025",
     "entidade_coluna": "Araucaria Serraria Ltda"},
    {"chave": "Clientes", "valor_num": "9000", "unidade": "milhar", "confianca": "0.9",
     "secao_canonica": "ativo_circulante", "periodo_coluna": "2025",
     "entidade_coluna": "Araucaria Paineis S.A."},
    {"chave": "Clientes", "valor_num": "7000", "unidade": "milhar", "confianca": "0.9",
     "secao_canonica": "ativo_circulante", "periodo_coluna": "2025",
     "entidade_coluna": "Araucaria Moveis Ltda"}
  ]'::jsonb, 'N0');

  -- O BALANÇO INDIVIDUAL da empresa, de UMA empresa só.
  v_r := fn_registrar_documento(
    v_caso, 'Araucaria Serraria Ltda', 'anual', '2025', 'BALANCO', 1.0, 'openai_conteudo',
    'supabase_storage', 'b/002.pdf', '002_Balanco_Patrimonial_Araucaria_Serraria_2025.pdf',
    false, 'HASH-155-INDIV', 'ok');
  v_indiv := (v_r->>'documento_id')::uuid;
  v_ver   := (v_r->>'documento_versao_id')::uuid;
  perform fn_registrar_campos_extraidos(v_ver, '[
    {"chave": "Clientes", "valor_num": "10000", "unidade": "milhar", "confianca": "0.9",
     "secao_canonica": "ativo_circulante", "periodo_coluna": "2025"}
  ]'::jsonb, 'N0');

  -- O COMPARATIVO MULTI-ANO DE UMA EMPRESA — a borda que separa "várias
  -- empresas" de "várias colunas". Ele DECLARA entidade_coluna, sempre a mesma.
  v_r := fn_registrar_documento(
    v_caso, 'Araucaria Paineis S.A.', 'multi', '24,25', 'BALANCO', 1.0, 'openai_conteudo',
    'supabase_storage', 'b/003.pdf', '003_Balanco_Patrimonial_Araucaria_Paineis_2025x2024.pdf',
    false, 'HASH-155-MULTI', 'ok');
  v_multi := (v_r->>'documento_id')::uuid;
  v_ver   := (v_r->>'documento_versao_id')::uuid;
  perform fn_registrar_campos_extraidos(v_ver, '[
    {"chave": "Clientes", "valor_num": "9000", "unidade": "milhar", "confianca": "0.9",
     "secao_canonica": "ativo_circulante", "periodo_coluna": "2025",
     "entidade_coluna": "Araucaria Paineis S.A."},
    {"chave": "Clientes", "valor_num": "8000", "unidade": "milhar", "confianca": "0.9",
     "secao_canonica": "ativo_circulante", "periodo_coluna": "2024",
     "entidade_coluna": "Araucaria Paineis S.A."}
  ]'::jsonb, 'N0');

  -- ===========================================================================
  raise notice '--- 1. O CRITÉRIO É ESTRUTURAL, E A BORDA É DUAS ---';
  -- ===========================================================================
  perform teste_assert_comb(fn_documento_de_varias_empresas(v_comb),
    'o documento com TRÊS empresas nas colunas é reconhecido como derivado');
  perform teste_assert_comb(not fn_documento_de_varias_empresas(v_indiv),
    'o balanço individual, sem coluna de empresa, NÃO é');
  perform teste_assert_comb(not fn_documento_de_varias_empresas(v_multi),
    'e o comparativo MULTI-ANO de uma empresa também não — ele tem várias colunas, uma empresa',
    'se este assert cair, todo balanço comparativo vira peça derivada');

  -- ===========================================================================
  raise notice '--- 2. O DEFEITO RELIGADO: o combinado PERDE do individual ---';
  -- ===========================================================================
  select autoridade into v_a_comb  from fn_autoridade_do_documento(v_comb);
  select autoridade into v_a_indiv from fn_autoridade_do_documento(v_indiv);

  perform teste_assert_comb(v_a_comb < v_a_indiv,
    'o combinado do grupo tem MENOS autoridade que o balanço individual da empresa',
    format('combinado = %s, individual = %s. Sem a 0155 os dois valem %s e o resultado é EMPATE '
           || '— e empate, pela 0151, MANTÉM o valor de maior módulo, que é o combinado inflado. '
           || 'É a armadilha central do book-araucaria voltando pela porta da classificação.',
           v_a_comb, v_a_indiv, v_a_indiv));

  perform teste_assert_comb(
    v_a_comb <= (select autoridade from taxonomia_tipo_documento where codigo='COMBINADO'),
    'e ele não passa do teto de COMBINADO, que é o que ele é',
    format('%s contra o teto %s', v_a_comb,
           (select autoridade from taxonomia_tipo_documento where codigo='COMBINADO')));

  select autoridade into v_a_multi from fn_autoridade_do_documento(v_multi);
  perform teste_assert_comb(v_a_multi = v_a_indiv,
    'o comparativo multi-ano continua valendo o mesmo que o balanço de uma empresa',
    format('multi-ano = %s, individual = %s', v_a_multi, v_a_indiv));

  -- ===========================================================================
  raise notice '--- 3. `least` SÓ ABAIXA — nunca levanta ---';
  -- ===========================================================================
  --
  -- Um RAZAO vale 10, abaixo do teto de 30. Se a regra fosse "vira COMBINADO"
  -- em vez de "não passa de COMBINADO", ele SUBIRIA — e um livro razão passaria
  -- a ganhar de um balancete.
  v_r := fn_registrar_documento(
    v_caso, 'Grupo Araucária', 'anual', '2025', 'RAZAO', 1.0, 'openai_conteudo',
    'supabase_storage', 'b/098.pdf', '098_Livro_Razao_Grupo_Araucaria_2025.pdf',
    false, 'HASH-155-RAZAO', 'ok');
  v_razao := (v_r->>'documento_id')::uuid;
  v_ver   := (v_r->>'documento_versao_id')::uuid;
  perform fn_registrar_campos_extraidos(v_ver, '[
    {"chave": "Fornecedor A", "valor_num": "100", "unidade": "milhar", "confianca": "0.9",
     "secao_canonica": "passivo_circulante", "periodo_coluna": "2025",
     "entidade_coluna": "Araucaria Serraria Ltda"},
    {"chave": "Fornecedor B", "valor_num": "200", "unidade": "milhar", "confianca": "0.9",
     "secao_canonica": "passivo_circulante", "periodo_coluna": "2025",
     "entidade_coluna": "Araucaria Paineis S.A."}
  ]'::jsonb, 'N0');

  select autoridade into v_a_razao from fn_autoridade_do_documento(v_razao);
  perform teste_assert_comb(
    v_a_razao = (select autoridade from taxonomia_tipo_documento where codigo='RAZAO'),
    'o RAZAO com várias empresas continua valendo 10 — a regra não LEVANTA autoridade',
    format('veio %s, esperado %s', v_a_razao,
           (select autoridade from taxonomia_tipo_documento where codigo='RAZAO')));

  -- ===========================================================================
  raise notice '--- 4. O MOTIVO DIZ POR EXTENSO QUE FOI LIMITADO ---';
  -- ===========================================================================
  select motivo into v_motivo from fn_autoridade_do_documento(v_comb);
  perform teste_assert_comb(v_motivo like '%VÁRIAS empresas%' and v_motivo like '%derivada%',
    'o motivo explica que a autoridade foi limitada, e por quê', v_motivo);

  -- ===========================================================================
  raise notice '--- 5. ASSINADO E PRELIMINAR VALEM DEPOIS DO TETO ---';
  -- ===========================================================================
  --
  -- É o combinado PRELIMINAR do araucária: teto 30, menos 25 do preliminar.
  -- Se o preliminar fosse aplicado antes do teto, ele acabaria em 30 e a peça
  -- mais frágil do book valeria o mesmo que o combinado assinado.
  v_r := fn_registrar_documento(
    v_caso, 'Grupo Araucária', 'anual', '2024', 'BALANCO', 1.0, 'openai_conteudo',
    'supabase_storage', 'b/059.pdf', '059_Balanco_Combinado_Grupo_Araucaria_2024_versao_preliminar.pdf',
    false, 'HASH-155-PRELIM', 'ok');
  v_prelim := (v_r->>'documento_id')::uuid;
  v_ver    := (v_r->>'documento_versao_id')::uuid;
  perform fn_registrar_campos_extraidos(v_ver, '[
    {"chave": "Clientes", "valor_num": "42800", "unidade": "milhar", "confianca": "0.9",
     "secao_canonica": "ativo_circulante", "periodo_coluna": "2024",
     "entidade_coluna": "Araucaria Serraria Ltda"},
    {"chave": "Clientes", "valor_num": "9000", "unidade": "milhar", "confianca": "0.9",
     "secao_canonica": "ativo_circulante", "periodo_coluna": "2024",
     "entidade_coluna": "Araucaria Paineis S.A."}
  ]'::jsonb, 'N0');

  select autoridade into v_a_prelim from fn_autoridade_do_documento(v_prelim);
  perform teste_assert_comb(v_a_prelim = v_a_comb - 25,
    'o combinado PRELIMINAR cai 25 abaixo do combinado normal — o teto vem antes do desconto',
    format('preliminar = %s, combinado = %s', v_a_prelim, v_a_comb));
  perform teste_assert_comb(v_a_prelim < v_a_indiv,
    'e ele fica bem abaixo do balanço individual, que é o ponto inteiro da 0151',
    format('preliminar = %s, individual = %s', v_a_prelim, v_a_indiv));

  -- ===========================================================================
  raise notice '--- 6. AS BORDAS QUE FALTAVAM ---';
  -- ===========================================================================
  --
  -- (a) A DF AUDITADA CONSOLIDADA. Ela vale 60 — é a peça que o comitê aceita
  -- sem perguntar — e cai para 30 quando as colunas nomeiam várias empresas.
  -- Está escrito no cabeçalho da 0155 como deliberado, e um "deliberado" sem
  -- teste é uma intenção: se alguém discordar, é aqui que a discordância
  -- aparece, com o número ao lado.
  v_r := fn_registrar_documento(
    v_caso, 'Grupo Araucária', 'anual', '2023', 'DF_AUDITADA', 1.0, 'openai_conteudo',
    'supabase_storage', 'b/df-grupo.pdf', 'Demonstracoes_Financeiras_Auditadas_Grupo_2023.pdf',
    false, 'HASH-155-DFGRUPO', 'ok');
  v_ver := (v_r->>'documento_versao_id')::uuid;
  perform fn_registrar_campos_extraidos(v_ver, '[
    {"chave": "Clientes", "valor_num": "1000", "unidade": "milhar", "confianca": "0.9",
     "secao_canonica": "ativo_circulante", "periodo_coluna": "2023",
     "entidade_coluna": "Araucaria Serraria Ltda"},
    {"chave": "Clientes", "valor_num": "2000", "unidade": "milhar", "confianca": "0.9",
     "secao_canonica": "ativo_circulante", "periodo_coluna": "2023",
     "entidade_coluna": "Araucaria Paineis S.A."}
  ]'::jsonb, 'N0');
  select autoridade into v_a_multi from fn_autoridade_do_documento((v_r->>'documento_id')::uuid);
  perform teste_assert_comb(
    v_a_multi = (select autoridade from taxonomia_tipo_documento where codigo='COMBINADO'),
    'a DF AUDITADA consolidada cai de 60 para a autoridade de combinado — deliberado, e medido',
    format('veio %s; a escala não mede a qualidade da auditoria, mede a distância até a peça '
           || 'original, e uma consolidada continua sendo a soma das empresas', v_a_multi));

  -- (b) LINHA SEM COLUNA DE EMPRESA NO MEIO. Um combinado real tem linhas de
  -- cabeçalho e de total que não pertencem a empresa nenhuma. Elas não podem
  -- fazer o documento deixar de ser reconhecido como derivado.
  v_r := fn_registrar_documento(
    v_caso, 'Grupo Araucária', 'anual', '2022', 'BALANCO', 1.0, 'openai_conteudo',
    'supabase_storage', 'b/comb-misto.pdf', 'Balanco_Combinado_com_totais_2022.pdf',
    false, 'HASH-155-MISTO', 'ok');
  v_ver := (v_r->>'documento_versao_id')::uuid;
  perform fn_registrar_campos_extraidos(v_ver, '[
    {"chave": "Clientes", "valor_num": "1000", "unidade": "milhar", "confianca": "0.9",
     "secao_canonica": "ativo_circulante", "periodo_coluna": "2022",
     "entidade_coluna": "Araucaria Serraria Ltda"},
    {"chave": "Clientes", "valor_num": "2000", "unidade": "milhar", "confianca": "0.9",
     "secao_canonica": "ativo_circulante", "periodo_coluna": "2022",
     "entidade_coluna": "Araucaria Paineis S.A."},
    {"chave": "Ativo Circulante", "valor_num": "3000", "unidade": "milhar", "confianca": "0.9",
     "secao_canonica": "ativo_circulante", "periodo_coluna": "2022"}
  ]'::jsonb, 'N0');
  perform teste_assert_comb(
    fn_documento_de_varias_empresas((v_r->>'documento_id')::uuid),
    'linha de TOTAL sem coluna de empresa não desfaz o reconhecimento — as outras duas bastam');

  -- (c) DOCUMENTO SEM EXTRAÇÃO NENHUMA. `fn_versao_com_extracao` devolve null e
  -- a contagem vem vazia: a função tem de responder FALSO, não nulo — nulo
  -- propagaria para o `case` e a autoridade sairia nula.
  v_r := fn_registrar_documento(
    v_caso, 'Araucaria Trading Ltda', 'anual', '2025', 'BALANCO', 1.0, 'nome_arquivo',
    'supabase_storage', 'b/vazio.pdf', 'Balanco_sem_extracao_2025.pdf',
    false, 'HASH-155-VAZIO', 'ok');
  perform teste_assert_comb(
    fn_documento_de_varias_empresas((v_r->>'documento_id')::uuid) = false,
    'documento sem extração responde FALSO, não nulo');
  select autoridade into v_a_multi from fn_autoridade_do_documento((v_r->>'documento_id')::uuid);
  perform teste_assert_comb(v_a_multi is not null,
    'e a autoridade dele continua sendo um número — nulo se propagaria para o desempate',
    coalesce(v_a_multi::text, 'NULO'));

  raise notice 'autoridade_combinado OK — o combinado se reconhece pela estrutura, perde do '
               'individual, o comparativo multi-ano não é afetado, e least só abaixa';
end $$;
