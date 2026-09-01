#!/usr/bin/env node
// SessionStart — a sonda barata do repositório.
//
// POR QUE. Toda sessão aqui começava lendo 700 KB de markdown ou nada. Este hook responde as
// quatro perguntas que a sessão precisa ANTES de decidir o que fazer, em ~50 ms, sem rede e sem
// banco: em que branch estou, qual é a migration mais nova, o ESTADO.md fala dela, e há derivado
// versionado sujo na árvore.
//
// FAIL-OPEN INTEGRAL: qualquer falha aqui vira silêncio. Um SessionStart que lança pode impedir
// a sessão de começar — o pior lugar possível para uma falha, porque não sobra sessão de onde
// depurar.

import { readdirSync, readFileSync } from "node:fs";
import { execFileSync } from "node:child_process";
import { lerEvento } from "./hook-io.mjs";

if (lerEvento() === null) process.exit(0);

const git = (...args) => {
  try {
    return execFileSync("git", args, { encoding: "utf8", stdio: ["ignore", "pipe", "ignore"] }).trim();
  } catch {
    return "";
  }
};

const linhas = [];
try {
  const branch = git("rev-parse", "--abbrev-ref", "HEAD");
  if (branch) linhas.push(`Branch: \`${branch}\``);

  const migrations = readdirSync("Supabase/migrations").filter((f) => f.endsWith(".sql")).sort();
  const ultima = migrations.at(-1);
  if (ultima) {
    const numero = ultima.slice(0, 4);
    linhas.push(`Migration mais nova no repositório: \`${ultima}\``);

    const estado = readFileSync("ESTADO.md", "utf8").slice(0, 20000);
    if (!estado.includes(ultima)) {
      linhas.push(
        `⚠️  O topo do \`ESTADO.md\` NÃO cita a \`${numero}\`. Ele é o arquivo que responde ` +
          `"onde estamos" — um documento de estado parado é a única forma de erro que ele comete ` +
          `sozinho, e já mandou 17 PRs seguidos começarem errado.`,
      );
    }
  }

  // Derivado versionado sujo: o que roda é o commitado, não a fonte que o gera.
  const sujos = git("status", "--porcelain", "--", "N8N/workflow.e1-ingestao.json",
    "N8N/workflow.macro.json", "N8N/workflow.erros.json", "Supabase/schema.sql",
    "Supabase/test/fixture_book_vertentes.sql", "Supabase/test/fixture_book_canastra.sql",
    "Vercel/scripts/fixtures/book-vertentes.json");
  if (sujos) {
    linhas.push(`⚠️  Derivado versionado modificado e não commitado:\n${sujos}`);
  }

  linhas.push(
    "Nenhum arquivo daqui é autoridade sobre o banco — quem responde é `fn_instalacao_conferir()`.",
  );
} catch {
  process.exit(0); // fail-open: sem contexto extra é melhor que sem sessão
}

if (linhas.length) {
  console.log(
    JSON.stringify({
      hookSpecificOutput: {
        hookEventName: "SessionStart",
        additionalContext: `Sonda do repositório:\n\n- ${linhas.join("\n- ")}`,
      },
    }),
  );
}
process.exit(0);
