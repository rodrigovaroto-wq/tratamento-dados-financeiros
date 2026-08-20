import Link from "next/link";
import { notFound } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { RotularDocumento } from "@/components/golden-rotular-documento";
import { RotularCampos } from "@/components/golden-rotular-campos";

// A TELA CEGA — a peça de que tudo isto depende.
//
// O QUE ELA NÃO CARREGA, e é a lista mais importante deste arquivo:
//   * `campo_extraido.valor_num` das linhas a rotular — vem de
//     `fn_golden_linhas_para_rotular`, que não devolve valor (0130);
//   * `documento.tipo_taxonomia` — o palpite de tipo da máquina;
//   * `entidade.razao_social` e `periodo` — os identificadores que a máquina
//     extraiu e que estão justamente sob medição;
//   * `documento.resumo` e `documento.justificativa` — a prosa que a IA escreveu
//     sobre o documento, que é o vazamento mais fácil de não notar: um resumo
//     dizendo "balanço da Alfa em 31/12/2024" entrega tipo, entidade e período de
//     uma vez.
//
// O que ela carrega é o NOME DO ARQUIVO, e só. É o mínimo para a pessoa saber
// qual documento abrir na outra janela — e nome de arquivo é o que o cliente
// escreveu, não o que a máquina concluiu.
//
// POR QUE ISSO IMPORTA MAIS QUE PARECE. Nada aqui quebra se o vazamento
// acontecer: a tela continua funcionando, os rótulos continuam sendo gravados, as
// métricas continuam saindo. Só param de medir alguma coisa. É o defeito mais
// barato de introduzir e o mais caro de descobrir deste sistema inteiro — quem
// acrescentar um campo a estas consultas, leia o parágrafo acima antes.

type Linha = {
  chave: string;
  secao: string | null;
  periodo_coluna: string | null;
  entidade_coluna: string | null;
  origem_pagina: number | null;
  unidade: string | null;
  ja_rotulada: boolean;
};

type Classe = { codigo: string; nome: string };

export default async function RotularPage({
  params,
}: {
  params: Promise<{ rodadaId: string; docId: string }>;
}) {
  const { rodadaId, docId } = await params;
  const supabase = await createClient();

  const { data: rodada } = await supabase
    .from("golden_rodada")
    .select("id, nome, congelada_em")
    .eq("id", rodadaId)
    .single();

  if (!rodada) notFound();

  const {
    data: { user },
  } = await supabase.auth.getUser();
  const rotulador = user?.email ?? null;

  // SÓ O NOME DO ARQUIVO. Ver o cabeçalho: nada de tipo, entidade, período ou
  // resumo — são exatamente as respostas que o rótulo vai julgar.
  const { data: docBruto } = await supabase
    .from("documento_versao")
    .select("nome_original, n_versao")
    .eq("documento_id", docId)
    .order("n_versao", { ascending: false })
    .limit(1);

  const nomeArquivo =
    (docBruto as { nome_original: string | null }[] | null)?.[0]?.nome_original ?? "(sem nome)";

  const [{ data: linhasBrutas }, { data: classesBrutas }, { data: meuRotulo }, { data: tipos }] =
    await Promise.all([
      supabase.rpc("fn_golden_linhas_para_rotular", {
        p_rodada: rodadaId,
        p_documento_id: docId,
        p_rotulador: rotulador,
      }),
      supabase
        .from("classe_contabil_catalogo")
        .select("codigo, nome")
        .eq("ativo", true)
        .order("ordem"),
      supabase
        .from("golden_rotulo")
        .select("id, tipo_correto, entidade_correta, periodo_correto, rotulado_em")
        .eq("rodada_id", rodadaId)
        .eq("documento_id", docId)
        .eq("rotulador", rotulador ?? "")
        .maybeSingle(),
      // O CATÁLOGO DE TIPOS não é vazamento: ele é a lista de opções possíveis, a
      // mesma para todo documento, e é o que impede o typo que viraria falso
      // negativo permanente. O que seria vazamento é dizer QUAL deles a máquina
      // escolheu — e isso não vem.
      supabase
        .from("taxonomia_tipo_documento")
        .select("codigo, documento, obrigatoriedade")
        .eq("ativo", true)
        .order("obrigatoriedade")
        .order("codigo"),
    ]);

  const linhas = (linhasBrutas as Linha[] | null) ?? [];
  const classes = (classesBrutas as Classe[] | null) ?? [];
  const congelada = (rodada as { congelada_em: string | null }).congelada_em !== null;

  return (
    <div className="space-y-6">
      <div>
        <Link href={`/autonomia/golden/${rodadaId}`} className="text-sm text-tinta-500 underline">
          ← {(rodada as { nome: string }).nome}
        </Link>
        <h1 className="mt-2 text-lg font-semibold">{nomeArquivo}</h1>
      </div>

      {/* O CONTRATO DA TELA, escrito para quem está rotulando. Sem isto, esconder
          a resposta da máquina parece falta de informação em vez de método — e a
          primeira reação de quem rotula é procurar onde está o palpite. */}
      <div className="rounded border border-tinta-300 bg-tinta-50 p-4 text-sm text-tinta-700">
        <p className="font-medium">Esta tela é cega de propósito.</p>
        <p className="mt-1">
          Você não vê o que a máquina extraiu — nem o tipo, nem a empresa, nem o período, nem os
          valores. Abra o documento e escreva o que <em>ele</em> diz. Se você visse a resposta da
          máquina, isto deixaria de ser um julgamento e viraria uma conferência, e conferência
          confirma o que é plausível. A métrica subiria sem nada ter melhorado, e o dial de
          autonomia subiria com ela — o sistema se aprovando.
        </p>
        <p className="mt-1 text-xs text-tinta-500">
          As <strong>rubricas</strong> abaixo vêm da extração, e só elas: são a chave que casa o
          seu número com o dela. Se você digitasse a rubrica com outra grafia, o par não casaria e
          a linha entraria como perda da máquina — um erro de datilografia cobrado dela.
        </p>
      </div>

      {congelada ? (
        <p className="rounded border border-amber-300 bg-amber-50 px-3 py-2 text-sm text-amber-900">
          Esta rodada está congelada e não aceita mais rótulo. Ampliar é rodada nova.
        </p>
      ) : !rotulador ? (
        <p className="rounded border border-red-300 bg-red-50 px-3 py-2 text-sm text-red-800">
          Não identifiquei quem está na sessão, e rótulo anônimo não participa de concordância
          nenhuma. Entre novamente.
        </p>
      ) : (
        <>
          <RotularDocumento
            rodadaId={rodadaId}
            docId={docId}
            tipos={(tipos as { codigo: string; documento: string }[] | null) ?? []}
            jaRotulado={meuRotulo != null}
          />
          <RotularCampos
            rodadaId={rodadaId}
            docId={docId}
            linhas={linhas}
            classes={classes}
          />
        </>
      )}
    </div>
  );
}
