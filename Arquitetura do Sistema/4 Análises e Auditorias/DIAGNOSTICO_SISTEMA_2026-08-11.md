# Diagnóstico do sistema — 2026-08-11

**Método:** leitura do `main` em `13a7a11` (PR #111, CI verde na execução `31215433081`), das
quatro suítes rodadas localmente, dos artefatos de F0 (`Arquitetura do Sistema/2 Especificação/f0/04`, `Arquitetura do Sistema/2 Especificação/f0/07`, `Arquitetura do Sistema/2 Especificação/f0/08`), dos `docs/`, do
`HANDOFF.md` e do PR #112 (aberto, em *draft*). Números citados foram medidos, não estimados; onde
não foi possível medir, está escrito que não foi.

**Quem escreve:** revisão de engenharia sênior, com o viés declarado de procurar **o que está
errado**. A seção 7 existe para equilibrar isso — há coisas aqui que não se deve mexer.

---

## 1. Veredito em uma página

**O que este sistema faz excepcionalmente bem, e é raro:** ele desconfia de si mesmo. A prática de
religar o defeito antes de aceitar que um teste o cobre, a recusa em apagar dado, o hábito de
transformar cada incidente em assert com o número exato de antes, a doutrina de "uma conta, um
lugar" — isso é maturidade de engenharia acima da média do mercado. Os quatro incidentes de dupla
contagem (caixa, dívida, subtotal informado, tributo) foram todos encontrados **por dentro**, e
todos fecharam com teste que reprova religado.

**O problema central não é qualidade de código. É que o sistema prova o GERADOR muito melhor do que
prova o RESULTADO, e mede o motor muito melhor do que mede o produto.** Três sintomas do mesmo fato:

1. **877 asserts verdes e o arquivo entregue estava errado** (sessão 40, seis defeitos de número).
   A resposta foi o `auditar-xlsx.mts` — certa, e insuficiente: ela cobre o arquivo, não a decisão
   que o arquivo sustenta.
2. **A fixture é sistematicamente mais fácil que a produção.** Está documentado três vezes (a do
   `0105`, a do `0113` sem conta tributária, o `medir-auto-aceite` medindo o próprio instrumento).
   O `book-canastra` (PR #112) ataca isso e está parado em *draft*, sem a fixture de extração — que
   é justamente a metade que provaria a ingestão.
3. **Nenhum número de produção governa nada.** Não há golden set, não há concordância medida, não há
   custo por caso em produção, não há métrica de quantos casos passaram pelo Portão 2 nem de quanto
   tempo levaram. O dial de autonomia está onde nasceu na F1, em 2026-07. `Arquitetura do Sistema/1 Visão e Doutrina/03` chama F4 de
   "loop permanente"; ele nunca começou.

**O risco nº 1, hoje:** o produto está tecnicamente pronto para gerar um arquivo que vai a comitê, e
**não existe nada entre esse arquivo e o comitê** além de um checklist humano de 10 itens que nunca
foi executado sobre um export pós-#111. Se um número sair errado agora, ele sai errado dentro de uma
decisão de crédito.

**O risco nº 2:** as proteções do `main` foram removidas em 07/08. Um repositório com 112 PRs, cujo
único revisor de fato é o CI, hoje aceita merge vermelho e push direto.

---

## 2. O OUTPUT — onde está o maior ganho disponível

Esta é a seção que importa. O motor está bom; o que ele entrega ainda não responde à pergunta do
mandato.

### 2.1 O arquivo diagnostica, mas não dimensiona (ALTO impacto, BAIXO esforço)

O `Output` do v35 diz: DSCR entre 0,3 e 0,7 contra corte de 1,2, ND/EBITDA de 5,1x a 10,8x, e o
revolver saindo de 48.406 para **122.216 em 2030**. Está certo, e é muito melhor do que a dívida
rolada para sempre que havia antes. Mas **o revolver é uma ficção de fechamento**: ele existe para o
balanço fechar, não porque alguém vai emprestar 122 milhões a uma empresa com DSCR de 0,3.

Quem lê um caso de reestruturação precisa de três números que o arquivo tem os insumos para dar e
não dá:

| Número | Onde já existe o insumo | O que falta |
|---|---|---|
| **Necessidade de recursos do pico** e em que ano | `Cash Flow` já tem "Caixa antes do revolver" e "quanto falta para o caixa mínimo" por ano (`modelo-institucional.ts:2942-2949`) | agregar: `MIN()` da série, o ano do mínimo, e o acumulado |
| **Decomposição do buraco** — quanto é serviço da dívida, quanto é giro, quanto é capex, quanto é tributo | as quatro linhas já são projetadas em abas com dono único | um bloco de quatro linhas que some cada uma no horizonte |
| **Capacidade de pagamento** — quanto de dívida esta empresa suporta com DSCR = 1,2 | DSCR já é fórmula com o corte em célula editável | inverter a conta: dívida sustentável = EBITDA ÷ (corte × custo médio) |

São ~15 linhas de fórmula numa aba que já existe. É a diferença entre "o modelo mostra que não
fecha" e "o modelo diz de quanto é o rombo, de onde ele vem, e qual dívida esta empresa aguenta" —
que é a frase que um comitê precisa ouvir.

### 2.2 O cenário é um interruptor, não uma comparação (ALTO impacto, MÉDIO esforço)

`Output!$G$2` é o único seletor, e todas as abas leem dele via `CHOOSE`. A decisão de ter um
interruptor só é **certa** (dois interruptores produziriam um arquivo em dois cenários ao mesmo
tempo, sem nada denunciar). A consequência é que o arquivo mostra **um cenário por vez**, e a
comparação base × cliente × stress — que é o motivo de existirem três — não está em lugar nenhum.

O caminho barato: um bloco "Resumo dos três cenários" com 6 a 8 métricas (receita do último ano,
EBITDA, ND/EBITDA, DSCR mínimo, necessidade de pico, ano do pico), calculado **independentemente do
seletor** — as três cascatas em paralelo para essas poucas linhas, não para o modelo inteiro. O
caminho caro (e desnecessário) seria triplicar as 14 abas.

> **FECHADO em 20/08 (sessão 54), com a fronteira menor do que esta lista.** O bloco existe no
> `Output` (`RESUMO DOS TRÊS CENÁRIOS`) alimentado por uma cascata paralela na aba de receita, e traz
> receita líquida, crescimento, EBITDA e margem para os três cenários ao mesmo tempo. **ND/EBITDA,
> DSCR e pico de caixa ficaram fora, por decisão medida:** eles não saem da cascata de receita —
> exigiriam replicar a cascata de dívida e o fluxo de caixa por cenário, que é a triplicação que este
> mesmo parágrafo chama de desnecessária. Um bloco que os mostrasse lendo a dívida de UM cenário seria
> pior que a ausência: pareceria comparação sem ser. O que ficou fora está escrito na própria aba, ao
> lado do bloco. Guardado por 20 asserts em `verificar-export.mts` (36), incluindo um CHECK que mede a
> distância entre a cascata paralela do cenário ativo e as linhas ativas — zero por construção.

### 2.3 A proveniência do arquivo entregue encolheu, e ninguém decidiu isso (MÉDIO, BAIXO)

Antes do PR #109 o arquivo de modelagem carregava as abas de dado, e cada célula delas tinha nota de
proveniência com **documento, página, confiança e status de aceite** (`export.ts:708-770`). O #109
separou os dois exports — decisão certa, medida (zero referências cruzadas) — e com as abas de dado
saiu essa camada.

O que sobrou no arquivo de comitê é a nota da aba `Premissas`: `"Extraído de <arquivos>"` mais a
conversão de unidade (`modelo-institucional.ts:586-598`). Ou seja: **sobrou o nome do documento, e
sumiram a página, a confiança e quem aceitou.** Para um arquivo que vai a credor, "de onde veio o
106.580" hoje se responde com o nome do arquivo, não com a linha.

Não é regressão de número — é redução de rastreabilidade que aconteceu como efeito colateral de
outra decisão. Ou se aceita explicitamente (e se registra no `Arquitetura do Sistema/2 Especificação/f0/07`, que promete proveniência por
célula), ou se leva página/confiança/aceite para a nota da `Premissas`, que é barato.

### 2.4 Metade do output especificado não existe (ALTO, ALTO)

`Arquitetura do Sistema/2 Especificação/f0/07` define **dois modos de entrega**. O Modo B (Excel) está entregue e maduro. O **Modo A — base
viva no portal, consultável por entidade × período × conta, com proveniência e status de aceite ao
passar o mouse, refletindo o estado em tempo real** — não existe: a navegação de dado é por
documento (`/casos/[id]/documentos/[docId]`), e não há tela que cruze entidades e períodos. Não há
uso de Realtime em lugar nenhum do portal (grep: zero ocorrências).

Consequência prática: para responder "quanto é Fornecedores em todas as empresas em 2025?" o
analista **exporta um Excel**. O portal virou um painel de ingestão com um botão de download; a
"base viva" que `Arquitetura do Sistema/2 Especificação/f0/07` chama de entrega principal é o Excel.

Isso é uma escolha legítima — mas está tomada por omissão, não por decisão. Vale escrever qual das
duas é a verdade: ou o Modo A entra no roadmap, ou `Arquitetura do Sistema/2 Especificação/f0/07` passa a dizer que o Excel é a entrega e o
portal é a esteira.

### 2.5 O que a `Arquitetura do Sistema/2 Especificação/f0/08` prometeu fasear continua faseado (MÉDIO, MÉDIO)

O faseamento honesto de `Arquitetura do Sistema/2 Especificação/f0/08` lista o que fica de fora "até a extração isolar as linhas-conceito":
liquidez seca/imediata, cobertura de juros, ciclo de caixa (PMR/PME/PMP), ROA/ROE, Altman Z''.

Só que **o modelo institucional passou a isolar quase tudo isso** desde então: `Working Capital` tem
contas a receber, estoques e fornecedores separados; `ST Inv. & Debt` tem dívida bruta e caixa; a
DRE tem despesa financeira. O bloqueio documentado em `Arquitetura do Sistema/2 Especificação/f0/08` **não vale mais para o arquivo de
modelagem** — vale só para o export de dados. Ninguém revisitou.

Ciclo de caixa e cobertura de juros são exatamente os índices que um analista de RX olha primeiro, e
hoje eles estão a uma fórmula de distância.

### 2.6 O modelo não tem o que fazer com a resposta que ele dá (MÉDIO, ALTO — decisão de produto)

Quando o `Output` diz DSCR 0,3 e ND/EBITDA 10,8x, a próxima pergunta do mandato é: **qual
reestruturação resolve?** Alongamento de prazo, carência, haircut, conversão, new money — o modelo
não tem nenhuma alavanca disso. O `CAPEX FINANCING` foi deliberadamente excluído para o rombo
aparecer (decisão certa); o passo seguinte natural é a alavanca que **fecha o rombo declaradamente**:
uma linha de "reperfilamento" com prazo e carência editáveis, comparando o antes e o depois.

Isto é escopo novo, não correção. Fica registrado como a pergunta que o produto vai receber assim
que o primeiro arquivo chegar a um comitê.

---

## 3. Arquitetura e código

### 3.1 Três arquivos concentram 30% do código, e nenhum tem teste próprio

Medido: 34.349 linhas nos arquivos de código (`.ts/.tsx/.mts/.mjs/.sql`), das quais **10.207 em três
arquivos** — `modelo-institucional.ts` (4.546), `export.ts` (3.261), `export-modelagem.ts` (2.400).

A única prova desses três é o `verificar-export.mts`, que monta o workbook inteiro e afirma coisas
sobre o resultado. É uma suíte de integração de 512 asserts fazendo o trabalho de testes de unidade
que não existem. O efeito colateral aparece na prática: quando um assert reprova, ele diz que a
célula `H42` está errada — não qual das 40 funções a produziu.

Não recomendo quebrar os arquivos por tamanho (a coesão é real e os comentários são o melhor ativo
do repositório). Recomendo extrair as **funções puras de cálculo** (prazo implícito, SAC, composição
índice×spread, rateio de capex, natureza tributária) para um módulo com teste direto de entrada e
saída. São dezenas de linhas com dezenas de asserts, e o retorno é o diagnóstico ficar fino.

### 3.2 Não existe "o schema atual" — existem 51 migrations que é preciso ler em ordem

`fn_recomputar_completude` foi republicada em `0004`, `0006` e `0036`. `fn_avaliar_portao2` em
`0037` e agora `0106`. Para saber o que uma função faz hoje, é preciso saber qual foi a última
migration que a tocou — e o único jeito de descobrir é ler as 51.

Isso já custou uma rodada (o incidente da `0101`, mergeada e não aplicada) e vai custar de novo.
**Correção barata e de alto retorno:** o CI já sobe um Postgres e aplica tudo do zero; que ele
também rode `pg_dump --schema-only` e versione o resultado em `Supabase/schema.sql`, com
`git diff --exit-code`. Passa a existir um arquivo que responde "como está o banco hoje", revisável
em PR — e a divergência entre a soma das migrations e o schema esperado morre no PR.

**Segunda correção, ainda mais barata:** tabela `schema_migrations` gravada por cada migration, e um
canto do portal mostrando "banco atrás do código: faltam aplicar N". Da tela, hoje, "aplicada" e
"não aplicada" têm exatamente a mesma aparência — é a frase do próprio `Supabase/README.md`.

### 3.3 Espelhos: três, dois com assert

O padrão "a regra vive no Postgres, o resto espelha" é certo. Cada espelho, porém, é um lugar onde a
verdade pode divergir em silêncio:

| Espelho | Protegido por |
|---|---|
| JSON dos nós do n8n ↔ `N8N/lib/` | `git diff --exit-code -- N8N/` no CI ✅ |
| piso do motivo de rejeição (`0106` ↔ `portal/src/lib/pendencia.ts`) | assert `(0114)`, que lê o SQL ✅ |
| tipos de pendência (`pendencia_tipo` no enum ↔ as listas de `portal/src/lib/types.ts`) | **nada** ❌ |

O terceiro é o que produziu o buraco corrigido nesta rodada: as listas do portal são enumerações
manuais dos tipos, e os tipos que ninguém listou não apareciam na tela. A correção foi listar por
complemento; o assert que faltaria é comparar o enum do banco com o que a tela sabe nomear.

### 3.4 A autorização é binária, e a spec pede papéis

`0003` estabelece: toda tabela exposta tem policy "usuário autenticado pode tudo". Não há papel de
usuário em lugar nenhum do schema. Consequências diretas, todas verificadas:

- `Arquitetura do Sistema/2 Especificação/f0/04` exige **papel sênior** para aceitar com ressalva → a ressalva **não pode ser
  implementada** como especificada. É por isso que o card do Portão 2 fala de um teto de 3 ressalvas
  que ninguém consegue criar (nenhum código de produção escreve `aceita_com_ressalva`);
- a rejeição de pendência entregue nesta rodada pode ser feita por **qualquer usuário
  autenticado**, inclusive sobre uma não-sobrepujável. Foi mitigada com motivo obrigatório, trilha e
  contagem publicada — mas mitigação não é controle de acesso;
- não há segregação entre quem prepara e quem aprova, que é o controle mais básico deste tipo de
  processo.

Com duas pessoas, isso é aceitável e consciente. Com a terceira, deixa de ser.

### 3.5 Três dos seis estados da pendência nunca foram escritos por código

`Arquitetura do Sistema/2 Especificação/f0/04` define seis estados. `aberta` (motor) e `resolvida` (`sistema:*`) sempre existiram;
`rejeitada` passou a existir nesta rodada. **`em_correcao_interna`, `reenviada_ao_cliente` e
`aceita_com_ressalva` continuam sem nenhum caminho** — o `reenviada_ao_cliente`, em particular, é o
estado que representa a ação mais comum do processo real ("pedi o documento de novo") e o motor de
pendências não sabe registrá-la.

Efeito colateral silencioso: o Portão 2 conta os três estados de tratamento como bloqueio, e a tela
até esta rodada só lia `aberta`. Enquanto ninguém escreve os outros dois, os números batem por
acaso.

---

## 4. Testes e evidência

**O que está muito bom:** 4 suítes + auditor de arquivo + aceite humano, os contadores tratados como
invariante ("se cair, alguém apagou cobertura"), o hábito de religar o defeito. O e2e cobrindo a
costura extração → banco → export é a peça mais valiosa do conjunto, e foi a última a chegar.

**As três lacunas reais:**

1. **A fixture é o melhor caso.** O `book-vertentes` é PDF gerado por `reportlab`, texto limpo,
   layout conhecido, extração fiel por construção. Todo defeito de leitura de documento *real* —
   scan torto, carimbo, coluna deslocada, escala mista — está fora do alcance de todas as suítes. O
   `book-canastra` do PR #112 é a resposta certa e está a meio caminho.
2. **Não existe golden set.** `Arquitetura do Sistema/1 Visão e Doutrina/01` exige concordância medida no estrato que vai a produção
   antes de tratar N2 como autonomia medida; o `medir-auto-aceite.mts` diz, no próprio cabeçalho,
   que rodado contra fixture ele mede o instrumento, não o modelo. O dial está em N2 para extração
   de linhas com **zero medição de campo**.
3. **A cobertura que ninguém olha.** A métrica mais importante do auto-aceite, segundo o próprio
   script, não é a concordância — é quantas linhas auto-aceitas **nenhum gabarito consegue
   conferir**. Esse número não é publicado em lugar nenhum.

---

## 5. Operação, segurança e processo

| Achado | Evidência | Consequência |
|---|---|---|
| **`main` sem proteção** | rules removidas em 07/08 | merge vermelho e push direto são possíveis hoje |
| **Zero observabilidade** | só `console.error` no portal; nenhuma métrica, nenhum alerta | uma falha em produção só aparece quando alguém abre a tela |
| **Custo medido offline, não em produção** | `medir-custo-book.mjs` (PR #112) calcula sem chamar a API | não há custo por caso real; o teto de lote é uma estimativa recalibrada uma vez |
| **Migration aplicada à mão** | `Supabase/README.md`, lista de comandos | ver 3.2 — já custou uma rodada |
| **`HANDOFF.md` com 5.176 linhas é a memória do projeto** | o cabeçalho já ficou 17 PRs desatualizado; hoje diz "#110" com o `main` em #111 e o #112 aberto | quem chega lê o estado errado — e o documento sabe disso, tem um parágrafo pedindo que se atualize |
| **Sem backup/retenção declarados** | nada em `docs/` sobre restore | dado de cliente em Supabase, sem procedimento de recuperação escrito |

Sobre o `HANDOFF.md`: a solução não é encurtar (o histórico tem valor real e a prosa é o que faz
este projeto ser retomável). É **separar o estado do histórico**: um `ESTADO.md` curto, com um
assert de CI conferindo que o último PR citado bate com o `git log`, e o `HANDOFF.md` como arquivo
morto por sessão. O cabeçalho falha porque é a única parte do documento que precisa mudar toda
rodada, e está no mesmo arquivo das partes que nunca mudam.

---

## 5-A. O que foi EXECUTADO nesta rodada (11/08/2026)

O diagnóstico acima foi escrito antes; este bloco é o depois, e fica no mesmo arquivo porque um
diagnóstico sem o que aconteceu com ele vira documento morto.

| # | Item | Estado | Onde |
|---|---|---|---|
| 1 | Necessidade de recursos no `Output` | ✅ | pico, ano do pico, acumulado, decomposição dos usos, dívida sustentável e serviço suportado — asserts `(0115)` |
| 2 | `Supabase/schema.sql` gerado e conferido | ✅ | `Supabase/test/run.sh` + passo de CI; 157 objetos, 84 funções |
| 3 | Índices faseados da `Arquitetura do Sistema/2 Especificação/f0/08` | ✅ | ciclo de caixa (PMR/PME/PMP + operacional/financeiro), asserts `(0116)`. **Correção do que eu havia escrito**: cobertura de juros e liquidez seca JÁ existiam; o que faltava era o ciclo |
| 7 | Papel de usuário | ✅ | `usuario_papel` + `fn_papel()`, default no menor privilégio (`0107`) |
| 7b | Ressalva, enfim implementável | ✅ | `fn_ressalvar_pendencia` com as quatro exigências de `Arquitetura do Sistema/2 Especificação/f0/04` |
| 8 | Estados de tratamento | ✅ | `fn_tratar_pendencia` + botões "pedi de novo" / "em correção interna" |
| 11 | `ESTADO.md` + guarda de frescor | ✅ | o `run.sh` reprova quando a migration mais nova não está citada |
| — | Rejeição de pendência (o pedido original) | ✅ | `0106`, e apertada pela `0107` (lista fechada exige sênior) |
| — | Espelho do n8n divergente | ✅ | o `main` estava vermelho: o `#112` recalibrou o custo por chamada e não regerou o JSON |

### E o que eu NÃO executei, com o motivo — não com uma promessa

**Resumo dos três cenários lado a lado (item 5).** Continua sendo o item de maior valor não feito, e
a razão de não ter saído nesta rodada é técnica, não de tempo. O modelo tem **um interruptor de
cenário** (`Output!$G$2`) e toda projeção lê `CHOOSE` dele. Para publicar as três colunas ao mesmo
tempo só há três caminhos, e dois são ruins:

- *replicar uma cascata compacta por cenário* — passa a existir um segundo lugar que calcula EBITDA,
  e esse é exatamente o defeito que os quatro incidentes de dupla contagem produziram. **Violaria a
  invariante central do projeto** ("uma conta, um lugar") em nome de uma tela;
- *Data Table do Excel* (`{=TABLE(,G2)}`) é a resposta tecnicamente correta — uma tabela de uma
  variável sobre a célula de cenário recalcula o modelo inteiro para os três valores. Escrever isso
  via ExcelJS é possível mas frágil, e a fragilidade cai justamente onde o arnês local **não
  consegue provar** (o comportamento é do Excel na abertura, não do arquivo);
- *bloco preenchido à mão* depois de trocar o cenário — honesto, mas é trabalho manual em um produto
  cujo argumento é não ter trabalho manual.

A recomendação, então, é a segunda opção **com um item de aceite humano próprio** em `Arquitetura do Sistema/6 Referência/ACEITE.md`
— porque é o único jeito de conferir o que o arnês não alcança. É uma rodada inteira, não um
acréscimo.

**Proveniência completa na `Premissas` (item 9).** O caminho barato que tentei — reaproveitar os
`campos` que a rota já busca — casa a linha do modelo com o campo extraído pelo **rótulo**, e a
normalização que o banco usa (`fn_normalizar_texto`) não tem equivalente garantido em TypeScript.
Casar por texto cru acerta o caso comum e falha em silêncio nas variações de grafia, publicando
"sem aceite" para linhas que têm aceite — uma nota de proveniência errada é pior que a ausência
dela. O caminho correto é estender `fn_linhas_para_modelagem` para devolver confiança, página e
status de aceite; como isso muda o **tipo de retorno**, exige `drop function` + recriação (a
restrição que a `0005`/`0006` já documentam), mais a rota, o tipo e a nota. Contido, mas é fatia
própria.

**Itens 4, 6, 12, 13 e 14** seguem como estavam: são do dono (proteção do `main`, golden set),
de outro PR (fixture do `book-canastra`) ou fatia grande com decisão de produto antes (Modo A,
observabilidade).

## 6. Backlog priorizado

Ordem por (impacto no output) ÷ (esforço). Os quatro primeiros cabem em uma rodada cada.

| # | Item | Onde | Impacto | Esforço |
|---|---|---|---|---|
| 1 | **Bloco "Necessidade de recursos"** — pico, ano, acumulado, decomposição em quatro linhas, dívida sustentável a DSCR 1,2 | `Output` | 🔴 alto | baixo |
| 2 | **`Supabase/schema.sql` gerado pelo CI** + `schema_migrations` com aviso no portal | CI, `Supabase/` | 🔴 alto (para de repetir a `0101`) | baixo |
| 3 | **Índices que a `Arquitetura do Sistema/2 Especificação/f0/08` faseou e o modelo já isola** — cobertura de juros, ciclo de caixa, liquidez seca | `Output`/`Balance Sheet` | 🟠 médio-alto | baixo |
| 4 | **Fechar o PR #112 com a fixture de extração** do `book-canastra` | `Dados de Teste/`, `Supabase/test/` | 🔴 alto (é a única prova sobre dado sujo) | médio |
| 5 | **Resumo dos três cenários** lado a lado | `Output` | 🔴 alto | médio |
| 6 | **Proteções do `main` de volta** (approvals em 0, `suítes` obrigatório) | GitHub | 🔴 alto | trivial |
| 7 | **Papel de usuário** (analista/sênior) → destrava a ressalva de `Arquitetura do Sistema/2 Especificação/f0/04` e limita quem rejeita | `Supabase/`, portal | 🟠 médio | médio |
| 8 | **`reenviada_ao_cliente` e `em_correcao_interna`** com ação de tela | portal, `Supabase/` | 🟠 médio | médio |
| 9 | **Proveniência completa na `Premissas`** (página, confiança, aceite) | `modelo-institucional.ts` | 🟠 médio | baixo |
| 10 | **Extrair as funções puras de cálculo** para módulo com teste direto | `portal/src/lib/` | 🟡 médio (velocidade futura) | médio |
| 11 | **`ESTADO.md` + assert de frescor no CI** | raiz, CI | 🟡 médio | baixo |
| 12 | **Golden set físico** (20-30 docs reais por tipo) e concordância medida | processo | 🔴 alto (destrava a F4 inteira) | alto |
| 13 | **Modo A de `Arquitetura do Sistema/2 Especificação/f0/07`** — base viva consultável — ou a decisão escrita de que ele não vem | portal | 🟠 médio | alto |
| 14 | **Métrica e alerta de pipeline** (documentos/dia, falhas, custo por caso) | n8n, portal | 🟠 médio | médio |

---

## 7. O que eu NÃO mudaria

Um diagnóstico que só lista defeitos convida a estragar o que está certo. Estas decisões estão bem
tomadas e devem ser defendidas contra a próxima refatoração:

- **A regra no Postgres, o portal encaminhando.** É o que permite que a tela, o teste e a ação leiam
  a mesma função. Não mover regra para o TypeScript "por conveniência".
- **Recusa retornada no payload, não `raise`.** A trilha da tentativa é mais valiosa que a
  elegância da exceção.
- **Nada é apagado.** Duplicidade vira achado, pendência rejeitada continua na tabela, ressalva
  expirada volta a bloquear na leitura em vez de depender de job.
- **Um interruptor de cenário só.** Dois seriam um arquivo mentindo em silêncio.
- **Premissa nasce vazia.** O sistema não chuta crescimento nem margem, e a coluna projetada fica
  zero em vez de virar estimativa que ninguém pediu.
- **Os comentários longos no código.** São caros de escrever e são a razão de este repositório ser
  retomável por outra pessoa (ou por outro modelo) meses depois. Não são ruído.
- **`CAPEX FINANCING` fora.** É a hipótese que deixa o rombo aparecer.
