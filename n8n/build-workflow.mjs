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
import { SECAO_CANONICA_ENUM } from './lib/extract.mjs';

const __dirname = dirname(fileURLToPath(import.meta.url));

// Enums da classificação — IMPORTADOS de lib/openai.mjs (fonte única), não
// copiados à mão: um mirror manual desses códigos já ficou desatualizado uma
// vez (permitindo a OpenAI inventar "BAL" em vez de "BALANCO", sem nenhum
// enum travando a saída) e só foi pego testando com documento real no N8N.
const TIPO_TAXONOMIA_ENUM = JSON.stringify(codigosConhecidos());
const PERIODO_TIPO_ENUM = JSON.stringify(['anual', 'trimestre', 'multi', 'data-base', 'outro', 'desconhecido']);

// Schemas estritos (mesma forma dos módulos lib/openai.mjs e lib/extract.mjs).
const SCHEMA_CLASSIF = `{name:'classificacao_documento',strict:true,schema:{type:'object',additionalProperties:false,required:['tipo_taxonomia','entidade','periodo_tipo','periodo_referencia','assinado','confianca','justificativa'],properties:{tipo_taxonomia:{type:'string',enum:${TIPO_TAXONOMIA_ENUM}},entidade:{type:['string','null']},periodo_tipo:{type:'string',enum:${PERIODO_TIPO_ENUM}},periodo_referencia:{type:['string','null']},assinado:{type:['boolean','null']},confianca:{type:'number',minimum:0,maximum:1},justificativa:{type:'string'}}}}`;
// Diagnóstico (entidade/confere tipo+período/legibilidade/resumo) + linhas
// com `secao` (agrupador de planilha) — mesma chamada que já rodava sempre
// para extrair linhas (não aumenta o nº de chamadas à OpenAI); espelha
// n8n/lib/extract.mjs (fonte da verdade).
const LEGIBILIDADE_ENUM = JSON.stringify(['ok', 'degradado', 'ilegivel']);
const SECAO_CANONICA_ENUM_JSON = JSON.stringify(SECAO_CANONICA_ENUM);
const SCHEMA_EXTRACAO = `{name:'diagnostico_e_extracao',strict:true,schema:{type:'object',additionalProperties:false,required:['moeda','unidade','diagnostico','linhas'],properties:{moeda:{type:['string','null']},unidade:{type:['string','null']},diagnostico:{type:'object',additionalProperties:false,required:['entidade','tipo_confirma','tipo_sugerido','periodo_tipo','periodo_referencia','legibilidade','nota_legibilidade','resumo','justificativa'],properties:{entidade:{type:['string','null']},tipo_confirma:{type:'boolean'},tipo_sugerido:{type:'string',enum:${TIPO_TAXONOMIA_ENUM}},periodo_tipo:{type:'string',enum:${PERIODO_TIPO_ENUM}},periodo_referencia:{type:['string','null']},legibilidade:{type:'string',enum:${LEGIBILIDADE_ENUM}},nota_legibilidade:{type:['string','null']},resumo:{type:'string'},justificativa:{type:'string'}}},linhas:{type:'array',items:{type:'object',additionalProperties:false,required:['s','sc','ec','pc','k','vt','vn','op','cf'],properties:{s:{type:['string','null'],description:'secao: agrupador livre (rótulo do próprio documento)'},sc:{type:'string',enum:${SECAO_CANONICA_ENUM_JSON},description:'secao_canonica: seção padronizada pelo significado contábil'},ec:{type:['string','null'],description:'entidade_coluna: nome da coluna/empresa quando há várias entidades lado a lado'},pc:{type:['string','null'],description:'periodo_coluna: rótulo da coluna de período quando há vários períodos lado a lado'},k:{type:'string',description:'chave: rótulo da conta'},vt:{type:['string','null'],description:'valor_texto: valor como aparece no documento'},vn:{type:['number','null'],description:'valor_num: valor numérico puro'},op:{type:['integer','null'],description:'origem_pagina: página de origem'},cf:{type:'number',description:'confianca: confiança 0-1 desta linha'}}}}}}}`;

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
function parsePeriodo(t){let m=t.match(/\\b(\\d{1,2})m(\\d{2,4})\\b/);if(m&&Number(m[1])===12)return{tipo:'anual',referencia:'12M'+m[2].slice(-2)};m=t.match(/\\bl(\\d{1,2})m\\b/)||t.match(/\\b(\\d{2})\\s*meses\\b/);if(m)return{tipo:'multi',referencia:'L'+m[1]+'M'};m=t.match(/\\b([1-4])t(\\d{2,4})\\b/);if(m)return{tipo:'trimestre',referencia:m[1]+'T'+m[2].slice(-2)};m=t.match(/\\b(20\\d{2}|\\d{2})\\s*(?:-|–|a)\\s*(20\\d{2}|\\d{2})\\b/);if(m){const full=y=>y.length===2?'20'+y:y;const start=Number(full(m[1])),end=Number(full(m[2]));if(start<=end&&end-start<=50){const anos=[];for(let y=start;y<=end;y++)anos.push(String(y).slice(-2));return{tipo:'multi',referencia:anos.join(',')};}}const a=t.match(/\\b(20)?\\d{2}\\b/g);if(a&&a.length>=2)return{tipo:'multi',referencia:a.map(x=>x.slice(-2)).join(',')};if(a&&a.length===1&&/^(19|20)\\d{2}$/.test(a[0]))return{tipo:'anual',referencia:a[0],fraco:true};return null;}
function parseTipo(t){for(const a of ALIASES){for(const termo of a.termos){if(t.includes(termo))return a.codigo;}}return null;}
const item=$input.item.json;
const t=normalize(item.nome_original);
const tipo=parseTipo(t), periodo=parsePeriodo(t);
const assinado=/\\bassinad[oa]s?\\b/.test(t)?true:null;
let conf=0; if(tipo)conf+=0.6; if(periodo)conf+=(periodo.fraco?0.05:0.3); if(assinado===true)conf+=0.1; conf=Math.min(1,Number(conf.toFixed(2)));
return {json:{...item, tipo_taxonomia:tipo, periodo_tipo:periodo?periodo.tipo:null, periodo_ref:periodo?periodo.referencia:null, assinado, entidade:null, confianca:conf, fonte:'nome_arquivo', precisa_fallback_openai:(conf<0.7|| !tipo)}, binary: $input.item.binary};
`.trim();

// --- Code (EACH ITEM): prepara a parte de CONTEUDO (para todos os docs) ---
// pdf→file; imagem→image_url; csv→texto (parse inline); xlsx→nota (ver README).
// Preserva o binário (o Upload Storage roda como ramo a partir deste node).
const CODE_PREPARAR_CONTEUDO = `
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
return {json:{...item, content_part: part, content_mime: mt}, binary: $input.item.binary};
`.trim();

// --- Code (EACH ITEM): monta corpo da chamada de CLASSIFICAÇÃO (fallback) ---
const CODE_REQ_CLASSIF = `
const item=$input.item.json;
const schema=${SCHEMA_CLASSIF};
const body={model:'gpt-4o',temperature:0,response_format:{type:'json_schema',json_schema:schema},messages:[
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
  return {json:{...item, ...mergeClassification(fromName, {tipo_taxonomia:null, confianca:0, justificativa:'A chamada a OpenAI nao retornou conteudo (falha de rede/API).'})}};
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
const prep=$('Preparar Conteudo').item.json;
const schema=${SCHEMA_EXTRACAO};
const promptSistema='Voce analisa UM documento financeiro de um mandato de Reestruturacao (Brasil) e devolve DUAS coisas: um diagnostico do documento e a extracao linha a linha de TODOS os dados financeiros, organizados como planilha. DIAGNOSTICO: entidade = razao social se visivel no conteudo (null se nao, nunca invente; NAO use o nome de quem ASSINOU -- contador/administrador/socio, bloco com CRC/CPF -- e o signatario, nao a entidade; se combina varias empresas use o nome do GRUPO ou null, nao escolha uma ao acaso); tipo_confirma/tipo_sugerido = voce recebe uma dica de tipo vinda do nome do arquivo, leia o conteudo e diga se bate (tipo_confirma) e qual o codigo que o CONTEUDO sugere (tipo_sugerido, pode diferir da dica; DESCONHECIDO so se ilegivel/nao-financeiro; BALANCO vs COMBINADO: COMBINADO = grupo de VARIAS empresas juntas com colunas por empresa; um arquivo com varias demonstracoes -- Balanco+DRE+DFC+DMPL -- de UMA entidade so NAO e COMBINADO, use a demonstracao principal (normalmente BALANCO); regra: linhas com entidade_coluna preenchido -> COMBINADO, entidade so -> tipo da demonstracao principal); periodo_tipo/periodo_referencia = periodo real do conteudo (12M25=ano 2025; 1T25=1o tri/2025; L24M=ultimos 24 meses; "23,24,25"=multiplos exercicios; ano isolado tambem vale; e o periodo ATUAL, NAO use a data de um SALDO DE ABERTURA/exercicio anterior -- ex. DMPL com "Saldos em 31/12/2023" e "31/12/2024" e documento de 2024, 2023 e so o saldo inicial); legibilidade = ok/degradado/ilegivel (avaliacao real do ARQUIVO: paginas faltando, digitalizacao ruim, tabela cortada), nota_legibilidade explica quando != ok (null quando ok); resumo = 2-3 frases objetivas do conteudo; justificativa = 1-2 frases do diagnostico. LINHAS: cada linha do JSON usa chaves curtas (economia de tokens em documentos com muitas contas): s=secao, sc=secao_canonica, ec=entidade_coluna, pc=periodo_coluna, k=chave, vt=valor_texto, vn=valor_num, op=origem_pagina, cf=confianca -- o texto abaixo usa os nomes completos, sempre correspondendo a chave curta do schema. Extraia TODAS as linhas financeiras (rotulo+valor), com secao = agrupador que espelha a estrutura do proprio documento (ex.: "Ativo Circulante", "Passivo Nao Circulante", "Patrimonio Liquido", "Receita Operacional", "Atividades de Investimento"; null se a linha nao pertencer a nenhuma secao clara). Alem da secao livre, classifique CADA linha em UMA secao_canonica padronizada usando julgamento contabil (o SIGNIFICADO da conta, nao so o nome literal): Balanco/Balancete = ativo_circulante, ativo_nao_circulante, passivo_circulante, passivo_nao_circulante, patrimonio_liquido (ex.: mutuo A RECEBER e ativo; mutuo A PAGAR e passivo); DRE = receita_bruta (receita e deducoes), custos (CPV/CMV/custo de servico), despesas_operacionais (vendas/administrativas/gerais), resultado_financeiro (receitas/despesas financeiras, juros), impostos_lucro (IRPJ/CSLL); Fluxo de Caixa = atividades_operacionais, atividades_investimento, atividades_financiamento. Use NAO_CLASSIFICAVEL quando a linha for um total/subtotal geral ou quando nao tiver seguranca (nao force palpite ruim -- vai para revisao manual). secao_canonica e SUGESTAO revisavel, nunca fato. DOCUMENTO COM VARIAS ENTIDADES/COLUNAS lado a lado (ex.: "Empresa A | Empresa B | Total"): NAO resuma num valor so por conta -- gere uma linha separada por (conta x coluna), mesmo "chave", com entidade_coluna = nome exato do cabecalho da coluna; nunca some/estime um valor unico representando varias colunas, omita so a linha que nao conseguir ler. Documento de uma entidade so (o caso comum): entidade_coluna null em todas as linhas. DOCUMENTO COMPARATIVO com varias colunas de PERIODO lado a lado (ex.: "2023 | 2024", "31/12/2023 | 31/12/2024", "atual | anterior") -- padrao em demonstracoes contabeis: NAO resuma num valor so -- gere uma linha por (conta x periodo), mesmo "chave", com periodo_coluna = rotulo EXATO da coluna de periodo ("2023", "2024", "31/12/2024"...). E ortogonal a entidade_coluna: um doc pode ter as duas dimensoes (varias empresas E varios anos) -> linha por (conta x empresa x periodo) com as duas preenchidas. Documento de periodo unico (caso comum): periodo_coluna null em todas as linhas. Nunca some/estime um valor unico cobrindo varios periodos. valor_num = numero puro quando houver, senao null. Informe pagina de origem. NAO invente linhas, valores nem entidade; omita o ilegivel.';
const body={model:'gpt-4o',temperature:0,max_tokens:16384,response_format:{type:'json_schema',json_schema:schema},messages:[
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
const ctx=$('Montar Req Extracao').item.json;
const resp=$json;
const finishReason=resp?.choices?.[0]?.finish_reason??null;
const content=resp?.choices?.[0]?.message?.content;
let p={}; let falhaMotivo=null;
if(resp?.error){
  falhaMotivo='Erro da API OpenAI: '+(resp.error.message||resp.error.code||JSON.stringify(resp.error));
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
const unidade=p.unidade??null;
const campos=Array.isArray(p.linhas)?p.linhas.map(l=>({secao:l.s??null, secao_canonica:(l.sc&&l.sc!=='NAO_CLASSIFICAVEL')?l.sc:null, entidade_coluna:l.ec??null, periodo_coluna:l.pc??null, chave:l.k, valor_texto:l.vt??null, valor_num:(typeof l.vn==='number')?l.vn:null, unidade, confianca:(typeof l.cf==='number')?l.cf:null, origem_pagina:Number.isInteger(l.op)?l.op:null})):[];
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
return {json:{documento_versao_id:ctx.documento_versao_id, campos, diagnostico, falha_motivo:falhaMotivo}};
`.trim();

const PG_CRED = { postgres: { id: 'REPLACE', name: 'Supabase Postgres (Session Pooler)' } };
const node = (name, type, typeVersion, parameters, x, yy, opts = {}) => ({
  parameters, id: name.toLowerCase().replace(/[^a-z0-9]+/g, '-'), name, type, typeVersion,
  position: [x, yy],
  ...(opts.credentials ? { credentials: opts.credentials } : {}),
  ...(opts.onError ? { onError: opts.onError } : {}),
  ...(opts.disabled ? { disabled: true } : {}),
  // Retry no nível do node (N8N): reexecuta o item que falhou antes de cair no
  // onError. waitBetweenTries tem teto de 5000ms no N8N — combinado com o
  // batching (abaixo) resolve o 429 de rate limit da OpenAI num upload em
  // lote. maxTries 6 (era 4, cont.⁸): o "teste v18" mostrou que 4 tentativas
  // ainda não bastavam pros 3 documentos mais pesados (cont.¹¹) — mais
  // tentativas dão mais chances do balde de TPM da conta se recompor.
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
const OPENAI_BATCHING = { batching: { batch: { batchSize: 1, batchInterval: 6000 } } };

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
    options: OPENAI_BATCHING,
  }, 1400, 200, { onError: 'continueRegularOutput', retryOnFail: true, credentials: { httpHeaderAuth: { id: 'REPLACE', name: 'OpenAI API' } } }),

  node('Parse OpenAI Classif', 'n8n-nodes-base.code', 2, { mode: 'runOnceForEachItem', jsCode: CODE_PARSE_CLASSIF }, 1600, 200),

  // $14 usa notação nomeada (p_justificativa=>) para pular o p_threshold (14º
  // parâmetro, mantém o default 0.7) sem precisar repeti-lo explicitamente.
  node('Registrar Documento', 'n8n-nodes-base.postgres', 2.5, {
    operation: 'executeQuery',
    query: 'select fn_registrar_documento($1::uuid,$2::text,$3::text,$4::text,$5::text,$6::numeric,$7::text,$8::origem_arquivo,$9::text,$10::text,$11::boolean,$12::text,$13::legibilidade, p_justificativa=>$14::text) as r',
    options: { queryReplacement: "={{ [$json.caso_id, $json.entidade || null, $json.periodo_tipo || null, $json.periodo_ref || null, $json.tipo_taxonomia || null, $json.confianca, $json.fonte, 'supabase_storage', $json.caso_id + '/' + $json.nome_original, $json.nome_original, $json.assinado, null, 'ok', $json.justificativa || null] }}" },
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
    options: OPENAI_BATCHING,
  }, 2300, 300, { onError: 'continueRegularOutput', retryOnFail: true, credentials: { httpHeaderAuth: { id: 'REPLACE', name: 'OpenAI API' } } }),

  node('Parse Extracao', 'n8n-nodes-base.code', 2, { mode: 'runOnceForEachItem', jsCode: CODE_PARSE_EXTRACAO }, 2500, 300),

  node('Gravar Campos (Sombra)', 'n8n-nodes-base.postgres', 2.5, {
    operation: 'executeQuery',
    query: 'select fn_registrar_campos_extraidos($1::uuid, $2::jsonb, p_falha_motivo=>$3::text) as n_campos',
    options: { queryReplacement: "={{ [$json.documento_versao_id, JSON.stringify($json.campos), $json.falha_motivo || null] }}" },
  }, 2700, 300, { credentials: PG_CRED }),

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
  }, 2900, 300, { credentials: PG_CRED }),

  // E3 (Classe A, N1): roda as checagens aritméticas relevantes ao tipo do
  // documento recém-extraído (docs/04). Só precisa do documento_id — a função
  // resolve caso/entidade/período sozinha (N8N continua stateless). Gera
  // pendência tipada quando diverge ou quando falta pré-condição; nunca
  // escreve "fato" numa base viva (anti-ancoragem, docs/01).
  node('Reconciliar (Classe A)', 'n8n-nodes-base.postgres', 2.5, {
    operation: 'executeQuery',
    query: 'select fn_reconciliar_por_documento($1::uuid) as resultado',
    options: { queryReplacement: "={{ [$('Registrar Documento').item.json.r.documento_id] }}" },
  }, 3100, 300, { credentials: PG_CRED }),
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
