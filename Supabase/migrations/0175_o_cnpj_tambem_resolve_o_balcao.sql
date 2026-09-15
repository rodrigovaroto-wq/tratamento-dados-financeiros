-- =============================================================================
-- 0175 — Dentro do balcão ambíguo, o CNPJ nunca era consultado
--
-- MEDIDO EM PRODUÇÃO (relato do dono, sessão 90; reproduzido aqui com os
-- MESMOS nomes reais e o MESMO CNPJ): caso bf0246bb-c93b-4d08-a7df-5d356c9d6275
-- ("teste 143", OMNIBEAUTY, CNPJ 36.193.378/0001-04). Depois de republicar o
-- workflow com as migrations até a 0173 e rodar o lote real, `evento_auditoria`
-- mostrou DOIS `entidade_ambigua` NOVOS, não uma fusão — as mesmas variantes
-- de nome de sempre, continuando SEPARADAS mesmo com o CNPJ chegando pelos dois
-- documentos.
--
-- A CAUSA, com o número: dentro de `fn_registrar_diagnostico`, o ramo
-- `if fn_entidade_e_balcao_ambiguo(...) then` (0162) só sabe perguntar ao
-- NOME — conta quantas outras entidades do caso casam EXATO com o nome
-- diagnosticado e, se for exatamente uma, abre uma pendência para um humano
-- confirmar a fusão. Ele NUNCA chama `fn_entidade_aprender_cnpj`, mesmo
-- quando `p_cnpj` não é nulo. Todo balcão ambíguo nasce sem CNPJ (a 0153/0162
-- não conhecem CNPJ). Quando dois documentos da MESMA empresa caem em DOIS
-- balcões ambíguos DIFERENTES — o cenário real medido — nenhum dos dois
-- converge nunca: a única saída do ramo é uma pendência para decisão humana,
-- e o CNPJ, que resolveria isso sozinho em QUALQUER outro caminho do sistema
-- desde a 0169 ("o CNPJ é a identidade que o nome não é"), nunca é
-- consultado aqui. Medido acima de escrever a correção, contra o estado da
-- 0174: dois documentos com o MESMO CNPJ, um em cada balcão, terminam com 4
-- entidades e 2 pendências `entidade_ambigua` abertas — os mesmos números de
-- antes de rodar. Nenhuma exceção, nenhum sintoma visível: é uma ausência
-- silenciosa, não um crash (ao contrário da 0174, cujo defeito era uma
-- exceção).
--
-- A CORREÇÃO: dentro do ramo do balcão ambíguo, tenta o CNPJ ANTES do nome —
-- é a MESMA regra 1 da 0169, chegando pela porta que faltava, com prioridade
-- sobre "casa por nome com exatamente uma candidata". `fn_entidade_aprender_cnpj`
-- (0169/0174) já sabe fazer as duas coisas que podem acontecer aqui:
--
--   (a) NENHUMA outra entidade do caso tem este CNPJ ainda: ela grava o CNPJ
--       no PRÓPRIO balcão. O balcão continua sendo um balcão ambíguo — a
--       pendência `entidade_ambigua` ORIGINAL continua aberta, porque o NOME
--       continua ambíguo — mas agora tem identidade fiscal para o PRÓXIMO
--       documento com o mesmo CNPJ convergir nele. É o resultado ESPERADO,
--       não uma correção parcial: o CNPJ não apaga a pergunta "que empresa é
--       esta", só dá ao sistema um jeito de reconhecer o SEGUNDO documento.
--   (b) OUTRA entidade do caso já tem este CNPJ (pode ser outro balcão que
--       aprendeu primeiro, como no cenário medido, ou uma entidade normal):
--       `fn_entidade_aprender_cnpj` FUNDE esta entidade NELA (`fn_fundir_entidade`)
--       e devolve o id da sobrevivente — o retorno é usado, nunca `perform`,
--       pelo MESMO cuidado que a 0174 corrigiu nos outros dois chamadores
--       (sem isso, `v_entidade_id` ficaria apontando para uma linha deletada
--       e o restante da função, incluindo o `entidade_id` no jsonb de
--       retorno, mentiria). `fn_fundir_entidade` já resolve a pendência
--       `entidade_ambigua:<id de quem foi fundido>` (Supabase/schema.sql:3356)
--       — é ASSIM que dois balcões convergem em UM: cada fusão fecha a
--       ambiguidade de quem foi fundido. Se o SOBREVIVENTE também nasceu
--       ambíguo por um nome diferente, a pendência DELE não fecha aqui — ela
--       fecha quando um TERCEIRO documento também trouxer o mesmo CNPJ e
--       fundir alguém nele, ou por decisão humana. Não fabricar essa segunda
--       resolução é a regra 1 do CLAUDE.md pelo avesso: silêncio sobre o que
--       não foi provado é honesto.
--
-- SÓ TENTA RESOLVER PELO NOME SE O CNPJ NÃO RESOLVEU: a lógica de nome
-- (inalterada) agora fica dentro de um segundo `if fn_entidade_e_balcao_ambiguo`,
-- checado DEPOIS da tentativa de CNPJ — se a entidade ainda é um balcão
-- ambíguo (sem CNPJ para tentar, ou com CNPJ que só gravou no próprio balcão
-- sem achar outra dona), o nome continua sendo o único sinal disponível, e o
-- comportamento é EXATAMENTE o de antes desta migration.
--
-- O RENOMEIO VEM JUNTO, pela MESMA função que o ramo `else` (confirmação por
-- nome) já usa desde a 0173 — não duplica lógica. Quando a fusão (b)
-- acontece, `fn_entidade_aprender_cnpj` já chama `fn_entidade_talvez_renomear`
-- por dentro, com o nome do balcão que acabou de ser fundido (o "de"). A
-- chamada acrescentada aqui cobre o caso (a): sem fusão, com o nome lido do
-- CONTEÚDO deste documento (`p_entidade_nome`) como candidato a nome mais
-- completo para o próprio balcão — as MESMAS três guardas da 0171/0173 (só
-- entre truncamentos, nunca cria homônima, recusa com rastro) decidem, e
-- MEDIDO no teste desta fatia: nos dois casos do cenário real (MARCAS LTDA e
-- SURUBIJU já existem como entidades de VERDADE com esses nomes exatos), a
-- guarda de homônima RECUSA o renomeio dos dois lados — o balcão ganha CNPJ,
-- mas mantém o próprio nome truncado, porque adotar o nome de MARCAS ou de
-- SURUBIJU criaria uma entidade homônima da que já existe. É a guarda
-- funcionando, não um defeito: ver Supabase/test/cnpj_renomeia.test.sql
-- bloco 10 para a mesma guarda no caminho antigo.
--
-- Reemite `fn_registrar_diagnostico` INTEIRA, verbatim do corpo vigente
-- (Supabase/schema.sql, confirmado idêntico ao corpo publicado pela 0174),
-- com só esta mudança — nunca por âncora de texto em corpo de função
-- (.claude/memory/nunca-corrigir-funcao-por-replace.md). A assinatura não
-- muda, então `create or replace` basta, sem DROP.
-- =============================================================================

begin;

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
        -- nunca `perform` (0174).
        if p_cnpj is not null then
          v_entidade_id := fn_entidade_aprender_cnpj(v_entidade_id, p_cnpj);

          -- E O RENOMEIO VEM JUNTO, pela MESMA função do ramo `else` (0173) —
          -- não duplica lógica. Se a linha acima FUNDIU, `fn_entidade_aprender_cnpj`
          -- já chamou fn_entidade_talvez_renomear por dentro com o nome do
          -- balcão fundido; esta chamada cobre o caso SEM fusão, em que o
          -- nome lido do CONTEÚDO deste documento pode ser a variante mais
          -- completa para o balcão que acabou de aprender o CNPJ.
          perform fn_entidade_talvez_renomear(v_caso_id, v_entidade_id, p_entidade_nome, p_cnpj);
        end if;

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
  'passava a apontar para uma linha deletada se ninguém capturasse o retorno. 0175: o ramo do '
  'balcão ambíguo (0162) agora tenta o CNPJ ANTES do nome — grava no próprio balcão, ou funde '
  'com quem já tinha o CNPJ (usando o retorno, com o mesmo cuidado da 0174), com o renomeio pela '
  'mesma fn_entidade_talvez_renomear da 0173 — e só cai na lógica de nome (inalterada) se o '
  'balcão ainda for ambíguo depois disso.';

-- -----------------------------------------------------------------------------
-- O CATÁLOGO DA SONDA.
-- -----------------------------------------------------------------------------
insert into instalacao_requisito
  (chave, migration, tipo, objeto, marcador, criterio_seed, porque, severidade, ordem) values
  ('balcao_ambiguo_aprende_cnpj', '0175', 'corpo', 'fn_registrar_diagnostico',
   -- CÓDIGO, não comentário nem número de migration
   -- (Supabase/test/sonda_marcador_e_codigo.test.sql): esta condição só existe
   -- dentro do ramo do balcão ambíguo depois da 0175, e não aparece em NENHUM
   -- outro lugar da função nem do schema inteiro (conferido por grep contra o
   -- schema.sql regenerado) — ao contrário da chamada a
   -- `fn_entidade_aprender_cnpj(v_entidade_id, p_cnpj)` em si, que já existe
   -- verbatim no ramo `else` desde a 0172 e por isso NÃO serviria de marcador.
   'if p_cnpj is not null then', null,
   'Sem esta chamada, o ramo do balcão ambíguo (0162) só sabe perguntar ao NOME, e todo balcão '
   'nasce sem CNPJ (0153/0162 não conhecem CNPJ) — dois documentos da MESMA empresa em DOIS '
   'balcões diferentes nunca convergem, mesmo trazendo o MESMO CNPJ. MEDIDO em produção (caso '
   'bf0246bb-c93b-4d08-a7df-5d356c9d6275, OMNIBEAUTY, teste 143): depois de republicar até a '
   '0173 e rodar o lote real, evento_auditoria mostrou DOIS entidade_ambigua novos em vez de uma '
   'fusão. Reproduzido contra o estado da 0174 (Supabase/test/balcao_ambiguo_e_cnpj.test.sql): '
   'dois documentos com o mesmo CNPJ, um em cada balcão, terminam com 4 entidades e 2 pendências '
   'entidade_ambigua abertas — sem crash, uma ausência silenciosa de convergência.',
   'bloqueante', 730)
on conflict (chave) do update set
  migration = excluded.migration, tipo = excluded.tipo, objeto = excluded.objeto,
  marcador = excluded.marcador, criterio_seed = excluded.criterio_seed,
  porque = excluded.porque, severidade = excluded.severidade, ordem = excluded.ordem;

update instalacao_cobertura
   set ate_migration = '0175', revisado_em = current_date,
       observacao = 'A 0175 acrescenta, dentro do ramo do balcão ambíguo (0162) de '
                    'fn_registrar_diagnostico, uma tentativa de resolver pelo CNPJ ANTES do '
                    'nome: aprende o CNPJ no próprio balcão (0169/0174) ou funde com quem já '
                    'tinha o mesmo CNPJ, com o renomeio da 0173 pela mesma função — e só cai na '
                    'lógica de nome (inalterada, desde a 0162) se o balcão ainda for ambíguo '
                    'depois disso. Sem assinatura nova, sem overload (0118/0170).';

commit;
