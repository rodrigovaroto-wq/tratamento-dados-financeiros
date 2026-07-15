import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
  buildClassificationRequest,
  parseClassificationResponse,
  classificationSchema,
  codigosConhecidos,
} from '../lib/openai.mjs';

test('schema é estrito e cobre o Kit Básico + escape', () => {
  const s = classificationSchema();
  assert.equal(s.strict, true);
  assert.equal(s.schema.additionalProperties, false);
  const enumTipos = s.schema.properties.tipo_taxonomia.enum;
  assert.ok(enumTipos.includes('DRE'));
  assert.ok(enumTipos.includes('DESCONHECIDO'));
});

test('codigosConhecidos não tem duplicatas', () => {
  const c = codigosConhecidos();
  assert.equal(new Set(c).size, c.length);
});

test('buildClassificationRequest monta corpo com json_schema e conteúdo', () => {
  const req = buildClassificationRequest({
    nomeOriginal: 'doc.pdf',
    conteudo: { type: 'image_url', image_url: { url: 'data:image/png;base64,AAA' } },
    model: 'gpt-4o',
  });
  assert.equal(req.method, 'POST');
  assert.equal(req.body.response_format.type, 'json_schema');
  assert.equal(req.body.temperature, 0);
  // system + user
  assert.equal(req.body.messages.length, 2);
  const userContent = req.body.messages[1].content;
  assert.ok(userContent.some((p) => p.type === 'image_url'));
});

test('parseClassificationResponse normaliza para o formato do classificador', () => {
  const api = {
    choices: [
      {
        message: {
          content: JSON.stringify({
            tipo_taxonomia: 'DRE',
            entidade: 'Empresa A Ltda',
            periodo_tipo: 'anual',
            periodo_referencia: '12M25',
            assinado: true,
            confianca: 0.88,
            justificativa: 'Cabeçalho "Demonstração de Resultado" e ano 2025.',
          }),
        },
      },
    ],
  };
  const r = parseClassificationResponse(api);
  assert.equal(r.tipo_taxonomia, 'DRE');
  assert.equal(r.entidade, 'Empresa A Ltda');
  assert.deepEqual(r.periodo, { tipo: 'anual', referencia: '12M25' });
  assert.equal(r.assinado, true);
  assert.equal(r.confianca, 0.88);
  assert.equal(r.fonte, 'openai_conteudo');
});

test('DESCONHECIDO vira tipo null', () => {
  const api = {
    choices: [{ message: { content: JSON.stringify({
      tipo_taxonomia: 'DESCONHECIDO', entidade: null, periodo_tipo: 'desconhecido',
      periodo_referencia: null, assinado: null, confianca: 0.2, justificativa: 'ilegível',
    }) } }],
  };
  const r = parseClassificationResponse(api);
  assert.equal(r.tipo_taxonomia, null);
  assert.equal(r.periodo, null);
});

test('resposta sem content lança erro claro', () => {
  assert.throws(() => parseClassificationResponse({ choices: [] }), /sem content/);
});
