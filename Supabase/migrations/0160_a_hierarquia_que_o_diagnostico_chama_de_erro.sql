-- =============================================================================
-- Migration 0160 — Holding registrada, subsidiária no conteúdo: não é erro.
--
-- MEDIDO NA RODADA REAL do lote `7377` (02/09, mandato "teste Canastra", ver
-- `ESTADO.md` seção "SESSÃO 79"). O documento `33_Notas_Explicativas` está
-- registrado na entidade **GRUPO CANASTRA**; o diagnóstico de conteúdo lê o
-- texto do próprio documento e aponta **Canastra Indústria**. `fn_registrar_
-- diagnostico` abriu `entidade_incorreta` dizendo que o documento "está
-- registrado" com o nome errado.
--
-- NÃO É ERRO. As duas são empresas REAIS e DISTINTAS do mesmo mandato — a
-- holding e uma das subsidiárias — e o fixture do book Canastra já cadastra
-- as duas como linhas próprias de `entidade` (`Supabase/test/fixture_book_
-- canastra.sql`: `GRUPO CANASTRA` e `CANASTRA INDÚSTRIA DE EMBALAGENS LTDA.`,
-- no mesmo `caso_id`). Reproduzido contra esse fixture, sem inventar nada:
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
-- empresas DIFERENTES, e as duas já existem neste mandato".
--
-- A CAUSA, em `fn_registrar_diagnostico` (0121): o `else` de
-- `fn_mesma_entidade(v_entidade_atual_nome, p_entidade_nome) = false` vai
-- direto para "abre `entidade_incorreta`", sem perguntar se o nome
-- diagnosticado é, ele mesmo, uma OUTRA empresa já cadastrada no caso. Quando
-- é, a pendência que nasce chama de "incorreto" um registro que está correto
-- — o documento está mesmo em GRUPO CANASTRA — e não fecha sozinha, porque
-- nenhum humano vai "corrigir" um nome que não estava errado.
--
-- ---------------------------------------------------------------------------
-- O QUE ESTA MIGRATION NÃO FAZ, E POR QUÊ
-- ---------------------------------------------------------------------------
--
-- **Não decide de quem é o documento.** Igual à 0153: um nome que aponta para
-- outra empresa real do mandato é uma PERGUNTA para o humano decidir (o
-- documento pertence à holding ou deveria estar associado à subsidiária?),
-- nunca uma escolha automática — mover o documento sozinho arriscaria o
-- mesmo dano que a 0153 evitou ao não fundir.
--
-- **Não funde as duas entidades.** `fn_fundir_entidade` (0153) existe para
-- quando duas linhas são a MESMA empresa com grafias diferentes. Holding e
-- subsidiária são empresas DIFERENTES de propósito — fundi-las apagaria a
-- distinção que o mandato existe para preservar (é por isso que o book
-- Canastra as cadastra em linhas separadas desde o fixture). A saída daqui é
-- confirmar a entidade do documento pela revisão que já existe, não fundir.
--
-- **Reaproveita `fn_entidades_candidatas` da 0153** em vez de duplicar a
-- busca: ela já sabe achar, dentro do caso, toda entidade com que um nome
-- casa por `fn_mesma_entidade`. Usada aqui para achar se o nome diagnosticado
-- é uma OUTRA entidade do caso — diferente da já registrada no documento.
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
        -- 0160: o nome que não casou com o registrado pode ser OUTRA empresa
        -- já cadastrada NESTE caso — hierarquia legítima (holding × subsidiária,
        -- ou duas empresas do mesmo grupo), não erro de registro. Excluída a
        -- própria entidade do documento, para não contar "casou consigo mesma"
        -- como candidata a outra empresa. Reaproveita `fn_entidades_candidatas`
        -- da 0153 em vez de duplicar a busca.
        select c.entidade_id, c.razao_social into v_outra_entidade_id, v_outra_entidade_nome
        from fn_entidades_candidatas(v_caso_id, p_entidade_nome) c
        where c.entidade_id <> v_entidade_id
        order by c.exata desc, c.razao_social
        limit 1;

        if v_outra_entidade_id is not null then
          -- HIERARQUIA: não decide quem está certo — só para de chamar de
          -- "incorreto" um registro que aponta para uma empresa real do
          -- mandato. A pendência de erro clássica, se estava aberta de uma
          -- rodada anterior, fecha — a resposta mudou de categoria.
          if v_pendencia_id is not null then
            update pendencia set estado = 'resolvida', resolvida_em = now(), resolvida_por = 'sistema:diagnostico'
              where id = v_pendencia_id;
          end if;
          if v_pendencia_grupo_id is null then
            insert into pendencia (caso_id, origem_estagio, tipo, severidade, sobrepujavel, descricao, documento_id, entidade_id, motivo)
              values (v_caso_id, 'diagnostico', 'entidade_incorreta', 'importante', true,
                format('O documento está registrado em "%s", mas o diagnóstico de conteúdo aponta "%s" — que já é '
                       || 'uma empresa CADASTRADA neste mandato ("%s"). Isto não é erro de registro: são duas '
                       || 'empresas distintas do mesmo grupo (holding × subsidiária, ou duas do grupo), e nenhuma '
                       || 'das duas é presumida a certa aqui. Confira pela revisão do documento se ele pertence '
                       || 'mesmo a "%s" ou deveria estar em "%s" — sem fundir: as duas continuam sendo empresas '
                       || 'diferentes.',
                       coalesce(v_entidade_atual_nome, '(nenhuma)'), p_entidade_nome, v_outra_entidade_nome,
                       coalesce(v_entidade_atual_nome, '(nenhuma)'), v_outra_entidade_nome),
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
    E'  v_outra_entidade_id   uuid;\n' ||
    E'  v_outra_entidade_nome text;');

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
  '0160: quando a entidade não casa, mas o nome diagnosticado é OUTRA empresa já cadastrada no '
  'mesmo caso, a divergência é hierarquia (holding × subsidiária) e não erro — a pendência para '
  'de chamar de "incorreto" um registro correto, sem decidir de quem é o documento nem fundir as '
  'duas entidades.';

grant execute on function fn_registrar_diagnostico(uuid, uuid, text, boolean, text, text, text, legibilidade, text, text, text) to authenticated;

-- =============================================================================
-- SONDA
-- =============================================================================
insert into instalacao_requisito
  (chave, migration, tipo, objeto, marcador, criterio_seed, porque, severidade, ordem) values
  ('entidade_hierarquia_nao_e_erro', '0160', 'corpo', 'fn_registrar_diagnostico', '0160', null,
   'Medido no lote 7377 (02/09): `33_Notas_Explicativas` registrado em GRUPO CANASTRA, diagnóstico '
   'aponta Canastra Indústria — as duas são empresas REAIS e distintas do mesmo mandato, e a '
   'pendência `entidade_incorreta` chamava isso de erro sem saber que "Canastra Indústria" já era '
   'uma entidade cadastrada no caso. `fn_mesma_entidade(''GRUPO CANASTRA'', ''CANASTRA INDÚSTRIA DE '
   'EMBALAGENS LTDA.'') = false`: a 0153 (ambiguidade em fn_upsert_entidade) não cobre este caso — é '
   'função diferente, e os dois nomes não casam entre si.',
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
                    'casam — se o nome diagnosticado já é OUTRA empresa cadastrada no mesmo caso, '
                    'é hierarquia legítima (holding × subsidiária), não erro. Medido no lote 7377: '
                    'GRUPO CANASTRA × Canastra Indústria, achado que é anterior à 0153 e que ela '
                    'não cobre (função diferente, nomes que não casam entre si). Patch por ÂNCORA '
                    'sobre o corpo VIGENTE de fn_registrar_diagnostico (não reemissão), para não '
                    'regredir o patch da 0142 em silêncio — a lição desta própria migration, ver '
                    'cabeçalho.'
 where id;
