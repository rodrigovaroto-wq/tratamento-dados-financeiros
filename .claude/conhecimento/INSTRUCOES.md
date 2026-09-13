# A camada de conhecimento — como usar, e como não estragar

> **Regra de uma linha:** o índice é DERIVADO. Se dá para extrair do git, das migrations, do
> código ou do CI, ninguém escreve — o `indexar.mjs` lê. A única coisa escrita à mão aqui é a
> ficha, e mesmo ela é estruturada e conferida.

## O que fazer, em ordem

### 1. Antes de abrir arquivo — o briefing

```bash
node .claude/conhecimento/buscar.mjs "<assunto em 2-4 palavras>"
node .claude/conhecimento/buscar.mjs --arquivo portal/src/lib/export.ts   # o que cerca este arquivo
node .claude/conhecimento/buscar.mjs "<assunto>" --largo                  # 3x mais linhas
```

O briefing devolve **ponteiros**, não conteúdo: qual ficha ler, qual arquivo abrir e em que
linha, qual portão prova aquilo, qual migration criou aquela função, qual sessão do HANDOFF
conta a história, e os commits que casam (via `git log --grep`, na hora).

Depois dele, abra **só** o que ele apontou. É esse o ganho: medido em 13/09/2026, as cinco
perguntas de `BASELINE.md` custavam 50.245 bytes de `grep` mais 60.178 bytes de arquivos que
ainda precisavam ser abertos; pelo briefing custam **10.667 bytes**, e nenhuma exige abrir
arquivo para saber onde olhar.

**Vazio é declarado.** Quando não acha, o comando diz "NADA ENCONTRADO" e diz quantos nós
existem. Isso é "procurei e não achei", não "não procurei" — a distinção é a regra 7.

### 2. Ao fechar a rodada — a ficha

Uma ficha nova quando, e **só** quando, a resposta for sim:

> Uma sessão futura ficaria surpresa e grata de saber disto antes de começar?

**E antes de escrever, rode `buscar.mjs` sobre o assunto dela.** Se o briefing já aponta para o
lugar onde a lição está escrita, a ficha NÃO deve existir — o ponteiro já é a memória. Esta regra
é o resultado medido da Etapa 5: das oito candidatas extraídas do HANDOFF, **as oito** já viviam
num comentário de função, no corpo de uma migration ou no cabeçalho de uma suíte, e duas já
nasceriam erradas. Ver `ETAPA-5.md`.

É a mesma pergunta de `.claude/memory/INSTRUCTIONS.md`, e ela não mudou. O que mudou é que
agora a ficha declara o que a desmente. Se dá para derivar lendo o código, **não é ficha**.

```bash
node .claude/conhecimento/indexar.mjs     # regera o grafo
node .claude/conhecimento/conferir.mjs    # o portão, antes do commit
```

O `grafo.jsonl` é versionado e passa por `git diff --exit-code` no CI — igual aos quatro
workflows do n8n, às três fixtures do book e ao `schema.sql`. **Gerar sem commitar deixa o
portão vermelho no CI**, e é de propósito: é assim que o conhecimento viaja junto do código
que o mudou, no mesmo PR.

## O cabeçalho da ficha — os campos, um a um

```yaml
---
id: teto-da-borda-recusa-antes-do-codigo   # = nome do arquivo sem .md
tipo: defeito                              # doutrina | defeito | armadilha | numero | invariante
toca:                                      # arquivos que a ficha descreve. TÊM de existir.
  - portal/src/lib/limite-de-envio.ts
prova: portal/scripts/verificar-limite-de-envio.mts   # suíte que reprova se a lição for violada
ancora: portal/src/lib/limite-de-envio.ts#TETO_DA_FUNCTION_BYTES
ancora_sha: a1b2c3d4e5f6                   # o hash da região, na hora em que a ficha foi confirmada
substitui: []                              # fichas que esta aposenta
---
```

| Campo | Obrigatório | O que o portão faz com ele |
|---|---|---|
| `id` | sim | precisa ser único |
| `tipo` | sim | `invariante` sem `prova` aparece no briefing como "afirmação sem quem a desminta" |
| `toca` | sim (pode ser `[]`) | **reprova** se o caminho não existir |
| `prova` | não | **reprova** se o arquivo não existir OU se o `suites.yml` não o executar |
| `ancora` | não | **reprova** se o arquivo ou o símbolo sumirem |
| `ancora_sha` | só com `ancora` | **reprova** quando a região muda — a ficha vira SUSPEITA |
| `substitui` | não | **reprova** se citar ficha inexistente |

**Omita o campo que você não tem.** Inventar um `prova` que não prova nada é pior que não ter:
o briefing passaria a afirmar que existe quem desminta aquilo.

## A âncora — o mecanismo que faz o conhecimento se invalidar sozinho

`ancora: caminho#SIMBOLO` aponta para um símbolo que aparece **literalmente** no arquivo (uma
constante, uma função). O indexador pega **as 40 linhas a partir dele** e grava o hash da região
no grafo. Quando esse hash diverge do `ancora_sha` da ficha, o portão reprova nomeando a ficha.

O conserto é de uma linha, e a decisão é humana: **releia a ficha contra o código**. Se ela
continua verdadeira, atualize `ancora_sha` com o valor que o portão imprime. Se não, corrija o
texto — foi para isso que ele avisou.

É hash de **região nomeada**, não do arquivo inteiro, e a diferença vem de um defeito real
(`.claude/memory/portao-pode-reprovar-por-ruido.md`): um portão que acusa quando alguém corrige
um comentário do outro lado do arquivo ensina a ignorar o portão.

**Ponha âncora quando a ficha afirma um NÚMERO ou um comportamento preso a um símbolo.** Não
ponha em doutrina ("nunca apresentar ausência como dado") — doutrina não tem região de código, e
uma âncora frouxa só gera ruído.

## Os arquivos daqui

| Arquivo | O que é |
|---|---|
| `buscar.mjs` | o briefing — é o que a sessão roda |
| `indexar.mjs` | lê o repositório e emite o grafo. Toda regra de extração está comentada nele |
| `conferir.mjs` | o portão: caminhos, portões, âncoras e cobertura |
| `grafo.jsonl` | **derivado e versionado**. Nunca editar à mão |
| `cobertura.json` | o piso por tipo de nó e aresta — impede o índice de encolher em silêncio |
| `BASELINE.md` | o custo de recuperação medido ANTES de tudo isto existir |
| `MEDICAO-ETAPA-1.md` | o mesmo custo, medido depois — e os três defeitos que a medição achou no próprio índice |
| `ETAPA-5.md` | a extração do HANDOFF, e por que ela produziu ZERO fichas |
| `medir.sh` | roda as duas medições de novo, em 2 segundos |
| `fichas/` | fichas novas. As antigas continuam em `.claude/memory/`, e as duas pastas são indexadas |

## Por que as fichas antigas não mudaram de pasta

`.claude/memory/` está citado no `CLAUDE.md`, no `MEMORY.md` e em dezenas de comentários de
código. Mover 26 arquivos para ganhar simetria de pasta quebraria todas essas referências de
uma vez — e o ganho seria estético. As duas pastas são indexadas do mesmo jeito; `fichas/` é só
onde as novas nascem.

## O que este índice NÃO é

- **Não é um banco de grafo.** É um arquivo de texto de ~260 KB lido em milissegundos. Se um dia
  passar de ~50 mil arestas, a troca é por SQLite — nunca por um servidor.
- **Não é busca semântica.** Casa termo, e a pontuação está declarada no `buscar.mjs`. Duas
  execuções sobre o mesmo grafo devolvem o mesmo briefing, palavra por palavra.
- **Não é a autoridade sobre o banco.** Quem responde pelo banco continua sendo
  `fn_instalacao_conferir()`, contra o banco em que você está conectado.
- **Não substitui ler o código.** Ele diz qual arquivo e qual linha. A leitura continua sendo sua.
