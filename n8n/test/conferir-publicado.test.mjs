import { test } from 'node:test';
import assert from 'node:assert/strict';
import { conferir } from '../conferir-publicado.mjs';

// O CONFERIDOR DO QUE ESTÁ PUBLICADO — e por que ele precisa de teste próprio.
//
// Ele nasceu de uma conferência que passou verde estando errada: em 26/08/2026
// a republicação foi declarada "33 de 33 nós byte a byte iguais" comparando
// `parameters`, e o que tinha se perdido morava fora de `parameters` —
// `onError` em 22 nós, `retryOnFail`/`maxTries` em 10, e o `disabled` do
// `Upload Storage`, que voltou a executar com credencial `REPLACE` e derrubou o
// primeiro lote no primeiro nó.
//
// Um conferidor com ponto cego é pior que nenhum: ele produz a frase "está
// igual" com autoridade. Então cada coisa que ele tem de ver, e cada coisa que
// ele tem de IGNORAR, é um teste.

const REPO = {
  nodes: [
    { name: 'Intake (Form)', type: 'n8n-nodes-base.formTrigger', typeVersion: 2.2,
      parameters: { formTitle: 'Intake' } },
    { name: 'IA Extrair', type: 'n8n-nodes-base.httpRequest', typeVersion: 4.2,
      parameters: { method: 'POST' }, onError: 'continueRegularOutput', retryOnFail: true, maxTries: 6,
      credentials: { httpHeaderAuth: { id: 'REPLACE', name: 'Google AI (Gemini)' } } },
    { name: 'Upload Storage', type: 'n8n-nodes-base.httpRequest', typeVersion: 4.2,
      parameters: { method: 'POST' }, disabled: true,
      credentials: { httpHeaderAuth: { id: 'REPLACE', name: 'Supabase Service (Header Auth)' } } },
  ],
  connections: { 'Intake (Form)': { main: [[{ node: 'IA Extrair', type: 'main', index: 0 }]] } },
};

// O publicado de um sistema SAUDÁVEL: mesmos nós, com os ids e nomes de
// credencial DA INSTALAÇÃO, e com o `path` que o n8n atribuiu ao formulário.
function publicadoSaudavel() {
  return {
    nodes: [
      { name: 'Intake (Form)', type: 'n8n-nodes-base.formTrigger', typeVersion: 2.2,
        parameters: { formTitle: 'Intake', path: 'bea41a5a-3c43-4fc6-915f-0d74d3bcf25e' } },
      { name: 'IA Extrair', type: 'n8n-nodes-base.httpRequest', typeVersion: 4.2,
        parameters: { method: 'POST' }, onError: 'continueRegularOutput', retryOnFail: true, maxTries: 6,
        credentials: { httpHeaderAuth: { id: 'FVVausmZHGZNICDP', name: 'Google AI (Gemini)' } } },
      { name: 'Upload Storage', type: 'n8n-nodes-base.httpRequest', typeVersion: 4.2,
        parameters: { method: 'POST' }, disabled: true,
        credentials: { httpHeaderAuth: { id: 'REPLACE', name: 'Supabase Service (Header Auth)' } } },
    ],
    connections: JSON.parse(JSON.stringify(REPO.connections)),
  };
}

const campos = (achados) => achados.map((a) => `${a.no}.${a.campo}`);

test('publicação saudável: nenhuma divergência', () => {
  assert.deepEqual(conferir(publicadoSaudavel(), REPO), []);
});

test('o id e o nome da credencial são DA INSTALAÇÃO e não viram divergência', () => {
  const vivo = publicadoSaudavel();
  vivo.nodes[1].credentials.httpHeaderAuth = { id: 'outro-id-qualquer', name: 'Gemini da conta nova' };
  assert.deepEqual(conferir(vivo, REPO), [],
    'o conferidor passou a cobrar um dado que não pertence ao repositório');
});

test('o `path` do formulário é atribuído pelo n8n e não vira divergência', () => {
  const vivo = publicadoSaudavel();
  vivo.nodes[0].parameters.path = 'outro-uuid-porque-o-n8n-quis';
  assert.deepEqual(conferir(vivo, REPO), [],
    'sobrescrever o path troca a URL pública do intake — o conferidor não pode empurrar para isso');
});

// ---------------------------------------------------------------------------
// O QUE ELE TEM DE PEGAR — cada caso é uma perda real da republicação de 26/08
// ---------------------------------------------------------------------------

test('perder o onError vira divergência — a rede de proteção some em silêncio', () => {
  const vivo = publicadoSaudavel();
  delete vivo.nodes[1].onError;
  assert.deepEqual(campos(conferir(vivo, REPO)), ['IA Extrair.onError']);
});

test('perder retryOnFail/maxTries vira divergência', () => {
  const vivo = publicadoSaudavel();
  delete vivo.nodes[1].retryOnFail;
  delete vivo.nodes[1].maxTries;
  assert.deepEqual(campos(conferir(vivo, REPO)), ['IA Extrair.retryOnFail', 'IA Extrair.maxTries']);
});

test('perder o `disabled` vira divergência — foi assim que o Upload Storage voltou a rodar', () => {
  const vivo = publicadoSaudavel();
  delete vivo.nodes[2].disabled;
  // Duas coisas ao mesmo tempo, e as duas verdadeiras: o nó deixou de estar
  // desabilitado, E agora ele é um nó HABILITADO com o placeholder do
  // repositório na credencial — que é a falha que o dono viu na tela.
  assert.deepEqual(campos(conferir(vivo, REPO)),
    ['Upload Storage.disabled', 'Upload Storage.credentials.httpHeaderAuth.id']);
});

test('o `REPLACE` do repositório num nó HABILITADO é divergência; num desabilitado, não', () => {
  const vivo = publicadoSaudavel();
  vivo.nodes[1].credentials.httpHeaderAuth = { id: 'REPLACE', name: 'Google AI (Gemini)' };
  assert.deepEqual(campos(conferir(vivo, REPO)), ['IA Extrair.credentials.httpHeaderAuth.id']);
  // e o Upload Storage, desabilitado com REPLACE, continua sem acusar nada.
});

test('nó a mais, nó a menos e conexão diferente também são divergência', () => {
  const semNo = publicadoSaudavel();
  semNo.nodes.splice(1, 1);
  assert.ok(campos(conferir(semNo, REPO)).includes('IA Extrair.(o nó)'));

  const aMais = publicadoSaudavel();
  aMais.nodes.push({ name: 'Alguém Mexeu Aqui', type: 'n8n-nodes-base.noOp', typeVersion: 1, parameters: {} });
  assert.ok(campos(conferir(aMais, REPO)).includes('Alguém Mexeu Aqui.(o nó)'));

  const religado = publicadoSaudavel();
  religado.connections['Intake (Form)'].main[0][0].node = 'Upload Storage';
  assert.ok(campos(conferir(religado, REPO)).includes('(o workflow).connections'),
    'um nó certo ligado errado não aparece em nenhuma comparação de nó');
});

test('parâmetro diferente continua sendo divergência — o conferidor de 26/08 não regrediu', () => {
  const vivo = publicadoSaudavel();
  vivo.nodes[1].parameters.method = 'GET';
  assert.deepEqual(campos(conferir(vivo, REPO)), ['IA Extrair.parameters']);
});
