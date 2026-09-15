# Auditoria profunda do sistema — 2026-09-15

**Método:** bateria COMPLETA do CI executada nesta árvore, sobre o `main` em `de556c2` (merge do PR
#225), antes de qualquer conclusão ser escrita. Banco Postgres 16 montado do zero pelas 119
migrations. Consultas diretas ao banco resultante para o dial, a sonda, a taxonomia e os catálogos.
Nada foi alterado, nada foi commitado durante a medição (`git status` limpo ao fim).

**Números citados foram MEDIDOS, não lembrados.** Onde não foi possível medir — produção, n8n
publicado, lote real — está escrito que não foi, e a fonte é o `ESTADO.md`.

**Quem escreve:** revisão de engenharia sênior com o viés declarado de procurar o que está errado.
A §7 existe para equilibrar isso.

> **A BASE ANDOU ENQUANTO ESTE DOCUMENTO ESTAVA ABERTO, e isto fica dito em vez de corrigido em
> silêncio.** A medição inteira é de `de556c2`. Antes de o PR mergear, o `main` avançou para
> `f230cff` com as migrations **`0175`, `0176` e `0177`** (o CNPJ resolvendo o balcão ambíguo) e
> duas suítes SQL novas. **Elas NÃO foram auditadas** — nenhum número abaixo as inclui.
>
> O que isso muda, aritmeticamente e só: onde se lê **119 migrations**, são **122**; onde se lê
> o repositório na **`0174`**, é a **`0177`**; e a defasagem contra a produção, se ela seguir na
> `0157`, passa de **17 para 20**. As três novas foram exercitadas aqui pela suíte de banco na
> árvore mesclada — **1.333 asserts `ok`** contra os 1.272 de `de556c2`, `schema.sql` idêntico —,
> mas **exercitar não é auditar**,
> e o veredito por componente da §5 continua sendo o de `de556c2`.
>
> Nenhuma conclusão desta auditoria depende de qual é a migration mais nova — as três causas-raiz
> da §6 são estruturais. A `0175`–`0177` serem *mais três rodadas sobre identidade de entidade*
> é, aliás, a §6.1 acontecendo outra vez enquanto o documento era escrito.

---

## 1. Veredito em uma página

**O projeto é sério, real e tecnicamente acima da média.** Não é protótipo: ~100k linhas de código
sob 26 portões, 119 migrations, 179 funções SQL, e uma disciplina (as sete regras do `CLAUDE.md`)
com resultado mensurável. **Tudo passa, medido agora:**

| Portão | Medido | Resultado |
|---|---|---|
| n8n | 543 testes | 0 falhas |
| Banco | 119 migrations do zero, **1.272 asserts `ok`** | verde |
| `schema.sql` materializado | `git diff --exit-code` | idêntico |
| Export | **721 verificações** | verde |
| 6 suítes do portal | transcrição 35, falha, premissas, kit básico, cobertura, limite | verdes |
| e2e (extração→banco→export) | 46 verificações | verde |
| Arnês de variações | 25 variantes de documento sujo | verde |
| 4 geradores de workflow | `git diff --exit-code` | sem drift |
| Régua de cobertura | 20/20 documentos de PRODUÇÃO, erro ≤0,5% | verde |
| Custo do book | invariantes de custo | verde |
| Grafo do conhecimento | 55 verificações + âncoras + piso de cobertura | verde |
| Hooks do agente / comandos | 5 testes / 137 citações, 43 agentes | verdes |
| `tsc` / `eslint` | portal | limpos |

**E ainda assim o veredito é PARCIAL, por três razões que portão verde não alcança.**

### 1.1 O sistema que os testes medem não existe em lugar nenhum

Há **três versões do sistema rodando ao mesmo tempo, e só uma é testada**:

| Camada | Testado pelo CI | Em operação | Defasagem |
|---|---|---|---|
| Banco | `0174` | **`0157`** (+`0160` fora de ordem) | **17 migrations** |
| Workflow n8n | HEAD | importado em **02/09** | ≥7 commits, 3 em extração |
| Provedor de IA | OpenAI `gpt-5.6-luna` | Google `gemini-3.5-flash-lite` | modelo inteiro |
| Portal | `npm ci --ignore-scripts` | install da Vercel, COM scripts | ambiente de build |

Não é dedução: está no `ESTADO.md` e é confirmado pela própria sonda. **Mesmo no banco recém-montado
pelo CI, `fn_instalacao_conferir()` devolve 1 requisito ausente** — `custo_gravado_pelo_n8n` (0115),
cujo `porque` é literalmente *"é o sintoma de que o workflow do n8n não foi reimportado"*.

E há o agravante já registrado na memória `sonda-so-conhece-o-catalogo-que-o-banco-tem`: a sonda
mora DENTRO do banco e é preenchida pelas migrations. **Um banco parado na `0157` não sabe o que a
`0158` exigiria** — responde "tudo certo" estando 17 migrations atrás.

### 1.2 A camada canônica não é canônica

`campo_extraido` é a tabela de fatos e **não tem chave estrangeira nem para `entidade` nem para
`periodo`**. Conferido: as únicas FKs que a tocam são `documento_versao_id` e as duas tabelas de
classe que apontam PARA ela.

- Entidade e período chegam como **texto livre** (`entidade_coluna`, `periodo_coluna`).
- A conta **não tem identificador**: identidade é `(secao_canonica, rótulo normalizado)`, com
  `secao_canonica` sendo um enum de **16 valores** que são seções de demonstração, não plano de contas.
- **Não há hierarquia** — nenhuma coluna de pai.

As tabelas `entidade` e `periodo` existem, mas se ligam ao DOCUMENTO, não ao FATO. Num balanço
COMBINADO — o caso central do produto — o documento tem uma entidade e as colunas têm outras.

### 1.3 O modelo financeiro não é objeto do sistema — é uma planilha

As projeções são **fórmulas do Excel** emitidas por `modelo-institucional.ts` (6.689 linhas). O
sistema não sabe o EBITDA projetado de 2027: quem calcula é o Excel do destinatário. A única forma
de o sistema ler o próprio modelo é `portal/scripts/lib/avaliar-formula.mts` — um mini-motor de
Excel de 630 linhas que existe **só para teste**.

E **não existe cenário no banco**: `grep -i cenario Supabase/schema.sql` devolve zero. Os três
cenários são um `CHOOSE()` dentro da pasta de trabalho, com "Stress" sendo um haircut fixo de 20%
sobre o Base.

### 1.4 Consequência para o objetivo de longo prazo

Do pipeline `DOCUMENTOS → … → POWERPOINT`, o sistema cobre de forma sólida
**EXTRAÇÃO → NORMALIZAÇÃO → RECONCILIAÇÃO** e produz um excelente 1º export de conferência.
CLASSIFICAÇÃO existe em sentido reduzido. MODELAGEM existe, fora do sistema.
**DIAGNÓSTICO, CENÁRIOS, REESTRUTURAÇÃO, VALUATION/RECOVERY, CREDORES, SOLUÇÃO e PRESENTATION
LAYER não existem** — `grep -ril 'valuation|recovery|powerpoint'` em `portal/src`,
`Supabase/migrations` e `N8N/lib` devolve **zero arquivos**.

---

## 2. A massa do repositório, medida

```
SQL migrations       41.250 linhas   119 arquivos (0001–0044, 0100–0174)
SQL tests            13.896 linhas   53 arquivos .test.sql
portal/src           26.845 linhas   TypeScript/React (Next.js)
portal/scripts       10.790 linhas   suítes + mini-motor de fórmulas
N8N/lib               6.560 linhas   17 bibliotecas
N8N/build-workflow*   3.283 linhas   geradores dos 4 workflows
Verificação           1.484 linhas   e2e + arnês de variações
documentação         65.460 linhas   187 arquivos .md
                                     (ESTADO.md 4.402 · HANDOFF.md 7.185)
```

A razão documentação/código (~65k / ~100k) é atípica e é, ela própria, um achado — §6.4.

---

## 3. O que foi descoberto e não estava documentado

### 3.1 A taxonomia já antecipa o produto inteiro — e 27 tipos são mudos

`taxonomia_tipo_documento` tem **36 tipos**, e eles já incluem exatamente os insumos de um produto
de reestruturação completo:

```
AGING_AP  AGING_AR  APLIC_FINANC  AVAIS_FIANCAS  BALANCETE  BALANCO  CERTIDOES
COMBINADO  CONTINGENCIAS  CONTRATOS_COM  CONTRATOS_IC  CONTRATO_DIVIDA
CONTRATO_SOCIAL  DEBITOS_TRIB  DF_AUDITADA  DMPL  DOCS_SOCIOS  DRE  DVA
ESTOQUE  EXTRATO_BANCARIO  FATURAMENTO_24M  FAT_INTRAGRUPO  FLUXO_CAIXA
FLUXO_PROJETADO  GARANTIAS  HEADCOUNT  MAPA_DIVIDA  MUTUOS  NOTAS_EXPL
ORGANOGRAMA  PLANO_NEGOCIOS  PREMISSAS  RAZAO  SITUACAO_FISCAL  SPED
```

**Mas `taxonomia_linha_exigida` tem 14 linhas cobrindo 9 tipos, e 3 delas são `origem='proposta'`
com o texto literal "nenhuma checagem lê X hoje"** (`MUTUOS`, `FAT_INTRAGRUPO`, `CONTRATO_SOCIAL`).

Resultado medido:

| Tipos com exigência VIVA | 6 | BALANCO, COMBINADO, DRE, FATURAMENTO_24M, FLUXO_CAIXA, MAPA_DIVIDA |
|---|---|---|
| Tipos com exigência morta | 3 | as `proposta` acima |
| **Tipos sem consumidor nenhum** | **27** | AGING_AP/AR, EXTRATO_BANCARIO, ESTOQUE, HEADCOUNT, GARANTIAS, CONTINGENCIAS, … |

**27 tipos de documento podem ser ingeridos, classificados e extraídos sem que nada confira se o
conteúdo chegou.** É a regra 7 do projeto — *"estágio que não rodou tem a mesma aparência de estágio
que rodou e não achou nada"* — aplicada ao produto, e ninguém a tinha aplicado aí.

### 3.2 O conjunto de instruções do motor de cálculo já está catalogado

`premissa_catalogo` tem **89 premissas** em 11 naturezas (receita 31, operacional 16, custo 15,
macro 6, investimento 5, giro 4, despesa 4, sazonalidade 3, dívida 3, sócios 1, tributo 1) e
**7 formas de fórmula**:

```
indice_macro · crescimento_composto · pct_de_linha · dias_de_giro
valor_por_ano · preco_x_volume · curva_mensal
```

**Isto é o conjunto de instruções de um motor de projeção que não existe.** O interpretador é o que
falta — hoje ele é emissão de fórmula Excel em TypeScript. Torna a construção do motor muito menor
do que parece: são 7 opcodes, não uma plataforma de modelagem.

### 3.3 A matriz de perímetro já existe

`checklist_item_status(caso_id, entidade_id, periodo_id, tipo_taxonomia, obrigatoriedade, status,
documento_id)` **é** a matriz de perímetro por entidade × período × tipo. A camada de perímetro está
~70% construída e não estava reconhecida como tal.

### 3.4 Semana não existe

`PERIODO_TIPO_ENUM = ['anual','trimestre','multi','data-base','outro','desconhecido']`.
Não há granularidade semanal em lugar nenhum do sistema. 13-week cash flow não é variação do
modelo; é um eixo novo.

### 3.5 O dial confirma a contradição estrutural

Consultado no banco montado:

```
extracao_linhas_financeiras | N2 | base_do_nivel = 'declarada' | medicao_* = NULL
classificacao_doc_checklist | N1 | limiar_auto_clear 0,93
classificacao_contabil      | N0
```

O estágio mais crítico opera em **N2 (auto-aceite) com base "declarada" e nenhuma medição de
concordância jamais registrada**. A `0126` pôs a regra de ouro em `fn_mudar_dial`, que agora recusa
subir — mas os dois já estavam em cima antes dela.

### 3.6 `classe_contabil_catalogo` não é plano de contas

São **5 classes, e são de recorrência**: `recorrente`, `nao_recorrente`, `extraordinario`,
`candidato_ajuste_ebitda`, `revisar_manual`. É normalização de EBITDA — útil e alinhada ao alvo —,
não classificação contábil.

### 3.7 RLS está ligada e permite tudo

38 tabelas com RLS, **47 policies, todas `USING (true) TO authenticated`**. Está documentado sem
suavizar no `10_DADOS_RETENCAO_E_LGPD.md` §4: *"qualquer pessoa com acesso ao portal vê todos os
mandatos"*. Deliberado para ferramenta interna; bloqueante como plataforma.

---

## 4. Contradições documentação × implementação

| # | Contradição | Evidência |
|---|---|---|
| **C1** | **A visão declarada nega o produto.** `00_VISAO_E_ESCOPO` fixa escopo negativo: *"não é ferramenta de modelagem financeira, não é motor de decisão contábil"*. O repositório tem 6.689 linhas de modelagem. O escopo foi ultrapassado sem ser reescrito. | `00_VISAO_E_ESCOPO.md` × `modelo-institucional.ts` |
| **C2** | **`PRONTIDAO_POR_ESTAGIO.md` está ~35 sessões atrasado**, e o `CLAUDE.md` o anuncia como autoridade. Diz *"20/08, sessão 55 · banco 884 · export 618 · n8n 298"* e "78 migrations". **Medido: 1.272 · 721 · 543 · 119.** O último commit no arquivo (09-01, `3cc3f39`) foi renomeação em massa, não conteúdo. | medição direta |
| **C3** | **`MAPA_DE_EXECUCAO.md` diz "0160, sessão 81"**; o repositório está em `0174`, sessão 90 — no arquivo que avisa *"cabeçalho que fica para trás manda a próxima sessão planejar contra um estado que não existe mais"*. | cabeçalho × `ls Supabase/migrations` |
| **C4** | **O `CLAUDE.md` ainda é espelho incompleto do CI.** Os dois auto-checks que ele documenta passam, mas cobrem só `verificar-*.mts` e `medir-*.mjs`. Ficaram de fora: `node --test '.claude/hooks/test/*.test.mjs'` e **todo o passo de regeneração de fixtures** (`gerar_fixture.py`, `gerar_fixture_canastra.py` + `git diff --exit-code`), que é portão duro. | `grep -c` comparativo |
| **C5** | **`N8N/medir-fase0-denominador.mjs` é órfão** — nem no CI nem no `CLAUDE.md`. | execução (exit 2) |
| **C6** | **3 das 14 linhas exigidas são declaradas e mortas** — eliminação intragrupo sem insumo. | `select * from taxonomia_linha_exigida` |

---

## 5. Estado por componente

Legenda: READY · PARTIAL · BROKEN · MISSING · REDUNDANT · REFACTOR · REBUILD

| Componente | Estado | Evidência |
|---|---|---|
| Ingestão (n8n E1, 40 nós) | **PARTIAL** | funciona; rodada de 190 docs teve **75 sem linha** (73 `extracao_falhou`, 72 por billing/429); workflow publicado defasado |
| Extração (IA) | **PARTIAL** | schema JSON forte, 543 testes, espelho de 26 funções; **N2 declarada sem concordância** |
| Normalização — escala | **READY** | `fn_fator_escala`/`fn_valor_em_base` linha a linha; `fn_motivo_escala_incomparavel` declara em vez de somar |
| Normalização — moeda | **PARTIAL** | gravada por linha e **nunca presumida** (`0035`); **sem conversão cambial**; o export se recusa a totalizar moedas distintas |
| Classificação contábil | **PARTIAL** | 5 classes de recorrência; dial **N0** |
| **Camada canônica** | **REFACTOR** | §1.2 — sem FK, sem `conta_id`, sem hierarquia |
| Completude / taxonomia | **PARTIAL** | §3.1 — 27 tipos mudos |
| Reconciliação (10 funções) | **READY** | `ativo_passivo_pl`, `caixa_bp_fluxo`, `despfin_dre_vs_divida`, `receita_dre_vs_faturamento`, `duplicidade`, `intragrupo`, `mutuos`, `versoes_do_periodo`, `arvore`, `por_documento`; tabela com FK real, materialidade e precondições |
| Fatos materiais | **READY (subdimensionado)** | `documento_fato` + 9 tipos (continuidade operacional, ressalva de auditoria, covenant rompido, reclassificação de dívida, litígio, garantia, evento subsequente, parte relacionada, mudança de critério), com trecho literal ≥20 chars obrigatório |
| Perímetro | **PARTIAL** | §3.3 |
| Modelagem | **PARTIAL / arquitetura inadequada ao alvo** | premissas persistidas; projeção no Excel; sem guarda de giro agregado |
| Cenários | **MISSING** | §1.3 |
| 1º export (dados) | **READY** | 721 verificações, proveniência por célula |
| 2º export (comitê) | **PARTIAL** | 14 abas; circularidade cortada e **declarada na aba `Considerações`**; ND/EBITDA, DSCR e pico de caixa fora dos três cenários |
| Portal | **READY** | `tsc`/`eslint` limpos |
| Índices macro | **READY** | BCB SGS + IBGE + Focus, `0032` corrigida |
| Testes / invariantes | **READY** | o componente mais forte |
| Dados de teste | **READY** | vertentes 14 docs/1.167 linhas · canastra 38 docs/3.034 linhas; o gerador fecha o balanço por `assert`; fixtures sob `git diff` |
| CI (28 passos) | **READY** | melhor que o `CLAUDE.md` que o descreve |
| Governança | **READY** | `evento_auditoria` (ator/ação/antes/depois), `decisao`, `pendencia` tipada, dial, `lote_execucao` com custo e cobertura, `fn_operacao_*` |
| Memória / conhecimento | **READY** | grafo derivado versionado + portão de âncora |
| Agentes | **PARTIAL / REDUNDANT** | 7 do projeto + **30 `importado.*`** que existem só para 13 comandos não morrerem |
| Segurança / RLS | **PARTIAL (documentado)** | §3.7 |
| **Deploy de migrations** | **BROKEN** | manual; 17 de defasagem |
| **Republicação n8n** | **BROKEN** | manual; defasada desde 02/09; memória registra perda de toggles |
| Backup / restauração | **PARTIAL** | documentado; **teste nunca executado** |
| Diagnóstico financeiro · Valuation · Recovery · Credores · Alavancas · PPT | **MISSING** | 0 ocorrências em código |

---

## 6. Causas-raiz

Os problemas não são independentes. São quatro causas produzindo dezenas de sintomas.

### 6.1 A camada canônica não tem identidade tipada

Quatro ausências, e o que cada uma custou no próprio git log:

| Ausência | Sintomas |
|---|---|
| **Sem `conta_id`** | `0105` duplicidade de rótulo · `0144` duplicidade é entre documentos · `0151` desempate · `0159` o rótulo que a estrutura desmente · `0168` apelido truncado. E as funções `fn_radicais_rotulo`, `fn_rotulo_contido`, `fn_rotulos_candidatos`, `fn_tokens_estruturais` — todas existem para adivinhar identidade a partir de string |
| **Sem hierarquia** | A `0144` nomeia: *"`secao` chega ACHATADA, com o subtotal e as folhas dele todos marcados com a seção de topo"*. O schema PEDE o agrupador imediato; o modelo devolve o topo. `0133`, `0143`, `0144` são a mesma causa em três lugares |
| **Sem FK de entidade/período no fato** | Consolidação e intercompany dependem de `fn_normalizar_texto(entidade_coluna) = …`. A saga `0169`–`0174` é dar identidade forte à entidade DEPOIS do fato |
| **`periodo_coluna` sobrecarregada** | O próprio schema admite: *"o período ('2024') quando é comparativo, OU a natureza da coluna quando não é ('Débito', 'Crédito', '31 a 60 dias')"*. `0140` e `0145` tratam disso |

**Oito rodadas de correção sobre a mesma causa-raiz.** Cada uma individualmente correta; juntas, um
imposto que não converge.

### 6.2 O sistema é testado, mas não é implantado

§1.1. O CI mede o repositório com rigor exemplar; nada mede o que está rodando. E a sonda não pode
avisar, porque só conhece o catálogo que o banco tem.

### 6.3 O modelo financeiro não é objeto do sistema

Consequências em cadeia: não dá para comparar cenários (não há números); não dá para calcular
valuation ou recovery; não dá para validar sem reimplementar Excel — e foi o que aconteceu
(`avaliar-formula.mts`, com limites declarados); a circularidade teve de ser cortada por falta de
motor iterativo; e um dia PPT exigiria uma **terceira** implementação.

Consequência prática já visível, medida no `PRONTIDAO`: *"Vinte contas × 60 dias = 1.200 dias de
receita em giro, e o balanço continua fechando porque o PL absorve"* — a fixture de demonstração faz
exatamente isso, e o passivo circulante vai de 71 mil a 5,7 milhões em cinco anos.

### 6.4 A documentação cresce mais rápido do que se mantém

65.460 linhas de markdown, três documentos de estado desalinhados entre si (C2, C3). O projeto tem
consciência do problema — separou `ESTADO.md` de `HANDOFF.md` exatamente por isso —, mas o mecanismo
escala pior que o problema.

---

## 7. O que não se deve mexer

Esta seção existe para equilibrar o viés declarado no cabeçalho.

1. **A camada de reconciliação.** Ativo mais valioso e mais difícil de reconstruir. Sobrevive a
   qualquer refatoração do canônico — só melhora com FK real.
2. **A disciplina de invariantes.** A regra 2 (desligar a correção, provar que a suíte reprova,
   religar, registrar quantos asserts reprovaram no commit) é prática que se vê raramente. O
   `ESTADO.md` registra *"11 invariantes novos medidos por seis desligamentos distintos"* e que
   *"um deles nasceu VAZIO"*. É o que torna uma cirurgia de arquitetura segura.
3. **Os dois books sintéticos.** Oráculo com gabarito, gerado por script que fecha o balanço de 6
   empresas × 3 exercícios por `assert`, sob `git diff`. Insubstituível.
4. **O schema de extração da IA.** As descrições dos campos codificam conhecimento contábil real
   (*"apontar para o topo faz o subgrupo ser somado duas vezes"*).
5. **`documento_fato` e os 9 fatos materiais.** Matéria-prima do Diagnóstico, com trecho literal
   obrigatório. Subutilizado, não defeituoso.
6. **A proveniência por (rótulo, seção, ANO).** O raciocínio da `0125` está certo e é raro:
   *"Rastreabilidade que aponta para a célula errada é pior que rastreabilidade nenhuma: a primeira
   convida a conferir e leva ao lugar errado."*
7. **A duplicação inline das 26 funções do n8n.** Imposta pela plataforma, contida por equivalência
   comportamental com assert de fechamento. Dívida **mitigada**, não aberta.
8. **O Excel com fórmula viva.** É ativo comercial. O motor muda a FONTE da verdade, não o formato
   da entrega.
9. **A camada de conhecimento.** Grafo derivado versionado com portão de âncora.

**E o que o sistema faz certo e é raro:** o Princípio "ausência não é zero" é honrado com rigor.
`fn_fator_escala` devolve `null` para escala desconhecida; `moeda is null` = desconhecida, nunca BRL
presumido; `avaliar-formula.mts` devolve `null` em vez de 0. Há ficha de memória dedicada
(`nunca-apresentar-ausencia-como-dado.md`).

---

## 8. Riscos

### Arquiteturais

| # | Risco | Grau |
|---|---|---|
| AR-1 | **Deriva repositório↔produção.** Uma rodada real hoje exercita um sistema que nenhum teste jamais viu | **CRÍTICO** |
| AR-2 | **Identidade por string no núcleo.** Cada nova classe de documento traz nova classe de bug de rótulo | **CRÍTICO** |
| AR-3 | **Modelo fora do sistema.** Bloqueia 6 dos 15 estágios do alvo | ALTO |
| AR-4 | **Dependência do n8n.** 40 nós num SaaS, republicados à mão, 26 funções duplicadas como texto em JSON | ALTO |
| AR-5 | **Dependência de um provedor de IA.** Já materializado: 72 documentos perdidos por billing numa rodada de 190 | ALTO |
| AR-6 | Concentração: `modelo-institucional.ts` 6.689 + `export.ts` 3.482 + `export-modelagem.ts` 2.340 = 12.511 linhas decidindo o arquivo do comitê | MÉDIO |
| AR-7 | Multi-tenancy inexistente | MÉDIO hoje / ALTO como plataforma |
| AR-8 | Massa documental com três documentos de estado desalinhados | MÉDIO |

### De dado e financeiros

| # | Risco | Estado |
|---|---|---|
| DR-1 | Auto-aceite sem concordância medida | **aberto, sem caminho** |
| DR-2 | Double counting por subtotal (`secao` achatada) | mitigado, causa aberta |
| DR-3 | **Sem eliminação intragrupo** — `MUTUOS`/`FAT_INTRAGRUPO` declarados e não lidos | aberto e declarado |
| DR-4 | Moeda sem conversão — grupo multimoeda não consolida | limite honesto |
| DR-5 | **Premissa de giro agregada** — 1.200 dias em giro na própria fixture | **aberto** |
| DR-6 | Restatement sem eixo próprio no fato | aberto |
| DR-7 | Circularidade cortada (juros sobre saldo de abertura) | **declarado na aba** |
| DR-8 | `fn_soma_secao` soma `valor_num` cru e devolve a unidade MODAL, enquanto as reconciliações aplicam `fn_valor_em_base` linha a linha — assimetria a verificar nos chamadores | **a confirmar** |
| DR-9 | Lineage morre na projeção | aberto |
| DR-10 | Apresentação como segunda fonte — não ocorre hoje, mas é o desfecho por construção | risco futuro |

### De teste e validação

| # | Risco |
|---|---|
| TR-1 | Tudo é medido sobre extração FIEL. O arnês de 25 variantes é a resposta certa, mas as variantes são sintéticas; a régua de produção cobre 20 documentos |
| TR-2 | O portão mede uma instalação que não é a de produção (`--ignore-scripts` × Vercel) — declarado no CI |
| TR-3 | O golden set não pode existir: a rotulagem manual saiu do produto (PR #153) e o portão ficou |
| TR-4 | Duas categorias de portão fora do espelho do `CLAUDE.md` (C4) |
| TR-5 | O motor de fórmulas tem limites declarados (célula vazia = 0; `null` = não sei) |
| TR-6 | Nenhum teste de carga. Maior book: 38 documentos. Maior rodada real: 190, com 39% de falha |
| TR-7 | Restauração nunca testada — backup é crença, não controle |

---

## 9. Conclusão sobre a viabilidade

**Viável, com folga — e a maior parte do valor já está construída.**

O que convence não são os portões verdes; é COMO eles chegaram a verde. Este repositório demonstra,
repetidamente e com evidência, a competência mais difícil em software financeiro: **descobrir o
defeito que não produz erro**. O erro de escala de ~496×, as 792 observações descartadas do SGS, a
moeda capturada e jogada fora, o subtotal contado duas vezes, a fixture que nasceu vazia, o
invariante que passou verde porque `toFixed(2)` comia a diferença — todos rodavam sem erro, todos
entregavam número errado, e todos foram achados, medidos e travados por invariante.

**Os três obstáculos são de naturezas diferentes, e só um é técnico.**

1. **Operacional:** o sistema testado não é o implantado. Dias de trabalho, e é o que mais paga.
2. **De produto:** a visão escrita nega a modelagem que o código já faz. É decisão do dono, não
   tarefa de engenharia, e trava a priorização.
3. **Arquitetural, e o único caro:** identidade canônica e motor de cálculo. Cirurgia localizada em
   fundação sadia — não reconstrução. Ambas se apoiam no que já existe: `campo_extraido` vira camada
   de evidência sem mudar; `avaliar-formula.mts` vira portão de migração do motor.

**O risco real não é técnico.** É que o volume de documentação e o ritmo de rodadas de correção
pontual consumam a capacidade antes das duas mudanças estruturais acontecerem. O padrão está visível
no git log — oito rodadas tratando sintomas da mesma causa de identidade por string.

**A arquitetura-alvo e o roadmap derivados desta auditoria estão em
`Arquitetura do Sistema/3 Estado e Execução/ARQUITETURA_ALVO_E_ROADMAP.md`.**

---

## 10. O que esta auditoria NÃO cobre — dito, não omitido

- **Produção.** Não houve acesso ao Supabase de produção nem à instância do n8n. Tudo que se afirma
  sobre o estado implantado vem do `ESTADO.md` e é citado como tal.
- **Nenhum lote real foi executado.** As conclusões sobre a rodada de 190 documentos são leitura de
  registro, não medição.
- **Não li linha a linha:** as 119 migrations, as ~7.400 linhas de telas do portal, os geradores dos
  books, nem `export-modelagem.ts` (2.340 linhas).
- **DR-8 está marcado "a confirmar"** de propósito: vi a assimetria em `fn_soma_secao` e não
  rastreei todos os chamadores. Afirmar defeito sem rastrear seria a mesma família de erro que este
  projeto combate.
- **Sonar não foi reexecutado.** Os ~770 achados em escopo real vêm do `SONARCLOUD.md`.
