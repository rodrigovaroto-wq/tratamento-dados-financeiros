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
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

// Caminhos ancorados na RAIZ do repositório, nunca no diretório de onde se chamou. O bloco
// canônico do CLAUDE.md deixa a sessão dentro de `portal/` (o `npm ci` é lá), e o passo 5 do
// `/fechar` chama este portão logo depois — com caminho relativo ao cwd ele morria com um stack
// trace de ENOENT, que é o mesmo defeito que `verificar-comandos.mjs` teve de corrigir.
const RAIZ = join(dirname(fileURLToPath(import.meta.url)), '..');
const CI = join(RAIZ, '.github/workflows/suites.yml');
const DOC = join(RAIZ, 'CLAUDE.md');

// Uma família por linha: o que se procura, e o nome que entra na mensagem de erro. As duas
// últimas entraram em 16/09/2026, na primeira revisão deste próprio portão: ele nascia cego para
// a suíte dos hooks e para os DOIS portões de `.claude/` — inclusive ele mesmo —, ou seja, o
// modo de falha que ele existe para pegar sobrevivia exatamente nas peças novas.
const FAMILIAS = [
  { nome: 'suítes de verificação do portal', padrao: /portal\/scripts\/verificar-[a-z0-9-]+\.mts/g },
  { nome: 'medidores', padrao: /N8N\/medir-[a-z0-9-]+\.mjs/g },
  { nome: 'portões de .claude', padrao: /\.claude\/verificar-[a-z-]+\.mjs/g },
  { nome: 'suíte dos hooks', padrao: /\.claude\/hooks\/test\/\*\.test\.mjs/g },
];

const ler = (p) => readFileSync(p, 'utf8');
const citados = (texto, padrao) => new Set(texto.match(padrao) ?? []);

// Só conta o que é COMANDO dos dois lados, e a razão é medida: ao acrescentar a família dos
// portões de `.claude`, o espelho fechou verde mesmo com a linha apagada do bloco canônico —
// porque o nome do portão aparece também na PROSA do CLAUDE.md. Citação em comentário de YAML ou
// em parágrafo explicativo não faz ninguém rodar nada; contá-la transforma o portão em enfeite.
const semComentario = (yaml) =>
  yaml.split('\n').filter((l) => !l.trimStart().startsWith('#')).join('\n');
const soOsBlocosDeComando = (md) =>
  (md.match(/```bash\n[\s\S]*?```/g) ?? []).join('\n');

const ci = semComentario(ler(CI));
const doc = soOsBlocosDeComando(ler(DOC));
const problemas = [];

for (const { nome, padrao } of FAMILIAS) {
  const noCi = citados(ci, new RegExp(padrao.source, 'g'));
  const noDoc = citados(doc, new RegExp(padrao.source, 'g'));

  for (const f of noCi) if (!noDoc.has(f)) problemas.push(`${nome}: o CI roda \`${f}\` e o CLAUDE.md não cita`);
  for (const f of noDoc) if (!noCi.has(f)) problemas.push(`${nome}: o CLAUDE.md manda rodar \`${f}\` e o CI não roda`);

  // E o espelho pode estar em dia dos dois lados apontando para um arquivo que a renomeação
  // levou embora — que foi exatamente como as regras do `lembrar-derivados` morreram.
  for (const f of new Set([...noCi, ...noDoc])) {
    // Citação com `*` é glob (a suíte dos hooks roda por glob nos dois lados): o que tem de
    // existir é o diretório, não um arquivo com asterisco no nome.
    const alvo = f.includes('*') ? dirname(f) : f;
    if (!existsSync(join(RAIZ, alvo))) problemas.push(`${nome}: \`${f}\` é citado mas não existe no repositório`);
  }
}

if (problemas.length === 0) {
  const total = FAMILIAS.map(({ nome, padrao }) => `${citados(ci, new RegExp(padrao.source, 'g')).size} ${nome}`).join(', ');
  console.log(`espelho OK — ${total}, iguais no .github/workflows/suites.yml e no CLAUDE.md`);
  process.exit(0);
}
console.error(`*** o CLAUDE.md e o CI divergem em ${problemas.length} ponto(s) ***\n`);
for (const p of problemas) console.error(`  ${p}`);
console.error(`\nEspelho que fica para trás é pior que espelho nenhum: ele manda a próxima sessão\nrodar diferente do portão. Acerte o lado que está errado — nunca apague a linha do CI\npara o espelho fechar.`);
process.exit(1);
