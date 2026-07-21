-- =============================================================================
-- Migration 0010 — Diagnóstico de documento + planilha organizada (E1/E2)
--
-- Antes desta migration, a IA só lia o CONTEÚDO do documento quando a
-- classificação por nome do arquivo tinha confiança baixa (fallback). Como a
-- maioria dos arquivos bem nomeados já bate confiança alta só pelo nome, isso
-- significava: (1) entidade nunca era extraída (só o fallback buscava
-- entidade); (2) nenhum diagnóstico de conteúdo rodava (nada conferia se
-- tipo/período do nome batem com o conteúdo real, nem sinalizava qualidade do
-- arquivo); (3) a extração linha a linha (que já rodava sempre, em sombra)
-- vinha achatada, sem organização de planilha.
--
-- `n8n/lib/extract.mjs` (que já rodava para TODO documento) passou a devolver,
-- na MESMA chamada de extração (não aumenta o nº de chamadas à OpenAI): um
-- bloco `diagnostico` (entidade, confere tipo/período, legibilidade real,
-- resumo, justificativa) + linhas com `secao` (agrupador, permite montar uma
-- planilha organizada tipo Ativo Circulante / Passivo Circulante / PL / etc.).
--
-- Doutrina (docs/01): continua N1/sombra — diagnóstico gera PENDÊNCIA tipada
-- para revisão humana (reaproveitando fn_revisar_documento, que já corrige
-- tipo/entidade/período); nunca corrige o documento sozinho (anti-ancoragem).
-- =============================================================================

-- -----------------------------------------------------------------------------
-- Colunas novas.
-- -----------------------------------------------------------------------------
alter table campo_extraido
  add column if not exists secao text;  -- agrupador da planilha (ex.: "Ativo Circulante")
comment on column campo_extraido.secao is
  'Agrupador de planilha extraído pela IA (espelha a estrutura do documento original). Livre, não é enum.';

alter table documento
  add column if not exists resumo text;
comment on column documento.resumo is
  'Resumo objetivo (2-3 frases) do conteúdo do documento, gerado no diagnóstico (E2).';

alter table documento_versao
  add column if not exists nota_legibilidade text;
comment on column documento_versao.nota_legibilidade is
  'Motivo objetivo quando legibilidade != ok (ex.: páginas faltando, digitalização ruim).';

-- -----------------------------------------------------------------------------
-- fn_registrar_campos_extraidos — mesma assinatura de 0005/0006 (sem DROP);
-- agora também grava `secao` por linha.
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
  v_count int := 0;
  v_item jsonb;
begin
  if p_campos is null or jsonb_typeof(p_campos) <> 'array' then
    return 0;
  end if;

  for v_item in select * from jsonb_array_elements(p_campos)
  loop
    insert into campo_extraido
      (documento_versao_id, chave, valor_texto, valor_num, unidade, confianca,
       origem_pagina, origem_linha, nivel_autonomia, secao)
    values (
      p_documento_versao_id,
      coalesce(v_item->>'chave', '(sem rótulo)'),
      v_item->>'valor_texto',
      case when (v_item->>'valor_num') ~ '^-?\d+(\.\d+)?$' then (v_item->>'valor_num')::numeric else null end,
      v_item->>'unidade',
      case when (v_item->>'confianca') ~ '^-?\d+(\.\d+)?$' then (v_item->>'confianca')::numeric else null end,
      case when (v_item->>'origem_pagina') ~ '^\d+$' then (v_item->>'origem_pagina')::int else null end,
      v_item->>'origem_linha',
      p_nivel,
      v_item->>'secao'
    );
    v_count := v_count + 1;
  end loop;

  insert into evento_auditoria (ator, acao, entidade_ref, depois)
    values ('sistema:n8n', 'extracao_sombra', 'documento_versao:'||p_documento_versao_id,
            jsonb_build_object('campos', v_count, 'nivel', p_nivel));

  return v_count;
end;
$$;

-- -----------------------------------------------------------------------------
-- fn_registrar_diagnostico — chamada pelo N8N logo após a extração (E2), com
-- o resultado do bloco `diagnostico` da mesma chamada. Nunca corrige o
-- documento sozinha: só preenche entidade quando ainda não havia nenhuma
-- (fecha uma lacuna, não sobrescreve) e gera PENDÊNCIA tipada — nunca
-- silenciosa — quando o conteúdo diverge do que já está registrado (entidade
-- diferente, tipo não confirmado, período diferente, arquivo ilegível).
-- Idempotente: reaproveita a pendência aberta da mesma checagem em vez de
-- duplicar; auto-resolve quando o diagnóstico deixa de encontrar divergência
-- (ex.: um humano já corrigiu na fila de revisão).
-- -----------------------------------------------------------------------------
create or replace function fn_registrar_diagnostico(
  p_documento_id        uuid,
  p_documento_versao_id uuid,
  p_entidade_nome        text,
  p_tipo_confirma        boolean,
  p_tipo_sugerido        text,
  p_periodo_tipo         text,
  p_periodo_referencia   text,
  p_legibilidade         legibilidade,
  p_nota_legibilidade    text,
  p_resumo               text,
  p_justificativa        text
)
returns jsonb
language plpgsql
as $$
declare
  v_caso_id            uuid;
  v_entidade_id         uuid;
  v_tipo_atual          text;
  v_periodo_id          uuid;
  v_periodo_tipo_atual  text;
  v_periodo_ref_atual   text;
  v_entidade_atual_nome text;
  v_pendencia_id        uuid;
  v_entidade_criada     boolean := false;
begin
  select caso_id, entidade_id, tipo_taxonomia, periodo_id
    into v_caso_id, v_entidade_id, v_tipo_atual, v_periodo_id
  from documento where id = p_documento_id;

  if v_caso_id is null then
    return jsonb_build_object('executado', false, 'motivo', 'documento não encontrado');
  end if;

  if v_periodo_id is not null then
    select tipo, referencia into v_periodo_tipo_atual, v_periodo_ref_atual from periodo where id = v_periodo_id;
  end if;

  -- ----- Entidade: preenche a lacuna se ainda vazia; senão só confere -----
  if p_entidade_nome is not null and length(trim(p_entidade_nome)) > 0 then
    if v_entidade_id is null then
      select id into v_entidade_id from entidade
        where caso_id = v_caso_id and lower(razao_social) = lower(trim(p_entidade_nome)) limit 1;
      if v_entidade_id is null then
        insert into entidade (caso_id, razao_social) values (v_caso_id, trim(p_entidade_nome))
          returning id into v_entidade_id;
      end if;
      update documento set entidade_id = v_entidade_id where id = p_documento_id;
      v_entidade_criada := true;
    else
      select razao_social into v_entidade_atual_nome from entidade where id = v_entidade_id;
      select id into v_pendencia_id from pendencia
        where caso_id = v_caso_id and motivo = 'diagnostico:entidade:' || p_documento_id and estado <> 'resolvida'
        limit 1;
      if lower(trim(coalesce(v_entidade_atual_nome, ''))) <> lower(trim(p_entidade_nome)) then
        if v_pendencia_id is null then
          insert into pendencia (caso_id, origem_estagio, tipo, severidade, sobrepujavel, descricao, documento_id, motivo)
            values (v_caso_id, 'diagnostico', 'entidade_incorreta', 'importante', true,
              format('Diagnóstico de conteúdo sugere entidade "%s", mas o documento está registrado com "%s".',
                     p_entidade_nome, coalesce(v_entidade_atual_nome, '(nenhuma)')),
              p_documento_id, 'diagnostico:entidade:' || p_documento_id);
        end if;
      elsif v_pendencia_id is not null then
        update pendencia set estado = 'resolvida', resolvida_em = now(), resolvida_por = 'sistema:diagnostico'
          where id = v_pendencia_id;
      end if;
    end if;
  end if;

  -- ----- Tipo: confere contra o que já está registrado -----
  select id into v_pendencia_id from pendencia
    where caso_id = v_caso_id and motivo = 'diagnostico:tipo:' || p_documento_id and estado <> 'resolvida'
    limit 1;
  if coalesce(p_tipo_confirma, true) = false
     or (p_tipo_sugerido is not null and p_tipo_sugerido is distinct from v_tipo_atual) then
    if v_pendencia_id is null then
      insert into pendencia (caso_id, origem_estagio, tipo, severidade, sobrepujavel, descricao, documento_id, motivo)
        values (v_caso_id, 'diagnostico', 'tipo_incorreto', 'importante', true,
          format('Diagnóstico de conteúdo sugere tipo "%s" (documento está registrado como "%s"). %s',
                 coalesce(p_tipo_sugerido, '?'), coalesce(v_tipo_atual, '(nenhum)'), coalesce(p_justificativa, '')),
          p_documento_id, 'diagnostico:tipo:' || p_documento_id);
    end if;
  elsif v_pendencia_id is not null then
    update pendencia set estado = 'resolvida', resolvida_em = now(), resolvida_por = 'sistema:diagnostico'
      where id = v_pendencia_id;
  end if;

  -- ----- Período: confere contra o que já está registrado -----
  select id into v_pendencia_id from pendencia
    where caso_id = v_caso_id and motivo = 'diagnostico:periodo:' || p_documento_id and estado <> 'resolvida'
    limit 1;
  if p_periodo_referencia is not null and (
       v_periodo_ref_atual is null
       or v_periodo_ref_atual is distinct from p_periodo_referencia
       or v_periodo_tipo_atual is distinct from p_periodo_tipo
     ) then
    if v_pendencia_id is null then
      insert into pendencia (caso_id, origem_estagio, tipo, severidade, sobrepujavel, descricao, documento_id, motivo)
        values (v_caso_id, 'diagnostico', 'periodo_incorreto', 'importante', true,
          format('Diagnóstico de conteúdo sugere período "%s %s" (documento está registrado com "%s %s").',
                 p_periodo_tipo, p_periodo_referencia, coalesce(v_periodo_tipo_atual, '?'), coalesce(v_periodo_ref_atual, '(nenhum)')),
          p_documento_id, 'diagnostico:periodo:' || p_documento_id);
    end if;
  elsif v_pendencia_id is not null then
    update pendencia set estado = 'resolvida', resolvida_em = now(), resolvida_por = 'sistema:diagnostico'
      where id = v_pendencia_id;
  end if;

  -- ----- Legibilidade real do arquivo -----
  update documento_versao set legibilidade = coalesce(p_legibilidade, legibilidade), nota_legibilidade = p_nota_legibilidade
    where id = p_documento_versao_id;

  select id into v_pendencia_id from pendencia
    where caso_id = v_caso_id and motivo = 'diagnostico:legibilidade:' || p_documento_id and estado <> 'resolvida'
    limit 1;
  if p_legibilidade = 'ilegivel' then
    if v_pendencia_id is null then
      insert into pendencia (caso_id, origem_estagio, tipo, severidade, sobrepujavel, descricao, documento_id, motivo)
        values (v_caso_id, 'diagnostico', 'arquivo_ilegivel', 'importante', true,
          coalesce(p_nota_legibilidade, 'Arquivo sinalizado como ilegível pelo diagnóstico de conteúdo.'),
          p_documento_id, 'diagnostico:legibilidade:' || p_documento_id);
    end if;
  elsif v_pendencia_id is not null then
    update pendencia set estado = 'resolvida', resolvida_em = now(), resolvida_por = 'sistema:diagnostico'
      where id = v_pendencia_id;
  end if;

  -- ----- Resumo (nunca apaga um resumo anterior com uma resposta vazia) -----
  update documento set resumo = coalesce(p_resumo, resumo) where id = p_documento_id;

  insert into evento_auditoria (ator, acao, entidade_ref, depois)
    values ('sistema:diagnostico', 'diagnostico_documento', 'documento:'||p_documento_id,
      jsonb_build_object(
        'entidade', p_entidade_nome, 'tipo_confirma', p_tipo_confirma, 'tipo_sugerido', p_tipo_sugerido,
        'periodo_tipo', p_periodo_tipo, 'periodo_referencia', p_periodo_referencia,
        'legibilidade', p_legibilidade, 'resumo', p_resumo, 'justificativa', p_justificativa));

  return jsonb_build_object('executado', true, 'documento_id', p_documento_id, 'entidade_id', v_entidade_id,
    'entidade_criada', v_entidade_criada);
end;
$$;
