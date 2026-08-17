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
import { SYSTEM_PROMPT, diagnosticarErroApi, MAX_OUTPUT_TOKENS, TPM_CONTA, normalizarUnidade, normalizarMoeda, extractionSchema, achatarGrupos } from './lib/extract.mjs';
import { ALIASES } from './lib/taxonomia.mjs';
import { parseEntidade } from './lib/classifier.mjs';
import { orcamentoDoLote, TETO_EXECUCAO_USD, CUSTO_ESTIMADO_DOC_USD, CUSTO_POR_MB_USD, CUSTO_MINIMO_CHAMADA_USD, bytesDoBinario, custoDaChamada, PRECO_USD_POR_MILHAO, MODELO_CLASSIFICACAO, MODELO_EXTRACAO, PARCELA_ENTRADA_NA_CHAMADA, PESO_MINIMO_CLASSIFICACAO, VERSAO_ORCAMENTO, pesoDaChamadaDeClassificacao } from './lib/custo.mjs';
import { sha256Hex } from './lib/hash.mjs';
import {
  linhasComNumero, linhasDeConta, planejarFatias, instrucaoDaFatia, juntarBlocos, avaliarCobertura,
  MAX_CELULAS_POR_BLOCO, LIMIAR_COBERTURA, MINIMO_PARA_AVALIAR,
} from './lib/cobertura.mjs';

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

// Modelos das DUAS chamadas. Eles MORAVAM aqui e passaram a morar em
// `lib/custo.mjs` (13/08/2026), porque o orçamento do lote passou a precisar do
// preço da classificação para pesar a segunda chamada — e preço derivado de um
// modelo declarado noutro arquivo é a cópia à mão que este repositório já viu
// divergir. Aqui ficam só os apelidos, para os nós não mudarem de forma.
//
// Hoje: classificação em `gpt-4o-mini`, extração em `gpt-4o`. O porquê (e a rede
// que torna isso seguro) está no comentário da fonte e em docs/CUSTO_OPENAI.md.
const MODEL_CLASSIFICACAO = MODELO_CLASSIFICACAO;
const MODEL_EXTRACAO = MODELO_EXTRACAO;

// Schemas estritos (mesma forma dos módulos lib/openai.mjs e lib/extract.mjs).
const SCHEMA_CLASSIF = `{name:'classificacao_documento',strict:true,schema:{type:'object',additionalProperties:false,required:['tipo_taxonomia','entidade','periodo_tipo','periodo_referencia','assinado','confianca','justificativa'],properties:{tipo_taxonomia:{type:'string',enum:${TIPO_TAXONOMIA_ENUM}},entidade:{type:['string','null']},periodo_tipo:{type:'string',enum:${PERIODO_TIPO_ENUM}},periodo_referencia:{type:['string','null']},assinado:{type:['boolean','null']},confianca:{type:'number',minimum:0,maximum:1},justificativa:{type:'string'}}}}`;
// Diagnóstico (entidade/confere tipo+período/legibilidade/resumo) + linhas
// com `secao` (agrupador de planilha) — mesma chamada que já rodava sempre
// para extrair linhas (não aumenta o nº de chamadas à OpenAI); espelha
// n8n/lib/extract.mjs (fonte da verdade).
// O SCHEMA DA EXTRAÇÃO SAI DA FONTE, NÃO DE UM ESPELHO À MÃO.
//
// Ele era uma linha de 2.400 caracteres copiada de `lib/extract.mjs` e mantida
// em paralelo — e este repositório já tem a lista dos espelhos manuais que
// divergiram (o `ALIASES` que parava em BALANCETE, o `normUnid` que perdeu a
// última cláusula, o schema de classificação que ficou sem `enum` e fez a
// OpenAI inventar "BAL"). O schema é JSON puro, então serializar a função da
// fonte é exato e a divergência deixa de ser possível: mudar o formato da saída
// num arquivo só passa a bastar. `extractionSchema()` já traz `strict`,
// `diagnostico`, `grupos` e os enums (taxonomia, seção canônica, legibilidade).
const SCHEMA_EXTRACAO = JSON.stringify(extractionSchema());

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
// Idem para a moeda: embutida do fonte, nunca copiada à mão — é o que garante
// que o nó e a lib normalizem "US$"/"dolar"/"usd" para o MESMO 'USD'. Divergir
// aqui reintroduziria exatamente a soma de moedas diferentes que a coluna
// `campo_extraido.moeda` existe para impedir.
const FONTE_NORMALIZAR_MOEDA = `const normMoeda = ${normalizarMoeda.toString()};`;

// Idem para o orçamento e para o custo real — embutidos do fonte, nunca copiados.
// O corpo de `orcamentoDoLote` referencia constantes do módulo, e `toString()`
// NÃO as leva junto — dentro do nó elas seriam `ReferenceError`. Embutir as
// quatro é o que mantém o espelho fiel; o teste que compara o nó com a fonte
// continua valendo sobre a função.
const FONTE_ORCAMENTO_LOTE = [
  `const TETO_EXECUCAO_USD = ${TETO_EXECUCAO_USD};`,
  `const CUSTO_ESTIMADO_DOC_USD = ${CUSTO_ESTIMADO_DOC_USD};`,
  `const CUSTO_POR_MB_USD = ${CUSTO_POR_MB_USD};`,
  `const CUSTO_MINIMO_CHAMADA_USD = ${CUSTO_MINIMO_CHAMADA_USD};`,
  `const BYTES_POR_MB = 1024 * 1024;`,
  // O peso da segunda chamada entrou no corpo de `orcamentoDoLote` (via
  // parâmetro com valor padrão), então a função e as CINCO constantes que ela
  // usa têm de vir junto — `toString()` não leva o escopo do módulo, e sem elas
  // o nó quebraria com ReferenceError na primeira execução.
  `const PRECO_USD_POR_MILHAO = ${JSON.stringify(PRECO_USD_POR_MILHAO)};`,
  `const MODELO_CLASSIFICACAO = ${JSON.stringify(MODELO_CLASSIFICACAO)};`,
  `const MODELO_EXTRACAO = ${JSON.stringify(MODELO_EXTRACAO)};`,
  `const PARCELA_ENTRADA_NA_CHAMADA = ${PARCELA_ENTRADA_NA_CHAMADA};`,
  `const PESO_MINIMO_CLASSIFICACAO = ${PESO_MINIMO_CLASSIFICACAO};`,
  `const VERSAO_ORCAMENTO = ${JSON.stringify(VERSAO_ORCAMENTO)};`,
  `const pesoDaChamadaDeClassificacao = ${pesoDaChamadaDeClassificacao.toString()};`,
  `const orcamentoDoLote = ${orcamentoDoLote.toString()};`,
].join('\n');
const FONTE_BYTES_BINARIO = `const bytesDoBinario = ${bytesDoBinario.toString()};`;

// `achatarGrupos` idem — embutida do fonte. Ela é a tradução do formato agrupado
// (o que cortou 63% da saída) para as linhas que o banco grava, e é o ÚNICO
// lugar onde valor e coluna são associados. Espelhá-la à mão seria escolher o
// erro mais caro possível: uma divergência aqui grava o número de 2024 na coluna
// de 2025, sem sintoma nenhum.
const FONTE_ACHATAR_GRUPOS = `const achatarGrupos = ${achatarGrupos.toString()};`;

// As três camadas contra o truncamento e a extração pela metade (lib/cobertura.mjs),
// embutidas do fonte como todo o resto. O comentário do topo daquele arquivo tem
// os números que as motivaram — 1.139 de 2.893 células numa rodada real.
const FONTE_COBERTURA = [
  `const MAX_CELULAS_POR_BLOCO = ${MAX_CELULAS_POR_BLOCO};`,
  `const LIMIAR_COBERTURA = ${LIMIAR_COBERTURA};`,
  `const MINIMO_PARA_AVALIAR = ${MINIMO_PARA_AVALIAR};`,
  `const linhasComNumero = ${linhasComNumero.toString()};`,
  `const linhasDeConta = ${linhasDeConta.toString()};`,
  `const planejarFatias = ${planejarFatias.toString()};`,
  `const instrucaoDaFatia = ${instrucaoDaFatia.toString()};`,
  `const juntarBlocos = ${juntarBlocos.toString()};`,
  `const avaliarCobertura = ${avaliarCobertura.toString()};`,
].join('\n');

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
// Soma os bytes que o \`Listar Arquivos\` mediu. Se QUALQUER arquivo veio sem
// tamanho, o lote inteiro cai na estimativa plana: somar só os conhecidos
// subestimaria o lote na exata proporção do que não se sabe.
const semTamanho = itens.some(i => !Number.isFinite(Number(i.json.bytes)) || Number(i.json.bytes) <= 0);
const bytes = semTamanho ? null : itens.reduce((s, i) => s + Number(i.json.bytes), 0);
const r = orcamentoDoLote({ documentos: itens.length, chamadasPorDocumento: chamadas / itens.length, teto: ${TETO_EXECUCAO_USD}, custoPorChamada: ${CUSTO_ESTIMADO_DOC_USD}, bytes });
// Recusa o lote INTEIRO. Não existe "roda os que cabem" de propósito: metade
// registrada sem extração e metade sem registro nenhum é estado que dá mais
// trabalho para desfazer do que o reenvio que esta mensagem pede.
//
// E A RECUSA NÃO LANÇA MAIS AQUI. Lançar punha a mensagem certa no lugar errado:
// ela ficava só no log do n8n, e o portal — que deduz progresso da ausência de
// documentos — seguia dizendo "estamos organizando tudo com cuidado" para
// sempre. Agora o item segue marcado, o IF manda a recusa para o nó que a GRAVA
// no banco, e só depois o lote é abortado. Nada foi enviado à OpenAI em nenhum
// dos caminhos: a decisão continua sendo antes de gastar.
//
// \`orcamento_versao\` viaja com o item mesmo quando o lote PASSA. É o que
// responde, da tela do n8n, a pergunta que custou uma rodada em 12/08: "este
// workflow é o que está no repositório ou é o que foi importado em julho?".
return itens.map(i => ({ json: { ...i.json, orcamento_cabe: r.cabe, orcamento_mensagem: r.mensagem, orcamento_estimado_usd: r.estimadoUSD, orcamento_teto_usd: r.teto, orcamento_chamadas: r.chamadas, orcamento_versao: r.versao }, binary: i.binary }));
`.trim();

// --- Code (ALL ITEMS): O CUSTO DO LOTE, NUM PAINEL SÓ -----------------------
// Nasceu de uma pergunta do dono que não tinha resposta boa: "como acesso isso?"
// — sobre os tokens por documento. Eles existiam desde sempre, um por item do
// `Parse Extracao`: para saber o custo do lote era preciso abrir 14 painéis e
// somar à mão. Custo que só se conhece somando à mão é custo que ninguém mede,
// e este projeto passou meses decidindo teto de gasto por estimativa porque a
// medição estava espalhada.
//
// É um nó TERMINAL (nada depende dele), então ele não pode quebrar o lote: se
// não achar as referências, devolve o que achou e diz que achou pouco. E é o
// último da cadeia de propósito — quando ele aparece, o lote acabou.
const CODE_RESUMO_CUSTO = `
// Soma por NÓ, nunca por índice do lote. A tentação é casar item a item com
// \`$input\`, e estaria errado: só os documentos cujo nome não resolve o tipo
// passam pelo Parse OpenAI Classif (8 de 14, no book do dono), então o índice i
// da cadeia principal NÃO é o índice i daquele nó. Casar por índice atribuiria o
// custo da classificação ao documento errado — e num relatório de custo isso é
// pior que não ter o relatório.
// O LOTE SE PARTE EM DOIS, E O RESUMO TEM DE SOMAR OS DOIS.
//
// O IF \`Precisa Fallback?\` manda os documentos por dois caminhos (com e sem
// classificacao por conteudo), e o n8n executa a cadeia inteira UMA VEZ POR
// RAMO. Na rodada de 14/08 isso deu 16 documentos numa execucao do
// \`Juntar Blocos\` e 19 na outra -- 35 no total, nada perdido -- mas o painel
// reportava so' a ultima, e o custo do lote saiu pela METADE. Pior: \`.all()\` sem
// indice de execucao devolve, para um no' do OUTRO ramo, tudo o que ele
// produziu; a classificacao entrava DUAS vezes na conta.
//
// Aqui as execucoes sao percorridas uma a uma. O painel sai duas vezes (uma por
// ramo), agora com o total INTEIRO nas duas -- somar dois paineis parciais a mao
// e' exatamente o trabalho que este no' existe para acabar.
const itensDe = (nome) => {
  const out = [];
  for (let run = 0; run < 50; run += 1) {
    let itens = null;
    try { itens = $(nome).all(0, run); } catch (err) { break; }
    if (!itens || itens.length === 0) break;
    for (const it of itens) out.push(it);
  }
  return out;
};
// \`Juntar Blocos\` e nao \`Parse Extracao\`: desde o fatiamento, o Parse tem um item
// por BLOCO, e contar blocos como documentos diria "48 documentos" para um lote
// de 35. O Juntar ja' devolve um item por documento, com o custo dos blocos
// somado. O fallback existe para o caso de alguem religar o grafo sem fatiamento.
const extracoes = itensDe('Juntar Blocos').length > 0 ? itensDe('Juntar Blocos') : itensDe('Parse Extracao');
const classificacoes = itensDe('Parse OpenAI Classif');

let extracao = 0, entrada = 0, saida = 0, cache = 0, linhas = 0, comFalha = 0, semMedicao = 0;
let celulas = 0, contas = 0, fatiados = 0;
for (const it of extracoes) {
  const e = it?.json || {};
  if (typeof e.custo_usd === 'number') extracao += e.custo_usd; else semMedicao += 1;
  if (e.tokens) { entrada += e.tokens.entrada || 0; saida += e.tokens.saida || 0; cache += e.tokens.cache || 0; }
  if (e.falha_motivo) comFalha += 1;
  linhas += Array.isArray(e.campos) ? e.campos.length : 0;
  if (Number.isFinite(Number(e.contas_no_documento))) celulas += Number(e.contas_no_documento);
  if (Number.isFinite(Number(e.contas_distintas))) contas += Number(e.contas_distintas);
  if (Number(e.blocos) > 1) fatiados += 1;
}
let classificacao = 0;
for (const it of classificacoes) {
  const c = it?.json || {};
  if (typeof c.custo_classificacao_usd === 'number') classificacao += c.custo_classificacao_usd;
}
const total = extracao + classificacao;
const arred = (x) => Number(x.toFixed(4));

// A comparação com o que o ORÇAMENTO estimou fecha o ciclo: é ela que diz se o
// estimador está calibrado, e é ela que este repositório nunca teve à mão.
let estimado = null, versao = null;
try {
  const o = $('Orcamento do Lote').first().json;
  estimado = o.orcamento_estimado_usd ?? null;
  versao = o.orcamento_versao ?? null;
} catch (err) { estimado = null; }

return [{ json: {
  resumo: 'Custo REAL deste lote: US$ ' + total.toFixed(4) + ' em ' + extracoes.length + ' documento(s)'
    + ' (' + classificacoes.length + ' pagaram o PDF duas vezes)'
    + (estimado !== null ? '. O orçamento havia estimado US$ ' + Number(estimado).toFixed(2) : '')
    + '. Saída: ' + saida + ' tokens; entrada: ' + entrada + ' (' + cache + ' em cache).'
    + (celulas > 0 ? ' Cobertura: ' + contas + ' contas gravadas de ' + celulas + ' linhas de conta nos PDFs ('
      + (contas / celulas * 100).toFixed(0) + '%), em ' + linhas + ' pares conta-coluna. '
      + fatiados + ' documento(s) precisaram de mais de uma chamada.' : ''),
  orcamento_versao: versao,
  documentos: extracoes.length,
  documentos_com_classificacao: classificacoes.length,
  custo_total_usd: arred(total),
  custo_extracao_usd: arred(extracao),
  custo_classificacao_usd: arred(classificacao),
  custo_estimado_usd: estimado,
  tokens: { entrada: entrada, saida: saida, cache: cache },
  // Tokens de SAÍDA POR LINHA extraída — o número que recalibra o estimador, e o
  // que estava errado por 45%: o repositório supunha 35 e a fatura do dono disse
  // 64. Ele é o insumo da próxima calibração, e por isso sai medido, não suposto.
  tokens_saida_por_linha: linhas > 0 ? Number((saida / linhas).toFixed(1)) : null,
  linhas_extraidas: linhas,
  // Cobertura: quantas linhas o documento TINHA (medidas no texto do PDF, sem
  // IA) contra quantas chegaram. E' a resposta para "o custo caiu porque ficou
  // eficiente ou porque deixou de extrair?" — a pergunta que custou uma rodada.
  // Na unidade de CONTAS dos dois lados: contas distintas gravadas contra linhas
  // de conta do texto. \`linhas_extraidas\` continua sendo pares (conta x coluna),
  // que e' o que o banco guarda -- as duas coisas sao uteis e nao se misturam.
  contas_nos_documentos: celulas,
  contas_extraidas: contas,
  cobertura_do_lote: celulas > 0 ? Number((contas / celulas).toFixed(3)) : null,
  documentos_fatiados: fatiados,
  documentos_com_falha: comFalha,
  documentos_sem_medicao: semMedicao,
} }];
`.trim();

// --- Code (ALL ITEMS — fan-out): um item por arquivo enviado no Form ---
// Binário vem do FORM (o Postgres anterior não o repassa). Chave normalizada
// para 'data' (o Upload Storage usa esse nome fixo).
const CODE_LISTAR = `
${FONTE_BYTES_BINARIO}
const caso_id = $('Upsert Caso (Postgres)').first().json.caso_id;
const form = $('Intake (Form)').first();
const bin = form.binary || {};
const out = [];
for (const key of Object.keys(bin)) {
  // O TAMANHO VIAJA COM O ITEM. É o insumo do orçamento: sem ele o lote é
  // estimado por um número plano que já recusou um lote de US$ 1,41 dizendo
  // US$ 7,65. \`null\` quando o metadado não permite medir — e null cai no
  // plano lá na frente, nunca em zero.
  out.push({ json: { caso_id, nome_original: bin[key].fileName || key, binary_key: 'data', bytes: bytesDoBinario(bin[key]) }, binary: { data: bin[key] } });
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
// TETOS: 2000x60, nao 50x25 -- espelha lib/spreadsheet.mjs (MAX_LINHAS_PLANILHA).
// 50 linhas e' menos do que um documento real tem (24 meses x 5 entidades = 120;
// balancete analitico passa de 500) e o resto ia embora com uma nota no prompt
// que so' a IA lia. Item 1 do 7.4 do Onboarding.
// Colunas pela UNIAO das chaves, nao pelas da primeira linha: o Extract From File
// devolve objeto esparso, e celula vazia na linha 0 apagava a coluna do documento
// inteiro.
function colsPlan(rows){const s=new Set();for(const r of rows){if(r&&typeof r==='object')for(const k of Object.keys(r))s.add(k);}return [...s];}
function sheetTxt(rows,mr=2000,mc=60){if(!rows.length)return '(planilha vazia)';const cols=colsPlan(rows).slice(0,mc);const head=cols.join(' | ');const body=rows.slice(0,mr).map(r=>cols.map(c=>String(r[c]??'')).join(' | ')).join('\\n');const ex=rows.length>mr?('\\n... (+'+(rows.length-mr)+' linhas omitidas)'):'';return head+'\\n'+body+ex;}
// O que ficou de fora vira PENDENCIA (falha_motivo -> 0016), nao nota no prompt.
function avisoSheet(rows,mr=2000,mc=60){if(!Array.isArray(rows)||!rows.length)return null;const nc=colsPlan(rows).length;const p=[];if(rows.length>mr)p.push((rows.length-mr)+' de '+rows.length+' linhas nao foram enviadas a extracao (teto de '+mr+')');if(nc>mc)p.push((nc-mc)+' de '+nc+' colunas nao foram enviadas a extracao (teto de '+mc+')');if(!p.length)return null;return 'Planilha maior que o teto de envio: '+p.join('; ')+'. A extracao deste documento esta INCOMPLETA -- o que falta nao esta no banco nem no book. Reenvie o arquivo fatiado ou peca ao dono para elevar o teto.';}
let part; let aviso=null;
if(/pdf/.test(mt)) part={type:'file',file:{filename:item.nome_original||'documento.pdf',file_data:'data:application/pdf;base64,'+b64}};
else if(mt.indexOf('image/')===0) part={type:'image_url',image_url:{url:'data:'+mt+';base64,'+b64}};
else if(/csv/.test(mt)||mt==='text/plain'){const txt=buf.toString('utf-8');const rows=parseCsv(txt);part={type:'text',text:sheetTxt(rows)};aviso=avisoSheet(rows);}
// XLSX: o conteudo NAO e' extraido. A versao anterior mandava esta frase como se
// fosse o documento -- a IA recebia um recado de configuracao no lugar do balanco,
// devolvia "nao ha linhas", e a pendencia dizia que a EXTRACAO falhou, nao que o
// arquivo nunca foi lido. A chamada continua sendo feita (pular exige no' IF, e'
// mudanca de topologia da fase 3); o que muda e' que o motivo real vira pendencia.
else if(/spreadsheetml|ms-excel|excel/.test(mt)){part={type:'text',text:'(XLSX nao extraido: habilitar Extract From File no N8N -- ver README. Nome: '+(item.nome_original||'')+')'};aviso='Arquivo .xlsx/.xls NAO foi lido: o no "Extract From File" nao esta habilitado nesta instancia do n8n, entao NENHUM dado deste documento chegou a extracao. O que este documento contem nao esta no banco nem no book.';}
else {part={type:'text',text:'(conteudo nao suportado: '+mt+')'};aviso='Formato nao suportado pelo preparo de conteudo ('+mt+'): NENHUM dado deste documento chegou a extracao.';}
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
// O binario segue: quem precisa dele depois daqui e' o \`Upload Storage\` (ramo
// lateral) e o \`Extrair Texto\`, que le a camada de texto do PDF. Da\u00ed para a
// frente ninguem mais precisa -- o \`content_part\` ja' carrega o arquivo em
// base64 DENTRO do json, e e' ele que vai para a OpenAI.
return {json:{...item, content_part: part, content_mime: mt, hash, aviso_conteudo: aviso}, binary: $input.item.binary};
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
// E ele passou a MEDIR o custo desta chamada (13/08/2026). Até aqui só a
// extração media o seu — a classificação era a metade da conta que ninguém
// olhava, e é exatamente a metade cujo preço acabou de mudar (gpt-4o →
// gpt-4o-mini). Sem `custo_classificacao_usd` na saída do nó, a economia
// prometida por este repositório seria verificável só na fatura da OpenAI, no
// fim do mês, misturada com todo o resto.
const CODE_PARSE_CLASSIF = `
${FONTE_DIAGNOSTICO_ERRO}
${FONTE_CUSTO_CHAMADA}
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
// \`content_part\` FICA no item (antes era descartado aqui junto do openai_body).
// Motivo: o \`Montar Req Extracao\` precisa do PDF, e ele o buscava em
// \`$('Preparar Conteudo').item\` -- pareamento que atravessa a convergencia dos
// dois ramos e por isso nao e' confiavel. Dado que o item CARREGA nao depende de
// pareamento nenhum. Só o \`openai_body\` da CLASSIFICACAO sai (aquele ja' foi
// usado, e levá-lo adiante incharia cada item com o base64 duas vezes).
const {openai_body, ...item}=src;
const resp=$json;
const content=resp?.choices?.[0]?.message?.content;
const fromName={tipo_taxonomia:item.tipo_taxonomia, periodo_tipo:item.periodo_tipo, periodo_ref:item.periodo_ref, assinado:item.assinado, entidade:item.entidade, confianca:item.confianca};
// Custo REAL desta chamada, pelo mesmo \`custoDaChamada\` da extracao e pelo
// modelo que ESTE no' pediu. Vai em TODOS os caminhos de saida: a chamada que
// falhou depois de consumir tokens tambem foi paga, e um custo que so' aparece
// no caminho feliz e' um custo subdeclarado.
const custo_classificacao_usd=custoDaChamada(resp?.usage, '${MODEL_CLASSIFICACAO}');
if(!content){
  // A classificação DEGRADA para o nome do arquivo quando a IA falha — e isso é
  // o certo (fail-safe). O que não pode é a justificativa dizer só "falha de
  // rede/API": no "teste v30" os 14 documentos ficaram classificados pelo nome
  // com essa frase genérica, enquanto a causa real era a OpenAI recusando TODA
  // chamada. A causa vai junto, com o mesmo diagnóstico da extração.
  const motivo=resp?.error?diagnosticarErroApi(resp.error).motivo:'A chamada a OpenAI nao retornou conteudo (falha de rede/API).';
  return {json:{...item, custo_classificacao_usd, ...mergeClassification(fromName, {tipo_taxonomia:null, confianca:0, justificativa:'Classificacao por conteudo indisponivel, valeu o nome do arquivo. '+motivo})}};
}
let p; try{p=typeof content==='string'?JSON.parse(content):content;}catch(e){
  return {json:{...item, custo_classificacao_usd, ...mergeClassification(fromName, {tipo_taxonomia:null, confianca:0, justificativa:'Resposta da OpenAI nao veio em JSON valido.'})}};
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
return {json:{...item, custo_classificacao_usd, ...mergeClassification(fromName, fromAI)}};
`.trim();

// --- Code (EACH ITEM): monta corpo da chamada de DIAGNÓSTICO+EXTRAÇÃO (E2) -
// $json vem do Registrar Documento (linha {r:{documento_id, documento_versao_id}}).
// O conteúdo do arquivo volta por referência ao Preparar Conteudo. Espelha
// n8n/lib/extract.mjs: SEMPRE roda (não só no fallback de baixa confiança) —
// é a ÚNICA leitura de conteúdo garantida para todo documento, por isso
// também busca entidade e faz o diagnóstico (confere tipo/período/legibilidade).
const CODE_REQ_EXTRACAO = `
const reg=$json;
const versaoId=reg.documento_versao_id||null;
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
// O CONTEUDO VEM DO PROPRIO ITEM. O \`Recompor Contexto\` (no' anterior) ja' juntou
// o resultado do Postgres com o contexto do preparo POR INDICE, entao aqui nao se
// pareia com no' nenhum -- era a leitura pareada do no' de preparo, feita daqui,
// que atravessava a convergencia dos dois ramos e perdeu 19 dos 35 no V45.
const prep=$json;
// SEM CONTEUDO, NAO SE CHAMA A OPENAI. Uma requisicao montada sem o documento
// volta "sem nenhuma linha" SEM erro de API -- extracao vazia que parece sucesso,
// que e' exatamente o silencio que este projeto passa o tempo fechando. Lancar
// aqui vira item de erro (onError: continue), o lote segue, e o motivo aparece.
if(!prep.content_part){
  throw new Error('Conteudo do documento indisponivel ao montar a extracao (content_part ausente): a chamada NAO foi feita, para nao pagar por uma extracao sem o arquivo. Causa provavel: o Recompor Contexto nao encontrou o item de origem -- ver o log desta execucao.');
}
const schema=${SCHEMA_EXTRACAO};
const promptSistema=${JSON.stringify(SYSTEM_PROMPT)};
const body={model:'${MODEL_EXTRACAO}',temperature:0,max_tokens:${MAX_OUTPUT_TOKENS},response_format:{type:'json_schema',json_schema:schema},messages:[
  {role:'system',content:promptSistema},
  {role:'user',content:[{type:'text',text:'Nome do arquivo: '+(prep.nome_original||'(sem nome)')+'. Dica de tipo (do nome, pode estar errada): '+(prep.tipo_taxonomia||'desconhecido')+'. Diagnostique e extraia as linhas financeiras.'}, prep.content_part]}
]};
// aviso_conteudo viaja junto: o que o preparo ja sabia estar faltando ANTES da
// chamada (planilha acima do teto, XLSX nao lido) tem de virar pendencia mesmo
// quando a extracao volta impecavel -- o pedaco que falta nunca chegou a IA.
// documento_id VIAJA COM O ITEM, e nao e' luxo: depois do fatiamento os nos
// seguintes nao conseguem mais resolver \`$('Registrar Documento').item\` -- um
// no' que muda a QUANTIDADE de itens (1 documento -> N blocos -> 1 documento)
// quebra a cadeia de pareamento do n8n, e a expressao volta \`undefined\`. Foi
// exatamente isso que derrubou a execucao 6164: "Query Parameters must be a
// string of comma-separated values" no Registrar Diagnostico e no Reconciliar.
// Dado que o item CARREGA nao depende de pareamento nenhum.
const docId=reg.documento_id||null;
return {json:{documento_id:docId, documento_versao_id:versaoId, tipo:prep.tipo_taxonomia||null, aviso_conteudo:prep.aviso_conteudo??null, openai_body:body}};
`.trim();

// --- Code (ALL ITEMS): recompõe contexto + resultado do Postgres, POR ÍNDICE --
//
// Existe porque o nó Postgres SUBSTITUI o item: depois do `Registrar Documento` o
// item é só `{r:{documento_id, documento_versao_id, ...}}`, e o `content_part`
// (o PDF) morre ali. O `Montar Req Extracao` buscava o conteúdo de volta em
// `$('Preparar Conteudo').item` — pareamento que atravessa a convergência dos
// dois ramos do `Precisa Fallback?`, e foi ele que perdeu 19 dos 35 documentos do
// "Teste V45 - Canastra" (zero linha, zero evento, zero pendência).
//
// A junção é por ÍNDICE, e isso é sólido: `Registrar Documento` roda
// `executeQuery` uma vez por item de entrada e devolve uma linha por item, na
// MESMA ordem — 1:1, inclusive quando um item falha (PG_RETRY tem
// `continueRegularOutput`, então o item de erro ocupa a posição dele). E
// `$('Juntar Ramos').all()` devolve a saída INTEIRA daquele nó, sem depender de
// `pairedItem` nenhum: é a diferença entre "me dê o item pareado com este" (que
// falhou) e "me dê a lista, eu sei minha posição nela".
//
// DIVERGÊNCIA DE CONTAGEM É FALHA DECLARADA, nunca ajuste silencioso: se as duas
// listas tiverem tamanhos diferentes, a correspondência por índice deixou de ser
// verdadeira, e continuar associaria o PDF de um documento ao id de outro — o
// pior erro possível aqui. Cada item sem par sai com o motivo escrito, e a guarda
// do `Gravar Campos` (0016/0043) o converte em pendência visível.
const CODE_RECOMPOR_CONTEXTO = `
const regs=$input.all();
let ctx=[];
try{ ctx=$('Juntar Ramos').all(); }catch(e){ ctx=[]; }
const desalinhado=ctx.length!==regs.length;
const saida=[];
for(let i=0;i<regs.length;i+=1){
  const r=regs[i].json||{};
  const res=r.r||r;
  const base=(!desalinhado&&ctx[i]&&ctx[i].json)?ctx[i].json:{};
  const {openai_body:_ob, ...limpo}=base;
  const motivos=[];
  if(desalinhado){
    motivos.push('Recompor Contexto: o Registrar Documento devolveu '+regs.length+' item(ns) e o Juntar Ramos '+ctx.length+' -- a correspondencia por indice deixou de ser verdadeira, e associar o arquivo de um documento ao id de outro seria pior que falhar. Contexto NAO recomposto.');
  }
  saida.push({pairedItem:{item:i}, json:{...limpo,
    documento_id:res.documento_id??null,
    documento_versao_id:res.documento_versao_id??null,
    recompor_motivo:motivos.length>0?motivos.join(' | '):null,
  }});
}
return saida;
`.trim();

// --- Code (EACH ITEM): CAMADA 1 — a régua do documento ----------------------
//
// Roda logo depois do `Extrair Texto` e existe por um motivo de MECÂNICA do n8n
// que custou duas execuções para ser entendido:
//
//   • `Extract From File` SUBSTITUI o item (escreve o resultado do PDF no `json`
//     e não repassa o binário). Posto entre `Lote cabe?` e `Preparar Conteudo`,
//     ele levou junto caso_id, classificação e arquivo — 35 documentos recusados
//     pelo banco com "null value in column caso_id".
//   • Pendurado como ramo LATERAL, ele parou de derrubar o lote — e parou também
//     de ser LIDO: `$('Nó').item` só resolve para nós ANCESTRAIS do item atual, e
//     um ramo irmão não é ancestral. A medição voltou vazia em todos os
//     documentos (`celulas_nos_documentos: 0`), e com ela as camadas 2 e 3
//     ficaram desligadas sem ninguém notar.
//
// A saída é pôr o `Extrair Texto` na corrente DEPOIS do `Preparar Conteudo`:
// nesse ponto o binário ainda existe (o preparo o repassa), o `content_part` já
// carrega o arquivo em base64 dentro do json — então perder o binário daqui para
// a frente não custa nada — e este nó recompõe o contexto lendo o
// `Preparar Conteudo`, que agora É ancestral.
const CODE_MEDIR_DOCUMENTO = `
${FONTE_COBERTURA}
// O texto vem do PROPRIO input (o \`Extrair Texto\` e' o no' anterior): nao depende
// de pareamento nenhum. O contexto vem do \`Preparar Conteudo\`, ancestral.
const doExtrator=$input.item.json||{};
const textoPdf=(typeof doExtrator.text==='string'&&doExtrator.text)||(typeof doExtrator.texto_pdf==='string'&&doExtrator.texto_pdf)||'';
let item={};
try{ item=$('Preparar Conteudo').item.json||{}; }catch(e){ item={}; }
const linhasDoTexto=linhasComNumero(textoPdf);
const temTexto=linhasDoTexto.length>0;
// AUSENCIA DE TEXTO NAO E' ERRO: PDF escaneado nao tem camada de texto, e o
// documento segue como imagem exatamente como antes -- so' as camadas 2 e 3 se
// calam para ele. \`null\` e' "nao sei", nunca "zero": zero ligaria a guarda de
// cobertura com regua inventada justamente no documento onde o modelo mais erra.
return {json:{...item,
  // DUAS reguas, e a distincao e' o que fez a guarda voltar a enxergar:
  //   celulas -> toda linha com digito. E' o tamanho da RESPOSTA, e e' o que o
  //     fatiamento precisa saber (cabecalho tambem gasta token).
  //   contas  -> so' linha de conta (rotulo + valor), sem cabecalho de ano, CNPJ,
  //     data nem assinatura. E' a unidade da COBERTURA, comparavel com as contas
  //     distintas que a extracao grava. Medido no 02_DRE: 46 contra 39.
  celulas_no_documento: temTexto?linhasDoTexto.length:null,
  contas_no_documento: temTexto?linhasDeConta(textoPdf).length:null,
  linhas_do_texto: temTexto?linhasDoTexto:null,
}};
`.trim();

// --- Code (ALL ITEMS): CAMADA 2 — FATIAR O QUE NÃO CABE NUMA CHAMADA ---------
//
// O gpt-4o tem teto de 16.384 tokens de SAÍDA. Um documento cuja extração passa
// disso é cortado no meio (`finish_reason=length`) e volta sem nada de
// aproveitável — foi o que aconteceu com dois documentos do book-canastra, um
// com 326 e outro com 308 células de valor.
//
// Este nó não conserta truncamento: ele o torna IMPOSSÍVEL. Com a contagem da
// camada 1, projeta a saída e, quando ela passa de 60% do teto, emite um item
// por BLOCO — cada um com a mesma requisição, mais uma instrução de faixa.
//
// Por que ele existe separado do `Montar Req Extracao` em vez de virar um
// fan-out lá: aquele nó roda em `runOnceForEachItem` e depende de
// `$('Preparar Conteudo').item` para achar o contexto do SEU item. Trocar o modo
// quebraria esse pareamento — e os itens chegam ali por dois caminhos (com e sem
// classificação por conteúdo), então a ordem não é a de `Preparar Conteudo`.
// Fatiar DEPOIS, sobre itens que já carregam tudo, não tem esse problema.
const CODE_FATIAR_EXTRACAO = `
${FONTE_COBERTURA}
const saida=[];
const entradas=$input.all();
for(let idx=0; idx<entradas.length; idx+=1){
  const it=entradas[idx];
  const j=it.json||{};
  // Documento sem medida (PDF escaneado, sem camada de texto) vai inteiro, como
  // sempre foi. Fatiar as cegas seria pior: sem ancora, "bloco 2 de 3" e' um
  // pedido para o modelo adivinhar onde a faixa comeca.
  const linhas=Array.isArray(j.linhas_do_texto)?j.linhas_do_texto:[];
  const fatias=linhas.length>0?planejarFatias(linhas, MAX_CELULAS_POR_BLOCO):[{bloco:1,blocos:1,de:0,ate:0,ancoraInicio:null,ancoraFim:null,celulas:0}];
  for(const f of fatias){
    // A instrucao da faixa vai na mensagem de USER, nunca no prompt de sistema:
    // o prefixo tem de continuar identico em toda chamada para o cache de
    // prefixo da OpenAI valer (docs/CUSTO_OPENAI.md, alavanca 3).
    const corpo=JSON.parse(JSON.stringify(j.openai_body||{}));
    const instrucao=instrucaoDaFatia(f);
    if(instrucao&&Array.isArray(corpo.messages)){
      const user=corpo.messages[corpo.messages.length-1];
      if(user&&Array.isArray(user.content)&&user.content[0]&&typeof user.content[0].text==='string'){
        user.content[0].text=user.content[0].text+instrucao;
      }
    }
    // \`linhas_do_texto\` fica para tras: ele ja' virou ancora, e levar o
    // documento inteiro em texto por todo o grafo incharia cada item a' toa.
    // \`content_part\` sai pelo mesmo motivo, e agora ele PRECISA sair: desde que o
    // conteudo passou a viajar com o item (para nao depender de pareamento), o
    // base64 do PDF esta no json -- e ele ja' foi copiado para dentro do \`corpo\`.
    // Levar as duas copias por todo o resto do grafo dobraria a memoria do lote.
    const {linhas_do_texto:_l, openai_body:_b, content_part:_cp, ...resto}=j;
    // \`pairedItem\` E' OBRIGATORIO num no' que muda a quantidade de itens. Sem
    // ele o n8n perde a cadeia e toda referencia a OUTRO no' por \`.item\` rio
    // abaixo volta undefined -- os nos Postgres recebem "undefined" em Query
    // Parameters e a execucao morre. Cada bloco aponta para o documento que o gerou.
    saida.push({json:{...resto, openai_body:corpo, bloco:f.bloco, blocos:f.blocos, celulas_do_bloco:f.celulas}, pairedItem:{item:idx}});
  }
}
return saida;
`.trim();

// --- Code (ALL ITEMS): junta os blocos e APLICA A GUARDA DE COBERTURA --------
//
// CAMADA 3. Depois de reunir os blocos de cada documento, compara o que voltou
// com o que a camada 1 mediu. Abaixo do limiar, escreve o motivo em
// `falha_motivo` — que `fn_registrar_campos_extraidos` já converte em pendência.
// Não precisa de migration: o caminho de "extração que não trouxe o que devia"
// já existe desde a `0016`; o que faltava era alguém CONFERIR.
//
// É esta camada que responde ao pedido do dono ("que nunca mais apareça"): ela
// não impede o modelo de pular uma linha — impede que isso seja silencioso. O
// livro razão devolveu 99 de 461 e passou como sucesso; com isto ele para na
// fila de revisão com os dois números na descrição.
const CODE_JUNTAR_BLOCOS = `
${FONTE_COBERTURA}
const porDocumento=new Map();
const primeiroIndice=new Map();
const entradas=$input.all();
for(let idx=0; idx<entradas.length; idx+=1){
  const j=entradas[idx].json||{};
  // A CHAVE NAO PODE SER INVENTADA. A primeira versao usava
  // \`'sem-versao-'+tamanho\` quando o id faltava, e esse texto ia direto para
  // \`fn_registrar_campos_extraidos($1::uuid)\`: "invalid input syntax for type
  // uuid: sem-versao-0", execucao 6164. Um id ausente e' uma FALHA a declarar,
  // nunca um id de mentira -- agrupa-se sob null e o motivo vai junto.
  const chave=(typeof j.documento_versao_id==='string'&&j.documento_versao_id)?j.documento_versao_id:'__sem_versao__';
  if(!porDocumento.has(chave)){ porDocumento.set(chave,[]); primeiroIndice.set(chave,idx); }
  porDocumento.get(chave).push(j);
}
const saida=[];
for(const [chave, blocos] of porDocumento){
  const r=juntarBlocos(blocos);
  const base=blocos[0]||{};
  const documento_versao_id=chave==='__sem_versao__'?null:chave;
  const motivos=r.motivos.slice();
  if(documento_versao_id===null){
    motivos.push('Bloco(s) de extracao voltaram SEM documento_versao_id: as linhas nao tem onde ser gravadas. Causa provavel: falha no no "Registrar Documento" ou perda de contexto entre os blocos -- ver o log desta execucao.');
  }
  // A guarda. \`celulas_no_documento\` e' null no PDF sem camada de texto: nesse
  // caso ela se cala, e o silencio e' declarado (nao ha regua, entao nao ha
  // veredito) em vez de fabricado.
  // CONTAS DISTINTAS, nao pares (conta x coluna): num documento de 3 colunas os
  // pares sao 3x as contas, e comparar par com linha dava 198% de "cobertura" --
  // a guarda ficava cega justamente no comparativo. \`chave\` repetida (livro razao
  // com o mesmo historico) conta uma vez so', e a descricao da pendencia diz isso.
  const contasDistintas=new Set(r.campos.map(c=>c.chave)).size;
  const cobertura=avaliarCobertura({extraidas:contasDistintas, esperadas:base.contas_no_documento});
  if(cobertura) motivos.push(cobertura.motivo);
  if(r.emendasLimpas>0) motivos.push(r.emendasLimpas+' linha(s) repetida(s) na emenda entre blocos foram descartadas (o modelo repetiu a ancora).');
  saida.push({pairedItem:{item:primeiroIndice.get(chave)??0}, json:{
    documento_versao_id,
    // Levado adiante pelo mesmo motivo do documento_versao_id: o Registrar
    // Diagnostico e o Reconciliar liam o no' de registro por \`.item\`, que nao
    // pareia mais atraves do fatiamento. Agora leem do proprio item.
    documento_id:base.documento_id??null,
    campos:r.campos,
    diagnostico:base.diagnostico||null,
    falha_motivo:motivos.length>0?motivos.join(' | '):null,
    blocos:r.blocos,
    celulas_no_documento:base.celulas_no_documento??null,
    contas_no_documento:base.contas_no_documento??null,
    contas_distintas:contasDistintas,
    cobertura:cobertura?cobertura.razao:(base.contas_no_documento>0?Number((contasDistintas/base.contas_no_documento).toFixed(3)):null),
    custo_usd:blocos.reduce((soma,b)=>soma+(typeof b.custo_usd==='number'?b.custo_usd:0),0),
    tokens:blocos.reduce((acc,b)=>b.tokens?{entrada:acc.entrada+(b.tokens.entrada||0), saida:acc.saida+(b.tokens.saida||0), cache:acc.cache+(b.tokens.cache||0)}:acc,{entrada:0,saida:0,cache:0}),
  }});
}
return saida;
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
// O contexto vem do FATIAMENTO, nao mais do \`Montar Req Extracao\`: e' ele que
// sabe qual bloco este item e', e um item por bloco significa que o pareamento
// com o no' anterior a ele deixou de ser 1:1. O fallback existe para o caso de
// alguem religar o grafo sem o fatiamento.
let ctx=null;
try{ ctx=$('Fatiar Extracao').item.json; }catch(e){ ctx=null; }
if(!ctx){ try{ ctx=$('Montar Req Extracao').item.json; }catch(e){ ctx=null; } }
// NENHUMA das duas leituras pode DERRUBAR o item: se o pareamento se perder, o
// que se perde e' o contexto, e perder contexto tem de virar falha declarada --
// nao uma excecao que manda o item inteiro para o ramo de erro sem dizer o que
// aconteceu (execucao 6164).
if(!ctx){ ctx={}; }
// O aviso do preparo e o motivo do Recompor Contexto entram JUNTOS: os dois sao
// "dado que o documento tem e o banco nao recebeu", e cabem no mesmo documento.
const avisoConteudo=[ctx.aviso_conteudo??null, ctx.recompor_motivo??null].filter(Boolean).join(' | ')||null;
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
${FONTE_NORMALIZAR_MOEDA}
const unidade=normUnid(p.unidade);
// Moeda do documento herdada por linha, mesma regra da escala (item 2 do 7.4):
// era normalizada e jogada fora aqui, e o book somava USD com BRL.
const moedaDoc=normMoeda(p.moeda);
function naoMonet(k,vt){const n=String(k??'').normalize('NFD').replace(/[\\u0300-\\u036f]/g,'').toLowerCase();return /%|\\bpercentual|\\bpor acao\\b|\\blpa\\b|\\bquantidade\\b|numero de acoes/.test(n)||String(vt??'').includes('%');}
${FONTE_ACHATAR_GRUPOS}
// A saida da OpenAI vem AGRUPADA (uma secao, suas colunas, e uma conta com um
// valor por coluna) e e' achatada aqui de volta para uma linha por
// (conta x coluna) -- a forma que \`campo_extraido\` sempre teve. O achatamento
// vem EMBUTIDO da fonte, nao copiado: se este no' e a lib discordarem sobre como
// associar valor a coluna, o banco recebe o numero de 2024 no lugar do de 2025.
const ach=achatarGrupos(p.grupos);
const campos=ach.linhas.length>0||Array.isArray(p.grupos)
  ? ach.linhas.map((l,i)=>({ordem:i, ...l, unidade:naoMonet(l.chave,l.valor_texto)?null:unidade, moeda:naoMonet(l.chave,l.valor_texto)?null:moedaDoc}))
  // FORMATO PLANO ANTIGO -- o caminho de um workflow importado velho responder
  // no formato de julho. Em 12/08/2026 o n8n do dono rodou dias assim, e "zero
  // linhas extraidas" sem explicacao seria a pior forma de descobrir.
  : (Array.isArray(p.linhas)?p.linhas.map((l,i)=>({ordem:i, secao:l.s??null, secao_canonica:(l.sc&&l.sc!=='NAO_CLASSIFICAVEL')?l.sc:null, entidade_coluna:l.ec??null, periodo_coluna:l.pc??null, chave:l.k, valor_texto:l.vt??null, valor_num:(typeof l.vn==='number')?l.vn:null, unidade:naoMonet(l.k,l.vt)?null:unidade, moeda:naoMonet(l.k,l.vt)?null:moedaDoc, confianca:(typeof l.cf==='number')?l.cf:null, origem_pagina:Number.isInteger(l.op)?l.op:null})):[]);
// Conta descartada por desalinhamento de coluna nao pode sumir em silencio: e'
// dado que o documento tem e o banco nao recebeu.
if(ach.problemas.length>0){
  const dizer=ach.problemas.length+' conta(s) descartada(s) por desalinhamento entre colunas e valores (a associacao valor-coluna ficou desconhecida, e adivinha-la trocaria um periodo pelo outro): '+ach.problemas.slice(0,5).join('; ')+(ach.problemas.length>5?'; ...':'');
  falhaMotivo=falhaMotivo?falhaMotivo+' | '+dizer:dizer;
}
const d=p.diagnostico||{};
const diagnostico={
  entidade: d.entidade??null,
  tipo_confirma: (typeof d.tipo_confirma==='boolean')?d.tipo_confirma:null,
  tipo_sugerido: d.tipo_sugerido==='DESCONHECIDO'?null:(d.tipo_sugerido??null),
  periodo_tipo: d.periodo_referencia?d.periodo_tipo:null,
  periodo_referencia: d.periodo_referencia??null,
  legibilidade: d.legibilidade??null,
  nota_legibilidade: d.nota_legibilidade??null,
  tem_dado_financeiro: (typeof d.tem_dado_financeiro==='boolean')?d.tem_dado_financeiro:null,
  resumo: d.resumo??null,
  justificativa: d.justificativa??'',
};
// Custo REAL desta chamada, do bloco \`usage\` que a OpenAI devolve. Não vai
// para o banco (exigiria migration) — vai para a saída do nó, visível na
// execução do n8n. É com ele que CUSTO_ESTIMADO_DOC_USD deve ser recalibrado:
// hoje o teto de US$ 3 por execução decide em cima de uma ESTIMATIVA declarada,
// e trocar estimativa por medição é o único jeito honesto de apertar o teto.
const custo_usd=custoDaChamada(resp?.usage, '${MODEL_EXTRACAO}');
// O aviso do preparo SOMA-SE ao motivo da chamada em vez de competir com ele:
// planilha cortada E resposta truncada cabem no mesmo documento, e esconder um
// dos dois e' a falha que esta mudanca fecha.
const falhaFinal=[avisoConteudo,falhaMotivo].filter(Boolean).join(' | ')||null;
// \`bloco\`/\`blocos\`/\`celulas_no_documento\` viajam para o \`Juntar Blocos\`: sem
// eles a juncao nao sabe a ordem dos pedacos nem tem regua para a cobertura.
return {json:{documento_id:ctx.documento_id??null, documento_versao_id:ctx.documento_versao_id??null, bloco:ctx.bloco??1, blocos:ctx.blocos??1, celulas_no_documento:ctx.celulas_no_documento??null, campos, diagnostico, falha_motivo:falhaFinal, custo_usd, tokens:resp?.usage?{entrada:resp.usage.prompt_tokens??null, saida:resp.usage.completion_tokens??null, cache:resp.usage.prompt_tokens_details?.cached_tokens??0}:null}};
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

  // O CAMINHO DA RECUSA — três nós, e cada um existe por um motivo.
  //
  // `Lote cabe?` decide; `Registrar Recusa` GRAVA a causa no banco (é o que faz
  // a tela do portal parar de dizer "aguarde" sobre um processo morto); e
  // `Abortar Lote` lança, para a execução aparecer VERMELHA no n8n. Sem o
  // último, a execução ficaria verde tendo recusado o lote — e "deu certo" é a
  // última coisa que ela deve dizer.
  node('Lote cabe?', 'n8n-nodes-base.if', 2, {
    conditions: { options: { caseSensitive: true, typeValidation: 'strict' }, combinator: 'and', conditions: [
      { leftValue: '={{ $json.orcamento_cabe }}', rightValue: true, operator: { type: 'boolean', operation: 'true', singleValue: true } },
    ] },
  }, 760, 260),

  node('Registrar Recusa', 'n8n-nodes-base.postgres', 2.5, {
    operation: 'executeQuery',
    query: 'select fn_registrar_falha_execucao($1::uuid, $2::text, $3::text, $4::text, null) as r',
    options: { queryReplacement: "={{ [$json.caso_id, $('Intake (Form)').first().json['Mandato (nome do caso)'], 'orcamento', $json.orcamento_mensagem] }}" },
  }, 900, 140, { credentials: PG_CRED, ...PG_RETRY }),

  node('Abortar Lote', 'n8n-nodes-base.code', 2, {
    mode: 'runOnceForAllItems',
    jsCode: `throw new Error($input.first().json.orcamento_mensagem || 'Lote recusado pelo orcamento.');`,
  }, 1060, 140),
  // CAMADA 1 — o texto do PDF lido na própria instância, antes de qualquer
  // chamada. Nó NATIVO do n8n; não manda nada para fora e não custa nada.
  //
  // `onError: continueRegularOutput` é o que torna a adição segura: PDF sem
  // camada de texto (escaneado, que é o caso em que este nó falha) segue o
  // caminho de sempre — o documento vai como imagem e as camadas 2 e 3 se calam
  // para ele. O pior caso desta mudança é o comportamento de ontem, nunca um
  // lote perdido.
  node('Extrair Texto', 'n8n-nodes-base.extractFromFile', 1, {
    operation: 'pdf', binaryPropertyName: 'data', options: { joinPages: true },
  }, 960, 400, { onError: 'continueRegularOutput' }),
  node('Preparar Conteudo', 'n8n-nodes-base.code', 2, { mode: 'runOnceForEachItem', jsCode: CODE_PREPARAR_CONTEUDO }, 800, 400, CODE_CONTINUA),
  node('Medir Documento', 'n8n-nodes-base.code', 2, { mode: 'runOnceForEachItem', jsCode: CODE_MEDIR_DOCUMENTO }, 1120, 400, CODE_CONTINUA),

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

  // JUNTA OS DOIS RAMOS DO `Precisa Fallback?` — e existe porque a ausência dele
  // custou 19 dos 35 documentos do "Teste V45 - Canastra".
  //
  // Antes, `Precisa Fallback?`[false] e `Parse OpenAI Classif` apontavam AMBOS
  // para o `Registrar Documento`: duas conexões CRUAS no MESMO input. O n8n não
  // garante uma execução por conexão nesse arranjo — no V45 só o ramo do fallback
  // propagou, e os 19 documentos do ramo direto (justamente os centrais: Balanço,
  // DRE, DFC, DMPL, DVA, balancetes, razão, faturamento) desapareceram ENTRE
  // `Registrar Documento` e `Gravar Campos`. Zero linha, zero evento de extração,
  // zero pendência — o dado não foi extraído errado, ele nunca foi pedido.
  //
  // O Merge em `append` é a resposta canônica do n8n para convergência: uma
  // execução, um lote com os itens dos dois ramos, uma cadeia linear de
  // `pairedItem` rio abaixo. É o que devolve a corrente única que o grafo
  // presumia ter.
  node('Juntar Ramos', 'n8n-nodes-base.merge', 3, {
    mode: 'append', numberInputs: 2,
  }, 1700, 300),

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

  node('Recompor Contexto', 'n8n-nodes-base.code', 2, {
    mode: 'runOnceForAllItems', jsCode: CODE_RECOMPOR_CONTEXTO,
  }, 1980, 300, CODE_CONTINUA),

  node('Montar Req Extracao', 'n8n-nodes-base.code', 2, { mode: 'runOnceForEachItem', jsCode: CODE_REQ_EXTRACAO }, 2100, 300, CODE_CONTINUA),

  // CAMADA 2 — um item por BLOCO. Vê o lote inteiro porque é fan-out (N → M).
  node('Fatiar Extracao', 'n8n-nodes-base.code', 2, {
    mode: 'runOnceForAllItems', jsCode: CODE_FATIAR_EXTRACAO,
  }, 2250, 300, CODE_CONTINUA),
  node('OpenAI Extrair', 'n8n-nodes-base.httpRequest', 4.2, {
    method: 'POST', url: 'https://api.openai.com/v1/chat/completions',
    authentication: 'genericCredentialType',
    genericAuthType: 'httpHeaderAuth',
    sendBody: true, specifyBody: 'json', jsonBody: '={{ JSON.stringify($json.openai_body) }}',
    options: OPENAI_BATCHING_EXTRACAO,
  }, 2300, 300, { onError: 'continueRegularOutput', retryOnFail: true, credentials: { httpHeaderAuth: { id: 'REPLACE', name: 'OpenAI API' } } }),

  node('Parse Extracao', 'n8n-nodes-base.code', 2, { mode: 'runOnceForEachItem', jsCode: CODE_PARSE_EXTRACAO }, 2500, 300, CODE_CONTINUA),

  // CAMADA 3 — junta os blocos de volta em UM item por documento e confere a
  // cobertura. Daqui para a frente o grafo é idêntico ao de sempre: um item por
  // documento, com `campos` e `falha_motivo`.
  node('Juntar Blocos', 'n8n-nodes-base.code', 2, {
    mode: 'runOnceForAllItems', jsCode: CODE_JUNTAR_BLOCOS,
  }, 2650, 300, CODE_CONTINUA),
  node('Gravar Campos (Sombra)', 'n8n-nodes-base.postgres', 2.5, {
    operation: 'executeQuery',
    query: 'select fn_registrar_campos_extraidos($1::uuid, $2::jsonb, p_falha_motivo=>$3::text, p_tem_dado_financeiro=>$4::boolean) as n_campos',
    options: { queryReplacement: "={{ [$json.documento_versao_id, JSON.stringify($json.campos), $json.falha_motivo || null, $json.diagnostico?.tem_dado_financeiro ?? null] }}" },
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
    options: { queryReplacement: "={{ [$json.documento_id, $json.documento_versao_id, $json.diagnostico?.entidade ?? null, $json.diagnostico?.tipo_confirma ?? null, $json.diagnostico?.tipo_sugerido ?? null, $json.diagnostico?.periodo_tipo ?? null, $json.diagnostico?.periodo_referencia ?? null, $json.diagnostico?.legibilidade ?? null, $json.diagnostico?.nota_legibilidade ?? null, $json.diagnostico?.resumo ?? null, $json.diagnostico?.justificativa ?? null] }}" },
  }, 2900, 300, { credentials: PG_CRED, ...PG_RETRY }),

  // E3 (Classe A, N1): roda as checagens aritméticas relevantes ao tipo do
  // documento recém-extraído (docs/04). Só precisa do documento_id — a função
  // resolve caso/entidade/período sozinha (N8N continua stateless). Gera
  // pendência tipada quando diverge ou quando falta pré-condição; nunca
  // escreve "fato" numa base viva (anti-ancoragem, docs/01).
  node('Reconciliar (Classe A)', 'n8n-nodes-base.postgres', 2.5, {
    operation: 'executeQuery',
    query: 'select fn_reconciliar_por_documento($1::uuid) as resultado',
    options: { queryReplacement: '={{ [$json.documento_id] }}' },
  }, 3100, 300, { credentials: PG_CRED, ...PG_RETRY }),

  // O custo do lote em UM painel, no fim da cadeia. `runOnceForAllItems` porque
  // a pergunta é do LOTE, não do documento — e `onError` porque um resumo que
  // derruba o lote que ele resume seria a pior troca possível.
  node('Resumo de Custo', 'n8n-nodes-base.code', 2, {
    mode: 'runOnceForAllItems', jsCode: CODE_RESUMO_CUSTO,
  }, 3300, 300, { onError: 'continueRegularOutput' }),

  // A CONFERÊNCIA DE FORA (0112), o último nó do canvas de propósito: ela pergunta
  // se TODO documento registrado passou pela extração. As três camadas de
  // cobertura medem o que voltou de uma chamada FEITA; nenhuma delas vê a chamada
  // que não aconteceu — e foi assim que o V45 entregou 16 de 35 documentos com o
  // checklist verde. Roda uma vez por lote, não gasta IA, e a saída (`lote_integro`)
  // é o número que decide se a rodada vale.
  node('Conferir Lote', 'n8n-nodes-base.postgres', 2.5, {
    operation: 'executeQuery', query: 'select fn_conferir_lote($1::uuid) as resultado',
    options: { queryReplacement: "={{ $('Upsert Caso (Postgres)').first().json.caso_id }}" },
  }, 3500, 300, { credentials: PG_CRED, ...PG_RETRY }),
];

const connections = {
  'Intake (Form)': { main: [[{ node: 'Upsert Caso (Postgres)', type: 'main', index: 0 }]] },
  'Upsert Caso (Postgres)': { main: [[{ node: 'Listar Arquivos', type: 'main', index: 0 }]] },
  'Listar Arquivos': { main: [[{ node: 'Classificar Nome', type: 'main', index: 0 }]] },
  // O orçamento entra AQUI, entre a classificação por nome e o preparo do
  // conteúdo: é o último ponto em que o lote inteiro está visível de uma vez e
  // ainda não custou nada (nem chamada à OpenAI, nem linha no banco).
  'Classificar Nome': { main: [[{ node: 'Orcamento do Lote', type: 'main', index: 0 }]] },
  'Orcamento do Lote': { main: [[{ node: 'Lote cabe?', type: 'main', index: 0 }]] },
  'Lote cabe?': { main: [
    [{ node: 'Preparar Conteudo', type: 'main', index: 0 }],   // true — segue
    [{ node: 'Registrar Recusa', type: 'main', index: 0 }],    // false — grava e aborta
  ] },
  'Registrar Recusa': { main: [[{ node: 'Abortar Lote', type: 'main', index: 0 }]] },
  // fan-out: upload (lateral) + decisão de fallback (cadeia principal)
  // O `Extrair Texto` entra AQUI, e não antes do preparo: neste ponto o binário
  // ainda existe (o preparo o repassa) e o `content_part` já carrega o arquivo em
  // base64 dentro do json — então o fato de ele descartar o binário deixa de ter
  // consequência. O `Medir Documento` logo depois recompõe o contexto lendo o
  // `Preparar Conteudo`, que É ancestral dele (um ramo irmão não seria).
  'Preparar Conteudo': { main: [[
    { node: 'Upload Storage', type: 'main', index: 0 },
    { node: 'Extrair Texto', type: 'main', index: 0 },
  ]] },
  'Extrair Texto': { main: [[{ node: 'Medir Documento', type: 'main', index: 0 }]] },
  'Medir Documento': { main: [[{ node: 'Precisa Fallback?', type: 'main', index: 0 }]] },
  // Os dois ramos entram em INPUTS DIFERENTES do Merge (0 e 1) — nunca mais duas
  // conexões cruas no mesmo input, que é o que comeu 19 documentos no V45.
  'Precisa Fallback?': { main: [
    [{ node: 'Montar Req Classif', type: 'main', index: 0 }],  // true  → classifica por conteúdo
    [{ node: 'Juntar Ramos', type: 'main', index: 1 }],        // false → direto para o Merge
  ] },
  'Montar Req Classif': { main: [[{ node: 'OpenAI Classificar', type: 'main', index: 0 }]] },
  'OpenAI Classificar': { main: [[{ node: 'Parse OpenAI Classif', type: 'main', index: 0 }]] },
  'Parse OpenAI Classif': { main: [[{ node: 'Juntar Ramos', type: 'main', index: 0 }]] },
  'Juntar Ramos': { main: [[{ node: 'Registrar Documento', type: 'main', index: 0 }]] },
  'Registrar Documento': { main: [[
    { node: 'Recomputar Completude', type: 'main', index: 0 },
    { node: 'Recompor Contexto', type: 'main', index: 0 },
  ]] },
  'Recompor Contexto': { main: [[{ node: 'Montar Req Extracao', type: 'main', index: 0 }]] },
  'Montar Req Extracao': { main: [[{ node: 'Fatiar Extracao', type: 'main', index: 0 }]] },
  'Fatiar Extracao': { main: [[{ node: 'OpenAI Extrair', type: 'main', index: 0 }]] },
  'OpenAI Extrair': { main: [[{ node: 'Parse Extracao', type: 'main', index: 0 }]] },
  'Parse Extracao': { main: [[{ node: 'Juntar Blocos', type: 'main', index: 0 }]] },
  'Juntar Blocos': { main: [[{ node: 'Gravar Campos (Sombra)', type: 'main', index: 0 }]] },
  'Gravar Campos (Sombra)': { main: [[{ node: 'Registrar Diagnostico', type: 'main', index: 0 }]] },
  'Registrar Diagnostico': { main: [[{ node: 'Reconciliar (Classe A)', type: 'main', index: 0 }]] },
  'Reconciliar (Classe A)': { main: [[{ node: 'Resumo de Custo', type: 'main', index: 0 }]] },
  'Resumo de Custo': { main: [[{ node: 'Conferir Lote', type: 'main', index: 0 }]] },
};

const workflow = {
  name: 'Oria — E1 Ingestão + Diagnóstico + E2 Extração-Sombra + E3 Reconciliação Classe A (Fatia 1)',
  nodes, connections, settings: { executionOrder: 'v1' },
  meta: { note: 'Gerado por n8n/build-workflow.mjs. Nós Code espelham n8n/lib/ (testado). Diagnóstico de conteúdo roda SEMPRE (entidade/tipo/período/legibilidade); E2 em N0/sombra; E3 Classe A em N1 (gera pendência, nunca fato).' },
};

writeFileSync(join(__dirname, 'workflow.e1-ingestao.json'), JSON.stringify(workflow, null, 2) + '\n');
console.log('Escrito workflow —', nodes.length, 'nós,', Object.keys(connections).length, 'conexões');
