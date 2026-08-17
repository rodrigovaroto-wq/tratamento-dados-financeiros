import { hasEnvVars } from "@/lib/supabase/env";
import { login } from "./actions";

export default async function LoginPage({
  searchParams,
}: {
  searchParams: Promise<{ error?: string }>;
}) {
  const { error } = await searchParams;

  return (
    // A PRIMEIRA TELA DO PRODUTO. Ela era um formulário solto no meio do branco;
    // agora tem a mesma marca do cabeçalho e uma superfície própria — é o que
    // separa "sistema interno" de "produto" na primeira impressão.
    <div className="flex min-h-screen items-center justify-center bg-tinta-50 px-4">
      <div className="w-full max-w-sm space-y-6">
        <div className="flex flex-col items-center gap-3 text-center">
          <span
            aria-hidden
            className="flex h-11 w-11 items-center justify-center rounded-xl bg-tinta-800 text-lg
                       font-bold text-white"
          >
            O
          </span>
          <div>
            <h1 className="text-lg font-semibold text-tinta-900">Oria</h1>
            <p className="mt-0.5 text-sm text-tinta-500">Tratamento de dados financeiros</p>
          </div>
        </div>

        {!hasEnvVars && (
          <p className="rounded-lg border border-amber-200 bg-amber-50 p-3 text-sm text-amber-800">
            Variáveis de ambiente do Supabase não configuradas — ver <code>portal/README.md</code>.
          </p>
        )}

        {error && (
          <p className="rounded-lg border border-red-200 bg-red-50 p-3 text-sm text-red-800">{error}</p>
        )}

        <form action={login} className="carta space-y-4 p-6">
          <div>
            <label htmlFor="email" className="block text-sm font-medium text-tinta-700">
              Email
            </label>
            <input
              id="email"
              name="email"
              type="email"
              required
              autoComplete="email"
              className="mt-1 w-full rounded-md border border-tinta-200 px-3 py-2 text-sm"
            />
          </div>
          <div>
            <label htmlFor="password" className="block text-sm font-medium text-tinta-700">
              Senha
            </label>
            <input
              id="password"
              name="password"
              type="password"
              required
              autoComplete="current-password"
              className="mt-1 w-full rounded-md border border-tinta-200 px-3 py-2 text-sm"
            />
          </div>
          <button type="submit" className="btn-primario w-full justify-center py-2">
            Entrar
          </button>
        </form>

        <p className="text-center text-xs text-tinta-400">
          O acesso é criado pelo administrador da equipe.
        </p>
      </div>
    </div>
  );
}
