// O QUE ESTÁ PUBLICADO É O QUE ESTÁ NO REPOSITÓRIO? — conferido campo a campo.
//
// POR QUE ESTE ARQUIVO EXISTE, e o preço de ele não ter existido antes. Em
// 26/08/2026 o workflow da ingestão foi republicado pela API REST e a
// conferência daquela sessão declarou "33 de 33 nós byte a byte iguais ao
// repositório". Era verdade — e insuficiente: ela comparava `parameters`, e
// TODA a configuração de falha de um nó do n8n mora FORA de `parameters`.
//
// O que a publicação tinha perdido, medido dois dias depois contra o workflow
// vivo: `onError: continueRegularOutput` em 22 nós, `retryOnFail`/`maxTries`
// em 10, e o `disabled: true` do `Upload Storage`. Os dois efeitos:
//
//   • o `Upload Storage` — um ramo lateral DESABILITADO desde 17/07/2026, com
//     URL de exemplo e credencial `REPLACE` — voltou a executar e derrubou o
//     primeiro lote no primeiro nó ("Credential with ID REPLACE does not
//     exist");
//   • e, pior porque é silencioso, TODA rede de proteção sumiu junto: uma falha
//     de provedor no `IA Extrair` (que tinha 6 tentativas) passa a matar o lote
//     inteiro em vez de repetir, e um PDF escaneado no `Extrair Texto` passa a
//     derrubar a execução em vez de seguir como imagem.
//
// A regra que sai disso: **espelho que compara só uma parte declara igualdade
// que não tem.** Este conferidor compara o nó INTEIRO — o que ele faz, como
// ele falha, e se ele está ligado.
//
//   # 1. no editor do n8n: … → Download, salva o JSON
//   node n8n/conferir-publicado.mjs ~/Downloads/workflow.json
//
//   # 2. ou, com acesso à API REST:
//   curl -s -H "X-N8N-API-KEY: $N8N_API_KEY" \
//     "$N8N_URL/api/v1/workflows/$ID" > /tmp/vivo.json
//   node n8n/conferir-publicado.mjs /tmp/vivo.json
//
// Sai com código 1 quando algo diverge, listando cada divergência com o nome do
// nó e o campo.
//
// O QUE ELE DELIBERADAMENTE NÃO COBRA, porque pertence à INSTALAÇÃO e não ao
// repositório — e cobrar seria um conferidor que grita todo dia e por isso
// deixa de ser lido:
//
//   • o `id` e o `name` da credencial. O repositório grava `REPLACE` e um nome
//     sugerido justamente para não guardar nada da instalação; quem publica
//     substitui pelos seus. O que SE cobra é o contrapositivo, que é o útil: um
//     nó HABILITADO com o `REPLACE` do repositório ainda no lugar não vai
//     rodar, e falha na primeira execução com "Credential with ID REPLACE does
//     not exist";
//   • o `path` do gatilho de formulário e o `webhookId`. Os dois são atribuídos
//     pelo n8n e sobrescrevê-los TROCA A URL PÚBLICA do intake — já se perdeu
//     uma vez assim;
//   • a `position` dos nós, que é do editor.
import { readFileSync, statSync } from 'node:fs';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const RAIZ = resolve(dirname(fileURLToPath(import.meta.url)), '..');

// Os campos de nó que MUDAM O COMPORTAMENTO e vivem fora de `parameters`.
// `position` e `id` ficam de fora de propósito: são do editor e da instalação.
export const CAMPOS_DE_COMPORTAMENTO = [
  'type', 'typeVersion', 'disabled', 'onError',
  'retryOnFail', 'maxTries', 'waitBetweenTries',
  'alwaysOutputData', 'executeOnce', 'notesInFlow',
];

// `path` é o endereço público do formulário e o n8n é quem o atribui — ele
// existe no publicado e não no repositório, e é assim que tem de ser.
const CAMPOS_DA_INSTALACAO = ['path'];
function semCamposDaInstalacao(parametros) {
  const copia = { ...parametros };
  for (const c of CAMPOS_DA_INSTALACAO) delete copia[c];
  return copia;
}

const iguais = (a, b) => JSON.stringify(a ?? null) === JSON.stringify(b ?? null);

/** Os nós que só existem de um lado — cada um vira um achado. */
function conferirPresenca(nosVivos, nosRepo) {
  const achados = [];
  for (const nome of nosRepo.keys()) {
    if (!nosVivos.has(nome)) achados.push({ no: nome, campo: '(o nó)', vivo: 'ausente', repo: 'presente' });
  }
  for (const nome of nosVivos.keys()) {
    if (!nosRepo.has(nome)) achados.push({ no: nome, campo: '(o nó)', vivo: 'presente', repo: 'ausente' });
  }
  return achados;
}

/** O que o nó FAZ e COMO ele falha — os campos que a republicação perdeu. */
function conferirComportamento(nome, oVivo, doRepo) {
  const achados = [];
  for (const campo of CAMPOS_DE_COMPORTAMENTO) {
    // `undefined` e ausência são a mesma coisa nos dois lados; o que não pode
    // é um lado declarar e o outro não.
    if (!iguais(oVivo[campo], doRepo[campo])) {
      achados.push({ no: nome, campo, vivo: oVivo[campo] ?? '(ausente)', repo: doRepo[campo] ?? '(ausente)' });
    }
  }
  // Os PARÂMETROS, que é o que a conferência de 26/08 já cobria — mantida
  // aqui para o conferidor ser um só.
  if (!iguais(semCamposDaInstalacao(oVivo.parameters), semCamposDaInstalacao(doRepo.parameters))) {
    achados.push({ no: nome, campo: 'parameters', vivo: '(diferente)', repo: '(diferente)' });
  }
  return achados;
}

/** As credenciais, pelo TIPO — nunca pelo id nem pelo nome (ver o topo). */
function conferirCredenciais(nome, oVivo, doRepo) {
  const achados = [];
  const tipos = new Set([
    ...Object.keys(doRepo.credentials ?? {}),
    ...Object.keys(oVivo.credentials ?? {}),
  ]);
  for (const tipo of tipos) {
    const noRepo = doRepo.credentials?.[tipo];
    const noVivo = oVivo.credentials?.[tipo];
    if (!noRepo || !noVivo) {
      achados.push({
        no: nome, campo: `credentials.${tipo}`,
        vivo: noVivo ? 'presente' : '(ausente)', repo: noRepo ? 'presente' : '(ausente)',
      });
    } else if (noVivo.id === 'REPLACE' && !oVivo.disabled) {
      // O `REPLACE` publicado: a publicação não passou pela substituição, e o
      // nó vai falhar na primeira execução com "Credential with ID REPLACE
      // does not exist" — a menos que esteja desabilitado, que é o único caso
      // em que o repositório publica um placeholder de propósito.
      achados.push({
        no: nome, campo: `credentials.${tipo}.id`,
        vivo: 'REPLACE (o placeholder do repositório) num nó HABILITADO',
        repo: '(um id da instalação)',
      });
    }
  }
  return achados;
}

export function conferir(vivo, repo) {
  const nosVivos = new Map((vivo.nodes ?? []).map((n) => [n.name, n]));
  const nosRepo = new Map((repo.nodes ?? []).map((n) => [n.name, n]));
  const achados = conferirPresenca(nosVivos, nosRepo);

  for (const [nome, doRepo] of nosRepo) {
    const oVivo = nosVivos.get(nome);
    if (!oVivo) continue;
    achados.push(...conferirComportamento(nome, oVivo, doRepo));
    achados.push(...conferirCredenciais(nome, oVivo, doRepo));
  }

  // As CONEXÕES: um nó certo ligado errado não aparece em nenhuma comparação
  // de nó.
  if (!iguais(vivo.connections ?? {}, repo.connections ?? {})) {
    achados.push({ no: '(o workflow)', campo: 'connections', vivo: '(diferente)', repo: '(diferente)' });
  }

  return achados;
}

// ---------------------------------------------------------------------------

// O CAMINHO VEM DA LINHA DE COMANDO, ENTÃO ELE É VALIDADO ANTES DE ABRIR.
//
// Ler um arquivo cujo caminho quem chama escolheu é o PROPÓSITO deste script —
// o JSON sai do editor do n8n e cai onde a pessoa salvou, normalmente
// `~/Downloads`. Então não cabe prender a leitura a um diretório: o que cabe é
// exigir que o argumento descreva de fato um arquivo JSON, e não um diretório,
// um dispositivo ou um caminho montado a partir de pedaços.
//
// A validação é feita sobre o caminho já RESOLVIDO (`resolve` normaliza `..` e
// links relativos), e é isso que a torna útil: validar a string crua deixaria
// passar `a/../../b`, que é outra coisa depois de normalizada.
function lerWorkflow(argumento) {
  const absoluto = resolve(String(argumento));
  if (!absoluto.toLowerCase().endsWith('.json')) {
    console.error(`recusado: "${argumento}" não é um arquivo .json — este conferidor lê o JSON do workflow.`);
    process.exit(2);
  }
  let info;
  try {
    info = statSync(absoluto);
  } catch {
    console.error(`recusado: não encontrei "${absoluto}".`);
    process.exit(2);
  }
  if (!info.isFile()) {
    console.error(`recusado: "${absoluto}" não é um arquivo comum.`);
    process.exit(2);
  }
  return JSON.parse(readFileSync(absoluto, 'utf8'));
}

const caminho = process.argv[2];
const ehExecucaoDireta = process.argv[1] && import.meta.url.endsWith(process.argv[1].split('/').pop());
if (ehExecucaoDireta) {
  if (!caminho) {
    console.error('uso: node n8n/conferir-publicado.mjs <workflow-publicado.json> [workflow-do-repo.json]');
    console.error('     o primeiro é o JSON BAIXADO do n8n; o segundo, por padrão, é n8n/workflow.e1-ingestao.json');
    process.exit(2);
  }
  const bruto = lerWorkflow(caminho);
  // Aceita tanto o JSON do editor quanto o envelope da API/MCP (`{workflow:…}`).
  const vivo = bruto.workflow ?? bruto.data ?? bruto;
  const doRepo = process.argv[3]
    ? lerWorkflow(process.argv[3])
    : JSON.parse(readFileSync(resolve(RAIZ, 'n8n/workflow.e1-ingestao.json'), 'utf8'));

  const achados = conferir(vivo, doRepo);
  const nNos = (doRepo.nodes ?? []).length;

  if (achados.length === 0) {
    console.log(`ok — os ${nNos} nós publicados batem com o repositório, inclusive disabled/onError/retryOnFail e o nome de cada credencial.`);
    process.exit(0);
  }
  console.error(`${achados.length} divergência(s) entre o publicado e o repositório:\n`);
  const larguraNo = Math.max(...achados.map((a) => a.no.length));
  for (const a of achados) {
    console.error(`  ${a.no.padEnd(larguraNo)}  ${a.campo}`);
    console.error(`  ${' '.repeat(larguraNo)}    publicado: ${JSON.stringify(a.vivo)}`);
    console.error(`  ${' '.repeat(larguraNo)}    repo:      ${JSON.stringify(a.repo)}`);
  }
  console.error('\nRepublique a partir do repositório (a substituição do `REPLACE` pelos ids da instalação');
  console.error('é o único passo manual) e rode este conferidor de novo sobre o JSON baixado depois.');
  process.exit(1);
}
