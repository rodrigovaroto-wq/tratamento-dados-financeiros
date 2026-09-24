-- =============================================================================
-- 0183 (item 10) — A FUSÃO DE ENTIDADES NÃO APAGA O CONTROLE DECLARADO.
--
-- O DEFEITO, reproduzido no banco de teste em 24/09/2026 antes da correção: `fn_fundir_entidade`
-- (0153) faz `delete from entidade` na absorvida, e o `on delete cascade` de `entidade_controlador`
-- (0182) levava junto o vínculo que um humano declarou — 1 vínculo antes, 0 depois, e o grupo por
-- controle comum ficava menor sem erro. Sobravam também as pendências de forma (0183) e de papel
-- (0179) da absorvida, abertas para sempre, apontando para uma entidade que não existe.
--
-- O ARRANJO É O DE PRODUÇÃO, não inventado (regra 4): é a chamada que `fn_entidade_aprender_cnpj`
-- (0174/0177) faz sozinha quando o CNPJ lido num documento já pertence a outra entidade do caso.
-- O teste chama `fn_fundir_entidade` direto porque a guarda de balcão (0177) e a normalização de
-- nome decidem SE a fusão acontece, e aqui a pergunta é o que ela faz QUANDO acontece.
--
-- O QUE ESTE ARQUIVO AFIRMA (comportamento, não mecanismo):
--   1. sobrevivente sem vínculo: o grupo por controle comum continua com a empresa fundida, e o
--      vínculo continua com o mesmo controlador e o mesmo percentual;
--   2. sobrevivente já com vínculo: os dela ficam como estavam, os da absorvida não são somados —
--      e aparecem no evento de auditoria da fusão (nada some sem rastro);
--   3. a forma de controle declarada na absorvida não é herdada (seria inferir), mas fica no evento;
--   4. nenhuma pendência de forma ou de papel fica aberta apontando para a entidade absorvida.
--
-- MEDIÇÃO NÃO-VAZIA (regra 2): com `fn_fundir_entidade` voltando ao corpo da 0153 — o número está
-- na mensagem do commit que introduziu este arquivo.
-- =============================================================================

begin;

create or replace function pg_temp.teste_assert_fusao(p_cond boolean, p_nome text, p_detalhe text default null)
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
  v_caso   uuid;
  v_a      uuid;
  v_b      uuid;
  v_irma   uuid;
  v_socio  uuid;
  v_outro  uuid;
  v_n      int;
  v_pct    numeric;
  v_grupo  uuid;
  v_grupo_irma uuid;
  v_forma  entidade_forma_de_controle;
  v_ev     record;
begin
  v_caso := (fn_upsert_caso('0183 — fusao preserva controle'))::uuid;

  raise notice '--- 1. sobrevivente SEM vínculo: o vínculo da absorvida passa para ela ---';
  v_a    := fn_upsert_entidade(v_caso, 'ALFA ZETA MADEIRAS');
  v_b    := fn_upsert_entidade(v_caso, 'BETA OMEGA TRANSPORTES', '11.222.333/0001-81');
  v_irma := fn_upsert_entidade(v_caso, 'GAMA SIGMA COMERCIO');
  v_socio := fn_controlador_registrar(v_caso, 'Socio da Fusao', null, 'fisica', 'teste');
  perform fn_entidade_definir_controlador(v_a, v_socio, 60, 'teste');
  perform fn_entidade_definir_controlador(v_irma, v_socio, 60, 'teste');
  perform fn_entidade_definir_forma_de_controle(v_a, 'controle_comum', 'teste');

  perform fn_fundir_entidade(v_caso, v_a, v_b, 'teste:fusao');

  select g.grupo_id into v_grupo      from fn_grupo_por_controle_comum(v_caso) g where g.entidade_id = v_b;
  select g.grupo_id into v_grupo_irma from fn_grupo_por_controle_comum(v_caso) g where g.entidade_id = v_irma;
  perform pg_temp.teste_assert_fusao(v_grupo is not null and v_grupo = v_grupo_irma,
    'a empresa fundida continua no grupo por controle comum da irmã',
    format('grupo sobrevivente=%s irma=%s', v_grupo, v_grupo_irma));

  select percentual into v_pct from entidade_controlador where entidade_id = v_b and controlador_id = v_socio;
  perform pg_temp.teste_assert_fusao(v_pct = 60,
    'e o vínculo mantém o controlador e o percentual declarados', format('percentual=%s', v_pct));

  select forma_de_controle into v_forma from entidade where id = v_b;
  perform pg_temp.teste_assert_fusao(v_forma = 'indefinido',
    'a forma declarada na absorvida NÃO é herdada — decidir a forma da sobrevivente é humano',
    format('forma=%s', v_forma));

  select antes, depois into v_ev from evento_auditoria
   where acao = 'entidade_fundida' and entidade_ref = 'entidade:' || v_b
   order by criado_em desc limit 1;
  perform pg_temp.teste_assert_fusao(v_ev.antes->>'forma_de_controle' = 'controle_comum',
    'mas a forma que a absorvida tinha fica no evento da fusão', format('antes=%s', v_ev.antes));

  select count(*) into v_n from pendencia
   where caso_id = v_caso and estado <> 'resolvida'
     and motivo in ('forma_de_controle_indefinida:' || v_a, 'papel_no_grupo_indefinido:' || v_a);
  perform pg_temp.teste_assert_fusao(v_n = 0,
    'nenhuma pendência de forma ou de papel fica aberta para a entidade que deixou de existir',
    format('%s abertas', v_n));

  select count(*) into v_n from pendencia
   where caso_id = v_caso and estado <> 'resolvida'
     and motivo = 'forma_de_controle_indefinida:' || v_b;
  perform pg_temp.teste_assert_fusao(v_n = 1,
    'e a da sobrevivente continua aberta — a pergunta sobre ela ninguém respondeu',
    format('%s abertas', v_n));

  raise notice '--- 2. sobrevivente JÁ com vínculo: os dela ficam, os da absorvida vão para o evento ---';
  v_a := fn_upsert_entidade(v_caso, 'DELTA KAPPA INDUSTRIA');
  v_outro := fn_controlador_registrar(v_caso, 'Outro Socio', null, 'fisica', 'teste');
  perform fn_entidade_definir_controlador(v_a, v_outro, 70, 'teste');

  perform fn_fundir_entidade(v_caso, v_a, v_b, 'teste:fusao');

  select count(*), max(percentual) into v_n, v_pct from entidade_controlador where entidade_id = v_b;
  perform pg_temp.teste_assert_fusao(v_n = 1 and v_pct = 60,
    'a declaração da sobrevivente fica como estava — as duas não são somadas',
    format('%s vínculo(s), maior percentual=%s', v_n, v_pct));

  select antes, depois into v_ev from evento_auditoria
   where acao = 'entidade_fundida' and entidade_ref = 'entidade:' || v_b
     and antes->>'entidade_id' = v_a::text;
  perform pg_temp.teste_assert_fusao(
    jsonb_array_length(v_ev.depois->'vinculos_descartados') = 1
    and v_ev.depois->'vinculos_descartados'->0->>'controlador' = 'Outro Socio'
    and (v_ev.depois->'vinculos_descartados'->0->>'percentual')::numeric = 70,
    'e a declaração da absorvida que não foi levada está no evento, com controlador e percentual',
    format('depois=%s', v_ev.depois));

  raise notice 'FUSAO OK — a fusão de entidades leva o controle declarado ou o registra, e não deixa pendência órfã';
end $$;

rollback;
