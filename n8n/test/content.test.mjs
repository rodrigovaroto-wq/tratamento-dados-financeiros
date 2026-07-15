import { test } from 'node:test';
import assert from 'node:assert/strict';
import { contentPartFromFile, isSpreadsheet, buildClassificationRequest } from '../lib/openai.mjs';

test('isSpreadsheet reconhece xlsx/xls/csv', () => {
  assert.equal(isSpreadsheet('application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'), true);
  assert.equal(isSpreadsheet('application/vnd.ms-excel'), true);
  assert.equal(isSpreadsheet('text/csv'), true);
  assert.equal(isSpreadsheet('application/pdf'), false);
});

test('contentPartFromFile — PDF vira file part com data URL', () => {
  const p = contentPartFromFile({ mimeType: 'application/pdf', base64: 'QUJD', filename: 'dre.pdf' });
  assert.equal(p.type, 'file');
  assert.equal(p.file.filename, 'dre.pdf');
  assert.match(p.file.file_data, /^data:application\/pdf;base64,QUJD$/);
});

test('contentPartFromFile — imagem vira image_url', () => {
  const p = contentPartFromFile({ mimeType: 'image/png', base64: 'QUJD' });
  assert.equal(p.type, 'image_url');
  assert.match(p.image_url.url, /^data:image\/png;base64,QUJD$/);
});

test('contentPartFromFile — texto extraído (planilha) vira text part e é truncado', () => {
  const p = contentPartFromFile({ mimeType: 'text/csv', text: 'a'.repeat(30000) });
  assert.equal(p.type, 'text');
  assert.equal(p.text.length, 20000);
});

test('contentPartFromFile — tipo não suportado não lança (fail-safe)', () => {
  const p = contentPartFromFile({ mimeType: 'application/zip', filename: 'x.zip' });
  assert.equal(p.type, 'text');
  assert.match(p.text, /requer extração prévia/);
});

test('buildClassificationRequest inclui a parte de conteúdo no user message', () => {
  const part = contentPartFromFile({ mimeType: 'application/pdf', base64: 'QUJD', filename: 'x.pdf' });
  const req = buildClassificationRequest({ nomeOriginal: 'x.pdf', conteudo: part });
  const userContent = req.body.messages[1].content;
  assert.ok(userContent.some((c) => c.type === 'file'));
});
