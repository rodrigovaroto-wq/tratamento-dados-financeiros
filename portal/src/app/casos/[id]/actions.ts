"use server";

import { revalidatePath } from "next/cache";
import { createClient } from "@/lib/supabase/server";
import { MOTIVO_REJEICAO_MIN, motivoDeRejeicaoValido } from "@/lib/pendencia";

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

// Chama fn_rejeitar_pendencia (db/migrations/0106) — o SEGUNDO lado do Portão 2.
//
// Até aqui o portal só sabia dizer sim: `aprovarCaso` é a única ação, e ela é
// justamente a que a regra proíbe enquanto houver pendência bloqueante viva. O
// caso travava, a tela explicava o motivo, e não havia ação que mudasse o motivo
// — o que sobrava era editar a tabela por fora, que é a mesma liberação sem
// rastro nenhum.
//
// A regra (motivo mínimo, estado terminal, contagem no portão) vive no Postgres.
// Aqui não se reimplementa nada: o piso do motivo é conferido antes só para o
// usuário saber ANTES de clicar, e o banco continua sendo quem decide.
export async function rejeitarPendencia(
  casoId: string,
  pendenciaId: string,
  formData: FormData,
) {
  const supabase = await createClient();

  const motivo = String(formData.get("motivo") || "");

  // Guarda de espelho, não de segurança: a autoridade é `fn_min_motivo_rejeicao`
  // e o `(0114)` prova que os dois números são o mesmo.
  if (!motivoDeRejeicaoValido(motivo)) {
    throw new Error(
      `Rejeitar uma pendência exige um motivo com pelo menos ${MOTIVO_REJEICAO_MIN} caracteres: `
      + "é a única ação que libera o Portão 2 sem teto, e quem ler o caso depois precisa saber "
      + "por que a pendência não procedia.",
    );
  }

  const {
    data: { user },
  } = await supabase.auth.getUser();

  const { data, error } = await supabase.rpc("fn_rejeitar_pendencia", {
    p_pendencia_id: pendenciaId,
    p_autor: user?.email ?? "portal:desconhecido",
    p_motivo: motivo,
  });

  if (error) {
    throw new Error(`Falha ao rejeitar a pendência: ${error.message}`);
  }

  // RECUSA no payload, não como erro de Postgres — mesmo padrão da 0036/0037, e
  // pelo mesmo motivo: exceção em plpgsql desfaria o registro da própria
  // tentativa, e "alguém tentou rejeitar sem justificar" é o que a trilha
  // precisa guardar. Ler este campo é obrigatório: sem isto, `error` nulo faria
  // a recusa passar por sucesso e a tela recarregaria como se a pendência
  // tivesse sido rejeitada.
  const r = data as { recusado?: boolean; motivo_recusa?: string } | null;
  if (r?.recusado) {
    throw new Error(r.motivo_recusa ?? "Rejeição recusada.");
  }

  revalidatePath(`/casos/${casoId}`);
}

// Chama fn_ressalvar_pendencia (db/migrations/0107) — o caminho que `f0/04`
// especificou na F0 e que nunca existiu em código.
//
// O card do Portão 2 fala do teto de 3 ressalvas desde a 0037, e até aqui
// NINGUÉM CONSEGUIA CRIAR UMA: o controle estava publicado sem existir. Ele
// exigia antes uma decisão — `f0/04` pede papel SÊNIOR, que não existia no
// schema —, e é por isso que a 0107 traz `usuario_papel` junto.
//
// As quatro exigências (sênior, motivo, expiração futura, teto) são cobradas no
// banco. Aqui não se reimplementa nenhuma: a tela só encaminha e mostra a recusa,
// que vem escrita para ser lida por gente.
export async function ressalvarPendencia(
  casoId: string,
  pendenciaId: string,
  formData: FormData,
) {
  const supabase = await createClient();

  const motivo = String(formData.get("motivo") || "");
  const expiraEm = String(formData.get("expira_em") || "").trim();

  if (!expiraEm) {
    throw new Error(
      "Ressalva exige data de expiração (f0/04): ressalva permanente é liberação com outro nome. "
      + "No vencimento a pendência volta a valer sozinha.",
    );
  }

  const {
    data: { user },
  } = await supabase.auth.getUser();

  const { data, error } = await supabase.rpc("fn_ressalvar_pendencia", {
    p_pendencia_id: pendenciaId,
    p_autor: user?.email ?? "portal:desconhecido",
    p_motivo: motivo,
    // O input de data devolve `YYYY-MM-DD`; o fim do dia é o que o usuário quer
    // dizer com "vale até dia 20" — às 00:00 a ressalva morreria no começo do dia
    // escolhido, um dia antes do esperado.
    p_expira_em: `${expiraEm}T23:59:59`,
  });

  if (error) {
    throw new Error(`Falha ao registrar a ressalva: ${error.message}`);
  }
  const r = data as { recusado?: boolean; motivo_recusa?: string } | null;
  if (r?.recusado) {
    throw new Error(r.motivo_recusa ?? "Ressalva recusada.");
  }

  revalidatePath(`/casos/${casoId}`);
}

// Chama fn_tratar_pendencia (db/migrations/0107) — "estou cuidando disto".
//
// É o estado mais comum do processo real e o que menos existia: quem pedia o
// documento de novo ao cliente não tinha onde registrar isso, e a pendência
// seguia idêntica a uma que ninguém tocou — o que leva a pedir duas vezes, que é
// como se perde credibilidade num mandato.
//
// NÃO libera o Portão 2, de propósito (f0/04 conta os três estados de tratamento
// como pendência viva). O valor é de processo, não de portão.
export async function tratarPendencia(
  casoId: string,
  pendenciaId: string,
  estado: "em_correcao_interna" | "reenviada_ao_cliente",
  formData: FormData,
) {
  const supabase = await createClient();

  const {
    data: { user },
  } = await supabase.auth.getUser();

  const { data, error } = await supabase.rpc("fn_tratar_pendencia", {
    p_pendencia_id: pendenciaId,
    p_autor: user?.email ?? "portal:desconhecido",
    p_estado: estado,
    p_motivo: String(formData.get("motivo") || "").trim() || null,
  });

  if (error) {
    throw new Error(`Falha ao registrar o tratamento: ${error.message}`);
  }
  const r = data as { recusado?: boolean; motivo_recusa?: string } | null;
  if (r?.recusado) {
    throw new Error(r.motivo_recusa ?? "Movimento recusado.");
  }

  revalidatePath(`/casos/${casoId}`);
}
