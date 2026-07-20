import { hasEnvVars } from "@/lib/supabase/env";
import { login } from "./actions";

export default async function LoginPage({
  searchParams,
}: {
  searchParams: Promise<{ error?: string }>;
}) {
  const { error } = await searchParams;

  return (
    <div className="flex min-h-screen items-center justify-center px-4">
      <div className="w-full max-w-sm space-y-6">
        <div>
          <h1 className="text-xl font-semibold">Oria · Tratamento de Dados Financeiros</h1>
          <p className="mt-1 text-sm text-neutral-500">Entre com sua conta da equipe.</p>
        </div>

        {!hasEnvVars && (
          <p className="rounded border border-amber-300 bg-amber-50 p-3 text-sm text-amber-800">
            Variáveis de ambiente do Supabase não configuradas — ver <code>portal/README.md</code>.
          </p>
        )}

        {error && (
          <p className="rounded border border-red-300 bg-red-50 p-3 text-sm text-red-700">{error}</p>
        )}

        <form action={login} className="space-y-4">
          <div>
            <label htmlFor="email" className="block text-sm font-medium">
              Email
            </label>
            <input
              id="email"
              name="email"
              type="email"
              required
              autoComplete="email"
              className="mt-1 w-full rounded border border-neutral-300 px-3 py-2 text-sm"
            />
          </div>
          <div>
            <label htmlFor="password" className="block text-sm font-medium">
              Senha
            </label>
            <input
              id="password"
              name="password"
              type="password"
              required
              autoComplete="current-password"
              className="mt-1 w-full rounded border border-neutral-300 px-3 py-2 text-sm"
            />
          </div>
          <button
            type="submit"
            className="w-full rounded bg-neutral-900 px-3 py-2 text-sm font-medium text-white hover:bg-neutral-800"
          >
            Entrar
          </button>
        </form>

        <p className="text-xs text-neutral-400">
          Contas são criadas pelo administrador no painel do Supabase (ferramenta interna).
        </p>
      </div>
    </div>
  );
}
