-- 0020 — Comparação de período por FORMA CANÔNICA (elimina divergência falsa)
-- =============================================================================
-- Achado com o dono (teste v22): a fila de revisão marcava "PERÍODO PODE ESTAR
-- INCORRETO" quando o diagnóstico de conteúdo sugeria o MESMO período do que
-- estava registrado, só que em NOTAÇÃO diferente:
--   registrado "data-base 2025-01-15"  ×  diagnóstico "data-base 15/01/2025"
--   registrado "anual 2025"            ×  diagnóstico "anual 12M25"
-- Ambos são o mesmo período. `fn_registrar_diagnostico` (0010) comparava a
-- STRING crua (`v_periodo_ref_atual is distinct from p_periodo_referencia`),
-- então qualquer diferença de escrita virava uma pendência `periodo_incorreto`
-- que o analista tinha de revisar à toa — o dono pediu que "todos os arquivos
-- sigam a sugestão sem precisar revisar essa parte".
--
-- Fix: uma forma CANÔNICA do período (fn_periodo_canonico) — mesma semântica de
-- `formatarPeriodo` do portal — usada na comparação. Só vira pendência quando
-- os períodos são canonicamente DISTINTOS (divergência real, ex.: 2024 × 2025).
-- Períodos iguais em notações diferentes deixam de gerar pendência e as
-- pendências falsas já abertas AUTO-RESOLVEM na próxima passada do diagnóstico.
-- Mesma assinatura de fn_registrar_diagnostico (0010) — nada mais muda.

-- Expansão de ano de 2 dígitos (pivô 79: 00-79 → 2000-2079; 80-99 → 1980-1999).
create or replace function fn_ano4(a text)
returns text language sql immutable as $$
  select case
    when a is null or a = '' then a
    when length(a) = 4 then a
    when a ~ '^\d{1,2}$' and (a)::int <= 79 then (2000 + (a)::int)::text
    when a ~ '^\d{1,2}$' then (1900 + (a)::int)::text
    else a end;
$$;

-- Forma canônica de (tipo, referencia) — colapsa notações equivalentes do mesmo
-- período num único texto comparável. O `tipo` é ignorado de propósito: a
-- referência já determina o período ("anual 2025" e "outro 2025" são o mesmo).
-- Notações cobertas: ISO (YYYY-MM-DD), data BR (DD/MM/YYYY, DD/MM/YY),
-- N meses/ano (12M25 → ano; 6M2024 → 6m2024), trimestre (1T25 → 1t2025),
-- últimos N meses (L24M), múltiplos exercícios com vírgula (23,24,25 →
-- 2023,2024,2025 ordenados), ano isolado (2 ou 4 dígitos). O que não casar
-- volta como texto normalizado (nunca pior que a comparação crua anterior).
create or replace function fn_periodo_canonico(p_tipo text, p_ref text)
returns text language plpgsql immutable as $$
declare
  r text := lower(trim(coalesce(p_ref, '')));
  m text[]; ano text; n int; toks text[]; t text; acc text[] := '{}';
begin
  if r = '' then return null; end if;
  r := replace(r, ' ', '');

  if r ~ '^\d{4}-\d{2}-\d{2}$' then return r; end if;                    -- ISO YYYY-MM-DD
  m := regexp_match(r, '^(\d{2})/(\d{2})/(\d{4})$');
  if m is not null then return m[3] || '-' || m[2] || '-' || m[1]; end if; -- DD/MM/YYYY
  m := regexp_match(r, '^(\d{2})/(\d{2})/(\d{2})$');
  if m is not null then return fn_ano4(m[3]) || '-' || m[2] || '-' || m[1]; end if; -- DD/MM/YY
  m := regexp_match(r, '^(\d{1,2})m(\d{2,4})$');
  if m is not null then
    ano := fn_ano4(m[2]); n := (m[1])::int;
    return case when n = 12 then ano else n || 'm' || ano end;          -- NM (12M25 → ano)
  end if;
  m := regexp_match(r, '^(\d)t(\d{2,4})$');
  if m is not null then return m[1] || 't' || fn_ano4(m[2]); end if;     -- trimestre (1T25)
  m := regexp_match(r, '^l(\d+)m$');
  if m is not null then return 'l' || m[1] || 'm'; end if;              -- últimos N meses (L24M)

  if position(',' in r) > 0 then                                        -- múltiplos exercícios
    toks := regexp_split_to_array(r, ',');
    foreach t in array toks loop
      t := trim(t);
      if t ~ '^\d{1,2}$' then t := fn_ano4(t); end if;
      if t <> '' then acc := array_append(acc, t); end if;
    end loop;
    acc := (select array_agg(x order by x) from unnest(acc) x);
    return array_to_string(acc, ',');
  end if;

  if r ~ '^\d{4}$' then return r; end if;                               -- ano 4 dígitos
  if r ~ '^\d{2}$' then return fn_ano4(r); end if;                      -- ano 2 dígitos
  return r;                                                             -- texto livre normalizado
end;
$$;

-- Redefinição de fn_registrar_diagnostico (0010) — corpo idêntico, exceto o
-- bloco de PERÍODO, que agora compara pela forma canônica.
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

  -- ----- Período: confere contra o registrado, por FORMA CANÔNICA (0020) -----
  -- Só diverge quando os períodos são canonicamente distintos — notações
  -- diferentes do MESMO período não geram mais pendência falsa.
  select id into v_pendencia_id from pendencia
    where caso_id = v_caso_id and motivo = 'diagnostico:periodo:' || p_documento_id and estado <> 'resolvida'
    limit 1;
  if p_periodo_referencia is not null
     and fn_periodo_canonico(p_periodo_tipo, p_periodo_referencia)
         is distinct from fn_periodo_canonico(v_periodo_tipo_atual, v_periodo_ref_atual) then
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
