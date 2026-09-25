// As DUAS PONTAS da fixture do book-vertentes descrevem a MESMA extração?
//
// `fixture_book_vertentes.sql` é o que o banco carrega (suítes de `run.sh`);
// `portal/scripts/fixtures/book-vertentes.json` é o que o export lê
// (`verificar-export.mts`). As duas saem de `gerar_fixture.py`, e o CI confere
// que cada uma está igual ao que o gerador emite — mas nada conferia que as duas
// dizem a MESMA coisa. Em 24/09/2026 não diziam: o `.json` gravava `ordem` em
// todas as 767 linhas e o `.sql`, em nenhuma. O banco via a fixture como
// "extração antiga" (`ordem` nula, `migrations/0027`), o export a via ordenada —
// o tipo de defeito que o CLAUDE.md registra em 19/08 ("desincronizar uma faz as
// outras duas mentirem sobre a terceira").
//
// O que se compara: as colunas de CONTEÚDO da extração, linha a linha, na ordem
// em que o gerador as emite. Coluna ausente numa ponta vale null — é o que o
// banco grava por padrão e o que o export lê de um campo que não existe. Ficam
// fora, declarados, só o id sintético do `.json` e os metadados de aceite
// (quem aceitou, quando, de que página), que não mudam número nenhum.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const RAIZ = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const SQL = readFileSync(join(RAIZ, 'Supabase/test/fixture_book_vertentes.sql'), 'utf8');
const JSON_ = JSON.parse(readFileSync(join(RAIZ, 'portal/scripts/fixtures/book-vertentes.json'), 'utf8'));

const CONTEUDO = ['documento_versao_id', 'chave', 'valor_num', 'valor_texto', 'unidade', 'moeda',
  'confianca', 'secao', 'secao_canonica', 'periodo_coluna', 'entidade_coluna', 'ordem', 'status_aceite'];

// Tupla SQL → valores JS. O gerador só emite 'texto' (com '' escapado), número e null.
function tuplas(corpo) {
  const linhas = [];
  let i = 0;
  while (i < corpo.length) {
    if (corpo[i] !== '(') { i++; continue; }
    const vals = [];
    i++;
    while (corpo[i] !== ')') {
      while (corpo[i] === ' ' || corpo[i] === ',') i++;
      if (corpo[i] === "'") {
        let s = '';
        i++;
        for (;;) {
          if (corpo[i] === "'" && corpo[i + 1] === "'") { s += "'"; i += 2; continue; }
          if (corpo[i] === "'") { i++; break; }
          s += corpo[i++];
        }
        vals.push(s);
      } else {
        let t = '';
        while (corpo[i] !== ',' && corpo[i] !== ')') t += corpo[i++];
        t = t.trim();
        vals.push(t === 'null' ? null : Number(t));
      }
    }
    i++;
    linhas.push(vals);
  }
  return linhas;
}

function linhasDoSql() {
  const out = [];
  for (const m of SQL.matchAll(/insert into campo_extraido \(([^)]*)\) values\n([\s\S]*?);\n/g)) {
    const cols = m[1].split(',').map((c) => c.trim());
    for (const vals of tuplas(m[2])) out.push(Object.fromEntries(cols.map((c, k) => [c, vals[k]])));
  }
  return out;
}

test('as duas pontas da fixture do book-vertentes têm as mesmas linhas, na mesma ordem', () => {
  const sql = linhasDoSql();
  // controle positivo: o parser ACHOU as linhas — "0 divergências" sobre 0 linhas
  // seria verde sem ter comparado nada
  assert.ok(sql.length > 700, `o .sql rendeu ${sql.length} linhas — o parser não achou os inserts`);
  assert.equal(sql.length, JSON_.campos.length, 'número de linhas: .sql × .json');
});

for (const col of CONTEUDO) {
  test(`fixture do book-vertentes: .sql e .json concordam em \`${col}\``, () => {
    const sql = linhasDoSql();
    const difs = [];
    sql.forEach((l, k) => {
      const a = l[col] ?? null;
      const b = JSON_.campos[k]?.[col] ?? null;
      if (a !== b) difs.push(`linha ${k} (${l.chave}): .sql=${JSON.stringify(a)} .json=${JSON.stringify(b)}`);
    });
    assert.equal(difs.length, 0, `${difs.length} linha(s) divergem em ${col}; primeiras: ${difs.slice(0, 3).join(' | ')}`);
  });
}
