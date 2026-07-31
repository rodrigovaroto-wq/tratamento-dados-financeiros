// SHA-256 em JS puro × o SHA-256 de verdade (node:crypto).
//
// A implementação existe porque o Code node do n8n não expõe `crypto` (medido
// na produção do dono, 2026-07-31). Reimplementar primitiva criptográfica é
// coisa que só se faz com o original ao lado provando byte a byte — é o que
// este arquivo é.

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { sha256Hex } from '../lib/hash.mjs';

const referencia = (b) => createHash('sha256').update(b).digest('hex');

test('bate com node:crypto nas fronteiras de bloco do padding', () => {
  // 55/56 e 63/64/65 são onde erro de padding se esconde: em 56 o comprimento
  // não cabe mais no bloco e um bloco EXTRA passa a ser exigido. Uma
  // implementação errada aqui acerta os casos curtos e falha nestes.
  for (const n of [0, 1, 55, 56, 63, 64, 65, 119, 120, 1000]) {
    const b = Buffer.alloc(n);
    for (let i = 0; i < n; i++) b[i] = (i * 31 + 7) & 0xff;
    assert.equal(sha256Hex(b), referencia(b), `comprimento ${n}`);
  }
});

test('bate com node:crypto em conteúdo real de PDF e em bytes altos', () => {
  const pdf = Buffer.from('%PDF-1.4\n1 0 obj\n<< /Type /Catalog >>\nendobj\ntrailer\n%%EOF\n');
  assert.equal(sha256Hex(pdf), referencia(pdf));

  // Bytes >= 0x80 pegam implementação que trate byte como signed em algum ponto.
  const altos = Buffer.from(Array.from({ length: 300 }, (_, i) => 0x80 + (i % 0x80)));
  assert.equal(sha256Hex(altos), referencia(altos));

  // Acentuação em UTF-8 (nomes de arquivo e demonstrações brasileiras são cheios).
  const texto = Buffer.from('Balanço Patrimonial — Vertentes Metalúrgica Ltda.', 'utf-8');
  assert.equal(sha256Hex(texto), referencia(texto));
});

test('vetor conhecido da FIPS 180-4 ("abc")', () => {
  // Vetor publicado, independente do node:crypto: se os dois estivessem errados
  // juntos (a falha que o teste de comparação não pega), este assert acusa.
  assert.equal(
    sha256Hex(Buffer.from('abc')),
    'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad',
  );
});

test('discrimina conteúdo: um byte trocado muda o hash', () => {
  const a = Buffer.from('conteudo do documento');
  const b = Buffer.from('conteudo do documentl');
  assert.notEqual(sha256Hex(a), sha256Hex(b));
});

test('aceita Uint8Array e ArrayBuffer, não só Buffer', () => {
  // O `buf` do nó é Buffer, mas a função é embutida por toString() num sandbox
  // onde Buffer pode não existir — precisa funcionar com Uint8Array puro.
  const bytes = new Uint8Array([1, 2, 3, 250, 251]);
  const esperado = referencia(Buffer.from(bytes));
  assert.equal(sha256Hex(bytes), esperado);
  assert.equal(sha256Hex(bytes.buffer), esperado);
});
