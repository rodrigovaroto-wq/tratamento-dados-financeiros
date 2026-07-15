# Camada N8N — Fatia 1 (E1 — Ingestão)

O N8N é o **orquestrador stateless** (docs/02, trava de stack nº 1): recebe o upload em lote,
classifica cada arquivo e chama as funções do Postgres (`db/migrations/0004`) que cuidam do
estado. A ingestão é feita **pelo próprio N8N** (Form Trigger) — sem Vercel nesta fatia.

## O que roda (fluxo do `workflow.e1-ingestao.json`)

```
Intake (Form Trigger: nome do mandato + upload de N arquivos)
  → Upsert Caso ............... fn_upsert_caso(nome) → caso_id
  → Listar Arquivos ........... 1 item por arquivo
  → Upload Storage ............ POST no bucket privado 'documentos'
  → Classificar Nome .......... nome + regras → {tipo, período, assinado, confiança}
  → Precisa Fallback? ......... confiança < 0.7 ou tipo desconhecido?
        ├─ sim → OpenAI Classificar → Parse OpenAI  (lê o conteúdo)
        └─ não → segue direto
  → Registrar Documento ....... fn_registrar_documento(...) → cria doc+versão+checklist+pendência
  → Recomputar Completude ..... fn_recomputar_completude(caso_id) → Portão 1 + status + pendências
```

Autonomia (docs/01): classificação nasce em **N1** (sugestão; humano confirma na fila de
revisão — próxima fatia). Nada é aceito como fato sem revisão (anti-ancoragem).

## Como usar

1. **Aplicar as migrations do banco** (`db/README.md`) — inclusive a `0004` (funções).
2. **Importar** `n8n/workflow.e1-ingestao.json` no N8N (Import from File).
3. **Configurar credenciais/variáveis** (ver abaixo).
4. Abrir a URL do **Form Trigger**, informar o nome do mandato e subir os arquivos.
5. Conferir no banco: `caso`, `documento`, `checklist_item_status`, `pendencia`,
   `evento_auditoria` populados; status do caso avançando conforme a completude.

## Credenciais e variáveis (configurar no N8N)

- **Postgres (Supabase, Session Pooler)** — credencial `Supabase Postgres (Session Pooler)`
  nos 3 nós Postgres. Reaproveitar do `clipping-news`. Pegadinhas herdadas: usar o **Session
  Pooler** (IPv4 + SSL), usuário com sufixo `.projectref`. O N8N usa conexão de serviço, que
  **ignora RLS** por design (é o orquestrador) — ver `db/migrations/0003`.
- **Variáveis de ambiente** do N8N:
  - `SUPABASE_URL` — ex.: `https://<ref>.supabase.co`
  - `SUPABASE_SERVICE_KEY` — service role (só no N8N, **nunca** no portal)
  - `OPENAI_API_KEY` — chave da API direta
  - `OPENAI_MODEL` — opcional (default `gpt-4o`)

## ⚠️ Estado honesto desta entrega

- **Caminho determinístico (nome → registro → completude): completo e testado** — a lógica
  está validada por testes unitários (`n8n/test/`) e as funções do banco foram exercitadas
  num Postgres real (ver PR).
- **Fallback OpenAI: scaffold.** O nó `OpenAI Classificar` está montado com o schema estrito
  correto, **mas** envia por ora só o nome do arquivo — falta plugar o **conteúdo** (converter
  página de PDF em imagem ou usar a File API da OpenAI). É o próximo passo para habilitar a
  leitura de arquivos de nome genérico. Enquanto isso, esses arquivos entram com pendência
  `classificacao_pendente` e vão para revisão humana (comportamento fail-safe correto).
- **Não executado no N8N real** deste ambiente (sem instância/credenciais). O JSON é válido e
  importável; os nós Code parseiam; a lógica e as funções SQL foram testadas isoladamente.

## Fonte da verdade da lógica

`n8n/lib/*.mjs` são os módulos **testados** (`node --test` em `n8n/test/`). Os nós Code do
workflow **espelham** essa lógica (inline, porque nós Code não importam arquivos). Ao alterar a
lógica: mude `lib/`, rode os testes, e **regenere** o workflow com `node n8n/build-workflow.mjs`.

## Estrutura

```
n8n/
├── lib/            # lógica testável (classifier, completude, openai, taxonomia, normalize)
├── test/           # node:test (17 casos)
├── build-workflow.mjs        # gerador do workflow (JSON válido)
├── workflow.e1-ingestao.json # workflow importável no N8N
└── README.md
```

## Próximas fatias

- Habilitar o conteúdo no fallback OpenAI (visão/OCR) + extração de linhas financeiras em
  **N0/sombra** (E2) → grava em `campo_extraido` (tabela a criar).
- Portal Vercel (fila de revisão para confirmar/corrigir a classificação N1, dashboard, export).
