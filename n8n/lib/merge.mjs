// Combina a classificação por NOME (barata/determinística) com a classificação
// por CONTEÚDO (fallback OpenAI), quando ambas rodaram para o mesmo documento.
//
// Regra: nenhuma das duas "vence" por padrão — fica a que tem MAIOR confiança
// (e, entre as duas, sempre com um tipo_taxonomia não-nulo, se alguma tiver).
// Isso evita que um fallback que voltou incerto (ex.: DESCONHECIDO, confiança
// baixa) sobrescreva um palpite melhor que já vinha do nome do arquivo.
//
// `justificativa` da IA é sempre preservada (mesmo quando o nome "vence"),
// para o humano ver o raciocínio por trás da chamada, inclusive quando ela
// discordou do nome do arquivo.

export function mergeClassification(fromName, fromAI) {
  const nameHasTipo = !!fromName.tipo_taxonomia;
  const aiHasTipo = !!fromAI.tipo_taxonomia;

  let winner;
  if (aiHasTipo && nameHasTipo) {
    winner = (fromAI.confianca ?? 0) >= (fromName.confianca ?? 0) ? fromAI : fromName;
  } else if (aiHasTipo) {
    winner = fromAI;
  } else if (nameHasTipo) {
    winner = fromName;
  } else {
    winner = fromAI; // nenhuma achou tipo; usa confiança/justificativa da IA mesmo assim
  }

  return {
    tipo_taxonomia: winner.tipo_taxonomia ?? null,
    periodo_tipo: fromAI.periodo_ref ? fromAI.periodo_tipo : (fromName.periodo_ref ? fromName.periodo_tipo : null),
    periodo_ref: fromAI.periodo_ref ?? fromName.periodo_ref ?? null,
    assinado: fromAI.assinado ?? fromName.assinado ?? null,
    entidade: fromAI.entidade ?? fromName.entidade ?? null,
    confianca: Math.max(fromName.confianca || 0, fromAI.confianca || 0),
    fonte: winner === fromAI ? 'openai_conteudo' : 'nome_arquivo',
    justificativa: fromAI.justificativa || '',
  };
}
