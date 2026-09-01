-- Testes dos TRÊS BOTÕES da pendência (Supabase/migrations/0109).
-- Rodar via Supabase/test/run.sh (que aplica as migrations antes).
--
-- A 0109 trocou três funções com formulário (motivo obrigatório, data de
-- expiração, papel sênior, teto de 3) por UMA função de um clique. O que estes
-- testes travam é o que sobrou de garantia depois dessa troca — porque o que
-- sobrou é pouco, e pouco que funciona vale mais que muito que ninguém confere:
--
--   • os três botões levam aos três estados de `Arquitetura do Sistema/2 Especificação/f0/04`, e "contatar o cliente"
--     NÃO libera o portão (o documento ainda não chegou);
--   • decidir de novo o mesmo é no-op — dois cliques não viram duas decisões;
--   • `resolvida` é do SISTEMA e nenhum clique a reescreve;
--   • nada é apagado: a linha fica, com autor e instante;
--   • e TUDO É CONTADO — a avaliação publica ressalvadas e improcedentes,
--     inclusive as da lista fechada. É a última defesa que restou: o Portão 2
--     não impede mais, mas informa sobre o que se passou por cima.

\set ON_ERROR_STOP on

create or replace function teste_assert_dec(p_ok boolean, p_nome text, p_detalhe text default null)
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
  v_aval   jsonb;
  v_pend   uuid;
  v_ns     uuid;
  v_estado text;
  v_txt    text;
  v_n      int;
begin
  raise notice '--- 1. CONTATAR O CLIENTE registra e NÃO libera o portão ---';
  v_caso := (fn_upsert_caso('Caso três botões'))::uuid;
  insert into pendencia (caso_id, origem_estagio, tipo, severidade, sobrepujavel, descricao)
    values (v_caso, 'completude', 'item_faltante', 'bloqueante', true, 'falta o MUTUOS')
    returning id into v_pend;

  v_r := fn_decidir_pendencia(v_pend, 'analista@oria', 'contatar_cliente');
  perform teste_assert_dec((v_r->>'decidida') = 'true', 'o clique é aceito sem motivo nenhum', v_r::text);
  perform teste_assert_dec((v_r->>'rotulo') = 'Contatar o Cliente',
    'e devolve o rótulo que a tela mostra', v_r->>'rotulo');
  select estado::text into v_estado from pendencia where id = v_pend;
  perform teste_assert_dec(v_estado = 'reenviada_ao_cliente', 'no estado de Arquitetura do Sistema/2 Especificação/f0/04', v_estado);
  perform teste_assert_dec(not (v_r->'avaliacao'->>'elegivel')::boolean,
    'e o portão CONTINUA fechado — pedir o documento não é tê-lo recebido', v_r::text);

  -- Pedir o documento não é decisão sobre o mérito: não vira `decisao`.
  select count(*) into v_n from decisao where caso_id = v_caso;
  perform teste_assert_dec(v_n = 0, 'contatar o cliente não grava decisão', format('%s', v_n));
  perform teste_assert_dec(
    exists (select 1 from evento_auditoria
            where acao = 'pendencia_decidida' and entidade_ref = 'pendencia:'||v_pend),
    'mas fica na trilha, com quem clicou');

  raise notice '--- 2. PROSSEGUIR SEM RESOLUÇÃO libera, e fica contado ---';
  v_r := fn_decidir_pendencia(v_pend, 'analista@oria', 'prosseguir');
  perform teste_assert_dec((v_r->'avaliacao'->>'elegivel')::boolean,
    'prosseguir libera o portão na mesma chamada', v_r::text);
  perform teste_assert_dec((v_r->'avaliacao'->>'ressalvas_ativas')::int = 1,
    'e a avaliação já conta a ressalva', v_r::text);
  select count(*) into v_n from decisao where caso_id = v_caso and tipo = 'ressalva';
  perform teste_assert_dec(v_n = 1, 'com UMA decisão de ressalva na trilha', format('%s', v_n));
  select resolvida_por into v_txt from pendencia where id = v_pend;
  perform teste_assert_dec(v_txt = 'analista@oria',
    'e o autor gravado — a trilha responde QUEM, mesmo sem o porquê', coalesce(v_txt, '(null)'));

  raise notice '--- 3. SEM TETO: a quarta, a quinta e a sexta ressalva passam ---';
  -- O teto de 3 de Arquitetura do Sistema/2 Especificação/f0/04 saiu por decisão do dono. Este assert existe para o dia
  -- em que alguém reintroduzir um limite sem perceber: seis ressalvas não podem
  -- fechar o portão.
  for v_n in 1..5 loop
    insert into pendencia (caso_id, origem_estagio, tipo, severidade, sobrepujavel, descricao)
      values (v_caso, 'validacao_formal', 'periodo_incorreto', 'bloqueante', true,
              format('ressalva %s', v_n))
      returning id into v_ns;
    perform fn_decidir_pendencia(v_ns, 'analista@oria', 'prosseguir');
  end loop;
  v_aval := fn_avaliar_portao2(v_caso);
  perform teste_assert_dec((v_aval->>'ressalvas_ativas')::int = 6, 'seis ressalvas ativas', v_aval::text);
  perform teste_assert_dec((v_aval->>'elegivel')::boolean,
    'e o caso continua elegível — não há mais teto', v_aval::text);
  perform teste_assert_dec(v_aval->>'teto_ressalvas' is null,
    'a avaliação declara que não há teto, em vez de publicar um número que não existe',
    v_aval::text);

  raise notice '--- 4. PENDÊNCIA NÃO PROCEDE, inclusive na lista fechada ---';
  -- A não-sobrepujável de Arquitetura do Sistema/2 Especificação/f0/04 deixou de bloquear quando o humano decide. Com
  -- um botão só, "prosseguir" que não faz prosseguir seria um botão que mente.
  insert into pendencia (caso_id, origem_estagio, tipo, severidade, sobrepujavel, descricao)
    values (v_caso, 'completude', 'item_sem_conteudo', 'bloqueante', false,
            'BALANCO recebido sem uma linha extraída')
    returning id into v_ns;
  perform teste_assert_dec(not (fn_avaliar_portao2(v_caso)->>'elegivel')::boolean,
    'antes de decidir, ela trava o caso');

  v_r := fn_decidir_pendencia(v_ns, 'analista@oria', 'nao_procede');
  perform teste_assert_dec((v_r->'avaliacao'->>'elegivel')::boolean,
    'declarada improcedente, libera — mesmo sendo da lista fechada', v_r::text);
  v_aval := fn_avaliar_portao2(v_caso);
  perform teste_assert_dec((v_aval->>'rejeitadas')::int = 1
    and (v_aval->>'rejeitadas_nao_sobrepujaveis')::int = 1,
    'e a contagem diz separadamente que uma era da lista fechada — é o que sobrou de controle',
    v_aval::text);

  -- Nada é apagado: a linha continua, com estado e autor.
  select estado::text into v_estado from pendencia where id = v_ns;
  perform teste_assert_dec(v_estado = 'rejeitada', 'a pendência continua na tabela', v_estado);

  raise notice '--- 5. a aprovação CARREGA a contagem ---';
  v_r := fn_aprovar_caso(v_caso, 'socio@oria', 'conferido');
  perform teste_assert_dec((v_r->>'aprovado') = 'true', 'o caso aprova', v_r::text);
  select payload->'avaliacao'->>'ressalvas_ativas' into v_txt from decisao
    where caso_id = v_caso and tipo = 'aprovacao';
  perform teste_assert_dec(v_txt = '6',
    'e a decisão de aprovação guarda, para sempre, sobre quantas ressalvas ela passou',
    coalesce(v_txt, '(ausente)'));

  raise notice '--- 6. clicar de novo é no-op, e resolvida não se reescreve ---';
  v_r := fn_decidir_pendencia(v_ns, 'analista@oria', 'nao_procede');
  perform teste_assert_dec((v_r->>'sem_mudanca') = 'true',
    'o segundo clique no mesmo botão não gera decisão nova', v_r::text);
  select count(*) into v_n from decisao where payload->>'pendencia_id' = v_ns::text;
  perform teste_assert_dec(v_n = 1, 'a trilha continua com UMA', format('%s', v_n));

  update pendencia set estado = 'resolvida' where id = v_ns;
  v_r := fn_decidir_pendencia(v_ns, 'analista@oria', 'prosseguir');
  perform teste_assert_dec((v_r->>'recusado') = 'true',
    'o que o SISTEMA resolveu não se decide por clique', v_r::text);

  raise notice '--- 7. decisão desconhecida é recusada com as três opções ---';
  v_r := fn_decidir_pendencia(v_pend, 'analista@oria', 'ignorar');
  perform teste_assert_dec((v_r->>'recusado') = 'true', 'palavra fora das três é recusada', v_r::text);
  perform teste_assert_dec((v_r->>'motivo_recusa') like '%contatar_cliente%',
    'e a recusa lista quais são', v_r->>'motivo_recusa');

  raise notice '--- 8. as funções antigas SAÍRAM (uma decisão, uma porta) ---';
  -- Duas portas para a mesma decisão com regras diferentes é o que produz caso
  -- cujo estado ninguém explica seis meses depois.
  perform teste_assert_dec(
    not exists (select 1 from pg_proc where proname in
      ('fn_rejeitar_pendencia', 'fn_ressalvar_pendencia', 'fn_tratar_pendencia')),
    'nenhuma das três funções da 0106/0107 sobreviveu à 0109');

  raise notice 'TODOS OS TESTES DOS TRÊS BOTÕES PASSARAM';
end $$;
