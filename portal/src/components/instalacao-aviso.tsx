import Link from "next/link";
import { createClient } from "@/lib/supabase/server";

// O AVISO DE INSTALAÇÃO INCOMPLETA, no topo do painel.
//
// POR QUE ISTO É COMPONENTE DE SERVIDOR E NÃO UM ALERTA CLIENTE. Ele consulta o
// banco, e a resposta não muda com interação: o que está instalado no Supabase é
// estado do servidor, não do navegador.
//
// POR QUE ELE APARECE SÓ QUANDO FALTA ALGO. Um selo verde permanente de "tudo
// instalado" seria ruído no topo da tela mais usada da casa, e ruído permanente é
// a receita para não se ver o dia em que ele fica vermelho. Ausência de aviso é a
// afirmação de que está tudo lá.
//
// E POR QUE ELE EXISTE. Este é o defeito que a 0131 fecha, e ele não é de código:
// os requisitos de instalação moravam em recados de prosa espalhados pelo
// `ESTADO.md`. Quem abre o portal não lê o `ESTADO.md`. O sintoma da falta nunca
// foi uma tela quebrada — foi um traço no lugar de um número, uma lista tratando
// todo mandato como ativo, uma aba de perguntas vazia. Tudo com cara de
// funcionando.

type Faltando = {
  chave: string;
  migration: string;
  porque: string;
  severidade: "bloqueante" | "importante" | "informativo";
};

type Resumo = {
  total: number;
  presentes: number;
  ausentes: number;
  bloqueantes_ausentes: number;
  completa: boolean;
  faltando: Faltando[];
};

export async function InstalacaoAviso() {
  const supabase = await createClient();
  const { data, error } = await supabase.rpc("fn_instalacao_resumo");

  // A PRÓPRIA SONDA PODE NÃO ESTAR INSTALADA, e este é o único caso em que o
  // silêncio é a resposta certa. Se a 0131 não foi aplicada, `fn_instalacao_resumo`
  // não existe e o erro que volta é sobre ela — avisar "não consegui conferir a
  // instalação" no topo do painel de quem ainda não aplicou a migration seria um
  // alarme sobre o próprio alarme. O sintoma da 0131 ausente é este aviso não
  // aparecer, e está escrito no `db/README.md`.
  if (error || !data) return null;

  const r = data as Resumo;
  if (r.completa || r.faltando.length === 0) return null;

  const bloqueantes = r.faltando.filter((f) => f.severidade === "bloqueante");
  const grave = bloqueantes.length > 0;

  return (
    <section
      className={`rounded-lg border p-4 ${
        grave ? "border-red-300 bg-red-50" : "border-amber-300 bg-amber-50"
      }`}
    >
      <div className="flex flex-wrap items-baseline justify-between gap-2">
        <h2
          className={`text-sm font-semibold ${grave ? "text-red-900" : "text-amber-900"}`}
        >
          {grave
            ? `Instalação incompleta — ${bloqueantes.length} item(ns) bloqueante(s)`
            : `Instalação incompleta — ${r.ausentes} de ${r.total} itens faltando`}
        </h2>
        <Link
          href="/instalacao"
          className={`text-xs underline ${grave ? "text-red-800" : "text-amber-800"}`}
        >
          ver a lista completa
        </Link>
      </div>

      {/* O SINTOMA, não o número da migration. Quem está olhando esta tela quer
          saber o que vai parecer errado, não qual arquivo aplicar — e o número da
          migration vem depois, entre parênteses, para quem for aplicar. */}
      <ul className={`mt-2 space-y-1.5 text-sm ${grave ? "text-red-800" : "text-amber-900"}`}>
        {r.faltando.slice(0, 3).map((f) => (
          <li key={f.chave}>
            {f.porque}{" "}
            <span className="whitespace-nowrap font-mono text-xs opacity-70">
              ({f.migration})
            </span>
          </li>
        ))}
      </ul>

      {r.faltando.length > 3 && (
        <p className={`mt-2 text-xs ${grave ? "text-red-700" : "text-amber-800"}`}>
          e mais {r.faltando.length - 3} — a lista completa diz o sintoma de cada um.
        </p>
      )}
    </section>
  );
}
