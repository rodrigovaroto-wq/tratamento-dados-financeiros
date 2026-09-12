import { test } from 'node:test';
import assert from 'node:assert/strict';
import { prepararRepublicacao, credenciaisPendentes, idsDeCredencialDoAmbiente } from '../preparar-republicacao.mjs';

// A FUSÃO QUE DEVOLVE O COMPORTAMENTO SEM PISAR NA INSTALAÇÃO.
//
// Duas republicações seguidas perderam o mesmo tipo de coisa, e a segunda
// perdeu a pior: o `multipleFiles: true` do campo de arquivo do formulário —
// sem ele, o intake aceita UM documento por vez, e os dois books que faltam têm
// 38 e 190. Cada caso abaixo é uma dessas perdas, ou uma coisa da instalação
// que a correção não pode atropelar.

const REPO = {
  name: 'Oria — E1',
  nodes: [
    { name: 'Intake (Form)', type: 'n8n-nodes-base.formTrigger', typeVersion: 2.2,
      parameters: { formTitle: 'Intake', formFields: { values: [
        { fieldLabel: 'Arquivos', fieldType: 'file', multipleFiles: true, requiredField: true },
      ] } } },
    { name: 'IA Extrair', type: 'n8n-nodes-base.httpRequest', typeVersion: 4.2,
      parameters: { method: 'POST' }, onError: 'continueRegularOutput', retryOnFail: true, maxTries: 6,
      credentials: { httpHeaderAuth: { id: 'REPLACE', name: 'Google AI (Gemini)' } } },
    { name: 'Upload Storage', type: 'n8n-nodes-base.httpRequest', typeVersion: 4.2,
      parameters: { method: 'POST' }, disabled: true,
      credentials: { httpHeaderAuth: { id: 'REPLACE', name: 'Supabase Service (Header Auth)' } } },
  ],
  connections: { 'Intake (Form)': { main: [[{ node: 'IA Extrair', type: 'main', index: 0 }]] } },
  settings: { executionOrder: 'v1' },
};

// O publicado como ele voltou da republicação de 27/08: sem os campos de
// comportamento, sem o `multipleFiles`, mas com os ids e o `path` da instalação
// e com o `errorWorkflow` que o dono ligou à mão.
const VIVO = {
  name: 'Oria — E1',
  nodes: [
    { id: 'no-1', name: 'Intake (Form)', type: 'n8n-nodes-base.formTrigger', typeVersion: 2.2,
      webhookId: 'wh-1',
      parameters: { formTitle: 'Intake', path: 'bea41a5a-3c43-4fc6-915f-0d74d3bcf25e', formFields: { values: [
        { fieldLabel: 'Arquivos', fieldType: 'file', requiredField: true },
      ] } } },
    { id: 'no-2', name: 'IA Extrair', type: 'n8n-nodes-base.httpRequest', typeVersion: 4.2,
      parameters: { method: 'POST' },
      credentials: { httpHeaderAuth: { id: 'FVVausmZHGZNICDP', name: 'Gemini da conta' } } },
    { id: 'no-3', name: 'Upload Storage', type: 'n8n-nodes-base.httpRequest', typeVersion: 4.2,
      parameters: { method: 'POST' }, disabled: true,
      credentials: { httpHeaderAuth: { id: 'REPLACE', name: 'Supabase Service (Header Auth)' } } },
  ],
  connections: {},
  settings: { executionOrder: 'v1', errorWorkflow: '59DPz4s2d3DHSR9M', callerPolicy: 'workflowsFromSameOwner' },
};

const porNome = (w) => Object.fromEntries(w.nodes.map((n) => [n.name, n]));

test('o COMPORTAMENTO volta do repositório — é o que as duas republicações perderam', () => {
  const n = porNome(prepararRepublicacao(VIVO, REPO))['IA Extrair'];
  assert.equal(n.onError, 'continueRegularOutput');
  assert.equal(n.retryOnFail, true);
  assert.equal(n.maxTries, 6);
});

test('o `multipleFiles` do campo de arquivo volta — sem ele o intake aceita UM documento', () => {
  const n = porNome(prepararRepublicacao(VIVO, REPO))['Intake (Form)'];
  assert.equal(n.parameters.formFields.values[0].multipleFiles, true,
    'o formulário voltaria a aceitar um arquivo por vez, e os books têm 38 e 190');
});

test('o `path` do formulário é DA INSTALAÇÃO e não pode ser sobrescrito', () => {
  const n = porNome(prepararRepublicacao(VIVO, REPO))['Intake (Form)'];
  assert.equal(n.parameters.path, 'bea41a5a-3c43-4fc6-915f-0d74d3bcf25e',
    'sobrescrever o path troca a URL pública do intake — já se perdeu uma vez assim');
  assert.equal(n.webhookId, 'wh-1');
  assert.equal(n.id, 'no-1', 'o id do nó vem do vivo, senão o n8n trata o nó como novo');
});

test('o id da credencial vem do VIVO; o REPLACE do repositório só fica no nó LIGADO sem outro id', () => {
  const nos = porNome(prepararRepublicacao(VIVO, REPO));
  assert.deepEqual(nos['IA Extrair'].credentials.httpHeaderAuth,
    { id: 'FVVausmZHGZNICDP', name: 'Gemini da conta' },
    'publicar o REPLACE derruba o nó com "Credential with ID REPLACE does not exist"');
  assert.equal(nos['Upload Storage'].credentials, undefined,
    'nó DESABILITADO sem id na instalação sai SEM credencial — o REPLACE barraria o arquivo inteiro sem impedir falha nenhuma');
});

test('as `settings` da instalação sobrevivem — é onde mora o errorWorkflow ligado à mão', () => {
  const p = prepararRepublicacao(VIVO, REPO);
  assert.equal(p.settings.errorWorkflow, '59DPz4s2d3DHSR9M',
    'sobrescrever as settings desligaria o Error Workflow em silêncio — o mesmo defeito, em outro campo');
  assert.equal(p.settings.executionOrder, 'v1');
});

test('as CONEXÕES vêm do repositório — um nó certo ligado errado não aparece em nó nenhum', () => {
  const p = prepararRepublicacao(VIVO, REPO);
  assert.deepEqual(p.connections, REPO.connections);
});

test('o relatório só aponta credencial REPLACE em nó LIGADO — o desligado nem pendente fica', () => {
  const pend = credenciaisPendentes(prepararRepublicacao(VIVO, REPO));
  assert.equal(pend.length, 0,
    'a única credencial sem id é de um nó desabilitado — ela some do JSON em vez de travar a rodada');

  // Com o mesmo nó HABILITADO, o REPLACE volta a existir — e é o portão que
  // derruba a publicação, não este relatório.
  const ligado = JSON.parse(JSON.stringify(REPO));
  delete ligado.nodes[2].disabled;
  const pend2 = credenciaisPendentes(prepararRepublicacao(VIVO, ligado));
  assert.equal(pend2.length, 1);
  assert.equal(pend2[0].no, 'Upload Storage');
  assert.equal(pend2[0].desabilitado, false, 'nó ligado com REPLACE é o que a trava do republicar.sh segura');
});

// ---------------------------------------------------------------------------
// IDs DE CREDENCIAL VINDOS DE FORA — o desbloqueio da action do GitHub.
// ---------------------------------------------------------------------------
//
// MEDIDO EM PRODUÇÃO, três execuções seguidas (11/09/2026, runs 1-3 de
// `.github/workflows/republicar.yml`): a action abortou no passo 4 com
// "sobraram 2 ocorrência(s) de REPLACE" — `IA Classificar` e `IA Extrair`.
//
// A divisão é por TIPO de credencial, não por nó, e é o que aponta a causa:
// as ONZE credenciais `postgres` do workflow resolveram TODAS pelo vivo; as
// TRÊS `httpHeaderAuth` não resolveram NENHUMA. A API pública do n8n não
// devolve a `httpHeaderAuth` desses nós, então não existe id a ler.
//
// A trava que abortou estava certa (publicar REPLACE em nó ligado quebra a
// credencial em produção). O que faltava era o id chegar sem passar pelo vivo.

const REPO_OPENAI = {
  ...REPO,
  nodes: [
    { name: 'IA Classificar', type: 'n8n-nodes-base.httpRequest', typeVersion: 4.2,
      parameters: { method: 'POST' },
      credentials: { httpHeaderAuth: { id: 'REPLACE', name: 'OpenAI API' } } },
    { name: 'IA Extrair', type: 'n8n-nodes-base.httpRequest', typeVersion: 4.2,
      parameters: { method: 'POST' },
      credentials: { httpHeaderAuth: { id: 'REPLACE', name: 'OpenAI API' } } },
  ],
};
// O vivo como a API o devolve: os nós existem, mas SEM a httpHeaderAuth.
const VIVO_SEM_HEADER_AUTH = {
  ...VIVO,
  nodes: [
    { id: 'no-c', name: 'IA Classificar', type: 'n8n-nodes-base.httpRequest', typeVersion: 4.2, parameters: {} },
    { id: 'no-e', name: 'IA Extrair', type: 'n8n-nodes-base.httpRequest', typeVersion: 4.2, parameters: {} },
  ],
};

test('MEDIDO: o cenário das 3 falhas da action — id de fora resolve o que o vivo não conta', () => {
  const semMapa = prepararRepublicacao(VIVO_SEM_HEADER_AUTH, REPO_OPENAI);
  assert.equal(credenciaisPendentes(semMapa).length, 2,
    'sem o mapa, os DOIS nós ficam em REPLACE — é exatamente o que abortou a action 3 vezes');

  const comMapa = prepararRepublicacao(VIVO_SEM_HEADER_AUTH, REPO_OPENAI,
    { idsPorNome: { 'OpenAI API': 'aBc123' } });
  assert.deepEqual(credenciaisPendentes(comMapa), [], 'com o mapa, nada fica pendente');
  const n = porNome(comMapa);
  assert.equal(n['IA Classificar'].credentials.httpHeaderAuth.id, 'aBc123');
  assert.equal(n['IA Extrair'].credentials.httpHeaderAuth.id, 'aBc123',
    'UMA entrada no mapa serve os dois nós — a chave é o nome da credencial, não o nó');
  assert.equal(n['IA Extrair'].credentials.httpHeaderAuth.name, 'OpenAI API');
});

test('o VIVO ganha do mapa — um mapa velho não pode sobrescrever a credencial publicada', () => {
  // A precedência importa: ao contrário, um id desatualizado no secret trocaria
  // em silêncio a credencial certa por uma que não existe mais, e o sintoma
  // apareceria só na próxima rodada.
  const pronto = prepararRepublicacao(VIVO, REPO, { idsPorNome: { 'Google AI (Gemini)': 'id-velho-do-secret' } });
  assert.equal(porNome(pronto)['IA Extrair'].credentials.httpHeaderAuth.id, 'FVVausmZHGZNICDP',
    'quem está publicado é a verdade sobre a instalação; o mapa é só a queda');
});

test('o mapa NÃO desarma a trava: REPLACE ou vazio no mapa é ausência, não resposta', () => {
  for (const idRuim of ['REPLACE', '', '   ']) {
    const pronto = prepararRepublicacao(VIVO_SEM_HEADER_AUTH, REPO_OPENAI,
      { idsPorNome: idsDeCredencialDoAmbiente({ N8N_CRED_IDS: JSON.stringify({ 'OpenAI API': idRuim }) }) });
    assert.equal(credenciaisPendentes(pronto).length, 2,
      `id "${idRuim}" no mapa não pode passar por resolvido — desarmaria o portão do republicar.sh`);
  }
});

test('idsDeCredencialDoAmbiente: ausente é {}, JSON quebrado FALA o que fazer', () => {
  assert.deepEqual(idsDeCredencialDoAmbiente({}), {}, 'sem o secret, segue o comportamento de sempre');
  assert.deepEqual(idsDeCredencialDoAmbiente({ N8N_CRED_IDS: '   ' }), {});
  assert.deepEqual(idsDeCredencialDoAmbiente({ N8N_CRED_IDS: '{"OpenAI API":"x1"}' }), { 'OpenAI API': 'x1' });
  // Secret mal colado é o erro mais provável deste caminho, e ele tem de dizer
  // o formato esperado em vez de estourar um SyntaxError cru do JSON.
  assert.throws(() => idsDeCredencialDoAmbiente({ N8N_CRED_IDS: 'OpenAI API=x1' }), /não é JSON válido/);
  assert.throws(() => idsDeCredencialDoAmbiente({ N8N_CRED_IDS: '["x1"]' }), /precisa ser um OBJETO/);
});
