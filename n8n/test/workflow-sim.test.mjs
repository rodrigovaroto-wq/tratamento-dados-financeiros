// Simulação do workflow gerado: executa os códigos REAIS dos nós Code de
// workflow.e1-ingestao.json com dados mock, reproduzindo como o N8N passa
// dados entre nós (incluindo: Postgres não repassa binário; HTTP Request
// substitui o item pela resposta; $('Node').item volta o contexto).
//
// Se este teste passa, os nós Code estão coerentes entre si de ponta a ponta.

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const wf = JSON.parse(readFileSync(new URL('../workflow.e1-ingestao.json', import.meta.url)));
const byName = Object.fromEntries(wf.nodes.map((n) => [n.name, n]));
const code = (name) => byName[name].parameters.jsCode;

// Executa um jsCode como o N8N: $input, $ (referência a nós), $env, $json.
function run(name, { item, items, refs = {}, env = {} }) {
  const $input = {
    item,
    first: () => (items ? items[0] : item),
    all: () => items || (item ? [item] : []),
  };
  const $ = (ref) => {
    if (!(ref in refs)) throw new Error(`Referência não mockada no teste: $('${ref}') — o node "${name}" depende dela`);
    return { first: () => refs[ref], item: refs[ref] };
  };
  const $json = item ? item.json : undefined;
  const fn = new Function('$input', '$', '$env', '$json', 'Buffer', code(name));
  return fn($input, $, env, $json, Buffer);
}

// ---------------------------------------------------------------------------
// Dados mock: o Form entrega binários; o Postgres do Upsert só entrega caso_id.
// Nome com espaço+acento de propósito (caso real: "BALANÇO ACUMULADO 2025.pdf").
// ---------------------------------------------------------------------------
const FORM_ITEM = {
  json: { 'Mandato (nome do caso)': 'Mandato Teste' },
  binary: {
    Arquivos_0: { fileName: 'BALANÇO ACUMULADO 2025.pdf', mimeType: 'application/pdf', data: 'QUJD' },
    Arquivos_1: { fileName: '12M25 DRE (Assinado).pdf', mimeType: 'application/pdf', data: 'REVG' },
  },
};
const UPSERT_ITEM = { json: { caso_id: 'caso-uuid-1' } }; // sem binário (Postgres não repassa)
const REFS_BASE = { 'Intake (Form)': FORM_ITEM, 'Upsert Caso (Postgres)': UPSERT_ITEM };

test('Listar Arquivos: fan-out lê binário do FORM (não do Postgres) e normaliza a chave', () => {
  const out = run('Listar Arquivos', { item: UPSERT_ITEM, items: [UPSERT_ITEM], refs: REFS_BASE });
  assert.ok(Array.isArray(out), 'all-items deve retornar array');
  assert.equal(out.length, 2);
  for (const it of out) {
    assert.equal(it.json.caso_id, 'caso-uuid-1');
    assert.equal(it.json.binary_key, 'data');
    assert.ok(it.binary.data, 'binário deve estar sob a chave normalizada "data"');
  }
  assert.equal(out[0].json.nome_original, 'BALANÇO ACUMULADO 2025.pdf');
});

test('Listar Arquivos: sem arquivos → erro explícito (não saída vazia silenciosa)', () => {
  const semArquivos = { ...UPSERT_ITEM };
  assert.throws(
    () => run('Listar Arquivos', {
      item: semArquivos, items: [semArquivos],
      refs: { ...REFS_BASE, 'Intake (Form)': { json: {}, binary: {} } },
    }),
    /Nenhum arquivo recebido/
  );
});

// Encadeia os dois arquivos pela cadeia principal e guarda os intermediários.
function chainFile(idx) {
  const listado = run('Listar Arquivos', { item: UPSERT_ITEM, items: [UPSERT_ITEM], refs: REFS_BASE })[idx];
  const classificado = run('Classificar Nome', { item: listado, refs: REFS_BASE });
  const preparado = run('Preparar Conteudo', { item: classificado, refs: REFS_BASE });
  return { listado, classificado, preparado };
}

test('Classificar Nome: objeto único, classifica o caso real e PRESERVA o binário', () => {
  const { classificado } = chainFile(0); // BALANÇO ACUMULADO 2025.pdf
  assert.ok(!Array.isArray(classificado), 'each-item deve retornar objeto único');
  assert.equal(classificado.json.tipo_taxonomia, 'BALANCO');
  assert.equal(classificado.json.precisa_fallback_openai, true, 'sem período no nome → confiança 0.6 → fallback');
  assert.ok(classificado.binary?.data, 'binário preservado para os nós seguintes');

  const { classificado: dre } = chainFile(1); // 12M25 DRE (Assinado).pdf
  assert.equal(dre.json.tipo_taxonomia, 'DRE');
  assert.equal(dre.json.periodo_ref, '12M25');
  assert.equal(dre.json.assinado, true);
  assert.equal(dre.json.precisa_fallback_openai, false, 'nome completo → alta confiança → direto');
});

test('Preparar Conteudo: monta file part do PDF e preserva o binário p/ Upload', () => {
  const { preparado } = chainFile(0);
  assert.ok(!Array.isArray(preparado));
  assert.equal(preparado.json.content_part.type, 'file');
  assert.match(preparado.json.content_part.file.file_data, /^data:application\/pdf;base64,QUJD$/);
  assert.equal(preparado.json.caso_id, 'caso-uuid-1', 'contexto (caso_id) atravessa a cadeia');
  assert.ok(preparado.binary?.data, 'binário preservado (Upload é ramo a partir daqui)');
});

test('Upload Storage: URL usa encodeURIComponent (nomes com espaço/acento)', () => {
  assert.match(byName['Upload Storage'].parameters.url, /encodeURIComponent\(\$json\.nome_original\)/);
  assert.equal(byName['Upload Storage'].parameters.inputDataFieldName, 'data');
  // Gateway do Supabase exige o header 'apikey' além do Authorization (credencial) — sem ele, 400.
  const headers = byName['Upload Storage'].parameters.headerParameters.parameters;
  assert.ok(headers.some((h) => h.name === 'apikey'), 'falta o header apikey exigido pelo Supabase');
});

test('Ramo fallback: Montar Req → (HTTP substitui item) → Parse recompõe pelo contexto', () => {
  const { preparado } = chainFile(0);
  const req = run('Montar Req Classif', { item: preparado, refs: REFS_BASE, env: {} });
  assert.equal(req.json.openai_body.model, 'gpt-4o');
  assert.ok(req.json.openai_body.messages[1].content.some((c) => c.type === 'file'), 'conteúdo do arquivo vai na chamada');

  // O N8N substitui o item pela resposta da OpenAI:
  const respostaOpenAI = { json: { choices: [{ message: { content: JSON.stringify({
    tipo_taxonomia: 'BALANCO', entidade: 'Empresa X Ltda', periodo_tipo: 'anual',
    periodo_referencia: '12M25', assinado: true, confianca: 0.91, justificativa: 'cabeçalho',
  }) } }] } };
  const parsed = run('Parse OpenAI Classif', { item: respostaOpenAI, refs: { 'Montar Req Classif': req } });
  assert.ok(!Array.isArray(parsed));
  assert.equal(parsed.json.tipo_taxonomia, 'BALANCO');
  assert.equal(parsed.json.entidade, 'Empresa X Ltda');
  assert.equal(parsed.json.confianca, 0.91);
  assert.equal(parsed.json.caso_id, 'caso-uuid-1', 'contexto recomposto');
  assert.equal(parsed.json.openai_body, undefined, 'campos pesados removidos');
  assert.equal(parsed.json.content_part, undefined, 'campos pesados removidos');
});

test('Ramo fallback: falha da OpenAI (onError continue) → confiança 0, sem quebrar', () => {
  const { preparado } = chainFile(0);
  const req = run('Montar Req Classif', { item: preparado, refs: REFS_BASE, env: {} });
  const erro = { json: { error: 'timeout' } }; // resposta de erro qualquer
  const parsed = run('Parse OpenAI Classif', { item: erro, refs: { 'Montar Req Classif': req } });
  assert.equal(parsed.json.confianca, 0, 'vira pendência de classificação (fail-safe)');
  assert.equal(byName['OpenAI Classificar'].onError, 'continueRegularOutput');
  assert.equal(byName['OpenAI Extrair'].onError, 'continueRegularOutput');
});

test('Ramo E2: Registrar → Montar Req Extracao → Parse → payload p/ Gravar Campos', () => {
  const { preparado } = chainFile(1);
  // Saída do Registrar Documento (Postgres): linha {r: {ids}}
  const registrado = { json: { r: { documento_id: 'doc-1', documento_versao_id: 'ver-1' } } };
  const req = run('Montar Req Extracao', { item: registrado, refs: { 'Preparar Conteudo': preparado }, env: {} });
  assert.equal(req.json.documento_versao_id, 'ver-1');
  assert.equal(req.json.tipo, 'DRE');
  assert.ok(req.json.openai_body.messages[1].content.some((c) => c.type === 'file'));

  const respostaOpenAI = { json: { choices: [{ message: { content: JSON.stringify({
    moeda: 'BRL', unidade: 'R$ mil',
    linhas: [
      { chave: 'Receita líquida', valor_texto: '10.000', valor_num: 10000, origem_pagina: 1, confianca: 0.8 },
      { chave: 'EBITDA', valor_texto: '2.500', valor_num: 2500, origem_pagina: 2, confianca: 0.7 },
    ],
  }) } }] } };
  const parsed = run('Parse Extracao', { item: respostaOpenAI, refs: { 'Montar Req Extracao': req } });
  assert.equal(parsed.json.documento_versao_id, 'ver-1');
  assert.equal(parsed.json.campos.length, 2);
  assert.equal(parsed.json.campos[0].unidade, 'R$ mil', 'unidade do documento herdada por linha');
});

test('Topologia: Upload é ramo lateral; nada consome a saída dele', () => {
  const destinosDePreparar = wf.connections['Preparar Conteudo'].main[0].map((c) => c.node);
  assert.deepEqual(destinosDePreparar.sort(), ['Precisa Fallback?', 'Upload Storage'].sort());
  assert.equal(wf.connections['Upload Storage'], undefined, 'Upload não alimenta nenhum node');
  const destinosDeRegistrar = wf.connections['Registrar Documento'].main[0].map((c) => c.node);
  assert.deepEqual(destinosDeRegistrar.sort(), ['Montar Req Extracao', 'Recomputar Completude'].sort());
});

test('Modos e referências: cada node Code no modo certo; toda $(ref) existe no canvas', () => {
  const nomes = wf.nodes.map((n) => n.name);
  for (const n of wf.nodes) {
    if (n.type !== 'n8n-nodes-base.code') continue;
    if (n.name === 'Listar Arquivos') {
      assert.equal(n.parameters.mode, 'runOnceForAllItems', `${n.name} faz fan-out`);
    } else {
      assert.equal(n.parameters.mode, 'runOnceForEachItem', `${n.name} é transformação 1:1`);
    }
    // toda referência $('X') aponta para um node que existe (pega renomeações)
    for (const m of n.parameters.jsCode.matchAll(/\$\('([^']+)'\)/g)) {
      assert.ok(nomes.includes(m[1]), `node "${n.name}" referencia "${m[1]}" que não existe no workflow`);
    }
  }
});
