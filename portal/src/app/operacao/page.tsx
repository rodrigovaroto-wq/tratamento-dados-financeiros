import Link from "next/link";
import { createClient } from "@/lib/supabase/server";

// O PAINEL DE OPERAÇÃO — o que já estava gravado deixa de ser cego.
//
// O diagnóstico de 11/08 chamou isto de "zero observabilidade", e a frase dele é
// exata: uma falha em produção só aparece quando alguém abre a tela. O portal tem
// oito `console.error` e nenhuma métrica.
//
// O DADO JÁ EXISTIA. A `0115` criou `lote_execucao` e o nó `Gravar Uso do Lote` a
// alimenta desde então — documentos, falhas, custo real, custo estimado, tokens,
// linhas e cobertura, uma linha por execução. Nunca foi lido. Não faltava
// instrumentação: faltava a pergunta.
//
// POR QUE O VEREDITO NÃO MORA AQUI. Os alertas são decididos por
// `fn_operacao_lotes` (0135), no banco. Repetir a regra na tela criaria duas
// réguas sobre a mesma quantidade — a forma de defeito que esta casa já pagou
// três vezes — e a segunda divergiria no dia em que existisse um segundo leitor.

export const dynamic = "force-dynamic";

type Resumo = {
  janela_dias: number;
  lotes: number;
  documentos: number;
  linhas_extraidas: number;
  custo_usd: number;
  custo_por_documento: number | null;
  cobertura_mediana: number | null;
  lotes_com_alerta: number;
  por_alerta: Record<string, number>;
  ultimo_lote: string | null;
  dias_desde_o_ultimo: number | null;
};

type Lote = {
  lote_id: string;
  caso_id: string | null;
  caso_nome: string | null;
  execucao_ref: string | null;
  quando: string;
  documentos: number | null;
  com_falha: number | null;
  sem_medicao: number | null;
  fatiados: number | null;
  linhas_extraidas: number | null;
  cobertura: number | null;
  custo_usd: number | null;
  custo_estimado: number | null;
  razao_custo: number | null;
  alertas: string[];
};

// O TEXTO DE CADA ALERTA DIZ O SINTOMA E O QUE FAZER, não o nome da coluna.
// É a mesma lição da `0131`: "0115 ausente" não serve para quem não tem o
// repositório na outra aba; "os indicadores de custo mostram um traço" serve.
const ALERTA: Record<string, { titulo: string; oQueFazer: string }> = {
  cobertura_nao_medida: {
    titulo: "A cobertura não foi medida",
    oQueFazer:
      "Este lote passou sem que ninguém pudesse dizer se a extração veio inteira — não é "
      + "cobertura baixa, é a guarda não ter opinado. Confira se o texto do PDF foi extraído no nó "
      + "Medir Documento; sem ele as três camadas ficam mudas.",
  },
  documento_com_falha: {
    titulo: "Documento falhou na extração",
    oQueFazer:
      "Abra o mandato e veja a fila de pendências: a falha já virou pendência tipada. Se o motivo "
      + "for teto de saída, o fatiamento devia ter agido — vale conferir se o documento foi fatiado.",
  },
  documento_sem_medicao: {
    titulo: "Documento entrou e não foi medido",
    oQueFazer:
      "Nem falha, nem sucesso: o documento atravessou o lote sem produzir medição. É o estado que "
      + "mais se parece com normalidade e menos é.",
  },
  custo_acima_do_previsto: {
    titulo: "Custo acima do previsto",
    oQueFazer:
      "O custo real passou de 1,5× a estimativa que o orçamento fez para ESTE lote. Alguma premissa "
      + "do orçamento deixou de valer — tamanho de documento, número de colunas ou preço do modelo.",
  },
};

function Indicador({ rotulo, valor, nota }: { rotulo: string; valor: string; nota?: string }) {
  return (
    <div className="rounded-lg border border-tinta-200 bg-white p-4">
      <div className="text-xs uppercase tracking-wide text-tinta-500">{rotulo}</div>
      <div className="mt-1 text-2xl font-semibold tabular-nums text-tinta-900">{valor}</div>
      {nota && <div className="mt-1 text-xs text-tinta-500">{nota}</div>}
    </div>
  );
}

export default async function OperacaoPage() {
  const supabase = await createClient();
  const [resumoRes, lotesRes] = await Promise.all([
    supabase.rpc("fn_operacao_resumo", { p_dias: 30 }),
    supabase.rpc("fn_operacao_lotes", { p_dias: 30, p_limite: 50 }),
  ]);

  // A FALHA DA CONSULTA É ESTADO, e é publicada. Um painel de operação que
  // silencia o próprio erro é a contradição mais óbvia possível — e foi assim que
  // a tela de Modelagem já mostrou 203 linhas quando a função tinha FALHADO.
  if (resumoRes.error || lotesRes.error) {
    return (
      <main className="mx-auto max-w-5xl p-8">
        <h1 className="text-2xl font-semibold text-tinta-900">Operação</h1>
        <div className="mt-6 rounded-lg border border-amber-300 bg-amber-50 p-4 text-sm text-amber-900">
          <strong>Não consegui ler o estado da operação.</strong>{" "}
          {resumoRes.error?.message ?? lotesRes.error?.message}
          <p className="mt-2">
            Se a mensagem fala em função inexistente, falta aplicar a migration{" "}
            <code>0135</code>. A tela <Link className="underline" href="/instalacao">Instalação</Link>{" "}
            responde o que está faltando neste banco.
          </p>
        </div>
      </main>
    );
  }

  const resumo = resumoRes.data as Resumo;
  const lotes = (lotesRes.data as Lote[] | null) ?? [];
  const num = (v: number | null | undefined, casas = 0) =>
    v == null ? "—" : v.toLocaleString("pt-BR", { minimumFractionDigits: casas, maximumFractionDigits: casas });

  return (
    <main className="mx-auto max-w-6xl p-8">
      <h1 className="text-2xl font-semibold text-tinta-900">Operação</h1>
      <p className="mt-1 text-sm text-tinta-600">
        As execuções de ingestão dos últimos {resumo.janela_dias} dias. Os alertas são decididos no
        banco (<code>fn_operacao_lotes</code>), não nesta tela.
      </p>

      {/* O SILÊNCIO É ESTADO. Um painel que mostra "0 alertas" quando não roda
          nada há duas semanas afirma uma saúde que ninguém mediu. */}
      {resumo.lotes === 0 ? (
        <div className="mt-6 rounded-lg border border-tinta-200 bg-tinta-50 p-4 text-sm text-tinta-700">
          <strong>Nenhuma execução nos últimos {resumo.janela_dias} dias.</strong> Isto não é
          &quot;tudo bem&quot; — é ausência de informação. Um painel vazio e um painel verde dizem
          coisas opostas, e esta tela não os confunde.
        </div>
      ) : (
        <>
          <div className="mt-6 grid grid-cols-2 gap-3 md:grid-cols-3 lg:grid-cols-6">
            <Indicador rotulo="Lotes" valor={num(resumo.lotes)} />
            <Indicador rotulo="Documentos" valor={num(resumo.documentos)} />
            <Indicador rotulo="Linhas extraídas" valor={num(resumo.linhas_extraidas)} />
            <Indicador
              rotulo="Custo"
              valor={`US$ ${num(resumo.custo_usd, 2)}`}
              nota={resumo.custo_por_documento != null
                ? `US$ ${num(resumo.custo_por_documento, 4)} por documento` : undefined}
            />
            <Indicador
              rotulo="Cobertura típica"
              valor={resumo.cobertura_mediana != null
                ? `${(resumo.cobertura_mediana * 100).toFixed(1)}%` : "—"}
              nota="mediana, não média"
            />
            <Indicador
              rotulo="Última execução"
              valor={resumo.dias_desde_o_ultimo != null
                ? `há ${num(resumo.dias_desde_o_ultimo)}d` : "—"}
            />
          </div>

          {resumo.lotes_com_alerta > 0 && (
            <div className="mt-6 rounded-lg border border-amber-300 bg-amber-50 p-4">
              <h2 className="text-sm font-semibold text-amber-900">
                {resumo.lotes_com_alerta} lote(s) com alerta
              </h2>
              <ul className="mt-2 space-y-2 text-sm text-amber-900">
                {Object.entries(resumo.por_alerta).map(([chave, n]) => (
                  <li key={chave}>
                    <strong>{ALERTA[chave]?.titulo ?? chave} ({n})</strong> —{" "}
                    {ALERTA[chave]?.oQueFazer ?? ""}
                  </li>
                ))}
              </ul>
            </div>
          )}

          <div className="mt-6 overflow-x-auto">
            <table className="w-full min-w-[52rem] text-sm">
              <thead>
                <tr className="border-b border-tinta-200 text-left text-xs uppercase tracking-wide text-tinta-500">
                  <th className="py-2 pr-3">Quando</th>
                  <th className="py-2 pr-3">Mandato</th>
                  <th className="py-2 pr-3 text-right">Docs</th>
                  <th className="py-2 pr-3 text-right">Linhas</th>
                  <th className="py-2 pr-3 text-right">Cobertura</th>
                  <th className="py-2 pr-3 text-right">Custo</th>
                  <th className="py-2 pr-3 text-right">× previsto</th>
                  <th className="py-2">Alertas</th>
                </tr>
              </thead>
              <tbody>
                {lotes.map((l) => (
                  <tr
                    key={l.lote_id}
                    className={`border-b border-tinta-100 ${l.alertas.length > 0 ? "bg-amber-50/60" : ""}`}
                  >
                    <td className="py-2 pr-3 whitespace-nowrap text-tinta-600">
                      {new Date(l.quando).toLocaleString("pt-BR", { dateStyle: "short", timeStyle: "short" })}
                    </td>
                    <td className="py-2 pr-3">
                      {l.caso_id ? (
                        <Link className="underline" href={`/casos/${l.caso_id}`}>
                          {l.caso_nome ?? "mandato"}
                        </Link>
                      ) : (l.caso_nome ?? "—")}
                    </td>
                    <td className="py-2 pr-3 text-right tabular-nums">{num(l.documentos)}</td>
                    <td className="py-2 pr-3 text-right tabular-nums">{num(l.linhas_extraidas)}</td>
                    <td className="py-2 pr-3 text-right tabular-nums">
                      {l.cobertura != null ? `${(l.cobertura * 100).toFixed(0)}%` : (
                        <span className="text-amber-800">não medida</span>
                      )}
                    </td>
                    <td className="py-2 pr-3 text-right tabular-nums">
                      {l.custo_usd != null ? `US$ ${num(l.custo_usd, 2)}` : "—"}
                    </td>
                    <td className="py-2 pr-3 text-right tabular-nums">
                      {l.razao_custo != null ? `${l.razao_custo.toFixed(2)}×` : "—"}
                    </td>
                    <td className="py-2 text-xs text-amber-900">
                      {l.alertas.map((a) => ALERTA[a]?.titulo ?? a).join(" · ")}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </>
      )}
    </main>
  );
}
