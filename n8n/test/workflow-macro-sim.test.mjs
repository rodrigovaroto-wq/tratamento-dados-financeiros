import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { SERIES_MACRO, INDICADORES_FOCUS, numeroMacro } from '../lib/macro.mjs';

// Executa os códigos REAIS dos nós Code do workflow gerado, com a semântica do
// N8N ($input/$json/$()). O mesmo padrão de `workflow-sim.test.mjs`: o mirror
// dentro do JSON é o que roda em produção, então é ELE que precisa ser testado
// — testar só a lib deixaria o mirror livre para divergir, que é exatamente o
// bug que este repositório já teve.
const __dirname = dirname(fileURLToPath(import.meta.url));
const workflow = JSON.parse(readFileSync(join(__dirname, '..', 'workflow.macro.json'), 'utf8'));
const nodeDe = (nome) => workflow.nodes.find((n) => n.name === nome);

function rodarCode(nome, { itens = [], porNome = {} } = {}) {
  const n = nodeDe(nome);
  assert.ok(n, `nó ${nome} não existe no workflow gerado`);
  const $input = { all: () => itens.map((json) => ({ json })) };
  const $ = (outro) => ({ item: { json: porNome[outro] } });
  const fn = new Function('$input', '$', '$json', `${n.parameters.jsCode}`);
  if (n.parameters.mode === 'runOnceForEachItem') {
    return itens.map((json) => fn($input, $, json));
  }
  return fn($input, $, itens[0]);
}

test('workflow macro: agenda mensal depois da divulgação do IPCA', () => {
  const t = nodeDe('Agenda Mensal');
  const dia = t.parameters.rule.interval[0].triggerAtDayOfMonth;
  // Dia 12 e não dia 1: o IBGE divulga o IPCA do mês anterior por volta do dia
  // 10. Coletar antes traria o mês sempre incompleto e faria a conferência
  // entre fontes acusar divergência por ATRASO DE PUBLICAÇÃO, não por erro.
  assert.ok(dia >= 10, `coleta no dia ${dia} corre na frente da divulgação do IPCA`);
});

test('workflow macro: toda série do catálogo entra na coleta', () => {
  const gerado = rodarCode('Séries a Coletar');
  assert.equal(gerado.length, SERIES_MACRO.length);
  for (const s of SERIES_MACRO) {
    const item = gerado.find((g) => g.json.__serie === s.codigo);
    assert.ok(item, `série ${s.codigo} ficou de fora da coleta`);
    assert.match(item.json.__url, new RegExp(`bcdata\\.sgs\\.${s.sgs}/`));
  }
  const focus = rodarCode('Indicadores Focus');
  assert.equal(focus.length, INDICADORES_FOCUS.length);
  // O filtro tem de ir codificado, senão o OData recusa a query.
  assert.ok(focus.every((f) => f.json.__url.includes('Indicador%20eq%20')));
});

test('workflow macro: normaliza SGS e SIDRA no MESMO formato de gravação', () => {
  // Respostas reais das duas APIs (2026-07-28), reduzidas.
  const saida = rodarCode('Normalizar Observações', {
    itens: [
      { __serie: 'IPCA', __fonte: 'BCB/SGS', __corpo: [
        { data: '01/01/2026', valor: '0.33' },
        { data: '01/02/2026', valor: '0.70' },
      ] },
      { __serie: 'IPCA', __fonte: 'IBGE/SIDRA', __corpo: [
        { NC: 'Nível Territorial (Código)', V: 'Valor', D3C: 'Mês (Código)' }, // cabeçalho
        { NC: '1', V: '0.33', D3C: '202601' },
      ] },
      { __serie: 'CAMBIO_USD', __fonte: 'BCB/SGS', __corpo: [{ data: '30/06/2026', valor: '5,4321' }] },
    ],
  });
  const obs = saida[0].json.observacoes;
  assert.equal(obs.length, 4);

  const sgs = obs.find((o) => o.fonte === 'BCB/SGS' && o.data_ref === '2026-01-01');
  assert.deepEqual(sgs, { serie: 'IPCA', fonte: 'BCB/SGS', data_ref: '2026-01-01', valor: 0.33 });

  // A linha de cabeçalho do SIDRA não pode virar observação.
  const ibge = obs.filter((o) => o.fonte === 'IBGE/SIDRA');
  assert.equal(ibge.length, 1);
  assert.equal(ibge[0].data_ref, '2026-01-01');
  assert.equal(ibge[0].valor, 0.33);

  // As duas fontes coexistem no mesmo mês — é isso que permite conferir.
  assert.equal(obs.filter((o) => o.serie === 'IPCA' && o.data_ref === '2026-01-01').length, 2);

  // Vírgula decimal (aparece em série antiga) não pode virar NaN e sumir.
  assert.equal(obs.find((o) => o.serie === 'CAMBIO_USD').valor, 5.4321);
});

test('workflow macro: observação sem data ou sem valor é descartada, não gravada torta', () => {
  const saida = rodarCode('Normalizar Observações', {
    itens: [{ __serie: 'IPCA', __fonte: 'BCB/SGS', __corpo: [
      { data: 'jan/26', valor: '1.0' },   // data ilegível
      { data: '01/03/2026', valor: '' },  // valor ausente
      { data: '01/04/2026', valor: '0.42' },
    ] }],
  });
  const obs = saida[0].json.observacoes;
  assert.equal(obs.length, 1, 'só a observação íntegra deveria passar');
  assert.equal(obs[0].data_ref, '2026-04-01');
});

test('workflow macro: Focus fica só na coleta mais recente (uma linha por ano)', () => {
  const saida = rodarCode('Normalizar Focus', {
    itens: [{ __serie: 'IPCA', __corpo: { value: [
      { Data: '2026-07-24', DataReferencia: '2026', Mediana: 5.1209, Media: 5.13, numeroRespondentes: 151 },
      { Data: '2026-07-24', DataReferencia: '2027', Mediana: 4.5, Media: 4.51, numeroRespondentes: 148 },
      { Data: '2026-07-17', DataReferencia: '2026', Mediana: 5.28, Media: 5.3, numeroRespondentes: 149 },
    ] } }],
  });
  const exp = saida[0].json.expectativas;
  assert.equal(exp.length, 2);
  const y26 = exp.find((e) => e.ano_ref === 2026);
  assert.equal(y26.mediana, 5.1209, 'pegou a coleta antiga em vez da mais recente');
  assert.equal(y26.coletado_em, '2026-07-24');
  // Sem a data de coleta a projeção deixa de ser reproduzível.
  assert.ok(exp.every((e) => e.coletado_em));
});

test('workflow macro: grava pelas funções da 0025 e confere as fontes', () => {
  assert.match(nodeDe('Gravar Índices').parameters.query, /fn_registrar_indice_macro/);
  assert.match(nodeDe('Gravar Expectativas').parameters.query, /fn_registrar_expectativa_macro/);
  assert.match(nodeDe('Conferir Fontes').parameters.query, /fn_divergencias_indice_macro/);
});

test('workflow macro: uma fonte fora do ar não derruba as outras', () => {
  // As três APIs são públicas e caem. Sem tolerância a erro, a queda de uma
  // interrompe a execução e o mês inteiro se perde — sendo que a ingestão é
  // idempotente e o mês voltaria sozinho na coleta seguinte.
  for (const nome of ['BCB SGS', 'IBGE SIDRA (IPCA)', 'BCB Focus']) {
    const n = nodeDe(nome);
    assert.equal(n.onError, 'continueRegularOutput', `${nome} sem tolerância a erro`);
    assert.equal(n.retryOnFail, true, `${nome} sem retry`);
  }
});

// --- O runtime REAL do n8n: o nó HTTP explode array em N itens ----------------
// Este é o teste que faltava, e a razão pela qual a perda total de 6 séries
// passava verde. O nó HTTP Request do n8n, ao receber uma resposta JSON que é um
// ARRAY, devolve um item por elemento. O SGS responde `[{data,valor}, …×132]`,
// então `Manter Contexto SGS` (que é `runOnceForEachItem`) recebe UM OBJETO por
// item — nunca o array inteiro.
//
// O teste antigo injetava `__corpo` já como array, um modelo que não corresponde
// ao runtime. Com isso, `if (!Array.isArray(corpo)) continue` parecia inofensivo
// aqui e descartava ~792 itens em produção, calado. O ramo IBGE/SIDRA sobrevivia
// porque é UMA requisição e o nó anterior remonta o array explicitamente — a
// assimetria entre os dois ramos era o sintoma à vista.
test('SGS: o split do nó HTTP (um item por observação) NÃO perde dado', () => {
  // É assim que os itens chegam de verdade: 6 séries × N observações, cada item
  // com `__corpo` sendo UMA observação e o `__serie` correto vindo do pareamento.
  const itens = [];
  for (const s of ['IPCA', 'SELIC', 'CDI']) {
    for (const [data, valor] of [['01/01/2026', '0.33'], ['01/02/2026', '0.70'], ['01/03/2026', '0.51']]) {
      itens.push({ __serie: s, __fonte: 'BCB/SGS', __corpo: { data, valor } });
    }
  }
  const saida = rodarCode('Normalizar Observações', { itens });
  const obs = saida[0].json.observacoes;
  assert.equal(obs.length, 9, 'as 9 observações do split foram normalizadas');
  assert.equal(saida[0].json.descartados, 0, 'nenhum item foi descartado');
  // Cada observação mantém a SÉRIE do seu item — é por isso que não se remonta o
  // array aqui: o pareamento do n8n já resolveu de qual requisição o item veio.
  for (const s of ['IPCA', 'SELIC', 'CDI']) {
    assert.equal(obs.filter((o) => o.serie === s).length, 3, `série ${s} preservada no split`);
  }
  assert.deepEqual(obs[0], { serie: 'IPCA', fonte: 'BCB/SGS', data_ref: '2026-01-01', valor: 0.33 });
});

// Corpo de ERRO da API também é um objeto único. Envolvê-lo num array faria a
// falha virar "zero observações" — o mesmo silêncio, por outra porta. Só o que tem
// CARA de observação é aceito, e o resto é CONTADO.
test('SGS: corpo de erro da API não é confundido com observação, e é contado', () => {
  const saida = rodarCode('Normalizar Observações', {
    itens: [
      { __serie: 'IPCA', __fonte: 'BCB/SGS', __corpo: { data: '01/01/2026', valor: '0.33' } },
      // com `neverError`, uma falha da API chega como CORPO, não como exceção
      { __serie: 'SELIC', __fonte: 'BCB/SGS', __corpo: { error: 'Bad Request', status: 400 } },
      { __serie: 'CDI', __fonte: 'BCB/SGS', __corpo: 'erro em texto puro' },
      { __serie: 'IGPM', __fonte: 'BCB/SGS', __corpo: null },
    ],
  });
  assert.equal(saida[0].json.observacoes.length, 1, 'só a observação de verdade entra');
  assert.equal(saida[0].json.descartados, 3, 'os três corpos inválidos são contados, não engolidos');
});

test('SGS: array inteiro (caso do SIDRA e de instância sem split) continua funcionando', () => {
  const saida = rodarCode('Normalizar Observações', {
    itens: [{ __serie: 'IPCA', __fonte: 'BCB/SGS', __corpo: [
      { data: '01/01/2026', valor: '0.33' }, { data: '01/02/2026', valor: '0.70' },
    ] }],
  });
  assert.equal(saida[0].json.observacoes.length, 2, 'a forma de array não regrediu');
  assert.equal(saida[0].json.descartados, 0);
});

// --- Anti-drift: o Focus usa o MESMO numeroMacro da lib ----------------------
// Era o último mirror manual do repositório, e tinha divergido: o nó fazia
// `typeof l.Mediana === 'number'`, rejeitando qualquer string — inclusive "4.50".
test('Normalizar Focus carrega o MESMO numeroMacro de lib/macro.mjs', () => {
  const codigo = nodeDe('Normalizar Focus').parameters.jsCode;
  assert.ok(codigo.includes(numeroMacro.toString()),
    'a conversão numérica embutida no nó divergiu da fonte em lib/macro.mjs');
});

test('Focus: decimal como STRING é aceito (era o que zerava o ramo inteiro)', () => {
  // Se o Olinda passar a serializar decimal como string — hoje ele devolve número —
  // o nó antigo descartaria TODA linha e as premissas de inflação/juro da aba
  // Modelagem iriam a 0%, sem erro em lugar nenhum.
  const saida = rodarCode('Normalizar Focus', {
    itens: [{ __serie: 'IPCA', __corpo: { value: [
      { Data: '2026-07-24', DataReferencia: '2026', Mediana: '4.50', Media: '4,52', numeroRespondentes: '151' },
      { Data: '2026-07-24', DataReferencia: '2027', Mediana: 3.9, Media: 3.88, numeroRespondentes: 148 },
      { Data: '2026-07-17', DataReferencia: '2026', Mediana: '9.99', Media: '9.99', numeroRespondentes: '10' },
    ] } }],
  });
  const exp = saida[0].json.expectativas;
  assert.equal(exp.length, 2, 'só o boletim mais recente entra, e as duas linhas dele passam');
  const y2026 = exp.find((e) => e.ano_ref === 2026);
  assert.equal(y2026.mediana, 4.5, 'decimal com ponto vindo como string');
  assert.equal(y2026.media, 4.52, 'decimal com VÍRGULA vindo como string');
  assert.equal(y2026.respondentes, 151, 'inteiro como string');
  assert.equal(exp.find((e) => e.ano_ref === 2027).mediana, 3.9, 'número continua funcionando');
});
