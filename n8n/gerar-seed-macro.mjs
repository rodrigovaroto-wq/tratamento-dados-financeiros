// Gera `db/seed/macro_carga_inicial.sql` — a PRIMEIRA carga dos índices macro,
// buscada das mesmas APIs oficiais que o `workflow.macro.json` consulta, com os
// mesmos parsers (`lib/macro.mjs`). Rodar: node n8n/gerar-seed-macro.mjs
//
// POR QUE EXISTE. O workflow de coleta roda no RELÓGIO (dia 12, depois da
// divulgação do IPCA) e não faz carga histórica: importar o workflow não traz
// número nenhum, e ativá-lo hoje só produziria dado no próximo dia 12. As médias
// de 3/5/10 anos e as premissas de Focus do modelo, porém, são inúteis vazias —
// e é isso que o dono viu em duas rodadas seguidas do export ("os índices não
// vieram com os dados"). Este gerador resolve a partida: um arquivo SQL que
// carrega os ~11 anos de histórico e o boletim Focus mais recente de uma vez.
//
// O SEED NÃO SUBSTITUI O WORKFLOW, e a diferença importa: ele é uma FOTO
// (buscada na data em que o arquivo foi gerado, registrada no cabeçalho dele) e
// o workflow é a manutenção. Depois da carga, é o workflow que mantém a série
// viva mês a mês.
//
// Nada aqui é digitado à mão: os valores vêm das APIs, pelas mesmas funções de
// parse que a produção usa, e entram pelas mesmas RPCs
// (`fn_registrar_indice_macro`/`fn_registrar_expectativa_macro`) — que são
// idempotentes por (serie, data_ref, fonte) e por (serie, ano_ref, coletado_em).
// Rodar o seed duas vezes não duplica nada.

import { writeFileSync, mkdirSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import {
  SERIES_MACRO, INDICADORES_FOCUS,
  urlSgs, parseSgs, urlFocus, parseFocus, urlSidraIpca, parseSidraIpca,
  divergenciasEntreFontes,
} from './lib/macro.mjs';

const __dirname = dirname(fileURLToPath(import.meta.url));
const MESES = 132; // 11 anos — cobre a janela de 10 anos com folga para ano incompleto

async function buscar(url, oQue) {
  const r = await fetch(url, { headers: { accept: 'application/json' } });
  if (!r.ok) throw new Error(`${oQue}: HTTP ${r.status} em ${url}`);
  return r.json();
}

const observacoes = [];
const expectativas = [];
const resumo = [];

for (const s of SERIES_MACRO) {
  // `mesesAtras`, não `ultimos`: a chave errada era IGNORADA em silêncio (é um
  // default de desestruturação), então o seed sempre puxou o default da lib em
  // vez dos MESES declarados aqui. Coincidiam em 132 — o defeito só apareceria
  // no dia em que alguém mudasse esta constante e nada mudasse na saída.
  const obs = parseSgs(await buscar(urlSgs(s.sgs, { mesesAtras: MESES }), `SGS ${s.codigo}`), s.codigo);
  observacoes.push(...obs);
  resumo.push(`${s.codigo}: ${obs.length} observações (BCB/SGS ${s.sgs})`);
}

// IPCA pelo IBGE também: é a fonte PRIMÁRIA (o BCB espelha), e ter as duas é o
// que permite `fn_divergencias_indice_macro` conferir. Sem a segunda fonte a
// checagem existe mas nunca tem o que comparar.
const ipcaIbge = parseSidraIpca(await buscar(urlSidraIpca({ ultimos: MESES }), 'SIDRA IPCA'));
observacoes.push(...ipcaIbge);
resumo.push(`IPCA: ${ipcaIbge.length} observações (IBGE/SIDRA — contraprova)`);

const ipcaBcb = observacoes.filter((o) => o.serie === 'IPCA' && o.fonte === 'BCB/SGS');
const divergencias = divergenciasEntreFontes(ipcaBcb, ipcaIbge);

for (const f of INDICADORES_FOCUS) {
  const exp = parseFocus(await buscar(urlFocus(f.indicador), `Focus ${f.codigo}`), f.codigo);
  expectativas.push(...exp);
  resumo.push(`${f.codigo}: ${exp.length} anos de expectativa (BCB/Focus, coleta ${exp[0]?.coletado_em ?? '—'})`);
}

const geradoEm = new Date().toISOString();
const sql = `-- =============================================================================
-- CARGA INICIAL dos índices macro (db/migrations/0025)
--
-- GERADO por \`node n8n/gerar-seed-macro.mjs\` em ${geradoEm}.
-- NÃO editar à mão: regerar o arquivo pega os números atualizados na fonte.
--
-- Pré-requisito: a \`0025_indices_macro.sql\` aplicada NO MESMO banco.
-- Seguro rodar mais de uma vez: as RPCs são idempotentes por (serie, data_ref,
-- fonte) e por (serie, ano_ref, coletado_em).
--
-- FONTES (as mesmas do workflow de coleta \`n8n/workflow.macro.json\`):
--   • BCB/SGS    — séries ${SERIES_MACRO.map((s) => `${s.codigo}=${s.sgs}`).join(', ')}
--   • IBGE/SIDRA — tabela 1737 var. 63 (IPCA mensal), fonte primária do índice
--   • BCB/Focus  — Expectativas de Mercado Anuais (mediana por ano-calendário)
--
-- O QUE ENTROU:
${resumo.map((l) => `--   ${l}`).join('\n')}
--
-- Conferência das duas fontes do IPCA no momento da geração:
--   ${divergencias.length === 0
    ? 'nenhuma divergência acima de 0,01 p.p. entre BCB/SGS e IBGE/SIDRA.'
    : `${divergencias.length} mês(es) divergentes — ver \`fn_divergencias_indice_macro()\` depois de aplicar: `
      + divergencias.slice(0, 6).map((d) => `${d.data_ref} (${d.valor_a} × ${d.valor_b})`).join(', ')}
--
-- Isto é uma FOTO da data acima. A manutenção mês a mês é do workflow — ativá-lo
-- continua sendo necessário; o seed só resolve a partida (o workflow roda dia 12
-- e não faz carga histórica).
-- =============================================================================

select * from fn_registrar_indice_macro($seed$${JSON.stringify(observacoes)}$seed$::jsonb);

select fn_registrar_expectativa_macro($seed$${JSON.stringify(expectativas)}$seed$::jsonb);

-- Conferência (rode e leia a saída):
--   select * from fn_indice_macro_anual(${new Date().getFullYear() - 11});
--   select * from fn_divergencias_indice_macro();
`;

mkdirSync(join(__dirname, '..', 'db', 'seed'), { recursive: true });
const destino = join(__dirname, '..', 'db', 'seed', 'macro_carga_inicial.sql');
writeFileSync(destino, sql);
console.log(`Escrito ${destino}`);
console.log(`  ${observacoes.length} observações, ${expectativas.length} expectativas`);
console.log(`  divergências BCB × IBGE no IPCA: ${divergencias.length}`);
for (const l of resumo) console.log(`  ${l}`);
