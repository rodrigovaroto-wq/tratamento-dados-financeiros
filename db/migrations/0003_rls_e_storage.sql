-- =============================================================================
-- Migration 0003 — RLS + Storage (Fatia 1)
--
-- Contexto de segurança (docs/02 §"três travas de stack", f0/05 política LGPD):
--   - RLS LIGADO sem policy tranca tudo. Toda tabela exposta ao portal precisa
--     de policy explícita.
--   - PEGADINHA HERDADA DO clipping-news: a conexão direta do N8N (service_role
--     ou conexão Postgres direta) IGNORA RLS por design — é o orquestrador.
--     O portal (Vercel) NUNCA deve usar a service_role; acessa via chave
--     anon/authenticated (PostgREST), que RESPEITA RLS.
--
-- Escopo da F1 (ferramenta interna, um time): policy = usuário autenticado tem
-- acesso. Restrição por-caso e reforço para PII sensível são refinamento de
-- fatia posterior (marcado abaixo).
-- =============================================================================

-- -----------------------------------------------------------------------------
-- Habilitar RLS em todas as tabelas de dados
-- -----------------------------------------------------------------------------
alter table caso                     enable row level security;
alter table entidade                 enable row level security;
alter table periodo                  enable row level security;
alter table documento                enable row level security;
alter table documento_versao         enable row level security;
alter table checklist_item_status    enable row level security;
alter table pendencia                enable row level security;
alter table decisao                  enable row level security;
alter table evento_auditoria         enable row level security;
alter table estagio_autonomia        enable row level security;
alter table taxonomia_tipo_documento enable row level security;

-- -----------------------------------------------------------------------------
-- Policies F1 — acesso para usuário autenticado (time interno)
-- Nota: a service_role do N8N ignora RLS (não precisa de policy).
-- -----------------------------------------------------------------------------
do $$
declare
  t text;
begin
  foreach t in array array[
    'caso','entidade','periodo','documento','documento_versao',
    'checklist_item_status','pendencia','decisao','estagio_autonomia'
  ]
  loop
    execute format($f$
      create policy %1$I_authenticated_all on %1$I
        for all to authenticated using (true) with check (true);
    $f$, t);
  end loop;
end$$;

-- Taxonomia: leitura para todos os autenticados; escrita reservada (seed/admin
-- via service_role). Portal só lê a taxonomia.
create policy taxonomia_read on taxonomia_tipo_documento
  for select to authenticated using (true);

-- Trilha de auditoria: APPEND-ONLY também na camada de acesso do portal.
-- Autenticado pode inserir e ler; nunca update/delete (imutável — docs/01 nº 7).
create policy evento_auditoria_insert on evento_auditoria
  for insert to authenticated with check (true);
create policy evento_auditoria_read on evento_auditoria
  for select to authenticated using (true);

-- TODO (fatia posterior): restringir por caso (membership) e adicionar policy
-- extra para documentos PII sensível (só papéis autorizados) — f0/05.

-- -----------------------------------------------------------------------------
-- Storage — bucket privado para os arquivos (upload manual da F1)
-- -----------------------------------------------------------------------------
insert into storage.buckets (id, name, public)
values ('documentos', 'documentos', false)
on conflict (id) do nothing;

-- Acesso ao bucket privado só para autenticados (nunca URL pública — f0/05).
create policy documentos_authenticated_all on storage.objects
  for all to authenticated
  using (bucket_id = 'documentos')
  with check (bucket_id = 'documentos');
