"use client";

import { useEffect, useRef } from "react";

// A ILUSTRAÇÃO DA CASA — e ela não é enfeite genérico.
//
// O QUE ELA DESENHA. Um sextante: o limbo (o arco graduado), o quadro, o braço
// da alidade e a constelação que ele mede. É a marca da Oria — o instrumento
// que aparece no logotipo —, redesenhada aqui em VETOR PRÓPRIO, nunca a arte
// original. A arte do dono é um raster embutido no `.svg` e a regra do
// `marca-oria.tsx` é não mexer nela; então o que se anima é um motivo novo, que
// cita o instrumento sem traçar o desenho.
//
// POR QUE UM SEXTANTE DIZ ALGO NESTE PRODUTO. Ele existe para achar onde você
// está a partir de pontos que não mentem. É literalmente o que o portal faz com
// os documentos do cliente — e é por isso que o motivo reage à ROLAGEM: os
// arcos giram conforme se desce a página, como o braço do instrumento girando
// para tomar uma medida. A constelação, por sua vez, acompanha o PONTEIRO, com
// atraso: o céu não gruda no mouse, ele deriva.
//
// AS DUAS INTENSIDADES:
//   • `fundo` — atrás do painel, em azul de marca a 5-8% de opacidade. Tem de
//     desaparecer quando alguém está lendo um número. Se der para "ver" o
//     desenho enquanto se lê a tela, está forte demais.
//   • `intro` — na abertura, no contraste cheio, com o traço entrando desenhado
//     (o arco cresce, as estrelas acendem em cascata).
//
// A ABERTURA É CLARA, E ISSO FOI UMA CORREÇÃO. O primeiro desenho punha tudo
// sobre o grafite, e ficou bonito — menos no que importava: a arte da marca é
// azul-escura sobre transparência, e sobre grafite ela simplesmente sumia.
// Clarear o logotipo por filtro resolveria a legibilidade mexendo na arte, que
// é o que `marca-oria.tsx` proíbe. Então quem mudou foi o fundo. De quebra, a
// abertura passou a desaguar no painel sem o salto de escuro para claro.
//
// MOVIMENTO É OPCIONAL, E ISSO NÃO É DETALHE. Com `prefers-reduced-motion` o
// componente desenha UM quadro e para o laço: quem marcou essa preferência no
// sistema costuma ter um motivo clínico, e uma tela de trabalho não é lugar de
// discutir com isso.

type Modo = "fundo" | "intro";

interface Estrela {
  /** posição em fração da tela (0..1), para o desenho não depender do tamanho */
  x: number;
  y: number;
  r: number;
  /** fase do brilho — evita que todas pisquem juntas */
  fase: number;
  /** 0 = longe, 2 = perto. Manda no paralaxe e na deriva do ponteiro. */
  camada: number;
}

/** Ruído determinístico: o mesmo céu a cada carga, sem `Math.random` no render. */
function semente(i: number, n: number): number {
  const x = Math.sin(i * 127.1 + n * 311.7) * 43758.5453;
  return x - Math.floor(x);
}

function montarCeu(quantas: number): Estrela[] {
  const estrelas: Estrela[] = [];
  for (let i = 0; i < quantas; i++) {
    const camada = Math.floor(semente(i, 3) * 3);
    estrelas.push({
      x: semente(i, 1),
      y: semente(i, 2),
      r: 0.6 + semente(i, 4) * (camada === 2 ? 1.6 : 0.9),
      fase: semente(i, 5) * Math.PI * 2,
      camada,
    });
  }
  return estrelas;
}

export function CeuOria({
  modo = "fundo",
  className = "",
}: {
  modo?: Modo;
  className?: string;
}) {
  const ref = useRef<HTMLCanvasElement | null>(null);

  useEffect(() => {
    const canvas = ref.current;
    if (!canvas) return;
    const ctx = canvas.getContext("2d");
    if (!ctx) return;

    const intro = modo === "intro";
    const estrelas = montarCeu(intro ? 120 : 76);
    const reduzido = window.matchMedia?.("(prefers-reduced-motion: reduce)").matches ?? false;

    // O PONTEIRO ENTRA COM ATRASO, e é o atraso que faz o céu parecer ter massa.
    // `alvo` é onde o mouse está; `atual` persegue com interpolação — sem isso o
    // desenho gruda no cursor e vira brinquedo.
    const alvo = { x: 0.5, y: 0.5 };
    const atual = { x: 0.5, y: 0.5 };

    let largura = 0;
    let altura = 0;
    const redimensionar = () => {
      const dpr = Math.min(window.devicePixelRatio || 1, 2);
      const caixa = canvas.getBoundingClientRect();
      largura = caixa.width;
      altura = caixa.height;
      canvas.width = Math.round(largura * dpr);
      canvas.height = Math.round(altura * dpr);
      ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    };
    redimensionar();
    const observador = new ResizeObserver(redimensionar);
    observador.observe(canvas);

    const noPonteiro = (e: PointerEvent) => {
      alvo.x = e.clientX / window.innerWidth;
      alvo.y = e.clientY / window.innerHeight;
    };
    if (!reduzido) window.addEventListener("pointermove", noPonteiro, { passive: true });

    const inicio = performance.now();
    let quadro = 0;

    const desenhar = (agora: number) => {
      const t = reduzido ? 1400 : agora - inicio;
      // A ENTRADA DURA 1,4s e depois o desenho só respira. Um traço que continua
      // "chegando" enquanto a pessoa lê é um traço que ela vai olhar de novo.
      const entrada = Math.min(1, t / 1400);
      const suave = 1 - Math.pow(1 - entrada, 3);

      atual.x += (alvo.x - atual.x) * 0.045;
      atual.y += (alvo.y - atual.y) * 0.045;
      const rolagem = reduzido ? 0 : window.scrollY;

      ctx.clearRect(0, 0, largura, altura);

      // --- o sextante ------------------------------------------------------
      // NO FUNDO ELE NASCE FORA DA TELA, no canto inferior direito, e o que se
      // vê é o limbo cruzando o alto da página à direita. A escolha é de
      // composição: as cartas do painel são brancas e opacas, então a
      // ilustração só existe nas MARGENS — desenhá-la no miolo seria desenhar
      // debaixo do tampo da mesa. Ali, na goteira à direita, ela aparece.
      const cx = intro ? largura / 2 : largura * 0.99;
      const cy = intro ? altura * 0.5 : altura * 1.02;
      const raio = intro ? Math.min(largura, altura) * 0.38 : Math.max(largura, altura) * 0.66;

      // A ROLAGEM GIRA O INSTRUMENTO. É o vínculo entre o que a pessoa faz e o
      // que a tela responde — e é sutil de propósito: 1.000px de rolagem giram
      // cerca de 11 graus, não uma volta.
      const giro = rolagem * 0.0002 + (reduzido ? 0 : t * 0.000012);
      const traco = intro ? 1.4 : 1;

      ctx.save();
      ctx.translate(cx, cy);
      ctx.rotate(giro);

      // Uma cor só nos dois modos — o azul de marca. O que muda é a opacidade:
      // a abertura pode ser vista, o fundo do painel não pode.
      const corArco = (a: number) => `rgba(14, 116, 144, ${a})`;

      // O LIMBO — o arco graduado, que é a parte que todo mundo reconhece.
      const abertura = Math.PI / 3;
      const inicioArco = -Math.PI / 2 - abertura / 2;
      const fimArco = inicioArco + abertura * suave;

      for (const [k, esp] of [
        [1, 2.2],
        [0.86, 0.9],
        [0.7, 0.6],
      ] as const) {
        ctx.beginPath();
        ctx.arc(0, 0, raio * k, inicioArco, fimArco);
        ctx.strokeStyle = corArco((intro ? 0.42 : 0.16) * (k === 1 ? 1 : 0.6));
        ctx.lineWidth = esp * traco;
        ctx.stroke();
      }

      // AS GRADUAÇÕES do limbo — os traços da escala. São o detalhe que faz o
      // arco virar INSTRUMENTO em vez de arco.
      const marcas = 34;
      for (let i = 0; i <= marcas; i++) {
        const p = i / marcas;
        if (p > suave) break;
        const ang = inicioArco + abertura * p;
        const comprido = i % 5 === 0;
        const de = raio * (comprido ? 0.93 : 0.96);
        ctx.beginPath();
        ctx.moveTo(Math.cos(ang) * de, Math.sin(ang) * de);
        ctx.lineTo(Math.cos(ang) * raio, Math.sin(ang) * raio);
        ctx.strokeStyle = corArco(intro ? (comprido ? 0.5 : 0.28) : comprido ? 0.17 : 0.09);
        ctx.lineWidth = (comprido ? 1.2 : 0.7) * traco;
        ctx.stroke();
      }

      // O QUADRO e a ALIDADE — as duas hastes do centro até o limbo, e o braço
      // móvel que faz a leitura. O braço oscila devagar; é o único elemento que
      // se mexe sozinho, e por isso ele é o que dá vida ao desenho parado.
      // O MIOLO FICA VAZIO NA ABERTURA. As hastes e a alidade convergem no
      // centro do instrumento, que é exatamente onde o logotipo está — e uma
      // linha atravessando a marca é a única coisa que este arquivo não pode
      // fazer. Elas passam a nascer a 58% do raio: o desenho continua inteiro
      // para o olho, e o centro fica livre.
      const deLinha = intro ? raio * 0.58 : 0;
      const hastes = [inicioArco, inicioArco + abertura];
      for (const ang of hastes) {
        ctx.beginPath();
        ctx.moveTo(Math.cos(ang) * deLinha, Math.sin(ang) * deLinha);
        ctx.lineTo(Math.cos(ang) * raio * suave, Math.sin(ang) * raio * suave);
        ctx.strokeStyle = corArco(intro ? 0.26 : 0.1);
        ctx.lineWidth = 1.1 * traco;
        ctx.stroke();
      }

      const balanco = Math.sin(t * 0.0004) * 0.5 + 0.5;
      const angAlidade = inicioArco + abertura * (0.15 + balanco * 0.7);
      ctx.beginPath();
      ctx.moveTo(Math.cos(angAlidade) * deLinha, Math.sin(angAlidade) * deLinha);
      ctx.lineTo(Math.cos(angAlidade) * raio * 1.04 * suave, Math.sin(angAlidade) * raio * 1.04 * suave);
      ctx.strokeStyle = corArco(intro ? 0.5 : 0.16);
      ctx.lineWidth = 1.6 * traco;
      ctx.stroke();

      if (!intro) {
        ctx.beginPath();
        ctx.arc(0, 0, 3.2 * traco, 0, Math.PI * 2);
        ctx.fillStyle = corArco(0.12);
        ctx.fill();
      }

      ctx.restore();

      // --- a constelação ---------------------------------------------------
      // As estrelas ACENDEM EM CASCATA na entrada: todas de uma vez é um flash,
      // e flash em tela de trabalho é agressivo.
      const posicoes: Array<{ x: number; y: number; a: number }> = [];
      estrelas.forEach((e, i) => {
        const atraso = (i / estrelas.length) * 0.55;
        const acendeu = Math.max(0, Math.min(1, (entrada - atraso) / 0.45));
        if (acendeu <= 0) return;

        const profundidade = 0.4 + e.camada * 0.55;
        const x = e.x * largura + (atual.x - 0.5) * profundidade * 26;
        const y =
          e.y * altura +
          (atual.y - 0.5) * profundidade * 18 -
          (reduzido ? 0 : rolagem * 0.03 * profundidade);

        const brilho = 0.55 + 0.45 * Math.sin(t * 0.0011 + e.fase);
        const a = acendeu * brilho * (intro ? 0.85 : 0.5);
        posicoes.push({ x, y, a });

        ctx.beginPath();
        ctx.arc(x, y, e.r * (intro ? 1 : 0.85), 0, Math.PI * 2);
        ctx.fillStyle = `rgba(14, 116, 144, ${a * (intro ? 0.5 : 0.5)})`;
        ctx.fill();
      });

      // AS LINHAS DA CONSTELAÇÃO só ligam vizinhas, e somem com a distância —
      // é o que impede a malha de virar teia. O limite quadrático evita a raiz
      // quadrada em ~7 mil pares por quadro.
      const limite = intro ? 118 : 132;
      const limite2 = limite * limite;
      for (let i = 0; i < posicoes.length; i++) {
        for (let j = i + 1; j < posicoes.length; j++) {
          const dx = posicoes[i].x - posicoes[j].x;
          const dy = posicoes[i].y - posicoes[j].y;
          const d2 = dx * dx + dy * dy;
          if (d2 > limite2) continue;
          const forca = (1 - d2 / limite2) * Math.min(posicoes[i].a, posicoes[j].a);
          ctx.beginPath();
          ctx.moveTo(posicoes[i].x, posicoes[i].y);
          ctx.lineTo(posicoes[j].x, posicoes[j].y);
          ctx.strokeStyle = `rgba(14, 116, 144, ${forca * (intro ? 0.26 : 0.2)})`;
          ctx.lineWidth = 0.6;
          ctx.stroke();
        }
      }

      if (!reduzido) quadro = requestAnimationFrame(desenhar);
    };

    quadro = requestAnimationFrame(desenhar);

    return () => {
      cancelAnimationFrame(quadro);
      observador.disconnect();
      window.removeEventListener("pointermove", noPonteiro);
    };
  }, [modo]);

  return (
    <canvas
      ref={ref}
      aria-hidden
      className={className}
      // DECORAÇÃO NÃO RECEBE CLIQUE. Sem isto o canvas cobriria a tela inteira e
      // engoliria todo o painel — o defeito clássico de fundo animado.
      style={{ pointerEvents: "none" }}
    />
  );
}
