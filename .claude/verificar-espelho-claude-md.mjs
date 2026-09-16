#!/usr/bin/env node
// PORTÃO: o bloco "Comandos canônicos" do `CLAUDE.md` é ESPELHO do `.github/workflows/suites.yml`.
//
// POR QUE ELE EXISTE, e os dois números que o justificam. O `CLAUDE.md` é lido por TODA sessão e
// é dele que sai a lista do que se roda aqui. Quando ele fica para trás do CI, ele não fica
// silencioso: ele manda a próxima sessão rodar MENOS do que o portão cobra, e a sessão relata
// "baseline completa" sobre uma medição que não existe. Já aconteceu duas vezes, as duas achadas
// por acidente e não por portão:
//
//   • sessão 82 — o CI rodava SEIS suítes de verificação e o CLAUDE.md listava QUATRO
//     (`verificar-kit-basico.mts` e `verificar-modelagem-cobertura.mts` faltavam): 18 asserts
//     ficaram fora de uma "baseline completa";
//   • sessão 86 — os dois MEDIDORES (`medir-regua-cobertura.mjs`, `medir-custo-book.mjs`) rodavam
//     no CI e não estavam no CLAUDE.md, e o primeiro nem roda sem o `book-canastra`, cujo preparo
//     também faltava.
//
// O próprio CLAUDE.md já documentava os dois `grep` que conferem isso em dez segundos. Um grep que
// alguém precisa lembrar de rodar não é portão — é uma nota de rodapé. Este arquivo é o portão.
//
// O que ele NÃO faz: julgar se a suíte é boa, ou se a ordem no CLAUDE.md é a melhor. Só responde
// "os dois lados citam exatamente o mesmo conjunto, e cada arquivo citado existe?".
//
// Uso:  node .claude/verificar-espelho-claude-md.mjs
// Saída: exit 0 = espelho em dia; exit 1 = lista o que falta de cada lado.
import { existsSync, readFileSync } from 'node:fs';

const CI = '.github/workflows/suites.yml';
const DOC = 'CLAUDE.md';

// Uma família por linha: o que se procura, e o nome que entra na mensagem de erro.
const FAMILIAS = [
  { nome: 'suítes de verificação do portal', padrao: /portal\/scripts\/verificar-[a-z0-9-]+\.mts/g },
  { nome: 'medidores', padrao: /N8N\/medir-[a-z0-9-]+\.mjs/g },
];

const ler = (p) => readFileSync(p, 'utf8');
const citados = (texto, padrao) => new Set(texto.match(padrao) ?? []);

const ci = ler(CI);
const doc = ler(DOC);
const problemas = [];

for (const { nome, padrao } of FAMILIAS) {
  const noCi = citados(ci, new RegExp(padrao.source, 'g'));
  const noDoc = citados(doc, new RegExp(padrao.source, 'g'));

  for (const f of noCi) if (!noDoc.has(f)) problemas.push(`${nome}: o CI roda \`${f}\` e o ${DOC} não cita`);
  for (const f of noDoc) if (!noCi.has(f)) problemas.push(`${nome}: o ${DOC} manda rodar \`${f}\` e o CI não roda`);

  // E o espelho pode estar em dia dos dois lados apontando para um arquivo que a renomeação
  // levou embora — que foi exatamente como as regras do `lembrar-derivados` morreram.
  for (const f of new Set([...noCi, ...noDoc])) {
    if (!existsSync(f)) problemas.push(`${nome}: \`${f}\` é citado mas não existe no repositório`);
  }
}

if (problemas.length === 0) {
  const total = FAMILIAS.map(({ nome, padrao }) => `${citados(ci, new RegExp(padrao.source, 'g')).size} ${nome}`).join(', ');
  console.log(`espelho OK — ${total}, iguais no ${CI} e no ${DOC}`);
  process.exit(0);
}
console.error(`*** o CLAUDE.md e o CI divergem em ${problemas.length} ponto(s) ***\n`);
for (const p of problemas) console.error(`  ${p}`);
console.error(`\nEspelho que fica para trás é pior que espelho nenhum: ele manda a próxima sessão\nrodar diferente do portão. Acerte o lado que está errado — nunca apague a linha do CI\npara o espelho fechar.`);
process.exit(1);
