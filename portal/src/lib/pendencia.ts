// AS DECISÕES DE PENDÊNCIA, DO LADO DA TELA.
//
// Este arquivo já teve o piso de caracteres do motivo de rejeição e o aviso que
// mudava conforme a pendência. Os dois saíram com a 0109, que trocou o
// formulário por três botões: código de uma regra que não existe mais é pior que
// código ausente, porque ele passa a impressão de que a regra continua valendo.
//
// AS TRÊS SAÍDAS DA PENDÊNCIA, COMO A TELA AS OFERECE (0109).
//
// Pedido do dono (11/08/2026): três botões, separados por cor, sem campo de
// escrita e sem data. O clique registra a decisão e o rótulo aparece na
// pendência — nenhum formulário no meio.
//
// A ORDEM É A DA TELA e não é alfabética: primeiro o que devolve o problema a
// quem pode resolvê-lo (o cliente), depois o que segue apesar dele, por último o
// que nega que ele exista. Do mais reversível para o menos, que é a ordem em que
// se deve pensar — e a ordem em que um botão apressado faz menos estrago.
export type DecisaoPendencia = "contatar_cliente" | "prosseguir" | "nao_procede";

export interface BotaoDecisao {
  decisao: DecisaoPendencia;
  rotulo: string;
  /** o que acontece com o caso — a tela diz, o usuário não adivinha */
  efeito: string;
  classe: string;
  /** cor do rótulo depois de decidida */
  chip: string;
}

export const BOTOES_DECISAO: BotaoDecisao[] = [
  {
    decisao: "contatar_cliente",
    rotulo: "Contatar o Cliente",
    efeito: "O caso continua aguardando: o documento ainda não chegou.",
    classe: "border-ok-200 bg-ok-50 text-ok-800 hover:bg-ok-100",
    chip: "bg-ok-100 text-ok-800",
  },
  {
    decisao: "prosseguir",
    rotulo: "Prosseguir sem resolução",
    efeito: "O caso deixa de ser travado por esta pendência, e ela fica registrada como aceita.",
    classe: "border-risco-200 bg-risco-50 text-risco-800 hover:bg-risco-100",
    chip: "bg-risco-100 text-risco-800",
  },
  {
    decisao: "nao_procede",
    rotulo: "Pendência não procede",
    efeito: "A pendência é declarada improcedente e deixa de travar o caso.",
    classe: "border-alerta-200 bg-alerta-50 text-alerta-900 hover:bg-alerta-100",
    chip: "bg-alerta-100 text-alerta-900",
  },
];

/** O rótulo que fica na pendência depois de decidida — indexado pelo ESTADO. */
export const ROTULO_POR_ESTADO: Record<string, BotaoDecisao> = {
  reenviada_ao_cliente: BOTOES_DECISAO[0],
  aceita_com_ressalva: BOTOES_DECISAO[1],
  rejeitada: BOTOES_DECISAO[2],
};

/**
 * O ESTADO DA PENDÊNCIA, EM PORTUGUÊS DE TELA.
 *
 * O banco guarda `reenviada_ao_cliente`; quem lê a tela precisa de "pedida ao
 * cliente". É a mesma regra do `rotulos.ts` — a tela não publica chave de banco.
 *
 * Continua existindo ao lado de `ROTULO_POR_ESTADO` porque os dois respondem
 * perguntas diferentes: aquele dá o BOTÃO que produziu o estado (e só vale para
 * os três decididos), este dá o NOME do estado, inclusive dos que nenhum botão
 * produz — `aberta` e `resolvida`, que são do motor.
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
