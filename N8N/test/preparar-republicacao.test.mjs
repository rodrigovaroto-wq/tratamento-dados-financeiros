import { test } from 'node:test';
import assert from 'node:assert/strict';
import { prepararRepublicacao, credenciaisPendentes } from '../preparar-republicacao.mjs';

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

test('o id da credencial vem do VIVO; o REPLACE do repositório só fica quando não há outro', () => {
  const nos = porNome(prepararRepublicacao(VIVO, REPO));
  assert.deepEqual(nos['IA Extrair'].credentials.httpHeaderAuth,
    { id: 'FVVausmZHGZNICDP', name: 'Gemini da conta' },
    'publicar o REPLACE derruba o nó com "Credential with ID REPLACE does not exist"');
  assert.equal(nos['Upload Storage'].credentials.httpHeaderAuth.id, 'REPLACE',
    'sem id na instalação, o placeholder é o que sobra — e o relatório avisa');
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

test('o relatório aponta a credencial que ainda vai falhar, e distingue nó ligado de desligado', () => {
  const pend = credenciaisPendentes(prepararRepublicacao(VIVO, REPO));
  assert.equal(pend.length, 1);
  assert.equal(pend[0].no, 'Upload Storage');
  assert.equal(pend[0].desabilitado, true, 'nó desabilitado com REPLACE não impede a rodada');

  // E com o mesmo nó HABILITADO, ele passa a ser o que derruba o lote.
  const ligado = JSON.parse(JSON.stringify(REPO));
  delete ligado.nodes[2].disabled;
  const pend2 = credenciaisPendentes(prepararRepublicacao(VIVO, ligado));
  assert.equal(pend2[0].desabilitado, false);
});
