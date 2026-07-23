import Link from "next/link";
import { createClient } from "@/lib/supabase/server";
import type { Caso } from "@/lib/types";
import { CASO_STATUS_LABEL, CASO_STATUS_COLOR } from "@/lib/status";

export default async function CasosPage() {
  const supabase = await createClient();
  const { data, error } = await supabase
    .from("caso")
    .select("id, nome, produto, status, criado_em")
    .order("criado_em", { ascending: false });

  const casos = (data as Caso[] | null) ?? [];

  return (
    <div className="space-y-4">
      <div className="flex items-center justify-between">
        <h1 className="text-lg font-semibold">Mandatos</h1>
        <Link
          href="/casos/novo"
          className="rounded bg-neutral-900 px-3 py-1.5 text-sm font-medium text-white hover:bg-neutral-700"
        >
          + Novo mandato
        </Link>
      </div>

      {error && (
        <p className="rounded border border-red-300 bg-red-50 p-3 text-sm text-red-700">
          Erro ao carregar casos: {error.message}
        </p>
      )}

      {!error && casos.length === 0 && (
        <p className="text-sm text-neutral-500">
          Nenhum mandato ainda — clique em “+ Novo mandato” para subir os primeiros arquivos.
        </p>
      )}

      <ul className="divide-y divide-neutral-200 rounded border border-neutral-200 bg-white">
        {casos.map((caso) => (
          <li key={caso.id}>
            <Link
              href={`/casos/${caso.id}`}
              className="flex items-center justify-between px-4 py-3 hover:bg-neutral-50"
            >
              <div>
                <p className="text-sm font-medium">{caso.nome}</p>
                <p className="text-xs text-neutral-500">{caso.produto}</p>
              </div>
              <span
                className={`rounded-full px-2 py-1 text-xs font-medium ${CASO_STATUS_COLOR[caso.status]}`}
              >
                {CASO_STATUS_LABEL[caso.status]}
              </span>
            </Link>
          </li>
        ))}
      </ul>
    </div>
  );
}
