-- =============================================================================
-- Migration 0038 — Catálogo de premissas, e a escolha de modelagem por caso
--
-- O PROBLEMA QUE ISTO RESOLVE. O modelo de hoje tem 15 premissas HARDCODED
-- (`PR`, em portal/src/lib/export-modelagem.ts) aplicadas a um esqueleto fixo de
-- linhas (`LINHAS_BASE`). Isso funciona para um caso genérico e não sobrevive ao
-- que o dono descreveu: "cada caso vai ser um caso, vai vir com linhas
-- diferentes, contas diferentes, vai precisar de inputs e premissas diferentes".
-- Um mandato de varejo projeta por same-store-sales e sazonalidade forte; um de
-- agro por produtividade e preço de commodity. Nenhum dos dois cabe num modelo
-- com premissa fixa no código.
--
-- A INVERSÃO: a premissa deixa de ser constante de código e passa a ser DADO.
-- Acrescentar "RevPAR" ao vocabulário do sistema passa a ser uma LINHA no
-- catálogo, não um ramo de `if` no gerador. É o que impede um agregado de 20
-- setores de virar 20 caminhos de código — que seria impossível de testar e
-- impossível de manter.
--
-- AS QUATRO TABELAS, e por que são quatro:
--   • `premissa_catalogo`      o vocabulário: o que EXISTE como premissa (global)
--   • `caso_modelagem`         os parâmetros do caso (entidade, corte, setor)
--   • `caso_premissa`          quais premissas ESTE caso usa, com valor por ano
--   • `caso_linha_premissa`    o vínculo linha↔premissa — onde cada input entra
--
-- Separar catálogo de escolha é o que permite o catálogo crescer sem tocar em
-- caso nenhum, e o caso ser auditável sem depender do catálogo do futuro.
--
-- DOUTRINA (docs/01): o sistema SUGERE, o humano decide.
-- `fn_premissas_sugeridas(setor)` devolve o que o setor costuma usar — sugestão,
-- nunca imposição. E toda mudança de premissa grava `decisao` +
-- `evento_auditoria`, porque projeção É decisão de análise: daqui a três meses
-- alguém vai perguntar por que a receita cresceu 8%, e a resposta tem de estar
-- na trilha, não na memória de quem exportou.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- Naturezas e fórmulas-tipo. ENUM em vez de texto livre: são o contrato entre o
-- catálogo e o gerador do modelo. Fórmula-tipo nova exige código novo no gerador
-- (é uma primitiva de projeção); premissa nova, não — e essa é exatamente a
-- fronteira que estes dois tipos existem para deixar explícita.
-- -----------------------------------------------------------------------------
do $$ begin
  create type premissa_natureza as enum (
    'macro',          -- índice externo (IPCA, Selic, câmbio…)
    'receita',        -- dirige linha de receita
    'custo',
    'despesa',
    'giro',           -- capital de giro (dias)
    'investimento',   -- capex, depreciação
    'divida',
    'tributo',
    'socios',
    'sazonalidade',   -- distribuição mensal — é premissa, não detalhe (pedido do dono)
    'operacional'     -- driver do setor (volume, ocupação, ARPU…)
  );
exception when duplicate_object then null; end $$;

do $$ begin
  create type premissa_formula as enum (
    'indice_macro',          -- valor vem de uma série macro (Focus/histórico)
    'crescimento_composto',  -- linha_ano_anterior × (1 + premissa)
    'pct_de_linha',          -- premissa × outra linha (margem, % da receita)
    'dias_de_giro',          -- saldo = linha_base × dias / 360
    'valor_por_ano',         -- valor absoluto por exercício (capex, captação)
    'preco_x_volume',        -- duas premissas se multiplicam
    'curva_mensal'           -- distribui o ano em 12 meses (sazonalidade)
  );
exception when duplicate_object then null; end $$;

-- -----------------------------------------------------------------------------
-- O CATÁLOGO — o vocabulário de premissas do sistema.
-- -----------------------------------------------------------------------------
create table if not exists premissa_catalogo (
  codigo      text primary key,
  nome        text not null,
  natureza    premissa_natureza not null,
  formula     premissa_formula not null,
  unidade     text,                        -- '%', 'R$/ano', 'dias', 'x', 'un', 'R$/un'
  -- A que GRUPOS de linha a premissa pode ser vinculada. Vazio = qualquer grupo.
  -- É o que alimenta o "aplicar em lote" do portal ("todas as linhas de receita").
  aplica_em   text[] not null default '{}',
  -- Setores em que a premissa é USUAL. VAZIO = base comum, vale para todos. Não
  -- é restrição: `fn_vincular_linha_premissa` aceita qualquer premissa ativa —
  -- setor é sugestão, e um caso atípico é a regra, não a exceção, em
  -- reestruturação.
  setores     text[] not null default '{}',
  fonte       text,                        -- 'focus' | 'historico' | 'digitado'
  descricao   text,
  ativo       boolean not null default true
);

comment on table premissa_catalogo is
  'Vocabulário de premissas de projeção. Premissa nova = LINHA nova aqui, sem código novo; '
  'fórmula-tipo nova = primitiva nova no gerador. `setores` vazio = base comum a todo setor.';

alter table premissa_catalogo enable row level security;
create policy premissa_catalogo_authenticated_all on premissa_catalogo
  for all to authenticated using (true) with check (true);

-- -----------------------------------------------------------------------------
-- Parâmetros de modelagem do CASO — as três células que saíram do topo da aba
-- Modelagem (entidade modelada, último exercício realizado, índice macro que
-- dirige) mais o setor do mandato. Decisão do dono: elas passam a ser escolhidas
-- no portal, e o Excel sai já parametrizado.
-- -----------------------------------------------------------------------------
create table if not exists caso_modelagem (
  caso_id               uuid primary key references caso(id) on delete cascade,
  entidade              text,
  ultimo_exercicio_real int,
  indice_macro          text,
  setor                 text,
  anos_projetados       int not null default 5,
  atualizado_por        text,
  atualizado_em         timestamptz not null default now()
);

alter table caso_modelagem enable row level security;
create policy caso_modelagem_authenticated_all on caso_modelagem
  for all to authenticated using (true) with check (true);

-- -----------------------------------------------------------------------------
-- As premissas ATIVAS do caso, com valor por ano.
--
-- `valores` é jsonb {"2026": 0.045, "2027": 0.04} em vez de tabela filha por ano:
-- o conjunto de anos muda quando o corte muda, e uma tabela por ano obrigaria a
-- reescrever linhas a cada ajuste do horizonte. Ano SEM valor é ausência
-- declarada — o modelo não projeta aquele ano por aquela premissa, e o arquivo
-- diz isso (nunca projeta com zero, que é a armadilha do "SEM FOCUS").
-- -----------------------------------------------------------------------------
create table if not exists caso_premissa (
  id               uuid primary key default gen_random_uuid(),
  caso_id          uuid not null references caso(id) on delete cascade,
  premissa_codigo  text not null references premissa_catalogo(codigo),
  valores          jsonb not null default '{}'::jsonb,
  origem           text,                    -- focus | historico | digitado
  ativo            boolean not null default true,
  atualizado_por   text,
  atualizado_em    timestamptz not null default now(),
  unique (caso_id, premissa_codigo)
);
create index if not exists idx_caso_premissa_caso on caso_premissa(caso_id);

alter table caso_premissa enable row level security;
create policy caso_premissa_authenticated_all on caso_premissa
  for all to authenticated using (true) with check (true);

-- -----------------------------------------------------------------------------
-- O VÍNCULO linha↔premissa — "onde cada input entra na projeção".
--
-- Como a linha é identificada: NÃO por `campo_extraido.id`. Aquele id morre a
-- cada reextração (versão nova do documento = campos novos), e a configuração de
-- modelagem tem de sobreviver a reenviar um arquivo. A identidade estável de uma
-- linha, para modelagem, é (seção canônica, rótulo normalizado, entidade) — a
-- mesma tripla que o export usa para alinhar a conta entre entidades e períodos.
-- -----------------------------------------------------------------------------
create table if not exists caso_linha_premissa (
  id                   uuid primary key default gen_random_uuid(),
  caso_id              uuid not null references caso(id) on delete cascade,
  secao_canonica       text,
  rotulo_norm          text not null,
  entidade             text,
  premissa_codigo      text references premissa_catalogo(codigo),
  sazonalidade_codigo  text references premissa_catalogo(codigo),
  atualizado_por       text,
  atualizado_em        timestamptz not null default now()
);
-- Unicidade por linha lógica. Índice de EXPRESSÃO porque `entidade` e
-- `secao_canonica` são nulos com frequência (documento de uma entidade só, linha
-- sem sugestão da IA), e em `unique` normal NULL não colide com NULL — duas
-- configurações para a mesma linha passariam.
create unique index if not exists idx_caso_linha_premissa_unica
  on caso_linha_premissa (caso_id, rotulo_norm, coalesce(entidade, ''), coalesce(secao_canonica, ''));
create index if not exists idx_caso_linha_premissa_caso on caso_linha_premissa(caso_id);

alter table caso_linha_premissa enable row level security;
create policy caso_linha_premissa_authenticated_all on caso_linha_premissa
  for all to authenticated using (true) with check (true);

-- =============================================================================
-- SEMENTE DO CATÁLOGO
--
-- Base comum (`setores = '{}'`) + os setores que o dono pediu: "todos os mais
-- comuns que tenha qualquer possibilidade de aparecer". A coluna `aplica_em` é o
-- que o portal usa para o aplicar-em-lote.
-- =============================================================================

-- ----- BASE COMUM ------------------------------------------------------------
insert into premissa_catalogo (codigo, nome, natureza, formula, unidade, aplica_em, setores, fonte, descricao) values
  -- Macro
  ('IPCA',            'IPCA (inflação)',                    'macro','indice_macro','%','{receita,custo,despesa}','{}','focus','Índice oficial de inflação. Do Focus quando há expectativa; média histórica quando não.'),
  ('IGPM',            'IGP-M',                              'macro','indice_macro','%','{receita,custo,despesa}','{}','focus','Reajuste de contratos de aluguel e de boa parte dos contratos B2B.'),
  ('INCC',            'INCC',                               'macro','indice_macro','%','{custo}','{construcao}','historico','Custo da construção civil — reajusta obra e insumo de incorporação.'),
  ('SELIC',           'Selic',                              'macro','indice_macro','%','{divida}','{}','focus','Juro básico; base do custo de dívida indexada ao CDI.'),
  ('CAMBIO_USD',      'Câmbio R$/US$',                      'macro','indice_macro','R$/US$','{receita,custo,divida}','{}','focus','Nível, não variação — receita/custo/dívida em dólar.'),
  ('PIB',             'PIB (crescimento real)',             'macro','indice_macro','%','{receita}','{}','focus','Proxy de volume: quanto da receita cresce porque a economia cresce.'),
  -- Receita
  ('CRESC_REAL',      'Crescimento real da receita',        'receita','crescimento_composto','%','{receita}','{}','digitado','Crescimento acima da inflação — o que é ganho próprio, não repasse de preço.'),
  ('CRESC_NOMINAL',   'Crescimento nominal da receita',     'receita','crescimento_composto','%','{receita}','{}','digitado','Quando não se quer separar preço de volume.'),
  ('PRECO_MEDIO',     'Preço médio',                        'receita','preco_x_volume','R$/un','{receita}','{}','digitado','Usar junto de VOLUME: receita = preço × volume.'),
  ('VOLUME',          'Volume vendido',                     'operacional','preco_x_volume','un','{receita}','{}','digitado','Usar junto de PRECO_MEDIO.'),
  ('SAZONALIDADE',    'Sazonalidade mensal',                'sazonalidade','curva_mensal','%','{receita,custo,despesa}','{}','digitado','Distribui o ano nos 12 meses. É PREMISSA, não detalhe: muda caixa e necessidade de giro.'),
  -- Custo e despesa
  ('MARGEM_BRUTA',    'Margem bruta',                       'custo','pct_de_linha','%','{custo}','{}','digitado','CPV/CSP como complemento da margem sobre a receita.'),
  ('CUSTO_VARIAVEL',  'Custo variável (% da receita)',      'custo','pct_de_linha','%','{custo}','{}','digitado',null),
  ('CUSTO_FIXO',      'Custo fixo por ano',                 'custo','valor_por_ano','R$/ano','{custo}','{}','digitado','Não escala com receita — decisão de plano.'),
  ('INFLACAO_INSUMO', 'Inflação do insumo principal',       'custo','crescimento_composto','%','{custo}','{}','digitado','Quando o insumo corre diferente do IPCA (commodity, energia, frete).'),
  ('SGA_PCT',         'SG&A (% da receita)',                'despesa','pct_de_linha','%','{despesa}','{}','digitado',null),
  ('DESPESA_FIXA',    'Despesa fixa por ano',               'despesa','valor_por_ano','R$/ano','{despesa}','{}','digitado',null),
  ('HEADCOUNT',       'Headcount',                          'operacional','preco_x_volume','un','{despesa}','{}','digitado','Usar junto de CUSTO_MEDIO_CABECA.'),
  ('CUSTO_MEDIO_CABECA','Custo médio por cabeça',           'despesa','preco_x_volume','R$/ano','{despesa}','{}','digitado',null),
  -- Giro, investimento, dívida, tributo, sócios
  ('PMR',             'Prazo médio de recebimento',         'giro','dias_de_giro','dias','{giro}','{}','digitado',null),
  ('PMP',             'Prazo médio de pagamento',           'giro','dias_de_giro','dias','{giro}','{}','digitado',null),
  ('PME',             'Prazo médio de estoque',             'giro','dias_de_giro','dias','{giro}','{}','digitado',null),
  ('CAPEX_ANO',       'Capex por ano',                      'investimento','valor_por_ano','R$/ano','{investimento}','{}','digitado',null),
  ('CAPEX_PCT',       'Capex (% da receita)',               'investimento','pct_de_linha','%','{investimento}','{}','digitado',null),
  ('DEPRECIACAO',     'Depreciação (% do imobilizado)',     'investimento','pct_de_linha','%','{investimento}','{}','digitado',null),
  ('DIVIDA_MOV',      'Captação (+) / amortização (−)',     'divida','valor_por_ano','R$/ano','{divida}','{}','digitado','Decisão do plano, não extrapolação do passado.'),
  ('TAXA_DIVIDA',     'Taxa média da dívida',               'divida','pct_de_linha','%','{divida}','{}','digitado',null),
  ('PARCELA_ONEROSA', 'Parcela onerosa do passivo',         'divida','pct_de_linha','%','{divida}','{}','digitado','Quanto do passivo cobra juro.'),
  ('ALIQUOTA',        'Alíquota efetiva de tributos',       'tributo','pct_de_linha','%','{tributo}','{}','digitado',null),
  ('SOCIOS_MOV',      'Aporte (+) / distribuição (−)',      'socios','valor_por_ano','R$/ano','{socios}','{}','digitado',null)
on conflict (codigo) do nothing;

-- ----- POR SETOR -------------------------------------------------------------
-- A "premissa que manda" de cada setor (a que o analista move primeiro) está na
-- descrição, porque é o que orienta quem nunca modelou aquele setor.
insert into premissa_catalogo (codigo, nome, natureza, formula, unidade, aplica_em, setores, fonte, descricao) values
  -- Indústria / metalurgia
  ('UTILIZACAO_CAP',  'Utilização da capacidade',           'operacional','pct_de_linha','%','{receita}','{industria}','digitado','A que manda junto de volume × preço: sem capacidade, volume não cresce.'),
  ('CUSTO_ENERGIA',   'Custo de energia',                   'custo','crescimento_composto','%','{custo}','{industria,mineracao,papel_celulose,quimica}','digitado',null),
  ('CUSTO_MP',        'Custo de matéria-prima',             'custo','crescimento_composto','%','{custo}','{industria,alimentos,automotivo,quimica,textil}','digitado',null),
  -- Varejo
  ('SSS',             'Same-store-sales',                   'receita','crescimento_composto','%','{receita}','{varejo,alimentos,farma}','digitado','A que manda no varejo: crescimento da loja madura, sem o efeito de abertura.'),
  ('N_LOJAS',         'Número de lojas',                    'operacional','preco_x_volume','un','{receita}','{varejo,farma,educacao}','digitado',null),
  ('TICKET_MEDIO',    'Ticket médio',                       'receita','preco_x_volume','R$/un','{receita}','{varejo,servicos,alimentos,saude}','digitado',null),
  ('QUEBRA_PERDA',    'Quebra / perda de estoque',          'custo','pct_de_linha','%','{custo}','{varejo,alimentos,farma}','digitado',null),
  -- Serviços
  ('OCUPACAO_EQUIPE', 'Taxa de ocupação da equipe',         'operacional','pct_de_linha','%','{receita}','{servicos}','digitado','A que manda em serviços junto de headcount.'),
  ('CHURN_CONTRATOS', 'Churn de contratos',                 'receita','pct_de_linha','%','{receita}','{servicos,tecnologia,telecom,educacao}','digitado',null),
  -- Agro
  ('AREA_PLANTADA',   'Área plantada',                      'operacional','preco_x_volume','ha','{receita}','{agro}','digitado',null),
  ('PRODUTIVIDADE',   'Produtividade (sc/ha)',              'operacional','preco_x_volume','sc/ha','{receita}','{agro}','digitado','A que manda no agro, junto do preço da commodity.'),
  ('PRECO_COMMODITY', 'Preço da commodity',                 'receita','preco_x_volume','R$/un','{receita}','{agro,alimentos,mineracao,papel_celulose}','digitado',null),
  ('CUSTO_HECTARE',   'Custo por hectare',                  'custo','pct_de_linha','R$/ha','{custo}','{agro}','digitado',null),
  -- Construção / incorporação
  ('VGV',             'VGV (valor geral de vendas)',        'receita','valor_por_ano','R$/ano','{receita}','{construcao}','digitado','A que manda em incorporação, junto do cronograma.'),
  ('CRONOGRAMA_FISICO','Cronograma físico-financeiro',      'sazonalidade','curva_mensal','%','{receita,custo}','{construcao}','digitado','Reconhecimento por evolução de obra — a curva importa mais que o total.'),
  ('VELOCIDADE_VENDAS','Velocidade de vendas (VSO)',        'receita','pct_de_linha','%','{receita}','{construcao,imobiliario}','digitado',null),
  ('DISTRATOS',       'Distratos',                          'receita','pct_de_linha','%','{receita}','{construcao}','digitado',null),
  -- Logística / transporte
  ('FROTA',           'Frota',                              'operacional','preco_x_volume','un','{receita}','{logistica}','digitado',null),
  ('OCUPACAO',        'Ocupação',                           'operacional','pct_de_linha','%','{receita}','{logistica,hotelaria,imobiliario,saude}','digitado','A que manda em logística.'),
  ('KM_RODADO',       'Km rodado',                          'operacional','preco_x_volume','km','{receita,custo}','{logistica}','digitado',null),
  ('PRECO_DIESEL',    'Preço do diesel',                    'custo','crescimento_composto','%','{custo}','{logistica,agro}','digitado',null),
  ('TAKE_OR_PAY',     'Contratos take-or-pay',              'receita','valor_por_ano','R$/ano','{receita}','{logistica,energia}','digitado','Receita contratada — não segue volume.'),
  -- Saúde
  ('SINISTRALIDADE',  'Sinistralidade',                     'custo','pct_de_linha','%','{custo}','{saude}','digitado','A que manda em saúde: custo assistencial sobre receita.'),
  ('TABELA_REEMBOLSO','Reajuste da tabela de reembolso',    'receita','crescimento_composto','%','{receita}','{saude}','digitado',null),
  ('GLOSA',           'Glosa',                              'receita','pct_de_linha','%','{receita}','{saude}','digitado',null),
  -- Energia
  ('TARIFA',          'Tarifa regulada',                    'receita','crescimento_composto','%','{receita}','{energia}','digitado','A que manda em energia.'),
  ('PLD',             'PLD (preço de liquidação)',          'receita','preco_x_volume','R$/MWh','{receita}','{energia}','digitado',null),
  ('DISPONIBILIDADE', 'Disponibilidade',                    'operacional','pct_de_linha','%','{receita}','{energia}','digitado',null),
  ('PERDAS',          'Perdas',                             'custo','pct_de_linha','%','{custo}','{energia}','digitado',null),
  -- Tecnologia
  ('ARR',             'ARR (receita recorrente anual)',     'receita','valor_por_ano','R$/ano','{receita}','{tecnologia}','digitado',null),
  ('CHURN',           'Churn',                              'receita','pct_de_linha','%','{receita}','{tecnologia,telecom}','digitado','A que manda em tecnologia: sem retenção, crescimento não compõe.'),
  ('CAC',             'CAC (custo de aquisição)',           'despesa','pct_de_linha','R$/un','{despesa}','{tecnologia}','digitado',null),
  ('LTV',             'LTV (valor do cliente)',             'receita','pct_de_linha','R$/un','{receita}','{tecnologia}','digitado',null),
  -- Alimentos e bebidas
  ('MIX_CANAL',       'Mix de canal',                       'receita','pct_de_linha','%','{receita}','{alimentos,farma,textil}','digitado',null),
  -- Educação
  ('N_ALUNOS',        'Número de alunos',                   'operacional','preco_x_volume','un','{receita}','{educacao}','digitado',null),
  ('EVASAO',          'Evasão',                             'receita','pct_de_linha','%','{receita}','{educacao}','digitado','A que manda em educação.'),
  ('INADIMPLENCIA',   'Inadimplência',                      'receita','pct_de_linha','%','{receita,giro}','{educacao,saude,imobiliario,varejo}','digitado',null),
  -- Mineração
  ('TEOR',            'Teor do minério',                    'operacional','pct_de_linha','%','{receita}','{mineracao}','digitado',null),
  ('CUSTO_CAIXA_TON', 'Custo caixa por tonelada',           'custo','pct_de_linha','R$/t','{custo}','{mineracao}','digitado',null),
  ('FRETE',           'Frete',                              'custo','crescimento_composto','%','{custo}','{mineracao,agro,alimentos,varejo}','digitado',null),
  -- Papel e celulose
  ('PRECO_USD',       'Preço em USD',                       'receita','preco_x_volume','US$/un','{receita}','{papel_celulose,mineracao,quimica}','digitado','Combinar com CAMBIO_USD — é o par que manda em exportador.'),
  ('CUSTO_MADEIRA',   'Custo de madeira',                   'custo','crescimento_composto','%','{custo}','{papel_celulose}','digitado',null),
  ('PARADA_MANUTENCAO','Parada de manutenção',              'sazonalidade','curva_mensal','%','{receita,custo}','{papel_celulose,quimica,industria}','digitado',null),
  -- Química / petroquímica
  ('SPREAD_MP',       'Spread de matéria-prima',            'custo','pct_de_linha','%','{custo,receita}','{quimica}','digitado','A que manda em petroquímica.'),
  -- Têxtil / vestuário
  ('COLECOES_ANO',    'Coleções por ano',                   'operacional','preco_x_volume','un','{receita}','{textil}','digitado',null),
  ('MARKDOWN',        'Markdown (remarcação)',              'receita','pct_de_linha','%','{receita}','{textil,varejo}','digitado','A que manda em vestuário.'),
  ('GIRO_ESTOQUE',    'Giro de estoque',                    'giro','dias_de_giro','dias','{giro}','{textil,varejo,alimentos}','digitado',null),
  -- Automotivo / autopeças
  ('PRODUCAO_CLIENTE','Produção do cliente (montadora)',    'operacional','preco_x_volume','un','{receita}','{automotivo}','digitado','A que manda em autopeças: a demanda é derivada.'),
  ('MARKET_SHARE',    'Market share',                       'receita','pct_de_linha','%','{receita}','{automotivo,alimentos,varejo}','digitado',null),
  ('FERRAMENTAL',     'Ferramental',                        'investimento','valor_por_ano','R$/ano','{investimento}','{automotivo}','digitado',null),
  -- Farma / distribuição
  ('MIX_GENERICOS',   'Mix de genéricos',                   'receita','pct_de_linha','%','{receita}','{farma}','digitado',null),
  ('CMED',            'Reajuste CMED',                      'receita','crescimento_composto','%','{receita}','{farma}','digitado','Teto regulatório de preço de medicamento.'),
  -- Telecom
  ('ARPU',            'ARPU',                               'receita','preco_x_volume','R$/un','{receita}','{telecom}','digitado','A que manda em telecom.'),
  ('BASE_ASSINANTES', 'Base de assinantes',                 'operacional','preco_x_volume','un','{receita}','{telecom}','digitado',null),
  ('CAPEX_REDE',      'Capex de rede',                      'investimento','valor_por_ano','R$/ano','{investimento}','{telecom,energia}','digitado',null),
  -- Hotelaria / turismo
  ('ADR',             'Diária média (ADR)',                 'receita','preco_x_volume','R$/un','{receita}','{hotelaria}','digitado',null),
  ('REVPAR',          'RevPAR',                             'receita','pct_de_linha','R$/un','{receita}','{hotelaria}','digitado','A que manda em hotelaria: junta ocupação e diária.'),
  -- Imobiliário de renda
  ('VACANCIA',        'Vacância',                           'receita','pct_de_linha','%','{receita}','{imobiliario}','digitado','A que manda em imobiliário de renda.'),
  ('ALUGUEL_M2',      'Aluguel por m²',                     'receita','preco_x_volume','R$/m²','{receita}','{imobiliario}','digitado',null)
on conflict (codigo) do nothing;

-- -----------------------------------------------------------------------------
-- fn_premissas_sugeridas — o que o setor COSTUMA usar. Sugestão, não restrição.
--
-- Base comum (`setores = '{}'`) sempre entra; as do setor entram junto. Setor
-- nulo ou desconhecido devolve só a base comum — que é o comportamento correto
-- para "ainda não sei o setor", e não um erro.
-- -----------------------------------------------------------------------------
create or replace function fn_premissas_sugeridas(p_setor text default null)
returns setof premissa_catalogo
language sql
stable
as $$
  select *
  from premissa_catalogo
  where ativo
    and (cardinality(setores) = 0 or (p_setor is not null and p_setor = any(setores)))
  order by natureza, codigo;
$$;

grant execute on function fn_premissas_sugeridas(text) to authenticated;

-- -----------------------------------------------------------------------------
-- fn_definir_modelagem — os parâmetros do caso, com trilha.
-- -----------------------------------------------------------------------------
create or replace function fn_definir_modelagem(
  p_caso_id uuid,
  p_entidade text,
  p_ultimo_exercicio_real int,
  p_indice_macro text,
  p_setor text,
  p_autor text,
  p_anos_projetados int default 5
)
returns jsonb
language plpgsql
as $$
declare
  v_antes jsonb;
begin
  if not exists (select 1 from caso where id = p_caso_id) then
    raise exception 'caso % não encontrado', p_caso_id;
  end if;

  select to_jsonb(m) into v_antes from caso_modelagem m where m.caso_id = p_caso_id;

  insert into caso_modelagem (caso_id, entidade, ultimo_exercicio_real, indice_macro, setor,
                              anos_projetados, atualizado_por, atualizado_em)
    values (p_caso_id, p_entidade, p_ultimo_exercicio_real, p_indice_macro, p_setor,
            p_anos_projetados, p_autor, now())
  on conflict (caso_id) do update
    set entidade = excluded.entidade,
        ultimo_exercicio_real = excluded.ultimo_exercicio_real,
        indice_macro = excluded.indice_macro,
        setor = excluded.setor,
        anos_projetados = excluded.anos_projetados,
        atualizado_por = excluded.atualizado_por,
        atualizado_em = now();

  -- Parâmetro de modelagem é DECISÃO DE ANÁLISE: trocar a entidade modelada ou o
  -- corte do último exercício real muda todos os números projetados do book.
  insert into evento_auditoria (ator, acao, entidade_ref, antes, depois)
    values (p_autor, 'modelagem_parametros', 'caso:'||p_caso_id, v_antes,
            (select to_jsonb(m) from caso_modelagem m where m.caso_id = p_caso_id));

  return (select to_jsonb(m) from caso_modelagem m where m.caso_id = p_caso_id);
end;
$$;

grant execute on function fn_definir_modelagem(uuid, text, int, text, text, text, int) to authenticated;

-- -----------------------------------------------------------------------------
-- fn_ativar_premissa — liga uma premissa do catálogo neste caso, com valores.
-- -----------------------------------------------------------------------------
create or replace function fn_ativar_premissa(
  p_caso_id uuid,
  p_codigo  text,
  p_valores jsonb,
  p_origem  text,
  p_autor   text
)
returns jsonb
language plpgsql
as $$
declare
  v_nome text;
begin
  select nome into v_nome from premissa_catalogo where codigo = p_codigo and ativo;
  if v_nome is null then
    -- Recusa RETORNADA (padrão das 0036/0037): premissa fora do catálogo é erro
    -- de chamador, e a tentativa interessa à trilha.
    insert into evento_auditoria (ator, acao, entidade_ref, depois)
      values (p_autor, 'premissa_recusada', 'caso:'||p_caso_id,
              jsonb_build_object('codigo', p_codigo, 'porque', 'codigo inexistente ou inativo no catalogo'));
    return jsonb_build_object('recusado', true,
      'motivo_recusa', format('A premissa "%s" não existe no catálogo (ou está inativa). '
                              'Premissa nova entra por semente no catálogo, não por caso.', p_codigo));
  end if;

  insert into caso_premissa (caso_id, premissa_codigo, valores, origem, ativo, atualizado_por, atualizado_em)
    values (p_caso_id, p_codigo, coalesce(p_valores, '{}'::jsonb), p_origem, true, p_autor, now())
  on conflict (caso_id, premissa_codigo) do update
    set valores = excluded.valores, origem = excluded.origem, ativo = true,
        atualizado_por = excluded.atualizado_por, atualizado_em = now();

  insert into decisao (caso_id, tipo, autor, motivo, payload)
    values (p_caso_id, 'override', p_autor,
            format('Premissa "%s" ativada/ajustada na modelagem', v_nome),
            jsonb_build_object('premissa', p_codigo, 'valores', p_valores, 'origem', p_origem));

  return jsonb_build_object('caso_id', p_caso_id, 'premissa', p_codigo, 'ativo', true);
end;
$$;

grant execute on function fn_ativar_premissa(uuid, text, jsonb, text, text) to authenticated;

-- -----------------------------------------------------------------------------
-- fn_vincular_linha_premissa — onde o input entra na projeção.
--
-- A GUARDA: só aceita premissa ATIVA NO CASO. Vincular linha a premissa que o
-- caso não ativou produziria linha "projetada" por uma premissa sem valor
-- nenhum — isto é, projetada com zero, que é a armadilha que este projeto já
-- combate no macro ("SEM FOCUS" projetando inflação zero).
-- -----------------------------------------------------------------------------
create or replace function fn_vincular_linha_premissa(
  p_caso_id uuid,
  p_secao_canonica text,
  p_rotulo text,
  p_entidade text,
  p_premissa text,
  p_autor text,
  p_sazonalidade text default null
)
returns jsonb
language plpgsql
as $$
declare
  v_rotulo_norm text := fn_normalizar_texto(p_rotulo);
begin
  if p_premissa is not null and not exists (
    select 1 from caso_premissa where caso_id = p_caso_id and premissa_codigo = p_premissa and ativo
  ) then
    return jsonb_build_object('recusado', true,
      'motivo_recusa', format('A premissa "%s" não está ATIVA neste caso. Ative-a (com valores) '
                              'antes de vincular linha — senão a linha sairia "projetada" por uma '
                              'premissa vazia, o que é projetar com zero.', p_premissa));
  end if;
  if p_sazonalidade is not null and not exists (
    select 1 from caso_premissa where caso_id = p_caso_id and premissa_codigo = p_sazonalidade and ativo
  ) then
    return jsonb_build_object('recusado', true,
      'motivo_recusa', format('A sazonalidade "%s" não está ativa neste caso.', p_sazonalidade));
  end if;

  insert into caso_linha_premissa (caso_id, secao_canonica, rotulo_norm, entidade,
                                   premissa_codigo, sazonalidade_codigo, atualizado_por, atualizado_em)
    values (p_caso_id, p_secao_canonica, v_rotulo_norm, p_entidade, p_premissa, p_sazonalidade, p_autor, now())
  on conflict (caso_id, rotulo_norm, coalesce(entidade, ''), coalesce(secao_canonica, '')) do update
    set premissa_codigo = excluded.premissa_codigo,
        sazonalidade_codigo = excluded.sazonalidade_codigo,
        atualizado_por = excluded.atualizado_por, atualizado_em = now();

  return jsonb_build_object('caso_id', p_caso_id, 'rotulo', v_rotulo_norm, 'premissa', p_premissa);
end;
$$;

grant execute on function fn_vincular_linha_premissa(uuid, text, text, text, text, text, text) to authenticated;

-- -----------------------------------------------------------------------------
-- fn_aplicar_premissa_em_lote — "todas as linhas de receita → crescimento real".
--
-- O lote roda no BANCO, não na tela: as linhas vêm de `campo_extraido`, e é aqui
-- que se sabe quais existem. Fazer isso no portal exigiria trazer todas as linhas
-- para o cliente e devolver uma por uma — num balancete de 500 linhas, 500
-- chamadas para uma decisão só.
--
-- Devolve quantas linhas foram vinculadas: o número é a conferência de que o
-- lote pegou o que se esperava (grupo errado = zero linhas, e isso tem de ser
-- visível em vez de parecer sucesso).
-- -----------------------------------------------------------------------------
create or replace function fn_aplicar_premissa_em_lote(
  p_caso_id uuid,
  p_secao_canonica text,
  p_premissa text,
  p_autor text,
  p_sazonalidade text default null
)
returns jsonb
language plpgsql
as $$
declare
  v_n int := 0;
  v_r jsonb;
  v_linha record;
begin
  if not exists (
    select 1 from caso_premissa where caso_id = p_caso_id and premissa_codigo = p_premissa and ativo
  ) then
    return jsonb_build_object('recusado', true,
      'motivo_recusa', format('A premissa "%s" não está ativa neste caso.', p_premissa));
  end if;

  for v_linha in
    select distinct ce.secao_canonica, ce.chave, coalesce(ce.entidade_coluna, e.razao_social) as entidade
    from campo_extraido ce
    join documento_versao dv on dv.id = ce.documento_versao_id
    join documento d on d.id = dv.documento_id
    left join entidade e on e.id = d.entidade_id
    where d.caso_id = p_caso_id
      and ce.secao_canonica = p_secao_canonica
      and ce.valor_num is not null
  loop
    v_r := fn_vincular_linha_premissa(p_caso_id, v_linha.secao_canonica, v_linha.chave,
                                      v_linha.entidade, p_premissa, p_autor, p_sazonalidade);
    if coalesce((v_r->>'recusado')::boolean, false) then
      return v_r;  -- se uma recusa acontece, todas recusariam pelo mesmo motivo
    end if;
    v_n := v_n + 1;
  end loop;

  insert into decisao (caso_id, tipo, autor, motivo, payload)
    values (p_caso_id, 'override', p_autor,
            format('Premissa "%s" aplicada em lote a %s linha(s) da seção "%s"',
                   p_premissa, v_n, coalesce(p_secao_canonica, '(sem seção)')),
            jsonb_build_object('premissa', p_premissa, 'secao_canonica', p_secao_canonica,
                               'n_linhas', v_n, 'sazonalidade', p_sazonalidade));

  return jsonb_build_object('caso_id', p_caso_id, 'secao_canonica', p_secao_canonica,
                            'premissa', p_premissa, 'n_linhas', v_n);
end;
$$;

grant execute on function fn_aplicar_premissa_em_lote(uuid, text, text, text, text) to authenticated;

-- -----------------------------------------------------------------------------
-- fn_conferir_modelagem — o que falta antes de exportar o completo.
--
-- Existe porque "linha sem premissa não é projetada" só é honesto se alguém
-- puder saber, ANTES de abrir o arquivo, quantas linhas ficaram de fora e quais
-- premissas ficaram sem valor. É o equivalente, na modelagem, do que
-- `fn_avaliar_portao2` é para a aprovação.
-- -----------------------------------------------------------------------------
create or replace function fn_conferir_modelagem(p_caso_id uuid)
returns jsonb
language plpgsql
stable
as $$
declare
  v_linhas_total int;
  v_linhas_com   int;
  v_premissas    int;
  v_sem_valor    text[];
  v_orfaos       text[];
  v_param        jsonb;
begin
  select count(distinct fn_normalizar_texto(ce.chave)) into v_linhas_total
  from campo_extraido ce
  join documento_versao dv on dv.id = ce.documento_versao_id
  join documento d on d.id = dv.documento_id
  where d.caso_id = p_caso_id and ce.valor_num is not null;

  -- CONTA POR JOIN, não por contagem de vínculos.
  --
  -- A primeira versão contava linhas de `caso_linha_premissa` direto, e o teste
  -- reprovou mostrando `linhas_com_premissa: 4` sobre `linhas_do_caso: 3` — com
  -- `linhas_sem_premissa` caindo para zero por subtração. Vínculo pode apontar
  -- para linha que não existe (configurada antes do documento chegar, ou o
  -- arquivo foi reextraído e o rótulo mudou), e nesse caso ele não cobre nada.
  select count(distinct l.rotulo_norm) into v_linhas_com
  from caso_linha_premissa l
  where l.caso_id = p_caso_id and l.premissa_codigo is not null
    and exists (
      select 1 from campo_extraido ce
      join documento_versao dv on dv.id = ce.documento_versao_id
      join documento d on d.id = dv.documento_id
      where d.caso_id = p_caso_id and ce.valor_num is not null
        and fn_normalizar_texto(ce.chave) = l.rotulo_norm
    );

  -- E os ÓRFÃOS ganham nome próprio: configuração apontando para linha que não
  -- existe é informação útil (o analista configurou e o documento não veio, ou
  -- veio com outro rótulo), não ruído a esconder.
  select array_agg(distinct l.rotulo_norm order by l.rotulo_norm) into v_orfaos
  from caso_linha_premissa l
  where l.caso_id = p_caso_id and l.premissa_codigo is not null
    and not exists (
      select 1 from campo_extraido ce
      join documento_versao dv on dv.id = ce.documento_versao_id
      join documento d on d.id = dv.documento_id
      where d.caso_id = p_caso_id and ce.valor_num is not null
        and fn_normalizar_texto(ce.chave) = l.rotulo_norm
    );

  select count(*) into v_premissas from caso_premissa where caso_id = p_caso_id and ativo;

  select array_agg(premissa_codigo order by premissa_codigo) into v_sem_valor
  from caso_premissa
  where caso_id = p_caso_id and ativo and (valores is null or valores = '{}'::jsonb);

  select to_jsonb(m) into v_param from caso_modelagem m where m.caso_id = p_caso_id;

  return jsonb_build_object(
    'parametros', v_param,
    'premissas_ativas', v_premissas,
    'premissas_sem_valor', to_jsonb(coalesce(v_sem_valor, array[]::text[])),
    'linhas_do_caso', v_linhas_total,
    'linhas_com_premissa', v_linhas_com,
    'linhas_sem_premissa', greatest(v_linhas_total - v_linhas_com, 0),
    -- Vínculo que não encontra linha: nomeado, não descartado.
    'vinculos_orfaos', to_jsonb(coalesce(v_orfaos, array[]::text[])),
    -- Pronto para o export completo: há parâmetros, há premissa ativa, e nenhuma
    -- premissa ativa está sem valor. Linha sem premissa NÃO impede — o arquivo a
    -- mostra como não projetada, que é informação legítima.
    'pronto', v_param is not null and v_premissas > 0 and coalesce(array_length(v_sem_valor, 1), 0) = 0
  );
end;
$$;

grant execute on function fn_conferir_modelagem(uuid) to authenticated;
