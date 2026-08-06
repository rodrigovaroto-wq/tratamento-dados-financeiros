// AUDITOR DO ARQUIVO ENTREGUE — responde, sobre um .xlsx pronto, o que dá para
// responder sem abrir o Excel.
//
// POR QUE ISTO EXISTE. A auditoria da sessão 40 foi feita à mão: um script
// descartável, rodado uma vez, que achou seis defeitos de número no arquivo que o
// dono tinha exportado — entre eles a DRE realizada dizendo o contrário do
// documento. Auditoria que existe uma vez não é controle, é sorte. Aqui ela vira
// comando, versionada e coberta por teste, para poder ser repetida em todo arquivo
// que sair daqui para a frente.
//
// A DIVISÃO DE TRABALHO é deliberada. As quatro suítes provam o GERADOR; este
// auditor prova o ARQUIVO — inclusive um arquivo gerado meses atrás, ou gerado em
// produção com dado que nenhuma fixture tem. E o que ele NÃO consegue provar (se o
// Excel abre sem reparo, se o gráfico desenha, se o dropdown reprojeta ao clicar)
// está no `docs/ACEITE.md`, que é a parte humana do aceite — curta de propósito.
//
// USO:
//
//   ./portal/node_modules/.bin/tsx portal/scripts/auditar-xlsx.mts <arquivo.xlsx>
//
// Sai com código 1 se qualquer item obrigatório reprovar, para poder entrar em
// script de aceite sem alguém ter de ler a saída.
import { readFileSync } from "node:fs";
import ExcelJS from "exceljs";
import JSZip from "jszip";
import { avaliarCelula, esquecerMemoria } from "./lib/avaliar-formula.mts";
import { ABAS_MODELO } from "../src/lib/modelo-institucional.ts";

export interface ItemAuditoria {
  chave: string;
  pergunta: string;
  ok: boolean;
  /** o que foi medido, para o item poder ser conferido à mão */
  medida: string;
  /** item que só se aplica quando o caso tem o dado (não reprova por ausência) */
  naoAplicavel?: boolean;
}

const letra = (n: number) => {
  let s = "";
  while (n > 0) { const r = (n - 1) % 26; s = String.fromCharCode(65 + r) + s; n = Math.floor((n - 1) / 26); }
  return s;
};

/** Linha de uma aba pelo rótulo (coluna C, comparação por prefixo já aparado). */
function linhaPorRotulo(ws: ExcelJS.Worksheet, rotulo: string): number | null {
  for (let r = 1; r <= ws.rowCount; r++) {
    if (String(ws.getRow(r).getCell(3).value ?? "").trim() === rotulo) return r;
  }
  return null;
}

/** As colunas de ano de uma aba do modelo: da E até a última com cabeçalho. */
function colunasDeAno(ws: ExcelJS.Worksheet): string[] {
  const cols: string[] = [];
  for (let c = 5; c <= 24; c++) {
    const cel = ws.getRow(3).getCell(c).value ?? ws.getRow(1).getCell(c).value;
    if (cel === null || cel === undefined) break;
    cols.push(letra(c));
  }
  return cols.length > 0 ? cols : ["E", "F", "G", "H", "I", "J", "K"];
}

/**
 * Audita um workbook JÁ CARREGADO. Separado do CLI para o
 * `verificar-export.mts` poder rodar o auditor sobre o workbook que ele monta —
 * um auditor sem teste próprio apodrece, e aí passa a mentir sobre o arquivo, que
 * é pior que não existir.
 */
export function auditarWorkbook(
  wb: ExcelJS.Workbook,
  /**
   * `true` quando o `fullCalcOnLoad` foi confirmado NO XML do arquivo. O ExcelJS
   * escreve a flag mas NÃO a restaura em `calcProperties` ao LER de disco (medido:
   * `{}` num arquivo cujo `xl/workbook.xml` traz `fullCalcOnLoad="1"`), então
   * conferir só o objeto reprovaria todo arquivo lido. Quem carrega o arquivo passa
   * o resultado da leitura do ZIP; quem audita um workbook em memória não passa nada
   * e a conferência cai no objeto.
   */
  recalculoNoArquivo?: boolean,
): ItemAuditoria[] {
  const itens: ItemAuditoria[] = [];
  const add = (chave: string, pergunta: string, ok: boolean, medida: string, naoAplicavel = false) =>
    itens.push({ chave, pergunta, ok, medida, naoAplicavel });

  // ---- 1. As 14 abas do modelo existem ------------------------------------
  const faltando = ABAS_MODELO.filter((a) => !wb.getWorksheet(a));
  add("abas", "As 14 abas do modelo institucional estão no arquivo?",
    faltando.length === 0, faltando.length ? `faltam: ${faltando.join(", ")}` : "14 de 14");

  const bs = wb.getWorksheet("Balance Sheet");
  const is = wb.getWorksheet("Income Statement");

  // ---- 2. O BALANÇO FECHA, em toda coluna ---------------------------------
  //
  // É o invariante que decide se o que está no arquivo é um modelo. No arquivo
  // entregue em 06/08/2026 esta linha dizia "NÃO FECHA" nas sete colunas.
  if (bs) {
    const cols = colunasDeAno(bs);
    const r = linhaPorRotulo(bs, "CHECK — Ativo − (Passivo + PL) deve ser ZERO");
    const desvios: string[] = [];
    for (const c of cols) {
      const v = r === null ? null : avaliarCelula(bs, c, r);
      if (typeof v !== "number") { desvios.push(`${c}: não avaliável`); continue; }
      if (Math.abs(v) > 0.5) desvios.push(`${c}: ${v.toFixed(2)}`);
    }
    add("balanco_fecha", "O balanço fecha (Ativo − Passivo − PL = 0) em TODOS os exercícios?",
      r !== null && desvios.length === 0,
      desvios.length ? desvios.join(" · ") : `zero nas ${cols.length} colunas`);
  } else {
    add("balanco_fecha", "O balanço fecha em todos os exercícios?", false, "aba ausente");
  }

  // ---- 3. A DRE REALIZADA É A DO DOCUMENTO --------------------------------
  //
  // O defeito mais caro da sessão 40: a cascata subtrai despesa e a extração
  // entrega despesa negativa, e o realizado saía com o sinal invertido. A linha de
  // conferência existe no arquivo desde então; aqui ela é LIDA.
  if (is) {
    const cols = colunasDeAno(is);
    const difs: string[] = [];
    let conferidos = 0;
    for (const rotulo of ["Receita líquida", "Lucro bruto", "EBIT", "Resultado líquido"]) {
      const r = linhaPorRotulo(is, `${rotulo} — informado no documento`);
      if (r === null) continue;
      // A linha de diferença é a de baixo (o par informado/diferença é gerado junto).
      for (const c of cols) {
        const informado = avaliarCelula(is, c, r);
        if (typeof informado !== "number") continue; // exercício projetado
        const dif = avaliarCelula(is, c, r + 1);
        conferidos++;
        if (typeof dif !== "number" || Math.abs(dif) > 0.5) difs.push(`${rotulo}/${c}: ${JSON.stringify(dif)}`);
      }
    }
    add("dre_confere", "A DRE do realizado reproduz o documento (diferença ZERO)?",
      conferidos > 0 && difs.length === 0,
      conferidos === 0
        ? "o documento não informa linha de resultado — nada a conferir"
        : difs.length ? difs.join(" · ") : `${conferidos} célula(s) conferidas, todas em zero`,
      conferidos === 0);
  }

  // ---- 4. O ativo total é o informado no documento ------------------------
  if (bs) {
    const cols = colunasDeAno(bs);
    const r = linhaPorRotulo(bs, "diferença (modelo − documento) — ZERO");
    const difs: string[] = [];
    let conferidos = 0;
    for (const c of cols) {
      const v = r === null ? null : avaliarCelula(bs, c, r);
      if (typeof v !== "number") continue;
      conferidos++;
      if (Math.abs(v) > 0.5) difs.push(`${c}: ${v.toFixed(2)}`);
    }
    add("ativo_confere", "O ativo total do modelo é o informado no documento?",
      r !== null && conferidos > 0 && difs.length === 0,
      r === null ? "o documento não informa o total do ativo"
        : difs.length ? difs.join(" · ") : `${conferidos} exercício(s) em zero`,
      r === null);
  }

  // ---- 4b. O MODELO TEM CONTEÚDO ------------------------------------------
  //
  // Um balanço sem conta nenhuma FECHA (zero = zero) e uma DRE sem linha de
  // resultado sai toda em zero — e zero, num modelo financeiro, é uma afirmação
  // sobre o negócio, não a ausência de dado. Foi exatamente o que a cadeia do book
  // produzia antes da Fase A (`secao_canonica` nula: 132 contas caíam fora dos
  // blocos), e nenhum invariante acusava porque tudo "fechava". Este item existe
  // para "não recebi dado" nunca mais se parecer com "a empresa não tem operação".
  {
    const rec2 = wb.getWorksheet("Revenues, COGS & SG&A");
    const cols = bs ? colunasDeAno(bs) : [];
    const rAtivo = bs ? linhaPorRotulo(bs, "ATIVO TOTAL") : null;
    // Último exercício REALIZADO é o que tem preenchimento vindo da extração; para o
    // item basta que ALGUMA coluna traga ativo diferente de zero.
    const ativoMax = bs && rAtivo !== null
      ? Math.max(...cols.map((c) => { const v = avaliarCelula(bs, c, rAtivo); return typeof v === "number" ? Math.abs(v) : 0; }))
      : 0;
    const temAvisoSemDRE = rec2 !== undefined && (() => {
      const isws = wb.getWorksheet("Income Statement");
      if (!isws) return false;
      for (let r = 1; r <= isws.rowCount; r++) {
        if (/^SEM DRE:/.test(String(isws.getRow(r).getCell(3).value ?? ""))) return true;
      }
      return false;
    })();
    add("conteudo", "O modelo tem CONTEÚDO (balanço com conta e DRE com linha de resultado)?",
      ativoMax > 0 && !temAvisoSemDRE,
      temAvisoSemDRE ? "a aba Income Statement declara SEM DRE — a extração não classificou as linhas de resultado"
        : ativoMax > 0 ? `ativo total máximo ${ativoMax.toLocaleString("pt-BR")}`
        : "ATIVO TOTAL é ZERO em todos os exercícios — balanço vazio FECHA, e não é modelo");
  }

  // ---- 5. Nenhuma fórmula nasce com erro ---------------------------------
  const comErro: string[] = [];
  let nFormulas = 0;
  for (const ws of wb.worksheets) {
    for (let r = 1; r <= ws.rowCount; r++) {
      const row = ws.getRow(r);
      row.eachCell({ includeEmpty: false }, (cell) => {
        const v = cell.value as { formula?: string } | null;
        if (!v || typeof v !== "object" || !("formula" in v) || !v.formula) return;
        nFormulas++;
        if (/#REF!|#VALUE!|#DIV\/0!|#NAME\?|#NUM!/.test(v.formula)) {
          comErro.push(`${ws.name}!${cell.address}`);
        }
      });
    }
  }
  add("sem_erro", "Nenhuma fórmula do arquivo nasce com #REF!/#VALUE!?",
    comErro.length === 0,
    comErro.length ? comErro.slice(0, 5).join(", ") : `${nFormulas} fórmulas, nenhuma com erro`);

  // ---- 6. Recalcula ao abrir ---------------------------------------------
  //
  // O arquivo sai com fórmula e SEM valor em cache. Sem `fullCalcOnLoad` o Excel
  // mostra célula vazia até alguém apertar F9 — e o dono leria zero como zero.
  const calc = (wb as unknown as { calcProperties?: { fullCalcOnLoad?: boolean } }).calcProperties;
  const temRecalculo = recalculoNoArquivo ?? calc?.fullCalcOnLoad === true;
  add("recalcula", "O arquivo pede recálculo ao abrir (fullCalcOnLoad)?",
    temRecalculo,
    recalculoNoArquivo === undefined
      ? `calcProperties: ${JSON.stringify(calc ?? null)}`
      : `xl/workbook.xml: fullCalcOnLoad ${recalculoNoArquivo ? "presente" : "AUSENTE"}`);

  // ---- 7. As 14 abas imprimem -------------------------------------------
  const semArea = ABAS_MODELO.filter((a) => {
    const ws = wb.getWorksheet(a);
    return !ws || !ws.pageSetup?.printArea;
  });
  add("imprime", "As 14 abas do modelo declaram área de impressão?",
    semArea.length === 0, semArea.length ? `sem área: ${semArea.join(", ")}` : "14 de 14");

  // ---- 8. O painel de premissas está montado e COMPÕE --------------------
  //
  // A promessa de editar dentro do Excel. Aqui se confere a mecânica (a fórmula
  // compõe índice e spread); que o dropdown reprojeta ao clicar é item humano.
  const rec = wb.getWorksheet("Revenues, COGS & SG&A");
  const rPainel = rec ? linhaPorRotulo(rec, "= crescimento nominal aplicado") : null;
  if (rec && rPainel !== null) {
    const cols = colunasDeAno(rec);
    const cel = rec.getRow(rPainel).getCell(cols[cols.length - 1]).value as { formula?: string } | null;
    const f = cel && typeof cel === "object" && "formula" in cel ? cel.formula ?? "" : "";
    const compoe = /\(1\+N\(/.test(f) && /\)\*\(1\+/.test(f);
    add("painel", "O painel de premissas COMPÕE índice macro × spread (não soma)?",
      compoe, compoe ? f.slice(0, 60) : `fórmula inesperada: ${f.slice(0, 60)}`);
  } else {
    add("painel", "O painel de premissas está montado?", true,
      "o caso não tem premissa de crescimento — painel não se aplica", true);
  }

  // ---- 9. Série de NÍVEL não carrega variação ----------------------------
  const anual = wb.getWorksheet("Anual");
  const rFx = anual ? linhaPorRotulo(anual, "R$/US$ — final de período") : null;
  if (anual && rFx !== null) {
    const cols = colunasDeAno(anual);
    const fora: string[] = [];
    for (const c of cols) {
      const v = avaliarCelula(anual, c, rFx);
      // Câmbio é nível: negativo não existe, e valor de dois dígitos é variação
      // percentual disfarçada (foi o que o arquivo de 06/08/2026 publicou: −10,6).
      if (typeof v === "number" && (v < 0 || v > 20)) fora.push(`${c}: ${v}`);
    }
    add("cambio", "A linha de câmbio traz NÍVEL (nunca variação, nunca negativo)?",
      fora.length === 0, fora.length ? fora.join(" · ") : "todos os anos plausíveis ou vazios");
  }

  // ---- 10. Os gráficos, e se eles imprimem ------------------------------
  //
  // A especificação viaja presa ao workbook até o pós-processamento do buffer; num
  // arquivo LIDO de disco ela não existe mais, então aqui só se confere o que o
  // ExcelJS expõe. O teste de que o gráfico DESENHA é humano (item do ACEITE).
  const espec = (wb as unknown as { __graficosDoModelo?: Array<{
    titulo: string; de: { col: number; linha: number }; ate: { col: number; linha: number };
  }> }).__graficosDoModelo;
  if (espec) {
    const out = wb.getWorksheet("Output");
    const area = String(out?.pageSetup?.printArea ?? "");
    const m = /^B1:([A-Z]+)(\d+)$/.exec(area);
    const colNum = (s: string) => [...s].reduce((n, ch) => n * 26 + (ch.charCodeAt(0) - 64), 0);
    const fora = m ? espec.filter((e) => e.ate.col + 1 > colNum(m[1]) || e.ate.linha + 1 > Number(m[2])) : espec;
    add("graficos", "Os 8 gráficos existem e caem DENTRO da área de impressão do Output?",
      espec.length === 8 && fora.length === 0,
      `${espec.length} gráfico(s), área ${area || "(ausente)"}, fora ${fora.length}`);
  }

  for (const ws of wb.worksheets) esquecerMemoria(ws);
  return itens;
}

// ---------------------------------------------------------------------------
// CLI
// ---------------------------------------------------------------------------
if (process.argv[1] && /auditar-xlsx\.mts$/.test(process.argv[1])) {
  const arq = process.argv[2];
  if (!arq) {
    console.error("uso: auditar-xlsx.mts <arquivo.xlsx>");
    process.exit(2);
  }
  const wb = new ExcelJS.Workbook();
  await wb.xlsx.readFile(arq);
  // A flag de recálculo é lida do XML, não do objeto — ver o comentário do parâmetro.
  const zip = await JSZip.loadAsync(readFileSync(arq));
  const workbookXml = await zip.file("xl/workbook.xml")?.async("string") ?? "";
  const itens = auditarWorkbook(wb, /fullCalcOnLoad="(1|true)"/.test(workbookXml));
  console.log(`AUDITORIA DE ${arq}\n`);
  let reprovados = 0;
  for (const it of itens) {
    const marca = it.ok ? "SIM " : it.naoAplicavel ? "n/a " : "NÃO ";
    if (!it.ok && !it.naoAplicavel) reprovados++;
    console.log(`[${marca}] ${it.pergunta}\n         ${it.medida}`);
  }
  console.log(`\n${itens.length - reprovados}/${itens.length} itens OK · ${reprovados} reprovado(s)`);
  if (reprovados > 0) {
    console.log("\nItem reprovado NÃO é opinião: cada um é um número lido do arquivo. Veja a medida");
    console.log("ao lado e o docs/ACEITE.md para o que fazer com ela.");
  }
  process.exit(reprovados > 0 ? 1 : 0);
}
