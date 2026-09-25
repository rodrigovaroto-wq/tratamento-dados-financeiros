// A SUÍTE DA CONTAGEM POR DOCUMENTO — o teto de 1000 linhas que o PostgREST
// aplica em silêncio.
//
// POR QUE ELA EXISTE. Em 24/09/2026 a auditoria achou a conta "quantas linhas
// cada documento rendeu" em duas cópias: o detalhe do caso passava por
// `paginar`, o painel (`casos/page.tsx`, as dez linhas de "O que chegou") fazia
// uma consulta só. O PostgREST devolve no máximo `db-max-rows` linhas — 1000 por
// padrão — e corta o resto SEM erro: a contagem saía truncada com cara de
// contagem. É o defeito que `paginar.ts` registra ter aparecido em produção
// ("1.000 linhas extraídas" com muito mais no banco), corrigido para o total e
// esquecido nesta conta.
//
// O QUE ESTA SUÍTE TRAVA:
//   1. contra um servidor que corta em 1000 como o PostgREST, a contagem de um
//      documento com 2.500 linhas dá 2.500 — e a soma das versões bate;
//   2. um teto de servidor MENOR que a janela (500) não encerra a leitura cedo —
//      a regra de parada de `paginar` é a página vazia, não a página curta;
//   3. nenhuma leitura de LINHAS de `campo_extraido` em `portal/src` fica fora
//      do `paginar` (ou de um `count` com `head: true`, que não traz linha) — é
//      a forma de a segunda cópia voltar.
//
// Não há banco aqui: o servidor é simulado, e o que se simula é SÓ o teto (a
// regra 4 — o arranjo real é "mais linhas do que o teto", e é esse o arranjo).
import { readFileSync, readdirSync, statSync } from "node:fs";
import { join } from "node:path";
import { contarLinhasPorVersao } from "../src/lib/supabase/linhas-por-versao";

let ok = 0;
const falhas: string[] = [];
function checar(cond: boolean, msg: string) {
  if (cond) ok++;
  else falhas.push(msg);
}

type Linha = { id: number; documento_versao_id: string };

/** Um PostgREST de mentira que só sabe uma coisa: cortar em `teto` linhas. */
function servidor(linhas: Linha[], teto: number, falhaNaConsulta = 0) {
  let consultas = 0;
  const cliente = {
    from: () => ({
      select: () => ({
        in: (_c: string, versoes: string[]) => {
          const filtradas = linhas.filter((l) => versoes.includes(l.documento_versao_id));
          // Só `.order().range()`: é a única forma de pedir linhas que este servidor
          // aceita, como o contrato de `paginar` exige.
          const range = (de: number, ate: number) => {
            consultas++;
            if (consultas === falhaNaConsulta) return Promise.resolve({ data: null, error: { message: "canceling statement due to statement timeout" } });
            const fim = Math.min(ate + 1, de + teto);
            return Promise.resolve({ data: filtradas.slice(de, fim), error: null });
          };
          return { order: () => ({ range }) };
        },
      }),
    }),
  };
  return { cliente, consultas: () => consultas };
}

function lote(porVersao: Record<string, number>): Linha[] {
  const out: Linha[] = [];
  let id = 1;
  for (const [v, n] of Object.entries(porVersao)) for (let i = 0; i < n; i++) out.push({ id: id++, documento_versao_id: v });
  return out;
}

// --- 1. acima do teto padrão -------------------------------------------------
{
  const esperado = { "v-razao": 2500, "v-bp": 180, "v-dre": 1 };
  const { cliente, consultas } = servidor(lote(esperado), 1000);
  const { porVersao, incompleto } = await contarLinhasPorVersao(cliente as never, Object.keys(esperado));
  for (const [v, n] of Object.entries(esperado)) {
    checar(porVersao.get(v) === n, `${v}: contou ${porVersao.get(v)} linhas, o documento tem ${n} — o teto de 1000 cortou em silêncio`);
  }
  const soma = [...porVersao.values()].reduce((a, b) => a + b, 0);
  checar(soma === 2681, `a soma das versões deu ${soma}, esperado 2681`);
  checar(incompleto === false, "a leitura se declarou incompleta sem ter falhado nem batido no teto de segurança");
  checar(consultas() > 1, `uma consulta só (${consultas()}) não passa de 1000 linhas — a leitura não está paginando`);
}

// --- 2. servidor com teto MENOR que a janela ----------------------------------
{
  const esperado = { "v-razao": 1700 };
  const { cliente } = servidor(lote(esperado), 500);
  const { porVersao } = await contarLinhasPorVersao(cliente as never, ["v-razao"]);
  checar(porVersao.get("v-razao") === 1700,
    `com o servidor cortando em 500, contou ${porVersao.get("v-razao")} de 1700 — a leitura parou na primeira página curta`);
}

// --- 2b. uma página que FALHA no meio não vira contagem ------------------------
// Achado da revisão do PR #244: `paginar` devolve o que leu até o erro, e a versão
// anterior desta função jogava o erro fora — o detalhe do caso mostrava a soma
// parcial e contava como "sem nenhuma linha" documentos que tinham linhas. A
// contagem parcial tem de se declarar (regra 1), e é o que `incompleto` faz.
{
  const esperado = { "v-razao": 2500 };
  const { cliente } = servidor(lote(esperado), 1000, 2);
  const { porVersao, incompleto } = await contarLinhasPorVersao(cliente as never, ["v-razao"]);
  checar(incompleto === true,
    `a segunda página falhou e a contagem (${porVersao.get("v-razao")} de 2500) NÃO se declarou incompleta`);
}

// --- e o caso vazio não consulta nada nem inventa zero -------------------------
{
  const { cliente, consultas } = servidor([], 1000);
  const { porVersao } = await contarLinhasPorVersao(cliente as never, []);
  checar(porVersao.size === 0 && consultas() === 0, "sem versões, a função consultou o banco ou devolveu contagem");
}

// --- 3. nenhuma outra leitura de LINHAS de campo_extraido fora do paginar ------
// Cada `.from("campo_extraido")` em portal/src precisa estar dentro de um
// `paginar(` ou ser um `count` com `head: true` NO PRÓPRIO `.select(` dessa
// consulta. A primeira versão (24/09/2026) aceitava `head: true` em qualquer lugar
// das 12 linhas seguintes — e no painel a consulta de `documento`, oito linhas
// abaixo, tem um: tirar o `head: true` da contagem total de linhas (a volta exata
// do "1.000 linhas extraídas") passava verde, medido pela revisão do PR #244.
// Agora o que se lê são os argumentos balanceados do `.select(` que segue o
// `.from(` — o `head` de outra consulta não conta.
{
  const SRC = new URL("../src/", import.meta.url).pathname;
  const arquivos: string[] = [];
  const andar = (d: string) => {
    for (const f of readdirSync(d)) {
      const p = join(d, f);
      if (statSync(p).isDirectory()) andar(p);
      else if (/\.(ts|tsx)$/.test(f)) arquivos.push(p);
    }
  };
  andar(SRC);
  /** Os argumentos de `.select(...)`, com parênteses balanceados, ou null. */
  const argsDoSelect = (texto: string, desde: number): string | null => {
    const i = texto.indexOf(".select(", desde);
    if (i < 0) return null;
    let nivel = 0;
    for (let k = i + ".select".length; k < texto.length; k++) {
      if (texto[k] === "(") nivel++;
      else if (texto[k] === ")" && --nivel === 0) return texto.slice(i + ".select(".length, k);
    }
    return null;
  };
  /**
   * A posição `i` está DENTRO dos parênteses de uma chamada `paginar(...)`?
   *
   * A segunda versão (24/09/2026) olhava os 400 caracteres anteriores procurando
   * `paginar(` sem `;` no meio — e num `Promise.all([paginar(...), supabase.from(
   * "campo_extraido")...])` a vírgula não é `;`: uma leitura não paginada logo depois
   * de um `paginar` passava (achado ALTO da terceira revisão do PR #244, medido em
   * `perguntas/page.tsx`; o varredor da primeira versão a pegava). Agora se casa o
   * parêntese de cada `paginar` e se exige que a leitura esteja entre os dois.
   */
  const dentroDeUmPaginar = (texto: string, i: number): boolean => {
    for (const m of texto.slice(0, i).matchAll(/paginar\s*(?:<[^()]*?>)?\s*\(/g)) {
      const abre = (m.index ?? 0) + m[0].length - 1;
      let nivel = 0;
      for (let k = abre; k < texto.length; k++) {
        if (texto[k] === "(") nivel++;
        else if (texto[k] === ")" && --nivel === 0) {
          if (k > i) return true;
          break;
        }
      }
    }
    return false;
  };
  let leituras = 0;
  for (const arq of arquivos) {
    const texto = readFileSync(arq, "utf8");
    const alvo = 'from("campo_extraido")';
    for (let i = texto.indexOf(alvo); i >= 0; i = texto.indexOf(alvo, i + 1)) {
      leituras++;
      const linha = texto.slice(0, i).split("\n").length;
      const dentroDoPaginar = dentroDeUmPaginar(texto, i);
      const soContagem = /head:\s*true/.test(argsDoSelect(texto, i) ?? "");
      checar(dentroDoPaginar || soContagem,
        `${arq.replace(SRC, "portal/src/")}:${linha} lê linhas de campo_extraido sem paginar — o teto de 1000 corta em silêncio`);
    }
  }
  // controle positivo: o varredor ACHOU as leituras que se sabe existirem
  checar(leituras >= 4, `o varredor achou só ${leituras} leitura(s) de campo_extraido — ele não está olhando onde devia`);
}

if (falhas.length > 0) {
  console.error(`\n${falhas.length} falha(s):`);
  for (const f of falhas) console.error(`  ✗ ${f}`);
  console.error(`\n${ok} verificações OK / ${falhas.length} falhas`);
  process.exit(1);
}
console.log(`${ok} verificações OK / 0 falhas`);
console.log("CONTAGEM POR DOCUMENTO OK — passa do teto de 1000 do PostgREST, e nenhuma leitura de linhas fica fora do paginar");
