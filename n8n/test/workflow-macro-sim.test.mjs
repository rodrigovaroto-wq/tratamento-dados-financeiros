import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { SERIES_MACRO, INDICADORES_FOCUS } from '../lib/macro.mjs';

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
