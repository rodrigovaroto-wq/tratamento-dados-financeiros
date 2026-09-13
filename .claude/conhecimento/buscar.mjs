#!/usr/bin/env node
// O BRIEFING — o comando que a sessão roda ANTES de abrir arquivo.
//
//   node .claude/conhecimento/buscar.mjs "upload 413 vercel"
//   node .claude/conhecimento/buscar.mjs fn_reconciliar_caso
//   node .claude/conhecimento/buscar.mjs "kit básico" --largo    # 3x mais linhas
//   node .claude/conhecimento/buscar.mjs --arquivo portal/src/lib/export.ts
//
// ---------------------------------------------------------------------------
// O QUE ELE DEVOLVE, E O QUE ELE DELIBERADAMENTE NÃO DEVOLVE
// ---------------------------------------------------------------------------
//
// Devolve PONTEIROS: qual ficha ler, qual arquivo abrir e em que linha, qual
// portão prova aquilo, qual migration criou aquela função, que sessão do
// HANDOFF conta a história. Cabe em ~60 linhas.
//
// NÃO devolve o conteúdo. A tentação de colar o corpo da ficha aqui é a mesma
// que produziu um `ESTADO.md` de 4.373 linhas: quem carrega tudo para não
// precisar escolher acaba carregando tudo sempre. Uma ficha tem ~30 linhas e é
// lida quando for a certa — o briefing existe para dizer QUAL é a certa.
//
// ---------------------------------------------------------------------------
// A PARTE HISTÓRICA VEM DO GIT, NA HORA
// ---------------------------------------------------------------------------
//
// `git log --grep` é o índice de commits, já existe e nunca envelhece. O grafo
// versionado guarda só o que o git NÃO sabe: a ligação entre migration, função,
// nó do n8n, portão, ficha e sessão. Ver a seção 7 do `indexar.mjs`.
//
// ---------------------------------------------------------------------------
// O SILÊNCIO É DECLARADO — regra 7
// ---------------------------------------------------------------------------
//
// Quando não acha nada, este comando DIZ que não achou e diz o que foi
// procurado. Um briefing curto e um briefing vazio não podem ter a mesma
// aparência: a sessão que lê "nada sobre isso" precisa saber se o índice
// procurou e não achou, ou se ela escreveu o termo de um jeito que o índice
// não conhece.

import { readFileSync, existsSync } from "node:fs";
import { execFileSync } from "node:child_process";

const RAIZ = new URL("../..", import.meta.url).pathname.replace(/\/$/, "");
const GRAFO = `${RAIZ}/.claude/conhecimento/grafo.jsonl`;

const argv = process.argv.slice(2);
const largo = argv.includes("--largo");
const porArquivo = argv.includes("--arquivo");
const termosCrus = argv.filter((a) => !a.startsWith("--"));

if (termosCrus.length === 0) {
  console.log('uso: node .claude/conhecimento/buscar.mjs "<assunto>" [--largo] [--arquivo <caminho>]');
  process.exit(2);
}
if (!existsSync(GRAFO)) {
  console.error("grafo.jsonl não existe — rode `node .claude/conhecimento/indexar.mjs`.");
  process.exit(1);
}

/** Sem acento e em minúscula: "BALANÇO" e "balanco" têm de casar. */
const normalizar = (s) => String(s).normalize("NFD").replace(/[̀-ͯ]/g, "").toLowerCase();

// Termos de 1 e 2 letras não discriminam nada num repositório deste tamanho e
// só inflam o resultado; "73" e "0164" discriminam muito, então número passa.
const termos = termosCrus
  .flatMap((t) => normalizar(t).split(/[\s,]+/))
  .filter((t) => t.length > 2 || /^\d+$/.test(t));

const nos = new Map();
const saindo = new Map(); // id → arestas que partem dele
const chegando = new Map(); // id → arestas que chegam nele
for (const linha of readFileSync(GRAFO, "utf8").split("\n")) {
  if (!linha) continue;
  const o = JSON.parse(linha);
  if (o.k === "n") nos.set(o.id, o);
  else {
    if (!saindo.has(o.de)) saindo.set(o.de, []);
    saindo.get(o.de).push(o);
    if (!chegando.has(o.pa)) chegando.set(o.pa, []);
    chegando.get(o.pa).push(o);
  }
}

// ---------------------------------------------------------------------------
// A PONTUAÇÃO — declarada, para o resultado ser reproduzível
// ---------------------------------------------------------------------------
//
// Casar no ID vale mais que casar no texto, e casar no texto vale mais que
// casar no caminho: quem procura "fn_reconciliar_caso" quer a função, não os
// nove arquivos cujo caminho contém "caso". Ficha pesa mais que o resto porque
// ela é a única coisa aqui escrita para ser lida por quem chega agora.
// `kw` são as palavras do CORPO da ficha, e existem só nela (ver indexar.mjs).
// Pesam menos que o título de propósito: casar no título é o assunto da ficha,
// casar no corpo é o assunto ter sido MENCIONADO nela.
const PESO = { id: 6, txt: 3, kw: 2, f: 1 };
const BONUS_TIPO = { ficha: 6, migration: 1, fn: 0, portao: 1, sessao: 0, suite: 1, arquivo: 0, no8n: 1 };

function pontuar(n) {
  const id = normalizar(n.id);
  const txt = normalizar(n.txt ?? "");
  const f = normalizar(n.f ?? "");
  const kw = normalizar(n.kw ?? "");
  let p = 0;
  let casou = 0;
  for (const t of termos) {
    let aqui = 0;
    if (id.includes(t)) aqui += PESO.id;
    if (txt.includes(t)) aqui += PESO.txt;
    if (kw.includes(t)) aqui += PESO.kw;
    if (f.includes(t)) aqui += PESO.f;
    if (aqui > 0) casou += 1;
    p += aqui;
  }
  // TODOS os termos casando vale mais que um termo casando três vezes: numa
  // busca de duas palavras, é o nó que junta as duas que interessa.
  if (casou === termos.length && termos.length > 1) p *= 2;
  // O BÔNUS POR TIPO SÓ SE APLICA A QUEM JÁ CASOU, e ele estava declarado e
  // NUNCA APLICADO na primeira versão deste arquivo — o defeito central desta
  // casa, dentro do próprio índice. O sintoma era mudo: "upload lote grande
  // 413" devolvia dez funções `fn_*lote*` antes da ficha que responde, porque
  // "lote" casa em meio repositório e nada empurrava a ficha para cima.
  if (p > 0) p += BONUS_TIPO[n.t] ?? 0;
  return p;
}

const alvoArquivo = porArquivo ? termosCrus[0].replace(/^\.\//, "") : null;
const achados = [...nos.values()]
  .map((n) => ({ n, p: alvoArquivo ? (n.f === alvoArquivo || n.id === `arquivo:${alvoArquivo}` ? 10 : 0) : pontuar(n) }))
  .filter((x) => x.p > 0)
  // Desempate pelo id: duas execuções com o mesmo grafo dão o mesmo briefing.
  .sort((a, b) => b.p - a.p || a.n.id.localeCompare(b.n.id));

// OS TETOS POR TIPO — e eles são um ORÇAMENTO, não um gosto. O briefing existe
// para caber numa leitura: medido em 13/09/2026, a consulta mais larga das
// cinco da linha de base devolve ~3.500 bytes com estes números e passava de
// 4.200 com os anteriores. Quem precisa de mais pede `--largo`, que é quando a
// sessão já decidiu que vale o custo.
const TETO = { ficha: largo ? 8 : 3, migration: largo ? 8 : 3, fn: largo ? 10 : 3,
  portao: largo ? 6 : 2, suite: largo ? 6 : 2, sessao: largo ? 8 : 2,
  no8n: largo ? 6 : 2, arquivo: largo ? 10 : 3 };

const porTipo = new Map();
for (const { n, p } of achados) {
  if (!porTipo.has(n.t)) porTipo.set(n.t, []);
  const lista = porTipo.get(n.t);
  if (lista.length < (TETO[n.t] ?? 3)) lista.push({ n, p });
}

const linhas = [];
const diz = (s = "") => linhas.push(s);
const local = (n) => (n.f ? `${n.f}${n.l ? `:${n.l}` : ""}` : "");

// ---- fichas: o que alguém já aprendeu sobre isto --------------------------
for (const { n } of porTipo.get("ficha") ?? []) {
  const suspeita = n.anc && n.anc_sha && n.sha && n.anc_sha !== n.sha;
  diz(`FICHA${suspeita ? " [SUSPEITA: a âncora mudou desde a confirmação]" : ""}  ${n.f}`);
  diz(`  ${(n.d ?? n.txt ?? "").slice(0, 140)}`);
  const toca = (saindo.get(n.id) ?? []).filter((e) => e.rel === "TOCA").map((e) => e.pa.slice(8));
  const prova = (saindo.get(n.id) ?? []).filter((e) => e.rel === "PROVADA_POR").map((e) => e.pa.slice(6));
  if (toca.length) diz(`  toca:  ${toca.join(", ")}`);
  if (prova.length) diz(`  prova: ${prova.join(", ")}`);
  else if (n.tp === "invariante") diz("  prova: NENHUMA — afirmação sem quem a desminta");
}

// ---- funções: quem cria e quem chama -------------------------------------
for (const { n } of porTipo.get("fn") ?? []) {
  const criada = (chegando.get(n.id) ?? []).find((e) => e.rel === "CRIA");
  const chamada = (chegando.get(n.id) ?? []).filter((e) => e.rel === "CHAMA");
  diz(`FUNÇÃO ${n.id.slice(3)}`);
  if (criada) diz(`  criada por ${criada.de.slice(10)} — ${criada.f}:${criada.l}`);
  if (chamada.length) {
    const onde = chamada.slice(0, largo ? 12 : 5).map((e) => `${e.f ?? e.de}${e.l ? `:${e.l}` : ""}`);
    diz(`  chamada em ${chamada.length}: ${onde.join(", ")}${chamada.length > onde.length ? ", …" : ""}`);
  } else {
    diz("  chamada em NENHUM lugar do código — ou é só de teste, ou o nome mudou");
  }
}

// ---- migrations ----------------------------------------------------------
for (const { n } of porTipo.get("migration") ?? []) {
  const cria = (saindo.get(n.id) ?? []).filter((e) => e.rel === "CRIA").map((e) => e.pa.slice(3));
  diz(`MIGRATION ${n.id.slice(10)}  ${n.txt}`);
  diz(`  ${n.f}${cria.length ? `\n  cria: ${cria.join(", ")}` : ""}`);
}

// ---- portões: o que reprova se isto mudar --------------------------------
for (const { n } of porTipo.get("portao") ?? []) {
  const roda = (saindo.get(n.id) ?? []).filter((e) => e.rel === "RODA").map((e) => e.pa.slice(8));
  diz(`PORTÃO "${n.txt}"  ${local(n)}`);
  if (roda.length) diz(`  roda: ${roda.join(", ")}`);
}

// ---- suítes --------------------------------------------------------------
for (const { n } of porTipo.get("suite") ?? []) {
  const provaFichas = (chegando.get(n.id) ?? []).filter((e) => e.rel === "PROVADA_POR").length;
  diz(`SUÍTE ${n.f}${provaFichas ? `  (prova ${provaFichas} ficha(s))` : ""}`);
}

// ---- nós do n8n ----------------------------------------------------------
for (const { n } of porTipo.get("no8n") ?? []) {
  const chama = (saindo.get(n.id) ?? []).filter((e) => e.rel === "CHAMA").map((e) => e.pa.slice(3));
  diz(`NÓ n8n "${n.id.slice(5)}"  ${n.f}${chama.length ? `\n  chama: ${chama.join(", ")}` : ""}`);
}

// ---- sessões do HANDOFF --------------------------------------------------
for (const { n } of porTipo.get("sessao") ?? []) {
  diz(`SESSÃO ${n.txt}`);
  diz(`  HANDOFF.md:${n.l}`);
}

// ---- arquivos ------------------------------------------------------------
for (const { n } of porTipo.get("arquivo") ?? []) {
  const fichas = (chegando.get(n.id) ?? []).filter((e) => e.rel === "TOCA").length;
  const portoes = (chegando.get(n.id) ?? []).filter((e) => e.rel === "RODA").length;
  const marca = [fichas ? `${fichas} ficha(s)` : "", portoes ? `${portoes} portão(ões)` : ""].filter(Boolean).join(", ");
  diz(`ARQUIVO ${n.f}${marca ? `  — ${marca}` : "  — sem ficha e sem portão"}`);
}

// ---- história: do git, na hora -------------------------------------------
try {
  const padrao = termosCrus.join(" ");
  const log = execFileSync(
    "git",
    ["log", "--format=%h %ad %s", "--date=short", "-i", `--grep=${padrao}`, `-${largo ? 8 : 3}`],
    { cwd: RAIZ, encoding: "utf8" },
  ).trim();
  if (log) {
    diz("COMMITS (git log --grep, na hora — `git show <sha>` traz o defeito, a causa e a medição)");
    for (const l of log.split("\n")) diz(`  ${l}`);
  }
} catch {
  // sem git aqui: o resto do briefing continua válido
}

// ---------------------------------------------------------------------------
// A SAÍDA — e o vazio que se declara
// ---------------------------------------------------------------------------
if (linhas.length === 0) {
  console.log(`NADA ENCONTRADO para: ${termos.join(", ")}`);
  console.log(`O índice tem ${nos.size} nós. Isto é "procurei e não achei", não "não procurei".`);
  console.log("Se o termo for novo no projeto, é caso de ficha nova — ver .claude/conhecimento/INSTRUCOES.md.");
  process.exit(0);
}
console.log(linhas.join("\n"));
console.log(`\n— ${achados.length} nó(s) casaram; acima estão os mais fortes por tipo. \`--largo\` mostra mais.`);
