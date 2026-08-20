// O ESPELHO DE `mergeClassification`: a lib e o que RODA EM PRODUÇÃO.
//
// POR QUE ESTE ARQUIVO EXISTE. `mergeClassification` mora em DOIS lugares:
// `n8n/lib/merge.mjs`, que é o que `merge.test.mjs` exercita, e uma cópia LITERAL
// dentro de `CODE_PARSE_CLASSIF` no `build-workflow.mjs`, que é a que vai para o
// JSON e a única que o n8n executa. Nós de Code do n8n não importam módulo, então
// a duplicação é estrutural e não dá para remover.
//
// O que dava para remover era o SILÊNCIO. Até aqui, corrigir a lib e esquecer a
// cópia deixava a suíte VERDE e a produção errada — e foi exatamente o risco na
// correção do `Math.max` (a confiança devolvida era a maior das duas, não a do
// vencedor, e um documento que a IA declarou ilegível entrava classificado sem
// humano). Um teste que exercita só a lib prova o arquivo errado.
//
// A ESTRATÉGIA: extrair a função DO JSON COMMITADO — que é o artefato que o dono
// importa — e rodar a mesma tabela de casos nas duas, exigindo resultado idêntico.
// Não se compara texto: comparar fonte reprovaria por espaço em branco e
// convidaria a "consertar" formatando. Compara-se COMPORTAMENTO.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { mergeClassification } from '../lib/merge.mjs';
import { parseCsv } from '../lib/spreadsheet.mjs';

const WORKFLOW = JSON.parse(
  readFileSync(new URL('../workflow.e1-ingestao.json', import.meta.url), 'utf8'),
);

/** O corpo de uma função nomeada dentro de um texto, delimitado por chaves. */
function corpoDaFuncao(src, nome) {
  const ini = src.indexOf(`function ${nome}`);
  if (ini < 0) return null;
  let i = src.indexOf('{', ini), prof = 0;
  for (; i < src.length; i++) {
    if (src[i] === '{') prof++;
    else if (src[i] === '}') { prof--; if (prof === 0) return src.slice(ini, i + 1); }
  }
  return null;
}

/**
 * Extrai do workflow COMMITADO a função `nome` (mais as auxiliares de que ela
 * depende) e a devolve executável. É o artefato que o dono importa no n8n, então
 * é ele que precisa ser exercitado — não a lib, que já tem teste próprio.
 */
function doWorkflow(nome, auxiliares = []) {
  const nos = (WORKFLOW.nodes ?? [])
    .map((n) => n.parameters?.jsCode)
    .filter((c) => typeof c === 'string' && c.includes(`function ${nome}`));
  assert.equal(nos.length, 1,
    `esperava EXATAMENTE um nó com ${nome} no workflow — achei ${nos.length}. `
    + 'Se virou dois, o espelho ganhou uma cópia e uma delas vai divergir.');
  const partes = [...auxiliares, nome].map((f) => {
    const corpo = corpoDaFuncao(nos[0], f);
    assert.ok(corpo, `não achei a função ${f} dentro do jsCode do nó`);
    return corpo;
  });
  return new Function(`${partes.join('\n')}; return ${nome};`)();
}

const mergeDoWorkflow = () => doWorkflow('mergeClassification');
const parseCsvDoWorkflow = () => doWorkflow('parseCsv', ['csvConta', 'csvRegs']);

// A TABELA COBRE OS QUATRO RAMOS do merge, mais o caso que motivou a correção.
const CASOS = [
  {
    nome: 'as duas acham tipo, a IA com mais confiança',
    fromName: { tipo_taxonomia: 'BALANCO', confianca: 0.6 },
    fromAI: { tipo_taxonomia: 'DRE', confianca: 0.9, justificativa: 'x' },
  },
  {
    nome: 'as duas acham tipo, o NOME com mais confiança',
    fromName: { tipo_taxonomia: 'BALANCO', confianca: 0.95 },
    fromAI: { tipo_taxonomia: 'DRE', confianca: 0.4, justificativa: 'x' },
  },
  {
    nome: 'só a IA acha tipo',
    fromName: { tipo_taxonomia: null, confianca: 0.3 },
    fromAI: { tipo_taxonomia: 'DRE', confianca: 0.8, justificativa: 'x' },
  },
  {
    // O CASO DO DEFEITO. A IA responde DESCONHECIDO (tipo vira null) com
    // confiança ALTA, e o palpite fraco do nome vence. Com `Math.max` saía 0,9 e
    // o documento entrava classificado sem revisão; com o vencedor sai 0,5 e ele
    // cai na fila, que é onde tem de cair.
    nome: 'a IA declara ilegível com confiança alta e só o NOME tem tipo',
    fromName: { tipo_taxonomia: 'BALANCO', confianca: 0.5 },
    fromAI: { tipo_taxonomia: null, confianca: 0.9, justificativa: 'documento ilegível' },
  },
  {
    nome: 'nenhuma das duas acha tipo',
    fromName: { tipo_taxonomia: null, confianca: 0.2 },
    fromAI: { tipo_taxonomia: null, confianca: 0.1, justificativa: 'nada' },
  },
  {
    nome: 'a chamada da IA falhou (confiança zero) — vale o nome',
    fromName: { tipo_taxonomia: 'MUTUOS', confianca: 0.75, periodo_ref: '2025', periodo_tipo: 'anual' },
    fromAI: { tipo_taxonomia: null, confianca: 0, justificativa: 'indisponível' },
  },
];

test('a lib e o workflow decidem IGUAL, caso a caso', () => {
  const doWorkflow = mergeDoWorkflow();
  for (const c of CASOS) {
    assert.deepEqual(
      doWorkflow(c.fromName, c.fromAI),
      mergeClassification(c.fromName, c.fromAI),
      `divergem em: ${c.nome} — a lib está testada e o workflow é o que RODA`,
    );
  }
});

test('a confiança devolvida é a do VENCEDOR, não a maior das duas', () => {
  for (const impl of [mergeClassification, mergeDoWorkflow()]) {
    const r = impl(
      { tipo_taxonomia: 'BALANCO', confianca: 0.5 },
      { tipo_taxonomia: null, confianca: 0.9, justificativa: 'documento ilegível' },
    );
    assert.equal(r.tipo_taxonomia, 'BALANCO', 'o tipo do nome é o único que existe');
    assert.equal(r.confianca, 0.5,
      'a confiança tem de ser a do palpite que venceu (0,5) — com 0,9 o documento '
      + 'passa do limiar de 0,70 e entra classificado sem humano olhar');
  }
});

// =============================================================================
// `parseCsv` — MESMO espelho, e ele carregava um defeito de corrupção silenciosa.
//
// A versão anterior era `linha.split(sep)`, sem noção de aspas. Um CSV com razão
// social entre aspas — `Empresa,"Silva, João & Cia",1000` — virava QUATRO células
// onde há três, o cabeçalho deslizava junto, e todo valor depois da vírgula
// passava a ser gravado sob o rótulo errado. Sem estouro e sem aviso.
const CASOS_CSV = [
  ['simples, vírgula', 'a,b\n1,2'],
  ['ponto e vírgula', 'a;b\n1;2'],
  ['VÍRGULA DENTRO DE ASPAS (o defeito)', 'nome,obs,v\nEmpresa,"Silva, João & Cia",1000'],
  ['aspas escapadas', 'a,b\n"x""y",2'],
  ['quebra de linha dentro do campo', 'a,b\n"li\nnha",2'],
  ['separador ; com vírgulas dentro de aspas', 'n;o\nX;"a,b,c"'],
  ['linha em branco no meio', 'a,b\n1,2\n\n3,4'],
  ['vazio', ''],
];

test('parseCsv: a lib e o workflow leem IGUAL', () => {
  const doWf = parseCsvDoWorkflow();
  for (const [nome, csv] of CASOS_CSV) {
    assert.deepEqual(doWf(csv), parseCsv(csv),
      `divergem em: ${nome} — o workflow é o que RODA na ingestão`);
  }
});

test('parseCsv: campo entre aspas com vírgula NÃO desloca as colunas', () => {
  for (const impl of [parseCsv, parseCsvDoWorkflow()]) {
    const linhas = impl('nome,obs,v\nEmpresa,"Silva, João & Cia",1000');
    assert.equal(linhas.length, 1);
    assert.deepEqual(Object.keys(linhas[0]), ['nome', 'obs', 'v'],
      'as três colunas do cabeçalho, não quatro');
    assert.equal(linhas[0].obs, 'Silva, João & Cia', 'a vírgula fica DENTRO do campo');
    assert.equal(linhas[0].v, '1000',
      'o valor continua sob "v" — com o split ingênuo ele caía sob a coluna errada');
  }
});

test('parseCsv: o separador é contado FORA das aspas', () => {
  for (const impl of [parseCsv, parseCsvDoWorkflow()]) {
    // Uma vírgula real (zero) contra três dentro de aspas: sem olhar aspas, a
    // detecção elegia a vírgula e quebrava o arquivo inteiro.
    const linhas = impl('n;o\nX;"a,b,c"');
    assert.deepEqual(linhas, [{ n: 'X', o: 'a,b,c' }]);
  }
});
