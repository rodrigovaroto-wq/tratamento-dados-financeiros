"use client";

import { useActionState, useState } from "react";
import { aplicarEmLote, salvarSecao, type Resultado } from "./actions";

// A SEÇÃO 3 DA MODELAGEM, COM ESTADO PRÓPRIO — e por que ela precisou virar
// componente de cliente.
//
// O RELATO DO DONO, na terceira rodada: "a seção 3 fecha do nada ENQUANTO eu
// estou editando". Não era mais o clique em "aplicar em lote" — era no meio da
// edição, sem submeter nada.
//
// A CAUSA: a página inteira era Server Component e os ~203 seletores de linha
// eram NÃO CONTROLADOS (`defaultValue`). Nesse arranjo, qualquer re-render vindo
// do servidor troca o DOM e leva junto tudo o que estava escolhido e ainda não
// foi salvo — e o scroll volta ao topo. Re-render do servidor acontece muito mais
// do que se imagina: o `revalidatePath` de QUALQUER ação da tela (ativar uma
// premissa no passo 2, por exemplo), o `redirect` que eu mesmo tinha introduzido
// para mostrar o aviso, e o próprio App Router, que rebusca o payload do servidor
// ao reganhar foco na janela ou ao voltar pelo histórico. Trocar de aba e voltar
// bastava.
//
// O CONSERTO, e ele é estrutural, não cosmético:
//
//   • a escolha de cada linha vive em ESTADO DE REACT aqui dentro (`escolhas`),
//     não no DOM. Re-render do servidor atualiza os dados ao redor e o estado
//     local permanece, porque o componente continua na mesma posição da árvore;
//   • as ações não navegam mais: `useActionState` recebe o resultado e a mensagem
//     aparece DENTRO desta seção, ao lado do botão que foi clicado;
//   • `key` estável por seção, para o React nunca remontar o bloco;
//   • a seção não tem, e não deve ganhar, nenhum mecanismo de recolher. Se um dia
//     alguém quiser um `<details>` aqui, o motivo desta linha é: o dono pediu
//     explicitamente que ela fique fixa, e "fechou sozinha" já custou duas
//     rodadas de teste.
//
// O `key` do formulário muda quando a seção é salva com sucesso, e só então: é o
// que ressincroniza os campos "original" com o que o banco passou a ter, para o
// próximo salvamento não reenviar o que já foi gravado.

export interface LinhaDaSecao {
  chave: string;
  rotulo_norm: string;
  entidade: string | null;
  valor_ultimo: number;
  n_ocorrencias: number;
  papel: "conta" | "subtotal" | "derivado" | "serie_mensal";
  unidade: string | null;
  moeda: string | null;
  documentos: string[] | null;
  sobreposicao_suspeita: boolean;
}

export interface OpcaoPremissa {
  codigo: string;
  nome: string;
}

const PAPEL_INFO: Record<string, { rotulo: string; explica: string; cor: string }> = {
  subtotal: {
    rotulo: "subtotal",
    explica: "sai no Excel como a SOMA dos componentes projetados — se move sozinho, e por isso "
      + "não recebe premissa (projetá-lo contaria o mesmo dinheiro duas vezes)",
    cor: "bg-sky-100 text-sky-800",
  },
  serie_mensal: {
    rotulo: "série mensal",
    explica: "alimenta a curva de sazonalidade, derivada do próprio histórico do caso — não é uma "
      + "conta a projetar",
    cor: "bg-violet-100 text-violet-800",
  },
  derivado: {
    rotulo: "derivado",
    explica: "indicador gerencial (resultado de outras contas, não dinheiro) — projetá-lo o faria "
      + "divergir das linhas que o compõem",
    cor: "bg-neutral-200 text-neutral-700",
  },
};

const fmt = new Intl.NumberFormat("pt-BR", { maximumFractionDigits: 0 });

const escala = (l: LinhaDaSecao) =>
  [l.unidade === "milhar" ? "R$ mil" : l.unidade === "unidade" ? "R$" : l.unidade,
    l.moeda && l.moeda !== "BRL" ? l.moeda : null].filter(Boolean).join(" ");

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

export function SecaoLinhas({
  casoId, secao, rotulo, linhas, ativas, sazonais, vinculos,
}: {
  casoId: string;
  /** chave canônica — é o que vai ao banco */
  secao: string;
  /** o nome em português — é o que aparece na tela */
  rotulo: string;
  linhas: LinhaDaSecao[];
  ativas: OpcaoPremissa[];
  sazonais: OpcaoPremissa[];
  /** rotulo_norm → { premissa, sazonalidade } já gravados */
  vinculos: Record<string, { premissa: string; sazonalidade: string }>;
}) {
  const semSecao = secao === "(sem seção canônica)";
  const contas = linhas.filter((l) => l.papel === "conta");

  // O estado de edição desta seção. Nasce do que o banco trouxe e passa a mandar
  // dali em diante — é ele, e não o DOM, que sobrevive ao re-render.
  const inicial = () => Object.fromEntries(linhas.map((l) => [l.rotulo_norm, {
    premissa: vinculos[l.rotulo_norm]?.premissa ?? "",
    sazonalidade: vinculos[l.rotulo_norm]?.sazonalidade ?? "",
  }]));
  const [escolhas, setEscolhas] = useState<Record<string, { premissa: string; sazonalidade: string }>>(inicial);
  // O que o banco tinha quando esta seção foi carregada ou salva pela última vez.
  // É a base do "só manda o que mudou".
  const [gravado, setGravado] = useState<Record<string, { premissa: string; sazonalidade: string }>>(inicial);
  const [premissaDoLote, setPremissaDoLote] = useState("");

  const [rSalvar, actSalvar, salvando] = useActionState(
    async (prev: Resultado, fd: FormData) => {
      const r = await salvarSecao(casoId, prev, fd);
      if (r?.tom === "ok") setGravado(escolhas);
      return r;
    }, null as Resultado);

  const [rLote, actLote, aplicando] = useActionState(
    async (prev: Resultado, fd: FormData) => {
      const r = await aplicarEmLote(casoId, prev, fd);
      if (r?.tom === "ok") {
        // O lote é do BANCO: ele acabou de vincular todas as contas da seção.
        // A tela reflete isso na hora, sem esperar recarregar — e sem descartar
        // a sazonalidade que já estava escolhida linha a linha.
        const p = String(fd.get("premissa") ?? "");
        const novo = Object.fromEntries(linhas.map((l) => [l.rotulo_norm, {
          premissa: l.papel === "conta" ? p : (escolhas[l.rotulo_norm]?.premissa ?? ""),
          sazonalidade: escolhas[l.rotulo_norm]?.sazonalidade ?? "",
        }]));
        setEscolhas(novo);
        setGravado(novo);
      }
      return r;
    }, null as Resultado);

  const mudar = (rotulo: string, campo: "premissa" | "sazonalidade", valor: string) =>
    setEscolhas((e) => ({ ...e, [rotulo]: { ...e[rotulo], [campo]: valor } }));

  const pendentes = linhas.filter((l) =>
    escolhas[l.rotulo_norm]?.premissa !== gravado[l.rotulo_norm]?.premissa
    || escolhas[l.rotulo_norm]?.sazonalidade !== gravado[l.rotulo_norm]?.sazonalidade).length;

  return (
    <div>
      <div className="mb-1 flex flex-wrap items-center gap-2">
        <h3 className="text-xs font-semibold uppercase text-neutral-500">
          {rotulo}{" "}
          <span className="font-normal">
            ({contas.length} conta(s)
            {linhas.length !== contas.length && ` + ${linhas.length - contas.length} não projetável(is)`})
          </span>
        </h3>
        {!semSecao && contas.length > 0 && (
          <form action={actLote} className="flex items-center gap-1">
            <input type="hidden" name="secao_canonica" value={secao} />
            <select
              name="premissa" required value={premissaDoLote}
              onChange={(e) => setPremissaDoLote(e.target.value)}
              className="rounded border border-neutral-300 px-1 py-0.5 text-xs"
            >
              <option value="" disabled>aplicar em lote…</option>
              {ativas.map((a) => <option key={a.codigo} value={a.codigo}>{a.nome}</option>)}
            </select>
            <button
              type="submit" disabled={aplicando}
              className="rounded border border-neutral-300 px-2 py-0.5 text-xs hover:bg-neutral-100 disabled:opacity-50"
            >
              {aplicando ? "aplicando…" : `aplicar às ${contas.length} conta(s)`}
            </button>
            <Aviso r={rLote} />
          </form>
        )}
      </div>

      {/* UM formulário por seção: as exceções se ajustam e salvam de uma vez.
          Antes era um botão por linha — 236 idas ao servidor. */}
      <form action={actSalvar}>
        <input type="hidden" name="secao_canonica" value={semSecao ? "" : secao} />
        <div className="overflow-x-auto rounded border border-neutral-200">
          <table className="w-full text-left text-sm">
            <thead className="bg-neutral-50 text-xs uppercase text-neutral-500">
              <tr>
                <th className="px-2 py-1">Linha</th>
                <th className="px-2 py-1 text-right">Último real</th>
                <th className="px-2 py-1">Premissa que dirige</th>
                <th className="px-2 py-1">Sazonalidade</th>
              </tr>
            </thead>
            <tbody>
              {linhas.map((l, i) => {
                const info = PAPEL_INFO[l.papel];
                const e = escolhas[l.rotulo_norm] ?? { premissa: "", sazonalidade: "" };
                const g = gravado[l.rotulo_norm] ?? { premissa: "", sazonalidade: "" };
                const sujo = e.premissa !== g.premissa || e.sazonalidade !== g.sazonalidade;
                return (
                  <tr
                    key={l.rotulo_norm}
                    className={`border-t border-neutral-100 align-top ${sujo ? "bg-amber-50" : ""}`}
                  >
                    <td className="px-2 py-1">
                      <span className={l.papel === "conta" ? "" : "text-neutral-500"}>{l.chave}</span>
                      {info && (
                        <span className={`ml-1 rounded px-1 text-[10px] ${info.cor}`} title={info.explica}>
                          {info.rotulo}
                        </span>
                      )}
                      {l.sobreposicao_suspeita && (
                        <span
                          className="ml-1 rounded bg-amber-100 px-1 text-[10px] text-amber-800"
                          title="Outra linha desta seção tem o MESMO valor e um rótulo que descreve a mesma conta de forma mais grossa — provavelmente o balanço sintético e o balancete analítico. Projetar as duas dobra a conta: escolha uma."
                        >
                          possível sobreposição
                        </span>
                      )}
                      <span className="block text-[10px] text-neutral-400">
                        {(l.documentos ?? []).join(" · ")}
                        {l.n_ocorrencias > 1 && ` · ${l.n_ocorrencias} ocorrências`}
                      </span>
                    </td>
                    <td className="px-2 py-1 text-right tabular-nums text-neutral-600">
                      {fmt.format(l.valor_ultimo)}
                      <span className="block text-[10px] text-neutral-400">{escala(l)}</span>
                    </td>
                    {l.papel === "conta" ? (
                      <>
                        <td className="px-2 py-1">
                          <input type="hidden" name={`rotulo__${i}`} value={l.chave} />
                          <input type="hidden" name={`entidade__${i}`} value={l.entidade ?? ""} />
                          <input type="hidden" name={`orig__${i}`} value={g.premissa} />
                          <select
                            name={`premissa__${i}`} value={e.premissa}
                            onChange={(ev) => mudar(l.rotulo_norm, "premissa", ev.target.value)}
                            className="rounded border border-neutral-300 px-1 py-0.5 text-xs"
                          >
                            <option value="">(não projetar)</option>
                            {ativas.map((a) => <option key={a.codigo} value={a.codigo}>{a.nome}</option>)}
                          </select>
                        </td>
                        <td className="px-2 py-1">
                          <input type="hidden" name={`origSaz__${i}`} value={g.sazonalidade} />
                          <select
                            name={`sazonalidade__${i}`} value={e.sazonalidade}
                            onChange={(ev) => mudar(l.rotulo_norm, "sazonalidade", ev.target.value)}
                            className="rounded border border-neutral-300 px-1 py-0.5 text-xs"
                            disabled={sazonais.length === 0}
                          >
                            <option value="">(sem sazonalidade)</option>
                            {sazonais.map((a) => <option key={a.codigo} value={a.codigo}>{a.nome}</option>)}
                          </select>
                        </td>
                      </>
                    ) : (
                      // Sem seletor, com o DESTINO escrito: se a linha simplesmente
                      // não tivesse controle, o analista procuraria o defeito na tela.
                      <td colSpan={2} className="px-2 py-1 text-xs text-neutral-500">
                        {info?.explica}
                      </td>
                    )}
                  </tr>
                );
              })}
            </tbody>
          </table>
        </div>
        {contas.length > 0 && (
          <div className="mt-1 flex flex-wrap items-center gap-2">
            <button
              type="submit" disabled={salvando}
              className="rounded border border-neutral-300 px-2 py-0.5 text-xs hover:bg-neutral-100 disabled:opacity-50"
            >
              {salvando ? "salvando…" : "salvar esta seção"}
            </button>
            <span className="text-[10px] text-neutral-400">
              só as linhas que você mudou vão ao banco
            </span>
            {/* Alteração não salva é destacada na linha E contada aqui: sair da
                tela com escolha pendente é a maneira mais fácil de perder
                trabalho, e nada avisava. */}
            {pendentes > 0 && (
              <span className="rounded bg-amber-100 px-2 py-0.5 text-[10px] text-amber-900">
                {pendentes} alteração(ões) ainda NÃO salva(s) nesta seção
              </span>
            )}
            <Aviso r={rSalvar} />
          </div>
        )}
      </form>
    </div>
  );
}
