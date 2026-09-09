// O INSTRUMENTO DA FASE 0 — as duas contagens de linhas de conta, lado a lado,
// para qualquer texto. Ver `Arquitetura do Sistema/3 Estado e Execução/PLANO_LINHA_A_LINHA.md`,
// Fase 0: "capturar o texto do nó `Extrair Texto` para os TRÊS documentos [do
// araucária] e contar as linhas de conta por um SEGUNDO MÉTODO INDEPENDENTE".
//
// Este script é o que falta para a Fase 0 fechar no minuto em que o texto dos
// três documentos (araucária `002`, `175`, `055`) chegar — sem trabalho manual.
//
//   node N8N/medir-fase0-denominador.mjs <arquivo-de-texto.txt>       # um documento
//   node N8N/medir-fase0-denominador.mjs <arquivo-de-texto.txt> --json
//   node N8N/medir-fase0-denominador.mjs --book canastra              # tabela lado a lado
//   node N8N/medir-fase0-denominador.mjs --book vertentes             # idem, vertentes
//   node N8N/medir-fase0-denominador.mjs --book canastra --json
//
// O ARQUIVO DE TEXTO é o texto como o nó `Extrair Texto` do n8n o produz — o
// mesmo formato que `Dados de Teste/capturas/*/textos.json` guarda por
// documento. Para o araucária: capture o texto de produção (mesmo processo da
// captura de 31/08) e salve em um `.txt`; este script não inventa entrada.
//
// O QUE ELE NÃO FAZ, e por quê: não decide qual dos dois números é a verdade.
// Ele existe porque nenhum dos dois é isento — `linhasDeConta` é uma heurística
// léxica (rótulo + valor, menos ruído conhecido) e `linhasDeContaPorForma` é
// uma heurística de forma (número que não é ano nem data). Onde concordam, a
// contagem tem duas pernas. Onde discordam, é exatamente o sinal que a Fase 0
// pede: abrir o documento e contar à mão as linhas em que os dois divergem —
// um trabalho de minutos, porque a lista de linhas diferentes é curta e
// nomeada, não "confira o documento inteiro de novo".

import { readFileSync, existsSync } from 'node:fs';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { linhasDeConta, juntarFragmentosDeLinha } from './lib/cobertura.mjs';
import { linhasDeContaPorForma } from './lib/segunda-contagem.mjs';

const RAIZ = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const JSON_SAIDA = process.argv.includes('--json');

/**
 * As duas contagens de um texto, e onde elas DIVERGEM linha a linha — a lista
 * curta que alguém abre o PDF para decidir, em vez de reler o documento
 * inteiro.
 */
export function compararMetodos(texto) {
  const m1 = new Set(linhasDeConta(texto));
  const m2 = new Set(linhasDeContaPorForma(texto, { juntarFragmentos: juntarFragmentosDeLinha }));
  const soM1 = [...m1].filter((l) => !m2.has(l));
  const soM2 = [...m2].filter((l) => !m1.has(l));
  return {
    linhasDeConta: m1.size,
    linhasDeContaPorForma: m2.size,
    diferenca: m2.size - m1.size,
    concordam: m1.size > 0 || m2.size > 0 ? [...m1].filter((l) => m2.has(l)).length : 0,
    soNaRegua: soM1,
    soNaForma: soM2,
  };
}

function medirUmArquivo(caminho) {
  const texto = readFileSync(caminho, 'utf8');
  const r = compararMetodos(texto);
  if (JSON_SAIDA) {
    console.log(JSON.stringify({ arquivo: caminho, ...r }, null, 2));
    return;
  }
  console.log(`\nFASE 0 — duas contagens independentes de "${caminho}"\n`);
  console.log(`  linhasDeConta (léxica: rótulo+valor, menos ruído conhecido) ... ${r.linhasDeConta}`);
  console.log(`  linhasDeContaPorForma (forma do número, sem lista de ruído) ... ${r.linhasDeContaPorForma}`);
  console.log(`  diferença (forma − léxica) ..................................... ${r.diferenca >= 0 ? '+' : ''}${r.diferenca}`);
  console.log(`  concordam em .................................................... ${r.concordam} linha(s)`);
  if (r.soNaRegua.length) {
    console.log(`\n  SÓ a léxica contou (a forma rejeitou — confira: pode ser ano/data que parece valor):`);
    for (const l of r.soNaRegua) console.log(`    - ${l}`);
  }
  if (r.soNaForma.length) {
    console.log(`\n  SÓ a forma contou (a léxica rejeitou — confira: pode ser ruído sem lista, ou defeito da léxica):`);
    for (const l of r.soNaForma) console.log(`    - ${l}`);
  }
  console.log('\nNenhum dos dois números é "a verdade" — são duas pernas independentes. Onde');
  console.log('concordam, a contagem é dupla; onde divergem, a lista acima nomeia as linhas a');
  console.log('conferir a olho no PDF — sem reler o documento inteiro.');
}

function medirBook(nome) {
  const pasta = resolve(RAIZ, `Dados de Teste/book-${nome}/pdf`);
  if (!existsSync(pasta)) {
    console.error(`Book desconhecido ou não gerado: ${pasta}`);
    console.error(`Gere primeiro: cd "Dados de Teste"/book-${nome} && PYTHONPATH=. python3 gerar.py`);
    process.exit(2);
  }
  const metricas = JSON.parse(readFileSync(resolve(pasta, 'METRICAS.json'), 'utf8')).documentos;
  const textos = JSON.parse(readFileSync(resolve(pasta, 'TEXTO_EXTRAIDO.json'), 'utf8')).documentos;
  const capturaPath = resolve(RAIZ, 'Dados de Teste/capturas/2026-08-31-texto-extraido-n8n/textos.json');
  const captura = nome === 'canastra' && existsSync(capturaPath)
    ? JSON.parse(readFileSync(capturaPath, 'utf8')) : null;

  const linhas = metricas
    .filter((m) => m.linhas_de_conta_verdade > 0)
    .map((m) => {
      const daProducao = captura?.documentos[m.arquivo];
      const texto = daProducao ? daProducao.texto : (textos[m.arquivo] ?? []).join('\n');
      const verdade = m.linhas_de_conta_verdade;
      const m1 = linhasDeConta(texto).length;
      const m2 = linhasDeContaPorForma(texto, { juntarFragmentos: juntarFragmentosDeLinha }).length;
      return {
        arquivo: m.arquivo,
        producao: Boolean(daProducao),
        verdade,
        m1, erroM1: (m1 - verdade) / verdade,
        m2, erroM2: (m2 - verdade) / verdade,
      };
    });

  if (JSON_SAIDA) {
    console.log(JSON.stringify({ book: nome, documentos: linhas }, null, 2));
    return;
  }

  console.log(`\nFASE 0 — as duas contagens contra o gabarito, book-${nome}\n`);
  console.log(`${'documento'.padEnd(50)}${'src'.padStart(5)}${'verdade'.padStart(8)}${'m1'.padStart(5)}${'erro1'.padStart(8)}${'m2'.padStart(5)}${'erro2'.padStart(8)}`);
  console.log('-'.repeat(94));
  let menosM1 = 0; let menosM2 = 0;
  const pct = (v) => `${v >= 0 ? '+' : ''}${(v * 100).toFixed(0)}%`;
  for (const l of linhas) {
    console.log(`${l.arquivo.slice(0, 49).padEnd(50)}${(l.producao ? 'prod' : 'gen').padStart(5)}`
      + `${String(l.verdade).padStart(8)}${String(l.m1).padStart(5)}${pct(l.erroM1).padStart(8)}`
      + `${String(l.m2).padStart(5)}${pct(l.erroM2).padStart(8)}`);
    if (l.erroM1 < -0.001) menosM1 += 1;
    if (l.erroM2 < -0.001) menosM2 += 1;
  }
  console.log('-'.repeat(94));
  console.log(`\ncontam A MENOS (o lado perigoso): linhasDeConta em ${menosM1}/${linhas.length}`
    + `, linhasDeContaPorForma em ${menosM2}/${linhas.length}`);
}

const argBook = process.argv.includes('--book') ? process.argv[process.argv.indexOf('--book') + 1] : null;
const argArquivo = process.argv.slice(2).find((a) => !a.startsWith('--') && a !== argBook);

if (argBook) {
  medirBook(argBook);
} else if (argArquivo) {
  if (!existsSync(argArquivo)) {
    console.error(`Não encontrei ${argArquivo}.`);
    process.exit(2);
  }
  medirUmArquivo(argArquivo);
} else {
  console.error('Uso: node N8N/medir-fase0-denominador.mjs <arquivo-de-texto.txt> [--json]');
  console.error('  ou: node N8N/medir-fase0-denominador.mjs --book <canastra|vertentes> [--json]');
  process.exit(2);
}
