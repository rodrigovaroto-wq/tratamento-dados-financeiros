import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
  orcamentoDoLote,
  custoDaChamada,
  custoEstimadoPorTamanho,
  bytesDoBinario,
  TETO_EXECUCAO_USD,
  CUSTO_ESTIMADO_DOC_USD,
  CUSTO_POR_MB_USD,
  CUSTO_MINIMO_CHAMADA_USD,
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
  assert.equal(antes.cabe, false, '22 chamadas ≈ US$ 4,40 estoura o teto de US$ 3');
  assert.match(antes.mensagem, /Lote recusado ANTES de gastar/);
  assert.match(antes.mensagem, /Nada foi enviado à OpenAI/);
  assert.ok(antes.maxDocumentos > 0 && antes.maxDocumentos < 14,
    'a mensagem tem de dizer um número de documentos por leva que seja acionável');

  // Depois do renome para a notação de f0/03 (12M25 / L24M): 1 chamada por
  // documento → 14 chamadas, US$ 2,80, cabe.
  const depois = orcamentoDoLote({ documentos: 14, chamadasPorDocumento: 1 });
  assert.equal(depois.chamadas, 14);
  assert.equal(depois.cabe, true);
  assert.equal(depois.estimadoUSD, 2.8);
  assert.equal(depois.mensagem, null, 'lote que cabe não produz mensagem de recusa');
});

// O book-canastra é o primeiro lote do repositório que NÃO CABE nem depois de
// renomear: 38 documentos, dos quais 19 pagam o PDF duas vezes = 57 chamadas.
// Ele existe para exercitar exatamente isto — que a decisão seja NÃO antes da
// primeira chamada, e que a mensagem diga em quantas levas o trabalho cabe.
// O custo MEDIDO desse lote está em `n8n/medir-custo-book.mjs`.
test('orçamento: o lote do book-canastra é recusado, e recusado de novo depois do renome', () => {
  const comoEsta = orcamentoDoLote({ documentos: 38, chamadasPorDocumento: 57 / 38 });
  assert.equal(comoEsta.chamadas, 57);
  assert.equal(comoEsta.cabe, false);
  // 10, e não 9. O 9 de antes era artefato de ponto flutuante: o cálculo
  // remultiplicava `0,20 × 1,5`, que não dá exatamente 0,30, e o `floor` comia um
  // documento. Agora o máximo sai do TOTAL do lote dividido pelos documentos
  // dele, então 10 × 1,5 = 15 chamadas × 0,20 = US$ 3,00 exatos — que cabem,
  // porque o teto é `<=`. Deixar de perder um documento por arredondamento é
  // ganho pequeno e real; o que importa é que a conta passou a ser a mesma que
  // decide o `cabe`, em vez de uma segunda fórmula parecida.
  assert.equal(comoEsta.maxDocumentos, 10);
  assert.match(comoEsta.mensagem, /Envie no máximo 10 documento\(s\) por vez \(4 levas\)/);

  // Renomear tudo para a notação de f0/03 corta 19 chamadas — e ainda assim o
  // lote não cabe. Ou seja: com kit de mandato completo, dividir em levas não é
  // contorno de nome mal escolhido, é a operação normal.
  const renomeado = orcamentoDoLote({ documentos: 38, chamadasPorDocumento: 1 });
  assert.equal(renomeado.chamadas, 38);
  assert.equal(renomeado.cabe, false, '38 × US$ 0,20 = US$ 7,60 continua acima do teto');
  assert.equal(renomeado.maxDocumentos, 15);
});

test('orçamento: fronteira exata do teto', () => {
  const n = Math.floor(TETO_EXECUCAO_USD / CUSTO_ESTIMADO_DOC_USD); // 15
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
  // O estimador por documento tem de ficar ACIMA do custo medido, senão o teto
  // de US$ 3 mente para o lado perigoso. O piso não é mais o cálculo de
  // guardanapo (US$ 0,105): é o documento MAIS CARO já medido num book real — o
  // livro razão do book-canastra, US$ 0,1725 por chamada (3 páginas, 461
  // linhas). Foi ele que obrigou a recalibração de 0,15 para 0,20.
  assert.ok(CUSTO_ESTIMADO_DOC_USD > 0.1725,
    'a estimativa precisa cobrir o documento mais caro já medido, não o típico');
});

test('custoDaChamada devolve null em vez de chutar quando não pode medir', () => {
  assert.equal(custoDaChamada(null, 'gpt-4o'), null, 'sem usage não há medição');
  assert.equal(custoDaChamada({ prompt_tokens: 1 }, 'modelo-que-nao-existe'), null,
    'modelo sem preço conhecido não vira número inventado');
  assert.equal(custoDaChamada({ prompt_tokens: 'x', completion_tokens: 1 }, 'gpt-4o'), null);
});


// ---------------------------------------------------------------------------
// ESTIMATIVA POR TAMANHO — o que corrige a recusa de 5,4×
// ---------------------------------------------------------------------------
//
// O caso real que motivou tudo isto: 35 documentos do book-canastra foram
// RECUSADOS com "≈ US$ 7,65", e o book inteiro (38 documentos, 57 chamadas) foi
// medido em US$ 1,41. O estimador plano barrava um lote que cabia com folga.

test('orçamento por tamanho: o lote real do book-canastra PASSA', () => {
  // 183.139 bytes é o total medido dos 38 PDFs (pdf/METRICAS.json).
  const r = orcamentoDoLote({ documentos: 38, chamadasPorDocumento: 57 / 38, bytes: 183_139 });
  assert.equal(r.porTamanho, true);
  assert.ok(r.cabe, `o lote real tem de caber — estimou US$ ${r.estimadoUSD}`);
  // A estimativa fica ACIMA do custo medido (US$ 1,41) e ABAIXO do teto: é a
  // faixa onde o estimador é útil. Fora dela ele ou mente ou trava o trabalho.
  assert.ok(r.estimadoUSD > 1.41, 'estima acima do medido — a margem existe');
  assert.ok(r.estimadoUSD <= 3, 'e abaixo do teto');
});

test('orçamento por tamanho: lote homogêneo DENSO continua sendo recusado', () => {
  // 35 cópias do documento mais denso do book (livro razão, 10.849 bytes, 461
  // linhas). Custo REAL medido: US$ 0,1725 por chamada = US$ 6,04 no lote.
  // Este é o caso que o teto existe para barrar, e a estimativa por tamanho tem
  // de continuar barrando — senão trocamos um erro (recusar o que cabe) por
  // outro pior (aceitar o que não cabe), que é o incidente v31.
  const r = orcamentoDoLote({ documentos: 35, chamadasPorDocumento: 1, bytes: 10_849 * 35 });
  assert.equal(r.cabe, false);
  assert.match(r.mensagem, /KB de arquivo/, 'a mensagem diz de onde saiu a conta');
});

test('orçamento por tamanho: tamanho desconhecido NÃO vira zero', () => {
  // Zero deixaria qualquer lote passar. A ausência cai no plano, que é
  // conservador, e a mensagem declara que foi ele quem decidiu.
  for (const bytes of [null, undefined, 0, -1, NaN, 'grande']) {
    const r = orcamentoDoLote({ documentos: 100, chamadasPorDocumento: 1, bytes });
    assert.equal(r.porTamanho, false, `bytes=${String(bytes)} não pode virar estimativa por tamanho`);
    assert.equal(r.cabe, false, `bytes=${String(bytes)}: 100 documentos não podem passar`);
    assert.match(r.mensagem, /estimativa plana/);
  }
});

test('custoEstimadoPorTamanho: piso por chamada, e null quando não dá para medir', () => {
  // Arquivo minúsculo ainda paga o prompt de sistema e uma página de imagem.
  assert.equal(custoEstimadoPorTamanho(10), CUSTO_MINIMO_CHAMADA_USD);
  // 1 MB pelo preço calibrado.
  assert.equal(custoEstimadoPorTamanho(1024 * 1024), CUSTO_POR_MB_USD);
  for (const x of [null, undefined, 0, -5, 'abc']) {
    assert.equal(custoEstimadoPorTamanho(x), null, `${String(x)} não é tamanho`);
  }
});

test('bytesDoBinario lê os DOIS formatos que o n8n usa', () => {
  // Modo memória: `data` é base64 e o tamanho sai dele.
  const base64 = Buffer.from('x'.repeat(300)).toString('base64');
  assert.equal(bytesDoBinario({ data: base64 }), 300);
  // Modo filesystem: `data` é ponteiro (tem `id`) e só resta `fileSize`, que vem
  // FORMATADO. Ler só o base64 funcionaria na máquina de quem escreveu e falharia
  // em produção — é o tipo de diferença que só aparece no ambiente do dono.
  assert.equal(bytesDoBinario({ id: 'abc', data: 'ponteiro', fileSize: '10.5 kB' }), 10752);
  assert.equal(bytesDoBinario({ id: 'abc', fileSize: '512 B' }), 512);
  assert.equal(bytesDoBinario({ id: 'abc', fileSize: '1,5 MB' }), 1572864);
  // Número puro (versões antigas do n8n) também vale.
  assert.equal(bytesDoBinario({ fileSize: 4096 }), 4096);
  // E o que não dá para medir devolve null, não zero.
  assert.equal(bytesDoBinario(null), null);
  assert.equal(bytesDoBinario({ id: 'abc', fileSize: 'sei lá' }), null);
});
