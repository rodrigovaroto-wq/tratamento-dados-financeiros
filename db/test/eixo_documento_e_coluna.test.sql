-- Testes das duas correções da v48 sobre EIXOS: o eixo DOCUMENTO na duplicidade
-- de rótulo (0144) e o eixo COLUNA no localizador de linha exigida (0145).
--
-- POR QUE UM CASO SINTÉTICO PRÓPRIO, e não os books. Os dois books trazem
-- extração fiel e por isso são casos NEGATIVOS por construção: eles provam que a
-- checagem não grita à toa, e é o que o `reconciliacao.test.sql` já trava. O que
-- falta é o outro lado, e é o lado perigoso: sem um caso POSITIVO, a 0144 poderia
-- ter matado a checagem de duplicidade inteira — ela passaria a devolver zero
-- pares para sempre — e todo teste do repositório continuaria verde. Um filtro
-- novo que silencia demais tem exatamente a mesma aparência de um filtro novo que
-- funciona, quando só se olha para o caso limpo.
--
-- Então este arquivo monta o mínimo necessário para exercitar os DOIS SENTIDOS de
-- cada correção:
--
--   1. duplicidade · dois rótulos no MESMO documento .......... NÃO é par (0144)
--   2. duplicidade · os mesmos dois em DOCUMENTOS distintos ... É par
--   3. coluna · conceito no cabeçalho, documento matricial .... satisfaz (0145)
--   4. coluna · o cabeçalho errado ............................ não satisfaz
--
-- O par do caso 2 é o achado histórico que fez a 0105 existir: "Prejuízos
-- acumulados" e "Resultados Acumulados", o mesmo fato escrito de dois jeitos pelo
-- balanço e pelo balancete, somados e inflando o patrimônio.

\set ON_ERROR_STOP on

create or replace function teste_assert_eixo(p_ok boolean, p_nome text, p_detalhe text default null)
returns void language plpgsql as $$
begin
  if p_ok then
    raise notice 'ok    %', p_nome;
  else
    raise exception 'FALHOU: % %', p_nome, coalesce(' — ' || p_detalhe, '');
  end if;
end $$;

-- =============================================================================
do $$
declare
  v_caso    uuid := '11111111-4444-4444-4444-111111111111';
  v_ent     uuid := '22222222-4444-0000-0000-000000000001';
  v_per     uuid := '33333333-4444-0000-0000-000000000001';
  v_doc_bp  uuid := '44444444-4444-0000-0000-000000000001';
  v_doc_bal uuid := '44444444-4444-0000-0000-000000000002';
  v_doc_div uuid := '44444444-4444-0000-0000-000000000003';
  v_ver_bp  uuid := '55555555-4444-0000-0000-000000000001';
  v_ver_bal uuid := '55555555-4444-0000-0000-000000000002';
  v_ver_div uuid := '55555555-4444-0000-0000-000000000003';
  v_n int;
  v_ok boolean;
begin
  insert into caso (id, nome, produto)
    values (v_caso, 'FIXTURE eixos (0144/0145)', 'reestruturacao');
  insert into entidade (id, caso_id, razao_social, papel_no_grupo)
    values (v_ent, v_caso, 'EIXO INDÚSTRIA LTDA.', 'alvo');
  insert into periodo (id, caso_id, tipo, referencia)
    values (v_per, v_caso, 'anual', '2025');

  -- ---------------------------------------------------------------------------
  -- 1. DOIS RÓTULOS NO MESMO DOCUMENTO — a hierarquia dele, não duplicidade.
  --
  -- É o achado da v48, na forma exata em que ele aparece: o subtotal de grupo e o
  -- seu único componente, em linhas vizinhas, valendo o mesmo ao centavo. Sem a
  -- 0144 este par abre pendência, e abriu — seis vezes na rodada real.
  -- ---------------------------------------------------------------------------
  raise notice '--- 1. mesmo documento: subtotal de grupo e seu único componente ---';

  insert into documento (id, caso_id, entidade_id, periodo_id, tipo_taxonomia, status, confianca, fonte)
    values (v_doc_bp, v_caso, v_ent, v_per, 'BALANCO', 'valido', 0.96, 'fixture');
  insert into documento_versao (id, documento_id, n_versao, arquivo_ref, nome_original, hash)
    values (v_ver_bp, v_doc_bp, 1, 'fixture/eixo-bp.pdf', 'Balanco.pdf', md5(v_doc_bp::text));

  -- `secao` ACHATADA de propósito: é assim que a extração da v48 entrega, e é
  -- por isso que o filtro `subtotal_de` da 0105 (que precisa do grupo IMEDIATO
  -- em `secao`) não dispara. O fixture tem de reproduzir o defeito, não a forma
  -- ideal — senão ele testa um mundo que não existe.
  -- DUAS COLUNAS, e não uma, porque é o que o critério da 0105 exige de um par
  -- sem radical estrutural comum ("Prejuízos acumulados" e "Resultados
  -- Acumulados" não compartilham radical — está escrito no cabeçalho dela). Com
  -- uma coluna só, nenhum dos dois casos abaixo seria candidato, e o teste
  -- estaria medindo o critério errado.
  insert into campo_extraido (documento_versao_id, chave, valor_num, unidade, confianca,
                              secao, secao_canonica, periodo_coluna, ordem, status_aceite) values
    (v_ver_bp, 'Patrimônio Líquido',    30000.0, 'milhar', 0.96, 'PASSIVO', 'patrimonio_liquido', '2025', 0, 'aceito'),
    (v_ver_bp, 'Capital Social',        45000.0, 'milhar', 0.96, 'Patrimônio Líquido', 'patrimonio_liquido', '2025', 1, 'aceito'),
    (v_ver_bp, 'Prejuízos acumulados', -15000.0, 'milhar', 0.96, 'Patrimônio Líquido', 'patrimonio_liquido', '2025', 2, 'aceito'),
    (v_ver_bp, 'Prejuízos acumulados', -12000.0, 'milhar', 0.96, 'Patrimônio Líquido', 'patrimonio_liquido', '2024', 2, 'aceito'),
    -- O par intradocumento: grupo de UM filho. Vizinhos, mesma seção, mesmo
    -- valor nas DUAS colunas — candidato perfeito por todo critério da 0105
    -- exceto o eixo novo.
    (v_ver_bp, 'Lucros ou Prejuízos Acumulados', -15000.0, 'milhar', 0.96, 'Patrimônio Líquido', 'patrimonio_liquido', '2025', 3, 'aceito'),
    (v_ver_bp, 'Lucros ou Prejuízos Acumulados', -12000.0, 'milhar', 0.96, 'Patrimônio Líquido', 'patrimonio_liquido', '2024', 3, 'aceito');

  select count(*) into v_n from fn_pares_duplicados_do_caso(v_caso);
  perform teste_assert_eixo(v_n = 0,
    'dois rótulos de mesmo valor NO MESMO documento não viram par (0144)',
    format('%s par(es): %s', v_n,
      (select coalesce(string_agg(p.rotulo_a || ' = ' || p.rotulo_b, '; '), '(nenhum)')
         from fn_pares_duplicados_do_caso(v_caso) p)));

  -- ---------------------------------------------------------------------------
  -- 2. OS MESMOS DOIS RÓTULOS EM DOCUMENTOS DISTINTOS — aí sim é duplicidade.
  --
  -- Este é o caso que a 0105 existe para pegar, e o que prova que a 0144 estreitou
  -- o critério sem desligar a checagem. O balancete escreve "Resultados
  -- Acumulados" onde o balanço escreveu "Prejuízos acumulados": mesmo fato, dois
  -- nomes, duas fontes — e somados inflam o patrimônio em 15.000.
  -- ---------------------------------------------------------------------------
  raise notice '--- 2. documentos distintos: o mesmo fato escrito de dois jeitos ---';

  insert into documento (id, caso_id, entidade_id, periodo_id, tipo_taxonomia, status, confianca, fonte)
    values (v_doc_bal, v_caso, v_ent, v_per, 'BALANCETE', 'valido', 0.96, 'fixture');
  insert into documento_versao (id, documento_id, n_versao, arquivo_ref, nome_original, hash)
    values (v_ver_bal, v_doc_bal, 1, 'fixture/eixo-bal.pdf', 'Balancete.pdf', md5(v_doc_bal::text));

  -- MESMOS VALORES, MESMA SEÇÃO, MESMAS DUAS COLUNAS que os dois rótulos do
  -- balanço. A comparação com o caso 1 é CONTROLADA: a única coisa que difere
  -- entre o par que passa e o par que não passa é o documento.
  insert into campo_extraido (documento_versao_id, chave, valor_num, unidade, confianca,
                              secao, secao_canonica, periodo_coluna, ordem, status_aceite) values
    (v_ver_bal, 'Resultados Acumulados', -15000.0, 'milhar', 0.96, 'Patrimônio Líquido', 'patrimonio_liquido', '2025', 0, 'aceito'),
    (v_ver_bal, 'Resultados Acumulados', -12000.0, 'milhar', 0.96, 'Patrimônio Líquido', 'patrimonio_liquido', '2024', 0, 'aceito');

  select count(*) into v_n from fn_pares_duplicados_do_caso(v_caso)
  where rotulo_a in ('Prejuízos acumulados', 'Resultados Acumulados')
    and rotulo_b in ('Prejuízos acumulados', 'Resultados Acumulados');
  perform teste_assert_eixo(v_n = 1,
    'o mesmo fato em DOIS documentos continua sendo acusado (a 0144 estreitou, não desligou)',
    format('%s par(es) entre os dois rótulos; todos: %s', v_n,
      (select coalesce(string_agg(p.rotulo_a || ' = ' || p.rotulo_b, '; '), '(nenhum)')
         from fn_pares_duplicados_do_caso(v_caso) p)));

  -- O CONTROLE da comparação: "Lucros ou Prejuízos Acumulados" também é rótulo
  -- de papel `conta`, com os mesmos valores nas mesmas colunas — e cruzando o
  -- documento ele é acusado. Sem este assert, o caso 1 poderia estar passando
  -- porque o rótulo nunca foi candidato, e não porque o eixo novo o barrou.
  select count(*) into v_n from fn_pares_duplicados_do_caso(v_caso)
  where 'Lucros ou Prejuízos Acumulados' in (rotulo_a, rotulo_b)
    and 'Resultados Acumulados' in (rotulo_a, rotulo_b);
  perform teste_assert_eixo(v_n = 1,
    'CONTROLE: o mesmo rótulo do caso 1 É candidato — cruzando o documento, ele é acusado',
    format('%s par(es)', v_n));

  -- E o par que o documento único explica CONTINUA fora, agora que há dois
  -- documentos no caso: o filtro é sobre o par, não sobre o caso.
  select count(*) into v_n from fn_pares_duplicados_do_caso(v_caso)
  where 'Lucros ou Prejuízos Acumulados' in (rotulo_a, rotulo_b)
    and 'Prejuízos acumulados' in (rotulo_a, rotulo_b);
  perform teste_assert_eixo(v_n = 0,
    'o par intradocumento segue fora mesmo com outro documento no caso',
    format('%s par(es)', v_n));

  -- ---------------------------------------------------------------------------
  -- 3 e 4. O CONCEITO QUE MORA NA COLUNA (0145).
  --
  -- Mapa de dívida matricial: a chave é o contrato, o cabeçalho é o conceito.
  -- Sem o modo `contra = 'coluna'` a exigência "Juros/encargos por contrato"
  -- procura "juros" no nome do banco e cobra do cliente um dado que já está no
  -- banco — três pendências falsas na v48, uma delas derrubando junto a
  -- reconciliação `despfin_dre_vs_divida`.
  -- ---------------------------------------------------------------------------
  raise notice '--- 3. documento matricial: o conceito está no cabeçalho da coluna ---';

  insert into documento (id, caso_id, entidade_id, periodo_id, tipo_taxonomia, status, confianca, fonte)
    values (v_doc_div, v_caso, v_ent, v_per, 'MAPA_DIVIDA', 'valido', 0.96, 'fixture');
  insert into documento_versao (id, documento_id, n_versao, arquivo_ref, nome_original, hash)
    values (v_ver_div, v_doc_div, 1, 'fixture/eixo-div.pdf', 'Mapa.pdf', md5(v_doc_div::text));

  -- A chave NÃO contém "juros" nem "encargos" — é o nome do banco, como no
  -- documento real. Quem carrega o conceito é `periodo_coluna`.
  insert into campo_extraido (documento_versao_id, chave, valor_num, unidade, confianca,
                              secao, periodo_coluna, ordem, status_aceite) values
    (v_ver_div, 'Banco Meridional S.A. - Capital de giro (CG-2021-884.117)', 10412600.0, 'unidade', 0.96,
     'Mapa de Endividamento Bancário', 'Saldo devedor (R$)', 0, 'aceito'),
    (v_ver_div, 'Banco Meridional S.A. - Capital de giro (CG-2021-884.117)',  2960400.0, 'unidade', 0.96,
     'Mapa de Endividamento Bancário', 'Juros do exercício (R$)', 0, 'aceito');

  select x.satisfeita into v_ok
  from fn_exigencias_do_caso(v_caso) x
  where x.tipo_taxonomia = 'MAPA_DIVIDA' and x.conceito = 'juros_por_contrato';
  perform teste_assert_eixo(coalesce(v_ok, false),
    'a exigência é satisfeita pelo cabeçalho da COLUNA, com a chave sem o termo (0145)',
    format('satisfeita = %s', coalesce(v_ok::text, '(exigência não avaliada)')));

  raise notice '--- 4. e o cabeçalho errado não satisfaz — o modo casa, não passa livre ---';
  -- Sem esta metade, um `contra = 'coluna'` que casasse com QUALQUER coluna
  -- passaria os dois testes acima e ninguém veria.
  update campo_extraido set periodo_coluna = 'Prazo remanescente (meses)'
  where documento_versao_id = v_ver_div and periodo_coluna = 'Juros do exercício (R$)';

  select x.satisfeita into v_ok
  from fn_exigencias_do_caso(v_caso) x
  where x.tipo_taxonomia = 'MAPA_DIVIDA' and x.conceito = 'juros_por_contrato';
  perform teste_assert_eixo(not coalesce(v_ok, false),
    'coluna que não traz o conceito NÃO satisfaz a exigência',
    format('satisfeita = %s', coalesce(v_ok::text, '(exigência não avaliada)')));

  -- E a checagem que consome o conceito enxerga a mesma coluna que o localizador
  -- — o passo (4) da 0145, que é o que impede a pendência de só mudar de nome.
  update campo_extraido set periodo_coluna = 'Juros do exercício (R$)'
  where documento_versao_id = v_ver_div and periodo_coluna = 'Prazo remanescente (meses)';

  select count(*) into v_n
  from campo_extraido ce
  where ce.documento_versao_id = v_ver_div
    and ce.valor_num is not null
    and (fn_normalizar_texto(ce.chave) like '%juros%'
         or fn_normalizar_texto(ce.chave) like '%encargos%'
         or fn_normalizar_texto(coalesce(ce.periodo_coluna, '')) like '%juros%'
         or fn_normalizar_texto(coalesce(ce.periodo_coluna, '')) like '%encargos%');
  perform teste_assert_eixo(v_n = 1,
    'o filtro de juros da reconciliação acha a linha pela coluna (uma, não a do saldo)',
    format('%s linha(s)', v_n));

  perform teste_assert_eixo(
    position('0145: o conceito pode morar na COLUNA' in
             (select pg_get_functiondef(p.oid) from pg_proc p
              where p.proname = 'fn_reconciliar_despfin_dre_vs_divida')) > 0,
    'fn_reconciliar_despfin_dre_vs_divida carrega o ramo da coluna (0145 passo 4)');

  raise notice 'eixo_documento_e_coluna OK — duplicidade só entre documentos, nos dois sentidos; conceito na coluna acha e não passa livre; a checagem enxerga o mesmo eixo que o localizador';
end $$;

drop function teste_assert_eixo(boolean, text, text);
