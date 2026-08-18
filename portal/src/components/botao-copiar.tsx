"use client";

import { useEffect, useRef, useState } from "react";

// COPIAR O TEXTO PRONTO — o gesto que a aba de perguntas existe para servir.
//
// O sistema não envia nada ao cliente (docs/01: o sistema sugere, o humano
// decide), então o caminho real da pergunta é: ler, copiar, colar no e-mail que
// o analista já ia escrever. Selecionar quatro linhas com o mouse dentro de um
// cartão funciona, mas leva junto o que estiver em volta — e o que sai daqui é
// texto que vai para fora da casa.
//
// POR QUE TEM PLANO B. `navigator.clipboard` só existe em contexto seguro
// (https ou localhost). Num portal aberto por IP na rede interna ele
// simplesmente não está definido, e um botão que não faz nada e não diz nada é
// pior que botão nenhum. O plano B é o `execCommand("copy")` de sempre —
// obsoleto, e ainda assim o que funciona onde o moderno não existe. Falhando os
// dois, a tela DIZ que falhou, em vez de piscar "Copiado" sem ter copiado.
export function BotaoCopiar({
  texto,
  rotulo = "Copiar pergunta",
  className,
}: {
  texto: string;
  rotulo?: string;
  className?: string;
}) {
  const [estado, setEstado] = useState<"parado" | "copiado" | "falhou">("parado");
  const temporizador = useRef<ReturnType<typeof setTimeout> | null>(null);

  // O aviso volta ao normal sozinho; sem a limpeza, sair da tela no meio do
  // intervalo deixaria o `setState` disparando sobre um componente desmontado.
  useEffect(() => () => {
    if (temporizador.current) clearTimeout(temporizador.current);
  }, []);

  const avisar = (novo: "copiado" | "falhou") => {
    setEstado(novo);
    if (temporizador.current) clearTimeout(temporizador.current);
    temporizador.current = setTimeout(() => setEstado("parado"), 2500);
  };

  const copiar = async () => {
    try {
      if (navigator.clipboard?.writeText) {
        await navigator.clipboard.writeText(texto);
        avisar("copiado");
        return;
      }
    } catch {
      // cai no plano B — permissão negada é tão comum quanto contexto inseguro
    }
    try {
      const area = document.createElement("textarea");
      area.value = texto;
      area.setAttribute("readonly", "");
      area.style.position = "fixed";
      area.style.opacity = "0";
      document.body.appendChild(area);
      area.select();
      const deu = document.execCommand("copy");
      document.body.removeChild(area);
      avisar(deu ? "copiado" : "falhou");
    } catch {
      avisar("falhou");
    }
  };

  return (
    <span className="inline-flex items-center gap-2">
      <button type="button" onClick={copiar} className={className ?? "btn-secundario"}>
        {rotulo}
      </button>
      {/* `aria-live` porque a confirmação é a única resposta do gesto: sem ela,
          quem usa leitor de tela clica e não fica sabendo se copiou. */}
      <span
        aria-live="polite"
        className={`text-xs font-medium ${estado === "falhou" ? "text-red-700" : "text-emerald-700"}`}
      >
        {estado === "copiado" && "copiado"}
        {estado === "falhou" && "não foi possível copiar — selecione o texto acima"}
      </span>
    </span>
  );
}
