import Link from "next/link";
import { notFound } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { SecaoLinhas } from "./SecaoLinhas";
import { FormParametros, FormPremissa } from "./FormsTopo";
import { chaveDaLinha, vinculoPorLinha } from "@/lib/modelagem-linha";
import { humanizar, rotuloDaSecao } from "@/lib/rotulos";

// A seção MODELAGEM do mandato (pedido do dono, Fase 7.3; revisada na Fase 8
// depois da rodada real do Teste v35).
//
// É aqui que "cada caso é um caso" vira operação: o analista escolhe as premissas
// que valem para ESTE mandato e diz ONDE cada uma entra na projeção.
//
// O QUE A RODADA REAL MUDOU NESTA TELA. Ela listava as 236 linhas do caso como se
// todas fossem conta projetável, e três coisas saíam erradas por isso:
//   • `Ativo Circulante 67.878` aparecia entre os 32 componentes dela, e um clique
//     em "aplicar a todas" projetava o total E as partes — dupla contagem, que não
//     parece erro no arquivo: parece um número maior;
//   • os 12 `Faturamento Janeiro…Dezembro` entravam como 12 contas, quando são o
//     insumo da curva de sazonalidade;
//   • `(-) Depreciação acumulada` aparecia POSITIVA e nada dizia a unidade, então
//     `TOTAL — saldo devedor 51.300.000` (reais) ficava ao lado de `Passivo
//     Circulante 92.539` (milhares) sem aviso.
// Agora cada linha traz PAPEL, sinal, unidade/moeda e documento de origem, e só
// `conta` recebe premissa. A regra mora no banco (0042) — aqui é a apresentação
// dela: se esta tela mentisse, o banco recusaria de todo jeito.
//
// Nada de regra de projeção vive aqui: tudo é `rpc` para as funções da 0038/0042.

interface PremissaCatalogo {
  codigo: string;
  nome: string;
  natureza: string;
  formula: string;
  unidade: string | null;
  aplica_em: string[];
  setores: string[];
  descricao: string | null;
}

interface CasoPremissa {
  premissa_codigo: string;
  valores: Record<string, number>;
  origem: string | null;
}

interface LinhaDoCaso {
  secao_canonica: string | null;
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

interface LinhaVinculo {
  secao_canonica: string | null;
  rotulo_norm: string;
  entidade: string | null;
  premissa_codigo: string | null;
  sazonalidade_codigo: string | null;
}

const SETORES = [
  ["industria", "Indústria / metalurgia"], ["varejo", "Varejo"], ["servicos", "Serviços"],
  ["agro", "Agro"], ["construcao", "Construção / incorporação"], ["logistica", "Logística / transporte"],
  ["saude", "Saúde"], ["energia", "Energia"], ["tecnologia", "Tecnologia"],
  ["alimentos", "Alimentos e bebidas"], ["educacao", "Educação"], ["mineracao", "Mineração"],
  ["papel_celulose", "Papel e celulose"], ["quimica", "Química / petroquímica"],
  ["textil", "Têxtil / vestuário"], ["automotivo", "Automotivo / autopeças"],
  ["farma", "Farma / distribuição"], ["telecom", "Telecom"], ["hotelaria", "Hotelaria / turismo"],
  ["imobiliario", "Imobiliário (renda)"],
];

const NATUREZA_LABEL: Record<string, string> = {
  macro: "Macro", receita: "Receita", custo: "Custo", despesa: "Despesa",
  giro: "Capital de giro", investimento: "Investimento", divida: "Dívida",
  tributo: "Tributos", socios: "Sócios", sazonalidade: "Sazonalidade",
  operacional: "Driver operacional",
};

// O que cada papel significa PARA O ARQUIVO. O texto é o destino da linha, não uma
// etiqueta: quem lê precisa entender por que aquela linha não tem seletor, senão
// procura o defeito na tela.
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

const MESES = ["jan", "fev", "mar", "abr", "mai", "jun", "jul", "ago", "set", "out", "nov", "dez"];

// CRONÔMETRO DE CHAMADA, em escopo de MÓDULO e não dentro do componente.
//
// Fica aqui por causa do `react-hooks/purity` do eslint, que reprova `Date.now()`
// no corpo de um componente — e reprova com razão no caso geral: leitura de relógio
// em render de componente cliente quebra a idempotência que o React assume. Esta é
// uma página `async` de servidor, que roda uma vez por requisição, e o relógio mede
// I/O que já aconteceu. Em escopo de módulo a regra não se aplica e a intenção fica
// explícita, em vez de silenciada com um `eslint-disable` que esconderia o motivo.
async function medir<T>(p: PromiseLike<T>): Promise<[T, number]> {
  const t0 = Date.now();
  const r = await p;
  return [r, Date.now() - t0];
}

export default async function ModelagemPage({
  params, searchParams,
}: {
  params: Promise<{ id: string }>;
  searchParams: Promise<{ q?: string }>;
}) {
  const { id } = await params;
  const { q } = await searchParams;
  const busca = (q ?? "").trim();
  const supabase = await createClient();

  const casoRes = await supabase.from("caso").select("id, nome, produto, status").eq("id", id).single();
  if (casoRes.error || !casoRes.data) notFound();
  const caso = casoRes.data;

  const paramRes = await supabase
    .from("caso_modelagem").select("*").eq("caso_id", id).maybeSingle();
  const parametros = paramRes.data as {
    entidade: string | null; ultimo_exercicio_real: number | null;
    indice_macro: string | null; setor: string | null; anos_projetados: number;
  } | null;

  // O catálogo vem FILTRADO pelo setor — é a sugestão da 0038. Sem setor
  // definido, vem só a base comum, que é a resposta correta para "ainda não sei
  // o setor" (e não uma lista de 90 premissas para escolher no escuro).
  // CADA CHAMADA VOLTA CRONOMETRADA, e o tempo aparece na caixa de erro.
  //
  // POR QUE ISSO É DIAGNÓSTICO E NÃO ENFEITE. Quando a resposta é `canceling
  // statement due to statement timeout`, o tempo decorrido É O TETO que o
  // servidor aplica — a consulta foi cortada nele. Sem o número, "estourou o
  // tempo" não diz QUAL tempo, e 8 s (o default do Supabase, contra o qual a
  // 0101 foi dimensionada) e 3 s (um projeto configurado mais apertado) produzem
  // exatamente a mesma mensagem. Foi essa ambiguidade que fez a rodada da 0101
  // custar idas e vindas: a tela relatava o sintoma sem a única grandeza capaz de
  // distinguir "a função está lenta" de "o teto é mais baixo do que supomos".
  //
  // O cronômetro fica FORA do `Promise.all` de propósito: as sete chamadas são
  // concorrentes, então o que interessa é o tempo de parede de cada uma sob a
  // concorrência real da página, não um tempo isolado que ninguém experimenta.
  const [
    [sugeridasRes, msSugeridas], [ativasRes, msAtivas], [vinculosRes, msVinculos],
    [confRes, msConf], [camposRes, msCampos], [sazRes, msSaz], [docsRes, msDocs],
  ] = await Promise.all([
    medir(supabase.rpc("fn_premissas_sugeridas", { p_setor: parametros?.setor ?? null })),
    medir(supabase.from("caso_premissa").select("premissa_codigo, valores, origem")
      .eq("caso_id", id).eq("ativo", true)),
    medir(supabase.from("caso_linha_premissa")
      .select("secao_canonica, rotulo_norm, entidade, premissa_codigo, sazonalidade_codigo")
      .eq("caso_id", id)),
    medir(supabase.rpc("fn_conferir_modelagem", { p_caso_id: id })),
    // As linhas do caso — por FUNÇÃO (0039/0042), não por consulta direta.
    //
    // `campo_extraido` não tem `caso_id`: o vínculo é `campo_extraido →
    // documento_versao → documento`. A primeira versão desta tela consultava a
    // tabela direto e, com a RLS aberta a qualquer autenticado, trazia as linhas
    // de TODOS os mandatos. O escopo por caso vive em UM lugar, coberto por teste.
    medir(supabase.rpc("fn_linhas_para_modelagem", { p_caso_id: id })),
    // A curva de sazonalidade é DERIVADA do faturamento mensal do caso (0040):
    // ninguém digita 12 percentuais que o documento já afirma.
    medir(supabase.rpc("fn_sazonalidade_do_caso", { p_caso_id: id })),
    // Só para SUGERIR entidade e último exercício no passo 1 (ver abaixo).
    medir(supabase.from("documento")
      .select("tipo_taxonomia, entidade(razao_social), periodo(referencia)").eq("caso_id", id)),
  ]);

  // ---------------------------------------------------------------------------
  // ERRO DE RPC NUNCA MAIS VIRA "LISTA VAZIA".
  //
  // Todas as sete chamadas acima terminavam em `?? []`, e o `.error` de nenhuma
  // era lido. O efeito apareceu em produção do jeito mais enganoso possível: a
  // seção 3 anunciou "Este caso ainda não tem linha extraída com valor" num caso
  // com 203 linhas, porque `fn_linhas_para_modelagem` tinha FALHADO e a falha foi
  // convertida em lista vazia. O analista lê isso como "o caso está vazio" e vai
  // procurar o problema na extração, que está intacta.
  //
  // Causa provável quando isso acontece logo depois de aplicar uma migration: o
  // PostgREST guarda um CACHE do schema, e função criada/derrubada só passa a
  // existir para ele depois de `notify pgrst, 'reload schema';`. Até lá a chamada
  // volta "function not found" — que é um erro, não um caso sem dado.
  //
  // A distinção que a tela precisa fazer, e agora faz: "não há linha" é uma
  // resposta; "não consegui perguntar" é outra.
  // ---------------------------------------------------------------------------
  const chamadas = ([
    ["premissas sugeridas (fn_premissas_sugeridas)", sugeridasRes.error, msSugeridas],
    ["premissas ativas (caso_premissa)", ativasRes.error, msAtivas],
    ["vínculos de linha (caso_linha_premissa)", vinculosRes.error, msVinculos],
    ["conferência (fn_conferir_modelagem)", confRes.error, msConf],
    ["linhas do caso (fn_linhas_para_modelagem)", camposRes.error, msCampos],
    ["curva de sazonalidade (fn_sazonalidade_do_caso)", sazRes.error, msSaz],
    ["documentos do caso", docsRes.error, msDocs],
  ] as const);

  // O tempo entra na linha da falha. Num cancelamento por tempo ele é o TETO do
  // servidor, que é a grandeza que faltava para saber contra o que a tela está
  // lutando (ver o comentário do `medir`).
  const falhas = chamadas
    .filter(([, e]) => e)
    .map(([nome, e, ms]) => `${nome}: ${e!.message} [${ms} ms]`);

  // E os tempos de QUEM DEU CERTO também, porque é a linha de base que dá sentido
  // ao número da falha: se as cinco chamadas leves voltam em 80 ms e as duas
  // pesadas são cortadas em 8.000 ms, o servidor está saudável e as duas funções
  // é que não couberam. Se TUDO estiver lento, o problema é a instância, e nenhuma
  // otimização de SQL vai resolver.
  const tempos = chamadas
    .map(([nome, e, ms]) => `${nome.replace(/ \(.*\)$/, "")} ${ms} ms${e ? " (falhou)" : ""}`)
    .join(" · ");

  const sugeridas = (sugeridasRes.data as PremissaCatalogo[] | null) ?? [];
  const ativas = (ativasRes.data as CasoPremissa[] | null) ?? [];
  const vinculos = (vinculosRes.data as LinhaVinculo[] | null) ?? [];
  const conf = confRes.data as {
    premissas_ativas: number; premissas_sem_valor: string[];
    linhas_do_caso: number; linhas_com_premissa: number; linhas_sem_premissa: number;
    linhas_nao_projetaveis: Record<string, number>;
    vinculos_orfaos: string[]; pronto: boolean;
  } | null;
  const curva = (sazRes.data as { mes: number; fracao: number; n_observacoes: number }[] | null) ?? [];

  const ativasPorCodigo = new Map(ativas.map((a) => [a.premissa_codigo, a]));
  // Indexado pelo PAR (seção, rótulo) — ver `lib/modelagem-linha.ts`. Com a chave
  // só no rótulo, vincular `Empréstimos e Financiamentos` no passivo circulante
  // fazia a linha homônima do NÃO circulante aparecer preenchida sozinha, e o
  // valor herdado virava o `orig` daquela seção: no salvamento seguinte ele ia ao
  // banco como escolha do analista.
  const vinculoDaLinha = vinculoPorLinha(vinculos);
  const nomeDaPremissa = new Map(sugeridas.map((p) => [p.codigo, p.nome]));

  // SUGESTÃO de entidade e de último exercício, a partir do que o caso já tem.
  // No v35 os dois campos ficaram VAZIOS enquanto o banco sabia as duas coisas —
  // e campo vazio num parâmetro que dirige todo o modelo é convite a esquecer.
  // É sugestão, não imposição: entra como `defaultValue` e o analista sobrescreve.
  const docs = (docsRes.data as {
    entidade: { razao_social: string } | { razao_social: string }[] | null;
    periodo: { referencia: string } | { referencia: string }[] | null;
  }[] | null) ?? [];
  const um = <T,>(x: T | T[] | null): T | null => (Array.isArray(x) ? x[0] ?? null : x);
  const contagemEntidade = new Map<string, number>();
  let anoMaisRecente = 0;
  for (const d of docs) {
    const razao = um(d.entidade)?.razao_social;
    if (razao) contagemEntidade.set(razao, (contagemEntidade.get(razao) ?? 0) + 1);
    for (const m of (um(d.periodo)?.referencia ?? "").matchAll(/\d{4}/g)) {
      anoMaisRecente = Math.max(anoMaisRecente, Number(m[0]));
    }
  }
  const entidadeSugerida = [...contagemEntidade.entries()].sort((a, b) => b[1] - a[1])[0]?.[0] ?? "";
  const anoSugerido = anoMaisRecente || new Date().getFullYear() - 1;

  // Anos a projetar: do último exercício real + 1 em diante. É o horizonte que as
  // premissas precisam cobrir, e é derivado dos parâmetros — não digitado duas vezes.
  const ultimoReal = parametros?.ultimo_exercicio_real ?? anoSugerido;
  const nAnos = parametros?.anos_projetados ?? 5;
  const anos = Array.from({ length: nAnos }, (_, i) => ultimoReal + 1 + i);

  // Linhas do caso agrupadas por seção canônica — é a unidade do aplicar-em-lote.
  // A função já devolve UMA linha por (seção, rótulo normalizado): o agrupamento
  // por rótulo é dela, não daqui, para a tela e o lote concordarem sobre o que é
  // "uma linha".
  const todasLinhas = (camposRes.data as LinhaDoCaso[] | null) ?? [];
  const alvo = busca.toLowerCase();
  const linhasPorSecao = new Map<string, LinhaDoCaso[]>();
  for (const c of todasLinhas) {
    if (alvo && !c.chave.toLowerCase().includes(alvo)) continue;
    const secao = c.secao_canonica ?? "(sem seção canônica)";
    if (!linhasPorSecao.has(secao)) linhasPorSecao.set(secao, []);
    linhasPorSecao.get(secao)!.push(c);
  }

  const porNatureza = new Map<string, PremissaCatalogo[]>();
  for (const p of sugeridas) {
    if (!porNatureza.has(p.natureza)) porNatureza.set(p.natureza, []);
    porNatureza.get(p.natureza)!.push(p);
  }

  const premissasSazonais = ativas.filter((a) => a.premissa_codigo.includes("SAZON")
    || a.premissa_codigo === "CRONOGRAMA_FISICO" || a.premissa_codigo === "PARADA_MANUTENCAO");

  return (
    <main className="mx-auto max-w-6xl space-y-6 p-6">
      <div className="flex items-baseline justify-between gap-4">
        <div>
          <Link href={`/casos/${id}`} className="text-sm text-neutral-500 hover:underline">
            ← {caso.nome}
          </Link>
          <h1 className="text-xl font-semibold">Modelagem</h1>
          <p className="text-xs text-neutral-500">
            Escolha as premissas deste mandato e diga onde cada uma entra na projeção.
          </p>
        </div>
        {/* OS DOIS EXPORTS, LADO A LADO (decisão do dono, 07/08/2026). Eram um só,
            e o "completo" trazia as 12 abas de dado cru junto com o modelo — 29
            abas para quem só queria o que vai a comitê. Agora são dois arquivos
            com dois propósitos, e o nome de cada botão diz qual é o seu:
            "modelagem" entrega as 14 abas do modelo; "dados financeiros" entrega
            a conferência da ingestão, linha a linha. O de dados vem primeiro por
            ser o que se usa ANTES de modelar. */}
        <div className="flex shrink-0 items-center gap-2">
          <a
            href={`/casos/${id}/export?modo=dados`}
            className="rounded border border-neutral-300 bg-white px-3 py-1.5 text-sm font-medium text-neutral-700 hover:bg-neutral-50"
            title="As abas de dado, linha a linha, como saíram da extração. Serve para conferir contra os documentos — não projeta nada."
          >
            Exportar dados financeiros ↓
          </a>
          <a
            href={`/casos/${id}/export`}
            className="rounded border border-indigo-300 bg-indigo-50 px-3 py-1.5 text-sm font-medium text-indigo-800 hover:bg-indigo-100"
            title="As 14 abas do modelo institucional, projetadas e editáveis dentro do Excel, mais a Modelagem e os índices macro. Sem as abas de dado cru."
          >
            Exportar modelagem ↓
          </a>
        </div>
      </div>

      {/* CONSULTA QUE FALHOU aparece ANTES de tudo, e nomeada. Enquanto isto não
          existia, uma RPC quebrada saía da tela como "este caso não tem linha". */}
      {falhas.length > 0 && (
        <section className="rounded border border-red-300 bg-red-50 p-3 text-sm text-red-900">
          <p className="font-semibold">
            {falhas.length} consulta(s) ao banco FALHARAM — o que está faltando nesta tela é efeito
            disso, não é o caso estar vazio.
          </p>
          <ul className="mt-1 list-disc pl-5 text-xs">
            {falhas.map((f) => <li key={f} className="font-mono">{f}</li>)}
          </ul>
          {/* A ORIENTAÇÃO SEGUE O ERRO, não o palpite mais comum.

              Esta caixa nasceu (PR #89) dando SEMPRE o conselho do cache de schema do
              PostgREST — que é o certo para "function not found" e o ERRADO para
              consulta cancelada. E foi com um `statement timeout` na tela que o
              conselho apareceu em produção: mandava recarregar o cache de schema
              quando a função existia, era encontrada, e só não tinha terminado em 8 s.
              Orientação errada num painel de diagnóstico é pior que orientação
              nenhuma: manda o analista consertar o que não está quebrado e confirma
              a impressão de que o PR não funcionou. */}
          {falhas.some((f) => /statement timeout|canceling statement/i.test(f)) ? (
            <p className="mt-2 text-xs">
              <strong>A consulta foi CANCELADA por tempo</strong> (o Supabase corta em 8 s), não é
              função faltando nem caso vazio — recarregar o cache de schema não resolve isto. Se as
              migrations <code className="font-mono">0101</code> e <code className="font-mono">0102</code>{" "}
              ainda não foram aplicadas neste banco, é isso: elas existirem no GitHub não as coloca
              no Supabase. Para confirmar sem adivinhar, rode no SQL Editor{" "}
              <code className="font-mono">select jsonb_pretty(fn_diagnostico_modelagem(&apos;{id}&apos;));</code>{" "}
              e olhe <code className="font-mono">correcoes_instaladas</code>. O diagnóstico completo
              de ambiente está em <code className="font-mono">db/diagnostico_modelagem.sql</code>.
            </p>
          ) : (
            <p className="mt-2 text-xs">
              Se isto começou logo depois de aplicar uma migration, é quase certo que seja o cache de
              schema do PostgREST: rode <code className="font-mono">notify pgrst, &apos;reload schema&apos;;</code>{" "}
              no SQL Editor do Supabase e recarregue. Função recém-criada só existe para a API depois
              disso.
            </p>
          )}
          {/* A linha de base: o tempo das SETE chamadas, inclusive as que deram
              certo. É o que separa "duas funções não couberam" de "a instância
              inteira está lenta" — e a segunda não se resolve com SQL. */}
          <p className="mt-2 font-mono text-[10px] text-red-800">{tempos}</p>
        </section>
      )}

      {/* 4. CONFERÊNCIA — no TOPO, não no fim. É o que o analista precisa saber
          antes de mexer em qualquer coisa: quantas linhas ficariam de fora e qual
          premissa está sem valor. Pôr isso no rodapé seria pôr o resultado depois
          da decisão. */}
      {conf && (
        <section
          className={`rounded border p-3 text-sm ${
            conf.pronto ? "border-emerald-300 bg-emerald-50" : "border-amber-300 bg-amber-50"
          }`}
        >
          <p className={`font-medium ${conf.pronto ? "text-emerald-900" : "text-amber-900"}`}>
            {conf.pronto
              ? "Pronto para o export de modelagem"
              : "Ainda falta algo para o export de modelagem"}
          </p>
          <ul className="mt-1 space-y-0.5 text-neutral-700">
            <li>
              {conf.linhas_com_premissa} de {conf.linhas_do_caso} <strong>contas projetáveis</strong>{" "}
              com premissa — <strong>{conf.linhas_sem_premissa} sem premissa</strong>, que não serão
              projetadas (o arquivo mostra cada uma como não projetada, nunca projetada por padrão).
            </li>
            {/* O que NÃO é projetável fica nomeado, em vez de desaparecer da conta:
                no v35 a tela dizia "0 de 236" e o alvo real era bem menor. */}
            {conf.linhas_nao_projetaveis && Object.keys(conf.linhas_nao_projetaveis).length > 0 && (
              <li className="text-neutral-600">
                Fora da conta por natureza da linha:{" "}
                {Object.entries(conf.linhas_nao_projetaveis)
                  .map(([p, n]) => `${n} ${PAPEL_INFO[p]?.rotulo ?? p}`)
                  .join(", ")}{" "}
                — subtotal sai como soma dos componentes, série mensal alimenta a sazonalidade e
                indicador derivado não se projeta.
              </li>
            )}
            <li>{conf.premissas_ativas} premissa(s) ativa(s) neste caso.</li>
            {conf.premissas_sem_valor?.length > 0 && (
              <li className="text-amber-900">
                <strong>Sem valor preenchido:</strong> {conf.premissas_sem_valor.join(", ")} — premissa
                ativa sem valor projetaria com zero, então ela impede o &quot;pronto&quot;. Premissa
                macro puxa o Focus sozinha ao ser ativada sem valor; se ficou vazia, é porque o Focus
                não publica expectativa para esses anos.
              </li>
            )}
            {conf.vinculos_orfaos?.length > 0 && (
              <li className="text-amber-900">
                <strong>Configuração apontando para linha que não existe:</strong>{" "}
                {conf.vinculos_orfaos.join(", ")} — o documento não chegou, ou foi reextraído com
                outro rótulo.
              </li>
            )}
          </ul>
        </section>
      )}

      {/* 1. PARÂMETROS — as três células que saíram do topo da aba Modelagem. */}
      <section className="rounded border border-neutral-200 bg-white p-4">
        <h2 className="mb-1 text-sm font-semibold text-neutral-700">1. Parâmetros do mandato</h2>
        <p className="mb-3 text-xs text-neutral-500">
          Entidade modelada, corte do último exercício real e índice macro saíram do topo da planilha
          e vivem aqui — o Excel sai já parametrizado com o que você escolher. O setor filtra as
          premissas sugeridas no passo 2. Entidade e último exercício vêm <strong>sugeridos</strong>{" "}
          pelo que os documentos deste caso dizem; confira antes de salvar.
        </p>
        <FormParametros casoId={id}>
          <label className="text-sm">
            <span className="text-neutral-600">Entidade modelada</span>
            <input
              type="text" name="entidade" defaultValue={parametros?.entidade ?? entidadeSugerida}
              placeholder="razão social como aparece nas abas de dados"
              className="mt-1 w-full rounded border border-neutral-300 px-2 py-1"
            />
          </label>
          <label className="text-sm">
            <span className="text-neutral-600">Último exercício realizado</span>
            <input
              type="number" name="ultimo_exercicio_real"
              defaultValue={parametros?.ultimo_exercicio_real ?? anoSugerido}
              className="mt-1 w-full rounded border border-neutral-300 px-2 py-1"
            />
          </label>
          <label className="text-sm">
            <span className="text-neutral-600">Índice macro que dirige a projeção</span>
            <select
              name="indice_macro" defaultValue={parametros?.indice_macro ?? "IPCA"}
              className="mt-1 w-full rounded border border-neutral-300 px-2 py-1"
            >
              {["IPCA", "IGPM", "INCC", "SELIC", "CAMBIO_USD", "PIB"].map((s) => (
                <option key={s} value={s}>{s}</option>
              ))}
            </select>
          </label>
          <label className="text-sm">
            <span className="text-neutral-600">Setor do mandato</span>
            <select
              name="setor" defaultValue={parametros?.setor ?? ""}
              className="mt-1 w-full rounded border border-neutral-300 px-2 py-1"
            >
              <option value="">(ainda não definido — sugere só a base comum)</option>
              {SETORES.map(([v, label]) => <option key={v} value={v}>{label}</option>)}
            </select>
          </label>
          <label className="text-sm">
            <span className="text-neutral-600">Anos projetados</span>
            <input
              type="number" name="anos_projetados" min={1} max={10}
              defaultValue={parametros?.anos_projetados ?? 5}
              className="mt-1 w-full rounded border border-neutral-300 px-2 py-1"
            />
            {/* O horizonte que estes dois campos PRODUZEM, escrito por extenso.
                "5 anos" a partir de "2025" é uma conta que o analista fazia de
                cabeça enquanto preenchia premissa — e errar o ano de corte move
                a projeção inteira sem gerar um único aviso. */}
            <span className="mt-1 block text-xs tabular-nums text-neutral-500">
              {anos.join(" · ")}
            </span>
          </label>
        </FormParametros>
      </section>

      {/* 2. PREMISSAS DO CASO */}
      <section className="rounded border border-neutral-200 bg-white p-4">
        <h2 className="mb-1 text-sm font-semibold text-neutral-700">
          2. Premissas deste caso
          {parametros?.setor && (
            <span className="ml-2 font-normal text-neutral-500">
              — sugeridas para {SETORES.find(([v]) => v === parametros.setor)?.[1] ?? humanizar(parametros.setor)}
            </span>
          )}
        </h2>
        <p className="mb-3 text-xs text-neutral-500">
          O setor <strong>sugere</strong>, não restringe: a lista traz a base comum mais as do setor,
          e qualquer premissa ativada aqui pode ser usada em qualquer linha. Ano em branco fica{" "}
          <strong>em branco</strong> — não vira zero, porque projetar com zero é o erro que não se
          denuncia. Premissa <strong>macro</strong> ativada sem valor puxa a expectativa do Focus que
          está no banco, com a origem declarada.
        </p>

        {/* A CURVA DE SAZONALIDADE não é digitada: ela é derivada do faturamento
            mensal que o próprio mandato entregou (0040). Mostrá-la aqui é o que
            permite ao analista discordar dela — e, quando ela não existe, saber
            por quê antes de abrir o arquivo. */}
        <div className="mb-4 rounded border border-neutral-200 bg-neutral-50 p-2 text-xs">
          <p className="font-medium text-neutral-700">Curva de sazonalidade deste caso</p>
          {curva.length === 12 ? (
            <>
              <div className="mt-1 flex flex-wrap gap-1">
                {curva.map((c) => (
                  <span key={c.mes} className="rounded bg-white px-1.5 py-0.5 tabular-nums text-neutral-700">
                    {MESES[c.mes - 1]} {(c.fracao * 100).toFixed(1)}%
                  </span>
                ))}
              </div>
              <p className="mt-1 text-neutral-500">
                Derivada do faturamento mensal do próprio caso — nada digitado. É ela que reparte o
                valor anual das linhas com sazonalidade vinculada.
              </p>
            </>
          ) : (
            <p className="mt-1 text-neutral-600">
              Sem curva: o caso não tem série mensal completa de faturamento (12 meses). As linhas
              ficam <strong>sem distribuição mensal</strong> e o arquivo diz isso — ratear 1/12 seria
              inventar um número que ninguém escolheu, e move caixa de dezembro para março.
            </p>
          )}
        </div>

        {/* CABEÇALHO DE ANOS — o horizonte fica ESCRITO, não insinuado.
            Antes o ano só aparecia como `placeholder` dentro da caixa: texto
            cinza que some no instante em que se digita o primeiro caractere.
            Quem preenchia a terceira caixa de uma premissa não tinha mais como
            saber se estava em 2028 ou 2029 — e premissa no ano errado não dá
            erro nenhum, só projeta diferente. O ano agora é rótulo fixo em cima
            da coluna, alinhado com as caixas, e continua no `placeholder` e no
            `title` para quem navega por teclado. */}
        <div className="flex flex-wrap items-center gap-2 px-2 pb-1 text-xs text-neutral-500">
          <span className="min-w-56 flex-1">
            Horizonte de projeção — <strong className="text-neutral-700">{anos.length} anos</strong>,
            de {anos[0]} a {anos[anos.length - 1]}, derivados do último exercício realizado
            ({ultimoReal}). Mudar em <em>1. Parâmetros do mandato</em>.
          </span>
          {anos.map((ano) => (
            <span key={ano} className="w-16 text-center font-semibold tabular-nums text-neutral-700">
              {ano}
            </span>
          ))}
          {/* Espelha a largura do botão da linha para os anos ficarem sobre as caixas. */}
          <span aria-hidden className="invisible px-2 py-0.5 text-xs">Atualizar</span>
        </div>

        <div className="space-y-4">
          {[...porNatureza.entries()].map(([natureza, lista]) => (
            <div key={natureza}>
              <h3 className="mb-1 text-xs font-semibold uppercase text-neutral-500">
                {NATUREZA_LABEL[natureza] ?? humanizar(natureza)}
              </h3>
              <div className="space-y-1">
                {lista.map((p) => {
                  const ativa = ativasPorCodigo.get(p.codigo);
                  return (
                    <FormPremissa key={p.codigo} casoId={id} codigo={p.codigo} ativa={!!ativa}>
                      <span className="min-w-56 flex-1" title={p.descricao ?? undefined}>
                        {p.nome}
                        {p.unidade && <span className="ml-1 text-neutral-500">({p.unidade})</span>}
                        {p.setores.length > 0 && (
                          <span className="ml-1 rounded bg-indigo-100 px-1 text-[10px] text-indigo-800">
                            setor
                          </span>
                        )}
                        {ativa?.origem === "focus" && (
                          <span className="ml-1 rounded bg-emerald-100 px-1 text-[10px] text-emerald-800">
                            Focus
                          </span>
                        )}
                      </span>
                      {/* O ANO FICA ESCRITO EM CIMA DA CAIXA, em preto.
                          Ele era o `placeholder` — cinza claro, e some no primeiro
                          caractere digitado. O dono leu isso como "tenho que
                          selecionar o ano em cada premissa", que é justamente o
                          trabalho que a tela existe para não dar: o horizonte já
                          vem dos parâmetros do mandato e é o mesmo para todas.
                          Agora o ano é rótulo fixo, e o `placeholder` passa a
                          dizer a UNIDADE, que é o que a caixa realmente pede. */}
                      {anos.map((ano) => (
                        <label key={ano} className="flex w-16 flex-col items-center">
                          <span className="text-[10px] font-semibold leading-none text-neutral-700 tabular-nums">
                            {ano}
                          </span>
                          <input
                            type="text" name={`valor_${ano}`}
                            defaultValue={ativa?.valores?.[String(ano)] ?? ""}
                            placeholder={p.unidade ?? "valor"}
                            title={`${p.nome} — ${ano}${p.unidade ? ` (${p.unidade})` : ""}`}
                            className="mt-0.5 w-16 rounded border border-neutral-300 px-1 py-0.5 text-right text-xs"
                          />
                        </label>
                      ))}
                    </FormPremissa>
                  );
                })}
              </div>
            </div>
          ))}
        </div>
      </section>

      {/* 3. LINHAS × PREMISSAS */}
      <section className="rounded border border-neutral-200 bg-white p-4">
        <h2 className="mb-1 text-sm font-semibold text-neutral-700">3. Linhas × premissas</h2>
        <p className="mb-3 text-xs text-neutral-500">
          Cada <strong>conta</strong> pode ter a sua premissa. O <strong>aplicar em lote</strong>{" "}
          resolve a maioria dos casos de uma vez (todas as contas de receita → crescimento real);
          depois é só ajustar as exceções e salvar a seção inteira de uma vez. Linha sem premissa não
          é projetada — e isso é escolha legítima, que o arquivo declara.
        </p>

        {/* Busca por rótulo: com 236 linhas, achar "Fornecedores nacionais" rolando
            a página é o que faz o analista desistir de ajustar a exceção. */}
        <form method="get" className="mb-3 flex items-center gap-2 text-sm">
          <input
            type="text" name="q" defaultValue={busca} placeholder="filtrar por rótulo…"
            className="w-64 rounded border border-neutral-300 px-2 py-1 text-xs"
          />
          <button type="submit" className="rounded border border-neutral-300 px-2 py-1 text-xs hover:bg-neutral-100">
            filtrar
          </button>
          {busca && (
            <Link href={`/casos/${id}/modelagem`} className="text-xs text-neutral-500 hover:underline">
              limpar filtro ({todasLinhas.length} linhas no total)
            </Link>
          )}
        </form>

        {ativas.length === 0 ? (
          <p className="rounded border border-amber-300 bg-amber-50 p-2 text-sm text-amber-900">
            Ative pelo menos uma premissa no passo 2 antes de vincular linhas. Vincular linha a
            premissa não ativada é recusado no banco, de propósito: a linha sairia
            &quot;projetada&quot; por uma premissa vazia.
          </p>
        ) : (
          <div className="space-y-5">
            {[...linhasPorSecao.entries()].sort().map(([secao, linhas]) => (
              <SecaoLinhas
                key={secao}
                casoId={id}
                secao={secao}
                // A CHAVE canônica continua sendo `secao` (é ela que o formulário manda
                // ao banco); o que a tela mostra é o rótulo em português. Misturar os
                // dois foi o defeito: `passivo_nao_circulante` num cabeçalho de seção.
                rotulo={rotuloDaSecao(secao === "(sem seção canônica)" ? null : secao)}
                linhas={linhas}
                ativas={ativas.map((a) => ({
                  codigo: a.premissa_codigo,
                  nome: nomeDaPremissa.get(a.premissa_codigo) ?? a.premissa_codigo,
                }))}
                sazonais={premissasSazonais.map((a) => ({
                  codigo: a.premissa_codigo,
                  nome: nomeDaPremissa.get(a.premissa_codigo) ?? a.premissa_codigo,
                }))}
                vinculos={Object.fromEntries(linhas.map((l) => [l.rotulo_norm, {
                  premissa: vinculoDaLinha.get(chaveDaLinha(l.secao_canonica, l.rotulo_norm))
                    ?.premissa_codigo ?? "",
                  sazonalidade: vinculoDaLinha.get(chaveDaLinha(l.secao_canonica, l.rotulo_norm))
                    ?.sazonalidade_codigo ?? "",
                }]))}
              />
            ))}
            {linhasPorSecao.size === 0 && (
              <p className="text-sm text-neutral-500">
                {busca
                  ? `Nenhuma linha com "${busca}" no rótulo.`
                  : falhas.length > 0
                    // A afirmação só pode ser feita quando a pergunta foi
                    // respondida. Com a consulta falhando, dizer "não tem linha"
                    // é inventar um fato sobre o caso.
                    ? "A consulta das linhas FALHOU (veja o aviso vermelho no topo). Isto NÃO quer dizer que o caso está vazio."
                    : "Este caso ainda não tem linha extraída com valor. Confira a fila de revisão e o export de dados."}
              </p>
            )}
          </div>
        )}
      </section>
    </main>
  );
}
