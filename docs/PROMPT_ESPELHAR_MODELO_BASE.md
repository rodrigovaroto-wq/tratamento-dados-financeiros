# Prompt — espelhar o Modelo Base no export do portal

> **Como usar:** cole este arquivo inteiro como primeira mensagem de uma sessão nova do Claude
> Code neste repositório. Ele é autossuficiente: descreve a função, o objetivo, o estado medido,
> as ferramentas, o método, os requisitos e o formato de entrega. Não presuma nada que não esteja
> aqui ou no repositório — em particular, **não presuma que o trabalho começa escrevendo código**.

---

## 1. Sua função

Você é o engenheiro responsável por fazer o **modelo institucional gerado pelo portal** ser uma
réplica fiel do **Modelo Base** — a planilha de referência do dono, em `docs/referencia/modelo-base.xlsx`.

Isto **não** é uma tarefa de "melhorar a planilha". É uma tarefa de **conformidade medida**: existe
um artefato de referência, existe um artefato gerado, e o seu trabalho é reduzir a distância entre
os dois até zero — em estrutura, fórmulas, formatação, recursos de planilha e comportamento —
provando a cada passo, com número, quanto da distância caiu.

O dono foi explícito sobre o padrão de exigência:

> *"Essa comparação deve partir da premissa de que esse modelo que estamos criando deve ser
> exatamente igual, tanto fórmulas, quanto formatação, quanto opcionalidades, quanto absolutamente
> tudo que você consiga captar. Você deve ler o modelo e analisar absolutamente tudo o que está
> configurado, como está configurado, onde está configurado e como está configurado, cada célula,
> cada micro coisa. (…) você primeiro irá analisar por completo o modelo, mapeá-lo por completo, e
> após isso replicar."*

**A ordem importa e é uma instrução direta: mapear primeiro, replicar depois.** Uma sessão que
começa editando `modelo-institucional.ts` sem ter o mapa completo vai reproduzir a aparência de
algumas abas e errar o mecanismo — que é exatamente o que já aconteceu neste projeto (ver §9).

---

## 2. O objetivo, e o que conta como pronto

**Pronto** é: um analista que conhece o Modelo Base abre o `.xlsx` gerado pelo portal para um caso
real e **não consegue apontar diferença estrutural** — mesmas abas na mesma ordem, mesmos blocos
na mesma posição relativa, mesmas fórmulas ligando as mesmas coisas, mesma formatação, mesmos
recursos (painéis congelados, validações, formatação condicional, faixas nomeadas, gráficos).

Isso **não** significa que os números sejam iguais: o Modelo Base é o modelo de **outra empresa**
(ver §4). O que tem de ser idêntico é o **motor**, não o dado.

Definição operacional de pronto, para não depender de impressão:

1. o mapa de conformidade (§7, fase 1) está completo e versionado no repositório;
2. para cada uma das 14 abas do Modelo Base existe uma linha na tabela de conformidade com
   veredito **conforme / divergente / deliberadamente diferente (com motivo escrito)**;
3. nenhuma divergência sem motivo escrito sobrevive;
4. as quatro suítes passam e os contadores **subiram**;
5. o `HANDOFF.md` tem a seção da rodada e o cabeçalho atualizado.

---

## 3. O estado de hoje, medido (não estimado)

Medições feitas em 2026-08-05 com `docs/referencia/mapear-xlsx.py` (§6), contra
`docs/referencia/modelo-base.xlsx` e contra um export completo real do caso de teste v35.

| | Modelo Base | Nosso export | Distância |
|---|---|---|---|
| Abas | **14** | 29 (as 14 + 15 nossas de dado/proveniência) | as 15 extras são **desejadas** (§10) |
| Fórmulas nas 14 abas | **14.504** | **2.842** | temos **~20%** |
| Nomes definidos (faixas nomeadas) | **1.044** | **0** | ausente por completo |
| Gráficos | **8** | **0** | ausente por completo |
| Imagens | **1** | **0** | ausente |
| Validação de dados | 3 (`ST Inv. & Debt`) | 3 (espalhadas) | conferir equivalência |
| Formatação condicional | 0 | 1 | conferir |

Fórmulas por aba — é aqui que o trabalho está concentrado:

| Aba | Modelo Base | Nosso | Falta |
|---|---|---|---|
| `Output` | **3.693** | 118 | **3.575** |
| `ST Inv. & Debt` | **3.573** | 241 | **3.332** |
| `Fixed Assets & CAPEX` | 1.785 | 207 | 1.578 |
| `Balance Sheet` | 1.275 | 275 | 1.000 |
| `Income Statement` | 738 | 125 | 613 |
| `Cash Flow` | 692 | 76 | 616 |
| `Revenues, COGS & SG&A` | 664 | 351 | 313 |
| `Working Capital` | 1.631 | 1.312 | 319 |
| `Goodwill, Taxes & Div.` | 337 | 42 | 295 |
| `Anual` | 64 | 0 | 64 |
| `Premissas` | 15 | 12 | 3 |
| `Considerações` | 3 | 1 | 2 |
| `Tributos a Recolher` | 34 | **82** | temos mais (conferir se é ruído) |
| `Capa` | 0 | 0 | — |

**Use esta tabela como placar.** Cada PR seu deve mover números dela, e o novo estado medido entra
no corpo do PR. Não confie na memória: **remeça a medição a cada rodada**, com a ferramenta.

---

## 4. A ambiguidade que você tem de resolver ANTES de escrever a primeira linha

O Modelo Base **não é um gabarito vazio**. Ele é um modelo preenchido de uma **operadora de plano
de saúde**, com exercícios **2010 a 2018** — a aba `Premissas` tem "Contraprest. efetivas de plano
de assist. à saúde", "Eventos conhecidos ou avisados", "Recuperação de eventos…", com valores.

Então "exatamente igual" tem duas leituras possíveis, e elas levam a trabalhos diferentes:

- **(A) igual no MOTOR** — mesmas abas, mesmos blocos, mesma gramática de fórmula, mesma
  formatação, mesmos recursos; o conteúdo vem do caso do mandato. É a leitura que faz sentido para
  um produto que gera modelo para qualquer cliente;
- **(B) igual no ARQUIVO** — incluindo rótulos e contas da operadora de saúde. Isso produziria um
  modelo que fala de "eventos avisados" para uma metalúrgica.

**Adote (A) como hipótese de trabalho e diga isso ao dono na primeira resposta**, em uma frase, sem
travar o trabalho: siga por (A) e peça confirmação em paralelo. Se ele corrigir para (B), o mapa da
fase 1 continua valendo inteiro — só muda o que se replica.

Há um caso intermediário que provavelmente é o certo e que o mapa vai revelar: **linhas do Modelo
Base que são estruturais do setor de origem** (assistência à saúde) versus **linhas que são
universais** (DRE, balanço, fluxo, giro, dívida). O mapa tem de marcar cada bloco como
`universal` ou `do setor de origem` — é essa marcação que permite replicar o motor sem importar o
vocabulário de outra indústria.

---

## 5. Onde estão as coisas

| O quê | Caminho |
|---|---|
| **Modelo Base (referência)** | `docs/referencia/modelo-base.xlsx` — 14 abas, 0,5 MB |
| Onboarding do dono (67 pág.) | `docs/referencia/onboarding.pdf` |
| **Gerador do modelo institucional** | `portal/src/lib/modelo-institucional.ts` (~1.850 linhas) — é o arquivo que você vai mudar |
| Gerador do resto do export | `portal/src/lib/export.ts` (~3.100 linhas), `portal/src/lib/export-modelagem.ts` (~2.400) |
| Estilo do export | `portal/src/lib/export-estilo.ts` |
| Rota que monta os insumos | `portal/src/app/casos/[id]/export/route.ts` |
| **Suíte do export** | `portal/scripts/verificar-export.mts` (435 asserts) — é onde os seus testes entram |
| Fixture do caso real | `db/test/fixture_modelagem_v35.sql` (249 linhas, 760 ocorrências, reconstrução fiel da produção) |
| Roteiro que configura a modelagem | `db/roteiro_modelagem_v35.sql` |
| Memória do projeto | `HANDOFF.md` (leia o cabeçalho e as duas últimas seções) |
| Regras de trabalho | `CLAUDE.md` (leia inteiro antes de tudo) |

---

## 6. As ferramentas que você já tem (não reinvente)

**`docs/referencia/mapear-xlsx.py`** — lê qualquer `.xlsx` como ZIP de XML.

```bash
# resumo de todas as abas: fórmulas, validações, cond., merges, congelamento
python3 docs/referencia/mapear-xlsx.py docs/referencia/modelo-base.xlsx

# TUDO de uma aba, célula a célula: fórmula, estilo, tipo, valor, painéis,
# merges, validações e formatação condicional
python3 docs/referencia/mapear-xlsx.py docs/referencia/modelo-base.xlsx \
    --aba "Balance Sheet" --celulas
```

Duas razões para ele existir, e as duas são economia de crédito para você:
- **`exceljs` estoura o heap** (8 GB) ao abrir o Modelo Base e o nosso export na mesma execução;
- **a ordem das abas não é a ordem dos `sheetN.xml`** — mapear por índice de arquivo atribui as
  fórmulas de uma aba a outra. O script resolve pelo `rels`, que é o vínculo correto. Essa
  armadilha já produziu número errado nesta investigação.

**`portal/scripts/gerar-export-do-banco.mts`** — gera o `.xlsx` do export a partir de um Postgres
local, **sem Supabase, sem Vercel e sem gastar um token**. É o seu laço de iteração:

```bash
TEST_DB=tdf_v35 PGDATABASE=postgres db/test/run.sh          # migrations + suíte
psql -d tdf_v35 -f db/test/fixture_modelagem_v35.sql        # imprime o caso_id
# edite o v_caso no topo de db/roteiro_modelagem_v35.sql e rode:
psql -d tdf_v35 -f db/roteiro_modelagem_v35.sql             # configura a modelagem
DB=tdf_v35 ./portal/node_modules/.bin/tsx \
  portal/scripts/gerar-export-do-banco.mts <caso_id> /tmp/nosso.xlsx
python3 docs/referencia/mapear-xlsx.py /tmp/nosso.xlsx      # e compare
```

**Preparação do ambiente**, uma vez por sessão:

```bash
cd portal && npm ci && cd ..                    # instala tsx e exceljs
pg_ctlcluster 16 main start                     # Postgres 16 local (descartável)
su postgres -c "createdb root" 2>/dev/null      # o papel do checkout precisa de banco próprio
pip install reportlab                           # só se for mexer no book sintético
cd test-data/book-vertentes && PYTHONPATH=. python3 gerar.py && cd ../..
```

---

## 7. O método, em cinco fases — nesta ordem

### Fase 1 — MAPEAR o Modelo Base, inteiro, antes de tocar em código

Produza `docs/referencia/MAPA_MODELO_BASE.md`, versionado. Para **cada uma das 14 abas**:

- **identidade**: nome exato, posição na ordem, estado (visível/oculta), painel congelado
  (`xSplit`/`ySplit`/`topLeftCell`), largura de colunas, altura de linhas relevantes;
- **anatomia**: os blocos na ordem em que aparecem (cabeçalho, premissas, histórico, projeção,
  totais, checagens), com as linhas/colunas em que começam e terminam;
- **gramática das fórmulas**: os *padrões*, não as 3.693 fórmulas uma a uma. Ex.: "coluna de ano
  N = coluna N−1 × (1 + premissa)", "total = SUM do bloco acima", "CHECK = ativo − passivo − PL",
  referência entre abas por nome de aba e endereço absoluto/relativo. **Nomeie cada padrão** — é
  ele que será replicado;
- **formatação**: formatos numéricos (`numFmt`) por tipo de linha, negrito/itálico, cores de
  preenchimento e o que cada cor SIGNIFICA (entrada manual × calculado × histórico × checagem),
  bordas, recuos;
- **recursos**: faixas nomeadas que a aba usa e define, validações de dados (com a fórmula da
  lista), formatação condicional (com a regra), merges, gráficos (tipo, séries, âncora);
- **classificação**: cada bloco marcado como `universal` ou `do setor de origem` (§4).

Ao fim da fase 1, o mapa tem de responder sozinho: *"para reconstruir esta aba do zero, o que
exatamente eu preciso escrever?"* Se não responder, ele não está pronto — e a fase 2 vai falhar
por falta de base, não por dificuldade.

### Fase 2 — COMPARAR, aba a aba, com veredito

Produza `docs/referencia/CONFORMIDADE.md`: uma tabela por aba, e dentro dela uma linha por
elemento do mapa, com veredito **conforme / divergente / deliberadamente diferente**. Toda
divergência recebe: o que a referência faz, o que nós fazemos, e o **impacto** (cosmético,
estrutural, ou de resultado). Ordene por impacto — é isso que define a ordem da fase 4.

### Fase 3 — PLANEJAR, e mostrar o plano ao dono antes de executar

Uma sequência de PRs pequenos, um por aba ou por família de padrões, cada um com: o que entra, o
que sai da tabela-placar (§3), e o teste que prova. **Peça aprovação do plano antes de executar** —
são muitas horas de trabalho e a ordem certa depende da prioridade dele, não da sua.

### Fase 4 — REPLICAR, uma aba por vez

Para cada aba: implemente em `modelo-institucional.ts`, gere o `.xlsx` local, mapeie os dois de
novo, atualize a tabela de conformidade, escreva o teste, abra o PR. **Nunca mais de uma aba por
PR** — um PR que muda cinco abas é impossível de revisar e de reverter.

### Fase 5 — PROVAR

Cada PR precisa de teste em `portal/scripts/verificar-export.mts` que **reprova com o defeito
religado**. Ver §8.

---

## 8. Requisitos inegociáveis (do `CLAUDE.md`, e valem para você)

1. **Branch + PR sempre.** Nunca push direto em `main`. **Abra o PR junto com o push** — neste
   projeto o dono mergeia rápido, e commit empurrado depois do merge fica órfão, fora de qualquer
   PR. Já aconteceu três vezes.
2. **Teste que não pode falhar não prova nada.** Antes de dizer que um teste cobre um defeito,
   **religue o defeito e veja o teste reprovar**. Cole a mensagem da reprovação no corpo do PR.
3. **Contadores nunca caem.** Estado atual: `n8n/test` **176** · `verificar-export.mts` **435** ·
   `db/test/run.sh` **49 migrations / 324 asserts** · `test/e2e` **27**. Se um número cair, você
   apagou cobertura.
4. **Nada de data do sistema em gerador.** `new Date()` faz o arquivo mudar sozinho e o CI ficar
   vermelho por não-motivo. Use data de referência fixa.
5. **Migrations**: faixa `0100+` é a do colaborador; a última é a `0104`. Confira `db/migrations/`
   antes de criar, registre no `db/README.md` **na tabela E na lista de comandos** (o `run.sh`
   reprova se faltar), e **não aplique nada** — aplicar é do dono.
6. **Português** em nomes, comentários e mensagens, como o resto do repositório.
7. **`HANDOFF.md`**: acrescente a seção da sua rodada no fim e **atualize o cabeçalho** (estado do
   `main`, migrations, contadores, o que está aberto).
8. **Mirror do n8n**: se mexer em `n8n/lib/*.mjs`, regenere os workflows e commite o JSON.
9. **Custo**: `test-data/book-vertentes` e a fixture do v35 exercitam tudo **sem IA**. Teste ao
   vivo é do dono e custa orçamento — não proponha um sem necessidade real.

---

## 9. Armadilhas conhecidas — todas custaram uma rodada aqui

- **A identidade de uma linha é o par (`secao_canonica`, `rotulo_norm`), nunca o rótulo sozinho.**
  Três defeitos desta família já foram corrigidos (PRs #98 e #100): a tela preenchia linha que
  ninguém tocou, o export puxava o valor base da seção errada, e o modelo institucional derrubava
  o export inteiro com HTTP 500 (`âncora duplicada "trib:obrigacoes tributarias"`). No caso v35,
  **13 rótulos existem em duas seções**. Ao criar qualquer chave/âncora nova, inclua a seção.
- **Fixture menor que a produção mede o instrumento, não o sistema.** Um benchmark contra 55
  rótulos aprovou uma otimização que não bastava para os ~250 reais. Use a fixture do v35.
- **`pct_de_linha` e `dias_de_giro` incidem sobre a RECEITA TOTAL do caso**, por decisão de
  produto — não sobre a linha. É por isso que `ALIQUOTA` e `TAXA_DIVIDA` ficaram fora do roteiro:
  aplicariam 43% e 15% da receita como imposto e juro. Se o Modelo Base usa outra base, isso é uma
  **divergência de mecanismo** e vai para a tabela de conformidade — não conserte por conta
  própria: é decisão do dono.
- **Dupla contagem de caixa e de dívida** no modelo institucional, aberta desde a sessão 32:
  `Working Capital` projeta todas as contas de `ativo_circulante` (inclusive caixa) por dias de
  giro, `Cash Flow` soma as mesmas em `CAIXA_FIM`, e `Balance Sheet` faz `AC = CAIXA + AC_OPER`. O
  `CHECK` do balanço acusa em vermelho. **Provavelmente o mapa do Modelo Base contém a resposta
  certa para isso** — é um bom primeiro alvo.
- **A guarda de âncora duplicada da `Grade` é proposital**: ela prefere explodir a somar a conta
  errada em silêncio. Não a remova para "fazer passar".
- **O modelo institucional só é construído quando o caso tem entidade reconhecível nos campos
  extraídos** (`if (entidadesConhecidas.size > 0)` em `export.ts`). Teste com `campos: []` passa
  sem exercitar nada — a primeira versão de um teste desta sessão caiu nessa.
- **Premissa de sazonalidade não tem valor a digitar**, mas `fn_conferir_modelagem` conta premissa
  ativa com `valores` vazio como "sem valor" e isso segura o "pronto" da tela. Pendência aberta.
- **Portão 2**: o export completo é recusado (HTTP 409) se houver pendência bloqueante ou
  não-sobrepujável viva. Não é bug. Para testar, resolva ou **rejeite** as pendências com motivo
  registrado — e não existe UI para isso hoje, é `UPDATE` no SQL Editor (lacuna conhecida).

---

## 10. O que NÃO fazer

- **Não remova as 15 abas nossas** (`Resumo`, `Dados (linha a linha)`, `Balanço`, `DRE`,
  `Fluxo de Caixa`, `DMPL`, `Combinado`, `Balancete`, `Faturamento`, `Dívida`, `Intragrupo`,
  `Outros`, `Macro`, `Macro (dados)`, `Modelagem`). Elas são a **proveniência** — o princípio de
  `f0/07` é que o dado curado e rastreável não some da entrega. O Modelo Base não as tem porque
  ele começa depois do trabalho de extração.
- **Não copie os números da operadora de saúde** para dentro do gerador (§4).
- **Não faça um PR gigante** "espelhando tudo".
- **Não aplique migration, não importe workflow no n8n, não rode teste ao vivo** — os três são do
  dono, por serem ações globais e irreversíveis sobre ambiente compartilhado.
- **Não conserte divergência de mecanismo por conta própria** quando ela mudar resultado
  financeiro: registre na tabela de conformidade e pergunte.

---

## 11. O que entregar (output final)

1. **`docs/referencia/MAPA_MODELO_BASE.md`** — o mapa completo das 14 abas (fase 1).
2. **`docs/referencia/CONFORMIDADE.md`** — a tabela de vereditos, atualizada a cada PR (fase 2).
3. **Uma sequência de PRs**, um por aba/família, cada um com:
   - o que mudou e **por quê**, no corpo;
   - a tabela-placar de §3 **remedida**, antes e depois;
   - o teste novo em `verificar-export.mts` e **a mensagem da reprovação com o defeito religado**;
   - os quatro contadores das suítes.
4. **`HANDOFF.md`** — seção da rodada no fim + cabeçalho atualizado.
5. **Uma resposta final ao dono** com: quanto da distância caiu (fórmulas por aba), o que ficou
   aberto, e a próxima decisão que depende dele.

---

## 12. Sua primeira resposta nesta sessão deve conter

1. confirmação de que leu `CLAUDE.md`, o cabeçalho do `HANDOFF.md` e este prompt;
2. o resultado de `python3 docs/referencia/mapear-xlsx.py docs/referencia/modelo-base.xlsx` —
   remedido por você, não copiado de §3;
3. a sua leitura da ambiguidade de §4, em uma frase, com a pergunta ao dono;
4. o plano da fase 1 (quais abas em que ordem) e a estimativa de quantas rodadas ela leva;
5. **nenhuma linha de código de produção alterada.** A fase 1 é de leitura.
