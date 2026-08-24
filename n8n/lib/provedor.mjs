// O PROVEDOR DE IA VIRA ESCOLHA, E A ESCOLHA MORA AQUI.
//
// Até 24/08/2026 este repositório não tinha "um provedor": tinha a OpenAI
// espalhada. A URL estava em `lib/openai.mjs` e outra vez em `lib/extract.mjs`;
// o formato do corpo (`messages`/`response_format`) estava nos dois módulos e
// mais uma vez, minificado, dentro de `build-workflow.mjs`; a leitura da
// resposta (`choices[0].message.content`) aparecia em quatro lugares; e o
// `usage` da OpenAI era lido direto pelo medidor de custo. Trocar de provedor
// era, literalmente, achar todos eles.
//
// Aqui a diferença entre um provedor e outro fica reduzida a UM objeto de dados
// (`PROVEDORES`) e a um punhado de funções que ramificam pelo `dialeto` dele.
// O resto do sistema não sabe com quem está falando: monta o corpo, lê o
// conteúdo, lê o uso.
//
// POR QUE DADO PURO, E NÃO UM OBJETO COM MÉTODOS. Os nós Code do n8n não
// importam módulo — o gerador embute o `toString()` das funções da lib, e
// `toString()` não leva o escopo do módulo junto (é o mesmo motivo pelo qual
// `diagnosticarErroApi` é auto-contida). Um provedor com métodos não
// atravessaria essa fronteira; um provedor que é JSON atravessa, porque o
// gerador o escreve no nó como literal e as funções o recebem por argumento.
//
// LGPD: vale para qualquer provedor daqui, e a trilha não mudou de lugar — API
// direta está fora do perímetro Azure, e antes de dado real em produção é
// preciso ter zero-retention/DPA acertado com QUEM ESTIVER ATIVO (ver f0/02 e
// docs/10). Trocar de provedor não herda o acordo do anterior.

// ---------------------------------------------------------------------------
// O CATÁLOGO
// ---------------------------------------------------------------------------
//
// `dialeto` é o que as funções deste arquivo olham — 'openai' cobre todo
// provedor que fala `/chat/completions` (a própria OpenAI, e por tabela quem
// imita o formato dela), 'gemini' cobre a API nativa do Google.
//
// A API NATIVA DO GOOGLE, E NÃO A CAMADA DE COMPATIBILIDADE. O Google publica um
// endpoint que imita o `/chat/completions`, e usá-lo faria este arquivo quase
// desaparecer. Não foi o escolhido, e o motivo é o único que importa aqui: o que
// esta troca busca é a leitura de DOCUMENTO, e é a API nativa que recebe o PDF
// como parte (`inlineData` com `application/pdf`) e aceita `responseSchema`. Uma
// camada de imitação é, por construção, o subconjunto que o formato do outro
// comporta — trocar de provedor para ficar com o subconjunto do provedor antigo
// seria pagar a migração e não levar a mercadoria.
export const PROVEDORES = {
  openai: {
    id: 'openai',
    rotulo: 'OpenAI',
    dialeto: 'openai',
    // `{modelo}` não é interpolado nesta URL (o modelo vai no corpo) — o
    // marcador existe para as duas entradas terem a mesma forma.
    url: 'https://api.openai.com/v1/chat/completions',
    // Nome da credencial Header Auth no n8n. O dono cria uma credencial com
    // este nome e o JSON gerado já aponta para ela.
    credencial: 'OpenAI API',
    auth: { nome: 'Authorization', prefixo: 'Bearer ' },
    console: 'platform.openai.com',
    // Cadência: os dois limites da conta, e o intervalo sai do MAIS restritivo.
    // TPM importa porque `max_tokens` é RESERVA de balde (ver extract.mjs);
    // RPM importa porque um provedor pode limitar por CHAMADA e não por token.
    tpm: 30000,
    rpm: null,
  },
  google: {
    id: 'google',
    rotulo: 'Google (Gemini)',
    dialeto: 'gemini',
    url: 'https://generativelanguage.googleapis.com/v1beta/models/{modelo}:generateContent',
    credencial: 'Google AI (Gemini)',
    // A chave vai em header próprio, não em Bearer, e NUNCA na query string:
    // `?key=` apareceria na URL do nó, que o n8n mostra na tela de execução e
    // grava no log — é segredo em lugar de leitura.
    auth: { nome: 'x-goog-api-key', prefixo: '' },
    console: 'aistudio.google.com/apikey',
    // 250.000 TPM e 15 RPM é o patamar de entrada anunciado para a linha
    // Flash-Lite. Declarado no PISO de propósito, pela mesma regra que já valia
    // para o Tier 1 da OpenAI: errar para o lento faz a extração demorar; errar
    // para o rápido faz ela FALHAR, e falha custa a rodada inteira. Quem estiver
    // num tier acima ajusta AQUI — e os três lugares que dependem da cadência
    // (o gerador, o teste que a trava e o diagnóstico) leem este mesmo número.
    tpm: 250000,
    rpm: 15,
  },
};

// O PADRÃO É O GOOGLE desde 24/08/2026 (decisão do dono). A OpenAI continua
// inteira e testada aqui — trocar de volta é `IA_PROVEDOR=openai` e regerar o
// workflow, não é reescrever nada.
export const PROVEDOR_PADRAO = 'google';

/**
 * O provedor ativo, lido do ambiente. Nome desconhecido cai no padrão em vez de
 * lançar: o gerador roda em CI e num terminal, e um `IA_PROVEDOR` com erro de
 * digitação não deve produzir um workflow pela metade — deve produzir o padrão.
 */
export function provedorAtivo(env = (typeof process !== 'undefined' ? process.env : {})) {
  const id = String((env && env.IA_PROVEDOR) || '').trim().toLowerCase();
  return Object.prototype.hasOwnProperty.call(PROVEDORES, id) ? id : PROVEDOR_PADRAO;
}

/** O objeto do provedor, por id. Desconhecido → o padrão (mesma razão acima). */
export function provedor(id = provedorAtivo()) {
  return PROVEDORES[id] || PROVEDORES[PROVEDOR_PADRAO];
}

/** A URL da chamada, já com o modelo no lugar quando o dialeto pede. */
export function urlDaChamada(prov, modelo) {
  return String(prov.url).replace('{modelo}', encodeURIComponent(String(modelo || '')));
}

// ---------------------------------------------------------------------------
// O SCHEMA — a tradução que não pode inventar campo
// ---------------------------------------------------------------------------
//
// Os dois schemas do sistema (classificação e extração) são escritos no dialeto
// da OpenAI: `strict`, `additionalProperties:false`, e o "nulo" expresso como
// `type:['string','null']`. O Gemini fala um subconjunto de OpenAPI: tipos em
// MAIÚSCULA, nulo como `nullable:true`, e nada de `additionalProperties`,
// `strict`, `minimum` ou `maximum` — mandar um campo que ele não conhece é 400
// na chamada inteira, não um aviso.
//
// A tradução é MECÂNICA de propósito: ela não acrescenta nem remove propriedade
// nenhuma, só reescreve a forma. Quem manda no conteúdo continua sendo o schema
// da lib — se um dia a extração ganhar um campo, ele aparece nos dois provedores
// sem ninguém tocar aqui, que é a diferença entre uma tradução e um segundo
// schema mantido à mão (o espelho manual que este repositório já viu divergir).
//
// `propertyOrdering` não é enfeite: o Gemini documenta que a ordem das chaves na
// saída segue a do schema, e a nossa ordem é a de LEITURA do documento
// (seção → colunas → contas). Sem ela, a ordem fica a critério do modelo — e a
// ordem das linhas é dado neste sistema (0027: é ela que denuncia o subtotal
// impresso acima dos componentes).
export function schemaDoProvedor(prov, jsonSchema) {
  const traduzir = (no) => {
    if (!no || typeof no !== 'object') return no;
    const tipos = Array.isArray(no.type) ? no.type : [no.type];
    const nulo = tipos.includes('null');
    const base = tipos.find((t) => t && t !== 'null') || 'string';
    const MAPA = {
      string: 'STRING', number: 'NUMBER', integer: 'INTEGER',
      boolean: 'BOOLEAN', array: 'ARRAY', object: 'OBJECT',
    };
    const fora = { type: MAPA[base] || 'STRING' };
    if (nulo) fora.nullable = true;
    if (no.description) fora.description = no.description;
    if (Array.isArray(no.enum)) fora.enum = no.enum.slice();
    if (no.items) fora.items = traduzir(no.items);
    if (no.properties && typeof no.properties === 'object') {
      const chaves = Object.keys(no.properties);
      fora.properties = {};
      for (const k of chaves) fora.properties[k] = traduzir(no.properties[k]);
      fora.propertyOrdering = chaves;
      // `required` do Gemini é lista de chaves, igual ao JSON Schema — mas só
      // faz sentido num objeto, e mandá-lo solto num escalar é 400.
      if (Array.isArray(no.required)) fora.required = no.required.slice();
    }
    return fora;
  };
  if (prov.dialeto === 'gemini') return traduzir(jsonSchema.schema || jsonSchema);
  return jsonSchema;
}

// ---------------------------------------------------------------------------
// O CORPO DA CHAMADA
// ---------------------------------------------------------------------------
//
// A mesma entrada nos dois dialetos: um prompt de SISTEMA (idêntico em toda
// chamada — é o que faz o cache de prefixo valer, docs/CUSTO_IA.md), uma lista
// de PARTES de usuário (texto + o documento), um schema e um teto de saída.
//
// O prompt de sistema fica em campo PRÓPRIO nos dois (`role:'system'` na OpenAI,
// `systemInstruction` no Gemini) e nunca é concatenado na mensagem do usuário:
// é a condição do cache, e é o invariante que `workflow-sim.test.mjs` trava.
//
// `schema` NULO é caso legítimo, e existe por um usuário só: o workflow de
// diagnóstico, que manda uma chamada de UM token para descobrir se a conta
// responde. Ali não há saída para prender — prendê-la a um schema faria a
// chamada mínima deixar de ser mínima. Todo o resto do sistema sempre manda
// schema, e é o schema que torna o parsing não-frágil.
export function montarCorpoIA(prov, { modelo, sistema, partes, schema = null, maxTokens = null }) {
  const lista = Array.isArray(partes) ? partes : [partes];
  if (prov.dialeto === 'gemini') {
    const corpo = {
      contents: [{ role: 'user', parts: lista }],
      generationConfig: { temperature: 0 },
    };
    if (sistema) corpo.systemInstruction = { parts: [{ text: sistema }] };
    if (schema) {
      corpo.generationConfig.responseMimeType = 'application/json';
      corpo.generationConfig.responseSchema = schemaDoProvedor(prov, schema);
    }
    if (maxTokens) corpo.generationConfig.maxOutputTokens = maxTokens;
    return corpo;
  }
  const corpo = { model: modelo, temperature: 0, messages: [] };
  if (schema) corpo.response_format = { type: 'json_schema', json_schema: schema };
  if (sistema) corpo.messages.push({ role: 'system', content: sistema });
  corpo.messages.push({ role: 'user', content: lista });
  if (maxTokens) corpo.max_tokens = maxTokens;
  return corpo;
}

// ---------------------------------------------------------------------------
// AS PARTES DE CONTEÚDO
// ---------------------------------------------------------------------------
//
// NUNCA LANÇA: tipo não suportado vira uma parte de TEXTO que declara o caso, em
// vez de derrubar o item. É comportamento antigo e deliberado — um dead-end no
// meio do grafo do n8n é uma execução que morre sem dizer o que faltou.
export function parteDeTexto(prov, texto) {
  const t = String(texto == null ? '' : texto);
  return prov.dialeto === 'gemini' ? { text: t } : { type: 'text', text: t };
}

export function parteDeArquivo(prov, { mimeType, base64, filename, text } = {}) {
  const mt = (mimeType || '').toLowerCase();
  if (text != null && text !== '') {
    return parteDeTexto(prov, String(text).slice(0, 20000));
  }
  const ehPdf = /pdf/.test(mt);
  const ehImagem = mt.startsWith('image/');
  if (!ehPdf && !ehImagem) {
    return parteDeTexto(
      prov,
      `(conteúdo não enviado: tipo "${mt || 'desconhecido'}" requer extração prévia; `
      + `classificar só pelo nome "${filename || ''}")`,
    );
  }
  if (prov.dialeto === 'gemini') {
    // O Gemini recebe PDF e imagem pela MESMA porta (`inlineData`), e é isso que
    // faz o documento escaneado e o documento com camada de texto seguirem o
    // mesmo caminho — na OpenAI eles são duas formas diferentes de parte.
    return { inlineData: { mimeType: ehPdf ? 'application/pdf' : mt, data: base64 } };
  }
  if (ehPdf) {
    return {
      type: 'file',
      file: { filename: filename || 'documento.pdf', file_data: `data:application/pdf;base64,${base64}` },
    };
  }
  return { type: 'image_url', image_url: { url: `data:${mt};base64,${base64}` } };
}

// ---------------------------------------------------------------------------
// A LEITURA DA RESPOSTA
// ---------------------------------------------------------------------------

/**
 * O texto da resposta — o JSON pedido no schema, ainda como string.
 *
 * O Gemini pode devolver a saída repartida em VÁRIAS partes do mesmo candidato;
 * ler só `parts[0]` daria um JSON cortado ao meio, que é indistinguível de
 * truncamento e mandaria a próxima sessão investigar o teto de tokens. Concatena.
 */
export function conteudoDaResposta(prov, resp) {
  if (prov.dialeto === 'gemini') {
    const partes = resp && resp.candidates && resp.candidates[0]
      && resp.candidates[0].content && resp.candidates[0].content.parts;
    if (!Array.isArray(partes)) return null;
    const texto = partes.map((p) => (p && typeof p.text === 'string' ? p.text : '')).join('');
    return texto === '' ? null : texto;
  }
  const c = resp && resp.choices && resp.choices[0]
    && resp.choices[0].message && resp.choices[0].message.content;
  return c == null || c === '' ? null : c;
}

/**
 * A resposta foi cortada pelo teto de saída?
 *
 * Normalizado para booleano de propósito: `finish_reason:'length'` e
 * `finishReason:'MAX_TOKENS'` são o mesmo fato, e quem lê rio abaixo só precisa
 * do fato. É ele que separa "documento denso demais para uma chamada" de
 * "resposta inválida" — e essa distinção decide se o caminho é fatiar ou
 * investigar.
 */
export function cortadoPorLimite(prov, resp) {
  if (prov.dialeto === 'gemini') {
    return (resp && resp.candidates && resp.candidates[0]
      && resp.candidates[0].finishReason) === 'MAX_TOKENS';
  }
  return (resp && resp.choices && resp.choices[0] && resp.choices[0].finish_reason) === 'length';
}

/**
 * O uso da chamada, NA FORMA DA OPENAI.
 *
 * Normalizar aqui é o que deixa `custoDaChamada` intocado: ele já sabia ler
 * `prompt_tokens`/`completion_tokens`/`cached_tokens`, e continua sendo o único
 * lugar que faz conta de dinheiro. O provedor novo não espalha um segundo
 * formato de `usage` pelo sistema — ele traduz para o que já existe.
 *
 * Ausente devolve `null`, e não zero: `custoDaChamada` trata null como "não sei"
 * e devolve null, que é o certo. Zero seria um custo INVENTADO num relatório de
 * custo, que é pior que um campo vazio.
 */
export function usoDaChamada(prov, resp) {
  if (prov.dialeto === 'gemini') {
    const u = resp && resp.usageMetadata;
    if (!u) return null;
    const cache = Number(u.cachedContentTokenCount || 0);
    return {
      prompt_tokens: Number(u.promptTokenCount || 0),
      completion_tokens: Number(u.candidatesTokenCount || 0),
      prompt_tokens_details: { cached_tokens: Number.isFinite(cache) ? cache : 0 },
    };
  }
  return (resp && resp.usage) || null;
}

/**
 * Acrescenta uma instrução ao FIM do texto da mensagem de usuário.
 *
 * Usado pelo fatiamento, que precisa dizer "extraia da linha X à Y" sem tocar no
 * prompt de sistema — o prefixo tem de continuar byte a byte idêntico em toda
 * chamada para o cache valer (docs/CUSTO_IA.md, alavanca 3). Muda o corpo NO
 * LUGAR e devolve ele, porque quem chama já trabalha sobre uma cópia funda.
 */
export function acrescentarInstrucao(prov, corpo, instrucao) {
  if (!instrucao || !corpo) return corpo;
  if (prov.dialeto === 'gemini') {
    const c = Array.isArray(corpo.contents) ? corpo.contents[corpo.contents.length - 1] : null;
    const p = c && Array.isArray(c.parts) ? c.parts[0] : null;
    if (p && typeof p.text === 'string') p.text += instrucao;
    return corpo;
  }
  const m = Array.isArray(corpo.messages) ? corpo.messages[corpo.messages.length - 1] : null;
  const parte = m && Array.isArray(m.content) ? m.content[0] : null;
  if (parte && typeof parte.text === 'string') parte.text += instrucao;
  return corpo;
}
