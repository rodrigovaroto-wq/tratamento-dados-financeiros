# Portal (Vercel) — Fatia 1

Next.js (App Router) + Supabase Auth. Duas telas cobrem a fatia 1 do plano
(`f0` / `docs/03`): **dashboard do caso** (checklist do Kit Básico + lista de
documentos) e **fila de revisão** (humano confirma/corrige a classificação —
o N1 da Doutrina de Autonomia, `docs/01`).

> **Upload em lote continua fora do portal por decisão explícita** (ver
> `n8n/README.md`): a ingestão roda pelo Form Trigger do N8N. O portal aqui é
> só o lado de **leitura + revisão humana**.

## O que tem

- `src/proxy.ts` + `src/lib/supabase/proxy.ts` — renova a sessão a cada
  requisição e redireciona quem não está autenticado para `/login` (Next.js
  16 renomeou `middleware.ts` → `proxy.ts`, ver
  [nextjs.org/docs/messages/middleware-to-proxy](https://nextjs.org/docs/messages/middleware-to-proxy)).
- `src/app/login` — login por email/senha (Supabase Auth). Contas são criadas
  pelo administrador direto no painel do Supabase (Authentication → Users) —
  não há tela de cadastro (ferramenta interna, um time).
- `src/app/casos` — lista de casos.
- `src/app/casos/[id]` — dashboard: status do caso, checklist do Kit Básico
  (verde = presente, calculado da mesma forma que `fn_recomputar_completude`
  no banco: existe algum `documento` desse `tipo_taxonomia` no caso), e a
  lista de documentos com tipo/entidade/período/confiança/fonte.
- `src/app/casos/[id]/revisao` — fila de revisão: uma pendência
  `classificacao_pendente` por card, formulário pré-preenchido com a sugestão
  atual. Confirmar (sem editar) ou corrigir e salvar chama a RPC
  `fn_revisar_documento` (`db/migrations/0008_portal_revisao.sql`) — toda a
  lógica (resolver pendência, `decisao`+`evento_auditoria`, checklist,
  recomputar completude) roda no Postgres, não no Next.js.

## Configuração

```bash
cp .env.example .env.local
```

Preencher com os valores do projeto Supabase (Settings → API):
- `NEXT_PUBLIC_SUPABASE_URL`
- `NEXT_PUBLIC_SUPABASE_ANON_KEY` — a chave **anon/publishable** (pública por
  design, é o que o browser usa). **Nunca** a `service_role` aqui — ela
  ignora RLS (ver `db/README.md` "Notas de segurança (LGPD)"). O acesso do
  portal respeita RLS porque o usuário chega autenticado (`authenticated`
  role) via Supabase Auth.

Depois de rodar as migrations do `db/` (até a `0008` inclusive):

```bash
npm install
npm run dev     # http://localhost:3000
```

Criar um usuário de teste em Authentication → Users no painel do Supabase
para logar.

## Deploy (Vercel)

1. Importar este diretório (`portal/`) como o **Root Directory** do projeto
   Vercel (o repo tem outras pastas — `n8n/`, `db/`, `docs/` — que não fazem
   parte do app Next.js).
2. Configurar as duas env vars acima em Project Settings → Environment
   Variables (mesmos valores do `.env.local`).
3. Deploy. Sem passos de build customizados — `next build` padrão.

## Verificado localmente antes de entregar

- `npx tsc --noEmit` — sem erros.
- `npm run lint` — sem erros.
- `npm run build` — build de produção completo, todas as rotas compilam
  (com env vars de teste; `/casos`, `/casos/[id]`, `/casos/[id]/revisao` e
  `/login` corretamente dinâmicas, `/` estática).

## O que NÃO foi possível verificar aqui (precisa do Supabase real)

Sem um projeto Supabase/PostgREST real rodando neste ambiente, as queries
com **embed de foreign key** (`entidade:entidade_id(razao_social)`,
`periodo:periodo_id(tipo, referencia)`, `documento_versao(nome_original)`,
e o embed de dois níveis em `revisao/page.tsx`) foram escritas conforme a
sintaxe documentada do PostgREST/Supabase-js, mas **não foram exercitadas
contra um banco real**. Ao testar a primeira vez com Supabase real, conferir
especialmente:
- Que os embeds trazem os dados esperados (não `null` por ambiguidade de FK
  ou nome errado de relação).
- Que a RPC `fn_revisar_documento` está com `EXECUTE` liberado para
  `authenticated` (a migration já faz o `grant`, mas confirmar no painel).
- Login/logout e o redirect do `proxy.ts` funcionando ponta a ponta.

## Estrutura

```
src/
  lib/
    supabase/{client,server,proxy,env}.ts   # clientes Supabase (browser/server/proxy)
    types.ts                                 # tipos das linhas do Postgres
    status.ts                                # rótulos/cores de caso_status
  app/
    login/{page.tsx,actions.ts}
    casos/
      layout.tsx                             # header + logout (rotas autenticadas)
      page.tsx                               # lista de casos
      [id]/page.tsx                          # dashboard do caso
      [id]/revisao/{page.tsx,actions.ts}      # fila de revisão
  proxy.ts                                    # sessão + redirect (Next.js 16)
```

## Próximas fatias (fora deste escopo)

- Upload em lote pelo portal (hoje é N8N Form) — se algum dia migrar, via SDK
  oficial do Supabase JS (evita o bug de plataforma do HTTP Request do N8N,
  ver `n8n/README.md`).
- Base viva com proveniência por célula + export Excel (`f0/07_output_spec.md`)
  — depende de E3 (reconciliação) e do aceite humano do Portão 2, que ainda
  não existem.
- RLS por caso (membership) — hoje é "qualquer autenticado vê tudo" (decisão
  explícita da F1, `db/migrations/0003_rls_e_storage.sql`).
