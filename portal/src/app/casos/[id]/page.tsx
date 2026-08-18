import Link from "next/link";
import { notFound } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { paginar } from "@/lib/supabase/paginar";
import {
  PENDENCIA_TIPOS_RECONCILIACAO,
  PENDENCIA_TIPOS_DIAGNOSTICO_REVISAVEIS,
  PENDENCIA_TIPOS_QUALIDADE_EXTRACAO,
  PENDENCIA_TIPO_ARQUIVO_ILEGIVEL,
  type Caso,
  type Documento,
  type Pendencia,
  type TaxonomiaTipoDocumento,
} from "@/lib/types";
import { CASO_STATUS_LABEL, CASO_STATUS_COLOR } from "@/lib/status";
import { aprovarCaso } from "./actions";
import { ItemPendencia } from "./Pendencia";
import { ExcluirMandato } from "@/components/excluir-mandato";
import { humanizar, suavizarMensagem } from "@/lib/rotulos";
import { formatarPeriodo, formatarTipoTaxonomia } from "@/lib/export";

const LEGIBILIDADE_LABEL: Record<string, string> = {
  degradado: "qualidade degradada",
  ilegivel: "ilegível",
};

// A COLUNA "FONTE" FALAVA BANCO DE DADOS. Ela mostrava `nome_arquivo` e
// `openai_conteudo` crus — vocabulário de quem escreveu o pipeline, não de quem
// confere um mandato. O fato que importa para quem lê é OUTRO: o documento foi
// reconhecido pelo nome do arquivo (barato, determinístico) ou foi preciso ler o
// conteúdo com IA (mais caro, e é o caminho de quem manda "Doc1.pdf").
const FONTE_LABEL: Record<string, string> = {
  nome_arquivo: "nome do arquivo",
  openai_conteudo: "leitura do conteúdo",
  manual: "revisão humana",
};

// Um indicador do topo. Número grande, rótulo embaixo, e um detalhe opcional em
// cor quando ele muda a leitura do número (ex.: "2 bloqueantes").
function Indicador({
  valor, rotulo, detalhe, tom,
}: {
  valor: string | number;
  rotulo: string;
  detalhe?: string | null;
  tom?: "neutro" | "alerta" | "bom";
}) {
  const corDetalhe =
    tom === "alerta" ? "text-red-700" : tom === "bom" ? "text-emerald-700" : "text-tinta-500";
  return (
    <div className="px-4 py-3">
      <p className="indicador-valor">{valor}</p>
      <p className="indicador-rotulo">{rotulo}</p>
      {detalhe && <p className={`mt-1 text-xs font-medium ${corDetalhe}`}>{detalhe}</p>}
    </div>
  );
}

export default async function CasoDashboardPage({
  params,
}: {
  params: Promise<{ id: string }>;
}) {
  const { id } = await params;
  const supabase = await createClient();

  const [casoRes, kitBasicoRes, documentosRes, pendenciasRes, checklistRes, portao2Res,
         perguntasRes] = await Promise.all([
    supabase.from("caso").select("id, nome, produto, status, criado_em").eq("id", id).single(),
    supabase
      .from("taxonomia_tipo_documento")
      .select("codigo, categoria, documento, obrigatoriedade")
      .eq("obrigatoriedade", "obrigatorio")
      .order("codigo"),
    // AS LISTAS DESTA TELA SÃO PAGINADAS. O teto do PostgREST (`db-max-rows`,
    // 1000 no Supabase) corta em silêncio, e aqui as linhas são o conteúdo: a
    // tabela de documentos, a fila de pendências do mandato e a contagem de
    // linhas por documento. Um mandato grande passava a mostrar só os mil
    // primeiros de cada, sem nada na tela dizendo isso.
    paginar<Documento>((de, ate) =>
      supabase
        .from("documento")
        .select(
          `id, tipo_taxonomia, status, confianca, fonte, justificativa, resumo, criado_em,
           entidade:entidade_id(razao_social), periodo:periodo_id(tipo, referencia),
           documento_versao(id, nome_original, legibilidade, nota_legibilidade)`,
        )
        .eq("caso_id", id)
        .order("criado_em", { ascending: false })
        .order("id", { ascending: true })
        .range(de, ate),
    ),
    paginar<Pendencia>((de, ate) =>
      supabase
        .from("pendencia")
        .select("id, tipo, severidade, estado, descricao, documento_id, caso_id, criada_em")
        .eq("caso_id", id)
      // A PENDÊNCIA DECIDIDA CONTINUA NA TELA — e isto é o que faz os três
      // botões (0109) terem sentido. Eles "adicionam um rótulo na pendência";
      // se o item sumisse ao ser decidido, o rótulo não existiria para ninguém
      // ver, e a única forma de saber o que foi decidido seria abrir o banco.
      //
      // Fica de fora só `resolvida`, que é do SISTEMA: o problema deixou de
      // existir, não há decisão humana para exibir nem nada a reconsiderar.
        .in("estado", ["aberta", "em_correcao_interna", "reenviada_ao_cliente",
                       "aceita_com_ressalva", "rejeitada"])
        .order("criada_em", { ascending: false })
        .order("id", { ascending: true })
        .range(de, ate),
    ),
    // db/migrations/0036 — o checklist é a fonte do TERCEIRO estado: um item pode
    // ter documento e ainda assim não ter uma linha extraída
    // (`recebido_nao_valido`). Antes o dashboard derivava "presente" só da
    // existência do documento, e por isso ficava verde sobre um book vazio.
    supabase
      .from("checklist_item_status")
      .select("tipo_taxonomia, status")
      .eq("caso_id", id),
    // db/migrations/0037 — a avaliação do Portão 2. Determinística e sem efeito
    // colateral (a função é `stable`), então dá para chamar a cada render: é a
    // MESMA função que `fn_aprovar_caso` usa para decidir, e não uma segunda
    // implementação da regra aqui no portal.
    supabase.rpc("fn_avaliar_portao2", { p_caso_id: id }),
    // QUANTAS PERGUNTAS ESTE MANDATO SUGERE (0120), só a contagem: `head` não
    // traz linha nenhuma, então o teto de 1000 não entra na conversa e a tela
    // do mandato não paga o preço de montar uma lista que mora em outra aba.
    //
    // A CHAMADA É TOLERANTE A ERRO de propósito. O dono aplica as migrations à
    // mão (db/README.md), então um banco sem a 0120 é estado normal, não
    // defeito — e nesse banco esta linha responde "não achei a função". O botão
    // continua na tela sem o número; o que não pode é a tela inteira do mandato
    // cair por causa de um contador de outra aba.
    supabase.rpc("fn_sugerir_perguntas", { p_caso_id: id }, { head: true, count: "exact" }),
  ]);

  // QUANTAS LINHAS CADA DOCUMENTO RENDEU. É o número que o dono procurava
  // abrindo o export, e ele não existia em tela nenhuma: a tabela dizia que o
  // documento chegou e foi classificado, não que ele TROUXE dado. Documento
  // classificado com zero linha é o modo de falha mais caro deste sistema (19 de
  // 35 numa rodada real), e agora ele aparece na coluna, em vermelho.
  const versoes = documentosRes.data
    .flatMap((d) => (d.documento_versao ?? []).map((v) => v.id))
    .filter(Boolean);
  const linhasRes = versoes.length
    ? await paginar<{ documento_versao_id: string }>((de, ate) =>
        supabase.from("campo_extraido").select("documento_versao_id")
          .in("documento_versao_id", versoes).order("id", { ascending: true }).range(de, ate))
    : { data: [] as Array<{ documento_versao_id: string }>, error: null };
  const linhasPorVersao = new Map<string, number>();
  for (const l of linhasRes.data) {
    linhasPorVersao.set(l.documento_versao_id, (linhasPorVersao.get(l.documento_versao_id) ?? 0) + 1);
  }

  if (casoRes.error || !casoRes.data) {
    notFound();
  }

  const caso = casoRes.data as Caso;
  const kitBasico = (kitBasicoRes.data as TaxonomiaTipoDocumento[] | null) ?? [];
  const documentos = documentosRes.data;
  const pendencias = pendenciasRes.data;

  const tiposPresentes = new Set(documentos.map((d) => d.tipo_taxonomia).filter(Boolean));
  // Chegou, mas não rendeu uma linha: nem verde nem faltante — é o
  // `recebido_nao_valido` de `docs/07`, e é bloqueante para o Portão 2.
  const portao2 = portao2Res.data as {
    elegivel: boolean; motivos: string[]; ressalvas_ativas: number; teto_ressalvas: number;
    status_atual: string;
    // db/migrations/0106 — quantas pendências foram declaradas IMPROCEDENTES.
    // Não entra na regra (rejeitada é estado terminal); entra na tela porque é a
    // única informação que separa um caso que nunca teve pendência de um que
    // teve e as rejeitou. Opcionais: um banco onde a 0106 ainda não foi aplicada
    // devolve o payload da 0037, e a tela tem de continuar funcionando.
    rejeitadas?: number; rejeitadas_nao_sobrepujaveis?: number;
  } | null;
  // Nulo tem significado: OU a 0120 não está aplicada, OU o PostgREST não
  // devolveu contagem. Nos dois casos o botão vai sem número — inventar zero
  // diria "não há nada a perguntar", que é afirmação sobre o mandato, e não é
  // isso que se sabe.
  const perguntasSugeridas = perguntasRes.error ? null : perguntasRes.count ?? null;
  const checklist = (checklistRes.data as Array<{ tipo_taxonomia: string; status: string }> | null) ?? [];
  const tiposSemConteudo = new Set(
    checklist.filter((c) => c.status === "recebido_nao_valido").map((c) => c.tipo_taxonomia),
  );
  // DECIDIDA VAI PARA O FIM. Quem abre a tela quer ver o que falta decidir; o
  // que já foi decidido continua visível (é onde o rótulo mora), mas embaixo.
  const DECIDIDOS = new Set(["aceita_com_ressalva", "rejeitada"]);
  const emAberto = (p: Pendencia) => !DECIDIDOS.has(p.estado);
  const porDecidirPrimeiro = (a: Pendencia, b: Pendencia) =>
    Number(!emAberto(a)) - Number(!emAberto(b));

  const pendenciasRevisao = pendencias.filter((p) =>
    (PENDENCIA_TIPOS_DIAGNOSTICO_REVISAVEIS as readonly string[]).includes(p.tipo),
  );
  const pendenciasReconciliacao = pendencias.filter((p) =>
    (PENDENCIA_TIPOS_RECONCILIACAO as readonly string[]).includes(p.tipo),
  );
  const pendenciasArquivo = pendencias.filter((p) => p.tipo === PENDENCIA_TIPO_ARQUIVO_ILEGIVEL);
  const pendenciasExtracao = pendencias.filter((p) =>
    (PENDENCIA_TIPOS_QUALIDADE_EXTRACAO as readonly string[]).includes(p.tipo),
  );

  // O RESTO — e "o resto" era o BURACO desta tela.
  //
  // As quatro listas acima são por tipo, escolhidas a dedo. Toda pendência de
  // tipo que não está em nenhuma delas simplesmente NÃO APARECIA — e as duas que
  // caem aqui são as que mais bloqueiam: `item_faltante` (obrigatório do Kit
  // Básico ausente, bloqueante, 0004/0036) e `item_sem_conteudo` (chegou e não
  // rendeu uma linha — bloqueante NÃO-SOBREPUJÁVEL, 0036). O card do Portão 2
  // dizia "2 pendência(s) BLOQUEANTE(s) em aberto" e não havia, na página
  // inteira, uma linha que dissesse QUAIS.
  //
  // A grade do Kit Básico mostra o FATO ("faltante", "recebido, sem conteúdo
  // extraído"), o que é fácil confundir com "então está mostrado". Não é a mesma
  // coisa: a pendência é o objeto que bloqueia e sobre o qual se decide, e é ela
  // que precisa estar na tela para poder ser rejeitada. Lista por COMPLEMENTO,
  // não por enumeração: tipo novo nasce visível: o erro que se paga por esquecer
  // de listar é o de mostrar demais, não o de esconder um bloqueio.
  const TIPOS_COM_SECAO_PROPRIA = new Set<string>([
    ...PENDENCIA_TIPOS_DIAGNOSTICO_REVISAVEIS,
    ...PENDENCIA_TIPOS_RECONCILIACAO,
    ...PENDENCIA_TIPOS_QUALIDADE_EXTRACAO,
    PENDENCIA_TIPO_ARQUIVO_ILEGIVEL,
  ]);
  const pendenciasOutras = pendencias.filter((p) => !TIPOS_COM_SECAO_PROPRIA.has(p.tipo));

  // O ARQUIVO DE CADA PENDÊNCIA. A mensagem diz o que está errado; sem o nome do
  // arquivo, quem vai conferir tem de adivinhar em qual dos treze documentos olhar.
  // A versão mais recente é a que vale — é ela que a extração usou.
  // ORDEM DA TABELA: pelo NOME DO ARQUIVO, não pela hora do upload. O cliente
  // manda o book numerado (`01_Balanco`, `02_DRE`, …) e procura por esse número;
  // ordenar por `criado_em desc` embaralhava o book na tela e obrigava a varrer
  // a lista inteira para achar um documento.
  documentos.sort((a, b) => {
    const na = (a.documento_versao ?? []).at(-1)?.nome_original ?? "";
    const nb = (b.documento_versao ?? []).at(-1)?.nome_original ?? "";
    return na.localeCompare(nb, "pt-BR", { numeric: true });
  });

  const arquivoDoDocumento = new Map<string, string>();
  for (const d of documentos) {
    const nome = (d.documento_versao ?? []).map((v) => v.nome_original).filter(Boolean).at(-1);
    if (nome) arquivoDoDocumento.set(d.id, nome);
  }

  const linhasTotais = [...linhasPorVersao.values()].reduce((a, b) => a + b, 0);
  const bloqueantesAbertas = pendencias.filter(
    (p) => emAberto(p) && p.severidade === "bloqueante",
  ).length;
  const abertas = pendencias.filter(emAberto).length;
  const kitPresentes = kitBasico.filter(
    (i) => tiposPresentes.has(i.codigo) && !tiposSemConteudo.has(i.codigo),
  ).length;
  // Documento que chegou, foi classificado e não rendeu UMA linha. É o que o
  // `fn_conferir_lote` mede do lado do banco; aqui ele vira número de topo,
  // porque é a pergunta que a rodada v45 respondeu tarde demais.
  const semLinha = documentos.filter(
    (d) => ((d.documento_versao ?? []).reduce((n, v) => n + (linhasPorVersao.get(v.id) ?? 0), 0)) === 0,
  ).length;

  return (
    <div className="space-y-8">
      <div className="flex flex-wrap items-start justify-between gap-4">
        <div className="min-w-0">
          <div className="flex flex-wrap items-center gap-2.5">
            <h1 className="text-xl font-semibold text-tinta-900">{caso.nome}</h1>
            <span className={`chip ${CASO_STATUS_COLOR[caso.status]}`}>
              {CASO_STATUS_LABEL[caso.status]}
            </span>
          </div>
          {/* O produto do mandato em português: o banco guarda `reestruturacao`. */}
          <p className="mt-0.5 text-sm text-tinta-500">{humanizar(caso.produto)}</p>
        </div>
        <div className="flex flex-wrap items-center gap-2">
          <Link href={`/casos/${id}/adicionar`} className="btn-secundario">
            Adicionar arquivos
          </Link>
          {/* UM EXPORT SÓ NESTA TELA (decisão do dono, 07/08/2026). Esta é a tela de
              CONFERIR O QUE CHEGOU, e o único arquivo que faz sentido aqui é o dos
              dados — ele existe desde a ingestão, mesmo com pendência aberta. O
              export de modelagem mora na tela de Modelagem, junto das premissas que
              ele usa: oferecê-lo aqui convidava a exportar o modelo antes de dizer
              como cada conta projeta. */}
          <a
            href={`/casos/${id}/export?modo=dados`}
            className="btn-secundario"
            title="Todas as abas de dado, linha a linha, sem modelagem. Serve para conferir a extração contra os documentos."
          >
            Exportar dados
          </a>
          {/* A ABA DAS PERGUNTAS AO CLIENTE (0120), que até aqui não tinha
              entrada em tela nenhuma — o motor existia e ninguém no produto
              chegava nele.

              ELA FICA FORA desta tela, e não dentro da fila de pendências, por
              decisão do dono (18/08/2026): o que está lá é decisão sobre
              problema medido; o que está na aba é o que AINDA NÃO foi
              perguntado a ninguém. O número no botão é a contagem de sugestões
              — quando o banco ainda não tem a 0120, ele some e o botão fica. */}
          <Link
            href={`/casos/${id}/perguntas`}
            className="btn-secundario"
            title="As perguntas que o sistema sugere fazer ao cliente a partir do que a extração encontrou. Nada é enviado automaticamente."
          >
            Perguntas ao cliente
            {perguntasSugeridas !== null && perguntasSugeridas > 0 && (
              <span className="chip bg-tinta-100 text-tinta-600">{perguntasSugeridas}</span>
            )}
          </Link>
          {/* A ÚNICA AÇÃO PRIMÁRIA DA TELA. Ela era um botão azul-claro entre
              outros três de peso igual, e a tela não dizia para onde ir depois de
              conferir o que chegou. */}
          <Link href={`/casos/${id}/modelagem`} className="btn-primario">
            Ir para a modelagem
          </Link>
          {/* Excluir fica por ÚLTIMO e discreto: encontrável por quem procura,
              não esbarrável por quem não. */}
          <ExcluirMandato casoId={id} nome={caso.nome} />
        </div>
      </div>

      {/* O RESUMO QUE A TELA NÃO DAVA. Quem abre um mandato pergunta uma coisa:
          "posso confiar neste caso?". A resposta exigia rolar seis seções e
          somar de cabeça. Os quatro números abaixo respondem em um olhar, e o
          terceiro — documentos sem uma linha extraída — é o que a rodada de
          15/08 descobriu tarde: documento classificado, checklist verde, e nada
          no banco. */}
      <div className="carta grid grid-cols-2 divide-x divide-y divide-tinta-100 sm:grid-cols-4 sm:divide-y-0">
        <Indicador valor={documentos.length} rotulo="documentos recebidos" />
        <Indicador
          valor={linhasTotais.toLocaleString("pt-BR")}
          rotulo="linhas financeiras extraídas"
          detalhe={semLinha > 0
            ? `${semLinha} ${semLinha === 1 ? "documento sem nenhuma linha" : "documentos sem nenhuma linha"}`
            : null}
          tom="alerta"
        />
        <Indicador
          valor={`${kitPresentes}/${kitBasico.length}`}
          rotulo="itens do Kit Básico"
          detalhe={kitPresentes === kitBasico.length ? "kit completo" : null}
          tom="bom"
        />
        <Indicador
          valor={abertas}
          rotulo={abertas === 1 ? "pendência em aberto" : "pendências em aberto"}
          detalhe={bloqueantesAbertas > 0
            ? `${bloqueantesAbertas} ${bloqueantesAbertas === 1 ? "bloqueia" : "bloqueiam"} a aprovação`
            : null}
          tom="alerta"
        />
      </div>

      {pendenciasRevisao.filter(emAberto).length > 0 && (
        <div className="flex flex-wrap items-center justify-between gap-3 rounded-lg border border-amber-200 bg-amber-50 px-4 py-3 text-sm">
          <span className="text-amber-900">
            <strong className="font-semibold">
              {pendenciasRevisao.filter(emAberto).length}{" "}
              {pendenciasRevisao.filter(emAberto).length === 1 ? "documento" : "documentos"}
            </strong>{" "}
            com dúvida de classificação, entidade ou período — o sistema quer sua confirmação.
          </span>
          <Link
            href={`/casos/${id}/revisao`}
            className="rounded-md bg-amber-800 px-3 py-1.5 text-xs font-semibold text-white hover:bg-amber-900"
          >
            Revisar agora
          </Link>
        </div>
      )}

      {/* PORTÃO 2 (db/migrations/0037) — a regra de f0/04, visível.
          Antes desta tela não havia como saber se um caso podia ser aprovado:
          a regra não existia em código, e "não implementado" tem a mesma
          aparência de "sem pendência bloqueante" para quem olha o dashboard. */}
      {portao2 && (
        <div
          className={`rounded-lg border p-4 text-sm ${
            portao2.elegivel ? "border-emerald-200 bg-emerald-50" : "carta"
          }`}
        >
          <div className="flex flex-wrap items-center justify-between gap-3">
            <div>
              {/* "PORTÃO 2" É NOME INTERNO (f0/04). Quem confere um mandato não
                  precisa do número da etapa — precisa saber se pode aprovar e o
                  que falta. O nome fica como legenda, não como manchete. */}
              <p className={`font-semibold ${portao2.elegivel ? "text-emerald-900" : "text-tinta-900"}`}>
                {portao2.elegivel
                  ? "Pronto para aprovação"
                  : "Ainda não pode ser aprovado"}
                <span className="ml-2 text-xs font-normal text-tinta-500">conferência final</span>
              </p>
              {!portao2.elegivel && portao2.motivos?.length > 0 && (
                <ul className="mt-1.5 list-disc space-y-0.5 pl-5 text-tinta-700">
                  {/* A MENSAGEM VEM DO BANCO com "(s)" e caixa alta —
                      "4 pendência(s) BLOQUEANTE(s) sem decisão". `suavizarMensagem`
                      já existia para as pendências; o motivo do portão passava direto. */}
                  {portao2.motivos.map((m) => (
                    <li key={m}>{suavizarMensagem(m)}</li>
                  ))}
                </ul>
              )}
              {/* A MESMA REGRA, EM PORTUGUÊS (pedido do dono, 07/08/2026). Antes esta
                  linha dizia "Ressalvas ativas: 0 de 3 (teto por caso, f0/04)" — três
                  coisas erradas de uma vez: citava um documento interno pelo código,
                  mostrava contagem sem dizer o que é uma ressalva, e não explicava a
                  consequência. Quem lê a tela precisa saber o que pode fazer, não o
                  número de referência da norma. */}
              {/* A CONTAGEM, sem teto (0109). O limite de 3 saiu por decisão do
                  dono; o número continua na tela porque é o que distingue um caso
                  limpo de um caso que seguiu por cima de seis pendências. */}
              <p className="mt-1.5 text-xs text-tinta-600">
                {portao2.ressalvas_ativas === 0
                  ? "Nenhuma pendência foi aceita sem resolução neste caso."
                  : `${portao2.ressalvas_ativas} ${portao2.ressalvas_ativas === 1
                      ? "pendência seguiu sem resolução" : "pendências seguiram sem resolução"}`
                    + " — o caso avança com elas registradas, não resolvidas."}
              </p>
              {/* O QUE FOI DECLARADO IMPROCEDENTE (0106). Rejeitar é a única ação
                  que libera o portão SEM TETO — inclusive a pendência que nenhuma
                  ressalva libera. Não dá para proibir (senão uma pendência
                  errada prende o caso para sempre, e o que sobra é editar a
                  tabela por fora, que é a mesma liberação sem rastro). O que dá
                  é não deixar invisível: aqui, e dentro da decisão de aprovação. */}
              {(portao2.rejeitadas ?? 0) > 0 && (
                <p className="mt-1 text-xs text-tinta-700">
                  <strong>
                    {portao2.rejeitadas === 1
                      ? "1 pendência foi declarada improcedente"
                      : `${portao2.rejeitadas} pendências foram declaradas improcedentes`}
                  </strong>
                  {(portao2.rejeitadas_nao_sobrepujaveis ?? 0) > 0 && (
                    <>
                      {", "}
                      {portao2.rejeitadas_nao_sobrepujaveis === 1
                        ? "sendo 1 daquelas que nenhuma ressalva libera"
                        : `sendo ${portao2.rejeitadas_nao_sobrepujaveis} daquelas que nenhuma `
                          + "ressalva libera"}
                    </>
                  )}
                  . Quem decidiu e por quê está na trilha do caso, e vai junto com a aprovação.
                </p>
              )}
            </div>
            {portao2.elegivel && caso.status !== "aprovado" && caso.status !== "pronto_para_base" && (
              <form action={aprovarCaso.bind(null, id)} className="flex items-center gap-2">
                <input
                  type="text"
                  name="motivo"
                  placeholder="Observação da aprovação (opcional)"
                  aria-label="Observação da aprovação"
                  className="w-56 rounded-md border border-tinta-200 px-2.5 py-1.5 text-sm
                             placeholder:text-tinta-400"
                />
                <button type="submit" className="btn-aprovar">
                  Aprovar mandato
                </button>
              </form>
            )}
          </div>
        </div>
      )}

      <section>
        <div className="mb-2 flex items-baseline justify-between gap-3">
          <h2 className="titulo-secao">Kit Básico</h2>
          <p className="text-xs text-tinta-500">
            os {kitBasico.length} documentos obrigatórios do mandato
          </p>
        </div>
        <ul className="grid grid-cols-1 gap-2 sm:grid-cols-2">
          {kitBasico.map((item) => {
            const semConteudo = tiposSemConteudo.has(item.codigo);
            // TRÊS estados, não dois (0036): verde só quando chegou E rendeu
            // linha. O documento que chegou vazio fica âmbar — não verde, porque
            // o book sai vazio nessa parte, e não "faltante", porque o arquivo
            // está lá e pedi-lo de novo ao cliente seria pedir o que ele mandou.
            const presente = tiposPresentes.has(item.codigo) && !semConteudo;
            const cor = presente
              ? "border-emerald-200 bg-emerald-50/60"
              : semConteudo
                ? "border-amber-200 bg-amber-50"
                : "border-tinta-200 bg-white";
            const corTexto = presente
              ? "text-emerald-700"
              : semConteudo
                ? "text-amber-800"
                : "text-tinta-400";
            return (
              <li
                key={item.codigo}
                className={`flex items-center justify-between gap-3 rounded-lg border px-3 py-2.5 text-sm ${cor}`}
              >
                <span className="text-tinta-800">{item.documento}</span>
                <span className={`shrink-0 text-xs font-medium ${corTexto}`}>
                  {presente
                    ? "✓ recebido"
                    : semConteudo
                      ? "chegou, sem dado extraído"
                      : "não recebido"}
                </span>
              </li>
            );
          })}
        </ul>
      </section>

      <section>
        <div className="mb-2 flex items-baseline justify-between gap-3">
          <h2 className="titulo-secao">Documentos</h2>
          <p className="text-xs text-tinta-500">
            {documentos.length} {documentos.length === 1 ? "arquivo recebido" : "arquivos recebidos"}
          </p>
        </div>
        {documentos.length === 0 ? (
          <div className="carta px-6 py-10 text-center text-sm text-tinta-500">
            Nenhum documento recebido ainda.
          </div>
        ) : (
          <div className="carta overflow-x-auto">
            <table className="w-full text-left text-sm">
              <thead className="border-b border-tinta-200 bg-tinta-50 text-[11px] uppercase tracking-wide text-tinta-500">
                <tr>
                  <th className="px-3 py-2.5 font-semibold">Arquivo</th>
                  <th className="px-3 py-2.5 font-semibold">Tipo</th>
                  <th className="px-3 py-2.5 font-semibold">Entidade</th>
                  <th className="px-3 py-2.5 font-semibold">Período</th>
                  {/* A COLUNA QUE FALTAVA. Sem ela a tabela dizia que o arquivo
                      chegou e foi entendido, nunca que ele TROUXE dado. */}
                  <th className="px-3 py-2.5 text-right font-semibold">Linhas</th>
                  {/* CONFIANÇA E ORIGEM NA MESMA COLUNA. Eram duas, e a tabela
                      estourava a largura da tela — a coluna de ação saía cortada
                      ("ve linha"), que é o tipo de defeito que só aparece
                      olhando a página renderizada. São dois fatos sobre a mesma
                      pergunta: o quanto o sistema confia, e por quê. */}
                  <th className="px-3 py-2.5 font-semibold">Confiança</th>
                  <th className="px-3 py-2.5"></th>
                </tr>
              </thead>
              <tbody className="divide-y divide-tinta-100">
                {documentos.map((doc) => {
                  const versao = doc.documento_versao?.[0];
                  const legibilidadeRuim = versao?.legibilidade && versao.legibilidade !== "ok";
                  const linhas = (doc.documento_versao ?? []).reduce(
                    (n, v) => n + (linhasPorVersao.get(v.id) ?? 0), 0,
                  );
                  return (
                    <tr key={doc.id} className="align-top transition-colors hover:bg-tinta-50">
                      <td className="max-w-[15rem] px-3 py-2.5">
                        <span
                          className="block truncate font-medium text-tinta-900"
                          title={versao?.nome_original ?? ""}
                        >
                          {versao?.nome_original ?? "—"}
                        </span>
                        {legibilidadeRuim && (
                          <span
                            title={versao?.nota_legibilidade ?? ""}
                            className="ml-2 chip bg-red-100 text-red-800"
                          >
                            {LEGIBILIDADE_LABEL[versao!.legibilidade!] ?? versao!.legibilidade}
                          </span>
                        )}
                        {/* O RESUMO SAIU DA COLUNA PRÓPRIA e virou a segunda linha do
                            arquivo: numa coluna estreita ele aparecia truncado em três
                            palavras, o que é ruído com cara de informação. */}
                        {doc.resumo && (
                          <p className="mt-0.5 max-w-[15rem] truncate text-xs text-tinta-500" title={doc.resumo}>
                            {doc.resumo}
                          </p>
                        )}
                      </td>
                      <td className="px-3 py-2.5 whitespace-nowrap text-tinta-700">
                        {formatarTipoTaxonomia(doc.tipo_taxonomia)}
                      </td>
                      <td className="max-w-[10rem] truncate px-3 py-2.5 text-tinta-700"
                          title={doc.entidade?.razao_social ?? ""}>
                        {doc.entidade?.razao_social ?? "—"}
                      </td>
                      <td className="px-3 py-2.5 whitespace-nowrap text-tinta-700">
                        {doc.periodo ? formatarPeriodo(doc.periodo.tipo, doc.periodo.referencia) : "—"}
                      </td>
                      <td className="px-3 py-2.5 text-right">
                        {linhas > 0 ? (
                          <span className="tabular-nums text-tinta-900">{linhas.toLocaleString("pt-BR")}</span>
                        ) : (
                          <span
                            className="chip bg-red-100 text-red-800"
                            title="O documento foi recebido e classificado, mas nenhuma linha financeira foi gravada."
                          >
                            nenhuma
                          </span>
                        )}
                      </td>
                      <td className="px-3 py-2.5 whitespace-nowrap">
                        <span className="tabular-nums text-tinta-700">
                          {doc.confianca != null ? `${Math.round(doc.confianca * 100)}%` : "—"}
                        </span>
                        {doc.fonte && (
                          <span
                            className="ml-1.5 hidden text-xs text-tinta-500 xl:inline"
                            title={`Como o documento foi reconhecido: ${FONTE_LABEL[doc.fonte] ?? humanizar(doc.fonte)}`}
                          >
                            · {FONTE_LABEL[doc.fonte] ?? humanizar(doc.fonte)}
                          </span>
                        )}
                      </td>
                      <td className="px-3 py-2.5 text-right whitespace-nowrap text-xs">
                        <Link
                          href={`/casos/${id}/documentos/${doc.id}`}
                          className="font-medium text-acento-600 hover:text-acento-700 hover:underline"
                        >
                          abrir
                        </Link>
                      </td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
          </div>
        )}
      </section>

      {pendenciasOutras.length > 0 && (
        <section>
          <div className="mb-2 flex items-baseline justify-between gap-3">
            <h2 className="titulo-secao">O que falta chegar</h2>
            <p className="text-xs text-tinta-500">{pendenciasOutras.length} em aberto</p>
          </div>
          <p className="mb-2.5 text-xs text-tinta-500">
            Documento obrigatório ausente, ou que chegou sem nenhuma linha aproveitável. A grade do
            Kit Básico mostra o mesmo fato; aqui cada item pode ser decidido.
          </p>
          <ul className="space-y-2">
            {[...pendenciasOutras].sort(porDecidirPrimeiro).map((p) => (
              <ItemPendencia
                key={p.id} p={p} tom={p.severidade === "bloqueante" ? "red" : "amber"} casoId={id}
                arquivo={p.documento_id ? arquivoDoDocumento.get(p.documento_id) ?? null : null}
              />
            ))}
          </ul>
        </section>
      )}

      <section>
        <div className="mb-2 flex items-baseline justify-between gap-3">
          {/* "Classe A/B" é vocabulário interno (f0/04): A é o que se confere
              dentro do próprio documento, B é entre documentos. Para quem lê a
              tela o que importa é que são números que não fecham. */}
          <h2 className="titulo-secao">Números que não fecham</h2>
          <p className="text-xs text-tinta-500">
            {pendenciasReconciliacao.length === 0
              ? "conferências automáticas entre documentos"
              : `${pendenciasReconciliacao.length} divergência(s)`}
          </p>
        </div>
        {pendenciasReconciliacao.length === 0 ? (
          <div className="carta px-4 py-6 text-sm text-tinta-500">
            Nenhuma divergência encontrada — o balanço fecha, o caixa bate com o fluxo e não há
            conta contada duas vezes.
          </div>
        ) : (
          <ul className="space-y-2">
            {[...pendenciasReconciliacao].sort(porDecidirPrimeiro).map((p) => (
              <ItemPendencia
                key={p.id} p={p} tom="amber" casoId={id}
                arquivo={p.documento_id ? arquivoDoDocumento.get(p.documento_id) ?? null : null}
              />
            ))}
          </ul>
        )}
      </section>

      {pendenciasArquivo.length > 0 && (
        <section>
          <div className="mb-2 flex items-baseline justify-between gap-3">
            <h2 className="titulo-secao">Arquivos ilegíveis</h2>
            <p className="text-xs text-tinta-500">{pendenciasArquivo.length} arquivo(s)</p>
          </div>
          <ul className="space-y-2">
            {[...pendenciasArquivo].sort(porDecidirPrimeiro).map((p) => (
              <ItemPendencia
                key={p.id} p={p} tom="red" casoId={id}
                arquivo={p.documento_id ? arquivoDoDocumento.get(p.documento_id) ?? null : null}
              />
            ))}
          </ul>
        </section>
      )}

      {pendenciasExtracao.length > 0 && (
        <section>
          <div className="mb-2 flex items-baseline justify-between gap-3">
            <h2 className="titulo-secao">Extração incompleta</h2>
            <p className="text-xs text-tinta-500">{pendenciasExtracao.length} documento(s)</p>
          </div>
          <ul className="space-y-2">
            {[...pendenciasExtracao].sort(porDecidirPrimeiro).map((p) => (
              <ItemPendencia
                key={p.id} p={p} tom="red" casoId={id}
                arquivo={p.documento_id ? arquivoDoDocumento.get(p.documento_id) ?? null : null}
              />
            ))}
          </ul>
        </section>
      )}
    </div>
  );
}
