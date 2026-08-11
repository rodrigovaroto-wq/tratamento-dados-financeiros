-- Testes de REJEITAR pendência (db/migrations/0106).
-- Rodar via db/test/run.sh (que aplica as migrations antes).
--
-- O que estes testes travam, e por quê cada um:
--
--   • rejeitar LIBERA o portão — inclusive a não-sobrepujável, que é o que
--     `f0/04` manda ("tem de ser resolvida ou rejeitada") e o que torna esta a
--     alavanca mais forte do sistema;
--   • …e por isso ela é CONTADA: a avaliação publica `rejeitadas` e
--     `rejeitadas_nao_sobrepujaveis`, e a `decisao` de aprovação carrega os dois.
--     Sem isto, um caso destravado a golpe de rejeição tem exatamente a mesma
--     aparência de um caso que nunca teve pendência;
--   • motivo curto é RECUSADO e a pendência não se move — a guarda que separa
--     "declarei improcedente e escrevi por quê" de "tirei o vermelho da tela";
--   • estado terminal não se rejeita (não se reescreve o passado);
--   • a rejeição SOBREVIVE ao recomputo da completude. Este é o assert que
--     decide se a funcionalidade serve para alguma coisa: se o motor reabrisse a
--     pendência na próxima passada, o botão seria decorativo.

\set ON_ERROR_STOP on

create or replace function teste_assert_rej(p_ok boolean, p_nome text, p_detalhe text default null)
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
  v_caso2  uuid;
  v_r      jsonb;
  v_aval   jsonb;
  v_pend   uuid;
  v_pend2  uuid;
  v_estado text;
  v_txt    text;
  v_n      int;
begin
  raise notice '--- 1. bloqueante rejeitada libera o portão, e a linha continua lá ---';
  v_caso := (fn_upsert_caso('Caso rejeição — bloqueante improcedente'))::uuid;
  insert into pendencia (caso_id, origem_estagio, tipo, severidade, sobrepujavel, descricao)
    values (v_caso, 'reconciliacao', 'divergencia_reconciliacao', 'bloqueante', true,
            'Ativo total 195.090 contra 95.780 informados')
    returning id into v_pend;

  perform teste_assert_rej(not (fn_avaliar_portao2(v_caso)->>'elegivel')::boolean,
    'antes de decidir, a bloqueante trava o caso');

  v_r := fn_rejeitar_pendencia(v_pend, 'analista@oria',
    'O 195.090 é o subtotal informado somado aos componentes; o documento fecha em 95.780.');
  perform teste_assert_rej((v_r->>'rejeitada') = 'true', 'a rejeição é aceita', v_r::text);
  perform teste_assert_rej((v_r->'avaliacao'->>'elegivel')::boolean,
    'e o caso passa a ser elegível na MESMA chamada — quem clica vê o efeito', v_r::text);

  -- Rejeitar NÃO é apagar: a linha fica, com autor e motivo. `delete` seria a
  -- mesma liberação sem contagem nenhuma, e é a contagem que o portão publica.
  select estado::text into v_estado from pendencia where id = v_pend;
  perform teste_assert_rej(v_estado = 'rejeitada', 'a pendência continua na tabela, rejeitada',
    coalesce(v_estado, '(sumiu)'));
  select resolvida_por into v_txt from pendencia where id = v_pend;
  perform teste_assert_rej(v_txt = 'analista@oria', 'com o autor gravado', coalesce(v_txt, '(null)'));
  select motivo into v_txt from pendencia where id = v_pend;
  perform teste_assert_rej(v_txt like '%95.780%', 'e o motivo escrito', coalesce(v_txt, '(null)'));

  raise notice '--- 2. …e a decisão é um OVERRIDE registrado, não um update solto ---';
  select count(*) into v_n from decisao
    where caso_id = v_caso and tipo = 'override' and payload->>'acao' = 'rejeitar_pendencia';
  perform teste_assert_rej(v_n = 1, 'uma decisão de override na trilha', format('decisões: %s', v_n));
  perform teste_assert_rej(
    exists (select 1 from evento_auditoria
            where acao = 'pendencia_rejeitada' and entidade_ref = 'pendencia:'||v_pend),
    'e o evento de auditoria com o antes e o depois');

  raise notice '--- 3. MOTIVO CURTO É RECUSADO, e a pendência não se move ---';
  -- Religando esta guarda (aceitar qualquer texto), "ok" liberaria o Portão 2 —
  -- que é exatamente o que se digita quando o objetivo é tirar o vermelho da
  -- tela, não declarar improcedência.
  insert into pendencia (caso_id, origem_estagio, tipo, severidade, sobrepujavel, descricao)
    values (v_caso, 'completude', 'item_faltante', 'bloqueante', true, 'falta o MUTUOS')
    returning id into v_pend2;

  v_r := fn_rejeitar_pendencia(v_pend2, 'analista@oria', 'ok');
  perform teste_assert_rej((v_r->>'recusado') = 'true', 'motivo de duas letras é recusado', v_r::text);
  perform teste_assert_rej((v_r->>'motivo_recusa') like '%pelo menos 15%',
    'e a recusa diz o mínimo exigido, em vez de só falhar', v_r->>'motivo_recusa');

  select estado::text into v_estado from pendencia where id = v_pend2;
  perform teste_assert_rej(v_estado = 'aberta', 'a pendência continua ABERTA', v_estado);
  perform teste_assert_rej(not (fn_avaliar_portao2(v_caso)->>'elegivel')::boolean,
    'e o portão continua fechado');

  -- A TENTATIVA fica na trilha. "Ninguém tentou" e "alguém tentou destravar sem
  -- justificar" são fatos diferentes, e o segundo é o que interessa a quem audita.
  perform teste_assert_rej(
    exists (select 1 from evento_auditoria
            where acao = 'rejeicao_recusada' and entidade_ref = 'pendencia:'||v_pend2),
    'mas a tentativa fica registrada — recusar não é apagar o rastro');

  select count(*) into v_n from decisao
    where caso_id = v_caso and payload->>'pendencia_id' = v_pend2::text;
  perform teste_assert_rej(v_n = 0, 'e NENHUMA decisão foi gravada', format('decisões: %s', v_n));

  -- Só espaço em branco também não passa (o trim vem antes da contagem).
  v_r := fn_rejeitar_pendencia(v_pend2, 'analista@oria', '                              ');
  perform teste_assert_rej((v_r->>'recusado') = 'true', 'nem trinta espaços em branco', v_r::text);

  raise notice '--- 4. rejeitar de novo é no-op DECLARADO ---';
  v_r := fn_rejeitar_pendencia(v_pend, 'outro.analista@oria',
    'clicou de novo depois de recarregar a página');
  perform teste_assert_rej((v_r->>'ja_rejeitada') = 'true',
    'o segundo clique se anuncia como no-op', v_r::text);
  select count(*) into v_n from decisao
    where caso_id = v_caso and payload->>'pendencia_id' = v_pend::text;
  perform teste_assert_rej(v_n = 1, 'e a trilha continua com UMA decisão', format('decisões: %s', v_n));

  raise notice '--- 5. pendência RESOLVIDA não vira rejeitada ---';
  -- Chamar de falso positivo o que foi de fato tratado reescreve o que aconteceu.
  update pendencia set estado = 'resolvida', resolvida_em = now() where id = v_pend2;
  v_r := fn_rejeitar_pendencia(v_pend2, 'analista@oria',
    'querendo mudar o rótulo do que já foi resolvido');
  perform teste_assert_rej((v_r->>'recusado') = 'true',
    'rejeitar o que já está resolvido é recusado', v_r::text);
  select estado::text into v_estado from pendencia where id = v_pend2;
  perform teste_assert_rej(v_estado = 'resolvida', 'e o estado não muda', v_estado);

  raise notice '--- 6. NÃO-SOBREPUJÁVEL: a rejeição libera, mas fica CONTADA ---';
  -- É o ponto sensível: a lista fechada de f0/04 diz que nenhuma RESSALVA a
  -- libera (0037 prova isso), e ao mesmo tempo manda "resolver ou rejeitar". Ou
  -- seja, rejeitar é o único caminho de saída além de consertar — sem teto, ao
  -- contrário da ressalva, que para em 3. Não dá para proibir sem prender o caso
  -- para sempre; o que dá é NÃO DEIXAR ISSO INVISÍVEL.
  v_caso2 := (fn_upsert_caso('Caso rejeição — não-sobrepujável'))::uuid;
  insert into pendencia (caso_id, origem_estagio, tipo, severidade, sobrepujavel, descricao)
    values (v_caso2, 'completude', 'item_sem_conteudo', 'bloqueante', false,
            'BALANCO recebido sem uma linha extraída')
    returning id into v_pend;

  v_aval := fn_avaliar_portao2(v_caso2);
  perform teste_assert_rej((v_aval->>'rejeitadas')::int = 0,
    'com nada rejeitado, o contador nasce em zero', v_aval::text);

  v_r := fn_rejeitar_pendencia(v_pend, 'socio.senior@oria',
    'O arquivo é a capa do balanço; as linhas vieram no PDF combinado do mesmo lote.');
  perform teste_assert_rej((v_r->'avaliacao'->>'elegivel')::boolean,
    'rejeitar a não-sobrepujável libera o portão (f0/04: resolver ou rejeitar)', v_r::text);

  v_aval := fn_avaliar_portao2(v_caso2);
  perform teste_assert_rej((v_aval->>'rejeitadas')::int = 1,
    'e o portão publica que UMA pendência foi declarada improcedente', v_aval::text);
  perform teste_assert_rej((v_aval->>'rejeitadas_nao_sobrepujaveis')::int = 1,
    '…dizendo separadamente que ela era da lista fechada — é o número que se lê antes de assinar',
    v_aval::text);

  raise notice '--- 7. a aprovação CARREGA a contagem: caso destravado ≠ caso limpo ---';
  v_r := fn_aprovar_caso(v_caso2, 'socio.senior@oria', 'conferido contra o PDF combinado');
  perform teste_assert_rej((v_r->>'aprovado') = 'true', 'o caso aprova', v_r::text);

  select payload->'avaliacao'->>'rejeitadas_nao_sobrepujaveis' into v_txt
    from decisao where caso_id = v_caso2 and tipo = 'aprovacao';
  perform teste_assert_rej(v_txt = '1',
    'e a decisão de aprovação guarda, para sempre, que ela passou por cima de uma não-sobrepujável',
    coalesce(v_txt, '(ausente)'));

  raise notice '--- 8. a rejeição SOBREVIVE ao recomputo da completude ---';
  -- Sem esta propriedade a funcionalidade seria decorativa: o motor roda a cada
  -- extração, e uma pendência que renasce na passada seguinte nunca destrava
  -- nada. A guarda de `fn_recomputar_completude` é `estado <> 'resolvida'`, então
  -- `rejeitada` conta como já existente — mas isso é consequência de uma linha
  -- escrita para outro fim, e é exatamente o tipo de acoplamento que quebra em
  -- silêncio. Por isso está travado aqui.
  v_caso2 := (fn_upsert_caso('Caso rejeição — recomputo'))::uuid;
  perform fn_recomputar_completude(v_caso2);

  select id into v_pend from pendencia
    where caso_id = v_caso2 and tipo = 'item_faltante' order by descricao limit 1;
  perform teste_assert_rej(v_pend is not null,
    'o recomputo abriu pendência de item faltante (caso sem nenhum documento)');

  v_r := fn_rejeitar_pendencia(v_pend, 'analista@oria',
    'Item dispensado pelo mandato: a holding não tem contrato de mútuo neste exercício.');
  perform teste_assert_rej((v_r->>'rejeitada') = 'true', 'e ela é rejeitada', v_r::text);

  perform fn_recomputar_completude(v_caso2);
  select estado::text into v_estado from pendencia where id = v_pend;
  perform teste_assert_rej(v_estado = 'rejeitada',
    'depois de recomputar, ela CONTINUA rejeitada — o motor não desfaz decisão humana', v_estado);

  select count(*) into v_n from pendencia
    where caso_id = v_caso2 and tipo = 'item_faltante'
      and descricao = (select descricao from pendencia where id = v_pend);
  perform teste_assert_rej(v_n = 1,
    '…e nenhuma cópia nova nasceu no lugar dela', format('linhas: %s', v_n));

  raise notice '--- 9. id que não existe é erro de programação, não recusa de política ---';
  begin
    perform fn_rejeitar_pendencia('00000000-0000-0000-0000-000000000000'::uuid, 'analista@oria',
      'motivo suficientemente longo para passar da guarda');
    perform teste_assert_rej(false, 'deveria ter levantado exceção para id inexistente');
  exception when others then
    perform teste_assert_rej(sqlerrm like '%não encontrada%',
      'id inexistente levanta exceção com o texto certo', sqlerrm);
  end;

  raise notice 'TODOS OS TESTES DE REJEITAR PENDÊNCIA PASSARAM';
end $$;
