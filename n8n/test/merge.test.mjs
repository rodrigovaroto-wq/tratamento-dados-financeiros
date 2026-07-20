import { test } from 'node:test';
import assert from 'node:assert/strict';
import { mergeClassification } from '../lib/merge.mjs';

test('IA menos confiante que o nome: mantém o tipo do nome, mas guarda a justificativa da IA', () => {
  const fromName = { tipo_taxonomia: 'BALANCO', periodo_tipo: null, periodo_ref: null, assinado: null, entidade: null, confianca: 0.6 };
  const fromAI = { tipo_taxonomia: null, periodo_tipo: 'anual', periodo_ref: '2025', assinado: null, entidade: null, confianca: 0.5, justificativa: 'Documento não traz cabeçalho claro de Balanço Patrimonial.' };
  const r = mergeClassification(fromName, fromAI);
  assert.equal(r.tipo_taxonomia, 'BALANCO');
  assert.equal(r.confianca, 0.6, 'fica com a maior confiança das duas fontes');
  assert.equal(r.fonte, 'nome_arquivo');
  assert.equal(r.periodo_ref, '2025', 'período: usa o que a IA achou, já que o nome não tinha');
  assert.match(r.justificativa, /não traz cabeçalho/);
});

test('IA mais confiante que o nome: usa o resultado da IA', () => {
  const fromName = { tipo_taxonomia: 'BALANCO', periodo_tipo: null, periodo_ref: null, assinado: null, entidade: null, confianca: 0.6 };
  const fromAI = { tipo_taxonomia: 'DRE', periodo_tipo: 'anual', periodo_ref: '12M25', assinado: true, entidade: 'Empresa X Ltda', confianca: 0.9, justificativa: 'Cabeçalho "Demonstração de Resultado".' };
  const r = mergeClassification(fromName, fromAI);
  assert.equal(r.tipo_taxonomia, 'DRE');
  assert.equal(r.confianca, 0.9);
  assert.equal(r.fonte, 'openai_conteudo');
  assert.equal(r.entidade, 'Empresa X Ltda');
});

test('nome não achou tipo, IA achou: usa a IA mesmo com confiança moderada', () => {
  const fromName = { tipo_taxonomia: null, periodo_tipo: null, periodo_ref: null, assinado: null, entidade: null, confianca: 0 };
  const fromAI = { tipo_taxonomia: 'FLUXO_CAIXA', periodo_tipo: 'anual', periodo_ref: '12M25', assinado: null, entidade: null, confianca: 0.55, justificativa: 'Tabela com entradas/saídas de caixa mensais.' };
  const r = mergeClassification(fromName, fromAI);
  assert.equal(r.tipo_taxonomia, 'FLUXO_CAIXA');
  assert.equal(r.fonte, 'openai_conteudo');
});

test('nenhuma fonte achou tipo: resultado fica null, mas confiança/justificativa da IA são preservadas', () => {
  const fromName = { tipo_taxonomia: null, periodo_tipo: null, periodo_ref: null, assinado: null, entidade: null, confianca: 0 };
  const fromAI = { tipo_taxonomia: null, periodo_tipo: null, periodo_ref: null, assinado: null, entidade: null, confianca: 0.2, justificativa: 'Documento ilegível — scan de baixa qualidade.' };
  const r = mergeClassification(fromName, fromAI);
  assert.equal(r.tipo_taxonomia, null);
  assert.equal(r.confianca, 0.2);
  assert.match(r.justificativa, /ilegível/);
});

test('entidade e assinado: IA preenche o que o nome nunca souber', () => {
  const fromName = { tipo_taxonomia: 'DRE', periodo_tipo: 'anual', periodo_ref: '12M25', assinado: true, entidade: null, confianca: 0.9 };
  const fromAI = { tipo_taxonomia: null, periodo_tipo: null, periodo_ref: null, assinado: null, entidade: 'Empresa Y S.A.', confianca: 0.4, justificativa: '' };
  const r = mergeClassification(fromName, fromAI);
  // nome venceu (0.9 > 0.4) mas entidade da IA é aproveitada mesmo assim
  assert.equal(r.tipo_taxonomia, 'DRE');
  assert.equal(r.entidade, 'Empresa Y S.A.');
  assert.equal(r.assinado, true);
});
