import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
  buildExtractionRequest, parseExtractionResponse, extractionSchema, SECAO_CANONICA_ENUM,
  normalizarUnidade, normalizarMoeda, SYSTEM_PROMPT, ehLinhaNaoMonetaria,
} from '../lib/extract.mjs';
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
  assert.equal(r.unidade, 'milhar', '"R$ mil" é normalizado para a escala canônica');
  assert.equal(r.campos.length, 3);
  assert.equal(r.campos[0].secao, 'Receita Operacional');
  assert.equal(r.campos[0].secao_canonica, 'receita_bruta');
  assert.equal(r.campos[0].chave, 'Receita líquida');
  assert.equal(r.campos[0].valor_num, 10000);
  assert.equal(r.campos[0].unidade, 'milhar'); // herda a unidade (normalizada) do documento
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

// --- Escala/moeda: normalização de fronteira (variação entre documentos) -----
// A `unidade` é herdada por TODA linha e a reconciliação Classe A compara a
// unidade de DOIS documentos diferentes (0009: divergência aborta a checagem),
// então texto livre inconsistente entre arquivos gerava precondição falsa.
test('normalizarUnidade colapsa as redações reais de escala num vocabulário fechado', () => {
  for (const bruto of ['R$ mil', 'milhares de reais', 'Em R$ mil', 'MILHAR', 'valores em milhares', 'R$ Mil']) {
    assert.equal(normalizarUnidade(bruto), 'milhar', `"${bruto}" → milhar`);
  }
  for (const bruto of ['R$ milhões', 'milhoes', 'em milhões de reais', 'MILHAO']) {
    assert.equal(normalizarUnidade(bruto), 'milhao', `"${bruto}" → milhao`);
  }
  for (const bruto of ['unidade', 'reais', 'R$', 'valores inteiros']) {
    assert.equal(normalizarUnidade(bruto), 'unidade', `"${bruto}" → unidade`);
  }
  // Desconhecido/ausente NUNCA chuta uma escala (errar em 1000x é pior que não saber).
  for (const bruto of [null, undefined, '', '   ', 'sei lá', 'xyz']) {
    assert.equal(normalizarUnidade(bruto), null, `${JSON.stringify(bruto)} → null`);
  }
});

test('normalizarMoeda devolve código ISO', () => {
  for (const bruto of ['R$', 'reais', 'BRL', 'Real']) assert.equal(normalizarMoeda(bruto), 'BRL');
  assert.equal(normalizarMoeda('US$'), 'USD');
  assert.equal(normalizarMoeda('dólar'), 'USD');
  assert.equal(normalizarMoeda('EUR'), 'EUR');
  assert.equal(normalizarMoeda(null), null);
  assert.equal(normalizarMoeda('qualquer coisa'), null);
});

test('parseExtractionResponse normaliza escala e moeda do documento', () => {
  const api = { choices: [{ finish_reason: 'stop', message: { content: JSON.stringify({
    moeda: 'R$', unidade: 'Em milhares de reais',
    diagnostico: {
      entidade: 'X Ltda', tipo_confirma: true, tipo_sugerido: 'BALANCO', periodo_tipo: 'anual',
      periodo_referencia: '12M25', legibilidade: 'ok', nota_legibilidade: null, resumo: 'r', justificativa: 'j',
    },
    linhas: [{ s: 'Ativo Circulante', sc: 'ativo_circulante', ec: null, pc: null, k: 'Caixa', vt: '1.000', vn: 1000, op: 1, cf: 0.9 }],
  }) } }] };
  const r = parseExtractionResponse(api);
  assert.equal(r.moeda, 'BRL');
  assert.equal(r.unidade, 'milhar');
  assert.equal(r.campos[0].unidade, 'milhar', 'a escala normalizada é a herdada por linha');
});

// --- Prompt: instruções que blindam a variação entre contratos --------------
test('SYSTEM_PROMPT instrui a notação CANÔNICA de período na emissão', () => {
  // Sem isto, a IA emitia o período em notação livre ("2025", "31/12/2024",
  // "12M25") — inconsistente com o lado do nome (lib/classifier.mjs).
  assert.match(SYSTEM_PROMPT, /notação canônica/i);
  for (const forma of ['12M25', '1T25', 'L24M', '23,24,25', 'AAAA-MM-DD']) {
    assert.ok(SYSTEM_PROMPT.includes(forma), `prompt exemplifica a forma "${forma}"`);
  }
});

test('SYSTEM_PROMPT define moeda e o vocabulário FECHADO de escala', () => {
  // moeda/unidade eram `required` no schema mas o prompt não dizia nada sobre
  // elas — o modelo escolhia o formato sozinho, documento a documento.
  assert.match(SYSTEM_PROMPT, /MOEDA E ESCALA/);
  assert.match(SYSTEM_PROMPT, /BRL/);
  for (const v of ['"unidade"', '"milhar"', '"milhao"']) {
    assert.ok(SYSTEM_PROMPT.includes(v), `prompt fecha o vocabulário em ${v}`);
  }
  // Não converter na origem: o número vai como impresso, a escala é declarada.
  assert.match(SYSTEM_PROMPT, /NÃO converta os valores/i);
});

test('SYSTEM_PROMPT define convenção de SINAL e decimal brasileiro', () => {
  // O prompt só dizia "número puro"; parênteses/decimal BR ficavam por conta
  // do palpite do modelo (fonte de erro de sinal e de 1.000 → 1,0).
  assert.match(SYSTEM_PROMPT, /PARÊNTESES são NEGATIVOS/i);
  assert.ok(SYSTEM_PROMPT.includes('"1.234,56" → 1234.56'), 'exemplifica o decimal BR');
  assert.ok(SYSTEM_PROMPT.includes('"1.000" → 1000'), 'exemplifica milhar sem decimal');
  assert.match(SYSTEM_PROMPT, /DEVEDOR\/CREDOR/i, 'cobre balancete com coluna D/C');
});

// --- Escala por linha: não herdar a escala do documento onde ela não vale ----
test('ehLinhaNaoMonetaria reconhece linhas fora da escala monetária', () => {
  for (const [chave, vt] of [
    ['Margem Bruta %', null], ['Lucro por Ação', '1,25'], ['LPA', '1,25'],
    ['Participação percentual', null], ['Quantidade de itens', '120'],
    ['Número de Ações', '1.000.000'], ['Índice de liquidez', '1,5 %'],
  ]) {
    assert.equal(ehLinhaNaoMonetaria(chave, vt), true, `"${chave}" é não-monetária`);
  }
  // Conservador de propósito: conta monetária legítima NÃO pode ser confundida
  // (um falso positivo aqui esconderia a escala de uma conta de verdade).
  for (const [chave, vt] of [
    ['Margem de Contribuição', '1.500,00'], ['Caixa e Equivalentes', '100'],
    ['Receita Operacional Bruta', '10.000'], ['Fornecedores', '(2.000)'],
  ]) {
    assert.equal(ehLinhaNaoMonetaria(chave, vt), false, `"${chave}" é monetária`);
  }
});

test('parseExtractionResponse: escala do documento NÃO contamina linha não-monetária', () => {
  // Demonstrações reais misturam naturezas no mesmo arquivo: balanço/DRE em
  // "R$ mil" junto de LPA e margens em %. Herdar "milhar" nessas linhas é uma
  // mis-escala silenciosa de 1000x quando o fator for aplicado.
  const api = { choices: [{ finish_reason: 'stop', message: { content: JSON.stringify({
    moeda: 'BRL', unidade: 'R$ mil',
    diagnostico: {
      entidade: 'X', tipo_confirma: true, tipo_sugerido: 'DRE', periodo_tipo: 'anual',
      periodo_referencia: '12M25', legibilidade: 'ok', nota_legibilidade: null, resumo: 'r', justificativa: 'j',
    },
    linhas: [
      { s: 'Receita', sc: 'receita_bruta', ec: null, pc: null, k: 'Receita Líquida', vt: '10.000', vn: 10000, op: 1, cf: 0.9 },
      { s: null, sc: 'NAO_CLASSIFICAVEL', ec: null, pc: null, k: 'Margem Líquida %', vt: '12,5%', vn: 12.5, op: 1, cf: 0.9 },
      { s: null, sc: 'NAO_CLASSIFICAVEL', ec: null, pc: null, k: 'Lucro por Ação', vt: '1,25', vn: 1.25, op: 1, cf: 0.9 },
    ],
  }) } }] };
  const r = parseExtractionResponse(api);
  assert.equal(r.unidade, 'milhar', 'escala do documento');
  assert.equal(r.campos[0].unidade, 'milhar', 'conta monetária herda a escala');
  assert.equal(r.campos[1].unidade, null, 'linha em % não herda escala (null = desconhecida)');
  assert.equal(r.campos[2].unidade, null, 'lucro por ação não herda escala');
  assert.equal(r.campos[1].valor_num, 12.5, 'o valor em si é preservado');
});

test('SYSTEM_PROMPT avisa que a escala vale só para valores monetários', () => {
  assert.match(SYSTEM_PROMPT, /escala vale para os valores MONETÁRIOS/i);
  assert.match(SYSTEM_PROMPT, /POR AÇÃO/);
});

test('DMPL/DVA: enum de seção canônica, códigos do diagnóstico e contrato da matriz (db/migrations/0024)', () => {
  // 1. A IA passa a ter como dizer "esta linha é da DMPL/DVA". Sem isso, a
  //    linha de uma DMPL embutida num PDF composto só tinha dois destinos, os
  //    dois ruins: 'patrimonio_liquido' (o saldo de fechamento REPETE o total do
  //    PL — somá-lo infla o balanço, bug real do export do dono) ou
  //    'NAO_CLASSIFICAVEL'.
  assert.ok(SECAO_CANONICA_ENUM.includes('dmpl'));
  assert.ok(SECAO_CANONICA_ENUM.includes('dva'));

  // 2. …e como classificar o DOCUMENTO inteiro como DMPL/DVA. `tipo_sugerido` é
  //    um enum fechado nos códigos da taxonomia: enquanto DMPL não existia lá, o
  //    modelo escolhia o vizinho mais próximo (a DMPL do book saiu como MUTUOS).
  const tipos = extractionSchema().schema.properties.diagnostico.properties.tipo_sugerido.enum;
  assert.ok(tipos.includes('DMPL'));
  assert.ok(tipos.includes('DVA'));

  // 3. O contrato da MATRIZ da DMPL — `secao` = movimento (a linha da tabela),
  //    `chave` = componente do PL (o cabeçalho da coluna). É o que permite ao
  //    export reconstruir a matriz; se o prompt parar de pedir isso, a aba DMPL
  //    vira uma listagem sem sentido.
  assert.match(SYSTEM_PROMPT, /"secao" = o rótulo do MOVIMENTO/);
  assert.match(SYSTEM_PROMPT, /"chave" = o\s+rótulo do COMPONENTE do PL/);
  // e a proibição explícita de reaproveitar entidade_coluna para os componentes
  assert.match(SYSTEM_PROMPT, /Não use\s+entidade_coluna para os componentes do PL/);
  // …e de marcar linha de DMPL como conta do PL (a dupla contagem)
  assert.match(SYSTEM_PROMPT, /Nunca marque uma linha de DMPL como "patrimonio_liquido"/);
});

test('DMPL: parse mapeia a matriz para linhas (movimento × componente)', () => {
  const api = {
    choices: [{
      finish_reason: 'stop',
      message: {
        content: JSON.stringify({
          moeda: 'BRL', unidade: 'milhar',
          diagnostico: { entidade: 'VERTENTES METALÚRGICA LTDA.', tipo_confirma: true, tipo_sugerido: 'DMPL',
            periodo_tipo: 'anual', periodo_referencia: '12M25', legibilidade: 'ok', nota_legibilidade: null,
            resumo: 'Mutações do PL', justificativa: 'Matriz de movimentos por componente.' },
          linhas: [
            { s: 'SALDOS EM 31 DE DEZEMBRO DE 2024', sc: 'dmpl', ec: null, pc: null,
              k: 'Capital social', vt: '45.000', vn: 45000, op: 1, cf: 0.98 },
            { s: 'SALDOS EM 31 DE DEZEMBRO DE 2024', sc: 'dmpl', ec: null, pc: null,
              k: 'Total', vt: '24.801', vn: 24801, op: 1, cf: 0.98 },
            { s: 'Prejuízo líquido do exercício', sc: 'dmpl', ec: null, pc: null,
              k: 'Prejuízos acumulados', vt: '(17.901)', vn: -17901, op: 1, cf: 0.97 },
          ],
        }),
      },
    }],
  };
  const r = parseExtractionResponse(api);
  assert.equal(r.falhaMotivo, null);
  assert.equal(r.campos.length, 3);
  // o movimento vai em `secao` e o componente em `chave` — é assim que o export
  // remonta a matriz (linhas = movimentos, colunas = componentes)
  assert.equal(r.campos[0].secao, 'SALDOS EM 31 DE DEZEMBRO DE 2024');
  assert.equal(r.campos[0].chave, 'Capital social');
  assert.equal(r.campos[0].secao_canonica, 'dmpl');
  assert.equal(r.campos[2].valor_num, -17901);
  // nenhum componente do PL pode ter virado "entidade" (isso criaria empresas
  // fantasmas no export, uma por componente)
  assert.ok(r.campos.every((c) => c.entidade_coluna === null));
});

test('ORDEM da linha vem da posição no array, não do modelo (db/migrations/0027)', () => {
  // Por que a ordem não é pedida ao modelo: a posição no array JÁ é a ordem de
  // leitura do documento. Pedir um campo gastaria token de saída por linha (e
  // `linhas` é o único bloco que se repete centenas de vezes) e daria ao modelo
  // uma chance de errar algo que nós sabemos com certeza.
  const api = { choices: [{ finish_reason: 'stop', message: { content: JSON.stringify({
    moeda: 'BRL', unidade: 'milhar',
    diagnostico: { entidade: 'VT LOGÍSTICA E TRANSPORTES LTDA.', tipo_confirma: true,
      tipo_sugerido: 'BALANCO', periodo_tipo: 'anual', periodo_referencia: '12M24',
      legibilidade: 'ok', nota_legibilidade: null, resumo: 'BP', justificativa: 'ok' },
    // Sequência REAL do arquivo que causou o defeito do teste v28: o subtotal
    // "Contas a Receber" (3.293) impresso ACIMA dos seus dois componentes.
    linhas: [
      { s: 'Ativo Circulante', sc: 'ativo_circulante', ec: null, pc: null, k: 'Caixa e bancos', vt: '399', vn: 399, op: 1, cf: 0.98 },
      { s: 'Ativo Circulante', sc: 'ativo_circulante', ec: null, pc: null, k: 'Contas a Receber', vt: '3.293', vn: 3293, op: 1, cf: 0.98 },
      { s: 'Ativo Circulante', sc: 'ativo_circulante', ec: null, pc: null, k: 'Fretes a receber', vt: '3.562', vn: 3562, op: 1, cf: 0.97 },
      { s: 'Ativo Circulante', sc: 'ativo_circulante', ec: null, pc: null, k: '(-) PECLD', vt: '(269)', vn: -269, op: 1, cf: 0.97 },
    ],
  }) } }] };
  const r = parseExtractionResponse(api);
  assert.deepEqual(r.campos.map((c) => c.ordem), [0, 1, 2, 3]);
  // A ordem tem de acompanhar o rótulo — se elas se descolarem, o export
  // reconhece o subtotal errado e tira da soma uma conta legítima.
  assert.equal(r.campos[1].chave, 'Contas a Receber');
  assert.equal(r.campos[1].ordem, 1);
  // O subtotal é a soma dos DOIS seguintes: é esse padrão que o export procura.
  assert.equal(r.campos[2].valor_num + r.campos[3].valor_num, r.campos[1].valor_num);
});
