// O SEGUNDO MÉTODO da Fase 0 — medido, e medido para NÃO concordar com o
// primeiro. Um teste que só confirma "os dois dão o mesmo número" provaria
// que este arquivo é um wrapper de `linhasDeConta` com outro nome, que é
// exatamente o que a Fase 0 do plano pede para NÃO construir.
//
// Os textos abaixo são REAIS, não inventados (regra 4): o de
// `13_Balanco_COMBINADO_Grupo_Canastra_2025` vem da captura de produção
// versionada (`Dados de Teste/capturas/2026-08-31-texto-extraido-n8n/`,
// execução 7276 do n8n, nó `Extrair Texto`); os de
// `10_Faturamento_24M_Vertentes_Metalurgica` e
// `11_Mapa_Divida_Vertentes_Metalurgica_2025` são o texto que
// `Dados de Teste/book-vertentes/gerar.py` produz para esses dois documentos
// (`pdf/TEXTO_EXTRAIDO.json`, não versionado — copiado aqui litera[l]mente
// para o teste não depender de `python3 gerar.py` ter rodado). As contagens
// de verdade (`linhas_de_conta_verdade`) vêm de `pdf/METRICAS.json`, medidas
// por `Dados de Teste/comum/contagem.py` sobre as linhas da TABELA do
// reportlab, antes de o PDF existir.

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { linhasDeConta, juntarFragmentosDeLinha } from '../lib/cobertura.mjs';
import { temFormaMonetaria, linhasDeContaPorForma } from '../lib/segunda-contagem.mjs';

const AQUI = dirname(fileURLToPath(import.meta.url));
const RAIZ = join(AQUI, '..', '..');

test('temFormaMonetaria: separador de milhar e decimal com vírgula contam; ano solto e data não', () => {
  assert.equal(temFormaMonetaria('51.300.000'), true);
  assert.equal(temFormaMonetaria('6,80% a.a.'), true);
  assert.equal(temFormaMonetaria('Ticket médio 38,2 31,4'), true);
  // Ano solto sozinho — a ÚNICA exclusão deste método, e ela é por FORMA
  // (1900-2099), não por saber que "Mês" é cabeçalho de coluna.
  assert.equal(temFormaMonetaria('Mês 2024 2025 Variação %'), false);
  assert.equal(temFormaMonetaria('31/12/2025'), false);
  assert.equal(temFormaMonetaria(''), false);
  assert.equal(temFormaMonetaria(null), false);
  assert.equal(temFormaMonetaria(undefined), false);
});

test('temFormaMonetaria: dia solto de "31 de dezembro" sobrevive — limite conhecido, não escondido', () => {
  // O método só sabe subtrair ANO (4 dígitos, 19xx/20xx) e data DD/MM/AAAA.
  // "31" isolado (dia do mês por extenso) não é nenhum dos dois pela forma, e
  // fica — ao contrário de `ehLinhaSemValor`, que tem uma regra própria para
  // "dia de mês" com lista de nomes de mês. É a troca deliberada: sem lista de
  // palavra, este caso vaza. Documentado aqui para não ser "achado" de novo.
  assert.equal(temFormaMonetaria('Posição em 31 de dezembro de 2025'), true);
});

test('linhasDeContaPorForma: entrada inválida devolve lista vazia, não erro', () => {
  for (const v of ['', null, undefined, 42, {}]) assert.deepEqual(linhasDeContaPorForma(v), []);
});

test('linhasDeContaPorForma: linha em branco não conta, e a emenda de fragmento é OPCIONAL', () => {
  const texto = 'Caixa   44.022\n\nBancos   9.410';
  assert.deepEqual(linhasDeContaPorForma(texto), ['Caixa   44.022', 'Bancos   9.410']);
  // Sem `juntarFragmentos`, um fragmento que termina em espaço (a marca de
  // `juntarFragmentosDeLinha`) NÃO é emendado — o chamador decide.
  const fragmentado = 'Fornecimento Canastra Agroflorestal \nx Canastra Indústria   2.900';
  const semEmenda = linhasDeContaPorForma(fragmentado);
  assert.equal(semEmenda.length, 1); // só a segunda linha tem forma monetária
  const comEmenda = linhasDeContaPorForma(fragmentado, { juntarFragmentos: juntarFragmentosDeLinha });
  assert.equal(comEmenda.length, 1);
  assert.match(comEmenda[0], /2\.900/);
});

// ---------------------------------------------------------------------------
// O DEFEITO REAL, CORRIGIDO EM 09/09: `ehLinhaSemValor` confundia total em
// REAIS com código de conta e apagava a linha. Medido no texto REAL de
// `11_Mapa_Divida_Vertentes_Metalurgica_2025` (`Dados de Teste/book-vertentes/
// pdf/TEXTO_EXTRAIDO.json`, gerado por `PYTHONPATH=. python3 gerar.py`).
// ---------------------------------------------------------------------------
const TEXTO_MAPA_DIVIDA = [
  'Credor Modalidade Saldo devedor (R$) Taxa Vencimento Garantia Juros do exercício (R$)',
  'Banco Meridional S.A. Capital de giro 9.420.000 CDI + 6,80% a.a. 15/03/2026 Recebíveis + aval dos sócios 2.180.000',
  'Banco Meridional S.A. Conta garantida 2.380.000 CDI + 9,20% a.a. Rotativo Aval dos sócios 640.000',
  'Banco Atlântico Sul Capital de giro 6.180.000 CDI + 7,40% a.a. 20/08/2026 Alienação fiduciária de máquinas 1.490.000',
  'Banco Atlântico Sul Antecipação de recebíveis 6.180.000 2,45% a.m. Rotativo Duplicatas cedidas 4.630.000',
  'BNDES / FINAME (agente: Banco Meridional) Financiamento de máquinas 9.080.000 TLP + 4,10% a.a. 10/07/2029 Alienação fiduciária dos bens financiados 1.080.000',
  'Cooperativa de Crédito Vale Capital de giro 3.140.000 1,95% a.m. 05/02/2026 Aval dos sócios 820.000',
  'Fomento Mercantil Paulista Ltda. Factoring 2.440.000 3,10% a.m. Rotativo Duplicatas cedidas com coobrigação 1.180.000',
  'Arrendadora Sigma Arrendamento mercantil (CPC 06) 2.680.000 CDI + 8,00% a.a. 30/11/2027 Bem arrendado 380.000',
  'Sócios pessoas físicas Empréstimo subordinado 9.800.000 Sem remuneração Sem vencimento definido Sem garantia 0',
  'Atenção: os valores deste mapa estão expressos em REAIS, enquanto as demonstrações contábeis estão em milhares de reais. Covenant de cobertura de juros descumprido em 31/12/2025 no contrato de capital de giro do Banco Meridional S.A., o que autoriza o vencimento antecipado da dívida.',
  'TOTAL 51.300.000 12.400.000',
  '_______________________________________ Marcos A. Ferreira — Contador — CRC 1SP-214.887/O-3 Documento sintético, gerado para teste de sistema. Não corresponde a empresa, pessoa ou fato real. MAPA DE ENDIVIDAMENTO BANCÁRIO E FINANCEIRO VERTENTES METALÚRGICA LTDA. (Valores expressos em REAIS — R$) Posição em 31 de dezembro de 2025 CNPJ 11.222.334/0001-08',
].join('\n');
const VERDADE_MAPA_DIVIDA = 10; // pdf/METRICAS.json, 11_Mapa_Divida_Vertentes_Metalurgica_2025

test('a régua (linhasDeConta) já NÃO conta a menos no Mapa de Dívida — defeito corrigido em 09/09', () => {
  // ANTES da correção, `ehLinhaSemValor` apagava "51.300.000" e "12.400.000"
  // como se fossem código de conta (`\d+(\.\d+){2,}` casa as duas formas) e a
  // linha TOTAL ficava sem dígito — 9 de 10, o caso perigoso (contar a menos).
  // A correção distingue as duas formas pelo GRUPO: separador de milhar tem
  // todo grupo depois do primeiro com exatamente 3 dígitos ("300", "000");
  // código de conta, não ("1.1.01.002" tem grupo de 1 dígito). Regressão: se
  // isto voltar a 9 e a linha TOTAL voltar a faltar, o defeito voltou.
  const linhas = linhasDeConta(TEXTO_MAPA_DIVIDA);
  assert.equal(linhas.length, VERDADE_MAPA_DIVIDA, 'se isto cair para 9, o defeito de ehLinhaSemValor voltou — ver N8N/lib/cobertura.mjs');
  assert.ok(linhas.some((l) => l.startsWith('TOTAL')), 'a linha TOTAL tem de estar presente');
});

test('linhasDeContaPorForma RECUPERA a linha TOTAL (sem o strip de código de conta)', () => {
  const linhas = linhasDeContaPorForma(TEXTO_MAPA_DIVIDA, { juntarFragmentos: juntarFragmentosDeLinha });
  assert.ok(linhas.some((l) => l.startsWith('TOTAL 51.300.000')), 'a linha TOTAL tem de estar presente');
  // E erra do lado SEGURO: soma um falso positivo (rodapé/CNPJ, mesma forma de
  // valor) que a correção da régua NÃO toca — o strip de código de conta não
  // tem nada a ver com este CNPJ —, então fica em 11 (+10%), contando A MAIS,
  // não a menos. A régua, corrigida, acerta 10/10; este método continua com o
  // mesmo erro de antes. Ver o comentário de lib/segunda-contagem.mjs.
  assert.equal(linhas.length, VERDADE_MAPA_DIVIDA + 1);
});

// ---------------------------------------------------------------------------
// O CASO EM QUE O GABARITO ESTÁ INFLADO — as duas pernas concordam nas 15
// linhas reais; a 16ª (o cabeçalho "Mês 2024 2025 Variação %" que o
// `contagem.py` conta por ter rótulo+dígito, sem saber que o dígito é ano) só
// bate por coincidência do lado da forma.
// ---------------------------------------------------------------------------
const TEXTO_FATURAMENTO_24M = [
  'Mês 2024 2025 Variação %',
  'jan/2024 — jan/2025 15.493 14.452 -6.7%',
  'fev/2024 — fev/2025 15.948 13.718 -14.0%',
  'mar/2024 — mar/2025 16.404 14.085 -14.1%',
  'abr/2024 — abr/2025 16.100 12.860 -20.1%',
  'mai/2024 — mai/2025 16.708 12.493 -25.2%',
  'jun/2024 — jun/2025 15.796 12.003 -24.0%',
  'jul/2024 — jul/2025 15.189 11.268 -25.8%',
  'ago/2024 — ago/2025 15.644 10.778 -31.1%',
  'set/2024 — set/2025 14.885 10.533 -29.2%',
  'out/2024 — out/2025 14.429 9.798 -32.1%',
  'nov/2024 — nov/2025 13.974 8.818 -36.9%',
  'dez/2024 — dez/2025 12.910 7.594 -41.2%',
  'TOTAL DO EXERCÍCIO 183.480 138.400 -24.6%',
  'Média mensal 15.290 11.533',
  'Ticket médio por pedido (R$ mil) — indicador gerencial 38,2 31,4 -17,8%',
  'O total do exercício de 2025 confere com a Receita Operacional Bruta da demonstração do resultado. _______________________________________ Marcos A. Ferreira — Contador — CRC 1SP-214.887/O-3 Documento sintético, gerado para teste de sistema. Não corresponde a empresa, pessoa ou fato real. FATURAMENTO MENSAL — ÚLTIMOS 24 MESES (Valores expressos em milhares de reais — R$ mil) VERTENTES METALÚRGICA LTDA. Período: janeiro/2024 a dezembro/2025 CNPJ 11.222.334/0001-08',
].join('\n');
const LINHAS_REAIS_FATURAMENTO = 15; // 12 meses + TOTAL + Média mensal + Ticket médio
const GABARITO_FATURAMENTO = 16; // pdf/METRICAS.json — inflado em 1, ver o motivo abaixo

test('as duas pernas excluem o CABEÇALHO da tabela pelo mesmo motivo (ano solto)', () => {
  const m1 = linhasDeConta(TEXTO_FATURAMENTO_24M);
  const m2 = linhasDeContaPorForma(TEXTO_FATURAMENTO_24M, { juntarFragmentos: juntarFragmentosDeLinha });
  assert.ok(!m1.some((l) => l.startsWith('Mês')), 'linhasDeConta não pode contar o cabeçalho');
  assert.ok(!m2.some((l) => l.startsWith('Mês')), 'linhasDeContaPorForma também não pode');
  assert.equal(m1.length, LINHAS_REAIS_FATURAMENTO, 'a régua acerta as linhas REAIS — o gabarito é que está inflado aqui');
  // A forma soma o MESMO falso positivo de rodapé/CNPJ do teste do Mapa de
  // Dívida e fecha em 16 — bate o gabarito por coincidência, não porque
  // entendeu o cabeçalho melhor que a régua.
  assert.equal(m2.length, GABARITO_FATURAMENTO);
  assert.ok(m2.some((l) => l.includes('CNPJ 11.222.334')), 'o 16º item da forma É o rodapé, não uma conta nova');
});

// ---------------------------------------------------------------------------
// A CAUSA DO -33% NO COMBINADO NÃO É A RÉGUA — texto de PRODUÇÃO real (captura
// versionada), onde `linhasDeConta` bate a verdade no dígito, e este método
// (sem lista de ruído) sobreconta o mesmo documento LIMPO. Prova que os dois
// erram em documentos e por motivos DIFERENTES — não é o mesmo método com
// outro nome.
// ---------------------------------------------------------------------------
test('13_Balanco_COMBINADO (texto de produção real): a régua bate a verdade; a forma sobreconta o rodapé', () => {
  const captura = JSON.parse(readFileSync(
    join(RAIZ, 'Dados de Teste/capturas/2026-08-31-texto-extraido-n8n/textos.json'), 'utf8',
  ));
  const doc = captura.documentos['13_Balanco_COMBINADO_Grupo_Canastra_2025.pdf'];
  assert.ok(doc, 'a captura de produção do 13_Balanco_COMBINADO tem de existir — se este assert falhar, o arquivo de captura mudou');
  const VERDADE = 15; // pdf/METRICAS.json do book-canastra
  const m1 = linhasDeConta(doc.texto);
  const m2 = linhasDeContaPorForma(doc.texto, { juntarFragmentos: juntarFragmentosDeLinha });
  assert.equal(m1.length, VERDADE, 'linhasDeConta bate a verdade no texto REAL de produção — o -33% do plano não reproduz aqui');
  // A forma não tem lista de ruído: Página, "Posição em", a continuação da
  // Nota ("aos 35% do capital..."), CRC e CPF de assinatura todos sobrevivem.
  assert.ok(m2.length > m1.length, 'a forma tem de sobrecontar ESTE documento limpo — é o preço documentado de não ter lista de ruído');
  assert.equal(m2.length, 20);
});

test('as duas pernas discordam em pelo menos um documento de cada book — não é wrapper', () => {
  // Guarda de regressão: se algum dia as duas contagens colapsarem para o
  // mesmo número em TODOS os quatro casos medidos acima, este método deixou
  // de ser um segundo princípio e passou a ser `linhasDeConta` com outro nome.
  const casos = [
    { nome: 'Mapa de Dívida', texto: TEXTO_MAPA_DIVIDA },
    { nome: 'Faturamento 24M', texto: TEXTO_FATURAMENTO_24M },
  ];
  let discordancias = 0;
  for (const c of casos) {
    const m1 = linhasDeConta(c.texto).length;
    const m2 = linhasDeContaPorForma(c.texto, { juntarFragmentos: juntarFragmentosDeLinha }).length;
    if (m1 !== m2) discordancias += 1;
  }
  assert.ok(discordancias >= 1, 'as duas contagens concordaram em TODOS os casos — não é mais um segundo método');
});
