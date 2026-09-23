// O DENOMINADOR DA MEDIÇÃO TEM DE SER O DO ARQUIVO.
//
// O DEFEITO QUE ESTE ARQUIVO EXISTE PARA PEGAR, medido em 21/09/2026 (PR #238): a regra 2 do
// CLAUDE.md manda escrever "N dos M asserts reprovaram" no cabeçalho da migration e do teste. Nas
// migrations 0182 e 0183 os NUMERADORES estavam certos e os DENOMINADORES errados — "24 asserts"
// num teste de 30, "22" num de 20 —, e passaram por três commits, uma rodada de medição e o CI
// verde até uma revisão independente contar à mão. Denominador errado não é detalhe: torna a
// medição IRREPRODUZÍVEL. A próxima sessão que reexecutar o protocolo mede outro número e tem de
// adivinhar se a diferença é regressão da guarda ou erro de contagem — exatamente o custo que a
// regra 2 existe para evitar.
//
// A CAUSA: número escrito em prosa não é conferido contra o código que ele descreve. Os agentes
// escreviam o número PREVISTO ao desenhar o teste e ninguém recontava depois de o arquivo mudar.
// Este portão reconta, sempre.
//
// COMO PAREIA migration → teste. Pelo arquivo citado JUNTO de "MEDIÇÃO NÃO-VAZIA" (a linha e as
// três seguintes), não pelo primeiro citado no cabeçalho. MEDIDO em 23/09/2026: a primeira versão
// deste portão pareava pelo primeiro citado e acusou a 0179 — que cita um teste de outra migration
// como precedente antes do seu. Pareada certo, a 0179 bate (21 = 21). O portão que acusava estava
// errado, não a migration.
//
// COMO CONTA. Chamadas `teste_assert_<x>(` fora de linha de comentário, menos a da própria
// definição da função. Comentário não conta: um cabeçalho que cite o nome do assert entre crases
// (aconteceu nesta sessão — o grep contou 33 num arquivo de 32) não pode inflar o denominador.
//
// MEDIÇÃO NÃO-VAZIA (regra 2): rodado contra os arquivos da 0182 como estavam no commit 070b0c2 —
// o defeito REAL, não um número inventado —, este portão reprova. O número está na mensagem do
// commit que o introduziu.

import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync, readdirSync, existsSync } from "node:fs";
import { join } from "node:path";

const RAIZ = new URL("../..", import.meta.url).pathname.replace(/\/$/, "");
const MIGRATIONS = join(RAIZ, "Supabase/migrations");
const TESTES = join(RAIZ, "Supabase/test");

/** Quantos asserts o arquivo de teste de fato chama. */
export function contarAsserts(texto) {
  let n = 0;
  for (const linha of texto.split("\n")) {
    if (linha.trimStart().startsWith("--")) continue;
    n += (linha.match(/\bteste_assert_\w+\s*\(/g) ?? []).length;
    n -= (linha.match(/function\s+[\w.]*teste_assert_\w+\s*\(/g) ?? []).length;
  }
  return n;
}

/**
 * Os denominadores "N dos M asserts" declarados nas linhas de comentário — só os de ARQUIVO.
 *
 * Denominador qualificado ("2 dos 2 asserts DO BLOCO de escala", como a 0164) é legítimo e não é
 * conferível mecanicamente: o portão não sabe onde um bloco começa. Ele fica de fora de propósito,
 * e não por esquecimento — MEDIDO em 23/09/2026: sem esta exclusão, a primeira versão acusou a
 * 0164, cuja medição está certa.
 */
export function denominadores(texto) {
  // As linhas de comentário são JUNTADAS antes da busca. A primeira versão procurava linha a linha e,
  // MEDIDO pela revisão de 23/09/2026, deixava fora quatro declarações reais quebradas entre "dos M" e
  // "asserts" (0182, e os testes da 0181, 0182 e 0183) — o portão ficava verde com elas erradas.
  // O parêntese opcional cobre "4 dos 24 (REMEDIDO 23/09/2026), asserts", que é a forma que existe.
  const comentario = texto
    .split("\n")
    .filter((l) => l.trimStart().startsWith("--"))
    .map((l) => l.trimStart().replace(/^--+\s?/, ""))
    .join(" ");
  return [...comentario.matchAll(/\b\d+\s+dos\s+(\d+)(?:\s*\([^)]*\))?,?\s+asserts(?!\s+do\s+bloco)/g)].map((m) =>
    Number(m[1]),
  );
}

/** O teste citado junto de "MEDIÇÃO NÃO-VAZIA" — a linha dela e as três seguintes. */
export function testeDaMedicao(texto) {
  const linhas = texto.split("\n");
  const i = linhas.findIndex((l) => l.startsWith("--") && /MEDIÇÃO NÃO-VAZIA/.test(l));
  if (i < 0) return null;
  const trecho = linhas.slice(i, i + 4).join("\n");
  return trecho.match(/Supabase\/test\/([\w-]+\.test\.sql)/)?.[1] ?? null;
}

function divergencias() {
  const achados = [];

  for (const nome of readdirSync(MIGRATIONS).filter((f) => f.endsWith(".sql")).sort()) {
    const texto = readFileSync(join(MIGRATIONS, nome), "utf8");
    const declarados = denominadores(texto);
    if (!declarados.length) continue;
    const teste = testeDaMedicao(texto);
    if (!teste) {
      achados.push(`${nome}: declara "dos ${declarados[0]} asserts" mas não cita o teste junto de "MEDIÇÃO NÃO-VAZIA" — não há como conferir`);
      continue;
    }
    const caminho = join(TESTES, teste);
    if (!existsSync(caminho)) {
      achados.push(`${nome}: cita ${teste}, que não existe`);
      continue;
    }
    const real = contarAsserts(readFileSync(caminho, "utf8"));
    for (const d of new Set(declarados)) {
      if (d !== real) achados.push(`${nome}: declara "dos ${d} asserts", e ${teste} tem ${real}`);
    }
  }

  for (const nome of readdirSync(TESTES).filter((f) => f.endsWith(".test.sql")).sort()) {
    const texto = readFileSync(join(TESTES, nome), "utf8");
    const declarados = denominadores(texto);
    if (!declarados.length) continue;
    const real = contarAsserts(texto);
    for (const d of new Set(declarados)) {
      if (d !== real) achados.push(`${nome}: o próprio cabeçalho declara "dos ${d} asserts", e o arquivo tem ${real}`);
    }
  }

  return achados;
}

test("todo denominador de medição declarado bate com o arquivo que ele descreve", () => {
  const achados = divergencias();
  assert.deepEqual(
    achados,
    [],
    `\n  ${achados.join("\n  ")}\n\n  Reconte depois de mexer no teste. Denominador errado torna a medição da regra 2 ` +
      `irreproduzível: quem reexecutar o protocolo não sabe se a diferença é regressão ou erro de contagem.`,
  );
});

test("o contador não é enganado por comentário nem pela definição da função", () => {
  // Um contador que conte errado faz o portão acima mentir nos dois sentidos.
  const texto = [
    "-- cabeçalho que cita `perform teste_assert_x(` entre crases",
    "create or replace function teste_assert_x(p boolean, n text) returns void language plpgsql as $$",
    "begin null; end $$;",
    "  perform teste_assert_x(true, 'um');",
    "  perform teste_assert_x(true, 'dois');",
  ].join("\n");
  assert.equal(contarAsserts(texto), 2);
});

test("o denominador é lido mesmo quebrado entre linhas e com parêntese no meio", () => {
  // As duas formas reais que a primeira versão deixava passar em silêncio.
  const quebrado = ["--   contando todos — **3 dos 32", "--     asserts reprovaram**: ..."].join("\n");
  const comParentese = ["-- contando todos — 4 dos 24 (REMEDIDO 23/09/2026),", "--     asserts reprovaram."].join("\n");
  assert.deepEqual(denominadores(quebrado), [32]);
  assert.deepEqual(denominadores(comParentese), [24]);
  // e o qualificado continua fora, como a 0164
  assert.deepEqual(denominadores("-- **2 dos 2 asserts do bloco de escala reprovaram**"), []);
});

test("o pareamento usa o teste citado na medição, não o primeiro citado", () => {
  const texto = [
    "-- o teste sintético `Supabase/test/outro.test.sql` é citado como precedente",
    "-- MEDIÇÃO NÃO-VAZIA (regra 2), em `Supabase/test/o_certo.test.sql`:",
  ].join("\n");
  assert.equal(testeDaMedicao(texto), "o_certo.test.sql");
});
