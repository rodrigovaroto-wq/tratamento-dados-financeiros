"use client";

import { useState } from "react";
import { incluirDocumento, type Resultado } from "@/app/autonomia/golden/actions";

// A ESCOLHA DA AMOSTRA, feita por pessoa e não por sorteio.
//
// A 0130 não sorteia de propósito, e a tela segue a mesma decisão: amostragem
// estratificada é escolha sobre um conjunto que quem escolhe conhece — qual
// cliente, qual arquivo era um horror de ler — e uma amostra sorteada por função
// é uma amostra que ninguém consegue defender numa reunião.
//
// O ESTRATO VEM SUGERIDO E O PORQUÊ FICA À VISTA. Diferente da classe contábil,
// aqui a sugestão PODE vir pré-selecionada: estrato é propriedade objetiva do
// arquivo (é ou não é um scan), não julgamento de conteúdo, então não há
// ancoragem a proteger. O que há é um erro provável e nomeado — scan legível cai
// em "pdf nativo" —, e é por isso que o motivo da sugestão fica escrito ao lado.

type Candidato = {
  documento_id: string;
  caso_nome: string;
  nome_original: string | null;
  tipo_maquina: string | null;
  legibilidade: string | null;
  n_linhas: number;
  estrato_sugerido: string | null;
  estrato_porque: string | null;
};

const ESTRATOS = [
  { v: "digital", t: "digital (planilha/doc)" },
  { v: "pdf_nativo", t: "PDF nativo" },
  { v: "escaneado", t: "escaneado" },
  { v: "foto", t: "foto" },
];

export function IncluirDocumento({
  rodadaId,
  candidatos,
}: {
  rodadaId: string;
  candidatos: Candidato[];
}) {
  const [r, setR] = useState<Resultado | null>(null);
  const [enviando, setEnviando] = useState<string | null>(null);
  const [busca, setBusca] = useState("");

  const filtrados = candidatos.filter((c) =>
    busca.trim() === ""
      ? true
      : `${c.nome_original ?? ""} ${c.caso_nome} ${c.tipo_maquina ?? ""}`
          .toLowerCase()
          .includes(busca.toLowerCase()),
  );

  return (
    <section className="rounded border border-tinta-200 bg-white p-4">
      <h2 className="text-sm font-semibold">Incluir documento</h2>
      <p className="mt-1 text-xs text-tinta-500">
        Estratifique por qualidade de captura: a métrica agregada sobre estratos misturados
        esconde o pior caso, e é o pior caso que decide se o dial pode subir. E marque{" "}
        <strong>sintético</strong> no que vier do book — as métricas do dial contam só documento
        real, porque rotular um gabarito que já se conhece mede o instrumento, não o modelo.
      </p>

      <input
        type="search"
        value={busca}
        onChange={(e) => setBusca(e.target.value)}
        placeholder="filtrar por arquivo, mandato ou tipo"
        className="mt-2 w-72 rounded border border-tinta-300 px-2 py-1 text-sm"
      />

      {r && !r.ok && (
        <p className="mt-2 rounded border border-red-300 bg-red-50 px-3 py-2 text-sm text-red-800">
          {r.erro}
        </p>
      )}
      {r?.ok && (
        <p className="mt-2 rounded border border-emerald-200 bg-emerald-50 px-3 py-2 text-sm text-emerald-800">
          ✓ Incluído. Recarregue para vê-lo na lista da rodada.
        </p>
      )}

      {filtrados.length === 0 ? (
        <p className="mt-3 text-sm text-tinta-500">
          {candidatos.length === 0
            ? "Todos os documentos já estão nesta rodada."
            : "Nenhum documento com esse filtro."}
        </p>
      ) : (
        <ul className="mt-3 max-h-96 divide-y divide-tinta-100 overflow-y-auto rounded border border-tinta-200">
          {filtrados.slice(0, 100).map((c) => (
            <li key={c.documento_id} className="px-3 py-2">
              <form
                className="flex flex-wrap items-center gap-2"
                action={async (fd) => {
                  setEnviando(c.documento_id);
                  setR(null);
                  try {
                    setR(await incluirDocumento(rodadaId, fd));
                  } finally {
                    setEnviando(null);
                  }
                }}
              >
                <input type="hidden" name="documento_id" value={c.documento_id} />
                <div className="min-w-56 flex-1">
                  <p className="text-sm">{c.nome_original ?? "(sem nome)"}</p>
                  <p className="text-xs text-tinta-500">
                    {c.caso_nome} · <span className="font-mono">{c.tipo_maquina ?? "?"}</span> ·{" "}
                    {c.n_linhas} linha(s)
                    {c.legibilidade && c.legibilidade !== "ok" && (
                      <span className="text-amber-800"> · {c.legibilidade}</span>
                    )}
                    {/* Zero linha extraída é candidato ruim e a tela diz por quê,
                        em vez de deixar a pessoa descobrir quando o placar sair
                        todo ausente. Não é proibido: perda total é dado real. */}
                    {c.n_linhas === 0 && (
                      <span className="text-amber-800">
                        {" "}
                        · sem extração: todo campo entraria como ausente
                      </span>
                    )}
                  </p>
                </div>
                <select
                  name="estrato"
                  required
                  defaultValue={c.estrato_sugerido ?? ""}
                  title={c.estrato_porque ?? undefined}
                  className="rounded border border-tinta-300 px-1 py-0.5 text-xs"
                >
                  <option value="" disabled>
                    estrato…
                  </option>
                  {ESTRATOS.map((e) => (
                    <option key={e.v} value={e.v}>
                      {e.t}
                    </option>
                  ))}
                </select>
                <select
                  name="origem"
                  required
                  defaultValue="real"
                  className="rounded border border-tinta-300 px-1 py-0.5 text-xs"
                >
                  <option value="real">real</option>
                  <option value="sintetico">sintético (book)</option>
                </select>
                <button
                  type="submit"
                  disabled={enviando === c.documento_id}
                  className="rounded border border-tinta-300 px-2 py-0.5 text-xs font-medium hover:bg-tinta-100 disabled:opacity-50"
                >
                  {enviando === c.documento_id ? "…" : "incluir"}
                </button>
              </form>
            </li>
          ))}
        </ul>
      )}
      {filtrados.length > 100 && (
        // TETO DITO, nunca silencioso: a lista mostra 100 e diz que mostra 100.
        <p className="mt-2 text-xs text-tinta-500">
          Mostrando 100 de {filtrados.length}. Filtre para alcançar o resto.
        </p>
      )}
    </section>
  );
}
