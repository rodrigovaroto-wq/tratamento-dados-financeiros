import Link from "next/link";
import { notFound } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { formatarTipoTaxonomia } from "@/lib/export";
import { definirParametros, ativarPremissa, vincularLinha, aplicarEmLote } from "./actions";

// A seção MODELAGEM do mandato (pedido do dono, Fase 7.3).
//
// É aqui que "cada caso é um caso" vira operação: o analista escolhe as premissas
// que valem para ESTE mandato e diz ONDE cada uma entra na projeção — linha por
// linha, com atalho em lote por seção.
//
// Três coisas que esta tela existe para tornar impossíveis:
//   1. premissa aparecer sem valor e o modelo projetar como se fosse zero — a
//      conferência no topo nomeia toda premissa ativa sem valor;
//   2. o analista não saber quais linhas ficariam de fora — o contador de "sem
//      premissa" é a primeira coisa que ele lê;
//   3. configuração apontando para linha que não existe mais (documento
//      reextraído com outro rótulo) passar por configuração válida — são os
//      `vinculos_orfaos`, nomeados.
//
// Nada de regra de projeção vive aqui: tudo é `rpc` para as funções da 0038.

interface PremissaCatalogo {
  codigo: string;
  nome: string;
  natureza: string;
  formula: string;
  unidade: string | null;
  aplica_em: string[];
  setores: string[];
  descricao: string | null;
}

interface CasoPremissa {
  premissa_codigo: string;
  valores: Record<string, number>;
  origem: string | null;
}

interface LinhaDoCaso {
  secao_canonica: string | null;
  chave: string;
  rotulo_norm: string;
  entidade: string | null;
  valor_ultimo: number;
  n_ocorrencias: number;
}

interface LinhaVinculo {
  secao_canonica: string | null;
  rotulo_norm: string;
  entidade: string | null;
  premissa_codigo: string | null;
  sazonalidade_codigo: string | null;
}

const SETORES = [
  ["industria", "Indústria / metalurgia"], ["varejo", "Varejo"], ["servicos", "Serviços"],
  ["agro", "Agro"], ["construcao", "Construção / incorporação"], ["logistica", "Logística / transporte"],
  ["saude", "Saúde"], ["energia", "Energia"], ["tecnologia", "Tecnologia"],
  ["alimentos", "Alimentos e bebidas"], ["educacao", "Educação"], ["mineracao", "Mineração"],
  ["papel_celulose", "Papel e celulose"], ["quimica", "Química / petroquímica"],
  ["textil", "Têxtil / vestuário"], ["automotivo", "Automotivo / autopeças"],
  ["farma", "Farma / distribuição"], ["telecom", "Telecom"], ["hotelaria", "Hotelaria / turismo"],
  ["imobiliario", "Imobiliário (renda)"],
];

const NATUREZA_LABEL: Record<string, string> = {
  macro: "Macro", receita: "Receita", custo: "Custo", despesa: "Despesa",
  giro: "Capital de giro", investimento: "Investimento", divida: "Dívida",
  tributo: "Tributos", socios: "Sócios", sazonalidade: "Sazonalidade",
  operacional: "Driver operacional",
};

export default async function ModelagemPage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  const supabase = await createClient();

  const casoRes = await supabase.from("caso").select("id, nome, produto, status").eq("id", id).single();
  if (casoRes.error || !casoRes.data) notFound();
  const caso = casoRes.data;

  const paramRes = await supabase
    .from("caso_modelagem").select("*").eq("caso_id", id).maybeSingle();
  const parametros = paramRes.data as {
    entidade: string | null; ultimo_exercicio_real: number | null;
    indice_macro: string | null; setor: string | null; anos_projetados: number;
  } | null;

  // O catálogo vem FILTRADO pelo setor — é a sugestão da 0038. Sem setor
  // definido, vem só a base comum, que é a resposta correta para "ainda não sei
  // o setor" (e não uma lista de 90 premissas para escolher no escuro).
  const [sugeridasRes, ativasRes, vinculosRes, confRes, camposRes] = await Promise.all([
    supabase.rpc("fn_premissas_sugeridas", { p_setor: parametros?.setor ?? null }),
    supabase.from("caso_premissa").select("premissa_codigo, valores, origem")
      .eq("caso_id", id).eq("ativo", true),
    supabase.from("caso_linha_premissa")
      .select("secao_canonica, rotulo_norm, entidade, premissa_codigo, sazonalidade_codigo")
      .eq("caso_id", id),
    supabase.rpc("fn_conferir_modelagem", { p_caso_id: id }),
    // As linhas do caso — por FUNÇÃO (db/migrations/0039), não por consulta direta.
    //
    // `campo_extraido` não tem `caso_id`: o vínculo é `campo_extraido →
    // documento_versao → documento`. A primeira versão desta tela consultava a
    // tabela direto e, com a RLS aberta a qualquer autenticado, trazia as linhas
    // de TODOS os mandatos. O escopo por caso passou a viver em UM lugar, coberto
    // por teste SQL, em vez de depender de um join escrito certo em cada consulta
    // nova que alguém acrescente aqui.
    supabase.rpc("fn_linhas_para_modelagem", { p_caso_id: id }),
  ]);

  const sugeridas = (sugeridasRes.data as PremissaCatalogo[] | null) ?? [];
  const ativas = (ativasRes.data as CasoPremissa[] | null) ?? [];
  const vinculos = (vinculosRes.data as LinhaVinculo[] | null) ?? [];
  const conf = confRes.data as {
    premissas_ativas: number; premissas_sem_valor: string[];
    linhas_do_caso: number; linhas_com_premissa: number; linhas_sem_premissa: number;
    vinculos_orfaos: string[]; pronto: boolean;
  } | null;

  const ativasPorCodigo = new Map(ativas.map((a) => [a.premissa_codigo, a]));
  const vinculoPorRotulo = new Map(vinculos.map((v) => [v.rotulo_norm, v]));
  const nomeDaPremissa = new Map(sugeridas.map((p) => [p.codigo, p.nome]));

  // Anos a projetar: do último exercício real + 1 em diante. É o horizonte que as
  // premissas precisam cobrir, e é derivado dos parâmetros — não digitado duas
  // vezes.
  const ultimoReal = parametros?.ultimo_exercicio_real ?? new Date().getFullYear() - 1;
  const nAnos = parametros?.anos_projetados ?? 5;
  const anos = Array.from({ length: nAnos }, (_, i) => ultimoReal + 1 + i);

  // Linhas do caso agrupadas por seção canônica — é a unidade do aplicar-em-lote.
  // A função já devolve UMA linha por (seção, rótulo normalizado): o agrupamento
  // por rótulo é dela, não daqui, para a tela e o lote concordarem sobre o que é
  // "uma linha".
  const linhasPorSecao = new Map<string, LinhaDoCaso[]>();
  for (const c of (camposRes.data as LinhaDoCaso[] | null) ?? []) {
    const secao = c.secao_canonica ?? "(sem seção canônica)";
    if (!linhasPorSecao.has(secao)) linhasPorSecao.set(secao, []);
    linhasPorSecao.get(secao)!.push(c);
  }

  const porNatureza = new Map<string, PremissaCatalogo[]>();
  for (const p of sugeridas) {
    if (!porNatureza.has(p.natureza)) porNatureza.set(p.natureza, []);
    porNatureza.get(p.natureza)!.push(p);
  }

  const fmt = new Intl.NumberFormat("pt-BR", { maximumFractionDigits: 0 });

  return (
    <main className="mx-auto max-w-6xl space-y-6 p-6">
      <div className="flex items-baseline justify-between gap-4">
        <div>
          <Link href={`/casos/${id}`} className="text-sm text-neutral-500 hover:underline">
            ← {caso.nome}
          </Link>
          <h1 className="text-xl font-semibold">Modelagem</h1>
          <p className="text-xs text-neutral-500">
            Escolha as premissas deste mandato e diga onde cada uma entra na projeção.
          </p>
        </div>
        <a
          href={`/casos/${id}/export`}
          className="rounded border border-neutral-300 bg-white px-3 py-1.5 text-sm font-medium text-neutral-700 hover:bg-neutral-50"
        >
          Exportar completo ↓
        </a>
      </div>

      {/* 4. CONFERÊNCIA — no TOPO, não no fim. É o que o analista precisa saber
          antes de mexer em qualquer coisa: quantas linhas ficariam de fora e qual
          premissa está sem valor. Pôr isso no rodapé seria pôr o resultado depois
          da decisão. */}
      {conf && (
        <section
          className={`rounded border p-3 text-sm ${
            conf.pronto ? "border-emerald-300 bg-emerald-50" : "border-amber-300 bg-amber-50"
          }`}
        >
          <p className={`font-medium ${conf.pronto ? "text-emerald-900" : "text-amber-900"}`}>
            {conf.pronto
              ? "Pronto para o export completo"
              : "Ainda falta algo para o export completo"}
          </p>
          <ul className="mt-1 space-y-0.5 text-neutral-700">
            <li>
              {conf.linhas_com_premissa} de {conf.linhas_do_caso} linhas com premissa —{" "}
              <strong>{conf.linhas_sem_premissa} sem premissa</strong>, que não serão projetadas (o
              arquivo mostra cada uma como não projetada, nunca projetada por padrão).
            </li>
            <li>{conf.premissas_ativas} premissa(s) ativa(s) neste caso.</li>
            {conf.premissas_sem_valor?.length > 0 && (
              <li className="text-amber-900">
                <strong>Sem valor preenchido:</strong> {conf.premissas_sem_valor.join(", ")} — premissa
                ativa sem valor projetaria com zero, então ela impede o &quot;pronto&quot;.
              </li>
            )}
            {conf.vinculos_orfaos?.length > 0 && (
              <li className="text-amber-900">
                <strong>Configuração apontando para linha que não existe:</strong>{" "}
                {conf.vinculos_orfaos.join(", ")} — o documento não chegou, ou foi reextraído com
                outro rótulo.
              </li>
            )}
          </ul>
        </section>
      )}

      {/* 1. PARÂMETROS — as três células que saíram do topo da aba Modelagem. */}
      <section className="rounded border border-neutral-200 bg-white p-4">
        <h2 className="mb-1 text-sm font-semibold text-neutral-700">1. Parâmetros do mandato</h2>
        <p className="mb-3 text-xs text-neutral-500">
          Entidade modelada, corte do último exercício real e índice macro saíram do topo da planilha
          e vivem aqui — o Excel sai já parametrizado com o que você escolher. O setor filtra as
          premissas sugeridas no passo 2.
        </p>
        <form action={definirParametros.bind(null, id)} className="grid gap-3 sm:grid-cols-2">
          <label className="text-sm">
            <span className="text-neutral-600">Entidade modelada</span>
            <input
              type="text" name="entidade" defaultValue={parametros?.entidade ?? ""}
              placeholder="razão social como aparece nas abas de dados"
              className="mt-1 w-full rounded border border-neutral-300 px-2 py-1"
            />
          </label>
          <label className="text-sm">
            <span className="text-neutral-600">Último exercício realizado</span>
            <input
              type="number" name="ultimo_exercicio_real"
              defaultValue={parametros?.ultimo_exercicio_real ?? ""}
              className="mt-1 w-full rounded border border-neutral-300 px-2 py-1"
            />
          </label>
          <label className="text-sm">
            <span className="text-neutral-600">Índice macro que dirige a projeção</span>
            <select
              name="indice_macro" defaultValue={parametros?.indice_macro ?? "IPCA"}
              className="mt-1 w-full rounded border border-neutral-300 px-2 py-1"
            >
              {["IPCA", "IGPM", "INCC", "SELIC", "CAMBIO_USD", "PIB"].map((s) => (
                <option key={s} value={s}>{s}</option>
              ))}
            </select>
          </label>
          <label className="text-sm">
            <span className="text-neutral-600">Setor do mandato</span>
            <select
              name="setor" defaultValue={parametros?.setor ?? ""}
              className="mt-1 w-full rounded border border-neutral-300 px-2 py-1"
            >
              <option value="">(ainda não definido — sugere só a base comum)</option>
              {SETORES.map(([v, label]) => <option key={v} value={v}>{label}</option>)}
            </select>
          </label>
          <label className="text-sm">
            <span className="text-neutral-600">Anos projetados</span>
            <input
              type="number" name="anos_projetados" min={1} max={10}
              defaultValue={parametros?.anos_projetados ?? 5}
              className="mt-1 w-full rounded border border-neutral-300 px-2 py-1"
            />
          </label>
          <div className="flex items-end">
            <button
              type="submit"
              className="rounded bg-neutral-900 px-3 py-1.5 text-sm font-medium text-white hover:bg-neutral-700"
            >
              Salvar parâmetros
            </button>
          </div>
        </form>
      </section>

      {/* 2. PREMISSAS DO CASO */}
      <section className="rounded border border-neutral-200 bg-white p-4">
        <h2 className="mb-1 text-sm font-semibold text-neutral-700">
          2. Premissas deste caso
          {parametros?.setor && (
            <span className="ml-2 font-normal text-neutral-500">
              — sugeridas para {SETORES.find(([v]) => v === parametros.setor)?.[1] ?? parametros.setor}
            </span>
          )}
        </h2>
        <p className="mb-3 text-xs text-neutral-500">
          O setor <strong>sugere</strong>, não restringe: a lista traz a base comum mais as do setor,
          e qualquer premissa ativada aqui pode ser usada em qualquer linha. Ano em branco fica{" "}
          <strong>em branco</strong> — não vira zero, porque projetar com zero é o erro que não se
          denuncia.
        </p>
        <div className="space-y-4">
          {[...porNatureza.entries()].map(([natureza, lista]) => (
            <div key={natureza}>
              <h3 className="mb-1 text-xs font-semibold uppercase text-neutral-500">
                {NATUREZA_LABEL[natureza] ?? natureza}
              </h3>
              <div className="space-y-1">
                {lista.map((p) => {
                  const ativa = ativasPorCodigo.get(p.codigo);
                  return (
                    <form
                      key={p.codigo} action={ativarPremissa.bind(null, id)}
                      className={`flex flex-wrap items-center gap-2 rounded border px-2 py-1.5 text-sm ${
                        ativa ? "border-emerald-200 bg-emerald-50" : "border-neutral-200"
                      }`}
                    >
                      <input type="hidden" name="codigo" value={p.codigo} />
                      <span className="min-w-56 flex-1" title={p.descricao ?? undefined}>
                        {p.nome}
                        {p.unidade && <span className="ml-1 text-neutral-500">({p.unidade})</span>}
                        {p.setores.length > 0 && (
                          <span className="ml-1 rounded bg-indigo-100 px-1 text-[10px] text-indigo-800">
                            setor
                          </span>
                        )}
                      </span>
                      {anos.map((ano) => (
                        <input
                          key={ano} type="text" name={`valor_${ano}`}
                          defaultValue={ativa?.valores?.[String(ano)] ?? ""}
                          placeholder={String(ano)} title={`${p.nome} — ${ano}`}
                          className="w-16 rounded border border-neutral-300 px-1 py-0.5 text-right text-xs"
                        />
                      ))}
                      <button
                        type="submit"
                        className="rounded border border-neutral-300 px-2 py-0.5 text-xs hover:bg-neutral-100"
                      >
                        {ativa ? "Atualizar" : "Ativar"}
                      </button>
                    </form>
                  );
                })}
              </div>
            </div>
          ))}
        </div>
      </section>

      {/* 3. LINHAS × PREMISSAS */}
      <section className="rounded border border-neutral-200 bg-white p-4">
        <h2 className="mb-1 text-sm font-semibold text-neutral-700">3. Linhas × premissas</h2>
        <p className="mb-3 text-xs text-neutral-500">
          Cada linha extraída pode ter a sua premissa. O <strong>aplicar em lote</strong> resolve a
          maioria dos casos de uma vez (todas as linhas de receita → crescimento real); depois é só
          ajustar as exceções. Linha sem premissa não é projetada — e isso é escolha legítima, que o
          arquivo declara.
        </p>

        {ativas.length === 0 ? (
          <p className="rounded border border-amber-300 bg-amber-50 p-2 text-sm text-amber-900">
            Ative pelo menos uma premissa no passo 2 antes de vincular linhas. Vincular linha a
            premissa não ativada é recusado no banco, de propósito: a linha sairia
            &quot;projetada&quot; por uma premissa vazia.
          </p>
        ) : (
          <div className="space-y-5">
            {[...linhasPorSecao.entries()].sort().map(([secao, linhas]) => (
              <div key={secao}>
                <div className="mb-1 flex flex-wrap items-center gap-2">
                  <h3 className="text-xs font-semibold uppercase text-neutral-500">
                    {secao} <span className="font-normal">({linhas.length} linha(s))</span>
                  </h3>
                  {secao !== "(sem seção canônica)" && (
                    <form action={aplicarEmLote.bind(null, id)} className="flex items-center gap-1">
                      <input type="hidden" name="secao_canonica" value={secao} />
                      <select
                        name="premissa" required
                        className="rounded border border-neutral-300 px-1 py-0.5 text-xs"
                        defaultValue=""
                      >
                        <option value="" disabled>aplicar em lote…</option>
                        {ativas.map((a) => (
                          <option key={a.premissa_codigo} value={a.premissa_codigo}>
                            {nomeDaPremissa.get(a.premissa_codigo) ?? a.premissa_codigo}
                          </option>
                        ))}
                      </select>
                      <button
                        type="submit"
                        className="rounded border border-neutral-300 px-2 py-0.5 text-xs hover:bg-neutral-100"
                      >
                        aplicar a todas
                      </button>
                    </form>
                  )}
                </div>
                <div className="overflow-x-auto rounded border border-neutral-200">
                  <table className="w-full text-left text-sm">
                    <thead className="bg-neutral-50 text-xs uppercase text-neutral-500">
                      <tr>
                        <th className="px-2 py-1">Linha</th>
                        <th className="px-2 py-1 text-right">Último real</th>
                        <th className="px-2 py-1">Premissa que dirige</th>
                        <th className="px-2 py-1">Sazonalidade</th>
                        <th className="px-2 py-1"></th>
                      </tr>
                    </thead>
                    <tbody>
                      {linhas.map((l) => {
                        // O rótulo normalizado vem do BANCO (`fn_normalizar_texto`,
                        // via 0039). Normalizar de novo aqui, em JS, criaria uma
                        // segunda definição de "mesma linha" — e as duas
                        // divergiriam no primeiro caractere que só uma das
                        // implementações tratasse.
                        const v = vinculoPorRotulo.get(l.rotulo_norm);
                        return (
                          <tr key={`${secao}-${l.chave}`} className="border-t border-neutral-100">
                            <td className="px-2 py-1">{l.chave}</td>
                            <td className="px-2 py-1 text-right tabular-nums text-neutral-600">
                              {fmt.format(l.valor_ultimo)}
                            </td>
                            <td colSpan={3} className="px-2 py-1">
                              <form action={vincularLinha.bind(null, id)} className="flex items-center gap-1">
                                <input type="hidden" name="secao_canonica" value={secao === "(sem seção canônica)" ? "" : secao} />
                                <input type="hidden" name="rotulo" value={l.chave} />
                                <input type="hidden" name="entidade" value={l.entidade ?? ""} />
                                <select
                                  name="premissa" defaultValue={v?.premissa_codigo ?? ""}
                                  className="rounded border border-neutral-300 px-1 py-0.5 text-xs"
                                >
                                  <option value="">(não projetar)</option>
                                  {ativas.map((a) => (
                                    <option key={a.premissa_codigo} value={a.premissa_codigo}>
                                      {nomeDaPremissa.get(a.premissa_codigo) ?? a.premissa_codigo}
                                    </option>
                                  ))}
                                </select>
                                <select
                                  name="sazonalidade" defaultValue={v?.sazonalidade_codigo ?? ""}
                                  className="rounded border border-neutral-300 px-1 py-0.5 text-xs"
                                >
                                  <option value="">(sem sazonalidade)</option>
                                  {ativas
                                    .filter((a) => a.premissa_codigo.includes("SAZON")
                                      || a.premissa_codigo === "CRONOGRAMA_FISICO"
                                      || a.premissa_codigo === "PARADA_MANUTENCAO")
                                    .map((a) => (
                                      <option key={a.premissa_codigo} value={a.premissa_codigo}>
                                        {nomeDaPremissa.get(a.premissa_codigo) ?? a.premissa_codigo}
                                      </option>
                                    ))}
                                </select>
                                <button
                                  type="submit"
                                  className="rounded border border-neutral-300 px-2 py-0.5 text-xs hover:bg-neutral-100"
                                >
                                  salvar
                                </button>
                                {v?.premissa_codigo && (
                                  <span className="text-xs text-emerald-700">
                                    ✓ {nomeDaPremissa.get(v.premissa_codigo) ?? v.premissa_codigo}
                                  </span>
                                )}
                              </form>
                            </td>
                          </tr>
                        );
                      })}
                    </tbody>
                  </table>
                </div>
              </div>
            ))}
            {linhasPorSecao.size === 0 && (
              <p className="text-sm text-neutral-500">
                Este caso ainda não tem linha extraída com valor. Confira a fila de revisão e o
                export de dados ({formatarTipoTaxonomia("BALANCO")} e as demais abas).
              </p>
            )}
          </div>
        )}
      </section>
    </main>
  );
}
