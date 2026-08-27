// COMO CADA PREMISSA SE PROJETA — e por que não é a mesma resposta para todas.
//
// O QUE ISTO RESOLVE. A tela de Modelagem pede, para cada premissa ativa, um
// valor por ano projetado: cinco caixas por premissa, onze premissas, cinquenta
// e cinco números digitados à mão antes de o modelo rodar uma vez. Na prática
// quem preenche repete o mesmo número nas cinco caixas — e o roteiro de teste do
// repositório faz exatamente isso, com a nota "julgamento" ao lado.
//
// Mas "repetir o mesmo número" é a resposta certa para UMA família de premissas e
// errada para as outras duas, e é essa distinção que este arquivo carrega:
//
//   1. AS MACRO (IPCA, SELIC, câmbio, IGP-M, PIB) já têm quem responda por elas,
//      e não somos nós: o Boletim Focus publica a mediana do mercado por ano, e
//      ela está no banco desde a `0025`. Repetir o IPCA do ano passado por cinco
//      anos é ignorar uma previsão que o próprio sistema já coletou.
//
//   2. AS RAZÕES DO REALIZADO (custo sobre receita, SG&A sobre receita, dias de
//      giro, alíquota efetiva, parcela onerosa, taxa da dívida) são estruturais:
//      elas descrevem COMO a empresa opera, e uma empresa não muda de estrutura
//      de custo por decreto. Projetá-las constantes é a hipótese honesta — e o
//      número certo é a MÉDIA dos exercícios, não o último. O último ano de uma
//      empresa em reestruturação é o pior ano dela, e projetar cinco anos a
//      partir dele é projetar a crise como se fosse o regime.
//
//   3. AS DE CRESCIMENTO E PREÇO (crescimento nominal, custo de matéria-prima,
//      frete, energia) não saem do balanço nem do Focus: são a tese do caso. O
//      que dá para oferecer sem inventar é a INDEXAÇÃO — crescer pelo índice
//      macro que o mandato escolheu, que é a hipótese de "nada muda em termos
//      reais". Continua sendo uma hipótese, e ela vai declarada.
//
// A REGRA SAI DO CATÁLOGO, NÃO DE UMA LISTA AQUI. `premissa_catalogo` já declara
// `natureza` e `formula` de cada premissa; é por eles que a decisão é tomada.
// Premissa nova no catálogo já nasce sabendo se projeta e como — que é a mesma
// doutrina da `0038` ("premissa nova = linha nova, sem código novo").
//
// E O QUE NÃO PROJETA DIZ POR QUÊ. Uma premissa de valor absoluto por ano
// (CAPEX_ANO, DIVIDA_MOV, VGV) não tem de onde sair sozinha: ela é decisão do
// caso. Devolver zero seria pior que devolver nada — zero é uma afirmação sobre
// o negócio, e ninguém a fez. É a mesma regra que governa `premissas-do-realizado`.

/** O que o catálogo diz sobre a premissa — só os campos que decidem a projeção. */
export interface PremissaDoCatalogo {
  codigo: string;
  natureza: string;
  formula: string;
  unidade: string | null;
}

export interface ProjecaoDaPremissa {
  /** ano → valor, na escala que a premissa usa. Vazio quando não dá para projetar. */
  valores: Record<string, number>;
  /** `focus` | `media_historica` | `indexado` | null — vai para `caso_premissa.origem`. */
  origem: "focus" | "media_historica" | "indexado" | null;
  /** uma linha dizendo como o número foi feito, para quem for discordar dele */
  conta: string;
  /** preenchido quando NÃO deu para projetar, e aí `valores` é vazio */
  porQueNao: string | null;
}

export interface EntradaDaProjecao {
  /** os anos projetados do mandato, já calculados pela tela */
  anos: number[];
  /** a média dos exercícios, quando a premissa é uma razão do realizado */
  mediaHistorica?: { valor: number | null; exercicios: number[]; conta: string } | null;
  /** o que o Focus afirma por ano, para as premissas macro (`fn_premissa_valores_sugeridos`) */
  focus?: Record<string, number> | null;
  /** o índice macro que o mandato escolheu (`caso_modelagem.indice_macro`), e a série dele */
  indiceDoCaso?: { codigo: string; valores: Record<string, number> } | null;
}

/**
 * As fórmulas cuja premissa é uma RAZÃO estrutural — projetadas constantes, na
 * média dos exercícios.
 *
 * `pct_de_linha` e `dias_de_giro` são as duas que incidem sobre uma linha do
 * modelo e descrevem proporção, não nível. Uma terceira família (`preco_x_volume`,
 * `valor_por_ano`) descreve NÍVEL, e nível não se projeta por média histórica sem
 * dizer o que acontece com o preço — por isso ela cai no "não projeta sozinha".
 */
const RAZOES_ESTRUTURAIS = new Set(["pct_de_linha", "dias_de_giro"]);

/** As fórmulas que descrevem VARIAÇÃO ao longo do tempo — indexáveis ao macro. */
const CRESCIMENTOS = new Set(["crescimento_composto"]);

export function projetarPremissa(
  premissa: PremissaDoCatalogo,
  entrada: EntradaDaProjecao,
): ProjecaoDaPremissa {
  const anos = entrada.anos ?? [];
  const vazio = (porQueNao: string, conta = ""): ProjecaoDaPremissa =>
    ({ valores: {}, origem: null, conta, porQueNao });

  if (anos.length === 0) {
    return vazio("o mandato ainda não tem anos projetados — falta o passo 1 da modelagem");
  }

  // 1. MACRO — quem responde é o Focus, e ano sem expectativa publicada fica
  //    FORA em vez de receber o valor do vizinho. Ausência é ausência: um ano
  //    interpolado seria uma previsão que ninguém fez.
  if (premissa.natureza === "macro") {
    const doFocus = entrada.focus ?? {};
    const valores: Record<string, number> = {};
    for (const ano of anos) {
      const v = doFocus[String(ano)];
      if (typeof v === "number" && Number.isFinite(v)) valores[String(ano)] = v;
    }
    if (Object.keys(valores).length === 0) {
      return vazio(
        `o Boletim Focus não publica expectativa de ${premissa.codigo} para nenhum dos anos `
        + `projetados (${anos[0]}–${anos[anos.length - 1]})`,
        "mediana do Focus, coleta mais recente de cada ano",
      );
    }
    const faltando = anos.filter((a) => !(String(a) in valores));
    return {
      valores,
      origem: "focus",
      conta: `mediana do Focus, coleta mais recente de cada ano`
        + (faltando.length > 0 ? ` — sem expectativa para ${faltando.join(", ")}` : ""),
      porQueNao: null,
    };
  }

  // 2. RAZÃO ESTRUTURAL — constante na média dos exercícios.
  if (RAZOES_ESTRUTURAIS.has(premissa.formula)) {
    const m = entrada.mediaHistorica;
    if (!m || m.valor === null || !Number.isFinite(m.valor)) {
      return vazio(
        m?.conta
          ? `a média histórica não pôde ser calculada: ${m.conta}`
          : "esta premissa se projeta pela média dos exercícios, e o caso não trouxe a conta que a calcula",
      );
    }
    const valores: Record<string, number> = {};
    for (const ano of anos) valores[String(ano)] = m.valor;
    const quantos = m.exercicios.length;
    return {
      valores,
      origem: "media_historica",
      // O TEXTO DIZ QUANTOS EXERCÍCIOS ENTRARAM, e isso não é enfeite: uma média
      // de um exercício só é o último ano com outro nome, e quem lê precisa
      // saber a diferença antes de aceitar o número.
      conta: quantos === 1
        ? `${m.conta} — UM exercício só (${m.exercicios[0]}), então é o valor dele, não uma média`
        : `${m.conta} — média de ${quantos} exercícios (${m.exercicios.join(", ")})`,
      porQueNao: null,
    };
  }

  // 3. CRESCIMENTO — indexado ao índice macro do mandato.
  if (CRESCIMENTOS.has(premissa.formula)) {
    const idx = entrada.indiceDoCaso;
    if (!idx || Object.keys(idx.valores ?? {}).length === 0) {
      return vazio(
        "esta premissa se projeta indexada ao índice macro do mandato, e ele não tem série "
        + "publicada para os anos projetados",
      );
    }
    const valores: Record<string, number> = {};
    for (const ano of anos) {
      const v = idx.valores[String(ano)];
      if (typeof v === "number" && Number.isFinite(v)) valores[String(ano)] = v;
    }
    if (Object.keys(valores).length === 0) {
      return vazio(
        `o índice ${idx.codigo} não cobre nenhum dos anos projetados `
        + `(${anos[0]}–${anos[anos.length - 1]})`,
      );
    }
    return {
      valores,
      origem: "indexado",
      // A HIPÓTESE VAI DECLARADA. Indexar ao IPCA é afirmar que nada muda em
      // termos reais — o que é uma tese sobre o caso, não um fato dele. Sem esta
      // frase, o número parece medido.
      conta: `indexado a ${idx.codigo} — supõe volume e preço relativo constantes `
        + `(crescimento apenas nominal). É hipótese, não medição`,
      porQueNao: null,
    };
  }

  // 4. O QUE NÃO PROJETA SOZINHA. Valor absoluto por ano e preço × volume são
  //    decisão do caso: capex, movimento de dívida, VGV, preço médio. Zero seria
  //    uma afirmação sobre o negócio que ninguém fez.
  return vazio(
    "esta premissa é um valor de decisão do caso (capex, movimento de dívida, preço, volume) — "
    + "ela não sai do balanço nem do Focus, e projetá-la por conta própria seria inventar a tese",
  );
}
