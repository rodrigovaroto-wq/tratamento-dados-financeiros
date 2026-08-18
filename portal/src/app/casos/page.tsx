import Link from "next/link";
import { createClient } from "@/lib/supabase/server";
import {
  PENDENCIA_TIPOS_DIAGNOSTICO_REVISAVEIS,
  type Caso,
  type Pendencia,
} from "@/lib/types";
import { CASO_STATUS_LABEL, CASO_STATUS_COLOR } from "@/lib/status";
import { rotuloDaPendencia, partesDaDescricao, suavizarMensagem } from "@/lib/rotulos";
import { formatarTipoTaxonomia } from "@/lib/export";

// O PAINEL — a primeira tela do dia.
//
// POR QUE ELA EXISTE (18/08). `/casos` era a LISTA de mandatos, e a barra
// lateral também. Abrir o portal dava a mesma resposta duas vezes, uma dela
// ocupando a tela inteira: *o que existe*. Só que ninguém abre um portal de
// conferência para saber o que existe — abre para saber **o que precisa de mim
// agora**, e essa pergunta não tinha tela nenhuma. As pendências viviam DENTRO
// de cada mandato, um por vez: com seis casos na mesa, descobrir onde estava a
// bloqueante custava seis cliques e a memória de quem clicou.
//
// A DIVISÃO DE TRABALHO, e ela é a regra desta tela: a barra lateral NAVEGA
// (criar mandato, pular de caso em caso) e o painel TRABALHA. Nenhuma função da
// barra se repete aqui — não há lista de mandatos, não há botão de criar. O que
// há são problemas, e cada um leva direto ao lugar onde se resolve.
//
// OS TRÊS BLOCOS RESPONDEM TRÊS PERGUNTAS, nesta ordem:
//
//   1. os indicadores — de que tamanho é a mesa hoje (e quanto dela está travado);
//   2. "Precisa de você" — a fila de pendências ATRAVESSANDO os mandatos,
//      ordenada por severidade: o que trava vem antes do que incomoda;
//   3. "O que chegou" — os documentos recentes, com quantas linhas cada um
//      rendeu. Documento classificado com ZERO linha é o modo de falha mais caro
//      deste sistema (19 de 35 numa rodada real, sem ninguém reclamar), e aqui
//      ele aparece em vermelho no dia em que acontece, não no export de sexta.

export const dynamic = "force-dynamic";

/** Estados de `pendencia` que ainda pedem alguém — os decididos saem da fila. */
const ESTADOS_EM_ABERTO = ["aberta", "em_correcao_interna", "reenviada_ao_cliente"];

// A ORDEM DA FILA NÃO É CRONOLÓGICA, é de consequência: bloqueante impede a
// aprovação do mandato, complementar não impede nada. Uma fila por data põe o
// aviso de ontem na frente do bloqueio de hoje.
const PESO_SEVERIDADE: Record<string, number> = {
  bloqueante: 0,
  importante: 1,
  complementar: 2,
};

const TOM_SEVERIDADE: Record<string, { ponto: string; chip: string; rotulo: string }> = {
  bloqueante: {
    ponto: "bg-red-500",
    chip: "bg-red-100 text-red-800",
    rotulo: "bloqueia a aprovação",
  },
  importante: {
    ponto: "bg-amber-500",
    chip: "bg-amber-100 text-amber-900",
    rotulo: "importante",
  },
  complementar: {
    ponto: "bg-tinta-300",
    chip: "bg-tinta-100 text-tinta-600",
    rotulo: "complementar",
  },
};

const REVISAVEIS = new Set<string>(PENDENCIA_TIPOS_DIAGNOSTICO_REVISAVEIS);

const FUSO = "America/Sao_Paulo";

/**
 * A saudação é calculada no FUSO DE QUEM USA, não no do servidor.
 *
 * O portal roda em UTC; sem isto, "Boa noite" apareceria às 21h de Brasília em
 * um dia e às 18h no outro, dependendo do horário de verão do servidor. É um
 * detalhe pequeno que, errado, faz a tela inteira parecer descuidada.
 */
function saudacao(agora: Date): string {
  const hora = Number(
    new Intl.DateTimeFormat("pt-BR", { hour: "2-digit", hour12: false, timeZone: FUSO }).format(agora),
  );
  if (hora < 12) return "Bom dia";
  if (hora < 18) return "Boa tarde";
  return "Boa noite";
}

function horaCurta(iso: string): string {
  const d = new Date(iso);
  if (Number.isNaN(d.getTime())) return "";
  return d.toLocaleTimeString("pt-BR", { hour: "2-digit", minute: "2-digit", timeZone: FUSO });
}

/** "Hoje", "Ontem" ou a data — o cabeçalho de cada bloco da linha do tempo. */
function diaRelativo(iso: string, agora: Date): string {
  const dia = (d: Date) =>
    new Intl.DateTimeFormat("en-CA", {
      year: "numeric", month: "2-digit", day: "2-digit", timeZone: FUSO,
    }).format(d);
  const d = new Date(iso);
  if (Number.isNaN(d.getTime())) return "";
  const ontem = new Date(agora.getTime() - 86_400_000);
  if (dia(d) === dia(agora)) return "Hoje";
  if (dia(d) === dia(ontem)) return "Ontem";
  return d.toLocaleDateString("pt-BR", { day: "2-digit", month: "short", timeZone: FUSO });
}

/**
 * A descrição de pendência em UMA linha.
 *
 * As mensagens vêm do banco com vários fatos emendados por `;` — na tela do
 * mandato elas viram lista, porque lá há espaço para conferir. Aqui a fila é de
 * TRIAGEM: o que ela precisa entregar é o primeiro fato, o suficiente para
 * decidir se vale abrir. O resto está a um clique.
 */
function resumoDaPendencia(descricao: string | null): string {
  if (!descricao) return "";
  const [primeira] = partesDaDescricao(suavizarMensagem(descricao));
  return (primeira ?? "").trim();
}

/** Um número do topo. Grande, com o rótulo embaixo e o detalhe só quando muda a leitura. */
function Indicador({
  valor, rotulo, detalhe, tom,
}: {
  valor: number;
  rotulo: string;
  detalhe?: string | null;
  tom?: "neutro" | "alerta" | "bom";
}) {
  const corDetalhe =
    tom === "alerta" ? "text-red-700" : tom === "bom" ? "text-emerald-700" : "text-tinta-500";
  return (
    <div className="px-5 py-4">
      <p className="indicador-valor">{valor.toLocaleString("pt-BR")}</p>
      <p className="indicador-rotulo">{rotulo}</p>
      <p className={`mt-1 h-4 text-xs font-medium ${corDetalhe}`}>{detalhe ?? ""}</p>
    </div>
  );
}

export default async function PainelPage() {
  const supabase = await createClient();
  const agora = new Date();

  // `fechado_em` é filtrado em JAVASCRIPT, não no `where`, pelo mesmo motivo da
  // lista completa: em um banco sem a 0114 aplicada a coluna não existe, e um
  // `.is("fechado_em", null)` derrubaria a tela inteira em vez de degradar.
  const casosRes = await supabase
    .from("caso")
    .select("id, nome, status, criado_em, fechado_em")
    .order("criado_em", { ascending: false });

  const casos = (casosRes.data as Caso[] | null) ?? [];
  const ativos = casos.filter((c) => !c.fechado_em);
  const ids = ativos.map((c) => c.id);
  const nomePorCaso = new Map(ativos.map((c) => [c.id, c.nome] as const));

  const [documentosRes, pendenciasRes] = ids.length
    ? await Promise.all([
        supabase
          .from("documento")
          .select("id, caso_id, tipo_taxonomia, status, criado_em, documento_versao(id)")
          .in("caso_id", ids)
          .order("criado_em", { ascending: false }),
        supabase
          .from("pendencia")
          .select("id, caso_id, tipo, severidade, estado, descricao, documento_id, criada_em")
          .in("caso_id", ids)
          .in("estado", ESTADOS_EM_ABERTO),
      ])
    : [{ data: [] }, { data: [] }];

  type DocumentoNoPainel = {
    id: string;
    caso_id: string;
    tipo_taxonomia: string | null;
    status: string;
    criado_em: string;
    documento_versao: Array<{ id: string }> | null;
  };
  const documentos = (documentosRes.data as unknown as DocumentoNoPainel[] | null) ?? [];
  const pendencias = (pendenciasRes.data as Pendencia[] | null) ?? [];

  // QUANTAS LINHAS CADA DOCUMENTO RENDEU — a mesma conta que a tela do mandato
  // faz, aqui somada sobre a mesa inteira. Uma ida ao banco para todas as
  // versões, não uma por documento: com seis mandatos abertos isso seria uma
  // consulta por linha da lista de atividade.
  const versoes = documentos.flatMap((d) => (d.documento_versao ?? []).map((v) => v.id)).filter(Boolean);
  const linhasRes = versoes.length
    ? await supabase.from("campo_extraido").select("documento_versao_id").in("documento_versao_id", versoes)
    : { data: [] as Array<{ documento_versao_id: string }> };
  const linhasPorVersao = new Map<string, number>();
  for (const l of (linhasRes.data as Array<{ documento_versao_id: string }> | null) ?? []) {
    linhasPorVersao.set(l.documento_versao_id, (linhasPorVersao.get(l.documento_versao_id) ?? 0) + 1);
  }
  const linhasDoDocumento = (d: DocumentoNoPainel) =>
    (d.documento_versao ?? []).reduce((s, v) => s + (linhasPorVersao.get(v.id) ?? 0), 0);
  const totalLinhas = documentos.reduce((s, d) => s + linhasDoDocumento(d), 0);

  const bloqueantes = pendencias.filter((p) => p.severidade === "bloqueante").length;
  const casosTravados = new Set(
    pendencias.filter((p) => p.severidade === "bloqueante").map((p) => p.caso_id),
  ).size;
  const semLinha = documentos.filter((d) => linhasDoDocumento(d) === 0).length;

  const fila = [...pendencias]
    .sort(
      (a, b) =>
        (PESO_SEVERIDADE[a.severidade] ?? 9) - (PESO_SEVERIDADE[b.severidade] ?? 9) ||
        new Date(b.criada_em).getTime() - new Date(a.criada_em).getTime(),
    )
    .slice(0, 12);

  const recentes = documentos.slice(0, 10);

  // A LINHA DO TEMPO É AGRUPADA POR DIA, e o cabeçalho do grupo é escrito uma
  // vez só — repetir "Hoje" em dez linhas é ruído que empurra o conteúdo para
  // baixo.
  const grupos: Array<{ dia: string; itens: DocumentoNoPainel[] }> = [];
  for (const d of recentes) {
    const dia = diaRelativo(d.criado_em, agora);
    const ultimo = grupos[grupos.length - 1];
    if (ultimo && ultimo.dia === dia) ultimo.itens.push(d);
    else grupos.push({ dia, itens: [d] });
  }

  const dataDeHoje = agora.toLocaleDateString("pt-BR", {
    weekday: "long", day: "2-digit", month: "long", timeZone: FUSO,
  });

  // A FRASE DE ABERTURA DIZ O VEREDITO, para quem não vai ler número nenhum.
  const resumo =
    ativos.length === 0
      ? "Nenhum mandato na mesa."
      : bloqueantes === 0
        ? `${ativos.length} ${ativos.length === 1 ? "mandato" : "mandatos"} na mesa, e nada trava a aprovação.`
        : `${bloqueantes} ${bloqueantes === 1 ? "pendência bloqueia" : "pendências bloqueiam"} ` +
          `${casosTravados === 1 ? "1 mandato" : `${casosTravados} mandatos`}.`;

  return (
    <div className="space-y-6">
      <div className="flex flex-wrap items-end justify-between gap-3">
        <div>
          <h1 className="text-xl font-semibold text-tinta-900">
            {saudacao(agora)}
          </h1>
          <p className="mt-0.5 text-sm text-tinta-500">{resumo}</p>
        </div>
        <p className="text-xs capitalize text-tinta-400">{dataDeHoje}</p>
      </div>

      {casosRes.error && (
        <p className="rounded-lg border border-red-200 bg-red-50 p-3 text-sm text-red-800">
          Não foi possível carregar o painel: {casosRes.error.message}
        </p>
      )}

      {/* 1. DE QUE TAMANHO É A MESA. Quatro números e nada mais: cada indicador
             a mais aqui rouba atenção da fila, que é o que a tela existe para
             mostrar. */}
      <div className="carta grid grid-cols-2 divide-tinta-200 sm:grid-cols-4 sm:divide-x">
        <Indicador
          valor={ativos.length}
          rotulo={ativos.length === 1 ? "mandato na mesa" : "mandatos na mesa"}
          detalhe={casosTravados > 0 ? `${casosTravados} travado${casosTravados === 1 ? "" : "s"}` : null}
          tom="alerta"
        />
        <Indicador
          valor={documentos.length}
          rotulo={documentos.length === 1 ? "documento recebido" : "documentos recebidos"}
          detalhe={semLinha > 0 ? `${semLinha} sem nenhuma linha` : null}
          tom="alerta"
        />
        <Indicador
          valor={totalLinhas}
          rotulo={totalLinhas === 1 ? "linha extraída" : "linhas extraídas"}
        />
        <Indicador
          valor={pendencias.length}
          rotulo={pendencias.length === 1 ? "pendência em aberto" : "pendências em aberto"}
          detalhe={
            bloqueantes > 0
              ? `${bloqueantes} ${bloqueantes === 1 ? "bloqueia" : "bloqueiam"}`
              : pendencias.length > 0
                ? "nenhuma bloqueia"
                : null
          }
          tom={bloqueantes > 0 ? "alerta" : "bom"}
        />
      </div>

      {ativos.length === 0 ? (
        /* SEM MANDATO, O PAINEL NÃO INVENTA CONTEÚDO — e também não repete o
           botão de criar, que mora no menu. Ele aponta para lá. */
        <div className="carta flex flex-col items-center gap-2 px-6 py-14 text-center">
          <p className="text-sm font-medium text-tinta-900">A mesa está vazia</p>
          <p className="max-w-md text-sm text-tinta-500">
            Abra um mandato pelo <strong className="font-medium text-tinta-700">Novo mandato</strong>,
            no menu à esquerda. O sistema classifica cada documento, extrai as linhas financeiras e
            aponta aqui o que ficou faltando ou divergente.
          </p>
        </div>
      ) : (
        <div className="grid gap-5 lg:grid-cols-3">
          {/* 2. O QUE PRECISA DE VOCÊ. */}
          <section className="lg:col-span-2">
            <div className="mb-2 flex items-baseline justify-between gap-3">
              <h2 className="titulo-secao">Precisa de você</h2>
              <p className="text-xs text-tinta-500">
                {pendencias.length === 0
                  ? "nada em aberto"
                  : `${fila.length} de ${pendencias.length}, o que trava primeiro`}
              </p>
            </div>

            {pendencias.length === 0 ? (
              <div className="rounded-lg border border-emerald-200 bg-emerald-50 px-5 py-10 text-center">
                <p className="text-sm font-medium text-emerald-900">Nenhuma pendência em aberto</p>
                <p className="mt-1 text-sm text-emerald-800">
                  Todo documento recebido foi conferido, e nenhum mandato está travado.
                </p>
              </div>
            ) : (
              <ul className="carta divide-y divide-tinta-100 overflow-hidden">
                {fila.map((p) => {
                  const tom = TOM_SEVERIDADE[p.severidade] ?? TOM_SEVERIDADE.complementar;
                  const destino = REVISAVEIS.has(p.tipo)
                    ? `/casos/${p.caso_id}/revisao`
                    : `/casos/${p.caso_id}`;
                  const resumoTexto = resumoDaPendencia(p.descricao);
                  return (
                    <li key={p.id}>
                      <Link
                        href={destino}
                        className="flex items-start gap-3 px-4 py-3 transition-colors hover:bg-tinta-50"
                      >
                        {/* O PONTO REPETE A SEVERIDADE QUE O CHIP JÁ DIZ EM
                            PALAVRA: cor sozinha nunca carrega significado nesta
                            tela — 8% dos homens que abrem este portal não
                            distinguem vermelho de âmbar. */}
                        <span
                          aria-hidden
                          className={`mt-1.5 h-2 w-2 shrink-0 rounded-full ${tom.ponto}`}
                        />
                        <div className="min-w-0 flex-1">
                          <p className="flex flex-wrap items-baseline gap-x-2 text-sm">
                            <span className="font-semibold text-tinta-900">
                              {rotuloDaPendencia(p.tipo)}
                            </span>
                            <span className="truncate text-xs text-tinta-500">
                              {nomePorCaso.get(p.caso_id) ?? "mandato"}
                            </span>
                          </p>
                          {resumoTexto && (
                            <p className="mt-0.5 line-clamp-2 text-xs text-tinta-600">{resumoTexto}</p>
                          )}
                        </div>
                        <span className={`chip shrink-0 ${tom.chip}`}>{tom.rotulo}</span>
                      </Link>
                    </li>
                  );
                })}
                {pendencias.length > fila.length && (
                  <li className="bg-tinta-50/60 px-4 py-2 text-[11px] text-tinta-500">
                    Mais {pendencias.length - fila.length}{" "}
                    {pendencias.length - fila.length === 1 ? "pendência" : "pendências"} em aberto —
                    abra o mandato para ver a lista completa dele.
                  </li>
                )}
              </ul>
            )}
          </section>

          {/* 3. O QUE CHEGOU. */}
          <section>
            <div className="mb-2 flex items-baseline justify-between gap-3">
              <h2 className="titulo-secao">O que chegou</h2>
              <p className="text-xs text-tinta-500">últimos {recentes.length}</p>
            </div>

            {recentes.length === 0 ? (
              <div className="carta px-4 py-10 text-center text-sm text-tinta-500">
                Nenhum documento recebido ainda.
              </div>
            ) : (
              <div className="carta overflow-hidden">
                {grupos.map((g) => (
                  <div key={g.dia}>
                    <p className="border-b border-tinta-100 bg-tinta-50/60 px-4 py-1.5 text-[11px] font-semibold uppercase tracking-wide text-tinta-400">
                      {g.dia}
                    </p>
                    <ul className="divide-y divide-tinta-100">
                      {g.itens.map((d) => {
                        const linhas = linhasDoDocumento(d);
                        return (
                          <li key={d.id}>
                            <Link
                              href={`/casos/${d.caso_id}/documentos/${d.id}`}
                              className="flex items-start gap-3 px-4 py-2.5 transition-colors hover:bg-tinta-50"
                            >
                              <span className="mt-0.5 shrink-0 text-[11px] tabular-nums text-tinta-400">
                                {horaCurta(d.criado_em)}
                              </span>
                              <span className="min-w-0 flex-1">
                                <span className="block truncate text-xs font-medium text-tinta-900">
                                  {d.tipo_taxonomia
                                    ? formatarTipoTaxonomia(d.tipo_taxonomia)
                                    : "documento não classificado"}
                                </span>
                                <span className="block truncate text-[11px] text-tinta-500">
                                  {nomePorCaso.get(d.caso_id) ?? "mandato"}
                                </span>
                              </span>
                              {/* ZERO LINHA É O ACHADO, não um detalhe: um
                                  documento que chegou, foi classificado e não
                                  trouxe dado nenhum passa por "recebido" em
                                  toda tela que só conta documentos. */}
                              <span
                                className={`shrink-0 text-[11px] font-medium tabular-nums ${
                                  linhas === 0 ? "text-red-700" : "text-tinta-500"
                                }`}
                              >
                                {linhas === 0 ? "0 linhas" : `${linhas.toLocaleString("pt-BR")} linhas`}
                              </span>
                            </Link>
                          </li>
                        );
                      })}
                    </ul>
                  </div>
                ))}
              </div>
            )}

            {/* O ESTADO DOS MANDATOS TRAVADOS, em uma linha cada — é a leitura
                que a fila acima não dá: qual caso está parado, e em que etapa
                ele parou. Não é a lista de mandatos (essa é da barra): só
                aparece quem tem bloqueante. */}
            {casosTravados > 0 && (
              <div className="mt-5">
                <h2 className="titulo-secao mb-2">Travados agora</h2>
                <ul className="carta divide-y divide-tinta-100 overflow-hidden">
                  {ativos
                    .filter((c) => pendencias.some((p) => p.caso_id === c.id && p.severidade === "bloqueante"))
                    .map((c) => {
                      const quantas = pendencias.filter(
                        (p) => p.caso_id === c.id && p.severidade === "bloqueante",
                      ).length;
                      return (
                        <li key={c.id}>
                          <Link
                            href={`/casos/${c.id}`}
                            className="flex items-center justify-between gap-3 px-4 py-2.5 transition-colors hover:bg-tinta-50"
                          >
                            <span className="min-w-0">
                              <span className="block truncate text-xs font-medium text-tinta-900">
                                {c.nome}
                              </span>
                              <span className="block text-[11px] text-red-700">
                                {quantas} {quantas === 1 ? "bloqueante" : "bloqueantes"}
                              </span>
                            </span>
                            <span className={`chip shrink-0 ${CASO_STATUS_COLOR[c.status]}`}>
                              {CASO_STATUS_LABEL[c.status]}
                            </span>
                          </Link>
                        </li>
                      );
                    })}
                </ul>
              </div>
            )}
          </section>
        </div>
      )}
    </div>
  );
}
