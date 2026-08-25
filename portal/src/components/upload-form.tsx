"use client";

import { useEffect, useRef, useState } from "react";
import { explicarFalha, explicarParada, explicarLoteVazio, type FalhaExplicada } from "@/lib/falha-em-portugues";
import { useRouter } from "next/navigation";

const MB = 1024 * 1024;
// Intervalo e teto do acompanhamento silencioso pós-envio — nem todo mandato
// termina rápido (documentos grandes/em lote levam minutos); depois do teto,
// para de perguntar sozinho sem assustar ninguém (o mandato sempre pode ser
// conferido manualmente).
const INTERVALO_ACOMPANHAMENTO_MS = 8000;

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
// documento. 14 cobre o upload e o banco. `n8n/test/workflow-sim.test.mjs`
// confere este número contra o `batchInterval` REAL do workflow gerado — se a
// cadência mudar de novo e este espelho não, a suíte reprova.
// RECALIBRADO CONTRA DUAS RODADAS REAIS de 38 documentos, e não contra a conta
// teórica: a v47 levou 9min01 (14,2s/doc) e a v48 levou 10min08 (16,0s/doc). O
// 14 vinha da aritmética das chamadas e ficava ABAIXO do observado — e errar
// para baixo é o defeito que a nota acima descreve, só que invertido: promete
// cedo e o analista lê o atraso como travamento. 16 é o pior caso medido.
const SEGUNDOS_POR_DOCUMENTO = 16;

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
const SEM_PROGRESSO_MS = 5 * 60 * 1000;

// ANTES DO PRIMEIRO SINAL A FOLGA É MAIOR, e a assimetria é medida, não
// cautela genérica: entre o envio e o primeiro documento registrado o sistema lê
// o texto de TODOS os arquivos e decide o orçamento do lote — nada disso produz
// contagem. Num lote de 38 esse silêncio inicial é legítimo e dura minutos.
const SEM_PRIMEIRO_SINAL_MS = 8 * 60 * 1000;
const ESPERA_MINIMA_MS = 12 * 60 * 1000;
const ESPERA_MAXIMA_MS = 90 * 60 * 1000;
function janelaPara(arquivos: number): number {
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
function proximoIntervalo(intervaloAtual: number, decorridoMs: number): number {
  if (decorridoMs < CADENCIA_RAPIDA_ATE_MS) return INTERVALO_ACOMPANHAMENTO_MS;
  return Math.min(INTERVALO_MAXIMO_MS, Math.round(intervaloAtual * FATOR_DESACELERACAO));
}

function formatarTamanho(bytes: number): string {
  if (bytes < MB) return `${Math.max(1, Math.round(bytes / 1024))} KB`;
  return `${(bytes / MB).toFixed(1)} MB`;
}

export default function UploadForm({
  mandatoInicial = "",
  travarMandato = false,
  casoId,
}: {
  mandatoInicial?: string;
  travarMandato?: boolean;
  casoId?: string;
}) {
  const router = useRouter();
  const inputRef = useRef<HTMLInputElement>(null);
  const [mandato, setMandato] = useState(mandatoInicial);
  const [arquivos, setArquivos] = useState<File[]>([]);
  const [arrastando, setArrastando] = useState(false);
  const [enviando, setEnviando] = useState(false);
  const [erro, setErro] = useState<string | null>(null);
  const [sucesso, setSucesso] = useState<{ mandato: string; arquivos: number; desde: string } | null>(null);
  const [pronto, setPronto] = useState(false);
  // A FALHA DO PROCESSAMENTO. Sem este estado, o "aguarde" era eterno: a tela
  // deduzia progresso da ausência de documentos, e falha produz exatamente a
  // mesma ausência.
  const [falha, setFalha] = useState<{ etapa: string; mensagem: string } | null>(null);
  // O PROGRESSO, que a rota já devolvia e esta tela ignorava. Numa espera de 20
  // minutos, "12 de 38 organizados" e "nada aconteceu" são a diferença entre
  // esperar tranquilo e achar que travou.
  const [progresso, setProgresso] = useState<{ processados: number; esperados: number } | null>(null);
  const [demorou, setDemorou] = useState(false);
  // A PARADA SEM REGISTRO — o caso que a 0108 não alcança (ver SEM_PROGRESSO_MS).
  const [parada, setParada] = useState<{ processados: number; esperados: number } | null>(null);
  // O LOTE QUE TERMINOU VAZIO. Vem do status, e só existe depois de `pronto`.
  const [loteVazio, setLoteVazio] = useState<{ comLinhas: number; documentos: number } | null>(null);

  // Acompanha silenciosamente, em segundo plano, até os arquivos enviados
  // estarem organizados — sem nomear nenhuma ferramenta ou etapa técnica.
  useEffect(() => {
    if (!sucesso || pronto || falha || parada) return;
    let cancelado = false;
    let intervalo = INTERVALO_ACOMPANHAMENTO_MS;
    let proximaEspera: ReturnType<typeof setTimeout> | undefined;
    const comecou = Date.now();
    const janela = janelaPara(sucesso.arquivos);
    // O RELÓGIO DA PARADA anda em paralelo ao da janela e mede outra coisa: a
    // janela pergunta "já esperei demais?", este pergunta "está andando?". Um
    // lote lento e vivo não pode acionar o segundo; um lote morto tem de acionar
    // antes de o primeiro estourar, senão a tela cala como sempre calou.
    let ultimoAvanco = Date.now();
    let ultimoVisto = -1;

    const verificar = async () => {
      if (cancelado) return;
      try {
        const params = new URLSearchParams({
          caso: sucesso.mandato,
          desde: sucesso.desde,
          esperados: String(sucesso.arquivos),
        });
        const resp = await fetch(`/api/intake/status?${params}`);
        const json = await resp.json().catch(() => ({}));
        // A falha ENCERRA o acompanhamento. Continuar perguntando depois dela
        // seria manter a espera de pé sobre um processo que não vai voltar.
        if (!cancelado && resp.ok && json.falha) {
          setFalha({ etapa: json.falha.etapa, mensagem: json.falha.mensagem });
          return;
        }
        if (!cancelado && resp.ok && typeof json.processados === "number") {
          setProgresso({ processados: json.processados, esperados: json.esperados });
          // AVANÇO é qualquer um dos dois contadores subindo. Só o de extração
          // deixaria a fase inicial inteira — upload, orçamento, registro dos
          // documentos — parecer parada, e ela pode durar minutos num lote grande.
          const marca = (json.classificados ?? 0) + json.processados;
          if (marca > ultimoVisto) {
            ultimoVisto = marca;
            ultimoAvanco = Date.now();
          }
        }
        if (!cancelado && resp.ok && json.pronto) {
          setPronto(true);
          // `comLinhas` só vem no fim, e `null` significa "não consegui conferir"
          // — que NÃO é zero. Tratar os dois igual acusaria lote vazio por causa
          // de uma consulta que falhou, e um alarme falso desses ensina a
          // ignorar o alarme.
          if (typeof json.comLinhas === "number") {
            setLoteVazio({ comLinhas: json.comLinhas, documentos: json.esperados });
          }
          if (casoId) router.refresh();
          return;
        }
        // PAROU DE ANDAR: declara, em vez de continuar perguntando com cara de
        // calma. O limite é maior enquanto nada apareceu ainda — nessa fase o
        // silêncio é legítimo.
        if (!cancelado && resp.ok) {
          const parado = Date.now() - ultimoAvanco;
          const limite = ultimoVisto > 0 ? SEM_PROGRESSO_MS : SEM_PRIMEIRO_SINAL_MS;
          if (parado > limite) {
            setParada({ processados: json.processados ?? 0, esperados: json.esperados ?? sucesso.arquivos });
            return;
          }
        }
      } catch {
        // Falha pontual de rede não interrompe o acompanhamento — só a
        // próxima tentativa (ou o teto de tentativas) decide quando parar.
      }
      const decorrido = Date.now() - comecou;
      if (!cancelado && decorrido < janela) {
        intervalo = proximoIntervalo(intervalo, decorrido);
        proximaEspera = setTimeout(verificar, intervalo);
      } else if (!cancelado) {
        // DESISTIR EM SILÊNCIO É O DEFEITO. Parar de perguntar é legítimo (a aba
        // pode ficar aberta o dia todo); fingir que ainda se está esperando, não.
        setDemorou(true);
      }
    };

    proximaEspera = setTimeout(verificar, intervalo);
    return () => {
      cancelado = true;
      // Limpa o timer AGENDADO, seja ele o primeiro ou um reagendamento: agora
      // que o intervalo varia, `proximaEspera` é sempre o único pendente.
      clearTimeout(proximaEspera);
    };
  }, [sucesso, pronto, falha, parada, casoId, router]);

  function adicionarArquivos(lista: FileList | null) {
    if (!lista) return;
    const novos = Array.from(lista);
    setArquivos((atuais) => {
      // dedup por nome+tamanho para evitar duplicar ao soltar duas vezes
      const chave = (f: File) => `${f.name}:${f.size}`;
      const vistos = new Set(atuais.map(chave));
      return [...atuais, ...novos.filter((f) => !vistos.has(chave(f)))];
    });
  }

  function removerArquivo(idx: number) {
    setArquivos((atuais) => atuais.filter((_, i) => i !== idx));
  }

  async function enviar(e: React.FormEvent) {
    e.preventDefault();
    setErro(null);
    if (!mandato.trim()) {
      setErro("Informe o nome do mandato.");
      return;
    }
    if (arquivos.length === 0) {
      setErro("Selecione ao menos um arquivo.");
      return;
    }
    setEnviando(true);
    try {
      const fd = new FormData();
      fd.append("mandato", mandato.trim());
      for (const a of arquivos) fd.append("arquivos", a, a.name);
      const resp = await fetch("/api/intake", { method: "POST", body: fd });
      const json = await resp.json().catch(() => ({}));
      if (!resp.ok) {
        setErro(json.error ?? `Falha no envio (HTTP ${resp.status}).`);
        return;
      }
      setPronto(false);
      setSucesso({
        mandato: json.mandato ?? mandato.trim(),
        arquivos: json.arquivos ?? arquivos.length,
        desde: json.desde ?? new Date().toISOString(),
      });
      setArquivos([]);
    } catch (err) {
      setErro((err as Error).message);
    } finally {
      setEnviando(false);
    }
  }

  // UM CARTÃO PARA AS TRÊS FORMAS DE NÃO TER DADO CERTO.
  //
  // Elas chegam por caminhos diferentes — falha registrada no banco, parada sem
  // registro nenhum, lote que terminou vazio — e para quem lê são a mesma
  // notícia: não terminou como devia, e isto é o que aconteceu. Três cartões
  // diferentes fariam o analista aprender três telas para uma informação só.
  //
  // A ORDEM DA LEITURA É A ORDEM DA PERGUNTA: o que aconteceu, o que fazer, e —
  // só se pedirem — o texto técnico. Ele continua ali porque sem ele quem for
  // ajudar começa perguntando "qual erro apareceu?"; mas fechado, porque quem
  // precisa dele não é quem está olhando a tela.
  const explicacao: FalhaExplicada | null = falha
    ? explicarFalha(falha)
    : parada
      ? explicarParada(parada)
      : loteVazio
        ? explicarLoteVazio(loteVazio)
        : null;

  if (sucesso && explicacao) {
    const tecnico = falha
      ? `${falha.etapa ? `Etapa: ${falha.etapa}\n` : ""}${falha.mensagem}`
      : parada
        ? `Sem progresso por mais de ${Math.round(SEM_PROGRESSO_MS / 60000)} minutos. `
          + `Organizados: ${parada.processados} de ${parada.esperados}. Mandato: "${sucesso.mandato}". `
          + `Envio: ${new Date(sucesso.desde).toLocaleString("pt-BR")}.`
        : `Lote concluído com ${loteVazio?.comLinhas ?? 0} de ${loteVazio?.documentos ?? 0} documentos `
          + `com linhas extraídas. Mandato: "${sucesso.mandato}". `
          + `Envio: ${new Date(sucesso.desde).toLocaleString("pt-BR")}.`;

    return (
      <div className="rounded border border-risco-300 bg-risco-50 p-4 text-sm text-risco-900">
        <p className="text-xs font-semibold uppercase tracking-wide text-risco-700">
          O sistema parou por um problema técnico
        </p>
        <p className="mt-2 text-base font-medium">{explicacao.titulo}</p>
        <p className="mt-2 text-risco-800">{explicacao.explicacao}</p>

        <div className="mt-3 rounded border border-risco-200 bg-folha p-3">
          <p className="text-xs font-semibold uppercase tracking-wide text-risco-700">
            {explicacao.quemResolve === "voce" ? "O que você pode fazer" : "Quem resolve isto"}
          </p>
          <p className="mt-1 text-risco-900">{explicacao.oQueFazer}</p>
        </div>

        {/* FECHADO POR PADRÃO, e presente por escolha. A causa técnica é o que
            um desenvolvedor precisa e o que some quando a interface "simplifica"
            demais — mas ela não é a primeira coisa que o analista deve ler. */}
        <details className="mt-3">
          <summary className="cursor-pointer text-xs text-risco-700 hover:text-risco-900">
            Ver detalhes técnicos (para enviar a quem cuida do sistema)
          </summary>
          <p className="mt-2 whitespace-pre-wrap rounded border border-risco-200 bg-folha p-3 text-xs text-tinta-600">
            {tecnico}
          </p>
        </details>

        <div className="mt-3 flex gap-3">
          <button
            type="button"
            onClick={() => { setFalha(null); setParada(null); setLoteVazio(null); setSucesso(null); }}
            className="rounded bg-risco-700 px-3 py-1.5 text-xs font-medium text-papel hover:bg-risco-800"
          >
            Enviar de novo
          </button>
          <button
            type="button"
            onClick={() => router.push(casoId ? `/casos/${casoId}` : "/casos")}
            className="rounded border border-risco-300 px-3 py-1.5 text-xs font-medium text-risco-800 hover:bg-risco-100"
          >
            {casoId ? "Voltar ao mandato →" : "Ver mandatos →"}
          </button>
        </div>
      </div>
    );
  }

  if (sucesso) {
    return (
      <>
        <div className="rounded border border-ok-300 bg-ok-50 p-4 text-sm text-ok-900">
          <p className="font-medium">
            {sucesso.arquivos} arquivo(s) enviado(s) para o mandato “{sucesso.mandato}”.
          </p>
          {/* O TEMPO É PROPORCIONAL AO LOTE, e a tela diz isso antes de a pessoa
              se perguntar. Cada documento passa pela IA com espaçamento entre as
              chamadas (o limite de uso da conta obriga), então 38 arquivos são
              ~20 minutos — e quem não sabe disso lê a demora como travamento. */}
          <p className="mt-1 text-ok-800">
            Estamos organizando tudo com cuidado. São cerca de{" "}
            <strong>{estimativaEmMinutos(sucesso.arquivos)} minutos</strong>
            {" "}para {sucesso.arquivos} arquivo(s) — cada um é lido separadamente. Você pode aguardar
            aqui ou voltar mais tarde.
          </p>
          {progresso && progresso.processados > 0 && (
            <div className="mt-2">
              <div className="h-1.5 w-full overflow-hidden rounded bg-ok-200">
                <div
                  className="h-full bg-ok-600 transition-all"
                  style={{ width: `${Math.min(100, (progresso.processados / Math.max(1, progresso.esperados)) * 100)}%` }}
                />
              </div>
              <p className="mt-1 text-xs text-ok-800">
                {progresso.processados} de {progresso.esperados} organizados
              </p>
            </div>
          )}
          {demorou && (
            <p className="mt-2 rounded border border-alerta-300 bg-alerta-50 p-2 text-xs text-alerta-900">
              Está levando mais tempo que o previsto e paramos de acompanhar por aqui — o
              processamento pode continuar em segundo plano. Abra o mandato para ver o estado atual;
              se nada tiver chegado, acione o desenvolvedor do sistema.
            </p>
          )}
          <div className="mt-3 flex gap-3">
            {casoId ? (
              <button
                type="button"
                onClick={() => router.push(`/casos/${casoId}`)}
                className="rounded bg-ok-700 px-3 py-1.5 text-xs font-medium text-papel hover:bg-ok-800"
              >
                Voltar ao mandato →
              </button>
            ) : (
              <button
                type="button"
                onClick={() => router.push("/casos")}
                className="rounded bg-ok-700 px-3 py-1.5 text-xs font-medium text-papel hover:bg-ok-800"
              >
                Ver mandatos →
              </button>
            )}
            <button
              type="button"
              onClick={() => {
                setSucesso(null);
                setPronto(false);
              }}
              className="rounded border border-ok-300 px-3 py-1.5 text-xs font-medium text-ok-800 hover:bg-ok-100"
            >
              Enviar mais arquivos
            </button>
          </div>
        </div>

        {pronto && (
          <div className="fixed inset-0 z-50 flex items-center justify-center bg-tinta-900/40 px-4">
            <div className="w-full max-w-sm rounded-lg bg-folha p-6 text-center shadow-xl">
              <div className="mx-auto mb-3 flex h-12 w-12 items-center justify-center rounded-full bg-ok-100 text-2xl">
                ✓
              </div>
              <h2 className="text-base font-semibold text-tinta-900">Tudo pronto</h2>
              <p className="mt-2 text-sm text-tinta-600">
                Seus documentos foram organizados e já estão disponíveis no mandato “{sucesso.mandato}”.
              </p>
              <div className="mt-5 flex justify-center gap-3">
                <button
                  type="button"
                  onClick={() => (casoId ? router.push(`/casos/${casoId}`) : router.push("/casos"))}
                  className="rounded bg-tinta-900 px-4 py-2 text-sm font-medium text-papel hover:bg-tinta-600"
                >
                  Ver mandato →
                </button>
                <button
                  type="button"
                  onClick={() => setPronto(false)}
                  className="rounded border border-tinta-200 px-4 py-2 text-sm font-medium text-tinta-600 hover:bg-tinta-50"
                >
                  Continuar aqui
                </button>
              </div>
            </div>
          </div>
        )}
      </>
    );
  }

  return (
    <form onSubmit={enviar} className="space-y-4">
      <div>
        <label className="mb-1 block text-sm font-medium text-tinta-600">Mandato</label>
        <input
          type="text"
          value={mandato}
          onChange={(e) => setMandato(e.target.value)}
          readOnly={travarMandato}
          placeholder="ex.: Reestruturação Grupo X"
          className={`w-full rounded border px-3 py-2 text-sm ${
            travarMandato ? "border-tinta-200 bg-tinta-100 text-tinta-600" : "border-tinta-200"
          }`}
        />
        <p className="mt-1 text-xs text-tinta-500">
          {travarMandato
            ? "Os arquivos entram neste mesmo mandato — somam ao checklist, à exportação e à checagem de dados já existentes."
            : "Use o MESMO nome para enviar arquivos em momentos diferentes e acumulá-los no mesmo mandato (mesmo checklist, mesma exportação, mesma reconciliação)."}
        </p>
      </div>

      <div>
        <label className="mb-1 block text-sm font-medium text-tinta-600">Arquivos</label>
        <div
          onClick={() => inputRef.current?.click()}
          onDragOver={(e) => {
            e.preventDefault();
            setArrastando(true);
          }}
          onDragLeave={() => setArrastando(false)}
          onDrop={(e) => {
            e.preventDefault();
            setArrastando(false);
            adicionarArquivos(e.dataTransfer.files);
          }}
          className={`flex cursor-pointer flex-col items-center justify-center rounded border-2 border-dashed px-4 py-8 text-center text-sm transition ${
            arrastando ? "border-tinta-500 bg-tinta-50" : "border-tinta-200"
          }`}
        >
          <span className="font-medium text-tinta-600">Arraste os arquivos aqui</span>
          <span className="text-tinta-500">ou clique para selecionar (PDF, imagens; vários de uma vez)</span>
          <input
            ref={inputRef}
            type="file"
            multiple
            className="hidden"
            onChange={(e) => adicionarArquivos(e.target.files)}
          />
        </div>
      </div>

      {arquivos.length > 0 && (
        <ul className="divide-y divide-tinta-100 rounded border border-tinta-200 bg-folha text-sm">
          {arquivos.map((a, i) => (
            <li key={`${a.name}:${a.size}`} className="flex items-center justify-between px-3 py-2">
              <span className="truncate">
                {a.name} <span className="text-tinta-400">({formatarTamanho(a.size)})</span>
              </span>
              <button
                type="button"
                onClick={() => removerArquivo(i)}
                className="ml-3 text-xs text-tinta-500 underline hover:text-risco-700"
              >
                remover
              </button>
            </li>
          ))}
        </ul>
      )}

      {/* O TEMPO ESPERADO APARECE ANTES DE ENVIAR, e não só depois.
          Até aqui a estimativa só existia na tela de sucesso — ou seja, o
          analista descobria que o lote levaria vinte minutos DEPOIS de já ter
          mandado, quando a decisão de esperar ou voltar mais tarde já não era
          dele. Com 38 arquivos selecionados isso é a diferença entre planejar e
          ser surpreendido. */}
      {arquivos.length > 0 && (
        <p className="rounded border border-tinta-200 bg-tinta-50 px-3 py-2 text-sm text-tinta-600">
          Tempo esperado de processamento:{" "}
          <strong className="text-tinta-800">
            ~{estimativaEmMinutos(arquivos.length)}{" "}
            {estimativaEmMinutos(arquivos.length) === 1 ? "minuto" : "minutos"}
          </strong>{" "}
          para {arquivos.length} {arquivos.length === 1 ? "arquivo" : "arquivos"}. Cada arquivo é
          lido separadamente pela IA, e as chamadas são espaçadas por exigência do limite de uso
          da conta. Você pode fechar esta aba: o processamento continua.
        </p>
      )}

      {erro && (
        <p className="rounded border border-risco-300 bg-risco-50 px-3 py-2 text-sm text-risco-700">{erro}</p>
      )}

      <button
        type="submit"
        disabled={enviando}
        className="btn-primario px-4 py-2"
      >
        {/* A ação primária da tela usa a cor primária do produto — este botão
            era grafite enquanto o resto do portal já era acento. E o rótulo
            conta os arquivos em vez do "(s)": com 38 selecionados, "Enviar 38
            arquivos" confirma o que vai acontecer. */}
        {enviando
          ? "Enviando…"
          : arquivos.length === 0
            ? "Enviar arquivos"
            : `Enviar ${arquivos.length} ${arquivos.length === 1 ? "arquivo" : "arquivos"}`}
      </button>
    </form>
  );
}
