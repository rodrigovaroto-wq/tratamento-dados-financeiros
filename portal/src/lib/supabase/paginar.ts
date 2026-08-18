/**
 * TODAS as linhas de uma consulta, e não as primeiras mil.
 *
 * O DEFEITO QUE ISTO EXISTE PARA IMPEDIR, e ele já apareceu em produção: o
 * PostgREST do Supabase devolve no máximo `db-max-rows` linhas por consulta —
 * **1000 por padrão** — e corta acima disso **em silêncio, sem erro nenhum**.
 * O painel mostrava exatamente "1.000 linhas extraídas" com muito mais que
 * isso no banco; quem notou foi o dono, pela redondeza do número. Aquele caso
 * virou um `count` exato (contar não precisa de linha nenhuma), mas nem toda
 * consulta pode: a lista de documentos alimenta o tempo médio POR MANDATO e a
 * de pendências alimenta a fila — as duas precisam das LINHAS.
 *
 * Para essas, a saída é pedir de mil em mil até a página vir incompleta. É
 * mais de uma ida ao banco, e é o preço de um número correto.
 *
 * O TETO DE SEGURANÇA é deliberado e não é um detalhe: sem ele, uma consulta
 * mal filtrada varreria a tabela inteira e a tela penduraria sem dizer por quê.
 * Ao bater no teto, a função DECLARA (`truncado: true`) em vez de devolver o
 * pedaço como se fosse o todo — que é justamente o defeito original, só que com
 * um número maior. Quem chama decide o que fazer com a declaração; o que não
 * pode é ninguém ficar sabendo.
 */
const PAGINA = 1000;
const MAX_PAGINAS = 50; // 50 mil linhas — muito além da mesa, e ainda assim finito

export interface Pagina<T> {
  data: T[];
  error: { message: string } | null;
  /** true quando o teto de segurança interrompeu a leitura antes do fim */
  truncado: boolean;
}

export async function paginar<T>(
  consulta: (de: number, ate: number) => PromiseLike<{ data: unknown; error: { message: string } | null }>,
): Promise<Pagina<T>> {
  const tudo: T[] = [];
  for (let p = 0; p < MAX_PAGINAS; p++) {
    const de = p * PAGINA;
    const { data, error } = await consulta(de, de + PAGINA - 1);
    if (error) return { data: tudo, error, truncado: false };
    const lote = (data as T[] | null) ?? [];
    tudo.push(...lote);
    // Página incompleta = acabou. É o único sinal confiável: o PostgREST não
    // diz "tem mais", e pedir um `count` junto custaria um COUNT(*) por página.
    if (lote.length < PAGINA) return { data: tudo, error: null, truncado: false };
  }
  return { data: tudo, error: null, truncado: true };
}
