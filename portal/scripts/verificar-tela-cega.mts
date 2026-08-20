/**
 * A TELA CEGA NÃO VAZA A RESPOSTA DA MÁQUINA.
 *
 * Rodar com `npx tsx portal/scripts/verificar-tela-cega.mts`.
 *
 * POR QUE ESTA SUÍTE EXISTE, e por que ela é de FONTE e não de comportamento. A
 * rotulagem cega (`0130`) é a propriedade mais frágil deste sistema e a única cujo
 * defeito não produz sintoma nenhum: se a tela de rotulagem passar a mostrar o que
 * a extração leu, tudo continua funcionando — a página renderiza, os rótulos são
 * gravados, as cinco métricas do `f0/06` são calculadas, o painel mostra números
 * bonitos. Só que os números param de medir alguma coisa, porque quem rotula
 * passou a conferir em vez de julgar, e conferência confirma o que é plausível. A
 * concordância sobe sem nada ter melhorado e o dial sobe com ela: o sistema se
 * aprovando.
 *
 * Nenhum teste de comportamento pega isso — o comportamento fica CORRETO. O que
 * muda é o que a página pede ao banco. Então o teste olha para lá: extrai as
 * colunas que a tela seleciona e os RPCs que ela chama, e reprova se aparecer
 * qualquer coisa que responda ao que o rótulo tem de julgar.
 *
 * O QUE É PROIBIDO, e por quê, um a um:
 *   valor_num / valor_texto  o número que a extração leu — a medição inteira
 *   tipo_taxonomia           o palpite de tipo (métrica 1 do f0/06)
 *   razao_social / entidade  a entidade extraída (métrica 2)
 *   periodo / referencia     o período extraído (métrica 2)
 *   resumo / justificativa   O VAZAMENTO MAIS FÁCIL DE NÃO NOTAR: é prosa livre da
 *                            IA, e um resumo dizendo "balanço da Alfa em 31/12/24"
 *                            entrega tipo, entidade e período numa frase.
 *   confianca                a autoavaliação do modelo. Não é resposta, mas dizer
 *                            "a máquina está 98% segura" ancora do mesmo jeito.
 *
 * O QUE É PERMITIDO, e a distinção importa: `nome_original` (é o que o CLIENTE
 * escreveu, não o que a máquina concluiu, e sem ele a pessoa não sabe qual arquivo
 * abrir), o catálogo de tipos (a lista de opções é a mesma para todo documento, e
 * é ela que impede o typo que viraria falso negativo permanente), o catálogo de
 * classes contábeis, e as rubricas — que vêm por `fn_golden_linhas_para_rotular`,
 * cuja cegueira o `db/test/golden_rotulagem.test.sql` trava do lado do banco.
 */
import { readFileSync } from "node:fs";

const RAIZ = new URL("../../", import.meta.url).pathname;

let ok = 0;
const falhas: string[] = [];
function checar(cond: boolean, desc: string, detalhe = "") {
  if (cond) {
    ok += 1;
  } else {
    falhas.push(`${desc}${detalhe ? ` — ${detalhe}` : ""}`);
  }
}

const TELA = "portal/src/app/autonomia/golden/[rodadaId]/[docId]/page.tsx";
const fonte = readFileSync(RAIZ + TELA, "utf8");

// Tira os comentários antes de qualquer análise: este arquivo FALA sobre
// `valor_num` e `tipo_taxonomia` no cabeçalho, justamente para explicar que não os
// carrega. Um verificador que casasse texto cru reprovaria a documentação da
// própria regra — e a saída natural seria apagar a explicação.
const semComentarios = fonte
  .replace(/\/\*[\s\S]*?\*\//g, "")
  .replace(/^\s*\/\/.*$/gm, "");

// As colunas que a tela pede: o conteúdo de cada `.select("…")`, quebrado em
// nomes. Analisar o argumento do select (em vez de procurar a palavra no arquivo
// inteiro) é o que faz o teste falar sobre a CONSULTA e não sobre o texto.
const selects = [...semComentarios.matchAll(/\.select\(\s*(["'`])([\s\S]*?)\1/g)].map((m) => m[2]);
checar(selects.length >= 3, "a tela cega faz as consultas que a suíte pretende inspecionar",
  `${selects.length} select(s) encontrados`);

const colunas = new Set(
  selects
    .join(",")
    .split(/[,\s()]+/)
    .map((c) => c.trim().toLowerCase())
    .filter(Boolean),
);

const PROIBIDAS = [
  ["valor_num", "o número que a extração leu — é a medição inteira"],
  ["valor_texto", "o texto que a extração leu"],
  ["tipo_taxonomia", "o palpite de tipo da máquina (métrica 1 do f0/06)"],
  ["razao_social", "a entidade que a máquina extraiu (métrica 2)"],
  ["entidade_id", "a entidade que a máquina extraiu (métrica 2)"],
  ["periodo_id", "o período que a máquina extraiu (métrica 2)"],
  ["referencia", "o período que a máquina extraiu (métrica 2)"],
  ["resumo", "prosa da IA: um resumo entrega tipo, entidade e período numa frase"],
  ["justificativa", "a explicação da IA sobre a própria conclusão"],
  ["confianca", "a autoavaliação do modelo ancora tanto quanto a resposta"],
];

for (const [col, porque] of PROIBIDAS) {
  checar(!colunas.has(col),
    `a tela cega NÃO seleciona "${col}" (${porque})`,
    colunas.has(col) ? `apareceu em: ${selects.find((s) => s.includes(col))}` : "");
}

// E o inverso: a tela precisa continuar pedindo o que a torna usável. Sem estes
// dois asserts, "cegar" tudo passaria — inclusive apagando a função que dá as
// rubricas, o que faria o rotulador digitar a grafia dele e transformar diferença
// de datilografia em perda da máquina.
checar(colunas.has("nome_original"),
  "a tela cega ainda mostra o nome do arquivo (é o que o cliente escreveu, não o que a máquina concluiu)");
checar(/fn_golden_linhas_para_rotular/.test(semComentarios),
  "a tela cega busca as rubricas por fn_golden_linhas_para_rotular (a função cega da 0130)");

// A tabela de tipos é permitida, mas só como CATÁLOGO: `taxonomia_tipo_documento`
// filtrado por `ativo`, nunca cruzado com este documento. Um `.eq("codigo", …)`
// vindo do documento seria o vazamento com cara de catálogo.
const trechoTipos = semComentarios.slice(semComentarios.indexOf("taxonomia_tipo_documento"));
checar(
  semComentarios.includes("taxonomia_tipo_documento") &&
    !/taxonomia_tipo_documento[\s\S]{0,400}\.eq\(\s*["']codigo["']/.test(trechoTipos),
  "o catálogo de tipos vem inteiro, não filtrado pelo tipo DESTE documento");

// O componente que recebe as linhas não pode declarar um campo de valor: se o
// tipo dele tivesse `valor_num`, a próxima pessoa a mexer na função do banco teria
// um lugar pronto esperando o dado.
const comp = readFileSync(RAIZ + "portal/src/components/golden-rotular-campos.tsx", "utf8");
const tipoLinha = /type Linha = \{([\s\S]*?)\}/.exec(comp)?.[1] ?? "";
checar(tipoLinha.length > 0, "o componente das linhas declara o tipo Linha");
checar(!/valor/i.test(tipoLinha),
  "…e o tipo Linha não tem nenhum campo com \"valor\" — não há onde o dado pousar",
  tipoLinha.trim());

// A REVELAÇÃO tem de continuar sendo pós-gravação. O que a trava é a ORIGEM do
// dado: `casou_com_a_extracao` só existe no retorno de `fn_golden_rotular_campos`,
// então ele só pode aparecer depois do submit. Se alguém o calculasse na tela, o
// aviso passaria a ser possível durante a digitação.
checar(/casou_com_a_extracao/.test(comp),
  "a revelação (casou/não casou) é exibida");
checar(!/casou_com_a_extracao\s*[=:]\s*(?!.*dado)/.test(comp.replace(/type Registro[\s\S]*$/, "")),
  "…e ela vem do retorno da função, não calculada na tela (só existe depois de gravar)");

console.log(`${ok} verificações OK / ${falhas.length} falhas`);
for (const f of falhas) console.log("  FALHOU:", f);
process.exit(falhas.length ? 1 : 0);
