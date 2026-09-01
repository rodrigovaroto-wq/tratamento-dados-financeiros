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
  // A CONFIANÇA É A DO VENCEDOR, NUNCA O MÁXIMO DAS DUAS.
  //
  // `Math.max` estava aqui e é um defeito de SEGURANÇA, não de estética: a
  // confiança devolvida passa a decidir, em `fn_registrar_documento`, se abre
  // `classificacao_pendente` (limiar do dial, 0,70). O caso concreto e alcançável:
  // a IA responde DESCONHECIDO com confiança 0,9 — ela está SEGURA de que o
  // documento é ilegível —, `tipo_taxonomia` vira `null`, o palpite do NOME vence
  // com 0,5… e saía 0,9. Um documento que a IA declarou ilegível entrava
  // classificado, sem humano nenhum olhar, apoiado num palpite de 0,5.
  //
  // Com o vencedor, os quatro casos ficam certos e o `max` some sem perda: quando
  // as duas têm tipo, o vencedor JÁ É o de maior confiança, então vencedor === max.
    confianca: winner.confianca ?? 0,
    fonte: winner === fromAI ? 'openai_conteudo' : 'nome_arquivo',
    justificativa: fromAI.justificativa || '',
  };
}
