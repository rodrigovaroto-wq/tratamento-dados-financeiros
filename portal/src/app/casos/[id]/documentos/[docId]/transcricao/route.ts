import { NextResponse } from "next/server";
import { createClient } from "@/lib/supabase/server";
import { nomeArquivoSanitizado } from "@/lib/export";
import {
  montarPlanilhaTranscricao,
  type LinhaExigidaParaTranscrever,
} from "@/lib/transcricao";

// exceljs usa Buffer/streams do Node — precisa do runtime Node, não Edge. Mesma
// razão da rota de export.
export const runtime = "nodejs";

// A PLANILHA DE TRANSCRIÇÃO, baixada deste documento.
//
// POR QUE UMA ROTA E NÃO UMA SERVER ACTION. Server action devolve dado para o
// React; o que se quer aqui é um ARQUIVO na pasta de Downloads. É o mesmo motivo
// pelo qual o export é rota, e a planilha reusa exatamente o padrão de resposta
// dela (Content-Type do .xlsx + Content-Disposition attachment).
//
// POR QUE A ROTA PRECISA EXISTIR POR DOCUMENTO. A planilha carrega o id do
// documento numa célula, e é esse id que `lerPlanilhaTranscricao` confere na
// importação. Uma planilha genérica, baixada de um lugar só, não teria como ser
// conferida — e a transcrição do balanço da Alfa poderia entrar na Beta.
export async function GET(
  _request: Request,
  { params }: { params: Promise<{ id: string; docId: string }> },
) {
  const { id, docId } = await params;
  const supabase = await createClient();

  const docRes = await supabase
    .from("documento")
    .select(
      `id, tipo_taxonomia,
       entidade:entidade_id(razao_social), periodo:periodo_id(tipo, referencia),
       documento_versao(nome_original, n_versao)`,
    )
    .eq("caso_id", id)
    .eq("id", docId)
    .single();

  if (docRes.error || !docRes.data) {
    return NextResponse.json({ error: "Documento não encontrado." }, { status: 404 });
  }

  const doc = docRes.data as unknown as {
    id: string;
    tipo_taxonomia: string | null;
    entidade: { razao_social: string } | null;
    periodo: { tipo: string; referencia: string } | null;
    documento_versao: { nome_original: string | null; n_versao: number }[] | null;
  };

  // A versão mais recente é a que dá o nome do arquivo — a mesma que a 0129 usa
  // como referência ao gravar a transcrição.
  const versao = [...(doc.documento_versao ?? [])].sort((a, b) => b.n_versao - a.n_versao)[0];

  // AS LINHAS QUE O PORTÃO 1 VAI COBRAR. Se esta chamada falhar, a planilha sai
  // sem elas — e isso é PIOR do que parece: quem preenche não teria como saber
  // quais linhas o sistema exige, e o documento voltaria incompleto depois de
  // alguém já ter digitado tudo à mão. Então a falha é dita, não engolida.
  const exigidasRes = await supabase.rpc("fn_linhas_para_transcrever", {
    p_documento_id: docId,
  });
  if (exigidasRes.error) {
    return NextResponse.json(
      {
        error:
          "Não consegui listar as linhas exigidas deste tipo de documento: " +
          `${exigidasRes.error.message}. A planilha sairia sem elas, e quem transcrevesse ` +
          "não saberia o que o sistema vai cobrar.",
      },
      { status: 500 },
    );
  }

  const workbook = montarPlanilhaTranscricao({
    documentoId: doc.id,
    nomeArquivo: versao?.nome_original ?? "(sem nome)",
    tipoTaxonomia: doc.tipo_taxonomia,
    entidade: doc.entidade?.razao_social ?? null,
    periodo: doc.periodo ? `${doc.periodo.tipo} ${doc.periodo.referencia}` : null,
    exigidas: (exigidasRes.data as LinhaExigidaParaTranscrever[] | null) ?? [],
  });

  const buffer = await workbook.xlsx.writeBuffer();

  // O NOME DO ARQUIVO DIZ O QUE ELE É e de qual documento veio. Quem transcreve
  // costuma ter vários abertos, e "transcricao.xlsx" repetido na pasta de
  // Downloads é exatamente o caminho para enviar a planilha errada — o erro que a
  // conferência do id existe para pegar. O nome evita o encontro com a guarda.
  const base = nomeArquivoSanitizado(versao?.nome_original ?? "documento");
  const filename = `transcricao-${base}-${docId.slice(0, 8)}.xlsx`;

  return new NextResponse(buffer as unknown as BodyInit, {
    headers: {
      "Content-Type": "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
      "Content-Disposition": `attachment; filename="${filename}"`,
    },
  });
}
