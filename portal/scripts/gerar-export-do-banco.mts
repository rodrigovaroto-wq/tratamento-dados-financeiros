// GERA O .XLSX DO EXPORT A PARTIR DE UM POSTGRES LOCAL — sem Supabase, sem rede,
// sem Vercel e sem gastar um token.
//
// POR QUE EXISTE. O export completo só podia ser exercitado em produção: a rota
// `/casos/[id]/export` depende do cliente Supabase, e um defeito nela aparecia
// como HTTP 500 numa aba do navegador, com o stack trace preso no log da Vercel.
// Foi assim que a âncora duplicada de `Obrigações Tributárias` (PR #100) chegou
// ao dono: uma página em branco. Com este script o mesmo defeito aparece como
// stack trace no terminal, em dois segundos.
//
// O QUE ELE REPLICA: exatamente as consultas da rota, na mesma ordem, montando o
// mesmo `ConfigModelagem` e a mesma `EntradaModeloInstitucional`, e chamando o
// MESMO `buildExportWorkbook`. Se este script gera e a rota não, a diferença é de
// AMBIENTE (RLS, permissão, timeout), não de lógica de planilha.
//
// COMO USAR:
//
//   # 1. banco local com as migrations e a fixture do caso real
//   TEST_DB=tdf_v35 PGDATABASE=postgres db/test/run.sh
//   psql -d tdf_v35 -f db/test/fixture_modelagem_v35.sql        # devolve o caso_id
//   # 2. configurar a modelagem (troque o v_caso no topo do arquivo)
//   psql -d tdf_v35 -f db/roteiro_modelagem_v35.sql
//   # 3. gerar o arquivo
//   DB=tdf_v35 ./portal/node_modules/.bin/tsx portal/scripts/gerar-export-do-banco.mts <caso_id> /tmp/saida.xlsx
//
// A data é FIXA (2026-08-05), como em todo gerador deste repositório: `new Date()`
// aqui faria o arquivo mudar sozinho e um diff de bytes acusar mudança onde não
// houve.
import { execFileSync } from "node:child_process";
import { buildExportWorkbook, type DocumentoParaExport, type ConfigModelagem } from "../src/lib/export.ts";
import type { EntradaModeloInstitucional, LinhaModelo } from "../src/lib/modelo-institucional.ts";
import type { CampoExtraido } from "../src/lib/types.ts";
import { casarVinculosComLinhas } from "../src/lib/modelagem-linha.ts";

const DB = process.env.DB ?? "tdf_v35";
const CASO = process.argv[2];
if (!CASO) throw new Error("uso: repro-export.mts <caso_id>");

function q<T>(sql: string): T[] {
  const out = execFileSync("psql", ["-d", DB, "-tAc",
    `select coalesce(json_agg(t), '[]'::json)::text from (${sql}) t`], { encoding: "utf8" });
  return JSON.parse(out.trim()) as T[];
}

const caso = q<{ id: string; nome: string; produto: string }>(
  `select id, nome, produto from caso where id = '${CASO}'`)[0];

const documentos = q<DocumentoParaExport>(`
  select d.id, d.tipo_taxonomia,
         json_build_object('razao_social', e.razao_social) as entidade,
         json_build_object('tipo', p.tipo, 'referencia', p.referencia) as periodo,
         (select coalesce(json_agg(json_build_object('id', dv.id, 'nome_original', dv.nome_original,
                                                     'n_versao', dv.n_versao)), '[]'::json)
            from documento_versao dv where dv.documento_id = d.id) as documento_versao
  from documento d
  left join entidade e on e.id = d.entidade_id
  left join periodo  p on p.id = d.periodo_id
  where d.caso_id = '${CASO}'`);

const versaoIds = documentos.flatMap((d) => (d.documento_versao ?? []).map((v) => v.id));
const campos = versaoIds.length ? q<CampoExtraido>(`
  select ce.id, ce.documento_versao_id, ce.secao, ce.secao_canonica, ce.entidade_coluna,
         ce.periodo_coluna, ce.chave, ce.valor_texto, ce.valor_num, ce.unidade, ce.confianca,
         ce.origem_pagina, ce.ordem, ce.status_aceite, ce.aceito_por, ce.aceito_em
  from campo_extraido ce
  where ce.documento_versao_id in (${versaoIds.map((v) => `'${v}'`).join(",")})
  order by ce.documento_versao_id, ce.ordem nulls last`) : [];

const par = q<{ entidade: string | null; ultimo_exercicio_real: number | null;
  anos_projetados: number; setor: string | null }>(
  `select entidade, ultimo_exercicio_real, anos_projetados, setor
   from caso_modelagem where caso_id = '${CASO}'`)[0] ?? null;

const premissas = q<{ codigo: string; nome: string; formula: string; unidade: string | null;
  natureza: string; origem: string | null; valores: Record<string, number> }>(`
  select cp.premissa_codigo as codigo, pc.nome, pc.formula::text as formula, pc.unidade,
         pc.natureza::text as natureza, cp.origem, cp.valores
  from caso_premissa cp join premissa_catalogo pc on pc.codigo = cp.premissa_codigo
  where cp.caso_id = '${CASO}' and cp.ativo`);

const vinculos = q<{ rotulo_norm: string; secao_canonica: string | null;
  premissa_codigo: string | null; sazonalidade_codigo: string | null }>(
  `select rotulo_norm, secao_canonica, premissa_codigo, sazonalidade_codigo
   from caso_linha_premissa where caso_id = '${CASO}'`);

const linhasRpc = q<{ secao_canonica: string | null; chave: string; rotulo_norm: string;
  valor_ultimo: number | null; papel: LinhaModelo["papel"]; unidade: string | null;
  moeda: string | null; documentos: string[] | null }>(
  `select * from fn_linhas_para_modelagem('${CASO}')`);

const curva = q<{ mes: number; fracao: number }>(
  `select mes, fracao from fn_sazonalidade_do_caso('${CASO}') order by mes`)
  .map((x) => Number(x.fracao));

const modelagemConfig: ConfigModelagem = {
  entidade: par?.entidade ?? null,
  sazonalidade: curva.length === 12 ? curva : undefined,
  ultimoExercicioReal: par?.ultimo_exercicio_real ?? null,
  anosProjetados: par?.anos_projetados ?? 5,
  premissas,
  linhas: casarVinculosComLinhas(vinculos, linhasRpc),
};

let modeloInstitucional: EntradaModeloInstitucional | undefined;
const entidadeModelada = par?.entidade?.trim() || null;
const ultimoReal = par?.ultimo_exercicio_real ?? null;
if (entidadeModelada && ultimoReal) {
  const valores = q<{ rotulo_norm: string; ano: number; valor: number }>(
    `select rotulo_norm, ano, valor from fn_valores_por_ano('${CASO}', '${entidadeModelada.replace(/'/g, "''")}')`);
  const anosHistoricos = [...new Set(valores.map((v) => v.ano))]
    .filter((a) => a <= ultimoReal).sort((a, b) => a - b);
  const nProj = par?.anos_projetados ?? 5;
  const anosProjetados = Array.from({ length: nProj }, (_, i) => ultimoReal + 1 + i);
  const porRotulo = new Map<string, Record<string, number>>();
  for (const v of valores) {
    if (!anosHistoricos.includes(v.ano)) continue;
    if (!porRotulo.has(v.rotulo_norm)) porRotulo.set(v.rotulo_norm, {});
    porRotulo.get(v.rotulo_norm)![String(v.ano)] = Number(v.valor);
  }
  const linhasModelo: LinhaModelo[] = linhasRpc.map((l) => ({
    secao_canonica: l.secao_canonica, chave: l.chave, rotulo_norm: l.rotulo_norm,
    papel: l.papel, unidade: l.unidade, moeda: l.moeda, documentos: l.documentos,
    valores: porRotulo.get(l.rotulo_norm) ?? {},
  }));
  const contagem = new Map<string, number>();
  for (const l of linhasModelo) if (l.unidade) contagem.set(l.unidade, (contagem.get(l.unidade) ?? 0) + 1);
  const unidadeDominante = [...contagem.entries()].sort((a, b) => b[1] - a[1])[0]?.[0];
  modeloInstitucional = {
    caso: { nome: caso.nome, produto: caso.produto },
    agora: new Date("2026-08-05T12:00:00Z"),
    entidade: entidadeModelada,
    setor: par?.setor ?? null,
    anosHistoricos, anosProjetados,
    stressPct: 0.2, caixaMinimo: 0, aliquotaTributos: 0.34,
    linhas: linhasModelo,
    premissas,
    vinculos: vinculos.map((v) => ({
      rotulo_norm: v.rotulo_norm, premissa_codigo: v.premissa_codigo,
      sazonalidade_codigo: v.sazonalidade_codigo,
    })),
    macro: [],
    unidade: unidadeDominante === "milhar" ? "R$ mil"
      : unidadeDominante === "unidade" ? "R$" : (unidadeDominante ?? "R$"),
  };
}

console.log(`caso=${caso.nome} · documentos=${documentos.length} · campos=${campos.length}`
  + ` · premissas=${premissas.length} · vínculos=${vinculos.length}`
  + ` · linhas modelo=${linhasRpc.length} · curva=${curva.length}`
  + ` · modeloInstitucional=${modeloInstitucional ? "SIM" : "não"}`);

const wb = buildExportWorkbook({
  caso, documentos, campos, modo: "completo", modelagemConfig, modeloInstitucional,
});
const saida = process.argv[3] ?? "/tmp/v35-completo.xlsx";
await wb.xlsx.writeFile(saida);
console.log(`OK — escrito ${saida}`);
console.log(`abas: ${wb.worksheets.map((w) => w.name).join(" · ")}`);
