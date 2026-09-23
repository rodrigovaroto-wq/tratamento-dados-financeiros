#!/usr/bin/env node
// A SONDA CONTRA PRODUÇÃO — e o ponto que ela sozinha não cobre.
//
// POR QUE ESTE ARQUIVO EXISTE (F0, fatia 0.4). `fn_instalacao_conferir()` é a autoridade sobre o
// banco, e o CI a roda TODA passada — mas contra o banco que ele mesmo acabou de montar a partir
// das migrations. Esse banco está, por construção, sempre em dia. O banco que atende o cliente
// não: em 16/09/2026 o repositório estava na `0177` e produção na `0157`(+`0160`). Nenhum portão
// olhava para lá, e é por isso que a defasagem cresceu 20 migrations sem nada acusar.
//
// E ELA TEM UM LIMITE QUE NÃO É DEFEITO, mas que precisa estar escrito aqui, porque quem lê
// "sonda verde" conclui a coisa errada: **o catálogo da sonda mora DENTRO do banco**. Um banco
// atrasado não sabe o que lhe falta — ele responde sobre o catálogo que TEM
// (`.claude/memory/sonda-so-conhece-o-catalogo-que-o-banco-tem.md`, medido em 02/09: banco parado
// na `0150`, sonda sem acusar nada, e três nós Postgres do workflow sem resolver). A outra ponta
// é `Supabase/test/conferir-chamadas.mjs`, que pergunta o contrário: o que o CÓDIGO chama existe
// no banco? As duas juntas fecham o cerco; cada uma sozinha tem um ângulo morto.
// Por isso o workflow agendado (`.github/workflows/sonda-producao.yml`) roda AS DUAS.
//
// COMO RODAR
//
//   SONDA_PSQL="psql 'postgresql://usuario:SENHA@host:5432/postgres'" \
//     node Supabase/test/sonda-producao.mjs
//
// OS CÓDIGOS DE SAÍDA, e a distinção entre eles é a razão de ser deste script:
//
//   0  perguntei e produção não tem ausência nenhuma
//   1  perguntei e produção TEM ausência (ou nem a própria sonda existe lá)
//   2  NÃO CONSEGUI PERGUNTAR — sem configuração, ou a conexão não subiu
//
// O 2 nunca colapsa no 0. "Não rodou" e "rodou e não achou nada" têm a mesma aparência, e é o
// defeito mais caro deste projeto (regra 7) — um portão que fica verde quando não conseguiu
// perguntar é a versão automatizada dele.
//
// A URL CARREGA SENHA e NUNCA sai daqui: `erro.message` do `execSync` começa com a linha de
// comando inteira, e um relatório com ela dentro acaba colado num PR. Só o `stderr` do psql sai.
//
// O BURACO NO MEIO — o ângulo morto que o limite acima NÃO cobria, MEDIDO em 23/09/2026 (PR #238).
// O limite acima presume banco atrasado NA CAUDA, e isso o `ate_migration` denuncia. O caso real foi
// outro: duas sessões em paralelo, a da F2 aplicou 0186–0188 em 22/09 e a 0182/0183 da F1.7 ficaram
// de fora. Produção respondia "132 requisitos, 0 ausentes, cobertura até a 0188" — tudo verde — com
// DUAS migrations faltando no meio da sequência. Uma migration que nunca rodou não deixa requisito
// nenhum no catálogo, então não há o que acusar como ausente.
//
// A correção não precisa de lista nova escrita à mão: `Supabase/README.md` JÁ é a lista declarada do
// que deve ser aplicado, e a migration que não deve (a 0185, reprovada na medição) já está COMENTADA
// lá. A sonda compara produção contra essa lista: toda migration listada sem comentário, que cataloga
// requisito com o próprio número, tem de ter pelo menos um requisito no catálogo de produção.
// Derivar, nunca duplicar — o mesmo princípio do `indexar.mjs`.
import { execSync } from 'node:child_process';
import { readFileSync, existsSync } from 'node:fs';
import { join } from 'node:path';

const ALVO = process.env.SONDA_PSQL ?? '';
const RAIZ = new URL('../..', import.meta.url).pathname.replace(/\/$/, '');

const SQL = `select chave, migration, tipo, objeto, coalesce(detalhe,''), coalesce(porque,'')
  from fn_instalacao_conferir() where not presente order by 1;`;

const SQL_MIGRACOES = `select distinct migration from instalacao_requisito order by 1;`;

/**
 * As migrations que DEVERIAM estar em produção, derivadas do README: linha `supabase db execute`
 * NÃO comentada, cujo arquivo cataloga requisito com o próprio número (as anteriores ao catálogo,
 * e as que só catalogam outras, não têm como deixar rastro próprio e ficam de fora).
 */
export function migracoesEsperadas(readme, lerMigration) {
  const esperadas = [];
  for (const linha of readme.split('\n')) {
    const m = linha.match(/^supabase db execute --file Supabase\/migrations\/((\d{4})_[\w-]+\.sql)\s*$/);
    if (!m) continue;
    const texto = lerMigration(m[1]);
    if (texto === null) continue;
    if (/insert into instalacao_requisito/i.test(texto) && texto.includes(`'${m[2]}'`)) esperadas.push(m[2]);
  }
  return [...new Set(esperadas)].sort();
}

/** O que a lista declara e produção não tem no catálogo — o buraco no meio. */
export function lacunas(esperadas, noBanco) {
  const presentes = new Set(noBanco);
  return esperadas.filter((n) => !presentes.has(n));
}

export function interpretar({ configurado, status, saida, stderr, esperadas, migracoesNoBanco }) {
  if (!configurado) {
    return {
      codigo: 2,
      mensagem:
        'NÃO CONFERIDO — `SONDA_PSQL` não está definida, então esta execução não perguntou nada a\n' +
        'produção. Isto NÃO é "produção está em dia": é ausência de medição.\n\n' +
        '  SONDA_PSQL="psql \'postgresql://usuario:SENHA@host:5432/postgres\'" \\\n' +
        '    node Supabase/test/sonda-producao.mjs\n\n' +
        'No CI, a URL vem do segredo `SONDA_DB_URL` (Settings → Secrets → Actions) — o nome é o\n' +
        'que `.github/workflows/sonda-producao.yml` lê, e o teste desta suíte confere os dois.',
    };
  }
  // 3 = o servidor RESPONDEU e a resposta é um erro (a sonda não existe lá, por exemplo).
  // Qualquer outro status ≠ 0 = a pergunta não chegou.
  if (status === 3) {
    const linha =
      stderr.split('\n').find((l) => /\b(ERROR|ERRO|FEHLER|ERREUR):/.test(l))?.replace(/^.*?(?:ERROR|ERRO|FEHLER|ERREUR):\s*/, '').trim() ??
      'erro no servidor';
    return {
      codigo: 1,
      mensagem:
        `produção RESPONDEU com erro: ${linha}\n\n` +
        'Se for "function fn_instalacao_conferir does not exist", o achado é esse: produção está\n' +
        'anterior à migration que criou a sonda, e nem consegue se autodiagnosticar.',
    };
  }
  if (status !== 0) {
    return { codigo: 2, mensagem: `NÃO CONFERIDO — a pergunta não chegou ao banco:\n${stderr.trim() || '(sem stderr)'}` };
  }
  const linhas = saida.split('\n').map((l) => l.trim()).filter(Boolean);
  // O buraco no meio só é conferível quando as duas listas vieram. `perguntar()` as traz sempre que a
  // pergunta chega; se uma faltar, o relatório DIZ que o buraco não foi conferido — nunca o omite,
  // porque omitir teria a mesma cara de "conferi e não há buraco" (regra 7).
  const buracoConferido = Array.isArray(esperadas) && Array.isArray(migracoesNoBanco);
  const buraco = buracoConferido ? lacunas(esperadas, migracoesNoBanco) : [];
  const partes = [];
  if (linhas.length) {
    partes.push(`produção tem ${linhas.length} ausência(s) no catálogo:\n\n` + linhas.map((l) => `  ${l}`).join('\n'));
  }
  if (buraco.length) {
    partes.push(
      `produção NÃO TEM ${buraco.length} migration(s) que o README declara aplicáveis: ${buraco.join(', ')}\n` +
        '  Nenhum requisito delas está no catálogo de produção. Uma migration que nunca rodou não deixa\n' +
        '  requisito para acusar como ausente — por isso a contagem de ausências acima não a enxerga.',
    );
  }
  if (partes.length) {
    return {
      codigo: 1,
      mensagem: partes.join('\n\n') + '\n\nAplique as migrations pendentes e rode de novo. Migration escrita ≠ aplicada.',
    };
  }
  return {
    codigo: 0,
    mensagem: buracoConferido
      ? 'sonda OK — nenhuma ausência no catálogo, e toda migration que o README declara tem rastro em produção.'
      : 'sonda OK — nenhuma ausência no catálogo que ELA conhece. O BURACO NO MEIO NÃO FOI CONFERIDO ' +
        '(faltou a lista do README ou a do banco): uma migration que nunca rodou não aparece aqui.',
  };
}

function consultar(sql) {
  return execSync(`${ALVO} -qAt -F'|' -v ON_ERROR_STOP=1`, {
    encoding: 'utf8',
    input: `start transaction read only;\n${sql}`,
    stdio: ['pipe', 'pipe', 'pipe'],
  });
}

function perguntar() {
  if (!ALVO) return { configurado: false };
  try {
    const saida = consultar(SQL);
    const migracoesNoBanco = consultar(SQL_MIGRACOES).split('\n').map((l) => l.trim()).filter(Boolean);
    return { configurado: true, status: 0, saida, stderr: '', migracoesNoBanco };
  } catch (erro) {
    return { configurado: true, status: erro.status ?? 2, saida: '', stderr: String(erro.stderr ?? '') };
  }
}

function esperadasDoRepositorio() {
  const readme = readFileSync(join(RAIZ, 'Supabase/README.md'), 'utf8');
  return migracoesEsperadas(readme, (arquivo) => {
    const caminho = join(RAIZ, 'Supabase/migrations', arquivo);
    return existsSync(caminho) ? readFileSync(caminho, 'utf8') : null;
  });
}

if (import.meta.url === `file://${process.argv[1]}`) {
  const { codigo, mensagem } = interpretar({ ...perguntar(), esperadas: esperadasDoRepositorio() });
  (codigo === 0 ? console.log : console.error)(mensagem);
  process.exit(codigo);
}
