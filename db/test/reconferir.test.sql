-- Testes de "reaplicar as regras de hoje sobre o dado já gravado" (0043).
-- Rodar via db/test/run.sh (que aplica as migrations antes).
--
-- O QUE ESTE ARQUIVO PROVA, e por que ele existe.
--
-- Os prints do Teste v35 mostravam duas pendências que pareciam defeito vivo:
-- "falta o Passivo+PL" numa mensagem que LISTAVA `PASSIVO E PATRIMÔNIO LÍQUIDO`
-- entre os rótulos extraídos, e "4 contas com o MESMO valor material (14529)" —
-- que são os ATIVOs iguais ao Passivo+PL por construção contábil. As duas são o
-- que a 0034 fechou.
--
-- O cenário 1 abaixo é a REPRODUÇÃO da forma exata daquele dado (rótulos e
-- colunas como a extração real os produziu, inclusive `31/12/2024`), e prova que
-- as regras de hoje devolvem `ok`. Ou seja: aquilo era achado de REGRA VELHA, e o
-- defeito real é que nada reavaliava pendência gravada quando a regra mudava.
--
-- Os cenários seguintes provam que `fn_reconferir_caso` fecha o achado velho SEM
-- gastar IA e — a parte que importa — que ele NÃO fecha achado de verdade.

\set ON_ERROR_STOP on

create or replace function teste_assert_rec(p_ok boolean, p_nome text, p_detalhe text default null)
returns void language plpgsql as $$
begin
  if p_ok then
    raise notice 'ok    %', p_nome;
  else
    raise exception 'FALHOU: % %', p_nome, coalesce(' — ' || p_detalhe, '');
  end if;
end $$;

do $$
declare
  v_caso uuid;
  v_doc  uuid;
  v_ver  uuid;
  v_r    jsonb;
  v_n    int;
  v_txt  text;
  v_ent  uuid;
  v_per  uuid;
  v_caso_b uuid;
begin
  raise notice '--- 1. a forma EXATA do v35 reconcilia OK com as regras de hoje ---';
  v_caso := (fn_upsert_caso('Reconferir: forma do v35'))::uuid;
  v_r := fn_registrar_documento(v_caso, 'REPRO VERTENTES S.A.', 'multi', '24,25', 'BALANCO', 0.95,
    'nome_arquivo', 'supabase_storage', 'b/bp.pdf', 'BP REPRO.pdf', true, 'HASH-REC-1', 'ok');
  v_ver := (v_r->>'documento_versao_id')::uuid;

  -- Rótulos e colunas como a extração REAL os escreveu (dos prints): o total do
  -- grupo sem a palavra "total" e a coluna de período em formato de data. É a
  -- combinação que a 0033 diagnosticava e a 0034 passou a resolver.
  perform fn_registrar_campos_extraidos(v_ver, jsonb_build_array(
    jsonb_build_object('ordem',0,'chave','ATIVO','valor_num','49969','periodo_coluna','31/12/2024','confianca','0.97'),
    jsonb_build_object('ordem',1,'chave','Ativo Circulante','valor_num','920','periodo_coluna','31/12/2024','confianca','0.97'),
    jsonb_build_object('ordem',2,'chave','Ativo Não Circulante','valor_num','49049','periodo_coluna','31/12/2024','confianca','0.97'),
    jsonb_build_object('ordem',3,'chave','Passivo Circulante','valor_num','2194','periodo_coluna','31/12/2024','confianca','0.97'),
    jsonb_build_object('ordem',4,'chave','PASSIVO E PATRIMÔNIO LÍQUIDO','valor_num','49969','periodo_coluna','31/12/2024','confianca','0.97'),
    jsonb_build_object('ordem',5,'chave','ATIVO','valor_num','35284','periodo_coluna','31/12/2025','confianca','0.97'),
    jsonb_build_object('ordem',6,'chave','Ativo Circulante','valor_num','250','periodo_coluna','31/12/2025','confianca','0.97'),
    jsonb_build_object('ordem',7,'chave','Ativo Não Circulante','valor_num','35034','periodo_coluna','31/12/2025','confianca','0.97'),
    jsonb_build_object('ordem',8,'chave','Passivo Circulante','valor_num','4594','periodo_coluna','31/12/2025','confianca','0.97'),
    jsonb_build_object('ordem',9,'chave','PASSIVO E PATRIMÔNIO LÍQUIDO','valor_num','35284','periodo_coluna','31/12/2025','confianca','0.97')
  ), 'N2');

  select id, entidade_id, periodo_id into v_doc, v_ent, v_per from documento where caso_id = v_caso limit 1;
  v_r := fn_reconciliar_ativo_passivo_pl(v_caso, v_ent, v_per);
  perform teste_assert_rec((v_r->>'resultado') = 'ok',
    'A.1 devolve ok sobre o dado que no v35 aparecia como "falta o Passivo+PL"', v_r::text);

  perform teste_assert_rec(
    not exists (select 1 from pendencia where caso_id = v_caso
                and tipo = 'precondicao_nao_satisfeita' and estado <> 'resolvida'),
    'e nenhuma pré-condição fica aberta');

  raise notice '--- 2. o Sinal 1 NÃO acusa os quatro totais estruturais ---';
  -- ATIVO = TOTAL DO ATIVO = PASSIVO E PL = TOTAL DO PASSIVO E PL, todos 35284:
  -- quatro rótulos com o mesmo valor material, que é o padrão que o Sinal 1
  -- procura — e que aqui é identidade contábil, não alucinação.
  v_r := fn_registrar_documento(v_caso, 'REPRO VERTENTES S.A.', 'anual', '2025', 'BALANCO', 0.95,
    'nome_arquivo', 'supabase_storage', 'b/bp2.pdf', 'BP REPRO 2.pdf', true, 'HASH-REC-2', 'ok');
  v_ver := (v_r->>'documento_versao_id')::uuid;
  perform fn_registrar_campos_extraidos(v_ver, jsonb_build_array(
    jsonb_build_object('ordem',0,'chave','ATIVO','valor_num','35284','periodo_coluna','2025','confianca','0.97'),
    jsonb_build_object('ordem',1,'chave','TOTAL DO ATIVO','valor_num','35284','periodo_coluna','2025','confianca','0.97'),
    jsonb_build_object('ordem',2,'chave','PASSIVO E PATRIMÔNIO LÍQUIDO','valor_num','35284','periodo_coluna','2025','confianca','0.97'),
    jsonb_build_object('ordem',3,'chave','TOTAL DO PASSIVO E DO PATRIMÔNIO LÍQUIDO','valor_num','35284','periodo_coluna','2025','confianca','0.97'),
    jsonb_build_object('ordem',4,'chave','Ativo Circulante','valor_num','250','periodo_coluna','2025','confianca','0.97')
  ), 'N2');

  v_r := fn_avaliar_guardas_extracao(v_ver);
  perform teste_assert_rec((v_r->>'padrao_suspeito')::boolean = false,
    'os quatro totais estruturais com 35284 NÃO disparam o Sinal 1 (0034)', v_r::text);

  raise notice '--- 3. e ele CONTINUA acusando repetição de verdade ---';
  -- O mesmo valor material em quatro contas COMUNS: é o padrão de fabricação que
  -- a guarda existe para pegar. Se este assert cair, a 0034 (ou a 0043) afrouxou
  -- a guarda em vez de refiná-la.
  -- Caso PRÓPRIO: este documento não tem nenhum dos dois lados do balanço, então
  -- a reconciliação abre uma pré-condição LEGÍTIMA nele — e ela poluiria a
  -- contagem de "achados de regra velha" do cenário 4 se ficasse no mesmo caso.
  v_caso_b := (fn_upsert_caso('Reconferir: repetição de verdade'))::uuid;
  v_r := fn_registrar_documento(v_caso_b, 'REPETE LTDA.', 'anual', '2023', 'BALANCO', 0.95,
    'nome_arquivo', 'supabase_storage', 'b/bp3.pdf', 'BP REPRO 3.pdf', true, 'HASH-REC-3', 'ok');
  v_ver := (v_r->>'documento_versao_id')::uuid;
  perform fn_registrar_campos_extraidos(v_ver, jsonb_build_array(
    jsonb_build_object('ordem',0,'chave','Clientes','valor_num','9000','periodo_coluna','2023','confianca','0.99'),
    jsonb_build_object('ordem',1,'chave','Estoques','valor_num','9000','periodo_coluna','2023','confianca','0.99'),
    jsonb_build_object('ordem',2,'chave','Adiantamentos','valor_num','9000','periodo_coluna','2023','confianca','0.99'),
    jsonb_build_object('ordem',3,'chave','Outros créditos','valor_num','9000','periodo_coluna','2023','confianca','0.99')
  ), 'N2');
  v_r := fn_avaliar_guardas_extracao(v_ver);
  perform teste_assert_rec((v_r->>'padrao_suspeito')::boolean,
    'quatro contas COMUNS com o mesmo valor continuam disparando', v_r::text);
  perform teste_assert_rec(v_r->'rotulos_repetindo' @> '["Clientes"]'::jsonb,
    'e a guarda NOMEIA as contas que repetiram — sem os nomes não dá para julgar da tela',
    v_r->>'rotulos_repetindo');

  raise notice '--- 4. reconferir FECHA o achado de regra velha, sem gastar IA ---';
  -- Uma pendência na forma exata em que a regra ANTIGA a gravou: mesma checagem,
  -- mesma entidade/período (é assim que `fn_registrar_reconciliacao` a encontra).
  select d.id, d.entidade_id, d.periodo_id into v_doc, v_ent, v_per
  from documento d where d.caso_id = v_caso order by d.criado_em limit 1;

  insert into pendencia (caso_id, origem_estagio, tipo, severidade, sobrepujavel, descricao,
                         documento_id, entidade_id, periodo_id, motivo)
    values (v_caso, 'reconciliacao', 'precondicao_nao_satisfeita', 'importante', true,
      'O Balanço foi encontrado, mas nenhum exercício teve os DOIS lados. 2024: falta o Passivo+PL '
      '(coluna de entidade: (qualquer); coluna de período: 31/12/2024)',
      v_doc, v_ent, v_per, 'reconciliacao:ativo_passivo_pl');
  insert into pendencia (caso_id, origem_estagio, tipo, severidade, sobrepujavel, descricao,
                         documento_id, motivo)
    values (v_caso, 'extracao', 'extracao_padrao_suspeito', 'importante', true,
      '4 contas diferentes, na MESMA coluna, vieram com o MESMO valor material (35284)',
      v_doc, 'extracao:padrao_suspeito:' || v_doc);

  -- Escopo por DOCUMENTO: o cenário 3 deixou uma pendência de repetição REAL
  -- aberta em outro documento, e ela tem de continuar lá (cenário 5).
  select count(*) into v_n from pendencia
    where caso_id = v_caso and estado <> 'resolvida' and documento_id = v_doc
      and tipo in ('precondicao_nao_satisfeita','extracao_padrao_suspeito');
  perform teste_assert_rec(v_n = 2, 'as duas pendências velhas estão abertas', format('abertas: %s', v_n));

  v_r := fn_reconferir_caso(v_caso, 'teste:reconferir');
  perform teste_assert_rec((v_r->>'achados_de_regra_velha')::int = 2,
    'reconferir fecha os dois achados que a regra de hoje não abriria', v_r::text);

  select count(*) into v_n from pendencia
    where caso_id = v_caso and estado <> 'resolvida' and documento_id = v_doc
      and tipo in ('precondicao_nao_satisfeita','extracao_padrao_suspeito');
  perform teste_assert_rec(v_n = 0, 'e nenhuma das duas segue aberta', format('ainda abertas: %s', v_n));

  -- Quem fechou fica dito: reavaliação NÃO é revisão humana, e confundir as duas
  -- na trilha faria parecer que alguém conferiu o arquivo.
  select string_agg(distinct resolvida_por, ' | ') into v_txt from pendencia
    where caso_id = v_caso and estado = 'resolvida' and documento_id = v_doc
      and tipo in ('precondicao_nao_satisfeita','extracao_padrao_suspeito');
  perform teste_assert_rec(v_txt like '%reconferir%' or v_txt like '%sistema:reconciliacao%',
    'e a trilha diz que foi reavaliação, não revisão humana', coalesce(v_txt,'(null)'));

  perform teste_assert_rec(
    exists (select 1 from evento_auditoria where acao = 'reconferir_caso'
            and entidade_ref = 'caso:'||v_caso and ator = 'teste:reconferir'),
    'e o reconferir fica registrado em evento_auditoria');

  raise notice '--- 5. reconferir NÃO fecha achado de VERDADE ---';
  -- Este é o assert que impede o reconferir de virar "limpar a tela": o documento
  -- do cenário 3 tem repetição real, e ela precisa sobreviver à reavaliação.
  v_r := fn_reconferir_caso(v_caso_b, 'teste:reconferir');
  perform teste_assert_rec(
    exists (select 1 from pendencia where caso_id = v_caso_b
            and tipo = 'extracao_padrao_suspeito' and estado <> 'resolvida'),
    'a repetição REAL do cenário 3 SOBREVIVE ao reconferir', v_r::text);
  perform teste_assert_rec((v_r->>'achados_de_regra_velha')::int = 0,
    'e o reconferir não reporta achado de regra velha onde não havia', v_r::text);

  raise notice '--- 6. reconferir num caso inexistente é RECUSA, não exceção ---';
  v_r := fn_reconferir_caso('00000000-0000-0000-0000-000000000000'::uuid, 'teste:reconferir');
  perform teste_assert_rec((v_r->>'recusado') = 'true',
    'caso inexistente devolve recusa no payload', v_r::text);

  raise notice 'TODOS OS TESTES DE RECONFERIR PASSARAM';
end $$;
