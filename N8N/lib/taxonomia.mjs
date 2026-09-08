// Espelho da taxonomia v1 (Arquitetura do Sistema/2 Especificação/f0/03) para o classificador determinístico.
//
// FONTE DA VERDADE = tabela `taxonomia_tipo_documento` no Postgres (Arquitetura do Sistema/1 Visão e Doutrina/02).
// Este arquivo é um ESPELHO de runtime usado só pela classificação por nome de
// arquivo (mapeamento código→apelidos/keywords). Mantê-lo em sync com o seed
// Supabase/migrations/0002. Não adicionar regra de negócio aqui além de aliases.

// Kit Básico — obrigatórios (verificados no Portão 1).
export const KIT_BASICO = [
  'DRE',
  'BALANCO',
  'FLUXO_CAIXA',
  'COMBINADO',
  'FATURAMENTO_24M',
  'MUTUOS',
  'FAT_INTRAGRUPO',
  'CONTRATO_SOCIAL',
];

// Bloqueantes NÃO-sobrepujáveis (Arquitetura do Sistema/2 Especificação/f0/04) — nenhuma ressalva libera.
export const NAO_SOBREPUJAVEIS = [
  'DRE',
  'BALANCO',
  'COMBINADO',
  'MUTUOS',
  'CONTRATO_SOCIAL',
];

// Apelidos/keywords por código. Ordem importa: as regras mais específicas
// (ex.: faturamento intragrupo) devem ser testadas antes das genéricas.
// Termos já normalizados (minúsculos, sem acento) — ver normalize.mjs.
export const ALIASES = [
  // --- específicos primeiro ---
  // RAZAO vem ANTES de AGING_AP por um achado do book-canastra: o arquivo
  // "17_Livro_Razao_Fornecedores_..." saía como AGING_AP, porque 'fornecedores'
  // — termo de UMA palavra e genérico — era testado antes de 'livro razao'.
  // Razão de fornecedores é livro contábil (lançamento a lançamento), não
  // relação de contas a pagar por faixa de vencimento: as duas coisas têm
  // colunas, granularidade e uso diferentes, e trocar uma pela outra manda o
  // documento para a aba errada. A regra do arquivo já era "o mais específico
  // primeiro"; era a ORDEM que não a seguia.
  { codigo: 'RAZAO', termos: ['livro razao', 'razao contabil', 'razao analitico'] },
  { codigo: 'FAT_INTRAGRUPO', termos: ['faturamento intragrupo', 'fat intragrupo', 'faturamento intra grupo'] },
  { codigo: 'FATURAMENTO_24M', termos: ['relatorio de faturamento', 'faturamento 24m',
    'faturamento 36', 'faturamento', 'receita bruta', 'receita'] },
  { codigo: 'CONTRATO_SOCIAL', termos: ['contrato social', 'estatuto social', 'alteracao contratual', 'estatuto'] },
  { codigo: 'MUTUOS', termos: ['mutuos', 'mutuo', 'relacao de mutuos', 'contas intragrupo'] },
  { codigo: 'COMBINADO', termos: ['combinado', 'combinada', 'demonstracoes combinadas', 'df combinada'] },
  { codigo: 'FLUXO_CAIXA', termos: [
    // 'fluxos de caixa' (PLURAL) é como o book real escreve, e a frase no
    // singular não casa — medido nos 190 nomes do araucária: quatro arquivos
    // saíam com a empresa "Fluxos Araucaria Serraria".
    'demonstracao dos fluxos de caixa', 'fluxos de caixa', 'fluxo de caixa',
    'fluxo caixa', 'dfc', 'cash flow', 'fluxos', 'fluxo'] },
  { codigo: 'DRE', termos: ['dre', 'demonstracao de resultado', 'demonstracao do resultado', 'resultado do exercicio'] },
  { codigo: 'BALANCO', termos: ['balanco patrimonial', 'balanco', 'bp'] },
  // DMPL/DVA vêm DEPOIS das demonstrações principais de propósito (Supabase/migrations/0024).
  // O caso comum de "DMPL" no nome de arquivo é o PDF COMPOSTO ("Balanço
  // Patrimonial DRE, DFC, DMPL 2024.pdf" — arquivo real do dono), que pela
  // taxonomia (Arquitetura do Sistema/2 Especificação/f0/03) é a demonstração PRINCIPAL, não a DMPL. Testando antes de
  // BALANCO/DRE, esse arquivo viraria DMPL — regressão. Aqui, só o documento
  // que é SÓ a DMPL/DVA ("09_DMPL_Metalurgica_2025.pdf") cai nestes códigos.
  { codigo: 'DMPL', termos: ['dmpl', 'mutacoes do patrimonio liquido',
    'mutacoes do patrimonio', 'mutacoes patrimonio', 'demonstracao das mutacoes'] },
  { codigo: 'DVA', termos: ['dva', 'valor adicionado'] },
  // --- variáveis (complementares) mais comuns, para não cair em "não classificado" à toa ---
  { codigo: 'BALANCETE', termos: ['balancete'] },
  // "Demonstrações Contábeis 2025.pdf" / "Demonstrações Financeiras 2025.pdf" é o
  // nome com que o conjunto CHEGA num mandato real — o PDF do exercício com
  // Balanço + DRE + DFC + DMPL + notas juntos, auditado ou não. Sem estes termos
  // o arquivo ficava SEM TIPO, e um documento sem tipo não tem aba nenhuma no
  // export (o roteamento por linha só socorre o que declara duas demonstrações).
  // Vem depois de BALANCO/DRE/FLUXO/COMBINADO de propósito: nome que diz qual
  // demonstração é a principal ("Balanço Patrimonial e DRE 2025") continua sendo
  // dela — mesma razão pela qual DMPL/DVA ficam abaixo das principais.
  { codigo: 'DF_AUDITADA', termos: [
    'demonstracoes financeiras auditadas', 'df auditada', 'demonstracoes auditadas',
    'demonstracoes contabeis', 'demonstracoes financeiras', 'demonstracao contabil',
    'demonstracoes contabeis completas', 'dfs',
    // O PARECER É A PEÇA AUDITADA, e sem estes termos ele fica SEM TIPO:
    // medido nos 190 nomes do araucária, `157_Relatorio_do_Auditor_Independente`
    // e o `158_..._reemitido` não casavam alias nenhum. É o documento de
    // autoridade 60 da 0151 — o que decide um conflito —, e ele chegava mudo.
    'relatorio do auditor independente', 'relatorio do auditor',
    'parecer do auditor independente', 'parecer do auditor', 'parecer de auditoria',
  ] },
  { codigo: 'MAPA_DIVIDA', termos: ['mapa de divida bancaria', 'mapa de divida',
    'mapa divida', 'divida bancaria', 'posicao de divida'] },
  { codigo: 'EXTRATO_BANCARIO', termos: ['extrato bancario', 'extrato'] },
  { codigo: 'AGING_AR', termos: ['aging de contas a receber', 'aging de recebiveis',
    'posicao de recebiveis por sacado', 'posicao de recebiveis', 'aging ar',
    'contas a receber'] },
  { codigo: 'AGING_AP', termos: ['aging de pagaveis', 'aging ap', 'contas a pagar', 'fornecedores'] },
  { codigo: 'ESTOQUE', termos: ['estoque', 'estoques'] },
  // HEADCOUNT já existia na taxonomia (seed 0002: "Headcount / folha de
  // pagamento") mas sem alias nenhum aqui — achado na rodada do lote 7377
  // (02/09, book "teste Canastra"): `28_Folha_de_Pagamento` saiu com
  // confiança da IA 0,9 (acima do limiar 0,70) mas MESMO ASSIM abriu
  // `classificacao_pendente`, porque `codigosConhecidos()` (ia.mjs) deriva o
  // enum do schema estrito de `KIT_BASICO` + `ALIASES.map(codigo)` — sem
  // entrada aqui, HEADCOUNT não existia no enum que a IA podia devolver, e
  // `fn_registrar_documento` (0127) nunca via um `tipo_taxonomia` do catálogo
  // para aceitar automaticamente. Não é caso de tipo novo: a taxonomia já
  // nomeia a família: só faltava o alias, dos dois lados (nome de arquivo e
  // enum da IA) — mesma família de checklist incompleto que 0157/0159.
  { codigo: 'HEADCOUNT', termos: ['folha de pagamento', 'folha pagamento', 'headcount'] },
  // 'negativas', 'societario' e 'parcelamentos' entram AQUI, no vocabulário de
  // tipo, e não numa lista à parte. Eles são a segunda palavra do nome que o
  // cliente escreve ("30_Certidoes_Negativas_...", "organograma SOCIETARIO",
  // "situacao fiscal e PARCELAMENTOS") e o alias que casa é o pedaço curto, então
  // a sobra grudava no nome da empresa: `parseEntidade` mantinha os três numa
  // lista de RUÍDO escrita à mão, com um comentário dizendo que o lugar certo
  // era a taxonomia. É este o lugar certo — a remoção de palavra de tipo em
  // `parseEntidade` varre o vocabulário palavra a palavra, então quem entra aqui
  // passa a ser removido de graça, e a lista à mão deixou de existir.
  { codigo: 'CERTIDOES', termos: ['certidao', 'certidoes', 'cnd', 'certidoes negativas', 'negativas', 'negativa'] },
  { codigo: 'CONTINGENCIAS', termos: ['contingencia', 'contingencias', 'processos judiciais'] },
  { codigo: 'SITUACAO_FISCAL', termos: ['situacao fiscal', 'parcelamento', 'parcelamentos', 'refis'] },
  { codigo: 'ORGANOGRAMA', termos: ['organograma', 'organograma societario', 'societario', 'societaria'] },
  { codigo: 'NOTAS_EXPL', termos: ['notas explicativas'] },
];
