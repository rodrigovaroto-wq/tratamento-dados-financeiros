// Diz, em segundos, POR QUE o provedor de IA está recusando as chamadas do
// pipeline.
//
//   IA_API_KEY=... node N8N/diagnosticar-ia.mjs
//   IA_API_KEY=... node N8N/diagnosticar-ia.mjs --modelos   (só lista, zero token)
//
// O provedor testado é o ATIVO (`lib/provedor.mjs`, padrão Google). Para testar
// o outro sem mexer em código:  IA_PROVEDOR=openai IA_API_KEY=sk-... node ...
//
// POR QUE EXISTE. No "teste v30" os 14 documentos falharam com uma frase que o
// N8N acrescenta a QUALQUER resposta 429 ("Try spacing your requests out using
// the batching settings under 'Options'"). Essa frase é indistinguível entre
// causas que pedem ações OPOSTAS:
//
//   • crédito esgotado          → recarregar (espaçar não resolve)
//   • TETO DE GASTO configurado → subir o teto do projeto/org (espaçar não resolve),
//                                 e ele NÃO aparece nas telas de Billing e Limits
//   • cota diária               → só reabre amanhã
//   • cadência por minuto       → o ÚNICO caso em que espaçar resolve
//
// Sem saber qual, a rodada anterior chutou "cadência" e subiu o intervalo de 6s
// para 12s — e o problema continuou. Este script tira o chute da frente: faz UMA
// chamada mínima com a sua chave e devolve a causa classificada.
//
// LIMITE DO SCRIPT, dito de frente: ele testa a conta AGORA. Uma chamada avulsa
// passar não descarta teto de gasto atingido no momento do lote, nem cadência sob
// carga. Quando ele diz "está respondendo normalmente", a saída explica os dois e
// aponta o que decide de fato — a execução guardada no N8N, que preservou o corpo
// real do provedor.
//
// CUSTO: uma requisição com `max_tokens: 1`. Se a conta estiver sem crédito, ela
// é recusada antes de gerar token nenhum — custo zero. Se estiver funcionando, o
// custo é de um token. Nunca envia documento.
//
// O diagnóstico é o MESMO usado em produção (`diagnosticarErroApi` de
// lib/extract.mjs, embutido nos nós do workflow) — de propósito: se o script diz
// "crédito esgotado", é exatamente isso que a pendência do documento vai dizer.

import { readFileSync } from 'node:fs';
import { diagnosticarErroApi, DEFAULT_MODEL, MAX_OUTPUT_TOKENS, TPM_CONTA, RPM_CONTA } from './lib/extract.mjs';
import { MODELO_EXTRACAO, MODELO_CLASSIFICACAO } from './lib/custo.mjs';
import {
  provedor, urlDaChamada, montarCorpoIA, parteDeTexto, modelosDoCatalogo, modelosParecidos,
} from './lib/provedor.mjs';

const PROV = provedor();

// ---------------------------------------------------------------------------
// NADA QUE VEIO DO OUTRO LADO DA REDE VAI CRU PARA A TELA
// ---------------------------------------------------------------------------
//
// Tudo o que este script imprime sobre a falha vem da resposta do provedor —
// mensagem de erro, id de modelo, valor de header. É o propósito do script, e
// não há como diagnosticar sem mostrar. O que NÃO pode é ir literal: uma string
// com `\n` inventa uma linha nova, e uma linha nova aqui parece saída do
// diagnóstico. É a diferença entre "o provedor disse X" e "o diagnóstico
// concluiu X" — e num script cuja saída inteira é para ser lida como veredito,
// essa confusão é o defeito.
//
// Colapsa controle e quebra de linha em espaço, e corta no tamanho: o resto da
// mensagem de um terceiro não acrescenta nada que decida alguma coisa. É a
// mesma regra que o `diagnosticarErroApi` já aplica ao cortar em 200/300
// caracteres o que entra no motivo da pendência.
const LIMITE_TEXTO_REMOTO = 400;
function deRemoto(valor, limite = LIMITE_TEXTO_REMOTO) {
  const t = typeof valor === 'string' ? valor : JSON.stringify(valor ?? null);
  // eslint-disable-next-line no-control-regex
  const limpo = String(t).replace(/[\u0000-\u001f\u007f]+/g, ' ').trim();
  return limpo.length > limite ? `${limpo.slice(0, limite)}…` : limpo;
}

// O intervalo REALMENTE gerado no workflow — lido do JSON, não reescrito aqui.
// Comparar o configurado com o que o TPM real suporta é o ponto do script; ler de
// uma segunda fonte anularia a comparação (os dois números viriam do mesmo lugar).
const INTERVALO_EXTRACAO_CONFIGURADO = (() => {
  try {
    const wf = JSON.parse(readFileSync(new URL('./workflow.e1-ingestao.json', import.meta.url), 'utf8'));
    const no = wf.nodes.find((n) => n.name === 'IA Extrair');
    return no?.parameters?.options?.batching?.batch?.batchInterval ?? null;
  } catch { return null; }
})();

// `IA_API_KEY` é o nome de hoje; `OPENAI_API_KEY` continua aceito para quem já
// tem a variável exportada no terminal. Aceitar as duas custa uma linha e evita
// que a troca de provedor quebre o hábito de quem já usava o script.
const chave = process.env.IA_API_KEY || process.env.OPENAI_API_KEY;
if (!chave) {
  console.error(`Falta IA_API_KEY. Rode:  IA_API_KEY=... node N8N/diagnosticar-ia.mjs`);
  console.error(`(a mesma chave que está na credencial "${PROV.credencial}" do N8N — é ela que precisa ser testada)`);
  console.error(`(provedor ativo: ${PROV.rotulo}; para testar outro: IA_PROVEDOR=openai ...)`);
  process.exit(2);
}

const args = process.argv.slice(2);
const soListar = args.includes('--modelos');
const modelo = args.find((a) => !a.startsWith('--')) || DEFAULT_MODEL;

// ---------------------------------------------------------------------------
// O CATÁLOGO — a checagem que não gasta token e responde antes de a conta pagar
// ---------------------------------------------------------------------------
//
// O id do modelo é a única coisa deste sistema que NÃO pode ser conferida por
// teste: ele é uma string que só a API do provedor sabe validar, e errá-la por
// um sufixo faz TODA chamada do lote voltar 404. `diagnosticarErroApi` nomeia
// esse caso, mas nomear depois de o lote morrer é tarde — e um 404 diz "este id
// não existe" sem dizer quais existem.
//
// Isto é um GET no catálogo da conta: custo zero, nenhum token, e responde as
// duas perguntas de uma vez — a chave funciona, e o id configurado está lá.
async function listarModelos() {
  try {
    const r = await fetch(PROV.catalogo, {
      headers: { [PROV.auth.nome]: `${PROV.auth.prefixo}${chave}` },
    });
    const corpoLista = await r.json().catch(() => ({}));
    if (!r.ok) return { ok: false, status: r.status, corpo: corpoLista, modelos: [] };
    return { ok: true, status: r.status, corpo: corpoLista, modelos: modelosDoCatalogo(PROV, corpoLista) };
  } catch (e) {
    return { ok: false, erro: e?.message ?? String(e), modelos: [] };
  }
}

if (soListar) {
  const cat = await listarModelos();
  if (!cat.ok) {
    console.log(`NÃO FOI POSSÍVEL LISTAR os modelos de ${PROV.rotulo}.`);
    if (cat.erro) {
      console.log(`  Falha de rede: ${cat.erro}`);
      console.log('  Se o terminal está atrás de proxy/firewall, é aí que olhar.');
    } else {
      // O MESMO diagnóstico da produção, e não uma segunda leitura do erro: se
      // a chave está errada aqui, a pendência do documento vai dizer a mesma
      // coisa com as mesmas palavras.
      // Sem `?? {}`: espalhar `null` já rende objeto vazio em JS, e o fallback
      // só fazia parecer que havia um caso a tratar onde não há.
      const dl = diagnosticarErroApi({ httpCode: cat.status, ...cat.corpo });
      console.log(`  CAUSA: ${dl.causa}`);
      // 1200: o `motivo` é quase todo TEXTO NOSSO, com um trecho do provedor
      // encaixado — cortá-lo em 400 truncaria a instrução do que fazer, que é a
      // metade útil. O que veio de fora já entra ali cortado em 200.
      console.log(`  ${deRemoto(dl.motivo, 1200)}`);
    }
    process.exit(1);
  }
  // Qual papel este modelo cumpre no workflow, se cumpre algum. Fora do laço e
  // com nome próprio: aninhar dois ternários numa expressão faz a leitura
  // depender de contar parênteses, e o que se lê aqui é a resposta à pergunta
  // que o dono veio fazer — "o que eu configurei está nesta lista?".
  const papelDoModelo = (id) => {
    if (id === MODELO_EXTRACAO) return '  ← MODELO_EXTRACAO';
    if (id === MODELO_CLASSIFICACAO) return '  ← MODELO_CLASSIFICACAO';
    return '';
  };
  console.log(`Modelos disponíveis para esta chave em ${PROV.rotulo} (${cat.modelos.length}):\n`);
  for (const id of cat.modelos.slice().sort()) {
    console.log(`  ${deRemoto(id, 120)}${papelDoModelo(id)}`);
  }
  const faltando = [MODELO_EXTRACAO, MODELO_CLASSIFICACAO]
    .filter((m, i, a) => a.indexOf(m) === i)
    .filter((m) => !cat.modelos.includes(m));
  if (faltando.length > 0) {
    console.log(`\n⚠️  CONFIGURADO MAS NÃO DISPONÍVEL: ${faltando.join(', ')}`);
    for (const m of faltando) {
      const perto = modelosParecidos(m, cat.modelos, 5).map((x) => deRemoto(x, 120));
      console.log(`  parecidos com "${m}": ${perto.join(', ') || '(nenhum)'}`);
    }
    console.log('  Corrija MODELOS_POR_PROVEDOR em N8N/lib/custo.mjs, rode');
    console.log('  `node N8N/build-workflow.mjs` e reimporte o workflow.');
    process.exit(1);
  }
  console.log('\nOK — os modelos configurados existem nesta conta.');
  process.exit(0);
}

console.log(`Testando a conta ${PROV.rotulo} com o modelo ${modelo} (1 token de saída)...\n`);

let resposta;
let corpo;
try {
  resposta = await fetch(urlDaChamada(PROV, modelo), {
    method: 'POST',
    headers: {
      'content-type': 'application/json',
      // O header de auth é do provedor: `Authorization: Bearer` na OpenAI,
      // `x-goog-api-key` no Google. A chave NUNCA vai na query string.
      [PROV.auth.nome]: `${PROV.auth.prefixo}${chave}`,
    },
    body: JSON.stringify(montarCorpoIA(PROV, {
      modelo,
      sistema: null,
      partes: [parteDeTexto(PROV, 'ok')],
      maxTokens: 1,
      // `none` pela MESMA razão do corpo mínimo do workflow de diagnóstico (ver
      // `build-workflow-diagnostico.mjs`): num modelo que raciocina, o default é
      // `medium`, e token de raciocínio é gasto ANTES da primeira letra da
      // resposta. Um teto de 1 token com esforço médio cobra centenas ou
      // milhares de tokens e devolve vazio — esta ferramenta passaria a medir
      // truncamento em vez de medir se a conta responde, que é a única pergunta
      // que ela existe para fazer. Em provedor que não raciocina o campo é
      // ignorado por `montarCorpoIA` (mandá-lo seria 400).
      esforco: 'none',
    })),
  });
  corpo = await resposta.json().catch(() => ({}));
} catch (erro) {
  console.log(`FALHA DE REDE ao chegar em ${PROV.rotulo} (nem o servidor respondeu):`);
  console.log(`  ${deRemoto(erro?.message ?? erro)}`);
  console.log('\nSe o N8N está atrás de proxy/firewall, é aí que olhar — não é conta nem cadência.');
  process.exit(1);
}

if (resposta.ok) {
  console.log('A CONTA ESTÁ RESPONDENDO NORMALMENTE.');
  console.log(`  HTTP ${resposta.status} · modelo ${deRemoto(corpo?.model ?? modelo, 120)}`);
  console.log('\nUma chamada avulsa passar NÃO descarta duas causas — as duas ficam invisíveis aqui:');
  console.log('  1. TETO DE GASTO já atingido no momento do LOTE (do projeto da chave ou orçamento');
  console.log('     mensal da org). Não aparece na tela de cobrança nem na de limites do tier.');
  console.log(`     Conferir no console do provedor: ${PROV.console}`);
  console.log('  2. CADÊNCIA sob carga: 1 chamada passa, 14 seguidas estouram o limite por MINUTO.');
  console.log('     A conta abaixo diz se é o caso.');
  console.log('\nO que decide de fato, sem gastar nada: abrir a execução que falhou no N8N →');
  console.log('nó "IA Extrair" → Output → JSON de um item falho → ler `error.error.code`.');
  console.log('O corpo real do provedor está preservado ali (o n8n só sobrescreve o campo `message`).');
  // Limites do momento vêm nos headers — quando presentes, respondem de uma vez
  // qual é o teto e quanto sobrou. É a informação que a pendência nunca teve.
  const cabecalhos = [
    'x-ratelimit-limit-requests', 'x-ratelimit-remaining-requests',
    'x-ratelimit-limit-tokens', 'x-ratelimit-remaining-tokens',
    'x-ratelimit-reset-tokens',
  ].map((h) => [h, resposta.headers.get(h)]).filter(([, v]) => v);
  if (cabecalhos.length) {
    console.log(`\nLimites informados por ${PROV.rotulo} para esta chave/modelo:`);
    for (const [h, v] of cabecalhos) console.log(`  ${h.replace('x-ratelimit-', '')}: ${deRemoto(v, 80)}`);
  }

  // A ARITMÉTICA, com o TPM REAL da conta em vez do palpite. A OpenAI conta o
  // consumo de rate limit como o MÁXIMO entre `max_tokens` e os tokens estimados
  // do request — então cada extração reserva `MAX_OUTPUT_TOKENS` do balde por
  // minuto, independente do tamanho do PDF. Com o teto real em mãos, dá para
  // dizer se a cadência configurada cabe ou não, e qual seria a certa.
  //
  // NEM TODO PROVEDOR MANDA ESSES HEADERS — o Google não manda. Quando não vêm,
  // o script cai no valor DECLARADO em `lib/provedor.mjs` e diz que é declarado:
  // afirmar um TPM que não foi lido seria a mesma invenção que este script
  // existe para tirar da frente.
  const tpmLido = Number(resposta.headers.get('x-ratelimit-limit-tokens'));
  const tpmReal = Number.isFinite(tpmLido) && tpmLido > 0 ? tpmLido : TPM_CONTA;
  const lido = Number.isFinite(tpmLido) && tpmLido > 0;
  if (tpmReal > 0) {
    const porTpm = tpmReal / MAX_OUTPUT_TOKENS;
    // O limite por CHAMADA entra na conta quando o provedor tem um, e cada
    // documento pode fazer DUAS chamadas (classificação + extração).
    const chamadasPorMin = RPM_CONTA ? Math.min(porTpm, RPM_CONTA / 2) : porTpm;
    const intervaloIdeal = Math.max(6000, Math.ceil(60000 / chamadasPorMin));
    console.log(`\nTPM ${lido ? 'LIDO da resposta' : `DECLARADO em lib/provedor.mjs (${PROV.rotulo} não informa nos headers)`}: ${tpmReal}`);
    if (RPM_CONTA) console.log(`RPM declarado: ${RPM_CONTA} chamada(s)/min`);
    console.log('\nCADÊNCIA que este TPM suporta (max_tokens da extração = '
      + `${MAX_OUTPUT_TOKENS}, que é RESERVA de TPM por chamada):`);
    console.log(`  ${chamadasPorMin.toFixed(1)} chamada(s)/min → intervalo mínimo de ${intervaloIdeal}ms`);
    if (intervaloIdeal !== INTERVALO_EXTRACAO_CONFIGURADO) {
      console.log(`\n  ⚠️  O workflow está configurado para ${INTERVALO_EXTRACAO_CONFIGURADO}ms.`);
      console.log(`  Ajuste tpm/rpm do provedor "${PROV.id}" em N8N/lib/provedor.mjs, rode`);
      console.log('  `node N8N/build-workflow.mjs` e reimporte o workflow.');
    } else {
      console.log(`\n  A configuração atual (${INTERVALO_EXTRACAO_CONFIGURADO}ms) confere com este TPM.`);
    }
  }
  process.exit(0);
}

// A resposta de erro real do provedor, classificada pelo MESMO código de produção.
const d = diagnosticarErroApi({ httpCode: resposta.status, ...corpo });
console.log(`CAUSA: ${d.causa}\n`);
console.log(deRemoto(d.motivo, 1200));
// MODELO INDISPONÍVEL É O ÚNICO CASO QUE TEM CONSERTO IMEDIATO, e o conserto
// depende de saber o que EXISTE. Listar aqui é automático de propósito: é o
// momento em que a informação vale, e pedir ao dono que rode outro comando
// depois de uma falha é como se perde a correção que estava a um GET de
// distância.
if (d.causa === 'modelo_indisponivel') {
  const cat = await listarModelos();
  if (cat.ok) {
    console.log(`\nO QUE EXISTE nesta conta (${cat.modelos.length} modelos). Mais parecidos com "${modelo}":`);
    for (const id of modelosParecidos(modelo, cat.modelos, 8)) console.log(`  ${deRemoto(id, 120)}`);
    console.log('\nCorrija MODELOS_POR_PROVEDOR em N8N/lib/custo.mjs, rode');
    console.log('`node N8N/build-workflow.mjs` e reimporte o workflow no n8n.');
  }
}

console.log(`\n--- resposta bruta de ${PROV.rotulo} (para o registro) ---`);
console.log(deRemoto(JSON.stringify(corpo), 800));
const retryAfter = resposta.headers.get('retry-after');
if (retryAfter) console.log(`\nRetry-After: ${deRemoto(retryAfter, 40)}s`);
process.exit(1);
