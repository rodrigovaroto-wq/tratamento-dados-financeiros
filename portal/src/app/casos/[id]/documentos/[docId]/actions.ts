"use server";

import { revalidatePath } from "next/cache";
import { createClient } from "@/lib/supabase/server";

// Chama fn_aceitar_extracao (db/migrations/0011_aceite_export_e4.sql) — o
// Portão 2 mínimo do E4 (f0/07_output_spec.md): humano aceita TODAS as linhas
// extraídas desta versão de documento de uma vez. Sem isso, nenhuma linha
// entra no export como fato (fica "pendente" — anti-ancoragem). A lógica
// (decisao + evento_auditoria) roda no Postgres, não aqui.
export async function aceitarExtracao(casoId: string, docId: string, formData: FormData) {
  const supabase = await createClient();

  const documentoVersaoId = String(formData.get("documento_versao_id") || "");
  const motivo = String(formData.get("motivo") || "").trim() || null;

  const {
    data: { user },
  } = await supabase.auth.getUser();

  const { error } = await supabase.rpc("fn_aceitar_extracao", {
    p_documento_versao_id: documentoVersaoId,
    p_autor: user?.email ?? "portal:desconhecido",
    p_motivo: motivo,
  });

  if (error) {
    throw new Error(`Falha ao aceitar extração: ${error.message}`);
  }

  revalidatePath(`/casos/${casoId}/documentos/${docId}`);
  revalidatePath(`/casos/${casoId}`);
}
