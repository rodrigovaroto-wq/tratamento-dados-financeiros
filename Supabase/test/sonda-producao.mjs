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
import { execSync } from 'node:child_process';

const ALVO = process.env.SONDA_PSQL ?? '';

const SQL = `select chave, migration, tipo, objeto, coalesce(detalhe,''), coalesce(porque,'')
  from fn_instalacao_conferir() where not presente order by 1;`;

export function interpretar({ configurado, status, saida, stderr }) {
  if (!configurado) {
    return {
      codigo: 2,
      mensagem:
        'NÃO CONFERIDO — `SONDA_PSQL` não está definida, então esta execução não perguntou nada a\n' +
        'produção. Isto NÃO é "produção está em dia": é ausência de medição.\n\n' +
        '  SONDA_PSQL="psql \'postgresql://usuario:SENHA@host:5432/postgres\'" \\\n' +
        '    node Supabase/test/sonda-producao.mjs\n\n' +
        'No CI, a URL vem do segredo `SONDA_PSQL_URL` (Settings → Secrets → Actions).',
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
  if (linhas.length === 0) {
    return { codigo: 0, mensagem: 'sonda OK — produção não tem nenhuma ausência no catálogo que ELA conhece.' };
  }
  return {
    codigo: 1,
    mensagem:
      `produção tem ${linhas.length} ausência(s) no catálogo:\n\n` +
      linhas.map((l) => `  ${l}`).join('\n') +
      '\n\nAplique as migrations pendentes EM ORDEM e rode de novo. Migration escrita ≠ aplicada.',
  };
}

function perguntar() {
  if (!ALVO) return { configurado: false };
  try {
    const saida = execSync(`${ALVO} -qAt -F'|' -v ON_ERROR_STOP=1`, {
      encoding: 'utf8',
      input: `start transaction read only;\n${SQL}`,
      stdio: ['pipe', 'pipe', 'pipe'],
    });
    return { configurado: true, status: 0, saida, stderr: '' };
  } catch (erro) {
    return { configurado: true, status: erro.status ?? 2, saida: '', stderr: String(erro.stderr ?? '') };
  }
}

if (import.meta.url === `file://${process.argv[1]}`) {
  const { codigo, mensagem } = interpretar(perguntar());
  (codigo === 0 ? console.log : console.error)(mensagem);
  process.exit(codigo);
}
