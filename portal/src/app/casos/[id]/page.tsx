import Link from "next/link";
import { notFound } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import {
  PENDENCIA_TIPOS_RECONCILIACAO,
  PENDENCIA_TIPOS_DIAGNOSTICO_REVISAVEIS,
  PENDENCIA_TIPO_ARQUIVO_ILEGIVEL,
  type Caso,
  type Documento,
  type Pendencia,
  type TaxonomiaTipoDocumento,
} from "@/lib/types";
import { CASO_STATUS_LABEL, CASO_STATUS_COLOR } from "@/lib/status";

const LEGIBILIDADE_LABEL: Record<string, string> = {
  degradado: "qualidade degradada",
  ilegivel: "ilegível",
};

export default async function CasoDashboardPage({
  params,
}: {
  params: Promise<{ id: string }>;
}) {
  const { id } = await params;
  const supabase = await createClient();

  const [casoRes, kitBasicoRes, documentosRes, pendenciasRes] = await Promise.all([
    supabase.from("caso").select("id, nome, produto, status, criado_em").eq("id", id).single(),
    supabase
      .from("taxonomia_tipo_documento")
      .select("codigo, categoria, documento, obrigatoriedade")
      .eq("obrigatoriedade", "obrigatorio")
      .order("codigo"),
    supabase
      .from("documento")
      .select(
        `id, tipo_taxonomia, status, confianca, fonte, justificativa, resumo, criado_em,
         entidade:entidade_id(razao_social), periodo:periodo_id(tipo, referencia),
         documento_versao(id, nome_original, legibilidade, nota_legibilidade)`,
      )
      .eq("caso_id", id)
      .order("criado_em", { ascending: false }),
    supabase
      .from("pendencia")
      .select("id, tipo, severidade, estado, descricao, documento_id, caso_id, criada_em")
      .eq("caso_id", id)
      .eq("estado", "aberta")
      .order("criada_em", { ascending: false }),
  ]);

  if (casoRes.error || !casoRes.data) {
    notFound();
  }

  const caso = casoRes.data as Caso;
  const kitBasico = (kitBasicoRes.data as TaxonomiaTipoDocumento[] | null) ?? [];
  const documentos = (documentosRes.data as unknown as Documento[] | null) ?? [];
  const pendencias = (pendenciasRes.data as Pendencia[] | null) ?? [];

  const tiposPresentes = new Set(documentos.map((d) => d.tipo_taxonomia).filter(Boolean));
  const pendenciasRevisao = pendencias.filter((p) =>
    (PENDENCIA_TIPOS_DIAGNOSTICO_REVISAVEIS as readonly string[]).includes(p.tipo),
  );
  const pendenciasReconciliacao = pendencias.filter((p) =>
    (PENDENCIA_TIPOS_RECONCILIACAO as readonly string[]).includes(p.tipo),
  );
  const pendenciasArquivo = pendencias.filter((p) => p.tipo === PENDENCIA_TIPO_ARQUIVO_ILEGIVEL);

  return (
    <div className="space-y-8">
      <div className="flex items-start justify-between">
        <div>
          <h1 className="text-lg font-semibold">{caso.nome}</h1>
          <p className="text-xs text-neutral-500">{caso.produto}</p>
        </div>
        <div className="flex items-center gap-3">
          <a
            href={`/casos/${id}/export`}
            className="rounded border border-neutral-300 bg-white px-3 py-1.5 text-sm font-medium text-neutral-700 hover:bg-neutral-50"
          >
            Exportar para Excel ↓
          </a>
          <span className={`rounded-full px-2 py-1 text-xs font-medium ${CASO_STATUS_COLOR[caso.status]}`}>
            {CASO_STATUS_LABEL[caso.status]}
          </span>
        </div>
      </div>

      {pendenciasRevisao.length > 0 && (
        <div className="flex items-center justify-between rounded border border-amber-300 bg-amber-50 p-3 text-sm">
          <span className="text-amber-800">
            {pendenciasRevisao.length} documento(s) com pendência de revisão (classificação, entidade ou período).
          </span>
          <Link href={`/casos/${id}/revisao`} className="font-medium text-amber-900 underline">
            Ir para a fila de revisão →
          </Link>
        </div>
      )}

      <section>
        <h2 className="mb-2 text-sm font-semibold text-neutral-700">Kit Básico (obrigatórios)</h2>
        <ul className="grid grid-cols-1 gap-2 sm:grid-cols-2">
          {kitBasico.map((item) => {
            const presente = tiposPresentes.has(item.codigo);
            return (
              <li
                key={item.codigo}
                className={`flex items-center justify-between rounded border px-3 py-2 text-sm ${
                  presente ? "border-emerald-200 bg-emerald-50" : "border-neutral-200 bg-white"
                }`}
              >
                <span>{item.documento}</span>
                <span className={presente ? "text-emerald-700" : "text-neutral-400"}>
                  {presente ? "✓ presente" : "faltante"}
                </span>
              </li>
            );
          })}
        </ul>
      </section>

      <section>
        <h2 className="mb-2 text-sm font-semibold text-neutral-700">Documentos ({documentos.length})</h2>
        {documentos.length === 0 ? (
          <p className="text-sm text-neutral-500">Nenhum documento recebido ainda.</p>
        ) : (
          <div className="overflow-x-auto rounded border border-neutral-200 bg-white">
            <table className="w-full text-left text-sm">
              <thead className="bg-neutral-50 text-xs uppercase text-neutral-500">
                <tr>
                  <th className="px-3 py-2">Arquivo</th>
                  <th className="px-3 py-2">Tipo</th>
                  <th className="px-3 py-2">Entidade</th>
                  <th className="px-3 py-2">Período</th>
                  <th className="px-3 py-2">Confiança</th>
                  <th className="px-3 py-2">Fonte</th>
                  <th className="px-3 py-2">Resumo</th>
                  <th className="px-3 py-2"></th>
                </tr>
              </thead>
              <tbody className="divide-y divide-neutral-100">
                {documentos.map((doc) => {
                  const versao = doc.documento_versao?.[0];
                  const legibilidadeRuim = versao?.legibilidade && versao.legibilidade !== "ok";
                  return (
                    <tr key={doc.id}>
                      <td className="px-3 py-2">
                        {versao?.nome_original ?? "—"}
                        {legibilidadeRuim && (
                          <span
                            title={versao?.nota_legibilidade ?? ""}
                            className="ml-2 rounded bg-red-100 px-1.5 py-0.5 text-xs font-medium uppercase text-red-700"
                          >
                            {LEGIBILIDADE_LABEL[versao!.legibilidade!] ?? versao!.legibilidade}
                          </span>
                        )}
                      </td>
                      <td className="px-3 py-2">{doc.tipo_taxonomia ?? "não classificado"}</td>
                      <td className="px-3 py-2">{doc.entidade?.razao_social ?? "—"}</td>
                      <td className="px-3 py-2">
                        {doc.periodo ? `${doc.periodo.tipo} ${doc.periodo.referencia}` : "—"}
                      </td>
                      <td className="px-3 py-2">
                        {doc.confianca != null ? `${Math.round(doc.confianca * 100)}%` : "—"}
                      </td>
                      <td className="px-3 py-2 text-xs text-neutral-500">{doc.fonte ?? "—"}</td>
                      <td className="max-w-xs truncate px-3 py-2 text-xs text-neutral-500" title={doc.resumo ?? ""}>
                        {doc.resumo ?? "—"}
                      </td>
                      <td className="px-3 py-2 text-xs">
                        <Link href={`/casos/${id}/documentos/${doc.id}`} className="text-neutral-600 underline">
                          ver linhas →
                        </Link>
                      </td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
          </div>
        )}
      </section>

      <section>
        <h2 className="mb-2 text-sm font-semibold text-neutral-700">
          Reconciliação (Classe A) ({pendenciasReconciliacao.length})
        </h2>
        {pendenciasReconciliacao.length === 0 ? (
          <p className="text-sm text-neutral-500">
            Nenhuma divergência ou pré-condição pendente no momento.
          </p>
        ) : (
          <ul className="space-y-2">
            {pendenciasReconciliacao.map((p) => (
              <li
                key={p.id}
                className="rounded border border-amber-200 bg-amber-50 px-3 py-2 text-sm text-amber-900"
              >
                <span className="mr-2 rounded bg-amber-100 px-1.5 py-0.5 text-xs font-medium uppercase text-amber-800">
                  {p.tipo === "precondicao_nao_satisfeita" ? "pré-condição" : "divergência"}
                </span>
                {p.descricao ?? "(sem descrição)"}
              </li>
            ))}
          </ul>
        )}
      </section>

      {pendenciasArquivo.length > 0 && (
        <section>
          <h2 className="mb-2 text-sm font-semibold text-neutral-700">
            Qualidade dos arquivos ({pendenciasArquivo.length})
          </h2>
          <ul className="space-y-2">
            {pendenciasArquivo.map((p) => (
              <li
                key={p.id}
                className="rounded border border-red-200 bg-red-50 px-3 py-2 text-sm text-red-900"
              >
                {p.descricao ?? "(sem descrição)"}
              </li>
            ))}
          </ul>
        </section>
      )}
    </div>
  );
}
