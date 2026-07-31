// Gerador do workflow de ÍNDICES MACROECONÔMICOS (db/migrations/0025).
//
// Workflow separado do de ingestão de propósito: ele não tem nada a ver com
// documento de mandato. Roda no relógio (mensal), não no upload; falha dele não
// pode derrubar a ingestão; e o dono pode reimportar/desligar um sem tocar no
// outro.
//
// Mesma disciplina do `build-workflow.mjs`: a lógica de verdade vive em
// `lib/macro.mjs` (testada por `test/macro.test.mjs`) e os nós Code EMBUTEM
// aquele código — aqui as constantes são importadas de `lib/`, não copiadas à
// mão, que é a origem conhecida de mirror desatualizado neste repositório.

import { writeFileSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { SERIES_MACRO, INDICADORES_FOCUS, urlSgs, urlFocus, urlSidraIpca, numeroMacro } from './lib/macro.mjs';

// `numeroMacro` EMBUTIDA do fonte, não copiada à mão. É o padrão que o gerador da
// ingestão já usa cinco vezes (prompt, ALIASES, diagnosticarErroApi, parseEntidade,
// orçamento) exatamente porque a cópia à mão deste repositório já divergiu — e este
// arquivo era o último mirror manual que restava.
const FONTE_NUMERO_MACRO = `const numeroMacro = ${numeroMacro.toString()};`;

const __dirname = dirname(fileURLToPath(import.meta.url));

const node = (name, type, typeVersion, parameters, x, y, opts = {}) => ({
  parameters, id: name.toLowerCase().replace(/[^a-z0-9]+/g, '-'), name, type, typeVersion,
  position: [x, y],
  ...(opts.credentials ? { credentials: opts.credentials } : {}),
  ...(opts.onError ? { onError: opts.onError } : {}),
  ...(opts.retryOnFail ? { retryOnFail: true, maxTries: opts.maxTries ?? 3, waitBetweenTries: 5000 } : {}),
});

// As APIs do BCB e do IBGE são públicas e sem chave, mas caem. `onError:
// continueRegularOutput` + retry: uma série indisponível não pode derrubar a
// coleta das outras — o mês volta na execução seguinte (a ingestão é
// idempotente por (serie, fonte, data_ref)).
const HTTP_TOLERANTE = { onError: 'continueRegularOutput', retryOnFail: true, maxTries: 3 };

// 132 meses = 11 anos: cobre a média de 10 anos com folga para o ano corrente
// incompleto. Rebaixar a janela inteira todo mês é de propósito — é assim que
// uma REVISÃO de série feita pela fonte chega até nós.
const MESES_HISTORICO = 132;

// Espelho do parse (lib/macro.mjs). Comprimido porque nó Code do N8N não
// importa arquivo; a fonte da verdade continua sendo a lib, e os testes de
// `macro.test.mjs` cobrem o comportamento.
const CODE_NORMALIZAR = `
const SERIES = ${JSON.stringify(SERIES_MACRO.map((s) => ({ codigo: s.codigo, sgs: s.sgs })))};
function num(b){ if(typeof b==='number') return isFinite(b)?b:null;
  const t=String(b==null?'':b).trim(); if(!t) return null;
  const n=Number(t.includes(',')?t.replace(/\\./g,'').replace(',','.'):t); return isFinite(n)?n:null; }
function dataSgs(b){ const m=String(b==null?'':b).match(/^(\\d{2})\\/(\\d{2})\\/(\\d{4})$/);
  return m? m[3]+'-'+m[2]+'-'+m[1] : null; }
// O no' HTTP Request do n8n EXPLODE resposta JSON que e' array em N itens. O SGS
// devolve [{data,valor}, ...x132], entao 'Manter Contexto SGS' (runOnceForEachItem)
// recebe UM objeto por item e gravava __corpo = {data,valor} -- nao um array. O
// '!Array.isArray(corpo) continue' abaixo descartava TODOS os ~792 itens das 6
// series mensais, em silencio. Sobrevivia so' o ramo IBGE/SIDRA, que ja' remontava
// o array ($input.all().map(...)) porque e' UMA requisicao so'.
//
// Nao se remonta aqui de proposito: cada item ja' carrega o __serie CERTO, pelo
// pareamento de itens do n8n ($('Series a Coletar').item). Agrupar de novo por
// serie seria refazer, com risco, um trabalho que o n8n ja' fez.
//
// A distincao importa: corpo de ERRO da API tambem e' um objeto unico. Envolver
// qualquer objeto num array faria a falha virar "zero observacoes" -- o mesmo
// silencio, por outra porta. So' o que TEM CARA DE OBSERVACAO e' aceito; o resto
// e' contado em 'descartados', e e' esse numero que torna a falha visivel.
function ehObsSgs(o){ return !!o && typeof o==='object' && !Array.isArray(o) && ('data' in o) && ('valor' in o); }
function comoArray(c){ return Array.isArray(c) ? c : (ehObsSgs(c) ? [c] : null); }
const obs=[];
let descartados=0;
for (const item of $input.all()) {
  const j=item.json||{};
  const serie=j.__serie, corpo=comoArray(j.__corpo);
  if(!serie||!corpo){ descartados++; continue; }
  if(j.__fonte==='IBGE/SIDRA'){
    for(const o of corpo.slice(1)){
      const m=String(o&&o.D3C||'').match(/^(\\d{4})(\\d{2})$/);
      const v=num(o&&o.V);
      if(m&&v!==null) obs.push({serie:'IPCA',fonte:'IBGE/SIDRA',data_ref:m[1]+'-'+m[2]+'-01',valor:v});
    }
  } else {
    for(const o of corpo){
      const d=dataSgs(o&&o.data), v=num(o&&o.valor);
      if(d&&v!==null) obs.push({serie:serie,fonte:'BCB/SGS',data_ref:d,valor:v});
    }
  }
}
// 'descartados' sai no payload de proposito: e' o unico numero que distingue
// "coletou e nao mudou nada" de "a API respondeu outra coisa e nada foi lido".
return [{ json: { observacoes: obs, n: obs.length, descartados } }];
`.trim();

const CODE_FOCUS = `
${FONTE_NUMERO_MACRO}
const obs=[];
for (const item of $input.all()) {
  const j=item.json||{};
  const serie=j.__serie;
  const linhas=(j.__corpo&&j.__corpo.value)||[];
  if(!serie||linhas.length===0) continue;
  // Só a coleta MAIS RECENTE: a API devolve o histórico inteiro de boletins e
  // misturar duas semanas daria dois números para o mesmo ano.
  let recente=''; for(const l of linhas){ if(l&&l.Data>recente) recente=l.Data; }
  const vistos={};
  for(const l of linhas){
    if(!l||l.Data!==recente) continue;
    const ano=Number(l.DataReferencia);
    // MIRROR que JA' DIVERGIU: o no' fazia typeof l.Mediana==='number' ? ... : null,
    // rejeitando QUALQUER string -- inclusive "4.50". A lib usa numeroMacro, que
    // aceita string e vírgula decimal. Medido: no' devolvia {n:0} onde a lib
    // devolvia 2 expectativas.
    //
    // Hoje o Olinda entrega numero (o seed versionado nao tem um null de
    // respondentes), entao isto era fragilidade LATENTE, nao a causa atual. Mas se
    // a API passar a serializar decimal como string, todo o ramo Focus zera em
    // silencio e as premissas de inflacao/juro da Modelagem vao a 0%.
    const mediana=numeroMacro(l.Mediana);
    if(!Number.isInteger(ano)||mediana===null||vistos[ano]) continue;
    vistos[ano]=1;
    obs.push({serie:serie,ano_ref:ano,mediana:mediana,
      media:numeroMacro(l.Media),
      respondentes:numeroMacro(l.numeroRespondentes),
      coletado_em:recente});
  }
}
return [{ json: { expectativas: obs, n: obs.length } }];
`.trim();

const PG = { credentials: { postgres: { id: 'SUPABASE_PG', name: 'Supabase Postgres' } },
  onError: 'continueRegularOutput', retryOnFail: true, maxTries: 3 };

const nodes = [
  node('Agenda Mensal', 'n8n-nodes-base.scheduleTrigger', 1.2, {
    rule: { interval: [{ field: 'months', triggerAtDayOfMonth: 12, triggerAtHour: 6 }] },
  }, 0, 300),

  // Dia 12 e não dia 1: o IPCA do mês anterior é divulgado pelo IBGE por volta
  // do dia 10. Coletar antes disso traria o mês sempre incompleto e faria a
  // conferência entre fontes acusar divergência todo mês por atraso de
  // publicação, não por erro.

  node('Séries a Coletar', 'n8n-nodes-base.code', 2, {
    jsCode: `return ${JSON.stringify(
      SERIES_MACRO.map((s) => ({ json: { __serie: s.codigo, __url: urlSgs(s.sgs, { mesesAtras: MESES_HISTORICO }) } })),
    )};`,
  }, 220, 200),

  node('BCB SGS', 'n8n-nodes-base.httpRequest', 4.2, {
    url: '={{ $json.__url }}', options: { response: { response: { neverError: true } } },
  }, 440, 200, HTTP_TOLERANTE),

  node('Manter Contexto SGS', 'n8n-nodes-base.code', 2, {
    mode: 'runOnceForEachItem',
    jsCode: "return { json: { __serie: $('Séries a Coletar').item.json.__serie, __fonte: 'BCB/SGS', __corpo: $json } };",
  }, 660, 200),

  node('IBGE SIDRA (IPCA)', 'n8n-nodes-base.httpRequest', 4.2, {
    url: urlSidraIpca({ ultimos: MESES_HISTORICO }),
    options: { response: { response: { neverError: true } } },
  }, 440, 380, HTTP_TOLERANTE),

  node('Marcar Fonte IBGE', 'n8n-nodes-base.code', 2, {
    jsCode: "return [{ json: { __serie: 'IPCA', __fonte: 'IBGE/SIDRA', __corpo: $input.all().map(i => i.json) } }];",
  }, 660, 380),

  node('Normalizar Observações', 'n8n-nodes-base.code', 2, { jsCode: CODE_NORMALIZAR }, 880, 290),

  node('Gravar Índices', 'n8n-nodes-base.postgres', 2.5, {
    operation: 'executeQuery',
    query: 'select * from fn_registrar_indice_macro($1::jsonb)',
    options: { queryReplacement: '={{ JSON.stringify($json.observacoes) }}' },
  }, 1100, 290, PG),

  node('Conferir Fontes', 'n8n-nodes-base.postgres', 2.5, {
    operation: 'executeQuery',
    // A conferência é o que autoriza chamar o dado de validado. Ela não corrige
    // nada: registra a divergência para um humano decidir qual fonte vale.
    query: 'select * from fn_divergencias_indice_macro()',
  }, 1320, 290, PG),

  node('Indicadores Focus', 'n8n-nodes-base.code', 2, {
    jsCode: `return ${JSON.stringify(
      INDICADORES_FOCUS.map((i) => ({ json: { __serie: i.codigo, __url: urlFocus(i.indicador, { top: 80 }) } })),
    )};`,
  }, 220, 560),

  node('BCB Focus', 'n8n-nodes-base.httpRequest', 4.2, {
    url: '={{ $json.__url }}', options: { response: { response: { neverError: true } } },
  }, 440, 560, HTTP_TOLERANTE),

  node('Manter Contexto Focus', 'n8n-nodes-base.code', 2, {
    mode: 'runOnceForEachItem',
    jsCode: "return { json: { __serie: $('Indicadores Focus').item.json.__serie, __corpo: $json } };",
  }, 660, 560),

  node('Normalizar Focus', 'n8n-nodes-base.code', 2, { jsCode: CODE_FOCUS }, 880, 560),

  node('Gravar Expectativas', 'n8n-nodes-base.postgres', 2.5, {
    operation: 'executeQuery',
    query: 'select fn_registrar_expectativa_macro($1::jsonb) as n',
    options: { queryReplacement: '={{ JSON.stringify($json.expectativas) }}' },
  }, 1100, 560, PG),
];

const connections = {
  'Agenda Mensal': { main: [[
    { node: 'Séries a Coletar', type: 'main', index: 0 },
    { node: 'IBGE SIDRA (IPCA)', type: 'main', index: 0 },
    { node: 'Indicadores Focus', type: 'main', index: 0 },
  ]] },
  'Séries a Coletar': { main: [[{ node: 'BCB SGS', type: 'main', index: 0 }]] },
  'BCB SGS': { main: [[{ node: 'Manter Contexto SGS', type: 'main', index: 0 }]] },
  'Manter Contexto SGS': { main: [[{ node: 'Normalizar Observações', type: 'main', index: 0 }]] },
  'IBGE SIDRA (IPCA)': { main: [[{ node: 'Marcar Fonte IBGE', type: 'main', index: 0 }]] },
  'Marcar Fonte IBGE': { main: [[{ node: 'Normalizar Observações', type: 'main', index: 0 }]] },
  'Normalizar Observações': { main: [[{ node: 'Gravar Índices', type: 'main', index: 0 }]] },
  'Gravar Índices': { main: [[{ node: 'Conferir Fontes', type: 'main', index: 0 }]] },
  'Indicadores Focus': { main: [[{ node: 'BCB Focus', type: 'main', index: 0 }]] },
  'BCB Focus': { main: [[{ node: 'Manter Contexto Focus', type: 'main', index: 0 }]] },
  'Manter Contexto Focus': { main: [[{ node: 'Normalizar Focus', type: 'main', index: 0 }]] },
  'Normalizar Focus': { main: [[{ node: 'Gravar Expectativas', type: 'main', index: 0 }]] },
};

const workflow = {
  name: 'Oria — Índices Macroeconômicos (BCB/SGS + Focus + IBGE)',
  nodes, connections, settings: { executionOrder: 'v1' },
  meta: {
    note: 'Gerado por n8n/build-workflow-macro.mjs. Coleta mensal de IPCA/IGP-M/INPC/Selic/CDI/câmbio '
      + '(BCB/SGS), da expectativa Focus por ano e do IPCA no IBGE/SIDRA para conferência cruzada. '
      + 'A ingestão é idempotente por (serie, fonte, data_ref): rebaixar a janela toda vez é '
      + 'intencional — é assim que uma revisão de série feita pela fonte chega até nós.',
  },
};

writeFileSync(join(__dirname, 'workflow.macro.json'), JSON.stringify(workflow, null, 2) + '\n');
console.log('Escrito workflow macro —', nodes.length, 'nós,', Object.keys(connections).length, 'conexões');
