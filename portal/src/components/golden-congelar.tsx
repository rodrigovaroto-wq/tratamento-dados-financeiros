"use client";

import { useState } from "react";
import { congelarRodada, type Resultado } from "@/app/autonomia/golden/actions";

// CONGELAR — o ato que transforma rótulo em evidência datada.
//
// A confirmação existe porque é irreversível por desenho: o gatilho da 0126
// recusa descongelar, e recusa por um motivo bom (uma rodada que volta a aceitar
// rótulo depois de ter autorizado uma subida de dial reabre o furo que congelar
// fecha). Então a tela avisa antes, em vez de a pessoa descobrir depois.

export function CongelarRodada({ rodadaId }: { rodadaId: string }) {
  const [r, setR] = useState<Resultado | null>(null);
  const [confirmando, setConfirmando] = useState(false);
  const [enviando, setEnviando] = useState(false);

  return (
    <section className="rounded border border-tinta-300 bg-tinta-50 p-4">
      <h2 className="text-sm font-semibold">Congelar rodada</h2>
      <p className="mt-1 text-sm text-tinta-600">
        Congelar é o que dá <strong>data</strong> à evidência: sem isso,{" "}
        <code>fn_golden_suficiente</code> não autoriza subida nenhuma. Depois de congelada, a
        rodada não aceita mais documento nem rótulo, e{" "}
        <strong>não descongela</strong> — ampliar é rodada nova.
      </p>
      <p className="mt-1 text-xs text-tinta-500">
        Documento incluído e não rotulado não impede: ele não entra em métrica nenhuma. Exigir
        que fosse rotulado produziria rótulo ruim, que é pior que rótulo nenhum.
      </p>

      {!confirmando ? (
        <button
          type="button"
          onClick={() => setConfirmando(true)}
          className="mt-3 rounded border border-tinta-400 px-3 py-1.5 text-sm font-medium hover:bg-tinta-100"
        >
          Congelar…
        </button>
      ) : (
        <div className="mt-3 flex flex-wrap items-center gap-2">
          <button
            type="button"
            disabled={enviando}
            onClick={async () => {
              setEnviando(true);
              setR(null);
              try {
                setR(await congelarRodada(rodadaId));
                setConfirmando(false);
              } finally {
                setEnviando(false);
              }
            }}
            className="rounded bg-tinta-900 px-3 py-1.5 text-sm font-medium text-white disabled:opacity-50"
          >
            {enviando ? "congelando…" : "Confirmo: congelar sem volta"}
          </button>
          <button
            type="button"
            onClick={() => setConfirmando(false)}
            className="text-sm text-tinta-500 underline"
          >
            cancelar
          </button>
        </div>
      )}

      {r && !r.ok && (
        <p className="mt-3 rounded border border-red-300 bg-red-50 px-3 py-2 text-sm text-red-800">
          {r.erro}
        </p>
      )}
      {r?.ok && (
        <div className="mt-3 space-y-2">
          <p className="rounded border border-emerald-200 bg-emerald-50 px-3 py-2 text-sm text-emerald-800">
            ✓ Congelada. {String(r.dado.n_rotulos)} rótulo(s) de documento e{" "}
            {String(r.dado.n_campos)} de campo, em {String(r.dado.n_documentos)} documento(s).
            {Number(r.dado.n_documentos_sem_rotulo) > 0 &&
              ` ${String(r.dado.n_documentos_sem_rotulo)} documento(s) ficaram sem rótulo e não entram em métrica.`}
          </p>
          {/* O AVISO DO ROTULADOR ÚNICO vem do banco, não da tela — para quem lê o
              retorno da função no psql ver a mesma coisa que quem lê aqui. */}
          {typeof r.dado.aviso_rotulador_unico === "string" && (
            <p className="rounded border border-amber-300 bg-amber-50 px-3 py-2 text-sm text-amber-900">
              {r.dado.aviso_rotulador_unico}
            </p>
          )}
        </div>
      )}
    </section>
  );
}
