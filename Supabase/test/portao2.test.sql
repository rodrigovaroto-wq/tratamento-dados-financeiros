-- Testes do Portão 2 por caso (Supabase/migrations/0037).
-- Rodar via Supabase/test/run.sh (que aplica as migrations antes).
--
-- A regra vem de `Arquitetura do Sistema/2 Especificação/f0/04` e está APROVADA desde a F0 — teto de ressalvas em 3,
-- lista fechada de não-sobrepujáveis, três condições. O que faltava era código:
-- `caso_status` tinha 'aprovado' e nada transicionava para lá, e
-- `pendencia.sobrepujavel` era gravado desde a 0001 sem NENHUM leitor.
--
-- O que estes testes travam: as três condições valem separadamente, a recusa
-- explica por quê, ressalva expirada volta a bloquear, e nenhum autor tem
-- exceção — a regra é determinística.

\set ON_ERROR_STOP on

create or replace function teste_assert_p2(p_ok boolean, p_nome text, p_detalhe text default null)
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
  v_pend uuid;
  v_status text;
  v_n int;
begin
  raise notice '--- 1. caso limpo é elegível ---';
  v_caso := (fn_upsert_caso('Caso portão 2 limpo'))::uuid;
  v_r := fn_avaliar_portao2(v_caso);
  perform teste_assert_p2((v_r->>'elegivel')::boolean,
    'sem pendência nenhuma, o caso é elegível', v_r::text);
  -- O teto de 3 saiu na 0109 (decisão do dono). A avaliação DECLARA que não há
  -- teto em vez de publicar um número que não vale mais — um `3` fantasma na
  -- resposta faria a tela mostrar um limite que ninguém cobra.
  perform teste_assert_p2(v_r->>'teto_ressalvas' is null,
    'e não há teto de ressalvas — a 0109 o removeu, e a avaliação diz isso', v_r::text);

  raise notice '--- 2. bloqueante aberta impede (condição 1) ---';
  insert into pendencia (caso_id, origem_estagio, tipo, severidade, sobrepujavel, descricao)
    values (v_caso, 'completude', 'item_faltante', 'bloqueante', true, 'falta DRE')
    returning id into v_pend;
  v_r := fn_avaliar_portao2(v_caso);
  perform teste_assert_p2(not (v_r->>'elegivel')::boolean,
    'com bloqueante aberta, não é elegível', v_r::text);
  perform teste_assert_p2((v_r->'motivos')::text like '%BLOQUEANTE%',
    'e o motivo diz isso em texto, não só um booleano falso', v_r->>'motivos');

  raise notice '--- 3. pendência EM TRATAMENTO continua bloqueando ---';
  -- Arquitetura do Sistema/2 Especificação/f0/04 escreve "aberta/em_correção/reenviada": pendência sendo tratada é
  -- pendência não resolvida. Se só 'aberta' contasse, bastaria mover para
  -- "em correção interna" para o portão liberar — uma porta dos fundos.
  update pendencia set estado = 'em_correcao_interna' where id = v_pend;
  v_r := fn_avaliar_portao2(v_caso);
  perform teste_assert_p2(not (v_r->>'elegivel')::boolean,
    'mover para "em correção interna" NÃO libera o portão', v_r::text);
  update pendencia set estado = 'reenviada_ao_cliente' where id = v_pend;
  perform teste_assert_p2(not (fn_avaliar_portao2(v_caso)->>'elegivel')::boolean,
    'nem "reenviada ao cliente"');

  raise notice '--- 4. resolver libera ---';
  update pendencia set estado = 'resolvida', resolvida_em = now() where id = v_pend;
  perform teste_assert_p2((fn_avaliar_portao2(v_caso)->>'elegivel')::boolean,
    'resolvida a pendência, o caso volta a ser elegível');

  raise notice '--- 5. NÃO-SOBREPUJÁVEL: ressalva não libera (condição 3) ---';
  -- É o coração da lista fechada de Arquitetura do Sistema/2 Especificação/f0/04. O flag `sobrepujavel=false` existia
  -- desde a 0001 e ninguém o lia — então, na prática, "não-sobrepujável" era
  -- decoração. Aqui ele decide.
  insert into pendencia (caso_id, origem_estagio, tipo, severidade, sobrepujavel, descricao)
    values (v_caso, 'completude', 'item_sem_conteudo', 'bloqueante', false,
            'BALANCO recebido sem uma linha extraída')
    returning id into v_pend;
  v_r := fn_avaliar_portao2(v_caso);
  perform teste_assert_p2(not (v_r->>'elegivel')::boolean, 'não-sobrepujável bloqueia');
  perform teste_assert_p2((v_r->>'nao_sobrepujaveis_abertas')::int = 1,
    'e é contada separadamente das outras bloqueantes', v_r::text);

  -- ATÉ A 0108 a ressalva NÃO liberava a não-sobrepujável (a lista fechada de
  -- Arquitetura do Sistema/2 Especificação/f0/04). A 0109 mudou isso por decisão do dono: com um botão só e sem campo,
  -- "Prosseguir sem resolução" que não faz prosseguir seria um botão que mente.
  -- O que sobra no lugar do bloqueio é a CONTAGEM, travada logo abaixo.
  update pendencia set estado = 'aceita_com_ressalva' where id = v_pend;
  v_r := fn_avaliar_portao2(v_caso);
  perform teste_assert_p2((v_r->>'elegivel')::boolean,
    'decidida, a não-sobrepujável deixa de travar o caso (0109)', v_r::text);
  perform teste_assert_p2((v_r->>'ressalvas_ativas')::int = 1,
    '…e aparece contada, que é o controle que restou', v_r::text);

  update pendencia set estado = 'resolvida' where id = v_pend;

  raise notice '--- 6. SEM TETO: a quarta ressalva também passa (0109) ---';
  for v_n in 1..3 loop
    insert into pendencia (caso_id, origem_estagio, tipo, severidade, sobrepujavel, descricao,
                           estado, expira_em)
      values (v_caso, 'validacao_formal', 'periodo_incorreto', 'importante', true,
              format('ressalva %s', v_n), 'aceita_com_ressalva', now() + interval '30 days');
  end loop;
  v_r := fn_avaliar_portao2(v_caso);
  perform teste_assert_p2((v_r->>'ressalvas_ativas')::int = 3, 'três ressalvas ativas', v_r::text);
  perform teste_assert_p2((v_r->>'elegivel')::boolean,
    'três ressalvas não travam nada', v_r::text);

  insert into pendencia (caso_id, origem_estagio, tipo, severidade, sobrepujavel, descricao,
                         estado)
    values (v_caso, 'validacao_formal', 'periodo_incorreto', 'importante', true,
            'ressalva 4', 'aceita_com_ressalva');
  v_r := fn_avaliar_portao2(v_caso);
  perform teste_assert_p2((v_r->>'elegivel')::boolean,
    'a quarta ressalva NÃO bloqueia — o teto saiu na 0109', v_r::text);
  perform teste_assert_p2((v_r->>'ressalvas_ativas')::int = 4,
    'e as quatro aparecem contadas', v_r::text);

  raise notice '--- 7. a EXPIRAÇÃO saiu junto com o teto (0109) ---';
  -- Arquitetura do Sistema/2 Especificação/f0/04 mandava a ressalva vencer e a pendência reabrir. Sem data de
  -- expiração no formulário (a 0109 tirou o campo), não há o que vencer: a
  -- ressalva vale enquanto ninguém mudar de ideia. O contador continua no
  -- payload, sempre zero, para nenhum leitor antigo quebrar.
  delete from pendencia where caso_id = v_caso and descricao = 'ressalva 4';
  update pendencia set expira_em = now() - interval '1 day'
    where caso_id = v_caso and descricao = 'ressalva 1';
  v_r := fn_avaliar_portao2(v_caso);
  perform teste_assert_p2((v_r->>'ressalvas_expiradas')::int = 0,
    'data no passado não reabre mais nada', v_r::text);
  perform teste_assert_p2((v_r->>'elegivel')::boolean,
    'e o caso segue elegível', v_r::text);

  raise notice '--- 8. fn_aprovar_caso RECUSA o que a regra não permite ---';
  -- Com o teto fora, o que ainda RECUSA é a bloqueante sem decisão — que é a
  -- única condição que sobrou. Uma nova, aberta, põe o caso de volta no vermelho.
  insert into pendencia (caso_id, origem_estagio, tipo, severidade, sobrepujavel, descricao)
    values (v_caso, 'completude', 'item_faltante', 'bloqueante', true, 'falta o CONTRATO_SOCIAL');
  v_r := fn_aprovar_caso(v_caso, 'socio.senior@oria', 'preciso fechar hoje');
  perform teste_assert_p2((v_r->>'recusado') = 'true',
    'a aprovação é recusada, e o payload declara isso', v_r::text);
  perform teste_assert_p2((v_r->>'motivo_recusa') like '%NÃO é elegível%',
    'com o motivo em texto, para aparecer na tela', v_r->>'motivo_recusa');

  select status::text into v_status from caso where id = v_caso;
  perform teste_assert_p2(v_status <> 'aprovado',
    'e o caso NÃO mudou de status', coalesce(v_status, '(null)'));

  select count(*) into v_n from decisao
    where caso_id = v_caso and tipo = 'aprovacao' and payload->>'portao' = '2';
  perform teste_assert_p2(v_n = 0, 'nenhuma decisão de aprovação foi gravada',
    format('decisões: %s', v_n));

  perform teste_assert_p2(
    exists (select 1 from evento_auditoria
            where acao = 'aprovacao_recusada' and entidade_ref = 'caso:'||v_caso),
    'mas a TENTATIVA fica na trilha — recusar não é apagar o rastro');

  raise notice '--- 9. com a regra satisfeita, aprova e registra ---';
  update pendencia set estado = 'resolvida'
    where caso_id = v_caso and descricao = 'falta o CONTRATO_SOCIAL';
  v_r := fn_aprovar_caso(v_caso, 'socio.senior@oria', 'conferido contra o book');
  perform teste_assert_p2((v_r->>'aprovado') = 'true', 'agora aprova', v_r::text);

  select status::text into v_status from caso where id = v_caso;
  perform teste_assert_p2(v_status = 'aprovado', 'e o caso está aprovado', v_status);

  select count(*) into v_n from decisao
    where caso_id = v_caso and tipo = 'aprovacao' and payload->>'portao' = '2';
  perform teste_assert_p2(v_n = 1, 'com UMA decisão registrada', format('decisões: %s', v_n));

  raise notice '--- 10. aprovar de novo é no-op declarado ---';
  v_r := fn_aprovar_caso(v_caso, 'socio.senior@oria', 'clicou de novo');
  perform teste_assert_p2((v_r->>'ja_aprovado') = 'true',
    'o segundo clique não gera decisão nova', v_r::text);
  select count(*) into v_n from decisao
    where caso_id = v_caso and tipo = 'aprovacao' and payload->>'portao' = '2';
  perform teste_assert_p2(v_n = 1, 'a trilha continua com UMA aprovação',
    format('decisões: %s', v_n));

  raise notice 'TODOS OS TESTES DO PORTÃO 2 PASSARAM';
end $$;
