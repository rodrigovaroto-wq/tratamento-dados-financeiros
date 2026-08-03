import Link from "next/link";
import { notFound } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import {
  PENDENCIA_TIPOS_RECONCILIACAO,
  PENDENCIA_TIPOS_DIAGNOSTICO_REVISAVEIS,
  PENDENCIA_TIPOS_QUALIDADE_EXTRACAO,
  PENDENCIA_TIPO_ARQUIVO_ILEGIVEL,
  type Caso,
  type Documento,
  type Pendencia,
  type TaxonomiaTipoDocumento,
} from "@/lib/types";
import { CASO_STATUS_LABEL, CASO_STATUS_COLOR } from "@/lib/status";
import { aprovarCaso } from "./actions";
import { formatarPeriodo, formatarTipoTaxonomia } from "@/lib/export";

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

  const [casoRes, kitBasicoRes, documentosRes, pendenciasRes, checklistRes, portao2Res] = await Promise.all([
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
    // db/migrations/0036 — o checklist é a fonte do TERCEIRO estado: um item pode
    // ter documento e ainda assim não ter uma linha extraída
    // (`recebido_nao_valido`). Antes o dashboard derivava "presente" só da
    // existência do documento, e por isso ficava verde sobre um book vazio.
    supabase
      .from("checklist_item_status")
      .select("tipo_taxonomia, status")
      .eq("caso_id", id),
    // db/migrations/0037 — a avaliação do Portão 2. Determinística e sem efeito
    // colateral (a função é `stable`), então dá para chamar a cada render: é a
    // MESMA função que `fn_aprovar_caso` usa para decidir, e não uma segunda
    // implementação da regra aqui no portal.
    supabase.rpc("fn_avaliar_portao2", { p_caso_id: id }),
  ]);

  if (casoRes.error || !casoRes.data) {
    notFound();
  }

  const caso = casoRes.data as Caso;
  const kitBasico = (kitBasicoRes.data as TaxonomiaTipoDocumento[] | null) ?? [];
  const documentos = (documentosRes.data as unknown as Documento[] | null) ?? [];
  const pendencias = (pendenciasRes.data as Pendencia[] | null) ?? [];

  const tiposPresentes = new Set(documentos.map((d) => d.tipo_taxonomia).filter(Boolean));
  // Chegou, mas não rendeu uma linha: nem verde nem faltante — é o
  // `recebido_nao_valido` de `docs/07`, e é bloqueante para o Portão 2.
  const portao2 = portao2Res.data as {
    elegivel: boolean; motivos: string[]; ressalvas_ativas: number; teto_ressalvas: number;
    status_atual: string;
  } | null;
  const checklist = (checklistRes.data as Array<{ tipo_taxonomia: string; status: string }> | null) ?? [];
  const tiposSemConteudo = new Set(
    checklist.filter((c) => c.status === "recebido_nao_valido").map((c) => c.tipo_taxonomia),
  );
  const pendenciasRevisao = pendencias.filter((p) =>
    (PENDENCIA_TIPOS_DIAGNOSTICO_REVISAVEIS as readonly string[]).includes(p.tipo),
  );
  const pendenciasReconciliacao = pendencias.filter((p) =>
    (PENDENCIA_TIPOS_RECONCILIACAO as readonly string[]).includes(p.tipo),
  );
  const pendenciasArquivo = pendencias.filter((p) => p.tipo === PENDENCIA_TIPO_ARQUIVO_ILEGIVEL);
  const pendenciasExtracao = pendencias.filter((p) =>
    (PENDENCIA_TIPOS_QUALIDADE_EXTRACAO as readonly string[]).includes(p.tipo),
  );

  return (
    <div className="space-y-8">
      <div className="flex items-start justify-between">
        <div>
          <h1 className="text-lg font-semibold">{caso.nome}</h1>
          <p className="text-xs text-neutral-500">{caso.produto}</p>
        </div>
        <div className="flex items-center gap-3">
          <Link
            href={`/casos/${id}/adicionar`}
            className="rounded bg-neutral-900 px-3 py-1.5 text-sm font-medium text-white hover:bg-neutral-700"
          >
            + Adicionar arquivos
          </Link>
          {/* DOIS EXPORTS (decisão do dono). "Dados" é insumo de conferência e fica
              disponível desde a ingestão, mesmo com pendência aberta — é o que
              permite conferir a extração antes de modelar. "Completo" acrescenta a
              Modelagem projetada. */}
          {/* A seção Modelagem (Fase 7.3): onde as linhas do caso cruzam com as
              premissas. Fica ao lado dos exports de propósito — é o passo ENTRE
              conferir os dados e gerar o completo. */}
          <Link
            href={`/casos/${id}/modelagem`}
            className="rounded border border-indigo-300 bg-indigo-50 px-3 py-1.5 text-sm font-medium text-indigo-800 hover:bg-indigo-100"
          >
            Modelagem
          </Link>
          <a
            href={`/casos/${id}/export?modo=dados`}
            className="rounded border border-neutral-300 bg-white px-3 py-1.5 text-sm font-medium text-neutral-700 hover:bg-neutral-50"
            title="Todas as abas de dado, linha a linha, sem modelagem. Serve para conferir a extração contra os documentos."
          >
            Exportar dados ↓
          </a>
          <a
            href={`/casos/${id}/export`}
            className="rounded border border-neutral-300 bg-white px-3 py-1.5 text-sm font-medium text-neutral-700 hover:bg-neutral-50"
            title="Dados + Modelagem projetada."
          >
            Exportar completo ↓
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

      {/* PORTÃO 2 (db/migrations/0037) — a regra de f0/04, visível.
          Antes desta tela não havia como saber se um caso podia ser aprovado:
          a regra não existia em código, e "não implementado" tem a mesma
          aparência de "sem pendência bloqueante" para quem olha o dashboard. */}
      {portao2 && (
        <div
          className={`rounded border p-3 text-sm ${
            portao2.elegivel
              ? "border-emerald-300 bg-emerald-50"
              : "border-neutral-300 bg-neutral-50"
          }`}
        >
          <div className="flex flex-wrap items-center justify-between gap-3">
            <div>
              <p className={`font-medium ${portao2.elegivel ? "text-emerald-900" : "text-neutral-800"}`}>
                Portão 2 —{" "}
                {portao2.elegivel ? "elegível a aprovação" : "não elegível"}
              </p>
              {!portao2.elegivel && portao2.motivos?.length > 0 && (
                <ul className="mt-1 list-disc pl-5 text-neutral-700">
                  {portao2.motivos.map((m) => (
                    <li key={m}>{m}</li>
                  ))}
                </ul>
              )}
              <p className="mt-1 text-xs text-neutral-500">
                Ressalvas ativas: {portao2.ressalvas_ativas} de {portao2.teto_ressalvas} (teto por
                caso, f0/04). A regra é determinística e não tem exceção por autor.
              </p>
            </div>
            {portao2.elegivel && caso.status !== "aprovado" && caso.status !== "pronto_para_base" && (
              <form action={aprovarCaso.bind(null, id)} className="flex items-center gap-2">
                <input
                  type="text"
                  name="motivo"
                  placeholder="motivo (opcional)"
                  className="rounded border border-neutral-300 px-2 py-1 text-sm"
                />
                <button
                  type="submit"
                  className="rounded bg-emerald-700 px-3 py-1.5 text-sm font-medium text-white hover:bg-emerald-600"
                >
                  Aprovar caso
                </button>
              </form>
            )}
          </div>
        </div>
      )}

      <section>
        <h2 className="mb-2 text-sm font-semibold text-neutral-700">Kit Básico (obrigatórios)</h2>
        <ul className="grid grid-cols-1 gap-2 sm:grid-cols-2">
          {kitBasico.map((item) => {
            const semConteudo = tiposSemConteudo.has(item.codigo);
            // TRÊS estados, não dois (0036): verde só quando chegou E rendeu
            // linha. O documento que chegou vazio fica âmbar — não verde, porque
            // o book sai vazio nessa parte, e não "faltante", porque o arquivo
            // está lá e pedi-lo de novo ao cliente seria pedir o que ele mandou.
            const presente = tiposPresentes.has(item.codigo) && !semConteudo;
            const cor = presente
              ? "border-emerald-200 bg-emerald-50"
              : semConteudo
                ? "border-amber-300 bg-amber-50"
                : "border-neutral-200 bg-white";
            const corTexto = presente
              ? "text-emerald-700"
              : semConteudo
                ? "text-amber-800"
                : "text-neutral-400";
            return (
              <li
                key={item.codigo}
                className={`flex items-center justify-between gap-3 rounded border px-3 py-2 text-sm ${cor}`}
              >
                <span>{item.documento}</span>
                <span className={`shrink-0 ${corTexto}`}>
                  {presente
                    ? "✓ presente"
                    : semConteudo
                      ? "recebido, sem conteúdo extraído"
                      : "faltante"}
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
                      <td className="px-3 py-2">{formatarTipoTaxonomia(doc.tipo_taxonomia)}</td>
                      <td className="px-3 py-2">{doc.entidade?.razao_social ?? "—"}</td>
                      <td className="px-3 py-2">
                        {doc.periodo ? formatarPeriodo(doc.periodo.tipo, doc.periodo.referencia) : "—"}
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
          Reconciliação (Classe A/B) ({pendenciasReconciliacao.length})
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

      {pendenciasExtracao.length > 0 && (
        <section>
          <h2 className="mb-2 text-sm font-semibold text-neutral-700">
            Qualidade da extração ({pendenciasExtracao.length})
          </h2>
          <ul className="space-y-2">
            {pendenciasExtracao.map((p) => (
              <li
                key={p.id}
                className="rounded border border-red-200 bg-red-50 px-3 py-2 text-sm text-red-900"
              >
                <span className="mr-2 rounded bg-red-100 px-1.5 py-0.5 text-xs font-medium uppercase text-red-800">
                  {p.tipo === "extracao_falhou" ? "extração falhou" : "revisar"}
                </span>
                {p.descricao ?? "(sem descrição)"}
              </li>
            ))}
          </ul>
        </section>
      )}
    </div>
  );
}
