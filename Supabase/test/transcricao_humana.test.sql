-- Testes da transcrição humana assistida (Supabase/migrations/0129).
-- Rodar via Supabase/test/run.sh (que aplica as migrations antes).
--
-- O QUE ESTES TESTES TRAVAM. O fechamento nº 2 do `Arquitetura do Sistema/1 Visão e Doutrina/01` — "gate de captura com
-- saída: input ilegível → transcrição humana assistida, nunca dead-end" — era o
-- único dos oito fechamentos sem código. Agora que a saída existe, as propriedades
-- que precisam de teto são estas, e a primeira é a que mais importa:
--
--   1. LINHA TRANSCRITA NÃO CONTA NA MEDIÇÃO DA EXTRAÇÃO. Ela mora na mesma tabela
--      das linhas que a IA leu. Sem o filtro da 0129, a primeira transcrição
--      inflaria fn_golden_campos: linha digitada por uma pessoa olhando o documento
--      bate com o rótulo quase sempre, e o acerto sairia creditado à extração —
--      subindo justamente nos documentos difíceis, que são os transcritos. Se este
--      assert cair, o sistema volta a medir a si mesmo por cima do trabalho humano,
--      e o número sobe, que é a direção que ninguém investiga.
--   2. AS GUARDAS DE EXTRAÇÃO NÃO RODAM. Elas pegam alucinação de modelo. Quatro
--      contas com o mesmo valor é padrão suspeito numa saída de IA e é rotina num
--      balanço com contas zeradas — acusar um humano de fabricar por ler o papel
--      seria uma guarda que só atrapalha.
--   3. A TRANSCRIÇÃO É VERSÃO NOVA e vira a vigente (doutrina da 0026 + 0102), com
--      a versão ilegível preservada contando a história.
--   4. A PENDÊNCIA DE ILEGIBILIDADE FECHA, com o nome de quem a fechou — é isto que
--      faz o gate deixar de ser dead-end.
--   5. CONFIANÇA NULA. Confiança é autoavaliação de modelo; não existe equivalente
--      para pessoa, e escrever 1.0 inventaria uma medida.

\set ON_ERROR_STOP on

create or replace function teste_assert_th(p_ok boolean, p_nome text, p_detalhe text default null)
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
  v_ent    uuid;
  v_per    uuid;
  v_doc    uuid;
  v_ver0   uuid;
  v_r      jsonb;
  v_ver1   uuid;
  v_n      int;
  v_txt    text;
  v_num    numeric;
  v_pend   uuid;
begin
  v_caso := (fn_upsert_caso('Caso transcricao humana 0129'))::uuid;
  insert into entidade (caso_id, razao_social) values (v_caso, 'Ilegível Ltda.')
    returning id into v_ent;
  insert into periodo (caso_id, tipo, referencia) values (v_caso, 'anual', '2025')
    returning id into v_per;
  insert into documento (caso_id, entidade_id, periodo_id, tipo_taxonomia, confianca)
    values (v_caso, v_ent, v_per, 'BALANCO', 0.9) returning id into v_doc;
  -- A versão ILEGÍVEL: existe, aponta para o arquivo, e não tem linha nenhuma.
  insert into documento_versao (documento_id, n_versao, arquivo_ref, nome_original, hash,
                                legibilidade, nota_legibilidade)
    values (v_doc, 1, 'bucket/ilegivel.pdf', 'BP escaneado torto.pdf', 'HASH-ILEG',
            'ilegivel', 'Digitalização em ângulo, colunas sobrepostas.')
    returning id into v_ver0;
  -- E a pendência que o gate abre.
  insert into pendencia (caso_id, origem_estagio, tipo, severidade, sobrepujavel,
                         descricao, documento_id, motivo)
    values (v_caso, 'diagnostico', 'arquivo_ilegivel', 'importante', true,
            'Digitalização em ângulo, colunas sobrepostas.', v_doc,
            'diagnostico:legibilidade:' || v_doc)
    returning id into v_pend;

  -- ==========================================================================
  raise notice '--- 1. as recusas, antes de qualquer coisa ser gravada ---';
  -- ==========================================================================
  v_r := fn_registrar_transcricao_humana(v_doc, '[]'::jsonb, 'rodrigo@oria');
  perform teste_assert_th((v_r->>'recusado')::boolean,
    'transcrição sem linha nenhuma é RECUSADA', v_r::text);
  perform teste_assert_th(v_r->>'motivo_recusa' like '%vazia%',
    'e o motivo diz por quê: versão vazia parece transcrita e não tem número',
    v_r->>'motivo_recusa');

  v_r := fn_registrar_transcricao_humana(
    v_doc, jsonb_build_array(jsonb_build_object('chave','X','valor_num','1')), '   ');
  perform teste_assert_th((v_r->>'recusado')::boolean,
    'transcrição sem AUTOR é recusada — não há guarda de máquina para isto, por desenho',
    v_r::text);

  v_r := fn_registrar_transcricao_humana(
    gen_random_uuid(), jsonb_build_array(jsonb_build_object('chave','X','valor_num','1')),
    'rodrigo@oria');
  perform teste_assert_th((v_r->>'recusado')::boolean,
    'documento inexistente é recusado — transcrição não é caminho para inserir arquivo');

  select count(*) into v_n from campo_extraido
   where documento_versao_id in (select id from documento_versao where documento_id = v_doc);
  perform teste_assert_th(v_n = 0, 'e nenhuma das recusas gravou linha', format('%s linhas', v_n));

  -- ==========================================================================
  raise notice '--- 2. a transcrição: versão nova, aceita, com autor e confiança NULA ---';
  -- ==========================================================================
  -- Quatro contas com o MESMO valor material, de propósito: é exatamente o padrão
  -- que dispara a guarda de "padrão suspeito" numa saída de IA (0013/0022), e é
  -- rotina num balanço com contas zeradas.
  v_r := fn_registrar_transcricao_humana(v_doc, jsonb_build_array(
      jsonb_build_object('chave','Caixa e equivalentes','valor_num','1500',
                         'unidade','milhar','secao_canonica','ativo_circulante',
                         'periodo_coluna','2025','origem_pagina','1'),
      jsonb_build_object('chave','Ativo Total','valor_num','9000',
                         'unidade','milhar','secao_canonica','ativo_circulante',
                         'periodo_coluna','2025'),
      jsonb_build_object('chave','Adiantamento a fornecedor A','valor_num','2500',
                         'unidade','milhar','secao_canonica','ativo_circulante',
                         'periodo_coluna','2025'),
      jsonb_build_object('chave','Adiantamento a fornecedor B','valor_num','2500',
                         'unidade','milhar','secao_canonica','ativo_circulante',
                         'periodo_coluna','2025'),
      jsonb_build_object('chave','Adiantamento a fornecedor C','valor_num','2500',
                         'unidade','milhar','secao_canonica','ativo_circulante',
                         'periodo_coluna','2025'),
      jsonb_build_object('chave','Adiantamento a fornecedor D','valor_num','2500',
                         'unidade','milhar','secao_canonica','ativo_circulante',
                         'periodo_coluna','2025')
    ), 'rodrigo@oria', 'o cliente não tem outra via do arquivo');
  perform teste_assert_th(coalesce((v_r->>'recusado')::boolean, false) = false,
    'a transcrição é aceita', v_r::text);
  perform teste_assert_th((v_r->>'n_versao')::int = 2,
    'e cria a VERSÃO 2 — transcrição é leitura nova (doutrina da 0026)', v_r::text);
  perform teste_assert_th((v_r->>'linhas')::int = 6, 'com as 6 linhas', v_r::text);
  v_ver1 := (v_r->>'documento_versao_id')::uuid;

  perform teste_assert_th(fn_versao_com_extracao(v_doc) = v_ver1,
    'e a versão transcrita passa a ser a VIGENTE (fn_versao_com_extracao, 0102)');
  perform teste_assert_th(
    exists (select 1 from documento_versao where id = v_ver0 and legibilidade = 'ilegivel'),
    'a versão ilegível fica preservada, contando por que houve transcrição');

  select count(*) into v_n from campo_extraido
   where documento_versao_id = v_ver1 and origem_valor = 'transcricao_humana';
  perform teste_assert_th(v_n = 6,
    'as 6 linhas nascem marcadas como origem_valor = transcricao_humana', format('%s', v_n));

  select count(*) into v_n from campo_extraido
   where documento_versao_id = v_ver1 and status_aceite = 'aceito' and aceito_por = 'rodrigo@oria';
  perform teste_assert_th(v_n = 6,
    'e já aceitas, com o nome de quem digitou — ele é a FONTE, não quem confirma máquina',
    format('%s', v_n));

  select count(*) into v_n from campo_extraido
   where documento_versao_id = v_ver1 and confianca is not null;
  perform teste_assert_th(v_n = 0,
    'confiança NULA em todas: não existe autoavaliação de pessoa, e 1.0 inventaria uma medida',
    format('%s com confiança', v_n));

  -- ==========================================================================
  raise notice '--- 3. AS GUARDAS DE EXTRAÇÃO NÃO RODAM ---';
  -- ==========================================================================
  perform teste_assert_th(
    not exists (select 1 from pendencia
                 where documento_id = v_doc and tipo = 'extracao_padrao_suspeito'),
    'quatro contas com o MESMO valor material NÃO abrem "padrão suspeito"',
    'a guarda pega alucinação de modelo; num balanço com contas zeradas isso é rotina');
  perform teste_assert_th(
    not exists (select 1 from pendencia
                 where documento_id = v_doc and tipo = 'extracao_baixa_confianca'),
    'e confiança nula não dispara "baixa confiança" — não há confiança a julgar');

  -- ==========================================================================
  raise notice '--- 4. a SAÍDA foi tomada: a pendência de ilegibilidade fecha ---';
  -- ==========================================================================
  select estado::text into v_txt from pendencia where id = v_pend;
  perform teste_assert_th(v_txt = 'resolvida',
    'a pendência de arquivo ilegível está RESOLVIDA — o gate deixou de ser dead-end',
    coalesce(v_txt, '(null)'));
  select resolvida_por into v_txt from pendencia where id = v_pend;
  perform teste_assert_th(v_txt = 'rodrigo@oria',
    'e resolvida COM O NOME de quem transcreveu, não por "sistema"', coalesce(v_txt, '(null)'));

  perform teste_assert_th(
    exists (select 1 from evento_auditoria
             where acao = 'transcricao_humana' and entidade_ref = 'documento_versao:'||v_ver1),
    'a transcrição fica na trilha');
  perform teste_assert_th(
    exists (select 1 from decisao where caso_id = v_caso and autor = 'rodrigo@oria'
              and payload->>'documento_versao_id' = v_ver1::text),
    'e vira DECISÃO registrada, porque um número entrou na base por ato humano');

  -- E a classificação contábil rodou sobre a versão nova, como sobre qualquer outra.
  perform teste_assert_th(
    exists (select 1 from campo_classe_sugerida s
             join campo_extraido ce on ce.id = s.campo_extraido_id
            where ce.documento_versao_id = v_ver1)
    or not exists (select 1 from campo_extraido ce
                    where ce.documento_versao_id = v_ver1
                      and fn_secao_e_de_resultado(ce.secao_canonica)),
    'a classificação contábil roda sobre a versão transcrita (ou não tem linha de resultado nela)');

  raise notice 'TODOS OS TESTES DA TRANSCRIÇÃO PASSARAM';
end $$;

-- =============================================================================
-- O ASSERT QUE PROTEGE A MEDIÇÃO — em bloco próprio, porque monta uma rodada de
-- golden set inteira.
--
-- O CENÁRIO: um documento cujas linhas foram TRANSCRITAS, com rótulo de golden set
-- afirmando exatamente os valores que o humano digitou. Se a transcrição contasse,
-- ela apareceria como acerto perfeito da extração. O correto é ela aparecer como
-- AUSENTE: a extração não devolveu aquelas linhas — uma pessoa as escreveu.
-- =============================================================================
do $$
declare
  v_caso   uuid;
  v_ent    uuid;
  v_per    uuid;
  v_doc    uuid;
  v_ver    uuid;
  v_rodada uuid;
  v_r      jsonb;
  v_exato  int;
  v_ausente int;
  v_acerto numeric;
begin
  v_caso := (fn_upsert_caso('Caso contaminacao golden 0129'))::uuid;
  insert into entidade (caso_id, razao_social) values (v_caso, 'Transcrita SA')
    returning id into v_ent;
  insert into periodo (caso_id, tipo, referencia) values (v_caso, 'anual', '2025')
    returning id into v_per;
  insert into documento (caso_id, entidade_id, periodo_id, tipo_taxonomia, confianca)
    values (v_caso, v_ent, v_per, 'BALANCO', 0.9) returning id into v_doc;
  insert into documento_versao (documento_id, n_versao, arquivo_ref, nome_original, hash,
                                legibilidade)
    values (v_doc, 1, 'bucket/cont.pdf', 'BP.pdf', 'HASH-CONT', 'ilegivel');

  v_r := fn_registrar_transcricao_humana(v_doc, jsonb_build_array(
      jsonb_build_object('chave','Caixa e equivalentes','valor_num','1500',
                         'unidade','milhar','secao_canonica','ativo_circulante',
                         'periodo_coluna','2025'),
      jsonb_build_object('chave','Estoques','valor_num','3200',
                         'unidade','milhar','secao_canonica','ativo_circulante',
                         'periodo_coluna','2025')
    ), 'ian@oria', 'arquivo escaneado sem outra via');
  v_ver := (v_r->>'documento_versao_id')::uuid;

  -- Uma rodada de golden set REAL, congelada, cujo rótulo afirma exatamente os
  -- valores transcritos.
  insert into golden_rodada (nome, taxonomia_versao, criada_por)
    values ('teste-0129-contaminacao', 1, 'teste:transcricao') returning id into v_rodada;
  insert into golden_documento (rodada_id, documento_id, estrato, origem, incluido_por)
    values (v_rodada, v_doc, 'escaneado', 'real', 'teste:transcricao');
  insert into golden_rotulo (rodada_id, documento_id, rotulador, tipo_correto)
    values (v_rodada, v_doc, 'rotulador:ana', 'BALANCO');
  insert into golden_campo (rodada_id, documento_id, rotulador, chave, periodo_coluna,
                            valor_correto, tolerancia)
    values (v_rodada, v_doc, 'rotulador:ana', 'Caixa e equivalentes', '2025', 1500, 0),
           (v_rodada, v_doc, 'rotulador:ana', 'Estoques',             '2025', 3200, 0);
  update golden_rodada set congelada_em = now(), congelada_por = 'teste:transcricao'
   where id = v_rodada;

  select n_exato, n_ausente, acerto into v_exato, v_ausente, v_acerto
    from fn_golden_campos(v_rodada) where tipo = 'BALANCO';

  perform teste_assert_th(coalesce(v_exato, 0) = 0,
    'as duas linhas TRANSCRITAS não contam como acerto da extração',
    format('n_exato=%s — se for 2, a transcrição está sendo creditada à IA', v_exato));
  perform teste_assert_th(v_ausente = 2,
    'elas contam como AUSENTES: a extração não devolveu nada, uma pessoa escreveu',
    format('n_ausente=%s', v_ausente));
  perform teste_assert_th(coalesce(v_acerto, 0) = 0,
    'e o acerto da extração naquele documento é ZERO, que é a verdade',
    format('acerto=%s', v_acerto));

  raise notice 'ok    (o assert que impede o sistema de medir a si mesmo por cima do trabalho humano)';
  raise notice 'TODOS OS TESTES DE CONTAMINAÇÃO PASSARAM';
end $$;
