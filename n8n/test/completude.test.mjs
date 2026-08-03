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

// --- Item 3 do §7.4 do Onboarding: chegou vazio não cumpre item -------------
// A v1 tinha dois estados, e "presente" queria dizer só "existe documento com
// esse código". Um .xlsx não convertido, um arquivo ilegível ou uma chamada que
// falhou davam item verde com zero linha no banco — dashboard pronto e book
// vazio. O terceiro estado usa o vocabulário de docs/07 (`recebido_não_válido`)
// e trava o Portão 2 pela pendência, sem redefinir o Portão 1.

test('obrigatório que chegou sem NENHUMA linha não conta como cumprido', () => {
  const r = computeCompletude(KIT_BASICO, { semConteudo: ['BALANCO'] });
  // Chegada continua completa: o arquivo está lá, e pedir de novo ao cliente
  // seria pedir o que ele já mandou.
  assert.equal(r.portao1_ok, true, 'Portão 1 é CHEGADA — não muda de significado');
  assert.deepEqual(r.faltantes, [], 'não é faltante: o documento existe');
  // Mas o caso não está pronto para revisão.
  assert.deepEqual(r.semConteudo, ['BALANCO']);
  assert.equal(r.pronto_para_revisao, false, 'chegou tudo, mas falta conteúdo');
});

test('…e a pendência é BLOQUEANTE e não-sobrepujável, sempre', () => {
  // docs/07 põe "arquivo ilegível de item essencial" na lista fechada que
  // nenhuma ressalva libera. Não há o que ressalvar num obrigatório do qual não
  // veio um único número — nem para os códigos que são sobrepujáveis quando
  // FALTAM (ex.: FATURAMENTO_24M).
  const r = computeCompletude(KIT_BASICO, { semConteudo: ['FATURAMENTO_24M'] });
  const p = r.pendencias.find((x) => x.tipo === 'item_sem_conteudo');
  assert.ok(p, 'tem de existir pendência de item sem conteúdo');
  assert.equal(p.severidade, 'bloqueante');
  assert.equal(p.sobrepujavel, false, 'não-sobrepujável mesmo sendo sobrepujável quando falta');
  assert.equal(p.alvo_tipo_taxonomia, 'FATURAMENTO_24M');
  assert.match(p.descricao, /book sai VAZIO/);
});

test('faltante e sem-conteúdo coexistem, cada um com sua pendência', () => {
  // O caso real de um mandato em andamento: alguns itens ainda não chegaram, e um
  // dos que chegaram veio ilegível. São dois problemas diferentes, com ações
  // diferentes (pedir ao cliente vs. reenviar/converter).
  const presentes = KIT_BASICO.filter((c) => c !== 'MUTUOS');
  const r = computeCompletude(presentes, { semConteudo: ['BALANCO'] });
  assert.deepEqual(r.faltantes, ['MUTUOS']);
  assert.deepEqual(r.semConteudo, ['BALANCO']);
  assert.equal(r.portao1_ok, false);
  assert.equal(r.pronto_para_revisao, false);
  const tipos = r.pendencias.map((p) => p.tipo).sort();
  assert.deepEqual(tipos, ['item_faltante', 'item_sem_conteudo']);
});

test('caso íntegro segue sem pendência nenhuma (nada de alarme falso)', () => {
  const r = computeCompletude(KIT_BASICO, { semConteudo: [] });
  assert.equal(r.pronto_para_revisao, true);
  assert.deepEqual(r.pendencias, []);
});

test('código em semConteudo que nem chegou é ignorado (o caso é faltante)', () => {
  // Incoerência do chamador não deve virar pendência sobre documento inexistente
  // — senão o mesmo item apareceria como faltante E como recebido-vazio.
  const r = computeCompletude([], { semConteudo: ['DRE'] });
  assert.deepEqual(r.semConteudo, []);
  assert.equal(r.pendencias.filter((p) => p.tipo === 'item_sem_conteudo').length, 0);
  assert.ok(r.faltantes.includes('DRE'), 'DRE é faltante, que é a leitura correta');
});
