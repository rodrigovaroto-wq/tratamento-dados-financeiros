import { NextResponse } from "next/server";
import { createClient } from "@/lib/supabase/server";

// Consultado pelo portal (polling) depois de um upload, pra saber quando os
// arquivos enviados já passaram pela classificação E pela extração — não tem
// nenhum "flag de concluído" único no schema, então isto combina dois sinais:
//   1. `documento` criado para o caso (classificação terminou) desde o envio.
//   2. `evento_auditoria` do tipo `extracao_sombra` referenciando aquele
//      documento_versao (extração TENTOU rodar — sucesso ou falha; sempre
//      gravado por fn_registrar_campos_extraidos, ver db/migrations/0016).
// "Pronto" aqui significa "o pipeline terminou de tentar", não "sem erros" —
// pendências (se houver) continuam visíveis no dashboard do caso como sempre.
export const runtime = "nodejs";

export async function GET(request: Request) {
  const { searchParams } = new URL(request.url);
  const casoNome = searchParams.get("caso")?.trim();
  const desde = searchParams.get("desde");
  const esperados = Number(searchParams.get("esperados") ?? "0");

  if (!casoNome || !desde || !Number.isFinite(esperados) || esperados <= 0) {
    return NextResponse.json({ error: "Parâmetros inválidos (caso, desde, esperados)." }, { status: 400 });
  }

  const supabase = await createClient();

  const { data: caso, error: casoErr } = await supabase
    .from("caso")
    .select("id")
    .eq("nome", casoNome)
    .maybeSingle();

  if (casoErr) {
    return NextResponse.json({ error: casoErr.message }, { status: 500 });
  }
  if (!caso) {
    // Ainda nem o `caso` foi criado — normal logo após o envio.
    return NextResponse.json({ classificados: 0, processados: 0, esperados, pronto: false });
  }

  const { data: documentos, error: docErr } = await supabase
    .from("documento")
    .select("id, documento_versao(id)")
    .eq("caso_id", caso.id)
    .gte("criado_em", desde);

  if (docErr) {
    return NextResponse.json({ error: docErr.message }, { status: 500 });
  }

  const docs = (documentos as unknown as Array<{ id: string; documento_versao: { id: string }[] }>) ?? [];
  const classificados = docs.length;
  const versaoIds = docs.flatMap((d) => (d.documento_versao ?? []).map((v) => v.id));

  let processados = 0;
  if (versaoIds.length > 0) {
    const refs = versaoIds.map((id) => `documento_versao:${id}`);
    const { data: eventos, error: evtErr } = await supabase
      .from("evento_auditoria")
      .select("entidade_ref")
      .eq("acao", "extracao_sombra")
      .gte("criado_em", desde)
      .in("entidade_ref", refs);

    if (evtErr) {
      return NextResponse.json({ error: evtErr.message }, { status: 500 });
    }
    processados = new Set((eventos ?? []).map((e) => e.entidade_ref)).size;
  }

  const pronto = classificados >= esperados && processados >= esperados;
  return NextResponse.json({ classificados, processados, esperados, pronto });
}
