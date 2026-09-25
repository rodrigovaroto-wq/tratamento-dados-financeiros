// O cabeçalho de uma ficha salva com CRLF é lido IGUAL ao da mesma ficha em LF.
//
// Até 24/09/2026 o `indexar.mjs` casava o cabeçalho com `/^---\n…\n---\n/`: uma ficha salva em
// CRLF (editor no Windows, "Add files via upload" do GitHub) devolvia `null`, e ela entrava no
// grafo SEM `toca`, `prova`, `ancora` nem `description` — sem erro nenhum. O portão que existe para
// descobrir que uma ficha envelheceu deixava de vê-la. É a lição de
// `.claude/memory/ancora-de-texto-quebra-com-crlf.md` repetida no próprio indexador; o
// `verificar-comandos.mjs` já aceitava `\r?\n` com um parser próprio. Agora há UM parser.
//
// O que se afirma, sobre TODAS as fichas e memórias reais do repositório: a leitura da versão
// CRLF é idêntica à da LF, e não é vazia.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readdirSync, readFileSync } from 'node:fs';
import { join, dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { cabecalho } from '../cabecalho.mjs';

const RAIZ = resolve(dirname(fileURLToPath(import.meta.url)), '..', '..', '..');
const fichas = ['.claude/memory', '.claude/conhecimento/fichas'].flatMap((d) =>
  readdirSync(join(RAIZ, d)).filter((f) => f.endsWith('.md') && f !== 'MEMORY.md' && f !== 'INSTRUCTIONS.md')
    .map((f) => join(RAIZ, d, f)));

test('controle positivo: as fichas do repositório têm cabeçalho legível em LF', () => {
  const comCabecalho = fichas.filter((f) => cabecalho(readFileSync(f, 'utf8')));
  assert.ok(comCabecalho.length > 30, `só ${comCabecalho.length} fichas com cabeçalho — o parser não está lendo`);
});

test('a mesma ficha em CRLF tem o MESMO cabeçalho que em LF — nenhuma perde toca/prova/ancora', () => {
  const diferentes = fichas.filter((f) => {
    const lf = readFileSync(f, 'utf8').replace(/\r\n/g, '\n');
    return JSON.stringify(cabecalho(lf)) !== JSON.stringify(cabecalho(lf.replace(/\n/g, '\r\n')));
  });
  assert.deepEqual(diferentes.map((f) => f.replace(RAIZ + '/', '')), []);
});
