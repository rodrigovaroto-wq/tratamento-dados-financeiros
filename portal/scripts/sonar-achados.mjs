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

if (lista || regra) {
  // A API devolve no máximo 500 por página e não pagina além de 10.000.
  const d = await buscar(filtro, 500);
  console.log(`${d.total} achado(s)${filtro ? ` [${filtro}]` : ""}\n`);
  for (const i of d.issues) {
    const arq = i.component.split(":").slice(1).join(":");
    console.log(`  [${i.rule}] ${arq}:${i.line ?? "?"}`);
    console.log(`      ${i.message}`);
  }
  if (d.total > d.issues.length) {
    console.log(`\n  … e mais ${d.total - d.issues.length} não listados (a página vai a 500).`);
  }
} else {
  const d = await buscar(`${filtro}&facets=types,severities,rules,languages`);
  console.log(`PROJETO ${PROJETO}`);
  console.log(`${d.total} achado(s) em aberto${filtro ? ` [${filtro}]` : ""}\n`);
  for (const f of d.facets) {
    const vals = f.values.filter((v) => v.count > 0).slice(0, 15);
    if (!vals.length) continue;
    console.log(`== ${f.property}`);
    for (const v of vals) console.log(`   ${String(v.count).padStart(5)}  ${v.val}`);
    console.log();
  }
  console.log("Para ver os arquivos: --lista, --tipo=BUG, --regra=typescript:S2871");
}
