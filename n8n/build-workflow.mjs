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
// 5. Posição de nó no canvas NÃO se escreve aqui: quem desenha é `posicionar()`
//    (n8n/layout.mjs), a partir das `connections`. Nó novo declara só a conexão.

import { posicionar } from './layout.mjs';
import { writeFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import { codigosConhecidos } from './lib/ia.mjs';
import {
  provedor, urlDaChamada, montarCorpoIA, schemaDoProvedor, parteDeArquivo, parteDeTexto,
  conteudoDaResposta, cortadoPorLimite, usoDaChamada, acrescentarInstrucao,
} from './lib/provedor.mjs';
import { createHash } from 'node:crypto';
import { SYSTEM_PROMPT, diagnosticarErroApi, MAX_OUTPUT_TOKENS, TPM_CONTA, RPM_CONTA, normalizarUnidade, normalizarMoeda, extractionSchema, achatarGrupos } from './lib/extract.mjs';
import { ALIASES } from './lib/taxonomia.mjs';
import { parseEntidade } from './lib/classifier.mjs';
import { orcamentoDoLote, orcamentoDoLotePorConteudo, custoEstimadoPorConteudo, tokensDeSaida, TETO_EXECUCAO_USD, CUSTO_ESTIMADO_DOC_USD, CUSTO_POR_MB_USD, CUSTO_MINIMO_CHAMADA_USD, bytesDoBinario, custoDaChamada, PRECO_USD_POR_MILHAO, MODELO_CLASSIFICACAO, MODELO_EXTRACAO, PARCELA_ENTRADA_NA_CHAMADA, PESO_MINIMO_CLASSIFICACAO, VERSAO_ORCAMENTO, pesoDaChamadaDeClassificacao, TOKENS_POR_PAGINA_IMAGEM, TOKENS_CABECALHO_GRUPO, TOKENS_CONTA_BASE, TOKENS_POR_VALOR, CONTAS_POR_GRUPO, TOKENS_SAIDA_CLASSIFICACAO, MARGEM_ORCAMENTO_CONTEUDO, CARACTERES_POR_TOKEN } from './lib/custo.mjs';
import { sha256Hex } from './lib/hash.mjs';
import {
  linhasComNumero, linhasDeConta, celulasDaLinha, celulasEstimadas,
  planejarFatias, instrucaoDaFatia, juntarBlocos, avaliarCobertura,
  MAX_CELULAS_POR_BLOCO, LIMIAR_COBERTURA, MINIMO_PARA_AVALIAR,
} from './lib/cobertura.mjs';

const __dirname = dirname(fileURLToPath(import.meta.url));

// Enums da classificação — IMPORTADOS de lib/ia.mjs (fonte única), não
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

// Schemas estritos (mesma forma dos módulos lib/ia.mjs e lib/extract.mjs).
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
// O FINGERPRINT DA EXTRAÇÃO — o que autoriza NÃO pagar a mesma extração duas
// vezes (db/migrations/0118).
//
// Ele responde a uma pergunta só: "a extração que já está no banco foi feita
// com as MESMAS regras que eu usaria agora?". As regras são três — o prompt de
// sistema, o modelo e o esquema de resposta —, e todas as três mudam neste
// repositório com frequência (a 0116 acabou de mexer no prompt). Calculado aqui,
// no BUILD, e embutido como literal na chamada de registro: assim o valor muda
// junto com o workflow, e um workflow importado em julho nunca casa com a
// extração de hoje.
//
// Os 16 primeiros hex bastam: é identidade, não segurança — colisão acidental
// em 64 bits de conteúdo controlado não é um risco que valha uma coluna maior.
const FINGERPRINT_EXTRACAO = createHash('sha256')
  .update([SYSTEM_PROMPT, MODELO_EXTRACAO, JSON.stringify(extractionSchema())].join('\u0000'))
  .digest('hex')
  .slice(0, 16);

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
  // A estimativa POR CONTEÚDO e as seis constantes dela. Mesma regra de
  // sempre: `toString()` não leva o escopo do módulo, então tudo o que o
  // corpo referencia é declarado aqui — inclusive o tamanho do prompt de
  // sistema, que é calculado no BUILD a partir do texto real (o nó não tem
  // como importar `extract.mjs` para medi-lo em execução).
  `const TOKENS_POR_PAGINA_IMAGEM = ${TOKENS_POR_PAGINA_IMAGEM};`,
  `const TOKENS_CABECALHO_GRUPO = ${TOKENS_CABECALHO_GRUPO};`,
  `const TOKENS_CONTA_BASE = ${TOKENS_CONTA_BASE};`,
  `const TOKENS_POR_VALOR = ${TOKENS_POR_VALOR};`,
  `const CONTAS_POR_GRUPO = ${CONTAS_POR_GRUPO};`,
  `const TOKENS_SAIDA_CLASSIFICACAO = ${TOKENS_SAIDA_CLASSIFICACAO};`,
  `const MARGEM_ORCAMENTO_CONTEUDO = ${MARGEM_ORCAMENTO_CONTEUDO};`,
  `const TOKENS_PROMPT_SISTEMA = ${Math.ceil(SYSTEM_PROMPT.length / CARACTERES_POR_TOKEN)};`,
  // `custoDaChamada` é o que converte tokens em dólares, e ela também não vem
  // de graça: sem esta linha o nó estoura `ReferenceError` na primeira
  // execução REAL — que é o modo de falha mais caro possível, porque a suíte
  // fica verde e o lote morre no cliente.
  `const custoDaChamada = ${custoDaChamada.toString()};`,
  `const tokensDeSaida = ${tokensDeSaida.toString()};`,
  `const custoEstimadoPorConteudo = ${custoEstimadoPorConteudo.toString()};`,
  `const orcamentoDoLotePorConteudo = ${orcamentoDoLotePorConteudo.toString()};`,
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
  `const celulasDaLinha = ${celulasDaLinha.toString()};`,
  `const celulasEstimadas = ${celulasEstimadas.toString()};`,
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

// ---------------------------------------------------------------------------
// O PROVEDOR DENTRO DOS NÓS
// ---------------------------------------------------------------------------
//
// O provedor ativo entra nos nós Code como um LITERAL (`const PROVEDOR = {...}`)
// e as funções que falam com ele entram por `toString()`, como todas as outras
// funções espelhadas. É por isso que `lib/provedor.mjs` descreve cada provedor
// como dado puro e não como objeto com métodos: dado atravessa a fronteira do nó
// Code, método não.
//
// O QUE ISSO COMPRA, e é o ponto da troca inteira: trocar de provedor deixa de
// ser achar cada literal `choices[0].message.content` espalhado pelo gerador e
// passa a ser uma variável de ambiente mais um rebuild. As funções abaixo são as
// MESMAS que a lib usa e que as suítes exercitam — não há uma segunda
// implementação minificada do dialeto vivendo aqui dentro.
const PROV = provedor();
const FONTE_PROVEDOR = [
  `const PROVEDOR = ${JSON.stringify(PROV)};`,
  `const parteDeTexto = ${parteDeTexto.toString()};`,
  `const parteDeArquivo = ${parteDeArquivo.toString()};`,
  `const schemaDoProvedor = ${schemaDoProvedor.toString()};`,
  `const montarCorpoIA = ${montarCorpoIA.toString()};`,
  `const conteudoDaResposta = ${conteudoDaResposta.toString()};`,
  `const cortadoPorLimite = ${cortadoPorLimite.toString()};`,
  `const usoDaChamada = ${usoDaChamada.toString()};`,
  `const acrescentarInstrucao = ${acrescentarInstrucao.toString()};`,
].join('\n');

// --- Code (ALL ITEMS): o TETO DE GASTO POR EXECUÇÃO -------------------------
// RODA DEPOIS DO `Medir Documento`, e a mudança de lugar É a correção.
//
// Onde ele ficava: entre `Classificar Nome` e `Preparar Conteudo`. Ali o guarda
// tem o nome do arquivo e os bytes, e mais nada — então estimava por TAMANHO,
// com uma margem de 1,8× que superestima o lote típico em ~50%, e não tinha
// como saber quantos BLOCOS a extração ia gastar (documento acima de
// `MAX_CELULAS_POR_BLOCO` é fatiado, e cada fatia reenvia o PDF inteiro). Errava
// para cima no lote comum e para baixo no documento grande, que é o caro.
//
// Onde ele fica: logo depois de o texto do PDF ter sido lido e medido. Aqui as
// duas coisas que mandam no custo são EXATAS — as linhas com número saem do
// próprio documento, e o número de blocos sai de `planejarFatias`, a mesma
// função que o `Fatiar Extracao` vai executar adiante.
//
// E CONTINUA SENDO ANTES DE GASTAR, que é a propriedade inegociável: entre o
// `Medir Documento` e a primeira chamada à OpenAI (`IA Classificar`) não há
// gasto nenhum. O `Extrair Texto` é local, o `Upload Storage` é ramo lateral e
// está desligado, e nenhum documento foi registrado — `Registrar Documento` vem
// depois do `Juntar Ramos`. Barrar aqui continua custando zero.
//
// A ESTIMATIVA POR BYTE NÃO FOI EMBORA: ela é o caminho de quando o conteúdo não
// pôde ser medido. PDF escaneado não tem camada de texto, e um lote com QUALQUER
// documento assim cai inteiro no caminho antigo — medir só os que dá
// subestimaria o lote na exata proporção do que não se sabe.
const CODE_ORCAMENTO = `
${FONTE_ORCAMENTO_LOTE}
${FONTE_COBERTURA}
const itens = $input.all();
const docs = itens.map((i) => {
  const j = i.json || {};
  // Blocos: a MESMA conta que o \`Fatiar Extracao\` fará. Documento sem camada de
  // texto vai inteiro (uma chamada), como sempre foi.
  const linhas = Array.isArray(j.linhas_do_texto) ? j.linhas_do_texto : [];
  // A MESMA CONTA DO \`Fatiar Extracao\`, com os MESMOS pesos. Duas estimativas da
  // mesma quantidade e' como elas divergem: se o orcamento previsse 1 bloco e o
  // fatiamento fizesse 4, o guarda de gasto mediria um lote que nao e' o que vai
  // rodar.
  const pesos = linhas.length > 0 ? celulasEstimadas(linhas) : [];
  const blocos = linhas.length > 0 ? planejarFatias(linhas, MAX_CELULAS_POR_BLOCO, pesos).length : 1;
  // CELULAS E COLUNAS, as duas MEDIDAS no texto.
  //
  // Antes as colunas vinham do NOME do arquivo ("25,24,23" são três; "12M25" é
  // uma), e o comentário de então declarava esse limite: coluna de EMPRESA não
  // aparece no nome. O que ele NÃO dizia é que \`celulas\` recebia a contagem de
  // LINHAS — e \`tokensDeSaida\` usa \`colunas\` para DIVIDIR células em contas, de
  // modo que passar linha onde ele espera célula fazia \`contas = linhas / colunas\`
  // num lugar em que a linha JÁ É a conta. As duas pontas erradas de uma vez, e o
  // erro se somava com o do fatiamento em vez de cancelar.
  //
  // Agora as duas saem do próprio texto (\`Medir Documento\`), e a razão
  // células/linhas conta a coluna de empresa junto — sem ler nome de arquivo.
  const celulas = Number.isFinite(Number(j.celulas_estimadas)) ? Number(j.celulas_estimadas)
    : Number(j.celulas_no_documento);
  const colunas = Number.isFinite(Number(j.colunas_estimadas)) && Number(j.colunas_estimadas) > 0
    ? Number(j.colunas_estimadas) : 1;
  return {
    celulas,
    paginas: Number(j.paginas_do_documento),
    colunas,
    blocos,
    precisaFallback: !!j.precisa_fallback_ia,
    bytes: Number(j.bytes),
  };
});
const r = orcamentoDoLotePorConteudo({ documentos: docs, teto: ${TETO_EXECUCAO_USD}, custoPorChamada: ${CUSTO_ESTIMADO_DOC_USD}, tokensPromptSistema: TOKENS_PROMPT_SISTEMA });
// Recusa o lote INTEIRO. Não existe "roda os que cabem" de propósito: metade
// registrada sem extração e metade sem registro nenhum é estado que dá mais
// trabalho para desfazer do que o reenvio que esta mensagem pede.
//
// E A RECUSA NÃO LANÇA AQUI: ela marca. Lançar punha a mensagem certa no lugar
// errado — ficava só no log do n8n, e o portal, que deduz progresso da ausência
// de documentos, seguia dizendo "estamos organizando tudo com cuidado" para
// sempre. Agora o item segue marcado, o IF manda a recusa para o nó que a GRAVA
// no banco, e só depois o lote é abortado.
//
// \`orcamento_versao\` viaja com o item mesmo quando o lote PASSA. É o que
// responde, da tela do n8n, a pergunta que custou uma rodada em 12/08: "este
// workflow é o que está no repositório ou é o que foi importado em julho?".
return itens.map(i => ({ json: { ...i.json, orcamento_cabe: r.cabe, orcamento_mensagem: r.mensagem, orcamento_estimado_usd: r.estimadoUSD, orcamento_teto_usd: r.teto, orcamento_chamadas: r.chamadas, orcamento_versao: r.versao, orcamento_por_conteudo: !!r.porConteudo }, binary: i.binary }));
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
// passam pelo Parse Classif (8 de 14, no book do dono), então o índice i
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
const classificacoes = itensDe('Parse Classif');

let extracao = 0, entrada = 0, saida = 0, cache = 0, linhas = 0, comFalha = 0, semMedicao = 0;
let celulas = 0, contas = 0, fatiados = 0;
for (const it of extracoes) {
  const e = it?.json || {};
  if (typeof e.custo_usd === 'number') extracao += e.custo_usd; else semMedicao += 1;
  if (e.tokens) { entrada += e.tokens.entrada || 0; saida += e.tokens.saida || 0; cache += e.tokens.cache || 0; }
  if (e.falha_motivo) comFalha += 1;
  linhas += Array.isArray(e.campos) ? e.campos.length : 0;
  if (Number.isFinite(Number(e.contas_no_documento))) celulas += Number(e.contas_no_documento);
  // O painel do lote soma a MESMA unidade da guarda: linhas devolvidas contra
  // linhas de conta do texto. \`contas_distintas\` continua saindo por documento,
  // porque e' ela que diz se o documento tem rotulo repetido.
  if (Number.isFinite(Number(e.linhas_devolvidas))) contas += Number(e.linhas_devolvidas);
  else if (Number.isFinite(Number(e.contas_distintas))) contas += Number(e.contas_distintas);
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
return {json:{...item, tipo_taxonomia:tipo, periodo_tipo:periodo?periodo.tipo:null, periodo_ref:periodo?periodo.referencia:null, assinado, entidade:parseEntidade(t,ALIASES), confianca:conf, fonte:'nome_arquivo', precisa_fallback_ia:(conf<0.7|| !tipo)}, binary: $input.item.binary};
`.trim();

// --- Code (EACH ITEM): prepara a parte de CONTEUDO (para todos os docs) ---
// pdf→file; imagem→image_url; csv→texto (parse inline); xlsx→nota (ver README).
// Preserva o binário (o Upload Storage roda como ramo a partir deste node).
const CODE_PREPARAR_CONTEUDO = `
${FONTE_SHA256}
${FONTE_PROVEDOR}
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
function csvConta(t,alvo){let n=0,d=false;for(let i=0;i<t.length;i++){const c=t[i];if(c==='"'){if(d&&t[i+1]==='"'){i++;continue;}d=!d;}else if(c===alvo&&!d)n++;else if(c==='\\n'&&!d)break;}return n;}\nfunction csvRegs(t,sep){const R=[];let f='',r=[],d=false;for(let i=0;i<t.length;i++){const c=t[i];if(d){if(c==='"'){if(t[i+1]==='"'){f+='"';i++;}else d=false;}else f+=c;continue;}if(c==='"'){d=true;continue;}if(c===sep){r.push(f);f='';continue;}if(c==='\\r')continue;if(c==='\\n'){r.push(f);R.push(r);r=[];f='';continue;}f+=c;}r.push(f);R.push(r);return R.filter(x=>x.some(y=>y.trim()!==''));}\nfunction parseCsv(t){const s=String(t||'');if(s.trim()==='')return [];const sep=csvConta(s,';')>csvConta(s,',')?';':',';const R=csvRegs(s,sep);if(!R.length)return [];const h=R[0].map(c=>c.trim());return R.slice(1).map(c=>{const o={};h.forEach((k,i)=>o[k||('col'+i)]=(c[i]??'').trim());return o;});}
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
// A FORMA DA PARTE E' DO PROVEDOR, e por isso ela sai de \`parteDeArquivo\`, a
// mesma funcao que a lib usa -- nao de tres literais escritos aqui. Eram eles
// que faziam a troca de provedor ser "achar cada lugar": um PDF montado na forma
// da OpenAI e' 400 no Google, e o 400 chega como falha da chamada, sem dizer que
// o defeito estava no PREPARO.
let part; let aviso=null;
if(/pdf/.test(mt)||mt.indexOf('image/')===0) part=parteDeArquivo(PROVEDOR,{mimeType:mt,base64:b64,filename:item.nome_original||'documento.pdf'});
else if(/csv/.test(mt)||mt==='text/plain'){const txt=buf.toString('utf-8');const rows=parseCsv(txt);part=parteDeTexto(PROVEDOR,sheetTxt(rows));aviso=avisoSheet(rows);}
// XLSX: o conteudo NAO e' extraido. A versao anterior mandava esta frase como se
// fosse o documento -- a IA recebia um recado de configuracao no lugar do balanco,
// devolvia "nao ha linhas", e a pendencia dizia que a EXTRACAO falhou, nao que o
// arquivo nunca foi lido. A chamada continua sendo feita (pular exige no' IF, e'
// mudanca de topologia da fase 3); o que muda e' que o motivo real vira pendencia.
else if(/spreadsheetml|ms-excel|excel/.test(mt)){part=parteDeTexto(PROVEDOR,'(XLSX nao extraido: habilitar Extract From File no N8N -- ver README. Nome: '+(item.nome_original||'')+')');aviso='Arquivo .xlsx/.xls NAO foi lido: o no "Extract From File" nao esta habilitado nesta instancia do n8n, entao NENHUM dado deste documento chegou a extracao. O que este documento contem nao esta no banco nem no book.';}
else {part=parteDeTexto(PROVEDOR,'(conteudo nao suportado: '+mt+')');aviso='Formato nao suportado pelo preparo de conteudo ('+mt+'): NENHUM dado deste documento chegou a extracao.';}
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
${FONTE_PROVEDOR}
const item=$input.item.json;
const schema=${SCHEMA_CLASSIF};
const body=montarCorpoIA(PROVEDOR,{modelo:'${MODEL_CLASSIFICACAO}',schema,partes:[parteDeTexto(PROVEDOR,'Nome (pista fraca): '+(item.nome_original||'')), item.content_part],sistema:'Classifique o documento financeiro na taxonomia da Oria (Reestruturacao, Brasil). Periodos: 12M25=ano 2025; 1T25=1o tri/2025; L24M=ultimos 24 meses; 23,24,25=multiplos exercicios; ano isolado como 2025 tambem e valido. IMPORTANTE: sempre tente identificar o tipo mais provavel dentre os codigos conhecidos, mesmo com confianca baixa -- analise cabecalhos, rotulos de linhas, estrutura de colunas e demais pistas visuais. DESCONHECIDO e reservado somente para documentos genuinamente ilegiveis/corrompidos ou que claramente nao sao documentos financeiros. Baixa confianca nao e motivo para deixar de dar um palpite -- e motivo para registrar o palpite com confianca baixa correspondente e uma justificativa objetiva. Nunca invente valores (numeros, entidade, periodo) que nao estao no documento, mas sempre ofereca sua melhor hipotese de tipo. O campo justificativa e obrigatorio: explicacao objetiva e especifica (1-2 frases) do que voce viu (ou nao viu) no documento que sustenta a classificacao e a confianca escolhida -- evite respostas genericas como nao foi possivel determinar.'});
return {json:{...item, ia_body: body}};
`.trim();

// --- Code (EACH ITEM): parse da classificação -----------------------------
// Contexto vem do node anterior por referência (a resposta HTTP substituiu o
// item). Remove os campos pesados (ia_body/content_part) do que segue.
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
${FONTE_PROVEDOR}
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
    confianca:winner.confianca??0,
    fonte:winner===fromAI?'openai_conteudo':'nome_arquivo',
    justificativa:fromAI.justificativa||'',
  };
}
const src=$('Montar Req Classif').item.json;
// \`content_part\` FICA no item (antes era descartado aqui junto do ia_body).
// Motivo: o \`Montar Req Extracao\` precisa do PDF, e ele o buscava em
// \`$('Preparar Conteudo').item\` -- pareamento que atravessa a convergencia dos
// dois ramos e por isso nao e' confiavel. Dado que o item CARREGA nao depende de
// pareamento nenhum. Só o \`ia_body\` da CLASSIFICACAO sai (aquele ja' foi
// usado, e levá-lo adiante incharia cada item com o base64 duas vezes).
const {ia_body, ...item}=src;
const resp=$json;
const content=conteudoDaResposta(PROVEDOR,resp);
const fromName={tipo_taxonomia:item.tipo_taxonomia, periodo_tipo:item.periodo_tipo, periodo_ref:item.periodo_ref, assinado:item.assinado, entidade:item.entidade, confianca:item.confianca};
// Custo REAL desta chamada, pelo mesmo \`custoDaChamada\` da extracao e pelo
// modelo que ESTE no' pediu. Vai em TODOS os caminhos de saida: a chamada que
// falhou depois de consumir tokens tambem foi paga, e um custo que so' aparece
// no caminho feliz e' um custo subdeclarado.
const custo_classificacao_usd=custoDaChamada(usoDaChamada(PROVEDOR,resp), '${MODEL_CLASSIFICACAO}');
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
${FONTE_PROVEDOR}
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
const body=montarCorpoIA(PROVEDOR,{modelo:'${MODEL_EXTRACAO}',sistema:promptSistema,schema,maxTokens:${MAX_OUTPUT_TOKENS},partes:[
  parteDeTexto(PROVEDOR,'Nome do arquivo: '+(prep.nome_original||'(sem nome)')+'. Dica de tipo (do nome, pode estar errada): '+(prep.tipo_taxonomia||'desconhecido')+'. Diagnostique e extraia as linhas financeiras.'),
  prep.content_part]});
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
return {json:{documento_id:docId, documento_versao_id:versaoId, tipo:prep.tipo_taxonomia||null, aviso_conteudo:prep.aviso_conteudo??null, ia_body:body}};
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
  const {ia_body:_ob, ...limpo}=base;
  const motivos=[];
  if(desalinhado){
    motivos.push('Recompor Contexto: o Registrar Documento devolveu '+regs.length+' item(ns) e o Juntar Ramos '+ctx.length+' -- a correspondencia por indice deixou de ser verdadeira, e associar o arquivo de um documento ao id de outro seria pior que falhar. Contexto NAO recomposto.');
  }
  saida.push({pairedItem:{item:i}, json:{...limpo,
    documento_id:res.documento_id??null,
    documento_versao_id:res.documento_versao_id??null,
    // 0118: o banco JA' SABE se esta extracao foi feita antes com o mesmo prompt.
    // O flag viaja daqui para o IF \`Extracao ja feita?\`, que e' quem pula a
    // chamada a' OpenAI. Ausente (workflow contra banco sem a 0118) vira false --
    // pular por omissao seria deixar de extrair de graca.
    reaproveitou_extracao:res.reaproveitou_extracao===true,
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
// AS CELULAS, contadas linha a linha. O \`Extract From File\` entrega o texto
// AGRUPADO POR LINHA, e uma linha de comparativo de tres exercicios produz TRES
// celulas -- contar linha como celula deixava o fatiamento de 1,7x a 6,8x mais
// frouxo do que o nome dele diz, e na pratica DESLIGADO: medido, nenhum dos 38
// documentos do book-canastra era fatiado. Ver o comentario de \`celulasDaLinha\`.
const pesosDaLinha=temTexto?celulasEstimadas(linhasDoTexto):[];
const celulasEstim=pesosDaLinha.reduce((a,b)=>a+b,0);
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
  // A TERCEIRA regua, e e' ela que decide o FATIAMENTO e o custo de SAIDA:
  // celulas de valor estimadas do proprio texto. \`colunas_estimadas\` sai da
  // razao celulas/linhas -- e substitui a leitura do NOME do arquivo, que so'
  // via coluna de PERIODO ("2025x2024x2023") e era cega a coluna de EMPRESA
  // (um combinado de seis empresas contava como uma coluna).
  celulas_estimadas: temTexto?celulasEstim:null,
  colunas_estimadas: temTexto?Math.max(1,Math.round(celulasEstim/linhasDoTexto.length)):null,
  // PAGINAS: quem paga a entrada da chamada e' a IMAGEM do PDF (~1.000 tokens
  // por pagina), entao o teto de gasto precisa deste numero -- e ele so' existe
  // aqui, na saida do \`Extrair Texto\` (o \`pdf-parse\` publica \`numpages\`).
  // \`null\` quando o extrator nao disse: o orcamento entao cai para a conta por
  // BYTE, que e' a saida conservadora, em vez de supor uma pagina.
  paginas_do_documento: Number.isFinite(Number(doExtrator.numpages))?Number(doExtrator.numpages)
    :(Number.isFinite(Number(doExtrator.numPages))?Number(doExtrator.numPages):null),
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
${FONTE_PROVEDOR}
const saida=[];
const entradas=$input.all();
for(let idx=0; idx<entradas.length; idx+=1){
  const it=entradas[idx];
  const j=it.json||{};
  // Documento sem medida (PDF escaneado, sem camada de texto) vai inteiro, como
  // sempre foi. Fatiar as cegas seria pior: sem ancora, "bloco 2 de 3" e' um
  // pedido para o modelo adivinhar onde a faixa comeca.
  const linhas=Array.isArray(j.linhas_do_texto)?j.linhas_do_texto:[];
  // OS PESOS EM CELULAS, e nao a contagem de linhas: \`MAX_CELULAS_POR_BLOCO\` e'
  // derivado de quantas CELULAS cabem em 60% do teto de saida, e aplica-lo a
  // linhas era o erro de unidade que desligava este no' na pratica.
  const fatias=linhas.length>0?planejarFatias(linhas, MAX_CELULAS_POR_BLOCO, celulasEstimadas(linhas)):[{bloco:1,blocos:1,de:0,ate:0,ancoraInicio:null,ancoraFim:null,celulas:0,linhas:0,acimaDoTeto:false}];
  for(const f of fatias){
    // A instrucao da faixa vai na mensagem de USER, nunca no prompt de sistema:
    // o prefixo tem de continuar identico em toda chamada para o cache de
    // prefixo da OpenAI valer (docs/CUSTO_OPENAI.md, alavanca 3).
    const corpo=JSON.parse(JSON.stringify(j.ia_body||{}));
    // ONDE a instrucao entra e' do provedor (\`contents\` no Google, \`messages\`
    // na OpenAI); QUE ela nao entra no prompt de sistema e' invariante nosso.
    acrescentarInstrucao(PROVEDOR,corpo,instrucaoDaFatia(f));
    // \`linhas_do_texto\` fica para tras: ele ja' virou ancora, e levar o
    // documento inteiro em texto por todo o grafo incharia cada item a' toa.
    // \`content_part\` sai pelo mesmo motivo, e agora ele PRECISA sair: desde que o
    // conteudo passou a viajar com o item (para nao depender de pareamento), o
    // base64 do PDF esta no json -- e ele ja' foi copiado para dentro do \`corpo\`.
    // Levar as duas copias por todo o resto do grafo dobraria a memoria do lote.
    const {linhas_do_texto:_l, ia_body:_b, content_part:_cp, ...resto}=j;
    // \`pairedItem\` E' OBRIGATORIO num no' que muda a quantidade de itens. Sem
    // ele o n8n perde a cadeia e toda referencia a OUTRO no' por \`.item\` rio
    // abaixo volta undefined -- os nos Postgres recebem "undefined" em Query
    // Parameters e a execucao morre. Cada bloco aponta para o documento que o gerou.
    // A FAIXA VIAJA COM O ITEM. Sem \`bloco_de\`/\`bloco_ate\` a unica forma de
    // saber qual pedaco do documento uma chamada cobriu e' reler o texto que o
    // item nem leva mais -- e quando um bloco volta vazio, e' isso que se
    // pergunta primeiro. \`bloco_acima_do_teto\` e' a promessa de
    // \`planejarFatias\` chegando a quem le a execucao: linha que sozinha nao cabe
    // no teto nao tem corte mais fino, e o caso nao pode ficar em silencio.
    saida.push({json:{...resto, ia_body:corpo, bloco:f.bloco, blocos:f.blocos,
      celulas_do_bloco:f.celulas, linhas_do_bloco:f.linhas??null,
      bloco_de:f.de, bloco_ate:f.ate, bloco_acima_do_teto:!!f.acimaDoTeto}, pairedItem:{item:idx}});
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
  // LINHAS devolvidas, nao contas distintas: num livro razao o mesmo historico
  // aparece em varios lancamentos (99 linhas, 66 historicos no book), e comparar
  // contas distintas com LINHAS do texto acusava de incompleta uma extracao
  // PERFEITA -- 66%, abaixo do limiar, pendencia falsa por construcao. As duas
  // pontas agora sao linha. O fallback para contas distintas cobre o bloco vindo
  // no formato plano antigo, que nao tem \`linha_origem\`: comportamento identico
  // ao de antes desta correcao, em vez de cobertura zero.
  const linhasDevolvidas=r.linhasRetornadas>0?r.linhasRetornadas:contasDistintas;
  const cobertura=avaliarCobertura({extraidas:linhasDevolvidas, esperadas:base.contas_no_documento});
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
    linhas_devolvidas:linhasDevolvidas,
    cobertura:cobertura?cobertura.razao:(base.contas_no_documento>0?Number((linhasDevolvidas/base.contas_no_documento).toFixed(3)):null),
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
${FONTE_PROVEDOR}
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
const cortado=cortadoPorLimite(PROVEDOR,resp);
const content=conteudoDaResposta(PROVEDOR,resp);
let p={}; let falhaMotivo=null;
if(resp?.error){
  falhaMotivo=diagnosticarErroApi(resp.error).motivo;
}else if(!content){
  falhaMotivo='Resposta do provedor de IA ('+PROVEDOR.rotulo+') sem conteudo (falha de rede/API).';
}else{
  try{p=typeof content==='string'?JSON.parse(content):content;}catch(e){
    falhaMotivo=cortado
      ?'Resposta do provedor de IA truncada por limite de tokens de saida -- o JSON ficou incompleto e nao pode ser interpretado. Documento provavelmente grande/denso demais (muitas contas/entidades) para uma unica chamada.'
      :'Resposta do provedor de IA nao veio em JSON valido.';
    p={};
  }
}
if(!falhaMotivo&&cortado){
  falhaMotivo='Resposta do provedor de IA atingiu o limite de tokens de saida; o JSON veio valido, mas o conteudo pode estar incompleto (faltando linhas do fim do documento).';
}
${FONTE_NORMALIZAR_UNIDADE}
${FONTE_NORMALIZAR_MOEDA}
const unidade=normUnid(p.unidade);
// Moeda do documento herdada por linha, mesma regra da escala (item 2 do 7.4):
// era normalizada e jogada fora aqui, e o book somava USD com BRL.
const moedaDoc=normMoeda(p.moeda);
function naoMonet(k,vt){const n=String(k??'').normalize('NFD').replace(/[\\u0300-\\u036f]/g,'').toLowerCase();return /%|\\bpercentual|\\bpor acao\\b|\\blpa\\b|\\bquantidade\\b|numero de acoes/.test(n)||String(vt??'').includes('%');}
${FONTE_ACHATAR_GRUPOS}
// A saida da IA vem AGRUPADA (uma secao, suas colunas, e uma conta com um
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
const uso=usoDaChamada(PROVEDOR,resp);
const custo_usd=custoDaChamada(uso, '${MODEL_EXTRACAO}');
// O aviso do preparo SOMA-SE ao motivo da chamada em vez de competir com ele:
// planilha cortada E resposta truncada cabem no mesmo documento, e esconder um
// dos dois e' a falha que esta mudanca fecha.
const falhaFinal=[avisoConteudo,falhaMotivo].filter(Boolean).join(' | ')||null;
// \`bloco\`/\`blocos\`/\`celulas_no_documento\` viajam para o \`Juntar Blocos\`: sem
// eles a juncao nao sabe a ordem dos pedacos nem tem regua para a cobertura.
return {json:{documento_id:ctx.documento_id??null, documento_versao_id:ctx.documento_versao_id??null, bloco:ctx.bloco??1, blocos:ctx.blocos??1, celulas_no_documento:ctx.celulas_no_documento??null, campos, diagnostico, falha_motivo:falhaFinal, custo_usd, tokens:uso?{entrada:uso.prompt_tokens??null, saida:uso.completion_tokens??null, cache:uso.prompt_tokens_details?.cached_tokens??0}:null}};
`.trim();

const PG_CRED = { postgres: { id: 'REPLACE', name: 'Supabase Postgres (Session Pooler)' } };
// `position` NÃO entra aqui: quem posiciona é `posicionar()` (n8n/layout.mjs), a
// partir das `connections`, depois que a lista inteira existe. Coordenada
// escolhida à mão nó a nó foi o que embaralhou o canvas (rótulo em cima de
// rótulo, linha atravessando nó), e ela não tem como saber do vizinho que ainda
// nem foi declarado.
const node = (name, type, typeVersion, parameters, opts = {}) => ({
  parameters, id: name.toLowerCase().replace(/[^a-z0-9]+/g, '-'), name, type, typeVersion,
  position: [0, 0],
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

// O PISO DE 6s É HISTÓRICO E FICA: veio do "teste v18", em que 3 de 16
// documentos ainda tomaram 429 com 3s. Ele não depende de provedor — é a folga
// mínima que a experiência com o n8n do dono mostrou ser necessária.
const PISO_BATCHING_MS = 6000;

// O QUE DEPENDE DO PROVEDOR É O LIMITE POR CHAMADA. Quando ele existe (RPM), o
// intervalo tem de respeitá-lo contando que um documento mal nomeado faz DUAS
// chamadas — a de classificação e a de extração, em nós diferentes, no mesmo
// minuto. Dividir o minuto pelo RPM e esquecer a segunda chamada é o jeito
// aritmeticamente garantido de tomar 429 no meio do lote: os dois nós somam.
const CHAMADAS_MAX_POR_DOCUMENTO = 2;
const INTERVALO_POR_RPM_MS = RPM_CONTA
  ? Math.ceil((60000 / RPM_CONTA) * CHAMADAS_MAX_POR_DOCUMENTO)
  : 0;

const IA_BATCHING = {
  batching: { batch: { batchSize: 1, batchInterval: Math.max(PISO_BATCHING_MS, INTERVALO_POR_RPM_MS) } },
  ...RESPOSTA_COM_CORPO_NO_ERRO,
};

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
// TPM_CONTA/RPM_CONTA são os ÚNICOS números a ajustar, e eles moram no provedor
// (`lib/provedor.mjs`), lidos por `lib/extract.mjs` junto de MAX_OUTPUT_TOKENS,
// porque o teste de cadência e o `diagnosticar-ia.mjs` leem os MESMOS valores —
// duplicar aqui faria os três discordarem no primeiro ajuste. Subir de tier é
// mexer numa linha lá: no Tier 2 da OpenAI (450.000 TPM) o intervalo cai para
// ~2,2s, a diferença entre 8 minutos e 30 segundos para o mesmo lote.
// E AGORA O RPM ENTRA NA CONTA, porque nem todo provedor tem o mesmo gargalo.
// Na OpenAI o balde de TOKENS sempre chega primeiro (a reserva de `max_tokens`
// garante isso), e o intervalo é o de sempre: ~33s no Tier 1. Na linha
// Flash-Lite do Google o balde de tokens é folgado e o limite é de CHAMADAS: só
// pelo TPM o intervalo daria ~1 segundo, e o lote tomaria 429 na terceira.
//
// O intervalo é o MAIOR dos três — o do balde de tokens, o do limite de
// chamadas, e o piso histórico de 6s. É o mesmo princípio de sempre: errar para
// o lento atrasa; errar para o rápido FALHA, e falha custa a rodada inteira.
const CHAMADAS_POR_MINUTO = TPM_CONTA / MAX_OUTPUT_TOKENS;
const INTERVALO_EXTRACAO_MS = Math.max(
  Math.ceil(60000 / CHAMADAS_POR_MINUTO),
  INTERVALO_POR_RPM_MS,
  PISO_BATCHING_MS,
);

const IA_BATCHING_EXTRACAO = { batching: { batch: { batchSize: 1, batchInterval: INTERVALO_EXTRACAO_MS } }, ...RESPOSTA_COM_CORPO_NO_ERRO };

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
  }),

  node('Upsert Caso (Postgres)', 'n8n-nodes-base.postgres', 2.5, {
    operation: 'executeQuery', query: 'select fn_upsert_caso($1::text) as caso_id',
    options: { queryReplacement: "={{ [$json['Mandato (nome do caso)']] }}" },
  }, { credentials: PG_CRED, ...PG_RETRY }),

  node('Listar Arquivos', 'n8n-nodes-base.code', 2, { mode: 'runOnceForAllItems', jsCode: CODE_LISTAR }),

  node('Classificar Nome', 'n8n-nodes-base.code', 2, { mode: 'runOnceForEachItem', jsCode: CODE_CLASSIFICAR }, CODE_CONTINUA),

  node('Orcamento do Lote', 'n8n-nodes-base.code', 2, { mode: 'runOnceForAllItems', jsCode: CODE_ORCAMENTO }),

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
  }),

  node('Registrar Recusa', 'n8n-nodes-base.postgres', 2.5, {
    operation: 'executeQuery',
    query: 'select fn_registrar_falha_execucao($1::uuid, $2::text, $3::text, $4::text, null) as r',
    options: { queryReplacement: "={{ [$json.caso_id, $('Intake (Form)').first().json['Mandato (nome do caso)'], 'orcamento', $json.orcamento_mensagem] }}" },
  }, { credentials: PG_CRED, ...PG_RETRY }),

  node('Abortar Lote', 'n8n-nodes-base.code', 2, {
    mode: 'runOnceForAllItems',
    jsCode: `throw new Error($input.first().json.orcamento_mensagem || 'Lote recusado pelo orcamento.');`,
  }),
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
  }, { onError: 'continueRegularOutput' }),
  node('Preparar Conteudo', 'n8n-nodes-base.code', 2, { mode: 'runOnceForEachItem', jsCode: CODE_PREPARAR_CONTEUDO }, CODE_CONTINUA),
  node('Medir Documento', 'n8n-nodes-base.code', 2, { mode: 'runOnceForEachItem', jsCode: CODE_MEDIR_DOCUMENTO }, CODE_CONTINUA),

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
  }, { credentials: { httpHeaderAuth: { id: 'REPLACE', name: 'Supabase Service (Header Auth)' } }, disabled: true }),

  node('Precisa Fallback?', 'n8n-nodes-base.if', 2, {
    conditions: { options: { caseSensitive: true, typeValidation: 'strict' }, combinator: 'and', conditions: [
      { leftValue: '={{ $json.precisa_fallback_ia }}', rightValue: true, operator: { type: 'boolean', operation: 'true', singleValue: true } },
    ] },
  }),

  node('Montar Req Classif', 'n8n-nodes-base.code', 2, { mode: 'runOnceForEachItem', jsCode: CODE_REQ_CLASSIF }, CODE_CONTINUA),

  // Falha do provedor NÃO derruba o workflow: segue com a resposta de erro, o
  // Parse produz confiança 0 → pendência de classificação (fail-safe).
  //
  // Auth via credencial Header Auth do n8n — sem `$env`, que é bloqueado por
  // padrão. O NOME da credencial e o header que ela preenche saem do provedor
  // ativo (`lib/provedor.mjs`): na OpenAI é "Authorization: Bearer sk-...", no
  // Google é "x-goog-api-key: ...". A chave NUNCA vai na URL como `?key=`: a URL
  // do nó aparece na tela de execução e no log, e isso é segredo em lugar de
  // leitura.
  node('IA Classificar', 'n8n-nodes-base.httpRequest', 4.2, {
    method: 'POST', url: urlDaChamada(PROV, MODEL_CLASSIFICACAO),
    authentication: 'genericCredentialType',
    genericAuthType: 'httpHeaderAuth',
    sendBody: true, specifyBody: 'json', jsonBody: '={{ JSON.stringify($json.ia_body) }}',
    options: IA_BATCHING,
  }, { onError: 'continueRegularOutput', retryOnFail: true, credentials: { httpHeaderAuth: { id: 'REPLACE', name: PROV.credencial } } }),

  node('Parse Classif', 'n8n-nodes-base.code', 2, { mode: 'runOnceForEachItem', jsCode: CODE_PARSE_CLASSIF }, CODE_CONTINUA),

  // JUNTA OS DOIS RAMOS DO `Precisa Fallback?` — e existe porque a ausência dele
  // custou 19 dos 35 documentos do "Teste V45 - Canastra".
  //
  // Antes, `Precisa Fallback?`[false] e `Parse Classif` apontavam AMBOS
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
  }),

  // $14 usa notação nomeada (p_justificativa=>) para pular o p_threshold (14º
  // parâmetro, mantém o default 0.7) sem precisar repeti-lo explicitamente.
  node('Registrar Documento', 'n8n-nodes-base.postgres', 2.5, {
    operation: 'executeQuery',
    query: 'select fn_registrar_documento($1::uuid,$2::text,$3::text,$4::text,$5::text,$6::numeric,$7::text,$8::origem_arquivo,$9::text,$10::text,$11::boolean,$12::text,$13::legibilidade, p_justificativa=>$14::text, p_fingerprint_extracao=>$15::text) as r',
    options: { queryReplacement: `={{ [$json.caso_id, $json.entidade || null, $json.periodo_tipo || null, $json.periodo_ref || null, $json.tipo_taxonomia || null, $json.confianca, $json.fonte, 'supabase_storage', $json.caso_id + '/' + $json.nome_original, $json.nome_original, $json.assinado, $json.hash || null, 'ok', $json.justificativa || null, '${FINGERPRINT_EXTRACAO}'] }}` },
  }, { credentials: PG_CRED, ...PG_RETRY }),

  node('Recomputar Completude', 'n8n-nodes-base.postgres', 2.5, {
    operation: 'executeQuery', query: 'select fn_recomputar_completude($1::uuid) as resultado',
    options: { queryReplacement: "={{ $('Upsert Caso (Postgres)').first().json.caso_id }}" },
  }, { credentials: PG_CRED, ...PG_RETRY }),

  node('Recompor Contexto', 'n8n-nodes-base.code', 2, {
    mode: 'runOnceForAllItems', jsCode: CODE_RECOMPOR_CONTEXTO,
  }, CODE_CONTINUA),

  // O CURTO-CIRCUITO DO DEDUP (0118). A `fn_registrar_documento` já respondeu se
  // este arquivo foi extraído antes com o MESMO prompt+modelo+esquema e se aquela
  // extração tem linha no banco. Quando sim, não há nada a pedir à OpenAI: o dado
  // já está lá, sob a mesma versão, e o item pula direto para a reconciliação.
  //
  // O IF fica AQUI, e não dentro do `Montar Req Extracao`, por uma restrição do
  // n8n que a 0026 já tinha mapeado: aquele nó é `runOnceForEachItem` e não pode
  // devolver zero itens. Filtrar com um IF é o jeito que o motor oferece.
  node('Extracao ja feita?', 'n8n-nodes-base.if', 2, {
    conditions: { options: { caseSensitive: true, typeValidation: 'strict' }, combinator: 'and', conditions: [
      { leftValue: '={{ $json.reaproveitou_extracao }}', rightValue: true, operator: { type: 'boolean', operation: 'true', singleValue: true } },
    ] },
  }),

  // E o Merge que junta quem extraiu com quem não precisou. Merge, e não duas
  // conexões cruas no mesmo input: foi convergência crua que fez 19 de 35
  // documentos desaparecerem no Teste V45 (ver `Juntar Ramos`).
  node('Juntar Extraidos', 'n8n-nodes-base.merge', 3, {
    mode: 'append', numberInputs: 2,
  }),

  node('Montar Req Extracao', 'n8n-nodes-base.code', 2, { mode: 'runOnceForEachItem', jsCode: CODE_REQ_EXTRACAO }, CODE_CONTINUA),

  // CAMADA 2 — um item por BLOCO. Vê o lote inteiro porque é fan-out (N → M).
  node('Fatiar Extracao', 'n8n-nodes-base.code', 2, {
    mode: 'runOnceForAllItems', jsCode: CODE_FATIAR_EXTRACAO,
  }, CODE_CONTINUA),
  node('IA Extrair', 'n8n-nodes-base.httpRequest', 4.2, {
    method: 'POST', url: urlDaChamada(PROV, MODEL_EXTRACAO),
    authentication: 'genericCredentialType',
    genericAuthType: 'httpHeaderAuth',
    sendBody: true, specifyBody: 'json', jsonBody: '={{ JSON.stringify($json.ia_body) }}',
    options: IA_BATCHING_EXTRACAO,
  }, { onError: 'continueRegularOutput', retryOnFail: true, credentials: { httpHeaderAuth: { id: 'REPLACE', name: PROV.credencial } } }),

  node('Parse Extracao', 'n8n-nodes-base.code', 2, { mode: 'runOnceForEachItem', jsCode: CODE_PARSE_EXTRACAO }, CODE_CONTINUA),

  // CAMADA 3 — junta os blocos de volta em UM item por documento e confere a
  // cobertura. Daqui para a frente o grafo é idêntico ao de sempre: um item por
  // documento, com `campos` e `falha_motivo`.
  node('Juntar Blocos', 'n8n-nodes-base.code', 2, {
    mode: 'runOnceForAllItems', jsCode: CODE_JUNTAR_BLOCOS,
  }, CODE_CONTINUA),
  node('Gravar Campos (Sombra)', 'n8n-nodes-base.postgres', 2.5, {
    operation: 'executeQuery',
    query: 'select fn_registrar_campos_extraidos($1::uuid, $2::jsonb, p_falha_motivo=>$3::text, p_tem_dado_financeiro=>$4::boolean) as n_campos',
    options: { queryReplacement: "={{ [$json.documento_versao_id, JSON.stringify($json.campos), $json.falha_motivo || null, $json.diagnostico?.tem_dado_financeiro ?? null] }}" },
  }, { credentials: PG_CRED, ...PG_RETRY }),

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
  }, { credentials: PG_CRED, ...PG_RETRY }),

  // E3 (Classe A, N1): roda as checagens aritméticas relevantes ao tipo do
  // documento recém-extraído (docs/04). Só precisa do documento_id — a função
  // resolve caso/entidade/período sozinha (N8N continua stateless). Gera
  // pendência tipada quando diverge ou quando falta pré-condição; nunca
  // escreve "fato" numa base viva (anti-ancoragem, docs/01).
  node('Reconciliar (Classe A)', 'n8n-nodes-base.postgres', 2.5, {
    operation: 'executeQuery',
    query: 'select fn_reconciliar_por_documento($1::uuid) as resultado',
    options: { queryReplacement: '={{ [$json.documento_id] }}' },
  }, { credentials: PG_CRED, ...PG_RETRY }),

  // O custo do lote em UM painel, no fim da cadeia. `runOnceForAllItems` porque
  // a pergunta é do LOTE, não do documento — e `onError` porque um resumo que
  // derruba o lote que ele resume seria a pior troca possível.
  node('Resumo de Custo', 'n8n-nodes-base.code', 2, {
    mode: 'runOnceForAllItems', jsCode: CODE_RESUMO_CUSTO,
  }, { onError: 'continueRegularOutput' }),

  // O CUSTO PASSA A DURAR (0115). O `Resumo de Custo` sempre soube quanto o lote
  // custou; o número morria na saída da execução do n8n, e responder "quanto
  // gastamos neste mandato" exigia abrir o n8n e ler um JSON. Aqui ele vira
  // linha de tabela, e o painel do portal passa a somar.
  //
  // `$execution.id` NÃO É DETALHE — É O QUE IMPEDE O CUSTO DE DOBRAR. Este nó
  // roda DUAS VEZES por lote (uma por ramo do `Precisa Fallback?`) e, desde a
  // correção de 14/08, as duas passadas trazem o total INTEIRO. Sem uma chave
  // por execução, seriam duas linhas e todo custo sairia 2×. A `0115` tem
  // `unique (caso_id, execucao_ref)` e faz `on conflict do update`: a segunda
  // passada reescreve a primeira com o mesmo valor.
  //
  // O resumo vai INTEIRO, como jsonb — a função escolhe o que conhece. Assim um
  // campo novo no relatório não pede migration de assinatura, e não existe
  // ordem de argumentos para alguém trocar sem querer.
  node('Gravar Uso do Lote', 'n8n-nodes-base.postgres', 2.5, {
    operation: 'executeQuery',
    query: 'select fn_registrar_uso_lote($1::uuid,$2::text,$3::jsonb) as resultado',
    options: {
      queryReplacement:
        "={{ [$('Upsert Caso (Postgres)').first().json.caso_id, String($execution.id), JSON.stringify($json)] }}",
    },
  }, { credentials: PG_CRED, ...PG_RETRY }),

  // A CONFERÊNCIA DE FORA (0112), o último nó do canvas de propósito: ela pergunta
  // se TODO documento registrado passou pela extração. As três camadas de
  // cobertura medem o que voltou de uma chamada FEITA; nenhuma delas vê a chamada
  // que não aconteceu — e foi assim que o V45 entregou 16 de 35 documentos com o
  // checklist verde. Roda uma vez por lote, não gasta IA, e a saída (`lote_integro`)
  // é o número que decide se a rodada vale.
  node('Conferir Lote', 'n8n-nodes-base.postgres', 2.5, {
    operation: 'executeQuery', query: 'select fn_conferir_lote($1::uuid) as resultado',
    options: { queryReplacement: "={{ $('Upsert Caso (Postgres)').first().json.caso_id }}" },
  }, { credentials: PG_CRED, ...PG_RETRY }),
];

const connections = {
  'Intake (Form)': { main: [[{ node: 'Upsert Caso (Postgres)', type: 'main', index: 0 }]] },
  'Upsert Caso (Postgres)': { main: [[{ node: 'Listar Arquivos', type: 'main', index: 0 }]] },
  'Listar Arquivos': { main: [[{ node: 'Classificar Nome', type: 'main', index: 0 }]] },
  'Classificar Nome': { main: [[{ node: 'Preparar Conteudo', type: 'main', index: 0 }]] },
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
  // O ORÇAMENTO ENTRA AQUI, e não antes do preparo do conteúdo (onde ficava até
  // a rodada de 18/08). Este é o primeiro ponto em que o lote inteiro está
  // visível de uma vez COM o documento já medido — linhas com número e número de
  // blocos —, e ainda é o último ponto antes de qualquer gasto: a primeira
  // chamada à OpenAI é o `IA Classificar`, logo depois do `Precisa
  // Fallback?`, e nenhum documento foi registrado no banco até o `Registrar
  // Documento`, muito mais adiante.
  'Medir Documento': { main: [[{ node: 'Orcamento do Lote', type: 'main', index: 0 }]] },
  'Orcamento do Lote': { main: [[{ node: 'Lote cabe?', type: 'main', index: 0 }]] },
  'Lote cabe?': { main: [
    [{ node: 'Precisa Fallback?', type: 'main', index: 0 }],   // true — segue
    [{ node: 'Registrar Recusa', type: 'main', index: 0 }],    // false — grava e aborta
  ] },
  // Os dois ramos entram em INPUTS DIFERENTES do Merge (0 e 1) — nunca mais duas
  // conexões cruas no mesmo input, que é o que comeu 19 documentos no V45.
  'Precisa Fallback?': { main: [
    [{ node: 'Montar Req Classif', type: 'main', index: 0 }],  // true  → classifica por conteúdo
    [{ node: 'Juntar Ramos', type: 'main', index: 1 }],        // false → direto para o Merge
  ] },
  'Montar Req Classif': { main: [[{ node: 'IA Classificar', type: 'main', index: 0 }]] },
  'IA Classificar': { main: [[{ node: 'Parse Classif', type: 'main', index: 0 }]] },
  'Parse Classif': { main: [[{ node: 'Juntar Ramos', type: 'main', index: 0 }]] },
  'Juntar Ramos': { main: [[{ node: 'Registrar Documento', type: 'main', index: 0 }]] },
  'Registrar Documento': { main: [[
    { node: 'Recomputar Completude', type: 'main', index: 0 },
    { node: 'Recompor Contexto', type: 'main', index: 0 },
  ]] },
  'Recompor Contexto': { main: [[{ node: 'Extracao ja feita?', type: 'main', index: 0 }]] },
  'Extracao ja feita?': { main: [
    [{ node: 'Juntar Extraidos', type: 'main', index: 1 }],     // true  → já extraído: pula a OpenAI
    [{ node: 'Montar Req Extracao', type: 'main', index: 0 }],  // false → extrai
  ] },
  'Montar Req Extracao': { main: [[{ node: 'Fatiar Extracao', type: 'main', index: 0 }]] },
  'Fatiar Extracao': { main: [[{ node: 'IA Extrair', type: 'main', index: 0 }]] },
  'IA Extrair': { main: [[{ node: 'Parse Extracao', type: 'main', index: 0 }]] },
  'Parse Extracao': { main: [[{ node: 'Juntar Blocos', type: 'main', index: 0 }]] },
  'Juntar Blocos': { main: [[{ node: 'Gravar Campos (Sombra)', type: 'main', index: 0 }]] },
  'Gravar Campos (Sombra)': { main: [[{ node: 'Registrar Diagnostico', type: 'main', index: 0 }]] },
  'Registrar Diagnostico': { main: [[{ node: 'Juntar Extraidos', type: 'main', index: 0 }]] },
  'Juntar Extraidos': { main: [[{ node: 'Reconciliar (Classe A)', type: 'main', index: 0 }]] },
  'Reconciliar (Classe A)': { main: [[{ node: 'Resumo de Custo', type: 'main', index: 0 }]] },
  'Resumo de Custo': { main: [[{ node: 'Gravar Uso do Lote', type: 'main', index: 0 }]] },
  'Gravar Uso do Lote': { main: [[{ node: 'Conferir Lote', type: 'main', index: 0 }]] },
};

// O canvas é desenhado a partir do grafo, nunca à mão (ver n8n/layout.mjs).
posicionar(nodes, connections);

const workflow = {
  name: 'Oria — E1 Ingestão + Diagnóstico + E2 Extração-Sombra + E3 Reconciliação Classe A (Fatia 1)',
  nodes, connections, settings: { executionOrder: 'v1' },
  meta: { note: 'Gerado por n8n/build-workflow.mjs. Nós Code espelham n8n/lib/ (testado). Diagnóstico de conteúdo roda SEMPRE (entidade/tipo/período/legibilidade); E2 em N0/sombra; E3 Classe A em N1 (gera pendência, nunca fato).' },
};

writeFileSync(join(__dirname, 'workflow.e1-ingestao.json'), JSON.stringify(workflow, null, 2) + '\n');
console.log('Escrito workflow —', nodes.length, 'nós,', Object.keys(connections).length, 'conexões');
