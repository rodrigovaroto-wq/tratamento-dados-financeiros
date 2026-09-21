-- =============================================================================
-- 0183 — `entidade.forma_de_controle`: o que torna `controladora_id` VAZIO distinguível de um
--        NÃO PREENCHIDO, fatia 1.7b do plano F1 (FECHA a fatia 1.7)
--
-- MEDIÇÃO NÃO-VAZIA (regra 2 do CLAUDE.md) — EXECUTADA, não descrita, duas vezes:
--
-- (a) A GUARDA DE COERÊNCIA (`entidade_forma_de_controle_coerente`, check de linha única): com o
--     `check` comentado na migration 0183 e `teste_assert_0183` trocado temporariamente para não
--     abortar no primeiro assert (`raise notice` em vez de `raise exception`) e contar todos —
--     4 dos 22 asserts do arquivo reprovaram (MEDIDO 21/09/2026). Religado o `check`, os 22 passam.
--
-- (b) A GUARDA DO VÍNCULO (`fn_trg_entidade_forma_de_controle_tem_vinculo`, trigger): com a
--     criação de `trg_entidade_forma_de_controle_tem_vinculo` comentada na migration (a função
--     existe, nada a chama) e `teste_assert_0183` contando todos — 4 dos 22 (MEDIDO 21/09/2026),
--     asserts reprovaram. Religado o trigger, todos passam.
--
-- (Ambos os números acima são preenchidos ao RODAR o protocolo — não estimados. Ver o cabeçalho
-- da migration 0183 para os números medidos e os nomes exatos dos asserts que discriminam cada
-- regressão, e para os que NÃO discriminam nenhuma (invariantes genuínos, independentes).)
--
-- O QUE ESTE ARQUIVO MEDE:
--   1. fn_entidade_definir_forma_de_controle grava a forma e o evento_auditoria;
--   2. a GUARDA DE COERÊNCIA: controlada_por_entidade sem controladora_id é recusado;
--      controlada_por_entidade COM controladora_id é aceito; controle_comum COM controladora_id
--      é recusado (mutuamente exclusivos);
--   3. a GUARDA DO VÍNCULO: controle_comum sem NENHUM vínculo em entidade_controlador é
--      recusado; controle_comum com pelo menos um vínculo é aceito;
--   4. reatribuir a forma (mudar de indefinido para outra, ou entre as duas) é permitido — é o
--      ESTADO ATUAL, o evento_auditoria registra o valor anterior;
--   5. fn_entidade_definir_forma_de_controle resolve a pendência forma_de_controle_indefinida
--      quando a forma deixa de ser 'indefinido';
--   6. toda entidade nova (fn_upsert_entidade) nasce 'indefinido' e ganha a pendência
--      complementar, incondicional;
--   7. entidade inexistente é recusada com raise exception, sem gravar nada;
--   8. A ASSIMETRIA CENTRAL DA FATIA: uma entidade 'indefinido' com controladora_id NULL e uma
--      entidade 'controle_comum' com controladora_id NULL são estados DIFERENTES e
--      DISTINGUÍVEIS por consulta — é a prova de que a fatia 1.7 está de fato fechada.
-- =============================================================================

create or replace function teste_assert_0183(p_cond boolean, p_nome text, p_detalhe text default null)
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
  v_caso                uuid;
  v_ent_a                uuid;  -- controlada por entidade (mundo 0181)
  v_ent_b                uuid;  -- controladora de v_ent_a
  v_ent_c                uuid;  -- controle comum (mundo 0182)
  v_ent_ambos            uuid;  -- controladora_id E vínculo: o par que só o check recusa
  v_ent_d                uuid;  -- indefinido, controladora_id NULL — a metade da assimetria
  v_ctrl                 uuid;
  v_forma                entidade_forma_de_controle;
  v_forma_anterior       entidade_forma_de_controle;
  v_excecao              boolean;
  v_ev_n                 int;
  v_ev_depois            jsonb;
  v_pend_id              uuid;
  v_pend_estado          pendencia_estado;
  v_novo                 uuid;
  v_novo_forma           entidade_forma_de_controle;
  v_novo_pend_n          int;
begin
  v_caso := (fn_upsert_caso('0183 — forma de controle'))::uuid;

  raise notice '--- 1. fn_upsert_entidade cria toda entidade nova como indefinido, com pendência ---';
  v_ent_d := fn_upsert_entidade(v_caso, 'ENTIDADE INDEFINIDA LTDA. (0183)');

  select forma_de_controle into v_forma from entidade where id = v_ent_d;
  perform teste_assert_0183(v_forma = 'indefinido',
    'entidade recém-criada nasce com forma_de_controle = indefinido', v_forma::text);

  select id, estado into v_pend_id, v_pend_estado from pendencia
   where entidade_id = v_ent_d and tipo = 'forma_de_controle_indefinida'
   order by criada_em desc limit 1;
  perform teste_assert_0183(v_pend_id is not null and v_pend_estado = 'aberta',
    'a pendência forma_de_controle_indefinida nasce ABERTA para toda entidade nova');

  -- idempotência: criar de novo (upsert) não duplica a pendência.
  perform fn_upsert_entidade(v_caso, 'ENTIDADE INDEFINIDA LTDA. (0183)');
  select count(*) into v_novo_pend_n from pendencia
   where entidade_id = v_ent_d and tipo = 'forma_de_controle_indefinida';
  perform teste_assert_0183(v_novo_pend_n = 1,
    'a pendência é idempotente por motivo — não duplica em upsert repetido',
    format('%s pendência(s)', v_novo_pend_n));

  raise notice '--- 2. GUARDA DE COERÊNCIA: controlada_por_entidade exige controladora_id ---';
  v_ent_a := fn_upsert_entidade(v_caso, 'ENTIDADE CONTROLADA LTDA. (0183)');
  v_ent_b := fn_upsert_entidade(v_caso, 'ENTIDADE CONTROLADORA LTDA. (0183)');

  v_excecao := false;
  begin
    perform fn_entidade_definir_forma_de_controle(v_ent_a, 'controlada_por_entidade', 'analista@0183');
  exception when others then
    v_excecao := true;
  end;
  perform teste_assert_0183(v_excecao,
    'declarar controlada_por_entidade SEM controladora_id preenchido é recusado');

  select forma_de_controle into v_forma from entidade where id = v_ent_a;
  perform teste_assert_0183(v_forma = 'indefinido',
    'e nada foi gravado — a forma continua indefinido (o estado anterior)', v_forma::text);

  -- agora com controladora_id preenchido (0181), a mesma declaração é aceita.
  perform fn_entidade_definir_participacao(v_ent_a, v_ent_b, 70, 'analista@0183');
  perform fn_entidade_definir_forma_de_controle(v_ent_a, 'controlada_por_entidade', 'analista@0183');

  select forma_de_controle into v_forma from entidade where id = v_ent_a;
  perform teste_assert_0183(v_forma = 'controlada_por_entidade',
    'com controladora_id preenchido, controlada_por_entidade é ACEITO', v_forma::text);

  raise notice '--- 3. GUARDA DE COERÊNCIA: controle_comum é INCOMPATÍVEL com controladora_id preenchido ---';
  v_excecao := false;
  begin
    -- v_ent_a JÁ TEM controladora_id (v_ent_b) do passo acima — declarar controle_comum aqui
    -- afirmaria "não há controladora empresa" contradizendo o próprio dado.
    perform fn_entidade_definir_forma_de_controle(v_ent_a, 'controle_comum', 'analista@0183');
  exception when others then
    v_excecao := true;
  end;
  perform teste_assert_0183(v_excecao,
    'declarar controle_comum com controladora_id AINDA preenchido é recusado (mutuamente exclusivos)');

  select forma_de_controle into v_forma from entidade where id = v_ent_a;
  perform teste_assert_0183(v_forma = 'controlada_por_entidade',
    'e nada foi gravado — a forma continua controlada_por_entidade', v_forma::text);

  raise notice '--- 4. GUARDA DO VÍNCULO: controle_comum exige pelo menos 1 linha em entidade_controlador ---';
  v_ent_c := fn_upsert_entidade(v_caso, 'ENTIDADE CONTROLE COMUM LTDA. (0183)');

  v_excecao := false;
  begin
    perform fn_entidade_definir_forma_de_controle(v_ent_c, 'controle_comum', 'analista@0183');
  exception when others then
    v_excecao := true;
  end;
  perform teste_assert_0183(v_excecao,
    'declarar controle_comum SEM NENHUM vínculo em entidade_controlador é recusado');

  select forma_de_controle into v_forma from entidade where id = v_ent_c;
  perform teste_assert_0183(v_forma = 'indefinido',
    'e nada foi gravado — a forma continua indefinido', v_forma::text);

  -- registra o controlador e o vínculo (0182) — agora a declaração é possível.
  v_ctrl := fn_controlador_registrar(v_caso, 'Sócio do controle comum (0183)', '123.456.789-00',
                                      'fisica', 'analista@0183');
  perform fn_entidade_definir_controlador(v_ent_c, v_ctrl, 100, 'analista@0183');

  perform fn_entidade_definir_forma_de_controle(v_ent_c, 'controle_comum', 'analista@0183');
  select forma_de_controle into v_forma from entidade where id = v_ent_c;
  perform teste_assert_0183(v_forma = 'controle_comum',
    'com pelo menos um vínculo registrado, controle_comum é ACEITO', v_forma::text);

  select controladora_id is null into v_excecao from entidade where id = v_ent_c;
  perform teste_assert_0183(v_excecao,
    'e controladora_id CONTINUA null (controle_comum não afirma controladora empresa nenhuma)');

  raise notice '--- 5. evento_auditoria, reatribuição, resolução de pendência ---';
  select count(*) into v_ev_n from evento_auditoria
   where acao = 'entidade_forma_de_controle_definida' and entidade_ref = 'entidade:' || v_ent_c;
  perform teste_assert_0183(v_ev_n = 1, 'exatamente um evento_auditoria gravado para v_ent_c',
    format('%s evento(s)', v_ev_n));

  select depois into v_ev_depois from evento_auditoria
   where acao = 'entidade_forma_de_controle_definida' and entidade_ref = 'entidade:' || v_ent_c;
  perform teste_assert_0183(
    (v_ev_depois->>'forma_nova') = 'controle_comum' and (v_ev_depois->>'forma_anterior') = 'indefinido',
    'o evento registra a forma nova (controle_comum) e a anterior (indefinido)', v_ev_depois::text);

  select id, estado into v_pend_id, v_pend_estado from pendencia
   where entidade_id = v_ent_c and tipo = 'forma_de_controle_indefinida'
   order by criada_em desc limit 1;
  perform teste_assert_0183(v_pend_estado = 'resolvida',
    'a pendência forma_de_controle_indefinida de v_ent_c foi RESOLVIDA pela declaração',
    v_pend_estado::text);

  -- reatribuição: v_ent_c já é controle_comum; declarar de novo (mesma forma) continua permitido
  -- e não quebra nada — é o ESTADO ATUAL, não um registro append-only.
  perform fn_entidade_definir_forma_de_controle(v_ent_c, 'controle_comum', 'analista@0183');
  select count(*) into v_ev_n from evento_auditoria
   where acao = 'entidade_forma_de_controle_definida' and entidade_ref = 'entidade:' || v_ent_c;
  perform teste_assert_0183(v_ev_n = 2,
    'reatribuir com a MESMA forma grava um segundo evento (histórico completo em evento_auditoria)',
    format('%s evento(s)', v_ev_n));

  raise notice '--- 6. entidade inexistente é recusada, nada gravado ---';
  v_excecao := false;
  begin
    perform fn_entidade_definir_forma_de_controle(gen_random_uuid(), 'controle_comum', 'analista@0183');
  exception when others then
    v_excecao := true;
  end;
  perform teste_assert_0183(v_excecao, 'entidade inexistente levanta exceção');

  raise notice '--- 7. A ASSIMETRIA CENTRAL: indefinido/NULL x controle_comum/NULL são DISTINGUÍVEIS ---';
  -- v_ent_d ('indefinido', controladora_id NULL desde o passo 1) e v_ent_c ('controle_comum',
  -- controladora_id NULL desde o passo 4): as duas têm controladora_id NULL, e a fatia 1.7
  -- EXISTE para tornar essa dupla ambiguidade legível por consulta.
  select controladora_id is null into v_excecao from entidade where id = v_ent_d;
  perform teste_assert_0183(v_excecao, 'v_ent_d (indefinido) também tem controladora_id NULL');

  select forma_de_controle into v_forma from entidade where id = v_ent_d;
  select forma_de_controle into v_forma_anterior from entidade where id = v_ent_c;
  perform teste_assert_0183(v_forma = 'indefinido' and v_forma_anterior = 'controle_comum'
                             and v_forma <> v_forma_anterior,
    'MESMO com controladora_id NULL nas duas, forma_de_controle DISTINGUE v_ent_d (indefinido, '
    'ninguém decidiu) de v_ent_c (controle_comum, apurado e é horizontal) — é o critério de '
    'pronto da fatia 1.7, medido por consulta direta',
    format('v_ent_d=%s v_ent_c=%s', v_forma, v_forma_anterior));

  -- a mesma pergunta, numa única consulta que qualquer consumidor real faria:
  perform teste_assert_0183(
    (select count(distinct forma_de_controle) from entidade
      where id in (v_ent_c, v_ent_d) and controladora_id is null) = 2,
    'entre as entidades com controladora_id NULL, há PELO MENOS duas formas_de_controle '
    'diferentes — o vazio de controladora_id não é mais um valor único e ambíguo');

  -- O BURACO QUE A REVISÃO INDEPENDENTE ACHOU (21/09/2026), e que os 20 asserts anteriores NÃO
  -- discriminavam: apagar a cláusula `controle_comum ⇒ controladora_id IS NULL` do check deixava
  -- a suíte inteira verde. O único assert que exercitava esse par era o de v_ent_a, que tem
  -- controladora_id e NENHUM vínculo — ali quem recusa é o TRIGGER, não o check, então a
  -- cláusula podia sumir sem que nada acusasse.
  --
  -- O arranjo que FALTAVA é perfeitamente real: uma entidade com as DUAS coisas — controladora
  -- empresa registrada pela 0181 E vínculo de pessoa física registrado pela 0182 (holding no
  -- papel + sócios no contrato social). Sem esta cláusula, ela poderia ser declarada
  -- `controle_comum`: o trigger vê o vínculo e libera, e o banco passaria a afirmar "grupo
  -- horizontal, não há controladora empresa" numa linha que TEM controladora empresa preenchida.
  -- É ausência virando dado (regra 1) pelo caminho mais silencioso possível — o estado declarado
  -- contradizendo a coluna ao lado.
  v_ent_ambos := fn_upsert_entidade(v_caso, 'ENTIDADE COM CONTROLADORA *E* VINCULO (0183)');
  perform fn_entidade_definir_participacao(v_ent_ambos, v_ent_a, 60, 'analista@0183');
  perform fn_entidade_definir_controlador(v_ent_ambos, v_ctrl, 40, 'analista@0183');

  v_excecao := false;
  begin
    perform fn_entidade_definir_forma_de_controle(v_ent_ambos, 'controle_comum', 'analista@0183');
  exception when others then
    v_excecao := true;
  end;
  perform teste_assert_0183(v_excecao,
    'entidade que tem controladora_id E vínculo NÃO pode ser declarada controle_comum — o '
    'trigger sozinho a liberaria (há vínculo); quem a recusa é a cláusula do check');

  select forma_de_controle into v_forma from entidade where id = v_ent_ambos;
  perform teste_assert_0183(v_forma = 'indefinido',
    'e nada foi gravado — a forma continua indefinido', format('forma=%s', v_forma));

  raise notice 'FORMA DE CONTROLE OK — indefinido é o default honesto de toda entidade nova, a '
    'guarda de coerência recusa controlada_por_entidade sem controladora_id e controle_comum '
    'com controladora_id, a guarda do vínculo recusa controle_comum sem nenhum controlador '
    'registrado, reatribuir é permitido, a pendência nasce e resolve corretamente, e '
    'controladora_id NULO deixou de ser um valor único e ambíguo — indefinido e controle_comum '
    'são estados DIFERENTES e distinguíveis por consulta';
end $$;
