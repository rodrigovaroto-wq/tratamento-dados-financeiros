// Índices macroeconômicos — coleta, validação cruzada e composição (F2).
//
// Por que isto existe: a aba de Modelagem projeta exercícios futuros a partir de
// premissas, e as premissas mais comuns de um plano de reestruturação são
// macro — inflação que corrige receita e contratos, juro que define o custo da
// dívida. Hoje o analista digita esses números de memória ou de um print; aqui
// eles passam a vir de fonte oficial, versionada e conferida.
//
// TRÊS DECISÕES DE DESENHO, todas com consequência:
//
// 1. HISTÓRICO **e** EXPECTATIVA. A média dos últimos 3/5/10 anos descreve o
//    passado e serve para calibrar; ela NÃO é previsão. Para projetar, o que o
//    mercado usa é o Focus/BCB (mediana das expectativas por ano-calendário).
//    Trazer só o histórico faria o modelo projetar o retrovisor.
//
// 2. COMPOSIÇÃO GEOMÉTRICA, nunca média aritmética. Taxa se compõe: a média de
//    10% e 4% não é 7,00% e sim 6,95% (√(1,10 × 1,04) − 1). Parece detalhe;
//    num horizonte de 10 anos a diferença vira erro material, e é o tipo de
//    erro que ninguém percebe olhando a planilha.
//
// 3. DUAS FONTES PARA O MESMO NÚMERO. O IPCA é publicado pelo IBGE (que o
//    produz) e espelhado pelo BCB/SGS. Divergência entre os dois significa
//    revisão de série ou coleta furada — exatamente a classe de problema que a
//    reconciliação do sistema já trata. Conferir custa uma requisição a mais e
//    é o que autoriza chamar o dado de "validado".

// Séries do SGS/BCB. `natureza` decide como o valor se agrega no tempo:
//   'taxa'  → variação percentual DO MÊS; o ano acumula por composição.
//   'nivel' → um preço/estoque na data (câmbio); o ano é o valor de fechamento
//             e a variação é entre fechamentos. Somar/compor nível é erro.
export const SERIES_MACRO = [
  { codigo: 'IPCA', sgs: 433, nome: 'IPCA (IBGE)', natureza: 'taxa', unidade: '% a.m.',
    descricao: 'Índice oficial de inflação ao consumidor — corrige contratos e define a meta do BCB.' },
  { codigo: 'IGPM', sgs: 189, nome: 'IGP-M (FGV)', natureza: 'taxa', unidade: '% a.m.',
    descricao: 'Índice geral de preços — usado em aluguéis e contratos de longo prazo.' },
  { codigo: 'INPC', sgs: 188, nome: 'INPC (IBGE)', natureza: 'taxa', unidade: '% a.m.',
    descricao: 'Inflação para faixa de renda mais baixa — referência de reajuste salarial.' },
  { codigo: 'SELIC', sgs: 4390, nome: 'Selic acumulada no mês', natureza: 'taxa', unidade: '% a.m.',
    descricao: 'Juro básico efetivamente acumulado no mês (não a meta anual).' },
  { codigo: 'CDI', sgs: 4391, nome: 'CDI acumulado no mês', natureza: 'taxa', unidade: '% a.m.',
    descricao: 'Referência de custo de dívida bancária e de rendimento de aplicação.' },
  { codigo: 'CAMBIO_USD', sgs: 1, nome: 'Câmbio R$/US$ (venda)', natureza: 'nivel', unidade: 'R$',
    descricao: 'Taxa de câmbio de fechamento — relevante quando há receita, custo ou dívida em dólar.' },
];

export function serieMacro(codigo) {
  return SERIES_MACRO.find((s) => s.codigo === codigo) ?? null;
}

// Indicadores do Focus (Expectativas de Mercado). O nome tem de bater com o
// campo `Indicador` da API — por isso ficam explícitos aqui e não derivados.
export const INDICADORES_FOCUS = [
  { codigo: 'IPCA', indicador: 'IPCA', unidade: '% a.a.' },
  { codigo: 'SELIC', indicador: 'Selic', unidade: '% a.a.' },
  { codigo: 'IGPM', indicador: 'IGP-M', unidade: '% a.a.' },
  { codigo: 'PIB', indicador: 'PIB Total', unidade: '% a.a.' },
  { codigo: 'CAMBIO_USD', indicador: 'Câmbio', unidade: 'R$/US$' },
];

const SGS_BASE = 'https://api.bcb.gov.br/dados/serie/bcdata.sgs';
const FOCUS_BASE = 'https://olinda.bcb.gov.br/olinda/servico/Expectativas/versao/v1/odata/ExpectativasMercadoAnuais';
const SIDRA_BASE = 'https://apisidra.ibge.gov.br/values';

// O SGS recusa janelas muito longas em algumas séries; pedir "os últimos N" é
// mais robusto que um intervalo de datas e não depende do relógio do servidor.
export function urlSgs(codigoSgs, { ultimos = 132 } = {}) {
  return `${SGS_BASE}.${codigoSgs}/dados/ultimos/${ultimos}?formato=json`;
}

// dd/MM/yyyy (formato do SGS) → ISO. Data inválida devolve null em vez de uma
// data errada: uma observação sem data não pode entrar na série.
function dataSgsParaIso(bruto) {
  const m = String(bruto ?? '').match(/^(\d{2})\/(\d{2})\/(\d{4})$/);
  return m ? `${m[3]}-${m[2]}-${m[1]}` : null;
}

// Número em notação BR ou EN → Number. O SGS devolve "0.67" (ponto decimal),
// mas séries antigas e outras fontes usam vírgula; aceitar os dois evita uma
// classe inteira de bug silencioso (o valor vira NaN e some da série).
export function numeroMacro(bruto) {
  if (typeof bruto === 'number') return Number.isFinite(bruto) ? bruto : null;
  const t = String(bruto ?? '').trim();
  if (!t) return null;
  const n = Number(t.includes(',') ? t.replace(/\./g, '').replace(',', '.') : t);
  return Number.isFinite(n) ? n : null;
}

export function parseSgs(json, codigo) {
  if (!Array.isArray(json)) return [];
  return json
    .map((o) => ({
      serie: codigo,
      fonte: 'BCB/SGS',
      data_ref: dataSgsParaIso(o?.data),
      valor: numeroMacro(o?.valor),
    }))
    .filter((o) => o.data_ref && o.valor !== null);
}

// Focus: só o boletim MAIS RECENTE interessa (a API devolve o histórico inteiro
// de coletas). `$orderby` decrescente + `$top` resolve sem baixar tudo.
export function urlFocus(indicador, { top = 40 } = {}) {
  const filtro = encodeURIComponent(`Indicador eq '${indicador}'`);
  return `${FOCUS_BASE}?$top=${top}&$format=json&$orderby=Data%20desc&$filter=${filtro}`;
}

export function parseFocus(json, codigo) {
  const linhas = Array.isArray(json?.value) ? json.value : [];
  if (linhas.length === 0) return [];
  // Uma coleta traz vários anos de referência; ficamos com a data de coleta mais
  // recente presente na resposta e com um registro por ano.
  const maisRecente = linhas.reduce((a, l) => (l?.Data > a ? l.Data : a), '');
  const porAno = new Map();
  for (const l of linhas) {
    if (l?.Data !== maisRecente) continue;
    const ano = Number(l?.DataReferencia);
    const mediana = numeroMacro(l?.Mediana);
    if (!Number.isInteger(ano) || mediana === null) continue;
    if (!porAno.has(ano)) {
      porAno.set(ano, {
        serie: codigo,
        fonte: 'BCB/Focus',
        ano_ref: ano,
        mediana,
        media: numeroMacro(l?.Media),
        respondentes: Number.isFinite(l?.numeroRespondentes) ? l.numeroRespondentes : null,
        coletado_em: maisRecente,
      });
    }
  }
  return [...porAno.values()].sort((a, b) => a.ano_ref - b.ano_ref);
}

// IBGE/SIDRA — tabela 1737, variável 63 = IPCA variação mensal. É a fonte
// PRIMÁRIA do índice (o BCB espelha); serve de contraprova.
export function urlSidraIpca({ ultimos = 24 } = {}) {
  return `${SIDRA_BASE}/t/1737/n1/all/v/63/p/last%20${ultimos}`;
}

export function parseSidraIpca(json) {
  if (!Array.isArray(json)) return [];
  // A primeira linha do SIDRA é o cabeçalho descritivo, não dado.
  return json
    .slice(1)
    .map((o) => {
      const periodo = String(o?.D3C ?? ''); // "202604"
      const m = periodo.match(/^(\d{4})(\d{2})$/);
      return {
        serie: 'IPCA',
        fonte: 'IBGE/SIDRA',
        data_ref: m ? `${m[1]}-${m[2]}-01` : null,
        valor: numeroMacro(o?.V),
      };
    })
    .filter((o) => o.data_ref && o.valor !== null);
}

// ---------------------------------------------------------------------------
// Validação cruzada. Duas fontes para o MESMO mês do MESMO índice têm de bater;
// divergência é revisão de série ou coleta furada. Tolerância em pontos
// percentuais porque os valores JÁ são percentuais (0,01 p.p. = arredondamento
// de publicação, não discordância).
// ---------------------------------------------------------------------------
export function divergenciasEntreFontes(serieA, serieB, tolerancia = 0.011) {
  const porData = new Map(serieB.map((o) => [o.data_ref, o]));
  const fora = [];
  for (const a of serieA) {
    const b = porData.get(a.data_ref);
    if (!b) continue; // mês só numa fonte não é divergência: é cobertura diferente
    const delta = Math.abs(a.valor - b.valor);
    if (delta > tolerancia) {
      fora.push({
        serie: a.serie, data_ref: a.data_ref, delta,
        fontes: { [a.fonte]: a.valor, [b.fonte]: b.valor },
      });
    }
  }
  return fora;
}

// ---------------------------------------------------------------------------
// Composição. Estas duas funções existem para o TESTE e para o SQL; na planilha
// o mesmo cálculo é refeito em FÓRMULA (regra do dono: o que dá para ser
// fórmula, é fórmula). Ter os dois lados é o que permite provar que a fórmula
// da planilha calcula a coisa certa.
// ---------------------------------------------------------------------------

// Acumula taxas percentuais por composição: [0.5, 0.3] → 0.8015%.
export function acumularTaxas(taxasPercentuais) {
  const fator = taxasPercentuais.reduce((acc, t) => acc * (1 + t / 100), 1);
  return (fator - 1) * 100;
}

// Retorno acumulado de cada ANO-CALENDÁRIO a partir das observações mensais.
// Ano incompleto é devolvido com `meses < 12` — quem consome decide se usa;
// tratá-lo como ano cheio distorceria qualquer média.
export function retornoAnual(observacoes) {
  const porAno = new Map();
  for (const o of observacoes) {
    const ano = Number(String(o.data_ref).slice(0, 4));
    if (!Number.isInteger(ano)) continue;
    if (!porAno.has(ano)) porAno.set(ano, []);
    porAno.get(ano).push(o.valor);
  }
  return [...porAno.entries()]
    .map(([ano, taxas]) => ({ ano, meses: taxas.length, retorno: acumularTaxas(taxas) }))
    .sort((a, b) => a.ano - b.ano);
}

// Média GEOMÉTRICA de retornos anuais — a única correta para taxa. Só considera
// anos completos: incluir um ano de 3 meses como se fosse cheio puxa a média
// para baixo sem que ninguém veja.
export function mediaAnualGeometrica(retornosAnuais, janela) {
  const cheios = retornosAnuais.filter((r) => r.meses === 12);
  if (cheios.length < janela) return null; // sem histórico suficiente: não inventa
  const ultimos = cheios.slice(-janela);
  const fator = ultimos.reduce((acc, r) => acc * (1 + r.retorno / 100), 1);
  return (Math.pow(fator, 1 / janela) - 1) * 100;
}

export const JANELAS_MEDIA = [3, 5, 10];
