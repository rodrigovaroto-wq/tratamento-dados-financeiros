#!/usr/bin/env node
// Puxa os achados do SonarQube Cloud deste projeto, agrupados, sem precisar abrir
// o site — e sem token: o projeto é público e a API de leitura responde anônima.
//
//   node portal/scripts/sonar-achados.mjs                  # o resumo
//   node portal/scripts/sonar-achados.mjs --tipo=BUG       # só bugs
//   node portal/scripts/sonar-achados.mjs --regra=typescript:S2871
//   node portal/scripts/sonar-achados.mjs --lista          # imprime arquivo:linha
//
// POR QUE ISTO EXISTE. O relatório do Sonar é grande e a maior parte dele, neste
// repositório, não é sobre o código (ver `.sonarcloud.properties`). Ler pela API
// agrupando por regra é o que separa sinal de volume em dez segundos; ler pelo
// site é rolar 3.000 linhas. E deixa a consulta REPRODUTÍVEL: quem retomar não
// precisa descobrir a chave do projeto nem lembrar dos parâmetros.
//
// O TOKEN. Só é necessário para ESCREVER (marcar issue como falso positivo) ou se
// o projeto virar privado. Nesse dia, exporte SONAR_TOKEN e ele é usado sozinho.

const PROJETO = "rodrigovaroto-wq_tratamento-dados-financeiros";
const BASE = "https://sonarcloud.io/api/issues/search";

const args = process.argv.slice(2);
const opt = (nome) => {
  const a = args.find((x) => x.startsWith(`--${nome}=`));
  return a ? a.slice(nome.length + 3) : null;
};
const lista = args.includes("--lista");

const cabecalho = process.env.SONAR_TOKEN
  ? { Authorization: `Bearer ${process.env.SONAR_TOKEN}` }
  : {};

async function buscar(extra, ps = 1) {
  const url = `${BASE}?componentKeys=${PROJETO}&resolved=false&ps=${ps}&${extra}`;
  const r = await fetch(url, { headers: cabecalho });
  if (!r.ok) throw new Error(`${r.status} ${r.statusText} — ${url}`);
  const j = await r.json();
  if (j.errors) throw new Error(JSON.stringify(j.errors));
  return j;
}

const tipo = opt("tipo");
const regra = opt("regra");
const filtro = [tipo && `types=${tipo}`, regra && `rules=${encodeURIComponent(regra)}`]
  .filter(Boolean).join("&");
// `filtro` vem de argv (--tipo=, --regra=) e é logado abaixo dentro de um
// `[...]` no meio da linha de resumo — uma quebra de linha aí forjaria uma
// segunda linha de saída como se fosse deste script (log injection,
// jssecurity:S5145). Argv não tem CR/LF de verdade (o shell já separa por
// espaço), mas a origem é entrada externa e o `console.log` não distingue —
// tirar quebra de linha antes de logar fecha o caso mesmo que ela chegue por
// outra via (variável de ambiente, wrapper que monta argv programaticamente).
// SANITIZA CADA CARACTERE DE CONTROLE, não só `\r\n`. Trocar quebra de linha
// resolvia a linha falsa, mas deixava passar o resto da classe: `\b` apaga o
// caractere anterior no terminal, `\x1b[` abre sequência ANSI (que repinta,
// move o cursor e pode esconder linhas inteiras da saída), e `\u2028` é quebra
// de linha para quem consumir a saída como JS. `\p{C}` cobre a categoria
// Unicode inteira — controle, formato e não-atribuído. O corte em 500 evita que
// uma mensagem gigante empurre os outros achados para fora da tela.
const semControle = (s) => String(s ?? "").replace(/\p{C}/gu, " ").slice(0, 500);
const filtroParaLog = semControle(filtro);

if (lista || regra) {
  // A API devolve no máximo 500 por página e não pagina além de 10.000.
  const d = await buscar(filtro, 500);
  // Sufixo fora do template (sonar javascript:S4624: template dentro de template
  // esconde qual crase fecha qual, e este arquivo já pagou por crase mal fechada).
  const total = Number(d.total) || 0;
  const sufixo = filtroParaLog ? ` [${filtroParaLog}]` : "";
  console.log(`${total} achado(s)${sufixo}\n`);
  for (const i of d.issues) {
    // `i.message`, `i.component` (via `arq`) e `i.rule` vêm da RESPOSTA HTTP do
    // Sonar, não de argv — e mensagem de issue com quebra de linha é normal
    // numa regra multi-linha (ex.: um bloco de código citado na descrição).
    // Sem sanitizar, uma dessas quebras forja uma linha extra na saída
    // indistinguível de um achado real — no único lugar que alguém lê para
    // decidir o que corrigir (jssecurity:S5145, mesmo motivo do `filtro`
    // acima, mas aqui a entrada é externa de verdade, não hipotética).
    const arq = semControle(i.component.split(":").slice(1).join(":"));
    console.log(`  [${semControle(i.rule)}] ${arq}:${i.line ?? "?"}`);
    console.log(`      ${semControle(i.message)}`);
  }
  if (d.total > d.issues.length) {
    console.log(`\n  … e mais ${total - d.issues.length} não listados (a página vai a 500).`);
  }
} else {
  const d = await buscar(`${filtro}&facets=types,severities,rules,languages`);
  console.log(`PROJETO ${PROJETO}`);
  const totalResumo = Number(d.total) || 0;
  const sufixoResumo = filtroParaLog ? ` [${filtroParaLog}]` : "";
  console.log(`${totalResumo} achado(s) em aberto${sufixoResumo}\n`);
  for (const f of d.facets) {
    const vals = f.values.filter((v) => v.count > 0).slice(0, 15);
    if (!vals.length) continue;
    console.log(`== ${f.property}`);
    // `v.val` também vem da resposta do Sonar (nome de regra/severidade/linguagem
    // no facet) — mesmo tratamento, mesmo motivo do bloco acima.
    for (const v of vals) console.log(`   ${String(v.count).padStart(5)}  ${semControle(v.val)}`);
    console.log();
  }
  console.log("Para ver os arquivos: --lista, --tipo=BUG, --regra=typescript:S2871");
}
