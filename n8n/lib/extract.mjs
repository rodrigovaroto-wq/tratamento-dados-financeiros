// Extração + DIAGNÓSTICO do documento (E2) via OpenAI — modo SOMBRA (N0/N1).
//
// Antes, esta chamada só extraía linhas financeiras (chave+valor). Ela já
// rodava SEMPRE (para todo documento, independente da confiança da
// classificação por nome) — então virou o lugar natural para resolver 3
// lacunas encontradas em produção:
//   1. Entidade nunca era extraída quando o nome do arquivo já dava confiança
//      alta no tipo/período (o fallback de classificação por conteúdo nunca
//      rodava para esses casos, e SÓ ele buscava entidade).
//   2. Não havia diagnóstico de conteúdo nenhum nesses casos: nada conferia
//      se o tipo/período do nome batem com o que está escrito dentro, nem
//      sinalizava qualidade/legibilidade real do arquivo.
//   3. As linhas extraídas vinham em lista achatada, sem agrupamento — difícil
//      de ler como uma "planilha" organizada (Ativo Circulante, Passivo
//      Circulante, PL, etc.).
//
// Uma ÚNICA chamada agora faz as duas coisas (não aumenta o número de
// chamadas à OpenAI): extrai linhas com `secao` (agrupador livre, espelha a
// estrutura do documento original) E devolve um bloco `diagnostico` (entidade,
// confere tipo/período, legibilidade, resumo, justificativa).
//
// Doutrina (docs/01): tudo aqui continua SUGESTÃO. Nada decide sozinho —
// diagnóstico gera pendência tipada para revisão humana (ver
// db/migrations/0010_diagnostico_e1e2.sql → fn_registrar_diagnostico);
// linhas continuam em N0 (sombra), sem entrar em base sem aceite humano.

import { codigosConhecidos } from './openai.mjs';

const OPENAI_URL = 'https://api.openai.com/v1/chat/completions';
const DEFAULT_MODEL = 'gpt-4o';

const PERIODO_TIPO_ENUM = ['anual', 'trimestre', 'multi', 'data-base', 'outro', 'desconhecido'];

// Seção CANÔNICA sugerida pela IA por linha (N1 — sugestão, não fato). É o
// mesmo conjunto de chaves internas do classificador do export
// (portal/src/lib/statement-templates.ts) — mantê-los IDÊNTICOS: se um lado
// mudar, o outro precisa acompanhar (não há import cruzado entre .mjs e o
// portal TS). Serve para o classificador determinístico do export ter um
// sinal interpretativo forte QUANDO ele mesmo não consegue classificar por
// regra — reduz o bloco "Contas Não Classificadas" sem virar fato (a linha
// continua pendente/âmbar até o aceite humano). "NAO_CLASSIFICAVEL" é o
// escape (a IA não força um palpite ruim — deixa cair no bloco de revisão).
export const SECAO_CANONICA_ENUM = [
  'ativo_circulante', 'ativo_nao_circulante',
  'passivo_circulante', 'passivo_nao_circulante', 'patrimonio_liquido',
  'receita_bruta', 'custos', 'despesas_operacionais', 'resultado_financeiro', 'impostos_lucro',
  'atividades_operacionais', 'atividades_investimento', 'atividades_financiamento',
  'NAO_CLASSIFICAVEL',
];

const SYSTEM_PROMPT = [
  'Você analisa UM documento financeiro de um mandato de Reestruturação (contexto Brasil) e',
  'devolve DUAS coisas: um diagnóstico do documento e a extração linha a linha de TODOS os',
  'dados financeiros nele contidos, organizados como uma planilha.',
  '',
  '== DIAGNÓSTICO ==',
  'entidade: razão social da empresa dona do documento, se aparecer no conteúdo (null se não',
  '  visível — NUNCA invente). NÃO use o nome de quem ASSINOU o documento (contador, administrador,',
  '  sócio) — o bloco de assinatura (com CRC, CPF, "Contador", "Administrador") é o SIGNATÁRIO, não',
  '  a entidade. Se o documento combina VÁRIAS empresas (colunas por empresa — ver LINHAS abaixo),',
  '  use o nome do GRUPO se houver um; senão deixe null (não escolha uma das empresas ao acaso).',
  'tipo_confirma / tipo_sugerido: você recebe uma DICA de tipo (vinda do nome do arquivo).',
  '  Leia o conteúdo e diga se ele bate (tipo_confirma=true) com a dica. tipo_sugerido é o',
  '  código da taxonomia que o CONTEÚDO sugere (pode ser igual ou diferente da dica — use',
  '  "DESCONHECIDO" só se o documento estiver genuinamente ilegível/não-financeiro).',
  '  BALANCO vs COMBINADO (confusão comum): COMBINADO = demonstrações de um GRUPO de VÁRIAS',
  '  empresas juntas (colunas por empresa: "Empresa A | Empresa B | Total"). Um único arquivo com',
  '  VÁRIAS demonstrações (Balanço + DRE + Fluxo de Caixa + DMPL) de UMA entidade só NÃO é',
  '  COMBINADO — classifique pela demonstração principal (normalmente BALANCO). Regra prática: se',
  '  as linhas têm entidade_coluna preenchido (várias empresas) → COMBINADO; se é uma entidade só',
  '  (mesmo com várias demonstrações no arquivo) → o tipo da demonstração principal.',
  'periodo_tipo / periodo_referencia: o período de competência real do conteúdo (convenções:',
  '  12M25=ano 2025; 1T25=1º tri/2025; L24M=últimos 24 meses; "23,24,25"=múltiplos exercícios;',
  '  um ano isolado como "2025" também é válido). É o período ATUAL do documento — NÃO use a data',
  '  de um SALDO DE ABERTURA/exercício anterior (ex.: uma DMPL que mostra "Saldos em 31/12/2023" e',
  '  "Saldos em 31/12/2024" é um documento de 2024; 2023 é só o saldo inicial, não o período).',
  'legibilidade: "ok" | "degradado" | "ilegivel" — avaliação real do ARQUIVO em si (não da',
  '  classificação): páginas faltando, tabela cortada, digitalização ruim, texto ilegível,',
  '  arquivo aparentemente incompleto. nota_legibilidade explica objetivamente QUANDO != "ok"',
  '  (null quando "ok").',
  'resumo: 2-3 frases objetivas do que o documento contém (para alguém decidir sem abrir o',
  '  arquivo).',
  'justificativa: 1-2 frases explicando o diagnóstico acima (o que você viu ou não viu).',
  '',
  '== LINHAS (planilha) ==',
  'Cada linha do JSON usa chaves CURTAS (economia de tokens de saída em documentos com muitas',
  'contas): s=secao, sc=secao_canonica, ec=entidade_coluna, pc=periodo_coluna, k=chave,',
  'vt=valor_texto, vn=valor_num, op=origem_pagina, cf=confianca. O texto abaixo usa os nomes',
  'completos (mais claro de explicar) — sempre correspondendo à chave curta do schema.',
  'Extraia TODAS as linhas financeiras do documento (rótulo + valor), preservando a estrutura',
  'original como uma "secao" por linha — ex.: "Ativo Circulante", "Ativo Não Circulante",',
  '"Passivo Circulante", "Passivo Não Circulante", "Patrimônio Líquido", "Receita Operacional",',
  '"Custos", "Despesas Operacionais", "Atividades Operacionais", "Atividades de Investimento",',
  '"Atividades de Financiamento" — use os agrupadores que o PRÓPRIO documento usa; null se a',
  'linha não pertencer a nenhuma seção clara (ex.: um total geral solto).',
  'valor_num = número puro (sem separador de milhar, ponto decimal) quando houver; senão null.',
  'valor_texto = como aparece no documento. Informe a página de origem.',
  'NÃO invente linhas nem valores. Se algo não estiver legível, omita — é melhor extrair de',
  'menos com confiança do que inventar.',
  '',
  'DOCUMENTO COM VÁRIAS ENTIDADES/COLUNAS LADO A LADO (ex.: um balanço combinado com colunas',
  '"Empresa A | Empresa B | Total"): isto é comum e NÃO deve ser resumido num valor só por',
  'conta — gere uma LINHA SEPARADA para cada combinação (conta × coluna), com o MESMO "chave"',
  '(rótulo da conta) e "entidade_coluna" preenchido com o nome EXATO do cabeçalho da coluna',
  '("Empresa A", "Empresa B", "Total", etc.). Nunca some, escolha ou estime um valor único',
  'representando várias colunas — se não conseguir ler alguma coluna com confiança, omita SÓ',
  'aquela linha (conta × coluna), não invente. Quando o documento é de uma entidade só (o caso',
  'comum), deixe "entidade_coluna" null em todas as linhas.',
  '',
  'DOCUMENTO COMPARATIVO — VÁRIAS COLUNAS DE PERÍODO LADO A LADO (ex.: um balanço ou DRE com',
  'colunas "2023 | 2024", ou "31/12/2023 | 31/12/2024", ou "Exercício atual | Exercício anterior"):',
  'isto é o padrão em demonstrações contábeis e NÃO deve ser resumido num valor só por conta —',
  'gere uma LINHA SEPARADA para cada (conta × período), com o MESMO "chave" e "periodo_coluna"',
  'preenchido com o rótulo EXATO da coluna de período ("2023", "2024", "31/12/2024", etc.). Isto é',
  'ortogonal a "entidade_coluna": um documento pode ter as duas dimensões (várias empresas E vários',
  'anos), gerando uma linha por (conta × empresa × período), cada uma com entidade_coluna E',
  'periodo_coluna preenchidos. Quando o documento tem um único período (o caso comum), deixe',
  '"periodo_coluna" null em todas as linhas. Nunca some, escolha ou estime um valor único cobrindo',
  'vários períodos.',
  '',
  'secao_canonica: além da "secao" livre acima, classifique CADA linha em UMA seção canônica',
  'padronizada (para a planilha final organizar as contas na estrutura de mercado). Use o',
  'julgamento contábil (o significado da conta, não só o nome literal — cada empresa nomeia',
  'diferente). Valores possíveis e seu significado:',
  '- Balanço/Balancete: "ativo_circulante", "ativo_nao_circulante", "passivo_circulante",',
  '  "passivo_nao_circulante", "patrimonio_liquido" (ex.: um mútuo A RECEBER é ativo; um mútuo',
  '  A PAGAR/tomado é passivo — decida pelo sentido).',
  '- DRE: "receita_bruta" (receita e deduções), "custos" (CPV/CMV/custo de serviço),',
  '  "despesas_operacionais" (vendas/administrativas/gerais), "resultado_financeiro"',
  '  (receitas/despesas financeiras, juros), "impostos_lucro" (IRPJ/CSLL).',
  '- Fluxo de Caixa: "atividades_operacionais", "atividades_investimento", "atividades_financiamento".',
  'Use "NAO_CLASSIFICAVEL" quando a linha for um TOTAL/subtotal geral, ou quando você não tiver',
  'segurança de qual seção é — NÃO force um palpite ruim (a linha vai para revisão manual, o que',
  'é preferível a classificar errado). Isto é uma SUGESTÃO revisável por humano, nunca um fato.',
].join(' ');

export function extractionSchema() {
  return {
    name: 'diagnostico_e_extracao',
    strict: true,
    schema: {
      type: 'object',
      additionalProperties: false,
      required: ['moeda', 'unidade', 'diagnostico', 'linhas'],
      properties: {
        moeda: { type: ['string', 'null'] },
        unidade: { type: ['string', 'null'] },
        diagnostico: {
          type: 'object',
          additionalProperties: false,
          required: [
            'entidade', 'tipo_confirma', 'tipo_sugerido', 'periodo_tipo', 'periodo_referencia',
            'legibilidade', 'nota_legibilidade', 'resumo', 'justificativa',
          ],
          properties: {
            entidade: { type: ['string', 'null'] },
            tipo_confirma: { type: 'boolean' },
            tipo_sugerido: { type: 'string', enum: codigosConhecidos() },
            periodo_tipo: { type: 'string', enum: PERIODO_TIPO_ENUM },
            periodo_referencia: { type: ['string', 'null'] },
            legibilidade: { type: 'string', enum: ['ok', 'degradado', 'ilegivel'] },
            nota_legibilidade: { type: ['string', 'null'] },
            resumo: { type: 'string' },
            justificativa: { type: 'string' },
          },
        },
        // Chaves CURTAS de propósito (s/sc/ec/pc/k/vt/vn/op/cf): `linhas` é o
        // único bloco que se repete centenas de vezes por documento — cada
        // caractere de nome de propriedade é gasto de novo A CADA linha no
        // JSON de saída. Documentos consolidados comparativos (2-3 anos lado
        // a lado, cada conta vira 2-3 linhas via periodo_coluna) truncavam
        // (finish_reason=length) antes mesmo de terminar de listar as contas —
        // achado em produção (sessão 7 cont.¹¹, "teste v18": 6 de 16
        // documentos, todos consolidados multi-ano). Nomes curtos aqui NÃO
        // mudam nada gravado no banco — `parseExtractionResponse` remapeia de
        // volta para os nomes completos (campo_extraido.secao_canonica etc.
        // continuam com os valores descritivos de sempre, só a REPRESENTAÇÃO
        // NO FIO com a OpenAI é compacta). `description` em cada campo mantém
        // o modelo orientado apesar do nome curto.
        linhas: {
          type: 'array',
          items: {
            type: 'object',
            additionalProperties: false,
            required: ['s', 'sc', 'ec', 'pc', 'k', 'vt', 'vn', 'op', 'cf'],
            properties: {
              s: { type: ['string', 'null'], description: 'secao: agrupador livre (rótulo do próprio documento)' },
              sc: { type: 'string', enum: SECAO_CANONICA_ENUM, description: 'secao_canonica: seção padronizada pelo significado contábil' },
              ec: { type: ['string', 'null'], description: 'entidade_coluna: nome da coluna/empresa quando há várias entidades lado a lado' },
              pc: { type: ['string', 'null'], description: 'periodo_coluna: rótulo da coluna de período quando há vários períodos lado a lado' },
              k: { type: 'string', description: 'chave: rótulo da conta' },
              vt: { type: ['string', 'null'], description: 'valor_texto: valor como aparece no documento' },
              vn: { type: ['number', 'null'], description: 'valor_num: valor numérico puro' },
              op: { type: ['integer', 'null'], description: 'origem_pagina: página de origem' },
              cf: { type: 'number', description: 'confianca: confiança 0-1 desta linha' },
            },
          },
        },
      },
    },
  };
}

// Teto de tokens de saída do gpt-4o (16384) — explícito porque documentos
// combinados grandes (grupo com várias entidades × várias demonstrações no
// mesmo PDF) exigem um array `linhas` extenso; sem isso fica sujeito a um
// default menor de max_tokens dependendo da conta/API, que corta a resposta
// no meio do JSON sem erro nenhum (ver parseExtractionResponse: finish_reason
// 'length' → JSON incompleto → falha silenciosa, achado em produção
// reprocessando "teste v14", sessão 7 cont.⁷).
const MAX_OUTPUT_TOKENS = 16384;

// conteudo: parte multimodal (file/image/text) — reaproveita contentPartFromFile.
export function buildExtractionRequest({ tipo, nomeOriginal, conteudo, model = DEFAULT_MODEL }) {
  return {
    url: OPENAI_URL,
    method: 'POST',
    body: {
      model,
      temperature: 0,
      max_tokens: MAX_OUTPUT_TOKENS,
      response_format: { type: 'json_schema', json_schema: extractionSchema() },
      messages: [
        { role: 'system', content: SYSTEM_PROMPT },
        {
          role: 'user',
          content: [
            {
              type: 'text',
              text: `Nome do arquivo: ${nomeOriginal || '(sem nome)'}. Dica de tipo (do nome, pode estar `
                + `errada): ${tipo || 'desconhecido'}. Diagnostique e extraia as linhas financeiras.`,
            },
            ...(Array.isArray(conteudo) ? conteudo : [conteudo]),
          ],
        },
      ],
    },
  };
}

// Normaliza a resposta para { moeda, unidade, campos[], diagnostico, falhaMotivo }.
// campos já vem no formato de fn_registrar_campos_extraidos (inclui secao).
// falhaMotivo é null quando a extração veio ok; motivo textual (para virar
// pendência tipada 'extracao_falhou') quando a chamada errou, veio truncada
// (finish_reason 'length' — teto de tokens de saída estourado) ou o conteúdo
// não é JSON válido. Sem isso, uma falha silenciosa gera 0 campos e ninguém
// nunca fica sabendo (achado em produção, sessão 7 cont.⁷ — "teste v14").
export function parseExtractionResponse(apiJson) {
  const finishReason = apiJson?.choices?.[0]?.finish_reason ?? null;
  const vazio = (falhaMotivo) => ({
    moeda: null, unidade: null, campos: [], falhaMotivo,
    diagnostico: {
      entidade: null, tipo_confirma: null, tipo_sugerido: null, periodo_tipo: null,
      periodo_referencia: null, legibilidade: null, nota_legibilidade: null,
      resumo: null, justificativa: '(sem diagnóstico: falha de rede/API ou resposta inválida)',
    },
  });
  if (apiJson?.error) {
    return vazio(`Erro da API OpenAI: ${apiJson.error.message || apiJson.error.code || JSON.stringify(apiJson.error)}`);
  }
  const content = apiJson?.choices?.[0]?.message?.content;
  if (!content) {
    return vazio('Resposta da OpenAI sem conteúdo (falha de rede/API).');
  }
  let p;
  try {
    p = typeof content === 'string' ? JSON.parse(content) : content;
  } catch {
    if (finishReason === 'length') {
      return vazio(
        'Resposta da OpenAI truncada por limite de tokens de saída (finish_reason=length) — o JSON '
        + 'ficou incompleto e não pôde ser interpretado. Documento provavelmente grande/denso demais '
        + '(muitas contas/entidades) para uma única chamada.',
      );
    }
    return vazio('Resposta da OpenAI não veio em JSON válido.');
  }
  const unidade = p.unidade ?? null;
  // Remapeia as chaves curtas do fio (s/sc/ec/pc/k/vt/vn/op/cf) para os nomes
  // completos usados em todo o resto do sistema (campo_extraido e por diante)
  // — a compactação é só na conversa com a OpenAI, nada rio abaixo muda.
  const campos = Array.isArray(p.linhas)
    ? p.linhas.map((l) => ({
        secao: l.s ?? null,
        secao_canonica: l.sc && l.sc !== 'NAO_CLASSIFICAVEL' ? l.sc : null,
        entidade_coluna: l.ec ?? null,
        periodo_coluna: l.pc ?? null,
        chave: l.k,
        valor_texto: l.vt ?? null,
        valor_num: typeof l.vn === 'number' ? l.vn : null,
        unidade,
        confianca: typeof l.cf === 'number' ? l.cf : null,
        origem_pagina: Number.isInteger(l.op) ? l.op : null,
      }))
    : [];
  const d = p.diagnostico || {};
  const diagnostico = {
    entidade: d.entidade ?? null,
    tipo_confirma: typeof d.tipo_confirma === 'boolean' ? d.tipo_confirma : null,
    tipo_sugerido: d.tipo_sugerido === 'DESCONHECIDO' ? null : (d.tipo_sugerido ?? null),
    periodo_tipo: d.periodo_referencia ? d.periodo_tipo : null,
    periodo_referencia: d.periodo_referencia ?? null,
    legibilidade: d.legibilidade ?? null,
    nota_legibilidade: d.nota_legibilidade ?? null,
    resumo: d.resumo ?? null,
    justificativa: d.justificativa ?? '',
  };
  // finish_reason 'length' com JSON válido é raro (o corte quase sempre cai
  // no meio de uma string/array e quebra o parse acima), mas se acontecer o
  // conteúdo pode estar incompleto de forma "silenciosa" (JSON bem formado,
  // faltando linhas do fim do documento) — sinaliza mesmo assim.
  const falhaMotivo = finishReason === 'length'
    ? 'Resposta da OpenAI atingiu o limite de tokens de saída (finish_reason=length); o JSON veio '
      + 'válido, mas o conteúdo pode estar incompleto (faltando linhas do fim do documento).'
    : null;
  return { moeda: p.moeda ?? null, unidade, campos, diagnostico, falhaMotivo };
}

export { OPENAI_URL, DEFAULT_MODEL, PERIODO_TIPO_ENUM };
