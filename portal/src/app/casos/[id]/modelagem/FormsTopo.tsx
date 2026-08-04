"use client";

import { useActionState } from "react";
import { definirParametros, ativarPremissa, type Resultado } from "./actions";

// OS FORMULÁRIOS DOS PASSOS 1 E 2.
//
// Eles viraram componentes de cliente pelo MESMO motivo da seção 3, e não por
// simetria: enquanto qualquer ação da tela navegava (`redirect`) ou dependia de um
// re-render do servidor para mostrar o que aconteceu, ativar uma premissa no passo
// 2 remontava a página inteira — e levava junto tudo o que estava escolhido e não
// salvo lá embaixo, no passo 3. O sintoma que o dono via ("a seção 3 fecha do
// nada") tinha esta como uma das origens: ele ativava uma premissa e perdia a
// edição em curso.
//
// Com `useActionState`, o resultado volta como VALOR e aparece ao lado do próprio
// botão. O `revalidatePath` do servidor continua atualizando os dados — só que
// agora sem desmontar nada.

function Aviso({ r }: { r: Resultado }) {
  if (!r) return null;
  return (
    <span
      role="status"
      className={`rounded px-2 py-0.5 text-xs ${
        r.tom === "ok" ? "bg-emerald-100 text-emerald-900" : "bg-amber-100 text-amber-900"
      }`}
    >
      {r.texto}
    </span>
  );
}

export function FormParametros({
  casoId, children,
}: {
  casoId: string;
  children: React.ReactNode;
}) {
  const [r, act, salvando] = useActionState(definirParametros.bind(null, casoId), null as Resultado);
  return (
    <form action={act} className="grid gap-3 sm:grid-cols-2">
      {children}
      <div className="flex items-end gap-2">
        <button
          type="submit" disabled={salvando}
          className="rounded bg-neutral-900 px-3 py-1.5 text-sm font-medium text-white hover:bg-neutral-700 disabled:opacity-50"
        >
          {salvando ? "Salvando…" : "Salvar parâmetros"}
        </button>
        <Aviso r={r} />
      </div>
    </form>
  );
}

export function FormPremissa({
  casoId, codigo, ativa, children,
}: {
  casoId: string;
  codigo: string;
  ativa: boolean;
  children: React.ReactNode;
}) {
  const [r, act, salvando] = useActionState(ativarPremissa.bind(null, casoId), null as Resultado);
  return (
    <form
      action={act}
      className={`flex flex-wrap items-center gap-2 rounded border px-2 py-1.5 text-sm ${
        ativa ? "border-emerald-200 bg-emerald-50" : "border-neutral-200"
      }`}
    >
      <input type="hidden" name="codigo" value={codigo} />
      {children}
      <button
        type="submit" disabled={salvando}
        className="rounded border border-neutral-300 px-2 py-0.5 text-xs hover:bg-neutral-100 disabled:opacity-50"
      >
        {salvando ? "…" : ativa ? "Atualizar" : "Ativar"}
      </button>
      <Aviso r={r} />
    </form>
  );
}
