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
  "credito com partes relacionadas", "obra em andamento", "adiantamento para futuro aumento de capital",
];
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
const EMPRESTIMO_FINANCIAMENTO_KW = ["emprestimo", "financiamento", "debenture", "arrendamento"];

export function classificarBalanco(secao: string | null, chave: string): Classificacao {
  const tokensTudo = tokensDe(`${secao || ""} ${chave}`);
  const tokensChave = tokensDe(chave);
  const tokensSecao = tokensDe(secao || "");

  // 1) Âncoras (total/subtotal) primeiro — sinal mais confiável, evita que
  // uma linha de total vire só "mais uma conta" dentro da seção.
  if (tokensTudo.has("total") || contemFrase(tokensTudo, "soma do")) {
    const eAtivo = tokensTudo.has("ativo");
    const ePassivo = tokensTudo.has("passivo");
    const ePatrimonio = contemFrase(tokensTudo, "patrimonio liquido");
    const eNaoCirculante = contemFrase(tokensTudo, "nao circulante");
    const eCirculante = tokensTudo.has("circulante") && !eNaoCirculante;

    if (ePassivo && ePatrimonio) return { secaoKey: null, ancoraKey: "total_passivo_pl" };
    if (eAtivo && !ePassivo) {
      if (eCirculante) return { secaoKey: null, ancoraKey: "total_ativo_circulante" };
      if (eNaoCirculante) return { secaoKey: null, ancoraKey: "total_ativo_nao_circulante" };
      return { secaoKey: null, ancoraKey: "total_ativo" };
    }
    if (ePassivo) {
      if (eCirculante) return { secaoKey: null, ancoraKey: "total_passivo_circulante" };
      if (eNaoCirculante) return { secaoKey: null, ancoraKey: "total_passivo_nao_circulante" };
    }
    if (ePatrimonio) return { secaoKey: null, ancoraKey: "total_patrimonio_liquido" };
  }

  // 2) Seção anotada pela IA no diagnóstico/extração (db/migrations/0010) —
  // mais confiável que adivinhar só pelo rótulo da conta.
  if (tokensSecao.size > 0) {
    const naoCirc = contemFrase(tokensSecao, "nao circulante") || contemFrase(tokensSecao, "longo prazo") || tokensSecao.has("permanente");
    if (contemFrase(tokensSecao, "patrimonio liquido")) return { secaoKey: "patrimonio_liquido", ancoraKey: null };
    if (tokensSecao.has("ativo")) {
      if (naoCirc) return { secaoKey: "ativo_nao_circulante", ancoraKey: null };
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
    const longoPrazo = contemFrase(tokensChave, "longo prazo") || contemFrase(tokensChave, "nao circulante");
    return { secaoKey: longoPrazo ? "passivo_nao_circulante" : "passivo_circulante", ancoraKey: null };
  }
  if (contemAlgumaFrase(tokensChave, PL_KW)) return { secaoKey: "patrimonio_liquido", ancoraKey: null };
  if (contemAlgumaFrase(tokensChave, ATIVO_CIRC_KW)) return { secaoKey: "ativo_circulante", ancoraKey: null };
  if (contemAlgumaFrase(tokensChave, ATIVO_NAO_CIRC_KW)) return { secaoKey: "ativo_nao_circulante", ancoraKey: null };
  if (contemAlgumaFrase(tokensChave, PASSIVO_CIRC_KW)) return { secaoKey: "passivo_circulante", ancoraKey: null };
  if (contemAlgumaFrase(tokensChave, PASSIVO_NAO_CIRC_KW)) return { secaoKey: "passivo_nao_circulante", ancoraKey: null };

  return SEM_CLASSIFICACAO;
}

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

  if (contemAlgumaFrase(tokens, ["saldo final caixa", "caixa saldo final"])) return { secaoKey: null, ancoraKey: "saldo_final_caixa" };
  if (contemAlgumaFrase(tokens, ["saldo inicial caixa", "caixa saldo inicial"])) return { secaoKey: null, ancoraKey: "saldo_inicial_caixa" };
  if (contemAlgumaFrase(tokens, ["aumento caixa", "reducao caixa", "variacao liquida caixa", "diminuicao caixa"])) {
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

export function classificarConta(estrutura: EstruturaDemonstracao, secao: string | null, chave: string): Classificacao {
  if (estrutura === "balanco") return classificarBalanco(secao, chave);
  if (estrutura === "dre") return classificarDRE(secao, chave);
  return classificarFluxoCaixa(secao, chave);
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
