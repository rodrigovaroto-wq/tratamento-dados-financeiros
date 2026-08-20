"use client";

import { useState } from "react";
import { rotularDocumento, type Resultado } from "@/app/autonomia/golden/actions";

// O JULGAMENTO DO DOCUMENTO: tipo, empresa, período, assinatura, legibilidade.
//
// TODO CAMPO É OPCIONAL, e isso é decisão da 0126 respeitada aqui: campo nulo
// significa "este rotulador não julgou isto", que NÃO é o mesmo que discordar —
// entra como item não medido, nunca como acerto nem como erro. Forçar o
// preenchimento produziria julgamento inventado sobre o que a pessoa não olhou, e
// julgamento inventado é pior que campo vazio, porque conta.
//
// A ASSINATURA É TRI-ESTADO pelo mesmo motivo, e é onde um seletor booleano
// erraria com mais facilidade: "não vi" e "não está assinado" são coisas
// diferentes e a segunda é uma afirmação sobre o documento.

export function RotularDocumento({
  rodadaId,
  docId,
  tipos,
  jaRotulado,
}: {
  rodadaId: string;
  docId: string;
  tipos: { codigo: string; documento: string }[];
  jaRotulado: boolean;
}) {
  const [r, setR] = useState<Resultado | null>(null);
  const [enviando, setEnviando] = useState(false);

  if (jaRotulado && !r) {
    return (
      <section className="rounded border border-emerald-200 bg-emerald-50 p-4 text-sm text-emerald-800">
        Você já rotulou este documento nesta rodada. Rótulo é append-only: corrigi-lo seria
        reescrever a justificativa de uma decisão de dial depois da decisão, então a correção é
        rodada nova. Os <strong>valores das linhas</strong> abaixo você ainda pode acrescentar.
      </section>
    );
  }

  return (
    <section className="rounded border border-tinta-200 bg-white p-4">
      <h2 className="text-sm font-semibold">1. O documento</h2>
      <p className="mt-1 text-xs text-tinta-500">
        Deixe em branco o que você não olhou. Campo vazio entra como{" "}
        <strong>não medido</strong> — nunca como acerto nem como erro da máquina.
      </p>

      <form
        className="mt-3 space-y-3"
        action={async (fd) => {
          setEnviando(true);
          setR(null);
          try {
            setR(await rotularDocumento(rodadaId, docId, fd));
          } finally {
            setEnviando(false);
          }
        }}
      >
        <div className="flex flex-wrap gap-3">
          <label className="text-xs text-tinta-600">
            <span className="block">Que documento é este?</span>
            <select
              name="tipo_correto"
              defaultValue=""
              className="mt-0.5 w-72 rounded border border-tinta-300 px-2 py-1 text-sm"
            >
              <option value="">— não julguei —</option>
              {tipos.map((t) => (
                <option key={t.codigo} value={t.codigo}>
                  {t.documento} ({t.codigo})
                </option>
              ))}
            </select>
          </label>

          <label className="text-xs text-tinta-600">
            <span className="block">Empresa, como está escrito no documento</span>
            <input
              type="text"
              name="entidade_correta"
              className="mt-0.5 w-72 rounded border border-tinta-300 px-2 py-1 text-sm"
            />
            {/* A comparação usa fn_mesma_entidade (0030): duas grafias da mesma
                companhia não contam como erro nem como discordância. Então vale
                copiar do papel, sem normalizar de cabeça. */}
            <span className="mt-0.5 block text-tinta-400">
              copie do papel — grafia diferente da mesma empresa não é erro
            </span>
          </label>

          <label className="text-xs text-tinta-600">
            <span className="block">Período</span>
            <input
              type="text"
              name="periodo_correto"
              placeholder="ex.: 2024 ou 2024-06"
              className="mt-0.5 w-40 rounded border border-tinta-300 px-2 py-1 text-sm"
            />
          </label>

          <label className="text-xs text-tinta-600">
            <span className="block">Assinado?</span>
            <select
              name="assinado_correto"
              defaultValue=""
              className="mt-0.5 w-36 rounded border border-tinta-300 px-2 py-1 text-sm"
            >
              <option value="">— não vi —</option>
              <option value="sim">sim</option>
              <option value="nao">não</option>
            </select>
          </label>

          <label className="text-xs text-tinta-600">
            <span className="block">Legibilidade</span>
            <select
              name="legibilidade"
              defaultValue=""
              className="mt-0.5 w-40 rounded border border-tinta-300 px-2 py-1 text-sm"
            >
              <option value="">— não julguei —</option>
              <option value="ok">ok</option>
              <option value="degradado">degradado</option>
              <option value="ilegivel">ilegível</option>
            </select>
          </label>
        </div>

        <div className="flex flex-wrap items-center gap-2">
          <input
            type="text"
            name="nota"
            placeholder="nota (ex.: página 3 rasgada, coluna de 2023 ilegível)"
            className="w-96 rounded border border-tinta-300 px-2 py-1 text-sm"
          />
          <button
            type="submit"
            disabled={enviando}
            className="rounded bg-tinta-900 px-3 py-1.5 text-sm font-medium text-white disabled:opacity-50"
          >
            {enviando ? "gravando…" : "Gravar rótulo do documento"}
          </button>
        </div>
      </form>

      {r && !r.ok && (
        <p className="mt-3 rounded border border-red-300 bg-red-50 px-3 py-2 text-sm text-red-800">
          {r.erro}
        </p>
      )}
      {r?.ok && (
        <p className="mt-3 rounded border border-emerald-200 bg-emerald-50 px-3 py-2 text-sm text-emerald-800">
          ✓ Rótulo gravado. Ele não se edita — se estiver errado, a correção é rodada nova.
        </p>
      )}
    </section>
  );
}
