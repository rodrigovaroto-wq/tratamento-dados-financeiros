// OS NÓS POSTGRES DOS WORKFLOWS DO n8n, extraídos como CHAMADA.
//
// Um módulo, dois leitores: `conferir-chamadas.mjs` (que confere cada chamada
// por PREPARE contra um banco) e `Supabase/conferir/gerar-conferir-chamadas.mjs`
// (que emite a mesma lista como SQL para colar no SQL Editor). Até 24/09/2026 o
// `.sql` se dizia "GERADO a partir dos nós" e não tinha gerador: 3 das 15
// consultas já diferiam do workflow (dois nós tinham ganhado `p_cnpj`), e como
// `p_cnpj` tem default a cópia velha dizia "PODE RODAR" num banco que não pode.
// Extrair num lugar só é o que impede a terceira cópia.
import { readFileSync, readdirSync } from "node:fs";
import { join } from "node:path";

/** "Não consegui conferir" — nunca "achei problema". Quem chama decide o código de saída. */
export class NaoConsegui extends Error {
  constructor(...linhas) {
    super(linhas[0]);
    this.linhas = linhas;
  }
}

/**
 * @param {string} raiz a raiz do repositório
 * @returns {{ nosPostgres: Array<{origem: string, arquivo: string, no: string, consulta: string}>,
 *             naoConferidos: Array<{origem: string, porque: string}>, nosDaFamiliaPostgres: number }}
 */
export function nosPostgresDosWorkflows(raiz) {
  const nosPostgres = [];
  const naoConferidos = [];
  let nosDaFamiliaPostgres = 0;

  let arquivosDeWorkflow;
  try {
    arquivosDeWorkflow = readdirSync(join(raiz, "N8N")).filter((f) => /^workflow.*\.json$/.test(f)).sort();
  } catch (erro) {
    throw new NaoConsegui(`NÃO CONSEGUI LER N8N/ — ${erro.message}`, "Sem os workflows não há o que conferir.");
  }

  for (const arq of arquivosDeWorkflow) {
    let wf;
    try {
      wf = JSON.parse(readFileSync(join(raiz, "N8N", arq), "utf8"));
    } catch (erro) {
      // JSON quebrado é "não consegui conferir", nunca "achei problema": o exit 1
      // manda aplicar migration, e migration não conserta JSON malformado.
      throw new NaoConsegui(`N8N/${arq} NÃO É JSON VÁLIDO — ${erro.message}`);
    }
    for (const no of wf.nodes ?? []) {
      // A FAMÍLIA INTEIRA É CONTADA, não só o tipo exato — e é a correção do achado
      // mais caro da revisão. A guarda de "extração quebrou" lá embaixo só pegava o
      // caso TOTAL (zero nó); com TRÊS nós fora, o conferidor imprimia "12 chamadas"
      // e dizia CHAMADAS OK sobre o banco na 0150 — exatamente o banco que ele existe
      // para reprovar. `n8n-nodes-base.postgresTool` (nó promovido a ferramenta de
      // agente) é uma exportação legítima que produz esse silêncio de graça.
      if (!/postgres/i.test(no.type ?? "")) continue;
      nosDaFamiliaPostgres++;

      const origem = `N8N/${arq} · nó "${no.name}"`;
      const bruta = no.parameters?.query;

      if (typeof bruta !== "string" || !bruta.trim()) {
        // Nó Postgres que não é `executeQuery` (um `insert` traz a tabela em
        // `parameters.table`) ou cuja query não é texto. Não dá para conferir por
        // `PREPARE` — e passar batido seria o silêncio de novo. Declarar é o mínimo.
        naoConferidos.push({ origem, porque: `sem 'query' em texto (operation='${no.parameters?.operation ?? "?"}')` });
        continue;
      }

      const consulta = bruta.trim().replace(/;\s*$/, "");

      // MODO EXPRESSÃO DO N8N: `=select … {{ $json.x }}`. O SQL só existe em tempo de
      // execução, então mandá-lo ao `PREPARE` produz `syntax error at or near "="` —
      // uma ACUSAÇÃO FALSA, com a receita errada em cima ("aplique as migrations").
      // A lição da v48 (20 de 27 pendências falsas) é que portão que mente é portão
      // que se aprende a ignorar. Declarar não-conferido é a resposta honesta.
      if (bruta.startsWith("=") || /\{\{/.test(consulta)) {
        naoConferidos.push({ origem, porque: "query montada por expressão do n8n — só existe em execução" });
        continue;
      }

      // MULTI-STATEMENT É RECUSADO ANTES DE CHEGAR AO BANCO. `prepare X as <consulta>`
      // com `;` no meio faz o psql executar o resto como comando próprio: a revisão
      // mediu um `update` gravando de verdade no banco apontado. A transação somente
      // leitura já barraria a escrita, mas esta trava é a que mantém verdadeira a
      // frase do cabeçalho — e ela é sobre a consulta, não sobre a sorte.
      if (consulta.includes(";")) {
        naoConferidos.push({ origem, porque: "a query tem mais de um comando (';') — recusada por segurança" });
        continue;
      }

      nosPostgres.push({ origem, arquivo: arq, no: no.name, consulta });
    }
  }
  return { nosPostgres, naoConferidos, nosDaFamiliaPostgres };
}
