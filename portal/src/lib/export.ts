import ExcelJS from "exceljs";
import JSZip from "jszip";
import type { CampoExtraido } from "./types";
import {
  classificarConta,
  classificarDemonstracao,
  familiaDeclarada,
  ehSecaoDeNotaExplicativa,
  secoesDe,
  ancorasDe,
  agruparPorChaveNormalizada,
  normalizar,
  ehNomeDeAgrupamento,
  ESTRUTURA_POR_TIPO,
  BALANCO_OUTLINE,
  type EstruturaDemonstracao,
  type FamiliaDemonstracao,
} from "./statement-templates";

// Modo B do output (f0/07_output_spec.md): export sob demanda. Princípio
// inegociável da spec: "Dado sem aceite não é entregue como fato — no
// máximo aparece como sugestão pendente de revisão, visualmente distinta."
// Por isso TODAS as linhas aparecem (aceitas e pendentes), mas com
// status/estilo bem distintos — nada aqui vira fato silenciosamente.
//
// Balanço/Balancete/DRE/Fluxo de Caixa/Combinado saem CLASSIFICADOS por
// SEÇÃO (statement-templates.ts) — não por um template de ~15 nomes de
// conta fixos. Cada empresa nomeia as contas do jeito dela; o que é
// universal é a SEÇÃO (Ativo Circulante, Despesas Operacionais, Atividades
// de Investimento, etc.). Cada conta aparece com o rótulo ORIGINAL da
// empresa, dentro da seção certa — nada é forçado a um nome canônico, e
// nada some: o que não é classificável com segurança cai num bloco
// explícito "Contas Não Classificadas". Faturamento/Dívida/Fluxo Projetado
// continuam em listagem simples (já são, por natureza, uma série/tabela).
// O export NÃO modela nem projeta (fora do escopo, mesma spec) — nenhum
// subtotal/total é calculado por soma; só aparece se o próprio documento
// já trouxer aquela linha extraída.
//
// Função pura (sem Supabase/Next.js) para ser testável isoladamente — a rota
// (`app/casos/[id]/export/route.ts`) só busca os dados e chama esta função.

// Padroniza o período (periodo.tipo + periodo.referencia — convenções livres
// vindas da extração: "12M25", "1T25", "L24M", "23,24,25", datas ISO/BR,
// texto livre) num modelo pronto de "períodos e intervalos", sem jargão
// técnico ("multi", "data-base") nem convenções cifradas na tela. Pedido do
// dono (sessão 7 cont.¹⁵): "simplificar e deixar mais objetiva a escrita de
// período". Nunca lança — o que não reconhece, devolve como veio (nunca pior
// que o comportamento anterior).
function anoDe4Digitos(anoTexto: string): string {
  if (anoTexto.length === 4) return anoTexto;
  const n = Number(anoTexto);
  return String(n <= 79 ? 2000 + n : 1900 + n);
}

function formatarDataBR(ref: string): string {
  const iso = ref.match(/^(\d{4})-(\d{2})-(\d{2})$/);
  return iso ? `${iso[3]}/${iso[2]}/${iso[1]}` : ref;
}

const MESES_ABREV = ["Jan", "Fev", "Mar", "Abr", "Mai", "Jun", "Jul", "Ago", "Set", "Out", "Nov", "Dez"];
const MES_POR_NOME: Record<string, number> = {
  jan: 1, fev: 2, mar: 3, abr: 4, mai: 5, jun: 6, jul: 7, ago: 8, set: 9, out: 10, nov: 11, dez: 12,
  janeiro: 1, fevereiro: 2, marco: 3, abril: 4, maio: 5, junho: 6, julho: 7, agosto: 8,
  setembro: 9, outubro: 10, novembro: 11, dezembro: 12,
};
function mesAno(mes: number, anoTexto: string): string {
  return `${MESES_ABREV[mes - 1]}/${anoDe4Digitos(anoTexto)}`;
}

// Padroniza o período num modelo pronto e objetivo, tolerante às MUITAS notações
// que a extração produz entre contratos diferentes (cada demonstração escreve o
// período de um jeito). Robusto contra os mis-parses reais achados na auditoria:
// "02,25" NÃO é o intervalo "2002–2025" e sim Fev/2025 (mês,ano); semestre,
// mês abreviado, MM/AAAA e ISO (mesmo sem tipo=data-base) são reconhecidos. O
// que não reconhece volta como veio (nunca pior que antes).
export function formatarPeriodo(tipo: string | null, referencia: string | null): string {
  const ref = (referencia ?? "").trim();
  const t = (tipo ?? "").trim();
  if (!ref) return "—";
  const low = ref.toLowerCase();

  const ultimosMeses = ref.match(/^L(\d+)M$/i);
  if (ultimosMeses) return `Últimos ${ultimosMeses[1]} meses`;

  const anoFiscal = ref.match(/^(\d{1,2})M(\d{2,4})$/i);
  if (anoFiscal) {
    const nMeses = Number(anoFiscal[1]);
    const ano = anoDe4Digitos(anoFiscal[2]);
    return nMeses === 12 ? ano : `${nMeses} meses/${ano}`;
  }

  const trimestre = ref.match(/^(\d)T(\d{2,4})$/i);
  if (trimestre) return `${trimestre[1]}º Tri/${anoDe4Digitos(trimestre[2])}`;
  const semestre = ref.match(/^(\d)S(\d{2,4})$/i);
  if (semestre) return `${semestre[1]}º Sem/${anoDe4Digitos(semestre[2])}`;

  // Datas: ISO (independente do tipo) e BR já legível
  const iso = ref.match(/^(\d{4})-(\d{2})-(\d{2})$/);
  if (iso) return `${iso[3]}/${iso[2]}/${iso[1]}`;
  if (/^\d{2}\/\d{2}\/\d{2,4}$/.test(ref)) return ref;

  // Mês por nome/abreviação + ano: "jan/25", "dez-24", "fevereiro/2025"
  const mesNome = low.match(/^([a-zç]{3,9})[\/\-. ](\d{2,4})$/);
  if (mesNome && MES_POR_NOME[mesNome[1]] != null) return mesAno(MES_POR_NOME[mesNome[1]], mesNome[2]);

  // MM/AAAA ou MM-AAAA (mês numérico + ano de 4 dígitos): "02/2025", "12/2025"
  const mmAno = ref.match(/^(\d{1,2})[\/-](\d{4})$/);
  if (mmAno && Number(mmAno[1]) >= 1 && Number(mmAno[1]) <= 12) return mesAno(Number(mmAno[1]), mmAno[2]);

  if (t === "data-base") return formatarDataBR(ref);

  if (t === "multi" || /,/.test(ref)) {
    const toks = ref.split(",").map((p) => p.trim()).filter(Boolean);
    // "MM,AAAA"/"MM,AA" = MÊS,ANO — não um intervalo de exercícios (o mis-parse
    // "2002–2025"/"2012–2024" da auditoria). Dois sinais desambiguam:
    //   (a) mês com zero à esquerda ("02,25" → Fev/2025);
    //   (b) mês 1–12 seguido de ano de 4 dígitos ("12,2024" → Dez/2024) — uma
    //       lista de exercícios seria escrita com a MESMA largura nos dois
    //       tokens ("2012,2024" ou "12,24"), não misturada.
    // Sobra ambíguo só "NN,NN" sem zero à esquerda ("11,12"), que continua
    // tratado como exercícios (2011–2012) — a convenção do sistema para lista
    // de anos é justamente 2 dígitos (ver notação canônica em n8n/lib/extract).
    if (toks.length === 2) {
      const mes = Number(toks[0]);
      const mesComZero = /^0[1-9]$/.test(toks[0]);
      const anoCheio = /^\d{4}$/.test(toks[1]);
      if ((mesComZero && /^\d{2,4}$/.test(toks[1])) || (anoCheio && mes >= 1 && mes <= 12)) {
        return mesAno(mes, toks[1]);
      }
    }
    // Caso geral: lista de exercícios (anos).
    if (toks.every((p) => /^\d{1,4}$/.test(p))) {
      const anos = toks.map((p) => anoDe4Digitos(p));
      if (anos.length === 1) return anos[0];
      if (anos.length === 2) return `${anos[0]}–${anos[1]}`;
      return anos.join(", ");
    }
    return toks.join(", ");
  }

  if (/^\d{4}$/.test(ref)) return ref;
  if (/^\d{2}$/.test(ref)) return anoDe4Digitos(ref);

  return ref; // texto livre já descritivo (ex.: "Jan/2024 a Dez/2025") — mantém como veio
}

// Colunas de uma demonstração COMBINADA que NÃO são entidades: a de
// "Eliminações"/"Ajustes" (lançamentos que anulam saldos recíprocos) e a de
// "Combinado"/"Consolidado"/"Total" (o resultado da soma). A extração as trata
// como mais uma coluna de empresa — correto do ponto de vista do documento, mas
// no export elas não podem ser lidas como entidade: a de total DUPLICA o que as
// demais já dizem, e AV%/Δ% sobre uma coluna de ajuste é ruído. Achado no teste
// v24: a aba Combinado saiu com "Eliminações" e "Combinado" como se fossem duas
// empresas do grupo. Aqui elas continuam no export (nada se perde), mas ficam
// no FIM, rotuladas pelo que são, e sem análise vertical/horizontal.
const RE_COLUNA_AJUSTE = /^(elimina|ajuste|eliminacao)/;
const RE_COLUNA_TOTAL = /^(combinad|consolidad|total|soma)/;
export function tipoColunaNaoEntidade(entidade: string): "ajuste" | "total" | null {
  const t = normalizar(entidade);
  if (RE_COLUNA_AJUSTE.test(t)) return "ajuste";
  if (RE_COLUNA_TOTAL.test(t)) return "total";
  return null;
}

// Chave CRONOLÓGICA de um período já formatado (saída de `formatarPeriodo`).
// As colunas do export eram ordenadas por `localeCompare` do rótulo, o que é
// alfabético: "Nov/2024" vinha antes de "Out/2024" e "Dez/2024" antes de
// "Jan/2024" — além de bagunçar a leitura, isso fazia a coluna Δ% (que compara
// períodos ADJACENTES da mesma entidade) casar o par errado, reportando uma
// variação entre meses que não se sucedem. Deriva (ano, mês, dia) do rótulo;
// períodos que agregam vários exercícios entram no nível do ANO (mês 0, antes
// dos meses daquele ano) e rótulos sem âncora temporal ("Últimos 24 meses",
// texto livre) vão para o fim — nunca no meio da série.
const MES_NUM: Record<string, number> = {
  jan: 1, fev: 2, mar: 3, abr: 4, mai: 5, jun: 6, jul: 7, ago: 8, set: 9, out: 10, nov: 11, dez: 12,
};
export const CRONO_SEM_ANCORA = Number.MAX_SAFE_INTEGER;

export function chaveCronologicaPeriodo(periodoFormatado: string): number {
  const p = (periodoFormatado ?? "").trim();
  if (!p || p === "—") return CRONO_SEM_ANCORA;
  const chave = (ano: number, mes = 0, dia = 0) => ano * 10000 + mes * 100 + dia;

  const data = p.match(/^(\d{2})\/(\d{2})\/(\d{4})$/); // 15/01/2025
  if (data) return chave(Number(data[3]), Number(data[2]), Number(data[1]));

  const mesAbrev = p.match(/^([A-Za-zç]{3})\/(\d{4})$/); // Fev/2025
  if (mesAbrev) {
    const m = MES_NUM[mesAbrev[1].toLowerCase()];
    if (m) return chave(Number(mesAbrev[2]), m);
  }

  const tri = p.match(/^([1-4])º Tri\/(\d{4})$/); // 1º Tri/2025 → início do trimestre
  if (tri) return chave(Number(tri[2]), (Number(tri[1]) - 1) * 3 + 1);

  const sem = p.match(/^([12])º Sem\/(\d{4})$/); // 2º Sem/2024 → início do semestre
  if (sem) return chave(Number(sem[2]), Number(sem[1]) === 1 ? 1 : 7);

  const nMeses = p.match(/^(\d{1,2}) meses\/(\d{4})$/); // 9 meses/2024 (YTD)
  if (nMeses) return chave(Number(nMeses[2]), Number(nMeses[1]));

  if (/^\d{4}$/.test(p)) return chave(Number(p)); // exercício completo

  // Agregados de vários exercícios ("2024–2025", "2023, 2024, 2025"): entram no
  // nível do ano pelo PRIMEIRO exercício da série (ordenação determinística).
  const anos = p.match(/\b(19|20)\d{2}\b/g);
  if (anos && anos.length > 0) return chave(Number(anos[0]));

  return CRONO_SEM_ANCORA; // "Últimos 24 meses", texto livre — sempre por último
}

// ---------------------------------------------------------------------------
// CONSOLIDAÇÃO DE COLUNA (achado do teste v27, medido no export do dono)
//
// O grupo Vertentes tem 5 empresas e o Balanço saiu com 15 colunas de entidade:
// cada empresa aparecia DUAS vezes, porque chega por dois caminhos com grafias
// diferentes —
//   • pelo documento COMBINADO, via `entidade_coluna`: "Componentes", "Metalúrgica";
//   • pelo balanço INDIVIDUAL, via razão social: "VERTENTES COMPONENTES AUTOMOTIVOS LTDA.".
// O mesmo vale para o período: o combinado declara "2025" e o individual
// "31/12/2025" — o mesmo exercício escrito de dois jeitos.
//
// Isso não é cosmético. Uma aba de modelagem que some as colunas do grupo conta
// cada empresa DUAS VEZES e fecha errado em silêncio. Consolidar é pré-requisito
// de qualquer análise em cima, e é o mesmo princípio que a `0022` já aplica no
// Postgres para período (comparar por CONJUNTO DE ANOS, não pelo rótulo).
//
// Critério deliberadamente CONSERVADOR — um falso casamento aqui FUNDE duas
// empresas diferentes, que é bem pior que deixar duas colunas: o apelido só é
// promovido à razão social quando TODAS as suas palavras significativas casam
// (por prefixo, para "Part." achar "Participações") com UMA ÚNICA razão social
// conhecida do caso. Zero candidatos ou dois, fica como está.
// ---------------------------------------------------------------------------
// Só FORMA JURÍDICA e conectivo entram aqui. Palavras de ramo ("Participações",
// "Comércio", "Serviços", "Logística") NÃO são ruído: são exatamente o que
// distingue duas empresas do mesmo grupo, que costumam repetir o sobrenome
// ("Vertentes Participações" × "Vertentes Componentes"). Tratá-las como vazias
// fazia "Vertentes Part." perder o casamento com "VERTENTES PARTICIPAÇÕES S.A."
// e, pior, deixaria "Alfa Comércio" e "Alfa Serviços" indistinguíveis.
const PALAVRAS_VAZIAS_ENTIDADE = new Set([
  "ltda", "sa", "s", "a", "me", "epp", "eireli", "cia", "companhia",
  "do", "da", "de", "e", "dos", "das",
]);

function tokensEntidade(nome: string): string[] {
  return normalizar(nome)
    .split(/[^a-z0-9]+/)
    .filter((t) => t.length > 1 && !PALAVRAS_VAZIAS_ENTIDADE.has(t));
}

/**
 * Mapa apelido → razão social, a partir das razões sociais conhecidas do caso.
 * `razoesSociais` são os nomes vindos do registro de entidade (documento
 * individual); `apelidos` são os rótulos de coluna do documento combinado.
 */
export function consolidarNomesDeEntidade(
  razoesSociais: string[],
  apelidos: string[],
): Map<string, string> {
  const canonico = new Map<string, string>();
  const conhecidas = [...new Set(razoesSociais)]
    .filter((r) => r && !tipoColunaNaoEntidade(r))
    .map((r) => ({ nome: r, tokens: tokensEntidade(r) }))
    .filter((r) => r.tokens.length > 0);

  for (const apelido of new Set(apelidos)) {
    if (!apelido || tipoColunaNaoEntidade(apelido)) continue;
    const tokens = tokensEntidade(apelido);
    if (tokens.length === 0) continue;
    // "Part." casa "Participações" por PREFIXO: o combinado abrevia a coluna
    // para caber no papel, e exigir a palavra inteira perderia o casamento.
    const casam = conhecidas.filter(
      (r) => r.nome !== apelido
        && tokens.every((t) => r.tokens.some((rt) => rt.startsWith(t) || t.startsWith(rt))),
    );
    if (casam.length === 1) canonico.set(apelido, casam[0].nome);
  }
  return canonico;
}

/**
 * Rótulo de período consolidado. Dois rótulos que descrevem o MESMO exercício
 * ("2025" e "31/12/2025") viram colunas distintas só por causa da grafia; aqui
 * a data-base de 31/12 colapsa no exercício, que é como um modelo lê a coluna.
 * Só 31/12 — qualquer outra data-base é uma posição no meio do ano e continua
 * uma coluna própria (não é o exercício fechado).
 */
export function periodoConsolidado(periodoFormatado: string): string {
  const fim = (periodoFormatado ?? "").trim().match(/^31\/12\/((?:19|20)\d{2})$/);
  return fim ? fim[1] : periodoFormatado;
}

// Comparador de coluna: entidade (alfabética) → período (CRONOLÓGICO) → rótulo
// como desempate estável para períodos sem âncora temporal.
function compararColunas(
  a: { entidade: string; periodo: string },
  b: { entidade: string; periodo: string },
): number {
  // Entidades reais primeiro; depois a coluna de eliminações; o total por último
  // (é a leitura natural de um mapa de combinação).
  const ordem = (e: string) => {
    const t = tipoColunaNaoEntidade(e);
    return t === "ajuste" ? 1 : t === "total" ? 2 : 0;
  };
  return (
    ordem(a.entidade) - ordem(b.entidade)
    || a.entidade.localeCompare(b.entidade)
    || chaveCronologicaPeriodo(a.periodo) - chaveCronologicaPeriodo(b.periodo)
    || a.periodo.localeCompare(b.periodo)
  );
}

// tipo_taxonomia → nome da aba (ordem de prioridade travada em f0/07;
// Balancete/Combinado entram na mesma família estrutural do Balanço).
//
// MUTUOS e FAT_INTRAGRUPO são categoria "Intragrupo" na própria taxonomia
// (db/migrations/0002) — mútuo entre empresas do grupo não é DÍVIDA externa
// (banco/financiamento, como MAPA_DIVIDA/CONTRATO_DIVIDA); misturar as duas
// na mesma aba "Dívida" era uma classificação sem sentido contábil (achado em
// produção, sessão 7 cont.¹⁴). CONTRATO_SOCIAL (Societário/Legal) também
// ganhou aba própria em vez de cair no genérico "Outros" junto com dado
// tabular não relacionado.
// DMPL/DVA têm renderização própria (nem grade classificada, nem listagem
// simples) — nomeadas para o roteamento não depender de string solta.
const ABA_DMPL = "DMPL";
const ABA_DVA = "DVA";

export const ABA_POR_TIPO: Record<string, string> = {
  BALANCO: "Balanço",
  DRE: "DRE",
  FLUXO_CAIXA: "Fluxo de Caixa",
  COMBINADO: "Combinado",
  BALANCETE: "Balancete",
  FATURAMENTO_24M: "Faturamento",
  MAPA_DIVIDA: "Dívida",
  CONTRATO_DIVIDA: "Dívida",
  MUTUOS: "Intragrupo",
  FAT_INTRAGRUPO: "Intragrupo",
  CONTRATO_SOCIAL: "Societário",
  FLUXO_PROJETADO: "Fluxo Projetado",
  DMPL: ABA_DMPL,
  DVA: ABA_DVA,
};
export const ORDEM_ABAS = [
  "Balanço",
  "DRE",
  "Fluxo de Caixa",
  // Depois das três demonstrações principais e antes do Combinado/Balancete:
  // é a ordem em que uma demonstração contábil publicada apresenta o conjunto
  // (BP, DRE, DFC, DMPL, DVA — Lei 6.404/76 art. 176).
  ABA_DMPL,
  ABA_DVA,
  "Combinado",
  "Balancete",
  "Faturamento",
  "Dívida",
  "Intragrupo",
  "Societário",
  "Fluxo Projetado",
  "Outros",
];
const ESTRUTURA_POR_ABA = new Map<string, EstruturaDemonstracao>(
  Object.entries(ESTRUTURA_POR_TIPO).map(([tipo, estrutura]) => [ABA_POR_TIPO[tipo], estrutura]),
);

// tipo_taxonomia (código interno da classificação) → rótulo natural pra
// tela (dashboard, planilha do documento, fila de revisão). Pedido do dono
// (sessão 7 cont.¹⁶): nada de código cru ("FATURAMENTO_24M") na interface —
// escrita natural, do mesmo jeito que um analista falaria. Distinto de
// ABA_POR_TIPO (que agrupa MUTUOS/FAT_INTRAGRUPO numa aba só "Intragrupo" e
// MAPA_DIVIDA/CONTRATO_DIVIDA em "Dívida") — aqui cada tipo tem o próprio
// rótulo, mesmo que dois deles caiam na mesma aba do export.
const TIPO_TAXONOMIA_LABEL: Record<string, string> = {
  BALANCO: "Balanço",
  DRE: "DRE",
  FLUXO_CAIXA: "Fluxo de Caixa",
  COMBINADO: "Demonstrações Combinadas",
  BALANCETE: "Balancete",
  FATURAMENTO_24M: "Faturamento em 24 meses",
  MAPA_DIVIDA: "Mapa da Dívida",
  CONTRATO_DIVIDA: "Contrato de Dívida",
  MUTUOS: "Mútuos",
  FAT_INTRAGRUPO: "Faturamento Intragrupo",
  CONTRATO_SOCIAL: "Contrato Social",
  FLUXO_PROJETADO: "Fluxo Projetado",
  DMPL: "Mutações do Patrimônio Líquido",
  DVA: "Demonstração do Valor Adicionado",
};

// Tipos ainda sem rótulo explícito (fora do Kit Básico + Variáveis já
// mapeados acima) caem num fallback genérico — "EXTRATO_BANCARIO" vira
// "Extrato Bancario" em vez do código cru — nunca pior que antes, e já seguem
// a mesma linha de escrita natural quando entrar um tipo novo.
export function formatarTipoTaxonomia(codigo: string | null): string {
  if (!codigo) return "Não classificado";
  const label = TIPO_TAXONOMIA_LABEL[codigo];
  if (label) return label;
  return codigo
    .toLowerCase()
    .split("_")
    .map((palavra) => palavra.charAt(0).toUpperCase() + palavra.slice(1))
    .join(" ");
}

// Família da demonstração → aba PADRÃO para onde vai uma linha que pertence a
// essa família mas foi extraída de um documento de OUTRO tipo (um PDF de
// "Demonstrações Contábeis" completo traz Balanço + DRE + Fluxo de Caixa
// juntos). Balancete/Combinado (também família "balanco") mantêm as próprias
// abas quando o documento é desse tipo — só o que "vaza" de um documento
// composto para uma família diferente é redirecionado para estas abas.
const ABA_PADRAO_POR_ESTRUTURA: Record<FamiliaDemonstracao, string> = {
  balanco: "Balanço",
  dre: "DRE",
  fluxo_caixa: "Fluxo de Caixa",
  dmpl: "DMPL",
  dva: "DVA",
};

// Tipo cujo documento é, por definição, o CONJUNTO das demonstrações num arquivo
// só: "Demonstrações financeiras auditadas completas (+ notas)"
// (`db/migrations/0002`). É a forma mais comum de entrega num mandato real — o
// cliente manda o PDF auditado do exercício, não um arquivo por demonstração.
//
// Ele não pode ter aba própria em `ABA_POR_TIPO` (que aba seria? o arquivo é
// Balanço E DRE E DFC E DMPL), e por não ter caía em "Outros": o roteamento por
// linha só rodava para documento de tipo ESTRUTURADO, então a DF auditada inteira
// saía como listagem crua — sem template, sem total de seção, sem AV%/Δ%, sem
// indicadores, e a aba Modelagem (que lê das abas de demonstração) saía ZERADA.
// Aqui o tipo declara "sou composto" e cada linha vai para a aba da SUA
// demonstração, do mesmo jeito que já acontecia com a DMPL embutida num Balanço.
//
// Por que só este tipo, e não todo o balde "Outros": aging de recebíveis, posição
// de estoques, extrato bancário, razão e notas explicativas DETALHAM o que o
// balanço já traz consolidado. Roteá-los para o Balanço somaria o detalhe junto
// com o total — a dupla contagem que o export levou três rodadas para eliminar.
const TIPOS_DOCUMENTO_COMPOSTO = new Set(["DF_AUDITADA"]);

// Demonstrações que a entrega sempre mostra, com dado ou sem. São as três que o
// Kit Básico cobra como obrigatórias e para as quais o modelo aponta.
const ABAS_SEMPRE_PRESENTES = new Set(["Balanço", "DRE", "Fluxo de Caixa"]);

/**
 * Aba de demonstração SEM dado — e dizendo por quê.
 *
 * Distingue os dois casos, que pedem ações opostas do dono:
 *   • documento ENTREGUE e sem linha extraída → é falha do pipeline (no v28, rate
 *     limit da OpenAI): reprocessar o arquivo resolve, e a fila já tem a pendência;
 *   • nenhum documento daquela demonstração → é cobrança de documento, e quem
 *     cobra é o checklist do Kit Básico. Não há nada a reprocessar.
 *
 * Nada é inventado aqui (f0/07): sem linha extraída não há o que o template
 * ordene. O que a aba entrega é a informação de que falta — que antes o arquivo
 * não dava de jeito nenhum.
 */
function construirAbaSemDado(
  workbook: ExcelJS.Workbook,
  aba: string,
  documentos: DocumentoParaExport[],
): void {
  const tiposDaAba = Object.entries(ABA_POR_TIPO).filter(([, nome]) => nome === aba).map(([tipo]) => tipo);
  const arquivos = [
    ...new Set(
      documentos
        .filter((d) => d.tipo_taxonomia && tiposDaAba.includes(d.tipo_taxonomia))
        .flatMap((d) => (d.documento_versao ?? []).map((v) => v.nome_original ?? "(sem nome)")),
    ),
  ];
  const ws = workbook.addWorksheet(aba);
  ws.columns = [{ width: 42 }, { width: 88 }];
  ws.addRow([`${aba} — sem dado nesta entrega`]).font = { bold: true, size: 12 };
  ws.addRow(
    arquivos.length > 0
      ? ["Documento entregue, extração sem linha",
        `${arquivos.join("; ")}. O arquivo chegou e foi classificado, mas a extração não gravou `
        + "nenhuma linha — a falha abre pendência própria na fila de revisão do mandato. "
        + "Reprocessar o arquivo preenche esta aba."]
      : ["Nenhum documento desta demonstração",
        "O mandato ainda não tem documento classificado nesta demonstração. Quem cobra isso é o "
        + "checklist do Kit Básico; esta aba existe para a ausência ficar visível na entrega."],
  );
  ws.getRow(2).alignment = { wrapText: true, vertical: "top" };
  ws.getRow(2).height = 42;
  ws.addRow([]);
  const nota = ws.addRow(["", "Nada é preenchido por conta própria: o template ordena o que o documento "
    + "trouxe (f0/07_output_spec.md). Sem linha extraída, não há o que ordenar."]);
  nota.alignment = { wrapText: true, vertical: "top" };
  nota.font = { italic: true, size: 9 };
}

export interface DocumentoParaExport {
  id: string;
  tipo_taxonomia: string | null;
  entidade: { razao_social: string } | null;
  periodo: { tipo: string; referencia: string } | null;
  documento_versao: Array<{ id: string; nome_original: string | null; n_versao?: number | null }> | null;
}

/**
 * Versões VIGENTES por documento — reextração SUBSTITUI, não acumula.
 *
 * Reextrair é a única forma de um documento já processado pegar prompt/taxonomia
 * novos (migration e prompt só valem para extração NOVA), e o dono precisa disso
 * para a DMPL da `0024`. Mas o export lia TODAS as versões de cada documento, e
 * duas extrações do mesmo arquivo não produzem as mesmas linhas — é o ponto de
 * mudar o prompt. Medido: com o rótulo renomeado entre as duas extrações, a
 * conta aparece DUAS vezes e a soma da seção somou as duas (1.000 + 1.500 =
 * 2.500 onde o documento diz 1.500). A dupla contagem de sempre, por um caminho
 * novo — e o pior tipo: o dono não pode nem desconfiar, porque as duas linhas têm
 * proveniência legítima.
 *
 * **A mais recente COM DADO manda.** Não é "a mais recente", e a diferença é uma
 * proteção real: uma reextração pode falhar (truncamento/rate limit gravam
 * `extracao_falhou` com ZERO linhas, `db/migrations/0016`). Se a vigência fosse
 * cega ao dado, essa falha APAGARIA do book tudo o que a versão anterior tinha
 * extraído com sucesso — trocar dupla contagem por perda silenciosa de dado não
 * é conserto.
 *
 * Empate (mesma `n_versao`, ou nenhuma informada) mantém as duas: sem ordem
 * declarada não há como saber qual é a nova, e escolher por chute é pior que o
 * comportamento antigo.
 */
export function versoesVigentes(documentos: DocumentoParaExport[], campos: CampoExtraido[]): Set<string> {
  const comDado = new Set(campos.map((c) => c.documento_versao_id));
  const vigentes = new Set<string>();
  for (const doc of documentos) {
    const versoes = doc.documento_versao ?? [];
    if (versoes.length <= 1) {
      for (const v of versoes) vigentes.add(v.id);
      continue;
    }
    const n = (v: { n_versao?: number | null }) => v.n_versao ?? 1;
    // Grupos por n_versao, do mais novo para o mais antigo.
    const grupos: Array<typeof versoes> = [];
    for (const v of [...versoes].sort((a, b) => n(b) - n(a))) {
      const ultimo = grupos[grupos.length - 1];
      if (ultimo && n(ultimo[0]) === n(v)) ultimo.push(v);
      else grupos.push([v]);
    }
    const vigente = grupos.find((g) => g.some((v) => comDado.has(v.id))) ?? grupos[0];
    for (const v of vigente) vigentes.add(v.id);
  }
  return vigentes;
}

interface ContextoVersao {
  entidade: string;
  periodo: string;
  tipoTaxonomia: string | null;
  nomeArquivo: string;
}

interface Coluna {
  key: string;
  entidade: string;
  periodo: string;
}

export function nomeArquivoSanitizado(nomeCaso: string) {
  return nomeCaso
    .normalize("NFD")
    .replace(/[̀-ͯ]/g, "") // remove acentos (marcas de combinação) após NFD
    .replace(/[^a-zA-Z0-9]+/g, "-")
    .replace(/(^-|-$)/g, "");
}

function formatarStatus(status: string) {
  return status === "aceito" ? "ACEITO" : status === "com_ressalva" ? "COM RESSALVA" : "PENDENTE";
}

// Em empate (mais de um campo casando no mesmo lugar), prefere maior
// confiança e rótulo mais curto (mais específico) — mesmo critério de
// `fn_valor_conceito` (db/migrations/0009).
// ---------------------------------------------------------------------------
// ESCALA (milhar/milhão/unidade) — o defeito mais caro que este arquivo tinha.
//
// `campo.unidade` existia, era lido e NUNCA era usado como fator. Cada célula
// gravava `campo.valor_num` cru, então um Balanço em MILHAR somado a um Balancete
// em UNIDADE na mesma coluna dava erro de ~496x — medido, não estimado:
//
//     ATIVO                      27.928.400   <- deveria ser 56.300 (em milhar)
//     Ativo Circulante  =SUM(...) 27.928.400
//       Disponibilidades              500     (milhar)
//       Duplicatas a receber       27.900     (milhar)
//       Clientes nacionais     27.900.000     (unidade)
//
// E sem NENHUMA marca de divergência: a linha de conferência só compara contra o
// total informado pelo documento, e aqui não havia total. AV%, Δ% e todos os
// indicadores de liquidez/endividamento herdavam o número corrompido.
//
// O banco já resolvia isso e o portal não usava: `fn_fator_escala` /
// `fn_valor_em_base` (0023) convertem antes de comparar, e é por isso que a
// reconciliação acertava enquanto o book mentia.
//
// A correção é feita no LIMITE DE NORMALIZAÇÃO (uma vez, logo depois de filtrar as
// versões vigentes) e não em cada ponto de escrita. Isso é deliberado: convertendo
// os valores na entrada, TODO consumidor a jusante — células, `SUM`, detecção de
// subtotal, AV%/Δ%, indicadores, linha de conferência, aba Modelagem — passa a
// estar correto sem precisar ser tocado. Corrigir célula por célula deixaria de
// fora exatamente os consumidores que ninguém lembra.
const FATOR_ESCALA: Record<string, number> = { unidade: 1, milhar: 1_000, milhao: 1_000_000 };

// Como a escala é escrita para humano. Vai no cabeçalho de cada aba de valores:
// planilha financeira sem escala declarada é planilha que alguém vai ler errado.
export const ROTULO_ESCALA: Record<string, string> = {
  unidade: "R$",
  milhar: "R$ mil",
  milhao: "R$ milhões",
};

export interface EscalaDoExport {
  alvo: string;                       // escala em que TODO valor do book está
  converteu: number;                  // quantos campos foram convertidos
  semDeclaracao: number;              // quantos não declaravam escala
  escalasEncontradas: string[];        // o que apareceu nos documentos
}

// A escala do book é a PREDOMINANTE entre as declaradas. Não é média nem "a
// primeira": é a que mais linhas declaram, porque converter a minoria produz
// menos ruído de leitura. Sem nenhuma escala declarada → 'unidade', que preserva
// os números exatamente como estão hoje.
export function escolherEscalaAlvo(campos: CampoExtraido[]): string {
  const contagem = new Map<string, number>();
  for (const c of campos) {
    if (c.unidade && FATOR_ESCALA[c.unidade] != null) {
      contagem.set(c.unidade, (contagem.get(c.unidade) ?? 0) + 1);
    }
  }
  if (contagem.size === 0) return "unidade";
  return [...contagem.entries()].sort((a, b) => b[1] - a[1] || FATOR_ESCALA[b[0]] - FATOR_ESCALA[a[0]])[0][0];
}

// Converte todo valor para a escala alvo. Campo sem escala declarada é deixado
// COMO ESTÁ e contado em `semDeclaracao`: assumir 'unidade' para ele seria
// inventar um fator de 1000x justamente onde não se sabe — e o comentário da
// fonte de `normalizarUnidade` já diz que "errar em 1000x é pior que não saber".
// A nota de proveniência da célula declara essa suposição, uma por uma.
export function normalizarEscala(
  campos: CampoExtraido[],
  alvo: string,
): { campos: CampoExtraido[]; escala: EscalaDoExport } {
  const fatorAlvo = FATOR_ESCALA[alvo] ?? 1;
  let converteu = 0;
  let semDeclaracao = 0;
  const encontradas = new Set<string>();

  const saida = campos.map((c) => {
    if (!c.unidade || FATOR_ESCALA[c.unidade] == null) {
      semDeclaracao += 1;
      return c;
    }
    encontradas.add(c.unidade);
    if (c.unidade === alvo || c.valor_num == null) return { ...c, unidade: alvo, unidade_original: c.unidade };
    const fator = FATOR_ESCALA[c.unidade] / fatorAlvo;
    converteu += 1;
    return { ...c, valor_num: c.valor_num * fator, unidade: alvo, unidade_original: c.unidade };
  });

  return {
    campos: saida,
    escala: { alvo, converteu, semDeclaracao, escalasEncontradas: [...encontradas].sort() },
  };
}

function melhorCampo(campos: CampoExtraido[]): CampoExtraido {
  return [...campos].sort((a, b) => (b.confianca ?? 0) - (a.confianca ?? 0) || a.chave.length - b.chave.length)[0];
}

// Fonte compacta (8pt) + caixa de comentário ampliada (ver `ampliarNotas`,
// pós-processamento do .xlsx — a API do ExcelJS não expõe tamanho de caixa de
// nota, só o conteúdo/fonte) — as anotações tinham texto cortado ao abrir
// (pedido do dono, sessão 7 cont.¹⁵).
const NOTA_FONT: Partial<ExcelJS.Font> = { size: 8, name: "Calibri" };
function comoNota(texto: string): ExcelJS.Comment {
  return { texts: [{ text: texto, font: NOTA_FONT }] };
}

function notaProveniencia(campo: CampoExtraido, ctx: ContextoVersao) {
  const linhas = [
    `Rótulo original: "${campo.chave}"`,
    campo.entidade_coluna ? `Coluna de origem no documento: ${campo.entidade_coluna}` : null,
    `Arquivo: ${ctx.nomeArquivo}`,
    // Escala: informação de AUDITORIA, não detalhe. Antes desta linha as abas
    // classificadas não mostravam a escala nem no hover, então um número
    // convertido era indistinguível de um número original — e um número SEM
    // escala declarada era indistinguível de um que declarava a escala do book.
    campo.unidade_original && campo.unidade_original !== campo.unidade
      ? `Escala: convertido de ${ROTULO_ESCALA[campo.unidade_original] ?? campo.unidade_original} para ${ROTULO_ESCALA[campo.unidade ?? ""] ?? campo.unidade}`
      : campo.unidade
        ? `Escala: ${ROTULO_ESCALA[campo.unidade] ?? campo.unidade}`
        : `Escala: NÃO declarada no documento — valor usado como está, sem conversão`,
    campo.origem_pagina != null ? `Página: ${campo.origem_pagina}` : null,
    campo.confianca != null ? `Confiança da extração: ${Math.round(campo.confianca * 100)}%` : null,
    `Status: ${formatarStatus(campo.status_aceite)}`,
    campo.status_aceite === "aceito" && campo.aceito_por ? `Aceito por: ${campo.aceito_por}` : null,
  ].filter(Boolean);
  return linhas.join("\n");
}

// Separador de chave composta. É um caractere que NUNCA aparece num rótulo
// contábil, e é isso que se quer: com espaço simples, entidade "A B" + período
// "C" colide com entidade "A" + período "B C" (colunas distintas fundidas numa
// só). Escrito como escape, e não como o byte literal, para não deixar um
// caractere invisível no fonte.
const CHAVE_SEP = "\u0000";

const VALOR_NUM_FMT = "#,##0.00;(#,##0.00)";
const PENDENTE_FILL: ExcelJS.Fill = { type: "pattern", pattern: "solid", fgColor: { argb: "FFFFF3CD" } };
const HEADER_FILL: ExcelJS.Fill = { type: "pattern", pattern: "solid", fgColor: { argb: "FFE5E7EB" } };
const SECAO_FILL: ExcelJS.Fill = { type: "pattern", pattern: "solid", fgColor: { argb: "FFF3F4F6" } };
const NAO_CLASSIFICADO_FILL: ExcelJS.Fill = { type: "pattern", pattern: "solid", fgColor: { argb: "FFF3E8FF" } };
const THIN_TOP_BORDER: Partial<ExcelJS.Borders> = { top: { style: "thin" } };
const DOUBLE_TOP_BORDER: Partial<ExcelJS.Borders> = { top: { style: "double" } };

interface GrupoConta {
  label: string;
  porColuna: Map<string, CampoExtraido[]>; // colKey → campos casados ali (melhorCampo escolhe 1)
}

function novoGrupo(label: string): GrupoConta {
  return { label, porColuna: new Map() };
}

function adicionarAoGrupo(grupo: GrupoConta, colKey: string, campo: CampoExtraido) {
  if (!grupo.porColuna.has(colKey)) grupo.porColuna.set(colKey, []);
  grupo.porColuna.get(colKey)!.push(campo);
}

// Escreve uma linha de conta (rótulo + valor por coluna + nota de
// proveniência + estilo pendente/total) numa `sheet` já criada. `valuePos[i]`
// = posição (número da coluna Excel) onde a coluna de valor `i` é escrita — as
// colunas de valor NÃO são mais contíguas (intercalam AV%/Δ%), então tudo é
// endereçado pelo plano de colunas, não por `i + 2`.
function escreverLinhaConta(
  sheet: ExcelJS.Worksheet,
  rowIndex: number,
  label: string,
  nivel: number,
  colunas: Coluna[],
  valuePos: number[],
  grupo: GrupoConta,
  opts: { negrito?: boolean; borda?: "simples" | "dupla" },
  contextoPorVersao: Map<string, ContextoVersao>,
) {
  const row = sheet.getRow(rowIndex);
  row.getCell(1).value = label;
  row.getCell(1).alignment = { indent: nivel };
  if (opts.negrito) row.font = { bold: true };

  colunas.forEach((col, i) => {
    const cell = row.getCell(valuePos[i]);
    if (opts.borda === "simples") cell.border = THIN_TOP_BORDER;
    if (opts.borda === "dupla") cell.border = DOUBLE_TOP_BORDER;
    const candidatos = grupo.porColuna.get(col.key);
    if (!candidatos || candidatos.length === 0) return;
    const campo = melhorCampo(candidatos);
    cell.value = campo.valor_num ?? campo.valor_texto ?? null;
    if (typeof cell.value === "number") cell.numFmt = VALOR_NUM_FMT;
    if (campo.status_aceite !== "aceito") {
      cell.fill = PENDENTE_FILL;
      cell.font = { ...(row.font ?? {}), italic: true };
    }
    const ctx = contextoPorVersao.get(campo.documento_versao_id);
    if (ctx) {
      cell.note = comoNota(notaProveniencia(campo, ctx));
    }
  });
}

const DIVERGENCIA_FILL: ExcelJS.Fill = { type: "pattern", pattern: "solid", fgColor: { argb: "FFFCE4E4" } };
const MARGEM_FONT: Partial<ExcelJS.Font> = { italic: true, size: 9, color: { argb: "FF2563EB" } };
// Âncora da DRE → rótulo da linha de margem (% da Receita Líquida).
const MARGEM_LABEL: Record<string, string> = {
  lucro_bruto: "Margem Bruta %",
  resultado_operacional: "Margem Operacional %",
  lucro_liquido: "Margem Líquida %",
};

// ----- Camada analítica (f0/08): análise vertical / horizontal / indicadores.
// Colunas AV% (análise vertical, common-size) e Δ% (análise horizontal, entre
// períodos comparáveis da mesma entidade) são FÓRMULAS transparentes sobre o
// dado já extraído — não projetam nem inventam número. Estilo discreto
// (cinza-azulado, menor) para não competir com os valores.
const SUBTOTAL_INFO_FONT: Partial<ExcelJS.Font> = { italic: true, size: 8, color: { argb: "FF7C3AED" } };
const ANALISE_FONT: Partial<ExcelJS.Font> = { italic: true, size: 9, color: { argb: "FF64748B" } };
const ANALISE_HEADER_FILL: ExcelJS.Fill = { type: "pattern", pattern: "solid", fgColor: { argb: "FFEEF2FF" } };
const AV_FMT = "0.0%";
const DELTA_FMT = "+0.0%;-0.0%;0.0%";
const RATIO_FMT = "0.00"; // índices "x vezes" (liquidez, participação)
const PCT_FMT = "0.0%"; // índices em % (endividamento, composição, imobilização)
const INDICADOR_TITULO_FILL: ExcelJS.Fill = { type: "pattern", pattern: "solid", fgColor: { argb: "FFE0E7FF" } };
const INDICADOR_LABEL_FONT: Partial<ExcelJS.Font> = { size: 10, color: { argb: "FF1E293B" } };

// Plano de colunas do relatório: as colunas de VALOR (entidade×período) não são
// mais contíguas — cada uma pode ser seguida de sua AV% e, quando comparável ao
// período anterior da MESMA entidade, de uma Δ%. Centraliza o mapeamento
// "índice da coluna de valor → coluna Excel real" para que todas as fórmulas
// (subtotais, margens, indicadores) refiram a célula certa.
interface PlanoColunas {
  valuePos: number[]; // i (coluna de valor) → nº da coluna Excel
  avPos: Array<number | null>; // i → coluna Excel da AV% (null quando não se aplica, ex.: Fluxo)
  deltas: Array<{ pos: number; atual: number; anterior: number }>; // colunas Δ%
  ultimaColuna: number;
}

function planejarColunas(colunas: Coluna[], comAV: boolean): PlanoColunas {
  const valuePos: number[] = [];
  const avPos: Array<number | null> = [];
  const deltas: Array<{ pos: number; atual: number; anterior: number }> = [];
  let col = 2; // coluna 1 = rótulo da conta
  colunas.forEach((coluna, i) => {
    const naoEntidade = tipoColunaNaoEntidade(coluna.entidade) != null;
    valuePos[i] = col++;
    // AV% não se aplica a coluna de ajuste/total (ver tipoColunaNaoEntidade).
    avPos[i] = comAV && !naoEntidade ? col++ : null;
    // Δ% só entre períodos DIFERENTES da MESMA entidade, adjacentes na ordenação
    // (as colunas vêm ordenadas por entidade e depois período).
    if (!naoEntidade && i > 0 && colunas[i - 1].entidade === coluna.entidade
        && colunas[i - 1].periodo !== coluna.periodo
        && tipoColunaNaoEntidade(colunas[i - 1].entidade) == null) {
      deltas.push({ pos: col++, atual: i, anterior: i - 1 });
    }
  });
  return { valuePos, avPos, deltas, ultimaColuna: col - 1 };
}

// valor_num "melhor" de um grupo de conta numa coluna (para conferir a soma em
// JS contra o total que o documento trouxe — a célula em si leva a FÓRMULA).
function valorNumDoGrupo(grupo: GrupoConta, colKey: string): number | null {
  const c = grupo.porColuna.get(colKey);
  if (!c || c.length === 0) return null;
  const campo = melhorCampo(c);
  return typeof campo.valor_num === "number" ? campo.valor_num : null;
}

// Uma linha extraída é o SUBTOTAL de um agrupamento do próprio documento (e não
// uma conta)? Demonstrações reais são hierárquicas: sob "Ativo Circulante" vêm
// os agrupamentos "Disponível", "Contas a Receber", "Estoques"… cada um com o
// PRÓPRIO subtotal impresso, seguido das contas que o compõem. Sem reconhecer
// isso, o subtotal entra no bucket como se fosse conta e o `SUM` da seção soma
// o subtotal MAIS os seus componentes — dobrando tudo. Achado com dado real
// (book Vertentes): `SUM` do Ativo Circulante deu 137.865 contra 67.878
// informados = 2,03x, contaminando também AV% e todos os indicadores.
//
// A `ancoraBalanco` de statement-templates.ts só reconhece total quando o
// rótulo tem "total"/"soma" ou é feito só de palavras estruturais — não cobre
// "Disponível"/"Estoques", que são nomes de agrupamento comuns. Aqui a detecção
// é ESTRUTURAL, a partir do próprio documento, por dois sinais independentes:
//
//   (A) o rótulo da linha é IGUAL ao nome de seção (`secao`) que outras linhas
//       do mesmo documento declaram — ou seja, o documento diz que aquele nome
//       é um agrupamento, e esta linha é o total dele;
//   (B) o valor da linha é IGUAL à soma das OUTRAS linhas que compartilham a
//       mesma `secao`, em TODAS as colunas com dado — coincidência estatística
//       praticamente impossível em documento multi-coluna.
//
// Nada é descartado: a linha continua visível (marcada como subtotal informado),
// só sai da SOMA. Sem `secao` anotada, nenhum dos sinais dispara e o
// comportamento é o de antes (conservador).
/**
 * Subtotal reconhecido pela ORDEM em que o documento imprime as linhas.
 *
 * Modo de falha que isto conserta (teste v28, VT Logística): a seção saiu com
 * Ativo Circulante 7.254 onde o documento diz 3.961, porque "Contas a Receber"
 * (3.293) foi somada JUNTO com "Fretes a receber" (3.562) e "(-) PECLD" (−269),
 * que são os seus componentes. As duas detecções estruturais existentes não
 * pegam esse caso: uma exige que alguma linha declare `secao` com o nome do
 * subtotal (a extração daquele arquivo anotou a seção de TOPO em todas), e a
 * outra exige que o valor bata com a soma dos irmãos da MESMA seção (ali os
 * irmãos são o circulante inteiro). E o documento não trouxe linha de total,
 * então nem a conferência acusava — o número errado não tinha como ser visto.
 *
 * O sinal que sobra é o que toda demonstração publicada dá: o subtotal vem
 * impresso IMEDIATAMENTE ANTES dos seus componentes.
 *
 * Critério deliberadamente ESTREITO — um falso positivo aqui tira da soma uma
 * conta legítima, que é pior que o defeito original:
 *   • exige `ordem` nas linhas (extração antiga não tem: nada acontece);
 *   • exige pelo menos DOIS componentes seguidos (um só é ambíguo — pode ser
 *     reclassificação, arredondamento ou simplesmente coincidência);
 *   • exige casamento EXATO (1 centavo) da soma, na MESMA coluna;
 *   • só dentro da mesma `secao` declarada, e para valor não nulo;
 *   • a varredura para no primeiro casamento, e retoma DEPOIS do último
 *     componente consumido — assim uma cascata de subtotais não se sobrepõe.
 */
function detectarSubtotaisPorOrdem(
  camposDaAba: Array<{ campo: CampoExtraido; colKey: string }>,
): Set<string> {
  const subtotais = new Set<string>();
  // Agrupa por (versão do documento × coluna × seção): a sequência impressa só
  // faz sentido dentro do mesmo documento e da mesma coluna de valor.
  const grupos = new Map<string, CampoExtraido[]>();
  for (const { campo, colKey } of camposDaAba) {
    if (campo.ordem == null) continue;
    const k = `${campo.documento_versao_id}${CHAVE_SEP}${colKey}${CHAVE_SEP}${normalizar(campo.secao ?? "")}`;
    if (!grupos.has(k)) grupos.set(k, []);
    grupos.get(k)!.push(campo);
  }

  for (const linhas of grupos.values()) {
    if (linhas.length < 3) continue; // subtotal + 2 componentes é o mínimo
    linhas.sort((a, b) => (a.ordem ?? 0) - (b.ordem ?? 0));
    let i = 0;
    while (i < linhas.length) {
      const candidato = linhas[i];
      const valor = candidato.valor_num;
      if (valor == null || valor === 0) { i++; continue; }
      // Quantos componentes seguidos bastam para caracterizar o subtotal:
      //   • 1, quando o rótulo já É nome de agrupamento contábil ("Contas a
      //     Receber", "Obrigações Tributárias") — aí há DOIS sinais
      //     independentes, e um componente só é suficiente;
      //   • 2, quando o rótulo não diz nada — só a aritmética sustenta, e uma
      //     coincidência de dois valores consecutivos é bem menos provável.
      // Sem o caso de 1 componente, "Outros Créditos 340" seguido de
      // "Adiantamentos diversos 340" (teste v29) ficava fora e mantinha 340 de
      // dupla contagem.
      const minComponentes = ehNomeDeAgrupamento(candidato.chave) ? 1 : 2;
      let acumulado = 0;
      let casouEm = -1;
      for (let j = i + 1; j < linhas.length; j++) {
        const v = linhas[j].valor_num;
        if (v == null) break;
        acumulado += v;
        if (j - i >= minComponentes && Math.abs(acumulado - valor) < 0.01) { casouEm = j; break; }
      }
      if (casouEm > 0) {
        subtotais.add(candidato.id);
        i = casouEm + 1; // retoma depois dos componentes consumidos
      } else {
        i++;
      }
    }
  }
  return subtotais;
}

function detectarSubtotaisInformados(
  camposDaAba: Array<{ campo: CampoExtraido; colKey: string }>,
): Set<string> {
  const subtotais = new Set<string>();
  const secoesDeclaradas = new Set<string>();
  for (const { campo } of camposDaAba) {
    const s = normalizar(campo.secao ?? "");
    if (s) secoesDeclaradas.add(s);
  }

  // (A) rótulo == nome de um agrupamento declarado pelo documento.
  for (const { campo } of camposDaAba) {
    const chaveNorm = normalizar(campo.chave);
    if (!chaveNorm || !secoesDeclaradas.has(chaveNorm)) continue;
    // exige que o agrupamento tenha MEMBROS (linhas cuja secao é esse nome e
    // cujo rótulo é diferente) — senão não há nada que este total duplique.
    const temMembros = camposDaAba.some(
      ({ campo: c }) => normalizar(c.secao ?? "") === chaveNorm && normalizar(c.chave) !== chaveNorm,
    );
    if (temMembros) subtotais.add(campo.id);
  }

  // (B) valor == soma dos irmãos da mesma seção, em todas as colunas com dado.
  const porSecao = new Map<string, Array<{ campo: CampoExtraido; colKey: string }>>();
  for (const item of camposDaAba) {
    const s = normalizar(item.campo.secao ?? "");
    if (!s) continue;
    if (!porSecao.has(s)) porSecao.set(s, []);
    porSecao.get(s)!.push(item);
  }
  for (const itens of porSecao.values()) {
    const porChave = new Map<string, Array<{ campo: CampoExtraido; colKey: string }>>();
    for (const it of itens) {
      const k = normalizar(it.campo.chave);
      if (!porChave.has(k)) porChave.set(k, []);
      porChave.get(k)!.push(it);
    }
    if (porChave.size < 3) continue; // precisa de >=2 componentes + o subtotal
    for (const [chaveCandidata, ocorrencias] of porChave) {
      let colunasConferidas = 0;
      let bate = true;
      const colunas = new Set(ocorrencias.map((o) => o.colKey));
      for (const colKey of colunas) {
        const cand = ocorrencias.find((o) => o.colKey === colKey)?.campo.valor_num;
        if (typeof cand !== "number") continue;
        let soma = 0;
        let n = 0;
        for (const [k, occ] of porChave) {
          if (k === chaveCandidata) continue;
          const v = occ.find((o) => o.colKey === colKey)?.campo.valor_num;
          if (typeof v === "number") { soma += v; n++; }
        }
        if (n < 2) continue;
        colunasConferidas++;
        if (Math.abs(soma - cand) > Math.max(0.01, Math.abs(cand) * 0.005)) { bate = false; break; }
      }
      if (bate && colunasConferidas > 0) {
        for (const o of ocorrencias) subtotais.add(o.campo.id);
      }
    }
  }
  return subtotais;
}

// ----- Aba classificada por seção (Balanço/Balancete/DRE/Fluxo/Combinado) --
// Totais/subtotais NÃO são valores estáticos: são FÓRMULAS Excel (=SUM(...)),
// transparentes e recalculáveis, colocadas NO cabeçalho de cada seção/grupo
// (f0/07 evoluído nesta sessão — pedido do dono). O total que o PRÓPRIO
// documento trouxe (quando existe) aparece numa linha de conferência logo
// abaixo; se a soma calculada divergir do informado, ambos são sinalizados
// (anti-ancoragem: nada que o documento disse é perdido, e divergência vira
// sinal visível — uma checagem de reconciliação embutida).
function construirAbaClassificada(
  workbook: ExcelJS.Workbook,
  nomeAba: string,
  estrutura: EstruturaDemonstracao,
  colunas: Coluna[],
  camposDaAba: Array<{ campo: CampoExtraido; colKey: string }>,
  contextoPorVersao: Map<string, ContextoVersao>,
) {
  const sheet = workbook.addWorksheet(nomeAba, { views: [{ state: "frozen", xSplit: 1, ySplit: 1 }] });
  // AV% (análise vertical) só faz sentido onde há uma base natural (Ativo Total
  // no Balanço; Receita Líquida na DRE). No Fluxo de Caixa não há base — só Δ%.
  const comAV = estrutura !== "fluxo_caixa";
  const plano = planejarColunas(colunas, comAV);
  const colLetra = (i: number) => sheet.getColumn(plano.valuePos[i]).letter;

  sheet.getColumn(1).width = 46;
  plano.valuePos.forEach((pos) => {
    sheet.getColumn(pos).width = 18;
  });
  plano.avPos.forEach((pos) => {
    if (pos != null) sheet.getColumn(pos).width = 8;
  });
  plano.deltas.forEach((d) => {
    sheet.getColumn(d.pos).width = 12;
  });

  const headerRow = sheet.getRow(1);
  headerRow.getCell(1).value = "Conta";
  colunas.forEach((col, i) => {
    const cell = headerRow.getCell(plano.valuePos[i]);
    const tipoCol = tipoColunaNaoEntidade(col.entidade);
    const sufixo = tipoCol === "ajuste" ? " (ajuste — não é entidade)"
      : tipoCol === "total" ? " (total do documento — não somar com as demais)" : "";
    cell.value = `${col.entidade} — ${col.periodo}${sufixo}`;
    cell.fill = tipoCol ? ANALISE_HEADER_FILL : HEADER_FILL;
    const av = plano.avPos[i];
    if (av != null) {
      const avCell = headerRow.getCell(av);
      avCell.value = "AV%";
      avCell.fill = ANALISE_HEADER_FILL;
    }
  });
  plano.deltas.forEach((d) => {
    const cell = headerRow.getCell(d.pos);
    cell.value = `Δ% ${colunas[d.anterior].periodo}→${colunas[d.atual].periodo}`;
    cell.fill = ANALISE_HEADER_FILL;
  });
  headerRow.getCell(1).fill = HEADER_FILL;
  headerRow.font = { bold: true };
  headerRow.alignment = { wrapText: true, vertical: "middle" };

  // Classifica cada campo: conta numa seção (bucket), âncora (total que o doc
  // trouxe, por chave de nó), ou não classificado.
  const contasPorSecao = new Map<string, Map<string, GrupoConta>>();
  const valoresPorAncora = new Map<string, GrupoConta>();
  const naoClassificados = new Map<string, GrupoConta>();
  const bucket = (mapa: Map<string, GrupoConta>, campo: CampoExtraido, colKey: string) => {
    // normalizar() (acento/espaço) para que "Salários" e "Salarios", ou
    // "Duplicatas  a Receber" e "Duplicatas a Receber" (deriva de grafia entre
    // períodos/entidades da mesma empresa), caiam na MESMA linha em vez de
    // gerar dois grupos que quebram o alinhamento entidade×período.
    const chaveNorm = normalizar(campo.chave);
    if (!mapa.has(chaveNorm)) mapa.set(chaveNorm, novoGrupo(campo.chave));
    adicionarAoGrupo(mapa.get(chaveNorm)!, colKey, campo);
  };
  // Subtotais de agrupamento que o documento trouxe (ver
  // `detectarSubtotaisInformados`): ficam FORA da soma da seção — senão o
  // `SUM` conta o subtotal e os seus componentes, dobrando o total.
  // Duas detecções, união dos resultados: a estrutural (rótulo == agrupamento
  // declarado, ou valor == soma dos irmãos) e a por ORDEM DE IMPRESSÃO, que é a
  // única que pega o caso em que a extração anotou a seção de topo em todas as
  // linhas e o documento não trouxe linha de total.
  const idsSubtotal = new Set([
    ...detectarSubtotaisInformados(camposDaAba),
    ...detectarSubtotaisPorOrdem(camposDaAba),
  ]);
  const subtotaisInformados = new Map<string, Map<string, GrupoConta>>(); // secaoKey → grupos

  // Classificação de cada linha, em DOIS passes.
  //
  // Passe 1: a regra de sempre (âncora / seção / palavra-chave / sugestão da IA).
  //
  // Passe 2 — CONSENSO DE IRMÃOS: demonstrações reais são hierárquicas, e a
  // `secao` que a IA anota costuma ser o nome da SUBSEÇÃO ("Estoques",
  // "Disponível", "Outras Obrigações"), que não carrega sinal de Ativo/Passivo.
  // Resultado (achado no teste v24): uma conta com vocabulário fora das listas
  // — "(-) PECLD", "Produtos em elaboração" — caía em "Contas Não
  // Classificadas" mesmo estando declaradamente sob "Estoques", e a soma da
  // seção ficava furada. Aqui a linha herda a seção dos IRMÃOS: se as outras
  // linhas do MESMO agrupamento foram classificadas, e de forma unânime, esta
  // vai para o mesmo lugar. É como um humano lê a demonstração ("está sob
  // Estoques, e o resto de Estoques é Ativo Circulante"), não depende de
  // vocabulário novo, e permanece conservador: sem irmãos classificados ou com
  // irmãos divergentes, a linha continua em "Não Classificadas".
  type Item = { campo: CampoExtraido; colKey: string };
  const classificado = new Map<string, { secaoKey: string | null; ancoraKey: string | null }>();
  const semClassificacao: Item[] = [];
  for (const item of camposDaAba) {
    const { campo } = item;
    if (campo.valor_num == null && campo.valor_texto == null) continue;
    const r = classificarConta(estrutura, campo.secao, campo.chave, campo.secao_canonica);
    classificado.set(campo.id, r);
    if (!r.secaoKey && !r.ancoraKey) semClassificacao.push(item);
  }
  if (semClassificacao.length > 0) {
    const consensoPorSecao = new Map<string, Set<string>>();
    for (const { campo } of camposDaAba) {
      const sec = normalizar(campo.secao ?? "");
      const r = classificado.get(campo.id);
      if (!sec || !r?.secaoKey) continue;
      if (!consensoPorSecao.has(sec)) consensoPorSecao.set(sec, new Set());
      consensoPorSecao.get(sec)!.add(r.secaoKey);
    }
    for (const { campo } of semClassificacao) {
      const sec = normalizar(campo.secao ?? "");
      const candidatas = sec ? consensoPorSecao.get(sec) : undefined;
      if (candidatas && candidatas.size === 1) {
        classificado.set(campo.id, { secaoKey: [...candidatas][0], ancoraKey: null });
      }
    }
  }

  for (const { campo, colKey } of camposDaAba) {
    if (campo.valor_num == null && campo.valor_texto == null) continue;
    const { secaoKey, ancoraKey } = classificado.get(campo.id) ?? { secaoKey: null, ancoraKey: null };
    if (ancoraKey) {
      if (!valoresPorAncora.has(ancoraKey)) valoresPorAncora.set(ancoraKey, novoGrupo(campo.chave));
      adicionarAoGrupo(valoresPorAncora.get(ancoraKey)!, colKey, campo);
    } else if (secaoKey && idsSubtotal.has(campo.id)) {
      if (!subtotaisInformados.has(secaoKey)) subtotaisInformados.set(secaoKey, new Map());
      bucket(subtotaisInformados.get(secaoKey)!, campo, colKey);
    } else if (secaoKey) {
      if (!contasPorSecao.has(secaoKey)) contasPorSecao.set(secaoKey, new Map());
      bucket(contasPorSecao.get(secaoKey)!, campo, colKey);
    } else {
      bucket(naoClassificados, campo, colKey);
    }
  }

  let rowIndex = 2;
  // Linhas monetárias elegíveis a AV%/Δ% (contas + subtotais + âncoras);
  // exclui cabeçalhos de seção sem valor, linhas de conferência e margens.
  const linhasValor = new Set<number>();
  // Balanço: nó da estrutura → linha do seu subtotal (para os indicadores).
  const noRow = new Map<string, number>();
  // …e o VALOR do nó por coluna, para os indicadores só emitirem índice que
  // realmente resolve (fórmula existir não basta: os insumos podem estar
  // vazios ou o denominador zerado, e o índice sairia como linha vazia).
  const noValor = new Map<string, Map<string, number>>();
  let baseTotalRow: number | null = null; // base da AV% (Ativo Total / Receita Líquida)

  const escrever = (label: string, nivel: number, grupo: GrupoConta, opts: { negrito?: boolean; borda?: "simples" | "dupla" } = {}) => {
    const r = rowIndex++;
    escreverLinhaConta(sheet, r, label, nivel, colunas, plano.valuePos, grupo, opts, contextoPorVersao);
    linhasValor.add(r);
    return r;
  };

  // Subtotais de agrupamento que o documento trouxe: emitidos DEPOIS do range
  // do SUM (portanto fora da soma) e com estilo próprio, para o analista ver o
  // que o documento declarou sem que isso dobre o total.
  const escreverSubtotaisInformados = (secaoKey: string, nivel: number) => {
    const grupos = subtotaisInformados.get(secaoKey);
    if (!grupos) return;
    for (const g of grupos.values()) {
      const r = rowIndex++;
      const row = sheet.getRow(r);
      row.getCell(1).value = `↳ subtotal informado: ${g.label}`;
      row.getCell(1).alignment = { indent: nivel + 1 };
      row.getCell(1).font = SUBTOTAL_INFO_FONT;
      row.getCell(1).note = comoNota(
        "Subtotal de agrupamento trazido pelo próprio documento. Fica FORA da soma da seção de "
        + "propósito: somá-lo junto com as contas que ele agrega dobraria o total.",
      );
      colunas.forEach((col, i) => {
        const cell = row.getCell(plano.valuePos[i]);
        const v = valorNumDoGrupo(g, col.key);
        if (v == null) return;
        cell.value = v;
        cell.numFmt = VALOR_NUM_FMT;
        cell.font = SUBTOTAL_INFO_FONT;
      });
      linhasValor.add(r);
    }
  };

  // Linha de conferência: o total que o DOCUMENTO trouxe (extraído), logo
  // abaixo do cabeçalho. Se divergir do subtotal calculado, pinta ambas as
  // células e anota o motivo (checagem de reconciliação embutida).
  // Devolve o índice da linha, para o cabeçalho poder apontar para ela.
  const escreverConferenciaExtraido = (nivel: number, ancoraKey: string, cabecalhoIdx: number, subtotalNum: Map<string, number>): number | null => {
    const grupo = valoresPorAncora.get(ancoraKey);
    if (!grupo) return null;
    const idx = rowIndex++;
    const row = sheet.getRow(idx);
    row.getCell(1).value = "↳ total informado no documento";
    row.getCell(1).alignment = { indent: nivel + 1 };
    row.getCell(1).font = { italic: true, size: 9, color: { argb: "FF6B7280" } };
    colunas.forEach((col, i) => {
      const cell = row.getCell(plano.valuePos[i]);
      const vExtraido = valorNumDoGrupo(grupo, col.key);
      if (vExtraido == null) return;
      cell.value = vExtraido;
      cell.numFmt = VALOR_NUM_FMT;
      cell.font = { italic: true, size: 9, color: { argb: "FF6B7280" } };
      const vCalc = subtotalNum.get(col.key);
      if (vCalc != null && Math.abs(vCalc - vExtraido) > Math.max(0.01, Math.abs(vExtraido) * 0.005)) {
        cell.fill = DIVERGENCIA_FILL;
        cell.note = comoNota(
          `Divergência: soma das contas listadas = ${vCalc.toLocaleString("pt-BR", { minimumFractionDigits: 2, maximumFractionDigits: 2 })}, `
          + `informado no documento = ${vExtraido.toLocaleString("pt-BR", { minimumFractionDigits: 2, maximumFractionDigits: 2 })}. `
          + `Duas causas possíveis, e elas pedem conferências diferentes. (1) O documento imprime `
          + `subtotais intermediários (ex.: "Disponível" acima de "Caixa e bancos" + "Aplicações") e a `
          + `soma conta o subtotal E os seus componentes — aí o informado é o certo. (2) Uma conta desta `
          + `seção foi classificada em OUTRA seção: o informado a inclui, a soma listada não, e o TOTAL `
          + `DO GRUPO passa a contá-la duas vezes. Achado real no teste v33: "Ferramental e moldes" `
          + `(3.600) caiu em "Outros Ativos Não Circulantes" enquanto o total do Imobilizado já a `
          + `continha. Se a diferença bater com uma conta que aparece em outra seção, é o caso (2).`,
        );
        // sinaliza também a célula do cabeçalho
        sheet.getRow(cabecalhoIdx).getCell(plano.valuePos[i]).fill = DIVERGENCIA_FILL;
      }
    });
    return idx;
  };

  // Linha "soma das contas listadas": a fórmula =SUM(range) sai do cabeçalho e
  // vem para cá quando o documento informou o total da seção.
  //
  // Por quê: demonstração real é hierárquica e imprime subtotais de subseção.
  // Somar as contas listadas conta o subtotal E os seus componentes — dobra o
  // total. Detectar o subtotal pela estrutura (`detectarSubtotaisInformados`)
  // resolve quando a IA anota a SUBSEÇÃO em `secao`; quando ela anota a seção de
  // topo, o subtotal impresso passa e a soma sai 2x (achado no teste v25: 36 de
  // 44 somas do Balanço divergiam, várias exatamente 2,00x).
  //
  // Então o número da seção deixa de depender de acertarmos a hierarquia: quando
  // o documento diz quanto é, o cabeçalho aponta para o que ele disse, e a nossa
  // soma vira uma LINHA DE CHECAGEM ao lado. Nada é escondido — a divergência
  // fica visível e pintada, que é o sinal útil — e AV%, Δ% e indicadores passam a
  // usar o número autoritativo em vez de um que pode estar dobrado.
  const escreverSomaCalculada = (nivel: number, rotulo: string, formulaDaColuna: (i: number) => string) => {
    const idx = rowIndex++;
    const row = sheet.getRow(idx);
    row.getCell(1).value = `↳ ${rotulo} (checagem)`;
    row.getCell(1).alignment = { indent: nivel + 1 };
    row.getCell(1).font = { italic: true, size: 9, color: { argb: "FF6B7280" } };
    row.getCell(1).note = comoNota(
      "Soma calculada por nós, para conferir contra o total que o documento informou (linha acima). "
      + "Quando as duas divergem, quase sempre é porque o documento traz subtotais intermediários, "
      + "que a soma conta duas vezes — por isso o valor da seção segue o informado, não esta soma.",
    );
    colunas.forEach((col, i) => {
      const cell = row.getCell(plano.valuePos[i]);
      cell.value = { formula: formulaDaColuna(i) } as ExcelJS.CellFormulaValue;
      cell.numFmt = VALOR_NUM_FMT;
      cell.font = { italic: true, size: 9, color: { argb: "FF6B7280" } };
    });
    return idx;
  };

  if (estrutura === "balanco") {
    const outline = new Map(BALANCO_OUTLINE.map((n) => [n.key, n]));
    // Emite um nó (recursivo): cabeçalho com fórmula (soma das contas-folha ou
    // dos subtotais dos filhos), contas indentadas, conferência do extraído.
    // Retorna { idx, subtotalNum } para o pai somar.
    const emitirNo = (chave: string): { idx: number; subtotalNum: Map<string, number> } | null => {
      const no = outline.get(chave)!;
      const fill = no.papel === "subsecao" ? SECAO_FILL : HEADER_FILL;
      const subtotalNum = new Map<string, number>();

      if (no.folha) {
        const contas = [...(contasPorSecao.get(no.key)?.values() ?? [])];
        const temAncora = valoresPorAncora.has(no.key);
        // Seção SEM NENHUM DADO não é emitida — em nenhum nível. O template
        // canônico (CPC 26 / art. 178) existe para ORDENAR o que o documento
        // trouxe, não para impor linhas que o documento não tem: antes, uma
        // empresa sem Realizável LP nem Intangível ganhava linhas de subgrupo em
        // branco, e uma sem Passivo Não Circulante ganhava um "0" que nós
        // inventamos (o documento não disse zero — não disse nada).
        if (contas.length === 0 && !temAncora) return null;
        // reserva o cabeçalho; escreve as contas; depois preenche a fórmula.
        const cabIdx = rowIndex++;
        const primeira = rowIndex;
        for (const conta of contas) {
          escrever(conta.label, no.nivel + 1, conta);
          colunas.forEach((col) => {
            const v = valorNumDoGrupo(conta, col.key);
            if (v != null) subtotalNum.set(col.key, (subtotalNum.get(col.key) ?? 0) + v);
          });
        }
        const ultima = rowIndex - 1;
        const temContas = ultima >= primeira;
        escreverSubtotaisInformados(no.key, no.nivel + 1);
        // Quando o documento informou o total desta seção, ELE é o número da
        // seção; a nossa soma vai para uma linha de checagem logo abaixo (ver
        // `escreverSomaCalculada`). Isso torna o total, a AV%, o Δ% e os
        // indicadores imunes a subtotal de subseção contado duas vezes.
        const informadoIdx = temAncora
          ? escreverConferenciaExtraido(no.nivel, no.key, cabIdx, temContas ? subtotalNum : new Map())
          : null;
        if (temAncora && temContas && informadoIdx != null) {
          escreverSomaCalculada(no.nivel, "soma das contas listadas",
            (i) => `SUM(${colLetra(i)}${primeira}:${colLetra(i)}${ultima})`);
        }
        const grupoAncora = temAncora ? valoresPorAncora.get(no.key)! : null;
        const row = sheet.getRow(cabIdx);
        row.getCell(1).value = no.label;
        row.getCell(1).alignment = { indent: no.nivel };
        row.font = { bold: true };
        row.fill = fill;
        colunas.forEach((col, i) => {
          const cell = row.getCell(plano.valuePos[i]);
          cell.font = { bold: true };
          const vInformado = grupoAncora ? valorNumDoGrupo(grupoAncora, col.key) : null;
          if (vInformado != null && informadoIdx != null) {
            // O documento disse quanto é: o cabeçalho APONTA para a célula do
            // valor extraído (fórmula, não valor colado — a planilha continua
            // viva e a proveniência fica a um clique).
            cell.value = { formula: `${colLetra(i)}${informadoIdx}` } as ExcelJS.CellFormulaValue;
            cell.numFmt = VALOR_NUM_FMT;
            subtotalNum.set(col.key, vInformado);
          } else if (temContas) {
            // O documento não trouxe o total desta coluna: soma as contas-folha.
            cell.value = { formula: `SUM(${colLetra(i)}${primeira}:${colLetra(i)}${ultima})` } as ExcelJS.CellFormulaValue;
            cell.numFmt = VALOR_NUM_FMT;
            // …e ISSO PRECISA APARECER. Sem total informado não existe checagem:
            // se o documento imprime subtotal de agrupamento e a extração anotou
            // a seção de TOPO em `secao` (em vez da subseção), a soma conta o
            // subtotal E os componentes, e ninguém tem contra o que comparar.
            // Aconteceu no teste v28: a VT Logística saiu com Ativo Circulante
            // 7.254 onde o documento diz 3.961 — "Contas a Receber" (3.293)
            // somada junto com "Fretes a receber" (3.562) e "(-) PECLD" (−269),
            // que são os componentes dela. Marcar não conserta o número; impede
            // que ele passe por conferido.
            cell.font = { bold: true, italic: true };
            cell.note = comoNota(
              `Sem total informado no documento para esta coluna: o número é a NOSSA soma das contas `
              + `listadas (${no.label}), não um valor que o documento tenha impresso. `
              + `Se o original traz subtotais de agrupamento (ex.: "Contas a Receber" acima das duplicatas), `
              + `confira dupla contagem antes de usar — a soma pode incluir o subtotal E os componentes dele.`,
            );
          }
        });
        noRow.set(no.key, cabIdx);
        noValor.set(no.key, new Map(subtotalNum));
        linhasValor.add(cabIdx);
        return { idx: cabIdx, subtotalNum };
      }

      // nó pai: cabeçalho reservado, emite filhos (pula os vazios), soma os
      // cabeçalhos deles.
      const cabIdx = rowIndex++;
      const filhosIdx: number[] = [];
      for (const filho of no.filhos ?? []) {
        const r = emitirNo(filho);
        if (!r) continue;
        filhosIdx.push(r.idx);
        colunas.forEach((col) => {
          const v = r.subtotalNum.get(col.key);
          if (v != null) subtotalNum.set(col.key, (subtotalNum.get(col.key) ?? 0) + v);
        });
      }
      // Grupo sem nenhum filho com dado e sem total informado: não existe neste
      // documento. Devolve a linha reservada ao pool e não emite nada.
      const temAncoraPai = valoresPorAncora.has(no.key);
      if (filhosIdx.length === 0 && !temAncoraPai) {
        if (cabIdx === rowIndex - 1) rowIndex--; // nada foi escrito depois: reaproveita
        return null;
      }
      // Mesma regra do nó folha: o total que o documento informou manda, e a
      // soma dos filhos vira linha de checagem.
      const informadoPaiIdx = temAncoraPai
        ? escreverConferenciaExtraido(no.nivel, no.key, cabIdx, subtotalNum)
        : null;
      if (temAncoraPai && filhosIdx.length && informadoPaiIdx != null) {
        escreverSomaCalculada(no.nivel, "soma das seções acima",
          (i) => filhosIdx.map((r) => `${colLetra(i)}${r}`).join("+"));
      }
      const grupoAncoraPai = temAncoraPai ? valoresPorAncora.get(no.key)! : null;
      const row = sheet.getRow(cabIdx);
      row.getCell(1).value = no.label;
      row.getCell(1).alignment = { indent: no.nivel };
      row.font = { bold: true };
      row.fill = fill;
      const dupla = no.papel === "grupo";
      colunas.forEach((col, i) => {
        const cell = row.getCell(plano.valuePos[i]);
        cell.font = { bold: true };
        const vInformado = grupoAncoraPai ? valorNumDoGrupo(grupoAncoraPai, col.key) : null;
        if (vInformado != null && informadoPaiIdx != null) {
          cell.value = { formula: `${colLetra(i)}${informadoPaiIdx}` } as ExcelJS.CellFormulaValue;
          cell.numFmt = VALOR_NUM_FMT;
          subtotalNum.set(col.key, vInformado);
        } else if (filhosIdx.length) {
          cell.value = { formula: filhosIdx.map((r) => `${colLetra(i)}${r}`).join("+") } as ExcelJS.CellFormulaValue;
          cell.numFmt = VALOR_NUM_FMT;
        }
        if (dupla) cell.border = DOUBLE_TOP_BORDER;
      });
      noRow.set(no.key, cabIdx);
      noValor.set(no.key, new Map(subtotalNum));
      linhasValor.add(cabIdx);
      return { idx: cabIdx, subtotalNum };
    };

    for (const raiz of BALANCO_OUTLINE.filter((n) => n.nivel === 0)) emitirNo(raiz.key);
    baseTotalRow = noRow.get("ATIVO") ?? null;
  } else {
    // Layout sequencial (DRE / Fluxo de Caixa): seção → contas → subtotal
    // (âncora). Subtotal é FÓRMULA: DRE é cascata cumulativa (cada subtotal =
    // soma de TODAS as contas da demonstração até ali — deduções/custos/
    // despesas entram negativos, então a soma corrida dá o resultado); Fluxo
    // é soma da própria seção, com variação/saldo final derivados.
    const secoes = secoesDe(estrutura);
    const ancoras = ancorasDe(estrutura);
    const idxAncora = new Map<string, number>();
    const subtotalAncora = new Map<string, Map<string, number>>();
    let dreAncoraAnteriorIdx: number | null = null; // DRE: célula do subtotal anterior (cascata)
    const dreAcumulado = new Map<string, number>(); // DRE: subtotal numérico corrido

    for (const secao of secoes) {
      const contas = [...(contasPorSecao.get(secao.key)?.values() ?? [])];
      const temSubtotalInformado = (subtotaisInformados.get(secao.key)?.size ?? 0) > 0;
      // Seção que o documento não tem: não é emitida. O template canônico ordena
      // o que existe, não impõe blocos vazios.
      if (contas.length === 0 && !temSubtotalInformado) continue;

      // O cabeçalho da seção CARREGA O SUBTOTAL DA SEÇÃO, não só o rótulo.
      // Antes era linha só de texto — 8 linhas 100% vazias entre DRE e Fluxo de
      // Caixa ("Custos", "Despesas Operacionais", "Atividades Operacionais"…).
      // E o número é o que uma DRE real imprime: o total de custos e o total de
      // despesas operacionais são leitura de primeira ordem, distinta da cascata
      // acumulada que a âncora abaixo mostra.
      const cabIdx = rowIndex++;
      const primeira = rowIndex;
      const somaSecao = new Map<string, number>();
      for (const conta of contas) {
        escrever(conta.label, 1, conta);
        colunas.forEach((col) => {
          const v = valorNumDoGrupo(conta, col.key);
          if (v != null) somaSecao.set(col.key, (somaSecao.get(col.key) ?? 0) + v);
        });
      }
      const ultima = rowIndex - 1;
      escreverSubtotaisInformados(secao.key, 1);

      const hdr = sheet.getRow(cabIdx);
      hdr.getCell(1).value = secao.label;
      hdr.getCell(1).alignment = { indent: 0 };
      hdr.font = { bold: true };
      hdr.fill = SECAO_FILL;
      if (ultima >= primeira) {
        hdr.getCell(1).note = comoNota(
          "Total desta seção — soma das contas listadas abaixo. Não confundir com a linha de "
          + "resultado que vem depois: na DRE ela é cumulativa (traz o resultado acumulado até "
          + "ali), esta é só do bloco.",
        );
        colunas.forEach((col, i) => {
          if (somaSecao.get(col.key) == null) return;
          const cell = hdr.getCell(plano.valuePos[i]);
          cell.value = { formula: `SUM(${colLetra(i)}${primeira}:${colLetra(i)}${ultima})` } as ExcelJS.CellFormulaValue;
          cell.numFmt = VALOR_NUM_FMT;
          cell.font = { bold: true };
        });
        linhasValor.add(cabIdx);
      }
      const ancoraSecao = ancoras.find((a) => "aposSecao" in a && (a as { aposSecao: string }).aposSecao === secao.key);
      if (ancoraSecao) {
        const idx = rowIndex++;
        const subtotalNum = new Map<string, number>();
        const row = sheet.getRow(idx);
        row.getCell(1).value = ancoraSecao.label;
        row.getCell(1).font = { bold: true };
        colunas.forEach((col, i) => {
          const cell = row.getCell(plano.valuePos[i]);
          cell.font = { bold: true };
          cell.border = THIN_TOP_BORDER;
          let formula: string | null = null;
          const somaSecaoFormula = ultima >= primeira ? `SUM(${colLetra(i)}${primeira}:${colLetra(i)}${ultima})` : null;
          if (estrutura === "dre") {
            // CASCATA: subtotal = subtotal anterior + soma das contas DESTA
            // seção (deduções/custos/despesas entram negativos). Referencia a
            // célula da âncora anterior — nunca re-soma linhas de subtotal já
            // escritas (evita dupla contagem).
            const prev = dreAncoraAnteriorIdx != null ? `${colLetra(i)}${dreAncoraAnteriorIdx}` : null;
            formula = prev && somaSecaoFormula ? `${prev}+${somaSecaoFormula}` : (prev ?? somaSecaoFormula);
            const acc = (dreAcumulado.get(col.key) ?? 0) + (somaSecao.get(col.key) ?? 0);
            dreAcumulado.set(col.key, acc);
            subtotalNum.set(col.key, acc);
          } else {
            // Fluxo: soma da própria seção
            formula = somaSecaoFormula;
            subtotalNum.set(col.key, somaSecao.get(col.key) ?? 0);
          }
          if (formula) {
            cell.value = { formula } as ExcelJS.CellFormulaValue;
            cell.numFmt = VALOR_NUM_FMT;
          }
        });
        idxAncora.set(ancoraSecao.key, idx);
        subtotalAncora.set(ancoraSecao.key, subtotalNum);
        linhasValor.add(idx);
        if (estrutura === "dre") dreAncoraAnteriorIdx = idx;
        if (valoresPorAncora.has(ancoraSecao.key)) escreverConferenciaExtraido(0, ancoraSecao.key, idx, subtotalNum);

        // Linha analítica de MARGEM (% da Receita Líquida) — estilo FP&A
        // (referência DelendSummary): Margem Bruta / Operacional / Líquida.
        // Fórmula por coluna (IFERROR evita divisão por zero); não projeta
        // nada, só divide dois valores já extraídos. EBITDA fica de fora aqui
        // porque a DRE não traz Depreciação/Amortização como linha isolada
        // (viria das notas/Fluxo) — não inventamos.
        const rlIdx = idxAncora.get("receita_liquida");
        if (estrutura === "dre" && rlIdx && ancoraSecao.key in MARGEM_LABEL) {
          const mIdx = rowIndex++;
          const mrow = sheet.getRow(mIdx);
          mrow.getCell(1).value = MARGEM_LABEL[ancoraSecao.key];
          mrow.getCell(1).alignment = { indent: 1 };
          mrow.getCell(1).font = MARGEM_FONT;
          colunas.forEach((col, i) => {
            const cell = mrow.getCell(plano.valuePos[i]);
            cell.value = { formula: `IFERROR(${colLetra(i)}${idx}/${colLetra(i)}${rlIdx},"")` } as ExcelJS.CellFormulaValue;
            cell.numFmt = "0.0%";
            cell.font = MARGEM_FONT;
          });
        }
      }
    }
    if (estrutura === "dre") baseTotalRow = idxAncora.get("receita_liquida") ?? null;

    // Âncoras "livres" (não presas a uma seção): Fluxo de Caixa —
    // variação líquida = soma dos 3 caixas líquidos; saldo final = saldo
    // inicial + variação; saldo inicial = só o que o documento trouxer.
    for (const ancora of ancoras) {
      if ("aposSecao" in ancora) continue;
      const idx = rowIndex++;
      const row = sheet.getRow(idx);
      row.getCell(1).value = ancora.label;
      row.getCell(1).font = { bold: true };
      const subtotalNum = new Map<string, number>();
      colunas.forEach((col, i) => {
        const cell = row.getCell(plano.valuePos[i]);
        cell.font = { bold: true };
        cell.border = THIN_TOP_BORDER;
        let formula: string | null = null;
        const cel = (k: string) => (idxAncora.has(k) ? `${colLetra(i)}${idxAncora.get(k)}` : null);
        if (ancora.key === "variacao_liquida_caixa") {
          const partes = ["caixa_operacional", "caixa_investimento", "caixa_financiamento"].map(cel).filter(Boolean);
          if (partes.length) formula = partes.join("+");
        } else if (ancora.key === "saldo_final_caixa") {
          const ini = cel("saldo_inicial_caixa");
          const varc = cel("variacao_liquida_caixa");
          if (ini && varc) formula = `${ini}+${varc}`;
        }
        if (formula) {
          cell.value = { formula } as ExcelJS.CellFormulaValue;
          cell.numFmt = VALOR_NUM_FMT;
        } else {
          // saldo inicial (ou sem fórmula possível): usa o valor extraído
          const grupo = valoresPorAncora.get(ancora.key);
          const v = grupo ? valorNumDoGrupo(grupo, col.key) : null;
          if (v != null) {
            cell.value = v;
            cell.numFmt = VALOR_NUM_FMT;
          }
        }
      });
      idxAncora.set(ancora.key, idx);
      subtotalAncora.set(ancora.key, subtotalNum);
      linhasValor.add(idx);
    }
  }

  // ----- Contas Não Classificadas: nada desaparece silenciosamente. -----
  // O título carrega o TOTAL do bloco por coluna. Deixa de ser linha vazia e
  // passa a responder a pergunta que o analista faz primeiro: "quanto de valor
  // está fora das seções?" — se for material, a planilha ainda não está pronta
  // para virar modelo.
  if (naoClassificados.size > 0) {
    rowIndex++; // linha em branco
    const tituloIdx = rowIndex++;
    const primeiraNC = rowIndex;
    for (const conta of naoClassificados.values()) escrever(conta.label, 1, conta);
    const ultimaNC = rowIndex - 1;
    const tituloRow = sheet.getRow(tituloIdx);
    tituloRow.getCell(1).value = "Contas Não Classificadas (revisar manualmente)";
    tituloRow.font = { bold: true, italic: true };
    tituloRow.fill = NAO_CLASSIFICADO_FILL;
    tituloRow.getCell(1).note = comoNota(
      "Contas que o classificador não colocou numa seção com segurança. O valor ao lado é o total "
      + "do bloco: quanto maior, menos a planilha está pronta para virar modelo. Nada foi "
      + "descartado — cada conta aparece abaixo com o rótulo original.",
    );
    if (ultimaNC >= primeiraNC) {
      colunas.forEach((col, i) => {
        let tem = false;
        for (const conta of naoClassificados.values()) {
          if (valorNumDoGrupo(conta, col.key) != null) { tem = true; break; }
        }
        if (!tem) return;
        const cell = tituloRow.getCell(plano.valuePos[i]);
        cell.value = { formula: `SUM(${colLetra(i)}${primeiraNC}:${colLetra(i)}${ultimaNC})` } as ExcelJS.CellFormulaValue;
        cell.numFmt = VALOR_NUM_FMT;
        cell.font = { bold: true, italic: true };
      });
    }
  }

  // ----- Camada analítica (f0/08): AV% (common-size) e Δ% (tendência). -----
  // Fórmulas transparentes sobre as MESMAS células de valor já escritas — não
  // inventam nada; a linha subjacente segue pendente/âmbar até o aceite.
  preencherAnaliseVerticalHorizontal(sheet, plano, [...linhasValor], baseTotalRow);

  // ----- Indicadores de liquidez/estrutura (Balanço) — f0/08. -----
  if (estrutura === "balanco") {
    escreverIndicadoresBalanco(sheet, plano, colunas, noRow, noValor, () => rowIndex++);
  }
}

// AV% e Δ% para todas as linhas monetárias. AV% = valor ÷ base (Ativo Total ou
// Receita Líquida); Δ% = (período atual − anterior) ÷ anterior. Só escreve onde
// a(s) célula(s) de valor referida(s) têm conteúdo — nunca força um % órfão.
function preencherAnaliseVerticalHorizontal(
  sheet: ExcelJS.Worksheet,
  plano: PlanoColunas,
  linhas: number[],
  baseTotalRow: number | null,
) {
  const temValor = (r: number, pos: number) => {
    const v = sheet.getRow(r).getCell(pos).value;
    return v != null && v !== "";
  };
  for (const r of linhas) {
    // Análise vertical
    if (baseTotalRow != null) {
      plano.valuePos.forEach((vp, i) => {
        const av = plano.avPos[i];
        if (av == null || !temValor(r, vp)) return;
        const L = sheet.getColumn(vp).letter;
        const cell = sheet.getRow(r).getCell(av);
        cell.value = { formula: `IFERROR(${L}${r}/${L}${baseTotalRow},"")` } as ExcelJS.CellFormulaValue;
        cell.numFmt = AV_FMT;
        cell.font = ANALISE_FONT;
      });
    }
    // Análise horizontal
    for (const d of plano.deltas) {
      const posAt = plano.valuePos[d.atual];
      const posAn = plano.valuePos[d.anterior];
      if (!temValor(r, posAt) || !temValor(r, posAn)) continue;
      const Lat = sheet.getColumn(posAt).letter;
      const Lan = sheet.getColumn(posAn).letter;
      const cell = sheet.getRow(r).getCell(d.pos);
      cell.value = { formula: `IFERROR((${Lat}${r}-${Lan}${r})/${Lan}${r},"")` } as ExcelJS.CellFormulaValue;
      cell.numFmt = DELTA_FMT;
      cell.font = ANALISE_FONT;
    }
  }
}

// Bloco de indicadores de liquidez e estrutura de capital ao pé do Balanço
// (Matarazzo/Assaf Neto; CFI credit analysis — f0/08). Cada indicador é uma
// FÓRMULA por coluna referenciando as linhas de subtotal do próprio Balanço
// (via `noRow`), com IFERROR: se o insumo não existe, a célula fica vazia —
// nunca estimamos. Índices que exigem detalhamento de conta ainda não isolado
// (liquidez seca/imediata, cobertura de juros, dívida líquida, ciclo de caixa,
// ROA/ROE, Altman Z'') ficam de fora por ora — ver f0/08.
function escreverIndicadoresBalanco(
  sheet: ExcelJS.Worksheet,
  plano: PlanoColunas,
  colunas: Coluna[],
  noRow: Map<string, number>,
  noValor: Map<string, Map<string, number>>,
  proximaLinha: () => number,
) {
  const AC = noRow.get("ativo_circulante");
  const ATV = noRow.get("ATIVO");
  const PC = noRow.get("passivo_circulante");
  const PNC = noRow.get("passivo_nao_circulante");
  const PL = noRow.get("patrimonio_liquido");
  const RLP = noRow.get("realizavel_lp");
  const IMOB = noRow.get("imobilizado");
  const INV = noRow.get("investimentos");
  const INT = noRow.get("intangivel");
  // Sem as âncoras estruturais mínimas não há o que calcular.
  if (AC == null || ATV == null || PC == null || PNC == null || PL == null) return;

  const cel = (i: number, row: number | undefined) => (row == null ? null : `${sheet.getColumn(plano.valuePos[i]).letter}${row}`);
  // Valor de um nó na coluna i (null quando o nó não existe ou a coluna está
  // vazia) — é com isso que decidimos se o índice resolve de verdade.
  const val = (i: number, chave: string): number | null => {
    const v = noValor.get(chave)?.get(colunas[i].key);
    return typeof v === "number" ? v : null;
  };
  const soma = (i: number, chaves: string[]): number | null => {
    let t: number | null = null;
    for (const c of chaves) {
      const v = val(i, c);
      if (v != null) t = (t ?? 0) + v;
    }
    return t;
  };
  // Um índice só é emitido se, em ALGUMA coluna, numerador e denominador
  // existem e o denominador não é zero.
  const razaoResolve = (i: number, num: string[], den: string[]): boolean => {
    const n = soma(i, num);
    const d = soma(i, den);
    return n != null && d != null && d !== 0;
  };

  const indicadores: Array<{
    label: string; fmt: string;
    formula: (i: number) => string | null;
    resolve: (i: number) => boolean;
  }> = [
    {
      label: "Liquidez Corrente (AC ÷ PC)", fmt: RATIO_FMT,
      formula: (i) => `${cel(i, AC)}/${cel(i, PC)}`,
      resolve: (i) => razaoResolve(i, ["ativo_circulante"], ["passivo_circulante"]),
    },
    {
      label: "Liquidez Geral ((AC + Realizável LP) ÷ (PC + PNC))",
      fmt: RATIO_FMT,
      formula: (i) => {
        const ac = cel(i, AC)!;
        const rlp = cel(i, RLP);
        const num = rlp ? `(${ac}+${rlp})` : ac;
        return `${num}/(${cel(i, PC)}+${cel(i, PNC)})`;
      },
      resolve: (i) => razaoResolve(i, ["ativo_circulante", "realizavel_lp"], ["passivo_circulante", "passivo_nao_circulante"]),
    },
    {
      label: "Endividamento Geral ((PC + PNC) ÷ Ativo Total)", fmt: PCT_FMT,
      formula: (i) => `(${cel(i, PC)}+${cel(i, PNC)})/${cel(i, ATV)}`,
      resolve: (i) => razaoResolve(i, ["passivo_circulante", "passivo_nao_circulante"], ["ATIVO"]),
    },
    {
      label: "Composição do Endividamento (PC ÷ (PC + PNC))", fmt: PCT_FMT,
      formula: (i) => `${cel(i, PC)}/(${cel(i, PC)}+${cel(i, PNC)})`,
      resolve: (i) => razaoResolve(i, ["passivo_circulante"], ["passivo_circulante", "passivo_nao_circulante"]),
    },
    {
      label: "Participação de Capital de Terceiros ((PC + PNC) ÷ PL)", fmt: PCT_FMT,
      formula: (i) => `(${cel(i, PC)}+${cel(i, PNC)})/${cel(i, PL)}`,
      resolve: (i) => razaoResolve(i, ["passivo_circulante", "passivo_nao_circulante"], ["patrimonio_liquido"]),
    },
    {
      label: "Imobilização do PL ((Imob. + Invest. + Intang.) ÷ PL)",
      fmt: PCT_FMT,
      formula: (i) => {
        const partes = [cel(i, IMOB), cel(i, INV), cel(i, INT)].filter(Boolean);
        if (partes.length === 0) return null;
        return `(${partes.join("+")})/${cel(i, PL)}`;
      },
      resolve: (i) => razaoResolve(i, ["imobilizado", "investimentos", "intangivel"], ["patrimonio_liquido"]),
    },
  ];

  // Só indicadores que TÊM fórmula em pelo menos uma coluna. Um índice cujos
  // insumos não existem na extração (ex.: Imobilização do PL num combinado que
  // não detalha Imobilizado) sairia como linha 100% vazia — e linha vazia numa
  // planilha de entrega parece defeito, não parece "insumo indisponível".
  const comValor = indicadores.filter((ind) =>
    colunas.some((_, i) => ind.formula(i) != null && ind.resolve(i)));
  if (comValor.length === 0) return;

  // Sem linha de título própria (era a última linha 100% vazia do Balanço): o
  // bloco é aberto pela borda dupla e pela nota no primeiro índice. Os rótulos
  // já explicitam a fórmula de cada um, então nada se perde.
  const NOTA_BLOCO = comoNota(
    "Início do bloco de INDICADORES DE LIQUIDEZ E ESTRUTURA: índices calculados por fórmula sobre os "
    + "subtotais extraídos deste Balanço (Matarazzo/Assaf Neto; f0/08). Não são linhas do documento. "
    + "Célula vazia = insumo não disponível na extração (nunca estimado). Índices que exigem "
    + "detalhamento de conta ainda não isolado (liquidez seca/imediata, cobertura de juros, dívida "
    + "líquida/EBITDA, ciclo de caixa, ROA/ROE, Altman Z'') ficam de fora desta versão — ver f0/08. "
    + "Valores derivados de linhas ainda PENDENTES seguem pendentes até o aceite humano.",
  );

  proximaLinha(); // linha em branco separando do balanço
  comValor.forEach((ind, ordem) => {
    const r = proximaLinha();
    const row = sheet.getRow(r);
    row.getCell(1).value = ind.label;
    row.getCell(1).font = INDICADOR_LABEL_FONT;
    if (ordem === 0) {
      row.getCell(1).font = { ...INDICADOR_LABEL_FONT, bold: true };
      row.getCell(1).fill = INDICADOR_TITULO_FILL;
      row.getCell(1).note = NOTA_BLOCO;
      row.getCell(1).border = DOUBLE_TOP_BORDER;
    }
    colunas.forEach((_, i) => {
      const f = ind.formula(i);
      if (!f) return;
      const cell = row.getCell(plano.valuePos[i]);
      cell.value = { formula: `IFERROR(${f},"")` } as ExcelJS.CellFormulaValue;
      cell.numFmt = ind.fmt;
      if (ordem === 0) cell.border = DOUBLE_TOP_BORDER;
    });
  });
}

// ----- Aba simples (Faturamento/Dívida/Fluxo Projetado/Outros) -------------
// Já são, por natureza, uma série/tabela — não uma demonstração de blocos.
interface LinhaSimples {
  entidade: string;
  periodo: string;
  secao: string;
  chave: string;
  valorTexto: string | null;
  valorNum: number | null;
  unidade: string | null;
  pagina: number | null;
  confianca: number | null;
  statusAceite: string;
  aceitoPor: string | null;
  aceitoEm: string | null;
  arquivoOrigem: string;
}

// Nota de proveniência da linha simples (mesmo espírito de `notaProveniencia`,
// para os campos que a v20 pediu pra tirar da grade — seção/página/unidade/
// confiança/aceito por/aceito em/arquivo continuam rastreáveis, só saem de
// coluna própria pra virar um comentário no rótulo).
function notaProvenienciaSimples(linha: LinhaSimples): string {
  const partes = [
    linha.secao !== "(sem seção)" ? `Seção: ${linha.secao}` : null,
    `Arquivo: ${linha.arquivoOrigem}`,
    linha.pagina != null ? `Página: ${linha.pagina}` : null,
    linha.unidade ? `Unidade: ${linha.unidade}` : null,
    linha.confianca != null ? `Confiança da extração: ${Math.round(linha.confianca * 100)}%` : null,
    `Status: ${formatarStatus(linha.statusAceite)}`,
    linha.statusAceite === "aceito" && linha.aceitoPor ? `Aceito por: ${linha.aceitoPor}` : null,
    linha.aceitoEm ? `Aceito em: ${new Date(linha.aceitoEm).toLocaleString("pt-BR")}` : null,
  ].filter(Boolean);
  return partes.join("\n");
}

// Colunas reduzidas ao essencial (pedido do dono, sessão 7 cont.¹⁴): a
// listagem simples (Faturamento, Dívida, Intragrupo, Societário, ...) tinha 13
// colunas — a maioria delas técnica/de rastreabilidade (seção, página,
// unidade, confiança, aceito por/em, arquivo, versão da taxonomia), poluindo
// a leitura de quem só quer ver conta × valor. Essas informações não somem —
// viram um comentário (`cell.note`) no rótulo, visível ao passar o mouse.
function construirAbaSimples(workbook: ExcelJS.Workbook, nomeAba: string, linhas: LinhaSimples[]) {
  linhas.sort((a, b) => compararColunas(a, b) || a.secao.localeCompare(b.secao));

  const sheet = workbook.addWorksheet(nomeAba, { views: [{ state: "frozen", ySplit: 1 }] });
  sheet.columns = [
    { header: "Entidade", key: "entidade", width: 26 },
    { header: "Período", key: "periodo", width: 14 },
    { header: "Rótulo", key: "chave", width: 38 },
    { header: "Valor", key: "valorNum", width: 16 },
    { header: "Status", key: "statusAceite", width: 12 },
  ];
  sheet.getRow(1).font = { bold: true };
  sheet.getRow(1).fill = HEADER_FILL;

  for (const linha of linhas) {
    const row = sheet.addRow({
      entidade: linha.entidade,
      periodo: linha.periodo,
      chave: linha.chave,
      valorNum: linha.valorNum ?? linha.valorTexto ?? null,
      statusAceite: formatarStatus(linha.statusAceite),
    });
    row.getCell("chave").note = comoNota(notaProvenienciaSimples(linha));
    if (typeof row.getCell("valorNum").value === "number") row.getCell("valorNum").numFmt = VALOR_NUM_FMT;
    if (/total/i.test(linha.chave)) row.font = { bold: true };
    if (linha.statusAceite !== "aceito") {
      row.eachCell((cell) => {
        cell.fill = PENDENTE_FILL;
      });
      row.font = { ...row.font, italic: true };
    }
  }
}

// ---------------------------------------------------------------------------
// DMPL e DVA (db/migrations/0024). As duas são demonstrações inteiras, mas
// nenhuma passa pelo `construirAbaClassificada`: aquele caminho existe para
// template de seções + subtotal em FÓRMULA (Balanço/DRE/Fluxo), e nem a DMPL
// nem a DVA têm um template nosso. Aqui vale o princípio travado na sessão 10:
// o que sai é o que o documento trouxe, na ordem em que ele trouxe — nenhuma
// linha imposta, nenhum subtotal calculado por nós (anti-ancoragem, f0/07).
// Por construção, então, toda linha destas abas nasce de uma linha extraída:
// não existe aqui a classe de defeito que o invariante 8 persegue nas abas com
// template (linha em branco emitida às cegas).
// ---------------------------------------------------------------------------
interface RegistroDemonstracao {
  campo: CampoExtraido;
  ctx: ContextoVersao;
  entidade: string;
  periodo: string;
}

const MOVIMENTO_SEM_ROTULO = "(movimento não informado)";
const SECAO_SEM_ROTULO = "(sem seção informada)";

// Chave estável para alinhar o MESMO rótulo escrito com grafias diferentes
// (plural, acento, caixa) sem forçar nome canônico — o rótulo exibido é sempre
// o primeiro que apareceu, como no resto do export.
function ordemPorPrimeiraAparicao() {
  const ordem = new Map<string, string>(); // chave normalizada → rótulo exibido
  return {
    registrar(rotulo: string) {
      const k = normalizar(rotulo);
      if (!ordem.has(k)) ordem.set(k, rotulo);
      return k;
    },
    lista(): Array<[string, string]> {
      return [...ordem.entries()];
    },
  };
}

// A DMPL é uma MATRIZ: as linhas são MOVIMENTOS do exercício ("SALDOS EM 31 DE
// DEZEMBRO DE 2024", "Prejuízo líquido do exercício") e as colunas são
// COMPONENTES do PL ("Capital social", "Reserva legal", "Prejuízos acumulados",
// "Total"). Achatá-la numa listagem perderia justamente a leitura que a
// demonstração existe para dar (como cada componente do PL se moveu), então a
// aba reconstrói a matriz: um bloco por entidade×período, cabeçalho com os
// componentes, uma linha por movimento. `secao` = movimento e `chave` =
// componente é o contrato que o prompt de extração pede (n8n/lib/extract.mjs).
function construirAbaDMPL(workbook: ExcelJS.Workbook, nomeAba: string, registros: RegistroDemonstracao[]) {
  const blocos = new Map<string, { entidade: string; periodo: string; registros: RegistroDemonstracao[] }>();
  for (const reg of registros) {
    const key = `${reg.entidade}${CHAVE_SEP}${reg.periodo}`;
    if (!blocos.has(key)) blocos.set(key, { entidade: reg.entidade, periodo: reg.periodo, registros: [] });
    blocos.get(key)!.registros.push(reg);
  }

  const sheet = workbook.addWorksheet(nomeAba, { views: [{ state: "frozen", ySplit: 1 }] });
  let larguraMax = 0;

  for (const bloco of [...blocos.values()].sort(compararColunas)) {
    const componentes = ordemPorPrimeiraAparicao();
    const movimentos = ordemPorPrimeiraAparicao();
    const celulas = new Map<string, RegistroDemonstracao[]>();
    for (const reg of bloco.registros) {
      const comp = componentes.registrar(reg.campo.chave);
      const mov = movimentos.registrar(reg.campo.secao ?? MOVIMENTO_SEM_ROTULO);
      const k = `${mov}${CHAVE_SEP}${comp}`;
      if (!celulas.has(k)) celulas.set(k, []);
      celulas.get(k)!.push(reg);
    }

    const colunasComp = componentes.lista();
    larguraMax = Math.max(larguraMax, colunasComp.length + 1);

    // O título do bloco vive na MESMA linha do cabeçalho dos componentes (em
    // vez de uma linha só de título): uma linha com rótulo e nenhum valor é
    // exatamente o que o invariante 8 chama de linha vazia.
    const header = sheet.addRow([
      `Movimento — ${bloco.entidade} (${bloco.periodo})`,
      ...colunasComp.map(([, label]) => label),
    ]);
    header.font = { bold: true };
    header.eachCell((cell) => {
      cell.fill = HEADER_FILL;
      cell.alignment = { wrapText: true, vertical: "bottom" };
    });

    for (const [movKey, movLabel] of movimentos.lista()) {
      const row = sheet.addRow([movLabel]);
      let algumPendente = false;
      colunasComp.forEach(([compKey], i) => {
        const candidatos = celulas.get(`${movKey}${CHAVE_SEP}${compKey}`);
        if (!candidatos || candidatos.length === 0) return;
        const melhor = melhorCampo(candidatos.map((r) => r.campo));
        const { ctx } = candidatos.find((r) => r.campo === melhor)!;
        const cell = row.getCell(i + 2);
        cell.value = melhor.valor_num ?? melhor.valor_texto ?? null;
        if (typeof cell.value === "number") cell.numFmt = VALOR_NUM_FMT;
        cell.note = comoNota(notaProveniencia(melhor, ctx));
        if (melhor.status_aceite !== "aceito") {
          cell.fill = PENDENTE_FILL;
          algumPendente = true;
        }
      });
      // Saldo de abertura/fechamento é a moldura da demonstração — negrito e
      // filete, como sai no PDF publicado.
      if (/\bsaldos?\b/i.test(movLabel)) {
        row.font = { bold: true };
        row.eachCell((cell) => {
          cell.border = THIN_TOP_BORDER;
        });
      }
      if (algumPendente) row.font = { ...row.font, italic: true };
    }

    sheet.addRow([]); // respiro entre blocos (sem rótulo — o invariante 8 pula)
  }

  sheet.getColumn(1).width = 46;
  for (let c = 2; c <= Math.max(larguraMax, 2); c++) sheet.getColumn(c).width = 20;
}

// A DVA (CPC 09) é uma cascata de seções — geração do valor adicionado e sua
// distribuição. Não escrevemos um template dela: a demonstração é padronizada
// pelo CPC, mas não temos nenhum arquivo real para validar um, e um template
// errado ordenaria o dado errado em silêncio. A aba apresenta o que o documento
// trouxe, na ordem dele, com a seção declarada numa coluna própria — e as
// colunas de valor são entidade×período, como nas demais demonstrações.
function construirAbaDocumental(workbook: ExcelJS.Workbook, nomeAba: string, registros: RegistroDemonstracao[]) {
  const colunas = new Map<string, Coluna>();
  for (const reg of registros) {
    const key = `${reg.entidade}${CHAVE_SEP}${reg.periodo}`;
    if (!colunas.has(key)) colunas.set(key, { key, entidade: reg.entidade, periodo: reg.periodo });
  }
  const ordemColunas = [...colunas.values()].sort(compararColunas);
  const posColuna = new Map(ordemColunas.map((c, i) => [c.key, i + 3]));

  const secoes = ordemPorPrimeiraAparicao();
  const linhas = new Map<string, { secaoLabel: string; rotulo: string; porColuna: Map<string, RegistroDemonstracao[]> }>();
  for (const reg of registros) {
    const secaoKey = secoes.registrar(reg.campo.secao ?? SECAO_SEM_ROTULO);
    const k = `${secaoKey}${CHAVE_SEP}${normalizar(reg.campo.chave)}`;
    if (!linhas.has(k)) {
      linhas.set(k, {
        secaoLabel: reg.campo.secao ?? SECAO_SEM_ROTULO,
        rotulo: reg.campo.chave,
        porColuna: new Map(),
      });
    }
    const alvo = linhas.get(k)!;
    const colKey = `${reg.entidade}${CHAVE_SEP}${reg.periodo}`;
    if (!alvo.porColuna.has(colKey)) alvo.porColuna.set(colKey, []);
    alvo.porColuna.get(colKey)!.push(reg);
  }

  const sheet = workbook.addWorksheet(nomeAba, { views: [{ state: "frozen", ySplit: 1, xSplit: 2 }] });
  sheet.columns = [
    { header: "Rótulo", width: 46 },
    { header: "Seção declarada no documento", width: 32 },
    ...ordemColunas.map((c) => ({ header: `${c.entidade} — ${c.periodo}`, width: 20 })),
  ];
  sheet.getRow(1).font = { bold: true };
  sheet.getRow(1).eachCell((cell) => {
    cell.fill = HEADER_FILL;
    cell.alignment = { wrapText: true, vertical: "bottom" };
  });

  for (const linha of linhas.values()) {
    const row = sheet.addRow([linha.rotulo, linha.secaoLabel]);
    let algumPendente = false;
    for (const [colKey, regs] of linha.porColuna) {
      const pos = posColuna.get(colKey);
      if (!pos) continue;
      const melhor = melhorCampo(regs.map((r) => r.campo));
      const reg = regs.find((r) => r.campo === melhor)!;
      const cell = row.getCell(pos);
      cell.value = melhor.valor_num ?? melhor.valor_texto ?? null;
      if (typeof cell.value === "number") cell.numFmt = VALOR_NUM_FMT;
      cell.note = comoNota(notaProveniencia(melhor, reg.ctx));
      if (melhor.status_aceite !== "aceito") {
        cell.fill = PENDENTE_FILL;
        algumPendente = true;
      }
    }
    row.getCell(2).font = { size: 9, color: { argb: "FF64748B" } };
    if (/total|valor adicionado/i.test(linha.rotulo)) row.font = { bold: true };
    if (algumPendente) row.font = { ...row.font, italic: true };
  }
}

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
const ABA_MODELAGEM = "Modelagem";

// Horizonte da projeção. Três exercícios é o padrão de um plano de
// reestruturação — e o número de colunas não muda nada da lógica: a timeline
// deriva de uma célula só.
const ANOS_PROJETADOS = 3;

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
      if (dado.meses === 12) {
        cell.value = dado.retorno;
        completosDe.set(serie, [...(completosDe.get(serie) ?? []), ano]);
      }
      cell.note = comoNota(`${dado.meses} ${dado.meses === 1 ? "mês" : "meses"} observado(s) em ${dado.ano}.`
        + (dado.meses === 12 ? "" : " Ano INCOMPLETO — fora das médias de 3/5/10 anos."));
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
}

/**
 * Aba Macro SEM índice coletado — dizendo exatamente o que falta e o efeito.
 *
 * O efeito importa porque não é neutro: sem Focus, as premissas de inflação e
 * juro do modelo ficam em branco, e quem digitar por cima delas está usando
 * memória, não dado publicado. Uma aba ausente não conta isso; esta conta.
 */
function construirAbaMacroSemDado(workbook: ExcelJS.Workbook, erro?: string): void {
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

export function buildExportWorkbook({
  caso,
  documentos,
  campos: camposDeTodasAsVersoes,
  macro,
  macroErro,
  causasDeFalha,
  agora = new Date(),
}: {
  caso: { nome: string; produto: string };
  documentos: DocumentoParaExport[];
  campos: CampoExtraido[];
  // Índices macro (db/migrations/0025). Opcional: sem eles o export sai como
  // sempre saiu, só sem a aba Macro e com as premissas macro zeradas.
  macro?: MacroParaExport;
  // Mensagem da consulta/RPC que FALHOU ao buscar macro (permissão, RLS, rede) —
  // distinta de "consultou e não achou nada". Confundir as duas é o próprio
  // defeito que motivou este parâmetro (0028): a base tinha dado, a consulta do
  // portal falhava por autorização, e a aba saía dizendo "sem dado coletado"
  // como se a coleta nunca tivesse rodado. Ver `route.ts` (chamador).
  macroErro?: string;
  // Causas DISTINTAS das falhas de extração abertas no caso (texto das pendências
  // `extracao_falhou`). Listar o arquivo que falhou sem dizer POR QUE deixa o
  // dono com meia informação: no v30 os 14 nomes estavam no Resumo e a causa
  // ficava só na fila de revisão, em outra tela.
  causasDeFalha?: string[];
  agora?: Date;
}): ExcelJS.Workbook {
  // Mapa documento_versao_id → contexto (entidade/período/tipo/arquivo) —
  // permite juntar campo_extraido (que só sabe a versão) com o resto. Só as
  // versões VIGENTES entram: reextração substitui, não acumula (ver
  // `versoesVigentes`).
  const vigentes = versoesVigentes(documentos, camposDeTodasAsVersoes);
  const contextoPorVersao = new Map<string, ContextoVersao>();
  for (const doc of documentos) {
    for (const versao of doc.documento_versao ?? []) {
      if (!vigentes.has(versao.id)) continue;
      contextoPorVersao.set(versao.id, {
        entidade: doc.entidade?.razao_social ?? "(sem entidade)",
        periodo: doc.periodo ? formatarPeriodo(doc.periodo.tipo, doc.periodo.referencia) : "(sem período)",
        tipoTaxonomia: doc.tipo_taxonomia,
        nomeArquivo: versao.nome_original ?? "(sem nome)",
      });
    }
  }
  // Daqui para baixo, `campos` é só o da versão vigente — inclusive nas contagens
  // do Resumo, que senão anunciariam linhas que a planilha não mostra.
  const camposVigentes = camposDeTodasAsVersoes.filter((c) => contextoPorVersao.has(c.documento_versao_id));
  const camposDeVersaoSubstituida = camposDeTodasAsVersoes.length - camposVigentes.length;

  // ESCALA: converte tudo para uma escala só, ANTES de qualquer soma. Ver o
  // comentário de `normalizarEscala`. Daqui para baixo, todo `valor_num` está na
  // mesma escala — que é o que torna `SUM`, AV%, indicadores e a Modelagem
  // corretos sem que nenhum deles precise saber que escala existe.
  const escalaAlvo = escolherEscalaAlvo(camposVigentes);
  const { campos, escala } = normalizarEscala(camposVigentes, escalaAlvo);

  // Consolidação de coluna (teste v27): o apelido que o documento combinado usa
  // na coluna ("Componentes") e a razão social do documento individual
  // ("VERTENTES COMPONENTES AUTOMOTIVOS LTDA.") são a MESMA empresa e precisam
  // virar UMA coluna — senão qualquer soma do grupo conta cada empresa 2x.
  const apelidosDeColuna = campos.map((c) => c.entidade_coluna).filter((x): x is string => !!x);
  const razoesSociais = [...contextoPorVersao.values()].map((c) => c.entidade);
  const nomeCanonico = consolidarNomesDeEntidade(razoesSociais, apelidosDeColuna);

  // Quais versões são documento COMPOSTO — várias demonstrações no mesmo arquivo
  // sem aba estruturada própria. Duas portas, e a diferença entre elas é o que
  // impede este roteamento de virar dupla contagem:
  //
  //  (a) o TIPO declara o conjunto (`TIPOS_DOCUMENTO_COMPOSTO`): basta isso. Seja
  //      o que o arquivo contiver, suas linhas são de demonstração e cada uma tem
  //      aba canônica — inclusive quando a DF auditada traz só o balanço.
  //  (b) o documento AINDA NÃO TEM TIPO (nome de arquivo que a taxonomia não
  //      reconhece, aguardando a fila de revisão): aí exige-se evidência DECLARADA
  //      de mais de uma demonstração — linhas com `secao_canonica` de duas
  //      famílias diferentes. É o sinal que separa "Demonstrações Contábeis
  //      2025.pdf" (BP + DRE + DFC juntos) de um aging de recebíveis, que é
  //      homogêneo e cujo lugar continua sendo a listagem documental. Sem essa
  //      exigência, o aging entraria no Balanço somando o detalhe DEBAIXO do total
  //      que o BP já informa.
  const versoesCompostas = new Set<string>();
  {
    const familiasDeclaradasPorVersao = new Map<string, Set<FamiliaDemonstracao>>();
    for (const campo of campos) {
      const ctx = contextoPorVersao.get(campo.documento_versao_id);
      if (!ctx) continue;
      const abaDoc = (ctx.tipoTaxonomia && ABA_POR_TIPO[ctx.tipoTaxonomia]) || "Outros";
      // Documento que já tem aba própria (estruturada, DMPL/DVA ou de série) não
      // é tocado: seu roteamento é o que sempre foi.
      if (abaDoc !== "Outros") continue;
      if (ctx.tipoTaxonomia) {
        if (TIPOS_DOCUMENTO_COMPOSTO.has(ctx.tipoTaxonomia)) versoesCompostas.add(campo.documento_versao_id);
        continue;
      }
      const familia = familiaDeclarada(campo.secao_canonica);
      if (!familia || ehSecaoDeNotaExplicativa(campo.secao)) continue;
      if (!familiasDeclaradasPorVersao.has(campo.documento_versao_id)) {
        familiasDeclaradasPorVersao.set(campo.documento_versao_id, new Set());
      }
      familiasDeclaradasPorVersao.get(campo.documento_versao_id)!.add(familia);
    }
    for (const [versaoId, familias] of familiasDeclaradasPorVersao) {
      if (familias.size >= 2) versoesCompostas.add(versaoId);
    }
  }

  // Num documento composto NÃO existe uma estrutura "própria" para desambiguar a
  // linha — e é justamente ela que o roteamento por linha usava para resolver a
  // ambiguidade legítima entre demonstrações. "Prejuízo líquido do exercício" é
  // âncora da DRE (linha de fechamento) E do Fluxo indireto (ponto de partida);
  // "Caixa e equivalentes" é conta do Balanço E saldo da DFC. Sem estrutura, o
  // fallback determinístico tenta Fluxo primeiro e a DRE inteira ia para a aba
  // errada — a primeira versão desta fatia fez exatamente isso, e a cascata saiu
  // com Lucro Bruto 10.820 onde o documento diz 5.280.
  //
  // Quem desempata é o próprio documento: um PDF auditado IMPRIME os blocos
  // ("CUSTO DOS PRODUTOS VENDIDOS", "FLUXO DE CAIXA DAS ATIVIDADES OPERACIONAIS")
  // e a extração traz esse cabeçalho em `secao`. A seção decide por VOTO das suas
  // linhas, e a linha ambígua vai com o bloco em que o documento a imprimiu — a
  // mesma doutrina que o resto do export já segue ("a seção declarada manda").
  const familiaPorSecaoComposta = new Map<string, FamiliaDemonstracao>();
  if (versoesCompostas.size > 0) {
    const chaveSecao = (campo: CampoExtraido) =>
      `${campo.documento_versao_id}${CHAVE_SEP}${normalizar(campo.secao ?? "")}`;
    // Voto DECLARADO (a IA disse a que demonstração a linha pertence) vale mais
    // que voto INFERIDO por palavra-chave — a seção só é decidida pelo segundo
    // quando nenhuma linha dela foi declarada.
    const votos = new Map<string, { declarados: Map<string, number>; inferidos: Map<string, number> }>();
    for (const campo of campos) {
      if (!versoesCompostas.has(campo.documento_versao_id)) continue;
      if (!campo.secao || ehSecaoDeNotaExplicativa(campo.secao)) continue;
      const k = chaveSecao(campo);
      if (!votos.has(k)) votos.set(k, { declarados: new Map(), inferidos: new Map() });
      const urna = votos.get(k)!;
      const declarada = familiaDeclarada(campo.secao_canonica);
      const inferida = declarada ? null : classificarDemonstracao(campo.secao, campo.chave, null, null);
      const alvo = declarada ? urna.declarados : urna.inferidos;
      const familia = declarada ?? inferida;
      if (familia) alvo.set(familia, (alvo.get(familia) ?? 0) + 1);
    }
    // Empate: mantém a ordem de preferência do fallback determinístico
    // (`classificarDemonstracao`) — Fluxo e DRE têm sinais específicos, Balanço
    // casa "caixa" de forma gulosa. DMPL/DVA vêm antes porque só chegam aqui
    // declaradas, e declaração não é palpite.
    const DESEMPATE: FamiliaDemonstracao[] = ["dmpl", "dva", "fluxo_caixa", "dre", "balanco"];
    for (const [k, urna] of votos) {
      const urnaValida = urna.declarados.size > 0 ? urna.declarados : urna.inferidos;
      let vencedora: FamiliaDemonstracao | null = null;
      let maisVotos = 0;
      for (const familia of DESEMPATE) {
        const n = urnaValida.get(familia) ?? 0;
        if (n > maisVotos) { maisVotos = n; vencedora = familia; }
      }
      if (vencedora) familiaPorSecaoComposta.set(k, vencedora);
    }
  }

  // Agrupa por aba → coluna (entidade×período) → campos daquela coluna.
  const colunasPorAba = new Map<string, Map<string, Coluna>>();
  const camposPorAba = new Map<string, Array<{ campo: CampoExtraido; colKey: string }>>();
  const linhasSimplesPorAba = new Map<string, LinhaSimples[]>();
  // DMPL/DVA (0024): nem grade classificada (não têm template) nem listagem
  // simples (perderiam a leitura da demonstração) — ver construirAbaDMPL /
  // construirAbaDocumental.
  const registrosPorAba = new Map<string, RegistroDemonstracao[]>();

  for (const campo of campos) {
    const ctx = contextoPorVersao.get(campo.documento_versao_id);
    if (!ctx) continue;
    const abaDoc = (ctx.tipoTaxonomia && ABA_POR_TIPO[ctx.tipoTaxonomia]) || "Outros";
    const estruturaDoc = ESTRUTURA_POR_ABA.get(abaDoc);

    // Roteamento por LINHA (não por tipo do documento): um PDF de
    // "Demonstrações Contábeis" traz Balanço + DRE + Fluxo de Caixa no mesmo
    // arquivo, mas é UM documento de um tipo só. Se a linha pertence a uma
    // demonstração diferente da do documento, ela vai para a aba canônica
    // daquela demonstração — em vez de empilhar tudo na aba do tipo do
    // documento (o que fazia a DRE cair em "Não Classificadas" e as linhas de
    // Fluxo de Caixa vazarem para dentro do Ativo). Só reroteia entre abas
    // ESTRUTURADAS (Balanço/DRE/Fluxo); abas de série (Faturamento/Dívida/…)
    // não são tocadas. Continua N1: a linha segue pendente/âmbar até o aceite.
    let aba = abaDoc;
    if (estruturaDoc) {
      const familiaLinha = classificarDemonstracao(campo.secao, campo.chave, campo.secao_canonica, estruturaDoc);
      if (familiaLinha && familiaLinha !== estruturaDoc) {
        aba = ABA_PADRAO_POR_ESTRUTURA[familiaLinha];
      }
    } else if (versoesCompostas.has(campo.documento_versao_id) && !ehSecaoDeNotaExplicativa(campo.secao)) {
      // Documento composto (DF auditada / conjunto ainda sem tipo): não há
      // estrutura "própria" para preferir, então a ordem de evidência é o que a IA
      // declarou PARA ESTA LINHA → o bloco em que o documento a imprimiu (voto da
      // seção) → palavra-chave. Sem nenhum sinal, a linha fica onde estava
      // (listagem documental): conservador, nada desaparece.
      const familiaLinha =
        familiaDeclarada(campo.secao_canonica)
        ?? (campo.secao
          ? familiaPorSecaoComposta.get(`${campo.documento_versao_id}${CHAVE_SEP}${normalizar(campo.secao)}`)
          : undefined)
        ?? classificarDemonstracao(campo.secao, campo.chave, campo.secao_canonica, null);
      if (familiaLinha) aba = ABA_PADRAO_POR_ESTRUTURA[familiaLinha];
    }
    // Documento multi-entidade (db/migrations/0014): quando a linha traz
    // `entidade_coluna` (ex.: "Certsys Tecn" num balanço combinado com várias
    // colunas de empresa), a coluna do export é a ENTIDADE DA LINHA, não a
    // entidade principal do documento — é o que separa "Certsys Tecn"/"Part"/
    // "Com"/"Total" em colunas próprias no lugar de forçar tudo numa coluna só.
    // …e o apelido dessa coluna é promovido à razão social quando o caso conhece
    // uma só que case (`consolidarNomesDeEntidade`) — sem isso a mesma empresa
    // fica em duas colunas, uma por grafia (teste v27).
    const entidadeBruta = campo.entidade_coluna || ctx.entidade;
    const entidadeColuna = nomeCanonico.get(entidadeBruta) ?? entidadeBruta;
    // Documento comparativo (db/migrations/0017): quando a linha traz
    // `periodo_coluna` (ex.: "2023"/"2024" num balanço 2023×2024), o período da
    // COLUNA do export é o da linha, não o período único do documento — é o que
    // separa os anos em colunas próprias em vez de colapsá-los num só (perda de
    // dado). Ortogonal a entidade_coluna: a coluna final é entidade × período.
    // `periodo_coluna` vem CRU da extração ("2024", "31/12/2024") enquanto
    // `ctx.periodo` já passou por `formatarPeriodo` — sem normalizar os dois do
    // mesmo jeito, o MESMO período aparecia em duas colunas distintas ("2024" e
    // "2024" formatado de outra fonte) e os rótulos saíam inconsistentes na
    // mesma aba. Formatar aqui colapsa a coluna e alinha a escrita.
    // `periodoConsolidado` fecha o mesmo buraco do lado do período: o combinado
    // declara "2025" e o balanço individual "31/12/2025" — o mesmo exercício em
    // duas colunas (teste v27).
    const periodoColuna = periodoConsolidado(
      campo.periodo_coluna ? formatarPeriodo(null, campo.periodo_coluna) : ctx.periodo,
    );
    // Separador improvável na chave: com espaço simples, entidade "A B" +
    // período "C" colidia com entidade "A" + período "B C" (colunas de
    // entidade×período diferentes fundidas numa só).
    const colKey = `${entidadeColuna}${CHAVE_SEP}${periodoColuna}`;
    const estrutura = ESTRUTURA_POR_ABA.get(aba);

    if (aba === ABA_DMPL || aba === ABA_DVA) {
      if (!registrosPorAba.has(aba)) registrosPorAba.set(aba, []);
      registrosPorAba.get(aba)!.push({ campo, ctx, entidade: entidadeColuna, periodo: periodoColuna });
    } else if (estrutura) {
      if (!colunasPorAba.has(aba)) colunasPorAba.set(aba, new Map());
      colunasPorAba.get(aba)!.set(colKey, { key: colKey, entidade: entidadeColuna, periodo: periodoColuna });
      if (!camposPorAba.has(aba)) camposPorAba.set(aba, []);
      camposPorAba.get(aba)!.push({ campo, colKey });
    } else {
      if (!linhasSimplesPorAba.has(aba)) linhasSimplesPorAba.set(aba, []);
      linhasSimplesPorAba.get(aba)!.push({
        entidade: entidadeColuna,
        periodo: periodoColuna,
        secao: campo.secao ?? "(sem seção)",
        chave: campo.chave,
        valorTexto: campo.valor_texto,
        valorNum: campo.valor_num,
        unidade: campo.unidade,
        pagina: campo.origem_pagina,
        confianca: campo.confianca,
        statusAceite: campo.status_aceite,
        aceitoPor: campo.aceito_por,
        aceitoEm: campo.aceito_em,
        arquivoOrigem: ctx.nomeArquivo,
      });
    }
  }

  const workbook = new ExcelJS.Workbook();
  workbook.creator = "Oria — Tratamento de Dados Financeiros";
  workbook.created = agora;

  // ----- Aba Resumo (metadados do snapshot) -----
  // Pedido do dono (sessão 7 cont.¹⁵): tipo/versão de taxonomia é detalhe
  // interno de classificação, não algo que o time de análise precisa ver na
  // planilha — some daqui (e de toda nota/aviso) mas continua orientando o
  // roteamento por aba internamente (`tipo_taxonomia`/`ABA_POR_TIPO`).
  const resumo = workbook.addWorksheet("Resumo");
  const totalLinhas = campos.length;
  const totalAceitas = campos.filter((c) => c.status_aceite === "aceito").length;
  resumo.columns = [{ width: 32 }, { width: 60 }];
  const linhasResumo: Array<[string, string | number]> = [
    ["Caso", caso.nome],
    ["Produto", caso.produto],
    ["Gerado em", agora.toLocaleString("pt-BR")],
    ["Linhas totais extraídas", totalLinhas],
    ["Linhas aceitas (fato)", totalAceitas],
    ["Linhas pendentes (sugestão, revisar)", totalLinhas - totalAceitas],
    // ESCALA: a informação mais importante do Resumo depois do nome do caso.
    // Toda aba de valores está NESTA escala — o export converte na entrada
    // (`normalizarEscala`) justamente para que exista uma resposta única aqui.
    // Antes desta linha o book não declarava escala em lugar nenhum, e valores em
    // escalas diferentes eram somados crus: erro de ~496x sem nenhuma marca.
    ["Escala dos valores", `${ROTULO_ESCALA[escala.alvo] ?? escala.alvo} — vale para TODAS as abas de valores`],
  ];
  // Só aparece quando houve conversão de verdade: linha que diz "0 convertidos"
  // é ruído, e ruído no Resumo treina o leitor a não ler o Resumo.
  if (escala.converteu > 0) {
    linhasResumo.push([
      "↳ valores convertidos de escala",
      `${escala.converteu} linha(s) vinham em ${escala.escalasEncontradas
        .filter((e) => e !== escala.alvo)
        .map((e) => ROTULO_ESCALA[e] ?? e)
        .join(", ")} e foram convertidas. A nota de cada célula diz a escala de origem.`,
    ]);
  }
  // E o que NÃO deu para converter, que é o que o leitor precisa conferir à mão.
  if (escala.semDeclaracao > 0) {
    linhasResumo.push([
      "↳ linhas sem escala declarada",
      `${escala.semDeclaracao} — o documento não disse a escala, então o valor entrou COMO ESTÁ, sem conversão. ` +
        `Assumir uma escala aqui seria inventar um fator de 1.000x onde não se sabe.`,
    ]);
  }
  // Reextração é substituição, e substituição não pode ser silenciosa: quem abre
  // o book tem de saber que existe extração anterior deste mesmo arquivo fora da
  // planilha (ela continua no banco, com proveniência, para auditoria).
  if (camposDeVersaoSubstituida > 0) {
    linhasResumo.push([
      "Linhas de versão substituída (fora deste export)",
      `${camposDeVersaoSubstituida} — o arquivo foi reextraído; só a extração mais recente com dado entra na planilha`,
    ]);
  }
  // Documento que chegou e não produziu NENHUMA linha. No v28 foram dois (a DRE da
  // Metalúrgica e o Balanço da SPE, os dois por rate limit da OpenAI) e o arquivo
  // não dizia uma palavra sobre isso: a DRE simplesmente não tinha aba, e a SPE
  // simplesmente não tinha coluna no Balanço. Contar quantas linhas foram
  // extraídas sem contar quantos documentos ficaram de fora é meia informação.
  const arquivosSemLinha = documentos
    .flatMap((d) => (d.documento_versao ?? [])
      .filter((v) => vigentes.has(v.id) && !campos.some((c) => c.documento_versao_id === v.id))
      .map((v) => v.nome_original ?? "(sem nome)"));
  if (arquivosSemLinha.length > 0) {
    linhasResumo.push([
      "Documentos SEM linha extraída",
      `${arquivosSemLinha.length} de ${documentos.length}: ${arquivosSemLinha.join("; ")} `
      + "— chegaram e foram classificados, mas a extração não gravou nada (a falha abre pendência na "
      + "fila de revisão). Onde faltou entidade/demonstração nas abas, é por isso.",
    ]);
    // …e a CAUSA junto. Quando as 14 falhas têm a MESMA causa (foi o caso do
    // v30), aparece uma linha só: repetir o mesmo motivo por arquivo esconderia
    // justamente o que a repetição significa — o problema é da conta/API, não
    // dos documentos.
    for (const causa of causasDeFalha ?? []) {
      linhasResumo.push(["↳ causa registrada", causa]);
    }
  }
  resumo.addRows([
    ...linhasResumo,
    [""],
    [
      "Aviso",
      "Este export NÃO é modelagem financeira e não projeta nada — é dado curado e rastreável " +
        "para o time de análise trabalhar em cima (f0/07_output_spec.md). Linhas marcadas " +
        "PENDENTE ainda não passaram por aceite humano — não são fato, são sugestão a revisar " +
        "antes de entrar no modelo. Quando um mesmo arquivo traz várias demonstrações juntas " +
        "(ex.: Balanço + DRE + Fluxo de Caixa no mesmo PDF), cada linha é encaminhada para a aba " +
        "da demonstração a que pertence — não fica tudo na aba do tipo do documento. " +
        "Balanço/Balancete/DRE/Fluxo de Caixa/Combinado classificam cada conta extraída por SEÇÃO " +
        "(Ativo Circulante, Despesas Operacionais, etc.), mantendo o rótulo original de cada " +
        "empresa — nenhum subtotal é calculado por nós, só aparece se o próprio documento já " +
        "trouxer aquela linha. Contas que não foi possível classificar com segurança aparecem em " +
        "\"Contas Não Classificadas\", ao final de cada aba — revisar manualmente.",
    ],
  ]);
  resumo.getRow(1).font = { bold: true };
  // A linha do Aviso muda de posição quando existe versão substituída — achar por
  // rótulo em vez de fixar "B9", que era uma referência a estourar no primeiro
  // item novo do Resumo.
  for (let r = 1; r <= resumo.rowCount; r++) {
    if (String(resumo.getRow(r).getCell(1).value ?? "") === "Aviso") {
      resumo.getRow(r).getCell(2).alignment = { wrapText: true };
    }
  }

  for (const aba of ORDEM_ABAS) {
    const estrutura = ESTRUTURA_POR_ABA.get(aba);
    if (aba === ABA_DMPL || aba === ABA_DVA) {
      const registros = registrosPorAba.get(aba);
      if (!registros || registros.length === 0) continue;
      if (aba === ABA_DMPL) construirAbaDMPL(workbook, aba, registros);
      else construirAbaDocumental(workbook, aba, registros);
    } else if (estrutura) {
      const colunas = [...(colunasPorAba.get(aba)?.values() ?? [])].sort(compararColunas);
      if (colunas.length === 0) {
        // As três demonstrações PRINCIPAIS existem SEMPRE, mesmo sem dado — com o
        // motivo escrito dentro da aba, e na posição certa da ordem canônica. No
        // teste v28 a extração da DRE falhou por rate limit (429) da OpenAI e a
        // aba simplesmente NÃO EXISTIU no arquivo: o dono abriu o book, não achou
        // a DRE e não tinha como saber se o problema era o documento, a extração
        // ou o export. Aba ausente é buraco silencioso; aba presente dizendo "o
        // documento veio e a extração falhou" é item de trabalho.
        if (ABAS_SEMPRE_PRESENTES.has(aba)) construirAbaSemDado(workbook, aba, documentos);
        continue;
      }
      construirAbaClassificada(
        workbook,
        aba,
        estrutura,
        colunas,
        camposPorAba.get(aba) ?? [],
        contextoPorVersao,
      );
    } else {
      const linhas = linhasSimplesPorAba.get(aba);
      if (!linhas || linhas.length === 0) continue;
      construirAbaSimples(workbook, aba, linhas);
    }
  }


  // ----- Aba Modelagem + ocultação das abas de dado cru ---------------------
  // Pedido do dono (v27): "depois de carregar e tratar, oculte as abas dos
  // dados crus e mantenha apenas o que for prático para a modelagem" — é a
  // mesma disciplina do modelo de referência, que deixa visíveis o Summary e os
  // drivers e esconde as abas de backup.
  //
  // OCULTAR, nunca remover: as abas continuam no arquivo e as fórmulas do
  // modelo seguem apontando para elas. É o que mantém a proveniência (e o
  // princípio de f0/07: o dado curado e rastreável não some da entrega).
  const entidadesConhecidas = new Map<string, number>();
  const anos = new Set<number>();
  for (const [aba, colunas] of colunasPorAba) {
    if (!ESTRUTURA_POR_ABA.has(aba)) continue;
    for (const c of colunas.values()) {
      if (tipoColunaNaoEntidade(c.entidade)) continue;
      entidadesConhecidas.set(c.entidade, (entidadesConhecidas.get(c.entidade) ?? 0) + 1);
      const ano = Number((c.periodo.match(/\b(19|20)\d{2}\b/) ?? [])[0]);
      if (ano) anos.add(ano);
    }
  }
  if (entidadesConhecidas.size > 0) {
    // Entidade sugerida = a que tem mais colunas de demonstração no caso (a
    // mais bem documentada). É só o VALOR INICIAL de uma célula de input.
    const ordenadas = [...entidadesConhecidas.entries()]
      .sort((a, b) => b[1] - a[1] || a[0].localeCompare(b[0]));
    const entidadeSugerida = ordenadas[0][0];
    // A lista suspensa da célula de entidade. Vírgula é o separador da lista
    // inline do Excel, então uma razão social que a contenha quebraria a
    // validação — essas ficam de fora da lista (o campo segue digitável).
    const entidadesDisponiveis = ordenadas.map(([e]) => e).filter((e) => !e.includes(","));
    const anosHistoricos = [...anos].sort((a, b) => a - b);
    // A aba Macro entra ANTES da Modelagem: o modelo referencia as linhas do
    // Focus por endereço, então elas precisam existir.
    const refsMacro = macro ? construirAbaMacro(workbook, macro, macroErro) : null;
    // Sem índice coletado a aba Macro também EXISTE, dizendo o que falta. No teste
    // v28 ela não existiu e o dono leu isso como "os índices não vieram com os
    // dados" — sem ter como distinguir "coleta não rodou" de "defeito no export".
    // A causa real ali: a `0025` não estava aplicada no projeto certo (foi aplicada
    // no banco errado e revertida), então não havia índice nenhum na base.
    // A aba de "sem dado" só cobre a falha TOTAL. Quando a consulta falha em
    // PARTE — o caso concreto: os índices vêm, mas a consulta de NOMES das
    // séries não —, a aba Macro é montada normalmente, exibe códigos crus no
    // lugar dos nomes, e o erro morria num `console.error` que ninguém lê. Um
    // arquivo degradado que não declara a degradação é pior que um que falha.
    if (!refsMacro) construirAbaMacroSemDado(workbook, macroErro);
    construirAbaModelagem(
      workbook, caso, entidadeSugerida, entidadesDisponiveis, anosHistoricos, ANOS_PROJETADOS,
      refsMacro,
    );

    // A Modelagem é a primeira aba: é por onde o arquivo deve abrir.
    const modelagem = workbook.getWorksheet(ABA_MODELAGEM);
    if (modelagem) {
      workbook.views = [{
        activeTab: modelagem.id - 1, firstSheet: 0, visibility: "visible",
        x: 0, y: 0, width: 10000, height: 20000,
      }];
    }
  } else {
    // NENHUMA entidade reconhecida nas abas de demonstração. Sem entidade não
    // dá para montar a Modelagem (o modelo inteiro pende de uma célula de
    // entidade) nem faz sentido montar a Macro — mas até aqui o arquivo saía
    // simplesmente SEM as duas abas, e uma aba que não existe não diz por quê.
    // No v28 foi assim que "não veio os dados macro" virou meia hora de
    // investigação: o dono não tinha como distinguir "o export não montou"
    // de "a coleta não rodou".
    const ws = workbook.addWorksheet(ABA_MODELAGEM);
    ws.columns = [{ width: 40 }, { width: 96 }];
    ws.addRow(["Modelagem e índices macro — não montados"]).font = { bold: true, size: 12 };
    ws.addRows([
      ["Por quê",
        "Nenhuma das linhas extraídas tem ENTIDADE reconhecida (razão social na coluna das abas de "
        + "demonstração). O modelo é recalculado a partir de uma célula de entidade — sem nenhuma "
        + "para escolher, ele não teria de onde ler número nenhum, e a aba Macro sozinha não "
        + "projetaria nada."],
      ["O que costuma ser",
        "Documentos que chegaram e não produziram linha (ver a aba Resumo: 'Documentos SEM linha "
        + "extraída' e a causa registrada), ou extração que gravou linhas sem identificar a empresa "
        + "— o diagnóstico da IA e o nome do arquivo são as duas fontes de entidade."],
      ["O que fazer",
        "Confira a aba Resumo e a fila de revisão do portal. Depois de aceitar/corrigir a entidade "
        + "de pelo menos um documento, exporte de novo: a Modelagem e a Macro voltam sozinhas."],
      ...(macroErro
        ? [["Nota sobre os índices macro",
            `A consulta dos índices também falhou: "${macroErro}". São problemas independentes — `
            + "este arquivo não montaria a Modelagem mesmo com o macro em ordem."] as [string, string]]
        : []),
    ]);
    for (let r = 2; r <= ws.rowCount; r++) {
      ws.getRow(r).alignment = { wrapText: true, vertical: "top" };
      ws.getRow(r).height = 56;
    }
  }

  return workbook;
}


// ExcelJS grava a caixa de toda nota (`cell.note`) com um tamanho FIXO no XML
// VML (`width:97.8pt;height:59.1pt`, ~130×80px) — hardcoded no próprio
// pacote (`lib/xlsx/xform/comment/vml-shape-xform.js`), sem parâmetro público
// pra mudar (conferido lendo o fonte, não só o `.d.ts`). É por isso que
// anotações com texto de várias linhas apareciam cortadas ao abrir (pedido do
// dono, sessão 7 cont.¹⁵). Sem editar `node_modules`, o único jeito é
// pós-processar o .xlsx já gerado: ele é um .zip, então abrimos com JSZip
// (já vem como dependência transitiva do próprio exceljs), achamos as partes
// `xl/drawings/vmlDrawing*.vml` e trocamos a string de tamanho fixo por uma
// caixa bem maior, igual para toda nota do workbook (o hardcode do exceljs
// já é idêntico em todas — troca segura por string).
const NOTA_BOX_ANTIGA = "width:97.8pt;height:59.1pt";
const NOTA_BOX_NOVA = "width:340pt;height:170pt";

export async function ampliarNotasNoBuffer(buffer: Buffer | ArrayBuffer): Promise<Buffer> {
  const zip = await JSZip.loadAsync(buffer);
  const vmlPaths = Object.keys(zip.files).filter((p) => /^xl\/drawings\/vmlDrawing\d+\.vml$/.test(p));
  for (const path of vmlPaths) {
    const xml = await zip.file(path)!.async("string");
    if (!xml.includes(NOTA_BOX_ANTIGA)) continue;
    zip.file(path, xml.split(NOTA_BOX_ANTIGA).join(NOTA_BOX_NOVA));
  }
  return zip.generateAsync({ type: "nodebuffer" });
}

// Reexportado para eventuais consumidores que só precisem agrupar por conta
// (ex.: uma futura tela de revisão por seção no portal).
export { agruparPorChaveNormalizada };
