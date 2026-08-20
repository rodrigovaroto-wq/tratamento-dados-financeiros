import Link from "next/link";
import { createClient } from "@/lib/supabase/server";

// A LISTA COMPLETA DA INSTALAÇÃO — a tela que substitui os recados de prosa.
//
// Ela responde uma pergunta que o sistema não sabia responder sobre si mesmo:
// "este banco tem tudo o que o portal precisa para não mentir?". Antes da 0131 a
// resposta morava em `ESTADO.md`, espalhada por 1.400 linhas de histórico, e
// ninguém a lia com a tela aberta.
//
// A ORDEM É A DA DOR, e vem do catálogo (`ordem`), não desta tela: o que quebra a
// tela mais visível vem primeiro. Ordenar aqui por número de migration daria uma
// lista cronológica — verdadeira e inútil para decidir o que fazer agora.

type Linha = {
  chave: string;
  migration: string;
  tipo: "tabela" | "coluna" | "funcao" | "seed" | "comportamento";
  objeto: string;
  presente: boolean;
  detalhe: string | null;
  porque: string;
  severidade: "bloqueante" | "importante" | "informativo";
};

const ROTULO_TIPO: Record<Linha["tipo"], string> = {
  tabela: "tabela",
  coluna: "coluna",
  funcao: "função",
  seed: "carga inicial",
  comportamento: "efeito",
};

export default async function InstalacaoPage() {
  const supabase = await createClient();
  const { data, error } = await supabase.rpc("fn_instalacao_conferir");

  if (error) {
    return (
      <div className="space-y-4">
        <h1 className="text-lg font-semibold">Instalação</h1>
        {/* A SONDA PODE SER O QUE FALTA, e aqui — diferente do aviso no painel —
            dizer isso é obrigatório: quem abriu esta tela veio perguntar sobre a
            instalação, e "não sei responder" é uma resposta legítima, desde que
            venha com a causa e o caminho. */}
        <div className="rounded border border-amber-300 bg-amber-50 p-4 text-sm text-amber-900">
          <p className="font-medium">Não consegui conferir a instalação.</p>
          <p className="mt-1">
            O motivo mais provável é que a própria migration desta tela não foi aplicada —
            ela cria <code className="font-mono text-xs">fn_instalacao_conferir</code>. Aplique{" "}
            <code className="font-mono text-xs">
              db/migrations/0131_instalacao_que_se_declara.sql
            </code>{" "}
            e recarregue.
          </p>
          <p className="mt-2 text-xs opacity-80">Erro do banco: {error.message}</p>
        </div>
      </div>
    );
  }

  const linhas = (data as Linha[] | null) ?? [];
  const ausentes = linhas.filter((l) => !l.presente);
  const bloqueantes = ausentes.filter((l) => l.severidade === "bloqueante");
  const completa = ausentes.length === 0;

  return (
    <div className="space-y-6">
      <div>
        <Link href="/casos" className="text-sm text-tinta-500 underline">
          ← Voltar ao painel
        </Link>
        <h1 className="mt-2 text-lg font-semibold">Instalação</h1>
        <p className="mt-1 max-w-2xl text-sm text-tinta-500">
          O que precisa existir neste banco para o portal não mostrar um traço no lugar de um
          número. Cada linha era um recado em prosa no <code className="font-mono text-xs">ESTADO.md</code>{" "}
          — que ninguém lê com a tela aberta.
        </p>
      </div>

      {completa ? (
        <p className="rounded border border-emerald-200 bg-emerald-50 px-4 py-3 text-sm text-emerald-800">
          ✓ Os {linhas.length} requisitos estão presentes. Nenhuma tela está mostrando número
          ausente por falta de migration.
        </p>
      ) : (
        <p
          className={`rounded border px-4 py-3 text-sm ${
            bloqueantes.length > 0
              ? "border-red-300 bg-red-50 text-red-800"
              : "border-amber-300 bg-amber-50 text-amber-900"
          }`}
        >
          {ausentes.length} de {linhas.length} requisitos faltando
          {bloqueantes.length > 0 && `, ${bloqueantes.length} deles bloqueante(s)`}.
        </p>
      )}

      {/* O QUE ESTA TELA NÃO PROVA, dito nela e não só no comentário da migration.
          Um painel de saúde que se apresenta como mais certeiro do que é ensina a
          confiar nele além do que ele mede — e aí a próxima falha real passa. */}
      <div className="rounded border border-tinta-200 bg-tinta-50 p-3 text-xs text-tinta-600">
        <strong>O que esta conferência garante:</strong> objeto ausente é migration ausente, sem
        dúvida. <strong>O que ela não garante:</strong> que o objeto presente esteja na versão
        certa — trocar o corpo de uma função deixa a assinatura idêntica, e nenhuma sonda de
        catálogo vê isso. Quem confere comportamento é a suíte de testes, no CI.
      </div>

      <div className="overflow-x-auto rounded border border-tinta-200 bg-white">
        <table className="w-full text-left text-sm">
          <thead className="text-xs uppercase text-tinta-500">
            <tr>
              <th className="px-3 py-2">Estado</th>
              <th className="px-3 py-2">O que acontece sem isto</th>
              <th className="px-3 py-2">Migration</th>
              <th className="px-3 py-2">Objeto</th>
            </tr>
          </thead>
          <tbody className="divide-y divide-tinta-100">
            {linhas.map((l) => (
              <tr key={l.chave} className={l.presente ? "" : "bg-amber-50/40"}>
                <td className="whitespace-nowrap px-3 py-2 align-top">
                  {l.presente ? (
                    <span className="rounded bg-emerald-100 px-1.5 py-0.5 text-xs font-medium uppercase text-emerald-700">
                      ok
                    </span>
                  ) : (
                    // A SEVERIDADE ESTÁ NA PALAVRA, não só na cor: cor sozinha
                    // não carrega significado nesta casa, e "falta" em vermelho
                    // contra "falta" em âmbar não diz a diferença a quem não sabe
                    // que ela existe.
                    <span
                      className={`rounded px-1.5 py-0.5 text-xs font-medium uppercase ${
                        l.severidade === "bloqueante"
                          ? "bg-red-100 text-red-700"
                          : "bg-amber-100 text-amber-800"
                      }`}
                    >
                      {l.severidade === "bloqueante" ? "bloqueia" : "falta"}
                    </span>
                  )}
                </td>
                <td className="px-3 py-2 align-top">
                  <span className={l.presente ? "text-tinta-500" : "text-tinta-800"}>
                    {l.porque}
                  </span>
                  {l.detalhe && (
                    <span className="ml-1 whitespace-nowrap text-xs text-tinta-400">
                      ({l.detalhe})
                    </span>
                  )}
                </td>
                <td className="whitespace-nowrap px-3 py-2 align-top font-mono text-xs text-tinta-600">
                  {l.migration}
                </td>
                <td className="px-3 py-2 align-top font-mono text-xs text-tinta-500">
                  {l.objeto}
                  <span className="ml-1 font-sans text-xs text-tinta-400">
                    {ROTULO_TIPO[l.tipo]}
                  </span>
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>

      {ausentes.length > 0 && (
        <div className="rounded border border-tinta-200 bg-white p-4 text-sm">
          <h2 className="text-sm font-semibold">Como resolver</h2>
          <p className="mt-1 text-tinta-600">
            As migrations se aplicam na ordem, com o comando que está no{" "}
            <code className="font-mono text-xs">db/README.md</code>. As que faltam aqui:
          </p>
          <pre className="mt-2 overflow-x-auto rounded bg-tinta-50 p-3 font-mono text-xs text-tinta-700">
{[...new Set(ausentes.filter((l) => l.tipo !== "comportamento").map((l) => l.migration))]
  .sort()
  .map((m) => `supabase db execute --file db/migrations/${m}_*.sql`)
  .join("\n") || "— nenhuma: o que falta não é migration."}
          </pre>
          {ausentes.some((l) => l.tipo === "comportamento") && (
            <p className="mt-3 text-tinta-600">
              E há item que <strong>não é migration</strong>: reimportar{" "}
              <code className="font-mono text-xs">n8n/workflow.e1-ingestao.json</code> no n8n. O
              n8n executa o JSON importado, não o do repositório — dar merge não reimporta.
            </p>
          )}
        </div>
      )}
    </div>
  );
}
