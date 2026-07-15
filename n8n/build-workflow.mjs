// Gera o workflow N8N da Fatia 1 (E1 — ingestão) a partir de partes legíveis.
// Rodar: node n8n/build-workflow.mjs  → escreve n8n/workflow.e1-ingestao.json
//
// Por que um gerador: garante JSON válido e mantém o corpo dos nós Code legível.
// A lógica dos nós Code ESPELHA os módulos testados em n8n/lib/ (fonte da verdade
// dos testes). Ao mudar a lógica, mude lib/ + rode os testes, depois regenere.

import { writeFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const __dirname = dirname(fileURLToPath(import.meta.url));

// --- corpo do nó Code: classificação por nome (espelha lib/classifier.mjs) ---
const CODE_CLASSIFICAR = `
// Espelha n8n/lib/classifier.mjs (fonte testada). Classifica por NOME + regras.
function normalize(s){return String(s||'').normalize('NFD').replace(/[\\u0300-\\u036f]/g,'').toLowerCase().replace(/\\.[a-z0-9]{2,4}$/i,'').replace(/[_\\-.]+/g,' ').replace(/\\s+/g,' ').trim();}
const ALIASES=[
  {codigo:'FAT_INTRAGRUPO',termos:['faturamento intragrupo','fat intragrupo','faturamento intra grupo']},
  {codigo:'FATURAMENTO_24M',termos:['faturamento 24m','faturamento 36','faturamento','receita bruta','receita']},
  {codigo:'CONTRATO_SOCIAL',termos:['contrato social','estatuto social','alteracao contratual','estatuto']},
  {codigo:'MUTUOS',termos:['mutuos','mutuo','relacao de mutuos','contas intragrupo']},
  {codigo:'COMBINADO',termos:['combinado','combinada','demonstracoes combinadas','df combinada']},
  {codigo:'FLUXO_CAIXA',termos:['fluxo de caixa','fluxo caixa','dfc','cash flow','fluxo']},
  {codigo:'DRE',termos:['dre','demonstracao de resultado','demonstracao do resultado','resultado do exercicio']},
  {codigo:'BALANCO',termos:['balanco patrimonial','balanco','bp']},
  {codigo:'BALANCETE',termos:['balancete']},
];
function parsePeriodo(t){
  let m=t.match(/\\b(\\d{1,2})m(\\d{2,4})\\b/); if(m&&Number(m[1])===12)return{tipo:'anual',referencia:'12M'+m[2].slice(-2)};
  m=t.match(/\\bl(\\d{1,2})m\\b/)||t.match(/\\b(\\d{2})\\s*meses\\b/); if(m)return{tipo:'multi',referencia:'L'+m[1]+'M'};
  m=t.match(/\\b([1-4])t(\\d{2,4})\\b/); if(m)return{tipo:'trimestre',referencia:m[1]+'T'+m[2].slice(-2)};
  const anos=t.match(/\\b(20)?\\d{2}\\b/g); if(anos&&anos.length>=2)return{tipo:'multi',referencia:anos.map(a=>a.slice(-2)).join(',')};
  return null;
}
function parseTipo(t){for(const a of ALIASES){for(const termo of a.termos){if(t.includes(termo))return a.codigo;}}return null;}
const item=$input.item.json;
const t=normalize(item.nome_original);
const tipo=parseTipo(t), periodo=parsePeriodo(t);
const assinado=/\\bassinad[oa]s?\\b/.test(t)?true:null;
let conf=0; if(tipo)conf+=0.6; if(periodo)conf+=0.3; if(assinado===true)conf+=0.1; conf=Math.min(1,Number(conf.toFixed(2)));
return [{json:{...item,
  tipo_taxonomia:tipo, periodo_tipo:periodo?periodo.tipo:null, periodo_ref:periodo?periodo.referencia:null,
  assinado, confianca:conf, fonte:'nome_arquivo', precisa_fallback_openai:(conf<0.7|| !tipo)}}];
`.trim();

// --- corpo do nó Code: monta o corpo da chamada OpenAI COM o conteúdo do arquivo
// (espelha lib/openai.mjs contentPartFromFile + buildClassificationRequest) ---
const CODE_PREPARAR_CONTEUDO = `
// Espelha n8n/lib/openai.mjs. Monta openai_body com a parte de CONTEUDO do arquivo.
const item=$input.item.json;
const binKey=item.binary_key;
const bin=($input.item.binary||{})[binKey]||{};
const b64=bin.data||''; const mt=(bin.mimeType||'').toLowerCase();
function part(){
  if(/pdf/.test(mt))return{type:'file',file:{filename:item.nome_original||'documento.pdf',file_data:'data:application/pdf;base64,'+b64}};
  if(mt.indexOf('image/')===0)return{type:'image_url',image_url:{url:'data:'+mt+';base64,'+b64}};
  if(/spreadsheetml|ms-excel|excel|csv/.test(mt))return{type:'text',text:'(planilha: extrair texto antes — ver README; classificar pelo nome '+(item.nome_original||'')+')'};
  return{type:'text',text:'(conteudo nao suportado: '+mt+')'};
}
const schema={name:'classificacao_documento',strict:true,schema:{type:'object',additionalProperties:false,required:['tipo_taxonomia','entidade','periodo_tipo','periodo_referencia','assinado','confianca','justificativa'],properties:{tipo_taxonomia:{type:'string'},entidade:{type:['string','null']},periodo_tipo:{type:'string'},periodo_referencia:{type:['string','null']},assinado:{type:['boolean','null']},confianca:{type:'number'},justificativa:{type:'string'}}}};
const body={model:($env.OPENAI_MODEL||'gpt-4o'),temperature:0,response_format:{type:'json_schema',json_schema:schema},messages:[
  {role:'system',content:'Classifique o documento financeiro na taxonomia da Oria (Reestruturacao, Brasil). Convencoes de periodo: 12M25=ano 2025; 1T25=1o trimestre/2025; L24M=ultimos 24 meses; 23,24,25=multiplos exercicios. Se incerto use DESCONHECIDO e confianca baixa. Nunca invente.'},
  {role:'user',content:[{type:'text',text:'Nome do arquivo (pista fraca): '+(item.nome_original||'')},part()]}
]};
return [{json:{...item, openai_body: body}}];
`.trim();

// --- corpo do nó Code: parse da resposta OpenAI (espelha lib/openai.mjs) ---
const CODE_PARSE_OPENAI = `
// Espelha n8n/lib/openai.mjs parseClassificationResponse.
// Contexto do item vem do nó anterior; a resposta da OpenAI vem em $json.
const item=$('Preparar Conteudo Fallback').item.json;
const resp=$json;
const content=resp?.choices?.[0]?.message?.content;
if(!content){return [{json:{...item, fonte:'openai_conteudo', confianca:0, tipo_taxonomia:item.tipo_taxonomia||null}}];}
let p; try{p=typeof content==='string'?JSON.parse(content):content;}catch(e){return [{json:{...item, fonte:'openai_conteudo', confianca:0}}];}
return [{json:{...item,
  tipo_taxonomia:p.tipo_taxonomia==='DESCONHECIDO'?null:p.tipo_taxonomia,
  entidade:p.entidade??item.entidade??null,
  periodo_tipo:p.periodo_referencia?p.periodo_tipo:null,
  periodo_ref:p.periodo_referencia??null,
  assinado:p.assinado??null,
  confianca:typeof p.confianca==='number'?p.confianca:0,
  fonte:'openai_conteudo', justificativa:p.justificativa||''}}];
`.trim();

// --- corpo do nó Code: split dos arquivos do Form em itens por arquivo ---
const CODE_LISTAR = `
// Um item por arquivo enviado no Form Trigger. Mantém caso_id (do nó anterior).
const caso_id = $('Upsert Caso (Postgres)').first().json.caso_id;
const bin = $input.item.binary || {};
const out = [];
for (const key of Object.keys(bin)) {
  out.push({ json: { caso_id, nome_original: bin[key].fileName || key, binary_key: key }, binary: { [key]: bin[key] } });
}
return out;
`.trim();

let y = 300;
const node = (name, type, typeVersion, parameters, extra = {}) => ({
  parameters, id: name.toLowerCase().replace(/[^a-z0-9]+/g, '-'),
  name, type, typeVersion, position: [extra.x ?? 0, extra.y ?? (y += 0)], ...(extra.credentials ? { credentials: extra.credentials } : {}),
});

const nodes = [
  node('Intake (Form)', 'n8n-nodes-base.formTrigger', 2, {
    formTitle: 'Intake Oria — Reestruturação',
    formDescription: 'Suba TODOS os arquivos brutos do mandato de uma vez. O sistema classifica e confere a completude.',
    formFields: { values: [
      { fieldLabel: 'Mandato (nome do caso)', fieldType: 'text', requiredField: true },
      { fieldLabel: 'Arquivos', fieldType: 'file', multipleFiles: true, requiredField: true },
    ] },
  }, { x: 0, y: 300 }),

  node('Upsert Caso (Postgres)', 'n8n-nodes-base.postgres', 2.5, {
    operation: 'executeQuery',
    query: "select fn_upsert_caso($1) as caso_id",
    options: { queryReplacement: "={{ $json['Mandato (nome do caso)'] }}" },
  }, { x: 220, y: 300, credentials: { postgres: { id: 'REPLACE', name: 'Supabase Postgres (Session Pooler)' } } }),

  node('Listar Arquivos', 'n8n-nodes-base.code', 2, { jsCode: CODE_LISTAR }, { x: 440, y: 300 }),

  node('Upload Storage', 'n8n-nodes-base.httpRequest', 4.2, {
    method: 'POST',
    url: "={{ $env.SUPABASE_URL }}/storage/v1/object/documentos/{{ $json.caso_id }}/{{ $json.nome_original }}",
    sendHeaders: true,
    headerParameters: { parameters: [
      { name: 'Authorization', value: '=Bearer {{ $env.SUPABASE_SERVICE_KEY }}' },
      { name: 'x-upsert', value: 'true' },
    ] },
    sendBody: true, contentType: 'binaryData', inputDataFieldName: '={{ $json.binary_key }}',
  }, { x: 660, y: 300 }),

  node('Classificar Nome', 'n8n-nodes-base.code', 2, { jsCode: CODE_CLASSIFICAR }, { x: 880, y: 300 }),

  node('Precisa Fallback?', 'n8n-nodes-base.if', 2, {
    conditions: { options: { caseSensitive: true, typeValidation: 'strict' }, combinator: 'and', conditions: [
      { leftValue: '={{ $json.precisa_fallback_openai }}', rightValue: true, operator: { type: 'boolean', operation: 'true', singleValue: true } },
    ] },
  }, { x: 1100, y: 300 }),

  node('Preparar Conteudo Fallback', 'n8n-nodes-base.code', 2, { jsCode: CODE_PREPARAR_CONTEUDO }, { x: 1320, y: 160 }),

  node('OpenAI Classificar', 'n8n-nodes-base.httpRequest', 4.2, {
    method: 'POST', url: 'https://api.openai.com/v1/chat/completions',
    sendHeaders: true, headerParameters: { parameters: [
      { name: 'Authorization', value: '=Bearer {{ $env.OPENAI_API_KEY }}' },
      { name: 'Content-Type', value: 'application/json' },
    ] },
    sendBody: true, specifyBody: 'json',
    jsonBody: "={{ JSON.stringify($json.openai_body) }}",
  }, { x: 1540, y: 160 }),

  node('Parse OpenAI', 'n8n-nodes-base.code', 2, { jsCode: CODE_PARSE_OPENAI }, { x: 1760, y: 160 }),

  node('Registrar Documento', 'n8n-nodes-base.postgres', 2.5, {
    operation: 'executeQuery',
    query: "select fn_registrar_documento($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13) as documento_id",
    options: { queryReplacement: "={{ [$json.caso_id, $json.entidade || null, $json.periodo_tipo || null, $json.periodo_ref || null, $json.tipo_taxonomia || null, $json.confianca, $json.fonte, 'supabase_storage', $json.caso_id + '/' + $json.nome_original, $json.nome_original, $json.assinado, null, 'ok'] }}" },
  }, { x: 1980, y: 300, credentials: { postgres: { id: 'REPLACE', name: 'Supabase Postgres (Session Pooler)' } } }),

  node('Recomputar Completude', 'n8n-nodes-base.postgres', 2.5, {
    operation: 'executeQuery',
    query: "select fn_recomputar_completude($1) as resultado",
    options: { queryReplacement: "={{ $json.caso_id }}" },
  }, { x: 2200, y: 300, credentials: { postgres: { id: 'REPLACE', name: 'Supabase Postgres (Session Pooler)' } } }),
];

const connections = {
  'Intake (Form)': { main: [[{ node: 'Upsert Caso (Postgres)', type: 'main', index: 0 }]] },
  'Upsert Caso (Postgres)': { main: [[{ node: 'Listar Arquivos', type: 'main', index: 0 }]] },
  'Listar Arquivos': { main: [[{ node: 'Upload Storage', type: 'main', index: 0 }]] },
  'Upload Storage': { main: [[{ node: 'Classificar Nome', type: 'main', index: 0 }]] },
  'Classificar Nome': { main: [[{ node: 'Precisa Fallback?', type: 'main', index: 0 }]] },
  'Precisa Fallback?': { main: [
    [{ node: 'Preparar Conteudo Fallback', type: 'main', index: 0 }], // true
    [{ node: 'Registrar Documento', type: 'main', index: 0 }], // false
  ] },
  'Preparar Conteudo Fallback': { main: [[{ node: 'OpenAI Classificar', type: 'main', index: 0 }]] },
  'OpenAI Classificar': { main: [[{ node: 'Parse OpenAI', type: 'main', index: 0 }]] },
  'Parse OpenAI': { main: [[{ node: 'Registrar Documento', type: 'main', index: 0 }]] },
  'Registrar Documento': { main: [[{ node: 'Recomputar Completude', type: 'main', index: 0 }]] },
};

const workflow = {
  name: 'Oria — E1 Ingestão (Fatia 1)',
  nodes,
  connections,
  settings: { executionOrder: 'v1' },
  meta: { note: 'Gerado por n8n/build-workflow.mjs. Lógica dos nós Code espelha n8n/lib/ (testado).' },
};

const outPath = join(__dirname, 'workflow.e1-ingestao.json');
writeFileSync(outPath, JSON.stringify(workflow, null, 2) + '\n');
console.log('Escrito:', outPath, '—', nodes.length, 'nós');
