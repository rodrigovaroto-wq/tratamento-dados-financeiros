// A RÉGUA DA COBERTURA, medida contra a verdade — sem gastar um centavo.
//
// POR QUE ESTE SCRIPT EXISTE. A guarda de cobertura (`lib/cobertura.mjs`) decide
// se um documento veio pela metade comparando duas contagens: as LINHAS que a
// extração devolveu e as LINHAS DE CONTA que o documento tem. A segunda é uma
// HEURÍSTICA sobre o texto do PDF — "linha que tem valor e tem identidade, menos
// o ruído conhecido" — e até aqui ela tinha **um** ponto de medição: o `02_DRE`,
// conferido a olho numa madrugada (o comentário do `LIMIAR_COBERTURA` dizia isso
// com todas as letras, e pedia a recalibração).
//
// Uma régua errada estraga os dois lados. Se ela conta demais, extração PERFEITA
// aparece como incompleta e a fila de revisão enche de falso positivo — o jeito
// mais rápido de ensinar o dono a ignorar pendência. Se conta de menos, extração
// pela metade passa como sadia, que é o defeito que as três camadas existem para
// eliminar.
//
// A VERDADE VEM DE QUEM ESCREVEU O DOCUMENTO. O gerador do `book-canastra` conta,
// enquanto monta cada tabela, quantas linhas têm rótulo e pelo menos um valor
// (`render.py`, `CONTAGEM`) e grava isso no `METRICAS.json` como
// `linhas_de_conta_verdade`. Não é outra leitura do PDF: é o dado antes de virar
// página. Conferir heurística contra heurística não prova nada.
//
//   node n8n/medir-regua-cobertura.mjs           # tabela por documento
//   node n8n/medir-regua-cobertura.mjs --json    # para script
//
// Sai com código 1 quando a régua erra ALÉM da faixa declarada abaixo — que é o
// mesmo contrato do `medir-custo-book.mjs`: o número que sustenta uma decisão de
// produção não pode envelhecer em silêncio.

import { readFileSync, existsSync } from 'node:fs';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

import { linhasDeConta, avaliarCobertura, LIMIAR_COBERTURA, MINIMO_PARA_AVALIAR } from './lib/cobertura.mjs';

const RAIZ = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const PASTA = process.argv.find((a) => !a.startsWith('--') && a.endsWith('pdf'))
  ?? resolve(RAIZ, 'test-data/book-canastra/pdf');
const JSON_SAIDA = process.argv.includes('--json');

// ---------------------------------------------------------------------------
// A FAIXA ACEITÁVEL, e por que cada número é este.
// ---------------------------------------------------------------------------

// A régua pode contar um pouco A MAIS que a verdade sem estragar nada: sobra
// vira "cobertura < 100%" num documento perfeito, e o limiar de 0,85 dá 15% de
// folga. Contar A MENOS é o erro perigoso — é ele que deixa passar extração pela
// metade —, por isso a faixa é ASSIMÉTRICA.
const ERRO_MAXIMO_PARA_MAIS = 0.15;
const ERRO_MAXIMO_PARA_MENOS = 0.05;

// Documento em que a régua sozinha já reprovaria uma extração PERFEITA. Zero é
// o alvo: qualquer um aqui é falso positivo garantido na fila de revisão, e é o
// número que o comentário do `LIMIAR_COBERTURA` pede para vigiar.
const MAX_FALSOS_POSITIVOS = 0;

// ---------------------------------------------------------------------------
// O DEFEITO QUE ESTA MEDIÇÃO ACHOU — E QUE ELA AGORA IMPEDE DE VOLTAR.
//
// A guarda comparava CONTAS DISTINTAS gravadas contra LINHAS DE CONTA do texto.
// As duas só viram a mesma unidade quando cada linha tem rótulo próprio — e num
// livro razão isso é falso por construção: o mesmo fornecedor aparece em vários
// lançamentos. Medido no book (`contas_distintas_verdade` ÷ `linhas_de_conta_verdade`):
//
//     17_Livro_Razao ............ 99 linhas, 66 rótulos distintos → 0,67
//     19_Faturamento_Intragrupo . 15 linhas,  7 rótulos distintos → 0,47
//     20_Mapa_de_Divida ......... 12 linhas,  8 rótulos distintos → 0,67
//
// Nos três, extração PERFEITA se reportava abaixo do limiar e a pendência era
// falsa. Corrigido em 17/08: `achatarGrupos` marca cada entrada com a LINHA do
// documento que a originou, `juntarBlocos` conta as linhas distintas depois de
// limpar a emenda, e a guarda compara linha com linha. O `linha_origem` não chega
// ao banco.
//
// Este script continua exibindo o segundo cenário — o que aconteceria se a guarda
// voltasse a se reportar em contas distintas — como EVIDÊNCIA de por que a unidade
// importa. Ele não reprova por isso: rótulo repetido é propriedade do documento, e
// o livro razão vai aparecer nessa lista para sempre. Quem tranca a regressão são
// os testes de unidade, que exigem a contagem em linhas.

// ---------------------------------------------------------------------------

const ler = (arquivo) => {
  const caminho = resolve(PASTA, arquivo);
  if (!existsSync(caminho)) {
    console.error(`Falta ${caminho}.`);
    console.error('Gere o book primeiro: cd test-data/book-canastra && PYTHONPATH=. python3 gerar.py');
    process.exit(2);
  }
  return JSON.parse(readFileSync(caminho, 'utf8'));
};

const metricas = ler('METRICAS.json').documentos;
const textos = ler('TEXTO_EXTRAIDO.json').documentos;

const pct = (v) => `${(v * 100).toFixed(0)}%`;

const linhas = metricas.map((m) => {
  const texto = (textos[m.arquivo] ?? []).join('\n');
  const regua = linhasDeConta(texto).length;
  const verdade = m.linhas_de_conta_verdade;
  // Erro relativo da régua contra a verdade. Positivo = contou a mais.
  const erro = verdade > 0 ? (regua - verdade) / verdade : (regua > 0 ? Infinity : 0);
  // A pergunta que decide: com a extração PERFEITA (todas as contas gravadas),
  // esta régua abriria pendência? É exatamente a chamada que roda em produção.
  const comExtracaoPerfeita = avaliarCobertura({ extraidas: verdade, esperadas: regua });
  // O segundo cenário: a extração devolve TUDO, mas se reporta na unidade que ela
  // tem — contas distintas. É o número que a guarda vê de verdade em produção.
  const distintas = m.contas_distintas_verdade ?? verdade;
  const comoAGuardaVe = avaliarCobertura({ extraidas: distintas, esperadas: regua });
  return {
    arquivo: m.arquivo,
    verdade,
    distintas,
    regua,
    erro,
    falsoPositivo: comExtracaoPerfeita !== null,
    falsoPositivoPorRotulo: comExtracaoPerfeita === null && comoAGuardaVe !== null,
  };
});

// Documento sem conta nenhuma (certidão, organograma, parecer) não tem régua a
// calibrar — e é o caso que a `0111` trata: zero linha ali é o resultado certo.
const comContas = linhas.filter((l) => l.verdade > 0);
const semContas = linhas.filter((l) => l.verdade === 0);

// Documentos que a guarda sequer avalia (abaixo do mínimo) não entram na
// aferição: a régua pode errar neles à vontade que ninguém lê o resultado.
const avaliados = comContas.filter((l) => l.regua >= MINIMO_PARA_AVALIAR);

const erros = avaliados.map((l) => l.erro).sort((a, b) => a - b);
const mediana = erros.length ? erros[Math.floor(erros.length / 2)] : 0;
const paraMais = avaliados.filter((l) => l.erro > ERRO_MAXIMO_PARA_MAIS);
const paraMenos = avaliados.filter((l) => l.erro < -ERRO_MAXIMO_PARA_MENOS);
const falsos = avaliados.filter((l) => l.falsoPositivo);
// Cenário de regressão: e SE a guarda voltasse a se reportar em contas distintas?
const porRotulo = avaliados.filter((l) => l.falsoPositivoPorRotulo);
// A régua que a extração perfeita precisaria vencer: o pior caso manda, porque
// o limiar é aplicado documento a documento, não na média.
const piorRazao = avaliados.reduce((pior, l) => Math.min(pior, l.verdade / l.regua), 1);

if (JSON_SAIDA) {
  console.log(JSON.stringify({
    documentos: linhas,
    resumo: {
      avaliados: avaliados.length,
      sem_contas: semContas.length,
      erro_mediano: Number(mediana.toFixed(3)),
      para_mais: paraMais.map((l) => l.arquivo),
      para_menos: paraMenos.map((l) => l.arquivo),
      falsos_positivos: falsos.map((l) => l.arquivo),
      pior_razao_com_extracao_perfeita: Number(piorRazao.toFixed(3)),
      limiar: LIMIAR_COBERTURA,
    },
  }, null, 2));
} else {
  console.log(`\nA RÉGUA DA COBERTURA CONTRA A VERDADE — ${PASTA}\n`);
  console.log(`${'documento'.padEnd(54)}${'verdade'.padStart(8)}${'régua'.padStart(7)}${'erro'.padStart(8)}   com extração perfeita`);
  console.log('-'.repeat(110));
  for (const l of linhas) {
    const nome = l.arquivo.length > 52 ? `${l.arquivo.slice(0, 51)}…` : l.arquivo;
    let veredito;
    if (l.verdade === 0) veredito = l.regua === 0 ? 'sem conta (ok)' : `SEM CONTA, régua vê ${l.regua}`;
    else if (l.regua < MINIMO_PARA_AVALIAR) veredito = 'abaixo do mínimo (guarda muda)';
    else if (l.falsoPositivo) veredito = `PENDÊNCIA FALSA (${pct(l.verdade / l.regua)})`;
    else veredito = `passa (${pct(l.verdade / l.regua)})`;
    const erro = l.verdade > 0 ? `${l.erro >= 0 ? '+' : ''}${pct(l.erro)}` : '—';
    console.log(`${nome.padEnd(54)}${String(l.verdade).padStart(8)}${String(l.regua).padStart(7)}${erro.padStart(8)}   ${veredito}`);
  }
  console.log('-'.repeat(110));
  console.log(`\n${avaliados.length} documentos avaliados pela guarda · ${semContas.length} sem conta nenhuma`);
  console.log(`erro mediano da régua: ${mediana >= 0 ? '+' : ''}${pct(mediana)}`);
  console.log(`pior razão com extração PERFEITA: ${pct(piorRazao)} (limiar em vigor: ${pct(LIMIAR_COBERTURA)})`);
  if (falsos.length) {
    console.log(`\n⚠️  ${falsos.length} documento(s) abririam pendência mesmo com extração perfeita:`);
    for (const l of falsos) console.log(`   ${l.arquivo}: verdade ${l.verdade}, régua ${l.regua} → ${pct(l.verdade / l.regua)}`);
  }
  if (porRotulo.length) {
    console.log(`\n⚠️  ${porRotulo.length} documento(s) voltariam a ser falso positivo se a guarda medisse em`);
    console.log('    CONTAS DISTINTAS em vez de LINHAS — é a evidência de por que a unidade é linha:');
    for (const l of porRotulo) {
      console.log(`   ${l.arquivo}: ${l.verdade} linhas, ${l.distintas} rótulos distintos, régua ${l.regua} → ${pct(l.distintas / l.regua)}`);
    }
  }
}

const problemas = [];
if (paraMais.length) {
  problemas.push(`${paraMais.length} documento(s) com a régua contando mais de ${pct(ERRO_MAXIMO_PARA_MAIS)} A MAIS: `
    + paraMais.map((l) => `${l.arquivo} (${l.verdade}→${l.regua})`).join(', '));
}
if (paraMenos.length) {
  problemas.push(`${paraMenos.length} documento(s) com a régua contando mais de ${pct(ERRO_MAXIMO_PARA_MENOS)} A MENOS `
    + `— é o erro que deixa passar extração incompleta: `
    + paraMenos.map((l) => `${l.arquivo} (${l.verdade}→${l.regua})`).join(', '));
}
if (falsos.length > MAX_FALSOS_POSITIVOS) {
  problemas.push(`${falsos.length} documento(s) abririam pendência com extração PERFEITA (máximo tolerado: `
    + `${MAX_FALSOS_POSITIVOS}): ${falsos.map((l) => l.arquivo).join(', ')}`);
}

if (problemas.length) {
  console.error('\nA RÉGUA SAIU DA FAIXA:');
  for (const p of problemas) console.error(`  • ${p}`);
  console.error('\nOu a régua (`linhasDeConta`) precisa de ajuste, ou o limiar (`LIMIAR_COBERTURA`) precisa '
    + 'de outro número — e a escolha é entre encher a fila de falso positivo e deixar passar documento pela metade.');
  process.exit(1);
}
