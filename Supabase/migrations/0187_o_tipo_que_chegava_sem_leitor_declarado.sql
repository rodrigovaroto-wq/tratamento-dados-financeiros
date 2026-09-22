-- =============================================================================
-- 0187 — O TIPO QUE CHEGAVA SEM LEITOR DECLARADO
--
-- O DEFEITO, medido contra produção (somente leitura, banco na 0181,
-- 21-22/09/2026). O portão D6 do roadmap
-- (`Arquitetura do Sistema/3 Estado e Execução/ARQUITETURA_ALVO_E_ROADMAP.md`,
-- DATA GATE) pede: "todo tipo com documento ingerido tem ≥1 exigência VIVA ou
-- está declarado SEM_CONSUMIDOR com motivo". Exigência viva =
-- `taxonomia_linha_exigida` ativa com `origem = 'codigo'` (a que espelha uma
-- reconciliação que de fato lê o número). Em produção, 24 tipos têm documento
-- e só SEIS têm exigência viva (BALANCO 517 docs, DRE 298, COMBINADO 133,
-- FATURAMENTO_24M 82, MAPA_DIVIDA 65, FLUXO_CAIXA 58). Os outros DEZOITO —
-- BALANCETE 179, MUTUOS 57, ESTOQUE 43, CONTRATO_SOCIAL 40, NOTAS_EXPL 40,
-- AGING_AR 38, SITUACAO_FISCAL 37, EXTRATO_BANCARIO 36, AGING_AP 34,
-- CONTINGENCIAS 34, DF_AUDITADA 34, DVA 34, RAZAO 34, DMPL 25, CERTIDOES 24,
-- FAT_INTRAGRUPO 23, ORGANOGRAMA 19, HEADCOUNT 5 — chegam, são contados pelo
-- checklist, e NADA no banco diz se alguém confere o que eles dizem. "Não tem
-- exigência" e "ninguém lê" e "alguém lê, só não por exigência" tinham a mesma
-- aparência: nenhuma linha em tabela nenhuma (regra 7 do CLAUDE.md).
--
-- A TENTATIVA ANTERIOR, e por que ela não serve. A 0185 tentou fechar D6 com
-- exigência LEXICAL para nove desses tipos e foi REPROVADA na medição: 17 de
-- 17 pendências que abriria eram falsas. Em relatório itemizado o rótulo é o
-- ITEM (fornecedor, banco, processo), não o conceito
-- (`.claude/memory/conceito-nao-esta-no-rotulo-de-relatorio-itemizado.md`). A
-- 0185 foi descartada sem ter sido aplicada em banco nenhum — o número fica
-- como lacuna (ver `Supabase/README.md`).
--
-- E O MESMO DEFEITO JÁ ESTAVA NO AR, desde a 0113. As três exigências
-- `origem='proposta'` da 0113 (MUTUOS/saldo_de_mutuo ['mutuo'] excl ['total'];
-- FAT_INTRAGRUPO/faturamento_entre_partes ['faturamento'] excl ['total'];
-- CONTRATO_SOCIAL/capital_social ['capital','social']) são a mesma premissa.
-- Medido em produção: as 5 pendências `linha_exigida_ausente` ABERTAS desses
-- tipos são TODAS FALSAS, conferidas uma a uma:
--   • MUTUOS ×1 — chaves "CANASTRA PARTICIPAÇÕES S.A. - CANASTRA INDÚSTRIA…",
--     seção "RELAÇÃO DE MÚTUOS ENTRE PARTES RELACIONADAS": cada linha É um
--     mútuo, e a palavra só está na seção;
--   • FAT_INTRAGRUPO ×3 — chaves = nomes de empresa ou "Julho 2025", seção às
--     vezes NULA: não há onde a palavra "faturamento" morar;
--   • CONTRATO_SOCIAL ×1 (entidade GLOBAL STORE) — chave "Total — Valor R$",
--     seção "CLÁUSULA V - Capital social": o conceito está na CLÁUSULA.
-- A `fixture_book_canastra.sql` reproduz os dois primeiros (documentos
-- 44444444-3333-0000-0000-000000000014 e …015) — é contra ela que o teste
-- prova. O CONTRATO_SOCIAL da fixture não tem linha nenhuma (0111), então o
-- arranjo de produção do contrato é montado no teste com os rótulos LITERAIS
-- medidos acima, e o comentário do teste diz isso (regra 4).
--
-- O QUE ESTA MIGRATION FAZ
--
--   (a) `taxonomia_tipo_cobertura` — uma DECLARAÇÃO por tipo ativo sem
--       exigência viva: ou `consumidor_nomeado` (a função SQL que LÊ e CONFERE
--       o número daquele tipo — conferida lendo o corpo VIGENTE, ver o seed) ou
--       `sem_consumidor`, com `motivo` e `efeito` obrigatórios. O `efeito` é a
--       regra 1: dizer o que deixa de ser conferido, não só que não é.
--       DESEMPATE NÃO É CONSUMIDOR: `fn_conflitos_do_caso` (0151) compara
--       linhas de dois documentos quando seção canônica, rótulo e exercício
--       COINCIDEM, e escolhe um vencedor por autoridade; ela lê DVA, DMPL,
--       NOTAS_EXPL e RAZAO de passagem, mas não confere o que cada um deles
--       tem de dizer — um PL da DMPL que não bate com o do BP só aparece se o
--       rótulo for literalmente o mesmo. `fn_linhas_do_realizado` (0150) soma
--       linhas para premissa: LÊ, não confere. Nenhuma das duas é declarada
--       consumidora de tipo nenhum.
--   (b) `fn_cobertura_de_tipos()` — o portão D6 como consulta. Uma linha por
--       tipo ATIVO (todos, não só os com documento: assim o portão roda no
--       banco de teste sem depender de fixture). D6 estrito = nenhuma linha em
--       `SEM_COBERTURA` nem em `DECLARACAO_QUEBRADA`. A declaração envelhece de
--       dois jeitos, e os dois viram `DECLARACAO_QUEBRADA`: o consumidor
--       nomeado some de `pg_proc`, ou o tipo ganha exigência viva e a
--       declaração fica duplicando o registro.
--   (c) Desativa (`ativo = false`, nunca delete — a FK de
--       `pergunta_catalogo` e a trilha precisam da linha) as exigências
--       proposta de MUTUOS e FAT_INTRAGRUPO. Para CONTRATO_SOCIAL — que NÃO é
--       relatório itemizado: capital social é conceito de CLÁUSULA — acrescenta
--       um localizador em cascata `contra = 'secao'` com ['capital','social'].
--       A `secao` NÃO É ESTÁVEL entre versões do extrator (o mesmo book
--       canastra tem `secao` nula nas ingestões antigas e preenchida nas novas —
--       `.claude/conhecimento/fichas/f2-localizador-chave-pendencia-falsa.md`).
--       Por isso o localizador só pode FAZER PASSAR, nunca abrir mais: é uma
--       tentativa a mais numa cascata em que basta uma casar. Documento cuja
--       versão vigente veio sem seção continua exatamente onde estava.
--   (d) Resolve de forma DIRIGIDA as pendências `linha_exigida_ausente`
--       ABERTAS desses três tipos que o Portão 1 não abriria mais hoje
--       (exigência inativa, ou exigência ativa e agora satisfeita para aquela
--       entidade — o critério é o próprio `fn_exigencias_do_caso`). NÃO chama
--       `fn_recomputar_completude` em lote: a 0179 mediu 365 pendências onde
--       se previam 13 (`.claude/memory/aplicar-migration-em-producao-pela-api.md`)
--       — recompute mexe em TODO o passo 2 de cada caso, não só nestes três
--       tipos. `aceita_com_ressalva` não é tocada: é decisão humana.
--   (e) `fn_sugerir_perguntas` REEMITIDA INTEIRA (corpo da 0122), com UMA
--       mudança: o marcador {saldo_mutuos} da pergunta 5.1 soma as linhas que
--       casam os localizadores de MUTUOS/saldo_de_mutuo, e filtrava
--       `e.ativo`. Desativar a exigência sem isto faria a pergunta ao CLIENTE
--       dizer "(não localizado)" sobre um saldo que está no documento — a
--       desativação desliga a COBRANÇA, não o léxico. Medido (22/09/2026,
--       com o `and e.ativo` de volta e o assert de `perguntas.test.sql` feito
--       não-fatal para contar): 3 asserts dele reprovam — a soma "R$ 150 mil",
--       as escalas mistas e o "R$ 16.060 mil", os três com o texto "(não
--       localizado)" — e mais 1 de `instalacao.test.sql` (o requisito de corpo
--       saldo_mutuos_nao_depende_da_cobranca some).
--   (f) O catálogo da sonda.
--
-- O QUE ESTA MIGRATION NÃO FAZ
--
--   • Não cria exigência nova para tipo nenhum, e não promove nenhum dos nove
--     da 0185 a obrigatório — decisão do dono em 21/09/2026: ficam
--     COMPLEMENTARES.
--   • Não constrói o consumidor que falta. `sem_consumidor` é o INVENTÁRIO do
--     que não se confere, com o efeito escrito; fechar cada um é fatia própria
--     (o candidato óbvio é estrutural: Σ aging = Fornecedores/Clientes do BP).
--   • Não toca `fn_recomputar_completude`. Consequência que quem aplica
--     precisa saber: a pendência MUTUOS em `aceita_com_ressalva` que existe em
--     produção NÃO é tocada por esta migration — mas o passo 2b resolve
--     `linha_exigida_ausente` em qualquer estado <> 'resolvida' cujo motivo
--     não é mais cobrado, então o PRÓXIMO recompute daquele caso a resolve
--     como `sistema:extracao`. Isso é o comportamento de hoje para qualquer
--     exigência desativada, não algo que a 0187 introduz.
--
-- ALCANCE — medido no banco de TESTE, não em produção. Aqui (`run.sh`, sem
-- fixture carregada quando a migration roda) `pendencia` está vazia e o passo
-- (d) resolve ZERO; o comportamento é provado em
-- `Supabase/test/cobertura_de_tipos.test.sql`, contra a fixture canastra. Em
-- produção a medição de 22/09/2026 conta 5 abertas (1 MUTUOS, 3
-- FAT_INTRAGRUPO, 1 CONTRATO_SOCIAL) + 1 MUTUOS em `aceita_com_ressalva`. As
-- quatro primeiras devem resolver; a do CONTRATO_SOCIAL só resolve se a versão
-- VIGENTE daquele documento tiver a seção preenchida. A consulta somente
-- leitura que confere isso ANTES está no `Supabase/README.md`.
-- =============================================================================

begin;

-- -----------------------------------------------------------------------------
-- (a) A DECLARAÇÃO
-- -----------------------------------------------------------------------------
create table if not exists taxonomia_tipo_cobertura (
  tipo_taxonomia text primary key references taxonomia_tipo_documento(codigo),
  estado         text not null check (estado in ('consumidor_nomeado', 'sem_consumidor')),
  consumidor     text,
  motivo         text not null check (length(btrim(motivo)) > 0),
  efeito         text not null check (length(btrim(efeito)) > 0),
  declarado_em   date not null default current_date,
  -- consumidor nomeado SEM nome é declaração que não se confere; sem_consumidor
  -- COM nome é contradição. As duas formas são recusadas pelo banco.
  check ((estado = 'consumidor_nomeado') = (consumidor is not null))
);

comment on table taxonomia_tipo_cobertura is
  '0187 (portão D6): para cada tipo ATIVO sem exigência viva (taxonomia_linha_exigida ativa com '
  'origem=codigo), QUEM confere o número dele — ou a declaração de que ninguém confere, com o '
  'motivo e o EFEITO (o que passa sem aviso). Desempate (fn_conflitos_do_caso, 0151) e soma para '
  'premissa (fn_linhas_do_realizado, 0150) NÃO contam como consumidor: leem, não conferem. '
  'Conferida por fn_cobertura_de_tipos().';
comment on column taxonomia_tipo_cobertura.consumidor is
  'Nome (proname, schema public) da função SQL que LÊ documentos do tipo e CONFERE o número. '
  'Obrigatório quando estado=consumidor_nomeado, NULL caso contrário. Se a função sumir, '
  'fn_cobertura_de_tipos devolve DECLARACAO_QUEBRADA.';
comment on column taxonomia_tipo_cobertura.efeito is
  'O que deixa de ser conferido por causa desta declaração (regra 1 do CLAUDE.md): "não tem '
  'consumidor" sem o efeito é ausência apresentada como dado.';

alter table taxonomia_tipo_cobertura enable row level security;
drop policy if exists taxonomia_tipo_cobertura_read on taxonomia_tipo_cobertura;
create policy taxonomia_tipo_cobertura_read on taxonomia_tipo_cobertura
  for select to authenticated using (true);
-- Escrita reservada (migration/service_role), como taxonomia_linha_exigida:
-- declarar quem confere um tipo é ação de banco, não de tela.

-- O SEED. Cada consumidor abaixo foi confirmado LENDO o corpo vigente
-- (pg_get_functiondef no banco montado do zero, 22/09/2026):
--
--   MUTUOS      → fn_reconciliar_mutuos (0123): lê a planilha MUTUOS
--                 (fn_documento_por_tipo(..., 'MUTUOS')) e soma o saldo de
--                 mútuo dos balanços do caso; grava mutuos_planilha_vs_balanco.
--   BALANCETE   → fn_reconciliar_arvore (0133): fn_reconciliar_por_documento a
--                 chama para BALANCO/BALANCETE/COMBINADO; confere Σ filhos =
--                 total de cada seção DO PRÓPRIO balancete (secao_fecha). O
--                 balancete é também fonte de balanço em fn_reconciliar_mutuos,
--                 fn_reconciliar_intragrupo e fn_documento_balanco — mas só
--                 quando a entidade não tem BALANCO (ordem por array_position).
--   DF_AUDITADA → fn_reconciliar_intragrupo (0124): DF_AUDITADA está entre as
--                 fontes de balanço por entidade (BALANCO, DF_AUDITADA,
--                 BALANCETE); fn_reconciliar_mutuos (0123) idem. SÓ quando a
--                 entidade não tem BALANCO — o efeito diz isso.
--
-- Todos os outros foram procurados como literal em todo corpo de função
-- vigente (`'TIPO'`): nenhuma função os lê, ou só o desempate/realizado os lê.
insert into taxonomia_tipo_cobertura (tipo_taxonomia, estado, consumidor, motivo, efeito, declarado_em)
values
  -- ---- os três com consumidor que confere o número --------------------------
  ('MUTUOS', 'consumidor_nomeado', 'fn_reconciliar_mutuos',
   'fn_reconciliar_mutuos (0123) lê a planilha de mútuos e confere o saldo contra a soma das contas '
   'de mútuo dos balanços do caso (mutuos_planilha_vs_balanco). A exigência lexical proposta da '
   '0113 foi desativada na 0187: relatório itemizado, o rótulo é o par de empresas — 1 de 1 '
   'pendência aberta em produção era falsa (22/09/2026).',
   'A conferência é por CASO, não por par de empresas: um mútuo lançado na empresa errada do grupo '
   'passa se o total bater. Mútuo com sócio fica fora (não tem espelho no mandato). Se nenhum '
   'balanço traz conta de mútuo com lado reconhecível, a checagem sai documento_ausente e NÃO abre '
   'pendência (contrato da 0186).',
   '2026-09-22'),
  ('BALANCETE', 'consumidor_nomeado', 'fn_reconciliar_arvore',
   'fn_reconciliar_por_documento chama fn_reconciliar_arvore (0133) para todo BALANCETE: Σ filhos = '
   'total de cada seção do próprio documento (secao_fecha). Também é fonte de balanço em '
   'fn_reconciliar_mutuos, fn_reconciliar_intragrupo e fn_documento_balanco quando a entidade não '
   'tem BALANCO.',
   'Balancete × balanço CONTA A CONTA não é conferido: um balancete cujo saldo de uma conta difere '
   'do BP da mesma entidade só aparece se o rótulo coincidir literalmente (desempate da 0151, que '
   'não é conferência). Com BALANCO presente, ativo = passivo + PL do balancete não é checado.',
   '2026-09-22'),
  ('DF_AUDITADA', 'consumidor_nomeado', 'fn_reconciliar_intragrupo',
   'fn_reconciliar_intragrupo (0124) e fn_reconciliar_mutuos (0123) usam a DF auditada como fonte '
   'de balanço por entidade (ordem BALANCO, DF_AUDITADA, BALANCETE) e conferem os saldos '
   'intragrupo/mútuo dela. Em produção 34 documentos, só 6 com linha (22/09/2026).',
   'SÓ é lida quando a entidade NÃO tem BALANCO — no caso típico ninguém lê a DF. Ativo = passivo + '
   'PL da DF não é conferido (fn_documento_balanco não inclui DF_AUDITADA), e DF divergente do '
   'balanço gerencial só aparece por rótulo coincidente (desempate 0151).',
   '2026-09-22'),

  -- ---- os nove da 0185: relatório itemizado, ficam COMPLEMENTARES -----------
  ('AGING_AP', 'sem_consumidor', null,
   'Relatório itemizado: o rótulo é o item (fornecedor), não o conceito. Exigência lexical medida '
   'falsa em 17/17 (0185, reprovada, 21/09/2026). Nenhuma função SQL lê AGING_AP.',
   'Aging de contas a pagar cujo total não bate com Fornecedores do BP passa sem aviso; aging que '
   'chega só com a linha de resto ("Demais fornecedores") também.',
   '2026-09-22'),
  ('AGING_AR', 'sem_consumidor', null,
   'Relatório itemizado: o rótulo é o item (cliente/sacado), não o conceito. Exigência lexical '
   'medida falsa em 17/17 (0185, reprovada, 21/09/2026). Nenhuma função SQL lê AGING_AR.',
   'Aging de contas a receber cujo total não bate com Clientes/Contas a receber do BP passa sem '
   'aviso, e a concentração/inadimplência por faixa não é lida por ninguém.',
   '2026-09-22'),
  ('EXTRATO_BANCARIO', 'sem_consumidor', null,
   'Relatório itemizado (conta × mês; o rótulo é o banco/agência). Exigência lexical medida falsa '
   'em 17/17 (0185, reprovada, 21/09/2026). Nenhuma função SQL lê EXTRATO_BANCARIO.',
   'Saldo de extrato que não bate com Caixa e equivalentes do BP passa sem aviso.',
   '2026-09-22'),
  ('GARANTIAS', 'sem_consumidor', null,
   'Relatório itemizado (bem/beneficiário). Exigência lexical da mesma forma medida falsa em 17/17 '
   '(0185, reprovada, 21/09/2026). Nenhuma função SQL lê GARANTIAS; zero documentos em produção.',
   'Bem dado em garantia não é confrontado com o MAPA_DIVIDA: dívida garantida sem garantia '
   'declarada (ou o contrário) passa sem aviso.',
   '2026-09-22'),
  ('AVAIS_FIANCAS', 'sem_consumidor', null,
   'Relatório itemizado (beneficiário/obrigação). Exigência lexical da mesma forma medida falsa em '
   '17/17 (0185, reprovada, 21/09/2026). Nenhuma função SQL lê AVAIS_FIANCAS; zero documentos em '
   'produção.',
   'Aval ou fiança prestado pelo grupo não entra em conferência nenhuma: a dívida contingente fora '
   'do balanço não gera aviso.',
   '2026-09-22'),
  ('CONTINGENCIAS', 'sem_consumidor', null,
   'Relatório itemizado (o rótulo é o processo; a seção é Trabalhista/Cível/Tributário — a palavra '
   '"contingência" não aparece no documento). 9 dos 17 falsos da 0185 (21/09/2026). Nenhuma '
   'função SQL lê CONTINGENCIAS.',
   'Contingência provável que não bate com Provisões do BP passa sem aviso.',
   '2026-09-22'),
  ('DEBITOS_TRIB', 'sem_consumidor', null,
   'Relatório itemizado (por tributo/competência). Exigência lexical da mesma forma medida falsa em '
   '17/17 (0185, reprovada, 21/09/2026). Nenhuma função SQL lê DEBITOS_TRIB; zero documentos em '
   'produção.',
   'Débito tributário/parcelamento que não bate com Tributos a recolher/parcelamentos do BP passa '
   'sem aviso.',
   '2026-09-22'),
  ('ESTOQUE', 'sem_consumidor', null,
   'Relatório itemizado (o rótulo é o SKU — 484 linhas como "2500 - ASSALA PRIME" no mandato real). '
   'Exigência lexical medida falsa em 17/17 (0185, reprovada, 21/09/2026). Nenhuma função SQL lê '
   'ESTOQUE.',
   'Posição de estoque que não soma Estoques do BP passa sem aviso.',
   '2026-09-22'),
  ('HEADCOUNT', 'sem_consumidor', null,
   'Relatório itemizado (o rótulo é o centro de custo; a unidade é PESSOAS). Exigência lexical '
   'medida falsa em 17/17 (0185, reprovada, 21/09/2026). Nenhuma função SQL lê HEADCOUNT.',
   'Headcount não é confrontado com a despesa de pessoal da DRE: folha que cresce com quadro '
   'estável (ou o contrário) passa sem aviso.',
   '2026-09-22'),

  -- ---- os outros itemizados/relatórios sem leitor --------------------------
  ('FAT_INTRAGRUPO', 'sem_consumidor', null,
   'Relatório itemizado: o rótulo é o par de empresas ou o mês ("Julho 2025"), a seção às vezes '
   'nula. A exigência lexical proposta da 0113 foi desativada na 0187: 3 de 3 pendências abertas '
   'em produção eram falsas (22/09/2026). fn_reconciliar_intragrupo (0124) confere saldos '
   'intragrupo de BALANÇO, não lê este documento.',
   'Faturamento intragrupo não é confrontado com a eliminação do COMBINADO nem com o '
   'FATURAMENTO_24M: receita intragrupo não eliminada no combinado passa sem aviso.',
   '2026-09-22'),
  ('APLIC_FINANC', 'sem_consumidor', null,
   'Relatório itemizado (aplicação a aplicação; abertura analítica, 0150). Nenhuma função SQL lê '
   'APLIC_FINANC; zero documentos em produção.',
   'Posição de aplicações que não bate com Aplicações financeiras/Caixa e equivalentes do BP passa '
   'sem aviso.',
   '2026-09-22'),
  ('RAZAO', 'sem_consumidor', null,
   'Abertura analítica lançamento a lançamento (0150). Só o desempate (fn_conflitos_do_caso, 0151) '
   'o lê, e só quando seção canônica e rótulo coincidem com outro documento — desempate não '
   'confere. fn_linhas_do_realizado o exclui (abertura_analitica).',
   'Saldo final do razão que não bate com a conta do BP passa sem aviso, salvo rótulo idêntico.',
   '2026-09-22'),
  ('SITUACAO_FISCAL', 'sem_consumidor', null,
   'Relatório da RFB/PGFN itemizado por débito/pendência, em boa parte não numérico. Nenhuma '
   'função SQL lê SITUACAO_FISCAL.',
   'Débito ativo ou inscrito em dívida ativa que o relatório mostra não é confrontado com '
   'DEBITOS_TRIB nem com o BP: passivo fiscal fora do balanço passa sem aviso.',
   '2026-09-22'),
  ('SPED', 'sem_consumidor', null,
   'Arquivo digital (ECD/ECF) sem extração estruturada no pipeline hoje. Nenhuma função SQL lê '
   'SPED; zero documentos em produção.',
   'Nada do SPED é confrontado com as demonstrações entregues: balanço gerencial que diverge do '
   'escriturado passa sem aviso.',
   '2026-09-22'),

  -- ---- demonstrações que só o desempate/realizado leem ---------------------
  ('DVA', 'sem_consumidor', null,
   'Só fn_conflitos_do_caso (0151, desempate — compara quando seção canônica e rótulo coincidem '
   'com outro documento) e fn_linhas_do_realizado (0150, soma para premissa) a leem. Desempate e '
   'soma leem, não conferem.',
   'Receita e distribuição do valor adicionado que não batem com a DRE passam sem aviso, salvo '
   'rótulo idêntico ao da DRE.',
   '2026-09-22'),
  ('DMPL', 'sem_consumidor', null,
   'Só fn_conflitos_do_caso (0151, desempate) e fn_linhas_do_realizado (0150) a leem; nenhuma '
   'checagem confere a DMPL contra o PL do BP.',
   'PL final da DMPL que não bate com o Patrimônio líquido do BP passa sem aviso, salvo rótulo '
   'idêntico; movimentação do PL (dividendos, aumento de capital) não é lida por ninguém.',
   '2026-09-22'),
  ('NOTAS_EXPL', 'sem_consumidor', null,
   'Só fn_conflitos_do_caso (0151, desempate) e fn_linhas_do_realizado (0150) a leem. Medido na '
   'fixture canastra: NOTAS_EXPL 7.825 × BALANCO 7.822 no mesmo rótulo — o desempate COMPARA, '
   'mas só quando o rótulo coincide.',
   'Nota explicativa (abertura de dívida, imobilizado, partes relacionadas) que discorda do BP só '
   'aparece quando rótulo e seção canônica coincidem; o que a nota abre e o BP não mostra não é '
   'lido.',
   '2026-09-22'),

  -- ---- documentos não numéricos por natureza -------------------------------
  ('CERTIDOES', 'sem_consumidor', null,
   'Documento não numérico por natureza (certidão negativa/positiva): 24 documentos em produção, '
   '0 com linha (22/09/2026). A 0111 já trata a ausência de linha como acerto, não como falha.',
   'Certidão POSITIVA (débito existente) não vira alerta: nada lê o conteúdo; o checklist só conta '
   'que ela chegou.',
   '2026-09-22'),
  ('ORGANOGRAMA', 'sem_consumidor', null,
   'Documento não numérico por natureza: 19 documentos em produção, 0 com linha (22/09/2026).',
   'A participação societária desenhada no organograma não é confrontada com '
   'entidade.controladora_id (0181) nem com o perímetro do combinado (0180).',
   '2026-09-22'),
  ('CONTRATO_SOCIAL', 'sem_consumidor', null,
   'Documento de cláusulas; o único número é o capital social. A exigência proposta capital_social '
   '(0113) continua ATIVA e ganhou, na 0187, um localizador por seção — mas ela confere PRESENÇA, '
   'não o número. Nenhuma função SQL confere o valor.',
   'Capital social do contrato não é confrontado com o Capital social do BP; composição societária '
   'e cláusula de administração não são lidas por ninguém.',
   '2026-09-22'),
  ('DOCS_SOCIOS', 'sem_consumidor', null,
   'Documentos pessoais dos sócios (identidade, IR), não numéricos para o book e com sensibilidade '
   'LGPD. Nenhuma função SQL lê DOCS_SOCIOS; zero documentos em produção.',
   'Garantia pessoal ou patrimônio de sócio declarado não é cruzado com AVAIS_FIANCAS nem com a '
   'dívida.',
   '2026-09-22'),
  ('CONTRATO_DIVIDA', 'sem_consumidor', null,
   'Contrato (cláusulas de taxa, prazo, covenant, garantia) sem linha numérica padronizada. Nenhuma '
   'função SQL lê CONTRATO_DIVIDA; zero documentos em produção.',
   'Taxa, vencimento e covenants do contrato não são confrontados com o MAPA_DIVIDA: mapa que '
   'diverge do contrato passa sem aviso.',
   '2026-09-22'),
  ('CONTRATOS_COM', 'sem_consumidor', null,
   'Contratos comerciais, não numéricos em linha. Nenhuma função SQL lê CONTRATOS_COM; zero '
   'documentos em produção.',
   'Exclusividade, change of control e concentração de cliente em contrato não são lidas.',
   '2026-09-22'),
  ('CONTRATOS_IC', 'sem_consumidor', null,
   'Contratos intercompany, não numéricos em linha. Nenhuma função SQL lê CONTRATOS_IC; zero '
   'documentos em produção.',
   'Contrato intercompany não é confrontado com FAT_INTRAGRUPO nem com os mútuos: preço de '
   'transferência e obrigação entre empresas do grupo passam sem aviso.',
   '2026-09-22'),

  -- ---- projeções: não são realizado -----------------------------------------
  ('FLUXO_PROJETADO', 'sem_consumidor', null,
   'Projeção do cliente, não realizado — nada a conferir contra demonstração. Nenhuma função SQL '
   'lê FLUXO_PROJETADO; zero documentos em produção.',
   'A projeção do cliente não é comparada com o modelo do book: premissa do cliente mais otimista '
   'que a do modelo passa sem aviso.',
   '2026-09-22'),
  ('PLANO_NEGOCIOS', 'sem_consumidor', null,
   'Documento narrativo/projetivo. Nenhuma função SQL lê PLANO_NEGOCIOS; zero documentos em '
   'produção.',
   'Metas do plano de negócios não são confrontadas com o modelo nem com o realizado.',
   '2026-09-22'),
  ('PREMISSAS', 'sem_consumidor', null,
   'Premissas enviadas pelo cliente (documento, não premissa_catalogo). Nenhuma função SQL lê '
   'documentos PREMISSAS; zero documentos em produção.',
   'Premissa do cliente não é comparada com a premissa do modelo (premissa_catalogo, 0038): '
   'divergência entre as duas passa sem aviso.',
   '2026-09-22')
on conflict (tipo_taxonomia) do nothing;

-- -----------------------------------------------------------------------------
-- (b) O PORTÃO D6 COMO CONSULTA
-- -----------------------------------------------------------------------------
create or replace function fn_cobertura_de_tipos()
returns table (
  tipo_taxonomia    text,
  obrigatoriedade   text,
  exigencias_vivas  int,
  estado_declarado  text,
  consumidor        text,
  consumidor_existe boolean,
  veredito          text
)
language sql stable
as $$
  with vivas as (
    select e.tipo_taxonomia, count(*)::int as n
      from taxonomia_linha_exigida e
     where e.ativo and e.origem = 'codigo'
     group by e.tipo_taxonomia
  ),
  base as (
    select t.codigo, t.obrigatoriedade::text as obrigatoriedade,
           coalesce(v.n, 0) as n_vivas,
           c.tipo_taxonomia is not null as declarado,
           c.estado, c.consumidor,
           case when c.consumidor is null then null
                else exists (select 1 from pg_proc p
                               join pg_namespace ns on ns.oid = p.pronamespace
                              where ns.nspname = 'public' and p.proname = c.consumidor)
           end as consumidor_existe
      from taxonomia_tipo_documento t
      left join vivas v on v.tipo_taxonomia = t.codigo
      left join taxonomia_tipo_cobertura c on c.tipo_taxonomia = t.codigo
     where t.ativo
  )
  select b.codigo, b.obrigatoriedade, b.n_vivas, b.estado, b.consumidor, b.consumidor_existe,
         case
           -- Duplo registro: o tipo ganhou exigência viva e a declaração ficou.
           -- Ela envelhece calada (o consumidor pode sumir, o motivo mentir), e
           -- o portão quer UMA fonte por tipo.
           when b.n_vivas > 0 and b.declarado            then 'DECLARACAO_QUEBRADA'
           when b.n_vivas > 0                            then 'exigencia_viva'
           when not b.declarado                          then 'SEM_COBERTURA'
           when b.estado = 'consumidor_nomeado'
            and not b.consumidor_existe                  then 'DECLARACAO_QUEBRADA'
           when b.estado = 'consumidor_nomeado'          then 'consumidor_nomeado'
           else 'sem_consumidor_declarado'
         end
    from base b
   order by b.codigo;
$$;

comment on function fn_cobertura_de_tipos() is
  '0187 — portão D6. Uma linha por tipo ATIVO da taxonomia. D6 estrito = nenhuma linha com '
  'veredito SEM_COBERTURA (sem exigência viva e sem declaração) nem DECLARACAO_QUEBRADA '
  '(consumidor nomeado que não existe em pg_proc, ou declaração para tipo que já tem exigência '
  'viva). Não depende de documento: roda igual no banco de teste e em produção.';

grant execute on function public.fn_cobertura_de_tipos() to authenticated;

-- -----------------------------------------------------------------------------
-- (c) AS EXIGÊNCIAS LEXICAIS QUE ERAM FALSAS
-- -----------------------------------------------------------------------------
-- A LINHA FICA (ativo=false): pergunta_catalogo tem FK para (tipo, conceito), a
-- trilha das pendências antigas cita o motivo, e fn_sugerir_perguntas continua
-- lendo os localizadores de MUTUOS como léxico do {saldo_mutuos} (ver (e)).
update taxonomia_linha_exigida
   set ativo = false,
       descricao = descricao || ' | DESATIVADA na 0187 (22/09/2026): relatório itemizado, o '
                   'rótulo é o item — todas as pendências abertas deste conceito em produção '
                   'eram falsas. Quem confere o tipo está em taxonomia_tipo_cobertura.'
 where origem = 'proposta'
   and ativo
   and (tipo_taxonomia, conceito) in (('MUTUOS', 'saldo_de_mutuo'),
                                      ('FAT_INTRAGRUPO', 'faturamento_entre_partes'));

-- CONTRATO_SOCIAL: capital social é conceito de CLÁUSULA, e a cláusula é a
-- SEÇÃO ("CLÁUSULA V - Capital social", produção 22/09/2026). Tentativa a MAIS
-- na cascata — basta uma casar —, então este localizador só pode fazer
-- passar. `secao` não é estável entre versões do extrator: documento cuja
-- versão vigente veio sem seção fica exatamente como estava (não satisfeita,
-- se a chave também não diz), nunca pior.
insert into taxonomia_linha_localizador (exigencia_id, ordem, contra, termos_inclui, termos_exclui)
select e.id, 2, 'secao', array['capital','social']::text[], '{}'::text[]
  from taxonomia_linha_exigida e
 where e.tipo_taxonomia = 'CONTRATO_SOCIAL' and e.conceito = 'capital_social'
on conflict (exigencia_id, ordem) do nothing;

-- -----------------------------------------------------------------------------
-- (d) A RESOLUÇÃO DIRIGIDA
-- -----------------------------------------------------------------------------
-- Função, e não um bloco solto, porque o teste precisa exercitá-la contra o
-- arranjo real (a fixture canastra carrega DEPOIS das migrations — aqui a
-- tabela está vazia e o bloco abaixo resolve zero).
--
-- O critério é o do próprio Portão 1: a pendência resolve quando o motivo dela
-- NÃO está entre os que fn_exigencias_do_caso ainda devolveria como não
-- satisfeitos, com a MESMA fórmula de motivo do passo 2b de
-- fn_recomputar_completude (0119: tipo:conceito[:entidade canônica]). O que
-- difere do recompute é o alcance: só `estado = 'aberta'` (aceita_com_ressalva
-- é decisão humana) e só os tipos pedidos — nenhum outro passo da completude
-- roda.
create or replace function fn_resolver_linha_exigida_superada(p_tipos text[], p_ator text)
returns jsonb
language plpgsql
as $$
declare
  v_caso       uuid;
  v_vivos      text[];
  v_p          record;
  v_razao      text;
  v_resolvidas int := 0;
  v_ficaram    int := 0;
  v_ressalva   int;
begin
  if p_ator is null or p_ator not like 'sistema:%' then
    raise exception 'fn_resolver_linha_exigida_superada: p_ator precisa ser ''sistema:<quem>'' (recebeu %)', p_ator;
  end if;

  for v_caso in
    select distinct p.caso_id
      from pendencia p
     where p.tipo = 'linha_exigida_ausente'
       and p.estado = 'aberta'
       and split_part(p.motivo, ':', 3) = any (p_tipos)
  loop
    select coalesce(array_agg(
             'completude:linha_exigida:' || x.tipo_taxonomia || ':' || x.conceito
             || case when x.entidade is not null
                     then ':' || fn_entidade_canonica(x.entidade) else '' end), '{}')
      into v_vivos
      from fn_exigencias_do_caso(v_caso) x
     where not x.satisfeita
       and x.tipo_taxonomia = any (p_tipos);

    for v_p in
      select p.id, p.motivo
        from pendencia p
       where p.caso_id = v_caso
         and p.tipo = 'linha_exigida_ausente'
         and p.estado = 'aberta'
         and split_part(p.motivo, ':', 3) = any (p_tipos)
       for update
    loop
      if v_p.motivo = any (v_vivos) then
        v_ficaram := v_ficaram + 1;
        continue;
      end if;

      v_razao := case when exists (
                        select 1 from taxonomia_linha_exigida e
                         where e.tipo_taxonomia = split_part(v_p.motivo, ':', 3)
                           and e.conceito = split_part(v_p.motivo, ':', 4)
                           and e.ativo)
                      then 'exigencia_ativa_nao_mais_ausente'
                      else 'exigencia_inativa' end;

      update pendencia
         set estado = 'resolvida', resolvida_em = now(), resolvida_por = p_ator
       where id = v_p.id;

      insert into evento_auditoria (ator, acao, entidade_ref, antes, depois)
      values (p_ator, 'pendencia_resolvida', 'pendencia:' || v_p.id,
              jsonb_build_object('estado', 'aberta', 'motivo', v_p.motivo),
              jsonb_build_object('estado', 'resolvida', 'resolvida_por', p_ator,
                                 'razao', v_razao));
      v_resolvidas := v_resolvidas + 1;
    end loop;
  end loop;

  select count(*) into v_ressalva
    from pendencia p
   where p.tipo = 'linha_exigida_ausente'
     and p.estado = 'aceita_com_ressalva'
     and split_part(p.motivo, ':', 3) = any (p_tipos);

  return jsonb_build_object('resolvidas', v_resolvidas,
                            'ficaram_abertas', v_ficaram,
                            'ressalvadas_intocadas', v_ressalva);
end;
$$;

comment on function fn_resolver_linha_exigida_superada(text[], text) is
  '0187: resolve as pendências linha_exigida_ausente ABERTAS dos tipos pedidos que o Portão 1 não '
  'abriria mais hoje (exigência inativa ou satisfeita, pelo critério de fn_exigencias_do_caso), '
  'com um evento_auditoria por pendência. Não toca aceita_com_ressalva, não roda o resto da '
  'completude. Ação de migration/service_role — sem grant para o portal.';

revoke all on function public.fn_resolver_linha_exigida_superada(text[], text) from public;

do $$
declare
  v_r jsonb;
begin
  v_r := fn_resolver_linha_exigida_superada(
           array['MUTUOS', 'FAT_INTRAGRUPO', 'CONTRATO_SOCIAL'], 'sistema:0187');
  -- O notice é EFÊMERO (some em apply com saída capturada); a consulta de
  -- pós-apply do README conta de novo pelo resolvida_por.
  raise notice '0187 resolução dirigida: % resolvida(s), % continuam abertas (ainda ausentes '
               'de verdade), % em aceita_com_ressalva NÃO tocadas',
    v_r->>'resolvidas', v_r->>'ficaram_abertas', v_r->>'ressalvadas_intocadas';
end $$;

-- -----------------------------------------------------------------------------
-- (e) fn_sugerir_perguntas — REEMITIDA INTEIRA (corpo da 0122)
-- -----------------------------------------------------------------------------
-- Mesma função da 0122, texto obtido por pg_get_functiondef do banco montado
-- do zero (nunca corrigida por replace — .claude/memory/nunca-corrigir-funcao-por-replace.md),
-- com UMA mudança, marcada `0187:` no saldo_mutuos. O grant da 0120 continua
-- valendo (create or replace preserva privilégios).
CREATE OR REPLACE FUNCTION public.fn_sugerir_perguntas(p_caso_id uuid)
 RETURNS TABLE(codigo text, titulo text, prioridade integer, entidade text, entidade_id uuid, pergunta text, motivo text, risco text, impacto text, gatilho text, fonte text, ja_enviada boolean)
 LANGUAGE sql
 STABLE
AS $function$
  with tem_conteudo as (
    select exists (
      select 1
      from documento d
      join campo_extraido ce on ce.documento_versao_id = fn_versao_com_extracao(d.id)
      where d.caso_id = p_caso_id and ce.valor_num is not null
    ) as ok
  ),
  -- QUAIS CÓDIGOS DISPARAM, E PARA QUEM (0120/0119): a espécie `sempre` vale
  -- para o caso; as ancoradas disparam uma vez por ENTIDADE que não satisfaz,
  -- espelhando a pendência `linha_exigida_ausente`.
  disparos as (
    select pc.codigo, null::text as entidade, null::uuid as entidade_id
    from pergunta_catalogo pc
    where pc.ativo and pc.gatilho_especie = 'sempre'
      and (select ok from tem_conteudo)
    union
    select distinct pc.codigo, x.entidade, x.entidade_id
    from pergunta_catalogo pc
    join fn_exigencias_do_caso(p_caso_id) x
      on x.tipo_taxonomia = pc.gatilho_tipo_taxonomia
     and x.conceito = pc.gatilho_conceito
    where pc.ativo
      and ((pc.gatilho_especie = 'exigencia_ausente' and not x.satisfeita)
        or (pc.gatilho_especie = 'linha_presente' and x.satisfeita))
  ),
  -- {saldo_mutuos}: soma das linhas que casam MUTUOS:saldo_de_mutuo na versão
  -- vigente. Escala única acompanha; escalas mistas NÃO são somadas às cegas.
  saldo_mutuos as (
    select case
      when count(*) = 0 then null
      when count(distinct coalesce(c.unidade, '')) > 1 then '(valores em escalas mistas — conferir)'
      -- 0122: era `sum(valor)::text || ' ' || unidade`, que produzia
      -- "16060 milhar" no texto enviado ao cliente.
      else fn_valor_pt_br(sum(c.valor_num), max(nullif(c.unidade, '')))
    end as txt
    from (
      select ce.valor_num, ce.unidade
      from documento d
      join campo_extraido ce on ce.documento_versao_id = fn_versao_com_extracao(d.id)
      where d.caso_id = p_caso_id
        and d.tipo_taxonomia = 'MUTUOS'
        and ce.valor_num is not null
        and exists (
          select 1
          from taxonomia_linha_exigida e
          join taxonomia_linha_localizador l on l.exigencia_id = e.id
          -- 0187: A DESATIVAÇÃO DESLIGA A COBRANÇA, NÃO O LÉXICO. A exigência
          -- MUTUOS/saldo_de_mutuo saiu do Portão 1 (relatório itemizado: 1 de 1
          -- pendência aberta em produção era falsa), mas os localizadores dela
          -- continuam sendo o que diz "esta linha é saldo de mútuo" para somar o
          -- marcador. Com `and e.ativo`, a pergunta 5.1 ao cliente passaria a
          -- dizer "(não localizado)" sobre um saldo que está no documento.
          where e.tipo_taxonomia = 'MUTUOS' and e.conceito = 'saldo_de_mutuo'
            and (e.ativo or e.conceito = 'saldo_de_mutuo')
            and case
              when l.contra = 'estrutural' then fn_rotulo_estrutural(ce.chave, l.termos_inclui)
              else
                not exists (
                  select 1 from unnest(l.termos_inclui) t
                  where fn_normalizar_texto(case when l.contra = 'secao'
                                            then coalesce(ce.secao, '') else ce.chave end)
                    not like '%' || fn_normalizar_texto(t) || '%')
                and not exists (
                  select 1 from unnest(l.termos_exclui) t
                  where fn_normalizar_texto(case when l.contra = 'secao'
                                            then coalesce(ce.secao, '') else ce.chave end)
                    like '%' || fn_normalizar_texto(t) || '%')
            end)
    ) c
  )
  select pc.codigo, pc.titulo, pc.prioridade, di.entidade, di.entidade_id,
         -- A ENTIDADE ENTRA COMO PREFIXO, e não reescrevendo o texto da entrega.
         case when di.entidade is not null then 'Sobre a ' || di.entidade || ': ' else '' end ||
         replace(replace(replace(pc.pergunta,
           -- 0122: o período vai POR EXTENSO. Era a `referencia` crua, e o que
           -- chegava ao cliente era "Na DRE de 24,25" / "de L36M" / "de 12M25".
           '{data_base}',    coalesce(per.por_extenso, '(período não informado)')),
           '{ano}',          coalesce(per.por_extenso, '(período não informado)')),
           '{saldo_mutuos}', coalesce(sm.txt, '(não localizado)')) as pergunta,
         pc.motivo, pc.risco, pc.impacto,
         case when pc.gatilho_especie = 'sempre' then 'sempre'
              else pc.gatilho_especie || ':' || pc.gatilho_tipo_taxonomia || ':' || pc.gatilho_conceito
         end as gatilho,
         pc.fonte,
         exists (
           select 1 from caso_pergunta cp
           where cp.caso_id = p_caso_id and cp.pergunta_codigo = pc.codigo and cp.acao = 'enviada'
             and cp.entidade_id is not distinct from di.entidade_id
         ) as ja_enviada
  from pergunta_catalogo pc
  join disparos di on di.codigo = pc.codigo
  cross join saldo_mutuos sm
  -- O PERÍODO MAIS RECENTE É POR ANO, NÃO POR ORDEM ALFABÉTICA (0120) — e desde
  -- a 0122 a janela móvel não finge um ano para vencer essa escolha: `L36M`
  -- devolvia 2036 e ganhava de um 2025 real.
  left join lateral (
    select fn_periodo_por_extenso(p2.tipo, p2.referencia) as por_extenso
    from documento d2
    join periodo p2 on p2.id = d2.periodo_id
    where d2.caso_id = p_caso_id
      and (pc.gatilho_tipo_taxonomia is null or d2.tipo_taxonomia = pc.gatilho_tipo_taxonomia)
      -- O PERÍODO É O DA EMPRESA DE QUE A PERGUNTA FALA (0122). A sugestão é
      -- por (pergunta × entidade) desde a 0119, e o período não acompanhava:
      -- num grupo em que a DRE da Indústria cobre 2023–2025 e a da Comercial
      -- só 2024–2025, a pergunta sobre a Comercial saía dizendo "Na DRE de
      -- 2023 a 2025" — um exercício que o documento DELA não tem. Quem recebe
      -- não reconhece o próprio documento na pergunta.
      and (di.entidade_id is null or d2.entidade_id = di.entidade_id)
    order by coalesce((select max(a) from unnest(fn_anos_do_periodo(p2.referencia)) a), -1) desc,
             -- EMPATE NO ANO MAIS RECENTE: ganha o período MAIS ESPECÍFICO. Um
             -- caso com "2025" e "24,25" tem os dois terminando em 2025, e
             -- perguntar "no faturamento de 2025" é mais preciso que "de 2024 e
             -- 2025". Sem este critério o desempate era alfabético — e o
             -- alfabeto punha o comparativo na frente.
             cardinality(coalesce(fn_anos_do_periodo(p2.referencia), '{}'::int[])) asc,
             p2.referencia desc
    limit 1
  ) per on true
  order by pc.prioridade, pc.codigo, di.entidade nulls first;
$function$;

-- -----------------------------------------------------------------------------
-- (f) O CATÁLOGO DA SONDA
-- -----------------------------------------------------------------------------
-- D6 como seed: a view tem UMA linha quando o portão está verde e ZERO quando
-- algum tipo ativo está SEM_COBERTURA ou com DECLARACAO_QUEBRADA. É o que faz
-- a sonda de produção responder D6 — inclusive quando alguém cadastra tipo
-- novo na taxonomia sem declarar quem o lê.
create or replace view instalacao_sonda_cobertura_de_tipos as
  select 1 as d6_estrito
   where not exists (select 1 from fn_cobertura_de_tipos() c
                      where c.veredito in ('SEM_COBERTURA', 'DECLARACAO_QUEBRADA'));

comment on view instalacao_sonda_cobertura_de_tipos is
  'Sonda da 0187: uma linha = D6 estrito verde (todo tipo ativo tem exigência viva ou declaração '
  'válida em taxonomia_tipo_cobertura). Zero linhas: select * from fn_cobertura_de_tipos() where '
  'veredito in (''SEM_COBERTURA'',''DECLARACAO_QUEBRADA'') diz qual.';

grant select on instalacao_sonda_cobertura_de_tipos to authenticated;

-- As três mudanças de exigência, isoladas: as duas exigências proposta
-- DESATIVADAS e o localizador de seção do contrato. Três linhas; menos que isso
-- é banco em que as pendências falsas voltam a abrir no próximo recompute.
create or replace view instalacao_sonda_exigencias_0187 as
  select e.tipo_taxonomia, e.conceito, 'desativada'::text as mudanca
    from taxonomia_linha_exigida e
   where e.origem = 'proposta' and not e.ativo
     and (e.tipo_taxonomia, e.conceito) in (('MUTUOS', 'saldo_de_mutuo'),
                                            ('FAT_INTRAGRUPO', 'faturamento_entre_partes'))
  union all
  select e.tipo_taxonomia, e.conceito, 'localizador_secao'
    from taxonomia_linha_localizador l
    join taxonomia_linha_exigida e on e.id = l.exigencia_id
   where e.tipo_taxonomia = 'CONTRATO_SOCIAL' and e.conceito = 'capital_social' and e.ativo
     and l.contra = 'secao' and l.termos_inclui = array['capital','social']::text[];

comment on view instalacao_sonda_exigencias_0187 is
  'Sonda da 0187: MUTUOS/saldo_de_mutuo e FAT_INTRAGRUPO/faturamento_entre_partes desativadas + o '
  'localizador por seção de CONTRATO_SOCIAL/capital_social. Três linhas.';

grant select on instalacao_sonda_exigencias_0187 to authenticated;

insert into instalacao_requisito
  (chave, migration, tipo, objeto, marcador, criterio_seed, porque, severidade, ordem) values

  ('taxonomia_tipo_cobertura_existe', '0187', 'tabela', 'taxonomia_tipo_cobertura', null, null,
   'Sem a tabela, "ninguém confere este tipo" e "ninguém declarou quem confere" continuam com a '
   'mesma aparência: nenhuma linha em lugar nenhum. 18 dos 24 tipos com documento em produção '
   'estavam assim (22/09/2026).',
   'importante', 790),

  ('fn_cobertura_de_tipos_existe', '0187', 'corpo', 'fn_cobertura_de_tipos',
   'then ''DECLARACAO_QUEBRADA''', null,
   'O portão D6 como consulta. O marcador é o ramo que devolve DECLARACAO_QUEBRADA — sem ele a '
   'declaração envelhece calada (consumidor que sumiu, tipo que ganhou exigência viva).',
   'importante', 791),

  ('d6_cobertura_de_tipos_estrita', '0187', 'seed', 'instalacao_sonda_cobertura_de_tipos', null, 1,
   'D6 do DATA GATE: todo tipo ATIVO tem exigência viva ou declaração válida. Zero linhas na view '
   '= algum tipo SEM_COBERTURA ou DECLARACAO_QUEBRADA — select * from fn_cobertura_de_tipos() '
   'diz qual. Tipo novo cadastrado sem declaração também cai aqui.',
   'importante', 792),

  ('exigencias_lexicais_falsas_desligadas', '0187', 'seed', 'instalacao_sonda_exigencias_0187', null, 3,
   'Sem as duas desativações e o localizador de seção, o próximo recompute de completude reabre as '
   'pendências linha_exigida_ausente de MUTUOS, FAT_INTRAGRUPO e CONTRATO_SOCIAL — 5 de 5 abertas '
   'em produção eram falsas (22/09/2026).',
   'importante', 793),

  ('saldo_mutuos_nao_depende_da_cobranca', '0187', 'corpo', 'fn_sugerir_perguntas',
   '(e.ativo or e.conceito = ''saldo_de_mutuo'')', null,
   'Com a exigência MUTUOS/saldo_de_mutuo desativada e fn_sugerir_perguntas da 0122, a pergunta 5.1 '
   'ao CLIENTE diz "(não localizado)" sobre um saldo de mútuo que está no documento. O marcador é '
   'o predicado que lê o léxico mesmo com a exigência inativa.',
   'importante', 794)

on conflict (chave) do update
  set migration = excluded.migration, tipo = excluded.tipo, objeto = excluded.objeto,
      marcador = excluded.marcador, criterio_seed = excluded.criterio_seed,
      porque = excluded.porque, severidade = excluded.severidade, ordem = excluded.ordem;

update instalacao_cobertura
   set ate_migration = '0187', revisado_em = current_date,
       observacao = 'A 0187 cria taxonomia_tipo_cobertura (uma declaração por tipo ativo sem '
                    'exigência viva) e fn_cobertura_de_tipos (portão D6), desativa as exigências '
                    'lexicais proposta de MUTUOS e FAT_INTRAGRUPO, acrescenta localizador por seção '
                    'a CONTRATO_SOCIAL/capital_social, resolve de forma dirigida as pendências '
                    'abertas que ficaram falsas, e reemite fn_sugerir_perguntas para o {saldo_mutuos} '
                    'não depender da cobrança. A 0185 NÃO existe (descartada, nunca aplicada) e '
                    '0182-0184 são lacuna reservada: o catálogo não tem requisito para elas.';

commit;
