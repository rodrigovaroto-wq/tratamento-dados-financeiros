import { test } from 'node:test';
import assert from 'node:assert/strict';
import { normalize } from '../lib/normalize.mjs';
import { classifyByFilename, parsePeriodo, parseTipo } from '../lib/classifier.mjs';

test('normalize remove acento, extensão e separadores', () => {
  assert.equal(normalize('12M25_DRE (Assinado).pdf'), '12m25 dre (assinado)');
  assert.equal(normalize('Balanço-Patrimonial.XLSX'), 'balanco patrimonial');
  assert.equal(normalize(null), '');
});

test('parsePeriodo reconhece as convenções de f0/03', () => {
  assert.deepEqual(parsePeriodo('12m25 dre'), { tipo: 'anual', referencia: '12M25' });
  assert.deepEqual(parsePeriodo('12m24 balanco'), { tipo: 'anual', referencia: '12M24' });
  assert.deepEqual(parsePeriodo('1t25 dre'), { tipo: 'trimestre', referencia: '1T25' });
  assert.deepEqual(parsePeriodo('1t26 balanco'), { tipo: 'trimestre', referencia: '1T26' });
  assert.deepEqual(parsePeriodo('faturamento l24m'), { tipo: 'multi', referencia: 'L24M' });
  assert.deepEqual(parsePeriodo('faturamento 36 meses'), { tipo: 'multi', referencia: 'L36M' });
  assert.deepEqual(parsePeriodo('mutuos 23 24 25'), { tipo: 'multi', referencia: '23,24,25' });
});

test('parsePeriodo reconhece ano isolado (sinal fraco)', () => {
  assert.deepEqual(parsePeriodo('balanco acumulado 2025'), { tipo: 'anual', referencia: '2025', fraco: true });
  assert.deepEqual(parsePeriodo('relatorio 2024'), { tipo: 'anual', referencia: '2024', fraco: true });
});

test('parsePeriodo reconhece intervalo de anos (expande a lista inteira)', () => {
  assert.deepEqual(parsePeriodo('mutuos 2021-2025'), { tipo: 'multi', referencia: '21,22,23,24,25' });
  assert.deepEqual(parsePeriodo('mutuos 2021 a 2025'), { tipo: 'multi', referencia: '21,22,23,24,25' });
  assert.deepEqual(parsePeriodo('mutuos 21-25'), { tipo: 'multi', referencia: '21,22,23,24,25' });
  assert.deepEqual(parsePeriodo('mutuos 2023-2024'), { tipo: 'multi', referencia: '23,24' });
});

test('parsePeriodo: intervalo invertido (fim < início) não expande, cai no fallback de lista', () => {
  // start > end: a expansão não roda; ainda assim os 2 números viram lista
  // multi-ano — ORDENADA, para que "2025-2021" e "2021,2025" tenham a MESMA
  // forma canônica (o mesmo critério de `fn_periodo_canonico` no Postgres:
  // notações equivalentes do mesmo período não podem parecer divergentes).
  assert.deepEqual(parsePeriodo('mutuos 2025-2021'), { tipo: 'multi', referencia: '21,25' });
});

test('parsePeriodo: prefixo de ORDENAÇÃO do arquivo não é ano (bug real do teste v24)', () => {
  // "13_Balancete_..._2025.pdf" saía como período "multi 13,25" — o "13" do
  // prefixo virava 2013. Além de exibir errado, fragmentava a tabela `periodo`
  // e impedia a reconciliação de casar documentos do mesmo exercício.
  assert.deepEqual(parsePeriodo('13 balancete analitico componentes 2025'),
    { tipo: 'anual', referencia: '2025', fraco: true });
  assert.deepEqual(parsePeriodo('08 dfc vertentes metalurgica 2025'),
    { tipo: 'anual', referencia: '2025', fraco: true });
  // "2025x2024" é o padrão de nome de demonstração comparativa.
  assert.deepEqual(parsePeriodo('01 bp vertentes metalurgica 2025x2024'),
    { tipo: 'multi', referencia: '24,25' });
  // Não regride os formatos estruturados nem o ano isolado.
  assert.deepEqual(parsePeriodo('12m25 dre'), { tipo: 'anual', referencia: '12M25' });
  assert.deepEqual(parsePeriodo('1t25 dre'), { tipo: 'trimestre', referencia: '1T25' });
  assert.deepEqual(parsePeriodo('faturamento 36 meses'), { tipo: 'multi', referencia: 'L36M' });
  assert.deepEqual(parsePeriodo('balanco acumulado 2025'), { tipo: 'anual', referencia: '2025', fraco: true });
});

test('parseTipo mapeia termos → código, específico antes de genérico', () => {
  assert.equal(parseTipo('dre').codigo, 'DRE');
  assert.equal(parseTipo('balanco patrimonial').codigo, 'BALANCO');
  assert.equal(parseTipo('fluxo de caixa').codigo, 'FLUXO_CAIXA');
  assert.equal(parseTipo('combinado').codigo, 'COMBINADO');
  assert.equal(parseTipo('contrato social').codigo, 'CONTRATO_SOCIAL');
  assert.equal(parseTipo('relacao de mutuos').codigo, 'MUTUOS');
  // "faturamento intragrupo" NÃO pode cair em FATURAMENTO_24M
  assert.equal(parseTipo('faturamento intragrupo').codigo, 'FAT_INTRAGRUPO');
  assert.equal(parseTipo('faturamento 24m').codigo, 'FATURAMENTO_24M');
  // balancete (variável) não pode ser confundido com balanço
  assert.equal(parseTipo('balancete').codigo, 'BALANCETE');
});

test('parseTipo reconhece DMPL e DVA (db/migrations/0024) sem roubar o arquivo COMPOSTO', () => {
  // Antes da 0024 não existia código nenhum para estas duas: o enum que a IA
  // recebe (`codigosConhecidos`) é fechado nos códigos da taxonomia, e a DMPL do
  // book saía classificada como MUTUOS — o vizinho mais próximo do que existia.
  assert.equal(parseTipo(normalize('09_DMPL_Vertentes_Metalurgica_2025.pdf')).codigo, 'DMPL');
  assert.equal(parseTipo(normalize('Demonstração das Mutações do Patrimônio Líquido 2025.pdf')).codigo, 'DMPL');
  assert.equal(parseTipo(normalize('DVA 2025.pdf')).codigo, 'DVA');
  assert.equal(parseTipo(normalize('Demonstração do Valor Adicionado 2025.pdf')).codigo, 'DVA');

  // …e a regressão que a ORDEM dos aliases protege: o caso comum de "DMPL" no
  // nome de arquivo NÃO é a DMPL — é o arquivo COMPOSTO (este é um nome real do
  // dono), em que a DMPL é uma das demonstrações e o tipo do documento é o da
  // demonstração PRINCIPAL (f0/03). Se DMPL/DVA fossem testados antes das
  // demonstrações principais, estes dois arquivos mudariam de tipo.
  // (Qual das principais ganha é decisão anterior a esta fatia: aqui 'dfc' casa
  // FLUXO_CAIXA antes de 'balanco'. O que importa é que não vira DMPL — e o
  // diagnóstico por CONTEÚDO, que é quem decide de fato, corrige o resto.)
  const composto = parseTipo(normalize('Balanço Patrimonial DRE, DFC, DMPL Global One 2024assinado.pdf'));
  assert.notEqual(composto.codigo, 'DMPL');
  assert.equal(composto.codigo, 'FLUXO_CAIXA');
  assert.equal(parseTipo(normalize('DRE e DVA consolidadas 2025.pdf')).codigo, 'DRE');
});

test('classifyByFilename — nomes descritivos dão alta confiança', () => {
  const r = classifyByFilename('12M25 DRE (Assinado).pdf');
  assert.equal(r.tipo_taxonomia, 'DRE');
  assert.deepEqual(r.periodo, { tipo: 'anual', referencia: '12M25' });
  assert.equal(r.assinado, true);
  assert.ok(r.confianca >= 0.9, `confianca=${r.confianca}`);
  assert.equal(r.precisa_fallback_openai, false);
});

test('classifyByFilename — nome genérico cai para fallback OpenAI', () => {
  const r = classifyByFilename('documento_final_v2.pdf');
  assert.equal(r.tipo_taxonomia, null);
  assert.equal(r.periodo, null);
  assert.ok(r.confianca < 0.7);
  assert.equal(r.precisa_fallback_openai, true);
});

test('classifyByFilename — tipo sem período ainda pede fallback (confiança 0.6)', () => {
  const r = classifyByFilename('balanco.pdf');
  assert.equal(r.tipo_taxonomia, 'BALANCO');
  assert.equal(r.periodo, null);
  assert.equal(r.confianca, 0.6);
  assert.equal(r.precisa_fallback_openai, true); // < 0.7
});

test('classifyByFilename — tipo + ano isolado NÃO ultrapassa o limiar sozinho (sempre verifica com a IA)', () => {
  // Caso real: "BALANÇO ACUMULADO 2025.pdf" — ter "BALANÇO" no nome + um ano
  // solto não é suficiente para aceitar sem checar o conteúdo (feedback do dono).
  const r = classifyByFilename('BALANÇO ACUMULADO 2025.pdf');
  assert.equal(r.tipo_taxonomia, 'BALANCO');
  assert.deepEqual(r.periodo, { tipo: 'anual', referencia: '2025', fraco: true });
  assert.equal(r.confianca, 0.65, `confianca=${r.confianca} deve ficar abaixo do limiar 0.7`);
  assert.equal(r.precisa_fallback_openai, true, 'ano isolado não deve pular a verificação da IA');
});

test('classifyByFilename — o CONJUNTO do exercício é DF_AUDITADA, e nome com demonstração principal não é', () => {
  // Como o conjunto chega de verdade: um PDF só, com tudo dentro. Antes ficava
  // SEM TIPO (a taxonomia só reconhecia "auditadas"), e documento sem tipo não
  // ganha aba de demonstração nenhuma no export.
  for (const nome of [
    'Demonstrações Contábeis 2025.pdf',
    'Demonstrações Financeiras 12M25.pdf',
    'DFs Grupo Vertentes 2025.pdf',
  ]) {
    assert.equal(classifyByFilename(nome).tipo_taxonomia, 'DF_AUDITADA', `tipo de ${nome}`);
  }
  // …e a fronteira: nome que diz QUAL demonstração é continua sendo dela — os
  // termos novos NÃO podem roubar esses casos. É o mesmo motivo pelo qual DMPL/DVA
  // vêm depois das principais.
  assert.equal(classifyByFilename('Demonstrações Combinadas 12M25.pdf').tipo_taxonomia, 'COMBINADO');
  assert.equal(classifyByFilename('Demonstração de Resultado 2025.pdf').tipo_taxonomia, 'DRE');
  assert.equal(classifyByFilename('Balanço Patrimonial 12M25.pdf').tipo_taxonomia, 'BALANCO');
  // Comportamento ANTERIOR a esta fatia, preservado de propósito: o PDF composto
  // que lista as demonstrações no nome ("Balanço Patrimonial DRE, DFC 2024.pdf",
  // arquivo real do dono) casa FLUXO_CAIXA pelo "dfc", porque FLUXO vem antes na
  // lista. Não mexo aqui: promovê-lo a DF_AUDITADA (complementar) tiraria dele a
  // capacidade de satisfazer os itens OBRIGATÓRIOS do Kit Básico e mudaria a
  // completude de todo caso já aberto — decisão de produto do dono, não efeito
  // colateral de uma fatia de export. E, de qualquer forma, o roteamento por
  // linha já separa as demonstrações desse arquivo aba por aba.
  assert.equal(classifyByFilename('Balanço Patrimonial DRE, DFC 2024.pdf').tipo_taxonomia, 'FLUXO_CAIXA');
});

test('classifyByFilename — casos reais do mandato de referência', () => {
  const casos = [
    ['Balancetes 1T2026 Empresa A.pdf', 'BALANCETE', '1T26'],
    ['12M24 Combinado Assinado.pdf', 'COMBINADO', '12M24'],
    ['Faturamento 36 meses.xlsx', 'FATURAMENTO_24M', 'L36M'],
    ['Balanço Patrimonial 12M25.pdf', 'BALANCO', '12M25'],
  ];
  for (const [nome, tipo, ref] of casos) {
    const r = classifyByFilename(nome);
    assert.equal(r.tipo_taxonomia, tipo, `tipo de ${nome}`);
    assert.equal(r.periodo?.referencia, ref, `periodo de ${nome}`);
  }
});
