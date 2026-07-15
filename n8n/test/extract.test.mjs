import { test } from 'node:test';
import assert from 'node:assert/strict';
import { buildExtractionRequest, parseExtractionResponse, extractionSchema } from '../lib/extract.mjs';
import { spreadsheetToText, parseCsv } from '../lib/spreadsheet.mjs';
import { contentPartFromFile } from '../lib/openai.mjs';

test('extractionSchema é estrito e tem array de linhas', () => {
  const s = extractionSchema();
  assert.equal(s.strict, true);
  assert.equal(s.schema.properties.linhas.type, 'array');
  assert.equal(s.schema.properties.linhas.items.additionalProperties, false);
});

test('buildExtractionRequest inclui o conteúdo e o schema de extração', () => {
  const parte = contentPartFromFile({ mimeType: 'application/pdf', base64: 'QUJD', filename: 'dre.pdf' });
  const req = buildExtractionRequest({ tipo: 'DRE', conteudo: parte });
  assert.equal(req.body.response_format.json_schema.name, 'extracao_linhas_financeiras');
  assert.ok(req.body.messages[1].content.some((c) => c.type === 'file'));
});

test('parseExtractionResponse normaliza linhas p/ fn_registrar_campos_extraidos', () => {
  const api = { choices: [{ message: { content: JSON.stringify({
    moeda: 'BRL', unidade: 'R$ mil',
    linhas: [
      { chave: 'Receita líquida', valor_texto: '10.000', valor_num: 10000, origem_pagina: 1, confianca: 0.8 },
      { chave: 'Custo', valor_texto: '(6.000)', valor_num: -6000, origem_pagina: 1, confianca: 0.7 },
    ],
  }) } }] };
  const r = parseExtractionResponse(api);
  assert.equal(r.unidade, 'R$ mil');
  assert.equal(r.campos.length, 2);
  assert.equal(r.campos[0].chave, 'Receita líquida');
  assert.equal(r.campos[0].valor_num, 10000);
  assert.equal(r.campos[0].unidade, 'R$ mil'); // herda a unidade do documento
});

test('parseExtractionResponse tolera resposta vazia/ruim', () => {
  assert.deepEqual(parseExtractionResponse({}).campos, []);
  assert.deepEqual(parseExtractionResponse({ choices: [{ message: { content: 'nao-json' } }] }).campos, []);
});

test('spreadsheetToText resume linhas com cabeçalho', () => {
  const rows = [ { Conta: 'Receita', Valor: '100' }, { Conta: 'Custo', Valor: '-60' } ];
  const t = spreadsheetToText(rows);
  assert.match(t, /Conta \| Valor/);
  assert.match(t, /Receita \| 100/);
});

test('spreadsheetToText trunca e sinaliza linhas omitidas', () => {
  const rows = Array.from({ length: 120 }, (_, i) => ({ A: i }));
  const t = spreadsheetToText(rows, { maxRows: 10 });
  assert.match(t, /\+110 linhas omitidas/);
});

test('parseCsv detecta separador e monta objetos', () => {
  const csv = 'Conta;Valor\nReceita;100\nCusto;-60';
  const rows = parseCsv(csv);
  assert.equal(rows.length, 2);
  assert.deepEqual(rows[0], { Conta: 'Receita', Valor: '100' });
});
