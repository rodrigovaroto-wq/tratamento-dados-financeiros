# Como se trabalha neste repositório

Duas pessoas trabalham aqui ao mesmo tempo. As regras abaixo não são estilo — cada uma
existe porque a alternativa já produziu, ou produziria, dado errado em produção sem nenhum
sinal de erro. Leia antes de escrever a primeira linha.

## Quem decide o quê

O **dono** (Rodrigo) é o único que:

- **aprova e faz merge de PR**;
- **aplica migration** no Supabase de produção;
- **importa workflow** na instância do n8n;
- **roda teste ao vivo** (qualquer coisa que chame a OpenAI).

Se você não é o dono, você **escreve e testa** essas coisas, e para aí. Não é burocracia:
os três últimos itens são **ações globais e irreversíveis** sobre um ambiente
compartilhado — um banco, uma instância de n8n, uma conta de OpenAI com orçamento no fim.
Aplicar uma migration no meio do teste de outra pessoa muda o schema debaixo dela.

## Faixas de numeração das migrations

| Faixa | De quem |
|---|---|
| `0001`–`0034` | já aplicadas, **não tocar** |
| `0035`–`0099` | reservada ao **dono** |
| `0100`+ | **estagiário / colaborador** |

Confira `db/migrations/` antes de criar o arquivo e **nunca reaproveite um número
existente**. Buraco na sequência (`0034` → `0100`) é o estado esperado, não erro.

**Por que a faixa existe:** duas migrations com o mesmo prefixo **não dão conflito de
merge**. O git aceita `0035_a.sql` e `0035_b.sql` de branches diferentes sem uma palavra, as
duas aplicam na ordem alfabética do sufixo, e o `db/README.md` — que é a ordem oficial de
aplicação — passa a mentir em silêncio. `db/test/run.sh` reprova prefixo duplicado antes de
aplicar qualquer coisa, então a colisão morre no PR; a faixa é o que evita chegar lá.

## Git

- **Branch + PR sempre.** Nunca push direto em `main`.
- O CI (`.github/workflows/suites.yml`) roda as quatro suítes em todo push e PR. **PR
  vermelho é regressão sua** — não peça revisão antes de estar verde.
- **`HANDOFF.md` é a memória do projeto** (2.500+ linhas) e o cabeçalho é o resumo de
  retomada. **Só acrescente seção nova**; não edite o cabeçalho nem as seções de sessões
  anteriores. Dois editando o topo conflita a cada rodada.

## As quatro suítes (rode antes de pedir revisão)

```bash
node --test 'n8n/test/*.test.mjs'                      # 162 asserts — libs e nós simulados
./portal/node_modules/.bin/tsx portal/scripts/verificar-export.mts   # 352 — invariantes do .xlsx entregue
db/test/run.sh                                          # 34 migrations do zero + testes SQL
E2E_PSQL=1 ./portal/node_modules/.bin/tsx test/e2e/run.mts          # 24 — costura extração → banco → export
```

Contadores acima são o estado atual: se um número **cair**, você apagou cobertura.

Insumos e pré-requisitos:

```bash
# O verificar-export e o e2e precisam do book sintético (gera pdf/ + GABARITO.json,
# NÃO versionados). Sem isto, ENOENT no GABARITO.json não é bug, é insumo faltando.
cd test-data/book-vertentes && PYTHONPATH=. python3 gerar.py

# db/test/run.sh precisa de um Postgres 16 local. É descartável — recria o banco
# a cada execução e NÃO toca no Supabase.
```

Use `tsx` pelo caminho do `node_modules/.bin`, **não `npx tsx`**: no CI o `npx` baixou uma
versão do registro em vez de usar a do lock, e a suíte passou a depender do que estivesse
publicado no dia.

## Iterar de graça — o orçamento da OpenAI está no fim

`test-data/book-vertentes` **gera PDFs de demonstrações sintéticas localmente, sem IA**
(reportlab), com gabarito. É o caminho para exercitar o pipeline sem gastar um token. Toda
descoberta que puder acontecer contra fixture deve acontecer contra fixture; teste ao vivo é
para **confirmar**, não para explorar — e é do dono.

## Disciplina de teste que o repo já exige

- **Lógica de n8n vive em `n8n/lib/*.mjs`** (é a fonte da verdade, e é o que os testes
  cobrem) e é **espelhada à mão** nas strings de código dos nós Code em
  `n8n/build-workflow*.mjs`, porque nó Code do n8n não importa arquivo. Mudou `lib/`:
  rode a suíte n8n **e regenere** (`node n8n/build-workflow.mjs` + os dois outros
  geradores) **e commite o JSON**. O CI compara o gerado com o commitado — mirror
  desatualizado já causou bug real em produção.
- **Nada de data do sistema em gerador.** `new Date()` num gerador faz o JSON mudar sozinho
  na virada do mês e deixa o CI vermelho por não-motivo. Já aconteceu; use data de
  referência fixa.
- **Teste que não pode falhar não prova nada.** Antes de dizer que um teste cobre um
  defeito, **ligue o defeito de novo e veja o teste reprovar**. Duas fixtures deste projeto
  nasceram vazias — passavam com o bug ligado — e criaram a impressão de cobertura onde não
  havia nenhuma.
- **Nomes e comentários em português**, como o resto do repositório.

## Onde as coisas ficam

| Área | Arquivos |
|---|---|
| Extração / n8n | `n8n/lib/*.mjs`, `n8n/build-workflow*.mjs`, `n8n/test/` |
| Banco | `db/migrations/`, `db/test/`, `db/README.md` |
| Portal e export .xlsx | `portal/src/`, `portal/src/lib/export.ts`, `portal/src/lib/statement-templates.ts` |
| Checklist / completude | `n8n/lib/completude.mjs`, `portal/src/lib/status.ts`, `portal/src/app/casos/[id]/revisao/actions.ts`, `fn_recomputar_completude` e `checklist_item_status` (nascem na `0001`/`0004`) |
| Decisões e histórico | `HANDOFF.md`, `docs/`, `f0/` |

Antes de mexer numa área, leia o que o `HANDOFF.md` já diz sobre ela. Boa parte do que
parece defeito novo é defeito **conhecido, com causa registrada** — e algumas "correções"
óbvias já foram tentadas e revertidas por motivo documentado.
