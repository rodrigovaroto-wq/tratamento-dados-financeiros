import Link from "next/link";
import { createClient } from "@/lib/supabase/server";
import { logout } from "@/app/login/actions";

// O CABEÇALHO É A ÚNICA COISA QUE APARECE EM TODAS AS TELAS, então ele é o que
// diz se o produto é sério antes de qualquer dado carregar. O que mudou:
//
//   • a marca virou marca — sigla em bloco grafite + nome, no lugar de uma
//     linha de texto que se confundia com um link qualquer;
//   • a largura foi de `max-w-5xl` (1024px) para `max-w-6xl`: as telas são
//     TABELAS de oito colunas, e 1024px obrigava a rolar na horizontal num
//     monitor de trabalho;
//   • o e-mail e o "Sair" deixaram de ter o mesmo peso do link de navegação.
export default async function CasosLayout({ children }: { children: React.ReactNode }) {
  const supabase = await createClient();
  const { data } = await supabase.auth.getClaims();
  const email = (data?.claims?.email as string | undefined) ?? "";

  return (
    <div className="flex min-h-screen flex-col bg-tinta-50">
      <header className="sticky top-0 z-10 border-b border-tinta-200 bg-white/95 backdrop-blur">
        <div className="mx-auto flex max-w-6xl items-center justify-between gap-4 px-6 py-3">
          <Link href="/casos" className="flex items-center gap-2.5">
            <span
              aria-hidden
              className="flex h-7 w-7 items-center justify-center rounded-md bg-tinta-800 text-[13px]
                         font-bold text-white"
            >
              O
            </span>
            <span className="flex flex-col leading-tight">
              <span className="text-sm font-semibold text-tinta-900">Oria</span>
              <span className="text-[11px] text-tinta-500">Tratamento de dados financeiros</span>
            </span>
          </Link>

          <div className="flex items-center gap-4 text-sm">
            {/* O dial é GLOBAL, não por mandato — por isso mora fora de /casos.
                O link fica aqui porque o painel só serve para quem está usando o
                portal e precisa saber com que autonomia o pipeline rodou. */}
            <Link
              href="/autonomia"
              className="rounded-md px-2 py-1 text-tinta-600 transition-colors hover:bg-tinta-100 hover:text-tinta-900"
            >
              Autonomia
            </Link>
            {email && (
              <span className="hidden text-xs text-tinta-500 sm:inline" title={email}>
                {email}
              </span>
            )}
            <form action={logout}>
              <button type="submit" className="btn-discreto">
                Sair
              </button>
            </form>
          </div>
        </div>
      </header>

      <main className="mx-auto w-full max-w-6xl flex-1 px-6 py-8">{children}</main>

      {/* O RODAPÉ EXISTE PARA DIZER UMA COISA SÓ, e ela é a mais importante do
          produto: nada aqui é fato até um humano aceitar. Quem abre o portal
          pela primeira vez precisa ler isso sem procurar. */}
      <footer className="border-t border-tinta-200 bg-white">
        <div className="mx-auto max-w-6xl px-6 py-4 text-xs text-tinta-500">
          Os dados desta tela são extraídos dos documentos enviados e conferidos automaticamente.
          Linha marcada como pendente é sugestão a revisar — não é fato até alguém aceitar.
        </div>
      </footer>
    </div>
  );
}
