import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
  linhasComNumero, linhasDeConta, celulasDaLinha, celulasEstimadas,
  planejarFatias, instrucaoDaFatia, juntarBlocos, avaliarCobertura,
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

// ---------------------------------------------------------------------------
// O PESO DA LINHA EM CÉLULAS — o erro de unidade que desligava o fatiamento.
// ---------------------------------------------------------------------------
test('celulasDaLinha conta as CÉLULAS da linha, não a linha', () => {
  // Uma linha de comparativo de três exercícios produz TRÊS células. Era isto que
  // o fatiamento contava como 1, e é por isso que ele nunca disparava.
  assert.equal(celulasDaLinha('Caixa e bancos conta movimento 610 1.420 2.870'), 3);
  // O parêntese contábil de negativo não parte o número em dois.
  assert.equal(celulasDaLinha('(-) Perdas estimadas (6.267) (2.858)'), 2);
  assert.equal(celulasDaLinha('TOTAL DO ATIVO 158.801'), 1);
  // Decimal com vírgula é UM número, não dois.
  assert.equal(celulasDaLinha('Bobina kraft 180 g/m2 1.240 t 2.513'), 4);
  // MÍNIMO 1: a linha veio de `linhasComNumero`, então tem dígito. Zero faria o
  // acumulador do fatiamento não avançar e um bloco crescer sem fim.
  assert.equal(celulasDaLinha('Nota 2 sem valor'), 1);
  assert.equal(celulasDaLinha(''), 1);
  assert.equal(celulasDaLinha(null), 1);
});

test('celulasEstimadas devolve um peso por linha, na ordem', () => {
  const pesos = celulasEstimadas(['a 1', 'b 1 2 3', 'c 1 2']);
  assert.deepEqual(pesos, [1, 3, 2]);
  assert.deepEqual(celulasEstimadas(null), []);
});

test('planejarFatias corta por CÉLULA: o comparativo de 3 colunas vira 3× mais blocos', () => {
  // 200 linhas de UMA coluna cabem num bloco (200 <= 234). O rótulo NÃO leva
  // dígito de propósito: número no rótulo (índice, número de lançamento, código)
  // conta como célula, e é justamente daí que vem o erro para cima de +64% que
  // `celulasDaLinha` documenta e aceita.
  const umaColuna = Array.from({ length: 200 }, (_, i) => `conta ${'x'.repeat(1 + (i % 5))} 1.000`);
  assert.equal(planejarFatias(umaColuna, MAX_CELULAS_POR_BLOCO, celulasEstimadas(umaColuna)).length, 1);
  // AS MESMAS 200 LINHAS com três colunas são 600 células e NÃO cabem — pela
  // contagem de linhas cabiam, e era exatamente esse o defeito.
  const tresColunas = Array.from({ length: 200 }, (_, i) => `conta ${'x'.repeat(1 + (i % 5))} 1.000 2.000 3.000`);
  const semPeso = planejarFatias(tresColunas, MAX_CELULAS_POR_BLOCO);
  const comPeso = planejarFatias(tresColunas, MAX_CELULAS_POR_BLOCO, celulasEstimadas(tresColunas));
  assert.equal(semPeso.length, 1, 'a contagem por LINHA achava que cabia — é o defeito');
  assert.ok(comPeso.length >= 3, `por CÉLULA são ${comPeso.length} blocos`);
  for (const b of comPeso) {
    assert.ok(b.celulas <= MAX_CELULAS_POR_BLOCO, `bloco ${b.bloco} com ${b.celulas} células`);
    assert.ok(b.celulas * TOKENS_POR_CELULA <= TETO_SAIDA_TOKENS, 'e portanto cabe no teto de saída');
  }
});

test('planejarFatias: os blocos cobrem tudo, sem buraco nem sobreposição, com peso', () => {
  const linhas = Array.from({ length: 461 }, (_, i) => `PAGTO ${i} 1.000,00 2.000,00`);
  const f = planejarFatias(linhas, MAX_CELULAS_POR_BLOCO, celulasEstimadas(linhas));
  assert.equal(f[0].de, 0);
  assert.equal(f[f.length - 1].ate, 460);
  for (let i = 1; i < f.length; i += 1) assert.equal(f[i].de, f[i - 1].ate + 1);
  // O `blocos` declarado é o REAL: instrução dizendo "bloco 2 de 3" num plano de
  // 2 manda o modelo procurar um terço que não existe.
  for (const b of f) assert.equal(b.blocos, f.length);
  // Parejo em CÉLULAS (é o que gasta token), com a folga de uma linha inteira —
  // a linha não é partida porque ela é a âncora.
  const cel = f.map((b) => b.celulas);
  const pesoMax = Math.max(...celulasEstimadas(linhas));
  assert.ok(Math.max(...cel) - Math.min(...cel) <= pesoMax, `células por bloco: ${cel}`);
});

test('planejarFatias: `ceil(soma/max)` mentiria — o corte cai entre LINHAS', () => {
  // Dez linhas de peso 4, teto 10. `ceil(40/10)` prevê 4 blocos, e o alvo de 10
  // produziria blocos de 12 — ACIMA do teto que a função existe para respeitar.
  // Medido assim ao escrever a função: [12, 12, 12, 4].
  const linhas = Array.from({ length: 10 }, (_, i) => `linha ${i} 1 2 3`);
  const f = planejarFatias(linhas, 10, linhas.map(() => 4));
  assert.equal(f.length, 5, 'cinco blocos, não os quatro que a divisão prevê');
  for (const b of f) assert.ok(b.celulas <= 10, `bloco com ${b.celulas}`);
  // E nada de toco no fim: a segunda passada reparte parejo.
  const cel = f.map((b) => b.celulas);
  assert.deepEqual(cel, [8, 8, 8, 8, 8]);
});

test('planejarFatias: linha que SOZINHA passa do teto é declarada, não escondida', () => {
  // Não há corte mais fino que a linha — ela é a âncora, e meia âncora não
  // localiza nada no PDF. O único resíduo de truncamento que sobra tem de
  // APARECER, senão volta a ser perda silenciosa.
  const linhas = ['gigante 1 2 3', 'normal 1'];
  const f = planejarFatias(linhas, 10, [300, 1]);
  assert.equal(f[0].acimaDoTeto, true);
  assert.equal(f[1].acimaDoTeto, false);
});

test('juntarBlocos NOMEIA o bloco cuja linha sozinha não cabia', () => {
  // A promessa de `planejarFatias` ("declarada, não escondida") só vale se o
  // aviso CHEGAR a algum lugar. Ele chega aqui, no mesmo campo em que a guarda de
  // cobertura escreve — e `fn_registrar_campos_extraidos` converte isso em
  // pendência desde a 0016.
  const r = juntarBlocos([
    { bloco: 1, blocos: 2, bloco_acima_do_teto: true, campos: [{ chave: 'a', valor_num: 1 }] },
    { bloco: 2, blocos: 2, bloco_acima_do_teto: false, campos: [{ chave: 'b', valor_num: 2 }] },
  ]);
  // `juntarBlocos` devolve `motivos`; é o nó `Juntar Blocos` que os junta em
  // `falha_motivo`, e daí `fn_registrar_campos_extraidos` faz a pendência.
  const texto = r.motivos.join(' | ');
  assert.match(texto, /bloco 1/);
  assert.match(texto, /não há corte mais fino que a linha/);
  assert.ok(!/bloco 2/.test(texto), 'o bloco que cabia não é acusado');
  // E o dado dos DOIS blocos continua chegando: o aviso não descarta nada.
  assert.equal(r.campos.length, 2);
});

test('planejarFatias sem pesos = comportamento antigo (uma célula por linha)', () => {
  // Compatibilidade que importa: o `Orcamento do Lote` e o `Fatiar Extracao`
  // passam pesos, mas a função tem de continuar correta sem eles — documento de
  // uma coluna é o caso em que linha e célula coincidem.
  const linhas = Array.from({ length: 500 }, (_, i) => `linha ${i}`);
  const f = planejarFatias(linhas, 200);
  assert.equal(f.length, 3);
  assert.equal(f.reduce((a, b) => a + b.linhas, 0), 500);
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

// --- a unidade da guarda: LINHA, não conta distinta ---------------------------
// O livro razão do book tem 99 lançamentos e 66 históricos distintos (medido por
// `medir-regua-cobertura.mjs`). Comparar 66 com as 100 linhas que a régua vê dá
// 66% — abaixo do limiar — para uma extração que não perdeu NADA. A guarda
// acusaria de incompleto justamente o documento que motivou as três camadas.

test('juntarBlocos conta LINHAS devolvidas — dois lançamentos do mesmo fornecedor contam dois', () => {
  const linha = (origem, k, v) => ({ linha_origem: origem, chave: k, valor_num: v, valor_texto: String(v) });
  const r = juntarBlocos([
    { bloco: 1, campos: [linha(0, 'PAGTO ARACATI', 150), linha(1, 'PAGTO ARACATI', 221), linha(2, 'PAGTO IPIRANGA', 226)] },
  ]);
  assert.equal(r.linhasRetornadas, 3, 'três lançamentos, ainda que dois tenham o mesmo histórico');
  assert.equal(new Set(r.campos.map((c) => c.chave)).size, 2, 'contas distintas seriam só duas');
  // Com 3 linhas de conta no texto, a extração está COMPLETA e a guarda se cala.
  assert.equal(avaliarCobertura({ extraidas: r.linhasRetornadas, esperadas: 3, minimo: 3 }), null);
  // Era este o falso positivo: 2 de 3 = 67%, o número do livro razão inteiro.
  assert.ok(avaliarCobertura({ extraidas: 2, esperadas: 3, minimo: 3 }), 'a unidade velha acusaria');
});

test('juntarBlocos: uma conta com três colunas é UMA linha — o viés oposto também some', () => {
  // O erro que a régua v1 corrigiu (198%) volta pela outra porta se a contagem
  // for de PARES: três colunas de um DRE comparativo são três campos, uma linha.
  const campo = (origem, k, pc, v) => ({ linha_origem: origem, chave: k, periodo_coluna: pc, valor_num: v });
  const r = juntarBlocos([
    { bloco: 1, campos: [campo(0, 'Receita', '2025', 1), campo(0, 'Receita', '2024', 2), campo(0, 'Receita', '2023', 3),
      campo(1, 'Custo', '2025', 4), campo(1, 'Custo', '2024', 5)] },
  ]);
  assert.equal(r.campos.length, 5, 'o banco continua recebendo par a par');
  assert.equal(r.linhasRetornadas, 2, 'mas o documento tem duas linhas');
});

test('juntarBlocos: `ordem` é a LINHA do documento, não o par (conta × coluna)', () => {
  // A `0027` define `ordem` como "posição na leitura do documento", e o export
  // conta com isso para alinhar a mesma conta ao longo das colunas. Quando a
  // saída virou agrupada, o achatamento numerava PARES: uma conta com três
  // exercícios ganhava três `ordem` distintas, e o Excel da rodada v46 saiu com
  // "Caixa e bancos conta movimento" em três linhas, uma por ano.
  const c = (origem, chave, periodo, valor) => ({ linha_origem: origem, chave, periodo_coluna: periodo, valor_num: valor });
  const r = juntarBlocos([{ bloco: 1, campos: [
    c(0, 'Caixa e bancos', '2025', 606), c(0, 'Caixa e bancos', '2024', 1412), c(0, 'Caixa e bancos', '2023', 2853),
    c(1, 'Aplicações', '2025', 181), c(1, 'Aplicações', '2024', 2114),
  ] }]);
  assert.deepEqual(r.campos.map((x) => x.ordem), [0, 0, 0, 1, 1], 'os pares de uma conta compartilham a ordem da linha');
  assert.equal(r.linhasRetornadas, 2);

  // Em documento fatiado a numeração é contínua entre blocos, e cada bloco
  // numera as suas linhas a partir de zero — sem a chave composta, a linha 0 do
  // bloco 2 colidiria com a linha 0 do bloco 1.
  const fatiado = juntarBlocos([
    { bloco: 1, campos: [c(0, 'A', '2025', 1), c(0, 'A', '2024', 2)] },
    { bloco: 2, campos: [c(0, 'B', '2025', 3), c(1, 'C', '2025', 4)] },
  ]);
  assert.deepEqual(fatiado.campos.map((x) => [x.chave, x.ordem]), [['A', 0], ['A', 0], ['B', 1], ['C', 2]]);
});

test('juntarBlocos: `linha_origem` NÃO chega ao banco, e o bloco antigo sem ele não zera a guarda', () => {
  const r = juntarBlocos([{ bloco: 1, campos: [{ linha_origem: 0, chave: 'A', valor_num: 1 }] }]);
  assert.equal(Object.hasOwn(r.campos[0], 'linha_origem'), false, 'sai antes de virar campo_extraido');
  // Formato plano antigo (workflow importado meses atrás): sem `linha_origem` a
  // contagem é zero, e quem chama cai para as contas distintas — o comportamento
  // de antes desta correção, em vez de "extraiu zero linhas".
  const antigo = juntarBlocos([{ bloco: 1, campos: [{ chave: 'A', valor_num: 1 }, { chave: 'B', valor_num: 2 }] }]);
  assert.equal(antigo.linhasRetornadas, 0);
  assert.equal(antigo.campos.length, 2);
});

test('juntarBlocos: o motivo de falha de UM bloco não some na junção', () => {
  const r = juntarBlocos([
    { bloco: 1, campos: [{ chave: 'A' }], falha_motivo: null },
    { bloco: 2, campos: [], falha_motivo: 'Resposta truncada' },
  ]);
  assert.equal(r.campos.length, 1);
  assert.deepEqual(r.motivos, ['bloco 2: Resposta truncada']);
});

test('a régua conta LINHA DE CONTA, não toda linha com dígito', () => {
  // O 02_DRE do book, medido: 46 linhas com dígito, 39 linhas de conta. Os 7
  // descartados são cabeçalho de ano, CNPJ, data por extenso, "Página 1", a nota
  // de rodapé com percentuais, o CRC e o CPF do bloco de assinatura.
  const dre = [
    'Página 1Documento sintético, gerado para teste de sistema.',
    'CANASTRA INDÚSTRIA DE EMBALAGENS LTDA.',
    'CNPJ 44.555.667/0001-59',
    'Exercícios encerrados em 31 de dezembro de 2025, 31 de dezembro de 2024',
    '(Valores expressos em milhares de reais — R$ mil)',
    '2025 2024 2023',
    'RECEITA OPERACIONAL BRUTA 188.000 246.000 318.000',
    'Vendas de embalagens - mercado interno 146.640 191.880 248.040',
    '(-) ICMS sobre vendas (31.960) (41.820) (54.060)',
    'Nota — A margem bruta do exercício de 2025 foi de 2,9% (contra 25,2% em 2023)',
    'Rita M. Andrade — Contadora — CRC 1MG-198.442/O-7',
    'Paulo Sérgio Canastra — Diretor Presidente — CPF 987.654.321-00',
  ].join('\n');
  assert.equal(linhasComNumero(dre).length, 10, 'a régua do FATIAMENTO conta tudo que gasta token');
  assert.deepEqual(linhasDeConta(dre), [
    'RECEITA OPERACIONAL BRUTA 188.000 246.000 318.000',
    'Vendas de embalagens - mercado interno 146.640 191.880 248.040',
    '(-) ICMS sobre vendas (31.960) (41.820) (54.060)',
  ]);
  // Linha só com número não é conta — é célula solta de um extrator que quebrou
  // a tabela em pedaços.
  assert.deepEqual(linhasDeConta('ATIVO\n137.624\n1.000'), []);
});

// --- os três documentos em que a régua v1 era CEGA ---------------------------
// Medido em 17/08 por `n8n/medir-regua-cobertura.mjs`, contra a contagem que o
// gerador do book declara: a v1 via 3 linhas num livro razão de 99 (−97%), 3 num
// balancete de 78 (−96%) e 2 num aging de 14 (−86%). E como a guarda se cala
// abaixo de 20 linhas, a cegueira virava silêncio: justamente os documentos
// analíticos — os que perdem dado — nunca eram avaliados.

test('linha que termina na NATUREZA (D/C) é conta — o balancete inteiro dependia disso', () => {
  const balancete = [
    'Código Conta Saldo D/C',           // cabeçalho: sem valor próprio
    '1.1.01.002 181 D',
    '1.1.02.003 9.644 C',
    'Caixa e equivalentes de caixa 24.861 D',
  ].join('\n');
  // O rótulo do balancete é o CÓDIGO da conta — não tem uma letra sequer, e a
  // régua v1 exigia três. As três linhas de valor contam; o cabeçalho não.
  assert.deepEqual(linhasDeConta(balancete), ['1.1.01.002 181 D', '1.1.02.003 9.644 C',
    'Caixa e equivalentes de caixa 24.861 D']);
});

test('linha de tabela numérica conta como conta — é o aging, onde o rótulo cai em outra linha', () => {
  // O leitor de PDF põe o nome do cliente numa linha e a faixa de valores na
  // seguinte. Contar a linha dos valores conta a conta UMA vez, que é a unidade
  // certa; ignorá-la é o que fazia o aging medir 2 de 14.
  const aging = [
    'Cliente / sacado A vencer 1-30 31-60 61-90 Total %',
    'Distribuidora Alfa Ltda.',
    '1.648 522 402 362 4.019 14,0%',
    'Comercial Beta S.A.',
    '1.295 411 316 284 3.158 11,0%',
  ].join('\n');
  const contadas = linhasDeConta(aging);
  assert.ok(contadas.includes('1.648 522 402 362 4.019 14,0%'), 'a linha de valores do cliente A conta');
  assert.ok(contadas.includes('1.295 411 316 284 3.158 11,0%'), 'a linha de valores do cliente B conta');
  // O cabeçalho de faixas ("1-30 31-60 61-90") entra junto: ele tem rótulo E
  // número, e nenhuma regra honesta o separa de uma linha de dado sem saber o
  // documento. É o viés conhecido da régua — UMA linha a mais por tabela, o que
  // `medir-regua-cobertura.mjs` mede como +2% a +4% nos documentos grandes e até
  // +17% nos pequenos. Sobra de denominador é o erro seguro: ela consome folga do
  // limiar de 0,85, não abre pendência falsa (o pior caso medido no book inteiro
  // é 96% com extração perfeita).
  assert.equal(contadas.length, 3, 'as duas contas mais o cabeçalho de faixas');
});

test('a régua v2 não afrouxou: valor solto, cabeçalho e prosa continuam fora', () => {
  // Um único número sem identidade nenhuma continua sendo célula solta.
  assert.deepEqual(linhasDeConta('16.839'), []);
  // Cabeçalho de ano tem dois valores, mas é ruído declarado.
  assert.deepEqual(linhasDeConta('2025 2024 2023'), []);
  assert.deepEqual(linhasDeConta('31/12/2025 31/12/2024'), []);
  // Nota de rodapé com dois percentuais: prosa, não conta.
  assert.deepEqual(linhasDeConta('Nota — A margem bruta foi de 2,9% (contra 25,2% em 2023)'), []);
  // Linha sem valor nenhum: título de seção. O modelo também não gera linha nela.
  assert.deepEqual(linhasDeConta('ATIVO CIRCULANTE'), []);
});

test('avaliarCobertura compara CONTA com CONTA — a razão antiga passava de 100%', () => {
  // O erro que a régua nova corrige: 91 pares (conta × coluna) contra 46 linhas
  // com dígito dava 198%, e a guarda NUNCA disparava num documento comparativo.
  assert.equal(avaliarCobertura({ extraidas: 91, esperadas: 46 }), null, 'na unidade errada não dispara');
  // Na unidade certa, o mesmo documento: ~30 contas distintas contra 39 linhas
  // de conta = 77%, abaixo do mínimo. Ele ESTÁ incompleto, e ninguém sabia.
  const dre = avaliarCobertura({ extraidas: 30, esperadas: 39 });
  assert.ok(dre, '30 de 39 tem de virar pendência');
  assert.equal(dre.razao, 0.769);
  assert.match(dre.motivo, /30 linha\(s\) devolvida\(s\).*39 linha\(s\)/);
  assert.match(dre.motivo, /MESMA unidade/);
  // A descrição diz o viés conhecido da régua, medido: ela conta ~3% a mais.
  assert.match(dre.motivo, /erra para cima em cerca de 3%/);

  // Documento completo passa.
  assert.equal(avaliarCobertura({ extraidas: 38, esperadas: 39 }), null, '97% passa');
  assert.equal(avaliarCobertura({ extraidas: 39, esperadas: 39 }), null, '100% passa');
});

test('avaliarCobertura se cala quando não tem régua ou quando a régua é ruído', () => {
  // PDF escaneado: sem camada de texto não há contagem, e "não sei" não pode
  // virar veredito — nem para acusar, nem para absolver.
  assert.equal(avaliarCobertura({ extraidas: 3, esperadas: null }), null);
  assert.equal(avaliarCobertura({ extraidas: 3, esperadas: undefined }), null);
  // Documento minúsculo: com 6 linhas, uma a menos derruba a cobertura em 17% e
  // a razão vira ruído.
  assert.equal(avaliarCobertura({ extraidas: 3, esperadas: 6 }), null);
  // O limiar é o declarado, e mexer nele é decisão consciente. 0,85 porque o
  // alvo é cobertura total — e ele é o próximo número a recalibrar, com 35
  // pontos de medição em vez de um.
  assert.equal(LIMIAR_COBERTURA, 0.85);
});

test('as funções são AUTO-CONTIDAS (os nós Code as embutem por toString)', () => {
  // Se alguma passar a referenciar constante do módulo, o nó quebra com
  // ReferenceError na primeira execução real e nenhum teste daqui pega.
  for (const fn of [linhasComNumero, celulasDaLinha, celulasEstimadas,
    planejarFatias, instrucaoDaFatia, juntarBlocos, avaliarCobertura]) {
    assert.doesNotThrow(() => new Function(`return (${fn.toString()})`)(), `${fn.name} não é auto-contida`);
  }
  // `planejarFatias` e `avaliarCobertura` têm default nos parâmetros que vêm de
  // constantes do módulo — conferido aqui chamando as versões isoladas.
  const fatiar = new Function(`return (${planejarFatias.toString()})`)();
  assert.equal(fatiar(['a 1', 'b 2', 'c 3'], 2).length, 2);
  const avaliar = new Function(`const LIMIAR_COBERTURA=0.6;const MINIMO_PARA_AVALIAR=20;return (${avaliarCobertura.toString()})`)();
  assert.ok(avaliar({ extraidas: 10, esperadas: 100 }));
});

// =============================================================================
// OS FATOS MATERIAIS ATRAVESSAM O FATIAMENTO (0148/0149, auditoria)
//
// O DEFEITO QUE ESTES TESTES FECHAM, e ele era silencioso: o nó `Juntar Blocos`
// montava o diagnóstico do documento com `blocos[0].diagnostico`. Para entidade,
// tipo e período isso está CERTO — são propriedades do documento, e todo bloco
// responde a mesma coisa. Para os FATOS não: cada bloco lê um PEDAÇO diferente
// do texto, então um covenant declarado na página 40 chega no bloco 2 e era
// descartado sem nada acusar.
//
// E os documentos fatiados são justamente os grandes: no book de 38, o
// `35_Demonstracoes_Contabeis` e o `01_Balanco` saem em 2 blocos cada, e o
// `17_Livro_Razao` em 4. Nota explicativa mora em documento grande.
test('os fatos de TODOS os blocos sobrevivem à junção', () => {
  const r = juntarBlocos([
    { bloco: 1, campos: [], diagnostico: { entidade: 'Canastra', fatos: [
      { tipo: 'covenant_rompido', trecho: 'o indice apurado nao atingiu o minimo contratado', pagina: 4 },
    ] } },
    { bloco: 2, campos: [], diagnostico: { entidade: 'Canastra', fatos: [
      { tipo: 'ressalva_auditoria', trecho: 'opiniao com ressalva em razao da limitacao de escopo', pagina: 41 },
    ] } },
    { bloco: 3, campos: [], diagnostico: { entidade: 'Canastra', fatos: [] } },
  ]);
  assert.equal(r.fatos.length, 2, 'o fato do bloco 2 não pode se perder');
  assert.deepEqual(r.fatos.map((f) => f.tipo).sort(),
    ['covenant_rompido', 'ressalva_auditoria']);
});

// A EMENDA ENTRE BLOCOS É SOBREPOSTA DE PROPÓSITO (o modelo repete a âncora, ver
// `emendasLimpas` acima), então um fato que caia na região de emenda é declarado
// DUAS vezes. Dois alertas idênticos numa lista curta ensinam a desconfiar dela
// inteira — que é o oposto do que este canal existe para fazer.
test('o mesmo fato declarado em dois blocos entra UMA vez', () => {
  const mesmo = 'o indice apurado em 31/12/2025 nao atingiu o minimo contratado';
  const r = juntarBlocos([
    { bloco: 1, campos: [], diagnostico: { fatos: [{ tipo: 'covenant_rompido', trecho: mesmo, pagina: 4 }] } },
    // mesmo fato, escrito com espaçamento e caixa diferentes, e outra página —
    // continua sendo a mesma frase do mesmo documento.
    { bloco: 2, campos: [], diagnostico: { fatos: [{ tipo: 'covenant_rompido', trecho: '  O INDICE   apurado em 31/12/2025 nao atingiu o MINIMO contratado ', pagina: 5 }] } },
  ]);
  assert.equal(r.fatos.length, 1, 'a deduplicação é por (tipo + trecho normalizado)');
  assert.equal(r.fatos[0].pagina, 4, 'e a primeira ocorrência é a que fica');
});

// O MESMO TRECHO SOB TIPOS DIFERENTES NÃO É O MESMO FATO. Uma nota que declara a
// reclassificação E o rompimento na mesma frase é dois fatos, e colapsá-los
// perderia um alerta.
test('trecho igual com tipos diferentes conta como dois fatos', () => {
  const frase = 'o indice nao foi atingido e os saldos foram reclassificados para o circulante';
  const r = juntarBlocos([
    { bloco: 1, campos: [], diagnostico: { fatos: [
      { tipo: 'covenant_rompido', trecho: frase },
      { tipo: 'reclassificacao_divida', trecho: frase },
    ] } },
  ]);
  assert.equal(r.fatos.length, 2);
});

// `null` NÃO É `[]`, E A DISTINÇÃO ATRAVESSA A JUNÇÃO ATÉ O BANCO.
//
// Nenhum bloco trouxe a chave (workflow antigo importado no n8n) → `null`, e
// `fn_registrar_fatos` NÃO TOCA nos fatos já gravados. Algum bloco leu e não
// achou nada → `[]`, e o banco APAGA. Colapsar os dois faria um n8n
// desatualizado destruir trilha em silêncio — o modo de falha do `Gravar
// Campos` que desligou a reconciliação por onze dias.
test('nenhum bloco com a chave "fatos" devolve null, não lista vazia', () => {
  const r = juntarBlocos([
    { bloco: 1, campos: [], diagnostico: { entidade: 'X' } },
    { bloco: 2, campos: [], diagnostico: { entidade: 'X' } },
  ]);
  assert.equal(r.fatos, null);
});

test('um bloco que leu e não achou nada devolve lista vazia, não null', () => {
  const r = juntarBlocos([
    { bloco: 1, campos: [], diagnostico: { entidade: 'X', fatos: [] } },
    { bloco: 2, campos: [], diagnostico: { entidade: 'X' } },
  ]);
  assert.deepEqual(r.fatos, []);
});

// Entrada degenerada dentro da lista não pode derrubar a junção do documento
// inteiro — o resto dos blocos tem dado bom.
test('lixo dentro de "fatos" não derruba a junção', () => {
  const r = juntarBlocos([
    { bloco: 1, campos: [], diagnostico: { fatos: [null, 42, 'texto', { tipo: 'covenant_rompido', trecho: 'frase que serve como evidencia do rompimento' }] } },
  ]);
  assert.equal(r.fatos.length, 1);
});
