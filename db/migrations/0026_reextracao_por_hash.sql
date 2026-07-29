-- =============================================================================
-- Migration 0026 — Reextração é VERSÃO NOVA do mesmo documento (idempotência por
-- hash) + limpeza do overload morto de fn_registrar_documento
--
-- Duas coisas, uma causa comum: o registro de documento nunca olhou o hash.
--
-- 1. IDEMPOTÊNCIA POR HASH. O comentário da 0004 dizia "de forma idempotente-ish
--    por hash", mas nenhuma versão do corpo (0004/0005/0006/0007/0008) chegou a
--    CONSULTAR o hash: todo reenvio do mesmo arquivo inseria `documento` novo +
--    `documento_versao` nova + `checklist_item_status` novo. Consequências reais,
--    e a segunda é a que motivou esta migration agora:
--
--      (a) o mesmo arquivo virava DOIS documentos no caso — duas linhas na fila
--          de revisão, dois itens de checklist, e no export duas colunas/abas da
--          mesma empresa (o dono já viu isso como "15 colunas de entidade para 5
--          empresas", teste v27);
--      (b) REEXTRAIR ficava impossível sem sujar o caso. E reextrair é a ÚNICA
--          forma de um documento já processado pegar prompt/taxonomia novos
--          (migration e prompt só valem para extração NOVA — regra de sempre): a
--          DMPL registrada como MUTUOS antes da `0024` só sai daquele código
--          sendo reextraída, e o caminho para isso era reenviar o arquivo, que
--          duplicava o documento.
--
--    Agora: mesmo `(caso_id, hash)` → nova `documento_versao` sob o MESMO
--    `documento`, com `n_versao` incrementado. O documento mantém identidade,
--    fila, checklist e histórico; o export usa a versão vigente
--    (`versoesVigentes` em portal/src/lib/export.ts, que escolhe a mais recente
--    COM DADO — reextração que falha e volta com zero linhas não pode apagar do
--    book o que a versão anterior extraiu com sucesso, `0016`).
--
--    O hash tem de ser NÃO NULO para casar: `hash is null` significa "não sei o
--    que é este arquivo", e tratar dois desconhecidos como o mesmo arquivo seria
--    fundir documentos diferentes — o erro mais caro possível aqui. Sem hash, o
--    comportamento é o de antes (documento novo).
--
--    O que esta migration NÃO faz, de propósito: **não deixa de PAGAR** a
--    extração repetida. Para isso o workflow precisaria não chamar a OpenAI
--    quando o arquivo é idêntico E a extração anterior foi feita com o MESMO
--    prompt/modelo — o que exige (i) um "fingerprint" de prompt+modelo gravado na
--    versão e (ii) curto-circuito no grafo do N8N (`Montar Req Extracao` é
--    `runOnceForEachItem` e não pode devolver zero itens; mudar o modo troca a
--    resolução de contexto por item, a mesma classe de mudança que já causou o
--    bug do `itemIndex` fixo). Fatia própria, com o N8N vivo do dono — não às
--    cegas. Enquanto isso, reenviar o arquivo é SEGURO (não duplica) mas custa
--    uma extração, que é exatamente o que se quer quando a reextração é
--    deliberada.
--
-- 2. OVERLOAD MORTO (achado da auditoria, `fn-registrar-documento-overload-duplicado`).
--    A 0007 adicionou `p_justificativa` via `create or replace` com um parâmetro a
--    MAIS — em Postgres isso CRIA uma segunda função em vez de substituir. Desde
--    então convivem a de 14 args (0005/0006) e a de 15 (0007/0008). Não quebrou a
--    produção porque o N8N chama com parâmetro nomeado, mas é lixo de schema: a
--    assinatura de 14 args ainda tem o corpo ANTIGO (sem confianca/fonte/
--    justificativa em `documento`, sem idempotência), e qualquer chamada
--    posicional pode cair nela. Vai embora aqui.
-- =============================================================================

-- 1. Fora o overload morto de 14 args (o de 15 continua e é o único).
drop function if exists fn_registrar_documento(
  uuid, text, text, text, text, numeric, text, origem_arquivo, text, text,
  boolean, text, legibilidade, numeric
);

-- 2. fn_registrar_documento — mesma assinatura de 0007/0008 (15 args), corpo com
--    idempotência por hash. Retorno ganha dois campos ADITIVOS (`n_versao`,
--    `reaproveitou_documento`); `documento_id`/`documento_versao_id` continuam
--    onde estavam, então o N8N atual segue funcionando sem mudança.
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
  p_justificativa  text default null
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

  -- Já existe ESTE arquivo (mesmo hash) neste caso? Então é reextração/reenvio:
  -- versão nova sob o mesmo documento. Hash nulo nunca casa (ver cabeçalho).
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
    -- `db/migrations/0008`), a reextração não desfaz a decisão dele — é a
    -- anti-ancoragem de sempre (docs/01), no sentido que importa: máquina não
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
    (documento_id, n_versao, origem_arquivo, arquivo_ref, nome_original, assinado, hash, legibilidade)
    values (v_documento_id, v_n_versao, coalesce(p_origem_arquivo,'supabase_storage'),
            p_arquivo_ref, p_nome_original, p_assinado, p_hash, p_legibilidade)
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

  -- Pendência de classificação incerta: idempotente por documento. Antes cada
  -- reenvio abria mais uma (documento novo, pendência nova); agora, se já existe
  -- uma aberta para este documento, ela continua sendo a mesma pendência — a
  -- reextração não multiplica cartões na fila do dono.
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
                               'hash', p_hash));

  return jsonb_build_object(
    'documento_id', v_documento_id,
    'documento_versao_id', v_versao_id,
    'n_versao', v_n_versao,
    'reaproveitou_documento', v_reaproveitou
  );
end;
$$;

comment on function fn_registrar_documento(
  uuid, text, text, text, text, numeric, text, origem_arquivo, text, text,
  boolean, text, legibilidade, numeric, text
) is
  'Registra um arquivo classificado (E1). Idempotente por (caso_id, hash): o MESMO arquivo '
  'reenviado/reextraído vira nova documento_versao sob o mesmo documento (n_versao+1), sem '
  'duplicar documento, checklist nem pendência. Hash nulo não casa. Classificação da máquina '
  'não sobrepõe revisão humana (documento.fonte = ''humano'').';
