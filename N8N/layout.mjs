// Posicionamento automático dos nós no canvas do n8n.
//
// Por que isto existe: as coordenadas eram escritas à mão em cada chamada de
// `node(...)`, e cada nó novo era encaixado "no espaço que sobrava" — 50px à
// direita do anterior aqui, 120px ali. O resultado no canvas do dono era o que
// se esperava de números escolhidos um a um ao longo de 40 sessões: rótulos
// sobrepostos (`Fatiar Extracao` em cima do `IA Extrair`, `Juntar Blocos`
// em cima do `Gravar Campos`), o tronco subindo e descendo sem motivo, e a
// aresta longa `Precisa Fallback?`[false] → `Juntar Ramos` atravessando por
// dentro dos três nós da classificação por conteúdo.
//
// A correção não é escolher números melhores — é parar de escolhê-los. O layout
// passa a ser DERIVADO do grafo (`connections`), com três garantias:
//
//   1. **Uma coluna por camada.** A camada de um nó é o caminho MAIS LONGO desde
//      a entrada, então toda aresta anda da esquerda para a direita, nunca para
//      trás e nunca na vertical pura.
//   2. **Uma faixa por corrente.** O filho de maior "altura" (maior caminho até
//      o fim) herda a faixa do pai — é o tronco, e ele fica reto. Os ramos
//      laterais caem na primeira faixa livre, e "livre" é conferido célula a
//      célula: dois nós nunca dividem a mesma (coluna, faixa).
//   3. **Corredor reservado para aresta longa.** Quando uma aresta pula colunas
//      (é o caso do `false` do fallback, que salta direto para o Merge), as
//      células entre as duas pontas ficam RESERVADAS na faixa da origem. Nada é
//      posicionado ali, e a linha atravessa espaço vazio em vez de cortar nó.
//
// O canvas volta a ser legível sozinho depois de qualquer inclusão de nó: quem
// acrescentar um nó amanhã declara só a conexão, e a posição sai daqui.

export const COLUNA = 260; // passo horizontal (largura do nó + folga para o rótulo)
export const LINHA = 180;  // passo vertical (altura do nó + folga para o rótulo de baixo)

const chave = (coluna, faixa) => `${coluna}:${faixa}`;

// Arestas `main` do formato de `connections` do n8n, sem duplicata (dois outputs
// do mesmo nó podem chegar no mesmo destino) e preservando a ordem declarada.
function arestas(nomes, connections) {
  const filhos = new Map(nomes.map((n) => [n, []]));
  const pais = new Map(nomes.map((n) => [n, []]));
  for (const [de, saidas] of Object.entries(connections)) {
    if (!filhos.has(de)) throw new Error(`layout: conexão parte de nó inexistente: "${de}"`);
    for (const grupo of saidas.main ?? []) {
      for (const c of grupo ?? []) {
        if (!filhos.has(c.node)) throw new Error(`layout: conexão chega em nó inexistente: "${c.node}"`);
        if (filhos.get(de).includes(c.node)) continue;
        filhos.get(de).push(c.node);
        pais.get(c.node).push(de);
      }
    }
  }
  return { filhos, pais };
}

// Ordem topológica (Kahn). Ciclo aqui é erro de grafo, não de desenho: o n8n
// executaria em laço, e o layout não teria "esquerda para a direita" nenhuma.
function ordemTopologica(nomes, filhos, pais) {
  const restam = new Map(nomes.map((n) => [n, pais.get(n).length]));
  const fila = nomes.filter((n) => restam.get(n) === 0);
  const ordem = [];
  while (fila.length) {
    const n = fila.shift();
    ordem.push(n);
    for (const f of filhos.get(n)) {
      restam.set(f, restam.get(f) - 1);
      if (restam.get(f) === 0) fila.push(f);
    }
  }
  if (ordem.length !== nomes.length) {
    const presos = nomes.filter((n) => !ordem.includes(n));
    throw new Error(`layout: ciclo nas conexões envolvendo: ${presos.join(', ')}`);
  }
  return ordem;
}

/**
 * Escreve `position` em cada nó a partir do grafo de conexões.
 * Muta e devolve o mesmo array (é o que o build faz logo antes de serializar).
 */
export function posicionar(nodes, connections, opts = {}) {
  const { coluna = COLUNA, linha = LINHA, x0 = 0, y0 = 0 } = opts;
  const nomes = nodes.map((n) => n.name);
  const duplicado = nomes.find((n, i) => nomes.indexOf(n) !== i);
  if (duplicado) throw new Error(`layout: dois nós com o mesmo nome: "${duplicado}"`);

  const { filhos, pais } = arestas(nomes, connections);
  const ordem = ordemTopologica(nomes, filhos, pais);

  // Coluna = caminho mais longo desde a entrada (a aresta mais curta possível
  // ainda anda uma coluna inteira para a direita).
  const col = new Map(nomes.map((n) => [n, 0]));
  for (const n of ordem) for (const f of filhos.get(n)) col.set(f, Math.max(col.get(f), col.get(n) + 1));

  // Altura = caminho mais longo até o fim. É ela que diz qual filho É o tronco:
  // o que ainda tem mais workflow pela frente segue reto, e o ramo curto desce.
  const alt = new Map(nomes.map((n) => [n, 0]));
  for (const n of [...ordem].reverse()) {
    for (const f of filhos.get(n)) alt.set(n, Math.max(alt.get(n), alt.get(f) + 1));
  }
  const troncoDe = (n) => {
    const fs = filhos.get(n);
    if (!fs.length) return null;
    return fs.reduce((a, b) => (alt.get(b) > alt.get(a) ? b : a));
  };

  // Pai que manda no alinhamento: o mais próximo (maior coluna) — é dele que a
  // linha curta chega, e é com ele que vale ficar na mesma faixa.
  const paiMandante = (n) => {
    const ps = pais.get(n);
    return ps.length ? ps.reduce((a, b) => (col.get(b) > col.get(a) ? b : a)) : null;
  };
  const ehTronco = (n) => {
    const p = paiMandante(n);
    return p !== null && troncoDe(p) === n;
  };

  // Dentro da mesma coluna, quem continua uma corrente escolhe a faixa ANTES de
  // quem abre ramo: sem isso um ramo lateral pode ocupar a faixa do tronco alheio
  // e empurrar a corrente inteira uma faixa para baixo (foi o que jogou o
  // `Abortar Lote` para longe do `Registrar Recusa`). A ordem continua topológica:
  // toda aresta anda para a frente, então ordenar por coluna preserva os pais.
  const posOriginal = new Map(ordem.map((n, i) => [n, i]));
  ordem.sort((a, b) => (col.get(a) - col.get(b))
    || ((ehTronco(a) ? 0 : 1) - (ehTronco(b) ? 0 : 1))
    || (posOriginal.get(a) - posOriginal.get(b)));

  const faixa = new Map();
  const ocupado = new Set();
  const livre = (c, f) => !ocupado.has(chave(c, f));
  // Procura para BAIXO primeiro (a convenção do canvas: o tronco em cima, o ramo
  // lateral logo abaixo), e só então para cima.
  const primeiraLivre = (c, pref) => {
    for (let d = 0; d < 1000; d++) {
      if (livre(c, pref + d)) return pref + d;
      if (d > 0 && livre(c, pref - d)) return pref - d;
    }
    throw new Error(`layout: sem faixa livre na coluna ${c}`);
  };

  for (const n of ordem) {
    if (!faixa.has(n)) {
      const pai = paiMandante(n);
      let pref = 0;
      if (pai !== null) {
        pref = faixa.get(pai) ?? 0;
        if (troncoDe(pai) !== n) pref += 1; // ramo lateral não disputa a faixa do tronco
      }
      faixa.set(n, primeiraLivre(col.get(n), pref));
    }
    const f = faixa.get(n);
    ocupado.add(chave(col.get(n), f));

    // Aresta longa: reserva o corredor por onde a linha vai passar e prende o
    // destino na mesma faixa, para a linha sair reta por cima do vazio.
    for (const c of filhos.get(n)) {
      const vao = col.get(c) - col.get(n);
      if (vao <= 1 || faixa.has(c)) continue;
      if (!livre(col.get(c), f)) continue; // destino já disputado: sem corredor
      let cabe = true;
      for (let k = col.get(n) + 1; k < col.get(c); k++) if (!livre(k, f)) cabe = false;
      if (!cabe) continue;
      faixa.set(c, f);
      ocupado.add(chave(col.get(c), f));
      for (let k = col.get(n) + 1; k < col.get(c); k++) ocupado.add(chave(k, f));
    }
  }

  const faixaMin = Math.min(...faixa.values());
  for (const n of nodes) {
    n.position = [x0 + col.get(n.name) * coluna, y0 + (faixa.get(n.name) - faixaMin) * linha];
  }
  return nodes;
}
