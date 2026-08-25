-- 0145 — EM DOCUMENTO MATRICIAL O CONCEITO É A COLUNA, E O LOCALIZADOR SÓ SABIA
-- OLHAR PARA A LINHA.
--
-- ACHADO NA RODADA v48. Três das 27 pendências abertas eram
-- `linha_exigida_ausente` cobrando dados que ESTÃO no banco, extraídos, corretos,
-- conferidos contra o `GABARITO.json`:
--
--   • MAPA_DIVIDA / "Juros/encargos por contrato" — 14.802.000 no total;
--   • MUTUOS / "Saldo de mútuo por contraparte"   — 16.060;
--   • FAT_INTRAGRUPO / "Faturamento entre partes" — 10.940 só em 2025.
--
-- POR QUE O LOCALIZADOR NÃO ACHOU. Os três documentos são MATRICIAIS: a linha é a
-- entidade concreta (o contrato, o par de contrapartes, o par emitente→tomador) e
-- o conceito é a COLUNA. O mapa de dívida grava assim:
--
--     chave                                          periodo_coluna           valor_num
--     "Banco Meridional S.A. - Capital de giro (…)"  "Saldo devedor (R$)"      10.412.600
--     "Banco Meridional S.A. - Capital de giro (…)"  "Juros do exercício (R$)"  2.960.400
--
-- A palavra "juros" existe no documento e está gravada — em `periodo_coluna`. O
-- localizador tinha `contra` em três modos ('chave', 'secao', 'estrutural') e
-- nenhum deles olha para a coluna, então procurava "juros" na `chave`, que é o
-- nome do banco, e não achava.
--
-- ISSO NÃO É UMA FALHA DA EXTRAÇÃO — foi o que a conferência linha a linha da v48
-- estabeleceu, e vale repetir porque a pendência dizia o contrário. Ela mandava o
-- analista "conferir se o documento traz a linha com outro rótulo ou reenviar o
-- arquivo completo": abrir um PDF que está certo, procurar um defeito que não
-- existe, e no fim reenviar o mesmo arquivo. Três toques humanos, zero
-- informação. Pendência falsa cobra mais caro que pendência ausente, porque
-- queima a confiança na fila inteira.
--
-- E UMA DELAS TINHA CONSEQUÊNCIA REAL. `juros_por_contrato` alimenta a
-- reconciliação `despfin_dre_vs_divida` (0023) — a que confere a despesa
-- financeira da DRE contra os juros do mapa de dívida. Sem o localizador achar a
-- coluna, essa checagem ficava em `precondicao_nao_satisfeita`, que é a quarta
-- pendência da v48 com a mesma raiz ("DRE e Mapa de Dívida presentes, mas não foi
-- possível localizar … as linhas de juros do mapa"). O dado para conferir estava
-- ali o tempo todo.
--
-- O QUE MUDA: um quarto modo, `contra = 'coluna'`, que casa contra
-- `campo_extraido.periodo_coluna` — o cabeçalho da coluna, como o documento o
-- escreveu. É a mesma mecânica de inclui/exclui dos outros modos, no outro eixo
-- da matriz; nada de heurística nova.
--
-- E POR QUE `periodo_coluna` E NÃO UMA COLUNA NOVA. Porque é onde o dado JÁ ESTÁ.
-- A extração grava o cabeçalho da coluna ali desde sempre — em demonstração
-- comparativa ele é o período ("31/12/2025"), em documento matricial é o conceito
-- ("Juros do exercício (R$)"). Uma coluna nova exigiria reextrair os 38
-- documentos para preencher o que já está preenchido. "Uma conta, um lugar."
--
-- MEDIDO ANTES DE APLICAR, contra os dados reais da v48: os três localizadores
-- novos casam ("juros" em "Juros do exercício (R$)", "saldo" em "Saldo devedor",
-- "valor" em "Valor") e as três exigências passam a satisfeitas. Os localizadores
-- antigos, `contra = 'chave'`, FICAM: um mapa de dívida escrito por linha em vez
-- de por coluna continua sendo localizado por eles, e um `or` a mais não custa.

-- -----------------------------------------------------------------------------
-- (1) O modo novo passa a ser aceito pela tabela.
-- -----------------------------------------------------------------------------
alter table taxonomia_linha_localizador
  drop constraint if exists taxonomia_linha_localizador_contra_check;

alter table taxonomia_linha_localizador
  add constraint taxonomia_linha_localizador_contra_check
  check (contra in ('chave', 'secao', 'estrutural', 'coluna'));

comment on column taxonomia_linha_localizador.contra is
  '''chave'' = casa contra ce.chave (fn_valor_conceito); ''secao'' = contra ce.secao; '
  '''coluna'' = contra ce.periodo_coluna, o cabeçalho da coluna (0145 — em documento MATRICIAL '
  'o conceito é a coluna e a linha é a entidade concreta: no mapa de dívida a chave é o contrato '
  'e "Juros do exercício (R$)" é o cabeçalho); ''estrutural'' = fn_rotulo_estrutural.';

-- -----------------------------------------------------------------------------
-- (2) fn_exigencias_do_caso reemitida com o quarto modo.
--
-- REEMISSÃO INTEIRA porque o corpo vigente é o da 0119 e ele já é o arquivo que
-- alguém lê para entender a função; o que muda é `periodo_coluna` descendo por
-- três CTEs e um ramo no `case`. As decisões de CUSTO da 0119 (o `materialized`,
-- a versão resolvida uma vez, o casamento por linha distinta) estão comentadas no
-- corpo e ficam intactas — inclusive `linhas_distintas`, que ganha a coluna e com
-- ela alguma cardinalidade: num documento matricial as combinações distintas de
-- (chave, coluna) são as células, não o produto, e é o que o casamento precisa.
-- -----------------------------------------------------------------------------
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
  -- que faz a diferença existir.
  --
  -- A forma herdada da 0113 era `select distinct d.tipo_taxonomia from documento
  -- where fn_linhas_do_tipo(...) > 0`: o `distinct` roda DEPOIS do filtro, então
  -- a função — que por dentro varre `campo_extraido` e chama
  -- `fn_versao_com_extracao` — era executada uma vez para cada DOCUMENTO.
  --
  -- MEDIDO, num caso sintético de 400 documentos e 16 mil linhas: o
  -- `explain analyze` mostra 662 ms dos 914 ms totais nesse único filtro. E a
  -- primeira tentativa de conserto — separar em duas CTEs — não mudou NADA no
  -- relógio, porque o Postgres achata CTE simples e empurrou o filtro de volta
  -- para baixo do agrupamento, desfazendo a intenção. É por isso que a primeira
  -- CTE é `as materialized`: ela é a barreira que obriga o agrupamento a
  -- acontecer ANTES da pergunta cara. Sem a palavra, o comentário estaria
  -- descrevendo uma otimização que não acontece.
  --
  -- Agrupar antes de perguntar não muda o resultado: `fn_linhas_do_tipo`
  -- depende de (caso, tipo), não do documento.
  with tipos_do_caso as materialized (
    select distinct d.tipo_taxonomia from documento d where d.caso_id = p_caso_id
  ),
  tipos_com_conteudo as (
    select t.tipo_taxonomia from tipos_do_caso t
    where fn_linhas_do_tipo(p_caso_id, t.tipo_taxonomia) > 0
  ),
  -- A VERSÃO VIGENTE DE CADA DOCUMENTO, resolvida UMA vez. `fn_versao_com_extracao`
  -- estava na condição do join, o que a fazia ser reavaliada durante o
  -- casamento das linhas; aqui ela é uma coluna, calculada uma vez por
  -- documento. Mesma lição de custo da 0101, aplicada ao outro lado da consulta.
  docs as (
    select d.id, d.tipo_taxonomia, ent.razao_social as ent_doc,
           fn_versao_com_extracao(d.id) as versao
    from documento d
    left join entidade ent on ent.id = d.entidade_id
    where d.caso_id = p_caso_id
  ),
  campos as (
    select dc.tipo_taxonomia,
           ce.chave, ce.secao, ce.secao_canonica,
           -- 0145: o outro eixo da matriz.
           ce.periodo_coluna as coluna,
           coalesce(ce.entidade_coluna, dc.ent_doc) as ent_txt
    from docs dc
    join campo_extraido ce on ce.documento_versao_id = dc.versao
    where ce.valor_num is not null
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
          -- O ALVO do casamento, escolhido pelo modo. `chave` é o padrão; `secao`
          -- e `coluna` (0145) são os dois eixos que o documento declara em volta
          -- da célula. Calculado uma vez, num lateral, em vez de repetido nas
          -- duas condições — a forma antiga repetia o `case` inteiro no inclui e
          -- no exclui, e a terceira alternativa deixaria isso ilegível.
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
  -- ocorrências para saber DE QUEM ela é. A coluna entra no reencontro junto com
  -- as outras chaves — sem ela, uma célula casada pela coluna traria de volta
  -- todas as células da mesma linha.
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
  'Exigências de linha aplicáveis ao caso (tipos presentes COM conteúdo), com satisfeita s/n. '
  'Casa contra a versão VIGENTE (0102), pela chave, pela seção, pela COLUNA (0145) ou pelo rótulo '
  'estrutural. Alimenta o passo 2b de fn_recomputar_completude e a tela do caso.';

grant execute on function fn_exigencias_do_caso(uuid) to authenticated;

-- -----------------------------------------------------------------------------
-- (3) Os três conceitos que moram na coluna ganham o localizador que os acha.
--
-- Os termos são os cabeçalhos como os documentos os escrevem, e cada um é
-- verificado contra o dado real da v48 no comentário. `ordem` alta para deixar os
-- localizadores de linha (0113) tentarem primeiro — em documento escrito por
-- linha eles continuam sendo o caminho.
-- -----------------------------------------------------------------------------
insert into taxonomia_linha_localizador (exigencia_id, ordem, contra, termos_inclui, termos_exclui)
select e.id, x.ordem, 'coluna', x.inclui, array[]::text[]
from taxonomia_linha_exigida e
join (values
  -- MAPA_DIVIDA: cabeçalho real "Juros do exercício (R$)". Sem `exclui` — a
  -- coluna vizinha é "Saldo devedor (R$)" e já não casa com "juros". Ela também
  -- não PODE ter `exclui` que a checagem não use: a guarda seed×código do
  -- `linha_exigida_entidade.test.sql` exige que todo termo do localizador exista
  -- no texto de `fn_reconciliar_despfin_dre_vs_divida`, e foi ela que reprovou a
  -- primeira versão desta migration, com `exclui = ['saldo']`. Guarda certa: um
  -- termo que só um dos dois lados conhece é a exigência dizendo "achei" sobre
  -- um dado que a checagem não acha.
  ('MAPA_DIVIDA',    'juros_por_contrato',      10, array['juros']),
  ('MAPA_DIVIDA',    'juros_por_contrato',      11, array['encargos']),
  -- MUTUOS: cabeçalho real "Saldo devedor".
  ('MUTUOS',         'saldo_de_mutuo',          10, array['saldo']),
  -- FAT_INTRAGRUPO: cabeçalho real "Valor" (as outras colunas do documento são
  -- "Exercício", "Empresa emitente", "Empresa tomadora" e "Natureza", e nenhuma
  -- delas traz `valor_num`, então nem chegam aqui).
  ('FAT_INTRAGRUPO', 'faturamento_entre_partes', 10, array['valor'])
) x(tipo, conceito, ordem, inclui)
  on x.tipo = e.tipo_taxonomia and x.conceito = e.conceito
where not exists (
  select 1 from taxonomia_linha_localizador l
  where l.exigencia_id = e.id and l.ordem = x.ordem
);

-- -----------------------------------------------------------------------------
-- (4) E A CHECAGEM QUE CONSOME O CONCEITO TAMBÉM PRECISA OLHAR PARA A COLUNA.
--
-- Este é o passo que quase ficou de fora, e a guarda seed×código do
-- `linha_exigida_entidade.test.sql` foi quem o cobrou. Fazer só (1)-(3) deixaria
-- a exigência SATISFEITA e `fn_reconciliar_despfin_dre_vs_divida` ainda cega: ela
-- soma os juros procurando '%juros%' em `ce.chave`, que no mapa de dívida é o
-- nome do banco. Não acharia linha nenhuma, cairia no `v_n = 0` e devolveria
-- `precondicao_nao_satisfeita` — exatamente a pendência da v48 no
-- `02_DRE_Canastra_Industria`. Uma pendência falsa trocada por outra não é
-- correção; é o defeito mudando de nome.
--
-- A busca passa a aceitar o termo na CHAVE **ou** na COLUNA. O documento escrito
-- por linha continua sendo achado pelo primeiro ramo; o matricial passa a ser
-- achado pelo segundo. O filtro de total continua sobre a chave, que é onde o
-- rótulo "TOTAL" mora nos dois formatos.
--
-- PATCH COM ÂNCORA, e não reemissão: a função tem ~120 linhas de aritmética de
-- escala e tolerância que não mudam, e o que muda é UMA condição. Mesma razão da
-- 0141/0142/0143, e a mesma proteção — âncora não encontrada levanta exceção.
do $mig$
declare
  v_src text; v_novo text; v_n int;
  v_padrao constant text :=
    '\s*and \(fn_normalizar_texto\(ce\.chave\) like ''%juros%'' '
    || 'or fn_normalizar_texto\(ce\.chave\) like ''%encargos%''\)';
  v_troca constant text :=
    E'\n      -- 0145: o conceito pode morar na COLUNA. No mapa de dívida matricial a\n'
    || E'      -- chave é o contrato ("Banco Meridional S.A. - Capital de giro (…)") e o\n'
    || E'      -- cabeçalho é "Juros do exercício (R$)". Sem este segundo ramo a soma vinha\n'
    || E'      -- vazia e a checagem devolvia precondicao_nao_satisfeita sobre um documento\n'
    || E'      -- perfeitamente extraído — pendência da v48 no 02_DRE_Canastra_Industria.\n'
    || E'      and (fn_normalizar_texto(ce.chave) like ''%juros%''\n'
    || E'           or fn_normalizar_texto(ce.chave) like ''%encargos%''\n'
    || E'           or fn_normalizar_texto(coalesce(ce.periodo_coluna, '''')) like ''%juros%''\n'
    || E'           or fn_normalizar_texto(coalesce(ce.periodo_coluna, '''')) like ''%encargos%'')';
begin
  select pg_get_functiondef(p.oid) into v_src
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public' and p.proname = 'fn_reconciliar_despfin_dre_vs_divida';

  if v_src is null then
    raise exception '0145: fn_reconciliar_despfin_dre_vs_divida não existe — migration fora de ordem';
  end if;

  select count(*) into v_n from regexp_matches(v_src, v_padrao, 'g');
  if v_n <> 1 then
    raise exception '0145: esperava UMA ocorrência do filtro de juros e achei % — a função mudou de forma', v_n;
  end if;

  v_novo := regexp_replace(v_src, v_padrao, v_troca);
  execute v_novo;

  -- Confere em vez de confiar.
  select pg_get_functiondef(p.oid) into v_src
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public' and p.proname = 'fn_reconciliar_despfin_dre_vs_divida';
  if position('0145: o conceito pode morar na COLUNA' in v_src) = 0 then
    raise exception '0145: a função foi recriada sem o ramo da coluna — abortado';
  end if;
end $mig$;
