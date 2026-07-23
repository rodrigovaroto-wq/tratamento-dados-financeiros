import Link from "next/link";
import { notFound } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import type { CampoExtraido, Documento } from "@/lib/types";
import { aceitarExtracao } from "./actions";

function formatValor(valorNum: number | null, valorTexto: string | null, unidade: string | null) {
  if (valorNum != null) {
    const formatado = valorNum.toLocaleString("pt-BR", { maximumFractionDigits: 2 });
    return unidade ? `${formatado} (${unidade})` : formatado;
  }
  return valorTexto ?? "—";
}

// Agrupa as linhas extraídas por `secao` (agrupador livre da IA — espelha a
// estrutura do próprio documento), preservando a ordem de primeira aparição —
// é o que dá a leitura de "planilha organizada" (docs/04, pedido do dono).
function agruparPorSecao(campos: CampoExtraido[]) {
  const grupos = new Map<string, CampoExtraido[]>();
  for (const campo of campos) {
    const chave = campo.secao ?? "(sem seção)";
    if (!grupos.has(chave)) grupos.set(chave, []);
    grupos.get(chave)!.push(campo);
  }
  return grupos;
}

export default async function PlanilhaDocumentoPage({
  params,
}: {
  params: Promise<{ id: string; docId: string }>;
}) {
  const { id, docId } = await params;
  const supabase = await createClient();

  const documentoRes = await supabase
    .from("documento")
    .select(
      `id, tipo_taxonomia, resumo, justificativa, confianca, fonte,
       entidade:entidade_id(razao_social), periodo:periodo_id(tipo, referencia),
       documento_versao(id, nome_original, legibilidade, nota_legibilidade)`,
    )
    .eq("caso_id", id)
    .eq("id", docId)
    .single();

  if (documentoRes.error || !documentoRes.data) {
    notFound();
  }

  const doc = documentoRes.data as unknown as Documento;
  const versao = doc.documento_versao?.[0];

  const camposRes = versao
    ? await supabase
        .from("campo_extraido")
        .select(
          "id, documento_versao_id, secao, entidade_coluna, periodo_coluna, chave, valor_texto, valor_num, unidade, confianca, origem_pagina, status_aceite, aceito_por, aceito_em",
        )
        .eq("documento_versao_id", versao.id)
        .order("origem_pagina", { ascending: true, nullsFirst: false })
        .order("criado_em", { ascending: true })
    : { data: [], error: null };

  const campos = (camposRes.data as CampoExtraido[] | null) ?? [];
  const grupos = agruparPorSecao(campos);
  const nAceitos = campos.filter((c) => c.status_aceite === "aceito").length;
  const tudoAceito = campos.length > 0 && nAceitos === campos.length;
  const aceitarAction = versao ? aceitarExtracao.bind(null, id, docId) : null;

  return (
    <div className="space-y-6">
      <div>
        <Link href={`/casos/${id}`} className="text-sm text-neutral-500 underline">
          ← Voltar ao caso
        </Link>
        <h1 className="mt-2 text-lg font-semibold">{versao?.nome_original ?? "(sem nome)"}</h1>
        <p className="text-xs text-neutral-500">
          {doc.tipo_taxonomia ?? "não classificado"}
          {doc.entidade?.razao_social ? ` · ${doc.entidade.razao_social}` : ""}
          {doc.periodo ? ` · ${doc.periodo.tipo} ${doc.periodo.referencia}` : ""}
        </p>
      </div>

      {versao?.legibilidade && versao.legibilidade !== "ok" && (
        <div className="rounded border border-red-300 bg-red-50 p-3 text-sm text-red-800">
          <strong className="uppercase">{versao.legibilidade}</strong>
          {versao.nota_legibilidade ? ` — ${versao.nota_legibilidade}` : ""}
        </div>
      )}

      {doc.resumo && (
        <div className="rounded border border-neutral-200 bg-neutral-50 p-3 text-sm text-neutral-700">
          <p className="mb-1 text-xs font-medium uppercase text-neutral-500">Resumo</p>
          {doc.resumo}
        </div>
      )}

      <section>
        <div className="mb-2 flex items-center justify-between">
          <h2 className="text-sm font-semibold text-neutral-700">
            Linhas extraídas ({campos.length}) — {nAceitos} de {campos.length} aceitas para o export
          </h2>
        </div>

        {campos.length > 0 && !tudoAceito && aceitarAction && (
          <form action={aceitarAction} className="mb-4 flex items-center gap-3 rounded border border-amber-200 bg-amber-50 p-3">
            <input type="hidden" name="documento_versao_id" value={versao!.id} />
            <input
              type="text"
              name="motivo"
              placeholder="Motivo/observação (opcional)"
              className="flex-1 rounded border border-neutral-300 px-2 py-1.5 text-sm"
            />
            <button
              type="submit"
              className="whitespace-nowrap rounded bg-neutral-900 px-3 py-1.5 text-sm font-medium text-white hover:bg-neutral-800"
            >
              Aceitar estes dados para a base
            </button>
          </form>
        )}
        {tudoAceito && (
          <p className="mb-4 rounded border border-emerald-200 bg-emerald-50 px-3 py-2 text-sm text-emerald-800">
            ✓ Todas as linhas foram aceitas — já entram no export como fato.
          </p>
        )}

        {campos.length === 0 ? (
          <p className="text-sm text-neutral-500">Nenhuma linha extraída para este documento ainda.</p>
        ) : (
          <div className="space-y-6">
            {[...grupos.entries()].map(([secao, linhas]) => (
              <div key={secao} className="overflow-x-auto rounded border border-neutral-200 bg-white">
                <p className="border-b border-neutral-200 bg-neutral-50 px-3 py-1.5 text-xs font-semibold uppercase text-neutral-600">
                  {secao}
                </p>
                <table className="w-full text-left text-sm">
                  <thead className="text-xs uppercase text-neutral-500">
                    <tr>
                      <th className="px-3 py-1.5">Rótulo</th>
                      <th className="px-3 py-1.5 text-right">Valor</th>
                      <th className="px-3 py-1.5">Página</th>
                      <th className="px-3 py-1.5">Confiança</th>
                      <th className="px-3 py-1.5">Status</th>
                    </tr>
                  </thead>
                  <tbody className="divide-y divide-neutral-100">
                    {linhas.map((linha) => {
                      const ehTotal = /total/i.test(linha.chave);
                      const aceito = linha.status_aceite === "aceito";
                      return (
                        <tr key={linha.id} className={ehTotal ? "font-semibold" : ""}>
                          <td className="px-3 py-1.5">
                            {linha.chave}
                            {linha.entidade_coluna && (
                              <span className="ml-1 text-xs font-normal text-neutral-500">
                                ({linha.entidade_coluna})
                              </span>
                            )}
                            {linha.periodo_coluna && (
                              <span className="ml-1 text-xs font-normal text-neutral-400">
                                [{linha.periodo_coluna}]
                              </span>
                            )}
                          </td>
                          <td className="px-3 py-1.5 text-right font-mono">
                            {formatValor(linha.valor_num, linha.valor_texto, linha.unidade)}
                          </td>
                          <td className="px-3 py-1.5 text-neutral-500">{linha.origem_pagina ?? "—"}</td>
                          <td className="px-3 py-1.5 text-neutral-500">
                            {linha.confianca != null ? `${Math.round(linha.confianca * 100)}%` : "—"}
                          </td>
                          <td className="px-3 py-1.5">
                            <span
                              className={`rounded px-1.5 py-0.5 text-xs font-medium uppercase ${
                                aceito ? "bg-emerald-100 text-emerald-700" : "bg-amber-100 text-amber-700"
                              }`}
                              title={aceito && linha.aceito_por ? `Aceito por ${linha.aceito_por}` : ""}
                            >
                              {aceito ? "aceito" : "pendente"}
                            </span>
                          </td>
                        </tr>
                      );
                    })}
                  </tbody>
                </table>
              </div>
            ))}
          </div>
        )}
      </section>
    </div>
  );
}
