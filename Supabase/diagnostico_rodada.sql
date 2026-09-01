-- RAIO-X DE UMA RODADA — uma linha por documento, tudo o que decide a análise.
--
-- POR QUE EXISTE. Depois de uma rodada real, a pergunta não é "deu certo?" — é
-- "o que exatamente saiu de cada documento, e onde isso diverge do esperado?".
-- Responder isso clicando documento por documento no portal leva uma tarde e
-- não deixa rastro; esta consulta responde em uma tabela que se copia inteira.
--
-- O QUE ELA MEDE, e cada coluna existe por uma pergunta:
--   • tipo/confiança/fonte  → a classificação acertou, e QUEM acertou (o nome do
--     arquivo ou a leitura do conteúdo)? É o que diz se o fallback está valendo;
--   • pares vs contas       → `campo_extraido` guarda um par (conta × coluna); um
--     balanço comparativo de 3 anos tem 3 pares por conta. Confundir os dois faz
--     "extraiu muito" parecer qualidade quando é só coluna repetida;
--   • colunas/entidades     → documento combinado tem várias empresas lado a lado;
--     se vier 1, a leitura achatou o que era comparativo;
--   • escala/moeda          → os dois fatores multiplicativos que já erraram 496×
--     neste projeto. Escala nula numa demonstração em milhares é um erro de 1000×
--     esperando para acontecer;
--   • seções canônicas      → quantas o documento produziu. Uma só num balanço
--     significa que tudo caiu no mesmo balde e o export não vai saber rotear;
--   • linhas sem seção      → o que vai cair em "Contas Não Classificadas";
--   • pendências            → o que o sistema já sabe que precisa de humano.
--
-- COMO RODAR: troque o nome do mandato na primeira linha e cole no SQL Editor do
-- Supabase. Não escreve nada — é só leitura.
with alvo as (select id from caso where nome = 'Teste v47 - Grupo Canastra + Gemini API')
select
  dv.nome_original                                             as arquivo,
  d.tipo_taxonomia                                             as tipo,
  round(d.confianca, 2)                                        as confianca,
  d.fonte                                                      as classificado_por,
  dv.legibilidade,
  dv.assinado,
  count(distinct ce.id)                                        as pares_conta_coluna,
  count(distinct ce.chave)                                     as contas_distintas,
  count(distinct ce.periodo_coluna)                            as colunas,
  count(distinct ce.entidade_coluna)                           as entidades_na_planilha,
  max(ce.unidade)                                              as escala,
  max(ce.moeda)                                                as moeda,
  round(avg(ce.confianca), 2)                                  as confianca_media_das_linhas,
  count(distinct ce.secao_canonica)                            as secoes_canonicas,
  count(*) filter (where ce.secao_canonica is null)            as linhas_sem_secao,
  (select count(*) from pendencia p
     where p.documento_id = d.id and p.estado = 'aberta')      as pendencias_abertas,
  (select string_agg(distinct p.tipo::text, ', ') from pendencia p
     where p.documento_id = d.id and p.estado = 'aberta')      as tipos_de_pendencia,
  left(coalesce(d.justificativa, ''), 180)                     as porque_classificou_assim,
  left(coalesce(dv.nota_legibilidade, ''), 180)                as nota_de_legibilidade
from documento d
join alvo on alvo.id = d.caso_id
left join documento_versao dv on dv.documento_id = d.id
left join campo_extraido ce on ce.documento_versao_id = dv.id
group by d.id, dv.id, dv.nome_original, d.tipo_taxonomia, d.confianca, d.fonte,
         dv.legibilidade, dv.assinado, d.justificativa, dv.nota_legibilidade
order by dv.nome_original;
