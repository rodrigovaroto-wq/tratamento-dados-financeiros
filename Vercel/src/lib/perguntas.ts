// AS PERGUNTAS AO CLIENTE, DO LADO DA TELA.
//
// A `0120` construiu o motor inteiro — `fn_sugerir_perguntas` devolve a pergunta
// PRONTA, com motivo, risco, impacto, os marcadores já resolvidos e o nome da
// empresa — e nenhuma tela do portal a chamava. A única forma de ver uma
// sugestão era rodar a função no SQL Editor, o que significa, na prática, que
// para quem usa o produto a 0120 não existia.
//
// POR QUE ELAS FICAM NUMA ABA PRÓPRIA (decisão do dono, 18/08/2026), e não
// dentro do botão "Contatar o Cliente" da fila de pendências, que era o desenho
// anterior: a pendência registra uma DECISÃO já tomada sobre um problema já
// medido; a pergunta é uma SUGESTÃO do sistema que provavelmente ainda não foi
// feita a ninguém. Misturar as duas na mesma lista faria a sugestão parecer
// tarefa concluída — e a mesma tela passaria a responder duas perguntas
// diferentes ("o que eu decidi?" e "o que eu ainda vou perguntar?").
//
// A REGRA DE OURO desta aba, e ela vale para cada linha de código abaixo: o
// sistema NÃO ENVIA NADA. Ele escreve a pergunta e registra o que o humano diz
// que fez com ela. O canal continua sendo o analista.
import { humanizar } from "./rotulos";
import { formatarTipoTaxonomia } from "./export";

/** Uma linha de `fn_sugerir_perguntas(caso)` — Supabase/migrations/0120. */
export interface PerguntaSugerida {
  codigo: string;
  titulo: string;
  prioridade: number;
  /** razão social da empresa de que a pergunta trata; nula na espécie `sempre` */
  entidade: string | null;
  /** o que `fn_registrar_pergunta_acao` precisa de volta para não errar a empresa */
  entidade_id: string | null;
  /** o texto RENDERIZADO — marcadores resolvidos, empresa no prefixo */
  pergunta: string;
  motivo: string;
  risco: string;
  impacto: string;
  /** `sempre` ou `especie:TIPO:conceito` */
  gatilho: string;
  fonte: string;
  ja_enviada: boolean;
}

/** Uma linha de `caso_pergunta` — a ação HUMANA, append-only. */
export interface AcaoDePergunta {
  id: string;
  pergunta_codigo: string;
  entidade_id: string | null;
  acao: "enviada" | "descartada";
  texto_enviado: string | null;
  autor: string;
  criado_em: string;
  /** a empresa, quando a ação foi registrada sobre uma (vem do embed da consulta) */
  entidade?: { razao_social: string } | null;
}

/**
 * A CHAVE DE UMA SUGESTÃO é o par (pergunta, empresa), nunca o código sozinho.
 *
 * Desde a 0119 a exigência é por ENTIDADE, e a 0120 seguiu junto: num grupo de
 * oito balanços a mesma pergunta aparece oito vezes, uma por empresa que não
 * satisfaz. Casar a ação só pelo código marcaria as oito como enviadas quando
 * uma foi — que é exatamente esconder as sete que faltam. O `ja_enviada` do
 * banco já faz esse casamento por par (`is not distinct from`); aqui é a mesma
 * regra, para os rótulos que a tela acrescenta.
 */
export function chaveDaSugestao(codigo: string, entidadeId: string | null): string {
  return `${codigo} ${entidadeId ?? ""}`;
}

/**
 * A PRIORIDADE, EM PALAVRAS — e só as duas pontas têm nome de verdade.
 *
 * A entrega define a escala como "1 crítica ... 4 contextual" e não nomeia o
 * meio. O número FICA VISÍVEL ao lado da palavra justamente por isso: os rótulos
 * 2 e 3 são leitura desta tela, não dado do catálogo, e quem confere a escala
 * precisa poder ver o valor que o banco guarda. Nenhum comportamento pende da
 * prioridade (a 0120 é explícita: corte e envio automático seriam política do
 * dono) — ela ordena a lista e agrupa a leitura, nada mais.
 */
export const PRIORIDADE: Record<number, { rotulo: string; chip: string; explicacao: string }> = {
  1: {
    rotulo: "crítica",
    chip: "bg-risco-100 text-risco-800",
    explicacao: "sem a resposta, uma conferência do sistema não roda de jeito nenhum",
  },
  2: {
    rotulo: "importante",
    chip: "bg-alerta-100 text-alerta-900",
    explicacao: "a análise anda sem a resposta, mas com um número sem contraprova",
  },
  3: {
    rotulo: "complementar",
    chip: "bg-info-100 text-info-800",
    explicacao: "melhora a leitura do caso; nada trava por ela",
  },
  4: {
    rotulo: "contextual",
    chip: "bg-tinta-100 text-tinta-600",
    explicacao: "contexto do negócio, para interpretar o que já foi extraído",
  },
};

export function rotuloDaPrioridade(p: number): string {
  return PRIORIDADE[p]?.rotulo ?? "sem prioridade";
}

export function chipDaPrioridade(p: number): string {
  return PRIORIDADE[p]?.chip ?? "bg-tinta-100 text-tinta-600";
}

/**
 * POR QUE ESTA PERGUNTA APARECEU, em português.
 *
 * O banco devolve o gatilho como `exigencia_ausente:BALANCO:ativo_total` — a
 * chave certa para o banco e ilegível na tela. Traduz-se o que se conhece; o
 * que não se conhece SAI COMO VEIO, em vez de virar uma frase genérica: espécie
 * nova (o dono já previu "resultado de reconciliação") aparece na tela no dia em
 * que nascer, mesmo antes de alguém passar por aqui.
 */
export function motivoDoDisparo(gatilho: string): string {
  if (gatilho === "sempre") {
    return "vale para todo mandato que trouxe dado extraído — não depende de linha faltando";
  }
  const [especie, tipo, conceito] = gatilho.split(":");
  if (!tipo || !conceito) return gatilho;
  const onde = formatarTipoTaxonomia(tipo);
  const oQue = humanizar(conceito);
  if (especie === "exigencia_ausente") {
    return `${onde} não trouxe a linha de ${oQue}`;
  }
  if (especie === "linha_presente") {
    return `${onde} trouxe a linha de ${oQue}`;
  }
  return gatilho;
}

/**
 * A DATA DE UMA AÇÃO, curta e em português. `Intl` com fuso explícito: o
 * servidor renderiza em UTC e o navegador em São Paulo, e sem fixar o fuso a
 * mesma linha aparece com horas diferentes nos dois — que o React acusa como
 * erro de hidratação e o leitor acusa como sistema que não sabe a hora.
 */
export function dataCurta(iso: string): string {
  return new Intl.DateTimeFormat("pt-BR", {
    day: "2-digit", month: "2-digit", year: "numeric",
    hour: "2-digit", minute: "2-digit",
    timeZone: "America/Sao_Paulo",
  }).format(new Date(iso));
}
