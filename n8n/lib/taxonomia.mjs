// Espelho da taxonomia v1 (f0/03) para o classificador determinístico.
//
// FONTE DA VERDADE = tabela `taxonomia_tipo_documento` no Postgres (docs/02).
// Este arquivo é um ESPELHO de runtime usado só pela classificação por nome de
// arquivo (mapeamento código→apelidos/keywords). Mantê-lo em sync com o seed
// db/migrations/0002. Não adicionar regra de negócio aqui além de aliases.

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

// Bloqueantes NÃO-sobrepujáveis (f0/04) — nenhuma ressalva libera.
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
  { codigo: 'FAT_INTRAGRUPO', termos: ['faturamento intragrupo', 'fat intragrupo', 'faturamento intra grupo'] },
  { codigo: 'FATURAMENTO_24M', termos: ['faturamento 24m', 'faturamento 36', 'faturamento', 'receita bruta', 'receita'] },
  { codigo: 'CONTRATO_SOCIAL', termos: ['contrato social', 'estatuto social', 'alteracao contratual', 'estatuto'] },
  { codigo: 'MUTUOS', termos: ['mutuos', 'mutuo', 'relacao de mutuos', 'contas intragrupo'] },
  { codigo: 'COMBINADO', termos: ['combinado', 'combinada', 'demonstracoes combinadas', 'df combinada'] },
  { codigo: 'FLUXO_CAIXA', termos: ['fluxo de caixa', 'fluxo caixa', 'dfc', 'cash flow', 'fluxo'] },
  { codigo: 'DRE', termos: ['dre', 'demonstracao de resultado', 'demonstracao do resultado', 'resultado do exercicio'] },
  { codigo: 'BALANCO', termos: ['balanco patrimonial', 'balanco', 'bp'] },
  // DMPL/DVA vêm DEPOIS das demonstrações principais de propósito (db/migrations/0024).
  // O caso comum de "DMPL" no nome de arquivo é o PDF COMPOSTO ("Balanço
  // Patrimonial DRE, DFC, DMPL 2024.pdf" — arquivo real do dono), que pela
  // taxonomia (f0/03) é a demonstração PRINCIPAL, não a DMPL. Testando antes de
  // BALANCO/DRE, esse arquivo viraria DMPL — regressão. Aqui, só o documento
  // que é SÓ a DMPL/DVA ("09_DMPL_Metalurgica_2025.pdf") cai nestes códigos.
  { codigo: 'DMPL', termos: ['dmpl', 'mutacoes do patrimonio', 'mutacoes patrimonio', 'demonstracao das mutacoes'] },
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
  ] },
  { codigo: 'MAPA_DIVIDA', termos: ['mapa de divida', 'mapa divida', 'posicao de divida'] },
  { codigo: 'EXTRATO_BANCARIO', termos: ['extrato bancario', 'extrato'] },
  { codigo: 'AGING_AR', termos: ['aging de recebiveis', 'aging ar', 'contas a receber', 'aging de contas a receber'] },
  { codigo: 'AGING_AP', termos: ['aging de pagaveis', 'aging ap', 'contas a pagar', 'fornecedores'] },
  { codigo: 'ESTOQUE', termos: ['estoque', 'estoques'] },
  { codigo: 'CERTIDOES', termos: ['certidao', 'certidoes', 'cnd'] },
  { codigo: 'CONTINGENCIAS', termos: ['contingencia', 'contingencias', 'processos judiciais'] },
  { codigo: 'SITUACAO_FISCAL', termos: ['situacao fiscal', 'parcelamento', 'refis'] },
  { codigo: 'ORGANOGRAMA', termos: ['organograma'] },
  { codigo: 'RAZAO', termos: ['livro razao', 'razao contabil'] },
  { codigo: 'NOTAS_EXPL', termos: ['notas explicativas'] },
];
