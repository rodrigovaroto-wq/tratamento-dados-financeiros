// O QUE DEU ERRADO, DITO PARA QUEM NÃO ESCREVEU O SISTEMA.
//
// O pedido do dono, literal (24/08/2026): "quando dê algum problema e o sistema
// não conseguir progredir até entregar tudo 100% deve aparecer um aviso que o
// sistema parou por problemas técnicos e apontar o problema específico para o
// usuário saber o que aconteceu, essa mensagem deve ser com uma linguagem bem
// simples e nada técnica".
//
// A tela já mostrava a falha — mas mostrava a mensagem CRUA, do jeito que o
// sistema a produziu: "LIMITE DO PROVEDOR ATINGIDO (HTTP 429) [http=429
// type=insufficient_quota …]". Quem lê isso é quem escreveu o código. Para o
// analista, "deu um erro que eu não entendo" e "não deu erro nenhum" pedem a
// mesma ação — chamar alguém — e é por isso que a tradução não é enfeite.
//
// O QUE ESTE ARQUIVO NÃO FAZ: não joga fora a causa técnica. Ela continua na
// tela, atrás de "ver detalhes técnicos", porque sem ela quem for ajudar começa
// perguntando "qual erro apareceu?" e a resposta vira "deu erro". A escolha é
// de ORDEM, não de conteúdo: primeiro o que aconteceu em português, depois o
// que copiar e colar.
//
// AS ASSINATURAS SÃO DE TEXTO, e isso é deliberado. As mensagens nascem em
// quatro lugares diferentes — `diagnosticarErroApi` (N8N/lib/extract.mjs), a
// recusa do orçamento (N8N/lib/custo.mjs), o Error Workflow (que repassa o que
// o n8n disser) e o Postgres. Um código de erro estruturado exigiria que os
// quatro concordassem com um vocabulário, e três deles são de terceiros. Casar
// por assinatura de texto é frágil no detalhe e robusto no que importa: quando
// nenhuma casa, cai no genérico — que continua sendo melhor que o texto cru.

export type FalhaExplicada = {
  /** Uma frase, no tempo do usuário: o que aconteceu. */
  titulo: string;
  /** Por que o trabalho parou, sem nomear ferramenta nenhuma. */
  explicacao: string;
  /** A próxima ação de quem está lendo. Nunca "contate o suporte" sozinho. */
  oQueFazer: string;
  /** Quem resolve: o próprio analista, ou quem cuida do sistema. */
  quemResolve: "voce" | "suporte";
};

/** Normaliza para casar assinatura sem depender de acento nem de caixa. */
function achatar(texto: string): string {
  return String(texto ?? "")
    .normalize("NFD")
    .replace(/[̀-ͯ]/g, "")
    .toLowerCase();
}

// A ORDEM DESTA LISTA É SIGNIFICATIVA, e é a mesma disciplina de
// `diagnosticarErroApi`: o caso que ENGANA vem antes do caso parecido.
//
// "Teto de gasto" antes de "sem crédito" porque os dois chegam como limite e
// pedem ações opostas — num há dinheiro e um limite configurado barrou, no
// outro não há dinheiro. Dizer "recarregue" para quem tem saldo manda a pessoa
// procurar o problema no lugar errado, e ela volta dizendo que está tudo certo.
const ASSINATURAS: Array<{
  quando: string[];
  explicada: FalhaExplicada;
}> = [
  {
    // A recusa do próprio sistema, antes de gastar. Não é erro: é o guarda
    // funcionando — e a tela precisa dizer isso, senão parece defeito.
    quando: ["lote recusado antes de gastar", "orcamento"],
    explicada: {
      titulo: "O envio era grande demais para uma vez só.",
      explicacao:
        "O sistema calculou quanto custaria ler todos esses arquivos de uma vez e o valor passou do "
        + "limite combinado para uma única leva. Ele parou ANTES de gastar qualquer coisa — nada foi "
        + "cobrado e nada ficou pela metade.",
      oQueFazer:
        "Divida os arquivos em levas menores e envie usando o MESMO nome de mandato: tudo se acumula "
        + "no mesmo lugar. A mensagem técnica abaixo diz quantos arquivos cabem por vez.",
      quemResolve: "voce",
    },
  },
  {
    quando: ["teto de gasto", "spend limit", "spend_limit", "usage limit", "limite configurado"],
    explicada: {
      titulo: "A conta que lê os documentos atingiu um limite de gasto.",
      explicacao:
        "Não é falta de dinheiro: existe saldo, mas alguém configurou um teto de quanto pode ser "
        + "gasto, e ele foi alcançado. Por isso as telas de cobertura e de saldo parecem normais.",
      oQueFazer: "Quem cuida do sistema precisa aumentar esse teto. Esperar não resolve.",
      quemResolve: "suporte",
    },
  },
  {
    quando: [
      "sem credito", "sem cobranca ativa", "insufficient_quota", "credit_balance",
      "billing", "recarregar credito",
    ],
    explicada: {
      titulo: "A conta que lê os documentos está sem saldo.",
      explicacao:
        "O serviço que lê os arquivos recusou o trabalho porque a conta não tem como pagar por ele.",
      oQueFazer: "Quem cuida do sistema precisa recolocar saldo. Tentar de novo agora dá o mesmo erro.",
      quemResolve: "suporte",
    },
  },
  {
    quando: ["cota diaria", "limite diario", "tokens per day", "requests per day"],
    explicada: {
      titulo: "A conta atingiu o limite de uso de hoje.",
      explicacao:
        "Existe um teto de quanto o sistema pode ler por dia, e ele acabou. O limite se renova "
        + "sozinho na virada do dia.",
      oQueFazer:
        "Tente de novo amanhã, ou peça a quem cuida do sistema para aumentar o limite diário se "
        + "isso passar a acontecer sempre.",
      quemResolve: "voce",
    },
  },
  {
    quando: ["limite de cadencia", "rate limit", "too many requests", "429"],
    explicada: {
      titulo: "O sistema pediu leituras rápido demais e foi barrado.",
      explicacao:
        "O serviço que lê os arquivos aceita um número máximo de pedidos por minuto, e o envio "
        + "passou disso.",
      oQueFazer:
        "Tente de novo daqui a alguns minutos. Se acontecer de novo com o mesmo tamanho de lote, "
        + "avise quem cuida do sistema: o espaçamento entre as leituras precisa ser ajustado.",
      quemResolve: "voce",
    },
  },
  {
    quando: [
      "chave do provedor invalida", "chave invalida", "api key", "api_key",
      "invalid authentication", "permission denied", "permission_denied", "401", "403",
    ],
    explicada: {
      titulo: "O sistema não conseguiu entrar na conta que lê os documentos.",
      explicacao:
        "A senha de acesso que o sistema usa foi recusada. Isso costuma acontecer quando ela expira, "
        + "é trocada, ou foi cadastrada errada.",
      oQueFazer: "Quem cuida do sistema precisa corrigir esse acesso. Não adianta reenviar os arquivos.",
      quemResolve: "suporte",
    },
  },
  {
    quando: ["modelo indisponivel", "model_not_found", "is not found for api version", "404"],
    explicada: {
      titulo: "O sistema está configurado para usar uma ferramenta de leitura que não existe mais.",
      explicacao:
        "O serviço que lê os arquivos respondeu que o recurso pedido não está disponível para esta "
        + "conta. Costuma ser uma configuração que ficou para trás depois de uma mudança.",
      oQueFazer: "Quem cuida do sistema precisa apontar para a ferramenta certa.",
      quemResolve: "suporte",
    },
  },
  {
    // Postgres/Supabase. O analista não precisa saber o nome de nenhum dos dois.
    quando: [
      "connection", "econnrefused", "etimedout", "timeout", "could not connect",
      "postgres", "supabase", "banco de dados", "relation ", "permission denied for",
    ],
    explicada: {
      titulo: "O sistema não conseguiu guardar o que leu.",
      explicacao:
        "Os arquivos chegaram, mas o lugar onde os dados ficam salvos não respondeu. Isso quase "
        + "sempre é passageiro.",
      oQueFazer:
        "Tente de novo em alguns minutos. Se continuar, avise quem cuida do sistema — nada do que "
        + "você enviou foi perdido.",
      quemResolve: "voce",
    },
  },
  {
    // O LOTE QUE NÃO FECHOU — a falha que ninguém registrava.
    //
    // Achado com o dono na tela, em 27/08/2026: a execução morreu no primeiro nó
    // (`Upload Storage`, com credencial `REPLACE`) e o portal disse **"Tudo
    // pronto"**. Não foi descuido da tela: o registro de falha depende do Error
    // Workflow do n8n, que é um passo MANUAL de configuração e **não está
    // ligado** — então nada foi escrito, e a tela deduziu sucesso de contadores
    // que o ramo sobrevivente satisfez sozinho.
    //
    // O sinal que substitui isso não depende de ninguém configurar nada: o
    // workflow termina em `Gravar Uso do Lote` → `Conferir Lote`, e um lote que
    // fecha DEIXA LINHA em `lote_execucao`. Medido nas duas rodadas: a v47 e a
    // v48 deixaram; as duas execuções que morreram não deixaram nenhuma. "O
    // lote fechou?" é a diferença entre terminar e morrer no meio.
    quando: ["lote_nao_fechou", "o lote nao fechou"],
    explicada: {
      titulo: "O processamento parou antes de terminar.",
      explicacao:
        "Parte dos arquivos chegou a ser lida, mas o processamento foi interrompido antes de fechar "
        + "o mandato — então o que está aí dentro pode estar pela metade, e não dá para saber quanto "
        + "falta só olhando a tela.",
      oQueFazer:
        "Não use este mandato como base para nada ainda. Fale com o Varoto com o nome do mandato e a "
        + "hora do envio — é por aí que se acha onde parou.",
      quemResolve: "suporte",
    },
  },
  {
    // O caso que o Error Workflow produz quando o n8n não deixou mensagem.
    quando: ["parou sem mensagem de erro"],
    explicada: {
      titulo: "O sistema parou e não disse o motivo.",
      explicacao:
        "O processamento foi interrompido sem deixar explicação. Os arquivos que você enviou estão "
        + "guardados; o que faltou foi a leitura deles.",
      oQueFazer:
        "Avise quem cuida do sistema com o nome do mandato e a hora do envio — é por aí que se acha "
        + "o que aconteceu.",
      quemResolve: "suporte",
    },
  },
];

// O GENÉRICO NÃO É DESISTÊNCIA, e a diferença está no que ele diz. Ele não sabe
// a causa, mas sabe as três coisas que tiram o analista da dúvida: parou, não
// foi culpa dele, e nada se perdeu. É estritamente mais útil que o texto cru,
// que não responde nenhuma das três.
const GENERICA: FalhaExplicada = {
  titulo: "O sistema parou por um problema técnico.",
  explicacao:
    "O processamento foi interrompido antes de terminar e o sistema não soube dizer por quê. Não foi "
    + "nada que você fez, e os arquivos que você enviou não se perderam.",
  // O DONO PEDIU O NOME, e o nome faz diferença: "contate o suporte" é um beco
  // quando a equipe é uma pessoa. Quem lê isto sabe exatamente para quem virar.
  oQueFazer:
    "Entre em contato com o Varoto para ele resolver essa questão para você — leve a mensagem "
    + "técnica abaixo, o nome do mandato e a hora do envio.",
  quemResolve: "suporte",
};

/**
 * Traduz uma falha registrada pelo pipeline.
 *
 * `etapa` entra na busca junto da mensagem porque em parte dos casos ela é o
 * único sinal: a recusa do orçamento grava `etapa='orcamento'`, e o Error
 * Workflow grava o NOME DO NÓ que quebrou ("IA Extrair", "Registrar
 * Documento") — que diz mais sobre onde parou do que a mensagem do n8n.
 */
export function explicarFalha(falha: { etapa?: string | null; mensagem?: string | null }): FalhaExplicada {
  const alvo = `${achatar(falha.etapa ?? "")} ${achatar(falha.mensagem ?? "")}`;
  for (const { quando, explicada } of ASSINATURAS) {
    if (quando.some((assinatura) => alvo.includes(assinatura))) return explicada;
  }
  return GENERICA;
}

/**
 * O caso SEM mensagem nenhuma: o trabalho parou de andar e ninguém registrou por quê.
 *
 * É o defeito original da 0108 na sua forma mais teimosa. A 0108 deu ao erro um
 * lugar para morar, e cobre duas fontes: a recusa do orçamento e o Error
 * Workflow. Mas o Error Workflow é um passo MANUAL de configuração no n8n, e um
 * nó que morre com o registro desligado não escreve linha nenhuma — a tela volta
 * a deduzir "está processando" de uma ausência que na verdade é morte.
 *
 * A saída é não depender de ninguém registrar nada: se o número de documentos
 * organizados PAROU DE SUBIR por tempo demais, o trabalho não está andando.
 * Isso é medível do lado de cá, sem banco e sem n8n.
 */
export function explicarParada(progresso: { processados: number; esperados: number }): FalhaExplicada {
  const comecou = progresso.processados > 0;
  return {
    titulo: "O sistema parou no meio do trabalho.",
    explicacao: comecou
      ? `Foram organizados ${progresso.processados} de ${progresso.esperados} arquivos e então parou `
        + "de avançar. O que já foi lido está guardado; o resto não chegou a ser lido."
      : "Os arquivos chegaram, mas a leitura não começou a avançar. Nada foi perdido.",
    oQueFazer:
      "Avise quem cuida do sistema com o nome do mandato e a hora do envio. Não reenvie os mesmos "
      + "arquivos ainda: reenviar antes de saber a causa pode duplicar o trabalho.",
    quemResolve: "suporte",
  };
}

/**
 * O caso que passava por SUCESSO: terminou, e não trouxe nada.
 *
 * A tela dizia "pronto" porque o pipeline TENTOU ler cada arquivo — e "tentou"
 * era o que ela media. Um lote em que toda leitura falhou produz exatamente o
 * mesmo sinal de um lote perfeito: um evento por documento. A diferença está no
 * que sobrou no banco, e é ela que este aviso passa a olhar.
 *
 * PARCIAL TAMBÉM AVISA, e o limiar é declarado: metade. Abaixo disso não é
 * "correu bem com algumas pendências", é um resultado que ninguém deveria levar
 * para o comitê sem olhar antes.
 */
export const FRACAO_MINIMA_COM_LINHAS = 0.5;

// DOCUMENTO SEM LINHA NÃO É DOCUMENTO SEM CONTEÚDO, e ignorar isso quebraria
// justamente o que a `0148` existe para fazer.
//
// Medido no smoke test de 27/08/2026: as Notas Explicativas e o Parecer do
// Auditor renderam **zero linhas** e **nove fatos materiais** — covenant
// rompido, ressalva, continuidade operacional. É o resultado CERTO: esses
// documentos não têm tabela numérica, eles dizem as coisas em texto. Uma
// checagem que só conta linha chamaria de "nada pôde ser lido" exatamente o
// lote que funcionou pela primeira vez — e um alarme falso desses ensina a
// ignorar o alarme.
//
// Então o que se conta é DOCUMENTO QUE RENDEU ALGUMA COISA: linha ou fato.
export function explicarLoteVazio(
  resultado: { comLinhas: number; documentos: number; comFatos?: number },
): FalhaExplicada | null {
  const { comLinhas, documentos } = resultado;
  const comFatos = Math.max(0, Number(resultado.comFatos) || 0);
  // Um documento pode ter linha E fato; somar contaria em dobro. O piso é o
  // maior dos dois, que é o menor número que com certeza rendeu alguma coisa.
  const renderam = Math.max(comLinhas, comFatos);
  if (documentos <= 0) return null;
  if (renderam / documentos >= FRACAO_MINIMA_COM_LINHAS) return null;

  if (renderam === 0) {
    return {
      titulo: "Os arquivos chegaram, mas nada pôde ser lido deles.",
      explicacao:
        `Nenhum dos ${documentos} arquivos rendeu uma única linha de dado nem um único alerta de `
        + "texto. Isso não é um mandato vazio: é sinal de que a leitura falhou em todos, e o motivo "
        + "costuma ser o mesmo para o lote inteiro.",
      oQueFazer:
        "Não use este mandato como base para nada — e ele pode ser descartado sem perda, porque não "
        + "há nada dentro dele. Entre em contato com o Varoto para ele resolver essa questão para "
        + "você, com o nome do mandato e a hora do envio.",
      quemResolve: "suporte",
    };
  }
  return {
    titulo: "A maior parte dos arquivos não pôde ser lida.",
    explicacao:
      `Só ${renderam} de ${documentos} arquivos renderam alguma coisa — linha de dado ou alerta de `
      + "texto. O mandato existe, mas está incompleto o bastante para enganar quem olhar os números.",
    oQueFazer:
      "Abra o mandato e confira a fila de pendências antes de usar qualquer número daqui. Se a maioria "
      + "falhou pelo mesmo motivo, avise quem cuida do sistema.",
    quemResolve: "suporte",
  };
}
