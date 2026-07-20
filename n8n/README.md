# Camada N8N — Fatia 1 (E1 — Ingestão + E2 — Extração-sombra)

O N8N é o **orquestrador stateless** (docs/02, trava de stack nº 1): recebe o upload em lote,
classifica cada arquivo e chama as funções do Postgres (`db/migrations/0004-0006`) que cuidam
do estado. A ingestão é feita **pelo próprio N8N** (Form Trigger) — sem Vercel nesta fatia.

## O que roda (fluxo do `workflow.e1-ingestao.json`)

```
Intake (Form: nome do mandato + upload de N arquivos)
  → Upsert Caso ............. fn_upsert_caso(nome) → caso_id   [Postgres: NÃO repassa binário]
  → Listar Arquivos ......... fan-out: 1 item por arquivo (binário lido do FORM, chave 'data')
  → Classificar Nome ........ nome + regras → {tipo, período, assinado, confiança} [preserva binário]
  → Preparar Conteudo ....... parte multimodal p/ TODOS: pdf→file, imagem→image_url,
       │                      csv→texto, xlsx→nota [preserva binário]
       ├─→ Upload Storage ... POST no bucket privado (RAMO LATERAL — nada depende da saída)
       └─→ Precisa Fallback? ... confiança < 0.7 ou tipo desconhecido?
             ├─ sim → Montar Req Classif → OpenAI Classificar → Parse (recompõe contexto)
             └─ não → direto
  → Registrar Documento ..... fn_registrar_documento(...) → {documento_id, documento_versao_id}
        ├─ Recomputar Completude ... fn_recomputar_completude(caso_id) → Portão 1 + status
        └─ [E2] Montar Req Extracao → OpenAI Extrair → Parse → Gravar Campos (Sombra, N0)
```

Autonomia (docs/01): classificação nasce em **N1** (sugestão; humano confirma na fila de
revisão — próxima fatia); **extração (E2) nasce em N0 (sombra)** — registra para medir, não
decide, não entra em base sem aceite humano (anti-ancoragem).

## Regras de fluxo do N8N (aprendidas em teste real — a topologia depende delas)

1. **Node Postgres não repassa binário** — a saída são as linhas da query. Por isso `Listar
   Arquivos` lê os arquivos por referência direta ao Form (`$('Intake (Form)')`), não do
   `$input`.
2. **Node HTTP Request substitui o item pela resposta da API** (perde json e binário). Por
   isso o `Upload Storage` é **ramo lateral** (nada consome a saída dele) e, após as chamadas
   OpenAI, o contexto volta por `$('Nome do Node').item`.
3. **Modos dos nós Code:** `Listar Arquivos` = "Run Once for All Items" (único fan-out; usa
   `$input.first()`; retorna **array**). Os outros 6 = "Run Once for Each Item" (1:1; usam
   `$input.item`; retornam **objeto único** `{json,...}` — array nesse modo dá o erro
   `A 'json' property isn't an object`).
4. **Code que repassa arquivo devolve `binary` explicitamente** — retornar só `{json}`
   descarta o binário (`Classificar Nome` e `Preparar Conteudo` preservam).

## Como usar

1. **Aplicar as migrations do banco** (`db/README.md`) — em caso de dúvida sobre o estado das
   funções, rodar a `0006` (reset idempotente).
2. **Importar como workflow NOVO**: Workflows → Add workflow → *Import from File* →
   `n8n/workflow.e1-ingestao.json`.
   > ⚠️ **Não cole/importe por cima de um workflow existente.** Se o canvas já tiver nodes com
   > os mesmos nomes, o N8N renomeia os novos com sufixo (ex.: `Intake (Form)1`) — e os códigos
   > referenciam nodes **pelo nome exato** (`$('Intake (Form)')`), então o sufixo quebra tudo.
   > Antes de reimportar, **apague ou arquive o workflow antigo**.
3. **Configurar credenciais** nos **4 nós Postgres** e **variáveis de ambiente** (ver abaixo).
4. **Conferir os Query Parameters** dos 4 nós Postgres (o import pode não preenchê-los — tabela
   no Troubleshooting).
5. Abrir a URL do **Form Trigger**, informar o nome do mandato e subir os arquivos.
6. Conferir no banco: `caso`, `documento`, `checklist_item_status`, `pendencia`,
   `evento_auditoria`, `campo_extraido` populados; status do caso avançando conforme a
   completude.

## Troubleshooting conhecido (achados testando no N8N real)

**`No output data returned` no Listar Arquivos:** o node lia o binário do `$input` (= saída do
Postgres, que não repassa binário) → lista vazia. Corrigido: lê do Form por referência. Se o
Form realmente não entregar arquivos, o node agora **lança erro explícito** em vez de parar em
silêncio.

**Erro `there is no parameter $1` num node Postgres:** o campo **"Query Parameters"** (em
Options) não veio preenchido do import. Abra o node → **"+ Add option"** → **"Query
Parameters"** → cole a expressão correspondente:

| Node | Query Parameters |
|---|---|
| Upsert Caso (Postgres) | `={{ [$json["Mandato (nome do caso)"]] }}` |
| Registrar Documento | `={{ [$json.caso_id, $json.entidade \|\| null, $json.periodo_tipo \|\| null, $json.periodo_ref \|\| null, $json.tipo_taxonomia \|\| null, $json.confianca, $json.fonte, 'supabase_storage', $json.caso_id + '/' + $json.nome_original, $json.nome_original, $json.assinado, null, 'ok', $json.justificativa \|\| null] }}` (14º parâmetro = justificativa; a query usa `p_justificativa=>$14` para pular o `p_threshold` que fica no default) |
| Recomputar Completude | `={{ $('Upsert Caso (Postgres)').first().json.caso_id }}` |
| Gravar Campos (Sombra) | `={{ [$json.documento_versao_id, JSON.stringify($json.campos)] }}` |

**Erro `function fn_upsert_caso(unknown) does not exist`:** o driver do N8N envia o parâmetro
sem tipo; a resolução falha sem cast. As queries já vêm com `::tipo` em cada `$N`.

**Erro `function fn_upsert_caso(text) does not exist` (com o cast!):** as funções no banco
estão com assinatura divergente (aplicações parciais/repetidas das migrations). Rodar
`db/migrations/0006_reset_funcoes.sql` — derruba qualquer versão e recria do zero (idempotente).

**Nodes com sufixo `1` no nome (`Upsert Caso (Postgres)1`):** o workflow foi importado/colado
por cima de outro. As referências `$('Nome')` quebram. Apagar o antigo e reimportar limpo.

**Erro `access to env vars denied` (num node Code ou expressão):** o N8N bloqueia `$env` por
padrão (`N8N_BLOCK_ENV_ACCESS_IN_NODE`). O workflow atual **não usa `$env`** — se esse erro
aparecer, é versão antiga: reimportar, ou trocar manualmente `($env.OPENAI_MODEL||'gpt-4o')` →
`'gpt-4o'` nos nós `Montar Req *` e configurar credenciais nos nós HTTP (ver seção
Credenciais).

**Erro `Credentials not found` nos nós OpenAI:** a Authentication está em *Predefined
Credential Type → OpenAI* mas a credencial não existe (ou é do tipo errado). Corrigido: os
nós vêm configurados como *Generic Credential Type → Header Auth* — criar a credencial Header
Auth (Authorization / Bearer sk-...) e selecionar.

**Erro `Bad request` no Upload Storage com a credencial da OpenAI selecionada:** a credencial
de Header Auth escolhida no node era a da OpenAI (manda a chave errada para o Supabase). Criar
uma credencial Header Auth **separada** para o Supabase (ver Credenciais acima).

**Erro `The resource you are requesting could not be found` no Upload Storage:** a URL está
apontando para o **painel** do Supabase (`supabase.com/dashboard/...`) em vez da **API**
(`<ref>.supabase.co/storage/v1/...`). Ver seção Credenciais acima.

**Erro `Bad request - please check your parameters` no Upload Storage mesmo com URL e
credencial corretas:** falta o header **`apikey`**. O gateway do Supabase exige esse header
**além** do `Authorization` (a credencial Header Auth só injeta um dos dois) — sem ele,
rejeita antes de processar o upload. Adicionar um header `apikey` com a mesma service role key
(já vem como campo no node, com placeholder para editar).

**Erro `Converting circular structure to JSON` / `_httpMessage closes the circle` ao rodar o
workflow inteiro (não ao testar node a node):** **não é bug nosso** — é um problema de longa
data do próprio node HTTP Request do N8N ao lidar com dados binários em certas configurações
(GitHub `n8n-io/n8n#3089`, `#10096`). Confirmado via console do navegador: é o **editor do
N8N** travando ao tentar serializar os dados de execução dos nodes HTTP, não uma falha de rede
com o Supabase/OpenAI. Limpar o cache de execução e recarregar a página **não resolve** — é
reproduzível. Ver seção "Upload Storage — pendência conhecida" abaixo.

**Erro `401 - "Your authentication token is not from a valid issuer"` (`invalid_issuer`) nos
nós `OpenAI Classificar`/`OpenAI Extrair`:** a credencial Header Auth selecionada no node não é
a chave da OpenAI (`sk-...`) — é um **JWT** (token de 3 partes com um campo `iss`), tipicamente
a chave `anon`/`service_role` do **Supabase** selecionada por engano (o inverso do bug já visto
no Upload Storage). Corrigir: no node, abrir a credencial Header Auth e conferir que o valor é
`Bearer sk-...` da OpenAI — criar uma credencial separada da do Supabase se ainda não existir.

**Documento com nome sugestivo (ex.: "BALANÇO ACUMULADO 2025.pdf") classificado com
`tipo_taxonomia` inválido (ex.: `"BAL"` em vez de `"BALANCO"`) → `insert or update on table
"documento" violates foreign key constraint "documento_tipo_taxonomia_fkey"` no Registrar
Documento:** bug real encontrado testando com documento real (2026-07-20) — o schema JSON
enviado à OpenAI (nó `Montar Req Classif`) **não travava `tipo_taxonomia`/`periodo_tipo` num
`enum`** (era só `{type:'string'}`), então a IA ficou livre para inventar abreviações (`"BAL"`)
em vez de usar exatamente um código da taxonomia — e até confundir `periodo_tipo` com a
referência (`"12M25"` em vez de `"anual"`). Corrigido em `n8n/build-workflow.mjs`: o enum de
`tipo_taxonomia` agora é **importado diretamente** de `codigosConhecidos()`
(`lib/openai.mjs`), não copiado à mão — e há um teste (`workflow-sim.test.mjs`) que trava essa
regressão. **Reimporte o workflow atualizado** (o node `Montar Req Classif` mudou) para pegar o
fix; nenhum dado ficou corrompido no banco porque o `insert` falhou e reverteu (a
constraint fez o trabalho dela).

## Upload Storage — pendência conhecida (node desabilitado)

O node **`Upload Storage` vem desabilitado por padrão** neste workflow (2026-07-17) por causa
do bug de plataforma acima. Como ele é um **ramo lateral** (nenhum outro node depende da sua
saída — ver teste `workflow-sim.test.mjs`), desabilitá-lo **não afeta** classificação,
extração, completude nem pendências — só significa que a cópia do arquivo não é enviada ao
Supabase Storage por enquanto (os arquivos originais continuam disponíveis onde foram
enviados no Form).

**Duas alternativas para resolver, fora do HTTP Request genérico do N8N:**

1. **Community node `n8n-nodes-supabase`** — node dedicado com operação de upload para
   Storage, usando a lib oficial do Supabase por baixo (evita o bug do HTTP Request com
   binário). Instalar em **Settings → Community Nodes → Install → `n8n-nodes-supabase`**
   (funciona em instâncias self-hosted, incluindo PikaPods, sem precisar de acesso ao
   servidor). Depois de instalado, trocar o node `Upload Storage` por ele, apontando para o
   mesmo bucket `documentos`.
2. **Mover o upload para o portal Vercel** (fatia futura) — usar o SDK oficial do Supabase em
   JavaScript (`@supabase/supabase-js`) direto no backend do portal, que não tem as
   limitações do node HTTP Request do N8N. Fica natural já que o portal também vai lidar com
   upload em lote na fatia seguinte.

**Para reabilitar** depois de adotar uma das alternativas: em `build-workflow.mjs`, localizar
o node `Upload Storage` e trocar/remover `disabled: true` (ou substituir o node inteiro pelo
community node, se for esse o caminho).

## Credenciais (configurar no N8N — o workflow NÃO usa variáveis de ambiente)

> O N8N **bloqueia `$env` por padrão** em nós Code e expressões (erro *"access to env vars
> denied"*). Por isso o workflow usa só **credenciais nativas** + 1 edição de URL:

- **Postgres (Supabase, Session Pooler)** — credencial nos **4 nós Postgres** (Upsert Caso,
  Registrar Documento, Recomputar Completude, Gravar Campos). Reaproveitar do `clipping-news`.
  Pegadinhas herdadas: usar o **Session Pooler** (IPv4 + SSL), usuário com sufixo
  `.projectref`. O N8N usa conexão de serviço, que **ignora RLS** por design (é o orquestrador)
  — ver `db/migrations/0003`.
- **OpenAI** — nos nós `OpenAI Classificar` e `OpenAI Extrair`: Authentication já vem como
  *Generic Credential Type → Header Auth*; criar (ou reaproveitar) uma credencial **Header
  Auth** com **Name=`Authorization`, Value=`Bearer sk-...`** (a palavra `Bearer` + espaço antes
  da chave — sem isso a OpenAI recusa) e selecioná-la nos dois nós. Modelo fixado em `gpt-4o`
  no código (trocar nos nós `Montar Req *` se quiser outro).
- **Upload Storage** — duas configurações no node:
  1. **URL:** trocar `SEU-PROJETO` pela ref real do projeto Supabase — **atenção:** é a URL da
     **API** (`https://<ref>.supabase.co/storage/v1/object/documentos/...`), **não** a URL do
     painel (`https://supabase.com/dashboard/project/<ref>/...`, que é só para humanos no
     navegador). A ref aparece em ambas as URLs; confirme também em Settings → API → Project URL.
  2. **Credencial:** Authentication já vem como *Generic → Header Auth*; criar credencial
     **Header Auth NOVA** (não reaproveitar a da OpenAI!) com Name=`Authorization`,
     Value=`Bearer <service role key>` — pegue em Settings → API → `service_role` (a chave
     secreta, não a `anon`).
  3. **Header `apikey`:** o gateway do Supabase exige esse header **além** do `Authorization`
     (a credencial só injeta um). No campo **Headers** do node, junto ao `x-upsert` já
     presente, colar a **mesma service role key** no header `apikey` (o valor já vem com um
     placeholder `COLE_A_SERVICE_ROLE_KEY_AQUI` para editar). Sem ele, a API responde `400
     Bad Request` mesmo com URL e credencial corretas.
- **Sem a credencial/URL do Upload**, o node falha (e para a execução — falha explícita de
  propósito: linha no banco apontando para arquivo inexistente seria um "falso-limpo"). Para
  um dry-run sem storage, **desative** o node Upload Storage.
- **Sem a credencial OpenAI**, os nós OpenAI falham mas **não derrubam o workflow**
  (`onError: continue`): o parse produz confiança 0 → pendência de classificação / extração
  vazia (fail-safe coerente com a doutrina).

## Fallback OpenAI (conteúdo) — como funciona

Quando o classificador por nome não tem confiança, a chamada leva o **conteúdo real do
arquivo** (montado no `Preparar Conteudo`, que roda para todos):
- **PDF** → parte `file` (base64) — o modelo lê texto + páginas.
- **Imagem** (scan/foto PNG/JPG) → parte `image_url` (base64).
- **CSV** → decodificado e parseado inline (vira texto tabular).
- **XLSX** → hoje envia uma nota de texto. Para habilitar: inserir um nó *Extract From File*
  (spreadsheet) antes de `Preparar Conteudo` e usar `spreadsheetToText(rows)`
  (`n8n/lib/spreadsheet.mjs`). Ponto explícito de adaptação no N8N.
- Saída sempre via **Structured Outputs** (JSON Schema estrito). Continua **N1**: sugestão
  para revisão humana.

## Qualidade da classificação — ajustes feitos a partir de teste real (2026-07-17)

Testando com um documento real (`BALANÇO ACUMULADO 2025.pdf`), a classificação ficou incerta
(confiança 0.5, tipo `DESCONHECIDO`) mesmo o nome citando "Balanço" claramente. Três ajustes:

1. **Período mais flexível** (`n8n/lib/classifier.mjs`): reconhece agora ano isolado ("2025")
   e intervalo de anos ("2021-2025", "2021 a 2025" — expandido para a lista inteira, não só os
   extremos). Um ano isolado é tratado como sinal **fraco** (soma só +0.05 à confiança, contra
   +0.3 dos formatos estruturados) — de propósito: "tipo no nome + ano solto" não deve, sozinho,
   pular a verificação pela IA (ex.: `BALANCO` + `2025` fica em 0.65, abaixo do limiar 0.7).
2. **Merge de confiança nome-vs-IA** (`n8n/lib/merge.mjs`): quando o fallback roda, o resultado
   final fica com a **maior confiança** entre nome-do-arquivo e IA — não é mais sempre a IA que
   vence. Entidade e assinado da IA são sempre aproveitados (o nome nunca informa isso). Se a
   chamada à OpenAI falhar tecnicamente, o sistema não zera a confiança à toa — mantém o que o
   nome já sabia.
3. **Prompt menos conservador + justificativa objetiva** (`n8n/lib/openai.mjs`): antes, o
   prompt incentivava "se incerto, use DESCONHECIDO" — na prática, isso fazia o modelo desistir
   fácil demais. Agora ele é instruído a **sempre tentar um palpite específico** (reservando
   `DESCONHECIDO` só para documento genuinamente ilegível/não-financeiro), e o campo
   `justificativa` passou a ser obrigatório e objetivo (o que ele viu/não viu no documento).
   Essa justificativa agora **aparece na descrição da pendência** de classificação
   (`db/migrations/0007`), então o humano revisando já vê o motivo, não só o número de confiança.

## ⚠️ Estado honesto desta entrega

- **Executado ponta a ponta no N8N real do dono (2026-07-17):** Upsert Caso → Listar Arquivos
  → Classificar Nome → Preparar Conteudo → (fallback OpenAI) → Registrar Documento →
  Recomputar Completude → Extração E2 → Gravar Campos — **todos passaram** com um caso real
  (arquivos com nome/acento reais, ex. "BALANÇO ACUMULADO 2025.pdf").
- **Upload Storage: desabilitado** por um bug de plataforma do N8N (ver seção dedicada acima)
  — pendência de arquitetura, não de lógica.
- **Caminho determinístico (nome → registro → completude): completo, testado e validado ao
  vivo** — lógica com testes unitários, funções do banco exercitadas num Postgres real, e
  confirmado no N8N real.
- **Fluxo entre nós: simulado por teste** — `n8n/test/workflow-sim.test.mjs` executa os códigos
  **reais** do JSON gerado com a semântica de passagem de dados do N8N (Postgres sem binário,
  HTTP substituindo o item, referências `$('Node')`), nos dois ramos.
- **Fallback OpenAI (PDF/imagem/CSV) e Extração E2 em N0/sombra: completos**, cobertos por
  testes de corpo/schema/parse e confirmados no N8N real.
- **Pendência: XLSX** — falta o *Extract From File* (ver acima).

## Fonte da verdade da lógica

`n8n/lib/*.mjs` são os módulos **testados** (`node --test` em `n8n/test/`). Os nós Code do
workflow **espelham** essa lógica (inline, porque nós Code não importam arquivos). Ao alterar a
lógica: mude `lib/`, rode os testes, e **regenere** com `node n8n/build-workflow.mjs` — o teste
`workflow-sim` valida o JSON regenerado.

## Estrutura

```
n8n/
├── lib/            # lógica testável: classifier, completude, openai, extract,
│                   #                  spreadsheet, taxonomia, normalize
├── test/           # node:test (41 casos, incl. simulação do workflow)
├── build-workflow.mjs        # gerador do workflow (JSON válido)
├── workflow.e1-ingestao.json # workflow importável no N8N (E1 + E2-sombra)
└── README.md
```

## Próximas fatias

- **Resolver o Upload Storage** (community node `n8n-nodes-supabase` ou mover para o portal Vercel).
- **XLSX** no fallback (nó *Extract From File* → `spreadsheetToText`).
- **E3 — reconciliação** (Classe A aritmética em N1; B/C aproximam para humano).
- **Refino da extração por tipo** (linhas esperadas de cada demonstração) — guiado pelo golden set.
- Portal Vercel (fila de revisão para confirmar/corrigir a classificação N1, dashboard, export).
