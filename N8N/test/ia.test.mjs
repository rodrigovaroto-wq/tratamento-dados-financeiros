// A CLASSIFICAÇÃO POR CONTEÚDO — o domínio aqui, o dialeto no fim do arquivo.
//
// O schema, a taxonomia e a normalização da saída não mudam com o provedor: é o
// que este arquivo prova. Os dois últimos testes fecham a outra metade — que a
// MESMA resposta, escrita no dialeto de cada provedor, é lida igual.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
  buildClassificationRequest,
  parseClassificationResponse,
  classificationSchema,
  codigosConhecidos,
} from '../lib/ia.mjs';
import {
  PROVEDORES, schemaDoProvedor, modelosDoCatalogo, modelosParecidos,
} from '../lib/provedor.mjs';

/** A mesma resposta, escrita como cada provedor a escreveria. */
function respostaDe(prov, objeto) {
  const texto = JSON.stringify(objeto);
  return prov.dialeto === 'gemini'
    ? { candidates: [{ content: { parts: [{ text: texto }] }, finishReason: 'STOP' }] }
    : { choices: [{ message: { content: texto }, finish_reason: 'stop' }] };
}

test('schema é estrito e cobre o Kit Básico + escape', () => {
  const s = classificationSchema();
  assert.equal(s.strict, true);
  assert.equal(s.schema.additionalProperties, false);
  const enumTipos = s.schema.properties.tipo_taxonomia.enum;
  assert.ok(enumTipos.includes('DRE'));
  assert.ok(enumTipos.includes('DESCONHECIDO'));
  // Lote 7377 (02/09): HEADCOUNT já existia na taxonomia (seed 0002) mas
  // faltava em `ALIASES`, e `codigosConhecidos()` monta o enum SÓ a partir de
  // KIT_BASICO + ALIASES — não da tabela inteira. Um código ausente aqui é um
  // código que a IA está PROIBIDA de devolver (schema estrito), qualquer que
  // seja a confiança: por isso `28_Folha_de_Pagamento` nunca virava HEADCOUNT
  // mesmo com 0,9 de confiança. Sem este alias o assert abaixo reprova.
  assert.ok(enumTipos.includes('HEADCOUNT'));
});

test('codigosConhecidos não tem duplicatas', () => {
  const c = codigosConhecidos();
  assert.equal(new Set(c).size, c.length);
});

test('buildClassificationRequest prende a saída ao schema e zera a temperatura', () => {
  // Os dois pedidos são o mesmo fato em dois dialetos, e nenhum dos dois é
  // opcional: sem o schema a saída é texto livre (parsing frágil, que este
  // sistema não tem), e sem temperatura 0 o mesmo documento classifica diferente
  // a cada rodada — o que arruinaria a rotulagem cega do golden set (0130).
  for (const prov of Object.values(PROVEDORES)) {
    const req = buildClassificationRequest({
      nomeOriginal: 'doc.pdf',
      conteudo: { type: 'image_url', image_url: { url: 'data:image/png;base64,AAA' } },
      model: 'modelo-de-teste',
      prov,
    });
    assert.equal(req.method, 'POST');
    if (prov.dialeto === 'gemini') {
      assert.equal(req.body.generationConfig.temperature, 0, prov.id);
      assert.equal(req.body.generationConfig.responseMimeType, 'application/json', prov.id);
      assert.equal(req.body.generationConfig.responseSchema.type, 'OBJECT', prov.id);
      assert.equal(req.body.contents.length, 1, prov.id);
    } else {
      assert.equal(req.body.temperature, 0, prov.id);
      assert.equal(req.body.response_format.type, 'json_schema', prov.id);
      assert.equal(req.body.messages.length, 2, prov.id);
    }
  }
});

test('o schema traduzido para o Google mantém TODAS as propriedades e a ordem', () => {
  // A tradução é mecânica de propósito: ela reescreve a forma e não mexe no
  // conteúdo. Se um dia alguém acrescentar um campo ao schema da lib e ele não
  // aparecer no dialeto do provedor ativo, a IA simplesmente nunca o devolve — e
  // um campo que nunca vem é indistinguível de um campo que veio vazio.
  const original = classificationSchema();
  const g = schemaDoProvedor(PROVEDORES.google, original);
  assert.deepEqual(Object.keys(g.properties), Object.keys(original.schema.properties));
  assert.deepEqual(g.propertyOrdering, Object.keys(original.schema.properties));
  assert.deepEqual(g.required, original.schema.required);
  // O nulo muda de forma: `type:['string','null']` não existe no dialeto do
  // Google, e mandá-lo assim é 400 na chamada inteira.
  assert.equal(g.properties.entidade.type, 'STRING');
  assert.equal(g.properties.entidade.nullable, true);
  assert.equal(g.properties.tipo_taxonomia.nullable, undefined);
  assert.ok(g.properties.tipo_taxonomia.enum.includes('DRE'));
  // E o que o Google não conhece não pode viajar junto.
  const texto = JSON.stringify(g);
  for (const proibido of ['additionalProperties', 'strict', 'minimum', 'maximum']) {
    assert.ok(!texto.includes(proibido), `campo "${proibido}" não existe no dialeto do Google`);
  }
});

test('parseClassificationResponse normaliza para o formato do classificador, em todo provedor', () => {
  const saida = {
    tipo_taxonomia: 'DRE',
    entidade: 'Empresa A Ltda',
    periodo_tipo: 'anual',
    periodo_referencia: '12M25',
    assinado: true,
    confianca: 0.88,
    justificativa: 'Cabeçalho "Demonstração de Resultado" e ano 2025.',
  };
  for (const prov of Object.values(PROVEDORES)) {
    const r = parseClassificationResponse(respostaDe(prov, saida), prov);
    assert.equal(r.tipo_taxonomia, 'DRE', prov.id);
    assert.equal(r.entidade, 'Empresa A Ltda', prov.id);
    assert.deepEqual(r.periodo, { tipo: 'anual', referencia: '12M25' }, prov.id);
    assert.equal(r.assinado, true, prov.id);
    assert.equal(r.confianca, 0.88, prov.id);
    // `openai_conteudo` é valor de DADO, não nome de fornecedor: ele está em
    // linha de produção e em CHECK de migration (0033), e trocá-lo por causa do
    // provedor seria reescrever histórico para arrumar um nome.
    assert.equal(r.fonte, 'openai_conteudo', prov.id);
  }
});

test('o Google pode repartir a saída em várias partes, e o JSON tem de sair inteiro', () => {
  // Ler só `parts[0]` daria um JSON cortado ao meio — indistinguível de
  // truncamento por teto de tokens, e mandaria a próxima sessão investigar o
  // limite de saída quando o defeito estava na leitura.
  const inteiro = JSON.stringify({
    tipo_taxonomia: 'BALANCO', entidade: null, periodo_tipo: 'anual',
    periodo_referencia: '2025', assinado: null, confianca: 0.7, justificativa: 'x',
  });
  const meio = Math.floor(inteiro.length / 2);
  const r = parseClassificationResponse({
    candidates: [{ content: { parts: [{ text: inteiro.slice(0, meio) }, { text: inteiro.slice(meio) }] } }],
  }, PROVEDORES.google);
  assert.equal(r.tipo_taxonomia, 'BALANCO');
  assert.equal(r.confianca, 0.7);
});

test('DESCONHECIDO vira tipo null, em todo provedor', () => {
  for (const prov of Object.values(PROVEDORES)) {
    const r = parseClassificationResponse(respostaDe(prov, {
      tipo_taxonomia: 'DESCONHECIDO', entidade: null, periodo_tipo: 'desconhecido',
      periodo_referencia: null, assinado: null, confianca: 0.2, justificativa: 'ilegível',
    }), prov);
    assert.equal(r.tipo_taxonomia, null, prov.id);
    assert.equal(r.periodo, null, prov.id);
  }
});

test('resposta sem conteúdo lança erro que NOMEIA o provedor', () => {
  // Nomear quem não respondeu é o que separa "a rede caiu" de "a chave do
  // provedor novo não foi criada" — as duas chegam aqui como resposta vazia.
  assert.throws(() => parseClassificationResponse({ choices: [] }, PROVEDORES.openai), /OpenAI.*sem conteúdo/);
  assert.throws(() => parseClassificationResponse({ candidates: [] }, PROVEDORES.google), /Gemini.*sem conteúdo/);
});

// ===========================================================================
// O CATÁLOGO DE MODELOS — a única checagem que nenhum teste pode fazer sozinho
// ===========================================================================
//
// O id do modelo é a única coisa deste sistema que não se prova offline: ele é
// uma string que só a API do provedor valida, e errá-la por um sufixo faz TODA
// chamada do lote voltar 404. O que DÁ para travar aqui é a leitura do catálogo
// — porque as duas respostas têm formas diferentes, e ler a do Google errado
// produziria um "seu modelo não existe" falso, que é pior que não checar.

test('modelosDoCatalogo lê as duas formas de resposta, e tira o prefixo do Google', () => {
  assert.deepEqual(
    modelosDoCatalogo(PROVEDORES.openai, { data: [{ id: 'gpt-4o' }, { id: 'gpt-4o-mini' }] }),
    ['gpt-4o', 'gpt-4o-mini'],
  );
  // `models/` é prefixo do RECURSO, não parte do id. Mandá-lo de volta no lugar
  // do id monta uma URL com `models/models/x` — 404 causado pela própria
  // checagem que existe para evitar 404.
  assert.deepEqual(
    modelosDoCatalogo(PROVEDORES.google, {
      models: [{ name: 'models/gemini-3.5-flash-lite' }, { name: 'models/text-embedding-004' }],
    }),
    ['gemini-3.5-flash-lite', 'text-embedding-004'],
  );
  // Resposta inesperada vira lista VAZIA, nunca exceção: "não consegui listar"
  // e "listei e seu modelo não está lá" pedem ações diferentes, e quem chama
  // precisa poder distinguir os dois.
  for (const lixo of [null, undefined, {}, { models: 'x' }, { data: 7 }]) {
    assert.deepEqual(modelosDoCatalogo(PROVEDORES.google, lixo), []);
    assert.deepEqual(modelosDoCatalogo(PROVEDORES.openai, lixo), []);
  }
});

test('modelosParecidos põe na frente o que erra só no sufixo', () => {
  // O erro real num id de modelo é sufixo de versão ou geração trocada — por
  // isso a semelhança é por PREFIXO comum. Distância de edição traria vizinhos
  // que não têm nada a ver, e uma sugestão ruim é pior que nenhuma.
  const disponiveis = ['text-embedding-004', 'gemini-2.5-flash', 'gemini-3.5-flash-lite-002', 'gemini-3.5-pro'];
  const p = modelosParecidos('gemini-3.5-flash-lite', disponiveis, 2);
  assert.equal(p[0], 'gemini-3.5-flash-lite-002');
  assert.equal(p.length, 2);
  assert.deepEqual(modelosParecidos('x', [], 5), [], 'catálogo vazio não inventa sugestão');
});

test('todo provedor do catálogo sabe dizer ONDE listar os seus modelos', () => {
  // Sem `catalogo`, a checagem mais barata do sistema simplesmente não existe
  // para aquele provedor — e o defeito só apareceria no dia da troca.
  for (const [id, prov] of Object.entries(PROVEDORES)) {
    assert.match(prov.catalogo, /^https:\/\//, `provedor "${id}" sem URL de catálogo`);
    assert.ok(prov.console, `provedor "${id}" sem console para o dono abrir`);
  }
});
