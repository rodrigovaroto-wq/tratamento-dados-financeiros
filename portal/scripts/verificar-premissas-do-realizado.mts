/**
 * Verificação das premissas sugeridas a partir do realizado
 * (roda com `./node_modules/.bin/tsx scripts/verificar-premissas-do-realizado.mts`).
 *
 * O QUE ESTA SUÍTE PROTEGE. A tela de Modelagem passou a sugerir oito premissas
 * lidas do próprio balanço e da própria DRE do caso. O analista aceita com um
 * clique, e a partir daí aquele número dirige a projeção inteira — receita
 * projetada, saldo de giro, caixa, necessidade de recursos. Um erro aqui não tem
 * sintoma: ele produz um modelo que parece calibrado pelo histórico e não é.
 *
 * Os invariantes, em ordem de quanto custa perdê-los:
 *
 *  1. ZERO NÃO É RESPOSTA. Sem a conta que serve de numerador, ou sem a base que
 *     serve de denominador, a sugestão NÃO sai — sai o motivo. Zero dias de
 *     recebimento não é "não sei": é a afirmação de que a empresa vende à vista.
 *  2. A BASE DE CADA RAZÃO É A QUE O MODELO APLICA. Fornecedor gira contra
 *     CUSTOS; cliente e estoque giram contra RECEITA LÍQUIDA. Medir num
 *     denominador e aplicar noutro é o defeito que o próprio modelo denuncia no
 *     Modelo Base, e ele infla o passivo projetado em ~1,27×. Se este assert cair,
 *     o dia sugerido deixa de reproduzir o saldo de onde saiu.
 *  3. SUBTOTAL NÃO SOMA. "Total do Ativo Circulante" ao lado das contas dele
 *     conta o circulante duas vezes, e a razão sai pela metade do que deveria.
 *  4. MAGNITUDE, NÃO SINAL. O documento publica despesa ora positiva, ora
 *     negativa. Custo de 300 com sinal negativo é custo de 300.
 *  5. RECEITA LÍQUIDA É BRUTA MENOS DEDUÇÕES, e não a linha impressa: em metade
 *     dos documentos ela não existe, e quando existe é subtotal.
 *  6. NUMERADOR ZERO COM CONTA PRESENTE PASSA. Uma empresa pode de fato fechar o
 *     exercício sem estoque. O que não pode é inventar a base.
 */

import { sugerirDoRealizado, type LinhaRealizada } from "../src/lib/premissas-do-realizado.ts";

let falhas = 0;
let passou = 0;

function ok(cond: boolean, nome: string, detalhe?: string) {
  if (cond) {
    passou += 1;
    console.log(`  ok    ${nome}`);
  } else {
    falhas += 1;
    console.error(`  FALHOU: ${nome}${detalhe ? ` — ${detalhe}` : ""}`);
  }
}

function perto(a: number | null, b: number, tol = 0.0001): boolean {
  return a !== null && Math.abs(a - b) <= tol;
}

const conta = (
  secao: string, chave: string, valor: number,
  papel: LinhaRealizada["papel"] = "conta",
): LinhaRealizada => ({
  secao_canonica: secao, chave, rotulo_norm: chave.toLowerCase(), papel,
  valor_ultimo: valor, documentos: null,
});

const achar = (lista: ReturnType<typeof sugerirDoRealizado>, codigo: string) =>
  lista.find((p) => p.codigo === codigo)!;

// -----------------------------------------------------------------------------
// UM CASO COMPLETO, com números redondos escolhidos para a conta ser conferível
// de cabeça por quem ler o assert.
//
//   receita bruta 1.200, deduções 200        → receita líquida 1.000
//   custos 600, SG&A 150, financeiro −50, tributos 40
//   clientes 200, estoques 100, fornecedores 150
//   dívida 400 (CP 100 + LP 300), passivo total 1.000
// -----------------------------------------------------------------------------
const casoCompleto: LinhaRealizada[] = [
  conta("receita_bruta", "Receita bruta de vendas", 1200),
  conta("receita_bruta", "Deduções da receita bruta", 200),
  conta("custos", "Custo dos produtos vendidos", 600),
  conta("despesas_operacionais", "Despesas administrativas", 150),
  conta("resultado_financeiro", "Despesas financeiras", -50),
  conta("impostos_lucro", "IRPJ e CSLL", 40),
  conta("ativo_circulante", "Clientes", 200),
  conta("ativo_circulante", "Estoques", 100),
  conta("ativo_circulante", "Caixa e equivalentes", 80),
  conta("passivo_circulante", "Fornecedores", 150),
  conta("passivo_circulante", "Empréstimos e financiamentos", 100),
  conta("passivo_nao_circulante", "Financiamentos de longo prazo", 300),
  conta("passivo_circulante", "Salários a pagar", 50),
  conta("passivo_nao_circulante", "Provisão para contingências", 400),
];

console.log("1. o caso completo responde as oito, e cada conta bate");
{
  const s = sugerirDoRealizado(casoCompleto);
  ok(s.length === 8, "são oito premissas", `veio ${s.length}`);

  // custos 600 ÷ RL 1000
  ok(perto(achar(s, "CUSTO_VARIAVEL").valor, 0.6), "CUSTO_VARIAVEL = 0,60",
     String(achar(s, "CUSTO_VARIAVEL").valor));
  // SG&A 150 ÷ RL 1000
  ok(perto(achar(s, "SGA_PCT").valor, 0.15), "SGA_PCT = 0,15", String(achar(s, "SGA_PCT").valor));
  // clientes 200 ÷ RL 1000 × 360
  ok(perto(achar(s, "PMR").valor, 72), "PMR = 72 dias", String(achar(s, "PMR").valor));
  // estoques 100 ÷ RL 1000 × 360
  ok(perto(achar(s, "PME").valor, 36), "PME = 36 dias", String(achar(s, "PME").valor));
  // fornecedores 150 ÷ CUSTOS 600 × 360
  ok(perto(achar(s, "PMP").valor, 90), "PMP = 90 dias", String(achar(s, "PMP").valor));
  // tributos 40 ÷ LAIR (1000 − 600 − 150 − 50 = 200)
  ok(perto(achar(s, "ALIQUOTA").valor, 0.2), "ALIQUOTA = 0,20", String(achar(s, "ALIQUOTA").valor));
  // dívida 400 ÷ passivo total 1000
  ok(perto(achar(s, "PARCELA_ONEROSA").valor, 0.4), "PARCELA_ONEROSA = 0,40",
     String(achar(s, "PARCELA_ONEROSA").valor));
  // |financeiro| 50 ÷ dívida 400
  ok(perto(achar(s, "TAXA_DIVIDA").valor, 0.125), "TAXA_DIVIDA = 0,125",
     String(achar(s, "TAXA_DIVIDA").valor));
}

console.log("2. a base de cada giro é a que o modelo aplica");
{
  // Se o PMP fosse medido contra receita líquida (o defeito do Modelo Base), ele
  // daria 54 dias em vez de 90. A diferença é a razão receita/custo, 1,67×.
  const s = sugerirDoRealizado(casoCompleto);
  ok(achar(s, "PMP").conta.includes("custos"), "PMP declara custos como base",
     achar(s, "PMP").conta);
  ok(!perto(achar(s, "PMP").valor, 54), "e NÃO usa receita líquida, que daria 54");
  ok(achar(s, "PME").conta.includes("receita líquida"),
     "PME declara receita líquida como base, que é a que o Working Capital aplica ao estoque",
     achar(s, "PME").conta);
}

console.log("3. zero não é resposta");
{
  const semClientes = casoCompleto.filter((l) => l.chave !== "Clientes");
  const s = sugerirDoRealizado(semClientes);
  const pmr = achar(s, "PMR");
  ok(pmr.valor === null, "sem conta de clientes, o PMR não sai", String(pmr.valor));
  ok(pmr.porQueNao !== null && pmr.porQueNao.includes("clientes"),
     "e o motivo nomeia a conta que falta", String(pmr.porQueNao));

  const semReceita = casoCompleto.filter((l) => l.secao_canonica !== "receita_bruta");
  const s2 = sugerirDoRealizado(semReceita);
  ok(achar(s2, "CUSTO_VARIAVEL").valor === null && achar(s2, "PMR").valor === null,
     "sem receita, nenhuma razão que a usa como base sai");
  ok(achar(s2, "PMP").valor !== null,
     "mas o PMP sai, porque a base dele é custo e o custo está lá");
}

console.log("4. numerador zero com conta presente PASSA");
{
  const semEstoqueNoFecho = casoCompleto.map((l) =>
    l.chave === "Estoques" ? { ...l, valor_ultimo: 0 } : l);
  const s = sugerirDoRealizado(semEstoqueNoFecho);
  ok(achar(s, "PME").valor === 0,
     "estoque zerado no fechamento é 0 dias, e isso é um fato do documento");
  ok(achar(s, "PME").porQueNao === null, "sem motivo de recusa, porque não houve recusa");
}

console.log("5. subtotal não entra na soma");
{
  const comSubtotal = [
    ...casoCompleto,
    conta("ativo_circulante", "Total do Ativo Circulante", 380, "subtotal"),
    conta("custos", "Total dos custos", 600, "subtotal"),
  ];
  const s = sugerirDoRealizado(comSubtotal);
  ok(perto(achar(s, "CUSTO_VARIAVEL").valor, 0.6),
     "o subtotal de custos não dobra o custo", String(achar(s, "CUSTO_VARIAVEL").valor));
  ok(perto(achar(s, "PMR").valor, 72),
     "e o subtotal do circulante não vira cliente", String(achar(s, "PMR").valor));
}

console.log("6. magnitude, não sinal");
{
  const despesaNegativa = casoCompleto.map((l) =>
    l.secao_canonica === "custos" || l.secao_canonica === "despesas_operacionais"
      ? { ...l, valor_ultimo: -Math.abs(l.valor_ultimo) } : l);
  const s = sugerirDoRealizado(despesaNegativa);
  ok(perto(achar(s, "CUSTO_VARIAVEL").valor, 0.6),
     "custo publicado negativo dá a mesma razão", String(achar(s, "CUSTO_VARIAVEL").valor));
  ok(perto(achar(s, "SGA_PCT").valor, 0.15), "SG&A idem", String(achar(s, "SGA_PCT").valor));
}

console.log("7. receita líquida é bruta menos deduções");
{
  const semDeducao = casoCompleto.filter((l) => !/Deduções/.test(l.chave));
  const s = sugerirDoRealizado(semDeducao);
  // Sem a dedução de 200, a base sobe de 1.000 para 1.200 e o custo cai para 0,50.
  ok(perto(achar(s, "CUSTO_VARIAVEL").valor, 0.5),
     "tirar a dedução muda a base, e a razão acompanha",
     String(achar(s, "CUSTO_VARIAVEL").valor));
}

console.log("8. o caso vazio não inventa nada");
{
  const s = sugerirDoRealizado([]);
  ok(s.length === 8, "as oito continuam listadas");
  ok(s.every((p) => p.valor === null && p.porQueNao !== null),
     "e todas as oito dizem por que não saíram");
}

console.log(`\n${passou} asserts passaram, ${falhas} falharam`);
if (falhas > 0) process.exit(1);
console.log("PREMISSAS DO REALIZADO OK — zero não é resposta, a base é a do modelo, subtotal não soma");
