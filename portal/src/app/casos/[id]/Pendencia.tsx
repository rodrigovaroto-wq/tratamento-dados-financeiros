// COMO UMA PENDÊNCIA APARECE NA TELA.
//
// POR QUE VIROU COMPONENTE. As mensagens de pendência são geradas no banco (é lá que
// a medição acontece) e chegam como UM parágrafo com vários fatos emendados por `;`,
// citando coluna, entidade e período no vocabulário interno. Antes cada seção da tela
// jogava esse texto inteiro num `<li>`, e o resultado era um bloco de seis linhas em
// que o fato principal — o que está errado e onde — ficava no meio.
//
// O pedido do dono (07/08/2026): um fato por linha, com travessão; e a tela tem de
// dizer EM QUAL ARQUIVO está o problema.
//
// SOBRE "EM QUAL LINHA". O sistema não guarda número de linha do PDF — o extrator
// devolve conta, coluna e valor, não coordenada de página. O que existe, e é o que
// serve para achar o erro no original, é o RÓTULO da conta e a COLUNA (período /
// entidade). Então é isso que fica em destaque: os rótulos citados pela mensagem
// aparecem como uma lista à parte, que é a "linha" no sentido de quem vai conferir.
// Inventar número de linha seria dar precisão falsa a quem precisa procurar.
//
// E POR QUE ELA GANHOU UM BOTÃO (07/08/2026). O portal só sabia dizer sim: a
// única ação do Portão 2 era *aprovar*, que é exatamente o que a regra proíbe
// enquanto houver pendência bloqueante viva. Quem olhava um caso travado por uma
// pendência que NÃO PROCEDE — o motor errou, a conta está no outro documento —
// não tinha o que fazer na tela. `f0/04` prevê esse caminho desde a F0
// (`rejeitada`); faltava código e faltava botão.
import { partesDaDescricao, rotuloDaPendencia, suavizarMensagem } from "@/lib/rotulos";
import { BOTOES_DECISAO, ROTULO_POR_ESTADO, rotuloDoEstado } from "@/lib/pendencia";
import { decidirPendencia } from "./actions";

export interface PendenciaNaTela {
  id: string;
  tipo: string;
  descricao: string | null;
  documento_id: string | null;
  severidade?: string;
  /** estado de f0/04: `aberta`, um dos dois de tratamento, ou um dos decididos */
  estado?: string;
}

/** Rótulos entre aspas que a mensagem cita — as contas a conferir no original. */
function rotulosCitados(texto: string): string[] {
  return [...new Set([...texto.matchAll(/"([^"]{2,80})"/g)].map((m) => m[1]))];
}

/** Tira do texto os rótulos que já vão aparecer na lista, para não repetir. */
function semALista(texto: string): string {
  const cortado = texto.replace(/Rótulos que a extração TROUXE[^.]*?:\s*/i, "")
    .replace(/(?:"[^"]+"\s*(?:\[[^\]]*\])?\s*,?\s*)+/g, "")
    .replace(/Contas:\s*$/i, "")
    .replace(/\s*\.\s*\./g, ".")
    .replace(/\s{2,}/g, " ")
    .trim();
  return cortado.length > 20 ? cortado : texto;
}

export function ItemPendencia({
  p, arquivo, tom, casoId,
}: {
  p: PendenciaNaTela;
  /** nome do arquivo de origem, quando a pendência aponta para um documento */
  arquivo: string | null;
  tom: "amber" | "red";
  /** quando informado, o item ganha a ação de declarar a pendência improcedente */
  casoId?: string;
}) {
  const cores = tom === "red"
    ? { caixa: "border-red-200 bg-red-50 text-red-900", chip: "bg-red-100 text-red-800", fraco: "text-red-700" }
    : { caixa: "border-amber-200 bg-amber-50 text-amber-900", chip: "bg-amber-100 text-amber-800", fraco: "text-amber-700" };

  const bruto = p.descricao ?? "Sem descrição.";
  const rotulos = rotulosCitados(bruto);
  const partes = partesDaDescricao(suavizarMensagem(semALista(bruto)));

  return (
    <li className={`rounded border px-3 py-2 text-sm ${cores.caixa}`}>
      <div className="mb-1 flex flex-wrap items-center gap-2">
        <span className={`rounded px-1.5 py-0.5 text-xs font-medium ${cores.chip}`}>
          {rotuloDaPendencia(p.tipo)}
        </span>
        {/* O ARQUIVO, quando se sabe qual é. "Sem arquivo específico" não é falha:
            divergência entre documentos é do CASO, não de um deles — e dizer isso é
            melhor que deixar o espaço vazio, que se lê como informação perdida. */}
        <span className={`text-xs ${cores.fraco}`}>
          {arquivo ? `Arquivo: ${arquivo}` : "Vale para o caso, não para um arquivo específico"}
        </span>
        {/* O ANDAMENTO, quando alguém já mexeu. Sem isto, uma pendência que já foi
            pedida ao cliente é visualmente idêntica a uma que ninguém tocou — e o
            resultado é pedir duas vezes. */}
        {p.estado && p.estado !== "aberta" && (
          <span className={`rounded px-1.5 py-0.5 text-xs font-medium ${
            ROTULO_POR_ESTADO[p.estado]?.chip ?? "bg-neutral-200 text-neutral-700"
          }`}>
            {ROTULO_POR_ESTADO[p.estado]?.rotulo ?? rotuloDoEstado(p.estado)}
          </span>
        )}
      </div>

      {/* UM FATO POR LINHA, com travessão. A primeira parte é a frase principal e
          vem sem marcador; as demais são qualificações dela. */}
      <p>{partes[0]}</p>
      {partes.length > 1 && (
        <ul className="mt-1 space-y-0.5">
          {partes.slice(1).map((parte, i) => (
            <li key={i} className="flex gap-1.5">
              <span aria-hidden className={cores.fraco}>—</span>
              <span>{parte}</span>
            </li>
          ))}
        </ul>
      )}

      {rotulos.length > 0 && (
        <div className="mt-1.5">
          <p className={`text-xs font-medium ${cores.fraco}`}>
            Onde conferir no arquivo — {rotulos.length === 1 ? "esta linha" : `estas ${rotulos.length} linhas`}:
          </p>
          <ul className="mt-0.5 flex flex-wrap gap-1">
            {rotulos.map((r) => (
              <li key={r} className={`rounded px-1.5 py-0.5 text-xs ${cores.chip}`}>{r}</li>
            ))}
          </ul>
        </div>
      )}

      {/* OS TRÊS BOTÕES (0109). Sem formulário: nem motivo, nem data.
          Pedido do dono — o clique registra a decisão e o rótulo colorido passa
          a aparecer no topo do item.

          FICAM VISÍVEIS, sem `<details>`. A versão anterior escondia a ação
          atrás de um clique a mais, de propósito, para que declarar improcedente
          não fosse o caminho mais curto. Com três botões e nenhum campo, esse
          cuidado vira só atrito: a decisão agora É a interface. */}
      {casoId && (
        <div className="mt-2 flex flex-wrap items-center gap-2 border-t border-white/40 pt-2">
          {BOTOES_DECISAO.map((b) => (
            <form key={b.decisao} action={decidirPendencia.bind(null, casoId, p.id, b.decisao)}>
              <button
                type="submit"
                title={b.efeito}
                className={`rounded border px-2.5 py-1 text-xs font-semibold ${b.classe}`}
              >
                {b.rotulo}
              </button>
            </form>
          ))}
        </div>
      )}
    </li>
  );
}
