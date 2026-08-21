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

## O que só o dono pode fazer

1. **Decidir entre Análise Automática e análise no CI.** Hoje é automática. Ela
   não faz cobertura de teste, não analisa branch que não seja a padrão, não
   decora PR e não deixa escolher dialeto de SQL. Trocar exige criar um
   `SONAR_TOKEN` em *My Account → Security*, guardá-lo em *Settings → Secrets and
   variables → Actions* do repositório, e desligar a análise automática no projeto.
2. **Definir um Quality Gate.** Hoje é `NONE`: o Sonar mede e não reprova nada. Com
   1.700 achados fora de escopo, gate nenhum fazia sentido — depois que este
   arquivo chegar à branch padrão, faz.
3. **Merge deste arquivo para a branch padrão**, senão as exclusões não valem.
