import Link from "next/link";
import { createClient } from "@/lib/supabase/server";
import { logout } from "@/app/login/actions";

export default async function CasosLayout({ children }: { children: React.ReactNode }) {
  const supabase = await createClient();
  const { data } = await supabase.auth.getClaims();
  const email = (data?.claims?.email as string | undefined) ?? "";

  return (
    <div className="min-h-screen flex flex-col">
      <header className="border-b border-neutral-200 bg-white">
        <div className="mx-auto flex max-w-5xl items-center justify-between px-4 py-3">
          <Link href="/casos" className="text-sm font-semibold">
            Oria · Tratamento de Dados Financeiros
          </Link>
          <div className="flex items-center gap-3 text-sm text-neutral-500">
            {/* O dial é GLOBAL, não por mandato — por isso mora fora de /casos.
                O link fica aqui porque o painel só serve para quem está usando o
                portal e precisa saber com que autonomia o pipeline rodou. */}
            <Link href="/autonomia" className="text-neutral-500 hover:text-neutral-900">
              Autonomia
            </Link>
            <span>{email}</span>
            <form action={logout}>
              <button type="submit" className="text-neutral-500 underline hover:text-neutral-900">
                Sair
              </button>
            </form>
          </div>
        </div>
      </header>
      <main className="mx-auto w-full max-w-5xl flex-1 px-4 py-6">{children}</main>
    </div>
  );
}
