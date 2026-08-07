import { test } from 'node:test';
import assert from 'node:assert/strict';
import { normalize } from '../lib/normalize.mjs';
import { classifyByFilename, parseEntidade, parsePeriodo, parseTipo } from '../lib/classifier.mjs';

test('normalize remove acento, extensão e separadores', () => {
  assert.equal(normalize('12M25_DRE (Assinado).pdf'), '12m25 dre (assinado)');
  assert.equal(normalize('Balanço-Patrimonial.XLSX'), 'balanco patrimonial');
  assert.equal(normalize(null), '');
});

test('parsePeriodo reconhece as convenções de f0/03', () => {
  assert.deepEqual(parsePeriodo('12m25 dre'), { tipo: 'anual', referencia: '12M25' });
  assert.deepEqual(parsePeriodo('12m24 balanco'), { tipo: 'anual', referencia: '12M24' });
  assert.deepEqual(parsePeriodo('1t25 dre'), { tipo: 'trimestre', referencia: '1T25' });
  assert.deepEqual(parsePeriodo('1t26 balanco'), { tipo: 'trimestre', referencia: '1T26' });
  assert.deepEqual(parsePeriodo('faturamento l24m'), { tipo: 'multi', referencia: 'L24M' });
  assert.deepEqual(parsePeriodo('faturamento 36 meses'), { tipo: 'multi', referencia: 'L36M' });
  assert.deepEqual(parsePeriodo('mutuos 23 24 25'), { tipo: 'multi', referencia: '23,24,25' });
});

test('parsePeriodo reconhece ano isolado (sinal fraco)', () => {
  assert.deepEqual(parsePeriodo('balanco acumulado 2025'), { tipo: 'anual', referencia: '2025', fraco: true });
  assert.deepEqual(parsePeriodo('relatorio 2024'), { tipo: 'anual', referencia: '2024', fraco: true });
});

test('parsePeriodo reconhece intervalo de anos (expande a lista inteira)', () => {
  assert.deepEqual(parsePeriodo('mutuos 2021-2025'), { tipo: 'multi', referencia: '21,22,23,24,25' });
  assert.deepEqual(parsePeriodo('mutuos 2021 a 2025'), { tipo: 'multi', referencia: '21,22,23,24,25' });
  assert.deepEqual(parsePeriodo('mutuos 21-25'), { tipo: 'multi', referencia: '21,22,23,24,25' });
  assert.deepEqual(parsePeriodo('mutuos 2023-2024'), { tipo: 'multi', referencia: '23,24' });
});

test('parsePeriodo: intervalo invertido (fim < início) não expande, cai no fallback de lista', () => {
  // start > end: a expansão não roda; ainda assim os 2 números viram lista
  // multi-ano — ORDENADA, para que "2025-2021" e "2021,2025" tenham a MESMA
  // forma canônica (o mesmo critério de `fn_periodo_canonico` no Postgres:
  // notações equivalentes do mesmo período não podem parecer divergentes).
  assert.deepEqual(parsePeriodo('mutuos 2025-2021'), { tipo: 'multi', referencia: '21,25' });
});

test('parsePeriodo: prefixo de ORDENAÇÃO do arquivo não é ano (bug real do teste v24)', () => {
  // "13_Balancete_..._2025.pdf" saía como período "multi 13,25" — o "13" do
  // prefixo virava 2013. Além de exibir errado, fragmentava a tabela `periodo`
  // e impedia a reconciliação de casar documentos do mesmo exercício.
  assert.deepEqual(parsePeriodo('13 balancete analitico componentes 2025'),
    { tipo: 'anual', referencia: '2025', fraco: true });
  assert.deepEqual(parsePeriodo('08 dfc vertentes metalurgica 2025'),
    { tipo: 'anual', referencia: '2025', fraco: true });
  // "2025x2024" é o padrão de nome de demonstração comparativa.
  assert.deepEqual(parsePeriodo('01 bp vertentes metalurgica 2025x2024'),
    { tipo: 'multi', referencia: '24,25' });
  // Não regride os formatos estruturados nem o ano isolado.
  assert.deepEqual(parsePeriodo('12m25 dre'), { tipo: 'anual', referencia: '12M25' });
  assert.deepEqual(parsePeriodo('1t25 dre'), { tipo: 'trimestre', referencia: '1T25' });
  assert.deepEqual(parsePeriodo('faturamento 36 meses'), { tipo: 'multi', referencia: 'L36M' });
  assert.deepEqual(parsePeriodo('balanco acumulado 2025'), { tipo: 'anual', referencia: '2025', fraco: true });
});

test('parseTipo mapeia termos → código, específico antes de genérico', () => {
  assert.equal(parseTipo('dre').codigo, 'DRE');
  assert.equal(parseTipo('balanco patrimonial').codigo, 'BALANCO');
  assert.equal(parseTipo('fluxo de caixa').codigo, 'FLUXO_CAIXA');
  assert.equal(parseTipo('combinado').codigo, 'COMBINADO');
  assert.equal(parseTipo('contrato social').codigo, 'CONTRATO_SOCIAL');
  assert.equal(parseTipo('relacao de mutuos').codigo, 'MUTUOS');
  // "faturamento intragrupo" NÃO pode cair em FATURAMENTO_24M
  assert.equal(parseTipo('faturamento intragrupo').codigo, 'FAT_INTRAGRUPO');
  assert.equal(parseTipo('faturamento 24m').codigo, 'FATURAMENTO_24M');
  // balancete (variável) não pode ser confundido com balanço
  assert.equal(parseTipo('balancete').codigo, 'BALANCETE');
});

test('parseTipo reconhece DMPL e DVA (db/migrations/0024) sem roubar o arquivo COMPOSTO', () => {
  // Antes da 0024 não existia código nenhum para estas duas: o enum que a IA
  // recebe (`codigosConhecidos`) é fechado nos códigos da taxonomia, e a DMPL do
  // book saía classificada como MUTUOS — o vizinho mais próximo do que existia.
  assert.equal(parseTipo(normalize('09_DMPL_Vertentes_Metalurgica_2025.pdf')).codigo, 'DMPL');
  assert.equal(parseTipo(normalize('Demonstração das Mutações do Patrimônio Líquido 2025.pdf')).codigo, 'DMPL');
  assert.equal(parseTipo(normalize('DVA 2025.pdf')).codigo, 'DVA');
  assert.equal(parseTipo(normalize('Demonstração do Valor Adicionado 2025.pdf')).codigo, 'DVA');

  // …e a regressão que a ORDEM dos aliases protege: o caso comum de "DMPL" no
  // nome de arquivo NÃO é a DMPL — é o arquivo COMPOSTO (este é um nome real do
  // dono), em que a DMPL é uma das demonstrações e o tipo do documento é o da
  // demonstração PRINCIPAL (f0/03). Se DMPL/DVA fossem testados antes das
  // demonstrações principais, estes dois arquivos mudariam de tipo.
  // (Qual das principais ganha é decisão anterior a esta fatia: aqui 'dfc' casa
  // FLUXO_CAIXA antes de 'balanco'. O que importa é que não vira DMPL — e o
  // diagnóstico por CONTEÚDO, que é quem decide de fato, corrige o resto.)
  const composto = parseTipo(normalize('Balanço Patrimonial DRE, DFC, DMPL Global One 2024assinado.pdf'));
  assert.notEqual(composto.codigo, 'DMPL');
  assert.equal(composto.codigo, 'FLUXO_CAIXA');
  assert.equal(parseTipo(normalize('DRE e DVA consolidadas 2025.pdf')).codigo, 'DRE');
});

test('classifyByFilename — nomes descritivos dão alta confiança', () => {
  const r = classifyByFilename('12M25 DRE (Assinado).pdf');
  assert.equal(r.tipo_taxonomia, 'DRE');
  assert.deepEqual(r.periodo, { tipo: 'anual', referencia: '12M25' });
  assert.equal(r.assinado, true);
  assert.ok(r.confianca >= 0.9, `confianca=${r.confianca}`);
  assert.equal(r.precisa_fallback_openai, false);
});

test('classifyByFilename — nome genérico cai para fallback OpenAI', () => {
  const r = classifyByFilename('documento_final_v2.pdf');
  assert.equal(r.tipo_taxonomia, null);
  assert.equal(r.periodo, null);
  assert.ok(r.confianca < 0.7);
  assert.equal(r.precisa_fallback_openai, true);
});

test('classifyByFilename — tipo sem período ainda pede fallback (confiança 0.6)', () => {
  const r = classifyByFilename('balanco.pdf');
  assert.equal(r.tipo_taxonomia, 'BALANCO');
  assert.equal(r.periodo, null);
  assert.equal(r.confianca, 0.6);
  assert.equal(r.precisa_fallback_openai, true); // < 0.7
});

test('classifyByFilename — tipo + ano isolado NÃO ultrapassa o limiar sozinho (sempre verifica com a IA)', () => {
  // Caso real: "BALANÇO ACUMULADO 2025.pdf" — ter "BALANÇO" no nome + um ano
  // solto não é suficiente para aceitar sem checar o conteúdo (feedback do dono).
  const r = classifyByFilename('BALANÇO ACUMULADO 2025.pdf');
  assert.equal(r.tipo_taxonomia, 'BALANCO');
  assert.deepEqual(r.periodo, { tipo: 'anual', referencia: '2025', fraco: true });
  assert.equal(r.confianca, 0.65, `confianca=${r.confianca} deve ficar abaixo do limiar 0.7`);
  assert.equal(r.precisa_fallback_openai, true, 'ano isolado não deve pular a verificação da IA');
});

test('classifyByFilename — o CONJUNTO do exercício é DF_AUDITADA, e nome com demonstração principal não é', () => {
  // Como o conjunto chega de verdade: um PDF só, com tudo dentro. Antes ficava
  // SEM TIPO (a taxonomia só reconhecia "auditadas"), e documento sem tipo não
  // ganha aba de demonstração nenhuma no export.
  for (const nome of [
    'Demonstrações Contábeis 2025.pdf',
    'Demonstrações Financeiras 12M25.pdf',
    'DFs Grupo Vertentes 2025.pdf',
  ]) {
    assert.equal(classifyByFilename(nome).tipo_taxonomia, 'DF_AUDITADA', `tipo de ${nome}`);
  }
  // …e a fronteira: nome que diz QUAL demonstração é continua sendo dela — os
  // termos novos NÃO podem roubar esses casos. É o mesmo motivo pelo qual DMPL/DVA
  // vêm depois das principais.
  assert.equal(classifyByFilename('Demonstrações Combinadas 12M25.pdf').tipo_taxonomia, 'COMBINADO');
  assert.equal(classifyByFilename('Demonstração de Resultado 2025.pdf').tipo_taxonomia, 'DRE');
  assert.equal(classifyByFilename('Balanço Patrimonial 12M25.pdf').tipo_taxonomia, 'BALANCO');
  // Comportamento ANTERIOR a esta fatia, preservado de propósito: o PDF composto
  // que lista as demonstrações no nome ("Balanço Patrimonial DRE, DFC 2024.pdf",
  // arquivo real do dono) casa FLUXO_CAIXA pelo "dfc", porque FLUXO vem antes na
  // lista. Não mexo aqui: promovê-lo a DF_AUDITADA (complementar) tiraria dele a
  // capacidade de satisfazer os itens OBRIGATÓRIOS do Kit Básico e mudaria a
  // completude de todo caso já aberto — decisão de produto do dono, não efeito
  // colateral de uma fatia de export. E, de qualquer forma, o roteamento por
  // linha já separa as demonstrações desse arquivo aba por aba.
  assert.equal(classifyByFilename('Balanço Patrimonial DRE, DFC 2024.pdf').tipo_taxonomia, 'FLUXO_CAIXA');
});

test('classifyByFilename — casos reais do mandato de referência', () => {
  const casos = [
    ['Balancetes 1T2026 Empresa A.pdf', 'BALANCETE', '1T26'],
    ['12M24 Combinado Assinado.pdf', 'COMBINADO', '12M24'],
    ['Faturamento 36 meses.xlsx', 'FATURAMENTO_24M', 'L36M'],
    ['Balanço Patrimonial 12M25.pdf', 'BALANCO', '12M25'],
  ];
  for (const [nome, tipo, ref] of casos) {
    const r = classifyByFilename(nome);
    assert.equal(r.tipo_taxonomia, tipo, `tipo de ${nome}`);
    assert.equal(r.periodo?.referencia, ref, `periodo de ${nome}`);
  }
});

// --- Entidade a partir do nome do arquivo (correção do "teste v31") ----------
// No v31 o dashboard mostrou entidade "—" nos 14 documentos, INCLUSIVE nos 6 que
// extraíram sem erro. A causa era `entidade: null` fixo aqui: nos documentos que
// o nome classifica acima do limiar a IA de classificação nunca roda, então a
// única fonte de entidade era o diagnóstico da extração — e a extração dos outros
// 8 morreu no teto de gasto da OpenAI, levando a entidade junto.
//
// Os nomes são os 14 REAIS do teste (test-data/book-vertentes), não inventados.
test('parseEntidade resolve a empresa nos 14 arquivos do teste v31', () => {
  const casos = [
    ['01_BP_Vertentes_Metalurgica_2025x2024.pdf', 'Vertentes Metalurgica'],
    ['02_BP_Vertentes_Componentes_2025x2024.pdf', 'Vertentes Componentes'],
    ['03_BP_Vertentes_Participacoes_2025x2024.pdf', 'Vertentes Participacoes'],
    // sigla fica em caixa alta: "Vt Logistica" leria como erro de digitação
    ['04_BP_VT_Logistica_2025x2024.pdf', 'VT Logistica'],
    ['05_BP_Vertentes_Imoveis_SPE_2025x2024.pdf', 'Vertentes Imoveis SPE'],
    // 'COMBINADO' é termo de TIPO, não parte do nome da empresa
    ['06_BP_COMBINADO_Grupo_Vertentes_2025.pdf', 'Grupo Vertentes'],
    ['07_DRE_Vertentes_Metalurgica_2025x2024.pdf', 'Vertentes Metalurgica'],
    ['08_DFC_Vertentes_Metalurgica_2025.pdf', 'Vertentes Metalurgica'],
    ['09_DMPL_Vertentes_Metalurgica_2025.pdf', 'Vertentes Metalurgica'],
    ['10_Faturamento_24M_Vertentes_Metalurgica.pdf', 'Vertentes Metalurgica'],
    ['11_Mapa_Divida_Vertentes_Metalurgica_2025.pdf', 'Vertentes Metalurgica'],
    // 'Intragrupo' descreve o documento; sem removê-lo viria "Intragrupo Grupo Vertentes"
    ['12_Mutuos_Intragrupo_Grupo_Vertentes_2025.pdf', 'Grupo Vertentes'],
    // o nome só diz "Componentes" — devolver isso é honesto; o conteúdo refina
    ['13_Balancete_Analitico_Componentes_2025.pdf', 'Componentes'],
    ['14_Notas_Explicativas_Grupo_Vertentes_2025.pdf', 'Grupo Vertentes'],
  ];
  for (const [nome, entidade] of casos) {
    assert.equal(classifyByFilename(nome).entidade, entidade, `entidade de ${nome}`);
  }
});

// O invariante que protege a doutrina: a entidade é hipótese, e hipótese não
// compra dispensa da verificação da IA. Se alguém somar a entidade à confiança,
// os documentos de 0,65 sobem para 0,70+ e PARAM de ser conferidos pela IA —
// exatamente o tipo de subida de dial que docs/01 proíbe sem golden set.
test('entidade do nome NÃO altera confiança nem o limiar de fallback', () => {
  const esperado = [
    ['01_BP_Vertentes_Metalurgica_2025x2024.pdf', 0.9, false],
    ['06_BP_COMBINADO_Grupo_Vertentes_2025.pdf', 0.65, true],
    ['10_Faturamento_24M_Vertentes_Metalurgica.pdf', 0.6, true],
  ];
  for (const [nome, conf, fallback] of esperado) {
    const r = classifyByFilename(nome);
    assert.ok(r.entidade, `${nome} tem hipótese de entidade`);
    assert.equal(r.confianca, conf, `confiança de ${nome} intacta`);
    assert.equal(r.precisa_fallback_openai, fallback, `fallback de ${nome} intacto`);
  }
});

test('parseEntidade se abstém quando o nome não carrega empresa', () => {
  // Só tipo + período: não há o que extrair, e inventar seria pior que nada.
  assert.equal(classifyByFilename('Balanço Patrimonial 12M25.pdf').entidade, null);
  assert.equal(classifyByFilename('DRE_2025.pdf').entidade, null);
  // Resto de 2 letras não identifica empresa nenhuma — não vira entidade-lixo.
  assert.equal(classifyByFilename('DRE_XY_2025.pdf').entidade, null);
  // contrato de auto-contenção: `parseEntidade` recebe os aliases por parâmetro
  // (é assim que o `toString()` dela funciona dentro do Code node do n8n) e não
  // pode estourar quando eles não vêm.
  assert.equal(parseEntidade('bp vertentes metalurgica 2025', []), 'Bp Vertentes Metalurgica');
  assert.equal(parseEntidade('bp vertentes metalurgica 2025', undefined), 'Bp Vertentes Metalurgica');
});

// --- O achado do book-canastra: razão de fornecedores não é aging de pagáveis -
//
// O arquivo "17_Livro_Razao_Fornecedores_Canastra_Industria_12M25.pdf" saía como
// AGING_AP com confiança 0,90 — alta o bastante para PULAR a verificação da IA e
// mandar um livro contábil para a aba de contas a pagar. A causa era a ordem da
// lista de ALIASES: 'fornecedores', termo de uma palavra, vinha antes de
// 'livro razao'. O defeito só apareceu porque um book passou a ter razão E aging
// no mesmo lote — com um dos dois faltando, a ordem errada nunca é exercitada.
test('nome com duas palavras-chave resolve pela regra MAIS ESPECÍFICA', () => {
  const casos = [
    ['17_Livro_Razao_Fornecedores_Canastra_Industria_12M25.pdf', 'RAZAO'],
    ['Razao Analitico Clientes 2025.pdf', 'RAZAO'],
    // e o aging continua sendo aging — a correção não pode roubar o caso dele
    ['23_Aging_de_Contas_a_Pagar_Canastra_Industria_2025.pdf', 'AGING_AP'],
    ['Fornecedores em aberto 12M25.pdf', 'AGING_AP'],
    ['22_Aging_de_Contas_a_Receber_Canastra_Industria_2025.pdf', 'AGING_AR'],
  ];
  for (const [nome, tipo] of casos) {
    assert.equal(classifyByFilename(nome).tipo_taxonomia, tipo, `tipo de ${nome}`);
  }
});

// --- Os nomes do book-canastra e o que eles CUSTAM ---------------------------
//
// Metade dos nomes está na notação de f0/03 e metade chega como o cliente manda.
// Este teste trava a fronteira: quem resolve tipo E período forte fica em 0,90 e
// paga UMA chamada; quem traz ano solto fica em 0,65 e paga DUAS (classificação
// por conteúdo + extração). É a diferença que faz o lote caber ou não no teto —
// ver `n8n/medir-custo-book.mjs` e docs/CUSTO_OPENAI.md.
test('a notação do nome decide se o documento paga o PDF uma ou duas vezes', () => {
  const umaChamada = [
    '01_Balanco_Patrimonial_Canastra_Industria_2025x2024x2023.pdf',
    '03_DFC_Canastra_Industria_12M25.pdf',
    '04_DMPL_Canastra_Industria_2023_a_2025.pdf',
    '18_Faturamento_36_meses_Canastra_Industria_2023_a_2025.pdf',
    '35_Demonstracoes_Contabeis_Canastra_Industria_2024x2023.pdf',
  ];
  const duasChamadas = [
    '13_Balanco_COMBINADO_Grupo_Canastra_2025.pdf', // ano solto: sinal fraco
    '20_Mapa_de_Divida_Canastra_Industria_2025.pdf',
    '30_Certidoes_Negativas_Grupo_Canastra.pdf', // sem período nenhum
    'Doc1.pdf', // sem tipo nenhum
    'digitalizado_20260115_0003.pdf',
    'ANEXO IV - planilha final REV3.pdf',
  ];
  for (const nome of umaChamada) {
    const r = classifyByFilename(nome);
    assert.equal(r.precisa_fallback_openai, false, `${nome} deveria dispensar a IA (conf ${r.confianca})`);
    assert.ok(r.confianca >= 0.7, `${nome}: confiança ${r.confianca}`);
  }
  for (const nome of duasChamadas) {
    const r = classifyByFilename(nome);
    assert.equal(r.precisa_fallback_openai, true, `${nome} deveria cair na IA (conf ${r.confianca})`);
  }
});

// O nome de scanner não pode inventar período: "20260115" não é o ano de 2026, e
// "0003" não é 2003. Período-lixo fragmenta a tabela `periodo` e impede a
// reconciliação de casar os documentos do mesmo exercício.
test('nome de scanner e de anexo de e-mail não produzem período inventado', () => {
  for (const nome of ['digitalizado_20260115_0003.pdf', 'ANEXO IV - planilha final REV3.pdf', 'Doc1.pdf']) {
    const r = classifyByFilename(nome);
    assert.equal(r.periodo, null, `${nome} não pode ter período: ${JSON.stringify(r.periodo)}`);
    assert.equal(r.tipo_taxonomia, null, `${nome} não pode ter tipo`);
  }
});
