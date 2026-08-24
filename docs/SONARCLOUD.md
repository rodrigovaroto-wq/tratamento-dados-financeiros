# SonarQube Cloud — como está ligado, o que ele mede, e o que ele não mede

**Data:** 21/08/2026 · **Projeto:** `rodrigovaroto-wq_tratamento-dados-financeiros`
· **Organização:** `oria-partners` · **Primeira análise:** 21/08/2026 21:45 UTC, sobre o `566810e`.

## O estado, conferido pela API e não pela memória

| | |
|---|---|
| **Modo** | **Análise Automática** (`detectedCI: null` — não há scanner em CI) |
| **Gatilho** | push na branch padrão; nada no `.github/workflows/` |
| **Quality Gate** | `NONE` — nenhum portão avaliado até agora |
| **Visibilidade** | pública: a API de leitura responde **sem token** |
| **Análises até hoje** | **uma** |

**Não é preciso token para LER.** É por isso que `portal/scripts/sonar-achados.mjs`
funciona de qualquer sessão, sem segredo nenhum:

```bash
node portal/scripts/sonar-achados.mjs                    # resumo por regra/tipo/linguagem
node portal/scripts/sonar-achados.mjs --tipo=BUG         # só bugs
node portal/scripts/sonar-achados.mjs --regra=typescript:S2871
```

Token só é necessário para **escrever** (marcar achado como falso positivo) ou no
dia em que o projeto virar privado. O script já usa `SONAR_TOKEN` se ele existir.

## A triagem dos 3.091, porque o número sozinho engana

A primeira análise devolveu **3.091 achados em aberto**. Ler isso como "3.091
erros no código" seria errado, e a conta mostra por quê:

| Fonte | Achados | O que é |
|---|---|---|
| `db/` lido como **Oracle PL/SQL** | 1.726 | dialeto errado; e é código imutável ou gerado |
| `test-data/capturas` — **um** arquivo | 591 | HTML salvo do navegador, evidência de rodada |
| **subtotal fora de escopo** | **2.317 (75%)** | |
| `portal/`, `n8n/`, `test/`, geradores | ~770 | **aqui há sinal** |

### O dialeto errado é o achado mais importante da conexão inteira

**No Oracle a string vazia é NULL. No PostgreSQL não é.** O analisador de PL/SQL
acusou `NullComparison` — "use IS NULL" — em três linhas corretas:

```sql
where padrao = '' and tipo_taxonomia is null    -- 0128:389
if v_norm = '' then                             -- 0128:446
if coalesce(trim(p_autor), '') = '' then        -- 0128:681
```

As três estão certas neste banco. Um analisador que erra a semântica de `''` não
tem autoridade para opinar sobre o resto do SQL — e é por isso que `db/` sai do
escopo em vez de ganhar 1.726 exceções uma a uma.

Os **9 BLOCKER** da análise seguem a mesma linha: são `DELETE`/`UPDATE` sem
`WHERE` no *teardown* de `db/test/`, que roda contra banco local recriado do zero
a cada execução do `run.sh`. É o comportamento pretendido.

E há a parte que nenhum ajuste de regra resolve: `db/migrations` é **imutável**
(migration aplicada não se reescreve) e `db/schema.sql` é **gerado** pelo
`run.sh`. Achado nos dois é inacionável por construção.

## O escopo, e a limitação que obriga a forma dele

`.sonarcloud.properties` na raiz. Três coisas que custaram tempo e ficam escritas
para ninguém repetir:

1. **A Análise Automática ignora `sonar-project.properties`.** O arquivo que ela
   lê é `.sonarcloud.properties`. Criar o outro não dá erro — simplesmente não faz
   nada, que é pior.
2. **Não aceita curinga.** Nada de `**/*.sql`; só caminho literal. É por isso que
   a exclusão é `db` inteiro e não um padrão por extensão.
3. **Só vale na branch PADRÃO.** Enquanto este arquivo estiver só numa branch de
   trabalho, a análise continua medindo tudo.

```properties
sonar.exclusions=db,test-data/capturas
```

Os geradores Python dos books ficam **dentro** do escopo de propósito: o oráculo
das suítes é código de verdade.

## O que foi corrigido a partir dos achados (21/08)

Cinco, e cada um foi conferido no código antes — não aceito veredito de
ferramenta sem olhar:

| Regra | Onde | O que era |
|---|---|---|
| `typescript:S3923` | `portal/scripts/lib/avaliar-formula.mts:252` | `typeof v === "number" ? String(v) : String(v)` — o ternário não decidia nada |
| `typescript:S3923` | `portal/src/components/ceu-oria.tsx:253` | `intro ? 0.5 : 0.5` — idem, no canvas da abertura |
| `typescript:S2871` | `portal/src/app/casos/[id]/modelagem/page.tsx:804` | `sort()` sobre entradas de `Map`: o critério era `[secao, linhas]` estringado, com `[object Object]` dentro |
| `githubactions:S8544` | `.github/workflows/suites.yml` | `pip install reportlab` **sem versão** — o CI baixava a última do dia para gerar o **oráculo** das suítes |
| `tssecurity:S8705` | `portal/scripts/gerar-export-do-banco.mts` | `caso_id` do `argv` entrava cru em SQL por interpolação; passa a exigir UUID |

O `S8544` é o que mais importava e não parece: o book sintético é o gabarito
contra o qual as suítes medem, e ele era gerado por uma dependência sem versão
presa. Um release que mudasse a renderização não quebraria nada visivelmente —
mudaria o oráculo em silêncio.

## O que NÃO foi corrigido, e por quê

Registrar isto é parte do trabalho: "achado aberto" sem motivo escrito vira dívida
que ninguém consegue julgar depois.

- **`typescript:S2871` — os outros 9 `sort()`.** Conferidos um a um: ordenam
  **strings** (escalas, moedas, nomes de série). `sort()` lexicográfico sobre
  string é o comportamento certo. Onde havia número, o comparador já existia
  (`.sort((a, b) => a - b)` nos anos). Falso positivo por regra genérica.
- **`typescript:S6551` — 40 ocorrências de `String(formData.get(x) || "")`.**
  Real em tese: `FormData.get` devolve `string | File`, e `String(file)` daria
  `"[object Object]"`. Mas são 40 pontos em 15 *server actions* sem cobertura de
  teste, para um caso que exige um multipart forjado. Trocar tudo mecanicamente
  num código sem rede é o tipo de mudança que este repositório já pagou caro.
  Fica nomeado, para ser feito junto com um teste dessas ações.
- **`typescript:S1244` — comparação de ponto flutuante** em
  `verificar-transcricao.mts:186`. É um assert de teste, e `1234.56` parseado dá
  exatamente o mesmo *double* que o literal. Funciona; uma tolerância seria mais
  robusta, sem corrigir defeito nenhum.
- **`javascript:S5850` — precedência em regex** (`cobertura.mjs:168-169`). O
  `^cnpj\b|\bcnpj\s*[\d.]` faz exatamente o que o comentário ao lado diz que deve
  fazer. Agrupar não muda semântica, e o próprio arquivo avisa que "melhorar"
  esses filtros já quebrou coisa antes.
- **`typescript:S4624`/`S3358` — literais aninhados e ternários encadeados** (189
  juntos). São a forma como este código é escrito, com comentário ao lado. Regra
  de estilo, não de correção.

## A PASSADA RIGOROSA DOS 769 EM ESCOPO (21/08)

Depois das exclusões sobram **769 achados em 89 regras distintas**. Fui regra a
regra, com o nome oficial de cada uma puxado da API e o código aberto ao lado.
O resultado, em uma linha: **31 corrigidos, e o resto tem motivo escrito.**

### O que foi corrigido nesta passada

**Trabalho feito e jogado fora** — a classe de maior valor, porque não aparece em
teste nenhum:

| Onde | O que era |
|---|---|
| `export-modelagem.ts` | **dois `Map` preenchidos e nunca lidos** (`linhaDaPremissa`, `linhaDoRotulo`). E o comentário acima do primeiro afirmava *"é a célula delas que as linhas abaixo citam"* — uma referência cruzada que **não existia**. O mapa saiu e o texto que a prometia, também |
| `verificar-export.mts` | `numerosEscritos` juntava o endereço de toda célula numérica da Modelagem e **não conferia nada** — parecia cobertura e não era |
| `test/e2e/run.mts` | `versaoNova`, `Map` preenchido e nunca lido |
| `export-modelagem.ts` | `linhaData` nascia `4` e era sempre sobrescrito antes da primeira leitura; `escreverSeletorMacro` nascia noop e a reatribuição é **incondicional** (bloco nu, não `if`) |
| `modelo-institucional.ts` | `void gGW;` marcava como não usado um valor que **é** usado na 5794 |
| `book-vertentes/render.py` | `c25 = M.combinado(...) if False else None` — chamada desligada, nome nunca lido |
| `book-vertentes/demonstracoes.py` | `def soma(tipo_filtro)` nunca chamada, cujo corpo **ignorava o parâmetro** e repetia exatamente a linha de baixo |
| `medir-custo-book.mjs` | `TETO_SAIDA_TOKENS` importado e não usado |

> **A prova de que o código Python era mesmo morto:** depois de removê-lo, os
> geradores rodaram e as fixtures derivadas (`fixture_book_vertentes.sql`,
> `book-vertentes.json`, `fixture_book_canastra.sql`) saíram **byte-idênticas**.

**Armadilhas tornadas impossíveis** — o código estava certo; o que mudou é que
agora ele não convida ao erro:

- **7 `<button>` sem `type`** em `upload-form.tsx`. Conferido: estão em retornos
  antecipados, **fora** do `<form>`, então não havia risco de submit hoje. Ganham
  `type="button"` porque o dia em que alguém envolver isso num form o defeito
  nasce pronto e silencioso.
- **4 corpos de laço sem chaves** em `avaliar-formula.mts` e `verificar-export.mts`
  (`while (…) x;` dentro de uma linha densa). Comportamento idêntico; a segunda
  linha que alguém acrescentar deixa de cair fora do laço.
- **Dois ramos idênticos** em `verificar-export.mts:1045`: `if (A) usada = true;
  else if (B) usada = true;` viraram `if (A || B)`. Eram um OU escrito como se
  houvesse dois caminhos.
- **`RE_CONTA_DETALHE`** (`statement-templates.ts`) tinha `\s*[([]?\s*` — dois
  `\s*` adjacentes quando não há parêntese, que é a forma-livro de backtracking
  super-linear. Vira `\s*(?:[([]\s*)?`. **Conferido equivalente em 200 mil
  entradas**, e esta regex roda uma vez por linha extraída de cada documento.

**Higiene:** import duplicado do mesmo módulo unificado em `export.ts`; escapes
desnecessários em classe de caractere (`[\/\-. ]` → `[/\-. ]`), conferidos
equivalentes.

### O ACHADO QUE O SONAR ERRA, E ERRAR NELE QUEBRARIA O CÓDIGO

**`javascript:S1940` — "Use the opposite operator (`<=`) instead"**, em
`n8n/lib/custo.mjs:100`, `cobertura.mjs:379` e `medir-custo-book.mjs:387`:

```js
if (!c || !e || !(e.entrada > 0)) return 1;
```

`!(x > 0)` **não é** `x <= 0`. Medido:

| x | `!(x > 0)` | `x <= 0` |
|---|---|---|
| `0`, `-1`, `null` | `true` | `true` |
| **`NaN`** | **`true`** | **`false`** |
| **`undefined`** | **`true`** | **`false`** |
| **`"abc"`** | **`true`** | **`false`** |

A forma atual é a guarda **correta** contra `NaN`/`undefined`. Trocar por `<=`
faria um `entrada` inválido **passar pela guarda** e produzir custo `NaN` — número
errado em silêncio, que é exatamente a família de defeito que este projeto existe
para não ter. **Esta regra fica desobedecida de propósito, nos três pontos.**

### O que NÃO foi corrigido, por classe e com o motivo

| Regra | N | Por que fica |
|---|---|---|
| `S4624` literais aninhados · `S3358` ternários aninhados | 199 | É a forma como este código é escrito, com comentário ao lado. São strings de **fórmula do Excel**: reescrever 199 delas é risco de erro de digitação num motor financeiro, em troca de estilo |
| `python:S1192` literais duplicados | 81 | Nos geradores dos books. Extrair constante num gerador que é o **oráculo** das suítes tem risco maior que o ganho |
| `S3776` complexidade cognitiva | 59 | É pedido de refatoração de funções grandes do export, não conserto. Dívida real e conhecida — mas é reescrita, e reescrita se faz com motivo próprio |
| `S6551` `String(formData.get(x))` | 40 | Real em tese (`FormData.get` devolve `string \| File`). São 40 pontos em 15 *server actions* **sem cobertura de teste**, para um caso que exige multipart forjado. Fica nomeado, para ir junto com o teste dessas ações |
| `S6035` alternação de um caractere | 43 | `(a\|b)` → `[ab]`. Seguro, mas 43 edições de regex por ganho nulo |
| `S6582` optional chaining | 34 | `a && a.b` → `a?.b` **não é sempre equivalente**: com `a` valendo `0` ou `""` o resultado muda. Aplicar em lote é justamente o que não se faz |
| `S6594` `exec()` em vez de `match()` | 30 | Difere com a flag `/g`. Mesma razão |
| `S6759` props do React `Readonly` | 31 | Só tipo, zero em runtime |
| `S77xx` modernização (`.at()`, `replaceAll`, `Number.parseInt`, Sets) | ~60 | Idioma novo, comportamento igual |
| `S2871` os outros 9 `sort()` | 9 | Conferidos um a um: ordenam **strings** (escalas, moedas, nomes de série). Onde havia número o comparador já existia |
| `S4144` funções idênticas | 5 | Helpers `linhaDe`/`linhaPorRotulo` repetidos no arquivo de teste. Consolidar muda qual planilha cada *closure* captura |
| `S6479` índice como `key` | 2 | Listas estáticas e append-only, sem reordenação e sem estado nos filhos |
| `S1874` `document.execCommand` | 1 | É o **plano B** deliberado, depois de `navigator.clipboard` falhar — e continua sendo o único que funciona em contexto inseguro |
| `S1244` igualdade de ponto flutuante | 1 | Assert de teste; `1234.56` parseado dá o mesmo *double* que o literal |
| `S5850` precedência em regex | 2 | `^cnpj\b\|\bcnpj\s*[\d.]` faz exatamente o que o comentário ao lado diz |
| `S8786`/`S5843` outras regex | 8 | Quadráticas no pior caso, com entrada curta e própria. Não são ReDoS exploráveis |
| `S6505`/`S8543` `npx` e `npm ci` no CI | 7 | `--ignore-scripts` quebra instalação que dependa de *postinstall*; os `npx` resolvem do `node_modules` local, que o `npm ci` já fixa pelo lock |
| `S4036`/`S5443`/`S8707` | 6 | Ferramentas **locais** de repro e diagnóstico: caminho vindo do `argv` é o propósito de um CLI, e `execFileSync` com vetor de argumentos não abre shell |
| `S5145` em `sonar-achados.mjs` | 2 | Mesma razão: script local que imprime o que a API do Sonar devolveu |
| ~~`S5145` em `diagnosticar-ia.mjs`~~ | ~~4~~ → **0** | **CORRIGIDOS em 24/08**, e não triados. Estavam aqui como "ferramenta local", e a triagem estava certa sobre o risco e errada sobre o custo: o conserto é uma função de quatro linhas. Tudo que vem da rede passa por `deRemoto()`, que colapsa controle e quebra de linha — uma mensagem de terceiro com `\n` inventava uma linha nova na saída, e linha nova ali parece **veredito do diagnóstico**. Num script cuja saída inteira é lida como veredito, essa confusão é o defeito |
| `python:S1481`/`S1172` não usados | 13 | Desempacotamento de tupla onde a posição é obrigatória. Trocar por `_` é cosmético |

## Decisões do dono, tomadas em 21/08 — para ninguém reabrir

**1. FICA NA ANÁLISE AUTOMÁTICA.** A alternativa era scanner no CI, que traria
cobertura de teste, análise por branch, decoração de PR e escopo com curinga — ao
custo de um `SONAR_TOKEN` como segredo do repositório e de desligar a automática.
Decidido que não compensa agora. A limitação que sobra é não medir cobertura de
teste, e ela pesa pouco aqui: as suítes deste repositório já são a medida de
cobertura, com contadores que **reprovam quando caem** (`n8n 321 · export 650 ·
transcrição 35 · premissas 32 · e2e 46`). O que o Sonar acrescenta é a classe de
defeito que teste não pega — ternário morto, `sort()` sem comparador, dependência
sem versão presa —, e isso a automática entrega.

**2. QUALITY GATE FICA PARA DEPOIS DAS EXCLUSÕES.** Hoje é `NONE`: o Sonar mede e
não reprova nada. Com 1.700 achados fora de escopo, gate nenhum era honesto — ele
reprovaria por PL/SQL mal interpretado. Quando o `.sonarcloud.properties` chegar à
branch padrão e a próxima análise rodar, aí vale definir, e **sobre código NOVO**,
não sobre o acumulado: gate retroativo em repositório com histórico só ensina a
ignorar o gate.

## O que ainda depende do dono

**Merge do `.sonarcloud.properties` para a branch padrão.** É o único passo que
falta, e sem ele nada acima vale: a Análise Automática só lê esse arquivo na
branch padrão. Depois do merge, a próxima análise deve cair de **3.091 para ~770**
achados — e esse número é a conferência de que a exclusão pegou. Se continuar em
3.000, a exclusão não foi aplicada e o motivo mais provável é sintaxe: sem
curinga, caminho literal.
