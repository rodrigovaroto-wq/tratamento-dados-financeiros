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
  assert.match(parsed.json.justificativa, /nao retornou conteudo/);
  assert.equal(byName['OpenAI Classificar'].onError, 'continueRegularOutput');
  assert.equal(byName['OpenAI Extrair'].onError, 'continueRegularOutput');
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
  assert.equal(parsed.json.campos[0].unidade, 'R$ mil', 'unidade do documento herdada por linha');
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
  for (const nm of ['OpenAI Classificar', 'OpenAI Extrair']) {
    const n = byName[nm];
    assert.equal(n.parameters.options?.batching?.batch?.batchInterval, 6000, `${nm}: intervalo endurecido`);
    assert.equal(n.maxTries, 6, `${nm}: mais tentativas`);
  }
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
