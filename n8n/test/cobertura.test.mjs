import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
  linhasComNumero, linhasDeConta, planejarFatias, instrucaoDaFatia, juntarBlocos, avaliarCobertura,
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
