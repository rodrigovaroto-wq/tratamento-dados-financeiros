-- =============================================================================
-- 0166 — A exigência `passivo_mais_pl` não conhecia o "PASSIVO" bare
--
-- MESMA CONVENÇÃO DA 0165, CÓDIGO DIFERENTE — e é por isso que a 0165 sozinha
-- não resolveu. A 0165 corrigiu a RECONCILIAÇÃO (a checagem A.1, que compara
-- valores); esta corrige o CHECKLIST (o Kit Básico, que só pergunta se a linha
-- EXISTE). São dois caminhos independentes sobre o mesmo dado, e o lote real do
-- caso "teste 143" abriu pendência nos dois.
--
-- O QUE O DONO VIU, no painel: CINCO pendências `linha_exigida_ausente` dizendo
--
--     "a linha exigida 'Passivo + Patrimônio Líquido (total)' não foi
--      localizada na versão vigente"
--
-- uma para cada entidade do grupo (AMOBELEZA, GENERAL CORPORATE, GENERAL
-- TABACO, OMNIBEAUTY) e uma para o tipo COMBINADO. Os balanços TÊM a linha —
-- ela se chama "PASSIVO", e vale 118.591.566,53 no balanço de 2024 da
-- AMOBELEZA, o mesmo valor do ATIVO (ver a 0165 para a medição completa).
--
-- CAUSA RAIZ. `passivo_mais_pl` tem QUATRO localizadores (seed da 0113):
--
--   1. chave      ['passivo','patrimonio','total']  exclui ['circulante']
--   2. estrutural ['passivo','patrimonio']
--   3. chave      ['passivo','total']               exclui ['patrimonio', …]
--   4. chave      ['patrimonio','liquido','total']  exclui ['circulante']
--
-- Nenhum casa "PASSIVO" sozinho: 1, 3 e 4 exigem a palavra "total" no rótulo, e
-- o 2 exige que sobrem EXATAMENTE os tokens {passivo, patrimonio} depois de
-- tirada a ligação (`fn_rotulo_estrutural`) — "PASSIVO" deixa só {passivo}.
--
-- E O SEED JÁ DIZIA QUE ISSO IA ACONTECER. O comentário dele, escrito na 0113:
--
--     "origem='codigo': termos copiados LITERALMENTE das reconciliações
--      vigentes … Se um dia a reconciliação mudar de termos, este seed é o
--      segundo lugar a atualizar"
--
-- A reconciliação mudou de termos na 0034 (ganhou os dois caminhos estruturais,
-- inclusive o `fn_valor_estrutural_col(['passivo'])` que casa "PASSIVO" bare) e
-- o seed não foi junto. Ficou dois anos de migration defasado, e só um lote com
-- essa convenção de rótulo fez a diferença aparecer.
--
-- A CORREÇÃO: um quinto localizador, `estrutural ['passivo']`, espelhando o
-- fallback que a reconciliação já tem. Ele casa "PASSIVO" e NÃO casa
-- "PASSIVO E PATRIMÔNIO LÍQUIDO" (que sobra {passivo, patrimonio} e já é o
-- localizador 2), nem "PASSIVO CIRCULANTE" (sobra {passivo, circulante}).
--
-- POR QUE UM LOCALIZADOR FROUXO AQUI NÃO AFROUXA A CHECAGEM, e isto é o ponto
-- que o próprio seed da 0113 já argumenta na descrição da exigência:
--
--     "aqui qualquer localizador satisfaz — a exigência acusa a ausência
--      total, o par fino continua com a reconciliação."
--
-- O Kit Básico responde "existe alguma linha que sirva de lado direito?". Se o
-- VALOR dela fecha com o ativo é pergunta da A.1 (`fn_reconciliar_ativo_passivo_pl`),
-- que roda sobre o mesmo documento e abre a pendência própria dela. Esta
-- migration não toca essa segunda pergunta.
--
-- Idempotente: `on conflict (exigencia_id, ordem) do nothing`, padrão do seed
-- da 0113.
-- =============================================================================

begin;

insert into taxonomia_linha_localizador (exigencia_id, ordem, contra, termos_inclui, termos_exclui)
select e.id, 5, 'estrutural', array['passivo']::text[], '{}'::text[]
from taxonomia_linha_exigida e
where e.tipo_taxonomia in ('BALANCO', 'COMBINADO') and e.conceito = 'passivo_mais_pl'
on conflict (exigencia_id, ordem) do nothing;

-- -----------------------------------------------------------------------------
-- O CATÁLOGO DA SONDA — e a VIEW existe porque o requisito de `seed` conta a
-- TABELA INTEIRA.
--
-- `fn_instalacao_conferir` responde ">= criterio" com
-- `select count(*) from (select 1 from <objeto> limit <criterio>)`. Apontado
-- direto para `taxonomia_linha_localizador`, qualquer critério pequeno já é
-- satisfeito pelas dezenas de localizadores das OUTRAS exigências — o requisito
-- passaria num banco que nunca aplicou esta migration. Seria um requisito
-- nascido vazio dentro da sonda, que é o pior lugar para ter um: a sonda é o
-- último lugar do sistema que pode mentir dizendo "está tudo instalado".
--
-- A view isola EXATAMENTE as linhas que esta migration insere. São duas
-- (BALANCO e COMBINADO), e o critério é 2.
-- -----------------------------------------------------------------------------
create or replace view instalacao_sonda_passivo_bare as
  select l.id, e.tipo_taxonomia
    from taxonomia_linha_localizador l
    join taxonomia_linha_exigida e on e.id = l.exigencia_id
   where e.conceito = 'passivo_mais_pl'
     and l.contra = 'estrutural'
     and l.termos_inclui = array['passivo']::text[];

comment on view instalacao_sonda_passivo_bare is
  'Sonda da 0166: os localizadores que casam o rótulo "PASSIVO" sozinho. Duas linhas '
  '(BALANCO e COMBINADO) — zero significa que o Kit Básico volta a cobrar do cliente uma '
  'linha que ele já entregou.';

grant select on instalacao_sonda_passivo_bare to authenticated;

insert into instalacao_requisito
  (chave, migration, tipo, objeto, marcador, criterio_seed, porque, severidade, ordem) values
  ('passivo_mais_pl_conhece_o_bare', '0166', 'seed', 'instalacao_sonda_passivo_bare', null, 2,
   'A exigência passivo_mais_pl tinha quatro localizadores e nenhum casava o rótulo "PASSIVO" '
   'sozinho — que é como a maioria dos balanços brasileiros imprime o total do lado direito. '
   'Sem o quinto, o Kit Básico abre linha_exigida_ausente para TODA entidade cujo balanço usa '
   'essa convenção (cinco pendências falsas no lote real do caso "teste 143"), e o mandato fica '
   'travado pedindo ao cliente uma linha que ele já entregou.',
   'bloqueante', 640)
on conflict (chave) do update set
  migration = excluded.migration, tipo = excluded.tipo, objeto = excluded.objeto,
  marcador = excluded.marcador, criterio_seed = excluded.criterio_seed,
  porque = excluded.porque, severidade = excluded.severidade, ordem = excluded.ordem;

update instalacao_cobertura
   set ate_migration = '0166', revisado_em = current_date,
       observacao = 'A 0166 é seed puro (um localizador a mais em passivo_mais_pl). O requisito '
                    'aponta para a view instalacao_sonda_passivo_bare, que isola as DUAS linhas '
                    'inseridas — apontar para a tabela contaria os localizadores das outras '
                    'exigências e o requisito nasceria vazio.';

commit;
