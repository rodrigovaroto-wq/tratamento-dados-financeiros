// Suíte da sonda contra produção.
//
// POR QUE ELA EXISTE, e por que ela testa `interpretar()` e não o `psql`. Este portão vai rodar
// AGENDADO, contra um banco que esta suíte não tem — então o que dá para provar aqui é a única
// parte que decide alguma coisa: a tradução de (configuração, código de saída, saída) em
// veredito. E é justamente aí que mora o defeito que ele existe para não cometer: **colapsar
// "não consegui perguntar" em "está tudo bem"**.
//
// As três situações abaixo têm de produzir TRÊS códigos diferentes. Se duas delas convergirem, o
// portão vira decoração — e a decoração é indistinguível do portão que funciona (regra 7).

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync, existsSync as existe } from 'node:fs';
import { join as juntar } from 'node:path';
import { interpretar, migracoesEsperadas, chavesGravadas } from './sonda-producao.mjs';

test('sem configuração NUNCA vira verde — é ausência de medição, não ausência de problema', () => {
  const r = interpretar({ configurado: false });
  assert.equal(r.codigo, 2);
  assert.match(r.mensagem, /NÃO CONFERIDO/);
  assert.match(r.mensagem, /NÃO é "produção está em dia"/);
});

test('conexão que não subiu também é 2, não 0 — a pergunta não chegou', () => {
  const r = interpretar({ configurado: true, status: 2, saida: '', stderr: 'could not connect to server' });
  assert.equal(r.codigo, 2);
  assert.match(r.mensagem, /não chegou ao banco/);
});

test('produção sem ausência nenhuma é o único caminho para o 0', () => {
  assert.equal(interpretar({ configurado: true, status: 0, saida: '\n  \n', stderr: '' }).codigo, 0);
});

test('ausência no catálogo reprova, e cada linha aparece no relatório', () => {
  const saida = [
    'fn_reconciliar_caso|0158|funcao|fn_reconciliar_caso|assinatura antiga|a 0158 endurece o pronto',
    'premissa_do_realizado|0161|tabela|premissa_do_realizado||',
  ].join('\n');
  const r = interpretar({ configurado: true, status: 0, saida, stderr: '' });
  assert.equal(r.codigo, 1);
  assert.match(r.mensagem, /2 ausência\(s\)/);
  assert.match(r.mensagem, /fn_reconciliar_caso/);
  assert.match(r.mensagem, /premissa_do_realizado/);
});

test('o servidor responder ERRO é achado (1), não falta de medição (2)', () => {
  // O caso real: produção anterior à migration que criou a própria sonda. Ela não consegue se
  // autodiagnosticar, e isso é um resultado — não um "não sei".
  const r = interpretar({
    configurado: true,
    status: 3,
    saida: '',
    stderr: 'psql:<stdin>:2: ERROR:  function fn_instalacao_conferir() does not exist',
  });
  assert.equal(r.codigo, 1);
  assert.match(r.mensagem, /does not exist/);
  assert.match(r.mensagem, /anterior à migration que criou a sonda/);
});

test('o erro do servidor é lido pelo CÓDIGO DE SAÍDA, não pelo idioma da mensagem', () => {
  // `ERROR:` traduzido (`ERRO:` num servidor pt_BR) já quebrou um portão irmão. O discriminador é
  // o status 3; o texto serve só para mostrar ao humano.
  const r = interpretar({ configurado: true, status: 3, saida: '', stderr: 'psql: ERRO:  função não existe' });
  assert.equal(r.codigo, 1);
  assert.match(r.mensagem, /função não existe/);
});

test('a URL com senha nunca aparece no relatório', () => {
  // `erro.message` do execSync começa com a linha de comando inteira. Só o stderr do psql sai.
  const r = interpretar({
    configurado: true,
    status: 2,
    saida: '',
    stderr: 'connection to server failed',
  });
  assert.doesNotMatch(r.mensagem, /postgresql:\/\/[^\s]*:[^\s]*@/);
});

test('o segredo que a mensagem manda cadastrar é o que o workflow lê', () => {
  // POR QUE ESTE INVARIANTE EXISTE, e o defeito que ele descobriu em 18/09/2026. A mensagem dizia
  // `SONDA_PSQL_URL` e `sonda-producao.yml` lia `SONDA_DB_URL`. Quem seguisse a instrução
  // cadastraria o nome errado; o workflow continuaria vermelho dizendo "não cadastrado", e a
  // leitura natural disso — "cadastrei, então o portão é que está quebrado" — é o pior desfecho
  // possível para um portão cuja razão de ser é NÃO ficar verde sem ter perguntado (regra 7).
  //
  // E o portão afirma COMPORTAMENTO, não o literal (regra 3): ele não fixa a string
  // `SONDA_DB_URL`, ele exige que a mensagem cite o nome que o workflow de fato lê. Renomear o
  // segredo nos dois lugares continua passando; renomear em um só reprova.
  const yml = readFileSync(
    new URL('../../.github/workflows/sonda-producao.yml', import.meta.url),
    'utf8',
  );
  const nomes = [...yml.matchAll(/secrets\.([A-Z0-9_]+)/g)].map((m) => m[1]);
  assert.ok(nomes.length > 0, 'o workflow não lê segredo nenhum — o invariante nasceria vazio');
  const distintos = [...new Set(nomes)];
  assert.equal(
    distintos.length,
    1,
    `o workflow lê mais de um segredo (${distintos.join(', ')}) e a mensagem cita um só`,
  );
  const { mensagem } = interpretar({ configurado: false });
  assert.match(mensagem, new RegExp(`\\b${distintos[0]}\\b`));
});

// --- O BURACO NO MEIO (PR #238, 23/09/2026) -------------------------------------------------------
// MEDIDO em produção antes de aplicar a 0182: `ate_migration = 0188`, 132 requisitos, 0 ausentes — e
// a 0182/0183 fora. Uma migration que nunca rodou não deixa requisito para acusar.
//
// A PRIMEIRA VERSÃO DESTES TESTES ERA CIRCULAR, e é por isso que eles estão assim agora. Ela montava
// "produção" como `ESPERADAS.filter(n <= '0181') + [0186, 0187, 0188]` — ou seja, a partir da saída da
// própria função testada — e afirmava "o buraco é exatamente [0182, 0183]". Verdade por construção:
// todo falso positivo até a 0181 ficava invisível. A revisão independente mediu o que ela escondia:
// contra um banco com TODAS as migrations aplicadas, o critério antigo acusava 0163 e 0171.
//
// Por isso a divisão de trabalho é explícita: ESTES testes provam a ESTRUTURA com os arquivos reais
// (o parser de chaves e o critério de dono final nos dois casos que derrubaram a primeira versão) e a
// integração do veredito. O CONTROLE POSITIVO contra dado real — banco completo tem de dar zero
// buracos — é do passo do CI "A sonda do buraco no meio não dá alarme falso num banco completo",
// porque só lá existe um banco completo para perguntar.
const RAIZ_REPO = new URL('../..', import.meta.url).pathname.replace(/\/$/, '');
const lerMig = (arq) => {
  const c = juntar(RAIZ_REPO, 'Supabase/migrations', arq);
  return existe(c) ? readFileSync(c, 'utf8') : null;
};
const ESPERADAS_REAIS = migracoesEsperadas(readFileSync(juntar(RAIZ_REPO, 'Supabase/README.md'), 'utf8'), lerMig);
const arquivoDe = (n) => readdirSync(juntar(RAIZ_REPO, 'Supabase/migrations')).find((f) => f.startsWith(n + '_'));

test('a lista esperada sai do README: inclui as da F1.7 e exclui a migration comentada (0185)', () => {
  assert.ok(ESPERADAS_REAIS.includes('0182') && ESPERADAS_REAIS.includes('0183'), ESPERADAS_REAIS.join(','));
  assert.ok(!ESPERADAS_REAIS.includes('0185'), 'a 0185 está comentada no README — não deve ser esperada');
});

test('migration que só cataloga OUTRA migration não é esperada no catálogo com o próprio número (0163)', () => {
  // A 0163 grava requisitos com os números '0161' e '0162' — nunca com o próprio. O '0163' dela está
  // só no `set ate_migration`, e foi isso que enganou a primeira versão.
  const numeros = new Set(chavesGravadas(lerMig(arquivoDe('0163'))).map((c) => c.migration));
  assert.ok(numeros.size > 0, 'o parser não leu nenhuma chave da 0163 — o teste abaixo não provaria nada');
  assert.ok(!numeros.has('0163'), `a 0163 grava ${[...numeros].join(', ')}`);
  assert.ok(!ESPERADAS_REAIS.includes('0163'));
});

test('migration cuja chave foi REETIQUETADA por uma posterior não é esperada (0171 → 0173)', () => {
  const da0173 = chavesGravadas(lerMig(arquivoDe('0173'))).find((c) => c.chave === 'cnpj_renomeia');
  assert.equal(da0173?.migration, '0173', 'a 0173 regrava cnpj_renomeia com o próprio número');
  assert.ok(!ESPERADAS_REAIS.includes('0171'), 'num banco completo a 0171 some do catálogo — esperá-la é alarme falso');
});

test('buraco no meio reprova MESMO com zero ausências no catálogo — era o caso real', () => {
  const r = interpretar({
    configurado: true, status: 0, saida: '', stderr: '',
    esperadas: ['0181', '0182', '0183', '0186'], migracoesNoBanco: ['0181', '0186'],
  });
  assert.equal(r.codigo, 1);
  assert.match(r.mensagem, /0182, 0183/);
});

test('sem as listas, o verde DIZ que o buraco não foi conferido — nunca o omite', () => {
  const r = interpretar({ configurado: true, status: 0, saida: '', stderr: '' });
  assert.equal(r.codigo, 0);
  assert.match(r.mensagem, /BURACO NO MEIO NÃO FOI CONFERIDO/);
});
