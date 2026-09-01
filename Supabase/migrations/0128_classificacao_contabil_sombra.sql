-- =============================================================================
-- Migration 0128 — A CLASSIFICAÇÃO CONTÁBIL passa a existir, em N0 (sombra)
--
-- O OITAVO ESTÁGIO DO MVP, COM ZERO LINHA DE CÓDIGO ATÉ AQUI.
--
-- O `Arquitetura do Sistema/1 Visão e Doutrina/03` lista oito estágios "dentro do MVP (tudo isto existe na v1 de
-- produção)", e um deles é *"Classificação contábil — presente em N0 (sombra):
-- registra sugestão, não decide"*. O `Arquitetura do Sistema/2 Especificação/05` o especifica por inteiro: taxonomia
-- fechada de cinco rótulos, as três condições de auto-aceite, o registro de
-- justificativa de toda sugestão, o registro de override humano. E a `0002` semeia
-- `classificacao_contabil` no dial, em N0 com teto N1.
--
-- Nada disso existia. Medido antes de escrever: `grep -rn 'classe_contabil\|
-- nao_recorrente\|candidato_ajuste_ebitda' db n8n Vercel/src` devolvia UMA
-- ocorrência — a coluna que a 0126 criou no golden set para guardar o rótulo
-- humano de uma classificação que ninguém produzia. Não havia enum, tabela,
-- sugestão nem captura de override. O EBITDA sai do modelo como linha de cascata,
-- sem nenhuma noção de recorrência.
--
-- E o dial dizia N0 com toda a convicção. N0 é "o estágio roda, registra a saída,
-- mas não influencia decisão" — a primeira metade daquela frase não estava
-- acontecendo. É a forma inversa do defeito que a 0127 corrigiu: lá o dial
-- subestimava a realidade, aqui ele afirmava a existência de um estágio.
--
-- COMO ELA DECIDE: REGRA DETERMINÍSTICA SOBRE RUBRICA. Decisão do dono, e ela
-- segue a condição 2 do próprio `Arquitetura do Sistema/2 Especificação/05` — *"bate com um padrão conhecido
-- (mapeamento de rubrica/keyword pré-registrado)"*. Sem IA e sem custo por
-- documento: o catálogo de rubricas é DADO, versionado, com justificativa escrita
-- por linha, e rubrica que ele não conhece cai em `revisar_manual`, que é o
-- default conservador que o `Arquitetura do Sistema/2 Especificação/05` manda ser o default.
--
-- EM N0 ELA NÃO TOCA EM NÚMERO NENHUM DO ARQUIVO ENTREGUE. Decisão do dono, e é a
-- leitura fiel de N0: a sugestão fica registrada e visível, o `.xlsx` sai idêntico
-- ao de hoje. É isso que permite acumular concordância sem risco de um número
-- errado chegar a comitê — e o override humano que se acumula é exatamente o sinal
-- de calibração de que a F4 se alimenta.
--
-- O QUE A REGRA COBRE, MEDIDO SOBRE OS DOIS BOOKS E O CASO DE REFERÊNCIA:
--
--   • 231 linhas de resultado com rubrica de verdade → **207 classificadas
--     (89,6%)**; as 24 restantes vão a `revisar_manual`, e cada uma por um motivo
--     que se sustenta: 6 são subtotais impressos que a `fn_papel_linha` não
--     reconhece como tal (ver a ressalva no corpo da regra), 1 é genuinamente
--     ambígua ("Outras receitas (despesas) operacionais, líquidas" — e aí
--     `revisar_manual` é a resposta CERTA) e o resto é artefato de fixture.
--   • O seed foi CORRIGIDO DUAS VEZES pela medição, e as duas correções estão
--     comentadas no próprio seed: a primeira versão cobria as deduções da receita e
--     não a receita (76% caindo em revisão), e a segunda não cobria "matéria-prima"
--     no singular nem a chave de mês do FATURAMENTO_24M.
--
-- =============================================================================
-- AS TRÊS DECISÕES DE DESENHO, E A PRIMEIRA VEIO DE UMA MEDIÇÃO
-- =============================================================================
--
-- 1. A REGRA SÓ RODA EM LINHA DE RESULTADO — e isto foi medido, não deduzido.
--    Recorrência é uma propriedade de linha de RESULTADO: uma conta do balanço não
--    é recorrente nem não recorrente, a pergunta não se aplica a ela. Rodar a
--    regra em tudo, com `revisar_manual` como default, produziria no fixture
--    atual **3.195 pedidos de revisão** contra 527 linhas em que a pergunta faz
--    sentido. Isso não seria conservador: seria destruir o sinal. Um analista que
--    recebe 3.195 itens para revisar não revisa nenhum — é o mesmo efeito que a
--    `0022` documentou ao refinar o Sinal 1 ("o teste v24 gerou 5 alertas falsos,
--    que é o pior resultado possível numa guarda: o analista aprende a ignorar o
--    aviso").
--
--    E AUSÊNCIA DE SUGESTÃO É A FORMA DE DIZER "NÃO SE APLICA". Não entra um
--    sexto rótulo para isso: o dono fechou a taxonomia nos cinco do `Arquitetura do Sistema/2 Especificação/05`, e
--    "não se aplica" não é um julgamento contábil — é o reconhecimento de que a
--    pergunta não foi feita. Linha de balanço simplesmente não ganha linha em
--    `campo_classe_sugerida`.
--
-- 2. A TAXONOMIA É TABELA, NÃO ENUM. Os cinco rótulos são os do `Arquitetura do Sistema/2 Especificação/05`, sem
--    acréscimo — decisão do dono. Mas eles entram como LINHAS de catálogo, porque
--    acrescentar um sexto rótulo daqui a três meses deve custar uma linha de seed,
--    e não uma migration que altera tipo (que no Postgres não remove valor e não
--    volta atrás). É a lição da `0038`, que fez o mesmo com premissas.
--
-- 3. O AUTO-ACEITE DO `Arquitetura do Sistema/2 Especificação/05` NÃO É IMPLEMENTADO, E O MOTIVO É UMA CONTRADIÇÃO
--    DO PRÓPRIO DOCUMENTO. O `Arquitetura do Sistema/2 Especificação/05` tem uma seção inteira sobre "quando a
--    sugestão PODE ser aceita (auto-aceite)", com três condições — e abre dizendo
--    "**teto N1 para sempre**: nunca vira número sem aceite humano". N1 é "a saída
--    aparece como sugestão; humano confirma todo item". Sob teto N1, auto-aceite
--    não pode acontecer nunca: as três condições descrevem um comportamento que a
--    própria doutrina do documento proíbe.
--
--    Implementá-las seria escrever código morto que um dia alguém liga por
--    engano. Não implementar e não dizer nada seria deixar a contradição para o
--    próximo. Então: `fn_classe_contabil_do_campo` devolve a classe EFETIVA como
--    "o override humano, ou nada" — a sugestão nunca é fato —, e a contradição
--    fica nomeada aqui e no `Arquitetura do Sistema/2 Especificação/05`.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- classe_contabil_catalogo — os cinco rótulos do `Arquitetura do Sistema/2 Especificação/05`, versionados.
-- -----------------------------------------------------------------------------
create table if not exists classe_contabil_catalogo (
  codigo      text primary key,
  nome        text not null,
  descricao   text not null,
  versao      int  not null default 1,
  ativo       boolean not null default true,
  ordem       int  not null
);

comment on table classe_contabil_catalogo is
  'A taxonomia contábil fechada do Arquitetura do Sistema/2 Especificação/05 (recorrente, nao_recorrente, extraordinario, '
  'candidato_ajuste_ebitda, revisar_manual). TABELA e não enum de propósito: acrescentar um sexto '
  'rótulo deve custar uma linha de seed, não uma migration que altera tipo — no Postgres alterar '
  'enum não remove valor e não volta atrás. Mesma escolha que a 0038 fez com premissas.';

insert into classe_contabil_catalogo (codigo, nome, descricao, ordem) values
  ('recorrente', 'Recorrente',
   'Acontece no curso normal do negócio e deve se repetir. É o default do que a operação produz.', 1),
  ('nao_recorrente', 'Não recorrente',
   'Ligado à operação, mas não deve se repetir: reestruturação, rescisões, assessores, impairment. '
   'Candidato natural a ajuste, mas quem decide é o humano.', 2),
  ('extraordinario', 'Extraordinário',
   'Fora do curso do negócio e sem previsão de repetição: adesão a transação tributária, ganho ou '
   'perda em evento único.', 3),
  ('candidato_ajuste_ebitda', 'Candidato a ajuste de EBITDA',
   'A rubrica é do tipo que costuma ser normalizada num EBITDA ajustado — provisões, perdas '
   'estimadas, obsolescência. Diz que MERECE OLHAR, nunca que o ajuste está feito.', 4),
  ('revisar_manual', 'Revisar manualmente',
   'O DEFAULT DE ESCAPE do Arquitetura do Sistema/2 Especificação/05. Rubrica que o catálogo não conhece, ou conhece e não determina '
   'recorrência. Não é falha da regra: é a regra dizendo que não sabe.', 5)
on conflict (codigo) do nothing;

-- -----------------------------------------------------------------------------
-- rubrica_classe — o "padrão conhecido pré-registrado" do `Arquitetura do Sistema/2 Especificação/05`, condição 2.
--
-- O CATÁLOGO É SEMEADO SÓ COM RUBRICA QUE APARECE DE VERDADE. Foram medidas as
-- rubricas presentes nos dois books e no caso de referência capturado da produção,
-- e é delas que sai a lista abaixo. Semear rubrica imaginada criaria a segunda
-- régua sobre a mesma quantidade — a forma de defeito que esta casa já pagou na
-- `0123`, no par fatiamento × orçamento e no limiar da classificação (`0127`).
--
-- Cada linha carrega `justificativa` NOT NULL, e isso não é burocracia: o `Arquitetura do Sistema/2 Especificação/05`
-- exige justificativa em toda sugestão, e a justificativa da sugestão é a da regra
-- que a produziu. Sem o campo obrigatório, a primeira rubrica cadastrada às
-- pressas viraria um rótulo sem defesa possível numa reunião.
-- -----------------------------------------------------------------------------
create table if not exists rubrica_classe (
  id              uuid primary key default gen_random_uuid(),
  padrao          text not null,
  classe_codigo   text not null references classe_contabil_catalogo(codigo),
  -- Quando preenchidos, restringem: a regra só vale naquela seção / naquele tipo.
  -- Nulo = vale em qualquer linha de resultado.
  secao_canonica  text,
  tipo_taxonomia  text,
  -- Mais específico ganha. Ver fn_classe_contabil_sugerir.
  especificidade  int  not null default 100,
  confianca       numeric not null default 1.0,
  justificativa   text not null,
  versao          int  not null default 1,
  ativo           boolean not null default true,
  criado_em       timestamptz not null default now()
);

create unique index if not exists idx_rubrica_classe_unica on rubrica_classe
  (padrao, coalesce(secao_canonica, ''), coalesce(tipo_taxonomia, ''), versao);

comment on table rubrica_classe is
  'Mapeamento rubrica -> classe contábil: a "condição 2" do Arquitetura do Sistema/2 Especificação/05 ("bate com um padrão conhecido '
  'pré-registrado"). Semeado SÓ com rubricas medidas nos dois books e no caso de referência — '
  'rubrica imaginada criaria uma segunda régua. justificativa é NOT NULL porque o Arquitetura do Sistema/2 Especificação/05 exige '
  'justificativa em toda sugestão, e a da sugestão é a da regra que a produziu.';

comment on column rubrica_classe.especificidade is
  'Desempate: mais ALTO ganha. Regra com seção e tipo declarados é mais específica que a genérica, e '
  'sem desempate declarado duas regras que casam a mesma linha dariam resultado dependente da ordem '
  'em que o banco devolveu — que é a forma de erro que a 0125 corrigiu na proveniência.';

comment on column rubrica_classe.padrao is
  'Casado contra fn_normalizar_texto(chave) por CONTENÇÃO de substring normalizada. Não é regex: '
  'padrão de regex em tabela editável por humano é a porta para uma linha quebrar a classificação '
  'do caso inteiro sem ninguém saber por quê.';

-- -----------------------------------------------------------------------------
-- campo_classe_sugerida — o "registro de justificativa (toda sugestão)" do
-- `Arquitetura do Sistema/2 Especificação/05`, campo a campo.
--
-- APPEND-ONLY, pelo par de políticas do `evento_auditoria` (0003) e do
-- `caso_pergunta` (0120): SELECT e INSERT, nenhuma de UPDATE ou DELETE. Sem
-- política para um comando, o RLS nega aquele comando.
--
-- Por que append-only importa aqui: a sequência de sugestões que o sistema deu a
-- uma linha ao longo do tempo é o histórico contra o qual a concordância humana é
-- medida. Sugestão editável depois do override apagaria a discordância que é o
-- dado de calibração.
-- -----------------------------------------------------------------------------
create table if not exists campo_classe_sugerida (
  id                uuid primary key default gen_random_uuid(),
  campo_extraido_id uuid not null references campo_extraido(id) on delete cascade,
  classe_codigo     text not null references classe_contabil_catalogo(codigo),
  confianca         numeric,
  rubrica_id        uuid references rubrica_classe(id),
  justificativa     text not null,
  versao_taxonomia  int  not null,
  nivel_autonomia   nivel_autonomia not null,
  criado_em         timestamptz not null default now()
);

create index if not exists idx_campo_classe_sugerida_campo
  on campo_classe_sugerida (campo_extraido_id, criado_em desc);

comment on table campo_classe_sugerida is
  'A sugestão da classificação contábil, com a justificativa que o Arquitetura do Sistema/2 Especificação/05 exige de toda sugestão. '
  'AUSÊNCIA de linha aqui significa "a pergunta não se aplica" — linha de balanço não é recorrente '
  'nem não recorrente. nivel_autonomia guarda em que nível o estágio estava quando sugeriu, porque '
  'uma sugestão feita em N0 e uma feita em N1 têm peso diferente na leitura de quem confere.';

-- -----------------------------------------------------------------------------
-- campo_classe_override — o "registro de override humano" do `Arquitetura do Sistema/2 Especificação/05`.
--
-- É ELE O SINAL DE CALIBRAÇÃO, e é a razão pela qual esta migration vale a pena
-- mesmo em sombra: *"o override vira sinal de calibração — onde humanos discordam
-- sistematicamente da máquina, ajusta-se regra/threshold (ou não se sobe o dial
-- daquele estágio)"*. Cada override é um ponto de golden set que o próprio uso do
-- produto gera, sem rotulagem dedicada — a mesma economia que a `0126` achou na
-- taxa de falso-positivo da Classe A, onde o rótulo é o veredito da `0106`.
-- -----------------------------------------------------------------------------
create table if not exists campo_classe_override (
  id                uuid primary key default gen_random_uuid(),
  campo_extraido_id uuid not null references campo_extraido(id) on delete cascade,
  classe_final      text not null references classe_contabil_catalogo(codigo),
  sugestao_original text,
  autor             text not null,
  motivo            text,
  criado_em         timestamptz not null default now()
);

create index if not exists idx_campo_classe_override_campo
  on campo_classe_override (campo_extraido_id, criado_em desc);

comment on table campo_classe_override is
  'A decisão humana sobre a classe contábil de uma linha (Arquitetura do Sistema/2 Especificação/05, "registro de override humano"). '
  'Append-only: reclassificar é linha nova, e a sequência é o histórico. É ele o SINAL DE '
  'CALIBRAÇÃO da F4 — cada override é um ponto de concordância medida que o uso do produto gera '
  'sozinho, sem rotulagem dedicada.';

-- -----------------------------------------------------------------------------
-- RLS append-only nas duas, e leitura no catálogo.
-- -----------------------------------------------------------------------------
alter table classe_contabil_catalogo enable row level security;
alter table rubrica_classe           enable row level security;
alter table campo_classe_sugerida    enable row level security;
alter table campo_classe_override    enable row level security;

drop policy if exists classe_contabil_catalogo_read on classe_contabil_catalogo;
create policy classe_contabil_catalogo_read on classe_contabil_catalogo
  for select to authenticated using (true);

drop policy if exists rubrica_classe_read on rubrica_classe;
create policy rubrica_classe_read on rubrica_classe
  for select to authenticated using (true);

drop policy if exists campo_classe_sugerida_read   on campo_classe_sugerida;
drop policy if exists campo_classe_sugerida_insert on campo_classe_sugerida;
create policy campo_classe_sugerida_read   on campo_classe_sugerida
  for select to authenticated using (true);
create policy campo_classe_sugerida_insert on campo_classe_sugerida
  for insert to authenticated with check (true);

drop policy if exists campo_classe_override_read   on campo_classe_override;
drop policy if exists campo_classe_override_insert on campo_classe_override;
create policy campo_classe_override_read   on campo_classe_override
  for select to authenticated using (true);
create policy campo_classe_override_insert on campo_classe_override
  for insert to authenticated with check (true);

-- -----------------------------------------------------------------------------
-- O SEED DAS RUBRICAS.
--
-- Todas as rubricas abaixo foram MEDIDAS: elas aparecem nos dois books e/ou no
-- caso de referência capturado da produção. Nenhuma foi imaginada.
--
-- `especificidade` 200 para o que é evento (reestruturação, impairment, transação
-- tributária) e 100 para o que é curso normal: quando as duas casam a mesma linha,
-- o evento ganha. Sem esse desempate declarado, "Multas e juros reconhecidos na
-- adesão à transação tributária" poderia sair como despesa financeira recorrente
-- só porque o banco devolveu aquela regra primeiro.
-- -----------------------------------------------------------------------------
insert into rubrica_classe (padrao, classe_codigo, especificidade, justificativa) values
  -- ---- evento: não deve se repetir ----------------------------------------
  ('despesas de reestruturacao', 'nao_recorrente', 200,
   'Reestruturação é, por definição, o evento que o mandato está tratando: não integra o curso '
   'normal e não deve se repetir depois de concluída.'),
  ('assessores', 'nao_recorrente', 200,
   'Honorário de assessor contratado para o evento (jurídico, financeiro, M&A) termina com o '
   'evento. Difere de honorário da administração, que é recorrente.'),
  ('rescis', 'nao_recorrente', 200,
   'Rescisão trabalhista ligada a corte de estrutura acompanha a reestruturação, não a operação.'),
  ('impairment', 'nao_recorrente', 200,
   'Perda por redução ao valor recuperável é reconhecimento pontual de valor de ativo, não '
   'consumo do exercício.'),
  ('reducao ao valor recuperavel', 'nao_recorrente', 200,
   'Mesma rubrica do impairment escrita em português — as duas grafias aparecem nos documentos.'),

  -- ---- extraordinário: fora do curso do negócio ---------------------------
  ('transacao tributaria', 'extraordinario', 200,
   'Adesão a programa de transação/anistia tributária é evento único de negociação com o fisco, '
   'fora de qualquer curso normal de operação.'),

  -- ---- candidato a ajuste de EBITDA ---------------------------------------
  ('provisao para contingencias', 'candidato_ajuste_ebitda', 200,
   'Provisão para contingência é estimativa que costuma ser normalizada num EBITDA ajustado. O '
   'rótulo diz que MERECE OLHAR — quem decide o ajuste é o analista.'),
  ('provisao para obsolescencia', 'candidato_ajuste_ebitda', 200,
   'Obsolescência de estoque é ajuste de valor, não consumo do exercício, e entra na conversa de '
   'EBITDA ajustado com frequência.'),
  ('perdas estimadas em creditos', 'candidato_ajuste_ebitda', 200,
   'PECLD é operacional e recorrente na maioria dos casos, MAS um salto dela num ano é justamente '
   'o que se normaliza. Marcada como candidata para o analista olhar, não como não recorrente.'),

  -- ---- curso normal do negócio -------------------------------------------
  ('materias-primas', 'recorrente', 100, 'Consumo de insumo é o curso normal da operação industrial.'),
  ('mao de obra direta', 'recorrente', 100, 'Folha de produção é custo recorrente da operação.'),
  ('energia eletrica', 'recorrente', 100, 'Utilidade industrial consumida no exercício.'),
  ('custos indiretos de fabricacao', 'recorrente', 100, 'Rateio de produção do exercício.'),
  ('outros custos de producao', 'recorrente', 100, 'Custo de produção do exercício.'),
  ('depreciacao', 'recorrente', 100,
   'Depreciação é recorrente por natureza — e fica abaixo do EBITDA por definição, então o rótulo '
   'aqui é sobre recorrência, não sobre ajuste.'),
  ('amortizacao', 'recorrente', 100, 'Mesma natureza da depreciação.'),
  ('honorarios da administracao', 'recorrente', 100,
   'Remuneração de administrador é despesa recorrente da estrutura. Difere de honorário de '
   'assessor de evento, que tem regra própria mais específica.'),
  ('despesas gerais e administrativas', 'recorrente', 100, 'Estrutura administrativa do exercício.'),
  ('despesas com vendas', 'recorrente', 100, 'Despesa comercial do exercício.'),
  ('despesas tributarias', 'recorrente', 100,
   'Tributo sobre atividade (taxas, contribuições) recorre com a operação.'),
  ('icms sobre vendas', 'recorrente', 100, 'Dedução de receita, recorrente com o faturamento.'),
  ('ipi sobre vendas', 'recorrente', 100, 'Dedução de receita, recorrente com o faturamento.'),
  ('pis e cofins', 'recorrente', 100, 'Dedução de receita, recorrente com o faturamento.'),
  ('devolucoes', 'recorrente', 100, 'Devolução e abatimento acompanham o volume de venda.'),
  ('imposto de renda e contribuicao social', 'recorrente', 100,
   'Tributo sobre o lucro é recorrente e fica abaixo do EBITDA.'),
  ('variacoes monetarias e cambiais', 'recorrente', 100,
   'Resultado financeiro do exercício. Recorrente em empresa com dívida ou moeda estrangeira.'),
  ('despesas financeiras', 'recorrente', 100, 'Custo da dívida, recorrente enquanto a dívida existe.'),
  ('juros e encargos bancarios', 'recorrente', 100, 'Custo da dívida do exercício.'),

  -- ---- receita: o buraco que a MEDIÇÃO achou ------------------------------
  -- A primeira versão deste seed cobria as DEDUÇÕES da receita (ICMS, IPI,
  -- PIS/COFINS, devoluções) e não cobria a receita em si. Rodada sobre os dois
  -- books, ela mandou "Vendas de embalagens", "Receita de exportação" e os doze
  -- "Faturamento <mês>" para revisão humana — 76% das linhas caindo em
  -- revisar_manual, quase todas por esta lacuna. Receita no curso normal do
  -- negócio é o exemplo canônico de recorrente.
  ('vendas de', 'recorrente', 100,
   'Venda de produto no curso normal do negócio. Cobre "Vendas de embalagens - mercado interno/'
   'externo" e formas equivalentes.'),
  ('receita com venda', 'recorrente', 100, 'Receita de produto do exercício.'),
  ('receita de exportacao', 'recorrente', 100,
   'Exportação é canal de venda, não evento — recorrente enquanto o canal existe.'),
  ('prestacao de servico', 'recorrente', 100, 'Receita de serviço no curso normal.'),
  ('faturamento', 'recorrente', 100,
   'Linha de série mensal de faturamento (documento FATURAMENTO_24M). É receita do mês, recorrente '
   'por natureza.'),
  ('variacoes cambiais', 'recorrente', 100,
   'A grafia que os documentos usam de fato ("Variações cambiais líquidas"), ao lado de "variações '
   'monetárias e cambiais". Casamento por substring não cobre as duas com um padrão só.'),

  -- ---- o que a SEGUNDA medição achou --------------------------------------
  ('materia-prima', 'recorrente', 100,
   'No singular, que é como um dos documentos escreve ("Matéria-prima consumida"). O padrão no '
   'plural com hífen não casa o singular — substring é literal, e é isso que a torna auditável.'),
  ('receitas financeiras', 'recorrente', 100,
   'Rendimento de aplicação e juros ativos: resultado financeiro do exercício, recorrente enquanto '
   'houver caixa aplicado.'),
  ('empresas do grupo', 'candidato_ajuste_ebitda', 200,
   'Receita ou despesa intragrupo é RECORRENTE para a empresa isolada e ELIMINADA no combinado — '
   'então ela merece olhar sempre que o EBITDA em discussão for o do grupo. O rótulo diz merece '
   'olhar, não diz que o ajuste está feito. (A conferência do saldo intragrupo é outra coisa, e '
   'mora na 0117/0124.)'),

  -- ---- e o caso em que o TIPO do documento decide sozinho ------------------
  -- Num FATURAMENTO_24M toda linha é receita do mês: as chaves são "abr/2025",
  -- "jan/2025" e assim por diante, e nenhuma delas é uma rubrica que um padrão de
  -- texto reconheça. O padrão VAZIO é o coringa (position('' in qualquer) = 1), e a
  -- especificidade 50 — a mais baixa da tabela — garante que qualquer regra de
  -- rubrica de verdade ganhe dele.
  ('', 'recorrente', 50,
   'Coringa do FATURAMENTO_24M: neste tipo de documento toda linha é receita do mês, e a chave é o '
   'próprio mês ("abr/2025"). Especificidade 50 para qualquer regra de rubrica ganhar deste coringa.')
on conflict do nothing;

update rubrica_classe set tipo_taxonomia = 'FATURAMENTO_24M'
 where padrao = '' and tipo_taxonomia is null;

-- =============================================================================
-- AS FUNÇÕES
-- =============================================================================

-- -----------------------------------------------------------------------------
-- fn_secao_e_de_resultado — a lista fechada, num lugar só.
--
-- Recorrência é propriedade de linha de RESULTADO. Conta de balanço não é
-- recorrente nem não recorrente: a pergunta não se aplica. Esta função existe para
-- essa lista não ser escrita duas vezes — e ela é a razão pela qual o
-- `revisar_manual` não inunda: no fixture atual são 527 linhas de resultado contra
-- 3.195 que não são.
-- -----------------------------------------------------------------------------
create or replace function fn_secao_e_de_resultado(p_secao text)
returns boolean
language sql
immutable
as $$
  select coalesce(p_secao, '') in
    ('receita_bruta', 'custos', 'despesas_operacionais', 'resultado_financeiro', 'impostos_lucro');
$$;

comment on function fn_secao_e_de_resultado(text) is
  'Esta seção canônica é de RESULTADO? Só nelas a pergunta "é recorrente?" faz sentido — conta de '
  'balanço não é recorrente nem não recorrente. Medido: rodar a classificação em tudo produziria '
  '3.195 pedidos de revisão contra 527 linhas em que a pergunta cabe, e um analista que recebe '
  '3.195 itens não revisa nenhum (é a lição do Sinal 1 refinado na 0022).';

grant execute on function fn_secao_e_de_resultado(text) to authenticated;

-- -----------------------------------------------------------------------------
-- fn_classe_contabil_sugerir — a regra determinística, condição 2 do `Arquitetura do Sistema/2 Especificação/05`.
--
-- Devolve NULL quando a pergunta não se aplica (linha que não é de resultado), e
-- `revisar_manual` quando ela se aplica e o catálogo não sabe. As duas coisas são
-- diferentes e confundi-las é o que produziria a inundação.
-- -----------------------------------------------------------------------------
create or replace function fn_classe_contabil_sugerir(
  p_chave          text,
  p_secao_canonica text,
  p_tipo_taxonomia text default null
)
returns jsonb
language plpgsql
stable
as $$
declare
  v_norm text;
  v_r    record;
begin
  if not fn_secao_e_de_resultado(p_secao_canonica) then
    return null;   -- a pergunta não se aplica; ausência de sugestão é a resposta
  end if;

  v_norm := fn_normalizar_texto(coalesce(p_chave, ''));
  if v_norm = '' then
    return null;
  end if;

  -- SUBTOTAL NÃO TEM RECORRÊNCIA PRÓPRIA: ela é herdada dos componentes. Mandar um
  -- subtotal para revisão humana é pedir uma decisão que não existe.
  --
  -- E aqui vai a ressalva medida, porque ela importa: `fn_papel_linha` NÃO pega
  -- todo subtotal impresso. Conferido — ela devolve `conta` para
  -- "CUSTO DOS PRODUTOS VENDIDOS" e para "(-) DESPESAS OPERACIONAIS", que são
  -- subtotais no documento. Então este filtro REDUZ o ruído sem eliminá-lo, e
  -- dizer o contrário seria prometer o que ele não cumpre. Quando ela diz
  -- `subtotal` ou `derivado`, aí é confiável — e é só nesse caso que se pula.
  if fn_papel_linha(p_chave, p_tipo_taxonomia, null) in ('subtotal', 'derivado') then
    return null;
  end if;

  -- Mais específico ganha, e o desempate é DECLARADO (especificidade, depois
  -- comprimento do padrão): duas regras que casam a mesma linha não podem dar
  -- resultado dependente da ordem em que o banco devolveu.
  select rc.id, rc.classe_codigo, rc.confianca, rc.justificativa, rc.versao
    into v_r
  from rubrica_classe rc
  where rc.ativo
    and position(fn_normalizar_texto(rc.padrao) in v_norm) > 0
    and (rc.secao_canonica is null or rc.secao_canonica = p_secao_canonica)
    and (rc.tipo_taxonomia is null or rc.tipo_taxonomia = p_tipo_taxonomia)
  order by rc.especificidade desc, length(rc.padrao) desc, rc.padrao
  limit 1;

  if v_r.id is null then
    return jsonb_build_object(
      'classe', 'revisar_manual',
      'confianca', null,
      'rubrica_id', null,
      'justificativa', format('Nenhuma rubrica do catálogo casa com "%s". O Arquitetura do Sistema/2 Especificação/05 manda o default '
                              'ser conservador: rubrica nova vai para revisão humana, não recebe '
                              'palpite.', p_chave),
      'versao_taxonomia', (select max(versao) from classe_contabil_catalogo));
  end if;

  return jsonb_build_object(
    'classe', v_r.classe_codigo,
    'confianca', v_r.confianca,
    'rubrica_id', v_r.id,
    'justificativa', v_r.justificativa,
    'versao_taxonomia', v_r.versao);
end;
$$;

comment on function fn_classe_contabil_sugerir(text, text, text) is
  'A regra determinística do Arquitetura do Sistema/2 Especificação/05 (condição 2: casa com padrão pré-registrado). NULL = a pergunta '
  'não se aplica (linha que não é de resultado); revisar_manual = ela se aplica e o catálogo não '
  'sabe. Confundir as duas produziria 3.195 pedidos de revisão em vez de 527. Desempate DECLARADO '
  'por especificidade: duas regras que casam a mesma linha não podem depender da ordem do banco.';

grant execute on function fn_classe_contabil_sugerir(text, text, text) to authenticated;

-- -----------------------------------------------------------------------------
-- fn_classificar_contabil — roda a regra sobre uma versão de documento e REGISTRA.
--
-- É a primeira metade de N0: "o estágio roda, registra a saída". A segunda metade
-- ("não influencia decisão") é garantida por construção — esta função só escreve em
-- `campo_classe_sugerida`, não abre pendência, não toca em `campo_extraido` e não
-- entra em nenhum caminho de export.
--
-- APPEND-ONLY SEM DUPLICAR: a sugestão só é gravada quando difere da última
-- daquele campo. Rodar duas vezes com o mesmo catálogo não cria duas linhas; mudar
-- uma rubrica do catálogo e rodar de novo cria — e a sequência passa a ser o
-- histórico de como a regra evoluiu, que é o que a concordância medida precisa.
--
-- O NÍVEL É LIDO, não suposto: `fn_dial_influencia` (0127) decide se este estágio
-- pode registrar, e o nível vigente é gravado na própria linha. Em N0 registra; se
-- alguém um dia baixar para... — não há nível abaixo de N0, então em N0 ele roda.
-- O que a leitura garante é o oposto: se o estágio subir para N1, a sugestão
-- passa a carregar N1 na linha, e quem confere sabe com que peso ela foi feita.
-- -----------------------------------------------------------------------------
create or replace function fn_classificar_contabil(p_documento_versao_id uuid)
returns int
language plpgsql
as $$
declare
  v_nivel   nivel_autonomia;
  v_c       record;
  v_sug     jsonb;
  v_ultima  text;
  v_n       int := 0;
begin
  select ea.nivel_atual into v_nivel
  from estagio_autonomia ea where ea.estagio = 'classificacao_contabil';
  -- Sem linha no dial (banco antigo), NÃO classifica. Ausência de configuração não
  -- é permissão para escrever — mesma regra da 0041 e da 0127.
  if v_nivel is null then
    return 0;
  end if;

  for v_c in
    select ce.id, ce.chave, ce.secao_canonica, d.tipo_taxonomia
    from campo_extraido ce
    join documento_versao dv on dv.id = ce.documento_versao_id
    join documento d on d.id = dv.documento_id
    where ce.documento_versao_id = p_documento_versao_id
      and fn_secao_e_de_resultado(ce.secao_canonica)
  loop
    v_sug := fn_classe_contabil_sugerir(v_c.chave, v_c.secao_canonica, v_c.tipo_taxonomia);
    if v_sug is null then
      continue;   -- a pergunta não se aplica a esta linha
    end if;

    select s.classe_codigo into v_ultima
    from campo_classe_sugerida s
    where s.campo_extraido_id = v_c.id
    order by s.criado_em desc, s.id desc
    limit 1;

    if v_ultima is not null and v_ultima = (v_sug->>'classe') then
      continue;   -- a regra não mudou de opinião: não há o que acrescentar
    end if;

    insert into campo_classe_sugerida
      (campo_extraido_id, classe_codigo, confianca, rubrica_id, justificativa,
       versao_taxonomia, nivel_autonomia)
    values (v_c.id, v_sug->>'classe',
            (v_sug->>'confianca')::numeric,
            (v_sug->>'rubrica_id')::uuid,
            v_sug->>'justificativa',
            coalesce((v_sug->>'versao_taxonomia')::int, 1),
            v_nivel);
    v_n := v_n + 1;
  end loop;

  if v_n > 0 then
    insert into evento_auditoria (ator, acao, entidade_ref, depois)
      values ('sistema:classificacao_contabil', 'classificacao_contabil_sombra',
              'documento_versao:'||p_documento_versao_id,
              jsonb_build_object('sugestoes', v_n, 'nivel', v_nivel,
                                 'porque', 'N0: registra a sugestao e nao influencia decisao '
                                           '(Arquitetura do Sistema/1 Visão e Doutrina/01). Nenhuma pendencia aberta, nenhum numero '
                                           'do export tocado.'));
  end if;
  return v_n;
end;
$$;

comment on function fn_classificar_contabil(uuid) is
  'Roda a classificação contábil sobre uma versão e REGISTRA a sugestão — a primeira metade de N0. A '
  'segunda ("não influencia decisão") é garantida por construção: só escreve em '
  'campo_classe_sugerida, não abre pendência e não entra em caminho de export. Append-only sem '
  'duplicar: grava só quando a regra muda de opinião, e aí a sequência é o histórico.';

grant execute on function fn_classificar_contabil(uuid) to authenticated;

-- -----------------------------------------------------------------------------
-- fn_classe_contabil_do_campo — a classe EFETIVA, e a anti-ancoragem por desenho.
--
-- Devolve a sugestão E o override, separados, e um `classe_efetiva` que é **só o
-- override**. A sugestão nunca é fato: é o fechamento #5 do `Arquitetura do Sistema/1 Visão e Doutrina/01` ("nenhum
-- número entra na base de modelagem sem evento de aceite humano explícito")
-- aplicado à classificação, e é a razão de o teto dela ser N1 para sempre.
--
-- Se um dia alguém quiser que a sugestão valha sozinha, vai ter de mudar ESTA
-- função — e não vai conseguir por acidente.
-- -----------------------------------------------------------------------------
create or replace function fn_classe_contabil_do_campo(p_campo_extraido_id uuid)
returns jsonb
language sql
stable
as $$
  with sug as (
    select s.classe_codigo, s.confianca, s.justificativa, s.criado_em, s.nivel_autonomia
    from campo_classe_sugerida s
    where s.campo_extraido_id = p_campo_extraido_id
    order by s.criado_em desc, s.id desc limit 1
  ), ovr as (
    select o.classe_final, o.autor, o.motivo, o.criado_em
    from campo_classe_override o
    where o.campo_extraido_id = p_campo_extraido_id
    order by o.criado_em desc, o.id desc limit 1
  )
  select jsonb_build_object(
    -- SÓ o override. A sugestão nunca vira fato — fechamento #5 do Arquitetura do Sistema/1 Visão e Doutrina/01.
    'classe_efetiva', (select classe_final from ovr),
    'aceita_por_humano', exists (select 1 from ovr),
    'sugestao', (select jsonb_build_object(
                   'classe', classe_codigo, 'confianca', confianca,
                   'justificativa', justificativa, 'em', criado_em,
                   'nivel_quando_sugerida', nivel_autonomia) from sug),
    'override', (select jsonb_build_object(
                   'classe', classe_final, 'autor', autor, 'motivo', motivo,
                   'em', criado_em) from ovr),
    'humano_discordou', (select o.classe_final from ovr o) is not null
                        and (select s.classe_codigo from sug s) is not null
                        and (select o.classe_final from ovr o)
                            <> (select s.classe_codigo from sug s)
  );
$$;

comment on function fn_classe_contabil_do_campo(uuid) is
  'A classe contábil efetiva de uma linha — e ela é SÓ o override humano. A sugestão vem no mesmo '
  'objeto, separada, e nunca conta como fato: é o fechamento #5 do Arquitetura do Sistema/1 Visão e Doutrina/01 aplicado à '
  'classificação, e a razão de o teto dela ser N1 para sempre. Mudar isso exige mudar esta função, '
  'de propósito.';

grant execute on function fn_classe_contabil_do_campo(uuid) to authenticated;

-- -----------------------------------------------------------------------------
-- fn_registrar_classe_override — a decisão humana, append-only.
--
-- RECUSA RETORNADA, não exceção (padrão 0036/0037/0038/0041/0126): a exceção
-- desfaria o registro da própria tentativa.
-- -----------------------------------------------------------------------------
create or replace function fn_registrar_classe_override(
  p_campo_extraido_id uuid,
  p_classe_final      text,
  p_autor             text,
  p_motivo            text default null
)
returns jsonb
language plpgsql
as $$
declare
  v_sug   text;
  v_id    uuid;
begin
  if not exists (select 1 from campo_extraido where id = p_campo_extraido_id) then
    return jsonb_build_object('recusado', true,
      'motivo_recusa', format('Linha extraída %s não existe.', p_campo_extraido_id));
  end if;
  if not exists (select 1 from classe_contabil_catalogo
                  where codigo = p_classe_final and ativo) then
    return jsonb_build_object('recusado', true,
      'motivo_recusa', format('"%s" não é uma classe contábil ativa. A taxonomia é FECHADA '
                              '(Arquitetura do Sistema/2 Especificação/05) e mora em classe_contabil_catalogo — rótulo novo entra por '
                              'linha de catálogo, não por chamada.', p_classe_final));
  end if;
  if coalesce(trim(p_autor), '') = '' then
    return jsonb_build_object('recusado', true,
      'motivo_recusa', 'Override sem autor não é override: o Arquitetura do Sistema/2 Especificação/05 exige autor no registro, e sem '
                       'ele o sinal de calibração não tem de quem discordar.');
  end if;

  select s.classe_codigo into v_sug
  from campo_classe_sugerida s
  where s.campo_extraido_id = p_campo_extraido_id
  order by s.criado_em desc, s.id desc limit 1;

  insert into campo_classe_override
    (campo_extraido_id, classe_final, sugestao_original, autor, motivo)
  values (p_campo_extraido_id, p_classe_final, v_sug, trim(p_autor), p_motivo)
  returning id into v_id;

  insert into evento_auditoria (ator, acao, entidade_ref, antes, depois)
    values (trim(p_autor), 'classe_contabil_override',
            'campo_extraido:'||p_campo_extraido_id,
            jsonb_build_object('sugestao', v_sug),
            jsonb_build_object('classe_final', p_classe_final, 'motivo', p_motivo,
                               'discordou', v_sug is not null and v_sug <> p_classe_final));

  return jsonb_build_object('override_id', v_id, 'classe_final', p_classe_final,
                            'sugestao_original', v_sug,
                            'discordou', v_sug is not null and v_sug <> p_classe_final);
end;
$$;

comment on function fn_registrar_classe_override(uuid, text, text, text) is
  'A decisão humana sobre a classe contábil (Arquitetura do Sistema/2 Especificação/05, "registro de override humano"). Append-only: '
  'reclassificar é linha nova. Recusa RETORNADA e não exceção, senão o registro da própria '
  'tentativa seria desfeito. Autor é obrigatório: sem ele o sinal de calibração não tem de quem '
  'discordar.';

grant execute on function fn_registrar_classe_override(uuid, text, text, text) to authenticated;

-- -----------------------------------------------------------------------------
-- fn_classe_contabil_concordancia — O SINAL DE CALIBRAÇÃO, que é o motivo de esta
-- migration valer a pena mesmo em sombra.
--
-- O `Arquitetura do Sistema/2 Especificação/05` diz: *"o override vira sinal de calibração — onde humanos discordam
-- sistematicamente da máquina, ajusta-se regra/threshold (ou não se sobe o dial
-- daquele estágio)"*. Esta função é aquela frase em número.
--
-- E ela é da mesma família do achado da `0126` sobre a Classe A: o rótulo não vem
-- de rotulagem dedicada, vem do trabalho que o analista já faz. Cada override é um
-- ponto de concordância medida que o uso do produto gera sozinho.
--
-- O DENOMINADOR SÃO AS LINHAS COM OS DOIS LADOS. Linha que o humano nunca olhou
-- não conta nem a favor nem contra — é contada à parte, porque "a máquina acertou"
-- e "ninguém conferiu" são estados diferentes, e confundi-los é como o
-- `medir-auto-aceite.mts` já avisa que a cobertura mente.
-- -----------------------------------------------------------------------------
create or replace function fn_classe_contabil_concordancia(p_caso_id uuid default null)
returns jsonb
language sql
stable
as $$
  with par as (
    select s.classe_codigo as sugerida, o.classe_final as humana, s.rubrica_id
    from campo_classe_sugerida s
    join lateral (
      select o.classe_final from campo_classe_override o
      where o.campo_extraido_id = s.campo_extraido_id
      order by o.criado_em desc, o.id desc limit 1
    ) o on true
    join campo_extraido ce on ce.id = s.campo_extraido_id
    join documento_versao dv on dv.id = ce.documento_versao_id
    join documento d on d.id = dv.documento_id
    where (p_caso_id is null or d.caso_id = p_caso_id)
      and s.criado_em = (select max(s2.criado_em) from campo_classe_sugerida s2
                          where s2.campo_extraido_id = s.campo_extraido_id)
  ),
  sem_veredito as (
    select count(*) as n
    from campo_classe_sugerida s
    join campo_extraido ce on ce.id = s.campo_extraido_id
    join documento_versao dv on dv.id = ce.documento_versao_id
    join documento d on d.id = dv.documento_id
    where (p_caso_id is null or d.caso_id = p_caso_id)
      and not exists (select 1 from campo_classe_override o
                       where o.campo_extraido_id = s.campo_extraido_id)
  )
  select jsonb_build_object(
    'com_veredito_humano', (select count(*) from par),
    'concordaram', (select count(*) from par where sugerida = humana),
    'concordancia', case when (select count(*) from par) = 0 then null
                        else round((select count(*) from par where sugerida = humana)::numeric
                                   / (select count(*) from par), 4) end,
    'sem_veredito_humano', (select n from sem_veredito),
    'rubricas_que_mais_erram', (
      select coalesce(jsonb_agg(x order by x->>'erros' desc), '[]'::jsonb) from (
        select jsonb_build_object(
                 'padrao', rc.padrao, 'sugeria', rc.classe_codigo,
                 'erros', count(*),
                 'humano_disse', jsonb_agg(distinct par.humana)) as x
        from par join rubrica_classe rc on rc.id = par.rubrica_id
        where par.sugerida <> par.humana
        group by rc.padrao, rc.classe_codigo
        order by count(*) desc limit 10
      ) t),
    'como_ler', 'O denominador são as linhas com sugestao E override. Linha que ninguem olhou fica '
                'FORA, contada a parte: "a maquina acertou" e "ninguem conferiu" sao estados '
                'diferentes. E este numero NAO autoriza subir o dial por si: o teto de '
                'classificacao_contabil e N1 para sempre (Arquitetura do Sistema/1 Visão e Doutrina/01).'
  );
$$;

comment on function fn_classe_contabil_concordancia(uuid) is
  'A concordância humano-máquina na classe contábil — o "sinal de calibração" que o Arquitetura do Sistema/2 Especificação/05 pede, em '
  'número, mais as rubricas que mais erram. Da mesma família do achado da 0126 sobre a Classe A: o '
  'rótulo vem do trabalho que o analista já faz, sem rotulagem dedicada. Denominador = linhas com '
  'os DOIS lados; quem ninguém olhou fica fora e é contado à parte.';

grant execute on function fn_classe_contabil_concordancia(uuid) to authenticated;

-- -----------------------------------------------------------------------------
-- E ELA PASSA A RODAR: fn_registrar_campos_extraidos — corpo da 0111 com UMA
-- linha acrescentada no fim. Ver o comentário no lugar exato.
-- -----------------------------------------------------------------------------
create or replace function fn_registrar_campos_extraidos(
  p_documento_versao_id uuid,
  p_campos jsonb,
  p_nivel nivel_autonomia default 'N0',
  p_falha_motivo text default null,
  p_tem_dado_financeiro boolean default null
)
returns int
language plpgsql
as $$
declare
  v_count            int := 0;
  v_item             jsonb;
  v_valor             numeric;
  v_confianca          numeric;
  v_status_aceite      text;
  v_aceito_por         text;
  v_aceito_em          timestamptz;
  v_n_auto_aceitos     int := 0;
  v_documento_id       uuid;
  v_caso_id            uuid;
  v_nome_original      text;
  v_pendencia_id       uuid;
  v_guarda_disparou    boolean := false;
  v_nivel_dial         nivel_autonomia;
  v_limiar             numeric;
  v_auto_permitido     boolean;
  v_g                  jsonb;
begin
  select ea.nivel_atual, ea.limiar_auto_clear into v_nivel_dial, v_limiar
  from estagio_autonomia ea where ea.estagio = 'extracao_linhas_financeiras';
  v_auto_permitido := v_nivel_dial in ('N2', 'N3') and v_limiar is not null;

  if p_campos is not null and jsonb_typeof(p_campos) = 'array' then
    for v_item in select * from jsonb_array_elements(p_campos)
    loop
      v_valor := case when (v_item->>'valor_num') ~ '^-?\d+(\.\d+)?$' then (v_item->>'valor_num')::numeric else null end;
      v_confianca := case when (v_item->>'confianca') ~ '^-?\d+(\.\d+)?$' then (v_item->>'confianca')::numeric else null end;

      v_status_aceite := 'pendente';
      v_aceito_por := null;
      v_aceito_em := null;
      if v_auto_permitido and v_confianca is not null and v_confianca >= v_limiar then
        v_n_auto_aceitos := v_n_auto_aceitos + 1;
      end if;

      insert into campo_extraido
        (documento_versao_id, chave, valor_texto, valor_num, unidade, moeda, confianca,
         origem_pagina, origem_linha, ordem, nivel_autonomia, secao, secao_canonica, entidade_coluna, periodo_coluna,
         status_aceite, aceito_por, aceito_em)
      values (
        p_documento_versao_id,
        coalesce(v_item->>'chave', '(sem rótulo)'),
        v_item->>'valor_texto',
        v_valor,
        v_item->>'unidade',
        v_item->>'moeda',
        v_confianca,
        case when (v_item->>'origem_pagina') ~ '^\d+$' then (v_item->>'origem_pagina')::int else null end,
        v_item->>'origem_linha',
        case when (v_item->>'ordem') ~ '^\d+$' then (v_item->>'ordem')::int else null end,
        p_nivel,
        v_item->>'secao',
        v_item->>'secao_canonica',
        v_item->>'entidade_coluna',
        v_item->>'periodo_coluna',
        v_status_aceite,
        v_aceito_por,
        v_aceito_em
      );
      v_count := v_count + 1;
    end loop;
  end if;

  insert into evento_auditoria (ator, acao, entidade_ref, depois)
    values ('sistema:n8n', 'extracao_sombra', 'documento_versao:'||p_documento_versao_id,
            jsonb_build_object('campos', v_count, 'nivel', p_nivel, 'falha_motivo', p_falha_motivo,
                               'tem_dado_financeiro', p_tem_dado_financeiro, 'auto_aceitos', v_n_auto_aceitos));

  select d.id, d.caso_id, dv.nome_original into v_documento_id, v_caso_id, v_nome_original
  from documento_versao dv join documento d on d.id = dv.documento_id
  where dv.id = p_documento_versao_id;

  if v_documento_id is null then
    insert into evento_auditoria (ator, acao, entidade_ref, depois)
      values ('sistema:n8n', 'extracao_orfa', 'documento_versao:'||coalesce(p_documento_versao_id::text,'null'),
              jsonb_build_object('campos_descartados', v_count, 'falha_motivo', p_falha_motivo,
                                 'porque', 'documento_versao inexistente: campos e motivo nao tinham onde ser gravados'));
    raise warning 'fn_registrar_campos_extraidos: documento_versao % inexistente; % campo(s) e o motivo "%" foram descartados',
      p_documento_versao_id, v_count, coalesce(p_falha_motivo, '(sem motivo)');
    return v_count;
  end if;

  v_g := fn_avaliar_guardas_extracao(p_documento_versao_id);

  if v_count > 0 then
    -- ----- Sinal 1 (0013/0022/0034): mesmo valor material repetido em contas ---
    select id into v_pendencia_id from pendencia
      where caso_id = v_caso_id and motivo = 'extracao:padrao_suspeito:' || v_documento_id and estado <> 'resolvida'
      limit 1;
    if (v_g->>'padrao_suspeito')::boolean then
      v_guarda_disparou := true;
      if v_pendencia_id is null then
        insert into pendencia (caso_id, origem_estagio, tipo, severidade, sobrepujavel, descricao, documento_id, motivo)
          values (v_caso_id, 'extracao', 'extracao_padrao_suspeito', 'importante', true,
            format('%s contas diferentes, na MESMA coluna, vieram com o MESMO valor material (%s) — padrão '
                   'típico de fabricação/alucinação, não de dado real. Conferir contra o arquivo original. '
                   'Contas: %s',
                   v_g->>'n_contas_repetindo', round((v_g->>'valor_repetido')::numeric, 2),
                   array_to_string(array(select jsonb_array_elements_text(v_g->'rotulos_repetindo')), '; ')),
            v_documento_id, 'extracao:padrao_suspeito:' || v_documento_id);
      end if;
    elsif v_pendencia_id is not null then
      update pendencia set estado = 'resolvida', resolvida_em = now(), resolvida_por = 'sistema:extracao'
        where id = v_pendencia_id;
    end if;

    -- ----- Sinal 2 (0013): parcela relevante das linhas com confiança baixa ----
    select id into v_pendencia_id from pendencia
      where caso_id = v_caso_id and motivo = 'extracao:baixa_confianca:' || v_documento_id and estado <> 'resolvida'
      limit 1;
    if (v_g->>'baixa_confianca')::boolean then
      v_guarda_disparou := true;
      if v_pendencia_id is null then
        insert into pendencia (caso_id, origem_estagio, tipo, severidade, sobrepujavel, descricao, documento_id, motivo)
          values (v_caso_id, 'extracao', 'extracao_baixa_confianca', 'importante', true,
            format('%s de %s linhas extraídas vieram com confiança abaixo de 70%%. Revisar antes de aceitar.',
                   v_g->>'n_baixa_confianca', v_count),
            v_documento_id, 'extracao:baixa_confianca:' || v_documento_id);
      end if;
    elsif v_pendencia_id is not null then
      update pendencia set estado = 'resolvida', resolvida_em = now(), resolvida_por = 'sistema:extracao'
        where id = v_pendencia_id;
    end if;
  end if;

  -- ----- Sinal 3 (0016/0029, unidade corrigida por 0111) ---------------------
  -- "veio vazia" só é sinal de FALHA quando ninguém disse o contrário. Um
  -- chamador antigo (workflow não reimportado) manda `p_tem_dado_financeiro`
  -- null, e o comportamento é IDÊNTICO ao de antes desta migration
  -- (coalesce(null, true) = true). Só o diagnóstico da própria chamada, com
  -- `false` explícito, prova que zero linhas era o resultado certo.
  select id into v_pendencia_id from pendencia
    where caso_id = v_caso_id and motivo = 'extracao:falhou:' || v_documento_id and estado <> 'resolvida'
    limit 1;
  if p_falha_motivo is not null or (v_count = 0 and coalesce(p_tem_dado_financeiro, true)) then
    v_guarda_disparou := true;
    if v_pendencia_id is null then
      insert into pendencia (caso_id, origem_estagio, tipo, severidade, sobrepujavel, descricao, documento_id, motivo)
        values (v_caso_id, 'extracao', 'extracao_falhou', 'importante', true,
          format('Extração de "%s" falhou ou veio incompleta (%s linhas gravadas). Motivo: %s',
                 coalesce(v_nome_original, '?'), v_count,
                 coalesce(p_falha_motivo,
                          'a chamada respondeu sem erro, mas não trouxe NENHUMA linha. '
                          'Causa mais comum: formato que o pipeline ainda não converte em texto '
                          '(.xlsx/.docx) — nesses casos a IA recebe um aviso em vez do arquivo.')),
          v_documento_id, 'extracao:falhou:' || v_documento_id);
    end if;
  elsif v_pendencia_id is not null then
    update pendencia set estado = 'resolvida', resolvida_em = now(), resolvida_por = 'sistema:extracao'
      where id = v_pendencia_id;
  end if;

  -- ----- Auto-aceite (0029): DEPOIS das guardas, nunca antes -----------------
  if v_n_auto_aceitos > 0 and not v_guarda_disparou then
    update campo_extraido
      set status_aceite = 'aceito',
          aceito_por = format('sistema:auto_aceite (dial %s, limiar %s, sem guarda disparada)',
                              v_nivel_dial, v_limiar),
          aceito_em = now()
      where documento_versao_id = p_documento_versao_id
        and confianca >= v_limiar
        and status_aceite = 'pendente';

    insert into decisao (caso_id, tipo, autor, motivo, payload)
      values (v_caso_id, 'aprovacao', 'sistema:auto_aceite',
        format('%s linha(s) auto-aceitas na extração de "%s" — dial %s, limiar %s, nenhuma guarda disparou.',
               v_n_auto_aceitos, coalesce(v_nome_original, '?'), v_nivel_dial, v_limiar),
        jsonb_build_object('documento_id', v_documento_id, 'documento_versao_id', p_documento_versao_id,
                           'n_auto_aceitos', v_n_auto_aceitos));
  elsif v_n_auto_aceitos > 0 then
    insert into evento_auditoria (ator, acao, entidade_ref, depois)
      values ('sistema:auto_aceite', 'auto_aceite_suprimido', 'documento_versao:'||p_documento_versao_id,
              jsonb_build_object('n_elegiveis', v_n_auto_aceitos,
                                 'porque', 'guarda de extracao disparou; linhas seguem pendentes de revisao humana'));
  end if;

  perform fn_recomputar_completude(v_caso_id);

  -- 0128: A CLASSIFICAÇÃO CONTÁBIL RODA AQUI, e o lugar não é arbitrário.
  --
  -- Este é o único ponto do pipeline que roda DEPOIS da extração — é o mesmo
  -- motivo pelo qual a 0036 pôs a recomputação de completude nesta linha, e o
  -- comentário dela explica: `Registrar Documento` liga em paralelo para a
  -- completude e para a extração, então nada que dependa das linhas extraídas pode
  -- morar antes daqui.
  --
  -- Pendurar aqui também é o que evita REIMPORTAR o workflow: um nó novo no canvas
  -- exigiria isso do dono, e o n8n executa o JSON importado (merge não reimporta).
  --
  -- E é seguro por construção: em N0 a função só escreve em campo_classe_sugerida.
  -- Não abre pendência, não toca em campo_extraido, não entra em caminho de export.
  -- O pior caso dela é não fazer nada — se o dial não tiver a linha do estágio, ela
  -- devolve zero e segue.
  perform fn_classificar_contabil(p_documento_versao_id);

  return v_count;
end;
$$;
grant execute on function fn_registrar_campos_extraidos(uuid, jsonb, nivel_autonomia, text, boolean) to authenticated;
