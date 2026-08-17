// O canvas tem de ser LEGÍVEL, e legível é uma propriedade verificável.
//
// Este arquivo existe porque as coordenadas dos nós eram escolhidas à mão, uma a
// uma, ao longo de 40 sessões — e ninguém nunca conferiu o resultado. O que o
// dono viu na tela: `Fatiar Extracao` desenhado por cima do `OpenAI Extrair`,
// `Juntar Blocos` por cima do `Gravar Campos (Sombra)`, o tronco subindo e
// descendo entre y=140 e y=560 sem motivo, e a aresta longa do `false` do
// fallback atravessando por dentro dos três nós da classificação por conteúdo.
//
// Os testes valem para os QUATRO workflows gerados, não só para o da ingestão:
// a regra é do repositório, e o próximo gerador nasce coberto. Eles conferem o
// JSON COMMITADO (o que o dono importa no n8n), não uma reconstrução — o passo
// de CI que regenera e roda `git diff` garante que os dois são o mesmo arquivo.

import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { posicionar, COLUNA, LINHA } from '../layout.mjs';

const AQUI = dirname(fileURLToPath(import.meta.url));
const ler = (arq) => JSON.parse(readFileSync(join(AQUI, '..', arq), 'utf8'));

const WORKFLOWS = [
  'workflow.e1-ingestao.json',
  'workflow.macro.json',
  'workflow.diagnostico-openai.json',
  'workflow.erros.json',
].map((arq) => [arq, ler(arq)]);

// Caixa do nó no canvas do n8n. A largura é a do nó; a folga vertical é maior
// que a altura porque o RÓTULO fica ABAIXO do nó — foi rótulo em cima de rótulo,
// não caixa em cima de caixa, o que deixou a tela ilegível.
const LARGURA = 200;
const ALTURA = 130;

const arestas = (wf) => {
  const saida = [];
  for (const [de, conexoes] of Object.entries(wf.connections)) {
    for (const grupo of conexoes.main ?? []) for (const c of grupo ?? []) saida.push([de, c.node]);
  }
  return saida;
};
const porNome = (wf) => new Map(wf.nodes.map((n) => [n.name, n]));

for (const [arq, wf] of WORKFLOWS) {
  test(`${arq}: nenhum nó desenhado por cima de outro`, () => {
    for (let i = 0; i < wf.nodes.length; i++) {
      for (let j = i + 1; j < wf.nodes.length; j++) {
        const a = wf.nodes[i]; const b = wf.nodes[j];
        const dx = Math.abs(a.position[0] - b.position[0]);
        const dy = Math.abs(a.position[1] - b.position[1]);
        assert.ok(dx >= LARGURA || dy >= ALTURA,
          `"${a.name}" ${JSON.stringify(a.position)} e "${b.name}" ${JSON.stringify(b.position)} se sobrepõem no canvas`);
      }
    }
  });

  test(`${arq}: toda conexão anda da esquerda para a direita`, () => {
    const nos = porNome(wf);
    for (const [de, para] of arestas(wf)) {
      const x0 = nos.get(de).position[0];
      const x1 = nos.get(para).position[0];
      assert.ok(x1 > x0, `"${de}" → "${para}": a linha volta para trás (x ${x0} → ${x1}), e linha para trás cruza o canvas inteiro`);
    }
  });

  // A linha do n8n sai da direita de um nó e entra na esquerda do outro. Quando
  // as duas pontas estão na MESMA altura, ela é um segmento reto — e qualquer nó
  // parado nessa altura entre elas é atravessado pelo traço. É exatamente o que
  // acontecia com `Precisa Fallback?`[false] → `Juntar Ramos`, que cruzava por
  // dentro do `Montar Req Classif`, do `OpenAI Classificar` e do `Parse OpenAI
  // Classif`.
  test(`${arq}: nenhuma linha reta atravessa um nó pelo caminho`, () => {
    const nos = porNome(wf);
    for (const [de, para] of arestas(wf)) {
      const a = nos.get(de).position; const b = nos.get(para).position;
      if (a[1] !== b[1]) continue;
      for (const n of wf.nodes) {
        if (n.name === de || n.name === para) continue;
        const [x, y] = n.position;
        const noCaminho = x > a[0] && x < b[0] && Math.abs(y - a[1]) < ALTURA;
        assert.ok(!noCaminho, `a linha "${de}" → "${para}" passa por dentro de "${n.name}"`);
      }
    }
  });

  test(`${arq}: posições alinhadas à grade do canvas`, () => {
    for (const n of wf.nodes) {
      assert.ok(n.position[0] % 20 === 0 && n.position[1] % 20 === 0,
        `"${n.name}" fora da grade de 20px: ${JSON.stringify(n.position)}`);
    }
  });
}

// --- o desenhista em si -------------------------------------------------------

test('posicionar: o tronco fica reto e o ramo curto desce', () => {
  const nodes = ['A', 'B', 'C', 'D', 'ramo'].map((name) => ({ name, position: [0, 0] }));
  posicionar(nodes, {
    A: { main: [[{ node: 'B' }]] },
    B: { main: [[{ node: 'ramo' }], [{ node: 'C' }]] }, // o ramo é declarado ANTES do tronco
    C: { main: [[{ node: 'D' }]] },
  });
  const p = Object.fromEntries(nodes.map((n) => [n.name, n.position]));
  assert.deepEqual(p.A, [0, 0]);
  assert.deepEqual(p.B, [COLUNA, 0]);
  // C tem mais workflow pela frente que `ramo`: é ele quem herda a faixa do tronco,
  // independentemente da ordem em que as conexões foram escritas.
  assert.deepEqual(p.C, [2 * COLUNA, 0]);
  assert.deepEqual(p.D, [3 * COLUNA, 0]);
  assert.deepEqual(p.ramo, [2 * COLUNA, LINHA]);
});

test('posicionar: aresta longa ganha corredor vazio, e nada é posicionado nele', () => {
  // Desvio → 3 nós → junção; e um atalho que salta do desvio direto para a junção.
  const nodes = ['Desvio', 'X1', 'X2', 'X3', 'Junta'].map((name) => ({ name, position: [0, 0] }));
  posicionar(nodes, {
    Desvio: { main: [[{ node: 'X1' }], [{ node: 'Junta' }]] },
    X1: { main: [[{ node: 'X2' }]] },
    X2: { main: [[{ node: 'X3' }]] },
    X3: { main: [[{ node: 'Junta' }]] },
  });
  const p = Object.fromEntries(nodes.map((n) => [n.name, n.position]));
  assert.equal(p.Desvio[1], p.Junta[1], 'as duas pontas do atalho ficam na mesma faixa');
  for (const n of ['X1', 'X2', 'X3']) {
    assert.notEqual(p[n][1], p.Desvio[1], `${n} ficou em cima do corredor do atalho`);
  }
});

test('posicionar: recusa grafo inconsistente em vez de desenhar errado', () => {
  const nodes = () => ['A', 'B'].map((name) => ({ name, position: [0, 0] }));
  assert.throws(() => posicionar(nodes(), { A: { main: [[{ node: 'Fantasma' }]] } }), /nó inexistente/);
  assert.throws(() => posicionar(nodes(), { Fantasma: { main: [[{ node: 'A' }]] } }), /nó inexistente/);
  assert.throws(
    () => posicionar(nodes(), { A: { main: [[{ node: 'B' }]] }, B: { main: [[{ node: 'A' }]] } }),
    /ciclo/,
  );
  assert.throws(
    () => posicionar([{ name: 'A', position: [0, 0] }, { name: 'A', position: [0, 0] }], {}),
    /mesmo nome/,
  );
});
