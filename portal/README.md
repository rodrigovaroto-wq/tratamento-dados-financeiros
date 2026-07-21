# Portal (Vercel) — Fatia 1

Next.js (App Router) + Supabase Auth. Telas cobrem a F1 do plano (`f0` /
`docs/03`): **dashboard do caso** (checklist do Kit Básico, lista de
documentos, pendências de reconciliação/qualidade), **fila de revisão**
(humano confirma/corrige classificação/entidade/tipo/período — o N1 da
Doutrina de Autonomia, `docs/01`), **planilha por documento** (linhas
extraídas + aceite humano — Portão 2 mínimo, `f0/07_output_spec.md`) e
**export Excel** do caso inteiro.

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
  no banco: existe algum `documento` desse `tipo_taxonomia` no caso), a lista
  de documentos com tipo/entidade/período/confiança/fonte/resumo/legibilidade
  (link "ver linhas →" por documento), pendências de **Reconciliação (Classe
  A)** e de **Qualidade dos arquivos**, e o botão **Exportar para Excel**.
- `src/app/casos/[id]/revisao` — fila de revisão: uma pendência de
  classificação/entidade/tipo/período por card (`classificacao_pendente`,
  `tipo_incorreto`, `entidade_incorreta`, `periodo_incorreto` — as três
  últimas vêm do diagnóstico de conteúdo do N8N, `db/migrations/0010`),
  formulário pré-preenchido com a sugestão atual. Confirmar (sem editar) ou
  corrigir e salvar chama a RPC `fn_revisar_documento`
  (`db/migrations/0008_portal_revisao.sql`) — toda a lógica (resolver
  pendência, `decisao`+`evento_auditoria`, checklist, recomputar completude)
  roda no Postgres, não no Next.js.
- `src/app/casos/[id]/documentos/[docId]` — a "planilha" de um documento:
  linhas extraídas agrupadas por `secao`, resumo, aviso de legibilidade, e o
  botão **"Aceitar estes dados para a base"** — chama `fn_aceitar_extracao`
  (`db/migrations/0011_aceite_export_e4.sql`), o Portão 2 mínimo: sem esse
  aceite, a linha nunca entra no export como fato (fica "pendente").
- `src/app/casos/[id]/export` — **route handler** (não página) que gera o
  Excel do caso (`src/lib/export.ts` + `src/lib/statement-templates.ts`,
  função pura testável isoladamente, `exceljs`).
  - **Balanço / DRE / Fluxo de Caixa / Combinado** saem no **layout padrão de
    mercado** dessas demonstrações (`statement-templates.ts`: Ativo/Passivo/PL
    hierárquico no Balanço, cascata Receita→Lucro Líquido na DRE, Atividades
    Operacionais/Investimento/Financiamento no Fluxo de Caixa) — linhas =
    contas do template, colunas = entidade × período. Toda conta casa com a
    chave extraída por termos determinísticos (mesma técnica de
    `fn_valor_conceito`, `db/migrations/0009`) — **nunca soma/calcula** um
    subtotal novo, só recoloca o que a IA já extraiu no lugar certo do
    layout. Contas extraídas que não batem com nenhuma linha do template
    aparecem à parte, em "Outras contas identificadas", ao final da aba —
    nada desaparece silenciosamente. Proveniência (arquivo/página/confiança/
    status/versão da taxonomia) vai em **comentário da célula** (não em
    colunas auxiliares, já que as colunas são entidade×período).
  - **Faturamento / Dívida / Fluxo Projetado** continuam em listagem simples
    (já são, por natureza, uma série/tabela — não uma demonstração de blocos).
  - Aba `Resumo` com metadados do snapshot (data-base, contagem aceitas/
    pendentes, versões de taxonomia). Linhas pendentes de aceite aparecem
    junto (nunca somem), mas com preenchimento âmbar + itálico — "sugestão
    pendente de revisão", nunca fato silencioso (princípio inegociável de
    `f0/07_output_spec.md`).

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

Depois de rodar as migrations do `db/` (até a `0011` inclusive):

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
  (com env vars de teste; `/casos`, `/casos/[id]`, `/casos/[id]/revisao`,
  `/casos/[id]/documentos/[docId]`, `/casos/[id]/export` e `/login`
  corretamente dinâmicas, `/` estática).
- `src/lib/export.ts` (montagem do workbook) testado isoladamente com dados
  sintéticos via `tsx` + `exceljs`: gera as abas certas, reabre o `.xlsx`
  gerado e confere célula a célula — layout padronizado do Balanço (linhas
  do template certas, valores casados por entidade×período, inclusive um
  mesmo rótulo em dois períodos diferentes da mesma entidade), disambiguação
  entre "Total do Ativo" e "Total do Ativo Circulante"/"Não Circulante" (achou
  e corrigiu um bug real de sobreposição: "Total do Patrimônio Líquido"
  casando com a linha combinada "Total do Passivo e do Patrimônio Líquido"),
  contas não mapeadas indo para o apêndice "Outras contas identificadas",
  nota de proveniência na célula, preenchimento âmbar + itálico em pendente,
  negrito + borda dupla em total, aba Resumo com as contagens certas.

## O que NÃO foi possível verificar aqui (precisa do Supabase real)

Sem um projeto Supabase/PostgREST real rodando neste ambiente, as queries
com **embed de foreign key** (`entidade:entidade_id(razao_social)`,
`periodo:periodo_id(tipo, referencia)`, `documento_versao(nome_original)`,
os embeds em `revisao/page.tsx`, `documentos/[docId]/page.tsx` e
`export/route.ts`) foram escritas conforme a sintaxe documentada do
PostgREST/Supabase-js, mas **não foram exercitadas contra um banco real**
(a lógica de montagem do Excel em si — `src/lib/export.ts` — foi testada
isoladamente com dados sintéticos, só a busca via Supabase não). Ao testar a
primeira vez com Supabase real, conferir especialmente:
- Que os embeds trazem os dados esperados (não `null` por ambiguidade de FK
  ou nome errado de relação).
- Que as RPCs `fn_revisar_documento` e `fn_aceitar_extracao` estão com
  `EXECUTE` liberado para `authenticated` (as migrations já fazem o `grant`,
  mas confirmar no painel).
- Login/logout e o redirect do `proxy.ts` funcionando ponta a ponta.
- O botão "Exportar para Excel" baixando um `.xlsx` que abre corretamente no
  Excel/LibreOffice (o teste local só reabriu com `exceljs`, não com um
  programa de planilha de verdade).

## Estrutura

```
src/
  lib/
    supabase/{client,server,proxy,env}.ts   # clientes Supabase (browser/server/proxy)
    types.ts                                 # tipos das linhas do Postgres
    status.ts                                # rótulos/cores de caso_status
    statement-templates.ts                   # layout padrão de mercado (Balanço/DRE/Fluxo)
    export.ts                                # monta o workbook (função pura, sem Supabase)
  app/
    login/{page.tsx,actions.ts}
    casos/
      layout.tsx                             # header + logout (rotas autenticadas)
      page.tsx                               # lista de casos
      [id]/page.tsx                          # dashboard do caso
      [id]/revisao/{page.tsx,actions.ts}      # fila de revisão
      [id]/documentos/[docId]/{page.tsx,actions.ts}  # planilha + aceite
      [id]/export/route.ts                    # gera o .xlsx (usa lib/export.ts)
  proxy.ts                                    # sessão + redirect (Next.js 16)
```

## Próximas fatias (fora deste escopo)

- Upload em lote pelo portal (hoje é N8N Form) — se algum dia migrar, via SDK
  oficial do Supabase JS (evita o bug de plataforma do HTTP Request do N8N,
  ver `n8n/README.md`).
- Aceite por linha/célula (hoje é por documento_versao inteiro, v0 —
  `f0/07_output_spec.md` permite refinar o "layout fino" depois).
- Portão 2 formal do caso inteiro (bloqueantes não-sobrepujáveis, teto de
  ressalva, `docs/07_STATUS_E_PENDENCIAS.md`) — hoje só existe o aceite
  mínimo por linha extraída (`fn_aceitar_extracao`).
- RLS por caso (membership) — hoje é "qualquer autenticado vê tudo" (decisão
  explícita da F1, `db/migrations/0003_rls_e_storage.sql`).
