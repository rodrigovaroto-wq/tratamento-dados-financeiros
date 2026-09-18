#!/usr/bin/env node
// O INVENTÁRIO DO PERÍMETRO — fatia 1.1 do plano F1 (irmão do `cobertura-do-lote.sql`).
//
// POR QUE ESTE ARQUIVO EXISTE. O roadmap estimava a F1 em "55%" desde 09/09/2026 sem medir contra
// o banco — a mesma classe de erro que o `MAPA_DE_EXECUCAO.md` cometeu ficando 9 dias para trás.
// Este script confere DUAS coisas, e as duas são pré-requisito para começar a F1 com número em
// vez de estimativa: (1) por caso, quantas entidades têm CNPJ e `papel_no_grupo`; (2) uma causa
// NOMEADA para cada pendência `entidade_incorreta` aberta — porque "71 pendências" não é
// diagnóstico, é contagem (regra 1: ausência de causa é ausência de dado).
//
// POR QUE A CLASSIFICAÇÃO É CÓDIGO E NÃO OLHO HUMANO. 71 descrições em prosa não cabem em uma
// leitura confiável, e a mesma pergunta ("essas duas strings são a mesma empresa?") vai se repetir
// toda vez que um mandato novo acumular pendências. `classificarCausa` é a resposta reaproveitável
// — testada com os 71 casos reais da rodada de 18/09/2026 como fixture (regra 4: fixture real,
// não inventada), e pronta para rodar de novo contra qualquer caso futuro.
//
// A CLASSIFICAÇÃO AFIRMA CAUSA, NÃO CONSERTO. Nenhuma categoria aqui funde entidade, renomeia ou
// resolve pendência — isso é a fatia 1.2 (para as duas primeiras causas, que são bugs de
// comparação) e trabalho humano pontual (para `ambigua_ja_correta` e `sem_relacao_aparente`, que
// não são bugs). Rodar este script não muda o banco: é `select`, sempre.
//
// COMO RODAR
//
//   CONFERIR_PSQL="psql 'postgresql://…'" node Supabase/test/perimetro-inventario.mjs
//
// Sem `CONFERIR_PSQL`, ele recusa como os outros scripts desta família: NÃO CONFERIDO (saída 2),
// nunca "0 pendências" — que seria ausência de medição travestida de banco limpo (regra 7).

import { execSync } from 'node:child_process';

const ALVO = process.env.CONFERIR_PSQL ?? '';

// -----------------------------------------------------------------------------------------------
// A classificação. Cada descrição de `entidade_incorreta` vem no formato:
//   Diagnóstico de conteúdo sugere entidade "A", mas o documento está registrado com "B".
// (ou a variação "registrado em … aponta"). `classificarCausa` decide POR QUE A e B divergem.
// -----------------------------------------------------------------------------------------------

export function normalizarNomeEntidade(s) {
  return s
    .normalize('NFD')
    .replace(/[̀-ͯ]/g, '') // acentos
    .toUpperCase()
    .replace(/\bLTDA\.?\b|\bS\.?A\.?\b|\bEPP\b|\bME\b/g, '') // sufixo jurídico
    .replace(/[^A-Z0-9]/g, ' ')
    .replace(/\s+/g, ' ')
    .trim();
}

function distanciaLevenshtein(a, b) {
  const dp = Array.from({ length: a.length + 1 }, () => new Array(b.length + 1).fill(0));
  for (let i = 0; i <= a.length; i++) dp[i][0] = i;
  for (let j = 0; j <= b.length; j++) dp[0][j] = j;
  for (let i = 1; i <= a.length; i++) {
    for (let j = 1; j <= b.length; j++) {
      dp[i][j] = Math.min(
        dp[i - 1][j] + 1,
        dp[i][j - 1] + 1,
        dp[i - 1][j - 1] + (a[i - 1] === b[j - 1] ? 0 : 1),
      );
    }
  }
  return dp[a.length][b.length];
}

const PADRAO_TITULO_OU_ARQUIVO =
  /^(COMPARATIVO|RELATORIO|CONTROLE|STATUS|MESES|LIQUIDO)\b|\d{4}X\d{4}/;

// A ordem importa: cada `if` é uma pergunta que só faz sentido depois que a anterior disse "não".
export function classificarCausa(descricao) {
  if (/脕|锟絀/.test(descricao)) return 'mojibake';
  if (/casa com MAIS DE UMA/.test(descricao)) return 'ambigua_ja_correta';
  if (/não editar nem resolver/.test(descricao)) return 'fixture_sonda';

  const m =
    descricao.match(/sugere entidade "([^"]+)", mas o documento está registrado (?:com|em) "([^"]+)"/) ||
    descricao.match(/registrado em "([^"]+)", mas o diagnóstico de conteúdo aponta "([^"]+)"/);
  if (!m) return 'residual';

  const [, a, b] = m;
  const na = normalizarNomeEntidade(a);
  const nb = normalizarNomeEntidade(b);

  if (PADRAO_TITULO_OU_ARQUIVO.test(na) || PADRAO_TITULO_OU_ARQUIVO.test(nb)) {
    return 'nome_de_arquivo_ou_titulo_virou_entidade';
  }
  if (na === nb) return 'normalizacao_acento_caixa_sufixo';

  const menor = Math.min(na.length, nb.length);
  if (menor >= 6 && (na.includes(nb) || nb.includes(na))) return 'prefixo_comum_truncado';

  if (menor > 8 && distanciaLevenshtein(na, nb) <= 2) return 'quase_igual_1_2_chars';

  if (menor <= 3) return 'apelido_curto_sem_mapeamento';

  const palavrasA = new Set(na.split(' ').filter((w) => w.length >= 4));
  const palavrasB = new Set(nb.split(' ').filter((w) => w.length >= 4));
  const comuns = [...palavrasA].filter((w) => palavrasB.has(w));
  if (comuns.length >= 1) return 'apelido_ou_nome_fantasia_com_palavra_em_comum';

  return 'sem_relacao_aparente_revisar_manualmente';
}

// As duas primeiras causas são BUGS DE COMPARAÇÃO — a mesma entidade, escrita de duas formas, que
// deveria ter fechado sozinha e não abriu pendência. As outras não: são gap de dado (apelido não
// mapeado, nome de arquivo virando cadastro) ou funcionamento correto (`ambigua_ja_correta`).
export const CAUSAS_SAO_BUG_DE_COMPARACAO = new Set([
  'mojibake',
  'normalizacao_acento_caixa_sufixo',
  'prefixo_comum_truncado',
  'quase_igual_1_2_chars',
]);

// -----------------------------------------------------------------------------------------------
function rodarPsql(sql) {
  const out = execSync(`${ALVO} -X -A -t -F '\t' -c ${JSON.stringify(sql)}`, {
    encoding: 'utf8',
    maxBuffer: 16 * 1024 * 1024,
  });
  return out.split('\n').filter((l) => l.length > 0);
}

function main() {
  if (!ALVO) {
    console.log(
      'NÃO CONFERIDO — `CONFERIR_PSQL` não está definida, então esta execução não perguntou nada\n' +
        'ao banco. Isto NÃO é "perímetro em dia": é ausência de medição.\n\n' +
        "  CONFERIR_PSQL=\"psql 'postgresql://usuario:SENHA@host:5432/postgres'\" \\\n" +
        '    node Supabase/test/perimetro-inventario.mjs',
    );
    process.exit(2);
  }

  const porCaso = rodarPsql(
    `select c.nome, count(*), count(*) filter (where e.cnpj is not null), ` +
      `count(*) filter (where e.papel_no_grupo is not null) ` +
      `from entidade e join caso c on c.id = e.caso_id group by 1 order by 2 desc;`,
  );

  const pendencias = rodarPsql(
    `select c.nome, p.descricao from pendencia p join caso c on c.id = p.caso_id ` +
      `where p.tipo::text = 'entidade_incorreta' and p.estado::text = 'aberta' order by c.nome;`,
  );

  console.log(`--- entidades por caso (${porCaso.length} casos) ---`);
  for (const linha of porCaso) {
    const [nome, total, comCnpj, comPapel] = linha.split('\t');
    console.log(`${total.padStart(4)} entidades · ${comCnpj.padStart(3)} c/CNPJ · ${comPapel.padStart(3)} c/papel  ${nome}`);
  }

  const contagem = new Map();
  for (const linha of pendencias) {
    const tab = linha.indexOf('\t');
    const descricao = linha.slice(tab + 1);
    const causa = classificarCausa(descricao);
    contagem.set(causa, (contagem.get(causa) ?? 0) + 1);
  }

  console.log(`\n--- ${pendencias.length} pendência(s) entidade_incorreta abertas, por causa ---`);
  const ordenado = [...contagem.entries()].sort((a, b) => b[1] - a[1]);
  let bugsDeComparacao = 0;
  for (const [causa, n] of ordenado) {
    console.log(`${String(n).padStart(3)}  ${causa}`);
    if (CAUSAS_SAO_BUG_DE_COMPARACAO.has(causa)) bugsDeComparacao += n;
  }
  console.log(`\n${bugsDeComparacao} de ${pendencias.length} são bug de comparação (candidatas à fatia 1.2).`);

  if (ordenado.some(([causa]) => causa === 'residual')) {
    console.log('\nATENÇÃO: há pendência(s) no formato "residual" — descrição fora do padrão esperado,');
    console.log('não classificada. Não é erro deste script: é sinal de que o formato da pendência mudou.');
  }
}

// Só roda ao ser chamado diretamente — importado pela suíte, `main()` não pode disparar
// `process.exit`, senão nenhum teste de `classificarCausa` conseguiria rodar sem `CONFERIR_PSQL`.
if (import.meta.url === `file://${process.argv[1]}`) {
  main();
}
