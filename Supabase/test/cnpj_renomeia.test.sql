-- =============================================================================
-- 0171 — o CNPJ também renomeia, não só funde
--
-- OS NOMES SÃO OS REAIS (regra 4): os quatro nomes da OMNIBEAUTY do caso
-- "teste 143", com o CNPJ real 36.193.378/0001-04.
--
-- O QUE ESTE ARQUIVO MEDE:
--   1. o nome contaminado pelo endereço, mais LONGO, chegando DEPOIS do nome
--      certo, não vence — é o cenário que motivou a fatia;
--   2. e chegando ANTES do nome certo, também não vence — a ordem de chegada
--      não deveria mudar qual nome sobrevive quando o CNPJ prova identidade;
--   3. entre dois nomes SEM sufixo, o que não tem cara de endereço vence
--      mesmo sendo mais curto (SURUBIJU vence SURUBIJU,1930);
--   4. o sufixo societário vence o nome truncado sem sufixo;
--   5. o rastro (entidade_renomeada_por_cnpj) só aparece quando o nome
--      REALMENTE mudou — não em todo documento que casa por CNPJ;
--   6. os ramos de casamento APROXIMADO (sem CNPJ) continuam SEM renomear —
--      escopo desta fatia é só o ramo (0).
-- =============================================================================

create or replace function teste_assert_ren(p_cond boolean, p_nome text, p_detalhe text default null)
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
  c_cnpj  constant text := '36.193.378/0001-04';
  c_t     constant text := 'OMNIBEAUTY DESENVOLVIMENTO E GESTAO DE';
  c_m     constant text := 'OMNIBEAUTY DESENVOLVIMENTO E GESTAO DE MARCAS LTDA';
  c_s     constant text := 'OMNIBEAUTY DESENVOLVIMENTO E GESTAO DE SURUBIJU';
  c_s1930 constant text := 'OMNIBEAUTY DESENVOLVIMENTO E GESTAO DE SURUBIJU, 1930';
  v_caso  uuid;
  v_id    uuid;
  v_nome  text;
  v_n     int;
BEGIN
  raise notice '--- 1. o contaminado (mais LONGO) chega DEPOIS do certo: não vence ---';
  v_caso := (fn_upsert_caso('CNPJ renomeia — contaminado depois'))::uuid;
  v_id := fn_upsert_entidade(v_caso, c_m, c_cnpj);
  v_id := fn_upsert_entidade(v_caso, c_s1930, c_cnpj);
  select razao_social into v_nome from entidade where id = v_id;

  -- ESTE É O ASSERT QUE REPROVA COM A CORREÇÃO DESLIGADA (a chamada abaixo
  -- devolvendo sempre p_atual): sem ela, o nome fica "…DE MARCAS LTDA" de
  -- qualquer forma NESTE sentido de chegada — que é justamente por que este
  -- bloco sozinho não bastaria; ver o bloco 2, no sentido oposto.
  perform teste_assert_ren(v_nome = c_m,
    'o nome contaminado pelo endereço (55 chars) NÃO desloca o certo (52 chars) chegando depois',
    v_nome);

  raise notice '--- 2. o contaminado chega ANTES do certo: também não vence ---';
  -- ESTE é o assert que de fato reprova com a correção desligada: sem ela, o
  -- PRIMEIRO nome a chegar sempre fica (é o que a 0169/0170 já faziam), e
  -- "SURUBIJU, 1930" teria virado o nome definitivo da entidade.
  v_caso := (fn_upsert_caso('CNPJ renomeia — contaminado primeiro'))::uuid;
  v_id := fn_upsert_entidade(v_caso, c_s1930, c_cnpj);
  v_id := fn_upsert_entidade(v_caso, c_m, c_cnpj);
  select razao_social into v_nome from entidade where id = v_id;
  perform teste_assert_ren(v_nome = c_m,
    'e chegando ANTES também não vence — a ORDEM não deveria decidir qual nome fica',
    v_nome);

  raise notice '--- 3. sem sufixo nenhum dos dois: quem não tem cara de endereço vence ---';
  v_caso := (fn_upsert_caso('CNPJ renomeia — SURUBIJU vs SURUBIJU 1930'))::uuid;
  v_id := fn_upsert_entidade(v_caso, c_s, c_cnpj);
  v_id := fn_upsert_entidade(v_caso, c_s1930, c_cnpj);
  select razao_social into v_nome from entidade where id = v_id;
  perform teste_assert_ren(v_nome = c_s,
    '"…DE SURUBIJU" (48 chars, sem endereço) vence "…DE SURUBIJU, 1930" (55 chars, com '
      || 'endereço) — comprimento cru sozinho erraria aqui',
    v_nome);

  raise notice '--- 4. sufixo societário vence o truncado sem sufixo ---';
  v_caso := (fn_upsert_caso('CNPJ renomeia — truncado vs MARCAS'))::uuid;
  v_id := fn_upsert_entidade(v_caso, c_t, c_cnpj);
  v_id := fn_upsert_entidade(v_caso, c_m, c_cnpj);
  select razao_social into v_nome from entidade where id = v_id;
  perform teste_assert_ren(v_nome = c_m,
    '"…DE MARCAS LTDA" (com sufixo) vence o truncado "…DE" (sem sufixo, mais curto)', v_nome);

  raise notice '--- 5. o rastro só aparece quando o nome REALMENTE mudou ---';
  v_caso := (fn_upsert_caso('CNPJ renomeia — rastro'))::uuid;
  v_id := fn_upsert_entidade(v_caso, c_t, c_cnpj);
  v_id := fn_upsert_entidade(v_caso, c_m, c_cnpj);  -- renomeia: …DE → …DE MARCAS LTDA
  v_id := fn_upsert_entidade(v_caso, c_t, c_cnpj);  -- casa de novo, NÃO deveria renomear de volta

  select count(*) into v_n from evento_auditoria
    where acao = 'entidade_renomeada_por_cnpj' and entidade_ref = 'entidade:' || v_id;
  perform teste_assert_ren(v_n = 1,
    'exatamente UM evento de renomeio — o terceiro documento (nome pior) não desfaz o segundo',
    format('%s evento(s)', v_n));

  select razao_social into v_nome from entidade where id = v_id;
  perform teste_assert_ren(v_nome = c_m,
    'e o nome continua o mais completo depois do terceiro documento', v_nome);

  raise notice '--- 6. os ramos de casamento APROXIMADO (sem CNPJ) continuam sem renomear ---';
  -- Escopo desta fatia é só o ramo (0), o CNPJ igual. Sem CNPJ, quem decide
  -- continua sendo a 0168 (escolhe entre os que JÁ EXISTIAM, nunca quem
  -- chega) — este bloco é regressão contra a fatia anterior.
  v_caso := (fn_upsert_caso('CNPJ renomeia — sem CNPJ, 0168 intacta'))::uuid;
  perform fn_upsert_entidade(v_caso, c_m);
  perform fn_upsert_entidade(v_caso, c_s);
  perform fn_upsert_entidade(v_caso, c_t);
  v_id := fn_upsert_entidade(v_caso, c_s1930);
  select razao_social into v_nome from entidade where id = v_id;
  perform teste_assert_ren(v_nome = c_s,
    'sem CNPJ, o resultado da 0168 não mudou: "…DE SURUBIJU" (o mais longo ENTRE OS QUE JÁ '
      || 'EXISTIAM), não "…DE MARCAS LTDA" nem o que chegou por último',
    v_nome);
  perform teste_assert_ren(not exists (
      select 1 from evento_auditoria
       where acao = 'entidade_renomeada_por_cnpj' and entidade_ref = 'entidade:' || v_id),
    'e nenhum evento de renomeio por CNPJ nasceu — não havia CNPJ nenhum envolvido');

  raise notice 'CNPJ RENOMEIA OK — a cara de endereço nunca vence, o sufixo desempata, o '
               'comprimento só decide por último, e a ordem de chegada parou de mandar';
END $$;
