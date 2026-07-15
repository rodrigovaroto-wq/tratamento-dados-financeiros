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
  → Preparar Conteudo ......... parte multimodal p/ TODOS: pdf→file, imagem→image_url,
                                csv→texto (parse inline), xlsx→nota (ver ⚠️)
  → Classificar Nome .......... nome + regras → {tipo, período, assinado, confiança}
  → Precisa Fallback? ......... confiança < 0.7 ou tipo desconhecido?
        ├─ sim → Montar Req Classif → OpenAI Classificar → Parse  (lê o conteúdo)
        └─ não → segue direto
  → Registrar Documento ....... fn_registrar_documento(...) → doc+versão+checklist+pendência
        ├─ Recomputar Completude ... fn_recomputar_completude(caso_id) → Portão 1 + status
        └─ [E2] Montar Req Extracao → OpenAI Extrair → Parse → Gravar Campos (Sombra)
                                      fn_registrar_campos_extraidos(...) em N0
```

Autonomia (docs/01): classificação nasce em **N1** (sugestão; humano confirma na fila de
revisão — próxima fatia); **extração (E2) nasce em N0 (sombra)** — registra para medir, não
decide, não entra em base sem aceite humano (anti-ancoragem).

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

## Fallback OpenAI (conteúdo) — como funciona

Quando o classificador por nome não tem confiança, o nó **Preparar Conteudo Fallback** monta o
corpo da chamada com o **conteúdo real do arquivo**:
- **PDF** → parte `file` (base64 `data:application/pdf;base64,...`) — o modelo lê texto + páginas.
- **Imagem** (scan/foto PNG/JPG) → parte `image_url` (base64).
- **CSV** → decodificado e parseado inline (vira texto tabular para o modelo).
- **XLSX** → hoje envia uma nota de texto. Para habilitar: inserir um nó *Extract From File*
  (spreadsheet) antes de `Preparar Conteudo` e usar `spreadsheetToText(rows)` (`n8n/lib/spreadsheet.mjs`)
  para montar a parte de texto. É um ponto explícito de validação/adaptação no N8N.
- Saída sempre via **Structured Outputs** (JSON Schema estrito) → `Parse OpenAI` normaliza para o
  mesmo formato do classificador por nome. Continua **N1**: sugestão para a fila de revisão.

## ⚠️ Estado honesto desta entrega

- **Caminho determinístico (nome → registro → completude): completo e testado** — lógica
  validada por testes unitários (`n8n/test/`) e funções do banco exercitadas num Postgres real.
- **Fallback OpenAI para PDF, imagem e CSV: completo** — conteúdo enviado como
  `file`/`image_url`/texto + Structured Outputs; corpo e parse cobertos por testes.
- **Extração E2 (linhas financeiras) em N0/sombra: completo** — corpo/schema/parse testados
  (`n8n/test/extract.test.mjs`) e a gravação (`fn_registrar_campos_extraidos`) exercitada em
  Postgres real. Não altera status nem entra em base (sombra/anti-ancoragem).
- **Pendência: XLSX** — falta o *Extract From File* (ver acima). CSV já é tratado.
- **Não executado no N8N real** deste ambiente (sem instância/credenciais). O JSON é válido e
  importável; os nós Code parseiam; a lógica e as funções SQL foram testadas isoladamente. A
  chamada real à OpenAI (custo/latência/qualidade) só é exercível no N8N do dono.

## Fonte da verdade da lógica

`n8n/lib/*.mjs` são os módulos **testados** (`node --test` em `n8n/test/`). Os nós Code do
workflow **espelham** essa lógica (inline, porque nós Code não importam arquivos). Ao alterar a
lógica: mude `lib/`, rode os testes, e **regenere** o workflow com `node n8n/build-workflow.mjs`.

## Estrutura

```
n8n/
├── lib/            # lógica testável: classifier, completude, openai, extract,
│                   #                  spreadsheet, taxonomia, normalize
├── test/           # node:test (30 casos)
├── build-workflow.mjs        # gerador do workflow (JSON válido)
├── workflow.e1-ingestao.json # workflow importável no N8N (E1 + E2-sombra)
└── README.md
```

## Próximas fatias

- **XLSX** no fallback (nó *Extract From File* → `spreadsheetToText`).
- **E3 — reconciliação** (Classe A aritmética em N1; B/C aproximam para humano).
- **Refino da extração por tipo** (linhas esperadas de cada demonstração) — guiado pelo golden set.
- Portal Vercel (fila de revisão para confirmar/corrigir a classificação N1, dashboard, export).
