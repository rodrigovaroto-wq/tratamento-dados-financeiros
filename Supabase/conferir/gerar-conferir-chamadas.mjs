#!/usr/bin/env node
// Emite `Supabase/conferir/conferir_chamadas.sql` — o conferidor de chamadas em
// SQL puro, para quem não usa terminal colar no SQL Editor do Supabase.
//
// POR QUE EXISTE (24/09/2026). O `.sql` dizia "ESTE ARQUIVO É GERADO a partir dos
// nós Postgres" e não havia gerador nem portão: 3 das 15 consultas já diferiam do
// workflow — `Registrar Documento` e `Registrar Diagnostico` tinham ganhado
// `p_cnpj`, e como `p_cnpj` tem default a cópia velha dizia "PODE RODAR" num banco
// sem ele. É o mesmo par de leitura (`nos-postgres.mjs`) do `conferir-chamadas.mjs`,
// e o CI roda este gerador sob `git diff --exit-code` e executa o `.sql` gerado
// contra o banco de teste, exigindo o veredito "PODE RODAR".
//
//   node Supabase/conferir/gerar-conferir-chamadas.mjs > Supabase/conferir/conferir_chamadas.sql
import { fileURLToPath } from "node:url";
import { nosPostgresDosWorkflows, NaoConsegui } from "../test/nos-postgres.mjs";

const CABECALHO = "-- ═══════════════════════════════════════════════════════════════════════════\n-- CONFERIDOR DE CHAMADAS — versão SQL, para colar no SQL Editor do Supabase.\n--\n-- MESMA PERGUNTA do `Supabase/test/conferir-chamadas.mjs`, sem precisar de\n-- terminal: o que o workflow do n8n chama existe NESTE banco, com estes tipos?\n-- Rode ANTES de subir documento. Leva 1 segundo e evita a rodada que morre no\n-- primeiro nó.\n--\n-- SÓ LEITURA. `PREPARE` faz o Postgres resolver nome e tipos da chamada e NÃO\n-- executa a consulta; o `deallocate` logo em seguida não deixa nada para trás.\n--\n-- POR QUE NÃO É `to_regprocedure`, que seria uma linha. Porque ele exige a\n-- assinatura EXATA, e o Postgres resolve chamada com argumento default e com\n-- cast implícito. Medido em 02/09 contra o banco completo: a versão com\n-- `to_regprocedure` acusou 6 das 15 chamadas como quebradas quando todas as 15\n-- funcionam — entre elas `fn_reconciliar_por_documento($1::uuid)`, que resolve\n-- pelo default de `p_escopo`. Portão que acusa à toa é portão que se aprende a\n-- ignorar, então ele confere a CHAMADA do jeito que o Postgres a resolveria.\n--\n-- ESTE ARQUIVO É GERADO a partir dos nós Postgres de `N8N/workflow*.json`, por\n-- `node Supabase/conferir/gerar-conferir-chamadas.mjs`, e o CI reprova se ele\n-- divergir do commitado. Não edite à mão: regere.\n-- ═══════════════════════════════════════════════════════════════════════════\n";
const LACO = "begin\n  for i in 1 .. array_length(alvos, 1) loop\n    begin\n      execute 'prepare _c' || i || ' as ' || alvos[i][2];\n      execute 'deallocate _c' || i;\n      insert into _conferir values (alvos[i][1], alvos[i][2], true, null);\n    exception when others then\n      insert into _conferir values (alvos[i][1], alvos[i][2], false, SQLERRM);\n    end;\n  end loop;\nend $conf$;\n";

const RAIZ = fileURLToPath(new URL("../..", import.meta.url));
const lit = (s) => "'" + s.replaceAll("'", "''") + "'";

/**
 * O `.sql` a partir do que `nosPostgresDosWorkflows` extraiu.
 *
 * O NÃO CONFERÍVEL ENTRA NO ARQUIVO. A primeira versão (24/09/2026) emitia só os
 * nós conferíveis e descartava `naoConferidos` em silêncio: um nó em modo
 * expressão (`=select … {{ }}`) ou com `;` sumia, e o veredito dizia "PODE RODAR
 * — as 14 chamadas" sobre um workflow de 15 — ausência apresentada como dado
 * (regras 1 e 7). Achado da revisão do PR #244. Agora cada um vira uma linha com
 * `resolve` nulo e o motivo, e o veredito diz CONFERENCIA INCOMPLETA e os lista.
 */
export function gerarSql({ nosPostgres, naoConferidos }) {
  const alvos = nosPostgres
    .map(({ arquivo, no, consulta }) => `    [${lit(`${arquivo} · ${no}`)}, ${lit(consulta)}]`)
    .join(",\n");
  const semConferir = naoConferidos
    .map(({ origem, porque }) => `insert into _conferir values (${lit(origem)}, null, null, ${lit(`NÃO CONFERIDA: ${porque}`)});\n`)
    .join("");
  return CABECALHO + `create temp table if not exists _conferir(no text, chamada text, resolve boolean, erro text);
truncate _conferir;
do $conf$
declare
  r record; i int := 0;
  alvos text[][] := array[
${alvos}
  ];
` + LACO + semConferir + `select
  case when count(*) filter (where resolve = false) > 0
       then '*** NAO RODE *** ' || count(*) filter (where resolve = false) || ' de ' || count(*) filter (where resolve is not null) || ' NAO resolvem'
       when count(*) filter (where resolve is null) > 0
       then '*** CONFERENCIA INCOMPLETA *** as ' || count(*) filter (where resolve) || ' chamadas conferidas resolvem, mas '
            || count(*) filter (where resolve is null) || ' NAO FORAM CONFERIDAS (listadas abaixo) — nao rode ate conferi-las'
       else 'PODE RODAR — as ' || count(*) || ' chamadas do n8n resolvem neste banco'
  end as veredito
from _conferir;
select no, erro from _conferir where resolve is not true order by no;
`;
}

if (process.argv[1] && fileURLToPath(import.meta.url) === process.argv[1]) {
  let extraido;
  try {
    extraido = nosPostgresDosWorkflows(RAIZ);
  } catch (erro) {
    if (erro instanceof NaoConsegui) {
      for (const l of erro.linhas) console.error(l);
      process.exit(2);
    }
    throw erro;
  }
  // Zero nó é a extração quebrada, não "nada a conferir" (regra 7): o arquivo
  // gerado diria "PODE RODAR — as 0 chamadas" sobre coisa nenhuma.
  if (extraido.nosPostgres.length === 0) {
    console.error("NÃO ACHEI NÓ POSTGRES CONFERÍVEL nos workflows — a extração quebrou; o .sql NÃO foi gerado.");
    process.exit(2);
  }
  process.stdout.write(gerarSql(extraido));
}
