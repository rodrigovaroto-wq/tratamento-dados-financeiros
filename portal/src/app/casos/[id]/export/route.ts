import { NextResponse } from "next/server";
import { createClient } from "@/lib/supabase/server";
import {
  ampliarNotasNoBuffer, buildExportWorkbook, nomeArquivoSanitizado,
  type DocumentoParaExport, type MacroAnual, type MacroExpectativa,
} from "@/lib/export";
import type { CampoExtraido } from "@/lib/types";

// exceljs (usado em lib/export.ts) usa Buffer/streams do Node — precisa do
// runtime Node, não Edge.
export const runtime = "nodejs";

export async function GET(_request: Request, { params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  const supabase = await createClient();

  const [casoRes, documentosRes] = await Promise.all([
    supabase.from("caso").select("id, nome, produto").eq("id", id).single(),
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
  const documentos = (documentosRes.data as unknown as DocumentoParaExport[] | null) ?? [];

  const versaoIds = documentos.flatMap((doc) => (doc.documento_versao ?? []).map((v) => v.id));
  const camposRes = versaoIds.length
    ? await supabase
        .from("campo_extraido")
        .select(
          "id, documento_versao_id, secao, secao_canonica, entidade_coluna, periodo_coluna, chave, valor_texto, valor_num, unidade, confianca, origem_pagina, status_aceite, aceito_por, aceito_em",
        )
        .in("documento_versao_id", versaoIds)
    : { data: [] as CampoExtraido[], error: null };

  const campos = (camposRes.data as CampoExtraido[] | null) ?? [];

  // Índices macro (db/migrations/0025). São do CASO nenhum — a série é a mesma
  // para todos os mandatos —, por isso vêm à parte e não filtram por caso.
  // Falha aqui NÃO derruba o export: sem macro o arquivo sai como sempre saiu,
  // só sem a aba Macro e com as premissas de inflação/juro zeradas. Um índice
  // indisponível não pode impedir alguém de baixar a planilha do mandato.
  const [anuaisRes, expRes] = await Promise.all([
    supabase.rpc("fn_indice_macro_anual", { p_desde_ano: new Date().getFullYear() - 11 }),
    supabase
      .from("indice_macro_expectativa")
      .select("serie, ano_ref, mediana, coletado_em")
      .gte("ano_ref", new Date().getFullYear() - 1)
      .order("coletado_em", { ascending: false }),
  ]);

  const anuais = (anuaisRes.data as MacroAnual[] | null) ?? [];
  // A API devolve todas as coletas; para o export vale a MAIS RECENTE de cada
  // (série, ano) — e como vem ordenado por coleta decrescente, o primeiro que
  // aparece já é o certo.
  const vistos = new Set<string>();
  const expectativas = ((expRes.data as MacroExpectativa[] | null) ?? []).filter((e) => {
    const k = `${e.serie}/${e.ano_ref}`;
    if (vistos.has(k)) return false;
    vistos.add(k);
    return true;
  });

  const nomes = Object.fromEntries(
    ((await supabase.from("indice_macro_serie").select("codigo, nome")).data ?? [])
      .map((s: { codigo: string; nome: string }) => [s.codigo, s.nome]),
  );

  const macro = anuais.length > 0 || expectativas.length > 0
    ? { anuais, expectativas, nomes }
    : undefined;

  const workbook = buildExportWorkbook({ caso, documentos, campos, macro });
  const buffer = await ampliarNotasNoBuffer(await workbook.xlsx.writeBuffer());
  const filename = `${nomeArquivoSanitizado(caso.nome)}-export-${new Date().toISOString().slice(0, 10)}.xlsx`;

  return new NextResponse(buffer as unknown as BodyInit, {
    headers: {
      "Content-Type": "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
      "Content-Disposition": `attachment; filename="${filename}"`,
    },
  });
}
