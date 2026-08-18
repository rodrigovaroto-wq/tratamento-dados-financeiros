-- =============================================================================
-- Migration 0121 — O diagnóstico de conteúdo para de duplicar a empresa
--
-- ACHADO EM DADO REAL, e não em teste: o dono rodou o diagnóstico de entidades
-- na base dele e quatro mandatos voltaram com TRÊS linhas para a mesma empresa —
-- "Canastra Industria 2025x2024x2023", "CANASTRA INDÚSTRIA DE EMBALAGENS LTDA."
-- e "Meses Canastra Industria". A primeira e a terceira são sujeira de nome de
-- arquivo, já corrigida na origem (o classificador limpa período e ruído desde
-- 17/08). A SEGUNDA não é sujeira: é a razão social correta, criada como linha
-- NOVA por esta função — e isso continua acontecendo hoje, em mandato novo, com
-- o workflow já reimportado.
--
-- A CAUSA é uma metade esquecida da 0030. Aquela migration ensinou
-- `fn_registrar_documento` a casar entidade pela forma CANÔNICA (via
-- `fn_upsert_entidade`/`fn_mesma_entidade`), porque a entidade chega de duas
-- fontes que escrevem diferente: o nome do arquivo e o diagnóstico do conteúdo.
-- `fn_registrar_diagnostico` — que é justamente a segunda fonte — ficou para
-- trás, comparando `lower(razao_social) = lower(p_entidade_nome)`.
--
-- DOIS EFEITOS, os dois reproduzidos em base limpa antes desta migration:
--
--   1. DUPLICA A EMPRESA. Documento que chega sem entidade (o classificador se
--      abstém quando o nome do arquivo não carrega empresa — 6 dos 38 do book)
--      recebe do diagnóstico a razão social completa; a busca por igualdade
--      exata falha, e nasce a segunda linha.
--   2. ABRE PENDÊNCIA FALSA. Quando o documento JÁ tem entidade, a mesma
--      igualdade exata compara "Canastra Industria" com "CANASTRA INDÚSTRIA DE
--      EMBALAGENS LTDA." e declara divergência — entre dois nomes da mesma
--      companhia, que `fn_mesma_entidade` reconhece como a mesma.
--
-- POR QUE ISSO FICOU CARO AGORA. Antes da 0119, entidade duplicada partia
-- colunas do export — ruim, e visível só por dentro. Depois dela, a entidade é o
-- EIXO da cobrança de linha exigida: a mesma empresa é cobrada duas vezes, abre
-- pendência em dobro, e a 0120 gera duas perguntas ao cliente sobre a mesma
-- coisa. O defeito é velho; o preço dele subiu.
--
-- O QUE ESTA MIGRATION NÃO FAZ: limpar as entidades já duplicadas. Os quatro
-- mandatos onde isso apareceu são de TESTE (v41, V45, v46, v4x), e construir
-- fusão de entidades para arrumar dado de teste é trabalho que não se paga —
-- corrigida a função que os produz, mandato novo nasce limpo. Se um dia a
-- duplicata aparecer em mandato de cliente, aí a fusão vira fatia própria, com
-- o cuidado que mover documento entre entidades merece.
--
-- REEMITIDA INTEIRA (padrão do repositório): fora as duas linhas de casamento
-- de entidade, o corpo é o vigente — tipo, período (que já compara por forma
-- canônica desde a 0022), legibilidade, resumo e a trilha, sem uma vírgula
-- mudada.
-- =============================================================================

create or replace function fn_registrar_diagnostico(
  p_documento_id        uuid,
  p_documento_versao_id uuid,
  p_entidade_nome       text,
  p_tipo_confirma       boolean,
  p_tipo_sugerido       text,
  p_periodo_tipo        text,
  p_periodo_referencia  text,
  p_legibilidade        legibilidade,
  p_nota_legibilidade   text,
  p_resumo              text,
  p_justificativa       text
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
      -- 0121: `fn_upsert_entidade` (0030), e não mais igualdade exata de texto.
      -- Era ela quem criava a segunda linha da MESMA empresa: o classificador
      -- não resolvia a entidade pelo nome do arquivo (6 dos 38 documentos do
      -- book), o diagnóstico lia a razão social completa do conteúdo
      -- ("CANASTRA INDÚSTRIA DE EMBALAGENS LTDA."), não achava igualdade exata
      -- com a que já existia ("Canastra Industria") e INSERIA outra.
      v_entidade_id := fn_upsert_entidade(v_caso_id, p_entidade_nome);
      update documento set entidade_id = v_entidade_id where id = p_documento_id;
      v_entidade_criada := true;
    else
      select razao_social into v_entidade_atual_nome from entidade where id = v_entidade_id;
      select id into v_pendencia_id from pendencia
        where caso_id = v_caso_id and motivo = 'diagnostico:entidade:' || p_documento_id and estado <> 'resolvida'
        limit 1;
      -- 0121: divergência de ENTIDADE passa a ser medida pela forma canônica,
      -- como o período já é desde a 0022. "Canastra Industria" e "CANASTRA
      -- INDÚSTRIA DE EMBALAGENS LTDA." são a mesma empresa, e `fn_mesma_entidade`
      -- já sabia disso — só esta comparação não perguntava, e por isso abria
      -- pendência de divergência entre dois nomes da mesma companhia.
      if not fn_mesma_entidade(v_entidade_atual_nome, p_entidade_nome) then
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
  -- 0022: compara pelo CONJUNTO DE ANOS. "anual 2025" e "data-base 2025-12-31"
  -- são o MESMO exercício com granularidade diferente — não é divergência, é
  -- refinamento; acusar isso enchia a fila de revisão de pendência falsa.
  -- Divergência real (2024 × 2025) continua virando pendência.
  if p_periodo_referencia is not null
     and not fn_periodos_equivalentes(p_periodo_tipo, p_periodo_referencia,
                                      v_periodo_tipo_atual, v_periodo_ref_atual) then
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
comment on function fn_registrar_diagnostico(uuid, uuid, text, boolean, text, text, text, legibilidade, text, text, text) is
  'Registra o diagnóstico de conteúdo (E1/E2) e confere contra o que já está no banco. 0121: a '
  'entidade passa a casar e a divergir pela forma CANÔNICA (fn_upsert_entidade/fn_mesma_entidade, '
  '0030) — antes, igualdade exata de texto criava uma segunda linha para a mesma empresa e abria '
  'pendência de divergência entre duas grafias dela.';

grant execute on function fn_registrar_diagnostico(uuid, uuid, text, boolean, text, text, text, legibilidade, text, text, text) to authenticated;

-- -----------------------------------------------------------------------------
-- VERIFICAÇÃO EMBUTIDA (padrão 0105) — os dois efeitos, provados aqui.
-- Ela confere o que ESTE arquivo faz; nada sobre o estado do banco do dono.
-- -----------------------------------------------------------------------------
do $$
declare
  v_caso uuid := gen_random_uuid();
  v_r jsonb;
  v_doc uuid; v_ver uuid;
  v_n int;
begin
  insert into caso (id, nome, produto) values (v_caso, 'VERIF 0121', 'reestruturacao');

  -- (1) documento SEM entidade + diagnóstico com a razão social completa:
  --     tem de reaproveitar a empresa que já existe, não criar outra.
  insert into entidade (caso_id, razao_social) values (v_caso, 'Canastra Industria');
  v_r := fn_registrar_documento(v_caso, null, 'anual', '2025', 'BALANCO', 0.9, 'nome_arquivo',
           'supabase_storage', 'b/x.pdf', 'BP.pdf', true, 'H-0121-A', 'ok');
  v_doc := (v_r->>'documento_id')::uuid; v_ver := (v_r->>'documento_versao_id')::uuid;
  perform fn_registrar_diagnostico(v_doc, v_ver, 'CANASTRA INDÚSTRIA DE EMBALAGENS LTDA.',
            true, 'BALANCO', 'anual', '2025', 'ok', null, 'r', 'j');
  select count(*) into v_n from entidade where caso_id = v_caso;
  if v_n <> 1 then
    raise exception '0121: o diagnóstico criou % entidade(s) para a mesma empresa — devia reaproveitar', v_n;
  end if;

  -- (2) documento COM entidade + diagnóstico com outra grafia da MESMA empresa:
  --     não pode abrir pendência de divergência.
  v_r := fn_registrar_documento(v_caso, 'Canastra Industria', 'anual', '2025', 'DRE', 0.9, 'nome_arquivo',
           'supabase_storage', 'b/y.pdf', 'DRE.pdf', true, 'H-0121-B', 'ok');
  v_doc := (v_r->>'documento_id')::uuid; v_ver := (v_r->>'documento_versao_id')::uuid;
  perform fn_registrar_diagnostico(v_doc, v_ver, 'CANASTRA INDÚSTRIA DE EMBALAGENS LTDA.',
            true, 'DRE', 'anual', '2025', 'ok', null, 'r', 'j');
  select count(*) into v_n from pendencia
   where caso_id = v_caso and tipo = 'entidade_incorreta' and estado <> 'resolvida';
  if v_n <> 0 then
    raise exception '0121: % pendência(s) de entidade_incorreta entre duas grafias da MESMA empresa', v_n;
  end if;

  -- (3) e a divergência de VERDADE continua sendo acusada.
  v_r := fn_registrar_documento(v_caso, 'Canastra Industria', 'anual', '2025', 'FLUXO_CAIXA', 0.9, 'nome_arquivo',
           'supabase_storage', 'b/z.pdf', 'DFC.pdf', true, 'H-0121-C', 'ok');
  v_doc := (v_r->>'documento_id')::uuid; v_ver := (v_r->>'documento_versao_id')::uuid;
  perform fn_registrar_diagnostico(v_doc, v_ver, 'Vertentes Metalurgica Ltda.',
            true, 'FLUXO_CAIXA', 'anual', '2025', 'ok', null, 'r', 'j');
  select count(*) into v_n from pendencia
   where caso_id = v_caso and tipo = 'entidade_incorreta' and estado <> 'resolvida';
  if v_n <> 1 then
    raise exception '0121: empresa DIFERENTE devia abrir 1 pendência, abriu %', v_n;
  end if;

  delete from caso where id = v_caso;
  raise notice '0121 OK — o diagnóstico reaproveita a empresa, não acusa grafia, e ainda acusa empresa diferente';
end $$;
