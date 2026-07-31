// Validação ENCADEADA: extração → banco → export, num só fluxo.
//
// Por que ela precisou existir. As três suítes do projeto são estanques:
//
//   n8n/test/*.test.mjs            libs + nós simulados. Não toca banco nem export.
//   db/test/run.sh                 funções SQL contra uma fixture escrita em Python.
//   portal/scripts/verificar-*.mts export a partir de uma fixture JSON.
//
// As duas fixtures vêm da MESMA origem (`db/test/gerar_fixture.py`, com `--json`),
// então elas concordam entre si. O que ninguém cobria é a COSTURA: nada roda o
// produtor real de campos e verifica que o que ele emite é o que o SQL grava e o
// que o export lê. Cada seam era afirmado à mão nas duas pontas — e as duas pontas
// podem estar erradas juntas.
//
// Foi essa classe de defeito que produziu os bugs mais caros deste repositório:
// a entidade que vinha vazia (o produtor não emitia o campo), a RLS que devolvia
// zero linhas (o leitor não chegava no dado), a escala que era gravada e nunca
// aplicada (o consumidor ignorava o campo). Nenhum dos três é visível olhando um
// lado só.
//
// Rodar (o socket local usa peer auth, então quem troca de usuário é o psql):
//   E2E_PSQL="sudo -u postgres psql -h /tmp -p 5432" npx tsx test/e2e/run.mts
//
// Num Postgres em que o usuário do checkout já tem acesso, basta:
//   npx tsx test/e2e/run.mts
//
// Cria e destrói o próprio banco (`tdf_e2e`), não toca em Supabase e não chama
// OpenAI nenhuma — o insumo é o book determinístico de `test-data/book-vertentes`.

import { execFileSync } from "node:child_process";
import { readFileSync } from "node:fs";
import { buildExportWorkbook } from "../../portal/src/lib/export.ts";
import type { CampoExtraido, DocumentoParaExport } from "../../portal/src/lib/types.ts";
import { avaliarCelula } from "../../portal/scripts/lib/avaliar-formula.mts";

const RAIZ = new URL("../../", import.meta.url).pathname;
const DB = process.env.E2E_DB ?? "tdf_e2e";

let ok = 0;
const falhas: string[] = [];
function checar(cond: boolean, desc: string, detalhe = "") {
  if (cond) {
    ok += 1;
    console.log(`ok    ${desc}`);
  } else {
    falhas.push(`${desc}${detalhe ? ` — ${detalhe}` : ""}`);
    console.log(`FALHOU ${desc}${detalhe ? ` — ${detalhe}` : ""}`);
  }
}

// ---------------------------------------------------------------------------
// psql como cliente. Evita dependência de driver: o portal não tem `pg`, e
// acrescentar dependência de produção para um teste seria pior que um exec.
// ---------------------------------------------------------------------------
// O comando é configurável porque o socket local do Postgres usa peer auth: o
// arnês roda como o usuário do checkout, e o cluster só aceita o usuário `postgres`.
// `npx` como `postgres` não funciona (HOME e certs diferentes), então quem troca de
// usuário é o psql, não o Node.
//   E2E_PSQL="sudo -u postgres psql" npx tsx test/e2e/run.mts
const PSQL = (process.env.E2E_PSQL ?? "psql").split(/\s+/);
function psql(sql: string, db = DB): string {
  return execFileSync(PSQL[0], [...PSQL.slice(1), "-v", "ON_ERROR_STOP=1", "-q", "-A", "-t", "-d", db, "-c", sql], {
    encoding: "utf8",
    cwd: RAIZ,
  });
}
function psqlJson<T>(sql: string): T {
  const out = psql(`select coalesce(json_agg(t), '[]'::json) from (${sql}) t`).trim();
  return JSON.parse(out) as T;
}

// ---------------------------------------------------------------------------
// FASE 1 — o produtor REAL de campos.
//
// Reconstrói a resposta da OpenAI a partir do book e roda o código do nó
// `Parse Extracao` extraído do JSON GERADO (não a lib): é o mesmo padrão de
// `n8n/test/workflow-sim.test.mjs`, e é o que garante que o que se testa é o que
// o dono importa no n8n.
// ---------------------------------------------------------------------------
const wf = JSON.parse(readFileSync(`${RAIZ}n8n/workflow.e1-ingestao.json`, "utf8")) as {
  nodes: Array<{ name: string; parameters: { jsCode: string } }>;
};
const codigoDoNo = (nome: string) => {
  const n = wf.nodes.find((x) => x.name === nome);
  if (!n) throw new Error(`nó "${nome}" não existe no workflow gerado`);
  return n.parameters.jsCode;
};
const AsyncFunction = Object.getPrototypeOf(async function () {}).constructor as new (
  ...args: string[]
) => (...a: unknown[]) => Promise<{ json: Record<string, unknown> }>;

async function rodarNo(nome: string, item: unknown, refs: Record<string, unknown> = {}) {
  const $input = { item, first: () => item, all: () => [item] };
  const $ = (ref: string) => {
    if (!(ref in refs)) throw new Error(`referência não mockada: $('${ref}')`);
    return { first: () => refs[ref], item: refs[ref] };
  };
  const fn = new AsyncFunction("$input", "$", "$env", "$json", "$itemIndex", "Buffer", codigoDoNo(nome));
  return fn.call({}, $input, $, {}, (item as { json: unknown }).json, 0, Buffer);
}

const fixture = JSON.parse(
  readFileSync(`${RAIZ}portal/scripts/fixtures/book-vertentes.json`, "utf8"),
) as { documentos: DocumentoParaExport[]; campos: CampoExtraido[] };

const gabarito = JSON.parse(
  readFileSync(`${RAIZ}test-data/book-vertentes/pdf/GABARITO.json`, "utf8"),
) as Record<string, unknown>;

// Campos do book agrupados por versão, para montar uma resposta por documento.
const camposPorVersao = new Map<string, CampoExtraido[]>();
for (const c of fixture.campos) {
  const lista = camposPorVersao.get(c.documento_versao_id) ?? [];
  lista.push(c);
  camposPorVersao.set(c.documento_versao_id, lista);
}

// A resposta da OpenAI usa chaves CURTAS (s/sc/ec/pc/k/vt/vn/op/cf) — foi uma
// otimização de custo de output. Reconstruí-las aqui é o que exercita o mapeamento
// curto→longo do nó, que é exatamente um dos seams não cobertos.
function respostaDaOpenAI(campos: CampoExtraido[]) {
  const unidade = campos.find((c) => c.unidade)?.unidade ?? null;
  return {
    json: {
      choices: [
        {
          finish_reason: "stop",
          message: {
            content: JSON.stringify({
              moeda: "BRL",
              unidade,
              diagnostico: {
                entidade: null,
                tipo_confirma: true,
                tipo_sugerido: "BALANCO",
                periodo_tipo: "anual",
                periodo_referencia: "12M25",
                legibilidade: "ok",
                nota_legibilidade: null,
                resumo: "e2e",
                justificativa: "e2e",
              },
              linhas: campos.map((c, i) => ({
                s: c.secao,
                sc: c.secao_canonica ?? "NAO_CLASSIFICAVEL",
                ec: c.entidade_coluna,
                pc: c.periodo_coluna,
                k: c.chave,
                vt: c.valor_texto,
                vn: c.valor_num,
                op: c.origem_pagina,
                cf: c.confianca ?? 0.9,
                ordem: i,
              })),
            }),
          },
        },
      ],
      usage: { prompt_tokens: 1000, completion_tokens: 500 },
    },
  };
}

console.log("== fase 1: o produtor real de campos (nó Parse Extracao)");
const camposDoProdutor = new Map<string, Array<Record<string, unknown>>>();
for (const [versaoId, campos] of camposPorVersao) {
  const req = { json: { documento_versao_id: versaoId, tipo: "BALANCO", openai_body: {} } };
  const out = await rodarNo("Parse Extracao", respostaDaOpenAI(campos), { "Montar Req Extracao": req });
  camposDoProdutor.set(versaoId, out.json.campos as Array<Record<string, unknown>>);
}

const totalProduzido = [...camposDoProdutor.values()].reduce((s, v) => s + v.length, 0);
checar(
  totalProduzido === fixture.campos.length,
  "o nó real produz o mesmo número de linhas que a fixture afirma",
  `nó=${totalProduzido} fixture=${fixture.campos.length}`,
);

// A COSTURA propriamente dita: o vocabulário de campos que o produtor emite tem de
// ser o que o banco grava e o export lê. Se o nó parar de emitir `secao_canonica`
// (ou passar a chamá-lo de outra coisa), NENHUMA das três suítes atuais percebe —
// a fixture continuaria afirmando o campo dos dois lados.
const CAMPOS_DO_CONTRATO = [
  "ordem", "secao", "secao_canonica", "entidade_coluna", "periodo_coluna",
  "chave", "valor_texto", "valor_num", "unidade", "confianca", "origem_pagina",
];
{
  const umaLinha = [...camposDoProdutor.values()][0][0];
  const faltando = CAMPOS_DO_CONTRATO.filter((k) => !(k in umaLinha));
  checar(faltando.length === 0, "o produtor emite todo o vocabulário que o banco grava", `faltando: ${faltando.join(", ")}`);
}

// ---------------------------------------------------------------------------
// FASE 2 — o banco REAL, pelas funções REAIS.
// ---------------------------------------------------------------------------
console.log("\n== fase 2: gravar pelas funções reais do Postgres");
psql(`drop database if exists ${DB}`, "postgres");
psql(`create database ${DB}`, "postgres");
// Bootstrap do que o Supabase provê por padrão e as migrations assumem. É o MESMO
// de `db/test/run.sh` — inclusive `storage.buckets`, sem o qual a 0003 não aplica,
// e o GRANT default de tabela, que a 0028 mostrou ser indispensável para um defeito
// de AUTORIZAÇÃO ser sequer visível num teste local. Mantê-los idênticos importa:
// dois bootstraps diferentes produziriam duas verdades diferentes sobre o schema.
psql(`
  do $$ begin
    if not exists (select 1 from pg_roles where rolname = 'anon') then create role anon nologin; end if;
    if not exists (select 1 from pg_roles where rolname = 'authenticated') then create role authenticated nologin; end if;
    if not exists (select 1 from pg_roles where rolname = 'service_role') then create role service_role nologin; end if;
  end $$;
  create schema if not exists storage;
  create table if not exists storage.buckets(id text primary key, name text, public boolean default false);
  create table if not exists storage.objects(id uuid default gen_random_uuid() primary key,
    bucket_id text, name text, owner uuid);
  alter table storage.objects enable row level security;
  grant usage on schema public to anon, authenticated, service_role;
  alter default privileges in schema public grant all on tables to anon, authenticated, service_role;
  alter default privileges in schema public grant all on sequences to anon, authenticated, service_role;
`);
for (const arquivo of execFileSync("bash", ["-c", "ls db/migrations/*.sql"], { encoding: "utf8", cwd: RAIZ })
  .trim()
  .split("\n")) {
  execFileSync(PSQL[0], [...PSQL.slice(1), "-v", "ON_ERROR_STOP=1", "-q", "-d", DB, "-f", arquivo], { cwd: RAIZ, stdio: "pipe" });
}
console.log("   migrations aplicadas");

const casoId = psql(`insert into caso (nome) values ('e2e book vertentes') returning id`).trim();

// Registra cada documento pela função de produção e grava os campos que o NÓ
// produziu (não os da fixture) — é isso que fecha a costura produtor→banco.
const versaoNova = new Map<string, string>();
for (const doc of fixture.documentos) {
  const versaoOriginal = doc.documento_versao?.[0];
  if (!versaoOriginal) continue;
  const ent = (doc.entidade?.razao_social ?? "").replace(/'/g, "''");
  const per = doc.periodo;
  const r = psql(`select fn_registrar_documento(
    '${casoId}', ${ent ? `'${ent}'` : "null"},
    ${per ? `'${per.tipo}'` : "null"}, ${per ? `'${per.referencia}'` : "null"},
    ${doc.tipo_taxonomia ? `'${doc.tipo_taxonomia}'` : "null"}, 0.9, 'nome_arquivo',
    'supabase_storage', 'b/${versaoOriginal.id}.pdf',
    '${(versaoOriginal.nome_original ?? "x.pdf").replace(/'/g, "''")}',
    null, 'HASH-E2E-${versaoOriginal.id}', 'ok')::text`).trim();
  const novaVersao = JSON.parse(r).documento_versao_id as string;
  versaoNova.set(versaoOriginal.id, novaVersao);

  const campos = camposDoProdutor.get(versaoOriginal.id) ?? [];
  const json = JSON.stringify(campos).replace(/'/g, "''");
  psql(`select fn_registrar_campos_extraidos('${novaVersao}', '${json}'::jsonb, 'N0', null)`);
}
psql(`select fn_recomputar_completude('${casoId}')`);

const nLinhas = Number(psql(`select count(*) from campo_extraido ce
  join documento_versao dv on dv.id = ce.documento_versao_id
  join documento d on d.id = dv.documento_id where d.caso_id = '${casoId}'`).trim());
checar(nLinhas === fixture.campos.length, "o banco gravou todas as linhas que o produtor emitiu", `banco=${nLinhas}`);

// O contrato do fixture: extração FIEL não abre pendência de reconciliação. É o que
// `gerar_fixture.py` documenta como cenário ("o arquivo foi 100% extraído").
const pendencias = psqlJson<Array<{ tipo: string; descricao: string }>>(
  `select tipo, descricao from pendencia where caso_id = '${casoId}' and estado <> 'resolvida'`,
);
const reconc = pendencias.filter((p) => p.tipo.startsWith("reconciliacao"));
checar(
  reconc.length === 0,
  "extração fiel não abre pendência de reconciliação (contrato do fixture)",
  reconc.map((p) => p.descricao?.slice(0, 100)).join(" | "),
);

// ---------------------------------------------------------------------------
// FASE 3 — ler de volta como o portal lê, e montar o export.
// ---------------------------------------------------------------------------
console.log("\n== fase 3: ler como o portal lê e montar o export");
const documentos = psqlJson<DocumentoParaExport[]>(`
  select d.id, d.tipo_taxonomia, d.status::text as status,
         json_build_object('razao_social', e.razao_social) as entidade,
         json_build_object('tipo', p.tipo, 'referencia', p.referencia) as periodo,
         (select json_agg(json_build_object('id', dv.id, 'n_versao', dv.n_versao, 'nome_original', dv.nome_original)
                          order by dv.n_versao)
            from documento_versao dv where dv.documento_id = d.id) as documento_versao
  from documento d
  left join entidade e on e.id = d.entidade_id
  left join periodo  p on p.id = d.periodo_id
  where d.caso_id = '${casoId}'
`);
const campos = psqlJson<CampoExtraido[]>(`
  select ce.id, ce.documento_versao_id, ce.secao, ce.secao_canonica, ce.entidade_coluna,
         ce.periodo_coluna, ce.chave, ce.valor_texto, ce.valor_num, ce.unidade, ce.confianca,
         ce.origem_pagina, ce.ordem, ce.status_aceite::text as status_aceite, ce.aceito_por,
         ce.aceito_em
  from campo_extraido ce
  join documento_versao dv on dv.id = ce.documento_versao_id
  join documento d on d.id = dv.documento_id
  where d.caso_id = '${casoId}'
  order by ce.ordem nulls last
`);

checar(documentos.length === fixture.documentos.length, "o portal lê todos os documentos", `leu ${documentos.length}`);
checar(campos.length === fixture.campos.length, "o portal lê todas as linhas", `leu ${campos.length}`);

const wb = buildExportWorkbook({
  caso: { nome: "e2e book vertentes", produto: "reestruturacao" },
  documentos,
  campos,
  agora: new Date("2026-07-31T12:00:00Z"),
});

const abas = wb.worksheets.map((w) => w.name);
for (const obrigatoria of ["Resumo", "Balanço", "DRE", "Modelagem"]) {
  checar(abas.includes(obrigatoria), `a aba "${obrigatoria}" existe no book gerado ponta a ponta`);
}

// ---------------------------------------------------------------------------
// FASE 4 — conferir contra o GABARITO do book.
// ---------------------------------------------------------------------------
console.log("\n== fase 4: conferir contra o gabarito determinístico do book");
const resumo = wb.getWorksheet("Resumo")!;
const valorResumo = (rot: string) => {
  for (let r = 1; r <= resumo.rowCount; r++) {
    if (String(resumo.getRow(r).getCell(1).value ?? "") === rot) return String(resumo.getRow(r).getCell(2).value ?? "");
  }
  return "";
};
checar(
  valorResumo("Linhas totais extraídas") === String(fixture.campos.length),
  "o Resumo anuncia o mesmo total que o banco tem",
  valorResumo("Linhas totais extraídas"),
);
// A escala do book Vertentes é milhar (as demonstrações) — a fatia 3 fez o export
// declarar isso, e aqui a declaração é conferida ponta a ponta.
checar(/R\$ mil/.test(valorResumo("Escala dos valores")), "a escala declarada é a do book", valorResumo("Escala dos valores"));

// Números do gabarito. Só os que o gabarito expõe como escalares — o objetivo aqui
// é provar que a CADEIA preserva o número, não reauditar o export (que já tem 146
// invariantes próprios).
// Confere os SUBTOTAIS NOMEADOS que o gabarito publica para a DRE da Metalúrgica.
// São o teste certo para a cadeia: cada um é um número que o book calcula a partir
// de várias linhas, então bater com ele prova que produtor → banco → export não
// perdeu nem deslocou nenhuma delas.
//
// O que NÃO se confere aqui, e por quê: `gabarito.receita_bruta_2025` (138.400) não
// existe como subtotal no export. A seção agrupa receita bruta E deduções sob
// "Receita Bruta e Deduções", então o subtotal dela é a receita LÍQUIDA. As três
// contas de receita aparecem individualmente e somam 138.400, mas não há linha de
// "Receita Bruta". É escolha de apresentação, não defeito — e fica registrada aqui
// porque foi o que meu primeiro assert cobrou por engano.
{
  const dre = wb.getWorksheet("DRE");
  const subtotais = (gabarito as { dre_metalurgica_2025?: Record<string, number> }).dre_metalurgica_2025 ?? {};
  // O export emite FÓRMULA, não valor: ler `cell.value` cru devolveria
  // `{formula: "SUM(...)"}` e o assert nasceria vazio (aconteceu na 1ª rodada).
  // `avaliarCelula` é o mesmo avaliador dos 146 invariantes do export.
  const valoresResolvidos: number[] = [];
  if (dre) {
    for (let r = 1; r <= dre.rowCount; r++) {
      for (const col of ["B", "C", "D", "E", "F", "G", "H"]) {
        const v = avaliarCelula(dre, col, r);
        if (typeof v === "number") valoresResolvidos.push(v);
      }
    }
  }
  for (const [nome, esperado] of Object.entries(subtotais)) {
    const achou = valoresResolvidos.some((v) => Math.abs(v - esperado) < 1);
    const perto = valoresResolvidos
      .slice()
      .sort((a, b) => Math.abs(a - esperado) - Math.abs(b - esperado))[0];
    checar(
      achou,
      `o subtotal "${nome}" do gabarito (${esperado}) sobreviveu à cadeia produtor→banco→export`,
      `mais próximo: ${perto}`,
    );
  }
  checar(Object.keys(subtotais).length >= 3, "o gabarito publica subtotais suficientes para valer como conferência");
}

psql(`drop database if exists ${DB}`, "postgres");

console.log(`\n${ok} verificações OK / ${falhas.length} falhas`);
for (const f of falhas) console.log("  FALHOU:", f);
process.exit(falhas.length ? 1 : 0);
