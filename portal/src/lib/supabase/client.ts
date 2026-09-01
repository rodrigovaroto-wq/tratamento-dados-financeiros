import { createBrowserClient } from "@supabase/ssr";

// Cliente para Client Components. Usa a chave anon/publishable — RESPEITA RLS
// (nunca a service_role; ver Supabase/README.md "Notas de segurança (LGPD)").
export function createClient() {
  return createBrowserClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
  );
}
