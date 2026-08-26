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
import {
  semPrimeiroSinalMs, janelaPara, SEM_PROGRESSO_MS, SEGUNDOS_POR_DOCUMENTO,
} from "../src/lib/espera-do-lote.ts";
import { readFileSync } from "node:fs";

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

// ---------------------------------------------------------------------------
// 5. A ESPERA DO LOTE — a outra forma de a tela mentir no dia ruim
// ---------------------------------------------------------------------------
//
// A mensagem de falha responde "o que aconteceu". Estas contas respondem, antes
// dela, "aconteceu alguma coisa?" — e erram para os dois lados: curtas demais,
// declaram parada sobre um lote vivo (e o analista reenvia, pagando a IA duas
// vezes); longas demais, devolvem a espera eterna que a 0108 existe para acabar.
//
// A CADÊNCIA VEM DO WORKFLOW, não de um número repetido aqui: é o mesmo
// `batchInterval` que o nó de classificação tem em produção. O JSON do workflow
// é dado, não código — lê-lo daqui não cruza a fronteira de build que impede o
// portal de importar `n8n/lib/*.mjs`.
const workflow = JSON.parse(
  readFileSync(new URL("../../n8n/workflow.e1-ingestao.json", import.meta.url), "utf8"),
) as { nodes: Array<{ name: string; parameters: Record<string, unknown> }> };
const noClassificar = workflow.nodes.find((n) => n.name === "IA Classificar")!;
const cadenciaS =
  (noClassificar.parameters as { options: { batching: { batch: { batchInterval: number } } } })
    .options.batching.batch.batchInterval / 1000;

// O SILÊNCIO INICIAL É UMA BARREIRA, não uma fila: `Juntar Ramos` (mode append)
// só emite quando a ÚLTIMA classificação volta, então o pior caso de um lote de
// N arquivos é N chamadas espaçadas pela cadência — nenhum documento é
// registrado antes disso, e é isso que a tela mede.
for (const n of [2, 38, 190]) {
  const piorSilencioMs = n * cadenciaS * 1000;
  checar(
    semPrimeiroSinalMs(n) > piorSilencioMs,
    `lote de ${n}: a tela desiste em ${(semPrimeiroSinalMs(n) / 60000).toFixed(1)} min e o silêncio `
      + `legítimo da barreira vai a ${(piorSilencioMs / 60000).toFixed(1)} min`,
  );
}

// E O LOTE DE 38 NÃO PODE GANHAR FOLGA: ele é onde o limite antigo (8 minutos
// fixos) foi calibrado, contra duas rodadas reais. Uma conta nova que afrouxe
// justamente o caso medido deixou de descrever o mesmo fenômeno.
checar(
  semPrimeiroSinalMs(38) <= 8 * 60 * 1000 * 1.1,
  `o lote de 38 ganhou folga demais: ${(semPrimeiroSinalMs(38) / 60000).toFixed(1)} min contra os 8 calibrados`,
);

// A JANELA TOTAL tem de entregar a margem que ela promete no lote de 190 — o
// teto de 90 minutos truncava 152 em 90, e a margem de 3x virava 1,77x sem que
// nada dissesse. Um lote que andasse a 28s por documento (contra os 16 medidos)
// veria a tela desistir viva.
for (const n of [38, 190]) {
  const previstoMs = n * SEGUNDOS_POR_DOCUMENTO * 1000;
  checar(
    janelaPara(n) >= previstoMs * 3,
    `lote de ${n}: a janela entrega ${(janelaPara(n) / previstoMs).toFixed(2)}x do previsto, e a tela promete 3x`,
  );
}

// E a parada por falta de AVANÇO continua curta: depois do primeiro documento o
// progresso anda a cada extração, e 5 minutos são ~20 documentos que deveriam
// ter aparecido. Ela não pode crescer com o lote — é isso que a distingue do
// silêncio inicial.
checar(
  SEM_PROGRESSO_MS === 5 * 60 * 1000,
  "o limite de 'parou de andar' deixou de ser 5 minutos — ele mede outra coisa que o silêncio inicial",
);

if (falhas.length > 0) {
  console.error(`\n${falhas.length} falha(s):`);
  for (const f of falhas) console.error(`  ✗ ${f}`);
  console.error(`\n${ok} verificações OK / ${falhas.length} falhas`);
  process.exit(1);
}
console.log(`${ok} verificações OK / 0 falhas`);
console.log("MENSAGEM DE FALHA OK — toda causa real tem explicação própria, e nenhuma cita ferramenta");
console.log("ESPERA DO LOTE OK — o silêncio da barreira e a janela cobrem o lote de 190");
