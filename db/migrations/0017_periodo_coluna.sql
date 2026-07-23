-- =============================================================================
-- Migration 0017 — Suporte a documentos COMPARATIVOS (colunas de período)
--
-- Lacuna encontrada testando o export (sessão 7 cont.⁹, HANDOFF.md): uma
-- demonstração comparativa — o padrão em contabilidade, ex. "Balanço
-- consolidado 2023 x 2024.pdf" com as colunas 2023 e 2024 lado a lado da MESMA
-- entidade — colapsava as duas colunas de ano numa só no export. O
-- `campo_extraido` só tinha a dimensão de entidade (`entidade_coluna`, 0014),
-- não de período: a extração emitia duas linhas "Caixa" (uma por ano) e, como
-- a coluna do export era `entidade × período-do-documento` (período único,
-- vindo de `documento.periodo_id`), as duas caíam na MESMA coluna e uma
-- sobrescrevia a outra — PERDA DE DADO, além de deixar o export inútil para
-- quem faz modelagem (análise horizontal/vertical exige os anos lado a lado).
--
-- `n8n/lib/extract.mjs` (schema + prompt) agora pede: quando o documento tem
-- várias colunas de período lado a lado, uma LINHA POR (conta × período) —
-- mesmo "chave", com `periodo_coluna` = rótulo exato da coluna ("2023",
-- "31/12/2024"...). É ORTOGONAL a `entidade_coluna`: um documento pode ter as
-- duas dimensões (várias empresas E vários anos). Em documentos de período
-- único (o caso comum), `periodo_coluna` fica null e o export usa o período do
-- próprio documento (comportamento de antes, sem regressão).
-- =============================================================================

alter table campo_extraido
  add column if not exists periodo_coluna text;
comment on column campo_extraido.periodo_coluna is
  'Rótulo da coluna de período a que esta linha pertence, quando o documento é comparativo e traz '
  'vários períodos lado a lado na mesma tabela (ex.: "2023" e "2024"). Null quando o documento é de '
  'período único (caso comum) — aí o período vem de documento.periodo_id. Ortogonal a entidade_coluna: '
  'um documento pode ter as duas dimensões (várias empresas E vários anos).';

-- -----------------------------------------------------------------------------
-- Limpeza de schema: a migration 0016 adicionou `p_falha_motivo` à assinatura
-- via `create or replace`, mas mudar o NÚMERO de parâmetros faz o Postgres
-- CRIAR UMA NOVA sobrecarga (4 params) em vez de substituir a antiga (3
-- params, de 0013/0014). As duas passaram a coexistir e uma chamada posicional
-- de 2 args fica AMBÍGUA (erro "is not unique") — só não estourou em produção
-- porque o N8N chama com o parâmetro nomeado `p_falha_motivo=>`. Derruba a
-- sobrecarga morta de 3 params antes de recriar a de 4, deixando UMA função só.
-- (mesmo tipo de cruft anotado em HANDOFF para fn_registrar_documento.)
-- -----------------------------------------------------------------------------
drop function if exists fn_registrar_campos_extraidos(uuid, jsonb, nivel_autonomia);

-- -----------------------------------------------------------------------------
-- fn_registrar_campos_extraidos — mesma assinatura de 0016 (p_falha_motivo);
-- agora também grava `periodo_coluna` por linha. Corpo idêntico ao de 0016
-- (guardas de padrão suspeito / baixa confiança / extração falhou preservadas),
-- só acrescenta a coluna nova no insert.
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
         origem_pagina, origem_linha, nivel_autonomia, secao, secao_canonica, entidade_coluna, periodo_coluna)
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
        v_item->>'secao_canonica',
        v_item->>'entidade_coluna',
        v_item->>'periodo_coluna'
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

  select d.id, d.caso_id, dv.nome_original into v_documento_id, v_caso_id, v_nome_original
  from documento_versao dv join documento d on d.id = dv.documento_id
  where dv.id = p_documento_versao_id;

  if v_documento_id is null then
    return v_count; -- nunca deveria acontecer (FK), mas não trava a extração por causa da guarda
  end if;

  if v_count > 0 then
    -- ----- Sinal 1 (0013): mesmo valor não-zero repetido em muitas contas -----
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

    -- ----- Sinal 2 (0013): parcela relevante das linhas com confiança baixa -----
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

  -- ----- Sinal 3 (0016): a própria chamada de extração falhou/veio truncada -----
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
