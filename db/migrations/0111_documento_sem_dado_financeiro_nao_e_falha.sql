-- =============================================================================
-- Migration 0111 — Certidão sem número não é extração falha: falta o veredito
--
-- ACHADO no "Teste V45 - Canastra": três documentos do book (certidões
-- negativas, organograma societário, parecer/relatório do auditor
-- independente) abriram pendência `extracao_falhou` ("a chamada respondeu sem
-- erro, mas não trouxe NENHUMA linha"), pedindo para "Contatar o Cliente".
--
-- O PRÓPRIO book, no seu GUIA_DE_TESTE, lista isso como armadilha DELIBERADA:
-- "Documentos sem valor monetário (certidões, organograma, parecer, contrato
-- social) não podem gerar linha financeira." Zero linhas nesses três É o
-- resultado CORRETO da extração — não uma falha.
--
-- A CAUSA: o Sinal 3 de `fn_registrar_campos_extraidos` (0016, reescrito por
-- 0029/0034/0035/0041/0043) dispara `extracao_falhou` sempre que `v_count = 0`,
-- sem distinguir "a chamada não trouxe nada porque falhou/truncou" de "a
-- chamada não trouxe nada porque o documento não tem NENHUM valor monetário a
-- extrair, por natureza". As duas coisas produzem `v_count = 0`, mas só a
-- primeira é falha — e o schema já pedia à IA um diagnóstico rico (entidade,
-- legibilidade, resumo) sem nunca perguntar isto, que é exatamente a pergunta
-- que falta para separar os dois casos.
--
-- A CORREÇÃO tem duas pontas, e as duas precisam existir juntas:
--   1. `n8n/lib/extract.mjs` (SYSTEM_PROMPT + schema) passa a pedir
--      `diagnostico.tem_dado_financeiro` — false SOMENTE quando o documento,
--      por natureza, não tem valor monetário nenhum (certidão, organograma,
--      ata, procuração, parecer de auditoria, contrato sem cifra); true nos
--      demais, inclusive quando a extração falhou em achar o que deveria
--      existir. O mirror embutido em `build-workflow.mjs` (CODE_PARSE_EXTRACAO)
--      e o nó `Gravar Campos (Sombra)` foram atualizados no mesmo commit —
--      REIMPORTAR o workflow depois de aplicar esta migration.
--   2. Aqui: `fn_registrar_campos_extraidos` ganha `p_tem_dado_financeiro`
--      (default null) e só abre `extracao_falhou` por "veio vazia" quando
--      `coalesce(p_tem_dado_financeiro, true)` — ou seja, quando o CHAMADOR
--      não sabe (null, o caso de todo chamador antigo/workflow não reimportado
--      — comportamento IDÊNTICO ao de hoje) ou quando o modelo disse que
--      deveria ter dado. `false` explícito é o único jeito de silenciar a
--      guarda, e só o diagnóstico da própria chamada pode dizer `false`.
--
-- O QUE ISTO NÃO FAZ: não desliga a guarda para nenhum TIPO de documento (não
-- é uma lista de códigos "isentos" na taxonomia) — é por CHAMADA, com o
-- veredito de quem leu o arquivo. Um organograma societário que também traz
-- uma tabela de valores (aconteceria) continua exigindo linha, porque o
-- próprio diagnóstico diria `tem_dado_financeiro: true` para ELE.
-- =============================================================================

create or replace function fn_registrar_campos_extraidos(
  p_documento_versao_id uuid,
  p_campos jsonb,
  p_nivel nivel_autonomia default 'N0',
  p_falha_motivo text default null,
  p_tem_dado_financeiro boolean default null
)
returns int
language plpgsql
as $$
declare
  v_count            int := 0;
  v_item             jsonb;
  v_valor             numeric;
  v_confianca          numeric;
  v_status_aceite      text;
  v_aceito_por         text;
  v_aceito_em          timestamptz;
  v_n_auto_aceitos     int := 0;
  v_documento_id       uuid;
  v_caso_id            uuid;
  v_nome_original      text;
  v_pendencia_id       uuid;
  v_guarda_disparou    boolean := false;
  v_nivel_dial         nivel_autonomia;
  v_limiar             numeric;
  v_auto_permitido     boolean;
  v_g                  jsonb;
begin
  select ea.nivel_atual, ea.limiar_auto_clear into v_nivel_dial, v_limiar
  from estagio_autonomia ea where ea.estagio = 'extracao_linhas_financeiras';
  v_auto_permitido := v_nivel_dial in ('N2', 'N3') and v_limiar is not null;

  if p_campos is not null and jsonb_typeof(p_campos) = 'array' then
    for v_item in select * from jsonb_array_elements(p_campos)
    loop
      v_valor := case when (v_item->>'valor_num') ~ '^-?\d+(\.\d+)?$' then (v_item->>'valor_num')::numeric else null end;
      v_confianca := case when (v_item->>'confianca') ~ '^-?\d+(\.\d+)?$' then (v_item->>'confianca')::numeric else null end;

      v_status_aceite := 'pendente';
      v_aceito_por := null;
      v_aceito_em := null;
      if v_auto_permitido and v_confianca is not null and v_confianca >= v_limiar then
        v_n_auto_aceitos := v_n_auto_aceitos + 1;
      end if;

      insert into campo_extraido
        (documento_versao_id, chave, valor_texto, valor_num, unidade, moeda, confianca,
         origem_pagina, origem_linha, ordem, nivel_autonomia, secao, secao_canonica, entidade_coluna, periodo_coluna,
         status_aceite, aceito_por, aceito_em)
      values (
        p_documento_versao_id,
        coalesce(v_item->>'chave', '(sem rótulo)'),
        v_item->>'valor_texto',
        v_valor,
        v_item->>'unidade',
        v_item->>'moeda',
        v_confianca,
        case when (v_item->>'origem_pagina') ~ '^\d+$' then (v_item->>'origem_pagina')::int else null end,
        v_item->>'origem_linha',
        case when (v_item->>'ordem') ~ '^\d+$' then (v_item->>'ordem')::int else null end,
        p_nivel,
        v_item->>'secao',
        v_item->>'secao_canonica',
        v_item->>'entidade_coluna',
        v_item->>'periodo_coluna',
        v_status_aceite,
        v_aceito_por,
        v_aceito_em
      );
      v_count := v_count + 1;
    end loop;
  end if;

  insert into evento_auditoria (ator, acao, entidade_ref, depois)
    values ('sistema:n8n', 'extracao_sombra', 'documento_versao:'||p_documento_versao_id,
            jsonb_build_object('campos', v_count, 'nivel', p_nivel, 'falha_motivo', p_falha_motivo,
                               'tem_dado_financeiro', p_tem_dado_financeiro, 'auto_aceitos', v_n_auto_aceitos));

  select d.id, d.caso_id, dv.nome_original into v_documento_id, v_caso_id, v_nome_original
  from documento_versao dv join documento d on d.id = dv.documento_id
  where dv.id = p_documento_versao_id;

  if v_documento_id is null then
    insert into evento_auditoria (ator, acao, entidade_ref, depois)
      values ('sistema:n8n', 'extracao_orfa', 'documento_versao:'||coalesce(p_documento_versao_id::text,'null'),
              jsonb_build_object('campos_descartados', v_count, 'falha_motivo', p_falha_motivo,
                                 'porque', 'documento_versao inexistente: campos e motivo nao tinham onde ser gravados'));
    raise warning 'fn_registrar_campos_extraidos: documento_versao % inexistente; % campo(s) e o motivo "%" foram descartados',
      p_documento_versao_id, v_count, coalesce(p_falha_motivo, '(sem motivo)');
    return v_count;
  end if;

  v_g := fn_avaliar_guardas_extracao(p_documento_versao_id);

  if v_count > 0 then
    -- ----- Sinal 1 (0013/0022/0034): mesmo valor material repetido em contas ---
    select id into v_pendencia_id from pendencia
      where caso_id = v_caso_id and motivo = 'extracao:padrao_suspeito:' || v_documento_id and estado <> 'resolvida'
      limit 1;
    if (v_g->>'padrao_suspeito')::boolean then
      v_guarda_disparou := true;
      if v_pendencia_id is null then
        insert into pendencia (caso_id, origem_estagio, tipo, severidade, sobrepujavel, descricao, documento_id, motivo)
          values (v_caso_id, 'extracao', 'extracao_padrao_suspeito', 'importante', true,
            format('%s contas diferentes, na MESMA coluna, vieram com o MESMO valor material (%s) — padrão '
                   'típico de fabricação/alucinação, não de dado real. Conferir contra o arquivo original. '
                   'Contas: %s',
                   v_g->>'n_contas_repetindo', round((v_g->>'valor_repetido')::numeric, 2),
                   array_to_string(array(select jsonb_array_elements_text(v_g->'rotulos_repetindo')), '; ')),
            v_documento_id, 'extracao:padrao_suspeito:' || v_documento_id);
      end if;
    elsif v_pendencia_id is not null then
      update pendencia set estado = 'resolvida', resolvida_em = now(), resolvida_por = 'sistema:extracao'
        where id = v_pendencia_id;
    end if;

    -- ----- Sinal 2 (0013): parcela relevante das linhas com confiança baixa ----
    select id into v_pendencia_id from pendencia
      where caso_id = v_caso_id and motivo = 'extracao:baixa_confianca:' || v_documento_id and estado <> 'resolvida'
      limit 1;
    if (v_g->>'baixa_confianca')::boolean then
      v_guarda_disparou := true;
      if v_pendencia_id is null then
        insert into pendencia (caso_id, origem_estagio, tipo, severidade, sobrepujavel, descricao, documento_id, motivo)
          values (v_caso_id, 'extracao', 'extracao_baixa_confianca', 'importante', true,
            format('%s de %s linhas extraídas vieram com confiança abaixo de 70%%. Revisar antes de aceitar.',
                   v_g->>'n_baixa_confianca', v_count),
            v_documento_id, 'extracao:baixa_confianca:' || v_documento_id);
      end if;
    elsif v_pendencia_id is not null then
      update pendencia set estado = 'resolvida', resolvida_em = now(), resolvida_por = 'sistema:extracao'
        where id = v_pendencia_id;
    end if;
  end if;

  -- ----- Sinal 3 (0016/0029, unidade corrigida por 0111) ---------------------
  -- "veio vazia" só é sinal de FALHA quando ninguém disse o contrário. Um
  -- chamador antigo (workflow não reimportado) manda `p_tem_dado_financeiro`
  -- null, e o comportamento é IDÊNTICO ao de antes desta migration
  -- (coalesce(null, true) = true). Só o diagnóstico da própria chamada, com
  -- `false` explícito, prova que zero linhas era o resultado certo.
  select id into v_pendencia_id from pendencia
    where caso_id = v_caso_id and motivo = 'extracao:falhou:' || v_documento_id and estado <> 'resolvida'
    limit 1;
  if p_falha_motivo is not null or (v_count = 0 and coalesce(p_tem_dado_financeiro, true)) then
    v_guarda_disparou := true;
    if v_pendencia_id is null then
      insert into pendencia (caso_id, origem_estagio, tipo, severidade, sobrepujavel, descricao, documento_id, motivo)
        values (v_caso_id, 'extracao', 'extracao_falhou', 'importante', true,
          format('Extração de "%s" falhou ou veio incompleta (%s linhas gravadas). Motivo: %s',
                 coalesce(v_nome_original, '?'), v_count,
                 coalesce(p_falha_motivo,
                          'a chamada respondeu sem erro, mas não trouxe NENHUMA linha. '
                          'Causa mais comum: formato que o pipeline ainda não converte em texto '
                          '(.xlsx/.docx) — nesses casos a IA recebe um aviso em vez do arquivo.')),
          v_documento_id, 'extracao:falhou:' || v_documento_id);
    end if;
  elsif v_pendencia_id is not null then
    update pendencia set estado = 'resolvida', resolvida_em = now(), resolvida_por = 'sistema:extracao'
      where id = v_pendencia_id;
  end if;

  -- ----- Auto-aceite (0029): DEPOIS das guardas, nunca antes -----------------
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
        format('%s linha(s) auto-aceitas na extração de "%s" — dial %s, limiar %s, nenhuma guarda disparou.',
               v_n_auto_aceitos, coalesce(v_nome_original, '?'), v_nivel_dial, v_limiar),
        jsonb_build_object('documento_id', v_documento_id, 'documento_versao_id', p_documento_versao_id,
                           'n_auto_aceitos', v_n_auto_aceitos));
  elsif v_n_auto_aceitos > 0 then
    insert into evento_auditoria (ator, acao, entidade_ref, depois)
      values ('sistema:auto_aceite', 'auto_aceite_suprimido', 'documento_versao:'||p_documento_versao_id,
              jsonb_build_object('n_elegiveis', v_n_auto_aceitos,
                                 'porque', 'guarda de extracao disparou; linhas seguem pendentes de revisao humana'));
  end if;

  perform fn_recomputar_completude(v_caso_id);

  return v_count;
end;
$$;

comment on function fn_registrar_campos_extraidos(uuid, jsonb, nivel_autonomia, text, boolean) is
  'Grava campos extraídos e roda as três guardas (0043: fn_avaliar_guardas_extracao). Sinal 3 '
  '("veio vazia") só dispara extracao_falhou quando p_tem_dado_financeiro não é explicitamente '
  'false — 0111: documento sem valor monetário por natureza (certidão, organograma, parecer de '
  'auditoria) não é falha de extração.';

grant execute on function fn_registrar_campos_extraidos(uuid, jsonb, nivel_autonomia, text, boolean) to authenticated;

-- Assinatura antiga (0016) fora: um parâmetro NOVO cria OVERLOAD em vez de
-- substituir (é a assinatura, não o corpo, que identifica a função) — mesmo
-- padrão de limpeza que a 0017 fez ao acrescentar `p_falha_motivo`. Sem isto,
-- as duas versões convivem e um chamador com 4 argumentos continuaria caindo
-- na função VELHA, com o Sinal 3 de sempre.
drop function if exists fn_registrar_campos_extraidos(uuid, jsonb, nivel_autonomia, text);
