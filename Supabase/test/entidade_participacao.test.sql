-- =============================================================================
-- 0181 — `entidade.controladora_id` + `percentual_participacao`: a FK self-referencing,
--        os checks óbvios, a guarda contra CICLO e o único caminho de escrita
--        (fn_entidade_definir_participacao), fatia 1.5 do plano F1
--
-- MEDIÇÃO NÃO-VAZIA (regra 2 do CLAUDE.md), MEDIDA (não estimada — rodada de fato em duas
-- cópias do banco, com `teste_assert_0181` trocado temporariamente para não abortar no primeiro
-- assert e contar todos, e cada chamada arriscada isolada num `begin/exception` — sem isso a
-- exceção de ciclo NÃO tratada aborta o `do` inteiro, e "o script morreu" não é uma contagem):
-- com a chamada a `fn_entidade_criaria_ciclo_participacao` comentada dentro de
-- `fn_entidade_definir_participacao` (a função grava direto, sem perguntar) — **4 dos 29
-- asserts deste arquivo reprovaram**, os 4 que checam diretamente o efeito da guarda: "a
-- tentativa de ciclo de 2 níveis levanta exceção" e "nada foi gravado — A continua sem
-- controladora" (bloco 4), e "a tentativa de ciclo de 3 níveis levanta exceção" e "nada foi
-- gravado — A continua sem controladora (o topo da cadeia real)" (bloco 5) — sem a guarda, a
-- chamada arriscada não levanta exceção e A GANHA a controladora de verdade. OS OUTROS 25
-- PASSAM COM OU SEM A CORREÇÃO, e por razões diferentes — dito aqui para não parecerem falsos
-- positivos: os blocos 1/2/3/6/7/8 são controle genuíno, independentes da guarda (entrada
-- simples, checks de tabela por UPDATE direto, e a leitura de fn_entidade_cadeia_controladora
-- num caso sem ciclo nenhum). Os dois asserts restantes dos blocos 4/5 ("B continua controlada
-- por A" e "C continua controlada por B"/"B continua controlada por A") não discriminam esta
-- regressão por acidente de arranjo: sem a guarda, só o UPDATE de A muda (para B ou C), e B/C
-- nunca são tocados nos dois cenários — continuam corretos por não terem sido escritos, não
-- porque a guarda os protegeu. Religada a guarda (0181 como está), os 29 asserts passam.
--
-- O QUE ESTE ARQUIVO MEDE:
--   1. definir controladora com percentual válido grava as duas colunas e o evento_auditoria
--      (anterior = null na primeira vez);
--   2. os dois checks da tabela recusam mesmo por UPDATE direto, sem passar pela função:
--      percentual fora de (0,100] (150 e também 0, que não é positivo) e
--      controladora_id = a própria entidade;
--   3. `fn_entidade_definir_participacao` recusa controladora = a própria entidade (a guarda de
--      ciclo pega o caso trivial de 0 saltos, sem precisar de um check separado em PL/pgSQL —
--      mesma doutrina de reaproveitar uma regra em vez de duplicá-la que a 0180 já usava);
--   4. CICLO DE 2 NÍVEIS: A controla B; tentar tornar B controladora de A é recusado, e A
--      continua sem controladora (nada foi gravado) — é a MEDIÇÃO real desta migration;
--   5. CICLO DE 3 NÍVEIS: A controla B controla C; tentar tornar C controladora de A é
--      recusado, e nem A nem a cadeia B/C são alteradas;
--   6. `fn_entidade_cadeia_controladora` sobe a cadeia certa (holding → subholding → SPE, 2
--      níveis de ancestral) e para no topo: a holding não tem controladora, e a cadeia A PARTIR
--      DELA vem vazia;
--   7. remover a controladora (`p_controladora_id = null`) exige `p_percentual` também null —
--      recusado com percentual e aceito sem, e o evento registra o valor anterior corretamente;
--   8. controle: entidade inexistente e controladora de OUTRO caso são recusadas com
--      `raise exception`, sem gravar nada.
-- =============================================================================

create or replace function teste_assert_0181(p_cond boolean, p_nome text, p_detalhe text default null)
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
  v_caso           uuid;
  v_outro_caso     uuid;
  v_ent_x          uuid;
  v_ctrl_x         uuid;
  v_a2             uuid;
  v_b2             uuid;
  v_a3             uuid;
  v_b3             uuid;
  v_c3             uuid;
  v_holding        uuid;
  v_sub            uuid;
  v_spe            uuid;
  v_ent_outro_caso uuid;
  v_controladora_id       uuid;
  v_percentual            numeric;
  v_controladora_anterior uuid;
  v_ev_n           int;
  v_ev_depois      jsonb;
  v_n              int;
  v_excecao        boolean;
  v_cad_n          int;
  v_cad_1_id       uuid;
  v_cad_1_nivel    int;
  v_cad_2_id       uuid;
  v_cad_2_nivel    int;
begin
  v_caso := (fn_upsert_caso('0181 — participação societária'))::uuid;
  v_outro_caso := (fn_upsert_caso('0181 — outro caso (controle)'))::uuid;

  raise notice '--- 1. definir controladora com percentual válido ---';
  v_ent_x := fn_upsert_entidade(v_caso, 'PARTICIPAÇÃO CONTROLADA LTDA. (0181)');
  v_ctrl_x := fn_upsert_entidade(v_caso, 'PARTICIPAÇÃO CONTROLADORA LTDA. (0181)');

  perform fn_entidade_definir_participacao(v_ent_x, v_ctrl_x, 45.5, 'analista@0181');

  select controladora_id, percentual_participacao into v_controladora_id, v_percentual
    from entidade where id = v_ent_x;
  perform teste_assert_0181(v_controladora_id = v_ctrl_x and v_percentual = 45.5,
    'controladora_id e percentual_participacao gravados',
    format('controladora=%s percentual=%s', v_controladora_id, v_percentual));

  select count(*) into v_ev_n from evento_auditoria
   where acao = 'entidade_participacao_definida' and entidade_ref = 'entidade:' || v_ent_x;
  perform teste_assert_0181(v_ev_n = 1, 'o evento da PRIMEIRA definição foi gravado',
    format('%s evento(s)', v_ev_n));

  select depois into v_ev_depois from evento_auditoria
   where acao = 'entidade_participacao_definida' and entidade_ref = 'entidade:' || v_ent_x;
  perform teste_assert_0181(
    (v_ev_depois->>'controladora_id_novo')::uuid = v_ctrl_x
    and v_ev_depois->>'controladora_id_anterior' is null
    and (v_ev_depois->>'percentual_novo')::numeric = 45.5,
    'o evento registra controladora nova e percentual novo, e anterior NULL na primeira vez',
    v_ev_depois::text);

  raise notice '--- 2. os checks da tabela recusam mesmo por UPDATE direto, sem a função ---';
  v_excecao := false;
  begin
    update entidade set percentual_participacao = 150 where id = v_ent_x;
  exception when others then
    v_excecao := true;
  end;
  perform teste_assert_0181(v_excecao,
    'update direto com percentual=150 (fora de 0,100) levanta exceção');

  select percentual_participacao into v_percentual from entidade where id = v_ent_x;
  perform teste_assert_0181(v_percentual = 45.5,
    'e o percentual continua 45.5 — a transação do update inválido não deixou rastro',
    v_percentual::text);

  v_excecao := false;
  begin
    update entidade set percentual_participacao = 0 where id = v_ent_x;
  exception when others then
    v_excecao := true;
  end;
  perform teste_assert_0181(v_excecao,
    'update direto com percentual=0 (não é positivo) também levanta exceção');

  v_excecao := false;
  begin
    update entidade set controladora_id = id where id = v_ent_x;
  exception when others then
    v_excecao := true;
  end;
  perform teste_assert_0181(v_excecao,
    'update direto com controladora_id = a própria entidade levanta exceção');

  select controladora_id into v_controladora_id from entidade where id = v_ent_x;
  perform teste_assert_0181(v_controladora_id = v_ctrl_x,
    'e controladora_id continua sendo a controladora original — nenhum update inválido colou',
    v_controladora_id::text);

  raise notice '--- 3. fn_entidade_definir_participacao recusa controladora = a própria entidade ---';
  v_excecao := false;
  begin
    perform fn_entidade_definir_participacao(v_ent_x, v_ent_x, 10, 'analista@0181');
  exception when others then
    v_excecao := true;
  end;
  perform teste_assert_0181(v_excecao,
    'a função recusa entidade como controladora de si mesma (a guarda de ciclo pega o caso '
    'trivial de 0 saltos)');

  select controladora_id, percentual_participacao into v_controladora_id, v_percentual
    from entidade where id = v_ent_x;
  perform teste_assert_0181(v_controladora_id = v_ctrl_x and v_percentual = 45.5,
    'e nada mudou — a tentativa não alterou a participação existente');

  raise notice '--- 4. CICLO DE 2 NÍVEIS: A controla B; B não pode virar controladora de A ---';
  v_a2 := fn_upsert_entidade(v_caso, 'CICLO2 HOLDING A LTDA. (0181)');
  v_b2 := fn_upsert_entidade(v_caso, 'CICLO2 CONTROLADA B LTDA. (0181)');
  perform fn_entidade_definir_participacao(v_b2, v_a2, 60, 'analista@0181');

  v_excecao := false;
  begin
    perform fn_entidade_definir_participacao(v_a2, v_b2, 50, 'analista@0181');
  exception when others then
    v_excecao := true;
  end;
  perform teste_assert_0181(v_excecao,
    'a tentativa de ciclo de 2 níveis (B controladora de A, que já controla B) levanta exceção');

  select controladora_id into v_controladora_id from entidade where id = v_a2;
  perform teste_assert_0181(v_controladora_id is null,
    'nada foi gravado — A continua sem controladora',
    coalesce(v_controladora_id::text, 'NULL'));

  select controladora_id into v_controladora_id from entidade where id = v_b2;
  perform teste_assert_0181(v_controladora_id = v_a2,
    'e B continua controlada por A, sem alteração');

  raise notice '--- 5. CICLO DE 3 NÍVEIS: A controla B controla C; C não pode virar controladora de A ---';
  v_a3 := fn_upsert_entidade(v_caso, 'CICLO3 HOLDING A LTDA. (0181)');
  v_b3 := fn_upsert_entidade(v_caso, 'CICLO3 SUBHOLDING B LTDA. (0181)');
  v_c3 := fn_upsert_entidade(v_caso, 'CICLO3 SPE C LTDA. (0181)');
  perform fn_entidade_definir_participacao(v_b3, v_a3, 70, 'analista@0181');
  perform fn_entidade_definir_participacao(v_c3, v_b3, 80, 'analista@0181');

  v_excecao := false;
  begin
    perform fn_entidade_definir_participacao(v_a3, v_c3, 50, 'analista@0181');
  exception when others then
    v_excecao := true;
  end;
  perform teste_assert_0181(v_excecao,
    'a tentativa de ciclo de 3 níveis (C controladora de A, que controla B, que controla C) '
    'levanta exceção');

  select controladora_id into v_controladora_id from entidade where id = v_a3;
  perform teste_assert_0181(v_controladora_id is null,
    'nada foi gravado — A continua sem controladora (o topo da cadeia real)',
    coalesce(v_controladora_id::text, 'NULL'));

  select controladora_id into v_controladora_id from entidade where id = v_c3;
  perform teste_assert_0181(v_controladora_id = v_b3,
    'C continua controlada por B — a cadeia real (A→B→C) não foi tocada pela tentativa recusada');

  select controladora_id into v_controladora_id from entidade where id = v_b3;
  perform teste_assert_0181(v_controladora_id = v_a3,
    'e B continua controlada por A — nenhum nó da cadeia real ganhou controladora por engano');

  raise notice '--- 6. fn_entidade_cadeia_controladora sobe a cadeia certa e para no topo ---';
  v_holding := fn_upsert_entidade(v_caso, 'CADEIA HOLDING TOPO LTDA. (0181)');
  v_sub := fn_upsert_entidade(v_caso, 'CADEIA SUBHOLDING MEIO LTDA. (0181)');
  v_spe := fn_upsert_entidade(v_caso, 'CADEIA SPE PONTA LTDA. (0181)');
  perform fn_entidade_definir_participacao(v_sub, v_holding, 90, 'analista@0181');
  perform fn_entidade_definir_participacao(v_spe, v_sub, 65, 'analista@0181');

  select count(*) into v_cad_n from fn_entidade_cadeia_controladora(v_spe);
  perform teste_assert_0181(v_cad_n = 2,
    'a cadeia a partir da SPE tem exatamente 2 ancestrais (subholding e holding)',
    format('%s ancestral(is)', v_cad_n));

  select entidade_id, nivel into v_cad_1_id, v_cad_1_nivel
    from fn_entidade_cadeia_controladora(v_spe) where nivel = 1;
  perform teste_assert_0181(v_cad_1_id = v_sub,
    'nível 1 (controladora DIRETA da SPE) é a subholding', v_cad_1_id::text);

  select entidade_id, nivel into v_cad_2_id, v_cad_2_nivel
    from fn_entidade_cadeia_controladora(v_spe) where nivel = 2;
  perform teste_assert_0181(v_cad_2_id = v_holding,
    'nível 2 (a controladora da controladora) é a holding do topo', v_cad_2_id::text);

  select controladora_id into v_controladora_id from entidade where id = v_holding;
  perform teste_assert_0181(v_controladora_id is null,
    'a holding do topo não tem controladora — é onde a cadeia real termina');

  select count(*) into v_cad_n from fn_entidade_cadeia_controladora(v_holding);
  perform teste_assert_0181(v_cad_n = 0,
    'a cadeia A PARTIR da holding do topo vem vazia — não há ancestral nenhum',
    format('%s ancestral(is)', v_cad_n));

  raise notice '--- 7. remover controladora exige percentual também null ---';
  v_excecao := false;
  begin
    perform fn_entidade_definir_participacao(v_spe, null, 50, 'analista@0181');
  exception when others then
    v_excecao := true;
  end;
  perform teste_assert_0181(v_excecao,
    'remover a controladora (null) com percentual não-null é recusado — percentual sem '
    'controladora não significa nada');

  select controladora_id into v_controladora_id from entidade where id = v_spe;
  perform teste_assert_0181(v_controladora_id = v_sub,
    'e a SPE continua controlada pela subholding — a tentativa recusada não alterou nada');

  perform fn_entidade_definir_participacao(v_spe, null, null, 'analista@0181');
  select controladora_id, percentual_participacao into v_controladora_id, v_percentual
    from entidade where id = v_spe;
  perform teste_assert_0181(v_controladora_id is null and v_percentual is null,
    'remover a controladora com percentual TAMBÉM null é aceito — as duas colunas voltam a NULL');

  select depois into v_ev_depois from evento_auditoria
   where acao = 'entidade_participacao_definida' and entidade_ref = 'entidade:' || v_spe
   order by criado_em desc, ((depois->>'controladora_id_novo') is null) desc limit 1;
  perform teste_assert_0181(
    v_ev_depois->>'controladora_id_novo' is null
    and (v_ev_depois->>'controladora_id_anterior')::uuid = v_sub,
    'o evento da remoção registra controladora_id_novo NULL e a anterior (subholding) correta',
    v_ev_depois::text);

  raise notice '--- 8. controle: entidade inexistente e controladora de OUTRO caso são recusadas ---';
  v_excecao := false;
  begin
    perform fn_entidade_definir_participacao(gen_random_uuid(), v_ctrl_x, 10, 'analista@0181');
  exception when others then
    v_excecao := true;
  end;
  perform teste_assert_0181(v_excecao, 'entidade inexistente levanta exceção');

  v_ent_outro_caso := fn_upsert_entidade(v_outro_caso, 'ENTIDADE DE OUTRO CASO LTDA. (0181)');
  v_excecao := false;
  begin
    perform fn_entidade_definir_participacao(v_ent_x, v_ent_outro_caso, 10, 'analista@0181');
  exception when others then
    v_excecao := true;
  end;
  perform teste_assert_0181(v_excecao,
    'controladora que pertence a OUTRO caso levanta exceção');

  select controladora_id into v_controladora_id from entidade where id = v_ent_x;
  perform teste_assert_0181(v_controladora_id = v_ctrl_x,
    'e a controladora de v_ent_x continua a original — a tentativa entre casos não colou');

  raise notice 'PARTICIPAÇÃO SOCIETÁRIA OK — controladora_id/percentual gravados e auditados, os '
    'checks recusam percentual e auto-referência mesmo por update direto, ciclos de 2 e 3 '
    'níveis são recusados pela função sem gravar nada, fn_entidade_cadeia_controladora sobe a '
    'cadeia certa e para no topo, remover controladora exige percentual também null, e entidade '
    'inexistente/controladora de outro caso são recusadas';
end $$;
