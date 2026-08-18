/**
 * TODAS as linhas de uma consulta — sem teto, e sem depender de um ajuste do
 * servidor para isso ser verdade.
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
 * Para essas, a saída é pedir em janelas até o banco não ter mais o que dar.
 * É mais de uma ida ao banco, e é o preço de um número correto.
 *
 * POR QUE A PARADA MUDOU (18/08/2026, a pedido do dono: "a lista não deve ser
 * restringida"). A versão anterior parava quando uma página vinha com MENOS
 * linhas do que a janela pedida — e essa regra só é correta enquanto a janela
 * (1000) couber no teto do servidor. Ela funcionava por coincidência: a janela
 * era exatamente o teto padrão. Baixar `db-max-rows` no painel do Supabase para
 * qualquer valor abaixo de 1000 fazia TODA página voltar curta, e a função
 * declarava "acabou" na primeira — silenciosamente, que é o defeito original de
 * volta, agora escondido dentro da própria defesa contra ele.
 *
 * Agora a leitura anda pelo número de linhas REALMENTE devolvidas e só termina
 * quando uma página volta VAZIA. Isso vale para qualquer teto do servidor —
 * alto, baixo ou removido — e custa, no pior caso, uma requisição a mais por
 * consulta (a que confirma o fim). É o preço de não depender de uma
 * configuração que mora fora do repositório.
 *
 * O TETO DE SEGURANÇA continua existindo e não é um detalhe: sem ele, uma
 * consulta mal filtrada varreria a tabela inteira e a tela penduraria sem dizer
 * por quê. Ele subiu de 50 mil para 500 mil linhas — muito além de qualquer
 * mandato — e continua DECLARANDO (`truncado: true`) em vez de devolver o
 * pedaço como se fosse o todo. Quem chama decide o que fazer com a declaração;
 * o que não pode é ninguém ficar sabendo.
 */
const PAGINA = 1000;
const MAX_LINHAS = 500_000; // meio milhão — além de qualquer mesa, e ainda assim finito

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
  while (tudo.length < MAX_LINHAS) {
    const de = tudo.length;
    const { data, error } = await consulta(de, de + PAGINA - 1);
    if (error) return { data: tudo, error, truncado: false };
    const lote = (data as T[] | null) ?? [];
    // Página VAZIA = acabou. É o único sinal que não depende do teto do
    // servidor: uma página curta pode ser o fim do dado ou o teto cortando, e
    // as duas são indistinguíveis de fora. Vazia só pode ser uma coisa.
    if (lote.length === 0) return { data: tudo, error: null, truncado: false };
    tudo.push(...lote);
  }
  return { data: tudo, error: null, truncado: true };
}
