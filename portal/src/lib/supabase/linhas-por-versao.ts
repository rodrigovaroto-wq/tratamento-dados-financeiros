import { paginar } from "./paginar";
import type { createClient } from "./server";

/**
 * Quantas linhas de `campo_extraido` cada versão de documento rendeu.
 *
 * UMA função, não duas cópias. Até 24/09/2026 esta conta morava inline no
 * painel (`casos/page.tsx`) e no detalhe do caso (`casos/[id]/page.tsx`), e as
 * duas já tinham divergido: o detalhe passava por `paginar`, o painel fazia uma
 * consulta só — e o PostgREST corta em 1000 linhas **sem erro nenhum**. As dez
 * linhas de "O que chegou" podiam mostrar a contagem do documento truncada, que
 * é o defeito que `paginar.ts` existe para impedir e que o próprio painel já
 * tinha corrigido para o total. `verificar-linhas-por-versao.mts` prova, contra
 * um servidor que corta em 1000, que a contagem passa do teto.
 *
 * O `.order("id")` não é enfeite: sem ordem estável, duas janelas de `range`
 * podem devolver a mesma linha duas vezes e pular outra.
 */
type Supabase = Awaited<ReturnType<typeof createClient>>;

export async function contarLinhasPorVersao(
  supabase: Supabase,
  versoes: string[],
): Promise<{ porVersao: Map<string, number>; truncado: boolean }> {
  const porVersao = new Map<string, number>();
  if (versoes.length === 0) return { porVersao, truncado: false };
  const { data, truncado } = await paginar<{ documento_versao_id: string }>((de, ate) =>
    supabase.from("campo_extraido").select("documento_versao_id")
      .in("documento_versao_id", versoes).order("id", { ascending: true }).range(de, ate));
  for (const l of data) porVersao.set(l.documento_versao_id, (porVersao.get(l.documento_versao_id) ?? 0) + 1);
  return { porVersao, truncado };
}
