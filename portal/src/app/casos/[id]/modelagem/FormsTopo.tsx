"use client";

import { useActionState, useState } from "react";
import { definirParametros, ativarPremissa, desativarPremissa, type Resultado } from "./actions";

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
  // Qual das duas ações respondeu por ÚLTIMO. Sem isto, o resultado da remoção
  // ("Premissa removida") ficaria na tela depois de uma reativação bem-sucedida,
  // afirmando o oposto do estado atual — e o aviso ao lado do botão é justamente
  // o que o analista usa para saber se o clique pegou.
  const [ultima, setUltima] = useState<"ativar" | "remover" | null>(null);

  const [r, act, salvando] = useActionState(
    async (prev: Resultado, fd: FormData) => {
      const res = await ativarPremissa(casoId, prev, fd);
      setUltima("ativar");
      return res;
    }, null as Resultado);

  // A REMOÇÃO É O MESMO FORMULÁRIO, por `formAction`. Formulário aninhado é HTML
  // inválido (o navegador desmonta o de dentro), e dois formulários lado a lado
  // separariam os campos de valor do botão que os grava. O `formAction` do React
  // 19 troca só o destino do envio, e o `codigo` — a única coisa que a remoção
  // precisa — já vai no hidden.
  const [rRem, actRemover, removendo] = useActionState(
    async (prev: Resultado, fd: FormData) => {
      const res = await desativarPremissa(casoId, prev, fd);
      setUltima("remover");
      return res;
    }, null as Resultado);
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
        type="submit" disabled={salvando || removendo}
        className="rounded border border-neutral-300 px-2 py-0.5 text-xs hover:bg-neutral-100 disabled:opacity-50"
      >
        {salvando ? "…" : ativa ? "Atualizar" : "Ativar"}
      </button>
      {/* SÓ APARECE NA PREMISSA ATIVA: um "Remover" ao lado de "Ativar" ofereceria
          desfazer o que ainda não foi feito, e é o tipo de botão que se clica por
          engano. Os valores digitados NÃO se perdem na remoção (a 0104 preserva
          `valores`), então o custo de errar o clique é reativar — por isso não há
          diálogo de confirmação no caminho de quem acerta. */}
      {ativa && (
        <button
          type="submit" formAction={actRemover} disabled={salvando || removendo}
          title={"Desativa a premissa neste caso e desfaz os vínculos que ela dirigia. "
            + "Os valores digitados ficam guardados."}
          className="rounded border border-red-200 px-2 py-0.5 text-xs text-red-700 hover:bg-red-50 disabled:opacity-50"
        >
          {removendo ? "removendo…" : "Remover"}
        </button>
      )}
      {/* Um aviso só, com o resultado da última ação que respondeu: dois avisos
          lado a lado deixariam "Premissa ativada" ao lado de "Premissa removida",
          e o analista não saberia qual é o estado de agora. */}
      <Aviso r={ultima === "remover" ? rRem : r} />
    </form>
  );
}
