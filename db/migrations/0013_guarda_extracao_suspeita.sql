-- =============================================================================
-- Migration 0013 — Guarda de segurança: detectar extração suspeita (E2)
--
-- Achado testando com um documento real (sessão 7, HANDOFF.md): um balanço
-- combinado de 3 entidades (múltiplas colunas numéricas por linha, sufixo D/C
-- colado no número) fez a extração (gpt-4o) fabricar ~20 contas com o MESMO
-- valor exato repetido ("1.234.567,00"), tudo com confiança declarada ALTA
-- (0.99-1.0). Nada no pipeline hoje detecta esse padrão — a linha entra em
-- campo_extraido igual a qualquer outra, só some do radar se alguém conferir
-- célula a célula contra o PDF original.
--
-- Esta migration NÃO resolve a causa raiz (documentos multi-entidade — isso é
-- uma fatia maior, de schema/prompt). É uma rede de segurança BARATA e GERAL:
-- depois de gravar os campos extraídos de um documento_versao, verifica dois
-- sinais de baixa confiabilidade da extração inteira (não célula a célula) e
-- gera pendência tipada — nunca corrige nada sozinha (doutrina docs/01,
-- anti-ancoragem; a linha segue pendente/âmbar no export até o aceite humano
-- de qualquer forma — isto só torna o problema VISÍVEL antes de alguém aceitar
-- às cegas):
--   1. `extracao_padrao_suspeito` (novo): 4+ contas DISTINTAS com o EXATO
--      mesmo valor não-zero na mesma extração — praticamente impossível em
--      dado real, típico de fabricação/alucinação.
--   2. `extracao_baixa_confianca` (enum já existia em 0001, nunca tinha sido
--      usado): parcela relevante das linhas com confiança abaixo do
--      threshold (0.7, mesmo padrão de fn_registrar_documento).
-- =============================================================================

alter type pendencia_tipo add value if not exists 'extracao_padrao_suspeito';

-- -----------------------------------------------------------------------------
-- fn_registrar_campos_extraidos — mesma assinatura de 0005/0006/0010/0012
-- (sem DROP). Guarda os valores/confianças da PRÓPRIA chamada (não relê
-- campo_extraido inteiro — evita misturar com uma extração anterior) para
-- calcular os dois sinais depois do loop de insert.
-- -----------------------------------------------------------------------------
create or replace function fn_registrar_campos_extraidos(
  p_documento_versao_id uuid,
  p_campos jsonb,
  p_nivel nivel_autonomia default 'N0'
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
  v_pendencia_id       uuid;
begin
  if p_campos is null or jsonb_typeof(p_campos) <> 'array' then
    return 0;
  end if;

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

  insert into evento_auditoria (ator, acao, entidade_ref, depois)
    values ('sistema:n8n', 'extracao_sombra', 'documento_versao:'||p_documento_versao_id,
            jsonb_build_object('campos', v_count, 'nivel', p_nivel));

  if v_count = 0 then
    return v_count;
  end if;

  select d.id, d.caso_id into v_documento_id, v_caso_id
  from documento_versao dv join documento d on d.id = dv.documento_id
  where dv.id = p_documento_versao_id;

  if v_documento_id is null then
    return v_count; -- nunca deveria acontecer (FK), mas não trava a extração por causa da guarda
  end if;

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

  return v_count;
end;
$$;
