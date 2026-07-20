// Permite rodar `npm run dev` antes de configurar o .env.local (ver README) sem
// crash — a UI mostra um aviso em vez de estourar em runtime.
export const hasEnvVars =
  !!process.env.NEXT_PUBLIC_SUPABASE_URL && !!process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;
