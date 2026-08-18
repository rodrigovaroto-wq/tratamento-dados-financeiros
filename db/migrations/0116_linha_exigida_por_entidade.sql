-- =============================================================================
-- Migration 0116 — A linha exigida passa a ser cobrada POR ENTIDADE
--
-- O CASO QUE MOTIVA (apontado pelo dono na revisão da 0113): um grupo econômico
-- com OITO balanços no caso, sete sem a linha de caixa e um com. A 0113
-- pergunta "algum documento do tipo tem a linha?" — o oitavo balanço responde
-- sim, e as sete ausências somem. Para mandato de grupo, que é o produto, isso
-- é a diferença entre pegar o problema e não pegar. A granularidade v1 estava
-- declarada como limitação no cabeçalho da 0113; esta migration é a evolução.
--
-- A PERGUNTA MUDA DE SUJEITO: de "o TIPO no caso tem a linha?" para "CADA
-- ENTIDADE que trouxe linhas desse tipo tem a linha NELA?". Oito balanços,
-- sete sem caixa: sete pendências, cada uma nomeando a entidade — e a oitava
-- limpa.
--
-- DE ONDE VEM O EIXO DE ENTIDADE — nada inventado, três peças que já existem:
--   • a entidade de uma linha é `coalesce(ce.entidade_coluna, e.razao_social)`
--     — o padrão da 0105: a coluna de entidade do campo (COMBINADO, um
--     documento com 8–9 colunas de empresa) com fallback na entidade do
--     documento (BALANCO, um documento por empresa);
--   • o eixo é o REGISTRO de entidades do caso (tabela `entidade`, que a 0030
--     já popula de forma canônica via fn_upsert_entidade);
--   • o casamento nome→entidade usa `fn_mesma_entidade` (0030) — o mesmo
--     critério do portal —, resolvido UMA vez por nome distinto e devolvido
--     por join (lição de custo da 0101).
--
-- DOIS FALLBACKS DELIBERADOS (doutrina da 0100: guarda que acusa à toa é
-- guarda que se aprende a ignorar):
--   1. linha cujo nome de entidade não casa com NENHUMA entidade registrada
--      não é atribuída a ninguém — ela conta para o escopo-caso, nunca para
--      uma entidade específica. Não inventamos entidade a partir de rótulo de
--      coluna sujo; errar aqui é errar para o lado de NÃO acusar.
--   2. tipo sem nenhuma linha atribuível a entidade (caso mono-entidade mal
--      rotulado, fixture antiga): cai no comportamento da 0113 — por tipo no
--      caso. Granularidade fina não pode virar máquina de pendência falsa em
--      caso que nem tem grupo.
--
-- O ESCOPO É DERIVADO, E A ALAVANCA É DO DONO. Nem todo tipo tem eixo de
-- entidade, e a taxonomia JÁ diz qual tem: `granularidade` é
-- 'entidade_periodo'/'entidade' (BALANCO, DRE, FATURAMENTO_24M...) ou
-- 'caso'/'periodo' (MUTUOS, FAT_INTRAGRUPO, COMBINADO). O default segue esse
-- fato: granularidade de entidade → cobra por entidade; caso/período → como
-- hoje. A coluna nova `escopo_entidade` (nullable) é o override POR EXIGÊNCIA,
-- e nasce NULL — mesmo padrão de severidade/sobrepujavel da 0113: a migration
-- não decide política. O caso que JUSTIFICA a alavanca existir é o COMBINADO:
-- granularidade 'periodo', mas as linhas têm `entidade_coluna` — cobrar caixa
-- por coluna de empresa ali é desejável, e é o dono quem liga
-- (`update taxonomia_linha_exigida set escopo_entidade = true where ...`).
--
-- AS PENDÊNCIAS QUE JÁ EXISTEM: transição pelo mecanismo que já está lá. O
-- passo 2b resolve pendência cujo motivo saiu da lista corrente; como o motivo
-- ganha o sufixo de entidade, no PRIMEIRO recomputo de cada caso a pendência
-- de formato velho (`...:BALANCO:caixa_e_equivalentes`) é resolvida e as novas
-- nascem por entidade, no mesmo ato — nada fica órfão, a trilha guarda as duas
-- gerações. Recomputo só roda quando chega extração ou revisão, então caso
-- PARADO ficaria no formato velho indefinidamente — é para isso que existe a
-- VARREDURA no fim do arquivo (bloco isolado, idempotente, removível; ver o
-- comentário dele).
--
-- O QUE NÃO MUDA: a exigência continua sendo DO TIPO (`taxonomia_linha_exigida`
-- não ganha linha nova por entidade); os localizadores, o seed, a política
-- NULL e o peso default (importante, sobrepujável) são os da 0113;
-- `pronto_para_revisao` segue intocado. `pendencia.entidade_id` existe desde a
-- 0001 e a 0009 já o preenche nas reconciliações — aqui ele passa a ser
-- preenchido também pela completude.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- A alavanca do dono: override de escopo POR EXIGÊNCIA. NULL = segue a
-- granularidade da taxonomia (o fato). true força por entidade (o caso
-- COMBINADO acima); false força por caso.
-- -----------------------------------------------------------------------------
alter table taxonomia_linha_exigida
  add column if not exists escopo_entidade boolean;

comment on column taxonomia_linha_exigida.escopo_entidade is
  'DECISÃO DO DONO, por exigência. NULL (default do seed) = o escopo segue a granularidade do '
  'tipo na taxonomia: entidade/entidade_periodo cobram POR ENTIDADE, caso/periodo cobram por '
  'caso. true força por entidade (ex.: COMBINADO, granularidade periodo mas linhas com '
  'entidade_coluna); false força por caso. Mesmo padrão de severidade/sobrepujavel (0113): '
  'a migration não define política.';

-- -----------------------------------------------------------------------------
-- fn_exigencias_do_caso — reemitida com o eixo de entidade no retorno.
--
-- O retorno muda de forma (duas colunas novas: entidade, entidade_id), então a
-- assinatura antiga é DERRUBADA antes — duas funções respondendo "o que falta
-- neste caso" com granularidades diferentes é exatamente o defeito que a 0100
-- matou para o papel da linha. Nenhum chamador fora do banco existe ainda
-- (conferido: portal e n8n não a citam).
--
-- Escopo por ENTIDADE: uma linha de resultado por (exigência × entidade do
-- eixo), com a entidade nomeada. Escopo por CASO (ou fallback de eixo vazio):
-- uma linha com entidade NULL — o comportamento da 0113, byte a byte.
-- -----------------------------------------------------------------------------
drop function if exists fn_exigencias_do_caso(uuid);

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
  with tipos_com_conteudo as (
    select distinct d.tipo_taxonomia
    from documento d
    where d.caso_id = p_caso_id
      and fn_linhas_do_tipo(p_caso_id, d.tipo_taxonomia) > 0
  ),
  campos as (
    select d.tipo_taxonomia,
           ce.chave, ce.secao, ce.secao_canonica,
           coalesce(ce.entidade_coluna, ent.razao_social) as ent_txt
    from documento d
    left join entidade ent on ent.id = d.entidade_id
    join campo_extraido ce on ce.documento_versao_id = fn_versao_com_extracao(d.id)
    where d.caso_id = p_caso_id
      and ce.valor_num is not null
  ),
  -- O NOME vira ENTIDADE REGISTRADA uma vez por nome DISTINTO (lição da 0101:
  -- fn_mesma_entidade custa; pagar por ocorrência seria pagar 770 vezes por
  -- ~10 respostas). Nome que não casa com registro nenhum fica NULL — fallback
  -- deliberado nº 1 do cabeçalho.
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
  -- (mesma lição): fn_normalizar_texto por (rótulo × termo) é o custo, e o
  -- caso real tem ~250 rótulos distintos para ~770 ocorrências.
  linhas_distintas as (
    select distinct c.tipo_taxonomia, c.chave, c.secao, c.secao_canonica from campos c
  ),
  casadas as (
    select e.id as exigencia_id, ld.tipo_taxonomia, ld.chave, ld.secao, ld.secao_canonica
    from taxonomia_linha_exigida e
    join linhas_distintas ld on ld.tipo_taxonomia = e.tipo_taxonomia
    where e.ativo
      and case e.checagem
        when 'secao_presente' then ld.secao_canonica = e.secao_canonica
        when 'serie_mensal'   then fn_mes_do_rotulo(ld.chave) is not null
        else exists (
          select 1 from taxonomia_linha_localizador l
          where l.exigencia_id = e.id
            and case
              when l.contra = 'estrutural' then fn_rotulo_estrutural(ld.chave, l.termos_inclui)
              else
                not exists (
                  select 1 from unnest(l.termos_inclui) t
                  where fn_normalizar_texto(case when l.contra = 'secao'
                                            then coalesce(ld.secao, '') else ld.chave end)
                    not like '%' || fn_normalizar_texto(t) || '%')
                and not exists (
                  select 1 from unnest(l.termos_exclui) t
                  where fn_normalizar_texto(case when l.contra = 'secao'
                                            then coalesce(ld.secao, '') else ld.chave end)
                    like '%' || fn_normalizar_texto(t) || '%')
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
  ),
  -- O EIXO: entidades registradas que TROUXERAM linha do tipo. Quem tem
  -- documento mas nenhuma linha atribuível não entra — cobrar conteúdo de quem
  -- não tem conteúdo é assunto da 0036/0112, não daqui.
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
    -- com entidade NULL (escopo caso, ou fallback nº 2 do cabeçalho).
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
  'Exigências de linha aplicáveis ao caso, POR ENTIDADE quando o escopo pede (0116): uma linha de '
  'resultado por (exigência × entidade do eixo), entidade NULL no escopo-caso e nos fallbacks. '
  'Escopo = escopo_entidade da exigência, ou (NULL) a granularidade do tipo na taxonomia. Eixo = '
  'entidades REGISTRADAS que trouxeram linha do tipo, via coalesce(entidade_coluna, razao_social) '
  '+ fn_mesma_entidade (0030/0105), resolvido uma vez por nome (0101). Casa contra a versão '
  'VIGENTE (0102), no formato de fn_valor_conceito (0009).';

grant execute on function fn_exigencias_do_caso(uuid) to authenticated;

-- -----------------------------------------------------------------------------
-- fn_recomputar_completude — corpo da 0113 com o passo (2b) POR ENTIDADE.
-- Reemitida inteira (padrão do repositório). Passos (1), (2), (3), (4): 0036,
-- intactos. Mudou SÓ o (2b): motivo com sufixo de entidade, entidade_id na
-- pendência, descrição nomeando a entidade.
-- -----------------------------------------------------------------------------
create or replace function fn_recomputar_completude(p_caso_id uuid)
returns jsonb
language plpgsql
as $$
declare
  v_faltantes text[];
  v_sem_conteudo text[];
  v_cod text;
  v_nao_sobre boolean;
  v_status_atual caso_status;
  v_novo_status caso_status;
  v_pend_id uuid;
  -- 0113/0116: passo (2b)
  v_ex record;
  v_motivo text;
  v_motivos_ausentes text[] := '{}';
  v_linhas_ausentes jsonb := '[]'::jsonb;
begin
  -- ----- (1) obrigatório sem NENHUM documento: igual à 0006 ------------------
  select array_agg(t.codigo order by t.codigo) into v_faltantes
  from taxonomia_tipo_documento t
  where t.obrigatoriedade = 'obrigatorio'
    and not exists (
      select 1 from documento d
      where d.caso_id = p_caso_id and d.tipo_taxonomia = t.codigo
    );
  v_faltantes := coalesce(v_faltantes, array[]::text[]);

  update pendencia p set estado = 'resolvida', resolvida_em = now(), resolvida_por = 'sistema:n8n'
  where p.caso_id = p_caso_id and p.tipo = 'item_faltante' and p.estado <> 'resolvida'
    and not (p.descricao = any (select 'Item obrigatório do Kit Básico ausente: '||x from unnest(v_faltantes) x));

  foreach v_cod in array v_faltantes loop
    select nao_sobrepujavel into v_nao_sobre from taxonomia_tipo_documento where codigo = v_cod;
    if not exists (
      select 1 from pendencia p
      where p.caso_id = p_caso_id and p.tipo = 'item_faltante'
        and p.estado <> 'resolvida'
        and p.descricao = 'Item obrigatório do Kit Básico ausente: '||v_cod
    ) then
      insert into pendencia (caso_id, origem_estagio, tipo, severidade, sobrepujavel, descricao)
        values (p_caso_id, 'completude', 'item_faltante', 'bloqueante',
                not coalesce(v_nao_sobre,false),
                'Item obrigatório do Kit Básico ausente: '||v_cod);
    end if;
  end loop;

  -- ----- (2) obrigatório PRESENTE mas sem uma linha aproveitável (0036) ------
  select array_agg(t.codigo order by t.codigo) into v_sem_conteudo
  from taxonomia_tipo_documento t
  where t.obrigatoriedade = 'obrigatorio'
    and exists (
      select 1 from documento d
      where d.caso_id = p_caso_id and d.tipo_taxonomia = t.codigo
    )
    and fn_linhas_do_tipo(p_caso_id, t.codigo) = 0;
  v_sem_conteudo := coalesce(v_sem_conteudo, array[]::text[]);

  update pendencia p set estado = 'resolvida', resolvida_em = now(), resolvida_por = 'sistema:extracao'
  where p.caso_id = p_caso_id and p.tipo = 'item_sem_conteudo' and p.estado <> 'resolvida'
    and not (p.motivo = any (select 'completude:sem_conteudo:'||x from unnest(v_sem_conteudo) x));

  foreach v_cod in array v_sem_conteudo loop
    if not exists (
      select 1 from pendencia p
      where p.caso_id = p_caso_id and p.tipo = 'item_sem_conteudo'
        and p.estado <> 'resolvida' and p.motivo = 'completude:sem_conteudo:'||v_cod
    ) then
      insert into pendencia (caso_id, origem_estagio, tipo, severidade, sobrepujavel, descricao, motivo)
        values (p_caso_id, 'completude', 'item_sem_conteudo', 'bloqueante', false,
                format('Item obrigatório "%s" foi RECEBIDO, mas nenhuma linha foi extraída de nenhuma '
                       'versão dele: o documento existe e o book sai VAZIO nesta parte. Causas comuns: '
                       'formato que o pipeline ainda não converte (.xlsx/.docx), arquivo ilegível, ou '
                       'chamada de extração que falhou. Conferir o arquivo e reenviar — completude não '
                       'é validade (docs/07), e um obrigatório sem conteúdo não passa o Portão 2.',
                       v_cod),
                'completude:sem_conteudo:'||v_cod);
    end if;
  end loop;

  -- ----- (2b) 0113/0116: tipo COM conteúdo, mas sem uma LINHA exigida --------
  -- 0116: a cobrança desce ao nível da ENTIDADE quando o escopo pede. O motivo
  -- ganha o sufixo canônico da entidade (chave estável mesmo que a grafia da
  -- razão social varie entre extrações), `entidade_id` vai na pendência, e a
  -- descrição nomeia a empresa. Pendência de formato velho (sem sufixo) sai da
  -- lista corrente e é resolvida no fim do bloco — é a transição, e a trilha
  -- guarda as duas gerações.
  for v_ex in
    select * from fn_exigencias_do_caso(p_caso_id) x where not x.satisfeita
  loop
    v_motivo := 'completude:linha_exigida:' || v_ex.tipo_taxonomia || ':' || v_ex.conceito
                || case when v_ex.entidade is not null
                        then ':' || fn_entidade_canonica(v_ex.entidade)
                        else '' end;
    v_motivos_ausentes := v_motivos_ausentes || v_motivo;
    v_linhas_ausentes := v_linhas_ausentes || jsonb_build_object(
      'tipo', v_ex.tipo_taxonomia, 'conceito', v_ex.conceito,
      'rotulo', v_ex.rotulo, 'origem', v_ex.origem,
      'entidade', v_ex.entidade);

    select id into v_pend_id from pendencia p
    where p.caso_id = p_caso_id and p.tipo = 'linha_exigida_ausente'
      and p.estado <> 'resolvida'
      and p.motivo = v_motivo
    limit 1;

    if v_pend_id is null then
      insert into pendencia (caso_id, origem_estagio, tipo, severidade, sobrepujavel,
                             descricao, entidade_id, motivo)
        values (p_caso_id, 'completude', 'linha_exigida_ausente',
                coalesce(v_ex.severidade, 'importante')::pendencia_severidade,
                coalesce(v_ex.sobrepujavel, true),
                case when v_ex.entidade is not null then
                  format('Nos documentos de %s da entidade "%s", a linha exigida "%s" não foi '
                         'localizada na versão vigente. Sem ela, PARA ESTA ENTIDADE: %s.%s Conferir '
                         'se o documento dela traz a linha com outro rótulo (e corrigir na revisão) '
                         'ou reenviar o arquivo completo.',
                         v_ex.tipo_taxonomia, v_ex.entidade, v_ex.rotulo,
                         array_to_string(v_ex.depende_de, '; '),
                         case when v_ex.origem = 'proposta'
                              then ' (Exigência PROPOSTA na análise — nenhuma checagem automática a lê hoje.)'
                              else '' end)
                else
                  format('O tipo %s chegou e rendeu linhas, mas a linha exigida "%s" não foi '
                         'localizada na versão vigente de nenhum documento do tipo. Sem ela: %s.%s '
                         'Conferir se o documento traz a linha com outro rótulo (e corrigir na '
                         'revisão) ou reenviar o arquivo completo.',
                         v_ex.tipo_taxonomia, v_ex.rotulo,
                         array_to_string(v_ex.depende_de, '; '),
                         case when v_ex.origem = 'proposta'
                              then ' (Exigência PROPOSTA na análise — nenhuma checagem automática a lê hoje.)'
                              else '' end)
                end,
                v_ex.entidade_id,
                v_motivo);
    else
      update pendencia set
        severidade   = coalesce(v_ex.severidade, 'importante')::pendencia_severidade,
        sobrepujavel = coalesce(v_ex.sobrepujavel, true)
      where id = v_pend_id;
    end if;
  end loop;

  -- A linha apareceu, a exigência foi desativada, ou o formato do motivo mudou
  -- (a transição 0113 → 0116): resolve sozinha, como as da 0036.
  update pendencia p set estado = 'resolvida', resolvida_em = now(), resolvida_por = 'sistema:extracao'
  where p.caso_id = p_caso_id and p.tipo = 'linha_exigida_ausente' and p.estado <> 'resolvida'
    and not (p.motivo = any (v_motivos_ausentes));

  -- ----- (3) o checklist reflete os três estados (0036) ----------------------
  update checklist_item_status c
    set status = case
                   when fn_linhas_do_tipo(p_caso_id, c.tipo_taxonomia) = 0 then 'recebido_nao_valido'
                   else 'presente'
                 end,
        atualizado_em = now()
  where c.caso_id = p_caso_id
    and c.documento_id is not null
    and c.status in ('presente', 'recebido_nao_valido');

  -- ----- (4) status do caso: Portão 1 continua sendo CHEGADA (0036) ----------
  select status into v_status_atual from caso where id = p_caso_id;
  if array_length(v_faltantes,1) is null then
    v_novo_status := 'completude_ok';
  else
    v_novo_status := 'em_triagem';
  end if;

  if v_status_atual in ('intake','em_triagem','completude_ok') and v_novo_status <> v_status_atual then
    update caso set status = v_novo_status where id = p_caso_id;
    insert into evento_auditoria (ator, acao, entidade_ref, antes, depois)
      values ('sistema:n8n', 'transicao_status', 'caso:'||p_caso_id,
              jsonb_build_object('status', v_status_atual),
              jsonb_build_object('status', v_novo_status));
  end if;

  return jsonb_build_object(
    'portao1_ok', array_length(v_faltantes,1) is null,
    'faltantes', to_jsonb(v_faltantes),
    'sem_conteudo', to_jsonb(v_sem_conteudo),
    -- 0116: cada ausência agora pode nomear a entidade. `pronto_para_revisao`
    -- segue intocado — endurecê-lo é decisão de produto do dono, não efeito
    -- colateral (0113).
    'linhas_exigidas_ausentes', v_linhas_ausentes,
    'pronto_para_revisao',
      array_length(v_faltantes,1) is null and array_length(v_sem_conteudo,1) is null,
    'status', v_novo_status
  );
end;
$$;

comment on function fn_recomputar_completude(uuid) is
  'Portão 1 (chegada) + 0036 (recebido sem conteúdo) + 0113/0116 (passo 2b: linha exigida ausente, '
  'cobrada POR ENTIDADE quando o escopo pede — motivo com sufixo canônico da entidade, entidade_id '
  'na pendência, descrição nomeando a empresa). Política por linha é do dono; default = '
  'importante/sobrepujável. `portao1_ok` segue "chegou tudo"; `pronto_para_revisao` segue "chegou '
  'tudo E tem conteúdo".';

-- -----------------------------------------------------------------------------
-- VERIFICAÇÃO EMBUTIDA (padrão 0105). Pode tocar em `pendencia` sem risco: o
-- valor `linha_exigida_ausente` existe desde a 0113, já commitado.
-- O cenário fino (8 balanços, COMBINADO, transição, guarda de termos) está em
-- db/test/linha_exigida_entidade.test.sql.
-- -----------------------------------------------------------------------------
do $$
declare
  v_caso uuid := gen_random_uuid();
  v_ent_a uuid := gen_random_uuid();
  v_ent_b uuid := gen_random_uuid();
  v_doc_a uuid := gen_random_uuid();
  v_doc_b uuid := gen_random_uuid();
  v_ver_a uuid := gen_random_uuid();
  v_ver_b uuid := gen_random_uuid();
  v_n int;
  v_ent uuid;
begin
  -- A alavanca nasce NULL em todo o seed: política é do dono.
  select count(*) into v_n from taxonomia_linha_exigida where escopo_entidade is not null;
  if v_n <> 0 then
    raise exception '0116: % exigência(s) com escopo_entidade definido no seed — a alavanca é do dono, nasce NULL', v_n;
  end if;

  -- Dois balanços, A com caixa e B sem: cobra SÓ a entidade B, nomeando-a.
  insert into caso (id, nome, produto) values (v_caso, 'VERIF 0116', 'reestruturacao');
  insert into entidade (id, caso_id, razao_social) values
    (v_ent_a, v_caso, 'Alfa Participações Ltda.'),
    (v_ent_b, v_caso, 'Beta Logística S.A.');
  insert into documento (id, caso_id, entidade_id, tipo_taxonomia, status, confianca, fonte) values
    (v_doc_a, v_caso, v_ent_a, 'BALANCO', 'valido', 0.9, 'verificacao'),
    (v_doc_b, v_caso, v_ent_b, 'BALANCO', 'valido', 0.9, 'verificacao');
  insert into documento_versao (id, documento_id, n_versao, arquivo_ref, nome_original, hash) values
    (v_ver_a, v_doc_a, 1, 'x', 'BP-Alfa.pdf', md5(v_ver_a::text)),
    (v_ver_b, v_doc_b, 1, 'x', 'BP-Beta.pdf', md5(v_ver_b::text));
  insert into campo_extraido (documento_versao_id, chave, valor_num, confianca) values
    (v_ver_a, 'TOTAL DO ATIVO',                           1000, 0.9),
    (v_ver_a, 'TOTAL DO PASSIVO E DO PATRIMONIO LIQUIDO', 1000, 0.9),
    (v_ver_a, 'Caixa e equivalentes de caixa',             120, 0.9),
    (v_ver_b, 'TOTAL DO ATIVO',                            500, 0.9),
    (v_ver_b, 'TOTAL DO PASSIVO E DO PATRIMONIO LIQUIDO',  500, 0.9),
    (v_ver_b, 'Estoques',                                  500, 0.9);

  perform fn_recomputar_completude(v_caso);

  select count(*) into v_n from pendencia
   where caso_id = v_caso and tipo = 'linha_exigida_ausente' and estado <> 'resolvida'
     and motivo like 'completude:linha_exigida:BALANCO:caixa_e_equivalentes:%';
  select entidade_id into v_ent from pendencia
   where caso_id = v_caso and tipo = 'linha_exigida_ausente' and estado <> 'resolvida'
     and motivo like 'completude:linha_exigida:BALANCO:caixa_e_equivalentes:%'
   limit 1;
  if v_n <> 1 or v_ent <> v_ent_b then
    raise exception '0116: dois balanços (A com caixa, B sem) deviam abrir UMA pendência para B — achou % (entidade %)', v_n, v_ent;
  end if;
  select count(*) into v_n from pendencia
   where caso_id = v_caso and tipo = 'linha_exigida_ausente' and estado <> 'resolvida'
     and entidade_id = v_ent_a;
  if v_n <> 0 then
    raise exception '0116: a entidade COM a linha foi cobrada (% pendência/s) — o eixo por entidade está errado', v_n;
  end if;

  delete from caso where id = v_caso;
  raise notice '0116 OK — escopo_entidade nasce NULL; A com caixa e B sem ⇒ só B cobrada, com entidade_id';
end $$;

-- =============================================================================
-- VARREDURA ÚNICA DOS CASOS EXISTENTES — bloco ISOLADO, de propósito.
--
-- O QUE FAZ: chama fn_recomputar_completude uma vez para cada caso já gravado,
-- para que as pendências `linha_exigida_ausente` de formato velho (por tipo)
-- sejam resolvidas e as novas (por entidade) nasçam agora — e não só quando a
-- próxima extração ou revisão tocar o caso. É a doutrina da 0043: reaplicar as
-- regras de hoje sobre o dado que já está no banco.
--
-- É IDEMPOTENTE (recomputar é o que o pipeline já faz a cada extração) e SÓ
-- mexe em pendência derivada + checklist — nenhum campo extraído, nenhuma
-- decisão, nenhum aceite. É a ÚNICA parte desta migration que toca casos
-- existentes: todo o resto define estrutura e função. Se preferir aplicar a
-- migration sem a varredura e rodá-la à parte (ou caso a caso), REMOVA este
-- bloco antes de aplicar — a migration fica completa sem ele; os casos
-- migram de formato no próximo recomputo natural de cada um.
-- =============================================================================
do $$
declare
  v_caso record;
  v_n int := 0;
begin
  for v_caso in select id from caso loop
    perform fn_recomputar_completude(v_caso.id);
    v_n := v_n + 1;
  end loop;
  raise notice '0116: varredura recomputou a completude de % caso(s) existente(s)', v_n;
end $$;
