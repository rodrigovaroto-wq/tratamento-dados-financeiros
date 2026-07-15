// Integração OpenAI (API direta) — fallback de classificação por CONTEÚDO.
//
// Usada quando o classificador por nome não tem confiança (nome genérico).
// Modelo multimodal + Structured Outputs: força a saída num JSON Schema, então
// não há parsing frágil de texto livre.
//
// Autonomia: continua N1 — a saída é SUGESTÃO para a fila de revisão, com
// confiança e justificativa. Nada é aceito sem humano (anti-ancoragem, docs/01).
//
// LGPD: API direta está fora do perímetro Azure. Antes de dados reais em
// produção, ativar zero-retention/DPA da OpenAI (ver f0/02). Migração p/ Azure
// OpenAI é trivial (trocar baseURL + auth).

import { ALIASES, KIT_BASICO } from './taxonomia.mjs';

const DEFAULT_MODEL = 'gpt-4o'; // configurável via env OPENAI_MODEL no N8N
const OPENAI_URL = 'https://api.openai.com/v1/chat/completions';

// Enum de códigos possíveis para a classificação (taxonomia conhecida + escape).
export function codigosConhecidos() {
  const set = new Set([...KIT_BASICO, ...ALIASES.map((a) => a.codigo)]);
  return [...set, 'DESCONHECIDO'];
}

const SYSTEM_PROMPT = [
  'Você classifica documentos financeiros de mandatos de Reestruturação (contexto Brasil).',
  'Dado o conteúdo de UM documento, identifique o tipo (código da taxonomia), a entidade',
  '(empresa/razão social, se visível), o período de competência e se é versão assinada.',
  'Convenções de período: "12M25"=ano 2025; "1T25"=1º trimestre/2025; "L24M"=últimos 24 meses;',
  'listas de anos como "23,24,25" para múltiplos exercícios.',
  'Se não tiver certeza do tipo, use "DESCONHECIDO" e confianca baixa. NUNCA invente valores.',
  'Responda SOMENTE conforme o schema.',
].join(' ');

// Schema estrito da resposta (Structured Outputs).
export function classificationSchema() {
  return {
    name: 'classificacao_documento',
    strict: true,
    schema: {
      type: 'object',
      additionalProperties: false,
      required: ['tipo_taxonomia', 'entidade', 'periodo_tipo', 'periodo_referencia', 'assinado', 'confianca', 'justificativa'],
      properties: {
        tipo_taxonomia: { type: 'string', enum: codigosConhecidos() },
        entidade: { type: ['string', 'null'] },
        periodo_tipo: { type: 'string', enum: ['anual', 'trimestre', 'multi', 'data-base', 'outro', 'desconhecido'] },
        periodo_referencia: { type: ['string', 'null'] },
        assinado: { type: ['boolean', 'null'] },
        confianca: { type: 'number', minimum: 0, maximum: 1 },
        justificativa: { type: 'string' },
      },
    },
  };
}

// Monta o corpo da chamada. `conteudo` é uma parte multimodal já pronta:
//   - { type:'image_url', image_url:{ url:'data:...'} } para página/imagem
//   - { type:'text', text:'...'} quando já houver texto extraído
export function buildClassificationRequest({ nomeOriginal, conteudo, model = DEFAULT_MODEL }) {
  return {
    url: OPENAI_URL,
    method: 'POST',
    body: {
      model,
      temperature: 0,
      response_format: { type: 'json_schema', json_schema: classificationSchema() },
      messages: [
        { role: 'system', content: SYSTEM_PROMPT },
        {
          role: 'user',
          content: [
            { type: 'text', text: `Nome do arquivo (pista fraca): ${nomeOriginal || '(sem nome)'}` },
            ...(Array.isArray(conteudo) ? conteudo : [conteudo]),
          ],
        },
      ],
    },
  };
}

// Extrai e valida o JSON da resposta da OpenAI (Chat Completions).
export function parseClassificationResponse(apiJson) {
  const content = apiJson?.choices?.[0]?.message?.content;
  if (!content) throw new Error('Resposta OpenAI sem content');
  let parsed;
  try {
    parsed = typeof content === 'string' ? JSON.parse(content) : content;
  } catch (e) {
    throw new Error(`Conteúdo OpenAI não é JSON válido: ${e.message}`);
  }
  // Normaliza para o mesmo formato do classificador por nome.
  return {
    tipo_taxonomia: parsed.tipo_taxonomia === 'DESCONHECIDO' ? null : parsed.tipo_taxonomia,
    entidade: parsed.entidade ?? null,
    periodo: parsed.periodo_referencia
      ? { tipo: parsed.periodo_tipo, referencia: parsed.periodo_referencia }
      : null,
    assinado: parsed.assinado ?? null,
    confianca: typeof parsed.confianca === 'number' ? parsed.confianca : 0,
    fonte: 'openai_conteudo',
    justificativa: parsed.justificativa || '',
  };
}

export { DEFAULT_MODEL, OPENAI_URL };
