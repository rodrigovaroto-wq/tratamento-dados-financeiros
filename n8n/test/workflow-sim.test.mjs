// Simulação do workflow gerado: executa os códigos REAIS dos nós Code de
// workflow.e1-ingestao.json com dados mock, reproduzindo como o N8N passa
// dados entre nós (incluindo: Postgres não repassa binário; HTTP Request
// substitui o item pela resposta; $('Node').item volta o contexto; binário
// só é lido via this.helpers.getBinaryDataBuffer, nunca direto do campo .data).
//
// Se este teste passa, os nós Code estão coerentes entre si de ponta a ponta.

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { codigosConhecidos } from '../lib/openai.mjs';
import { SYSTEM_PROMPT, diagnosticarErroApi, MAX_OUTPUT_TOKENS, TPM_CONTA } from '../lib/extract.mjs';
import { ALIASES } from '../lib/taxonomia.mjs';
import { parseEntidade, classifyByFilename } from '../lib/classifier.mjs';
import { orcamentoDoLote } from '../lib/custo.mjs';

const wf = JSON.parse(readFileSync(new URL('../workflow.e1-ingestao.json', import.meta.url)));
const byName = Object.fromEntries(wf.nodes.map((n) => [n.name, n]));
const code = (name) => byName[name].parameters.jsCode;
const AsyncFunction = Object.getPrototypeOf(async function () {}).constructor;

// Executa um jsCode como o N8N: $input, $ (referência a nós), $env, $json,
// $itemIndex e this.helpers (binário — NÃO o global $helpers: no runtime de
// Task Runner do N8N (padrão em instalações self-hosted recentes), $helpers
// não existe; o jeito certo é this.helpers.getBinaryDataBuffer, confirmado
// testando ao vivo e na doc oficial do n8n). O código real usa `await`,
// então o mock roda como função async, com `this` vinculado via .call().
//
// getBinaryDataBuffer resolve o buffer pelo `itemIndex` DENTRO DO LOTE
// inteiro do node — não pelo `item` específico passado nesta chamada de
// `run()`. Por isso o mock busca em `binaryStore` (o lote completo, quando
// fornecido) usando o itemIndex recebido pelo CÓDIGO (não um valor fixo do
// teste) — é o que teria pego o bug real (2026-07-22): getBinaryDataBuffer(0,
// ...) sempre lia o item 0 do lote, mesmo processando o item 1. Sem
// binaryStore, cai pro item único (`item`) — comportamento de antes, para
// nodes que não dependem de itemIndex.
async function run(name, { item, items, refs = {}, env = {}, itemIndex = 0, binaryStore } = {}) {
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
  const thisContext = {
    helpers: {
      getBinaryDataBuffer: async (idx, propertyName) => {
        const lote = binaryStore || (item ? [item] : []);
        const fonte = lote[idx];
        const bin = (fonte && fonte.binary && fonte.binary[propertyName]) || {};
        return Buffer.from(bin.data || '', 'base64');
      },
    },
  };
  const fn = new AsyncFunction('$input', '$', '$env', '$json', '$itemIndex', 'Buffer', code(name));
  return fn.call(thisContext, $input, $, env, $json, itemIndex, Buffer);
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

test('Listar Arquivos: fan-out lê binário do FORM (não do Postgres) e normaliza a chave', async () => {
  const out = await run('Listar Arquivos', { item: UPSERT_ITEM, items: [UPSERT_ITEM], refs: REFS_BASE });
  assert.ok(Array.isArray(out), 'all-items deve retornar array');
  assert.equal(out.length, 2);
  for (const it of out) {
    assert.equal(it.json.caso_id, 'caso-uuid-1');
    assert.equal(it.json.binary_key, 'data');
    assert.ok(it.binary.data, 'binário deve estar sob a chave normalizada "data"');
  }
  assert.equal(out[0].json.nome_original, 'BALANÇO ACUMULADO 2025.pdf');
});

test('Listar Arquivos: sem arquivos → erro explícito (não saída vazia silenciosa)', async () => {
  const semArquivos = { ...UPSERT_ITEM };
  await assert.rejects(
    () => run('Listar Arquivos', {
      item: semArquivos, items: [semArquivos],
      refs: { ...REFS_BASE, 'Intake (Form)': { json: {}, binary: {} } },
    }),
    /Nenhum arquivo recebido/
  );
});

// Encadeia os dois arquivos pela cadeia principal e guarda os intermediários.
// `lote` guarda os DOIS itens fan-out (mesmo processando só um pelo resto da
// cadeia) — é o que permite `Preparar Conteudo` simular getBinaryDataBuffer
// resolvendo pelo itemIndex dentro do lote inteiro, não só pelo item único.
async function chainFile(idx) {
  const lote = await run('Listar Arquivos', { item: UPSERT_ITEM, items: [UPSERT_ITEM], refs: REFS_BASE });
  const listado = lote[idx];
  const classificado = await run('Classificar Nome', { item: listado, refs: REFS_BASE, itemIndex: idx, binaryStore: lote });
  const preparado = await run('Preparar Conteudo', { item: classificado, refs: REFS_BASE, itemIndex: idx, binaryStore: lote });
  return { listado, classificado, preparado };
}

test('Classificar Nome: objeto único, classifica o caso real e PRESERVA o binário', async () => {
  const { classificado } = await chainFile(0); // BALANÇO ACUMULADO 2025.pdf
  assert.ok(!Array.isArray(classificado), 'each-item deve retornar objeto único');
  assert.equal(classificado.json.tipo_taxonomia, 'BALANCO');
  assert.equal(classificado.json.precisa_fallback_openai, true, 'sem período no nome → confiança 0.6 → fallback');
  assert.ok(classificado.binary?.data, 'binário preservado para os nós seguintes');

  const { classificado: dre } = await chainFile(1); // 12M25 DRE (Assinado).pdf
  assert.equal(dre.json.tipo_taxonomia, 'DRE');
  assert.equal(dre.json.periodo_ref, '12M25');
  assert.equal(dre.json.assinado, true);
  assert.equal(dre.json.precisa_fallback_openai, false, 'nome completo → alta confiança → direto');
});

test('Preparar Conteudo: lê o binário via $helpers.getBinaryDataBuffer (não do campo .data direto)', async () => {
  // Bug real (2026-07-20): ler binary.data.data direto funciona só por acaso
  // no modo de binário em memória do N8N; no modo filesystem/S3 esse campo
  // vira uma referência interna (ex.: "filesystem-v2"), não a base64 — e a
  // OpenAI acaba recebendo um PDF inválido sem nenhum erro (achado quando a
  // IA só "leu" o nome do arquivo, porque o conteúdo enviado era lixo).
  const { preparado } = await chainFile(0);
  assert.ok(!Array.isArray(preparado));
  assert.equal(preparado.json.content_part.type, 'file');
  assert.match(preparado.json.content_part.file.file_data, /^data:application\/pdf;base64,QUJD$/);
  assert.equal(preparado.json.caso_id, 'caso-uuid-1', 'contexto (caso_id) atravessa a cadeia');
  assert.ok(preparado.binary?.data, 'binário preservado (Upload é ramo a partir daqui)');
});

test('Preparar Conteudo: com 2+ arquivos no MESMO lote, cada item lê o SEU PRÓPRIO binário', async () => {
  // Bug real (2026-07-22, achado testando com 2 documentos reais no mesmo
  // upload): getBinaryDataBuffer(0, 'data') fixo lia sempre o binário do
  // ITEM 0 do lote, mesmo processando o item 1 — o nome/mimeType do item 1
  // batiam (vêm do JSON, correto), mas os BYTES enviados pra IA eram os do
  // item 0. Com upload de 1 arquivo por vez isso nunca aparecia (o único
  // item É o item 0). Resultado real: um documento foi extraído com o
  // CONTEÚDO de outro (diagnóstico/entidade/valores de um arquivo diferente
  // do que o nome dizia). Fix: usar $itemIndex em vez do literal 0.
  const { preparado: item0 } = await chainFile(0); // BALANÇO ACUMULADO 2025.pdf (base64 "QUJD")
  const { preparado: item1 } = await chainFile(1); // 12M25 DRE (Assinado).pdf (base64 "REVG")
  assert.match(item0.json.content_part.file.file_data, /base64,QUJD$/, 'item 0 deve ler o PRÓPRIO binário');
  assert.match(item1.json.content_part.file.file_data, /base64,REVG$/, 'item 1 deve ler o PRÓPRIO binário, não o do item 0');
  assert.notEqual(item0.json.content_part.file.file_data, item1.json.content_part.file.file_data);
});

test('Upload Storage: URL usa encodeURIComponent (nomes com espaço/acento)', () => {
  assert.match(byName['Upload Storage'].parameters.url, /encodeURIComponent\(\$json\.nome_original\)/);
  assert.equal(byName['Upload Storage'].parameters.inputDataFieldName, 'data');
  // Gateway do Supabase exige o header 'apikey' além do Authorization (credencial) — sem ele, 400.
  const headers = byName['Upload Storage'].parameters.headerParameters.parameters;
  assert.ok(headers.some((h) => h.name === 'apikey'), 'falta o header apikey exigido pelo Supabase');
});

test('Upload Storage: desabilitado (bug de plataforma do HTTP Request + binário)', () => {
  // n8n-io/n8n#3089, #10096: o node HTTP Request trava o editor com
  // "Converting circular structure to JSON" ao lidar com dados binários em
  // certas configs. Confirmado reproduzível no N8N real (não é bug nosso).
  // Fica desabilitado até adotar uma alternativa (ver README).
  assert.equal(byName['Upload Storage'].disabled, true, 'Upload Storage deve seguir desabilitado até resolver o bug de plataforma');
});

test('Ramo fallback: Montar Req → (HTTP substitui item) → Parse recompõe pelo contexto', async () => {
  const { preparado } = await chainFile(0);
  const req = await run('Montar Req Classif', { item: preparado, refs: REFS_BASE, env: {} });
  assert.equal(req.json.openai_body.model, 'gpt-4o');
  assert.ok(req.json.openai_body.messages[1].content.some((c) => c.type === 'file'), 'conteúdo do arquivo vai na chamada');

  // O N8N substitui o item pela resposta da OpenAI:
  const respostaOpenAI = { json: { choices: [{ message: { content: JSON.stringify({
    tipo_taxonomia: 'BALANCO', entidade: 'Empresa X Ltda', periodo_tipo: 'anual',
    periodo_referencia: '12M25', assinado: true, confianca: 0.91, justificativa: 'cabeçalho',
  }) } }] } };
  const parsed = await run('Parse OpenAI Classif', { item: respostaOpenAI, refs: { 'Montar Req Classif': req } });
  assert.ok(!Array.isArray(parsed));
  assert.equal(parsed.json.tipo_taxonomia, 'BALANCO');
  assert.equal(parsed.json.entidade, 'Empresa X Ltda');
  assert.equal(parsed.json.confianca, 0.91);
  assert.equal(parsed.json.caso_id, 'caso-uuid-1', 'contexto recomposto');
  assert.equal(parsed.json.openai_body, undefined, 'campos pesados removidos');
  assert.equal(parsed.json.content_part, undefined, 'campos pesados removidos');
});

test('Montar Req Classif: schema da OpenAI TRAVA tipo_taxonomia/periodo_tipo num enum (caso real: virou "BAL" sem isso)', async () => {
  // Bug real (2026-07-20): o mirror manual do schema em build-workflow.mjs
  // não tinha `enum`, então a OpenAI inventou "BAL" como tipo_taxonomia (não
  // é um código válido) e "12M25" como periodo_tipo (é a REFERENCIA, não o
  // tipo). Sem enum, nada no request impedia isso — Structured Outputs só
  // restringe de fato quando o schema declara o enum explicitamente.
  const { preparado } = await chainFile(0);
  const req = await run('Montar Req Classif', { item: preparado, refs: REFS_BASE, env: {} });
  const schema = req.json.openai_body.response_format.json_schema.schema;
  const tipoEnum = schema.properties.tipo_taxonomia.enum;
  const periodoEnum = schema.properties.periodo_tipo.enum;
  assert.ok(Array.isArray(tipoEnum), 'tipo_taxonomia precisa de enum (senão a IA pode inventar código)');
  assert.deepEqual([...tipoEnum].sort(), [...codigosConhecidos()].sort(), 'enum deve ser exatamente os códigos conhecidos + DESCONHECIDO');
  assert.ok(tipoEnum.includes('BALANCO') && !tipoEnum.includes('BAL'), 'código correto é BALANCO, não uma abreviação inventada');
  assert.deepEqual(periodoEnum, ['anual', 'trimestre', 'multi', 'data-base', 'outro', 'desconhecido']);
});

test('Ramo fallback: falha da OpenAI (onError continue) → mantém o que o nome já sabia, sem quebrar', async () => {
  const { preparado } = await chainFile(0); // BALANÇO ACUMULADO 2025.pdf: nome já dava BALANCO @ 0.65
  const req = await run('Montar Req Classif', { item: preparado, refs: REFS_BASE, env: {} });
  const erro = { json: { error: 'timeout' } }; // resposta de erro qualquer (sem content)
  const parsed = await run('Parse OpenAI Classif', { item: erro, refs: { 'Montar Req Classif': req } });
  // Merge: falha técnica da IA não deve descartar um sinal que o nome já dava.
  assert.equal(parsed.json.tipo_taxonomia, 'BALANCO');
  assert.equal(parsed.json.confianca, 0.65, 'mantém a confiança do nome, não zera por falha técnica da IA');
  assert.equal(parsed.json.fonte, 'nome_arquivo');
  // A justificativa tem de dizer as DUAS coisas: que valeu o nome, e QUAL foi a
  // falha. No "teste v30" os 14 documentos ficaram com uma justificativa genérica
  // ("falha de rede/API") enquanto a causa real era a OpenAI recusando toda
  // chamada — o dono não tinha como ligar uma coisa à outra.
  assert.match(parsed.json.justificativa, /valeu o nome do arquivo/);
  assert.match(parsed.json.justificativa, /timeout/, 'a falha real aparece, não uma frase genérica');
  assert.equal(byName['OpenAI Classificar'].onError, 'continueRegularOutput');
  assert.equal(byName['OpenAI Extrair'].onError, 'continueRegularOutput');
});

test('Parse OpenAI Classif: 429 da OpenAI nomeia a CAUSA na justificativa do documento', async () => {
  // O sintoma real do v30: o n8n devolve a própria dica ("Try spacing your
  // requests out...") e nada mais. Antes isso virava "falha de rede/API"; agora
  // vira "limite atingido, e não sabemos qual — confira crédito", que é
  // acionável e não afirma cadência sem evidência.
  const { preparado } = await chainFile(0);
  const req = await run('Montar Req Classif', { item: preparado, refs: REFS_BASE, env: {} });
  const erro = { json: { error: { message: "Try spacing your requests out using the batching settings under 'Options'" } } };
  const parsed = await run('Parse OpenAI Classif', { item: erro, refs: { 'Montar Req Classif': req } });
  assert.match(parsed.json.justificativa, /LIMITE DA OPENAI ATINGIDO \(HTTP 429\)/);
  assert.match(parsed.json.justificativa, /crédito/i, 'diz que pode ser crédito — a causa que espaçar NÃO resolve');
  assert.equal(parsed.json.tipo_taxonomia, 'BALANCO', 'e o nome do arquivo continua valendo');
});

test('Ramo E2: Registrar → Montar Req Extracao → Parse → payload de diagnóstico+extração', async () => {
  const { preparado } = await chainFile(1);
  // Saída do Registrar Documento (Postgres): linha {r: {ids}}
  const registrado = { json: { r: { documento_id: 'doc-1', documento_versao_id: 'ver-1' } } };
  const req = await run('Montar Req Extracao', { item: registrado, refs: { 'Preparar Conteudo': preparado }, env: {} });
  assert.equal(req.json.documento_versao_id, 'ver-1');
  assert.equal(req.json.tipo, 'DRE');
  assert.ok(req.json.openai_body.messages[1].content.some((c) => c.type === 'file'));
  assert.equal(req.json.openai_body.response_format.json_schema.name, 'diagnostico_e_extracao');
  assert.ok(
    req.json.openai_body.response_format.json_schema.schema.properties.linhas.items.required.includes('pc'),
    'schema gerado pede pc/periodo_coluna por linha (db/migrations/0017)',
  );
  assert.equal(req.json.openai_body.max_tokens, 16384, 'teto de tokens de saída explícito (sessão 7 cont.⁷: sem isso, documentos combinados grandes truncavam a resposta silenciosamente)');
  assert.match(req.json.openai_body.messages[1].content[0].text, /12M25 DRE \(Assinado\)\.pdf/, 'nome do arquivo vai no prompt (base do diagnóstico de tipo/período)');

  const respostaOpenAI = { json: { choices: [{ message: { content: JSON.stringify({
    moeda: 'BRL', unidade: 'R$ mil',
    diagnostico: {
      entidade: 'Empresa Teste Ltda', tipo_confirma: false, tipo_sugerido: 'BALANCO',
      periodo_tipo: 'anual', periodo_referencia: '12M25',
      legibilidade: 'degradado', nota_legibilidade: 'Última página cortada.',
      resumo: 'Balanço patrimonial de 2025.', justificativa: 'Conteúdo é Balanço, não DRE (dica do nome estava errada).',
    },
    linhas: [
      { s: 'Ativo Circulante', sc: 'ativo_circulante', k: 'Caixa e equivalentes', vt: '10.000', vn: 10000, op: 1, cf: 0.8 },
      { s: 'Passivo Circulante', sc: 'NAO_CLASSIFICAVEL', k: 'Fornecedores', vt: '2.500', vn: 2500, op: 2, cf: 0.7 },
    ],
  }) } }] } };
  const parsed = await run('Parse Extracao', { item: respostaOpenAI, refs: { 'Montar Req Extracao': req } });
  assert.equal(parsed.json.documento_versao_id, 'ver-1');
  assert.equal(parsed.json.campos.length, 2);
  assert.equal(parsed.json.campos[0].secao, 'Ativo Circulante');
  assert.equal(parsed.json.campos[0].secao_canonica, 'ativo_circulante', 'secao_canonica mapeada no mirror do Code node');
  assert.equal(parsed.json.campos[1].secao_canonica, null, 'NAO_CLASSIFICAVEL vira null no mirror');
  assert.equal(parsed.json.campos[0].unidade, 'milhar', 'unidade herdada por linha E normalizada na escala canônica pelo Code node real');
  assert.equal(parsed.json.diagnostico.entidade, 'Empresa Teste Ltda');
  assert.equal(parsed.json.diagnostico.tipo_confirma, false);
  assert.equal(parsed.json.diagnostico.tipo_sugerido, 'BALANCO');
  assert.equal(parsed.json.diagnostico.legibilidade, 'degradado');
  assert.equal(parsed.json.falha_motivo, null, 'extração ok não gera motivo de falha');
  assert.ok('periodo_coluna' in parsed.json.campos[0], 'mirror do Code node propaga periodo_coluna (db/migrations/0017)');

  // Registrar Diagnostico lê $('Parse Extracao').item.json.diagnostico.* — a
  // mesma simulação do node real garante que o encadeamento produz os campos
  // que a query Postgres espera (sem rodar Postgres de verdade aqui).
  const diagNode = byName['Registrar Diagnostico'];
  const refsUsadas = [...diagNode.parameters.options.queryReplacement.matchAll(/\$\('Parse Extracao'\)\.item\.json\.diagnostico\.(\w+)/g)].map((m) => m[1]);
  for (const campo of refsUsadas) {
    assert.ok(campo in parsed.json.diagnostico, `Registrar Diagnostico espera diagnostico.${campo}, que Parse Extracao não produz`);
  }
});

test('Diagnóstico com resposta DESCONHECIDO/ilegível vira null (não "DESCONHECIDO" literal na pendência)', async () => {
  const req = { json: { documento_versao_id: 'ver-2', tipo: 'BALANCO', openai_body: {} } };
  const respostaOpenAI = { json: { choices: [{ message: { content: JSON.stringify({
    moeda: null, unidade: null,
    diagnostico: {
      entidade: null, tipo_confirma: false, tipo_sugerido: 'DESCONHECIDO',
      periodo_tipo: 'desconhecido', periodo_referencia: null,
      legibilidade: 'ilegivel', nota_legibilidade: 'Arquivo corrompido.',
      resumo: 'Não foi possível ler.', justificativa: 'Ilegível.',
    },
    linhas: [],
  }) } }] } };
  const parsed = await run('Parse Extracao', { item: respostaOpenAI, refs: { 'Montar Req Extracao': req } });
  assert.equal(parsed.json.diagnostico.tipo_sugerido, null);
  assert.equal(parsed.json.diagnostico.legibilidade, 'ilegivel');
});

test('Parse Extracao: resposta truncada (finish_reason=length, JSON incompleto) vira falha_motivo, não 0 campos silencioso', async () => {
  const req = { json: { documento_versao_id: 'ver-3', tipo: 'COMBINADO', openai_body: {} } };
  // JSON deliberadamente cortado no meio (simula o corte real de um output
  // que estourou o teto de tokens antes de fechar o array `linhas`).
  const respostaOpenAI = { json: { choices: [{ finish_reason: 'length', message: { content: '{"moeda":"BRL","unidade":null,"diagnostico":{"entidade":"Grupo X"' } }] } };
  const parsed = await run('Parse Extracao', { item: respostaOpenAI, refs: { 'Montar Req Extracao': req } });
  assert.equal(parsed.json.campos.length, 0);
  assert.match(parsed.json.falha_motivo, /truncada.*finish_reason=length/i);
});

test('Parse Extracao: erro da API OpenAI vira falha_motivo (não silencioso)', async () => {
  const req = { json: { documento_versao_id: 'ver-4', tipo: 'BALANCO', openai_body: {} } };
  const respostaOpenAI = { json: { error: { message: 'Rate limit reached', code: 'rate_limit_exceeded' } } };
  const parsed = await run('Parse Extracao', { item: respostaOpenAI, refs: { 'Montar Req Extracao': req } });
  assert.equal(parsed.json.campos.length, 0);
  assert.match(parsed.json.falha_motivo, /Rate limit reached/);
});

test('Gravar Campos (Sombra): passa falha_motivo para fn_registrar_campos_extraidos', () => {
  const node = byName['Gravar Campos (Sombra)'];
  assert.match(node.parameters.query, /p_falha_motivo\s*=>\s*\$3::text/);
  assert.match(node.parameters.options.queryReplacement, /\$json\.falha_motivo\s*\|\|\s*null/);
});

test('Nós OpenAI têm batching + retry (evita o 429 de rate limit num upload em lote)', () => {
  // Achado em produção (sessão 7 cont.⁸, "teste v15"): 16 documentos → 16
  // chamadas OpenAI quase simultâneas → 429 em TODAS ("Try spacing your
  // requests out"). Batching espaça no tempo; retry cobre o 429 residual.
  for (const nm of ['OpenAI Classificar', 'OpenAI Extrair']) {
    const n = byName[nm];
    assert.equal(n.parameters.options?.batching?.batch?.batchSize, 1, `${nm}: 1 chamada por vez`);
    assert.ok(n.parameters.options?.batching?.batch?.batchInterval >= 1000, `${nm}: intervalo entre chamadas`);
    assert.equal(n.retryOnFail, true, `${nm}: reexecuta antes de cair no onError`);
    assert.ok(n.maxTries >= 2, `${nm}: mais de uma tentativa`);
  }
});

test('Batching endurecido após "teste v18" (3 de 16 docs ainda deram 429 com 3s/4 tentativas)', () => {
  // Achado em produção (sessão 7 cont.¹¹): os 3 documentos que ainda deram 429
  // com o batching da cont.⁸ (3s, 4 tentativas) eram justamente os
  // consolidados comparativos multi-ano — mais tokens de entrada E saída que
  // os demais. 6s + 6 tentativas dão mais folga pro balde de TPM da conta.
  // O piso de 6s vale para as DUAS chamadas; a extração subiu para 12s depois do
  // v28 (teste próprio abaixo), então aqui a asserção é o PISO, não a igualdade —
  // travar 6000 exato reprovaria justamente o endurecimento seguinte.
  for (const nm of ['OpenAI Classificar', 'OpenAI Extrair']) {
    const n = byName[nm];
    assert.ok(n.parameters.options?.batching?.batch?.batchInterval >= 6000, `${nm}: intervalo endurecido`);
    assert.equal(n.maxTries, 6, `${nm}: mais tentativas`);
  }
});

test('Os dois nós OpenAI pedem o CORPO da resposta de erro (`neverError`)', () => {
  // Sem isto, o item que chega ao parse num 429 é só o AxiosError — foi
  // literalmente o que o dono colou depois do v30: `name: AxiosError`,
  // `code: ERR_BAD_REQUEST`, `status: 429`, `message` = a dica genérica que o
  // n8n escreve em cima de QUALQUER 429, e NENHUM corpo da OpenAI em lugar
  // nenhum do item. Sem corpo, `error.code` (o campo que a doc da OpenAI manda
  // inspecionar) não existe, e as causas que pedem ações OPOSTAS — crédito,
  // teto de gasto, cota diária, cadência — ficam indistinguíveis. Com
  // `neverError`, a resposta 429 vem como item normal E COM CORPO, e o
  // diagnóstico deixa de precisar adivinhar.
  for (const nm of ['OpenAI Classificar', 'OpenAI Extrair']) {
    const n = byName[nm];
    assert.equal(n.parameters.options?.response?.response?.neverError, true,
      `${nm}: sem neverError o corpo do erro da OpenAI é descartado antes do parse`);
  }
});

test('A cadência da extração é DERIVADA do TPM, não escolhida a olho', () => {
  // A rodada anterior subiu o intervalo de 6s para 12s por chute e o 429
  // continuou — erro meu, registrado aqui para não repetir. A OpenAI cobra do
  // balde de TPM o MÁXIMO entre `max_tokens` e os tokens estimados do request,
  // então cada extração RESERVA MAX_OUTPUT_TOKENS por chamada, independente do
  // tamanho do PDF. Isso torna o intervalo mínimo uma conta, não uma opinião:
  // TPM / max_tokens = chamadas por minuto.
  const intervalo = byName['OpenAI Extrair'].parameters.options.batching.batch.batchInterval;
  const chamadasPorMinuto = 60000 / intervalo;
  const tpmReservado = chamadasPorMinuto * MAX_OUTPUT_TOKENS;
  assert.ok(tpmReservado <= TPM_CONTA + 1,
    `a cadência reserva ${Math.round(tpmReservado)} TPM, acima do teto da conta (${TPM_CONTA}) — o 429 é matemático`);
  // E não pode ser lenta a ponto de não usar a conta: pelo menos metade do balde.
  assert.ok(tpmReservado >= TPM_CONTA / 2,
    `${Math.round(tpmReservado)} TPM desperdiça mais da metade do limite disponível (${TPM_CONTA})`);
});

test('Nós Postgres têm onError+retry — um erro num item não derruba o resto do lote em silêncio', () => {
  // Achado em produção (sessão 7 cont.¹³, "teste v19"): 9 arquivos pequenos
  // enviados, só 6 apareceram no dashboard — os outros 3 nunca chegaram a ter
  // uma linha `documento` criada. Sem onError, um erro transitório de conexão
  // num ÚNICO node Postgres (mais provável sob a carga do lote, com o rate
  // limit da OpenAI já no teto) PARA A EXECUÇÃO INTEIRA — todo item ainda na
  // fila some sem nenhum rastro. Com onError:continueRegularOutput +
  // retryOnFail, o pior caso vira "esse item específico fica incompleto"
  // (nunca vira fato, doutrina docs/01), não "o lote inteiro desaparece".
  const nomesPostgres = [
    'Upsert Caso (Postgres)', 'Registrar Documento', 'Recomputar Completude',
    'Gravar Campos (Sombra)', 'Registrar Diagnostico', 'Reconciliar (Classe A)',
  ];
  for (const nm of nomesPostgres) {
    const n = byName[nm];
    assert.equal(n.type, 'n8n-nodes-base.postgres', `${nm}: é um node Postgres de verdade (checagem do teste)`);
    assert.equal(n.onError, 'continueRegularOutput', `${nm}: onError ausente — um erro aqui derruba todo o lote`);
    assert.equal(n.retryOnFail, true, `${nm}: sem retry — erro transitório de conexão não se recupera sozinho`);
    assert.ok(n.maxTries >= 2, `${nm}: mais de uma tentativa`);
  }
});

test('Chaves curtas de linhas cortam o overhead de tokens de saída (documentos densos truncavam antes)', () => {
  // Achado em produção (sessão 7 cont.¹¹): os 3 documentos que truncaram
  // (finish_reason=length) no "teste v18" eram consolidados comparativos
  // multi-ano — cada conta vira 2-3 linhas via periodo_coluna. Prova que a
  // representação por linha ficou objetivamente mais compacta (menos
  // caracteres de CHAVE repetidos centenas de vezes por documento).
  const linhaAntiga = {
    secao: 'Ativo Circulante', secao_canonica: 'ativo_circulante', entidade_coluna: null,
    periodo_coluna: '2023', chave: 'Caixa e equivalentes de caixa', valor_texto: '1.234.567,89',
    valor_num: 1234567.89, origem_pagina: 3, confianca: 0.95,
  };
  const linhaNova = {
    s: 'Ativo Circulante', sc: 'ativo_circulante', ec: null,
    pc: '2023', k: 'Caixa e equivalentes de caixa', vt: '1.234.567,89',
    vn: 1234567.89, op: 3, cf: 0.95,
  };
  const bytesAntigos = JSON.stringify(linhaAntiga).length;
  const bytesNovos = JSON.stringify(linhaNova).length;
  assert.ok(bytesNovos < bytesAntigos, `esperava reduzir; antigo=${bytesAntigos} novo=${bytesNovos}`);
  const reducaoPct = (1 - bytesNovos / bytesAntigos) * 100;
  assert.ok(reducaoPct >= 15, `esperava >=15% de redução por linha, obteve ${reducaoPct.toFixed(1)}%`);
});

// O guarda de orçamento tem de estar ANTES de qualquer gasto: depois da
// classificação por nome (que é grátis e diz quantas chamadas o lote fará) e
// antes de `Preparar Conteudo`, que abre os binários para as chamadas.
test('Topologia: o teto de gasto fica entre a classificação por nome e o conteúdo', () => {
  assert.deepEqual(wf.connections['Classificar Nome'].main[0].map((c) => c.node), ['Orcamento do Lote']);
  assert.deepEqual(wf.connections['Orcamento do Lote'].main[0].map((c) => c.node), ['Preparar Conteudo']);
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
    if (n.type === 'n8n-nodes-base.code') {
      // Dois nós legitimamente veem o LOTE inteiro, por motivos diferentes:
      // `Listar Arquivos` faz fan-out (1 item → N), e `Orcamento do Lote` é N→N
      // mas precisa contar o lote para decidir se ele cabe no teto de gasto —
      // uma decisão que por definição não existe olhando um item por vez.
      if (n.name === 'Listar Arquivos' || n.name === 'Orcamento do Lote') {
        assert.equal(n.parameters.mode, 'runOnceForAllItems', `${n.name} enxerga o lote inteiro`);
      } else {
        assert.equal(n.parameters.mode, 'runOnceForEachItem', `${n.name} é transformação 1:1`);
      }
      // toda referência $('X') aponta para um node que existe (pega renomeações)
      for (const m of n.parameters.jsCode.matchAll(/\$\('([^']+)'\)/g)) {
        assert.ok(nomes.includes(m[1]), `node "${n.name}" referencia "${m[1]}" que não existe no workflow`);
      }
    }
    // nós Postgres referenciam outros nós pelo nome na expressão de Query
    // Parameters (queryReplacement) — mesma pegadinha de renomeação se aplica.
    const queryReplacement = n.parameters?.options?.queryReplacement;
    if (typeof queryReplacement === 'string') {
      for (const m of queryReplacement.matchAll(/\$\('([^']+)'\)/g)) {
        assert.ok(nomes.includes(m[1]), `node "${n.name}" referencia "${m[1]}" que não existe no workflow`);
      }
    }
  }
});

// --- Anti-drift: o diagnóstico de erro do workflow É o de lib/extract.mjs -----
// Terceiro mirror deste repositório (depois do prompt e dos apelidos), e os dois
// anteriores JÁ divergiram na prática. Aqui a função é auto-contida de propósito
// e o gerador embute o `toString()` dela — este teste trava que os DOIS nós que
// diagnosticam erro carregam exatamente o mesmo código da lib.
test('os nós de parse carregam o MESMO diagnosticarErroApi de lib/extract.mjs', () => {
  const fonte = diagnosticarErroApi.toString();
  for (const nome of ['Parse Extracao', 'Parse OpenAI Classif']) {
    assert.ok(code(nome).includes(fonte),
      `${nome}: o diagnóstico embutido divergiu da fonte em lib/extract.mjs`);
  }
});

// E o comportamento de verdade, executando o código REAL do nó: o sintoma exato
// do "teste v30" (o n8n devolve só a própria dica de 429) tem de virar causa
// nomeada, e uma causa que espaçar NÃO resolve tem de dizer isso.
test('Parse Extracao: 429 sem corpo vira causa nomeada; quota diz que espaçar não resolve', async () => {
  const req = { json: { documento_versao_id: 'ver-9', tipo: 'BALANCO', openai_body: {} } };
  const soDica = { json: { error: { message: "Try spacing your requests out using the batching settings under 'Options'" } } };
  const p1 = await run('Parse Extracao', { item: soDica, refs: { 'Montar Req Extracao': req } });
  assert.equal(p1.json.campos.length, 0);
  assert.match(p1.json.falha_motivo, /HTTP 429/);
  assert.match(p1.json.falha_motivo, /não disse QUAL/, 'não afirma cadência sem evidência');

  const comQuota = { json: { error: { httpCode: '429', cause: { error: { type: 'insufficient_quota', message: 'You exceeded your current quota' } } } } };
  const p2 = await run('Parse Extracao', { item: comQuota, refs: { 'Montar Req Extracao': req } });
  assert.match(p2.json.falha_motivo, /CRÉDITO DA OPENAI ESGOTADO/);
  assert.match(p2.json.falha_motivo, /NÃO resolve/, 'diz explicitamente o que não resolve');
  assert.match(p2.json.falha_motivo, /insufficient_quota/, 'o detalhe técnico vai junto');
});

// --- Anti-drift: os apelidos do workflow SÃO os de lib/taxonomia.mjs ---------
// Mesmo defeito do prompt, e este já estava acontecendo: a cópia à mão dentro de
// build-workflow.mjs parava em BALANCETE, então o nó que roda em produção não
// conhecia DF_AUDITADA, MAPA_DIVIDA, EXTRATO_BANCARIO, AGING_AR/AP, ESTOQUE,
// CERTIDOES, CONTINGENCIAS, SITUACAO_FISCAL, ORGANOGRAMA, RAZAO nem NOTAS_EXPL —
// arquivos com esses nomes saíam do passe de nome SEM TIPO, que é exatamente o
// gasto de chamada de IA que a classificação por nome existe para evitar.
test('os ALIASES do workflow gerado são IDÊNTICOS aos de lib/taxonomia.mjs (ordem inclusa)', () => {
  const m = code('Classificar Nome').match(/const ALIASES=(\[[\s\S]*?\]);/);
  assert.ok(m, 'ALIASES embutido como literal JSON no nó');
  // Ordem importa: a lista é avaliada de cima para baixo e a regra específica
  // ("faturamento intragrupo") tem de ser testada antes da genérica
  // ("faturamento"). deepEqual sem sort é intencional.
  assert.deepEqual(JSON.parse(m[1]), ALIASES, 'apelidos do workflow == fonte única, na mesma ordem');
});

// --- Cadência da OpenAI: a extração é mais lenta que a classificação ---------
// Teste v28 (14 documentos): DOIS caíram por 429 — e eram dois dos documentos
// MENORES do book. Não foi o tamanho deles; foi o balde de TPM já esvaziado pelos
// pesados que passaram antes. Quem esvazia o balde não é quem cai, então o que
// espalha as chamadas da extração no tempo é o que resolve; retry não (o
// `waitBetweenTries` do N8N tem teto de 5s, e 6 tentativas cabem na MESMA janela
// de TPM que acabou de recusar).
test('a cadência da extração É a aritmética do TPM, não um número escolhido', () => {
  // A correção do v30. A OpenAI calcula o consumo de rate limit como o MÁXIMO
  // entre `max_tokens` e os tokens estimados do request — então `max_tokens` é
  // RESERVA de TPM, e toda extração reserva o mesmo, seja o PDF de 2 KB ou de 40
  // páginas (foi por isso que as notas explicativas minúsculas também tomaram
  // 429). Logo o intervalo entre chamadas não é gosto: é 60s ÷ (TPM ÷ max_tokens).
  //
  // Este teste trava a RELAÇÃO, não o valor: se alguém mexer em max_tokens ou no
  // TPM da conta sem recalcular a cadência, ele reprova. Era exatamente esse
  // acoplamento que faltava — eu subi 6s→12s sem olhar o max_tokens, e 12s
  // suportava 5 chamadas/min = 81.920 TPM, quase 3x o teto do Tier 1.
  const intervalo = byName['OpenAI Extrair'].parameters.options?.batching?.batch?.batchInterval;
  const chamadasPorMinuto = 60000 / intervalo;
  const tpmDemandado = chamadasPorMinuto * MAX_OUTPUT_TOKENS;
  const TPM_TIER1_GPT4O = 30000;
  assert.ok(tpmDemandado <= TPM_TIER1_GPT4O,
    `a cadência demanda ${Math.round(tpmDemandado)} TPM, acima do Tier 1 (${TPM_TIER1_GPT4O}) — `
    + `com intervalo de ${intervalo}ms e max_tokens de ${MAX_OUTPUT_TOKENS}`);
  // …e não folgado ao ponto de ser lentidão gratuita: no limite do tier, o
  // intervalo certo usa a banda quase toda.
  assert.ok(tpmDemandado > TPM_TIER1_GPT4O * 0.8,
    `a cadência usa só ${Math.round(tpmDemandado)} de ${TPM_TIER1_GPT4O} TPM — lentidão sem ganho`);
});

test('OpenAI Extrair espaça mais que OpenAI Classificar, e as duas têm retry', () => {
  const extrair = byName['OpenAI Extrair'];
  const classificar = byName['OpenAI Classificar'];
  const intervalo = (n) => n.parameters.options?.batching?.batch?.batchInterval;
  assert.equal(n8nBatchSize(extrair), 1, 'extração: um documento por vez');
  assert.ok(
    intervalo(extrair) > intervalo(classificar),
    `extração (${intervalo(extrair)}ms) tem de espaçar mais que classificação (${intervalo(classificar)}ms)`,
  );
  assert.ok(intervalo(extrair) >= 12000, `intervalo da extração = ${intervalo(extrair)}ms (< 12s não bastou no v28)`);
  for (const n of [extrair, classificar]) {
    assert.equal(n.retryOnFail, true, `${n.name}: retry no nível do node`);
    assert.ok(n.maxTries >= 4, `${n.name}: maxTries=${n.maxTries}`);
    assert.equal(n.onError, 'continueRegularOutput',
      `${n.name}: falha da IA não derruba a execução (vira pendência)`);
  }
});

function n8nBatchSize(node) {
  return node.parameters.options?.batching?.batch?.batchSize;
}

// --- Anti-drift: o prompt do workflow É a fonte única de lib/extract.mjs -----
// Antes o prompt existia em TRÊS lugares (lib/extract.mjs, a paráfrase manual em
// build-workflow.mjs, e o JSON gerado) e eles já tinham divergido de fato: uma
// melhoria aplicada na fonte não chegava à produção até alguém reescrever o
// mirror à mão. Agora o gerador embute o SYSTEM_PROMPT literal — este teste
// trava essa propriedade (se alguém voltar a parafrasear, o teste quebra).
test('o promptSistema do workflow gerado é IDÊNTICO ao SYSTEM_PROMPT de lib/extract.mjs', () => {
  const node = wf.nodes.find((n) => n.name === 'Montar Req Extração' || n.name === 'Montar Req Extracao');
  assert.ok(node, 'nó de montagem da requisição de extração encontrado');
  const code = node.parameters.jsCode;
  const m = code.match(/const promptSistema=("(?:[^"\\]|\\.)*");/);
  assert.ok(m, 'promptSistema embutido como literal JSON no nó');
  assert.equal(JSON.parse(m[1]), SYSTEM_PROMPT, 'prompt do workflow == fonte única (sem paráfrase manual)');
});

test('o prompt em produção carrega as instruções de escala, sinal e período canônico', () => {
  // Garante que as melhorias de blindagem a variação de contrato chegaram ao
  // JSON que o dono importa no N8N (não só à fonte).
  const node = wf.nodes.find((n) => n.name === 'Montar Req Extração' || n.name === 'Montar Req Extracao');
  // O prompt é embutido como literal JSON (aspas internas escapadas), então a
  // verificação é sobre o texto DECODIFICADO — o que a OpenAI vai receber.
  const prompt = JSON.parse(node.parameters.jsCode.match(/const promptSistema=("(?:[^"\\]|\\.)*");/)[1]);
  for (const marca of ['MOEDA E ESCALA', '"milhar"', 'PARÊNTESES são NEGATIVOS', 'notação canônica', '12M25']) {
    assert.ok(prompt.includes(marca), `prompt em produção contém ${marca}`);
  }
});

test('Parse Extracao (nó real): escala não contamina linha não-monetária', async () => {
  // Mesma proteção de lib/extract.mjs (ehLinhaNaoMonetaria), verificada no
  // CÓDIGO QUE RODA EM PRODUÇÃO: um documento em "R$ mil" com margem em % e
  // lucro por ação não pode marcar essas linhas como "milhar" (mis-escala de
  // 1000x quando o fator for aplicado).
  const { preparado } = await chainFile(1);
  const registrado = { json: { r: { documento_id: 'doc-9', documento_versao_id: 'ver-9' } } };
  const req = await run('Montar Req Extracao', { item: registrado, refs: { 'Preparar Conteudo': preparado }, env: {} });
  const resposta = { json: { choices: [{ finish_reason: 'stop', message: { content: JSON.stringify({
    moeda: 'R$', unidade: 'Em milhares de reais',
    diagnostico: {
      entidade: 'Empresa Teste Ltda', tipo_confirma: true, tipo_sugerido: 'DRE',
      periodo_tipo: 'anual', periodo_referencia: '12M25', legibilidade: 'ok',
      nota_legibilidade: null, resumo: 'DRE 2025.', justificativa: 'ok',
    },
    linhas: [
      { s: 'Receita', sc: 'receita_bruta', ec: null, pc: null, k: 'Receita Líquida', vt: '10.000', vn: 10000, op: 1, cf: 0.9 },
      { s: null, sc: 'NAO_CLASSIFICAVEL', ec: null, pc: null, k: 'Margem Líquida %', vt: '12,5%', vn: 12.5, op: 1, cf: 0.9 },
      { s: null, sc: 'NAO_CLASSIFICAVEL', ec: null, pc: null, k: 'Lucro por Ação', vt: '1,25', vn: 1.25, op: 1, cf: 0.9 },
    ],
  }) } }] } };
  const parsed = await run('Parse Extracao', { item: resposta, refs: { 'Montar Req Extracao': req } });
  assert.equal(parsed.json.campos[0].unidade, 'milhar', 'conta monetária herda a escala normalizada');
  assert.equal(parsed.json.campos[1].unidade, null, 'linha em % não herda escala');
  assert.equal(parsed.json.campos[2].unidade, null, 'lucro por ação não herda escala');
  assert.equal(parsed.json.campos[1].valor_num, 12.5, 'valor preservado');
});

test('prefixo cacheável: o system prompt é IDÊNTICO entre documentos (e vem primeiro)', async () => {
  // A OpenAI cacheia automaticamente o PREFIXO do prompt (a partir de ~1024
  // tokens) e cobra ~metade pelos tokens em cache. Nosso system prompt tem
  // ~2,5k tokens e é o mesmo para TODO documento — desde que (a) venha como
  // primeira mensagem e (b) NÃO tenha nada interpolado por documento. É o que
  // paga a maior parte do custo de tê-lo completo. Este teste trava as duas
  // condições: se alguém interpolar nome de arquivo/tipo no system prompt, o
  // cache passa a falhar em cada chamada (custo silenciosamente maior) e o
  // teste quebra. O que varia por documento vive na mensagem de USER.
  const a = await run('Montar Req Extracao', {
    item: { json: { r: { documento_id: 'd0', documento_versao_id: 'v0' } } },
    refs: { 'Preparar Conteudo': (await chainFile(0)).preparado }, env: {},
  });
  const b = await run('Montar Req Extracao', {
    item: { json: { r: { documento_id: 'd1', documento_versao_id: 'v1' } } },
    refs: { 'Preparar Conteudo': (await chainFile(1)).preparado }, env: {},
  });
  const msgA = a.json.openai_body.messages;
  const msgB = b.json.openai_body.messages;
  assert.equal(msgA[0].role, 'system', 'system prompt é a PRIMEIRA mensagem (prefixo)');
  assert.equal(msgA[0].content, msgB[0].content, 'system prompt idêntico entre documentos diferentes');
  assert.ok(msgA[0].content.length > 3000, 'prefixo grande o suficiente para o cache valer');
  // E o que varia (nome do arquivo) está na mensagem de user, não no prefixo.
  assert.notEqual(msgA[1].content[0].text, msgB[1].content[0].text, 'o que varia por documento fica no user');
  assert.ok(!msgA[0].content.includes('BALANÇO ACUMULADO'), 'nada de nome de arquivo no system prompt');
});

test('Parse Extracao (nó real): propaga a ORDEM da linha (db/migrations/0027)', () => {
  // O mirror dentro do JSON é o que roda em produção. Sem `ordem` aqui, a
  // migration e o export existem e o dado real chega sem o sinal — o defeito do
  // v28 continuaria acontecendo em silêncio.
  const parse = wf.nodes.find((n) => n.name === 'Parse Extracao');
  assert.ok(parse, 'nó Parse Extracao não existe');
  assert.match(parse.parameters.jsCode, /p\.linhas\.map\(\(l,i\)=>\(\{ordem:i,/,
    'o mirror não está numerando as linhas pela posição no array');
});

// --- Anti-drift: a entidade do nome no nó É a de lib/classifier.mjs -----------
// QUARTO mirror do repositório. Nasceu já embutido por `toString()` (como o
// diagnóstico de erro) em vez de copiado à mão, porque dos três anteriores DOIS
// divergiram na prática — o mirror manual é o defeito, não o descuido de quem
// mexeu depois.
test('Classificar Nome carrega o MESMO parseEntidade de lib/classifier.mjs', () => {
  assert.ok(code('Classificar Nome').includes(parseEntidade.toString()),
    'a entidade embutida no nó divergiu da fonte em lib/classifier.mjs');
});

// E o comportamento, executando o código REAL do nó — não a lib. É o que prova
// que a correção do v31 chega ao workflow que o dono importa: no v31 estes 14
// documentos gravaram entidade nula, e 8 deles perderam a única outra chance de
// tê-la quando a extração morreu no teto de gasto da OpenAI.
test('Classificar Nome: entidade sai do nome do arquivo, e a confiança não muda', async () => {
  const casos = [
    ['01_BP_Vertentes_Metalurgica_2025x2024.pdf', 'Vertentes Metalurgica', 0.9, false],
    ['06_BP_COMBINADO_Grupo_Vertentes_2025.pdf', 'Grupo Vertentes', 0.65, true],
    ['10_Faturamento_24M_Vertentes_Metalurgica.pdf', 'Vertentes Metalurgica', 0.6, true],
  ];
  for (const [nome, entidade, conf, fallback] of casos) {
    const out = await run('Classificar Nome', { item: { json: { caso_id: 'c-1', nome_original: nome } } });
    assert.equal(out.json.entidade, entidade, `entidade de ${nome} no nó`);
    assert.equal(out.json.confianca, conf, `confiança de ${nome} no nó`);
    assert.equal(out.json.precisa_fallback_openai, fallback, `fallback de ${nome} no nó`);
    // o nó e a lib têm de concordar — é o ponto de existir um mirror testado
    assert.equal(out.json.entidade, classifyByFilename(nome).entidade, `nó × lib para ${nome}`);
  }
});

// --- O teto de gasto por execução, executando o nó REAL ----------------------
// Pedido do dono depois do v31: no máximo US$ 3 por execução completa, com o teto
// da OpenAI em US$ 5. As duas defesas são de camadas diferentes e nenhuma
// substitui a outra — ver o comentário do topo de lib/custo.mjs. Este teste cobre
// a de dentro: recusar o lote ANTES da primeira chamada.
const itemDoc = (nome, precisaFallback) => ({
  json: { caso_id: 'c-1', nome_original: nome, precisa_fallback_openai: precisaFallback },
  binary: { data: { fileName: nome, mimeType: 'application/pdf', data: '' } },
});

test('Orcamento do Lote: o lote do v31 é RECUSADO antes do renome', async () => {
  // 14 documentos, 8 deles precisando da classificação por conteúdo = 22 chamadas.
  const items = [
    ...Array.from({ length: 6 }, (_, i) => itemDoc(`0${i + 1}_BP_X_2025x2024.pdf`, false)),
    ...Array.from({ length: 8 }, (_, i) => itemDoc(`1${i}_DFC_X_2025.pdf`, true)),
  ];
  await assert.rejects(
    () => run('Orcamento do Lote', { items }),
    (e) => {
      assert.match(e.message, /Lote recusado ANTES de gastar/);
      assert.match(e.message, /22 chamada/, 'a mensagem conta as CHAMADAS, não os documentos');
      assert.match(e.message, /Nada foi enviado à OpenAI e nada foi gravado/,
        'quem lê o erro precisa saber que reenviar é seguro');
      return true;
    },
  );
});

test('Orcamento do Lote: depois do renome o mesmo lote passa, e o binário sobrevive', async () => {
  // Mesmos 14 documentos, agora todos resolvidos pelo nome (12M25/L24M) = 14 chamadas.
  const items = Array.from({ length: 14 }, (_, i) => itemDoc(`${i + 1}_BP_X_12M25.pdf`, false));
  const out = await run('Orcamento do Lote', { items });
  assert.equal(out.length, 14, 'passa os 14 adiante');
  assert.equal(out[0].json.orcamento_estimado_usd, 2.1);
  assert.equal(out[0].json.orcamento_chamadas, 14);
  // Regra 4 do topo do gerador: Code que repassa arquivo DEVE devolver `binary`.
  // Perder isso aqui deixaria `Preparar Conteudo` sem arquivo — e o sintoma seria
  // "conteudo nao suportado" em todo documento, longe da causa.
  assert.ok(out[13].binary?.data, 'o binário do último item sobreviveu ao nó');
  assert.equal(out[13].binary.data.fileName, '14_BP_X_12M25.pdf');
});

test('Orcamento do Lote carrega o MESMO orcamentoDoLote de lib/custo.mjs', () => {
  assert.ok(code('Orcamento do Lote').includes(orcamentoDoLote.toString()),
    'o orçamento embutido no nó divergiu da fonte em lib/custo.mjs');
});

test('Parse Extracao mede o custo real da chamada a partir do usage', async () => {
  const req = { json: { documento_versao_id: 'ver-1', tipo: 'BALANCO', openai_body: {} } };
  const resp = {
    json: {
      choices: [{ finish_reason: 'stop', message: { content: JSON.stringify({
        moeda: 'BRL', unidade: 'milhar',
        diagnostico: { entidade: 'Vertentes Metalurgica', tipo_confirma: true, tipo_sugerido: 'BALANCO', periodo_tipo: 'anual', periodo_referencia: '12M25', legibilidade: 'ok', nota_legibilidade: null, resumo: 'ok', justificativa: 'ok' },
        linhas: [{ s: 'Ativo', sc: 'ativo_circulante', ec: null, pc: null, k: 'Caixa', vt: '1.000', vn: 1000, op: 1, cf: 0.9 }],
      }) } }],
      usage: { prompt_tokens: 10_000, completion_tokens: 8_000 },
    },
  };
  const out = await run('Parse Extracao', { item: resp, refs: { 'Montar Req Extracao': req } });
  assert.equal(out.json.custo_usd, 0.105, 'custo medido, não estimado');
  assert.deepEqual(out.json.tokens, { entrada: 10_000, saida: 8_000, cache: 0 });
});
