// A ESPERA DO LOTE — quanto tempo a tela acompanha, e quando ela declara parada.
//
// POR QUE ISTO É UM ARQUIVO, E NÃO O TOPO DO `upload-form.tsx`. As quatro contas
// abaixo decidem, sozinhas, se o analista vê "está andando" ou "parou" — e
// enquanto viviam dentro do componente ninguém conseguia CHAMÁ-LAS num teste. O
// que o `N8N/test/workflow-sim.test.mjs` fazia era ler as constantes do fonte e
// refazer a conta do lado dele: espelho sem guarda, o defeito que este
// repositório já nomeou três vezes — a fórmula muda aqui, o espelho não muda, e
// o teste continua verde provando a conta ERRADA. Agora a suíte chama a mesma
// função que a tela chama.

// Intervalo e teto do acompanhamento silencioso pós-envio — nem todo mandato
// termina rápido (documentos grandes/em lote levam minutos); depois do teto,
// para de perguntar sozinho sem assustar ninguém (o mandato sempre pode ser
// conferido manualmente).
export const INTERVALO_ACOMPANHAMENTO_MS = 8000;

// QUANTO ESPERAR — calculado a partir do LOTE, não fixo.
//
// O teto era fixo em 90 tentativas (~12 minutos), e isso funcionou enquanto o
// orçamento recusava lote grande: 14 documentos terminam em minutos e cabiam.
// Com a estimativa por tamanho, 38 documentos passam a rodar de uma vez. Com o
// teto fixo, a tela desistiria no meio de um trabalho que ainda está vivo e
// voltaria a mostrar "assim que estiver pronto, avisamos" para sempre —
// exatamente o defeito que a 0108 corrigiu, agora com o processo VIVO em vez de
// morto.
//
// ---------------------------------------------------------------------------
// O NÚMERO ERA 45s, E ELE MENTIU NA TROCA DE PROVEDOR (24/08/2026)
// ---------------------------------------------------------------------------
//
// 45s vinha dos ~33s da cadência do gpt-4o no Tier 1, onde `max_tokens` é
// RESERVA de TPM e cada extração reservava 16.384 tokens do minuto. Com o
// Gemini o gargalo deixou de ser o balde de tokens e passou a ser o de
// CHAMADAS: o intervalo caiu para 8s nos dois nós.
//
// O efeito na tela foi dizer **29 minutos** para um lote de 38 documentos que
// leva ~8. Não quebrou nada — e é justamente por isso que era o tipo de defeito
// que sobrevive: a estimativa não tem quem a desminta, e o analista fica
// esperando um trabalho que já acabou, ou desiste de acompanhar.
//
// A conta agora é declarada: ~44 extrações (38 documentos, 4 deles fatiados) +
// ~19 classificações por conteúdo, a 8s cada, dá 63 × 8 ÷ 38 ≈ 13s por
// documento. 14 cobre o upload e o banco. `N8N/test/workflow-sim.test.mjs`
// confere este número contra o `batchInterval` REAL do workflow gerado — se a
// cadência mudar de novo e este espelho não, a suíte reprova.
// RECALIBRADO CONTRA DUAS RODADAS REAIS de 38 documentos, e não contra a conta
// teórica: a v47 levou 9min01 (14,2s/doc) e a v48 levou 10min08 (16,0s/doc). O
// 14 vinha da aritmética das chamadas e ficava ABAIXO do observado — e errar
// para baixo é o defeito que a nota acima descreve, só que invertido: promete
// cedo e o analista lê o atraso como travamento. 16 era o pior caso medido.
//
// 11/09/2026 — A TROCA DE PROVEDOR MULTIPLICOU ISTO POR QUATRO, e o número
// antigo virou mentira no mesmo instante. A cadência da extração não é escolha:
// é `60s ÷ (TPM ÷ teto de saída)`, porque o teto de saída RESERVA balde de TPM
// (ver o adendo do v30 em CUSTO_IA.md). Com o Gemini eram 250.000 TPM e a
// extração saía a cada 8s; com a OpenAI no PISO de tier declarado (30.000 TPM)
// e o mesmo teto de 16.384, a PRIMEIRA versão desta conta (mesmo dia) saía a
// cada 32,768s.
//
// 11/09/2026, MESMO DIA — ESSA PRIMEIRA VERSÃO TAMBÉM MENTIA, e uma revisão
// adversarial achou o porquê: `60s ÷ (TPM ÷ teto de saída)` só reserva a
// SAÍDA. A OpenAI reserva TPM pelo MAIOR entre `max_tokens` e o tamanho real
// da requisição — e um PDF de 20 páginas (o maior já medido,
// `PAGINAS_MAX_MEDIDO` em `N8N/lib/custo.mjs`) manda ~20.000 tokens de
// ENTRADA, que a conta antiga ignorava por inteiro. Com a entrada somada:
// `30.000 ÷ (20.000 + 16.384) ≈ 0,825 chamada/min` → **~73s** por chamada
// (arredondado para cima ao segundo cheio — `build-workflow.mjs`,
// `arredondarParaSegundoCheio`). É mais que o dobro dos 32,768s da primeira
// correção, e é o número que de fato não estoura o balde: a versão anterior
// deixava um PDF grande sozinho, numa única chamada, acima do TPM — nenhum
// espaçamento entre chamadas evita isso.
//
// 73 é o teto arredondado para cima dessa cadência, e NÃO é uma estimativa de
// quanto um documento demora em média — é o piso do que UMA chamada custa. O
// teste `workflow-sim.test.mjs` exige exatamente isto: que a tela nunca prometa
// menos do que uma única chamada já leva.
//
// O QUE MUDA ESTE NÚMERO DE VOLTA: o TPM da conta, ou o pior caso de páginas
// medido. Os dois estão declarados no PISO (`PROVEDORES.openai.tpm` em
// `N8N/lib/provedor.mjs`; `PAGINAS_MAX_MEDIDO` em `N8N/lib/custo.mjs`) pela
// mesma doutrina de sempre — errar para o lento atrasa, errar para o rápido FAZ
// FALHAR. Numa conta de tier mais alto, sobe-se o TPM, regera-se o workflow e
// este cai junto; a suíte reprova se um subir sem o outro.
//
// 14/09/2026 — SUBIU, E É EXATAMENTE ISSO QUE ACONTECEU. O dono mediu o lote
// real da AMO (44 documentos) em 1h28 com o TPM no piso do Tier 1 (30.000) e
// confirmou a conta real: 500.000. `30.000 ÷ (20.000+16.384) ≈ 0,825
// chamada/min` virou `500.000 ÷ 36.384 ≈ 13,74 chamada/min` — abaixo do
// PISO HISTÓRICO de batching (`PISO_BATCHING_MS`, `N8N/lib/extract.mjs`, 6s,
// medido no "teste v18"), que passou a ser quem decide o intervalo. **73 não
// é mais o número: é 6.** Não é o balde de TPM que aperta agora — é a folga
// mínima contra a rede, e é por isso que subir o TPM não fez este número ir a
// zero.
export const SEGUNDOS_POR_DOCUMENTO = 6;

// A ESTIMATIVA É UMA FUNÇÃO SÓ, e isso não é preciosismo. Ela aparece em DOIS
// lugares — antes de enviar (para decidir se espera) e depois (para acompanhar)
// — e duas contas iguais escritas em dois lugares é exatamente como este
// repositório descreve seus piores defeitos: uma muda, a outra não, e a tela
// passa a se contradizer sem ninguém notar.
export function estimativaEmMinutos(arquivos: number): number {
  return Math.max(1, Math.round((arquivos * SEGUNDOS_POR_DOCUMENTO) / 60));
}

// A MARGEM DA JANELA É SEPARADA DA ESTIMATIVA, e a separação é a lição.
//
// Os dois números vinham do mesmo lugar, com 50% de folga — então encurtar a
// estimativa encurtaria a janela junto, e uma janela curta é o defeito da 0108
// de volta: a tela desiste de um lote que ainda está rodando. Errar para o lado
// de mostrar "quase pronto" por mais tempo não custa nada; errar para o lado de
// parar de perguntar custa o acompanhamento inteiro.
const MARGEM_DA_JANELA = 3;

// QUANTO TEMPO SEM ANDAR É "PAROU".
//
// A 0108 deu ao erro um lugar para morar, e cobre duas fontes: a recusa do
// orçamento e o Error Workflow do n8n. Sobra um caso, e ele é o mais teimoso: o
// Error Workflow é um passo MANUAL de configuração, e um nó que morre com esse
// registro desligado não escreve linha nenhuma. A tela volta a deduzir "está
// processando" de uma ausência que na verdade é morte.
//
// A saída é não depender de ninguém registrar nada. Se o número de arquivos
// organizados PAROU DE SUBIR por tempo demais, o trabalho não está andando —
// isso é medível daqui, sem banco e sem n8n.
//
// O NÚMERO SAI DA CADÊNCIA, não do gosto: um documento leva ~14s, então 5
// minutos são ~20 documentos que deveriam ter aparecido e não apareceram. Curto
// demais acusa parada no meio de um documento grande (que faz várias leituras
// antes de registrar qualquer coisa); longo demais devolve a espera eterna que
// isto existe para acabar.
//
// ---------------------------------------------------------------------------
// O 5 FIXO DECLAROU MORTO UM LOTE VIVO — MEDIDO EM 27/08/2026, NOS 190
// ---------------------------------------------------------------------------
//
// A correção do silêncio INICIAL (`semPrimeiroSinalMs`, logo abaixo) foi feita
// pela metade: o limite da primeira fase passou a sair do tamanho do lote, e o
// do MEIO ficou com o número calibrado em 38 documentos. A rodada do
// `book-araucaria` mostrou que o silêncio do meio tem exatamente a mesma forma
// — e a mesma causa.
//
// Cronometrado no banco:
//   20:55:12  os 190 documentos registrados, TODOS no mesmo instante
//   21:24     as 13.942 linhas gravadas, TODAS no mesmo minuto
//   → 28min48 sem UMA escrita, contra um limite de 5 minutos.
//
// A causa é estrutural e não é lentidão: nó do n8n NÃO É STREAMING. Ele
// processa todos os itens antes de passar adiante. Entre a barreira do
// `Juntar Ramos` (que registra os documentos) e a do `Juntar Extraidos` (que
// grava as linhas) corre o `IA Extrair` inteiro — `batchSize: 1`,
// `batchInterval: 8000ms`, 190 itens = **25min20s** em que, por construção,
// nada é escrito no banco.
//
// Aos 21:00 o portal declarou "o sistema parou por um problema técnico" sobre
// um lote que estava rodando, e o analista quase reenviou 190 arquivos —
// pagando a IA duas vezes.
//
// A CONTA É A MESMA DA PRIMEIRA FASE, e isso não é economia de código: as duas
// esperas são o MESMO fenômeno (uma barreira segurando todos os itens até a
// última chamada de IA voltar), então dar-lhes contas diferentes seria afirmar
// uma diferença que não existe. `SEM_PROGRESSO_MINIMO_MS` preserva o 5 antigo
// como piso, para o lote pequeno não perder nada.
// A CADÊNCIA DA IA E O PREPARO POR ARQUIVO — as duas contas de espera saem
// daqui, e é por isso que eles moram acima das duas.
//   CADENCIA_IA_S ......... o `batchInterval` real do nó `IA Classificar`
//                           (6s). `workflow-sim.test.mjs` confere este
//                           espelho contra o workflow gerado.
//                           ATENÇÃO: é a cadência da CLASSIFICAÇÃO, não a da
//                           extração — as duas podem DIVERGIR, e por um tempo
//                           divergiram (classificação 42s, extração 73s, com o
//                           TPM no piso de Tier 1). 14/09/2026: o dono
//                           confirmou o TPM real da conta (500.000, era
//                           30.000), e nesse regime as DUAS cadências caem
//                           abaixo do PISO HISTÓRICO de batching
//                           (`PISO_BATCHING_MS`, 6s) — que passa a decidir as
//                           duas, e elas voltam a CONVERGIR (como na era
//                           Gemini, quando as duas eram 8s). Isso pode
//                           divergir de novo se o TPM mudar sem passar pelo
//                           piso — ver `build-workflow.mjs`,
//                           `INTERVALO_CLASSIFICACAO_MS` e
//                           `INTERVALO_EXTRACAO_MS`. Quem usa esta constante
//                           está medindo o silêncio até o primeiro sinal, que é
//                           governado pela barreira do merge das
//                           CLASSIFICAÇÕES — por isso é a dela que vale aqui, e
//                           é por isso que ela não pode ser reaproveitada para
//                           estimar a rodada inteira.
//   PREPARO_POR_ARQUIVO_S . upload ao Storage, leitura do texto e medição. Saiu
//                           da diferença entre a duração real das rodadas
//                           v47/v48 e o que a cadência sozinha explica.
const CADENCIA_IA_S = 6;
const PREPARO_POR_ARQUIVO_S = 5;

const SEM_PROGRESSO_MINIMO_MS = 5 * 60 * 1000;
export function semProgressoMs(arquivos: number): number {
  const n = Math.max(0, Number(arquivos) || 0);
  return Math.max(SEM_PROGRESSO_MINIMO_MS, n * (CADENCIA_IA_S + PREPARO_POR_ARQUIVO_S) * 1000);
}

// ANTES DO PRIMEIRO SINAL A FOLGA É MAIOR, e a assimetria é medida, não
// cautela genérica: entre o envio e o primeiro documento registrado o sistema lê
// o texto de TODOS os arquivos e decide o orçamento do lote — nada disso produz
// contagem. Num lote de 38 esse silêncio inicial é legítimo e dura minutos.
//
// O 8 FIXO ERA CALIBRAÇÃO DE UM LOTE DE 38, E ELE NÃO SOBREVIVE A UM LOTE DE
// 190 — medido no workflow, não estimado. A cadeia até o primeiro
// `Registrar Documento` é: `Preparar Conteudo` → `Upload Storage` (uma
// requisição por arquivo) → `Extrair Texto` → `Medir Documento` →
// `Orcamento do Lote` → `IA Classificar` → **`Juntar Ramos`**. O merge é uma
// BARREIRA: nenhum documento é registrado enquanto a última chamada de
// classificação não voltar, e essa chamada sai a uma por
// `CADENCIA_IA_S` (o `batchInterval` do nó). Num lote em que metade dos nomes
// não resolve tipo+período — a proporção medida no `book-canastra`, 19 de 38 —
// isso dá 19 × 8s ≈ 2,5 min para 38 arquivos e ~13 min para 190. Com o limite
// fixo de 8 minutos, a tela declararia "o processamento parou" sobre um lote
// perfeitamente vivo, e o analista reenviaria um lote que já está rodando.
//
// Então o limite passa a sair da MESMA conta que o silêncio: o pior caso é todo
// arquivo precisar da classificação por conteúdo. `PREPARO_POR_ARQUIVO_S` cobre
// o resto da fase (upload ao Storage, leitura do texto, medição) e sai da
// diferença entre a duração real das rodadas v47/v48 (9min01 e 10min08 para 38
// documentos) e o que a cadência sozinha explica (~44 extrações + 19
// classificações a 8s ≈ 8,4 min): sobram ~1,5 min para 38 arquivos, ~2,4s cada,
// e 5 é a margem. A conta reproduz o 8 antigo no lote em que ele foi calibrado
// (38 × 13s = 8,2 min), que é o sinal de que ela descreve o mesmo fenômeno.
const SEM_PRIMEIRO_SINAL_MINIMO_MS = 8 * 60 * 1000;
export function semPrimeiroSinalMs(arquivos: number): number {
  const n = Math.max(0, Number(arquivos) || 0);
  return Math.max(SEM_PRIMEIRO_SINAL_MINIMO_MS, n * (CADENCIA_IA_S + PREPARO_POR_ARQUIVO_S) * 1000);
}

const ESPERA_MINIMA_MS = 12 * 60 * 1000;
// O TETO DA JANELA SUBIU DE 90 PARA 160 MINUTOS, e o número vem do custo, não
// do conforto. Ele existia para limitar consulta ao Supabase, e foi escrito
// quando a cadência era fixa em 8s: 90 min davam ~675 consultas. A
// desaceleração (ver abaixo) mudou a conta e ninguém remediu o teto — hoje 90
// min custam **193** consultas e 160 min custam **333**, ainda metade do que o
// teto antigo custava quando foi escrito.
//
// O que o 90 quebrava: a margem de 3× que o comentário do `MARGEM_DA_JANELA`
// promete só valia até 112 arquivos. Num lote de 190 (previsão de 51 min) o
// teto truncava a janela em 90 min — margem real de 1,77× —, e uma rodada que
// andasse a 28s por documento em vez dos 16 medidos veria a tela desistir viva.
// Com 160 min a margem prometida valia até 200 arquivos.
//
// 11/09/2026 — O MESMO TETO QUEBROU DE NOVO, pela mesma razão e com o mesmo
// sintoma, porque `SEGUNDOS_POR_DOCUMENTO` dobrou de 16 para 33 com a troca de
// provedor. Num lote de 190 a previsão passou de 51 para 104 min, e 160 min de
// teto entregavam 1,53× da margem de 3× prometida — medido pelo
// `verificar-mensagem-de-falha.mts`, que reprovou. 320 min repunha a promessa
// nos 190 documentos com os 33s daquela versão (190 × 33s × 3 = 313,5 min).
//
// 11/09/2026, MESMO DIA — O TETO QUEBROU UMA TERCEIRA VEZ, na MESMA sessão: a
// correção da cadência (ver `SEGUNDOS_POR_DOCUMENTO` acima — a conta de 33s
// ignorava os tokens de ENTRADA) subiu o número para 73s, e 320 min deixaram
// de cobrir 190 × 73s × 3 = 693,5 min. 700 min repõe a margem de 3× com folga
// (190 × 73s × 3 ÷ 60 ≈ 693,5 min < 700).
//
// E VALE DIZER O QUE ESTE NÚMERO É: ele não é uma escolha de produto, é uma
// CONSEQUÊNCIA de a cadência da extração ser ~73s. Ele encolhe sozinho no dia
// em que o TPM declarado do provedor subir para o valor real da conta — e a
// única razão de ele estar tão alto é o TPM estar no piso conservador do tier 1.
const ESPERA_MAXIMA_MS = 700 * 60 * 1000;
export function janelaPara(arquivos: number): number {
  const previsto = arquivos * SEGUNDOS_POR_DOCUMENTO * 1000 * MARGEM_DA_JANELA;
  return Math.min(ESPERA_MAXIMA_MS, Math.max(ESPERA_MINIMA_MS, previsto));
}

// A CADÊNCIA DESACELERA, A JANELA NÃO MUDA.
//
// Perguntar de 8 em 8 segundos durante até 90 minutos são ~675 consultas por
// lote, cada uma custando um RPC mais duas leituras no Supabase. O egresso é da
// ORGANIZAÇÃO, dividido com o clipping, e no plano Free estourar derruba os dois
// projetos juntos — então cadência de tela é custo, não detalhe.
//
// Mas desacelerar tudo pioraria a tela onde ela mais importa: lote de 1 ou 2
// documentos termina em menos de dois minutos, com o analista olhando. Por isso
// a cadência só afrouxa DEPOIS desses dois minutos — quando o lote é grande, a
// espera é de dezenas de minutos e ninguém está mais na frente da tela. Lote
// pequeno não percebe diferença nenhuma; lote grande custa ~3x menos.
//
// A JANELA TOTAL é preservada de propósito: ela foi dimensionada no lote real de
// 38 documentos (~23 min de extração), e encurtá-la traria de volta o defeito que
// a 0108 corrigiu — a tela desistindo no minuto 12 de um trabalho vivo. Por isso
// o laço passa a ser guiado por PRAZO decorrido, e não por contagem de
// tentativas: com intervalo variável, contar tentativas deixa de descrever tempo.
const CADENCIA_RAPIDA_ATE_MS = 2 * 60 * 1000;
const INTERVALO_MAXIMO_MS = 30000;
const FATOR_DESACELERACAO = 1.5;
export function proximoIntervalo(intervaloAtual: number, decorridoMs: number): number {
  if (decorridoMs < CADENCIA_RAPIDA_ATE_MS) return INTERVALO_ACOMPANHAMENTO_MS;
  return Math.min(INTERVALO_MAXIMO_MS, Math.round(intervaloAtual * FATOR_DESACELERACAO));
}

// ---------------------------------------------------------------------------
// O VEREDITO DO LOTE — "terminou" não é "terminou bem"
// ---------------------------------------------------------------------------
//
// ACHADO COM O DONO NA TELA, 27/08/2026: a execução morreu no primeiro nó
// (`Upload Storage`, habilitado por engano com credencial `REPLACE`) e o portal
// mostrou **"Tudo pronto"**. Nenhuma peça mentiu sozinha:
//
//   • o registro de falha depende do **Error Workflow** do n8n, que é passo
//     MANUAL de configuração e não está ligado (conferido no workflow vivo:
//     `settings` sem `errorWorkflow`) — nada foi escrito em `execucao_falha`;
//   • e os contadores foram satisfeitos assim mesmo, porque o nó que morreu é
//     ramo LATERAL: o irmão rodou inteiro e gravou documentos e eventos.
//
// Deduzir "terminou bem" de contadores é deduzir de um sintoma que a MORTE
// também produz. O sinal que não depende de configuração nenhuma é o fim do
// workflow: ele termina em `Gravar Uso do Lote` → `Conferir Lote`, e um lote que
// fecha deixa linha em `lote_execucao`. Medido: v47 e v48 deixaram; as duas
// execuções mortas do smoke test não deixaram nenhuma.
//
// A função é pura para poder ser CHAMADA por teste. A regra anterior morava
// dentro da rota, e uma decisão que ninguém consegue chamar é uma decisão que
// ninguém confere.
export type VereditoDoLote =
  | { estado: 'andando' }
  | { estado: 'pronto' }
  | { estado: 'nao_fechou' };

// Entre o último documento extraído e a linha de `lote_execucao` correm quatro
// nós (`Reconciliar (Classe A)` → `Reconciliar Lote` → `Resumo de Custo` →
// `Gravar Uso do Lote`). Sem carência, QUALQUER lote saudável acusaria falha na
// janela entre o último documento e o fechamento — o alarme falso que ensina a
// ignorar o alarme.
//
// O COMENTÁRIO ANTERIOR DIZIA "que levam segundos", E ISSO ERA VERDADE EM 38
// DOCUMENTOS. Na rodada de 190 o `Reconciliar` sozinho passou de UMA HORA sem
// terminar: as checagens do despachante leem (caso, entidade, período) e
// rodavam uma vez por DOCUMENTO — 190 execuções para 82 chaves. A `0152`
// corrigiu a causa, mas o número aqui continuava descrevendo o lote em que foi
// calibrado, que é o defeito que este arquivo inteiro documenta.
//
// Agora ele escala: a reconciliação por documento é O(documentos) e a do lote é
// O(chaves), e `chaves <= documentos`. Um segundo por documento é folga larga
// sobre o que a 0152 mede (a árvore por documento é uma consulta indexada), e o
// piso de 2 minutos preserva o comportamento em lote pequeno.
const CARENCIA_MINIMA_MS = 2 * 60 * 1000;
export function carenciaDoFechamentoMs(arquivos: number): number {
  const n = Math.max(0, Number(arquivos) || 0);
  return Math.max(CARENCIA_MINIMA_MS, n * 1000);
}

/** @deprecated use `carenciaDoFechamentoMs(arquivos)` — o fixo não sobrevive a 190. */
export const CARENCIA_DO_FECHAMENTO_MS = CARENCIA_MINIMA_MS;

export function vereditoDoLote({
  classificados, processados, esperados, loteFechou, desdeMs, agoraMs,
}: {
  classificados: number;
  processados: number;
  esperados: number;
  /** `null` = não deu para conferir. "Não sei" NUNCA acusa um lote vivo. */
  loteFechou: boolean | null;
  desdeMs: number;
  agoraMs: number;
}): VereditoDoLote {
  const contadoresCompletos = classificados >= esperados && processados >= esperados;
  if (!contadoresCompletos) return { estado: 'andando' };
  if (loteFechou !== false) return { estado: 'pronto' };

  const esperandoHa = Number.isFinite(desdeMs) ? agoraMs - desdeMs : 0;
  if (esperandoHa > carenciaDoFechamentoMs(esperados)) return { estado: 'nao_fechou' };
  return { estado: 'andando' };
}
