import { NextResponse } from "next/server";
import { createClient } from "@/lib/supabase/server";
import { buildExportWorkbook, nomeArquivoSanitizado, type DocumentoParaExport, type TaxonomiaParaExport } from "@/lib/export";
import type { CampoExtraido } from "@/lib/types";

// exceljs (usado em lib/export.ts) usa Buffer/streams do Node — precisa do
// runtime Node, não Edge.
export const runtime = "nodejs";

export async function GET(_request: Request, { params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  const supabase = await createClient();

  const [casoRes, taxonomiaRes, documentosRes] = await Promise.all([
    supabase.from("caso").select("id, nome, produto").eq("id", id).single(),
    supabase.from("taxonomia_tipo_documento").select("codigo, documento, versao"),
    supabase
      .from("documento")
      .select(
        `id, tipo_taxonomia,
         entidade:entidade_id(razao_social), periodo:periodo_id(tipo, referencia),
         documento_versao(id, nome_original)`,
      )
      .eq("caso_id", id),
  ]);

  if (casoRes.error || !casoRes.data) {
    return NextResponse.json({ error: "Caso não encontrado." }, { status: 404 });
  }

  const caso = casoRes.data;
  const taxonomia = (taxonomiaRes.data as TaxonomiaParaExport[] | null) ?? [];
  const documentos = (documentosRes.data as unknown as DocumentoParaExport[] | null) ?? [];

  const versaoIds = documentos.flatMap((doc) => (doc.documento_versao ?? []).map((v) => v.id));
  const camposRes = versaoIds.length
    ? await supabase
        .from("campo_extraido")
        .select(
          "id, documento_versao_id, secao, secao_canonica, chave, valor_texto, valor_num, unidade, confianca, origem_pagina, status_aceite, aceito_por, aceito_em",
        )
        .in("documento_versao_id", versaoIds)
    : { data: [] as CampoExtraido[], error: null };

  const campos = (camposRes.data as CampoExtraido[] | null) ?? [];

  const workbook = buildExportWorkbook({ caso, taxonomia, documentos, campos });
  const buffer = await workbook.xlsx.writeBuffer();
  const filename = `${nomeArquivoSanitizado(caso.nome)}-export-${new Date().toISOString().slice(0, 10)}.xlsx`;

  return new NextResponse(buffer as unknown as BodyInit, {
    headers: {
      "Content-Type": "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
      "Content-Disposition": `attachment; filename="${filename}"`,
    },
  });
}
