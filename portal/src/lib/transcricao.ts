import ExcelJS from "exceljs";
import { ORIA, fonte, preencher } from "./oria-marca";

// A PLANILHA DE TRANSCRIÇÃO HUMANA ASSISTIDA — gerar e ler, no mesmo arquivo.
//
// POR QUE AS DUAS METADES MORAM JUNTAS. O formato da planilha é um contrato entre
// quem escreve e quem lê, e as duas pontas são este sistema. Separá-las em dois
// arquivos é a receita para a coluna mudar de lugar num lado e não no outro — e o
// sintoma disso não é um erro, é uma transcrição importada com o valor na coluna
// da unidade. As constantes de layout abaixo são a única fonte da verdade.
//
// O QUE ESTA PLANILHA É. A saída do gate de captura (fechamento #2 do `Arquitetura do Sistema/1 Visão e Doutrina/01`):
// quando o arquivo não se lê e o cliente não tem outra via, o analista digita o que
// está no papel. Ela é ferramenta de MESA e não sai da casa — decisão do dono —,
// então usa o vocabulário interno (conceito da taxonomia, seção canônica) sem o
// cuidado de linguagem que a `0122` deu às perguntas ao cliente.
//
// O QUE ELA NÃO É. Um gabarito da demonstração. As linhas pré-listadas são só as
// que o Portão 1 vai COBRAR daquele tipo — três num balanço —, porque
// `taxonomia_linha_exigida` é o mínimo exigido e não a estrutura do documento do
// cliente. O resto vai em linha livre, porque só quem está com o papel na mão sabe
// o que ele tem.

/** Linha que o Portão 1 exige daquele tipo de documento (`fn_linhas_para_transcrever`). */
export type LinhaExigidaParaTranscrever = {
  conceito: string;
  rotulo: string;
  descricao: string;
  secao_canonica: string | null;
  checagem: string;
  severidade: string;
};

export type LinhaTranscrita = {
  chave: string;
  valor_num: string | null;
  valor_texto: string | null;
  unidade: string | null;
  periodo_coluna: string | null;
  entidade_coluna: string | null;
  secao_canonica: string | null;
  origem_pagina: string | null;
  ordem: number;
};

// -----------------------------------------------------------------------------
// LAYOUT — a fonte única da verdade das duas metades.
// -----------------------------------------------------------------------------
const ABA = "Transcrição";
/** Linha onde ficam os cabeçalhos de coluna. Os dados começam na seguinte. */
const LINHA_CABECALHO = 8;
/** A célula que carrega o id do documento, e o motivo dela está em `lerPlanilha`. */
const CELULA_DOC_ID = "B5";
const LINHAS_LIVRES = 60;

const COLUNAS = [
  { chave: "rotulo", titulo: "Rótulo (como está no documento)", largura: 46 },
  { chave: "valor", titulo: "Valor", largura: 16 },
  { chave: "unidade", titulo: "Unidade", largura: 12 },
  { chave: "periodo", titulo: "Período", largura: 12 },
  { chave: "entidade", titulo: "Empresa", largura: 24 },
  { chave: "secao", titulo: "Seção canônica", largura: 22 },
  { chave: "pagina", titulo: "Página", largura: 9 },
  { chave: "conceito", titulo: "Conceito exigido (não editar)", largura: 26 },
] as const;

const col = (chave: (typeof COLUNAS)[number]["chave"]) =>
  COLUNAS.findIndex((c) => c.chave === chave) + 1;

// -----------------------------------------------------------------------------
// GERAR
// -----------------------------------------------------------------------------
export function montarPlanilhaTranscricao(entrada: {
  documentoId: string;
  nomeArquivo: string;
  tipoTaxonomia: string | null;
  entidade: string | null;
  periodo: string | null;
  exigidas: LinhaExigidaParaTranscrever[];
}): ExcelJS.Workbook {
  const wb = new ExcelJS.Workbook();
  wb.creator = "Oria Partners — transcrição assistida";
  const ws = wb.addWorksheet(ABA);

  COLUNAS.forEach((c, i) => {
    ws.getColumn(i + 1).width = c.largura;
  });

  const titulo = ws.getCell("A1");
  titulo.value = "TRANSCRIÇÃO HUMANA ASSISTIDA";
  titulo.font = fonte({ bold: true, size: 12, color: { argb: ORIA.branco } });
  titulo.fill = preencher(ORIA.grafite);
  ws.mergeCells("A1:H1");

  // A INSTRUÇÃO FICA NO ARQUIVO, não só na tela que gerou o download. Quem preenche
  // pode abrir isto dias depois, ou receber por e-mail de um colega.
  const inst = ws.getCell("A2");
  inst.value =
    "Digite o que está no documento. Linha SEM valor é ignorada na importação — " +
    "então sobra em branco não estraga nada. As linhas já preenchidas abaixo são as " +
    "que o sistema vai COBRAR deste tipo de documento; o resto do documento vai nas " +
    "linhas livres, na ordem que estiver no papel.";
  inst.font = fonte({ size: 9, italic: true, color: { argb: ORIA.grafiteClaro } });
  inst.alignment = { wrapText: true, vertical: "top" };
  ws.mergeCells("A2:H3");
  ws.getRow(2).height = 30;

  ws.getCell("A5").value = "Documento (não editar):";
  ws.getCell("A5").font = fonte({ bold: true, size: 9 });
  ws.getCell(CELULA_DOC_ID).value = entrada.documentoId;
  ws.getCell(CELULA_DOC_ID).font = fonte({ size: 9, color: { argb: ORIA.grafiteClaro } });

  ws.getCell("A6").value = "Arquivo:";
  ws.getCell("A6").font = fonte({ bold: true, size: 9 });
  ws.getCell("B6").value = [
    entrada.nomeArquivo,
    entrada.tipoTaxonomia,
    entrada.entidade,
    entrada.periodo,
  ]
    .filter(Boolean)
    .join(" · ");
  ws.getCell("B6").font = fonte({ size: 9 });

  const cab = ws.getRow(LINHA_CABECALHO);
  COLUNAS.forEach((c, i) => {
    const cell = cab.getCell(i + 1);
    cell.value = c.titulo;
    cell.font = fonte({ bold: true, size: 9 });
    cell.fill = preencher(ORIA.cinza);
    cell.alignment = { wrapText: true, vertical: "middle" };
  });
  cab.height = 26;

  let linha = LINHA_CABECALHO + 1;
  for (const ex of entrada.exigidas) {
    const r = ws.getRow(linha);
    r.getCell(col("rotulo")).value = ex.rotulo;
    r.getCell(col("rotulo")).font = fonte({ bold: true });
    r.getCell(col("secao")).value = ex.secao_canonica ?? "";
    r.getCell(col("conceito")).value = ex.conceito;
    r.getCell(col("conceito")).font = fonte({ size: 8, color: { argb: ORIA.grafiteClaro } });
    // A célula de VALOR das linhas exigidas ganha o fundo de entrada — a mesma
    // gramática do arquivo entregue (`oria-marca.ts`): areia = digite aqui.
    r.getCell(col("valor")).fill = preencher(ORIA.entrada);
    r.getCell(col("valor")).note = ex.descricao;
    linha += 1;
  }

  for (let i = 0; i < LINHAS_LIVRES; i += 1) {
    ws.getRow(linha).getCell(col("valor")).fill = preencher(ORIA.entrada);
    linha += 1;
  }

  return wb;
}

// -----------------------------------------------------------------------------
// LER
// -----------------------------------------------------------------------------
export type ResultadoLeitura =
  | { ok: true; linhas: LinhaTranscrita[] }
  | { ok: false; erro: string };

/**
 * Lê a planilha preenchida. `documentoIdEsperado` é conferido contra a célula que a
 * geração gravou.
 */
export async function lerPlanilhaTranscricao(
  buffer: ArrayBuffer,
  documentoIdEsperado: string,
): Promise<ResultadoLeitura> {
  const wb = new ExcelJS.Workbook();
  try {
    await wb.xlsx.load(buffer);
  } catch {
    return {
      ok: false,
      erro:
        "Não consegui abrir o arquivo como planilha. Envie o .xlsx que o botão " +
        "“Baixar planilha” gerou, preenchido — não um PDF nem um CSV.",
    };
  }

  const ws = wb.getWorksheet(ABA) ?? wb.worksheets[0];
  if (!ws) {
    return { ok: false, erro: "A planilha está vazia — nenhuma aba com conteúdo." };
  }

  // A CONFERÊNCIA DO DOCUMENTO, e ela não é zelo burocrático. Enviar a planilha do
  // balanço da Alfa na tela do balanço da Beta é um erro plausível de alguém com
  // seis arquivos abertos — e o resultado seria uma transcrição gravada no
  // documento errado, ACEITA, com o nome de quem enviou. Um número errado que
  // ninguém vai desconfiar, porque tem autor.
  const idNaPlanilha = String(ws.getCell(CELULA_DOC_ID).value ?? "").trim();
  if (idNaPlanilha && idNaPlanilha !== documentoIdEsperado) {
    return {
      ok: false,
      erro:
        "Esta planilha foi gerada para OUTRO documento. Ela traz o identificador " +
        `${idNaPlanilha} e este documento é ${documentoIdEsperado}. Baixe a planilha ` +
        "deste documento e transcreva nela — importar aqui gravaria os números no " +
        "documento errado, já aceitos e com o seu nome.",
    };
  }
  if (!idNaPlanilha) {
    return {
      ok: false,
      erro:
        "A planilha não traz o identificador do documento na célula " +
        `${CELULA_DOC_ID}. Ela provavelmente não foi gerada pelo botão “Baixar ` +
        "planilha” — sem esse identificador não há como conferir que os números " +
        "vão para o documento certo.",
    };
  }

  const texto = (v: ExcelJS.CellValue): string | null => {
    if (v === null || v === undefined) return null;
    if (typeof v === "object" && "richText" in v) {
      return (v.richText as { text: string }[]).map((t) => t.text).join("").trim() || null;
    }
    if (typeof v === "object" && "result" in v) {
      const r = (v as { result?: unknown }).result;
      return r === null || r === undefined ? null : String(r).trim() || null;
    }
    const s = String(v).trim();
    return s === "" ? null : s;
  };

  // NÚMERO EM PT-BR, e este é o ponto em que uma leitura ingênua perde dinheiro.
  // O Excel entrega número como number quando a célula é numérica — aí é direto.
  // Quando o analista cola de um PDF, ela vem TEXTO: "1.234,56" (ponto de milhar,
  // vírgula decimal) ou "(1.234)" para negativo, que é a convenção contábil. Ler
  // "1.234,56" com parseFloat devolve 1.234 — três ordens de grandeza abaixo, e
  // plausível o bastante para passar.
  const numero = (v: ExcelJS.CellValue): string | null => {
    if (typeof v === "number") return String(v);
    const s = texto(v);
    if (s === null) return null;
    const negativoPorParenteses = /^\(.*\)$/.test(s);
    let limpo = s.replace(/[()\s]/g, "").replace(/R\$/gi, "");
    // Se tem vírgula, ela é o separador DECIMAL (convenção pt-BR) e o ponto é
    // milhar.
    if (limpo.includes(",")) {
      limpo = limpo.replace(/\./g, "").replace(",", ".");
    } else if (/^-?\d{1,3}(\.\d{3})+$/.test(limpo)) {
      // SEM VÍRGULA, MAS COM PONTO SEPARANDO GRUPOS DE EXATAMENTE TRÊS DÍGITOS: é
      // milhar, e "1.234" vale 1234.
      //
      // Este ramo nasceu de um assert que caiu: "(1.234)" voltava −1,234 em vez de
      // −1234. É o mesmo defeito do `parseFloat` um passo adiante — a regra "sem
      // vírgula, o ponto pode ser decimal" está certa para "0.75" e catastrófica
      // para "1.234", que é como um PDF brasileiro escreve mil duzentos e trinta e
      // quatro. Três ordens de grandeza, num número plausível.
      //
      // A AMBIGUIDADE É REAL E ESTA É A ESCOLHA. "1.234" pode, em teoria, ser um
      // decimal com três casas. Numa planilha em pt-BR onde o decimal se escreve
      // com vírgula, não é — e o grupo de EXATAMENTE três dígitos é o que
      // distingue: "1.5", "0.75" e "12.34" não entram aqui e seguem sendo
      // decimais, porque nenhum milhar tem um ou dois dígitos depois do ponto.
      limpo = limpo.replace(/\./g, "");
    }
    if (!/^-?\d+(\.\d+)?$/.test(limpo)) return null;
    const n = negativoPorParenteses && !limpo.startsWith("-") ? `-${limpo}` : limpo;
    return n;
  };

  const linhas: LinhaTranscrita[] = [];
  let ordem = 0;
  ws.eachRow((row, n) => {
    if (n <= LINHA_CABECALHO) return;
    const rotulo = texto(row.getCell(col("rotulo")).value);
    const bruto = row.getCell(col("valor")).value;
    const valorNum = numero(bruto);
    const valorTexto = texto(bruto);

    // LINHA SEM VALOR É IGNORADA — é o que faz sobra em branco não estragar nada, e
    // está escrito na instrução do próprio arquivo. Rótulo sem valor também sai:
    // as linhas exigidas vêm pré-preenchidas com rótulo, e importar essas como
    // linha de zero seria inventar que o documento afirma zero.
    if (valorNum === null && valorTexto === null) return;
    if (!rotulo) return;

    linhas.push({
      chave: rotulo,
      valor_num: valorNum,
      // Quando o valor não é número, o texto vai junto: "n/d", "vide nota 12" e
      // afins são informação, e descartá-los perderia o que o documento diz.
      valor_texto: valorNum === null ? valorTexto : null,
      unidade: texto(row.getCell(col("unidade")).value),
      periodo_coluna: texto(row.getCell(col("periodo")).value),
      entidade_coluna: texto(row.getCell(col("entidade")).value),
      secao_canonica: texto(row.getCell(col("secao")).value),
      origem_pagina: texto(row.getCell(col("pagina")).value),
      ordem,
    });
    ordem += 1;
  });

  if (linhas.length === 0) {
    return {
      ok: false,
      erro:
        "Nenhuma linha com valor na planilha. Preencha a coluna “Valor” — linha só " +
        "com rótulo é ignorada de propósito, para sobra em branco não virar linha " +
        "de zero.",
    };
  }

  return { ok: true, linhas };
}

export const LAYOUT_TRANSCRICAO = { ABA, LINHA_CABECALHO, CELULA_DOC_ID, COLUNAS };
