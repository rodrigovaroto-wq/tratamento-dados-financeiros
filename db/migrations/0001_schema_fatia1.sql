-- =============================================================================
-- Migration 0001 — Schema físico da Fatia 1 (E1 — Intake determinístico)
-- Projeto: workflow-operacional-oria (tratamento-dados-financeiros)
-- Materializa o subconjunto de f0/05_schema_conceitual.md necessário para o E1.
-- As tabelas de extração/reconciliação entram nas fatias que as usam.
--
-- Fonte da verdade do estado = Postgres (ver docs/02, trava de stack nº 1).
-- Convenções: snake_case; timestamps em timestamptz; ids uuid.
-- =============================================================================

create extension if not exists "pgcrypto";  -- gen_random_uuid()

-- -----------------------------------------------------------------------------
-- Tipos enumerados (máquinas de estado de f0/04)
-- -----------------------------------------------------------------------------

-- Estado do CASO (f0/04 — máquina de estado do caso)
create type caso_status as enum (
  'intake',
  'em_triagem',
  'completude_ok',
  'em_revisao',
  'aprovado',
  'pronto_para_base',
  'bloqueado',
  'aguardando_cliente'
);

-- Estado do DOCUMENTO/ITEM (f0/04 — completude != validade)
create type documento_status as enum (
  'solicitado',
  'recebido',
  'em_validacao',
  'valido',
  'invalido',
  'recebido_nao_valido',
  'vencido'
);

-- Obrigatoriedade da taxonomia (f0/03 — dois níveis)
create type obrigatoriedade as enum (
  'obrigatorio',   -- Kit Básico
  'complementar'   -- Variáveis
);

-- Sensibilidade LGPD (f0/03 / f0/05)
create type sensibilidade_lgpd as enum (
  'nenhuma',
  'pii',
  'pii_sensivel'
);

-- Granularidade do tipo de documento (f0/03)
create type granularidade as enum (
  'caso',
  'entidade',
  'periodo',
  'entidade_periodo'
);

-- Origem física do arquivo (decisão híbrida 0.2 — dois modos de storage)
create type origem_arquivo as enum (
  'supabase_storage',  -- F1: upload manual em lote
  'sharepoint'         -- fase futura: integração
);

-- Legibilidade (gate de captura, E1)
create type legibilidade as enum (
  'ok',
  'degradado',
  'ilegivel'
);

-- Catálogo de pendências (f0/04)
create type pendencia_tipo as enum (
  'item_faltante',
  'periodo_faltante',
  'item_vencido',
  'arquivo_ilegivel',
  'arquivo_corrompido',
  'entidade_incorreta',
  'periodo_incorreto',
  'tipo_incorreto',
  'classificacao_pendente',       -- nome genérico / baixa confiança na classificação
  'divergencia_reconciliacao',
  'precondicao_nao_satisfeita',
  'extracao_baixa_confianca'
);

create type pendencia_severidade as enum (
  'bloqueante',
  'importante',
  'complementar'
);

create type pendencia_estado as enum (
  'aberta',
  'em_correcao_interna',
  'reenviada_ao_cliente',
  'aceita_com_ressalva',
  'rejeitada',
  'resolvida'
);

-- Nível de autonomia por estágio (Doutrina de Autonomia, docs/01)
create type nivel_autonomia as enum ('N0', 'N1', 'N2', 'N3');

-- Tipo de decisão humana (f0/05)
create type decisao_tipo as enum (
  'aprovacao',
  'override',
  'ressalva',
  'mudanca_dial',
  'correcao_classificacao'
);

-- -----------------------------------------------------------------------------
-- Taxonomia (fonte da verdade; versionada) — f0/03
-- -----------------------------------------------------------------------------
create table taxonomia_tipo_documento (
  codigo             text primary key,               -- estável, usado no runtime
  categoria          text not null,
  documento          text not null,                  -- rótulo legível
  obrigatoriedade    obrigatoriedade not null,
  granularidade      granularidade not null,
  vigencia           text,                            -- janela de validade (texto livre v1)
  sensibilidade      sensibilidade_lgpd not null default 'nenhuma',
  versao             int not null default 1,
  ativo              boolean not null default true    -- deprecar em vez de renomear
);

comment on table taxonomia_tipo_documento is
  'Taxonomia documental v1 (f0/03). Kit Básico = obrigatorio; Variáveis = complementar.';

-- -----------------------------------------------------------------------------
-- Caso / Entidade / Período (unidade de trabalho e eixos) — f0/05
-- -----------------------------------------------------------------------------
create table caso (
  id          uuid primary key default gen_random_uuid(),
  nome        text not null,
  produto     text not null default 'reestruturacao',
  status      caso_status not null default 'intake',
  criado_em   timestamptz not null default now()
);

create table entidade (
  id             uuid primary key default gen_random_uuid(),
  caso_id        uuid not null references caso(id) on delete cascade,
  razao_social   text not null,
  cnpj           text,
  papel_no_grupo text
);
create index idx_entidade_caso on entidade(caso_id);

create table periodo (
  id          uuid primary key default gen_random_uuid(),
  caso_id     uuid not null references caso(id) on delete cascade,
  tipo        text not null,          -- mes | trimestre | ano | data-base | multi
  referencia  text not null,          -- ex.: '12M25', '1T25', 'L24M', '23,24,25'
  unique (caso_id, tipo, referencia)
);
create index idx_periodo_caso on periodo(caso_id);

-- -----------------------------------------------------------------------------
-- Documento + versões — f0/05 (storage em dois modos, decisão 0.2)
-- -----------------------------------------------------------------------------
create table documento (
  id                 uuid primary key default gen_random_uuid(),
  caso_id            uuid not null references caso(id) on delete cascade,
  entidade_id        uuid references entidade(id),
  periodo_id         uuid references periodo(id),
  tipo_taxonomia     text references taxonomia_tipo_documento(codigo),  -- null enquanto não classificado
  status             documento_status not null default 'recebido',
  sensibilidade_lgpd sensibilidade_lgpd not null default 'nenhuma',
  criado_em          timestamptz not null default now()
);
create index idx_documento_caso on documento(caso_id);

create table documento_versao (
  id              uuid primary key default gen_random_uuid(),
  documento_id    uuid not null references documento(id) on delete cascade,
  n_versao        int not null default 1,
  origem_arquivo  origem_arquivo not null default 'supabase_storage',
  arquivo_ref     text not null,          -- path no bucket OU id do item no SharePoint
  nome_original   text,                   -- nome do arquivo enviado (insumo da classificação)
  assinado        boolean,                -- flag (Assinado) da taxonomia (f0/03)
  hash            text,                   -- integridade
  legibilidade    legibilidade,
  criada_em       timestamptz not null default now(),
  unique (documento_id, n_versao)
);
create index idx_docversao_documento on documento_versao(documento_id);

-- -----------------------------------------------------------------------------
-- Checklist de completude (derivado da taxonomia × entidade × período) — f0/04/05
-- -----------------------------------------------------------------------------
create table checklist_item_status (
  id              uuid primary key default gen_random_uuid(),
  caso_id         uuid not null references caso(id) on delete cascade,
  entidade_id     uuid references entidade(id),
  periodo_id      uuid references periodo(id),
  tipo_taxonomia  text not null references taxonomia_tipo_documento(codigo),
  obrigatoriedade obrigatoriedade not null,
  status          text not null default 'faltante',  -- faltante | presente | vencido | invalido
  documento_id    uuid references documento(id),     -- documento que satisfez o item (se houver)
  atualizado_em   timestamptz not null default now()
);
create index idx_checklist_caso on checklist_item_status(caso_id);

-- -----------------------------------------------------------------------------
-- Motor de pendências — f0/04
-- -----------------------------------------------------------------------------
create table pendencia (
  id              uuid primary key default gen_random_uuid(),
  caso_id         uuid not null references caso(id) on delete cascade,
  origem_estagio  text,                    -- 'completude' | 'gate_captura' | 'validacao_formal' | ...
  tipo            pendencia_tipo not null,
  severidade      pendencia_severidade not null,
  estado          pendencia_estado not null default 'aberta',
  descricao       text,
  documento_id    uuid references documento(id),
  entidade_id     uuid references entidade(id),
  periodo_id      uuid references periodo(id),
  sobrepujavel    boolean not null default true,   -- false = bloqueante não-sobrepujável (f0/04)
  expira_em       timestamptz,                     -- ressalva com data de expiração
  motivo          text,
  criada_em       timestamptz not null default now(),
  resolvida_em    timestamptz,
  resolvida_por   text
);
create index idx_pendencia_caso on pendencia(caso_id);
create index idx_pendencia_estado on pendencia(estado);

-- -----------------------------------------------------------------------------
-- Decisões humanas (append-only por convenção) — f0/05
-- -----------------------------------------------------------------------------
create table decisao (
  id          uuid primary key default gen_random_uuid(),
  caso_id     uuid not null references caso(id) on delete cascade,
  tipo        decisao_tipo not null,
  autor       text not null,
  criado_em   timestamptz not null default now(),
  motivo      text,
  payload     jsonb                       -- ex.: {de: 'BALANCO', para: 'DRE'} numa correção
);
create index idx_decisao_caso on decisao(caso_id);

-- -----------------------------------------------------------------------------
-- Trilha de auditoria (append-only, imutável) — f0/05, docs/01 fechamento 7
-- -----------------------------------------------------------------------------
create table evento_auditoria (
  id            uuid primary key default gen_random_uuid(),
  criado_em     timestamptz not null default now(),
  ator          text not null,             -- usuário ou 'sistema:n8n'
  acao          text not null,
  entidade_ref  text,                      -- 'documento:<id>' | 'caso:<id>' | ...
  antes         jsonb,
  depois        jsonb
);
create index idx_evento_entidade_ref on evento_auditoria(entidade_ref);

-- -----------------------------------------------------------------------------
-- Dial de autonomia por estágio (config) — docs/01, f0/04
-- -----------------------------------------------------------------------------
create table estagio_autonomia (
  estagio        text primary key,
  nivel_atual    nivel_autonomia not null,
  teto           nivel_autonomia not null,
  atualizado_por text,
  atualizado_em  timestamptz not null default now()
);

comment on table estagio_autonomia is
  'O "dial" de autonomia por estágio. Nível é estado do sistema, não constante de código (docs/01).';
