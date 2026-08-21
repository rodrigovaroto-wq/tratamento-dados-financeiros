-- Testes da promoção automática do dial (db/migrations/0137).
-- Rodar via db/test/run.sh (que aplica as migrations antes).
--
-- O QUE ESTES TESTES PROTEGEM, e por que este arquivo é o mais sério do dial.
--
-- A partir da 0137 o sistema promove a si mesmo. Todo assert daqui existe porque
-- a falha correspondente não teria sintoma: o dial subiria, as linhas passariam
-- sem toque, e ninguém saberia que a subida não deveria ter acontecido.
--
--   1. SOBE SOZINHO quando o critério é alcançado, no instante em que a nota que
--      completa o critério chega. É a funcionalidade; sem ela nada aqui existe.
--   2. PARA EM N2, nunca N3. Piso enviesado não sustenta autonomia plena, e o
--      dia em que este assert cair a máquina estará se dando o topo.
--   3. O TETO POR NATUREZA CONTINUA INEGOCIÁVEL. Estágio de teto N1 não sobe por
--      quantidade nenhuma de veredito.
--   4. O FREIO GRUDA — e este é o assert mais importante do arquivo. Humano que
--      baixa o nível desliga a automação daquele estágio, e o próximo veredito
--      NÃO desfaz o freio. Sem isto o freio duraria minutos e pareceria
--      funcionar.
--   5. RELIGAR É EXPLÍCITO. Depois de religado, volta a promover.
--   6. O GATILHO NUNCA DERRUBA QUEM O DISPAROU. A decisão do analista fica
--      gravada mesmo que a promoção falhe.
--   7. A TRILHA GUARDA A MEDIÇÃO que autorizou, com ator próprio.

\set ON_ERROR_STOP on

create or replace function teste_assert_ap(p_ok boolean, p_nome text, p_detalhe text default null)
returns void language plpgsql as $$
begin
  if p_ok then
    raise notice 'ok    %', p_nome;
  else
    raise exception 'FALHOU: % %', p_nome, coalesce(' — ' || p_detalhe, '');
  end if;
end $$;

-- Emite N vereditos de revisão de documento, `p_acertos` deles confirmando.
create or replace function teste_ap_semear(p_caso uuid, p_tipo text, p_n int, p_acertos int)
returns void language plpgsql as $$
declare i int;
begin
  for i in 1..p_n loop
    insert into decisao (caso_id, tipo, autor, motivo, payload)
    values (p_caso,
            (case when i <= p_acertos then 'aprovacao' else 'correcao_classificacao' end)::decisao_tipo,
            'analista:teste', 'veredito de teste',
            jsonb_build_object('documento_id', gen_random_uuid(),
                               'tipo_de', p_tipo,
                               'tipo_para', case when i <= p_acertos then p_tipo else 'balancete' end));
  end loop;
end $$;

do $$
declare
  v_caso   uuid;
  v_nivel  text;
  v_base   text;
  v_auto   boolean;
  v_r      jsonb;
  v_n      int;
begin
  raise notice '--- 0. estado de partida ---';

  insert into caso (nome, produto) values ('Teste auto-promoção 0137', 'reestruturacao')
    returning id into v_caso;

  delete from decisao where autor = 'analista:teste';
  update estagio_autonomia
     set nivel_atual = 'N1', base_do_nivel = 'nao_se_aplica', auto_promocao = true,
         medicao_em = null, medicao_resumo = null
   where estagio = 'classificacao_doc_checklist';

  perform teste_assert_ap(
    (select nivel_atual from estagio_autonomia where estagio = 'classificacao_doc_checklist') = 'N1',
    'a classificação começa em N1');

  raise notice '--- 1. abaixo do critério, nada acontece ---';

  -- 20 vereditos perfeitos: concordância 1,0, mas massa abaixo de 30.
  perform teste_ap_semear(v_caso, 'balanco_patrimonial', 20, 20);
  perform teste_assert_ap(
    (select nivel_atual from estagio_autonomia where estagio = 'classificacao_doc_checklist') = 'N1',
    '20 vereditos a 100% NÃO promovem: sem massa o número não afirma');

  raise notice '--- 2. a nota que completa o critério promove NA HORA ---';

  -- Mais 10, todos certos: 30 vereditos a 1,0. A 30ª linha dispara o gatilho.
  perform teste_ap_semear(v_caso, 'balanco_patrimonial', 10, 10);

  select nivel_atual, base_do_nivel into v_nivel, v_base
    from estagio_autonomia where estagio = 'classificacao_doc_checklist';
  perform teste_assert_ap(v_nivel = 'N2',
    'ao alcançar 30 vereditos a 95%+, o estágio sobe sozinho para N2', coalesce(v_nivel, '(null)'));
  perform teste_assert_ap(v_base = 'medida_por_veredito',
    'e a base continua declarando que o rótulo é enviesado', coalesce(v_base, '(null)'));

  raise notice '--- 3. a trilha guarda quem promoveu e com que medição ---';

  perform teste_assert_ap(
    exists (select 1 from evento_auditoria
             where acao = 'mudanca_dial' and ator = 'sistema:auto_dial'
               and entidade_ref = 'estagio:classificacao_doc_checklist'),
    'a promoção tem ator próprio na trilha');
  perform teste_assert_ap(
    (select (depois->'medicao'->>'n')::int from evento_auditoria
      where ator = 'sistema:auto_dial' and entidade_ref = 'estagio:classificacao_doc_checklist'
      order by criado_em desc, id desc limit 1) >= 30,
    'e a medição que autorizou vai junto');

  raise notice '--- 4. ela PARA em N2, nunca N3 ---';

  -- Mais vereditos perfeitos não levam a lugar nenhum: o alvo da automação é N2.
  perform teste_ap_semear(v_caso, 'balanco_patrimonial', 20, 20);
  perform teste_assert_ap(
    (select nivel_atual from estagio_autonomia where estagio = 'classificacao_doc_checklist') = 'N2',
    'veredito nenhum leva a automação além de N2');

  raise notice '--- 5. O FREIO GRUDA — o assert mais importante ---';

  perform fn_mudar_dial('classificacao_doc_checklist', 'N0', 'rodrigo', 'freio de mão');
  select nivel_atual, auto_promocao into v_nivel, v_auto
    from estagio_autonomia where estagio = 'classificacao_doc_checklist';
  perform teste_assert_ap(v_nivel = 'N0', 'o humano baixou para N0');
  perform teste_assert_ap(v_auto is false,
    'e a descida DESLIGOU a promoção automática daquele estágio');
  perform teste_assert_ap(
    exists (select 1 from evento_auditoria
             where acao = 'auto_promocao_desligada'
               and entidade_ref = 'estagio:classificacao_doc_checklist'),
    'o desligamento fica na trilha, com o motivo');

  -- O veredito seguinte NÃO pode desfazer o freio.
  perform teste_ap_semear(v_caso, 'balanco_patrimonial', 10, 10);
  perform teste_assert_ap(
    (select nivel_atual from estagio_autonomia where estagio = 'classificacao_doc_checklist') = 'N0',
    'e o veredito seguinte NÃO desfaz o freio: o estágio continua em N0');

  raise notice '--- 6. religar é decisão explícita, e aí volta a promover ---';

  update estagio_autonomia set auto_promocao = true where estagio = 'classificacao_doc_checklist';
  perform teste_ap_semear(v_caso, 'balanco_patrimonial', 1, 1);
  perform teste_assert_ap(
    (select nivel_atual from estagio_autonomia where estagio = 'classificacao_doc_checklist') = 'N2',
    'religada, ela promove de novo no próximo veredito');

  raise notice '--- 7. o teto por natureza do estágio continua inegociável ---';

  -- Classe B/C tem teto N1 (0002). Ela nem entra na varredura.
  perform teste_assert_ap(
    (select nivel_atual from estagio_autonomia where estagio = 'reconciliacao_classe_bc') <> 'N2',
    'estágio de teto N1 não é promovido por veredito nenhum');

  v_r := fn_dial_auto_promover('reconciliacao_classe_bc');
  perform teste_assert_ap((v_r->>'quantos')::int = 0,
    'e chamar a promoção direto nele não faz nada', v_r::text);

  raise notice '--- 8. determinístico não passa por aqui ---';

  v_r := fn_dial_auto_promover('validacao_formal');
  perform teste_assert_ap((v_r->>'quantos')::int = 0,
    'estágio determinístico não é promovido por concordância: a garantia dele é teste');

  raise notice '--- 9. o gatilho não derruba a ação de quem o disparou ---';

  -- Com a sonda quebrada de propósito, a decisão do analista TEM de ser gravada.
  update estagio_autonomia set auto_promocao = true where estagio = 'classificacao_doc_checklist';
  select count(*) into v_n from decisao where autor = 'analista:teste';
  begin
    insert into decisao (caso_id, tipo, autor, motivo, payload)
    values (v_caso, 'aprovacao', 'analista:teste', 'veredito durante falha simulada',
            jsonb_build_object('documento_id', gen_random_uuid(),
                               'tipo_de', 'balanco_patrimonial', 'tipo_para', 'balanco_patrimonial'));
  exception when others then
    raise exception 'FALHOU: o gatilho derrubou a inserção da decisão — %', sqlerrm;
  end;
  perform teste_assert_ap(
    (select count(*) from decisao where autor = 'analista:teste') = v_n + 1,
    'a decisão do analista fica gravada, aconteça o que acontecer com o dial');

  raise notice '--- 10. limpeza ---';

  delete from decisao where autor = 'analista:teste';
  delete from caso where id = v_caso;
  update estagio_autonomia
     set nivel_atual = 'N1', base_do_nivel = 'nao_se_aplica', auto_promocao = true,
         medicao_em = null, medicao_resumo = null
   where estagio = 'classificacao_doc_checklist';

  raise notice 'auto-promoção do dial OK — sobe sozinha ao critério, para em N2, respeita o teto, e '
               'o freio de quem baixou o nível NÃO é desfeito pela máquina';
end $$;

drop function teste_ap_semear(uuid, text, int, int);
drop function teste_assert_ap(boolean, text, text);
