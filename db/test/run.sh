#!/usr/bin/env bash
# Aplica as migrations num Postgres local, carrega o fixture do book Vertentes e
# roda os testes de reconciliação.
#
#   db/test/run.sh                     # usa um Postgres já rodando (PGHOST/PGPORT/PGUSER)
#   PGPORT=5599 db/test/run.sh         # porta alternativa
#
# Precisa de um Postgres 16 acessível e de permissão para criar banco. Não toca
# em Supabase — é tudo local e descartável (o banco é recriado a cada execução).
set -euo pipefail

DB="${TEST_DB:-tdf_test}"
RAIZ="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$RAIZ"

psql -q -c "drop database if exists $DB" -c "create database $DB"

# Papéis e schema que o Supabase provê por padrão e as migrations assumem.
for r in anon authenticated service_role; do
  psql -tAc "select 1 from pg_roles where rolname='$r'" | grep -q 1 \
    || psql -q -c "create role $r nologin"
done
psql -q -d "$DB" -c "
  create schema if not exists storage;
  create table if not exists storage.buckets(id text primary key, name text, public boolean default false);
  create table if not exists storage.objects(id uuid default gen_random_uuid() primary key,
    bucket_id text, name text, owner uuid);
  alter table storage.objects enable row level security;" >/dev/null

echo "== migrations"
for f in db/migrations/*.sql; do
  if ! out=$(psql -q -v ON_ERROR_STOP=1 -d "$DB" -f "$f" 2>&1); then
    echo "FALHOU $f"; echo "$out" | head -20; exit 1
  fi
done
echo "   $(ls db/migrations/*.sql | wc -l) migrations aplicadas"

echo "== fixture (book Vertentes, extração fiel dos 14 documentos)"
psql -q -v ON_ERROR_STOP=1 -d "$DB" -f db/test/fixture_book_vertentes.sql

echo "== testes de reconciliação"
psql -v ON_ERROR_STOP=1 -d "$DB" -f db/test/reconciliacao.test.sql 2>&1 \
  | grep -E '^(NOTICE|ERROR|psql)' | sed -E 's/^NOTICE:  //'

echo
echo "== testes de índices macro"
psql -v ON_ERROR_STOP=1 -d "$DB" -f db/test/macro.test.sql 2>&1 \
  | grep -E '^(NOTICE|ERROR|psql)' | sed -E 's/^NOTICE:  //'

echo
echo "TODOS OS TESTES PASSARAM"
