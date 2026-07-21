import Link from "next/link";
import { createClient } from "@/lib/supabase/server";
import { PENDENCIA_TIPOS_DIAGNOSTICO_REVISAVEIS, type TaxonomiaTipoDocumento } from "@/lib/types";
import { revisarDocumento } from "./actions";

const PENDENCIA_TIPO_LABEL: Record<string, string> = {
  classificacao_pendente: "classificação incerta",
  tipo_incorreto: "tipo pode estar incorreto",
  entidade_incorreta: "entidade pode estar incorreta",
  periodo_incorreto: "período pode estar incorreto",
};

interface PendenciaComDocumento {
  id: string;
  tipo: string;
  descricao: string | null;
  criada_em: string;
  documento: {
    id: string;
    tipo_taxonomia: string | null;
    confianca: number | null;
    fonte: string | null;
    justificativa: string | null;
    entidade: { razao_social: string } | null;
    periodo: { tipo: string; referencia: string } | null;
    documento_versao: Array<{ nome_original: string | null }> | null;
  } | null;
}

export default async function FilaRevisaoPage({
  params,
}: {
  params: Promise<{ id: string }>;
}) {
  const { id } = await params;
  const supabase = await createClient();

  const [pendenciasRes, taxonomiaRes] = await Promise.all([
    supabase
      .from("pendencia")
      .select(
        `id, tipo, descricao, criada_em,
         documento:documento_id(
           id, tipo_taxonomia, confianca, fonte, justificativa,
           entidade:entidade_id(razao_social), periodo:periodo_id(tipo, referencia),
           documento_versao(nome_original)
         )`,
      )
      .eq("caso_id", id)
      .in("tipo", PENDENCIA_TIPOS_DIAGNOSTICO_REVISAVEIS)
      .eq("estado", "aberta")
      .order("criada_em", { ascending: true }),
    supabase.from("taxonomia_tipo_documento").select("codigo, categoria, documento, obrigatoriedade").order("codigo"),
  ]);

  const pendencias = (pendenciasRes.data as unknown as PendenciaComDocumento[] | null) ?? [];
  const taxonomia = (taxonomiaRes.data as TaxonomiaTipoDocumento[] | null) ?? [];

  const revisarAction = revisarDocumento.bind(null, id);

  return (
    <div className="space-y-6">
      <div>
        <Link href={`/casos/${id}`} className="text-sm text-neutral-500 underline">
          ← Voltar ao caso
        </Link>
        <h1 className="mt-2 text-lg font-semibold">Fila de revisão — classificação e diagnóstico</h1>
        <p className="text-sm text-neutral-500">
          Confirme ou corrija a sugestão (classificação por nome/conteúdo, ou divergência
          apontada pelo diagnóstico de conteúdo). Nada entra na base sem essa decisão (anti-ancoragem).
        </p>
      </div>

      {pendenciasRes.error && (
        <p className="rounded border border-red-300 bg-red-50 p-3 text-sm text-red-700">
          Erro ao carregar pendências: {pendenciasRes.error.message}
        </p>
      )}

      {pendencias.length === 0 && !pendenciasRes.error && (
        <p className="text-sm text-neutral-500">Nenhuma pendência de revisão aberta. 🎉</p>
      )}

      <ul className="space-y-4">
        {pendencias.map((p) => {
          const doc = p.documento;
          if (!doc) return null;
          const nomeArquivo = doc.documento_versao?.[0]?.nome_original ?? "(sem nome)";

          return (
            <li key={p.id} className="rounded border border-neutral-200 bg-white p-4">
              <div className="mb-3">
                <p className="text-sm font-medium">
                  {nomeArquivo}
                  <span className="ml-2 rounded bg-amber-100 px-1.5 py-0.5 text-xs font-medium uppercase text-amber-800">
                    {PENDENCIA_TIPO_LABEL[p.tipo] ?? p.tipo}
                  </span>
                </p>
                <p className="mt-1 text-xs text-neutral-500">{p.descricao}</p>
              </div>

              <form action={revisarAction} className="grid grid-cols-1 gap-3 sm:grid-cols-2">
                <input type="hidden" name="documento_id" value={doc.id} />

                <div>
                  <label className="block text-xs font-medium text-neutral-600">Tipo (taxonomia)</label>
                  <select
                    name="novo_tipo_taxonomia"
                    defaultValue={doc.tipo_taxonomia ?? ""}
                    className="mt-1 w-full rounded border border-neutral-300 px-2 py-1.5 text-sm"
                  >
                    <option value="">— sem tipo —</option>
                    {taxonomia.map((t) => (
                      <option key={t.codigo} value={t.codigo}>
                        {t.documento} ({t.codigo})
                      </option>
                    ))}
                  </select>
                </div>

                <div>
                  <label className="block text-xs font-medium text-neutral-600">Entidade</label>
                  <input
                    type="text"
                    name="nova_entidade_nome"
                    defaultValue={doc.entidade?.razao_social ?? ""}
                    placeholder="Razão social"
                    className="mt-1 w-full rounded border border-neutral-300 px-2 py-1.5 text-sm"
                  />
                </div>

                <div>
                  <label className="block text-xs font-medium text-neutral-600">Período — tipo</label>
                  <select
                    name="novo_periodo_tipo"
                    defaultValue={doc.periodo?.tipo ?? "anual"}
                    className="mt-1 w-full rounded border border-neutral-300 px-2 py-1.5 text-sm"
                  >
                    <option value="anual">anual</option>
                    <option value="trimestre">trimestre</option>
                    <option value="multi">multi</option>
                    <option value="data-base">data-base</option>
                    <option value="outro">outro</option>
                  </select>
                </div>

                <div>
                  <label className="block text-xs font-medium text-neutral-600">Período — referência</label>
                  <input
                    type="text"
                    name="novo_periodo_ref"
                    defaultValue={doc.periodo?.referencia ?? ""}
                    placeholder="ex.: 12M25, 2025"
                    className="mt-1 w-full rounded border border-neutral-300 px-2 py-1.5 text-sm"
                  />
                </div>

                <div className="sm:col-span-2">
                  <label className="block text-xs font-medium text-neutral-600">Motivo / observação</label>
                  <textarea
                    name="motivo"
                    rows={2}
                    placeholder="Opcional — por que confirmou ou corrigiu"
                    className="mt-1 w-full rounded border border-neutral-300 px-2 py-1.5 text-sm"
                  />
                </div>

                <div className="sm:col-span-2 flex items-center justify-between text-xs text-neutral-500">
                  <span>
                    Sugestão atual: <strong>{doc.tipo_taxonomia ?? "sem tipo"}</strong>
                    {doc.confianca != null && ` · confiança ${Math.round(doc.confianca * 100)}%`}
                    {doc.fonte && ` · fonte ${doc.fonte}`}
                  </span>
                  <button
                    type="submit"
                    className="rounded bg-neutral-900 px-3 py-1.5 font-medium text-white hover:bg-neutral-800"
                  >
                    Confirmar / salvar
                  </button>
                </div>
              </form>
            </li>
          );
        })}
      </ul>
    </div>
  );
}
