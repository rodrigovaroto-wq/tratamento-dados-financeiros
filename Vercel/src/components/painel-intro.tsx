"use client";

import { useCallback, useEffect, useState, useSyncExternalStore } from "react";
import { MarcaOria } from "./marca-oria";
import { CeuOria } from "./ceu-oria";

// A ABERTURA DO PAINEL.
//
// QUANDO ELA TOCA (pedido do dono, 21/08): toda vez que o sistema abre e toda
// vez que alguém entra. Na prática são três gatilhos, e o `sessao` cobre os três:
//
//   • abrir o portal, recarregar a página ou abrir outra aba, porque a marca
//     abaixo mora na memória do módulo e some junto com a carga;
//   • entrar de novo, porque a sessão do Supabase muda de identidade a cada
//     login e a marca deixa de valer;
//   • ir a um mandato e voltar ao painel NÃO toca, que é a única exceção. É
//     navegação dentro da mesma sessão, e três segundos de véu a cada volta
//     viraria pedágio na tela mais usada da casa.
//
// Qualquer gesto corta a cena (clique, tecla, rolagem, toque), e quem pediu
// `prefers-reduced-motion` no sistema não vê nenhuma versão dela. A abertura
// também não segura carregamento: o painel já está pronto atrás do véu, então o
// que aparece ao fim é a tela, nunca um spinner.
//
// POR QUE `useSyncExternalStore`. A marca é estado fora do React. Copiá-la num
// efeito faria o servidor renderizar uma coisa e o cliente corrigir para outra,
// que é o lampejo de véu que esta tela não pode ter. O `getServerSnapshot`
// devolve "já vista", porque no servidor não existe navegador e o padrão seguro
// é não cobrir a tela.

const EVENTO = "oria:abertura";

/**
 * A sessão para a qual a abertura já tocou.
 *
 * Mora no MÓDULO e não no `sessionStorage` de propósito: `sessionStorage`
 * sobrevive ao recarregamento, e era isso que fazia a abertura quase nunca
 * aparecer. Na memória do módulo ela morre com a carga da página, que é
 * exatamente o gatilho "o sistema abriu".
 */
let sessaoJaVista: string | null = null;

/** 2,5s de cena + 0,5s de saída. Os 3 segundos pedidos, com o fim já contado. */
const DURACAO_MS = 2500;
const SAIDA_MS = 520;

function useJaVista(sessao: string): [boolean, () => void] {
  const assinar = useCallback((avisar: () => void) => {
    window.addEventListener(EVENTO, avisar);
    return () => window.removeEventListener(EVENTO, avisar);
  }, []);
  const jaVista = useSyncExternalStore(
    assinar,
    () =>
      sessaoJaVista === sessao ||
      (window.matchMedia?.("(prefers-reduced-motion: reduce)").matches ?? false),
    () => true,
  );
  const marcar = useCallback(() => {
    sessaoJaVista = sessao;
    window.dispatchEvent(new Event(EVENTO));
  }, [sessao]);
  return [jaVista, marcar];
}

/**
 * `sessao` identifica quem está logado AGORA. Ela vem do painel, que a lê do
 * token do Supabase: trocou de valor, houve login novo, e a abertura toca.
 */
export function PainelIntro({ sessao }: { sessao: string }) {
  const [jaVista, marcar] = useJaVista(sessao);
  const [saindo, setSaindo] = useState(false);

  // O ENCERRAMENTO É EM DOIS TEMPOS: primeiro a cena começa a sair (opacidade e
  // uma escala mínima), e só depois de a saída terminar o véu é desmontado. Um
  // desmonte direto cortaria a animação no meio, que é pior que não ter.
  useEffect(() => {
    if (jaVista) return;

    let saidaId: ReturnType<typeof setTimeout> | undefined;
    const encerrar = () => {
      setSaindo(true);
      saidaId = setTimeout(marcar, SAIDA_MS);
    };
    const cenaId = setTimeout(encerrar, DURACAO_MS);

    // ROLAR TAMBÉM CORTA, e é o gesto mais provável de quem está com pressa:
    // a mão já está no trackpad.
    const gestos: Array<keyof WindowEventMap> = ["pointerdown", "keydown", "wheel", "touchstart"];
    const aoGesto = () => {
      clearTimeout(cenaId);
      encerrar();
    };
    for (const g of gestos) window.addEventListener(g, aoGesto, { passive: true, once: true });

    return () => {
      clearTimeout(cenaId);
      clearTimeout(saidaId);
      for (const g of gestos) window.removeEventListener(g, aoGesto);
    };
  }, [jaVista, marcar]);

  if (jaVista) return null;

  return (
    <div
      // `aria-hidden` + `role="presentation"`: para um leitor de tela isto é uma
      // cortina, não conteúdo. O painel INTEIRO já está no DOM atrás — quem
      // navega por leitor nunca fica esperando os três segundos.
      aria-hidden
      role="presentation"
      className={`fixed inset-0 z-50 flex flex-col items-center justify-center overflow-hidden
                  ${saindo ? "intro-sai" : ""}`}
      style={{
        // Claro, e não grafite: a arte da marca é azul-escura sobre
        // transparência e desaparecia no escuro (ver `ceu-oria.tsx`). O gradiente
        // termina no MESMO `tinta-50` do painel, então a cortina não sai de uma
        // cor para outra — ela só deixa de existir.
        background: "radial-gradient(circle at 50% 46%, #ffffff 0%, #f1f5f9 55%, #e8eef3 100%)",
      }}
    >
      {/* O céu, no contraste cheio — o mesmo motivo que fica de fundo no painel
          depois, para a abertura e a tela serem a MESMA ilustração em dois
          volumes, e não dois desenhos diferentes. */}
      <CeuOria modo="intro" className="absolute inset-0 h-full w-full" />

      {/* Um halo atrás da marca: separa o logotipo da constelação sem precisar
          de caixa, moldura ou sombra. */}
      <div
        className="pointer-events-none absolute h-[560px] w-[560px] rounded-full"
        style={{
          background:
            "radial-gradient(circle, rgba(255,255,255,0.95) 0%, rgba(255,255,255,0.75) 42%, rgba(255,255,255,0) 68%)",
        }}
      />

      <div className="relative flex flex-col items-center px-6 text-center">
        <MarcaOria variante="completa" className="intro-marca h-40 w-40 sm:h-48 sm:w-48" />
        <p className="intro-nome mt-5 text-sm font-semibold uppercase text-tinta-800">
          Oria Partners
        </p>
        <p className="intro-verso mt-3 max-w-sm text-[13px] leading-relaxed text-tinta-500">
          Tratamento de dados financeiros. Nada aqui é fato até alguém aceitar.
        </p>
      </div>

      {/* A LINHA DE TEMPO diz quanto falta. É o que transforma "espere" em "vai
          acabar em um segundo", e é a diferença entre uma pausa e um travamento
          aos olhos de quem olha. */}
      <div className="absolute bottom-16 h-px w-40 overflow-hidden bg-tinta-200">
        <div
          className="intro-linha h-full w-full bg-acento-600"
          style={{ ["--duracao" as string]: `${DURACAO_MS}ms` }}
        />
      </div>
      <p className="intro-verso absolute bottom-8 text-[11px] tracking-wide text-tinta-400">
        clique para entrar
      </p>
    </div>
  );
}
