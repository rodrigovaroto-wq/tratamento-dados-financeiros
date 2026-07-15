-- =============================================================================
-- Migration 0002 — Seed da taxonomia (f0/03) + dial de autonomia inicial (f0/04)
-- Taxonomia v1: Kit Básico (obrigatório) + Variáveis (complementar).
-- Idempotente: on conflict do nothing (para reaplicar sem duplicar).
-- =============================================================================

-- -----------------------------------------------------------------------------
-- NÍVEL 1 — Kit Básico (obrigatório · verificado no Portão 1)
-- -----------------------------------------------------------------------------
insert into taxonomia_tipo_documento
  (codigo, categoria, documento, obrigatoriedade, granularidade, vigencia, sensibilidade, versao)
values
  ('DRE',             'Contábil/Demonstrações', 'Demonstração de Resultado do Exercício',            'obrigatorio', 'entidade_periodo', '12M25,12M24,1T25,1T26', 'nenhuma', 1),
  ('BALANCO',         'Contábil/Demonstrações', 'Balanço Patrimonial',                               'obrigatorio', 'entidade_periodo', '12M25,12M24,1T25,1T26', 'nenhuma', 1),
  ('FLUXO_CAIXA',     'Contábil/Demonstrações', 'Demonstração de Fluxo de Caixa',                    'obrigatorio', 'entidade_periodo', '12M25,12M24',           'nenhuma', 1),
  ('COMBINADO',       'Contábil/Demonstrações', 'Demonstrações combinadas (grupo consolidado)',      'obrigatorio', 'periodo',          '12M25,12M24',           'nenhuma', 1),
  ('FATURAMENTO_24M', 'Faturamento/Receita',    'Série de faturamento dos últimos 24 meses',         'obrigatorio', 'entidade',         'L24M',                  'nenhuma', 1),
  ('MUTUOS',          'Intragrupo',             'Relação de mútuos / posição de contas intragrupo',  'obrigatorio', 'caso',             '23,24,25',              'nenhuma', 1),
  ('FAT_INTRAGRUPO',  'Intragrupo',             'Faturamento intragrupo',                            'obrigatorio', 'caso',             '23,24,26',              'nenhuma', 1),
  ('CONTRATO_SOCIAL', 'Societário/Legal',       'Contrato/estatuto social registrado (ou última alteração)', 'obrigatorio', 'entidade',  'vigente',               'nenhuma', 1)
on conflict (codigo) do nothing;

-- -----------------------------------------------------------------------------
-- NÍVEL 2 — Variáveis (complementar · não bloqueiam completude)
-- -----------------------------------------------------------------------------
insert into taxonomia_tipo_documento
  (codigo, categoria, documento, obrigatoriedade, granularidade, vigencia, sensibilidade, versao)
values
  -- Contábil / Demonstrações (detalhamento)
  ('DF_AUDITADA',     'Contábil/Demonstrações', 'Demonstrações financeiras auditadas completas (+ notas)', 'complementar', 'entidade_periodo', '3 últimos exercícios', 'nenhuma', 1),
  ('BALANCETE',       'Contábil/Demonstrações', 'Balancete mensal (trial balance) analítico',             'complementar', 'entidade_periodo', '12-24 meses',          'nenhuma', 1),
  ('RAZAO',           'Contábil/Demonstrações', 'Livro razão / razão contábil',                           'complementar', 'entidade_periodo', 'conforme pedido',      'nenhuma', 1),
  ('NOTAS_EXPL',      'Contábil/Demonstrações', 'Notas explicativas',                                     'complementar', 'entidade_periodo', 'acompanha DF',         'nenhuma', 1),
  -- Dívida / Tesouraria
  ('MAPA_DIVIDA',     'Dívida/Tesouraria',      'Mapa de dívida (credor, modalidade, saldo, taxa, venc., garantias)', 'complementar', 'caso',     'data-base <= 60 dias', 'nenhuma', 1),
  ('CONTRATO_DIVIDA', 'Dívida/Tesouraria',      'Contratos de empréstimo/financiamento/debêntures',       'complementar', 'caso',             'vigente',              'nenhuma', 1),
  ('EXTRATO_BANCARIO','Dívida/Tesouraria',      'Extratos bancários',                                     'complementar', 'entidade_periodo', '6-12 meses',           'nenhuma', 1),
  ('FLUXO_PROJETADO', 'Dívida/Tesouraria',      'Fluxo de caixa projetado',                               'complementar', 'periodo',          'horizonte do plano',   'nenhuma', 1),
  ('APLIC_FINANC',    'Dívida/Tesouraria',      'Posição de aplicações financeiras',                      'complementar', 'entidade',         'data-base',            'nenhuma', 1),
  -- Operacional
  ('AGING_AR',        'Operacional',            'Aging de contas a receber',                              'complementar', 'entidade',         'data-base <= 60 dias', 'nenhuma', 1),
  ('AGING_AP',        'Operacional',            'Aging de contas a pagar / fornecedores',                 'complementar', 'entidade',         'data-base <= 60 dias', 'nenhuma', 1),
  ('ESTOQUE',         'Operacional',            'Posição de estoques',                                    'complementar', 'entidade',         'data-base',            'nenhuma', 1),
  ('CONTRATOS_COM',   'Operacional',            'Contratos relevantes com clientes/fornecedores',        'complementar', 'caso',             'vigente',              'nenhuma', 1),
  ('HEADCOUNT',       'Operacional',            'Headcount / folha de pagamento',                         'complementar', 'entidade_periodo', '3 meses',              'pii',     1),
  -- Societário / Legal
  ('ORGANOGRAMA',     'Societário/Legal',       'Organograma societário do grupo',                        'complementar', 'caso',             'vigente',              'nenhuma', 1),
  ('CERTIDOES',       'Societário/Legal',       'Certidões (negativas de débito, protestos, falência)',   'complementar', 'entidade',         '<= 90 dias',           'nenhuma', 1),
  ('CONTINGENCIAS',   'Societário/Legal',       'Relatório de contingências / processos judiciais',       'complementar', 'caso',             '<= 90 dias',           'nenhuma', 1),
  -- Tributário
  ('SITUACAO_FISCAL', 'Tributário',             'Situação fiscal / parcelamentos (Refis etc.)',          'complementar', 'entidade',         '<= 90 dias',           'nenhuma', 1),
  ('DEBITOS_TRIB',    'Tributário',             'Demonstrativo de débitos tributários',                   'complementar', 'entidade',         '<= 90 dias',           'nenhuma', 1),
  ('SPED',            'Tributário',             'Obrigações acessórias (SPED/ECD/ECF)',                   'complementar', 'entidade_periodo', 'último exercício',     'nenhuma', 1),
  -- Intragrupo / Partes relacionadas
  ('CONTRATOS_IC',    'Intragrupo',             'Contratos intercompany relevantes',                      'complementar', 'caso',             'vigente',              'nenhuma', 1),
  -- Garantias / Sócios (atenção LGPD)
  ('GARANTIAS',       'Garantias/Sócios',       'Garantias prestadas (reais e fidejussórias); bens em garantia', 'complementar', 'caso',     'vigente',              'nenhuma', 1),
  ('AVAIS_FIANCAS',   'Garantias/Sócios',       'Avais / fianças dos sócios',                             'complementar', 'entidade',         'vigente',              'pii',     1),
  ('DOCS_SOCIOS',     'Garantias/Sócios',       'Documentos pessoais dos sócios garantidores',            'complementar', 'entidade',         'vigente',              'pii_sensivel', 1),
  -- Plano / Projeções
  ('PLANO_NEGOCIOS',  'Plano/Projeções',        'Plano de negócios / turnaround',                         'complementar', 'caso',             'vigente',              'nenhuma', 1),
  ('PREMISSAS',       'Plano/Projeções',        'Premissas das projeções',                                'complementar', 'caso',             'acompanha projeção',   'nenhuma', 1)
on conflict (codigo) do nothing;

-- -----------------------------------------------------------------------------
-- Dial de autonomia inicial da F1 (f0/04 — estado inicial + teto)
-- Chaves de estágio estáveis (usadas no runtime).
-- -----------------------------------------------------------------------------
insert into estagio_autonomia (estagio, nivel_atual, teto) values
  ('classificacao_doc_checklist',   'N1', 'N2'),
  ('validacao_formal',              'N2', 'N3'),
  ('completude_portao1',            'N2', 'N3'),
  ('extracao_identificadores',      'N1', 'N2'),
  ('extracao_linhas_financeiras',   'N0', 'N2'),
  ('reconciliacao_classe_a',        'N1', 'N2'),
  ('reconciliacao_classe_bc',       'N0', 'N1'),
  ('classificacao_contabil',        'N0', 'N1')
on conflict (estagio) do nothing;
