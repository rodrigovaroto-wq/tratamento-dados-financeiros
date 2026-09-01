-- =============================================================================
-- Migration 0126 — O golden set passa a existir como DADO, e a regra de ouro do
--                  Arquitetura do Sistema/1 Visão e Doutrina/01 passa a ser EXECUTADA
--
-- O DEFEITO, E ELE É O MESMO DE SEMPRE NESTA CASA: A GUARDA PROMETIDA NÃO EXISTE.
--
-- `Arquitetura do Sistema/1 Visão e Doutrina/01` fecha com uma "regra de ouro", em negrito e sem ressalva:
--
--     "Nada de subir o dial de autonomia de um estágio interpretativo sem
--      golden set e concordância medida."
--
-- `fn_mudar_dial` (0041) confere UMA coisa: o teto. Pedir N2 num estágio de teto
-- N2 é aceito com um `p_motivo` em texto livre, e nada olha para medição alguma —
-- não existe onde olhar. A regra de ouro está escrita na doutrina, repetida no
-- cabeçalho de duas migrations, impressa na tela de autonomia em letras âmbar, e
-- não é código em lugar nenhum.
--
-- Quem fez isso primeiro foi a própria 0041, e ela DECLARA que fez:
--
--     "A ressalva que a 0019 registrou continua verdadeira: este N2 é decisão de
--      produto do dono, NÃO autonomia medida. Arquitetura do Sistema/1 Visão e Doutrina/01 exige concordância contra
--      golden set para subir dial de estágio interpretativo, e o golden set
--      físico ainda não existe."
--
-- É a mesma forma dos defeitos que a 0123 achou: `v_lados_bp` atribuída e nunca
-- lida, "a guarda que o comentário da 0117 prometia não existia". A diferença é
-- que aqui a promessa é do documento fundador do projeto.
--
-- E O PROTOCOLO ESTÁ PRONTO DESDE 14/07. O `Arquitetura do Sistema/2 Especificação/f0/06` foi fechado como v1 pelo dono:
-- dimensionamento (~20–30 documentos por tipo core), o que se rotula, uma tabela
-- de CINCO métricas, protocolo de rotulagem com dois rotuladores independentes, e
-- o laço de calibração desenhado. No banco não existe uma linha disso: `grep -ril
-- golden` devolve documentação, o comentário de um script e prosa de migration.
-- O protocolo virou v1 e ficou esperando por um lugar onde morar.
--
-- O QUE ESTA MIGRATION FAZ, E O QUE ELA DELIBERADAMENTE NÃO FAZ.
--
-- Faz: o lugar onde o ground truth mora (três tabelas), as cinco métricas do
-- `Arquitetura do Sistema/2 Especificação/f0/06` como função, a tabela de teto do `Arquitetura do Sistema/1 Visão e Doutrina/01` deixando de ser prosa e
-- virando coluna, e `fn_mudar_dial` RECUSANDO subida a N2/N3 de estágio
-- interpretativo sem concordância medida.
--
-- NÃO faz: o golden set físico. Esse é rotulagem de documento real de cliente,
-- com LGPD, e o `Arquitetura do Sistema/2 Especificação/f0/06` já diz por que não se monta em documentação — "é tarefa
-- de execução". Continua sendo do dono. O que muda é que agora existe onde
-- colocar, o que mede, e um portão que cobra.
--
-- AS TRÊS DECISÕES QUE VALE LER ANTES DO CÓDIGO.
--
-- 1. O PORTÃO MORDE NA SUBIDA A N2/N3, NÃO EM TODA SUBIDA. A leitura literal da
--    regra de ouro cobraria golden set para ir de N0 a N1 — e N1 é "sugestão,
--    humano confirma todo item". Nada é automatizado em N1; o fechamento #5
--    (anti-ancoragem) continua inteiro, porque nenhum número vira fato sem aceite
--    explícito. O risco que a regra de ouro guarda é automatizar erro em escala,
--    e a escala começa no auto-clear, que é N2. Cobrar medição para exibir uma
--    sugestão travaria o caminho que a doutrina manda percorrer — os estágios
--    NASCEM baixos justamente para subir. Descer, por definição, nunca pede nada.
--
-- 2. O GOLDEN SINTÉTICO NÃO SOBE DIAL, E ISSO É COLUNA. `golden_documento.origem`
--    é 'real' ou 'sintetico', e as métricas contam 'real' por default. Sem isso o
--    portão seria teatro: os dois books têm GABARITO.json, rotulá-los é de graça,
--    a concordância sairia ~100% por construção e o dial subiria com a medição do
--    INSTRUMENTO. O cabeçalho do `medir-auto-aceite.mts` já avisa disso em prosa
--    há sessões ("está medindo o próprio instrumento, NÃO a autonomia do
--    modelo"); aqui o aviso vira guarda.
--
-- 3. A DECISÃO DECLARADA CONTINUA POSSÍVEL — MAS PASSA A SER CONTÁVEL. Recusar
--    tudo o que não é medido quebraria a reaplicação da 0041 num banco montado do
--    zero e, pior, tiraria do dono uma decisão que é dele. Então existe
--    `p_sem_medicao_porque`: um MOTIVO, não um booleano. Com ele a subida
--    acontece, a trilha grava `mudanca_dial_sem_medicao`, e `base_do_nivel` fica
--    'declarada' — de modo que "N2 medido" e "N2 decidido" deixam de ser
--    indistinguíveis para quem lê o estado do sistema. Era isso que a tela de
--    autonomia adivinhava por `estagio.startsWith("extracao")`.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- ESTRATO e ORIGEM.
--
-- O estrato é a exigência de amostragem do `Arquitetura do Sistema/2 Especificação/f0/06`: "incluir digital, PDF nativo,
-- escaneado e foto na proporção real — senão a métrica mente sobre o pior caso".
-- Uma concordância de 99% medida só em PDF nativo não autoriza autonomia sobre o
-- escaneado que chega do cliente, e sem a coluna ninguém consegue nem perguntar.
-- -----------------------------------------------------------------------------
do $$ begin
  create type golden_estrato as enum ('digital', 'pdf_nativo', 'escaneado', 'foto');
exception when duplicate_object then null; end $$;

do $$ begin
  create type golden_origem as enum ('real', 'sintetico');
exception when duplicate_object then null; end $$;

comment on type golden_estrato is
  'Qualidade de captura do documento (Arquitetura do Sistema/2 Especificação/f0/06, amostragem estratificada). A métrica agregada sobre '
  'estratos misturados esconde o pior caso, que é justamente o que decide se o dial pode subir.';

comment on type golden_origem is
  'real = documento de cliente. sintetico = book gerado (Dados de Teste/). As métricas que governam o '
  'dial contam SÓ real: rotular um book cujo GABARITO.json já se conhece mede o instrumento, não o '
  'modelo — é a ressalva que o cabeçalho do medir-auto-aceite.mts carrega desde que existe.';

-- -----------------------------------------------------------------------------
-- golden_rodada — a rodada de calibração, e ela CONGELA.
--
-- `Arquitetura do Sistema/2 Especificação/f0/06`: "golden set congelado por rodada de calibração; ampliado, não editado
-- retroativamente". Congelar não é enfeite de processo: uma medição que autoriza
-- subir o dial precisa ser reproduzível depois, e rótulo editado em cima do
-- conjunto já medido apaga a evidência da decisão que ele mesmo justificou.
-- Ampliar é rodada NOVA — e é assim que o `Arquitetura do Sistema/2 Especificação/f0/06` manda o conjunto crescer.
-- -----------------------------------------------------------------------------
create table if not exists golden_rodada (
  id                uuid primary key default gen_random_uuid(),
  nome              text not null unique,
  taxonomia_versao  int  not null,
  criada_em         timestamptz not null default now(),
  criada_por        text,
  congelada_em      timestamptz,
  congelada_por     text,
  nota              text
);

comment on table golden_rodada is
  'Rodada de calibração do golden set (Arquitetura do Sistema/2 Especificação/f0/06). Congelada = não aceita mais rótulo; ampliar é rodada '
  'nova, nunca edição da anterior — senão a evidência que autorizou uma subida de dial muda depois '
  'da subida. taxonomia_versao amarra os rótulos à versão da taxonomia em que foram feitos, porque '
  'tipo correto em v1 pode não ser tipo correto em v2.';

-- -----------------------------------------------------------------------------
-- golden_documento — o que a rodada CONTÉM.
--
-- Aponta para um `documento` que já passou pelo pipeline, e essa é a decisão de
-- desenho que evita uma tabela inteira: a resposta da MÁQUINA (tipo, entidade,
-- período, e as linhas de `campo_extraido`) já está no banco. Não há "tabela de
-- predição" — a predição é o estado de produção, e medir contra ela é medir o
-- que o sistema de fato faz, não uma cópia dele.
--
-- Estrato e origem moram AQUI e não no rótulo: são propriedades do documento, não
-- julgamento de rotulador. Dois rotuladores podem discordar do tipo; nenhum dos
-- dois decide se o arquivo é escaneado.
-- -----------------------------------------------------------------------------
create table if not exists golden_documento (
  rodada_id     uuid not null references golden_rodada(id) on delete cascade,
  documento_id  uuid not null references documento(id) on delete cascade,
  estrato       golden_estrato not null,
  origem        golden_origem  not null,
  incluido_em   timestamptz not null default now(),
  incluido_por  text,
  nota          text,
  primary key (rodada_id, documento_id)
);

create index if not exists idx_golden_documento_rodada on golden_documento (rodada_id, origem);

comment on table golden_documento is
  'Quais documentos a rodada cobre. A resposta da MÁQUINA para cada um já está em documento/'
  'campo_extraido — não existe tabela de predição de propósito: medir contra o estado de produção é '
  'medir o sistema, e não uma cópia dele que pode divergir.';

-- -----------------------------------------------------------------------------
-- golden_rotulo — o JULGAMENTO humano, um por rotulador.
--
-- `Arquitetura do Sistema/2 Especificação/f0/06`: "dois rotuladores independentes nos casos ambíguos; medir concordância
-- inter-avaliador (se humanos discordam, a máquina não tem como acertar — mantém
-- revisão)". A chave inclui o rotulador exatamente para permitir os dois, e o que
-- eles discordam é EXCLUÍDO do placar da máquina em vez de contado como erro
-- dela. Contar como erro seria cobrar da máquina uma resposta que não existe.
-- -----------------------------------------------------------------------------
create table if not exists golden_rotulo (
  id                       uuid primary key default gen_random_uuid(),
  rodada_id                uuid not null,
  documento_id             uuid not null,
  rotulador                text not null,
  tipo_correto             text,
  entidade_correta         text,
  periodo_correto          text,
  assinado_correto         boolean,
  legibilidade             legibilidade,
  item_checklist_correto   text,
  rotulado_em              timestamptz not null default now(),
  nota                     text,
  foreign key (rodada_id, documento_id)
    references golden_documento (rodada_id, documento_id) on delete cascade,
  unique (rodada_id, documento_id, rotulador)
);

comment on table golden_rotulo is
  'O ground truth por rotulador (Arquitetura do Sistema/2 Especificação/f0/06, "o que é rotulado"). Campo null = "este rotulador não '
  'julgou isto", que NÃO é o mesmo que discordar: entra como item não medido, nunca como acerto.';

comment on column golden_rotulo.entidade_correta is
  'Razão social como o humano leu NO documento. A comparação usa fn_mesma_entidade (0030), então '
  'duas grafias da mesma companhia não contam como erro da máquina nem como discordância entre '
  'rotuladores — foi exatamente esse par de grafias que a 0121 mostrou duplicando empresa.';

-- -----------------------------------------------------------------------------
-- golden_campo — os `campos_chave` do `Arquitetura do Sistema/2 Especificação/f0/06`, com TOLERÂNCIA declarada.
--
-- A métrica do protocolo é "erro de extração de campos financeiros (exato /
-- dentro de tolerância)", então a tolerância é dado do rótulo e não constante de
-- código: o book é em milhares e o arredondamento do PDF é legítimo (o
-- `medir-auto-aceite.mts` fixa 1 no código por isso), mas num documento em reais
-- a mesma tolerância de 1 é ruído e num em milhões é cegueira.
-- -----------------------------------------------------------------------------
create table if not exists golden_campo (
  id                       uuid primary key default gen_random_uuid(),
  rodada_id                uuid not null,
  documento_id             uuid not null,
  rotulador                text not null,
  chave                    text not null,
  periodo_coluna           text,
  entidade_coluna          text,
  valor_correto            numeric,
  classe_contabil_correta  text,
  tolerancia               numeric not null default 0,
  rotulado_em              timestamptz not null default now(),
  foreign key (rodada_id, documento_id)
    references golden_documento (rodada_id, documento_id) on delete cascade
);

-- Unicidade com coluna anulável: `unique (…, periodo_coluna, …)` deixaria passar
-- duas linhas com period null, porque null nunca é igual a null. O mesmo motivo
-- que faz o `fn_registrar_reconciliacao` (0023) comparar período com coalesce.
create unique index if not exists idx_golden_campo_unico on golden_campo
  (rodada_id, documento_id, rotulador, chave,
   coalesce(periodo_coluna, ''), coalesce(entidade_coluna, ''));

comment on table golden_campo is
  'Os campos_chave do Arquitetura do Sistema/2 Especificação/f0/06: que valor o humano leu no documento, para a linha que a extração '
  'devolve. tolerancia é por LINHA porque escala é por documento — 1 unidade é arredondamento '
  'legítimo em milhares e é cegueira em milhões.';

comment on column golden_campo.classe_contabil_correta is
  'A classe contábil que o humano atribuiu (recorrente/EBITDA…). É o ground truth da quinta linha '
  'da tabela de métricas do Arquitetura do Sistema/2 Especificação/f0/06 — e o estágio classificacao_contabil tem teto N1 em Arquitetura do Sistema/1 Visão e Doutrina/01, '
  'então este número serve para MANTER o teto honesto, nunca para soltá-lo.';

-- -----------------------------------------------------------------------------
-- APPEND-ONLY, E LGPD.
--
-- O par de políticas é o do `evento_auditoria` (0003) e o do `caso_pergunta`
-- (0120): uma de SELECT, uma de INSERT, e NENHUMA de update ou delete — sem
-- política para um comando, o RLS nega aquele comando. É o que faz "append-only"
-- ser regra do banco em vez de adjetivo no comentário. A 0120 registra a medição
-- que prova a diferença: com `for all to authenticated`, um
-- `set role authenticated; delete` apagou a linha.
--
-- Aqui o motivo é mais forte que no `caso_pergunta`: o rótulo é a EVIDÊNCIA que
-- autoriza subir autonomia. Rótulo editável depois da medição é uma decisão de
-- dial cuja justificativa pode ser reescrita a posteriori.
--
-- LGPD: `golden_documento` aponta para documento real de cliente, e o `Arquitetura do Sistema/2 Especificação/f0/06`
-- exige "armazenar com controle de acesso". A F1 é ferramenta interna de um time
-- (0003), então o escopo é o mesmo das outras tabelas — usuário autenticado. O
-- que esta migration acrescenta é que o conjunto agora tem NOME próprio, o que
-- torna possível restringi-lo depois sem tocar em mais nada.
-- -----------------------------------------------------------------------------
alter table golden_rodada     enable row level security;
alter table golden_documento  enable row level security;
alter table golden_rotulo     enable row level security;
alter table golden_campo      enable row level security;

drop policy if exists golden_rodada_read    on golden_rodada;
drop policy if exists golden_rodada_insert  on golden_rodada;
drop policy if exists golden_rodada_update  on golden_rodada;
create policy golden_rodada_read   on golden_rodada for select to authenticated using (true);
create policy golden_rodada_insert on golden_rodada for insert to authenticated with check (true);
-- A rodada é a ÚNICA das quatro que aceita update, e só para poder ser congelada.
-- Um `using (congelada_em is null)` faria o congelamento ser irreversível pelo
-- próprio comando que o aplica — congelar duas vezes é inofensivo, descongelar é
-- que não pode, e é o gatilho abaixo que trata disso.
create policy golden_rodada_update on golden_rodada for update to authenticated using (true);

drop policy if exists golden_documento_read   on golden_documento;
drop policy if exists golden_documento_insert on golden_documento;
create policy golden_documento_read   on golden_documento for select to authenticated using (true);
create policy golden_documento_insert on golden_documento for insert to authenticated with check (true);

drop policy if exists golden_rotulo_read   on golden_rotulo;
drop policy if exists golden_rotulo_insert on golden_rotulo;
create policy golden_rotulo_read   on golden_rotulo for select to authenticated using (true);
create policy golden_rotulo_insert on golden_rotulo for insert to authenticated with check (true);

drop policy if exists golden_campo_read   on golden_campo;
drop policy if exists golden_campo_insert on golden_campo;
create policy golden_campo_read   on golden_campo for select to authenticated using (true);
create policy golden_campo_insert on golden_campo for insert to authenticated with check (true);

-- -----------------------------------------------------------------------------
-- A RODADA CONGELADA NÃO ACEITA MAIS RÓTULO — por gatilho, não por convenção.
--
-- Sem isto, "congelada" seria uma data numa coluna que ninguém consulta antes de
-- inserir, e o `Arquitetura do Sistema/2 Especificação/f0/06` teria a mesma sorte da regra de ouro: doutrina correta,
-- zero execução. O gatilho vale para as três tabelas de conteúdo da rodada.
--
-- E descongelar é recusado no mesmo lugar: uma rodada que volta a aceitar rótulo
-- depois de ter autorizado uma subida de dial reabre exatamente o furo que
-- congelar fecha.
-- -----------------------------------------------------------------------------
create or replace function fn_golden_rodada_congelada() returns trigger
language plpgsql as $$
declare
  v_rodada uuid := new.rodada_id;
  v_congelada timestamptz;
  v_nome text;
begin
  select gr.congelada_em, gr.nome into v_congelada, v_nome
  from golden_rodada gr where gr.id = v_rodada;
  if v_congelada is not null then
    raise exception 'A rodada de golden set "%" foi congelada em % e não aceita mais rótulo. '
                    'O Arquitetura do Sistema/2 Especificação/f0/06 manda AMPLIAR criando rodada nova, não editando a medida: a rodada '
                    'congelada é a evidência de uma decisão de dial já tomada.',
                    coalesce(v_nome, v_rodada::text), v_congelada
      using errcode = 'check_violation';
  end if;
  return new;
end;
$$;

drop trigger if exists trg_golden_documento_congelada on golden_documento;
create trigger trg_golden_documento_congelada before insert or update on golden_documento
  for each row execute function fn_golden_rodada_congelada();

drop trigger if exists trg_golden_rotulo_congelada on golden_rotulo;
create trigger trg_golden_rotulo_congelada before insert or update on golden_rotulo
  for each row execute function fn_golden_rodada_congelada();

drop trigger if exists trg_golden_campo_congelada on golden_campo;
create trigger trg_golden_campo_congelada before insert or update on golden_campo
  for each row execute function fn_golden_rodada_congelada();

-- A rodada congelada é IMUTÁVEL, e não só quanto ao congelamento.
--
-- A política de UPDATE existe porque congelar é um update — e é a única razão. Ela
-- abre, de carona, duas coisas que precisam ser fechadas aqui:
--
--   • DESCONGELAR. Rodada que volta a aceitar rótulo depois de ter autorizado uma
--     subida de dial reabre exatamente o furo que congelar fecha.
--   • RENOMEAR, ou trocar a versão da taxonomia. O `nome` da rodada é citado na
--     trilha de auditoria e dentro de `estagio_autonomia.medicao_resumo`; renomear
--     depois faz o registro apontar para um nome que não significa mais o mesmo.
--     E `taxonomia_versao` é o que amarra o rótulo à taxonomia em que foi feito —
--     mudá-lo reescreve a premissa da medição sem tocar em um rótulo.
create or replace function fn_golden_rodada_congelada_imutavel() returns trigger
language plpgsql as $$
begin
  if old.congelada_em is null then
    return new;   -- rodada aberta: nome, nota e versão ainda são editáveis
  end if;
  if new.congelada_em is null then
    raise exception 'A rodada "%" já foi congelada em % e não descongela. Ampliar o golden set é '
                    'rodada NOVA (Arquitetura do Sistema/2 Especificação/f0/06); descongelar permitiria reescrever a evidência depois de '
                    'ela ter autorizado uma subida de dial.', old.nome, old.congelada_em
      using errcode = 'check_violation';
  end if;
  if new.nome <> old.nome or new.taxonomia_versao <> old.taxonomia_versao then
    raise exception 'A rodada "%" está congelada: nome e taxonomia_versao não mudam mais. O nome é '
                    'citado na trilha e em estagio_autonomia.medicao_resumo, e a versão da '
                    'taxonomia é a premissa dos rótulos — mudar qualquer um reescreve a evidência '
                    'de uma decisão de dial sem tocar em um rótulo.', old.nome
      using errcode = 'check_violation';
  end if;
  return new;
end;
$$;

drop trigger if exists trg_golden_rodada_nao_descongela on golden_rodada;
drop trigger if exists trg_golden_rodada_imutavel on golden_rodada;
create trigger trg_golden_rodada_imutavel before update on golden_rodada
  for each row execute function fn_golden_rodada_congelada_imutavel();

-- -----------------------------------------------------------------------------
-- golden_criterio — QUANTO é "concordância alta e estável", por estágio.
--
-- ESTE NÚMERO É DECISÃO, NÃO MEDIÇÃO, e o cabeçalho declara isso porque a casa já
-- se queimou com número de aparência técnica que era palpite (o `LIMIAR_COBERTURA`
-- de 0,85, o `CUSTO_POR_MB_USD`). O `Arquitetura do Sistema/2 Especificação/f0/06` dimensiona o N — "~20–30 documentos
-- rotulados por tipo core" — e NÃO fixa limiar de concordância; ele diz
-- "concordância alta e estável" e deixa a decisão em aberto.
--
-- O default entra em 0,95 por um motivo verificável, não por gosto: é o
-- `limiar_auto_clear` que a 0019 fixou e a 0041 tornou dado. Aceitar dial em N2
-- com concordância medida ABAIXO de 0,95 seria auto-aceitar linha a uma confiança
-- que a própria medição não alcança — o sistema apostaria mais alto do que sabe.
--
-- E é DADO, na mesma lógica da 0041: o dono ajusta com um update, sem migration e
-- sem deploy.
-- -----------------------------------------------------------------------------
create table if not exists golden_criterio (
  estagio               text primary key references estagio_autonomia(estagio) on delete cascade,
  n_minimo              int     not null default 20,
  concordancia_minima   numeric not null default 0.95,
  metrica               text    not null,
  nota                  text
);

comment on table golden_criterio is
  'O que "concordância alta e estável" (Arquitetura do Sistema/2 Especificação/f0/06) significa em número, por estágio. n_minimo vem do '
  'Arquitetura do Sistema/2 Especificação/f0/06 (~20-30 por tipo core); concordancia_minima é DECISÃO e entra em 0.95 porque é o '
  'limiar_auto_clear em vigor desde a 0019 — auto-aceitar a 0.95 com medição abaixo de 0.95 seria '
  'apostar acima do que se sabe. Dado, não constante: muda por update.';

comment on column golden_criterio.metrica is
  'Qual das cinco métricas do Arquitetura do Sistema/2 Especificação/f0/06 governa este estágio. É o mapa que fn_golden_suficiente segue, '
  'e existe como dado para que acrescentar estágio não exija reescrever aquela função.';

insert into golden_criterio (estagio, metrica, nota) values
  ('classificacao_doc_checklist', 'f1_classificacao',
   'F1 da classificação doc->tipo (Arquitetura do Sistema/2 Especificação/f0/06, linha 1 da tabela de métricas).'),
  ('extracao_identificadores', 'acuracia_identificadores',
   'Acurácia de tipo/período/entidade (Arquitetura do Sistema/2 Especificação/f0/06, linha 2). A entidade casa por fn_mesma_entidade: '
   'duas grafias da mesma companhia não são erro.'),
  ('extracao_linhas_financeiras', 'acerto_campos',
   'Fração das linhas conferíveis cujo valor cai dentro da tolerância do rótulo (Arquitetura do Sistema/2 Especificação/f0/06, linha 3). '
   'Vem junto a COBERTURA, que é a métrica que o medir-auto-aceite.mts aponta como a que decide.'),
  ('reconciliacao_classe_a', 'nao_falso_positivo_classe_a',
   'Arquitetura do Sistema/2 Especificação/f0/06 linha 5 pede a TAXA DE FALSO-POSITIVO; aqui ela entra invertida (1 - taxa) para que '
   '"mais alto e melhor" valha para todos os critérios e a comparação seja uma só. O rótulo dela '
   'NÃO precisa de rotulagem nova: estado "rejeitada" (0106) é, textualmente, "a pendência não '
   'procede (falso positivo do motor)".')
on conflict (estagio) do nothing;

-- -----------------------------------------------------------------------------
-- A TABELA DE TETO DO Arquitetura do Sistema/1 Visão e Doutrina/01 DEIXA DE SER PROSA.
--
-- `Arquitetura do Sistema/1 Visão e Doutrina/01` tem uma tabela chamada "Regra de teto por natureza do estágio
-- (inegociável)" cuja primeira coluna é justamente a natureza: "Determinístico
-- objetivo" contra os interpretativos. O `teto` dela virou coluna na 0001; a
-- NATUREZA não, e é ela que decide se a regra de ouro se aplica.
--
-- Sem esta coluna, o portão precisaria de uma lista de nomes de estágio dentro de
-- uma função — que é exatamente a forma de defeito que a 0041 corrigiu no
-- limiar (0.95 dentro do corpo de `fn_registrar_campos_extraidos`) e que a tela
-- de autonomia ainda carrega em `estagio.startsWith("extracao")`.
--
-- `validacao_formal` e `completude_portao1` são os dois determinísticos: nascem em
-- N2 na semeadura da 0002 justamente porque aritmética e integridade de arquivo
-- não precisam de concordância humana para serem confiadas. Cobrar golden set
-- deles seria pedir rotulador para conferir se um zip abre.
-- -----------------------------------------------------------------------------
alter table estagio_autonomia
  add column if not exists natureza text not null default 'interpretativo';

alter table estagio_autonomia
  drop constraint if exists estagio_autonomia_natureza_check;
alter table estagio_autonomia
  add constraint estagio_autonomia_natureza_check
  check (natureza in ('deterministico', 'interpretativo'));

comment on column estagio_autonomia.natureza is
  'Arquitetura do Sistema/1 Visão e Doutrina/01, "regra de teto por natureza do estágio": deterministico = aritmética/integridade, cuja '
  'confiança não vem de concordância humana; interpretativo = tudo o que a regra de ouro governa. '
  'Default interpretativo porque, em dúvida, a regra APLICA — estágio novo nasce cobrado.';

update estagio_autonomia set natureza = 'deterministico'
  where estagio in ('validacao_formal', 'completude_portao1');

-- -----------------------------------------------------------------------------
-- SOBRE O QUE O NÍVEL DE HOJE SE APOIA.
--
-- Este é o campo que a tela de autonomia estava adivinhando. Hoje ela decide o
-- aviso "Autonomia declarada, não medida" por `d.estagio.startsWith("extracao")`
-- — heurística de NOME de estágio, que erra nos dois sentidos: um estágio de
-- extração que venha a ter medição continua recebendo o aviso, e um estágio de
-- outro nome que suba sem medição não recebe nenhum.
--
--   nao_se_aplica : N0/N1 — não há autonomia para justificar, ou é determinístico
--   declarada     : N2/N3 por decisão, sem medição (o caso da 0019/0041)
--   medida        : N2/N3 com concordância medida contra uma rodada de golden set
-- -----------------------------------------------------------------------------
alter table estagio_autonomia
  add column if not exists base_do_nivel text not null default 'nao_se_aplica';

alter table estagio_autonomia
  drop constraint if exists estagio_autonomia_base_check;
alter table estagio_autonomia
  add constraint estagio_autonomia_base_check
  check (base_do_nivel in ('nao_se_aplica', 'declarada', 'medida'));

alter table estagio_autonomia
  add column if not exists medicao_rodada_id uuid references golden_rodada(id);
alter table estagio_autonomia
  add column if not exists medicao_em timestamptz;
alter table estagio_autonomia
  add column if not exists medicao_resumo jsonb;

comment on column estagio_autonomia.base_do_nivel is
  'Em que o nível de HOJE se apoia: nao_se_aplica (N0/N1, ou determinístico), declarada (N2/N3 por '
  'decisão do dono, sem medição — o caso da 0019/0041) ou medida (N2/N3 contra rodada de golden '
  'set). Existe porque "N2 medido" e "N2 decidido" eram indistinguíveis para quem lê o estado do '
  'sistema, e a tela adivinhava por prefixo do nome do estágio.';

comment on column estagio_autonomia.medicao_resumo is
  'A medição que autorizou o nível, congelada no momento da subida. Guardar o resultado (e não só o '
  'ponteiro para a rodada) é o que permite responder "com que número isto subiu?" mesmo depois de o '
  'golden set crescer em rodadas seguintes.';

-- =============================================================================
-- AS CINCO MÉTRICAS DO Arquitetura do Sistema/2 Especificação/f0/06
-- =============================================================================

-- -----------------------------------------------------------------------------
-- fn_golden_consenso — a base de todas as outras, e a regra que ela encarna é a
-- frase do `Arquitetura do Sistema/2 Especificação/f0/06`: "se humanos discordam, a máquina não tem como acertar".
--
-- Onde os rotuladores discordam, o item NÃO entra no placar da máquina — nem como
-- acerto nem como erro. Contá-lo como erro cobraria dela uma resposta que não
-- existe; contá-lo como acerto premiaria adivinhação. Ele sai da conta e é
-- contado à parte, que é o que mantém o número honesto e visível.
--
-- O consenso é POR CAMPO, não por documento: dois rotuladores podem concordar no
-- tipo e discordar da legibilidade, e derrubar o documento inteiro por causa da
-- segunda jogaria fora a evidência boa sobre a primeira.
--
-- `null` não é discordância — é "este rotulador não julgou isto". Entra como não
-- medido, nunca como acerto. Um campo em que UM dos dois se calou não tem
-- consenso de dois, e é assim que ele é contado.
-- -----------------------------------------------------------------------------
create or replace function fn_golden_consenso(p_rodada uuid)
returns table (
  documento_id            uuid,
  estrato                 golden_estrato,
  origem                  golden_origem,
  n_rotuladores           int,
  tipo_correto            text,
  tipo_consenso           boolean,
  entidade_correta        text,
  entidade_consenso       boolean,
  periodo_correto         text,
  periodo_consenso        boolean,
  assinado_correto        boolean,
  assinado_consenso       boolean,
  legibilidade_correta    legibilidade,
  legibilidade_consenso   boolean,
  item_checklist_correto  text,
  item_consenso           boolean
)
language sql
stable
as $$
  with base as (
    -- Colunas nomeadas, não `gr.*`: golden_rotulo TAMBÉM tem documento_id, e o
    -- `*` faria a CTE devolver duas colunas com esse nome — o `group by
    -- b.documento_id` sai como "column reference is ambiguous".
    select gd.documento_id, gd.estrato, gd.origem,
           gr.rotulador, gr.tipo_correto, gr.entidade_correta, gr.periodo_correto,
           gr.assinado_correto, gr.legibilidade, gr.item_checklist_correto,
           -- O primeiro rotulador (ordem estável por nome) é a referência da
           -- comparação de entidade: fn_mesma_entidade é par a par, e comparar
           -- todos contra um só é o que a torna agregável.
           first_value(gr.entidade_correta) over (
             partition by gd.documento_id order by gr.rotulador
           ) as entidade_ref
    from golden_documento gd
    join golden_rotulo gr
      on gr.rodada_id = gd.rodada_id and gr.documento_id = gd.documento_id
    where gd.rodada_id = p_rodada
  )
  select
    b.documento_id,
    min(b.estrato) as estrato,
    min(b.origem)  as origem,
    count(*)::int  as n_rotuladores,

    -- Consenso: só devolve valor quando TODOS julgaram e todos disseram o mesmo.
    -- `count(x) = count(*)` é o que exige que ninguém tenha se calado, e
    -- `count(distinct x) = 1` é o que exige que todos digam o mesmo.
    case when count(b.tipo_correto) = count(*) and count(distinct b.tipo_correto) = 1
         then min(b.tipo_correto) end,
    (count(b.tipo_correto) = count(*) and count(distinct b.tipo_correto) = 1),

    case when count(b.entidade_correta) = count(*)
              and bool_and(fn_mesma_entidade(b.entidade_correta, b.entidade_ref))
         then min(b.entidade_ref) end,
    (count(b.entidade_correta) = count(*)
       and bool_and(fn_mesma_entidade(b.entidade_correta, b.entidade_ref))),

    case when count(b.periodo_correto) = count(*) and count(distinct b.periodo_correto) = 1
         then min(b.periodo_correto) end,
    (count(b.periodo_correto) = count(*) and count(distinct b.periodo_correto) = 1),

    case when count(b.assinado_correto) = count(*) and count(distinct b.assinado_correto) = 1
         then bool_and(b.assinado_correto) end,
    (count(b.assinado_correto) = count(*) and count(distinct b.assinado_correto) = 1),

    case when count(b.legibilidade) = count(*) and count(distinct b.legibilidade) = 1
         then min(b.legibilidade) end,
    (count(b.legibilidade) = count(*) and count(distinct b.legibilidade) = 1),

    case when count(b.item_checklist_correto) = count(*)
              and count(distinct b.item_checklist_correto) = 1
         then min(b.item_checklist_correto) end,
    (count(b.item_checklist_correto) = count(*)
       and count(distinct b.item_checklist_correto) = 1)
  from base b
  group by b.documento_id;
$$;

comment on function fn_golden_consenso(uuid) is
  'O ground truth consolidado de uma rodada, campo a campo. Onde os rotuladores discordam o campo '
  'volta null com consenso=false, e as métricas o EXCLUEM: Arquitetura do Sistema/2 Especificação/f0/06, "se humanos discordam, a máquina '
  'não tem como acertar". null de rotulador é "não julgou", que também não vira consenso.';

grant execute on function fn_golden_consenso(uuid) to authenticated;

-- -----------------------------------------------------------------------------
-- fn_golden_inter_avaliador — a concordância entre HUMANOS (Arquitetura do Sistema/2 Especificação/f0/06, protocolo de
-- rotulagem, item 1).
--
-- Ela não mede o sistema; mede se a pergunta é respondível. Concordância humana
-- baixa num campo significa que o rótulo daquele campo não sustenta decisão
-- nenhuma — e é sinal para revisar a taxonomia ou o próprio protocolo, não para
-- ajustar o modelo.
-- -----------------------------------------------------------------------------
create or replace function fn_golden_inter_avaliador(
  p_rodada uuid,
  p_origem golden_origem default 'real'
)
returns table (campo text, n_com_dois_ou_mais int, n_concordam int, concordancia numeric)
language sql
stable
as $$
  with c as (
    select * from fn_golden_consenso(p_rodada) where origem = p_origem
  ), m as (
    select 'tipo' as campo, n_rotuladores, tipo_consenso as ok from c
    union all select 'entidade',     n_rotuladores, entidade_consenso     from c
    union all select 'periodo',      n_rotuladores, periodo_consenso      from c
    union all select 'assinado',     n_rotuladores, assinado_consenso     from c
    union all select 'legibilidade', n_rotuladores, legibilidade_consenso from c
    union all select 'item_checklist', n_rotuladores, item_consenso       from c
  )
  select m.campo,
         count(*) filter (where m.n_rotuladores >= 2)::int,
         count(*) filter (where m.n_rotuladores >= 2 and m.ok)::int,
         case when count(*) filter (where m.n_rotuladores >= 2) = 0 then null
              else round(count(*) filter (where m.n_rotuladores >= 2 and m.ok)::numeric
                         / count(*) filter (where m.n_rotuladores >= 2), 4) end
  from m group by m.campo;
$$;

comment on function fn_golden_inter_avaliador(uuid, golden_origem) is
  'Concordância entre rotuladores, por campo (Arquitetura do Sistema/2 Especificação/f0/06). Conta só documento com 2+ rotuladores — com um '
  'só não há discordância possível, e incluí-lo inflaria a concordância humana com itens que ninguém '
  'conferiu duas vezes. Não mede o sistema: mede se a pergunta é respondível.';

grant execute on function fn_golden_inter_avaliador(uuid, golden_origem) to authenticated;

-- -----------------------------------------------------------------------------
-- fn_golden_classificacao — precisão / recall / F1 da classificação doc→tipo
-- (Arquitetura do Sistema/2 Especificação/f0/06, linha 1). Por TIPO, que é como o protocolo pede e como a decisão de
-- dial é tomada: um F1 agregado alto esconde o tipo raro que erra sempre.
--
-- A resposta da máquina é `documento.tipo_taxonomia` — o estado de produção, sem
-- intermediário. Documento cujos rotuladores discordam do tipo fica fora dos três
-- números e aparece em `n_sem_consenso`, para o total não parecer menor sem
-- explicação.
-- -----------------------------------------------------------------------------
create or replace function fn_golden_classificacao(
  p_rodada uuid,
  p_origem golden_origem default 'real'
)
returns table (
  tipo         text,
  n_verdade    int,
  n_maquina    int,
  tp           int,
  fp           int,
  fn_          int,
  precisao     numeric,
  recall       numeric,
  f1           numeric
)
language sql
stable
as $$
  with medido as (
    select c.documento_id, c.tipo_correto, d.tipo_taxonomia as tipo_maquina
    from fn_golden_consenso(p_rodada) c
    join documento d on d.id = c.documento_id
    where c.origem = p_origem and c.tipo_consenso
  ),
  -- O universo de tipos é a UNIÃO do que a verdade diz com o que a máquina diz.
  -- Sem a união, um tipo que a máquina inventa (só falso-positivo, nenhum caso
  -- verdadeiro) desapareceria do relatório — e é o erro mais caro que existe
  -- aqui, porque manda o documento para o checklist errado.
  tipos as (
    select tipo_correto as tipo from medido where tipo_correto is not null
    union
    select tipo_maquina from medido where tipo_maquina is not null
  )
  select t.tipo,
         count(*) filter (where m.tipo_correto = t.tipo)::int,
         count(*) filter (where m.tipo_maquina = t.tipo)::int,
         count(*) filter (where m.tipo_maquina = t.tipo and m.tipo_correto = t.tipo)::int,
         count(*) filter (where m.tipo_maquina = t.tipo
                            and m.tipo_correto is distinct from t.tipo)::int,
         count(*) filter (where m.tipo_correto = t.tipo
                            and m.tipo_maquina is distinct from t.tipo)::int,
         case when count(*) filter (where m.tipo_maquina = t.tipo) = 0 then null
              else round(count(*) filter (where m.tipo_maquina = t.tipo
                                            and m.tipo_correto = t.tipo)::numeric
                         / count(*) filter (where m.tipo_maquina = t.tipo), 4) end,
         case when count(*) filter (where m.tipo_correto = t.tipo) = 0 then null
              else round(count(*) filter (where m.tipo_maquina = t.tipo
                                            and m.tipo_correto = t.tipo)::numeric
                         / count(*) filter (where m.tipo_correto = t.tipo), 4) end,
         -- F1 = 2PR/(P+R), calculado dos contadores em vez de P e R já
         -- arredondados: arredondar antes de combinar propaga o erro para a
         -- métrica que decide.
         case when 2 * count(*) filter (where m.tipo_maquina = t.tipo and m.tipo_correto = t.tipo)
                   + count(*) filter (where m.tipo_maquina = t.tipo
                                        and m.tipo_correto is distinct from t.tipo)
                   + count(*) filter (where m.tipo_correto = t.tipo
                                        and m.tipo_maquina is distinct from t.tipo) = 0
              then null
              else round(
                (2.0 * count(*) filter (where m.tipo_maquina = t.tipo and m.tipo_correto = t.tipo))
                / (2 * count(*) filter (where m.tipo_maquina = t.tipo and m.tipo_correto = t.tipo)
                   + count(*) filter (where m.tipo_maquina = t.tipo
                                        and m.tipo_correto is distinct from t.tipo)
                   + count(*) filter (where m.tipo_correto = t.tipo
                                        and m.tipo_maquina is distinct from t.tipo)), 4) end
  from tipos t cross join medido m
  group by t.tipo;
$$;

comment on function fn_golden_classificacao(uuid, golden_origem) is
  'Precisão/recall/F1 da classificação doc->tipo, POR TIPO (Arquitetura do Sistema/2 Especificação/f0/06). O universo de tipos é a união da '
  'verdade com a saída da máquina, senão tipo que a máquina inventa (só FP) não apareceria — e é o '
  'erro mais caro, porque manda o documento para o item errado do checklist.';

grant execute on function fn_golden_classificacao(uuid, golden_origem) to authenticated;

-- -----------------------------------------------------------------------------
-- fn_golden_identificadores — acurácia de tipo / período / entidade (Arquitetura do Sistema/2 Especificação/f0/06,
-- linha 2), cada um por conta própria.
--
-- Separados de propósito: o estágio `extracao_identificadores` erra os três de
-- formas diferentes e por causas diferentes (a 0121 é um caso de ENTIDADE puro, a
-- 0122 um caso de PERÍODO puro), e um número agregado esconderia justamente a
-- coluna que precisa de trabalho.
--
-- A entidade casa por `fn_mesma_entidade` (0030) — duas grafias da mesma
-- companhia não são erro da máquina. Sem isso a métrica reprovaria o sistema por
-- ele estar certo, que é o defeito que a 0121 corrigiu na direção oposta.
-- -----------------------------------------------------------------------------
create or replace function fn_golden_identificadores(
  p_rodada uuid,
  p_origem golden_origem default 'real'
)
returns table (identificador text, n_medido int, n_acerto int, acuracia numeric, n_sem_consenso int)
language sql
stable
as $$
  with c as (select * from fn_golden_consenso(p_rodada) where origem = p_origem),
  j as (
    select c.*,
           d.tipo_taxonomia as tipo_maquina,
           (select p.referencia from periodo p where p.id = d.periodo_id)  as periodo_maquina,
           (select e.razao_social from entidade e where e.id = d.entidade_id) as entidade_maquina
    from c join documento d on d.id = c.documento_id
  ), m as (
    select 'tipo' as identificador, tipo_consenso as tem_consenso,
           (tipo_maquina = tipo_correto) as acertou from j
    union all
    select 'periodo', periodo_consenso,
           (periodo_maquina = periodo_correto) from j
    union all
    select 'entidade', entidade_consenso,
           -- fn_mesma_entidade nunca devolve null aqui: o consenso garante os
           -- dois lados preenchidos do lado da verdade, e do lado da máquina o
           -- coalesce evita que documento sem entidade some da conta — ele é
           -- ERRO quando a verdade nomeia uma empresa, não item não medido.
           fn_mesma_entidade(coalesce(entidade_maquina, ''), entidade_correta) from j
  )
  select m.identificador,
         count(*) filter (where m.tem_consenso)::int,
         count(*) filter (where m.tem_consenso and m.acertou)::int,
         case when count(*) filter (where m.tem_consenso) = 0 then null
              else round(count(*) filter (where m.tem_consenso and m.acertou)::numeric
                         / count(*) filter (where m.tem_consenso), 4) end,
         count(*) filter (where not m.tem_consenso)::int
  from m group by m.identificador;
$$;

comment on function fn_golden_identificadores(uuid, golden_origem) is
  'Acurácia de tipo/período/entidade separadamente (Arquitetura do Sistema/2 Especificação/f0/06). Separados porque as causas de erro são '
  'distintas — a 0121 foi entidade pura, a 0122 período puro — e o agregado esconderia a coluna que '
  'precisa de trabalho. Entidade casa por fn_mesma_entidade: grafia diferente não é erro.';

grant execute on function fn_golden_identificadores(uuid, golden_origem) to authenticated;

-- -----------------------------------------------------------------------------
-- fn_golden_campos — erro de extração de campos financeiros (Arquitetura do Sistema/2 Especificação/f0/06, linha 3) E a
-- COBERTURA, que o `medir-auto-aceite.mts` aponta como "a métrica que mais
-- importa" e é a razão de ela sair junto e não numa função separada.
--
-- QUATRO DESFECHOS, E O QUARTO É O QUE ESTE PROJETO INTEIRO PERSEGUE:
--
--   exato              — valor idêntico ao rótulo
--   dentro_tolerancia  — diferença dentro da tolerância declarada NO rótulo
--   errado             — a linha voltou com outro número
--   ausente            — a linha NÃO voltou
--
-- `ausente` não é um tipo de erro: é perda silenciosa, que é a família de defeito
-- que custou as três camadas de cobertura (39% do dado chegando ao banco, o livro
-- razão com 99 de 461 linhas "sem uma pendência"). Somar `ausente` com `errado`
-- num "erro de extração" único apagaria justamente a distinção que motivou a
-- metade do trabalho das sessões 45 a 47.
--
-- E A COBERTURA VAI NA DIREÇÃO CONTRÁRIA: quantas linhas o dial AUTO-ACEITOU sem
-- que exista rótulo capaz de conferi-las. Essa linha virou fato sem que humano ou
-- teste tenha olhado, e é o tamanho real da aposta do N2. Reduzi-la exige rótulo
-- mais fino, não limiar mais alto — está escrito no cabeçalho daquele script e
-- vale repetir aqui, porque é a conclusão que o número convida a errar.
--
-- Casa com a versão VIGENTE (`fn_versao_com_extracao`, 0102), não com
-- `max(n_versao)`: entre registrar o documento e gravar os campos a versão mais
-- nova está vazia, e medir contra ela reportaria 100% de ausência numa janela em
-- que nada está errado.
-- -----------------------------------------------------------------------------
create or replace function fn_golden_campos(
  p_rodada uuid,
  p_origem golden_origem default 'real'
)
returns table (
  tipo                       text,
  n_rotulado                 int,
  n_exato                    int,
  n_dentro_tolerancia        int,
  n_errado                   int,
  n_ausente                  int,
  acerto                     numeric,
  n_auto_aceito              int,
  n_auto_aceito_sem_rotulo   int,
  cobertura_conferida        numeric,
  n_sem_consenso             int
)
language sql
stable
as $$
  with docs as (
    select gd.documento_id, d.tipo_taxonomia, fn_versao_com_extracao(d.id) as versao_id
    from golden_documento gd
    join documento d on d.id = gd.documento_id
    where gd.rodada_id = p_rodada and gd.origem = p_origem
  ),
  -- Consenso do CAMPO. Regra diferente da do documento, de propósito: aqui basta
  -- que os rotuladores que julgaram este campo concordem. O Arquitetura do Sistema/2 Especificação/f0/06 pede dois
  -- rotuladores "nos casos ambíguos", então o segundo confere uma AMOSTRA das
  -- linhas — exigir que ele tenha julgado todas jogaria fora o rótulo do
  -- primeiro em tudo o que a amostra não cobriu.
  rotulo as (
    select gc.documento_id,
           fn_normalizar_texto(gc.chave)            as chave_norm,
           coalesce(gc.periodo_coluna, '')          as periodo,
           coalesce(gc.entidade_coluna, '')         as entidade,
           min(gc.valor_correto)                    as valor_correto,
           max(gc.tolerancia)                       as tolerancia,
           (count(distinct gc.valor_correto) = 1)   as consenso
    from golden_campo gc
    join docs on docs.documento_id = gc.documento_id
    where gc.rodada_id = p_rodada and gc.valor_correto is not null
    group by 1, 2, 3, 4
  ),
  maquina as (
    select docs.documento_id, docs.tipo_taxonomia,
           fn_normalizar_texto(ce.chave)      as chave_norm,
           coalesce(ce.periodo_coluna, '')    as periodo,
           coalesce(ce.entidade_coluna, '')   as entidade,
           -- Mesma regra de desempate da fn_valores_por_ano (0125): quando o
           -- mesmo par volta duas vezes, vale a ocorrência de maior módulo.
           (array_agg(ce.valor_num order by abs(ce.valor_num) desc))[1] as valor_num,
           bool_or(ce.status_aceite = 'aceito' and ce.aceito_por like 'sistema:auto_aceite%')
             as auto_aceito
    from docs
    join campo_extraido ce on ce.documento_versao_id = docs.versao_id
    where ce.valor_num is not null
    group by 1, 2, 3, 4, 5
  ),
  par as (
    select docs.tipo_taxonomia as tipo, r.consenso,
           m.valor_num, r.valor_correto, r.tolerancia
    from rotulo r
    join docs on docs.documento_id = r.documento_id
    left join maquina m
      on m.documento_id = r.documento_id and m.chave_norm = r.chave_norm
     and m.periodo = r.periodo and m.entidade = r.entidade
  ),
  -- A cobertura olha o conjunto INVERSO: linha auto-aceita da máquina que nenhum
  -- rótulo confere.
  cob as (
    select m.tipo_taxonomia as tipo,
           count(*) filter (where m.auto_aceito)::int as n_auto,
           count(*) filter (where m.auto_aceito and r.valor_correto is null)::int as n_auto_sem
    from maquina m
    left join rotulo r
      on r.documento_id = m.documento_id and r.chave_norm = m.chave_norm
     and r.periodo = m.periodo and r.entidade = m.entidade
    group by 1
  )
  select coalesce(p.tipo, c.tipo),
         count(p.consenso) filter (where p.consenso)::int,
         count(*) filter (where p.consenso and p.valor_num is not null
                            and p.valor_num = p.valor_correto)::int,
         count(*) filter (where p.consenso and p.valor_num is not null
                            and p.valor_num <> p.valor_correto
                            and abs(p.valor_num - p.valor_correto) <= p.tolerancia)::int,
         count(*) filter (where p.consenso and p.valor_num is not null
                            and abs(p.valor_num - p.valor_correto) > p.tolerancia)::int,
         count(*) filter (where p.consenso and p.valor_num is null)::int,
         case when count(*) filter (where p.consenso) = 0 then null
              else round(count(*) filter (where p.consenso and p.valor_num is not null
                                            and abs(p.valor_num - p.valor_correto)
                                                <= p.tolerancia)::numeric
                         / count(*) filter (where p.consenso), 4) end,
         coalesce(max(c.n_auto), 0),
         coalesce(max(c.n_auto_sem), 0),
         case when coalesce(max(c.n_auto), 0) = 0 then null
              else round((max(c.n_auto) - max(c.n_auto_sem))::numeric / max(c.n_auto), 4) end,
         count(*) filter (where not p.consenso)::int
  from par p full outer join cob c on c.tipo = p.tipo
  group by 1;
$$;

comment on function fn_golden_campos(uuid, golden_origem) is
  'Erro de extração de campo financeiro (Arquitetura do Sistema/2 Especificação/f0/06) com AUSENTE separado de ERRADO — perda silenciosa é '
  'outra família de defeito, e foi ela que custou as três camadas de cobertura. Traz junto a '
  'cobertura_conferida: fração das linhas AUTO-ACEITAS que algum rótulo consegue conferir. O resto '
  'virou fato sem ninguém olhar, e reduzi-lo exige rótulo mais fino, não limiar mais alto.';

grant execute on function fn_golden_campos(uuid, golden_origem) to authenticated;

-- -----------------------------------------------------------------------------
-- fn_golden_classe_a — taxa de falso-positivo da reconciliação Classe A (Arquitetura do Sistema/2 Especificação/f0/06,
-- linha 5: "subir Classe A de N1→N2").
--
-- ESTA É A MÉTRICA QUE NUNCA PRECISOU DE GOLDEN SET, E É POR ISSO QUE ELA DÓI.
-- O rótulo dela existe desde a 0106 e é produzido pelo próprio trabalho do
-- analista: o cabeçalho daquela migration define `rejeitada` como *"a pendência
-- não procede (falso positivo do motor)"*, com essas palavras. Ou seja: desde 11
-- de agosto o sistema coleta, a cada rejeição, um ponto de dado sobre a qualidade
-- da própria reconciliação — e ninguém somou.
--
-- O DENOMINADOR SÃO OS VEREDITOS HUMANOS, e só eles. `resolvida` por
-- `sistema:reconciliacao` significa que o sintoma desapareceu (reextração
-- corrigiu, ou a regra mudou e não emite mais) — não é ninguém dizendo que a
-- pendência procedia. Contá-la como acerto do motor seria creditar a ele um
-- veredito que ninguém deu; é contada à parte, para o número não sumir.
-- -----------------------------------------------------------------------------
create or replace function fn_golden_classe_a(p_caso_id uuid default null)
returns jsonb
language sql
stable
as $$
  with a as (
    select p.id, p.estado, p.resolvida_por
    from pendencia p
    where p.origem_estagio = 'reconciliacao'
      and (p_caso_id is null or p.caso_id = p_caso_id)
      and exists (
        select 1 from reconciliacao r
        where r.caso_id = p.caso_id
          and r.classe = 'A'
          and p.motivo = 'reconciliacao:' || r.tipo
      )
  ), v as (
    select
      count(*) filter (where estado = 'rejeitada')::int as falso_positivo,
      count(*) filter (where estado in ('resolvida', 'aceita_com_ressalva')
                         and coalesce(resolvida_por, '') not like 'sistema:%')::int as procedia,
      count(*) filter (where estado = 'resolvida'
                         and coalesce(resolvida_por, '') like 'sistema:%')::int as sumiu_sozinha,
      count(*) filter (where estado in ('aberta','em_correcao_interna','reenviada_ao_cliente'))::int
        as sem_veredito
    from a
  )
  select jsonb_build_object(
    'com_veredito_humano', falso_positivo + procedia,
    'falso_positivo', falso_positivo,
    'procedia', procedia,
    'taxa_falso_positivo',
      case when falso_positivo + procedia = 0 then null
           else round(falso_positivo::numeric / (falso_positivo + procedia), 4) end,
    -- O critério é "mais alto e melhor", como os outros três, para a comparação
    -- em fn_golden_suficiente ser uma só.
    'nao_falso_positivo',
      case when falso_positivo + procedia = 0 then null
           else round(1 - falso_positivo::numeric / (falso_positivo + procedia), 4) end,
    'resolvida_pelo_sistema_sem_veredito', sumiu_sozinha,
    'ainda_sem_veredito', sem_veredito,
    'como_ler', 'O rótulo é o veredito humano registrado pela 0106: rejeitada = não procede = falso '
                'positivo do motor. Pendência que o próprio sistema resolveu não conta em nenhum dos '
                'dois lados — ninguém disse que ela procedia.'
  ) from v;
$$;

comment on function fn_golden_classe_a(uuid) is
  'Taxa de falso-positivo da reconciliação Classe A (Arquitetura do Sistema/2 Especificação/f0/06, linha 5). Única das cinco métricas que '
  'NÃO precisa de rotulagem: o rótulo é o estado "rejeitada" que a 0106 define como "não procede '
  '(falso positivo do motor)", e o analista o produz desde 11/08. Denominador = vereditos humanos; '
  'pendência que o sistema resolveu sozinho fica fora, contada à parte.';

grant execute on function fn_golden_classe_a(uuid) to authenticated;

-- -----------------------------------------------------------------------------
-- fn_golden_cobertura — o dimensionamento do `Arquitetura do Sistema/2 Especificação/f0/06`, medido.
--
-- OS "TIPOS CORE" NÃO ENTRAM COMO LISTA. O `Arquitetura do Sistema/2 Especificação/f0/06` define core como "os 8 do Kit
-- Básico (0.3)" e nomeia os oito; a taxonomia semeada na 0002 já marca esses
-- mesmos oito com `obrigatoriedade = 'obrigatorio'`. Repetir a lista dentro desta
-- função criaria o segundo lugar que decide quem é core — a forma exata dos
-- quatro incidentes de dupla contagem que o HANDOFF tabela.
--
-- E `granularidade` responde de graça a nuance que o `Arquitetura do Sistema/2 Especificação/f0/06` levanta: os tipos de
-- granularidade `caso`/`periodo` rendem ~1 por mandato e vão demorar mais para
-- juntar 20 — o protocolo diz que isso "é esperado, não é falha". A coluna vem no
-- resultado para que a demora seja legível em vez de parecer negligência.
-- -----------------------------------------------------------------------------
create or replace function fn_golden_cobertura(
  p_rodada uuid,
  p_origem golden_origem default 'real'
)
returns table (
  tipo                    text,
  granularidade           granularidade,
  n_documentos            int,
  n_dois_rotuladores      int,
  estratos                text[],
  n_minimo                int,
  atinge_minimo           boolean
)
language sql
stable
as $$
  with alvo as (
    -- Um n_minimo por rodada: o critério é por ESTÁGIO, e a cobertura por tipo é
    -- a mesma exigência para todos eles. O maior dos critérios é o que vale, para
    -- a cobertura não aprovar um tipo que o estágio mais exigente reprovaria.
    select coalesce(max(gc.n_minimo), 20) as n from golden_criterio gc
  ),
  -- O TIPO AQUI É O DA VERDADE, NÃO O DA MÁQUINA, e esta linha é a correção de um
  -- defeito que o teste desta migration achou na primeira execução. Agrupar por
  -- `documento.tipo_taxonomia` faria a COBERTURA DO GROUND TRUTH ser medida pela
  -- resposta que está sob avaliação: numa rodada com 25 balanços dos quais o
  -- classificador chamou 5 de DRE, a cobertura reportava "BALANCO 20, DRE 5" e
  -- reprovava por N — quando a rodada tem 25 balanços rotulados e o que ela
  -- deveria acusar é a classificação errada, não falta de amostra. É a mesma
  -- confusão de autoridade das três de unidade que a sessão 52 achou.
  --
  -- Documento em que os rotuladores discordam do tipo não entra em tipo nenhum:
  -- ele não TEM tipo acordado, e atribuí-lo ao palpite de um dos dois seria
  -- inventar a verdade que falta.
  rot as (
    select c.documento_id, c.tipo_correto, c.n_rotuladores as n_rot, c.estrato
    from fn_golden_consenso(p_rodada) c
    where c.origem = p_origem and c.tipo_consenso
  )
  select t.codigo,
         t.granularidade,
         count(rot.documento_id)::int,
         count(rot.documento_id) filter (where rot.n_rot >= 2)::int,
         coalesce(array_agg(distinct rot.estrato::text)
                    filter (where rot.estrato is not null), '{}'),
         (select n from alvo)::int,
         count(rot.documento_id) >= (select n from alvo)
  from taxonomia_tipo_documento t
  left join rot on rot.tipo_correto = t.codigo
  where t.obrigatoriedade = 'obrigatorio' and t.ativo
  group by t.codigo, t.granularidade;
$$;

comment on function fn_golden_cobertura(uuid, golden_origem) is
  'Quantos documentos rotulados a rodada tem por tipo CORE, contra o alvo do Arquitetura do Sistema/2 Especificação/f0/06 (~20-30). Core sai '
  'de obrigatoriedade=obrigatorio na taxonomia (0002), que são os mesmos 8 do Kit Básico — não de uma '
  'lista repetida aqui. granularidade vem no resultado porque tipo por CASO rende ~1 por mandato: '
  'demorar a juntar 20 é esperado, e o Arquitetura do Sistema/2 Especificação/f0/06 diz isso.';

grant execute on function fn_golden_cobertura(uuid, golden_origem) to authenticated;

-- -----------------------------------------------------------------------------
-- fn_golden_suficiente — a pergunta única que o portão faz.
--
-- É aqui que "concordância alta e estável no tipo X?" do laço de calibração do
-- `Arquitetura do Sistema/2 Especificação/f0/06` deixa de ser um losango de fluxograma.
--
-- DUAS REGRAS QUE NÃO SÃO ÓBVIAS E SÃO AS QUE IMPORTAM:
--
-- 1. O TIPO MAIS FRACO GOVERNA. O dial é por ESTÁGIO (0001/0002) e o `Arquitetura do Sistema/2 Especificação/f0/06`
--    raciocina por TIPO — ele chega a dizer "se para algum tipo não houver ~20
--    exemplos, aquele tipo permanece em N0/N1". Autonomia por (estágio × tipo) não
--    existe no schema, e inventá-la aqui seria decidir de lado uma mudança de
--    modelo de dados. Enquanto não existir, a leitura conservadora é a única
--    honesta: se um tipo core presente na rodada reprova, o estágio não sobe. É o
--    fechamento #1 (default-para-humano) aplicado à própria calibração, e fica
--    anotado como a decisão de schema que falta.
--
-- 2. RODADA NÃO CONGELADA NÃO AUTORIZA NADA. Evidência que ainda pode mudar não
--    sustenta uma decisão que fica registrada como tomada contra ela.
-- -----------------------------------------------------------------------------
create or replace function fn_golden_suficiente(p_estagio text, p_rodada uuid default null)
returns jsonb
language plpgsql
stable
as $$
declare
  v_natureza  text;
  v_crit      golden_criterio;
  v_rodada    golden_rodada;
  v_falhas    jsonb := '[]'::jsonb;
  v_detalhe   jsonb;
  v_pior      numeric;
  v_n_min_ok  boolean;
  v_classe_a  jsonb;
begin
  select natureza into v_natureza from estagio_autonomia where estagio = p_estagio;
  if v_natureza is null then
    return jsonb_build_object('aplica', false, 'suficiente', false,
      'porque', format('Estágio "%s" não existe no dial.', p_estagio));
  end if;

  -- Determinístico: a regra de ouro do Arquitetura do Sistema/1 Visão e Doutrina/01 fala de estágio INTERPRETATIVO. A
  -- confiança em aritmética e integridade de arquivo não vem de concordância
  -- humana, e pedir rotulador para conferir se um zip abre não mediria nada.
  if v_natureza = 'deterministico' then
    return jsonb_build_object('aplica', false, 'suficiente', true,
      'porque', 'Estágio determinístico objetivo (Arquitetura do Sistema/1 Visão e Doutrina/01): a regra de ouro governa os '
                'interpretativos. A garantia dele é teste, não concordância medida.');
  end if;

  select * into v_crit from golden_criterio where estagio = p_estagio;
  if v_crit.estagio is null then
    return jsonb_build_object('aplica', true, 'suficiente', false,
      'porque', format('Não há critério de golden set para "%s" em golden_criterio, então não há '
                       'como medir se a concordância basta. Estágio de teto N1 (reconciliação '
                       'Classe B/C, classificação contábil) nunca chega aqui — o teto recusa antes, '
                       'e Arquitetura do Sistema/1 Visão e Doutrina/01 os marca como "nunca autônomo".', p_estagio));
  end if;

  if p_rodada is null then
    return jsonb_build_object('aplica', true, 'suficiente', false,
      'criterio', to_jsonb(v_crit),
      'porque', 'Nenhuma rodada de golden set informada. Arquitetura do Sistema/1 Visão e Doutrina/01, regra de ouro: subir dial de '
                'estágio interpretativo exige concordância MEDIDA — sem rodada não há medição.');
  end if;

  select * into v_rodada from golden_rodada where id = p_rodada;
  if v_rodada.id is null then
    return jsonb_build_object('aplica', true, 'suficiente', false, 'criterio', to_jsonb(v_crit),
      'porque', format('Rodada de golden set %s não existe.', p_rodada));
  end if;
  if v_rodada.congelada_em is null then
    return jsonb_build_object('aplica', true, 'suficiente', false, 'criterio', to_jsonb(v_crit),
      'rodada', v_rodada.nome,
      'porque', format('A rodada "%s" não está CONGELADA. O Arquitetura do Sistema/2 Especificação/f0/06 congela a rodada por medição, e '
                       'evidência que ainda pode mudar não sustenta uma decisão registrada contra '
                       'ela.', v_rodada.nome));
  end if;

  -- --- cobertura: o N do Arquitetura do Sistema/2 Especificação/f0/06, por tipo core PRESENTE na rodada ---------------
  -- Tipo com zero documento não reprova a subida: o Arquitetura do Sistema/2 Especificação/f0/06 diz que tipo sem
  -- exemplo "permanece em N0/N1", e essa é uma afirmação sobre o TIPO, não sobre
  -- o estágio. Reprovar por ausência travaria toda subida para sempre, porque
  -- CONTRATO_SOCIAL rende 1 por mandato.
  select jsonb_agg(to_jsonb(c)), bool_and(c.atinge_minimo)
    into v_detalhe, v_n_min_ok
  from fn_golden_cobertura(p_rodada) c where c.n_documentos > 0;

  if v_detalhe is null then
    return jsonb_build_object('aplica', true, 'suficiente', false, 'criterio', to_jsonb(v_crit),
      'rodada', v_rodada.nome,
      'porque', 'A rodada não tem nenhum documento de tipo CORE com origem "real". Rotular o book '
                'sintético mede o instrumento, não o modelo — é a ressalva que o '
                'medir-auto-aceite.mts carrega no cabeçalho, e aqui ela é guarda.');
  end if;

  if not coalesce(v_n_min_ok, false) then
    v_falhas := v_falhas || jsonb_build_object('falha', 'n_minimo',
      'detalhe', format('Tipo core presente na rodada com menos de %s documentos rotulados. O tipo '
                        'mais fraco governa: o dial é por ESTÁGIO e o Arquitetura do Sistema/2 Especificação/f0/06 raciocina por TIPO, '
                        'então subir com um tipo fraco sobe autonomia sobre ele também.',
                        v_crit.n_minimo));
  end if;

  -- --- a métrica que governa este estágio -------------------------------------
  if v_crit.metrica = 'f1_classificacao' then
    -- `n_verdade > 0`: só tipo para o qual a rodada TEM verdade participa do
    -- "mais fraco governa". Um tipo que aparece apenas como falso-positivo da
    -- máquina tem F1 zero por construção (precisão 0, recall indefinido), e
    -- deixá-lo entrar daria poder de VETO a um único documento — pior, o mesmo
    -- erro seria contado duas vezes, porque o documento cuja verdade era X e que
    -- a máquina chamou de Y já é falso-negativo de X. O erro é contado uma vez,
    -- no tipo que tinha a verdade, que é onde ele tem denominador.
    select min(f1) into v_pior from fn_golden_classificacao(p_rodada) c
      join taxonomia_tipo_documento t on t.codigo = c.tipo
     where t.obrigatoriedade = 'obrigatorio' and c.f1 is not null and c.n_verdade > 0;

  elsif v_crit.metrica = 'acuracia_identificadores' then
    -- Aqui o "mais fraco" é o IDENTIFICADOR, não o tipo: a função mede tipo,
    -- período e entidade separadamente porque as causas de erro são distintas, e
    -- é a pior das três que diz o que o estágio entrega.
    select min(acuracia) into v_pior from fn_golden_identificadores(p_rodada)
     where acuracia is not null;

  elsif v_crit.metrica = 'acerto_campos' then
    select min(acerto) into v_pior from fn_golden_campos(p_rodada) c
      join taxonomia_tipo_documento t on t.codigo = c.tipo
     where t.obrigatoriedade = 'obrigatorio' and c.acerto is not null;

  elsif v_crit.metrica = 'nao_falso_positivo_classe_a' then
    -- A única que não sai da rodada: o rótulo dela é o veredito humano da 0106,
    -- produzido em produção. A rodada continua sendo exigida acima porque o N e o
    -- congelamento são o que datam a decisão.
    v_classe_a := fn_golden_classe_a();
    v_pior := (v_classe_a->>'nao_falso_positivo')::numeric;
    v_detalhe := jsonb_build_object('cobertura', v_detalhe, 'classe_a', v_classe_a);
    if (v_classe_a->>'com_veredito_humano')::int < v_crit.n_minimo then
      v_falhas := v_falhas || jsonb_build_object('falha', 'n_minimo_vereditos',
        'detalhe', format('%s veredito(s) humano(s) sobre divergência Classe A, contra o mínimo de '
                          '%s. Pendência que o próprio sistema resolveu não conta: ninguém disse '
                          'que ela procedia.',
                          v_classe_a->>'com_veredito_humano', v_crit.n_minimo));
    end if;

  else
    return jsonb_build_object('aplica', true, 'suficiente', false, 'criterio', to_jsonb(v_crit),
      'porque', format('Métrica "%s" não é calculada por nenhuma função desta migration. Critério '
                       'com métrica desconhecida RECUSA — aprovar por não saber medir é o oposto '
                       'do que a regra de ouro pede.', v_crit.metrica));
  end if;

  if v_pior is null then
    v_falhas := v_falhas || jsonb_build_object('falha', 'sem_medicao',
      'detalhe', 'A rodada existe e está congelada, mas a métrica deste estágio não pôde ser '
                 'calculada em nenhum tipo core — sem rótulo conferível não há concordância.');
  elsif v_pior < v_crit.concordancia_minima then
    v_falhas := v_falhas || jsonb_build_object('falha', 'concordancia',
      'detalhe', format('Pior caso medido %s, contra o mínimo de %s.',
                        v_pior, v_crit.concordancia_minima));
  end if;

  return jsonb_build_object(
    'aplica', true,
    'suficiente', jsonb_array_length(v_falhas) = 0,
    'estagio', p_estagio,
    'rodada', v_rodada.nome,
    'rodada_id', v_rodada.id,
    'congelada_em', v_rodada.congelada_em,
    'criterio', to_jsonb(v_crit),
    'metrica', v_crit.metrica,
    'pior_caso', v_pior,
    'detalhe', v_detalhe,
    'falhas', v_falhas
  );
end;
$$;

comment on function fn_golden_suficiente(text, uuid) is
  'A pergunta do laço de calibração do Arquitetura do Sistema/2 Especificação/f0/06 ("concordância alta e estável?"), respondida em número. '
  'O TIPO MAIS FRACO governa: o dial é por estágio e o Arquitetura do Sistema/2 Especificação/f0/06 raciocina por tipo, e autonomia por '
  '(estágio x tipo) não existe no schema — enquanto não existir, a leitura conservadora é a única '
  'honesta. Rodada não congelada não autoriza nada. Métrica desconhecida RECUSA.';

grant execute on function fn_golden_suficiente(text, uuid) to authenticated;

-- =============================================================================
-- O DIAL
-- =============================================================================

-- -----------------------------------------------------------------------------
-- fn_dial — passa a dizer NATUREZA e BASE, que é o que a tela adivinhava.
--
-- O painel de autonomia decide o aviso "Autonomia declarada, não medida" por
-- `d.estagio.startsWith("extracao")`. Heurística de nome erra nos dois sentidos:
-- um estágio de extração que ganhe medição continua sendo avisado, e um estágio
-- de outro nome que suba sem medição não é avisado por ninguém. Com `base` no
-- retorno, a tela lê o fato.
-- -----------------------------------------------------------------------------
create or replace function fn_dial(p_estagio text)
returns jsonb
language sql
stable
as $$
  select jsonb_build_object(
    'estagio', ea.estagio,
    'nivel_atual', ea.nivel_atual,
    'teto', ea.teto,
    'limiar_auto_clear', ea.limiar_auto_clear,
    'no_teto', ea.nivel_atual = ea.teto,
    'natureza', ea.natureza,
    'base_do_nivel', ea.base_do_nivel,
    'medicao_rodada_id', ea.medicao_rodada_id,
    'medicao_em', ea.medicao_em,
    'medicao_resumo', ea.medicao_resumo,
    'atualizado_por', ea.atualizado_por,
    'atualizado_em', ea.atualizado_em
  )
  from estagio_autonomia ea where ea.estagio = p_estagio;
$$;

grant execute on function fn_dial(text) to authenticated;

-- -----------------------------------------------------------------------------
-- fn_mudar_dial — a regra de ouro do `Arquitetura do Sistema/1 Visão e Doutrina/01` passa a ser executada aqui.
--
-- A ordem das guardas importa, e é esta:
--
--   1. estágio existe?            (0041)
--   2. respeita o TETO?           (0041 — natureza do estágio, inegociável)
--   3. é SUBIDA que alcança N2/N3 num estágio INTERPRETATIVO?   ← novo
--        ├─ com rodada de golden set: `fn_golden_suficiente` decide.
--        │    Insuficiente ⇒ RECUSA, nomeando o número que faltou.
--        ├─ com `p_sem_medicao_porque`: passa, `base = 'declarada'`, e a trilha
--        │    grava `mudanca_dial_sem_medicao` — a decisão do dono continua
--        │    sendo dele, e passa a ser CONTÁVEL.
--        └─ com nenhum dos dois: RECUSA, e o motivo explica os dois caminhos.
--
-- POR QUE `p_sem_medicao_porque` EXISTE, e por que é texto e não booleano. Um
-- `p_forcar boolean` seria marcado como true e esquecido lá; um motivo obrigatório
-- é lido por quem revisa a trilha depois. E sem essa porta a 0041 não conseguiria
-- rodar num banco montado do zero — ela sobe a extração para N2 declaradamente
-- sem medição, e travá-la aqui transformaria a cadeia de migrations em algo que
-- não aplica. É a lição das verificações-alçapão que a 0119 e a 0120 tiveram de
-- ter desarmadas: guarda que impede o estado legítimo do dono não é guarda.
--
-- DESCER NUNCA PEDE NADA. Não é omissão, é a propriedade mais importante do
-- arquivo: `fn_mudar_dial(x, 'N0', …)` é o freio, e freio que exige papelada não
-- é freio. O teste do dial já trata isso como o assert mais importante dele.
--
-- RECUSA RETORNADA, não exceção — padrão 0036/0037/0038/0041: a exceção desfaria o
-- registro da própria tentativa, e tentativa de subir sem medição é exatamente o
-- que a trilha precisa guardar.
-- -----------------------------------------------------------------------------
drop function if exists fn_mudar_dial(text, nivel_autonomia, text, text, numeric);

create or replace function fn_mudar_dial(
  p_estagio             text,
  p_nivel               nivel_autonomia,
  p_autor               text,
  p_motivo              text default null,
  p_limiar              numeric default null,
  p_rodada_golden       uuid default null,
  p_sem_medicao_porque  text default null
)
returns jsonb
language plpgsql
as $$
declare
  v_antes     jsonb;
  v_teto      nivel_autonomia;
  v_nivel_ant nivel_autonomia;
  v_natureza  text;
  v_sobe_para_autonomia boolean;
  v_med       jsonb;
  v_base      text;
  v_resumo    jsonb;
begin
  select to_jsonb(ea), ea.teto, ea.nivel_atual, ea.natureza
    into v_antes, v_teto, v_nivel_ant, v_natureza
  from estagio_autonomia ea where ea.estagio = p_estagio;

  if v_antes is null then
    return jsonb_build_object('recusado', true,
      'motivo_recusa', format('Estágio "%s" não existe no dial. Os estágios são semeados na 0002 '
                              '(Arquitetura do Sistema/2 Especificação/f0/04) — estágio novo entra por migration, não por chamada.', p_estagio));
  end if;

  -- O TETO É POR NATUREZA DO ESTÁGIO e é inegociável (Arquitetura do Sistema/1 Visão e Doutrina/01, "regra de teto"):
  -- reconciliação Classe B/C e classificação contábil têm teto N1 e NUNCA viram
  -- autônomas. Recusar aqui é o que impede uma chamada de fazer o que a doutrina
  -- proíbe.
  if p_nivel > v_teto then
    insert into evento_auditoria (ator, acao, entidade_ref, depois)
      values (p_autor, 'mudanca_dial_recusada', 'estagio:'||p_estagio,
              jsonb_build_object('pedido', p_nivel, 'teto', v_teto, 'motivo_informado', p_motivo));
    return jsonb_build_object('recusado', true,
      'motivo_recusa', format('O estágio "%s" tem TETO %s e foi pedido %s. O teto é por natureza do '
                              'estágio (Arquitetura do Sistema/1 Visão e Doutrina/01) e nenhuma chamada o sobrepõe — mudá-lo é decisão de '
                              'doutrina, por migration.', p_estagio, v_teto, p_nivel));
  end if;

  -- ----- A REGRA DE OURO (0126) ---------------------------------------------
  -- "Subida que ALCANÇA N2/N3": `p_nivel > v_nivel_ant` é o que faz descer e
  -- reafirmar o mesmo nível passarem livres. Reafirmar importa na prática — é o
  -- que a 0041 faz ao ser reaplicada, e o que qualquer `update` do limiar faz.
  v_sobe_para_autonomia := p_nivel > v_nivel_ant
                           and p_nivel in ('N2', 'N3')
                           and v_natureza = 'interpretativo';

  v_base := case when p_nivel in ('N2','N3') and v_natureza = 'interpretativo'
                 then 'declarada' else 'nao_se_aplica' end;

  if v_sobe_para_autonomia then
    if p_rodada_golden is not null then
      v_med := fn_golden_suficiente(p_estagio, p_rodada_golden);
      if not coalesce((v_med->>'suficiente')::boolean, false) then
        insert into evento_auditoria (ator, acao, entidade_ref, depois)
          values (p_autor, 'mudanca_dial_recusada', 'estagio:'||p_estagio,
                  jsonb_build_object('pedido', p_nivel, 'de', v_nivel_ant,
                                     'motivo_informado', p_motivo, 'medicao', v_med));
        return jsonb_build_object('recusado', true, 'medicao', v_med,
          'motivo_recusa', format('A concordância medida contra a rodada de golden set não basta '
                                  'para subir "%s" de %s para %s. Arquitetura do Sistema/1 Visão e Doutrina/01, regra de ouro: nada de '
                                  'subir dial de estágio interpretativo sem golden set e '
                                  'concordância medida. O que faltou está em "medicao".',
                                  p_estagio, v_nivel_ant, p_nivel));
      end if;
      v_base := 'medida';
      v_resumo := v_med;

    elsif p_sem_medicao_porque is null then
      insert into evento_auditoria (ator, acao, entidade_ref, depois)
        values (p_autor, 'mudanca_dial_recusada', 'estagio:'||p_estagio,
                jsonb_build_object('pedido', p_nivel, 'de', v_nivel_ant,
                                   'motivo_informado', p_motivo,
                                   'porque', 'sem rodada de golden set e sem motivo declarado'));
      return jsonb_build_object('recusado', true,
        'motivo_recusa', format('Subir "%s" de %s para %s é entrar em auto-clear num estágio '
                                'INTERPRETATIVO, e Arquitetura do Sistema/1 Visão e Doutrina/01 exige concordância medida para isso. '
                                'Dois caminhos: passe `p_rodada_golden` com uma rodada CONGELADA que '
                                'satisfaça golden_criterio, ou assuma a decisão em '
                                '`p_sem_medicao_porque` — nesse caso a subida acontece, fica '
                                'registrada como mudanca_dial_sem_medicao e o nível passa a valer '
                                'como DECLARADO, não medido.', p_estagio, v_nivel_ant, p_nivel));
    end if;
  end if;

  update estagio_autonomia
    set nivel_atual = p_nivel,
        limiar_auto_clear = coalesce(p_limiar, limiar_auto_clear),
        base_do_nivel = v_base,
        -- Ponteiro e resumo só sobrevivem enquanto o nível que eles justificam
        -- sobrevive: descer para N1 e subir de novo não pode reaproveitar a
        -- medição de antes como se ela tivesse sido feita agora.
        medicao_rodada_id = case when v_base = 'medida' then p_rodada_golden else null end,
        medicao_em        = case when v_base = 'medida' then now() else null end,
        medicao_resumo    = case when v_base = 'medida' then v_resumo else null end,
        atualizado_por = p_autor,
        atualizado_em = now()
  where estagio = p_estagio;

  -- 'mudanca_dial' existe no enum desde a 0001. `mudanca_dial_sem_medicao` é da
  -- 0126 e existe para que o dial declarado seja CONTÁVEL: sem ação própria, ele
  -- fica indistinguível do medido dentro de uma lista de 'mudanca_dial'.
  insert into evento_auditoria (ator, acao, entidade_ref, antes, depois)
    values (p_autor,
            case when v_sobe_para_autonomia and p_rodada_golden is null
                 then 'mudanca_dial_sem_medicao' else 'mudanca_dial' end,
            'estagio:'||p_estagio, v_antes,
            (select to_jsonb(ea) from estagio_autonomia ea where ea.estagio = p_estagio)
            || jsonb_build_object('motivo', p_motivo,
                                  'sem_medicao_porque', p_sem_medicao_porque,
                                  'medicao', v_resumo));

  return fn_dial(p_estagio);
end;
$$;

grant execute on function fn_mudar_dial(text, nivel_autonomia, text, text, numeric, uuid, text)
  to authenticated;

-- -----------------------------------------------------------------------------
-- E O QUE JÁ ESTÁ LIGADO PASSA A DIZER EM QUE SE APOIA.
--
-- Nada muda de nível aqui. O que muda é que o N2 da extração para de ser
-- indistinguível de um N2 medido — a ressalva que a 0019 escreveu em prosa, a
-- 0041 repetiu em prosa e a tela de autonomia imprime em prosa passa a ser uma
-- coluna que dá para consultar e contar.
--
-- Sem `where`, um `update` aqui marcaria os determinísticos como declarados
-- também, e eles não são: N2 em validação formal não é aposta nenhuma.
-- -----------------------------------------------------------------------------
update estagio_autonomia
   set base_do_nivel = 'declarada'
 where natureza = 'interpretativo'
   and nivel_atual in ('N2', 'N3')
   and base_do_nivel = 'nao_se_aplica';

do $$
declare v_n int;
begin
  select count(*) into v_n from estagio_autonomia
   where base_do_nivel = 'declarada';
  -- NOTICE, nunca exception. A 0119 e a 0120 tiveram de ter verificações-alçapão
  -- desarmadas por abortarem diante de estado legítimo do dono: se ele já tiver
  -- baixado a extração para N0, este número é zero e está CERTO.
  raise notice '0126: % estágio(s) interpretativo(s) em N2/N3 com base DECLARADA (não medida). '
               'É o estado real do sistema desde a 0019 — agora consultável em '
               'estagio_autonomia.base_do_nivel.', v_n;
end $$;
