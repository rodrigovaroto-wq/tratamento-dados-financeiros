/**
 * Verificação da planilha de transcrição humana assistida
 * (roda com `./node_modules/.bin/tsx scripts/verificar-transcricao.mts`).
 *
 * O QUE ESTA SUÍTE PROTEGE. A planilha da 0129 é a saída do gate de captura
 * (fechamento #2 do `Arquitetura do Sistema/1 Visão e Doutrina/01`): quando o arquivo não se lê e o cliente não tem
 * outra via, uma pessoa digita o que está no papel. As linhas digitadas entram no
 * banco JÁ ACEITAS, com o nome de quem digitou, e SEM passar por guarda nenhuma —
 * as guardas de extração existem para pegar alucinação de modelo e não têm o que
 * fazer com o que um humano escreveu. O que substitui a guarda é a autoria.
 *
 * Isso muda o que um defeito aqui custa. Um erro de leitura desta planilha não
 * gera pendência nem divergência: gera um número errado, aceito, com autor — e
 * ninguém volta a desconfiar de um número que tem dono. Daí esta suíte, e daí ela
 * ser round-trip de verdade (gerar → escrever .xlsx → ler de volta), e não teste
 * de unidade da função de parse: o defeito que interessa é a coluna que muda de
 * lugar em UMA das duas metades.
 *
 * Os invariantes:
 *
 *  1. IDA E VOLTA PELAS COLUNAS. O que foi escrito na coluna de unidade volta em
 *     `unidade`, o de período em `periodo_coluna`, e assim por diante. É o teste
 *     que pega a coluna deslocada — cujo sintoma não é erro, é uma transcrição
 *     importada com o valor no campo da unidade.
 *  2. NÚMERO EM PT-BR. "1.234,56" vale 1234,56 e não 1,234 — três ordens de
 *     grandeza, e plausível o bastante para passar por revisão. `parseFloat` puro
 *     erra este caso, que é o formato de quem cola de um PDF brasileiro.
 *  3. PARÊNTESES SÃO NEGATIVO. Convenção contábil: "(1.234)" é −1234.
 *  4. LINHA SEM VALOR É IGNORADA. A planilha traz 60 linhas livres em branco de
 *     propósito; se sobra em branco virasse linha, cada transcrição gravaria
 *     dezenas de linhas afirmando que o documento diz zero.
 *  5. RÓTULO SEM VALOR TAMBÉM SAI. As linhas exigidas vêm pré-preenchidas com
 *     rótulo — importá-las sem valor seria inventar que o documento afirma zero
 *     justamente nas linhas que o Portão 1 cobra.
 *  6. VALOR NÃO-NUMÉRICO NÃO É DESCARTADO. "vide nota 12" é o que o documento diz.
 *  7. A CONFERÊNCIA DO DOCUMENTO RECUSA. Planilha gerada para outro documento é
 *     recusada, e a mensagem nomeia os dois ids. Sem esta guarda, a transcrição do
 *     balanço de uma empresa entraria no da outra — aceita, com autor.
 *  8. PLANILHA SEM O IDENTIFICADOR RECUSA. Arquivo montado à mão não tem como ser
 *     conferido, e "não pude conferir" não é motivo para gravar.
 *  9. PLANILHA VAZIA RECUSA, em vez de gravar uma versão sem número nenhum — que é
 *     o pior dos dois estados: parece transcrito e não tem dado.
 * 10. A CÉLULA DE ENTRADA É MARCADA. Areia = digite aqui, a mesma gramática do
 *     arquivo entregue. É a única indicação visual de ONDE digitar.
 */
import ExcelJS from "exceljs";
import {
  montarPlanilhaTranscricao, lerPlanilhaTranscricao, LAYOUT_TRANSCRICAO,
  type LinhaExigidaParaTranscrever,
} from "../src/lib/transcricao.ts";
import { ORIA } from "../src/lib/oria-marca.ts";

let ok = 0;
const falhas: string[] = [];
function checar(cond: boolean, desc: string, detalhe = "") {
  if (cond) ok++;
  else falhas.push(`${desc}${detalhe ? ` — ${detalhe}` : ""}`);
}

const DOC = "11111111-1111-1111-1111-111111111111";
const OUTRO_DOC = "22222222-2222-2222-2222-222222222222";

const EXIGIDAS: LinhaExigidaParaTranscrever[] = [
  {
    conceito: "ativo_total", rotulo: "Ativo Total", descricao: "Soma do ativo.",
    secao_canonica: "ativo", checagem: "presenca", severidade: "bloqueante",
  },
  {
    conceito: "passivo_total", rotulo: "Passivo Total", descricao: "Soma do passivo.",
    secao_canonica: "passivo", checagem: "presenca", severidade: "bloqueante",
  },
  {
    conceito: "patrimonio_liquido", rotulo: "Patrimônio Líquido", descricao: "PL.",
    secao_canonica: "patrimonio_liquido", checagem: "presenca", severidade: "importante",
  },
];

const { ABA, LINHA_CABECALHO, CELULA_DOC_ID, COLUNAS } = LAYOUT_TRANSCRICAO;
const col = (chave: string) => COLUNAS.findIndex((c) => c.chave === chave) + 1;

function montar() {
  return montarPlanilhaTranscricao({
    documentoId: DOC,
    nomeArquivo: "balanco-2024.pdf",
    tipoTaxonomia: "balanco_patrimonial",
    entidade: "Alfa Indústria Ltda",
    periodo: "anual 2024",
    exigidas: EXIGIDAS,
  });
}

/** Escreve o workbook e o lê de volta pela outra metade do contrato. */
async function idaEVolta(wb: ExcelJS.Workbook, esperado = DOC) {
  const buf = await wb.xlsx.writeBuffer();
  return lerPlanilhaTranscricao(buf as ArrayBuffer, esperado);
}

// ---- a planilha gerada tem a forma que a leitura espera ----------------------
{
  const wb = montar();
  const ws = wb.getWorksheet(ABA)!;
  checar(!!ws, "(0) a aba de transcrição existe com o nome que a leitura procura");
  checar(String(ws.getCell(CELULA_DOC_ID).value ?? "") === DOC,
    "(0) o id do documento está na célula que a leitura confere", CELULA_DOC_ID);

  // As linhas exigidas vêm pré-listadas, com rótulo e conceito.
  const rotulos: string[] = [];
  for (let r = LINHA_CABECALHO + 1; r <= LINHA_CABECALHO + EXIGIDAS.length; r++) {
    rotulos.push(String(ws.getRow(r).getCell(col("rotulo")).value ?? ""));
  }
  checar(EXIGIDAS.every((e) => rotulos.includes(e.rotulo)),
    "(0) as linhas que o Portão 1 cobra vêm pré-listadas", rotulos.join(" | "));
  checar(
    String(ws.getRow(LINHA_CABECALHO + 1).getCell(col("conceito")).value ?? "") === "ativo_total",
    "(0) …com o conceito ao lado, para a importação não depender do rótulo digitado");

  // 10. A célula de VALOR é marcada como entrada (areia) — nas exigidas e nas livres.
  const fillDe = (r: number) => {
    const f = ws.getRow(r).getCell(col("valor")).fill as
      | { fgColor?: { argb?: string } } | undefined;
    return f?.fgColor?.argb;
  };
  checar(fillDe(LINHA_CABECALHO + 1) === ORIA.entrada,
    "(10) a célula de valor da linha exigida é marcada como entrada", String(fillDe(LINHA_CABECALHO + 1)));
  checar(fillDe(LINHA_CABECALHO + EXIGIDAS.length + 5) === ORIA.entrada,
    "(10) …e as linhas livres também, senão não se sabe onde digitar");
}

// ---- 1/2/3/6: ida e volta com os formatos que aparecem na mesa ---------------
{
  const wb = montar();
  const ws = wb.getWorksheet(ABA)!;

  // Linha exigida 1: número de verdade (célula numérica do Excel).
  const r1 = ws.getRow(LINHA_CABECALHO + 1);
  r1.getCell(col("valor")).value = 67878.5;
  r1.getCell(col("unidade")).value = "R$ mil";
  r1.getCell(col("periodo")).value = "2024";
  r1.getCell(col("entidade")).value = "Alfa";
  r1.getCell(col("pagina")).value = 3;

  // Linha exigida 2: colado de PDF — TEXTO em pt-BR, com milhar e decimal.
  const r2 = ws.getRow(LINHA_CABECALHO + 2);
  r2.getCell(col("valor")).value = "1.234,56";

  // Linha exigida 3: negativo pela convenção contábil.
  const r3 = ws.getRow(LINHA_CABECALHO + 3);
  r3.getCell(col("valor")).value = "(1.234)";

  // Linha livre: valor que não é número.
  const rl = ws.getRow(LINHA_CABECALHO + EXIGIDAS.length + 1);
  rl.getCell(col("rotulo")).value = "Provisão para contingências";
  rl.getCell(col("valor")).value = "vide nota 12";

  // Linha livre com moeda escrita junto — o analista digita como está no papel.
  const rm = ws.getRow(LINHA_CABECALHO + EXIGIDAS.length + 2);
  rm.getCell(col("rotulo")).value = "Caixa e equivalentes";
  rm.getCell(col("valor")).value = "R$ 2.000,00";

  // Linha livre SÓ COM RÓTULO — não deve entrar (invariante 5).
  ws.getRow(LINHA_CABECALHO + EXIGIDAS.length + 3).getCell(col("rotulo")).value =
    "Rótulo digitado e valor esquecido";

  const res = await idaEVolta(wb);
  checar(res.ok, "(1) a planilha preenchida é lida", res.ok ? "" : res.erro);
  if (res.ok) {
    const porChave = new Map(res.linhas.map((l) => [l.chave, l]));

    // 4/5: 60 linhas livres em branco + 1 linha só com rótulo não viraram linha.
    checar(res.linhas.length === 5,
      "(4/5) só as linhas COM valor entram — sobra em branco e rótulo sem valor saem",
      `${res.linhas.length} linha(s): ${res.linhas.map((l) => l.chave).join(" | ")}`);

    // 1: as colunas voltam nos campos certos.
    const a = porChave.get("Ativo Total");
    checar(Number(a?.valor_num) === 67878.5, "(2) número do Excel volta inteiro", String(a?.valor_num));
    checar(a?.unidade === "R$ mil", "(1) a unidade volta em `unidade`", String(a?.unidade));
    checar(a?.periodo_coluna === "2024", "(1) o período volta em `periodo_coluna`", String(a?.periodo_coluna));
    checar(a?.entidade_coluna === "Alfa", "(1) a entidade volta em `entidade_coluna`", String(a?.entidade_coluna));
    checar(a?.origem_pagina === "3", "(1) a página volta em `origem_pagina`", String(a?.origem_pagina));
    checar(a?.secao_canonica === "ativo",
      "(1) a seção canônica pré-preenchida volta em `secao_canonica`", String(a?.secao_canonica));

    // 2: O ASSERT QUE PEGA `parseFloat`. Com leitura ingênua isto vale 1.234.
    const p = porChave.get("Passivo Total");
    checar(Number(p?.valor_num) === 1234.56,
      "(2) \"1.234,56\" vale 1234,56 — não 1,234, que é o que parseFloat devolveria",
      String(p?.valor_num));

    // 3: parênteses = negativo.
    const pl = porChave.get("Patrimônio Líquido");
    checar(Number(pl?.valor_num) === -1234,
      "(3) \"(1.234)\" é negativo, pela convenção contábil", String(pl?.valor_num));

    // 6: valor não-numérico preservado como texto, e sem número inventado.
    const prov = porChave.get("Provisão para contingências");
    checar(prov?.valor_num === null && prov?.valor_texto === "vide nota 12",
      "(6) valor que não é número volta como TEXTO, sem número inventado",
      `${prov?.valor_num} / ${prov?.valor_texto}`);

    // O símbolo de moeda digitado junto não estraga o número.
    const cx = porChave.get("Caixa e equivalentes");
    checar(Number(cx?.valor_num) === 2000,
      "(2) \"R$ 2.000,00\" vale 2000 — o símbolo digitado junto não estraga",
      String(cx?.valor_num));

    // A ordem da planilha é preservada, e é o que o banco grava em `ordem`.
    checar(res.linhas.every((l, i) => l.ordem === i),
      "(1) `ordem` segue a ordem do papel, sem furo",
      res.linhas.map((l) => l.ordem).join(","));
  }
}

// ---- 2b: a FRONTEIRA da regra de milhar sem vírgula --------------------------
//
// O ramo que lê "1.234" como 1234 é uma ESCOLHA sobre um caso ambíguo, e a
// fronteira dela é o que impede a escolha de virar um erro novo: grupo de
// exatamente três dígitos é milhar; um ou dois dígitos depois do ponto é decimal, e
// continua decimal. Sem estes asserts, alguém "simplificaria" a regra para "tira
// todo ponto" e "0,75" viraria 75 — o mesmo tipo de erro na direção oposta.
{
  const casos: [string, number | null][] = [
    ["1.234", 1234],
    ["1.234.567", 1234567],
    ["12.345", 12345],
    ["0.75", 0.75],
    ["1.5", 1.5],
    ["12.34", 12.34],
    ["(2.500)", -2500],
    ["1.234,00", 1234],
    ["-1.234", -1234],
  ];
  const wb = montar();
  const ws = wb.getWorksheet(ABA)!;
  let linha = LINHA_CABECALHO + EXIGIDAS.length + 1;
  for (const [texto] of casos) {
    ws.getRow(linha).getCell(col("rotulo")).value = texto;
    ws.getRow(linha).getCell(col("valor")).value = texto;
    linha += 1;
  }
  const res = await idaEVolta(wb);
  checar(res.ok, "(2b) a planilha da fronteira é lida", res.ok ? "" : res.erro);
  if (res.ok) {
    const porChave = new Map(res.linhas.map((l) => [l.chave, l]));
    for (const [texto, esperado] of casos) {
      const lida = porChave.get(texto);
      checar(Number(lida?.valor_num) === esperado,
        `(2b) "${texto}" vale ${esperado}`, String(lida?.valor_num));
    }
  }
}

// ---- 7: a planilha de OUTRO documento é recusada -----------------------------
{
  const res = await idaEVolta(montar(), OUTRO_DOC);
  checar(!res.ok, "(7) planilha gerada para outro documento é RECUSADA");
  if (!res.ok) {
    // A mensagem nomeia os DOIS ids: sem isso, quem recebe a recusa não sabe qual
    // dos seis arquivos abertos é o certo, e a próxima tentativa é chute.
    checar(res.erro.includes(DOC) && res.erro.includes(OUTRO_DOC),
      "(7) …e a recusa nomeia os dois ids, para a próxima tentativa não ser chute",
      res.erro);
  }
}

// ---- 8: planilha sem o identificador é recusada ------------------------------
{
  const wb = montar();
  const ws = wb.getWorksheet(ABA)!;
  ws.getCell(CELULA_DOC_ID).value = null;
  ws.getRow(LINHA_CABECALHO + 1).getCell(col("valor")).value = 100;
  const res = await idaEVolta(wb);
  checar(!res.ok, "(8) planilha sem o identificador do documento é RECUSADA");
  if (!res.ok) {
    checar(res.erro.includes(CELULA_DOC_ID),
      "(8) …e a recusa diz QUAL célula falta", res.erro);
  }
}

// ---- 9: planilha em branco é recusada, não gravada ---------------------------
{
  const res = await idaEVolta(montar());
  checar(!res.ok, "(9) planilha baixada e devolvida em branco é RECUSADA");
}

// ---- arquivo que não é planilha ----------------------------------------------
{
  const res = await lerPlanilhaTranscricao(
    new TextEncoder().encode("%PDF-1.4 isto é um PDF, não uma planilha").buffer as ArrayBuffer,
    DOC,
  );
  checar(!res.ok, "(8) arquivo que não é .xlsx é recusado com mensagem, não com stack");
}

console.log(`${ok} verificações OK / ${falhas.length} falhas`);
for (const f of falhas) console.log("  FALHOU:", f);
process.exit(falhas.length ? 1 : 0);
