// O ESPELHO ENTRE A LIB E O QUE RODA EM PRODUÇÃO — as 26 funções, não duas.
//
// POR QUE ESTE ARQUIVO EXISTE. Toda função de `N8N/lib/*.mjs` que a ingestão usa
// mora em DOIS lugares: a lib, que as outras suítes exercitam, e uma cópia
// LITERAL dentro do `build-workflow.mjs`, que vai para o JSON e é **a única que o
// n8n executa**. Nós de Code do n8n não importam módulo, então a duplicação é
// estrutural e não dá para remover.
//
// O que dava para remover era o SILÊNCIO: até aqui, corrigir a lib e esquecer a
// cópia deixava a suíte VERDE e a produção errada. Aconteceu duas vezes na mesma
// sessão — no `Math.max` da confiança de classificação (documento que a IA
// declarou ilegível entrava sem revisão) e no `parseCsv` sem aspas (o valor da
// última coluna virava pedaço de nome).
//
// A ESTRATÉGIA, e por que não é comparar o texto. As cópias são MINIFICADAS de
// propósito (`const L=String(t||'')...`), com nomes de variável próprios: comparar
// fonte reprovaria por formatação e convidaria a "consertar" formatando, que é o
// pior desfecho possível para um teste. Compara-se COMPORTAMENTO — a mesma
// entrada nas duas implementações, saída idêntica.
//
// E O ASSERT QUE FAZ ESTE ARQUIVO DURAR é o último: ele varre o workflow, lista
// TODA função duplicada e exige que cada uma esteja coberta aqui ou declarada em
// `SEM_CASO` com motivo. A 27ª função duplicada não entra em silêncio.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

import { normalize } from '../lib/normalize.mjs';
import { mergeClassification } from '../lib/merge.mjs';
import { parseCsv } from '../lib/spreadsheet.mjs';
import { sha256Hex } from '../lib/hash.mjs';
import { parseTipo, parsePeriodo, parseEntidade } from '../lib/classifier.mjs';
import {
  avaliarCobertura, celulasDaLinha, celulasEstimadas, linhasComNumero, linhasDeConta,
  juntarFragmentosDeLinha, ehLinhaSemValor, ehLinhaDeConta,
  planejarFatias, instrucaoDaFatia, juntarBlocos,
} from '../lib/cobertura.mjs';
import {
  custoDaChamada, tokensDeSaida, bytesDoBinario, orcamentoDoLote,
  pesoDaChamadaDeClassificacao, custoEstimadoPorConteudo, orcamentoDoLotePorConteudo,
  vereditoDaCotaDiaria,
} from '../lib/custo.mjs';
import {
  normalizarUnidade, normalizarMoeda, diagnosticarErroApi, achatarGrupos,
  ehLinhaNaoMonetaria, escalaDeclaradaNaColuna,
} from '../lib/extract.mjs';
import { ALIASES } from '../lib/taxonomia.mjs';

const WORKFLOW = JSON.parse(
  readFileSync(new URL('../workflow.e1-ingestao.json', import.meta.url), 'utf8'),
);

/**
 * Varredura léxica do JS: devolve, para cada posição, se ela está em código de
 * verdade ou dentro de string / template / regex / comentário.
 *
 * POR QUE PRECISA DISSO. A primeira versão casava chaves contando `{` e `}` no
 * texto cru, e quebrava na primeira regex com quantificador — `/\d{2,4}/` tem uma
 * chave que não fecha bloco nenhum. O resultado eram corpos truncados e
 * `SyntaxError` em metade das funções. Contar chave em JS exige saber onde o
 * código termina e o literal começa; não há atalho honesto.
 */
function mapaDeCodigo(src) {
  const codigo = new Uint8Array(src.length); // 1 = código, 0 = literal/comentário
  let i = 0;
  // O último caractere significativo decide se `/` abre regex ou é divisão.
  let anterior = '';
  while (i < src.length) {
    const c = src[i];
    const prox = src[i + 1];
    if (c === '/' && prox === '/') { while (i < src.length && src[i] !== '\n') i++; continue; }
    if (c === '/' && prox === '*') { i += 2; while (i < src.length && !(src[i] === '*' && src[i + 1] === '/')) i++; i += 2; continue; }
    if (c === '"' || c === "'" || c === '`') {
      const aspa = c; i++;
      while (i < src.length) {
        if (src[i] === '\\') { i += 2; continue; }
        if (src[i] === aspa) { i++; break; }
        i++;
      }
      anterior = aspa; continue;
    }
    if (c === '/' && /[(,=:[!&|?{};+\-*%~^<>]|^$/.test(anterior)) {
      i++; let emClasse = false;
      while (i < src.length) {
        if (src[i] === '\\') { i += 2; continue; }
        if (src[i] === '[') emClasse = true;
        else if (src[i] === ']') emClasse = false;
        else if (src[i] === '/' && !emClasse) { i++; break; }
        i++;
      }
      while (i < src.length && /[a-z]/.test(src[i])) i++; // flags
      anterior = '/'; continue;
    }
    codigo[i] = 1;
    if (!/\s/.test(c)) anterior = c;
    i++;
  }
  return codigo;
}

/** Fim do bloco `{...}` que começa em `abre`, contando só chaves de CÓDIGO. */
function fimDoBloco(src, codigo, abre) {
  let prof = 0;
  for (let i = abre; i < src.length; i++) {
    if (!codigo[i]) continue;
    if (src[i] === '{') prof++;
    else if (src[i] === '}') { prof--; if (prof === 0) return i + 1; }
  }
  return -1;
}

/**
 * As DECLARAÇÕES de topo de um nó: o TEXTO delas, em ordem, e os nomes que são
 * função.
 *
 * DUAS FORMAS, e ignorar a segunda custou uma volta. O `build-workflow.mjs`
 * embute a maioria das funções como `const nome = function nome(...) {...};` —
 * expressão nomeada atribuída a uma constante, não declaração. Um extrator que
 * só reconhece `function nome(` acha 11 das 32 e conclui, errado, que as outras
 * "não estão no workflow".
 *
 * As constantes entram junto porque várias funções as usam — `parseTipo` lê a
 * tabela de tipos declarada acima dela. O que fica DE FORA é toda declaração que
 * toca `$(...)`, `$input`, `item` ou `items`: essas são o corpo do nó, existem só
 * dentro do n8n, e avaliá-las aqui derrubaria o teste por um motivo que não é
 * divergência.
 */
function declaracoesDeTopo(src) {
  const codigo = mapaDeCodigo(src);
  const nomes = new Map(); // nome da lib -> como chamá-lo no sandbox
  const partes = [];
  let i = 0, prof = 0;
  while (i < src.length) {
    if (!codigo[i]) { i++; continue; }
    const c = src[i];
    if (c === '{') { prof++; i++; continue; }
    if (c === '}') { prof--; i++; continue; }
    if (prof === 0) {
      const resto = src.slice(i);
      const mFn = /^(?:async\s+)?function\s+([A-Za-z_$][\w$]*)\s*\(/.exec(resto);
      if (mFn) {
        const fim = fimDoBloco(src, codigo, src.indexOf('{', i + mFn[0].length - 1));
        if (fim > 0) {
          partes.push({ nome: mFn[1], texto: src.slice(i, fim) });
          nomes.set(mFn[1], mFn[1]);
          i = fim; continue;
        }
      }
      const mDecl = /^(?:const|let|var)\s+([A-Za-z_$][\w$]*)\s*=/.exec(resto);
      if (mDecl) {
        let j = i, p2 = 0;
        for (; j < src.length; j++) {
          if (!codigo[j]) continue;
          if ('{(['.includes(src[j])) p2++;
          else if ('})]'.includes(src[j])) p2--;
          else if (src[j] === ';' && p2 === 0) break;
        }
        const texto = src.slice(i, j + 1);
        // SÓ TABELA LITERAL ENTRA como constante.
        //
        // As funções embutidas precisam de tabelas — `ALIASES`, o preço por
        // modelo, a lista de ruído. O que elas NUNCA precisam é das variáveis de
        // trabalho do nó (`const t = normalize(nome);`), e arrastá-las custou
        // duas voltas: além de estourarem ao avaliar, os nomes delas COLIDEM com
        // parâmetros — `parseTipo(t)` cita `t`, e o fecho transitivo puxava a
        // variável do nó por causa do parâmetro. Literal não tem esse problema:
        // é dado, não depende de nada, e é exatamente o que uma tabela é.
        const ehLiteral = /^(?:const|let|var)\s+[A-Za-z_$][\w$]*\s*=\s*(?:\[|\{|'|"|`|\d|\/|new (?:Set|Map)\(|Object\.freeze\()/
          .test(texto);
        const ehFuncao = /^(?:const|let|var)\s+[A-Za-z_$][\w$]*\s*=\s*(?:async\s*)?(?:function\b|\()/
          .test(texto);
        // O filtro de runtime vale para o INICIALIZADOR de constante comum, não
        // para o corpo de função: `diagnosticarErroApi` cita "item" numa frase de
        // comentário, e checar o texto inteiro a excluía do inventário.
        const usaRuntime = /\$\(|\$input|\$json|\bitems?\b|\bthis\b/.test(texto);
        if ((ehFuncao && !/\$\(|\$input|\$json/.test(texto)) || (ehLiteral && !usaRuntime)) {
          partes.push({ nome: mDecl[1], texto });
          // `const f = function f(){}` e `const f = (x) => …` são função para o
          // que este teste faz com elas: dá para chamar.
          if (ehFuncao) {
            nomes.set(mDecl[1], mDecl[1]);
            // `const normUnid = function normalizarUnidade(...)`: o nome da
            // CONSTANTE e o da FUNÇÃO diferem, e o segundo só existe dentro do
            // corpo dela. Quem procura pelo nome da lib tem de achar — pelo
            // acessor que funciona aqui fora, que é a constante.
            const mExpr = /=\s*(?:async\s*)?function\s+([A-Za-z_$][\w$]*)\s*\(/.exec(texto);
            if (mExpr && mExpr[1] !== mDecl[1]) nomes.set(mExpr[1], mDecl[1]);
          }
        }
        i = j + 1; continue;
      }
    }
    i++;
  }
  return { nomes, partes };
}

/** Toda função duplicada do workflow, com o nó em que ela vive. */
function inventarioDoWorkflow() {
  const inv = new Map();
  for (const no of WORKFLOW.nodes ?? []) {
    const src = no.parameters?.jsCode;
    if (typeof src !== 'string') continue;
    const { nomes, partes } = declaracoesDeTopo(src);
    for (const [nome, acessor] of nomes) if (!inv.has(nome)) inv.set(nome, { no: no.name, acessor, partes });
  }
  return inv;
}
const INVENTARIO = inventarioDoWorkflow();

/**
 * A implementação que o n8n executa, extraída do JSON COMMITADO.
 *
 * Leva TODAS as funções do mesmo nó junto — é mais barato que mapear dependência
 * a dependência à mão, e o custo de carregar uma função a mais é zero. O que NÃO
 * se leva é o corpo do nó fora das funções: lá há `$('Nó').item`, que não existe
 * fora do n8n e derrubaria a avaliação.
 */
function doWorkflow(nome) {
  const alvo = INVENTARIO.get(nome);
  assert.ok(alvo, `a função ${nome} não está em nenhum nó do workflow commitado`);
  // O FECHO TRANSITIVO, e não "junta tudo do nó e torce".
  //
  // Um nó declara, além das funções, constantes que dependem do CORPO dele
  // (`const aviso = binMeta.aviso_conteudo;`). Arrastá-las para o sandbox faz a
  // avaliação estourar por um motivo que não é divergência — e remendar isso com
  // uma lista de identificadores proibidos envelheceria a cada nó novo. Aqui só
  // entra o que a função ALVO alcança: começa nela e puxa, transitivamente, as
  // declarações cujos nomes ela cita. O resto do nó não é executado.
  const porNome = new Map(alvo.partes.map((p) => [p.nome, p]));
  const escolhidas = new Set();
  const fila = [alvo.acessor];
  while (fila.length > 0) {
    const atual = fila.pop();
    if (escolhidas.has(atual) || !porNome.has(atual)) continue;
    escolhidas.add(atual);
    const texto = porNome.get(atual).texto;
    for (const m of texto.matchAll(/[A-Za-z_$][\w$]*/g)) {
      if (porNome.has(m[0]) && !escolhidas.has(m[0])) fila.push(m[0]);
    }
  }
  const corpo = alvo.partes.filter((x) => escolhidas.has(x.nome)).map((x) => x.texto).join('\n');
  try {
    return new Function(`${corpo}\nreturn ${alvo.acessor};`)();
  } catch {
    // QUEDA PARA A FUNÇÃO SOZINHA. Boa parte delas é autossuficiente — não lê
    // tabela nenhuma —, e aí o fecho só pode atrapalhar: um parâmetro com nome
    // curto (`t`, `p`) coincide com uma variável de trabalho do nó e puxa junto
    // uma declaração que não compila fora do n8n. Se sozinha ela monta, é porque
    // dependência não havia.
    const soEla = alvo.partes.find((x) => x.nome === alvo.acessor);
    assert.ok(soEla, `não achei o texto de ${nome} no nó ${alvo.no}`);
    return new Function(`${soEla.texto}\nreturn ${alvo.acessor};`)();
  }
}

// -----------------------------------------------------------------------------
// A TABELA. Cada entrada: a função da lib e as chamadas que a exercitam.
//
// Os casos não precisam ser exaustivos — as suítes próprias de cada lib já fazem
// isso. Aqui basta EXERCITAR os ramos: o que se mede é se as duas implementações
// concordam, e duas implementações que concordam em cinco entradas diferentes
// dificilmente divergem em silêncio na sexta.
// -----------------------------------------------------------------------------
const TABELA = [
  { nome: 'normalize', lib: normalize, casos: [['Balanço_2025.PDF'], ['a  b'], [null], ['']] },

  // A DIFERENÇA DE CONTRATO, DECLARADA em vez de descoberta: a lib devolve
  // `{codigo, termo}` e a cópia do workflow devolve só o `codigo`. Não muda
  // comportamento — o nó usa apenas o código —, mas com o mesmo NOME e retornos
  // diferentes, quem melhorar o desempate por `termo` na lib não teria como
  // saber que o workflow não o carrega. Aqui a diferença fica escrita, e o
  // CÓDIGO escolhido continua tendo de bater.
  { nome: 'parseTipo', lib: parseTipo,
    porque: 'a lib devolve {codigo, termo}; o workflow devolve só o codigo',
    projLib: (r) => (r ? r.codigo : null),
    casos: [['balanco patrimonial 2025'], ['dre 2025'], ['mapa de divida'], ['arquivo qualquer']] },
  { nome: 'parsePeriodo', lib: parsePeriodo,
    casos: [['balanco 12m25'], ['dre 1t25'], ['fat l24m'], ['x 2023x2024x2025'], ['sem periodo']] },
  { nome: 'parseEntidade', lib: parseEntidade,
    casos: [['balanco vertentes metalurgica 2025', ALIASES], ['relatorio auditor independente', ALIASES]] },

  { nome: 'mergeClassification', lib: mergeClassification, casos: [
    [{ tipo_taxonomia: 'BALANCO', confianca: 0.6 }, { tipo_taxonomia: 'DRE', confianca: 0.9, justificativa: 'x' }],
    [{ tipo_taxonomia: 'BALANCO', confianca: 0.5 }, { tipo_taxonomia: null, confianca: 0.9, justificativa: 'ilegível' }],
    [{ tipo_taxonomia: null, confianca: 0.3 }, { tipo_taxonomia: 'DRE', confianca: 0.8, justificativa: 'x' }],
    [{ tipo_taxonomia: null, confianca: 0.2 }, { tipo_taxonomia: null, confianca: 0.1, justificativa: '' }],
  ] },

  { nome: 'parseCsv', lib: parseCsv, casos: [
    ['a,b\n1,2'], ['a;b\n1;2'], ['nome,obs,v\nEmpresa,"Silva, João & Cia",1000'],
    ['a,b\n"x""y",2'], ['a,b\n"li\nnha",2'], ['n;o\nX;"a,b,c"'], [''],
  ] },
  { nome: 'sha256Hex', lib: sha256Hex,
    casos: [[Buffer.from('abc')], [Buffer.from('')], [Buffer.from('Ação — çãé')]] },

  { nome: 'linhasDeConta', lib: linhasDeConta, casos: [
    ['Caixa 1.000\nCNPJ 12.345.678/0001-99\nEstoques 2.500\nPágina 1'],
    ['1.1.01.002  181  D\n2025 2024 2023\nReceita bruta 10.000,50'],
    // A linha visual fragmentada, literal da captura de produção. Se a cópia
    // inline ficar sem a emenda, é aqui que ela reprova — e era a divergência
    // que deixava a lib certa e produção contando 258 onde há 99.
    ['01/12/2025 LC-2025-4000 \nNF 010000 - Papéis e Celulose Aracati S.A. \n- 150 16.839 C'],
    [''], [null],
  ] },
  { nome: 'juntarFragmentosDeLinha', lib: juntarFragmentosDeLinha, casos: [
    // Literais da captura de produção (execução 7276): o espaço no fim do
    // fragmento é o dado real, e é o que a cópia inline precisa respeitar.
    ['01/12/2025 LC-2025-4000 \nNF 010000 - Papéis e Celulose Aracati S.A. \n- 150 16.839 C'],
    ['Banco Meridional S.A. Capital de giro CG-2021-884.117 \n15/03/2026 CDI + 4,80% a.a. 10.412.600,00 '],
    ['ATIVO 137.624 163.941\nAtivo Circulante 44.022'],
    ['a 1 \n\nb 2'], ['a 1 \nb 2 \nc 3 \nd 4 \ne 5 \nf 6'], [''], [null],
  ] },
  { nome: 'ehLinhaDeConta', lib: ehLinhaDeConta, casos: [
    ['Ativo Circulante 44.022 68.103'], ['1.1.01.002 181 D'], ['ATIVO CIRCULANTE'],
    ['Posição em 31 de dezembro de 2025'], ['CNPJ 44.555.667/0001-59'],
    ['- 150 16.839 C'], ['2025 2024 2023'], [''], [null],
  ] },
  { nome: 'ehLinhaSemValor', lib: ehLinhaSemValor, casos: [
    // As cinco frases reais da captura, e as três contas que precisam sobreviver.
    ['Posição em 31 de dezembro de 2025'], ['Movimento de dezembro de 2025'],
    ['Encerramento do exercício de 2025'], ['Exercícios de 2023, 2024 e 2025'],
    ['Janeiro de 2023 a dezembro de 2025'],
    ['Total de 2023 7.120'], ['01/12/2025 SALDO ANTERIOR 16.689 C'], ['Ativo Circulante 44.022'],
    [''], [null],
  ] },
  { nome: 'linhasComNumero', lib: linhasComNumero,
    casos: [['a 1\nb\nc 3'], [''], [null]] },
  { nome: 'celulasDaLinha', lib: celulasDaLinha,
    casos: [['Caixa 1.000 2.000 3.000'], ['Só rótulo'], ['']] },
  { nome: 'celulasEstimadas', lib: celulasEstimadas,
    casos: [[['a 1 2', 'b 3']], [[]]] },
  { nome: 'avaliarCobertura', lib: avaliarCobertura, casos: [
    [{ extraidas: 90, esperadas: 100 }], [{ extraidas: 30, esperadas: 100 }],
    [{ extraidas: 5, esperadas: 6 }], [{ extraidas: 0, esperadas: 0 }],
  ] },
  { nome: 'planejarFatias', lib: planejarFatias,
    casos: [[500, 234, null], [10, 234, null], [0, 234, null]] },
  { nome: 'instrucaoDaFatia', lib: instrucaoDaFatia, casos: [
    [{ bloco: 1, blocos: 3, de: 0, ate: 100, ancoraInicio: null, ancoraFim: 'Estoques' }],
    [{ bloco: 1, blocos: 1, de: 0, ate: 0, ancoraInicio: null, ancoraFim: null }],
  ] },
  { nome: 'juntarBlocos', lib: juntarBlocos, casos: [
    [[]],
    [[{ campos: [{ chave: 'Caixa', valor_num: 1 }], linhas: 1 },
      { campos: [{ chave: 'Caixa', valor_num: 1 }, { chave: 'Estoques', valor_num: 2 }], linhas: 2 }]],
  ] },

  { nome: 'custoDaChamada', lib: custoDaChamada, casos: [
    [{ prompt_tokens: 1000, completion_tokens: 500 }, 'gpt-4o'],
    [{ prompt_tokens: 1000, completion_tokens: 500, prompt_tokens_details: { cached_tokens: 800 } }, 'gpt-4o-mini'],
    [null, 'gpt-4o'], [{}, 'modelo-desconhecido'],
  ] },
  { nome: 'tokensDeSaida', lib: tokensDeSaida, casos: [[100, 1], [100, 3], [0, 0]] },
  { nome: 'bytesDoBinario', lib: bytesDoBinario,
    casos: [[{ fileSize: '1.2 MB' }], [{ data: 'YWJj' }], [null], [{}]] },
  { nome: 'pesoDaChamadaDeClassificacao', lib: pesoDaChamadaDeClassificacao,
    casos: [[1_000_000], [0], [50_000_000]] },
  { nome: 'custoEstimadoPorConteudo', lib: custoEstimadoPorConteudo,
    casos: [[{ paginas: 3, celulas: 200, colunas: 2 }], [{ paginas: 0, celulas: 0, colunas: 1 }]] },
  { nome: 'orcamentoDoLote', lib: orcamentoDoLote,
    casos: [[{ documentos: [] }], [{ documentos: [{ bytes: 1_000_000 }, { bytes: 2_000_000 }] }]] },
  { nome: 'orcamentoDoLotePorConteudo', lib: orcamentoDoLotePorConteudo, casos: [
    [{ documentos: [] }],
    [{ documentos: [{ paginas: 2, celulas: 100, colunas: 1 }, { paginas: 5, celulas: 400, colunas: 3 }] }],
  ] },
  // Os três vereditos, e o quarto que é "não sei": abaixo do aviso (silencioso),
  // acima do aviso mas cabendo, estourando o dia, e `rpd` nulo — a OpenAI não
  // publica um número único para o Tier 1, e nulo NÃO pode virar "cabe".
  { nome: 'vereditoDaCotaDiaria', lib: vereditoDaCotaDiaria, casos: [
    [{ chamadas: 63, rpd: 500 }],
    [{ chamadas: 440, rpd: 500 }],
    [{ chamadas: 501, rpd: 500 }],
    [{ chamadas: 900, rpd: null }],
  ] },

  { nome: 'normalizarUnidade', lib: normalizarUnidade,
    casos: [['mil'], ['R$ mil'], ['milhões'], ['unidade'], ['sacas'], [null], ['']] },
  { nome: 'normalizarMoeda', lib: normalizarMoeda,
    casos: [['R$'], ['US$'], ['EUR'], ['reais'], ['iene'], [null], ['']] },

  // Os casos da v47 estão aqui de propósito: são os que a versão ANTERIOR desta
  // função errava, com a coluna ignorada. `Quantidade` e `Efetivo (pessoas)`
  // herdavam escala e moeda do documento — 1.240 bobinas e 96 pessoas prontas
  // para virar bilhão e milhão de pessoas.
  { nome: 'ehLinhaNaoMonetaria', lib: ehLinhaNaoMonetaria, casos: [
    ['Bobina kraft 180 g/m²', '2.513', 'Valor (R$ mil)'],
    ['Bobina kraft 180 g/m²', '1.240', 'Quantidade'],
    ['Produção - turno A', '96', 'Efetivo (pessoas)'],
    ['2023 - Agro para Indústria', '2023', 'Exercício'],
    ['Margem de contribuição', '12%', null],
    ['Ativo Circulante', '44.022', '31/12/2025'],
    [null, null, null], ['', '', ''],
  ] },
  // E aqui os dois documentos que declaravam "R$ mil" em cada coluna e vieram
  // com `milhao` no cabeçalho do documento.
  { nome: 'escalaDeclaradaNaColuna', lib: escalaDeclaradaNaColuna, casos: [
    ['Valor (R$ mil)'], ['Custo anual com encargos (R$ mil)'], ['Saldo (R$ milhões)'],
    ['31/12/2025'], ['Saldo devedor (R$)'], [null], [''],
  ] },
  { nome: 'diagnosticarErroApi', lib: diagnosticarErroApi, casos: [
    [{ error: { message: 'rate limit', code: 'rate_limit_exceeded' } }],
    [{ choices: [{ finish_reason: 'length' }] }],
    [null], [{}],
  ] },
  { nome: 'achatarGrupos', lib: achatarGrupos, casos: [
    [[]], [null],
    [[{ s: 'ATIVO', sc: 'ativo_circulante', pc: '2025', linhas: [
      { k: 'Caixa', vn: 100 }, { k: 'Estoques', vn: 200 }] }]],
  ] },
];

// FUNÇÕES DUPLICADAS QUE NÃO TÊM CASO AQUI, cada uma com o motivo. Não é lista de
// perdão: é o que impede o assert final de virar decoração.
const SEM_CASO = new Map([
  // Nenhuma hoje. Quando houver, o motivo entra aqui e o assert final passa a
  // aceitá-la — deliberadamente, não por esquecimento.
]);

// -----------------------------------------------------------------------------
for (const { nome, lib, casos, projLib = (x) => x, projWf = (x) => x, porque } of TABELA) {
  test(`espelho: ${nome} — a lib e o workflow decidem IGUAL${porque ? ' (contrato reduzido)' : ''}`, () => {
    const noWorkflow = doWorkflow(nome);
    for (const args of casos) {
      const esperado = projLib(lib(...args));
      const obtido = projWf(noWorkflow(...args));
      assert.deepEqual(obtido, esperado,
        `${nome}(${JSON.stringify(args).slice(0, 90)}) diverge — o workflow é o que RODA`);
    }
  });
}

test('TODA função duplicada está coberta, ou declarada com motivo', () => {
  const naLib = new Set(TABELA.map((t) => t.nome));
  const faltando = [];
  for (const [nome] of INVENTARIO) {
    // Só interessa o que EXISTE nos dois lados. Função que só vive inline (helper
    // de um nó, sem par na lib) não tem espelho a manter.
    const temPar = ['normalize', 'merge', 'spreadsheet', 'hash', 'classifier', 'cobertura', 'custo', 'extract']
      .some((m) => {
        try {
          return new RegExp(`(export )?(async )?function ${nome}\\b`)
            .test(readFileSync(new URL(`../lib/${m}.mjs`, import.meta.url), 'utf8'));
        } catch { return false; }
      });
    if (!temPar) continue;
    if (naLib.has(nome) || SEM_CASO.has(nome)) continue;
    faltando.push(nome);
  }
  assert.deepEqual(faltando, [],
    'função duplicada entre a lib e o workflow SEM caso de espelho: '
    + `${faltando.join(', ')}. Acrescente à TABELA, ou a SEM_CASO com o motivo. `
    + 'Sem isso, corrigir a lib e esquecer a cópia inline volta a deixar a suíte '
    + 'verde e a produção errada.');
});

test('o inventário do workflow não encolheu sem alguém notar', () => {
  // Contador, no idioma do CLAUDE.md: se cair, alguém apagou cobertura — ou o
  // workflow deixou de embutir uma função e ninguém disse.
  assert.ok(INVENTARIO.size >= 30,
    `o workflow declara ${INVENTARIO.size} funções embutidas; eram 32 quando este `
    + 'assert foi escrito. Queda significa função removida do workflow.');
});
