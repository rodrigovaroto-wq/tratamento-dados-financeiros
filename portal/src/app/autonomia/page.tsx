import { createClient } from "@/lib/supabase/server";

// Painel de autonomia — SOMENTE LEITURA.
//
// POR QUE ESTA TELA EXISTE. `estagio_autonomia` nasce na 0001 com o comentário
// "Nível é estado do sistema, não constante de código (docs/01)" e, até a 0041,
// não tinha um único leitor: `grep -rl estagio_autonomia portal/src n8n` não
// retornava nada. O dial da extração dizia N0 ("roda, registra, NÃO influencia
// decisão") enquanto o código auto-aceitava toda linha com confiança >= 0.95. O
// estado declarado do sistema era invisível, então a divergência podia durar
// meses sem ninguém tropeçar nela. Esta tela é onde ela para de ser invisível.
//
// POR QUE SÓ LEITURA. Subir dial é decisão de doutrina, não de sessão: docs/01
// exige concordância MEDIDA contra golden set, e a mudança é global (afeta todo
// mandato, não o que está aberto). Um botão aqui convidaria a mexer no meio de um
// caso. A mudança se faz por `fn_mudar_dial`, que registra autor e motivo — e é
// ação do dono, como migration e teste ao vivo (CLAUDE.md).

type Dial = {
  estagio: string;
  nivel_atual: "N0" | "N1" | "N2" | "N3";
  teto: "N0" | "N1" | "N2" | "N3";
  limiar_auto_clear: number | null;
  atualizado_por: string | null;
  atualizado_em: string | null;
};

type EventoDial = {
  ator: string;
  acao: string;
  entidade_ref: string;
  depois: { motivo?: string; motivo_informado?: string; pedido?: string; teto?: string } | null;
  criado_em: string;
};

// docs/01, tabela de níveis. O texto é o da doutrina, palavra por palavra, porque
// é ele que define o que o número significa — reescrever "com minhas palavras"
// aqui abriria espaço para a tela dizer uma coisa e a doutrina outra.
const NIVEL: Record<string, { titulo: string; o_que_faz: string }> = {
  N0: { titulo: "Sombra", o_que_faz: "roda e registra a saída, mas NÃO influencia decisão" },
  N1: { titulo: "Sugestão + revisão 100%", o_que_faz: "a saída é sugestão; humano confirma todo item" },
  N2: { titulo: "Auto-clear + resto p/ humano", o_que_faz: "acima do limiar é autônomo; abaixo vai para humano" },
  N3: { titulo: "Autônomo + auditoria por amostragem", o_que_faz: "roda sozinho; humano audita amostra" },
};

const NOME_ESTAGIO: Record<string, string> = {
  classificacao_doc_checklist: "Classificação documento → checklist",
  validacao_formal: "Validação formal do arquivo",
  completude_portao1: "Completude (Portão 1)",
  extracao_identificadores: "Extração de identificadores (tipo/período/entidade)",
  extracao_linhas_financeiras: "Extração de linhas/tabelas financeiras",
  reconciliacao_classe_a: "Reconciliação Classe A (aritmética)",
  reconciliacao_classe_bc: "Reconciliação Classe B/C (semi/interpretativa)",
  classificacao_contabil: "Classificação contábil (recorrente/EBITDA)",
};

function dataHora(iso: string | null) {
  if (!iso) return "—";
  return new Date(iso).toLocaleString("pt-BR", { dateStyle: "short", timeStyle: "short" });
}

export default async function AutonomiaPage() {
  const supabase = await createClient();

  const [{ data: dials, error: erroDial }, { data: eventos }] = await Promise.all([
    supabase
      .from("estagio_autonomia")
      .select("estagio, nivel_atual, teto, limiar_auto_clear, atualizado_por, atualizado_em")
      .order("estagio"),
    supabase
      .from("evento_auditoria")
      .select("ator, acao, entidade_ref, depois, criado_em")
      .in("acao", ["mudanca_dial", "mudanca_dial_recusada"])
      .order("criado_em", { ascending: false })
      .limit(15),
  ]);

  const linhas = (dials as Dial[] | null) ?? [];
  const trilha = (eventos as EventoDial[] | null) ?? [];

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-lg font-semibold">Autonomia por estágio</h1>
        <p className="mt-1 text-sm text-neutral-600">
          O estado declarado do sistema: em que nível cada estágio opera hoje, e até onde a
          doutrina permite que ele suba. Esta tela só lê — mudar o dial é ação do dono, por{" "}
          <code className="rounded bg-neutral-100 px-1 text-xs">fn_mudar_dial</code>, que grava
          autor e motivo.
        </p>
      </div>

      {erroDial && (
        <p className="rounded border border-red-300 bg-red-50 p-3 text-sm text-red-700">
          Erro ao ler o dial: {erroDial.message}
        </p>
      )}

      <div className="overflow-x-auto rounded border border-neutral-200 bg-white">
        <table className="w-full text-sm">
          <thead className="bg-neutral-50 text-left text-xs uppercase text-neutral-500">
            <tr>
              <th className="px-4 py-2 font-medium">Estágio</th>
              <th className="px-4 py-2 font-medium">Hoje</th>
              <th className="px-4 py-2 font-medium">Teto</th>
              <th className="px-4 py-2 font-medium">Limiar de auto-clear</th>
              <th className="px-4 py-2 font-medium">Última mudança</th>
            </tr>
          </thead>
          <tbody className="divide-y divide-neutral-200">
            {linhas.map((d) => {
              const noTeto = d.nivel_atual === d.teto;
              // Teto N1 é o caso que docs/01 marca com "nunca autônomo": não é um
              // limite provisório à espera de medição, é decisão de doutrina.
              const nuncaAutonomo = d.teto === "N1";
              return (
                <tr key={d.estagio} className="align-top">
                  <td className="px-4 py-3">
                    <p className="font-medium">{NOME_ESTAGIO[d.estagio] ?? d.estagio}</p>
                    <p className="font-mono text-xs text-neutral-400">{d.estagio}</p>
                  </td>
                  <td className="px-4 py-3">
                    <span className="rounded bg-neutral-900 px-1.5 py-0.5 text-xs font-semibold text-white">
                      {d.nivel_atual}
                    </span>
                    <p className="mt-1 text-xs text-neutral-600">
                      {NIVEL[d.nivel_atual]?.titulo}
                    </p>
                    <p className="text-xs text-neutral-500">{NIVEL[d.nivel_atual]?.o_que_faz}</p>
                  </td>
                  <td className="px-4 py-3 text-xs text-neutral-600">
                    {d.teto}
                    {noTeto && <span className="ml-1 text-neutral-400">(no teto)</span>}
                    {nuncaAutonomo && (
                      <p className="mt-1 text-neutral-500">
                        docs/01: nunca autônomo — o teto é por natureza do estágio e nenhuma
                        chamada o sobrepõe.
                      </p>
                    )}
                  </td>
                  <td className="px-4 py-3 text-xs text-neutral-600">
                    {d.limiar_auto_clear === null ? (
                      <span className="text-neutral-500">
                        sem limiar — não auto-aceita, qualquer que seja o nível
                      </span>
                    ) : (
                      <>
                        {d.limiar_auto_clear}
                        {d.nivel_atual === "N0" || d.nivel_atual === "N1" ? (
                          <p className="mt-1 text-neutral-500">
                            sem efeito em {d.nivel_atual}: só N2/N3 auto-aceitam.
                          </p>
                        ) : null}
                      </>
                    )}
                  </td>
                  <td className="px-4 py-3 text-xs text-neutral-600">
                    <p>{dataHora(d.atualizado_em)}</p>
                    <p className="text-neutral-500">{d.atualizado_por ?? "—"}</p>
                  </td>
                </tr>
              );
            })}
          </tbody>
        </table>
      </div>

      {/* A RESSALVA QUE VIAJA COM O NÚMERO. Sem isto, alguém lê "N2" na extração e
          conclui que houve medição de concordância contra golden set. Não houve —
          é decisão de produto do dono, registrada assim na 0019 e na 0041, e o
          golden set físico é item aberto (§7.4 #8 do material de Onboarding). */}
      {linhas.some(
        (d) =>
          (d.nivel_atual === "N2" || d.nivel_atual === "N3") &&
          d.estagio.startsWith("extracao"),
      ) && (
        <div className="rounded border border-amber-300 bg-amber-50 p-3 text-sm text-amber-900">
          <p className="font-medium">Autonomia declarada, não medida</p>
          <p className="mt-1">
            Os estágios de <strong>extração</strong> acima de N1 estão nesse nível por decisão de
            produto, não por concordância medida: <code>docs/01</code> exige comparação contra um
            golden set para subir dial de estágio interpretativo, e o golden set físico ainda não
            existe. Quando existir, a medição confirma ou derruba estes níveis.
          </p>
          <p className="mt-1">
            A medição que já é possível hoje roda contra o book sintético (
            <code>portal/scripts/medir-auto-aceite.mts</code>) e vale como piso, não como
            equivalente: o book é o melhor caso — PDF gerado, texto limpo, layout conhecido.
          </p>
        </div>
      )}

      <div>
        <h2 className="text-sm font-semibold">Mudanças de dial</h2>
        <p className="mt-1 text-xs text-neutral-500">
          docs/01: toda mudança de nível é decisão versionada e reversível. Tentativa recusada
          também fica — passar do teto é justamente o que a trilha precisa guardar.
        </p>
        {trilha.length === 0 ? (
          <p className="mt-2 text-sm text-neutral-500">Nenhuma mudança de dial registrada.</p>
        ) : (
          <ul className="mt-2 divide-y divide-neutral-200 rounded border border-neutral-200 bg-white text-sm">
            {trilha.map((e, i) => (
              <li key={i} className="px-4 py-2">
                <div className="flex flex-wrap items-baseline gap-2">
                  <span
                    className={
                      e.acao === "mudanca_dial_recusada"
                        ? "rounded bg-red-100 px-1.5 py-0.5 text-xs font-medium text-red-800"
                        : "rounded bg-neutral-100 px-1.5 py-0.5 text-xs font-medium text-neutral-700"
                    }
                  >
                    {e.acao === "mudanca_dial_recusada" ? "recusada" : "aplicada"}
                  </span>
                  <span className="font-mono text-xs">{e.entidade_ref}</span>
                  <span className="text-xs text-neutral-500">
                    {e.ator} · {dataHora(e.criado_em)}
                  </span>
                </div>
                {e.acao === "mudanca_dial_recusada" ? (
                  <p className="mt-1 text-xs text-neutral-600">
                    pediu {e.depois?.pedido} com teto {e.depois?.teto}
                    {e.depois?.motivo_informado ? ` — "${e.depois.motivo_informado}"` : ""}
                  </p>
                ) : (
                  e.depois?.motivo && (
                    <p className="mt-1 text-xs text-neutral-600">{e.depois.motivo}</p>
                  )
                )}
              </li>
            ))}
          </ul>
        )}
      </div>
    </div>
  );
}
