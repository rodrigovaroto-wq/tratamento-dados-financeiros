// O conferidor em SQL que o dono cola no SQL Editor (`Supabase/conferir/conferir_chamadas.sql`)
// nunca pode dizer "PODE RODAR" sobre uma chamada que ele não conferiu.
//
// A primeira versão do gerador (24/09/2026) emitia só os nós conferíveis e descartava os não
// conferíveis (modo expressão do n8n, consulta com `;`) em silêncio: um workflow com 15 nós e um
// deles em expressão gerava "PODE RODAR — as 14 chamadas". Achado da revisão do PR #244.
//
// O que se afirma é o que o dono LÊ no SQL Editor: com banco declarado (`TESTE_PSQL`, que o
// `suites.yml` define), o `.sql` gerado é EXECUTADO e o veredito é conferido. As consultas usadas
// (`select 1`) resolvem em qualquer banco, então basta um Postgres de pé. Sem `TESTE_PSQL`, o teste
// que executa se declara NÃO CONFERIDO pelo nome (regra 7).
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { execSync } from 'node:child_process';
import { gerarSql } from '../conferir/gerar-conferir-chamadas.mjs';

const TESTE_PSQL = process.env.TESTE_PSQL ?? '';
const semBanco = TESTE_PSQL ? false
  : 'NÃO CONFERIDO: TESTE_PSQL não definida — o .sql gerado não foi executado';
const rodar = (sql) => execSync(`${TESTE_PSQL} -X -q -At -v ON_ERROR_STOP=1`, { input: sql, encoding: 'utf8' });

const conferivel = { arquivo: 'workflow.x.json', no: 'Nó conferível', consulta: 'select 1' };
const emExpressao = { origem: 'N8N/workflow.x.json · nó "Nó em expressão"',
  porque: 'query montada por expressão do n8n — só existe em execução' };

test('o nó não conferível entra no .sql gerado, com o motivo', () => {
  const sql = gerarSql({ nosPostgres: [conferivel], naoConferidos: [emExpressao] });
  assert.ok(sql.includes('Nó em expressão'), 'o nó não conferível sumiu do arquivo');
  assert.ok(sql.includes('só existe em execução'), 'o motivo sumiu do arquivo');
});

test('com um nó não conferido, o veredito NÃO é "PODE RODAR" — é CONFERENCIA INCOMPLETA e o nomeia', { skip: semBanco }, () => {
  const saida = rodar(gerarSql({ nosPostgres: [conferivel], naoConferidos: [emExpressao] }));
  assert.ok(!/PODE RODAR —/.test(saida), `o veredito disse PODE RODAR sobre chamada não conferida:\n${saida}`);
  assert.match(saida, /CONFERENCIA INCOMPLETA/);
  assert.match(saida, /Nó em expressão/);
});

test('controle positivo: tudo conferível e resolvendo, o veredito é PODE RODAR', { skip: semBanco }, () => {
  const saida = rodar(gerarSql({ nosPostgres: [conferivel], naoConferidos: [] }));
  assert.match(saida, /PODE RODAR — as 1 chamadas/);
});
