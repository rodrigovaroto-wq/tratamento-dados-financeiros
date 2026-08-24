// Simula os nós Code do workflow de DIAGNÓSTICO executando o código REAL do JSON
// gerado — mesmo padrão de workflow-sim.test.mjs. Testar só a lib deixaria o nó
// livre para divergir, que é a classe de bug que este repositório já teve duas
// vezes.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { diagnosticarErroApi } from '../lib/extract.mjs';
import { provedor } from '../lib/provedor.mjs';
import { PRECO_USD_POR_MILHAO, MODELO_EXTRACAO } from '../lib/custo.mjs';

const PROV = provedor();
const GEMINI = PROV.dialeto === 'gemini';

/** O teto de saída do corpo montado, no dialeto do provedor ativo. */
const tetoDoCorpo = (corpo) => (GEMINI ? corpo.generationConfig.maxOutputTokens : corpo.max_tokens);

/** Uma resposta de sucesso com uso declarado, no dialeto do provedor ativo. */
const respostaComUso = (texto, uso) => (GEMINI
  ? {
    candidates: [{ content: { parts: [{ text: texto }] }, finishReason: 'MAX_TOKENS' }],
    usageMetadata: { promptTokenCount: uso.prompt_tokens, candidatesTokenCount: uso.completion_tokens },
  }
  : {
    choices: [{ message: { content: texto }, finish_reason: 'length' }],
    usage: uso,
  });

const wf = JSON.parse(readFileSync(new URL('../workflow.diagnostico-ia.json', import.meta.url), 'utf8'));
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

test('a chamada é mínima de verdade: teto de saída 1, e sem schema', async () => {
  const out = await run('Montar Chamada Minima', { json: {} });
  assert.equal(tetoDoCorpo(out.json.ia_body), 1,
    'o teto de saída é RESERVA de TPM — 1 é o que faz esta chamada passar com o balde cheio');
  // SEM SCHEMA é parte de ser mínima: prender a saída a um JSON Schema faria a
  // chamada de diagnóstico deixar de ser a mais barata possível.
  const temSchema = GEMINI
    ? !!out.json.ia_body.generationConfig.responseSchema
    : !!out.json.ia_body.response_format;
  assert.equal(temSchema, false);
});

test('o nó de IA tem neverError: sem isso o corpo da causa nunca chega', () => {
  const n = wf.nodes.find((x) => x.name === 'IA (1 token)');
  assert.equal(n.parameters.options.response.response.neverError, true);
  assert.equal(n.credentials.httpHeaderAuth.name, PROV.credencial,
    'tem de usar a MESMA credencial da ingestão — diagnosticar outra chave responde a pergunta errada');
  // E o MESMO modelo: limite e disponibilidade são por modelo na maioria dos
  // provedores, então diagnosticar outro responderia a pergunta errada do mesmo
  // jeito que diagnosticar outra chave.
  if (GEMINI) assert.match(n.parameters.url, new RegExp(`models/${MODELO_EXTRACAO}:`));
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
  const resp = { json: respostaComUso('ok', { prompt_tokens: 8, completion_tokens: 1 }) };
  const out = await run('Veredito', resp);
  assert.equal(out.json.passou, true);
  assert.match(out.json.veredito, /a chamada de 1 token PASSOU/);
  assert.match(out.json.veredito, /credito e teto de gasto estao/);
  assert.match(out.json.veredito, /DESCARTADOS/);
  // O custo é MEDIDO do uso que o provedor devolveu — inclusive quando o uso vem
  // no formato dele (`usageMetadata`), que é o que a fronteira traduz.
  const p = PRECO_USD_POR_MILHAO[MODELO_EXTRACAO];
  const esperado = ((8 * p.entrada + 1 * p.saida) / 1e6).toFixed(6);
  assert.match(out.json.veredito, new RegExp(`Custo desta chamada: US\\$ ${esperado}`));
});

test('Veredito: a aritmética da cadência e o teto de gasto aparecem sempre', async () => {
  for (const resp of [{ json: respostaComUso('ok', { prompt_tokens: 1, completion_tokens: 1 }) },
    { json: { error: { status: 429, message: 'x' } } }]) {
    const out = await run('Veredito', resp);
    assert.match(out.json.veredito, /CADENCIA CONFIGURADA/);
    assert.match(out.json.veredito, /max_tokens e RESERVA de TPM/);
    assert.match(out.json.veredito, /TETO DE GASTO POR EXECUCAO/);
    // o dono precisa saber que o teto do provedor tem de ficar ACIMA do do código
    assert.match(out.json.veredito, /deve ficar ACIMA disso \(US\$ 5\)/);
  }
});
