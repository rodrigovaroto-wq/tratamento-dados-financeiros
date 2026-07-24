import { test } from 'node:test';
import assert from 'node:assert/strict';
import { buildExtractionRequest, parseExtractionResponse, extractionSchema, SECAO_CANONICA_ENUM } from '../lib/extract.mjs';
import { spreadsheetToText, parseCsv } from '../lib/spreadsheet.mjs';
import { contentPartFromFile } from '../lib/openai.mjs';

test('extractionSchema é estrito, tem diagnóstico e array de linhas com chaves curtas', () => {
  // Chaves curtas de propósito (s/sc/ec/pc/k/vt/vn/op/cf) — economia de
  // tokens de saída em documentos com muitas contas (sessão 7 cont.¹¹).
  const s = extractionSchema();
  assert.equal(s.strict, true);
  assert.equal(s.schema.properties.linhas.type, 'array');
  assert.equal(s.schema.properties.linhas.items.additionalProperties, false);
  assert.ok(s.schema.properties.linhas.items.required.includes('s'), 's=secao');
  assert.ok(s.schema.properties.linhas.items.required.includes('sc'), 'sc=secao_canonica');
  assert.ok(s.schema.properties.linhas.items.required.includes('ec'), 'ec=entidade_coluna');
  assert.deepEqual(s.schema.properties.linhas.items.properties.ec.type, ['string', 'null']);
  assert.deepEqual(s.schema.properties.linhas.items.properties.sc.enum, SECAO_CANONICA_ENUM);
  assert.ok(s.schema.properties.linhas.items.properties.sc.enum.includes('NAO_CLASSIFICAVEL'));
  // Cada chave curta carrega uma description explicando o nome completo, pra
  // não perder a orientação do modelo com o nome cifrado.
  for (const k of ['s', 'sc', 'ec', 'pc', 'k', 'vt', 'vn', 'op', 'cf']) {
    assert.ok(s.schema.properties.linhas.items.properties[k].description, `campo ${k} sem description`);
  }
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
      { s: 'Receita Operacional', sc: 'receita_bruta', k: 'Receita líquida', vt: '10.000', vn: 10000, op: 1, cf: 0.8 },
      { s: 'Custos', sc: 'custos', k: 'Custo', vt: '(6.000)', vn: -6000, op: 1, cf: 0.7 },
      { s: null, sc: 'NAO_CLASSIFICAVEL', k: 'Total geral', vt: '4.000', vn: 4000, op: 1, cf: 0.9 },
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
  assert.equal(r.campos[0].entidade_coluna, null); // documento de 1 entidade só (caso comum)
  assert.equal(r.diagnostico.entidade, 'Empresa X Ltda');
  assert.equal(r.diagnostico.tipo_confirma, true);
  assert.equal(r.diagnostico.legibilidade, 'ok');
});

test('parseExtractionResponse: documento com várias entidades/colunas lado a lado (entidade_coluna por linha)', () => {
  // Achado real (sessão 7, HANDOFF.md): um balanço combinado de 3 entidades
  // (Certsys Tecn/Part/Com + Total) fazia a IA fabricar um valor único por
  // conta em vez de reportar as 3 colunas — o schema não tinha como
  // representar isso. Agora uma mesma "chave" pode aparecer em várias linhas,
  // uma por coluna, com entidade_coluna preenchido.
  const api = { choices: [{ message: { content: JSON.stringify({
    moeda: 'BRL', unidade: null,
    diagnostico: {
      entidade: null, tipo_confirma: true, tipo_sugerido: 'COMBINADO',
      periodo_tipo: 'anual', periodo_referencia: '2025',
      legibilidade: 'ok', nota_legibilidade: null,
      resumo: 'Balanço combinado de 3 entidades do grupo.',
      justificativa: 'Colunas Certsys Tecn/Part/Com + Total.',
    },
    linhas: [
      { s: 'Ativo Circulante', sc: 'ativo_circulante', ec: 'Certsys Tecn', k: 'Bens Numerários', vt: '51,29', vn: 51.29, op: 1, cf: 0.95 },
      { s: 'Ativo Circulante', sc: 'ativo_circulante', ec: 'Certsys Part', k: 'Bens Numerários', vt: '0,00', vn: 0, op: 1, cf: 0.95 },
      { s: 'Ativo Circulante', sc: 'ativo_circulante', ec: 'Certsys Com', k: 'Bens Numerários', vt: '0,00', vn: 0, op: 1, cf: 0.95 },
      { s: 'Ativo Circulante', sc: 'ativo_circulante', ec: 'Total', k: 'Bens Numerários', vt: '51,29', vn: 51.29, op: 1, cf: 0.95 },
    ],
  }) } }] };
  const r = parseExtractionResponse(api);
  assert.equal(r.campos.length, 4, 'uma linha por (conta x coluna), não uma linha só');
  assert.deepEqual(r.campos.map((c) => c.entidade_coluna), ['Certsys Tecn', 'Certsys Part', 'Certsys Com', 'Total']);
  assert.ok(r.campos.every((c) => c.chave === 'Bens Numerários'), 'mesma chave, colunas diferentes');
});

test('parseExtractionResponse: documento comparativo (várias colunas de período) — periodo_coluna por linha', () => {
  // Lacuna real (sessão 7 cont.⁹): "Balanço consolidado 2023 x 2024.pdf" traz
  // 2023 e 2024 lado a lado da MESMA entidade. Sem periodo_coluna, as duas
  // linhas "Caixa" colapsavam numa coluna só no export (perda de dado). Agora
  // uma linha por (conta × período), ortogonal a entidade_coluna.
  const api = { choices: [{ message: { content: JSON.stringify({
    moeda: 'BRL', unidade: 'R$ mil',
    diagnostico: {
      entidade: 'Grupo X', tipo_confirma: true, tipo_sugerido: 'BALANCO',
      periodo_tipo: 'multi', periodo_referencia: '23,24',
      legibilidade: 'ok', nota_legibilidade: null, resumo: 'Balanço comparativo 2023×2024.', justificativa: 'Duas colunas de ano.',
    },
    linhas: [
      { s: 'Ativo Circulante', sc: 'ativo_circulante', ec: null, pc: '2023', k: 'Caixa', vt: '100', vn: 100, op: 1, cf: 0.9 },
      { s: 'Ativo Circulante', sc: 'ativo_circulante', ec: null, pc: '2024', k: 'Caixa', vt: '120', vn: 120, op: 1, cf: 0.9 },
    ],
  }) } }] };
  const r = parseExtractionResponse(api);
  assert.equal(r.campos.length, 2, 'uma linha por (conta × período), não colapsada');
  assert.deepEqual(r.campos.map((c) => c.periodo_coluna), ['2023', '2024']);
  assert.ok(r.campos.every((c) => c.chave === 'Caixa'), 'mesma chave, períodos diferentes');
  assert.ok(r.campos.every((c) => c.entidade_coluna === null), 'periodo_coluna é ortogonal a entidade_coluna');
});

test('extractionSchema inclui pc/periodo_coluna (required + string|null)', () => {
  const s = extractionSchema();
  assert.ok(s.schema.properties.linhas.items.required.includes('pc'));
  assert.deepEqual(s.schema.properties.linhas.items.properties.pc.type, ['string', 'null']);
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

test('buildExtractionRequest define max_tokens explícito (sem isso, documentos combinados grandes truncam a resposta silenciosamente)', () => {
  const parte = contentPartFromFile({ mimeType: 'application/pdf', base64: 'QUJD', filename: 'balanco.pdf' });
  const req = buildExtractionRequest({ tipo: 'COMBINADO', nomeOriginal: 'balanco.pdf', conteudo: parte });
  assert.equal(req.body.max_tokens, 16384);
});

test('parseExtractionResponse: resposta ok não tem falhaMotivo', () => {
  const api = { choices: [{ finish_reason: 'stop', message: { content: JSON.stringify({
    moeda: null, unidade: null,
    diagnostico: {
      entidade: null, tipo_confirma: true, tipo_sugerido: 'DRE',
      periodo_tipo: 'anual', periodo_referencia: '2025',
      legibilidade: 'ok', nota_legibilidade: null, resumo: 'x', justificativa: 'x',
    },
    linhas: [],
  }) } }] };
  assert.equal(parseExtractionResponse(api).falhaMotivo, null);
});

test('parseExtractionResponse: JSON truncado (finish_reason=length) vira falhaMotivo explicativo, não 0 campos silencioso', () => {
  // Achado em produção (sessão 7 cont.⁷, "teste v14"): 16 documentos combinados
  // grandes classificados com sucesso mas extraídos com 0 linhas — a chamada
  // de extração vinha truncada e o parse falhava silenciosamente, sem
  // sinalizar nada. Isso é o que passou a detectar.
  const api = { choices: [{ finish_reason: 'length', message: { content: '{"moeda":"BRL","diagnostico":{"entidade":"Grupo Y"' } }] };
  const r = parseExtractionResponse(api);
  assert.deepEqual(r.campos, []);
  assert.match(r.falhaMotivo, /truncada/i);
  assert.match(r.falhaMotivo, /finish_reason=length/);
});

test('parseExtractionResponse: erro da API OpenAI vira falhaMotivo com a mensagem original', () => {
  const api = { error: { message: 'You exceeded your current quota', code: 'insufficient_quota' } };
  const r = parseExtractionResponse(api);
  assert.deepEqual(r.campos, []);
  assert.match(r.falhaMotivo, /You exceeded your current quota/);
});

test('parseExtractionResponse: sem conteúdo (falha de rede/API) vira falhaMotivo, não só diagnóstico genérico', () => {
  const r = parseExtractionResponse({});
  assert.deepEqual(r.campos, []);
  assert.ok(r.falhaMotivo, 'deve haver um motivo textual, não silêncio');
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
