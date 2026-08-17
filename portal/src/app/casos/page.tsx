import Link from "next/link";
import { createClient } from "@/lib/supabase/server";
import type { Caso } from "@/lib/types";
import { CASO_STATUS_LABEL, CASO_STATUS_COLOR } from "@/lib/status";
import { humanizar } from "@/lib/rotulos";

// A LISTA DE MANDATOS É A PORTA DE ENTRADA, e ela dizia menos do que sabia: nome,
// produto em código (`reestruturacao`) e um chip de status. Faltava a data — sem
// ela não dá para distinguir o mandato de ontem do de março — e faltava o estado
// vazio dizer o que fazer.
function dataCurta(iso: string | null | undefined): string {
  if (!iso) return "";
  const d = new Date(iso);
  if (Number.isNaN(d.getTime())) return "";
  return d.toLocaleDateString("pt-BR", { day: "2-digit", month: "short", year: "numeric" });
}

export default async function CasosPage() {
  const supabase = await createClient();
  const { data, error } = await supabase
    .from("caso")
    .select("id, nome, produto, status, criado_em")
    .order("criado_em", { ascending: false });

  const casos = (data as Caso[] | null) ?? [];

  return (
    <div className="space-y-6">
      <div className="flex flex-wrap items-end justify-between gap-3">
        <div>
          <h1 className="text-xl font-semibold text-tinta-900">Mandatos</h1>
          <p className="mt-0.5 text-sm text-tinta-500">
            {casos.length === 0
              ? "Nenhum mandato aberto."
              : `${casos.length} ${casos.length === 1 ? "mandato" : "mandatos"} em acompanhamento.`}
          </p>
        </div>
        <Link href="/casos/novo" className="btn-primario">
          Novo mandato
        </Link>
      </div>

      {error && (
        <p className="rounded-lg border border-red-200 bg-red-50 p-3 text-sm text-red-800">
          Não foi possível carregar os mandatos: {error.message}
        </p>
      )}

      {!error && casos.length === 0 ? (
        // ESTADO VAZIO COM SAÍDA. "Nenhum mandato ainda" deixava quem chegou sem
        // o próximo passo; agora a própria caixa é o convite.
        <div className="carta flex flex-col items-center gap-3 px-6 py-12 text-center">
          <p className="text-sm font-medium text-tinta-900">Comece subindo os arquivos de um mandato</p>
          <p className="max-w-md text-sm text-tinta-500">
            O sistema classifica cada documento, extrai as linhas financeiras e aponta o que ficou
            faltando ou divergente. Você confere e aprova.
          </p>
          <Link href="/casos/novo" className="btn-primario mt-1">
            Novo mandato
          </Link>
        </div>
      ) : (
        <ul className="carta divide-y divide-tinta-100 overflow-hidden">
          {casos.map((caso) => (
            <li key={caso.id}>
              <Link
                href={`/casos/${caso.id}`}
                className="flex items-center justify-between gap-4 px-4 py-3.5 transition-colors hover:bg-tinta-50"
              >
                <div className="min-w-0">
                  <p className="truncate text-sm font-medium text-tinta-900">{caso.nome}</p>
                  <p className="mt-0.5 text-xs text-tinta-500">
                    {humanizar(caso.produto)}
                    {dataCurta(caso.criado_em) && ` · aberto em ${dataCurta(caso.criado_em)}`}
                  </p>
                </div>
                <div className="flex shrink-0 items-center gap-3">
                  <span className={`chip ${CASO_STATUS_COLOR[caso.status]}`}>
                    {CASO_STATUS_LABEL[caso.status]}
                  </span>
                  <span aria-hidden className="text-tinta-400">
                    ›
                  </span>
                </div>
              </Link>
            </li>
          ))}
        </ul>
      )}
    </div>
  );
}
