"use server";

import { revalidatePath } from "next/cache";
import { createClient } from "@/lib/supabase/server";

// As ações da rotulagem do golden set (db/migrations/0130).
//
// TODAS DEVOLVEM A RECUSA em vez de lançar, e aqui isso não é estilo: o texto das
// recusas da 0130 é o produto. "Esta rodada está congelada — ampliar é rodada
// nova" é a instrução que a pessoa precisa ler; um throw viraria digest opaco em
// produção (o Next redige erro de server action) e ela ficaria sem saber o que
// fazer. Mesmo raciocínio da importação da transcrição.
//
// O AUTOR VEM DA SESSÃO, sempre, e nunca de um campo de texto. O rotulador é a
// chave de `golden_rotulo` — é ele que faz a concordância inter-avaliador existir
// — e um campo digitável permitiria, sem querer, dois rótulos "independentes" da
// mesma pessoa com dois nomes diferentes: concordância perfeita medida contra si
// mesma, que é o pior número que este sistema pode produzir.

export type Resultado = { ok: true; dado: Record<string, unknown> } | { ok: false; erro: string };

async function autor(): Promise<string | null> {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  return user?.email ?? null;
}

const SEM_AUTOR =
  "Não identifiquei quem está na sessão. A 0130 recusa rodada, rótulo e congelamento sem autor: " +
  "o golden set é a evidência que autoriza subir autonomia, e evidência sem procedência não " +
  "autoriza nada. Entre novamente e repita a ação.";

// Envelopa a chamada: recusa retornada pelo banco, erro de transporte e sucesso
// entram todos na mesma forma, para a tela ter um só caminho de leitura.
async function chamar(fn: string, args: Record<string, unknown>): Promise<Resultado> {
  const supabase = await createClient();
  const { data, error } = await supabase.rpc(fn, args);
  if (error) return { ok: false, erro: `${fn}: ${error.message}` };
  const r = (data ?? {}) as Record<string, unknown>;
  if (r.recusado === true) {
    return { ok: false, erro: String(r.motivo_recusa ?? "Recusado.") };
  }
  return { ok: true, dado: r };
}

export async function abrirRodada(formData: FormData): Promise<Resultado> {
  const a = await autor();
  if (!a) return { ok: false, erro: SEM_AUTOR };
  const r = await chamar("fn_golden_abrir_rodada", {
    p_nome: String(formData.get("nome") || ""),
    p_autor: a,
    p_nota: String(formData.get("nota") || "").trim() || null,
  });
  revalidatePath("/autonomia/golden");
  revalidatePath("/autonomia");
  return r;
}

export async function incluirDocumento(
  rodadaId: string,
  formData: FormData,
): Promise<Resultado> {
  const a = await autor();
  if (!a) return { ok: false, erro: SEM_AUTOR };
  const r = await chamar("fn_golden_incluir_documento", {
    p_rodada: rodadaId,
    p_documento_id: String(formData.get("documento_id") || ""),
    p_estrato: String(formData.get("estrato") || "") || null,
    p_origem: String(formData.get("origem") || "") || null,
    p_autor: a,
  });
  revalidatePath(`/autonomia/golden/${rodadaId}`);
  return r;
}

export async function rotularDocumento(
  rodadaId: string,
  docId: string,
  formData: FormData,
): Promise<Resultado> {
  const a = await autor();
  if (!a) return { ok: false, erro: SEM_AUTOR };
  const txt = (k: string) => String(formData.get(k) || "").trim() || null;
  // `assinado` é tri-estado de propósito: "não olhei" não é "não está assinado".
  // A 0126 documenta que campo nulo entra como item NÃO MEDIDO e nunca como
  // acerto — um seletor booleano forçaria a pessoa a afirmar o que não viu.
  const assinado = txt("assinado_correto");
  const r = await chamar("fn_golden_rotular", {
    p_rodada: rodadaId,
    p_documento_id: docId,
    p_rotulador: a,
    p_tipo_correto: txt("tipo_correto"),
    p_entidade_correta: txt("entidade_correta"),
    p_periodo_correto: txt("periodo_correto"),
    p_assinado_correto: assinado === null ? null : assinado === "sim",
    p_legibilidade: txt("legibilidade"),
    p_item_checklist_correto: null,
    p_nota: txt("nota"),
  });
  revalidatePath(`/autonomia/golden/${rodadaId}/${docId}`);
  revalidatePath(`/autonomia/golden/${rodadaId}`);
  return r;
}

export async function rotularCampos(
  rodadaId: string,
  docId: string,
  formData: FormData,
): Promise<Resultado> {
  const a = await autor();
  if (!a) return { ok: false, erro: SEM_AUTOR };

  // As linhas chegam em campos indexados (`chave_0`, `valor_0`, …) porque o
  // formulário é uma TABELA: uma linha por rubrica que a máquina achou, mais as
  // livres. Montar o array aqui, no servidor, mantém a tela sem estado de dados.
  const linhas: Record<string, string | null>[] = [];
  for (const [k, v] of formData.entries()) {
    const m = /^chave_(\d+)$/.exec(k);
    if (!m) continue;
    const i = m[1];
    const chave = String(v).trim();
    const valor = String(formData.get(`valor_${i}`) ?? "").trim();
    // Linha em branco é ignorada em silêncio, e é o que faz a tabela poder ter
    // 40 rubricas com 12 preenchidas sem obrigar ninguém a apagar as outras.
    if (!chave || !valor) continue;
    linhas.push({
      chave,
      // pt-BR: vírgula é decimal e ponto é milhar. A mesma conversão da planilha
      // de transcrição, e pelo mesmo motivo — quem digita valor de balanço digita
      // "1.234,56", e parseFloat devolveria 1,234.
      valor_correto: normalizarNumero(valor),
      periodo_coluna: String(formData.get(`periodo_${i}`) ?? "").trim() || null,
      entidade_coluna: String(formData.get(`entidade_${i}`) ?? "").trim() || null,
      tolerancia: String(formData.get(`tolerancia_${i}`) ?? "").trim() || "0",
      classe_contabil_correta:
        String(formData.get(`classe_${i}`) ?? "").trim() || null,
    });
  }

  if (linhas.length === 0) {
    return {
      ok: false,
      erro:
        "Nenhuma linha preenchida. Rubrica sem valor é ignorada de propósito — é o que permite a " +
        "tabela ter 40 linhas e você rotular 12 — mas então não há nada para gravar.",
    };
  }

  const r = await chamar("fn_golden_rotular_campos", {
    p_rodada: rodadaId,
    p_documento_id: docId,
    p_rotulador: a,
    p_campos: linhas,
  });
  revalidatePath(`/autonomia/golden/${rodadaId}/${docId}`);
  revalidatePath(`/autonomia/golden/${rodadaId}`);
  return r;
}

export async function congelarRodada(rodadaId: string): Promise<Resultado> {
  const a = await autor();
  if (!a) return { ok: false, erro: SEM_AUTOR };
  const r = await chamar("fn_golden_congelar", { p_rodada: rodadaId, p_autor: a });
  revalidatePath(`/autonomia/golden/${rodadaId}`);
  revalidatePath("/autonomia/golden");
  revalidatePath("/autonomia");
  return r;
}

function normalizarNumero(s: string): string {
  let limpo = s.replace(/[()\s]/g, "").replace(/R\$/gi, "");
  const negativo = /^\(.*\)$/.test(s.trim());
  if (limpo.includes(",")) limpo = limpo.replace(/\./g, "").replace(",", ".");
  if (negativo && !limpo.startsWith("-")) limpo = `-${limpo}`;
  return limpo;
}
