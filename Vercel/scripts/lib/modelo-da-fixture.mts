import type { DocumentoParaExport } from "../../src/lib/export";
import type { CampoExtraido } from "../../src/lib/types";
import type {
  EntradaModeloInstitucional, LinhaModelo, PremissaModelo,
} from "../../src/lib/modelo-institucional";

// Monta a entrada do modelo institucional a partir da fixture do book, SEM banco.
//
// POR QUE ISTO NÃO É "REIMPLEMENTAR O BANCO EM TS". As regras que decidem
// significado — papel da linha (0042), ano da ocorrência (0044), agrupamento por
// rótulo normalizado (0039) — moram no Postgres e são cobertas por teste SQL. Aqui
// o objetivo é outro: exercitar o GERADOR do Excel contra dado conhecido, sem
// Postgres, no `verificar-export.mts` e no gerador de fixture. Então esta função
// replica só o ESSENCIAL e de forma DELIBERADAMENTE simples, e o e2e (`test/e2e`)
// é quem confere a costura banco → export com as funções de verdade.
//
// Se as duas divergirem, quem está certo é o banco.

const norm = (s: string) =>
  s.normalize("NFD").replace(/[̀-ͯ]/g, "").toLowerCase().replace(/\s+/g, " ").trim();

const anoDe = (periodo: string | null | undefined, ref: string | null | undefined) => {
  const m = /((?:19|20)\d{2})/.exec(periodo ?? "") ?? /((?:19|20)\d{2})/.exec(ref ?? "");
  if (m) return Number(m[1]);
  const m2 = /(\d{2})\s*$/.exec(ref ?? "");
  return m2 ? 2000 + Number(m2[1]) : null;
};

const ESTRUTURAIS = [
  /^total\b/, /^subtotal\b/, /^soma\b/, /^ativo$/, /^passivo$/, /^patrimonio( liquido)?$/,
  /^ativo (nao )?circulante$/, /^passivo (nao )?circulante$/, /^realizavel a longo prazo$/,
  /^passivo e patrimonio liquido$/, /^receita (operacional )?liquida$/, /^lucro bruto$/,
  /^prejuizo bruto$/, /^(lucro|prejuizo) liquido( do exercicio)?$/, /^resultado do exercicio$/,
  /^resultado (operacional )?antes/, /^caixa liquido /, /^(reducao|aumento) liquida/,
];
const DERIVADOS = [/^indice /, /^media (mensal|anual)/, /^ticket medio/, /^prazo medio/,
  /^margem /, /^capital circulante liquido/];
const MESES = ["jan", "fev", "mar", "abr", "mai", "jun", "jul", "ago", "set", "out", "nov", "dez"];

function papel(chave: string, tipo: string): LinhaModelo["papel"] {
  const t = norm(chave);
  if (DERIVADOS.some((re) => re.test(t))) return "derivado";
  if (tipo === "FATURAMENTO_24M" && t.split(/[^a-z]+/).some((w) => MESES.includes(w.slice(0, 3)) && w.length <= 9)) {
    return "serie_mensal";
  }
  if (ESTRUTURAIS.some((re) => re.test(t))) return "subtotal";
  return "conta";
}

export function entradaModeloDaFixture(
  fixture: { documentos: DocumentoParaExport[]; campos: CampoExtraido[] },
  agora: Date,
  opts: { entidade?: string; ultimoReal?: number; anosProjetados?: number } = {},
): EntradaModeloInstitucional {
  const entidade = opts.entidade ?? "VERTENTES METALÚRGICA LTDA.";
  const ultimoReal = opts.ultimoReal ?? 2025;
  const nProj = opts.anosProjetados ?? 5;

  const ctxVersao = new Map<string, { tipo: string; razao: string | null; ref: string | null }>();
  for (const d of fixture.documentos) {
    const razao = (Array.isArray(d.entidade) ? d.entidade[0] : d.entidade)?.razao_social ?? null;
    const ref = (Array.isArray(d.periodo) ? d.periodo[0] : d.periodo)?.referencia ?? null;
    for (const v of d.documento_versao ?? []) {
      ctxVersao.set(v.id, { tipo: d.tipo_taxonomia ?? "", razao, ref });
    }
  }

  const agrup = new Map<string, LinhaModelo>();
  for (const c of fixture.campos) {
    if (c.valor_num === null || c.valor_num === undefined) continue;
    const ctx = ctxVersao.get(c.documento_versao_id);
    if (!ctx) continue;
    const dono = c.entidade_coluna ?? ctx.razao ?? "";
    // Casamento de entidade simplificado: canônico contido. O banco usa
    // `fn_mesma_entidade`, que é mais tolerante — e é ele que vale.
    const a = norm(dono).replace(/[^a-z0-9 ]/g, "");
    const b = norm(entidade).replace(/[^a-z0-9 ]/g, "");
    if (!(a.includes(b) || b.includes(a))) continue;
    const ano = anoDe(c.periodo_coluna, ctx.ref);
    if (ano === null || ano > ultimoReal) continue;

    const rn = norm(c.chave);
    const chaveG = `${c.secao_canonica ?? ""}|${rn}`;
    if (!agrup.has(chaveG)) {
      agrup.set(chaveG, {
        secao_canonica: c.secao_canonica ?? null, chave: c.chave, rotulo_norm: rn,
        papel: papel(c.chave, ctx.tipo), unidade: c.unidade ?? null, moeda: c.moeda ?? null,
        documentos: [ctx.tipo], valores: {},
      });
    }
    const l = agrup.get(chaveG)!;
    if (!l.documentos!.includes(ctx.tipo)) l.documentos!.push(ctx.tipo);
    const atual = l.valores[String(ano)];
    if (atual === undefined || Math.abs(Number(c.valor_num)) > Math.abs(atual)) {
      l.valores[String(ano)] = Number(c.valor_num);
    }
  }

  const linhas = [...agrup.values()];
  const anosHistoricos = [...new Set(linhas.flatMap((l) => Object.keys(l.valores).map(Number)))]
    .filter((a) => a <= ultimoReal).sort((a, b) => a - b);

  // Premissas de demonstração: crescimento de receita e margem de custo, para o
  // arquivo sair com projeção de verdade. O portal manda as reais.
  const premissas: PremissaModelo[] = [
    {
      codigo: "CRESC_REAL", nome: "Crescimento real da receita", natureza: "receita",
      formula: "crescimento_composto", unidade: "%", origem: "digitado",
      valores: Object.fromEntries(
        Array.from({ length: nProj }, (_, i) => [String(ultimoReal + 1 + i), 5]),
      ),
    },
    {
      codigo: "CUSTO_VARIAVEL", nome: "Custo variável (% da receita)", natureza: "custo",
      formula: "pct_de_linha", unidade: "%", origem: "digitado",
      valores: Object.fromEntries(
        Array.from({ length: nProj }, (_, i) => [String(ultimoReal + 1 + i), 60]),
      ),
    },
    {
      codigo: "PMR", nome: "Prazo médio de recebimento", natureza: "giro",
      formula: "dias_de_giro", unidade: "dias", origem: "digitado",
      valores: Object.fromEntries(
        Array.from({ length: nProj }, (_, i) => [String(ultimoReal + 1 + i), 60]),
      ),
    },
  ];
  const vinculos = linhas
    .filter((l) => l.papel === "conta")
    .map((l) => ({
      rotulo_norm: l.rotulo_norm,
      premissa_codigo: l.secao_canonica === "receita_bruta" ? "CRESC_REAL"
        : l.secao_canonica === "custos" || l.secao_canonica === "despesas_operacionais" ? "CUSTO_VARIAVEL"
        : l.secao_canonica === "ativo_circulante" || l.secao_canonica === "passivo_circulante" ? "PMR"
        : null,
      sazonalidade_codigo: null,
    }));

  return {
    caso: { nome: "Book Vertentes (sintético)", produto: "reestruturacao" },
    agora, entidade, setor: "industria",
    anosHistoricos, anosProjetados: Array.from({ length: nProj }, (_, i) => ultimoReal + 1 + i),
    stressPct: 0.2, caixaMinimo: 1000, aliquotaTributos: 0.34,
    linhas, premissas, vinculos,
    macro: [
      { serie: "IPCA", ano: ultimoReal + 1, valor: 5.12, fonte: "Focus (fixture)" },
      { serie: "CDI", ano: ultimoReal + 1, valor: 12.5, fonte: "realizado (fixture)" },
    ],
    unidade: "R$ mil",
  };
}
