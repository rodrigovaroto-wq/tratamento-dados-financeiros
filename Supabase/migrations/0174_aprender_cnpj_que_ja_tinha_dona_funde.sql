-- =============================================================================
-- 0174 — Aprender o CNPJ de uma entidade que JÁ TEM outra dona derrubava tudo
--
-- MEDIDO EM PRODUÇÃO, não em fixture: o dono rodou o lote real da OMNIBEAUTY
-- (caso bf0246bb-c93b-4d08-a7df-5d356c9d6275, teste 143) depois de republicar
-- o workflow com as migrations até a 0173, e `evento_auditoria` mostrou DOIS
-- `entidade_ambigua` novos em vez de uma fusão — as mesmas quatro variantes de
-- nome de sempre, ainda separadas. Reproduzido aqui com os MESMOS nomes reais
-- e o MESMO CNPJ (36.193.378/0001-04), na ordem em que o pipeline realmente
-- executa (documento registrado ANTES do diagnóstico rodar): a chamada que
-- crasha é `fn_entidade_aprender_cnpj`, com
--
--   ERROR: duplicate key value violates unique constraint "entidade_caso_cnpj_unico"
--
-- A CAUSA é estrutural, e as 0172/0173 já andavam perto dela sem pisar nela:
-- o CNPJ chega pelo DIAGNÓSTICO — o único caminho garantido para TODO
-- documento — mas SÓ DEPOIS que o documento já foi registrado (e a entidade
-- já resolvida) por NOME, sem CNPJ nenhum disponível ainda. Quando duas
-- variantes de nome da MESMA empresa chegam assim, cada uma vira (ou casa
-- aproximadamente com) uma entidade PRÓPRIA, sem CNPJ. O primeiro documento
-- confirmado ensina o CNPJ na sua entidade sem problema (`fn_entidade_aprender_cnpj`
-- via `UPDATE ... WHERE cnpj IS NULL`). O SEGUNDO documento, de uma entidade
-- DIFERENTE mas da MESMA empresa, tenta gravar o MESMO CNPJ — e o índice único
-- `entidade_caso_cnpj_unico (caso_id, cnpj)` (0169) rejeita. `fn_entidade_aprender_cnpj`
-- não tratava esse conflito: só sabia UPDATE ou nada, nunca fundir.
--
-- Como `fn_registrar_diagnostico` roda para TODO documento (é a premissa da
-- 0172), este crash não é um caso de borda raro: é o destino de QUALQUER par
-- de documentos da mesma empresa cujos nomes não casam por igualdade exata
-- nem por candidato aproximado ANTES de o CNPJ aparecer — exatamente o
-- cenário que motivou a 0171 inteira, só que pela porta errada.
--
-- A CORREÇÃO: `fn_entidade_aprender_cnpj` passa a devolver `uuid` (antes
-- `void`) — o id da entidade que sobrou. Quando o CNPJ já pertence a OUTRA
-- entidade do mesmo caso, ela funde a atual NELA (`fn_fundir_entidade`, que já
-- existe desde a fusão retroativa da OMNIBEAUTY e já deixa rastro) em vez de
-- tentar gravar; e chama `fn_entidade_talvez_renomear` (0171/0173) com o nome
-- da entidade que acabou de ser fundida, para a sobrevivente poder adotar o
-- nome mais completo — as MESMAS três guardas, sem duplicar lógica nenhuma.
-- Sem cnpj já registrado, sem outra dona: comportamento idêntico ao de antes.
--
-- OS DOIS CHAMADORES (`fn_upsert_entidade` ramo (1) e `fn_registrar_diagnostico`,
-- ramo que confirma) tinham de parar de `perform` e passar a usar o retorno:
-- sem isso, a variável local ficaria apontando para uma linha DELETADA depois
-- da fusão — em `fn_upsert_entidade` isso quebraria a FK de
-- `documento.entidade_id` no INSERT seguinte (um crash NOVO, pior que o que
-- está sendo consertado); em `fn_registrar_diagnostico`, o `entidade_id` do
-- jsonb devolvido para quem chamou (e o `fn_entidade_talvez_renomear` logo
-- depois) mentiriam.
--
-- Reemite as TRÊS funções INTEIRAS — `fn_entidade_aprender_cnpj` (com DROP:
-- muda o TIPO de retorno, e `create or replace` não permite isso), mais
-- `fn_upsert_entidade` e `fn_registrar_diagnostico` verbatim, com as duas
-- linhas trocadas — nunca por âncora de texto
-- (.claude/memory/nunca-corrigir-funcao-por-replace.md). Nenhuma ASSINATURA
-- muda nos dois chamadores, então não há overload novo (0118/0170).
-- =============================================================================

begin;

-- -----------------------------------------------------------------------------
-- fn_entidade_aprender_cnpj — agora devolve a entidade que sobrou, e funde
-- em vez de tentar gravar um CNPJ que já pertence a outra linha do caso.
-- -----------------------------------------------------------------------------
drop function fn_entidade_aprender_cnpj(uuid, text);

create function fn_entidade_aprender_cnpj(p_entidade_id uuid, p_cnpj text)
returns uuid
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

comment on function fn_entidade_aprender_cnpj(uuid, text) is
  'Grava o CNPJ numa entidade que ainda não tem um, com rastro (0169). Nunca sobrescreve: um '
  'CNPJ já gravado na MESMA entidade (mesmo que divergente) é decisão de humano. 0174: quando o '
  'CNPJ já pertence a OUTRA entidade do mesmo caso, funde as duas (fn_fundir_entidade) em vez de '
  'tentar gravar — sem isso o UPDATE violava entidade_caso_cnpj_unico e derrubava '
  'fn_registrar_diagnostico inteira. Devolve o id da entidade que sobrou: SEMPRE use o retorno, '
  'nunca o id que foi passado — depois de uma fusão ele pode apontar para uma linha deletada.';

grant execute on function fn_entidade_aprender_cnpj(uuid, text) to authenticated;

-- -----------------------------------------------------------------------------
-- fn_upsert_entidade — corpo da 0173 com o ramo (1) usando o retorno de
-- fn_entidade_aprender_cnpj em vez de `perform`.
-- -----------------------------------------------------------------------------
create or replace function fn_upsert_entidade(p_caso_id uuid, p_nome text, p_cnpj text DEFAULT NULL::text) RETURNS uuid
    LANGUAGE plpgsql
    AS $$
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

    -- O RASTRO É OBRIGATÓRIO AQUI, e a revisão desta fatia o achou faltando.
    -- Este é o ramo MAIS FORTE da função — funde sem olhar o nome — e era o
    -- único caminho de fusão sem uma linha em `evento_auditoria` (o (3b) grava
    -- `entidade_alias_fundido`, o de ambiguidade grava `entidade_ambigua`).
    --
    -- O cenário que torna isso perigoso é o MESMO template que já colou o
    -- endereço no nome: o rodapé do relatório traz o CNPJ do ESCRITÓRIO DE
    -- CONTABILIDADE, não o do emitente. Lido em documentos de três clientes do
    -- mesmo mandato, o primeiro cria a entidade e os outros dois caem nela sem
    -- comparar nome nenhum. É o dano da 0153 por uma porta nova — e sem o
    -- evento não haveria uma linha dizendo que "CONTABILIDADE X LTDA." foi
    -- respondido com "OMNIBEAUTY".
    if v_id is not null then
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
  'completa ao fundir por CNPJ (0171/0173 — a decisão mora em fn_entidade_talvez_renomear, '
  'chamada dos dois caminhos). 0174: o ramo (1) usa o RETORNO de fn_entidade_aprender_cnpj — ela '
  'pode fundir esta entidade numa outra do mesmo caso que já tinha o CNPJ, e devolver o id de '
  'quem sobrou não é mais opcional.';

-- -----------------------------------------------------------------------------
-- fn_registrar_diagnostico — corpo da 0173 com o ramo que confirma usando o
-- retorno de fn_entidade_aprender_cnpj em vez de `perform`.
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
        -- pendências logo abaixo são a resposta certa para ela.
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
  'passava a apontar para uma linha deletada se ninguém capturasse o retorno.';

-- -----------------------------------------------------------------------------
-- O CATÁLOGO DA SONDA.
-- -----------------------------------------------------------------------------
insert into instalacao_requisito
  (chave, migration, tipo, objeto, marcador, criterio_seed, porque, severidade, ordem) values
  ('cnpj_aprender_funde_duplicata', '0174', 'corpo', 'fn_entidade_aprender_cnpj',
   'fn_fundir_entidade(v_caso_id, p_entidade_id, v_outra_id', null,
   'Sem esta chamada, aprender um CNPJ que já pertence a OUTRA entidade do mesmo caso viola o '
   'índice único entidade_caso_cnpj_unico (0169) e DERRUBA fn_registrar_diagnostico — que roda '
   'para TODO documento. MEDIDO reproduzindo com os nomes e o CNPJ reais de produção (caso '
   'bf0246bb-c93b-4d08-a7df-5d356c9d6275, OMNIBEAUTY, teste 143): "duplicate key value violates '
   'unique constraint entidade_caso_cnpj_unico" — o mesmo lote que motivou a 0169/0171 continuava '
   'quebrando depois delas, só que num ponto mais tarde do pipeline.',
   'bloqueante', 720)
on conflict (chave) do update set
  migration = excluded.migration, tipo = excluded.tipo, objeto = excluded.objeto,
  marcador = excluded.marcador, criterio_seed = excluded.criterio_seed,
  porque = excluded.porque, severidade = excluded.severidade, ordem = excluded.ordem;

update instalacao_cobertura
   set ate_migration = '0174', revisado_em = current_date,
       observacao = 'A 0174 muda fn_entidade_aprender_cnpj de void para uuid (DROP + CREATE — '
                    'create or replace não permite mudar tipo de retorno) e a faz FUNDIR quando '
                    'o CNPJ já pertence a outra entidade do mesmo caso, em vez de tentar gravar e '
                    'crashar. Reemite fn_upsert_entidade e fn_registrar_diagnostico INTEIRAS para '
                    'trocar `perform` pelo uso do retorno nos dois chamadores — sem isso a '
                    'variável local ficaria com um id deletado na mão. Nenhuma assinatura muda '
                    'nos dois chamadores, então não há overload novo (0118/0170).';

commit;
