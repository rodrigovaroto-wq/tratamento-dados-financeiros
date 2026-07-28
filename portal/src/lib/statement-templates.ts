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

// Marcadores de CONTA DE DETALHE: uma linha assim nunca é o total da seção.
// "(-) ..."/"(+) ..." é lançamento; "Outras/Outros ..." é conta residual;
// "Variação em ..." é ajuste do método indireto.
const RE_CONTA_DETALHE = /^\s*[([]?\s*[-+]|^\s*outr[ao]s?\b|^\s*variac|^\s*\(-\)/i;

/**
 * A linha É a legenda de um total/resultado (âncora), e não uma conta que por
 * acaso repete algumas palavras dela?
 *
 * `contemFrase` casa por CONJUNTO de palavras, sem ordem — o que é ótimo para
 * tolerar "Duplicatas a receber de clientes" × "Clientes a receber", e péssimo
 * para âncora: "Outras receitas (despesas) operacionais, líquidas" contém
 * "receita" e "líquida", então casava "receita liquida" e a conta era tratada
 * como a linha de RECEITA OPERACIONAL LÍQUIDA (achado no book: a cascata da DRE
 * fechava em -27.550 onde o documento diz -17.901).
 *
 * Critério: além de conter todas as palavras da legenda, o rótulo não pode ser
 * conta de detalhe nem trazer MUITA palavra a mais — legenda de total é curta e
 * quase toda ela é a própria legenda ("RECEITA OPERACIONAL LÍQUIDA" tem 1
 * palavra a mais que "receita líquida"; a conta residual acima tem 3).
 */
// Palavras de FRASEADO que uma legenda de total carrega sem mudar de sentido.
// Demonstração brasileira escreve "Caixa líquido GERADO PELAS (APLICADO NAS)
// ATIVIDADES de investimento" — cinco palavras a mais que "caixa líquido
// investimento", e nenhuma delas muda o que a linha é. Sem esta lista, a
// tolerância de "palavras a mais" reprovava justamente as legendas mais
// verbosas, que são as mais comuns em arquivo real.
const FRASEADO_DE_LEGENDA = new Set([
  "gerado", "gerada", "aplicado", "aplicada", "consumido", "consumida", "utilizado", "utilizada",
  "proveniente", "obtido", "obtida", "oriundo", "oriunda", "decorrente", "atividade", "operacao",
  "pela", "pelo", "na", "no", "exercicio", "periodo", "ano", "total", "geral", "valor",
]);

function ehLegendaDeTotal(chave: string, tokensChave: Set<string>, frase: string, maxExtras = 2): boolean {
  if (RE_CONTA_DETALHE.test(chave)) return false;
  if (!contemFrase(tokensChave, frase)) return false;
  const daFrase = new Set(
    normalizar(frase).split(/[^a-z0-9]+/).filter(Boolean).map(singularizar).filter((t) => !CONECTIVOS.has(t)),
  );
  let extras = 0;
  for (const t of tokensChave) {
    if (daFrase.has(t) || FRASEADO_DE_LEGENDA.has(t)) continue;
    extras++;
  }
  return extras <= maxExtras;
}

function ehLegendaDeAlgumTotal(chave: string, tokensChave: Set<string>, frases: string[], maxExtras = 2): boolean {
  return frases.some((f) => ehLegendaDeTotal(chave, tokensChave, f, maxExtras));
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
  "cliente", "contas a receber", "conta a receber", "valores a receber", "duplicata a receber", "estoque",
  "mercadoria", "produto acabado", "produto em elaboracao", "produto em processo", "produto em andamento",
  "materia prima", "insumo", "numerario", "bens numerarios", "deposito bancario",
  "pecld", "pdd", "provisao para devedores duvidosos", "perda estimada em credito",
  "imposto a recuperar", "tributo a recuperar", "imposto a compensar", "tributo a compensar",
  "icms a recuperar", "icms a compensar", "pis a recuperar", "cofins a recuperar", "irpj a recuperar",
  "csll a recuperar", "ir a recuperar", "despesa antecipada", "despesa paga antecipadamente",
  "adiantamento a fornecedor", "adiantamento a empregado", "adiantamento diverso", "cheque a compensar",
  "outros creditos",
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
// Nomes de SUBSEÇÃO que identificam a seção sem ambiguidade quando o documento
// os declara como `secao` de uma conta. Deliberadamente NÃO inclui
// "Fornecedores", "Empréstimos e Financiamentos", "Partes Relacionadas" nem
// "Provisões": esses cabeçalhos existem no circulante E no não circulante, e
// chutar o lado distorceria liquidez e endividamento.
const SUBSECAO_AUTORITATIVA: Array<[string, string]> = [
  // Subgrupos do Ativo Não Circulante (Lei 6.404/76 art. 178, CPC 26).
  ["realizavel a longo prazo", "realizavel_lp"],
  ["ativo realizavel a longo prazo", "realizavel_lp"],
  ["investimentos", "investimentos"],
  ["imobilizado", "imobilizado"],
  ["ativo imobilizado", "imobilizado"],
  ["intangivel", "intangivel"],
  ["ativo intangivel", "intangivel"],
  // Subseções que só existem no Ativo Circulante.
  ["disponivel", "ativo_circulante"],
  ["disponibilidades", "ativo_circulante"],
  ["caixa e equivalentes de caixa", "ativo_circulante"],
  ["contas a receber", "ativo_circulante"],
  ["clientes", "ativo_circulante"],
  ["duplicatas a receber", "ativo_circulante"],
  ["estoques", "ativo_circulante"],
  ["tributos a recuperar", "ativo_circulante"],
  ["impostos a recuperar", "ativo_circulante"],
  ["outros creditos", "ativo_circulante"],
  ["despesas antecipadas", "ativo_circulante"],
  // Subseções que só existem no Passivo Circulante.
  ["obrigacoes trabalhistas", "passivo_circulante"],
  ["obrigacoes trabalhistas e sociais", "passivo_circulante"],
  ["obrigacoes sociais", "passivo_circulante"],
  ["obrigacoes tributarias", "passivo_circulante"],
  ["obrigacoes fiscais", "passivo_circulante"],
  ["outras obrigacoes", "passivo_circulante"],
  ["contas a pagar", "passivo_circulante"],
];

function subsecaoAutoritativa(tokensSecao: Set<string>): string | null {
  // "Imobilizado" isolado é subseção; "Imobilizado líquido de depreciação" e
  // afins também. Mas se a seção declarada JÁ diz circulante/não circulante,
  // aquela informação é mais específica — deixa o passe seguinte decidir.
  if (tokensSecao.has("circulante")) return null;
  for (const [frase, key] of SUBSECAO_AUTORITATIVA) {
    if (contemFrase(tokensSecao, frase)) return key;
  }
  return null;
}

function subgrupoNaoCirculante(tokensChave: Set<string>): string {
  if (contemAlgumaFrase(tokensChave, INTANGIVEL_KW)) return "intangivel";
  if (contemAlgumaFrase(tokensChave, IMOBILIZADO_KW)) return "imobilizado";
  if (contemAlgumaFrase(tokensChave, INVESTIMENTOS_KW)) return "investimentos";
  if (contemAlgumaFrase(tokensChave, REALIZAVEL_LP_KW)) return "realizavel_lp";
  return "ativo_nao_circulante";
}
const PASSIVO_CIRC_KW = [
  "fornecedor", "salario", "obrigacao trabalhista", "obrigacao social", "obrigacao tributaria", "obrigacao fiscal",
  "imposto a pagar", "tributo a pagar", "imposto a recolher", "tributo a recolher", "contribuicao a recolher",
  "icms a recolher", "iss a recolher", "irpj a recolher", "csll a recolher", "pis a recolher", "cofins a recolher",
  "adiantamento de cliente", "dividendo a pagar", "provisao de ferias", "provisao trabalhista", "receita diferida",
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
    // 2a) A seção declarada é o nome de uma SUBSEÇÃO da própria estrutura?
    // Então ela MANDA. Antes, só seções que diziam "ativo"/"passivo"/"patrimônio
    // líquido" eram consideradas aqui, e um cabeçalho de subseção caía no passe
    // 3 (palavra-chave do rótulo) — onde o vocabulário do rótulo podia mandar a
    // conta para o lugar errado. Achados reais no book:
    //   secao="Realizável a Longo Prazo" chave="Títulos a receber - venda de
    //     imobilizado"  →  ia para `imobilizado`, porque o rótulo diz imobilizado
    //   secao="Investimentos" chave="Mútuos a receber de controladas"
    //     →  ia para `ativo_circulante`
    //   secao="Imobilizado" chave="Terrenos" / "Edificações e benfeitorias"
    //     →  ia para "Não Classificadas"
    // O documento imprimiu a conta debaixo daquele cabeçalho: isso é fato
    // estrutural do arquivo, não palpite. Só entram aqui nomes de subseção
    // INEQUÍVOCOS (subgrupos do art. 178 / CPC 26 e subseções de circulante que
    // não existem nos dois lados do balanço) — "Fornecedores", "Empréstimos e
    // Financiamentos" e "Provisões" aparecem no circulante E no não circulante,
    // então continuam decididos pelo rótulo + consenso de irmãos.
    const subsecaoDeclarada = subsecaoAutoritativa(tokensSecao);
    if (subsecaoDeclarada) return { secaoKey: subsecaoDeclarada, ancoraKey: null };

    const naoCirc = contemFrase(tokensSecao, "nao circulante") || contemFrase(tokensSecao, "longo prazo") || tokensSecao.has("permanente");
    if (tokensSecao.has("ativo")) {
      if (naoCirc) return { secaoKey: subgrupoNaoCirculante(tokensChave), ancoraKey: null };
      if (tokensSecao.has("circulante")) return { secaoKey: "ativo_circulante", ancoraKey: null };
    }
    // "passivo" TEM que ser checado antes de "patrimonio liquido": o
    // cabeçalho combinado "Passivo e Patrimônio Líquido" (padrão MUITO comum
    // em balanços brasileiros, Lei 6.404/76 art. 178) contém as duas palavras
    // — checar "patrimonio liquido" primeiro fazia TODA conta sob esse
    // cabeçalho (até "Fornecedores", "Empréstimos") cair em patrimonio_liquido
    // (achado em produção, sessão 7 cont.¹⁵). Com "passivo" combinado mas sem
    // qualificador de circulante/não circulante, não dá pra decidir só pela
    // seção — cai pro fallback por palavra-chave da própria conta (passo 3).
    if (tokensSecao.has("passivo")) {
      if (naoCirc) return { secaoKey: "passivo_nao_circulante", ancoraKey: null };
      if (tokensSecao.has("circulante")) return { secaoKey: "passivo_circulante", ancoraKey: null };
    } else if (contemFrase(tokensSecao, "patrimonio liquido")) {
      return { secaoKey: "patrimonio_liquido", ancoraKey: null };
    }
  }

  // 3) Palavras-chave do próprio rótulo (fallback — cobre quando a seção não
  // veio ou não foi clara o suficiente).
  //
  // 3a) PARES AMBÍGUOS resolvidos antes do passe genérico: há rótulos em que a
  // MESMA palavra aparece nas duas listas e a ordem de checagem decidia o lado
  // do balanço. Achado com dado real: "Adiantamentos de clientes" (obrigação —
  // o cliente pagou antes da entrega) caía no ATIVO porque "cliente" é
  // palavra-chave de Contas a Receber e o ativo é checado primeiro — pôr uma
  // conta no lado errado distorce subtotais, liquidez e endividamento.
  if (tokensChave.has("adiantamento") && tokensChave.has("cliente")) {
    return { secaoKey: "passivo_circulante", ancoraKey: null };
  }
  // "Receita diferida"/"faturamento antecipado" é obrigação, não receita/ativo.
  if (contemAlgumaFrase(tokensChave, ["receita diferida", "faturamento antecipado", "receita antecipada"])) {
    return { secaoKey: "passivo_circulante", ancoraKey: null };
  }
  // Tributo pode ser a RECUPERAR (ativo) ou a RECOLHER/PAGAR (passivo) — o
  // verbo decide, não a palavra "imposto".
  if (contemAlgumaFrase(tokensChave, ["imposto", "tributo", "icms", "iss", "pis", "cofins", "irpj", "csll", "inss", "fgts"])) {
    if (contemAlgumaFrase(tokensChave, ["recolher", "pagar"])) {
      return { secaoKey: "passivo_circulante", ancoraKey: null };
    }
  }
  if (contemAlgumaFrase(tokensChave, EMPRESTIMO_FINANCIAMENTO_KW)) {
    // Empréstimo/mútuo pode ser DÍVIDA (passivo, ex. "Empréstimos Bancários")
    // ou um DIREITO da empresa (ativo, ex. "Mútuo a Receber de Coligada" —
    // comum em holdings/grupos econômicos). Sem esse sinal, tudo caía em
    // passivo, mesmo quando o rótulo dizia "a receber".
    const longoPrazo = contemFrase(tokensChave, "longo prazo") || contemFrase(tokensChave, "nao circulante");
    // Direção ATIVO (crédito da empresa): "a receber" ou "concedido(s)". O
    // conectivo "a"/"de" ("Empréstimos A Coligadas" vs "DE Coligadas") é
    // removido no matcher, então intragrupo sem "receber"/"concedido" fica
    // ambíguo e cai no default passivo — a `secao` anotada (passo 2) resolve
    // quando o documento diz o lado. Empréstimo bancário tomado (sem sinal de
    // direção) segue corretamente no passivo.
    if (tokensChave.has("receber") || tokensChave.has("concedido")) {
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
// Nomes de SEÇÃO que a demonstração declara e que identificam o bloco sem
// ambiguidade. Mesmo princípio do Balanço (`SUBSECAO_AUTORITATIVA`): se o
// documento imprimiu a conta debaixo de "DESPESAS OPERACIONAIS", ela é despesa
// operacional — não interessa se o rótulo dela está no nosso vocabulário.
// Sem isto, "(-) Honorários da administração" e "(-) Provisão para
// contingências trabalhistas e cíveis" caíam fora da seção e a cascata da DRE
// não fechava com o total informado.
const SECAO_DECLARADA_DRE: Array<[string, string]> = [
  ["receita operacional bruta", "receita_bruta"],
  ["receita bruta", "receita_bruta"],
  ["deducoes da receita", "receita_bruta"],
  ["deducao da receita", "receita_bruta"],
  ["custo dos produtos vendidos", "custos"],
  ["custo das mercadorias vendidas", "custos"],
  ["custo dos servicos prestados", "custos"],
  ["custo dos produtos", "custos"],
  ["custos operacionais", "custos"],
  ["despesas operacionais", "despesas_operacionais"],
  ["despesas administrativas", "despesas_operacionais"],
  ["despesas comerciais", "despesas_operacionais"],
  ["despesas com vendas", "despesas_operacionais"],
  ["resultado financeiro", "resultado_financeiro"],
  ["despesas financeiras", "resultado_financeiro"],
  ["receitas financeiras", "resultado_financeiro"],
  ["tributos sobre o lucro", "impostos_lucro"],
  ["impostos sobre o lucro", "impostos_lucro"],
  ["provisao para imposto de renda", "impostos_lucro"],
];

const SECAO_DECLARADA_FLUXO: Array<[string, string]> = [
  ["atividades operacionais", "atividades_operacionais"],
  ["fluxo de caixa das atividades operacionais", "atividades_operacionais"],
  ["atividades de investimento", "atividades_investimento"],
  ["fluxo de caixa das atividades de investimento", "atividades_investimento"],
  ["atividades de financiamento", "atividades_financiamento"],
  ["fluxo de caixa das atividades de financiamento", "atividades_financiamento"],
];

function secaoDeclarada(tokensSecao: Set<string>, mapa: Array<[string, string]>): string | null {
  if (tokensSecao.size === 0) return null;
  // Mais específico primeiro: "custo dos produtos vendidos" antes de "custo".
  const ordenado = [...mapa].sort((a, b) => b[0].length - a[0].length);
  for (const [frase, key] of ordenado) {
    if (contemFrase(tokensSecao, frase)) return key;
  }
  return null;
}

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

// Subtotais intermediários da DRE que RESTATEM um valor já coberto por outra
// âncora/fórmula (ex.: "Resultado antes do Resultado Financeiro" repete o
// EBIT; "Resultado Financeiro Líquido" repete a soma de Despesas+Receitas
// Financeiras já dentro da própria seção) — comuns em demonstrações reais
// (apresentação por cascata com subtotal explícito entre grupos), mas o
// rótulo compartilha vocabulário com a seção onde a linha está ("resultado
// financeiro" aparece tanto na âncora quanto no cabeçalho da seção
// "Resultado Financeiro"), então caíam classificadas como uma CONTA comum
// dentro da seção e eram somadas de novo — dobrando o valor no total
// calculado (achado em produção, sessão 7 cont.¹⁵). Ficam fora da soma (igual
// à DMPL, `ehLinhaDMPL`) até terem âncora própria; aparecem em "Contas Não
// Classificadas", visíveis, sem distorcer nenhum subtotal.
function ehSubtotalRedundanteDRE(chave: string): boolean {
  const t = tokensDe(chave);
  if (contemFrase(t, "resultado financeiro") && (t.has("antes") || contemFrase(t, "resultado liquido"))) return true;
  if (contemFrase(t, "resultado antes") && t.has("financeiro")) return true;
  return false;
}

export function classificarDRE(secao: string | null, chave: string): Classificacao {
  const tokens = tokensDe(`${secao || ""} ${chave}`);
  // ÂNCORA olha só o RÓTULO. Misturar o nome da seção fazia a conta herdar as
  // palavras do cabeçalho e virar "total da seção" — no book, "Mútuos recebidos
  // da controladora" ficava sendo o Caixa Líquido de Financiamento porque a
  // seção se chama "FLUXO DE CAIXA DAS ATIVIDADES DE FINANCIAMENTO".
  const tk = tokensDe(chave);

  if (ehLegendaDeTotal(chave, tk, "receita liquida")) return { secaoKey: null, ancoraKey: "receita_liquida" };
  if (ehLegendaDeAlgumTotal(chave, tk, ["lucro bruto", "resultado bruto"])) return { secaoKey: null, ancoraKey: "lucro_bruto" };
  if (ehLegendaDeAlgumTotal(chave, tk, ["resultado operacional", "ebit", "lucro operacional"], 4)) {
    return { secaoKey: null, ancoraKey: "resultado_operacional" };
  }
  if (ehLegendaDeAlgumTotal(chave, tk, ["resultado antes dos tributos", "lucro antes dos impostos", "lair"], 3)) {
    return { secaoKey: null, ancoraKey: "resultado_antes_tributos" };
  }
  if (ehLegendaDeAlgumTotal(chave, tk, ["lucro liquido", "prejuizo liquido", "resultado liquido do exercicio"])) {
    return { secaoKey: null, ancoraKey: "lucro_liquido" };
  }
  if (ehSubtotalRedundanteDRE(chave)) return SEM_CLASSIFICACAO;

  // A seção que o DOCUMENTO declarou manda, quando é um bloco reconhecível da
  // DRE. Vem antes do passe por palavra-chave do rótulo (que é adivinhação).
  const declarada = secaoDeclarada(tokensDe(secao || ""), SECAO_DECLARADA_DRE);
  if (declarada) return { secaoKey: declarada, ancoraKey: null };

  if (contemAlgumaFrase(tokens, [
    "receita bruta", "receita operacional bruta", "receita de venda", "receita com venda", "receita de servico",
    "receita de mercadoria", "venda de mercadoria", "venda de produto", "receita de produto",
    "deducao da receita", "deducao", "imposto sobre venda", "tributo sobre venda", "imposto sobre servico",
    "iss sobre servico",
  ])) {
    return { secaoKey: "receita_bruta", ancoraKey: null };
  }
  if (contemAlgumaFrase(tokens, [
    "custo dos produtos", "custo das mercadorias", "custo dos servicos", "custo do servico prestado",
    "custo de venda", "custo operacional", "cpv", "cmv", "custo da venda",
  ])) {
    return { secaoKey: "custos", ancoraKey: null };
  }
  if (contemAlgumaFrase(tokens, [
    "despesas com venda", "despesas comerciais", "despesas administrativas", "despesas gerais",
    "despesa com pessoal", "despesa tributaria", "despesa geral e administrativa",
    "outras despesas operacionais", "outras receitas operacionais", "outras despesas", "outras receitas",
    "depreciacao", "amortizacao", "provisao para devedores duvidosos", "perda estimada", "perda com credito",
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
  const tk = tokensDe(chave); // âncora olha só o rótulo — ver classificarDRE

  // Saldos de caixa: documentos reais frequentemente NÃO usam a palavra
  // "saldo" — escrevem "Caixa e Equivalentes de Caixa no Final/Início do
  // Período". Casa também esse padrão (caixa/equivalente + final|inicio +
  // periodo|exercicio), sem casar a linha do Balanço "Caixa e Equivalentes
  // de Caixa" (que não tem final/inicio/periodo).
  if (ehLegendaDeAlgumTotal(chave, tk, ["saldo final caixa", "caixa saldo final", "caixa final periodo", "caixa final exercicio", "equivalente caixa final"], 3)) {
    return { secaoKey: null, ancoraKey: "saldo_final_caixa" };
  }
  if (ehLegendaDeAlgumTotal(chave, tk, ["saldo inicial caixa", "caixa saldo inicial", "caixa inicio periodo", "caixa inicio exercicio", "equivalente caixa inicio"], 3)) {
    return { secaoKey: null, ancoraKey: "saldo_inicial_caixa" };
  }
  // "REDUÇÃO LÍQUIDA DE CAIXA E EQUIVALENTES DE CAIXA" é legenda de total, mas
  // começa com palavra que o filtro de conta-detalhe não pega — e "Variação em
  // contas a receber" (conta do método indireto) pega. Por isso a lista de
  // frases aqui não inclui "variacao ... caixa" sozinho.
  if (ehLegendaDeAlgumTotal(chave, tk, [
    "aumento caixa", "reducao caixa", "variacao liquida caixa", "diminuicao caixa",
    "acrescimo caixa", "decrescimo caixa", "acrescimo equivalente caixa", "decrescimo equivalente caixa",
  ], 3)) {
    return { secaoKey: null, ancoraKey: "variacao_liquida_caixa" };
  }
  if (ehLegendaDeAlgumTotal(chave, tk, ["caixa liquido atividades operacional", "caixa gerado atividades operacional", "total atividades operacional"], 3)) {
    return { secaoKey: null, ancoraKey: "caixa_operacional" };
  }
  if (ehLegendaDeAlgumTotal(chave, tk, ["caixa liquido investimento", "total atividades investimento"], 3)) {
    return { secaoKey: null, ancoraKey: "caixa_investimento" };
  }
  if (ehLegendaDeAlgumTotal(chave, tk, ["caixa liquido financiamento", "total atividades financiamento"], 3)) {
    return { secaoKey: null, ancoraKey: "caixa_financiamento" };
  }

  // A seção declarada pelo documento manda (ver classificarDRE).
  const declaradaFx = secaoDeclarada(tokensDe(secao || ""), SECAO_DECLARADA_FLUXO);
  if (declaradaFx) return { secaoKey: declaradaFx, ancoraKey: null };
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
    // Método direto (CPC 03) — recebimentos/pagamentos operacionais explícitos:
    "recebimento de cliente", "recebimento de venda", "recebimento de duplicata", "pagamento a fornecedor",
    "pagamento de fornecedor", "pagamento a empregado", "pagamento de salario", "pagamento de imposto",
    "imposto de renda pago", "imposto pago", "juros pago", "juros recebido",
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

// DMPL e DVA são demonstrações inteiras, mas NÃO entram em EstruturaDemonstracao:
// aquele tipo significa "tem template de seções/âncoras e subtotal em fórmula"
// (`secoesDe`/`ancorasDe`/`classificarConta`), e nenhuma das duas tem. A DMPL é
// uma MATRIZ (movimento × componente do PL) e a DVA é a cascata do próprio
// documento — as duas são renderizadas pelo que o documento trouxe, sem template
// imposto. O que elas precisam é do ROTEAMENTO por linha, e é só isso que este
// tipo mais largo carrega: a que demonstração a linha pertence.
export type FamiliaDemonstracao = EstruturaDemonstracao | "dmpl" | "dva";

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
const FAMILIA_POR_SECAO_CANONICA: Record<string, FamiliaDemonstracao> = {
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
  // db/migrations/0024 — a IA passou a poder dizer "esta linha é da DMPL/DVA".
  // Antes não havia como: uma DMPL embutida num PDF de Balanço só tinha
  // "patrimonio_liquido" (que INFLA o PL, porque o saldo de fechamento repete o
  // total) ou "NAO_CLASSIFICAVEL" como destino.
  dmpl: "dmpl",
  dva: "dva",
};

// A qual demonstração (Balanço/DRE/Fluxo de Caixa) uma linha pertence. Usado
// para ROTEAR a linha para a aba certa — separado da classificação da SEÇÃO
// dentro da aba (classificarConta). Prioridade:
//   1) secao_canonica (a IA olhou o conteúdo e disse a qual demonstração é) —
//      "o modelo identifica o que é DRE e o que é Balanço", pedido do dono;
//   2) a linha bate com a estrutura do PRÓPRIO documento (`estruturaDocumento`,
//      quando informado) — evita reroteio por ambiguidade legítima de
//      vocabulário entre demonstrações. Achado em produção (sessão 7 cont.¹⁴):
//      "Lucro Líquido do Exercício" é âncora TANTO da DRE (linha de fechamento)
//      QUANTO do Fluxo de Caixa indireto (ponto de partida da reconciliação) —
//      o mesmo rótulo, dois sentidos legítimos. Um documento que é SÓ uma DRE
//      (sem Fluxo de Caixa embutido) tinha essa linha desviada pra aba Fluxo de
//      Caixa (que vinha antes na ordem de prioridade abaixo), criando uma
//      coluna fantasma lá. Preferir a estrutura do próprio documento quando ela
//      TAMBÉM reconhece a linha resolve a ambiguidade a favor do que é mais
//      provável (o documento já é dessa demonstração);
//   3) fallback determinístico quando a estrutura do documento não reconhece a
//      linha (aí sim é sinal de que ela pertence a OUTRA demonstração — o caso
//      de um PDF que combina várias) — ordem Fluxo de Caixa → DRE → Balanço,
//      porque os sinais de Fluxo/DRE são específicos e o de Balanço casa
//      "caixa" de forma gulosa (senão uma linha de Fluxo cairia no Ativo
//      Circulante, o bug real observado);
//   4) null quando nenhum sinal claro — o chamador mantém a linha na aba do
//      tipo do documento (conservador).
// Não decide nada como fato: a linha continua N1/pendente até o aceite humano;
// isto afeta só EM QUAL ABA a sugestão aparece.
export function classificarDemonstracao(
  secao: string | null,
  chave: string,
  secaoCanonica?: string | null,
  estruturaDocumento?: EstruturaDemonstracao | null,
): FamiliaDemonstracao | null {
  if (secaoCanonica && FAMILIA_POR_SECAO_CANONICA[secaoCanonica]) {
    return FAMILIA_POR_SECAO_CANONICA[secaoCanonica];
  }
  // Documento ANTIGO (extraído antes da 0024, sem `secao_canonica='dmpl'`): a
  // linha de saldo de exercício é reconhecível pela forma e vale mais na aba da
  // DMPL do que em "Contas Não Classificadas", que era o destino dela desde que
  // a guarda `ehLinhaDMPL` foi criada. Só o que a guarda já reconhecia — não é
  // uma detecção nova, é o mesmo sinal com um destino melhor. Vem ANTES da
  // checagem por estrutura do documento de propósito: `classificarBalanco` casa
  // essas linhas pela seção declarada ("Patrimônio Líquido") e as devolveria
  // para o Balanço, que é exatamente o destino errado. A única exceção é a
  // Demonstração de Fluxo de Caixa que escreve o saldo de caixa com data por
  // extenso — se o classificador do Fluxo reconhece a linha como SALDO DE
  // CAIXA, ela é dele, não da DMPL.
  if (ehLinhaDMPL(chave) && !classificarFluxoCaixa(secao, chave).ancoraKey) return "dmpl";
  if (estruturaDocumento) {
    const propria =
      estruturaDocumento === "fluxo_caixa"
        ? classificarFluxoCaixa(secao, chave)
        : estruturaDocumento === "dre"
          ? classificarDRE(secao, chave)
          : classificarBalanco(secao, chave);
    if (propria.secaoKey || propria.ancoraKey) return estruturaDocumento;
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
// somá-las infla o Patrimônio Líquido (bug real visto no export do dono).
// Desde a 0024 a DMPL tem aba própria e o roteamento manda essas linhas para
// lá; esta guarda continua como REDE DE SEGURANÇA para a linha que, por
// qualquer motivo, ainda caia na aba do Balanço (ex.: extração antiga com
// `secao_canonica='patrimonio_liquido'`, que ganha do roteamento por forma).
function ehLinhaDMPL(chave: string): boolean {
  const t = normalizar(chave);
  if (!t.includes("saldo")) return false;
  // Padrão REAL de linha de DMPL: cabeçalho de exercício com DATA COMPLETA
  // ("SALDOS EM 31 DE DEZEMBRO DE 2024" / "Saldo em 31/12/2024"). Exigir a data
  // completa evita descartar contas legítimas como "Disponibilidades - Saldo
  // Final" ou "Saldo de Aplicações em 2024" (achado da auditoria) — antes
  // qualquer "saldo" + ano/final caía como DMPL e sumia da seção.
  return /\d{1,2}\/\d{1,2}\/\d{2,4}/.test(t) || /\d{1,2} de [a-z]+ de (19|20)\d{2}/.test(t);
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
