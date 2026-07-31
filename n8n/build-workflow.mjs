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
import { codigosConhecidos } from './lib/openai.mjs';
import { SECAO_CANONICA_ENUM, SYSTEM_PROMPT, diagnosticarErroApi, MAX_OUTPUT_TOKENS, TPM_CONTA, normalizarUnidade } from './lib/extract.mjs';
import { ALIASES } from './lib/taxonomia.mjs';
import { parseEntidade } from './lib/classifier.mjs';
import { orcamentoDoLote, TETO_EXECUCAO_USD, CUSTO_ESTIMADO_DOC_USD, custoDaChamada, PRECO_USD_POR_MILHAO } from './lib/custo.mjs';
import { sha256Hex } from './lib/hash.mjs';

const __dirname = dirname(fileURLToPath(import.meta.url));

// Enums da classificação — IMPORTADOS de lib/openai.mjs (fonte única), não
// copiados à mão: um mirror manual desses códigos já ficou desatualizado uma
// vez (permitindo a OpenAI inventar "BAL" em vez de "BALANCO", sem nenhum
// enum travando a saída) e só foi pego testando com documento real no N8N.
const TIPO_TAXONOMIA_ENUM = JSON.stringify(codigosConhecidos());
const PERIODO_TIPO_ENUM = JSON.stringify(['anual', 'trimestre', 'multi', 'data-base', 'outro', 'desconhecido']);

// Apelidos por código da taxonomia — IMPORTADOS de lib/taxonomia.mjs pelo mesmo
// motivo dos enums acima, e aqui o mirror manual JÁ TINHA DIVERGIDO: a cópia à
// mão parava em BALANCETE e o nó real do workflow não conhecia DF_AUDITADA,
// MAPA_DIVIDA, EXTRATO_BANCARIO, AGING_AR/AP, ESTOQUE, CERTIDOES, CONTINGENCIAS,
// SITUACAO_FISCAL, ORGANOGRAMA, RAZAO nem NOTAS_EXPL. Em produção esses arquivos
// saíam do passe de nome SEM TIPO — a classificação por nome existe justamente
// para não gastar uma chamada de IA com o que o nome já diz. `n8n/test/
// workflow-sim.test.mjs` agora compara as duas listas e falha se voltarem a
// divergir. A ORDEM da lista é significativa (regra específica antes da genérica)
// e serializar preserva ela.
const ALIASES_JSON = JSON.stringify(ALIASES);

// Modelos das DUAS chamadas, num lugar só (antes 'gpt-4o' estava hardcoded em
// cada nó). A classificação por CONTEÚDO é a tarefa mais leve do pipeline (só
// escolhe um código de um enum + entidade/período) e só roda quando o nome do
// arquivo não dá confiança >= 0.7; a extração linha a linha é a tarefa pesada.
// Separar os dois permite trocar SÓ a classificação por um modelo mais barato
// (ex.: 'gpt-4o-mini') sem tocar na extração — a troca é uma linha aqui +
// `node build-workflow.mjs`. Ver docs/CUSTO_OPENAI.md antes de mudar: a
// classificação tem rede de segurança (o diagnóstico da extração confere
// tipo/entidade/período e abre pendência quando diverge), a extração NÃO tem.
const MODEL_CLASSIFICACAO = 'gpt-4o';
const MODEL_EXTRACAO = 'gpt-4o';

// Schemas estritos (mesma forma dos módulos lib/openai.mjs e lib/extract.mjs).
const SCHEMA_CLASSIF = `{name:'classificacao_documento',strict:true,schema:{type:'object',additionalProperties:false,required:['tipo_taxonomia','entidade','periodo_tipo','periodo_referencia','assinado','confianca','justificativa'],properties:{tipo_taxonomia:{type:'string',enum:${TIPO_TAXONOMIA_ENUM}},entidade:{type:['string','null']},periodo_tipo:{type:'string',enum:${PERIODO_TIPO_ENUM}},periodo_referencia:{type:['string','null']},assinado:{type:['boolean','null']},confianca:{type:'number',minimum:0,maximum:1},justificativa:{type:'string'}}}}`;
// Diagnóstico (entidade/confere tipo+período/legibilidade/resumo) + linhas
// com `secao` (agrupador de planilha) — mesma chamada que já rodava sempre
// para extrair linhas (não aumenta o nº de chamadas à OpenAI); espelha
// n8n/lib/extract.mjs (fonte da verdade).
const LEGIBILIDADE_ENUM = JSON.stringify(['ok', 'degradado', 'ilegivel']);
const SECAO_CANONICA_ENUM_JSON = JSON.stringify(SECAO_CANONICA_ENUM);
const SCHEMA_EXTRACAO = `{name:'diagnostico_e_extracao',strict:true,schema:{type:'object',additionalProperties:false,required:['moeda','unidade','diagnostico','linhas'],properties:{moeda:{type:['string','null']},unidade:{type:['string','null']},diagnostico:{type:'object',additionalProperties:false,required:['entidade','tipo_confirma','tipo_sugerido','periodo_tipo','periodo_referencia','legibilidade','nota_legibilidade','resumo','justificativa'],properties:{entidade:{type:['string','null']},tipo_confirma:{type:'boolean'},tipo_sugerido:{type:'string',enum:${TIPO_TAXONOMIA_ENUM}},periodo_tipo:{type:'string',enum:${PERIODO_TIPO_ENUM}},periodo_referencia:{type:['string','null']},legibilidade:{type:'string',enum:${LEGIBILIDADE_ENUM}},nota_legibilidade:{type:['string','null']},resumo:{type:'string'},justificativa:{type:'string'}}},linhas:{type:'array',items:{type:'object',additionalProperties:false,required:['s','sc','ec','pc','k','vt','vn','op','cf'],properties:{s:{type:['string','null'],description:'secao: agrupador livre (rótulo do próprio documento)'},sc:{type:'string',enum:${SECAO_CANONICA_ENUM_JSON},description:'secao_canonica: seção padronizada pelo significado contábil'},ec:{type:['string','null'],description:'entidade_coluna: nome da coluna/empresa quando há várias entidades lado a lado'},pc:{type:['string','null'],description:'periodo_coluna: rótulo da coluna de período quando há vários períodos lado a lado'},k:{type:'string',description:'chave: rótulo da conta'},vt:{type:['string','null'],description:'valor_texto: valor como aparece no documento'},vn:{type:['number','null'],description:'valor_num: valor numérico puro'},op:{type:['integer','null'],description:'origem_pagina: página de origem'},cf:{type:'number',description:'confianca: confiança 0-1 desta linha'}}}}}}}`;

// `diagnosticarErroApi` é EMBUTIDA a partir do fonte de lib/extract.mjs (fonte
// única — o nó Code do n8n não importa arquivo, e cópia à mão neste repositório
// já divergiu duas vezes). A função é auto-contida justamente para o toString()
// bastar; `workflow-sim.test.mjs` confere que o nó carrega este mesmo código.
const FONTE_DIAGNOSTICO_ERRO = `const diagnosticarErroApi = ${diagnosticarErroApi.toString()};`;

// `parseEntidade` idem — embutida do fonte, não espelhada à mão. Ela é a correção
// do achado do "teste v31" (entidade "—" nos 14 documentos porque o nome do
// arquivo nunca era lido para isso); ver o comentário longo em lib/classifier.mjs
// para por que ela NÃO mexe na confiança.
const FONTE_PARSE_ENTIDADE = `const parseEntidade = ${parseEntidade.toString()};`;

// `normalizarUnidade` — o mirror manual que ficou de fora quando todos os outros
// passaram a ser embutidos, e que JÁ DIVERGIU. A cópia à mão em `normUnid` perdeu
// a última cláusula da fonte:
//
//     if (t === '1' || t === '1.000' || t === '1000') return t === '1' ? 'unidade' : 'milhar';
//
// Divergência MEDIDA (não estimada): em 13 redações de escala testadas, 3 diferem —
// quando a célula é EXATAMENTE o multiplicador (`1.000`, `1000`, `1`), que é como
// um cabeçalho de coluna costuma declarar a escala. A lib devolve
// `milhar`/`milhar`/`unidade`; o nó em produção devolvia `null` nos três.
//
// Por que `null` é caro aqui: escala nula não é neutra. `fn_valor_em_base`
// (0023:127) multiplica por `coalesce(fn_fator_escala(...), 1)`, então escala
// desconhecida é tratada como UNIDADE — e comparar milhar com unidade erra por
// 1000x. O comentário da própria fonte diz "errar em 1000x é pior que não saber";
// perder a escala silenciosamente entrega exatamente esse 1000x.
const FONTE_NORMALIZAR_UNIDADE = `const normUnid = ${normalizarUnidade.toString()};`;

// Idem para o orçamento e para o custo real — embutidos do fonte, nunca copiados.
const FONTE_ORCAMENTO_LOTE = `const orcamentoDoLote = ${orcamentoDoLote.toString()};`;

// `sha256Hex` idem — embutida do fonte. Ela substituiu a dependência de
// `crypto.subtle`, que o dono MEDIU vindo ausente no sandbox do n8n dele
// (campo `hash` = null na saída de `Preparar Conteudo`, 2026-07-31); ver o
// cabeçalho de lib/hash.mjs.
const FONTE_SHA256 = `const sha256Hex = ${sha256Hex.toString()};`;
const FONTE_CUSTO_CHAMADA = `const PRECO_USD_POR_MILHAO = ${JSON.stringify(PRECO_USD_POR_MILHAO)};
const custoDaChamada = ${custoDaChamada.toString()};`;

// --- Code (ALL ITEMS): o TETO DE GASTO POR EXECUÇÃO -------------------------
// Roda depois de `Classificar Nome` e antes de `Preparar Conteudo`, e o lugar é
// o ponto todo: aqui o número de chamadas do lote é EXATO (cada item já sabe se
// `precisa_fallback_openai`), e nada foi enviado à OpenAI nem gravado no banco.
// Barrar aqui custa zero; barrar depois é o v31 — 8 documentos registrados sem
// extração porque o teto da OpenAI cortou no meio.
//
// Por que contar as chamadas em vez dos documentos: um documento cujo nome não
// resolve o tipo paga o PDF DUAS vezes (classificação por conteúdo + extração).
// No v31 isso valia para 8 dos 14 — 22 chamadas num lote de 14 documentos, que
// com este teto de US$ 3 teria sido RECUSADO antes de gastar. Depois de renomear
// para a notação de f0/03 (`12M25`/`L24M`), o mesmo lote são 14 chamadas e passa.
const CODE_ORCAMENTO = `
${FONTE_ORCAMENTO_LOTE}
const itens = $input.all();
const comFallback = itens.filter(i => i.json.precisa_fallback_openai).length;
const chamadas = itens.length + comFallback;
const r = orcamentoDoLote({ documentos: itens.length, chamadasPorDocumento: chamadas / itens.length, teto: ${TETO_EXECUCAO_USD}, custoPorChamada: ${CUSTO_ESTIMADO_DOC_USD} });
// Recusa o lote INTEIRO. Não existe "roda os que cabem" de propósito: metade
// registrada sem extração e metade sem registro nenhum é estado que dá mais
// trabalho para desfazer do que o reenvio que esta mensagem pede.
if (!r.cabe) throw new Error(r.mensagem);
return itens.map(i => ({ json: { ...i.json, orcamento_estimado_usd: r.estimadoUSD, orcamento_teto_usd: r.teto, orcamento_chamadas: r.chamadas }, binary: i.binary }));
`.trim();

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
const ALIASES=${ALIASES_JSON};
function parsePeriodo(t0){const t=String(t0||'').replace(/^\\s*\\d{1,3}\\s*[-_. ]+/,'').replace(/(\\d)\\s*[x\\u00d7]\\s*(\\d)/g,'$1 $2');let m=t.match(/\\b(\\d{1,2})m(\\d{2,4})\\b/);if(m&&Number(m[1])===12)return{tipo:'anual',referencia:'12M'+m[2].slice(-2)};m=t.match(/\\bl(\\d{1,2})m\\b/)||t.match(/\\b(\\d{2})\\s*meses\\b/);if(m)return{tipo:'multi',referencia:'L'+m[1]+'M'};m=t.match(/\\b([1-4])t(\\d{2,4})\\b/);if(m)return{tipo:'trimestre',referencia:m[1]+'T'+m[2].slice(-2)};m=t.match(/\\b(20\\d{2}|\\d{2})\\s*(?:-|–|a)\\s*(20\\d{2}|\\d{2})\\b/);if(m){const full=y=>y.length===2?'20'+y:y;const start=Number(full(m[1])),end=Number(full(m[2]));if(start<=end&&end-start<=50){const anos=[];for(let y=start;y<=end;y++)anos.push(String(y).slice(-2));return{tipo:'multi',referencia:anos.join(',')};}}const a4=t.match(/\\b(19|20)\\d{2}\\b/g);if(a4&&a4.length===1)return{tipo:'anual',referencia:a4[0],fraco:true};if(a4&&a4.length>=2)return{tipo:'multi',referencia:a4.map(x=>x.slice(-2)).sort().join(',')};const a=t.match(/\\b(20)?\\d{2}\\b/g);if(a&&a.length>=2)return{tipo:'multi',referencia:a.map(x=>x.slice(-2)).join(',')};if(a&&a.length===1&&/^(19|20)\\d{2}$/.test(a[0]))return{tipo:'anual',referencia:a[0],fraco:true};return null;}
function parseTipo(t){for(const a of ALIASES){for(const termo of a.termos){if(t.includes(termo))return a.codigo;}}return null;}
${FONTE_PARSE_ENTIDADE}
const item=$input.item.json;
const t=normalize(item.nome_original);
const tipo=parseTipo(t), periodo=parsePeriodo(t);
const assinado=/\\bassinad[oa]s?\\b/.test(t)?true:null;
let conf=0; if(tipo)conf+=0.6; if(periodo)conf+=(periodo.fraco?0.05:0.3); if(assinado===true)conf+=0.1; conf=Math.min(1,Number(conf.toFixed(2)));
return {json:{...item, tipo_taxonomia:tipo, periodo_tipo:periodo?periodo.tipo:null, periodo_ref:periodo?periodo.referencia:null, assinado, entidade:parseEntidade(t,ALIASES), confianca:conf, fonte:'nome_arquivo', precisa_fallback_openai:(conf<0.7|| !tipo)}, binary: $input.item.binary};
`.trim();

// --- Code (EACH ITEM): prepara a parte de CONTEUDO (para todos os docs) ---
// pdf→file; imagem→image_url; csv→texto (parse inline); xlsx→nota (ver README).
// Preserva o binário (o Upload Storage roda como ramo a partir deste node).
const CODE_PREPARAR_CONTEUDO = `
${FONTE_SHA256}
const item=$input.item.json;
const binMeta=($input.item.binary||{})['data']||{};
const mt=(binMeta.mimeType||'').toLowerCase();
// NUNCA ler binMeta.data direto: se o N8N estiver em modo de binario "filesystem"
// (ou S3), esse campo NAO e' a base64 -- e' so' uma referencia interna (ex.:
// "filesystem-v2"), e a IA acaba recebendo um PDF invalido sem avisar (achado
// testando com documento real: a OpenAI so' "leu" o nome do arquivo, porque o
// file_data enviado era lixo). O helper resolve os dois modos corretamente.
// No runtime de Task Runner (padrao a partir do N8N 1.x/2.x self-hosted) o
// global $helpers NAO existe -- e' this.helpers (doc oficial n8n, cookbook
// "Get the binary data buffer").
// BUG REAL (achado testando com 2 arquivos no mesmo lote, 2026-07-22): o
// indice NAO e' sempre 0. Mesmo em each-item mode, getBinaryDataBuffer
// resolve o buffer pelo indice do item DENTRO DO LOTE inteiro do node (e' a
// forma como a referencia interna de binario vira bytes de verdade) -- nao
// pelo item que o closure do JS acha que esta processando. Com 0 fixo, todo
// item != 0 lia o BINARIO DO ITEM 0 (mimeType/nome do proprio item batiam,
// mas o CONTEUDO enviado pra IA era de outro arquivo) -- so' nao aparecia
// com upload de 1 arquivo por vez, onde o unico item e' sempre indice 0. Usa
// $itemIndex (global do N8N em each-item mode: indice do item corrente no
// lote) em vez do literal 0.
const buf=await this.helpers.getBinaryDataBuffer($itemIndex,'data');
const b64=buf.toString('base64');
function parseCsv(t){const L=String(t||'').split(/\\r?\\n/).filter(x=>x.trim()!=='');if(!L.length)return [];const sep=(L[0].match(/;/g)||[]).length>(L[0].match(/,/g)||[]).length?';':',';const h=L[0].split(sep).map(c=>c.trim());return L.slice(1).map(l=>{const c=l.split(sep);const o={};h.forEach((k,i)=>o[k||('col'+i)]=(c[i]||'').trim());return o;});}
function sheetTxt(rows,mr=50,mc=25){if(!rows.length)return '(planilha vazia)';const cols=Object.keys(rows[0]).slice(0,mc);const head=cols.join(' | ');const body=rows.slice(0,mr).map(r=>cols.map(c=>String(r[c]??'')).join(' | ')).join('\\n');const ex=rows.length>mr?('\\n... (+'+(rows.length-mr)+' linhas omitidas)'):'';return head+'\\n'+body+ex;}
let part;
if(/pdf/.test(mt)) part={type:'file',file:{filename:item.nome_original||'documento.pdf',file_data:'data:application/pdf;base64,'+b64}};
else if(mt.indexOf('image/')===0) part={type:'image_url',image_url:{url:'data:'+mt+';base64,'+b64}};
else if(/csv/.test(mt)||mt==='text/plain'){const txt=buf.toString('utf-8');part={type:'text',text:sheetTxt(parseCsv(txt))};}
else if(/spreadsheetml|ms-excel|excel/.test(mt)) part={type:'text',text:'(XLSX: habilitar Extract From File no N8N p/ extrair texto — ver README. Nome: '+(item.nome_original||'')+')'};
else part={type:'text',text:'(conteudo nao suportado: '+mt+')'};
// HASH DO CONTEUDO -- a idempotencia da 0026 dependia disto e nunca recebeu nada.
// A 0026 existe para reenvio do MESMO arquivo virar uma documento_versao nova sob
// o MESMO documento, em vez de documento novo. Como o pipeline mandava null no
// 12o elemento do queryReplacement de Registrar Documento, a condicao
// "p_hash is not null" nunca era verdade: todo reenvio duplicava o documento,
// inflava a completude e duplicava colunas no export -- o "15 colunas para 5
// empresas" do teste v27. O reextracao.test.sql provava a FUNCAO passando o hash
// a mao, e e' por isso que o gap ficou invisivel para a suite.
//
// Calculado AQUI porque este e' o unico no' que tem os bytes de verdade (o buffer
// acima, resolvido pelo helper).
//
// A primeira versao usava crypto.subtle e se ABSTINHA (hash null) se ele nao
// existisse. O dono conferiu a saida deste no' no n8n dele e o campo veio NULL:
// o Code node nao expoe crypto. A abstencao funcionou como projetada -- nao
// inventou hash fraco -- mas deixava a idempotencia da 0026 adormecida na
// pratica. Agora o SHA-256 vem de sha256Hex (JS puro, lib/hash.mjs), que nao
// depende de nada do ambiente; o caminho nativo fica so' como atalho de
// velocidade quando existe. MESMO algoritmo nos dois: nada de hash mais fraco,
// porque colisao aqui FUNDIRIA documentos diferentes -- "o erro mais caro
// possivel", nas palavras do cabecalho da 0026.
let hash=null;
try{
  if(typeof crypto!=='undefined'&&crypto&&crypto.subtle){
    const d=await crypto.subtle.digest('SHA-256',buf);
    hash=Array.from(new Uint8Array(d)).map(x=>x.toString(16).padStart(2,'0')).join('');
  }else{
    hash=sha256Hex(buf);
  }
}catch(e){
  // Ultimo recurso: se ate' o caminho nativo falhar (por qualquer motivo do
  // sandbox), tenta o JS puro antes de desistir. So' devolve null se os DOIS
  // falharem -- ai' sim nao saber e' melhor que errar.
  try{hash=sha256Hex(buf);}catch(e2){hash=null;}
}
return {json:{...item, content_part: part, content_mime: mt, hash}, binary: $input.item.binary};
`.trim();

// --- Code (EACH ITEM): monta corpo da chamada de CLASSIFICAÇÃO (fallback) ---
const CODE_REQ_CLASSIF = `
const item=$input.item.json;
const schema=${SCHEMA_CLASSIF};
const body={model:'${MODEL_CLASSIFICACAO}',temperature:0,response_format:{type:'json_schema',json_schema:schema},messages:[
  {role:'system',content:'Classifique o documento financeiro na taxonomia da Oria (Reestruturacao, Brasil). Periodos: 12M25=ano 2025; 1T25=1o tri/2025; L24M=ultimos 24 meses; 23,24,25=multiplos exercicios; ano isolado como 2025 tambem e valido. IMPORTANTE: sempre tente identificar o tipo mais provavel dentre os codigos conhecidos, mesmo com confianca baixa -- analise cabecalhos, rotulos de linhas, estrutura de colunas e demais pistas visuais. DESCONHECIDO e reservado somente para documentos genuinamente ilegiveis/corrompidos ou que claramente nao sao documentos financeiros. Baixa confianca nao e motivo para deixar de dar um palpite -- e motivo para registrar o palpite com confianca baixa correspondente e uma justificativa objetiva. Nunca invente valores (numeros, entidade, periodo) que nao estao no documento, mas sempre ofereca sua melhor hipotese de tipo. O campo justificativa e obrigatorio: explicacao objetiva e especifica (1-2 frases) do que voce viu (ou nao viu) no documento que sustenta a classificacao e a confianca escolhida -- evite respostas genericas como nao foi possivel determinar.'},
  {role:'user',content:[{type:'text',text:'Nome (pista fraca): '+(item.nome_original||'')}, item.content_part]}
]};
return {json:{...item, openai_body: body}};
`.trim();

// --- Code (EACH ITEM): parse da classificação -----------------------------
// Contexto vem do node anterior por referência (a resposta HTTP substituiu o
// item). Remove os campos pesados (openai_body/content_part) do que segue.
// Espelha n8n/lib/merge.mjs: fica com a MAIOR confiança entre nome-do-arquivo
// e IA (não sobrescreve cegamente); entidade/assinado da IA sempre aproveitados.
const CODE_PARSE_CLASSIF = `
${FONTE_DIAGNOSTICO_ERRO}
function mergeClassification(fromName, fromAI){
  const nameHasTipo=!!fromName.tipo_taxonomia, aiHasTipo=!!fromAI.tipo_taxonomia;
  let winner;
  if(aiHasTipo&&nameHasTipo) winner=(fromAI.confianca??0)>=(fromName.confianca??0)?fromAI:fromName;
  else if(aiHasTipo) winner=fromAI;
  else if(nameHasTipo) winner=fromName;
  else winner=fromAI;
  return {
    tipo_taxonomia:winner.tipo_taxonomia??null,
    periodo_tipo:fromAI.periodo_ref?fromAI.periodo_tipo:(fromName.periodo_ref?fromName.periodo_tipo:null),
    periodo_ref:fromAI.periodo_ref??fromName.periodo_ref??null,
    assinado:fromAI.assinado??fromName.assinado??null,
    entidade:fromAI.entidade??fromName.entidade??null,
    confianca:Math.max(fromName.confianca||0, fromAI.confianca||0),
    fonte:winner===fromAI?'openai_conteudo':'nome_arquivo',
    justificativa:fromAI.justificativa||'',
  };
}
const src=$('Montar Req Classif').item.json;
const {openai_body, content_part, content_mime, ...item}=src;
const resp=$json;
const content=resp?.choices?.[0]?.message?.content;
const fromName={tipo_taxonomia:item.tipo_taxonomia, periodo_tipo:item.periodo_tipo, periodo_ref:item.periodo_ref, assinado:item.assinado, entidade:item.entidade, confianca:item.confianca};
if(!content){
  // A classificação DEGRADA para o nome do arquivo quando a IA falha — e isso é
  // o certo (fail-safe). O que não pode é a justificativa dizer só "falha de
  // rede/API": no "teste v30" os 14 documentos ficaram classificados pelo nome
  // com essa frase genérica, enquanto a causa real era a OpenAI recusando TODA
  // chamada. A causa vai junto, com o mesmo diagnóstico da extração.
  const motivo=resp?.error?diagnosticarErroApi(resp.error).motivo:'A chamada a OpenAI nao retornou conteudo (falha de rede/API).';
  return {json:{...item, ...mergeClassification(fromName, {tipo_taxonomia:null, confianca:0, justificativa:'Classificacao por conteudo indisponivel, valeu o nome do arquivo. '+motivo})}};
}
let p; try{p=typeof content==='string'?JSON.parse(content):content;}catch(e){
  return {json:{...item, ...mergeClassification(fromName, {tipo_taxonomia:null, confianca:0, justificativa:'Resposta da OpenAI nao veio em JSON valido.'})}};
}
const fromAI={
  tipo_taxonomia:p.tipo_taxonomia==='DESCONHECIDO'?null:p.tipo_taxonomia,
  entidade:p.entidade??null,
  periodo_tipo:p.periodo_referencia?p.periodo_tipo:null,
  periodo_ref:p.periodo_referencia??null,
  assinado:p.assinado??null,
  confianca:typeof p.confianca==='number'?p.confianca:0,
  justificativa:p.justificativa||'',
};
return {json:{...item, ...mergeClassification(fromName, fromAI)}};
`.trim();

// --- Code (EACH ITEM): monta corpo da chamada de DIAGNÓSTICO+EXTRAÇÃO (E2) -
// $json vem do Registrar Documento (linha {r:{documento_id, documento_versao_id}}).
// O conteúdo do arquivo volta por referência ao Preparar Conteudo. Espelha
// n8n/lib/extract.mjs: SEMPRE roda (não só no fallback de baixa confiança) —
// é a ÚNICA leitura de conteúdo garantida para todo documento, por isso
// também busca entidade e faz o diagnóstico (confere tipo/período/legibilidade).
const CODE_REQ_EXTRACAO = `
const reg=$json;
const versaoId=(reg.r&&reg.r.documento_versao_id)||reg.documento_versao_id||null;
// SEM VERSAO, NAO SE MONTA REQUISICAO -- e' o que impede pagar por uma extracao
// que nao tem onde ser gravada.
//
// O caminho era real e caro: com PG_RETRY (onError: continueRegularOutput), quando
// "Registrar Documento" falha o item de erro segue adiante, versaoId virava null
// SEM sinalizar nada, a extracao era EXECUTADA (dinheiro gasto) e
// fn_registrar_campos_extraidos(null, ...) retornava 0 jogando fora o
// falha_motivo antes do Sinal 3. Documento inexistente, chamada paga, zero
// pendencia -- so' o log do n8n sabia. A 0029 fecha o lado do banco (registra em
// evento_auditoria em vez de descartar); esta guarda fecha o lado do DINHEIRO.
//
// Lancar aqui e' seguro porque este no' tem onError: o item vira item de erro, o
// lote CONTINUA, e nenhum token e' cobrado (o corpo nunca e' montado). O modo
// runOnceForEachItem nao permite devolver zero itens -- por isso guarda, nao filtro.
if(!versaoId){
  throw new Error('Documento nao registrado no banco (documento_versao_id ausente): a extracao NAO foi chamada, para nao gastar credito com um documento que nao existe. Causa provavel: falha no no "Registrar Documento" -- ver o log desta execucao.');
}
const prep=$('Preparar Conteudo').item.json;
const schema=${SCHEMA_EXTRACAO};
const promptSistema=${JSON.stringify(SYSTEM_PROMPT)};
const body={model:'${MODEL_EXTRACAO}',temperature:0,max_tokens:${MAX_OUTPUT_TOKENS},response_format:{type:'json_schema',json_schema:schema},messages:[
  {role:'system',content:promptSistema},
  {role:'user',content:[{type:'text',text:'Nome do arquivo: '+(prep.nome_original||'(sem nome)')+'. Dica de tipo (do nome, pode estar errada): '+(prep.tipo_taxonomia||'desconhecido')+'. Diagnostique e extraia as linhas financeiras.'}, prep.content_part]}
]};
return {json:{documento_versao_id:versaoId, tipo:prep.tipo_taxonomia||null, openai_body:body}};
`.trim();

// --- Code (EACH ITEM): parse do diagnóstico+extração → payload p/ Postgres -
// falha_motivo: espelha n8n/lib/extract.mjs parseExtractionResponse — null
// quando ok; motivo textual (vira pendencia 'extracao_falhou') quando a
// chamada errou, veio truncada (finish_reason 'length') ou o JSON é inválido.
// Sem isso, uma falha silenciosa grava 0 campos e ninguém fica sabendo
// (achado em produção, sessão 7 cont.⁷ — "teste v14").
const CODE_PARSE_EXTRACAO = `
${FONTE_DIAGNOSTICO_ERRO}
${FONTE_CUSTO_CHAMADA}
const ctx=$('Montar Req Extracao').item.json;
const resp=$json;
const finishReason=resp?.choices?.[0]?.finish_reason??null;
const content=resp?.choices?.[0]?.message?.content;
let p={}; let falhaMotivo=null;
if(resp?.error){
  falhaMotivo=diagnosticarErroApi(resp.error).motivo;
}else if(!content){
  falhaMotivo='Resposta da OpenAI sem conteudo (falha de rede/API).';
}else{
  try{p=typeof content==='string'?JSON.parse(content):content;}catch(e){
    falhaMotivo=(finishReason==='length')
      ?'Resposta da OpenAI truncada por limite de tokens de saida (finish_reason=length) -- o JSON ficou incompleto e nao pode ser interpretado. Documento provavelmente grande/denso demais (muitas contas/entidades) para uma unica chamada.'
      :'Resposta da OpenAI nao veio em JSON valido.';
    p={};
  }
}
if(!falhaMotivo&&finishReason==='length'){
  falhaMotivo='Resposta da OpenAI atingiu o limite de tokens de saida (finish_reason=length); o JSON veio valido, mas o conteudo pode estar incompleto (faltando linhas do fim do documento).';
}
${FONTE_NORMALIZAR_UNIDADE}
const unidade=normUnid(p.unidade);
function naoMonet(k,vt){const n=String(k??'').normalize('NFD').replace(/[\\u0300-\\u036f]/g,'').toLowerCase();return /%|\\bpercentual|\\bpor acao\\b|\\blpa\\b|\\bquantidade\\b|numero de acoes/.test(n)||String(vt??'').includes('%');}
const campos=Array.isArray(p.linhas)?p.linhas.map((l,i)=>({ordem:i, secao:l.s??null, secao_canonica:(l.sc&&l.sc!=='NAO_CLASSIFICAVEL')?l.sc:null, entidade_coluna:l.ec??null, periodo_coluna:l.pc??null, chave:l.k, valor_texto:l.vt??null, valor_num:(typeof l.vn==='number')?l.vn:null, unidade:naoMonet(l.k,l.vt)?null:unidade, confianca:(typeof l.cf==='number')?l.cf:null, origem_pagina:Number.isInteger(l.op)?l.op:null})):[];
const d=p.diagnostico||{};
const diagnostico={
  entidade: d.entidade??null,
  tipo_confirma: (typeof d.tipo_confirma==='boolean')?d.tipo_confirma:null,
  tipo_sugerido: d.tipo_sugerido==='DESCONHECIDO'?null:(d.tipo_sugerido??null),
  periodo_tipo: d.periodo_referencia?d.periodo_tipo:null,
  periodo_referencia: d.periodo_referencia??null,
  legibilidade: d.legibilidade??null,
  nota_legibilidade: d.nota_legibilidade??null,
  resumo: d.resumo??null,
  justificativa: d.justificativa??'',
};
// Custo REAL desta chamada, do bloco \`usage\` que a OpenAI devolve. Não vai
// para o banco (exigiria migration) — vai para a saída do nó, visível na
// execução do n8n. É com ele que CUSTO_ESTIMADO_DOC_USD deve ser recalibrado:
// hoje o teto de US$ 3 por execução decide em cima de uma ESTIMATIVA declarada,
// e trocar estimativa por medição é o único jeito honesto de apertar o teto.
const custo_usd=custoDaChamada(resp?.usage, '${MODEL_EXTRACAO}');
return {json:{documento_versao_id:ctx.documento_versao_id, campos, diagnostico, falha_motivo:falhaMotivo, custo_usd, tokens:resp?.usage?{entrada:resp.usage.prompt_tokens??null, saida:resp.usage.completion_tokens??null, cache:resp.usage.prompt_tokens_details?.cached_tokens??0}:null}};
`.trim();

const PG_CRED = { postgres: { id: 'REPLACE', name: 'Supabase Postgres (Session Pooler)' } };
const node = (name, type, typeVersion, parameters, x, yy, opts = {}) => ({
  parameters, id: name.toLowerCase().replace(/[^a-z0-9]+/g, '-'), name, type, typeVersion,
  position: [x, yy],
  ...(opts.credentials ? { credentials: opts.credentials } : {}),
  ...(opts.onError ? { onError: opts.onError } : {}),
  ...(opts.disabled ? { disabled: true } : {}),
  // Retry no nível do node (N8N): reexecuta o item que falhou antes de cair no
  // onError. waitBetweenTries tem teto de 5000ms no N8N. maxTries 6 (era 4,
  // cont.⁸): o "teste v18" mostrou que 4 tentativas não bastavam pros documentos
  // mais pesados (cont.¹¹).
  //
  // ⚠️ SUSPEITA FORTE, NÃO CONFIRMADA (achado ao investigar o v30, lendo o fonte
  // do n8n): com `onError: 'continueRegularOutput'` o nó NUNCA LANÇA — ele empurra
  // o item de erro adiante —, e se o retry do n8n depende do lançamento, então
  // `retryOnFail` nunca dispara nos nós OpenAI e as "6 tentativas" em que este
  // comentário confiava são ficção. Não confirmei contra o n8n do dono, e por isso
  // NÃO mexi na configuração: trocar `onError` para o retry funcionar traria de
  // volta o bug da sessão 7 cont.¹³ (um erro num item matando o lote inteiro em
  // silêncio), o que é pior que não ter retry. A verificação é de 1 minuto no n8n
  // vivo: a duração da execução diz se houve 1 passada ou 6 (ver HANDOFF).
  //
  // O que NÃO depende dessa dúvida: a cadência derivada do TPM (abaixo). Ela
  // dimensiona o lote para não estourar o balde na PRIMEIRA tentativa — que é a
  // única em que dá para confiar hoje.
  ...(opts.retryOnFail ? { retryOnFail: true, maxTries: opts.maxTries ?? 6, waitBetweenTries: opts.waitBetweenTries ?? 5000 } : {}),
});

// Batching do HTTP Request (N8N): processa `batchSize` itens, espera
// `batchInterval` ms, processa os próximos. Com um upload em lote de N
// documentos, sem isso o node dispara N chamadas à OpenAI praticamente
// simultâneas → estoura o rate limit (RPM/TPM), a API responde 429 e TODAS as
// extrações falham (achado em produção, sessão 7 cont.⁸ — "teste v15", 16
// documentos, 16 erros idênticos "Try spacing your requests out"). 1 por vez
// com intervalo espalha as chamadas no tempo (RPM e TPM).
//
// 3s (cont.⁸) reduziu bastante mas NÃO eliminou o 429: no "teste v18" (16
// documentos reais), os 3 que ainda deram 429 eram justamente os consolidados
// comparativos multi-ano (mais tokens de ENTRADA — o PDF é mais denso — e de
// SAÍDA — cada conta vira 2-3 linhas via periodo_coluna), que consomem TPM
// desproporcionalmente mais que os demais mesmo com a mesma cadência de
// requisições. 6s de intervalo + mais tentativas de retry dão mais folga pro
// balde de TPM da conta se recompor entre chamadas pesadas (achado em
// produção, sessão 7 cont.¹¹). Trade-off consciente: processa mais devagar.
// `neverError`: A CORREÇÃO QUE O DADO DO DONO EXIGIU.
//
// A saída real do nó no v30, colada por ele:
//
//     error.message = "Try spacing your requests out using the batching settings…"
//     error.name    = "AxiosError"
//     error.code    = "ERR_BAD_REQUEST"      ← código de TRANSPORTE, não da OpenAI
//     error.status  = 429
//
// Não há `error.error`, não há `cause`, não há headers: o corpo da resposta da
// OpenAI — que é o único lugar onde `insufficient_quota` / `rate_limit_exceeded` /
// `project_spend_limit_exceeded` aparecem — **não chega ao item**. A investigação
// tinha previsto que ele estaria em `error.error.error`; o dado do dono refutou
// isso nesta versão do n8n. Tratar 429 sem corpo é o melhor que dá para fazer com
// esse item, e é honestamente o que o diagnóstico faz ("não disse QUAL").
//
// Com `neverError`, o nó deixa de tratar 4xx/5xx como exceção e entrega a
// RESPOSTA — cujo corpo é exatamente `{error:{type,code,message}}`. Aí o
// diagnóstico nomeia a causa em vez de dizer "indeterminado", e a mensagem da
// OpenAI para rate limit traz os números do balde ("Limit 30000, Used …").
//
// TRADE-OFF, explícito: sem exceção, o `retryOnFail` do nó não tem o que
// reexecutar. Aceito por duas razões — (a) a investigação indica que ele já não
// disparava, porque `onError: continueRegularOutput` também impede o lançamento;
// (b) uma tentativa que sabe a causa vale mais que seis que não sabem. Falha de
// REDE (sem resposta) continua sendo exceção, então retry/onError seguem valendo
// para ela. Se em produção aparecer sinal de que o retry era real e fazia falta,
// o caminho é reverter esta opção — não empilhar as duas.
const RESPOSTA_COM_CORPO_NO_ERRO = { response: { response: { neverError: true } } };

const OPENAI_BATCHING = { batching: { batch: { batchSize: 1, batchInterval: 6000 } }, ...RESPOSTA_COM_CORPO_NO_ERRO };

// A CADÊNCIA DA EXTRAÇÃO É ARITMÉTICA, NÃO CHUTE — e isto é a correção do v30.
//
// O que eu não sabia quando escolhi 6s e depois 12s: a OpenAI documenta que
// "your rate limit is calculated as the MAXIMUM of max_tokens and the estimated
// number of tokens based on the character count of your request". Ou seja,
// `max_tokens` é RESERVA de TPM: toda extração reserva 16.384
// tokens do balde por minuto, para um PDF de 2 KB ou de 40 páginas — os dois
// pagam igual. Isso explica o fato que mais incomodava no v30: as notas
// explicativas minúsculas também tomaram 429.
//
// Com isso, a cadência deixa de ser opinião:
//
//     chamadas por minuto suportadas = TPM_DA_CONTA / max_tokens
//     intervalo mínimo entre chamadas = 60.000ms / chamadas por minuto
//
// Nos números de hoje (Tier 1 = 30.000 TPM, max_tokens = 16.384):
// 1,8 chamada/min → intervalo de ~33s. Os 12s que eu havia posto suportam 5
// chamadas/min = 81.920 TPM — quase 3x o teto do Tier 1. Ou seja: no Tier 1 o
// lote de 14 documentos NÃO tinha como passar, nem a 6s nem a 12s, e o problema
// não era "espaçar um pouco mais".
//
// TPM_CONTA é o ÚNICO número a ajustar, e ele mora em lib/extract.mjs (junto de
// MAX_OUTPUT_TOKENS) porque o teste de cadência e o diagnosticar-openai.mjs leem
// o MESMO valor — duplicar aqui faria os três discordarem no primeiro ajuste.
// Tier 2 do gpt-4o são 450.000 TPM, e aí o intervalo cai para ~2,2s — a
// diferença entre 8 minutos e 30 segundos para o mesmo lote.
const CHAMADAS_POR_MINUTO = TPM_CONTA / MAX_OUTPUT_TOKENS;
const INTERVALO_EXTRACAO_MS = Math.ceil(60000 / CHAMADAS_POR_MINUTO);

const OPENAI_BATCHING_EXTRACAO = { batching: { batch: { batchSize: 1, batchInterval: INTERVALO_EXTRACAO_MS } }, ...RESPOSTA_COM_CORPO_NO_ERRO };

// Retry para os nós Postgres: SEM onError, um erro transitório (conexão sob
// carga, timeout pontual) num ÚNICO item PARA A EXECUÇÃO INTEIRA — todos os
// itens ainda na fila somem sem nenhum rastro (achado em produção, sessão 7
// cont.¹³, "teste v19": 9 arquivos pequenos enviados, só 6 apareceram no
// dashboard; os outros 3 nunca chegaram nem a ter uma linha `documento`
// criada — consistente com a execução ter sido interrompida por um erro de
// node Postgres no meio do lote, não com falha de extração, que já é
// tolerante a erro). `continueRegularOutput` (como os nós OpenAI já têm)
// impede esse efeito cascata: o item que falhou fica com dado incompleto
// (nunca vira fato — segue N0/pendente, doutrina docs/01), mas os itens
// SEGUINTES no lote continuam sendo processados normalmente.
const PG_RETRY = { onError: 'continueRegularOutput', retryOnFail: true, maxTries: 3, waitBetweenTries: 3000 };

// Todo nó Code POR ITEM continua o lote quando um item falha.
//
// Antes desta correção o JSON tinha 8 `onError` — os 6 Postgres e os 2 OpenAI — e
// ZERO nos Code. `Preparar Conteudo` chama `getBinaryDataBuffer` (binário
// corrompido, referência de filesystem expirada, arquivo grande demais): um throw
// ali **mata a execução inteira** e todos os itens ainda na fila desaparecem sem
// rastro. É exatamente o bug do "teste v19" (9 arquivos enviados, 6 no dashboard)
// por outra causa, e foi para ele que os nós Postgres ganharam `onError` na
// sessão 7 cont.¹³ — os Code ficaram de fora e ninguém notou porque o invariante
// que confere isso tem lista de nomes hardcoded.
//
// DOIS nós Code NÃO entram aqui, e a exclusão é o ponto:
//   • `Listar Arquivos` lança quando o formulário vem sem arquivo — abortar é a
//     resposta certa, não há lote para continuar.
//   • `Orcamento do Lote` lança para RECUSAR o lote acima de US$ 3. Pôr `onError`
//     nele desativaria o teto de gasto, que é o oposto do que ele existe para fazer.
const CODE_CONTINUA = { onError: 'continueRegularOutput' };

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
  }, 200, 400, { credentials: PG_CRED, ...PG_RETRY }),

  node('Listar Arquivos', 'n8n-nodes-base.code', 2, { mode: 'runOnceForAllItems', jsCode: CODE_LISTAR }, 400, 400),

  node('Classificar Nome', 'n8n-nodes-base.code', 2, { mode: 'runOnceForEachItem', jsCode: CODE_CLASSIFICAR }, 600, 400, CODE_CONTINUA),

  node('Orcamento do Lote', 'n8n-nodes-base.code', 2, { mode: 'runOnceForAllItems', jsCode: CODE_ORCAMENTO }, 700, 260),
  node('Preparar Conteudo', 'n8n-nodes-base.code', 2, { mode: 'runOnceForEachItem', jsCode: CODE_PREPARAR_CONTEUDO }, 800, 400, CODE_CONTINUA),

  // RAMO LATERAL: nada depende da saída deste node (HTTP substitui o item).
  // ⚠️ DESABILITADO (2026-07-17): bug de longa data do node HTTP Request do
  // N8N ao lidar com dados binários (GitHub n8n-io/n8n#3089, #10096) — trava
  // o editor com "Converting circular structure to JSON" ao rodar o workflow
  // inteiro (não é config nossa: URL/credencial/headers já testados corretos;
  // limpar cache de execução não resolve, é reproduzível). Como este node é
  // ramo lateral (não bloqueia classificação/extração/completude), fica
  // desabilitado até trocarmos de abordagem — ver n8n/README.md
  // "Upload Storage — pendência conhecida" para as alternativas (community
  // node n8n-nodes-supabase, ou mover o upload para o portal Vercel).
  // Reabilitar: trocar `disabled: true` por `disabled: false` (ou remover)
  // depois de adotar uma das alternativas.
  node('Upload Storage', 'n8n-nodes-base.httpRequest', 4.2, {
    method: 'POST',
    url: '=https://SEU-PROJETO.supabase.co/storage/v1/object/documentos/{{ $json.caso_id }}/{{ encodeURIComponent($json.nome_original) }}',
    authentication: 'genericCredentialType',
    genericAuthType: 'httpHeaderAuth',
    sendHeaders: true, headerParameters: { parameters: [
      { name: 'x-upsert', value: 'true' },
      { name: 'apikey', value: 'COLE_A_SERVICE_ROLE_KEY_AQUI' },
    ] },
    sendBody: true, contentType: 'binaryData', inputDataFieldName: 'data',
  }, 1000, 560, { credentials: { httpHeaderAuth: { id: 'REPLACE', name: 'Supabase Service (Header Auth)' } }, disabled: true }),

  node('Precisa Fallback?', 'n8n-nodes-base.if', 2, {
    conditions: { options: { caseSensitive: true, typeValidation: 'strict' }, combinator: 'and', conditions: [
      { leftValue: '={{ $json.precisa_fallback_openai }}', rightValue: true, operator: { type: 'boolean', operation: 'true', singleValue: true } },
    ] },
  }, 1000, 300),

  node('Montar Req Classif', 'n8n-nodes-base.code', 2, { mode: 'runOnceForEachItem', jsCode: CODE_REQ_CLASSIF }, 1200, 200, CODE_CONTINUA),

  // Falha da OpenAI NÃO derruba o workflow: segue com a resposta de erro, o
  // Parse produz confiança 0 → pendência de classificação (fail-safe).
  // Auth via credencial Header Auth (Name=Authorization, Value=Bearer sk-...),
  // o setup real do dono — sem $env (bloqueado por padrão no N8N).
  node('OpenAI Classificar', 'n8n-nodes-base.httpRequest', 4.2, {
    method: 'POST', url: 'https://api.openai.com/v1/chat/completions',
    authentication: 'genericCredentialType',
    genericAuthType: 'httpHeaderAuth',
    sendBody: true, specifyBody: 'json', jsonBody: '={{ JSON.stringify($json.openai_body) }}',
    options: OPENAI_BATCHING,
  }, 1400, 200, { onError: 'continueRegularOutput', retryOnFail: true, credentials: { httpHeaderAuth: { id: 'REPLACE', name: 'OpenAI API' } } }),

  node('Parse OpenAI Classif', 'n8n-nodes-base.code', 2, { mode: 'runOnceForEachItem', jsCode: CODE_PARSE_CLASSIF }, 1600, 200, CODE_CONTINUA),

  // $14 usa notação nomeada (p_justificativa=>) para pular o p_threshold (14º
  // parâmetro, mantém o default 0.7) sem precisar repeti-lo explicitamente.
  node('Registrar Documento', 'n8n-nodes-base.postgres', 2.5, {
    operation: 'executeQuery',
    query: 'select fn_registrar_documento($1::uuid,$2::text,$3::text,$4::text,$5::text,$6::numeric,$7::text,$8::origem_arquivo,$9::text,$10::text,$11::boolean,$12::text,$13::legibilidade, p_justificativa=>$14::text) as r',
    options: { queryReplacement: "={{ [$json.caso_id, $json.entidade || null, $json.periodo_tipo || null, $json.periodo_ref || null, $json.tipo_taxonomia || null, $json.confianca, $json.fonte, 'supabase_storage', $json.caso_id + '/' + $json.nome_original, $json.nome_original, $json.assinado, $json.hash || null, 'ok', $json.justificativa || null] }}" },
  }, 1850, 400, { credentials: PG_CRED, ...PG_RETRY }),

  node('Recomputar Completude', 'n8n-nodes-base.postgres', 2.5, {
    operation: 'executeQuery', query: 'select fn_recomputar_completude($1::uuid) as resultado',
    options: { queryReplacement: "={{ $('Upsert Caso (Postgres)').first().json.caso_id }}" },
  }, 2100, 560, { credentials: PG_CRED, ...PG_RETRY }),

  node('Montar Req Extracao', 'n8n-nodes-base.code', 2, { mode: 'runOnceForEachItem', jsCode: CODE_REQ_EXTRACAO }, 2100, 300, CODE_CONTINUA),

  node('OpenAI Extrair', 'n8n-nodes-base.httpRequest', 4.2, {
    method: 'POST', url: 'https://api.openai.com/v1/chat/completions',
    authentication: 'genericCredentialType',
    genericAuthType: 'httpHeaderAuth',
    sendBody: true, specifyBody: 'json', jsonBody: '={{ JSON.stringify($json.openai_body) }}',
    options: OPENAI_BATCHING_EXTRACAO,
  }, 2300, 300, { onError: 'continueRegularOutput', retryOnFail: true, credentials: { httpHeaderAuth: { id: 'REPLACE', name: 'OpenAI API' } } }),

  node('Parse Extracao', 'n8n-nodes-base.code', 2, { mode: 'runOnceForEachItem', jsCode: CODE_PARSE_EXTRACAO }, 2500, 300, CODE_CONTINUA),

  node('Gravar Campos (Sombra)', 'n8n-nodes-base.postgres', 2.5, {
    operation: 'executeQuery',
    query: 'select fn_registrar_campos_extraidos($1::uuid, $2::jsonb, p_falha_motivo=>$3::text) as n_campos',
    options: { queryReplacement: "={{ [$json.documento_versao_id, JSON.stringify($json.campos), $json.falha_motivo || null] }}" },
  }, 2700, 300, { credentials: PG_CRED, ...PG_RETRY }),

  // Diagnóstico (E1/E2, N1): entidade preenche a lacuna quando ainda vazia;
  // tipo/período/legibilidade só CONFEREM contra o que já está registrado —
  // divergência vira pendência tipada (tipo_incorreto/periodo_incorreto/
  // entidade_incorreta/arquivo_ilegivel), nunca corrige sozinho (anti-
  // ancoragem, docs/01). Roda ANTES da reconciliação para que ela já veja a
  // entidade recém-preenchida, se for o caso.
  node('Registrar Diagnostico', 'n8n-nodes-base.postgres', 2.5, {
    operation: 'executeQuery',
    query: 'select fn_registrar_diagnostico($1::uuid,$2::uuid,$3::text,$4::boolean,$5::text,$6::text,$7::text,$8::legibilidade,$9::text,$10::text,$11::text) as resultado',
    options: { queryReplacement: "={{ [$('Registrar Documento').item.json.r.documento_id, $('Parse Extracao').item.json.documento_versao_id, $('Parse Extracao').item.json.diagnostico.entidade, $('Parse Extracao').item.json.diagnostico.tipo_confirma, $('Parse Extracao').item.json.diagnostico.tipo_sugerido, $('Parse Extracao').item.json.diagnostico.periodo_tipo, $('Parse Extracao').item.json.diagnostico.periodo_referencia, $('Parse Extracao').item.json.diagnostico.legibilidade, $('Parse Extracao').item.json.diagnostico.nota_legibilidade, $('Parse Extracao').item.json.diagnostico.resumo, $('Parse Extracao').item.json.diagnostico.justificativa] }}" },
  }, 2900, 300, { credentials: PG_CRED, ...PG_RETRY }),

  // E3 (Classe A, N1): roda as checagens aritméticas relevantes ao tipo do
  // documento recém-extraído (docs/04). Só precisa do documento_id — a função
  // resolve caso/entidade/período sozinha (N8N continua stateless). Gera
  // pendência tipada quando diverge ou quando falta pré-condição; nunca
  // escreve "fato" numa base viva (anti-ancoragem, docs/01).
  node('Reconciliar (Classe A)', 'n8n-nodes-base.postgres', 2.5, {
    operation: 'executeQuery',
    query: 'select fn_reconciliar_por_documento($1::uuid) as resultado',
    options: { queryReplacement: "={{ [$('Registrar Documento').item.json.r.documento_id] }}" },
  }, 3100, 300, { credentials: PG_CRED, ...PG_RETRY }),
];

const connections = {
  'Intake (Form)': { main: [[{ node: 'Upsert Caso (Postgres)', type: 'main', index: 0 }]] },
  'Upsert Caso (Postgres)': { main: [[{ node: 'Listar Arquivos', type: 'main', index: 0 }]] },
  'Listar Arquivos': { main: [[{ node: 'Classificar Nome', type: 'main', index: 0 }]] },
  // O orçamento entra AQUI, entre a classificação por nome e o preparo do
  // conteúdo: é o último ponto em que o lote inteiro está visível de uma vez e
  // ainda não custou nada (nem chamada à OpenAI, nem linha no banco).
  'Classificar Nome': { main: [[{ node: 'Orcamento do Lote', type: 'main', index: 0 }]] },
  'Orcamento do Lote': { main: [[{ node: 'Preparar Conteudo', type: 'main', index: 0 }]] },
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
  'Gravar Campos (Sombra)': { main: [[{ node: 'Registrar Diagnostico', type: 'main', index: 0 }]] },
  'Registrar Diagnostico': { main: [[{ node: 'Reconciliar (Classe A)', type: 'main', index: 0 }]] },
};

const workflow = {
  name: 'Oria — E1 Ingestão + Diagnóstico + E2 Extração-Sombra + E3 Reconciliação Classe A (Fatia 1)',
  nodes, connections, settings: { executionOrder: 'v1' },
  meta: { note: 'Gerado por n8n/build-workflow.mjs. Nós Code espelham n8n/lib/ (testado). Diagnóstico de conteúdo roda SEMPRE (entidade/tipo/período/legibilidade); E2 em N0/sombra; E3 Classe A em N1 (gera pendência, nunca fato).' },
};

writeFileSync(join(__dirname, 'workflow.e1-ingestao.json'), JSON.stringify(workflow, null, 2) + '\n');
console.log('Escrito workflow —', nodes.length, 'nós,', Object.keys(connections).length, 'conexões');
