#!/usr/bin/env node
// O INDEXADOR — lê o repositório e emite `grafo.jsonl`. Nada aqui é digitado à mão.
//
//   node .claude/conhecimento/indexar.mjs           # regera grafo.jsonl
//   node .claude/conhecimento/indexar.mjs --contar  # só imprime a contagem por tipo
//
// ---------------------------------------------------------------------------
// O PRINCÍPIO, e ele é a razão de este arquivo existir em vez de um documento
// ---------------------------------------------------------------------------
//
// **Derivar, nunca duplicar.** Toda aresta abaixo tem uma REGRA DE EXTRAÇÃO —
// um caminho de arquivo e uma expressão. Nenhuma é escrita por alguém, e por
// isso nenhuma pode ficar para trás em relação ao código: ela É o código, lido.
//
// Isto não é preferência de estilo. Este repositório já mediu DUAS VEZES o custo
// do contrário: na sessão 82 o `CLAUDE.md` listava quatro suítes e o CI rodava
// seis (18 asserts nunca executados), e na 86 os dois medidores estavam no CI e
// fora do `CLAUDE.md`. Um índice escrito à mão seria a terceira ocorrência do
// mesmo defeito, só que maior.
//
// ---------------------------------------------------------------------------
// O FORMATO — JSONL, uma linha por nó ou aresta, ORDENADO
// ---------------------------------------------------------------------------
//
//   nó     {"k":"n","id":"migration:0164","t":"migration","f":"Supabase/...","txt":"..."}
//   aresta {"k":"e","de":"migration:0164","rel":"CRIA","pa":"fn:fn_x","f":"...","l":12}
//
// A ordenação é determinística (por `k`, depois pelo texto da linha) porque o
// arquivo é VERSIONADO e passa por `git diff --exit-code` no CI — o mesmo portão
// que já protege os quatro workflows do n8n, as três fixtures do book e o
// `schema.sql`. Sem ordem estável, cada execução produziria um diff diferente e
// o portão viraria ruído; com ela, o diff do PR mostra exatamente o conhecimento
// que mudou junto do código que o mudou.
//
// Chaves curtas de propósito: quem lê este arquivo inteiro é o `buscar.mjs`, e
// um nome de campo repetido 6.000 vezes é custo sem leitor.
//
// ---------------------------------------------------------------------------
// O QUE É INDEXADO, com a regra de cada um
// ---------------------------------------------------------------------------
//
//   migration   Supabase/migrations/NNNN_*.sql — o número e o slug do nome
//   fn          `create [or replace] function <nome>` dentro de uma migration
//   arquivo     qualquer caminho que apareça numa aresta (não o repositório todo)
//   suite       portal/scripts/verificar-*.mts, N8N/medir-*.mjs, N8N/test/*.test.mjs,
//               Verificação/*.mts, .claude/verificar-comandos.mjs
//   portao      cada passo `- name:` de .github/workflows/suites.yml
//   no8n        cada nó dos workflows publicados em N8N/*.json
//   ficha       .claude/memory/*.md e .claude/conhecimento/fichas/*.md
//   sessao      cada cabeçalho `## Sessão N` do HANDOFF.md
//   (commits NÃO entram: `git log` já é esse índice — ver a seção 7)
//
//   CRIA        migration → fn
//   CHAMA       arquivo|no8n → fn
//   RODA        portao → arquivo (o que o passo do CI executa)
//   TOCA        ficha → arquivo          (cabeçalho da ficha)
//   PROVADA_POR ficha → suite            (cabeçalho da ficha)
//   SUBSTITUI   ficha → ficha            (cabeçalho da ficha)
//   CITA        sessao → migration
//
// ---------------------------------------------------------------------------
// A ÂNCORA — como uma ficha descobre sozinha que envelheceu
// ---------------------------------------------------------------------------
//
// Uma ficha pode declarar `ancora: caminho#SIMBOLO`. O indexador acha o símbolo
// no arquivo, pega as 40 linhas a partir dele, e grava o hash dessa REGIÃO no
// nó da ficha (`sha`). A ficha guarda, no cabeçalho, o hash contra o qual ela
// foi confirmada (`ancora_sha`). Quando os dois divergem, o `conferir.mjs`
// reprova e nomeia a ficha: o número que ela afirma mudou de lugar.
//
// É hash de REGIÃO NOMEADA, não do arquivo inteiro, e a distinção vem de um
// defeito real deste repositório (`.claude/memory/portao-pode-reprovar-por-ruido.md`):
// um portão que acusa quando alguém corrige um comentário do outro lado do
// arquivo ensina a ignorar o portão.

import { readFileSync, readdirSync, writeFileSync, existsSync, statSync } from "node:fs";
import { createHash } from "node:crypto";
import { execFileSync } from "node:child_process";
import { join, relative } from "node:path";

const RAIZ = new URL("../..", import.meta.url).pathname.replace(/\/$/, "");
const SAIDA = join(RAIZ, ".claude/conhecimento/grafo.jsonl");

/** Linhas do grafo. `nos` é mapa para o último vencer (id único). */
const nos = new Map();
const arestas = new Set();

const no = (id, t, f, txt = "", extra = {}) => {
  nos.set(id, { k: "n", id, t, ...(f ? { f } : {}), ...(txt ? { txt } : {}), ...extra });
};
const aresta = (de, rel, pa, f = "", l = 0) => {
  arestas.add(JSON.stringify({ k: "e", de, rel, pa, ...(f ? { f } : {}), ...(l ? { l } : {}) }));
};

const ler = (p) => readFileSync(join(RAIZ, p), "utf8");
const existe = (p) => existsSync(join(RAIZ, p));

// TUDO QUE O GIT IGNORA FICA FORA DO GRAFO, e a razão é um portão vermelho medido
// em 21/09/2026 (PR #238). Antes desta linha, a lista de exclusão era três NOMES
// (`node_modules`, `.git`, `.next`), e qualquer outro diretório gerado entrava no
// índice. Foi o que aconteceu: `Verificação/variacoes.mts` grava 51 arquivos em
// `Verificação/saida/` (gitignored, `.gitignore:21`), a sessão rodou o `variacoes`
// ANTES do `indexar` — que é a ordem em que o bloco de comandos do `CLAUDE.md` os
// lista —, e o grafo commitado saiu com **50 nós e arestas que não existem num
// checkout limpo**. No runner esses arquivos não existem, o grafo regerado sai sem
// eles, e o `git diff --exit-code` do portão reprovou.
//
// O defeito real não era o commit: era o conteúdo do grafo DEPENDER de quais
// scripts a sessão rodou antes de indexar. Um portão cujo veredito é função do
// estado local de quem commitou não está medindo o repositório — é a regra 7 do
// CLAUDE.md aplicada à própria ferramenta de memória. Perguntar ao git, em vez de
// manter uma lista de nomes à mão, é o mesmo princípio de "derivar, nunca
// duplicar" que o cabeçalho deste arquivo defende: o `.gitignore` já é a
// declaração de o que não é código do repositório, e mantê-la copiada aqui seria
// a terceira ocorrência do defeito que o cabeçalho cita duas vezes.
//
// `-z` é OBRIGATÓRIO, não estilo: sem ele o git aplica `core.quotePath` e devolve
// `"Verifica\303\247\303\243o/saida/"` — com aspas e escapes octais —, que nunca
// casaria com o caminho real. Este repositório tem acento em nome de diretório de
// topo (`Verificação/`), então o caso quebrado é o caso comum aqui.
const IGNORADOS = new Set(
  execFileSync("git", ["ls-files", "-z", "-o", "-i", "--exclude-standard", "--directory"],
    { cwd: RAIZ, encoding: "utf8", maxBuffer: 64 * 1024 * 1024 })
    .split("\0")
    .filter(Boolean)
    .map((p) => p.replace(/\/$/, "")),
);

/** Percorre um diretório do repositório, pulando o que o git ignora. */
function* arquivos(dir, filtro = () => true) {
  const abs = join(RAIZ, dir);
  if (!existsSync(abs)) return;
  for (const nome of readdirSync(abs).sort()) {
    // DOIS casos que `ls-files -i` NÃO cobre, e os dois foram CONFERIDOS em
    // 21/09/2026 com `git check-ignore -q` antes de esta linha encolher:
    //   `.git`   — o git não o "ignora", ele o desconhece; nunca sai em ls-files.
    //   `.next`  — **NÃO está no `.gitignore` deste repositório** (medido: só
    //              `portal/node_modules` sai ignorado; `portal/.next` não). Trocar
    //              este pulo por "pergunte ao git" faria o build do Next entrar no
    //              grafo na primeira sessão que rodasse `next build` — o mesmo
    //              defeito que esta fatia corrige, ao contrário. Fica por NOME até
    //              que alguém decida acrescentá-lo ao `.gitignore`, que é outra
    //              fatia (e o `git status` hoje o mostra como não rastreado).
    if (nome === ".git" || nome === ".next") continue;
    const p = join(abs, nome);
    const rel = relative(RAIZ, p);
    if (IGNORADOS.has(rel)) continue;
    if (statSync(p).isDirectory()) yield* arquivos(rel, filtro);
    else if (filtro(rel)) yield rel;
  }
}

/** Número da linha (1-based) de um índice de caractere. */
const linhaDe = (texto, idx) => texto.slice(0, idx).split("\n").length;

// ---------------------------------------------------------------------------
// 1. MIGRATIONS e as FUNÇÕES que elas criam
// ---------------------------------------------------------------------------
//
// O nome do arquivo é mnemônico neste repositório ("0157_o_combinado_que_travava
// _o_kit_basico"), então o slug vira o texto de busca do nó — é ele que faz
// "kit básico" achar a 0157 sem ninguém ter escrito um índice.
const MIGRATIONS = [...arquivos("Supabase/migrations", (p) => p.endsWith(".sql"))];
for (const p of MIGRATIONS) {
  const base = p.split("/").pop();
  const num = base.slice(0, 4);
  const slug = base.slice(5).replace(/\.sql$/, "").replace(/_/g, " ");
  no(`migration:${num}`, "migration", p, slug);
  const sql = ler(p);
  const re = /create\s+(?:or\s+replace\s+)?function\s+(?:public\.)?([a-z0-9_]+)/gi;
  let m;
  while ((m = re.exec(sql))) {
    const fn = m[1].toLowerCase();
    no(`fn:${fn}`, "fn", p, fn.replace(/^fn_/, "").replace(/_/g, " "));
    aresta(`migration:${num}`, "CRIA", `fn:${fn}`, p, linhaDe(sql, m.index));
  }
}

// ---------------------------------------------------------------------------
// 2. QUEM CHAMA CADA FUNÇÃO — a pergunta que hoje custa um grep no repo inteiro
// ---------------------------------------------------------------------------
//
// Duas formas no código: `.rpc("fn_x")` no portal e a citação nua `fn_x(` nos
// geradores e nas verificações. A aresta só é criada se a função EXISTE numa
// migration — assim um `fn_` escrito errado não vira nó fantasma, e a diferença
// entre "ninguém chama" e "o nome está errado" fica visível no `conferir.mjs`.
const FN_CONHECIDAS = new Set([...nos.keys()].filter((k) => k.startsWith("fn:")).map((k) => k.slice(3)));
const CODIGO = (p) =>
  (p.startsWith("portal/src/") || p.startsWith("portal/scripts/") || p.startsWith("N8N/")
    || p.startsWith("Verificação/") || p.startsWith("Supabase/test/"))
  && /\.(ts|tsx|mts|mjs|js|json|sql)$/.test(p);
for (const p of arquivos(".", CODIGO)) {
  const texto = ler(p);
  if (!texto.includes("fn_")) continue;
  const re = /\bfn_[a-z0-9_]+/gi;
  let m;
  const vistos = new Set();
  while ((m = re.exec(texto))) {
    const fn = m[0].toLowerCase();
    if (!FN_CONHECIDAS.has(fn) || vistos.has(fn)) continue;
    vistos.add(fn);
    no(`arquivo:${p}`, "arquivo", p, p.split("/").pop());
    aresta(`arquivo:${p}`, "CHAMA", `fn:${fn}`, p, linhaDe(texto, m.index));
  }
}

// ---------------------------------------------------------------------------
// 3. OS NÓS DO N8N — lidos do JSON PUBLICADO, que é o que roda
// ---------------------------------------------------------------------------
//
// Do JSON commitado, não do gerador: é o JSON que o dono importa no n8n, e o CI
// já garante que os dois concordam (`git diff --exit-code` depois dos quatro
// geradores). Ler o gerador aqui seria indexar a intenção em vez do que roda.
for (const p of arquivos("N8N", (x) => /^N8N\/workflow[.\w-]*\.json$/.test(x))) {
  let wf;
  try { wf = JSON.parse(ler(p)); } catch { continue; }
  for (const n of wf.nodes ?? []) {
    const id = `no8n:${n.name}`;
    no(id, "no8n", p, `${n.name} ${String(n.type ?? "").split(".").pop()}`);
    const params = JSON.stringify(n.parameters ?? {});
    for (const fn of params.match(/\bfn_[a-z0-9_]+/gi) ?? []) {
      if (FN_CONHECIDAS.has(fn.toLowerCase())) aresta(id, "CHAMA", `fn:${fn.toLowerCase()}`, p);
    }
  }
}

// ---------------------------------------------------------------------------
// 4. OS PORTÕES — cada passo do CI, e o que ele executa
// ---------------------------------------------------------------------------
//
// Esta é a aresta que responde "mudar este arquivo reprova alguma coisa?" — a
// pergunta cuja resposta hoje só existe dentro dos comentários do `suites.yml`.
const CI = ".github/workflows/suites.yml";
if (existe(CI)) {
  const yml = ler(CI);
  const passos = [...yml.matchAll(/^\s*-\s+name:\s*(.+)$/gm)];
  for (let i = 0; i < passos.length; i++) {
    const nome = passos[i][1].trim();
    const ini = passos[i].index;
    const fim = i + 1 < passos.length ? passos[i + 1].index : yml.length;
    const bloco = yml.slice(ini, fim);
    const id = `portao:${nome}`;
    no(id, "portao", CI, nome, { l: linhaDe(yml, ini) });
    // Todo caminho de arquivo citado no bloco do passo — é o que ele roda.
    for (const cam of bloco.match(/[\w./À-ſ-]+\.(mts|mjs|js|sh|py|ts)/g) ?? []) {
      const limpo = cam.replace(/^\.\//, "");
      if (existe(limpo)) {
        no(`arquivo:${limpo}`, "arquivo", limpo, limpo.split("/").pop());
        aresta(id, "RODA", `arquivo:${limpo}`, CI, linhaDe(yml, ini));
      }
    }
  }
}

// As suítes e medidores ganham tipo próprio: eles são o que PROVA, e uma busca
// por um assunto precisa poder devolver "e quem desmente isto é esta suíte".
const EH_SUITE = (p) =>
  /^portal\/scripts\/verificar-[\w-]+\.mts$/.test(p) || /^N8N\/medir-[\w-]+\.mjs$/.test(p)
  || /^N8N\/test\/.+\.test\.mjs$/.test(p) || /^Verificação\/.+\.mts$/.test(p)
  || p === ".claude/verificar-comandos.mjs" || p === "Supabase/test/run.sh";
for (const p of arquivos(".", EH_SUITE)) {
  no(`suite:${p}`, "suite", p, p.split("/").pop().replace(/[-.]/g, " "));
}

// ---------------------------------------------------------------------------
// 5. AS FICHAS — o único lugar onde alguém escreve, e mesmo assim estruturado
// ---------------------------------------------------------------------------
const FICHAS = [
  ...arquivos(".claude/memory", (p) => p.endsWith(".md") && !p.endsWith("MEMORY.md") && !p.endsWith("INSTRUCTIONS.md")),
  ...arquivos(".claude/conhecimento/fichas", (p) => p.endsWith(".md")),
];
/** Cabeçalho YAML simples (só os campos que usamos) — sem dependência nova. */
function cabecalho(texto) {
  const m = /^---\n([\s\S]*?)\n---\n/.exec(texto);
  if (!m) return null;
  const campos = {};
  let chaveLista = null;
  for (const linha of m[1].split("\n")) {
    const item = /^\s+-\s+(.+)$/.exec(linha);
    if (item && chaveLista) { campos[chaveLista].push(item[1].trim()); continue; }
    const par = /^([a-z_]+):\s*(.*)$/.exec(linha);
    if (!par) continue;
    chaveLista = null;
    if (par[2] === "") { campos[par[1]] = []; chaveLista = par[1]; }
    else if (par[2] === "[]") campos[par[1]] = [];
    else campos[par[1]] = par[2].trim();
  }
  return campos;
}
/** O hash da região ancorada: 40 linhas a partir da primeira ocorrência do símbolo. */
function hashDaAncora(ancora) {
  const [caminho, simbolo] = String(ancora).split("#");
  if (!caminho || !simbolo || !existe(caminho)) return null;
  const texto = ler(caminho);
  const idx = texto.indexOf(simbolo);
  if (idx < 0) return null;
  const linhas = texto.split("\n");
  const inicio = linhaDe(texto, idx) - 1;
  const regiao = linhas.slice(inicio, inicio + 40).join("\n");
  return createHash("sha256").update(regiao).digest("hex").slice(0, 12);
}
for (const p of FICHAS) {
  const texto = ler(p);
  const cab = cabecalho(texto);
  const titulo = (/^#\s+(.+)$/m.exec(texto)?.[1] ?? p.split("/").pop().replace(/\.md$/, "")).trim();
  // O texto de busca da ficha são o título e os subtítulos — não o corpo. Quem
  // precisa do corpo abre o arquivo, que tem ~30 linhas; carregar o corpo no
  // índice encheria o grafo com a prosa que ele existe para NÃO carregar.
  const subtitulos = [...texto.matchAll(/^#{2,3}\s+(.+)$/gm)].map((m) => m[1]).join(" ");
  // AS PALAVRAS DO CORPO, e só para a ficha. Sem isto, a ficha do 413 não casava
  // com "413": o índice lia título e subtítulo, e o número mora no corpo. Medido
  // em 13/09/2026 — "upload lote grande 413" devolvia dez funções `fn_*lote*` e
  // nenhuma ficha. A ficha é o nó de maior valor do grafo e não pode ser o mais
  // difícil de achar.
  //
  // Só a ficha: o corpo de um arquivo de código no índice seria o repositório
  // duplicado. Palavra de 4+ letras (ou número), sem repetição, teto de 150 —
  // uma ficha de 30 linhas cabe inteira nisso, e o teto impede que uma ficha
  // longa demais afogue as outras na pontuação.
  const palavras = [...new Set(
    (cab ? texto.slice(texto.indexOf("\n---\n") + 5) : texto)
      .toLowerCase().match(/[\wÀ-ÿ]{4,}|\b\d{3,}\b/g) ?? [],
  )].slice(0, 150).join(" ");
  const id = `ficha:${cab?.id ?? p.split("/").pop().replace(/\.md$/, "")}`;
  const sha = cab?.ancora ? hashDaAncora(cab.ancora) : null;
  // A LINHA QUE O BRIEFING MOSTRA é o `description` do cabeçalho — as 24 fichas
  // de `.claude/memory/` já o tinham, e a primeira versão deste indexador o
  // jogava fora e mostrava o nome do arquivo no lugar ("no-postgres-novo-vai-
  // como-ramo-terminal"), que não diz nada a quem ainda não leu a ficha.
  const desc = (cab?.description ?? "").trim();
  no(id, "ficha", p, `${desc || titulo} ${subtitulos}`, {
    ...(desc ? { d: desc } : {}),
    kw: palavras,
    ...(cab?.tipo ? { tp: cab.tipo } : {}),
    ...(cab?.ancora ? { anc: cab.ancora } : {}),
    ...(sha ? { sha } : {}),
    ...(cab?.ancora_sha ? { anc_sha: cab.ancora_sha } : {}),
  });
  for (const alvo of cab?.toca ?? []) {
    no(`arquivo:${alvo}`, "arquivo", alvo, alvo.split("/").pop());
    aresta(id, "TOCA", `arquivo:${alvo}`, p);
  }
  const prova = cab?.prova;
  for (const s of Array.isArray(prova) ? prova : prova ? [prova] : []) {
    aresta(id, "PROVADA_POR", `suite:${s}`, p);
  }
  for (const outra of cab?.substitui ?? []) aresta(id, "SUBSTITUI", `ficha:${outra}`, p);
}

// ---------------------------------------------------------------------------
// 6. AS SESSÕES do HANDOFF — 69 cabeçalhos que hoje só o `grep` alcança
// ---------------------------------------------------------------------------
if (existe("HANDOFF.md")) {
  const h = ler("HANDOFF.md");
  const cabecalhos = [...h.matchAll(/^#{2,3}\s*Sess(?:ã|a)o\s+([\w.]+)(.*)$/gim)];
  for (let i = 0; i < cabecalhos.length; i++) {
    const [linhaToda, numero, resto] = cabecalhos[i];
    const ini = cabecalhos[i].index;
    const fim = i + 1 < cabecalhos.length ? cabecalhos[i + 1].index : h.length;
    // "Sessão 7 cont.⁸" e "Sessão 7" são cabeçalhos DIFERENTES e contam duas
    // vezes: colapsar os dois num nó só apontaria a linha do primeiro para o
    // conteúdo do segundo — a ficha diria onde está e não estaria lá.
    const base = `sessao:${numero}`;
    let id = base;
    for (let j = 2; nos.has(id); j++) id = `${base}#${j}`;
    no(id, "sessao", "HANDOFF.md", `${numero} ${resto.replace(/[—–-]/g, " ").trim()}`.trim(), {
      l: linhaDe(h, ini),
    });
    void linhaToda;
    // As migrations que a sessão cita — é o que liga "o que aconteceu" a "o que
    // mudou no banco" sem ninguém escrever a ligação.
    const corpo = h.slice(ini, fim);
    for (const num of new Set(corpo.match(/\b0\d{3}\b/g) ?? [])) {
      if (nos.has(`migration:${num}`)) aresta(id, "CITA", `migration:${num}`, "HANDOFF.md", linhaDe(h, ini));
    }
  }
}

// ---------------------------------------------------------------------------
// 7. OS COMMITS NÃO ENTRAM AQUI — e a ausência é a aplicação do princípio
// ---------------------------------------------------------------------------
//
// A primeira versão deste arquivo indexava `commit → TOCOU → arquivo`: 228
// commits, 2.267 arestas, e o `grafo.jsonl` saltou de 226 KB para 583 KB.
//
// Era duplicação pura. `git log -- <arquivo>` e `git log --grep` já respondem
// isso, sempre frescos, sem arquivo versionado nenhum no meio — e o princípio
// que governa este índice é DERIVAR, NUNCA DUPLICAR. Um índice de commits em
// texto seria uma cópia que envelhece de uma coisa que não envelhece.
//
// Então o `buscar.mjs` consulta o git NA HORA para a parte histórica. O que
// mora aqui é só o que o git não sabe responder: a ligação entre migration,
// função, nó do n8n, portão, ficha e sessão.

// ---------------------------------------------------------------------------
// SAÍDA — ordenada, para o `git diff` ser legível e o portão não virar ruído
// ---------------------------------------------------------------------------
const linhasNo = [...nos.values()].map((n) => JSON.stringify(n)).sort();
const linhasAresta = [...arestas].sort();
const saida = [...linhasNo, ...linhasAresta].join("\n") + "\n";

const contagem = {};
for (const n of nos.values()) contagem[n.t] = (contagem[n.t] ?? 0) + 1;
for (const l of arestas) {
  const rel = JSON.parse(l).rel;
  contagem[rel] = (contagem[rel] ?? 0) + 1;
}

if (process.argv.includes("--contar")) {
  console.log(JSON.stringify(contagem, null, 2));
} else {
  writeFileSync(SAIDA, saida);
  const kb = Math.round(saida.length / 1024);
  console.log(`grafo.jsonl: ${linhasNo.length} nós + ${linhasAresta.length} arestas (${kb} KB)`);
  console.log(Object.entries(contagem).sort().map(([k, v]) => `  ${k}: ${v}`).join("\n"));
}
