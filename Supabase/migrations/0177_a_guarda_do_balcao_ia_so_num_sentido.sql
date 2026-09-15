-- =============================================================================
-- 0177 — A GUARDA DA 0176 SÓ OLHAVA NUM SENTIDO, E É O SENTIDO PRINCIPAL DESDE
--        A 0175 QUE FICAVA DESPROTEGIDO — MAIS TRÊS DEFEITOS DA MESMA REVISÃO
--
-- A 0176 (já commitada, `b8fc826`, PR #226) corrigiu o balcão ambíguo (0162,
-- com CNPJ desde a 0175) absorvendo entidade CONFIRMADA via CNPJ — mas só
-- quando `v_outra_id` (quem já tinha o CNPJ) era o balcão. Uma SEGUNDA
-- revisão independente (`revisor-defeito-silencioso`) mediu que a condição é
-- UNIDIRECIONAL, e a direção que falta é a PRINCIPAL: desde a 0175,
-- `fn_registrar_diagnostico`, no ramo do balcão ambíguo, chama
-- `fn_entidade_aprender_cnpj(v_entidade_id, p_cnpj)` com `v_entidade_id` = o
-- PRÓPRIO BALCÃO — ou seja, na chamada mais comum do sistema, o balcão é
-- `p_entidade_id` (quem está "aprendendo"), exatamente o lado que a guarda da
-- 0176 não olhava.
--
-- =============================================================================
-- CRÍTICO — a guarda unidirecional. Dentro de `fn_entidade_aprender_cnpj`, a
-- condição da 0176 era:
--
--   if fn_entidade_e_balcao_ambiguo(v_caso_id, v_outra_id)
--      and not fn_entidade_e_balcao_ambiguo(v_caso_id, p_entidade_id) then
--     -- bloqueia, abre pendência
--
-- Quando é o INVERSO — `p_entidade_id` é o balcão (chegando para aprender) e
-- `v_outra_id` é uma entidade CONFIRMADA que já tinha o CNPJ — a condição é
-- FALSA (`v_outra_id` não é balcão) e a fusão passa:
-- `fn_fundir_entidade(v_caso_id, p_entidade_id, v_outra_id, ...)` deleta o
-- BALCÃO (`p_de_id = p_entidade_id`) dentro da confirmada, e
-- `fn_fundir_entidade` resolve a pendência `entidade_ambigua:<balcão>` —
-- BLOQUEANTE — junto, sem pendência de colisão nenhuma no lugar.
--
-- MEDIDO nesta sessão (mesmos nomes/CNPJ do teste da 0176 —
-- `Supabase/test/balcao_nao_absorve_confirmada.test.sql` — com a entidade
-- CONFIRMADA aprendendo o CNPJ de rodapé PRIMEIRO, e o balcão chegando
-- DEPOIS, contra o estado da 0176 sem esta correção):
--
--   ANTES:  4 entidades, 1 pendência BLOQUEANTE (entidade_ambigua do balcão)
--   DEPOIS: 3 entidades, 0 pendências bloqueantes, 0 pendências de colisão
--   o balcão ainda existe? f  -- foi DELETADO
--   documentos dentro da confirmada: 2 (era 1)
--
-- A CORREÇÃO: o invariante não é "quem RECEBE não pode ser confirmada quando
-- o outro é balcão" — é "um balcão ambíguo não funde por CNPJ com quem NÃO é
-- balcão, EM NENHUMA DIREÇÃO". A condição vira XOR: exatamente um dos dois
-- lados é balcão bloqueia a fusão e abre pendência (nomeando corretamente
-- QUAL dos dois é o balcão, para a pendência ficar pendurada nele — não na
-- confirmada); quando os DOIS são balcão (convergência balcão↔balcão, o
-- PONTO da 0175) ou os DOIS são confirmados (o caso normal desde a 0169),
-- funde normalmente como sempre fundiu. Em qualquer recusa, devolve
-- `p_entidade_id` inalterado — o mesmo contrato que a 0176 já tinha.
--
-- Reemite `fn_entidade_aprender_cnpj` INTEIRA, verbatim do corpo vigente
-- (0176) com só esta mudança — nunca por âncora de texto em corpo de função
-- (.claude/memory/nunca-corrigir-funcao-por-replace.md).
--
-- =============================================================================
-- ALTO — o balcão colidindo "consigo mesmo". No ramo (0) de
-- `fn_upsert_entidade` (caso A da 0176: documento NOVO por registrar), a
-- guarda disparava só por `fn_entidade_e_balcao_ambiguo(p_caso_id, v_id)`,
-- sem checar se o NOME que está chegando é o nome do PRÓPRIO balcão que já
-- tem esse CNPJ — um SEGUNDO documento do MESMO balcão, chegando pela
-- classificação, com o CNPJ que ele já aprendeu.
--
-- MEDIDO nesta sessão: um balcão ambíguo aprende o CNPJ pelo diagnóstico; um
-- SEGUNDO documento chega pela classificação com o MESMO nome do balcão e o
-- MESMO CNPJ (`p_cnpj` direto em `fn_registrar_documento`). Contra o estado
-- da 0176 sem esta correção: uma pendência de colisão nascia (0→1) mesmo
-- sendo o PRÓPRIO balcão recebendo mais um documento seu — e o documento
-- terminava, de qualquer forma, atribuído a ele pelo ramo (1) de casamento
-- exato por nome, alguns passos abaixo (a mesma pendência dizia "o sistema
-- NÃO... atribuiu este documento/entidade a ele", o que é FALSO). A
-- orientação da pendência ("funda manualmente com fn_fundir_entidade") levaria
-- um analista a tentar fundir o balcão consigo mesmo, que `fn_fundir_entidade`
-- recusa com exceção (`p_de_id = p_para_id`).
--
-- A CORREÇÃO: antes de tratar como colisão, confere se o nome que chegou
-- (forma canônica, `fn_entidade_canonica`) é o mesmo do balcão que já detém
-- este CNPJ — se for, não é colisão nenhuma, é o próprio balcão recebendo
-- mais um documento pelo caminho normal (sem evento de "casamento", que
-- exige nome MATERIALMENTE diferente; com o renomeio de sempre, que aqui é
-- no-op porque o nome já é o mesmo).
--
-- Reemite `fn_upsert_entidade` INTEIRA, mesma regra de nunca corrigir por
-- âncora.
--
-- =============================================================================
-- MÉDIO 1 — a pendência de colisão perdia a colisão anterior.
-- `fn_pendencia_cnpj_colide_balcao` é idempotente POR BALCÃO (uma linha,
-- `update descricao` a cada nova colisão): se o MESMO balcão colide com
-- entidades DIFERENTES em momentos diferentes, a SEGUNDA colisão sobrescrevia
-- a descrição inteira e o nome da PRIMEIRA colidente desaparecia da pendência
-- (só ficava em `evento_auditoria`, que o analista não lê ao abrir a fila).
--
-- MEDIDO nesta sessão: um balcão colide primeiro com "VERTENTES METALURGICA
-- LTDA" e depois com "OUTRA METALURGICA NOVA SA" — sem esta correção, a
-- descrição da pendência, depois da segunda colisão, não citava mais a
-- primeira colidente em lugar nenhum.
--
-- A CORREÇÃO: a descrição passa a listar TODAS as colisões já registradas
-- contra este balcão (lidas de `evento_auditoria`, que já é gravado a cada
-- chamada e nunca se perde), mantendo UMA pendência por balcão — não uma
-- enxurrada.
--
-- =============================================================================
-- MÉDIO 2 — o marcador da sonda `balcao_ambiguo_aprende_cnpj` atestava a
-- coisa errada. O marcador da 0176
-- (`fn_cnpj_canonico(v_entidade_cnpj_pos_aprender) = fn_cnpj_canonico(p_cnpj)`)
-- prova a guarda do RENOMEIO (MÉDIO 1 da 0176), não a chamada real a
-- `fn_entidade_aprender_cnpj` dentro do ramo do balcão — essa chamada
-- (`v_entidade_id := fn_entidade_aprender_cnpj(v_entidade_id, p_cnpj);`) tinha
-- texto IDÊNTICO à do ramo `else` (0172): MEDIDO por contagem via
-- `pg_get_functiondef` contra o corpo de `fn_registrar_diagnostico` do
-- estado da 0176 — `2` ocorrências do texto genérico
-- `v_entidade_id := fn_entidade_aprender_cnpj(v_entidade_id, p_cnpj)`. Se uma
-- reemissão futura removesse SÓ a chamada do ramo do balcão mas deixasse o
-- `if` do marcador, a sonda continuaria dizendo "presente" com a
-- convergência morta.
--
-- A CORREÇÃO: a variável de atribuição, SÓ dentro do ramo do balcão, passa a
-- ser `v_entidade_id_balcao` (nova, não existe no ramo `else`) — o texto da
-- chamada fica ÚNICO no corpo, e o marcador aponta para ELE. MEDIDO depois
-- desta migration: `1` ocorrência do texto novo
-- (`v_entidade_id_balcao := fn_entidade_aprender_cnpj(v_entidade_id, p_cnpj)`)
-- e `1` ocorrência do texto genérico (só o ramo `else`, que nunca mudou).
--
-- Reemite `fn_registrar_diagnostico` INTEIRA, mesma regra — a única mudança
-- de comportamento é nenhuma: é troca de nome de variável local, puramente
-- para amarrar o marcador ao código certo.
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
  v_colisoes_acumuladas text[];
begin
  select razao_social into v_balcao_nome from entidade where id = p_balcao_id;
  if v_balcao_nome is null then return null; end if;

  -- Uma pendência por BALCÃO colidido, não por documento — o mesmo desenho
  -- de `fn_pendencia_entidade_ambigua` (0153): vários documentos batendo na
  -- mesma colisão fazem UMA pergunta, não uma enxurrada.
  v_motivo := 'entidade_cnpj_colide_balcao:' || p_balcao_id;

  -- 0177 (MÉDIO 1): grava o evento de auditoria ANTES de montar a descrição
  -- — ele é a fonte de verdade que a lista abaixo acumula, e nunca some
  -- (ao contrário da pendência, que a UPDATE sobrescrevia por inteiro).
  insert into evento_auditoria (ator, acao, entidade_ref, depois)
    values ('sistema:entidade', 'entidade_cnpj_colisao_recusada', 'entidade:' || p_balcao_id,
      jsonb_build_object('caso_id', p_caso_id, 'balcao_id', p_balcao_id, 'cnpj', v_cnpj,
                         'nome_outro', p_nome_outro, 'entidade_outro_id', p_entidade_outro_id,
                         'porque', 'balcão ambíguo só absorve via CNPJ quando o outro lado também é balcão'));

  -- 0177 (MÉDIO 1): lista TODAS as colisões já registradas contra ESTE
  -- balcão — sem isto, a segunda colisão contra um balcão diferente do
  -- primeiro apagava o nome do primeiro colidente da descrição (só ficava
  -- em evento_auditoria, que o analista não lê ao abrir a fila de
  -- pendências). `distinct` evita repetir o mesmo nome se o mesmo documento
  -- reemitir o diagnóstico mais de uma vez.
  select array_agg(distinct (depois->>'nome_outro') order by (depois->>'nome_outro'))
    into v_colisoes_acumuladas
    from evento_auditoria
   where acao = 'entidade_cnpj_colisao_recusada' and entidade_ref = 'entidade:' || p_balcao_id;

  v_desc := format(
    'O balcão ambíguo "%s" (nome ainda NÃO confirmado — foi criado porque casa com MAIS DE UMA '
    || 'empresa deste mandato) já tinha aprendido o CNPJ %s. Colidiu com o MESMO CNPJ sem ser, '
    || 'ela própria, um balcão ambíguo: %s — pela regra "balcão só absorve balcão", o sistema NÃO '
    || 'fundiu nem atribuiu nenhum destes documentos/entidades a ele; o caminho normal (nome, '
    || 'entidade própria) decidiu como decidiria se o balcão nunca tivesse este CNPJ. Confira de '
    || 'quem é o CNPJ: se for mesmo de alguma das colidentes, funda manualmente com '
    || 'fn_fundir_entidade; se for coincidência (ex.: CNPJ do escritório de contabilidade no '
    || 'rodapé do relatório), o CNPJ pode estar gravado na entidade ERRADA (o balcão) e vale '
    || 'reavaliar quem deveria tê-lo.',
    v_balcao_nome, coalesce(v_cnpj, p_cnpj), array_to_string(v_colisoes_acumuladas, ' × '));

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

  return v_pend;
end;
$$;

comment on function fn_pendencia_cnpj_colide_balcao(uuid, uuid, text, text, uuid) is
  '0176: registra (idempotente por balcão) a colisão de CNPJ entre um balcão ambíguo e uma '
  'entidade CONFIRMADA (documento novo por registrar, ou entidade já existente) que trouxe o '
  'MESMO CNPJ — o caso em que o balcão NÃO PODE absorver (ver o CRÍTICO da 0176/0177). Não decide '
  'de quem é o CNPJ: só nomeia a colisão para revisão humana, com rastro em evento_auditoria '
  '(entidade_cnpj_colisao_recusada). 0177 (MÉDIO 1): a descrição ACUMULA todas as colisões já '
  'registradas contra este balcão (lidas de evento_auditoria, que nunca se perde) — uma segunda '
  'colisão, contra outra entidade, não apaga mais o nome da primeira colidente.';

-- -----------------------------------------------------------------------------
-- fn_entidade_aprender_cnpj — reemitida inteira, corpo vigente (0176) + a
-- guarda BIDIRECIONAL do CRÍTICO desta migration.
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
  v_outra_nome text;
  v_outra_e_balcao boolean;
  v_esta_e_balcao  boolean;
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
  select id, razao_social into v_outra_id, v_outra_nome
    from entidade
   where caso_id = v_caso_id and id <> p_entidade_id
     and fn_cnpj_canonico(cnpj) = v_cnpj
   limit 1;

  if v_outra_id is not null then
    v_outra_e_balcao := fn_entidade_e_balcao_ambiguo(v_caso_id, v_outra_id);
    v_esta_e_balcao  := fn_entidade_e_balcao_ambiguo(v_caso_id, p_entidade_id);

    -- 0177 (CRÍTICO): a guarda da 0176 só olhava a direção
    -- "`v_outra_id` é balcão e `p_entidade_id` não é". Mas desde a 0175, o
    -- caminho PRINCIPAL de `fn_registrar_diagnostico` chama esta função com
    -- `p_entidade_id` = o PRÓPRIO BALCÃO (é ele quem está "aprendendo") — e
    -- nessa direção a condição da 0176 era FALSA (a confirmada não é
    -- balcão) e a fusão passava: `fn_fundir_entidade` deletava o BALCÃO
    -- (`p_de_id = p_entidade_id`) dentro da confirmada, e resolvia a
    -- pendência `entidade_ambigua:<balcão>` — BLOQUEANTE — junto, sem
    -- pendência de colisão nenhuma no lugar. MEDIDO nesta sessão (mesmos
    -- dados do teste da 0176, ordem de chegada invertida): 4 entidades/1
    -- pendência bloqueante → 3 entidades/0 bloqueantes/0 colisões, balcão
    -- deletado, 2 documentos dentro da confirmada (era 1). O invariante
    -- correto é XOR: EXATAMENTE um dos dois lados é balcão bloqueia a
    -- fusão, nas DUAS direções — quando os DOIS são balcão (convergência
    -- 0175) ou os DOIS são confirmados (0169/0174), funde normalmente como
    -- sempre fundiu.
    if v_outra_e_balcao <> v_esta_e_balcao then
      if v_outra_e_balcao then
        perform fn_pendencia_cnpj_colide_balcao(v_caso_id, v_outra_id, v_cnpj, v_nome_atual, p_entidade_id);
      else
        perform fn_pendencia_cnpj_colide_balcao(v_caso_id, p_entidade_id, v_cnpj, v_outra_nome, v_outra_id);
      end if;
      -- Em QUALQUER direção, devolve p_entidade_id inalterado — se ele é o
      -- balcão recusado, continua existindo e continua ambíguo (o mesmo
      -- contrato que a 0176 já tinha para o caso em que a recusa protegia a
      -- entidade que chegou).
      return p_entidade_id;
    end if;

    -- FUNDE sem perguntar ao nome — é a MESMA regra 1 da 0169 ("CNPJ é a
    -- identidade que o nome não é"), chegando pela porta do diagnóstico em
    -- vez da porta de registro. Chega aqui porque os DOIS lados são balcão
    -- (convergência balcão↔balcão, o PONTO da 0175) ou os DOIS são
    -- confirmados (o caso normal desde a 0169/0174). `fn_fundir_entidade`
    -- já move documentos, checklist, pendências e reconciliações, resolve a
    -- pendência de ambiguidade da entidade fundida, e grava
    -- `entidade_fundida` com os dois nomes e quantos documentos mudaram de
    -- dono.
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
  'inteira. 0177: a fusão é recusada quando EXATAMENTE um dos dois lados é um balcão ambíguo '
  '(0162/0175) — em QUALQUER direção (a guarda da 0176 só olhava uma) — porque fundir apagaria uma '
  'entidade CONFIRMADA dentro de um balcão sem nome validado, ou apagaria o BALCÃO (com sua '
  'pendência de ambiguidade bloqueante) dentro de uma confirmada; a colisão vira pendência '
  '(fn_pendencia_cnpj_colide_balcao) e nada funde. Quando os DOIS são balcão (convergência 0175) ou '
  'os DOIS são confirmados, funde normalmente. Devolve o id da entidade que sobrou: SEMPRE use o '
  'retorno, nunca o id que foi passado — depois de uma fusão ele pode apontar para uma linha '
  'deletada.';

-- -----------------------------------------------------------------------------
-- fn_upsert_entidade — reemitida inteira, corpo vigente (0176) + a guarda do
-- ALTO desta migration (não colide "consigo mesmo").
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
  v_e_balcao   boolean;
  v_mesmo_nome_do_balcao boolean;
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
      v_e_balcao := fn_entidade_e_balcao_ambiguo(p_caso_id, v_id);

      -- 0177 (ALTO): o nome que chega pode ser o PRÓPRIO nome do balcão —
      -- um SEGUNDO documento do MESMO balcão, chegando pela classificação,
      -- com o CNPJ que ele já aprendeu. A 0176 tratava QUALQUER chegada
      -- contra um balcão como colisão externa, mesmo quando é o balcão
      -- recebendo mais um documento seu: a pendência abria dizendo que o
      -- nome "chegou... sem ser, ela própria, um balcão ambíguo" e que "o
      -- sistema NÃO... atribuiu este documento/entidade a ele" — as DUAS
      -- afirmações falsas, porque o nome que chegou É o do balcão e o
      -- documento SIM termina atribuído a ele pelo ramo (1) de casamento
      -- exato por nome, alguns passos abaixo. MEDIDO nesta sessão: uma
      -- pendência de colisão nascia (0→1) mesmo quando o documento novo era
      -- só mais um do MESMO balcão.
      v_mesmo_nome_do_balcao := v_e_balcao
        and fn_entidade_canonica(v_nome_atual) is not distinct from fn_entidade_canonica(trim(p_nome));

      -- MEDIDO (0176): um documento novo de OUTRA empresa (mesmo CNPJ de
      -- rodapé de contador) virava absorvido pelo balcão sem nunca ganhar
      -- linha própria — entidades no caso ficavam em 3 em vez de virarem 4.
      -- Trata o CNPJ como se nunca tivesse chegado (`v_cnpj := null`) para o
      -- resto desta chamada: sem isso, o `insert` do fim desta função
      -- tentaria gravar este MESMO CNPJ numa entidade nova e violaria
      -- `entidade_caso_cnpj_unico` — e, pior, atribuiria à empresa nova um
      -- CNPJ que pode não ser dela.
      if v_e_balcao and not v_mesmo_nome_do_balcao then
        perform fn_pendencia_cnpj_colide_balcao(p_caso_id, v_id, v_cnpj, trim(p_nome), null);
        v_id := null;
        v_cnpj := null;
      else
        -- O EVENTO DE CASAMENTO fica na forma CANÔNICA: ele existe para registrar
        -- que o CNPJ respondeu um nome MATERIALMENTE diferente do gravado, e
        -- diferença só de sufixo/pontuação não é isso. Quando é o PRÓPRIO
        -- balcão (v_mesmo_nome_do_balcao), esta condição já é falsa por
        -- construção — nenhum evento de "casamento" nasce, porque não houve
        -- casamento: é o mesmo nome de sempre.
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
  'dos dois caminhos). 0174: o ramo (1) usa o RETORNO de fn_entidade_aprender_cnpj. 0176: o ramo (0) '
  'não devolve mais um balcão ambíguo (0162/0175) direto para OUTRA empresa — trata o CNPJ como '
  'ausente e registra a colisão (fn_pendencia_cnpj_colide_balcao). 0177: essa colisão só é '
  'registrada quando quem chegou NÃO é, ela própria, o mesmo balcão — um segundo documento do '
  'PRÓPRIO balcão (mesmo nome, mesmo CNPJ) não abre pendência falsa; segue pelo caminho normal.';

-- -----------------------------------------------------------------------------
-- fn_registrar_diagnostico — reemitida inteira, corpo vigente (0176) + o
-- MÉDIO 2 desta migration (variável local renomeada no ramo do balcão, para
-- o marcador da sonda amarrar na chamada certa). Nenhuma mudança de
-- comportamento.
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
  v_entidade_id_balcao         uuid;
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
        -- nunca `perform` (0174). 0176/0177: `fn_entidade_aprender_cnpj`
        -- agora RECUSA a fusão quando EXATAMENTE um dos dois lados é um
        -- balcão e o outro não — em QUALQUER direção (ver o CRÍTICO da
        -- 0177) — nesse caso ela devolve o mesmo `v_entidade_id`, sem CNPJ
        -- novo nenhum gravado.
        if p_cnpj is not null then
          -- 0177 (MÉDIO 2): a variável de atribuição é só desta chamada,
          -- para que o texto da chamada dentro do ramo do balcão fique
          -- ÚNICO no corpo — até aqui, a atribuição de v_entidade_id a
          -- partir do resultado do aprender era IDÊNTICA, char por char, à
          -- do ramo `else` (0172): MEDIDO por contagem (2 ocorrências)
          -- contra o corpo do estado da 0176. O marcador da sonda para
          -- `balcao_ambiguo_aprende_cnpj` provava a guarda do renomeio
          -- (MÉDIO 1 da 0176), não esta chamada — se uma reemissão futura
          -- removesse SÓ esta chamada, o requisito continuaria "presente"
          -- via o texto genérico do ramo `else`. Nenhuma mudança de
          -- COMPORTAMENTO: é troca de nome de variável. (Este comentário
          -- evita, de propósito, escrever a chamada antiga por extenso —
          -- fazer isso aqui inflaria a própria contagem que a correção
          -- existe para corrigir.)
          v_entidade_id_balcao := fn_entidade_aprender_cnpj(v_entidade_id, p_cnpj);
          v_entidade_id := v_entidade_id_balcao;

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
          -- cobre o refúgio do CRÍTICO da 0176/0177: se
          -- `fn_entidade_aprender_cnpj` recusou fundir (balcão não pode
          -- absorver quem não é balcão, em nenhuma direção), esta entidade
          -- não ficou com este CNPJ, e o `if` abaixo não deixa o renomeio
          -- rodar mesmo assim.
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
        -- pendências logo abaixo são a resposta certa para ela. 0176/0177:
        -- esta proteção agora vale também quando a "outra dona" do CNPJ é um
        -- balcão ambíguo — `fn_entidade_aprender_cnpj` recusa fundir esta
        -- entidade (confirmada) NELE, em qualquer direção (ver o CRÍTICO da
        -- 0177).
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
        -- MESMO PADRÃO do MÉDIO 1 da 0176 (p_cnpj bruto, não o CNPJ real da
        -- entidade) existe AQUI TAMBÉM, e fica FORA do escopo desta fatia —
        -- ver o cabeçalho da 0176. Registrado para o
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
  'chama fn_entidade_talvez_renomear. 0174: usa o RETORNO de fn_entidade_aprender_cnpj. 0175: o '
  'ramo do balcão ambíguo (0162) agora tenta o CNPJ ANTES do nome. 0176: o renomeio dentro do ramo '
  'do balcão só roda com o CNPJ que o aprender de fato confirmou NESTA entidade, e o nome usado '
  'pela pendência entidade_ambigua_respondida é RECONFERIDO depois do bloco do balcão. 0177: a '
  'chamada a fn_entidade_aprender_cnpj dentro do ramo do balcão usa uma variável local própria '
  '(v_entidade_id_balcao) — texto único, para o marcador da sonda de balcao_ambiguo_aprende_cnpj '
  'parar de casar também com a chamada IDÊNTICA do ramo `else`. Nenhuma mudança de comportamento.';

-- -----------------------------------------------------------------------------
-- O CATÁLOGO DA SONDA.
-- -----------------------------------------------------------------------------

-- CRÍTICO — a guarda de fn_entidade_aprender_cnpj vira XOR bidirecional.
-- Substitui o marcador da 0176 (que só provava metade da condição).
insert into instalacao_requisito
  (chave, migration, tipo, objeto, marcador, criterio_seed, porque, severidade, ordem) values
  ('aprender_cnpj_balcao_nao_absorve_confirmada', '0176', 'corpo', 'fn_entidade_aprender_cnpj',
   'if v_outra_e_balcao <> v_esta_e_balcao then', null,
   'A guarda da 0176 só olhava a direção "v_outra_id é balcão e p_entidade_id não é" — mas desde a '
   '0175, o caminho PRINCIPAL de fn_registrar_diagnostico chama esta função com p_entidade_id = o '
   'PRÓPRIO BALCÃO, exatamente o lado que essa guarda não protegia. MEDIDO nesta sessão (0177, '
   'ordem de chegada invertida do teste da 0176): 4 entidades/1 pendência bloqueante → 3 '
   'entidades/0 bloqueantes/0 colisões, o BALCÃO deletado (e sua pendência entidade_ambigua '
   'bloqueante resolvida junto, sem colisão nenhuma no lugar), 2 documentos dentro da confirmada '
   '(era 1). O invariante correto é XOR: EXATAMENTE um dos dois lados é balcão bloqueia a fusão, '
   'nas DUAS direções.',
   'bloqueante', 731)
on conflict (chave) do update set
  migration = excluded.migration, tipo = excluded.tipo, objeto = excluded.objeto,
  marcador = excluded.marcador, criterio_seed = excluded.criterio_seed,
  porque = excluded.porque, severidade = excluded.severidade, ordem = excluded.ordem;

-- ALTO — o balcão não colide "consigo mesmo" em fn_upsert_entidade.
insert into instalacao_requisito
  (chave, migration, tipo, objeto, marcador, criterio_seed, porque, severidade, ordem) values
  ('upsert_balcao_nao_colide_consigo_mesmo', '0177', 'corpo', 'fn_upsert_entidade',
   'v_mesmo_nome_do_balcao', null,
   'Sem esta guarda, um SEGUNDO documento do MESMO balcão (mesmo nome, mesmo CNPJ que ele já '
   'aprendeu), chegando pela classificação, abria uma pendência de colisão FALSA — a descrição '
   'afirmava que o nome chegou "sem ser, ela própria, um balcão ambíguo" e que o sistema "NÃO '
   'atribuiu este documento/entidade a ele", as duas coisas falsas, e orientava fundir o balcão '
   'consigo mesmo (fn_fundir_entidade recusa com exceção). MEDIDO nesta sessão: uma pendência de '
   'colisão nascia (0→1) mesmo sendo só mais um documento do próprio balcão.',
   'importante', 735)
on conflict (chave) do update set
  migration = excluded.migration, tipo = excluded.tipo, objeto = excluded.objeto,
  marcador = excluded.marcador, criterio_seed = excluded.criterio_seed,
  porque = excluded.porque, severidade = excluded.severidade, ordem = excluded.ordem;

-- MÉDIO 3.1 (revisão original da 0175/0176) — marcador de
-- `balcao_ambiguo_aprende_cnpj` trocado de novo: agora prova a CHAMADA real
-- a fn_entidade_aprender_cnpj dentro do ramo do balcão (variável renomeada
-- nesta migration), não a guarda do renomeio. Migration do requisito
-- CONTINUA '0175' — é a chave que importa, não quem a atualiza.
insert into instalacao_requisito
  (chave, migration, tipo, objeto, marcador, criterio_seed, porque, severidade, ordem) values
  ('balcao_ambiguo_aprende_cnpj', '0175', 'corpo', 'fn_registrar_diagnostico',
   'v_entidade_id_balcao := fn_entidade_aprender_cnpj(v_entidade_id, p_cnpj)', null,
   'Sem a tentativa de CNPJ dentro do ramo do balcão ambíguo (0162/0175), dois documentos da '
   'MESMA empresa em DOIS balcões diferentes nunca convergem, mesmo trazendo o MESMO CNPJ — '
   'MEDIDO em produção (caso bf0246bb-c93b-4d08-a7df-5d356c9d6275, OMNIBEAUTY, teste 143). '
   'MARCADOR TROCADO NA 0177: o da 0176 '
   '(''fn_cnpj_canonico(v_entidade_cnpj_pos_aprender) = fn_cnpj_canonico(p_cnpj)'') provava a '
   'guarda do RENOMEIO, não a chamada a fn_entidade_aprender_cnpj em si — essa chamada tinha '
   'texto IDÊNTICO ao do ramo `else` (0172), MEDIDO por contagem via pg_get_functiondef contra o '
   'corpo do estado da 0176: `2` ocorrências de '
   '''v_entidade_id := fn_entidade_aprender_cnpj(v_entidade_id, p_cnpj)''. Se uma reemissão futura '
   'removesse SÓ a chamada do ramo do balcão, o requisito continuaria "presente" via o texto '
   'genérico do ramo `else`. O novo marcador usa a variável local `v_entidade_id_balcao` — só '
   'existe no ramo do balcão (0177) — e desaparece se a chamada de lá for removida. MEDIDO depois '
   'desta migration: `1` ocorrência do texto novo, `1` do texto genérico (só o ramo `else`).',
   'bloqueante', 730)
on conflict (chave) do update set
  migration = excluded.migration, tipo = excluded.tipo, objeto = excluded.objeto,
  marcador = excluded.marcador, criterio_seed = excluded.criterio_seed,
  porque = excluded.porque, severidade = excluded.severidade, ordem = excluded.ordem;

update instalacao_cobertura
   set ate_migration = '0177', revisado_em = current_date,
       observacao = 'A 0177 corrige o que uma SEGUNDA revisão independente mediu na 0176: '
                    '(CRÍTICO) a guarda de fn_entidade_aprender_cnpj era UNIDIRECIONAL — só '
                    'bloqueava quando v_outra_id era o balcão, mas o caminho PRINCIPAL desde a '
                    '0175 chama a função com o balcão em p_entidade_id, o lado desprotegido; '
                    'virou XOR bidirecional; (ALTO) fn_upsert_entidade abria pendência de '
                    'colisão FALSA quando o balcão recebia mais um documento seu — corrigido '
                    'checando se o nome que chega é o do próprio balcão; (MÉDIO 1) '
                    'fn_pendencia_cnpj_colide_balcao agora ACUMULA todas as colisões contra o '
                    'mesmo balcão, em vez de sobrescrever a descrição a cada nova; (MÉDIO 2) o '
                    'marcador de balcao_ambiguo_aprende_cnpj trocado para provar a chamada real '
                    '(variável local renomeada no ramo do balcão), não mais a guarda do '
                    'renomeio.';
