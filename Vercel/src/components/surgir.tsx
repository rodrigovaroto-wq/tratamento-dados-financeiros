"use client";

import { useEffect, useRef } from "react";

// OS BLOCOS ENTRAM CONFORME SE ROLA.
//
// O pedido foi "algo que se mexa quando o usuário rola". O jeito ERRADO de
// atender é amarrar transformações à posição da rolagem quadro a quadro: isso
// custa layout em cada evento e, num painel, faz o número tremer enquanto
// alguém tenta lê-lo. O jeito certo é este — `IntersectionObserver` avisa UMA
// vez que o bloco entrou na tela, a animação roda no compositor, e o observador
// larga o elemento em seguida. Custo zero depois do primeiro quadro.
//
// A REDE DE SEGURANÇA IMPORTA MAIS QUE O EFEITO. O bloco começa invisível, e
// conteúdo invisível é conteúdo perdido se qualquer coisa falhar. Por isso há um
// prazo: passados 1,2s, ele aparece de qualquer jeito — sem observador, sem
// animação, sem discussão. Uma tela de conferência pode ficar sem enfeite; não
// pode ficar sem o número.
export function Surgir({
  atraso = 0,
  className = "",
  children,
}: {
  /** escalona um bloco depois do outro, em ms */
  atraso?: number;
  className?: string;
  children: React.ReactNode;
}) {
  const ref = useRef<HTMLDivElement | null>(null);

  useEffect(() => {
    const el = ref.current;
    if (!el) return;

    const mostrar = () => {
      el.style.opacity = "";
      el.classList.add("surgir");
    };

    if (window.matchMedia?.("(prefers-reduced-motion: reduce)").matches) {
      el.style.opacity = "";
      return;
    }

    const prazo = setTimeout(mostrar, 1200);
    const observador = new IntersectionObserver(
      (entradas) => {
        for (const e of entradas) {
          if (!e.isIntersecting) continue;
          clearTimeout(prazo);
          mostrar();
          observador.unobserve(e.target);
        }
      },
      // Dispara um pouco ANTES de o bloco encostar na borda: a animação começa
      // enquanto ele ainda sobe, e chega pronta ao campo de leitura.
      { rootMargin: "0px 0px -6% 0px", threshold: 0.05 },
    );
    observador.observe(el);

    return () => {
      clearTimeout(prazo);
      observador.disconnect();
    };
  }, []);

  return (
    <div
      ref={ref}
      className={className}
      style={{ opacity: 0, ["--atraso" as string]: `${atraso}ms` }}
    >
      {children}
    </div>
  );
}
