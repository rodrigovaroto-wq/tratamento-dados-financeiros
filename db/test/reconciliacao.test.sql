-- Testes da reconciliação (Classe A/B) contra o fixture do book Vertentes.
-- Rodar via db/test/run.sh (que aplica as migrations e o fixture antes).
--
-- A regra de ouro que estes testes travam: **extração fiel => nenhuma
-- pendência**. Uma checagem que grita à toa é pior que checagem nenhuma, porque
-- ensina o analista a ignorar o aviso. Mas o inverso também é testado: cada
-- checagem tem um caso NEGATIVO provando que ela ainda pega o erro real.

\set ON_ERROR_STOP on
\set CASO '11111111-1111-1111-1111-111111111111'
\set ENT_METAL '22222222-0000-0000-0000-000000000001'
\set ENT_GRUPO '22222222-0000-0000-0000-000000000006'
\set VER_BP_METAL '55555555-0000-0000-0000-000000000001'
\set VER_DRE '55555555-0000-0000-0000-000000000007'
\set VER_DIVIDA '55555555-0000-0000-0000-000000000011'

create or replace function teste_assert(p_ok boolean, p_nome text, p_detalhe text default null)
returns void language plpgsql as $$
begin
  if p_ok then
    raise notice 'ok    %', p_nome;
  else
    raise exception 'FALHOU: % %', p_nome, coalesce(' — ' || p_detalhe, '');
  end if;
end $$;

create or replace function teste_reconciliar_tudo(p_caso uuid)
returns void language plpgsql as $$
declare r record;
begin
  for r in select id from documento where caso_id = p_caso order by id loop
    perform fn_reconciliar_por_documento(r.id);
  end loop;
end $$;

-- =============================================================================
do $$
declare
  v_caso uuid := '11111111-1111-1111-1111-111111111111';
  v_n int;
  v_txt text;
begin
  raise notice '--- 1. extração fiel dos 14 documentos ---';
  perform teste_reconciliar_tudo(v_caso);

  select count(*) into v_n from pendencia
  where caso_id = v_caso and estado <> 'resolvida';
  perform teste_assert(v_n = 0,
    'extração fiel não abre nenhuma pendência de reconciliação',
    format('%s pendência(s): %s', v_n,
      (select string_agg(left(descricao, 90), ' | ') from pendencia
       where caso_id = v_caso and estado <> 'resolvida')));

  -- As 4 checagens têm de ter CHEGADO a um veredito, não ficado caladas.
  select count(distinct tipo) into v_n from reconciliacao
  where caso_id = v_caso and resultado = 'ok';
  perform teste_assert(v_n = 4,
    'as 4 checagens A/B chegam a "ok" com número (nenhuma fica muda)',
    format('%s tipo(s) com ok', v_n));

  -- Balanço comparativo => os DOIS anos conferidos, não só um.
  select max((materialidade->>'anos_checados')::int) into v_n from reconciliacao
  where caso_id = v_caso and tipo = 'ativo_passivo_pl';
  perform teste_assert(v_n = 2,
    'balanço comparativo é conferido nos dois anos, não só no primeiro casamento',
    format('anos_checados = %s', v_n));

  -- O COMBINADO é aceito como balanço do grupo (antes: "nenhum Balanço classificado").
  select resultado into v_txt from reconciliacao
  where caso_id = v_caso and tipo = 'ativo_passivo_pl'
    and entidade_id = '22222222-0000-0000-0000-000000000006';
  perform teste_assert(v_txt = 'ok',
    'balanço COMBINADO é aceito como balanço do grupo', coalesce(v_txt, 'sem registro'));

  -- Receita bruta obtida somando a seção (a DRE do book não tem linha de total).
  select fonte_a->>'chave' into v_txt from reconciliacao
  where caso_id = v_caso and tipo = 'receita_dre_vs_faturamento' and resultado = 'ok' limit 1;
  perform teste_assert(v_txt like 'soma de%',
    'Receita Bruta sem linha de total é obtida somando as contas da seção',
    coalesce(v_txt, 'null'));

  -- Escalas diferentes (DRE em milhar, mapa de dívida em reais) => converte.
  select count(*) into v_n from reconciliacao
  where caso_id = v_caso and tipo = 'despfin_dre_vs_divida' and resultado = 'ok';
  perform teste_assert(v_n > 0,
    'DRE em milhar vs Mapa de Dívida em reais: converte a escala em vez de recusar',
    format('%s ok', v_n));

  -- Documento ausente: registrado na trilha, mas sem pendência.
  select count(*) into v_n from reconciliacao
  where caso_id = v_caso and tipo = 'caixa_bp_fluxo'
    and resultado = 'precondicao_nao_satisfeita';
  perform teste_assert(v_n > 0,
    'DFC ausente fica registrada em reconciliacao (trilha de auditoria preservada)',
    format('%s registros', v_n));
  select count(*) into v_n from pendencia
  where caso_id = v_caso and motivo = 'reconciliacao:caixa_bp_fluxo' and estado <> 'resolvida';
  perform teste_assert(v_n = 0,
    'DFC ausente NÃO abre pendência (é cobrança do checklist do Kit Básico)',
    format('%s pendência(s)', v_n));
end $$;

-- =============================================================================
do $$
declare
  v_caso uuid := '11111111-1111-1111-1111-111111111111';
  v_ver  uuid := '55555555-0000-0000-0000-000000000001';
  v_n int;
begin
  raise notice '--- 2. NEGATIVO: balanço que não fecha tem de ser pego ---';
  update campo_extraido set valor_num = valor_num + 5000
  where documento_versao_id = v_ver
    and chave = 'TOTAL DO ATIVO' and periodo_coluna = '2024';

  perform teste_reconciliar_tudo(v_caso);
  select count(*) into v_n from pendencia
  where caso_id = v_caso and motivo = 'reconciliacao:ativo_passivo_pl' and estado <> 'resolvida';
  perform teste_assert(v_n = 1,
    'Ativo inflado em 5.000 no ano de 2024 abre exatamente 1 pendência',
    format('%s pendência(s)', v_n));

  -- E a descrição tem de dizer QUAL ano, senão o humano não sabe onde olhar.
  select count(*) into v_n from pendencia
  where caso_id = v_caso and motivo = 'reconciliacao:ativo_passivo_pl'
    and estado <> 'resolvida' and descricao like '%2024%' and descricao like '%2025: confere%';
  perform teste_assert(v_n = 1,
    'a pendência diz qual ano divergiu e qual conferiu');

  -- Desfaz e confirma a auto-resolução.
  update campo_extraido set valor_num = valor_num - 5000
  where documento_versao_id = v_ver
    and chave = 'TOTAL DO ATIVO' and periodo_coluna = '2024';
  perform teste_reconciliar_tudo(v_caso);
  select count(*) into v_n from pendencia
  where caso_id = v_caso and motivo = 'reconciliacao:ativo_passivo_pl' and estado <> 'resolvida';
  perform teste_assert(v_n = 0, 'corrigido o número, a pendência auto-resolve');
end $$;

-- =============================================================================
do $$
declare
  v_caso uuid := '11111111-1111-1111-1111-111111111111';
  v_ver  uuid := '55555555-0000-0000-0000-000000000011';
  v_n int;
begin
  raise notice '--- 3. NEGATIVO: escala desconhecida ainda recusa ---';
  update campo_extraido set unidade = 'sacas de café' where documento_versao_id = v_ver;
  perform teste_reconciliar_tudo(v_caso);
  select count(*) into v_n from pendencia
  where caso_id = v_caso and motivo = 'reconciliacao:despfin_dre_vs_divida'
    and estado <> 'resolvida' and descricao like '%não conversíveis%';
  perform teste_assert(v_n = 1,
    'escala em vocabulário desconhecido recusa a comparação (não inventa fator)',
    format('%s pendência(s)', v_n));

  update campo_extraido set unidade = 'unidade' where documento_versao_id = v_ver;
  perform teste_reconciliar_tudo(v_caso);
  select count(*) into v_n from pendencia
  where caso_id = v_caso and motivo = 'reconciliacao:despfin_dre_vs_divida' and estado <> 'resolvida';
  perform teste_assert(v_n = 0, 'escala reconhecida de volta: pendência auto-resolve');
end $$;

-- =============================================================================
do $$
declare
  v_caso uuid := '11111111-1111-1111-1111-111111111111';
  v_ver  uuid := '55555555-0000-0000-0000-000000000008';
  v_n int;
begin
  raise notice '--- 4. NEGATIVO: caixa do BP que não bate com a DFC ---';
  update campo_extraido set valor_num = 9999
  where documento_versao_id = v_ver
    and chave = 'Caixa e equivalentes de caixa no final do exercício';
  perform teste_reconciliar_tudo(v_caso);
  select count(*) into v_n from pendencia
  where caso_id = v_caso and motivo = 'reconciliacao:caixa_bp_fluxo' and estado <> 'resolvida';
  perform teste_assert(v_n = 1,
    'saldo final da DFC divergente do Disponível do BP abre pendência',
    format('%s pendência(s)', v_n));

  update campo_extraido set valor_num = 500
  where documento_versao_id = v_ver
    and chave = 'Caixa e equivalentes de caixa no final do exercício';
  perform teste_reconciliar_tudo(v_caso);
  select count(*) into v_n from pendencia
  where caso_id = v_caso and motivo = 'reconciliacao:caixa_bp_fluxo' and estado <> 'resolvida';
  perform teste_assert(v_n = 0, 'saldo corrigido: pendência auto-resolve');
end $$;

-- =============================================================================
do $$
declare
  v_caso uuid := '11111111-1111-1111-1111-111111111111';
  v_ver  uuid := '55555555-0000-0000-0000-000000000010';
  v_n int;
begin
  raise notice '--- 5. NEGATIVO: faturamento que não amarra com a receita da DRE ---';
  update campo_extraido set valor_num = valor_num * 0.5
  where documento_versao_id = v_ver and periodo_coluna = '2025' and chave like '%/2025';
  perform teste_reconciliar_tudo(v_caso);
  select count(*) into v_n from pendencia
  where caso_id = v_caso and motivo = 'reconciliacao:receita_dre_vs_faturamento'
    and estado <> 'resolvida';
  perform teste_assert(v_n = 1,
    'faturamento de 2025 pela metade abre pendência de zona cinzenta (Classe B)',
    format('%s pendência(s)', v_n));

  update campo_extraido set valor_num = valor_num * 2
  where documento_versao_id = v_ver and periodo_coluna = '2025' and chave like '%/2025';
  perform teste_reconciliar_tudo(v_caso);
  select count(*) into v_n from pendencia
  where caso_id = v_caso and motivo = 'reconciliacao:receita_dre_vs_faturamento'
    and estado <> 'resolvida';
  perform teste_assert(v_n = 0, 'faturamento corrigido: pendência auto-resolve');
end $$;

-- =============================================================================
do $$
declare
  v_caso uuid := '11111111-1111-1111-1111-111111111111';
  v_ver  uuid := '55555555-0000-0000-0000-000000000001';
  v_n int;
begin
  raise notice '--- 6. NEGATIVO: rótulo de total irreconhecível => pendência real ---';
  -- Documento presente mas sem NADA que sirva de Ativo Total nem de contas de
  -- seção: aí sim é defeito de extração e o humano tem o que fazer.
  update campo_extraido set secao = 'BLOCO SEM NOME',
                            chave = 'XPTO ' || id::text
  where documento_versao_id = v_ver;
  perform teste_reconciliar_tudo(v_caso);
  select count(*) into v_n from pendencia
  where caso_id = v_caso and motivo = 'reconciliacao:ativo_passivo_pl'
    and estado <> 'resolvida' and descricao like '%rótulos extraídos não bateram%';
  perform teste_assert(v_n = 1,
    'documento presente com rótulos irreconhecíveis abre pendência (defeito acionável)',
    format('%s pendência(s)', v_n));
end $$;

drop function teste_assert(boolean, text, text);
drop function teste_reconciliar_tudo(uuid);
