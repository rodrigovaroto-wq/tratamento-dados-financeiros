// Simula os nós Code do workflow de DIAGNÓSTICO executando o código REAL do JSON
// gerado — mesmo padrão de workflow-sim.test.mjs. Testar só a lib deixaria o nó
// livre para divergir, que é a classe de bug que este repositório já teve duas
// vezes.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { diagnosticarErroApi } from '../lib/extract.mjs';
import { provedor } from '../lib/provedor.mjs';
import { PRECO_USD_POR_MILHAO, MODELO_EXTRACAO, MODELO_CLASSIFICACAO } from '../lib/custo.mjs';
import { capacidadesDoModelo, modeloRaciocina } from '../lib/provedor.mjs';

const PROV = provedor();
const GEMINI = PROV.dialeto === 'gemini';

/** O teto de saída do corpo montado, no dialeto do provedor ativo. */
// O NOME DO CAMPO DE TETO É DO MODELO, não do dialeto. A família GPT-5 recusa
// `max_tokens` e exige `max_completion_tokens`; o 4o aceita o antigo. Ler pelo
// nome fixo travava o MECANISMO (regra 3 do CLAUDE.md) e reprovaria numa troca
// de modelo que está correta. Lê-se pela capacidade DECLARADA, que é a mesma
// fonte que `montarCorpoIA` usa para escrever.
const tetoDoCorpo = (corpo) => (GEMINI
  ? corpo.generationConfig.maxOutputTokens
  : corpo[capacidadesDoModelo(corpo.model).tetoDeSaida]);

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

test('a chamada mínima NÃO pode raciocinar — senão o teto de 1 token vira a conta mais cara do sistema', async () => {
  // O DEFEITO QUE ISTO FECHA, achado ao revisar a própria troca de provedor em
  // 11/09/2026 (nenhuma suíte pegava; este teste é a suíte passando a pegar).
  //
  // O Luna raciocina e o default dele é `medium`. Token de raciocínio é cobrado
  // como SAÍDA e é gasto ANTES da primeira letra da resposta. Um teto de 1 token
  // com esforço médio devolve resposta VAZIA (cortada antes de escrever
  // qualquer coisa) e cobra centenas ou milhares de tokens — a chamada feita
  // para ser a mais barata do sistema viraria uma das mais caras, e o veredito
  // passaria a medir truncamento em vez de medir se a conta responde.
  //
  // A PRIMEIRA VERSÃO DESTE TESTE NASCEU VAZIA, e o protocolo de medição pegou:
  // ela aceitava `undefined` como se fosse seguro. Não é — ausência do campo é
  // exatamente o defeito, porque a API aplica o DEFAULT DO MODELO (`medium`)
  // quando ninguém manda nada. Num modelo que raciocina, o campo tem de estar
  // lá, escrito, valendo `none`; só em modelo que não raciocina a ausência é a
  // resposta certa (mandá-lo ali seria 400).
  const out = await run('Montar Chamada Minima', { json: {} });
  const esforco = out.json.ia_body.reasoning_effort;
  if (modeloRaciocina(MODELO_EXTRACAO)) {
    assert.equal(esforco, 'none',
      `o modelo "${MODELO_EXTRACAO}" raciocina, então a chamada mínima PRECISA de `
      + `reasoning_effort:"none" explícito — veio ${JSON.stringify(esforco)}, e o `
      + 'default do modelo (medium) devolve vazio e cobra caro contra um teto de 1 token');
  } else {
    assert.equal(esforco, undefined,
      `o modelo "${MODELO_EXTRACAO}" não raciocina — mandar reasoning_effort é 400`);
  }
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

// ===========================================================================
// A CHECAGEM DO ID DO MODELO — e por que ela tem de estar AQUI, e não só no CLI
// ===========================================================================
//
// O id do modelo é a única coisa deste sistema que nenhum teste prova: é uma
// string que só a API do provedor valida, e errá-la faz TODA chamada do lote
// voltar 404. O script de terminal responde isso com `--modelos`.
//
// O dono NÃO USA TERMINAL, e disse isso com todas as letras ("não sei onde roda
// isso") — é o motivo de este workflow existir. Deixar a checagem só na versão
// de terminal seria pôr a resposta exatamente onde quem precisa dela não
// alcança, que é a forma mais silenciosa de um diagnóstico não diagnosticar.

const respostaDaLista = (ids) => (GEMINI
  ? { models: ids.map((id) => ({ name: `models/${id}` })) }
  : { data: ids.map((id) => ({ id })) });

const rodarVeredito = async (lista, resposta) => {
  const code = (nome) => {
    const n = wf.nodes.find((x) => x.name === nome);
    return n.parameters.jsCode;
  };
  const item = { json: resposta };
  const $input = { item, first: () => item, all: () => [item] };
  const $ = (ref) => {
    if (ref !== 'Listar Modelos') throw new Error(`ref não mockada: ${ref}`);
    return { item: { json: lista }, first: () => ({ json: lista }) };
  };
  return new AsyncFunction('$input', '$', '$json', code('Veredito')).call({}, $input, $, item.json);
};

test('o GET do catálogo vem ANTES da chamada paga, e usa a mesma credencial', () => {
  const n = wf.nodes.find((x) => x.name === 'Listar Modelos');
  assert.equal(n.parameters.method, 'GET', 'listar não manda corpo e não gasta token');
  assert.equal(n.parameters.url, PROV.catalogo);
  assert.equal(n.credentials.httpHeaderAuth.name, PROV.credencial);
  // `neverError` pela mesma razão do nó pago: sem ele uma chave inválida vira
  // exceção e o veredito nunca chega a dizer o que houve.
  assert.equal(n.parameters.options.response.response.neverError, true);
  // A ORDEM importa: a checagem grátis vem primeiro, e é ela que explica um 404
  // da chamada seguinte. Invertida, o dono lê "404" e só depois descobre o porquê.
  assert.deepEqual(wf.connections['Rodar Diagnostico'].main[0][0].node, 'Listar Modelos');
  assert.deepEqual(wf.connections['Listar Modelos'].main[0][0].node, 'Montar Chamada Minima');
});

test('Veredito: quando o modelo configurado EXISTE, diz que o id está certo', async () => {
  const lista = respostaDaLista([MODELO_EXTRACAO, MODELO_CLASSIFICACAO, 'outro-qualquer']);
  const out = await rodarVeredito(lista, respostaComUso('ok', { prompt_tokens: 1, completion_tokens: 1 }));
  assert.match(out.json.veredito, /MODELOS DA CONTA/);
  assert.match(out.json.veredito, /O id do modelo esta certo/);
});

test('Veredito: modelo configurado que NÃO existe é nomeado, com os parecidos', async () => {
  // O caso que este trabalho inteiro existe para pegar: o id veio de uma lista
  // de marketing e a API chama a coisa por outro nome. Sem isto, o sintoma é
  // "todas as 57 chamadas deram 404" e a causa fica a uma pesquisa de distância.
  const lista = respostaDaLista([`${MODELO_EXTRACAO}-002`, 'text-embedding-004']);
  const out = await rodarVeredito(lista, respostaComUso('ok', { prompt_tokens: 1, completion_tokens: 1 }));
  assert.match(out.json.veredito, /PROBLEMA/);
  assert.match(out.json.veredito, new RegExp(MODELO_EXTRACAO.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')));
  assert.match(out.json.veredito, /Toda chamada do lote voltaria 404/);
  assert.match(out.json.veredito, new RegExp(`${MODELO_EXTRACAO.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}-002`),
    'tem de sugerir o que existe — "não existe" sozinho é meia informação');
});

test('Veredito: catálogo que não veio NÃO vira "modelo não existe"', async () => {
  // A distinção que decide a ação: "não consegui listar" (credencial do nó de
  // listagem) é outro problema de "listei e o seu modelo não está lá" (id
  // errado). Confundi-los mandaria o dono corrigir o arquivo errado.
  const out = await rodarVeredito({}, respostaComUso('ok', { prompt_tokens: 1, completion_tokens: 1 }));
  assert.match(out.json.veredito, /NAO FOI POSSIVEL LISTAR/);
  assert.ok(!/PROBLEMA/.test(out.json.veredito), 'sem lista, não se afirma nada sobre o id');
});
