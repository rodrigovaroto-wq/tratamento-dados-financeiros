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
// está no `Arquitetura do Sistema/6 Referência/ACEITE.md`, que é a parte humana do aceite — curta de propósito.
//
// USO:
//
//   ./portal/node_modules/.bin/tsx portal/scripts/auditar-xlsx.mts <arquivo.xlsx>
//
// Sai com código 1 se qualquer item obrigatório reprovar, para poder entrar em
// script de aceite sem alguém ter de ler a saída.
import { existsSync, readFileSync, realpathSync, statSync } from "node:fs";
import { extname, isAbsolute, relative, resolve } from "node:path";
import { homedir, tmpdir } from "node:os";
import { fileURLToPath } from "node:url";
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
  //
  // ARQUIVO SEM MODELO NÃO É ARQUIVO QUEBRADO. O portal tem DOIS botões: o de
  // dados (as abas linha a linha, sem projeção nenhuma) e o de modelagem. E
  // mesmo no completo, o modelo só é construído quando o mandato configurou a
  // modelagem — antes disso o arquivo sai legítimo e sem as 14 abas.
  //
  // Auditar esse arquivo item a item do modelo produzia CINCO reprovações
  // seguidas ("balanço não fecha", "sem área de impressão", …) sobre um arquivo
  // correto. Alarme falso em ferramenta de aceite custa o mesmo que alarme
  // ausente: quem vê cinco vermelhos num arquivo bom aprende a ignorar o
  // vermelho. Aqui o auditor DIZ o que está auditando e cala o que não se
  // aplica — os itens do arquivo inteiro (fórmula com erro, recálculo ao abrir)
  // continuam valendo, porque esses valem para qualquer .xlsx que saia daqui.
  const faltando = ABAS_MODELO.filter((a) => !wb.getWorksheet(a));
  const semModelo = faltando.length === ABAS_MODELO.length;
  if (semModelo) {
    add("abas", "Este arquivo traz o modelo institucional?", true,
      "não — é o export de DADOS (ou um mandato sem modelagem configurada). Os itens do modelo "
      + "não se aplicam; os do arquivo inteiro, abaixo, sim.", true);
  } else {
    add("abas", "As 14 abas do modelo institucional estão no arquivo?",
      faltando.length === 0, faltando.length ? `faltam: ${faltando.join(", ")}` : "14 de 14");
  }

  const bs = semModelo ? undefined : wb.getWorksheet("Balance Sheet");
  const is = semModelo ? undefined : wb.getWorksheet("Income Statement");

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
  } else if (!semModelo) {
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
  if (!semModelo) {
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
  if (!semModelo) {
    const semArea = ABAS_MODELO.filter((a) => {
      const ws = wb.getWorksheet(a);
      return !ws || !ws.pageSetup?.printArea;
    });
    add("imprime", "As 14 abas do modelo declaram área de impressão?",
      semArea.length === 0, semArea.length ? `sem área: ${semArea.join(", ")}` : "14 de 14");
  }

  // ---- 8. O painel de premissas está montado e COMPÕE --------------------
  //
  // A promessa de editar dentro do Excel. Aqui se confere a mecânica (a fórmula
  // compõe índice e spread); que o dropdown reprojeta ao clicar é item humano.
  const rec = semModelo ? undefined : wb.getWorksheet("Revenues, COGS & SG&A");
  const rPainel = rec ? linhaPorRotulo(rec, "= crescimento nominal aplicado") : null;
  if (rec && rPainel !== null) {
    const cols = colunasDeAno(rec);
    const cel = rec.getRow(rPainel).getCell(cols[cols.length - 1]).value as { formula?: string } | null;
    const f = cel && typeof cel === "object" && "formula" in cel ? cel.formula ?? "" : "";
    const compoe = /\(1\+N\(/.test(f) && /\)\*\(1\+/.test(f);
    add("painel", "O painel de premissas COMPÕE índice macro × spread (não soma)?",
      compoe, compoe ? f.slice(0, 60) : `fórmula inesperada: ${f.slice(0, 60)}`);
  } else if (!semModelo) {
    add("painel", "O painel de premissas está montado?", true,
      "o caso não tem premissa de crescimento — painel não se aplica", true);
  }

  // ---- 9. Série de NÍVEL não carrega variação ----------------------------
  const anual = semModelo ? undefined : wb.getWorksheet("Anual");
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

  // ---- 9b. O TAMANHO DO RESÍDUO DE RECONCILIAÇÃO -------------------------
  //
  // POR QUE ESTE ITEM EXISTE, e por que sem ele os dois itens acima passariam a
  // ser decorativos. O modelo fecha o realizado NO NÚMERO DO DOCUMENTO: cada
  // grupo do balanço, os dois totais gerais e os quatro níveis da DRE têm uma
  // linha de reconciliação que absorve a diferença entre a soma das contas
  // extraídas e o total impresso. É o que torna o modelo utilizável — um balanço
  // que não fecha não projeta — e é também o que faz "o balanço fecha" e "a DRE
  // reproduz o documento" passarem por construção.
  //
  // O que NÃO passa por construção é o TAMANHO do resíduo. Ele é a medida direta
  // da qualidade da extração daquele caso: zero significa que as contas extraídas
  // somam exatamente o que o documento imprime; 13% da receita significa que o
  // modelo está apoiado no total do documento e que as contas por baixo dele não
  // fecham — o analista precisa saber disso ANTES de usar a abertura por conta.
  //
  // O corte de 5% é de materialidade, na faixa usual de auditoria (5% do
  // resultado, 0,5–1% de receita/ativo): abaixo dele o resíduo é ruído de
  // arredondamento e classificação; acima, é o tipo de buraco que muda a leitura
  // de uma linha inteira.
  if (!semModelo) {
    const alvos: Array<{ aba: string; base: string }> = [
      { aba: "Balance Sheet", base: "ATIVO TOTAL" },
      { aba: "Income Statement", base: "NET REVENUES" },
    ];
    const achados: string[] = [];
    let pior = 0;
    let medidos = 0;
    for (const { aba, base } of alvos) {
      const ws = wb.getWorksheet(aba);
      if (!ws) continue;
      const rBase = linhaPorRotulo(ws, base);
      if (rBase === null) continue;
      const cols = colunasDeAno(ws);
      for (let r = 1; r <= ws.rowCount; r++) {
        const rot = String(ws.getRow(r).getCell(3).value ?? "");
        if (!/^\s*reconciliação com /.test(rot)) continue;
        for (const c of cols) {
          const v = avaliarCelula(ws, c, r);
          const b = avaliarCelula(ws, c, rBase);
          if (typeof v !== "number" || typeof b !== "number" || Math.abs(b) < 0.5) continue;
          medidos++;
          const pct = Math.abs(v) / Math.abs(b);
          if (pct > pior) pior = pct;
          if (pct > 0.05) {
            achados.push(`${aba}!${c}${r} ${rot.trim().slice(0, 46)}: `
              + `${v.toLocaleString("pt-BR", { maximumFractionDigits: 0 })} `
              + `(${(pct * 100).toFixed(1)}% de ${base})`);
          }
        }
      }
    }
    add("residuo_reconciliacao",
      "O resíduo de reconciliação com o documento é IMATERIAL (≤5% da base)?",
      achados.length === 0,
      medidos === 0
        ? "o caso não tem linha de reconciliação — as contas extraídas somam o total informado"
        : achados.length > 0
          ? `${achados.length} acima de 5% · ${achados.slice(0, 3).join(" · ")}`
          : `maior resíduo: ${(pior * 100).toFixed(1)}% da base`,
      medidos === 0);
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
  // VALIDAÇÃO DO CAMINHO (sonar tssecurity:S8707). Este comando não tem um
  // "diretório esperado" para confinar o argumento: é uma ferramenta de
  // operador, chamada diretamente por quem já tem acesso ao arquivo no próprio
  // disco (Downloads, /tmp, uma exportação recém-gerada em outro lugar) — o
  // arquivo a auditar É QUALQUER exportação, de propósito, não um caminho
  // dentro do projeto. Não existe fronteira de privilégio sendo cruzada (quem
  // roda o comando já poderia ler o arquivo por fora dele).
  //
  // O CAMINHO É CONTIDO ANTES DE O DISCO SER TOCADO, e a ORDEM é a correção.
  // A tentativa anterior continha o caminho — mas só DEPOIS de `existsSync` e
  // `statSync`, e o `tssecurity:S8707` apontou exatamente as duas linhas: uma
  // checagem que roda depois do acesso não é guarda, é legenda. É o mesmo
  // formato de defeito que a `0029` corrigiu no banco (auto-aceite gravado antes
  // das guardas, e nenhuma guarda revertia), agora no sistema de arquivos.
  //
  // A ordem passa a ser: normaliza -> CONTÉM -> confere extensão -> toca o disco
  // -> resolve links -> CONTÉM DE NOVO. A segunda contenção existe porque a
  // primeira julga o nome e o symlink só se revela no `realpathSync`: sem ela,
  // `~/exp.xlsx -> /etc/shadow` passaria na primeira (o nome está no home) e
  // seria lido. Cada `if` sai por `process.exit`, então nada a jusante recebe
  // caminho não contido.
  //
  // AS RAÍZES SÃO TRÊS, e cobrem o uso legítimo inteiro: a raiz do projeto (a
  // exportação recém-gerada), o temporário do sistema (para onde o
  // `gerar-export-*.mts` escreve por padrão) e o home do operador (Downloads, de
  // onde vem o arquivo que o cliente devolveu). Fora desses três não é caso de
  // uso desta ferramenta — é engano de digitação ou caminho vindo de outro
  // lugar, e recusar é o certo nos dois. A raiz do projeto sai da localização
  // DESTE arquivo, não do cwd, que é entrada do operador como qualquer outra.
  //
  // A contenção usa `relative()` e não `startsWith()`: comparar prefixo de texto
  // deixa `/home/user-malicioso` passar por estar sob `/home/user`, porque um é
  // prefixo do outro sem ser diretório-pai. `relative(raiz, alvo)` devolve o
  // caminho de dentro; se ele começa com `..` ou é absoluto, o alvo está FORA.
  const raizProjeto = resolve(fileURLToPath(new URL("../..", import.meta.url)));
  const RAIZES_PERMITIDAS = [raizProjeto, realpathSync(tmpdir()), homedir()]
    .map((r) => resolve(r));
  function dentroDeRaizPermitida(caminho: string): boolean {
    return RAIZES_PERMITIDAS.some((raiz) => {
      const dentro = relative(raiz, caminho);
      return dentro === "" || (!dentro.startsWith("..") && !isAbsolute(dentro));
    });
  }

  const arqResolvido = resolve(arq);
  if (!dentroDeRaizPermitida(arqResolvido)) {
    console.error(
      `recusado: ${arqResolvido} está fora do projeto, do temporário e do home.`);
    process.exit(2);
  }
  if (extname(arqResolvido).toLowerCase() !== ".xlsx") {
    console.error(`esperado um arquivo .xlsx: ${arq}`);
    process.exit(2);
  }
  if (!existsSync(arqResolvido) || !statSync(arqResolvido).isFile()) {
    console.error(`arquivo não encontrado: ${arq}`);
    process.exit(2);
  }
  // Segunda contenção, agora sobre o destino REAL do link.
  const arqReal = realpathSync(arqResolvido);
  if (!dentroDeRaizPermitida(arqReal)) {
    console.error(
      `recusado: ${arq} aponta para ${arqReal}, fora do projeto, do temporário e do home.`);
    process.exit(2);
  }

  const wb = new ExcelJS.Workbook();
  await wb.xlsx.readFile(arqReal);
  // A flag de recálculo é lida do XML, não do objeto — ver o comentário do parâmetro.
  const zip = await JSZip.loadAsync(readFileSync(arqReal));
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
    console.log("ao lado e o Arquitetura do Sistema/6 Referência/ACEITE.md para o que fazer com ela.");
  }
  process.exit(reprovados > 0 ? 1 : 0);
}
