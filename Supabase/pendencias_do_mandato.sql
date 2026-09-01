-- TODA PENDÊNCIA ABERTA DE UM MANDATO, com o documento a que pertence.
--
-- Companheira de `Supabase/diagnostico_rodada.sql`: aquela diz o que SAIU de cada
-- documento, esta diz o que o sistema DECLAROU que precisa de humano.
--
-- A ordenação é por severidade porque é assim que se trabalha a fila: bloqueante
-- impede o aceite do mandato, o resto é fila de revisão. E `sobrepujavel` vem na
-- tabela porque é a diferença entre "alguém decide e segue" e "não tem como
-- seguir sem resolver".
--
-- COMO RODAR: troque o nome do mandato na primeira linha e cole no SQL Editor do
-- Supabase. Não escreve nada — é só leitura.
with alvo as (select id from caso where nome = 'Teste v47 - Grupo Canastra + Gemini API')
select
  p.severidade, p.tipo, p.origem_estagio,
  dv.nome_original as arquivo,
  left(coalesce(p.descricao, ''), 400) as descricao,
  left(coalesce(p.motivo, ''), 400)    as motivo,
  p.sobrepujavel, p.criada_em
from pendencia p
join alvo on alvo.id = p.caso_id
left join documento d on d.id = p.documento_id
left join documento_versao dv on dv.documento_id = d.id
where p.estado = 'aberta'
order by
  case p.severidade::text when 'bloqueante' then 1 when 'alta' then 2 when 'media' then 3 else 4 end,
  p.tipo, dv.nome_original;
