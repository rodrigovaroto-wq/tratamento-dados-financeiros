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
import { PainelIntro } from "@/components/painel-intro";
import { CeuOria } from "@/components/ceu-oria";
import { Surgir } from "@/components/surgir";

// O PAINEL — a primeira tela do dia.
//
// POR QUE ELA EXISTE (18/08). `/casos` era a LISTA de mandatos, e a barra
// lateral também. Abrir o portal dava a mesma resposta duas vezes, uma delas
// ocupando a tela inteira: *o que existe*. Só que ninguém abre um portal de
// conferência para saber o que existe — abre para saber **o que precisa de mim
// agora**, e essa pergunta não tinha tela nenhuma. As pendências viviam DENTRO
// de cada mandato, um por vez: com seis casos na mesa, descobrir onde estava a
// bloqueante custava seis cliques e a memória de quem clicou.
//
// A DIVISÃO DE TRABALHO, e ela é a regra desta tela: a barra lateral NAVEGA
// (criar mandato, pular de caso em caso) e o painel TRABALHA. Nenhuma função da
// barra se repete aqui — não há lista de mandatos, não há botão de criar.
//
// OS SETE INDICADORES foram escolhidos pelo dono, e a lista dele diz o que ele
// quer saber de manhã: quanto trabalho existe (mandatos ativos e fechados),
// quanto dado já foi arrancado dos PDFs (linhas), quanto tempo cada mandato
// leva, quanto custa, e o que está parado esperando alguém.
//
// DOIS DELES NÃO TÊM DE ONDE SAIR AINDA, e a tela DIZ ISSO em vez de inventar.
// O custo de API é calculado no n8n (`n8n/lib/custo.mjs`, nó `Resumo de Custo`)
// e vive só na saída da execução — nenhuma tabela do Postgres guarda um dólar.
// Mostrar zero seria mentira barata; mostrar "sem medição" com a causa escrita
// ao lado é o que permite alguém decidir se vale instrumentar. Ver o rodapé
// desta tela e o `ESTADO.md`.

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
  bloqueante: { ponto: "bg-red-500", chip: "bg-red-100 text-red-800", rotulo: "bloqueia a aprovação" },
  importante: { ponto: "bg-amber-500", chip: "bg-amber-100 text-amber-900", rotulo: "importante" },
  complementar: { ponto: "bg-tinta-300", chip: "bg-tinta-100 text-tinta-600", rotulo: "complementar" },
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
    new Intl.DateTimeFormat("en-CA", { year: "numeric", month: "2-digit", day: "2-digit", timeZone: FUSO }).format(d);
  const d = new Date(iso);
  if (Number.isNaN(d.getTime())) return "";
  const ontem = new Date(agora.getTime() - 86_400_000);
  if (dia(d) === dia(agora)) return "Hoje";
  if (dia(d) === dia(ontem)) return "Ontem";
  return d.toLocaleDateString("pt-BR", { day: "2-digit", month: "short", timeZone: FUSO });
}

/** Duração em palavras curtas: "8 min", "1 h 12", "2 d". */
function duracaoCurta(ms: number): string {
  const min = Math.round(ms / 60_000);
  if (min < 1) return "menos de 1 min";
  if (min < 90) return `${min} min`;
  const h = Math.floor(min / 60);
  if (h < 36) return `${h} h ${String(min % 60).padStart(2, "0")}`;
  return `${Math.round(h / 24)} d`;
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

/**
 * Um número do topo.
 *
 * `valor` é STRING e não número de propósito: metade destes indicadores não é
 * contagem — é dinheiro, duração, ou a ausência dos dois. Formatar aqui dentro
 * obrigaria o componente a saber de moeda e de fuso, e ele não precisa saber.
 * Quando não há medição, `valor` vem nulo e o indicador assume a cara de
 * "ainda não medimos" — que é informação, não buraco.
 */
function Indicador({
  valor, rotulo, detalhe, tom, nota,
}: {
  valor: string | null;
  rotulo: string;
  detalhe?: string | null;
  tom?: "neutro" | "alerta" | "bom";
  /** por que não há número — só aparece quando `valor` é nulo */
  nota?: string;
}) {
  const corDetalhe =
    tom === "alerta" ? "text-red-700" : tom === "bom" ? "text-emerald-700" : "text-tinta-500";
  return (
    <div className="bg-white px-4 py-4">
      {valor === null ? (
        <p className="text-2xl font-semibold text-tinta-300" title={nota}>
          —
        </p>
      ) : (
        <p className="indicador-valor">{valor}</p>
      )}
      <p className="indicador-rotulo">{rotulo}</p>
      <p className={`mt-1 min-h-4 text-xs font-medium ${valor === null ? "text-tinta-400" : corDetalhe}`}>
        {valor === null ? (nota ?? "") : (detalhe ?? "")}
      </p>
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
  const fechados = casos.filter((c) => c.fechado_em);
  const ids = casos.map((c) => c.id);
  const idsAtivos = ativos.map((c) => c.id);
  const nomePorCaso = new Map(casos.map((c) => [c.id, c.nome] as const));

  const [documentosRes, pendenciasRes] = ids.length
    ? await Promise.all([
        // TODOS os mandatos, não só os ativos: "linhas extraídas" e "tempo médio"
        // são números da OPERAÇÃO, e um mandato fechado com sucesso é justamente
        // o que se quer ter no denominador de uma média de tempo.
        supabase
          .from("documento")
          .select("id, caso_id, tipo_taxonomia, status, criado_em, documento_versao(id)")
          .in("caso_id", ids)
          .order("criado_em", { ascending: false }),
        // A FILA, ao contrário, é só dos ATIVOS: pendência de mandato fechado não
        // é trabalho de hoje, e listá-la encheria a tela de coisa que ninguém vai
        // fazer.
        idsAtivos.length
          ? supabase
              .from("pendencia")
              .select("id, caso_id, tipo, severidade, estado, descricao, documento_id, criada_em")
              .in("caso_id", idsAtivos)
              .in("estado", ESTADOS_EM_ABERTO)
          : Promise.resolve({ data: [] }),
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
  // faz, aqui somada sobre a operação inteira. Uma ida ao banco para todas as
  // versões, não uma por documento.
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

  // TEMPO MÉDIO DE PROCESSAMENTO — do intake ao último documento registrado.
  //
  // O QUE ESTE NÚMERO É, EXATAMENTE. `caso.criado_em` é gravado pelo primeiro nó
  // do workflow (`Upsert Caso`), no instante em que o formulário de intake é
  // enviado; cada documento ganha `criado_em` quando o pipeline o registra. A
  // distância entre os dois é, portanto, a duração real da ingestão do lote —
  // não uma estimativa.
  //
  // ONDE ELE MENTE, e a tela precisa dizer: acrescentar documentos depois (a
  // tela "adicionar") dispara uma SEGUNDA execução, e o intervalo passa a
  // incluir os dias em que o mandato ficou parado esperando o cliente. Por isso
  // a média é dos mandatos com UMA janela plausível — acima de 12 horas o número
  // deixou de medir processamento e passou a medir espera, e entra na contagem
  // de fora ("N fora da média"), em vez de inflar a média em silêncio.
  const TETO_JANELA_MS = 12 * 3_600_000;
  const ultimoDocPorCaso = new Map<string, number>();
  for (const d of documentos) {
    const t = new Date(d.criado_em).getTime();
    if (Number.isNaN(t)) continue;
    ultimoDocPorCaso.set(d.caso_id, Math.max(ultimoDocPorCaso.get(d.caso_id) ?? 0, t));
  }
  const janelas: number[] = [];
  let janelasLongas = 0;
  for (const c of casos) {
    const fim = ultimoDocPorCaso.get(c.id);
    const inicio = new Date(c.criado_em).getTime();
    if (!fim || Number.isNaN(inicio) || fim <= inicio) continue;
    const dur = fim - inicio;
    if (dur > TETO_JANELA_MS) janelasLongas += 1;
    else janelas.push(dur);
  }
  const tempoMedioMs = janelas.length
    ? janelas.reduce((s, v) => s + v, 0) / janelas.length
    : null;

  // GASTO COM API — SEM FONTE. O cálculo existe e é bom (`n8n/lib/custo.mjs`
  // conhece o preço por milhão de tokens dos dois modelos e mede a chamada de
  // verdade), mas o resultado morre na saída da execução do n8n: nenhuma tabela
  // do Postgres tem uma coluna de dólar. Enquanto isso for verdade, estes dois
  // indicadores dizem "sem medição" — e o rodapé diz o que falta para eles
  // acenderem.
  const gastoTotalUsd: number | null = null;
  const gastoMedioUsd: number | null = null;

  const dinheiro = (v: number) =>
    v.toLocaleString("pt-BR", { style: "currency", currency: "USD", minimumFractionDigits: 2 });

  const bloqueantes = pendencias.filter((p) => p.severidade === "bloqueante").length;
  const casosTravados = new Set(
    pendencias.filter((p) => p.severidade === "bloqueante").map((p) => p.caso_id),
  ).size;

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

  const numero = (n: number) => n.toLocaleString("pt-BR");

  return (
    <div className="relative space-y-6">
      {/* A abertura de ~3s, uma vez por sessão e interrompível por qualquer
          gesto — ver o cabeçalho do componente. */}
      <PainelIntro />

      {/* O MESMO SEXTANTE DA ABERTURA, agora a 8% de opacidade e ancorado no
          canto superior direito, onde não passa por baixo de número nenhum.
          `fixed` e não `absolute`: assim ele fica parado enquanto o conteúdo
          rola por cima, e o giro que a rolagem provoca fica visível. */}
      <CeuOria modo="fundo" className="pointer-events-none fixed inset-0 -z-10 h-full w-full" />

      <div className="flex flex-wrap items-end justify-between gap-3">
        <div>
          <h1 className="text-xl font-semibold text-tinta-900">{saudacao(agora)}</h1>
          <p className="mt-0.5 text-sm text-tinta-500">{resumo}</p>
        </div>
        <p className="text-xs capitalize text-tinta-400">{dataDeHoje}</p>
      </div>

      {casosRes.error && (
        <p className="rounded-lg border border-red-200 bg-red-50 p-3 text-sm text-red-800">
          Não foi possível carregar o painel: {casosRes.error.message}
        </p>
      )}

      {/* OS SETE INDICADORES, em duas fileiras de quatro. A oitava célula não é
          sobra: é onde mora a legenda das duas medições que ainda não existem,
          no lugar exato em que alguém vai procurar por elas. */}
      {/* A GRADE SEPARA COM `gap-px` SOBRE UM FUNDO CINZA, e não com `divide-x`.
          Com duas fileiras, o `divide-x` do Tailwind põe borda à esquerda de
          TODO filho menos o primeiro — inclusive o quinto, que é o primeiro da
          segunda fileira e não deveria ter nenhuma. O vão de 1px deixa a própria
          grade desenhar a malha, certa nas duas direções. */}
      <Surgir className="carta overflow-hidden">
        <div className="grid grid-cols-2 gap-px bg-tinta-100 sm:grid-cols-4">
          <Indicador
            valor={numero(ativos.length)}
            rotulo={ativos.length === 1 ? "mandato ativo" : "mandatos ativos"}
            detalhe={casosTravados > 0 ? `${casosTravados} travado${casosTravados === 1 ? "" : "s"}` : null}
            tom="alerta"
          />
          <Indicador
            valor={numero(fechados.length)}
            rotulo={fechados.length === 1 ? "mandato fechado" : "mandatos fechados"}
            detalhe={casos.length ? `${numero(casos.length)} no total` : null}
          />
          <Indicador
            valor={numero(totalLinhas)}
            rotulo={totalLinhas === 1 ? "linha extraída" : "linhas extraídas"}
            detalhe={documentos.length ? `de ${numero(documentos.length)} documentos` : null}
          />
          <Indicador
            valor={numero(pendencias.length)}
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

          <Indicador
            valor={tempoMedioMs === null ? null : duracaoCurta(tempoMedioMs)}
            rotulo="tempo médio de processamento"
            detalhe={
              janelas.length
                ? `${janelas.length} ${janelas.length === 1 ? "mandato medido" : "mandatos medidos"}` +
                  (janelasLongas ? ` · ${janelasLongas} fora da média` : "")
                : null
            }
            nota="nenhum mandato com documento registrado ainda"
          />
          <Indicador
            valor={gastoMedioUsd === null ? null : dinheiro(gastoMedioUsd)}
            rotulo="gasto médio de API por mandato"
            nota="sem medição — o custo não é gravado no banco"
          />
          <Indicador
            valor={gastoTotalUsd === null ? null : dinheiro(gastoTotalUsd)}
            rotulo="gasto total de API"
            nota="sem medição — o custo não é gravado no banco"
          />
          <div className="bg-white px-4 py-4 text-[11px] leading-relaxed text-tinta-400">
            O custo por chamada é calculado na ingestão e só aparece na execução
            do n8n. Para os dois indicadores acima acenderem, ele precisa ser
            gravado por mandato — hoje nenhuma tabela tem coluna de dólar.
          </div>
        </div>
      </Surgir>

      {ativos.length === 0 ? (
        /* SEM MANDATO, O PAINEL NÃO INVENTA CONTEÚDO — e também não repete o
           botão de criar, que mora no menu. Ele aponta para lá. */
        <Surgir atraso={120} className="carta flex flex-col items-center gap-2 px-6 py-14 text-center">
          <p className="text-sm font-medium text-tinta-900">A mesa está vazia</p>
          <p className="max-w-md text-sm text-tinta-500">
            Abra um mandato pelo <strong className="font-medium text-tinta-700">Novo mandato</strong>,
            no menu à esquerda. O sistema classifica cada documento, extrai as linhas financeiras e
            aponta aqui o que ficou faltando ou divergente.
          </p>
        </Surgir>
      ) : (
        <div className="grid gap-5 lg:grid-cols-3">
          {/* O QUE PRECISA DE VOCÊ. */}
          <Surgir atraso={120} className="lg:col-span-2">
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
                        <span aria-hidden className={`mt-1.5 h-2 w-2 shrink-0 rounded-full ${tom.ponto}`} />
                        <div className="min-w-0 flex-1">
                          <p className="flex flex-wrap items-baseline gap-x-2 text-sm">
                            <span className="font-semibold text-tinta-900">{rotuloDaPendencia(p.tipo)}</span>
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
          </Surgir>

          {/* O QUE CHEGOU. */}
          <Surgir atraso={220}>
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
                              <span className="shrink-0 text-[11px] font-medium tabular-nums text-tinta-500">
                                {numero(linhas)} {linhas === 1 ? "linha" : "linhas"}
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
                              <span className="block truncate text-xs font-medium text-tinta-900">{c.nome}</span>
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
          </Surgir>
        </div>
      )}
    </div>
  );
}
