-- Testes do Kit Básico aceitando o COMBINADO por ESTRUTURA (Supabase/migrations/0157).
-- Rodar via Supabase/test/run.sh (que aplica as migrations antes).
--
-- O DEFEITO MEDIDO (lote 7377, mandato "teste Canastra", 02/09): dois
-- documentos com 8 empresas na planilha, confiança 1,0, classificados de
-- BALANCO pela IA, deixavam o item COMBINADO do Kit Básico "ausente" — e a
-- pendência é bloqueante e NÃO-sobrepujável: sem botão no portal que destrave.
--
-- As propriedades travadas, todas em COMPORTAMENTO (o estado da pendência),
-- nunca em mecanismo:
--
--   #1  documento rotulado BALANCO mas com colunas de VÁRIAS empresas (>=2)
--       COM VALOR SATISFAZ o item COMBINADO — nenhuma pendência item_faltante
--       abre;
--   #2  o MESMO documento, mas com UMA empresa só nas colunas (ou nenhuma),
--       NÃO satisfaz — a pendência continua aberta, bloqueante e
--       não-sobrepujável, exatamente como antes da 0157;
--   #3  o CASO REAL: a pendência bloqueante já aberta (porque o documento
--       ainda não tinha chegado) se RESOLVE sozinha assim que o documento
--       estrutural chega e o caso é recomputado — sem código novo além do
--       passo (1), que já resolvia pendência fora da lista corrente desde a
--       0006;
--   #4  um item que NÃO é COMBINADO (BALANCO) continua exigindo o rótulo —
--       um documento de várias empresas rotulado de DRE não o satisfaz como
--       BALANCO. DRE, por ser demonstração contábil primária, SATISFAZ
--       COMBINADO — é a decisão do achado B da revisão, não mais um
--       comportamento fonte-agnóstico;
--   #5  (achado A da revisão) cabeçalho de VÁRIAS empresas SEM NENHUM VALOR
--       (valor_num nulo em todas as linhas) NÃO satisfaz — a sub-extração que
--       perde os números mantendo os cabeçalhos não é combinado, e a
--       pendência abre dizendo o motivo, nunca em silêncio;
--   #6  (achado B da revisão) fonte fora da lista de demonstrações primárias
--       — DF_AUDITADA, com várias empresas e valor de verdade — NÃO satisfaz.
--       É o arranjo realista que a lista fechada existe para não deixar
--       passar: a DF auditada consolidada de um grupo não é o item COMBINADO;
--   #7  (achado C da revisão) o combinado servido por estrutura tem as 3
--       exigências de linha do item (ativo_total, passivo_mais_pl,
--       caixa_e_equivalentes) de fato AVALIADAS: as duas presentes não abrem
--       pendência, a ausente abre — nada fica mudo.

\set ON_ERROR_STOP on

create or replace function teste_assert_kbc(p_ok boolean, p_nome text, p_detalhe text default null)
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
  v_r jsonb;
  v_ver uuid;
  v_n int;
  v_severidade text;
  v_sobrepujavel boolean;
begin
  raise notice '--- 1. BALANCO com 3 empresas nas colunas SATISFAZ o item COMBINADO ---';
  v_caso := (fn_upsert_caso('Caso combinado rotulado de balanco'))::uuid;

  v_r := fn_registrar_documento(
    v_caso, 'Grupo Canastra', 'anual', '2025', 'BALANCO', 1.0, 'openai_conteudo',
    'supabase_storage', 'bucket/13-balanco-combinado.pdf',
    '13_Balanco_COMBINADO_Grupo_Canastra_2025.pdf', true, 'HASH-CANASTRA-13', 'ok');
  v_ver := (v_r->>'documento_versao_id')::uuid;
  perform fn_registrar_campos_extraidos(v_ver, '[
    {"chave": "TOTAL DO ATIVO",                           "valor_num": "100", "confianca": "1.0", "entidade_coluna": "Canastra Alfa Ltda"},
    {"chave": "TOTAL DO PASSIVO E DO PATRIMONIO LIQUIDO", "valor_num": "100", "confianca": "1.0", "entidade_coluna": "Canastra Alfa Ltda"},
    {"chave": "TOTAL DO ATIVO",                           "valor_num": "200", "confianca": "1.0", "entidade_coluna": "Canastra Beta Ltda"},
    {"chave": "TOTAL DO PASSIVO E DO PATRIMONIO LIQUIDO", "valor_num": "200", "confianca": "1.0", "entidade_coluna": "Canastra Beta Ltda"},
    {"chave": "TOTAL DO ATIVO",                           "valor_num": "300", "confianca": "1.0", "entidade_coluna": "Canastra Gama Ltda"},
    {"chave": "TOTAL DO PASSIVO E DO PATRIMONIO LIQUIDO", "valor_num": "300", "confianca": "1.0", "entidade_coluna": "Canastra Gama Ltda"}
  ]'::jsonb, 'N0');

  perform fn_recomputar_completude(v_caso);

  select count(*) into v_n from pendencia
    where caso_id = v_caso and tipo = 'item_faltante' and estado <> 'resolvida'
      and descricao = 'Item obrigatório do Kit Básico ausente: COMBINADO';
  perform teste_assert_kbc(v_n = 0,
    'BALANCO com 3 empresas nas colunas satisfaz o item COMBINADO (nenhuma pendência)', 'abriu ' || v_n);

  raise notice '--- 2. o MESMO documento com UMA empresa só NÃO satisfaz — pendência continua ---';
  v_caso := (fn_upsert_caso('Caso balanco de uma empresa so'))::uuid;

  v_r := fn_registrar_documento(
    v_caso, 'Canastra Alfa Ltda', 'anual', '2025', 'BALANCO', 1.0, 'openai_conteudo',
    'supabase_storage', 'bucket/bp-alfa.pdf', 'BP Canastra Alfa 2025.pdf', true,
    'HASH-CANASTRA-ALFA', 'ok');
  v_ver := (v_r->>'documento_versao_id')::uuid;
  -- Balanço de UMA empresa só: as duas linhas repetem a MESMA entidade_coluna
  -- ("Canastra Alfa Ltda"), então count(distinct entidade_coluna) = 1 — é
  -- exatamente o caso que a 0155 blinda com ">1" em vez de ">0" (um
  -- comparativo de dois anos da MESMA empresa também repetiria a mesma
  -- entidade_coluna, e rebaixá-lo inventaria combinado onde não há grupo).
  perform fn_registrar_campos_extraidos(v_ver, '[
    {"chave": "TOTAL DO ATIVO",                           "valor_num": "100", "confianca": "1.0", "entidade_coluna": "Canastra Alfa Ltda"},
    {"chave": "TOTAL DO PASSIVO E DO PATRIMONIO LIQUIDO", "valor_num": "100", "confianca": "1.0", "entidade_coluna": "Canastra Alfa Ltda"}
  ]'::jsonb, 'N0');

  perform fn_recomputar_completude(v_caso);

  select count(*), min(severidade::text), bool_and(sobrepujavel) into v_n, v_severidade, v_sobrepujavel
    from pendencia
    where caso_id = v_caso and tipo = 'item_faltante' and estado <> 'resolvida'
      and descricao = 'Item obrigatório do Kit Básico ausente: COMBINADO';
  perform teste_assert_kbc(v_n = 1,
    'balanço de UMA empresa não satisfaz o item COMBINADO — a pendência continua aberta', 'achou ' || v_n);
  perform teste_assert_kbc(v_severidade = 'bloqueante',
    'a pendência é bloqueante, como sempre foi (0004)', coalesce(v_severidade, '(nulo)'));
  perform teste_assert_kbc(v_sobrepujavel = false,
    'a pendência é NÃO-sobrepujável (COMBINADO está na lista fechada da 0004) — sem botão que destrave',
    coalesce(v_sobrepujavel::text, '(nulo)'));

  raise notice '--- 3. O CASO REAL: a pendência bloqueante JÁ ABERTA se resolve sozinha ---';
  v_caso := (fn_upsert_caso('Caso lote 7377 travado depois destravado'))::uuid;

  -- Primeiro recompute, ANTES do documento chegar: abre a pendência (entre
  -- outras) igual ao lote 7377 antes dos documentos 13/14 serem processados.
  perform fn_recomputar_completude(v_caso);
  select count(*) into v_n from pendencia
    where caso_id = v_caso and tipo = 'item_faltante' and estado <> 'resolvida'
      and descricao = 'Item obrigatório do Kit Básico ausente: COMBINADO';
  perform teste_assert_kbc(v_n = 1,
    'setup: sem documento nenhum, a pendência do COMBINADO abre (comportamento herdado, intocado)',
    'achou ' || v_n);

  -- O documento estrutural chega (13_Balanco_COMBINADO..., 3 empresas, rotulado BALANCO).
  v_r := fn_registrar_documento(
    v_caso, 'Grupo Canastra', 'anual', '2025', 'BALANCO', 1.0, 'openai_conteudo',
    'supabase_storage', 'bucket/13-balanco-combinado.pdf',
    '13_Balanco_COMBINADO_Grupo_Canastra_2025.pdf', true, 'HASH-CANASTRA-13B', 'ok');
  v_ver := (v_r->>'documento_versao_id')::uuid;
  perform fn_registrar_campos_extraidos(v_ver, '[
    {"chave": "TOTAL DO ATIVO",                           "valor_num": "100", "confianca": "1.0", "entidade_coluna": "Canastra Alfa Ltda"},
    {"chave": "TOTAL DO ATIVO",                           "valor_num": "200", "confianca": "1.0", "entidade_coluna": "Canastra Beta Ltda"}
  ]'::jsonb, 'N0');

  -- No pipeline real quem chama fn_recomputar_completude é o n8n, depois do
  -- registro; aqui o segundo recompute explícito é o que faz esse segundo
  -- passo acontecer no teste.
  perform fn_recomputar_completude(v_caso);

  select count(*) into v_n from pendencia
    where caso_id = v_caso and tipo = 'item_faltante' and estado = 'resolvida'
      and descricao = 'Item obrigatório do Kit Básico ausente: COMBINADO';
  perform teste_assert_kbc(v_n = 1,
    'a pendência bloqueante já aberta é RESOLVIDA sozinha quando o combinado estrutural chega',
    'resolvida(s): ' || v_n);
  select count(*) into v_n from pendencia
    where caso_id = v_caso and tipo = 'item_faltante' and estado <> 'resolvida'
      and descricao = 'Item obrigatório do Kit Básico ausente: COMBINADO';
  perform teste_assert_kbc(v_n = 0,
    'e nenhuma pendência do COMBINADO permanece aberta', 'ainda aberta(s): ' || v_n);

  raise notice '--- 4. a exceção NÃO generaliza PARA O OUTRO LADO: estrutura não serve como BALANCO ---';
  -- A restrição de desenho (cabeçalho da 0157) é sobre BALANCO, não sobre
  -- COMBINADO: um documento estrutural (várias empresas nas colunas) pode
  -- satisfazer o item COMBINADO quando sua FONTE é demonstração contábil
  -- primária — DRE, BALANCO ou FLUXO_CAIXA (decisão do achado B da revisão;
  -- "demonstrações combinadas", a descrição do código no catálogo, não é
  -- exclusividade do balanço). O que NÃO pode acontecer é o inverso: esse
  -- MESMO documento, estrutural, não pode passar a servir como BALANCO —
  -- senão o Kit Básico deixaria de exigir o balanço INDIVIDUAL de cada
  -- empresa, que é o problema que a 0157 existe para não criar.
  v_caso := (fn_upsert_caso('Caso excecao nao generaliza'))::uuid;

  v_r := fn_registrar_documento(
    v_caso, 'Grupo Canastra', 'anual', '2025', 'DRE', 1.0, 'openai_conteudo',
    'supabase_storage', 'bucket/dre-combinada.pdf', 'DRE COMBINADA Grupo Canastra 2025.pdf', true,
    'HASH-CANASTRA-DRE', 'ok');
  v_ver := (v_r->>'documento_versao_id')::uuid;
  perform fn_registrar_campos_extraidos(v_ver, '[
    {"chave": "RECEITA BRUTA", "valor_num": "500", "confianca": "1.0", "entidade_coluna": "Canastra Alfa Ltda"},
    {"chave": "RECEITA BRUTA", "valor_num": "700", "confianca": "1.0", "entidade_coluna": "Canastra Beta Ltda"}
  ]'::jsonb, 'N0');

  perform fn_recomputar_completude(v_caso);

  select count(*) into v_n from pendencia
    where caso_id = v_caso and tipo = 'item_faltante' and estado <> 'resolvida'
      and descricao = 'Item obrigatório do Kit Básico ausente: BALANCO';
  perform teste_assert_kbc(v_n = 1,
    'um DRE (ainda que estrutural, de várias empresas) NÃO serve como BALANCO — a exceção é só do '
    'lado do COMBINADO', 'abriu ' || v_n);
  select count(*) into v_n from pendencia
    where caso_id = v_caso and tipo = 'item_faltante' and estado <> 'resolvida'
      and descricao = 'Item obrigatório do Kit Básico ausente: COMBINADO';
  perform teste_assert_kbc(v_n = 0,
    'e o MESMO documento, estrutural, satisfaz o item COMBINADO — DRE é demonstração contábil '
    'primária (achado B da revisão), não "qualquer tipo serve"', 'abriu ' || v_n);

  raise notice '--- 5. (achado A) cabeçalho de VÁRIAS empresas SEM NENHUM VALOR não satisfaz ---';
  -- A sub-extração que a 0154 mediu (40%-78% no araucária, book escaneado):
  -- os cabeçalhos de empresa saem da extração, os números não. `valor_num`
  -- "n/d" vira NULL em fn_registrar_campos_extraidos (a mesma cascata usada
  -- em produção) — sem isto, a versão original da 0157 dava o item por
  -- satisfeito com um documento do qual não saiu nenhum número.
  v_caso := (fn_upsert_caso('Caso combinado sem nenhum valor extraido'))::uuid;

  v_r := fn_registrar_documento(
    v_caso, 'Grupo Canastra', 'anual', '2025', 'BALANCO', 1.0, 'openai_conteudo',
    'supabase_storage', 'bucket/combinado-sem-valor.pdf',
    'Balanco COMBINADO Grupo Canastra 2025 (escaneado).pdf', true,
    'HASH-CANASTRA-SEM-VALOR', 'ok');
  v_ver := (v_r->>'documento_versao_id')::uuid;
  perform fn_registrar_campos_extraidos(v_ver, '[
    {"chave": "TOTAL DO ATIVO",                           "valor_num": "n/d", "confianca": "1.0", "entidade_coluna": "Canastra Alfa Ltda"},
    {"chave": "TOTAL DO PASSIVO E DO PATRIMONIO LIQUIDO", "valor_num": "n/d", "confianca": "1.0", "entidade_coluna": "Canastra Alfa Ltda"},
    {"chave": "TOTAL DO ATIVO",                           "valor_num": "n/d", "confianca": "1.0", "entidade_coluna": "Canastra Beta Ltda"},
    {"chave": "TOTAL DO PASSIVO E DO PATRIMONIO LIQUIDO", "valor_num": "n/d", "confianca": "1.0", "entidade_coluna": "Canastra Beta Ltda"}
  ]'::jsonb, 'N0');

  perform fn_recomputar_completude(v_caso);

  select count(*), min(severidade::text), bool_and(sobrepujavel) into v_n, v_severidade, v_sobrepujavel
    from pendencia
    where caso_id = v_caso and tipo = 'item_faltante' and estado <> 'resolvida'
      and descricao = 'Item obrigatório do Kit Básico ausente: COMBINADO';
  perform teste_assert_kbc(v_n = 1,
    'cabeçalho de várias empresas SEM NENHUM valor extraído não satisfaz o item COMBINADO — a '
    'pendência abre, não fica em silêncio', 'achou ' || v_n);
  perform teste_assert_kbc(v_severidade = 'bloqueante' and v_sobrepujavel = false,
    '…e a pendência é bloqueante e não-sobrepujável, exatamente como um COMBINADO que nunca chegou',
    format('severidade=%s sobrepujavel=%s', coalesce(v_severidade, '(nulo)'), coalesce(v_sobrepujavel::text, '(nulo)')));

  raise notice '--- 6. (achado B) fonte fora da lista de demonstrações primárias não satisfaz ---';
  -- O arranjo REALISTA que a lista fechada existe para não deixar passar: uma
  -- DF_AUDITADA consolidada de grupo (a 0151 já a trata como par de BALANCO
  -- na escala de autoridade) com colunas de várias empresas e valor de
  -- verdade. Sem a restrição de fonte, isto satisfaria COMBINADO mesmo que o
  -- mandato nunca tenha mandado o combinado de verdade.
  v_caso := (fn_upsert_caso('Caso df auditada consolidada nao serve como combinado'))::uuid;

  v_r := fn_registrar_documento(
    v_caso, 'Grupo Canastra', 'anual', '2025', 'DF_AUDITADA', 1.0, 'openai_conteudo',
    'supabase_storage', 'bucket/df-auditada-consolidada.pdf',
    'DF Auditada Consolidada Grupo Canastra 2025.pdf', true,
    'HASH-CANASTRA-DFAUD', 'ok');
  v_ver := (v_r->>'documento_versao_id')::uuid;
  perform fn_registrar_campos_extraidos(v_ver, '[
    {"chave": "TOTAL DO ATIVO",                           "valor_num": "100", "confianca": "1.0", "entidade_coluna": "Canastra Alfa Ltda"},
    {"chave": "TOTAL DO PASSIVO E DO PATRIMONIO LIQUIDO", "valor_num": "100", "confianca": "1.0", "entidade_coluna": "Canastra Alfa Ltda"},
    {"chave": "TOTAL DO ATIVO",                           "valor_num": "200", "confianca": "1.0", "entidade_coluna": "Canastra Beta Ltda"},
    {"chave": "TOTAL DO PASSIVO E DO PATRIMONIO LIQUIDO", "valor_num": "200", "confianca": "1.0", "entidade_coluna": "Canastra Beta Ltda"}
  ]'::jsonb, 'N0');

  perform fn_recomputar_completude(v_caso);

  select count(*) into v_n from pendencia
    where caso_id = v_caso and tipo = 'item_faltante' and estado <> 'resolvida'
      and descricao = 'Item obrigatório do Kit Básico ausente: COMBINADO';
  perform teste_assert_kbc(v_n = 1,
    'DF_AUDITADA consolidada, com várias empresas e valor de verdade, NÃO satisfaz o item COMBINADO '
    '— fonte fora da lista de demonstrações primárias (decisão do achado B; DF_AUDITADA fica de '
    'fora de propósito, ver o cabeçalho da 0157)', 'abriu ' || v_n);

  raise notice '--- 7. (achado C) o combinado servido por estrutura tem as exigências de LINHA avaliadas ---';
  -- Mesmo arranjo do teste #1 (BALANCO com 3 empresas), mas SEM a linha de
  -- caixa: ativo_total e passivo_mais_pl vêm nas 3 empresas,
  -- caixa_e_equivalentes não vem em nenhuma. Antes da correção do achado C,
  -- 'COMBINADO' nunca entrava em fn_exigencias_do_caso quando o documento
  -- está rotulado BALANCO, e as 3 exigências ficavam mudas — nem satisfeitas,
  -- nem ausentes. Aqui elas têm de aparecer avaliadas: as duas presentes SEM
  -- pendência, a ausente COM pendência.
  v_caso := (fn_upsert_caso('Caso combinado estrutural com exigencia de linha ausente'))::uuid;

  v_r := fn_registrar_documento(
    v_caso, 'Grupo Canastra', 'anual', '2025', 'BALANCO', 1.0, 'openai_conteudo',
    'supabase_storage', 'bucket/combinado-sem-caixa.pdf',
    'Balanco COMBINADO Grupo Canastra 2025 (sem caixa).pdf', true,
    'HASH-CANASTRA-SEM-CAIXA', 'ok');
  v_ver := (v_r->>'documento_versao_id')::uuid;
  perform fn_registrar_campos_extraidos(v_ver, '[
    {"chave": "TOTAL DO ATIVO",                           "valor_num": "100", "confianca": "1.0", "entidade_coluna": "Canastra Alfa Ltda"},
    {"chave": "TOTAL DO PASSIVO E DO PATRIMONIO LIQUIDO", "valor_num": "100", "confianca": "1.0", "entidade_coluna": "Canastra Alfa Ltda"},
    {"chave": "TOTAL DO ATIVO",                           "valor_num": "200", "confianca": "1.0", "entidade_coluna": "Canastra Beta Ltda"},
    {"chave": "TOTAL DO PASSIVO E DO PATRIMONIO LIQUIDO", "valor_num": "200", "confianca": "1.0", "entidade_coluna": "Canastra Beta Ltda"},
    {"chave": "TOTAL DO ATIVO",                           "valor_num": "300", "confianca": "1.0", "entidade_coluna": "Canastra Gama Ltda"},
    {"chave": "TOTAL DO PASSIVO E DO PATRIMONIO LIQUIDO", "valor_num": "300", "confianca": "1.0", "entidade_coluna": "Canastra Gama Ltda"}
  ]'::jsonb, 'N0');

  perform fn_recomputar_completude(v_caso);

  -- Pré-condição: o item COMBINADO em si está satisfeito (é a mesma forma do
  -- teste #1) — senão o teste mediria travamento no passo 1, não silêncio no
  -- passo 2b.
  select count(*) into v_n from pendencia
    where caso_id = v_caso and tipo = 'item_faltante' and estado <> 'resolvida'
      and descricao = 'Item obrigatório do Kit Básico ausente: COMBINADO';
  perform teste_assert_kbc(v_n = 0,
    'PRÉ-CONDIÇÃO: o item COMBINADO está satisfeito por estrutura (mesma forma do teste #1)',
    'abriu ' || v_n);

  select count(*) into v_n from pendencia
    where caso_id = v_caso and tipo = 'linha_exigida_ausente' and estado <> 'resolvida'
      and motivo = 'completude:linha_exigida:COMBINADO:caixa_e_equivalentes';
  perform teste_assert_kbc(v_n = 1,
    'a linha "caixa_e_equivalentes" do COMBINADO servido por estrutura é cobrada como ausente — '
    'não fica muda', 'achou ' || v_n);

  select count(*) into v_n from pendencia
    where caso_id = v_caso and tipo = 'linha_exigida_ausente' and estado <> 'resolvida'
      and motivo = 'completude:linha_exigida:COMBINADO:ativo_total';
  perform teste_assert_kbc(v_n = 0,
    '…e "ativo_total", que ESTÁ nas 3 empresas, é reconhecida como satisfeita — a avaliação '
    'discrimina, não acusa tudo por reflexo', 'achou ' || v_n);

  select count(*) into v_n from pendencia
    where caso_id = v_caso and tipo = 'linha_exigida_ausente' and estado <> 'resolvida'
      and motivo = 'completude:linha_exigida:COMBINADO:passivo_mais_pl';
  perform teste_assert_kbc(v_n = 0,
    '…e "passivo_mais_pl", também presente, idem', 'achou ' || v_n);

  raise notice 'kit_basico_combinado_estrutural OK — estrutural com valor satisfaz; uma empresa ou '
               'sem valor não satisfaz; pendência já aberta se resolve sozinha; a exceção não '
               'generaliza para o lado do BALANCO; fonte fora da lista (DF_AUDITADA) não satisfaz; '
               'e as exigências de linha do combinado estrutural são avaliadas, não mudas';
end $$;

drop function teste_assert_kbc(boolean, text, text);
