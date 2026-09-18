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
import { readFileSync } from 'node:fs';
import { interpretar } from './sonda-producao.mjs';

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
