-- =============================================================================
-- A SAZONALIDADE E O "PRONTO" DA MODELAGEM (0134)
--
-- O defeito era de FLUIDEZ, não de número: vincular sazonalidade a uma linha —
-- que é exatamente o que a aba Modelagem existe para permitir — punha a premissa
-- em `premissas_sem_valor` e travava o "pronto" com uma pendência que o analista
-- NÃO TEM COMO RESOLVER. Não há campo para preencher: a curva vem do documento
-- mensal, derivada por `fn_sazonalidade_do_caso`.
--
-- O assert que importa é o 3: com a sazonalidade vinculada e todo o resto em
-- ordem, `pronto` tem de ser TRUE. Sem ele, esta migration seria uma opinião.
-- =============================================================================

create or replace function teste_assert(p_cond boolean, p_nome text, p_detalhe text default null)
returns void language plpgsql as $$
begin
  if p_cond then raise notice 'ok    %', p_nome;
  else raise exception 'FALHOU: % %', p_nome, coalesce(' — ' || p_detalhe, '');
  end if;
end $$;

do $$
declare
  v_caso  uuid;
  v_n     int;
  v_conf  jsonb;
  v_sem   text[];
  v_saz   text[];
  v_cod   text;
begin
  select count(*) into v_n from premissa_catalogo where formula = 'curva_mensal';
  perform teste_assert(v_n >= 3,
    'o catálogo tem as premissas de curva mensal (SAZONALIDADE e as outras)',
    format('%s premissa(s) com formula=curva_mensal', v_n));

  -- Um caso com modelagem configurada. Sem ele não há "pronto" para conferir.
  select caso_id into v_caso from caso_modelagem limit 1;
  perform teste_assert(v_caso is not null,
    'há um caso com modelagem configurada no banco de teste');
  if v_caso is null then return; end if;

  raise notice '--- 2. a sazonalidade NÃO entra em "premissas sem valor" ---';

  -- Estado de partida: nenhuma curva mensal vinculada.
  delete from caso_premissa where caso_id = v_caso
    and premissa_codigo in (select codigo from premissa_catalogo where formula = 'curva_mensal');

  -- Toda premissa que sobrou ganha valor, para isolar o efeito da sazonalidade:
  -- o que este teste mede é ELA, não a lista de pendências do caso.
  update caso_premissa set valores = '{"2026": 10}'::jsonb
   where caso_id = v_caso and ativo and (valores is null or valores = '{}'::jsonb);

  v_conf := fn_conferir_modelagem(v_caso);
  perform teste_assert((v_conf->>'pronto')::boolean,
    'com tudo preenchido e SEM sazonalidade, o caso está pronto',
    v_conf->>'premissas_sem_valor');

  -- Agora vincula a sazonalidade, com `valores` VAZIO — que é o estado CERTO
  -- dela, porque a curva não é digitada.
  select codigo into v_cod from premissa_catalogo where formula = 'curva_mensal' order by codigo limit 1;
  insert into caso_premissa (caso_id, premissa_codigo, valores, origem, ativo, atualizado_por)
    values (v_caso, v_cod, '{}'::jsonb, 'digitado', true, 'teste')
    on conflict (caso_id, premissa_codigo) do update
      set ativo = true, valores = '{}'::jsonb;

  v_conf := fn_conferir_modelagem(v_caso);
  select array(select jsonb_array_elements_text(v_conf->'premissas_sem_valor')) into v_sem;
  perform teste_assert(not (v_cod = any(v_sem)),
    format('"%s" (curva mensal) NÃO aparece como premissa sem valor', v_cod),
    coalesce(array_to_string(v_sem, ', '), '(vazio)'));

  raise notice '--- 3. O ASSERT QUE IMPORTA: o "pronto" não trava ---';
  perform teste_assert((v_conf->>'pronto')::boolean,
    'com a sazonalidade vinculada, o caso CONTINUA pronto — antes da 0134 travava para sempre, '
    || 'com uma pendência sem ação possível',
    format('pronto=%s sem_valor=%s', v_conf->>'pronto', v_conf->>'premissas_sem_valor'));

  raise notice '--- 4. o caso ruim DE VERDADE ganhou nome, e informa em vez de bloquear ---';
  select array(select jsonb_array_elements_text(v_conf->'sazonalidade_sem_curva')) into v_saz;
  -- Este caso de teste não tem documento mensal, então a curva não tem de onde
  -- sair — e é exatamente o estado que o campo novo existe para publicar.
  perform teste_assert(v_cod = any(v_saz),
    'curva mensal ativa num caso SEM documento mensal é publicada em sazonalidade_sem_curva',
    coalesce(array_to_string(v_saz, ', '), '(vazio)'));
  perform teste_assert((v_conf->>'pronto')::boolean,
    '…e mesmo assim NÃO bloqueia: o número anual continua certo, só o rateio mensal fica liso');

  raise notice '--- 5. e a premissa que REALMENTE falta valor continua travando ---';
  -- A contraprova. Sem ela, um `sem_valor` sempre vazio passaria em tudo acima.
  update caso_premissa set valores = '{}'::jsonb
   where caso_id = v_caso and ativo
     and premissa_codigo in (select codigo from premissa_catalogo where formula <> 'curva_mensal')
     and premissa_codigo = (select premissa_codigo from caso_premissa
                             where caso_id = v_caso and ativo
                               and premissa_codigo in (select codigo from premissa_catalogo
                                                        where formula <> 'curva_mensal')
                             order by premissa_codigo limit 1);
  v_conf := fn_conferir_modelagem(v_caso);
  select array(select jsonb_array_elements_text(v_conf->'premissas_sem_valor')) into v_sem;
  perform teste_assert(coalesce(array_length(v_sem, 1), 0) > 0,
    'premissa de fórmula NORMAL sem valor continua entrando na lista',
    coalesce(array_to_string(v_sem, ', '), '(vazio)'));
  perform teste_assert(not (v_conf->>'pronto')::boolean,
    '…e continua travando o "pronto" — o portão não foi afrouxado, só deixou de cobrar o impossível');
end $$;

do $$ begin raise notice 'TODOS OS TESTES DA SAZONALIDADE NO PRONTO (0134) PASSARAM'; end $$;

drop function teste_assert(boolean, text, text);
