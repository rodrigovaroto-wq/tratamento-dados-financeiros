-- Testes do veredito de produção (db/migrations/0136).
-- Rodar via db/test/run.sh (que aplica as migrations antes).
--
-- O QUE ESTES TESTES TRAVAM, e por que cada um.
--
--   1. NÃO MEDIDO NÃO É MEDIDO E RUIM. Estágio sem fonte de veredito devolve
--      `suficiente = false` com motivo, e nunca uma concordância inventada a
--      partir de zero veredito. É a mesma distinção que a 0131 faz entre "tabela
--      ausente" e "tabela vazia", e é a que impede o dial de subir por silêncio.
--   2. O N MÍNIMO REPROVA ANTES DA CONCORDÂNCIA. Cinco vereditos com 100% de
--      acerto não autorizam nada: sem massa, o número não afirma. Este assert é o
--      que impede a primeira semana de uso de destravar o dial.
--   3. MASSA SUFICIENTE E CONCORDÂNCIA BAIXA REPROVA — e o motivo nomeia o
--      número, não o campo.
--   4. MASSA E CONCORDÂNCIA SUFICIENTES SOBEM O DIAL, e a base fica
--      `medida_por_veredito`. Se este assert cair, a saída B do B3 virou prosa.
--   5. E A BASE NÃO PODE VIRAR `medida`. Este é o assert mais importante do
--      arquivo. `medida` é rótulo CEGO; veredito de produção é rótulo enviesado,
--      e o dia em que os dois ficarem indistinguíveis na coluna é o dia em que a
--      honestidade do dial acabou — sem sintoma, porque o número é o mesmo.
--   6. O TETO CONTINUA INEGOCIÁVEL. Nenhuma quantidade de veredito sobe um
--      estágio acima do teto da natureza dele.
--   7. DESCER CONTINUA SEM PEDIR NADA. Freio que exige papelada não é freio.
--   8. A RECUSA VAI PARA A TRILHA COM A MEDIÇÃO JUNTO. É ela que responde
--      "quanto faltava, e está subindo?" daqui a três meses.

\set ON_ERROR_STOP on

create or replace function teste_assert_vp(p_ok boolean, p_nome text, p_detalhe text default null)
returns void language plpgsql as $$
begin
  if p_ok then
    raise notice 'ok    %', p_nome;
  else
    raise exception 'FALHOU: % %', p_nome, coalesce(' — ' || p_detalhe, '');
  end if;
end $$;

-- Emite N vereditos de revisão de documento: `p_acertos` deles confirmando o
-- tipo sugerido e o resto corrigindo. É o formato que `fn_revisar_documento`
-- grava, e o teste escreve direto em `decisao` de propósito — o caminho completo
-- de revisão já é coberto pela suíte dele, e aqui o que está sob teste é a
-- LEITURA desse rastro.
create or replace function teste_vp_semear(p_caso uuid, p_tipo text, p_n int, p_acertos int)
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
  v_caso    uuid;
  v_r       jsonb;
  v_dial    jsonb;
  v_base    text;
  v_nivel   text;
  v_n       int;
begin
  raise notice '--- 0. o estado de partida ---';

  insert into caso (nome, produto) values ('Teste veredito 0136', 'reestruturacao')
    returning id into v_caso;

  -- O dial da classificação nasce em N1 com teto N2 (0002), que é exatamente a
  -- subida que esta migration passa a poder autorizar.
  update estagio_autonomia set nivel_atual = 'N1', base_do_nivel = 'nao_se_aplica'
   where estagio = 'classificacao_doc_checklist';

  delete from decisao where autor = 'analista:teste';

  raise notice '--- 1. estágio sem fonte de veredito RECUSA nomeando a falta ---';

  v_r := fn_veredito_producao('extracao_linhas_financeiras');
  perform teste_assert_vp(
    (v_r->>'suficiente')::boolean is false,
    'estágio sem veredito de produção não é suficiente');
  perform teste_assert_vp(
    v_r->>'motivo' like '%não emite rótulo%',
    'e o motivo diz que o trabalho normal não produz rótulo sobre ele',
    v_r::text);
  perform teste_assert_vp(
    v_r->'concordancia' is null,
    'sem fonte, não existe concordância — nem zero, que seria uma afirmação');

  v_r := fn_veredito_producao('estagio_que_nao_existe');
  perform teste_assert_vp(
    (v_r->>'suficiente')::boolean is false and v_r->>'motivo' like '%não existe no dial%',
    'estágio inexistente recusa em vez de estourar');

  raise notice '--- 2. massa insuficiente reprova, mesmo com acerto perfeito ---';

  -- Cinco vereditos, todos certos. Concordância 1,0 e mínimo 0,95: passaria pela
  -- concordância e não pode passar pelo N.
  perform teste_vp_semear(v_caso, 'balanco_patrimonial', 5, 5);
  v_r := fn_veredito_producao('classificacao_doc_checklist');
  perform teste_assert_vp(
    (v_r->>'concordancia')::numeric = 1.0,
    'concordância de 5/5 é 1,0', v_r::text);
  perform teste_assert_vp(
    (v_r->>'suficiente')::boolean is false,
    'e mesmo assim NÃO é suficiente: cinco vereditos não afirmam nada');
  perform teste_assert_vp(
    v_r->'falhas'->>0 like '%vereditos de produção: 5, mínimo 30%',
    'a falha nomeia o número que faltou, não o campo', v_r::text);

  raise notice '--- 3. o dial recusa a subida e a trilha guarda a medição ---';

  select count(*) into v_n from evento_auditoria
   where acao = 'mudanca_dial_recusada' and entidade_ref = 'estagio:classificacao_doc_checklist';

  v_r := fn_mudar_dial('classificacao_doc_checklist', 'N2', 'analista:teste',
                       'tentativa com pouco veredito', null, null, null, true);
  perform teste_assert_vp(
    (v_r->>'recusado')::boolean is true,
    'o dial recusa subir com veredito insuficiente');
  perform teste_assert_vp(
    v_r->>'motivo_recusa' like '%PISO%',
    'e a recusa lembra que este caminho mede um piso', v_r::text);
  perform teste_assert_vp(
    (select count(*) from evento_auditoria
      where acao = 'mudanca_dial_recusada'
        and entidade_ref = 'estagio:classificacao_doc_checklist') = v_n + 1,
    'a tentativa recusada entrou na trilha');
  perform teste_assert_vp(
    (select depois->'medicao'->>'n' from evento_auditoria
      where acao = 'mudanca_dial_recusada'
        and entidade_ref = 'estagio:classificacao_doc_checklist'
      order by criado_em desc, id desc limit 1) = '5',
    'e a trilha guardou QUANTO faltava, não só que faltou');
  perform teste_assert_vp(
    (fn_dial('classificacao_doc_checklist')->>'nivel_atual') = 'N1',
    'o nível não se moveu');

  raise notice '--- 4. massa suficiente com concordância baixa também reprova ---';

  delete from decisao where autor = 'analista:teste';
  -- 40 vereditos, 30 certos: 0,75 contra o mínimo de 0,95.
  perform teste_vp_semear(v_caso, 'balanco_patrimonial', 40, 30);
  v_r := fn_veredito_producao('classificacao_doc_checklist');
  perform teste_assert_vp(
    (v_r->>'n')::int = 40 and (v_r->>'concordancia')::numeric = 0.75,
    '40 vereditos, concordância 0,75', v_r::text);
  perform teste_assert_vp(
    (v_r->>'suficiente')::boolean is false
      and array_to_string(array(select jsonb_array_elements_text(v_r->'falhas')), ' ') like '%0.7500%',
    'reprova nomeando a concordância medida', v_r::text);

  raise notice '--- 5. com massa e concordância, o dial SOBE — e a base diz de onde veio ---';

  delete from decisao where autor = 'analista:teste';
  -- 40 vereditos, 39 certos: 0,975 contra o mínimo de 0,95.
  perform teste_vp_semear(v_caso, 'balanco_patrimonial', 40, 39);
  v_r := fn_veredito_producao('classificacao_doc_checklist');
  perform teste_assert_vp(
    (v_r->>'suficiente')::boolean is true,
    '40 vereditos a 0,975 são suficientes', v_r::text);
  perform teste_assert_vp(
    (v_r->>'piso_enviesado')::boolean is true and v_r->>'como_ler' like '%PISO%',
    'e o número se declara piso enviesado no próprio retorno');

  v_dial := fn_mudar_dial('classificacao_doc_checklist', 'N2', 'analista:teste',
                          'subida por veredito de produção', null, null, null, true);
  perform teste_assert_vp(
    v_dial->>'nivel_atual' = 'N2',
    'o dial sobe para N2');

  select base_do_nivel into v_base from estagio_autonomia where estagio = 'classificacao_doc_checklist';
  perform teste_assert_vp(
    v_base = 'medida_por_veredito',
    'a base é medida_por_veredito', coalesce(v_base, '(null)'));

  raise notice '--- 6. E A BASE NÃO PODE SER "medida" — o assert que protege a honestidade ---';

  perform teste_assert_vp(
    v_base <> 'medida',
    'veredito de produção NUNCA vira "medida": rótulo enviesado não é rótulo cego');
  perform teste_assert_vp(
    (select medicao_rodada_id from estagio_autonomia
      where estagio = 'classificacao_doc_checklist') is null,
    'e não aponta rodada nenhuma, porque não houve rodada');
  perform teste_assert_vp(
    (select medicao_resumo->>'fonte' from estagio_autonomia
      where estagio = 'classificacao_doc_checklist') like '%fn_revisar_documento%',
    'o resumo guarda a FONTE do rótulo, que é o que permite duvidar dele depois');

  raise notice '--- 7. o teto continua inegociável, e descer continua livre ---';

  -- Classe B/C tem teto N1 (0002) e nenhum veredito o sobe.
  v_r := fn_mudar_dial('reconciliacao_classe_bc', 'N2', 'analista:teste',
                       'tentativa acima do teto', null, null, null, true);
  perform teste_assert_vp(
    (v_r->>'recusado')::boolean is true and v_r->>'motivo_recusa' like '%TETO%',
    'nenhuma quantidade de veredito passa do teto da natureza do estágio');

  v_dial := fn_mudar_dial('classificacao_doc_checklist', 'N0', 'analista:teste', 'freio');
  perform teste_assert_vp(
    v_dial->>'nivel_atual' = 'N0',
    'descer não pede evidência nenhuma');
  select base_do_nivel into v_base from estagio_autonomia where estagio = 'classificacao_doc_checklist';
  perform teste_assert_vp(
    v_base = 'nao_se_aplica',
    'e a base de medição não sobrevive à descida', coalesce(v_base, '(null)'));

  raise notice '--- 8. o tipo mais fraco governa quando tem massa ---';

  delete from decisao where autor = 'analista:teste';
  -- Um tipo ótimo e com massa, outro ruim e com massa: o estágio inteiro reprova.
  perform teste_vp_semear(v_caso, 'balanco_patrimonial', 40, 40);
  perform teste_vp_semear(v_caso, 'dre', 20, 10);
  v_r := fn_veredito_producao('classificacao_doc_checklist');
  perform teste_assert_vp(
    (v_r->>'concordancia')::numeric >= 0.83,
    'a média dos dois tipos passaria de 0,80', v_r::text);
  perform teste_assert_vp(
    (v_r->>'suficiente')::boolean is false
      and jsonb_array_length(v_r->'tipos_abaixo_do_minimo') = 1,
    'e o estágio reprova por causa do tipo fraco, que a média escondia', v_r::text);

  -- Tipo raro NÃO reprova sozinho: sem massa ele não afirma nada.
  delete from decisao where autor = 'analista:teste';
  perform teste_vp_semear(v_caso, 'balanco_patrimonial', 40, 39);
  perform teste_vp_semear(v_caso, 'certidao', 2, 0);
  v_r := fn_veredito_producao('classificacao_doc_checklist');
  perform teste_assert_vp(
    jsonb_array_length(v_r->'tipos_abaixo_do_minimo') = 0,
    'dois vereditos de um tipo raro não reprovam o estágio inteiro', v_r::text);

  raise notice '--- 9. limpeza e volta ao estado de partida ---';

  delete from decisao where autor = 'analista:teste';
  delete from caso where id = v_caso;
  update estagio_autonomia set nivel_atual = 'N1', base_do_nivel = 'nao_se_aplica',
                               medicao_em = null, medicao_resumo = null
   where estagio = 'classificacao_doc_checklist';

  raise notice 'veredito de producao OK — não medido distinguido de medido e ruim; massa antes de '
               'concordância; a base nunca vira "medida"; o teto e o freio intactos';
end $$;

drop function teste_vp_semear(uuid, text, int, int);
drop function teste_assert_vp(boolean, text, text);
