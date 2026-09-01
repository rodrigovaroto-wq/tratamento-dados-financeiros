-- =============================================================================
-- Migration 0127 — O dial passa a ser OBEDECIDO, e os níveis declarados passam a
--                  ser verdade
--
-- O QUE A 0126 FECHOU, E O QUE ELA DEIXOU ABERTO. A 0126 fez a regra de ouro do
-- `Arquitetura do Sistema/1 Visão e Doutrina/01` ser executada: subir dial de estágio interpretativo para auto-clear
-- passou a exigir concordância medida. Ela cuidou de COMO O DIAL MUDA. Ela não
-- cuidou de o dial ser LIDO.
--
-- E a 0041 já havia diagnosticado exatamente isso, com um comando: «`grep -rl
-- estagio_autonomia portal/src n8n` não retornava NADA — a tabela não tinha um
-- único leitor». Ela consertou para UM estágio, a extração de linhas financeiras.
-- Rodando a mesma busca hoje, estágio por estágio, os outros SETE continuam sem
-- leitor. O efeito é preciso: **mudar o nível de sete dos oito estágios não muda
-- comportamento nenhum.** A mudança é validada contra o teto, cobrada contra
-- golden set pela 0126, gravada na trilha — e inerte.
--
-- E DOIS DOS SETE NÃO SÓ NÃO SÃO LIDOS: ELES DECLARAM O NÍVEL ERRADO.
--
--   • `classificacao_doc_checklist` declara **N1 com limiar 0,95**. Na prática
--     opera como **N2 com limiar 0,70**: `fn_registrar_documento` só abre
--     `classificacao_pendente` abaixo de `p_threshold`, cujo default é 0.7 — e
--     documento com confiança 0,80 entra classificado sem humano nenhum olhar.
--     N1 na doutrina é "humano confirma TODO item"; isto é auto-clear.
--     Pior: o 0,70 mora em DOIS lugares (o default aqui e `THRESHOLD_AUTO` no
--     `N8N/lib/classifier.mjs`), e nenhum dos dois é o dial. Duas réguas sobre a
--     mesma quantidade é a forma de defeito que esta casa já pagou três vezes
--     (a 0123, e o par fatiamento × orçamento).
--
--   • `reconciliacao_classe_bc` declara **N0** — "roda, registra a saída, mas NÃO
--     influencia decisão". Na prática ela ABRE PENDÊNCIA: as checagens B passam
--     `'B'` para `fn_registrar_reconciliacao`, que abre pendência para
--     `divergente` e `zona_cinzenta` sem olhar a classe. Pendência entra na fila
--     do painel e é contada na avaliação do Portão 2 — isso é influenciar. O
--     comportamento é N1, e N1 é o teto dela; não é inseguro, é MAL DECLARADO.
--
-- POR QUE ISSO É PIOR DO QUE PARECE. Quem lê o dial para decidir se confia num
-- achado da Classe B/C conclui "sombra, não influencia" e está errado. E quem
-- baixar a classificação para N1 para forçar revisão de tudo não vai conseguir:
-- hoje o nível não é lido, e depois desta migration ele é — mas com o número que
-- estava de fato em vigor, não com um que nunca foi aplicado.
--
-- O QUE ESTA MIGRATION FAZ, E O QUE ELA NÃO MUDA.
--
-- Ela NÃO muda comportamento nenhum. É a mesma escolha que a 0041 fez, e pelo
-- mesmo motivo: o dial passa a DECLARAR o que o sistema já faz, e a partir daí
-- mudar de verdade passa a ser uma chamada. Concretamente:
--
--   1. `fn_dial_permite_auto` — o leitor ÚNICO. Um só lugar decide "este estágio,
--      nesta confiança, pode seguir sem humano?".
--   2. `fn_dial_influencia` — o leitor de N0: em sombra, o estágio registra e não
--      abre pendência.
--   3. `fn_registrar_documento` passa a tirar o limiar do DIAL em vez do
--      parâmetro. O parâmetro fica como queda para banco sem linha no dial.
--   4. `fn_registrar_reconciliacao` passa a respeitar o nível da classe: em N0
--      registra em `reconciliacao` e NÃO abre pendência.
--   5. As duas declarações são corrigidas para a verdade: classificação para
--      N2/0,70 e Classe B/C para N1.
--
-- A CORREÇÃO DA CLASSIFICAÇÃO PASSA PELO PORTÃO DA 0126, e é bom que passe: N1 →
-- N2 é subida que alcança auto-clear num estágio interpretativo, então ela exige
-- `p_sem_medicao_porque`. Não há golden set, então o motivo vai escrito, a trilha
-- grava `mudanca_dial_sem_medicao`, e o painel passa a mostrar DOIS estágios como
-- "declarada" em vez de um. Não é regressão: é o tamanho real da autonomia não
-- medida, que até agora estava escondido em `p_threshold default 0.7`.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- fn_dial_permite_auto — o leitor único do dial.
--
-- POR QUE UMA FUNÇÃO E NÃO A REGRA COPIADA EM CADA LUGAR. O bloco
-- «`nivel in ('N2','N3')` e `limiar is not null` e `confianca >= limiar`» estava
-- escrito à mão dentro de `fn_registrar_campos_extraidos` (0041). Copiá-lo para
-- mais três funções criaria quatro cópias de uma regra de doutrina — e quando uma
-- delas divergir, o sistema volta a fazer uma coisa e declarar outra, que é
-- exatamente o defeito que a 0041 e a 0126 existem para fechar.
--
-- SEM LINHA NO DIAL, NADA É AUTOMÁTICO. Ausência de configuração não pode virar
-- permissão — é o default seguro que o fechamento #1 do `Arquitetura do Sistema/1 Visão e Doutrina/01` exige
-- ("default-para-humano"). Mesma regra que a 0041 já aplicava.
-- -----------------------------------------------------------------------------
create or replace function fn_dial_permite_auto(p_estagio text, p_confianca numeric)
returns boolean
language sql
stable
as $$
  select coalesce(
    (select ea.nivel_atual in ('N2','N3')
              and ea.limiar_auto_clear is not null
              and p_confianca is not null
              and p_confianca >= ea.limiar_auto_clear
       from estagio_autonomia ea where ea.estagio = p_estagio),
    false);
$$;

comment on function fn_dial_permite_auto(text, numeric) is
  'Este estágio, nesta confiança, pode seguir SEM humano? Leitor único da regra de auto-clear do '
  'Arquitetura do Sistema/1 Visão e Doutrina/01, para ela não existir copiada em quatro funções. Sem linha no dial devolve false: '
  'ausência de configuração não é permissão (fechamento #1, default-para-humano).';

grant execute on function fn_dial_permite_auto(text, numeric) to authenticated;

-- -----------------------------------------------------------------------------
-- fn_dial_influencia — o leitor de N0, que é um nível de significado diferente.
--
-- N0 no `Arquitetura do Sistema/1 Visão e Doutrina/01` é "o estágio roda, registra a saída, mas NÃO influencia
-- decisão". Isso não é sobre limiar: é sobre o resultado poder ou não chegar à
-- fila de alguém. Um estágio em N0 que abre pendência não está em N0.
-- -----------------------------------------------------------------------------
create or replace function fn_dial_influencia(p_estagio text)
returns boolean
language sql
stable
as $$
  select coalesce(
    (select ea.nivel_atual <> 'N0' from estagio_autonomia ea where ea.estagio = p_estagio),
    -- Sem linha no dial, INFLUENCIA. Aqui o default seguro é o oposto do de
    -- fn_dial_permite_auto, e de propósito: calar um achado por falta de
    -- configuração esconderia problema, enquanto auto-aceitar por falta de
    -- configuração criaria fato. Em dúvida, mostre para o humano.
    true);
$$;

comment on function fn_dial_influencia(p_estagio text) is
  'O resultado deste estágio pode chegar à fila de alguém? False só em N0, que o Arquitetura do Sistema/1 Visão e Doutrina/01 define como '
  '"roda, registra, NÃO influencia decisão" — estágio em N0 que abre pendência não está em N0. Sem '
  'linha no dial devolve TRUE (oposto de fn_dial_permite_auto, de propósito: calar achado por falta '
  'de configuração esconde problema; auto-aceitar por falta de configuração cria fato).';

grant execute on function fn_dial_influencia(text) to authenticated;

-- -----------------------------------------------------------------------------
-- fn_registrar_documento — corpo da 0118 com UMA mudança de lógica: o limiar da
-- classificação sai do parâmetro e passa a vir do dial. Ver o comentário no lugar
-- exato da mudança, e o segundo, na descrição da pendência.
-- -----------------------------------------------------------------------------
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
grant execute on function fn_registrar_documento(uuid, text, text, text, text, numeric, text, origem_arquivo, text, text, boolean, text, legibilidade, numeric, text, text) to authenticated;

-- -----------------------------------------------------------------------------
-- fn_registrar_reconciliacao — corpo da 0023 com a classe passando a ser lida no
-- dial, e um ramo novo para o caso que faltava: sombra COM divergência presente.
-- -----------------------------------------------------------------------------
create or replace function fn_registrar_reconciliacao(
  p_caso_id       uuid,
  p_entidade_id   uuid,
  p_periodo_id    uuid,
  p_tipo          text,
  p_classe        text,
  p_documento_id  uuid,
  p_fonte_a       jsonb,
  p_fonte_b       jsonb,
  p_resultado     text,
  p_divergencia_abs numeric,
  p_divergencia_pct numeric,
  p_materialidade jsonb,
  p_descricao     text
)
returns jsonb
language plpgsql
as $$
declare
  v_reconciliacao_id uuid;
  v_pendencia_id     uuid;
  v_motivo           text := 'reconciliacao:' || p_tipo;
  -- 'documento_ausente' é um resultado NOSSO, para decidir a pendência; no log
  -- ele é gravado como pré-condição não satisfeita (é o que ele é).
  v_res_log          text := case when p_resultado = 'documento_ausente'
                                  then 'precondicao_nao_satisfeita' else p_resultado end;
  -- 0127: a decisão passa para o corpo, porque agora ela depende do DIAL da
  -- classe — e o dial não se lê no declare sem esconder a regra.
  v_divergente       boolean := p_resultado not in ('ok', 'documento_ausente');
  v_abre_pendencia   boolean;
  v_estagio_dial     text;
  v_influencia       boolean;
begin
  -- 0127: O DIAL DA CLASSE DECIDE SE O ACHADO CHEGA À FILA DE ALGUÉM.
  --
  -- `reconciliacao_classe_bc` declarava N0 — "roda, registra a saída, mas NÃO
  -- influencia decisão" (Arquitetura do Sistema/1 Visão e Doutrina/01) — e abria pendência: as checagens B passam 'B'
  -- para cá e esta função nunca olhou a classe. Pendência entra na fila do painel
  -- e é contada na avaliação do Portão 2; isso é influenciar. O comportamento era
  -- N1, que é o teto dela — não era inseguro, era MAL DECLARADO.
  --
  -- Note que o registro em `reconciliacao` acontece SEMPRE, inclusive em N0: "roda
  -- e registra" é a primeira metade da definição de sombra, e é ela que permite
  -- medir um estágio antes de confiar nele.
  v_estagio_dial := case when upper(coalesce(p_classe, 'A')) = 'A'
                         then 'reconciliacao_classe_a'
                         else 'reconciliacao_classe_bc' end;
  v_influencia := fn_dial_influencia(v_estagio_dial);
  v_abre_pendencia := v_divergente and v_influencia;

  insert into reconciliacao
    (caso_id, entidade_id, periodo_id, tipo, classe, fonte_a, fonte_b,
     precondicoes_ok, resultado, divergencia_abs, divergencia_pct, materialidade)
  values (
    p_caso_id, p_entidade_id, p_periodo_id, p_tipo, p_classe, p_fonte_a, p_fonte_b,
    v_res_log <> 'precondicao_nao_satisfeita', v_res_log,
    p_divergencia_abs, p_divergencia_pct, p_materialidade
  )
  returning id into v_reconciliacao_id;

  select id into v_pendencia_id from pendencia
  where caso_id = p_caso_id and motivo = v_motivo
    and coalesce(entidade_id, '00000000-0000-0000-0000-000000000000'::uuid)
      = coalesce(p_entidade_id, '00000000-0000-0000-0000-000000000000'::uuid)
    -- Período COMPATÍVEL, não igual: a mesma checagem chega por dois documentos
    -- com granularidade diferente (DRE "multi 24,25" × Faturamento "L24M") e sem
    -- isso o mesmo achado abriria duas pendências.
    and (periodo_id is not distinct from p_periodo_id
         or fn_periodos_compativeis(periodo_id, p_periodo_id))
    and estado <> 'resolvida'
  order by criada_em
  limit 1;

  if v_abre_pendencia then
    if v_pendencia_id is null then
      insert into pendencia
        (caso_id, origem_estagio, tipo, severidade, sobrepujavel, descricao,
         documento_id, entidade_id, periodo_id, motivo)
      values (
        p_caso_id, 'reconciliacao',
        case when v_res_log = 'precondicao_nao_satisfeita' then 'precondicao_nao_satisfeita'
             else 'divergencia_reconciliacao' end::pendencia_tipo,
        'importante', true, p_descricao, p_documento_id, p_entidade_id, p_periodo_id, v_motivo
      )
      returning id into v_pendencia_id;
    else
      update pendencia set descricao = p_descricao where id = v_pendencia_id;
    end if;
  elsif v_divergente and not v_influencia then
    -- 0127: SOMBRA COM DIVERGÊNCIA PRESENTE — e este ramo existe para não mentir.
    --
    -- Sem ele, este caso cairia no `elsif` de baixo e a pendência aberta seria
    -- marcada "resolvida por sistema:reconciliacao". Mas o sintoma NÃO sumiu: o
    -- estágio foi silenciado. Resolver aqui escreveria na trilha que o problema
    -- acabou, quando o que acabou foi o direito daquele estágio de falar — e a
    -- trilha é append-only justamente para não permitir esse tipo de reescrita.
    --
    -- Então: registra em sombra, e deixa em paz a pendência que um humano já pode
    -- estar tratando.
    insert into evento_auditoria (ator, acao, entidade_ref, depois)
      values ('sistema:reconciliacao', 'reconciliacao_em_sombra',
              'reconciliacao:' || v_reconciliacao_id,
              jsonb_build_object('estagio', v_estagio_dial, 'classe', p_classe,
                                 'tipo', p_tipo, 'resultado', p_resultado,
                                 'divergencia_abs', p_divergencia_abs,
                                 'pendencia_preexistente', v_pendencia_id,
                                 'porque', 'estagio em N0: registra e nao abre pendencia (Arquitetura do Sistema/1 Visão e Doutrina/01). '
                                           'Pendencia anterior, se existe, NAO foi resolvida: o '
                                           'sintoma nao sumiu, o estagio foi silenciado.'));

  elsif v_pendencia_id is not null then
    -- Sumiu o sintoma (reextração corrigiu, ou a pendência era falsa e a regra
    -- nova não a emite mais): fecha. Não escreve número nenhum em base viva.
    update pendencia set estado = 'resolvida', resolvida_em = now(),
           resolvida_por = 'sistema:reconciliacao'
    where id = v_pendencia_id;
    v_pendencia_id := null;
  end if;

  insert into evento_auditoria (ator, acao, entidade_ref, depois)
    values ('sistema:reconciliacao', 'reconciliacao_' || p_tipo,
            'reconciliacao:' || v_reconciliacao_id,
            jsonb_build_object('resultado', p_resultado, 'divergencia_abs', p_divergencia_abs));

  return jsonb_build_object(
    'reconciliacao_id', v_reconciliacao_id, 'tipo', p_tipo,
    'resultado', p_resultado, 'pendencia_id', v_pendencia_id
  );
end;
$$;
-- Sem `grant` aqui de propósito: fn_registrar_reconciliacao nunca foi exposta ao
-- portal — ela é chamada só por outras funções SQL, e o schema materializado
-- confirma que ela não tem grant. Acrescentar um mudaria o dump sem motivo.

-- =============================================================================
-- E OS DOIS NÍVEIS DECLARADOS PASSAM A SER VERDADE.
--
-- Nada de comportamento muda aqui. O que muda é que o estado declarado do sistema
-- para de contradizer o que ele faz — a mesma coisa que a 0041 fez para a
-- extração, e pelo mesmo motivo dela: enquanto a contradição existe, ninguém
-- consegue usar o dial nem para conferir nem para mudar.
-- =============================================================================

do $$
declare v_r jsonb;
begin
  -- --- classificação documento→checklist: N1/0,95 declarado → N2/0,70 real ----
  --
  -- Ela SEMPRE operou como N2: `fn_registrar_documento` só abria pendência abaixo
  -- do limiar, e acima dele o documento entrava classificado sem revisão. O 0,95
  -- que o dial trazia nunca foi aplicado por ninguém — o número em vigor era o
  -- 0,70 do `p_threshold`.
  --
  -- Esta subida passa pelo portão da 0126 (N1 → N2 alcança auto-clear em estágio
  -- interpretativo), então precisa de motivo assumido. É exatamente o que se quer:
  -- a autonomia que estava escondida num default de parâmetro passa a estar
  -- declarada, contável, e visível na tela como "declarada, não medida".
  v_r := fn_mudar_dial(
    'classificacao_doc_checklist', 'N2', 'sistema:0127',
    'Declara o N2 que a classificação já praticava desde sempre: fn_registrar_documento '
    'auto-aceitava acima de p_threshold (0,70) e só abria pendência abaixo. Não muda '
    'comportamento — o limiar declarado passa a ser o que está de fato em vigor.',
    0.70, null,
    'A classificação nunca teve golden set. Este N2 é o comportamento existente sendo '
    'declarado, não uma subida de autonomia: antes da 0127 o nível não era lido por '
    'ninguém e o limiar vinha do código, em dois lugares (p_threshold e THRESHOLD_AUTO '
    'no classifier.mjs). Quando houver golden set, a medição confirma ou derruba.');
  if coalesce((v_r->>'recusado')::boolean, false) then
    raise exception '0127 não conseguiu declarar o dial da classificação: %', v_r->>'motivo_recusa';
  end if;
  raise notice '0127: classificacao_doc_checklist declarada em % (base %), limiar %',
    v_r->>'nivel_atual', v_r->>'base_do_nivel', v_r->>'limiar_auto_clear';

  -- --- reconciliação Classe B/C: N0 declarado → N1 real -----------------------
  --
  -- Ela abre pendência desde a 0015, e pendência entra na fila e conta na
  -- avaliação do Portão 2. Isso é N1 ("a saída aparece como sugestão; humano
  -- confirma todo item"), não N0 ("não influencia decisão").
  --
  -- N1 é o TETO dela, e o Arquitetura do Sistema/1 Visão e Doutrina/01 marca esse teto como "nunca autônomo". Então
  -- esta correção a leva ao teto sem nenhuma folga sobrando — e não passa pelo
  -- portão da regra de ouro, porque N1 não é auto-clear: nada é automatizado, o
  -- humano continua decidindo item por item. É a distinção que a 0126 declara no
  -- cabeçalho, e este é o primeiro caso real dela.
  v_r := fn_mudar_dial(
    'reconciliacao_classe_bc', 'N1', 'sistema:0127',
    'Declara o N1 que a Classe B/C já praticava: ela abre pendência desde a 0015, e pendência '
    'na fila é influência sobre decisão — o que N0 exclui por definição. Não muda '
    'comportamento; corrige a declaração. N1 é o teto dela e continua sendo.');
  if coalesce((v_r->>'recusado')::boolean, false) then
    raise exception '0127 não conseguiu declarar o dial da Classe B/C: %', v_r->>'motivo_recusa';
  end if;
  raise notice '0127: reconciliacao_classe_bc declarada em % (teto %)',
    v_r->>'nivel_atual', v_r->>'teto';
end $$;

-- -----------------------------------------------------------------------------
-- O QUE ESTA MIGRATION DELIBERADAMENTE NÃO FAZ, e por quê.
--
-- `extracao_identificadores` continua sem leitor, e não é esquecimento: para
-- obedecer ao dial ele precisa de uma CONFIANÇA que hoje não chega ao banco.
-- `fn_registrar_diagnostico` recebe `p_tipo_confirma boolean` — a decisão já vem
-- tomada do nó do n8n, e um dial no banco não alcança decisão tomada fora dele.
-- Fechar isso exige acrescentar a confiança à assinatura E mudar o nó, o que
-- obriga a REIMPORTAR o workflow. Fica nomeado como a fatia seguinte, em vez de
-- entrar pela metade aqui.
--
-- Os dois estágios DETERMINÍSTICOS (`validacao_formal`, `completude_portao1`)
-- também seguem sem leitor, e aqui a razão é de natureza: a garantia deles é
-- aritmética e integridade de arquivo, não concordância humana. Baixá-los para
-- N1 significaria "todo resultado de validação formal vira sugestão a confirmar",
-- que é uma capacidade sem uso conhecido. Se um dia houver o uso, o leitor entra
-- com ele — construir agora seria adivinhar a forma.
-- -----------------------------------------------------------------------------
