-- Testes do DESEMPATE ENTRE DOCUMENTOS DO MESMO PERÍODO (Supabase/migrations/0151).
-- Rodar via Supabase/test/run.sh (que aplica as migrations antes).
--
-- POR QUE ESTE TESTE CONSTRÓI O PRÓPRIO CASO. Medido nas duas fixtures antes de
-- escrever a migration: o Canastra (28 documentos, extração real) tem 117
-- conceitos em dois ou mais documentos e ZERO conflitos depois dos filtros; o
-- Vertentes, zero também. É a resposta certa — os dois books foram construídos
-- para ser internamente consistentes —, e é também o motivo de uma checagem
-- provada só contra eles não estar provada: função que sempre devolve vazio
-- passa em qualquer teste que só conte linhas.
--
-- As propriedades travadas:
--
--   #1  o conflito é ACHADO e DECIDIDO: balanço assinado × combinado preliminar
--       discordando em 32.800 (o número da armadilha central do araucária),
--       vencedor nomeado e critério por extenso;
--   #2  o EMPATE não decide nada e diz isso — dois balanços igualmente
--       autorizados discordando voltam com `decidido = false`;
--   #3  a soma do realizado PARA DE ESCOLHER O MAIOR: DF auditada 10.000 contra
--       balanço preliminar 42.800, e o realizado passa a usar 10.000. Este é o
--       defeito religado — com a ordem antiga do `array_agg` o teste reprova;
--   #4  os TRÊS FALSOS POSITIVOS medidos na fixture do Canastra continuam
--       fora: rótulo sem seção canônica, papel subtotal, unidade inconversível;
--   #5  a TOLERÂNCIA deixa passar os 3 mil em 7,8 milhões que a nota explicativa
--       e o balanço do Canastra realmente têm entre si;
--   #6  a checagem entra na rodada pelo despachante, abre pendência, e NADA é
--       apagado — as duas linhas continuam gravadas;
--   #7  o marcador de preliminar só casa com palavra inteira ("imprevistos" não
--       é "prévia") e devolve BOOLEANO (o `~` tem precedência maior que o `||`,
--       e sem parênteses a função devolvia texto casando com meia expressão);
--   #8  GUARDA DE FIXTURE: o Canastra continua devolvendo ZERO conflitos. Quem
--       afrouxar um dos três filtros vê aqui, e não em produção.

\set ON_ERROR_STOP on

create or replace function teste_assert_des(p_ok boolean, p_nome text, p_detalhe text default null)
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
  v_caso   uuid;
  v_r      jsonb;
  v_ver    uuid;
  v_c      record;
  v_n      int;
  v_val    numeric;
  v_txt    text;
begin
  -- ---------------------------------------------------------------------------
  raise notice '--- 1. O CONFLITO É ACHADO E DECIDIDO (a armadilha do araucária) ---';
  -- ---------------------------------------------------------------------------
  v_caso := (fn_upsert_caso('Caso desempate entre documentos'))::uuid;

  v_r := fn_registrar_documento(
    v_caso, 'Canastra Embalagens Ltda', 'anual', '2025', 'BALANCO', 0.9, 'nome_arquivo',
    'supabase_storage', 'bucket/bp-2025.pdf', 'Balanço Patrimonial 2025 assinado.pdf',
    true, 'HASH-DES-BP', 'ok');
  v_ver := (v_r->>'documento_versao_id')::uuid;
  perform fn_registrar_campos_extraidos(v_ver, '[
    {"chave": "Clientes", "valor_num": "10000", "unidade": "milhar", "confianca": "0.9",
     "secao_canonica": "ativo_circulante", "periodo_coluna": "2025"}
  ]'::jsonb, 'N0');

  -- O combinado PRELIMINAR infla o ativo do grupo em 32.800 (R$ mil) — e fecha,
  -- porque ativo e passivo caem na mesma medida quando um par intragrupo deixa
  -- de ser eliminado. Nenhuma reconciliação de igualdade acusa isso.
  v_r := fn_registrar_documento(
    v_caso, 'Canastra Embalagens Ltda', 'anual', '2025', 'COMBINADO', 0.9, 'nome_arquivo',
    'supabase_storage', 'bucket/comb-2025.pdf', 'Combinado do grupo PRELIMINAR 2025.xlsx',
    false, 'HASH-DES-COMB', 'ok');
  v_ver := (v_r->>'documento_versao_id')::uuid;
  perform fn_registrar_campos_extraidos(v_ver, '[
    {"chave": "Clientes", "valor_num": "42800", "unidade": "milhar", "confianca": "0.9",
     "secao_canonica": "ativo_circulante", "periodo_coluna": "2025"}
  ]'::jsonb, 'N0');

  select count(*) into v_n from fn_conflitos_do_caso(v_caso);
  perform teste_assert_des(v_n = 1,
    'um conflito, e um só — o mesmo par não volta invertido', 'achou ' || v_n);

  select * into v_c from fn_conflitos_do_caso(v_caso) limit 1;
  perform teste_assert_des(v_c.tipo_vencedor = 'BALANCO',
    'o BALANÇO assinado vence o COMBINADO preliminar', 'venceu ' || v_c.tipo_vencedor);
  perform teste_assert_des(v_c.valor_vencedor = 10000000 and v_c.valor_perdedor = 42800000,
    'os dois valores vêm NA BASE, e o perdedor vem junto (é ele a evidência da escolha)',
    v_c.valor_vencedor || ' × ' || v_c.valor_perdedor);
  perform teste_assert_des(v_c.diferenca = 32800000,
    'a diferença é exatamente os 32.800 (R$ mil) da armadilha', v_c.diferenca::text);
  perform teste_assert_des(v_c.decidido,
    'a autoridade separou os dois: houve decisão');
  perform teste_assert_des(v_c.criterio like '%BALANCO%' and v_c.criterio like '%preliminar%',
    'o critério diz QUEM venceu e POR QUÊ, incluindo o sinal do nome do arquivo',
    left(v_c.criterio, 160));

  -- ---------------------------------------------------------------------------
  raise notice '--- 2. O EMPATE NÃO DECIDE, E DIZ ISSO ---';
  -- ---------------------------------------------------------------------------
  v_caso := (fn_upsert_caso('Caso desempate empate'))::uuid;
  v_r := fn_registrar_documento(
    v_caso, 'Aurora Alimentos Ltda', 'anual', '2025', 'BALANCO', 0.9, 'nome_arquivo',
    'supabase_storage', 'bucket/bp-a.pdf', 'Balanço 2025 - via contabilidade.pdf',
    false, 'HASH-EMP-A', 'ok');
  perform fn_registrar_campos_extraidos((v_r->>'documento_versao_id')::uuid, '[
    {"chave": "Estoques", "valor_num": "5000", "unidade": "milhar", "confianca": "0.9",
     "secao_canonica": "ativo_circulante", "periodo_coluna": "2025"}
  ]'::jsonb, 'N0');
  v_r := fn_registrar_documento(
    v_caso, 'Aurora Alimentos Ltda', 'anual', '2025', 'BALANCO', 0.9, 'nome_arquivo',
    'supabase_storage', 'bucket/bp-b.pdf', 'Balanço 2025 - via diretoria.pdf',
    false, 'HASH-EMP-B', 'ok');
  perform fn_registrar_campos_extraidos((v_r->>'documento_versao_id')::uuid, '[
    {"chave": "Estoques", "valor_num": "9000", "unidade": "milhar", "confianca": "0.9",
     "secao_canonica": "ativo_circulante", "periodo_coluna": "2025"}
  ]'::jsonb, 'N0');

  select * into v_c from fn_conflitos_do_caso(v_caso) limit 1;
  perform teste_assert_des(v_c.decidido is false,
    'dois balanços igualmente autorizados: ninguém vence');
  perform teste_assert_des(v_c.criterio like 'EMPATE%' and v_c.criterio like '%humana%',
    'o critério diz que a escolha é humana, em vez de escondê-la', left(v_c.criterio, 120));

  select valor into v_val from fn_linhas_do_realizado(v_caso, 'Aurora Alimentos Ltda')
   where rotulo_norm = 'estoques';
  perform teste_assert_des(v_val = 9000,
    'no empate o valor NÃO muda — continua o de maior módulo, o mesmo de antes da 0151',
    v_val::text);

  -- ---------------------------------------------------------------------------
  raise notice '--- 3. A SOMA DO REALIZADO PARA DE ESCOLHER O MAIOR (defeito religado) ---';
  -- ---------------------------------------------------------------------------
  v_caso := (fn_upsert_caso('Caso realizado desempatado'))::uuid;
  v_r := fn_registrar_documento(
    v_caso, 'Boreal Transportes Ltda', 'anual', '2025', 'DF_AUDITADA', 0.9, 'nome_arquivo',
    'supabase_storage', 'bucket/df.pdf', 'Demonstrações auditadas 2025.pdf',
    true, 'HASH-REA-DF', 'ok');
  perform fn_registrar_campos_extraidos((v_r->>'documento_versao_id')::uuid, '[
    {"chave": "Clientes", "valor_num": "10000", "unidade": "milhar", "confianca": "0.9",
     "secao_canonica": "ativo_circulante", "periodo_coluna": "2025"}
  ]'::jsonb, 'N0');
  v_r := fn_registrar_documento(
    v_caso, 'Boreal Transportes Ltda', 'anual', '2025', 'BALANCO', 0.9, 'nome_arquivo',
    'supabase_storage', 'bucket/bp-rascunho.pdf', 'Balanço 2025 (rascunho).xlsx',
    false, 'HASH-REA-BP', 'ok');
  perform fn_registrar_campos_extraidos((v_r->>'documento_versao_id')::uuid, '[
    {"chave": "Clientes", "valor_num": "42800", "unidade": "milhar", "confianca": "0.9",
     "secao_canonica": "ativo_circulante", "periodo_coluna": "2025"}
  ]'::jsonb, 'N0');

  select valor into v_val from fn_linhas_do_realizado(v_caso, 'Boreal Transportes Ltda')
   where rotulo_norm = 'clientes';
  perform teste_assert_des(v_val = 10000,
    'o realizado usa a DF AUDITADA (10.000), não o rascunho de maior módulo (42.800)',
    'usou ' || v_val::text);

  -- ---------------------------------------------------------------------------
  raise notice '--- 4. OS TRÊS FALSOS POSITIVOS MEDIDOS NO CANASTRA CONTINUAM FORA ---';
  -- ---------------------------------------------------------------------------
  v_caso := (fn_upsert_caso('Caso desempate falsos positivos'))::uuid;

  -- (a) "total" sem seção canônica: o total de um extrato e o de uma folha não
  -- são o mesmo conceito. (b) "TOTAL DO ATIVO": papel subtotal. (c) a unidade
  -- "pessoas" não converte para base nenhuma.
  v_r := fn_registrar_documento(
    v_caso, 'Cedro Papel Ltda', 'anual', '2025', 'EXTRATO_BANCARIO', 0.9, 'nome_arquivo',
    'supabase_storage', 'bucket/ext.pdf', 'Extrato 2025.pdf', false, 'HASH-FP-EXT', 'ok');
  perform fn_registrar_campos_extraidos((v_r->>'documento_versao_id')::uuid, '[
    {"chave": "Total", "valor_num": "825", "unidade": "milhar", "confianca": "0.9",
     "periodo_coluna": "2025"},
    {"chave": "TOTAL DO ATIVO", "valor_num": "1000", "unidade": "milhar", "confianca": "0.9",
     "secao_canonica": "ativo_circulante", "periodo_coluna": "2025"},
    {"chave": "Quadro de pessoal", "valor_num": "120", "unidade": "pessoas", "confianca": "0.9",
     "secao_canonica": "ativo_circulante", "periodo_coluna": "2025"}
  ]'::jsonb, 'N0');
  v_r := fn_registrar_documento(
    v_caso, 'Cedro Papel Ltda', 'anual', '2025', 'HEADCOUNT', 0.9, 'nome_arquivo',
    'supabase_storage', 'bucket/hc.pdf', 'Headcount 2025.pdf', false, 'HASH-FP-HC', 'ok');
  perform fn_registrar_campos_extraidos((v_r->>'documento_versao_id')::uuid, '[
    {"chave": "Total", "valor_num": "20510", "unidade": "milhar", "confianca": "0.9",
     "periodo_coluna": "2025"},
    {"chave": "TOTAL DO ATIVO", "valor_num": "9000", "unidade": "milhar", "confianca": "0.9",
     "secao_canonica": "ativo_circulante", "periodo_coluna": "2025"},
    {"chave": "Quadro de pessoal", "valor_num": "480", "unidade": "pessoas", "confianca": "0.9",
     "secao_canonica": "ativo_circulante", "periodo_coluna": "2025"}
  ]'::jsonb, 'N0');

  select count(*) into v_n from fn_conflitos_do_caso(v_caso);
  perform teste_assert_des(v_n = 0,
    'rótulo sem seção canônica, papel subtotal e unidade inconversível: nenhum vira conflito',
    'vazaram ' || v_n);

  -- ---------------------------------------------------------------------------
  raise notice '--- 5. A TOLERÂNCIA DEIXA PASSAR O ARREDONDAMENTO REAL DO CANASTRA ---';
  -- ---------------------------------------------------------------------------
  v_caso := (fn_upsert_caso('Caso desempate tolerancia'))::uuid;
  v_r := fn_registrar_documento(
    v_caso, 'Diamante Aco Ltda', 'anual', '2025', 'BALANCO', 0.9, 'nome_arquivo',
    'supabase_storage', 'bucket/bp-t.pdf', 'Balanço 2025.pdf', false, 'HASH-TOL-BP', 'ok');
  perform fn_registrar_campos_extraidos((v_r->>'documento_versao_id')::uuid, '[
    {"chave": "Direito de uso - arrendamentos", "valor_num": "7822", "unidade": "milhar",
     "confianca": "0.9", "secao_canonica": "ativo_nao_circulante", "periodo_coluna": "2025"}
  ]'::jsonb, 'N0');
  v_r := fn_registrar_documento(
    v_caso, 'Diamante Aco Ltda', 'anual', '2025', 'NOTAS_EXPL', 0.9, 'nome_arquivo',
    'supabase_storage', 'bucket/nota.pdf', 'Notas explicativas 2025.pdf', false,
    'HASH-TOL-NE', 'ok');
  perform fn_registrar_campos_extraidos((v_r->>'documento_versao_id')::uuid, '[
    {"chave": "Direito de uso - arrendamentos", "valor_num": "7825", "unidade": "milhar",
     "confianca": "0.9", "secao_canonica": "ativo_nao_circulante", "periodo_coluna": "2025"}
  ]'::jsonb, 'N0');

  select count(*) into v_n from fn_conflitos_do_caso(v_caso);
  perform teste_assert_des(v_n = 0,
    '3 mil em 7,8 milhões (0,04%) é arredondamento, não discordância — os dois números são reais',
    'acusou ' || v_n);

  -- …mas a MESMA dupla, com diferença material, acusa e o balanço vence a nota.
  select count(*) into v_n from fn_conflitos_do_caso(v_caso, null, 100, 0.0001);
  perform teste_assert_des(v_n = 1,
    '…e com a tolerância apertada ela reaparece: é a tolerância que a esconde, não um filtro',
    'achou ' || v_n);
  select * into v_c from fn_conflitos_do_caso(v_caso, null, 100, 0.0001) limit 1;
  perform teste_assert_des(v_c.tipo_vencedor = 'BALANCO',
    'a face da demonstração vence a nota que a detalha', 'venceu ' || v_c.tipo_vencedor);

  -- ---------------------------------------------------------------------------
  raise notice '--- 6. A CHECAGEM ENTRA NA RODADA, ABRE PENDÊNCIA, E NÃO APAGA NADA ---';
  -- ---------------------------------------------------------------------------
  v_caso := (select id from caso where nome = 'Caso desempate entre documentos');

  -- O despachante é chamado pelo workflow depois de gravar os campos, não por
  -- gatilho — é assim que o `reconciliacao.test.sql` e o `canastra.test.sql`
  -- também fazem. Rodá-lo aqui é reproduzir a rodada, não contornar nada.
  perform fn_reconciliar_por_documento(d.id) from documento d where d.caso_id = v_caso;

  select count(*) into v_n from reconciliacao
   where caso_id = v_caso and tipo = 'conflito_entre_documentos' and resultado = 'divergencia';
  perform teste_assert_des(v_n >= 1,
    'o despachante chamou a checagem quando o combinado foi registrado', 'registros: ' || v_n);

  select count(*) into v_n from pendencia
   where caso_id = v_caso and motivo = 'reconciliacao:conflito_entre_documentos'
     and estado <> 'resolvida';
  perform teste_assert_des(v_n >= 1, 'e a pendência está na fila do analista', 'abriu ' || v_n);

  select descricao into v_txt from pendencia
   where caso_id = v_caso and motivo = 'reconciliacao:conflito_entre_documentos'
   order by criada_em desc limit 1;
  perform teste_assert_des(v_txt like '%NADA foi apagado%'
                           and v_txt like '%BALANCO%' and v_txt like '%COMBINADO%',
    'a descrição nomeia os dois documentos e diz que nada foi apagado', left(v_txt, 200));

  -- Os NÚMEROS ficam no jsonb, e não no `like` da descrição de propósito: o
  -- separador de milhar do `to_char` depende do lc_numeric da instalação, e um
  -- assert que casa '42.800' passa aqui e reprova em produção por causa de um
  -- ponto. O que a descrição tem de garantir é que os dois lados APAREÇAM.
  select count(*) into v_n from reconciliacao r,
       jsonb_array_elements(r.fonte_a->'conflitos') x
   where r.caso_id = v_caso and r.tipo = 'conflito_entre_documentos'
     and (x->'vencedor'->>'valor')::numeric = 10000000
     and (x->'perdedor'->>'valor')::numeric = 42800000;
  perform teste_assert_des(v_n >= 1,
    'e o registro guarda os DOIS valores, na base, vencedor e perdedor', 'achou ' || v_n);

  select count(*) into v_n from campo_extraido ce
    join documento_versao dv on dv.id = ce.documento_versao_id
    join documento d on d.id = dv.documento_id
   where d.caso_id = v_caso and fn_normalizar_texto(ce.chave) = 'clientes';
  perform teste_assert_des(v_n = 2,
    'as duas linhas continuam gravadas — o perdedor é a evidência de que houve escolha',
    'sobraram ' || v_n);

  -- ---------------------------------------------------------------------------
  raise notice '--- 7. O MARCADOR DE PRELIMINAR: booleano, e por palavra inteira ---';
  -- ---------------------------------------------------------------------------
  perform teste_assert_des(fn_documento_preliminar('Combinado PRELIMINAR 2025.xlsx') is true,
    'casa com "preliminar"');
  perform teste_assert_des(fn_documento_preliminar('Prévia do combinado.pdf') is true,
    'casa com "prévia" mesmo acentuada (fn_normalizar_texto tira o acento antes)');
  perform teste_assert_des(fn_documento_preliminar('Relatório de imprevistos.pdf') is false,
    'NÃO casa dentro de outra palavra: "imprevistos" não é "prévia"');
  perform teste_assert_des(fn_documento_preliminar('Balanço 2025 final.pdf') is false,
    'e não casa com um nome comum');
  perform teste_assert_des(
    (select pg_typeof(fn_documento_preliminar('x'))::text) = 'boolean',
    'devolve BOOLEANO — sem os parênteses o `~` casava com meia expressão e o retorno virava texto');

  -- ---------------------------------------------------------------------------
  raise notice '--- 8. GUARDA DE FIXTURE: o Canastra continua em ZERO conflitos ---';
  -- ---------------------------------------------------------------------------
  select count(*) into v_n
    from fn_conflitos_do_caso((select id from caso where nome = 'FIXTURE Grupo Canastra'));
  perform teste_assert_des(v_n = 0,
    'o book real, 117 conceitos em 2+ documentos, não gera conflito nenhum', 'gerou ' || v_n);
  select count(*) into v_n
    from fn_conflitos_do_caso((select id from caso where nome = 'FIXTURE Grupo Vertentes'));
  perform teste_assert_des(v_n = 0, '…e o Vertentes também', 'gerou ' || v_n);

  raise notice 'desempate OK — conflito achado e decidido; empate declarado sem trocar valor; o realizado deixa de escolher o maior; os três falsos positivos e a tolerância travados';
end $$;
