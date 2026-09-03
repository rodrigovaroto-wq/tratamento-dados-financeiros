/**
 * Verificação do Kit Básico satisfeito por ESTRUTURA (Supabase/migrations/0157)
 * (roda com `./node_modules/.bin/tsx scripts/verificar-kit-basico.mts`).
 *
 * O DEFEITO, medido no lote real 7377 (mandato "teste Canastra", 02/09): dois
 * documentos COMBINADO (8 empresas na planilha, confiança 1,0) foram
 * rotulados BALANCO pelo classificador. A 0157 fez `fn_recomputar_completude`
 * passo (1) parar de perguntar só ao rótulo — `fn_documento_serve_como`
 * também aceita, SÓ para o código COMBINADO, um documento estruturalmente
 * combinado (`fn_documento_de_varias_empresas`, 0155). A pendência
 * `item_faltante: COMBINADO` se resolve sozinha e o Portão 1 abre
 * (`portao1_ok = true`).
 *
 * A TELA (`casos/[id]/page.tsx`) tinha a SUA PRÓPRIA implementação da regra
 * antiga — `tipo_taxonomia === codigo` — e por isso continuava desenhando
 * COMBINADO em cinza, "não recebido", com o tile de topo em 7/8 e `detalhe`
 * nulo, mesmo com o Portão 1 já aberto. Duas telas da MESMA verdade
 * discordando, sem nenhum sinal de erro: é a lente central deste projeto.
 *
 * O invariante que este arquivo prova, em COMPORTAMENTO — nunca em mecanismo
 * (nunca reimplementa `fn_documento_de_varias_empresas` aqui; o "banco" do
 * teste é um dublê que só devolve o que o SQL devolveria, pelo contrato
 * documento×tipo):
 *
 *  1. Um documento estruturalmente COMBINADO, rotulado BALANCO, faz o item
 *     COMBINADO do Kit Básico aparecer ATENDIDO na tela — a mesma resposta
 *     que abriu o Portão 1. Sem a correção, este assert falha: a tela
 *     continua achando que falta.
 *  2. Um documento de UMA empresa só, rotulado BALANCO, NÃO atende o item
 *     COMBINADO — a exceção não é "documento chegou", é "documento serve".
 *  3. O caminho comum (rótulo bate) não faz NENHUMA chamada ao banco — a
 *     correção não pode trocar uma tela rápida por uma tela lenta para o caso
 *     que já funcionava.
 *  4. Um banco sem a 0157 (a função responde erro) faz a tela voltar ao
 *     comportamento de ANTES da 0157 — só o rótulo conta — nunca inventa
 *     "atendido" por conta própria.
 */

import { itensDoKitBasicoAtendidos, type ServicoDocumentoServeComo } from "../src/lib/kit-basico.ts";
import type { Documento, TaxonomiaTipoDocumento } from "../src/lib/types.ts";

let falhas = 0;
let passou = 0;

// O Sonar cobra `typescript:S2301` nesta assinatura ("não decida ação por
// parâmetro booleano"). Fica como está DE PROPÓSITO: é a mesma assinatura,
// caractere por caractere, de `verificar-premissas-do-realizado.mts:37`, e
// partir um helper de assert em dois métodos deixaria cada teste daqui menos
// legível para satisfazer uma regra escrita para código de produção.
function ok(cond: boolean, nome: string, detalhe?: string) {
  if (cond) {
    passou += 1;
    console.log(`  ok    ${nome}`);
  } else {
    falhas += 1;
    const sufixo = detalhe ? " — " + detalhe : "";
    console.error(`  FALHOU: ${nome}${sufixo}`);
  }
}

const kitBasico: Pick<TaxonomiaTipoDocumento, "codigo">[] = [
  { codigo: "BALANCO" },
  { codigo: "DRE" },
  { codigo: "COMBINADO" },
];

function documento(id: string, tipo_taxonomia: string | null): Pick<Documento, "id" | "tipo_taxonomia"> {
  return { id, tipo_taxonomia };
}

// O "banco" do teste: um dublê que responde exatamente o que
// `fn_documento_serve_como` responderia, pelo CONTRATO (documento × tipo) —
// nunca reimplementa `fn_documento_de_varias_empresas` em TypeScript. Cada
// entrada é um fato medido do lote 7377, não uma regra derivada.
function bancoComEstrutura(estruturais: Set<string>): ServicoDocumentoServeComo {
  return async (documentoId, tipoTaxonomia) => {
    if (tipoTaxonomia === "COMBINADO" && estruturais.has(documentoId)) return true;
    return false;
  };
}

const bancoSemChamadaEsperada: ServicoDocumentoServeComo = async () => {
  throw new Error("o rótulo já resolvia — a chamada ao banco não deveria ter acontecido");
};

const bancoSem0157: ServicoDocumentoServeComo = async () => {
  // `page.tsx` trata erro de RPC como "não sei" — nunca "sim" por invenção.
  // O dublê aqui já representa esse tratamento (o `error` virou `false` antes
  // de chegar à função), então simular apenas devolve `false`.
  return false;
};

// SEM `async function principal()` embrulhando: `.mts` é módulo ESM e aceita
// top-level await. Os irmãos (verificar-export, verificar-transcricao) também
// rodam no topo — e o Sonar cobra isto em typescript:S7785.
console.log("--- 1. documento estruturalmente COMBINADO, rotulado BALANCO: item aparece atendido ---");
{
  const documentos = [
    documento("doc-13", "BALANCO"), // 13_Balanco_COMBINADO_Grupo_Canastra_2025.pdf, 8 empresas, medido no 7377
    documento("doc-14", "BALANCO"), // 14_Balanco_COMBINADO_Grupo_Canastra_2024.pdf, 8 empresas
  ];
  const banco = bancoComEstrutura(new Set(["doc-13", "doc-14"]));
  const atendidos = await itensDoKitBasicoAtendidos(kitBasico, documentos, banco);
  ok(atendidos.has("COMBINADO"),
    "COMBINADO aparece atendido quando um documento é estruturalmente combinado");
  ok(!atendidos.has("DRE"), "DRE continua faltante — nada nesta rodada satisfaz DRE");
}

console.log("--- 2. o MESMO rótulo, mas UMA empresa só nas colunas: item continua faltante ---");
{
  const documentos = [documento("doc-alfa", "BALANCO")]; // uma empresa: fn_documento_de_varias_empresas = false
  const banco = bancoComEstrutura(new Set()); // nenhum documento é estrutural
  const atendidos = await itensDoKitBasicoAtendidos(kitBasico, documentos, banco);
  ok(!atendidos.has("COMBINADO"),
    "documento de uma empresa só NÃO satisfaz COMBINADO — a exceção é de estrutura, não de chegada");
}

console.log("--- 3. rótulo bate: zero chamada ao banco (o caminho comum não fica mais lento) ---");
{
  // SÓ os dois itens que o rótulo já resolve — DRE ficaria de fora do kit
  // real e chamaria o dublê que lança, o que provaria outra coisa.
  const kitResolvidoPeloRotulo: Pick<TaxonomiaTipoDocumento, "codigo">[] = [
    { codigo: "BALANCO" },
    { codigo: "COMBINADO" },
  ];
  const documentos = [documento("doc-c1", "COMBINADO"), documento("doc-b1", "BALANCO")];
  const atendidos = await itensDoKitBasicoAtendidos(
    kitResolvidoPeloRotulo, documentos, bancoSemChamadaEsperada,
  );
  ok(atendidos.has("COMBINADO") && atendidos.has("BALANCO"),
    "os dois itens já resolvidos pelo rótulo aparecem atendidos sem perguntar ao banco");
}

console.log("--- 4. banco sem a 0157 (RPC devolve erro, tratado como `false` por page.tsx) ---");
{
  const documentos = [documento("doc-13", "BALANCO")];
  const atendidos = await itensDoKitBasicoAtendidos(kitBasico, documentos, bancoSem0157);
  ok(!atendidos.has("COMBINADO"),
    "sem a 0157 aplicada, COMBINADO continua faltante — o mesmo comportamento de ANTES da migration, "
    + "nunca 'atendido' inventado pelo portal");
}

console.log(`\n${passou} asserts passaram, ${falhas} falharam`);
if (falhas > 0) process.exit(1);
console.log("KIT BÁSICO OK — a tela pergunta ao banco, nunca rederiva a regra do COMBINADO estrutural");
