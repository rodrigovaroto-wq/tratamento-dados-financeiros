# Onde paramos — troca de provedor de IA (OpenAI → Google Gemini)

**Data:** 2026-08-24. **Para que serve:** retomar a análise da PRIMEIRA rodada real com o
Gemini, num chat novo, sem reler nada.

> Este arquivo mora no repositório de propósito. Ele nasceu como anexo de chat, e anexo de
> chat é a forma mais fácil de perder um handoff: quem assume tem acesso ao REPOSITÓRIO,
> não à conversa. É o mesmo motivo de `docs/PROMPT_CONTINUACAO.md` existir — a diferença é
> que aquele é o prompt genérico de retomada e este é a tarefa específica de agora.
>
> **Quando ele deixar de valer, apague-o.** Um handoff velho no repositório é pior que
> nenhum: ele manda a próxima sessão começar por um trabalho que já acabou. O cabeçalho do
> `HANDOFF.md` passou 17 PRs mentindo por não ter sido apagado a tempo.

Branch de trabalho da troca: `claude/switch-ai-api-kcwcq7`.

**Leia primeiro:** `ESTADO.md` (seção "O PROVEDOR DE IA VIROU ESCOLHA", no topo) e
`docs/CUSTO_IA.md` (último adendo). Eles têm a narrativa completa. O `HANDOFF.md`
é histórico e NÃO precisa ser lido para retomar.

---

## O que já está no `main` (5 PRs, todos verdes e mergeados)

| PR | O que levou |
|---|---|
| #166 | A troca em si: `n8n/lib/provedor.mjs` — o provedor virou dado, e as diferenças de dialeto viraram 7 funções. Padrão: **Google, `gemini-3.5-flash-lite`**, API nativa (não a camada de compatibilidade). A OpenAI continua no catálogo e testada: `IA_PROVEDOR=openai node n8n/build-workflow.mjs` |
| #167 | `diagnosticar-ia.mjs --modelos`: GET no catálogo da conta, zero token, confere se o id do modelo existe |
| #168 | A mesma checagem dentro do `workflow.diagnostico-ia.json` (nó `Listar Modelos`), porque **o dono não usa terminal** |
| #169 | `thoughtsTokenCount` conta como saída — toda a linha 3.x do Gemini tem `thinking: true`, e o custo estava subdeclarado |
| #170 (ABERTO) | A estimativa de tempo do portal + o cartão de falha em português. Ver abaixo |

**Medido** (`node n8n/medir-custo-book.mjs`, mesmos 38 PDFs, só trocando a tabela de preço):
lote de US$ 1,2932 → **US$ 0,2821**; documento mais caro US$ 0,1725 → **US$ 0,0459**;
intervalo entre chamadas ~33s → **8s**. **Atenção:** esses números foram calculados
ANTES da correção do #169, então são um **piso** — não contam o token de raciocínio.

---

## O PR #170, que está aberto agora

Dois trabalhos no mesmo ramo, ambos com CI passando na última verificação local:

1. **A estimativa de tempo do portal.** Dizia "29 minutos" para um lote de 38 que leva ~8
   (`SEGUNDOS_POR_DOCUMENTO` era 45, herdado dos ~33s do gpt-4o). Agora deriva da cadência,
   com espelho travado em `n8n/test/workflow-sim.test.mjs`.
2. **O cartão de falha em português** (`portal/src/lib/falha-em-portugues.ts`), pedido do dono:
   quando o sistema para, a tela tem de dizer que parou, apontar o problema, em linguagem
   simples. Cobre três casos: falha registrada, **parada sem registro** (detectada por
   ausência de progresso, porque o Error Workflow do n8n é passo manual) e **lote que
   terminou vazio**. Suíte própria: `portal/scripts/verificar-mensagem-de-falha.mts` (37 asserts, no CI).

**Confira o CI do #170 antes de qualquer coisa.** O último commit (`e04a79c`) conserta uma
reprovação do Sonar por duplicação. Se estiver verde, o dono mergeia.

---

## A TAREFA DE AGORA: analisar a primeira rodada real com o Gemini

O dono acabou de rodar o `book-canastra` (38 PDFs sintéticos) num mandato novo chamado
**"Teste v47 - Grupo Canastra + Gemini API"**. A run terminou. Ele quer uma análise
exaustiva: o que está excelente, o que otimizar, sem deixar nada em aberto.

**Você tem o gabarito.** `test-data/book-canastra/pdf/GABARITO.json` é a resposta certa,
conta a conta — gere o book com
`cd test-data/book-canastra && PYTHONPATH=. python3 gerar.py` (precisa de
`pip install reportlab==5.0.1`). Isso permite comparar a extração linha a linha, não só
olhar se "parece certo".

### O que pedir ao dono, em ordem de valor

**1. A saída do nó `Resumo de Custo` do n8n** (um item, JSON pequeno). É o de maior
informação por byte: traz `custo_total_usd`, `custo_extracao_usd`, `custo_classificacao_usd`,
tokens de entrada/saída/cache, `cobertura_do_lote`, `documentos_fatiados`,
`documentos_com_falha`. Responde de uma vez as duas perguntas em aberto (abaixo).

**2. Os dois arquivos `.xlsx` exportados pelo portal.** Audite com
`./portal/node_modules/.bin/tsx portal/scripts/auditar-xlsx.mts <arquivo.xlsx>`
(10 itens automáticos) e confronte com o `GABARITO.json`.

**3. Duas consultas SQL no Supabase** (o dono roda no SQL Editor). Estão no repositório,
prontas e conferidas contra o schema real:

- `db/diagnostico_rodada.sql` — raio-X por documento: tipo, confiança, fonte da
  classificação, pares conta-coluna, contas distintas, colunas, escala, moeda, seções
  canônicas, pendências abertas e a justificativa da IA;
- `db/pendencias_do_mandato.sql` — toda pendência aberta, com descrição e motivo,
  ordenada por severidade.

Em ambas, troque o nome do mandato na primeira linha.

**NÃO peça o JSON completo da execução do n8n:** ele carrega o base64 de todo PDF
(`content_part`), são dezenas de MB, e os documentos você já tem no repositório.

### As duas perguntas que a rodada foi feita para responder

| Pergunta | Onde está | Por que importa |
|---|---|---|
| **Quantas chamadas o lote fez** — 38 ou ~44? | `Resumo de Custo` → `documentos_fatiados` | O fatiamento **nunca foi visto ligado em produção** (0 de 38 na sessão 52). É o item nº 1 das onze provas do B1 |
| **`thoughts_tokens` e `custo_usd`** de um documento denso (`17_Livro_Razao`) | saída do nó `Parse Extracao` | Decide duas coisas: se vale subir `MAX_OUTPUT_TOKENS` (o catálogo do Gemini declara 65.536, e o nosso é 16.384 herdado do gpt-4o) e se vale desligar o pensamento na extração |

---

## Decisões em aberto, para tomar COM a medição

1. **Subir `MAX_OUTPUT_TOKENS` de 16.384 para algo maior?** A favor: com `thinking` ligado,
   o raciocínio come parte do orçamento antes do JSON, e o documento mais denso já pede
   17.875 tokens de saída. Contra: o fatiamento deixaria de disparar neste book, e é a única
   chance de vê-lo funcionando numa rodada real. **Se mexer**, `TETO_SAIDA_TOKENS` em
   `n8n/lib/cobertura.mjs` tem de acompanhar — há um teste que trava os dois iguais.
2. **Desligar o pensamento na extração** (`thinkingConfig.thinkingBudget: 0`)? Só com o
   número do `thoughts_tokens` na mão. **Risco não verificado:** se o modelo recusar o
   campo, TODA chamada vira 400 — vale testar com uma chamada antes de mexer no workflow.
3. **Estender o `eslint` ao diretório `n8n/`.** Hoje ele roda com `working-directory: portal`,
   então os geradores e libs do n8n só são vistos pelo Sonar. Foi assim que um import morto
   viveu dois commits. É fatia própria: provavelmente acende uma lista de achados antigos.

---

## O que só o dono destrava

- **O teto de gasto do projeto no Google.** É configuração de conta e **não se herda** da
  OpenAI: a conta nova começa sem teto, e essa é a defesa dura.
- **Zero-retention / DPA com o Google** antes de dado real de cliente. Se a chave for do
  **nível gratuito**, o provedor usa o conteúdo para melhorar os produtos dele — então
  **só material sintético** nessa chave (`docs/10_DADOS_RETENCAO_E_LGPD.md`).
- **A sonda das migrations.** O dono diz ter aplicado a `0138` e a `0139`; o `ESTADO.md`
  ainda registra o banco na `0137`. Rode `fn_instalacao_conferir` contra o banco e
  atualize o `ESTADO.md` com o que ela responder — a lição da `0133`, que três documentos
  davam por aplicada e não estava, é que **documento não é medição**.

---

## Como este repositório trabalha (importa mais que qualquer item acima)

- **Medir antes de escrever código já desmentiu a correção anotada** em quase toda rodada.
  Está no `ESTADO.md` como método, não anedota.
- **Todo espelho é travado por teste.** Nó Code do n8n não importa módulo, então funções da
  lib são embutidas por `toString()` e `n8n/test/espelho-inline.test.mjs` confere as 26.
- **Comentário explica POR QUE, com o incidente que o originou** — não o que o código faz.
- **Suítes:** `node --test 'n8n/test/*.test.mjs'` (340) · os `portal/scripts/verificar-*.mts` ·
  `test/e2e/run.mts` (46) · `test/e2e/variacoes.mts` · `db/test/run.sh`. Os quatro geradores
  de workflow têm de ser idempotentes (o CI compara o JSON regerado).
- **Postgres local:** `service postgresql start`, e `PGHOST=localhost PGUSER=postgres PGPASSWORD=postgres`.
