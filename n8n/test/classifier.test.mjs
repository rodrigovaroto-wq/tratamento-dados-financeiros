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
