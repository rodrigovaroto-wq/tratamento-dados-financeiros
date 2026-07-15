# Camada de banco (Supabase / Postgres) — Fatia 1

Materializa o schema conceitual (`f0/05_schema_conceitual.md`) no Postgres do Supabase, no
subconjunto necessário para a **Fatia 1 (E1 — Intake determinístico)** da F1.

> **Fonte da verdade do estado = Postgres** (ver `docs/02`, trava de stack nº 1). O N8N é
> stateless; o portal Vercel lê/escreve via camada que respeita RLS.

## Migrations (aplicar nesta ordem)

| Arquivo | O que faz |
|---|---|
| `migrations/0001_schema_fatia1.sql` | Tipos enumerados (máquinas de estado de `f0/04`) + tabelas: `caso`, `entidade`, `periodo`, `taxonomia_tipo_documento`, `documento`, `documento_versao`, `checklist_item_status`, `pendencia`, `decisao`, `evento_auditoria`, `estagio_autonomia`. |
| `migrations/0002_seed_taxonomia_e_dial.sql` | Seed da taxonomia v1 (`f0/03`: Kit Básico + Variáveis) e do dial de autonomia inicial (`f0/04`). Idempotente. |
| `migrations/0003_rls_e_storage.sql` | RLS por tabela + bucket privado `documentos` no Storage. |

## Como aplicar

**Opção A — Supabase CLI (recomendado):**
```bash
supabase db push
# ou aplicar arquivo a arquivo:
supabase db execute --file db/migrations/0001_schema_fatia1.sql
supabase db execute --file db/migrations/0002_seed_taxonomia_e_dial.sql
supabase db execute --file db/migrations/0003_rls_e_storage.sql
```

**Opção B — psql direto** (usar o **Session Pooler**; herdar a pegadinha do `clipping-news`:
IPv4 + SSL, usuário do pooler com sufixo `.projectref`):
```bash
psql "$SUPABASE_DB_URL" -f db/migrations/0001_schema_fatia1.sql
psql "$SUPABASE_DB_URL" -f db/migrations/0002_seed_taxonomia_e_dial.sql
psql "$SUPABASE_DB_URL" -f db/migrations/0003_rls_e_storage.sql
```

## Notas de segurança (LGPD) — ler antes de conectar clientes

- **service_role ignora RLS** (é o que o N8N usa como orquestrador). O portal Vercel **nunca**
  deve usar a service_role — só chave `anon`/`authenticated`, que respeita RLS.
- Bucket `documentos` é **privado**; nunca gerar URL pública — usar signed URLs.
- **TODO de fatia posterior:** restringir RLS por caso (membership) e reforço para documentos
  `pii_sensivel` (`DOCS_SOCIOS`, `AVAIS_FIANCAS`, `HEADCOUNT`).

## Verificação rápida (após aplicar)

```sql
-- Taxonomia populada? (esperado: 8 obrigatórios do Kit Básico)
select obrigatoriedade, count(*) from taxonomia_tipo_documento group by obrigatoriedade;

-- Dial de autonomia inicial? (esperado: 8 estágios)
select estagio, nivel_atual, teto from estagio_autonomia order by estagio;

-- RLS ligado em todas as tabelas de dados?
select relname, relrowsecurity from pg_class
where relname in ('caso','documento','pendencia','evento_auditoria') order by relname;
```

## O que NÃO está aqui (entra em fatias seguintes)

`campo_extraido` (extração E2), `reconciliacao` (E3) e o refinamento de RLS por caso. Ver o
plano da F1 e `f0/05_schema_conceitual.md`.
