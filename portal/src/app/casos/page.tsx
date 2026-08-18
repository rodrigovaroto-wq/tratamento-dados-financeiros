import Link from "next/link";
import { createClient } from "@/lib/supabase/server";
import { paginar } from "@/lib/supabase/paginar";
import {
  PENDENCIA_TIPOS_DIAGNOSTICO_REVISAVEIS,
  type Caso,
  type Pendencia,
} from "@/lib/types";
import { CASO_STATUS_LABEL, CASO_STATUS_COLOR } from "@/lib/status";
import { rotuloDaPendencia, nomeDaChecagem, partesDaDescricao, suavizarMensagem } from "@/lib/rotulos";
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
// O OITAVO É A COBERTURA, e ele é o único que responde "o número acima é bom?".
// "1.139 linhas extraídas" parece ótimo até alguém dizer que os documentos
// tinham 2.893 — que foi exatamente a rodada em que 39% do dado chegou com o
// checklist verde. Ele fecha a fileira porque uma fração ao lado de totais é o
// que impede um total grande de passar por bom resultado.
//
// O CUSTO PASSOU A TER DE ONDE SAIR (0115). Ele sempre foi calculado no n8n
// (`n8n/lib/custo.mjs`, nó `Resumo de Custo`), mas morria na saída da execução:
// nenhuma tabela guardava um dólar. Agora o nó `Gravar Uso do Lote` grava uma
// linha por execução em `lote_execucao`, e os dois indicadores de dinheiro — e
// a COBERTURA — são somas dessa tabela.
//
// A TELA CONTINUA SABENDO DIZER "NÃO SEI". Se a `0115` não estiver aplicada no
// banco, a consulta falha e os três indicadores mostram um traço com a causa,
// em vez de zero. Zero e "não medido" são frases diferentes, e num número de
// dinheiro a diferença é a que importa.

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
  valor, rotulo, detalhe, tom, nota, barra,
}: {
  valor: string | null;
  rotulo: string;
  detalhe?: string | null;
  tom?: "neutro" | "alerta" | "bom";
  /** por que não há número — só aparece quando `valor` é nulo */
  nota?: string;
  /** 0..1 — desenha a fração embaixo do número. Só onde a fração É o número. */
  barra?: number | null;
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
      {/* A BARRA SÓ EXISTE ONDE A FRAÇÃO É O NÚMERO — hoje, a cobertura. Uma
          barra ao lado de um total (linhas, dólares) sugeriria um limite que
          não existe, e barra que insinua meta é pior que barra nenhuma. */}
      {typeof barra === "number" && (
        <div className="mt-2 h-1 w-full overflow-hidden rounded-full bg-tinta-100">
          <div
            className={`h-full rounded-full ${barra >= 0.9 ? "bg-emerald-600" : barra >= 0.6 ? "bg-amber-500" : "bg-red-500"}`}
            style={{ width: `${Math.min(100, Math.max(2, barra * 100))}%` }}
          />
        </div>
      )}
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
  const casosRes = await paginar<Caso>((de, ate) =>
    supabase
      .from("caso")
      .select("id, nome, status, criado_em, fechado_em")
      .order("criado_em", { ascending: false })
      .range(de, ate),
  );

  const casos = casosRes.data;
  const ativos = casos.filter((c) => !c.fechado_em);
  const fechados = casos.filter((c) => c.fechado_em);
  const ids = casos.map((c) => c.id);
  const idsAtivos = ativos.map((c) => c.id);
  const nomePorCaso = new Map(casos.map((c) => [c.id, c.nome] as const));

  // AS DUAS LISTAS SÃO PAGINADAS, e não é otimização: é correção.
  //
  // Elas alimentam cálculo por LINHA — o tempo médio por mandato e a fila de
  // pendências —, então não dá para trocá-las por um `count` como se fez com o
  // total de linhas extraídas. E o teto do PostgREST (`db-max-rows`, 1000 no
  // Supabase por padrão) corta em SILÊNCIO: no dia em que a mesa passar de mil
  // documentos, o tempo médio passaria a ser o dos mil mais recentes e a tela
  // não teria como dizer isso. Hoje são 475 documentos e 541 pendências — o
  // conserto entra ANTES de o número doer, porque depois ele não dói: ele
  // mente. `paginar` lê de mil em mil até a página vir incompleta.
  const [documentosRes, pendenciasRes] = ids.length
    ? await Promise.all([
        // TODOS os mandatos, não só os ativos: "linhas extraídas" e "tempo médio"
        // são números da OPERAÇÃO, e um mandato fechado com sucesso é justamente
        // o que se quer ter no denominador de uma média de tempo.
        paginar<DocumentoNoPainel>((de, ate) =>
          supabase
            .from("documento")
            .select("id, caso_id, tipo_taxonomia, status, criado_em, documento_versao(id)")
            .in("caso_id", ids)
            .order("criado_em", { ascending: false })
            .range(de, ate),
        ),
        // A FILA, ao contrário, é só dos ATIVOS: pendência de mandato fechado não
        // é trabalho de hoje, e listá-la encheria a tela de coisa que ninguém vai
        // fazer.
        idsAtivos.length
          ? paginar<Pendencia>((de, ate) =>
              supabase
                .from("pendencia")
                .select("id, caso_id, tipo, severidade, estado, descricao, documento_id, criada_em, motivo")
                .in("caso_id", idsAtivos)
                .in("estado", ESTADOS_EM_ABERTO)
                .order("criada_em", { ascending: false })
                .range(de, ate),
            )
          : Promise.resolve({ data: [] as Pendencia[], error: null, truncado: false }),
      ])
    : [
        { data: [] as DocumentoNoPainel[], error: null, truncado: false },
        { data: [] as Pendencia[], error: null, truncado: false },
      ];

  // O USO DE IA POR EXECUÇÃO (0115). Consulta à parte e TOLERANTE A FALHA: num
  // banco sem a migration aplicada a tabela não existe, e o painel inteiro não
  // pode cair por causa de três indicadores. `error` aqui vira "sem medição",
  // não uma tela vermelha.
  const usoRes = ids.length
    ? await supabase
        .from("lote_execucao")
        .select("caso_id, custo_total_usd, contas_nos_documentos, contas_extraidas")
        .in("caso_id", ids)
    : { data: [], error: null };

  type UsoDoLote = {
    caso_id: string;
    custo_total_usd: number | string | null;
    contas_nos_documentos: number | null;
    contas_extraidas: number | null;
  };

  type DocumentoNoPainel = {
    id: string;
    caso_id: string;
    tipo_taxonomia: string | null;
    status: string;
    criado_em: string;
    documento_versao: Array<{ id: string }> | null;
  };
  const documentos = documentosRes.data;
  const pendencias = pendenciasRes.data;

  // O TOTAL DE LINHAS É UM COUNT, NÃO A SOMA DE LINHAS BAIXADAS.
  //
  // O DEFEITO QUE ISTO CORRIGE, e ele já apareceu em produção: a versão
  // anterior buscava CADA linha de `campo_extraido` (`.select(...)` sem
  // paginação) e somava no JavaScript. O PostgREST do Supabase devolve no
  // máximo `db-max-rows` por consulta — **1000**, por padrão — e acima disso
  // corta em silêncio, sem erro. Com 475 documentos de dado financeiro real, o
  // total verdadeiro passa longe de 1000, e a tela mostrava exatamente
  // "1.000 linhas extraídas": não era o dado, era o TETO.
  //
  // A CORREÇÃO É PEDIR UM COUNT, NÃO LINHAS. `count: "exact", head: true` faz o
  // Postgres calcular `COUNT(*)` e devolver só o número — sem corpo de linhas,
  // não há o que paginar, e o teto não se aplica. O FILTRO é pelo CASO, via o
  // relacionamento embutido (`documento_versao!inner(documento!inner(caso_id))`),
  // e não pela lista de versões já carregada em `documentos`: assim o total
  // continua CORRETO mesmo se um dia a lista de documentos também passar de
  // 1000 — as duas consultas deixam de compartilhar o mesmo teto.
  const totalLinhasRes = ids.length
    ? await supabase
        .from("campo_extraido")
        .select("id, documento_versao!inner(documento!inner(caso_id))", { count: "exact", head: true })
        .in("documento_versao.documento.caso_id", ids)
    : { count: 0 };
  const totalLinhas = totalLinhasRes.count ?? 0;

  // MESMO TETO, MESMA CORREÇÃO: quantos documentos existem é outro COUNT, não
  // o tamanho do array que a lista de "O que chegou" já baixou (esse array
  // POR SI está sujeito ao mesmo `db-max-rows` — hoje 475 documentos, folgado,
  // mas o dia em que passar de 1000 esta consulta continua certa mesmo que a
  // lista abaixo pare de crescer).
  const totalDocumentosRes = ids.length
    ? await supabase.from("documento").select("id", { count: "exact", head: true }).in("caso_id", ids)
    : { count: 0 };
  const totalDocumentos = totalDocumentosRes.count ?? 0;

  // A CONTAGEM POR DOCUMENTO só serve para os 10 itens visíveis em "O que
  // chegou" — não para o total (que já saiu acima). Por isso a consulta é
  // pequena e ESCOPADA aos 10 mais recentes, em vez de baixar linhas de TODOS
  // os documentos só para exibir dez.
  const recentes = documentos.slice(0, 10);
  const versoesRecentes = recentes
    .flatMap((d) => (d.documento_versao ?? []).map((v) => v.id))
    .filter(Boolean);
  const linhasRecentesRes = versoesRecentes.length
    ? await supabase.from("campo_extraido").select("documento_versao_id").in("documento_versao_id", versoesRecentes)
    : { data: [] as Array<{ documento_versao_id: string }> };
  const linhasPorVersao = new Map<string, number>();
  for (const l of (linhasRecentesRes.data as Array<{ documento_versao_id: string }> | null) ?? []) {
    linhasPorVersao.set(l.documento_versao_id, (linhasPorVersao.get(l.documento_versao_id) ?? 0) + 1);
  }
  const linhasDoDocumento = (d: DocumentoNoPainel) =>
    (d.documento_versao ?? []).reduce((s, v) => s + (linhasPorVersao.get(v.id) ?? 0), 0);

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

  // GASTO E COBERTURA — as somas da `lote_execucao`.
  //
  // O MÉDIO É POR MANDATO QUE GASTOU, não pelo total de mandatos. Dividir pelos
  // 12 da mesa quando só 4 rodaram ingestão daria um número três vezes menor que
  // a verdade, e a leitura de quem olha ("cada mandato me custa X") ficaria
  // errada exatamente na direção confortável.
  //
  // A COBERTURA é a razão de DUAS SOMAS, não a média das razões. Um lote de 400
  // linhas com 90% e um de 4 linhas com 25% não fazem 57,5% — fazem 89,4%. Média
  // de porcentagem é o erro clássico aqui, e ele dá peso de lote grande a lote
  // minúsculo.
  const usoErro = Boolean((usoRes as { error?: unknown }).error);
  const usos = (usoRes.data as UsoDoLote[] | null) ?? [];
  const casosComGasto = new Set(usos.map((u) => u.caso_id)).size;
  const gastoTotalUsd: number | null = usoErro || usos.length === 0
    ? null
    : usos.reduce((s, u) => s + (Number(u.custo_total_usd) || 0), 0);
  const gastoMedioUsd: number | null =
    gastoTotalUsd === null || casosComGasto === 0 ? null : gastoTotalUsd / casosComGasto;

  let contasNosDocs = 0;
  let contasExtraidas = 0;
  for (const u of usos) {
    if (!u.contas_nos_documentos) continue;
    contasNosDocs += u.contas_nos_documentos;
    contasExtraidas += u.contas_extraidas ?? 0;
  }
  const cobertura: number | null = usoErro || contasNosDocs === 0 ? null : contasExtraidas / contasNosDocs;

  // A causa do traço, escrita uma vez e usada nos três: banco sem a migration é
  // um problema; nenhuma ingestão ainda é outro; e quem lê precisa saber qual.
  const semMedicao = usoErro
    ? "sem medição — a migration 0115 não está aplicada"
    : "sem medição — nenhuma ingestão registrada ainda";

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
            detalhe={totalDocumentos ? `de ${numero(totalDocumentos)} documentos` : null}
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

          {/* A COBERTURA É O INDICADOR MAIS DURO DESTA TELA, e por isso ela tem
              barra: os outros são totais, este é uma FRAÇÃO — quanto do que
              estava escrito no PDF chegou ao banco. Foi o número que faltava na
              rodada em que 39% das células chegaram e o checklist ficou verde:
              "1.139 linhas extraídas" parece ótimo até alguém dizer que o
              documento tinha 2.893. */}
          <Indicador
            valor={cobertura === null ? null : `${Math.round(cobertura * 100)}%`}
            rotulo="cobertura da extração"
            barra={cobertura}
            detalhe={
              cobertura === null
                ? null
                : `${numero(contasExtraidas)} de ${numero(contasNosDocs)} linhas de conta`
            }
            tom={cobertura !== null && cobertura < 0.6 ? "alerta" : "bom"}
            nota={semMedicao}
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
            detalhe={
              casosComGasto
                ? `sobre ${numero(casosComGasto)} ${casosComGasto === 1 ? "mandato que rodou" : "mandatos que rodaram"}`
                : null
            }
            nota={semMedicao}
          />
          <Indicador
            valor={gastoTotalUsd === null ? null : dinheiro(gastoTotalUsd)}
            rotulo="gasto total de API"
            detalhe={usos.length ? `${numero(usos.length)} ${usos.length === 1 ? "execução" : "execuções"}` : null}
            nota={semMedicao}
          />
        </div>
      </Surgir>

      {/* O TETO DE LEITURA, QUANDO BATE, APARECE — a razão de existir deste
          aviso é o defeito que ele fecha: o corte do PostgREST é silencioso, e
          um painel que mostra números de um pedaço da mesa como se fossem da
          mesa inteira é pior que um painel que não abre. Em operação normal
          este bloco nunca renderiza (o teto é 50 mil linhas). */}
      {(casosRes.truncado || documentosRes.truncado || pendenciasRes.truncado) && (
        <p className="carta border-amber-200 bg-amber-50 px-4 py-3 text-xs text-amber-900">
          Os números acima leem no máximo 50 mil registros por lista, e esse teto foi atingido —
          eles descrevem parte da mesa, não a mesa inteira. Isto pede agregação no banco, não mais
          páginas.
        </p>
      )}

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
                            {/* QUAL checagem acusou. Seis reconciliações
                                diferentes chegam aqui com o mesmo tipo
                                ("os documentos não batem"), e sem este pedaço
                                a fila mostra seis linhas iguais — o analista
                                tem de abrir cada uma para saber do que se
                                trata, que é o oposto de uma fila de triagem. */}
                            {nomeDaChecagem(p.motivo ?? null) && (
                              <span className="text-xs text-tinta-500">
                                · {nomeDaChecagem(p.motivo ?? null)}
                              </span>
                            )}
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
