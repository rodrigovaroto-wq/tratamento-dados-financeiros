// O SEGUNDO MÉTODO da Fase 0 do plano — independente de `linhasDeConta`.
//
// A FASE 0 (`Arquitetura do Sistema/3 Estado e Execução/PLANO_LINHA_A_LINHA.md`)
// pede uma contagem de linhas de conta por um método que não seja outra leitura
// da MESMA regra: "conferir heurística contra heurística não prova nada". Este
// arquivo é essa segunda régua. Ela NÃO é usada pelos geradores nem pelos nós
// Code do workflow — existe só para MEDIR `linhasDeConta` (`lib/cobertura.mjs`)
// contra o gabarito, lado a lado. Ver `N8N/medir-fase0-denominador.mjs`.
//
// O PRINCÍPIO É OUTRO, de propósito. `linhasDeConta` pergunta, por linha:
// "tem valor E tem identidade (rótulo, código de conta, ou linha de tabela
// numérica), descontado o RUÍDO LÉXICO conhecido deste tipo de documento —
// CNPJ, CRC, mês por extenso, duração, Página, Nota, assinatura." É uma lista
// de exclusões que cresce a cada documento novo que a engana.
//
// Este método não pergunta o que a linha DIZ. Pergunta só se algum número dela
// TEM A FORMA de um valor monetário brasileiro — sem olhar identidade, sem
// lista de palavras. A forma: separador de milhar em grupos de EXATAMENTE três
// dígitos ("51.300.000"), ou parte decimal com vírgula ("38,2" / "6,80%"). A
// única coisa que ele sabe subtrair — não por lista de palavra, mas por FORMA
// do próprio número — é ano solto (1900-2099) e data DD/MM/AAAA, porque um ano
// ou uma data são a única forma numérica que aparece em toda linha de cabeçalho
// de tabela sem nunca ser valor.
//
// A CAUSA MEDIDA DO SUBCOUNT NO COMBINADO — e por que ela NÃO está aqui.
// O pedido citava `13`/`14_Balanco_COMBINADO`, `21_Mutuos` e
// `25_Situacao_Fiscal` do canastra contando a menos (-33%/-33%/-30%). Medido
// (09/09): contra o TEXTO DE PRODUÇÃO capturado (`Dados de
// Teste/capturas/2026-08-31-texto-extraido-n8n/`), `13_Balanco_COMBINADO` e
// `14_Balanco_COMBINADO` batem a verdade NO DÍGITO (15 de 15, erro 0%) — a
// régua `linhasDeConta` está CERTA. O -33% só aparece quando o texto vem do
// REPLICADOR LOCAL de extração do book (`Dados de Teste/comum/extrai.py`,
// função `linhas()`): ela agrupa pedaços de texto pela coordenada Y com
// tolerância de 2pt, e nos documentos com DUAS tabelas na mesma página (o
// balanço principal e o painel "Eliminações do combinado") duas linhas de
// tabelas DIFERENTES caem dentro da tolerância e saem MESCLADAS numa
// única linha ilegível — ex. `"Eliminações do combinado Ativo Não Circulante
// 42.034 93.602 1.427 Valor 3.167 25.975 29.422 (42.034) 153.593"`, que funde
// o cabeçalho de uma tabela com uma linha de dados da outra. `linhasDeConta`
// (corretamente) não reconhece a mistura como conta; nenhum método de contagem
// que opere sobre o texto já mesclado recupera o dado — ele já não existe como
// texto de linha. `21_Mutuos` e `25_Situacao_Fiscal` não têm captura de
// produção (só os 20 primeiros documentos do canastra foram capturados em
// 31/08); a mesma assinatura de mescla aparece no texto que os gera
// (confirmado por inspeção), então o -33%/-30% é, com alta probabilidade, o
// MESMO artefato do replicador — não um fato medido contra produção. Regra 4:
// dito como hipótese, não como fato.
//
// O DEFEITO REAL QUE A INVESTIGAÇÃO ACHOU — esse SIM é da régua. Em
// `11_Mapa_Divida_Vertentes_Metalurgica_2025` (valores em REAIS, não em
// milhares), a linha `"TOTAL 51.300.000 12.400.000"` é descartada por
// `ehLinhaSemValor`: o strip de CÓDIGO DE CONTA (`\b\d+(?:\.\d+){2,}\b`,
// pensado para `1.1.01.002`) também casa com um valor de R$ 51,3 milhões
// escrito com separador de milhar em três grupos, apaga os dois números da
// linha e a deixa sem dígito — "sem valor". Medido: verdade 10, régua 9 (-10%).
// Este método NÃO tem esse strip — ele recupera a linha do TOTAL — mas soma,
// no MESMO documento, um falso positivo que a régua não tinha: o rodapé de
// assinatura funde num só parágrafo (mesma causa de coordenada Y de acima) e
// carrega um CNPJ ("11.222.334/0001-08", forma \d{1,3}(\.\d{3})+) que TEM a
// forma de valor e não é. Medido: este método dá 11 (+10%) — mais longe do
// zero que a régua em módulo igual, mas do lado SEGURO (conta a mais, não a
// menos). Reconhecer o CNPJ sem lista de ruído voltaria a exigir léxico — e
// deixaria de ser um segundo princípio.
//
// E UM CASO EM QUE O GABARITO, NÃO A RÉGUA, ESTÁ ERRADO — só que os dois
// métodos fecham o número por motivos DIFERENTES, e um deles é sorte. Em
// `10_Faturamento_24M_Vertentes_Metalurgica`, `linhas_de_conta_verdade` = 16,
// mas o texto tem só 15 linhas de dado real (12 meses + TOTAL + Média mensal +
// Ticket médio). A verdade é contada em `Dados de Teste/comum/contagem.py`
// sobre as LINHAS DA TABELA do reportlab, antes de o PDF existir — e a regra
// dela é mecânica: conta uma linha se tem UMA célula com 3+ letras e OUTRA com
// dígito, sem saber se o dígito é ano. A própria linha de CABEÇALHO da
// tabela, `["Mês", "2024", "2025", "Variação %"]`, satisfaz essa regra
// (rótulo "Mês", valores "2024"/"2025") e é contada como conta — quando é
// cabeçalho de coluna. Medido: régua 15 — exclui o cabeçalho pelo ano solto,
// CERTA contra as 15 linhas reais, "errada" só contra o gabarito inflado.
// Este método TAMBÉM exclui o cabeçalho pelo mesmo motivo (é a única exclusão
// que ele tem) — e ainda assim fecha em 16, batendo o gabarito, porque soma o
// MESMO falso positivo de rodapé/CNPJ do parágrafo acima. As duas pernas
// concordam em 15 das 16 linhas; a 16ª sobra dos dois lados, só que num lado
// ela cancela o defeito do gabarito e no outro não. Registrado para não ler
// "bateu 16" como "este método entende cabeçalho de tabela" — ele não
// entende; entendeu por acaso.
//
// O VEREDITO HONESTO, medido nos dois books versionados (canastra + vertentes,
// 46 documentos com conta, `N8N/medir-fase0-denominador.mjs --book <nome>`):
// este método SOBRECONTA em relação a `linhasDeConta` na maioria dos
// documentos (erro absoluto médio ~8-25% contra ~1-5% da régua atual) — ele
// não filtra CNPJ, CRC, Página, Nota nem assinatura, então cada um desses
// vira uma linha a mais. Mas ele SUBCONTA em só 1 dos 46 (o
// `25_Situacao_Fiscal`, cujo texto já vem mesclado antes de qualquer contagem
// — ver acima), contra 4 dos 46 para `linhasDeConta`. NÃO é um wrapper da
// régua atual: erra em documentos DIFERENTES (concorda exatamente em 0 dos 4
// documentos onde a régua atual erra) e erra para o lado QUE O PROJETO
// considera seguro — contar a mais nunca esconde extração pela metade; contar
// a menos, sim. Dos 4 documentos em que a régua atual conta a menos, este
// método vira para o lado seguro (conta a mais) em 3 (`25_Situacao_Fiscal`,
// `10_Faturamento_24M`, `11_Mapa_Divida`) e SOBRECONTA AINDA MAIS no quarto
// (`21_Mutuos`: verdade 3, régua 2, este método 6) — nenhum dos 4 fica pior
// do lado perigoso, e nenhum vira demonstração de que o método é bom: é a
// assimetria do projeto na prática, não uma vitória sem preço.

// Ano solto (1900-2099) e data DD/MM/AAAA — a única forma que este método
// sabe que não mede número, e sabe pela FORMA do dígito, não por lista de
// palavra.
const ANO_SOLTO = /\b(19|20)\d{2}\b/g;
const DATA_DMA = /\b\d{1,2}\/\d{1,2}\/\d{2,4}\b/g;

/**
 * Esta linha, isolada, tem algum número que NÃO é ano solto nem data?
 */
export function temFormaMonetaria(linha) {
  if (typeof linha !== 'string' || linha.length === 0) return false;
  const resto = linha.replace(DATA_DMA, ' ').replace(ANO_SOLTO, ' ');
  return /\d/.test(resto);
}

/**
 * O segundo método completo: linhas do texto (já emendado de fragmento —
 * `juntarFragmentosDeLinha`, a mesma emenda que `linhasDeConta` usa, porque
 * corrigir o corte de linha do extrator não é o princípio em disputa) que
 * sobram depois de tirar ano solto e data.
 */
export function linhasDeContaPorForma(texto, { juntarFragmentos } = {}) {
  if (typeof texto !== 'string' || texto.length === 0) return [];
  const normalizado = typeof juntarFragmentos === 'function' ? juntarFragmentos(texto) : texto;
  const out = [];
  for (const bruta of normalizado.split('\n')) {
    const linha = bruta.trim();
    if (linha.length === 0) continue;
    if (temFormaMonetaria(linha)) out.push(linha);
  }
  return out;
}
