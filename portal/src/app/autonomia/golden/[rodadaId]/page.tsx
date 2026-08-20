import Link from "next/link";
import { notFound } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { IncluirDocumento } from "@/components/golden-incluir";
import { CongelarRodada } from "@/components/golden-congelar";

// O DETALHE DA RODADA: quanto falta, o que já entrou, o que pode entrar.
//
// A TABELA DE PROGRESSO TRAZ DUAS CONTAGENS, e a diferença entre elas é
// informação, não redundância. "Rotulados" agrupa pelo tipo que a MÁQUINA diz —
// é a etiqueta que existe na hora de escolher documentos. "Pela verdade" agrupa
// pelo consenso humano, e é essa que o portão do dial conta. Quando as duas
// divergem, o que está aparecendo é o erro de classificação: a máquina achou que
// eram 12 balanços e o consenso diz que eram 10.

type Rodada = {
  id: string;
  nome: string;
  taxonomia_versao: number;
  congelada_em: string | null;
  congelada_por: string | null;
  criada_por: string | null;
};

type Progresso = {
  tipo: string;
  tipo_nome: string | null;
  obrigatoriedade: string | null;
  n_incluidos: number;
  n_rotulados: number;
  n_rotulados_verdade: number;
  n_minimo: number;
  falta: number;
};

type Candidato = {
  documento_id: string;
  caso_id: string;
  caso_nome: string;
  nome_original: string | null;
  tipo_maquina: string | null;
  tipo_nome: string | null;
  obrigatoriedade: string | null;
  legibilidade: string | null;
  n_linhas: number;
  estrato_sugerido: string | null;
  estrato_porque: string | null;
  ja_na_rodada: boolean;
  ja_rotulado: boolean;
};

export default async function RodadaPage({
  params,
}: {
  params: Promise<{ rodadaId: string }>;
}) {
  const { rodadaId } = await params;
  const supabase = await createClient();

  const { data: rodadaBruta, error } = await supabase
    .from("golden_rodada")
    .select("id, nome, taxonomia_versao, congelada_em, congelada_por, criada_por")
    .eq("id", rodadaId)
    .single();

  if (error || !rodadaBruta) notFound();
  const rodada = rodadaBruta as Rodada;
  const congelada = rodada.congelada_em !== null;

  const [{ data: progBruto }, { data: candBruto }] = await Promise.all([
    supabase.rpc("fn_golden_progresso", { p_rodada: rodadaId }),
    supabase.rpc("fn_golden_candidatos", { p_rodada: rodadaId }),
  ]);

  const progresso = (progBruto as Progresso[] | null) ?? [];
  const candidatos = (candBruto as Candidato[] | null) ?? [];
  const dentro = candidatos.filter((c) => c.ja_na_rodada);
  const fora = candidatos.filter((c) => !c.ja_na_rodada);

  return (
    <div className="space-y-6">
      <div>
        <Link href="/autonomia/golden" className="text-sm text-tinta-500 underline">
          ← Rodadas
        </Link>
        <div className="mt-2 flex flex-wrap items-baseline gap-2">
          <h1 className="text-lg font-semibold">{rodada.nome}</h1>
          <span
            className={
              congelada
                ? "rounded bg-tinta-900 px-1.5 py-0.5 text-xs font-medium text-white"
                : "rounded bg-amber-100 px-1.5 py-0.5 text-xs font-medium text-amber-900"
            }
          >
            {congelada ? "congelada" : "em montagem"}
          </span>
          <span className="text-xs text-tinta-500">taxonomia v{rodada.taxonomia_versao}</span>
        </div>
        {congelada && (
          <p className="mt-1 text-sm text-tinta-600">
            Congelada por {rodada.congelada_por ?? "—"}. Não aceita mais documento nem rótulo —
            ampliar é rodada nova.
          </p>
        )}
      </div>

      {progresso.length > 0 && (
        <div className="overflow-x-auto rounded border border-tinta-200 bg-white">
          <table className="w-full text-sm">
            <caption className="px-4 pt-2 text-left text-xs text-tinta-500">
              Progresso por tipo. <strong>Rotulados</strong> conta pelo tipo que a máquina diz —
              é a etiqueta que existe na hora de escolher. <strong>Pela verdade</strong> conta
              pelo consenso humano, e é essa que o portão do dial usa. Divergirem não é defeito:
              é o erro de classificação aparecendo.
            </caption>
            <thead className="bg-tinta-50 text-left text-xs uppercase text-tinta-500">
              <tr>
                <th className="px-4 py-2 font-medium">Tipo</th>
                <th className="px-4 py-2 font-medium">Incluídos</th>
                <th className="px-4 py-2 font-medium">Rotulados</th>
                <th className="px-4 py-2 font-medium">Pela verdade</th>
                <th className="px-4 py-2 font-medium">Falta</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-tinta-200">
              {progresso.map((p) => (
                <tr key={p.tipo ?? "sem-tipo"}>
                  <td className="px-4 py-2">
                    <p className="font-mono text-xs">{p.tipo ?? "(sem tipo)"}</p>
                    {p.obrigatoriedade && (
                      <p className="text-xs text-tinta-500">{p.obrigatoriedade}</p>
                    )}
                  </td>
                  <td className="px-4 py-2 text-xs text-tinta-600">{p.n_incluidos}</td>
                  <td className="px-4 py-2 text-xs text-tinta-600">{p.n_rotulados}</td>
                  <td className="px-4 py-2 text-xs">
                    <span
                      className={
                        p.n_rotulados_verdade !== p.n_rotulados
                          ? "text-amber-800"
                          : "text-tinta-600"
                      }
                    >
                      {p.n_rotulados_verdade}
                      {p.n_rotulados_verdade !== p.n_rotulados && " ⚠"}
                    </span>
                  </td>
                  <td className="px-4 py-2 text-xs">
                    <span className={p.falta === 0 ? "text-emerald-700" : "text-amber-800"}>
                      {p.falta === 0 ? "✓ bate o mínimo" : `${p.falta} de ${p.n_minimo}`}
                    </span>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}

      <section>
        <h2 className="text-sm font-semibold text-tinta-700">
          Documentos da rodada ({dentro.length})
        </h2>
        {dentro.length === 0 ? (
          <p className="mt-2 text-sm text-tinta-500">
            Nenhum documento ainda. Escolha abaixo, declarando estrato e origem.
          </p>
        ) : (
          <ul className="mt-2 divide-y divide-tinta-200 rounded border border-tinta-200 bg-white">
            {dentro.map((c) => (
              <li key={c.documento_id} className="flex flex-wrap items-baseline gap-2 px-4 py-2">
                {congelada ? (
                  <span className="text-sm">{c.nome_original ?? "(sem nome)"}</span>
                ) : (
                  <Link
                    href={`/autonomia/golden/${rodadaId}/${c.documento_id}`}
                    className="text-sm underline"
                  >
                    {c.nome_original ?? "(sem nome)"}
                  </Link>
                )}
                <span className="font-mono text-xs text-tinta-500">
                  {c.tipo_maquina ?? "(sem tipo)"}
                </span>
                <span className="text-xs text-tinta-500">
                  {c.caso_nome} · {c.n_linhas} linha(s) extraída(s)
                </span>
                <span
                  className={
                    c.ja_rotulado
                      ? "rounded bg-emerald-100 px-1.5 py-0.5 text-xs font-medium text-emerald-800"
                      : "rounded bg-tinta-100 px-1.5 py-0.5 text-xs font-medium text-tinta-600"
                  }
                >
                  {c.ja_rotulado ? "rotulado" : "a rotular"}
                </span>
              </li>
            ))}
          </ul>
        )}
      </section>

      {!congelada && (
        <>
          <IncluirDocumento rodadaId={rodadaId} candidatos={fora} />
          <CongelarRodada rodadaId={rodadaId} />
        </>
      )}
    </div>
  );
}
