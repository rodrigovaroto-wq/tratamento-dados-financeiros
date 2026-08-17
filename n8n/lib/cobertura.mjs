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
// 0,60 era o limiar da régua ANTIGA (linhas com dígito × pares conta-coluna),
// e ele foi calibrado sobre uma razão que não fazia sentido dimensional. Com a
// régua na unidade certa — LINHAS DE CONTA contra CONTAS DISTINTAS — o mesmo
// `02_DRE` sai de "198%" para **77%**, que é a cobertura real dele.
//
// O limiar sobe para **0,85** porque o alvo declarado pelo dono é cobertura
// TOTAL. Isso vai abrir pendência em documentos que antes passavam — é o
// objetivo, não efeito colateral: o `02_DRE` a 77% está mesmo deixando ~9 contas
// para trás, e ninguém sabia.
//
// CALIBRADO CONTRA A VERDADE EM 17/08, e o número FICA em 0,85. Deixou de ter um
// ponto de medição e passou a ter 38: `node n8n/medir-regua-cobertura.mjs`
// confronta a régua com a contagem que o gerador do book declara. O resultado
// (com a régua v2, abaixo):
//
//   • erro mediano da régua: +3% — ela conta uma linha a mais por tabela, quase
//     sempre o cabeçalho de faixas/colunas, que tem rótulo E número;
//   • pior caso do book com extração PERFEITA: 96% de cobertura aparente.
//
// Ou seja, sobram 11 pontos entre o pior documento honesto (96%) e o limiar
// (85%). Subir para 0,90 caberia na medição e ainda assim NÃO se sobe: a folga
// existe para o documento real, que é mais sujo que o sintético — rodapé colado
// no número, coluna encavalada, rótulo quebrado em duas linhas. Quando a próxima
// rodada trouxer 35 documentos reais medidos, aí o número tem base para apertar.
//
// O QUE A MESMA MEDIÇÃO ACHOU E NÃO SE CONSERTA COM LIMIAR: onde o rótulo se
// repete (livro razão: 99 linhas, 66 históricos distintos), extração PERFEITA se
// reporta em 66% e a pendência é falsa — as duas pontas deixam de estar na mesma
// unidade. A correção é a extração informar quantas LINHAS devolveu, não só
// quantas contas distintas, e está aberta no `ESTADO.md`.
export const LIMIAR_COBERTURA = 0.85;

// Abaixo de quantas células a guarda se cala. Num documento de 6 linhas a razão
// é ruído: uma linha a menos derruba a cobertura em 17%.
export const MINIMO_PARA_AVALIAR = 20;

/**
 * As linhas do texto que são LINHA DE CONTA — rótulo seguido de valor.
 *
 * A RÉGUA ESTAVA NA UNIDADE ERRADA, e isso importa mais que a precisão dela.
 * A primeira versão contava toda linha com algum dígito e comparava com os
 * PARES (conta × coluna) que a extração grava. Medido no `02_DRE` do
 * book-canastra: o texto tem 46 linhas com dígito, a extração gravou 91 pares —
 * a razão dá 198%, e a guarda de cobertura nunca dispararia. Pior: ela ficava
 * cega justamente nos documentos COMPARATIVOS, que são os que mais têm a perder.
 *
 * Agora a régua conta LINHAS DE CONTA e é comparada com CONTAS DISTINTAS
 * extraídas — as duas na mesma unidade. No mesmo DRE: 39 linhas de conta contra
 * ~30 contas extraídas = 77%, que é a cobertura de verdade.
 *
 * O que sai da contagem, e é 15% do total naquele documento: cabeçalho de ano
 * ("2025 2024 2023"), CNPJ, data por extenso, número de página, CRC e CPF do
 * bloco de assinatura. Nada disso é dado financeiro, e contá-los inflava o
 * denominador — a régua "grosseira mas honesta" era grosseira de mais.
 *
 * ┌─ v2 (17/08), medida contra as 38 verdades do `book-canastra` ──────────────
 * │ `node n8n/medir-regua-cobertura.mjs` confrontou esta função com a contagem
 * │ que o GERADOR do book declara (ele sabe quantas linhas escreveu, não é outra
 * │ leitura do PDF). A régua acertava os documentos de demonstração — balanço,
 * │ DRE, DFC, faturamento: erro de +2% a +4% — e DESABAVA justamente nos
 * │ analíticos, que são os que perdem dado:
 * │
 * │   livro razão   99 linhas → a régua via  3   (−97%)
 * │   balancete     78 linhas → a régua via  3   (−96%)
 * │   aging         14 linhas → a régua via  2   (−86%)
 * │   imobilizado    9 linhas → a régua via  2   (−78%)
 * │
 * │ E como `MINIMO_PARA_AVALIAR` cala a guarda abaixo de 20 linhas, a cegueira
 * │ virava SILÊNCIO: nesses documentos a guarda nunca chegava a opinar. O livro
 * │ razão da rodada de 14/08 — o caso que motivou as três camadas — era invisível
 * │ para a guarda que existe para vigiá-lo.
 * │
 * │ A CAUSA: "termina em valor" pressupõe que rótulo e valor caem na MESMA linha
 * │ do texto extraído. Num documento de sistema contábil isso é falso de três
 * │ jeitos, e os três foram conferidos no artefato (e num segundo leitor de PDF,
 * │ o `pdf-parse` que o n8n usa, para não calibrar contra um extrator só):
 * │   • a linha termina na NATUREZA, não no valor — `1.1.01.002  181  D`;
 * │   • o rótulo é CÓDIGO de conta, sem letra nenhuma — o mesmo `1.1.01.002`;
 * │   • o histórico é parágrafo que quebra, e o leitor o deixa numa linha só
 * │     dele: os valores do lançamento ficam órfãos de rótulo.
 * │
 * │ A v2 troca "termina em valor" por "TEM valor E tem identidade", e aceita como
 * │ identidade três formas: rótulo em letras, código de conta, ou — quando o
 * │ leitor separou o rótulo — a própria linha de tabela numérica (dois valores ou
 * │ mais). Erro absoluto médio: 29% → 9%, sem piorar um único documento.
 * └───────────────────────────────────────────────────────────────────────────
 */
export function linhasDeConta(texto) {
  if (typeof texto !== 'string' || texto.length === 0) return [];
  // Um valor: número solto, com separador de milhar, decimal, percentual, ou
  // negativo entre parênteses — as quatro formas que o book usa.
  const valores = /\(?-?\d[\d.]*(?:,\d+)?\)?%?/g;
  // Código de conta contábil ("1.1.01.002"): identidade sem uma letra sequer.
  const codigoDeConta = /\b\d+(?:\.\d+){2,}\b/;
  // Ruído conhecido de documento contábil brasileiro. Cada padrão saiu de uma
  // linha real do book, e o comentário evita que alguém "melhore" tirando um.
  const ruido = [
    /^p[áa]gina\b/i,                       // "Página 1"
    /^cnpj\b|\bcnpj\s*[\d.]/i,             // "CNPJ 44.555.667/0001-59"
    /^cpf\b|\bcpf\s*[\d.]/i,               // assinatura
    /\bcrc\s*\d|\bcrc\s*[a-z]{2}/i,        // "CRC 1MG-198.442/O-7"
    /^\(?valores expressos/i,              // "(Valores expressos em milhares…)"
    /^exerc[íi]cios? encerrados?/i,        // "Exercícios encerrados em 31 de dezembro…"
    /^(nota|obs)\b|^_{3,}/i,               // nota de rodapé, linha de assinatura
    // Cabeçalho de coluna: só anos/datas, sem rótulo de conta antes.
    /^[\s|]*((19|20)\d{2}|\d{2}\/\d{2}\/\d{4})([\s|]+((19|20)\d{2}|\d{2}\/\d{2}\/\d{4}))*[\s|]*$/,
  ];
  const out = [];
  for (const bruta of texto.split('\n')) {
    const linha = bruta.trim();
    if (linha.length === 0) continue;
    if (ruido.some((r) => r.test(linha))) continue;
    const quantos = (linha.match(valores) ?? []).filter((t) => /\d/.test(t)).length;
    // Sem valor não é conta: é título, é seção, é prosa. O modelo também não
    // gera linha para ela.
    if (quantos === 0) continue;
    // Identidade da conta, em qualquer uma das três formas. A terceira —
    // "linha de tabela numérica" — é a que recupera o razão e o aging, onde o
    // leitor de PDF põe o rótulo numa linha e os valores na seguinte: contar a
    // linha dos valores é contar a conta UMA vez, que é a unidade certa.
    const temRotulo = /[a-zà-ú]{3}/i.test(linha);
    if (!temRotulo && !codigoDeConta.test(linha) && quantos < 2) continue;
    out.push(linha);
  }
  return out;
}

/**
 * Toda linha com algum dígito. Continua existindo porque é a régua do
 * FATIAMENTO — ali o que importa é o tamanho da resposta, e cada célula pesa,
 * inclusive as do cabeçalho. Para COBERTURA use `linhasDeConta`.
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
  // `extraidas` = CONTAS DISTINTAS gravadas; `esperadas` = LINHAS DE CONTA do
  // texto. As duas na mesma unidade — foi trocar isso que fez a guarda ficar
  // cega nos documentos comparativos, onde 3 colunas por conta faziam a razão
  // passar de 100% e nada nunca disparar.
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
      `Extração INCOMPLETA: ${e} conta(s) distinta(s) gravada(s) para um documento com ${t} linha(s) `
      + `de conta no texto (${(razao * 100).toFixed(0)}% de cobertura, abaixo do mínimo de `
      + `${(limiar * 100).toFixed(0)}%). A contagem do documento é feita sobre o texto do PDF, sem IA: `
      + `linha que termina em valor e tem rótulo, descontados cabeçalho de ano, CNPJ, data, número de `
      + `página e bloco de assinatura. As duas medidas estão na MESMA unidade (contas, não valores), `
      + `então a diferença é dado que o modelo deixou de ler — conferir o documento na fila de revisão `
      + `antes de usar o book. Documento com rótulo repetido (livro razão com o mesmo histórico em `
      + `lançamentos diferentes) conta menos contas distintas do que tem linhas: aí a pendência é falso `
      + `positivo e pode ser resolvida sem ação.`,
  };
}
