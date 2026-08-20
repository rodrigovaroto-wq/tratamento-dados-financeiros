"use client";

import { useState } from "react";
import { rotularCampos, type Resultado } from "@/app/autonomia/golden/actions";

// OS VALORES — e as duas metades que fazem a medição valer.
//
// METADE 1: as rubricas que a extração achou, com o valor EM BRANCO. É onde a
// pessoa escreve o número que está no papel, sem ver o que a máquina leu.
//
// METADE 2: as linhas livres, e elas não são conveniência. Uma tela só com a
// primeira metade faria a extração parecer perfeita justamente nos documentos de
// que ela perdeu metade: quem rotula confirmaria as 40 linhas listadas e nunca
// notaria as 3 que faltam. `n_ausente` — a perda silenciosa, a família de defeito
// que custou três camadas de cobertura nesta casa — só chega a ser medida por
// aqui. Por isso a pergunta é feita com palavra, e não deixada implícita numa
// linha vazia no fim da tabela.
//
// A TOLERÂNCIA É POR LINHA porque escala é por documento: 1 unidade é
// arredondamento legítimo num balanço em milhares e é cegueira num em milhões. O
// default 0 é o conservador — exige valor exato, e quem souber que o documento
// arredonda afrouxa na linha.

type Linha = {
  chave: string;
  secao: string | null;
  periodo_coluna: string | null;
  entidade_coluna: string | null;
  origem_pagina: number | null;
  unidade: string | null;
  ja_rotulada: boolean;
};

const LIVRES = 8;

export function RotularCampos({
  rodadaId,
  docId,
  linhas,
  classes,
}: {
  rodadaId: string;
  docId: string;
  linhas: Linha[];
  classes: { codigo: string; nome: string }[];
}) {
  const [r, setR] = useState<Resultado | null>(null);
  const [enviando, setEnviando] = useState(false);

  const pendentes = linhas.filter((l) => !l.ja_rotulada);
  const gravados = (r?.ok ? (r.dado.gravados as Registro[] | undefined) : undefined) ?? [];
  const pulados = (r?.ok ? (r.dado.pulados as Pulado[] | undefined) : undefined) ?? [];

  return (
    <section className="rounded border border-tinta-200 bg-white p-4">
      <h2 className="text-sm font-semibold">2. Os valores</h2>
      <p className="mt-1 text-xs text-tinta-500">
        Escreva o valor que está no documento. Linha em branco é ignorada — não precisa preencher
        tudo de uma vez, e você pode voltar e acrescentar.
      </p>

      <form
        action={async (fd) => {
          setEnviando(true);
          setR(null);
          try {
            setR(await rotularCampos(rodadaId, docId, fd));
          } finally {
            setEnviando(false);
          }
        }}
      >
        <div className="mt-3 overflow-x-auto rounded border border-tinta-200">
          <table className="w-full text-sm">
            <thead className="bg-tinta-50 text-left text-xs uppercase text-tinta-500">
              <tr>
                <th className="px-3 py-2 font-medium">Rubrica</th>
                <th className="px-3 py-2 font-medium">Valor no documento</th>
                <th className="px-3 py-2 font-medium">Tolerância</th>
                <th className="px-3 py-2 font-medium">Classe contábil</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-tinta-100">
              {pendentes.map((l, i) => (
                <tr key={`${l.chave}-${i}`}>
                  <td className="px-3 py-1.5">
                    <input type="hidden" name={`chave_${i}`} value={l.chave} />
                    <input
                      type="hidden"
                      name={`periodo_${i}`}
                      value={l.periodo_coluna ?? ""}
                    />
                    <input
                      type="hidden"
                      name={`entidade_${i}`}
                      value={l.entidade_coluna ?? ""}
                    />
                    <span>{l.chave}</span>
                    <span className="ml-1 text-xs text-tinta-400">
                      {l.periodo_coluna ? `[${l.periodo_coluna}]` : ""}
                      {l.entidade_coluna ? ` (${l.entidade_coluna})` : ""}
                      {l.origem_pagina ? ` · p.${l.origem_pagina}` : ""}
                      {l.unidade ? ` · ${l.unidade}` : ""}
                    </span>
                  </td>
                  <td className="px-3 py-1.5">
                    <input
                      type="text"
                      name={`valor_${i}`}
                      inputMode="decimal"
                      placeholder="—"
                      className="w-32 rounded border border-tinta-300 bg-amber-50 px-2 py-1 text-right font-mono text-sm"
                    />
                  </td>
                  <td className="px-3 py-1.5">
                    <input
                      type="text"
                      name={`tolerancia_${i}`}
                      defaultValue="0"
                      className="w-16 rounded border border-tinta-300 px-1 py-1 text-right text-xs"
                    />
                  </td>
                  <td className="px-3 py-1.5">
                    <select
                      name={`classe_${i}`}
                      defaultValue=""
                      className="rounded border border-tinta-300 px-1 py-1 text-xs"
                    >
                      <option value="">—</option>
                      {classes.map((c) => (
                        <option key={c.codigo} value={c.codigo}>
                          {c.nome}
                        </option>
                      ))}
                    </select>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>

        {/* A PERGUNTA QUE FAZ A PERDA SILENCIOSA SER MEDIDA. Ver o cabeçalho. */}
        <div className="mt-4 rounded border border-amber-300 bg-amber-50 p-3">
          <p className="text-sm font-medium text-amber-900">
            O documento tem alguma linha que <em>não</em> está na lista acima?
          </p>
          <p className="mt-0.5 text-xs text-amber-800">
            Esta é a pergunta mais importante desta tela. A lista acima é o que a extração achou;
            o que ela perdeu só aparece se você escrever aqui. Sem isso, a extração parece
            perfeita exatamente nos documentos de que ela perdeu metade.
          </p>
          <div className="mt-2 overflow-x-auto">
            <table className="w-full text-sm">
              <tbody>
                {Array.from({ length: LIVRES }, (_, k) => {
                  const i = pendentes.length + k;
                  return (
                    <tr key={i}>
                      <td className="py-1 pr-2">
                        <input
                          type="text"
                          name={`chave_${i}`}
                          placeholder="rubrica, como está no documento"
                          className="w-72 rounded border border-amber-300 px-2 py-1 text-sm"
                        />
                      </td>
                      <td className="py-1 pr-2">
                        <input
                          type="text"
                          name={`valor_${i}`}
                          inputMode="decimal"
                          placeholder="valor"
                          className="w-32 rounded border border-amber-300 px-2 py-1 text-right font-mono text-sm"
                        />
                      </td>
                      <td className="py-1 pr-2">
                        <input
                          type="text"
                          name={`periodo_${i}`}
                          placeholder="período"
                          className="w-24 rounded border border-amber-300 px-2 py-1 text-xs"
                        />
                      </td>
                      <td className="py-1">
                        <input
                          type="text"
                          name={`tolerancia_${i}`}
                          defaultValue="0"
                          className="w-16 rounded border border-amber-300 px-1 py-1 text-right text-xs"
                        />
                      </td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
          </div>
        </div>

        <button
          type="submit"
          disabled={enviando}
          className="mt-3 rounded bg-tinta-900 px-3 py-1.5 text-sm font-medium text-white disabled:opacity-50"
        >
          {enviando ? "gravando…" : "Gravar valores"}
        </button>
      </form>

      {r && !r.ok && (
        <p className="mt-3 rounded border border-red-300 bg-red-50 px-3 py-2 text-sm text-red-800">
          {r.erro}
        </p>
      )}

      {/* A REVELAÇÃO, e ela aparece só AQUI — depois de gravar. Durante a digitação
          um aviso de "não casou" seria convite a procurar a grafia que casa, e o
          rótulo passaria a perseguir a máquina em vez de julgar o papel. */}
      {r?.ok && (
        <div className="mt-3 space-y-2">
          <p className="rounded border border-emerald-200 bg-emerald-50 px-3 py-2 text-sm text-emerald-800">
            ✓ {String(r.dado.n_gravados)} linha(s) gravada(s).
          </p>

          {typeof r.dado.aviso_sem_par === "string" && (
            <p className="rounded border border-amber-300 bg-amber-50 px-3 py-2 text-sm text-amber-900">
              {r.dado.aviso_sem_par}
            </p>
          )}

          {gravados.length > 0 && (
            <div className="overflow-x-auto rounded border border-tinta-200">
              <table className="w-full text-sm">
                <caption className="px-3 pt-2 text-left text-xs text-tinta-500">
                  Agora sim: onde o seu rótulo encontrou a extração. Isto aparece{" "}
                  <strong>depois</strong> de gravar de propósito — ver antes faria você procurar a
                  grafia que casa em vez de escrever a do papel.
                </caption>
                <tbody className="divide-y divide-tinta-100">
                  {gravados.map((g, i) => (
                    <tr key={i}>
                      <td className="px-3 py-1">{g.chave}</td>
                      <td className="px-3 py-1 text-right font-mono text-xs">
                        {String(g.valor_correto)}
                      </td>
                      <td className="px-3 py-1 text-xs">
                        {g.casou_com_a_extracao ? (
                          <span className="text-tinta-500">casou com a extração</span>
                        ) : (
                          <span className="text-amber-800">
                            sem par — conta como AUSENTE no placar
                          </span>
                        )}
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          )}

          {pulados.length > 0 && (
            <div className="rounded border border-tinta-200 bg-tinta-50 px-3 py-2 text-xs text-tinta-600">
              <p className="font-medium">Linhas que não entraram, e por quê:</p>
              <ul className="mt-1 list-disc pl-5">
                {pulados.map((p, i) => (
                  <li key={i}>
                    <span className="font-medium">{p.chave ?? "(sem rubrica)"}</span> — {p.porque}
                  </li>
                ))}
              </ul>
            </div>
          )}

          <p className="text-xs text-tinta-500">
            Recarregue a página para as linhas já rotuladas saírem da tabela.
          </p>
        </div>
      )}
    </section>
  );
}

type Registro = {
  chave: string;
  valor_correto: number | string;
  casou_com_a_extracao: boolean;
};
type Pulado = { chave: string | null; porque: string };
