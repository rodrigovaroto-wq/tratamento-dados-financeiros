-- =============================================================================
-- 0183 — O MARCADOR DE COBERTURA DA SONDA NÃO REGRIDE.
--
-- O DEFEITO, medido em produção em 23/09/2026: a 0182 foi aplicada DEPOIS da 0188 (duas sessões
-- trabalhando em paralelo, cada uma aplicando o que era dela) e o `update instalacao_cobertura set
-- ate_migration = '0182'` incondicional do fim dela rebaixou o marcador de '0188' para '0182'. A
-- sonda passou a responder "cobertura até a 0182" com a 0186–0188 no ar, sem erro nenhum. O mesmo
-- update incondicional está em 39 migrations; a correção mora na tabela, num gatilho.
--
-- ESTE ARQUIVO NÃO REPRODUZ A APLICAÇÃO FORA DE ORDEM (regra 4 — não inventar o arranjo de
-- produção). Ele afirma o COMPORTAMENTO que teria evitado o defeito: um update que tenta pôr um
-- valor MENOR no marcador não o rebaixa, e não troca a observação da linha; um update com valor
-- MAIOR avança normalmente. Roda dentro de uma transação desfeita no fim, porque o marcador é lido
-- por outros portões desta suíte e não pode sair daqui alterado.
--
-- MEDIÇÃO NÃO-VAZIA (regra 2): com a criação do gatilho `trg_instalacao_cobertura_nao_regride`
-- comentada na 0183 — o número está na mensagem do commit que introduziu este arquivo.
-- =============================================================================

begin;

create or replace function pg_temp.teste_assert_cobertura(p_cond boolean, p_nome text, p_detalhe text default null)
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
  v_antes      text;
  v_obs_antes  text;
  v_depois     text;
  v_obs_depois text;
begin
  select ate_migration, observacao into v_antes, v_obs_antes from instalacao_cobertura;

  raise notice '--- 1. uma migration MAIS ANTIGA que o marcador não o rebaixa ---';
  update instalacao_cobertura
     set ate_migration = '0001', observacao = 'texto de uma migration antiga', revisado_em = current_date;
  select ate_migration, observacao into v_depois, v_obs_depois from instalacao_cobertura;
  perform pg_temp.teste_assert_cobertura(v_depois = v_antes,
    'o marcador não desce quando uma migration anterior escreve o dela',
    format('antes=%s depois=%s', v_antes, v_depois));
  perform pg_temp.teste_assert_cobertura(v_obs_depois = v_obs_antes,
    'e a observação ao lado continua descrevendo a migration do marcador, não a antiga',
    format('observacao=%s', left(v_obs_depois, 60)));

  raise notice '--- 2. uma migration MAIS NOVA avança o marcador normalmente ---';
  update instalacao_cobertura set ate_migration = '9999', observacao = 'a mais nova';
  select ate_migration, observacao into v_depois, v_obs_depois from instalacao_cobertura;
  perform pg_temp.teste_assert_cobertura(v_depois = '9999' and v_obs_depois = 'a mais nova',
    'o gatilho não congela o marcador — uma migration mais nova o avança e troca a observação',
    format('depois=%s', v_depois));

  raise notice 'COBERTURA OK — o marcador da sonda não regride nem troca a descrição por uma migration mais antiga, e continua avançando com as mais novas';
end $$;

rollback;
