-- =============================================================================
-- Migration 0016 — Guarda de segurança: extração que falhou/veio vazia (E2)
--
-- Achado testando em produção (sessão 7 cont.⁷, HANDOFF.md): um lote de 16
-- documentos ("teste v14") foi classificado com sucesso (tipo/entidade/período
-- gravados, confiança 90-95%, fonte openai_conteudo) mas NENHUMA linha foi
-- extraída para nenhum deles — a exportação saiu com "Linhas totais
-- extraídas: 0" e a Reconciliação (Classe A) só apontou pré-condição não
-- satisfeita (sem dado nenhum pra conferir). O n8n mostrava sucesso em TODOS
-- os nós, e reprocessar não mudava nada.
--
-- Causa: classificação e extração são DUAS chamadas OpenAI separadas e
-- sequenciais por documento (n8n/build-workflow.mjs). A de extração pede um
-- array `linhas` sem limite de tamanho (documentos combinados grandes — grupo
-- com várias entidades/demonstrações no mesmo PDF — podem precisar de uma
-- saída JSON enorme). Sem `max_tokens` explícito, e sem nenhuma checagem de
-- `finish_reason`, uma resposta truncada (finish_reason=length) vira um JSON
-- incompleto que falha o parse — e n8n/lib/extract.mjs (e o mirror em
-- build-workflow.mjs) simplesmente devolvia `campos: []`, sem sinalizar nada.
-- fn_registrar_campos_extraidos (0013) tratava array vazio como "0 campos,
-- sucesso" e retornava cedo, sem checar NADA — a falha inteira ficava
-- invisível em todo o pipeline (n8n verde, documento/reconciliação sem pista
-- do motivo real).
--
-- Esta migration fecha essa lacuna (o fix de `max_tokens` está no código do
-- n8n/lib/extract.mjs e build-workflow.mjs — precisa REIMPORTAR o workflow):
--   1. Novo parâmetro `p_falha_motivo` (opcional, default null) — o n8n agora
--      manda um motivo textual quando a chamada de extração errou, veio
--      truncada ou o JSON foi inválido (null quando ok).
--   2. Novo tipo `extracao_falhou` (severidade importante, sobrepujável):
--      gerado sempre que p_falha_motivo não é null, MESMO com 0 campos —
--      idempotente pelo mesmo padrão de motivo dos outros dois sinais (0013),
--      auto-resolve quando uma reextração subsequente vier ok.
--   3. A checagem de documento/caso, que antes só rodava se v_count > 0,
--      agora roda sempre (precisa existir mesmo com 0 campos para poder
--      registrar a pendência).
-- =============================================================================

alter type pendencia_tipo add value if not exists 'extracao_falhou';

-- -----------------------------------------------------------------------------
-- fn_registrar_campos_extraidos — mesma assinatura de 0005/0006/0010/0012/0013
-- + `p_falha_motivo` no final (default null, não quebra chamadores antigos).
-- -----------------------------------------------------------------------------
create or replace function fn_registrar_campos_extraidos(
  p_documento_versao_id uuid,
  p_campos jsonb,
  p_nivel nivel_autonomia default 'N0',
  p_falha_motivo text default null
)
returns int
language plpgsql
as $$
declare
  v_count            int := 0;
  v_item             jsonb;
  v_valor             numeric;
  v_confianca          numeric;
  v_valores_nao_zero   numeric[] := '{}';
  v_n_baixa_confianca  int := 0;
  v_max_repeticoes     int := 0;
  v_valor_repetido      numeric;
  v_documento_id       uuid;
  v_caso_id            uuid;
  v_nome_original      text;
  v_pendencia_id       uuid;
begin
  if p_campos is not null and jsonb_typeof(p_campos) = 'array' then
    for v_item in select * from jsonb_array_elements(p_campos)
    loop
      v_valor := case when (v_item->>'valor_num') ~ '^-?\d+(\.\d+)?$' then (v_item->>'valor_num')::numeric else null end;
      v_confianca := case when (v_item->>'confianca') ~ '^-?\d+(\.\d+)?$' then (v_item->>'confianca')::numeric else null end;

      insert into campo_extraido
        (documento_versao_id, chave, valor_texto, valor_num, unidade, confianca,
         origem_pagina, origem_linha, nivel_autonomia, secao, secao_canonica)
      values (
        p_documento_versao_id,
        coalesce(v_item->>'chave', '(sem rótulo)'),
        v_item->>'valor_texto',
        v_valor,
        v_item->>'unidade',
        v_confianca,
        case when (v_item->>'origem_pagina') ~ '^\d+$' then (v_item->>'origem_pagina')::int else null end,
        v_item->>'origem_linha',
        p_nivel,
        v_item->>'secao',
        v_item->>'secao_canonica'
      );
      v_count := v_count + 1;

      if v_valor is not null and v_valor <> 0 then
        v_valores_nao_zero := array_append(v_valores_nao_zero, v_valor);
      end if;
      if v_confianca is not null and v_confianca < 0.7 then
        v_n_baixa_confianca := v_n_baixa_confianca + 1;
      end if;
    end loop;
  end if;

  insert into evento_auditoria (ator, acao, entidade_ref, depois)
    values ('sistema:n8n', 'extracao_sombra', 'documento_versao:'||p_documento_versao_id,
            jsonb_build_object('campos', v_count, 'nivel', p_nivel, 'falha_motivo', p_falha_motivo));

  -- precisa do documento/caso mesmo com v_count=0, para poder registrar a
  -- pendência de falha de extração (sinal 3, abaixo).
  select d.id, d.caso_id, dv.nome_original into v_documento_id, v_caso_id, v_nome_original
  from documento_versao dv join documento d on d.id = dv.documento_id
  where dv.id = p_documento_versao_id;

  if v_documento_id is null then
    return v_count; -- nunca deveria acontecer (FK), mas não trava a extração por causa da guarda
  end if;

  if v_count > 0 then
    -- ----- Sinal 1: mesmo valor não-zero repetido em muitas contas -----
    select v.valor, count(*) into v_valor_repetido, v_max_repeticoes
    from unnest(v_valores_nao_zero) as v(valor)
    group by v.valor
    order by count(*) desc
    limit 1;

    select id into v_pendencia_id from pendencia
      where caso_id = v_caso_id and motivo = 'extracao:padrao_suspeito:' || p_documento_versao_id and estado <> 'resolvida'
      limit 1;
    if coalesce(v_max_repeticoes, 0) >= 4 then
      if v_pendencia_id is null then
        insert into pendencia (caso_id, origem_estagio, tipo, severidade, sobrepujavel, descricao, documento_id, motivo)
          values (v_caso_id, 'extracao', 'extracao_padrao_suspeito', 'importante', true,
            format('%s contas diferentes vieram com o MESMO valor extraído (%s) — padrão típico de fabricação/'
                   'alucinação, não de dado real. Conferir a extração contra o arquivo original antes de aceitar.',
                   v_max_repeticoes, round(v_valor_repetido, 2)),
            v_documento_id, 'extracao:padrao_suspeito:' || p_documento_versao_id);
      end if;
    elsif v_pendencia_id is not null then
      update pendencia set estado = 'resolvida', resolvida_em = now(), resolvida_por = 'sistema:extracao'
        where id = v_pendencia_id;
    end if;

    -- ----- Sinal 2: parcela relevante das linhas com confiança baixa -----
    select id into v_pendencia_id from pendencia
      where caso_id = v_caso_id and motivo = 'extracao:baixa_confianca:' || p_documento_versao_id and estado <> 'resolvida'
      limit 1;
    if v_n_baixa_confianca >= 3 and v_n_baixa_confianca::numeric / v_count >= 0.3 then
      if v_pendencia_id is null then
        insert into pendencia (caso_id, origem_estagio, tipo, severidade, sobrepujavel, descricao, documento_id, motivo)
          values (v_caso_id, 'extracao', 'extracao_baixa_confianca', 'importante', true,
            format('%s de %s linhas extraídas vieram com confiança abaixo de 70%%. Revisar antes de aceitar.',
                   v_n_baixa_confianca, v_count),
            v_documento_id, 'extracao:baixa_confianca:' || p_documento_versao_id);
      end if;
    elsif v_pendencia_id is not null then
      update pendencia set estado = 'resolvida', resolvida_em = now(), resolvida_por = 'sistema:extracao'
        where id = v_pendencia_id;
    end if;
  end if;

  -- ----- Sinal 3: a própria chamada de extração falhou/veio truncada -----
  -- Roda MESMO com v_count=0 (é justamente o caso mais comum desse sinal: a
  -- extração inteira falhou e não sobrou nenhuma linha). Idempotente pelo
  -- mesmo motivo do documento_versao — reprocessar substitui a pendência
  -- aberta em vez de duplicar; se uma extração seguinte vier ok (p_falha_motivo
  -- null), a pendência aberta se auto-resolve.
  select id into v_pendencia_id from pendencia
    where caso_id = v_caso_id and motivo = 'extracao:falhou:' || p_documento_versao_id and estado <> 'resolvida'
    limit 1;
  if p_falha_motivo is not null then
    if v_pendencia_id is null then
      insert into pendencia (caso_id, origem_estagio, tipo, severidade, sobrepujavel, descricao, documento_id, motivo)
        values (v_caso_id, 'extracao', 'extracao_falhou', 'importante', true,
          format('Extração de "%s" falhou ou veio incompleta (%s linhas gravadas). Motivo: %s',
                 coalesce(v_nome_original, '?'), v_count, p_falha_motivo),
          v_documento_id, 'extracao:falhou:' || p_documento_versao_id);
    end if;
  elsif v_pendencia_id is not null then
    update pendencia set estado = 'resolvida', resolvida_em = now(), resolvida_por = 'sistema:extracao'
      where id = v_pendencia_id;
  end if;

  return v_count;
end;
$$;
