import Link from "next/link";
import { notFound } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { paginar } from "@/lib/supabase/paginar";
import type { CampoExtraido, Documento } from "@/lib/types";
import { formatarPeriodo, formatarTipoTaxonomia } from "@/lib/export";
import { aceitarExtracao } from "./actions";
import { ClasseContabil } from "@/components/classe-contabil";

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
    ? await paginar<CampoExtraido>((de, ate) =>
        supabase
          .from("campo_extraido")
          .select(
            "id, documento_versao_id, secao, entidade_coluna, periodo_coluna, chave, valor_texto, valor_num, unidade, confianca, origem_pagina, status_aceite, aceito_por, aceito_em",
          )
          .eq("documento_versao_id", versao.id)
          // Paginado: um documento denso passa de mil linhas (o livro razão do
          // book tem 461 células numa coluna só, e um razão real vai muito além),
          // e o teto do PostgREST corta em silêncio — a tela mostraria parte da
          // extração como se fosse toda ela.
          .order("origem_pagina", { ascending: true, nullsFirst: false })
          .order("criado_em", { ascending: true })
          .order("id", { ascending: true })
          .range(de, ate))
    : { data: [] as CampoExtraido[], error: null, truncado: false };

  const campos = camposRes.data;

  // A CLASSIFICAÇÃO CONTÁBIL DESTAS LINHAS (0128), em duas leituras de catálogo.
  //
  // Por que aqui e não por linha: uma chamada por linha seriam centenas de idas ao
  // banco numa página que já pagina as linhas justamente porque um razão real
  // passa de mil. As duas consultas abaixo trazem tudo de uma vez e são casadas em
  // memória.
  //
  // Ambas são CATÁLOGO ou escopo de versão — não crescem com a mesa —, então não
  // paginam, pela mesma regra das outras listas de catálogo do portal.
  const [classesRes, sugRes, ovrRes] = await Promise.all([
    supabase
      .from("classe_contabil_catalogo")
      .select("codigo, nome")
      .eq("ativo", true)
      .order("ordem"),
    supabase
      .from("campo_classe_sugerida")
      .select("campo_extraido_id, classe_codigo, justificativa, criado_em")
      .in("campo_extraido_id", campos.map((c) => c.id).slice(0, 1000))
      .order("criado_em", { ascending: true }),
    supabase
      .from("campo_classe_override")
      .select("campo_extraido_id, classe_final, autor, criado_em")
      .in("campo_extraido_id", campos.map((c) => c.id).slice(0, 1000))
      .order("criado_em", { ascending: true }),
  ]);

  const classes = (classesRes.data as { codigo: string; nome: string }[] | null) ?? [];
  // A ÚLTIMA de cada linha é a que vale, nas duas tabelas: as duas são append-only,
  // então reclassificar acrescenta em vez de substituir. Ordenado crescente acima e
  // sobrescrevendo no laço, a última leitura ganha — que é a mais recente.
  const sugestaoDe = new Map<string, { classe: string; justificativa: string }>();
  for (const r of (sugRes.data ?? []) as {
    campo_extraido_id: string; classe_codigo: string; justificativa: string;
  }[]) {
    sugestaoDe.set(r.campo_extraido_id, {
      classe: r.classe_codigo,
      justificativa: r.justificativa,
    });
  }
  const overrideDe = new Map<string, { classe: string; autor: string }>();
  for (const r of (ovrRes.data ?? []) as {
    campo_extraido_id: string; classe_final: string; autor: string;
  }[]) {
    overrideDe.set(r.campo_extraido_id, { classe: r.classe_final, autor: r.autor });
  }
  const nClassificaveis = campos.filter((c) => sugestaoDe.has(c.id)).length;
  const nDecididas = campos.filter((c) => overrideDe.has(c.id)).length;

  const grupos = agruparPorSecao(campos);
  const nAceitos = campos.filter((c) => c.status_aceite === "aceito").length;
  const tudoAceito = campos.length > 0 && nAceitos === campos.length;
  const aceitarAction = versao ? aceitarExtracao.bind(null, id, docId) : null;

  return (
    <div className="space-y-6">
      <div>
        <Link href={`/casos/${id}`} className="text-sm text-tinta-500 underline">
          ← Voltar ao caso
        </Link>
        <h1 className="mt-2 text-lg font-semibold">{versao?.nome_original ?? "(sem nome)"}</h1>
        <p className="text-xs text-tinta-500">
          {formatarTipoTaxonomia(doc.tipo_taxonomia)}
          {doc.entidade?.razao_social ? ` · ${doc.entidade.razao_social}` : ""}
          {doc.periodo ? ` · ${formatarPeriodo(doc.periodo.tipo, doc.periodo.referencia)}` : ""}
        </p>
      </div>

      {versao?.legibilidade && versao.legibilidade !== "ok" && (
        <div className="rounded border border-red-300 bg-red-50 p-3 text-sm text-red-800">
          <strong className="uppercase">{versao.legibilidade}</strong>
          {versao.nota_legibilidade ? ` — ${versao.nota_legibilidade}` : ""}
        </div>
      )}

      {doc.resumo && (
        <div className="rounded border border-tinta-200 bg-tinta-50 p-3 text-sm text-tinta-600">
          <p className="mb-1 text-xs font-medium uppercase text-tinta-500">Resumo</p>
          {doc.resumo}
        </div>
      )}

      <section>
        <div className="mb-2 flex items-center justify-between">
          <h2 className="text-sm font-semibold text-tinta-600">
            Linhas extraídas ({campos.length}) — {nAceitos} de {campos.length} aceitas para o export
          </h2>
          {/* 0128: o contador da classificação contábil fica SEPARADO do de aceite,
              e não somado a ele, porque são duas decisões diferentes sobre a mesma
              linha: aceitar o NÚMERO e classificar a NATUREZA dele. Somá-las daria
              um "N de M decidido" que não corresponde a nada. */}
          {nClassificaveis > 0 && (
            <p className="text-xs text-tinta-500">
              Classe contábil: {nDecididas} de {nClassificaveis} decididas por humano
              {nClassificaveis < campos.length && (
                <span className="text-tinta-400">
                  {" "}
                  · {campos.length - nClassificaveis} linhas não são de resultado
                </span>
              )}
            </p>
          )}
        </div>

        {campos.length > 0 && !tudoAceito && aceitarAction && (
          <form action={aceitarAction} className="mb-4 flex items-center gap-3 rounded border border-amber-200 bg-amber-50 p-3">
            <input type="hidden" name="documento_versao_id" value={versao!.id} />
            <input
              type="text"
              name="motivo"
              placeholder="Motivo/observação (opcional)"
              className="flex-1 rounded border border-tinta-200 px-2 py-1.5 text-sm"
            />
            <button
              type="submit"
              className="whitespace-nowrap rounded bg-tinta-900 px-3 py-1.5 text-sm font-medium text-white hover:bg-tinta-800"
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
          // db/migrations/0036 — item 3 do §7.4. A mensagem antiga era "Nenhuma
          // linha extraída para este documento ainda", e o "ainda" fazia parecer
          // fila: quem lia esperava. Na prática, se a extração já rodou, este
          // documento NÃO tem nada no banco e sai vazio do book — e, sendo
          // obrigatório do Kit Básico, agora abre pendência bloqueante.
          <div className="rounded border border-amber-300 bg-amber-50 p-3 text-sm text-amber-900">
            <p className="font-medium">Nenhuma linha foi extraída deste documento.</p>
            <p className="mt-1">
              Se a extração já rodou, isto não é fila: não há nada deste arquivo no banco, e a parte
              dele no book sai vazia. Causas comuns — formato que o pipeline ainda não converte
              (.xlsx/.docx), arquivo ilegível, ou chamada de extração que falhou. Veja a pendência
              de extração deste documento e reenvie o arquivo. Não há o que aceitar aqui: aceitar
              gravaria uma aprovação formal de nada.
            </p>
          </div>
        ) : (
          <div className="space-y-6">
            {[...grupos.entries()].map(([secao, linhas]) => (
              <div key={secao} className="overflow-x-auto rounded border border-tinta-200 bg-white">
                <p className="border-b border-tinta-200 bg-tinta-50 px-3 py-1.5 text-xs font-semibold uppercase text-tinta-600">
                  {secao}
                </p>
                <table className="w-full text-left text-sm">
                  <thead className="text-xs uppercase text-tinta-500">
                    <tr>
                      <th className="px-3 py-1.5">Rótulo</th>
                      <th className="px-3 py-1.5 text-right">Valor</th>
                      <th className="px-3 py-1.5">Página</th>
                      <th className="px-3 py-1.5">Confiança</th>
                      <th className="px-3 py-1.5">Status</th>
                      <th className="px-3 py-1.5">Classe contábil</th>
                    </tr>
                  </thead>
                  <tbody className="divide-y divide-tinta-100">
                    {linhas.map((linha) => {
                      const ehTotal = /total/i.test(linha.chave);
                      const aceito = linha.status_aceite === "aceito";
                      return (
                        <tr key={linha.id} className={ehTotal ? "font-semibold" : ""}>
                          <td className="px-3 py-1.5">
                            {linha.chave}
                            {linha.entidade_coluna && (
                              <span className="ml-1 text-xs font-normal text-tinta-500">
                                ({linha.entidade_coluna})
                              </span>
                            )}
                            {linha.periodo_coluna && (
                              <span className="ml-1 text-xs font-normal text-tinta-400">
                                [{linha.periodo_coluna}]
                              </span>
                            )}
                          </td>
                          <td className="px-3 py-1.5 text-right font-mono">
                            {formatValor(linha.valor_num, linha.valor_texto, linha.unidade)}
                          </td>
                          <td className="px-3 py-1.5 text-tinta-500">{linha.origem_pagina ?? "—"}</td>
                          <td className="px-3 py-1.5 text-tinta-500">
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
                          <td className="px-3 py-1.5 align-top font-normal">
                            <ClasseContabil
                              casoId={id}
                              docId={docId}
                              campoId={linha.id}
                              classes={classes}
                              sugestao={sugestaoDe.get(linha.id)?.classe ?? null}
                              justificativa={sugestaoDe.get(linha.id)?.justificativa ?? null}
                              override={overrideDe.get(linha.id)?.classe ?? null}
                              overridePor={overrideDe.get(linha.id)?.autor ?? null}
                            />
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
