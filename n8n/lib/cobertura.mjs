// As três camadas contra o truncamento e a extração pela metade.
//
// O QUE ACONTECEU, com os números que motivaram este arquivo (rodada do
// `book-canastra`, 13/08/2026, 35 documentos): das 2.893 células de valor que
// os PDFs contêm, chegaram ao banco **1.139 — 39%**. Duas famílias distintas:
//
//   • TRUNCAMENTO (5 documentos, zero linhas). O gpt-4o tem teto de 16.384
//     tokens de SAÍDA. `01_Balanco_Patrimonial_..._2025x2024x2023` tem 326
//     células; no formato plano da época isso são ~20.900 tokens. Não cabia por
//     construção — e nenhum prompt conserta um teto físico. Ao menos falhou
//     ALTO: `finish_reason=length` virou `extracao_falhou` com a causa escrita.
//
//   • SUB-EXTRAÇÃO SILENCIOSA (o resto). `17_Livro_Razao_Fornecedores` devolveu
//     **99 de 461** linhas, sem estourar teto nenhum e sem abrir uma única
//     pendência. O sistema registrou sucesso. Esse é o modo de falha que este
//     projeto passa o tempo corrigindo: ausência com cara de normalidade.
//
// A resposta tem três camadas, e o desenho importa mais que cada uma:
//
//   1. SABER ANTES DE CHAMAR — o texto do PDF é extraído na própria instância
//      (nó `Extrair Texto`), o que dá de graça e sem IA a contagem de linhas com
//      número. É o insumo das outras duas; sem ela, elas não existem.
//   2. FATIAR POR TAMANHO — se a saída projetada passa do teto com folga, o
//      documento vai em blocos, um por chamada. Não é "tentar de novo quando
//      falhar": é nunca fazer o pedido que não cabe.
//   3. GUARDA DE COBERTURA — comparar o que voltou com o que o documento tem.
//      Ela não impede o modelo de pular uma linha; impede que isso seja
//      SILENCIOSO, que é a única promessa honesta de "nunca mais".
//
// O QUE ESTE ARQUIVO DELIBERADAMENTE NÃO FAZ: mandar o texto extraído para a
// OpenAI no lugar do PDF. A tentação é grande (o texto é mais barato que a
// imagem), e seria uma troca ruim AGORA: o texto de uma tabela perde o
// alinhamento das colunas, e foi exatamente a leitura de coluna que acabou de
// funcionar bem — o balanço combinado saiu com as 8 colunas de empresa certas.
// O texto aqui serve para MEDIR, não para LER.
//
// Todas as funções são AUTO-CONTIDAS: os nós Code do n8n não importam arquivo, e
// elas são embutidas lá por `toString()`. Nenhuma pode referenciar constante do
// módulo — se referenciar, o nó quebra com ReferenceError na primeira execução
// real e nenhum teste daqui pega isso.

// Teto de saída do modelo (espelha MAX_OUTPUT_TOKENS de lib/extract.mjs).
export const TETO_SAIDA_TOKENS = 16384;

// Tokens de saída por célula de valor, no formato agrupado. Medido em 13/08:
// ~39 por linha extraída (era ~64 no formato plano). Arredondado para cima.
export const TOKENS_POR_CELULA = 42;

// Fração do teto que um bloco pode ocupar. 0,6 e não 0,9 porque a contagem de
// linhas é uma ESTIMATIVA do que a saída vai custar: documento com rótulos
// longos gasta mais por linha, e o custo de errar para baixo é o truncamento
// que este arquivo existe para eliminar. Uma chamada a mais custa ~US$ 0,03 e
// 33 segundos; um documento truncado custa o dado.
export const FRACAO_DO_TETO = 0.6;

// Quantas células de valor cabem, com folga, numa chamada.
// 16.384 × 0,6 ÷ 42 ≈ 234.
export const MAX_CELULAS_POR_BLOCO = Math.floor((TETO_SAIDA_TOKENS * FRACAO_DO_TETO) / TOKENS_POR_CELULA);

// Limiar de cobertura abaixo do qual a extração é considerada incompleta.
//
// CALIBRADO NA RODADA REAL, e a calibração é apertada de propósito. Nos
// documentos que vieram sadios a cobertura ficou em 68%-90% (`02_DRE` 104 de
// 115; `22_Aging` 91 de 114; `06_Balanco` 74 de 109) — a diferença é linha com
// número que não é dado financeiro: CNPJ, data, número de página, rodapé. Nos
// documentos que vieram pela metade ficou em 21%-48% (`17_Livro_Razao` 99 de
// 461; `15_Balancete` 77 de 162).
//
// 0,60 separa os dois grupos, e vai FALHAR PARA O LADO DE AVISAR DEMAIS: um
// documento sadio com muito cabeçalho numérico pode cair abaixo dele. É a troca
// deliberada — uma pendência falsa custa uma olhada, um buraco não visto custa
// o mandato. Quem quiser apertar depois tem os números acima como base.
export const LIMIAR_COBERTURA = 0.6;

// Abaixo de quantas células a guarda se cala. Num documento de 6 linhas a razão
// é ruído: uma linha a menos derruba a cobertura em 17%.
export const MINIMO_PARA_AVALIAR = 20;

/**
 * As linhas do texto que contêm ALGUM dígito — a contagem determinística do que
 * o documento tem para extrair, feita sem IA e sem custo.
 *
 * Ela superestima de propósito (conta CNPJ, data, número de página), e é por
 * isso que o limiar de cobertura é 0,6 e não 0,95: a régua é grosseira, e uma
 * régua grosseira honesta vale mais que uma precisa inventada.
 */
export function linhasComNumero(texto) {
  if (typeof texto !== 'string' || texto.length === 0) return [];
  const out = [];
  for (const bruta of texto.split('\n')) {
    const linha = bruta.trim();
    if (linha.length === 0) continue;
    if (!/\d/.test(linha)) continue;
    out.push(linha);
  }
  return out;
}

/**
 * O plano de fatiamento de UM documento.
 *
 * Devolve sempre pelo menos um bloco — documento pequeno é "um bloco só", não
 * um caso especial, e tratar os dois pelo mesmo caminho é o que impede o
 * fatiamento de ser um modo raro que ninguém exercita.
 *
 * AS ÂNCORAS SÃO O CORAÇÃO DISTO. O modelo continua vendo o PDF INTEIRO (é onde
 * está o alinhamento das colunas), então dizer "extraia o bloco 2 de 3" seria
 * pedir para ele adivinhar onde o bloco começa. Em vez disso cada bloco carrega
 * o TEXTO EXATO da primeira e da última linha da faixa, lidos do PDF pelo
 * extrator: "comece em «Duplicatas a receber ... 22.310» e termine em «(-) PCLD
 * ... (1.900)»". Vira uma instrução verificável em vez de uma proporção.
 */
export function planejarFatias(linhas, maxPorBloco) {
  const lista = Array.isArray(linhas) ? linhas : [];
  const max = Number.isFinite(Number(maxPorBloco)) && Number(maxPorBloco) > 0
    ? Math.floor(Number(maxPorBloco))
    : 234;
  const total = lista.length;
  if (total <= max) {
    return [{ bloco: 1, blocos: 1, de: 0, ate: Math.max(0, total - 1), ancoraInicio: null, ancoraFim: null, celulas: total }];
  }
  // Blocos de tamanho PAREJO em vez de "enche o primeiro e sobra um toco": um
  // bloco final de 3 linhas dá ao modelo uma faixa curta demais para ancorar.
  const blocos = Math.ceil(total / max);
  const porBloco = Math.ceil(total / blocos);
  const out = [];
  for (let i = 0; i < blocos; i += 1) {
    const de = i * porBloco;
    const ate = Math.min(total - 1, de + porBloco - 1);
    if (de > ate) break;
    out.push({
      bloco: i + 1,
      blocos,
      de,
      ate,
      ancoraInicio: lista[de],
      ancoraFim: lista[ate],
      celulas: ate - de + 1,
    });
  }
  return out;
}

/**
 * A instrução que vai na mensagem de USER do bloco (nunca no prompt de sistema:
 * o prefixo tem de continuar idêntico em toda chamada para o cache valer).
 */
export function instrucaoDaFatia(fatia) {
  if (!fatia || !(fatia.blocos > 1)) return '';
  return ' ATENCAO -- EXTRACAO EM BLOCOS: este documento e' + ' grande demais para uma resposta so, '
    + 'entao voce esta extraindo o BLOCO ' + fatia.bloco + ' DE ' + fatia.blocos + '. '
    + 'Extraia SOMENTE as linhas de valor a partir da linha que aparece no documento como "'
    + String(fatia.ancoraInicio || '').slice(0, 160) + '" ate a linha "'
    + String(fatia.ancoraFim || '').slice(0, 160) + '", ambas INCLUSIVE, na ordem de leitura. '
    + 'Nao extraia nada antes da primeira nem depois da ultima: os outros blocos cobrem o resto, '
    + 'e linha repetida entre blocos vira dado duplicado. O diagnostico do documento (entidade, '
    + 'tipo, periodo, moeda, escala) deve descrever o DOCUMENTO INTEIRO, nao so este bloco.';
}

/**
 * Junta os blocos de um documento em um conjunto único de campos.
 *
 * A EMENDA É O PONTO DELICADO. As âncoras dizem ao modelo onde começar e onde
 * parar, mas o limite entre dois blocos é o lugar onde ele pode repetir uma
 * linha — e linha repetida vira valor contado duas vezes no book, que é
 * exatamente a classe de erro que o invariante "uma conta, um lugar" persegue.
 *
 * A limpeza é deliberadamente ESTREITA: só remove, do começo do bloco seguinte,
 * linhas idênticas (mesma chave, mesma coluna, mesmo valor) às do FIM do bloco
 * anterior. Não é dedupe global — num livro razão a mesma conta com o mesmo
 * valor aparece legitimamente várias vezes ao longo do documento, e apagá-las
 * seria destruir dado real para consertar um problema de costura.
 */
export function juntarBlocos(blocos) {
  const lista = (Array.isArray(blocos) ? blocos : [])
    .filter((b) => b && typeof b === 'object')
    .slice()
    .sort((a, b) => (Number(a.bloco) || 0) - (Number(b.bloco) || 0));

  const campos = [];
  const motivos = [];
  let emendasLimpas = 0;
  const assinatura = (c) => [c.chave, c.entidade_coluna, c.periodo_coluna, c.valor_texto, c.valor_num].join('');

  for (const b of lista) {
    const doBloco = Array.isArray(b.campos) ? b.campos.slice() : [];
    if (campos.length > 0 && doBloco.length > 0) {
      // Janela de 3: a repetição de emenda é de uma ou duas linhas na prática, e
      // uma janela grande começaria a comer dado legítimo.
      const cauda = campos.slice(-3).map(assinatura);
      while (doBloco.length > 0 && cauda.includes(assinatura(doBloco[0]))) {
        doBloco.shift();
        emendasLimpas += 1;
      }
    }
    for (const c of doBloco) campos.push(c);
    if (b.falha_motivo) motivos.push(`bloco ${b.bloco}: ${b.falha_motivo}`);
  }

  // `ordem` é renumerada no conjunto: ela significa "posição na leitura do
  // documento" e é o que permite ao export reconhecer subtotal impresso acima
  // dos componentes. Cada bloco numera a partir de zero, então manter a
  // numeração do bloco faria o documento ter três linhas de `ordem` 0.
  const renumerados = campos.map((c, i) => ({ ...c, ordem: i }));
  return { campos: renumerados, motivos, emendasLimpas, blocos: lista.length };
}

/**
 * A guarda de cobertura. Devolve `null` quando não há o que dizer — e "não há o
 * que dizer" é o caso comum, então ela não polui a fila de revisão.
 */
export function avaliarCobertura({ extraidas, esperadas, limiar = LIMIAR_COBERTURA, minimo = MINIMO_PARA_AVALIAR }) {
  const e = Number(extraidas);
  const t = Number(esperadas);
  if (!Number.isFinite(e) || !Number.isFinite(t) || t < minimo) return null;
  const razao = t > 0 ? e / t : 1;
  if (razao >= limiar) return null;
  return {
    razao: Number(razao.toFixed(3)),
    extraidas: e,
    esperadas: t,
    motivo:
      `Extração INCOMPLETA: ${e} linha(s) gravada(s) para um documento com ${t} linha(s) com número `
      + `(${(razao * 100).toFixed(0)}% de cobertura, abaixo do mínimo de ${(limiar * 100).toFixed(0)}%). `
      + `A contagem do documento é feita sobre o texto do PDF, sem IA, e conta linhas que podem não ser `
      + `dado financeiro (CNPJ, data, número de página) — então ela superestima. Ainda assim, uma diferença `
      + `deste tamanho quase sempre é dado que o modelo deixou de ler: conferir o documento na fila de `
      + `revisão antes de usar o book. Se o arquivo tiver mesmo poucas linhas financeiras, a pendência é `
      + `falso positivo e pode ser resolvida sem ação.`,
  };
}
