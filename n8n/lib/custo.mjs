// Orçamento de execução — o teto de gasto que o DONO pediu, em código.
//
// Pedido literal (2026-07-31, depois do teste v31): "o sistema não deve gastar
// mais de $3 dólares por execução completa e o teto deve ficar em $5".
//
// São DUAS defesas em camadas diferentes, e a distinção importa:
//
//   • O teto de US$ 5 é configurado NA OPENAI (Settings → Projects → Limits). É
//     a defesa dura: se este código falhar em qualquer hipótese, a OpenAI recusa
//     a chamada e o pipeline registra `limite_de_gasto` com causa nomeada — foi
//     exatamente o que aconteceu no v31. Nenhuma linha daqui pode substituir
//     isso, e é bom que não possa: um teto que o próprio sistema controla é um
//     teto que um bug do próprio sistema fura.
//
//   • O teto de US$ 3 por execução é ESTE arquivo. Ele existe para o lote nunca
//     CHEGAR no limite da OpenAI, porque chegar lá é caro de outra forma: no v31
//     o teto cortou no meio do lote e 8 documentos morreram sem extração. A
//     diferença entre US$ 3 e US$ 5 é a folga que garante que quem barra o lote
//     seja este código (que explica o que fazer) e não a API (que só devolve 429).
//
// A decisão é tomada ANTES da primeira chamada, e é um NÃO INTEIRO: ou o lote
// cabe e roda todo, ou não começa. Deliberadamente não existe "roda os que
// cabem": um lote parcial deixa metade dos documentos registrados sem extração
// e a outra metade sem registro nenhum, e distinguir os dois casos depois é o
// tipo de trabalho que a doutrina (docs/01) manda não criar. Recusar antes de
// gastar não custa nada e diz o que fazer.

// Preço do gpt-4o, US$ por MILHÃO de tokens (platform.openai.com/pricing).
// ⚠️ Preço de terceiro muda sem avisar e este arquivo não tem como saber. Se a
// conta divergir do que `custoDaChamada` reporta, é AQUI que se corrige — e o
// sintoma é o orçamento parecer folgado enquanto a fatura não é.
export const PRECO_USD_POR_MILHAO = {
  'gpt-4o': { entrada: 2.5, entrada_cache: 1.25, saida: 10.0 },
  'gpt-4o-mini': { entrada: 0.15, entrada_cache: 0.075, saida: 0.6 },
};

// Teto por execução completa (pedido do dono). Menor que o teto da OpenAI de
// propósito — ver o comentário do topo.
export const TETO_EXECUCAO_USD = 3;

// ---------------------------------------------------------------------------
// OS DOIS MODELOS DO PIPELINE — e por que eles moram AQUI e não no build
// ---------------------------------------------------------------------------
//
// Eles estavam em `build-workflow.mjs`, que é quem os escreve nos nós. Mudaram
// de casa porque o ORÇAMENTO passou a depender deles: o preço da chamada de
// classificação entra na conta do lote (ver `pesoDaChamadaDeClassificacao`), e
// um preço derivado de um modelo declarado em outro arquivo é a mesma cópia à
// mão que este repositório já viu divergir três vezes. O build importa daqui.
//
// `MODELO_CLASSIFICACAO` é `gpt-4o-mini` desde 13/08/2026 — a recomendação nº 1
// de `docs/CUSTO_OPENAI.md` ("agora, sem risco"), acionada quando o dono pediu
// redução de custo por chamada. A tarefa é a mais leve do pipeline (escolher um
// código de um enum + entidade/período) e ela tem REDE: o `diagnostico` da
// extração — que segue no modelo forte — confere tipo/entidade/período contra o
// conteúdo e abre pendência quando diverge. Erro de classificação é detectado,
// não silencioso.
//
// `MODELO_EXTRACAO` NÃO muda. É a tarefa que exige julgamento contábil linha a
// linha, e ela não tem rede nenhuma depois dela.
export const MODELO_CLASSIFICACAO = 'gpt-4o-mini';
export const MODELO_EXTRACAO = 'gpt-4o';

// ---------------------------------------------------------------------------
// O PESO DA SEGUNDA CHAMADA — o defeito de estimativa que restava
// ---------------------------------------------------------------------------
//
// O orçamento contava a chamada de CLASSIFICAÇÃO como se ela custasse o mesmo
// que uma extração. Não custa, e a diferença é grande: medido no book-canastra,
// as 19 classificações somaram **US$ 0,0893** contra **US$ 1,32** das 38
// extrações — US$ 0,0047 contra US$ 0,035 em média, ou seja **13%**. A razão é
// física: as duas mandam o MESMO PDF, mas a classificação devolve um objeto de
// ~120 tokens e a extração devolve centenas de linhas — e a saída responde por
// ~75% da conta (medição do book, `docs/CUSTO_OPENAI.md`).
//
// Cobrar cheio inflava a estimativa do book em 46% (fator 1,5 em vez de 1,03) e
// era o que faltava para o lote de 35 caber com folga em vez de raspar o teto.
//
// A conta do peso, com as duas parcelas declaradas:
//
//   peso = PARCELA_ENTRADA_NA_CHAMADA × (preço de entrada do modelo de
//          classificação ÷ preço de entrada do modelo de extração)
//
// `PARCELA_ENTRADA_NA_CHAMADA = 0,30` é a fatia da conta que é ENTRADA (medido:
// 25%; 0,30 é a margem). O segundo termo é 1 quando os dois modelos são iguais e
// 0,06 com a classificação em `gpt-4o-mini`. O piso de 0,05 existe para que a
// segunda chamada NUNCA saia de graça: modelo barato não é modelo grátis, e um
// lote de mil documentos mal nomeados tem de pesar alguma coisa.
export const PARCELA_ENTRADA_NA_CHAMADA = 0.3;
export const PESO_MINIMO_CLASSIFICACAO = 0.05;

export function pesoDaChamadaDeClassificacao(
  modeloClassificacao = MODELO_CLASSIFICACAO,
  modeloExtracao = MODELO_EXTRACAO,
) {
  const c = PRECO_USD_POR_MILHAO[modeloClassificacao];
  const e = PRECO_USD_POR_MILHAO[modeloExtracao];
  // Modelo que não está na tabela de preço é modelo cujo custo não se conhece —
  // e desconhecido cobra CHEIO. Errar para o lado seguro é o projeto daqui.
  if (!c || !e || !(e.entrada > 0)) return 1;
  return Math.max(PESO_MINIMO_CLASSIFICACAO, PARCELA_ENTRADA_NA_CHAMADA * (c.entrada / e.entrada));
}

// Versão do orçamento, e ela vai na MENSAGEM de recusa de propósito.
//
// Por que existe: em 12/08/2026 o dono reexecutou o lote depois de a estimativa
// por tamanho ter entrado no repositório e recebeu a MESMA recusa antiga
// ("51 chamadas ≈ US$ 7,65") — porque o n8n roda o JSON que foi IMPORTADO, e o
// merge no `main` não reimporta nada. Da tela, código novo e código velho têm a
// mesma aparência: os dois recusam. Com a versão na mensagem, "o n8n está com o
// workflow velho" deixa de ser hipótese e vira leitura.
export const VERSAO_ORCAMENTO = 'v3 (2026-08-13)';

// Custo estimado de UM documento, usado só para decidir se o lote cabe antes de
// existir qualquer medição.
//
// De onde saiu o número original (docs/CUSTO_OPENAI.md): ~1k tokens de entrada
// por página, documento típico de ~10 páginas + ~2,5k do prompt de sistema ≈
// 12,5k de entrada = US$ 0,031; saída de extração densa até MAX_OUTPUT_TOKENS/2
// ≈ 8k = US$ 0,08. Soma ≈ US$ 0,11 — e ficou em 0,15 para o estimador errar para
// o lado SEGURO (barrar um lote que caberia é um aviso; deixar passar um que não
// cabe é o v31 de novo).
//
// RECALIBRADO DE 0,15 PARA 0,20 EM 07/08/2026, POR MEDIÇÃO. Este comentário
// pedia justamente isso ("é com ele que este número deve ser recalibrado"), e a
// medição chegou com o book-canastra: `n8n/medir-custo-book.mjs` mede o custo de
// cada documento a partir de páginas e linhas contadas no PDF gerado, e um dos
// 38 — o livro razão, 3 páginas e 461 linhas — deu **US$ 0,1725 por chamada**,
// ACIMA dos 0,15. Ou seja: existia documento realista que custava mais do que o
// número que sustenta o teto, e num lote só dele a promessa de "no máximo US$ 3
// por execução" seria quebrada em ~15%.
//
// O que 0,20 muda na prática: o lote máximo cai de 20 para 15 chamadas. É o
// preço de a recusa continuar acontecendo AQUI (com mensagem que diz o que
// fazer) e não na API (que só devolve 429 no meio do lote).
//
// O limite que 0,20 NÃO resolve, e que fica declarado: o estimador é PLANO — ele
// não sabe quantas páginas nem quantas linhas o documento tem. Acima de ~550
// linhas extraíveis o custo real volta a passar de 0,20. Enquanto for plano, a
// defesa dura continua sendo o teto de US$ 5 do projeto na OpenAI.
export const CUSTO_ESTIMADO_DOC_USD = 0.20;

// ---------------------------------------------------------------------------
// ESTIMATIVA POR TAMANHO — o que substitui o número plano quando os bytes são
// conhecidos, que é sempre que o arquivo veio pelo formulário.
// ---------------------------------------------------------------------------
//
// POR QUE ISTO EXISTE, com o número que o justifica. O estimador plano recusou
// um lote REAL de 35 documentos do book-canastra dizendo "≈ US$ 7,65, acima do
// teto de US$ 3". O mesmo book inteiro — 38 documentos, 57 chamadas — foi MEDIDO
// por `n8n/medir-custo-book.mjs` em **US$ 1,41**. O estimador errou por 5,4× e
// barrou um lote que cabia com folga de mais da metade do teto.
//
// Errar para o lado seguro é o projeto do estimador, e continua sendo. Errar por
// 5× é outra coisa: é impedir o uso do sistema para proteger um orçamento que
// nunca esteve em risco. E o custo disso não é teórico — foi o que travou o
// primeiro teste de ponta a ponta com o book difícil.
//
// A CALIBRAÇÃO, medida sobre os 38 documentos do book-canastra:
//
//   • custo agregado real: US$ 1,4117 para 257.150 bytes ponderados por chamada
//     (o documento mal nomeado paga o PDF duas vezes e conta duas vezes aqui)
//     = US$ 5,76 por MB;
//   • `CUSTO_POR_MB_USD` fica em **10,5**, ou seja 1,8× o agregado medido. A
//     margem cobre um lote quase duas vezes mais denso que o book — e o book já
//     é o material mais difícil que existe no repositório;
//   • `CUSTO_MINIMO_CHAMADA_USD` existe porque toda chamada paga o prompt de
//     sistema e pelo menos uma página de imagem, independente do tamanho do
//     arquivo. Sem ele, um lote de PDFs minúsculos estimaria quase zero.
//
// O QUE ESTA CALIBRAÇÃO ACERTA, e é o teste que importa: o book de 38 documentos
// estima ≈ US$ 2,5 (real 1,41) e PASSA; um lote de 35 cópias do documento mais
// denso do book — o livro razão, 461 linhas — estima ≈ US$ 3,7 e é RECUSADO,
// enquanto custaria US$ 6,04 de verdade. Ou seja: passa o caso realista e barra
// o caso caro, que é exatamente o que o teto existe para fazer e o que o número
// plano não conseguia fazer nos dois sentidos ao mesmo tempo.
//
// O LIMITE QUE FICA DECLARADO: bytes de PDF não são tokens. Um PDF de texto
// dá mais linhas por byte que um escaneado, e a razão entre os extremos medidos
// no book é de 4× por byte. A margem de 1,8× cobre a média de um lote, não o
// pior documento isolado — para isso continua valendo a defesa dura, o teto de
// US$ 5 do projeto na OpenAI. Um lote que estimasse exatamente no teto de US$ 3
// e fosse inteiro do tipo mais denso custaria ~US$ 4,8: cabe no teto duro.
export const CUSTO_POR_MB_USD = 10.5;
export const CUSTO_MINIMO_CHAMADA_USD = 0.012;

const BYTES_POR_MB = 1024 * 1024;

/**
 * Custo estimado de UMA chamada sobre um arquivo de `bytes`.
 * Devolve `null` quando o tamanho não é conhecido — quem chama decide o que
 * fazer com isso, e o que NÃO se pode fazer é tratar desconhecido como zero.
 */
export function custoEstimadoPorTamanho(bytes) {
  const b = Number(bytes);
  if (!Number.isFinite(b) || b <= 0) return null;
  return Math.max(CUSTO_MINIMO_CHAMADA_USD, (b / BYTES_POR_MB) * CUSTO_POR_MB_USD);
}

/**
 * Bytes de um binário do n8n, na ordem do mais confiável para o menos.
 *
 * O n8n guarda o binário de dois jeitos e o formato do metadado muda com o modo:
 * em memória, `data` é base64 (e o tamanho real sai dele); em modo filesystem,
 * `data` é um ponteiro e só resta `fileSize`, que vem FORMATADO ("10.79 kB").
 * Ler só um dos dois funciona no ambiente de quem escreveu e falha no outro.
 */
export function bytesDoBinario(bin) {
  if (!bin) return null;
  if (Number.isFinite(Number(bin.fileSize))) return Number(bin.fileSize);
  if (typeof bin.data === 'string' && !bin.id) {
    // base64 → bytes, sem alocar o buffer inteiro só para medir.
    const s = bin.data.length;
    const pad = bin.data.endsWith('==') ? 2 : bin.data.endsWith('=') ? 1 : 0;
    const n = Math.floor((s * 3) / 4) - pad;
    if (n > 0) return n;
  }
  if (typeof bin.fileSize === 'string') {
    const m = /^\s*([\d.,]+)\s*([kmg]?b)\s*$/i.exec(bin.fileSize);
    if (m) {
      const n = Number(m[1].replace(',', '.'));
      const mult = { b: 1, kb: 1024, mb: 1024 * 1024, gb: 1024 * 1024 * 1024 }[m[2].toLowerCase()];
      if (Number.isFinite(n) && mult) return Math.round(n * mult);
    }
  }
  return null;
}

// Custo REAL de uma chamada, a partir do bloco `usage` da resposta da OpenAI.
// Não estima nada: se o `usage` não vier, devolve null em vez de chutar — um
// custo inventado num relatório de custo é pior que um campo vazio.
export function custoDaChamada(usage, modelo) {
  const p = PRECO_USD_POR_MILHAO[modelo];
  if (!p || !usage) return null;
  const entradaTotal = Number(usage.prompt_tokens ?? usage.input_tokens ?? 0);
  const saida = Number(usage.completion_tokens ?? usage.output_tokens ?? 0);
  if (!Number.isFinite(entradaTotal) || !Number.isFinite(saida)) return null;
  // Tokens em cache custam metade (o prompt de sistema é o mesmo em toda
  // chamada, então o cache pega — ignorar isso superestimaria em ~40%).
  const cache = Number(usage.prompt_tokens_details?.cached_tokens ?? 0);
  const entradaCheia = Math.max(0, entradaTotal - cache);
  const usd =
    (entradaCheia * p.entrada + cache * p.entrada_cache + saida * p.saida) / 1_000_000;
  return Number(usd.toFixed(6));
}

// A decisão de orçamento do lote. Pura de propósito: é o que permite testá-la
// sem n8n e sem gastar um centavo.
//
// `chamadasPorDocumento` existe porque um documento mal nomeado paga o PDF DUAS
// vezes (classificação por conteúdo + extração — docs/CUSTO_OPENAI.md, medido no
// v31: 8 dos 14). O orçamento tem de contar o custo que o lote REALMENTE tem, não
// o do caso bem nomeado.
export function orcamentoDoLote({
  documentos,
  chamadasPorDocumento = 1,
  teto = TETO_EXECUCAO_USD,
  custoPorChamada = CUSTO_ESTIMADO_DOC_USD,
  bytes = null,
  pesoClassificacao = pesoDaChamadaDeClassificacao(),
}) {
  const n = Number(documentos) || 0;
  // Arredonda para CIMA: meia chamada não existe, e a metade que sobra é gasto.
  const chamadas = Math.ceil(n * Math.max(1, chamadasPorDocumento));

  // POR TAMANHO quando os bytes vieram; PLANO quando não vieram.
  //
  // `bytes` é o total do lote. A distinção não é cosmética: o número plano é o
  // que recusou um lote de US$ 1,41 dizendo US$ 7,65, e a estimativa por tamanho
  // é o que o corrige. Mas tamanho DESCONHECIDO não pode virar zero — isso
  // deixaria qualquer lote passar —, então a ausência cai no plano de propósito,
  // e a mensagem diz qual dos dois decidiu.
  const bytesTotais = Number(bytes);
  const porTamanho = Number.isFinite(bytesTotais) && bytesTotais > 0;

  // O FATOR DE CUSTO não é o número de chamadas: a segunda chamada de um
  // documento é a de CLASSIFICAÇÃO, e ela custa uma fração da extração (o
  // comentário de `pesoDaChamadaDeClassificacao` traz a medição). Contar
  // "2 chamadas = 2× o custo" é o que inflava a estimativa em 46% no lote real.
  //
  // E ELE SÓ VALE NO CAMINHO POR TAMANHO. A tentação é aplicar nos dois — o
  // desconto é o mesmo fato físico —, e é justamente onde ele não deve ir: o
  // caminho PLANO é o de "não sei nada sobre estes arquivos", e a única
  // calibração que ele tem é um incidente de dinheiro de verdade (o v31, 14
  // documentos reais que estouraram o teto de US$ 5 da OpenAI no meio do lote).
  // Descontar num caminho cego, com base numa proporção medida em PDFs
  // sintéticos de uma página, seria trocar a evidência cara pela barata. Quando
  // o tamanho é conhecido, a conta tem base própria e o desconto tem onde se
  // apoiar; quando não é, o guarda continua contando chamada cheia.
  const extrasPorDocumento = Math.max(0, Math.max(1, chamadasPorDocumento) - 1);
  const peso = Number.isFinite(Number(pesoClassificacao))
    ? Math.min(1, Math.max(0, Number(pesoClassificacao)))
    : 1;
  const fatorCusto = porTamanho ? 1 + extrasPorDocumento * peso : Math.max(1, chamadasPorDocumento);

  const estimadoUSD = porTamanho
    ? Number(Math.max(
        chamadas * CUSTO_MINIMO_CHAMADA_USD,
        (bytesTotais / BYTES_POR_MB) * CUSTO_POR_MB_USD * fatorCusto,
      ).toFixed(2))
    : Number((chamadas * custoPorChamada).toFixed(2));

  // Quantos documentos caberiam. Por tamanho, usa o tamanho MÉDIO deste lote —
  // é a única base honesta: dizer "no máximo 15" com base num documento típico
  // que não é o deste lote foi o que produziu a recusa errada.
  const custoMedioPorDoc = n > 0 ? estimadoUSD / n : custoPorChamada;
  const maxDocumentos = custoMedioPorDoc > 0
    ? Math.max(0, Math.floor(teto / custoMedioPorDoc))
    : n;
  const cabe = estimadoUSD <= teto;

  // A mensagem é metade do valor desta função: ela é o que o dono lê quando o
  // lote é recusado, e tem de dizer o que FAZER — não só que deu errado.
  const base = porTamanho
    ? `${(bytesTotais / 1024).toFixed(0)} KB de arquivo`
    : `estimativa plana de US$ ${custoPorChamada.toFixed(2)} por chamada (o tamanho dos arquivos não chegou até aqui)`;

  const mensagem = cabe
    ? null
    : `[orçamento ${VERSAO_ORCAMENTO}] ` +
      `Lote recusado ANTES de gastar: ${n} documento(s) = ${chamadas} chamada(s) à OpenAI ` +
      `≈ US$ ${estimadoUSD.toFixed(2)}, acima do teto de US$ ${teto.toFixed(2)} por execução. ` +
      `A conta saiu de ${base}. ` +
      `Envie no máximo ${maxDocumentos} documento(s) por vez (${Math.ceil(n / Math.max(1, maxDocumentos))} levas). ` +
      `Nada foi enviado à OpenAI e nada foi gravado, então reenviar não duplica nem custa. ` +
      `Se o lote precisa rodar inteiro, o teto vive em TETO_EXECUCAO_USD (n8n/lib/custo.mjs) ` +
      `— e subir ele exige subir também o teto do projeto na OpenAI, senão a API barra no meio.`;

  return {
    cabe, estimadoUSD, maxDocumentos, teto, chamadas, mensagem, porTamanho,
    versao: VERSAO_ORCAMENTO,
    fatorCusto: Number(fatorCusto.toFixed(4)),
  };
}
