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
  VERSAO_ORCAMENTO,
  MODELO_CLASSIFICACAO,
  MODELO_EXTRACAO,
  MODELOS_POR_PROVEDOR,
  pesoDaChamadaDeClassificacao,
  PRECO_USD_POR_MILHAO,
  TOKENS_SAIDA_CLASSIFICACAO,
  PERFIL_MEDIDO,
  FOLGA_EXTRACAO,
  FOLGA_CLASSIFICACAO,
  limiarDeRaciocinio,
  escolherEsforco,
  esforcosDoProvedor,
  PRECOS_POR_PROVEDOR,
  vereditoDaCotaDiaria,
} from '../lib/custo.mjs';
import { PROVEDORES, provedorAtivo, montarCorpoIA } from '../lib/provedor.mjs';

// O teto que o dono pediu, travado por teste. Se alguém mexer no número sem
// mexer também no teto do projeto no provedor (US$ 5), o lote volta a ser barrado
// PELA API no meio — que é o v31 — em vez de aqui, antes de gastar.
test('o teto por execução é o que o dono pediu: US$ 3', () => {
  assert.equal(TETO_EXECUCAO_USD, 3);
});

// TODO PROVEDOR DO CATÁLOGO TEM DE SER UTILIZÁVEL, não só o ativo. Um provedor
// com um modelo sem preço não é uma opção: o orçamento devolveria `null` como
// custo, e `custoDaChamada` trata null como "não sei" — o lote passaria pelo
// guarda sem ninguém saber quanto ia custar. É a única forma de o teto de US$ 3
// deixar de existir sem ninguém apagar uma linha.
test('todo provedor do catálogo tem modelo declarado e preço para os dois', () => {
  for (const id of Object.keys(PROVEDORES)) {
    const modelos = MODELOS_POR_PROVEDOR[id];
    assert.ok(modelos, `provedor "${id}" sem modelos declarados`);
    const tabela = PRECOS_POR_PROVEDOR[id];
    assert.ok(tabela, `provedor "${id}" sem tabela de preço`);
    for (const papel of ['classificacao', 'extracao']) {
      const preco = tabela[modelos[papel]];
      assert.ok(preco, `${id}: modelo de ${papel} ("${modelos[papel]}") sem preço não entra em produção`);
      assert.ok(preco.entrada > 0 && preco.saida > 0, `${id}: preço de ${papel} tem de ser positivo`);
    }
    // A classificação nunca pode custar MAIS que a extração — seria a troca ao
    // contrário: pagar o modelo caro na tarefa que TEM rede (o `diagnostico` da
    // extração confere tipo/entidade/período) e o barato na que não tem nenhuma.
    assert.ok(tabela[modelos.classificacao].entrada <= tabela[modelos.extracao].entrada, id);
  }
});

test('as constantes exportadas são as do provedor ATIVO', () => {
  const ativo = provedorAtivo();
  assert.equal(MODELO_EXTRACAO, MODELOS_POR_PROVEDOR[ativo].extracao);
  assert.equal(MODELO_CLASSIFICACAO, MODELOS_POR_PROVEDOR[ativo].classificacao);
  assert.equal(PRECO_USD_POR_MILHAO, PRECOS_POR_PROVEDOR[ativo]);
});

// O RENOME CONTINUA VALENDO DINHEIRO, e é isso que este teste prova — não um
// valor em dólar. Documento cujo nome não resolve tipo+período paga o PDF duas
// vezes, e a recusa acontece ANTES da primeira chamada.
//
// Ele testava o lote do v31 (14 documentos, 22 chamadas) contra o teto, e o
// número que fazia isso funcionar era US$ 0,20 por chamada. No preço do provedor
// novo esse lote custa ~US$ 0,30 e passa — como deve passar. O tamanho do lote
// passou a sair da própria constante: o que o guarda promete é sobre DINHEIRO,
// não sobre uma quantidade de arquivos.
test('orçamento: o renome muda a conta, e o lote que não cabe é recusado antes de gastar', () => {
  const cabemNoTeto = Math.floor(TETO_EXECUCAO_USD / CUSTO_ESTIMADO_DOC_USD);
  // Um lote em que TODO documento paga o PDF duas vezes: metade dos documentos
  // do teto, e ainda assim o dobro de chamadas — é o que estoura.
  const documentos = Math.ceil(cabemNoTeto / 2) + 1;
  const antes = orcamentoDoLote({ documentos, chamadasPorDocumento: 2 });
  assert.equal(antes.chamadas, documentos * 2);
  assert.equal(antes.cabe, false, 'nome mal escolhido dobra as chamadas e estoura o teto');
  assert.match(antes.mensagem, /Lote recusado ANTES de gastar/);
  assert.match(antes.mensagem, /Nada foi enviado ao provedor de IA/);
  assert.ok(antes.maxDocumentos > 0 && antes.maxDocumentos < documentos,
    'a mensagem tem de dizer um número de documentos por leva que seja acionável');

  // Depois do renome para a notação de Arquitetura do Sistema/2 Especificação/f0/03 (12M25 / L24M): 1 chamada por
  // documento, e o MESMO lote cabe.
  const depois = orcamentoDoLote({ documentos, chamadasPorDocumento: 1 });
  assert.equal(depois.chamadas, documentos);
  assert.equal(depois.cabe, true);
  assert.equal(depois.estimadoUSD, Number((documentos * CUSTO_ESTIMADO_DOC_USD).toFixed(2)));
  assert.equal(depois.mensagem, null, 'lote que cabe não produz mensagem de recusa');
});

// A MEDIÇÃO DA TROCA DE PROVEDOR, escrita como assert: o lote do v31 — 14
// documentos, 8 deles pagando o PDF duas vezes = 22 chamadas — estourou o teto
// de US$ 5 da OpenAI no meio da execução em 31/07/2026, e 8 documentos morreram
// sem extração. No preço de hoje ele cabe, e cabe com folga.
test('o lote do v31, que estourou o teto em produção, cabe no preço de hoje', () => {
  const v31 = orcamentoDoLote({ documentos: 14, chamadasPorDocumento: 22 / 14 });
  assert.equal(v31.chamadas, 22);
  assert.equal(v31.cabe, true);
  assert.ok(v31.estimadoUSD < TETO_EXECUCAO_USD / 2,
    `o lote que quebrou o teto agora usa menos da metade dele (US$ ${v31.estimadoUSD})`);
});

// O book-canastra é o primeiro lote do repositório que NÃO CABE nem depois de
// renomear: 38 documentos, dos quais 19 pagam o PDF duas vezes = 57 chamadas.
// Ele existe para exercitar exatamente isto — que a decisão seja NÃO antes da
// primeira chamada, e que a mensagem diga em quantas levas o trabalho cabe.
// O custo MEDIDO desse lote está em `N8N/medir-custo-book.mjs`.
test('orçamento: o lote do book-canastra é recusado pelo estimador PLANO, e recusado de novo depois do renome', () => {
  // Continua sendo o lote que não cabe NO CAMINHO CEGO — o plano, de "não sei
  // nada sobre estes arquivos". Pelos bytes e pelo conteúdo ele passa (testes
  // abaixo, e a medição em `medir-custo-book.mjs`: US$ 0,28 de verdade). É
  // exatamente essa diferença que justifica os três estimadores existirem.
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
  // O máximo por leva sai da MESMA conta que decide o `cabe` — antes havia uma
  // segunda fórmula parecida, e o `floor` dela comia um documento por
  // arredondamento. O valor exato depende da calibração; a propriedade não.
  assert.ok(comoEsta.maxDocumentos > 0 && comoEsta.maxDocumentos < 38);
  assert.match(comoEsta.mensagem,
    new RegExp(`Envie no máximo ${comoEsta.maxDocumentos} documento\\(s\\) por vez`));

  // Renomear tudo para a notação de Arquitetura do Sistema/2 Especificação/f0/03 corta 19 chamadas — e ainda assim o
  // lote não cabe. Ou seja: com kit de mandato completo, dividir em levas não é
  // contorno de nome mal escolhido, é a operação normal.
  // E DEPOIS DO RENOME ELE PASSA A CABER — 38 × US$ 0,055 = US$ 2,09 contra o
  // teto de US$ 3. Era o contrário até 24/08/2026 (38 × US$ 0,20 = US$ 7,60), e a
  // mudança é a troca de provedor: o book completo do mandato deixou de precisar
  // ser dividido em levas quando os nomes estão na notação de Arquitetura do Sistema/2 Especificação/f0/03. Continua
  // sendo o caminho CEGO — o mais conservador dos três.
  const renomeado = orcamentoDoLote({ documentos: 38, chamadasPorDocumento: 1 });
  assert.equal(renomeado.chamadas, 38);
  assert.equal(renomeado.cabe, true, `38 × US$ ${CUSTO_ESTIMADO_DOC_USD} cabe no teto de US$ ${TETO_EXECUCAO_USD}`);
  assert.equal(renomeado.maxDocumentos, Math.floor(TETO_EXECUCAO_USD / CUSTO_ESTIMADO_DOC_USD));
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
test('custoDaChamada mede a partir do usage e cobra o cache mais barato', () => {
  // A tabela vai EXPLÍCITA nesta conta: o número conferível à mão é o do gpt-4o,
  // e ele tem de continuar conferindo mesmo quando o provedor ativo é outro —
  // é a aritmética da função que está sob teste, não o preço da vez.
  const tabela = PRECOS_POR_PROVEDOR.openai;
  // gpt-4o: US$ 2,50/1M entrada, US$ 10,00/1M saída, cache US$ 1,25/1M.
  // 10.000 de entrada sem cache + 8.000 de saída = 0,025 + 0,08 = 0,105
  assert.equal(
    custoDaChamada({ prompt_tokens: 10_000, completion_tokens: 8_000 }, 'gpt-4o', tabela),
    0.105,
  );
  // Mesmos tokens, metade da entrada em cache: 5.000×2,50 + 5.000×1,25 = 0,01875
  // + 0,08 = 0,09875. Ignorar o cache superestimaria — e o prompt de sistema é
  // idêntico em toda chamada, então o cache pega de verdade.
  assert.equal(
    custoDaChamada(
      { prompt_tokens: 10_000, completion_tokens: 8_000, prompt_tokens_details: { cached_tokens: 5_000 } },
      'gpt-4o',
      tabela,
    ),
    0.09875,
  );
  // E a mesma conta no provedor ativo: 10.000 × 0,30 + 8.000 × 2,50, por milhão.
  const p = PRECO_USD_POR_MILHAO[MODELO_EXTRACAO];
  assert.equal(
    custoDaChamada({ prompt_tokens: 10_000, completion_tokens: 8_000 }, MODELO_EXTRACAO),
    Number(((10_000 * p.entrada + 8_000 * p.saida) / 1e6).toFixed(6)),
  );
  // MODELO FORA DA TABELA NÃO VIRA ZERO: vira null. Um custo de zero num
  // relatório de custo é um número inventado, e o guarda o somaria como se o
  // documento fosse de graça.
  assert.equal(custoDaChamada({ prompt_tokens: 10_000, completion_tokens: 8_000 }, 'modelo-que-nao-existe'), null);
  // O estimador por documento tem de ficar ACIMA do custo medido, senão o teto
  // de US$ 3 mente para o lado perigoso. O piso não é mais o cálculo de
  // guardanapo (US$ 0,105): é o documento MAIS CARO já medido num book real — o
  // livro razão do book-canastra, US$ 0,1725 por chamada (3 páginas, 461
  // linhas). Foi ele que obrigou a recalibração de 0,15 para 0,20.
  // O estimador plano tem de ficar ACIMA do custo medido, senão o teto de US$ 3
  // mente para o lado perigoso. O piso é o documento MAIS CARO já medido num book
  // real — o livro razão do book-canastra, 3 páginas e 461 linhas. No provedor
  // novo ele mede US$ 0,0459 (era US$ 0,1725 no gpt-4o), medido pelo mesmo
  // `medir-custo-book.mjs` sobre os mesmos PDFs.
  assert.ok(CUSTO_ESTIMADO_DOC_USD > 0.0459,
    'a estimativa precisa cobrir o documento mais caro já medido, não o típico');
  assert.ok(CUSTO_ESTIMADO_DOC_USD < 0.0459 * 2,
    'e não pode ser tão folgada a ponto de recusar lote que cabe — foi o defeito de deixar 0,20 de pé');
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
  // A estimativa fica ACIMA do custo medido e ABAIXO do teto: é a faixa onde o
  // estimador é útil. Fora dela ele ou mente ou trava o trabalho.
  //
  // O custo MEDIDO deste lote é US$ 0,2821 no provedor de hoje (era US$ 1,2932
  // no gpt-4o), pelo `N8N/medir-custo-book.mjs` sobre os mesmos 38 PDFs.
  assert.ok(r.estimadoUSD > 0.2821, `estima acima do medido — a margem existe (US$ ${r.estimadoUSD})`);
  assert.ok(r.estimadoUSD <= TETO_EXECUCAO_USD, 'e abaixo do teto');
});

test('orçamento por tamanho: lote homogêneo DENSO continua sendo recusado', () => {
  // Cópias do documento mais denso do book (livro razão, 10.849 bytes, 461
  // linhas). No provedor de hoje ele mede US$ 0,0459 por chamada, então o lote
  // que estoura o teto é maior — e o TAMANHO sai da conta, não de um número
  // escrito à mão que valia no preço de agosto.
  //
  // Este é o caso que o teto existe para barrar, e a estimativa por tamanho tem
  // de continuar barrando — senão trocamos um erro (recusar o que cabe) por
  // outro pior (aceitar o que não cabe), que é o incidente v31.
  const BYTES_DO_MAIS_DENSO = 10_849;
  const CUSTO_MEDIDO_DO_MAIS_DENSO = 0.0459;
  const documentos = Math.ceil(TETO_EXECUCAO_USD / custoEstimadoPorTamanho(BYTES_DO_MAIS_DENSO)) + 1;
  const r = orcamentoDoLote({ documentos, chamadasPorDocumento: 1, bytes: BYTES_DO_MAIS_DENSO * documentos });
  assert.equal(r.cabe, false);
  assert.match(r.mensagem, /KB de arquivo/, 'a mensagem diz de onde saiu a conta');
  // E o lote recusado é, DE VERDADE, um lote que não cabia: o guarda por byte
  // subestima o documento denso (é o limite declarado em lib/custo.mjs), então o
  // que ele barra custa mais que o teto, e não menos.
  assert.ok(documentos * CUSTO_MEDIDO_DO_MAIS_DENSO > TETO_EXECUCAO_USD,
    'recusar um lote que caberia seria travar trabalho à toa');
});

// ---------------------------------------------------------------------------
// O PESO DA SEGUNDA CHAMADA — a última superestimação que restava
// ---------------------------------------------------------------------------

test('a chamada de classificação NÃO custa o mesmo que a de extração', () => {
  const bytes = 183_139;
  const semFallback = orcamentoDoLote({ documentos: 38, chamadasPorDocumento: 1, bytes });
  const comFallback = orcamentoDoLote({ documentos: 38, chamadasPorDocumento: 57 / 38, bytes });

  // 19 documentos a mais pagando o PDF duas vezes não podem somar 50% na conta:
  // medido no book, as 19 classificações são US$ 0,0089 contra US$ 1,32 das
  // extrações. Cobrar cheio é o que fazia o mesmo lote estimar 46% mais caro.
  assert.ok(comFallback.estimadoUSD > semFallback.estimadoUSD,
    'a segunda chamada continua custando ALGUMA coisa — barato não é grátis');
  assert.ok(comFallback.estimadoUSD < semFallback.estimadoUSD * 1.2,
    `19 classificações não podem pesar 50% do lote (${semFallback.estimadoUSD} → ${comFallback.estimadoUSD})`);
  // O TETO DO PESO É A PARCELA DE ENTRADA, e ele SUBIU na troca de provedor —
  // de ~1,03 para 1,15 — porque os dois modelos passaram a ser o mesmo. Não é
  // regressão: com modelos iguais, a classificação custa a ENTRADA de uma
  // chamada cheia (0,30 declarado, 25% medido), e não 6% dela. O que continua
  // valendo, e é o que este assert trava, é que ela nunca conta como chamada
  // inteira — contar 2 chamadas = 2× o custo é o que inflava o lote em 46%.
  assert.ok(comFallback.fatorCusto > 1 && comFallback.fatorCusto < 1.2,
    `a segunda chamada pesa, mas não como uma inteira (fator ${comFallback.fatorCusto})`);
  // E as 57 chamadas continuam sendo REPORTADAS como 57: o que mudou é o peso
  // de cada uma na conta, não a contagem — a mensagem seguiria mentindo se
  // dissesse "39 chamadas" para um lote que faz 57.
  assert.equal(comFallback.chamadas, 57);
});

// A tentação é aplicar o desconto nos dois caminhos. O plano é o de "não sei
// nada sobre estes arquivos", e a única calibração que ele tem é um incidente
// de dinheiro de verdade (v31). Descontar ali com base numa proporção medida em
// PDF sintético seria trocar evidência cara por barata.
test('o desconto da 2ª chamada vale SÓ quando o tamanho é conhecido', () => {
  const plano = orcamentoDoLote({ documentos: 14, chamadasPorDocumento: 22 / 14 });
  assert.equal(plano.porTamanho, false);
  assert.equal(plano.estimadoUSD, Number((22 * CUSTO_ESTIMADO_DOC_USD).toFixed(2)),
    '22 chamadas CHEIAS — no caminho cego não há desconto');
  assert.equal(plano.fatorCusto, Number((22 / 14).toFixed(4)));
});

test('modelo fora da tabela de preço cobra CHEIO', () => {
  // Desconhecido não é barato. Se alguém apontar a classificação para um modelo
  // que este arquivo não conhece, o orçamento volta a contar chamada inteira em
  // vez de aplicar um desconto que ninguém mediu.
  const peso = pesoDaChamadaDeClassificacao('modelo-que-nao-existe', MODELO_EXTRACAO);
  assert.equal(peso, 1);
  const r = orcamentoDoLote({ documentos: 38, chamadasPorDocumento: 2, bytes: 183_139, pesoClassificacao: peso });
  assert.equal(r.fatorCusto, 2);
});

test('a mensagem de recusa CARIMBA a versão do orçamento', () => {
  // Sem isto, "reimportei o workflow?" é uma pergunta que só a memória responde
  // — e em 12/08/2026 ela respondeu errado, custando uma rodada de teste.
  const r = orcamentoDoLote({ documentos: 500, chamadasPorDocumento: 1, bytes: 500 * 1024 * 1024 });
  assert.equal(r.cabe, false);
  assert.equal(r.versao, VERSAO_ORCAMENTO);
  assert.ok(r.mensagem.startsWith(`[orçamento ${VERSAO_ORCAMENTO}]`), r.mensagem);
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

// ---------------------------------------------------------------------------
// O LOTE DE 190 DOCUMENTOS — o `book-araucaria`, antes de ele custar dinheiro
// ---------------------------------------------------------------------------
//
// O teto é um NÃO INTEIRO: ou o lote cabe e roda todo, ou não começa. Então a
// pergunta "190 documentos cabem em US$ 3?" tem de ser respondida ANTES do
// envio, e não pelo recado de recusa depois de o dono ter subido 190 arquivos.
//
// A forma vem do que o gerador MEDIU no book (sessão 70, registrado no
// HANDOFF): 190 documentos, 247 páginas, 16.081 linhas com número. O
// `book-araucaria` não está no repositório — foi entregue ao dono por arquivo,
// por decisão dele —, então o que este teste guarda é a FORMA do lote, que é o
// que decide o orçamento; os PDFs não acrescentariam nada à conta.
//
// E ele guarda um SEGUNDO fato, que é o que quase deu errado: a estimativa por
// CONTEÚDO devolve US$ 0,93 a US$ 2,30 (conforme quantas colunas os documentos
// têm e quantos nomes de arquivo não resolvem tipo+período), e a estimativa por
// TAMANHO — o caminho de queda, que vale para o lote INTEIRO assim que UM
// documento não trouxer medida de conteúdo — devolve US$ 2,47 a US$ 3,21 para o
// mesmo lote. No lote de 38 essa diferença era inofensiva (US$ 0,29 medido
// contra US$ 0,56 estimado, longe do teto); em 190 ela decide se a rodada
// acontece. Um PDF escaneado no meio do lote é o gatilho.
import { orcamentoDoLotePorConteudo } from '../lib/custo.mjs';
import { SYSTEM_PROMPT } from '../lib/extract.mjs';

const ARAUCARIA = { documentos: 190, paginas: 247, celulas: 16081 };

function loteComForma({ colunas, fracaoSemNomeResolvido }) {
  const docs = [];
  for (let i = 0; i < ARAUCARIA.documentos; i += 1) {
    docs.push({
      celulas: Math.round(ARAUCARIA.celulas / ARAUCARIA.documentos),
      paginas: Math.max(1, Math.round(ARAUCARIA.paginas / ARAUCARIA.documentos)),
      colunas,
      blocos: 1,
      precisaFallback: i / ARAUCARIA.documentos < fracaoSemNomeResolvido,
      bytes: Math.round((179 / 49) * 1024 * (ARAUCARIA.paginas / ARAUCARIA.documentos)),
    });
  }
  return docs;
}

test('o lote de 190 documentos do book-araucaria CABE no teto pela conta de conteúdo', () => {
  const tokensPromptSistema = Math.ceil(SYSTEM_PROMPT.length / 4);
  // O pior caso das duas variáveis que o lote não controla: uma coluna por
  // documento (mais saída por linha) e NENHUM nome de arquivo resolvendo
  // tipo+período (toda classificação paga o PDF de novo).
  const r = orcamentoDoLotePorConteudo({
    documentos: loteComForma({ colunas: 1, fracaoSemNomeResolvido: 1 }),
    tokensPromptSistema,
  });
  assert.equal(r.porConteudo, true, 'a conta caiu para a estimativa por tamanho — reveja a medição');
  assert.ok(r.cabe,
    `190 documentos com a forma do book-araucaria foram RECUSADOS: US$ ${r.estimadoUSD} contra o teto `
    + `de US$ ${TETO_EXECUCAO_USD}. O lote é um não-inteiro: recusado, ele não roda em nenhuma parte.`);
  assert.equal(r.chamadas, 380, '190 extrações + 190 classificações — se este número mudou, a cadência da tela mudou junto');
});

test('UM documento sem medida de conteúdo derruba o lote de 190 para a conta por TAMANHO', () => {
  const tokensPromptSistema = Math.ceil(SYSTEM_PROMPT.length / 4);
  const docs = loteComForma({ colunas: 1, fracaoSemNomeResolvido: 1 });
  // Um PDF escaneado: tem tamanho, não tem camada de texto.
  docs[0] = { ...docs[0], celulas: 0, paginas: 0 };

  const r = orcamentoDoLotePorConteudo({ documentos: docs, tokensPromptSistema });

  // A queda é DOUTRINA, não defeito: medir só os documentos que dá subestimaria
  // o lote na exata proporção do que não se sabe. O que este teste trava é a
  // CONSEQUÊNCIA, para que ela nunca seja descoberta no dia do envio: com o
  // lote inteiro caindo para a conta por tamanho, 190 documentos são recusados.
  assert.equal(r.porConteudo, false, 'a queda para a conta por tamanho deixou de acontecer');
  assert.equal(r.cabe, false,
    'um único PDF escaneado deixou de derrubar o lote de 190 — se isto passou a caber, a conta por '
    + 'tamanho mudou e o comentário acima envelheceu');
  assert.match(r.mensagem, /Envie no máximo \d+ documento\(s\) por vez/,
    'a recusa tem de dizer quantos cabem, senão o dono só sabe que não pode');
});

test('a cota do DIA é um portão, e ela recusa o que o teto de dólar aprovava', () => {
  // O DEFEITO QUE ISTO FECHA, medido em 31/08 sobre o `main`.
  //
  // `lib/provedor.mjs` declara `rpd: 500` com um comentário que o chama de "O
  // LIMITE QUE NINGUÉM TINHA MODELADO, E É O QUE DE FATO APERTA". Quem lia esse
  // número: o `medir-custo-book.mjs` (relatório de CI) e a suíte. NADA em
  // execução. `tpm` e `rpm` alimentam a cadência (lib/extract.mjs); o RPD não
  // alimentava nada, e o único portão pré-voo conferia dólar.
  //
  // E o dólar não é a restrição que morde. Medido:
  //   Canastra   38 doc  US$ 0,285  passa    63 chamadas =  13% do RPD
  //   Araucária 190 doc  ~US$ 2,1   passa   440 chamadas =  88% do RPD
  // O lote que o guarda aprova por preço é o mesmo que a cota mata na metade.
  const canastra = vereditoDaCotaDiaria({ chamadas: 63, rpd: 500 });
  assert.equal(canastra.cabe, true);
  assert.equal(canastra.mensagem, null, 'lote pequeno não gera ruído — portão que fala sempre não é lido');

  // O araucária PASSA e DECLARA. Recusar a 88% barraria o caso de uso do dono, e
  // portão que impede o trabalho legítimo é portão que alguém desliga.
  const araucaria = vereditoDaCotaDiaria({ chamadas: 440, rpd: 500 });
  assert.equal(araucaria.cabe, true, 'o book de 190 continua podendo rodar');
  assert.equal(araucaria.fracao, 0.88);
  assert.match(araucaria.mensagem, /88%/);
  assert.match(araucaria.mensagem, /um book por dia/);
  // As duas ignorâncias declaradas, e é o ponto: um "cabe" que escondesse a
  // premissa "supondo que hoje ainda não rodou nada" seria ausência apresentada
  // como dado.
  assert.match(araucaria.mensagem, /não é visível daqui/);
  assert.match(araucaria.mensagem, /RETENTATIVA também conta/);

  // Só o impossível é recusado.
  const naoCabe = vereditoDaCotaDiaria({ chamadas: 501, rpd: 500 });
  assert.equal(naoCabe.cabe, false);
  assert.match(naoCabe.mensagem, /não cabe num dia inteiro nem sozinho/);
  assert.match(naoCabe.mensagem, /MATA os documentos que faltavam/, 'diz o efeito, não só o fato');
  assert.match(naoCabe.mensagem, /reenviar não\s+duplica nem custa/);

  // RPD ausente é "não sei", NUNCA "cabe". A OpenAI não publica um número único
  // para o Tier 1, e transformar isso num veredito verde seria inventar folga.
  const semRpd = vereditoDaCotaDiaria({ chamadas: 9000, rpd: null });
  assert.equal(semRpd.conhecido, false);
  assert.equal(semRpd.fracao, null);
  assert.equal(semRpd.mensagem, null);
});

// ---------------------------------------------------------------------------
// O ESFORÇO DE RACIOCÍNIO — a regra do dono (11/09/2026), e o limiar que a torna
// auditável em vez de opinião.
// ---------------------------------------------------------------------------

test('o limiar de raciocínio é a aritmética da regra, não um número escolhido', () => {
  // A conta que o limiar resolve, escrita de novo aqui de propósito: se o teste
  // repetisse a fórmula da lib, ele não provaria nada (seria o espelho sem
  // guarda). Prova-se pela DEFINIÇÃO — monta-se o custo dos dois lados e
  // confere-se que, exatamente no limiar, o caro custa (1+folga) vezes o barato.
  const preco = { entrada: 0.20, entrada_cache: 0.02, saida: 1.20 };
  const entrada = 3500;
  const saida = 7571;
  const folga = 0.5;

  const limiar = limiarDeRaciocinio({ entrada, saida, folga, preco });
  const custo = (raciocinio) => (entrada * preco.entrada + (saida + raciocinio) * preco.saida) / 1e6;

  // No limiar, a razão é exatamente 1 + folga.
  assert.ok(Math.abs(custo(limiar) / custo(0) - (1 + folga)) < 1e-9,
    `no limiar a razão deveria ser ${1 + folga} e é ${custo(limiar) / custo(0)}`);
  // Um token acima, a regra é violada.
  assert.ok(custo(limiar + 1) > custo(0) * (1 + folga));
});

test('a classificação quase não tem folga, e é por isso que ela cai em "none"', () => {
  // O FATO QUE ESTE TESTE TRAVA, e que não é óbvio: a classificação manda o PDF
  // INTEIRO de entrada e devolve ~120 tokens. A folga de 25% incide sobre um
  // custo dominado pela ENTRADA, então ela vale pouquíssimos tokens de saída —
  // e qualquer raciocínio real estoura. Se um dia alguém baratear a entrada (só
  // mandar texto, por exemplo), este limiar sobe e a decisão pode mudar
  // legitimamente — mas aí é por medição, não por descuido.
  const preco = PRECOS_POR_PROVEDOR.openai['gpt-5.6-luna'];
  const limiar = limiarDeRaciocinio({
    entrada: PERFIL_MEDIDO.entradaPorDocumento,
    saida: PERFIL_MEDIDO.saidaClassificacao,
    folga: FOLGA_CLASSIFICACAO,
    preco,
  });
  assert.ok(limiar < 200,
    `o limiar da classificação é ${limiar} tokens — se passou de 200, a premissa da decisão mudou`);

  // Sem medição, a função NÃO promove o nível caro: devolve o barato e DIZ que
  // não mediu. É a regra 1 aplicada a configuração — "não medi" não pode sair
  // vestido de "medi e deu isto".
  const semMedir = escolherEsforco({
    barato: 'none',
    caro: 'low',
    entrada: PERFIL_MEDIDO.entradaPorDocumento,
    saida: PERFIL_MEDIDO.saidaClassificacao,
    folga: FOLGA_CLASSIFICACAO,
    preco,
  });
  assert.equal(semMedir.esforco, 'none');
  assert.match(semMedir.porque, /não foi medid/i);
});

test('medido acima do limiar, a regra REBAIXA o esforço — e medido abaixo, promove', () => {
  const preco = PRECOS_POR_PROVEDOR.openai['gpt-5.6-luna'];
  const base = {
    barato: 'low',
    caro: 'medium',
    entrada: PERFIL_MEDIDO.entradaPorDocumento,
    saida: PERFIL_MEDIDO.saidaExtracao,
    folga: FOLGA_EXTRACAO,
    preco,
  };
  const limiar = limiarDeRaciocinio(base);
  assert.equal(escolherEsforco({ ...base, raciocinioMedido: Math.floor(limiar) - 1 }).esforco, 'medium');
  assert.equal(escolherEsforco({ ...base, raciocinioMedido: Math.ceil(limiar) + 1 }).esforco, 'low');
});

test('modelo sem preço não inventa limiar — devolve o barato e declara por quê', () => {
  const r = escolherEsforco({
    barato: 'none', caro: 'low', entrada: 3500, saida: 120,
    folga: 0.25, preco: undefined, raciocinioMedido: 10,
  });
  assert.equal(r.esforco, 'none');
  assert.equal(r.limiar, null);
  assert.match(r.porque, /desconhecid/i);
});

test('provedor que não raciocina não recebe esforço nenhum (campo desconhecido é 400)', () => {
  const so = esforcosDoProvedor('gemini-2.5-flash-lite', 'gemini-2.5-flash-lite', PRECOS_POR_PROVEDOR.google);
  assert.equal(so.extracao, null);
  assert.equal(so.classificacao, null);
});

test('o corpo do Gemini NUNCA leva reasoning_effort — inclusive com o modelo CONFIGURADO, que raciocina', () => {
  // A VERSÃO ANTERIOR DESTE PORTÃO ERA UMA FIXTURE NASCIDA PARA PASSAR, e uma
  // revisão pegou: ela chamava `esforcosDoProvedor` com `gemini-2.5-flash-lite`,
  // que NÃO é o modelo configurado para o Google. O configurado é o
  // `gemini-3.5-flash-lite`, e ele É modelo de raciocínio (`raciocina: true`,
  // porque gasta `thoughtsTokenCount` de verdade) — então para ELE a função
  // devolve esforço, e o `null` que o teste afirmava nunca descrevia a rodada
  // real. O teste passava sem medir o caminho que a produção percorre.
  //
  // O INVARIANTE QUE DE FATO PROTEGE contra o 400 não é "a função devolve
  // null": é o CORPO não carregar o campo. Quem garante isso é o dialeto em
  // `montarCorpoIA` — o ramo gemini não escreve `reasoning_effort` nem quando
  // recebe um esforço. É isso que se afirma aqui, com o modelo de verdade.
  const modeloReal = MODELOS_POR_PROVEDOR.google.extracao;
  const corpo = montarCorpoIA(PROVEDORES.google, {
    modelo: modeloReal,
    sistema: 'S',
    partes: [{ text: 'x' }],
    maxTokens: 16384,
    esforco: 'medium',
  });
  assert.equal(corpo.reasoning_effort, undefined,
    'o corpo do Gemini levou reasoning_effort — isso é 400 na chamada inteira');
  assert.equal(corpo.generationConfig.maxOutputTokens, 16384,
    'e o teto continua no campo que o Gemini entende');
});

test('o espelho de TOKENS_SAIDA_CLASSIFICACAO não pode divergir do PERFIL_MEDIDO', () => {
  // Os dois números são o MESMO fato escrito em dois lugares, e este repositório
  // já viu um espelho assim divergir. Aqui ele reprova.
  assert.equal(PERFIL_MEDIDO.saidaClassificacao, TOKENS_SAIDA_CLASSIFICACAO);
});
