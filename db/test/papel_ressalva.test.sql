-- Testes de papel, ressalva e estados de tratamento (db/migrations/0107).
-- Rodar via db/test/run.sh (que aplica as migrations antes).
--
-- O que estes testes travam:
--
--   • o default do papel é o MENOR privilégio — num banco novo ninguém ressalva.
--     Religar isso (default 'senior') abre o controle inteiro em silêncio;
--   • a ressalva exige as quatro coisas de f0/04 (sênior, motivo, expiração
--     futura, teto) e RECUSA a lista fechada — aceitar ali deixaria o humano
--     achando que resolveu enquanto o caso segue travado;
--   • a ressalva criada aqui é contada pela MESMA regra da 0037, inclusive
--     quando vence: as duas funções não podem discordar sobre o que é uma
--     ressalva ativa;
--   • tratamento não libera portão — é o que separa "estou cuidando" de
--     "resolvi", e a diferença é o que impede um caso de ser aprovado porque
--     alguém mexeu no estado;
--   • rejeitar não-sobrepujável passou a exigir sênior (aperto da 0107 sobre a
--     0106), e a rejeição comum continua aberta.

\set ON_ERROR_STOP on

create or replace function teste_assert_pr(p_ok boolean, p_nome text, p_detalhe text default null)
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
  v_pend   uuid;
  v_ns     uuid;
  v_estado text;
  v_n      int;
begin
  raise notice '--- 1. o papel nasce no MENOR privilégio ---';
  perform teste_assert_pr(fn_papel('ninguem@oria') = 'analista',
    'e-mail não cadastrado é analista, não sênior', fn_papel('ninguem@oria'));
  insert into usuario_papel (email, papel, criado_por) values ('socio@oria', 'senior', 'teste');
  perform teste_assert_pr(fn_papel('socio@oria') = 'senior', 'cadastrado como sênior, é sênior');
  perform teste_assert_pr(fn_papel('  SOCIO@ORIA ') = 'senior',
    'e o casamento ignora caixa e espaço — senão o mesmo e-mail digitado diferente perde o papel',
    fn_papel('  SOCIO@ORIA '));

  raise notice '--- 2. ressalva: as quatro exigências de f0/04 ---';
  v_caso := (fn_upsert_caso('Caso ressalva'))::uuid;
  insert into pendencia (caso_id, origem_estagio, tipo, severidade, sobrepujavel, descricao)
    values (v_caso, 'validacao_formal', 'periodo_incorreto', 'importante', true,
            'Balancete de novembro no lugar do de dezembro')
    returning id into v_pend;

  v_r := fn_ressalvar_pendencia(v_pend, 'analista@oria',
    'Cliente confirmou por e-mail que o de dezembro não fecha a tempo.', now() + interval '30 days');
  perform teste_assert_pr((v_r->>'recusado') = 'true', 'ANALISTA não ressalva', v_r::text);
  perform teste_assert_pr((v_r->>'motivo_recusa') like '%SÊNIOR%',
    'e a recusa diz o que falta, não só que falhou', v_r->>'motivo_recusa');

  v_r := fn_ressalvar_pendencia(v_pend, 'socio@oria', 'ok', now() + interval '30 days');
  perform teste_assert_pr((v_r->>'recusado') = 'true', 'sênior com motivo de duas letras: recusado');

  v_r := fn_ressalvar_pendencia(v_pend, 'socio@oria',
    'Cliente confirmou por e-mail que o de dezembro não fecha a tempo.', null);
  perform teste_assert_pr((v_r->>'recusado') = 'true',
    'sem data de expiração: recusado — ressalva permanente é liberação com outro nome');

  v_r := fn_ressalvar_pendencia(v_pend, 'socio@oria',
    'Cliente confirmou por e-mail que o de dezembro não fecha a tempo.', now() - interval '1 day');
  perform teste_assert_pr((v_r->>'recusado') = 'true',
    'expiração no passado: recusada — nasceria vencida e bloquearia no mesmo instante');

  select estado::text into v_estado from pendencia where id = v_pend;
  perform teste_assert_pr(v_estado = 'aberta',
    'e depois das quatro recusas a pendência continua ABERTA', v_estado);

  raise notice '--- 3. …com tudo em ordem, ressalva e o portão passa a contá-la ---';
  v_r := fn_ressalvar_pendencia(v_pend, 'socio@oria',
    'Cliente confirmou por e-mail que o de dezembro não fecha a tempo.', now() + interval '30 days');
  perform teste_assert_pr((v_r->>'ressalvada') = 'true', 'a ressalva é aceita', v_r::text);
  perform teste_assert_pr((v_r->'avaliacao'->>'ressalvas_ativas')::int = 1,
    'e a MESMA função que decide o Portão 2 já a conta', v_r::text);
  select count(*) into v_n from decisao where caso_id = v_caso and tipo = 'ressalva';
  perform teste_assert_pr(v_n = 1, 'com uma decisão de ressalva na trilha', format('%s', v_n));

  -- Ressalva vencida volta a bloquear (0037), e é a mesma linha que a 0107 criou:
  -- as duas funções não podem discordar sobre o que é ressalva ativa.
  update pendencia set expira_em = now() - interval '1 day' where id = v_pend;
  perform teste_assert_pr((fn_avaliar_portao2(v_caso)->>'ressalvas_expiradas')::int = 1,
    'vencida, ela volta a contar como pendência — sem job nenhum');
  update pendencia set expira_em = now() + interval '30 days' where id = v_pend;

  raise notice '--- 4. a lista fechada NÃO se ressalva ---';
  insert into pendencia (caso_id, origem_estagio, tipo, severidade, sobrepujavel, descricao)
    values (v_caso, 'completude', 'item_sem_conteudo', 'bloqueante', false,
            'BALANCO recebido sem uma linha extraída')
    returning id into v_ns;
  v_r := fn_ressalvar_pendencia(v_ns, 'socio@oria',
    'Assumo o risco: o balanço veio dentro do PDF combinado.', now() + interval '30 days');
  perform teste_assert_pr((v_r->>'recusado') = 'true',
    'nem para sênior: a lista fechada de f0/04 não aceita ressalva', v_r::text);
  -- E o motivo é o que evita o pior dos dois mundos: aceitar e o caso seguir travado.
  perform teste_assert_pr((v_r->>'motivo_recusa') like '%travado%',
    'e a recusa explica que aceitar deixaria o caso travado do mesmo jeito',
    v_r->>'motivo_recusa');

  raise notice '--- 5. rejeitar a lista fechada agora exige SÊNIOR (aperto sobre a 0106) ---';
  v_r := fn_rejeitar_pendencia(v_ns, 'analista@oria',
    'O balanço veio dentro do PDF combinado do mesmo lote, com as linhas todas.');
  perform teste_assert_pr((v_r->>'recusado') = 'true',
    'analista não declara improcedente uma não-sobrepujável', v_r::text);
  v_r := fn_rejeitar_pendencia(v_ns, 'socio@oria',
    'O balanço veio dentro do PDF combinado do mesmo lote, com as linhas todas.');
  perform teste_assert_pr((v_r->>'rejeitada') = 'true', 'o sênior declara', v_r::text);
  select payload->>'papel_do_autor' into v_estado from decisao
    where caso_id = v_caso and payload->>'pendencia_id' = v_ns::text;
  perform teste_assert_pr(v_estado = 'senior',
    'e a decisão guarda o PAPEL de quem decidiu, não só o e-mail', coalesce(v_estado, '(null)'));

  -- A rejeição COMUM continua aberta: o aperto é só sobre a lista fechada.
  insert into pendencia (caso_id, origem_estagio, tipo, severidade, sobrepujavel, descricao)
    values (v_caso, 'reconciliacao', 'divergencia_reconciliacao', 'importante', true, 'ruído')
    returning id into v_pend;
  v_r := fn_rejeitar_pendencia(v_pend, 'analista@oria',
    'Os dois rótulos são a mesma conta transposta; o documento fecha.');
  perform teste_assert_pr((v_r->>'rejeitada') = 'true',
    'analista continua podendo rejeitar pendência comum', v_r::text);

  raise notice '--- 6. tratamento: registra, e NÃO libera o portão ---';
  v_caso := (fn_upsert_caso('Caso tratamento'))::uuid;
  insert into pendencia (caso_id, origem_estagio, tipo, severidade, sobrepujavel, descricao)
    values (v_caso, 'completude', 'item_faltante', 'bloqueante', true, 'falta o MUTUOS')
    returning id into v_pend;

  v_r := fn_tratar_pendencia(v_pend, 'analista@oria', 'reenviada_ao_cliente',
    'Pedido por e-mail em 11/08, com prazo de 5 dias.');
  perform teste_assert_pr((v_r->>'tratada') = 'true', 'o pedido ao cliente fica registrado', v_r::text);
  select estado::text into v_estado from pendencia where id = v_pend;
  perform teste_assert_pr(v_estado = 'reenviada_ao_cliente', 'no estado de f0/04', v_estado);
  perform teste_assert_pr(not (fn_avaliar_portao2(v_caso)->>'elegivel')::boolean,
    'e o Portão 2 CONTINUA fechado — pendência sendo tratada é pendência não resolvida');

  -- Movimento de tratamento não é decisão: ninguém decidiu sobre o mérito.
  select count(*) into v_n from decisao where caso_id = v_caso;
  perform teste_assert_pr(v_n = 0, 'tratar não grava `decisao`', format('%s', v_n));
  perform teste_assert_pr(
    exists (select 1 from evento_auditoria
            where acao = 'pendencia_em_tratamento' and entidade_ref = 'pendencia:'||v_pend),
    'mas fica na trilha, que é onde "quem fez o quê" mora');

  v_r := fn_tratar_pendencia(v_pend, 'analista@oria', 'reenviada_ao_cliente');
  perform teste_assert_pr((v_r->>'sem_mudanca') = 'true',
    'repetir o mesmo estado é no-op declarado', v_r::text);

  v_r := fn_tratar_pendencia(v_pend, 'analista@oria', 'resolvida');
  perform teste_assert_pr((v_r->>'recusado') = 'true',
    'e "resolvida" NÃO se alcança por aqui — os estados finais têm guarda própria', v_r::text);

  raise notice '--- 7. pendência encerrada não volta para tratamento ---';
  update pendencia set estado = 'rejeitada' where id = v_pend;
  v_r := fn_tratar_pendencia(v_pend, 'analista@oria', 'em_correcao_interna');
  perform teste_assert_pr((v_r->>'recusado') = 'true',
    'reabrir por tratamento desfaria uma decisão que alguém tomou', v_r::text);

  raise notice 'TODOS OS TESTES DE PAPEL, RESSALVA E TRATAMENTO PASSARAM';
end $$;
