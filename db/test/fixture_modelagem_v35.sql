-- =============================================================================
-- Fixture de MODELAGEM com o caso REAL de produção — "Teste v35"
--
-- DE ONDE VEM ESTE DADO, e por que ele não foi inventado. As 249 linhas abaixo
-- foram extraídas de `test-data/capturas/2026-08-04-v35-modelagem/`, que é a
-- página de Modelagem renderizada pelo servidor em produção para o caso
-- `c4581e51-…`. Rótulo, seção, valor, unidade, número de ocorrências e tipos de
-- documento de origem são os que o extrator REALMENTE produziu — não os que
-- alguém escreveu à mão imaginando o formato.
--
-- POR QUE ISSO IMPORTA MAIS DO QUE PARECE. `db/test/modelagem_escala.test.sql`
-- monta 770 ocorrências de 55 rótulos sintéticos ("Conta analitica numero 3").
-- Ele mede escala e mede bem — mas 55 rótulos inventados não exercitam
-- `fn_papel_linha` contra rótulo de verdade, e é exatamente aí que este projeto
-- já se enganou duas vezes: a 0042 registra que `fn_mes_do_rotulo` passava na
-- fixture ("jan/2024") e voltava VAZIA na extração real ("Faturamento
-- Janeiro"). O CLAUDE.md chama isso pelo nome: a fixture usava o rótulo que o
-- autor do teste inventou, não o que o extrator produz.
--
-- O QUE ESTA FIXTURE TRAVA. Com ela, `fn_papel_linha` é conferida contra os 249
-- rótulos reais e a classificação tem de sair EXATAMENTE como a produção
-- mostrou: 203 contas, 28 subtotais, 12 séries mensais, 6 derivados. Qualquer
-- mexida em `fn_papel_linha`, `fn_rotulo_estrutural` ou `fn_normalizar_texto`
-- que reclassifique um rótulo real reprova aqui — inclusive as reclassificações
-- DESEJÁVEIS, que passam a exigir atualizar este número de propósito, com o
-- rótulo nomeado no diff. É o oposto de um teste frouxo.
--
-- FORMA DO CASO: 14 documentos (um por tipo de taxonomia visto na captura, mais
-- BALANCO repetido até 14, que é o que o v35 tem), e as ocorrências de cada
-- linha distribuídas entre os documentos dos tipos que a linha declara — é isso
-- que faz uma linha lógica ter 13 ocorrências e não 1.
--
-- Deixa o id do caso em `v35.caso` para o teste que a carrega.
-- =============================================================================

\set ON_ERROR_STOP on

create temporary table v35_linha(
  secao          text,
  chave          text,
  papel_esperado text,
  valor          numeric,
  unidade        text,
  n_ocorrencias  int,
  tipos          text[]
);

insert into v35_linha (secao, chave, papel_esperado, valor, unidade, n_ocorrencias, tipos) values
  (null, 'Aluguéis a receber', 'conta', 640, 'milhar', 1, array['MUTUOS']),
  (null, 'Arrendadora Sigma - Arrendamento mercantil - Juros do exercício', 'conta', 380000, 'unidade', 1, array['MAPA_DIVIDA']),
  (null, 'Arrendadora Sigma - Arrendamento mercantil - Saldo devedor', 'conta', 2680000, 'unidade', 1, array['MAPA_DIVIDA']),
  (null, 'ATIVO', 'subtotal', 158801, 'milhar', 13, array['BALANCO','COMBINADO']),
  (null, 'Banco Atlântico Sul - Antecipação de recebíveis - Juros do exercício', 'conta', 4630000, 'unidade', 1, array['MAPA_DIVIDA']),
  (null, 'Banco Atlântico Sul - Antecipação de recebíveis - Saldo devedor', 'conta', 6180000, 'unidade', 1, array['MAPA_DIVIDA']),
  (null, 'Banco Atlântico Sul - Capital de giro - Juros do exercício', 'conta', 1490000, 'unidade', 1, array['MAPA_DIVIDA']),
  (null, 'Banco Atlântico Sul - Capital de giro - Saldo devedor', 'conta', 6180000, 'unidade', 1, array['MAPA_DIVIDA']),
  (null, 'Banco Meridional S.A. - Capital de giro - Juros do exercício', 'conta', 2180000, 'unidade', 1, array['MAPA_DIVIDA']),
  (null, 'Banco Meridional S.A. - Capital de giro - Saldo devedor', 'conta', 9420000, 'unidade', 1, array['MAPA_DIVIDA']),
  (null, 'Banco Meridional S.A. - Conta garantida - Juros do exercício', 'conta', 640000, 'unidade', 1, array['MAPA_DIVIDA']),
  (null, 'Banco Meridional S.A. - Conta garantida - Saldo devedor', 'conta', 2380000, 'unidade', 1, array['MAPA_DIVIDA']),
  (null, 'BNDES / FINAME - Financiamento de máquinas - Juros do exercício', 'conta', 1080000, 'unidade', 1, array['MAPA_DIVIDA']),
  (null, 'BNDES / FINAME - Financiamento de máquinas - Saldo devedor', 'conta', 9080000, 'unidade', 1, array['MAPA_DIVIDA']),
  (null, 'Caixa e equivalentes de caixa no final do exercício', 'conta', 500, 'milhar', 1, array['FLUXO_CAIXA']),
  (null, 'Caixa e equivalentes de caixa no início do exercício', 'conta', 4840, 'milhar', 1, array['FLUXO_CAIXA']),
  (null, 'Capital circulante líquido negativo', 'derivado', 24392, 'milhar', 1, array['NOTAS_EXPL']),
  (null, 'Conta corrente', 'conta', 1400, 'milhar', 1, array['MUTUOS']),
  (null, 'Cooperativa de Crédito Vale - Capital de giro - Juros do exercício', 'conta', 820000, 'unidade', 1, array['MAPA_DIVIDA']),
  (null, 'Cooperativa de Crédito Vale - Capital de giro - Saldo devedor', 'conta', 3140000, 'unidade', 1, array['MAPA_DIVIDA']),
  (null, 'Fomento Mercantil Paulista Ltda. - Factoring - Juros do exercício', 'conta', 1180000, 'unidade', 1, array['MAPA_DIVIDA']),
  (null, 'Fomento Mercantil Paulista Ltda. - Factoring - Saldo devedor', 'conta', 2440000, 'unidade', 1, array['MAPA_DIVIDA']),
  (null, 'Índice de liquidez corrente', 'derivado', 1, 'milhar', 1, array['NOTAS_EXPL']),
  (null, 'LUCRO BRUTO', 'subtotal', 27400, 'milhar', 2, array['DRE']),
  (null, 'Média mensal 2024', 'derivado', 15290, 'milhar', 1, array['FATURAMENTO_24M']),
  (null, 'Média mensal 2025', 'derivado', 11533, 'milhar', 1, array['FATURAMENTO_24M']),
  (null, 'Mútuo', 'conta', 7600, 'milhar', 2, array['MUTUOS']),
  (null, 'PASSIVO E PATRIMÔNIO LÍQUIDO', 'subtotal', 121198, 'milhar', 6, array['BALANCO']),
  (null, 'Prejuízo líquido', 'subtotal', 17901, 'milhar', 1, array['NOTAS_EXPL']),
  (null, 'PREJUÍZO LÍQUIDO DO EXERCÍCIO', 'subtotal', -17901, 'milhar', 2, array['DRE']),
  (null, 'REDUÇÃO LÍQUIDA DE CAIXA E EQUIVALENTES DE CAIXA', 'subtotal', -4340, 'milhar', 1, array['FLUXO_CAIXA']),
  (null, 'RESULTADO ANTES DOS TRIBUTOS SOBRE O LUCRO', 'subtotal', -17901, 'milhar', 2, array['DRE']),
  (null, 'RESULTADO OPERACIONAL ANTES DO RESULTADO FINANCEIRO', 'subtotal', 6470, 'milhar', 2, array['DRE']),
  (null, 'Sócios pessoas físicas - Empréstimo subordinado - Juros do exercício', 'conta', 0, 'unidade', 1, array['MAPA_DIVIDA']),
  (null, 'Sócios pessoas físicas - Empréstimo subordinado - Saldo devedor', 'conta', 9800000, 'unidade', 1, array['MAPA_DIVIDA']),
  (null, 'Ticket médio por pedido 2024', 'derivado', 38, 'milhar', 1, array['FATURAMENTO_24M']),
  (null, 'Ticket médio por pedido 2025', 'derivado', 31, 'milhar', 1, array['FATURAMENTO_24M']),
  (null, 'TOTAL', 'subtotal', 13673, 'milhar', 1, array['MUTUOS']),
  (null, 'TOTAL - Juros do exercício', 'subtotal', 12400000, 'unidade', 1, array['MAPA_DIVIDA']),
  (null, 'TOTAL - Saldo devedor', 'subtotal', 51300000, 'unidade', 1, array['MAPA_DIVIDA']),
  (null, 'TOTAL DO ATIVO', 'subtotal', 158801, 'milhar', 13, array['BALANCO','COMBINADO']),
  (null, 'TOTAL DO EXERCÍCIO 2024', 'subtotal', 183480, 'milhar', 1, array['FATURAMENTO_24M']),
  (null, 'TOTAL DO EXERCÍCIO 2025', 'subtotal', 138400, 'milhar', 1, array['FATURAMENTO_24M']),
  (null, 'TOTAL DO PASSIVO E DO PATRIMÔNIO LÍQUIDO', 'subtotal', 158801, 'milhar', 7, array['BALANCO','COMBINADO']),
  (null, 'TOTAL DO PATRIMÔNIO LÍQUIDO', 'subtotal', 8569, 'milhar', 1, array['COMBINADO']),
  ('atividades_financiamento', 'Amortização de empréstimos e financiamentos', 'conta', -21400, 'milhar', 1, array['FLUXO_CAIXA']),
  ('atividades_financiamento', 'Antecipação de recebíveis, líquida', 'conta', 4600, 'milhar', 1, array['FLUXO_CAIXA']),
  ('atividades_financiamento', 'Caixa líquido gerado pelas (aplicado nas) atividades de financiamento', 'subtotal', -3490, 'milhar', 1, array['FLUXO_CAIXA']),
  ('atividades_financiamento', 'Captação de empréstimos e financiamentos', 'conta', 18600, 'milhar', 1, array['FLUXO_CAIXA']),
  ('atividades_financiamento', 'Juros pagos', 'conta', -9800, 'milhar', 1, array['FLUXO_CAIXA']),
  ('atividades_financiamento', 'Mútuos recebidos da controladora, líquidos', 'conta', 5400, 'milhar', 1, array['FLUXO_CAIXA']),
  ('atividades_financiamento', 'Pagamento de arrendamentos - CPC 06', 'conta', -890, 'milhar', 1, array['FLUXO_CAIXA']),
  ('atividades_investimento', 'Aquisições de imobilizado', 'conta', -3900, 'milhar', 1, array['FLUXO_CAIXA']),
  ('atividades_investimento', 'Aquisições de intangível', 'conta', -180, 'milhar', 1, array['FLUXO_CAIXA']),
  ('atividades_investimento', 'Caixa líquido aplicado nas atividades de investimento', 'subtotal', -1940, 'milhar', 1, array['FLUXO_CAIXA']),
  ('atividades_investimento', 'Recebimento pela alienação de imobilizado', 'conta', 2140, 'milhar', 1, array['FLUXO_CAIXA']),
  ('atividades_operacionais', 'Caixa líquido gerado pelas (aplicado nas) atividades operacionais', 'subtotal', 1090, 'milhar', 1, array['FLUXO_CAIXA']),
  ('atividades_operacionais', 'Depreciação e amortização', 'conta', 5840, 'milhar', 1, array['FLUXO_CAIXA']),
  ('atividades_operacionais', 'Juros e encargos provisionados não pagos', 'conta', 3420, 'milhar', 1, array['FLUXO_CAIXA']),
  ('atividades_operacionais', 'Perdas estimadas em créditos de liquidação duvidosa', 'conta', 2180, 'milhar', 1, array['FLUXO_CAIXA']),
  ('atividades_operacionais', 'Prejuízo líquido do exercício', 'subtotal', -17901, 'milhar', 1, array['FLUXO_CAIXA']),
  ('atividades_operacionais', 'Provisão para contingências', 'conta', 1900, 'milhar', 1, array['FLUXO_CAIXA']),
  ('atividades_operacionais', 'Provisão para obsolescência de estoques', 'conta', 1250, 'milhar', 1, array['FLUXO_CAIXA']),
  ('atividades_operacionais', 'Resultado na alienação de imobilizado', 'conta', -1180, 'milhar', 1, array['FLUXO_CAIXA']),
  ('atividades_operacionais', 'Variação em contas a receber de clientes', 'conta', 7740, 'milhar', 1, array['FLUXO_CAIXA']),
  ('atividades_operacionais', 'Variação em estoques', 'conta', 4930, 'milhar', 1, array['FLUXO_CAIXA']),
  ('atividades_operacionais', 'Variação em fornecedores', 'conta', -4749, 'milhar', 1, array['FLUXO_CAIXA']),
  ('atividades_operacionais', 'Variação em obrigações trabalhistas e sociais', 'conta', 2180, 'milhar', 1, array['FLUXO_CAIXA']),
  ('atividades_operacionais', 'Variação em obrigações tributárias e parcelamentos', 'conta', -3180, 'milhar', 1, array['FLUXO_CAIXA']),
  ('atividades_operacionais', 'Variação em outros ativos e passivos operacionais', 'conta', -890, 'milhar', 1, array['FLUXO_CAIXA']),
  ('atividades_operacionais', 'Variação em tributos a recuperar', 'conta', -450, 'milhar', 1, array['FLUXO_CAIXA']),
  ('ativo_circulante', '(-) PECLD', 'conta', 1640, 'milhar', 5, array['BALANCETE','BALANCO']),
  ('ativo_circulante', '(-) Perdas estimadas em créditos de liquidação duvidosa', 'conta', -3850, 'milhar', 2, array['BALANCO']),
  ('ativo_circulante', '(-) Provisão para obsolescência de estoques', 'conta', -2350, 'milhar', 2, array['BALANCO']),
  ('ativo_circulante', '(-) Provisão para perdas em estoques', 'conta', 890, 'milhar', 3, array['BALANCETE','BALANCO']),
  ('ativo_circulante', 'Adiantamentos a empregados', 'conta', 460, 'milhar', 2, array['BALANCO']),
  ('ativo_circulante', 'Adiantamentos a fornecedores', 'conta', 2210, 'milhar', 2, array['BALANCO']),
  ('ativo_circulante', 'Adiantamentos diversos', 'conta', 340, 'milhar', 3, array['BALANCETE','BALANCO']),
  ('ativo_circulante', 'Aplicações financeiras de liquidez imediata', 'conta', 3600, 'milhar', 2, array['BALANCO']),
  ('ativo_circulante', 'Ativo Circulante', 'subtotal', 67878, 'milhar', 13, array['BALANCO','COMBINADO']),
  ('ativo_circulante', 'Caixa e bancos conta movimento', 'conta', 1240, 'milhar', 2, array['BALANCO']),
  ('ativo_circulante', 'Caixa e equivalentes de caixa', 'conta', 880, 'milhar', 2, array['BALANCO']),
  ('ativo_circulante', 'Clientes - mercado interno', 'conta', 9240, 'milhar', 3, array['BALANCETE','BALANCO']),
  ('ativo_circulante', 'Conta corrente a receber - VT Logística e Transportes', 'conta', 1568, 'milhar', 2, array['BALANCO']),
  ('ativo_circulante', 'Contas a Receber', 'conta', 30020, 'milhar', 10, array['BALANCO','COMBINADO']),
  ('ativo_circulante', 'Despesas antecipadas', 'conta', 40, 'milhar', 2, array['BALANCO']),
  ('ativo_circulante', 'Despesas antecipadas - seguros e apólices', 'conta', 260, 'milhar', 2, array['BALANCO']),
  ('ativo_circulante', 'Disponível', 'conta', 4840, 'milhar', 16, array['BALANCO','COMBINADO']),
  ('ativo_circulante', 'Duplicatas a receber de clientes - mercado externo', 'conta', 4100, 'milhar', 2, array['BALANCO']),
  ('ativo_circulante', 'Duplicatas a receber de clientes - mercado interno', 'conta', 27900, 'milhar', 2, array['BALANCO']),
  ('ativo_circulante', 'Estoques', 'conta', 24610, 'milhar', 7, array['BALANCO','COMBINADO']),
  ('ativo_circulante', 'Fretes a receber', 'conta', 3562, 'milhar', 2, array['BALANCO']),
  ('ativo_circulante', 'ICMS a recuperar', 'conta', 2640, 'milhar', 5, array['BALANCETE','BALANCO']),
  ('ativo_circulante', 'IRRF sobre aplicações financeiras', 'conta', 340, 'milhar', 2, array['BALANCO']),
  ('ativo_circulante', 'Matéria-prima', 'conta', 3180, 'milhar', 3, array['BALANCETE','BALANCO']),
  ('ativo_circulante', 'Materiais de manutenção e consumo', 'conta', 910, 'milhar', 2, array['BALANCO']),
  ('ativo_circulante', 'Matérias-primas e insumos', 'conta', 12400, 'milhar', 2, array['BALANCO']),
  ('ativo_circulante', 'Numerário disponível em bancos', 'conta', 410, 'milhar', 3, array['BALANCETE','BALANCO']),
  ('ativo_circulante', 'Outros Créditos', 'conta', 4428, 'milhar', 17, array['BALANCO','COMBINADO']),
  ('ativo_circulante', 'PIS e COFINS a recuperar', 'conta', 1460, 'milhar', 2, array['BALANCO']),
  ('ativo_circulante', 'PIS/COFINS a compensar', 'conta', 410, 'milhar', 3, array['BALANCETE','BALANCO']),
  ('ativo_circulante', 'Produtos acabados', 'conta', 8100, 'milhar', 5, array['BALANCETE','BALANCO']),
  ('ativo_circulante', 'Produtos em elaboração', 'conta', 4300, 'milhar', 2, array['BALANCO']),
  ('ativo_circulante', 'Tributos a Recuperar', 'conta', 5071, 'milhar', 10, array['BALANCO','COMBINADO']),
  ('ativo_nao_circulante', '(-) Amortização acumulada', 'conta', -1480, 'milhar', 5, array['BALANCETE','BALANCO']),
  ('ativo_nao_circulante', '(-) Depreciação acumulada', 'conta', -52300, 'milhar', 7, array['BALANCETE','BALANCO']),
  ('ativo_nao_circulante', '(-) Depreciação acumulada da frota', 'conta', -6832, 'milhar', 2, array['BALANCO']),
  ('ativo_nao_circulante', 'Ativo Não Circulante', 'subtotal', 101200, 'milhar', 13, array['BALANCO','COMBINADO']),
  ('ativo_nao_circulante', 'Créditos tributários - ICMS sobre ativo permanente', 'conta', 3900, 'milhar', 2, array['BALANCO']),
  ('ativo_nao_circulante', 'Depósitos judiciais', 'conta', 1180, 'milhar', 3, array['BALANCETE','BALANCO']),
  ('ativo_nao_circulante', 'Depósitos judiciais - trabalhistas', 'conta', 3120, 'milhar', 2, array['BALANCO']),
  ('ativo_nao_circulante', 'Depósitos judiciais - tributários', 'conta', 1730, 'milhar', 2, array['BALANCO']),
  ('ativo_nao_circulante', 'Edificações e benfeitorias', 'conta', 24000, 'milhar', 2, array['BALANCO']),
  ('ativo_nao_circulante', 'Ferramental e moldes', 'conta', 3900, 'milhar', 3, array['BALANCETE','BALANCO']),
  ('ativo_nao_circulante', 'Frota de veículos e implementos', 'conta', 10976, 'milhar', 2, array['BALANCO']),
  ('ativo_nao_circulante', 'Imobilizado', 'conta', 58570, 'milhar', 13, array['BALANCO','COMBINADO']),
  ('ativo_nao_circulante', 'Imobilizado em andamento - linha de usinagem', 'conta', 2700, 'milhar', 2, array['BALANCO']),
  ('ativo_nao_circulante', 'Instalações industriais', 'conta', 6200, 'milhar', 2, array['BALANCO']),
  ('ativo_nao_circulante', 'Intangível', 'conta', 960, 'milhar', 7, array['BALANCO','COMBINADO']),
  ('ativo_nao_circulante', 'Investimentos', 'conta', 41715, 'milhar', 11, array['BALANCO','COMBINADO']),
  ('ativo_nao_circulante', 'Máquinas e equipamentos', 'conta', 14600, 'milhar', 3, array['BALANCETE','BALANCO']),
  ('ativo_nao_circulante', 'Máquinas, aparelhos e equipamentos industriais', 'conta', 46800, 'milhar', 2, array['BALANCO']),
  ('ativo_nao_circulante', 'Marcas e patentes', 'conta', 420, 'milhar', 2, array['BALANCO']),
  ('ativo_nao_circulante', 'Móveis e utensílios', 'conta', 1150, 'milhar', 2, array['BALANCO']),
  ('ativo_nao_circulante', 'Mútuos a receber de controladas', 'conta', 11453, 'milhar', 2, array['BALANCO']),
  ('ativo_nao_circulante', 'Participação em VERTENTES IMÓVEIS SPE LTDA. (100%) - MEP', 'conta', 16500, null, 2, array['BALANCO']),
  ('ativo_nao_circulante', 'Participação em VERTENTES METALÚRGICA LTDA. (100%) - MEP', 'conta', 24801, null, 2, array['BALANCO']),
  ('ativo_nao_circulante', 'Participação em VT LOGÍSTICA E TRANSPORTES LTDA. (70%) - MEP', 'conta', 1014, null, 2, array['BALANCO']),
  ('ativo_nao_circulante', 'Participações em outras sociedades - avaliadas ao custo', 'conta', 180, 'milhar', 2, array['BALANCO']),
  ('ativo_nao_circulante', 'Realizável a Longo Prazo', 'subtotal', 11453, 'milhar', 11, array['BALANCO','COMBINADO']),
  ('ativo_nao_circulante', 'Software', 'conta', 210, 'milhar', 3, array['BALANCETE','BALANCO']),
  ('ativo_nao_circulante', 'Softwares e licenças de uso', 'conta', 1900, 'milhar', 2, array['BALANCO']),
  ('ativo_nao_circulante', 'Terrenos', 'conta', 8500, 'milhar', 2, array['BALANCO']),
  ('ativo_nao_circulante', 'Títulos a receber - venda de imobilizado', 'conta', 940, 'milhar', 2, array['BALANCO']),
  ('ativo_nao_circulante', 'Veículos', 'conta', 890, 'milhar', 3, array['BALANCETE','BALANCO']),
  ('ativo_nao_circulante', 'Veículos e empilhadeiras', 'conta', 3900, 'milhar', 2, array['BALANCO']),
  ('custos', 'Custos indiretos de fabricação', 'conta', -11200, 'milhar', 2, array['DRE']),
  ('custos', 'Depreciação industrial', 'conta', -5540, 'milhar', 2, array['DRE']),
  ('custos', 'Mão de obra direta e encargos', 'conta', -21400, 'milhar', 2, array['DRE']),
  ('custos', 'Matérias-primas e insumos consumidos', 'conta', -78200, 'milhar', 2, array['DRE']),
  ('despesas_operacionais', 'Despesas com vendas e comerciais', 'conta', -8100, 'milhar', 2, array['DRE']),
  ('despesas_operacionais', 'Despesas gerais e administrativas', 'conta', -9640, 'milhar', 2, array['DRE']),
  ('despesas_operacionais', 'Despesas tributárias', 'conta', -910, 'milhar', 2, array['DRE']),
  ('despesas_operacionais', 'Honorários da administração', 'conta', -1440, 'milhar', 2, array['DRE']),
  ('despesas_operacionais', 'Outras receitas (despesas) operacionais, líquidas', 'conta', 11549, 'milhar', 2, array['DRE']),
  ('despesas_operacionais', 'Perdas estimadas em créditos de liquidação duvidosa', 'conta', -2180, 'milhar', 2, array['DRE']),
  ('despesas_operacionais', 'Provisão para contingências trabalhistas e cíveis', 'conta', -1900, 'milhar', 2, array['DRE']),
  ('dmpl', 'Ajuste de avaliação patrimonial', 'conta', 1850, 'milhar', 2, array['DMPL']),
  ('dmpl', 'Capital a integralizar', 'conta', -2000, 'milhar', 2, array['DMPL']),
  ('dmpl', 'Capital social', 'conta', 45000, 'milhar', 2, array['DMPL']),
  ('dmpl', 'Prejuízos acumulados', 'conta', -39150, 'milhar', 3, array['DMPL']),
  ('dmpl', 'Reserva legal', 'conta', 1200, 'milhar', 2, array['DMPL']),
  ('dmpl', 'Total', 'subtotal', 24801, 'milhar', 3, array['DMPL']),
  ('impostos_lucro', 'Imposto de renda e contribuição social - corrente', 'conta', -420, 'milhar', 2, array['DRE']),
  ('impostos_lucro', 'Imposto de renda e contribuição social - diferido', 'conta', 0, 'milhar', 2, array['DRE']),
  ('passivo_circulante', 'Adiantamentos de clientes', 'conta', 2109, 'milhar', 2, array['BALANCO']),
  ('passivo_circulante', 'Aluguéis a pagar - Vertentes Imóveis SPE', 'conta', 400, 'milhar', 2, array['BALANCO']),
  ('passivo_circulante', 'Antecipação de recebíveis (factoring)', 'conta', 1283, 'milhar', 3, array['BALANCETE','BALANCO']),
  ('passivo_circulante', 'Arrendamentos', 'conta', 908, 'milhar', 4, array['BALANCO','COMBINADO']),
  ('passivo_circulante', 'Arrendamentos a pagar - CPC 06 (R2)', 'conta', 908, 'milhar', 2, array['BALANCO']),
  ('passivo_circulante', 'Cheque especial / conta garantida', 'conta', 588, 'milhar', 3, array['BALANCETE','BALANCO']),
  ('passivo_circulante', 'Conta garantida', 'conta', 1665, 'milhar', 2, array['BALANCO']),
  ('passivo_circulante', 'Duplicatas descontadas e antecipação de recebíveis', 'conta', 5668, 'milhar', 2, array['BALANCO']),
  ('passivo_circulante', 'Empréstimo com garantia de recebíveis do grupo', 'conta', 4200, 'milhar', 2, array['BALANCO']),
  ('passivo_circulante', 'Empréstimos bancários - capital de giro', 'conta', 15660, 'milhar', 5, array['BALANCETE','BALANCO']),
  ('passivo_circulante', 'Empréstimos e Financiamentos', 'conta', 44474, 'milhar', 16, array['BALANCO','COMBINADO']),
  ('passivo_circulante', 'Empréstimos reclassificados do longo prazo (covenant)', 'conta', 3915, 'milhar', 1, array['BALANCO']),
  ('passivo_circulante', 'FGTS a recolher', 'conta', 456, 'milhar', 2, array['BALANCO']),
  ('passivo_circulante', 'Financiamentos - FINAME/BNDES', 'conta', 3618, 'milhar', 2, array['BALANCO']),
  ('passivo_circulante', 'Fornecedores', 'conta', 23559, 'milhar', 10, array['BALANCO','COMBINADO']),
  ('passivo_circulante', 'Fornecedores estrangeiros', 'conta', 3541, 'milhar', 2, array['BALANCO']),
  ('passivo_circulante', 'Fornecedores nacionais', 'conta', 14374, 'milhar', 2, array['BALANCO']),
  ('passivo_circulante', 'Fornecedores nacionais - a vencer', 'conta', 1948, 'milhar', 3, array['BALANCETE','BALANCO']),
  ('passivo_circulante', 'Fornecedores nacionais - em atraso', 'conta', 4719, 'milhar', 3, array['BALANCETE','BALANCO']),
  ('passivo_circulante', 'Honorários da administração a pagar', 'conta', 320, 'milhar', 2, array['BALANCO']),
  ('passivo_circulante', 'ICMS a recolher', 'conta', 1239, 'milhar', 2, array['BALANCO']),
  ('passivo_circulante', 'ICMS a recolher - em atraso', 'conta', 1184, 'milhar', 3, array['BALANCETE','BALANCO']),
  ('passivo_circulante', 'INSS a recolher', 'conta', 1718, 'milhar', 2, array['BALANCO']),
  ('passivo_circulante', 'INSS e FGTS a recolher - em atraso', 'conta', 1623, 'milhar', 3, array['BALANCETE','BALANCO']),
  ('passivo_circulante', 'IRRF a recolher', 'conta', 293, 'milhar', 2, array['BALANCO']),
  ('passivo_circulante', 'ISS a recolher', 'conta', 70, 'milhar', 2, array['BALANCO']),
  ('passivo_circulante', 'Mútuos a pagar - controladora', 'conta', 3974, 'milhar', 3, array['BALANCETE','BALANCO']),
  ('passivo_circulante', 'Mútuos a pagar - Vertentes Participações S.A.', 'conta', 7479, 'milhar', 2, array['BALANCO']),
  ('passivo_circulante', 'Obrigações Trabalhistas e Sociais', 'conta', 11025, 'milhar', 10, array['BALANCO','COMBINADO']),
  ('passivo_circulante', 'Obrigações Tributárias', 'conta', 7895, 'milhar', 16, array['BALANCO','COMBINADO']),
  ('passivo_circulante', 'Outras contas a pagar', 'conta', 739, 'milhar', 5, array['BALANCETE','BALANCO']),
  ('passivo_circulante', 'Outras Obrigações', 'conta', 4861, 'milhar', 11, array['BALANCO','COMBINADO']),
  ('passivo_circulante', 'Parcelamentos tributários - curto prazo', 'conta', 3272, 'milhar', 5, array['BALANCETE','BALANCO']),
  ('passivo_circulante', 'Partes Relacionadas', 'conta', -12431, 'milhar', 11, array['BALANCO','COMBINADO']),
  ('passivo_circulante', 'Passivo Circulante', 'subtotal', 92539, 'milhar', 13, array['BALANCO','COMBINADO']),
  ('passivo_circulante', 'PIS e COFINS a recolher', 'conta', 831, 'milhar', 2, array['BALANCO']),
  ('passivo_circulante', 'PIS/COFINS a recolher', 'conta', 395, 'milhar', 3, array['BALANCETE','BALANCO']),
  ('passivo_circulante', 'Provisão de 13º salário e encargos', 'conta', 801, 'milhar', 2, array['BALANCO']),
  ('passivo_circulante', 'Provisão de férias e 13º', 'conta', 848, 'milhar', 3, array['BALANCETE','BALANCO']),
  ('passivo_circulante', 'Provisão de férias e encargos', 'conta', 1801, 'milhar', 2, array['BALANCO']),
  ('passivo_circulante', 'Provisões trabalhistas', 'conta', 1408, 'milhar', 3, array['BALANCETE','BALANCO']),
  ('passivo_circulante', 'Provisões trabalhistas e cíveis - curto prazo', 'conta', 1344, 'milhar', 2, array['BALANCO']),
  ('passivo_circulante', 'Salários a pagar - em atraso', 'conta', 902, 'milhar', 3, array['BALANCETE','BALANCO']),
  ('passivo_circulante', 'Salários e ordenados a pagar', 'conta', 2972, 'milhar', 2, array['BALANCO']),
  ('passivo_circulante', 'Tributos a recolher', 'conta', 74, 'milhar', 2, array['BALANCO']),
  ('passivo_nao_circulante', 'Arrendamentos', 'conta', 3118, 'milhar', 4, array['BALANCO','COMBINADO']),
  ('passivo_nao_circulante', 'Arrendamentos a pagar - CPC 06 (R2)', 'conta', 3118, 'milhar', 2, array['BALANCO']),
  ('passivo_nao_circulante', 'Empréstimo de sócios - subordinado', 'conta', 9800, 'milhar', 2, array['BALANCO']),
  ('passivo_nao_circulante', 'Empréstimos e Financiamentos', 'conta', 37379, 'milhar', 13, array['BALANCO','COMBINADO']),
  ('passivo_nao_circulante', 'Financiamentos - FINAME/BNDES', 'conta', 11393, 'milhar', 2, array['BALANCO']),
  ('passivo_nao_circulante', 'Obrigações Tributárias', 'conta', 13549, 'milhar', 7, array['BALANCO','COMBINADO']),
  ('passivo_nao_circulante', 'Parcelamentos tributários - longo prazo', 'conta', 13549, 'milhar', 5, array['BALANCETE','BALANCO']),
  ('passivo_nao_circulante', 'Passivo Não Circulante', 'subtotal', 57693, 'milhar', 13, array['BALANCO','COMBINADO']),
  ('passivo_nao_circulante', 'Provisão para contingências cíveis', 'conta', 539, 'milhar', 2, array['BALANCO']),
  ('passivo_nao_circulante', 'Provisão para contingências trabalhistas', 'conta', 3002, 'milhar', 2, array['BALANCO']),
  ('passivo_nao_circulante', 'Provisão para contingências trabalhistas e cíveis', 'conta', 2567, 'milhar', 3, array['BALANCETE','BALANCO']),
  ('passivo_nao_circulante', 'Provisão para contingências tributárias', 'conta', 1617, 'milhar', 2, array['BALANCO']),
  ('passivo_nao_circulante', 'Provisão para passivo a descoberto de controlada', 'conta', 12399, 'milhar', 2, array['BALANCO']),
  ('passivo_nao_circulante', 'Provisões', 'conta', 12399, 'milhar', 14, array['BALANCO','COMBINADO']),
  ('patrimonio_liquido', '(-) Capital social a integralizar', 'conta', -2000, 'milhar', 2, array['BALANCO']),
  ('patrimonio_liquido', '(-) Eliminação do patrimônio líquido das controladas', 'conta', -11260, 'milhar', 1, array['COMBINADO']),
  ('patrimonio_liquido', 'Ajuste de avaliação patrimonial', 'conta', 1850, 'milhar', 2, array['BALANCO']),
  ('patrimonio_liquido', 'Capital Social', 'conta', 43000, 'milhar', 13, array['BALANCETE','BALANCO']),
  ('patrimonio_liquido', 'Capital social subscrito', 'conta', 45000, 'milhar', 2, array['BALANCO']),
  ('patrimonio_liquido', 'Capital social subscrito e integralizado', 'conta', 30000, 'milhar', 2, array['BALANCO']),
  ('patrimonio_liquido', 'Participação de não controladores (VT Logística — 30%)', 'conta', 78, null, 1, array['COMBINADO']),
  ('patrimonio_liquido', 'Patrimônio Líquido', 'subtotal', 39375, 'milhar', 11, array['BALANCO','COMBINADO']),
  ('patrimonio_liquido', 'Prejuízos acumulados', 'conta', -39150, 'milhar', 6, array['BALANCETE','BALANCO']),
  ('patrimonio_liquido', 'Reserva legal', 'conta', 1200, 'milhar', 2, array['BALANCO']),
  ('patrimonio_liquido', 'Reservas', 'conta', 3050, 'milhar', 2, array['BALANCO']),
  ('patrimonio_liquido', 'Resultados Acumulados', 'conta', -39150, 'milhar', 10, array['BALANCO']),
  ('receita_bruta', 'Devoluções e abatimentos', 'conta', -3180, 'milhar', 2, array['DRE']),
  ('receita_bruta', 'Faturamento Abril', 'serie_mensal', 16100, 'milhar', 1, array['FATURAMENTO_24M']),
  ('receita_bruta', 'Faturamento Agosto', 'serie_mensal', 15644, 'milhar', 1, array['FATURAMENTO_24M']),
  ('receita_bruta', 'Faturamento Dezembro', 'serie_mensal', 12910, 'milhar', 1, array['FATURAMENTO_24M']),
  ('receita_bruta', 'Faturamento Fevereiro', 'serie_mensal', 15948, 'milhar', 1, array['FATURAMENTO_24M']),
  ('receita_bruta', 'Faturamento Janeiro', 'serie_mensal', 15493, 'milhar', 1, array['FATURAMENTO_24M']),
  ('receita_bruta', 'Faturamento Julho', 'serie_mensal', 15189, 'milhar', 1, array['FATURAMENTO_24M']),
  ('receita_bruta', 'Faturamento Junho', 'serie_mensal', 15796, 'milhar', 1, array['FATURAMENTO_24M']),
  ('receita_bruta', 'Faturamento Maio', 'serie_mensal', 16708, 'milhar', 1, array['FATURAMENTO_24M']),
  ('receita_bruta', 'Faturamento Março', 'serie_mensal', 16404, 'milhar', 1, array['FATURAMENTO_24M']),
  ('receita_bruta', 'Faturamento Novembro', 'serie_mensal', 13974, 'milhar', 1, array['FATURAMENTO_24M']),
  ('receita_bruta', 'Faturamento Outubro', 'serie_mensal', 14429, 'milhar', 1, array['FATURAMENTO_24M']),
  ('receita_bruta', 'Faturamento Setembro', 'serie_mensal', 14885, 'milhar', 1, array['FATURAMENTO_24M']),
  ('receita_bruta', 'ICMS sobre vendas', 'conta', -24600, 'milhar', 2, array['DRE']),
  ('receita_bruta', 'IPI sobre vendas', 'conta', -2780, 'milhar', 2, array['DRE']),
  ('receita_bruta', 'PIS e COFINS sobre vendas', 'conta', -9980, 'milhar', 2, array['DRE']),
  ('receita_bruta', 'Prestação de serviços de industrialização', 'conta', 3180, 'milhar', 2, array['DRE']),
  ('receita_bruta', 'RECEITA OPERACIONAL LÍQUIDA', 'subtotal', 143380, 'milhar', 2, array['DRE']),
  ('receita_bruta', 'Vendas de produtos - mercado externo', 'conta', 21400, 'milhar', 2, array['DRE']),
  ('receita_bruta', 'Vendas de produtos - mercado interno', 'conta', 158900, 'milhar', 2, array['DRE']),
  ('resultado_financeiro', 'Despesas financeiras - juros e encargos bancários', 'conta', -12400, 'milhar', 2, array['DRE']),
  ('resultado_financeiro', 'Receitas financeiras', 'conta', 640, 'milhar', 2, array['DRE']),
  ('resultado_financeiro', 'Variações monetárias e cambiais, líquidas', 'conta', -1240, 'milhar', 2, array['DRE']);

do $$
declare
  -- Os 14 documentos do caso, na ordem em que a captura os revela. BALANCO
  -- repete porque o v35 tem vários balanços (exercícios e entidades do grupo) —
  -- é o que produz as 13 ocorrências de "ATIVO".
  v_docs text[] := array['BALANCETE','BALANCO','COMBINADO','DMPL','DRE','FATURAMENTO_24M',
                         'FLUXO_CAIXA','MAPA_DIVIDA','MUTUOS','NOTAS_EXPL',
                         'BALANCO','BALANCO','BALANCO','BALANCO'];
  v_caso  uuid;
  v_ver   uuid;
  v_r     jsonb;
  v_lotes jsonb[];
  v_cand  int[];
  v_i     int;
  v_d     int;
  v_n     int;
  r       record;
begin
  -- Nome ÚNICO por execução: `fn_upsert_caso` reaproveita o caso pelo nome, e um
  -- segundo run.sh no mesmo banco somaria outras 760 ocorrências ao caso
  -- anterior — as contagens dariam o dobro e o teste reprovaria por motivo
  -- errado. Mesma armadilha registrada em modelagem_escala.test.sql.
  v_caso := (fn_upsert_caso('Modelagem v35 real ' || clock_timestamp()::text))::uuid;

  v_lotes := array_fill('[]'::jsonb, array[array_length(v_docs, 1)]);

  -- Distribui as ocorrências de cada linha entre os documentos cujo tipo a linha
  -- declara, em rodízio. Rodízio e não "tudo no primeiro": é a repetição ENTRE
  -- documentos que cria linha lógica com várias ocorrências, que é a forma que
  -- fazia `fn_conferir_modelagem` reexecutar a função inteira por vínculo.
  for r in select * from v35_linha order by secao nulls first, chave loop
    v_cand := array(select i from generate_subscripts(v_docs, 1) i where v_docs[i] = any(r.tipos));
    if array_length(v_cand, 1) is null then
      v_cand := array[1];
    end if;
    for v_i in 1..r.n_ocorrencias loop
      v_d := v_cand[1 + ((v_i - 1) % array_length(v_cand, 1))];
      v_lotes[v_d] := v_lotes[v_d] || jsonb_build_object(
        'ordem',          jsonb_array_length(v_lotes[v_d]) + 1,
        'chave',          r.chave,
        'valor_num',      r.valor::text,
        'unidade',        r.unidade,
        'moeda',          'BRL',
        'confianca',      '0.97',
        'secao_canonica', r.secao);
    end loop;
  end loop;

  for v_d in 1..array_length(v_docs, 1) loop
    v_r := fn_registrar_documento(v_caso, 'VERTENTES METALÚRGICA LTDA.', 'anual', '2025',
      v_docs[v_d], 0.95, 'nome_arquivo', 'supabase_storage',
      'v35/' || v_d || '.pdf', v_docs[v_d] || ' ' || v_d || '.pdf', true,
      'HASH-V35-' || v_d, 'ok');
    v_ver := (v_r->>'documento_versao_id')::uuid;
    perform fn_registrar_campos_extraidos(v_ver, v_lotes[v_d], 'N2');
  end loop;

  select count(*) into v_n
  from campo_extraido ce
  join documento_versao dv on dv.id = ce.documento_versao_id
  join documento d on d.id = dv.documento_id
  where d.caso_id = v_caso and ce.valor_num is not null;

  if v_n <> (select sum(n_ocorrencias) from v35_linha) then
    raise exception 'fixture v35: % ocorrências gravadas, % esperadas', v_n,
      (select sum(n_ocorrencias) from v35_linha);
  end if;

  perform set_config('v35.caso', v_caso::text, false);
  raise notice 'fixture v35 carregada: % linhas lógicas, % ocorrências, caso %',
    (select count(*) from v35_linha), v_n, v_caso;
end $$;
