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
//   node n8n/conferir-publicado.mjs < ~/Downloads/workflow.json
//
//   # 2. ou, com acesso à API REST, sem passar por arquivo nenhum:
//   curl -s -H "X-N8N-API-KEY: $N8N_API_KEY" \
//     "$N8N_URL/api/v1/workflows/$ID" | node n8n/conferir-publicado.mjs
//
// O JSON ENTRA PELA ENTRADA PADRÃO, e não como caminho de arquivo. Não é
// preferência de estilo: um caminho vindo da linha de comando é um caminho que
// alguém — pessoa distraída ou agente automatizado — pode montar errado, e a
// primeira versão deste script abria o que recebesse. Com `<` e `|`, quem abre
// o arquivo é o shell, com as permissões de quem digitou, e este código não
// toca em caminho nenhum além do arquivo do próprio repositório, que é
// constante. O risco não foi validado: ele deixou de existir.
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
import { readFileSync } from 'node:fs';
import { lerWorkflowDaEntradaPadrao, ehExecucaoDireta } from './entrada-workflow.mjs';
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

/**
 * O PUBLICADO CONTÉM O QUE O REPOSITÓRIO DECLARA? — e não "é idêntico a".
 *
 * A distinção nasceu de uma acusação em massa: depois de uma republicação, este
 * conferidor apontou 20 nós com `parameters` diferentes, e quase todos eram o
 * n8n preenchendo o PRÓPRIO default ao salvar — `leftValue: ""`, `version: 1`,
 * um `options: {}` vazio. Nenhum deles muda comportamento, e um conferidor que
 * grita vinte vezes por nada deixa de ser lido, que é o pior estado possível
 * para uma ferramenta cuja única serventia é ser levada a sério.
 *
 * A regra certa é assimétrica, e é a que descreve o que se quer garantir: TUDO
 * o que o repositório declara tem de estar no publicado, com o mesmo valor. O
 * que o publicado acrescenta por conta própria é do n8n. Assim continua pegando
 * o caso real — `Juntar Ramos` publicado com `parameters: {}` enquanto o
 * repositório declara `mode: append` — sem inventar divergência.
 */
function contem(vivo, repo) {
  if (repo === null || typeof repo !== 'object') return iguais(vivo, repo);
  if (Array.isArray(repo)) {
    if (!Array.isArray(vivo) || vivo.length !== repo.length) return false;
    return repo.every((item, i) => contem(vivo[i], item));
  }
  if (vivo === null || typeof vivo !== 'object' || Array.isArray(vivo)) return false;
  return Object.keys(repo).every((k) => contem(vivo[k], repo[k]));
}

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
  if (!contem(semCamposDaInstalacao(oVivo.parameters), semCamposDaInstalacao(doRepo.parameters))) {
    achados.push({ no: nome, campo: 'parameters', vivo: '(falta ou diverge)', repo: '(o que o repositório declara)' });
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
    achados.push(
      ...conferirComportamento(nome, oVivo, doRepo),
      ...conferirCredenciais(nome, oVivo, doRepo),
    );
  }

  // As CONEXÕES: um nó certo ligado errado não aparece em nenhuma comparação
  // de nó.
  if (!iguais(vivo.connections ?? {}, repo.connections ?? {})) {
    achados.push({ no: '(o workflow)', campo: 'connections', vivo: '(diferente)', repo: '(diferente)' });
  }

  return achados;
}

// ---------------------------------------------------------------------------

if (ehExecucaoDireta(import.meta.url)) {
  const vivo = await lerWorkflowDaEntradaPadrao([
    'uso: node n8n/conferir-publicado.mjs < workflow-publicado.json',
    '     o JSON é o BAIXADO do editor do n8n (… → Download), ou a resposta da API REST.',
    '     ele entra pela ENTRADA PADRÃO — com `<` ou por `|`.',
  ]);
  const doRepo = JSON.parse(readFileSync(resolve(RAIZ, 'n8n/workflow.e1-ingestao.json'), 'utf8'));

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
