"use server";

import { revalidatePath } from "next/cache";
import { createClient } from "@/lib/supabase/server";

// As ações da seção Modelagem (db/migrations/0038).
//
// TODA a regra vive no Postgres — este arquivo só encaminha e mostra o resultado.
// Não é preferência de estilo: `fn_aplicar_premissa_em_lote` precisa das linhas de
// `campo_extraido` para saber quais existem, e `fn_vincular_linha_premissa` recusa
// premissa que o caso não ativou. Reimplementar qualquer uma dessas duas coisas
// aqui criaria uma segunda verdade sobre a mesma pergunta.
//
// PADRÃO DE RECUSA (0036/0037/0038): as funções devolvem `recusado: true` no
// payload em vez de levantar exceção — exceção em plpgsql desfaz o registro da
// própria tentativa. Ler esse campo é OBRIGATÓRIO em cada ação: sem isso, `error`
// nulo faria a recusa passar por sucesso, e a tela recarregaria como se algo
// tivesse sido salvo.

type Recusavel = { recusado?: boolean; motivo_recusa?: string } | null;

async function autor() {
  const supabase = await createClient();
  const { data: { user } } = await supabase.auth.getUser();
  return user?.email ?? "portal:desconhecido";
}

function conferirRecusa(data: unknown, fallback: string) {
  const r = data as Recusavel;
  if (r?.recusado) throw new Error(r.motivo_recusa ?? fallback);
}

export async function definirParametros(casoId: string, formData: FormData) {
  const supabase = await createClient();
  const ultimo = Number(formData.get("ultimo_exercicio_real"));
  const { data, error } = await supabase.rpc("fn_definir_modelagem", {
    p_caso_id: casoId,
    p_entidade: String(formData.get("entidade") || "").trim() || null,
    p_ultimo_exercicio_real: Number.isFinite(ultimo) && ultimo > 0 ? ultimo : null,
    p_indice_macro: String(formData.get("indice_macro") || "").trim() || null,
    p_setor: String(formData.get("setor") || "").trim() || null,
    p_autor: await autor(),
    p_anos_projetados: Number(formData.get("anos_projetados")) || 5,
  });
  if (error) throw new Error(`Falha ao salvar os parâmetros: ${error.message}`);
  conferirRecusa(data, "Parâmetros recusados.");
  revalidatePath(`/casos/${casoId}/modelagem`);
}

export async function ativarPremissa(casoId: string, formData: FormData) {
  const supabase = await createClient();
  const codigo = String(formData.get("codigo") || "");

  // Valores por ano vêm como campos `valor_2026`, `valor_2027`… O ano SEM valor
  // fica FORA do jsonb de propósito: ausência é ausência, e a 0038 trata premissa
  // sem valor como "não projeta aquele ano" em vez de projetar com zero. Escrever
  // 0 aqui seria inventar a premissa mais perigosa que existe.
  const valores: Record<string, number> = {};
  for (const [k, v] of formData.entries()) {
    if (!k.startsWith("valor_")) continue;
    const texto = String(v).trim().replace(",", ".");
    if (texto === "") continue;
    const n = Number(texto);
    if (Number.isFinite(n)) valores[k.slice("valor_".length)] = n;
  }

  const { data, error } = await supabase.rpc("fn_ativar_premissa", {
    p_caso_id: casoId,
    p_codigo: codigo,
    p_valores: valores,
    p_origem: String(formData.get("origem") || "digitado"),
    p_autor: await autor(),
  });
  if (error) throw new Error(`Falha ao ativar a premissa: ${error.message}`);
  conferirRecusa(data, "Premissa recusada.");
  revalidatePath(`/casos/${casoId}/modelagem`);
}

export async function vincularLinha(casoId: string, formData: FormData) {
  const supabase = await createClient();
  const premissa = String(formData.get("premissa") || "");
  const { data, error } = await supabase.rpc("fn_vincular_linha_premissa", {
    p_caso_id: casoId,
    p_secao_canonica: String(formData.get("secao_canonica") || "") || null,
    p_rotulo: String(formData.get("rotulo") || ""),
    p_entidade: String(formData.get("entidade") || "") || null,
    // Vazio = desvincular. Linha sem premissa não é projetada, e o arquivo diz
    // isso — é escolha legítima, não estado incompleto.
    p_premissa: premissa || null,
    p_autor: await autor(),
    p_sazonalidade: String(formData.get("sazonalidade") || "") || null,
  });
  if (error) throw new Error(`Falha ao vincular a linha: ${error.message}`);
  conferirRecusa(data, "Vínculo recusado.");
  revalidatePath(`/casos/${casoId}/modelagem`);
}

// Salvar a seção inteira de uma vez.
//
// POR QUE ISTO EXISTE: no v35 a tela listou 236 linhas, cada uma com o seu botão
// `salvar`. Configurar as exceções depois do lote significava 236 idas ao
// servidor, uma por clique — e trabalho que dá 236 cliques é trabalho que não se
// faz. Aqui cada seção é UM formulário e UMA submissão.
//
// Só chama o banco para a linha que MUDOU (`orig__i` traz o valor que a tela
// carregou). Reenviar as 45 linhas de uma seção a cada salvamento gravaria
// `caso_linha_premissa` para linha que ninguém tocou — inclusive para a linha
// deliberadamente "não projetar" —, e a trilha de decisão passaria a registrar
// escolhas que o analista não fez.
export async function salvarSecao(casoId: string, formData: FormData) {
  const supabase = await createClient();
  const autorNome = await autor();

  const indices = new Set<string>();
  for (const k of formData.keys()) {
    const m = k.match(/^(?:premissa|sazonalidade|rotulo|entidade|orig|origSaz)__(\d+)$/);
    if (m) indices.add(m[1]);
  }

  const erros: string[] = [];
  let n = 0;
  for (const i of [...indices].sort((a, b) => Number(a) - Number(b))) {
    const premissa = String(formData.get(`premissa__${i}`) ?? "");
    const sazonalidade = String(formData.get(`sazonalidade__${i}`) ?? "");
    const orig = String(formData.get(`orig__${i}`) ?? "");
    const origSaz = String(formData.get(`origSaz__${i}`) ?? "");
    if (premissa === orig && sazonalidade === origSaz) continue;

    const rotulo = String(formData.get(`rotulo__${i}`) ?? "");
    const { data, error } = await supabase.rpc("fn_vincular_linha_premissa", {
      p_caso_id: casoId,
      p_secao_canonica: String(formData.get("secao_canonica") || "") || null,
      p_rotulo: rotulo,
      p_entidade: String(formData.get(`entidade__${i}`) || "") || null,
      p_premissa: premissa || null,
      p_autor: autorNome,
      p_sazonalidade: sazonalidade || null,
    });
    if (error) { erros.push(`${rotulo}: ${error.message}`); continue; }
    // Recusa por linha NÃO aborta as outras: numa submissão de 45 linhas, parar
    // na primeira perderia as 44 decisões seguintes. Junta e relata.
    const r = data as Recusavel;
    if (r?.recusado) { erros.push(`${rotulo}: ${r.motivo_recusa ?? "recusado"}`); continue; }
    n++;
  }

  revalidatePath(`/casos/${casoId}/modelagem`);
  if (erros.length > 0) {
    throw new Error(
      `${n} linha(s) salva(s); ${erros.length} recusada(s):\n` + erros.slice(0, 8).join("\n"),
    );
  }
}

export async function aplicarEmLote(casoId: string, formData: FormData) {
  const supabase = await createClient();
  const { data, error } = await supabase.rpc("fn_aplicar_premissa_em_lote", {
    p_caso_id: casoId,
    p_secao_canonica: String(formData.get("secao_canonica") || ""),
    p_premissa: String(formData.get("premissa") || ""),
    p_autor: await autor(),
    p_sazonalidade: String(formData.get("sazonalidade") || "") || null,
  });
  if (error) throw new Error(`Falha ao aplicar em lote: ${error.message}`);
  conferirRecusa(data, "Lote recusado.");

  // Lote que pega ZERO linha não é erro, mas também não pode passar por sucesso:
  // significa que a seção escolhida não tem CONTA nenhuma neste caso (só subtotal,
  // série mensal ou indicador), e quem clicou precisa saber disso agora — não ao
  // abrir o Excel.
  const r = data as { n_linhas?: number; n_ignoradas?: number } | null;
  if (r && r.n_linhas === 0) {
    throw new Error(
      "O lote não vinculou NENHUMA linha nessa seção. "
      + (r.n_ignoradas
        ? `As ${r.n_ignoradas} linha(s) da seção não são contas projetáveis (subtotal, série mensal `
          + "ou indicador derivado) — subtotal sai como soma dos componentes no Excel, e por isso "
          + "não recebe premissa."
        : "Confira a seção escolhida na lista de linhas abaixo."),
    );
  }
  revalidatePath(`/casos/${casoId}/modelagem`);
}
