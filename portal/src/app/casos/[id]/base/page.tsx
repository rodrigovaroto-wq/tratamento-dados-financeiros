import Link from "next/link";
import { notFound } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { paginar } from "@/lib/supabase/paginar";
import type { CampoExtraido } from "@/lib/types";
import {
  chaveCronologicaPeriodo, consolidarNomesDeEntidade, entidadePeriodoDaLinha,
  formatarPeriodo, formatarTipoTaxonomia, versoesVigentes,
  type DocumentoParaExport,
} from "@/lib/export";

// A BASE VIVA — o Modo A do `f0/07`, que era o modo declarado PRINCIPAL e não
// existia em tela nenhuma.
//
// O que o spec pede, literal: *"o analista acessa o portal e consulta/filtra os
// dados curados na tela, por Entidade × Período × Conta/linha financeira"*, e
// *"cada valor exibido carrega sua proveniência e seu status de aceite"*. Até aqui
// o portal tinha a tela de UM documento (as linhas daquele arquivo) e o export
// (todas as linhas, dentro de um `.xlsx`). Perguntar "o que a base diz sobre
// Estoques na Alfa em 2024" exigia abrir os documentos um a um ou baixar o arquivo
// — que é justamente o Modo B.
//
// ESTA TELA NÃO SOMA, E ISSO É A DECISÃO CENTRAL DELA.
//
// Consolidar demonstração é difícil de um jeito que não aparece: subtotal impresso
// que não pode entrar na soma, conta sem vocabulário que herda a seção dos irmãos,
// escalas diferentes no mesmo caso, o mesmo rótulo sendo subtotal num documento e
// conta-folha em outro. O export paga esse preço com 568 verificações atrás dele.
// Uma tela que somasse "para ficar mais útil" produziria um SEGUNDO total para a
// mesma pergunta, mais fraco — e o defeito que este sistema mais persegue é
// exatamente dois números para o mesmo fato. Então aqui não há total, não há AV%, e
// não há conversão de escala: cada linha aparece como o documento a trouxe, com a
// unidade ao lado. O consolidado é do arquivo, e a tela diz isso com palavra.
//
// O QUE ELA FAZ QUE O ARQUIVO NÃO FAZ: responder rápido, com a proveniência de cada
// número à mão, e sobre a base VIVA — inclusive as linhas pendentes de aceite, que
// o export por doutrina não trata como fato.

const TETO_LINHAS = 500;

function Chip({
  href, ativo, children,
}: { href: string; ativo: boolean; children: React.ReactNode }) {
  return (
    <Link
      href={href}
      className={`rounded-full border px-2.5 py-0.5 text-xs ${
        ativo
          ? "border-tinta-900 bg-tinta-900 text-white"
          : "border-tinta-300 bg-white text-tinta-600 hover:bg-tinta-50"
      }`}
    >
      {children}
    </Link>
  );
}

export default async function BaseVivaPage({
  params,
  searchParams,
}: {
  params: Promise<{ id: string }>;
  searchParams: Promise<{ entidade?: string; periodo?: string; q?: string; status?: string }>;
}) {
  const { id } = await params;
  const filtro = await searchParams;
  const supabase = await createClient();

  const [casoRes, documentosRes] = await Promise.all([
    supabase.from("caso").select("id, nome").eq("id", id).single(),
    paginar<DocumentoParaExport>((de, ate) =>
      supabase
        .from("documento")
        .select(
          `id, tipo_taxonomia,
           entidade:entidade_id(razao_social), periodo:periodo_id(tipo, referencia),
           documento_versao(id, nome_original, n_versao)`,
        )
        .eq("caso_id", id)
        .order("id", { ascending: true })
        .range(de, ate),
    ),
  ]);

  if (casoRes.error || !casoRes.data) notFound();
  const caso = casoRes.data;

  // A CONSULTA QUE FALHA É DITA, não virada em tela vazia. Mesmo raciocínio da rota
  // de export: uma tela que lê zero por erro de RLS e mostra "nenhuma linha" mente
  // com mais convicção do que um erro — quem lê conclui que a base está vazia.
  const erroLeitura = documentosRes.error?.message ?? null;
  const documentos = documentosRes.data;

  const versaoIds = documentos.flatMap((d) => (d.documento_versao ?? []).map((v) => v.id));
  const camposRes = versaoIds.length
    ? await paginar<CampoExtraido>((de, ate) =>
        supabase
          .from("campo_extraido")
          .select(
            "id, documento_versao_id, secao, secao_canonica, entidade_coluna, periodo_coluna, chave, valor_texto, valor_num, unidade, confianca, origem_pagina, ordem, status_aceite, aceito_por, aceito_em",
          )
          .in("documento_versao_id", versaoIds)
          // Mesma ordem da rota de export, e pelo mesmo motivo: sem ordem total e
          // estável, duas páginas podem repetir e omitir a mesma linha.
          .order("documento_versao_id", { ascending: true })
          .order("ordem", { ascending: true, nullsFirst: false })
          .order("id", { ascending: true })
          .range(de, ate),
      )
    : { data: [] as CampoExtraido[], error: null, truncado: false };

  // SÓ A VERSÃO VIGENTE, com a mesma função que o export usa (`versoesVigentes`).
  // Reextração e transcrição humana SUBSTITUEM, não acumulam: mostrar as duas
  // versões faria a mesma conta aparecer duas vezes, com valores diferentes, e
  // nada na tela explicaria qual é a de agora.
  const vigentes = versoesVigentes(documentos, camposRes.data);
  const contextoPorVersao = new Map<
    string,
    { entidade: string; periodo: string; tipoTaxonomia: string | null; nomeArquivo: string }
  >();
  for (const doc of documentos) {
    for (const v of doc.documento_versao ?? []) {
      if (!vigentes.has(v.id)) continue;
      contextoPorVersao.set(v.id, {
        entidade: doc.entidade?.razao_social ?? "(sem entidade)",
        periodo: doc.periodo ? formatarPeriodo(doc.periodo.tipo, doc.periodo.referencia) : "(sem período)",
        tipoTaxonomia: doc.tipo_taxonomia,
        nomeArquivo: v.nome_original ?? "(sem nome)",
      });
    }
  }

  // A MESMA consolidação de nome do export: o apelido da coluna do combinado
  // ("Componentes") e a razão social do documento individual são a MESMA empresa, e
  // sem isso ela apareceria como duas no filtro.
  const nomeCanonico = consolidarNomesDeEntidade(
    [...contextoPorVersao.values()].map((c) => c.entidade),
    camposRes.data.map((c) => c.entidade_coluna).filter((x): x is string => !!x),
  );

  type Linha = {
    campo: CampoExtraido;
    entidade: string;
    periodo: string;
    arquivo: string;
    tipo: string | null;
  };

  const linhas: Linha[] = [];
  for (const campo of camposRes.data) {
    const ctx = contextoPorVersao.get(campo.documento_versao_id);
    if (!ctx) continue; // versão substituída
    // A REGRA DE ENTIDADE E PERÍODO É A DO EXPORT, chamada e não recopiada: a linha
    // pode pertencer à coluna (`entidade_coluna`/`periodo_coluna`) e não ao
    // documento, e duas respostas para essa pergunta em duas telas é o defeito que
    // esta casa persegue.
    const { entidade, periodo } = entidadePeriodoDaLinha(campo, ctx, nomeCanonico);
    linhas.push({ campo, entidade, periodo, arquivo: ctx.nomeArquivo, tipo: ctx.tipoTaxonomia });
  }

  const entidades = [...new Set(linhas.map((l) => l.entidade))].sort((a, b) => a.localeCompare(b, "pt-BR"));
  const periodos = [...new Set(linhas.map((l) => l.periodo))].sort(
    // Cronológica, não alfabética — a mesma chave do export. Alfabético põe
    // "Nov/2024" antes de "Out/2024", e um filtro de período em ordem errada faz
    // quem procura o exercício mais recente clicar no meio da série.
    (a, b) => chaveCronologicaPeriodo(a) - chaveCronologicaPeriodo(b) || a.localeCompare(b, "pt-BR"),
  );

  const busca = (filtro.q ?? "").trim().toLocaleLowerCase("pt-BR");
  const filtradas = linhas.filter((l) => {
    if (filtro.entidade && l.entidade !== filtro.entidade) return false;
    if (filtro.periodo && l.periodo !== filtro.periodo) return false;
    if (filtro.status === "aceito" && l.campo.status_aceite !== "aceito") return false;
    if (filtro.status === "pendente" && l.campo.status_aceite === "aceito") return false;
    if (busca && !l.campo.chave.toLocaleLowerCase("pt-BR").includes(busca)) return false;
    return true;
  });

  const nAceitas = filtradas.filter((l) => l.campo.status_aceite === "aceito").length;
  const mostradas = filtradas.slice(0, TETO_LINHAS);

  const url = (mudanca: Record<string, string | undefined>) => {
    const p = new URLSearchParams();
    const base: Record<string, string | undefined> = {
      entidade: filtro.entidade, periodo: filtro.periodo, q: filtro.q, status: filtro.status,
      ...mudanca,
    };
    for (const [k, v] of Object.entries(base)) if (v) p.set(k, v);
    const qs = p.toString();
    return `/casos/${id}/base${qs ? `?${qs}` : ""}`;
  };

  return (
    <div className="space-y-5">
      <div>
        <Link href={`/casos/${id}`} className="text-sm text-tinta-500 underline">
          ← Voltar ao caso
        </Link>
        <h1 className="mt-2 text-xl font-semibold text-tinta-900">A base viva</h1>
        <p className="text-sm text-tinta-500">
          {caso.nome} — o que a base diz, linha a linha, atravessando os documentos. Cada valor
          traz de onde veio e se já foi aceito.
        </p>
      </div>

      {erroLeitura && (
        <div className="rounded border border-red-300 bg-red-50 p-3 text-sm text-red-800">
          <strong>A leitura dos documentos falhou</strong> — {erroLeitura}. A tela abaixo pode estar
          incompleta, e o vazio dela não significa base vazia. Causa mais comum: RLS/GRANT
          (`db/migrations/0028`).
        </div>
      )}

      {/* NÃO SOMA, E DIZ QUE NÃO SOMA. Sem esta frase, um analista somaria a coluna
          no olho e chegaria a um total que dobra subtotais — e a culpa pareceria dele. */}
      <p className="rounded border border-tinta-200 bg-tinta-50 px-3 py-2 text-xs text-tinta-600">
        Esta tela <strong>não totaliza e não converte escala</strong>: cada linha aparece como o
        documento a trouxe, com a unidade ao lado. Somar aqui contaria subtotais impressos duas
        vezes. O consolidado — com subtotal tratado, escala única e AV% — é o{" "}
        <a href={`/casos/${id}/export?modo=dados`} className="underline">
          arquivo de dados
        </a>
        .
      </p>

      <form method="get" className="flex flex-wrap items-end gap-2">
        <div>
          <label htmlFor="q" className="block text-xs text-tinta-500">
            Conta / linha
          </label>
          <input
            id="q"
            type="text"
            name="q"
            defaultValue={filtro.q ?? ""}
            placeholder="ex.: estoques"
            className="w-56 rounded border border-tinta-300 px-2 py-1 text-sm"
          />
        </div>
        {/* Entidade e período preservados no submit da busca: sem estes hidden, digitar
            no campo de texto apagaria os dois filtros de chip que a pessoa acabou de
            escolher — e a tela pareceria ter ignorado o clique. */}
        {filtro.entidade && <input type="hidden" name="entidade" value={filtro.entidade} />}
        {filtro.periodo && <input type="hidden" name="periodo" value={filtro.periodo} />}
        {filtro.status && <input type="hidden" name="status" value={filtro.status} />}
        <button type="submit" className="rounded bg-tinta-900 px-3 py-1 text-sm font-medium text-white">
          Filtrar
        </button>
        {(filtro.q || filtro.entidade || filtro.periodo || filtro.status) && (
          <Link href={`/casos/${id}/base`} className="px-1 text-xs text-tinta-500 underline">
            limpar tudo
          </Link>
        )}
      </form>

      <div className="space-y-2">
        <div className="flex flex-wrap items-center gap-1.5">
          <span className="w-16 text-xs uppercase text-tinta-400">Empresa</span>
          {/* "Consolidado" aqui quer dizer TODAS AS EMPRESAS na mesma lista — é o
              recorte do spec ("visão consolidada do caso e visão por entidade"), e
              não uma soma. A coluna de empresa continua em cada linha. */}
          <Chip href={url({ entidade: undefined })} ativo={!filtro.entidade}>
            todas
          </Chip>
          {entidades.map((e) => (
            <Chip key={e} href={url({ entidade: e })} ativo={filtro.entidade === e}>
              {e}
            </Chip>
          ))}
        </div>
        <div className="flex flex-wrap items-center gap-1.5">
          <span className="w-16 text-xs uppercase text-tinta-400">Período</span>
          <Chip href={url({ periodo: undefined })} ativo={!filtro.periodo}>
            todos
          </Chip>
          {periodos.map((p) => (
            <Chip key={p} href={url({ periodo: p })} ativo={filtro.periodo === p}>
              {p}
            </Chip>
          ))}
        </div>
        <div className="flex flex-wrap items-center gap-1.5">
          <span className="w-16 text-xs uppercase text-tinta-400">Aceite</span>
          <Chip href={url({ status: undefined })} ativo={!filtro.status}>
            todos
          </Chip>
          <Chip href={url({ status: "aceito" })} ativo={filtro.status === "aceito"}>
            aceitos
          </Chip>
          <Chip href={url({ status: "pendente" })} ativo={filtro.status === "pendente"}>
            pendentes
          </Chip>
        </div>
      </div>

      <div className="flex flex-wrap items-baseline gap-x-3 text-sm text-tinta-600">
        <span>
          <strong>{filtradas.length}</strong> linha(s)
        </span>
        <span className="text-xs text-tinta-500">
          {nAceitas} aceita(s) · {filtradas.length - nAceitas} pendente(s) de revisão
        </span>
      </div>

      {/* O TETO DA TELA SAI DO SILÊNCIO. Cortar em 500 e não dizer nada seria o
          mesmo defeito do teto do PostgREST que este código já matou duas vezes: a
          lista abre normalmente e parece completa. */}
      {filtradas.length > mostradas.length && (
        <p className="rounded border border-amber-300 bg-amber-50 px-3 py-2 text-xs text-amber-900">
          Mostrando as primeiras <strong>{mostradas.length}</strong> de {filtradas.length} linhas.
          Estreite o filtro (empresa, período ou busca) para ver o resto — a lista não continua
          abaixo.
        </p>
      )}
      {camposRes.truncado && (
        <p className="rounded border border-amber-300 bg-amber-50 px-3 py-2 text-xs text-amber-900">
          A leitura da base atingiu o teto de segurança da paginação — há linhas neste caso que não
          entraram nem na contagem acima.
        </p>
      )}

      {mostradas.length === 0 ? (
        <p className="rounded border border-tinta-200 bg-white px-3 py-4 text-sm text-tinta-500">
          Nenhuma linha com esses filtros.
          {linhas.length > 0 && " A base tem linhas — o recorte é que não casou."}
        </p>
      ) : (
        <div className="overflow-x-auto rounded border border-tinta-200 bg-white">
          <table className="w-full text-left text-sm">
            <thead className="text-xs uppercase text-tinta-500">
              <tr>
                <th className="px-3 py-1.5">Conta / linha</th>
                <th className="px-3 py-1.5">Empresa</th>
                <th className="px-3 py-1.5">Período</th>
                <th className="px-3 py-1.5 text-right">Valor</th>
                <th className="px-3 py-1.5">Unidade</th>
                <th className="px-3 py-1.5">Aceite</th>
                <th className="px-3 py-1.5">De onde veio</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-tinta-100">
              {mostradas.map((l) => {
                const aceito = l.campo.status_aceite === "aceito";
                return (
                  <tr key={l.campo.id} className={aceito ? "" : "bg-amber-50/40"}>
                    <td className="px-3 py-1.5">
                      {l.campo.chave}
                      {l.campo.secao && (
                        <span className="ml-1 text-xs text-tinta-400">{l.campo.secao}</span>
                      )}
                    </td>
                    <td className="px-3 py-1.5 text-tinta-600">{l.entidade}</td>
                    <td className="px-3 py-1.5 text-tinta-600">{l.periodo}</td>
                    <td className="px-3 py-1.5 text-right font-mono">
                      {l.campo.valor_num != null
                        ? l.campo.valor_num.toLocaleString("pt-BR", { maximumFractionDigits: 2 })
                        : (l.campo.valor_texto ?? "—")}
                    </td>
                    <td className="px-3 py-1.5 text-xs text-tinta-500">{l.campo.unidade ?? "—"}</td>
                    <td className="px-3 py-1.5">
                      {/* PENDENTE É VISUALMENTE DISTINTO — exigência escrita do `f0/07`
                          §"o que está pendente de revisão, visualmente distinta". E a
                          palavra vai escrita: a cor de fundo sozinha não carrega
                          significado para quem não a distingue. */}
                      <span
                        className={`rounded px-1.5 py-0.5 text-xs font-medium uppercase ${
                          aceito ? "bg-emerald-100 text-emerald-700" : "bg-amber-100 text-amber-800"
                        }`}
                        title={aceito && l.campo.aceito_por ? `Aceito por ${l.campo.aceito_por}` : ""}
                      >
                        {aceito ? "aceito" : "pendente"}
                      </span>
                    </td>
                    <td className="px-3 py-1.5 text-xs text-tinta-500">
                      {/* A PROVENIÊNCIA, que é o que o `f0/07` exige de cada valor
                          exibido: o arquivo, a página e a confiança da extração.
                          Confiança nula é o caso da linha TRANSCRITA (0129) — não
                          existe autoavaliação de pessoa — e aparece como "—", nunca
                          como 0%, que seria ler "a máquina não confia" onde não houve
                          máquina. */}
                      {l.arquivo}
                      {l.campo.origem_pagina != null && ` · p. ${l.campo.origem_pagina}`}
                      {l.tipo && (
                        <span className="ml-1 text-tinta-400">{formatarTipoTaxonomia(l.tipo)}</span>
                      )}
                      {l.campo.confianca != null && (
                        <span className="ml-1">· {Math.round(l.campo.confianca * 100)}%</span>
                      )}
                    </td>
                  </tr>
                );
              })}
            </tbody>
          </table>
        </div>
      )}
    </div>
  );
}
