-- =============================================================================
-- 0179 — `papel_no_grupo` tipado E preenchido: o enum, a pendência que marca a
--        ausência (nunca decide) e o único caminho de escrita
--        (fn_entidade_definir_papel_no_grupo), fatia 1.3 do plano F1
--
-- MEDIÇÃO NÃO-VAZIA (regra 2 do CLAUDE.md), MEDIDA (não estimada — rodada de
-- fato contra um banco nas duas posições, com o `teste_assert_0179` trocado
-- temporariamente para não abortar no primeiro assert e contar todos):
-- com a chamada a `fn_pendencia_papel_no_grupo_indefinido` comentada dentro
-- de `fn_upsert_entidade` (estado equivalente ao vigente na 0178, antes
-- desta fatia) — **11 dos 21 asserts deste arquivo reprovaram**:
--   bloco 1 (5 de 6): "abriu pendência", "o motivo identifica a entidade",
--     "severidade complementar", "sobrepujável", "origem_estagio" — só "a
--     entidade nasce com papel NULL" passa sem a marca (é independente dela);
--   bloco 2 (3 de 7): "a pendência foi resolvida", "resolvida_em" e
--     "resolvida_por" reprovam porque não HÁ pendência para resolver (o
--     update de fn_entidade_definir_papel_no_grupo vira no-op); os 4 que
--     checam papel gravado/evento_auditoria passam — são de
--     fn_entidade_definir_papel_no_grupo, não da marca automática;
--   bloco 3 (1 de 3): "a reatribuição não reabriu nem duplicou a pendência"
--     reprova (0 em vez de 1 — não há pendência nenhuma para não duplicar);
--   bloco 4 (2 de 3): as duas checagens de "a entidade tem exatamente 1
--     pendência" (A e B) reprovam por 0 em vez de 1; a terceira (chamar
--     fn_pendencia_papel_no_grupo_indefinido DIRETO, sem depender da marca
--     automática, para a entidade B) continua passando — ela cria a
--     pendência por conta própria, então não mede a marca automática.
-- Os blocos 2/3 (fn_entidade_definir_papel_no_grupo em si) e o bloco 5
-- (entidade inexistente) são o controle: passam com ou sem a marca, porque
-- não dependem dela — a MEDIÇÃO real está nos 11 acima. Religada a chamada
-- (0179 como está), os 21 asserts deste arquivo passam.
--
-- UM SEGUNDO DEFEITO FOI ACHADO E CORRIGIDO NO PRÓPRIO TESTE durante esta
-- medição, antes de fechar o número acima: o bloco 3 comparava o SEGUNDO
-- evento_auditoria com `order by criado_em desc limit 1`, mas os dois
-- eventos deste arquivo nascem na MESMA transação (o `do` inteiro é uma
-- transação só) e `now()` é estável dentro dela — os dois `criado_em` são
-- IDÊNTICOS, e o `order by` empatava, escolhendo qualquer um dos dois. Esse
-- assert reprovava de forma ESPÚRIA (por um bug do teste, não do produto) em
-- ~50% das execuções, com ou sem a marca. Corrigido guardando o id do
-- PRIMEIRO evento (`v_ev_id_1`) e excluindo-o na segunda leitura, em vez de
-- reordenar por um timestamp empatado.
--
-- O QUE ESTE ARQUIVO MEDE:
--   1. entidade nova nasce com papel_no_grupo NULL e COM pendência
--      papel_no_grupo_indefinido aberta (complementar, sobrepujável,
--      origem_estagio = 'diagnostico') — a marca da ausência, não uma escolha;
--   2. fn_entidade_definir_papel_no_grupo grava o papel, resolve a pendência
--      (resolvida_por = o autor humano, não 'sistema:...') e grava
--      evento_auditoria com o papel novo e o anterior (null na primeira vez);
--   3. chamar de novo com papel DIFERENTE sobrescreve — é o estado ATUAL da
--      classificação, não um registro append-only (a decisão de produto que
--      a fatia 1.3 tomou: o histórico mora em evento_auditoria, a coluna
--      guarda o agora) — e não reabre nem duplica a pendência já resolvida;
--   4. idempotência: duas entidades sem papel no MESMO caso não colidem
--      motivo (cada uma com a sua própria pendência), e a mesma entidade
--      não duplica pendência ao ser marcada duas vezes;
--   5. entidade inexistente: fn_entidade_definir_papel_no_grupo recusa com
--      `raise exception`, nunca grava nada.
-- =============================================================================

create or replace function teste_assert_0179(p_cond boolean, p_nome text, p_detalhe text default null)
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
  v_caso        uuid;
  v_ent_a       uuid;
  v_ent_b       uuid;
  v_papel       entidade_papel_no_grupo;
  v_pend_id     uuid;
  v_pend_tipo   text;
  v_pend_sever  text;
  v_pend_sobre  boolean;
  v_pend_estagio text;
  v_pend_motivo text;
  v_pend_n      int;
  v_resolvida_em timestamptz;
  v_resolvida_por text;
  v_ev_n        int;
  v_ev_depois   jsonb;
  v_ev_id_1     uuid;
  v_excecao     boolean;
begin
  v_caso := (fn_upsert_caso('0179 — papel no grupo tipado e preenchido'))::uuid;

  raise notice '--- 1. entidade nova nasce sem papel e COM pendência papel_no_grupo_indefinido ---';
  v_ent_a := fn_upsert_entidade(v_caso, 'EIXO PARTICIPAÇÕES LTDA. (0179)');

  select papel_no_grupo into v_papel from entidade where id = v_ent_a;
  perform teste_assert_0179(v_papel is null,
    'a entidade nasce com papel_no_grupo NULL — nenhum sinal automático a classifica');

  select tipo::text, severidade::text, sobrepujavel, origem_estagio, motivo
    into v_pend_tipo, v_pend_sever, v_pend_sobre, v_pend_estagio, v_pend_motivo
  from pendencia
  where entidade_id = v_ent_a and motivo = 'papel_no_grupo_indefinido:' || v_ent_a
  order by criada_em desc limit 1;

  perform teste_assert_0179(v_pend_tipo = 'papel_no_grupo_indefinido',
    'abriu pendência do tipo papel_no_grupo_indefinido', coalesce(v_pend_tipo, '(nenhuma pendência)'));
  perform teste_assert_0179(v_pend_motivo = 'papel_no_grupo_indefinido:' || v_ent_a,
    'o motivo identifica a entidade, para dedupe');
  perform teste_assert_0179(v_pend_sever = 'complementar',
    'severidade complementar — ausência de classificação não é defeito, não bloqueia nada',
    coalesce(v_pend_sever, '(nula)'));
  perform teste_assert_0179(v_pend_sobre is true,
    'sobrepujável — não impede o caso de seguir');
  perform teste_assert_0179(v_pend_estagio = 'diagnostico',
    'origem_estagio = diagnostico, mesmo estágio de fn_upsert_entidade');

  raise notice '--- 2. fn_entidade_definir_papel_no_grupo grava o papel, resolve a pendência e audita ---';
  select id into v_pend_id from pendencia
   where entidade_id = v_ent_a and motivo = 'papel_no_grupo_indefinido:' || v_ent_a
   order by criada_em desc limit 1;

  perform fn_entidade_definir_papel_no_grupo(v_ent_a, 'operacional'::entidade_papel_no_grupo, 'analista@0179');

  select papel_no_grupo into v_papel from entidade where id = v_ent_a;
  perform teste_assert_0179(v_papel = 'operacional',
    'o papel foi gravado na entidade', coalesce(v_papel::text, '(nulo)'));

  select estado::text, resolvida_em, resolvida_por into v_pend_tipo, v_resolvida_em, v_resolvida_por
  from pendencia where id = v_pend_id;
  perform teste_assert_0179(v_pend_tipo = 'resolvida',
    'a pendência foi resolvida pela mesma chamada');
  perform teste_assert_0179(v_resolvida_em is not null,
    'resolvida_em foi preenchido');
  perform teste_assert_0179(v_resolvida_por = 'analista@0179',
    'resolvida_por é o AUTOR HUMANO que chamou a função, nunca ''sistema:...''',
    coalesce(v_resolvida_por, '(nulo)'));

  select count(*) into v_ev_n from evento_auditoria
   where acao = 'entidade_papel_no_grupo_definido' and entidade_ref = 'entidade:' || v_ent_a;
  perform teste_assert_0179(v_ev_n = 1, 'gravou evento_auditoria uma vez', format('%s evento(s)', v_ev_n));

  -- `criado_em` (default now()) é o MESMO valor em toda esta transação —
  -- este bloco `do` inteiro roda numa transação só, e `now()` é estável
  -- dentro dela. "order by criado_em desc" empataria entre os dois eventos
  -- do bloco 3 abaixo;
  -- por isso o id deste PRIMEIRO evento é guardado agora (aqui só existe um,
  -- sem ambiguidade) para o bloco 3 excluí-lo em vez de reordenar por empate.
  select id, depois into v_ev_id_1, v_ev_depois from evento_auditoria
   where acao = 'entidade_papel_no_grupo_definido' and entidade_ref = 'entidade:' || v_ent_a
   limit 1;
  perform teste_assert_0179((v_ev_depois->>'papel_novo') = 'operacional',
    'o evento registra o papel novo');
  perform teste_assert_0179(v_ev_depois->'papel_anterior' = 'null'::jsonb,
    'e o papel anterior — null na primeira definição', v_ev_depois->>'papel_anterior');

  raise notice '--- 3. reatribuição: papel DIFERENTE sobrescreve (é o estado ATUAL, não append-only) ---';
  perform fn_entidade_definir_papel_no_grupo(v_ent_a, 'holding'::entidade_papel_no_grupo, 'outro-analista@0179');

  select papel_no_grupo into v_papel from entidade where id = v_ent_a;
  perform teste_assert_0179(v_papel = 'holding',
    'a reatribuição sobrescreveu o papel — a coluna guarda o AGORA, não o histórico');

  select count(*) into v_pend_n from pendencia
   where entidade_id = v_ent_a and motivo = 'papel_no_grupo_indefinido:' || v_ent_a;
  perform teste_assert_0179(v_pend_n = 1,
    'a reatribuição não reabriu nem duplicou a pendência (já resolvida)',
    format('%s pendência(s)', v_pend_n));

  select depois into v_ev_depois from evento_auditoria
   where acao = 'entidade_papel_no_grupo_definido' and entidade_ref = 'entidade:' || v_ent_a
     and id <> v_ev_id_1
   limit 1;
  perform teste_assert_0179((v_ev_depois->>'papel_anterior') = 'operacional',
    'o SEGUNDO evento registra o papel anterior correto — o histórico mora aqui, não na coluna');

  raise notice '--- 4. idempotência: duas entidades sem papel no MESMO caso não colidem motivo ---';
  v_ent_b := fn_upsert_entidade(v_caso, 'EIXO VEÍCULO SPE LTDA. (0179)');

  select count(*) into v_pend_n from pendencia
   where entidade_id = v_ent_a and motivo = 'papel_no_grupo_indefinido:' || v_ent_a;
  perform teste_assert_0179(v_pend_n = 1,
    'a entidade A continua com exatamente UMA pendência (já resolvida, no bloco 2)',
    format('%s pendência(s)', v_pend_n));

  select count(*) into v_pend_n from pendencia
   where entidade_id = v_ent_b and motivo = 'papel_no_grupo_indefinido:' || v_ent_b;
  perform teste_assert_0179(v_pend_n = 1,
    'a entidade B ganhou a SUA PRÓPRIA pendência — motivos não colidem entre entidades',
    format('%s pendência(s)', v_pend_n));

  -- Chamar a função de pendência DIRETAMENTE de novo para a entidade B (o
  -- mesmo caminho que um segundo documento dela executaria via
  -- fn_upsert_entidade) não deve duplicar — mesmo desenho de
  -- fn_pendencia_cnpj_colide_balcao (0177) e fn_pendencia_entidade_ambigua (0153).
  perform fn_pendencia_papel_no_grupo_indefinido(v_caso, v_ent_b, 'EIXO VEÍCULO SPE LTDA. (0179)');

  select count(*) into v_pend_n from pendencia
   where entidade_id = v_ent_b and motivo = 'papel_no_grupo_indefinido:' || v_ent_b;
  perform teste_assert_0179(v_pend_n = 1,
    'chamar a pendência de novo para a MESMA entidade, sem resolver a anterior, não duplica',
    format('%s pendência(s)', v_pend_n));

  raise notice '--- 5. entidade inexistente: fn_entidade_definir_papel_no_grupo recusa, sem gravar nada ---';
  v_excecao := false;
  begin
    perform fn_entidade_definir_papel_no_grupo(
      '00000000-0000-0000-0000-000000000000'::uuid, 'holding'::entidade_papel_no_grupo, 'analista@0179');
  exception when others then
    v_excecao := true;
  end;
  perform teste_assert_0179(v_excecao,
    'entidade inexistente levanta exceção — a função não grava evento nem pendência às cegas');

  select count(*) into v_ev_n from evento_auditoria
   where acao = 'entidade_papel_no_grupo_definido'
     and entidade_ref = 'entidade:00000000-0000-0000-0000-000000000000';
  perform teste_assert_0179(v_ev_n = 0,
    'e nenhum evento_auditoria foi gravado para a entidade inexistente');

  raise notice 'PAPEL NO GRUPO OK — enum tipado, pendência complementar idempotente, escrita humana '
    'audita e resolve, reatribuição sobrescreve o estado atual sem apagar o histórico';
end $$;
