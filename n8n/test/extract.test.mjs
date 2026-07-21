import { test } from 'node:test';
import assert from 'node:assert/strict';
import { buildExtractionRequest, parseExtractionResponse, extractionSchema, SECAO_CANONICA_ENUM } from '../lib/extract.mjs';
import { spreadsheetToText, parseCsv } from '../lib/spreadsheet.mjs';
import { contentPartFromFile } from '../lib/openai.mjs';

test('extractionSchema é estrito, tem diagnóstico e array de linhas com seção', () => {
  const s = extractionSchema();
  assert.equal(s.strict, true);
  assert.equal(s.schema.properties.linhas.type, 'array');
  assert.equal(s.schema.properties.linhas.items.additionalProperties, false);
  assert.ok(s.schema.properties.linhas.items.required.includes('secao'));
  assert.ok(s.schema.properties.linhas.items.required.includes('secao_canonica'));
  assert.deepEqual(s.schema.properties.linhas.items.properties.secao_canonica.enum, SECAO_CANONICA_ENUM);
  assert.ok(s.schema.properties.linhas.items.properties.secao_canonica.enum.includes('NAO_CLASSIFICAVEL'));
  assert.equal(s.schema.properties.diagnostico.type, 'object');
  assert.ok(s.schema.properties.diagnostico.required.includes('legibilidade'));
  assert.ok(s.schema.properties.diagnostico.properties.tipo_sugerido.enum.includes('DESCONHECIDO'));
});

test('buildExtractionRequest inclui o conteúdo, o nome do arquivo e o schema de diagnóstico+extração', () => {
  const parte = contentPartFromFile({ mimeType: 'application/pdf', base64: 'QUJD', filename: 'dre.pdf' });
  const req = buildExtractionRequest({ tipo: 'DRE', nomeOriginal: 'dre.pdf', conteudo: parte });
  assert.equal(req.body.response_format.json_schema.name, 'diagnostico_e_extracao');
  assert.ok(req.body.messages[1].content.some((c) => c.type === 'file'));
  assert.match(req.body.messages[1].content[0].text, /dre\.pdf/);
});

test('parseExtractionResponse normaliza linhas (com seção) e diagnóstico', () => {
  const api = { choices: [{ message: { content: JSON.stringify({
    moeda: 'BRL', unidade: 'R$ mil',
    diagnostico: {
      entidade: 'Empresa X Ltda', tipo_confirma: true, tipo_sugerido: 'DRE',
      periodo_tipo: 'anual', periodo_referencia: '12M25',
      legibilidade: 'ok', nota_legibilidade: null,
      resumo: 'DRE anual de 2025 com receita e custos detalhados.',
      justificativa: 'Cabeçalho e estrutura batem com DRE.',
    },
    linhas: [
      { secao: 'Receita Operacional', secao_canonica: 'receita_bruta', chave: 'Receita líquida', valor_texto: '10.000', valor_num: 10000, origem_pagina: 1, confianca: 0.8 },
      { secao: 'Custos', secao_canonica: 'custos', chave: 'Custo', valor_texto: '(6.000)', valor_num: -6000, origem_pagina: 1, confianca: 0.7 },
      { secao: null, secao_canonica: 'NAO_CLASSIFICAVEL', chave: 'Total geral', valor_texto: '4.000', valor_num: 4000, origem_pagina: 1, confianca: 0.9 },
    ],
  }) } }] };
  const r = parseExtractionResponse(api);
  assert.equal(r.unidade, 'R$ mil');
  assert.equal(r.campos.length, 3);
  assert.equal(r.campos[0].secao, 'Receita Operacional');
  assert.equal(r.campos[0].secao_canonica, 'receita_bruta');
  assert.equal(r.campos[0].chave, 'Receita líquida');
  assert.equal(r.campos[0].valor_num, 10000);
  assert.equal(r.campos[0].unidade, 'R$ mil'); // herda a unidade do documento
  assert.equal(r.campos[1].secao_canonica, 'custos');
  assert.equal(r.campos[2].secao_canonica, null); // NAO_CLASSIFICAVEL vira null
  assert.equal(r.diagnostico.entidade, 'Empresa X Ltda');
  assert.equal(r.diagnostico.tipo_confirma, true);
  assert.equal(r.diagnostico.legibilidade, 'ok');
});

test('parseExtractionResponse normaliza tipo_sugerido=DESCONHECIDO para null', () => {
  const api = { choices: [{ message: { content: JSON.stringify({
    moeda: null, unidade: null,
    diagnostico: {
      entidade: null, tipo_confirma: false, tipo_sugerido: 'DESCONHECIDO',
      periodo_tipo: 'desconhecido', periodo_referencia: null,
      legibilidade: 'ilegivel', nota_legibilidade: 'Digitalização ilegível, páginas em branco.',
      resumo: 'Não foi possível ler o conteúdo.', justificativa: 'Arquivo corrompido/ilegível.',
    },
    linhas: [],
  }) } }] };
  const r = parseExtractionResponse(api);
  assert.equal(r.diagnostico.tipo_sugerido, null);
  assert.equal(r.diagnostico.legibilidade, 'ilegivel');
  assert.equal(r.diagnostico.nota_legibilidade, 'Digitalização ilegível, páginas em branco.');
});

test('parseExtractionResponse tolera resposta vazia/ruim', () => {
  assert.deepEqual(parseExtractionResponse({}).campos, []);
  assert.deepEqual(parseExtractionResponse({ choices: [{ message: { content: 'nao-json' } }] }).campos, []);
  assert.equal(parseExtractionResponse({}).diagnostico.entidade, null);
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
