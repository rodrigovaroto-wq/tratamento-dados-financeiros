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

# Supabase configura isto UMA VEZ, na criação do projeto — e nenhuma migration
# deste repositório faz GRANT de tabela (nem precisa) porque conta com isso.
# É por isso que um defeito de AUTORIZAÇÃO nunca tinha sido pego por teste
# nenhum aqui: sem replicar este passo, `set role authenticated` falharia para
# QUALQUER tabela, não só a que tem o bug — o teste acusaria falso positivo em
# geral, então ninguém testava como authenticated. Achado real:
# db/migrations/0028 (índices macro sem RLS nem grant).
#
# Função é DIFERENTE de tabela, e não replicamos o lado de função aqui — de
# propósito, depois de medir. Em produção o Supabase impede EXECUTE público em
# função nova (é por isso que este projeto já tem, desde a sessão 8, `grant
# execute ... to authenticated` explícito em toda função chamada PELO PORTAL:
# 0008 `fn_revisar_documento`, 0011 `fn_aceitar_extracao`, 0028
# `fn_indice_macro_anual`). Tentei replicar isso aqui com `alter default
# privileges ... revoke execute on functions from public` e MEDI que não
# funciona neste Postgres: a revoke não grava linha em `pg_default_acl` (objtype
# 'f') e função criada depois continua executável por PUBLIC — plain Postgres
# não tem como REVOGAR um default que nunca foi GRANTado por default privilege
# (o hardcoded "PUBLIC pode executar" não passa por ali). O mecanismo real do
# Supabase para isso não é `ALTER DEFAULT PRIVILEGES` puro. Por isso os `grant
# execute` em migration continuam sendo o único jeito CORRETO de garantir o
# acesso em produção — só não dá para provar aqui, com teste local, que a
# ausência deles quebraria (o teste da 0028 exercita a chamada como smoke test,
# não como negativo).
psql -q -d "$DB" -c "
  grant usage on schema public to anon, authenticated, service_role;
  alter default privileges in schema public grant all on tables to anon, authenticated, service_role;
  alter default privileges in schema public grant all on sequences to anon, authenticated, service_role;"

# Duas migrations com o MESMO prefixo não geram conflito de merge — o git aceita
# `0035_a.sql` e `0035_b.sql` de branches diferentes sem uma palavra, e o laço
# abaixo aplica as duas na ordem alfabética do SUFIXO. A ordem oficial de
# aplicação (`db/README.md`) passa a mentir em silêncio, e nada acusa. É por isso
# que a checagem existe, e é por isso que ela vem ANTES de aplicar qualquer coisa:
# com duas pessoas no repositório (faixas em `CLAUDE.md`), colisão é questão de
# tempo, e o lugar de morrer é o PR, não o banco de produção.
#
# BURACO na sequência é LEGÍTIMO e não reprova: as faixas reservam 0035-0099 ao
# dono, então 0034 → 0100 é o estado esperado, não um erro.
echo "== numeração das migrations"
dup=$(for f in db/migrations/*.sql; do basename "$f" | cut -c1-4; done | sort | uniq -d)
if [ -n "$dup" ]; then
  echo "FALHOU: prefixo de migration duplicado — cada número tem de ser único."
  for n in $dup; do
    echo "   $n:"
    for f in db/migrations/"$n"*.sql; do echo "     - $f"; done
  done
  echo "   Renumere a mais nova respeitando as faixas de CLAUDE.md (dono 0035-0099, estagiário 0100+)."
  exit 1
fi
echo "   sem prefixo duplicado"

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
echo "== testes de reextração (idempotência por hash)"
psql -v ON_ERROR_STOP=1 -d "$DB" -f db/test/reextracao.test.sql 2>&1 \
  | grep -E '^(NOTICE|ERROR|psql)' | sed -E 's/^NOTICE:  //'

echo
echo "== testes de canonicalização (entidade e período no caminho de escrita)"
psql -v ON_ERROR_STOP=1 -d "$DB" -f db/test/canonico.test.sql 2>&1 \
  | grep -E '^(NOTICE|ERROR|psql)' | sed -E 's/^NOTICE:  //'

echo
echo "== carga inicial dos índices macro (dado real, versionado)"
psql -q -v ON_ERROR_STOP=1 -d "$DB" -f db/seed/macro_carga_inicial.sql >/dev/null
psql -v ON_ERROR_STOP=1 -d "$DB" -f db/test/seed_macro.test.sql 2>&1 \
  | grep -E '^(NOTICE|ERROR|psql)' | sed -E 's/^NOTICE:  //'

echo
echo "TODOS OS TESTES PASSARAM"
