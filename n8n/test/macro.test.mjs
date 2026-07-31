import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
  SERIES_MACRO, INDICADORES_FOCUS, serieMacro, urlSgs, urlFocus, urlSidraIpca,
  parseSgs, parseFocus, parseSidraIpca, numeroMacro,
  divergenciasEntreFontes, acumularTaxas, retornoAnual, mediaAnualGeometrica,
} from '../lib/macro.mjs';

// Respostas REAIS das três APIs (capturadas em 2026-07-28), reduzidas. Fixture
// de resposta real e não inventada: o formato do SGS (data dd/MM/yyyy e valor
// como STRING) e o cabeçalho descritivo na primeira linha do SIDRA são
// exatamente o tipo de detalhe que um mock caprichado esconde.
const SGS_IPCA = [
  { data: '01/01/2026', valor: '0.33' },
  { data: '01/02/2026', valor: '0.70' },
  { data: '01/03/2026', valor: '0.42' },
];
const SIDRA_IPCA = [
  { NC: 'Nível Territorial (Código)', V: 'Valor', D3C: 'Mês (Código)' }, // cabeçalho
  { NC: '1', MN: '%', V: '0.33', D2C: '63', D3C: '202601', D3N: 'janeiro 2026' },
  { NC: '1', MN: '%', V: '0.70', D2C: '63', D3C: '202602', D3N: 'fevereiro 2026' },
];
const FOCUS_IPCA = {
  value: [
    { Indicador: 'IPCA', Data: '2026-07-24', DataReferencia: '2026', Media: 5.13, Mediana: 5.1209, numeroRespondentes: 151 },
    { Indicador: 'IPCA', Data: '2026-07-24', DataReferencia: '2027', Media: 4.51, Mediana: 4.5, numeroRespondentes: 148 },
    { Indicador: 'IPCA', Data: '2026-07-24', DataReferencia: '2027', Media: 9.99, Mediana: 9.99, numeroRespondentes: 1 },
    // coleta ANTERIOR: não pode se misturar com a mais recente
    { Indicador: 'IPCA', Data: '2026-07-17', DataReferencia: '2026', Media: 5.30, Mediana: 5.28, numeroRespondentes: 149 },
  ],
};

test('catálogo de séries: taxa e nível são distinguidos (agregam de formas diferentes)', () => {
  assert.equal(serieMacro('IPCA').sgs, 433);
  assert.equal(serieMacro('IPCA').natureza, 'taxa');
  // Câmbio é NÍVEL: compor variações mensais de um preço é erro conceitual.
  assert.equal(serieMacro('CAMBIO_USD').natureza, 'nivel');
  assert.equal(serieMacro('INEXISTENTE'), null);
  for (const s of SERIES_MACRO) {
    assert.ok(s.codigo && s.nome && s.sgs && ['taxa', 'nivel'].includes(s.natureza), `série incompleta: ${s.codigo}`);
  }
  assert.ok(INDICADORES_FOCUS.every((i) => i.codigo && i.indicador));
  // O câmbio tem de ser a série MENSAL de fechamento (3698), não a PTAX diária
  // (1): a diária estoura a janela de 11 anos no SGS (HTTP 406, medido) e, se
  // passasse, misturaria ~2.800 observações diárias com séries mensais — aí
  // "fechamento do ano" passaria a depender do último dia útil coletado.
  assert.equal(serieMacro('CAMBIO_USD').sgs, 3698, 'câmbio: série mensal de fim de período');
  assert.equal(serieMacro('CAMBIO_USD').natureza, 'nivel');
});

test('URLs das três fontes', () => {
  // O SGS responde HTTP 400 para `ultimos/N` com N acima de ~20 (medido em
  // 2026-07-29 nas séries 433, 4390, 1 e 189: 20 → 200, 22 → 400) — e a coleta
  // pede 132 meses. Com a forma antiga, TODAS as séries falhavam, e o sintoma era
  // a aba Macro vazia, indistinguível de "workflow não ativado". A janela por
  // DATA devolve os 11 anos sem reclamar; este teste impede a volta do `ultimos`.
  const u = urlSgs(433, { mesesAtras: 132, hoje: new Date('2026-07-29T00:00:00Z') });
  assert.match(u, /bcdata\.sgs\.433\/dados\?formato=json&dataInicial=01%2F08%2F2015$/);
  assert.ok(!u.includes('/ultimos/'), 'a forma `ultimos/N` é recusada pelo SGS na janela que usamos');
  // `dataFinal` fica de fora: a URL não pode envelhecer nem depender do relógio
  // de quem chama — sem ela o SGS devolve até a última observação publicada.
  assert.ok(!u.includes('dataFinal'), 'sem dataFinal: a série vem até a última publicação');
  // Janela curta continua correta (o mês inicial anda com a janela).
  assert.match(
    urlSgs(4390, { mesesAtras: 12, hoje: new Date('2026-07-29T00:00:00Z') }),
    /dataInicial=01%2F08%2F2025$/,
  );
  const f = urlFocus('IPCA');
  assert.match(f, /ExpectativasMercadoAnuais/);
  assert.match(f, /Indicador%20eq%20'IPCA'/); // filtro precisa ir codificado
  assert.match(f, /orderby=Data%20desc/); // sem isso vem a coleta mais ANTIGA
  assert.match(urlSidraIpca({ ultimos: 6 }), /t\/1737\/n1\/all\/v\/63\/p\/last%206$/);
});

// --- Focus: qual das DUAS medianas -------------------------------------------
// O Olinda devolve, para o mesmo (indicador, ano, coleta), duas linhas: base 30
// dias (`baseCalculo=0`) e base 5 dias úteis (`=1`), com medianas diferentes. O
// dedup de `parseFocus` ficava com "a que o servidor devolvesse primeiro" — a
// premissa de inflação do modelo dependia da ordem de uma resposta HTTP. Não é
// erro grande em magnitude; é irreprodutível, e numa entrega auditável isso é
// pior do que estar um pouco diferente.
test('a URL do Focus fixa a base de cálculo, e o parse não aceita a outra', () => {
  assert.match(urlFocus('IPCA'), /baseCalculo%20eq%200/);

  // Resposta com AS DUAS bases para o mesmo ano — o que a API devolve de fato.
  const resposta = { value: [
    { Indicador: 'IPCA', Data: '2026-07-24', DataReferencia: '2027', Mediana: '9,99', baseCalculo: 1 },
    { Indicador: 'IPCA', Data: '2026-07-24', DataReferencia: '2027', Mediana: '4,50', baseCalculo: 0 },
  ] };
  const exp = parseFocus(resposta, 'IPCA');
  assert.equal(exp.length, 1, 'um registro por ano de referência');
  assert.equal(exp[0].mediana, 4.5, 'vale a base de 30 dias, não a que vier primeiro');

  // A ORDEM INVERSA tem de dar o mesmo resultado — é justamente o que não
  // acontecia. Sem esta metade o teste passaria com o bug ligado (a linha certa
  // já vinha em segundo lugar acima, mas um dedup por "primeiro que chega" com
  // a ordem trocada devolveria 9,99).
  const invertida = { value: [resposta.value[1], resposta.value[0]] };
  assert.equal(parseFocus(invertida, 'IPCA')[0].mediana, 4.5, 'a ordem da resposta não decide');

  // Resposta SEM o campo (seed antigo, chamada à mão) continua valendo: filtrar
  // o que não se sabe esvaziaria a série em silêncio, que é o defeito da fatia 1.
  const semCampo = { value: [
    { Indicador: 'IPCA', Data: '2026-07-24', DataReferencia: '2027', Mediana: '4,50' },
  ] };
  assert.equal(parseFocus(semCampo, 'IPCA').length, 1, 'ausência do campo não descarta a linha');
});

test('numeroMacro aceita ponto e vírgula decimal, recusa lixo', () => {
  assert.equal(numeroMacro('0.67'), 0.67);
  assert.equal(numeroMacro('1.234,56'), 1234.56);
  assert.equal(numeroMacro(4.2), 4.2);
  assert.equal(numeroMacro(''), null);
  assert.equal(numeroMacro('n/d'), null);
  assert.equal(numeroMacro(null), null);
});

test('parseSgs normaliza data e valor; observação sem data é descartada', () => {
  const r = parseSgs(SGS_IPCA, 'IPCA');
  assert.equal(r.length, 3);
  assert.deepEqual(r[0], { serie: 'IPCA', fonte: 'BCB/SGS', data_ref: '2026-01-01', valor: 0.33 });
  // Uma data ilegível não pode virar uma observação sem data (entraria no ano errado).
  assert.equal(parseSgs([{ data: 'jan/26', valor: '1' }], 'IPCA').length, 0);
  assert.deepEqual(parseSgs(null, 'IPCA'), []);
});

test('parseSidraIpca pula o cabeçalho descritivo e converte o período AAAAMM', () => {
  const r = parseSidraIpca(SIDRA_IPCA);
  assert.equal(r.length, 2);
  assert.deepEqual(r[0], { serie: 'IPCA', fonte: 'IBGE/SIDRA', data_ref: '2026-01-01', valor: 0.33 });
});

test('parseFocus fica só na coleta MAIS RECENTE e num registro por ano', () => {
  const r = parseFocus(FOCUS_IPCA, 'IPCA');
  assert.equal(r.length, 2, 'dois anos de referência na coleta mais recente');
  assert.equal(r[0].ano_ref, 2026);
  assert.equal(r[0].mediana, 5.1209);
  assert.equal(r[0].coletado_em, '2026-07-24');
  // A coleta de 17/07 (mediana 5.28) NÃO pode contaminar o mesmo ano.
  assert.notEqual(r[0].mediana, 5.28);
  // Nem o segundo registro de 2027 (1 respondente) pode substituir o primeiro.
  assert.equal(r[1].ano_ref, 2027);
  assert.equal(r[1].mediana, 4.5);
  assert.deepEqual(parseFocus({ value: [] }, 'IPCA'), []);
});

test('VALIDAÇÃO CRUZADA: BCB e IBGE têm de dar o mesmo IPCA', () => {
  const bcb = parseSgs(SGS_IPCA, 'IPCA');
  const ibge = parseSidraIpca(SIDRA_IPCA);
  // Dado real das duas fontes: bate.
  assert.deepEqual(divergenciasEntreFontes(bcb, ibge), []);
  // Mês presente em só uma das fontes não é divergência — é cobertura diferente
  // (o BCB publica antes). Tratar como divergência geraria alerta toda semana.
  assert.equal(bcb.length, 3);
  assert.equal(ibge.length, 2);

  // …e uma divergência REAL é pega.
  const adulterado = ibge.map((o) => (o.data_ref === '2026-01-01' ? { ...o, valor: 0.51 } : o));
  const fora = divergenciasEntreFontes(bcb, adulterado);
  assert.equal(fora.length, 1);
  assert.equal(fora[0].data_ref, '2026-01-01');
  assert.ok(Math.abs(fora[0].delta - 0.18) < 1e-9);

  // Arredondamento de publicação (0,01 p.p.) não pode virar alerta.
  const arredondado = ibge.map((o) => ({ ...o, valor: o.valor + 0.01 }));
  assert.deepEqual(divergenciasEntreFontes(bcb, arredondado), []);
});

test('acumularTaxas compõe (não soma)', () => {
  // 0,5% e 0,3% → 1,005 × 1,003 = 1,008015 → 0,8015%, não 0,8%.
  assert.ok(Math.abs(acumularTaxas([0.5, 0.3]) - 0.8015) < 1e-9);
  assert.equal(acumularTaxas([]), 0);
  // 12 meses de 1% dão 12,6825%, não 12%.
  assert.ok(Math.abs(acumularTaxas(Array(12).fill(1)) - 12.682503013196977) < 1e-9);
});

test('retornoAnual acumula por ano-calendário e marca o ano incompleto', () => {
  const obs = [
    ...Array.from({ length: 12 }, (_, i) => ({ data_ref: `2024-${String(i + 1).padStart(2, '0')}-01`, valor: 1 })),
    { data_ref: '2025-01-01', valor: 2 },
  ];
  const r = retornoAnual(obs);
  assert.equal(r.length, 2);
  assert.equal(r[0].ano, 2024);
  assert.equal(r[0].meses, 12);
  assert.ok(Math.abs(r[0].retorno - 12.682503013196977) < 1e-9);
  assert.equal(r[1].meses, 1, 'ano corrente fica marcado como incompleto');
});

test('mediaAnualGeometrica: geométrica, só anos cheios, e nunca inventa', () => {
  const anos = (retornos) => retornos.map((v, i) => ({ ano: 2016 + i, meses: 12, retorno: v }));
  // √(1,10 × 1,04) − 1 = 6,9579%, NÃO os 7,00% da média aritmética. É o erro
  // que este teste existe para impedir: parece detalhe e vira erro material num
  // horizonte de 10 anos.
  const g = mediaAnualGeometrica(anos([10, 4]), 2);
  assert.ok(Math.abs(g - 6.95794) < 1e-4, `geométrica=${g}`);
  assert.notEqual(Math.round(g * 100) / 100, 7);

  // Histórico insuficiente devolve null (não completa com o que tem).
  assert.equal(mediaAnualGeometrica(anos([10, 4]), 3), null);

  // Ano incompleto é EXCLUÍDO: entrando como se fosse cheio, puxaria a média.
  const comParcial = [...anos([10, 4, 6]), { ano: 2019, meses: 4, retorno: 1.2 }];
  assert.equal(mediaAnualGeometrica(comParcial, 3), mediaAnualGeometrica(anos([10, 4, 6]), 3));

  // Deflação entra normalmente (fator < 1) — a fórmula não pode quebrar.
  assert.ok(mediaAnualGeometrica(anos([-2, 3]), 2) < 1);
});
