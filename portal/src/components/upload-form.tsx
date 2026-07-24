"use client";

import { useEffect, useRef, useState } from "react";
import { useRouter } from "next/navigation";

const MB = 1024 * 1024;
// Intervalo e teto do acompanhamento silencioso pós-envio — nem todo mandato
// termina rápido (documentos grandes/em lote levam minutos); depois do teto,
// para de perguntar sozinho sem assustar ninguém (o mandato sempre pode ser
// conferido manualmente).
const INTERVALO_ACOMPANHAMENTO_MS = 8000;
const TENTATIVAS_MAXIMAS = 90; // ~12 minutos

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

  // Acompanha silenciosamente, em segundo plano, até os arquivos enviados
  // estarem organizados — sem nomear nenhuma ferramenta ou etapa técnica.
  useEffect(() => {
    if (!sucesso || pronto) return;
    let cancelado = false;
    let tentativas = 0;

    const verificar = async () => {
      if (cancelado) return;
      tentativas += 1;
      try {
        const params = new URLSearchParams({
          caso: sucesso.mandato,
          desde: sucesso.desde,
          esperados: String(sucesso.arquivos),
        });
        const resp = await fetch(`/api/intake/status?${params}`);
        const json = await resp.json().catch(() => ({}));
        if (!cancelado && resp.ok && json.pronto) {
          setPronto(true);
          if (casoId) router.refresh();
          return;
        }
      } catch {
        // Falha pontual de rede não interrompe o acompanhamento — só a
        // próxima tentativa (ou o teto de tentativas) decide quando parar.
      }
      if (!cancelado && tentativas < TENTATIVAS_MAXIMAS) {
        setTimeout(verificar, INTERVALO_ACOMPANHAMENTO_MS);
      }
    };

    const primeiraEspera = setTimeout(verificar, INTERVALO_ACOMPANHAMENTO_MS);
    return () => {
      cancelado = true;
      clearTimeout(primeiraEspera);
    };
  }, [sucesso, pronto, casoId, router]);

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

  if (sucesso) {
    return (
      <>
        <div className="rounded border border-emerald-300 bg-emerald-50 p-4 text-sm text-emerald-900">
          <p className="font-medium">
            {sucesso.arquivos} arquivo(s) enviado(s) para o mandato “{sucesso.mandato}”.
          </p>
          <p className="mt-1 text-emerald-800">
            Estamos organizando tudo com cuidado — isso costuma levar alguns minutos. Você pode
            aguardar aqui ou voltar mais tarde; assim que estiver pronto, avisamos.
          </p>
          <div className="mt-3 flex gap-3">
            {casoId ? (
              <button
                onClick={() => router.push(`/casos/${casoId}`)}
                className="rounded bg-emerald-700 px-3 py-1.5 text-xs font-medium text-white hover:bg-emerald-800"
              >
                Voltar ao mandato →
              </button>
            ) : (
              <button
                onClick={() => router.push("/casos")}
                className="rounded bg-emerald-700 px-3 py-1.5 text-xs font-medium text-white hover:bg-emerald-800"
              >
                Ver mandatos →
              </button>
            )}
            <button
              onClick={() => {
                setSucesso(null);
                setPronto(false);
              }}
              className="rounded border border-emerald-300 px-3 py-1.5 text-xs font-medium text-emerald-800 hover:bg-emerald-100"
            >
              Enviar mais arquivos
            </button>
          </div>
        </div>

        {pronto && (
          <div className="fixed inset-0 z-50 flex items-center justify-center bg-neutral-900/40 px-4">
            <div className="w-full max-w-sm rounded-lg bg-white p-6 text-center shadow-xl">
              <div className="mx-auto mb-3 flex h-12 w-12 items-center justify-center rounded-full bg-emerald-100 text-2xl">
                ✓
              </div>
              <h2 className="text-base font-semibold text-neutral-900">Tudo pronto</h2>
              <p className="mt-2 text-sm text-neutral-600">
                Seus documentos foram organizados e já estão disponíveis no mandato “{sucesso.mandato}”.
              </p>
              <div className="mt-5 flex justify-center gap-3">
                <button
                  onClick={() => (casoId ? router.push(`/casos/${casoId}`) : router.push("/casos"))}
                  className="rounded bg-neutral-900 px-4 py-2 text-sm font-medium text-white hover:bg-neutral-700"
                >
                  Ver mandato →
                </button>
                <button
                  onClick={() => setPronto(false)}
                  className="rounded border border-neutral-300 px-4 py-2 text-sm font-medium text-neutral-700 hover:bg-neutral-50"
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
        <label className="mb-1 block text-sm font-medium text-neutral-700">Mandato</label>
        <input
          type="text"
          value={mandato}
          onChange={(e) => setMandato(e.target.value)}
          readOnly={travarMandato}
          placeholder="ex.: Reestruturação Grupo X"
          className={`w-full rounded border px-3 py-2 text-sm ${
            travarMandato ? "border-neutral-200 bg-neutral-100 text-neutral-600" : "border-neutral-300"
          }`}
        />
        <p className="mt-1 text-xs text-neutral-500">
          {travarMandato
            ? "Os arquivos entram neste mesmo mandato — somam ao checklist, à exportação e à checagem de dados já existentes."
            : "Use o MESMO nome para enviar arquivos em momentos diferentes e acumulá-los no mesmo mandato (mesmo checklist, mesma exportação, mesma reconciliação)."}
        </p>
      </div>

      <div>
        <label className="mb-1 block text-sm font-medium text-neutral-700">Arquivos</label>
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
            arrastando ? "border-neutral-500 bg-neutral-50" : "border-neutral-300"
          }`}
        >
          <span className="font-medium text-neutral-700">Arraste os arquivos aqui</span>
          <span className="text-neutral-500">ou clique para selecionar (PDF, imagens; vários de uma vez)</span>
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
        <ul className="divide-y divide-neutral-100 rounded border border-neutral-200 bg-white text-sm">
          {arquivos.map((a, i) => (
            <li key={`${a.name}:${a.size}`} className="flex items-center justify-between px-3 py-2">
              <span className="truncate">
                {a.name} <span className="text-neutral-400">({formatarTamanho(a.size)})</span>
              </span>
              <button
                type="button"
                onClick={() => removerArquivo(i)}
                className="ml-3 text-xs text-neutral-500 underline hover:text-red-700"
              >
                remover
              </button>
            </li>
          ))}
        </ul>
      )}

      {erro && (
        <p className="rounded border border-red-300 bg-red-50 px-3 py-2 text-sm text-red-700">{erro}</p>
      )}

      <button
        type="submit"
        disabled={enviando}
        className="rounded bg-neutral-900 px-4 py-2 text-sm font-medium text-white hover:bg-neutral-700 disabled:opacity-50"
      >
        {enviando ? "Enviando…" : `Enviar ${arquivos.length || ""} arquivo(s)`}
      </button>
    </form>
  );
}
