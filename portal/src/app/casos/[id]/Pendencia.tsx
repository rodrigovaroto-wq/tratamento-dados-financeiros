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
import { MOTIVO_REJEICAO_MIN, avisoDeRejeicao } from "@/lib/pendencia";
import { rejeitarPendencia } from "./actions";

export interface PendenciaNaTela {
  id: string;
  tipo: string;
  descricao: string | null;
  documento_id: string | null;
  severidade?: string;
  /** `false` = da lista fechada de f0/04, que nenhuma ressalva libera. */
  sobrepujavel?: boolean | null;
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

      {/* A DECISÃO DE QUEM ESTÁ LENDO — dentro de `<details>`, e isso é escolha,
          não economia de espaço. A ação normal diante de uma pendência é
          CONFERIR e corrigir; declarar que ela não procede é a exceção, e uma
          exceção com botão sempre visível vira o caminho mais curto. Fechado por
          padrão, o clique a mais é o convite a ler antes. */}
      {casoId && (
        <details className="mt-2">
          <summary className={`cursor-pointer text-xs font-medium ${cores.fraco}`}>
            Esta pendência não procede?
          </summary>
          <div className="mt-1.5 rounded border border-neutral-200 bg-white p-2">
            <p className="text-xs text-neutral-600">{avisoDeRejeicao({
              severidade: p.severidade ?? "importante", sobrepujavel: p.sobrepujavel,
            })}</p>
            <form
              action={rejeitarPendencia.bind(null, casoId, p.id)}
              className="mt-2 flex flex-wrap items-center gap-2"
            >
              {/* `required` + `minLength` espelham `fn_min_motivo_rejeicao()`: o
                  navegador recusa antes do round-trip, o banco recusa de novo, e
                  o assert (0114) prova que os dois números são o mesmo. */}
              <input
                type="text"
                name="motivo"
                required
                minLength={MOTIVO_REJEICAO_MIN}
                placeholder={`por que não procede (mín. ${MOTIVO_REJEICAO_MIN} caracteres)`}
                className="min-w-64 flex-1 rounded border border-neutral-300 px-2 py-1 text-sm"
              />
              <button
                type="submit"
                className="rounded border border-neutral-400 bg-white px-3 py-1 text-sm font-medium text-neutral-800 hover:bg-neutral-100"
              >
                Declarar improcedente
              </button>
            </form>
            <p className="mt-1 text-[11px] text-neutral-500">
              A pendência não é apagada: fica registrada como improcedente, com o seu nome e o
              seu motivo, e a contagem aparece no Portão 2.
            </p>
          </div>
        </details>
      )}
    </li>
  );
}
