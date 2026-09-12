import { test } from 'node:test';
import assert from 'node:assert/strict';
import { detectarFormato, formaDoTexto } from '../lib/formato.mjs';

// --------------------------------------------------------------------------
// O CASO DA AMO, REPRODUZIDO — 60/60 documentos em 12/09/2026.
// --------------------------------------------------------------------------
//
// Planilha que estava dentro de um PDF, convertida para texto por quem subiu
// o arquivo: colunas alinhadas por ESPAÇO, com \x0C (form-feed) separando
// página — exatamente o que uma conversão de PDF para texto produz — e
// mimeType declarado `text/plain`, porque foi assim que o upload chegou.
const TEXTO_TABULAR_AMO = [
  'Balanço Patrimonial',
  '',
  'Caixa e equivalentes        1.234.567     987.654',
  'Contas a receber             456.789     321.098',
  'Estoques                     234.567     198.765',
  '\x0C',
  'Fornecedores                 345.678     287.654',
  'Empréstimos                  567.890     498.321',
  'Patrimônio líquido          1.987.654   1.654.321',
].join('\n');

test('AMO: texto tabular por espaço declarado text/plain vira formato texto, forma tabular-espaco, confiavel', () => {
  const buf = Buffer.from(TEXTO_TABULAR_AMO, 'latin1');
  const r = detectarFormato(buf, { mimeDeclarado: 'text/plain', nome: 'balanco.txt' });
  assert.equal(r.formato, 'texto');
  assert.notEqual(r.formato, 'xlsx');
  assert.equal(r.texto.forma, 'tabular-espaco');
  assert.equal(r.confiavel, true);
  // Nunca pode exigir nó nativo de planilha (Extrair XLSX/XLS) — é exatamente
  // o roteamento que rejeitou os 60 arquivos por mimeType inválido.
  assert.notEqual(r.formato, 'xls');
});

// --------------------------------------------------------------------------
// EXTENSÃO MENTIROSA NÃO ENGANA.
// --------------------------------------------------------------------------

test('bytes de PDF declarados text/plain: formato decide pela assinatura, não pelo mimetype', () => {
  const buf = Buffer.concat([Buffer.from('%PDF-1.7\n%âãÏÓ\n'), Buffer.from('resto do conteudo binario')]);
  const r = detectarFormato(buf, { mimeDeclarado: 'text/plain', nome: 'planilha.txt' });
  assert.equal(r.formato, 'pdf');
  assert.equal(r.evidencia, 'assinatura');
});

test('bytes de XLSX (zip + xl/) declarados text/plain: formato decide pela assinatura', () => {
  const buf = Buffer.concat([
    Buffer.from([0x50, 0x4b, 0x03, 0x04]),
    Buffer.from('algum preenchimento xl/workbook.xml resto do diretorio central'),
  ]);
  const r = detectarFormato(buf, { mimeDeclarado: 'text/plain', nome: 'demonstrativo.txt' });
  assert.equal(r.formato, 'xlsx');
  assert.equal(r.evidencia, 'assinatura');
});

// --------------------------------------------------------------------------
// ZIP QUE NÃO É PLANILHA NÃO VIRA PLANILHA.
// --------------------------------------------------------------------------

test('zip com entradas word/ nao vira xlsx — rotear docx ao extrator de planilha é o defeito irmao', () => {
  const buf = Buffer.concat([
    Buffer.from([0x50, 0x4b, 0x03, 0x04]),
    Buffer.from('word/document.xml resto do conteudo do pacote OOXML'),
  ]);
  const r = detectarFormato(buf, { mimeDeclarado: 'application/octet-stream' });
  assert.notEqual(r.formato, 'xlsx');
});

// --------------------------------------------------------------------------
// DELIMITADO DE VERDADE É DISTINGUIDO DE PROSA.
// --------------------------------------------------------------------------

test('CSV com ponto-e-virgula consistente: forma delimitado, separador correto', () => {
  const csv = [
    'conta;jan;fev;mar',
    'caixa;100;110;120',
    'receber;200;210;220',
    'estoques;50;55;60',
  ].join('\n');
  const r = formaDoTexto(csv);
  assert.equal(r.forma, 'delimitado');
  assert.equal(r.separador, ';');
});

test('contrato em prosa com virgulas em toda linha: NUNCA delimitado', () => {
  const contrato = [
    'O presente instrumento, doravante denominado Contrato, é celebrado entre as partes.',
    'A CONTRATANTE, pessoa jurídica de direito privado, e a CONTRATADA, sociedade limitada.',
    'As partes acordam, de comum acordo, os termos abaixo, sujeitos à legislação vigente.',
    'Fica eleito, para dirimir quaisquer controvérsias, o foro da comarca de São Paulo.',
  ].join('\n');
  const r = formaDoTexto(contrato);
  assert.notEqual(r.forma, 'delimitado');
  assert.equal(r.forma, 'corrido');
});

// --------------------------------------------------------------------------
// BINÁRIO SEM ASSINATURA CONHECIDA NÃO VIRA TEXTO.
// --------------------------------------------------------------------------

test('buffer com NUL nao vira formato texto mesmo sem assinatura conhecida', () => {
  // ATENÇÃO À FIXTURE: um NUL sozinho não basta para isolar esta checagem —
  // um buffer curto e majoritariamente de bytes de controle já reprova pelo
  // limiar de DENSIDADE (regra 4 do CLAUDE.md: fixture nasceu vazia na
  // primeira tentativa, com poucos bytes de controle "de sobra" — o mesmo
  // teste passava IGUAL com a checagem de NUL desligada, porque a densidade
  // sozinha já classificava como binário). Aqui o corpo é texto de verdade
  // — só o NUL, no meio de ~700 bytes de prosa normal, precisa decidir.
  const prosaAntes = 'Balanco patrimonial da empresa em 31 de dezembro. '.repeat(10);
  const prosaDepois = ' Ativos totais e passivos totais conferem com o razao.'.repeat(10);
  const buf = Buffer.concat([Buffer.from(prosaAntes, 'latin1'), Buffer.from([0x00]), Buffer.from(prosaDepois, 'latin1')]);
  const r = detectarFormato(buf, { mimeDeclarado: '' });
  assert.notEqual(r.formato, 'texto');
});

// --------------------------------------------------------------------------
// SUPOSIÇÃO É DECLARADA (regra 1 do CLAUDE.md aplicada ao detector).
// --------------------------------------------------------------------------

test('quando os bytes nao decidem, confiavel é false e evidencia é mime-declarado', () => {
  // Bytes sem assinatura conhecida E que não passam em pareceTexto (tem NUL) —
  // então cai direto no mimetype declarado.
  const buf = Buffer.from([0x01, 0x02, 0x00, 0x03, 0x04, 0x00, 0x05]);
  const r = detectarFormato(buf, { mimeDeclarado: 'application/pdf' });
  assert.equal(r.confiavel, false);
  assert.equal(r.evidencia, 'mime-declarado');
  assert.equal(r.formato, 'pdf');
});

// --------------------------------------------------------------------------
// formaDoTexto COM TEXTO VAZIO NÃO ESTOURA.
// --------------------------------------------------------------------------

test('formaDoTexto de texto vazio devolve forma vazio, sem lançar', () => {
  assert.deepEqual(formaDoTexto(''), { forma: 'vazio', separador: null, colunas: 0 });
  assert.deepEqual(formaDoTexto('   \n  \n'), { forma: 'vazio', separador: null, colunas: 0 });
  assert.deepEqual(formaDoTexto(null), { forma: 'vazio', separador: null, colunas: 0 });
});
