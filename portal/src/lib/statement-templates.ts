// Classificação por SEÇÃO (não por nome de conta fixo) para o export Excel
// (f0/07_output_spec.md, Modo B). Um template com ~15 nomes de conta exatos
// quebra na primeira empresa que nomeia as contas diferente — cada empresa
// tem seu próprio plano de contas. A abordagem certa (a mesma de um
// balancete/razão de verdade) é: classificar cada conta extraída na SEÇÃO
// correta (Ativo Circulante, Passivo Não Circulante, etc.) por sinais amplos
// — a `secao` que a IA já anotou (docs/01, `db/migrations/0010`) + palavras-
// chave no rótulo — e then LISTAR a conta com o nome ORIGINAL que a empresa
// usa, dentro da seção certa. Nenhuma conta fica de fora só por causa da
// redação; o que não é classificável com segurança cai num bloco explícito
// "Contas Não Classificadas" (nunca desaparece, nunca é forçada pro lugar
// errado).
//
// IMPORTANTE (doutrina, docs/01): nenhum subtotal/total aqui é CALCULADO por
// soma de itens — só aparece se o próprio documento extraído trouxer aquela
// linha explicitamente (ex.: "Total do Ativo Circulante" como linha do PDF).
// Não inventamos números novos — só classificamos e reorganizamos o que já
// foi extraído.

import type { CampoExtraido } from "./types";

export function normalizar(s: string): string {
  return s
    .normalize("NFD")
    .replace(/[̀-ͯ]/g, "")
    .toLowerCase()
    .replace(/\s+/g, " ")
    .trim();
}

// Singularização aproximada (PT-BR) — cobre os padrões de plural mais comuns
// no vocabulário contábil ("contas"→"conta", "deduções"→"dedução",
// "materiais"→"material", "credores"→"credor"). Não é um stemmer completo,
// só o suficiente para o casamento de seção não quebrar por causa de plural/
// singular — o achado real do dono ("Duplicatas a Receber" no documento vs.
// "duplicata a receber" na regra não batiam por causa do 's').
function singularizar(palavra: string): string {
  if (palavra.length <= 3) return palavra;
  if (palavra.endsWith("oes") || palavra.endsWith("aes")) return palavra.slice(0, -3) + "ao";
  if (palavra.endsWith("ais")) return palavra.slice(0, -3) + "al";
  if (palavra.endsWith("eis")) return palavra.slice(0, -3) + "el";
  if (palavra.endsWith("ois")) return palavra.slice(0, -3) + "ol";
  if (palavra.length > 5 && palavra.endsWith("res")) return palavra.slice(0, -2);
  if (palavra.endsWith("s")) return palavra.slice(0, -1);
  return palavra;
}

// Conectivos (preposição/artigo) — ignorados no casamento. Documentos reais
// variam a preposição ("provisão PARA férias" vs. "provisão DE férias") sem
// mudar o significado contábil; exigir a preposição exata quebraria o
// casamento à toa.
const CONECTIVOS = new Set([
  "de", "da", "do", "das", "dos", "e", "a", "o", "as", "os", "para", "com", "em", "na", "no", "nas", "nos", "um", "uma",
]);

function tokensDe(texto: string): Set<string> {
  return new Set(
    normalizar(texto)
      .split(/[^a-z0-9]+/)
      .filter(Boolean)
      .map(singularizar)
      .filter((t) => !CONECTIVOS.has(t)),
  );
}

// Verifica se TODAS as palavras SIGNIFICATIVAS de `frase` aparecem em
// `tokens` — por PALAVRA (tolerante a plural via singularização e a
// conectivos diferentes), não por substring nem por ordem. É o que permite
// "Duplicatas a Receber - Terceiros" (redação real de uma empresa) casar
// com a regra "duplicata a receber", e "Provisão PARA Férias" casar com
// "provisão DE férias", mesmo com plural/preposição/palavras extras.
function contemFrase(tokens: Set<string>, frase: string): boolean {
  const tokensFrase = normalizar(frase)
    .split(/[^a-z0-9]+/)
    .filter(Boolean)
    .map(singularizar)
    .filter((t) => !CONECTIVOS.has(t));
  return tokensFrase.every((t) => tokens.has(t));
}

function contemAlgumaFrase(tokens: Set<string>, frases: string[]): boolean {
  return frases.some((frase) => contemFrase(tokens, frase));
}

export interface SecaoDef {
  key: string;
  label: string;
  grupo?: string; // agrupador visual maior (ex.: "ATIVO") — só no layout hierárquico do Balanço
}

export interface Classificacao {
  secaoKey: string | null; // seção onde a conta entra (null = não classificável)
  ancoraKey: string | null; // é uma linha-âncora (subtotal/total já extraído) — ver ANCORAS
}

const SEM_CLASSIFICACAO: Classificacao = { secaoKey: null, ancoraKey: null };

// ----- Balanço / Balancete / Combinado (estrutura hierárquica Ativo/Passivo) -
export const BALANCO_SECOES: SecaoDef[] = [
  { key: "ativo_circulante", label: "Ativo Circulante", grupo: "ATIVO" },
  { key: "ativo_nao_circulante", label: "Ativo Não Circulante", grupo: "ATIVO" },
  { key: "passivo_circulante", label: "Passivo Circulante", grupo: "PASSIVO E PATRIMÔNIO LÍQUIDO" },
  { key: "passivo_nao_circulante", label: "Passivo Não Circulante", grupo: "PASSIVO E PATRIMÔNIO LÍQUIDO" },
  { key: "patrimonio_liquido", label: "Patrimônio Líquido", grupo: "PASSIVO E PATRIMÔNIO LÍQUIDO" },
];

// Âncoras: linhas que são elas mesmas um subtotal/total já extraído do
// documento. `apos` diz depois de qual seção (na ordem de BALANCO_SECOES)
// a âncora aparece; `grupo` marca que é o total do grupo inteiro (aparece
// no fim de todas as seções daquele grupo).
export const BALANCO_ANCORAS = [
  { key: "total_ativo_circulante", label: "Total do Ativo Circulante", aposSecao: "ativo_circulante" },
  { key: "total_ativo_nao_circulante", label: "Total do Ativo Não Circulante", aposSecao: "ativo_nao_circulante" },
  { key: "total_ativo", label: "TOTAL DO ATIVO", grupo: "ATIVO" },
  { key: "total_passivo_circulante", label: "Total do Passivo Circulante", aposSecao: "passivo_circulante" },
  { key: "total_passivo_nao_circulante", label: "Total do Passivo Não Circulante", aposSecao: "passivo_nao_circulante" },
  { key: "total_patrimonio_liquido", label: "Total do Patrimônio Líquido", aposSecao: "patrimonio_liquido" },
  { key: "total_passivo_pl", label: "TOTAL DO PASSIVO E PATRIMÔNIO LÍQUIDO", grupo: "PASSIVO E PATRIMÔNIO LÍQUIDO" },
] as const;

const ATIVO_CIRC_KW = [
  "caixa", "banco", "equivalente de caixa", "disponibilidade", "aplicacao financeira", "titulo e valor mobiliario",
  "cliente", "contas a receber", "duplicata a receber", "estoque", "mercadoria", "produto acabado", "materia prima",
  "imposto a recuperar", "tributo a recuperar", "despesa antecipada", "adiantamento a fornecedor", "outros creditos",
  "adiantamento a empregado",
];
const ATIVO_NAO_CIRC_KW = [
  "imobilizado", "intangivel", "investimento", "realizavel a longo prazo", "depreciacao acumulada",
  "amortizacao acumulada", "direito de uso", "deposito judicial", "credito com pessoas ligadas",
  "credito com partes relacionadas", "credito com terceiros", "credito c terceiros",
  "obra em andamento", "adiantamento para futuro aumento de capital",
];

// Subgrupos do Ativo Não Circulante (Lei 6.404/76 art. 178 + CPC 26): a conta
// não circulante é sub-classificada em Realizável a LP / Investimentos /
// Imobilizado / Intangível. O que não casar com segurança cai no bucket
// genérico "ativo_nao_circulante" (Outros), nunca some.
const REALIZAVEL_LP_KW = [
  "realizavel a longo prazo", "credito com pessoas ligadas", "credito com partes relacionadas",
  "credito com terceiros", "credito c terceiros", "credito c/terceiros", "conta a receber longo prazo",
  "deposito judicial", "adiantamento para futuro aumento de capital", "tributo a recuperar longo prazo",
  "aplicacao financeira longo prazo", "mutuo a receber", "partes relacionadas",
];
const INVESTIMENTOS_KW = [
  "investimento", "participacao societaria", "participacao em outras empresas", "participacao em coligada",
  "participacao em controlada", "propriedade para investimento", "coligada", "controlada",
];
const IMOBILIZADO_KW = [
  "imobilizado", "imovel", "maquina", "equipamento", "veiculo", "movei", "utensilio", "terreno",
  "edificacao", "edificio", "obra em andamento", "instalacao", "ferramenta", "benfeitoria",
  "depreciacao acumulada", "bem do ativo imobilizado", "adiantamento a fornecedor de imobilizado",
];
const INTANGIVEL_KW = [
  "intangivel", "software", "marca", "patente", "agio", "fundo de comercio", "direito de uso",
  "licenca", "amortizacao acumulada", "gasto com desenvolvimento", "mais valia",
];

// Sub-classifica uma conta já sabida do Ativo Não Circulante num subgrupo CPC.
// Devolve o bucket genérico quando nenhum subgrupo casa (nunca força palpite).
function subgrupoNaoCirculante(tokensChave: Set<string>): string {
  if (contemAlgumaFrase(tokensChave, INTANGIVEL_KW)) return "intangivel";
  if (contemAlgumaFrase(tokensChave, IMOBILIZADO_KW)) return "imobilizado";
  if (contemAlgumaFrase(tokensChave, INVESTIMENTOS_KW)) return "investimentos";
  if (contemAlgumaFrase(tokensChave, REALIZAVEL_LP_KW)) return "realizavel_lp";
  return "ativo_nao_circulante";
}
const PASSIVO_CIRC_KW = [
  "fornecedor", "salario", "obrigacao trabalhista", "obrigacao social", "obrigacao tributaria",
  "imposto a pagar", "tributo a pagar", "adiantamento de cliente", "dividendo a pagar", "provisao de ferias",
  "decimo terceiro", "conta a pagar", "encargo social", "inss", "fgts a recolher",
];
const PASSIVO_NAO_CIRC_KW = [
  "provisao para contingencia", "obrigacao de longo prazo", "partes relacionadas longo prazo",
  "imposto de renda diferido", "tributos diferidos",
];
const PL_KW = [
  "capital social", "reserva de capital", "reserva de lucro", "lucro acumulado", "prejuizo acumulado",
  "ajuste de avaliacao patrimonial", "acoes em tesouraria", "patrimonio liquido", "capital a integralizar",
];
const EMPRESTIMO_FINANCIAMENTO_KW = ["emprestimo", "financiamento", "debenture", "arrendamento", "mutuo"];

// Palavras puramente ESTRUTURAIS (nome de grupo/seção/subgrupo) — uma linha
// cujo rótulo é feito só delas (+ "total"/"soma") é um TOTAL/cabeçalho que o
// documento trouxe, não uma conta. É o que faz "NÃO CIRCULANTE 12.080.078,23"
// ser reconhecido como o total da seção (indo para o nó certo) em vez de virar
// "mais uma conta no meio" — e resolve o "nomes iguais para valores diferentes"
// ("CIRCULANTE" sob Ativo vs. sob Passivo viram os totais de cada seção).
const ESTRUTURAIS = new Set([
  "ativo", "passivo", "circulante", "nao", "patrimonio", "liquido", "total", "soma",
  "realizavel", "longo", "prazo", "investimento", "imobilizado", "intangivel", "permanente",
  "subtotal", "grupo", "geral",
]);

// Devolve o NÓ da estrutura cujo TOTAL esta linha representa (ver BALANCO_OUTLINE)
// ou null se a linha não for um total/cabeçalho. Usa o contexto de `secao` para
// desambiguar rótulos "nus" iguais (ex.: "CIRCULANTE" sob Ativo vs. Passivo).
function ancoraBalanco(tokensChave: Set<string>, tokensSecao: Set<string>): string | null {
  const temTotal = tokensChave.has("total") || contemFrase(tokensChave, "soma");
  const soEstrutural = tokensChave.size > 0 && [...tokensChave].every((t) => ESTRUTURAIS.has(t));
  if (!temTotal && !soEstrutural) return null;

  const ctxAtivo = tokensChave.has("ativo") || tokensSecao.has("ativo");
  const ctxPassivo = tokensChave.has("passivo") || tokensSecao.has("passivo");
  const patrimonio = contemFrase(tokensChave, "patrimonio liquido") || (tokensSecao.has("patrimonio") && !tokensChave.has("ativo") && !tokensChave.has("passivo"));
  const naoCirc = contemFrase(tokensChave, "nao circulante") || contemFrase(tokensChave, "longo prazo") || tokensChave.has("permanente");
  const circ = tokensChave.has("circulante") && !naoCirc;
  const realizavel = tokensChave.has("realizavel");
  const invest = tokensChave.has("investimento");
  const imob = tokensChave.has("imobilizado");
  const intang = tokensChave.has("intangivel");

  // Total do GRUPO Passivo+PL ("total do passivo E do patrimônio líquido") —
  // o rótulo menciona passivo E patrimônio JUNTOS. Um rótulo só "Patrimônio
  // Líquido" (mesmo com secao=PASSIVO) é o total da SEÇÃO PL, não do grupo —
  // por isso exigimos "passivo" no PRÓPRIO rótulo, não no contexto da seção.
  if (tokensChave.has("passivo") && contemFrase(tokensChave, "patrimonio liquido")) return "PASSIVO_PL";
  // Subgrupos do Ativo Não Circulante (subtotais).
  if (realizavel) return "realizavel_lp";
  if (invest && !ctxPassivo) return "investimentos";
  if (imob && !ctxPassivo) return "imobilizado";
  if (intang && !ctxPassivo) return "intangivel";
  // Patrimônio Líquido (total).
  if (patrimonio) return "patrimonio_liquido";
  // Seções circulante / não circulante, desambiguadas por Ativo/Passivo.
  if (ctxPassivo) {
    if (circ) return "passivo_circulante";
    if (naoCirc) return "passivo_nao_circulante";
  }
  if (ctxAtivo || (!ctxPassivo && (circ || naoCirc))) {
    if (circ) return "ativo_circulante";
    if (naoCirc) return "ativo_nao_circulante_grp"; // total da SEÇÃO (nó pai), não o bucket "Outros"
    return "ATIVO"; // "TOTAL DO ATIVO" sem qualificar circulante
  }
  if (ctxPassivo) return "PASSIVO_PL";
  return null;
}

export function classificarBalanco(secao: string | null, chave: string): Classificacao {
  const tokensChave = tokensDe(chave);
  const tokensSecao = tokensDe(secao || "");

  // 1) A linha É um total/cabeçalho que o documento trouxe? Vira âncora do nó
  // correspondente (não conta) — assim ela aparece ALINHADA com o total da
  // seção, não perdida no meio das contas.
  const anc = ancoraBalanco(tokensChave, tokensSecao);
  if (anc) return { secaoKey: null, ancoraKey: anc };

  // 2) Seção anotada pela IA no diagnóstico/extração (db/migrations/0010) —
  // mais confiável que adivinhar só pelo rótulo da conta.
  if (tokensSecao.size > 0) {
    const naoCirc = contemFrase(tokensSecao, "nao circulante") || contemFrase(tokensSecao, "longo prazo") || tokensSecao.has("permanente");
    if (contemFrase(tokensSecao, "patrimonio liquido")) return { secaoKey: "patrimonio_liquido", ancoraKey: null };
    if (tokensSecao.has("ativo")) {
      if (naoCirc) return { secaoKey: subgrupoNaoCirculante(tokensChave), ancoraKey: null };
      if (tokensSecao.has("circulante")) return { secaoKey: "ativo_circulante", ancoraKey: null };
    }
    if (tokensSecao.has("passivo")) {
      if (naoCirc) return { secaoKey: "passivo_nao_circulante", ancoraKey: null };
      if (tokensSecao.has("circulante")) return { secaoKey: "passivo_circulante", ancoraKey: null };
    }
  }

  // 3) Palavras-chave do próprio rótulo (fallback — cobre quando a seção não
  // veio ou não foi clara o suficiente).
  if (contemAlgumaFrase(tokensChave, EMPRESTIMO_FINANCIAMENTO_KW)) {
    // Empréstimo/mútuo pode ser DÍVIDA (passivo, ex. "Empréstimos Bancários")
    // ou um DIREITO da empresa (ativo, ex. "Mútuo a Receber de Coligada" —
    // comum em holdings/grupos econômicos). Sem esse sinal, tudo caía em
    // passivo, mesmo quando o rótulo dizia "a receber".
    const longoPrazo = contemFrase(tokensChave, "longo prazo") || contemFrase(tokensChave, "nao circulante");
    if (tokensChave.has("receber")) {
      return { secaoKey: longoPrazo ? "realizavel_lp" : "ativo_circulante", ancoraKey: null };
    }
    return { secaoKey: longoPrazo ? "passivo_nao_circulante" : "passivo_circulante", ancoraKey: null };
  }
  if (contemAlgumaFrase(tokensChave, PL_KW)) return { secaoKey: "patrimonio_liquido", ancoraKey: null };
  if (contemAlgumaFrase(tokensChave, ATIVO_CIRC_KW)) return { secaoKey: "ativo_circulante", ancoraKey: null };
  if (contemAlgumaFrase(tokensChave, ATIVO_NAO_CIRC_KW)) return { secaoKey: subgrupoNaoCirculante(tokensChave), ancoraKey: null };
  if (contemAlgumaFrase(tokensChave, PASSIVO_CIRC_KW)) return { secaoKey: "passivo_circulante", ancoraKey: null };
  if (contemAlgumaFrase(tokensChave, PASSIVO_NAO_CIRC_KW)) return { secaoKey: "passivo_nao_circulante", ancoraKey: null };

  return SEM_CLASSIFICACAO;
}

// ----- Estrutura hierárquica do Balanço (Lei 6.404/76 art. 178 + CPC 26) -----
// Árvore ordenada usada pelo builder do export: grupo → seção → subseção.
// `folha` = contas caem direto aqui (bucket do classificador); `filhos` = nós
// cujos subtotais somam neste nó. `anc` = a MESMA key é usada como ancoraKey
// quando o documento traz o total daquele nó (comparação formula×extraído).
export type PapelNo = "grupo" | "secao" | "subsecao";
export interface NoBalanco {
  key: string;
  label: string;
  nivel: number;
  papel: PapelNo;
  folha: boolean;
  filhos?: string[];
}
export const BALANCO_OUTLINE: NoBalanco[] = [
  { key: "ATIVO", label: "ATIVO", nivel: 0, papel: "grupo", folha: false, filhos: ["ativo_circulante", "ativo_nao_circulante_grp"] },
  { key: "ativo_circulante", label: "Ativo Circulante", nivel: 1, papel: "secao", folha: true },
  { key: "ativo_nao_circulante_grp", label: "Ativo Não Circulante", nivel: 1, papel: "secao", folha: false, filhos: ["realizavel_lp", "investimentos", "imobilizado", "intangivel", "ativo_nao_circulante"] },
  { key: "realizavel_lp", label: "Realizável a Longo Prazo", nivel: 2, papel: "subsecao", folha: true },
  { key: "investimentos", label: "Investimentos", nivel: 2, papel: "subsecao", folha: true },
  { key: "imobilizado", label: "Imobilizado", nivel: 2, papel: "subsecao", folha: true },
  { key: "intangivel", label: "Intangível", nivel: 2, papel: "subsecao", folha: true },
  { key: "ativo_nao_circulante", label: "Outros Ativos Não Circulantes", nivel: 2, papel: "subsecao", folha: true },
  { key: "PASSIVO_PL", label: "PASSIVO E PATRIMÔNIO LÍQUIDO", nivel: 0, papel: "grupo", folha: false, filhos: ["passivo_circulante", "passivo_nao_circulante", "patrimonio_liquido"] },
  { key: "passivo_circulante", label: "Passivo Circulante", nivel: 1, papel: "secao", folha: true },
  { key: "passivo_nao_circulante", label: "Passivo Não Circulante", nivel: 1, papel: "secao", folha: true },
  { key: "patrimonio_liquido", label: "Patrimônio Líquido", nivel: 1, papel: "secao", folha: true },
];

// ----- DRE (cascata sequencial Receita → Lucro Líquido) --------------------
export const DRE_SECOES: SecaoDef[] = [
  { key: "receita_bruta", label: "Receita Bruta e Deduções" },
  { key: "custos", label: "Custos" },
  { key: "despesas_operacionais", label: "Despesas Operacionais" },
  { key: "resultado_financeiro", label: "Resultado Financeiro" },
  { key: "impostos_lucro", label: "Impostos sobre o Lucro" },
];
export const DRE_ANCORAS = [
  { key: "receita_liquida", label: "Receita Líquida", aposSecao: "receita_bruta" },
  { key: "lucro_bruto", label: "Lucro Bruto", aposSecao: "custos" },
  { key: "resultado_operacional", label: "Resultado Operacional (EBIT)", aposSecao: "despesas_operacionais" },
  { key: "resultado_antes_tributos", label: "Resultado Antes dos Tributos", aposSecao: "resultado_financeiro" },
  { key: "lucro_liquido", label: "Lucro/Prejuízo Líquido do Exercício", aposSecao: "impostos_lucro" },
] as const;

export function classificarDRE(secao: string | null, chave: string): Classificacao {
  const tokens = tokensDe(`${secao || ""} ${chave}`);

  if (contemFrase(tokens, "receita liquida")) return { secaoKey: null, ancoraKey: "receita_liquida" };
  if (contemAlgumaFrase(tokens, ["lucro bruto", "resultado bruto"])) return { secaoKey: null, ancoraKey: "lucro_bruto" };
  if (contemAlgumaFrase(tokens, ["resultado operacional", "ebit", "lucro operacional"])) {
    return { secaoKey: null, ancoraKey: "resultado_operacional" };
  }
  if (contemAlgumaFrase(tokens, ["resultado antes dos tributos", "lucro antes dos impostos", "lair"])) {
    return { secaoKey: null, ancoraKey: "resultado_antes_tributos" };
  }
  if (contemAlgumaFrase(tokens, ["lucro liquido", "prejuizo liquido", "resultado liquido do exercicio"])) {
    return { secaoKey: null, ancoraKey: "lucro_liquido" };
  }
  if (contemAlgumaFrase(tokens, ["receita bruta", "receita operacional bruta", "deducao da receita", "deducao"])) {
    return { secaoKey: "receita_bruta", ancoraKey: null };
  }
  if (contemAlgumaFrase(tokens, ["custo dos produtos", "custo das mercadorias", "custo dos servicos", "cpv", "cmv", "custo da venda"])) {
    return { secaoKey: "custos", ancoraKey: null };
  }
  if (contemAlgumaFrase(tokens, [
    "despesas com venda", "despesas comerciais", "despesas administrativas", "despesas gerais",
    "outras despesas operacionais", "outras receitas operacionais",
  ])) {
    return { secaoKey: "despesas_operacionais", ancoraKey: null };
  }
  if (contemAlgumaFrase(tokens, ["resultado financeiro", "despesas financeiras", "receitas financeiras", "juros"])) {
    return { secaoKey: "resultado_financeiro", ancoraKey: null };
  }
  if (contemAlgumaFrase(tokens, ["imposto de renda", "contribuicao social", "irpj", "csll"])) {
    return { secaoKey: "impostos_lucro", ancoraKey: null };
  }

  return SEM_CLASSIFICACAO;
}

// ----- Fluxo de Caixa (método indireto, CPC 03) -----------------------------
export const FLUXO_CAIXA_SECOES: SecaoDef[] = [
  { key: "atividades_operacionais", label: "Atividades Operacionais" },
  { key: "atividades_investimento", label: "Atividades de Investimento" },
  { key: "atividades_financiamento", label: "Atividades de Financiamento" },
];
export const FLUXO_CAIXA_ANCORAS = [
  { key: "caixa_operacional", label: "Caixa Líquido das Atividades Operacionais", aposSecao: "atividades_operacionais" },
  { key: "caixa_investimento", label: "Caixa Líquido das Atividades de Investimento", aposSecao: "atividades_investimento" },
  { key: "caixa_financiamento", label: "Caixa Líquido das Atividades de Financiamento", aposSecao: "atividades_financiamento" },
  { key: "variacao_liquida_caixa", label: "Aumento (Redução) Líquido de Caixa" },
  { key: "saldo_inicial_caixa", label: "Saldo Inicial de Caixa" },
  { key: "saldo_final_caixa", label: "Saldo Final de Caixa" },
] as const;

export function classificarFluxoCaixa(secao: string | null, chave: string): Classificacao {
  const tokens = tokensDe(`${secao || ""} ${chave}`);

  // Saldos de caixa: documentos reais frequentemente NÃO usam a palavra
  // "saldo" — escrevem "Caixa e Equivalentes de Caixa no Final/Início do
  // Período". Casa também esse padrão (caixa/equivalente + final|inicio +
  // periodo|exercicio), sem casar a linha do Balanço "Caixa e Equivalentes
  // de Caixa" (que não tem final/inicio/periodo).
  if (contemAlgumaFrase(tokens, ["saldo final caixa", "caixa saldo final", "caixa final periodo", "caixa final exercicio", "equivalente caixa final"])) {
    return { secaoKey: null, ancoraKey: "saldo_final_caixa" };
  }
  if (contemAlgumaFrase(tokens, ["saldo inicial caixa", "caixa saldo inicial", "caixa inicio periodo", "caixa inicio exercicio", "equivalente caixa inicio"])) {
    return { secaoKey: null, ancoraKey: "saldo_inicial_caixa" };
  }
  if (contemAlgumaFrase(tokens, [
    "aumento caixa", "reducao caixa", "variacao liquida caixa", "diminuicao caixa",
    "acrescimo caixa", "decrescimo caixa", "acrescimo equivalente caixa", "decrescimo equivalente caixa",
  ])) {
    return { secaoKey: null, ancoraKey: "variacao_liquida_caixa" };
  }
  if (contemAlgumaFrase(tokens, ["caixa liquido atividades operacional", "caixa gerado atividades operacional", "total atividades operacional"])) {
    return { secaoKey: null, ancoraKey: "caixa_operacional" };
  }
  if (contemAlgumaFrase(tokens, ["caixa liquido investimento", "total atividades investimento"])) {
    return { secaoKey: null, ancoraKey: "caixa_investimento" };
  }
  if (contemAlgumaFrase(tokens, ["caixa liquido financiamento", "total atividades financiamento"])) {
    return { secaoKey: null, ancoraKey: "caixa_financiamento" };
  }
  if (contemAlgumaFrase(tokens, [
    "atividades investimento", "aquisicao imobilizado", "aquisicao intangivel", "venda ativo", "alienacao ativo",
  ])) {
    return { secaoKey: "atividades_investimento", ancoraKey: null };
  }
  if (contemAlgumaFrase(tokens, [
    "atividades financiamento", "captacao emprestimo", "pagamento emprestimo", "aporte capital",
    "distribuicao dividendo", "dividendo pago",
  ])) {
    return { secaoKey: "atividades_financiamento", ancoraKey: null };
  }
  if (contemAlgumaFrase(tokens, [
    "atividades operacional", "lucro liquido exercicio", "depreciacao", "amortizacao", "variacao contas receber",
    "variacao estoque", "variacao fornecedor", "capital giro",
  ])) {
    return { secaoKey: "atividades_operacionais", ancoraKey: null };
  }

  return SEM_CLASSIFICACAO;
}

// tipo_taxonomia → qual classificador/estrutura usar. BALANCETE reaproveita o
// classificador do Balanço (um balancete é, por natureza, o mesmo agrupamento
// por seção do plano de contas — só mais granular). COMBINADO idem (uso mais
// comum de "demonstrações combinadas" nos mandatos da Oria é o balanço
// consolidado do grupo, f0/03).
export type EstruturaDemonstracao = "balanco" | "dre" | "fluxo_caixa";

export const ESTRUTURA_POR_TIPO: Record<string, EstruturaDemonstracao> = {
  BALANCO: "balanco",
  BALANCETE: "balanco",
  COMBINADO: "balanco",
  DRE: "dre",
  FLUXO_CAIXA: "fluxo_caixa",
};

// secao_canonica (sugestão da IA por linha, db/migrations/0012) → a QUAL
// demonstração aquela conta pertence. É o que permite separar por aba um PDF
// que traz várias demonstrações juntas ("Demonstrações Contábeis completas":
// Balanço + DRE + Fluxo de Caixa no mesmo arquivo) — cada linha vai para a aba
// da SUA demonstração, não para a do tipo do documento inteiro.
const FAMILIA_POR_SECAO_CANONICA: Record<string, EstruturaDemonstracao> = {
  ativo_circulante: "balanco",
  ativo_nao_circulante: "balanco",
  passivo_circulante: "balanco",
  passivo_nao_circulante: "balanco",
  patrimonio_liquido: "balanco",
  receita_bruta: "dre",
  custos: "dre",
  despesas_operacionais: "dre",
  resultado_financeiro: "dre",
  impostos_lucro: "dre",
  atividades_operacionais: "fluxo_caixa",
  atividades_investimento: "fluxo_caixa",
  atividades_financiamento: "fluxo_caixa",
};

// A qual demonstração (Balanço/DRE/Fluxo de Caixa) uma linha pertence. Usado
// para ROTEAR a linha para a aba certa — separado da classificação da SEÇÃO
// dentro da aba (classificarConta). Prioridade:
//   1) secao_canonica (a IA olhou o conteúdo e disse a qual demonstração é) —
//      "o modelo identifica o que é DRE e o que é Balanço", pedido do dono;
//   2) fallback determinístico quando a IA não anotou — ordem Fluxo de Caixa →
//      DRE → Balanço, porque os sinais de Fluxo/DRE são específicos e o de
//      Balanço casa "caixa" de forma gulosa (senão uma linha de Fluxo cairia
//      no Ativo Circulante, o bug real observado);
//   3) null quando nenhum sinal claro — o chamador mantém a linha na aba do
//      tipo do documento (conservador).
// Não decide nada como fato: a linha continua N1/pendente até o aceite humano;
// isto afeta só EM QUAL ABA a sugestão aparece.
export function classificarDemonstracao(
  secao: string | null,
  chave: string,
  secaoCanonica?: string | null,
): EstruturaDemonstracao | null {
  if (secaoCanonica && FAMILIA_POR_SECAO_CANONICA[secaoCanonica]) {
    return FAMILIA_POR_SECAO_CANONICA[secaoCanonica];
  }
  const fc = classificarFluxoCaixa(secao, chave);
  if (fc.secaoKey || fc.ancoraKey) return "fluxo_caixa";
  const dre = classificarDRE(secao, chave);
  if (dre.secaoKey || dre.ancoraKey) return "dre";
  const bal = classificarBalanco(secao, chave);
  if (bal.secaoKey || bal.ancoraKey) return "balanco";
  return null;
}

// Conjunto de chaves de seção válidas por estrutura — usado para validar a
// sugestão canônica da IA (só entra se pertencer à estrutura do documento).
function secaoKeysDe(estrutura: EstruturaDemonstracao): Set<string> {
  return new Set(secoesDe(estrutura).map((s) => s.key));
}

// Linhas de DMPL (Demonstração das Mutações do PL) — saldos de abertura/
// fechamento por exercício ("SALDOS EM 31 DE DEZEMBRO DE 2024") — NÃO são
// contas do Balanço: o saldo de fechamento REPETE o próprio total do PL, então
// somá-las infla o Patrimônio Líquido (bug real visto no export do dono). Até a
// DMPL ter aba própria, ficam fora da classificação do Balanço (vão para
// "Contas Não Classificadas" — visíveis, sem entrar em nenhuma soma).
function ehLinhaDMPL(chave: string): boolean {
  const t = normalizar(chave);
  if (!t.includes("saldo")) return false;
  return /\b(19|20)\d{2}\b/.test(t) || /\b(inici|final|finai)/.test(t);
}

export function classificarConta(
  estrutura: EstruturaDemonstracao,
  secao: string | null,
  chave: string,
  secaoCanonica?: string | null,
): Classificacao {
  // DMPL no meio de um Balanço/Combinado (documento composto): não classifica —
  // não pode inflar o PL. (No Fluxo de Caixa, "saldo inicial/final de caixa" é
  // tratado à parte pelo classificador do Fluxo, então este guard é só balanço.)
  if (estrutura === "balanco" && ehLinhaDMPL(chave)) return SEM_CLASSIFICACAO;

  const base =
    estrutura === "balanco"
      ? classificarBalanco(secao, chave)
      : estrutura === "dre"
        ? classificarDRE(secao, chave)
        : classificarFluxoCaixa(secao, chave);

  // A regra determinística tem prioridade: se ela achou uma âncora (total) ou
  // uma seção, mantém — é confiável e não depende de golden set (docs/01).
  if (base.ancoraKey || base.secaoKey) return base;

  // Só quando o determinístico ABSTÉM (a conta cairia em "Não Classificadas"),
  // usa a sugestão canônica da IA (N1/advisory, db/migrations/0012) — desde que
  // seja uma seção válida para ESTA estrutura. Preenche a lacuna sem sobrepor a
  // regra; a linha continua pendente/âmbar até o aceite humano. Subir a IA para
  // prioridade/auto-clear exigiria golden set + concordância medida (f0/06).
  if (secaoCanonica && secaoKeysDe(estrutura).has(secaoCanonica)) {
    // A IA sugere a seção no nível achatado (enum de 0012). Se for Ativo Não
    // Circulante, refina no subgrupo CPC (Realizável LP / Investimentos /
    // Imobilizado / Intangível) pelo rótulo — assim a conta cai na subseção
    // certa e os subtotais batem com os que o documento traz.
    if (estrutura === "balanco" && secaoCanonica === "ativo_nao_circulante") {
      return { secaoKey: subgrupoNaoCirculante(tokensDe(chave)), ancoraKey: null };
    }
    return { secaoKey: secaoCanonica, ancoraKey: null };
  }

  return base;
}

export function secoesDe(estrutura: EstruturaDemonstracao): SecaoDef[] {
  if (estrutura === "balanco") return BALANCO_SECOES;
  if (estrutura === "dre") return DRE_SECOES;
  return FLUXO_CAIXA_SECOES;
}

export function ancorasDe(estrutura: EstruturaDemonstracao) {
  if (estrutura === "balanco") return BALANCO_ANCORAS;
  if (estrutura === "dre") return DRE_ANCORAS;
  return FLUXO_CAIXA_ANCORAS;
}

// Agrupa campos com a MESMA chave normalizada (mesma conta, grafias iguais
// entre períodos/entidades da mesma empresa) — alinha a mesma conta na mesma
// linha ao longo das colunas sem forçar nomes canônicos artificiais.
export function agruparPorChaveNormalizada(campos: CampoExtraido[]): Map<string, { label: string; campos: CampoExtraido[] }> {
  const grupos = new Map<string, { label: string; campos: CampoExtraido[] }>();
  for (const campo of campos) {
    const key = normalizar(campo.chave);
    if (!grupos.has(key)) grupos.set(key, { label: campo.chave, campos: [] });
    grupos.get(key)!.campos.push(campo);
  }
  return grupos;
}
