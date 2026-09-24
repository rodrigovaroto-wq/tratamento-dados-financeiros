-- =============================================================================
-- 0182 — `controlador` + `entidade_controlador`: o grupo por CONTROLE COMUM que
--        `entidade.controladora_id` (0181) não alcança quando não há holding, fatia 1.7a do
--        plano F1
--
-- MEDIÇÃO NÃO-VAZIA (regra 2 do CLAUDE.md) — REMEDIDA EM 21/09/2026 contra este arquivo como
-- ele está, com 32 asserts no corpo do bloco. A primeira versão deste
-- cabeçalho dizia "24", denominador que não correspondia ao arquivo — e denominador errado torna
-- a medição irreproduzível, que é a regra 2 por fora.
--
-- (a) A GUARDA DE SOMA: com a criação do `trigger trg_entidade_controlador_soma_maxima` comentada
--     na 0182 (a função-guarda existe, mas nada a chama) e `teste_assert_0182` trocado
--     temporariamente para não abortar no primeiro assert (`raise notice` em vez de `raise
--     exception`) e contar todos — **5 dos 32 asserts reprovaram**: os 3 do bloco 3 ("a terceira
--     participação que passaria de 100% é recusada", "nada foi gravado — a soma continua em 80,
--     não 130", "o terceiro sócio nem aparece no vínculo") e os 2 do bloco 8, que cobrem a
--     MUDANÇA DE `entidade_id` (mover um vínculo de 60 para uma entidade que já soma 80). Os
--     dois primeiros inserts do bloco 3 (45 + 35 = 80) NÃO discriminam: nenhum ultrapassa 100
--     sozinho, então passam com ou sem a guarda. Religado o trigger, os 32 passam.
--
-- (b) O FECHO TRANSITIVO: com o join da recursão trocado de `pd.a = al.alcancavel` para
--     `pd.a = al.entidade_id` (cada entidade passa a ver só quem compartilha controlador
--     diretamente com ela, sem propagar) e `teste_assert_0182` contando todos — **3 dos 32
--     asserts reprovaram**: "A e C (que só se ligam via B) caem no MESMO grupo", "o grupo de
--     A/B/C tem exatamente 3 entidades, não 2" e — a surpresa que só a medição revelou — "A e B
--     estão no mesmo grupo", que PARECE ser de um salto só.
--
--     A causa dessa terceira: `grupo_id` é o menor `alcancavel` do alcance INTEIRO, não do
--     vínculo direto. Sem propagação, A alcança {A,B} e tira o grupo_id desse par; B alcança
--     {A,B,C} e tira o dela dos três — quando C ordena antes de A textualmente, os dois divergem
--     e o assert quebra sem nunca ter perguntado sobre C. A quebra da transitividade VAZA para
--     uma afirmação que parecia local. "B e C estão no mesmo grupo" é a única comparação de fato
--     robusta a um salto, e não discrimina.
--
-- (c) OS 24 QUE NÃO DISCRIMINAM NENHUM DOS DOIS PROTOCOLOS, nomeados pela mesma honestidade que a
--     0181 usou com os 25 dela: unicidade de documento por caso, checks de tabela por UPDATE
--     direto, percentual NULL distinguível de linha ausente, reatribuição de percentual e
--     controle cross-caso são invariantes GENUÍNOS, independentes das duas guardas — protegem
--     coisas diferentes, e não deveriam cair em nenhum dos dois protocolos.
--
-- O QUE ESTE ARQUIVO MEDE:
--   1. fn_controlador_registrar grava nome/documento/tipo_pessoa e o evento_auditoria; documento
--      duplicado no MESMO caso é recusado pelo índice único, documento NULL repetido não colide;
--   2. os checks da tabela `entidade_controlador` recusam mesmo por UPDATE direto (percentual
--      fora de (0,100]);
--   3. A GUARDA DE SOMA: sócio A com 45%, sócio B com 35% (soma 80, aceito); um terceiro sócio
--      que levaria a soma a 130% é RECUSADO, e nada muda — nem a soma, nem o terceiro vínculo;
--      NÃO exige soma = 100 (dois sócios somando 80 continuam válidos, sem terceiro nenhum);
--   4. percentual NULL é distinguível da ausência da linha — um sócio conhecido sem percentual
--      medido aparece com percentual NULL, e uma pessoa sem vínculo nenhum não aparece na tabela;
--   5. O FECHO TRANSITIVO: A e B compartilham o controlador X; B e C compartilham o controlador Y
--      (controlador DIFERENTE — a cadeia só fecha por transitividade via B); D não compartilha
--      controlador com ninguém. fn_grupo_por_controle_comum devolve A, B, C no MESMO grupo (3
--      entidades) e D de fora (sem controlador, não aparece);
--   6. reatribuir o percentual de um vínculo já existente é permitido — é o ESTADO ATUAL, e o
--      evento_auditoria registra o valor anterior;
--   7. controle: entidade inexistente, controlador inexistente e controlador de OUTRO caso são
--      recusados com `raise exception`, sem gravar nada;
--   8. o nome da entidade aparece corretamente em fn_grupo_por_controle_comum (não é uma
--      "prova vazia" que só olha ids).
-- =============================================================================

create or replace function teste_assert_0182(p_cond boolean, p_nome text, p_detalhe text default null)
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
  v_caso              uuid;
  v_outro_caso        uuid;
  v_ctrl_a            uuid;
  v_ctrl_b            uuid;
  v_ctrl_c            uuid;
  v_ctrl_outro_caso   uuid;
  v_ent_x             uuid;
  v_soma_ent          uuid;
  v_soma_socio_a      uuid;
  v_soma_socio_b      uuid;
  v_soma_socio_c      uuid;
  v_soma_socio_c_bis  uuid;
  v_perc_ent          uuid;
  v_grupo_a           uuid;
  v_grupo_b           uuid;
  v_grupo_c           uuid;
  v_grupo_d           uuid;
  v_reatrib_ent       uuid;
  v_reatrib_ctrl      uuid;
  v_id                uuid;
  v_vinculo_id        uuid;
  v_documento         text;
  v_tipo_pessoa       controlador_tipo_pessoa;
  v_percentual        numeric;
  v_percentual_ant    numeric;
  v_ev_n              int;
  v_ev_depois         jsonb;
  v_excecao           boolean;
  v_grupo_n           int;
  v_grupo_ids         uuid[];
  v_razao             text;
begin
  v_caso := (fn_upsert_caso('0182 — controle comum'))::uuid;
  v_outro_caso := (fn_upsert_caso('0182 — outro caso (controle)'))::uuid;

  raise notice '--- 1. fn_controlador_registrar grava nome/documento/tipo_pessoa e o evento ---';
  v_ctrl_a := fn_controlador_registrar(v_caso, 'Karina Souto Damasio Tascino', '111.111.111-11',
                                        'fisica', 'analista@0182');

  select nome, documento, tipo_pessoa into v_razao, v_documento, v_tipo_pessoa
    from controlador where id = v_ctrl_a;
  perform teste_assert_0182(v_razao = 'Karina Souto Damasio Tascino'
                             and v_documento = '111.111.111-11' and v_tipo_pessoa = 'fisica',
    'nome, documento e tipo_pessoa gravados', format('%s/%s/%s', v_razao, v_documento, v_tipo_pessoa));

  select count(*) into v_ev_n from evento_auditoria
   where acao = 'controlador_registrado' and entidade_ref = 'controlador:' || v_ctrl_a;
  perform teste_assert_0182(v_ev_n = 1, 'o evento_auditoria de registro foi gravado',
    format('%s evento(s)', v_ev_n));

  select depois into v_ev_depois from evento_auditoria
   where acao = 'controlador_registrado' and entidade_ref = 'controlador:' || v_ctrl_a;
  perform teste_assert_0182(v_ev_depois->>'nome' = 'Karina Souto Damasio Tascino'
                             and v_ev_depois->>'documento' = '111.111.111-11',
    'o evento registra nome e documento', v_ev_depois::text);

  v_excecao := false;
  begin
    perform fn_controlador_registrar(v_caso, 'Karina (outro registro, mesmo CPF)',
                                      '111.111.111-11', 'fisica', 'analista@0182');
  exception when others then
    v_excecao := true;
  end;
  perform teste_assert_0182(v_excecao,
    'documento duplicado no MESMO caso é recusado (índice único) — duplicaria a contagem da soma');

  -- documento NULL repetido não colide: vários controladores sem documento informado.
  perform fn_controlador_registrar(v_caso, 'Sócio sem CPF no contrato (1)', null, 'fisica', 'analista@0182');
  perform fn_controlador_registrar(v_caso, 'Sócio sem CPF no contrato (2)', null, 'fisica', 'analista@0182');
  -- O assert era `true` literal, o que imprimia `ok` incondicionalmente: quem provava a
  -- afirmação eram os dois `fn_controlador_registrar` acima (que abortariam o bloco se o índice
  -- único cobrisse NULL), e o log não distinguia a prova do carimbo. Achado da revisão de
  -- 21/09/2026 — num arquivo cujo assunto é "ausência não é dado", um `ok` que sempre imprime é
  -- exatamente a coisa errada a deixar no log.
  select count(*) into v_ev_n from controlador
   where caso_id = v_caso and documento is null;
  perform teste_assert_0182(v_ev_n = 2,
    'dois controladores sem documento (NULL) no mesmo caso NÃO colidem entre si — os dois estão '
    'gravados', format('%s controlador(es) sem documento', v_ev_n));

  raise notice '--- 2. os checks de entidade_controlador recusam por UPDATE direto ---';
  v_ent_x := fn_upsert_entidade(v_caso, 'ENTIDADE DE TESTE DE CHECK LTDA. (0182)');
  v_ctrl_b := fn_controlador_registrar(v_caso, 'Sócio do check', '222.222.222-22', 'fisica', 'analista@0182');

  insert into entidade_controlador (caso_id, entidade_id, controlador_id, percentual)
  values (v_caso, v_ent_x, v_ctrl_b, 50) returning id into v_vinculo_id;

  v_excecao := false;
  begin
    update entidade_controlador set percentual = 150 where id = v_vinculo_id;
  exception when others then
    v_excecao := true;
  end;
  perform teste_assert_0182(v_excecao,
    'update direto com percentual=150 (fora de 0,100) levanta exceção');

  v_excecao := false;
  begin
    update entidade_controlador set percentual = 0 where id = v_vinculo_id;
  exception when others then
    v_excecao := true;
  end;
  perform teste_assert_0182(v_excecao,
    'update direto com percentual=0 (não é positivo) também levanta exceção');

  select percentual into v_percentual from entidade_controlador where id = v_vinculo_id;
  perform teste_assert_0182(v_percentual = 50,
    'e o percentual continua 50 — nenhum update inválido colou', v_percentual::text);

  raise notice '--- 3. A GUARDA DE SOMA: 45 + 35 = 80 aceito; um terceiro que levaria a 130 é recusado ---';
  v_soma_ent := fn_upsert_entidade(v_caso, 'ENTIDADE DA GUARDA DE SOMA LTDA. (0182)');
  v_soma_socio_a := fn_controlador_registrar(v_caso, 'Sócio A da guarda', '333.333.333-33', 'fisica', 'analista@0182');
  v_soma_socio_b := fn_controlador_registrar(v_caso, 'Sócio B da guarda', '444.444.444-44', 'fisica', 'analista@0182');
  v_soma_socio_c := fn_controlador_registrar(v_caso, 'Sócio C da guarda', '555.555.555-55', 'fisica', 'analista@0182');
  v_soma_socio_c_bis := fn_controlador_registrar(v_caso, 'Sócio C-bis (vínculo movido)', '121.121.121-12', 'fisica', 'analista@0182');

  perform fn_entidade_definir_controlador(v_soma_ent, v_soma_socio_a, 45, 'analista@0182');
  perform fn_entidade_definir_controlador(v_soma_ent, v_soma_socio_b, 35, 'analista@0182');

  select coalesce(sum(percentual), 0) into v_percentual
    from entidade_controlador where entidade_id = v_soma_ent;
  perform teste_assert_0182(v_percentual = 80,
    'dois sócios somando 80 (não 100) são aceitos — não exige soma completa',
    format('soma=%s', v_percentual));

  v_excecao := false;
  begin
    perform fn_entidade_definir_controlador(v_soma_ent, v_soma_socio_c, 50, 'analista@0182');
  exception when others then
    v_excecao := true;
  end;
  perform teste_assert_0182(v_excecao,
    'a terceira participação (que passaria de 100%) é recusada');

  select coalesce(sum(percentual), 0) into v_percentual
    from entidade_controlador where entidade_id = v_soma_ent;
  perform teste_assert_0182(v_percentual = 80,
    'e nada foi gravado — a soma continua em 80, não 130', format('soma=%s', v_percentual));

  perform teste_assert_0182(
    not exists(select 1 from entidade_controlador
                where entidade_id = v_soma_ent and controlador_id = v_soma_socio_c),
    'e o terceiro sócio nem aparece no vínculo');

  raise notice '--- 4. percentual NULL distinguível da ausência da linha ---';
  perform fn_entidade_definir_controlador(v_soma_ent, v_soma_socio_c, null, 'analista@0182');
  -- Corrige o estado acima só para este bloco: v_soma_socio_c agora É sócio conhecido de
  -- v_soma_ent, mas sem percentual medido (a guarda de soma não bloqueia NULL — 0 contribuição).

  select percentual into v_percentual
    from entidade_controlador where entidade_id = v_soma_ent and controlador_id = v_soma_socio_c;
  perform teste_assert_0182(v_percentual is null,
    'sócio conhecido sem percentual medido: a linha existe, percentual é NULL');

  select count(*) into v_ev_n from entidade_controlador
   where entidade_id = v_soma_ent and controlador_id = v_soma_socio_c;
  perform teste_assert_0182(v_ev_n = 1,
    'a linha do sócio conhecido-sem-percentual EXISTE (distinta de não existir)');

  -- uma pessoa NUNCA vinculada à entidade não aparece nem com percentual NULL nem de nenhuma forma
  perform teste_assert_0182(
    not exists(select 1 from entidade_controlador ec
                join controlador c on c.id = ec.controlador_id
                where ec.entidade_id = v_soma_ent and c.nome = 'Sócio sem CPF no contrato (1)'),
    'uma pessoa sem vínculo registrado não aparece na tabela — ausência de LINHA, não de percentual');

  raise notice '--- 5. O FECHO TRANSITIVO: A-B compartilham X; B-C compartilham Y (Y != X); D isolada ---';
  declare
    v_a uuid; v_b uuid; v_c uuid; v_d uuid; v_e_sem_controlador uuid;
    v_ctrl_x uuid; v_ctrl_y uuid; v_ctrl_isolado uuid;
  begin
    -- Nomes com tokens de 4+ caracteres BEM diferentes entre si de propósito: um token de UMA
    -- letra ("A", "C") colidiria com fn_mesma_entidade/fn_upsert_entidade (0168) — "C" é PREFIXO
    -- de "CONTROLADOR" e as cinco entidades se fundiriam numa só pelo casamento frouxo de nomes,
    -- medido ao escrever este teste (fn_upsert_entidade não é ingênuo: ele TENTA reconhecer
    -- nomes truncados, e "FECHO ENTIDADE C LTDA." casava com "FECHO ENTIDADE E SEM CONTROLADOR
    -- LTDA." pelo token "C"/"CONTROLADOR"). ALFA/BETA/GAMA/DELTA/EPSILON não colidem entre si.
    v_a := fn_upsert_entidade(v_caso, 'FECHO HOLDING ALFA LTDA. (0182)');
    v_b := fn_upsert_entidade(v_caso, 'FECHO HOLDING BETA LTDA. (0182)');
    v_c := fn_upsert_entidade(v_caso, 'FECHO HOLDING GAMA LTDA. (0182)');
    v_d := fn_upsert_entidade(v_caso, 'FECHO ISOLADA DELTA LTDA. (0182)');
    v_e_sem_controlador := fn_upsert_entidade(v_caso, 'FECHO SEMCONTROLE EPSILON LTDA. (0182)');

    v_ctrl_x := fn_controlador_registrar(v_caso, 'Controlador X (A e B)', '666.666.666-66', 'fisica', 'analista@0182');
    v_ctrl_y := fn_controlador_registrar(v_caso, 'Controlador Y (B e C)', '777.777.777-77', 'fisica', 'analista@0182');
    v_ctrl_isolado := fn_controlador_registrar(v_caso, 'Controlador isolado (só D)', '888.888.888-88', 'fisica', 'analista@0182');

    -- A e B compartilham X (A NUNCA compartilha controlador diretamente com C).
    perform fn_entidade_definir_controlador(v_a, v_ctrl_x, 60, 'analista@0182');
    perform fn_entidade_definir_controlador(v_b, v_ctrl_x, 40, 'analista@0182');
    -- B e C compartilham Y — é este segundo controlador, diferente de X, que só um FECHO
    -- transitivo reconhece como ligando A a C (via B).
    perform fn_entidade_definir_controlador(v_b, v_ctrl_y, 30, 'analista@0182');
    perform fn_entidade_definir_controlador(v_c, v_ctrl_y, 70, 'analista@0182');
    -- D tem controlador próprio, mas não compartilhado com ninguém — grupo de 1.
    perform fn_entidade_definir_controlador(v_d, v_ctrl_isolado, 100, 'analista@0182');

    select grupo_id into v_grupo_a from fn_grupo_por_controle_comum(v_caso) where entidade_id = v_a;
    select grupo_id into v_grupo_b from fn_grupo_por_controle_comum(v_caso) where entidade_id = v_b;
    select grupo_id into v_grupo_c from fn_grupo_por_controle_comum(v_caso) where entidade_id = v_c;
    select grupo_id into v_grupo_d from fn_grupo_por_controle_comum(v_caso) where entidade_id = v_d;

    perform teste_assert_0182(v_grupo_a = v_grupo_b,
      'A e B estão no mesmo grupo (compartilham X diretamente)');
    perform teste_assert_0182(v_grupo_b = v_grupo_c,
      'B e C estão no mesmo grupo (compartilham Y diretamente)');
    perform teste_assert_0182(v_grupo_a = v_grupo_c,
      'A e C (que só compartilham controlador via B, nunca diretamente) caem no MESMO grupo '
      '— é o FECHO TRANSITIVO, a medição real desta migration');
    perform teste_assert_0182(v_grupo_a <> v_grupo_d,
      'D (controlador isolado, não compartilhado) NÃO cai no grupo de A/B/C');

    select count(*) into v_grupo_n from fn_grupo_por_controle_comum(v_caso) where grupo_id = v_grupo_a;
    perform teste_assert_0182(v_grupo_n = 3,
      'o grupo de A/B/C tem exatamente 3 entidades, não 2 (não é um grupo por salto só)',
      format('%s entidade(s)', v_grupo_n));

    select razao_social into v_razao from fn_grupo_por_controle_comum(v_caso) where entidade_id = v_a;
    perform teste_assert_0182(v_razao = 'FECHO HOLDING ALFA LTDA. (0182)',
      'a razão social vem correta na saída — não é uma prova vazia que só olha ids', v_razao);

    perform teste_assert_0182(
      not exists(select 1 from fn_grupo_por_controle_comum(v_caso) g
                  where g.entidade_id = v_e_sem_controlador),
      'entidade sem controlador nenhum registrado (v_e_sem_controlador) não aparece na saída');
  end;

  raise notice '--- 6. reatribuir percentual de um vínculo já existente é permitido ---';
  v_reatrib_ent := fn_upsert_entidade(v_caso, 'REATRIBUIÇÃO ENTIDADE LTDA. (0182)');
  v_reatrib_ctrl := fn_controlador_registrar(v_caso, 'Sócio da reatribuição', '999.999.999-99', 'fisica', 'analista@0182');

  perform fn_entidade_definir_controlador(v_reatrib_ent, v_reatrib_ctrl, 30, 'analista@0182');
  perform fn_entidade_definir_controlador(v_reatrib_ent, v_reatrib_ctrl, 55, 'analista@0182');

  select count(*) into v_ev_n from entidade_controlador
   where entidade_id = v_reatrib_ent and controlador_id = v_reatrib_ctrl;
  perform teste_assert_0182(v_ev_n = 1,
    'ainda é UMA linha (upsert, não duplicou) — no máximo uma por (entidade, controlador)');

  select percentual into v_percentual from entidade_controlador
   where entidade_id = v_reatrib_ent and controlador_id = v_reatrib_ctrl;
  perform teste_assert_0182(v_percentual = 55,
    'e o percentual é o ESTADO ATUAL (55, o mais recente)', v_percentual::text);

  -- `order by criado_em desc` sozinho empata (as duas chamadas caem no mesmo timestamptz dentro
  -- da mesma transação — o mesmo empate que a 0179 já documentou para evento_auditoria); o
  -- percentual_novo=55 identifica sem ambiguidade QUAL dos dois eventos é o da reatribuição.
  select depois into v_ev_depois from evento_auditoria
   where acao = 'entidade_controlador_definido' and entidade_ref = 'entidade:' || v_reatrib_ent
     and depois->>'percentual_novo' = '55';
  perform teste_assert_0182(
    (v_ev_depois->>'percentual_novo')::numeric = 55
    and (v_ev_depois->>'percentual_anterior')::numeric = 30,
    'o evento da reatribuição registra o percentual novo (55) e o anterior (30) corretamente',
    v_ev_depois::text);

  raise notice '--- 7. controle: entidade/controlador inexistentes e controlador de OUTRO caso são recusados ---';
  v_excecao := false;
  begin
    perform fn_entidade_definir_controlador(gen_random_uuid(), v_ctrl_a, 10, 'analista@0182');
  exception when others then
    v_excecao := true;
  end;
  perform teste_assert_0182(v_excecao, 'entidade inexistente levanta exceção');

  v_excecao := false;
  begin
    perform fn_entidade_definir_controlador(v_ent_x, gen_random_uuid(), 10, 'analista@0182');
  exception when others then
    v_excecao := true;
  end;
  perform teste_assert_0182(v_excecao, 'controlador inexistente levanta exceção');

  v_ctrl_outro_caso := fn_controlador_registrar(v_outro_caso, 'Sócio de outro caso',
                                                 'aaa.aaa.aaa-aa', 'fisica', 'analista@0182');
  v_excecao := false;
  begin
    perform fn_entidade_definir_controlador(v_ent_x, v_ctrl_outro_caso, 10, 'analista@0182');
  exception when others then
    v_excecao := true;
  end;
  perform teste_assert_0182(v_excecao,
    'controlador que pertence a OUTRO caso levanta exceção');

  perform teste_assert_0182(
    not exists(select 1 from entidade_controlador
                where entidade_id = v_ent_x and controlador_id = v_ctrl_outro_caso),
    'e o vínculo entre casos não foi gravado');

  v_excecao := false;
  begin
    perform fn_controlador_registrar(v_caso, '  ', null, 'fisica', 'analista@0182');
  exception when others then
    v_excecao := true;
  end;
  perform teste_assert_0182(v_excecao,
    'nome em branco é recusado por fn_controlador_registrar');

  -- 8. A GUARDA DE SOMA TAMBÉM PRECISA COBRIR A MUDANÇA DE `entidade_id`, e não cobria.
  -- Achado da revisão independente (21/09/2026): o gatilho era `after insert or update OF
  -- percentual`, então mover um vínculo de uma entidade para outra por UPDATE direto não o
  -- disparava — a linha chegava inteira na entidade de destino sem que a soma de lá fosse
  -- reconferida. UPDATE direto não é arranjo inventado: o bloco 2 deste arquivo já cobra os
  -- checks por esse caminho, então ele está no modelo de ameaça declarado pelo próprio teste.
  -- v_soma_ent já tem 45 + 35 (+ o sócio C com percentual NULL, que não soma).
  v_perc_ent := fn_upsert_entidade(v_caso, 'ENTIDADE DE ORIGEM DO VINCULO MOVIDO (0182)');
  v_vinculo_id := fn_entidade_definir_controlador(v_perc_ent, v_soma_socio_c_bis, 60,
                                                   'analista@0182');

  v_excecao := false;
  begin
    update entidade_controlador set entidade_id = v_soma_ent where id = v_vinculo_id;
  exception when others then
    v_excecao := true;
  end;
  perform teste_assert_0182(v_excecao,
    'mover um vínculo de 60 para uma entidade que já soma 80 é recusado — a guarda de soma '
    'dispara na mudança de entidade_id, não só na de percentual');

  select coalesce(sum(percentual), 0) into v_percentual
    from entidade_controlador where entidade_id = v_soma_ent;
  perform teste_assert_0182(v_percentual = 80,
    'e a entidade de destino continua somando 80, não 140', format('soma=%s', v_percentual));

  raise notice 'CONTROLE COMUM OK — controlador e entidade_controlador gravados e auditados, a '
    'guarda de soma nunca deixa passar de 100 sem exigir soma completa, percentual NULL é '
    'distinguível da ausência da linha, o fecho transitivo une A/B/C por controladores '
    'diferentes (X e Y) sem confundir com D (isolada), reatribuir percentual é permitido, e '
    'entidade/controlador inexistentes e cross-caso são recusados';
end $$;
