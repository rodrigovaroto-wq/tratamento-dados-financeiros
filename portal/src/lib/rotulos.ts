// RÓTULOS LEGÍVEIS — a tradução do vocabulário interno para o que se lê na tela.
//
// POR QUE ESTE ARQUIVO EXISTE. O banco guarda chave canônica (`ativo_circulante`,
// `precondicao_nao_satisfeita`), que é o certo para o banco: chave estável, sem
// acento, sem espaço, comparável. O erro era publicar essa chave na TELA. Quem lê
// não é o banco — é o analista, e "passivo_nao_circulante" num cabeçalho é ao mesmo
// tempo mais feio e menos informativo que "Passivo Não Circulante".
//
// O pedido do dono (07/08/2026) foi explícito: nada de `_`, título em maiúscula
// quando é título, e ACENTO em todo lugar. O acento não é estética — "divida" e
// "dívida" são palavras diferentes em português, e a primeira não é a que se quer.
//
// A regra é: mapa explícito para o que tem nome próprio, e um humanizador genérico
// como rede de segurança — chave nova aparece legível mesmo antes de alguém a
// mapear, em vez de vazar `snake_case` para o cliente.
import { BALANCO_SECOES, DRE_SECOES, FLUXO_CAIXA_SECOES } from "./statement-templates";

/** Siglas: ficam MAIÚSCULAS, sempre. */
const SIGLAS = new Set([
  "dre", "dfc", "dmpl", "ebit", "ebitda", "cnpj", "cpf", "icms", "ipi", "pis",
  "cofins", "iss", "irpj", "csll", "irrf", "inss", "fgts", "cdi", "ipca", "igpm",
  "igp", "inpc", "selic", "pib", "usd", "brl", "sac", "dscr", "sga", "capex",
  "bndes", "finame", "tjlp", "cpc", "ncg", "pl", "bp", "id", "ok",
]);

/** Palavras que o vocabulário interno guarda sem acento e que a tela precisa com. */
const ACENTOS: Record<string, string> = {
  nao: "não", divida: "dívida", dividas: "dívidas", patrimonio: "patrimônio",
  liquido: "líquido", liquida: "líquida", tributario: "tributário",
  tributaria: "tributária", tributarios: "tributários", precondicao: "pré-condição",
  extracao: "extração", secao: "seção", secoes: "seções", orgao: "órgão",
  periodo: "período", credito: "crédito", debito: "débito", saldo: "saldo",
  imposto: "imposto", impostos: "impostos", exercicio: "exercício",
  provisao: "provisão", provisoes: "provisões", obrigacao: "obrigação",
  obrigacoes: "obrigações", operacao: "operação", operacoes: "operações",
  reconciliacao: "reconciliação", divergencia: "divergência",
  aprovacao: "aprovação", ressalva: "ressalva", intragrupo: "intragrupo",
  mutuo: "mútuo", mutuos: "mútuos", cambio: "câmbio", juros: "juros",
  amortizacao: "amortização", captacao: "captação", pagamento: "pagamento",
  emprestimo: "empréstimo", emprestimos: "empréstimos", debenture: "debênture",
  debentures: "debêntures", arrendamento: "arrendamento", garantia: "garantia",
  sazonalidade: "sazonalidade", premissa: "premissa", premissas: "premissas",
  faturamento: "faturamento", balancete: "balancete", balanco: "balanço",
  combinado: "combinado", mensal: "mensal", anual: "anual",
  classificacao: "classificação", entidade: "entidade", conta: "conta",
  contas: "contas", valor: "valor", material: "material", suspeito: "suspeito",
  padrao: "padrão", confianca: "confiança", ilegivel: "ilegível",
  satisfeita: "satisfeita", aritmetica: "aritmética", serie: "série",
  numerico: "numérico", numerica: "numérica", unico: "único", ultimo: "último",
  proximo: "próximo", minimo: "mínimo", maximo: "máximo", medio: "médio",
  media: "média", indice: "índice", indices: "índices", macro: "macro",
};

/** Palavras que ficam minúsculas no meio de um título. */
const MINUSCULAS = new Set(["de", "da", "do", "das", "dos", "e", "em", "no", "na", "por", "para", "sobre", "a", "o"]);

/**
 * Humanizador genérico: `passivo_nao_circulante` → "Passivo Não Circulante".
 * Rede de segurança para chave que ninguém mapeou ainda.
 */
export function humanizar(chave: string): string {
  const palavras = chave.trim().replace(/[_:]+/g, " ").replace(/\s+/g, " ").split(" ");
  return palavras
    .map((p, i) => {
      const bruta = p.toLowerCase();
      if (SIGLAS.has(bruta)) return bruta.toUpperCase();
      const comAcento = ACENTOS[bruta] ?? bruta;
      if (i > 0 && MINUSCULAS.has(bruta)) return comAcento;
      return comAcento.charAt(0).toUpperCase() + comAcento.slice(1);
    })
    .join(" ");
}

/** Seções canônicas com nome próprio, das três estruturas que o sistema conhece. */
const SECOES = new Map<string, string>([
  ...[...BALANCO_SECOES, ...DRE_SECOES, ...FLUXO_CAIXA_SECOES].map(
    (s) => [s.key, s.label] as [string, string],
  ),
  // As que não vêm de uma estrutura de demonstração — dívida, tributos e afins.
  ["divida", "Mapa de Dívida"],
  ["tributos", "Tributos a Recolher"],
  ["intragrupo", "Mútuos e Intragrupo"],
  ["faturamento", "Faturamento Mensal"],
  ["outros", "Outros"],
]);

/**
 * O nome de uma seção canônica na TELA. `null`/vazio devolve a frase que explica a
 * ausência — a seção sem classificação é uma informação, não um buraco.
 */
export function rotuloDaSecao(chave: string | null | undefined): string {
  if (!chave || chave === "(sem seção canônica)") return "Linhas sem seção identificada";
  return SECOES.get(chave) ?? humanizar(chave);
}

/** Tipos de pendência, com o nome que o analista usa. */
const PENDENCIAS = new Map<string, string>([
  ["precondicao_nao_satisfeita", "falta um lado da conta"],
  ["divergencia_aritmetica", "os números não fecham"],
  ["divergencia_classe_b", "divergência entre documentos"],
  ["arquivo_ilegivel", "arquivo ilegível"],
  ["extracao_falhou", "a extração falhou"],
  ["extracao_padrao_suspeito", "conferir contra o original"],
  ["extracao_confianca_baixa", "conferir contra o original"],
  ["classificacao_incerta", "classificação a confirmar"],
  ["entidade_incerta", "entidade a confirmar"],
  ["periodo_incerto", "período a confirmar"],
]);

export function rotuloDaPendencia(tipo: string): string {
  return PENDENCIAS.get(tipo) ?? humanizar(tipo);
}

/**
 * Quebra a descrição de uma pendência em PARTES LEGÍVEIS.
 *
 * As mensagens são geradas no banco e emendam vários fatos com `;` — o que numa
 * tela vira um parágrafo em que ninguém acha o que importa. Aqui elas voltam a ser
 * uma lista, para a tela pôr uma por linha.
 *
 * O `;` DENTRO DE PARÊNTESES OU COLCHETES NÃO SEPARA NADA: ele está lá justamente
 * para qualificar o item (`[entidade: —; período: 31/12/2024]`). Quebrar ali
 * partiria o qualificador do fato que ele qualifica — foi o primeiro desenho, e
 * produzia linhas órfãs do tipo "período: 31/12/2024]".
 */
export function partesDaDescricao(texto: string): string[] {
  const partes: string[] = [];
  let atual = "";
  let profundidade = 0;
  for (let i = 0; i < texto.length; i++) {
    const ch = texto[i];
    if (ch === "(" || ch === "[") profundidade++;
    else if (ch === ")" || ch === "]") profundidade = Math.max(0, profundidade - 1);
    if (ch === ";" && profundidade === 0) { partes.push(atual.trim()); atual = ""; continue; }
    // FIM DE FRASE também separa fato: as mensagens emendam "achei o Balanço" com
    // "2024 está assim" e "2025 está assim" usando ponto, não só `;`. O ponto só
    // separa quando vem SEGUIDO DE ESPAÇO — assim `14529.00` e `R$ 1.234` seguem
    // inteiros, que é o defeito óbvio de quebrar por `.`.
    if (ch === "." && profundidade === 0 && /\s/.test(texto[i + 1] ?? "")) {
      partes.push((atual + ch).trim()); atual = ""; i++; continue;
    }
    atual += ch;
  }
  if (atual.trim()) partes.push(atual.trim());
  return partes.filter(Boolean);
}

/**
 * Troca o vocabulário interno que sobra nas mensagens do banco pelo de tela.
 * Conservador de propósito: só o que é claramente jargão de campo, para não
 * reescrever o conteúdo da mensagem — que é medição, e medição não se edita.
 */
export function suavizarMensagem(texto: string): string {
  return texto
    .replace(/\bcoluna de entidade:\s*\(qualquer\)/gi, "qualquer entidade")
    .replace(/\bcoluna de per[ií]odo:\s*/gi, "coluna ")
    .replace(/\bentidade:\s*—/gi, "sem entidade")
    .replace(/\bper[ií]odo:\s*/gi, "")
    .replace(/\bsecao_canonica\b/g, "seção")
    .replace(/\brotulo_norm\b/g, "rótulo")
    .replace(/\bf0\/\d+\b/g, "")
    .replace(/\s{2,}/g, " ")
    .trim();
}
