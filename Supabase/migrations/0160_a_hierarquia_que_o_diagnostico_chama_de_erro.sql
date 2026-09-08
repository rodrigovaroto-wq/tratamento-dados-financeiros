-- =============================================================================
-- Migration 0160 — O diagnóstico não sabia que o nome apontado já era outra
-- empresa cadastrada no mesmo mandato.
--
-- MEDIDO NA RODADA REAL do lote `7377` (02/09, mandato "teste Canastra", ver
-- `ESTADO.md` seção "SESSÃO 79"). O documento `33_Notas_Explicativas` está
-- registrado na entidade **GRUPO CANASTRA**; o diagnóstico de conteúdo lê o
-- texto do próprio documento e aponta **Canastra Indústria**. `fn_registrar_
-- diagnostico` abriu `entidade_incorreta` dizendo que o documento "está
-- registrado" com o nome errado — como se soubesse que GRUPO CANASTRA é a
-- resposta errada e Canastra Indústria a certa.
--
-- NÃO SE SABE QUAL DAS DUAS É A CERTA. O que se sabe, sem inventar nada, é que
-- as duas são empresas REAIS e DISTINTAS do mesmo mandato — o fixture do book
-- Canastra já cadastra as duas como linhas próprias de `entidade`
-- (`Supabase/test/fixture_book_canastra.sql`: `GRUPO CANASTRA` e `CANASTRA
-- INDÚSTRIA DE EMBALAGENS LTDA.`, no mesmo `caso_id`) — não que uma seja
-- holding da outra: `entidade.papel_no_grupo` (0001) é o único campo que
-- registraria essa relação, e nem o diagnóstico nem esta migration o consultam.
-- Reproduzido contra esse fixture, sem inventar nada:
--
--     fn_mesma_entidade('GRUPO CANASTRA', 'CANASTRA INDÚSTRIA DE EMBALAGENS LTDA.') → false
--
-- Confirma que a ambiguidade da `0153` NÃO cobre este caso: aquela migration
-- trata do nome que casa com DUAS entidades já cadastradas (`fn_upsert_
-- entidade`, chamada quando um documento CHEGA sem entidade e o nome é
-- procurado). Aqui a função é outra (`fn_registrar_diagnostico`), o documento
-- JÁ TEM entidade, e o que se compara são dois nomes que **não casam entre
-- si** — "grupo canastra" não é subsequência de "canastra industria" nem
-- vice-versa, então `fn_mesma_entidade` corretamente diz que não é a MESMA
-- empresa. O defeito não é aí: é que a função só sabia responder "é a mesma
-- empresa" ou "é erro" — não tinha uma terceira resposta para "são duas
-- empresas DIFERENTES, e as duas já existem neste mandato, e eu não sei qual
-- das duas é a certa aqui".
--
-- A CAUSA, em `fn_registrar_diagnostico` (0121): o `else` de
-- `fn_mesma_entidade(v_entidade_atual_nome, p_entidade_nome) = false` vai
-- direto para "abre `entidade_incorreta`", sem perguntar se o nome
-- diagnosticado é, ele mesmo, uma OUTRA empresa já cadastrada no caso. Quando
-- é, a pendência que nasce chama de "incorreto" um registro que TALVEZ esteja
-- certo — não há como saber pelo nome sozinho se o documento pertence mesmo a
-- GRUPO CANASTRA ou deveria estar em Canastra Indústria — e não fecha sozinha,
-- porque o humano não tem como "corrigir" algo que pode não estar errado.
--
-- ---------------------------------------------------------------------------
-- O QUE ESTA MIGRATION NÃO FAZ, E POR QUÊ
-- ---------------------------------------------------------------------------
--
-- **Não decide de quem é o documento.** Igual à 0153: um nome que aponta para
-- outra empresa real do mandato é uma PERGUNTA para o humano decidir (o
-- documento pertence a quem está registrado ou deveria estar na outra
-- candidata?), nunca uma escolha automática — mover o documento sozinho
-- arriscaria o mesmo dano que a 0153 evitou ao não fundir.
--
-- **Não funde nenhuma entidade.** `fn_fundir_entidade` (0153) existe para
-- quando duas linhas são a MESMA empresa com grafias diferentes. Aqui os
-- nomes NÃO casam entre si (`fn_mesma_entidade` já disse que não é a mesma
-- empresa) — fundi-las apagaria uma distinção que pode ser real (é por isso
-- que o book Canastra as cadastra em linhas separadas desde o fixture). A
-- saída daqui é confirmar a entidade do documento pela revisão que já existe,
-- não fundir nem presumir qual das duas é a certa.
--
-- **Não afirma hierarquia.** `entidade.papel_no_grupo` (0001) é o único campo
-- que registraria holding × subsidiária, e nem o diagnóstico de conteúdo nem
-- esta migration o consultam — não há como saber, só a partir de dois nomes
-- que não casam, qual é a relação entre as duas empresas, ou se há relação
-- alguma. O que a pendência afirma é só o que dá para provar: as candidatas
-- já existem no caso, e o sistema não sabe qual delas é a certa.
--
-- **Reaproveita `fn_entidades_candidatas` da 0153** em vez de duplicar a
-- busca: ela já sabe achar, dentro do caso, toda entidade com que um nome
-- casa por `fn_mesma_entidade`. Usada aqui para achar se o nome diagnosticado
-- é OUTRA entidade (ou mais de uma) do caso — diferente da já registrada no
-- documento, e SEM escolher uma no empate quando há mais de uma candidata
-- (a mesma armadilha que a 0153 corrigiu em `fn_upsert_entidade`).
--
-- ---------------------------------------------------------------------------
-- POR QUE É PATCH COM ÂNCORA, e não reemissão inteira: é a lição da própria
-- 0121, aplicada nesta sessão antes de commitar. Uma primeira versão desta
-- migration reemitiu `fn_registrar_diagnostico` INTEIRA, copiando o corpo do
-- arquivo da 0121 — e por pouco regrediu o patch da `0142` em silêncio (a
-- condição de `tipo_incorreto`), que só existe no corpo VIGENTE, aplicado por
-- regex sobre o banco, e não no texto de nenhum arquivo de migration sozinho.
-- `Supabase/test/instalacao.test.sql` pegou: o requisito `corpo` da `0142`
-- caiu para ausente. É a mesma regressão silenciosa que a 0006 registrou e
-- que a 0141/0142 passaram a evitar com âncora — este arquivo segue o mesmo
-- caminho, com uma âncora maior porque a resposta nova precisa de um terceiro
-- ramo, não só trocar uma condição.
-- =============================================================================

do $mig$
declare
  v_src text; v_novo text;
  v_pat constant text := $pat$\ \ \ \ else\r?\n\ \ \ \ \ \ select\ razao_social\ into\ v_entidade_atual_nome\ from\ entidade\ where\ id\ =\ v_entidade_id;\r?\n\ \ \ \ \ \ select\ id\ into\ v_pendencia_id\ from\ pendencia\r?\n\ \ \ \ \ \ \ \ where\ caso_id\ =\ v_caso_id\ and\ motivo\ =\ 'diagnostico:entidade:'\ \|\|\ p_documento_id\ and\ estado\ <>\ 'resolvida'\r?\n\ \ \ \ \ \ \ \ limit\ 1;\r?\n\ \ \ \ \ \ \-\-\ 0121:\ divergência\ de\ ENTIDADE\ passa\ a\ ser\ medida\ pela\ forma\ canônica,\r?\n\ \ \ \ \ \ \-\-\ como\ o\ período\ já\ é\ desde\ a\ 0022\.\ "Canastra\ Industria"\ e\ "CANASTRA\r?\n\ \ \ \ \ \ \-\-\ INDÚSTRIA\ DE\ EMBALAGENS\ LTDA\."\ são\ a\ mesma\ empresa,\ e\ `fn_mesma_entidade`\r?\n\ \ \ \ \ \ \-\-\ já\ sabia\ disso\ —\ só\ esta\ comparação\ não\ perguntava,\ e\ por\ isso\ abria\r?\n\ \ \ \ \ \ \-\-\ pendência\ de\ divergência\ entre\ dois\ nomes\ da\ mesma\ companhia\.\r?\n\ \ \ \ \ \ if\ not\ fn_mesma_entidade\(v_entidade_atual_nome,\ p_entidade_nome\)\ then\r?\n\ \ \ \ \ \ \ \ if\ v_pendencia_id\ is\ null\ then\r?\n\ \ \ \ \ \ \ \ \ \ insert\ into\ pendencia\ \(caso_id,\ origem_estagio,\ tipo,\ severidade,\ sobrepujavel,\ descricao,\ documento_id,\ motivo\)\r?\n\ \ \ \ \ \ \ \ \ \ \ \ values\ \(v_caso_id,\ 'diagnostico',\ 'entidade_incorreta',\ 'importante',\ true,\r?\n\ \ \ \ \ \ \ \ \ \ \ \ \ \ format\('Diagnóstico\ de\ conteúdo\ sugere\ entidade\ "%s",\ mas\ o\ documento\ está\ registrado\ com\ "%s"\.',\r?\n\ \ \ \ \ \ \ \ \ \ \ \ \ \ \ \ \ \ \ \ \ p_entidade_nome,\ coalesce\(v_entidade_atual_nome,\ '\(nenhuma\)'\)\),\r?\n\ \ \ \ \ \ \ \ \ \ \ \ \ \ p_documento_id,\ 'diagnostico:entidade:'\ \|\|\ p_documento_id\);\r?\n\ \ \ \ \ \ \ \ end\ if;\r?\n\ \ \ \ \ \ elsif\ v_pendencia_id\ is\ not\ null\ then\r?\n\ \ \ \ \ \ \ \ update\ pendencia\ set\ estado\ =\ 'resolvida',\ resolvida_em\ =\ now\(\),\ resolvida_por\ =\ 'sistema:diagnostico'\r?\n\ \ \ \ \ \ \ \ \ \ where\ id\ =\ v_pendencia_id;\r?\n\ \ \ \ \ \ end\ if;$pat$;
  v_rep constant text := $rep$    else
      select razao_social into v_entidade_atual_nome from entidade where id = v_entidade_id;

      select id into v_pendencia_id from pendencia
        where caso_id = v_caso_id and motivo = 'diagnostico:entidade:' || p_documento_id and estado <> 'resolvida'
        limit 1;
      select id into v_pendencia_grupo_id from pendencia
        where caso_id = v_caso_id and motivo = 'diagnostico:entidade_grupo:' || p_documento_id and estado <> 'resolvida'
        limit 1;

      -- 0121: divergência de ENTIDADE medida pela forma canônica, como o
      -- período já é desde a 0022. "Canastra Industria" e "CANASTRA INDÚSTRIA
      -- DE EMBALAGENS LTDA." são a mesma empresa, e `fn_mesma_entidade` já
      -- sabia disso.
      if fn_mesma_entidade(v_entidade_atual_nome, p_entidade_nome) then
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
      end if;$rep$;
begin
  select pg_get_functiondef(p.oid) into v_src
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public' and p.proname = 'fn_registrar_diagnostico';

  if v_src is null then
    raise exception '0160: fn_registrar_diagnostico não existe — migration fora de ordem';
  end if;

  if (select count(*) from regexp_matches(v_src, v_pat, 'g')) <> 1 then
    raise exception '0160: o bloco de comparação de entidade não foi encontrado UMA vez — este patch precisa ser relido por gente';
  end if;

  v_novo := regexp_replace(v_src, v_pat, v_rep);

  -- as três variáveis novas que o ramo de hierarquia usa.
  if (select count(*) from regexp_matches(v_novo, 'v_entidade_criada     boolean := false;')) <> 1 then
    raise exception '0160: âncora da declaração de variáveis não encontrada UMA vez';
  end if;
  v_novo := regexp_replace(v_novo,
    'v_entidade_criada     boolean := false;',
    E'v_entidade_criada     boolean := false;\n' ||
    E'  v_pendencia_grupo_id  uuid;\n' ||
    E'  v_outros_n            int;\n' ||
    E'  v_outros_nomes        text;');

  execute v_novo;

  -- Confere em vez de confiar.
  select pg_get_functiondef(p.oid) into v_src
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public' and p.proname = 'fn_registrar_diagnostico';
  if position('0160: o nome que não casou' in v_src) = 0 then
    raise exception '0160: a função foi recriada sem o ramo de hierarquia — abortado';
  end if;
  if position('0142: exige divergência ACIONÁVEL' in v_src) = 0 then
    raise exception '0160: o patch apagou o da 0142 — abortado';
  end if;
end $mig$;

comment on function fn_registrar_diagnostico(uuid, uuid, text, boolean, text, text, text, legibilidade, text, text, text) is
  'Registra o diagnóstico de conteúdo (E1/E2) e confere contra o que já está no banco. 0121: a '
  'entidade casa e diverge pela forma CANÔNICA. 0142: tipo só diverge com divergência ACIONÁVEL. '
  '0160: quando a entidade não casa, mas o nome diagnosticado é ELE MESMO outra (ou mais de uma) '
  'empresa já cadastrada no mesmo caso, a função não sabe se o registro está certo ou errado — não '
  'presume nenhuma das duas, nomeia as candidatas na pendência e deixa a revisão decidir, sem '
  'fundir nem mover o documento sozinha.';

grant execute on function fn_registrar_diagnostico(uuid, uuid, text, boolean, text, text, text, legibilidade, text, text, text) to authenticated;

-- =============================================================================
-- SONDA
-- =============================================================================
insert into instalacao_requisito
  (chave, migration, tipo, objeto, marcador, criterio_seed, porque, severidade, ordem) values
  ('entidade_hierarquia_nao_e_erro', '0160', 'corpo', 'fn_registrar_diagnostico', '0160', null,
   'Medido no lote 7377 (02/09): `33_Notas_Explicativas` registrado em GRUPO CANASTRA, diagnóstico '
   'aponta Canastra Indústria — as duas são empresas REAIS e distintas do mesmo mandato (o fixture '
   'cadastra as duas em linhas próprias de `entidade`), e a pendência `entidade_incorreta` chamava '
   'isso de erro sem saber que "Canastra Indústria" já era uma entidade cadastrada no caso — sem '
   'saber, tampouco, se o registro em GRUPO CANASTRA está certo ou errado. '
   '`fn_mesma_entidade(''GRUPO CANASTRA'', ''CANASTRA INDÚSTRIA DE EMBALAGENS LTDA.'') = false`: a '
   '0153 (ambiguidade em fn_upsert_entidade) não cobre este caso — é função diferente, e os dois '
   'nomes não casam entre si.',
   'importante', 580)
on conflict (chave) do update
  set migration = excluded.migration, tipo = excluded.tipo, objeto = excluded.objeto,
      marcador = excluded.marcador, criterio_seed = excluded.criterio_seed,
      porque = excluded.porque, severidade = excluded.severidade, ordem = excluded.ordem;

update instalacao_cobertura
   set ate_migration = '0160',
       revisado_em = date '2026-09-08',
       observacao = 'Revisão de 08/09/2026: a 0160 dá uma terceira resposta a '
                    'fn_registrar_diagnostico quando entidade registrada e diagnosticada não '
                    'casam — se o nome diagnosticado já é ELE MESMO outra empresa (ou mais de uma) '
                    'cadastrada no mesmo caso, a função não sabe se o registro está certo, e para de '
                    'chamar isso de erro sem decidir quem está certo. Medido no lote 7377: GRUPO '
                    'CANASTRA × Canastra Indústria, achado que é anterior à 0153 e que ela não cobre '
                    '(função diferente, nomes que não casam entre si). Patch por ÂNCORA sobre o '
                    'corpo VIGENTE de fn_registrar_diagnostico (não reemissão), para não regredir o '
                    'patch da 0142 em silêncio — a lição desta própria migration, ver cabeçalho.'
 where id;
