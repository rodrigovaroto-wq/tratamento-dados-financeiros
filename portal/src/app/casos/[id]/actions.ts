"use server";

import { revalidatePath } from "next/cache";
import { createClient } from "@/lib/supabase/server";

// Chama fn_aprovar_caso (db/migrations/0037) — o Portão 2 POR CASO, que até a
// 0037 não existia em código: `caso_status` tinha 'aprovado' e nada transicionava
// para lá, e `pendencia.sobrepujavel` era gravado sem nenhum leitor.
//
// A regra é determinística e vive no Postgres (f0/04): nenhuma bloqueante em
// aberto, nenhuma não-sobrepujável viva, ressalvas ativas <= teto (3). Nada dela
// é reimplementado aqui — este arquivo só encaminha e mostra o resultado.
export async function aprovarCaso(casoId: string, formData: FormData) {
  const supabase = await createClient();

  const motivo = String(formData.get("motivo") || "").trim() || null;

  const {
    data: { user },
  } = await supabase.auth.getUser();

  const { data, error } = await supabase.rpc("fn_aprovar_caso", {
    p_caso_id: casoId,
    p_autor: user?.email ?? "portal:desconhecido",
    p_motivo: motivo,
  });

  if (error) {
    throw new Error(`Falha ao aprovar o caso: ${error.message}`);
  }

  // RECUSA no payload, não como erro de Postgres — mesmo padrão da 0036, e pelo
  // mesmo motivo: exceção em plpgsql desfaria o registro da própria tentativa em
  // `evento_auditoria`, e "alguém tentou aprovar um caso bloqueado" é justamente
  // o que uma trilha de auditoria precisa guardar.
  //
  // Ler este campo é obrigatório: sem isto, `error` nulo faria a recusa passar
  // por sucesso e a tela recarregaria como se o caso tivesse sido aprovado.
  const r = data as { recusado?: boolean; motivo_recusa?: string } | null;
  if (r?.recusado) {
    throw new Error(r.motivo_recusa ?? "Aprovação recusada pelo Portão 2.");
  }

  revalidatePath(`/casos/${casoId}`);
}
