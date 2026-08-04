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

# A LISTA DE COMANDOS DO db/README.md É O QUE O DONO COPIA PARA APLICAR.
#
# O CLAUDE.md chama esse arquivo de "ordem oficial de aplicação", e o próprio
# README já narra o estrago de ele ficar atrás: treze migrations (0032→0044)
# nunca entraram na lista, e quem aplicasse seguindo-a pararia na 0031 com um
# banco "sem Portão 2, sem catálogo de premissas, sem papel da linha — sem nenhum
# erro, só faltando".
#
# ACONTECEU DE NOVO, e desta vez custou uma rodada de produção: a `0101` entrou na
# TABELA do README e **não** na lista de comandos. O dono mergeou o PR, aplicou o
# que a lista mandava, e a tela de Modelagem continuou mostrando o mesmo defeito —
# porque a correção nunca chegou ao banco. Da tela, "aplicada" e "não aplicada"
# têm exatamente a mesma aparência.
#
# Escrever migration e esquecer de listá-la é um erro silencioso de UMA linha, e é
# o único passo entre "corrigido no git" e "corrigido em produção". Aqui ele para
# de ser silencioso.
echo "== o db/README.md lista todas as migrations"
faltando=""
for f in db/migrations/*.sql; do
  grep -qF "$f" db/README.md || faltando="$faltando $f"
done
if [ -n "$faltando" ]; then
  echo "FALHOU: migration que existe e o db/README.md não manda aplicar:"
  for f in $faltando; do echo "     - $f"; done
  echo "   Acrescente 'supabase db execute --file <arquivo>' na lista de comandos do db/README.md."
  echo "   Sem isso o dono aplica o que a lista diz, a correção não chega ao banco, e a tela"
  echo "   mostra o defeito antigo como se o PR não tivesse funcionado."
  exit 1
fi
echo "   as $(ls db/migrations/*.sql | wc -l) migrations estão na lista de aplicação"

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
echo "== testes de moeda por linha (0035: o último fator multiplicativo invisível)"
psql -v ON_ERROR_STOP=1 -d "$DB" -f db/test/moeda.test.sql 2>&1 \
  | grep -E '^(NOTICE|ERROR|psql)' | sed -E 's/^NOTICE:  //'

echo
echo "== testes de completude vs conteúdo (0036: chegou vazio não cumpre item)"
psql -v ON_ERROR_STOP=1 -d "$DB" -f db/test/completude_conteudo.test.sql 2>&1 \
  | grep -E '^(NOTICE|ERROR|psql)' | sed -E 's/^NOTICE:  //'

echo
echo "== testes do Portão 2 por caso (0037: a regra de f0/04 virou código)"
psql -v ON_ERROR_STOP=1 -d "$DB" -f db/test/portao2.test.sql 2>&1 \
  | grep -E '^(NOTICE|ERROR|psql)' | sed -E 's/^NOTICE:  //'

echo
echo "== testes do catálogo de premissas e da modelagem por caso (0038)"
psql -v ON_ERROR_STOP=1 -d "$DB" -f db/test/premissas.test.sql 2>&1 \
  | grep -E '^(NOTICE|ERROR|psql)' | sed -E 's/^NOTICE:  //'

echo
echo "== testes do papel da linha (0042: subtotal/serie mensal/derivado não se projetam)"
psql -v ON_ERROR_STOP=1 -d "$DB" -f db/test/papel_da_linha.test.sql 2>&1 \
  | grep -E '^(NOTICE|ERROR|psql)' | sed -E 's/^NOTICE:  //'

echo
echo "== testes do papel POR SEÇÃO (0100: guarda e tela concordam; lote não cai inteiro)"
psql -v ON_ERROR_STOP=1 -d "$DB" -f db/test/papel_por_secao.test.sql 2>&1 \
  | grep -E '^(NOTICE|ERROR|psql)' | sed -E 's/^NOTICE:  //'

echo
echo "== testes de ESCALA da modelagem (0101: cabe no statement_timeout do Supabase)"
psql -v ON_ERROR_STOP=1 -d "$DB" -f db/test/modelagem_escala.test.sql 2>&1 \
  | grep -E '^(NOTICE|ERROR|psql)' | sed -E 's/^NOTICE:  //'

echo
echo "== testes da Modelagem contra o caso REAL de produção (0102: versão vigente; rótulo real)"
psql -v ON_ERROR_STOP=1 -d "$DB" -f db/test/modelagem_v35.test.sql 2>&1 \
  | grep -E '^(NOTICE|ERROR|psql)' | sed -E 's/^NOTICE:  //'

echo
echo "== testes de reconferir (0043: reaplicar as regras de hoje sobre o dado gravado)"
psql -v ON_ERROR_STOP=1 -d "$DB" -f db/test/reconferir.test.sql 2>&1 \
  | grep -E '^(NOTICE|ERROR|psql)' | sed -E 's/^NOTICE:  //'

echo
echo "== testes do dial de autonomia (0041: o dial passa a mandar no auto-aceite)"
psql -v ON_ERROR_STOP=1 -d "$DB" -f db/test/dial.test.sql 2>&1 \
  | grep -E '^(NOTICE|ERROR|psql)' | sed -E 's/^NOTICE:  //'

echo
echo "== carga inicial dos índices macro (dado real, versionado)"
psql -q -v ON_ERROR_STOP=1 -d "$DB" -f db/seed/macro_carga_inicial.sql >/dev/null
psql -v ON_ERROR_STOP=1 -d "$DB" -f db/test/seed_macro.test.sql 2>&1 \
  | grep -E '^(NOTICE|ERROR|psql)' | sed -E 's/^NOTICE:  //'

echo
echo "TODOS OS TESTES PASSARAM"
