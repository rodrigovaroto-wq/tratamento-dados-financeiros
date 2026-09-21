-- =============================================================================
-- 0185 — Nove tipos do complementar chegam e ninguém confere o CONTEÚDO
--
-- O DEFEITO. `taxonomia_linha_exigida` (0113) nomeou o que precisa existir
-- dentro de um documento para seis tipos (BALANCO, COMBINADO, FLUXO_CAIXA,
-- DRE, FATURAMENTO_24M, MAPA_DIVIDA — origem 'codigo') e propôs mais três
-- (MUTUOS, FAT_INTRAGRUPO, CONTRATO_SOCIAL — origem 'proposta'). Fora esses
-- nove, mais DEZOITO tipos da taxonomia (0002) não têm NENHUMA linha na
-- tabela — o Portão 1 confere que o tipo tem "conteúdo" (`fn_linhas_do_tipo`
-- > 0, 0036), mas não confere QUE conteúdo. Um AGING_AP com uma única linha
-- de rodapé ("Total: R$ 0,00") passa pela completude do mesmo jeito que um
-- aging completo por fornecedor — o documento "chegou", rendeu uma linha
-- extraída qualquer, e ninguém percebeu que o book sai vazio nessa parte.
--
-- ESTA MIGRATION fecha nove desses dezoito (fatia F2.1 do roadmap —
-- `Arquitetura do Sistema/3 Estado e Execução/ARQUITETURA_ALVO_E_ROADMAP.md`,
-- "F2 — COBERTURA DE TIPOS"): AGING_AP, AGING_AR, EXTRATO_BANCARIO,
-- GARANTIAS, AVAIS_FIANCAS, CONTINGENCIAS, DEBITOS_TRIB, ESTOQUE, HEADCOUNT.
-- MAPA_DIVIDA já tem exigência 'codigo' desde a 0113 (o mapa fino — taxa por
-- contrato, granularidade abaixo da linha — é a fatia F2.2, separada). Os
-- outros nove tipos mudos que sobram ficam para fatias seguintes.
--
-- MESMO MECANISMO DA 0113, ORIGEM 'proposta': nenhuma reconciliação lê estes
-- nove tipos hoje (não há um `fn_reconciliar_*` para aging, garantia ou
-- headcount), então não há termo "vigente" para copiar — cada localizador
-- abaixo é PROPOSTO por este trabalho, não extraído de código existente. Por
-- isso `origem='proposta'` em todas, como MUTUOS/FAT_INTRAGRUPO/CONTRATO_SOCIAL.
--
-- MESMA REDUÇÃO DECLARADA. A entrega aprovada (`Arquitetura do Sistema/2
-- Especificação/f0/03_taxonomia_reestruturacao.md`) pede estrutura que
-- "existe linha com valor casando um termo" não exprime: aging pede FAIXA de
-- vencimento por contraparte, extrato pede conta × mês, garantias e avais
-- pedem beneficiário/bem, contingências pedem por PROCESSO com probabilidade
-- de perda, débitos tributários pedem por competência, estoque pede por
-- SKU, headcount pede por mês × entidade. Cada `descricao` abaixo nomeia a
-- redução, para ela não passar por cobertura completa.
--
-- UM CONCEITO por tipo — o precedente da 0113 é deliberadamente reduzido, e
-- nenhum destes nove tem uma segunda linha óbvia o bastante para justificar
-- inventar estrutura que a entrega não isolou com a mesma clareza que "Ativo
-- Total" e "Caixa" tinham no balanço. Dois tipos (AVAIS_FIANCAS,
-- DEBITOS_TRIB e HEADCOUNT) ganham um SEGUNDO localizador em cascata para o
-- mesmo conceito — não um segundo conceito — porque o rótulo real varia
-- entre sinônimos plausíveis ("aval" vs. "fiança", "tributo" vs. "imposto",
-- "headcount" vs. "funcionário") e a exigência satisfaz-se quando QUALQUER
-- localizador casa (mesmo padrão do `juros`/`encargos` de MAPA_DIVIDA, 0113).
--
-- POLÍTICA: severidade e sobrepujavel ficam NULL — decisão do dono, como a
-- 0113 fez. Isto NÃO promove nenhum destes nove a bloqueante nem toca
-- `fn_recomputar_completude`: o passo (2b) já lê QUALQUER exigência ativa via
-- `fn_exigencias_do_caso` (0113/0166), então as nove exigências novas entram
-- em produção sozinhas, sem função nenhuma reemitida aqui — exatamente como
-- as três propostas da 0113 já entraram.
--
-- "SOZINHAS" NÃO É "SÓ NA PRÓXIMA EXTRAÇÃO". `fn_recomputar_completude` é
-- chamada de dentro de `fn_registrar_campos_extraidos` (0128:989) E de mais
-- sete lugares (0008:206, 0018:117, 0041:396, 0043:298, 0111:234, 0129:286, e
-- o nó "Recomputar Completude" de `N8N/workflow.e1-ingestao.json`). Aplicar
-- esta migration em produção materializa as nove exigências RETROATIVAMENTE
-- para todo caso já gravado, no primeiro recompute que tocar cada um — o que
-- inclui qualquer revisão no portal, não só extração de documento novo. Quem
-- aplicar mede o alcance ANTES, pela lição da 0179
-- (`.claude/memory/aplicar-migration-em-producao-pela-api.md`) — ver o
-- comentário junto do comando de apply em `Supabase/README.md`.
--
-- Idempotente: `on conflict (tipo_taxonomia, conceito) do nothing` /
-- `on conflict (exigencia_id, ordem) do nothing`, padrão do seed da 0113.
--
-- CORREÇÃO (revisão independente, medida contra
-- Supabase/test/fixture_book_canastra.sql — o documento mais realista que o
-- repositório tem, gerado e versionado pelo CI). A PRIMEIRA versão desta
-- migration só tinha localizador `contra='chave'`. Contra a fixture real, isso
-- é o MESMO defeito que a 0166 já corrigiu uma vez, em escala 4×: em quatro
-- tipos, o termo que a extração real usa não mora no RÓTULO da linha, mora na
-- SEÇÃO — e um localizador que só olha `chave` não vê o documento correto,
-- abre pendência FALSA nele.
--
--   • CONTINGENCIAS: as chaves são "Trabalhista — Reclamações de horas
--     extras…", "Tributária — Glosa de créditos de ICMS…" — "contingência"
--     está na secao ("CONTINGÊNCIAS — Provável"/"Possível"/"Remoto"), não na
--     chave.
--   • HEADCOUNT: as chaves são nomes de centro de custo ("Produção - turno
--     A", "Diretoria") — "Headcount" é a SECAO; zero ocorrências de
--     "headcount"/"funcionario" em qualquer chave da fixture.
--   • EXTRATO_BANCARIO: as chaves são "Banco Meridional S.A. — ag. 0341 c/c
--     12.884-7" — "saldo" só aparece na secao ("SALDOS BANCÁRIOS").
--   • ESTOQUE: a única chave que contém "estoque" é "TOTAL DE ESTOQUES", e o
--     `exclui ['total']` do localizador por chave a mata de propósito (é o
--     mesmo `exclui` que protege os outros tipos itemizados de satisfazer só
--     com o rodapé). As linhas REAIS de estoque ("Matérias-primas…",
--     "Produtos acabados", "(-) Provisão para obsolescência") têm chaves sem
--     a palavra "estoque" nenhuma — mas TÊM secao = "ESTOQUES", em várias
--     linhas além do total (fixture:1067, 1080, 1086 — não só a 1086).
--
-- A CORREÇÃO acrescenta, para esses quatro conceitos, um localizador em
-- CASCATA com `contra='secao'` (mecanismo que já existe desde a 0113,
-- 0113:150-162 e o `case` de 0113:230-240 — não foi usado em nenhum dos nove
-- localizadores originais desta migration). A exigência satisfaz-se quando
-- QUALQUER localizador casa, então o de `chave` continua ali (documentando a
-- convenção "codigo" que ele cobriria, se algum documento a usasse) e o novo
-- de `secao` é quem de fato casa a fixture real. Para ESTOQUE, especificamente,
-- a decisão é MANTER o `exclui ['total']` do localizador por chave — ele seria
-- perigoso remover (um documento que só trouxesse "TOTAL DE ESTOQUES" e mais
-- nada voltaria a satisfazer com uma linha de rodapé só, o BURACO que esta
-- migration existe para fechar, achado 4 da revisão) — e resolver via o novo
-- localizador de secao, que casa as linhas de detalhe reais sem depender do
-- rótulo "estoque" estar na chave.
--
-- O QUE ISTO NÃO FECHA (dívida nomeada, não bloqueante — achado 4 da revisão,
-- registrado para quem for endurecer estas exigências depois):
--   • AGING_AP/AGING_AR só se satisfazem hoje pela linha RESIDUAL da fixture
--     ("Demais fornecedores (184 credores)", "Demais clientes (312
--     sacados)") — as demais chaves são nomes próprios de contraparte, sem a
--     palavra "fornecedor"/"cliente". Um aging que trouxesse só o top-N sem
--     linha de resto abriria pendência FALSA; um que trouxesse SÓ a linha de
--     resto SATISFAZ a exigência — o buraco oposto ao que a migration diz
--     fechar. Não corrigido aqui: exigiria uma forma de localizador que este
--     mecanismo (termo em chave/secao) não expressa — é candidato a esperar
--     mais dado real antes de desenhar, mesma doutrina da 0181 sobre "grupo
--     por controle comum sem holding".
--   • `aval` é substring de "avaliação"/"avaliado" depois de
--     `fn_normalizar_texto` (minúsculas, sem acento): `like '%aval%'` casaria
--     "Participações em outras sociedades - avaliadas ao custo", presente na
--     canastra num tipo de documento DIFERENTE de AVAIS_FIANCAS — inofensivo
--     hoje porque a exigência só é cobrada dentro de documentos do próprio
--     tipo AVAIS_FIANCAS (fn_exigencias_do_caso casa `c.tipo_taxonomia =
--     e.tipo_taxonomia`), mas o termo continua largo o bastante para colidir
--     se um documento de AVAIS_FIANCAS real tiver uma linha de avaliação de
--     participação societária. GARANTIAS, AVAIS_FIANCAS e DEBITOS_TRIB não
--     aparecem em nenhuma das duas fixtures do repositório (Vertentes nem
--     Canastra) — não há documento real contra o qual medir estes três hoje;
--     ficam com os localizadores originais, sem correção adicional.
-- =============================================================================

insert into taxonomia_linha_exigida
  (tipo_taxonomia, conceito, rotulo, checagem, origem, depende_de, descricao)
values
  ('AGING_AP', 'saldo_em_aberto_fornecedor', 'Saldo em aberto por fornecedor',
   'linha_por_termos', 'proposta',
   array['(proposta) nenhuma checagem lê AGING_AP hoje'],
   'REDUÇÃO da entrega: ela pede o saldo por fornecedor QUEBRADO por faixa de vencimento '
   '(0-30/31-60/61-90/>90 dias); esta tabela só consegue exigir "existe linha de saldo por '
   'fornecedor com valor" — a faixa etária fica de fora. Sem nem essa linha, o aging de contas '
   'a pagar do book sai vazio.'),
  ('AGING_AR', 'saldo_em_aberto_cliente', 'Saldo em aberto por cliente',
   'linha_por_termos', 'proposta',
   array['(proposta) nenhuma checagem lê AGING_AR hoje'],
   'REDUÇÃO da entrega: mesma lacuna do AGING_AP, do lado de contas a receber — ela pede a '
   'faixa de vencimento por cliente; aqui só "existe linha de saldo por cliente com valor". Sem '
   'nem essa linha, o aging de contas a receber do book sai vazio.'),
  ('EXTRATO_BANCARIO', 'saldo_em_conta', 'Saldo em conta corrente',
   'linha_por_termos', 'proposta',
   array['(proposta) nenhuma checagem lê EXTRATO_BANCARIO hoje'],
   'REDUÇÃO da entrega: ela pede o saldo por CONTA, por MÊS (entidade × conta × mês, 6-12 '
   'meses de histórico); aqui só "existe alguma linha de saldo com valor" — nem a conta nem o '
   'mês são distinguidos. Sem nem essa linha, a posição de caixa por banco do book sai vazia.'),
  ('GARANTIAS', 'valor_garantia', 'Valor da garantia',
   'linha_por_termos', 'proposta',
   array['(proposta) nenhuma checagem lê GARANTIAS hoje'],
   'REDUÇÃO da entrega: ela pede tipo de garantia (real/fidejussória), o bem dado em garantia e '
   'o beneficiário; aqui só "existe linha de garantia com valor". Sem nem essa linha, o mapa de '
   'garantias prestadas do book sai vazio.'),
  ('AVAIS_FIANCAS', 'valor_aval_fianca', 'Valor de aval/fiança',
   'linha_por_termos', 'proposta',
   array['(proposta) nenhuma checagem lê AVAIS_FIANCAS hoje'],
   'REDUÇÃO da entrega: ela pede o aval/fiança por SÓCIO (nome, PII) e o contrato garantido; '
   'aqui só "existe linha de aval ou fiança com valor". Sem nem essa linha, a exposição pessoal '
   'dos sócios não aparece em lugar nenhum do book.'),
  ('CONTINGENCIAS', 'valor_contingencia', 'Valor provisionado / valor da causa',
   'linha_por_termos', 'proposta',
   array['(proposta) nenhuma checagem lê CONTINGENCIAS hoje'],
   'REDUÇÃO da entrega: ela pede por PROCESSO (número, tribunal, probabilidade de perda, valor '
   'provisionado x valor da causa); aqui só "existe linha de contingência com valor". Sem nem '
   'essa linha, o passivo contingente do book sai vazio.'),
  ('DEBITOS_TRIB', 'valor_debito_tributario', 'Valor do débito tributário',
   'linha_por_termos', 'proposta',
   array['(proposta) nenhuma checagem lê DEBITOS_TRIB hoje'],
   'REDUÇÃO da entrega: ela pede por TRIBUTO e competência, com principal x multa x juros e '
   'situação (parcelado/em discussão); aqui só "existe linha de débito tributário com valor". '
   'Sem nem essa linha, o passivo tributário do book sai vazio.'),
  ('ESTOQUE', 'valor_estoque', 'Valor de estoque',
   'linha_por_termos', 'proposta',
   array['(proposta) nenhuma checagem lê ESTOQUE hoje'],
   'REDUÇÃO da entrega: ela pede por SKU/categoria, quantidade x valor unitário x valor total, '
   'com giro; aqui só "existe linha de estoque com valor". Sem nem essa linha, a posição de '
   'estoque do book sai vazia.'),
  ('HEADCOUNT', 'quantidade_headcount', 'Quantidade de headcount / folha',
   'linha_por_termos', 'proposta',
   array['(proposta) nenhuma checagem lê HEADCOUNT hoje'],
   'REDUÇÃO da entrega: ela pede por MÊS × ENTIDADE, quantidade e custo de folha (PII); aqui só '
   '"existe linha de headcount/funcionários com valor". Sem nem essa linha, o quadro de pessoal '
   'do book sai vazio.')
on conflict (tipo_taxonomia, conceito) do nothing;

-- Um termo por conceito, salvo os três com sinônimo plausível (AVAIS_FIANCAS,
-- DEBITOS_TRIB, HEADCOUNT): dois localizadores em cascata para o MESMO
-- conceito, não dois conceitos — a exigência satisfaz-se quando QUALQUER um
-- casa (padrão juros/encargos de MAPA_DIVIDA, 0113). `exclui ['total']` onde
-- o documento é tipicamente um demonstrativo ITEMIZADO (aging, garantia,
-- contingência, tributo, estoque): uma única linha de rodapé "Total" não
-- prova que o detalhe por contraparte/item existe. EXTRATO_BANCARIO e
-- AVAIS_FIANCAS não excluem 'total' — "saldo" e "aval"/"fiança" não colidem
-- com um rótulo de total genérico nesses dois tipos.
--
-- QUATRO conceitos (CONTINGENCIAS, HEADCOUNT, EXTRATO_BANCARIO, ESTOQUE)
-- ganham AINDA um localizador `contra='secao'` — ver "CORREÇÃO" no header
-- desta migration. Sem `exclui`: a secao de um documento real não é um rótulo
-- de rodapé isolado, é o agrupamento inteiro (várias linhas de detalhe
-- compartilham a mesma secao), então o risco de satisfazer só com uma linha
-- de total sozinha — a razão do `exclui ['total']` nos localizadores de
-- `chave` acima — não se aplica do mesmo jeito aqui.
insert into taxonomia_linha_localizador (exigencia_id, ordem, contra, termos_inclui, termos_exclui)
select e.id, x.ordem, x.contra, x.inclui, x.exclui
from taxonomia_linha_exigida e
join (values
  ('AGING_AP',        'saldo_em_aberto_fornecedor', 1, 'chave', array['fornecedor']::text[], array['total']::text[]),
  ('AGING_AR',         'saldo_em_aberto_cliente',    1, 'chave', array['cliente']::text[],    array['total']::text[]),
  ('EXTRATO_BANCARIO', 'saldo_em_conta',             1, 'chave', array['saldo']::text[],      '{}'::text[]),
  ('GARANTIAS',        'valor_garantia',             1, 'chave', array['garantia']::text[],   array['total']::text[]),
  ('AVAIS_FIANCAS',    'valor_aval_fianca',          1, 'chave', array['aval']::text[],       '{}'::text[]),
  ('AVAIS_FIANCAS',    'valor_aval_fianca',          2, 'chave', array['fianca']::text[],     '{}'::text[]),
  ('CONTINGENCIAS',    'valor_contingencia',         1, 'chave', array['contingencia']::text[], array['total']::text[]),
  ('DEBITOS_TRIB',     'valor_debito_tributario',    1, 'chave', array['tributo']::text[],    array['total']::text[]),
  ('DEBITOS_TRIB',     'valor_debito_tributario',    2, 'chave', array['imposto']::text[],    array['total']::text[]),
  ('ESTOQUE',          'valor_estoque',              1, 'chave', array['estoque']::text[],    array['total']::text[]),
  ('HEADCOUNT',        'quantidade_headcount',       1, 'chave', array['headcount']::text[],  '{}'::text[]),
  ('HEADCOUNT',        'quantidade_headcount',       2, 'chave', array['funcionario']::text[], '{}'::text[]),
  -- CORREÇÃO (revisão, ver o header): quatro conceitos em que o rótulo real
  -- carrega o termo na SEÇÃO, não na chave (fixture_book_canastra.sql). O
  -- `contra='secao'` já existe desde a 0113 — só não tinha sido usado aqui.
  ('CONTINGENCIAS',    'valor_contingencia',         3, 'secao', array['contingencia']::text[], '{}'::text[]),
  ('HEADCOUNT',        'quantidade_headcount',       3, 'secao', array['headcount']::text[],  '{}'::text[]),
  ('EXTRATO_BANCARIO', 'saldo_em_conta',             2, 'secao', array['saldo']::text[],      '{}'::text[]),
  ('ESTOQUE',          'valor_estoque',              2, 'secao', array['estoque']::text[],    '{}'::text[])
) x(tipo, conceito, ordem, contra, inclui, exclui)
  on x.tipo = e.tipo_taxonomia and x.conceito = e.conceito
where e.origem = 'proposta'
on conflict (exigencia_id, ordem) do nothing;

-- -----------------------------------------------------------------------------
-- O CATÁLOGO DA SONDA — mesma view isolante da 0166, pelo mesmo motivo: um
-- requisito de `seed` que contasse `taxonomia_linha_exigida` inteira passaria
-- num banco que nunca aplicou esta migration, porque as OUTRAS 12 exigências
-- (0113) já bastam para qualquer critério pequeno. A view isola EXATAMENTE as
-- nove linhas que este arquivo insere.
-- -----------------------------------------------------------------------------
create or replace view instalacao_sonda_tipos_mudos_f21 as
  select e.id, e.tipo_taxonomia
    from taxonomia_linha_exigida e
   where e.origem = 'proposta'
     and e.tipo_taxonomia in (
       'AGING_AP', 'AGING_AR', 'EXTRATO_BANCARIO', 'GARANTIAS', 'AVAIS_FIANCAS',
       'CONTINGENCIAS', 'DEBITOS_TRIB', 'ESTOQUE', 'HEADCOUNT');

comment on view instalacao_sonda_tipos_mudos_f21 is
  'Sonda da 0185: as nove exigências de conteúdo (F2.1) para tipos que antes não tinham '
  'NENHUMA linha em taxonomia_linha_exigida. Nove é o total — zero ou menos significa que a '
  '0185 não foi aplicada e estes nove tipos continuam passando pela completude sem que ninguém '
  'confira o conteúdo.';

grant select on instalacao_sonda_tipos_mudos_f21 to authenticated;

insert into instalacao_requisito
  (chave, migration, tipo, objeto, marcador, criterio_seed, porque, severidade, ordem) values
  ('tipos_mudos_f21_tem_exigencia', '0185', 'seed', 'instalacao_sonda_tipos_mudos_f21', null, 9,
   'AGING_AP, AGING_AR, EXTRATO_BANCARIO, GARANTIAS, AVAIS_FIANCAS, CONTINGENCIAS, '
   'DEBITOS_TRIB, ESTOQUE e HEADCOUNT não tinham NENHUMA linha em taxonomia_linha_exigida — um '
   'documento desses tipos "passava" a completude com qualquer conteúdo, inclusive uma única '
   'linha de rodapé, e o book saía vazio nessa parte sem pendência nenhuma nomeando a ausência.',
   'importante', 770)
on conflict (chave) do update set
  migration = excluded.migration, tipo = excluded.tipo, objeto = excluded.objeto,
  marcador = excluded.marcador, criterio_seed = excluded.criterio_seed,
  porque = excluded.porque, severidade = excluded.severidade, ordem = excluded.ordem;

update instalacao_cobertura
   set ate_migration = '0185', revisado_em = current_date,
       observacao = 'A 0185 é seed puro (nove exigências origem=''proposta'' + localizadores, '
                    'fatia F2.1 do roadmap — cobertura de tipos). O requisito aponta para a view '
                    'instalacao_sonda_tipos_mudos_f21, que isola as NOVE linhas que esta '
                    'migration insere; apontar para a tabela inteira contaria as 12 exigências '
                    'da 0113 e o requisito nasceria vazio. Nenhuma função foi tocada — o passo '
                    '(2b) de fn_recomputar_completude (0113) já lê qualquer exigência ativa via '
                    'fn_exigencias_do_caso, então estas nove entram em produção sozinhas.';

-- -----------------------------------------------------------------------------
-- VERIFICAÇÃO EMBUTIDA (padrão 0113/0166): sem tocar em pendência, cobertura
-- funcional é a de Supabase/test/linha_exigida_tipos_variaveis.test.sql.
-- -----------------------------------------------------------------------------
do $$
declare
  v_n int;
begin
  select count(*) into v_n from taxonomia_linha_exigida
   where origem = 'proposta'
     and tipo_taxonomia in (
       'AGING_AP', 'AGING_AR', 'EXTRATO_BANCARIO', 'GARANTIAS', 'AVAIS_FIANCAS',
       'CONTINGENCIAS', 'DEBITOS_TRIB', 'ESTOQUE', 'HEADCOUNT');
  if v_n <> 9 then
    raise exception '0185: esperava 9 exigências novas (uma por tipo), achou %', v_n;
  end if;

  select count(*) into v_n from taxonomia_linha_exigida e
   where e.tipo_taxonomia in (
       'AGING_AP', 'AGING_AR', 'EXTRATO_BANCARIO', 'GARANTIAS', 'AVAIS_FIANCAS',
       'CONTINGENCIAS', 'DEBITOS_TRIB', 'ESTOQUE', 'HEADCOUNT')
     and e.checagem = 'linha_por_termos'
     and not exists (select 1 from taxonomia_linha_localizador l where l.exigencia_id = e.id);
  if v_n <> 0 then
    raise exception '0185: % exigência(s) por termos SEM localizador — não se procura, não se satisfaz nunca', v_n;
  end if;

  select count(*) into v_n from taxonomia_linha_exigida
   where tipo_taxonomia in (
       'AGING_AP', 'AGING_AR', 'EXTRATO_BANCARIO', 'GARANTIAS', 'AVAIS_FIANCAS',
       'CONTINGENCIAS', 'DEBITOS_TRIB', 'ESTOQUE', 'HEADCOUNT')
     and (severidade is not null or sobrepujavel is not null);
  if v_n <> 0 then
    raise exception '0185: % exigência(s) com política definida no seed — severidade/sobrepujavel são decisão do dono, nascem NULL', v_n;
  end if;

  raise notice '0185 OK — 9 exigências propostas (AGING_AP/AGING_AR/EXTRATO_BANCARIO/GARANTIAS/AVAIS_FIANCAS/CONTINGENCIAS/DEBITOS_TRIB/ESTOQUE/HEADCOUNT), todas com localizador, política toda NULL (do dono)';
end $$;
