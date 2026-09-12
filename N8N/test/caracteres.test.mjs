// O JSON DO WORKFLOW É CARREGADO À MÃO PARA DENTRO DO n8n — E CARACTERE
// INVISÍVEL SOBREVIVE A ESSE CAMINHO SEM DEIXAR RASTRO.
//
// POR QUE ESTE ARQUIVO EXISTE. O `Parse Extracao` carregava, dentro de três
// classes de caractere de regex, os caracteres combinantes CRUS — U+0300 a
// U+036F escritos literalmente. Funciona: é a mesma classe que
// `[\u0300-\u036f]`, e a quarta ocorrência da MESMA função já usava a forma
// escapada. Só que essas três não eram legíveis em lugar nenhum: no `git diff`,
// no editor do nó Code do n8n e em qualquer transcrição, elas aparecem como um
// borrão de um ou dois caracteres, ou como nada.
//
// E o caminho desse arquivo até a produção NÃO é o `git`: é uma pessoa copiando
// o JSON para dentro do n8n, ou uma chamada de API carregando o `jsCode` como
// texto. Nesse trajeto, um caractere que ninguém consegue ver é um caractere que
// ninguém consegue conferir — e a sessão 61 já pagou por isso uma vez, com o
// caractere invisível que partia a conta em duas.
//
// A REGRA, então: o que sai daqui para o n8n é escrito em caractere VISÍVEL.
// Acento em comentário e em texto de mensagem continua valendo — o que esta
// suíte proíbe é a marca combinante SOLTA (a que só existe grudada na letra
// anterior, e que num range de regex fica órfã) e a família dos invisíveis de
// largura zero. Quem precisar do codepoint escreve `\u0300`, que é a forma que
// aparece no diff.
//
// RELIGAMENTO: desfazer a correção em `N8N/lib/extract.mjs` (voltar as três
// classes para a forma crua) deixa este arquivo vermelho nomeando o nó.

import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const AQUI = dirname(fileURLToPath(import.meta.url));

const WORKFLOWS = [
  'workflow.e1-ingestao.json',
  'workflow.macro.json',
  'workflow.diagnostico-ia.json',
  'workflow.erros.json',
];

// Os proibidos, cada um com o nome que uma pessoa reconhece. Um código de erro
// como "U+200B" manda quem leu procurar numa tabela; "espaço de largura zero"
// já diz o que aconteceu.
//
// NBSP entra na lista por um motivo diferente dos outros: ele é VISÍVEL como
// espaço e não quebra nada em texto — mas dentro de um regex ou de uma chave de
// comparação ele é um caractere que não é o espaço, e a diferença só aparece no
// dado que não casa.
const INVISIVEIS = new Map([
  ['\u200b', 'espaço de largura zero (ZWSP)'],
  ['\u200c', 'não-juntador de largura zero (ZWNJ)'],
  ['\u200d', 'juntador de largura zero (ZWJ)'],
  ['\u2060', 'juntador de palavra (WJ)'],
  ['\ufeff', 'marca de ordem de byte (BOM)'],
  ['\u00a0', 'espaço não-separável (NBSP)'],
  ['\u202f', 'espaço estreito não-separável (NNBSP)'],
  ['\u00ad', 'hífen condicional (SHY)'],
  ['\u2028', 'separador de linha (LS)'],
  ['\u2029', 'separador de parágrafo (PS)'],
]);

// A marca combinante SOLTA. Ela é legítima grudada numa letra — mas o gerador
// escreve todo texto em NFC, então uma combinante que sobra aqui está órfã, e
// órfã dentro de um range de regex é exatamente o caso do `Parse Extracao`.
const combinante = (ch) => ch >= '\u0300' && ch <= '\u036f';

const nomeDoCaractere = (ch) => INVISIVEIS.get(ch)
  ?? (combinante(ch) ? 'marca combinante solta' : null);

// Onde ele está, em vez de só quantos são: o nó é a unidade que a pessoa abre no
// n8n, e o trecho ao redor é o que ela procura com Ctrl+F.
const varrer = (texto, ondeEstou, achados) => {
  for (let i = 0; i < texto.length; i += 1) {
    const nome = nomeDoCaractere(texto[i]);
    if (!nome) continue;
    const ponto = texto.codePointAt(i).toString(16).padStart(4, '0');
    achados.push(
      `${ondeEstou}: ${nome} (U+${ponto.toUpperCase()}) perto de `
      + `«${texto.slice(Math.max(0, i - 30), i + 30).replace(/\s+/g, ' ')}»`,
    );
  }
};

for (const arq of WORKFLOWS) {
  test(`${arq} — nenhum caractere invisível chega ao n8n`, () => {
    const wf = JSON.parse(readFileSync(join(AQUI, '..', arq), 'utf8'));
    const achados = [];
    for (const no of wf.nodes) {
      varrer(JSON.stringify(no.parameters ?? {}), `nó "${no.name}" (parâmetros)`, achados);
      varrer(String(no.notes ?? ''), `nó "${no.name}" (nota)`, achados);
      varrer(String(no.name ?? ''), `nome do nó "${no.name}"`, achados);
    }
    assert.equal(
      achados.length, 0,
      'caractere invisível no JSON que é carregado à mão para dentro do n8n — '
      + 'escreva o codepoint escapado (\\u0300), que é a forma que aparece no diff:\n  '
      + achados.join('\n  '),
    );
  });
}

// A guarda acima só vale se ela SOUBER acusar. Sem este teste, um `varrer` que
// nunca achasse nada passaria nos quatro workflows com nota máxima — é o mesmo
// assert 3 do `instalacao.test.sql`, pela mesma razão.
test('a varredura de fato acusa — um invisível fabricado é encontrado', () => {
  const achados = [];
  varrer('const re = /[​]/;', 'nó fabricado', achados);
  assert.equal(achados.length, 1);
  assert.match(achados[0], /largura zero/);

  const combinantes = [];
  varrer('/[̀-ͯ]/', 'nó fabricado', combinantes);
  assert.equal(combinantes.length, 2, 'as duas pontas do range cru têm de ser acusadas');
  assert.match(combinantes[0], /marca combinante solta/);
});

// E a forma ESCAPADA — a que a correção usa — tem de passar. Um portão que
// proíba as duas formas não deixa caminho nenhum, e quem esbarrar nele vai
// desligá-lo.
test('a forma escapada passa — ela é o caminho que a regra deixa aberto', () => {
  const achados = [];
  varrer(String.raw`.normalize('NFD').replace(/[\u0300-\u036f]/g, '')`, 'nó fabricado', achados);
  assert.deepEqual(achados, []);
});

// O acento NORMAL não pode cair aqui. Este repositório escreve tudo em
// português, e um portão que proibisse "reconciliação" seria desligado no
// primeiro dia — a regra é sobre a marca ÓRFÃ, não sobre a letra acentuada.
test('texto em português com acento passa — a regra é sobre a marca órfã', () => {
  const achados = [];
  varrer('A reconciliação não foi possível: precondição não satisfeita.', 'nó fabricado', achados);
  assert.deepEqual(achados, [], 'acento em NFC é UM caractere, e não uma marca combinante solta');
});

// ---------------------------------------------------------------------------
// A FONTE TAMBEM, nao so o JSON gerado — e esta metade faltava.
// ---------------------------------------------------------------------------
//
// MEDIDO EM 12/09/2026: `N8N/lib/aritmetica.mjs` nasceu com DOIS bytes NUL
// CRUS, usados de proposito como separador de chave composta, mas escritos como
// o BYTE e nao como o escape. O efeito e o de sempre: o `grep` passa a responder
// "binary file matches" e o arquivo inteiro some de toda busca — foi assim que
// dois bytes esconderam 3.484 linhas do gerador do book (commit `8d378b0`).
//
// E ESTA SUITE PASSOU VERDE sobre o arquivo, porque ela varria so o `jsCode`
// dos nos do workflow JSON. O NUL estava na FONTE, que e onde alguem escreve —
// e uma lib so chega ao JSON quando e serializada para dentro de um no, o que
// pode demorar commits. Portao que mede um lado do espelho tem a mesma
// aparencia de um portao que mede os dois (regra 7).
//
// A REGRA E A MESMA do cabecalho deste arquivo, um passo antes: quem precisa do
// codepoint escreve `\u0000`, que e a forma que aparece no diff e que o grep
// enxerga. O comportamento em execucao e identico.
const CONTROLE_CRU = (b) => b < 0x20 && b !== 0x09 && b !== 0x0a && b !== 0x0d;

test('nenhuma fonte de N8N/lib tem byte de controle CRU — o grep tem de enxergar o arquivo', () => {
  const libs = readdirSync(join(AQUI, '..', 'lib')).filter((f) => f.endsWith('.mjs'));
  assert.ok(libs.length > 0, 'nao achei as libs — o portao estaria medindo o vazio');
  const achados = [];
  for (const f of libs) {
    const bytes = readFileSync(join(AQUI, '..', 'lib', f));
    for (let i = 0; i < bytes.length; i += 1) {
      // TAB, LF e CR sao texto de verdade; o resto do C0 nao tem o que fazer
      // numa fonte JS e so chega ali por colagem ou descuido.
      if (CONTROLE_CRU(bytes[i])) {
        achados.push(`lib/${f}: byte 0x${bytes[i].toString(16).padStart(2, '0')} no offset ${i}`);
      }
    }
  }
  assert.deepEqual(achados, [],
    `byte de controle cru na fonte — escreva o escape ("\u0000") em vez do byte:\n  ${achados.join('\n  ')}`);
});

test('a varredura da fonte de fato acusa — um byte cru fabricado e encontrado', () => {
  // REGRA 2 aplicada ao proprio portao: sem esta prova, o teste acima teria a
  // mesma aparencia passando sobre libs limpas e passando por estar quebrado.
  const comNul = Buffer.from(`const a = "x${String.fromCharCode(0)}y";`, 'utf8');
  assert.equal([...comNul].filter(CONTROLE_CRU).length, 1,
    'o criterio tem de achar o byte cru que ele existe para achar');
  const semNul = Buffer.from('const a = "xy";\n', 'utf8');
  assert.equal([...semNul].filter(CONTROLE_CRU).length, 0, 'e nao pode acusar fonte limpa');
});
