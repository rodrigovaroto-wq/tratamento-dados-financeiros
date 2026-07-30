// Extração + DIAGNÓSTICO do documento (E2) via OpenAI — modo SOMBRA (N0/N1).
//
// Antes, esta chamada só extraía linhas financeiras (chave+valor). Ela já
// rodava SEMPRE (para todo documento, independente da confiança da
// classificação por nome) — então virou o lugar natural para resolver 3
// lacunas encontradas em produção:
//   1. Entidade nunca era extraída quando o nome do arquivo já dava confiança
//      alta no tipo/período (o fallback de classificação por conteúdo nunca
//      rodava para esses casos, e SÓ ele buscava entidade).
//   2. Não havia diagnóstico de conteúdo nenhum nesses casos: nada conferia
//      se o tipo/período do nome batem com o que está escrito dentro, nem
//      sinalizava qualidade/legibilidade real do arquivo.
//   3. As linhas extraídas vinham em lista achatada, sem agrupamento — difícil
//      de ler como uma "planilha" organizada (Ativo Circulante, Passivo
//      Circulante, PL, etc.).
//
// Uma ÚNICA chamada agora faz as duas coisas (não aumenta o número de
// chamadas à OpenAI): extrai linhas com `secao` (agrupador livre, espelha a
// estrutura do documento original) E devolve um bloco `diagnostico` (entidade,
// confere tipo/período, legibilidade, resumo, justificativa).
//
// Doutrina (docs/01): tudo aqui continua SUGESTÃO. Nada decide sozinho —
// diagnóstico gera pendência tipada para revisão humana (ver
// db/migrations/0010_diagnostico_e1e2.sql → fn_registrar_diagnostico);
// linhas continuam em N0 (sombra), sem entrar em base sem aceite humano.

import { codigosConhecidos } from './openai.mjs';

const OPENAI_URL = 'https://api.openai.com/v1/chat/completions';
const DEFAULT_MODEL = 'gpt-4o';

const PERIODO_TIPO_ENUM = ['anual', 'trimestre', 'multi', 'data-base', 'outro', 'desconhecido'];

// Seção CANÔNICA sugerida pela IA por linha (N1 — sugestão, não fato). É o
// mesmo conjunto de chaves internas do classificador do export
// (portal/src/lib/statement-templates.ts) — mantê-los IDÊNTICOS: se um lado
// mudar, o outro precisa acompanhar (não há import cruzado entre .mjs e o
// portal TS). Serve para o classificador determinístico do export ter um
// sinal interpretativo forte QUANDO ele mesmo não consegue classificar por
// regra — reduz o bloco "Contas Não Classificadas" sem virar fato (a linha
// continua pendente/âmbar até o aceite humano). "NAO_CLASSIFICAVEL" é o
// escape (a IA não força um palpite ruim — deixa cair no bloco de revisão).
export const SECAO_CANONICA_ENUM = [
  'ativo_circulante', 'ativo_nao_circulante',
  'passivo_circulante', 'passivo_nao_circulante', 'patrimonio_liquido',
  'receita_bruta', 'custos', 'despesas_operacionais', 'resultado_financeiro', 'impostos_lucro',
  'atividades_operacionais', 'atividades_investimento', 'atividades_financiamento',
  // DMPL e DVA (db/migrations/0024). Não são seções de outra demonstração: são
  // demonstrações INTEIRAS, e é por isso que precisam de valor próprio aqui.
  // Sem elas, a linha de uma DMPL embutida num PDF composto só tinha dois
  // destinos ruins — "patrimonio_liquido" (o saldo de fechamento REPETE o total
  // do PL, então somá-lo INFLA o balanço: bug real do export do dono) ou
  // "NAO_CLASSIFICAVEL". Com o valor próprio, a linha é roteada para a aba da
  // sua demonstração, do mesmo jeito que Balanço/DRE/Fluxo já são.
  'dmpl', 'dva',
  'NAO_CLASSIFICAVEL',
];

// Exportado de propósito: `build-workflow.mjs` embute ESTE texto no nó Code do
// workflow (via JSON.stringify), em vez de manter uma paráfrase manual. Antes
// havia três cópias do prompt (aqui, no gerador e no JSON gerado) e elas já
// tinham divergido de fato — uma melhoria aplicada aqui não chegava à produção
// até alguém reescrever o mirror à mão. Fonte única agora.
export const SYSTEM_PROMPT = [
  'Você analisa UM documento financeiro de um mandato de Reestruturação (contexto Brasil) e',
  'devolve DUAS coisas: um diagnóstico do documento e a extração linha a linha de TODOS os',
  'dados financeiros nele contidos, organizados como uma planilha.',
  '',
  '== DIAGNÓSTICO ==',
  'entidade: razão social da empresa dona do documento, se aparecer no conteúdo (null se não',
  '  visível — NUNCA invente). NÃO use o nome de quem ASSINOU o documento (contador, administrador,',
  '  sócio) — o bloco de assinatura (com CRC, CPF, "Contador", "Administrador") é o SIGNATÁRIO, não',
  '  a entidade. Se o documento combina VÁRIAS empresas (colunas por empresa — ver LINHAS abaixo),',
  '  use o nome do GRUPO se houver um; senão deixe null (não escolha uma das empresas ao acaso).',
  'tipo_confirma / tipo_sugerido: você recebe uma DICA de tipo (vinda do nome do arquivo).',
  '  Leia o conteúdo e diga se ele bate (tipo_confirma=true) com a dica. tipo_sugerido é o',
  '  código da taxonomia que o CONTEÚDO sugere (pode ser igual ou diferente da dica — use',
  '  "DESCONHECIDO" só se o documento estiver genuinamente ilegível/não-financeiro).',
  '  BALANCO vs COMBINADO (confusão comum): COMBINADO = demonstrações de um GRUPO de VÁRIAS',
  '  empresas juntas (colunas por empresa: "Empresa A | Empresa B | Total"). Um único arquivo com',
  '  VÁRIAS demonstrações (Balanço + DRE + Fluxo de Caixa + DMPL) de UMA entidade só NÃO é',
  '  COMBINADO — classifique pela demonstração principal (normalmente BALANCO). Regra prática: se',
  '  as linhas têm entidade_coluna preenchido (várias empresas) → COMBINADO; se é uma entidade só',
  '  (mesmo com várias demonstrações no arquivo) → o tipo da demonstração principal.',
  '  DMPL e DVA são códigos próprios: use "DMPL" quando o documento É a Demonstração das Mutações',
  '  do Patrimônio Líquido (linhas de movimentação do PL — saldos de abertura/fechamento, lucro ou',
  '  prejuízo do exercício, dividendos, aumento de capital — com colunas por componente do PL) e',
  '  "DVA" quando é a Demonstração do Valor Adicionado (CPC 09: receitas, insumos adquiridos de',
  '  terceiros, valor adicionado a distribuir e sua distribuição). Se a DMPL/DVA é só UMA das',
  '  demonstrações dentro de um arquivo que traz várias, o tipo do DOCUMENTO continua sendo o da',
  '  demonstração principal — a separação por demonstração acontece linha a linha (secao_canonica).',
  'periodo_tipo / periodo_referencia: o período de competência real do conteúdo. É o período ATUAL',
  '  do documento — NÃO use a data de um SALDO DE ABERTURA/exercício anterior (ex.: uma DMPL que',
  '  mostra "Saldos em 31/12/2023" e "Saldos em 31/12/2024" é um documento de 2024; 2023 é só o',
  '  saldo inicial, não o período). EMITA periodo_referencia SEMPRE numa destas formas exatas',
  '  (notação canônica do sistema — não invente outro formato):',
  '  - exercício anual completo → "12M" + ano de 2 dígitos. Ex.: 2025 → "12M25".',
  '  - trimestre → dígito do trimestre + "T" + ano de 2 dígitos. Ex.: 1º tri/2025 → "1T25".',
  '  - período de N meses corridos (últimos N meses) → "L" + N + "M". Ex.: últimos 24 meses → "L24M".',
  '  - vários exercícios no mesmo documento → anos de 2 dígitos separados por vírgula, em ordem',
  '    crescente. Ex.: 2023, 2024 e 2025 → "23,24,25".',
  '  - data-base (posição numa data específica) → ISO "AAAA-MM-DD". Ex.: 15/01/2025 → "2025-01-15".',
  '  - período de N meses de um ano específico (parcial) → N + "M" + ano de 2 dígitos. Ex.: 9 meses',
  '    de 2024 → "9M24".',
  '  Use o periodo_tipo coerente com a forma escolhida ("anual", "trimestre", "multi", "data-base").',
  'legibilidade: "ok" | "degradado" | "ilegivel" — avaliação real do ARQUIVO em si (não da',
  '  classificação): páginas faltando, tabela cortada, digitalização ruim, texto ilegível,',
  '  arquivo aparentemente incompleto. nota_legibilidade explica objetivamente QUANDO != "ok"',
  '  (null quando "ok").',
  'resumo: 2-3 frases objetivas do que o documento contém (para alguém decidir sem abrir o',
  '  arquivo).',
  'justificativa: 1-2 frases explicando o diagnóstico acima (o que você viu ou não viu).',
  '',
  '== MOEDA E ESCALA (nível do documento) ==',
  'moeda: código ISO da moeda em que os valores estão expressos — "BRL" para Real, "USD" para',
  '  dólar, "EUR" para euro. Use o código, não o símbolo. null se não houver indicação nenhuma.',
  'unidade: o FATOR DE ESCALA dos valores, declarado no cabeçalho/título das demonstrações',
  '  ("Em R$ mil", "valores expressos em milhares de reais", "R$ milhões", "em unidades"). Responda',
  '  com UMA destas três palavras exatas, e nada mais:',
  '  - "unidade" → os valores estão em reais inteiros (o caso mais comum; use também quando o',
  '    documento não declara escala nenhuma).',
  '  - "milhar" → os valores estão em milhares (multiplicar por 1.000 para ter o valor real).',
  '  - "milhao" → os valores estão em milhões (multiplicar por 1.000.000).',
  '  NÃO converta os valores você mesmo: extraia os números COMO ESTÃO impressos no documento e',
  '  declare a escala aqui — a conversão é feita depois, de forma auditável. A escala é crítica:',
  '  errá-la altera o valor em 1000x.',
  '  Atenção: a escala vale para os valores MONETÁRIOS. Linhas que não são dinheiro (percentuais,',
  '  margens em %, lucro POR AÇÃO, quantidades, índices, prazos em dias) não estão nessa escala —',
  '  extraia o número como impresso e mantenha o "%"/unidade no valor_texto para ficar evidente.',
  '',
  '== LINHAS (planilha) ==',
  'Cada linha do JSON usa chaves CURTAS (economia de tokens de saída em documentos com muitas',
  'contas): s=secao, sc=secao_canonica, ec=entidade_coluna, pc=periodo_coluna, k=chave,',
  'vt=valor_texto, vn=valor_num, op=origem_pagina, cf=confianca. O texto abaixo usa os nomes',
  'completos (mais claro de explicar) — sempre correspondendo à chave curta do schema.',
  'Extraia TODAS as linhas financeiras do documento (rótulo + valor), preservando a estrutura',
  'original como uma "secao" por linha — ex.: "Ativo Circulante", "Ativo Não Circulante",',
  '"Passivo Circulante", "Passivo Não Circulante", "Patrimônio Líquido", "Receita Operacional",',
  '"Custos", "Despesas Operacionais", "Atividades Operacionais", "Atividades de Investimento",',
  '"Atividades de Financiamento" — use os agrupadores que o PRÓPRIO documento usa; null se a',
  'linha não pertencer a nenhuma seção clara (ex.: um total geral solto).',
  'valor_texto = o valor COMO APARECE no documento (com os separadores e sinais originais).',
  'valor_num = o mesmo valor como número puro, ou null quando não houver número. Regras de',
  'conversão (documentos brasileiros — siga à risca, é fonte comum de erro):',
  '- NOTAÇÃO DECIMAL BR: o ponto é separador de MILHAR e a vírgula é o separador DECIMAL.',
  '  "1.234,56" → 1234.56 ; "12.080.078,23" → 12080078.23 ; "1.000" → 1000 (mil, não 1,0).',
  '- SINAL NEGATIVO: valores entre PARÊNTESES são NEGATIVOS — "(6.000,00)" → -6000.00. Idem sinal',
  '  de menos antes ou DEPOIS do número ("6.000-" → -6000). Em demonstrações, deduções da receita,',
  '  custos, despesas e saídas de caixa costumam vir entre parênteses: preserve o sinal negativo.',
  '- BALANCETE COM COLUNAS DEVEDOR/CREDOR (ou sufixo "D"/"C"): use o sinal conforme a natureza do',
  '  saldo — saldo devedor (D) positivo em contas de ativo/despesa; saldo credor (C) positivo em',
  '  contas de passivo/PL/receita. Não misture: mantenha a mesma convenção em todo o documento.',
  '- Não aplique a escala de "unidade" aqui: o número vai como impresso (ver MOEDA E ESCALA).',
  'Informe a página de origem.',
  'NÃO invente linhas nem valores. Se algo não estiver legível, omita — é melhor extrair de',
  'menos com confiança do que inventar.',
  '',
  'DOCUMENTO COM VÁRIAS ENTIDADES/COLUNAS LADO A LADO (ex.: um balanço combinado com colunas',
  '"Empresa A | Empresa B | Total"): isto é comum e NÃO deve ser resumido num valor só por',
  'conta — gere uma LINHA SEPARADA para cada combinação (conta × coluna), com o MESMO "chave"',
  '(rótulo da conta) e "entidade_coluna" preenchido com o nome EXATO do cabeçalho da coluna',
  '("Empresa A", "Empresa B", "Total", etc.). Nunca some, escolha ou estime um valor único',
  'representando várias colunas — se não conseguir ler alguma coluna com confiança, omita SÓ',
  'aquela linha (conta × coluna), não invente. Quando o documento é de uma entidade só (o caso',
  'comum), deixe "entidade_coluna" null em todas as linhas.',
  '',
  'DOCUMENTO COMPARATIVO — VÁRIAS COLUNAS DE PERÍODO LADO A LADO (ex.: um balanço ou DRE com',
  'colunas "2023 | 2024", ou "31/12/2023 | 31/12/2024", ou "Exercício atual | Exercício anterior"):',
  'isto é o padrão em demonstrações contábeis e NÃO deve ser resumido num valor só por conta —',
  'gere uma LINHA SEPARADA para cada (conta × período), com o MESMO "chave" e "periodo_coluna"',
  'preenchido com o rótulo EXATO da coluna de período ("2023", "2024", "31/12/2024", etc.). Isto é',
  'ortogonal a "entidade_coluna": um documento pode ter as duas dimensões (várias empresas E vários',
  'anos), gerando uma linha por (conta × empresa × período), cada uma com entidade_coluna E',
  'periodo_coluna preenchidos. Quando o documento tem um único período (o caso comum), deixe',
  '"periodo_coluna" null em todas as linhas. Nunca some, escolha ou estime um valor único cobrindo',
  'vários períodos.',
  '',
  'DMPL — DEMONSTRAÇÃO DAS MUTAÇÕES DO PATRIMÔNIO LÍQUIDO (formato de MATRIZ, trate assim SEMPRE,',
  'inclusive quando ela é só uma parte de um arquivo com várias demonstrações): as linhas são',
  'MOVIMENTOS do exercício ("SALDOS EM 31 DE DEZEMBRO DE 2024", "Prejuízo líquido do exercício",',
  '"Aumento de capital", "Dividendos distribuídos", "SALDOS EM 31 DE DEZEMBRO DE 2025") e as',
  'COLUNAS são os componentes do PL ("Capital social", "Capital a integralizar", "Reserva legal",',
  '"Ajuste de avaliação patrimonial", "Prejuízos acumulados", "Total"). Gere uma linha do JSON para',
  'cada CRUZAMENTO com valor, com "secao" = o rótulo do MOVIMENTO (a linha da tabela) e "chave" = o',
  'rótulo do COMPONENTE do PL (o cabeçalho da coluna) — é o componente que é a CONTA. Não use',
  'entidade_coluna para os componentes do PL: ela é só para colunas de EMPRESAS diferentes. Células',
  'vazias ou com traço ("-") não geram linha nenhuma. Não some nem recalcule a coluna "Total": se o',
  'documento a traz, extraia como veio; se não traz, não invente.',
  '',
  'secao_canonica: além da "secao" livre acima, classifique CADA linha em UMA seção canônica',
  'padronizada (para a planilha final organizar as contas na estrutura de mercado). Use o',
  'julgamento contábil (o significado da conta, não só o nome literal — cada empresa nomeia',
  'diferente). Valores possíveis e seu significado:',
  '- Balanço/Balancete: "ativo_circulante", "ativo_nao_circulante", "passivo_circulante",',
  '  "passivo_nao_circulante", "patrimonio_liquido" (ex.: um mútuo A RECEBER é ativo; um mútuo',
  '  A PAGAR/tomado é passivo — decida pelo sentido).',
  '- DRE: "receita_bruta" (receita e deduções), "custos" (CPV/CMV/custo de serviço),',
  '  "despesas_operacionais" (vendas/administrativas/gerais), "resultado_financeiro"',
  '  (receitas/despesas financeiras, juros), "impostos_lucro" (IRPJ/CSLL).',
  '- Fluxo de Caixa: "atividades_operacionais", "atividades_investimento", "atividades_financiamento".',
  '- DMPL: "dmpl" para TODA linha da Demonstração das Mutações do Patrimônio Líquido (inclusive os',
  '  saldos de abertura/fechamento). Nunca marque uma linha de DMPL como "patrimonio_liquido": o',
  '  saldo de fechamento da DMPL REPETE o total do PL do balanço, e classificá-lo como conta do PL',
  '  faz o patrimônio ser contado duas vezes.',
  '- DVA: "dva" para toda linha da Demonstração do Valor Adicionado (tanto a geração — receitas,',
  '  insumos, depreciação, valor adicionado recebido em transferência — quanto a distribuição —',
  '  pessoal, impostos, remuneração de capitais de terceiros e próprios).',
  'Use "NAO_CLASSIFICAVEL" quando a linha for um TOTAL/subtotal geral, ou quando você não tiver',
  'segurança de qual seção é — NÃO force um palpite ruim (a linha vai para revisão manual, o que',
  'é preferível a classificar errado). Isto é uma SUGESTÃO revisável por humano, nunca um fato.',
].join(' ');

export function extractionSchema() {
  return {
    name: 'diagnostico_e_extracao',
    strict: true,
    schema: {
      type: 'object',
      additionalProperties: false,
      required: ['moeda', 'unidade', 'diagnostico', 'linhas'],
      properties: {
        moeda: { type: ['string', 'null'] },
        unidade: { type: ['string', 'null'] },
        diagnostico: {
          type: 'object',
          additionalProperties: false,
          required: [
            'entidade', 'tipo_confirma', 'tipo_sugerido', 'periodo_tipo', 'periodo_referencia',
            'legibilidade', 'nota_legibilidade', 'resumo', 'justificativa',
          ],
          properties: {
            entidade: { type: ['string', 'null'] },
            tipo_confirma: { type: 'boolean' },
            tipo_sugerido: { type: 'string', enum: codigosConhecidos() },
            periodo_tipo: { type: 'string', enum: PERIODO_TIPO_ENUM },
            periodo_referencia: { type: ['string', 'null'] },
            legibilidade: { type: 'string', enum: ['ok', 'degradado', 'ilegivel'] },
            nota_legibilidade: { type: ['string', 'null'] },
            resumo: { type: 'string' },
            justificativa: { type: 'string' },
          },
        },
        // Chaves CURTAS de propósito (s/sc/ec/pc/k/vt/vn/op/cf): `linhas` é o
        // único bloco que se repete centenas de vezes por documento — cada
        // caractere de nome de propriedade é gasto de novo A CADA linha no
        // JSON de saída. Documentos consolidados comparativos (2-3 anos lado
        // a lado, cada conta vira 2-3 linhas via periodo_coluna) truncavam
        // (finish_reason=length) antes mesmo de terminar de listar as contas —
        // achado em produção (sessão 7 cont.¹¹, "teste v18": 6 de 16
        // documentos, todos consolidados multi-ano). Nomes curtos aqui NÃO
        // mudam nada gravado no banco — `parseExtractionResponse` remapeia de
        // volta para os nomes completos (campo_extraido.secao_canonica etc.
        // continuam com os valores descritivos de sempre, só a REPRESENTAÇÃO
        // NO FIO com a OpenAI é compacta). `description` em cada campo mantém
        // o modelo orientado apesar do nome curto.
        linhas: {
          type: 'array',
          items: {
            type: 'object',
            additionalProperties: false,
            required: ['s', 'sc', 'ec', 'pc', 'k', 'vt', 'vn', 'op', 'cf'],
            properties: {
              s: { type: ['string', 'null'], description: 'secao: agrupador livre (rótulo do próprio documento)' },
              sc: { type: 'string', enum: SECAO_CANONICA_ENUM, description: 'secao_canonica: seção padronizada pelo significado contábil' },
              ec: { type: ['string', 'null'], description: 'entidade_coluna: nome da coluna/empresa quando há várias entidades lado a lado' },
              pc: { type: ['string', 'null'], description: 'periodo_coluna: rótulo da coluna de período quando há vários períodos lado a lado' },
              k: { type: 'string', description: 'chave: rótulo da conta' },
              vt: { type: ['string', 'null'], description: 'valor_texto: valor como aparece no documento' },
              vn: { type: ['number', 'null'], description: 'valor_num: valor numérico puro' },
              op: { type: ['integer', 'null'], description: 'origem_pagina: página de origem' },
              cf: { type: 'number', description: 'confianca: confiança 0-1 desta linha' },
            },
          },
        },
      },
    },
  };
}

// Teto de tokens de saída do gpt-4o (16384) — explícito porque documentos
// combinados grandes (grupo com várias entidades × várias demonstrações no
// mesmo PDF) exigem um array `linhas` extenso; sem isso fica sujeito a um
// default menor de max_tokens dependendo da conta/API, que corta a resposta
// no meio do JSON sem erro nenhum (ver parseExtractionResponse: finish_reason
// 'length' → JSON incompleto → falha silenciosa, achado em produção
// reprocessando "teste v14", sessão 7 cont.⁷).
export const MAX_OUTPUT_TOKENS = 16384;

// conteudo: parte multimodal (file/image/text) — reaproveita contentPartFromFile.
export function buildExtractionRequest({ tipo, nomeOriginal, conteudo, model = DEFAULT_MODEL }) {
  return {
    url: OPENAI_URL,
    method: 'POST',
    body: {
      model,
      temperature: 0,
      max_tokens: MAX_OUTPUT_TOKENS,
      response_format: { type: 'json_schema', json_schema: extractionSchema() },
      messages: [
        { role: 'system', content: SYSTEM_PROMPT },
        {
          role: 'user',
          content: [
            {
              type: 'text',
              text: `Nome do arquivo: ${nomeOriginal || '(sem nome)'}. Dica de tipo (do nome, pode estar `
                + `errada): ${tipo || 'desconhecido'}. Diagnostique e extraia as linhas financeiras.`,
            },
            ...(Array.isArray(conteudo) ? conteudo : [conteudo]),
          ],
        },
      ],
    },
  };
}

// Normaliza a resposta para { moeda, unidade, campos[], diagnostico, falhaMotivo }.
// campos já vem no formato de fn_registrar_campos_extraidos (inclui secao).
// falhaMotivo é null quando a extração veio ok; motivo textual (para virar
// pendência tipada 'extracao_falhou') quando a chamada errou, veio truncada
// (finish_reason 'length' — teto de tokens de saída estourado) ou o conteúdo
// não é JSON válido. Sem isso, uma falha silenciosa gera 0 campos e ninguém
// nunca fica sabendo (achado em produção, sessão 7 cont.⁷ — "teste v14").
// Normalização de ESCALA na fronteira. O prompt pede "unidade"|"milhar"|"milhao",
// mas o campo é texto livre no schema (fechá-lo em enum exigiria validar contra a
// API real, que não temos aqui) e documentos já processados trazem variedade
// ("R$ mil", "milhares de reais", "em milhões"). Como a `unidade` é herdada por
// TODA linha e a reconciliação Classe A compara a unidade de DOIS documentos
// diferentes (0009: divergência aborta a checagem), texto livre inconsistente
// gera "precondição não satisfeita" falsa — normalizar aqui torna a comparação
// confiável, sem depender do humor do modelo. Desconhecido → null (nunca chuta
// uma escala: errar em 1000x é pior que não saber).
export function normalizarUnidade(bruto) {
  if (bruto == null) return null;
  const t = String(bruto)
    .normalize('NFD').replace(/[̀-ͯ]/g, '')
    .toLowerCase().trim();
  if (!t) return null;
  if (/\bmilhao|milhoes|\bmm\b|r\$\s*mi\b|\bmi\b/.test(t)) return 'milhao';
  if (/\bmilhar|milhares|\bmil\b|r\$\s*mil|\bm\$\b/.test(t)) return 'milhar';
  if (/\bunidade|\breal\b|reais|inteiro|r\$$|^r\$$/.test(t)) return 'unidade';
  if (t === '1' || t === '1.000' || t === '1000') return t === '1' ? 'unidade' : 'milhar';
  return null;
}

// Moeda para código ISO — mesmo espírito da escala: "R$"/"reais" e "BRL" devem
// virar a MESMA coisa para qualquer comparação/exibição a jusante.
export function normalizarMoeda(bruto) {
  if (bruto == null) return null;
  const t = String(bruto)
    .normalize('NFD').replace(/[̀-ͯ]/g, '')
    .toLowerCase().trim();
  if (!t) return null;
  if (/\bbrl\b|r\$|real|reais/.test(t)) return 'BRL';
  if (/\busd\b|us\$|dolar|dollar/.test(t)) return 'USD';
  if (/\beur\b|€|euro/.test(t)) return 'EUR';
  return /^[a-z]{3}$/.test(t) ? t.toUpperCase() : null;
}

// A escala do documento ("R$ mil") é herdada por TODA linha — mas demonstrações
// reais MISTURAM naturezas no mesmo arquivo: junto do balanço em milhares vêm
// linhas que NÃO estão nessa escala (percentuais, lucro por ação, quantidades,
// índices). Herdar a escala nessas linhas é uma mis-escala silenciosa: um "LPA
// 1,25" viraria 1.250 quando alguém aplicasse o fator. Aqui a herança é
// BLOQUEADA para as linhas claramente não-monetárias (unidade fica null =
// escala desconhecida, nunca uma escala errada).
//
// Sinais deliberadamente CONSERVADORES (falso positivo aqui esconderia a escala
// de uma conta monetária legítima): "%" no valor ou no rótulo, "por ação"/LPA,
// "percentual", "quantidade", "número de ações". Note que "margem" NÃO entra —
// "margem de contribuição" é conta monetária de verdade.
const RE_NAO_MONETARIA = /%|\bpercentual|\bpor acao\b|\blpa\b|\bquantidade\b|numero de acoes/;
export function ehLinhaNaoMonetaria(chave, valorTexto) {
  const norm = (s) => String(s ?? '').normalize('NFD').replace(/[̀-ͯ]/g, '').toLowerCase();
  return RE_NAO_MONETARIA.test(norm(chave)) || String(valorTexto ?? '').includes('%');
}

// ---------------------------------------------------------------------------
// DIAGNÓSTICO DE ERRO DA API — separar causas que pedem ações OPOSTAS
//
// O "teste v30" custou uma rodada inteira por causa disto: 14 de 14 documentos
// falharam e a única coisa que a pendência dizia era
//
//     "Erro da API OpenAI: Try spacing your requests out using the batching
//      settings under 'Options'"
//
// Essa frase é do **N8N**, não da OpenAI: o nó HTTP Request a acrescenta a
// QUALQUER resposta 429. E 429 na OpenAI cobre causas que pedem ações opostas:
//
//   • `insufficient_quota` / limite de faturamento → acabou o CRÉDITO.
//     Espaçar as chamadas NÃO resolve; só recarregar/subir o limite resolve.
//   • `rate_limit_exceeded` (RPM/TPM) → cadência alta. Espaçar resolve.
//   • limite DIÁRIO (TPD) → cota do dia esgotada. Espaçar não resolve hoje;
//     resolve amanhã (ou subindo o tier).
//
// Lendo só a frase do n8n, as três são indistinguíveis — e eu mesmo tratei o
// v28 como cadência e subi o intervalo de 6s para 12s sem ter evidência de que
// a causa fosse cadência. Este diagnóstico existe para que ninguém (dono ou
// sessão futura) volte a chutar isso.
//
// A busca é DEFENSIVA por desenho: dependendo da versão do n8n e do modo de
// erro, o corpo real da OpenAI aparece em lugares diferentes do objeto de erro
// (`cause`, `context.data`, `response.data`, `error.error`…), e não há como
// fixar uma forma só sem o n8n vivo do dono para conferir. Procurar em todos os
// caminhos plausíveis é mais robusto que acertar um e falhar calado nos outros.
/**
 * Classifica um erro de chamada à OpenAI numa CAUSA acionável.
 *
 * Devolve `{ causa, status, tipo, codigo, mensagem, motivo }` — `motivo` é o
 * texto que vai para a pendência: diz a causa, o que fazer, e (quando é o caso)
 * diz explicitamente o que NÃO resolve. `causa` é o código estável para teste.
 *
 * AUTO-CONTIDA de propósito: os helpers ficam DENTRO da função porque o gerador
 * do workflow embute o `toString()` dela no nó Code (nó Code do n8n não importa
 * arquivo). Com dependência de escopo externo, o mirror voltaria a ser cópia à
 * mão — e cópia à mão neste repositório já divergiu duas vezes (o prompt de
 * extração e a lista de apelidos da taxonomia). Aqui a fonte é UMA, e
 * `n8n/test/workflow-sim.test.mjs` confere que o nó carrega exatamente este
 * código. O custo (recriar helpers por chamada) é irrelevante: roda uma vez por
 * documento que FALHOU.
 */
export function diagnosticarErroApi(erro) {
  // Dependendo da versão do n8n e do modo de erro, o corpo real da OpenAI
  // aparece em lugares diferentes (`cause`, `context.data`, `response.data`,
  // `error.error`…). Sem o n8n vivo do dono não há como fixar uma forma só;
  // procurar em todos os caminhos plausíveis é mais robusto que acertar um e
  // falhar calado nos outros.
  const CAMINHOS = [
    // A FORMA REAL DO N8N, confirmada no fonte dele (não suposta):
    // `packages/@n8n/backend-network/src/http/legacy-request.ts` anexa ao erro
    // `error: responseData` — o JSON da OpenAI JÁ PARSEADO, que por sua vez é
    // `{ error: { type, code, message } }`. O item que chega ao nó Code é
    // `{ json: { error: <reason inteiro> } }`, então o corpo da OpenAI fica em
    // `error.error.error` a partir da raiz do item. Este caminho vem PRIMEIRO
    // porque é o que acontece em produção.
    (e) => e && e.error && e.error.error,
    (e) => e && e.error,                                  // corpo da OpenAI direto (ou responseData já desembrulhado)
    (e) => e && e.cause && e.cause.error,                 // NodeApiError embrulhando a resposta
    (e) => e && e.cause && e.cause.response && e.cause.response.data && e.cause.response.data.error,
    (e) => e && e.cause && e.cause.data && e.cause.data.error,
    (e) => e && e.context && e.context.data && e.context.data.error,
    (e) => e && e.response && e.response.data && e.response.data.error,
    (e) => e && e.data && e.data.error,
    (e) => e && e.cause,                                  // último recurso: o cause pode já ser o corpo
  ];
  const corpoDeErroOpenAI = (e) => {
    if (!e || typeof e !== 'object') return null;
    for (const caminho of CAMINHOS) {
      let c;
      try { c = caminho(e); } catch { continue; }
      if (c && typeof c === 'object' && (c.type || c.code || c.message)) return c;
    }
    return null;
  };
  // A FRASE do n8n como sinal de status. O n8n só acrescenta "Try spacing your
  // requests out using the batching settings under 'Options'" em resposta 429 —
  // então, quando ele entrega só a frase (sem httpCode em campo nenhum, que é
  // exatamente o caso que chegou na pendência do v30), a frase é a única
  // evidência de que houve 429. Reconhecê-la separa "sei que é limite, não sei
  // qual" de "não sei nada" — e a primeira já dá um passo concreto ao dono.
  const RE_DICA_429_N8N = /spacing your requests out|too many requests from you/i;
  const statusHttpDoErro = (e) => {
    const candidatos = [
      e && e.httpCode, e && e.status, e && e.statusCode,
      e && e.cause && e.cause.status, e && e.cause && e.cause.statusCode,
      e && e.response && e.response.status, e && e.context && e.context.httpCode,
    ];
    for (const v of candidatos) {
      const n = Number(v);
      if (Number.isFinite(n) && n >= 100 && n < 600) return n;
    }
    const texto = typeof e === 'string' ? e : ((e && e.message) || '');
    return RE_DICA_429_N8N.test(String(texto)) ? 429 : null;
  };
  // Serializar tudo é o que permite reconhecer "insufficient_quota" mesmo quando
  // ele não vem num campo estruturado (o n8n às vezes entrega só string).
  const textoDoErro = (e) => {
    if (typeof e === 'string') return e;
    try { return JSON.stringify(e); } catch { return String(e === undefined ? '' : e); }
  };

  const corpo = corpoDeErroOpenAI(erro);
  const status = statusHttpDoErro(erro);
  const tipo = corpo?.type ?? null;
  const codigo = corpo?.code ?? null;
  const mensagemOpenAI = corpo?.message ?? null;
  const mensagemBruta = typeof erro === 'string' ? erro : (erro?.message ?? null);
  // O texto completo inclui a mensagem do n8n E o corpo da OpenAI, quando os
  // dois vieram — é nele que a busca por assinatura procura.
  const alvo = `${tipo ?? ''} ${codigo ?? ''} ${mensagemOpenAI ?? ''} ${textoDoErro(erro)}`.toLowerCase();

  const tem = (...frases) => frases.some((f) => alvo.includes(f));

  let causa = 'desconhecida';
  let motivo;

  // TETO DE GASTO vem ANTES de "sem crédito" de propósito: são coisas
  // diferentes com ações diferentes, e esta é a que engana. Um teto de gasto de
  // PROJETO (ou o orçamento mensal da organização) devolve 429 com a conta
  // perfeitamente saudável — há saldo, o tier está normal, e as páginas de
  // Billing e de Limits não mostram nada de errado. Foi exatamente o relato do
  // dono depois do v30: "o limite da OpenAI está OK". Estes códigos estão na doc
  // oficial de erros da OpenAI e nenhum deles é falta de dinheiro.
  if (tem('spend_limit_exceeded', 'spend limit', 'usage_limit_exceeded',
    'usage limit', 'budget')) {
    causa = 'limite_de_gasto';
    motivo = 'TETO DE GASTO ATINGIDO na OpenAI — e isto NÃO é falta de crédito: há saldo, o tier '
      + 'está normal, e é por isso que as páginas de Billing e de Limits parecem em ordem. O que '
      + 'estourou é um LIMITE CONFIGURADO: teto do PROJETO a que a chave pertence, ou orçamento '
      + 'mensal da organização. Onde olhar: platform.openai.com → Settings → Limits (orçamento '
      + 'mensal da org) E Settings → Projects → o projeto da chave → Limits (teto do projeto). '
      + 'Espaçar as chamadas não resolve; subir o teto resolve na hora.';
  } else if (tem('insufficient_quota', 'exceeded your current quota', 'billing_hard_limit',
    'billing hard limit', 'check your plan and billing', 'account is not active',
    'credit_balance_exhausted', 'no prepaid credits')) {
    causa = 'sem_credito';
    motivo = 'CRÉDITO DA OPENAI ESGOTADO (insufficient_quota / credit_balance_exhausted). A conta '
      + 'não tem saldo pré-pago para processar. Espaçar as chamadas NÃO resolve isto — é preciso '
      + 'recarregar crédito em platform.openai.com/settings/organization/billing.';
  } else if (tem('tokens per day', 'requests per day', 'tpd', 'rpd', 'daily limit', 'per-day')) {
    causa = 'limite_diario';
    motivo = 'COTA DIÁRIA DA OPENAI ESGOTADA (limite por DIA de tokens/requisições do tier da conta). '
      + 'Espaçar as chamadas não resolve hoje: a cota reabre na virada da janela diária, ou sobe '
      + 'junto com o tier da conta.';
  } else if (tem('rate_limit_exceeded', 'rate limit', 'too many requests', 'tokens per min',
    'requests per min', 'tpm', 'rpm')) {
    causa = 'limite_cadencia';
    motivo = 'LIMITE DE CADÊNCIA DA OPENAI (rate limit por minuto). Aqui espaçar as chamadas ajuda '
      + 'de fato — é o único caso em que ajuda. Reduzir o tamanho do que é enviado (PDF como texto '
      + 'em vez de imagem) ataca a causa, porque o limite por minuto é de TOKENS, não de arquivos.';
  } else if (status === 401 || tem('invalid_api_key', 'incorrect api key', 'invalid authentication')) {
    causa = 'chave_invalida';
    motivo = 'CHAVE DA OPENAI INVÁLIDA OU AUSENTE (401). Nada a ver com cadência ou crédito: a '
      + 'credencial do nó HTTP no N8N precisa ser corrigida (header Authorization: Bearer sk-...).';
  } else if (status === 404 || tem('model_not_found', 'does not exist or you do not have access')) {
    causa = 'modelo_indisponivel';
    motivo = 'MODELO INDISPONÍVEL PARA ESTA CONTA (404). O modelo configurado no workflow não existe '
      + 'ou a conta não tem acesso a ele — conferir MODEL_EXTRACAO em n8n/build-workflow.mjs contra '
      + 'os modelos disponíveis na conta.';
  } else if (status === 429) {
    // 429 sem assinatura reconhecível: NÃO afirmar cadência. Foi exatamente o
    // palpite errado do v28→v30, e afirmar causa sem evidência é o defeito que
    // este diagnóstico existe para não repetir.
    causa = 'limite_indeterminado';
    motivo = 'LIMITE DA OPENAI ATINGIDO (HTTP 429), mas a resposta não disse QUAL: pode ser crédito '
      + 'esgotado (insufficient_quota), cota diária, ou cadência por minuto — e cada um pede ação '
      + 'diferente. Confira em platform.openai.com: se houver saldo/limite disponível, é cadência; '
      + 'se não houver, é crédito. Espaçar as chamadas só resolve o caso de cadência.';
  } else {
    motivo = `ERRO NA CHAMADA À OPENAI${status ? ` (HTTP ${status})` : ''}: `
      + `${mensagemOpenAI || mensagemBruta || textoDoErro(erro).slice(0, 300)}`;
  }

  // OS HEADERS DE RATE LIMIT são o número que o repositório inteiro só chutava:
  // `x-ratelimit-limit-tokens` é o TPM REAL da conta para aquele modelo, e
  // `retry-after` é quanto a própria OpenAI diz para esperar. O n8n preserva os
  // headers em `error.response.headers` (legacy-request.ts) — eles estavam ali no
  // v30, intactos, e o pipeline os descartava junto com o resto.
  const headers = (erro && erro.response && erro.response.headers)
    || (erro && erro.headers)
    || (erro && erro.cause && erro.cause.response && erro.cause.response.headers)
    || null;
  const h = (nome) => {
    if (!headers) return null;
    const v = typeof headers.get === 'function' ? headers.get(nome) : headers[nome];
    return v == null || v === '' ? null : String(v);
  };
  const limiteTokens = h('x-ratelimit-limit-tokens');
  const restamTokens = h('x-ratelimit-remaining-tokens');
  const esperar = h('retry-after') || h('x-ratelimit-reset-tokens');

  // Detalhe técnico junto do motivo: sem isto a sessão seguinte fica no mesmo
  // escuro em que esta ficou. Só o que é útil para decidir — não o objeto todo.
  const detalhes = [
    status ? `http=${status}` : null,
    tipo ? `type=${tipo}` : null,
    codigo ? `code=${codigo}` : null,
    limiteTokens ? `limite_tokens_min=${limiteTokens}` : null,
    restamTokens ? `restavam=${restamTokens}` : null,
    esperar ? `esperar=${esperar}` : null,
    mensagemOpenAI ? `openai="${String(mensagemOpenAI).slice(0, 200)}"` : null,
    // A mensagem do n8n entra por último e IDENTIFICADA como dele: ela é a que
    // enganou a rodada passada, então fica claro de quem é a frase.
    (mensagemBruta && mensagemBruta !== mensagemOpenAI)
      ? `n8n="${String(mensagemBruta).slice(0, 200)}"` : null,
  ].filter(Boolean).join(' ');

  return {
    causa,
    status,
    tipo,
    codigo,
    mensagem: mensagemOpenAI ?? mensagemBruta ?? null,
    motivo: detalhes ? `${motivo} [${detalhes}]` : motivo,
  };
}

export function parseExtractionResponse(apiJson) {
  const finishReason = apiJson?.choices?.[0]?.finish_reason ?? null;
  const vazio = (falhaMotivo) => ({
    moeda: null, unidade: null, campos: [], falhaMotivo,
    diagnostico: {
      entidade: null, tipo_confirma: null, tipo_sugerido: null, periodo_tipo: null,
      periodo_referencia: null, legibilidade: null, nota_legibilidade: null,
      resumo: null, justificativa: '(sem diagnóstico: falha de rede/API ou resposta inválida)',
    },
  });
  if (apiJson?.error) {
    // Diagnostica a CAUSA em vez de repassar a frase do n8n: ver
    // `diagnosticarErroApi` acima e o que o "teste v30" custou sem isto.
    return vazio(diagnosticarErroApi(apiJson.error).motivo);
  }
  const content = apiJson?.choices?.[0]?.message?.content;
  if (!content) {
    return vazio('Resposta da OpenAI sem conteúdo (falha de rede/API).');
  }
  let p;
  try {
    p = typeof content === 'string' ? JSON.parse(content) : content;
  } catch {
    if (finishReason === 'length') {
      return vazio(
        'Resposta da OpenAI truncada por limite de tokens de saída (finish_reason=length) — o JSON '
        + 'ficou incompleto e não pôde ser interpretado. Documento provavelmente grande/denso demais '
        + '(muitas contas/entidades) para uma única chamada.',
      );
    }
    return vazio('Resposta da OpenAI não veio em JSON válido.');
  }
  const unidade = normalizarUnidade(p.unidade);
  // Remapeia as chaves curtas do fio (s/sc/ec/pc/k/vt/vn/op/cf) para os nomes
  // completos usados em todo o resto do sistema (campo_extraido e por diante)
  // — a compactação é só na conversa com a OpenAI, nada rio abaixo muda.
  const campos = Array.isArray(p.linhas)
    ? p.linhas.map((l, i) => ({
        // ORDEM da linha no documento (db/migrations/0027). NÃO é pedida ao
        // modelo: é a posição no array que ele devolveu, que já é a ordem de
        // leitura do documento. Pedir um campo de ordem gastaria token de saída
        // por linha e daria ao modelo uma chance de errar algo que nós já
        // sabemos com certeza. É o que permite ao export reconhecer um subtotal
        // impresso ACIMA dos seus componentes (teste v28: Ativo Circulante da
        // VT Logística saiu 7.254 onde o documento diz 3.961).
        ordem: i,
        secao: l.s ?? null,
        secao_canonica: l.sc && l.sc !== 'NAO_CLASSIFICAVEL' ? l.sc : null,
        entidade_coluna: l.ec ?? null,
        periodo_coluna: l.pc ?? null,
        chave: l.k,
        valor_texto: l.vt ?? null,
        valor_num: typeof l.vn === 'number' ? l.vn : null,
        // escala do documento, EXCETO em linha não-monetária (ver acima)
        unidade: ehLinhaNaoMonetaria(l.k, l.vt) ? null : unidade,
        confianca: typeof l.cf === 'number' ? l.cf : null,
        origem_pagina: Number.isInteger(l.op) ? l.op : null,
      }))
    : [];
  const d = p.diagnostico || {};
  const diagnostico = {
    entidade: d.entidade ?? null,
    tipo_confirma: typeof d.tipo_confirma === 'boolean' ? d.tipo_confirma : null,
    tipo_sugerido: d.tipo_sugerido === 'DESCONHECIDO' ? null : (d.tipo_sugerido ?? null),
    periodo_tipo: d.periodo_referencia ? d.periodo_tipo : null,
    periodo_referencia: d.periodo_referencia ?? null,
    legibilidade: d.legibilidade ?? null,
    nota_legibilidade: d.nota_legibilidade ?? null,
    resumo: d.resumo ?? null,
    justificativa: d.justificativa ?? '',
  };
  // finish_reason 'length' com JSON válido é raro (o corte quase sempre cai
  // no meio de uma string/array e quebra o parse acima), mas se acontecer o
  // conteúdo pode estar incompleto de forma "silenciosa" (JSON bem formado,
  // faltando linhas do fim do documento) — sinaliza mesmo assim.
  const falhaMotivo = finishReason === 'length'
    ? 'Resposta da OpenAI atingiu o limite de tokens de saída (finish_reason=length); o JSON veio '
      + 'válido, mas o conteúdo pode estar incompleto (faltando linhas do fim do documento).'
    : null;
  return { moeda: normalizarMoeda(p.moeda), unidade, campos, diagnostico, falhaMotivo };
}

export { OPENAI_URL, DEFAULT_MODEL, PERIODO_TIPO_ENUM };
