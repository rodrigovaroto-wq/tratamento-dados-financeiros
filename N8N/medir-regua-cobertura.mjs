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
// A ENTRADA ERRADA — o defeito que este script TINHA, corrigido em 31/08/2026.
// Até aqui ele media a régua contra o `TEXTO_EXTRAIDO.json`, que é o agrupamento
// do GERADOR: um texto que produção nunca vê. Devolvia "erro mediano +3%" e
// passava, honestamente, sobre a entrada errada — enquanto em produção o mesmo
// `17_Livro_Razao` dava régua 258 contra as 99 linhas que o documento tem, e
// abria pendência FALSA sobre extração completa. Portão que mede a entrada errada
// tem exatamente a mesma aparência de um portão que mede a certa e não acha nada.
//
// Agora a entrada é a CAPTURA DE PRODUÇÃO: o texto como o nó `Extrair Texto` do
// n8n o produziu, versionado em `Dados de Teste/capturas/2026-08-31-texto-extraido-n8n/`
// com a procedência (workflow, execução, nó). Ela cobre 20 dos 38 documentos, e
// os outros 18 **não gatilham nada**: aparecem numa lista à parte, dizendo que não
// foram medidos contra produção, em vez de deixar a tabela parecer completa.
//
// A VERDADE VEM DE QUEM ESCREVEU O DOCUMENTO. O gerador do `book-canastra` conta,
// enquanto monta cada tabela, quantas linhas têm rótulo e pelo menos um valor
// (`render.py`, `CONTAGEM`) e grava isso no `METRICAS.json` como
// `linhas_de_conta_verdade`. Não é outra leitura do PDF: é o dado antes de virar
// página. Conferir heurística contra heurística não prova nada.
//
//   node N8N/medir-regua-cobertura.mjs           # tabela por documento
//   node N8N/medir-regua-cobertura.mjs --json    # para script
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
  ?? resolve(RAIZ, 'Dados de Teste/book-canastra/pdf');
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

// O ERRO MÁXIMO EM QUALQUER DOCUMENTO CAPTURADO DE PRODUÇÃO, e por que ele é
// meio ponto percentual.
//
// A faixa acima (+15%/-5%) responde "a régua atrapalha a GUARDA?" — e por isso
// só olha os documentos que a guarda chega a avaliar (régua >= MINIMO_PARA_AVALIAR).
// Ela deixava de fora justamente os pequenos, e um erro de +1 linha num documento
// de 12 é +8% sem ninguém reclamar.
//
// Esta segunda trava responde outra pergunta: **a régua ainda está exata?** Em
// 31/08, depois de `juntarFragmentosDeLinha` e `ehLinhaSemValor`, ela acerta a
// verdade do gerador em TODOS os 20 documentos capturados — 20 de 20, erro 0,0%.
// Sem uma trava, esse 0% envelhece calado: alguém mexe na régua, o erro volta
// para 3% e o portão continua verde porque 3% cabe em 15%.
//
// Meio ponto é "zero com folga para arredondamento", não uma tolerância de
// projeto: num documento de 200 linhas ele nem chega a permitir UMA linha de
// diferença. Quando um documento novo legitimamente não couber aqui, o número
// sobe DE PROPÓSITO, com a medição na mensagem do commit — e a doutrina da
// assimetria continua valendo: relaxe o lado de contar A MAIS, nunca o de contar
// a menos, porque é o de menos que deixa passar extração pela metade.
const ERRO_MAXIMO_EM_PRODUCAO = 0.005;

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
    console.error('Gere o book primeiro: cd "Dados de Teste"/book-canastra && PYTHONPATH=. python3 gerar.py');
    process.exit(2);
  }
  return JSON.parse(readFileSync(caminho, 'utf8'));
};

const metricas = ler('METRICAS.json').documentos;
const textos = ler('TEXTO_EXTRAIDO.json').documentos;

// A CAPTURA DE PRODUÇÃO. É ela que manda: onde ela tem o documento, o texto do
// gerador não é consultado. `origem` viaja junto para o cabeçalho da tabela —
// número sem procedência é o que este projeto passa o tempo desfazendo.
const CAPTURA = resolve(RAIZ, 'Dados de Teste/capturas/2026-08-31-texto-extraido-n8n/textos.json');
if (!existsSync(CAPTURA)) {
  console.error(`Falta a captura de produção em ${CAPTURA}.`);
  console.error('Sem ela este portão mede o texto do GERADOR, que produção nunca vê — e passa por engano.');
  process.exit(2);
}
const capturado = JSON.parse(readFileSync(CAPTURA, 'utf8'));

const pct = (v) => `${(v * 100).toFixed(0)}%`;
// Teto sub-percentual precisa de casa decimal: `pct(0,005)` imprimiria "1%", que
// é o dobro do que o portão exige e ensinaria o número errado a quem lê.
const pctFino = (v) => `${Number((v * 100).toFixed(1))}%`;

const linhas = metricas.map((m) => {
  const daProducao = capturado.documentos[m.arquivo];
  const texto = daProducao ? daProducao.texto : (textos[m.arquivo] ?? []).join('\n');
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
    // A DISTINÇÃO QUE FAZ O PORTÃO HONESTO: só o que veio de produção decide.
    producao: Boolean(daProducao),
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
// E só o que veio da CAPTURA DE PRODUÇÃO decide alguma coisa. Documento medido
// sobre o texto do gerador entra na tabela marcado, e sai da aferição: ele não
// prova nem desmente nada sobre a régua que roda no n8n.
const avaliados = comContas.filter((l) => l.regua >= MINIMO_PARA_AVALIAR && l.producao);
const semProducao = linhas.filter((l) => !l.producao);

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
      medidos_contra_producao: linhas.filter((l) => l.producao).length,
      sem_captura_de_producao: semProducao.map((l) => l.arquivo),
      captura: capturado.origem,
      sem_contas: semContas.length,
      erro_mediano: Number(mediana.toFixed(3)),
      para_mais: paraMais.map((l) => l.arquivo),
      para_menos: paraMenos.map((l) => l.arquivo),
      falsos_positivos: falsos.map((l) => l.arquivo),
      pior_razao_com_extracao_perfeita: Number(piorRazao.toFixed(3)),
      exatos_em_producao: linhas.filter((l) => l.producao && l.verdade > 0 && l.regua === l.verdade).length,
      com_conta_em_producao: linhas.filter((l) => l.producao && l.verdade > 0).length,
      erro_maximo_em_producao: ERRO_MAXIMO_EM_PRODUCAO,
      limiar: LIMIAR_COBERTURA,
    },
  }, null, 2));
} else {
  console.log(`\nA RÉGUA DA COBERTURA CONTRA A VERDADE — ${PASTA}\n`);
  console.log(`texto de PRODUÇÃO: execução ${capturado.origem.execucao} do n8n (${capturado.origem.iniciada_em}), `
    + `nó "${capturado.origem.no}" — ${capturado.origem.documentos_capturados} de ${capturado.origem.documentos_na_execucao} documentos\n`);
  console.log(`${'documento'.padEnd(54)}${'verdade'.padStart(8)}${'régua'.padStart(7)}${'erro'.padStart(8)}   com extração perfeita`);
  console.log('-'.repeat(110));
  for (const l of linhas) {
    const nome = l.arquivo.length > 52 ? `${l.arquivo.slice(0, 51)}…` : l.arquivo;
    let veredito;
    if (!l.producao) veredito = 'NÃO MEDIDO CONTRA PRODUÇÃO (texto do gerador)';
    else if (l.verdade === 0) veredito = l.regua === 0 ? 'sem conta (ok)' : `SEM CONTA, régua vê ${l.regua}`;
    else if (l.regua < MINIMO_PARA_AVALIAR) veredito = 'abaixo do mínimo (guarda muda)';
    else if (l.falsoPositivo) veredito = `PENDÊNCIA FALSA (${pct(l.verdade / l.regua)})`;
    else veredito = `passa (${pct(l.verdade / l.regua)})`;
    const erro = l.verdade > 0 ? `${l.erro >= 0 ? '+' : ''}${pct(l.erro)}` : '—';
    console.log(`${nome.padEnd(54)}${String(l.verdade).padStart(8)}${String(l.regua).padStart(7)}${erro.padStart(8)}   ${veredito}`);
  }
  console.log('-'.repeat(110));
  console.log(`\n${avaliados.length} documentos avaliados pela guarda SOBRE TEXTO DE PRODUÇÃO · ${semContas.length} sem conta nenhuma`);
  if (semProducao.length) {
    console.log(`\n⚠️  ${semProducao.length} documento(s) SEM captura de produção — não entraram na aferição.`);
    console.log('    Não são "passa": são "não medido". Capture-os na próxima rodada e substitua o arquivo');
    console.log('    em Dados de Teste/capturas/. Ver o README de lá.');
  }
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

// A EXATIDÃO, medida em CADA documento capturado de produção que tem conta —
// inclusive os pequenos, que a faixa acima não alcança.
const foraDaExatidao = linhas.filter((l) => l.producao && l.verdade > 0
  && Math.abs(l.erro) > ERRO_MAXIMO_EM_PRODUCAO);
const exatos = linhas.filter((l) => l.producao && l.verdade > 0 && l.regua === l.verdade);
const comContaEmProducao = linhas.filter((l) => l.producao && l.verdade > 0);

if (!JSON_SAIDA) {
  console.log(`régua EXATA em ${exatos.length} de ${comContaEmProducao.length} documentos de produção`
    + ` (teto de erro por documento: ${pctFino(ERRO_MAXIMO_EM_PRODUCAO)})`);
}

const problemas = [];
if (foraDaExatidao.length) {
  problemas.push(`${foraDaExatidao.length} documento(s) de produção com erro acima de `
    + `${pctFino(ERRO_MAXIMO_EM_PRODUCAO)}: `
    + foraDaExatidao.map((l) => `${l.arquivo} (${l.verdade}→${l.regua})`).join(', '));
}
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
