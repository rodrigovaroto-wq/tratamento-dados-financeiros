-- =============================================================================
-- 0118 — Reenviar o mesmo arquivo com o mesmo prompt deixa de pagar a extração
--
-- ISTO É A SEGUNDA METADE DA 0026, e ela mesma descreveu o que faltava:
--
--   "O que esta migration NÃO faz, de propósito: não deixa de PAGAR a extração
--    repetida. Para isso o workflow precisaria não chamar a OpenAI quando o
--    arquivo é idêntico E a extração anterior foi feita com o MESMO
--    prompt/modelo — o que exige (i) um fingerprint de prompt+modelo gravado na
--    versão e (ii) curto-circuito no grafo do N8N. Fatia própria."
--
-- Esta é a fatia. O (i) está aqui; o (ii) está no `N8N/build-workflow.mjs`
-- (o IF `Extracao ja feita?` e o Merge `Juntar Extraidos`).
--
-- O QUE O FINGERPRINT PRECISA SER, e por que ele não é só o modelo. Uma extração
-- é reaproveitável quando NADA que a determina mudou: o arquivo (já coberto pelo
-- `hash`), o modelo, o PROMPT DE SISTEMA e o esquema de resposta. O prompt é o
-- que mais muda neste repositório — a `0116` acabou de mexer nele — e uma
-- extração feita com o prompt de ontem não vale como a de hoje: era exatamente
-- assim que a DMPL registrada como MUTUOS antes da `0024` ficava presa no código
-- errado. Então o fingerprint é calculado sobre prompt+modelo+esquema, no BUILD
-- do workflow, e viaja com a chamada de registro.
--
-- AS DUAS CONDIÇÕES QUE O REAPROVEITAMENTO EXIGE, e a segunda é a que impede o
-- pior erro possível aqui:
--
--   1. mesmo `(caso_id, hash)` E mesmo `fingerprint_extracao`;
--   2. a versão antiga TEM linha em `campo_extraido`.
--
-- Sem a (2), uma extração que FALHOU (truncada, recusada, arquivo ilegível)
-- passaria a valer como extração feita, e o reenvio — que é justamente o que se
-- faz para consertar uma falha — nunca mais chamaria a OpenAI. O documento
-- ficaria permanentemente sem dado, com o sistema dizendo que estava tudo certo.
-- É por isso que a condição é "tem linha", e não "tem versão".
--
-- E O QUE ISTO NÃO IMPEDE: reextração DELIBERADA continua funcionando. Basta o
-- prompt, o modelo ou o esquema terem mudado — e é isso que muda quando se
-- reextrai para pegar taxonomia nova. Fingerprint nulo (workflow antigo, que não
-- manda o campo) cai no comportamento da 0026: versão nova, extração paga.
-- =============================================================================

alter table documento_versao
  add column if not exists fingerprint_extracao text;

comment on column documento_versao.fingerprint_extracao is
  'Impressão do que determinou a extração desta versão: prompt de sistema + modelo + esquema de resposta, calculada no build do workflow. É o que autoriza NÃO pagar a extração de novo quando o mesmo arquivo volta — junto com a exigência de a versão ter linha extraída (0118).';

-- O ÍNDICE existe porque a consulta de reaproveitamento roda para TODO documento
-- de TODO lote, antes de qualquer gasto: é caminho quente. Sem ele, cada
-- documento faz varredura em `documento_versao` do caso.
create index if not exists idx_documento_versao_hash_fingerprint
  on documento_versao (hash, fingerprint_extracao)
  where hash is not null and fingerprint_extracao is not null;

-- A ASSINATURA VELHA SAI, e isto não é zelo: é a lição da 0026, que aprendeu na
-- pele que `create or replace` com um parâmetro A MAIS não substitui — CRIA uma
-- segunda função. Com as duas vivas, a chamada do n8n (13 posicionais + o resto
-- por nome) casaria com AMBAS e o Postgres recusaria com "function is not
-- unique" — no meio de um lote real, e não em teste.
drop function if exists fn_registrar_documento(
  uuid, text, text, text, text, numeric, text, origem_arquivo, text, text,
  boolean, text, legibilidade, numeric, text
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
  p_threshold      numeric default 0.7,
  p_justificativa  text default null,
  p_fingerprint_extracao text default null
)
returns jsonb
language plpgsql
as $$
declare
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
  v_entidade_id := fn_upsert_entidade(p_caso_id, p_entidade_nome);
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
  if p_tipo_taxonomia is null or coalesce(p_confianca,0) < p_threshold then
    if not exists (
      select 1 from pendencia p
      where p.documento_id = v_documento_id
        and p.tipo = 'classificacao_pendente'
        and p.estado <> 'resolvida'
    ) then
      insert into pendencia (caso_id, origem_estagio, tipo, severidade, sobrepujavel, descricao, documento_id)
        values (p_caso_id, 'classificacao', 'classificacao_pendente', 'importante', true,
                format('Classificação incerta (conf=%s, fonte=%s) para "%s". Motivo: %s',
                       coalesce(p_confianca,0), coalesce(p_fonte,'?'), coalesce(p_nome_original,'?'),
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

comment on function fn_registrar_documento(
  uuid, text, text, text, text, numeric, text, origem_arquivo, text, text,
  boolean, text, legibilidade, numeric, text, text
) is
  'Registra um arquivo classificado (E1). Idempotente por (caso_id, hash): o MESMO arquivo '
  'reenviado/reextraído vira nova documento_versao sob o mesmo documento (n_versao+1), sem '
  'duplicar documento, checklist nem pendência. 0118: quando o hash E o fingerprint de '
  'prompt+modelo+esquema batem com uma versão que JÁ TEM linha extraída, nem versão nova é '
  'criada — devolve a existente com reaproveitou_extracao=true, e o workflow pula a chamada à '
  'OpenAI. Hash nulo não casa. Classificação da máquina não sobrepõe revisão humana.';

grant execute on function fn_registrar_documento(
  uuid, text, text, text, text, numeric, text, origem_arquivo, text, text,
  boolean, text, legibilidade, numeric, text, text
) to authenticated;
