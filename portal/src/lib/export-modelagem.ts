// Aba MACRO e aba MODELAGEM do export.
//
// SEPARADO DE `export.ts` na sessão 20. Motivo, medido: `export.ts` estava com
// 4.100 linhas e as duas metades não conversam — a de cima classifica e emite
// as demonstrações EXTRAÍDAS; esta constrói os índices macro e o modelo de
// FP&A. O corte exigiu exatamente nove símbolos em comum, todos de
// apresentação, que foram para `export-estilo.ts`.
//
// O QUE ESTE MOVIMENTO NÃO PODE TER MUDADO: nenhum endereço de célula. É uma
// realocação de texto, não uma reescrita — a ordem em que as abas são criadas,
// as linhas em que cada bloco é escrito e todas as fórmulas continuam idênticas.
// Quem prova isso são os 273 invariantes do `verificar-export.mts` (vários
// afirmam endereço e fórmula literais) e a suíte e2e, que confere o arquivo
// gerado contra o gabarito do book.
import ExcelJS from "exceljs";
import {
  ANALISE_HEADER_FILL, CHAVE_SEP, DIVERGENCIA_FILL, HEADER_FILL, PCT_FMT,
  RATIO_FMT, THIN_TOP_BORDER, VALOR_NUM_FMT, comoNota,
} from "./export-estilo";


// ===========================================================================
// ABA MODELAGEM — o modelo pronto para receber inputs (pedido do dono, v27)
//
// Espelha a arquitetura do modelo de FP&A que o dono usa como referência
// (Projeções DeLend), traduzida para dado ANUAL de reestruturação:
//   • TIMELINE derivada de uma célula: lá `C7=2022-01-31` + `=EDATE(C7,1)`;
//     aqui o primeiro exercício + `=anterior+1`.
//   • CORTE Real×Projetado numa única célula, com linha-flag derivada dela
//     (lá `=IF(C7<=$C$2,1,0)`) — é o que faz a MESMA fórmula servir a coluna
//     histórica e a projetada.
//   • Custo/despesa entram NEGATIVOS, para todo agregado ser soma simples
//     (`=EBITDA+D&A`, nunca `receita - custo` com sinal implícito).
//   • Índice sempre `IFERROR(x/denominador$ancorado, "")`.
//
// A regra que o dono travou: **nada escrito à mão fora dos INPUTS**. Toda
// linha histórica é `INDEX/MATCH` contra as abas de dados deste mesmo arquivo
// (a planilha continua viva: corrigiu a aba de origem, o modelo acompanha), e
// toda linha projetada é fórmula sobre as premissas. Por isso o modelo é
// honesto com a doutrina (f0/07): ele não GRAVA número nenhum — ele referencia
// o que foi extraído e aplica a premissa que o humano digitou.
//
// A chave de busca reaproveita o cabeçalho que as abas de dados já emitem
// ("<entidade> — <período>"), montada por fórmula a partir das duas células de
// input: `=$C$3&" — "&C$7`. Trocar a entidade modelada reescreve o modelo
// inteiro sem tocar em nenhuma outra célula.
// ===========================================================================
export const ABA_MODELAGEM = "Modelagem";

// Horizonte da projeção. Três exercícios é o padrão de um plano de
// reestruturação — e o número de colunas não muda nada da lógica: a timeline
// deriva de uma célula só.
export const ANOS_PROJETADOS = 3;

// NENHUMA aba é ocultada (pedido do dono, teste v28: "quero todas as abas juntas
// no exportável"). O que motivou o pedido não foi estética: ele abriu o v28, viu
// 4 abas visíveis e concluiu que "as demais não vieram" — DMPL, Combinado,
// Balancete, Faturamento, Dívida, Intragrupo e Outros ESTAVAM lá, ocultas. Aba
// oculta num arquivo de entrega lê-se como dado ausente, e dado ausente é a
// pergunta mais cara que este export pode provocar. A Modelagem continua sendo a
// aba ATIVA (é por onde o arquivo abre) — o que se perde ao ocultar as outras não
// se ganha em nada.
const ABA_MACRO = "Macro";
const ABA_MACRO_DADOS = "Macro (dados)";

// ---------------------------------------------------------------------------
// ÍNDICES MACROECONÔMICOS (db/migrations/0025)
//
// Dois fatos diferentes, e o modelo usa os dois para coisas diferentes:
//   • `anuais`       — o que ACONTECEU (série publicada, acumulada por ano).
//                      Serve para calibrar: média de 3/5/10 anos.
//   • `expectativas` — o que o mercado ESPERA (Focus, por ano-calendário).
//                      Serve para PROJETAR. Média histórica não é previsão.
//
// A aba visível "Macro" não guarda número nenhum: ela é toda fórmula sobre a
// aba oculta "Macro (dados)", pela mesma regra das demonstrações — corrigiu a
// origem, tudo acompanha.
// ---------------------------------------------------------------------------
export interface MacroAnual {
  serie: string;
  ano: number;
  meses: number;
  retorno: number;
}
export interface MacroExpectativa {
  serie: string;
  ano_ref: number;
  mediana: number;
  coletado_em: string;
}
export interface MacroParaExport {
  anuais: MacroAnual[];
  expectativas: MacroExpectativa[];
  nomes?: Record<string, string>;
}

const JANELAS_MEDIA_EXPORT = [3, 5, 10];

const INPUT_FILL: ExcelJS.Fill = { type: "pattern", pattern: "solid", fgColor: { argb: "FFFFF9C4" } };
const INPUT_BORDER: Partial<ExcelJS.Borders> = {
  top: { style: "thin", color: { argb: "FFB8860B" } },
  left: { style: "thin", color: { argb: "FFB8860B" } },
  bottom: { style: "thin", color: { argb: "FFB8860B" } },
  right: { style: "thin", color: { argb: "FFB8860B" } },
};
const BLOCO_FILL: ExcelJS.Fill = { type: "pattern", pattern: "solid", fgColor: { argb: "FF1E293B" } };
const BLOCO_FONT: Partial<ExcelJS.Font> = { bold: true, color: { argb: "FFFFFFFF" }, size: 11 };
const PROJETADO_FILL: ExcelJS.Fill = { type: "pattern", pattern: "solid", fgColor: { argb: "FFEFF6FF" } };
const TOTAL_FONT: Partial<ExcelJS.Font> = { bold: true };

// Referência a uma linha-âncora de uma aba de dados, para a coluna da entidade
// e período modelados. Duas buscas: a linha pelo rótulo (coluna A da origem) e
// a coluna pelo cabeçalho "<entidade> — <período>" — os dois já existem hoje.
// ATENÇÃO ao `rotulo`: é o texto que a aba de origem escreve na coluna A. No
// Balanço isso é o nome da SEÇÃO ("Ativo Circulante"), que é a linha que carrega
// o subtotal — NÃO "Total do Ativo Circulante", que só aparece quando o próprio
// documento traz essa linha. Errar aqui não quebra nada visivelmente: o
// `IFERROR` devolve 0 e o modelo fecha com zeros. O invariante 13 confere que
// todo rótulo procurado existe de fato na aba de destino.
//
// Os intervalos são LIMITADOS ao tamanho real da aba de destino, nunca coluna
// inteira. `INDEX('Balanço'!$B:$BZ, …)` referencia 77 colunas × 1.048.576 linhas
// por célula do modelo; com ~500 células isso é um grafo de dependência que
// trava o recálculo (aqui derrubou por falta de memória um motor de fórmulas
// que abre a planilha inteira sem esforço — no Excel do usuário o efeito é a
// planilha "pensando" a cada digitação). Limitar não muda o resultado: fora do
// intervalo usado não há dado nenhum.
function limitesDaAba(workbook: ExcelJS.Workbook, aba: string): { ultimaCol: string; ultimaLinha: number } {
  const ws = workbook.getWorksheet(aba);
  if (!ws) return { ultimaCol: "B", ultimaLinha: 1 };
  return {
    ultimaCol: ws.getColumn(Math.max(2, ws.columnCount)).letter,
    ultimaLinha: Math.max(1, ws.rowCount),
  };
}

function buscaNaAba(
  workbook: ExcelJS.Workbook, aba: string, rotulo: string, colChave: string,
): string {
  const ref = `'${aba}'`;
  const { ultimaCol, ultimaLinha } = limitesDaAba(workbook, aba);
  return `IFERROR(INDEX(${ref}!$B$1:$${ultimaCol}$${ultimaLinha},`
    + `MATCH("${rotulo}",${ref}!$A$1:$A$${ultimaLinha},0),`
    + `MATCH(${colChave},${ref}!$B$1:$${ultimaCol}$1,0)),0)`;
}

// Aba OCULTA com o dado cru vindo do banco. É a única parte do bloco macro que
// carrega número escrito — exatamente como as abas de demonstração: o dado
// entra aqui, e tudo que é leitura vira fórmula em cima.
function construirAbaMacroDados(
  workbook: ExcelJS.Workbook, macro: MacroParaExport,
): { anos: number[]; series: string[]; linhaDe: Map<string, number>; colDe: Map<number, number>;
     // Quais anos, POR SÉRIE, têm os 12 meses. É o que a janela das médias precisa
     // saber — e não sabia, o que a deixava em branco com histórico de sobra.
     completosDe: Map<string, number[]>;
     anosExp: number[]; linhaExpDe: Map<string, number>; colExpDe: Map<number, number>;
     // Quais anos, POR SÉRIE, têm mediana do Focus. `anosExp` é a união de todas
     // as séries e NÃO serve para isso: o Focus publica horizontes diferentes
     // por indicador, então uma série pode não ter o ano que outra tem. O modelo
     // precisa da cobertura da SÉRIE que ele vai ler, senão apresenta ausência
     // como expectativa zero.
     anosExpDe: Map<string, number[]> } {
  const sheet = workbook.addWorksheet(ABA_MACRO_DADOS, { views: [{ state: "frozen", xSplit: 1, ySplit: 1 }] });
  const anos = [...new Set(macro.anuais.map((a) => a.ano))].sort((a, b) => a - b);
  const series = [...new Set(macro.anuais.map((a) => a.serie))].sort();

  sheet.getColumn(1).width = 30;
  const cab = sheet.addRow(["Série (retorno anual %)", ...anos]);
  cab.font = { bold: true };
  cab.eachCell((c) => { c.fill = HEADER_FILL; });

  const colDe = new Map(anos.map((a, i) => [a, i + 2]));
  const linhaDe = new Map<string, number>();
  const completosDe = new Map<string, number[]>();
  const porChave = new Map(macro.anuais.map((a) => [`${a.serie}${CHAVE_SEP}${a.ano}`, a]));
  for (const serie of series) {
    const row = sheet.addRow([serie]);
    linhaDe.set(serie, row.number);
    for (const ano of anos) {
      const dado = porChave.get(`${serie}${CHAVE_SEP}${ano}`);
      if (!dado) continue;
      const cell = row.getCell(colDe.get(ano)!);
      // Ano INCOMPLETO não entra: acumulado de 4 meses tratado como ano cheio
      // puxaria a média de 3/5/10 anos para baixo sem ninguém perceber. Fica
      // registrado na nota, visível para quem for conferir.
      //
      // E `retorno` NULO também não entra — 12 meses NÃO bastam. A `0032` fez a
      // série de NÍVEL (câmbio) devolver NULL no primeiro ano da série: sem o
      // fechamento do ano anterior não existe variação, e inventar uma era o
      // defeito que ela corrigiu. Mas `meses` continua 12 (o ano TEM observação,
      // só não tem base), e uma coleta que começa em JANEIRO produz exatamente
      // isso: 12 meses + retorno NULL.
      //
      // O QUE ACONTECIA, medido: o ano entrava em `completosDe`, a janela de 3
      // anos o nomeava, e a fórmula da média virava PRODUCT(1+B3/100, …) com B3
      // resolvendo para `""` — porque a célula da aba visível é
      // `IF(dados!X="","",dados!X)`, e texto vazio NÃO é o mesmo que célula
      // vazia: `""/100` é #VALUE!, o erro sobe pelo PRODUCT e o IFERROR de fora
      // devolve "". Resultado: a média 3a saía EM BRANCO com a nota dela
      // afirmando "Média geométrica dos exercícios completos: 2023, 2024, 2025"
      // — nota afirmando um cálculo que não aconteceu, que é exatamente o
      // defeito da fatia 4 num lugar novo. (E se o Excel coagisse "" a 0 em vez
      // de errar, seria pior: o ano sem base entraria valendo 0% de variação,
      // ressuscitando o número inventado que a 0032 tirou.)
      if (dado.meses === 12 && dado.retorno != null) {
        cell.value = dado.retorno;
        completosDe.set(serie, [...(completosDe.get(serie) ?? []), ano]);
      }
      cell.note = comoNota(`${dado.meses} ${dado.meses === 1 ? "mês" : "meses"} observado(s) em ${dado.ano}.`
        + (dado.meses !== 12
          ? " Ano INCOMPLETO — fora das médias de 3/5/10 anos."
          : dado.retorno == null
            ? " SEM RETORNO CALCULÁVEL: é o primeiro exercício desta série e não há fechamento "
              + "do ano anterior para servir de base (série de NÍVEL, como o câmbio, varia entre "
              + "fechamentos — db/migrations/0032). O ano tem os 12 meses observados, mas fica "
              + "fora das médias de 3/5/10 anos: não existe variação, e 0% seria invenção."
            : ""));
      cell.numFmt = "0.00";
    }
  }

  sheet.addRow([]);
  const anosExp = [...new Set(macro.expectativas.map((e) => e.ano_ref))].sort((a, b) => a - b);
  const cabExp = sheet.addRow(["Expectativa Focus (% a.a.)", ...anosExp]);
  cabExp.font = { bold: true };
  cabExp.eachCell((c) => { c.fill = HEADER_FILL; });
  const colExpDe = new Map(anosExp.map((a, i) => [a, i + 2]));
  const linhaExpDe = new Map<string, number>();
  const anosExpDe = new Map<string, number[]>();
  const expPorChave = new Map(macro.expectativas.map((e) => [`${e.serie}${CHAVE_SEP}${e.ano_ref}`, e]));
  for (const serie of [...new Set(macro.expectativas.map((e) => e.serie))].sort()) {
    const row = sheet.addRow([serie]);
    linhaExpDe.set(serie, row.number);
    for (const ano of anosExp) {
      const e = expPorChave.get(`${serie}${CHAVE_SEP}${ano}`);
      if (!e) continue;
      anosExpDe.set(serie, [...(anosExpDe.get(serie) ?? []), ano]);
      const cell = row.getCell(colExpDe.get(ano)!);
      cell.value = e.mediana;
      cell.numFmt = "0.00";
      cell.note = comoNota(
        `Mediana das expectativas de mercado coletadas em ${e.coletado_em} (Boletim Focus/BCB).\n`
        + "Expectativa é DATADA: muda toda semana. A data fica registrada para a projeção "
        + "poder ser reproduzida depois.",
      );
    }
  }
  return { anos, series, linhaDe, colDe, completosDe, anosExp, linhaExpDe, colExpDe, anosExpDe };
}

// Aba VISÍVEL: nenhum número escrito — tudo referência ou fórmula.
export interface RefsMacro {
  // linha do cabeçalho de anos do bloco Focus e linha de cada série nele — é o
  // que permite ao modelo buscar "a expectativa do ANO desta coluna".
  linhaCabFocus: number;
  linhaFocusDe: Map<string, number>;
  ultimaColFocus: string;
  // Cobertura REAL do Focus, por série. Sem isto o modelo não tem como
  // distinguir "o mercado espera 0%" de "o Focus não fala deste ano" — e
  // apresentava a segunda como a primeira, com nota afirmando procedência.
  anosFocusDe: Map<string, number[]>;
  // Endereço das médias históricas 3a/5a/10a, por série, para o modelo poder
  // citá-las. Elas existiam só na aba Macro e não eram referenciadas em lugar
  // nenhum — 18 células que não moviam nada e que ninguém via.
  mediaDe: Map<string, { linha: number; colunas: string[] }>;
  // As janelas, na mesma ordem de `colunas`, para rotular sem adivinhar.
  janelasMedia: readonly number[];
  // Nome por extenso de cada série, como a aba Macro o escreve. O bloco de
  // REFERÊNCIAS MACRO cita séries que o modelo não usa (IGP-M, PIB, câmbio) e
  // "IGPM" cru numa linha de leitura humana é código de sistema, não rótulo.
  nomeDe: Map<string, string>;
}

/**
 * Aba Macro SEM índice coletado — dizendo exatamente o que falta e o efeito.
 *
 * O efeito importa porque não é neutro: sem Focus, as premissas de inflação e
 * juro do modelo ficam em branco, e quem digitar por cima delas está usando
 * memória, não dado publicado. Uma aba ausente não conta isso; esta conta.
 */
export function construirAbaMacroSemDado(workbook: ExcelJS.Workbook, erro?: string): void {
  const ws = workbook.addWorksheet(ABA_MACRO);
  ws.columns = [{ width: 42 }, { width: 92 }];
  const linhas: Array<[string, string]> = [];
  if (erro) {
    // A consulta/RPC FALHOU — a base pode muito bem ter dado. Confundir isto com
    // "não há dado coletado" foi o próprio defeito (0028): RLS habilitado sem
    // policy volta ZERO linhas SEM erro nenhum para quem lê, e função sem
    // `grant execute` volta erro de permissão que o `route.ts` engolia
    // silenciosamente (`?? []` sobre `.data`, sem olhar `.error`). Por isso as
    // duas mensagens abaixo são deliberadamente diferentes uma da outra.
    ws.addRow(["Índices macro — a CONSULTA falhou (pode haver dado na base)"]).font = { bold: true, size: 12 };
    linhas.push([
      "O que aconteceu",
      `A busca dos índices retornou erro: "${erro}". Isto é diferente de "sem dado coletado" — pode `
      + "haver observação/expectativa gravada e a consulta não ter permissão para lê-la (RLS sem "
      + "policy, ou função sem grant para o papel authenticated — db/migrations/0028). Confira "
      + "rodando `select count(*) from indice_macro_obs;` no SQL Editor do Supabase: se vier > 0, é "
      + "autorização, não ausência de coleta.",
    ]);
  } else {
    ws.addRow(["Índices macro — sem dado coletado"]).font = { bold: true, size: 12 };
    linhas.push([
      "O que falta",
      "Nenhuma observação (BCB/IBGE) nem expectativa (Focus) na base. A coleta é o workflow "
      + "n8n/workflow.macro.json, que roda no relógio (dia 12, depois da divulgação do IPCA) e depende "
      + "da migration db/migrations/0025 aplicada NO PROJETO em uso. Importar o workflow não coleta "
      + "nada sozinho: ele precisa estar ATIVO, e a primeira carga histórica pede uma execução manual "
      + "(ou o seed `db/seed/macro_carga_inicial.sql`).",
    ]);
  }
  linhas.push([
    "Efeito nesta entrega",
    "As premissas de inflação (IPCA — Focus) e juro (Selic — Focus) da aba Modelagem ficam em branco. "
    + "Elas são input: dá para digitar por cima e o modelo inteiro responde — mas aí o número é "
    + "memória de quem digitou, não índice publicado com fonte e data.",
  ]);
  ws.addRows(linhas);
  for (const r of [2, 3]) {
    ws.getRow(r).alignment = { wrapText: true, vertical: "top" };
    ws.getRow(r).height = 56;
  }
}

export function construirAbaMacro(
  workbook: ExcelJS.Workbook, macro: MacroParaExport, erroParcial?: string,
): RefsMacro | null {
  if (macro.anuais.length === 0 && macro.expectativas.length === 0) return null;
  const d = construirAbaMacroDados(workbook, macro);
  const dados = `'${ABA_MACRO_DADOS}'`;
  const sheet = workbook.addWorksheet(ABA_MACRO, { views: [{ state: "frozen", xSplit: 1, ySplit: 2 }] });
  const nome = (s: string) => macro.nomes?.[s] ?? s;

  sheet.getColumn(1).width = 34;

  // FALHA PARCIAL da consulta, declarada DENTRO do arquivo.
  //
  // `macroErro` só era usado quando NÃO havia macro nenhum. O caso real que
  // escapava: `fn_indice_macro_anual` e as expectativas respondem, mas a
  // consulta de NOMES das séries não — a aba sai com "IPCA"/"SELIC" crus no
  // lugar dos nomes por extenso, e o único registro do erro era um
  // `console.error` no servidor. Quem abre a planilha não tem acesso a log.
  //
  // A linha é escrita AQUI, antes de qualquer outra: `spliceRows` depois do
  // fato deslocaria toda a numeração da aba, e o modelo endereça as linhas do
  // Focus por NÚMERO (`linhaCabFocus`, `linhaFocusDe`) — cada INDEX/MATCH
  // passaria a apontar uma linha acima, em silêncio.
  if (erroParcial) {
    const av = sheet.addRow([
      `⚠ A consulta dos índices macro falhou EM PARTE: "${erroParcial}". O que está nesta aba veio `
      + "da base e é confiável; o que faltou não aparece — nome de série pode estar como código "
      + "cru, e uma série inteira pode estar ausente sem que a aba tenha como dizer qual. Confira "
      + "no Supabase antes de usar estes índices numa entrega.",
    ]);
    av.font = { bold: true, size: 10, color: { argb: "FF991B1B" } };
    av.getCell(1).fill = DIVERGENCIA_FILL;
    av.alignment = { wrapText: true, vertical: "top" };
    av.height = 42;
  }

  const tit = sheet.addRow(["ÍNDICES MACROECONÔMICOS"]);
  tit.font = { bold: true, size: 14 };

  // ---- Histórico + médias 3/5/10 anos -------------------------------------
  const cab = sheet.addRow([
    "Retorno anual (%)", ...d.anos,
    ...JANELAS_MEDIA_EXPORT.map((j) => `Média ${j}a`),
  ]);
  cab.font = { bold: true };
  cab.eachCell((c) => { c.fill = HEADER_FILL; c.alignment = { horizontal: "center" }; });
  for (let i = 2; i <= 2 + d.anos.length + JANELAS_MEDIA_EXPORT.length; i++) sheet.getColumn(i).width = 12;

  const colLetra = (i: number) => sheet.getColumn(i).letter;
  // Endereço das médias, por série, para o modelo poder CITÁ-LAS. Sem isto elas
  // eram 18 células que não moviam nada e que ninguém fora da aba Macro via.
  const mediaDe = new Map<string, { linha: number; colunas: string[] }>();
  for (const serie of d.series) {
    const origem = d.linhaDe.get(serie)!;
    const row = sheet.addRow([nome(serie)]);
    mediaDe.set(serie, {
      linha: row.number,
      colunas: JANELAS_MEDIA_EXPORT.map((_, k) => colLetra(2 + d.anos.length + k)),
    });
    d.anos.forEach((ano, i) => {
      const c = row.getCell(i + 2);
      c.value = { formula: `IF(${dados}!${colLetra(d.colDe.get(ano)!)}${origem}="","",${dados}!${colLetra(d.colDe.get(ano)!)}${origem})` };
      c.numFmt = "0.00";
    });
    // MÉDIA GEOMÉTRICA, em fórmula: (Π(1+i))^(1/n) − 1. A aritmética daria
    // outro número (10% e 4% → 7,00% em vez de 6,96%) e o erro compõe ao longo
    // do horizonte. `IFERROR` cobre a janela sem histórico suficiente: fica
    // vazia em vez de inventar uma média com os anos que existem.
    // A JANELA É SOBRE OS ANOS COMPLETOS, NOMEADOS UM A UM — não uma fatia
    // posicional das últimas N colunas.
    //
    // O defeito que isto corrige, medido lendo a fórmula gerada: a faixa era
    // `COUNT(L3:N3)<3` sobre as três últimas COLUNAS, e a RPC devolve o ano
    // corrente parcial por construção, então a última coluna está SEMPRE vazia
    // (só `meses === 12` recebe valor). Com 2014-2025 completos + 2026 parcial:
    // COUNT dava 2, 4 e 9 ⇒ as TRÊS médias em branco, com 12 anos completos na
    // base. E a nota explicava "falta de histórico" — falso no caso concreto.
    //
    // Nomear as células também resolve BURACO NO MEIO da série (revisão do IBGE,
    // mês não consolidado), que a faixa contígua não resolvia de jeito nenhum.
    // E `COUNT` deixa de ser necessário: aqui já se sabe, em tempo de geração,
    // se existem N anos completos.
    const completos = d.completosDe.get(serie) ?? [];
    JANELAS_MEDIA_EXPORT.forEach((janela, k) => {
      const c = row.getCell(2 + d.anos.length + k);
      const usados = completos.slice(-janela);
      if (usados.length < janela) {
        // Vazia, mas por um motivo VERDADEIRO — e a nota diz quantos anos há.
        c.note = comoNota(
          `Vazia: a janela de ${janela} anos exige ${janela} exercícios COMPLETOS e há ${completos.length}`
          + `${completos.length > 0 ? ` (${completos.join(", ")})` : ""}.`,
        );
      } else {
        const refs = usados.map((ano) => `1+${colLetra(d.colDe.get(ano)!)}${row.number}/100`).join(",");
        c.value = { formula: `IFERROR((PRODUCT(${refs}))^(1/${janela})-1,"")` };
        // Quais anos entraram: sem isso, uma média sobre anos não adjacentes
        // (por causa de buraco) seria indistinguível de uma sobre os últimos N.
        c.note = comoNota(`Média geométrica dos exercícios completos: ${usados.join(", ")}.`);
      }
      c.numFmt = PCT_FMT;
      c.font = { bold: true };
    });
  }
  sheet.getRow(sheet.rowCount).getCell(1).note = comoNota(
    "As médias são GEOMÉTRICAS ((Π(1+i))^(1/n) − 1), não aritméticas: taxa se compõe. "
    + "A janela usa os últimos N exercícios COMPLETOS, nomeados um a um — o ano corrente, "
    + "sempre parcial, não entra e não estraga a janela. Quando não há N exercícios completos "
    + "a célula fica vazia e a NOTA DELA diz quantos existem.",
  );

  // ---- Expectativa Focus ---------------------------------------------------
  sheet.addRow([]);
  // Os anos vão como NÚMERO, não texto: o modelo busca a expectativa com
  // MATCH(<célula do exercício>, <esta linha>, 0), e o exercício é numérico.
  // Com o cabeçalho em texto o MATCH nunca casa, o IFERROR devolve 0, e a
  // premissa de inflação aparece zerada sem nenhum sinal de erro — foi
  // exatamente o que o primeiro recálculo mostrou.
  const cabExp = sheet.addRow(["Expectativa Focus (% a.a.)", ...d.anosExp]);
  cabExp.font = { bold: true };
  cabExp.eachCell((c) => { c.fill = ANALISE_HEADER_FILL; c.alignment = { horizontal: "center" }; });
  const linhaFocusDe = new Map<string, number>();
  for (const [serie, origem] of d.linhaExpDe) {
    const row = sheet.addRow([nome(serie)]);
    linhaFocusDe.set(serie, row.number);
    d.anosExp.forEach((ano, i) => {
      const c = row.getCell(i + 2);
      const cl = colLetra(d.colExpDe.get(ano)!);
      c.value = { formula: `IF(${dados}!${cl}${origem}="","",${dados}!${cl}${origem})` };
      c.numFmt = "0.00";
    });
  }
  sheet.addRow([]);
  const aviso = sheet.addRow([
    "Histórico calibra; expectativa projeta. A média de 3/5/10 anos descreve o passado e NÃO é "
    + "previsão — quem alimenta a projeção do modelo é a linha do Focus.",
  ]);
  aviso.font = { italic: true, size: 9, color: { argb: "FF64748B" } };
  return {
    linhaCabFocus: cabExp.number,
    linhaFocusDe,
    ultimaColFocus: sheet.getColumn(Math.max(2, 1 + d.anosExp.length)).letter,
    anosFocusDe: d.anosExpDe,
    // Endereço das médias históricas — coletado aqui, ainda NÃO consumido pela
    // Modelagem. É a base do bloco de REFERÊNCIAS MACRO que o dono aprovou
    // (ver HANDOFF, "o que falta da Etapa 2"): sem estes endereços, citar a
    // média 3a/5a/10a no modelo exigiria adivinhar linha e coluna da aba Macro.
    mediaDe,
    janelasMedia: JANELAS_MEDIA_EXPORT,
    // As séries do histórico E as do Focus: o Focus publica PIB, que não tem
    // série histórica coletada, e o histórico tem INPC/CDI, que o Focus não
    // publica. Unir as duas é o que evita "PIB" cru na aba Modelagem.
    nomeDe: new Map(
      [...new Set([...d.series, ...d.linhaExpDe.keys()])].map((s) => [s, nome(s)]),
    ),
  };
}

// Expectativa Focus do ANO de uma coluna.
//
// O QUE ESTA FUNÇÃO NÃO FAZ MAIS, e por quê. Ela devolvia o literal `"0"`
// quando a série não tinha linha, e embrulhava a busca em `IFERROR(…,0)`
// quando o ano projetado não estava no Focus. Os dois zeros chegavam à célula
// de premissa PINTADA DE INPUT e com a nota afirmando "Mediana das
// expectativas de mercado (Boletim Focus/BCB)" — isto é, ausência de dado
// apresentada como dado publicado, que é a coisa que a doutrina (docs/01)
// proíbe explicitamente.
//
// O gatilho é banal, não exótico: os anos que o modelo projeta derivam do
// histórico do CASO. Um mandato com demonstrações de 2019-2021 projeta
// 2022-2024, o Focus publicado cobre 2026-2030, e as TRÊS colunas saíam com
// inflação e juro ZERADOS — enquanto a aba Macro, ao lado, exibia o Focus de
// 2026-2030 como se estivesse tudo em ordem. Todo o bloco de dívida cobra juro
// zero nesse cenário, e o modelo fecha bonito.
//
// Agora a função devolve `null` quando não há o que ler, e quem chama deixa a
// CÉLULA EM BRANCO com nota dizendo o que falta. Em branco é 0 na aritmética do
// Excel (o modelo não quebra), mas lê como "falta preencher" em vez de "o
// mercado espera zero" — e é o que a própria aba "sem dado" já prometia:
// "as premissas … ficam em branco".
function focusMacro(macro: RefsMacro, serie: string, ano: number, colAno: string): string | null {
  const linha = macro.linhaFocusDe.get(serie);
  if (!linha) return null;
  if (!(macro.anosFocusDe.get(serie) ?? []).includes(ano)) return null;
  const ref = `'${ABA_MACRO}'`;
  // O IFERROR fica: a cobertura acima é do ANO DA EXPORTAÇÃO, e a célula do
  // exercício é editável (o dono move a linha do tempo inteira mexendo em uma
  // célula). Se ele mover para um ano fora do Focus, o IFERROR evita #N/A —
  // e a linha "cobertura do Focus", que é VIVA, é quem denuncia o buraco.
  return `IFERROR(INDEX(${ref}!$B$${linha}:$${macro.ultimaColFocus}$${linha},`
    + `MATCH(${colAno},${ref}!$B$${macro.linhaCabFocus}:$${macro.ultimaColFocus}$${macro.linhaCabFocus},0)),0)`;
}

// A premissa em si: a fórmula quando há Focus para ler, `null` (branco) quando
// não há. Cobre também o caso "nenhum índice macro no arquivo", que antes
// escrevia `"0"` — e um zero é indistinguível de uma expectativa medida de 0%.
function premissaDoFocus(
  macro: RefsMacro | null, serie: string, ano: number, colAno: string,
): string | null {
  if (!macro) return null;
  const f = focusMacro(macro, serie, ano, colAno);
  return f === null ? null : `${f}/100`;
}

// A nota da CÉLULA quando ela sai em branco — ela é o que transforma "vazio"
// em "vazio por este motivo". Devolve null quando há dado: aí a nota da linha
// (que descreve a fonte) já basta e repetir só polui.
function notaDoFocus(
  macro: RefsMacro | null, serie: string, ano: number, oQue: string,
): string | null {
  const semDado = (motivo: string) =>
    `EM BRANCO — ${motivo}\n\n`
    + `Ausência não é expectativa. Um 0 aqui projetaria ${oQue} zero para ${ano} com a aparência `
    + "de consenso de mercado, e o modelo fecharia bonito em cima disso. Digite a premissa à mão "
    + "se você tem uma fonte — e então o número é sua hipótese declarada, não índice publicado.";

  if (!macro) {
    return semDado(
      "este arquivo não tem índice macro nenhum (ver a aba Macro, que diz se foi falta de coleta "
      + "ou falha de consulta).",
    );
  }
  if (!macro.linhaFocusDe.has(serie)) {
    return semDado(`o Focus carregado não traz a série ${serie}.`);
  }
  const cobertos = macro.anosFocusDe.get(serie) ?? [];
  if (!cobertos.includes(ano)) {
    const faixa = cobertos.length
      ? `${cobertos[0]}–${cobertos[cobertos.length - 1]}`
      : "nenhum ano";
    return semDado(
      `o Boletim Focus publicado cobre ${faixa} para ${serie}, e esta coluna é o exercício ${ano}. `
      + "Os exercícios do modelo derivam do histórico DESTE mandato — quando as demonstrações são "
      + "antigas, o horizonte projetado fica atrás do horizonte que o Focus publica.",
    );
  }
  return null;
}

// A linha de conferência VIVA que acompanha as duas premissas do Focus.
//
// A cobertura conferida no `focusMacro` é a do momento da exportação. A célula
// do exercício é input — mover o "Último exercício realizado" ou o primeiro ano
// remapeia todas as colunas, e a decisão tomada na geração fica velha. Esta
// fórmula pergunta ao arquivo, a cada recálculo, se AQUELE ano tem Focus.
//
// Dois casos distintos, e os dois viram o mesmo aviso: o ano não está no
// cabeçalho do Focus (MATCH falha → IFERROR) ou está, mas a série não tem
// mediana nele (a célula da aba Macro é "" por construção).
function coberturaFocus(macro: RefsMacro, serie: string, colAno: string): string {
  const linha = macro.linhaFocusDe.get(serie);
  if (!linha) return `"sem Focus para ${serie}"`;
  const ref = `'${ABA_MACRO}'`;
  const valor = `INDEX(${ref}!$B$${linha}:$${macro.ultimaColFocus}$${linha},`
    + `MATCH(${colAno},${ref}!$B$${macro.linhaCabFocus}:$${macro.ultimaColFocus}$${macro.linhaCabFocus},0))`;
  return `IFERROR(IF(${valor}="","SEM FOCUS","Focus "&${colAno}),"SEM FOCUS")`;
}

// ===========================================================================
// ABA MODELAGEM — modelo MENSAL com consolidação anual
//
// Espelha a arquitetura do modelo de FP&A de referência (Projeções DeLend):
// colunas mensais encadeadas por `EDATE`, corte Actual/Forecast numa célula, e
// blocos de consolidação. Lá os anos ficam todos à direita; aqui o consolidado
// vem LOGO DEPOIS dos 12 meses do seu ano, que é como se lê um plano.
//
// AS TRÊS REGRAS DE CONSOLIDAÇÃO — é onde um modelo mensal se perde, e o erro
// é invisível na tela:
//   • FLUXO (receita, custo, caixa gerado) → SOMA dos 12 meses.
//   • ESTOQUE (saldo de caixa, ativo, passivo, PL) → valor de DEZEMBRO. Somar
//     doze balanços daria doze vezes o patrimônio.
//   • ÍNDICE (margem, liquidez) → RECALCULADO sobre os agregados anuais. Somar
//     ou tirar média de percentual mensal não dá o percentual do ano.
//
// E A REGRA DO HISTÓRICO, que é a diferença honesta entre este modelo e um que
// finge precisão que não tem: as demonstrações extraídas são ANUAIS. Não existe
// balanço mensal de 2024 para extrair. Então:
//   • fluxo histórico é DISTRIBUÍDO pelos meses por um vetor de sazonalidade
//     explícito e editável (padrão: 1/12 por mês) — e a soma do ano bate com o
//     número extraído, o que uma linha de conferência prova;
//   • estoque histórico é INTERPOLADO entre o fechamento do ano anterior e o
//     do ano corrente, de modo que dezembro é exatamente o valor extraído.
// Nada disso é apresentado como observação: é distribuição declarada, com o
// critério à vista e na mão do usuário.
// ===========================================================================

interface LinhaModelo {
  rotulo: string;
  unidade?: string;
  // Fórmula da célula MENSAL. `ctx` traz tudo que a linha precisa endereçar.
  mensal?: (ctx: CtxMes) => string;
  // Como o ano consolida. Default: "fluxo" (soma dos 12 meses).
  consolida?: "fluxo" | "estoque" | "inicial" | "formula";
  // Consolidação própria (índices/margens: recalcular sobre o agregado anual).
  // `null` deixa a célula EM BRANCO de propósito — é como uma premissa declara
  // que não tem valor de origem, em vez de fabricar um zero que parece medido.
  anual?: (ctx: CtxAno) => string | null;
  // Nota da célula ANUAL, por exercício. Diferente de `nota`, que fica no rótulo
  // e vale para a linha toda: o que precisa ser dito aqui muda de ano para ano
  // ("2024 não está no Focus" não vale para 2026).
  notaAnual?: (ctx: CtxAno) => string | null;
  premissa?: boolean;
  fmt?: string;
  destaque?: boolean;
  subtotal?: boolean;
  nota?: string;
}

interface CtxMes {
  c: string;            // coluna deste mês
  ant: string | null;   // coluna do mês anterior (null no 1º mês da série)
  mesmoMesAnoAnt: string | null; // coluna do MESMO mês do ano anterior
  fy: string;           // coluna do consolidado ANUAL deste ano (onde vivem as premissas)
  m: number;            // 0..11
  y: number;            // índice do ano
  L: (o: number) => number;
  F: (o: number) => number;
  B: (o: number) => number;
  P: (i: number) => string;
  S: (m: number) => string; // sazonalidade do mês
  totalSazo: string;
  hist: (aba: string, rotulo: string) => string; // valor ANUAL extraído deste ano
  histAnoAnt: (aba: string, rotulo: string) => string;
}

interface CtxAno {
  fy: string;
  // O exercício deste bloco no momento da EXPORTAÇÃO. É o que permite decidir
  // na geração o que só o arquivo saberia depois (ex.: se o Focus cobre este
  // ano). Continua sendo uma foto: a célula do exercício é editável.
  ano: number;
  primeiroMes: string;
  ultimoMes: string;
  fyAnt: string | null;
  L: (o: number) => number;
  F: (o: number) => number;
  B: (o: number) => number;
}

const MESES_PT = ["Jan", "Fev", "Mar", "Abr", "Mai", "Jun", "Jul", "Ago", "Set", "Out", "Nov", "Dez"];

export function construirAbaModelagem(
  workbook: ExcelJS.Workbook,
  caso: { nome: string },
  entidadeSugerida: string,
  entidadesDisponiveis: string[],
  anosHistoricos: number[],
  anosProjetados: number,
  macro: RefsMacro | null,
): ExcelJS.Worksheet {
  const sheet = workbook.addWorksheet(ABA_MODELAGEM, {
    views: [{ state: "frozen", xSplit: 2, ySplit: 11 }],
  });

  const primeiroAno = anosHistoricos[0] ?? new Date().getFullYear() - 1;
  const ultimoReal = anosHistoricos[anosHistoricos.length - 1] ?? primeiroAno;
  const nHist = Math.max(anosHistoricos.length, 1);
  const nAnos = nHist + anosProjetados;

  // Layout: por ano, 12 colunas mensais + 1 coluna de consolidado anual.
  const COLS_POR_ANO = 13;
  const idxMes = (y: number, m: number) => 3 + y * COLS_POR_ANO + m;
  const idxFY = (y: number) => 3 + y * COLS_POR_ANO + 12;
  const cm = (y: number, m: number) => sheet.getColumn(idxMes(y, m)).letter;
  const cfy = (y: number) => sheet.getColumn(idxFY(y)).letter;

  let refEntidade = "$C$3";
  let refCorte = "$C$4";
  let linhaAno = 8;
  let linhaData = 9;

  sheet.getColumn(1).width = 52;
  sheet.getColumn(2).width = 11;
  for (let y = 0; y < nAnos; y++) {
    for (let m = 0; m < 12; m++) sheet.getColumn(idxMes(y, m)).width = 12;
    sheet.getColumn(idxFY(y)).width = 15;
  }

  const linha = (rotulo: string, unidade = "") => sheet.addRow([rotulo, unidade]);
  const marcarInput = (cell: ExcelJS.Cell) => {
    cell.fill = INPUT_FILL;
    cell.border = INPUT_BORDER;
  };
  // ---- Cabeçalho -----------------------------------------------------------
  const tit = linha(`MODELAGEM — ${caso.nome}`);
  tit.font = { bold: true, size: 14 };
  linha("");

  const rEnt = linha("Entidade modelada", "input");
  refEntidade = `$C$${rEnt.number}`;
  rEnt.getCell(3).value = entidadeSugerida;
  marcarInput(rEnt.getCell(3));
  rEnt.getCell(1).font = TOTAL_FONT;
  if (entidadesDisponiveis.length > 0) {
    rEnt.getCell(3).dataValidation = {
      type: "list", allowBlank: false, showErrorMessage: true,
      formulae: [`"${entidadesDisponiveis.join(",").replace(/"/g, "'")}"`],
      errorTitle: "Entidade desconhecida",
      error: "Escolha uma das entidades presentes nas abas de dados deste arquivo.",
    };
  }
  rEnt.getCell(3).note = comoNota(
    "A empresa modelada. Todo o modelo é recalculado a partir desta célula — nenhuma outra "
    + "precisa ser tocada para trocar de empresa.",
  );

  const rCorte = linha("Último exercício realizado", "input");
  refCorte = `$C$${rCorte.number}`;
  rCorte.getCell(3).value = ultimoReal;
  marcarInput(rCorte.getCell(3));
  rCorte.getCell(1).font = TOTAL_FONT;
  rCorte.getCell(3).note = comoNota(
    "Exercícios até este ano puxam o número REAL das abas de dados (distribuído nos meses pela "
    + "sazonalidade abaixo); os seguintes são projetados pelas premissas. Mover esta célula move "
    + "o modelo inteiro, inclusive o sombreado das colunas projetadas.",
  );

  const rEscala = linha("Escala dos valores");
  rEscala.getCell(3).value = "conforme os documentos (ver aba Resumo)";
  rEscala.getCell(3).font = { italic: true, size: 9, color: { argb: "FF64748B" } };
  linha("");

  // ---- Timeline ------------------------------------------------------------
  const rAno = linha("Exercício");
  linhaAno = rAno.number;
  // Só o PRIMEIRO ano é digitado; cada janeiro seguinte deriva do anterior, e
  // todas as demais colunas do ano (meses 2..12 e o FY) apontam para o janeiro
  // do seu próprio ano. Uma célula comanda a linha do tempo inteira.
  sheet.getRow(linhaAno).getCell(idxMes(0, 0)).value = primeiroAno;
  marcarInput(sheet.getRow(linhaAno).getCell(idxMes(0, 0)));
  for (let y = 0; y < nAnos; y++) {
    if (y > 0) {
      sheet.getRow(linhaAno).getCell(idxMes(y, 0)).value = { formula: `${cm(y - 1, 0)}${linhaAno}+1` };
    }
    for (let m = 1; m < 12; m++) {
      sheet.getRow(linhaAno).getCell(idxMes(y, m)).value = { formula: `${cm(y, 0)}${linhaAno}` };
    }
    sheet.getRow(linhaAno).getCell(idxFY(y)).value = { formula: `${cm(y, 0)}${linhaAno}` };
  }
  rAno.font = TOTAL_FONT;
  rAno.eachCell((c) => { c.fill = HEADER_FILL; c.alignment = { horizontal: "center" }; });
  marcarInput(sheet.getRow(linhaAno).getCell(idxMes(0, 0)));

  const rData = linha("Período");
  linhaData = rData.number;
  for (let y = 0; y < nAnos; y++) {
    for (let m = 0; m < 12; m++) {
      const cell = sheet.getRow(linhaData).getCell(idxMes(y, m));
      cell.value = `${MESES_PT[m]}`;
      cell.alignment = { horizontal: "center" };
      cell.font = { size: 9 };
    }
    const fy = sheet.getRow(linhaData).getCell(idxFY(y));
    fy.value = { formula: `"FY"&${cm(y, 0)}${linhaAno}` };
    fy.font = { bold: true };
    fy.alignment = { horizontal: "center" };
    fy.fill = ANALISE_HEADER_FILL;
  }

  const rTipo = linha("Tipo");
  for (let y = 0; y < nAnos; y++) {
    for (let m = 0; m < 12; m++) {
      const cell = sheet.getRow(rTipo.number).getCell(idxMes(y, m));
      cell.value = { formula: `IF(${cm(y, 0)}${linhaAno}<=${refCorte},"Real","Projetado")` };
      cell.alignment = { horizontal: "center" };
    }
    const fy = sheet.getRow(rTipo.number).getCell(idxFY(y));
    fy.value = { formula: `IF(${cm(y, 0)}${linhaAno}<=${refCorte},"Real","Projetado")` };
    fy.alignment = { horizontal: "center" };
  }
  rTipo.font = { italic: true, size: 9, color: { argb: "FF64748B" } };

  const rCob = linha("Dado encontrado");
  for (let y = 0; y < nAnos; y++) {
    const cell = sheet.getRow(rCob.number).getCell(idxFY(y));
    const chave = `${refEntidade}&" — "&${cm(y, 0)}${linhaAno}`;
    cell.value = {
      formula: `IF(${cm(y, 0)}${linhaAno}>${refCorte},"projetado",`
        + `IF(ISNUMBER(MATCH(${chave},'Balanço'!$B$1:$BZ$1,0)),"Balanço+",`
        + `IF(ISNUMBER(MATCH(${chave},'DRE'!$B$1:$BZ$1,0)),"só DRE","SEM DADO")))`,
    };
    cell.alignment = { horizontal: "center" };
    cell.font = { italic: true, size: 9 };
  }
  rCob.getCell(1).note = comoNota(
    "\"SEM DADO\" num exercício histórico significa que não existe coluna dessa entidade nesse ano "
    + "nas abas de dados — o modelo mostra zeros ali porque o documento não foi entregue ou não "
    + "foi extraído, não porque a empresa vale zero.",
  );
  linha("");

  // ---- Blocos --------------------------------------------------------------
  const bloco = (titulo: string) => {
    const r = linha(titulo);
    r.font = BLOCO_FONT;
    for (let i = 1; i <= 2 + nAnos * COLS_POR_ANO; i++) r.getCell(i).fill = BLOCO_FILL;
    return r;
  };

  const linhasDeValor: number[] = [];
  let rSazo = 0;
  let rPremissas = 0;

  const S = (m: number) => `$${sheet.getColumn(3 + m).letter}$${rSazo}`;
  const totalSazo = () => `SUM($${sheet.getColumn(3).letter}$${rSazo}:$${sheet.getColumn(14).letter}$${rSazo})`;
  const P = (i: number, y: number) => `${cfy(y)}$${rPremissas + i}`;

  const escrever = (defs: LinhaModelo[], base: { L: (o: number) => number; F: (o: number) => number; B: (o: number) => number }) => {
    for (const d of defs) {
      const r = linha(d.rotulo, d.unidade ?? "");
      linhasDeValor.push(r.number);
      for (let y = 0; y < nAnos; y++) {
        // --- 12 células mensais ---
        if (d.mensal) {
          for (let m = 0; m < 12; m++) {
            const cell = r.getCell(idxMes(y, m));
            const ant = m > 0 ? cm(y, m - 1) : (y > 0 ? cm(y - 1, 11) : null);
            const ctx: CtxMes = {
              c: cm(y, m), ant, mesmoMesAnoAnt: y > 0 ? cm(y - 1, m) : null,
              fy: cfy(y), m, y, ...base,
              P: (i) => P(i, y), S, totalSazo: totalSazo(),
              hist: (aba, rot) => buscaNaAba(workbook, aba, rot, `${refEntidade}&" — "&${cm(y, 0)}$${linhaAno}`),
              histAnoAnt: (aba, rot) => buscaNaAba(workbook, aba, rot, `${refEntidade}&" — "&(${cm(y, 0)}$${linhaAno}-1)`),
            };
            cell.value = { formula: d.mensal(ctx) };
            cell.numFmt = d.fmt ?? VALOR_NUM_FMT;
            if (d.premissa) marcarInput(cell);
          }
        }
        // --- consolidado anual ---
        const fyCell = r.getCell(idxFY(y));
        const ctxAno: CtxAno = {
          fy: cfy(y), ano: primeiroAno + y, primeiroMes: cm(y, 0), ultimoMes: cm(y, 11),
          fyAnt: y > 0 ? cfy(y - 1) : null, ...base,
        };
        if (d.notaAnual) {
          const n = d.notaAnual(ctxAno);
          if (n) fyCell.note = comoNota(n);
        }
        if (d.anual) {
          // `null` = em branco DE PROPÓSITO (ver LinhaModelo.anual). Não é o
          // mesmo que "não tem regra anual": a célula segue pintada de input,
          // com a nota dizendo o que falta, e o humano digita por cima.
          const f = d.anual(ctxAno);
          if (f !== null) fyCell.value = { formula: f };
        } else if (d.premissa) {
          // premissa vive NA coluna anual: é anual por natureza
        } else if (d.consolida === "estoque") {
          fyCell.value = { formula: `${cm(y, 11)}${r.number}` };
        } else if (d.consolida === "inicial") {
          fyCell.value = { formula: `${cm(y, 0)}${r.number}` };
        } else if (d.mensal) {
          fyCell.value = { formula: `SUM(${cm(y, 0)}${r.number}:${cm(y, 11)}${r.number})` };
        }
        fyCell.numFmt = d.fmt ?? VALOR_NUM_FMT;
        fyCell.font = { bold: true };
        if (!d.premissa) fyCell.fill = ANALISE_HEADER_FILL;
        if (d.premissa) marcarInput(fyCell);
      }
      if (d.destaque) {
        r.font = TOTAL_FONT;
        r.getCell(1).border = THIN_TOP_BORDER;
      }
      if (d.nota) r.getCell(1).note = comoNota(d.nota);
    }
  };

  const nada = { L: () => 0, F: () => 0, B: () => 0 };

  // ======================= SAZONALIDADE ====================================
  bloco("SAZONALIDADE — como o ano se distribui nos meses (histórico e projeção)");
  {
    const r = linha("Peso do mês", "% do ano");
    rSazo = r.number;
    linhasDeValor.push(r.number);
    for (let m = 0; m < 12; m++) {
      const cell = r.getCell(3 + m);
      cell.value = 1 / 12;
      cell.numFmt = PCT_FMT;
      marcarInput(cell);
    }
    r.getCell(1).note = comoNota(
      "Os 12 pesos valem para TODOS os anos: é o vetor que distribui o número ANUAL extraído "
      + "(as demonstrações são anuais — não existe balanço mensal para extrair) e que dá forma à "
      + "projeção. Padrão 1/12: distribuição uniforme, a hipótese mais neutra possível. Se o "
      + "mandato tem sazonalidade conhecida, digite-a aqui — os pesos NÃO precisam somar 100%, "
      + "o modelo normaliza pela soma. Nada aqui é observação: é distribuição declarada.",
    );
    const chk = linha("↳ soma dos pesos", "confere");
    chk.getCell(3).value = { formula: totalSazo() };
    chk.getCell(3).numFmt = PCT_FMT;
    chk.font = { italic: true, size: 9, color: { argb: "FF64748B" } };
  }
  linha("");

  // ======================= PREMISSAS =======================================
  // Ficam na COLUNA ANUAL de cada exercício: são premissas de ano, e as células
  // mensais leem a do seu próprio ano. Uma premissa por mês (60 células por
  // linha) seria impossível de operar e é o oposto de "pronto para modelar".
  bloco("PREMISSAS — uma por exercício, na coluna FY. Digite por cima para simular");
  rPremissas = sheet.rowCount + 1;

  const recCorte = buscaNaAba(workbook, "DRE", "Receita Líquida", `${refEntidade}&" — "&${refCorte}`);
  const recAnterior = buscaNaAba(workbook, "DRE", "Receita Líquida", `${refEntidade}&" — "&(${refCorte}-1)`);
  const noCorte = (aba: string, rot: string) => buscaNaAba(workbook, aba, rot, `${refEntidade}&" — "&${refCorte}`);

  escrever([
    { rotulo: "Inflação esperada (IPCA — Focus)", premissa: true, fmt: PCT_FMT, unidade: "% a.a.",
      anual: (a) => premissaDoFocus(macro, "IPCA", a.ano, `${a.fy}$${linhaAno}`),
      notaAnual: (a) => notaDoFocus(macro, "IPCA", a.ano, "inflação"),
      nota: "Mediana das expectativas de mercado para o ANO desta coluna (aba Macro, Boletim "
        + "Focus/BCB). Não é a média histórica: média do passado calibra, não prevê. Célula EM "
        + "BRANCO significa que o Focus não cobre aquele exercício — a nota da célula diz qual "
        + "é a cobertura publicada, e a linha 'cobertura do Focus' confere isso a cada recálculo." },
    { rotulo: "Juro esperado (Selic — Focus)", premissa: true, fmt: PCT_FMT, unidade: "% a.a.",
      anual: (a) => premissaDoFocus(macro, "SELIC", a.ano, `${a.fy}$${linhaAno}`),
      notaAnual: (a) => notaDoFocus(macro, "SELIC", a.ano, "juro"),
      nota: "Precifica o custo da dívida. A conversão para o mês é GEOMÉTRICA — (1+i)^(1/12)−1, "
        + "não i/12: dividir por 12 subestima o juro composto. Em branco, o bloco de dívida cobra "
        + "juro ZERO — é a premissa mais cara de deixar vazia." },
    { rotulo: "Parcela onerosa do passivo", premissa: true, fmt: PCT_FMT, unidade: "% do passivo",
      anual: () => "0",
      nota: "Quanto do passivo paga juro (empréstimos, financiamentos, debêntures). O export "
        + "classifica por SEÇÃO contábil e não isola dívida onerosa — este número sai do Mapa da "
        + "Dívida. Em 0, a projeção não cobra juro nenhum." },
    { rotulo: "Crescimento REAL da receita (acima da inflação)", premissa: true, fmt: PCT_FMT,
      unidade: "% a.a.",
      anual: (a) => `IFERROR((1+IFERROR(${recCorte}/${recAnterior}-1,0))/(1+${a.fy}$${rPremissas})-1,0)`,
      nota: "O crescimento NOMINAL projetado é (1+IPCA)×(1+real)−1. Separar os dois é o que "
        + "responde 'a empresa cresce acima ou abaixo da inflação?'. Padrão: o crescimento "
        + "observado entre os dois últimos exercícios reais, deflacionado." },
    { rotulo: "Margem bruta ALVO", premissa: true, fmt: PCT_FMT, unidade: "% da RL",
      nota: "Rótulo distinto do da DRE de propósito: num modelo que vai ser auditado, duas "
        + "linhas com o mesmo nome fazem quem confere (e quem escreve fórmula) apontar para a "
        + "errada. Esta é a PREMISSA; a margem realizada é calculada lá embaixo.",
      anual: () => `IFERROR(${noCorte("DRE", "Lucro Bruto")}/${recCorte},0)` },
    { rotulo: "SG&A sobre receita líquida", premissa: true, fmt: PCT_FMT, unidade: "% da RL",
      anual: () => `IFERROR((${noCorte("DRE", "Lucro Bruto")}-${noCorte("DRE", "Resultado Operacional (EBIT)")})/${recCorte},0)` },
    { rotulo: "Depreciação e amortização", premissa: true, fmt: PCT_FMT, unidade: "% da RL",
      anual: () => "0",
      nota: "Sem padrão derivável: a DRE brasileira raramente isola D&A (vem das notas ou do "
        + "fluxo). Fica 0 — lacuna visível — até você preencher." },
    { rotulo: "Outras receitas/despesas financeiras", premissa: true, fmt: PCT_FMT, unidade: "% da RL",
      anual: () => `IFERROR((${noCorte("DRE", "Resultado Operacional (EBIT)")}-${noCorte("DRE", "Resultado Antes dos Tributos")})/${recCorte},0)`,
      nota: "A parcela do resultado financeiro que NÃO é juro de dívida (tarifas, variação "
        + "cambial, descontos). O juro da dívida é calculado à parte, pela Selic." },
    { rotulo: "Alíquota efetiva de tributos sobre o lucro", premissa: true, fmt: PCT_FMT, unidade: "%",
      anual: () => `IFERROR((${noCorte("DRE", "Resultado Antes dos Tributos")}-${noCorte("DRE", "Lucro/Prejuízo Líquido do Exercício")})/MAX(1,${noCorte("DRE", "Resultado Antes dos Tributos")}),0)` },
    { rotulo: "Capex", premissa: true, fmt: PCT_FMT, unidade: "% da RL",
      anual: () => `IFERROR(-${noCorte("Fluxo de Caixa", "Caixa Líquido das Atividades de Investimento")}/${recCorte},0)` },
    { rotulo: "Prazo médio de recebimento", premissa: true, fmt: "0", unidade: "dias",
      anual: () => "0",
      nota: "Dias de receita parados em clientes. Move o contas a receber e, por consequência, o "
        + "caixa: é o principal driver de capital de giro num turnaround." },
    { rotulo: "Prazo médio de pagamento", premissa: true, fmt: "0", unidade: "dias",
      anual: () => "0",
      nota: "Dias de custo financiados por fornecedores. Alongar prazo gera caixa — e é uma das "
        + "primeiras alavancas de uma renegociação." },
    { rotulo: "Prazo médio de estoque", premissa: true, fmt: "0", unidade: "dias",
      anual: () => "0" },
    { rotulo: "Captação (+) / amortização (−) de dívida no ano", premissa: true, unidade: "R$/ano",
      anual: () => "0",
      nota: "Valor absoluto por ano, distribuído nos 12 meses pela sazonalidade. Captação e "
        + "amortização são decisão do plano, não extrapolação do passado." },
    { rotulo: "Aporte (+) / distribuição (−) de sócios no ano", premissa: true, unidade: "R$/ano",
      anual: () => "0" },
  ], nada);

  const PR = {
    ipca: 0, selic: 1, parcelaOnerosa: 2, crescReal: 3, margemBruta: 4, sga: 5, depreciacao: 6,
    outrasFin: 7, aliquota: 8, capex: 9, pmr: 10, pmp: 11, pme: 12, divida: 13, socios: 14,
  } as const;

  // ---- Cobertura do Focus: a conferência que acompanha a edição -------------
  // Fica FORA do bloco de premissas de propósito: `P(i)` endereça as premissas
  // por deslocamento a partir de `rPremissas`, e uma linha inserida no meio
  // deslocaria todas as fórmulas do modelo em silêncio. A linha em branco
  // ENCERRA o bloco — é o que separa premissa (o que se digita) de conferência
  // (o que o arquivo responde), inclusive para quem conta as premissas.
  linha("");
  //
  // Por que existir, já que as células vazias têm nota: a nota é do momento da
  // exportação. O exercício é INPUT — mover "Último exercício realizado" ou o
  // primeiro ano remapeia as colunas, e a nota fica velha sem avisar. Esta
  // linha é fórmula: ela responde sobre o ano que está na coluna AGORA.
  {
    const rCob = linha("↳ cobertura do Focus (IPCA / Selic)", "confere");
    rCob.font = { italic: true, size: 9, color: { argb: "FF64748B" } };
    for (let y = 0; y < nAnos; y++) {
      const cell = rCob.getCell(idxFY(y));
      const colAno = `${cfy(y)}$${linhaAno}`;
      cell.value = macro
        ? { formula: `${coberturaFocus(macro, "IPCA", colAno)}&" / "&${coberturaFocus(macro, "SELIC", colAno)}` }
        : "sem índice macro";
      cell.alignment = { horizontal: "center" };
      cell.font = { italic: true, size: 9 };
    }
    rCob.getCell(1).note = comoNota(
      "\"SEM FOCUS\" quer dizer que o Boletim Focus carregado neste arquivo não tem expectativa "
      + "para o exercício desta coluna — a premissa acima fica EM BRANCO e o modelo projeta como "
      + "se inflação (ou juro) fosse zero naquele ano. Não é opinião do mercado: é ausência. "
      + "Digite a premissa à mão ou rode a coleta macro para um horizonte que cubra estes anos.",
    );
  }

  // O aviso de ANTES DE ABRIR A PLANILHA: quem exporta precisa saber que a
  // projeção saiu sem inflação e sem juro, e a nota de uma célula não conta
  // isso — ela só é lida por quem já foi até lá.
  {
    const projetados = Array.from({ length: nAnos }, (_, y) => primeiroAno + y).filter((a) => a > ultimoReal);
    const semFocus = projetados.filter((a) =>
      premissaDoFocus(macro, "IPCA", a, "X") === null || premissaDoFocus(macro, "SELIC", a, "X") === null);
    if (semFocus.length > 0) {
      const r = linha(
        `⚠ SEM EXPECTATIVA DO FOCUS para ${semFocus.join(", ")} — `
        + "as premissas de inflação e juro desses exercícios estão EM BRANCO, e o modelo os projeta "
        + "com inflação zero e juro zero (o bloco de dívida não cobra juro nenhum). Preencha à mão "
        + "ou amplie a coleta macro antes de usar estes números.",
      );
      r.font = { bold: true, size: 10, color: { argb: "FF991B1B" } };
      r.getCell(1).fill = DIVERGENCIA_FILL;
      linha("");
    }
  }

  // ======================= REFERÊNCIAS MACRO ================================
  //
  // POR QUE ESTE BLOCO EXISTE, e por que ele NÃO é um bloco de premissas.
  //
  // Placar medido antes de escrevê-lo: das 15 premissas, 2 leem macro (IPCA e
  // Selic do Focus); das 6 séries históricas coletadas, 0 alimentavam qualquer
  // fórmula — as 18 células de média 3a/5a/10a da aba Macro não moviam nada e
  // ninguém fora daquela aba as via.
  //
  // Mas o modelo é dirigido por PERCENTUAL DE RECEITA (CPV = RL×(1−margem
  // alvo), SG&A = % da RL) e por IPCA+crescimento real. IGP-M, PIB e câmbio
  // não têm alavanca nenhuma aqui hoje: dar alavanca a eles é escolher qual
  // índice corrige o quê, e isso é o SELETOR DE INPUTS MACRO — Etapa 5 do
  // plano do dono, ainda não construída. Ligá-los agora sem seletor seria
  // arbitrar a escolha dentro do código, onde ninguém audita.
  //
  // Decisão do dono (2026-07-31): trazer como REFERÊNCIA agora, seletor na
  // Etapa 5. Então cada linha aqui DIZ o que ela deveria dirigir e diz que
  // ainda não dirige. Uma referência que PARECE premissa é pior que nenhuma:
  // quem digita por cima de uma célula esperando o modelo responder, e ele não
  // responde, sai com um número que ele acha que testou.
  //
  // POSIÇÃO: aqui, depois das conferências — nunca dentro do bloco de
  // premissas. `P(i)` endereça premissa por deslocamento a partir de
  // `rPremissas`, e uma linha inserida lá desloca todas as fórmulas do modelo
  // em silêncio; além disso o verificador conta as premissas varrendo do
  // cabeçalho "PREMISSAS" até a primeira linha vazia.
  //
  // TUDO EM FÓRMULA lendo a aba Macro, nenhum valor escrito: a planilha tem de
  // continuar viva. Corrigir a origem (recoletar o macro, recalcular a média)
  // e ver o modelo acompanhar é a arquitetura desde a sessão 12.
  {
    bloco("REFERÊNCIAS MACRO — informam a leitura; NÃO movem o modelo sozinhas");
    const rCab = sheet.getRow(sheet.rowCount);
    rCab.getCell(1).note = comoNota(
      "Estas linhas são LEITURA, não input. Nenhuma fórmula do modelo depende delas: digitar por "
      + "cima não recalcula nada, e apagar não quebra nada. Elas existem porque o modelo hoje é "
      + "dirigido por IPCA + crescimento real + percentuais de receita, e IGP-M, PIB e câmbio não "
      + "têm alavanca nenhuma nessa mecânica — quem escolhe qual índice corrige o quê é o SELETOR "
      + "DE INPUTS MACRO, que é a Etapa 5 do plano e ainda não existe. Até lá, o número fica à "
      + "vista para quem for calibrar as premissas à mão, com a fonte declarada.",
    );

    // ---- Focus por exercício: IGP-M, PIB, câmbio ---------------------------
    // Mesma mecânica de `premissaDoFocus`/`notaDoFocus` das duas premissas que
    // já leem Focus, inclusive o tratamento de ausência da fatia 4: célula EM
    // BRANCO com nota dizendo a cobertura real, jamais 0. Um 0 aqui seria lido
    // como "o mercado espera PIB zero" — e para o câmbio seria pior ainda, um
    // dólar de R$ 0,00.
    const refsFocus: Array<{
      serie: string; rotulo: string; unidade: string; fmt: string;
      percentual: boolean; oQue: string; deveriaDirigir: string;
    }> = [
      { serie: "IGPM", rotulo: "IGP-M esperado (Focus)", unidade: "% a.a.", fmt: PCT_FMT,
        percentual: true, oQue: "inflação de contratos",
        deveriaDirigir:
          "Reajuste de aluguel e de contratos de fornecimento de longo prazo, que no Brasil são "
          + "indexados a IGP-M e não a IPCA. Hoje o modelo corrige receita e custo SÓ por IPCA "
          + "(premissa 'Inflação esperada'), então um mandato com custo majoritariamente indexado "
          + "a IGP-M está sendo projetado com o índice errado — e a diferença entre os dois passou "
          + "de 15 p.p. num único ano (2021).",
      },
      { serie: "PIB", rotulo: "PIB esperado (Focus)", unidade: "% a.a.", fmt: PCT_FMT,
        percentual: true, oQue: "crescimento da economia",
        deveriaDirigir:
          "Proxy de VOLUME: quanto da receita cresce porque a economia cresce, separado do quanto "
          + "cresce por preço. Hoje a premissa 'Crescimento REAL da receita' é derivada dos dois "
          + "últimos exercícios do próprio mandato e não olha a economia — uma empresa que só "
          + "acompanhou o PIB aparece com crescimento próprio.",
      },
      { serie: "CAMBIO_USD", rotulo: "Câmbio esperado (Focus)", unidade: "R$/US$", fmt: "0.0000",
        // NÃO é percentual: o Focus publica o câmbio como NÍVEL (R$/US$ no fim
        // do período), não como variação. Dividir por 100 daria R$ 0,054 e
        // formatar como % daria 540% — o mesmo tipo de erro de escala que
        // custou ~496x nas abas de dados na Etapa 1.
        percentual: false, oQue: "taxa de câmbio",
        deveriaDirigir:
          "Receita, custo e dívida denominados em dólar. Hoje o modelo não separa moeda: o campo "
          + "`moeda` é capturado na extração e DESCARTADO (não há coluna), então uma linha em USD "
          + "é somada a uma em BRL sem nenhuma marca. Enquanto isso não mudar, esta linha é a "
          + "única menção a câmbio no modelo.",
      },
    ];

    for (const r of refsFocus) {
      // O rótulo é o fixo daqui, não o `nomeDe` da aba Macro: ali o nome é o da
      // SÉRIE ("Câmbio R$/US$ (venda, fim de período)"); aqui a linha precisa
      // dizer que é EXPECTATIVA e de quem — "(Focus)" é a metade que importa.
      const row = linha(`↳ ${r.rotulo}`, r.unidade);
      row.font = { italic: true, size: 9, color: { argb: "FF334155" } };
      for (let y = 0; y < nAnos; y++) {
        const cell = row.getCell(idxFY(y));
        const ano = primeiroAno + y;
        const colAno = `${cfy(y)}$${linhaAno}`;
        const f = r.percentual
          ? premissaDoFocus(macro, r.serie, ano, colAno)
          : (macro ? focusMacro(macro, r.serie, ano, colAno) : null);
        if (f !== null) {
          cell.value = { formula: f };
        } else {
          const n = notaDoFocus(macro, r.serie, ano, r.oQue);
          if (n) cell.note = comoNota(n);
        }
        cell.numFmt = r.fmt;
        cell.alignment = { horizontal: "center" };
      }
      row.getCell(1).note = comoNota(
        `FONTE: mediana das expectativas de mercado (Boletim Focus/BCB) para o exercício de cada `
        + `coluna — a mesma linha da aba ${ABA_MACRO}, lida por fórmula (INDEX/MATCH), não copiada.\n\n`
        + `O QUE ESTA LINHA DEVERIA DIRIGIR: ${r.deveriaDirigir}\n\n`
        + "HOJE ELA NÃO DIRIGE NADA. Quem escolhe qual índice corrige o quê é o seletor de inputs "
        + "macro (Etapa 5), que ainda não foi construído. Célula em branco significa que o Focus "
        + "não cobre aquele exercício — a nota da própria célula diz qual é a cobertura publicada.",
      );
    }

    // ---- Médias históricas 3a/5a/10a --------------------------------------
    // Escalares: não variam por exercício. Vão nas três primeiras colunas do
    // bloco com um sub-cabeçalho explícito, do mesmo jeito que "↳ soma dos
    // pesos" já usa a coluna 3 para um escalar. A nota do sub-cabeçalho diz
    // que aquelas colunas NÃO são meses aqui — o painel congelado no topo
    // continua exibindo "jan/fev/mar" e essa colisão precisa estar declarada,
    // não deixada para o leitor descobrir.
    if (macro && macro.mediaDe.size > 0) {
      const janelas = macro.janelasMedia;
      const subCab = linha("↳ médias históricas (média GEOMÉTRICA dos exercícios completos)", "");
      subCab.font = { bold: true, size: 9, color: { argb: "FF334155" } };
      janelas.forEach((j, k) => {
        const c = subCab.getCell(3 + k);
        c.value = `Média ${j}a`;
        c.font = { bold: true, size: 9 };
        c.alignment = { horizontal: "center" };
        c.fill = ANALISE_HEADER_FILL;
      });
      subCab.getCell(1).note = comoNota(
        "ATENÇÃO À LEITURA DAS COLUNAS: as três células com valor abaixo estão nas colunas que o "
        + "painel congelado no topo rotula como jan/fev/mar. Aqui elas NÃO são meses — são as "
        + "janelas 3a / 5a / 10a, como diz o sub-cabeçalho desta linha. O resto do bloco (as três "
        + "linhas do Focus acima) usa as colunas FY normalmente.\n\n"
        + "MÉDIA GEOMÉTRICA ((Π(1+i))^(1/n) − 1), não aritmética: taxa se compõe, e a aritmética "
        + "daria outro número que erra mais a cada ano do horizonte. A janela usa os últimos N "
        + `exercícios COMPLETOS da aba ${ABA_MACRO}, nomeados um a um — o ano corrente, sempre `
        + "parcial, não entra.",
      );

      for (const [serie, ref] of macro.mediaDe) {
        const row = linha(`   ↳ ${macro.nomeDe.get(serie) ?? serie}`, "% a.a.");
        row.font = { italic: true, size: 9, color: { argb: "FF334155" } };
        ref.colunas.forEach((col, k) => {
          const cell = row.getCell(3 + k);
          // O `IF(...="","",...)` não é decoração. A célula de origem na aba
          // Macro fica LITERALMENTE VAZIA quando não há N exercícios completos
          // (a fatia 3a deixou assim de propósito, com a nota dizendo quantos
          // há). Uma referência crua a célula vazia vale 0 no Excel, e este
          // bloco publicaria "0,0%" como média de 10 anos do IPCA — ausência
          // apresentada como medição, que é exatamente o defeito da fatia 4
          // reencenado num lugar novo.
          cell.value = {
            formula: `IF('${ABA_MACRO}'!${col}${ref.linha}="","",'${ABA_MACRO}'!${col}${ref.linha})`,
          };
          cell.numFmt = PCT_FMT;
          cell.alignment = { horizontal: "center" };
          cell.note = comoNota(
            `Média geométrica de ${janelas[k]} exercícios completos da série ${serie}, calculada na `
            + `aba ${ABA_MACRO} e lida daqui por fórmula. EM BRANCO significa que a base não tem `
            + `${janelas[k]} exercícios completos — a nota da célula de origem, na aba ${ABA_MACRO}, `
            + "diz quantos existem e quais são. Em branco NÃO é zero.",
          );
        });
        row.getCell(1).note = comoNota(
          `FONTE: histórico coletado (BCB/SGS e IBGE/SIDRA) e agregado por exercício na aba `
          + `${ABA_MACRO}.\n\n`
          + "O QUE ESTA LINHA DEVERIA DIRIGIR: calibrar a premissa do exercício que o Focus NÃO "
          + "cobre. Os exercícios do modelo derivam do histórico DESTE mandato — com demonstrações "
          + "antigas, o horizonte projetado fica atrás do horizonte que o Focus publica, e hoje "
          + "essas colunas ficam em branco (ver a linha 'cobertura do Focus' acima). A média "
          + "histórica é o candidato natural a preencher, e é uma ESCOLHA: histórico calibra, não "
          + "prevê.\n\n"
          + "HOJE ELA NÃO DIRIGE NADA — nenhuma premissa lê esta célula. Ligar média histórica a "
          + "premissa é o seletor de inputs macro (Etapa 5).",
        );
      }
    }
    linha("");
  }

  // ======================= DÍVIDA ==========================================
  // Vem ANTES da DRE de propósito: o juro do mês nasce do saldo de dívida do mês
  // anterior, e a DRE precisa dele. Assim não há referência para frente — nem no
  // código, nem na planilha.
  bloco("DÍVIDA ONEROSA");
  const rDiv = sheet.rowCount + 1;
  const D = (o: number) => rDiv + o;
  const selicMes = (y: number) => `((1+${P(PR.selic, y)})^(1/12)-1)`;
  escrever([
    { rotulo: "Saldo inicial", consolida: "inicial",
      // No HISTÓRICO a dívida segue o passivo extraído daquele ano (a empresa
      // tinha a dívida que tinha — não faz sentido rolar uma estimativa por
      // cima de um balanço que existe). Só na PROJEÇÃO o saldo rola.
      mensal: (x) => `IF(${x.c}$${linhaAno}<=${refCorte},`
        + `(${x.hist("Balanço", "Passivo Circulante")}+${x.hist("Balanço", "Passivo Não Circulante")})`
        + `*${x.P(PR.parcelaOnerosa)},`
        + (x.ant ? `${x.ant}${D(4)})` : `0)`),
      nota: "No histórico, a parcela ONEROSA do passivo daquele exercício — a premissa vale por "
        + "ano, então cada exercício pode ter um mix de dívida diferente. Na projeção o saldo "
        + "rola: fim do mês anterior = início deste." },
    { rotulo: "(+) Captação", mensal: (x) => `IF(${x.c}$${linhaAno}<=${refCorte},0,MAX(0,${x.P(PR.divida)})*${x.S(x.m)}/${x.totalSazo})` },
    { rotulo: "(−) Amortização", mensal: (x) => `IF(${x.c}$${linhaAno}<=${refCorte},0,MIN(0,${x.P(PR.divida)})*${x.S(x.m)}/${x.totalSazo})` },
    { rotulo: "Juros do mês", destaque: true,
      mensal: (x) => `-${x.c}${D(0)}*${selicMes(x.y)}`,
      nota: "Juro sobre o saldo INICIAL do mês, à Selic esperada convertida geometricamente: "
        + "(1+i)^(1/12)−1. Dividir a taxa anual por 12 subestimaria o juro composto — num saldo "
        + "de dezenas de milhões, a diferença é material." },
    { rotulo: "Saldo final", destaque: true, consolida: "estoque",
      mensal: (x) => `${x.c}${D(0)}+${x.c}${D(1)}+${x.c}${D(2)}` },
  ], nada);
  linha("");

  // ======================= DRE =============================================
  bloco("DEMONSTRAÇÃO DE RESULTADO");
  const rDRE = sheet.rowCount + 1;
  const L = (o: number) => rDRE + o;
  // Histórico distribuído: valor ANUAL extraído × peso do mês ÷ soma dos pesos.
  // A normalização pela soma é o que permite ao usuário digitar pesos em
  // qualquer escala (1..12, 100..) sem quebrar a amarração com o ano.
  const dist = (x: CtxMes, anual: string) => `${anual}*${x.S(x.m)}/${x.totalSazo}`;
  escrever([
    { rotulo: "Receita Líquida", destaque: true,
      mensal: (x) => `IF(${x.c}$${linhaAno}<=${refCorte},${dist(x, x.hist("DRE", "Receita Líquida"))},`
        + (x.mesmoMesAnoAnt
          ? `${x.mesmoMesAnoAnt}${L(0)}*(1+${x.P(PR.ipca)})*(1+${x.P(PR.crescReal)}))`
          : `${dist(x, x.hist("DRE", "Receita Líquida"))})`),
      nota: "Projeção sobre o MESMO MÊS do ano anterior × (1+IPCA) × (1+crescimento real) — "
        + "assim a sazonalidade se propaga sozinha, em vez de ser reaplicada." },
    { rotulo: "(−) Custo dos produtos/serviços vendidos",
      mensal: (x) => `IF(${x.c}$${linhaAno}<=${refCorte},`
        + `${dist(x, `(${x.hist("DRE", "Lucro Bruto")}-${x.hist("DRE", "Receita Líquida")})`)},`
        + `-${x.c}${L(0)}*(1-${x.P(PR.margemBruta)}))` },
    { rotulo: "Lucro Bruto", destaque: true, mensal: (x) => `${x.c}${L(0)}+${x.c}${L(1)}` },
    { rotulo: "Margem bruta", fmt: PCT_FMT,
      mensal: (x) => `IFERROR(${x.c}${L(2)}/${x.c}${L(0)},"")`,
      anual: (a) => `IFERROR(${a.fy}${L(2)}/${a.fy}${L(0)},"")`,
      nota: "No consolidado a margem é RECALCULADA sobre os agregados do ano — somar ou tirar "
        + "média de percentual mensal não dá o percentual do ano." },
    { rotulo: "(−) Despesas operacionais (SG&A)",
      mensal: (x) => `IF(${x.c}$${linhaAno}<=${refCorte},`
        + `${dist(x, `(${x.hist("DRE", "Resultado Operacional (EBIT)")}-${x.hist("DRE", "Lucro Bruto")})`)},`
        + `-${x.c}${L(0)}*${x.P(PR.sga)})` },
    { rotulo: "EBIT (resultado operacional)", destaque: true, mensal: (x) => `${x.c}${L(2)}+${x.c}${L(4)}` },
    { rotulo: "(+) Depreciação e amortização",
      mensal: (x) => `IF(${x.c}$${linhaAno}<=${refCorte},0,${x.c}${L(0)}*${x.P(PR.depreciacao)})`,
      nota: "A DRE brasileira raramente isola D&A (vem das notas ou do fluxo). No histórico fica "
        + "0 e o EBITDA iguala o EBIT — lacuna VISÍVEL, não estimativa nossa." },
    { rotulo: "EBITDA", destaque: true, mensal: (x) => `${x.c}${L(5)}+${x.c}${L(6)}` },
    { rotulo: "Margem EBITDA", fmt: PCT_FMT,
      mensal: (x) => `IFERROR(${x.c}${L(7)}/${x.c}${L(0)},"")`,
      anual: (a) => `IFERROR(${a.fy}${L(7)}/${a.fy}${L(0)},"")` },
    { rotulo: "(−) Juros sobre dívida",
      mensal: (x) => `IF(${x.c}$${linhaAno}<=${refCorte},0,${x.c}${D(3)})`,
      nota: "Projetado: o juro calculado no bloco DÍVIDA. No histórico fica em 0 e o resultado "
        + "financeiro inteiro entra na linha de baixo — o documento não separa os dois." },
    { rotulo: "(+/−) Outras receitas/despesas financeiras",
      mensal: (x) => `IF(${x.c}$${linhaAno}<=${refCorte},`
        + `${dist(x, `(${x.hist("DRE", "Resultado Antes dos Tributos")}-${x.hist("DRE", "Resultado Operacional (EBIT)")})`)},`
        + `-${x.c}${L(0)}*${x.P(PR.outrasFin)})` },
    { rotulo: "Resultado financeiro", mensal: (x) => `${x.c}${L(9)}+${x.c}${L(10)}` },
    { rotulo: "Resultado antes dos tributos", destaque: true, mensal: (x) => `${x.c}${L(5)}+${x.c}${L(11)}` },
    { rotulo: "(−) Tributos sobre o lucro",
      mensal: (x) => `IF(${x.c}$${linhaAno}<=${refCorte},`
        + `${dist(x, `(${x.hist("DRE", "Lucro/Prejuízo Líquido do Exercício")}-${x.hist("DRE", "Resultado Antes dos Tributos")})`)},`
        + `-MAX(0,${x.c}${L(12)})*${x.P(PR.aliquota)})`,
      nota: "Projeção aplica a alíquota só sobre lucro positivo — prejuízo não gera tributo a pagar." },
    { rotulo: "Lucro/Prejuízo Líquido do Exercício", destaque: true,
      mensal: (x) => `${x.c}${L(12)}+${x.c}${L(13)}` },
    { rotulo: "Margem líquida", fmt: PCT_FMT,
      mensal: (x) => `IFERROR(${x.c}${L(14)}/${x.c}${L(0)},"")`,
      anual: (a) => `IFERROR(${a.fy}${L(14)}/${a.fy}${L(0)},"")` },
  ], nada);
  linha("");

  // ======================= CAPITAL DE GIRO =================================
  // Schedule próprio (como o modelo de referência tem uma aba de Working
  // Capital): é daqui que saem TANTO a variação que entra no fluxo QUANTO os
  // saldos que aparecem no balanço. Uma fonte só para os dois — se cada um
  // calculasse o seu, eles divergiriam em silêncio.
  bloco("CAPITAL DE GIRO");
  const rWC = sheet.rowCount + 1;
  const W = (o: number) => rWC + o;
  escrever([
    { rotulo: "Contas a receber", consolida: "estoque",
      mensal: (x) => `${x.c}${L(0)}*${x.P(PR.pmr)}/30`,
      nota: "Receita do mês × prazo médio de recebimento ÷ 30. Com PMR em 0 não há contas a "
        + "receber projetadas — preencha o prazo para o giro entrar no modelo." },
    { rotulo: "Estoques", consolida: "estoque",
      mensal: (x) => `-${x.c}${L(1)}*${x.P(PR.pme)}/30` },
    { rotulo: "(−) Fornecedores", consolida: "estoque",
      mensal: (x) => `${x.c}${L(1)}*${x.P(PR.pmp)}/30` },
    { rotulo: "Necessidade de capital de giro (NCG)", destaque: true, consolida: "estoque",
      mensal: (x) => `${x.c}${W(0)}+${x.c}${W(1)}+${x.c}${W(2)}` },
    { rotulo: "(+/−) Variação da NCG no mês",
      mensal: (x) => x.ant ? `-(${x.c}${W(3)}-${x.ant}${W(3)})` : "0",
      nota: "Entra no fluxo de caixa com o sinal invertido: NCG que cresce CONSOME caixa. É a "
        + "alavanca mais rápida de um turnaround, e por isso ela é premissa e não resultado." },
  ], nada);
  linha("");

  // ======================= FLUXO DE CAIXA ==================================
  bloco("FLUXO DE CAIXA (MÉTODO INDIRETO)");
  const rFC = sheet.rowCount + 1;
  const F = (o: number) => rFC + o;
  escrever([
    { rotulo: "Lucro/Prejuízo Líquido", mensal: (x) => `${x.c}${L(14)}` },
    { rotulo: "(+) Depreciação e amortização", mensal: (x) => `${x.c}${L(6)}` },
    { rotulo: "(+) Juros (estorno da despesa)", mensal: (x) => `-${x.c}${L(9)}`,
      nota: "O lucro líquido já está LÍQUIDO de juros. Como o desembolso do juro é classificado "
        + "em Financiamento (padrão CPC 03), ele precisa ser estornado aqui — senão a mesma "
        + "despesa sai do caixa DUAS VEZES e o balanço deixa de fechar. É o erro clássico do "
        + "método indireto." },
    { rotulo: "(+/−) Variação da NCG", mensal: (x) => `${x.c}${W(4)}` },
    { rotulo: "Caixa das Atividades Operacionais", destaque: true,
      mensal: (x) => `IF(${x.c}$${linhaAno}<=${refCorte},`
        + `${dist(x, x.hist("Fluxo de Caixa", "Caixa Líquido das Atividades Operacionais"))},`
        + `${x.c}${F(0)}+${x.c}${F(1)}+${x.c}${F(2)}+${x.c}${F(3)})` },
    { rotulo: "(−) Capex", mensal: (x) => `-${x.c}${L(0)}*${x.P(PR.capex)}` },
    { rotulo: "Caixa das Atividades de Investimento", destaque: true,
      mensal: (x) => `IF(${x.c}$${linhaAno}<=${refCorte},`
        + `${dist(x, x.hist("Fluxo de Caixa", "Caixa Líquido das Atividades de Investimento"))},`
        + `${x.c}${F(5)})` },
    { rotulo: "(+) Captação de dívida", mensal: (x) => `${x.c}${D(1)}` },
    { rotulo: "(−) Amortização de dívida", mensal: (x) => `${x.c}${D(2)}` },
    { rotulo: "(−) Juros pagos", mensal: (x) => `IF(${x.c}$${linhaAno}<=${refCorte},0,${x.c}${D(3)})` },
    { rotulo: "(+/−) Aporte / distribuição de sócios",
      mensal: (x) => `IF(${x.c}$${linhaAno}<=${refCorte},0,${x.P(PR.socios)}*${x.S(x.m)}/${x.totalSazo})` },
    { rotulo: "Caixa das Atividades de Financiamento", destaque: true,
      mensal: (x) => `IF(${x.c}$${linhaAno}<=${refCorte},`
        + `${dist(x, x.hist("Fluxo de Caixa", "Caixa Líquido das Atividades de Financiamento"))},`
        + `${x.c}${F(7)}+${x.c}${F(8)}+${x.c}${F(9)}+${x.c}${F(10)})` },
    { rotulo: "Variação líquida de caixa", destaque: true,
      mensal: (x) => `${x.c}${F(4)}+${x.c}${F(6)}+${x.c}${F(11)}` },
    { rotulo: "Saldo inicial de caixa", consolida: "inicial",
      mensal: (x) => x.ant
        ? `${x.ant}${F(14)}`
        : `${x.hist("Fluxo de Caixa", "Saldo Inicial de Caixa")}` },
    { rotulo: "Saldo final de caixa", destaque: true, consolida: "estoque",
      mensal: (x) => `${x.c}${F(13)}+${x.c}${F(12)}` },
  ], nada);
  linha("");

  // ======================= BALANÇO =========================================
  bloco("BALANÇO PATRIMONIAL");
  const rBP = sheet.rowCount + 1;
  const B = (o: number) => rBP + o;
  // Estoque histórico é INTERPOLADO entre o fechamento do ano anterior e o do
  // ano corrente: dezembro cai exatamente no valor extraído (a conferência lá
  // embaixo prova) e os meses do meio ganham uma trajetória, em vez de um
  // degrau em janeiro que ninguém observou.
  const interp = (x: CtxMes, aba: string, rot: string) =>
    `(${x.histAnoAnt(aba, rot)}+(${x.hist(aba, rot)}-${x.histAnoAnt(aba, rot)})*${x.m + 1}/12)`;
  escrever([
    { rotulo: "Caixa e equivalentes", consolida: "estoque", mensal: (x) => `${x.c}${F(14)}`,
      nota: "Vem do saldo final do fluxo — é o elo que faz o balanço responder a QUALQUER "
        + "premissa: uma margem pior queima caixa e aparece aqui." },
    { rotulo: "Contas a receber", consolida: "estoque", mensal: (x) => `${x.c}${W(0)}`,
      nota: "Vem do schedule de capital de giro, e vale TAMBÉM no histórico. Zerá-lo no passado "
        + "faria os recebíveis saltarem de 0 para o valor cheio no primeiro mês projetado, sem "
        + "contrapartida no caixa — e o balanço abriria exatamente esse salto." },
    { rotulo: "Estoques", consolida: "estoque", mensal: (x) => `${x.c}${W(1)}` },
    { rotulo: "Demais ativos circulantes", consolida: "estoque",
      mensal: (x) => `IF(${x.c}$${linhaAno}<=${refCorte},`
        + `${interp(x, "Balanço", "Ativo Circulante")}-${x.c}${B(0)}-${x.c}${B(1)}-${x.c}${B(2)},`
        + `MAX(0,${x.ant ? `${x.ant}${B(3)}` : "0"}))`,
      nota: "No histórico é o resto do circulante depois do caixa (o documento não detalha "
        + "recebíveis e estoques de forma comparável entre empresas); na projeção fica constante, "
        + "porque o giro já está modelado nas linhas acima." },
    { rotulo: "Ativo Circulante", destaque: true, consolida: "estoque",
      mensal: (x) => `${x.c}${B(0)}+${x.c}${B(1)}+${x.c}${B(2)}+${x.c}${B(3)}` },
    { rotulo: "Ativo Não Circulante", consolida: "estoque",
      mensal: (x) => `IF(${x.c}$${linhaAno}<=${refCorte},${interp(x, "Balanço", "Ativo Não Circulante")},`
        + `${x.ant ? `${x.ant}${B(5)}` : interp(x, "Balanço", "Ativo Não Circulante")}`
        + `-${x.c}${F(5)}-${x.c}${L(6)})`,
      nota: "Anterior + capex − depreciação. As duas premissas movem esta linha." },
    { rotulo: "TOTAL DO ATIVO", destaque: true, consolida: "estoque",
      mensal: (x) => `${x.c}${B(4)}+${x.c}${B(5)}` },
    { rotulo: "Fornecedores", consolida: "estoque", mensal: (x) => `-${x.c}${W(2)}` },
    { rotulo: "Dívida onerosa", consolida: "estoque", mensal: (x) => `${x.c}${D(4)}` },
    { rotulo: "Demais passivos", consolida: "estoque",
      mensal: (x) => `IF(${x.c}$${linhaAno}<=${refCorte},`
        + `${interp(x, "Balanço", "Passivo Circulante")}+${interp(x, "Balanço", "Passivo Não Circulante")}`
        + `-${x.c}${B(8)}-${x.c}${B(7)},`
        + `${x.ant ? `${x.ant}${B(9)}` : "0"})` },
    { rotulo: "Passivo Total", destaque: true, consolida: "estoque",
      mensal: (x) => `${x.c}${B(7)}+${x.c}${B(8)}+${x.c}${B(9)}` },
    { rotulo: "Patrimônio Líquido", consolida: "estoque",
      mensal: (x) => `IF(${x.c}$${linhaAno}<=${refCorte},${interp(x, "Balanço", "Patrimônio Líquido")},`
        + `${x.ant ? `${x.ant}${B(11)}` : interp(x, "Balanço", "Patrimônio Líquido")}`
        + `+${x.c}${L(14)}+${x.c}${F(10)})`,
      nota: "PL projetado = PL anterior + resultado do mês + aporte/distribuição de sócios." },
    { rotulo: "TOTAL DO PASSIVO E PL", destaque: true, consolida: "estoque",
      mensal: (x) => `${x.c}${B(10)}+${x.c}${B(11)}` },
  ], nada);
  linha("");

  // ======================= INDICADORES =====================================
  bloco("INDICADORES");
  escrever([
    { rotulo: "Liquidez corrente", fmt: RATIO_FMT, consolida: "estoque",
      mensal: (x) => `IFERROR(${x.c}${B(4)}/(${x.c}${B(7)}+${x.c}${B(8)}),"")` },
    { rotulo: "Dívida líquida", consolida: "estoque",
      mensal: (x) => `${x.c}${B(8)}-${x.c}${B(0)}`,
      nota: "Agora é dívida líquida DE VERDADE: a dívida onerosa tem linha própria no modelo "
        + "(bloco DÍVIDA), então o indicador não precisa mais usar o passivo inteiro como proxy." },
    { rotulo: "Dívida líquida / EBITDA (12m)", fmt: RATIO_FMT, consolida: "formula",
      mensal: (x) => `IFERROR(${x.c}${B(8)}-${x.c}${B(0)},"")`,
      anual: (a) => `IFERROR((${a.ultimoMes}${B(8)}-${a.ultimoMes}${B(0)})/${a.fy}${L(7)},"")`,
      nota: "Alavancagem: dívida líquida do FIM do ano sobre o EBITDA ACUMULADO de 12 meses — "
        + "estoque sobre fluxo, que é como o covenant é escrito." },
    { rotulo: "Endividamento geral", fmt: PCT_FMT, consolida: "estoque",
      mensal: (x) => `IFERROR(${x.c}${B(10)}/${x.c}${B(6)},"")` },
    { rotulo: "Retorno sobre o PL (ROE)", fmt: PCT_FMT, consolida: "formula",
      mensal: (x) => `IFERROR(${x.c}${L(14)}/${x.c}${B(11)},"")`,
      anual: (a) => `IFERROR(${a.fy}${L(14)}/${a.ultimoMes}${B(11)},"")` },
    { rotulo: "Necessidade de captação (caixa negativo)", destaque: true, consolida: "estoque",
      mensal: (x) => `MAX(0,-${x.c}${B(0)})`,
      anual: (a) => `MAX(0,-MIN(${a.primeiroMes}${B(0)}:${a.ultimoMes}${B(0)}))`,
      nota: "Quanto o plano precisa levantar para o caixa não virar negativo. No consolidado é o "
        + "PIOR mês do ano, não o de dezembro: um vale de caixa em julho precisa ser financiado "
        + "mesmo que dezembro feche positivo. É o número que decide o tamanho da captação." },
  ], nada);
  linha("");

  // ======================= CONFERÊNCIAS ====================================
  // Um modelo institucional tem de provar que fecha. Estas linhas não são
  // decorativas: se qualquer uma sair de zero, o número acima não vale.
  bloco("CONFERÊNCIAS — todas têm de ficar em zero");
  escrever([
    { rotulo: "Balanço fecha (Ativo − Passivo − PL)", destaque: true, consolida: "estoque",
      mensal: (x) => `${x.c}${B(6)}-${x.c}${B(12)}`,
      nota: "No HISTÓRICO tem de ser zero: diferente disso, o dado extraído não fecha (confira a "
        + "aba Balanço). No PROJETADO, o resíduo é o desequilíbrio entre as premissas de ativo e "
        + "de passivo — e a necessidade de captação acima é quem o financia." },
    { rotulo: "Receita do ano = receita extraída", destaque: true, consolida: "formula",
      mensal: () => `""`,
      anual: (a) => `IF(${a.fy}$${linhaAno}>${refCorte},"—",ROUND(${a.fy}${L(0)}-`
        + `${buscaNaAba(workbook, "DRE", "Receita Líquida", `${refEntidade}&" — "&${a.fy}$${linhaAno}`)},2))`,
      nota: "A soma dos 12 meses distribuídos tem de dar EXATAMENTE o número anual extraído. "
        + "Diferente de zero significa que a distribuição perdeu ou criou receita — o defeito "
        + "mais perigoso de um modelo mensal construído sobre dado anual." },
    { rotulo: "Caixa do balanço = saldo final do fluxo", destaque: true, consolida: "estoque",
      mensal: (x) => `ROUND(${x.c}${B(0)}-${x.c}${F(14)},2)` },
  ], nada);

  // ---- Sombreado das colunas projetadas, por FORMATAÇÃO CONDICIONAL -------
  // Pintar por posição fixa deixaria o sombreado mentindo assim que o usuário
  // mexesse no exercício de corte. Aqui a própria cor é fórmula.
  if (linhasDeValor.length > 0) {
    const primeira = Math.min(...linhasDeValor);
    const ultima = Math.max(...linhasDeValor);
    sheet.addConditionalFormatting({
      ref: `${sheet.getColumn(3).letter}${primeira}:${sheet.getColumn(2 + nAnos * COLS_POR_ANO).letter}${ultima}`,
      rules: [{
        type: "expression", priority: 1,
        formulae: [`${sheet.getColumn(3).letter}$${linhaAno}>${refCorte}`],
        style: { fill: PROJETADO_FILL },
      }],
    });
  }
  return sheet;
}
