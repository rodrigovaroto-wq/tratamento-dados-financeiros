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
--       três jeitos, e os três viram `DECLARACAO_QUEBRADA`: o consumidor
--       nomeado some de `pg_proc`; o consumidor fica mas o MARCADOR (o trecho
--       que faz a leitura) some do corpo de `marcador_em` — achado da revisão:
--       tirar 'BALANCETE' do despachante desligava a leitura sem que nome
--       nenhum sumisse; ou o tipo ganha exigência viva e a declaração fica
--       duplicando o registro.
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
--   (e) O SALDO DA PERGUNTA 5.1 SEM LÉXICO: `fn_saldo_mutuos_do_documento`
--       (pura) e `fn_saldo_mutuos_texto` (o caso), e `fn_sugerir_perguntas`
--       REEMITIDA INTEIRA (corpo da 0122) com UMA mudança, o CTE do
--       {saldo_mutuos}. A 0122 somava as linhas cujo rótulo casava o léxico
--       de MUTUOS/saldo_de_mutuo; a primeira versão desta migration só tirou o
--       filtro `e.ativo` desse léxico, e a revisão independente mediu que isso
--       não basta: no arranjo REAL (fixture canastra, chave = par de
--       empresas) nada casa 'mutuo' e a pergunta ao CLIENTE dizia "(não
--       localizado)"; com item + total no documento a soma dobrava (300 em vez
--       de 150); no documento matricial ela atravessava as colunas (20.158 em
--       vez de 11.079). O desenho novo, no bloco (e): o documento É o
--       conceito; coluna do exercício mais recente; linha de total geral se
--       houver, senão a soma dos itens; e, quando não dá para determinar, a
--       pergunta diz que não foi possível apurar e por quê. Medição (regra 2)
--       no fim do bloco (e).
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
-- quatro primeiras devem resolver. A do CONTRATO_SOCIAL dependia de a versão
-- VIGENTE daquele documento ter a seção preenchida — e isso FOI MEDIDO pela
-- sessão principal em produção (22/09/2026, somente leitura): na versão
-- vigente do documento 9ae9ca0b-7b6a-4fa1-bf23-ef3cc8805ffc (entidade GLOBAL
-- STORE), 4 das 6 linhas têm `secao` com 'capital' e 'social'. Previsão: 5
-- resolvidas, 0 abertas. A consulta somente leitura que confere isso ANTES
-- está no `Supabase/README.md`.
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
  -- 0187 (revisão): O NOME NÃO PROVA A LEITURA. Um consumidor que continua em
  -- pg_proc mas deixou de ler o tipo (o despachante tirou 'BALANCETE' da lista,
  -- a checagem trocou de documento) mantinha a declaração verde. `marcador` é
  -- um trecho de UMA linha que precisa aparecer no corpo publicado
  -- (pg_get_functiondef) de `marcador_em` — o próprio consumidor, ou o
  -- despachante que o chama para este tipo.
  marcador       text check (marcador is null or length(btrim(marcador)) > 0),
  marcador_em    text,
  -- consumidor nomeado SEM nome é declaração que não se confere; sem_consumidor
  -- COM nome é contradição. As duas formas são recusadas pelo banco — e o
  -- mesmo vale para o marcador.
  check ((estado = 'consumidor_nomeado') = (consumidor is not null)),
  check ((estado = 'consumidor_nomeado') = (marcador is not null and marcador_em is not null)),
  check ((marcador is null) = (marcador_em is null))
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
comment on column taxonomia_tipo_cobertura.marcador is
  'Trecho de UMA linha que precisa aparecer no corpo publicado (pg_get_functiondef, \r removido) '
  'da função marcador_em para a declaração valer: é o que prova que ela AINDA lê o tipo. '
  'Obrigatório quando estado=consumidor_nomeado. Some do corpo → DECLARACAO_QUEBRADA.';
comment on column taxonomia_tipo_cobertura.marcador_em is
  'proname (schema public) da função cujo corpo carrega o marcador — o consumidor ou o despachante '
  'que o chama para o tipo (BALANCETE: fn_reconciliar_por_documento).';
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
--
-- E UM QUE NÃO ENTROU, por decisão da revisão (22/09/2026): DF_AUDITADA.
-- fn_reconciliar_intragrupo (0124) e fn_reconciliar_mutuos (0123) só a leem
-- como balanço SUBSTITUTO, quando a entidade não tem BALANCO — e o próprio
-- efeito escrito na primeira versão dizia "no caso típico ninguém lê a DF".
-- Declarar consumidor_nomeado deixava D6 verde sobre uma leitura que, no caso
-- típico, não acontece: estágio que não roda com cara de estágio que roda
-- (regra 7). Ela é sem_consumidor, com o fallback descrito no motivo.
--
-- O MARCADOR de cada consumidor é o trecho que faz a leitura, no corpo vigente:
--   MUTUOS    → em fn_reconciliar_mutuos, a busca do documento do tipo;
--   BALANCETE → em fn_reconciliar_por_documento, o `if v_tipo in (...)` que
--               despacha fn_reconciliar_arvore — tirar 'BALANCETE' da lista
--               desliga a leitura sem que o nome de função nenhum suma.
--
-- Todos os outros foram procurados como literal em todo corpo de função
-- vigente (`'TIPO'`): nenhuma função os lê, ou só o desempate/realizado os lê.
insert into taxonomia_tipo_cobertura
  (tipo_taxonomia, estado, consumidor, motivo, efeito, declarado_em, marcador, marcador_em)
values
  -- ---- os dois com consumidor que confere o número ---------------------------
  ('MUTUOS', 'consumidor_nomeado', 'fn_reconciliar_mutuos',
   'fn_reconciliar_mutuos (0123) lê a planilha de mútuos e confere o saldo contra a soma das contas '
   'de mútuo dos balanços do caso (mutuos_planilha_vs_balanco). A exigência lexical proposta da '
   '0113 foi desativada na 0187: relatório itemizado, o rótulo é o par de empresas — 1 de 1 '
   'pendência aberta em produção era falsa (22/09/2026).',
   'A conferência é por CASO, não por par de empresas: um mútuo lançado na empresa errada do grupo '
   'passa se o total bater. Mútuo com sócio fica fora (não tem espelho no mandato). Se nenhum '
   'balanço traz conta de mútuo com lado reconhecível, a checagem sai documento_ausente e NÃO abre '
   'pendência (contrato da 0186).',
   '2026-09-22',
   'fn_documento_por_tipo(p_caso_id, null, p_periodo_id, ''MUTUOS'')', 'fn_reconciliar_mutuos'),
  ('BALANCETE', 'consumidor_nomeado', 'fn_reconciliar_arvore',
   'fn_reconciliar_por_documento chama fn_reconciliar_arvore (0133) para todo BALANCETE: Σ filhos = '
   'total de cada seção do próprio documento (secao_fecha). Também é fonte de balanço em '
   'fn_reconciliar_mutuos, fn_reconciliar_intragrupo e fn_documento_balanco quando a entidade não '
   'tem BALANCO.',
   'Balancete × balanço CONTA A CONTA não é conferido: um balancete cujo saldo de uma conta difere '
   'do BP da mesma entidade só aparece se o rótulo coincidir literalmente (desempate da 0151, que '
   'não é conferência). Com BALANCO presente, ativo = passivo + PL do balancete não é checado.',
   '2026-09-22',
   'v_tipo in (''BALANCO'', ''BALANCETE'', ''COMBINADO'')', 'fn_reconciliar_por_documento'),

  -- ---- a DF auditada: lida só como balanço SUBSTITUTO, ninguém a confere ----
  ('DF_AUDITADA', 'sem_consumidor', null,
   'Nenhuma função confere a DF auditada. fn_reconciliar_intragrupo (0124) e fn_reconciliar_mutuos '
   '(0123) só a leem como balanço SUBSTITUTO, quando a entidade não tem BALANCO (ordem BALANCO, '
   'COMBINADO, DF_AUDITADA, BALANCETE), e mesmo aí conferem só os saldos intragrupo/mútuo. A '
   'primeira versão da 0187 a declarava consumidor_nomeado — revisto em 22/09/2026: no caso '
   'típico ninguém lê a DF, e o portão ficaria verde sobre uma leitura que não acontece (regra 7). '
   'Em produção 34 documentos, só 6 com linha (22/09/2026).',
   'DF auditada que diverge do balanço gerencial passa sem aviso (só aparece por rótulo '
   'coincidente, no desempate da 0151, que não é conferência). Ativo = passivo + PL da DF não é '
   'conferido (fn_documento_balanco não inclui DF_AUDITADA). Na entidade SEM BALANCO, os saldos '
   'intragrupo/mútuo dela entram em fn_reconciliar_intragrupo/fn_reconciliar_mutuos.',
   '2026-09-22', null, null),

  -- ---- os nove da 0185: relatório itemizado, ficam COMPLEMENTARES -----------
  ('AGING_AP', 'sem_consumidor', null,
   'Relatório itemizado: o rótulo é o item (fornecedor — "41518 - WELLA BRASIL LTDA." no mandato '
   'real), não o conceito. A exigência lexical da 0185 foi reprovada em 21/09/2026: AGING_AP é '
   'parte dos 17 falsos da medição AGREGADA sobre os nove tipos (a contagem por tipo não foi '
   'registrada). Nenhuma função SQL lê AGING_AP.',
   'Aging de contas a pagar cujo total não bate com Fornecedores do BP passa sem aviso; aging que '
   'chega só com a linha de resto ("Demais fornecedores") também.',
   '2026-09-22', null, null),
  ('AGING_AR', 'sem_consumidor', null,
   'Relatório itemizado: o rótulo é o item (cliente/sacado), não o conceito. A exigência lexical '
   'da 0185 foi reprovada em 21/09/2026: AGING_AR é parte dos 17 falsos da medição AGREGADA sobre '
   'os nove tipos (a contagem por tipo não foi registrada). Nenhuma função SQL lê AGING_AR.',
   'Aging de contas a receber cujo total não bate com Clientes/Contas a receber do BP passa sem '
   'aviso, e a concentração/inadimplência por faixa não é lida por ninguém.',
   '2026-09-22', null, null),
  ('EXTRATO_BANCARIO', 'sem_consumidor', null,
   'Relatório itemizado (conta × mês; o rótulo é o banco — "Banco Meridional S.A."). A exigência '
   'lexical da 0185 foi reprovada em 21/09/2026: EXTRATO_BANCARIO é parte dos 17 falsos da medição '
   'AGREGADA sobre os nove tipos (a contagem por tipo não foi registrada). Nenhuma função SQL lê '
   'EXTRATO_BANCARIO.',
   'Saldo de extrato que não bate com Caixa e equivalentes do BP passa sem aviso.',
   '2026-09-22', null, null),
  ('GARANTIAS', 'sem_consumidor', null,
   'Relatório itemizado (bem/beneficiário). ZERO documentos em produção (22/09/2026): nada foi '
   'medido para este tipo. Fica sem exigência pela FORMA (itemizado, o mesmo motivo que reprovou '
   'a 0185 nos tipos que tinham documento), não por medição dele. Nenhuma função SQL lê GARANTIAS.',
   'Bem dado em garantia não é confrontado com o MAPA_DIVIDA: dívida garantida sem garantia '
   'declarada (ou o contrário) passa sem aviso.',
   '2026-09-22', null, null),
  ('AVAIS_FIANCAS', 'sem_consumidor', null,
   'Relatório itemizado (beneficiário/obrigação). ZERO documentos em produção (22/09/2026): nada '
   'foi medido para este tipo. Fica sem exigência pela FORMA (itemizado, o mesmo motivo que '
   'reprovou a 0185 nos tipos que tinham documento), não por medição dele. Nenhuma função SQL lê '
   'AVAIS_FIANCAS.',
   'Aval ou fiança prestado pelo grupo não entra em conferência nenhuma: a dívida contingente fora '
   'do balanço não gera aviso.',
   '2026-09-22', null, null),
  ('CONTINGENCIAS', 'sem_consumidor', null,
   'Relatório itemizado (o rótulo é o processo; a seção é Trabalhista/Cível/Tributário — a palavra '
   '"contingência" não aparece no documento). 9 dos 17 falsos da medição agregada da 0185 '
   '(21/09/2026) eram deste tipo — o único com a contagem registrada. Nenhuma função SQL lê '
   'CONTINGENCIAS.',
   'Contingência provável que não bate com Provisões do BP passa sem aviso.',
   '2026-09-22', null, null),
  ('DEBITOS_TRIB', 'sem_consumidor', null,
   'Relatório itemizado (por tributo/competência). ZERO documentos em produção (22/09/2026): nada '
   'foi medido para este tipo. Fica sem exigência pela FORMA (itemizado, o mesmo motivo que '
   'reprovou a 0185 nos tipos que tinham documento), não por medição dele. Nenhuma função SQL lê '
   'DEBITOS_TRIB.',
   'Débito tributário/parcelamento que não bate com Tributos a recolher/parcelamentos do BP passa '
   'sem aviso.',
   '2026-09-22', null, null),
  ('ESTOQUE', 'sem_consumidor', null,
   'Relatório itemizado (o rótulo é o SKU — 484 linhas como "2500 - ASSALA PRIME" no mandato real). '
   'A exigência lexical da 0185 foi reprovada em 21/09/2026: ESTOQUE é parte dos 17 falsos da '
   'medição AGREGADA sobre os nove tipos (a contagem por tipo não foi registrada). Nenhuma função '
   'SQL lê ESTOQUE.',
   'Posição de estoque que não soma Estoques do BP passa sem aviso.',
   '2026-09-22', null, null),
  ('HEADCOUNT', 'sem_consumidor', null,
   'Relatório itemizado (o rótulo é o centro de custo — "Produção - turno A"; a unidade é PESSOAS). '
   'A exigência lexical da 0185 foi reprovada em 21/09/2026: HEADCOUNT (5 documentos em produção) é '
   'parte dos 17 falsos da medição AGREGADA sobre os nove tipos (a contagem por tipo não foi '
   'registrada). Nenhuma função SQL lê HEADCOUNT.',
   'Headcount não é confrontado com a despesa de pessoal da DRE: folha que cresce com quadro '
   'estável (ou o contrário) passa sem aviso.',
   '2026-09-22', null, null),

  -- ---- os outros itemizados/relatórios sem leitor --------------------------
  ('FAT_INTRAGRUPO', 'sem_consumidor', null,
   'Relatório itemizado: o rótulo é o par de empresas ou o mês ("Julho 2025"), a seção às vezes '
   'nula. A exigência lexical proposta da 0113 foi desativada na 0187: 3 de 3 pendências abertas '
   'em produção eram falsas (22/09/2026). fn_reconciliar_intragrupo (0124) confere saldos '
   'intragrupo de BALANÇO, não lê este documento.',
   'Faturamento intragrupo não é confrontado com a eliminação do COMBINADO nem com o '
   'FATURAMENTO_24M: receita intragrupo não eliminada no combinado passa sem aviso.',
   '2026-09-22', null, null),
  ('APLIC_FINANC', 'sem_consumidor', null,
   'Relatório itemizado (aplicação a aplicação; abertura analítica, 0150). Nenhuma função SQL lê '
   'APLIC_FINANC; zero documentos em produção.',
   'Posição de aplicações que não bate com Aplicações financeiras/Caixa e equivalentes do BP passa '
   'sem aviso.',
   '2026-09-22', null, null),
  ('RAZAO', 'sem_consumidor', null,
   'Abertura analítica lançamento a lançamento (0150). Só o desempate (fn_conflitos_do_caso, 0151) '
   'o lê, e só quando seção canônica e rótulo coincidem com outro documento — desempate não '
   'confere. fn_linhas_do_realizado o exclui (abertura_analitica).',
   'Saldo final do razão que não bate com a conta do BP passa sem aviso, salvo rótulo idêntico.',
   '2026-09-22', null, null),
  ('SITUACAO_FISCAL', 'sem_consumidor', null,
   'Relatório da RFB/PGFN itemizado por débito/pendência, em boa parte não numérico. Nenhuma '
   'função SQL lê SITUACAO_FISCAL.',
   'Débito ativo ou inscrito em dívida ativa que o relatório mostra não é confrontado com '
   'DEBITOS_TRIB nem com o BP: passivo fiscal fora do balanço passa sem aviso.',
   '2026-09-22', null, null),
  ('SPED', 'sem_consumidor', null,
   'Arquivo digital (ECD/ECF) sem extração estruturada no pipeline hoje. Nenhuma função SQL lê '
   'SPED; zero documentos em produção.',
   'Nada do SPED é confrontado com as demonstrações entregues: balanço gerencial que diverge do '
   'escriturado passa sem aviso.',
   '2026-09-22', null, null),

  -- ---- demonstrações que só o desempate/realizado leem ---------------------
  ('DVA', 'sem_consumidor', null,
   'Só fn_conflitos_do_caso (0151, desempate — compara quando seção canônica e rótulo coincidem '
   'com outro documento) e fn_linhas_do_realizado (0150, soma para premissa) a leem. Desempate e '
   'soma leem, não conferem.',
   'Receita e distribuição do valor adicionado que não batem com a DRE passam sem aviso, salvo '
   'rótulo idêntico ao da DRE.',
   '2026-09-22', null, null),
  ('DMPL', 'sem_consumidor', null,
   'Só fn_conflitos_do_caso (0151, desempate) e fn_linhas_do_realizado (0150) a leem; nenhuma '
   'checagem confere a DMPL contra o PL do BP.',
   'PL final da DMPL que não bate com o Patrimônio líquido do BP passa sem aviso, salvo rótulo '
   'idêntico; movimentação do PL (dividendos, aumento de capital) não é lida por ninguém.',
   '2026-09-22', null, null),
  ('NOTAS_EXPL', 'sem_consumidor', null,
   'Só fn_conflitos_do_caso (0151, desempate) e fn_linhas_do_realizado (0150) a leem. Medido na '
   'fixture canastra: NOTAS_EXPL 7.825 × BALANCO 7.822 no mesmo rótulo — o desempate COMPARA, '
   'mas só quando o rótulo coincide.',
   'Nota explicativa (abertura de dívida, imobilizado, partes relacionadas) que discorda do BP só '
   'aparece quando rótulo e seção canônica coincidem; o que a nota abre e o BP não mostra não é '
   'lido.',
   '2026-09-22', null, null),

  -- ---- documentos não numéricos por natureza -------------------------------
  ('CERTIDOES', 'sem_consumidor', null,
   'Documento não numérico por natureza (certidão negativa/positiva): 24 documentos em produção, '
   '0 com linha (22/09/2026). A 0111 já trata a ausência de linha como acerto, não como falha.',
   'Certidão POSITIVA (débito existente) não vira alerta: nada lê o conteúdo; o checklist só conta '
   'que ela chegou.',
   '2026-09-22', null, null),
  ('ORGANOGRAMA', 'sem_consumidor', null,
   'Documento não numérico por natureza: 19 documentos em produção, 0 com linha (22/09/2026).',
   'A participação societária desenhada no organograma não é confrontada com '
   'entidade.controladora_id (0181) nem com o perímetro do combinado (0180).',
   '2026-09-22', null, null),
  ('CONTRATO_SOCIAL', 'sem_consumidor', null,
   'Documento de cláusulas; o único número é o capital social. A exigência proposta capital_social '
   '(0113) continua ATIVA e ganhou, na 0187, um localizador por seção — mas ela confere PRESENÇA, '
   'não o número. Nenhuma função SQL confere o valor.',
   'Capital social do contrato não é confrontado com o Capital social do BP; composição societária '
   'e cláusula de administração não são lidas por ninguém.',
   '2026-09-22', null, null),
  ('DOCS_SOCIOS', 'sem_consumidor', null,
   'Documentos pessoais dos sócios (identidade, IR), não numéricos para o book e com sensibilidade '
   'LGPD. Nenhuma função SQL lê DOCS_SOCIOS; zero documentos em produção.',
   'Garantia pessoal ou patrimônio de sócio declarado não é cruzado com AVAIS_FIANCAS nem com a '
   'dívida.',
   '2026-09-22', null, null),
  ('CONTRATO_DIVIDA', 'sem_consumidor', null,
   'Contrato (cláusulas de taxa, prazo, covenant, garantia) sem linha numérica padronizada. Nenhuma '
   'função SQL lê CONTRATO_DIVIDA; zero documentos em produção.',
   'Taxa, vencimento e covenants do contrato não são confrontados com o MAPA_DIVIDA: mapa que '
   'diverge do contrato passa sem aviso.',
   '2026-09-22', null, null),
  ('CONTRATOS_COM', 'sem_consumidor', null,
   'Contratos comerciais, não numéricos em linha. Nenhuma função SQL lê CONTRATOS_COM; zero '
   'documentos em produção.',
   'Exclusividade, change of control e concentração de cliente em contrato não são lidas.',
   '2026-09-22', null, null),
  ('CONTRATOS_IC', 'sem_consumidor', null,
   'Contratos intercompany, não numéricos em linha. Nenhuma função SQL lê CONTRATOS_IC; zero '
   'documentos em produção.',
   'Contrato intercompany não é confrontado com FAT_INTRAGRUPO nem com os mútuos: preço de '
   'transferência e obrigação entre empresas do grupo passam sem aviso.',
   '2026-09-22', null, null),

  -- ---- projeções: não são realizado -----------------------------------------
  ('FLUXO_PROJETADO', 'sem_consumidor', null,
   'Projeção do cliente, não realizado — nada a conferir contra demonstração. Nenhuma função SQL '
   'lê FLUXO_PROJETADO; zero documentos em produção.',
   'A projeção do cliente não é comparada com o modelo do book: premissa do cliente mais otimista '
   'que a do modelo passa sem aviso.',
   '2026-09-22', null, null),
  ('PLANO_NEGOCIOS', 'sem_consumidor', null,
   'Documento narrativo/projetivo. Nenhuma função SQL lê PLANO_NEGOCIOS; zero documentos em '
   'produção.',
   'Metas do plano de negócios não são confrontadas com o modelo nem com o realizado.',
   '2026-09-22', null, null),
  ('PREMISSAS', 'sem_consumidor', null,
   'Premissas enviadas pelo cliente (documento, não premissa_catalogo). Nenhuma função SQL lê '
   'documentos PREMISSAS; zero documentos em produção.',
   'Premissa do cliente não é comparada com a premissa do modelo (premissa_catalogo, 0038): '
   'divergência entre as duas passa sem aviso.',
   '2026-09-22', null, null)
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
  marcador_presente boolean,
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
           end as consumidor_existe,
           -- 0187 (revisão): o nome em pg_proc não prova que a função AINDA lê
           -- o tipo. O marcador precisa estar no corpo PUBLICADO, com o \r
           -- tirado dos dois lados — produção guarda corpo com CRLF
           -- (.claude/memory/ancora-de-texto-quebra-com-crlf.md).
           case when c.marcador is null then null
                else exists (select 1 from pg_proc p
                               join pg_namespace ns on ns.oid = p.pronamespace
                              where ns.nspname = 'public' and p.proname = c.marcador_em
                                and p.prokind = 'f'
                                and position(replace(c.marcador, E'\r', '')
                                             in replace(pg_get_functiondef(p.oid), E'\r', '')) > 0)
           end as marcador_presente
      from taxonomia_tipo_documento t
      left join vivas v on v.tipo_taxonomia = t.codigo
      left join taxonomia_tipo_cobertura c on c.tipo_taxonomia = t.codigo
     where t.ativo
  )
  select b.codigo, b.obrigatoriedade, b.n_vivas, b.estado, b.consumidor, b.consumidor_existe,
         b.marcador_presente,
         case
           -- Duplo registro: o tipo ganhou exigência viva e a declaração ficou.
           -- Ela envelhece calada (o consumidor pode sumir, o motivo mentir), e
           -- o portão quer UMA fonte por tipo.
           when b.n_vivas > 0 and b.declarado            then 'DECLARACAO_QUEBRADA'
           when b.n_vivas > 0                            then 'exigencia_viva'
           when not b.declarado                          then 'SEM_COBERTURA'
           when b.estado = 'consumidor_nomeado'
            and not b.consumidor_existe                  then 'DECLARACAO_QUEBRADA'
           -- O consumidor existe mas o trecho que faz a leitura sumiu do corpo
           -- (do dele ou do despachante que o chama): a declaração mente.
           when b.estado = 'consumidor_nomeado'
            and not coalesce(b.marcador_presente, false) then 'DECLARACAO_QUEBRADA'
           when b.estado = 'consumidor_nomeado'          then 'consumidor_nomeado'
           else 'sem_consumidor_declarado'
         end
    from base b
   order by b.codigo;
$$;

-- MEDIDO (regra 2, 22/09/2026): sem o ramo do marcador, 3 asserts — os 2 do
-- bloco 3b de cobertura_de_tipos.test.sql (despachante sem 'BALANCETE' fica
-- consumidor_nomeado; a sonda D6 fica verde) + 1 de instalacao.test.sql (o
-- requisito cobertura_confere_marcador). Sem o check do marcador na tabela: 1
-- (o insert de consumidor_nomeado sem marcador passa). DF_AUDITADA de volta a
-- consumidor_nomeado: 1.
comment on function fn_cobertura_de_tipos() is
  '0187 — portão D6. Uma linha por tipo ATIVO da taxonomia. D6 estrito = nenhuma linha com '
  'veredito SEM_COBERTURA (sem exigência viva e sem declaração) nem DECLARACAO_QUEBRADA '
  '(consumidor nomeado que não existe em pg_proc, marcador que sumiu do corpo de marcador_em, ou '
  'declaração para tipo que já tem exigência viva). Não depende de documento: roda igual no banco '
  'de teste e em produção.';

grant execute on function public.fn_cobertura_de_tipos() to authenticated;

-- -----------------------------------------------------------------------------
-- (c) AS EXIGÊNCIAS LEXICAIS QUE ERAM FALSAS
-- -----------------------------------------------------------------------------
-- A LINHA FICA (ativo=false): pergunta_catalogo tem FK para (tipo, conceito) e
-- a trilha das pendências antigas cita o motivo. (A primeira versão desta
-- migration também deixava fn_sugerir_perguntas lendo os localizadores dela
-- como léxico do {saldo_mutuos}; desde a revisão o saldo não lê léxico
-- nenhum — ver (e).)
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
-- (e) O SALDO DE MÚTUOS DA PERGUNTA 5.1 — o documento É o conceito
-- -----------------------------------------------------------------------------
-- A 0122 somava as linhas do MUTUOS cujo RÓTULO casasse o léxico da exigência
-- MUTUOS/saldo_de_mutuo (['mutuo'] exclui ['total']). A primeira versão desta
-- migration só tirou o filtro `e.ativo` desse léxico. A revisão independente
-- (22/09/2026) mediu que isso não basta, porque o defeito é a premissa, não o
-- filtro (`.claude/memory/conceito-nao-esta-no-rotulo-de-relatorio-itemizado.md`):
--   (a) NO ARRANJO REAL (fixture canastra, documento
--       44444444-3333-0000-0000-000000000014 — as chaves são o PAR de empresas,
--       "CANASTRA PARTICIPAÇÕES S.A. → CANASTRA INDÚSTRIA…" 11.160 e "… →
--       CANASTRA COMERCIAL…" 4.900, e "TOTAL" 16.060; a palavra "mútuo" só está
--       na seção) nenhuma linha casa 'mutuo' e a pergunta ao CLIENTE dizia
--       "(não localizado)" — ausência apresentada como dado (regra 1);
--   (b) com um localizador que casasse item E total, a soma contava os dois:
--       "Mútuo a receber - Beta" 100 + "Mútuo a pagar - Gama" 50 + "Saldo total
--       dos mútuos" 150 saía "R$ 300 mil" (certo: 150);
--   (c) no documento MATRICIAL (Saldo 2024 7.991 / Juros 1.088 / Saldo 2025
--       11.079 na mesma linha, 0145 "o conceito que mora na coluna") a soma
--       atravessava as colunas: "R$ 20.158 mil" (certo: 11.079).
--
-- O DESENHO. Num relatório itemizado o conceito é o TIPO do documento: toda
-- linha com valor de um MUTUOS é mútuo. O que falta decidir é só QUAIS linhas
-- somar, e isso é estrutural, não lexical:
--   1. A COLUNA. Uma só (ou nenhuma) → ela. Várias → a do exercício MAIS
--      RECENTE (fn_anos_texto no cabeçalho, o mesmo de fn_coluna_periodo_do_ano);
--      empate no ano → a única cujo cabeçalho diz "saldo". Nenhuma coluna com
--      ano, ou empate sem "saldo" → NÃO APURA, e diz por quê.
--   2. A LINHA DE TOTAL GERAL, se existir: rótulo com a palavra total/subtotal/
--      soma e, tiradas as palavras de ligação (fn_tokens_estruturais, 0034/0102),
--      nada além do vocabulário do próprio documento (saldo, mútuo, empréstimo,
--      intragrupo, partes relacionadas, grupo, operações). "TOTAL" e "Saldo total
--      dos mútuos" são; "Total a receber" NÃO é (é subtotal de um lado).
--      Dois totais gerais com valores diferentes → NÃO APURA.
--   3. SEM TOTAL GERAL: a soma dos ITENS (linhas sem a palavra total), numa
--      escala só. Subtotal parcial nunca entra na soma. Escalas diferentes → NÃO
--      APURA (não se soma às cegas).
-- NÃO APURAR é uma resposta: a pergunta diz "não foi possível apurar o saldo"
-- e o porquê — nunca um número somado de linhas que não se somam.
--
-- O QUE ISTO NÃO FAZ: não separa mútuo de conta corrente ou aluguel
-- intragrupo listados na mesma planilha (fn_reconciliar_mutuos, 0123, faz isso
-- pelos degraus de rótulo/seção, e a pergunta é sobre o perímetro das
-- operações, não sobre a natureza), nem tira o mútuo com sócio.
--
-- Função PURA sobre as linhas (jsonb), separada da que lê o banco, para a
-- sonda de instalação poder EXECUTÁ-LA sobre os três arranjos acima em
-- produção (instalacao_sonda_saldo_mutuos) — um marcador de texto não prova
-- comportamento, uma função executada prova (a lição da 0157).
-- As linhas com valor, normalizadas uma vez. Indicador derivado (taxa, prazo
-- médio — fn_papel_linha) não é saldo e não entra.
create or replace function fn_saldo_mutuos_linhas(p_linhas jsonb)
returns table (chave text, valor numeric, unidade text, coluna text, eh_total boolean,
               eh_total_geral boolean)
language sql immutable
as $$
  select x->>'chave', (x->>'valor')::numeric, nullif(btrim(x->>'unidade'), ''),
         coalesce(nullif(btrim(x->>'coluna'), ''), ''),
         t.eh_total,
         t.eh_total and fn_tokens_estruturais(x->>'chave')
                        <@ array['saldo','saldos','mutuo','mutuos','emprestimo','emprestimos',
                                 'intragrupo','partes','relacionadas','grupo','operacoes',
                                 'operacao','entre','empresas']::text[]
    from jsonb_array_elements(coalesce(p_linhas, '[]'::jsonb)) x
    cross join lateral (select fn_normalizar_texto(x->>'chave')
                               ~ '(^|[^a-z])(total|totais|subtotal|soma|somatorio)([^a-z]|$)'
                               as eh_total) t
   where x->>'valor' is not null
     and fn_papel_linha(x->>'chave') <> 'derivado';
$$;

create or replace function fn_saldo_mutuos_do_documento(p_linhas jsonb)
returns jsonb
language plpgsql immutable
as $$
declare
  v_n        int;
  v_cols     text[];
  v_ano      int;
  v_cand     text[];
  v_col      text;
  v_tot_n    int;
  v_tot_vals numeric[];
  v_tot_unid text[];
  v_it_n     int;
  v_it_unid  text[];
  v_soma     numeric;
begin
  select count(*)::int, array_agg(distinct l.coluna order by l.coluna)
    into v_n, v_cols from fn_saldo_mutuos_linhas(p_linhas) l;
  if v_n = 0 then
    return jsonb_build_object('valor', null, 'porque', null, 'n_linhas', 0);
  end if;

  -- 1. A COLUNA
  if cardinality(v_cols) = 1 then
    v_col := v_cols[1];
  else
    select max(a) into v_ano from unnest(v_cols) c, unnest(fn_anos_texto(c)) a;
    if v_ano is null then
      return jsonb_build_object('valor', null, 'n_linhas', v_n, 'porque',
        format('a relação tem %s colunas de valor (%s) e nenhuma diz o exercício — somá-las '
               'misturaria saldo com juros ou com o ano anterior',
               cardinality(v_cols), array_to_string(v_cols, ', ')));
    end if;
    select array_agg(c order by c) into v_cand from unnest(v_cols) c
     where v_ano = any (fn_anos_texto(c));
    if cardinality(v_cand) > 1 then
      select array_agg(c order by c) into v_cand from unnest(v_cand) c
       where fn_normalizar_texto(c) like '%saldo%';
    end if;
    if coalesce(cardinality(v_cand), 0) <> 1 then
      return jsonb_build_object('valor', null, 'n_linhas', v_n, 'porque',
        format('a relação tem mais de uma coluna do exercício %s (%s) e nenhuma é, sozinha, a '
               'do saldo', v_ano, array_to_string(v_cols, ', ')));
    end if;
    v_col := v_cand[1];
  end if;

  -- 2. O TOTAL GERAL
  select count(*)::int, array_agg(distinct l.valor order by l.valor),
         array_agg(distinct coalesce(l.unidade, '') order by coalesce(l.unidade, ''))
    into v_tot_n, v_tot_vals, v_tot_unid
    from fn_saldo_mutuos_linhas(p_linhas) l
   where l.coluna = v_col and l.eh_total_geral;
  if v_tot_n > 0 then
    if cardinality(v_tot_vals) = 1 and cardinality(v_tot_unid) = 1 then
      return jsonb_build_object('valor', v_tot_vals[1], 'unidade', nullif(v_tot_unid[1], ''),
        'forma', 'linha_de_total', 'coluna', nullif(v_col, ''), 'n_linhas', v_n, 'porque', null);
    end if;
    return jsonb_build_object('valor', null, 'n_linhas', v_n, 'porque',
      format('a relação tem %s linhas de total geral que não concordam entre si', v_tot_n));
  end if;

  -- 3. A SOMA DOS ITENS
  select count(*), array_agg(distinct coalesce(l.unidade, '') order by coalesce(l.unidade, '')),
         sum(l.valor)
    into v_it_n, v_it_unid, v_soma
    from fn_saldo_mutuos_linhas(p_linhas) l
   where l.coluna = v_col and not l.eh_total;
  if v_it_n = 0 then
    return jsonb_build_object('valor', null, 'n_linhas', v_n, 'porque',
      'a relação só traz subtotais parciais, sem total geral nem os itens');
  end if;
  if cardinality(v_it_unid) > 1 then
    return jsonb_build_object('valor', null, 'n_linhas', v_n, 'porque',
      'as linhas da relação estão em escalas diferentes');
  end if;
  return jsonb_build_object('valor', v_soma, 'unidade', nullif(v_it_unid[1], ''),
    'forma', 'soma_dos_itens', 'coluna', nullif(v_col, ''), 'n_itens', v_it_n,
    'n_linhas', v_n, 'porque', null);
end;
$$;

comment on function fn_saldo_mutuos_do_documento(jsonb) is
  '0187 (revisão): o saldo de UMA relação de mútuos a partir das linhas com valor '
  '([{chave, valor, unidade, coluna}]). Coluna do exercício mais recente; linha de total geral se '
  'houver, senão a soma dos itens numa escala só. Devolve {valor, unidade, forma, coluna} ou '
  '{valor: null, porque} quando não dá para apurar com segurança — nunca uma soma cega. Pura: a '
  'sonda instalacao_sonda_saldo_mutuos a executa sobre literais.';

-- O TEXTO DO {saldo_mutuos}, para o caso. Relação de mútuos é documento do
-- GRUPO (fn_reconciliar_mutuos, 0123): o esperado é UMA por caso. Entre várias,
-- valem só as do período mais recente; se ainda sobra mais de uma, não há
-- "o" saldo do caso para citar ao cliente, e a pergunta diz isso em vez de
-- somar relações que podem ser a mesma planilha em duas datas.
create or replace function fn_saldo_mutuos_texto(p_caso_id uuid)
returns text
language sql stable
as $$
  with docs as (
    select d.id, dv.nome_original,
           (select max(a) from unnest(fn_anos_do_periodo(p.referencia)) a) as ano,
           fn_saldo_mutuos_do_documento((
             select jsonb_agg(jsonb_build_object('chave', ce.chave, 'valor', ce.valor_num,
                                                 'unidade', ce.unidade,
                                                 'coluna', ce.periodo_coluna))
               from campo_extraido ce
              where ce.documento_versao_id = dv.id and ce.valor_num is not null)) as r
      from documento d
      join documento_versao dv on dv.id = fn_versao_com_extracao(d.id)
      left join periodo p on p.id = d.periodo_id
     where d.caso_id = p_caso_id
       and d.tipo_taxonomia = 'MUTUOS'
  ),
  com_valor as (
    select * from docs where coalesce((r->>'n_linhas')::int, 0) > 0
  ),
  recentes as (
    select * from com_valor
     where ano is not distinct from (select max(ano) from com_valor)
        or (select max(ano) from com_valor) is null
  )
  select case
    when count(*) = 0 then null
    when count(*) = 1 then
      coalesce(fn_valor_pt_br(max((r->>'valor')::numeric), max(r->>'unidade')),
               '(não foi possível apurar o saldo: ' || max(r->>'porque') || ' — conferir na relação enviada)')
    when count(*) filter (where r->>'valor' is null) > 0 then
      '(não foi possível apurar o saldo: ' || string_agg(nome_original || ' — ' || (r->>'porque'), '; ')
        filter (where r->>'valor' is null) || ')'
    when count(distinct coalesce(r->>'unidade', '')) > 1 then '(valores em escalas mistas — conferir)'
    else format('(não foi possível apurar um saldo único: o caso tem %s relações de mútuos do mesmo '
                'exercício — conferir qual vale)', count(*))
  end
  from recentes;
$$;

-- MEDIDO (regra 2, 22/09/2026, banco montado do zero com a correção
-- desligada, contando todos os arquivos de teste sem parar no primeiro):
--   • CTE de volta ao léxico (o corpo da primeira versão): 5 asserts — os 4 do
--     bloco 13 de perguntas.test.sql (canastra real "(não localizado)"; item +
--     total "R$ 300 mil"; matricial e sem-exercício "(não localizado)", porque a
--     chave é o par de empresas) + 1 de instalacao.test.sql (o requisito de
--     corpo saldo_mutuos_nao_depende_da_cobranca);
--   • linha de total NÃO excluída dos itens: 3 — canastra "R$ 32.120 mil",
--     item + total "R$ 300 mil", e a sonda instalacao_sonda_saldo_mutuos;
--   • coluna NÃO escolhida (a primeira, qualquer que seja): 3 — matricial
--     "R$ 1.088 mil" (a coluna de juros), sem-exercício "R$ 120 mil", e a sonda.
comment on function fn_saldo_mutuos_texto(uuid) is
  '0187 (revisão): o texto do marcador {saldo_mutuos} da pergunta 5.1. NULL sem relação de mútuos '
  'com valor (a pergunta diz "(não localizado)"); o saldo em reais quando UMA relação do período '
  'mais recente o apura; "(não foi possível apurar…)" com o motivo em qualquer outro caso.';

-- O portal chama fn_sugerir_perguntas como `authenticated` (grant da 0120), e
-- ela chama estas três: em produção o Supabase não dá EXECUTE público a função
-- nova (ver o comentário de privilégio no Supabase/test/run.sh), e sem o grant
-- a aba de perguntas recebe "permission denied" — a 0028 de novo.
grant execute on function public.fn_saldo_mutuos_linhas(jsonb) to authenticated;
grant execute on function public.fn_saldo_mutuos_do_documento(jsonb) to authenticated;
grant execute on function public.fn_saldo_mutuos_texto(uuid) to authenticated;

-- -----------------------------------------------------------------------------
-- (e2) fn_sugerir_perguntas — REEMITIDA INTEIRA (corpo da 0122)
-- -----------------------------------------------------------------------------
-- Mesma função da 0122, texto obtido por pg_get_functiondef do banco montado
-- do zero (nunca corrigida por replace — .claude/memory/nunca-corrigir-funcao-por-replace.md),
-- com UMA mudança, marcada `0187:` no saldo_mutuos: o CTE passa a ser
-- fn_saldo_mutuos_texto (acima), e não lê mais léxico de exigência nenhuma. O
-- grant da 0120 continua valendo (create or replace preserva privilégios).
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
  -- {saldo_mutuos}: 0187 — o saldo da relação de mútuos como a RELAÇÃO o diz
  -- (linha de total geral, senão soma dos itens, na coluna do exercício mais
  -- recente), ou "(não foi possível apurar…)" com o motivo. Era a soma das
  -- linhas cujo rótulo casava o léxico MUTUOS/saldo_de_mutuo, e no arranjo
  -- real (o rótulo é o par de empresas) nada casava: a pergunta ao cliente
  -- dizia "(não localizado)" sobre um saldo que está no documento.
  saldo_mutuos as (
    select fn_saldo_mutuos_texto(p_caso_id) as txt
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

-- O SALDO DA PERGUNTA 5.1 COMO COMPORTAMENTO, não como texto de corpo. A
-- primeira versão desta migration usava como marcador `(e.ativo or e.conceito
-- = 'saldo_de_mutuo')`, que é verdadeiro por construção (o `where` logo acima
-- já fixa o conceito) — um marcador que não prova nada. Aqui a função pura é
-- EXECUTADA em produção sobre os arranjos que a revisão mediu, e cada linha
-- só aparece se o resultado for o certo.
create or replace view instalacao_sonda_saldo_mutuos as
  with casos(arranjo, linhas, esperado) as (values
    ('canastra_par_de_empresas_e_TOTAL', jsonb_build_array(
       jsonb_build_object('chave', 'CANASTRA PARTICIPAÇÕES S.A. → CANASTRA INDÚSTRIA DE EMBALAGENS LTDA.',
                          'valor', 11160, 'unidade', 'milhar', 'coluna', '2025'),
       jsonb_build_object('chave', 'CANASTRA PARTICIPAÇÕES S.A. → CANASTRA COMERCIAL E DISTRIBUIDORA LTDA.',
                          'valor', 4900, 'unidade', 'milhar', 'coluna', '2025'),
       jsonb_build_object('chave', 'TOTAL', 'valor', 16060, 'unidade', 'milhar', 'coluna', '2025')),
     16060::numeric),
    ('itens_e_total_geral', jsonb_build_array(
       jsonb_build_object('chave', 'Mútuo a receber - Beta', 'valor', 100, 'unidade', 'milhar'),
       jsonb_build_object('chave', 'Mútuo a pagar - Gama', 'valor', 50, 'unidade', 'milhar'),
       jsonb_build_object('chave', 'Saldo total dos mútuos', 'valor', 150, 'unidade', 'milhar')),
     150::numeric),
    ('matricial_saldo_juros_saldo', jsonb_build_array(
       jsonb_build_object('chave', 'Alfa → Beta', 'valor', 7991, 'unidade', 'milhar', 'coluna', 'Saldo 2024'),
       jsonb_build_object('chave', 'Alfa → Beta', 'valor', 1088, 'unidade', 'milhar', 'coluna', 'Juros'),
       jsonb_build_object('chave', 'Alfa → Beta', 'valor', 11079, 'unidade', 'milhar', 'coluna', 'Saldo 2025')),
     11079::numeric),
    ('duas_colunas_sem_exercicio', jsonb_build_array(
       jsonb_build_object('chave', 'Alfa → Beta', 'valor', 100, 'unidade', 'milhar', 'coluna', 'Saldo inicial'),
       jsonb_build_object('chave', 'Alfa → Beta', 'valor', 120, 'unidade', 'milhar', 'coluna', 'Saldo final')),
     null::numeric)
  )
  select c.arranjo
    from casos c
    cross join lateral (select fn_saldo_mutuos_do_documento(c.linhas) as r) x
   where case when c.esperado is null
              then x.r->>'valor' is null and coalesce(x.r->>'porque', '') <> ''
              else (x.r->>'valor')::numeric = c.esperado end;

comment on view instalacao_sonda_saldo_mutuos is
  'Sonda da 0187 (revisão): uma linha por arranjo em que fn_saldo_mutuos_do_documento dá o saldo '
  'CERTO (canastra real 16.060; item + total 150; matricial 11.079; sem exercício → não apura). '
  'Quatro linhas.';

grant select on instalacao_sonda_saldo_mutuos to authenticated;

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
   'select fn_saldo_mutuos_texto(p_caso_id) as txt', null,
   'Com fn_sugerir_perguntas da 0122, o {saldo_mutuos} da pergunta 5.1 ao CLIENTE soma as linhas '
   'cujo rótulo casa o léxico de MUTUOS/saldo_de_mutuo: no arranjo real (o rótulo é o par de '
   'empresas) diz "(não localizado)" sobre um saldo que está no documento, e com item + total '
   'soma os dois. O marcador é o CTE que delega ao cálculo estrutural; o comportamento dele é o '
   'requisito seguinte.',
   'importante', 794),

  ('saldo_mutuos_estrutural', '0187', 'seed', 'instalacao_sonda_saldo_mutuos', null, 4,
   'fn_saldo_mutuos_do_documento EXECUTADA sobre quatro arranjos: o real da canastra (par de '
   'empresas + TOTAL → 16.060), item + total (→ 150, não 300), matricial Saldo 2024/Juros/Saldo '
   '2025 (→ 11.079, não 20.158) e duas colunas sem exercício (→ não apura, com motivo). Menos de '
   'quatro linhas = o saldo que vai ao cliente na pergunta 5.1 está errado nesse arranjo — select '
   '* from instalacao_sonda_saldo_mutuos diz qual passou.',
   'importante', 795),

  ('cobertura_confere_marcador', '0187', 'corpo', 'fn_cobertura_de_tipos',
   'and not coalesce(b.marcador_presente, false) then ''DECLARACAO_QUEBRADA''', null,
   'Sem este ramo, o consumidor nomeado que continua em pg_proc mas deixou de ler o tipo (o '
   'despachante tirou ''BALANCETE'' da lista) mantém a declaração verde: D6 passa sobre uma '
   'leitura que não acontece.',
   'importante', 796)

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
                    'abertas que ficaram falsas, e reemite fn_sugerir_perguntas com o {saldo_mutuos} '
                    'estrutural (fn_saldo_mutuos_texto: o documento é o conceito, total geral ou '
                    'soma dos itens, coluna do exercício mais recente, e "não foi possível apurar" '
                    'com o motivo). A declaração exige marcador no corpo de quem lê. A 0185 NÃO '
                    'existe (descartada, nunca aplicada) e '
                    '0182-0184 são lacuna reservada: o catálogo não tem requisito para elas.';

commit;
