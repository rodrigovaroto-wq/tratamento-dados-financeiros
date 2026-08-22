import {
  blocoDaLinha, ehCliente, ehEstoque, ehFornecedor, ehDividaFinanceira,
  ehDespesaFinanceira, type LinhaModelo,
} from "./modelo-institucional";

// SUGERIR A PREMISSA A PARTIR DO QUE A EMPRESA JÁ FEZ.
//
// O QUE ISTO RESOLVE. A tela de Modelagem pede oito números que o próprio caso já
// responde: quanto o custo consome da receita, quanto o SG&A consome, em quantos
// dias a empresa recebe, estoca e paga, qual a alíquota efetiva, quanto do passivo
// cobra juro e a que taxa. Hoje todos entram em campo vazio, digitados de cabeça
// ou copiados de outro mandato — e campo vazio numa premissa é o começo de um
// modelo que não reproduz o balanço de onde saiu.
//
// A REGRA QUE GOVERNA ESTE ARQUIVO INTEIRO: ZERO NÃO É RESPOSTA. Sem a conta que
// serve de numerador, ou sem a base que serve de denominador, a sugestão não sai —
// sai o motivo. Zero dias de recebimento não é "não sei": é a afirmação de que a
// empresa vende à vista, e é uma afirmação sobre o negócio que ninguém fez. É a
// mesma doutrina do `f0/08` e a que o `Output` já aplica ao ciclo de caixa.
//
// A BASE DE CADA RAZÃO É A MESMA QUE O MODELO APLICA, e isso não é detalhe. O
// `modelo-institucional` projeta saldo de giro como `dias ÷ 360 × base`, com base
// = CUSTOS para fornecedor e RECEITA LÍQUIDA para o resto. Medir num denominador e
// aplicar noutro é o defeito que o próprio modelo denuncia no Modelo Base (lá o
// prazo do fornecedor é medido contra custo e aplicado sobre receita, inflando o
// passivo projetado em ~1,27×). Aqui a ponta que mede e a ponta que aplica usam a
// mesma base, e é por isso que os classificadores de cliente, estoque e fornecedor
// são importados de lá em vez de reescritos.
//
// SINAL. O documento publica despesa ora positiva, ora negativa, conforme a
// convenção de quem o emitiu. Toda razão daqui usa MAGNITUDE — o que se quer saber
// é o tamanho do custo contra a receita, e o sinal é convenção de partida dobrada,
// não informação econômica.
//
// SUBTOTAL NÃO ENTRA EM SOMA. Somar "Total do Ativo Circulante" junto das contas
// dele conta tudo duas vezes. Só `papel = 'conta'` soma; o subtotal impresso serve
// para conferir, e quem confere é a reconciliação.

/** O que a tela de Modelagem já carrega por linha, e é tudo de que isto precisa. */
export interface LinhaRealizada {
  secao_canonica: string | null;
  chave: string;
  rotulo_norm: string;
  papel: "conta" | "subtotal" | "derivado" | "serie_mensal";
  valor_ultimo: number;
  documentos: string[] | null;
}

export interface PremissaSugerida {
  codigo: string;
  nome: string;
  /** já na escala que o catálogo espera: fração para `pct_de_linha`, dias para `dias_de_giro` */
  valor: number | null;
  unidade: "%" | "dias";
  /** como o número foi feito, em uma linha, para quem for discordar dele */
  conta: string;
  numerador: { rotulo: string; valor: number } | null;
  denominador: { rotulo: string; valor: number } | null;
  /** preenchido quando NÃO deu para calcular — e aí `valor` é null */
  porQueNao: string | null;
}

type Bolsa = { rotulo: string; valor: number; n: number };

/** Soma as contas (nunca subtotais) que casam com o filtro, em magnitude. */
function somar(linhas: LinhaRealizada[], rotulo: string, filtro: (l: LinhaRealizada) => boolean): Bolsa {
  const escolhidas = linhas.filter((l) => l.papel === "conta" && filtro(l));
  return {
    rotulo,
    valor: escolhidas.reduce((s, l) => s + Math.abs(l.valor_ultimo), 0),
    n: escolhidas.length,
  };
}

/** `blocoDaLinha` pede um `LinhaModelo`; a tela tem menos campos, e só estes importam. */
const comoModelo = (l: LinhaRealizada): LinhaModelo => ({
  secao_canonica: l.secao_canonica,
  chave: l.chave,
  rotulo_norm: l.rotulo_norm,
  papel: l.papel,
  unidade: null,
  moeda: null,
  documentos: l.documentos,
  valores: {},
});

function razao(
  codigo: string, nome: string, unidade: "%" | "dias", conta: string,
  num: Bolsa, den: Bolsa, fator = 1,
  /**
   * Quando a base só faz sentido POSITIVA, o texto do porquê. Existe porque
   * `den.valor === 0` não é a única base impossível: base NEGATIVA produz uma
   * razão negativa, e uma razão negativa publicada como premissa é pior que a
   * ausência dela — ela entra no modelo e projeta o contrário do que aconteceu.
   */
  basePositivaPorque?: string,
): PremissaSugerida {
  const base: PremissaSugerida = {
    codigo, nome, unidade, conta, valor: null, porQueNao: null,
    numerador: num.n > 0 ? { rotulo: num.rotulo, valor: num.valor } : null,
    denominador: den.n > 0 ? { rotulo: den.rotulo, valor: den.valor } : null,
  };
  if (num.n === 0) {
    return { ...base, porQueNao: `o caso não tem nenhuma linha de ${num.rotulo}` };
  }
  if (den.n === 0 || den.valor === 0) {
    return { ...base, porQueNao: `o caso não tem ${den.rotulo} com valor, e é a base desta conta` };
  }
  if (basePositivaPorque !== undefined && den.valor < 0) {
    return { ...base, porQueNao: basePositivaPorque };
  }
  // NUMERADOR ZERO COM CONTA EXISTENTE é diferente de conta ausente, e passa: uma
  // empresa pode de fato não ter estoque no fechamento. O que não passa é inventar
  // a base.
  return { ...base, valor: Number(((num.valor / den.valor) * fator).toFixed(4)) };
}

/**
 * As oito premissas que o próprio realizado responde.
 *
 * Recebe as linhas do caso como a tela de Modelagem as tem (`fn_linhas_para_modelagem`,
 * uma por seção × rótulo, com o valor do ÚLTIMO exercício) e devolve as oito na
 * ordem em que a tela as mostra: primeiro as que quase todo caso responde.
 */
export function sugerirDoRealizado(linhas: LinhaRealizada[]): PremissaSugerida[] {
  const bloco = new Map<string, LinhaRealizada[]>();
  for (const l of linhas) {
    const b = blocoDaLinha(comoModelo(l));
    const lista = bloco.get(b) ?? [];
    lista.push(l);
    bloco.set(b, lista);
  }
  const de = (b: string) => bloco.get(b) ?? [];

  // A CASCATA DO REALIZADO. Receita líquida é bruta menos deduções, como no
  // modelo — e não a linha "Receita Líquida" impressa, que pode não existir no
  // documento e, quando existe, é subtotal (não soma).
  const receitaBruta = somar(de("receita"), "receita bruta", () => true);
  const deducoes = somar(de("deducao"), "deduções da receita", () => true);
  const receitaLiquida: Bolsa = {
    rotulo: "receita líquida",
    valor: receitaBruta.valor - deducoes.valor,
    n: receitaBruta.n,
  };
  const custos = somar(de("custo"), "custos", () => true);
  const sga = somar(de("sga"), "SG&A", () => true);
  const tributos = somar(de("tributos"), "tributos sobre o lucro", () => true);
  // A TAXA DA DÍVIDA SE MEDE COM O QUE A DÍVIDA CUSTA, e o bloco
  // `resultado_financeiro` tem as DUAS pontas: o juro pago e o rendimento da
  // aplicação. Somar as duas em magnitude — que era o que estava aqui — INFLA a
  // taxa pelo rendimento. Medido: despesa 9.000 e receita 1.500 sobre dívida de
  // 30.000 devolviam 35% onde o custo é 30%. Cinco pontos de custo de dívida,
  // entrando no modelo como premissa.
  const despesaFinanceira = somar(de("resultado_financeiro"), "despesa financeira",
    (l) => ehDespesaFinanceira(l.chave));

  // O resultado antes dos tributos, pela mesma cascata: RL − custos − SG&A ± financeiro.
  // O sinal do financeiro volta a importar aqui, então ele é lido da linha e não da
  // magnitude.
  const financeiroComSinal = de("resultado_financeiro")
    .filter((l) => l.papel === "conta")
    .reduce((s, l) => s + l.valor_ultimo, 0);
  const lair: Bolsa = {
    rotulo: "resultado antes dos tributos",
    valor: receitaLiquida.valor - custos.valor - sga.valor + financeiroComSinal,
    n: receitaBruta.n > 0 ? 1 : 0,
  };

  const clientes = somar(de("ativo_circulante"), "clientes", (l) => ehCliente(l.chave));
  const estoques = somar(de("ativo_circulante"), "estoques", (l) => ehEstoque(l.chave));
  const fornecedores = somar(de("passivo_circulante"), "fornecedores", (l) => ehFornecedor(l.chave));

  // A DÍVIDA ONEROSA atravessa os dois passivos e o mapa de dívida, e é o mesmo
  // `ehDividaFinanceira` que a aba de dívida usa para não deixar empréstimo virar
  // giro.
  const passivosTodos = [...de("passivo_circulante"), ...de("passivo_nao_circulante")];
  const divida = somar([...passivosTodos, ...de("divida")], "dívida financeira",
    (l) => ehDividaFinanceira(l.chave) || l.documentos?.includes("MAPA_DIVIDA") === true);
  const passivoTotal = somar(passivosTodos, "passivo total", () => true);

  return [
    razao("CUSTO_VARIAVEL", "Custo variável (% da receita)", "%",
      "custos ÷ receita líquida", custos, receitaLiquida),
    razao("SGA_PCT", "SG&A (% da receita)", "%",
      "SG&A ÷ receita líquida", sga, receitaLiquida),
    razao("PMR", "Prazo médio de recebimento", "dias",
      "clientes ÷ receita líquida × 360", clientes, receitaLiquida, 360),
    // ESTOQUE GIRA CONTRA RECEITA LÍQUIDA e não contra custo, e isso contraria o
    // PME de manual de propósito: é a base que o `Working Capital` aplica ao
    // projetar a conta (só fornecedor gira contra custo). Medir contra custo aqui
    // faria o dia sugerido não reproduzir o saldo de onde ele saiu.
    razao("PME", "Prazo médio de estoque", "dias",
      "estoques ÷ receita líquida × 360", estoques, receitaLiquida, 360),
    razao("PMP", "Prazo médio de pagamento", "dias",
      "fornecedores ÷ custos × 360", fornecedores, custos, 360),
    // ALÍQUOTA COM PREJUÍZO NÃO É ALÍQUOTA NEGATIVA. Este produto atende mandato
    // de REESTRUTURAÇÃO, então LAIR negativo é o caso normal e não a exceção —
    // e tributo dividido por prejuízo devolvia, medido, −5,85%. Uma alíquota
    // negativa aplicada à projeção faz o fisco PAGAR a empresa sobre o lucro
    // futuro: o modelo passa a inventar caixa exatamente na direção que lisonjeia
    // o caso. É a mesma doutrina do `Output`, que se recusa a publicar ROE com PL
    // negativo em vez de imprimir um retorno positivo enganoso.
    razao("ALIQUOTA", "Alíquota efetiva de tributos", "%",
      "tributos sobre o lucro ÷ resultado antes dos tributos", tributos, lair, 1,
      "o resultado antes dos tributos é NEGATIVO neste caso, e alíquota efetiva sobre prejuízo "
      + "não é uma taxa: aplicada à projeção ela devolveria crédito onde há lucro. Digite a "
      + "alíquota que o caso vai usar daqui para frente"),
    razao("PARCELA_ONEROSA", "Parcela onerosa do passivo", "%",
      "dívida financeira ÷ passivo total", divida, passivoTotal),
    razao("TAXA_DIVIDA", "Taxa média da dívida", "%",
      "despesa financeira ÷ dívida financeira", despesaFinanceira, divida),
  ];
}
