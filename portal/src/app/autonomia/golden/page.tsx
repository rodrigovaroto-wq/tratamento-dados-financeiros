import Link from "next/link";
import { createClient } from "@/lib/supabase/server";
import { AbrirRodada } from "@/components/golden-abrir-rodada";

// A LISTA DE RODADAS do golden set, e o formulário que abre a próxima.
//
// POR QUE ESTA TELA NÃO É O PAINEL DE AUTONOMIA. O painel é somente leitura por
// decisão registrada nele: "subir dial é decisão de doutrina, não de sessão", e
// um botão ali convidaria a mexer no dial no meio de um caso. Rotular é o
// oposto — é trabalho de mesa, repetitivo, feito documento por documento. São
// duas atividades diferentes e ficam em dois lugares.

type Rodada = {
  id: string;
  nome: string;
  taxonomia_versao: number;
  criada_em: string;
  criada_por: string | null;
  congelada_em: string | null;
  congelada_por: string | null;
  nota: string | null;
};

const dataHora = (s: string | null) =>
  s ? new Date(s).toLocaleString("pt-BR", { dateStyle: "short", timeStyle: "short" }) : "—";

export default async function GoldenPage() {
  const supabase = await createClient();

  const [{ data: rodadas }, { data: contagens }] = await Promise.all([
    supabase
      .from("golden_rodada")
      .select("id, nome, taxonomia_versao, criada_em, criada_por, congelada_em, congelada_por, nota")
      .order("criada_em", { ascending: false })
      .limit(50),
    supabase.from("golden_documento").select("rodada_id"),
  ]);

  const lista = (rodadas as Rodada[] | null) ?? [];
  const nDocs = new Map<string, number>();
  for (const r of ((contagens as { rodada_id: string }[] | null) ?? [])) {
    nDocs.set(r.rodada_id, (nDocs.get(r.rodada_id) ?? 0) + 1);
  }

  return (
    <div className="space-y-6">
      <div>
        <Link href="/autonomia" className="text-sm text-tinta-500 underline">
          ← Painel de autonomia
        </Link>
        <h1 className="mt-2 text-lg font-semibold">Golden set — rodadas de calibração</h1>
        <p className="mt-1 text-sm text-tinta-600">
          O <code>f0/06</code> pede ~20–30 documentos rotulados por tipo core, estratificados por
          qualidade de captura. A rodada <strong>congela</strong> quando a rotulagem termina: é o
          congelamento que dá data à evidência, e só rodada congelada autoriza subir dial.
        </p>
        {/* A REGRA QUE MAIS SURPREENDE QUEM CHEGA, dita antes de alguém tentar. */}
        <p className="mt-1 text-xs text-tinta-500">
          Ampliar o golden set é abrir rodada <strong>nova</strong>, nunca editar a anterior — e
          rótulo não se corrige, porque ele é a justificativa de uma decisão de dial já tomada.
        </p>
      </div>

      <AbrirRodada />

      {lista.length === 0 ? (
        <p className="rounded border border-tinta-200 bg-white px-4 py-3 text-sm text-tinta-500">
          Nenhuma rodada ainda. Abra a primeira acima.
        </p>
      ) : (
        <ul className="divide-y divide-tinta-200 rounded border border-tinta-200 bg-white">
          {lista.map((r) => (
            <li key={r.id} className="px-4 py-3">
              <div className="flex flex-wrap items-baseline gap-2">
                <Link href={`/autonomia/golden/${r.id}`} className="font-medium underline">
                  {r.nome}
                </Link>
                <span
                  className={
                    r.congelada_em
                      ? "rounded bg-tinta-900 px-1.5 py-0.5 text-xs font-medium text-white"
                      : "rounded bg-amber-100 px-1.5 py-0.5 text-xs font-medium text-amber-900"
                  }
                >
                  {r.congelada_em ? "congelada" : "em montagem"}
                </span>
                <span className="text-xs text-tinta-500">
                  {nDocs.get(r.id) ?? 0} documento(s) · taxonomia v{r.taxonomia_versao}
                </span>
              </div>
              <p className="mt-0.5 text-xs text-tinta-500">
                aberta {dataHora(r.criada_em)} por {r.criada_por ?? "—"}
                {r.congelada_em
                  ? ` · congelada ${dataHora(r.congelada_em)} por ${r.congelada_por ?? "—"}`
                  : ""}
              </p>
              {r.nota && <p className="mt-0.5 text-xs text-tinta-600">{r.nota}</p>}
            </li>
          ))}
        </ul>
      )}
    </div>
  );
}
