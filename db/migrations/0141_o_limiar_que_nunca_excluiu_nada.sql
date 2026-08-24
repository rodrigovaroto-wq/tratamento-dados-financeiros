-- 0141 — O LIMIAR DE AUTO-ACEITE NUNCA EXCLUIU NADA, E A TRILHA PASSA A DIZER ISSO.
--
-- MEDIDO EM 24/08, sobre as 15.030 linhas que este sistema já gravou:
--
--   • a confiança auto-reportada pela IA assumiu TRÊS valores em toda a história
--     do banco: 0,95, 0,99 e 1;
--   • o limiar de auto-aceite de `extracao_linhas_financeiras` é 0,95;
--   • logo `confianca >= v_limiar` é satisfeito por TODA linha que já existiu, e
--     14.470 das 15.030 foram auto-aceitas — as outras 560 barradas por GUARDA,
--     nunca por confiança;
--   • e a guarda de baixa confiança (Sinal 2, limiar 0,70) nunca disparou, pelo
--     mesmo motivo: ZERO linhas abaixo de 0,70 em toda a história.
--
-- O limiar é exatamente o PISO do que o modelo emite. Não é um filtro: é uma
-- formalidade. Dois mecanismos de segurança estão inertes, e nenhuma tela diz.
--
-- O QUE ESTA MIGRATION FAZ, E O QUE ELA DELIBERADAMENTE NÃO FAZ. Ela NÃO muda
-- comportamento — decisão do dono, 24/08: bloquear o auto-aceite mandaria ~96%
-- das linhas para revisão humana, o que é uma decisão de operação e não de
-- engenharia. O que ela muda é que a decisão de auto-aceite passa a REGISTRAR
-- quantas linhas o limiar excluiu, e quando exclui zero diz isso com todas as
-- letras. Um portão que aprova tudo e não declara que aprovou tudo é pior que
-- portão nenhum: ele parece funcionar.
--
-- POR QUE ESTA MIGRATION É UM PATCH E NÃO UMA REEMISSÃO INTEIRA. A doutrina da
-- 0103 manda reemitir a função completa, e ela está certa na maioria dos casos.
-- Aqui a função tem 200 linhas e o que muda são DUAS: transcrevê-la à mão para
-- alterar duas linhas troca um risco pequeno (patch que não encontra a âncora,
-- e que aqui FALHA ALTO) por um risco grande e silencioso (um caractere errado
-- no meio da função que grava toda linha extraída do sistema).
--
-- Por isso o patch se recusa a agir às cegas: se qualquer âncora não for
-- encontrada — porque uma migration futura reescreveu o bloco —, ele levanta
-- exceção em vez de não fazer nada. E confere o resultado depois de aplicar.

do $mig$
declare
  v_src text; v_novo text; v_ini int; v_fim int; v_decl int;
begin
  select pg_get_functiondef(p.oid) into v_src
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public' and p.proname = 'fn_registrar_campos_extraidos';

  if v_src is null then
    raise exception '0141: fn_registrar_campos_extraidos não existe — migration fora de ordem';
  end if;

  -- As três âncoras. Falhar aqui é o comportamento DESEJADO: significa que o
  -- bloco mudou de forma e que este patch precisa ser relido por gente.
  v_ini  := position('  -- ----- Auto-aceite (0029)' in v_src);
  v_fim  := position('  perform fn_recomputar_completude' in v_src);
  v_decl := position('  v_g                  jsonb;' in v_src);
  if v_ini = 0 or v_fim = 0 or v_fim <= v_ini or v_decl = 0 then
    raise exception '0141: âncoras não encontradas (ini=%, fim=%, decl=%) — o bloco de auto-aceite mudou de forma',
      v_ini, v_fim, v_decl;
  end if;

  v_novo := substring(v_src from 1 for v_decl - 1)
         || '  v_n_excluidas        int := 0;' || chr(13) || chr(10)
         || substring(v_src from v_decl for (v_ini - v_decl))
         || $novo$  -- ----- Auto-aceite (0029): DEPOIS das guardas, nunca antes -----------------
  --
  -- 0141: E A TRILHA PASSA A DIZER QUANTO O LIMIAR FILTROU, porque medido em
  -- 24/08 ele nunca filtrou nada. Em 15.030 linhas gravadas por este sistema, a
  -- confiança auto-reportada assumiu TRÊS valores — 0,95, 0,99 e 1 — e o limiar
  -- de `extracao_linhas_financeiras` é 0,95. O limiar é exatamente o PISO do que
  -- o modelo já emitiu: `confianca >= v_limiar` é satisfeito por toda linha que
  -- já existiu, e 14.470 das 15.030 foram auto-aceitas (as outras 560 foram
  -- barradas por GUARDA, não por confiança).
  --
  -- A guarda de baixa confiança (Sinal 2, limiar 0,70) nunca disparou pelo mesmo
  -- motivo: zero linhas abaixo de 0,70 em toda a história do banco.
  --
  -- Isto NÃO muda comportamento — decisão do dono, 24/08. O que muda é que a
  -- decisão passa a registrar quantas linhas o limiar excluiu. Quando exclui
  -- zero, ela diz isso com todas as letras, porque um portão que aprova tudo e
  -- não declara que aprovou tudo é pior que portão nenhum: ele parece funcionar.
  v_n_excluidas := greatest(v_count - v_n_auto_aceitos, 0);
  if v_n_auto_aceitos > 0 and not v_guarda_disparou then
    update campo_extraido
      set status_aceite = 'aceito',
          aceito_por = format('sistema:auto_aceite (dial %s, limiar %s, sem guarda disparada)',
                              v_nivel_dial, v_limiar),
          aceito_em = now()
      where documento_versao_id = p_documento_versao_id
        and confianca >= v_limiar
        and status_aceite = 'pendente';

    insert into decisao (caso_id, tipo, autor, motivo, payload)
      values (v_caso_id, 'aprovacao', 'sistema:auto_aceite',
        format('%s linha(s) auto-aceitas na extração de "%s" — dial %s, limiar %s, nenhuma guarda disparou. %s',
               v_n_auto_aceitos, coalesce(v_nome_original, '?'), v_nivel_dial, v_limiar,
               case when v_n_excluidas = 0
                 then format('O limiar NAO excluiu nenhuma das %s linhas: a confiança auto-reportada não '
                             'discriminou nada nesta versão, e o que barra linha aqui são as guardas.', v_count)
                 else format('O limiar deixou %s de %s linha(s) pendentes.', v_n_excluidas, v_count)
               end),
        jsonb_build_object('documento_id', v_documento_id, 'documento_versao_id', p_documento_versao_id,
                           'n_auto_aceitos', v_n_auto_aceitos,
                           'n_excluidas_pelo_limiar', v_n_excluidas,
                           'limiar_discriminou', v_n_excluidas > 0));
  elsif v_n_auto_aceitos > 0 then
    insert into evento_auditoria (ator, acao, entidade_ref, depois)
      values ('sistema:auto_aceite', 'auto_aceite_suprimido', 'documento_versao:'||p_documento_versao_id,
              jsonb_build_object('n_elegiveis', v_n_auto_aceitos,
                                 'n_excluidas_pelo_limiar', v_n_excluidas,
                                 'limiar_discriminou', v_n_excluidas > 0,
                                 'porque', 'guarda de extracao disparou; linhas seguem pendentes de revisao humana'));
  end if;$novo$
         || chr(13) || chr(10)
         || substring(v_src from v_fim);

  execute v_novo;

  -- Confere o resultado em vez de confiar nele.
  select pg_get_functiondef(p.oid) into v_src
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public' and p.proname = 'fn_registrar_campos_extraidos';
  if position('n_excluidas_pelo_limiar' in v_src) = 0
     or position('v_n_excluidas        int := 0;' in v_src) = 0 then
    raise exception '0141: a função foi recriada sem a declaração do limiar — abortado';
  end if;
end $mig$;
