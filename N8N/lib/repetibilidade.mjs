// A TRAVA DETERMINÍSTICA — repetibilidade, não correção.
//
// POR QUE ELA EXISTE AGORA. O provedor virou OpenAI `gpt-5.6-luna` (commit
// `bac2517`): a família GPT-5 RECUSA `temperature` (HTTP 400), então
// `montarCorpoIA` (lib/provedor.mjs) parou de mandar `temperature: 0` para todo
// modelo que não a aceita. Sem temperatura fixa, a extração numérica deixou de
// ser reproduzível — o MESMO documento pode devolver números DIFERENTES em duas
// rodadas. O schema estruturado (`extractionSchema`) segura a FORMA da
// resposta, nunca o VALOR: um JSON perfeitamente válido pode trazer "Caixa: 380"
// numa passada e "Caixa: 830" na outra, e nada no pipeline percebia.
//
// Pedido do dono, literal: "inclua uma avaliação determinística fora do LLM
// para acusar divergência e corrigir dentro do fluxo antes de entregar o
// resultado final da rodada".
//
// O QUE JÁ EXISTIA E NÃO FOI DUPLICADO AQUI (conferido antes de escrever
// qualquer coisa — `fn_conferir_arvore`, schema.sql:1294;
// `fn_reconciliar_ativo_passivo_pl`, migration 0105; `fn_reconciliar_por_
// documento`/`fn_conflitos_do_caso`). As três pegam extração INTERNAMENTE
// inconsistente (pai ≠ soma dos filhos; ativo ≠ passivo+PL; um documento
// contradizendo outro). NENHUMA delas pega o caso novo: uma extração
// internamente consistente, porém DIFERENTE da que o mesmo PDF deu da vez
// passada — que é exatamente o que a falta de `temperature` introduziu. Esta
// trava é ortogonal às três, não uma quarta camada em cima da mesma pergunta.
//
// O QUE ESTA TRAVA MEDE, E O QUE ELA NÃO MEDE (dito aqui para não virar
// alegação maior lida em outro lugar). Ela mede REPETIBILIDADE: duas extrações
// do MESMO documento bateram byte a byte nos números? Ela NÃO mede CORREÇÃO:
// duas extrações IDÊNTICAS e as DUAS erradas (o modelo lê "380" onde o PDF diz
// "830", sempre) passam por aqui sem uma única divergência. Determinismo não é
// verdade — é o mínimo necessário para que "rodou de novo e mudou" pare de ser
// uma pergunta sem resposta.
//
// AS DUAS FUNÇÕES ABAIXO SÃO AUTO-CONTIDAS DE PROPÓSITO: os nós Code do n8n não
// importam módulo — o gerador embute cada uma por `toString()`, que NÃO leva o
// escopo do módulo junto. Uma função que chamasse outra função ou lesse uma
// constante deste arquivo quebraria com `ReferenceError` DENTRO do nó na
// primeira execução real (aconteceu duas vezes nesta mesma sessão, com
// `capacidadesDoModelo` e `usoGemini` — nenhum teste que só chama a função
// isolada pega isso; só um teste que roda o CÓDIGO GERADO pega). Por isso cada
// função aqui carrega toda a lógica de que precisa, inclusive helpers
// aninhados, sem depender de nada fora da própria assinatura.

/**
 * Compara DUAS extrações do MESMO documento (a forma que `parseExtractionResponse`
 * — `lib/extract.mjs` — devolve em `.campos`) e devolve as divergências.
 *
 * CHAVE DE COMPARAÇÃO: seção + rótulo (`chave`) + `entidade_coluna` +
 * `periodo_coluna`. Duas linhas só são "a mesma linha" se as quatro baterem —
 * é a mesma chave que separa, por exemplo, "Caixa" da entidade A no período
 * 2024 de "Caixa" da entidade B no período 2024.
 *
 * TOLERÂNCIA ZERO PARA VALOR: a comparação de `valor_num` é por IDENTIDADE
 * ESTRITA (`===`), nunca por proximidade. Este sistema não arredonda número de
 * cliente — duas extrações do mesmo PDF ou dão o MESMO número ou divergiram.
 *
 * AUSÊNCIA NÃO É IGUALDADE (regra 1 do CLAUDE.md): `null` numa passada e `0` na
 * outra é DIVERGÊNCIA, não empate — por isso `valor_num` é normalizado para
 * `null` quando não é `number` e comparado por `===` depois, nunca por
 * `!valorA === !valorB` nem qualquer forma que trate as duas ausências como
 * iguais entre si.
 *
 * `maxDivergencias` limita quantas divergências detalhadas voltam (a MENSAGEM
 * fica ilegível com centenas) — as contagens (`linhasDivergentes`,
 * `linhasIguais`) são sempre completas, só a lista `divergencias` é truncada.
 */
// POR QUE ESTA FUNÇÃO É LONGA DE PROPÓSITO, e a decisão foi MEDIDA, não
// preguiça. O Sonar acusa complexidade cognitiva acima do teto de 15, e a saída
// óbvia — extrair `chaveDaLinha`/`descreverLinha`/`compararPar` para o escopo do
// módulo — foi ESCRITA E REVERTIDA em 11/09/2026, porque o teste
// "compararExtracoes é AUTO-CONTIDA" reprovou na hora.
//
// A auto-contenção não é preferência de estilo: é a fronteira do `toString()`.
// Os nós Code do n8n não importam módulo, e o gerador embute funções pelo
// `toString()`, que NÃO leva o escopo junto. Nesta mesma sessão isso quebrou
// DUAS vezes em produção potencial (`capacidadesDoModelo` e `usoGemini`, as duas
// com `ReferenceError` DENTRO do nó, ou seja: a chamada de IA simplesmente não
// sairia). Uma função auto-contida atravessa com um `toString()` e zero fiação
// extra; uma partida em quatro exige que quem for ligá-la ao grafo lembre de
// embutir as quatro — e "lembrar" é exatamente o que falhou duas vezes hoje.
//
// Entre uma restrição ARQUITETURAL que um teste comprova e uma heurística de
// linter que não conhece essa restrição, manda a primeira. O que a legibilidade
// ganha em troca são as auxiliares nomeadas aqui dentro e este comentário.
export function compararExtracoes(camposA, camposB, { maxDivergencias = 20 } = {}) {
  const listaA = Array.isArray(camposA) ? camposA : [];
  const listaB = Array.isArray(camposB) ? camposB : [];

  // A CHAVE, como string — JSON.stringify de um array preserva a posição de
  // cada campo (não colide "seção nula, rótulo X" com "seção X, rótulo nula").
  const chaveDe = (l) => JSON.stringify([
    l?.secao ?? null,
    l?.chave ?? null,
    l?.entidade_coluna ?? null,
    l?.periodo_coluna ?? null,
  ]);

  // A DESCRIÇÃO de uma linha para a MENSAGEM — os dois lados (a passada 1 e a
  // passada 2) precisam do bastante para um humano decidir sem reabrir o PDF.
  const descreverLinha = (l) => ({
    chave: l?.chave ?? null,
    secao: l?.secao ?? null,
    entidade_coluna: l?.entidade_coluna ?? null,
    periodo_coluna: l?.periodo_coluna ?? null,
    valor_num: typeof l?.valor_num === 'number' ? l.valor_num : null,
    valor_texto: l?.valor_texto ?? null,
    unidade: l?.unidade ?? null,
    moeda: l?.moeda ?? null,
  });

  const porChaveA = new Map();
  for (const l of listaA) {
    const k = chaveDe(l);
    if (!porChaveA.has(k)) porChaveA.set(k, []);
    porChaveA.get(k).push(l);
  }
  const porChaveB = new Map();
  for (const l of listaB) {
    const k = chaveDe(l);
    if (!porChaveB.has(k)) porChaveB.set(k, []);
    porChaveB.get(k).push(l);
  }
  const todasChaves = new Set([...porChaveA.keys(), ...porChaveB.keys()]);

  let linhasIguais = 0;
  let linhasDivergentes = 0;
  const divergencias = [];

  for (const k of todasChaves) {
    const linhasA = porChaveA.get(k) || [];
    const linhasB = porChaveB.get(k) || [];
    // Chave repetida NA MESMA extração (ex.: livro-razão com o mesmo histórico
    // mais de uma vez) casa por ORDEM de aparição — não é o caso comum (a
    // chave já inclui seção+coluna+período), mas perder a linha é pior que
    // casar pela posição.
    const n = Math.max(linhasA.length, linhasB.length);
    for (let i = 0; i < n; i += 1) {
      const a = linhasA[i];
      const b = linhasB[i];
      let divergencia = null;
      if (a === undefined) {
        divergencia = { tipo: 'ausente_na_primeira_passada', a: null, b: descreverLinha(b) };
      } else if (b === undefined) {
        divergencia = { tipo: 'ausente_na_segunda_passada', a: descreverLinha(a), b: null };
      } else {
        const valorA = typeof a.valor_num === 'number' ? a.valor_num : null;
        const valorB = typeof b.valor_num === 'number' ? b.valor_num : null;
        const unidadeA = a.unidade ?? null;
        const unidadeB = b.unidade ?? null;
        const moedaA = a.moeda ?? null;
        const moedaB = b.moeda ?? null;
        const camposDivergentes = [];
        // ESTRITO: null !== 0, 'BRL' !== 'USD', 1000 !== 1000.01 — tolerância
        // zero, e ausência não é empate (regra 1).
        if (valorA !== valorB) camposDivergentes.push('valor_num');
        if (unidadeA !== unidadeB) camposDivergentes.push('unidade');
        if (moedaA !== moedaB) camposDivergentes.push('moeda');
        if (camposDivergentes.length > 0) {
          divergencia = {
            tipo: 'valor_diferente', campos: camposDivergentes,
            a: descreverLinha(a), b: descreverLinha(b),
          };
        }
      }
      if (divergencia) {
        linhasDivergentes += 1;
        if (divergencias.length < maxDivergencias) divergencias.push({ chave: k, ...divergencia });
      } else {
        linhasIguais += 1;
      }
    }
  }

  return {
    chavesComparadas: todasChaves.size,
    linhasComparadas: linhasIguais + linhasDivergentes,
    linhasIguais,
    linhasDivergentes,
    divergencias,
    divergenciasTruncadas: linhasDivergentes > divergencias.length,
  };
}

/**
 * A mensagem humana a partir do resultado de `compararExtracoes` — separada da
 * comparação em si para poder mudar o TEXTO sem mudar a MEDIÇÃO (regra 3 do
 * CLAUDE.md: o invariante afirma comportamento, o texto é só a superfície).
 *
 * Zero divergência ainda produz uma frase (regra 7: estágio que não rodou tem a
 * mesma aparência de estágio que rodou e não achou nada — o silêncio não pode
 * ser a única prova de que a amostra foi conferida).
 */
export function mensagemRepetibilidade(resultado) {
  const r = resultado || {};
  const divergentes = Number(r.linhasDivergentes) || 0;
  const iguais = Number(r.linhasIguais) || 0;
  const total = divergentes + iguais;
  if (divergentes === 0) {
    return `[repetibilidade] Amostra conferida: ${iguais} de ${total} linha(s) bateram `
      + 'IDENTICAMENTE entre as duas extrações do mesmo documento (tolerância zero). '
      + 'Nenhuma divergência.';
  }
  const divergencias = Array.isArray(r.divergencias) ? r.divergencias : [];
  const exemplos = divergencias.slice(0, 5).map((d) => {
    const chaveLegivel = (d.a && d.a.chave) || (d.b && d.b.chave) || '(sem rótulo)';
    const doLado = (lado) => {
      if (!lado) return '(ausente)';
      if (lado.valor_num !== null) return String(lado.valor_num);
      if (lado.valor_texto !== null) return JSON.stringify(lado.valor_texto);
      return '(sem valor)';
    };
    return `"${chaveLegivel}": ${doLado(d.a)} vs ${doLado(d.b)}`;
  }).join(' | ');
  return `[repetibilidade] DIVERGÊNCIA: o mesmo documento extraiu números DIFERENTES em duas `
    + `passadas (${divergentes} de ${total} linha(s) não bateram, tolerância zero). O book NÃO `
    + 'pode ser entregue sem um humano olhar estas linhas antes do fechamento. '
    + `Exemplos: ${exemplos}${r.divergenciasTruncadas ? ' (lista truncada)' : ''}.`;
}

/**
 * A decisão de amostra: este documento entra na segunda passada?
 *
 * RESTRITA A DOCUMENTO LIDO EM BLOCO ÚNICO (`blocos === 1`) NESTA RODADA. Um
 * documento FATIADO (`Fatiar Extracao`, N8N/build-workflow.mjs) manda N
 * chamadas que juntas formam UM resultado (`Juntar Blocos`); comparar duas
 * extrações fatiadas exigiria alinhar bloco a bloco entre as duas passadas —
 * e o próprio fatiamento pode sair diferente entre elas se a extração de texto
 * variar. Essa complexidade fica declarada como lacuna (ver o cabeçalho deste
 * arquivo) em vez de construída sem necessidade agora — os documentos GRANDES
 * (multi-bloco) são, ironicamente, os mais prováveis de inconsistência entre
 * passadas, e ficam de fora desta primeira rodada da trava.
 *
 * DETERMINÍSTICA POR HASH, não por `Math.random()`: o MESMO documento (mesmo
 * SHA-256, `hash` — calculado em `Preparar Conteudo`, é o mesmo usado pela
 * dedup da migration 0026) toma a MESMA decisão em toda rodada, sem precisar
 * coordenar entre nós do grafo qual "posição" ele ocupa no lote — a decisão só
 * olha o PRÓPRIO documento, nunca o lote inteiro.
 *
 * `fracaoAmostra` é passada pelo chamador (nunca lida de constante de módulo —
 * ver a nota de auto-contenção no topo do arquivo); 0 (ou ausente) nunca
 * amostra nada, o padrão seguro caso alguém esqueça de passá-la.
 */
export function documentoAmostradoParaRepetibilidade({ hash, blocos, fracaoAmostra = 0 } = {}) {
  if (Number(blocos) !== 1) return false;
  if (typeof hash !== 'string' || hash.length < 8) return false;
  const fracao = Math.max(0, Math.min(1, Number(fracaoAmostra) || 0));
  if (fracao <= 0) return false;
  const n = Number.parseInt(hash.slice(0, 8), 16);
  if (!Number.isFinite(n)) return false;
  // Escala em 2**32 (não 0xffffffff): com `fracaoAmostra: 1` o maior `n`
  // possível (0xffffffff) tem de CABER como "amostrado" — contra 0xffffffff a
  // igualdade excluiria justamente o hash mais alto e "amostra tudo" deixaria
  // de ser literal.
  const limiar = Math.floor(fracao * 0x100000000);
  return n < limiar;
}

// A FRAÇÃO DA AMOSTRA — declarada aqui, com o porquê, para ficar num lugar só.
//
// FIXA EM PROPORÇÃO, NÃO EM CONTAGEM ABSOLUTA por lote: uma contagem fixa (ex.:
// "sempre 3 por lote") exigiria que TODOS os nós que decidem amostra (o
// `Orcamento do Lote`, para o efeito na cota, e o `Fatiar Extracao`, para de
// fato repetir a chamada) vissem o MESMO conjunto de documentos do lote para
// escolher os MESMOS 3 — uma coordenação a mais entre dois nós que hoje não
// precisam se falar. Uma FRAÇÃO por documento, decidida sozinha por
// `documentoAmostradoParaRepetibilidade` (hash do próprio documento, sem olhar
// o lote), dá o mesmo veredito nos dois nós sem coordenação nenhuma.
//
// 2% (1 em 50) FOI ESCOLHIDO PELO EFEITO NA COTA DO DIA (RPD 500,
// `lib/custo.mjs`), não por instinto. Extrair CADA documento duas vezes
// dobraria o custo e a cota; extrair zero não mede nada. Nos dois lotes já
// medidos neste repositório (`Arquitetura do Sistema`/ESTADO.md):
//
//   Araucária  190 documentos, 440 chamadas = 88% do RPD → amostra de ~2%
//              dos documentos de BLOCO ÚNICO acrescenta, no PIOR CASO (todos
//              de bloco único), ~4 chamadas → 444/500 = 88,8% — mudança
//              desprezível na fração que a cota já reporta.
//   Canastra    38 documentos,  63 chamadas = 13% do RPD → ~1 chamada extra
//              no pior caso → 64/500 = 12,8%.
//
// Cada documento amostrado custa NO MÁXIMO 1 chamada extra (a restrição a
// bloco único acima garante isso — nunca `blocos` chamadas a mais). Subir a
// fração é subir o custo E a cobertura da amostra; o número mora aqui para não
// ficar espalhado nos dois nós que o consultam.
export const FRACAO_AMOSTRA_REPETIBILIDADE = 0.02;

// Quantas divergências detalhadas a mensagem cita — mais que isso e a
// descrição de uma pendência vira ilegível. As CONTAGENS continuam completas.
export const MAX_DIVERGENCIAS_REPETIBILIDADE = 20;
