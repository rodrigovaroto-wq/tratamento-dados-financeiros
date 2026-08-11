// A REJEIÇÃO DE PENDÊNCIA, DO LADO DA TELA.
//
// A regra vive no Postgres (`db/migrations/0106`), como toda regra deste projeto.
// Este arquivo é o ESPELHO dela no portal, e existe por um motivo prático: sem o
// piso do motivo aqui, o botão manda o texto curto ao banco, o banco recusa, e o
// usuário descobre pelo erro genérico da server action que "algo deu errado" —
// quando o que houve foi uma regra clara que dava para dizer antes de clicar.
//
// ESPELHO DIVERGE. É o defeito clássico desta arquitetura (o mesmo do JSON dos
// nós do n8n contra a `lib/`), e a resposta é a mesma: um assert que compara os
// dois. `(0114)` em `portal/scripts/verificar-export.mts` LÊ o `select 15;` da
// migration e exige que bata com a constante abaixo — mudar o piso no banco sem
// mudar aqui reprova a suíte, em vez de produzir uma tela que mente sobre a
// regra.

/** Mínimo de caracteres do motivo. Espelha `fn_min_motivo_rejeicao()` (0106). */
export const MOTIVO_REJEICAO_MIN = 15;

/**
 * O motivo é suficiente? `trim` antes de contar — trinta espaços em branco são
 * zero caractere de justificativa, e é o primeiro atalho que alguém tenta.
 */
export function motivoDeRejeicaoValido(texto: string | null | undefined): boolean {
  return (texto ?? "").trim().length >= MOTIVO_REJEICAO_MIN;
}

/**
 * O QUE A TELA DIZ ANTES DE ALGUÉM CLICAR — e por que o texto muda com a
 * pendência.
 *
 * Rejeitar não é "arquivar": é afirmar que o motor errou, que o problema não
 * existe. Para a pendência NÃO-SOBREPUJÁVEL (a lista fechada de `f0/04`) essa
 * afirmação é a única saída além de consertar o documento — nenhuma ressalva a
 * libera —, e é por isso que ela merece frase própria: quem clica ali está
 * passando por cima do controle mais duro do sistema, e a tela tem de dizer isso
 * com essas palavras, não com um ícone amarelo.
 */
export function avisoDeRejeicao(p: { severidade: string; sobrepujavel?: boolean | null }): string {
  if (p.sobrepujavel === false) {
    return (
      "Esta é uma pendência que NENHUMA ressalva libera. Rejeitar é declarar que ela não "
      + "procede — o caso passa a poder ser aprovado, e o Portão 2 vai mostrar que isso "
      + "aconteceu, com o seu nome e o seu motivo, também dentro da aprovação."
    );
  }
  if (p.severidade === "bloqueante") {
    return (
      "Esta pendência está impedindo a aprovação do caso. Rejeitar é declarar que ela não "
      + "procede — não que o problema foi resolvido. Se ele foi resolvido, o próprio sistema "
      + "fecha a pendência na próxima passada."
    );
  }
  return (
    "Rejeitar é declarar que a pendência não procede. Ela não some: fica registrada como "
    + "improcedente, com o seu nome e o seu motivo."
  );
}

/**
 * O ESTADO DA PENDÊNCIA, EM PORTUGUÊS DE TELA.
 *
 * O banco guarda `reenviada_ao_cliente`; quem lê a tela precisa de "pedida ao
 * cliente". É a mesma regra do `rotulos.ts` — a tela não publica chave de banco
 * —, e fica aqui porque estes cinco valores são da máquina de estado de `f0/04`,
 * não vocabulário de seção contábil.
 */
export function rotuloDoEstado(estado: string): string {
  const mapa: Record<string, string> = {
    aberta: "em aberto",
    em_correcao_interna: "em correção interna",
    reenviada_ao_cliente: "pedida ao cliente",
    aceita_com_ressalva: "aceita com ressalva",
    rejeitada: "declarada improcedente",
    resolvida: "resolvida",
  };
  return mapa[estado] ?? estado.replace(/_/g, " ");
}
