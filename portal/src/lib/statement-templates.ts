// Modelos padronizados (layout de mercado) para as demonstrações financeiras
// do export Excel (f0/07_output_spec.md, Modo B). Cada template é a estrutura
// PADRÃO usada por analistas no Brasil (CPC/prática de mercado) — o export
// pivota entidade×período nas colunas e usa este template para as linhas.
//
// IMPORTANTE (doutrina, docs/01): nenhuma linha aqui é CALCULADA por soma de
// itens — todo subtotal/total só aparece se o próprio documento extraído
// trouxer aquela linha explicitamente (ex.: "Total do Ativo Circulante" como
// linha do PDF). Não fazemos contas novas — só recolocamos o que já foi
// extraído no lugar certo do layout padrão (mesmo princípio de
// `fn_valor_conceito`, db/migrations/0009: casamento determinístico por
// termos, nunca um cálculo/LLM decidindo o número).

import type { CampoExtraido } from "./types";

export type TemplateRowKind = "header" | "item" | "subtotal" | "total";

export interface MatchPattern {
  include: string[];
  exclude?: string[];
}

export interface TemplateRow {
  label: string;
  kind: TemplateRowKind;
  level: number; // indentação visual (0 = sem indent)
  patterns?: MatchPattern[]; // ausente só em kind:"header" (linha divisória, sem valor)
}

function normalizar(s: string): string {
  return s
    .normalize("NFD")
    .replace(/[̀-ͯ]/g, "")
    .toLowerCase()
    .replace(/\s+/g, " ")
    .trim();
}

// Acha, dentro de um conjunto de campos extraídos (já restrito a UMA
// coluna/contexto entidade×período), o que casa com QUALQUER um dos padrões
// (cada padrão = todos os termos de `include` presentes E nenhum de
// `exclude`). Em empate, prefere maior confiança e chave mais curta (mais
// específica) — mesmo critério de `fn_valor_conceito`.
export function casarPadrao(campos: CampoExtraido[], patterns: MatchPattern[]): CampoExtraido | null {
  for (const pattern of patterns) {
    const candidatos = campos.filter((c) => {
      if (c.valor_num == null) return false;
      const chaveNorm = normalizar(c.chave);
      const bateInclui = pattern.include.every((termo) => chaveNorm.includes(normalizar(termo)));
      const bateExclui = (pattern.exclude ?? []).some((termo) => chaveNorm.includes(normalizar(termo)));
      return bateInclui && !bateExclui;
    });
    if (candidatos.length > 0) {
      candidatos.sort((a, b) => (b.confianca ?? 0) - (a.confianca ?? 0) || a.chave.length - b.chave.length);
      return candidatos[0];
    }
  }
  return null;
}

export { normalizar };

// ----- Balanço Patrimonial (estrutura padrão CPC/mercado) -------------------
export const BALANCO_TEMPLATE: TemplateRow[] = [
  { label: "ATIVO", kind: "header", level: 0 },
  { label: "Ativo Circulante", kind: "header", level: 1 },
  { label: "Caixa e Equivalentes de Caixa", kind: "item", level: 2, patterns: [
    { include: ["caixa", "equivalente"] }, { include: ["disponibilidades"] }, { include: ["caixa", "banco"] },
  ] },
  { label: "Aplicações Financeiras", kind: "item", level: 2, patterns: [
    { include: ["aplicacoes financeiras"] }, { include: ["titulos e valores mobiliarios"] },
  ] },
  { label: "Contas a Receber de Clientes", kind: "item", level: 2, patterns: [
    { include: ["contas a receber"] }, { include: ["clientes"], exclude: ["fornecedores"] }, { include: ["duplicatas a receber"] },
  ] },
  { label: "Estoques", kind: "item", level: 2, patterns: [{ include: ["estoque"] }, { include: ["mercadorias"] }] },
  { label: "Impostos a Recuperar", kind: "item", level: 2, patterns: [
    { include: ["impostos a recuperar"] }, { include: ["tributos a recuperar"] },
  ] },
  { label: "Despesas Antecipadas", kind: "item", level: 2, patterns: [{ include: ["despesas antecipadas"] }] },
  { label: "Outros Ativos Circulantes", kind: "item", level: 2, patterns: [
    { include: ["outros ativos circulantes"] }, { include: ["outros creditos"], exclude: ["nao circulante", "não circulante"] },
  ] },
  { label: "Total do Ativo Circulante", kind: "subtotal", level: 1, patterns: [
    { include: ["total", "ativo", "circulante"], exclude: ["nao circulante", "não circulante"] },
  ] },
  { label: "Ativo Não Circulante", kind: "header", level: 1 },
  { label: "Realizável a Longo Prazo", kind: "item", level: 2, patterns: [{ include: ["realizavel a longo prazo"] }] },
  { label: "Investimentos", kind: "item", level: 2, patterns: [{ include: ["investimentos"], exclude: ["financeiros"] }] },
  { label: "Imobilizado", kind: "item", level: 2, patterns: [{ include: ["imobilizado"] }] },
  { label: "Intangível", kind: "item", level: 2, patterns: [{ include: ["intangivel"] }] },
  { label: "Total do Ativo Não Circulante", kind: "subtotal", level: 1, patterns: [
    { include: ["total", "ativo", "nao circulante"] }, { include: ["total", "ativo", "não circulante"] },
  ] },
  { label: "TOTAL DO ATIVO", kind: "total", level: 0, patterns: [{ include: ["total", "ativo"], exclude: ["circulante"] }] },
  { label: "PASSIVO E PATRIMÔNIO LÍQUIDO", kind: "header", level: 0 },
  { label: "Passivo Circulante", kind: "header", level: 1 },
  { label: "Fornecedores", kind: "item", level: 2, patterns: [{ include: ["fornecedores"] }] },
  { label: "Empréstimos e Financiamentos (Curto Prazo)", kind: "item", level: 2, patterns: [
    { include: ["emprestimo"], exclude: ["longo prazo", "nao circulante", "não circulante"] },
    { include: ["financiamento"], exclude: ["longo prazo", "nao circulante", "não circulante"] },
  ] },
  { label: "Obrigações Trabalhistas e Sociais", kind: "item", level: 2, patterns: [
    { include: ["obrigacoes trabalhistas"] }, { include: ["salarios a pagar"] }, { include: ["folha de pagamento"] },
  ] },
  { label: "Obrigações Tributárias", kind: "item", level: 2, patterns: [
    { include: ["obrigacoes tributarias"] }, { include: ["impostos a pagar"] }, { include: ["tributos a pagar"] },
  ] },
  { label: "Outros Passivos Circulantes", kind: "item", level: 2, patterns: [
    { include: ["outros passivos circulantes"] }, { include: ["outras contas a pagar"] },
  ] },
  { label: "Total do Passivo Circulante", kind: "subtotal", level: 1, patterns: [
    { include: ["total", "passivo", "circulante"], exclude: ["nao circulante", "não circulante", "patrimonio"] },
  ] },
  { label: "Passivo Não Circulante", kind: "header", level: 1 },
  { label: "Empréstimos e Financiamentos (Longo Prazo)", kind: "item", level: 2, patterns: [
    { include: ["emprestimo", "longo prazo"] }, { include: ["financiamento", "longo prazo"] },
    { include: ["emprestimo", "nao circulante"] }, { include: ["financiamento", "nao circulante"] },
  ] },
  { label: "Outras Obrigações de Longo Prazo", kind: "item", level: 2, patterns: [
    { include: ["outras obrigacoes"], exclude: ["circulante"] }, { include: ["provisoes"] },
  ] },
  { label: "Total do Passivo Não Circulante", kind: "subtotal", level: 1, patterns: [
    { include: ["total", "passivo", "nao circulante"] }, { include: ["total", "passivo", "não circulante"] },
  ] },
  { label: "Patrimônio Líquido", kind: "header", level: 1 },
  { label: "Capital Social", kind: "item", level: 2, patterns: [{ include: ["capital social"] }] },
  { label: "Reservas de Capital", kind: "item", level: 2, patterns: [{ include: ["reserva", "capital"] }] },
  { label: "Reservas de Lucros", kind: "item", level: 2, patterns: [{ include: ["reserva", "lucro"] }] },
  { label: "Lucros/Prejuízos Acumulados", kind: "item", level: 2, patterns: [
    { include: ["lucros acumulados"] }, { include: ["prejuizos acumulados"] }, { include: ["lucros ou prejuizos acumulados"] },
  ] },
  { label: "Total do Patrimônio Líquido", kind: "subtotal", level: 1, patterns: [
    { include: ["total", "patrimonio liquido"], exclude: ["passivo"] },
  ] },
  { label: "TOTAL DO PASSIVO E PATRIMÔNIO LÍQUIDO", kind: "total", level: 0, patterns: [
    { include: ["total", "passivo", "patrimonio"] },
  ] },
];

// ----- DRE (estrutura em cascata, padrão CPC/mercado) -----------------------
export const DRE_TEMPLATE: TemplateRow[] = [
  { label: "Receita Bruta de Vendas e/ou Serviços", kind: "item", level: 0, patterns: [
    { include: ["receita bruta"] }, { include: ["receita operacional bruta"] },
  ] },
  { label: "Deduções da Receita Bruta", kind: "item", level: 0, patterns: [{ include: ["deducoes"] }] },
  { label: "Receita Líquida", kind: "subtotal", level: 0, patterns: [{ include: ["receita liquida"] }] },
  { label: "Custo dos Produtos/Mercadorias/Serviços Vendidos", kind: "item", level: 0, patterns: [
    { include: ["custo dos produtos"] }, { include: ["custo das mercadorias"] }, { include: ["custo dos servicos"] },
    { include: ["cpv"] }, { include: ["cmv"] },
  ] },
  { label: "Lucro Bruto", kind: "subtotal", level: 0, patterns: [{ include: ["lucro bruto"] }, { include: ["resultado bruto"] }] },
  { label: "Despesas com Vendas", kind: "item", level: 0, patterns: [
    { include: ["despesas com vendas"] }, { include: ["despesas comerciais"] },
  ] },
  { label: "Despesas Administrativas", kind: "item", level: 0, patterns: [
    { include: ["despesas administrativas"] }, { include: ["despesas gerais e administrativas"] },
  ] },
  { label: "Outras Receitas/Despesas Operacionais", kind: "item", level: 0, patterns: [
    { include: ["outras receitas operacionais"] }, { include: ["outras despesas operacionais"] },
  ] },
  { label: "Resultado Operacional (EBIT)", kind: "subtotal", level: 0, patterns: [
    { include: ["resultado operacional"] }, { include: ["ebit"] }, { include: ["lucro operacional"] },
  ] },
  { label: "Resultado Financeiro Líquido", kind: "item", level: 0, patterns: [
    { include: ["resultado financeiro"] }, { include: ["despesas financeiras"], exclude: ["receitas"] },
    { include: ["receitas financeiras"], exclude: ["despesas"] },
  ] },
  { label: "Resultado Antes dos Tributos", kind: "subtotal", level: 0, patterns: [
    { include: ["resultado antes", "tributos"] }, { include: ["lucro antes", "impostos"] }, { include: ["lair"] },
  ] },
  { label: "Imposto de Renda e Contribuição Social", kind: "item", level: 0, patterns: [
    { include: ["imposto de renda"] }, { include: ["ir e csll"] }, { include: ["irpj"] },
  ] },
  { label: "Lucro/Prejuízo Líquido do Exercício", kind: "total", level: 0, patterns: [
    { include: ["lucro liquido"] }, { include: ["prejuizo liquido"] }, { include: ["resultado liquido do exercicio"] },
  ] },
];

// ----- Fluxo de Caixa (método indireto, padrão CPC 03) ----------------------
export const FLUXO_CAIXA_TEMPLATE: TemplateRow[] = [
  { label: "Atividades Operacionais", kind: "header", level: 0 },
  { label: "Lucro Líquido do Exercício", kind: "item", level: 1, patterns: [{ include: ["lucro liquido"] }] },
  { label: "Depreciação e Amortização", kind: "item", level: 1, patterns: [
    { include: ["depreciacao"] }, { include: ["amortizacao"], exclude: ["emprestimo", "financiamento"] },
  ] },
  { label: "Variação em Contas a Receber", kind: "item", level: 1, patterns: [{ include: ["variacao", "contas a receber"] }] },
  { label: "Variação em Estoques", kind: "item", level: 1, patterns: [{ include: ["variacao", "estoque"] }] },
  { label: "Variação em Fornecedores", kind: "item", level: 1, patterns: [{ include: ["variacao", "fornecedores"] }] },
  { label: "Outras Variações no Capital de Giro", kind: "item", level: 1, patterns: [
    { include: ["capital de giro"] }, { include: ["outras variacoes"] },
  ] },
  { label: "Caixa Líquido das Atividades Operacionais", kind: "subtotal", level: 0, patterns: [
    { include: ["caixa liquido", "atividades operacionais"] }, { include: ["caixa gerado", "atividades operacionais"] },
    { include: ["total", "atividades operacionais"] },
  ] },
  { label: "Atividades de Investimento", kind: "header", level: 0 },
  { label: "Aquisição de Imobilizado", kind: "item", level: 1, patterns: [
    { include: ["aquisicao", "imobilizado"] }, { include: ["compra", "imobilizado"] },
  ] },
  { label: "Aquisição de Intangível", kind: "item", level: 1, patterns: [{ include: ["aquisicao", "intangivel"] }] },
  { label: "Recebimento pela Venda de Ativos", kind: "item", level: 1, patterns: [
    { include: ["venda de ativo"] }, { include: ["alienacao de ativo"] },
  ] },
  { label: "Caixa Líquido das Atividades de Investimento", kind: "subtotal", level: 0, patterns: [
    { include: ["caixa liquido", "investimento"] }, { include: ["total", "atividades de investimento"] },
  ] },
  { label: "Atividades de Financiamento", kind: "header", level: 0 },
  { label: "Captação de Empréstimos", kind: "item", level: 1, patterns: [
    { include: ["captacao", "emprestimo"] }, { include: ["ingresso", "emprestimo"] },
  ] },
  { label: "Pagamento de Empréstimos", kind: "item", level: 1, patterns: [
    { include: ["pagamento", "emprestimo"] }, { include: ["amortizacao", "emprestimo"] },
  ] },
  { label: "Aportes/Distribuições de Capital", kind: "item", level: 1, patterns: [
    { include: ["aporte de capital"] }, { include: ["distribuicao de dividendos"] }, { include: ["dividendos pagos"] },
  ] },
  { label: "Caixa Líquido das Atividades de Financiamento", kind: "subtotal", level: 0, patterns: [
    { include: ["caixa liquido", "financiamento"] }, { include: ["total", "atividades de financiamento"] },
  ] },
  { label: "Aumento (Redução) Líquido de Caixa", kind: "subtotal", level: 0, patterns: [
    { include: ["aumento", "caixa"] }, { include: ["reducao", "caixa"] }, { include: ["variacao liquida", "caixa"] },
  ] },
  { label: "Saldo Inicial de Caixa", kind: "item", level: 0, patterns: [{ include: ["saldo inicial", "caixa"] }] },
  { label: "Saldo Final de Caixa", kind: "total", level: 0, patterns: [{ include: ["saldo final", "caixa"] }] },
];

// tipo_taxonomia → template padronizado. COMBINADO reaproveita o layout do
// Balanço (o caso mais comum de "demonstrações combinadas" nos mandatos da
// Oria é o balanço consolidado do grupo — f0/03). Tipos fora deste mapa
// (Faturamento, Dívida, Fluxo Projetado, etc.) usam a listagem simples — já
// são, por natureza, uma série/tabela, não uma demonstração de 3 blocos.
export const TEMPLATE_POR_TIPO: Record<string, TemplateRow[]> = {
  BALANCO: BALANCO_TEMPLATE,
  DRE: DRE_TEMPLATE,
  FLUXO_CAIXA: FLUXO_CAIXA_TEMPLATE,
  COMBINADO: BALANCO_TEMPLATE,
};
