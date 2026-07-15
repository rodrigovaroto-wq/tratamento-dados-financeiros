// Extração de linhas financeiras (E2) via OpenAI — modo SOMBRA (N0).
//
// Doutrina (docs/01): extração de linhas NASCE em N0. Aqui só montamos a chamada
// e parseamos a resposta; o registro no banco é sombra (fn_registrar_campos_extraidos,
// nivel_autonomia N0). Nada entra em base sem aceite humano (anti-ancoragem).
//
// Schema genérico (v1): serve para DRE/Balanço/Fluxo/Combinado/Faturamento. O
// refino por tipo (linhas esperadas de cada demonstração) é calibração posterior.

const OPENAI_URL = 'https://api.openai.com/v1/chat/completions';
const DEFAULT_MODEL = 'gpt-4o';

const SYSTEM_PROMPT = [
  'Você extrai LINHAS FINANCEIRAS de um documento (DRE, Balanço, Fluxo de Caixa, Combinado,',
  'Faturamento) de uma empresa brasileira. Liste cada rótulo com seu valor.',
  'valor_num = número puro (sem separador de milhar, ponto decimal), quando houver; senão null.',
  'valor_texto = como aparece no documento. Informe a unidade (ex.: "BRL", "R$ mil") e a página.',
  'NÃO invente linhas nem valores. Se algo não estiver legível, omita. É melhor extrair de',
  'menos com confiança do que inventar.',
].join(' ');

export function extractionSchema() {
  return {
    name: 'extracao_linhas_financeiras',
    strict: true,
    schema: {
      type: 'object',
      additionalProperties: false,
      required: ['moeda', 'unidade', 'linhas'],
      properties: {
        moeda: { type: ['string', 'null'] },
        unidade: { type: ['string', 'null'] },
        linhas: {
          type: 'array',
          items: {
            type: 'object',
            additionalProperties: false,
            required: ['chave', 'valor_texto', 'valor_num', 'origem_pagina', 'confianca'],
            properties: {
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
export function buildExtractionRequest({ tipo, conteudo, model = DEFAULT_MODEL }) {
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
            { type: 'text', text: `Tipo do documento (dica): ${tipo || 'desconhecido'}. Extraia as linhas financeiras.` },
            ...(Array.isArray(conteudo) ? conteudo : [conteudo]),
          ],
        },
      ],
    },
  };
}

// Normaliza a resposta para o formato de fn_registrar_campos_extraidos.
export function parseExtractionResponse(apiJson) {
  const content = apiJson?.choices?.[0]?.message?.content;
  if (!content) return { moeda: null, unidade: null, campos: [] };
  let p;
  try {
    p = typeof content === 'string' ? JSON.parse(content) : content;
  } catch {
    return { moeda: null, unidade: null, campos: [] };
  }
  const unidade = p.unidade ?? null;
  const campos = Array.isArray(p.linhas)
    ? p.linhas.map((l) => ({
        chave: l.chave,
        valor_texto: l.valor_texto ?? null,
        valor_num: typeof l.valor_num === 'number' ? l.valor_num : null,
        unidade,
        confianca: typeof l.confianca === 'number' ? l.confianca : null,
        origem_pagina: Number.isInteger(l.origem_pagina) ? l.origem_pagina : null,
      }))
    : [];
  return { moeda: p.moeda ?? null, unidade, campos };
}

export { OPENAI_URL, DEFAULT_MODEL };
