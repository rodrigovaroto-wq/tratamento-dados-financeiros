// Gera o workflow N8N da Fatia 1 (E1 ingestão + E2 extração em sombra).
// Rodar: node n8n/build-workflow.mjs  → escreve n8n/workflow.e1-ingestao.json
//
// A lógica dos nós Code ESPELHA os módulos testados em n8n/lib/ (fonte da verdade
// dos testes). Ao mudar a lógica: mude lib/, rode `npm test`, e regenere.
// O teste n8n/test/workflow-sim.test.mjs executa os códigos REAIS deste JSON
// com dados mock, simulando a passagem de dados node a node.
//
// REGRAS DE FLUXO (aprendidas testando no N8N real — não violar):
// 1. Node Postgres NÃO repassa binário: a saída são as linhas da query.
//    → Quem precisa dos arquivos lê do Form por referência: $('Intake (Form)').
// 2. Node HTTP Request SUBSTITUI o item pela resposta da API (perde json+binário).
//    → Upload Storage é RAMO LATERAL (nada depende da saída dele).
//    → Após chamadas OpenAI, o contexto volta por $('Nome do Node').item.
// 3. Code em 'runOnceForEachItem' retorna UM OBJETO {json,binary?}; em
//    'runOnceForAllItems' retorna ARRAY (único modo que permite fan-out).
// 4. Code que repassa arquivos deve devolver `binary` explicitamente
//    (retornar só {json} descarta o binário).

import { writeFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const __dirname = dirname(fileURLToPath(import.meta.url));

// Schemas estritos (mesma forma dos módulos lib/openai.mjs e lib/extract.mjs).
const SCHEMA_CLASSIF = `{name:'classificacao_documento',strict:true,schema:{type:'object',additionalProperties:false,required:['tipo_taxonomia','entidade','periodo_tipo','periodo_referencia','assinado','confianca','justificativa'],properties:{tipo_taxonomia:{type:'string'},entidade:{type:['string','null']},periodo_tipo:{type:'string'},periodo_referencia:{type:['string','null']},assinado:{type:['boolean','null']},confianca:{type:'number'},justificativa:{type:'string'}}}}`;
const SCHEMA_EXTRACAO = `{name:'extracao_linhas_financeiras',strict:true,schema:{type:'object',additionalProperties:false,required:['moeda','unidade','linhas'],properties:{moeda:{type:['string','null']},unidade:{type:['string','null']},linhas:{type:'array',items:{type:'object',additionalProperties:false,required:['chave','valor_texto','valor_num','origem_pagina','confianca'],properties:{chave:{type:'string'},valor_texto:{type:['string','null']},valor_num:{type:['number','null']},origem_pagina:{type:['integer','null']},confianca:{type:'number'}}}}}}}`;

// --- Code (ALL ITEMS — fan-out): um item por arquivo enviado no Form ---
// Binário vem do FORM (o Postgres anterior não o repassa). Chave normalizada
// para 'data' (o Upload Storage usa esse nome fixo).
const CODE_LISTAR = `
const caso_id = $('Upsert Caso (Postgres)').first().json.caso_id;
const form = $('Intake (Form)').first();
const bin = form.binary || {};
const out = [];
for (const key of Object.keys(bin)) {
  out.push({ json: { caso_id, nome_original: bin[key].fileName || key, binary_key: 'data' }, binary: { data: bin[key] } });
}
if (out.length === 0) {
  throw new Error('Nenhum arquivo recebido do formulario (binario vazio). Confira o campo "Arquivos" do Form.');
}
return out;
`.trim();

// --- Code (EACH ITEM): classificação por nome (espelha lib/classifier.mjs) ---
// Preserva o binário (Preparar Conteudo e Upload precisam dele adiante).
const CODE_CLASSIFICAR = `
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
function parsePeriodo(t){let m=t.match(/\\b(\\d{1,2})m(\\d{2,4})\\b/);if(m&&Number(m[1])===12)return{tipo:'anual',referencia:'12M'+m[2].slice(-2)};m=t.match(/\\bl(\\d{1,2})m\\b/)||t.match(/\\b(\\d{2})\\s*meses\\b/);if(m)return{tipo:'multi',referencia:'L'+m[1]+'M'};m=t.match(/\\b([1-4])t(\\d{2,4})\\b/);if(m)return{tipo:'trimestre',referencia:m[1]+'T'+m[2].slice(-2)};const a=t.match(/\\b(20)?\\d{2}\\b/g);if(a&&a.length>=2)return{tipo:'multi',referencia:a.map(x=>x.slice(-2)).join(',')};return null;}
function parseTipo(t){for(const a of ALIASES){for(const termo of a.termos){if(t.includes(termo))return a.codigo;}}return null;}
const item=$input.item.json;
const t=normalize(item.nome_original);
const tipo=parseTipo(t), periodo=parsePeriodo(t);
const assinado=/\\bassinad[oa]s?\\b/.test(t)?true:null;
let conf=0; if(tipo)conf+=0.6; if(periodo)conf+=0.3; if(assinado===true)conf+=0.1; conf=Math.min(1,Number(conf.toFixed(2)));
return {json:{...item, tipo_taxonomia:tipo, periodo_tipo:periodo?periodo.tipo:null, periodo_ref:periodo?periodo.referencia:null, assinado, entidade:null, confianca:conf, fonte:'nome_arquivo', precisa_fallback_openai:(conf<0.7|| !tipo)}, binary: $input.item.binary};
`.trim();

// --- Code (EACH ITEM): prepara a parte de CONTEUDO (para todos os docs) ---
// pdf→file; imagem→image_url; csv→texto (parse inline); xlsx→nota (ver README).
// Preserva o binário (o Upload Storage roda como ramo a partir deste node).
const CODE_PREPARAR_CONTEUDO = `
const item=$input.item.json;
const bin=($input.item.binary||{})['data']||{};
const b64=bin.data||''; const mt=(bin.mimeType||'').toLowerCase();
function parseCsv(t){const L=String(t||'').split(/\\r?\\n/).filter(x=>x.trim()!=='');if(!L.length)return [];const sep=(L[0].match(/;/g)||[]).length>(L[0].match(/,/g)||[]).length?';':',';const h=L[0].split(sep).map(c=>c.trim());return L.slice(1).map(l=>{const c=l.split(sep);const o={};h.forEach((k,i)=>o[k||('col'+i)]=(c[i]||'').trim());return o;});}
function sheetTxt(rows,mr=50,mc=25){if(!rows.length)return '(planilha vazia)';const cols=Object.keys(rows[0]).slice(0,mc);const head=cols.join(' | ');const body=rows.slice(0,mr).map(r=>cols.map(c=>String(r[c]??'')).join(' | ')).join('\\n');const ex=rows.length>mr?('\\n... (+'+(rows.length-mr)+' linhas omitidas)'):'';return head+'\\n'+body+ex;}
let part;
if(/pdf/.test(mt)) part={type:'file',file:{filename:item.nome_original||'documento.pdf',file_data:'data:application/pdf;base64,'+b64}};
else if(mt.indexOf('image/')===0) part={type:'image_url',image_url:{url:'data:'+mt+';base64,'+b64}};
else if(/csv/.test(mt)||mt==='text/plain'){const txt=Buffer.from(b64,'base64').toString('utf-8');part={type:'text',text:sheetTxt(parseCsv(txt))};}
else if(/spreadsheetml|ms-excel|excel/.test(mt)) part={type:'text',text:'(XLSX: habilitar Extract From File no N8N p/ extrair texto — ver README. Nome: '+(item.nome_original||'')+')'};
else part={type:'text',text:'(conteudo nao suportado: '+mt+')'};
return {json:{...item, content_part: part, content_mime: mt}, binary: $input.item.binary};
`.trim();

// --- Code (EACH ITEM): monta corpo da chamada de CLASSIFICAÇÃO (fallback) ---
const CODE_REQ_CLASSIF = `
const item=$input.item.json;
const schema=${SCHEMA_CLASSIF};
const body={model:'gpt-4o',temperature:0,response_format:{type:'json_schema',json_schema:schema},messages:[
  {role:'system',content:'Classifique o documento financeiro na taxonomia da Oria (Reestruturacao, Brasil). Periodos: 12M25=ano 2025; 1T25=1o tri/2025; L24M=ultimos 24 meses; 23,24,25=multiplos exercicios. Se incerto use DESCONHECIDO e confianca baixa. Nunca invente.'},
  {role:'user',content:[{type:'text',text:'Nome (pista fraca): '+(item.nome_original||'')}, item.content_part]}
]};
return {json:{...item, openai_body: body}};
`.trim();

// --- Code (EACH ITEM): parse da classificação -----------------------------
// Contexto vem do node anterior por referência (a resposta HTTP substituiu o
// item). Remove os campos pesados (openai_body/content_part) do que segue.
const CODE_PARSE_CLASSIF = `
const src=$('Montar Req Classif').item.json;
const {openai_body, content_part, content_mime, ...item}=src;
const resp=$json;
const content=resp?.choices?.[0]?.message?.content;
if(!content){return {json:{...item, fonte:'openai_conteudo', confianca:0}};}
let p; try{p=typeof content==='string'?JSON.parse(content):content;}catch(e){return {json:{...item, fonte:'openai_conteudo', confianca:0}};}
return {json:{...item,
  tipo_taxonomia:p.tipo_taxonomia==='DESCONHECIDO'?null:p.tipo_taxonomia,
  entidade:p.entidade??item.entidade??null,
  periodo_tipo:p.periodo_referencia?p.periodo_tipo:null,
  periodo_ref:p.periodo_referencia??null,
  assinado:p.assinado??null,
  confianca:typeof p.confianca==='number'?p.confianca:0,
  fonte:'openai_conteudo', justificativa:p.justificativa||''}};
`.trim();

// --- Code (EACH ITEM): monta corpo da chamada de EXTRAÇÃO (E2, sombra) -----
// $json vem do Registrar Documento (linha {r:{documento_id, documento_versao_id}}).
// O conteúdo do arquivo volta por referência ao Preparar Conteudo.
const CODE_REQ_EXTRACAO = `
const reg=$json;
const versaoId=(reg.r&&reg.r.documento_versao_id)||reg.documento_versao_id||null;
const prep=$('Preparar Conteudo').item.json;
const schema=${SCHEMA_EXTRACAO};
const body={model:'gpt-4o',temperature:0,response_format:{type:'json_schema',json_schema:schema},messages:[
  {role:'system',content:'Extraia LINHAS FINANCEIRAS (rotulo + valor). valor_num = numero puro quando houver, senao null. Informe unidade e pagina. NAO invente linhas nem valores; omita o ilegivel.'},
  {role:'user',content:[{type:'text',text:'Tipo (dica): '+(prep.tipo_taxonomia||'desconhecido')+'. Extraia as linhas financeiras.'}, prep.content_part]}
]};
return {json:{documento_versao_id:versaoId, tipo:prep.tipo_taxonomia||null, openai_body:body}};
`.trim();

// --- Code (EACH ITEM): parse da extração → campos p/ fn_registrar_campos ---
const CODE_PARSE_EXTRACAO = `
const ctx=$('Montar Req Extracao').item.json;
const resp=$json;
const content=resp?.choices?.[0]?.message?.content;
let p={}; try{p=content?(typeof content==='string'?JSON.parse(content):content):{};}catch(e){p={};}
const unidade=p.unidade??null;
const campos=Array.isArray(p.linhas)?p.linhas.map(l=>({chave:l.chave, valor_texto:l.valor_texto??null, valor_num:(typeof l.valor_num==='number')?l.valor_num:null, unidade, confianca:(typeof l.confianca==='number')?l.confianca:null, origem_pagina:Number.isInteger(l.origem_pagina)?l.origem_pagina:null})):[];
return {json:{documento_versao_id:ctx.documento_versao_id, campos}};
`.trim();

const PG_CRED = { postgres: { id: 'REPLACE', name: 'Supabase Postgres (Session Pooler)' } };
const node = (name, type, typeVersion, parameters, x, yy, opts = {}) => ({
  parameters, id: name.toLowerCase().replace(/[^a-z0-9]+/g, '-'), name, type, typeVersion,
  position: [x, yy],
  ...(opts.credentials ? { credentials: opts.credentials } : {}),
  ...(opts.onError ? { onError: opts.onError } : {}),
});

const nodes = [
  node('Intake (Form)', 'n8n-nodes-base.formTrigger', 2, {
    formTitle: 'Intake Oria — Reestruturação',
    formDescription: 'Suba TODOS os arquivos brutos do mandato de uma vez.',
    formFields: { values: [
      { fieldLabel: 'Mandato (nome do caso)', fieldType: 'text', requiredField: true },
      { fieldLabel: 'Arquivos', fieldType: 'file', multipleFiles: true, requiredField: true },
    ] },
  }, 0, 400),

  node('Upsert Caso (Postgres)', 'n8n-nodes-base.postgres', 2.5, {
    operation: 'executeQuery', query: 'select fn_upsert_caso($1::text) as caso_id',
    options: { queryReplacement: "={{ [$json['Mandato (nome do caso)']] }}" },
  }, 200, 400, { credentials: PG_CRED }),

  node('Listar Arquivos', 'n8n-nodes-base.code', 2, { mode: 'runOnceForAllItems', jsCode: CODE_LISTAR }, 400, 400),

  node('Classificar Nome', 'n8n-nodes-base.code', 2, { mode: 'runOnceForEachItem', jsCode: CODE_CLASSIFICAR }, 600, 400),

  node('Preparar Conteudo', 'n8n-nodes-base.code', 2, { mode: 'runOnceForEachItem', jsCode: CODE_PREPARAR_CONTEUDO }, 800, 400),

  // RAMO LATERAL: nada depende da saída deste node (HTTP substitui o item).
  // Sem $env (bloqueado por padrão no N8N): auth via credencial Header Auth
  // (Authorization: Bearer <service key>) e URL do projeto editada no node
  // após o import (trocar SEU-PROJETO pela ref real).
  node('Upload Storage', 'n8n-nodes-base.httpRequest', 4.2, {
    method: 'POST',
    url: '=https://SEU-PROJETO.supabase.co/storage/v1/object/documentos/{{ $json.caso_id }}/{{ encodeURIComponent($json.nome_original) }}',
    authentication: 'genericCredentialType',
    genericAuthType: 'httpHeaderAuth',
    sendHeaders: true, headerParameters: { parameters: [
      { name: 'x-upsert', value: 'true' },
    ] },
    sendBody: true, contentType: 'binaryData', inputDataFieldName: 'data',
  }, 1000, 560, { credentials: { httpHeaderAuth: { id: 'REPLACE', name: 'Supabase Service (Header Auth)' } } }),

  node('Precisa Fallback?', 'n8n-nodes-base.if', 2, {
    conditions: { options: { caseSensitive: true, typeValidation: 'strict' }, combinator: 'and', conditions: [
      { leftValue: '={{ $json.precisa_fallback_openai }}', rightValue: true, operator: { type: 'boolean', operation: 'true', singleValue: true } },
    ] },
  }, 1000, 300),

  node('Montar Req Classif', 'n8n-nodes-base.code', 2, { mode: 'runOnceForEachItem', jsCode: CODE_REQ_CLASSIF }, 1200, 200),

  // Falha da OpenAI NÃO derruba o workflow: segue com a resposta de erro, o
  // Parse produz confiança 0 → pendência de classificação (fail-safe).
  // Auth via credencial Header Auth (Name=Authorization, Value=Bearer sk-...),
  // o setup real do dono — sem $env (bloqueado por padrão no N8N).
  node('OpenAI Classificar', 'n8n-nodes-base.httpRequest', 4.2, {
    method: 'POST', url: 'https://api.openai.com/v1/chat/completions',
    authentication: 'genericCredentialType',
    genericAuthType: 'httpHeaderAuth',
    sendBody: true, specifyBody: 'json', jsonBody: '={{ JSON.stringify($json.openai_body) }}',
  }, 1400, 200, { onError: 'continueRegularOutput', credentials: { httpHeaderAuth: { id: 'REPLACE', name: 'OpenAI API' } } }),

  node('Parse OpenAI Classif', 'n8n-nodes-base.code', 2, { mode: 'runOnceForEachItem', jsCode: CODE_PARSE_CLASSIF }, 1600, 200),

  node('Registrar Documento', 'n8n-nodes-base.postgres', 2.5, {
    operation: 'executeQuery',
    query: 'select fn_registrar_documento($1::uuid,$2::text,$3::text,$4::text,$5::text,$6::numeric,$7::text,$8::origem_arquivo,$9::text,$10::text,$11::boolean,$12::text,$13::legibilidade) as r',
    options: { queryReplacement: "={{ [$json.caso_id, $json.entidade || null, $json.periodo_tipo || null, $json.periodo_ref || null, $json.tipo_taxonomia || null, $json.confianca, $json.fonte, 'supabase_storage', $json.caso_id + '/' + $json.nome_original, $json.nome_original, $json.assinado, null, 'ok'] }}" },
  }, 1850, 400, { credentials: PG_CRED }),

  node('Recomputar Completude', 'n8n-nodes-base.postgres', 2.5, {
    operation: 'executeQuery', query: 'select fn_recomputar_completude($1::uuid) as resultado',
    options: { queryReplacement: "={{ $('Upsert Caso (Postgres)').first().json.caso_id }}" },
  }, 2100, 560, { credentials: PG_CRED }),

  node('Montar Req Extracao', 'n8n-nodes-base.code', 2, { mode: 'runOnceForEachItem', jsCode: CODE_REQ_EXTRACAO }, 2100, 300),

  node('OpenAI Extrair', 'n8n-nodes-base.httpRequest', 4.2, {
    method: 'POST', url: 'https://api.openai.com/v1/chat/completions',
    authentication: 'genericCredentialType',
    genericAuthType: 'httpHeaderAuth',
    sendBody: true, specifyBody: 'json', jsonBody: '={{ JSON.stringify($json.openai_body) }}',
  }, 2300, 300, { onError: 'continueRegularOutput', credentials: { httpHeaderAuth: { id: 'REPLACE', name: 'OpenAI API' } } }),

  node('Parse Extracao', 'n8n-nodes-base.code', 2, { mode: 'runOnceForEachItem', jsCode: CODE_PARSE_EXTRACAO }, 2500, 300),

  node('Gravar Campos (Sombra)', 'n8n-nodes-base.postgres', 2.5, {
    operation: 'executeQuery',
    query: 'select fn_registrar_campos_extraidos($1::uuid, $2::jsonb) as n_campos',
    options: { queryReplacement: "={{ [$json.documento_versao_id, JSON.stringify($json.campos)] }}" },
  }, 2700, 300, { credentials: PG_CRED }),
];

const connections = {
  'Intake (Form)': { main: [[{ node: 'Upsert Caso (Postgres)', type: 'main', index: 0 }]] },
  'Upsert Caso (Postgres)': { main: [[{ node: 'Listar Arquivos', type: 'main', index: 0 }]] },
  'Listar Arquivos': { main: [[{ node: 'Classificar Nome', type: 'main', index: 0 }]] },
  'Classificar Nome': { main: [[{ node: 'Preparar Conteudo', type: 'main', index: 0 }]] },
  // fan-out: upload (lateral) + decisão de fallback (cadeia principal)
  'Preparar Conteudo': { main: [[
    { node: 'Upload Storage', type: 'main', index: 0 },
    { node: 'Precisa Fallback?', type: 'main', index: 0 },
  ]] },
  'Precisa Fallback?': { main: [
    [{ node: 'Montar Req Classif', type: 'main', index: 0 }],   // true
    [{ node: 'Registrar Documento', type: 'main', index: 0 }],  // false
  ] },
  'Montar Req Classif': { main: [[{ node: 'OpenAI Classificar', type: 'main', index: 0 }]] },
  'OpenAI Classificar': { main: [[{ node: 'Parse OpenAI Classif', type: 'main', index: 0 }]] },
  'Parse OpenAI Classif': { main: [[{ node: 'Registrar Documento', type: 'main', index: 0 }]] },
  'Registrar Documento': { main: [[
    { node: 'Recomputar Completude', type: 'main', index: 0 },
    { node: 'Montar Req Extracao', type: 'main', index: 0 },
  ]] },
  'Montar Req Extracao': { main: [[{ node: 'OpenAI Extrair', type: 'main', index: 0 }]] },
  'OpenAI Extrair': { main: [[{ node: 'Parse Extracao', type: 'main', index: 0 }]] },
  'Parse Extracao': { main: [[{ node: 'Gravar Campos (Sombra)', type: 'main', index: 0 }]] },
};

const workflow = {
  name: 'Oria — E1 Ingestão + E2 Extração-Sombra (Fatia 1)',
  nodes, connections, settings: { executionOrder: 'v1' },
  meta: { note: 'Gerado por n8n/build-workflow.mjs. Nós Code espelham n8n/lib/ (testado). E2 em N0/sombra.' },
};

writeFileSync(join(__dirname, 'workflow.e1-ingestao.json'), JSON.stringify(workflow, null, 2) + '\n');
console.log('Escrito workflow —', nodes.length, 'nós,', Object.keys(connections).length, 'conexões');
