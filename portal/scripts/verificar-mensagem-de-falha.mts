// A SUÍTE DA MENSAGEM DE FALHA — o texto que o analista lê quando nada deu certo.
//
// POR QUE ELA EXISTE. Este é o único texto do sistema cujo defeito NÃO aparece
// enquanto tudo funciona: ele só é lido no dia ruim. Um erro aqui — uma
// assinatura que deixou de casar, uma frase que voltou a citar ferramenta — não
// quebra nada, não aparece em nenhuma tela de teste, e só se descobre quando
// alguém está esperando ajuda e recebe "deu erro".
//
// O que ela trava, e cada item saiu de uma forma de errar:
//   1. toda causa REAL do pipeline chega numa explicação específica, e não na
//      genérica — a genérica é rede, não destino;
//   2. nenhuma frase visível nomeia ferramenta, empresa ou termo de código;
//   3. as causas que pedem AÇÕES OPOSTAS não podem cair na mesma explicação;
//   4. a genérica ainda responde as três perguntas que tiram o analista da
//      dúvida: parou, não foi culpa sua, nada se perdeu.
import {
  explicarFalha, explicarParada, explicarLoteVazio, FRACAO_MINIMA_COM_LINHAS,
  type FalhaExplicada,
} from "../src/lib/falha-em-portugues.ts";

let ok = 0;
const falhas: string[] = [];
function checar(condicao: boolean, o_que: string) {
  if (condicao) { ok += 1; return; }
  falhas.push(o_que);
}

// ---------------------------------------------------------------------------
// 1. As causas REAIS, com as mensagens como o pipeline as produz
// ---------------------------------------------------------------------------
//
// Não são exemplos inventados: cada uma é a forma que `diagnosticarErroApi`
// (n8n/lib/extract.mjs), a recusa do orçamento (n8n/lib/custo.mjs) ou o Error
// Workflow escrevem no banco hoje.
// Tuplas e não objetos: são 9 linhas de DADO, e a forma repetida
// `{ etapa: …, mensagem: …, esperado: … }` nove vezes é ruído que esconde o que
// varia — além de o próprio Sonar ler o bloco como duplicado, com razão.
type CausaReal = readonly [etapa: string, mensagem: string, esperadoNoTitulo: string];

const CAUSAS_REAIS: readonly CausaReal[] = [
  ["orcamento", "[orçamento v4 (2026-08-24)] Lote recusado ANTES de gastar: 38 documento(s) = 44 chamada(s) de IA ≈ US$ 3,10, acima do teto de US$ 3,00 por execução.", "grande demais"],
  ["IA Extrair", "CHAVE DO PROVEDOR INVÁLIDA, AUSENTE OU SEM PERMISSÃO (401/403). Nada a ver com cadência ou crédito.", "entrar na conta"],
  ["IA Extrair", "CONTA DO PROVEDOR SEM CRÉDITO OU SEM COBRANÇA ATIVA. A conta não tem como pagar a chamada.", "sem saldo"],
  ["IA Classificar", "TETO DE GASTO ATINGIDO no provedor de IA — e isto NÃO é falta de crédito: há saldo.", "limite de gasto"],
  ["IA Extrair", "MODELO INDISPONÍVEL PARA ESTA CONTA (404). O modelo configurado no workflow não existe.", "não existe mais"],
  ["IA Extrair", "LIMITE DE CADÊNCIA DO PROVEDOR (rate limit por minuto). Aqui espaçar as chamadas ajuda.", "rápido demais"],
  ["IA Extrair", "COTA DIÁRIA DO PROVEDOR ESGOTADA (limite por DIA de tokens/requisições do tier da conta).", "limite de uso de hoje"],
  ["Registrar Documento", "connect ETIMEDOUT 10.0.0.1:5432", "guardar"],
  ["desconhecida", "O processamento parou sem mensagem de erro.", "não disse o motivo"],
];

for (const [etapa, mensagem, esperado] of CAUSAS_REAIS) {
  const e = explicarFalha({ etapa, mensagem });
  checar(
    e.titulo.toLowerCase().includes(esperado.toLowerCase()),
    `"${esperado}" — causa real de "${etapa}" caiu em: "${e.titulo}"`,
  );
}

// ---------------------------------------------------------------------------
// 2. NENHUMA palavra técnica no que o analista lê
// ---------------------------------------------------------------------------
//
// A lista é de coisas que o dono não deve precisar conhecer para entender que o
// trabalho parou. Ela inclui nomes de fornecedor de propósito: o analista não
// tem contrato com nenhum deles, e citá-los transfere para ele um problema que
// não é dele resolver.
const PROIBIDAS = [
  "openai", "gemini", "google", "n8n", "supabase", "postgres", "api", "token",
  "http", "json", "workflow", "endpoint", "timeout", "rate limit", "payload",
  "null", "undefined", "exception", "stack", "query", "sql", "webhook",
  "credencial", "provedor",
];

function textoVisivel(e: FalhaExplicada): string {
  return `${e.titulo} ${e.explicacao} ${e.oQueFazer}`.toLowerCase();
}

const TODAS: FalhaExplicada[] = [
  ...CAUSAS_REAIS.map(([etapa, mensagem]) => explicarFalha({ etapa, mensagem })),
  explicarFalha({ etapa: "Fatiar Extracao", mensagem: "Cannot read properties of undefined" }),
  explicarParada({ processados: 12, esperados: 38 }),
  explicarParada({ processados: 0, esperados: 38 }),
  explicarLoteVazio({ comLinhas: 0, documentos: 38 })!,
  explicarLoteVazio({ comLinhas: 5, documentos: 38 })!,
];

for (const e of TODAS) {
  const texto = textoVisivel(e);
  const encontradas = PROIBIDAS.filter((p) => texto.includes(p));
  checar(encontradas.length === 0, `palavra técnica na tela: ${encontradas.join(", ")} — em "${e.titulo}"`);
}

// ---------------------------------------------------------------------------
// 3. Causas com AÇÕES OPOSTAS não podem cair na mesma explicação
// ---------------------------------------------------------------------------
//
// É a mesma disciplina de `diagnosticarErroApi`, e o motivo é o mesmo: "sem
// saldo" manda recolocar dinheiro, "teto de gasto" manda mexer numa
// configuração com o dinheiro lá. Dizer um pelo outro faz a pessoa procurar o
// problema no lugar errado — e voltar dizendo que está tudo certo.
const semSaldo = explicarFalha({ etapa: "IA Extrair", mensagem: "CONTA DO PROVEDOR SEM CRÉDITO" });
const tetoGasto = explicarFalha({ etapa: "IA Extrair", mensagem: "TETO DE GASTO ATINGIDO no provedor" });
checar(semSaldo.titulo !== tetoGasto.titulo, "sem saldo e teto de gasto dizem a mesma coisa");
checar(semSaldo.oQueFazer !== tetoGasto.oQueFazer, "sem saldo e teto de gasto mandam fazer a mesma coisa");

// E a recusa do orçamento é a única em que a ação é DO ANALISTA — ele divide o
// lote e resolve sozinho. Marcá-la como "chame o suporte" transformaria um
// autoatendimento de um minuto numa espera.
const orcamento = explicarFalha({ etapa: "orcamento", mensagem: "Lote recusado ANTES de gastar" });
checar(orcamento.quemResolve === "voce", "a recusa por tamanho de lote é resolvível pelo próprio analista");
checar(
  explicarFalha({ etapa: "IA Extrair", mensagem: "CHAVE DO PROVEDOR INVÁLIDA" }).quemResolve === "suporte",
  "acesso recusado não é coisa que o analista resolva",
);

// ---------------------------------------------------------------------------
// 4. A genérica é REDE, e ainda responde as três perguntas
// ---------------------------------------------------------------------------
const generica = explicarFalha({ etapa: "Nó Que Ninguém Previu", mensagem: "algo completamente novo" });
checar(generica.titulo.toLowerCase().includes("problema técnico"), "a genérica diz que parou");
checar(
  generica.explicacao.toLowerCase().includes("não foi nada que você fez"),
  "a genérica tira a culpa de quem está lendo",
);
checar(
  generica.explicacao.toLowerCase().includes("não se perderam"),
  "a genérica diz que os arquivos estão salvos — é a pergunta seguinte de quem lê",
);

// ---------------------------------------------------------------------------
// 5. O lote vazio, e o limiar declarado
// ---------------------------------------------------------------------------
checar(explicarLoteVazio({ comLinhas: 38, documentos: 38 }) === null, "lote inteiro lido não vira aviso");
checar(explicarLoteVazio({ comLinhas: 0, documentos: 0 }) === null, "lote sem documento nenhum não vira aviso");
checar(
  explicarLoteVazio({ comLinhas: 19, documentos: 38 }) === null,
  `metade lida está no limiar (${FRACAO_MINIMA_COM_LINHAS}) e não vira aviso`,
);
checar(explicarLoteVazio({ comLinhas: 18, documentos: 38 }) !== null, "abaixo da metade vira aviso");
checar(
  explicarLoteVazio({ comLinhas: 0, documentos: 38 })!.titulo
    !== explicarLoteVazio({ comLinhas: 5, documentos: 38 })!.titulo,
  "nada lido e pouco lido são notícias diferentes",
);

// A parada precisa dizer QUANTO andou: "parou" sozinho não diz se dá para
// aproveitar o que já entrou.
checar(
  explicarParada({ processados: 12, esperados: 38 }).explicacao.includes("12"),
  "a parada diz quantos arquivos chegaram a ser organizados",
);
checar(
  explicarParada({ processados: 12, esperados: 38 }).oQueFazer.toLowerCase().includes("não reenvie"),
  "a parada avisa para não reenviar antes de saber a causa — reenviar pode duplicar",
);

if (falhas.length > 0) {
  console.error(`\n${falhas.length} falha(s):`);
  for (const f of falhas) console.error(`  ✗ ${f}`);
  console.error(`\n${ok} verificações OK / ${falhas.length} falhas`);
  process.exit(1);
}
console.log(`${ok} verificações OK / 0 falhas`);
console.log("MENSAGEM DE FALHA OK — toda causa real tem explicação própria, e nenhuma cita ferramenta");
