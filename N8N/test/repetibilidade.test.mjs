import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import {
  compararExtracoes, mensagemRepetibilidade, documentoAmostradoParaRepetibilidade,
  FRACAO_AMOSTRA_REPETIBILIDADE, MAX_DIVERGENCIAS_REPETIBILIDADE,
} from '../lib/repetibilidade.mjs';

// A trava determinística — repetibilidade, não correção. Ver o cabeçalho de
// `lib/repetibilidade.mjs` para o porquê. Estes testes exercitam a função PURA
// isolada; `workflow-sim.test.mjs` exercita o CÓDIGO GERADO (a fronteira do
// `toString()` só quebra lá, nunca aqui — ver a nota "AUTO-CONTIDAS" no arquivo).

const linha = (over = {}) => ({
  secao: 'ativo_circulante', chave: 'Caixa', entidade_coluna: null, periodo_coluna: '2024',
  valor_texto: '380', valor_num: 380, unidade: null, moeda: 'BRL', ...over,
});

test('compararExtracoes: extrações IDÊNTICAS não divergem em nada', () => {
  const a = [linha(), linha({ chave: 'Bancos', valor_texto: '50', valor_num: 50 })];
  const b = [linha(), linha({ chave: 'Bancos', valor_texto: '50', valor_num: 50 })];
  const r = compararExtracoes(a, b);
  assert.equal(r.linhasDivergentes, 0);
  assert.equal(r.linhasIguais, 2);
  assert.equal(r.divergencias.length, 0);
  assert.equal(r.chavesComparadas, 2);
});

test('compararExtracoes: TOLERÂNCIA ZERO — valor levemente diferente é divergência, não é arredondado', () => {
  const a = [linha({ valor_num: 380 })];
  const b = [linha({ valor_num: 380.01 })];
  const r = compararExtracoes(a, b);
  assert.equal(r.linhasDivergentes, 1);
  assert.equal(r.linhasIguais, 0);
  assert.equal(r.divergencias[0].tipo, 'valor_diferente');
  assert.deepEqual(r.divergencias[0].campos, ['valor_num']);
});

test('compararExtracoes: regra 1 do CLAUDE.md — null numa passada e 0 na outra é DIVERGÊNCIA, não empate', () => {
  const a = [linha({ valor_num: null, valor_texto: null })];
  const b = [linha({ valor_num: 0, valor_texto: '0' })];
  const r = compararExtracoes(a, b);
  assert.equal(r.linhasDivergentes, 1, 'null e 0 tratados como iguais seria apresentar ausência como dado');
  assert.equal(r.linhasIguais, 0);
  assert.deepEqual(r.divergencias[0].campos, ['valor_num']);
});

test('compararExtracoes: linha presente numa passada e ausente na outra', () => {
  const a = [linha(), linha({ chave: 'Bancos', valor_num: 50, valor_texto: '50' })];
  const b = [linha()];
  const r = compararExtracoes(a, b);
  assert.equal(r.linhasIguais, 1);
  assert.equal(r.linhasDivergentes, 1);
  assert.equal(r.divergencias[0].tipo, 'ausente_na_segunda_passada');
  assert.equal(r.divergencias[0].a.chave, 'Bancos');
  assert.equal(r.divergencias[0].b, null);

  const r2 = compararExtracoes([linha()], [linha(), linha({ chave: 'Bancos', valor_num: 50 })]);
  assert.equal(r2.divergencias[0].tipo, 'ausente_na_primeira_passada');
});

test('compararExtracoes: mesma chave, unidade ou moeda diferente (valor igual) — ainda diverge', () => {
  const rUnidade = compararExtracoes(
    [linha({ unidade: 'milhares' })], [linha({ unidade: null })],
  );
  assert.equal(rUnidade.linhasDivergentes, 1);
  assert.deepEqual(rUnidade.divergencias[0].campos, ['unidade']);

  const rMoeda = compararExtracoes([linha({ moeda: 'BRL' })], [linha({ moeda: 'USD' })]);
  assert.equal(rMoeda.linhasDivergentes, 1);
  assert.deepEqual(rMoeda.divergencias[0].campos, ['moeda']);
});

test('compararExtracoes: a CHAVE inclui entidade_coluna e periodo_coluna — mesmo rótulo, coluna diferente, não é a "mesma linha"', () => {
  const a = [linha({ periodo_coluna: '2024' }), linha({ periodo_coluna: '2023', valor_num: 300 })];
  const b = [linha({ periodo_coluna: '2024' })]; // falta o período 2023 nesta passada
  const r = compararExtracoes(a, b);
  assert.equal(r.linhasIguais, 1);
  assert.equal(r.linhasDivergentes, 1);
  assert.equal(r.divergencias[0].a.periodo_coluna, '2023');
});

test('compararExtracoes: maxDivergencias trunca a LISTA, nunca a CONTAGEM', () => {
  const a = []; const b = [];
  for (let i = 0; i < 25; i += 1) {
    a.push(linha({ chave: `Conta ${i}`, valor_num: i }));
    b.push(linha({ chave: `Conta ${i}`, valor_num: i + 1 })); // todas divergem
  }
  const r = compararExtracoes(a, b, { maxDivergencias: 5 });
  assert.equal(r.linhasDivergentes, 25, 'a CONTAGEM não pode ser vítima do truncamento da lista');
  assert.equal(r.divergencias.length, 5);
  assert.equal(r.divergenciasTruncadas, true);
});

test('compararExtracoes: chave repetida na MESMA extração (livro-razão) casa por ordem, não perde a linha', () => {
  const a = [linha({ chave: 'Histórico X' }), linha({ chave: 'Histórico X', valor_num: 999 })];
  const b = [linha({ chave: 'Histórico X' }), linha({ chave: 'Histórico X', valor_num: 999 })];
  const r = compararExtracoes(a, b);
  assert.equal(r.linhasComparadas, 2);
  assert.equal(r.linhasDivergentes, 0);
});

test('compararExtracoes: entradas vazias/inválidas não explodem — devolvem zero comparações', () => {
  assert.deepEqual(compararExtracoes(null, undefined), {
    chavesComparadas: 0, linhasComparadas: 0, linhasIguais: 0, linhasDivergentes: 0,
    divergencias: [], divergenciasTruncadas: false,
  });
  assert.equal(compararExtracoes([], []).linhasComparadas, 0);
});

test('compararExtracoes é AUTO-CONTIDA — sobrevive fora do escopo do módulo (a fronteira do toString() do n8n)', () => {
  // O nó Code do n8n embute a função por toString() e NÃO leva o escopo do
  // módulo junto — se o corpo referenciasse outra função ou constante daqui, a
  // reconstrução abaixo replicaria o `ReferenceError` que só apareceria dentro
  // do nó real (aconteceu duas vezes nesta sessão: capacidadesDoModelo, usoGemini).
  // eslint-disable-next-line no-new-func
  const reconstruida = new Function(`return (${compararExtracoes.toString()});`)();
  const r = reconstruida([linha()], [linha({ valor_num: 1 })]);
  assert.equal(r.linhasDivergentes, 1, 'a função reconstruída FORA do módulo tem de funcionar sozinha');
});

test('documentoAmostradoParaRepetibilidade é AUTO-CONTIDA também', () => {
  // eslint-disable-next-line no-new-func
  const reconstruida = new Function(`return (${documentoAmostradoParaRepetibilidade.toString()});`)();
  assert.equal(reconstruida({ hash: 'ab'.repeat(32), blocos: 1, fracaoAmostra: 1 }), true);
});

// --- documentoAmostradoParaRepetibilidade -----------------------------------

test('documentoAmostradoParaRepetibilidade: restrita a documento de BLOCO ÚNICO', () => {
  const hash = 'a'.repeat(64);
  assert.equal(documentoAmostradoParaRepetibilidade({ hash, blocos: 2, fracaoAmostra: 1 }), false,
    'documento fatiado nunca entra na amostra nesta rodada — ver a nota no cabeçalho da função');
  assert.equal(documentoAmostradoParaRepetibilidade({ hash, blocos: 1, fracaoAmostra: 1 }), true);
});

test('documentoAmostradoParaRepetibilidade: fração 0 (ou ausente) nunca amostra — padrão seguro', () => {
  const hash = 'a'.repeat(64);
  assert.equal(documentoAmostradoParaRepetibilidade({ hash, blocos: 1, fracaoAmostra: 0 }), false);
  assert.equal(documentoAmostradoParaRepetibilidade({ hash, blocos: 1 }), false);
});

test('documentoAmostradoParaRepetibilidade: fração 1 amostra QUALQUER hash válido; hash ausente nunca amostra', () => {
  for (const hash of ['0'.repeat(64), 'f'.repeat(64), '1234567890abcdef'.repeat(4)]) {
    assert.equal(documentoAmostradoParaRepetibilidade({ hash, blocos: 1, fracaoAmostra: 1 }), true, hash);
  }
  assert.equal(documentoAmostradoParaRepetibilidade({ hash: null, blocos: 1, fracaoAmostra: 1 }), false);
  assert.equal(documentoAmostradoParaRepetibilidade({ blocos: 1, fracaoAmostra: 1 }), false);
});

test('documentoAmostradoParaRepetibilidade: DETERMINÍSTICA — o MESMO hash toma a MESMA decisão sempre', () => {
  const hash = createHashDeTeste('doc-real-1');
  const d1 = documentoAmostradoParaRepetibilidade({ hash, blocos: 1, fracaoAmostra: FRACAO_AMOSTRA_REPETIBILIDADE });
  const d2 = documentoAmostradoParaRepetibilidade({ hash, blocos: 1, fracaoAmostra: FRACAO_AMOSTRA_REPETIBILIDADE });
  assert.equal(d1, d2);
});

test('documentoAmostradoParaRepetibilidade: MEDIDO — a fração pedida é aproximadamente a fração observada, num hashset amplo', () => {
  const N = 20000;
  let amostrados = 0;
  for (let i = 0; i < N; i += 1) {
    const hash = createHashDeTeste(`documento-${i}`);
    if (documentoAmostradoParaRepetibilidade({ hash, blocos: 1, fracaoAmostra: FRACAO_AMOSTRA_REPETIBILIDADE })) {
      amostrados += 1;
    }
  }
  const fracaoObservada = amostrados / N;
  // Folga generosa (±30% relativo): o teste existe para pegar um erro grosseiro
  // de escala (ex.: usar 8 dígitos hex errado e amostrar 100% ou 0%), não para
  // travar o terceiro dígito decimal de uma decisão por hash.
  assert.ok(
    fracaoObservada > FRACAO_AMOSTRA_REPETIBILIDADE * 0.7
    && fracaoObservada < FRACAO_AMOSTRA_REPETIBILIDADE * 1.3,
    `fração observada ${fracaoObservada} longe da pedida ${FRACAO_AMOSTRA_REPETIBILIDADE}`,
  );
});

// SHA-256 real (node:crypto, não `lib/hash.mjs` — evitar acoplar este teste a
// outro arquivo) só para o teste acima montar hashes de exemplo bem
// distribuídos. Um hash "de brinquedo" (polinomial simples sobre um prefixo
// comum + um dígito incremental) foi tentado primeiro e falhou por um motivo
// instrutivo: sementes sequenciais ("documento-0", "documento-1", …) davam
// hashes CONSECUTIVOS (0x1e337b57, 0x1e337b58, …) — todos no mesmo canto do
// espaço de 32 bits, então a fração observada saía 0 de 20000 mesmo com a
// função sob teste correta. SHA-256 de verdade não tem esse problema.
function createHashDeTeste(semente) {
  return createHash('sha256').update(String(semente)).digest('hex');
}

// --- mensagemRepetibilidade --------------------------------------------------

test('mensagemRepetibilidade: zero divergência AINDA produz uma frase (regra 7 — silêncio não é prova de execução)', () => {
  const r = compararExtracoes([linha()], [linha()]);
  const msg = mensagemRepetibilidade(r);
  assert.match(msg, /Amostra conferida/);
  assert.match(msg, /1 de 1 linha/);
  assert.doesNotMatch(msg, /DIVERGÊNCIA/);
});

test('mensagemRepetibilidade: divergência traz o EFEITO ("book não pode ser entregue") e exemplos com os DOIS valores', () => {
  const r = compararExtracoes([linha({ valor_num: 380 })], [linha({ valor_num: 830 })]);
  const msg = mensagemRepetibilidade(r);
  assert.match(msg, /DIVERGÊNCIA/);
  assert.match(msg, /book NÃO pode ser entregue/);
  assert.match(msg, /380/);
  assert.match(msg, /830/);
  assert.match(msg, /tolerância zero/);
});

test('MAX_DIVERGENCIAS_REPETIBILIDADE é o padrão usado quando o chamador não pede outro', () => {
  const a = []; const b = [];
  for (let i = 0; i < MAX_DIVERGENCIAS_REPETIBILIDADE + 5; i += 1) {
    a.push(linha({ chave: `C${i}`, valor_num: i }));
    b.push(linha({ chave: `C${i}`, valor_num: -1 }));
  }
  const r = compararExtracoes(a, b);
  assert.equal(r.divergencias.length, MAX_DIVERGENCIAS_REPETIBILIDADE);
});
