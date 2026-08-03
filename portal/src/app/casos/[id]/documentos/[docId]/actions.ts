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

  const { data, error } = await supabase.rpc("fn_aceitar_extracao", {
    p_documento_versao_id: documentoVersaoId,
    p_autor: user?.email ?? "portal:desconhecido",
    p_motivo: motivo,
  });

  if (error) {
    throw new Error(`Falha ao aceitar extração: ${error.message}`);
  }

  // RECUSA (db/migrations/0036): a função devolve `recusado: true` quando a versão
  // não tem NENHUMA linha extraída — aceitar ali gravaria uma aprovação formal de
  // nada numa tabela append-only. A recusa vem no payload, e não como erro de
  // Postgres, porque exceção em plpgsql desfaria o registro da própria tentativa
  // em `evento_auditoria` (ver o comentário na migration).
  //
  // Ler este campo é OBRIGATÓRIO aqui: sem isto, o `error` nulo faria a recusa
  // passar por sucesso e a tela recarregaria como se algo tivesse sido aceito —
  // trocar um "aceite de nada" por um "sucesso de nada" não seria correção
  // nenhuma.
  const resultado = data as { recusado?: boolean; motivo_recusa?: string } | null;
  if (resultado?.recusado) {
    throw new Error(resultado.motivo_recusa ?? "Aceite recusado: versão sem linhas extraídas.");
  }

  revalidatePath(`/casos/${casoId}/documentos/${docId}`);
  revalidatePath(`/casos/${casoId}`);
}
