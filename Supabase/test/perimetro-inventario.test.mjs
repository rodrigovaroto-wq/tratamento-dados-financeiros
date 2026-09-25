// Suíte do inventário do perímetro (fatia 1.1 da F1).
//
// POR QUE ESTA SUÍTE TESTA `classificarCausa` CONTRA UMA FIXTURE REAL, E NÃO INVENTADA (regra 4).
// As 71 descrições em `fixtures/entidade_incorreta_18-09-2026.json` são as pendências
// `entidade_incorreta` ABERTAS em produção, lidas em 18/09/2026 — não um caso sintético escrito
// para caber na régua. Congelá-las como fixture é o que torna a triagem RE-CONFERÍVEL: se alguém
// mudar `classificarCausa` amanhã, esta suíte prova que ela ainda decide as mesmas 71 causas, ou
// aponta exatamente onde divergiu.

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { classificarCausa, normalizarNomeEntidade, CAUSAS_SAO_BUG_DE_COMPARACAO } from './perimetro-inventario.mjs';

const fixture = JSON.parse(
  readFileSync(new URL('./fixtures/entidade_incorreta_18-09-2026.json', import.meta.url), 'utf8'),
);

test('a fixture não está vazia — senão nenhum assert abaixo prova nada (regra 7)', () => {
  assert.equal(fixture.length, 71);
});

test('toda pendência recebe exatamente uma causa — nenhuma cai fora da classificação', () => {
  for (const { descricao } of fixture) {
    const causa = classificarCausa(descricao);
    assert.equal(typeof causa, 'string');
    assert.ok(causa.length > 0);
  }
});

test('a distribuição por causa bate com a medição de 18/09/2026, dígito a dígito', () => {
  // Este é o "veredito congelado": se mudar, é PORQUE a classificação mudou de propósito, e quem
  // mudar atualiza este mapa na mesma passada — exatamente como o grafo.jsonl e as fixtures do
  // book. Não é um número que se ajusta para o teste passar; é o número que o teste EXISTE para
  // proteger.
  const esperado = {
    normalizacao_acento_caixa_sufixo: 20,
    nome_de_arquivo_ou_titulo_virou_entidade: 16,
    apelido_ou_nome_fantasia_com_palavra_em_comum: 12,
    prefixo_comum_truncado: 10,
    sem_relacao_aparente_revisar_manualmente: 4,
    quase_igual_1_2_chars: 3,
    ambigua_ja_correta: 2,
    apelido_curto_sem_mapeamento: 2,
    mojibake: 1,
    fixture_sonda: 1,
  };
  const contagem = {};
  for (const { descricao } of fixture) {
    const causa = classificarCausa(descricao);
    contagem[causa] = (contagem[causa] ?? 0) + 1;
  }
  assert.deepEqual(contagem, esperado);
  const soma = Object.values(esperado).reduce((a, b) => a + b, 0);
  assert.equal(soma, fixture.length, 'a soma das causas tem de bater com o total da fixture');
});

test('nenhuma pendência cai em "residual" — todas casam com o formato conhecido de descrição', () => {
  // Se este assert reprovar no futuro, não é bug do classificador: é sinal de que o TEXTO da
  // pendência mudou de formato em produção, e a suíte está fazendo exatamente o que deveria —
  // acusar em vez de calar (regra 7).
  for (const { descricao } of fixture) {
    assert.notEqual(classificarCausa(descricao), 'residual', descricao);
  }
});

test('bug de comparação é a MINORIA das 71 — a maioria é gap de dado, não defeito de código', () => {
  let bugs = 0;
  for (const { descricao } of fixture) {
    if (CAUSAS_SAO_BUG_DE_COMPARACAO.has(classificarCausa(descricao))) bugs++;
  }
  // 20 (normalização) + 10 (prefixo truncado) + 3 (quase igual) + 1 (mojibake) = 34
  assert.equal(bugs, 34);
});

test('normalizarNomeEntidade ignora acento, caixa e sufixo jurídico — comportamento, não regex', () => {
  assert.equal(normalizarNomeEntidade('Canastra Indústria Ltda.'), normalizarNomeEntidade('CANASTRA INDUSTRIA'));
  assert.equal(normalizarNomeEntidade('Araucária S.A.'), normalizarNomeEntidade('ARAUCARIA'));
});

test('duas empresas do MESMO grupo com nome próximo não colapsam em normalização', () => {
  // ARAUCÁRIA IMOBILIÁRIA SPE × ARAUCÁRIA BIOENERGIA SPE são entidades DIFERENTES — a
  // normalização não pode fundi-las, senão o classificador esconderia uma troca real de empresa.
  assert.notEqual(
    normalizarNomeEntidade('ARAUCÁRIA IMOBILIÁRIA SPE LTDA.'),
    normalizarNomeEntidade('ARAUCÁRIA BIOENERGIA SPE LTDA.'),
  );
});

// --- O executor contra PRODUÇÃO: não escreve, e não vaza a senha ----------------------------------
// Contra um Postgres DE VERDADE, não um psql de mentira: o que se afirma é o comportamento que o
// banco impõe. QUEM TEM BANCO DECLARA: `TESTE_PSQL` definida torna estes testes OBRIGATÓRIOS — e
// banco inalcançável, então, reprova. O `suites.yml` a define (o job tem o serviço postgres:16).
// Sem ela, os dois se declaram NÃO CONFERIDOS pelo nome em vez de passar calados (regra 7).
//
// POR QUE NÃO `process.env.CI`, que foi a primeira versão (24/09/2026): o workflow manual
// `perimetro-inventario.yml` roda este glob no Actions (CI=true) SEM serviço Postgres, e os dois
// testes o deixavam vermelho antes de ele chegar a consultar produção — medido simulando o
// runner: `CI=true PGHOST=127.0.0.1 PGPORT=1` → 39 passam, 2 reprovam. Achado da revisão.
// À mão:
//   TESTE_PSQL="sudo -u postgres psql -h /tmp -p 5432" node --test Supabase/test/perimetro-inventario.test.mjs
import { rodarPsql, NaoConferido } from './perimetro-inventario.mjs';

const TESTE_PSQL = process.env.TESTE_PSQL ?? '';
const semBanco = TESTE_PSQL
  ? false
  : 'NÃO CONFERIDO: TESTE_PSQL não definida — sem banco declarado, o executor não foi posto à prova';

test('o executor lê (controle positivo: sem ele, "recusou escrever" podia ser "não conecta")', { skip: semBanco }, () => {
  assert.deepEqual(rodarPsql('select 41 + 1;', TESTE_PSQL), ['42']);
});

test('o executor NÃO escreve: o Postgres recusa, e a recusa vira NÃO CONFERIDO', { skip: semBanco }, () => {
  assert.throws(
    () => rodarPsql('create temp table _inventario_nao_escreve (a int);', TESTE_PSQL),
    (e) => e instanceof NaoConferido && /read-only|somente leitura|apenas leitura/i.test(e.message),
  );
});

test('falha de conexão sai como NÃO CONFERIDO e a senha da URL não aparece na mensagem', () => {
  const alvo = "psql 'postgresql://usuario:SENHA-QUE-NAO-PODE-VAZAR@127.0.0.1:1/postgres?connect_timeout=2'";
  assert.throws(
    () => rodarPsql('select 1;', alvo),
    (e) => e instanceof NaoConferido && !e.message.includes('SENHA-QUE-NAO-PODE-VAZAR'),
  );
});
