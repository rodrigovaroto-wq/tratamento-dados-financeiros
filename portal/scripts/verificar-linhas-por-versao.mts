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
function servidor(linhas: Linha[], teto: number) {
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
  const { porVersao, truncado } = await contarLinhasPorVersao(cliente as never, Object.keys(esperado));
  for (const [v, n] of Object.entries(esperado)) {
    checar(porVersao.get(v) === n, `${v}: contou ${porVersao.get(v)} linhas, o documento tem ${n} — o teto de 1000 cortou em silêncio`);
  }
  const soma = [...porVersao.values()].reduce((a, b) => a + b, 0);
  checar(soma === 2681, `a soma das versões deu ${soma}, esperado 2681`);
  checar(truncado === false, "a leitura se declarou truncada sem ter batido no teto de segurança");
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

// --- e o caso vazio não consulta nada nem inventa zero -------------------------
{
  const { cliente, consultas } = servidor([], 1000);
  const { porVersao } = await contarLinhasPorVersao(cliente as never, []);
  checar(porVersao.size === 0 && consultas() === 0, "sem versões, a função consultou o banco ou devolveu contagem");
}

// --- 3. nenhuma outra leitura de LINHAS de campo_extraido fora do paginar ------
// Cada `.from("campo_extraido")` em portal/src precisa estar dentro de um
// `paginar(` ou ser um `count` com `head: true`. Olha-se o trecho que cerca a
// chamada (a consulta inteira cabe em ~12 linhas neste código).
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
  let leituras = 0;
  for (const arq of arquivos) {
    const linhas = readFileSync(arq, "utf8").split("\n");
    linhas.forEach((l, i) => {
      if (!l.includes('from("campo_extraido")')) return;
      leituras++;
      const antes = linhas.slice(Math.max(0, i - 4), i + 1).join("\n");
      const depois = linhas.slice(i, i + 12).join("\n");
      const protegida = /paginar\s*[<(]/.test(antes) || /head:\s*true/.test(depois);
      checar(protegida, `${arq.replace(SRC, "portal/src/")}:${i + 1} lê linhas de campo_extraido sem paginar — o teto de 1000 corta em silêncio`);
    });
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
