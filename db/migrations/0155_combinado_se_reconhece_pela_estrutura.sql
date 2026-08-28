-- 0155 — UM DOCUMENTO COM QUINZE EMPRESAS NAS COLUNAS É UM COMBINADO, E O
-- CATÁLOGO NÃO PRECISA ACREDITAR NO NOME DELE.
--
-- MEDIDO NA RODADA REAL DO `book-araucaria`, conferindo a escala de autoridade
-- da `0151` contra o dado gravado:
--
--   arquivo                                          tipo        empresas   autoridade
--   053_Balanco_Patrimonial_COMBINADO_..._2025.pdf   BALANCO        15          55
--   054_Balanco_Patrimonial_COMBINADO_..._2024.pdf   BALANCO        15          55
--   055_Balanco_Patrimonial_COMBINADO_..._2023.pdf   BALANCO        15          55
--   056_Balanco_Patrimonial_COMBINADO_..._2022.pdf   COMBINADO      14          35
--   057_Balanco_Patrimonial_COMBINADO_..._2021.pdf   BALANCO        14          55
--
-- **O MESMO PADRÃO DE NOME, TIPOS DIFERENTES.** A classificação veio da IA
-- (`openai_conteudo`, confiança 1,0) em todos os cinco, e ela chamou quatro de
-- BALANCO e um de COMBINADO. Não é aleatório no sentido de ser raro: é o que
-- acontece quando se pede a um modelo que escolha entre dois rótulos que
-- descrevem a mesma peça por ângulos diferentes — um balanço combinado É um
-- balanço, e É um combinado.
--
-- ---------------------------------------------------------------------------
-- POR QUE ISSO DERRUBA A 0151
-- ---------------------------------------------------------------------------
--
-- A escala da `0151` existe para que o combinado PERCA das peças que o formam:
--
--     BALANCO ....... 50    a demonstração fechada da própria entidade
--     COMBINADO ..... 30    DERIVADO: a soma das empresas menos as eliminações,
--                           e a eliminação é julgamento de quem montou
--
-- Chamado de BALANCO, o combinado sobe de 30 para 50 — e passa a EMPATAR com o
-- balanço individual da empresa. Pela `0151`, empate significa "ninguém decide"
-- e o valor em uso continua o de maior módulo: **exatamente o desempate
-- silencioso que a 0151 foi escrita para eliminar**, de volta pela porta da
-- classificação.
--
-- E ele encosta nos individuais de verdade, não em tese: as linhas do combinado
-- trazem `entidade_coluna` por empresa, então elas são atribuídas a cada
-- companhia (0146) e entram na mesma comparação que o balanço dela. Medido
-- nesta rodada: `NOTAS_EXPL diz X, COMBINADO diz Y` para a Araucária Serraria —
-- a comparação acontece.
--
-- É a armadilha central do araucária: *um combinado preliminar que infla o
-- ativo do grupo em até 32.800 (R$ mil) e FECHA.*
--
-- ---------------------------------------------------------------------------
-- A CORREÇÃO NÃO É ENSINAR O CLASSIFICADOR — É PARAR DE PERGUNTAR
-- ---------------------------------------------------------------------------
--
-- Dava para mexer no prompt, ou para impedir a IA de rebaixar COMBINADO para
-- BALANCO quando o nome do arquivo diz "combinado". As duas tratam o sintoma e
-- as duas dependem de alguém acertar um rótulo ambíguo.
--
-- O FATO ESTÁ NO DADO, E É DE GRAÇA: **quantas empresas as colunas do documento
-- nomeiam.** Um documento cujas linhas falam de quinze companhias é a soma
-- delas, qualquer que seja o nome na capa. Nenhuma IA precisa opinar.
--
-- É o mesmo movimento da `0146` — lá, "a capa só responde quando o documento é
-- de UMA empresa", critério estrutural em vez de lista de nomes. Aqui é o mesmo
-- critério, do outro lado: quando o documento é de VÁRIAS, ele é derivado.
--
-- A REGRA SÓ ABAIXA, NUNCA LEVANTA (`least`). Um documento já declarado
-- COMBINADO não muda; uma DF AUDITADA de um grupo — que é auditada de verdade,
-- por terceiro, e por isso vale 60 — **também cai para 30**, e isso é
-- deliberado: o que a escala mede não é a qualidade da auditoria, é a distância
-- até a peça original. Uma DF auditada consolidada continua sendo a soma das
-- empresas com eliminações julgadas por alguém, e contra o balanço individual
-- da empresa ela é a fonte derivada. Se um dia isso se mostrar errado, o lugar
-- de mudar é aqui, com o número medido ao lado.

create or replace function fn_documento_de_varias_empresas(p_documento_id uuid)
returns boolean
language sql
stable
as $$
  -- 0155: o critério é ESTRUTURAL — quantas empresas as colunas nomeiam.
  --
  -- DUAS OU MAIS, e não "mais que zero": um comparativo de exercícios de UMA
  -- empresa também declara `entidade_coluna` (a mesma, repetida), e rebaixá-lo
  -- transformaria todo balanço multi-ano em derivado.
  select count(distinct ce.entidade_coluna) > 1
  from campo_extraido ce
  where ce.documento_versao_id = fn_versao_com_extracao(p_documento_id)
    and ce.entidade_coluna is not null;
$$;

comment on function fn_documento_de_varias_empresas(uuid) is
  'As linhas deste documento nomeiam mais de uma empresa? (0155) Critério ESTRUTURAL de que a '
  'peça é derivada — a soma de várias companhias —, independente do rótulo que o classificador '
  'lhe deu. Medido no book-araucaria: o mesmo padrão de nome saiu como BALANCO em quatro '
  'documentos e COMBINADO num quinto, todos com 14-15 empresas nas colunas.';

create or replace function fn_autoridade_do_documento(p_documento_id uuid)
returns table (autoridade integer, motivo text)
language sql
stable
as $$
  -- 0155: um documento cujas linhas nomeiam VÁRIAS empresas é derivado, e a
  -- autoridade dele não pode passar da de COMBINADO — senão o combinado empata
  -- com o balanço individual e o empate volta a "fica com o maior".
  with base as (
    select
      coalesce(t.autoridade, 0) as do_tipo,
      coalesce(t.codigo, 'sem tipo') as codigo,
      coalesce(t.autoridade, 0) = 0 as sem_declaracao,
      dv.assinado is true as assinado,
      fn_documento_preliminar(dv.nome_original) as preliminar,
      fn_documento_de_varias_empresas(d.id) as varias_empresas,
      (select coalesce(tc.autoridade, 30) from taxonomia_tipo_documento tc
        where tc.codigo = 'COMBINADO') as teto_derivado
    from documento d
    left join taxonomia_tipo_documento t on t.codigo = d.tipo_taxonomia
    left join documento_versao dv on dv.id = fn_versao_com_extracao(d.id)
    where d.id = p_documento_id
  )
  select
    (case when b.varias_empresas then least(b.do_tipo, b.teto_derivado) else b.do_tipo end
     + case when b.assinado then 5 else 0 end
     - case when b.preliminar then 25 else 0 end)::integer,
    b.codigo
      || case when b.sem_declaracao
              then ' (o catálogo não declara autoridade para este tipo)' else '' end
      || case when b.varias_empresas
              then format(', mas as colunas nomeiam VÁRIAS empresas — é peça derivada, e a '
                       || 'autoridade não passa da de combinado (%s)', b.teto_derivado)
              else '' end
      || case when b.assinado then ', assinado' else '' end
      || case when b.preliminar
              then ', e o nome do arquivo diz que é preliminar' else '' end
  from base b;
$$;

comment on function fn_autoridade_do_documento(uuid) is
  'A autoridade documental de UM documento e o motivo por extenso (0151): a do tipo no catálogo, '
  'mais 5 se assinada, menos 25 se o nome do arquivo declara preliminar. Desde a 0155, um '
  'documento cujas colunas nomeiam VÁRIAS empresas tem a autoridade limitada à de COMBINADO — '
  'ele é a soma delas, e o classificador chama a mesma peça de BALANCO ou de COMBINADO conforme '
  'o dia.';

grant execute on function fn_documento_de_varias_empresas(uuid) to authenticated;

-- -----------------------------------------------------------------------------
-- A SONDA
-- -----------------------------------------------------------------------------
insert into instalacao_requisito
  (chave, migration, tipo, objeto, marcador, criterio_seed, porque, severidade, ordem) values
  ('combinado_pela_estrutura', '0155', 'corpo', 'fn_autoridade_do_documento', '0155', null,
   'O combinado do grupo volta a valer o mesmo que o balanço individual da empresa quando o '
   'classificador o chama de BALANCO — e ele chama: medido no book-araucaria, o mesmo padrão de '
   'nome saiu BALANCO em quatro documentos e COMBINADO num quinto, todos com 14-15 empresas nas '
   'colunas. Com autoridade igual, o desempate da 0151 vira EMPATE, e empate mantém o de maior '
   'módulo — que é o combinado inflado, a armadilha central do araucária.',
   'bloqueante', 590),
  ('documento_de_varias_empresas', '0155', 'funcao', 'fn_documento_de_varias_empresas', null, null,
   'Sem ela não há critério estrutural para reconhecer peça derivada, e a autoridade volta a '
   'depender de um rótulo que a IA escolhe entre dois igualmente defensáveis.',
   'importante', 595)
on conflict (chave) do update
  set migration = excluded.migration, tipo = excluded.tipo, objeto = excluded.objeto,
      marcador = excluded.marcador, criterio_seed = excluded.criterio_seed,
      porque = excluded.porque, severidade = excluded.severidade, ordem = excluded.ordem;

update instalacao_cobertura
   set ate_migration = '0155',
       revisado_em = date '2026-08-28',
       observacao = 'Revisão de 28/08/2026: a 0155 fecha a porta pela qual a armadilha do '
                    'araucária voltava — o combinado do grupo classificado como BALANCO empata '
                    'com o balanço individual, e empate mantém o de maior módulo. O critério '
                    'passa a ser estrutural (quantas empresas as colunas nomeiam), como a 0146 '
                    'já faz do outro lado. Dois requisitos novos.'
 where id;
