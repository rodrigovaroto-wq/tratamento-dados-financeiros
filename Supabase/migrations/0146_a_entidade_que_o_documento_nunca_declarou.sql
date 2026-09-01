-- 0146 — NUM DOCUMENTO DE VÁRIAS EMPRESAS, A LINHA SEM COLUNA NÃO É DA CAPA.
--
-- ACHADO NA RODADA v48. Três das 27 pendências cobravam de "GRUPO CANASTRA" as
-- linhas de um balanço patrimonial:
--
--   Nos documentos de BALANCO da entidade "GRUPO CANASTRA", a linha exigida
--   "Ativo Total" não foi localizada na versão vigente.
--   … idem "Caixa e equivalentes (BP)" e "Passivo + Patrimônio Líquido (total)".
--
-- GRUPO CANASTRA NÃO É UMA EMPRESA. É o nome do grupo, e grupo não levanta
-- balanço — as seis operadoras levantam, e o combinado é a soma delas menos as
-- eliminações. Cobrar "Ativo Total do GRUPO CANASTRA" é pedir uma demonstração
-- que não existe e não vai existir; o analista não tem o que fazer com isso.
--
-- DE ONDE VEIO A ENTIDADE FANTASMA. Medido: os documentos 13 e 14 (os balanços
-- COMBINADOS) declaram OITO colunas de entidade — as seis operadoras, mais
-- "Eliminações", mais "Combinado" — e trazem 58 linhas atribuídas a uma coluna e
-- **7 sem coluna nenhuma** (cabeçalhos de seção e totais que atravessam a
-- matriz). Para essas 7, `fn_exigencias_do_caso` caía no fallback
-- `coalesce(ce.entidade_coluna, ent_doc)` e usava a entidade da CAPA do
-- documento, que é "GRUPO CANASTRA". Sete linhas bastaram para inscrever o grupo
-- no eixo de entidades que devem um balanço.
--
-- O FALLBACK NÃO ESTÁ ERRADO — ESTÁ FORA DE LUGAR. Num balanço de UMA empresa,
-- nenhuma linha traz coluna de entidade (não há por quê), e usar a capa é
-- exatamente certo: é a única fonte da informação. Num documento que declara
-- VÁRIAS, a capa não é fonte de nada — o documento já disse de quem é cada
-- número, coluna por coluna, e uma linha sem coluna é ou um cabeçalho que
-- atravessa todas, ou uma célula cuja coluna a extração perdeu. Nos dois casos,
-- atribuí-la à capa INVENTA uma atribuição que o documento nunca fez.
--
-- O CRITÉRIO É ESTRUTURAL, e não uma lista de nomes de grupo. Rótulo mente:
-- "GRUPO CANASTRA" é holding em um caso e razão social em outro, e uma lista de
-- palavras ("grupo", "holding") erraria nos dois sentidos. O que não mente é a
-- forma do documento: quantas colunas de entidade ele declara. Medido no caso
-- real da v48 — dos 38 documentos, exatamente DOIS declaram mais de uma, e são
-- precisamente os dois balanços combinados. O critério não encosta em mais nada.
--
-- MEDIDO ANTES DE APLICAR: com a regra nova, GRUPO CANASTRA sai do eixo de
-- BALANCO e de COMBINADO — e CONTINUA no de MUTUOS, SITUACAO_FISCAL e
-- FAT_INTRAGRUPO, que são documentos de UMA coluna e genuinamente do grupo. Não é
-- silenciar a entidade: é deixar de atribuir a ela o que o documento não atribuiu.
--
-- REEMISSÃO INTEIRA pela mesma razão da 0145, que reemitiu esta função uma
-- migration atrás: o corpo é o arquivo que alguém lê para entendê-la, e o que
-- muda são duas linhas (a coluna `multi_entidade` em `docs` e o `case` em
-- `campos`). As decisões de custo da 0119 seguem comentadas e intactas.

create or replace function fn_exigencias_do_caso(p_caso_id uuid)
returns table (
  exigencia_id   uuid,
  tipo_taxonomia text,
  conceito       text,
  rotulo         text,
  origem         text,
  depende_de     text[],
  severidade     text,
  sobrepujavel   boolean,
  descricao      text,
  entidade       text,
  entidade_id    uuid,
  satisfeita     boolean
)
language sql
stable
as $$
  -- UMA CHAMADA POR TIPO, E NÃO POR DOCUMENTO — e o `materialized` é a metade
  -- que faz a diferença existir. A forma herdada da 0113 rodava
  -- `fn_linhas_do_tipo` uma vez por DOCUMENTO (662 ms de 914 num caso de 400
  -- documentos), e separar em duas CTEs simples não mudou nada, porque o
  -- Postgres achata CTE e empurra o filtro de volta para baixo do agrupamento.
  -- É a palavra `materialized` que impede isso; sem ela este comentário estaria
  -- descrevendo uma otimização que não acontece.
  with tipos_do_caso as materialized (
    select distinct d.tipo_taxonomia from documento d where d.caso_id = p_caso_id
  ),
  tipos_com_conteudo as (
    select t.tipo_taxonomia from tipos_do_caso t
    where fn_linhas_do_tipo(p_caso_id, t.tipo_taxonomia) > 0
  ),
  -- A VERSÃO VIGENTE DE CADA DOCUMENTO, resolvida UMA vez (lição de custo da
  -- 0101), e — 0146 — QUANTAS COLUNAS DE ENTIDADE o documento declara.
  --
  -- É esse número que decide se a capa do documento pode responder pela linha
  -- que não tem coluna. Uma coluna (ou nenhuma): o documento é de uma empresa e
  -- a capa é a única fonte. Mais de uma: o documento já disse de quem é cada
  -- número, e a capa não responde por ninguém.
  docs as (
    select d.id, d.tipo_taxonomia, ent.razao_social as ent_doc,
           v.versao,
           (select count(distinct ce.entidade_coluna) from campo_extraido ce
             where ce.documento_versao_id = v.versao and ce.valor_num is not null) > 1
             as multi_entidade
    from documento d
    left join entidade ent on ent.id = d.entidade_id
    cross join lateral (select fn_versao_com_extracao(d.id) as versao) v
    where d.caso_id = p_caso_id
  ),
  campos as (
    select dc.tipo_taxonomia,
           ce.chave, ce.secao, ce.secao_canonica,
           -- 0145: o outro eixo da matriz.
           ce.periodo_coluna as coluna,
           -- 0146: a capa só responde pela linha sem coluna quando o documento é
           -- de UMA empresa. Num documento de várias, a linha sem coluna fica sem
           -- entidade — ela vale para o caso, não para a capa.
           case when dc.multi_entidade then ce.entidade_coluna
                else coalesce(ce.entidade_coluna, dc.ent_doc) end as ent_txt
    from docs dc
    join campo_extraido ce on ce.documento_versao_id = dc.versao
    where ce.valor_num is not null
  ),
  -- O NOME vira ENTIDADE REGISTRADA uma vez por nome DISTINTO (lição da 0101:
  -- fn_mesma_entidade custa; pagar por ocorrência seria pagar 770 vezes por
  -- ~10 respostas). Nome que não casa com registro nenhum fica NULL.
  nomes_resolvidos as (
    select n.ent_txt,
           (select e.id from entidade e
             where e.caso_id = p_caso_id
               and fn_mesma_entidade(n.ent_txt, e.razao_social)
             order by e.razao_social, e.id limit 1) as entidade_id
    from (select distinct c.ent_txt from campos c where c.ent_txt is not null) n
  ),
  campos_ent as (
    select c.*, nr.entidade_id
    from campos c
    left join nomes_resolvidos nr on nr.ent_txt = c.ent_txt
  ),
  -- O CASAMENTO exigência × rótulo é avaliado uma vez por LINHA DISTINTA
  -- (mesma lição): fn_normalizar_texto por (rótulo × termo) é o custo.
  linhas_distintas as (
    select distinct c.tipo_taxonomia, c.chave, c.secao, c.secao_canonica, c.coluna
    from campos c
  ),
  casadas as (
    select e.id as exigencia_id, ld.tipo_taxonomia, ld.chave, ld.secao,
           ld.secao_canonica, ld.coluna
    from taxonomia_linha_exigida e
    join linhas_distintas ld on ld.tipo_taxonomia = e.tipo_taxonomia
    where e.ativo
      and case e.checagem
        when 'secao_presente' then ld.secao_canonica = e.secao_canonica
        when 'serie_mensal'   then fn_mes_do_rotulo(ld.chave) is not null
        else exists (
          select 1 from taxonomia_linha_localizador l
          -- O ALVO do casamento, escolhido pelo modo (0145).
          cross join lateral (select fn_normalizar_texto(
            case l.contra
              when 'secao'  then coalesce(ld.secao, '')
              when 'coluna' then coalesce(ld.coluna, '')
              else ld.chave
            end) as alvo) a
          where l.exigencia_id = e.id
            and case
              when l.contra = 'estrutural' then fn_rotulo_estrutural(ld.chave, l.termos_inclui)
              else
                not exists (
                  select 1 from unnest(l.termos_inclui) t
                  where a.alvo not like '%' || fn_normalizar_texto(t) || '%')
                and not exists (
                  select 1 from unnest(l.termos_exclui) t
                  where a.alvo like '%' || fn_normalizar_texto(t) || '%')
            end)
      end
  ),
  -- Quais (exigência, entidade) estão SATISFEITAS: a linha casada volta às
  -- ocorrências para saber DE QUEM ela é.
  satisfazedores as (
    select distinct ca.exigencia_id, c.entidade_id
    from casadas ca
    join campos_ent c
      on c.tipo_taxonomia = ca.tipo_taxonomia
     and c.chave = ca.chave
     and c.secao is not distinct from ca.secao
     and c.secao_canonica is not distinct from ca.secao_canonica
     and c.coluna is not distinct from ca.coluna
  ),
  -- O EIXO: entidades registradas que TROUXERAM linha do tipo. Quem tem
  -- documento mas nenhuma linha atribuível não entra — cobrar conteúdo de quem
  -- não tem conteúdo é assunto da 0036/0112, não daqui. E, desde a 0146, "linha
  -- atribuível" quer dizer atribuída PELO DOCUMENTO quando ele sabe atribuir.
  eixo as (
    select distinct c.tipo_taxonomia, c.entidade_id
    from campos_ent c
    where c.entidade_id is not null
  )
  select e.id, e.tipo_taxonomia, e.conceito, e.rotulo, e.origem, e.depende_de,
         e.severidade, e.sobrepujavel, e.descricao,
         ent.razao_social, ax.entidade_id,
         case when ax.entidade_id is null
              then exists (select 1 from satisfazedores s where s.exigencia_id = e.id)
              else exists (select 1 from satisfazedores s
                            where s.exigencia_id = e.id and s.entidade_id = ax.entidade_id)
         end as satisfeita
  from taxonomia_linha_exigida e
  join tipos_com_conteudo t on t.tipo_taxonomia = e.tipo_taxonomia
  join taxonomia_tipo_documento tx on tx.codigo = e.tipo_taxonomia
  cross join lateral (
    -- Escopo entidade COM eixo: uma linha por entidade. Senão: a linha única
    -- com entidade NULL (escopo caso, ou fallback nº 2 do cabeçalho da 0119).
    select x.entidade_id
    from eixo x
    where x.tipo_taxonomia = e.tipo_taxonomia
      and coalesce(e.escopo_entidade, tx.granularidade::text in ('entidade', 'entidade_periodo'))
    union all
    select null::uuid
    where not (coalesce(e.escopo_entidade, tx.granularidade::text in ('entidade', 'entidade_periodo'))
               and exists (select 1 from eixo x2 where x2.tipo_taxonomia = e.tipo_taxonomia))
  ) ax
  left join entidade ent on ent.id = ax.entidade_id
  where e.ativo;
$$;

comment on function fn_exigencias_do_caso(uuid) is
  'Exigências de linha aplicáveis ao caso (tipos presentes COM conteúdo), com satisfeita s/n. '
  'Casa contra a versão VIGENTE (0102), pela chave, pela seção, pela COLUNA (0145) ou pelo rótulo '
  'estrutural. Num documento que declara VÁRIAS colunas de entidade, a linha sem coluna não é '
  'atribuída à capa (0146) — é o que criava a entidade fantasma "GRUPO CANASTRA" devendo balanço. '
  'Alimenta o passo 2b de fn_recomputar_completude e a tela do caso.';

grant execute on function fn_exigencias_do_caso(uuid) to authenticated;
