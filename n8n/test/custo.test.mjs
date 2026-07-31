import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
  orcamentoDoLote,
  custoDaChamada,
  TETO_EXECUCAO_USD,
  CUSTO_ESTIMADO_DOC_USD,
} from '../lib/custo.mjs';

// O teto que o dono pediu, travado por teste. Se alguém mexer no número sem
// mexer também no teto do projeto na OpenAI (US$ 5), o lote volta a ser barrado
// PELA API no meio — que é o v31 — em vez de aqui, antes de gastar.
test('o teto por execução é o que o dono pediu: US$ 3', () => {
  assert.equal(TETO_EXECUCAO_USD, 3);
});

// O caso REAL do v31, nas duas versões, porque é o que dá sentido ao guarda.
test('orçamento: o lote do v31 é recusado ANTES do renome e passa DEPOIS', () => {
  // Antes: 8 dos 14 documentos tinham nome que não resolvia o período, então
  // pagavam o PDF duas vezes → 22 chamadas.
  const antes = orcamentoDoLote({ documentos: 14, chamadasPorDocumento: 22 / 14 });
  assert.equal(antes.chamadas, 22);
  assert.equal(antes.cabe, false, '22 chamadas ≈ US$ 3,30 estoura o teto de US$ 3');
  assert.match(antes.mensagem, /Lote recusado ANTES de gastar/);
  assert.match(antes.mensagem, /Nada foi enviado à OpenAI/);
  assert.ok(antes.maxDocumentos > 0 && antes.maxDocumentos < 14,
    'a mensagem tem de dizer um número de documentos por leva que seja acionável');

  // Depois do renome para a notação de f0/03 (12M25 / L24M): 1 chamada por
  // documento → 14 chamadas, US$ 2,10, cabe.
  const depois = orcamentoDoLote({ documentos: 14, chamadasPorDocumento: 1 });
  assert.equal(depois.chamadas, 14);
  assert.equal(depois.cabe, true);
  assert.equal(depois.estimadoUSD, 2.1);
  assert.equal(depois.mensagem, null, 'lote que cabe não produz mensagem de recusa');
});

test('orçamento: fronteira exata do teto', () => {
  const n = Math.floor(TETO_EXECUCAO_USD / CUSTO_ESTIMADO_DOC_USD); // 20
  assert.equal(orcamentoDoLote({ documentos: n }).cabe, true, `${n} documentos cabem`);
  assert.equal(orcamentoDoLote({ documentos: n + 1 }).cabe, false, `${n + 1} não cabem`);
  // Lote vazio não é erro de orçamento — quem reclama de lote vazio é
  // `Listar Arquivos`, com a mensagem sobre o campo do Form.
  assert.equal(orcamentoDoLote({ documentos: 0 }).cabe, true);
});

// Custo REAL, do `usage` da própria OpenAI. É o que permite trocar a estimativa
// por medição depois do próximo lote.
test('custoDaChamada mede a partir do usage e cobra cache pela metade', () => {
  // gpt-4o: US$ 2,50/1M entrada, US$ 10,00/1M saída, cache US$ 1,25/1M.
  // 10.000 de entrada sem cache + 8.000 de saída = 0,025 + 0,08 = 0,105
  assert.equal(
    custoDaChamada({ prompt_tokens: 10_000, completion_tokens: 8_000 }, 'gpt-4o'),
    0.105,
  );
  // Mesmos tokens, metade da entrada em cache: 5.000×2,50 + 5.000×1,25 = 0,01875
  // + 0,08 = 0,09875. Ignorar o cache superestimaria — e o prompt de sistema é
  // idêntico em toda chamada, então o cache pega de verdade.
  assert.equal(
    custoDaChamada(
      { prompt_tokens: 10_000, completion_tokens: 8_000, prompt_tokens_details: { cached_tokens: 5_000 } },
      'gpt-4o',
    ),
    0.09875,
  );
  // O estimador de US$ 0,15/documento tem de ficar ACIMA do custo medido típico,
  // senão o teto de US$ 3 mente para o lado perigoso.
  assert.ok(CUSTO_ESTIMADO_DOC_USD > 0.105,
    'a estimativa precisa errar para o lado seguro (superestimar), não subestimar');
});

test('custoDaChamada devolve null em vez de chutar quando não pode medir', () => {
  assert.equal(custoDaChamada(null, 'gpt-4o'), null, 'sem usage não há medição');
  assert.equal(custoDaChamada({ prompt_tokens: 1 }, 'modelo-que-nao-existe'), null,
    'modelo sem preço conhecido não vira número inventado');
  assert.equal(custoDaChamada({ prompt_tokens: 'x', completion_tokens: 1 }, 'gpt-4o'), null);
});
