import { test } from 'node:test';
import assert from 'node:assert/strict';
import { computeCompletude } from '../lib/completude.mjs';
import { KIT_BASICO } from '../lib/taxonomia.mjs';

test('caso completo → Portão 1 ok, sem pendências', () => {
  const r = computeCompletude(KIT_BASICO);
  assert.equal(r.completo, true);
  assert.equal(r.portao1_ok, true);
  assert.equal(r.pendencias.length, 0);
});

test('faltando itens → pendências bloqueantes', () => {
  const presentes = ['DRE', 'BALANCO', 'FLUXO_CAIXA'];
  const r = computeCompletude(presentes);
  assert.equal(r.portao1_ok, false);
  // faltam 5 do Kit Básico
  assert.equal(r.faltantes.length, 5);
  assert.ok(r.pendencias.every((p) => p.severidade === 'bloqueante'));
  assert.ok(r.pendencias.every((p) => p.tipo === 'item_faltante'));
});

test('bloqueantes não-sobrepujáveis marcados corretamente', () => {
  const r = computeCompletude([]); // nada presente
  const porCodigo = Object.fromEntries(r.pendencias.map((p) => [p.alvo_tipo_taxonomia, p]));
  // Não-sobrepujáveis (f0/04): DRE, BALANCO, COMBINADO, MUTUOS, CONTRATO_SOCIAL
  assert.equal(porCodigo['DRE'].sobrepujavel, false);
  assert.equal(porCodigo['BALANCO'].sobrepujavel, false);
  assert.equal(porCodigo['COMBINADO'].sobrepujavel, false);
  assert.equal(porCodigo['MUTUOS'].sobrepujavel, false);
  assert.equal(porCodigo['CONTRATO_SOCIAL'].sobrepujavel, false);
  // Sobrepujáveis: FATURAMENTO_24M, FAT_INTRAGRUPO, FLUXO_CAIXA
  assert.equal(porCodigo['FATURAMENTO_24M'].sobrepujavel, true);
  assert.equal(porCodigo['FLUXO_CAIXA'].sobrepujavel, true);
});

test('duplicatas de presentes não quebram a contagem', () => {
  const r = computeCompletude(['DRE', 'DRE', 'BALANCO']);
  assert.equal(r.faltantes.includes('DRE'), false);
  assert.equal(r.faltantes.includes('BALANCO'), false);
});
