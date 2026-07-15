-- =============================================================================
-- Migration 0005 — Extração (E2) em modo SOMBRA (N0)
--
-- Adiciona a tabela campo_extraido (f0/05) e as funções que a alimentam.
-- Doutrina (docs/01, f0/04): extração de linhas financeiras NASCE em N0 (sombra)
-- — registra a sugestão, NÃO decide, NÃO entra em base sem aceite humano
-- (anti-ancoragem). Serve para começar a MEDIR a qualidade desde já.
--
-- Também redefine fn_registrar_documento para retornar { documento_id,
-- documento_versao_id } (o E2 precisa da versão para ancorar os campos).
-- =============================================================================

-- -----------------------------------------------------------------------------
-- Tabela de campos extraídos (com proveniência e confiança) — f0/05, f0/07
-- -----------------------------------------------------------------------------
create table if not exists campo_extraido (
  id                   uuid primary key default gen_random_uuid(),
  documento_versao_id  uuid not null references documento_versao(id) on delete cascade,
  chave                text not null,           -- rótulo da linha (ex.: 'Receita líquida')
  valor_texto          text,                    -- valor como veio
  valor_num            numeric,                 -- valor normalizado, quando numérico
  unidade              text,                    -- ex.: 'BRL', 'milhares'
  confianca            numeric,                 -- score de extração
  origem_pagina        int,
  origem_linha         text,
  nivel_autonomia      nivel_autonomia not null default 'N0',  -- sombra
  revisado_por         text,                    -- null = ainda não revisado
  criado_em            timestamptz not null default now()
);
create index if not exists idx_campo_docversao on campo_extraido(documento_versao_id);

alter table campo_extraido enable row level security;
create policy campo_extraido_authenticated_all on campo_extraido
  for all to authenticated using (true) with check (true);

-- -----------------------------------------------------------------------------
-- Redefine fn_registrar_documento para devolver os DOIS ids (jsonb).
-- (Corpo idêntico ao de 0004, só muda o retorno.) Mudar o tipo de retorno
-- exige DROP antes (Postgres não permite via create or replace).
-- -----------------------------------------------------------------------------
drop function if exists fn_registrar_documento(
  uuid, text, text, text, text, numeric, text, origem_arquivo, text, text, boolean, text, legibilidade, numeric
);

create or replace function fn_registrar_documento(
  p_caso_id        uuid,
  p_entidade_nome  text,
  p_periodo_tipo   text,
  p_periodo_ref    text,
  p_tipo_taxonomia text,
  p_confianca      numeric,
  p_fonte          text,
  p_origem_arquivo origem_arquivo,
  p_arquivo_ref    text,
  p_nome_original  text,
  p_assinado       boolean,
  p_hash           text,
  p_legibilidade   legibilidade,
  p_threshold      numeric default 0.7
)
returns jsonb
language plpgsql
as $$
declare
  v_entidade_id uuid;
  v_periodo_id  uuid;
  v_documento_id uuid;
  v_versao_id   uuid;
  v_obrig obrigatoriedade;
begin
  if p_entidade_nome is not null and length(trim(p_entidade_nome)) > 0 then
    select id into v_entidade_id from entidade
      where caso_id = p_caso_id and lower(razao_social) = lower(p_entidade_nome) limit 1;
    if v_entidade_id is null then
      insert into entidade (caso_id, razao_social) values (p_caso_id, p_entidade_nome)
        returning id into v_entidade_id;
    end if;
  end if;

  if p_periodo_ref is not null and length(trim(p_periodo_ref)) > 0 then
    select id into v_periodo_id from periodo
      where caso_id = p_caso_id and tipo = coalesce(p_periodo_tipo,'outro') and referencia = p_periodo_ref limit 1;
    if v_periodo_id is null then
      insert into periodo (caso_id, tipo, referencia)
        values (p_caso_id, coalesce(p_periodo_tipo,'outro'), p_periodo_ref)
        returning id into v_periodo_id;
    end if;
  end if;

  insert into documento (caso_id, entidade_id, periodo_id, tipo_taxonomia, status)
    values (p_caso_id, v_entidade_id, v_periodo_id, p_tipo_taxonomia, 'em_validacao')
    returning id into v_documento_id;

  insert into documento_versao
    (documento_id, origem_arquivo, arquivo_ref, nome_original, assinado, hash, legibilidade)
    values (v_documento_id, coalesce(p_origem_arquivo,'supabase_storage'),
            p_arquivo_ref, p_nome_original, p_assinado, p_hash, p_legibilidade)
    returning id into v_versao_id;

  if p_tipo_taxonomia is not null then
    select obrigatoriedade into v_obrig from taxonomia_tipo_documento where codigo = p_tipo_taxonomia;
    insert into checklist_item_status
      (caso_id, entidade_id, periodo_id, tipo_taxonomia, obrigatoriedade, status, documento_id)
      values (p_caso_id, v_entidade_id, v_periodo_id, p_tipo_taxonomia,
              coalesce(v_obrig,'complementar'), 'presente', v_documento_id);
  end if;

  if p_tipo_taxonomia is null or coalesce(p_confianca,0) < p_threshold then
    insert into pendencia (caso_id, origem_estagio, tipo, severidade, sobrepujavel, descricao, documento_id)
      values (p_caso_id, 'classificacao', 'classificacao_pendente', 'importante', true,
              format('Classificação incerta (conf=%s, fonte=%s) para "%s"',
                     coalesce(p_confianca,0), coalesce(p_fonte,'?'), coalesce(p_nome_original,'?')),
              v_documento_id);
  end if;

  insert into evento_auditoria (ator, acao, entidade_ref, depois)
    values ('sistema:n8n', 'documento_registrado', 'documento:'||v_documento_id,
            jsonb_build_object('tipo', p_tipo_taxonomia, 'confianca', p_confianca, 'fonte', p_fonte));

  return jsonb_build_object('documento_id', v_documento_id, 'documento_versao_id', v_versao_id);
end;
$$;

-- -----------------------------------------------------------------------------
-- fn_registrar_campos_extraidos — grava os campos extraídos em SOMBRA (N0).
-- p_campos: array jsonb [{chave, valor_texto, valor_num, unidade, confianca,
--                         origem_pagina, origem_linha}]. Retorna a contagem.
-- NÃO altera status do caso nem cria "número aceito" — é sombra (anti-ancoragem).
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
       origem_pagina, origem_linha, nivel_autonomia)
    values (
      p_documento_versao_id,
      coalesce(v_item->>'chave', '(sem rótulo)'),
      v_item->>'valor_texto',
      case when (v_item->>'valor_num') ~ '^-?\d+(\.\d+)?$' then (v_item->>'valor_num')::numeric else null end,
      v_item->>'unidade',
      case when (v_item->>'confianca') ~ '^-?\d+(\.\d+)?$' then (v_item->>'confianca')::numeric else null end,
      case when (v_item->>'origem_pagina') ~ '^\d+$' then (v_item->>'origem_pagina')::int else null end,
      v_item->>'origem_linha',
      p_nivel
    );
    v_count := v_count + 1;
  end loop;

  insert into evento_auditoria (ator, acao, entidade_ref, depois)
    values ('sistema:n8n', 'extracao_sombra', 'documento_versao:'||p_documento_versao_id,
            jsonb_build_object('campos', v_count, 'nivel', p_nivel));

  return v_count;
end;
$$;
