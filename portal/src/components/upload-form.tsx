"use client";

import { useEffect, useRef, useState } from "react";
import { explicarFalha, explicarParada, explicarLoteVazio, type FalhaExplicada } from "@/lib/falha-em-portugues";
import { ExcluirMandato } from "@/components/excluir-mandato";
import { useRouter } from "next/navigation";
import {
  estimativaEmMinutos, janelaPara, semPrimeiroSinalMs, semProgressoMs, proximoIntervalo,
  INTERVALO_ACOMPANHAMENTO_MS,
} from "@/lib/espera-do-lote";


const MB = 1024 * 1024;
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
  const [loteVazio, setLoteVazio] = useState<{ comLinhas: number; comFatos: number; documentos: number } | null>(null);
  // O ID DO MANDATO, que a rota já conhecia e não devolvia. Ele existe aqui por
  // UM motivo: um mandato que terminou sem nada dentro tem de poder ser
  // descartado da própria tela que o acusa — ver o bloco de explicação.
  const [casoIdDoLote, setCasoIdDoLote] = useState<string | null>(null);

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
          if (typeof json.casoId === "string") setCasoIdDoLote(json.casoId);
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
          if (typeof json.casoId === "string") setCasoIdDoLote(json.casoId);
          if (typeof json.comLinhas === "number") {
            setLoteVazio({
              comLinhas: json.comLinhas,
              // FATO CONTA COMO CONTEÚDO: um Parecer do Auditor rende zero
              // linhas e o alerta que vai ao comitê. Ver `explicarLoteVazio`.
              comFatos: typeof json.comFatos === "number" ? json.comFatos : 0,
              documentos: json.esperados,
            });
          }
          if (casoId) router.refresh();
          return;
        }
        // PAROU DE ANDAR: declara, em vez de continuar perguntando com cara de
        // calma. O limite é maior enquanto nada apareceu ainda — nessa fase o
        // silêncio é legítimo.
        if (!cancelado && resp.ok) {
          const parado = Date.now() - ultimoAvanco;
          // OS DOIS LIMITES SAEM DO TAMANHO DO LOTE (ver espera-do-lote.ts).
          // O do meio era FIXO em 5 minutos e declarou morto um lote de 190 que
          // estava vivo: entre a barreira que registra os documentos e a que
          // grava as linhas correm 25 minutos de chamadas de IA em que, por
          // construção, nada é escrito no banco.
          const limite = ultimoVisto > 0
            ? semProgressoMs(sucesso.arquivos)
            : semPrimeiroSinalMs(sucesso.arquivos);
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
        ? `Sem progresso por mais de ${Math.round(semProgressoMs(sucesso?.arquivos ?? 0) / 60000)} minutos. `
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

          {/* DESCARTAR O MANDATO QUE NÃO TROUXE NADA — na tela que o acusa.
              O mandato é criado no PRIMEIRO nó do fluxo, antes de qualquer
              leitura: ele é o recipiente em que todo o resto é gravado, e não
              existe "criar depois" sem inverter o pipeline inteiro. O que dá
              para garantir é o efeito prático — que ninguém fique com um
              mandato vazio na lista sem saber o que fazer com ele.
              Só aparece quando o lote terminou SEM CONTEÚDO NENHUM (nem linha
              nem fato); um lote incompleto tem dado dentro, e apagá-lo perderia
              o que deu certo. A confirmação é a mesma do resto do portal. */}
          {loteVazio && !falha && !parada && loteVazio.comLinhas === 0 && loteVazio.comFatos === 0
            && casoIdDoLote && (
            <ExcluirMandato casoId={casoIdDoLote} nome={sucesso.mandato} />
          )}
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

        {/* O MODAL DE SUCESSO SÓ APARECE QUANDO HOUVE SUCESSO.
            Ele era condicionado só a `pronto`, e `pronto` mede que o pipeline
            TENTOU ler cada arquivo — não que ele conseguiu, e não que a
            execução chegou ao fim. Foi assim que uma execução morta virou "Tudo
            pronto" na tela do dono em 27/08/2026. Agora, se há o que explicar
            (falha, parada ou lote sem conteúdo), a explicação é a tela — e ela
            já é renderizada acima, antes de chegar aqui. */}
        {pronto && !explicacao && (
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
        <button
          type="button"
          // BOTÃO DE VERDADE, não `div` com `role="button"`. A versão anterior
          // reimplementava na mão o que o elemento nativo já faz — foco, Enter,
          // Espaço, anúncio do papel — e o Sonar cobra isso em `typescript:S6819`
          // com razão: a reimplementação cobre os teclados que alguém lembrou, e
          // o elemento nativo cobre os que ninguém lembrou (leitor de tela em
          // modo de navegação, controle por voz, teclado de celular). Some junto
          // o `onKeyDown` manual: Enter e Espaço passam a vir do navegador.
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
          className={`flex w-full cursor-pointer flex-col items-center justify-center rounded border-2 border-dashed px-4 py-8 text-center text-sm transition ${
            arrastando ? "border-tinta-500 bg-tinta-50" : "border-tinta-200"
          }`}
        >
          <span className="font-medium text-tinta-600">Arraste os arquivos aqui</span>
          <span className="text-tinta-500">ou clique para selecionar (PDF, imagens; vários de uma vez)</span>
        </button>
        {/* O input fica FORA do botão: `<input>` dentro de `<button>` é HTML
            inválido (conteúdo interativo aninhado), e o navegador pode reparar a
            árvore movendo o input para fora do botão sozinho — o que quebraria o
            `inputRef` de um jeito que só aparece em runtime. */}
        <input
          ref={inputRef}
          type="file"
          multiple
          className="hidden"
          onChange={(e) => adicionarArquivos(e.target.files)}
        />
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
