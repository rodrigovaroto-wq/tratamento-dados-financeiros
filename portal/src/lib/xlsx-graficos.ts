// GRÁFICOS NO .XLSX ENTREGUE — o que o ExcelJS não sabe fazer.
//
// POR QUE ESTE ARQUIVO EXISTE. O Modelo Base do dono
// (`docs/referencia/modelo-base.xlsx`) tem **8 gráficos**, todos de linha, todos
// na aba `Output`, alimentados por tabelas laterais da própria aba. Medido em
// `docs/referencia/MAPA_MODELO_BASE.md` §17.2. O nosso export tinha **zero**, e
// não por esquecimento: o **ExcelJS não tem API de gráfico** — nem
// `workbook.addChart` nem `worksheet.addChart` existem (conferido no runtime da
// versão 4.4.0 que está no lock, não só no `.d.ts`).
//
// Um `.xlsx` é um ZIP de XML, e gráfico é uma parte como qualquer outra. Então o
// caminho é o MESMO que este repositório já usa para ampliar a caixa das notas
// (`ampliarNotasNoBuffer` em `export.ts`): pós-processar o buffer com JSZip, que
// já vem como dependência do próprio ExcelJS. Nenhuma dependência nova.
//
// O QUE ESTE MÓDULO ESCREVE, por gráfico:
//   • `xl/charts/chartN.xml`            — o gráfico (c:lineChart, uma c:ser por série)
//   • `xl/drawings/drawingK.xml`        — a âncora na aba (twoCellAnchor + graphicFrame)
//   • `xl/drawings/_rels/drawingK.xml.rels` — o vínculo desenho → gráfico
//   • `<drawing r:id="..."/>` na aba    — e a relação correspondente no rels dela
//   • dois `Override` em `[Content_Types].xml`
//
// TRÊS ARMADILHAS QUE ESTE CÓDIGO EVITA DE PROPÓSITO, e que produzem arquivo que
// o Excel recusa a abrir (a mensagem dele é sempre a mesma, "conteúdo
// ilegível", sem dizer onde):
//
//   1. **A ordem dos elementos no XML do OOXML é NORMATIVA.** `<drawing/>` só
//      pode aparecer depois de `pageSetup`/`headerFooter` e antes de
//      `legacyDrawing`. Como o ExcelJS já emite `<legacyDrawing>` nas abas que
//      têm nota, inserir "antes de `</worksheet>`" quebraria exatamente as abas
//      comentadas — que são as nossas. Aqui a inserção é ANTES de
//      `<legacyDrawing`, quando ele existe.
//   2. **A ordem das abas não é a ordem dos `sheetN.xml`.** É a mesma armadilha
//      que fez o `docs/referencia/mapear-xlsx.py` existir. A resolução aqui é
//      `xl/workbook.xml` → `r:id` → `xl/_rels/workbook.xml.rels` → `Target`.
//   3. **Os `rId` da aba já estão ocupados.** ExcelJS cria
//      `xl/worksheets/_rels/sheetN.xml.rels` para a nota (vmlDrawing + comments).
//      Reusar um `rId` existente sequestra o vínculo da nota. Aqui o próximo id
//      é calculado lendo os que já existem.
//
// Por isso o módulo NUNCA falha em silêncio: se a parte não existir, se a aba
// não for encontrada ou se o XML não casar com o esperado, ele LANÇA. Um
// gráfico faltando é visível; um .xlsx corrompido chega ao cliente como "o
// arquivo da Oria não abre".
import JSZip from "jszip";

/** Uma série do gráfico. Os endereços são absolutos e COM nome de aba. */
export interface SerieGrafico {
  /** célula com o nome da série, ex.: `Output!$C$40`. Opcional: sem ela a legenda fica com o número. */
  refNome?: string;
  /** faixa das categorias (o eixo X), ex.: `Output!$E$9:$J$9`. */
  refCategorias: string;
  /** faixa dos valores, ex.: `Output!$E$40:$J$40`. */
  refValores: string;
  /** cor da linha em RGB de 6 dígitos, sem alfa. */
  cor: string;
  /** linha tracejada — usada para corte de covenant, que não é projeção. */
  tracejada?: boolean;
}

export interface EspecGrafico {
  /** nome EXATO da aba onde o gráfico é ancorado. */
  aba: string;
  titulo: string;
  /** âncora em índices base 0 (coluna, linha), canto superior esquerdo e inferior direito. */
  de: { col: number; linha: number };
  ate: { col: number; linha: number };
  series: SerieGrafico[];
  /** formato numérico do eixo de valores. */
  fmtValor?: string;
}

const NS_C = "http://schemas.openxmlformats.org/drawingml/2006/chart";
const NS_A = "http://schemas.openxmlformats.org/drawingml/2006/main";
const NS_R = "http://schemas.openxmlformats.org/officeDocument/2006/relationships";
const NS_XDR = "http://schemas.openxmlformats.org/drawingml/2006/spreadsheetDrawing";
const NS_PKG_REL = "http://schemas.openxmlformats.org/package/2006/relationships";
const TIPO_REL_DESENHO = "http://schemas.openxmlformats.org/officeDocument/2006/relationships/drawing";
const TIPO_REL_GRAFICO = "http://schemas.openxmlformats.org/officeDocument/2006/relationships/chart";
const CT_GRAFICO = "application/vnd.openxmlformats-officedocument.drawingml.chart+xml";
const CT_DESENHO = "application/vnd.openxmlformats-officedocument.drawing+xml";

function escapar(s: string): string {
  return s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;");
}

/**
 * Resolve nome de aba → caminho da parte, pelo `rels` (nunca por índice de
 * arquivo: `sheet3.xml` não é a terceira aba).
 */
async function parteDaAba(zip: JSZip, nome: string): Promise<string> {
  const wb = await lerParte(zip, "xl/workbook.xml");
  const rels = await lerParte(zip, "xl/_rels/workbook.xml.rels");
  const alvoPorId = new Map<string, string>();
  for (const m of rels.matchAll(/<Relationship\b[^>]*>/g)) {
    const id = /\bId="([^"]+)"/.exec(m[0])?.[1];
    const target = /\bTarget="([^"]+)"/.exec(m[0])?.[1];
    if (id && target) alvoPorId.set(id, target);
  }
  for (const m of wb.matchAll(/<sheet\b[^>]*\/>/g)) {
    const n = /\bname="([^"]*)"/.exec(m[0])?.[1];
    const rid = /\br:id="([^"]+)"/.exec(m[0])?.[1];
    if (n === undefined || !rid) continue;
    // O nome no XML vem com entidade (`&amp;` em "Revenues, COGS &amp; SG&amp;A").
    const nomeLimpo = n.replace(/&amp;/g, "&").replace(/&lt;/g, "<").replace(/&gt;/g, ">").replace(/&quot;/g, '"')
      .replace(/&apos;/g, "'");
    if (nomeLimpo !== nome) continue;
    const alvo = (alvoPorId.get(rid) ?? "").replace(/^\//, "");
    if (!alvo) break;
    return alvo.startsWith("xl/") ? alvo : `xl/${alvo}`;
  }
  throw new Error(`xlsx-graficos: aba "${nome}" não existe no workbook gerado`);
}

async function lerParte(zip: JSZip, caminho: string): Promise<string> {
  const f = zip.file(caminho);
  if (!f) throw new Error(`xlsx-graficos: parte ausente no .xlsx gerado: ${caminho}`);
  return f.async("string");
}

function proximoRId(relsXml: string): string {
  let maior = 0;
  for (const m of relsXml.matchAll(/\bId="rId(\d+)"/g)) maior = Math.max(maior, Number(m[1]));
  return `rId${maior + 1}`;
}

function xmlGrafico(espec: EspecGrafico, idEixoCat: number, idEixoVal: number): string {
  const series = espec.series.map((s, i) => {
    const nome = s.refNome
      ? `<c:tx><c:strRef><c:f>${escapar(s.refNome)}</c:f></c:strRef></c:tx>`
      : "";
    const traco = s.tracejada ? '<a:prstDash val="dash"/>' : "";
    return `<c:ser><c:idx val="${i}"/><c:order val="${i}"/>${nome}`
      + `<c:spPr><a:ln w="19050" cap="rnd"><a:solidFill><a:srgbClr val="${s.cor}"/></a:solidFill>${traco}`
      + `<a:round/></a:ln><a:effectLst/></c:spPr>`
      + `<c:marker><c:symbol val="none"/></c:marker>`
      + `<c:cat><c:numRef><c:f>${escapar(s.refCategorias)}</c:f></c:numRef></c:cat>`
      + `<c:val><c:numRef><c:f>${escapar(s.refValores)}</c:f></c:numRef></c:val>`
      + `<c:smooth val="0"/></c:ser>`;
  }).join("");

  // A ordem dos filhos abaixo segue o esquema (CT_LineChart, CT_CatAx,
  // CT_ValAx). Trocar dois de lugar produz arquivo que o Excel recusa.
  return `<?xml version="1.0" encoding="UTF-8" standalone="yes"?>`
    + `<c:chartSpace xmlns:c="${NS_C}" xmlns:a="${NS_A}" xmlns:r="${NS_R}">`
    + `<c:roundedCorners val="0"/>`
    + `<c:chart>`
    + `<c:title><c:tx><c:rich><a:bodyPr/><a:lstStyle/><a:p><a:pPr>`
    + `<a:defRPr sz="1000" b="1"/></a:pPr><a:r><a:rPr lang="pt-BR" sz="1000" b="1"/>`
    + `<a:t>${escapar(espec.titulo)}</a:t></a:r></a:p></c:rich></c:tx>`
    + `<c:overlay val="0"/></c:title><c:autoTitleDeleted val="0"/>`
    + `<c:plotArea><c:layout/>`
    + `<c:lineChart><c:grouping val="standard"/><c:varyColors val="0"/>${series}`
    + `<c:marker val="0"/><c:axId val="${idEixoCat}"/><c:axId val="${idEixoVal}"/></c:lineChart>`
    + `<c:catAx><c:axId val="${idEixoCat}"/><c:scaling><c:orientation val="minMax"/></c:scaling>`
    + `<c:delete val="0"/><c:axPos val="b"/><c:numFmt formatCode="General" sourceLinked="0"/>`
    + `<c:majorTickMark val="out"/><c:minorTickMark val="none"/><c:tickLblPos val="nextTo"/>`
    + `<c:crossAx val="${idEixoVal}"/><c:crosses val="autoZero"/><c:auto val="1"/>`
    + `<c:lblAlgn val="ctr"/><c:lblOffset val="100"/><c:noMultiLvlLbl val="0"/></c:catAx>`
    + `<c:valAx><c:axId val="${idEixoVal}"/><c:scaling><c:orientation val="minMax"/></c:scaling>`
    + `<c:delete val="0"/><c:axPos val="l"/><c:majorGridlines/>`
    + `<c:numFmt formatCode="${escapar(espec.fmtValor ?? "#,##0")}" sourceLinked="0"/>`
    + `<c:majorTickMark val="out"/><c:minorTickMark val="none"/><c:tickLblPos val="nextTo"/>`
    + `<c:crossAx val="${idEixoCat}"/><c:crosses val="autoZero"/><c:crossBetween val="between"/></c:valAx>`
    + `</c:plotArea><c:legend><c:legendPos val="b"/><c:overlay val="0"/></c:legend>`
    + `<c:plotVisOnly val="1"/><c:dispBlanksAs val="gap"/></c:chart></c:chartSpace>`;
}

function xmlDesenho(ancoras: { espec: EspecGrafico; rid: string; id: number }[]): string {
  const partes = ancoras.map(({ espec, rid, id }) =>
    `<xdr:twoCellAnchor>`
    + `<xdr:from><xdr:col>${espec.de.col}</xdr:col><xdr:colOff>0</xdr:colOff>`
    + `<xdr:row>${espec.de.linha}</xdr:row><xdr:rowOff>0</xdr:rowOff></xdr:from>`
    + `<xdr:to><xdr:col>${espec.ate.col}</xdr:col><xdr:colOff>0</xdr:colOff>`
    + `<xdr:row>${espec.ate.linha}</xdr:row><xdr:rowOff>0</xdr:rowOff></xdr:to>`
    + `<xdr:graphicFrame macro="">`
    + `<xdr:nvGraphicFramePr><xdr:cNvPr id="${id}" name="Gráfico ${id - 1}"/>`
    + `<xdr:cNvGraphicFramePr/></xdr:nvGraphicFramePr>`
    + `<xdr:xfrm><a:off x="0" y="0"/><a:ext cx="0" cy="0"/></xdr:xfrm>`
    + `<a:graphic><a:graphicData uri="${NS_C}">`
    + `<c:chart xmlns:c="${NS_C}" xmlns:r="${NS_R}" r:id="${rid}"/>`
    + `</a:graphicData></a:graphic></xdr:graphicFrame><xdr:clientData/></xdr:twoCellAnchor>`,
  ).join("");
  return `<?xml version="1.0" encoding="UTF-8" standalone="yes"?>`
    + `<xdr:wsDr xmlns:xdr="${NS_XDR}" xmlns:a="${NS_A}" xmlns:r="${NS_R}">${partes}</xdr:wsDr>`;
}

/**
 * Injeta os gráficos no buffer de um .xlsx já gerado pelo ExcelJS.
 *
 * Agrupa por aba: uma parte de desenho por aba, com um `twoCellAnchor` por
 * gráfico — que é exatamente como o Modelo Base faz (os 8 gráficos dele estão em
 * um único `drawing1.xml` da aba `Output`).
 */
export async function injetarGraficosNoBuffer(
  buffer: Buffer | ArrayBuffer,
  especs: EspecGrafico[],
): Promise<Buffer> {
  const zip = await JSZip.loadAsync(buffer);
  if (especs.length === 0) return zip.generateAsync({ type: "nodebuffer", compression: "DEFLATE" });

  // Índices livres: o ExcelJS pode já ter criado desenho (imagem) e o VML das notas.
  const usados = Object.keys(zip.files);
  let proxGrafico = 1 + usados.filter((p) => /^xl\/charts\/chart\d+\.xml$/.test(p)).length;
  let proxDesenho = 1 + usados.filter((p) => /^xl\/drawings\/drawing\d+\.xml$/.test(p)).length;

  const overrides: string[] = [];
  const porAba = new Map<string, EspecGrafico[]>();
  for (const e of especs) {
    if (!porAba.has(e.aba)) porAba.set(e.aba, []);
    porAba.get(e.aba)!.push(e);
  }

  for (const [aba, lista] of porAba) {
    const parteAba = await parteDaAba(zip, aba);
    const caminhoDesenho = `xl/drawings/drawing${proxDesenho}.xml`;
    const relsDesenho: string[] = [];
    const ancoras: { espec: EspecGrafico; rid: string; id: number }[] = [];

    for (let i = 0; i < lista.length; i++) {
      const espec = lista[i];
      const caminhoGrafico = `xl/charts/chart${proxGrafico}.xml`;
      // Ids de eixo só precisam ser únicos DENTRO do gráfico, mas mantê-los
      // únicos no arquivo torna o diff legível quando algo dá errado.
      zip.file(caminhoGrafico, xmlGrafico(espec, 100000 + proxGrafico * 2, 100001 + proxGrafico * 2));
      overrides.push(`<Override PartName="/${caminhoGrafico}" ContentType="${CT_GRAFICO}"/>`);
      const rid = `rId${i + 1}`;
      relsDesenho.push(
        `<Relationship Id="${rid}" Type="${TIPO_REL_GRAFICO}" Target="../charts/chart${proxGrafico}.xml"/>`,
      );
      // O `id` do cNvPr precisa ser >= 2 e único na parte de desenho.
      ancoras.push({ espec, rid, id: i + 2 });
      proxGrafico++;
    }

    zip.file(caminhoDesenho, xmlDesenho(ancoras));
    zip.file(
      `xl/drawings/_rels/drawing${proxDesenho}.xml.rels`,
      `<?xml version="1.0" encoding="UTF-8" standalone="yes"?>`
      + `<Relationships xmlns="${NS_PKG_REL}">${relsDesenho.join("")}</Relationships>`,
    );
    overrides.push(`<Override PartName="/${caminhoDesenho}" ContentType="${CT_DESENHO}"/>`);

    // ---- relação da ABA para o desenho -------------------------------------
    const nomeArquivoAba = parteAba.split("/").pop()!;
    const caminhoRelsAba = `xl/worksheets/_rels/${nomeArquivoAba}.rels`;
    const relsAbaExistente = zip.file(caminhoRelsAba)
      ? await lerParte(zip, caminhoRelsAba)
      : `<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="${NS_PKG_REL}"></Relationships>`;
    const ridAba = proximoRId(relsAbaExistente);
    const relNova = `<Relationship Id="${ridAba}" Type="${TIPO_REL_DESENHO}" Target="../drawings/drawing${proxDesenho}.xml"/>`;
    if (!relsAbaExistente.includes("</Relationships>")) {
      throw new Error(`xlsx-graficos: rels da aba "${aba}" em formato inesperado`);
    }
    zip.file(caminhoRelsAba, relsAbaExistente.replace("</Relationships>", `${relNova}</Relationships>`));

    // ---- `<drawing/>` dentro da aba, NA POSIÇÃO QUE O ESQUEMA EXIGE --------
    let abaXml = await lerParte(zip, parteAba);
    if (/<drawing\b/.test(abaXml)) {
      throw new Error(`xlsx-graficos: a aba "${aba}" já tem <drawing> — dois desenhos na mesma aba `
        + "exigiriam fundir as âncoras, e fundir em silêncio esconderia o gráfico perdido");
    }
    const tagDrawing = `<drawing r:id="${ridAba}"/>`;
    // `<drawing>` vem DEPOIS de pageSetup/headerFooter e ANTES de legacyDrawing
    // (que o ExcelJS emite em toda aba com nota — ou seja, nas nossas).
    const iLegacy = abaXml.indexOf("<legacyDrawing");
    if (iLegacy >= 0) {
      abaXml = abaXml.slice(0, iLegacy) + tagDrawing + abaXml.slice(iLegacy);
    } else if (abaXml.includes("</worksheet>")) {
      abaXml = abaXml.replace("</worksheet>", `${tagDrawing}</worksheet>`);
    } else {
      throw new Error(`xlsx-graficos: não achei onde inserir <drawing> na aba "${aba}"`);
    }
    zip.file(parteAba, abaXml);
    proxDesenho++;
  }

  // ---- [Content_Types].xml -------------------------------------------------
  const ct = await lerParte(zip, "[Content_Types].xml");
  if (!ct.includes("</Types>")) throw new Error("xlsx-graficos: [Content_Types].xml em formato inesperado");
  zip.file("[Content_Types].xml", ct.replace("</Types>", `${overrides.join("")}</Types>`));

  // DEFLATE explícito: o default do JSZip é STORE, e regravar sem compressão
  // multiplica por ~14 o tamanho do arquivo entregue.
  return zip.generateAsync({ type: "nodebuffer", compression: "DEFLATE", compressionOptions: { level: 6 } });
}
