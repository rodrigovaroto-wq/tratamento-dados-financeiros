-- =============================================================================
-- 0170 — O CNPJ atravessa a porta de entrada
--
-- A 0169 ensinou o banco a USAR o CNPJ como identidade. Ela nasceu DORMENTE, e
-- isso estava escrito no cabeçalho dela: `fn_registrar_documento` — a porta por
-- onde todo documento entra — chama `fn_upsert_entidade` com DOIS argumentos, e
-- o terceiro fica no default nulo. Enquanto essa chamada não passar o CNPJ, as
-- três regras da 0169 nunca disparam em produção, e o único sintoma é que nada
-- melhora: o estágio ligado e o estágio que não roda têm a mesma aparência
-- (regra 7 do CLAUDE.md).
--
-- ESTA MIGRATION É O FIO. Um parâmetro a mais em `fn_registrar_documento`,
-- repassado para `fn_upsert_entidade`. Nada mais.
--
-- O CORPO É REEMITIDO INTEIRO, verbatim do `Supabase/schema.sql` vigente, com
-- DUAS mudanças e nenhuma outra: a assinatura ganha `p_cnpj text default null`
-- no fim, e a linha da chamada passa a levar `p_cnpj`. Nunca por patch de
-- âncora — `.claude/memory/nunca-corrigir-funcao-por-replace.md`, e o incidente
-- de CRLF que a 0163 teve de consertar.
--
-- O PARÂMETRO VAI NO FIM, com default, por uma razão de compatibilidade: as
-- chamadas POSICIONAIS existentes (13 posicionais + o resto por nome, que é
-- como o nó do n8n chama) continuam válidas sem tocar em nada. Um documento que
-- chega sem CNPJ se comporta exatamente como hoje.
--
-- A ARMADILHA DO OVERLOAD, de novo e pelo mesmo motivo: com a de 16 argumentos
-- viva ao lado da de 17, a chamada do n8n casa com AMBAS e o Postgres recusa
-- com "function is not unique" — no meio de um lote real, não em teste. Foi
-- exatamente isso que a 0118 teve de consertar quando acrescentou o 16º
-- parâmetro, e é o que `reextracao.test.sql` mede. O `drop function` explícito
-- abaixo cita a assinatura de 16 por extenso.
--
-- E O PORTÃO QUE CONTA OS ARGUMENTOS MUDA JUNTO, na mesma passada:
-- `Supabase/test/reextracao.test.sql` afirma `pronargs = 16`. Ele não é um
-- teste que "quebrou" — ele é o teste que está fazendo o trabalho dele, e
-- atualizá-lo para 17 é parte da fatia, não conserto de dano colateral.
--
-- O QUE ESTA MIGRATION NÃO FAZ: não faz a IA LER o CNPJ do documento. Isso é o
-- prompt e o schema de classificação, no `N8N/build-workflow.mjs`, e vai na
-- mesma fatia mas do outro lado da fronteira. Até lá o parâmetro chega nulo e
-- nada muda — que é a mesma propriedade de segurança que a 0169 já mede.
--
-- Idempotente: `drop ... if exists` + `create or replace`.
-- =============================================================================

begin;

drop function if exists fn_registrar_documento(
  uuid, text, text, text, text, numeric, text, origem_arquivo, text, text,
  boolean, text, legibilidade, numeric, text, text
);

create or replace function fn_registrar_documento(p_caso_id uuid, p_entidade_nome text, p_periodo_tipo text, p_periodo_ref text, p_tipo_taxonomia text, p_confianca numeric, p_fonte text, p_origem_arquivo public.origem_arquivo, p_arquivo_ref text, p_nome_original text, p_assinado boolean, p_hash text, p_legibilidade public.legibilidade, p_threshold numeric DEFAULT 0.7, p_justificativa text DEFAULT NULL::text, p_fingerprint_extracao text DEFAULT NULL::text, p_cnpj text DEFAULT NULL::text) RETURNS jsonb
language plpgsql
as $$
declare
  -- 0127: o limiar da classificacao passa a vir do DIAL.
  v_auto_classif   boolean;
  v_entidade_id uuid;
  v_periodo_id  uuid;
  v_documento_id uuid;
  v_versao_id   uuid;
  v_n_versao    int := 1;
  v_obrig obrigatoriedade;
  v_reaproveitou boolean := false;
  v_versao_reuso uuid;
  v_doc_reuso    uuid;
  v_n_reuso      int;
begin
  -- ---- REAPROVEITAMENTO DE EXTRAÇÃO: a primeira pergunta, e a mais barata ----
  -- Vem ANTES do upsert de entidade/período de propósito: se o arquivo já foi
  -- extraído com este mesmo prompt, nada precisa ser criado — nem versão, nem
  -- entidade, nem período. Sair daqui é o caminho de custo zero.
  if p_hash is not null and length(trim(p_hash)) > 0
     and p_fingerprint_extracao is not null and length(trim(p_fingerprint_extracao)) > 0 then
    select dv.id, dv.documento_id, dv.n_versao
      into v_versao_reuso, v_doc_reuso, v_n_reuso
    from documento_versao dv
    join documento d on d.id = dv.documento_id
    where d.caso_id = p_caso_id
      and dv.hash = p_hash
      and dv.fingerprint_extracao = p_fingerprint_extracao
      -- TEM LINHA: extração que falhou não vale como extração feita (ver o
      -- cabeçalho). É o que mantém o reenvio como conserto possível.
      and exists (select 1 from campo_extraido ce where ce.documento_versao_id = dv.id)
    order by dv.n_versao desc
    limit 1;
  end if;

  if v_versao_reuso is not null then
    insert into evento_auditoria (ator, acao, entidade_ref, depois)
      values ('sistema:n8n', 'documento_extracao_reaproveitada',
              'documento_versao:' || v_versao_reuso,
              jsonb_build_object('documento_id', v_doc_reuso, 'hash', p_hash,
                                 'fingerprint_extracao', p_fingerprint_extracao,
                                 'nome_original', p_nome_original));
    return jsonb_build_object(
      'documento_id', v_doc_reuso,
      'documento_versao_id', v_versao_reuso,
      'n_versao', v_n_reuso,
      'reaproveitou_documento', true,
      'reaproveitou_extracao', true
    );
  end if;

  -- ENTIDADE E PERÍODO PELA FORMA CANÔNICA (0030), e não por `lower()`. Esta é a
  -- parte que a primeira versão desta migration perdeu por copiar o corpo da
  -- 0026 em vez do corpo VIGENTE: o teste de canonicalização reprovou na hora
  -- ("as duas grafias da mesma empresa viram UMA entidade — achei 2"), que é
  -- exatamente o defeito que a 0030 tinha corrigido. Republicar função neste
  -- banco significa partir do corpo mais recente, nunca do da migration que a
  -- gente está lendo.
  v_entidade_id := fn_upsert_entidade(p_caso_id, p_entidade_nome, p_cnpj);
  v_periodo_id := fn_upsert_periodo(p_caso_id, p_periodo_tipo, p_periodo_ref);

  -- Já existe ESTE arquivo (mesmo hash) neste caso? Então é reextração/reenvio:
  -- versão nova sob o mesmo documento. Hash nulo nunca casa (ver 0026).
  if p_hash is not null and length(trim(p_hash)) > 0 then
    select dv.documento_id into v_documento_id
    from documento_versao dv
    join documento d on d.id = dv.documento_id
    where d.caso_id = p_caso_id and dv.hash = p_hash
    order by dv.criada_em desc
    limit 1;
    v_reaproveitou := v_documento_id is not null;
  end if;

  if v_reaproveitou then
    select coalesce(max(n_versao), 0) + 1 into v_n_versao
      from documento_versao where documento_id = v_documento_id;
    -- A classificação da versão nova prevalece SOBRE A DO SISTEMA, nunca sobre a
    -- do humano: se alguém já revisou este documento na fila (`fonte='humano'`,
    -- `Supabase/migrations/0008`), a reextração não desfaz a decisão dele — é a
    -- anti-ancoragem de sempre (Arquitetura do Sistema/1 Visão e Doutrina/01), no sentido que importa: máquina não
    -- sobrepõe humano. Entidade/período seguem a mesma regra.
    update documento d set
      tipo_taxonomia = case when d.fonte = 'humano' then d.tipo_taxonomia else p_tipo_taxonomia end,
      entidade_id    = case when d.fonte = 'humano' then d.entidade_id else coalesce(v_entidade_id, d.entidade_id) end,
      periodo_id     = case when d.fonte = 'humano' then d.periodo_id else coalesce(v_periodo_id, d.periodo_id) end,
      confianca      = case when d.fonte = 'humano' then d.confianca else p_confianca end,
      fonte          = case when d.fonte = 'humano' then d.fonte else p_fonte end,
      justificativa  = case when d.fonte = 'humano' then d.justificativa else p_justificativa end,
      status         = case when d.fonte = 'humano' then d.status else 'em_validacao' end
    where d.id = v_documento_id;
  else
    insert into documento (caso_id, entidade_id, periodo_id, tipo_taxonomia, status, confianca, fonte, justificativa)
      values (p_caso_id, v_entidade_id, v_periodo_id, p_tipo_taxonomia, 'em_validacao', p_confianca, p_fonte, p_justificativa)
      returning id into v_documento_id;
  end if;

  insert into documento_versao
    (documento_id, n_versao, origem_arquivo, arquivo_ref, nome_original, assinado, hash,
     legibilidade, fingerprint_extracao)
    values (v_documento_id, v_n_versao, coalesce(p_origem_arquivo,'supabase_storage'),
            p_arquivo_ref, p_nome_original, p_assinado, p_hash, p_legibilidade,
            p_fingerprint_extracao)
    returning id into v_versao_id;

  -- Checklist: só na PRIMEIRA vez. Reextração não é documento novo — inserir de
  -- novo daria dois itens "presente" para o mesmo documento e inflaria a
  -- completude com um arquivo só (a `unique` do checklist não cobre isso porque
  -- `documento_id` faz parte da linha).
  if p_tipo_taxonomia is not null and not v_reaproveitou then
    select obrigatoriedade into v_obrig from taxonomia_tipo_documento where codigo = p_tipo_taxonomia;
    insert into checklist_item_status
      (caso_id, entidade_id, periodo_id, tipo_taxonomia, obrigatoriedade, status, documento_id)
      values (p_caso_id, v_entidade_id, v_periodo_id, p_tipo_taxonomia,
              coalesce(v_obrig,'complementar'), 'presente', v_documento_id);
  end if;

  -- Pendência de classificação incerta: idempotente por documento.
  --
  -- 0127: O LIMIAR SAI DO PARÂMETRO E PASSA A VIR DO DIAL. Até aqui ele era
  -- `p_threshold`, default 0.7 — e o dial de `classificacao_doc_checklist` dizia
  -- limiar 0,95, lido por ninguém. O sistema declarava 0,95 e aplicava 0,70.
  --
  -- O parâmetro fica como QUEDA, para banco que ainda não tem a linha do dial
  -- (a semeadura é da 0002). Não é cortesia: sem a queda, um banco antigo passaria
  -- a abrir pendência de classificação em TODO documento no instante em que esta
  -- migration entrasse, e o motivo seria invisível.
  v_auto_classif := case
    when exists (select 1 from estagio_autonomia
                  where estagio = 'classificacao_doc_checklist')
      then fn_dial_permite_auto('classificacao_doc_checklist', p_confianca)
    else coalesce(p_confianca, 0) >= p_threshold
  end;

  if p_tipo_taxonomia is null or not v_auto_classif then
    if not exists (
      select 1 from pendencia p
      where p.documento_id = v_documento_id
        and p.tipo = 'classificacao_pendente'
        and p.estado <> 'resolvida'
    ) then
      insert into pendencia (caso_id, origem_estagio, tipo, severidade, sobrepujavel, descricao, documento_id)
        values (p_caso_id, 'classificacao', 'classificacao_pendente', 'importante', true,
                -- 0127: a mensagem passa a dizer QUAL limiar reprovou. Sem isso, o
                -- analista lê "conf=0,62" e não sabe contra o que ela perdeu — e
                -- o limiar agora é dado, então pode ter mudado desde ontem.
                format('Classificação incerta (conf=%s, limiar do dial=%s, fonte=%s) para "%s". Motivo: %s',
                       coalesce(p_confianca,0),
                       coalesce((select ea.limiar_auto_clear::text from estagio_autonomia ea
                                  where ea.estagio = 'classificacao_doc_checklist'),
                                p_threshold::text || ' (queda: dial sem linha)'),
                       coalesce(p_fonte,'?'), coalesce(p_nome_original,'?'),
                       coalesce(nullif(trim(p_justificativa), ''), 'nenhuma justificativa fornecida')),
                v_documento_id);
    end if;
  end if;

  insert into evento_auditoria (ator, acao, entidade_ref, depois)
    values ('sistema:n8n',
            case when v_reaproveitou then 'documento_reextraido' else 'documento_registrado' end,
            'documento:'||v_documento_id,
            jsonb_build_object('tipo', p_tipo_taxonomia, 'confianca', p_confianca, 'fonte', p_fonte,
                               'justificativa', p_justificativa, 'n_versao', v_n_versao,
                               'hash', p_hash, 'fingerprint_extracao', p_fingerprint_extracao));

  return jsonb_build_object(
    'documento_id', v_documento_id,
    'documento_versao_id', v_versao_id,
    'n_versao', v_n_versao,
    'reaproveitou_documento', v_reaproveitou,
    'reaproveitou_extracao', false
  );
end;
$$;
comment on function fn_registrar_documento(uuid, text, text, text, text, numeric, text, origem_arquivo, text, text, boolean, text, legibilidade, numeric, text, text, text) is
  'A porta de entrada do documento: acha ou cria caso/entidade/período, versiona e responde se '
  'já foi extraído (0118). 0170: recebe o CNPJ do emitente e o repassa a fn_upsert_entidade — '
  'sem este fio, as três regras de identidade da 0169 nunca disparam em produção e o sintoma é '
  'que nada melhora.';

-- -----------------------------------------------------------------------------
-- O CATÁLOGO DA SONDA — requisito de CORPO sobre a chamada com três argumentos.
--
-- O marcador é a CHAMADA, não o nome da função: `fn_upsert_entidade` aparece no
-- corpo com dois argumentos desde a 0030, então procurá-lo passaria num banco
-- que nunca aplicou esta migration — requisito nascido vazio dentro da sonda.
-- `p_entidade_nome, p_cnpj` só existe depois daqui.
-- -----------------------------------------------------------------------------
insert into instalacao_requisito
  (chave, migration, tipo, objeto, marcador, criterio_seed, porque, severidade, ordem) values
  ('cnpj_atravessa_a_porta', '0170', 'corpo', 'fn_registrar_documento',
   'p_entidade_nome, p_cnpj', null,
   'Sem esta migration a 0169 fica DORMENTE: fn_registrar_documento chama fn_upsert_entidade com '
   'dois argumentos e o CNPJ nunca chega. O sintoma é não haver sintoma — a fragmentação de '
   'entidade continua exatamente como no lote do caso "teste 143" (a OMNIBEAUTY em quatro linhas) '
   'com todo o código de identidade instalado e nunca executado.',
   'bloqueante', 680)
on conflict (chave) do update set
  migration = excluded.migration, tipo = excluded.tipo, objeto = excluded.objeto,
  marcador = excluded.marcador, criterio_seed = excluded.criterio_seed,
  porque = excluded.porque, severidade = excluded.severidade, ordem = excluded.ordem;

update instalacao_cobertura
   set ate_migration = '0170', revisado_em = current_date,
       observacao = 'A 0170 reemite fn_registrar_documento INTEIRA (16 → 17 args, com DROP da de '
                    '16: overload vivo derruba lote real com "function is not unique", como a '
                    '0118 já teve de consertar). Requisito de corpo pela CHAMADA de três '
                    'argumentos, não pelo nome da função chamada — o nome está lá desde a 0030 e '
                    'o requisito nasceria vazio. O portão de aridade de reextracao.test.sql passa '
                    'de 16 para 17 na mesma passada.';

commit;
