import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
  linhasComNumero, planejarFatias, instrucaoDaFatia, juntarBlocos, avaliarCobertura,
  MAX_CELULAS_POR_BLOCO, TETO_SAIDA_TOKENS, TOKENS_POR_CELULA, LIMIAR_COBERTURA,
} from '../lib/cobertura.mjs';
import { MAX_OUTPUT_TOKENS } from '../lib/extract.mjs';

// O caso REAL que motivou o arquivo inteiro (book-canastra, 13/08/2026): 1.139
// das 2.893 células de valor chegaram ao banco. Dois documentos truncaram e
// vieram zerados; o livro razão devolveu 99 de 461 SEM abrir pendência nenhuma.

test('o teto do fatiamento é o teto REAL do modelo, não um número solto', () => {
  // Se `MAX_OUTPUT_TOKENS` mudar (troca de modelo) e este espelho não, os blocos
  // passam a ser calibrados para um teto que não existe mais — e o truncamento
  // volta pela porta que este arquivo fechou.
  assert.equal(TETO_SAIDA_TOKENS, MAX_OUTPUT_TOKENS);
  assert.equal(MAX_CELULAS_POR_BLOCO, Math.floor((TETO_SAIDA_TOKENS * 0.6) / TOKENS_POR_CELULA));
  // O bloco cheio tem de caber com folga real, não raspando.
  assert.ok(MAX_CELULAS_POR_BLOCO * TOKENS_POR_CELULA <= TETO_SAIDA_TOKENS * 0.65);
});

test('linhasComNumero conta o que o documento tem, sem IA', () => {
  const texto = [
    'CANASTRA INDÚSTRIA DE EMBALAGENS LTDA.',   // sem número → fora
    'CNPJ 44.555.667/0001-59',                   // com número → conta (e superestima de propósito)
    'ATIVO',                                     // fora
    'Caixa e bancos conta movimento    380',
    '',                                          // vazia → fora
    '   Duplicatas a receber   22.310',
  ].join('\n');
  assert.deepEqual(linhasComNumero(texto).length, 3);
  // Sem camada de texto (PDF escaneado) a régua não existe — e não existir é
  // diferente de ser zero.
  for (const vazio of ['', null, undefined, 42]) assert.deepEqual(linhasComNumero(vazio), []);
});

test('planejarFatias: documento que cabe vai INTEIRO, em um bloco só', () => {
  const linhas = Array.from({ length: 40 }, (_, i) => `conta ${i}   ${i * 10}`);
  const f = planejarFatias(linhas, MAX_CELULAS_POR_BLOCO);
  assert.equal(f.length, 1);
  assert.equal(f[0].blocos, 1);
  // Bloco único não carrega âncora: `instrucaoDaFatia` devolve vazio e a
  // requisição fica byte a byte igual à de antes do fatiamento existir.
  assert.equal(instrucaoDaFatia(f[0]), '');
});

test('planejarFatias: o livro razão (461 linhas) vira blocos que CABEM, com âncora', () => {
  const linhas = Array.from({ length: 461 }, (_, i) => `PAGTO FORNECEDOR ${i}   ${1000 + i},00`);
  const f = planejarFatias(linhas, MAX_CELULAS_POR_BLOCO);
  assert.ok(f.length >= 2, 'não cabia numa chamada, tem de virar mais de uma');
  // Cobertura EXATA: sem buraco entre blocos e sem sobreposição.
  assert.equal(f[0].de, 0);
  assert.equal(f[f.length - 1].ate, 460);
  for (let i = 1; i < f.length; i += 1) assert.equal(f[i].de, f[i - 1].ate + 1);
  // Todo bloco cabe no teto.
  for (const b of f) assert.ok(b.celulas <= MAX_CELULAS_POR_BLOCO, `bloco ${b.bloco} com ${b.celulas}`);
  // Blocos parelhos: um bloco final de 3 linhas daria ao modelo uma faixa curta
  // demais para ancorar com segurança.
  const tamanhos = f.map((b) => b.celulas);
  assert.ok(Math.max(...tamanhos) - Math.min(...tamanhos) <= 1, `tamanhos ${tamanhos}`);
  // E as âncoras são o TEXTO da linha, não um índice: é o que o modelo consegue
  // localizar no PDF que ele está vendo.
  assert.equal(f[0].ancoraInicio, linhas[0]);
  assert.equal(f[1].ancoraInicio, linhas[f[0].ate + 1]);
});

test('instrucaoDaFatia vai na mensagem de USER e nomeia as duas pontas da faixa', () => {
  const f = planejarFatias(Array.from({ length: 500 }, (_, i) => `linha ${i} 1,00`), 200)[1];
  const t = instrucaoDaFatia(f);
  assert.match(t, /BLOCO 2 DE 3/);
  assert.ok(t.includes(f.ancoraInicio), 'a âncora de início vai no texto');
  assert.ok(t.includes(f.ancoraFim), 'a âncora de fim vai no texto');
  // O diagnóstico é do DOCUMENTO, não do bloco: sem isto o bloco 2 diria que o
  // documento não tem entidade, e a divergência viraria pendência falsa.
  assert.match(t, /DOCUMENTO INTEIRO/);
});

test('juntarBlocos: renumera a ordem no CONJUNTO, não por bloco', () => {
  // `ordem` significa "posição na leitura do documento" e é o que deixa o export
  // reconhecer subtotal impresso acima dos componentes. Cada bloco numera a
  // partir de zero — manter isso daria três linhas de ordem 0 no mesmo documento.
  const r = juntarBlocos([
    { bloco: 2, campos: [{ ordem: 0, chave: 'C', valor_num: 3 }] },
    { bloco: 1, campos: [{ ordem: 0, chave: 'A', valor_num: 1 }, { ordem: 1, chave: 'B', valor_num: 2 }] },
  ]);
  assert.deepEqual(r.campos.map((c) => [c.chave, c.ordem]), [['A', 0], ['B', 1], ['C', 2]]);
  assert.equal(r.blocos, 2);
});

test('juntarBlocos: limpa a linha repetida NA EMENDA, e só ela', () => {
  const linha = (k, v) => ({ ordem: 0, chave: k, valor_num: v, valor_texto: String(v), entidade_coluna: null, periodo_coluna: null });
  const r = juntarBlocos([
    { bloco: 1, campos: [linha('A', 1), linha('B', 2), linha('C', 3)] },
    // O modelo repetiu a âncora: 'C' abre o bloco 2 e já estava no fim do 1.
    { bloco: 2, campos: [linha('C', 3), linha('D', 4)] },
  ]);
  assert.deepEqual(r.campos.map((c) => c.chave), ['A', 'B', 'C', 'D']);
  assert.equal(r.emendasLimpas, 1);

  // E o que ela NÃO faz: dedupe global. Num livro razão a mesma conta com o
  // mesmo valor aparece legitimamente várias vezes ao longo do documento —
  // apagar isso seria destruir dado real para consertar um problema de costura.
  const repetida = juntarBlocos([
    { bloco: 1, campos: [linha('PAGTO', 100), linha('OUTRA', 5), linha('PAGTO', 100)] },
  ]);
  assert.equal(repetida.campos.length, 3);
  assert.equal(repetida.emendasLimpas, 0);
});

test('juntarBlocos: o motivo de falha de UM bloco não some na junção', () => {
  const r = juntarBlocos([
    { bloco: 1, campos: [{ chave: 'A' }], falha_motivo: null },
    { bloco: 2, campos: [], falha_motivo: 'Resposta truncada' },
  ]);
  assert.equal(r.campos.length, 1);
  assert.deepEqual(r.motivos, ['bloco 2: Resposta truncada']);
});

test('avaliarCobertura: o livro razão (99 de 461) PARA na fila; o documento sadio passa', () => {
  const razao = avaliarCobertura({ extraidas: 99, esperadas: 461 });
  assert.ok(razao, '99 de 461 tem de virar pendência — hoje passou como sucesso');
  assert.equal(razao.razao, 0.215);
  assert.match(razao.motivo, /99 linha\(s\) gravada\(s\).*461 linha\(s\) com número/);
  // A descrição tem de dizer que a régua superestima: quem lê a pendência
  // precisa saber que 100% nunca é o alvo.
  assert.match(razao.motivo, /superestima/);

  // Os três documentos que vieram SADIOS na mesma rodada, com os números reais.
  assert.equal(avaliarCobertura({ extraidas: 104, esperadas: 115 }), null, '02_DRE: 90%');
  assert.equal(avaliarCobertura({ extraidas: 91, esperadas: 114 }), null, '22_Aging: 80%');
  assert.equal(avaliarCobertura({ extraidas: 74, esperadas: 109 }), null, '06_Balanco: 68%');
  // E os que vieram pela metade.
  assert.ok(avaliarCobertura({ extraidas: 77, esperadas: 162 }), '15_Balancete: 48%');
  assert.ok(avaliarCobertura({ extraidas: 0, esperadas: 326 }), '01_Balanco truncado: 0%');
});

test('avaliarCobertura se cala quando não tem régua ou quando a régua é ruído', () => {
  // PDF escaneado: sem camada de texto não há contagem, e "não sei" não pode
  // virar veredito — nem para acusar, nem para absolver.
  assert.equal(avaliarCobertura({ extraidas: 3, esperadas: null }), null);
  assert.equal(avaliarCobertura({ extraidas: 3, esperadas: undefined }), null);
  // Documento minúsculo: com 6 linhas, uma a menos derruba a cobertura em 17% e
  // a razão vira ruído.
  assert.equal(avaliarCobertura({ extraidas: 3, esperadas: 6 }), null);
  // O limiar é o declarado, e mexer nele é decisão consciente.
  assert.equal(LIMIAR_COBERTURA, 0.6);
});

test('as funções são AUTO-CONTIDAS (os nós Code as embutem por toString)', () => {
  // Se alguma passar a referenciar constante do módulo, o nó quebra com
  // ReferenceError na primeira execução real e nenhum teste daqui pega.
  for (const fn of [linhasComNumero, planejarFatias, instrucaoDaFatia, juntarBlocos, avaliarCobertura]) {
    assert.doesNotThrow(() => new Function(`return (${fn.toString()})`)(), `${fn.name} não é auto-contida`);
  }
  // `planejarFatias` e `avaliarCobertura` têm default nos parâmetros que vêm de
  // constantes do módulo — conferido aqui chamando as versões isoladas.
  const fatiar = new Function(`return (${planejarFatias.toString()})`)();
  assert.equal(fatiar(['a 1', 'b 2', 'c 3'], 2).length, 2);
  const avaliar = new Function(`const LIMIAR_COBERTURA=0.6;const MINIMO_PARA_AVALIAR=20;return (${avaliarCobertura.toString()})`)();
  assert.ok(avaliar({ extraidas: 10, esperadas: 100 }));
});
