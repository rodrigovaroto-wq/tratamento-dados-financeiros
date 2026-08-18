-- Testes do banco de perguntas ao cliente (db/migrations/0120).
-- Rodar via db/test/run.sh (que aplica as migrations antes).
--
-- As propriedades travadas:
--
--   #1  balanço sem caixa: A3 é sugerida (gatilho exigencia_ausente), A1/A2
--       NÃO (satisfeitas), e as quatro 'sempre' aparecem — caso com conteúdo;
--   #2  marcador {data_base}/{ano} preenchido com a referência do período, e
--       nenhum marcador sobra sem resolver nas perguntas seedadas do cenário;
--   #3  {saldo_mutuos}: sem linha de mútuo → "(não localizado)"; com linhas na
--       MESMA escala → a soma com a unidade; escalas MISTAS → aviso, nunca uma
--       soma cega;
--   #4  espécie linha_presente (nenhuma seedada — é o upgrade do dono):
--       testada com pergunta temporária ancorada em MUTUOS:saldo_de_mutuo —
--       dispara quando a linha existe, cala quando não;
--   #5  marcador DESCONHECIDO fica VISÍVEL no texto renderizado;
--   #6  ação humana: enviada sem texto é RECUSADA (jsonb, não exceção);
--       enviada com texto grava, audita, e a sugestão passa a ja_enviada=true
--       SEM sumir da lista; código inexistente é recusado;
--   #7  sugerir é SÓ LEITURA: nada muda em campo_extraido nem em pendencia.

\set ON_ERROR_STOP on

create or replace function teste_assert_pg(p_ok boolean, p_nome text, p_detalhe text default null)
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
  v_ent uuid;
  v_caso uuid;
  v_caso2 uuid;
  v_r jsonb;
  v_ver uuid;
  v_n int;
  v_n_campos int;
  v_n_pend int;
  v_txt text;
begin
  raise notice '--- 1. balanço sem caixa: A3 dispara, A1/A2 não, e as quatro sempre aparecem ---';
  v_caso := (fn_upsert_caso('Caso perguntas — balanço sem caixa'))::uuid;
  v_r := fn_registrar_documento(
    v_caso, 'Quero Perguntas Ltda', 'anual', '2025', 'BALANCO', 0.9, 'nome_arquivo',
    'supabase_storage', 'bucket/bp-pg.pdf', 'BP Perguntas.pdf', true, 'HASH-PG-1', 'ok');
  v_ver := (v_r->>'documento_versao_id')::uuid;
  perform fn_registrar_campos_extraidos(v_ver, '[
    {"chave": "TOTAL DO ATIVO",                           "valor_num": "900", "confianca": "0.9"},
    {"chave": "TOTAL DO PASSIVO E DO PATRIMONIO LIQUIDO", "valor_num": "900", "confianca": "0.9"},
    {"chave": "Estoques",                                 "valor_num": "900", "confianca": "0.9"}
  ]'::jsonb, 'N0');

  select count(*) into v_n from fn_sugerir_perguntas(v_caso);
  perform teste_assert_pg(v_n = 5,
    'cinco sugestões: A3 + as quatro sempre (5.1, 5.3, 6.3, 7.1)', 'achou ' || v_n);

  select count(*) into v_n from fn_sugerir_perguntas(v_caso) s
    where s.codigo = 'A3' and s.gatilho = 'exigencia_ausente:BALANCO:caixa_e_equivalentes';
  perform teste_assert_pg(v_n = 1, 'A3 sugerida, com o gatilho declarado', 'achou ' || v_n);

  select count(*) into v_n from fn_sugerir_perguntas(v_caso) s where s.codigo in ('A1', 'A2');
  perform teste_assert_pg(v_n = 0,
    'A1 e A2 NÃO sugeridas — Ativo Total e Passivo+PL estão no documento', 'sugeriu ' || v_n);

  select count(*) into v_n from fn_sugerir_perguntas(v_caso) s
    where s.codigo in ('A4', 'A5', 'A6', 'A7');
  perform teste_assert_pg(v_n = 0,
    'perguntas de FLUXO/DRE/MAPA não disparam sem documento do tipo (cadê-o-documento é item_faltante)',
    'sugeriu ' || v_n);

  raise notice '--- 2. marcadores de período preenchidos ---';
  select s.pergunta into v_txt from fn_sugerir_perguntas(v_caso) s where s.codigo = 'A3';
  perform teste_assert_pg(v_txt like '%2025%' and v_txt not like '%{data_base}%',
    'A3 sai com {data_base} → 2025', left(v_txt, 100));

  raise notice '--- 3. {saldo_mutuos}: não localizado → soma → escalas mistas ---';
  select s.pergunta into v_txt from fn_sugerir_perguntas(v_caso) s where s.codigo = '5.1';
  perform teste_assert_pg(v_txt like '%(não localizado)%',
    'sem linha de mútuo, o marcador declara (não localizado) — nunca em branco', left(v_txt, 120));

  v_r := fn_registrar_documento(
    v_caso, 'Quero Perguntas Ltda', 'anual', '2025', 'MUTUOS', 0.9, 'nome_arquivo',
    'supabase_storage', 'bucket/mut-pg.pdf', 'Mutuos Perguntas.pdf', true, 'HASH-PG-2', 'ok');
  v_ver := (v_r->>'documento_versao_id')::uuid;
  perform fn_registrar_campos_extraidos(v_ver, '[
    {"chave": "Mútuo a receber - Beta", "valor_num": "100", "unidade": "milhar", "confianca": "0.9"},
    {"chave": "Mútuo a pagar - Gama",   "valor_num": "50",  "unidade": "milhar", "confianca": "0.9"}
  ]'::jsonb, 'N0');

  select s.pergunta into v_txt from fn_sugerir_perguntas(v_caso) s where s.codigo = '5.1';
  perform teste_assert_pg(v_txt like '%150 milhar%',
    'duas linhas na MESMA escala: soma com a unidade (150 milhar)', left(v_txt, 140));

  v_r := fn_registrar_documento(
    v_caso, 'Quero Perguntas Ltda', 'anual', '2025', 'MUTUOS', 0.9, 'nome_arquivo',
    'supabase_storage', 'bucket/mut-pg2.pdf', 'Mutuos Perguntas 2.pdf', true, 'HASH-PG-3', 'ok');
  v_ver := (v_r->>'documento_versao_id')::uuid;
  perform fn_registrar_campos_extraidos(v_ver, '[
    {"chave": "Mútuo com Delta", "valor_num": "5", "unidade": "unidade", "confianca": "0.9"}
  ]'::jsonb, 'N0');

  select s.pergunta into v_txt from fn_sugerir_perguntas(v_caso) s where s.codigo = '5.1';
  perform teste_assert_pg(v_txt like '%escalas mistas%',
    'escalas mistas NÃO são somadas às cegas — o marcador avisa', left(v_txt, 140));

  raise notice '--- 4. espécie linha_presente (pergunta temporária — o upgrade do dono) ---';
  insert into pergunta_catalogo
    (codigo, titulo, prioridade, gatilho_especie, gatilho_tipo_taxonomia, gatilho_conceito,
     pergunta, motivo, risco, impacto, gatilho_descricao, fonte)
  values
    ('TESTE_LP', 'teste linha_presente', 4, 'linha_presente', 'MUTUOS', 'saldo_de_mutuo',
     'teste: ha mutuos de {saldo_mutuos}.', 'teste', 'teste', 'teste', 'teste', 'teste');

  select count(*) into v_n from fn_sugerir_perguntas(v_caso) s where s.codigo = 'TESTE_LP';
  perform teste_assert_pg(v_n = 1,
    'linha_presente dispara no caso que TEM linha de mútuo', 'achou ' || v_n);

  v_caso2 := (fn_upsert_caso('Caso perguntas — mutuos sem mutuo'))::uuid;
  v_r := fn_registrar_documento(
    v_caso2, 'Outro Grupo Ltda', 'anual', '2025', 'MUTUOS', 0.9, 'nome_arquivo',
    'supabase_storage', 'bucket/mut-pg3.pdf', 'Mutuos Outro.pdf', true, 'HASH-PG-4', 'ok');
  v_ver := (v_r->>'documento_versao_id')::uuid;
  perform fn_registrar_campos_extraidos(v_ver, '[
    {"chave": "Saldo com controlada Zeta", "valor_num": "70", "confianca": "0.9"}
  ]'::jsonb, 'N0');

  select count(*) into v_n from fn_sugerir_perguntas(v_caso2) s where s.codigo = 'TESTE_LP';
  perform teste_assert_pg(v_n = 0,
    'linha_presente CALA no caso cujo MUTUOS não tem linha de mútuo', 'sugeriu ' || v_n);

  raise notice '--- 5. marcador desconhecido fica visível ---';
  insert into pergunta_catalogo
    (codigo, titulo, prioridade, gatilho_especie, gatilho_tipo_taxonomia, gatilho_conceito,
     pergunta, motivo, risco, impacto, gatilho_descricao, fonte)
  values
    ('TESTE_MARC', 'teste marcador', 4, 'sempre', null, null,
     'teste com {marcador_que_nao_existe} no meio.', 'teste', 'teste', 'teste', 'teste', 'teste');
  select s.pergunta into v_txt from fn_sugerir_perguntas(v_caso) s where s.codigo = 'TESTE_MARC';
  perform teste_assert_pg(v_txt like '%{marcador_que_nao_existe}%',
    'marcador desconhecido permanece VISÍVEL — nunca vira espaço em branco', left(v_txt, 100));

  delete from pergunta_catalogo where codigo in ('TESTE_LP', 'TESTE_MARC');

  raise notice '--- 6. ação humana: recusas em jsonb, envio congelado, ja_enviada informa ---';
  v_r := fn_registrar_pergunta_acao(v_caso, 'A3', 'enviada', null, 'teste@oria');
  perform teste_assert_pg(coalesce((v_r->>'recusado')::boolean, false),
    'enviar SEM o texto é recusado — a trilha precisa dizer O QUE se perguntou', v_r::text);

  v_r := fn_registrar_pergunta_acao(v_caso, 'ZZ_NAO_EXISTE', 'enviada', 'x', 'teste@oria');
  perform teste_assert_pg(coalesce((v_r->>'recusado')::boolean, false),
    'pergunta fora do catálogo é recusada', v_r::text);

  -- A ENTIDADE VOLTA JUNTO NA AÇÃO. Desde que a sugestão é por entidade (0119
  -- no main), registrar o envio sem dizer de qual empresa deixaria a pergunta
  -- da OUTRA empresa marcada como enviada — ou nenhuma delas. `entidade_id` sai
  -- na sugestão exatamente para ser devolvido aqui.
  select s.pergunta, s.entidade_id into v_txt, v_ent
    from fn_sugerir_perguntas(v_caso) s where s.codigo = 'A3';
  v_r := fn_registrar_pergunta_acao(v_caso, 'A3', 'enviada', v_txt, 'teste@oria', v_ent);
  perform teste_assert_pg((v_r->>'caso_pergunta_id') is not null,
    'enviar com o texto renderizado grava', v_r::text);
  select count(*) into v_n from caso_pergunta
    where caso_id = v_caso and pergunta_codigo = 'A3' and acao = 'enviada'
      and texto_enviado like '%2025%';
  perform teste_assert_pg(v_n = 1, 'o texto enviado fica CONGELADO na linha (com o período resolvido)', 'achou ' || v_n);
  select count(*) into v_n from evento_auditoria
    where acao = 'pergunta_enviada' and entidade_ref = 'caso:' || v_caso;
  perform teste_assert_pg(v_n = 1, 'o envio vai para evento_auditoria', 'achou ' || v_n);

  select count(*) into v_n from fn_sugerir_perguntas(v_caso) s
    where s.codigo = 'A3' and s.ja_enviada;
  perform teste_assert_pg(v_n = 1,
    'a sugestão vira ja_enviada=true e CONTINUA listada — informa, não filtra', 'achou ' || v_n);

  v_r := fn_registrar_pergunta_acao(v_caso, '7.1', 'descartada', null, 'teste@oria');
  perform teste_assert_pg((v_r->>'caso_pergunta_id') is not null,
    'descartar não exige texto', v_r::text);

  raise notice '--- 7. sugerir é só leitura ---';
  select count(*) into v_n_campos from campo_extraido;
  select count(*) into v_n_pend from pendencia;
  perform (select count(*) from fn_sugerir_perguntas(v_caso));
  select count(*) - v_n_campos into v_n from campo_extraido;
  perform teste_assert_pg(v_n = 0, 'campo_extraido intacto', 'delta ' || v_n);
  select count(*) - v_n_pend into v_n from pendencia;
  perform teste_assert_pg(v_n = 0, 'pendencia intacta — sugerir não abre nem resolve nada', 'delta ' || v_n);

  -- ---------------------------------------------------------------------------
  -- 8. AS CORREÇÕES DA INCORPORAÇÃO (o conteúdo é do PR #138, revisado)
  -- ---------------------------------------------------------------------------
  raise notice '--- 8. append-only é REGRA DO BANCO, não adjetivo do comentário ---';
  -- O QUE ACONTECIA: a tabela declarava "append-only por desenho" e publicava
  -- `for all to authenticated` — o que deixa qualquer usuário autenticado dar
  -- UPDATE e DELETE. Medido antes do conserto: `set role authenticated; delete
  -- from caso_pergunta` apagou a linha. O texto do que foi perguntado a um
  -- cliente é fato histórico; tabela que promete guardá-lo e aceita `delete`
  -- promete o que não cumpre. O par certo já existia ao lado, no
  -- `evento_auditoria` (0003): INSERT e SELECT, e nada mais — sem política para
  -- um comando, o RLS nega aquele comando.
  select count(*) into v_n from pg_policies
   where tablename = 'caso_pergunta' and cmd in ('ALL', 'UPDATE', 'DELETE');
  perform teste_assert_pg(v_n = 0,
    'caso_pergunta não tem política de UPDATE nem de DELETE — o histórico não se reescreve',
    'achou ' || v_n || ' política(s) permissiva(s)');
  select count(*) into v_n from pg_policies
   where tablename = 'caso_pergunta' and cmd in ('SELECT', 'INSERT');
  perform teste_assert_pg(v_n = 2,
    '…e tem as duas que faltavam: ler e inserir', 'achou ' || v_n);

  raise notice '--- 9. o período do marcador é o MAIS RECENTE por ANO, não por texto ---';
  -- O QUE ACONTECIA: o período saía de `max(referencia)`, máximo de TEXTO sobre
  -- rótulos que não são comparáveis como texto. Num caso com "2025" e "L24M", o
  -- `max` devolve L24M — rótulo de janela móvel, não data de balanço, e nem o
  -- mais recente. E este é o texto que vai para o CLIENTE:
  --   "No balanço de L24M não localizamos uma linha de Ativo Total."
  perform fn_registrar_documento(
    v_caso, 'Quero Perguntas Ltda', 'multi', 'L24M', 'BALANCO', 0.9, 'nome_arquivo',
    'supabase_storage', 'bucket/bp-l24m.pdf', 'BP L24M.pdf', true, 'HASH-PG-L24M', 'ok');
  select s.pergunta into v_txt from fn_sugerir_perguntas(v_caso) s where s.codigo = 'A3' limit 1;
  perform teste_assert_pg(v_txt like '%2025%' and v_txt not like '%L24M%',
    'com 2025 e L24M no mesmo caso, a pergunta diz 2025 — o exercício, não a janela móvel',
    left(v_txt, 140));

  raise notice '--- 10. a pergunta NOMEIA a empresa (o reemit que a 0119 tornou devido) ---';
  -- A pendência `linha_exigida_ausente` nomeia a entidade desde a 0119. A
  -- pergunta é o lado externo da MESMA avaliação — e é ENVIADA ao cliente. Num
  -- grupo de oito balanços, "no balanço de 2025 não localizamos Ativo Total"
  -- não diz de qual empresa se fala: quem recebe não tem como responder.
  select count(*) into v_n from fn_sugerir_perguntas(v_caso) s
   where s.codigo = 'A3' and s.entidade is not null and s.pergunta like 'Sobre a %';
  perform teste_assert_pg(v_n >= 1,
    'a sugestão de exigência ausente nomeia a entidade no texto', 'achou ' || v_n);
  select count(*) into v_n from fn_sugerir_perguntas(v_caso) s
   where s.codigo = '7.1' and (s.entidade is not null or s.pergunta like 'Sobre a %');
  perform teste_assert_pg(v_n = 0,
    'pergunta contextual (sempre) NÃO ganha prefixo de empresa — não é de ninguém em particular',
    'achou ' || v_n);

  raise notice 'perguntas OK — A3 dispara e A1/A2 calam; sempre só com conteúdo; marcadores resolvidos ou visíveis; saldo por escala única; linha_presente pronta para o upgrade do dono; ação humana auditada; só leitura; append-only imposto; período por ano; pergunta com o nome da empresa';
end $$;

drop function teste_assert_pg(boolean, text, text);
