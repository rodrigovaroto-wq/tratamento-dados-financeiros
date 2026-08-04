-- Testes do PAPEL da linha na modelagem (db/migrations/0042).
-- Rodar via db/test/run.sh (que aplica as migrations antes).
--
-- O QUE ESTE ARQUIVO TRAVA. A rodada real (Teste v35) listou 236 linhas na tela de
-- Modelagem e tratou todas como conta projetável — subtotal ao lado dos seus
-- componentes, os 12 meses de faturamento como 12 contas, indicador gerencial
-- como dinheiro. As propriedades aqui, em ordem de gravidade:
--
--   1. SUBTOTAL não recebe premissa. É a dupla contagem, que é o defeito mais
--      caro deste projeto porque não parece erro — parece um número maior.
--   2. SÉRIE MENSAL não recebe premissa: ela alimenta a curva de sazonalidade.
--   3. O mês é lido por PALAVRA. `left(chave,3)` funcionava na fixture ("jan/2024")
--      e falhava no rótulo que a extração real escreveu ("Faturamento Janeiro") —
--      a curva de sazonalidade voltava VAZIA em produção com o teste verde.
--   4. Redutor aparece NEGATIVO. `max(abs())` mostrava `(-) Depreciação
--      acumulada` como +52.300 na coluna que decide a premissa.
--   5. A guarda mora no BANCO: recusa em fn_vincular_linha_premissa, não só na tela.

\set ON_ERROR_STOP on

create or replace function teste_assert_papel(p_ok boolean, p_nome text, p_detalhe text default null)
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
  v_ver  uuid;
  v_r    jsonb;
  v_n    int;
  v_txt  text;
  v_num  numeric;
begin
  raise notice '--- 1. fn_mes_do_rotulo lê a PALAVRA do mês, em qualquer posição ---';
  perform teste_assert_papel(fn_mes_do_rotulo('jan/2024') = 1, 'jan/2024 → 1');
  perform teste_assert_papel(fn_mes_do_rotulo('jan/2024 — jan/2025') = 1,
    'a forma que o PDF imprime ("jan/2024 — jan/2025") → 1');
  -- O rótulo que a extração REAL do v35 produziu. Com `left(chave,3)` isto era
  -- "fat" e a curva de sazonalidade do caso saía VAZIA — em produção, com a
  -- suíte verde, porque a fixture usava o rótulo que eu inventei.
  perform teste_assert_papel(fn_mes_do_rotulo('Faturamento Janeiro') = 1,
    'o rótulo REAL da extração ("Faturamento Janeiro") → 1');
  perform teste_assert_papel(fn_mes_do_rotulo('Faturamento Dezembro') = 12, 'Faturamento Dezembro → 12');
  -- E o falso positivo que um LIKE '%mar%' produziria.
  perform teste_assert_papel(fn_mes_do_rotulo('Marcas e patentes') is null,
    'Marcas e patentes NÃO é março (palavra inteira, não prefixo)');
  perform teste_assert_papel(fn_mes_do_rotulo('Materiais de manutenção e consumo') is null,
    'Materiais de manutenção NÃO é maio');
  perform teste_assert_papel(fn_mes_do_rotulo('TOTAL DO EXERCÍCIO') is null, 'TOTAL DO EXERCÍCIO não é mês');

  raise notice '--- 2. fn_papel_linha: subtotal, derivado, série mensal e conta ---';
  -- Subtotais REAIS do v35, com a grafia dos documentos.
  perform teste_assert_papel(fn_papel_linha('ATIVO') = 'subtotal', 'ATIVO é subtotal');
  perform teste_assert_papel(fn_papel_linha('TOTAL DO ATIVO') = 'subtotal', 'TOTAL DO ATIVO é subtotal');
  perform teste_assert_papel(fn_papel_linha('Ativo Circulante') = 'subtotal', 'Ativo Circulante é subtotal');
  perform teste_assert_papel(fn_papel_linha('Passivo Não Circulante') = 'subtotal', 'Passivo Não Circulante é subtotal');
  perform teste_assert_papel(fn_papel_linha('PASSIVO E PATRIMÔNIO LÍQUIDO') = 'subtotal',
    'PASSIVO E PATRIMÔNIO LÍQUIDO é subtotal');
  perform teste_assert_papel(fn_papel_linha('Patrimônio Líquido') = 'subtotal', 'Patrimônio Líquido é subtotal');
  perform teste_assert_papel(fn_papel_linha('RECEITA OPERACIONAL LÍQUIDA') = 'subtotal',
    'RECEITA OPERACIONAL LÍQUIDA é subtotal (receita menos deduções)');
  perform teste_assert_papel(fn_papel_linha('LUCRO BRUTO') = 'subtotal', 'LUCRO BRUTO é subtotal');
  perform teste_assert_papel(fn_papel_linha('PREJUÍZO LÍQUIDO DO EXERCÍCIO') = 'subtotal',
    'PREJUÍZO LÍQUIDO DO EXERCÍCIO é subtotal');
  perform teste_assert_papel(
    fn_papel_linha('Caixa líquido gerado pelas (aplicado nas) atividades operacionais') = 'subtotal',
    'o subtotal do Fluxo é subtotal');

  -- E as CONTAS que um filtro por substring pegaria por engano. Este bloco é o
  -- que impede a lista fechada de virar peneira: errar para subtotal ESCONDE a
  -- conta da tela, e o analista não descobre por quê.
  perform teste_assert_papel(fn_papel_linha('Créditos tributários - ICMS sobre ativo permanente') = 'conta',
    'conta que MENCIONA "ativo" continua conta');
  perform teste_assert_papel(fn_papel_linha('Provisão para passivo a descoberto de controlada') = 'conta',
    'conta que menciona "passivo" continua conta');
  perform teste_assert_papel(fn_papel_linha('Participação de não controladores (VT Logística — 30%)') = 'conta',
    'participação de não controladores é conta do PL, não o total dele');
  perform teste_assert_papel(fn_papel_linha('Duplicatas a receber de clientes - mercado interno') = 'conta',
    'duplicatas a receber é conta');
  perform teste_assert_papel(fn_papel_linha('Ajuste de avaliação patrimonial') = 'conta',
    'ajuste de avaliação patrimonial é conta (não é o total do patrimônio)');

  -- Derivados: indicador gerencial não é dinheiro.
  perform teste_assert_papel(fn_papel_linha('Índice de liquidez corrente') = 'derivado',
    'Índice de liquidez corrente é derivado');
  perform teste_assert_papel(fn_papel_linha('Média mensal 2024') = 'derivado', 'Média mensal é derivado');
  perform teste_assert_papel(fn_papel_linha('Ticket médio por pedido 2025') = 'derivado',
    'Ticket médio por pedido é derivado');
  perform teste_assert_papel(fn_papel_linha('Prazo médio de recebimento') = 'derivado',
    'Prazo médio de recebimento é derivado');
  perform teste_assert_papel(fn_papel_linha('Adiantamentos diversos') = 'conta',
    'e uma conta comum não é confundida com indicador');

  -- Série mensal: SÓ no documento de faturamento.
  perform teste_assert_papel(fn_papel_linha('Faturamento Janeiro', 'FATURAMENTO_24M') = 'serie_mensal',
    'Faturamento Janeiro no FATURAMENTO_24M é série mensal');
  perform teste_assert_papel(fn_papel_linha('Provisão de férias e 13º', 'BALANCO') = 'conta',
    'e um rótulo com palavra de mês num BALANÇO continua conta');
  perform teste_assert_papel(fn_papel_linha('jan/2024', 'BALANCO') = 'conta',
    'mês fora do documento de faturamento não vira série mensal');

  raise notice '--- 3. um caso real: papel, sinal e proveniência na lista ---';
  v_caso := (fn_upsert_caso('Papel da linha'))::uuid;
  v_r := fn_registrar_documento(v_caso, 'PAPEL LTDA.', 'anual', '2025', 'BALANCO', 0.95,
    'nome_arquivo', 'supabase_storage', 'b/bp.pdf', 'BP PAPEL.pdf', true, 'HASH-PAPEL-1', 'ok');
  v_ver := (v_r->>'documento_versao_id')::uuid;
  perform fn_registrar_campos_extraidos(v_ver, jsonb_build_array(
    jsonb_build_object('ordem',0,'chave','Ativo Circulante','valor_num','1000','unidade','milhar',
                       'moeda','BRL','confianca','0.97','secao_canonica','ativo_circulante'),
    jsonb_build_object('ordem',1,'chave','Clientes','valor_num','700','unidade','milhar',
                       'moeda','BRL','confianca','0.97','secao_canonica','ativo_circulante'),
    jsonb_build_object('ordem',2,'chave','Estoques','valor_num','400','unidade','milhar',
                       'moeda','BRL','confianca','0.97','secao_canonica','ativo_circulante'),
    -- Redutor: o documento imprime com sinal negativo, e a tela tem de mostrar isso.
    jsonb_build_object('ordem',3,'chave','(-) Depreciação acumulada','valor_num','-100','unidade','milhar',
                       'moeda','BRL','confianca','0.97','secao_canonica','ativo_nao_circulante'),
    jsonb_build_object('ordem',4,'chave','Índice de liquidez corrente','valor_num','0.65',
                       'confianca','0.97','secao_canonica','ativo_circulante')
  ), 'N2');

  select papel into v_txt from fn_linhas_para_modelagem(v_caso) where rotulo_norm = 'ativo circulante';
  perform teste_assert_papel(v_txt = 'subtotal', 'a lista marca Ativo Circulante como subtotal', v_txt);

  select valor_ultimo into v_num from fn_linhas_para_modelagem(v_caso)
    where rotulo_norm = fn_normalizar_texto('(-) Depreciação acumulada');
  perform teste_assert_papel(v_num = -100,
    'o redutor aparece NEGATIVO (era max(abs()) e mostrava +)', v_num::text);

  select unidade, moeda into v_txt, v_txt from fn_linhas_para_modelagem(v_caso)
    where rotulo_norm = 'clientes';
  select unidade into v_txt from fn_linhas_para_modelagem(v_caso) where rotulo_norm = 'clientes';
  perform teste_assert_papel(v_txt = 'milhar',
    'a unidade viaja com a linha (é o que impede somar milhar com real)', coalesce(v_txt,'(null)'));

  perform teste_assert_papel(
    (select documentos from fn_linhas_para_modelagem(v_caso) where rotulo_norm = 'clientes') @> array['BALANCO'],
    'e o documento de origem também — sem ele a duplicata sintético/analítico é indecidível');

  raise notice '--- 4. a SOBREPOSIÇÃO marcada é a real, não coincidência de valor ---';
  -- `Provisões` × `Provisão para passivo a descoberto de controlada` com o MESMO
  -- valor: o mesmo dinheiro em dois níveis de descrição (o caso do v35).
  -- `Fornecedores 4.861` × `Outras Obrigações 4.861`: valor igual por
  -- coincidência, NA MESMA SEÇÃO, conceitos sem relação — e marcar isso seria
  -- ensinar o analista a ignorar a marca.
  --
  -- O par coincidente TEM de estar na mesma seção: na primeira versão deste teste
  -- ele estava em seções diferentes, e aí o assert passava mesmo com o defeito
  -- religado — provava o filtro de seção, não a regra de contenção. Teste que não
  -- pode falhar não prova nada (CLAUDE.md), e este foi o caso.
  v_r := fn_registrar_documento(v_caso, 'PAPEL LTDA.', 'anual', '2024', 'BALANCO', 0.95,
    'nome_arquivo', 'supabase_storage', 'b/bp2.pdf', 'BP PAPEL 2.pdf', true, 'HASH-PAPEL-2', 'ok');
  v_ver := (v_r->>'documento_versao_id')::uuid;
  perform fn_registrar_campos_extraidos(v_ver, jsonb_build_array(
    jsonb_build_object('ordem',0,'chave','Provisões','valor_num','12399','unidade','milhar',
                       'confianca','0.97','secao_canonica','passivo_nao_circulante'),
    jsonb_build_object('ordem',1,'chave','Provisão para passivo a descoberto de controlada','valor_num','12399',
                       'unidade','milhar','confianca','0.97','secao_canonica','passivo_nao_circulante'),
    jsonb_build_object('ordem',2,'chave','Fornecedores','valor_num','4861','unidade','milhar',
                       'confianca','0.97','secao_canonica','passivo_circulante'),
    jsonb_build_object('ordem',3,'chave','Outras Obrigações','valor_num','4861','unidade','milhar',
                       'confianca','0.97','secao_canonica','passivo_circulante')
  ), 'N2');

  perform teste_assert_papel(
    (select sobreposicao_suspeita from fn_linhas_para_modelagem(v_caso) where rotulo_norm = 'provisoes'),
    'Provisões × Provisão para passivo a descoberto: marcada');
  perform teste_assert_papel(
    not (select sobreposicao_suspeita from fn_linhas_para_modelagem(v_caso) where rotulo_norm = 'fornecedores'),
    'Fornecedores 4.861 × Outras Obrigações 4.861 (MESMA seção, coincidência): NÃO marcada');

  raise notice '--- 5. a guarda de papel mora no BANCO ---';
  v_r := fn_ativar_premissa(v_caso, 'CRESC_REAL', '{"2026": 5}'::jsonb, 'digitado', 'teste');
  perform teste_assert_papel(coalesce((v_r->>'recusado')::boolean, false) = false,
    'premissa de teste ativada', v_r::text);

  v_r := fn_vincular_linha_premissa(v_caso, 'ativo_circulante', 'Ativo Circulante', null,
                                    'CRESC_REAL', 'teste');
  perform teste_assert_papel((v_r->>'recusado') = 'true',
    'vincular premissa a SUBTOTAL é recusado', v_r::text);
  perform teste_assert_papel((v_r->>'motivo_recusa') like '%soma dos componentes%',
    'e o motivo explica que no Excel ele sai como soma', v_r->>'motivo_recusa');

  v_r := fn_vincular_linha_premissa(v_caso, 'ativo_circulante', 'Índice de liquidez corrente', null,
                                    'CRESC_REAL', 'teste');
  perform teste_assert_papel((v_r->>'recusado') = 'true' and (v_r->>'papel') = 'derivado',
    'vincular premissa a DERIVADO é recusado', v_r::text);

  -- E a conta de verdade passa.
  v_r := fn_vincular_linha_premissa(v_caso, 'ativo_circulante', 'Clientes', null,
                                    'CRESC_REAL', 'teste');
  perform teste_assert_papel(coalesce((v_r->>'recusado')::boolean, false) = false,
    'e a CONTA é vinculada normalmente', v_r::text);

  -- DESVINCULAR nunca é bloqueado: limpar configuração antiga não pode depender
  -- de a linha ainda ser projetável (o rótulo pode ter mudado de papel).
  v_r := fn_vincular_linha_premissa(v_caso, 'ativo_circulante', 'Ativo Circulante', null, null, 'teste');
  perform teste_assert_papel(coalesce((v_r->>'recusado')::boolean, false) = false,
    'desvincular (premissa null) é sempre permitido', v_r::text);

  raise notice '--- 6. o lote pega as contas e DECLARA o que deixou de fora ---';
  v_r := fn_aplicar_premissa_em_lote(v_caso, 'ativo_circulante', 'CRESC_REAL', 'teste');
  -- ativo_circulante tem 5 linhas: Ativo Circulante (subtotal), Clientes,
  -- Estoques, Índice de liquidez (derivado) — o lote pega 2 e declara 2.
  perform teste_assert_papel((v_r->>'n_linhas')::int = 2,
    'o lote vinculou as CONTAS da seção', v_r::text);
  perform teste_assert_papel((v_r->>'n_ignoradas')::int = 2,
    'e deixou fora o subtotal e o indicador', v_r::text);
  perform teste_assert_papel(v_r->'ignoradas' @> '[{"papel": "subtotal"}]'::jsonb,
    'nomeando qual ficou de fora e por qual papel', v_r->>'ignoradas');

  raise notice '--- 7. a conferência conta o que é PROJETÁVEL ---';
  v_r := fn_conferir_modelagem(v_caso);
  select count(*) into v_n from fn_linhas_para_modelagem(v_caso) where papel = 'conta';
  perform teste_assert_papel((v_r->>'linhas_do_caso')::int = v_n,
    'o denominador é só de contas (era 236 no v35, incluindo o que nunca receberia premissa)',
    v_r::text);
  perform teste_assert_papel((v_r->'linhas_nao_projetaveis'->>'subtotal')::int >= 1,
    'e o que não é projetável fica NOMEADO por papel, não desaparece da conta',
    v_r->>'linhas_nao_projetaveis');

  raise notice '--- 8. sazonalidade com o rótulo REAL da extração ---';
  -- O defeito nº 3 do cabeçalho: com `left(chave,3)` esta curva vinha VAZIA.
  v_r := fn_registrar_documento(v_caso, 'PAPEL LTDA.', 'l24m', 'Últimos 24 meses', 'FATURAMENTO_24M', 0.95,
    'nome_arquivo', 'supabase_storage', 'b/fat.pdf', 'FAT PAPEL.pdf', true, 'HASH-PAPEL-3', 'ok');
  v_ver := (v_r->>'documento_versao_id')::uuid;
  perform fn_registrar_campos_extraidos(v_ver, (
    select jsonb_agg(jsonb_build_object(
      'ordem', i, 'chave', 'Faturamento ' || m, 'valor_num', (100 + i * 10)::text,
      'unidade','milhar','periodo_coluna','2025','confianca','0.97','secao_canonica','receita_bruta'))
    from unnest(array['Janeiro','Fevereiro','Março','Abril','Maio','Junho',
                      'Julho','Agosto','Setembro','Outubro','Novembro','Dezembro'])
      with ordinality as t(m, i)
  ), 'N2');

  select count(*) into v_n from fn_sazonalidade_do_caso(v_caso);
  perform teste_assert_papel(v_n = 12,
    'a curva sai com 12 meses a partir de "Faturamento <Mês>"', format('meses: %s', v_n));
  select round(sum(fracao), 6) into v_num from fn_sazonalidade_do_caso(v_caso);
  perform teste_assert_papel(v_num = 1, 'e as frações somam 1', v_num::text);

  -- E as 12 linhas mensais NÃO são projetáveis.
  select count(*) into v_n from fn_linhas_para_modelagem(v_caso) where papel = 'serie_mensal';
  perform teste_assert_papel(v_n = 12, 'as 12 linhas mensais ficam como serie_mensal', format('%s', v_n));
  v_r := fn_vincular_linha_premissa(v_caso, 'receita_bruta', 'Faturamento Janeiro', null,
                                    'CRESC_REAL', 'teste');
  perform teste_assert_papel((v_r->>'recusado') = 'true' and (v_r->>'papel') = 'serie_mensal',
    'e vincular premissa a linha mensal é recusado', v_r::text);

  raise notice '--- 9. premissa macro nasce com o valor do Focus ---';
  perform fn_definir_modelagem(v_caso, 'PAPEL LTDA.', 2025, 'IPCA', 'industria', 'teste', 5);
  v_r := fn_ativar_premissa(v_caso, 'IPCA', '{}'::jsonb, 'digitado', 'teste');
  perform teste_assert_papel((v_r->>'origem') = 'focus',
    'ativar IPCA sem valor traz a expectativa do Focus, com origem declarada', v_r::text);
  perform teste_assert_papel((v_r->'valores'->>'2026') is not null,
    'e o primeiro ano projetado vem preenchido', v_r->>'valores');

  -- Valor DIGITADO ganha do Focus: o analista pode estar usando cenário próprio,
  -- e sobrescrever escolha humana com default do sistema é o oposto da doutrina.
  v_r := fn_ativar_premissa(v_caso, 'IPCA', '{"2026": 9.9}'::jsonb, 'digitado', 'teste');
  perform teste_assert_papel((v_r->'valores'->>'2026') = '9.9' and (v_r->>'origem') = 'digitado',
    'e o valor digitado pelo analista NÃO é sobrescrito pelo Focus', v_r::text);

  raise notice 'TODOS OS TESTES DE PAPEL DA LINHA PASSARAM';
end $$;
