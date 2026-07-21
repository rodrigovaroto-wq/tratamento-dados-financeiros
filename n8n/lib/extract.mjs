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

const SYSTEM_PROMPT = [
  'Você analisa UM documento financeiro de um mandato de Reestruturação (contexto Brasil) e',
  'devolve DUAS coisas: um diagnóstico do documento e a extração linha a linha de TODOS os',
  'dados financeiros nele contidos, organizados como uma planilha.',
  '',
  '== DIAGNÓSTICO ==',
  'entidade: razão social da empresa dona do documento, se aparecer no conteúdo (null se não',
  '  visível — NUNCA invente).',
  'tipo_confirma / tipo_sugerido: você recebe uma DICA de tipo (vinda do nome do arquivo).',
  '  Leia o conteúdo e diga se ele bate (tipo_confirma=true) com a dica. tipo_sugerido é o',
  '  código da taxonomia que o CONTEÚDO sugere (pode ser igual ou diferente da dica — use',
  '  "DESCONHECIDO" só se o documento estiver genuinamente ilegível/não-financeiro).',
  'periodo_tipo / periodo_referencia: o período de competência real do conteúdo (convenções:',
  '  12M25=ano 2025; 1T25=1º tri/2025; L24M=últimos 24 meses; "23,24,25"=múltiplos exercícios;',
  '  um ano isolado como "2025" também é válido).',
  'legibilidade: "ok" | "degradado" | "ilegivel" — avaliação real do ARQUIVO em si (não da',
  '  classificação): páginas faltando, tabela cortada, digitalização ruim, texto ilegível,',
  '  arquivo aparentemente incompleto. nota_legibilidade explica objetivamente QUANDO != "ok"',
  '  (null quando "ok").',
  'resumo: 2-3 frases objetivas do que o documento contém (para alguém decidir sem abrir o',
  '  arquivo).',
  'justificativa: 1-2 frases explicando o diagnóstico acima (o que você viu ou não viu).',
  '',
  '== LINHAS (planilha) ==',
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
        linhas: {
          type: 'array',
          items: {
            type: 'object',
            additionalProperties: false,
            required: ['secao', 'chave', 'valor_texto', 'valor_num', 'origem_pagina', 'confianca'],
            properties: {
              secao: { type: ['string', 'null'] },
              chave: { type: 'string' },
              valor_texto: { type: ['string', 'null'] },
              valor_num: { type: ['number', 'null'] },
              origem_pagina: { type: ['integer', 'null'] },
              confianca: { type: 'number' },
            },
          },
        },
      },
    },
  };
}

// conteudo: parte multimodal (file/image/text) — reaproveita contentPartFromFile.
export function buildExtractionRequest({ tipo, nomeOriginal, conteudo, model = DEFAULT_MODEL }) {
  return {
    url: OPENAI_URL,
    method: 'POST',
    body: {
      model,
      temperature: 0,
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

// Normaliza a resposta para { moeda, unidade, campos[], diagnostico }.
// campos já vem no formato de fn_registrar_campos_extraidos (inclui secao).
export function parseExtractionResponse(apiJson) {
  const vazio = {
    moeda: null, unidade: null, campos: [],
    diagnostico: {
      entidade: null, tipo_confirma: null, tipo_sugerido: null, periodo_tipo: null,
      periodo_referencia: null, legibilidade: null, nota_legibilidade: null,
      resumo: null, justificativa: '(sem diagnóstico: falha de rede/API ou resposta inválida)',
    },
  };
  const content = apiJson?.choices?.[0]?.message?.content;
  if (!content) return vazio;
  let p;
  try {
    p = typeof content === 'string' ? JSON.parse(content) : content;
  } catch {
    return vazio;
  }
  const unidade = p.unidade ?? null;
  const campos = Array.isArray(p.linhas)
    ? p.linhas.map((l) => ({
        secao: l.secao ?? null,
        chave: l.chave,
        valor_texto: l.valor_texto ?? null,
        valor_num: typeof l.valor_num === 'number' ? l.valor_num : null,
        unidade,
        confianca: typeof l.confianca === 'number' ? l.confianca : null,
        origem_pagina: Number.isInteger(l.origem_pagina) ? l.origem_pagina : null,
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
  return { moeda: p.moeda ?? null, unidade, campos, diagnostico };
}

export { OPENAI_URL, DEFAULT_MODEL, PERIODO_TIPO_ENUM };
