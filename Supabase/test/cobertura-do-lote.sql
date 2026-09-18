-- COBERTURA DO LOTE, DOCUMENTO A DOCUMENTO — o aceite financeiro da F0 (fatia 0.5).
--
-- POR QUE ESTE ARQUIVO EXISTE. O critério de aceite da fatia 0.5 é "≥95% dos documentos com
-- linha; o que falhar, falha por razão nova e documentada". Um percentual sozinho NÃO cumpre
-- esse critério, e cumprir pela metade aqui é pior do que não medir: um documento que
-- legitimamente não tem linha (certidão, organograma, contrato social — a regra da `0111`) é
-- indistinguível, num percentual, de um documento cuja extração voltou vazia. Descontar os dois
-- do numerador reprova um lote são; contar os dois aprova um lote quebrado. É a regra 1 do
-- projeto na sua forma mais direta: **a ausência precisa vir com o motivo**.
--
-- Por isso a consulta classifica cada documento em uma de quatro situações, e as três primeiras
-- NÃO são a mesma coisa:
--
--   com_linha                 a extração rodou e produziu linha. É o numerador.
--   sem_linha_declarado       a extração rodou, produziu zero linha, e o diagnóstico declarou
--                             `tem_dado_financeiro = false`. NÃO é falha (`0111`): é o sistema
--                             dizendo, com registro, que este documento não tinha número para dar.
--   sem_linha_silencioso      a extração rodou, produziu zero linha, e NINGUÉM declarou que não
--                             havia dado (`tem_dado_financeiro` true ou nulo). **Esta é a falha
--                             real** — a extração foi paga e voltou vazia sem ninguém assumir.
--   extracao_nunca_chamada    não existe evento `extracao_sombra` em versão nenhuma. O documento
--                             não foi processado; é o que `fn_documentos_nao_extraidos` (`0112`)
--                             persegue, e a falha mais grave das quatro, porque não custou nada
--                             e não deixou rastro no lote.
--
-- O SINAL VEM DO EVENTO, e não de uma coluna, porque é lá que ele é gravado:
-- `fn_registrar_campos_extraidos` (`0111`, linha 124) publica
-- `jsonb_build_object('campos', …, 'tem_dado_financeiro', …)` no `evento_auditoria` de ação
-- `extracao_sombra`. A última versão de cada documento é a que vale — reprocessar grava um
-- evento novo, e o veredito do lote é o do último processamento, não o do primeiro.
--
-- COMO RODAR (somente leitura — nenhuma escrita, nenhuma função que grava):
--
--   psql "$URL" -v caso_id="'<uuid do caso>'" -f Supabase/test/cobertura-do-lote.sql
--
-- Para descobrir o uuid pelo nome do mandato:
--   select id, nome from caso order by criado_em desc;

\set ON_ERROR_STOP on

-- SOMENTE LEITURA, e por que NÃO com `begin read only` / `commit`. A primeira versão deste
-- arquivo abria e fechava a própria transação — e ao ser rodado de dentro de uma transação já
-- aberta (foi assim que a prova o exercitou), o `begin` só avisava `there is already a
-- transaction in progress` e o `commit` COMITAVA a transação de quem chamou. Um arquivo que se
-- anuncia somente-leitura encerrando a transação alheia é pior que um sem garantia nenhuma.
-- `default_transaction_read_only` dá a mesma proteção sem tocar no controle de transação: uma
-- escrita acidental aqui dentro reprova, e o chamador continua dono da transação dele.
set default_transaction_read_only = on;

-- O veredito por documento. É esta saída que vai ao ACEITE — o percentual sozinho não basta.
with ultima_versao as (
  select distinct on (dv.documento_id)
         dv.documento_id, dv.id as versao_id, dv.nome_original
    from documento_versao dv
    join documento d on d.id = dv.documento_id
   where d.caso_id = :caso_id
   order by dv.documento_id, dv.n_versao desc
),
-- O último evento de extração de CADA versão do documento, não só da última: um documento cuja
-- versão nova ainda não foi extraída continua tendo o veredito da versão que foi.
extracao as (
  select distinct on (dv.documento_id)
         dv.documento_id,
         ea.criado_em,
         (ea.depois->>'campos')::int              as campos_no_evento,
         ea.depois->>'falha_motivo'               as falha_motivo,
         (ea.depois->>'tem_dado_financeiro')::bool as tem_dado_financeiro
    from documento_versao dv
    join documento d on d.id = dv.documento_id
    join evento_auditoria ea
      on ea.acao = 'extracao_sombra'
     and ea.entidade_ref = 'documento_versao:' || dv.id::text
   where d.caso_id = :caso_id
   order by dv.documento_id, ea.criado_em desc
),
linhas as (
  select dv.documento_id, count(ce.id) as linhas
    from documento_versao dv
    join documento d on d.id = dv.documento_id
    left join campo_extraido ce on ce.documento_versao_id = dv.id
   where d.caso_id = :caso_id
   group by dv.documento_id
),
veredito as (
  select d.id,
         d.tipo_taxonomia,
         uv.nome_original,
         coalesce(l.linhas, 0) as linhas,
         e.falha_motivo,
         e.tem_dado_financeiro,
         case
           when coalesce(l.linhas, 0) > 0                     then 'com_linha'
           when e.documento_id is null                        then 'extracao_nunca_chamada'
           when e.tem_dado_financeiro is false                then 'sem_linha_declarado'
           else                                                    'sem_linha_silencioso'
         end as situacao
    from documento d
    join ultima_versao uv on uv.documento_id = d.id
    left join linhas    l on l.documento_id  = d.id
    left join extracao  e on e.documento_id  = d.id
   where d.caso_id = :caso_id
)
select situacao, tipo_taxonomia, nome_original, linhas, falha_motivo, tem_dado_financeiro
  from veredito
 -- Os que não têm linha primeiro: são eles que o aceite manda explicar.
 order by (situacao = 'com_linha'), situacao, tipo_taxonomia, nome_original;

-- O placar, com as quatro situações abertas. O ">= 95%" do aceite é lido de `pct_com_linha`,
-- e as outras três colunas são o que impede esse número de ser lido sozinho.
with ultima_versao as (
  select distinct on (dv.documento_id) dv.documento_id, dv.id as versao_id
    from documento_versao dv join documento d on d.id = dv.documento_id
   where d.caso_id = :caso_id
   order by dv.documento_id, dv.n_versao desc
),
extracao as (
  select distinct on (dv.documento_id)
         dv.documento_id, (ea.depois->>'tem_dado_financeiro')::bool as tem_dado_financeiro
    from documento_versao dv
    join documento d on d.id = dv.documento_id
    join evento_auditoria ea
      on ea.acao = 'extracao_sombra'
     and ea.entidade_ref = 'documento_versao:' || dv.id::text
   where d.caso_id = :caso_id
   order by dv.documento_id, ea.criado_em desc
),
linhas as (
  select dv.documento_id, count(ce.id) as linhas
    from documento_versao dv
    join documento d on d.id = dv.documento_id
    left join campo_extraido ce on ce.documento_versao_id = dv.id
   where d.caso_id = :caso_id
   group by dv.documento_id
),
veredito as (
  select case
           when coalesce(l.linhas, 0) > 0      then 'com_linha'
           when e.documento_id is null         then 'extracao_nunca_chamada'
           when e.tem_dado_financeiro is false then 'sem_linha_declarado'
           else                                     'sem_linha_silencioso'
         end as situacao
    from documento d
    join ultima_versao uv on uv.documento_id = d.id
    left join linhas    l on l.documento_id  = d.id
    left join extracao  e on e.documento_id  = d.id
   where d.caso_id = :caso_id
)
select count(*) as documentos,
       count(*) filter (where situacao = 'com_linha')              as com_linha,
       count(*) filter (where situacao = 'sem_linha_declarado')    as sem_linha_declarado,
       count(*) filter (where situacao = 'sem_linha_silencioso')   as sem_linha_silencioso,
       count(*) filter (where situacao = 'extracao_nunca_chamada') as extracao_nunca_chamada,
       -- NULL quando o caso não tem documento nenhum: 0% e "não há o que medir" são coisas
       -- diferentes, e a divisão por zero é a única que devolve a verdade aqui.
       round(100.0 * count(*) filter (where situacao = 'com_linha')
             / nullif(count(*), 0), 1) as pct_com_linha
  from veredito;

-- As pendências ainda abertas do caso, por tipo. Fecham o quadro: um documento pode ter linha e
-- mesmo assim ter deixado pendência (cobertura parcial, balanço que não fecha).
select tipo::text, severidade::text, count(*) as abertas
  from pendencia
 where caso_id = :caso_id and estado <> 'resolvida'
 group by 1, 2
 order by 3 desc, 1;
