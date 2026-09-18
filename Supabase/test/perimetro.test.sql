-- =============================================================================
-- 0180 — `perimetro(caso, entidade, escopo, desde, ate)`: quem entra no COMBINADO,
--        a troca de escopo no meio do mandato (fecha, não sobrescreve) e o
--        consumidor mínimo de leitura, fatia 1.4 do plano F1
--
-- MEDIÇÃO NÃO-VAZIA (regra 2 do CLAUDE.md), MEDIDA (não estimada — rodada de fato,
-- em duas cópias do banco, com `teste_assert_0180` trocado temporariamente para
-- não abortar no primeiro assert e contar todos, e a chamada arriscada isolada
-- num `begin/exception` — sem isso a colisão de índice único vira uma exceção
-- NÃO tratada que aborta o `do` inteiro, e "o script morreu" não é uma
-- contagem):
-- com o `update` que fecha o intervalo aberto anterior comentado dentro de
-- `fn_perimetro_definir_escopo` (a chamada que fecha `ate = p_desde - 1` antes de
-- inserir o novo intervalo) — **4 dos 17 asserts deste arquivo reprovaram**, os
-- 4 do BLOCO 2 que dependem diretamente do fechamento: "a troca de escopo não
-- levanta exceção" (sem o fechamento, o `insert` do segundo intervalo colide de
-- verdade com `perimetro_atual_unico`), "o intervalo anterior foi fechado em
-- 2024-12-31" (fica NULL — nunca fechou), "o novo intervalo abre com
-- desde=2025-01-01" (a linha nem chega a existir — o `insert` falhou) e "dois
-- registros no total para (caso, entidade A, escopo)" (fica em 1, não 2).
-- OS OUTROS 13 PASSAM COM OU SEM A CORREÇÃO, e por razões diferentes — dito
-- aqui para não parecerem falsos positivos: os 2 do bloco 1 e os 2 do bloco 4
-- (o `check` contra INSERT direto) são controle genuíno, independentes do
-- fechamento. Os 3 do bloco 3 e os 4 do bloco 5 MEDEM outra coisa (que duas
-- entidades não colidem, e que `fn_perimetro_vigente` lê `desde`/`ate`
-- corretamente) e por isso não discriminam ESTA regressão específica: sem o
-- fechamento, o intervalo velho da entidade A fica aberto para sempre
-- (`ate` nunca vira não-nulo), e o que esses blocos verificam — quantidade de
-- intervalos abertos, e se `fn_perimetro_vigente` acha a entidade certa numa
-- data — dá, por acidente, a mesma resposta que dá no mundo correto. A
-- MEDIÇÃO real desta correção está inteira no bloco 2, e é isso que os 4/17
-- provam.
-- Religado o fechamento (0180 como está), os 17 asserts deste arquivo passam.
--
-- O QUE ESTE ARQUIVO MEDE:
--   1. entidade entra no escopo com `desde` e sem `ate` (ainda vigente);
--   2. segunda chamada com nova `desde` fecha o intervalo anterior — o `ate`
--      do velho bate `nova_desde - 1` — e abre um novo, sem violar o índice
--      único (nunca dois "vigente" ao mesmo tempo para o mesmo
--      caso/entidade/escopo) nem apagar o registro antigo (o histórico fica
--      na TABELA, não só em evento_auditoria — ao contrário de
--      papel_no_grupo/0179, aqui não há coluna mutável para sobrescrever);
--   3. duas entidades diferentes no MESMO escopo não colidem — cada uma tem
--      seu próprio intervalo aberto ao mesmo tempo, e fechar o de uma não
--      toca a outra;
--   4. o `check perimetro_intervalo_valido` recusa `ate < desde` mesmo por
--      INSERT direto, sem passar pela função — não é regra só de PL/pgSQL;
--   5. `fn_perimetro_vigente` responde à pergunta "quem estava no escopo
--      NESTA DATA" corretamente antes de uma troca de escopo, depois da
--      troca (olhando para uma data ANTIGA, dentro do intervalo já fechado)
--      e antes de a entidade nunca ter entrado — as três respostas diferentes
--      é o que prova que a data importa, não só a existência da linha.
-- =============================================================================

create or replace function teste_assert_0180(p_cond boolean, p_nome text, p_detalhe text default null)
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
  v_ent_c       uuid;
  v_escopo      text := 'COMBINADO Grupo Perímetro (0180)';
  v_escopo_vig  text := 'COMBINADO Vigente (0180)';
  v_id_a1       uuid;
  v_id_a2       uuid;
  v_id_b1       uuid;
  v_id_c1       uuid;
  v_id_c2       uuid;
  v_desde       date;
  v_ate         date;
  v_n           int;
  v_ev_n        int;
  v_excecao     boolean;
begin
  v_caso := (fn_upsert_caso('0180 — perimetro do combinado'))::uuid;
  v_ent_a := fn_upsert_entidade(v_caso, 'PERÍMETRO HOLDING LTDA. (0180)');
  v_ent_b := fn_upsert_entidade(v_caso, 'PERÍMETRO OPERACIONAL LTDA. (0180)');

  raise notice '--- 1. entidade entra no escopo com desde e sem ate (ainda vigente) ---';
  v_id_a1 := fn_perimetro_definir_escopo(v_caso, v_ent_a, v_escopo, '2024-01-01'::date, 'analista@0180');

  select desde, ate into v_desde, v_ate from perimetro where id = v_id_a1;
  perform teste_assert_0180(v_desde = '2024-01-01'::date and v_ate is null,
    'a entidade entra no escopo com desde=2024-01-01 e ate NULL',
    format('desde=%s ate=%s', v_desde, coalesce(v_ate::text, 'NULL')));

  select count(*) into v_ev_n from evento_auditoria
   where acao = 'perimetro_escopo_definido' and entidade_ref = 'entidade:' || v_ent_a;
  perform teste_assert_0180(v_ev_n = 1,
    'o evento do PRIMEIRO perímetro foi gravado', format('%s evento(s)', v_ev_n));

  raise notice '--- 2. segunda chamada com nova desde fecha o intervalo anterior e abre outro ---';
  -- A chamada vai numa transação PRÓPRIA (begin/exception aqui dentro), não porque o produto
  -- precise disso — `fn_perimetro_definir_escopo` não é chamada assim em uso normal — mas porque
  -- SEM o fechamento do intervalo anterior (a correção desta migration) o `insert` colide de
  -- verdade com `perimetro_atual_unico` e levanta uma exceção de ÍNDICE ÚNICO do Postgres, que
  -- abortaria o `do` INTEIRO (e todo assert depois dele) em vez de deixar a MEDIÇÃO continuar.
  -- Isolar aqui é o que permite medir quantos dos asserts abaixo reprovam de fato, em vez de só
  -- "o script morreu".
  v_excecao := false;
  begin
    v_id_a2 := fn_perimetro_definir_escopo(v_caso, v_ent_a, v_escopo, '2025-01-01'::date, 'analista@0180');
  exception when others then
    v_excecao := true;
    v_id_a2 := null;
  end;
  perform teste_assert_0180(not v_excecao,
    'a troca de escopo não levanta exceção — o fechamento do intervalo anterior evita a colisão '
    'com o índice único perimetro_atual_unico');

  select ate into v_ate from perimetro where id = v_id_a1;
  perform teste_assert_0180(v_ate = '2024-12-31'::date,
    'o intervalo anterior foi fechado em 2024-12-31 (nova_desde - 1)',
    coalesce(v_ate::text, 'NULL'));

  select count(*) into v_n from perimetro where id = v_id_a1;
  perform teste_assert_0180(v_n = 1,
    'o intervalo anterior continua existindo (não foi apagado) — o histórico mora na tabela');

  select desde, ate into v_desde, v_ate from perimetro where id = v_id_a2;
  perform teste_assert_0180(v_desde = '2025-01-01'::date and v_ate is null,
    'o novo intervalo abre com desde=2025-01-01 e ate NULL',
    format('desde=%s ate=%s', v_desde, coalesce(v_ate::text, 'NULL')));

  select count(*) into v_n from perimetro
   where caso_id = v_caso and entidade_id = v_ent_a and escopo = v_escopo and ate is null;
  perform teste_assert_0180(v_n = 1,
    'só UM intervalo aberto para (caso, entidade A, escopo) — o índice único não colidiu',
    format('%s intervalo(s) aberto(s)', v_n));

  select count(*) into v_n from perimetro
   where caso_id = v_caso and entidade_id = v_ent_a and escopo = v_escopo;
  perform teste_assert_0180(v_n = 2,
    'dois registros no total para (caso, entidade A, escopo) — nada foi sobrescrito',
    format('%s registro(s)', v_n));

  raise notice '--- 3. duas entidades diferentes no MESMO escopo não colidem ---';
  v_id_b1 := fn_perimetro_definir_escopo(v_caso, v_ent_b, v_escopo, '2024-06-01'::date, 'analista@0180');

  select desde, ate into v_desde, v_ate from perimetro where id = v_id_b1;
  perform teste_assert_0180(v_desde = '2024-06-01'::date and v_ate is null,
    'a entidade B ganhou perímetro próprio, sem colidir com A',
    format('desde=%s ate=%s', v_desde, coalesce(v_ate::text, 'NULL')));

  select ate into v_ate from perimetro where id = v_id_a2;
  perform teste_assert_0180(v_ate is null,
    'o intervalo aberto da entidade A não foi tocado pela entrada da entidade B');

  select count(*) into v_n from perimetro
   where caso_id = v_caso and escopo = v_escopo and ate is null;
  perform teste_assert_0180(v_n = 2,
    'dois intervalos abertos simultâneos no MESMO escopo, um por entidade',
    format('%s intervalo(s) aberto(s)', v_n));

  raise notice '--- 4. o check perimetro_intervalo_valido recusa ate < desde por INSERT direto ---';
  v_excecao := false;
  begin
    insert into perimetro (caso_id, entidade_id, escopo, desde, ate)
    values (v_caso, v_ent_a, 'escopo-invalido-0180', '2024-06-01'::date, '2024-01-01'::date);
  exception when others then
    v_excecao := true;
  end;
  perform teste_assert_0180(v_excecao,
    'insert direto com ate < desde levanta exceção — o check protege mesmo sem a função');

  select count(*) into v_n from perimetro where escopo = 'escopo-invalido-0180';
  perform teste_assert_0180(v_n = 0,
    'e nada foi gravado — a transação do insert inválido não deixou rastro',
    format('%s linha(s)', v_n));

  raise notice '--- 5. fn_perimetro_vigente responde à data, não só à existência da linha ---';
  v_ent_c := fn_upsert_entidade(v_caso, 'PERÍMETRO VEÍCULO SPE LTDA. (0180)');
  v_id_c1 := fn_perimetro_definir_escopo(v_caso, v_ent_c, v_escopo_vig, '2024-01-01'::date, 'analista@0180');

  select count(*) into v_n from fn_perimetro_vigente(v_caso, v_escopo_vig, '2024-06-01'::date) e
   where e.id = v_ent_c;
  perform teste_assert_0180(v_n = 1,
    'ANTES da troca: fn_perimetro_vigente em 2024-06-01 encontra a entidade C');

  select count(*) into v_n from fn_perimetro_vigente(v_caso, v_escopo_vig, '2023-06-01'::date) e
   where e.id = v_ent_c;
  perform teste_assert_0180(v_n = 0,
    'ANTES de a entidade C ter entrado no escopo (2023-06-01): fn_perimetro_vigente não a acha');

  -- Mesmo isolamento do bloco 2, e pelo mesmo motivo: sem o fechamento, esta chamada colide com
  -- o índice único e abortaria o restante da medição.
  begin
    v_id_c2 := fn_perimetro_definir_escopo(v_caso, v_ent_c, v_escopo_vig, '2025-01-01'::date, 'analista@0180');
  exception when others then
    v_id_c2 := null;
  end;

  select count(*) into v_n from fn_perimetro_vigente(v_caso, v_escopo_vig, '2024-06-01'::date) e
   where e.id = v_ent_c;
  perform teste_assert_0180(v_n = 1,
    'DEPOIS da troca: consultando a DATA ANTIGA (2024-06-01, dentro do intervalo já fechado) '
    'ainda acha a entidade C — o perímetro do exercício anterior não mudou de resposta');

  select count(*) into v_n from fn_perimetro_vigente(v_caso, v_escopo_vig) e
   where e.id = v_ent_c;
  perform teste_assert_0180(v_n = 1,
    'DEPOIS da troca: sem data (default current_date), a entidade C ainda está vigente no novo intervalo');

  raise notice 'PERÍMETRO OK — entra com desde/sem ate, a troca de escopo FECHA o intervalo anterior '
    'sem apagar nem colidir, duas entidades no mesmo escopo não se atrapalham, o check recusa '
    'ate < desde mesmo por insert direto, e fn_perimetro_vigente responde à data certa antes e '
    'depois da troca';
end $$;
