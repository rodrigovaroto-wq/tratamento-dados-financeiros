"use client";

import { useState } from "react";
import { abrirRodada, type Resultado } from "@/app/autonomia/golden/actions";

export function AbrirRodada() {
  const [r, setR] = useState<Resultado | null>(null);
  const [enviando, setEnviando] = useState(false);

  return (
    <section className="rounded border border-tinta-200 bg-white p-4">
      <h2 className="text-sm font-semibold">Abrir rodada</h2>
      {/* O NOME É A REFERÊNCIA QUE UMA DECISÃO DE DIAL CITA, e por isso a tela pede
          um nome que sirva de citação em vez de aceitar qualquer coisa em silêncio.
          "a rodada de agosto" não é referência quando existirem três. */}
      <p className="mt-1 text-xs text-tinta-500">
        O nome fica citado na trilha do dial como a evidência de uma subida — escolha um que
        ainda faça sentido daqui a um ano.
      </p>
      <form
        className="mt-2 flex flex-wrap items-center gap-2"
        action={async (fd) => {
          setEnviando(true);
          setR(null);
          try {
            setR(await abrirRodada(fd));
          } finally {
            setEnviando(false);
          }
        }}
      >
        <input
          type="text"
          name="nome"
          required
          placeholder="ex.: Calibração 2026-Q3 — balanços e DREs"
          className="w-80 rounded border border-tinta-300 px-2 py-1 text-sm"
        />
        <input
          type="text"
          name="nota"
          placeholder="nota (opcional)"
          className="w-64 rounded border border-tinta-300 px-2 py-1 text-sm"
        />
        <button
          type="submit"
          disabled={enviando}
          className="rounded bg-tinta-900 px-3 py-1.5 text-sm font-medium text-white disabled:opacity-50"
        >
          {enviando ? "abrindo…" : "Abrir"}
        </button>
      </form>
      {r && !r.ok && (
        <p className="mt-2 rounded border border-red-300 bg-red-50 px-3 py-2 text-sm text-red-800">
          {r.erro}
        </p>
      )}
      {r?.ok && (
        <p className="mt-2 rounded border border-emerald-200 bg-emerald-50 px-3 py-2 text-sm text-emerald-800">
          ✓ Rodada “{String(r.dado.nome)}” aberta na taxonomia v
          {String(r.dado.taxonomia_versao)}. Recarregue para vê-la na lista.
        </p>
      )}
    </section>
  );
}
