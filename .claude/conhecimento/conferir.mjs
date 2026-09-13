#!/usr/bin/env node
// O PORTÃO DO CONHECIMENTO — roda no CI, e reprova.
//
//   node .claude/conhecimento/conferir.mjs
//
// ---------------------------------------------------------------------------
// O QUE ELE TRAVA, e cada item é uma forma de o índice virar mentira
// ---------------------------------------------------------------------------
//
//   1. CAMINHO QUE SUMIU. Uma ficha aponta `toca:` ou `prova:` para arquivo que
//      não existe mais. É o que uma renomeação silenciosa produz — e é
//      exatamente o erro que um vault de Markdown com `[[links]]` deixa passar
//      sem nenhum aviso.
//
//   2. PORTÃO QUE NÃO RODA. Uma ficha diz ser provada por uma suíte que o
//      `suites.yml` não executa. Invariante que não roda é invariante que
//      apodrece — este repositório já mediu isso duas vezes (sessões 82 e 86).
//
//   3. ÂNCORA QUE MUDOU. A região de código que a ficha cita mudou desde a
//      confirmação. A ficha vira SUSPEITA, e o conserto é de uma linha: reler a
//      ficha contra o código e atualizar `ancora_sha`. É este item que faz o
//      conhecimento se invalidar SOZINHO em vez de envelhecer em silêncio.
//
//   4. GRAFO MENOR DO QUE ERA. As contagens por tipo caíram abaixo do piso
//      declarado em `cobertura.json`. É a regra 7 aplicada ao próprio índice:
//      uma regex que parou de casar continua rodando, continua verde, e devolve
//      briefing curto — que a sessão lê como "não há nada sobre isso".
//
//   5. GRAFO DESATUALIZADO. Isto NÃO é conferido aqui: quem o confere é o
//      `git diff --exit-code -- .claude/conhecimento/grafo.jsonl` no CI, o mesmo
//      portão dos quatro workflows do n8n e do `schema.sql`. Está escrito aqui
//      para ninguém procurar essa checagem neste arquivo e concluir que falta.

import { readFileSync, readdirSync, existsSync } from "node:fs";
import { join } from "node:path";

const RAIZ = new URL("../..", import.meta.url).pathname.replace(/\/$/, "");
const ler = (p) => readFileSync(join(RAIZ, p), "utf8");
const existe = (p) => existsSync(join(RAIZ, p));

const falhas = [];
const avisos = [];
let ok = 0;
const checar = (cond, oQue) => { if (cond) ok += 1; else falhas.push(oQue); };

// ---------------------------------------------------------------------------
// O grafo, que é a entrada deste portão
// ---------------------------------------------------------------------------
const GRAFO = ".claude/conhecimento/grafo.jsonl";
if (!existe(GRAFO)) {
  console.error("grafo.jsonl não existe — rode `node .claude/conhecimento/indexar.mjs`.");
  process.exit(1);
}
const objetos = ler(GRAFO).split("\n").filter(Boolean).map((l) => JSON.parse(l));
const nos = objetos.filter((o) => o.k === "n");
const arestas = objetos.filter((o) => o.k === "e");

// ---------------------------------------------------------------------------
// 1 e 2. As fichas apontam para coisas que existem e que rodam
// ---------------------------------------------------------------------------
const CI = ".github/workflows/suites.yml";
const yml = existe(CI) ? ler(CI) : "";

for (const e of arestas.filter((x) => x.rel === "TOCA")) {
  const alvo = e.pa.slice("arquivo:".length);
  checar(existe(alvo), `${e.f}: o campo "toca" aponta para "${alvo}", que não existe mais`);
}
// O CI RODA SUÍTE POR GLOB, e este portão não sabia disso — medido em
// 13/09/2026: uma ficha nova sobre um invariante de `N8N/test/custo.test.mjs`
// não tinha COMO passar. O caminho literal existe e o `suites.yml` não o cita
// (ele roda `node --test 'N8N/test/*.test.mjs'`); o glob é citado e não existe
// como arquivo. As duas checagens, cada uma correta sozinha, formavam uma
// tenaz: a única saída era a ficha apontar para uma suíte que não é a dela.
// Um glob passa a valer como caminho quando ALGUM arquivo casa com ele — o que
// preserva as duas coisas que o portão quer: o alvo existe de verdade, e o CI
// o executa.
const casaAlgum = (padrao) => {
  const barra = padrao.lastIndexOf("/");
  const dir = barra >= 0 ? padrao.slice(0, barra) : ".";
  const nome = barra >= 0 ? padrao.slice(barra + 1) : padrao;
  if (!existe(dir)) return false;
  const re = new RegExp(`^${nome.split("*").map((x) => x.replace(/[.+?^${}()|[\]\\]/g, "\\$&")).join("[^/]*")}$`);
  return readdirSync(join(RAIZ, dir)).some((f) => re.test(f));
};

for (const e of arestas.filter((x) => x.rel === "PROVADA_POR")) {
  const suite = e.pa.slice("suite:".length);
  checar(suite.includes("*") ? casaAlgum(suite) : existe(suite),
    `${e.f}: o campo "prova" aponta para "${suite}", que não existe`);
  checar(yml.includes(suite), `${e.f}: a suíte "${suite}" não é executada pelo ${CI} — invariante que não roda apodrece`);
}
for (const e of arestas.filter((x) => x.rel === "SUBSTITUI")) {
  checar(nos.some((n) => n.id === e.pa), `${e.f}: o campo "substitui" cita a ficha "${e.pa.slice(6)}", que não existe`);
}

// ---------------------------------------------------------------------------
// 3. ÂNCORAS — a ficha descobre sozinha que envelheceu
// ---------------------------------------------------------------------------
//
// Três estados, e os três são diferentes de propósito:
//   • sem `ancora`            → nada a conferir (a maioria das fichas)
//   • `ancora` sem `ancora_sha` → AVISO: a ficha nunca foi confirmada contra o
//     código. Não reprova, porque uma ficha nova legitimamente nasce assim — o
//     texto do aviso diz o valor a colar.
//   • `ancora_sha` != hash atual → REPROVA, nomeando a ficha.
const fichas = nos.filter((n) => n.t === "ficha");
for (const f of fichas) {
  if (!f.anc) continue;
  const [caminho, simbolo] = String(f.anc).split("#");
  checar(existe(caminho), `${f.f}: a âncora aponta para "${caminho}", que não existe`);
  if (!existe(caminho)) continue;
  checar(
    ler(caminho).includes(simbolo),
    `${f.f}: a âncora cita o símbolo "${simbolo}", que não está mais em "${caminho}" — ou ele foi renomeado, ou a ficha fala de código que sumiu`,
  );
  if (!f.sha) continue;
  if (!f.anc_sha) {
    avisos.push(`${f.f}: âncora ainda não confirmada. Releia a ficha contra ${f.anc} e acrescente ao cabeçalho:  ancora_sha: ${f.sha}`);
    continue;
  }
  checar(
    f.anc_sha === f.sha,
    `${f.f}: SUSPEITA — a região ${f.anc} mudou desde a confirmação (${f.anc_sha} → ${f.sha}). `
    + "Releia a ficha contra o código: se ela continua verdadeira, atualize `ancora_sha`; se não, corrija o texto.",
  );
}

// ---------------------------------------------------------------------------
// 4. COBERTURA — o índice não pode encolher em silêncio
// ---------------------------------------------------------------------------
const PISO = ".claude/conhecimento/cobertura.json";
const contagem = {};
for (const n of nos) contagem[n.t] = (contagem[n.t] ?? 0) + 1;
for (const e of arestas) contagem[e.rel] = (contagem[e.rel] ?? 0) + 1;

if (existe(PISO)) {
  const piso = JSON.parse(ler(PISO));
  for (const [chave, minimo] of Object.entries(piso.minimos)) {
    const atual = contagem[chave] ?? 0;
    checar(
      atual >= minimo,
      `cobertura: "${chave}" caiu de um piso de ${minimo} para ${atual}. `
      + "Ou a extração parou de casar, ou o repositório encolheu — as duas exigem olhar, e a primeira é o defeito silencioso.",
    );
  }
} else {
  falhas.push(`${PISO} não existe — sem piso declarado, um índice vazio passa por índice limpo (regra 7)`);
}

// A OUTRA METADE DA REGRA 7: migrations e funções têm de estar TODAS no grafo.
// Comparar contra o disco é o que separa "não existe" de "a regex parou de
// casar" — a contagem sozinha não faria essa distinção.
const migrationsNoDisco = readdirSync(join(RAIZ, "Supabase/migrations")).filter((p) => p.endsWith(".sql")).length;
checar(
  (contagem.migration ?? 0) === migrationsNoDisco,
  `cobertura: o disco tem ${migrationsNoDisco} migrations e o grafo tem ${contagem.migration ?? 0} — a extração está perdendo arquivo`,
);

// ---------------------------------------------------------------------------
// Saída
// ---------------------------------------------------------------------------
for (const a of avisos) console.log(`  ~ ${a}`);
if (falhas.length > 0) {
  console.error(`\n${falhas.length} falha(s):`);
  for (const f of falhas) console.error(`  ✗ ${f}`);
  console.error(`\n${ok} verificações OK / ${falhas.length} falhas`);
  process.exit(1);
}
console.log(`${ok} verificações OK / 0 falhas${avisos.length ? ` / ${avisos.length} aviso(s)` : ""}`);
console.log("CONHECIMENTO OK — toda ficha aponta para arquivo que existe e suíte que roda");
console.log("ÂNCORAS OK — nenhuma ficha afirma um número cuja região de código mudou");
console.log(`COBERTURA OK — ${contagem.migration} migrations, ${contagem.fn} funções, ${contagem.CHAMA} chamadas, ${contagem.portao} portões`);
