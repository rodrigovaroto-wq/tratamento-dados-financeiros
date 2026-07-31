// Simula os nós Code do workflow de DIAGNÓSTICO executando o código REAL do JSON
// gerado — mesmo padrão de workflow-sim.test.mjs. Testar só a lib deixaria o nó
// livre para divergir, que é a classe de bug que este repositório já teve duas
// vezes.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { diagnosticarErroApi } from '../lib/extract.mjs';

const wf = JSON.parse(readFileSync(new URL('../workflow.diagnostico-openai.json', import.meta.url), 'utf8'));
const code = (nome) => {
  const n = wf.nodes.find((x) => x.name === nome);
  if (!n) throw new Error(`node "${nome}" não existe no workflow de diagnóstico`);
  return n.parameters.jsCode;
};
const AsyncFunction = Object.getPrototypeOf(async function () {}).constructor;
const run = async (nome, item) => {
  const $input = { item, first: () => item, all: () => [item] };
  return new AsyncFunction('$input', '$json', code(nome)).call({}, $input, item.json);
};

test('o diagnóstico não grava nada e não roda no relógio — é diagnóstico, não pipeline', () => {
  const tipos = wf.nodes.map((n) => n.type);
  assert.ok(!tipos.some((t) => t.includes('postgres')), 'nenhum nó de banco');
  assert.ok(tipos.includes('n8n-nodes-base.manualTrigger'), 'só roda quando alguém clica');
  assert.ok(!tipos.some((t) => t.includes('scheduleTrigger')), 'nenhum trigger de relógio');
});

test('a chamada é mínima de verdade: max_tokens 1', async () => {
  const out = await run('Montar Chamada Minima', { json: {} });
  assert.equal(out.json.openai_body.max_tokens, 1,
    'max_tokens é RESERVA de TPM — 1 é o que faz esta chamada passar com o balde cheio');
});

test('o nó OpenAI tem neverError: sem isso o corpo da causa nunca chega', () => {
  const n = wf.nodes.find((x) => x.name === 'OpenAI (1 token)');
  assert.equal(n.parameters.options.response.response.neverError, true);
  assert.equal(n.credentials.httpHeaderAuth.name, 'OpenAI API',
    'tem de usar a MESMA credencial da ingestão — diagnosticar outra chave responde a pergunta errada');
});

test('Veredito carrega o MESMO diagnosticarErroApi da produção', () => {
  assert.ok(code('Veredito').includes(diagnosticarErroApi.toString()));
});

// O caso do v31: o corpo REAL que a OpenAI devolveu ao pipeline do dono.
test('Veredito: teto de gasto é nomeado e diz que espaçar não resolve', async () => {
  const resp = { json: { error: {
    type: 'insufficient_quota',
    code: 'project_spend_limit_exceeded',
    message: 'Your project has reached its configured enforced spend limit.',
    status: 429,
  } } };
  const out = await run('Veredito', resp);
  assert.equal(out.json.passou, false);
  assert.equal(out.json.causa, 'limite_de_gasto');
  assert.match(out.json.veredito, /CAUSA CLASSIFICADA: limite_de_gasto/);
  // A leitura que fecha o raciocínio: 1 token recusado NÃO pode ser cadência.
  assert.match(out.json.veredito, /descarta cadencia por/);
  assert.match(out.json.veredito, /nao existe "espacar mais" que resolva/);
});

test('Veredito: quando passa, entrega o experimento discriminante e o custo real', async () => {
  const resp = { json: {
    choices: [{ message: { content: 'ok' }, finish_reason: 'length' }],
    usage: { prompt_tokens: 8, completion_tokens: 1 },
  } };
  const out = await run('Veredito', resp);
  assert.equal(out.json.passou, true);
  assert.match(out.json.veredito, /a chamada de 1 token PASSOU/);
  assert.match(out.json.veredito, /credito e teto de gasto estao/);
  assert.match(out.json.veredito, /DESCARTADOS/);
  // custo medido de verdade: 8×2,50/1M + 1×10,00/1M = 0,00003
  assert.match(out.json.veredito, /Custo desta chamada: US\$ 0\.000030/);
});

test('Veredito: a aritmética da cadência e o teto de gasto aparecem sempre', async () => {
  for (const resp of [{ json: { usage: { prompt_tokens: 1, completion_tokens: 1 } } },
    { json: { error: { status: 429, message: 'x' } } }]) {
    const out = await run('Veredito', resp);
    assert.match(out.json.veredito, /CADENCIA CONFIGURADA/);
    assert.match(out.json.veredito, /max_tokens e RESERVA de TPM/);
    assert.match(out.json.veredito, /TETO DE GASTO POR EXECUCAO/);
    // o dono precisa saber que o teto da OpenAI tem de ficar ACIMA do do código
    assert.match(out.json.veredito, /deve ficar ACIMA disso \(US\$ 5\)/);
  }
});
