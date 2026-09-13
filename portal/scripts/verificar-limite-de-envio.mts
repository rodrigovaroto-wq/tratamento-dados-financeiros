// A SUÍTE DO LIMITE DE ENVIO — o lote que a hospedagem recusa antes de o código rodar.
//
// POR QUE ELA EXISTE. Em 13/09/2026 o dono selecionou 48 arquivos (~50 MB) para
// o mandato da AMO, a tela ofereceu "Enviar 48 arquivos", estimou 58 minutos de
// processamento, e o envio morreu em **HTTP 413** — da BORDA da Vercel, antes
// de `/api/intake` ser invocado. Nenhuma mensagem em português do portal podia
// aparecer ali, e nenhuma correção DENTRO da rota resolveria.
//
// O QUE ESTA SUÍTE TRAVA, e cada item é uma forma medida de errar:
//   1. lote que não cabe na Serverless Function NUNCA é mandado para ela —
//      é o 413 em si;
//   2. a conta do tamanho é a do CORPO que sobe, não a soma dos arquivos — um
//      lote de muitos arquivos pequenos estoura o teto só com a sobrecarga do
//      `multipart`, e essa é a forma de o 413 voltar "por pouco";
//   3. o lote pequeno continua indo pelo caminho de sempre — o que tem status
//      real e mensagem em português. Uma correção que jogasse TODO envio no
//      caminho direto trocaria o 413 por perda de diagnóstico em 100% dos dias;
//   4. o teto por arquivo do outro lado é recusado ANTES de subir, com o NOME
//      do arquivo — sob envio direto ele seria recusado em silêncio.
//
// O ORÁCULO DO ITEM 1 É O LOTE REAL, não um lote inventado: os arquivos e os
// tamanhos abaixo são os que aparecem na captura de tela do envio que falhou.
// São 13 dos 48 — os que a tela mostrava. Os outros 35 NÃO estão aqui, e não
// são estimados: o que se afirma é só o que dá para provar (regra 4). Mesmo
// esses 13 já bastam para o invariante, e isso é dito onde é usado.
import {
  planejarEnvio, corpoMultipartBytes, recusaPorArquivoGrande, formatarBytes,
  TETO_DA_FUNCTION_BYTES, TETO_DO_PROXY_BYTES, TETO_POR_ARQUIVO_BYTES,
  type ArquivoParaEnvio,
} from "../src/lib/limite-de-envio.ts";

let ok = 0;
const falhas: string[] = [];
function checar(condicao: boolean, o_que: string) {
  if (condicao) { ok += 1; return; }
  falhas.push(o_que);
}

const KiB = 1024;
const MiB = 1024 * KiB;

// Os nomes de campo REAIS que o portal descobre no HTML do Form (ver
// `n8n-form.ts`). Entram na conta porque entram no corpo.
const CAMPOS = { mandato: "Mandato (nome do caso)", arquivos: "Arquivos" } as const;
const MANDATO = "AMO";

// ---------------------------------------------------------------------------
// 1. O LOTE QUE PRODUZIU O 413 — medido na captura de 13/09/2026
// ---------------------------------------------------------------------------
//
// 13 dos 48 arquivos, com os tamanhos exibidos na própria lista da tela.
const LOTE_DA_CAPTURA: readonly ArquivoParaEnvio[] = [
  { nome: "GENERAL TABACO - DRE 202603.pdf", bytes: Math.round(1.2 * MiB) },
  { nome: "OMNIBEAUTY - BALANÇO 2023.pdf", bytes: 839 * KiB },
  { nome: "OMNIBEAUTY - BALANÇO 2024.pdf", bytes: Math.round(2.0 * MiB) },
  { nome: "OMNIBEAUTY - BALANÇO 2025.03.pdf", bytes: 178 * KiB },
  { nome: "OMNIBEAUTY - BALANÇO 2025.06.pdf", bytes: 179 * KiB },
  { nome: "OMNIBEAUTY - BALANÇO 2025.pdf", bytes: 973 * KiB },
  { nome: "OMNIBEAUTY - BALANÇO 202603.pdf", bytes: Math.round(1.2 * MiB) },
  { nome: "OMNIBEAUTY - DRE 2023_assin.pdf", bytes: 850 * KiB },
  { nome: "OMNIBEAUTY - DRE 2024.pdf", bytes: Math.round(2.0 * MiB) },
  { nome: "OMNIBEAUTY - DRE 2025.03.pdf", bytes: 175 * KiB },
  { nome: "OMNIBEAUTY - DRE 2025.06.pdf", bytes: Math.round(1.0 * MiB) },
  { nome: "OMNIBEAUTY - DRE 2025.pdf", bytes: Math.round(1.2 * MiB) },
  { nome: "OMNIBEAUTY - DRE 202603.pdf", bytes: Math.round(1.2 * MiB) },
];

const planoDaCaptura = planejarEnvio(LOTE_DA_CAPTURA, CAMPOS, MANDATO);

// 13 dos 48 arquivos já somam ~13 MB — quase TRÊS VEZES o teto da Function.
// Isto é o que torna os 35 desconhecidos dispensáveis para o invariante: o
// lote já não cabia antes de metade dele ser contado.
checar(planoDaCaptura.corpoBytes > TETO_DA_FUNCTION_BYTES,
  `os 13 arquivos da captura (${formatarBytes(planoDaCaptura.corpoBytes)}) passariam a caber no teto da Function `
  + `(${formatarBytes(TETO_DA_FUNCTION_BYTES)}) — o lote que produziu o 413 deixou de ser grande`);
checar(planoDaCaptura.via === "direto",
  "o lote da captura (48 arquivos, ~50 MB) voltaria a ser encaminhado pela Serverless Function — é o 413 de 13/09/2026 de volta");

// ---------------------------------------------------------------------------
// 2. NENHUM LOTE ACIMA DO TETO É MANDADO PARA A FUNCTION
// ---------------------------------------------------------------------------
//
// Não é um caso: é uma varredura. Para cada combinação de quantidade × tamanho,
// o que se exige é uma coisa só — se o corpo passa do teto, o caminho não pode
// ser o `proxy`. Um teto que vale para o exemplo escolhido e falha para o
// vizinho não é teto.
const QUANTIDADES = [1, 2, 3, 5, 10, 20, 38, 48, 100, 190];
const TAMANHOS = [1, 1 * KiB, 100 * KiB, 175 * KiB, 1 * MiB, 2 * MiB, 4 * MiB, 10 * MiB];
let varridos = 0;
let acimaDoTeto = 0;
for (const n of QUANTIDADES) {
  for (const bytes of TAMANHOS) {
    const lote = Array.from({ length: n }, (_, i) => ({ nome: `documento-${i}.pdf`, bytes }));
    const plano = planejarEnvio(lote, CAMPOS, MANDATO);
    varridos += 1;
    if (plano.corpoBytes >= TETO_DA_FUNCTION_BYTES) {
      acimaDoTeto += 1;
      checar(plano.via === "direto",
        `${n} arquivo(s) de ${formatarBytes(bytes)} (corpo de ${formatarBytes(plano.corpoBytes)}) `
        + "seriam encaminhados pela Function, que os recusa na borda com 413");
    }
  }
}
// A VARREDURA TEM DE TER ACHADO CASOS GRANDES. Sem esta linha, uma mudança que
// zerasse os tamanhos deixaria o laço acima sem nenhum `checar` — e um laço que
// não afirma nada é verde por vacuidade, que é o defeito central deste
// repositório (ver `.claude/memory/fixture-nasce-vazia.md`).
checar(acimaDoTeto >= 20,
  `a varredura só encontrou ${acimaDoTeto} lote(s) acima do teto em ${varridos} — ela parou de medir o caso que interessa`);

// ---------------------------------------------------------------------------
// 3. A SOBRECARGA DO MULTIPART É CONTADA — o 413 "por pouco"
// ---------------------------------------------------------------------------
//
// O corpo que sobe é maior que a soma dos arquivos: cada parte leva boundary,
// `Content-Disposition` com o nome do arquivo e `Content-Type`. Um lote de
// muitos arquivos pequenos calibrado contra a SOMA passa raspando na conta
// errada e estoura na borda.
const MUITOS_PEQUENOS = Array.from({ length: 400 }, (_, i) => ({
  nome: `extrato-mensal-consolidado-${i}.pdf`,
  bytes: 9 * KiB,
}));
const somaPura = MUITOS_PEQUENOS.reduce((s, a) => s + a.bytes, 0);
const corpoReal = corpoMultipartBytes(MUITOS_PEQUENOS, CAMPOS, MANDATO);
checar(corpoReal > somaPura,
  "o corpo do multipart ficou igual à soma dos arquivos — a sobrecarga por parte deixou de ser contada");
checar(corpoReal - somaPura > 50 * KiB,
  `400 arquivos rendem só ${formatarBytes(corpoReal - somaPura)} de sobrecarga — a conta por parte encolheu e volta a caber onde não cabe`);
// O nome do arquivo entra em BYTES, não em caracteres: "BALANÇO" tem 7
// caracteres e 8 bytes em UTF-8. Contar caractere subestima justo os nomes do
// cliente, que são em português.
const comCedilha = corpoMultipartBytes([{ nome: "BALANÇO.pdf", bytes: 0 }], CAMPOS, MANDATO);
const semCedilha = corpoMultipartBytes([{ nome: "BALANCO.pdf", bytes: 0 }], CAMPOS, MANDATO);
checar(comCedilha > semCedilha,
  "o nome do arquivo passou a ser contado em caracteres, não em bytes UTF-8 — acentos deixaram de pesar");

// ---------------------------------------------------------------------------
// 4. O LOTE PEQUENO NÃO MUDOU DE CAMINHO
// ---------------------------------------------------------------------------
//
// Esta metade é tão importante quanto a outra. O caminho pela Function é o
// único que devolve o status REAL do n8n e as mensagens em português (chave
// inválida, sem crédito, orçamento recusado). Empurrar todo envio para o
// caminho direto trocaria um defeito raro por perda de diagnóstico todo dia.
checar(planejarEnvio([{ nome: "DRE 2025.pdf", bytes: 175 * KiB }], CAMPOS, MANDATO).via === "proxy",
  "um único PDF de 175 KB deixou de ir pelo encaminhamento do portal — o diagnóstico em português some do caso comum");
checar(planejarEnvio(
  [{ nome: "a.pdf", bytes: 1 * MiB }, { nome: "b.pdf", bytes: 1 * MiB }], CAMPOS, MANDATO,
).via === "proxy",
  "dois PDFs de 1 MB (o lote que rodou a US$ 0,04) deixaram de ir pelo encaminhamento do portal");

// E O TETO DO PORTAL FICA ABAIXO DO DA PLATAFORMA, com folga real. Se alguém
// igualar os dois, o lote que cai exatamente no limite volta a depender de a
// borda contar os bytes igual a nós.
checar(TETO_DO_PROXY_BYTES < TETO_DA_FUNCTION_BYTES,
  "o teto do portal alcançou o da plataforma — não sobrou margem para a sobrecarga do multipart");
checar(TETO_DA_FUNCTION_BYTES - TETO_DO_PROXY_BYTES >= 256 * KiB,
  "a margem entre o teto do portal e o da plataforma encolheu abaixo de 256 KB");

// ---------------------------------------------------------------------------
// 5. O ARQUIVO QUE NENHUM CAMINHO ACEITA É NOMEADO ANTES DE SUBIR
// ---------------------------------------------------------------------------
const GIGANTE = { nome: "SCAN COMPLETO 2019-2025.pdf", bytes: TETO_POR_ARQUIVO_BYTES + 1 };
const planoGigante = planejarEnvio([GIGANTE, { nome: "DRE.pdf", bytes: 10 * KiB }], CAMPOS, MANDATO);
checar(planoGigante.acimaDoTetoPorArquivo.length === 1,
  "um arquivo acima do teto por arquivo deixou de ser detectado — ele subiria inteiro para ser recusado em silêncio do outro lado");
const recusa = recusaPorArquivoGrande(planoGigante.acimaDoTetoPorArquivo);
checar(recusa.includes(GIGANTE.nome),
  "a recusa por arquivo grande não diz QUAL arquivo — num lote de 48, isso é um convite a tentar de novo igual");
checar(!/\b(413|HTTP|multipart|Vercel|Serverless|n8n|CORS)\b/i.test(recusa),
  `a recusa por arquivo grande passou a citar ferramenta ou código de protocolo: "${recusa}"`);

// O teto por arquivo não pode ser menor que o do proxy: seria um lote que não
// cabe em lugar nenhum, recusado por um motivo que não é o verdadeiro.
checar(TETO_POR_ARQUIVO_BYTES > TETO_DO_PROXY_BYTES,
  "o teto por arquivo ficou abaixo do teto do encaminhamento — arquivo legítimo passaria a ser recusado pelo motivo errado");

if (falhas.length > 0) {
  console.error(`\n${falhas.length} falha(s):`);
  for (const f of falhas) console.error(`  ✗ ${f}`);
  console.error(`\n${ok} verificações OK / ${falhas.length} falhas`);
  process.exit(1);
}
console.log(`${ok} verificações OK / 0 falhas`);
console.log("LIMITE DE ENVIO OK — nenhum lote acima do teto da hospedagem é mandado para ela");
console.log("SOBRECARGA OK — o corpo medido é o do multipart, não a soma dos arquivos");
console.log("CAMINHO COMUM OK — lote pequeno continua com status real e mensagem em português");
