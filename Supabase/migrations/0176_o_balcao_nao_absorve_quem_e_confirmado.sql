-- =============================================================================
-- 0176 — O BALCÃO AMBÍGUO GANHOU CNPJ NA 0175, E PASSOU A ABSORVER QUEM É
--        CONFIRMADO — CINCO DEFEITOS DA REVISÃO DA 0175, NUMA FATIA SÓ
--
-- A 0175 (já commitada, `f549842`) fez o ramo do balcão ambíguo de
-- `fn_registrar_diagnostico` tentar o CNPJ antes do nome — e funciona: dois
-- balcões da mesma empresa convergem (`Supabase/test/balcao_ambiguo_e_cnpj.test.sql`,
-- 18 asserts, continuam passando depois desta migration). Uma revisão
-- independente (`revisor-defeito-silencioso`) mediu, com dois bancos
-- Postgres (um com a 0175, um sem), CINCO defeitos que sobrevivem à leitura.
-- Esta migration corrige os cinco, cada um MEDIDO com a correção desligada
-- antes de escrever a correção (regra 2 do CLAUDE.md).
--
-- =============================================================================
-- CRÍTICO — o balcão passou a carregar CNPJ, e todo o resto do sistema desde
-- a 0169 trata "mesmo CNPJ" como identidade CONFIRMADA, sem olhar nome. O
-- balcão nunca teve o nome confirmado — é POR ISSO que ele existe. A 0175
-- abriu dois buracos de absorção silenciosa (regra 1 do CLAUDE.md: ausência
-- fabricada como dado):
--
--   (A) `fn_upsert_entidade`, ramo (0) — 0169: quando um documento NOVO
--       chega com um CNPJ que já pertence a um balcão (o cenário real: o
--       CNPJ do RODAPÉ do contador, coincidência entre clientes distintos do
--       mesmo escritório), o ramo devolvia o id do balcão DIRETO, sem checar
--       `fn_entidade_e_balcao_ambiguo`. MEDIDO nesta sessão, contra o estado
--       da 0175 (banco `tdf_test`, caso sintético com os nomes/CNPJ reais da
--       OMNIBEAUTY): um documento de "OUTRA METALURGICA NOVA SA" trazendo o
--       CNPJ do balcão OMNIBEAUTY foi registrado DENTRO do balcão —
--       `entidade_id` do documento novo apontava para a linha do balcão, e
--       o caso continuou com 3 entidades (o balcão nunca soltou uma linha
--       própria para a metalúrgica; seria 4 se ela tivesse nascido).
--   (B) `fn_entidade_aprender_cnpj` (chamada também pelo ramo do balcão desde
--       a 0175): quando uma entidade JÁ CONFIRMADA (documento próprio, nome
--       validado pelo ramo `else` desde a 0172/0174) traz um CNPJ que já
--       está gravado no balcão (via o caso A, ou via a convergência
--       balcão↔balcão da própria 0175), a função FUNDE a confirmada DENTRO
--       do balcão — `fn_fundir_entidade` DELETA a linha da confirmada. MEDIDO
--       nesta sessão, mesmo cenário: uma "VERTENTES METALURGICA LTDA"
--       registrada com documento e nome próprios, ao receber pelo
--       diagnóstico o MESMO CNPJ do rodapé (agora já gravado no balcão),
--       desaparece — `exists(select 1 from entidade where id = <metalúrgica>)`
--       vira `false`, o caso cai de 4 para 3 entidades, e o balcão sobrevivente
--       mantém o PRÓPRIO nome truncado. Rastro existe em `evento_auditoria`
--       (`entidade_fundida`), mas NENHUMA pendência acusa — é exatamente o
--       dano que o comentário do ramo `else` de `fn_registrar_diagnostico`
--       já nomeava desde a 0172 ("por uma razão de segurança... esse CNPJ
--       passaria a ATRAIR todo documento futuro da empresa de verdade para
--       dentro da entidade errada, sem olhar nome") — a 0175 abriu essa
--       porta pelo lado do balcão, sem essa guarda.
--
-- A CAUSA RAIZ: até a 0175, "entidade tem CNPJ" e "entidade tem CNPJ
-- CONFIRMADO" eram a MESMA coisa por CONSTRUÇÃO — nenhum balcão jamais tinha
-- CNPJ. A 0175 quebrou essa construção sem substituí-la por uma checagem
-- explícita.
--
-- A CORREÇÃO: um balcão ambíguo só pode ser o lado que RECEBE/SOBREVIVE via
-- CNPJ quando quem está sendo fundido ou atribuído a ele é, ele também, um
-- balcão ambíguo — a convergência balcão↔balcão que é o PONTO da 0175, e que
-- continua funcionando (ver a suíte 0175 na lista de testes abaixo). Quando o
-- outro lado é uma entidade CONFIRMADA (documento novo por registrar, ou
-- entidade já existente e validada), o balcão NÃO absorve: a colisão vira uma
-- PENDÊNCIA nova (`fn_pendencia_cnpj_colide_balcao`, motivo
-- `entidade_cnpj_colide_balcao:<balcão>`, tipo `entidade_incorreta`,
-- `importante`, `sobrepujavel`) descrevendo o CNPJ suspeito e QUEM colidiu, e
-- o caminho normal (nome, entidade nova) decide exatamente como decidiria se
-- o balcão nunca tivesse aprendido este CNPJ — sem tentar gravar o CNPJ
-- colidido em lugar nenhum (evita também a violação de
-- `entidade_caso_cnpj_unico` que a tentativa causaria).
--
-- Reemite `fn_entidade_aprender_cnpj` e `fn_upsert_entidade` INTEIRAS,
-- verbatim do corpo vigente com só esta mudança — nunca por âncora de texto
-- em corpo de função (.claude/memory/nunca-corrigir-funcao-por-replace.md).
--
-- =============================================================================
-- ALTO — nome desatualizado na pendência depois da fusão/renomeio. Dentro de
-- `fn_registrar_diagnostico`, `v_entidade_atual_nome` é lido UMA vez, ANTES
-- do bloco novo da 0175, e usado — sem reconferir — para montar a descrição
-- da pendência `diagnostico:entidade_ambigua_respondida:<doc>` depois que
-- esse bloco pode ter FUNDIDO (a linha antiga foi deletada) ou RENOMEADO a
-- entidade. MEDIDO nesta sessão contra o cenário da própria 0175 (rodando
-- `Supabase/test/balcao_ambiguo_e_cnpj.test.sql` e consultando a pendência
-- do segundo diagnóstico): a pendência do documento do segundo balcão dizia
-- "...registrado numa entidade própria ("OMNIBEAUTY DESENVOLVIMENTO E
-- GESTAO")" — o nome do balcão FUNDIDO, já apagado da tabela `entidade` —
-- enquanto a entidade referenciada (`entidade_id` da pendência, o balcão
-- SOBREVIVENTE) se chama "OMNIBEAUTY DESENVOLVIMENTO E GESTAO DE". A
-- correção reconfere `razao_social` (de `v_entidade_id`, já atualizado pelo
-- bloco novo) antes de montar a descrição.
--
-- =============================================================================
-- MÉDIO 1 — `fn_entidade_talvez_renomear` recebia o CNPJ BRUTO do parâmetro
-- (`p_cnpj`) mesmo quando `fn_entidade_aprender_cnpj` voltou SEM gravar nada
-- nesta entidade (porque ela já tinha outro CNPJ — guarda antiga da 0169 —
-- ou, agora, porque o CRÍTICO acima recusou a fusão). MEDIDO nesta sessão:
-- uma entidade com `cnpj = 11222333000181` (o CNPJ real, aprendido antes) foi
-- "renomeada por CNPJ" com o evento `entidade_renomeada_por_cnpj` gravando
-- `{"cnpj": "36193378000104", ...}` — o CNPJ ESTRANHO à entidade, só porque
-- era o `p_cnpj` deste documento. A correção relê o CNPJ REAL da entidade
-- depois do `aprender` e só chama o renomeio quando ele bate com o `p_cnpj`
-- recebido — ou seja, quando o `aprender` de fato ESTABELECEU este CNPJ
-- nesta entidade. O MESMO padrão (passar `p_cnpj` bruto para o renomeio) já
-- existe no ramo `else` desde a 0173 — FORA DO ESCOPO desta fatia (o ramo
-- `else` só aprende CNPJ quando o NOME já confirmou a entidade, então o risco
-- prático é menor, mas não é zero: uma entidade confirmada que já tivesse
-- OUTRO cnpj gravado teria o mesmo sintoma). Registrado para o
-- `MAPA_DE_EXECUCAO.md`.
--
-- =============================================================================
-- MÉDIO 2 — "todo balcão ambíguo nasce sem CNPJ" (afirmado no cabeçalho e no
-- `porque` da 0175) é FALSO desde a 0170: `fn_upsert_entidade`, no ramo de
-- ambiguidade (`v_n > 1`, sem grupo), grava `v_cnpj` no `insert into entidade`
-- quando ele vier disponível — e `p_cnpj` chega a `fn_upsert_entidade` desde
-- a 0170 (`fn_registrar_documento` sempre o repassa, na CLASSIFICAÇÃO, não só
-- no diagnóstico). MEDIDO nesta sessão: um balcão nascido por nome ambíguo
-- (nenhum candidato exato, nenhum grupo) COM `p_cnpj` não-nulo na chamada de
-- registro nasce com `entidade.cnpj` já preenchido —
-- `fn_entidade_e_balcao_ambiguo` = true e `cnpj` não-nulo na MESMA linha,
-- contra a afirmação do cabeçalho da 0175.
--
-- MEDIDO SE ISSO QUEBRA A CONVERGÊNCIA (a pergunta que importa, não o texto
-- sozinho): com a guarda do CRÍTICO desta migration em `fn_upsert_entidade`
-- (ramo 0), uma SEGUNDA entidade nunca é inserida com um CNPJ que um balcão
-- já detém — a colisão vira pendência e o CNPJ é tratado como ausente para o
-- resto daquela chamada (nem grava, nem funde). Como o índice
-- `entidade_caso_cnpj_unico` já impede DUAS linhas do mesmo caso com o MESMO
-- CNPJ não-nulo simultaneamente, e a ÚNICA outra gravação de `entidade.cnpj`
-- do sistema é `fn_entidade_aprender_cnpj` (também guardada pelo CRÍTICO), o
-- cenário "dois balcões nascem AMBOS já com o CNPJ certo, e nenhum dos dois
-- nunca busca `v_outra_id`" não ocorre em nenhuma sequência de chamadas
-- alcançável por este código — o segundo balcão nasceria SEM o CNPJ (colisão
-- registrada, pendência aberta) e convergiria depois pelo caminho normal da
-- 0175 (os dois são balcões, a guarda do CRÍTICO permite). CONCORRÊNCIA REAL
-- (duas transações lendo o mesmo `select` antes de qualquer `insert`
-- comitar) fica FORA do escopo desta fatia — é um risco pré-existente do
-- índice único, não introduzido aqui, e nenhum teste desta casa cobre
-- concorrência em `fn_upsert_entidade` hoje.
--
-- CORREÇÃO APLICADA: só o TEXTO — o `porque` do requisito
-- `balcao_ambiguo_aprende_cnpj` é corrigido abaixo (`update`), e o cabeçalho
-- desta migration é o registro da medição. Nenhuma mudança de código além do
-- CRÍTICO, que já fecha o buraco por outro caminho.
--
-- =============================================================================
-- MÉDIO 3 — dois marcadores da sonda colidem. `position(marcador in corpo) > 0`
-- é toda a lógica de match (`0147`) — não conta ocorrências, só presença.
--
--   1. O marcador de `balcao_ambiguo_aprende_cnpj` (`'if p_cnpj is not null
--      then'`) é específico HOJE, mas casaria com qualquer bloco futuro que
--      comece por essa condição em QUALQUER lugar da função, sem a lógica da
--      0175 precisar estar presente. Novo marcador, amarrado ao código do
--      MÉDIO 1 desta migration (só existe por causa dele):
--      `'fn_cnpj_canonico(v_entidade_cnpj_pos_aprender) = fn_cnpj_canonico(p_cnpj)'`.
--      CONFIRMADO por contagem (`grep -c` contra o `schema.sql` regenerado):
--      bloco comentado → 0 ocorrências; bloco de volta → 1.
--   2. O marcador de `renomeio_no_diagnostico`
--      (`'fn_entidade_talvez_renomear(v_caso_id, v_entidade_id'`) aparecia
--      2 VEZES no corpo — a chamada original do ramo `else` (0173) e a nova
--      do ramo do balcão (0175), texto IDÊNTICO. MEDIDO nesta sessão:
--      `grep -c` contra o `schema.sql` do estado da 0175 devolve `2`. Se uma
--      reemissão futura removesse a chamada original (0173) mas deixasse a
--      do balcão, o requisito continuaria "presente" com o comportamento que
--      ele deveria proteger (renomeio nos ~50% dos documentos que passam por
--      classificação) quebrado. O MÉDIO 1 desta migration já torna as DUAS
--      chamadas textualmente diferentes (a do balcão passa
--      `v_entidade_cnpj_pos_aprender`, não `p_cnpj` bruto) — o novo marcador
--      usa o texto COMPLETO da chamada do ramo `else`, que agora só casa com
--      ELA: `'fn_entidade_talvez_renomear(v_caso_id, v_entidade_id, p_entidade_nome, p_cnpj)'`.
--      CONFIRMADO por contagem depois desta migration: 1 ocorrência (não 2).
--      Migration do requisito continua `'0173'` — é a CHAVE que importa, não
--      o número da migration que a atualiza (precedente: a própria 0173 já
--      reapontou `cnpj_renomeia`).
--
-- =============================================================================
create or replace function fn_pendencia_cnpj_colide_balcao(
  p_caso_id uuid, p_balcao_id uuid, p_cnpj text, p_nome_outro text,
  p_entidade_outro_id uuid default null
) returns uuid
    language plpgsql
    as $$
declare
  v_cnpj        text := fn_cnpj_canonico(p_cnpj);
  v_balcao_nome text;
  v_motivo      text;
  v_desc        text;
  v_pend        uuid;
begin
  select razao_social into v_balcao_nome from entidade where id = p_balcao_id;
  if v_balcao_nome is null then return null; end if;

  -- Uma pendência por BALCÃO colidido, não por documento — o mesmo desenho
  -- de `fn_pendencia_entidade_ambigua` (0153): vários documentos batendo na
  -- mesma colisão fazem UMA pergunta, não uma enxurrada.
  v_motivo := 'entidade_cnpj_colide_balcao:' || p_balcao_id;

  v_desc := format(
    'O balcão ambíguo "%s" (nome ainda NÃO confirmado — foi criado porque casa com MAIS DE UMA '
    || 'empresa deste mandato) já tinha aprendido o CNPJ %s. "%s" chegou com o MESMO CNPJ sem '
    || 'ser, ela própria, um balcão ambíguo — pela regra "balcão só absorve balcão", o sistema '
    || 'NÃO fundiu nem atribuiu este documento/entidade a ele; o caminho normal (nome, entidade '
    || 'própria) decidiu como decidiria se o balcão nunca tivesse este CNPJ. Confira de quem é o '
    || 'CNPJ: se for mesmo de "%s", funda manualmente com fn_fundir_entidade; se for coincidência '
    || '(ex.: CNPJ do escritório de contabilidade no rodapé do relatório), o CNPJ pode estar '
    || 'gravado na entidade ERRADA (o balcão) e vale reavaliar quem deveria tê-lo.',
    v_balcao_nome, coalesce(v_cnpj, p_cnpj), p_nome_outro, p_nome_outro);

  select id into v_pend from pendencia
   where caso_id = p_caso_id and motivo = v_motivo and estado <> 'resolvida'
   limit 1;

  if v_pend is not null then
    update pendencia set descricao = v_desc where id = v_pend;
  else
    insert into pendencia
      (caso_id, origem_estagio, tipo, severidade, sobrepujavel, descricao, entidade_id, motivo)
      values (p_caso_id, 'diagnostico', 'entidade_incorreta', 'importante', true,
              v_desc, p_balcao_id, v_motivo)
      returning id into v_pend;
  end if;

  insert into evento_auditoria (ator, acao, entidade_ref, depois)
    values ('sistema:entidade', 'entidade_cnpj_colisao_recusada', 'entidade:' || p_balcao_id,
      jsonb_build_object('caso_id', p_caso_id, 'balcao_id', p_balcao_id, 'cnpj', v_cnpj,
                         'nome_outro', p_nome_outro, 'entidade_outro_id', p_entidade_outro_id,
                         'porque', 'balcão ambíguo só absorve via CNPJ quando o outro lado também é balcão'));

  return v_pend;
end;
$$;

comment on function fn_pendencia_cnpj_colide_balcao(uuid, uuid, text, text, uuid) is
  '0176: registra (idempotente por balcão) a colisão de CNPJ entre um balcão ambíguo e uma '
  'entidade CONFIRMADA (documento novo por registrar, ou entidade já existente) que trouxe o '
  'MESMO CNPJ — o caso em que o balcão NÃO PODE absorver (ver o CRÍTICO da 0176). Não decide de '
  'quem é o CNPJ: só nomeia a colisão para revisão humana, com rastro em evento_auditoria '
  '(entidade_cnpj_colisao_recusada).';

-- -----------------------------------------------------------------------------
-- fn_entidade_aprender_cnpj — reemitida inteira, corpo vigente + a guarda do
-- CRÍTICO (caso B).
-- -----------------------------------------------------------------------------
create or replace function fn_entidade_aprender_cnpj(p_entidade_id uuid, p_cnpj text) returns uuid
    language plpgsql
    as $$
declare
  v_cnpj       text := fn_cnpj_canonico(p_cnpj);
  v_caso_id    uuid;
  v_nome_atual text;
  v_cnpj_atual text;
  v_outra_id   uuid;
begin
  if p_entidade_id is null or v_cnpj is null then return p_entidade_id; end if;

  select caso_id, razao_social, cnpj into v_caso_id, v_nome_atual, v_cnpj_atual
    from entidade where id = p_entidade_id;
  if v_caso_id is null then return p_entidade_id; end if;

  -- `cnpj is not null`, NÃO `fn_cnpj_canonico(cnpj) is not null` — a diferença
  -- é a mesma da versão original (0169): com o canônico, um CNPJ INVÁLIDO já
  -- gravado por uma pessoa seria SOBRESCRITO pelo que a IA leu. Coluna vazia é
  -- ausência; coluna com número ruim é registro humano que só humano corrige.
  if v_cnpj_atual is not null then
    return p_entidade_id;
  end if;

  -- 0174: OUTRA entidade do MESMO CASO pode já ter este CNPJ — é o cenário
  -- inteiro desta migration. Ver o cabeçalho para a medição em produção.
  select id into v_outra_id
    from entidade
   where caso_id = v_caso_id and id <> p_entidade_id
     and fn_cnpj_canonico(cnpj) = v_cnpj
   limit 1;

  if v_outra_id is not null then
    -- 0176 (CRÍTICO): um balcão ambíguo só pode ser o lado que RECEBE via
    -- CNPJ quando quem está sendo fundido NELE é, ele também, um balcão
    -- ambíguo — a convergência balcão↔balcão que é o PONTO da 0175. Quando
    -- `v_outra_id` (quem já tinha o CNPJ) é um balcão e `p_entidade_id`
    -- (quem está tentando aprender) NÃO é — uma entidade CONFIRMADA, com
    -- documento e nome próprios — fundir aqui apagaria a confirmada DENTRO
    -- do balcão. MEDIDO (0176, ver o cabeçalho): uma entidade confirmada
    -- desaparecia (fn_fundir_entidade a deleta) e o book somava duas
    -- empresas diferentes numa entidade só, com rastro em evento_auditoria
    -- mas SEM pendência nenhuma acusando. É exatamente o dano que o
    -- comentário do ramo `else` de fn_registrar_diagnostico já nomeava
    -- ("por uma razão de segurança") — a 0175 abriu essa porta sem esta
    -- guarda.
    if fn_entidade_e_balcao_ambiguo(v_caso_id, v_outra_id) and not fn_entidade_e_balcao_ambiguo(v_caso_id, p_entidade_id) then
      perform fn_pendencia_cnpj_colide_balcao(v_caso_id, v_outra_id, v_cnpj, v_nome_atual, p_entidade_id);
      return p_entidade_id;
    end if;

    -- FUNDE sem perguntar ao nome — é a MESMA regra 1 da 0169 ("CNPJ é a
    -- identidade que o nome não é"), chegando pela porta do diagnóstico em
    -- vez da porta de registro. `fn_fundir_entidade` já move documentos,
    -- checklist, pendências e reconciliações, resolve a pendência de
    -- ambiguidade da entidade fundida, e grava `entidade_fundida` com os
    -- dois nomes e quantos documentos mudaram de dono — o mesmo rastro que a
    -- fusão retroativa da OMNIBEAUTY usou.
    perform fn_fundir_entidade(v_caso_id, p_entidade_id, v_outra_id, 'sistema:entidade');

    -- E o nome sobrevivente pode não ser o mais completo dos dois — quem
    -- decide são as MESMAS três guardas da 0171/0173 (só entre truncamentos,
    -- nunca cria homônima, recusa com rastro), com o nome da entidade que
    -- acabou de ser fundida (`v_nome_atual`, capturado ANTES da fusão —
    -- depois dela a linha não existe mais para ler).
    perform fn_entidade_talvez_renomear(v_caso_id, v_outra_id, v_nome_atual, v_cnpj);

    return v_outra_id;
  end if;

  update entidade set cnpj = v_cnpj where id = p_entidade_id;
  insert into evento_auditoria (ator, acao, entidade_ref, antes, depois)
  values ('sistema:entidade', 'entidade_cnpj_aprendido', 'entidade:' || p_entidade_id,
          jsonb_build_object('cnpj', v_cnpj_atual),
          jsonb_build_object('cnpj', v_cnpj, 'como', 'aprendido de um documento posterior'));

  return p_entidade_id;
end;
$$;

comment on function fn_entidade_aprender_cnpj(p_entidade_id uuid, p_cnpj text) is
  'Grava o CNPJ numa entidade que ainda não tem um, com rastro (0169). Nunca sobrescreve: um CNPJ '
  'já gravado na MESMA entidade (mesmo que divergente) é decisão de humano. 0174: quando o CNPJ já '
  'pertence a OUTRA entidade do mesmo caso, funde as duas (fn_fundir_entidade) em vez de tentar '
  'gravar — sem isso o UPDATE violava entidade_caso_cnpj_unico e derrubava fn_registrar_diagnostico '
  'inteira. 0176: EXCETO quando quem já tem o CNPJ é um balcão ambíguo (0162/0175) e quem está '
  'aprendendo NÃO é — aí a fusão APAGARIA uma entidade CONFIRMADA dentro de um balcão sem nome '
  'validado; a colisão vira pendência (fn_pendencia_cnpj_colide_balcao) e nada funde. Devolve o id '
  'da entidade que sobrou: SEMPRE use o retorno, nunca o id que foi passado — depois de uma fusão '
  'ele pode apontar para uma linha deletada.';

-- -----------------------------------------------------------------------------
-- fn_upsert_entidade — reemitida inteira, corpo vigente + a guarda do
-- CRÍTICO (caso A).
-- -----------------------------------------------------------------------------
create or replace function fn_upsert_entidade(p_caso_id uuid, p_nome text, p_cnpj text DEFAULT NULL::text) returns uuid
    language plpgsql
    as $$
declare
  v_id         uuid;
  v_n          int;
  v_candidatos text;
  v_nomes      text[];
  v_cnpj       text := fn_cnpj_canonico(p_cnpj);
  v_nome_atual text;
begin
  -- 0153: no empate, não escolhe. (E o requisito de sonda `entidade_ambigua_nao_decide`
  -- tem o literal "0153" como MARCADOR DE CORPO — tirar esta linha derruba a sonda
  -- sem mudar comportamento nenhum. Achado ao rodar a suíte desta fatia.)
  if p_nome is null or length(trim(p_nome)) = 0 then return null; end if;

  -- (0) 0169: CNPJ IGUAL É A MESMA EMPRESA, e ele não pergunta o nome. É esta
  -- regra que funde as variantes truncadas em QUALQUER ordem de chegada —
  -- a 0168 só conseguia quando a ordem ajudava.
  if v_cnpj is not null then
    -- `order by` sem efeito prático desde a 0169: o índice único
    -- `entidade_caso_cnpj_unico (caso_id, cnpj)` garante NO MÁXIMO uma linha.
    -- Fica como documentação da invariante, não como desempate de verdade.
    select e.id, e.razao_social into v_id, v_nome_atual
    from entidade e
    where e.caso_id = p_caso_id and fn_cnpj_canonico(e.cnpj) = v_cnpj
    order by length(e.razao_social) desc, e.razao_social
    limit 1;

    if v_id is not null then
      -- 0176 (CRÍTICO, caso A): quem já tem este CNPJ pode ser, desde a
      -- 0175, um balcão ambíguo — e o documento que está chegando AGORA
      -- (ainda sem entidade nenhuma, muito menos ambígua) não é, ele
      -- próprio, um balcão. Pela regra "balcão só absorve balcão", esta
      -- entidade NÃO pode ser devolvida direto. MEDIDO (0176): um documento
      -- novo de OUTRA empresa (mesmo CNPJ de rodapé de contador) virava
      -- absorvido pelo balcão sem nunca ganhar linha própria — entidades no
      -- caso ficavam em 3 em vez de virarem 4. Trata o CNPJ como se nunca
      -- tivesse chegado (`v_cnpj := null`) para o resto desta chamada: sem
      -- isso, o `insert` do fim desta função tentaria gravar este MESMO
      -- CNPJ numa entidade nova e violaria `entidade_caso_cnpj_unico` — e,
      -- pior, atribuiria à empresa nova um CNPJ que pode não ser dela.
      if fn_entidade_e_balcao_ambiguo(p_caso_id, v_id) then
        perform fn_pendencia_cnpj_colide_balcao(p_caso_id, v_id, v_cnpj, trim(p_nome), null);
        v_id := null;
        v_cnpj := null;
      else
        -- O EVENTO DE CASAMENTO fica na forma CANÔNICA: ele existe para registrar
        -- que o CNPJ respondeu um nome MATERIALMENTE diferente do gravado, e
        -- diferença só de sufixo/pontuação não é isso.
        if fn_entidade_canonica(v_nome_atual) is distinct from fn_entidade_canonica(trim(p_nome)) then
          insert into evento_auditoria (ator, acao, entidade_ref, depois)
          values ('sistema:entidade', 'entidade_cnpj_casou', 'entidade:' || v_id,
                  jsonb_build_object('caso_id', p_caso_id, 'nome_procurado', trim(p_nome),
                                     'nome_mantido_antes_do_renomeio', v_nome_atual,
                                     'cnpj', v_cnpj,
                                     'pode_renomear', fn_pode_renomear_por_cnpj(v_nome_atual, trim(p_nome)),
                                     'porque', 'o CNPJ é o mesmo — o nome não foi consultado'));
        end if;

        -- 0173: O RENOMEIO VIROU FUNÇÃO PRÓPRIA, e os DOIS caminhos a chamam.
        -- Antes ele morava aqui dentro, e só este caminho (a classificação) o
        -- executava — o diagnóstico, que é o único que roda para TODO documento,
        -- gravava o CNPJ e ia embora sem renomear. Medido: identidade fiscal em
        -- 100% do lote e renomeio em ~50%.
        perform fn_entidade_talvez_renomear(p_caso_id, v_id, trim(p_nome), v_cnpj);

        return v_id;
      end if;
    end if;
  end if;

  -- (1) exato pela forma canônica — não há o que desempatar.
  select c.entidade_id into v_id
  from fn_entidades_candidatas_cnpj(p_caso_id, p_nome, p_cnpj) c
  where c.exata
  order by c.razao_social
  limit 1;
  if v_id is not null then
    -- 0174: usa o RETORNO, não `perform`. Sem isto, quando `fn_entidade_aprender_cnpj`
    -- funde esta entidade numa OUTRA que já tinha o mesmo CNPJ (a corrida entre
    -- o ramo (0) acima e este ramo, ou a mesma situação chegando pela porta do
    -- diagnóstico — ver o cabeçalho da função), `v_id` ficaria apontando para
    -- uma linha DELETADA, e o `insert into documento` em `fn_registrar_documento`
    -- quebraria a FK `documento.entidade_id → entidade.id`.
    v_id := fn_entidade_aprender_cnpj(v_id, v_cnpj);
    return v_id;
  end if;

  -- (2)/(3) quantos APROXIMADOS existem?
  select count(*), string_agg(c.razao_social, ' × ' order by c.razao_social),
         array_agg(c.razao_social)
    into v_n, v_candidatos, v_nomes
  from fn_entidades_candidatas_cnpj(p_caso_id, p_nome, p_cnpj) c;

  -- APRENDER SÓ NO CASAMENTO EXATO, e este `return` SEM `aprender` é a
  -- correção mais importante que a revisão desta fatia trouxe. Este ramo é o
  -- casamento FROUXO (subsequência de prefixos) — é ele que faz "Metalúrgica"
  -- ser absorvido por "VERTENTES METALÚRGICA LTDA.". Deixá-lo GRAVAR o CNPJ
  -- transformaria um palpite de nome em identidade fiscal permanente:
  -- "Canastra" com o CNPJ do GRUPO CANASTRA (a holding, impressa no
  -- consolidado) seria absorvido pela subsidiária e escreveria nela o CNPJ da
  -- holding — e daí em diante TODO documento da holding cairia na subsidiária
  -- pelo ramo (0), sem olhar nome. A própria 0168 já diz que o nome que CHEGA é
  -- o que pode estar contaminado; o CNPJ do mesmo documento não pode ser
  -- promovido a identidade por um casamento que o nome só aproximou.
  if v_n = 1 then
    select c.entidade_id into v_id
    from fn_entidades_candidatas_cnpj(p_caso_id, p_nome, p_cnpj) c limit 1;
    return v_id;
  end if;

  -- (3b) 0168: dois ou mais candidatos que casam ENTRE SI não são ambiguidade.
  if v_n > 1 and fn_entidades_sao_um_grupo(v_nomes || trim(p_nome)) then
    select c.entidade_id into v_id
    from fn_entidades_candidatas_cnpj(p_caso_id, p_nome, p_cnpj) c
    order by length(c.razao_social) desc, c.razao_social
    limit 1;

    insert into evento_auditoria (ator, acao, entidade_ref, depois)
    values ('sistema:entidade', 'entidade_alias_fundido', 'entidade:' || v_id,
            jsonb_build_object('caso_id', p_caso_id, 'nome_procurado', trim(p_nome),
                               'candidatos', v_candidatos, 'quantos', v_n,
                               'porque', 'os candidatos casam todos entre si — é um nome só, '
                                      || 'truncado de jeitos diferentes pela fonte'));
    -- Sem `aprender` pelo mesmo motivo do ramo acima, e aqui é PIOR: o nome que
    -- chega é justamente o truncado, o que pode trazer o endereço colado.
    return v_id;
  end if;

  insert into entidade (caso_id, razao_social, cnpj) values (p_caso_id, trim(p_nome), v_cnpj)
    returning id into v_id;

  -- NASCER COM CNPJ MERECE O MESMO RASTRO QUE APRENDER DEPOIS. É uma afirmação
  -- de identidade tirada de UM documento, que nunca mais é revisitada e que
  -- passa a mandar sobre todo nome — o mínimo honesto é ela aparecer no log.
  if v_cnpj is not null then
    insert into evento_auditoria (ator, acao, entidade_ref, depois)
    values ('sistema:entidade', 'entidade_cnpj_aprendido', 'entidade:' || v_id,
            jsonb_build_object('cnpj', v_cnpj, 'como', 'nasceu com ele'));
  end if;

  if v_n > 1 then
    -- A AMBIGUIDADE É REGISTRADA AQUI e virada em pendência por quem tem o
    -- documento na mão. Esta função não conhece documento.
    insert into evento_auditoria (ator, acao, entidade_ref, depois)
    values ('sistema:entidade', 'entidade_ambigua', 'entidade:' || v_id,
            jsonb_build_object('caso_id', p_caso_id, 'nome_procurado', trim(p_nome),
                               'candidatos', v_candidatos, 'quantos', v_n,
                               -- O CNPJ VAI JUNTO, e a revisão achou ele faltando:
                               -- `fn_pendencia_entidade_ambigua` (0153) monta a descrição
                               -- a partir deste payload, e o analista lia "casa com mais de
                               -- uma empresa: A × B" sem o único número que decide — a
                               -- regra 1 pelo avesso (a nota existe e cala o dado).
                               'cnpj', v_cnpj));
  end if;

  return v_id;
end;
$$;

comment on function fn_upsert_entidade(p_caso_id uuid, p_nome text, p_cnpj text) is
  'Acha ou cria a entidade do caso (0030), sem ESCOLHER no empate (0153), com o nome truncado '
  'fundido no mais completo (0168), com o CNPJ como identidade (0169) e adotando a variante mais '
  'completa ao fundir por CNPJ (0171/0173 — a decisão mora em fn_entidade_talvez_renomear, chamada '
  'dos dois caminhos). 0174: o ramo (1) usa o RETORNO de fn_entidade_aprender_cnpj — ela pode '
  'fundir esta entidade numa outra do mesmo caso que já tinha o CNPJ, e devolver o id de quem sobrou '
  'não é mais opcional. 0176: o ramo (0) NÃO devolve mais um balcão ambíguo (0162/0175) direto — '
  'trata o CNPJ como ausente e registra a colisão (fn_pendencia_cnpj_colide_balcao) em vez de '
  'absorver um documento novo que ainda não é, ele mesmo, um balcão.';

-- -----------------------------------------------------------------------------
-- fn_registrar_diagnostico — reemitida inteira, corpo vigente (0175) + ALTO
-- (reconfere o nome depois do bloco novo) + MÉDIO 1 (só renomeia com o CNPJ
-- que o aprender de fato confirmou nesta entidade).
-- -----------------------------------------------------------------------------
create or replace function fn_registrar_diagnostico(p_documento_id uuid, p_documento_versao_id uuid, p_entidade_nome text, p_tipo_confirma boolean, p_tipo_sugerido text, p_periodo_tipo text, p_periodo_referencia text, p_legibilidade public.legibilidade, p_nota_legibilidade text, p_resumo text, p_justificativa text, p_cnpj text DEFAULT NULL::text) RETURNS jsonb
    LANGUAGE plpgsql
    AS $$
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
  v_pendencia_grupo_id  uuid;
  v_outros_n            int;
  v_outros_nomes        text;
  v_exatas_ambiguidade_n    int;
  v_exata_ambiguidade_nome  text;
  v_pendencia_ambigua_resp_id uuid;
  v_ambigua_resp_desc       text;
  v_entidade_cnpj_pos_aprender text;
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
      v_entidade_id := fn_upsert_entidade(v_caso_id, p_entidade_nome, p_cnpj);
      update documento set entidade_id = v_entidade_id where id = p_documento_id;
      v_entidade_criada := true;
    else
      select razao_social into v_entidade_atual_nome from entidade where id = v_entidade_id;

      select id into v_pendencia_id from pendencia
        where caso_id = v_caso_id and motivo = 'diagnostico:entidade:' || p_documento_id and estado <> 'resolvida'
        limit 1;
      select id into v_pendencia_grupo_id from pendencia
        where caso_id = v_caso_id and motivo = 'diagnostico:entidade_grupo:' || p_documento_id and estado <> 'resolvida'
        limit 1;

      -- 0162: O CASAMENTO CONTRA O BALCÃO AMBÍGUO NÃO CONFIRMA NADA — ele foi
      -- criado (0153) exatamente porque o nome dele já casava com MAIS DE UMA
      -- empresa do caso, então casa por construção com qualquer nome de
      -- conteúdo que aponte para as candidatas que o originaram. Medido no
      -- araucária (lote 7417, 03/09): o documento 009 ficou no balcão
      -- "Araucaria SPE" (pendência entidade_ambigua bloqueante contra
      -- BIOENERGIA × IMOBILIÁRIA), e o diagnóstico de conteúdo, lendo o
      -- PRÓPRIO documento, nomeou "ARAUCÁRIA IMOBILIÁRIA SPE LTDA." por
      -- extenso — que `fn_mesma_entidade` confirma contra o balcão (ele casa
      -- com as DUAS empresas do grupo, por definição), e o ramo abaixo (0121)
      -- tomava isso como CONFIRMAÇÃO, sem a pendência bloqueante da 0153 nunca
      -- ter sido tocada e sem a resposta deixar rastro em lugar nenhum.
      if fn_entidade_e_balcao_ambiguo(v_caso_id, v_entidade_id) then
        -- 0175: dentro do balcão ambíguo, o CNPJ decide ANTES do nome — a
        -- MESMA regra 1 da 0169 ("CNPJ é a identidade que o nome não é"),
        -- chegando pela porta que faltava. MEDIDO em produção (caso
        -- bf0246bb-c93b-4d08-a7df-5d356c9d6275, OMNIBEAUTY, teste 143): sem
        -- esta chamada, dois documentos da MESMA empresa em DOIS balcões
        -- diferentes nunca convergem — cada um só sabe perguntar ao nome, e
        -- o balcão nasce sem CNPJ. Ver o cabeçalho desta migration para os
        -- dois casos que `fn_entidade_aprender_cnpj` já sabe tratar: grava
        -- no próprio balcão quando é o primeiro a aprender este CNPJ no
        -- caso, ou FUNDE nele quando outra entidade (outro balcão, ou uma
        -- entidade de verdade) já tinha o mesmo CNPJ — usando o RETORNO,
        -- nunca `perform` (0174). 0176: `fn_entidade_aprender_cnpj` agora
        -- RECUSA a fusão quando a "outra dona" é um balcão e ESTA entidade
        -- não é (ver o CRÍTICO da 0176) — nesse caso ela devolve o mesmo
        -- `v_entidade_id`, sem CNPJ novo nenhum gravado.
        if p_cnpj is not null then
          v_entidade_id := fn_entidade_aprender_cnpj(v_entidade_id, p_cnpj);

          -- E O RENOMEIO VEM JUNTO, pela MESMA função do ramo `else` (0173) —
          -- não duplica lógica. Se a linha acima FUNDIU, `fn_entidade_aprender_cnpj`
          -- já chamou fn_entidade_talvez_renomear por dentro com o nome do
          -- balcão fundido; esta chamada cobre o caso SEM fusão, em que o
          -- nome lido do CONTEÚDO deste documento pode ser a variante mais
          -- completa para o balcão que acabou de aprender o CNPJ.
          --
          -- 0176 (MÉDIO 1 da revisão da 0175): só chama o renomeio quando o
          -- `aprender` ACIMA realmente confirmou ESTE p_cnpj NESTA entidade —
          -- nunca com o p_cnpj bruto. MEDIDO: uma entidade que já tinha OUTRO
          -- CNPJ gravado (aprender_cnpj devolve sem tocar em nada) ainda era
          -- renomeada com o evento citando um CNPJ ESTRANHO à entidade —
          -- entidade com cnpj real 11222333000181 "renomeada por CNPJ" com o
          -- evento dizendo {"cnpj": "36193378000104", ...}. O mesmo guarda
          -- cobre o refúgio do CRÍTICO desta migration: se
          -- `fn_entidade_aprender_cnpj` recusou fundir (balcão não pode
          -- absorver quem não é balcão), esta entidade não ficou com este
          -- CNPJ, e o `if` abaixo não deixa o renomeio rodar mesmo assim.
          select cnpj into v_entidade_cnpj_pos_aprender from entidade where id = v_entidade_id;
          if v_entidade_cnpj_pos_aprender is not null
             and fn_cnpj_canonico(v_entidade_cnpj_pos_aprender) = fn_cnpj_canonico(p_cnpj) then
            perform fn_entidade_talvez_renomear(v_caso_id, v_entidade_id, p_entidade_nome, v_entidade_cnpj_pos_aprender);
          end if;
        end if;

        -- 0176 (ALTO da revisão da 0175): o NOME pode ter mudado — o bloco
        -- acima pode ter FUNDIDO (`v_entidade_id` agora aponta para OUTRA
        -- linha, a sobrevivente) ou RENOMEADO a própria entidade.
        -- `v_entidade_atual_nome`, lido ANTES deste ramo (no topo da
        -- função), ficaria citando uma razão social que pode não existir
        -- MAIS no banco — a entidade fundida foi DELETADA — e é ela que a
        -- pendência `entidade_ambigua_respondida`, poucas linhas abaixo,
        -- usa para montar a descrição que o analista lê. MEDIDO contra o
        -- cenário de dois balcões convergindo
        -- (Supabase/test/balcao_ambiguo_e_cnpj.test.sql): a pendência do
        -- segundo balcão citava "OMNIBEAUTY DESENVOLVIMENTO E GESTAO" — o
        -- nome do balcão FUNDIDO, já apagado — atribuída ao balcão
        -- sobrevivente, que se chama "...GESTAO DE". Sintaxe `:=` (não
        -- `select into`), de propósito: o marcador de corpo da sonda para
        -- este requisito precisa de um trecho que só exista por causa DESTA
        -- correção.
        v_entidade_atual_nome := (select razao_social from entidade where id = v_entidade_id);

        -- SÓ TENTA RESOLVER PELO NOME SE O CNPJ NÃO RESOLVEU: se a entidade
        -- (que pode ter mudado de id na linha acima) AINDA é um balcão
        -- ambíguo — sem CNPJ para tentar, ou com CNPJ que só gravou no
        -- próprio balcão sem achar outra dona — o nome continua sendo o
        -- único sinal disponível, e a lógica abaixo é EXATAMENTE a de antes
        -- desta migration.
        if fn_entidade_e_balcao_ambiguo(v_caso_id, v_entidade_id) then
        -- O conteúdo pode ter respondido à própria pergunta: se o nome
        -- diagnosticado casa EXATO com exatamente UMA empresa já cadastrada
        -- neste caso (excluído o próprio balcão), é essa a resposta. NÃO
        -- decide sozinho — não move o documento, não funde — só a NOMEIA,
        -- para o humano confirmar em segundos em vez de abrir o PDF.
        select count(*) into v_exatas_ambiguidade_n
        from fn_entidades_candidatas(v_caso_id, p_entidade_nome) c
        where c.exata and c.entidade_id <> v_entidade_id;

        if v_exatas_ambiguidade_n = 1 then
          select c.razao_social into v_exata_ambiguidade_nome
          from fn_entidades_candidatas(v_caso_id, p_entidade_nome) c
          where c.exata and c.entidade_id <> v_entidade_id
          limit 1;

          select id into v_pendencia_ambigua_resp_id from pendencia
            where caso_id = v_caso_id
              and motivo = 'diagnostico:entidade_ambigua_respondida:' || p_documento_id
              and estado <> 'resolvida'
            limit 1;

          v_ambigua_resp_desc := format(
            'O nome do arquivo casou com MAIS DE UMA empresa deste mandato e não identificou '
            || 'nenhuma — por isso o documento foi registrado numa entidade própria ("%s"). O '
            || 'CONTEÚDO deste documento nomeia "%s", que é uma das empresas JÁ CADASTRADAS '
            || 'neste mandato — e nomeia só ela. Confirme pela revisão (fn_revisar_documento) se '
            || 'o documento é mesmo dela; se as duas linhas forem a mesma empresa, funda com '
            || 'fn_fundir_entidade.%s',
            coalesce(v_entidade_atual_nome, '(nenhuma)'), v_exata_ambiguidade_nome,
            case when p_justificativa is not null and length(trim(p_justificativa)) > 0
                 then ' Justificativa do diagnóstico: ' || p_justificativa else '' end);

          if v_pendencia_ambigua_resp_id is null then
            insert into pendencia (caso_id, origem_estagio, tipo, severidade, sobrepujavel, descricao, documento_id, entidade_id, motivo)
              values (v_caso_id, 'diagnostico', 'entidade_incorreta', 'importante', true,
                v_ambigua_resp_desc, p_documento_id, v_entidade_id,
                'diagnostico:entidade_ambigua_respondida:' || p_documento_id);
          else
            update pendencia set descricao = v_ambigua_resp_desc where id = v_pendencia_ambigua_resp_id;
          end if;
        end if;
        -- Zero, duas ou mais exatas: o conteúdo NÃO respondeu — silêncio aqui
        -- é honesto (regra 1 do CLAUDE.md: não fabricar ausência como dado).
        -- E, em QUALQUER dos casos acima, o casamento contra o balcão NUNCA
        -- resolve `diagnostico:entidade`/`diagnostico:entidade_grupo` — não
        -- tocar `v_pendencia_id`/`v_pendencia_grupo_id` aqui é o que deixa
        -- isso explícito: só o ramo `else` abaixo (comparação contra uma
        -- entidade de VERDADE) resolve essas duas pendências.
        end if;
      else
      -- 0121: divergência de ENTIDADE medida pela forma canônica, como o
      -- período já é desde a 0022. "Canastra Industria" e "CANASTRA INDÚSTRIA
      -- DE EMBALAGENS LTDA." são a mesma empresa, e `fn_mesma_entidade` já
      -- sabia disso.
      if fn_mesma_entidade(v_entidade_atual_nome, p_entidade_nome) then
        -- 0172: É AQUI QUE O CNPJ DO CONTEÚDO ENCONTRA A ENTIDADE, e não na
        -- chamada de `fn_upsert_entidade` acima — ela só roda quando o
        -- documento AINDA NÃO TEM entidade, e `fn_registrar_documento` sempre
        -- resolve uma antes. MEDIDO: com o parâmetro só chegando lá, o CNPJ
        -- entrava e morria; a entidade continuava com `cnpj` nulo depois do
        -- diagnóstico. Era conserto de sintoma, não de causa.
        --
        -- E É NESTE RAMO, não no de cima nem no `else`, por uma razão de
        -- segurança: aqui o nome lido do CONTEÚDO **confirma** a entidade em
        -- que o documento está registrado. Nos outros ramos a função está
        -- justamente em dúvida sobre qual é a empresa certa — gravar ali um
        -- CNPJ na entidade ERRADA seria pior que não gravar nenhum, porque
        -- pela regra 1 da 0169 esse CNPJ passaria a ATRAIR todo documento
        -- futuro da empresa de verdade para dentro da entidade errada, sem
        -- olhar nome. Divergência de entidade é pergunta para humano, e as
        -- pendências logo abaixo são a resposta certa para ela. 0176: esta
        -- proteção agora vale também quando a "outra dona" do CNPJ é um
        -- balcão ambíguo — `fn_entidade_aprender_cnpj` recusa fundir esta
        -- entidade (confirmada) NELE (ver o CRÍTICO desta migration).
        --
        -- `fn_entidade_aprender_cnpj` (0169) nunca sobrescreve CNPJ já gravado
        -- e deixa rastro (`entidade_cnpj_aprendido`) — é a mesma função que o
        -- ramo exato de `fn_upsert_entidade` usa, pelo mesmo motivo.
        -- 0174: usa o RETORNO, não `perform`. Quando a outra entidade do
        -- mesmo caso já tinha este CNPJ, a função acima FUNDE esta entidade
        -- nela e devolve o id da SOBREVIVENTE — sem capturá-lo aqui,
        -- `v_entidade_id` ficaria apontando para uma linha deletada, e tanto o
        -- `fn_entidade_talvez_renomear` logo abaixo quanto o `entidade_id` no
        -- jsonb de retorno (fim da função) mentiriam.
        v_entidade_id := fn_entidade_aprender_cnpj(v_entidade_id, p_cnpj);

        -- 0173: E O RENOMEIO VEM JUNTO, pelo mesmo caminho e pela mesma razão.
        -- A 0172 fez o CNPJ chegar aqui, mas só APRENDIDO — quem adota o nome
        -- mais completo era o bloco dentro de `fn_upsert_entidade`, que neste
        -- ramo não roda (o documento já tem entidade). O resultado medido era
        -- desequilibrado: identidade fiscal em 100% do lote e renomeio em ~50%
        -- — só nos documentos que passam pela classificação (19 de 38 no
        -- book-canastra). Para uma empresa cujo ÚNICO documento chega com o
        -- nome contaminado pelo endereço, o nome errado ficava no book até
        -- aparecer um segundo documento pelo outro caminho.
        --
        -- MESMO PADRÃO do MÉDIO 1 desta migration (p_cnpj bruto, não o CNPJ
        -- real da entidade) existe AQUI TAMBÉM, e fica FORA do escopo desta
        -- fatia — ver o cabeçalho da 0176. Registrado para o
        -- MAPA_DE_EXECUCAO.md.
        --
        -- As três guardas da 0171 vão inteiras dentro da função (só entre
        -- truncamentos, nunca cria homônima, recusa com rastro), e sem CNPJ
        -- ela não renomeia — então este fio não toca nenhum documento que
        -- chegue sem identidade fiscal.
        perform fn_entidade_talvez_renomear(v_caso_id, v_entidade_id, p_entidade_nome, p_cnpj);

        if v_pendencia_id is not null then
          update pendencia set estado = 'resolvida', resolvida_em = now(), resolvida_por = 'sistema:diagnostico'
            where id = v_pendencia_id;
        end if;
        if v_pendencia_grupo_id is not null then
          update pendencia set estado = 'resolvida', resolvida_em = now(), resolvida_por = 'sistema:diagnostico'
            where id = v_pendencia_grupo_id;
        end if;
      else
        -- 0160: o nome que não casou com o registrado pode casar com OUTRA(S)
        -- empresa(s) já cadastrada(s) NESTE caso — nesse caso a função não sabe
        -- afirmar que o registro está errado. Excluída a própria entidade do
        -- documento, para não contar "casou consigo mesma" como candidata a
        -- outra empresa. Reaproveita `fn_entidades_candidatas` da 0153 em vez de
        -- duplicar a busca — e, ao contrário da 0153 (que ali resolve escolhendo
        -- SEM decidir, criando entidade nova), aqui `order by ... limit 1`
        -- escolheria no empate quando há mais de um candidato, que é exatamente
        -- o que a 0153 existe para não fazer: conta TODOS os candidatos, para a
        -- mensagem nomear todos, não só o primeiro por ordem alfabética.
        select count(*), string_agg(c.razao_social, ' × ' order by c.razao_social)
          into v_outros_n, v_outros_nomes
        from fn_entidades_candidatas(v_caso_id, p_entidade_nome) c
        where c.entidade_id <> v_entidade_id;

        if v_outros_n >= 1 then
          -- NÃO É AFIRMAÇÃO DE HIERARQUIA: `entidade.papel_no_grupo` é o único
          -- campo que registraria holding × subsidiária, e esta função não o
          -- consulta — não há como saber, só a partir do nome, qual é a relação
          -- entre as duas empresas, ou se há relação alguma. O que dá para
          -- afirmar sem inventar é só isto: as duas (ou mais) já são empresas
          -- cadastradas neste mandato, e o sistema não sabe qual delas é a
          -- certa para este documento — não decide quem está certo, só para de
          -- chamar de "incorreto" um registro que pode estar certo. A pendência
          -- de erro clássica, se estava aberta de uma rodada anterior, fecha —
          -- a resposta mudou de categoria (mas isso só acontece na PRÓXIMA
          -- passada de `fn_registrar_diagnostico` sobre o documento, não ao
          -- aplicar esta migration — ver `Supabase/README.md`).
          if v_pendencia_id is not null then
            update pendencia set estado = 'resolvida', resolvida_em = now(), resolvida_por = 'sistema:diagnostico'
              where id = v_pendencia_id;
          end if;
          if v_pendencia_grupo_id is null then
            insert into pendencia (caso_id, origem_estagio, tipo, severidade, sobrepujavel, descricao, documento_id, entidade_id, motivo)
              values (v_caso_id, 'diagnostico', 'entidade_incorreta', 'importante', true,
                case when v_outros_n = 1 then
                  format('O documento está registrado em "%s", mas o diagnóstico de conteúdo aponta "%s" — nome '
                         || 'que também já é uma empresa CADASTRADA neste mandato ("%s"). As duas são empresas '
                         || 'cadastradas neste caso, e o sistema não sabe qual das duas é a certa para este '
                         || 'documento — não presume nenhuma. Confira pela revisão se ele pertence mesmo a "%s" '
                         || 'ou deveria estar em "%s", sem fundir: as duas continuam sendo empresas diferentes.',
                         coalesce(v_entidade_atual_nome, '(nenhuma)'), p_entidade_nome, v_outros_nomes,
                         coalesce(v_entidade_atual_nome, '(nenhuma)'), v_outros_nomes)
                else
                  format('O documento está registrado em "%s", mas o diagnóstico de conteúdo aponta "%s" — nome '
                         || 'que casa com MAIS DE UMA empresa já cadastrada neste mandato (%s). O sistema não '
                         || 'sabe qual delas é a certa para este documento — não presume nenhuma. Confira pela '
                         || 'revisão qual é a empresa certa, sem fundir: continuam sendo empresas diferentes.',
                         coalesce(v_entidade_atual_nome, '(nenhuma)'), p_entidade_nome, v_outros_nomes)
                end,
                p_documento_id, v_entidade_id, 'diagnostico:entidade_grupo:' || p_documento_id);
          end if;
        else
          -- DIVERGÊNCIA DE VERDADE: o nome diagnosticado não bate com NENHUMA
          -- empresa já cadastrada no caso — não há hierarquia a reconhecer, e a
          -- pendência clássica continua acusando exatamente como na 0121.
          if v_pendencia_grupo_id is not null then
            update pendencia set estado = 'resolvida', resolvida_em = now(), resolvida_por = 'sistema:diagnostico'
              where id = v_pendencia_grupo_id;
          end if;
          if v_pendencia_id is null then
            insert into pendencia (caso_id, origem_estagio, tipo, severidade, sobrepujavel, descricao, documento_id, motivo)
              values (v_caso_id, 'diagnostico', 'entidade_incorreta', 'importante', true,
                format('Diagnóstico de conteúdo sugere entidade "%s", mas o documento está registrado com "%s".',
                       p_entidade_nome, coalesce(v_entidade_atual_nome, '(nenhuma)')),
                p_documento_id, 'diagnostico:entidade:' || p_documento_id);
          end if;
        end if;
      end if;
      end if;
    end if;
  end if;

  -- ----- Tipo: confere contra o que já está registrado -----
  select id into v_pendencia_id from pendencia
    where caso_id = v_caso_id and motivo = 'diagnostico:tipo:' || p_documento_id and estado <> 'resolvida'
    limit 1;
  -- 0142: exige divergência ACIONÁVEL. "Não confirmo" sozinho não basta —
  -- o modelo diz isso também quando reconhece o mesmo tipo com outro nome
  -- (doc 27 da v48: NOTAS_EXPL contra NOTAS_EXPL) ou quando não sabe o que o
  -- documento é ("?" contra "(nenhum)", doc 28). Nos dois casos a pendência
  -- pedia decisão sobre uma diferença que não existe.
  if (p_tipo_sugerido is not null and p_tipo_sugerido is distinct from v_tipo_atual)
     or (coalesce(p_tipo_confirma, true) = false
         and v_tipo_atual is not null
         and coalesce(p_tipo_sugerido, '') <> coalesce(v_tipo_atual, '')) then
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
          format('Diagnóstico de conteúdo sugere período "%s %s" (documento está registrado com "%s %s"). %s',
                 p_periodo_tipo, p_periodo_referencia, coalesce(v_periodo_tipo_atual, '?'), coalesce(v_periodo_ref_atual, '(nenhum)'),
                 coalesce(p_justificativa, '')),
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

comment on function fn_registrar_diagnostico(uuid, uuid, text, boolean, text, text, text, legibilidade, text, text, text, text) is
  'Registra o diagnóstico de conteúdo (E1/E2) e confere contra o que já está no banco — ver o '
  'histórico de 0121/0142/0160/0161/0162/0163 no comentário da 0163. 0172: recebe o CNPJ lido do '
  'CONTEÚDO e o aprende no ramo em que o nome CONFIRMA a entidade. 0173: no mesmo ramo, também '
  'chama fn_entidade_talvez_renomear. 0174: usa o RETORNO de fn_entidade_aprender_cnpj — quando o '
  'CNPJ já pertencia a OUTRA entidade do mesmo caso, ela funde as duas, e a variável local '
  'passava a apontar para uma linha deletada se ninguém capturasse o retorno. 0175: o ramo do '
  'balcão ambíguo (0162) agora tenta o CNPJ ANTES do nome — grava no próprio balcão, ou funde '
  'com quem já tinha o CNPJ (usando o retorno, com o mesmo cuidado da 0174), com o renomeio pela '
  'mesma fn_entidade_talvez_renomear da 0173 — e só cai na lógica de nome (inalterada) se o '
  'balcão ainda for ambíguo depois disso. 0176: o renomeio dentro do ramo do balcão só roda com o '
  'CNPJ que o aprender de fato confirmou NESTA entidade (nunca o p_cnpj bruto — MÉDIO 1 da revisão '
  'da 0175), e o nome usado pela pendência entidade_ambigua_respondida é RECONFERIDO depois do '
  'bloco do balcão, porque ele pode ter fundido ou renomeado a entidade (ALTO da mesma revisão).';

-- -----------------------------------------------------------------------------
-- O CATÁLOGO DA SONDA.
-- -----------------------------------------------------------------------------

-- CRÍTICO, caso B — a guarda nova em fn_entidade_aprender_cnpj.
insert into instalacao_requisito
  (chave, migration, tipo, objeto, marcador, criterio_seed, porque, severidade, ordem) values
  ('aprender_cnpj_balcao_nao_absorve_confirmada', '0176', 'corpo', 'fn_entidade_aprender_cnpj',
   'and not fn_entidade_e_balcao_ambiguo(v_caso_id, p_entidade_id)', null,
   'Sem esta guarda, um balcão ambíguo (0162) que já tinha aprendido um CNPJ (0175) FUNDIA e '
   'DELETAVA qualquer entidade CONFIRMADA que trouxesse o mesmo CNPJ — MEDIDO nesta sessão: uma '
   '"VERTENTES METALURGICA LTDA" com documento e nome próprios desaparecia (fn_fundir_entidade a '
   'deleta), o caso caía de 4 para 3 entidades, e nenhuma pendência acusava. Balcão só pode '
   'absorver quem também é balcão.',
   'bloqueante', 731)
on conflict (chave) do update set
  migration = excluded.migration, tipo = excluded.tipo, objeto = excluded.objeto,
  marcador = excluded.marcador, criterio_seed = excluded.criterio_seed,
  porque = excluded.porque, severidade = excluded.severidade, ordem = excluded.ordem;

-- CRÍTICO, caso A — a guarda nova em fn_upsert_entidade.
insert into instalacao_requisito
  (chave, migration, tipo, objeto, marcador, criterio_seed, porque, severidade, ordem) values
  ('upsert_balcao_nao_absorve_documento_novo', '0176', 'corpo', 'fn_upsert_entidade',
   'fn_entidade_e_balcao_ambiguo(p_caso_id, v_id)', null,
   'Sem esta guarda, o ramo (0) de fn_upsert_entidade (0169) devolvia direto qualquer entidade '
   'que já tivesse o CNPJ do documento novo — inclusive um balcão ambíguo (0162/0175), que nunca '
   'teve o nome confirmado. MEDIDO nesta sessão: um documento novo de "OUTRA METALURGICA NOVA SA" '
   'com o CNPJ (de rodapé) de um balcão já existente foi registrado DENTRO do balcão, sem nunca '
   'ganhar entidade própria — o caso ficou com 3 entidades em vez de 4.',
   'bloqueante', 732)
on conflict (chave) do update set
  migration = excluded.migration, tipo = excluded.tipo, objeto = excluded.objeto,
  marcador = excluded.marcador, criterio_seed = excluded.criterio_seed,
  porque = excluded.porque, severidade = excluded.severidade, ordem = excluded.ordem;

-- A função nova que registra a colisão.
insert into instalacao_requisito
  (chave, migration, tipo, objeto, marcador, criterio_seed, porque, severidade, ordem) values
  ('fn_pendencia_cnpj_colide_balcao_existe', '0176', 'funcao', 'fn_pendencia_cnpj_colide_balcao',
   null, null,
   'É ela que registra, com rastro e sem enxurrada (uma pendência por balcão colidido), a '
   'colisão de CNPJ que as duas guardas do CRÍTICO da 0176 recusam resolver por fusão silenciosa. '
   'Sem esta função, as duas guardas ficariam sem forma de avisar um humano — voltariam ao '
   'defeito 1 do CLAUDE.md (ausência fabricada como dado) por outro caminho.',
   'importante', 733)
on conflict (chave) do update set
  migration = excluded.migration, tipo = excluded.tipo, objeto = excluded.objeto,
  marcador = excluded.marcador, criterio_seed = excluded.criterio_seed,
  porque = excluded.porque, severidade = excluded.severidade, ordem = excluded.ordem;

-- ALTO — reconfere o nome depois do bloco do balcão.
insert into instalacao_requisito
  (chave, migration, tipo, objeto, marcador, criterio_seed, porque, severidade, ordem) values
  ('diagnostico_reconfere_nome_apos_balcao', '0176', 'corpo', 'fn_registrar_diagnostico',
   'v_entidade_atual_nome := (select razao_social from entidade where id = v_entidade_id)', null,
   'Sem esta releitura, a pendência diagnostico:entidade_ambigua_respondida cita a razão social '
   'lida ANTES do bloco do balcão (0175) — que pode ter FUNDIDO a entidade original (linha '
   'deletada) ou RENOMEADO a que sobrou. MEDIDO nesta sessão contra o cenário de dois balcões '
   'convergindo: a pendência citava "OMNIBEAUTY DESENVOLVIMENTO E GESTAO" (o balcão fundido, já '
   'apagado) atribuída ao balcão sobrevivente, que se chama "...GESTAO DE".',
   'importante', 734)
on conflict (chave) do update set
  migration = excluded.migration, tipo = excluded.tipo, objeto = excluded.objeto,
  marcador = excluded.marcador, criterio_seed = excluded.criterio_seed,
  porque = excluded.porque, severidade = excluded.severidade, ordem = excluded.ordem;

-- MÉDIO 3.1 — o marcador de `balcao_ambiguo_aprende_cnpj` (0175) trocado por
-- um amarrado ao código do MÉDIO 1, e o `porque` corrigido (MÉDIO 2): a
-- afirmação "todo balcão ambíguo nasce sem CNPJ" é falsa desde a 0170 — ver
-- o cabeçalho desta migration para a medição completa. Migration do
-- requisito CONTINUA '0175': é a chave que importa, não quem a atualiza.
insert into instalacao_requisito
  (chave, migration, tipo, objeto, marcador, criterio_seed, porque, severidade, ordem) values
  ('balcao_ambiguo_aprende_cnpj', '0175', 'corpo', 'fn_registrar_diagnostico',
   'fn_cnpj_canonico(v_entidade_cnpj_pos_aprender) = fn_cnpj_canonico(p_cnpj)', null,
   'Sem a tentativa de CNPJ dentro do ramo do balcão ambíguo (0162/0175), dois documentos da '
   'MESMA empresa em DOIS balcões diferentes nunca convergem, mesmo trazendo o MESMO CNPJ — '
   'MEDIDO em produção (caso bf0246bb-c93b-4d08-a7df-5d356c9d6275, OMNIBEAUTY, teste 143). '
   'MARCADOR TROCADO NA 0176: o da 0175 (''if p_cnpj is not null then'') era código de fato, mas '
   'FRÁGIL — qualquer bloco futuro que comece por essa condição em QUALQUER lugar da função '
   'satisfaria o requisito sem a lógica precisar estar presente. O novo marcador só existe por '
   'causa do MÉDIO 1 da revisão da 0175 (só renomeia com o CNPJ que o aprender de fato confirmou '
   'nesta entidade), e desaparece se o bloco do balcão for removido. TEXTO CORRIGIDO NA 0176 '
   '(MÉDIO 2 da mesma revisão): a afirmação "todo balcão ambíguo nasce sem CNPJ" é FALSA desde a '
   '0170 — fn_upsert_entidade grava o CNPJ na entidade nova quando a ambiguidade nasce pela '
   'CLASSIFICAÇÃO (fn_registrar_documento chega com p_cnpj) — MEDIDO nesta sessão. Isso NÃO '
   'quebra a convergência: a guarda do CRÍTICO da 0176 em fn_upsert_entidade nunca deixa uma '
   'SEGUNDA entidade nascer com um CNPJ que um balcão já detém (o índice entidade_caso_cnpj_unico '
   'já impede duas linhas simultâneas), então "dois balcões nascem AMBOS já com o CNPJ certo" não '
   'ocorre em nenhuma sequência alcançável fora de concorrência real, fora do escopo desta fatia.',
   'bloqueante', 730)
on conflict (chave) do update set
  migration = excluded.migration, tipo = excluded.tipo, objeto = excluded.objeto,
  marcador = excluded.marcador, criterio_seed = excluded.criterio_seed,
  porque = excluded.porque, severidade = excluded.severidade, ordem = excluded.ordem;

-- MÉDIO 3.2 — o marcador de `renomeio_no_diagnostico` (0173) trocado pelo
-- texto COMPLETO da chamada do ramo `else`, que só existe UMA vez desde que
-- o MÉDIO 1 desta migration mudou o quarto argumento da chamada do ramo do
-- balcão. Migration do requisito CONTINUA '0173' — mesmo precedente da
-- 0173 reapontando `cnpj_renomeia`.
insert into instalacao_requisito
  (chave, migration, tipo, objeto, marcador, criterio_seed, porque, severidade, ordem) values
  ('renomeio_no_diagnostico', '0173', 'corpo', 'fn_registrar_diagnostico',
   'fn_entidade_talvez_renomear(v_caso_id, v_entidade_id, p_entidade_nome, p_cnpj)', null,
   'Sem esta chamada o renomeio por CNPJ só alcança os documentos que passam pela CLASSIFICAÇÃO '
   'por conteúdo — o ramo de fallback. Medido no book-canastra versionado: 19 de 38 documentos. '
   'MARCADOR TROCADO NA 0176: o da 0173 (''fn_entidade_talvez_renomear(v_caso_id, v_entidade_id'') '
   'passou a casar com DUAS chamadas depois da 0175 (a original do ramo `else`, e a nova do ramo '
   'do balcão) — texto IDÊNTICO nas duas até o MÉDIO 1 desta migration, MEDIDO por grep (`2` '
   'ocorrências) contra o schema do estado da 0175. Se uma reemissão futura removesse a chamada '
   'original (0173) mas deixasse a do balcão, o requisito continuaria "presente" com o '
   'comportamento que ele deveria proteger quebrado. O novo marcador usa o texto COMPLETO da '
   'chamada do ramo `else`, que o MÉDIO 1 tornou única (a do balcão agora passa '
   'v_entidade_cnpj_pos_aprender, não p_cnpj bruto) — MEDIDO por grep depois desta migration: `1` '
   'ocorrência.',
   'bloqueante', 710)
on conflict (chave) do update set
  migration = excluded.migration, tipo = excluded.tipo, objeto = excluded.objeto,
  marcador = excluded.marcador, criterio_seed = excluded.criterio_seed,
  porque = excluded.porque, severidade = excluded.severidade, ordem = excluded.ordem;

update instalacao_cobertura
   set ate_migration = '0176', revisado_em = current_date,
       observacao = 'A 0176 corrige cinco defeitos que a revisão da 0175 mediu: (CRÍTICO) o '
                    'balcão ambíguo, que desde a 0175 pode ter CNPJ, absorvia entidades '
                    'CONFIRMADAS via CNPJ pelos dois caminhos que gravam entidade.cnpj '
                    '(fn_upsert_entidade ramo 0, fn_entidade_aprender_cnpj) — agora só absorve '
                    'quem também é balcão, com a colisão registrada por '
                    'fn_pendencia_cnpj_colide_balcao (função nova); (ALTO) o nome usado na '
                    'pendência entidade_ambigua_respondida é reconferido depois do bloco do '
                    'balcão; (MÉDIO 1) o renomeio dentro do balcão usa o CNPJ que o aprender de '
                    'fato confirmou, não o bruto; (MÉDIO 2) o porque de '
                    'balcao_ambiguo_aprende_cnpj corrigido (balcão PODE nascer com CNPJ desde a '
                    '0170); (MÉDIO 3) os marcadores de balcao_ambiguo_aprende_cnpj e '
                    'renomeio_no_diagnostico trocados por texto amarrado ao código, não mais '
                    'sujeito a colisão ou a fragilidade de condição genérica.';
