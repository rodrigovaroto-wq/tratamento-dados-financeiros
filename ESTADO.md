# Estado do projeto — leia isto antes do `HANDOFF.md`

Este arquivo responde **onde o projeto está agora**. O `HANDOFF.md` responde **como chegou aqui** —
5.000 linhas de histórico sessão a sessão, que continuam valendo como referência e não precisam ser
lidas para retomar.

> **Por que os dois são arquivos separados.** O cabeçalho do `HANDOFF.md` já passou 17 PRs congelado
> em "PR #70, migrations até `0034`", e mandava quem chegava começar errado. A causa não é descuido:
> é que a parte que muda TODA rodada morava no mesmo arquivo das partes que nunca mudam, e um
> arquivo que quase nunca se edita não convida a editar nada. Aqui só há o que muda — e o
> `db/test/run.sh` reprova quando a migration mais nova não está citada abaixo.

## Onde está

| | |
|---|---|
| **Última migration** | `db/migrations/0127_o_dial_obedecido.sql` |
| **Schema materializado** | `db/schema.sql` — gerado pelo `db/test/run.sh`, conferido pelo CI |
| **Suítes** | n8n 293 · export 568 · e2e 46 · banco (735 asserts, 72 migrations do zero, os DOIS books) |
| **CI** | `.github/workflows/suites.yml` — push, PR e `workflow_dispatch` |

## O portal (17/08) — navegação, marca e o fim de vida do mandato

- **Barra lateral retrátil** com duas seções que não são simétricas de propósito: *Novo mandato* é
  AÇÃO (fixa, sem filhos) e *Mandatos* é LUGAR (abre e lista os **ativos**). O estado — recolhida e
  seção aberta — mora no navegador via `useSyncExternalStore`, para a barra não "piscar" no lugar
  errado a cada carga. Ela some na tela de abrir mandato, que é de tela cheia.
- **A marca entrou** (`portal/public/logo-oria*.svg`): o original do dono com o fundo creme trocado
  por transparência, **sem redesenhar nada**. O SVG EMBUTE a arte original — vetorizar exigiria
  traçar, e traçar é aproximar. Sextante no cabeçalho e no favicon; a lockup completa no login,
  onde há altura para ela.
- **Fechar ≠ excluir** (`0114`): `caso.status` diz onde o mandato está no trabalho, e não respondia
  "ainda estamos nisso?". `fechado_em` responde, preservando tudo — para apagar continua existindo
  `fn_excluir_caso`. A lista ganhou o segundo rótulo (**Ativo/Fechado**), uma descrição derivada de
  uma linha (documentos · pendências · data) e as duas ações no rodapé de cada item.

> **Para o dono:** a `0114` precisa ser aplicada no Supabase. Sem ela, a coluna não existe e a lista
> trata todo mandato como ativo — a tela não quebra, mas o botão de fechar falha.

## O portal (18/08) — a home deixou de ser a lista

- **A barra lateral rola sozinha.** O `nav` era `sticky` mas não tinha altura: com mais mandatos
  do que cabe na tela, os últimos ficavam abaixo da dobra do elemento grudado e só apareciam
  quando a PÁGINA terminava de rolar. Agora ela tem a altura da viewport abaixo do cabeçalho e a
  lista rola dentro dela, com o topo (Painel, Novo mandato, Mandatos) parado.
- **`/casos` virou o PAINEL e a lista completa foi para `/casos/todos`.** A home repetia inteira a
  lista que a barra já dá em um clique — duas telas para "o que existe", e nenhuma para *o que
  precisa de mim agora*. O painel tem três blocos: indicadores da mesa (mandatos, documentos,
  linhas extraídas, pendências e quantas bloqueiam), a **fila de pendências atravessando os
  mandatos** ordenada por severidade — que antes só existia dentro de um caso por vez —, e o que
  chegou, com as linhas de cada documento (zero linhas em vermelho).
- **A regra que saiu disso:** nenhuma função da barra lateral se repete no conteúdo. O botão
  "Novo mandato" saiu da lista completa; quem precisa dele o tem na barra, sempre visível.
- **Os sete indicadores do painel** (escolhidos pelo dono): mandatos ativos, mandatos fechados,
  linhas extraídas, tempo médio de processamento, gasto médio de API por mandato, gasto total de
  API, pendências em aberto.
- **A abertura e a ilustração.** O painel abre com uma cena de ~3s — o sextante da marca desenhado
  em vetor próprio (a arte original NÃO é tocada), com o limbo crescendo e a constelação acendendo
  em cascata. Toca **uma vez por sessão** do navegador, **qualquer gesto corta**, e
  `prefers-reduced-motion` pula por completo. O mesmo motivo fica de fundo no painel a ~15% de
  opacidade, na goteira à direita: **gira com a rolagem** e a constelação deriva com o ponteiro.

- **O custo passou a durar (`0115`)**, e com ele veio o **oitavo indicador: cobertura da extração**.
  `lote_execucao` guarda uma linha por execução de ingestão (custo real, custo estimado, tokens,
  linhas, cobertura), gravada pelo nó novo `Gravar Uso do Lote`. A chave `(caso_id, execucao_ref)`
  é o que impede o custo de sair **dobrado**: o `Resumo de Custo` roda uma vez por ramo do lote e
  as duas passadas trazem o total inteiro.

> **PARA OS TRÊS INDICADORES NOVOS ACENDEREM, DUAS COISAS PRECISAM ACONTECER FORA DO GIT:** aplicar
> a `0115` no Supabase e **reimportar o `n8n/workflow.e1-ingestao.json`** (o n8n executa o JSON
> importado, e merge não reimporta). Sem a migration, a tela mostra um traço com a causa escrita —
> não zero. Sem a reimportação, a tabela existe e fica vazia. O **tempo médio** não depende de
> nenhuma das duas: é uma janela derivada — de
> `caso.criado_em` (gravado pelo `Upsert Caso`, no envio do intake) até o `criado_em` do último
> documento do mandato; janelas acima de 12h são contadas à parte, porque a partir daí o número
> mede espera pelo cliente, não processamento.

## Estado dos PRs (18/08, sessão 51 — leia isto antes de continuar)

| PR | O quê | Estado |
|---|---|---|
| **#133** | Barra lateral rolável, `/casos` vira Painel (8 indicadores), lista completa em `/casos/todos`, abertura animada, migration `0115` (custo do lote em `lote_execucao`) | **mergeado no `main`** |
| **#134** | Correção: "1.000 linhas extraídas" no Painel era o teto padrão do Supabase/PostgREST (`db-max-rows`), não o dado real | **mergeado no `main`** |
| **sessão 50** | Os sete itens de "o que está aberto", atacados em ordem a pedido do dono: subtotais impressos, mútuos, Modelagem, apelidos, teto de gasto, dedup e o teto de 1000 nas listas | **mergeado no `main`** (PRs #137, #139, #140, #141) |
| **sessão 51** | A aba "Perguntas ao cliente" (`/casos/[id]/perguntas`), o fim do teto de 1000 no portal e a `0122` (o texto que vai ao cliente em português) | **mergeado no `main`** (PR #142) |
| **sessão 51 (cont.)** | Os cinco defeitos de número do EXPORT do Excel, achados rodando o arquivo do caso de referência | **branch `claude/client-question-suggestions-ves2ty`** |

**Nada da sessão 50 ficou pendente de merge** — o `main` já tem os sete itens, e a branch da sessão
51 sai dele. As migrations `0116` a `0121` **já estão aplicadas** (o dono confirmou em 18/08); o que
continua pendente daquela rodada é a reimportação do workflow e a rodada real, no quadro "O próximo
passo".

**O risco que a sessão 50 fechou, e que estava anotado aqui como "não se resolve sozinho":** as
listas de `documento` e `pendencia` do painel continuavam sujeitas ao teto de 1000 do PostgREST.
Agora elas paginam (`portal/src/lib/supabase/paginar.ts`), junto com a lista de mandatos, e o
painel avisa se o teto de segurança for atingido. **A sessão 51 terminou o serviço** — ver "O teto
de 1000 deixou de existir para o portal".

## A rodada v46 (17/08) — o que ela provou e os dois defeitos que ela achou

**9 documentos, 714 linhas, US$ ~0,46.** O defeito que comeu 19 dos 35 documentos na v45 está
**morto**: todos os 9 tiveram extração chamada, e o único sem linha é a certidão negativa — que é o
resultado CERTO (`0111`). Conferido contra o gabarito do gerador:

| | |
|---|---|
| DFC | caixa inicial 3.621 e final 825 — **exatos** |
| DVA | valor adicionado a distribuir 49.110 — **exato** |
| Mútuos | planilha 16.060 (11.160 + 4.900) — **exato**, e o balanço traz 11.400: a divergência plantada de **R$ 240 mil** está no dado, dos dois lados |
| Livro razão | 99 de 99 linhas — **100%**, no documento que motivou as três camadas |
| Balancete | 78 de 78 linhas — **100%** |
| Balanço | 105 de 114 linhas (92%) · DRE 34 de 39 (87%) · DVA 13 de 16 (81%) |

**O que falta são os SUBTOTAIS IMPRESSOS** — "ATIVO CIRCULANTE", "TOTAL DO ATIVO", "RECEITA
OPERACIONAL BRUTA". Eles viraram metadado (`secao`) em vez de linha. Some-se a isso que os
subtotais de subgrupo ("Disponível") FORAM extraídos, e a soma bruta de cada seção dá **exatamente
2× a verdade**. O export já sabe descontar subtotal de subseção; o que falta é o total de topo.

### Defeito 1 — o comparativo não comparava (corrigido)

A mesma conta saía em **três linhas** do Excel, uma por exercício, com as outras colunas vazias. Duas
causas, nas duas pontas:

- **n8n:** `ordem` numerava PARES (conta × coluna) desde que a saída virou agrupada, mas a `0027` a
  define como "posição na leitura do DOCUMENTO". Agora os pares de uma conta compartilham a `ordem`
  da linha que os originou;
- **portal:** o rank que impede dois "Outros" de colapsarem era calculado por VERSÃO, então os três
  valores da mesma conta viravam ocorrência 1, 2 e 3. Agora é por versão **e coluna** — que é o que o
  comentário do próprio bloco dizia querer.

A correção do portal vale para o dado **que já está no banco**: o export da v46 sai alinhado sem
nova extração. Seis verificações novas cobrem as duas formas (agrupada e antiga), e elas reprovam o
código anterior.

### Defeito 2 — a entidade poluída (corrigido, exige reimportar)

O export da v46 mostra `Canastra Industria 2025x2024x2023` como entidade em todas as abas. A
correção está no repositório desde 17/08 (32 entidades limpas, 6 nulas, zero sujas nos 38 nomes),
mas **só entra em produção quando o workflow for reimportado**.

## O próximo passo (para quem retomar depois de 19/08, sessão 53)

**O DONO FEZ AS DUAS COISAS QUE FALTAVAM** — confirmado em 19/08: as migrations estão aplicadas
**até a `0125`** e o `workflow.e1-ingestao.json` foi **reimportado**. Não há mais nada de infra
pendente **daquela rodada**.

> **A sessão 53 acrescentou a `0126`, e ela precisa ser aplicada** — é a única coisa de banco
> pendente agora. Ela não muda o comportamento da ingestão nem do export: cria as tabelas do golden
> set, as funções de medição, e faz `fn_mudar_dial` cobrar concordância medida para subir dial de
> estágio interpretativo. **Nenhum nível de autonomia muda ao aplicá-la**; o que muda é que o N2 da
> extração passa a se declarar como `declarada` em vez de ficar indistinguível de um N2 medido.
> Isso NÃO altera a prioridade do bloqueio abaixo: rodar o book continua sendo o próximo passo.

**Sobrou UM bloqueio, e é grande: NINGUÉM RODOU O BOOK AINDA.**

Isso importa mais nesta rodada do que nas anteriores, e o motivo é aritmético: a sessão 52 acrescentou
**três checagens novas e um conserto de motor que nunca rodaram sobre dado real**. O fixture prova que
elas funcionam sobre extração FIEL; a rodada é a única coisa que prova que elas funcionam sobre o que
o modelo de verdade lê de um PDF sujo.

| | O que a rodada prova | De onde vem | Como saber que passou |
|---|---|---|---|
| 1 | **O fatiamento liga em produção** — ele estava DESLIGADO até agora (zero de 38 documentos fatiados) | sessão 52 | o lote sai com **~44 chamadas de extração**, não 38; o `17_Livro_Razao` vira **4 blocos** |
| 2 | Os **SUBTOTAIS IMPRESSOS** chegam | `0116`, sessão 50 | "TOTAL DO ATIVO" e "RECEITA OPERACIONAL BRUTA" aparecem como LINHA, não só como `secao` |
| 3 | A **divergência de mútuos** aparece quando existe | `0123` | pendência `reconciliacao:mutuos_planilha_vs_balanco`, se o caso tiver planilha e balanço |
| 4 | O **espelho intragrupo** não dá falso positivo | `0124` | `reconciliacao:intragrupo_espelho` só abre se um par de empresas realmente não fechar |
| 5 | A **proveniência** chega ao arquivo | `0125` | a nota de uma célula histórica diz arquivo, página, confiança e aceite — não "Extraído de BALANCO" |
| 6 | `lote_integro` e `cobertura_do_lote` | sessão 50 | `cobertura_do_lote` **não pode vir `null`** (null = a camada 1 não mediu e as outras duas estão mudas) |
| 7 | O custo bate com o previsto | sessões 50-52 | o guarda prevê ~US$ 1,42 para o book sintético contra US$ 1,29 medido (+10%); num mandato real o desvio é o número a olhar |

**Ordem sugerida:** rodar o book num mandato NOVO → exportar o completo → passar o
`auditar-xlsx.mts` e o `docs/ACEITE.md` por cima. Os três juntos levam menos de uma hora e são a
única evidência que nenhuma suíte substitui.

**Com a rodada na mão, a próxima sessão tem duas tarefas que só existem depois dela:**

1. **Recalibrar o limiar de cobertura de 0,85** com pontos REAIS. Hoje ele está calibrado contra os
   38 documentos SINTÉTICOS do book (erro mediano da régua +3%, pior caso 96% com extração perfeita).
   O documento real é mais sujo, e a folga de 11 pontos existe para ele — mas ninguém mediu ainda.
2. **Conferir se o fatiamento cortou onde devia** e se a emenda entre blocos não duplicou linha. A
   `juntarBlocos` limpa emenda repetida, mas ela nunca viu bloco de verdade.

> **A `0118` muda o que se vê ao reenviar um arquivo.** Reenviar o MESMO PDF sem que prompt, modelo
> ou esquema tenham mudado não chama mais a OpenAI: o documento aparece no lote, sem custo e sem
> versão nova. Se a intenção era reextrair de verdade, mude o prompt (ou espere a próxima mudança
> dele) — o fingerprint muda junto e a extração volta a acontecer.

> **Opcional, e só isso: o `Max rows` do Supabase.** O teto de 1000 linhas do PostgREST
> (*Project Settings → API → Max rows*) continua no padrão, e **nenhuma tela depende dele** — o
> `paginar` lê em janelas até o banco acabar. Subi-lo só deixa cada leitura mais barata.

### O DIAL PASSA A SER OBEDECIDO — e dois níveis declarados eram falsos (20/08, sessão 53) — `0127`

**A `0126` cuidou de COMO O DIAL MUDA. Ela não cuidou de o dial ser LIDO.** E a `0041` já havia
diagnosticado isso com um comando: *"`grep -rl estagio_autonomia portal/src n8n` não retornava NADA
— a tabela não tinha um único leitor"*. Ela consertou para **um** estágio. Rodando a mesma busca
hoje, estágio por estágio, os outros **sete** continuavam sem leitor: mudar o nível deles era
validado contra o teto, cobrado contra golden set pela `0126`, gravado na trilha — e **inerte**.

**E dois deles não só não eram lidos: declaravam o nível ERRADO.**

| Estágio | Declarava | Fazia | Onde estava o número |
|---|---|---|---|
| `classificacao_doc_checklist` | N1, limiar 0,95 | **N2, limiar 0,70** — documento com confiança 0,80 entrava classificado sem humano olhar | `p_threshold default 0.7` **e** `THRESHOLD_AUTO` no `classifier.mjs` — duas réguas, nenhuma o dial |
| `reconciliacao_classe_bc` | N0 ("não influencia decisão") | **N1** — abre pendência desde a `0015`, e pendência entra na fila e conta no Portão 2 | a classe nunca era olhada em `fn_registrar_reconciliacao` |

**Por que isso é pior do que parece:** quem lê o dial para decidir se confia num achado da Classe
B/C conclui "sombra, não influencia" e está errado. E quem baixasse a classificação para N1 para
forçar revisão de tudo não conseguiria — o nível não era lido.

**A `0127` não muda comportamento nenhum.** É a escolha da `0041`, pelo mesmo motivo: o dial passa a
declarar o que o sistema já faz, e a partir daí mudar de verdade passa a ser uma chamada.

- **`fn_dial_permite_auto`** — o leitor ÚNICO de "este estágio, nesta confiança, pode seguir sem
  humano?". Uma função e não a regra copiada, porque quatro cópias de uma regra de doutrina voltam a
  divergir — que é o defeito que a `0041` e a `0126` existem para fechar.
- **`fn_dial_influencia`** — o leitor de N0, que é significado diferente: não é sobre limiar, é sobre
  o resultado poder chegar à fila de alguém. **Os defaults seguros são opostos de propósito:** sem
  linha no dial, `permite_auto` devolve false (ausência de configuração não é permissão) e
  `influencia` devolve true (calar achado por falta de configuração esconde problema).
- **A classificação tira o limiar do dial**, com o parâmetro ficando como queda para banco sem a
  linha semeada — sem essa queda, um banco antigo passaria a abrir pendência em TODO documento no
  instante em que a migration entrasse. E a mensagem da pendência passa a dizer **qual** limiar
  reprovou, porque o limiar agora é dado e pode ter mudado desde ontem.
- **A Classe B/C respeita o nível:** em N0 registra em `reconciliacao` e não abre pendência. "Roda e
  registra" é a primeira metade da definição de sombra, e é ela que permite medir antes de confiar.

#### O RAMO QUE FALTAVA, E É O ASSERT MAIS IMPORTANTE DA SUÍTE NOVA

Silenciar um estágio com divergência **presente** cairia no `elsif` que fecha pendência, e marcaria
a pendência aberta como *"resolvida por sistema:reconciliacao"*. Mas o sintoma não sumiu: o estágio
foi silenciado. Resolver ali escreveria na trilha que o problema acabou, quando o que acabou foi o
direito daquele estágio de falar — e a trilha é append-only justamente para não permitir esse tipo
de reescrita. O ramo novo registra `reconciliacao_em_sombra` e **deixa em paz** a pendência que um
humano já pode estar tratando.

#### E A CORREÇÃO DA CLASSIFICAÇÃO PASSOU PELO PORTÃO DA 0126

N1 → N2 alcança auto-clear em estágio interpretativo, então exigiu `p_sem_medicao_porque`. O painel
passa a mostrar **dois** estágios como "declarada" em vez de um. Não é regressão: é o tamanho real
da autonomia não medida, que estava escondido num default de parâmetro.

**Um teste frágil que isto expôs, e o conserto vale mais que ele:** o cenário 1 da `golden.test.sql`
confiava em a classificação estar em N1 *por semeadura*. No dia em que uma migration declarou o N2
que ela já praticava, o cenário passou a testar "N2 → N2" — que não é subida — e reprovou. Agora ele
**estabelece a própria pré-condição** (baixar é sempre livre); depender de um default global é que
custa.

**O que a `0127` deliberadamente NÃO fez, com o motivo escrito:** `extracao_identificadores` continua
sem leitor porque para obedecer ao dial ele precisa de uma CONFIANÇA que hoje não chega ao banco —
`fn_registrar_diagnostico` recebe `p_tipo_confirma boolean`, com a decisão já tomada no nó do n8n, e
um dial no banco não alcança decisão tomada fora dele. Fechar exige mudar a assinatura **e** o nó, o
que obriga a reimportar o workflow. Os dois estágios determinísticos também seguem sem leitor, e ali
a razão é de natureza: a garantia deles é aritmética, não concordância humana.

### A REGRA DE OURO PASSA A SER EXECUTADA (19/08, sessão 53) — `0126`

**O `docs/01` fecha com uma regra de ouro, em negrito e sem ressalva:** *"nada de subir o dial de
autonomia de um estágio interpretativo sem golden set e concordância medida."* **E `fn_mudar_dial`
(0041) conferia UMA coisa: o teto.** Pedir N2 num estágio de teto N2 era aceito com um `p_motivo` em
texto livre, e nada olhava para medição alguma — não existia onde olhar. A regra estava escrita na
doutrina, repetida no cabeçalho de duas migrations, impressa em letras âmbar na tela de autonomia, e
não era código em lugar nenhum.

**Quem fez isso primeiro foi a própria `0041`, e ela declara que fez:** *"este N2 é decisão de
produto do dono, NÃO autonomia medida… o golden set físico ainda não existe."* É a mesma forma dos
defeitos que a `0123` achou — `v_lados_bp` atribuída e nunca lida, "a guarda que o comentário da
`0117` prometia não existia" —, com a diferença de que aqui a promessa é do documento fundador.

**E o protocolo estava pronto desde 14/07.** O `f0/06` foi fechado como v1: dimensionamento (~20–30
por tipo core), o que se rotula, uma tabela de CINCO métricas, rotulagem com dois avaliadores e o
laço de calibração desenhado. No banco não havia uma linha disso — `grep -ril golden` devolvia
documentação, o comentário de um script e prosa de migration.

| O que entrou | Onde |
|---|---|
| Ground truth: rodada que **congela**, documento com **estrato** e **origem**, rótulo **por rotulador**, e `golden_campo` com tolerância declarada no rótulo | `0126` |
| As **cinco métricas** do `f0/06`: F1 da classificação por tipo, acurácia dos identificadores, erro de campo, concordância contábil e falso-positivo da Classe A | `fn_golden_*` |
| `natureza` e `base_do_nivel` em `estagio_autonomia` — a tabela de teto do `docs/01` e a ressalva "declarada, não medida" saem da prosa | `0126` |
| O **portão**: subida que alcança N2/N3 em estágio interpretativo exige medição, ou motivo assumido | `fn_mudar_dial` |
| O painel de autonomia mostrando a base, a cobertura por tipo e o que falta | `/autonomia` |

**AS TRÊS DECISÕES QUE VALE LER:**

1. **O portão morde na subida que ALCANÇA N2/N3, não em toda subida.** A leitura literal cobraria
   golden set para ir de N0 a N1 — e N1 é "sugestão, humano confirma todo item": nada é automatizado,
   e a anti-ancoragem continua inteira. O risco que a regra guarda é automatizar erro em escala, e a
   escala começa no auto-clear. Cobrar medição para exibir sugestão travaria o caminho que a própria
   doutrina manda percorrer. **Descer nunca pede nada** — freio que exige papelada não é freio.
2. **Golden SINTÉTICO não sobe dial, e isso é coluna.** Sem `origem`, o portão seria teatro: os dois
   books têm `GABARITO.json`, rotulá-los é de graça, a concordância sairia ~100% por construção e o
   dial subiria com a medição do INSTRUMENTO. O cabeçalho do `medir-auto-aceite.mts` avisa disso em
   prosa há sessões; agora o aviso é guarda. Medido no teste: os MESMOS 20 documentos, o MESMO F1,
   e a subida é recusada só por a origem ser sintética.
3. **A decisão declarada continua possível — e passa a ser CONTÁVEL.** `p_sem_medicao_porque` é um
   MOTIVO, não um booleano (booleano vira `true` e se esquece; motivo é lido por quem revisa a
   trilha). Com ele a subida acontece, a trilha grava `mudanca_dial_sem_medicao` e o nível fica
   `declarada`. Sem essa porta, a cadeia de migrations deixaria de aplicar do zero — é a lição das
   verificações-alçapão que a `0119` e a `0120` tiveram de ter desarmadas: guarda que impede o estado
   legítimo do dono não é guarda.

#### A MÉTRICA QUE NUNCA PRECISOU DE GOLDEN SET, E NINGUÉM SOMOU

A quinta linha da tabela do `f0/06` é *"taxa de falso-positivo da reconciliação Classe A → subir
Classe A de N1 para N2"*. **O rótulo dela existe desde a `0106`**, cujo cabeçalho define `rejeitada`
como *"a pendência não procede (falso positivo do motor)"*, com essas palavras. Ou seja: desde 11 de
agosto o sistema coleta, a cada rejeição de analista, um ponto de dado sobre a qualidade da própria
reconciliação — e ninguém tinha somado. `fn_golden_classe_a` soma, com o denominador certo: **só
vereditos humanos.** Pendência que o próprio sistema resolveu (o sintoma sumiu) não é ninguém dizendo
que ela procedia, então fica fora dos dois lados e é contada à parte.

#### O QUE O TESTE ACHOU, E É UM DEFEITO DE AUTORIDADE

A `fn_golden_cobertura` agrupava a cobertura por `documento.tipo_taxonomia` — **o tipo que a MÁQUINA
disse.** Cobertura de ground truth medida pela resposta que está sob avaliação. Numa rodada com 25
balanços rotulados dos quais o classificador chamou 5 de DRE, ela reportava "BALANCO 20, DRE 5" e
reprovava por falta de amostra — quando a rodada tem 25 balanços e o que ela deveria acusar é a
classificação errada. Agora o tipo vem do CONSENSO dos rotuladores. É a mesma família das três
confusões de unidade da sessão 52, num eixo diferente: autoridade, não unidade.

**E um segundo, achado ao escrever o critério:** contar no "tipo mais fraco governa" um tipo que só
existe como falso-positivo daria **poder de veto a um único documento** (precisão 0, recall
indefinido, F1 zero) — e contaria o mesmo erro duas vezes, porque o documento cuja verdade era X e a
máquina chamou de Y já é falso-negativo de X. O erro é contado uma vez, onde tem denominador. Medido:
sem o filtro, o pior caso da rodada de teste cai de 0,8889 para **0,0000**.

#### E O CENÁRIO DO DIAL QUE PASSARIA PELO MOTIVO ERRADO

Ligar o portão derrubou um cenário da `dial.test.sql`, e o motivo vale mais que a correção. O cenário
5 ("o limiar vem da tabela") vinha depois do cenário 4, que deixa o dial em **N1**. Com o portão, a
volta para N2 é recusada — e o assert seguinte, *"com limiar 0.99 a linha de 0.98 fica pendente"*,
**passaria verde pelo motivo errado**: pendente por N1, não pelo limiar. Um cenário inteiro medindo
outra coisa e dizendo que passou. A recusa passou a ser afirmada ali mesmo, porque é ela que decide
se o resto do cenário significa algo.

**O que NÃO foi feito, e é honesto dizer:** o golden set FÍSICO. Rotular documento real de cliente,
com controle de acesso LGPD, é o que o `f0/06` já classificava como "tarefa de execução" que "não se
monta em documentação" — continua sendo do dono. O que mudou é que agora existe onde colocar, o que
mede, e um portão que cobra. **E fica anotada a decisão de schema que falta:** o dial é por ESTÁGIO
(`0001`/`0002`) e o `f0/06` raciocina por TIPO — ele chega a dizer que "tipo sem ~20 exemplos
permanece em N0/N1". Autonomia por (estágio × tipo) não existe no schema, e inventá-la de lado seria
decidir uma mudança de modelo de dados por tabela. Enquanto não existir, vale a leitura conservadora:
o tipo mais fraco governa.

### "OS TRÊS CENÁRIOS SÃO TRÊS?" — e o buraco que a pergunta abriu no arnês (19/08, sessão 52)

**O §2.2 do diagnóstico pedia um bloco "Resumo dos três cenários" lado a lado. Ao medir para
construí-lo, apareceu algo antes:** o `Cliente Case` nasce como `=<Base Case>` em TODA conta do modelo
(convenção do Modelo Base, e certa como ponto de partida). Num arquivo recém-exportado, **girar o dial
de 1 para 2 não muda um número sequer — e nada dizia isso.** Um "Cliente Case" que é, número por
número, o Base Case podia chegar a um comitê sem a planilha o contradizer, com o dropdown de três
opções servindo de evidência de que ela deveria contradizer.

O Stress tem a forma espelhada do mesmo risco: é o Base vezes um haircut único
(`Considerações!$F$8`). Zerada aquela célula, o Stress vira o Base e o dropdown continua oferecendo
três.

**O que entrou:** um painel `OS TRÊS CENÁRIOS SÃO TRÊS?` no `Output`, ao lado do interruptor, dizendo
por cenário se ele está **diferenciado** ou **IDÊNTICO AO BASE**. A medida é EXATA e vem da linha
`DIF_CENARIO` da aba de receita: a soma, conta a conta e ano a ano, de `ABS(premissa do cenário −
premissa do Base)`. Zero significa premissas idênticas e não pode significar outra coisa — somar as
premissas em vez das diferenças em módulo seria mais curto e errado (dois conjuntos diferentes podem
ter a mesma soma). E é **fórmula viva**: no minuto em que o analista digitar a primeira premissa
própria do Cliente Case dentro do Excel, o aviso some sozinho.

#### O BURACO QUE ESTE TESTE ACHOU NO ARNÊS

O teste do painel reprovava dizendo **"IDÊNTICO AO BASE" sobre um Stress de 20%**. A causa não estava
no produto: o nome da aba principal do modelo tem VÍRGULA (`Revenues, COGS & SG&A`), então toda
referência a ela vai entre apóstrofos — e o scanner de argumentos de função do `avaliar-formula.mts`
pulava trecho entre **aspas duplas** e não entre **apóstrofos**. A vírgula de dentro do nome partia o
argumento em dois, `N('Revenues` não avaliava nada, e o resultado era **0. Em silêncio.**

**O efeito:** qualquer assert que avaliasse uma fórmula referenciando a aba principal do modelo dentro
de uma função lia zero e passava por não conseguir avaliar — a forma mais silenciosa de teste que não
prova nada. Corrigido nos dois scanners do arquivo, e travado por assert próprio. Conferido que a
correção não mudou nenhum assert antigo: a contagem foi de 559 para 566 com exatamente 7 asserts
novos.

#### O QUE NÃO FOI FEITO DO §2.2, E POR QUÊ

O bloco numérico com as métricas dos três cenários lado a lado **não entrou**, e a razão é que a
especificação dele não fecha:

1. **A lista de métricas mistura duas famílias.** Receita e EBITDA saem de uma cascata paralela sobre
   as premissas (que existem por cenário no arquivo). **DSCR mínimo e necessidade de pico não** — eles
   saem do `Cash Flow` e da lógica do revolver, e não há como avaliá-los para um cenário INATIVO sem
   replicar o modelo inteiro, que é o "caminho caro (e desnecessário)" que o próprio §2.2 descarta.
2. **A metade viável custa duplicar a projeção.** As contas se projetam por quatro formas diferentes
   (`pct_de_linha`, `indice_macro` com e sem painel, crescimento composto, e "sem premissa"). Uma
   cascata paralela reescreveria essas quatro regras num segundo lugar — e esta sessão já pagou duas
   vezes a lição de duas réguas sobre a mesma quantidade (a `0123` e o par fatiamento×orçamento). O
   caminho correto é PARAMETRIZAR a cascata pelo cenário e emiti-la quatro vezes do mesmo código, com
   um CHECK provando que a sombra do cenário ativo é igual à linha ativa — é refatoração da aba que
   produz os números do modelo, e merece decisão própria.
3. **E a coluna do meio nasceria vazia:** com o Cliente Case idêntico ao Base por construção, duas das
   três colunas mostrariam o mesmo número até alguém preencher as premissas. É exatamente o que o
   painel novo passa a denunciar — e denunciar isso vale mais, hoje, do que exibir duas colunas iguais.

### A PROVENIÊNCIA VOLTA AO ARQUIVO DE COMITÊ (19/08, sessão 52)

O §2.3 do diagnóstico de 11/08 tinha medido a perda: antes do PR #109 cada célula de dado trazia
documento, **página, confiança e status de aceite**; o #109 separou os dois exports — decisão certa e
medida — e a camada saiu junto com as abas de dado.

**E nem o nome do arquivo estava lá.** Achado ao ler o código para consertar: o que a nota mostrava é
`documentos`, que a `fn_linhas_para_modelagem` monta como `array_agg(distinct tipo_taxonomia)` — o
TIPO. A nota dizia *"Extraído de BALANCO, DF_AUDITADA"*. Num mandato com oito balanços, isso é a
categoria e não a peça.

**A mudança é na `fn_valores_por_ano`, e não na `fn_linhas_para_modelagem` — esse é o ponto.** A
segunda devolve UMA linha por (seção, rótulo), e a proveniência dela é da ocorrência de maior módulo
**entre os exercícios**. Usada na nota de uma célula de 2023, ela descreveria a célula de 2025 com
toda a convicção. Rastreabilidade que aponta para o lugar errado é pior que rastreabilidade nenhuma:
a primeira convida a conferir e leva ao lugar errado.

**O número não podia mudar por causa disto,** e não mudou: `valor` continua sendo
`(array_agg(valor order by abs(valor) desc))[1]`, letra por letra. Reescrever com janela seria
elegante e arriscado — em empate de módulo com sinais opostos (`abs(-1900) = abs(1900)`) duas formas
de "maior módulo" escolhem valores diferentes, e isso é número de modelo mudando de graça. A
proveniência vem por join de volta na ocorrência que tem aquele valor, com desempate declarado.

**A nota melhora nas CATORZE abas de uma vez.** O §2.3 pedia a `Premissas`; `valorNaEscala` é o
caminho único por onde valor de documento entra no arquivo, então sair por ele custa o mesmo e não
deixa aba de segunda classe.

A nota agora diz, nesta ordem — primeiro onde procurar, depois o quanto confiar:

> `Extraído de 01_Balanco_2025x2024.pdf · página 3 · confiança da extração 97% · ACEITO por rodrigo@oria`

e, quando ninguém conferiu:

> `… · aceite: pendente — este número ainda NÃO foi conferido por ninguém`

Campo que a extração não informou sai FORA da frase: `null` é "não sei", e escrever "página 0" seria
dar precisão falsa. Os 7 asserts substantivos foram conferidos reprovando com o código antigo.

### O INTRAGRUPO QUE NÃO É MÚTUO passa a ser conferido — pelo ESPELHO (19/08, sessão 52)

**O item estava aberto com a dificuldade certa escrita:** *"cada uma casa com uma conta DIFERENTE do
balanço — e escolher errado inventa divergência."*

**A primeira ideia era errada e não foi usada.** Comparar a planilha contra o balanço, como a `0117`
faz com mútuos, é comparar FLUXO com ESTOQUE: o documento que a taxonomia tem para as outras naturezas
é `FAT_INTRAGRUPO`, faturamento do exercício. No book os números coincidem por construção (nada foi
pago no ano), então a checagem teria saído verde sobre uma comparação sem sentido — a mesma forma de
defeito que a `0123` acabou de achar.

**O que se confere é o ESPELHO.** Todo saldo intragrupo aparece duas vezes dentro do mandato: a receber
no balanço de quem tem o crédito, a pagar no de quem tem a obrigação. É identidade contábil, e não
precisa de segundo documento — os balanços que o mandato já tem bastam.

**E o pareamento é pelo PAR DE EMPRESAS, não pela natureza** — é essa a resposta à dificuldade. O dado
do book mostra por quê:

| | |
|---|---|
| Canastra Indústria | `Contas a receber intragrupo - Canastra Comercial` |
| Canastra Comercial | `Fornecedores intragrupo - Canastra Indústria` |

Quem vende chama de "contas a receber"; quem compra chama de "fornecedores". **Pela natureza elas nunca
se encontram; pelo par de empresas, sempre.** E nenhuma linha precisa ser casada com "a conta certa": a
linha DIZ com quem é. A contraparte sai do sufixo do rótulo contra a lista de entidades do caso —
medido: **6 de 6 rótulos intragrupo do book casados com a empresa certa, 3 de 3 de terceiro
corretamente ignorados** (`terceiros`, `nacionais`, `mercado interno`).

**Ficam fora, com o motivo escrito:** mútuo (é da `fn_reconciliar_mutuos` — uma linha, uma régua),
mútuo com sócio (não tem espelho), o documento COMBINADO (as linhas intragrupo dele são eliminações,
que nomeiam as duas pontas) e par em que uma das empresas não entregou balanço (aí a falta de espelho é
falta de documento, e o Portão 1 já cobra).

**Canastra: os quatro pares fecham** — aluguel 940, conta corrente 1.900, fornecimento 2.900 e 5.200.
Zero pendências, que é o certo para um book cuja única divergência plantada é a de mútuos.

#### E ela achou um defeito no book VERTENTES, na primeira vez que rodou

A `escalar_passivo` do `motor.py` multiplica o passivo INTEIRO de cada controlada por um fator até o PL
cair num alvo — e a conta corrente ia junto. Resultado: a VT Logística registrava **978** a pagar
contra os **1.400** que a Metalúrgica registrava a receber. **422 de diferença, num book que declara
ter UMA divergência só** (os 180 dos mútuos).

O próprio gerador já declarava o invariante que estava violando, no comentário de `construir`:
*"contrapartes intragrupo que faltavam na Metalúrgica (o combinado precisa dos dois lados para as
eliminações fecharem)"*. Elas não fechavam.

**Saldo intragrupo é fixado pela contraparte e não é livre para calibração.** As contas de
`INTRAGRUPO_FIXO` saíram do fator, que passou a ser recalculado sobre o resto do passivo — o PL-alvo
continua sendo atingido. É a segunda consequência ruim da calibração por PL-alvo; o `book-canastra` já
tinha abandonado a técnica pela primeira (com três exercícios o fator vira distorção ENTRE anos).

#### E um portão que faltava no CI

Do mesmo `gerar_fixture.py` saem TRÊS artefatos versionados — o SQL da suíte de banco, o JSON da suíte
de export e (via `gerar.py`) o GABARITO. Os workflows do n8n têm `git diff --exit-code` desde a sessão
20, com o motivo escrito: *"o JSON commitado pode divergir da fonte que o gera"*. **As fixtures não
tinham, e o mesmo defeito aconteceu aqui:** a correção do `motor.py` mudou o SQL e o GABARITO, o JSON
ficou para trás, e a suíte de export reprovou em 5 itens comparando um export NOVO com um gabarito NOVO
a partir de uma fixture VELHA. O portão entrou, e cobre as três fixtures (as duas de Vertentes e a do
Canastra).

### O FATIAMENTO ESTAVA DESLIGADO — e a correção anotada aqui era a errada (19/08, sessão 52)

**O que estava escrito nesta lista:** *"O item mais denso do book ainda estoura o teto de saída:
`17_Livro_Razao_Fornecedores` mede 17.875 tokens (109% dos 16.384). O `Fatiar Extracao` cobre isso
hoje partindo o documento; o que falta é o caso de o BLOCO mais denso ainda não caber — extrair por
faixa de PÁGINA."*

**Medi antes de mexer, e as duas metades estavam erradas.** Rodando `planejarFatias` sobre o texto
real dos 38 PDFs (`pdf/TEXTO_EXTRAIDO.json`, que é a forma que o nó `Extract From File` entrega):

| | |
|---|---|
| documentos fatiados | **ZERO de 38** — todos davam `blocos = 1` |
| livro razão | ia **inteiro numa chamada**, pedindo 16.506 tokens = **101% do teto** |
| razão células/linha no book | **1,67 a 6,81** (o aging tem seis faixas por linha) |

**A causa é de UNIDADE, e é a terceira da mesma família no mesmo arquivo** (as outras duas estão nos
comentários de `linhasDeConta` e de `LIMIAR_COBERTURA`, ambas já corrigidas). `MAX_CELULAS_POR_BLOCO`
é derivado como *"quantas CÉLULAS cabem em 60% do teto de saída"* — 234 — e vinha sendo aplicado a
uma contagem de **LINHAS**. Uma linha de comparativo de três exercícios produz três células, então o
corte ficava de 1,7× a 6,8× mais frouxo do que o nome dele diz. Na prática: nunca disparava.

**Não era preciso mudar topologia nenhuma.** Faixa de página nunca foi o eixo do problema. Com o peso
em células, o fatiamento por âncora que já existe corta o razão em blocos que cabem — e um bloco pode
descer a UMA linha, que é mais fino que qualquer página.

**Medido depois:**

| | antes | depois |
|---|---|---|
| chamadas de extração no book | 38 | **44** (+6) |
| documentos que estouravam o teto | 1 | **0** |
| pior bloco do livro razão | 101% do teto | **16%** |
| o guarda de gasto contra o custo medido | +45% | **+10%** (US$ 1,42 previsto × 1,29 medido) |

**A contagem erra para CIMA de propósito, e o número está medido: +64% agregado** sobre a verdade
declarada pelo gerador (pior caso +187%, no razão — data, número de lançamento e código de conta são
números que não viram célula). Errar para cima fatia mais fino que o necessário: ~6 chamadas a mais,
~US$ 0,12 sobre US$ 1,29. Errar para baixo trunca, e truncar custa o dado — é a mesma escolha que
`FRACAO_DO_TETO` já documentava.

**Medi a versão refinada e ela foi REJEITADA:** tirando data, CNPJ, código de conta (`1.1.01.001`) e
percentual, o erro agregado cai de +64% para +23% — mas **quatro documentos passam a SUBESTIMAR**, e
o balancete analítico subestima em 43%. Menos erro médio pelo preço de errar para o lado que trunca é
troca ruim. Ficou registrado em `celulasDaLinha` para quem tentar de novo.

**O orçamento também estava errado, e do outro lado.** Ele recebia `celulas = contagem de LINHAS` e
`colunas` lidas do NOME do arquivo — e `tokensDeSaida` usa `colunas` para **dividir** células em
contas, então passar linha onde ele espera célula fazia `contas = linhas / colunas` num lugar em que a
linha JÁ É a conta. Duas pontas erradas ao mesmo tempo, e os erros se somavam em vez de cancelar.
Agora as duas quantidades saem do próprio texto, e a razão células/linhas conta a coluna de EMPRESA
junto — que a leitura do nome nunca viu (o comentário de então já declarava essa cegueira).

**O que sobra de irreparável, e agora aparece:** uma linha que SOZINHA passe do teto. Não há corte
mais fino que a linha (ela é a âncora, e meia âncora não localiza nada no PDF). `planejarFatias` marca
esse bloco com `acimaDoTeto`, o nó propaga em `bloco_acima_do_teto`, e `juntarBlocos` escreve o motivo
— que a `0016` já converte em pendência. Nenhum documento do book cai nesse caso.

**E o aviso do `medir-custo-book.mjs` mentia por construção:** ele comparava a saída do DOCUMENTO com
o teto, o que deixou de significar algo no dia em que o fatiamento nasceu. Agora ele compara o pior
BLOCO, lista quantos blocos cada documento vai gerar, e ganhou um invariante que **REPROVA** se um
documento voltar a passar do teto sem ser fatiado.

### A FIXTURE DE EXTRAÇÃO DO BOOK-CANASTRA, e os três defeitos que ela achou na primeira rodada (19/08, sessão 52)

**A lacuna que ela fecha.** O `book-canastra` está no repositório desde o PR #112 e provava duas
coisas: que os números do gerador fecham no papel, e que o lote não cabe no teto de gasto. **A
ingestão nunca havia sido exercitada sobre ele** — era a maior lacuna de cobertura viva, e estava
anotada como tal neste arquivo.

Agora existe `db/test/gerar_fixture_canastra.py` → `db/test/fixture_book_canastra.sql` (28
documentos, 1.264 linhas) e `db/test/canastra.test.sql`, ligados ao `db/test/run.sh`. A regra que ele
trava é a de Vertentes, sobre documento **difícil**: *extração fiel => a única pendência é a
divergência que o book planta de propósito* (R$ 240 mil de mútuos). Cada uma das 15 armadilhas que
virasse pendência seria falso positivo.

**Carregada e reconciliada, ela abriu ZERO pendência.** Num caso que planta uma. Três defeitos, e a
`0123` os corrige:

| | O defeito | O número |
|---|---|---|
| 1 | A checagem procurava a palavra "mútuo" no **rótulo de cada linha** da planilha. Nenhuma planilha real a repete ali — ela diz a natureza **uma vez, no título** ("RELAÇÃO DE MÚTUOS ENTRE PARTES RELACIONADAS" / "Mutuante \| Mutuária \| Saldo devedor"). O filtro zerava o lado B e a função devolvia `documento_ausente`, o único resultado que **não** abre pendência: a divergência não estava "não encontrada", estava **declarada inexistente**. | R$ 240 mil invisíveis |
| 2 | A guarda que o comentário da `0117` prometia **não existia**: `v_lados_bp` era atribuída e nunca lida. | — |
| 3 | Achado ao ligar a guarda: **mútuo com SÓCIO não tem espelho** no mandato (a contraparte é o quotista) e estava somado junto com o intragrupo. | 14.000 na SPE, que esconderiam os 240 atrás de um número 60× maior |

**Por que o defeito 1 passou seis sessões.** O `fixture_book_vertentes.sql` escreve o rótulo como
`"A → B — Mútuo"`, colando a natureza dentro do nome da linha. Isso não vem de PDF nenhum — é um
enfeite do gerador do fixture. A checagem estava aprovada por um dado que só existia no teste.

**A guarda prometida está errada, e isso foi MEDIDO, não deduzido.** "Interromper quando há os dois
lados" calaria a checagem exatamente onde a evidência é mais forte: no Canastra os dois lados dão
16.300 cada — eles se confirmam, e é a planilha (16.060) que discorda. A regra que entrou: lados que
**concordam** estabelecem o saldo por dupla evidência (uma comparação, não uma por lado); lados que
**discordam** são eles o achado, e aí a planilha não é atribuída a nenhum deles.

**E a primeira versão da correção repetiu o defeito que consertava.** Ler "rótulo OU seção" sem
ordem fez a suíte de Vertentes reprovar na hora: o fixture de lá põe `secao = "MÚTUOS E CONTAS
INTRAGRUPO"`, um agrupador que nomeia DUAS naturezas, e com a seção valendo por si a conta corrente
(1.400) e o aluguel (640) entraram na soma — **a divergência saltou de R$ 180 mil para R$ 2.220
mil**. É textualmente o que o comentário da `0117` já avisava. A régua final tem **precedência
estrita**: o rótulo, quando fala, é a autoridade sobre a linha dele; a seção só vale quando os
rótulos estão calados; nada dizer significa que o documento inteiro é a relação de mútuos, que é o
que a taxonomia já afirmou ao classificá-lo.

**O que fica aberto, e está dito na migration:** mútuo com sócio passa a não ser conferido por
ninguém — o par dele não é a planilha intragrupo, é o contrato com o quotista, e ninguém cruza isso
hoje. Antes da `0123` ele também não era conferido; a diferença é que agora está escrito.

**Duas coisas que a fixture ensinou sobre a forma FIEL de extrair, e que valem para o prompt:**
matriz se extrai como um grupo por COLUNA (`secao` = nome da coluna, `chave` = o rótulo da linha) —
escrever "Terrenos — custo" cola a coluna dentro do nome da conta e cria três rótulos que nenhuma
outra peça reconhece; e **a taxonomia não tem tipo para anexo de composição de imobilizado** (conferi
o seed `0002`), então ele entrou como `NOTAS_EXPL`, que é a semântica certa (detalhamento
complementar que não se soma debaixo do total do balanço) mas não o nome certo.

### O EXPORT DO EXCEL: cinco defeitos de número, achados rodando o arquivo (18/08, sessão 51)

**De onde isto saiu:** gerar o export completo do caso de referência
(`db/test/fixture_modelagem_v35.sql` — o caso REAL capturado da produção) e rodar o
`auditar-xlsx.mts` nele. **Três dos dez itens reprovavam:**

| Item | Medida |
|---|---|
| o balanço fecha? | **NÃO** — Ativo − (Passivo+PL) = **−20.529** nas seis colunas |
| a DRE reproduz o documento? | **NÃO** — receita −440, lucro bruto −800, EBIT **+9.409**, resultado líquido **+20.780** |
| o ativo é o do documento? | **NÃO** — **+10.277** |

Modelo que não fecha não projeta: fluxo, revolver e alavancagem viram aritmética sobre um
balanço impossível. Os cinco defeitos, cada um com o número que ele movia:

1. **A série histórica de cada conta vinha indexada só pelo RÓTULO.** `fn_valores_por_ano`
   agrupa por (rotulo_norm, secao_canonica, ano) e devolve a seção porque demonstração real
   repete rótulo entre seções; a rota indexava só pelo rótulo e a última seção lida
   sobrescrevia as outras. É o irmão do defeito que a `modelagem-linha.ts` já tinha
   corrigido para os VÍNCULOS — ficou de fora justamente onde decide os NÚMEROS. Medido no
   v35: **treze rótulos** em duas seções com valores diferentes (`Empréstimos e
   Financiamentos` 37.379 × 44.474, `Obrigações Tributárias` 13.549 × 7.895, `Provisão para
   contingências` −1.900 na despesa × 2.567 no passivo…). A dívida existente do modelo saía
   **3.176 errada (12%)**. O casamento virou `seriesPorLinha`/`serieDaLinha` na lib, e a
   rota e o gerador local passaram a chamar a MESMA função.
2. **Ocorrência repetida do mesmo rótulo era lida como componente de subtotal.** O detector
   por ordem lê a sequência impressa; a extração repete rótulo dentro do mesmo documento
   (é o que um comparativo produz sem `periodo_coluna`). Errava dos dois lados: declarava
   subtotal uma DESPESA REAL (a provisão de −1.900 e o IR de −420 **sumiam** do modelo —
   SG&A 1.900 menor, EBIT 1.900 maior) e deixava de reconhecer subtotal de verdade, porque
   os componentes dele também vinham duplicados.
3. **Cabeçalho de grupo impresso entrava como conta** quando a `ordem` não é a do documento.
   `Contas a Receber`, `Disponível`, `Estoques` não estão na lista fechada da
   `fn_papel_linha`. A remoção nova exige PROVA: rótulo exatamente igual a um nome de grupo,
   o documento informando o total daquele grupo, a soma EXCEDENDO esse total, e a remoção
   aproximando sem ultrapassar — documento simples nunca perde a conta, e valor idêntico ao
   de outra linha do bloco não é removido (é a mesma conta transposta, e a doutrina é não
   apagar conta).
4. **O balanço não reconciliava com o TOTAL GERAL do documento.** Cada grupo já seguia o
   total informado, mas os totais de grupo do próprio documento não somam o total geral
   dele (67.878 + 101.200 = 169.078 contra `TOTAL DO ATIVO` **158.801**). Agora há uma linha
   de reconciliação por lado, e ela **só entra quando o documento informa os DOIS totais
   gerais e eles concordam** — evidência dupla; senão nada é ajustado e o CHECK continua
   acusando. A DRE ganhou o mesmo nos quatro níveis que o documento informa. Junto veio o
   desempate de âncora: `PASSIVO E PATRIMÔNIO LÍQUIDO` (121.198) × `TOTAL DO PASSIVO E DO
   PATRIMÔNIO LÍQUIDO` (158.801) passa a ser decidido pelo rótulo que **diz "total"**, e não
   pela ordem em que o banco devolveu.
5. **O export de DADOS não pedia recálculo ao abrir.** Todo total das abas classificadas é
   `=SUM(...)` sem valor em cache: sem `fullCalcOnLoad` o Excel abre a célula VAZIA até
   alguém apertar F9. A flag era ligada dentro do modelo institucional — então o arquivo do
   botão **Exportar dados**, o que serve para CONFERIR a extração, saía sem ela.

**O auditor ganhou dentes e perdeu alarme falso.** Item novo — *o resíduo de reconciliação é
imaterial (≤5% da base)?* — porque sem ele "o balanço fecha" e "a DRE reproduz o documento"
passariam por CONSTRUÇÃO; o tamanho do resíduo é a medida direta da qualidade da extração
(no v35 ele acusa **18% do ativo**, que é a verdade daquele caso: conta duplicada com dois
rótulos, que nenhum código desambigua). E arquivo SEM modelo (export de dados, ou mandato
sem modelagem) deixou de receber cinco reprovações de itens que não se aplicam.

**Resultado no caso de referência: 10 de 10 itens do modelo OK** (era 7/10), com o resíduo
declarado e medido. Balanço fechando nas seis colunas, ativo total igual ao documento em
todos os exercícios, DRE realizada reproduzindo o documento nas 24 células conferidas.

**Desempenho, medido antes de mexer:** o build do export é LINEAR no número de campos
(1.000 → 299 ms; 16.000 → 3.543 ms; 30.000 → 6.257 ms — ~0,21 ms por campo). Não há O(n²)
nesse caminho e nada foi "otimizado" às cegas.

### O teto de 1000 deixou de existir para o portal (18/08, sessão 51)

Pedido do dono, literal: *"a lista pagina não deve ser restringida, remova o teto de 1000 do
PostgREST"*. O teto mora em dois lugares, e os dois foram tratados:

**1. No servidor — e lá ele é do DONO, não do repositório.** É o `db-max-rows` do PostgREST
(*painel do Supabase → Project Settings → API → Max rows*, padrão 1000). Subi-lo para 100000 remove
o teto na prática e deixa cada leitura mais barata. **Está documentado no `db/README.md`, com o
caminho exato — e é opcional**, pelo motivo abaixo.

**2. No portal — e aqui ele acabou de verdade.** Duas mudanças:

- **`paginar` deixou de depender do teto do servidor.** A parada era "página com menos linhas que a
  janela = acabou", e isso só era correto porque a janela (1000) era exatamente o teto padrão. Com
  `Max rows` abaixo de 1000, TODA página voltaria curta e a leitura pararia na primeira — o defeito
  original de volta, escondido dentro da própria defesa contra ele. Agora a leitura anda pelo número
  de linhas REALMENTE devolvidas e só termina quando uma página volta **vazia**: vale para qualquer
  teto, e custa uma requisição a mais por consulta. O teto de segurança subiu de 50 mil para **500
  mil linhas** e continua declarando (`truncado`) em vez de entregar o pedaço como se fosse o todo.
- **As leituras que ainda escapavam passaram a paginar** — e uma delas já estava a meses de
  quebrar:

| Onde | O que era truncado | Por que importa |
|---|---|---|
| `indice_macro_obs` (export) | as observações macro | **920 linhas hoje**, +72 por ano. Ao passar de 1000, o corte cairia nas MAIS RECENTES (ordem crescente por data) — e é a última observação que dá o câmbio de fechamento do ano |
| `indice_macro_expectativa` (export) | as coletas do Focus | cada coleta acrescenta linhas; truncar não deixa o arquivo sem macro, deixa com a expectativa ERRADA |
| `fn_linhas_para_modelagem` (export e tela) | as linhas do modelo | é o conteúdo das 14 abas e da seção 3 da Modelagem |
| `fn_valores_por_ano` (export) | a série histórica por conta | 400 rótulos × 3 exercícios já passam de mil; cortar aqui dá a uma conta menos anos do que ela tem |
| `caso_linha_premissa` (export e tela) | os vínculos linha→premissa | truncado, o analista reescolhe premissa de linha que já tinha uma |

Todas com **ordem total e estável** (o desempate que impede duas páginas de repetirem e omitirem a
mesma linha), e o export passou a **declarar** no cabeçalho `X-Oria-Leitura-Truncada` se algum teto
de segurança for atingido — um arquivo incompleto que não se anuncia é pior que um erro.

Ficam de fora, de propósito e por não crescerem com a mesa: catálogos (taxonomia, premissas, séries
macro, banco de perguntas), consultas de linha única e as duas listas com `limit` deliberado (barra
lateral, trilha de autonomia).

### A `0122` — o texto que vai AO CLIENTE passa a ser escrito em português (18/08, sessão 51)

**Achado rodando a aba nova sobre o book da Canastra**, e é o tipo de defeito que só aparece com
dado real na tela. As perguntas saíam assim, literal:

| Saía | Sai agora |
|---|---|
| "Na DRE de **24,25** não localizamos a linha de despesas financeiras" | "Na DRE de **2024 e 2025**…" |
| "no faturamento de **L36M**?" | "no faturamento de **2025**?" |
| "A relação de mútuos informa **16060 milhar**" | "…informa **R$ 16.060 mil**" |

Nenhuma delas está errada no DADO — `24,25` é a referência multi-ano do classificador, `L36M` é a
notação de janela móvel de `f0/03`, `16060 milhar` é a soma com a escala declarada. Estão erradas no
LEITOR, e o leitor aqui é o cliente do mandato: **este é o único texto do sistema que sai da casa**,
e ele não pode falar em chave interna.

São três consertos, e o terceiro **não é de redação**:

1. **`fn_periodo_por_extenso`** — o período na forma que cabe depois de "de"/"em": `2025`,
   `2024 e 2025`, `2023 a 2025`, `2021, 2023 e 2025` (com buraco vira lista: o intervalo afirmaria
   um exercício que o documento não traz), `2025 (1º trimestre)` e `um período de 36 meses`. Rótulo
   que não diz ano nenhum **sai como veio**.
2. **`fn_valor_pt_br`** — `R$ 16.060 mil`, com separador de milhar do país, escala em palavra, sinal
   antes da moeda (`-R$ 240 mil`) e escala desconhecida **visível**. Independe do `lc_numeric` do
   servidor.
3. **`fn_anos_texto` deixa de ler `L36M` como o ano 2036.** A regra de "dois dígitos no fim"
   (`0023`) foi escrita para `dez/25` e `12M25`; em `L36M` o que está no fim é o **tamanho da
   janela**. Duas consequências, as duas invisíveis: na `0120` o período da pergunta é escolhido
   pelo maior ano do caso, então um documento `L36M` **vencia** um 2025 real (foi exatamente o que a
   Canastra produziu); e em `fn_valores_por_ano` uma coluna `L24M` entraria no modelo como o
   exercício de 2024 — janela móvel tratada como ano fechado. Corrigir só o texto teria trocado
   `L36M` por `2036`: um ano plausível e errado.

**E o período passou a ser o DA EMPRESA de que a pergunta fala.** A sugestão é por (pergunta ×
entidade) desde a `0119` e o período não acompanhava: num grupo em que a DRE da Indústria cobre
2023–2025 e a da Comercial só 2024–2025, a pergunta sobre a Comercial citava um exercício que o
documento dela não tem — e quem recebe não reconhece o próprio documento na pergunta.

Dezesseis asserts novos em `db/test/perguntas.test.sql` (`#12`), incluindo o que vale por todos:
**nenhuma pergunta do caso publica referência crua nem nome de escala**.

### As perguntas ao cliente ganharam a ABA que faltava (18/08, sessão 51)

A `0120` construiu o motor inteiro e **nenhuma tela o chamava**: `fn_sugerir_perguntas(caso)`
devolve a pergunta pronta — com motivo, risco, impacto, os marcadores resolvidos e o nome da
empresa — e a única forma de ver uma sugestão era rodar a função no SQL Editor. Para quem usa o
produto, a `0120` não existia.

**Onde ela ficou, e por que não onde o desenho anterior previa.** O plano era abrir a pergunta
dentro do botão "Contatar o Cliente" da fila de pendências (`0109`). O dono redirecionou, e a razão
é boa: **essas perguntas são sugestões que provavelmente ainda não foram feitas a ninguém** —
pendência é decisão sobre problema já medido, sugestão é rascunho de conversa. Numa lista só, a
segunda herda a aparência de tarefa concluída da primeira. Então elas moram numa aba própria,
`/casos/[id]/perguntas`, com entrada no cabeçalho do mandato (com a contagem) e um link a partir da
pendência **depois** que ela é marcada como pedida ao cliente — que é o momento exato em que o
analista precisa do texto.

O que a aba faz, em ordem de uso:

| | |
|---|---|
| **Mostra o texto pronto** | renderizado pelo banco, com `{data_base}`/`{saldo_mutuos}` resolvidos e a empresa no prefixo. Bloco próprio, para ser lido como citação do que vai sair da casa |
| **Copia** | `BotaoCopiar` com plano B (`execCommand`) para o portal aberto fora de contexto seguro — e que **declara** quando não conseguiu, em vez de piscar "copiado" |
| **Registra o envio** | `fn_registrar_pergunta_acao`, com o texto EXATO da tela num campo oculto: é ele que a `0120` congela. Append-only — reenviar é linha nova, e não há como apagar |
| **Registra o descarte** | "Não vou perguntar" grava a decisão sem sumir com a sugestão: quem chegar depois vê que alguém já olhou |
| **Diz quem e quando** | `ja_enviada` vem do banco (casado por empresa); autor e data vêm de `caso_pergunta` |
| **Explica o porquê** | motivo, risco, impacto e o gatilho traduzido, recolhidos num `<details>` — sustentam a pergunta numa reunião, e ninguém quer relê-los para copiar um texto |

Três cuidados que não são enfeite:

- **A lista é paginada**, como todas as outras — e isto vale para função que devolve tabela como
  vale para consulta: o PostgREST corta em 1000 linhas em silêncio, e a sugestão é uma por
  (pergunta × empresa que não satisfaz) desde a `0119`. A ordem é `(prioridade, codigo,
  entidade_id)`, **total e estável**; o teste `#11` da `perguntas.test.sql` trava a propriedade que
  torna essa ordem total (o par código × empresa é único na saída) — sem ela, duas páginas repetem
  uma linha e omitem outra.
- **A tela diz, em cima, que nada foi perguntado ainda e que nada é enviado automaticamente.** Uma
  lista de textos prontos com um botão verde se parece com caixa de saída; não é. O canal continua
  sendo o analista.
- **Banco sem a `0120` aplicada não quebra nada.** A aba explica que a migration falta e mostra a
  resposta do banco; a tela do mandato perde só o número do botão. Merge não é apply, e o dono
  aplica à mão — banco atrasado é estado normal, não defeito.

### O teto de 1000 linhas: agora em TODAS as telas, e o pior deles era o export

O PR #136 tirou do teto do PostgREST as três listas do PAINEL. Faltavam as de DENTRO do mandato — e
entre elas estava a mais cara de todas: **o export baixava `campo_extraido` sem paginação**. Um
mandato com mais de mil linhas extraídas gerava um `.xlsx` faltando linhas, que abre normalmente e
parece completo. O book de teste sozinho tem ~3.000 linhas com número.

Passaram a paginar (`portal/src/lib/supabase/paginar.ts`, de mil em mil):

| Onde | O que era truncado |
|---|---|
| **`/casos/[id]/export`** | as **linhas extraídas** (o produto), os documentos e as causas de falha |
| `/casos/[id]` | documentos, fila de pendências do mandato, contagem de linhas por documento |
| `/casos/[id]/documentos/[docId]` | as linhas do documento (um razão real passa de mil sozinho) |
| `/casos/[id]/revisao` | a fila de revisão — que desde a `0119` multiplica pelo número de empresas |
| `/casos/todos` | mandatos, documentos e pendências |
| `/casos` (painel) | `lote_execucao`, que alimenta os indicadores de custo |
| `/api/intake/status` | os **contadores de progresso** da ingestão: a barra parava em mil e o lote parecia travado |
| `/casos/[id]/modelagem` | a lista que sugere entidade e último exercício |

**Toda consulta paginada ganhou desempate por `id` na ordenação** — sem ordem total e estável, duas
páginas podem repetir e omitir a mesma linha, que é um jeito pior de errar do que truncar.

Ficaram DE PROPÓSITO sem paginação, e não são defeito: a barra lateral (`limit(30)` deliberado), a
trilha de autonomia (`limit(15)`) e as consultas de linha única (`.single()`) ou de catálogo
(taxonomia, índices macro), que não crescem com a mesa.

### A 0121 — o achado que o dado real do dono entregou (18/08)

**Não veio de teste: veio da base.** Rodando o diagnóstico de entidades antes da rodada de
validação, quatro mandatos voltaram com **três linhas para a mesma empresa** —
`Canastra Industria 2025x2024x2023`, `CANASTRA INDÚSTRIA DE EMBALAGENS LTDA.` e
`Meses Canastra Industria`. A primeira e a terceira são sujeira de nome de arquivo, já corrigida na
origem em 17/08. **A segunda não é sujeira: é a razão social correta**, e continuava sendo criada
como linha nova — em mandato novo, com o workflow já reimportado.

**A causa é uma metade esquecida da `0030`.** Aquela migration ensinou `fn_registrar_documento` a
casar entidade pela forma canônica, porque o nome chega de duas fontes que escrevem diferente: o
arquivo e o diagnóstico do conteúdo. `fn_registrar_diagnostico` — que é **a segunda fonte** — ficou
comparando `lower(razao_social) = lower(nome)`. Os dois efeitos, reproduzidos em base limpa antes de
consertar:

1. **duplica a empresa** quando o documento chega sem entidade (o classificador se abstém em 6 dos
   38 do book) e o diagnóstico traz a razão social completa;
2. **abre pendência falsa** de `entidade_incorreta` entre duas grafias da mesma companhia — que
   `fn_mesma_entidade` já reconhecia como a mesma.

**Por que ficou caro agora:** antes da `0119`, entidade duplicada partia colunas do export. Depois
dela, a entidade é o **eixo** da cobrança de linha exigida — a mesma empresa é cobrada duas vezes,
abre pendência em dobro, e a `0120` gera duas perguntas ao cliente sobre a mesma coisa.

**O que deliberadamente NÃO foi feito:** limpar as entidades já duplicadas. Os quatro mandatos são
de teste (v41, V45, v46, v4x); fusão de entidades para arrumar dado de teste é trabalho que não se
paga. Corrigida a função que as produz, mandato novo nasce limpo — e a validação deve rodar num
mandato novo. Se a duplicata aparecer um dia em mandato de cliente, a fusão vira fatia própria.

### O PR #138 do Ian, incorporado com seis correções (0120)

**O que ele resolve:** o capítulo 10 do onboarding define 36 perguntas a fazer ao cliente depois que
a extração roda. Nenhuma era sistema — quando o analista clicava "Contatar o Cliente", o que
perguntar saía da cabeça dele. Agora `fn_sugerir_perguntas` devolve a pergunta pronta, com
motivo/risco/impacto e os marcadores preenchidos. O encaixe é o melhor da entrega:
`exigencia_ausente` lê a **mesma** `fn_exigencias_do_caso` da pendência — pendência e pergunta são
duas faces da mesma avaliação e não podem divergir. Escopo declarado: 11 das 36, com as outras 25
nomeadas família a família.

**As seis correções feitas na incorporação:**

| | O quê | Por quê |
|---|---|---|
| 1 | **Conflito com o `main` resolvido, e a `0120` entrou na lista de comandos** | O `#137` mergeou depois da base dele. E a migration não estava no `db/README.md` — o portão do `run.sh` reprovava. |
| 2 | **A migration voltou a ser reaplicável** | `create policy` sem `drop policy if exists`: rerodar morria em *"policy already exists"*. O resto do arquivo já era reaplicável (`create table if not exists`, `on conflict do nothing`) — só as políticas escapavam, e a casa já tem o padrão (`0009`, `0107`, `0108`, `0115`). |
| 3 | **`caso_pergunta` virou append-only de verdade** | A tabela dizia "append-only por desenho" e publicava `for all to authenticated`. Medido: `set role authenticated; delete from caso_pergunta` **apagou a linha**. Agora são duas políticas, SELECT e INSERT — o desenho do `evento_auditoria` (0003), que é onde ele já estava certo. |
| 4 | **`{data_base}`/`{ano}` deixaram de errar o exercício** | O período saía de `max(referencia)` — máximo de TEXTO. Num caso com `2025` e `L24M`, a pergunta ia ao cliente dizendo *"No balanço de **L24M**…"*: rótulo de janela móvel, não data de balanço, e nem o mais recente. Agora ordena por ano com `fn_anos_texto`. |
| 5 | **A verificação embutida deixou de ser alçapão** | `count(*) where ativo <> 11 → exception`: bastava você **desativar uma pergunta** (a coluna `ativo` existe para isso) para a reaplicação morrer. É o mesmo defeito que a `0119` teve, na mesma posição do arquivo. Agora ela confere as 11 pelo código, e o que você fizer depois vira NOTICE. |
| 6 | **A pergunta passou a nomear a empresa** | A pendência nomeia a entidade desde a `0119`; a pergunta, não — e ela é **enviada ao cliente**. Num grupo de oito balanços, *"no balanço de 2025 não localizamos Ativo Total"* não diz de qual empresa se fala. Era o reemit que ele mesmo previu quando a `0119` ainda não existia. `ja_enviada` passou a ser por entidade junto: enviar sobre a Alfa não responde pela Beta. |

Menor, também feito: índice em `caso_pergunta (caso_id, pergunta_codigo)`, que o `ja_enviada` usa a
cada sugestão.

### O PR #135 do Ian, incorporado com quatro correções (0119)

**O que ele resolve, e o número que prova:** a `0113` perguntava "algum documento do tipo tem a
linha?". Num grupo com oito balanços, sete sem a linha de caixa, o oitavo respondia sim e as sete
ausências sumiam — **zero pendência**. A `0119` pergunta "cada entidade que trouxe linhas desse tipo
tem a linha NELA?": sete pendências, cada uma nomeando a empresa, e a oitava limpa.

**A suspeita que eu tinha, e que a medição derrubou:** granularidade fina costuma virar máquina de
pendência falsa. Medi num banco limpo, com o fixture Vertentes (5 entidades, 14 documentos, extração
fiel): **1 pendência antes, 1 depois — idêntico**. Os dois fallbacks dele funcionam. (Na primeira
medição vi 7, mas era lixo de outro teste no mesmo caso; num banco limpo o número não se move.)

**As quatro correções feitas na incorporação:**

| | O quê | Por quê |
|---|---|---|
| 1 | **Renumerada `0116` → `0119`** | A faixa 0116-0118 foi ocupada pelo PR #136, mergeado antes. O portão de prefixo duplicado do `run.sh` reprovava — e com razão. |
| 2 | **A verificação embutida deixou de ser alçapão** | Ela abortava a migration se encontrasse qualquer `escopo_entidade` não nulo. No dia em que o dono ligasse o override do COMBINADO — que é o que o cabeçalho manda ele fazer — e reaplicasse a lista do `db/README.md`, a migration **morreria no meio por causa de uma decisão legítima dele**. Medido: a versão original aborta. Agora prova o que interessa (a coluna não tem DEFAULT) e o override vira NOTICE. |
| 3 | **A varredura saiu da migration** para `db/varredura_linha_exigida.sql` | Era a única parte que tocava caso já gravado, e o efeito visível é uma leva de pendências novas na fila do painel sem ninguém ter enviado nada. Separada, o dono aplica a estrutura hoje e escolhe a hora da varredura — ou roda num mandato só. O script diz quantas pendências entraram. |
| 4 | **`fn_exigencias_do_caso` ficou 5,9× mais rápida** | O `explain analyze` mostrou 662 ms dos 914 ms num único filtro: `fn_linhas_do_tipo` rodando uma vez por DOCUMENTO em vez de por tipo. Separar em duas CTEs não mudou nada — o Postgres achata CTE simples e empurrava o filtro de volta. Com `as materialized`: **693 ms → 116 ms** num caso de 400 documentos. |

As duas propriedades novas estão travadas em teste (`db/test/linha_exigida_entidade.test.sql`,
blocos 8 e 9), e a do `materialized` é teste de TEXTO de propósito: medir por relógio daria um teste
que falha em máquina lenta e passa com o defeito de volta em máquina rápida.

### O que a sessão 50 (18/08) fez, e o que ficou de fora

Os sete itens da lista "o que está aberto" foram atacados em ordem, a pedido do dono. O que
**entrou**:

| | O quê | Onde |
|---|---|---|
| 1 | **Subtotais impressos viram LINHA.** O prompt passou a exigir o valor impresso na linha do agrupamento ("ATIVO CIRCULANTE ... 3.961"), que antes virava só o nome da `secao` e sumia. A `0116` ensina `fn_papel_linha` a reconhecer os totais novos (topo da DRE, DVA) para eles não receberem premissa e dobrarem a conta. | `n8n/lib/extract.mjs`, `0116` |
| 2 | **A divergência de mútuos é acusada.** Checagem B nova, lado a lado (ativo × passivo), disparada pelos dois lados do par. No fixture ela acusa exatamente os R$ 180 mil que o book planta de propósito — e o teste que cobrava "zero pendências" era, ele mesmo, a prova de que a checagem faltava. No painel, a fila agora diz QUAL checagem acusou. | `0117`, `portal/src/lib/rotulos.ts` |
| 3 | **A tela de Modelagem entrou na linguagem do portal:** `<main>` aninhado (que estreitava a página dentro do layout) foi embora, as três seções viraram `carta` com âncora, e uma trilha de passos no topo diz o que falta em cada uma. Na tabela, o cabeçalho gruda e o "salvar" aparece também no topo com o aviso de alteração não salva — os dois viviam no rodapé, fora da tela justamente enquanto se edita. | `portal/src/app/casos/[id]/modelagem/` |
| 4 | **`negativas`/`societario`/`parcelamentos` saíram da lista à mão** e viraram termos da taxonomia. A remoção de palavra de tipo em `parseEntidade` varre o vocabulário palavra a palavra, então quem entra lá é removido de graça. | `n8n/lib/taxonomia.mjs` |
| 5 | **O teto de gasto decide depois do `Extrair Texto`.** Com o documento medido, a estimativa deixa de ser por byte (margem de 1,8×, que recusava lote que cabia) e passa a contar linhas e BLOCOS — exatamente os que o `Fatiar Extracao` vai gastar. Medido no book: guarda por byte US$ 0,67 contra custo real US$ 0,49; por conteúdo, US$ 0,61. Continua barrando antes de qualquer gasto. | `n8n/lib/custo.mjs`, grafo |
| 6 | **Dedup por fingerprint (a segunda metade da 0026).** Prompt+modelo+esquema viram uma impressão gravada na versão; mesmo arquivo + mesma impressão + extração que TEM linha ⇒ o grafo pula a chamada. A exigência de "ter linha" é o que impede uma extração falha de valer como feita. | `0118`, grafo |
| 7 | **As listas do painel saíram do teto de 1000** (documentos, pendências e mandatos), com paginação de mil em mil e um aviso que aparece se o teto de segurança de 50 mil for atingido. | `portal/src/lib/supabase/paginar.ts` |

O que **ficou de fora, e é honesto dizer**:

- **O item 1 não pode ser provado sem gastar crédito.** O prompt mudou e os testes travam o texto
  dele, mas se o modelo passa a devolver os totais é a rodada que responde. É o passo 4 acima.
- **A checagem de mútuos cobre MÚTUO contra MÚTUO.** Conta corrente rotativa, aluguel entre
  coligadas e rateio de despesa também moram na planilha intragrupo e continuam sem conferência —
  casar cada uma com a conta certa de cada balanço é outro problema.
- **A tela de Modelagem recebeu revisão de apresentação, não redesenho de fluxo.** A ordem dos três
  passos e o modelo de dados por trás dela continuam os mesmos.

### O book inteiro, quando houver crédito

Os 38 documentos do `book-canastra` estão prontos para subir:

| | Estado |
|---|---|
| Orçamento | estima **US$ 1,88** (era US$ 2,46, e US$ 11,40 no estimador plano) → **passa** |
| Gasto real esperado | **~US$ 1,25** — 42% do teto de US$ 3 (era 2,23 antes do agrupamento) |
| Timeout do n8n | **desativado** (conferido pelo dono em 11/08) |
| Duração | **~23 minutos** (33s por extração no Tier 1) |

> **ANTES DE RODAR, REIMPORTE O `n8n/workflow.e1-ingestao.json`.** A execução de 12/08 recusou o
> lote com *"51 chamadas ≈ US$ 7,65"* — um número que o código deste repositório não produz desde
> 07/08 (US$ 0,15 por chamada saiu de lá). O n8n executa o JSON **importado**, e merge não
> reimporta. A partir da v3 dá para conferir da tela: a mensagem de recusa começa com
> `[orçamento v3 (2026-08-13)]` e o campo `orcamento_versao` aparece na saída do nó mesmo quando o
> lote passa. Se a versão não aparecer, o workflow importado é velho.

Gerar os PDFs: `cd test-data/book-canastra && PYTHONPATH=. python3 gerar.py`

> **A rodada de 17/08 ("Teste V45") já aconteceu, e o que ela achou muda o que a próxima tem de
> provar.** Foram **438 linhas**: 19 dos 35 documentos — os centrais (Balanço, DRE, DFC, DMPL, DVA,
> balancetes, razão, faturamento) — **nunca tiveram a extração chamada**, e nada reclamou. A causa era
> topológica (duas conexões cruas no mesmo input, e só o ramo do fallback propagava), está corrigida
> com o `Juntar Ramos`, e a classe inteira ficou barrada por teste. O que a próxima rodada precisa
> trazer, além do custo: **`lote_integro` verdadeiro** no `Conferir Lote` — sem isso, qualquer número
> de cobertura está medindo só os documentos que chegaram lá.

**O que trazer de volta:** a saída do nó **`Resumo de Custo`** (último do canvas) — ela traz o custo
real do lote, o que o orçamento estimou e os **tokens de saída por linha**, que é o número com que
`CUSTO_POR_MB_USD` e o modelo de saída se recalibram. Mais: quantos dos 38 chegaram, e o que a
reconciliação abriu — em especial o erro plantado de **R$ 240 mil na planilha de mútuos**.

### O buraco que a rodada completa abriu — e as três camadas que o fecham

A rodada do `book-canastra` (35 documentos, 21 min, US$ 0,71, no workflow ANTIGO) respondeu o custo e
abriu outra coisa: **das 2.893 células de valor dos PDFs, chegaram ao banco 1.139 — 39%**. Duas
famílias: 5 documentos TRUNCARAM (teto de 16.384 tokens de saída do gpt-4o; `01_Balanco` sozinho pede
~20.900) e o resto veio pela metade **em silêncio** (`17_Livro_Razao`: 99 de 461, sem uma pendência).

O `.xlsx` da modelagem exportado dessa rodada passa em **9 de 10** itens do auditor; o único reprovado
é o balanço não fechar por 40.169 — que é o buraco da extração chegando ao arquivo entregue.

Três camadas, no `n8n/lib/cobertura.mjs` e no grafo:

| | O que faz | Onde |
|---|---|---|
| **1. Medir antes de chamar** | lê a camada de texto do PDF na instância (sem IA, sem custo) e conta as linhas com número | nó `Extrair Texto` |
| **2. Fatiar** | acima de 60% do teto, um item por bloco de ≤234 células, cada um com o TEXTO da primeira e última linha da faixa como âncora | nó `Fatiar Extracao` |
| **3. Guarda de cobertura** | compara o que voltou com o que o documento tem; abaixo de 60% abre pendência com os dois números | nó `Juntar Blocos` |

No `book-canastra`: 38 documentos → **41 chamadas** de extração, 3 fatiados. Custo projetado com o
dado INTEIRO: **~US$ 1,4** (era 0,71 com 39% do dado) — menos da metade do teto.

> **Corrigido na execução 6164 (13/08, mesmo dia):** o fan-out corta a cadeia de `pairedItem` do
> n8n, e toda expressão `$('Outro Nó').item` rio abaixo virou `undefined` — os nós Postgres
> receberam "undefined" em Query Parameters. Agora `Fatiar Extracao` e `Juntar Blocos` declaram
> `pairedItem`, os dois ids viajam com o item, e `Gravar Campos`/`Registrar Diagnostico`/`Reconciliar`
> leem do PRÓPRIO item. **Quem for reimportar precisa da versão com essa correção.**
>
> **O que a camada 3 promete, com precisão:** ela não impede o modelo de pular uma linha. Impede que
> isso seja silencioso. E o `Extrair Texto` tem `onError: continue` — PDF escaneado não tem camada de
> texto, o nó falha nele, o documento segue como imagem e as camadas 2 e 3 se calam. **O pior caso da
> mudança é o comportamento de ontem.**

### A rodada de 14/08 com o agrupamento: cobertura 39% → 58%

**1.683 linhas gravadas** contra 1.139 (+48%), ainda **sem** as camadas 2 e 3 (elas estavam
desligadas: a referência a ramo irmão não resolvia). O ganho é todo do agrupamento, e o maior efeito
foi o fim do truncamento nos dois maiores documentos:

| Documento | células | antes | agora |
|---|---:|---:|---:|
| `01_Balanco_..._2025x2024x2023` | 326 | **0** | **281 (86%)** |
| `35_Demonstracoes_Contabeis_...` | 308 | **0** | **282 (92%)** |
| `13/14_Balanco_COMBINADO` (8-9 colunas de empresa) | 70 | 57 | 57-64 (81-91%) |
| `17_Livro_Razao_Fornecedores` | 461 | 99 | **1** ← ver abaixo |

**O livro razão caiu para 1 linha, e o guarda de desalinhamento explicou por quê:** o documento tem
**três colunas de valor** (Débito, Crédito, Saldo), o modelo devolveu três valores por lançamento e
declarou `cols` VAZIA — 98 de 99 contas descartadas. O guarda agiu certo; faltava o prompt dizer que
coluna de valor **não é só período e empresa**. Corrigido em 14/08, com os cinco casos nomeados
(razão, balancete, aging, estoques, mapa de dívida) e a consequência escrita.

### A régua da cobertura estava na UNIDADE ERRADA (corrigido em 14/08)

A guarda comparava **linhas com dígito** (do texto) com **pares conta × coluna** (do banco). São
unidades diferentes, e num documento comparativo a razão passa de 100%: o `02_DRE` deu 91 pares
contra 46 linhas = **198%**. A guarda ficava cega justamente onde há mais a perder.

Agora as duas pontas estão em CONTAS:

| | |
|---|---|
| régua | **linhas de conta** — tem valor e tem identidade (rótulo, código de conta, ou linha de tabela numérica); fora cabeçalho de ano, CNPJ, data, página, CRC/CPF |
| medida | **linhas devolvidas** pela extração (era contas distintas até 17/08 — ver abaixo) |
| `02_DRE` | ~30 de 39 = **77%** — ele ESTÁ incompleto, e a régua antiga dizia 198% |

O limiar subiu de 0,60 para **0,85** porque o alvo é cobertura total: isso vai abrir pendência em
documentos que antes passavam, e é o objetivo.

### A régua calibrada contra a verdade — e a cegueira que ela escondia (17/08)

`node n8n/medir-regua-cobertura.mjs` confronta a régua com a contagem que o **gerador** do book
declara (ele sabe quantas linhas escreveu; não é outra leitura do PDF). A primeira medição, nos 38
documentos, achou o defeito que o limiar nunca resolveria:

| Documento | linhas de verdade | a régua via | |
|---|---:|---:|---|
| `17_Livro_Razao` | 99 | **3** | −97% |
| `15_Balancete` | 78 | **3** | −96% |
| `22_Aging` | 14 | **2** | −86% |
| `27_Imobilizado` | 9 | **2** | −78% |

A régua acertava as demonstrações (+2% a +4%) e **desabava nos analíticos — os que perdem dado**. E
como a guarda se cala abaixo de 20 linhas, a cegueira virava **silêncio**: o livro razão, o caso que
motivou as três camadas, nunca chegava a ser avaliado por elas. A causa: "termina em valor" pressupõe
rótulo e valor na mesma linha, e num documento de sistema contábil a linha termina em `D`/`C`, o
rótulo é código sem letra, ou o histórico é parágrafo que o leitor de PDF deixa sozinho numa linha.

A **régua v2** troca isso por "tem valor E tem identidade" (rótulo, código de conta, ou linha de
tabela numérica com dois valores ou mais). Erro absoluto médio **29% → 9%**, sem piorar um documento
sequer; os avaliados pela guarda passam de 10 para 14. O limiar **fica em 0,85**: o pior documento
honesto do book se reporta a 96%, então sobram 11 pontos de folga — e a folga é para o documento
real, que é mais sujo que o sintético. O CI roda a medição a cada push.

### E a unidade do OUTRO lado da guarda: linha, não conta distinta (17/08)

A mesma medição achou o viés oposto, e ele tinha número exato: a guarda comparava **contas distintas
gravadas** com **linhas do texto**, e num livro razão o mesmo fornecedor aparece em vários
lançamentos — 99 linhas para **66 históricos distintos**. Uma extração que não perdia NADA se
reportava em 66% e abria pendência. Foi o segundo erro de unidade da mesma guarda, na direção
contrária ao primeiro (pares × linhas dava 198%).

Agora as duas pontas são **linha**: `achatarGrupos` marca cada campo com a linha do documento que o
originou, `juntarBlocos` conta as linhas distintas depois de limpar a emenda, e o campo **não chega
ao banco** (nada de migration por causa de uma contagem interna). Uma conta com três colunas conta
uma vez; dois lançamentos do mesmo fornecedor contam dois. Bloco no formato plano antigo, sem a
marca, cai para as contas distintas — o comportamento de antes, em vez de cobertura zero. O painel do
`Resumo de Custo` passa a somar a mesma unidade, e `contas_distintas` continua saindo por documento,
porque é ela que denuncia rótulo repetido.

### O custo, medido e projetado (13/08/2026)

A primeira fatura real veio dos 14 documentos do `book-vertentes`: **US$ 0,90**, com alvo de US$ 0,50.
84% era saída de extração, a ~64 tokens por célula de valor — 45% acima do que este repositório
supunha. A saída passou a ser **agrupada** (uma seção por grupo, colunas declaradas uma vez, conta
escrita uma vez com um valor por coluna) e o `medir-custo-book.mjs` projeta:

| Book | formato plano | agrupado |
|---|---:|---:|
| `book-vertentes` (14 docs) | US$ 0,857 (fatura real: **0,90**) | **US$ 0,471** |
| `book-canastra` (38 docs) | US$ 2,226 | **US$ 1,252** |

~~**Aberto:** o livro razão projeta 109% do teto de saída mesmo agrupado.~~ **Fechado no mesmo dia
pelo fatiamento** (camada 2): ele vira 2 blocos de ≤234 células e nenhum deles chega perto do teto. O
`medir-custo-book.mjs` continua avisando, nomeando o arquivo, se algum documento voltar a passar de
80% do teto numa chamada — a guarda fica de pé mesmo depois de a causa conhecida sumir.

## O que só o dono pode fazer

**As duas linhas de infra da sessão 52 saíram em 19/08** — migrations até a `0125` aplicadas, workflow
reimportado. A sessão 53 acrescentou uma migration e um item que não é de infra.

1. **RODAR O BOOK NUM MANDATO NOVO, e depois o aceite sobre o export de verdade.** Continua sendo o
   item que destrava mais, e o que ele prova está na tabela de "O próximo passo" — sete coisas, três
   delas checagens que nunca viram dado real. O aceite são duas peças: `auditar-xlsx.mts` (10 itens
   automáticos) e `docs/ACEITE.md` (10 itens humanos). Foi a falta desse par que deixou sair, em
   06/08, um arquivo com seis números errados e as suítes verdes.

2. **Aplicar a `0126`.** Não muda nível de autonomia nenhum nem comportamento de ingestão/export —
   cria o golden set e o portão da regra de ouro. Depois de aplicar, `/autonomia` passa a dizer em
   que cada nível se apoia; hoje ela adivinha pelo nome do estágio.

3. **A ROTULAGEM DO GOLDEN SET — e este não é de infra, é de julgamento.** A máquina está pronta e
   testada; o que falta é o `f0/06` executado: ~20 documentos REAIS por tipo core, estratificados por
   qualidade de captura (digital, PDF nativo, escaneado, foto), dois rotuladores nos casos ambíguos, e
   a rodada **congelada** ao fim. Rotular o book não serve e o banco recusa (`origem = 'sintetico'`):
   o gabarito dele já é conhecido, então a concordância mediria o instrumento. É o item de maior
   alcance que existe hoje — sem ele o dial não sobe por medição e a F4 do `docs/03` não começa.

> **A conferência de 30 segundos, depois de qualquer rodada nova.** Merge não é apply, e da tela
> "aplicada" e "não aplicada" têm a mesma aparência. Vale reconferir quando algo parecer não ter
> mudado:
> ```sql
> -- 0122: a pergunta ao cliente em português
> select fn_periodo_por_extenso('multi','23,24,25');  -- esperado: 2023 a 2025
> select fn_valor_pt_br(16060, 'milhar');             -- esperado: R$ 16.060 mil
> select fn_anos_texto('L36M');                       -- esperado: {} (antes: {2036})
>
> -- 0123/0124/0125: as funções que a sessão 52 acrescentou
> select proname from pg_proc
>  where proname in ('fn_texto_nomeia_mutuo','fn_mutuo_com_socio',
>                    'fn_contraparte_intragrupo','fn_lado_intragrupo',
>                    'fn_natureza_intragrupo','fn_reconciliar_intragrupo');
> -- esperado: as SEIS
>
> -- 0125 muda o TIPO DE RETORNO da fn_valores_por_ano (quatro colunas novas):
> select count(*) from information_schema.routines r
>  join information_schema.parameters p on p.specific_name = r.specific_name
>  where r.routine_name = 'fn_valores_por_ano' and p.parameter_name = 'arquivo';
> -- esperado: 1. Zero significa que a 0125 não entrou, e a nota do export volta
> -- a dizer só "Extraído de BALANCO" sem quebrar nada — falha silenciosa.
> ```

> **Conferência de 5 segundos do workflow, se a rodada sair estranha:** o canvas tem **33 nós**.
> Procure, em ordem: `Medir Documento` → `Orcamento do Lote` → `Lote cabe?`, `Precisa Fallback?` →
> `Juntar Ramos`, `Registrar Documento` → `Recompor Contexto` → `Extracao ja feita?` (o dedup) e
> `Juntar Extraidos`, e na ponta direita `Resumo de Custo` → `Gravar Uso do Lote` → `Conferir Lote`.
> E, para cobrir falha de qualquer origem, o `workflow.erros.json` ligado como **Error Workflow** nas
> Settings do Intake (`n8n/README.md`).

## O que está aberto no produto

> **Os quatro itens que abriam esta lista em 17/08 foram FECHADOS na sessão 50** (subtotais
> impressos, checagem de mútuos, tela de Modelagem e os apelidos à mão) — ver "O que a sessão 50
> fez". Dois deles com uma ressalva registrada lá: o dos subtotais só a rodada real prova, e a
> checagem de mútuos cobre mútuo contra mútuo, não a planilha intragrupo inteira.

- ~~**AS PERGUNTAS AO CLIENTE NÃO TÊM TELA**~~ — **fechado em 18/08 (sessão 51)**: elas ganharam
  uma **aba própria**, `/casos/[id]/perguntas`, com o texto pronto para copiar, o registro de envio
  por `fn_registrar_pergunta_acao` (texto congelado) e o de descarte. Ficaram FORA da fila de
  pendências por decisão do dono — sugestão que ninguém fez ainda não se mistura com decisão sobre
  problema medido. Ver "As perguntas ao cliente ganharam a ABA que faltava". **Depende da `0120`
  estar aplicada no Supabase**; sem ela a aba explica o que falta em vez de quebrar.
- ~~**A conferência das linhas intragrupo que NÃO são mútuo**~~ — **fechado em 19/08 (sessão 52)**,
  pelo ESPELHO entre cada par de empresas (`0124`), não pela planilha: a planilha de faturamento
  intragrupo é FLUXO e o balanço é ESTOQUE. Ver "O INTRAGRUPO QUE NÃO É MÚTUO". **O que ela NÃO cobre,
  e fica anotado:** rateio de despesa que não deixa saldo no balanço (não há espelho para conferir), e
  mútuo com sócio — cujo par é o contrato com o quotista, que ninguém cruza hoje.
- ~~**O item mais denso do book ainda estoura o teto de saída**~~ — **fechado em 19/08 (sessão 52),
  e a correção anotada aqui era a errada.** Não faltava extrair por faixa de PÁGINA: o fatiamento
  estava desligado por erro de unidade (teto em CÉLULAS aplicado a uma contagem de LINHAS), e ZERO
  dos 38 documentos era fatiado. Ver "O FATIAMENTO ESTAVA DESLIGADO". **O que sobra, e agora aparece
  na fila:** linha que sozinha passe do teto — sem corte mais fino possível; nenhum documento do book
  cai nesse caso.

### O QUE SOBROU, em ordem de quem destrava o quê (19/08, sessão 52)

**DEPENDE DA RODADA DO DONO — não dá para começar antes:**

1. **Recalibrar o limiar de cobertura (0,85)** com pontos reais. Hoje ele está calibrado contra 38
   documentos SINTÉTICOS.
2. **Conferir o fatiamento em produção** — ele nunca rodou ligado. Cortou onde devia? A emenda entre
   blocos duplicou linha? A `juntarBlocos` limpa emenda repetida e nunca viu bloco de verdade.
3. **Conferir os subtotais impressos** (`0116`) — a única mudança daquela rodada que só a extração
   real prova.

**NÃO DEPENDE DE NADA — pode começar já:**

4. **Golden set e concordância medida** — **a MÁQUINA foi feita em 19/08 (sessão 53, `0126`); o que
   falta é a ROTULAGEM.** O esquema, as cinco métricas do `f0/06` e o portão que cobra existem e
   estão travados por teste; rotular documento real de cliente continua sendo trabalho de execução
   do dono, com LGPD, e o `f0/06` já dizia que não se monta em documentação. Ver "A REGRA DE OURO
   PASSA A SER EXECUTADA". Sem a rotulagem o dial continua não subindo por medição — a diferença é
   que agora ele também não sobe **em silêncio**.
5. **Bloco numérico dos três cenários lado a lado** — dimensionado abaixo, e é decisão do dono se
   vale: exige PARAMETRIZAR a cascata da aba que produz os números do modelo.
6. **Modo A do `f0/07`** (base viva consultável no portal) — **ou a decisão escrita de que ele não
   vem.** Está tomada por omissão há meses; o §2.4 do diagnóstico pede que se escreva qual das duas
   é a verdade.

**BLOQUEADOS POR DADO QUE O KIT BÁSICO NÃO COLETA** — não são trabalho, são espera:

7. **Tranche em moeda estrangeira** (falta a MOEDA por tranche; aplicar câmbio sem saber erra ~5×).
8. **Vida útil por classe de imobilizado** (exige laudo).
9. **Goodwill** — os três blocos de espelho só valem quando houver ágio de verdade no caso.

**ANOTADOS, PEQUENOS, NÃO RECONFERIDOS NESTA SESSÃO:**

10. **`fn_conferir_modelagem` conta premissa de sazonalidade como "sem valor"** — vem da sessão 39. O
    critério em vigor (`0101`) é `valores is null or valores = '{}'`, e uma premissa de sazonalidade
    guarda os fatores em outro lugar. **Não reconferi contra dado real** — fica como suspeita, não
    como fato.
11. **"Sugerir do realizado"** (proposta, nunca feita): oito premissas saem do próprio balanço/DRE do
    caso, com `origem = 'historico'`, que o schema da `0038` já prevê.

O diagnóstico completo, com evidência e prioridade, está em `docs/DIAGNOSTICO_SISTEMA_2026-08-11.md`.
Os itens acima, com o histórico de cada um:

- ~~**A entidade sai poluída com o período**~~ — **fechado em 17/08.** Eram quatro famílias de
  sujeira, não uma: o comparativo de TRÊS exercícios (`2025x2024x2023`, que o regex de um `x` só não
  pegava), preposições (`Aging De Canastra`), sobra de tipo quando o apelido casado é mais curto que
  o nome do arquivo (`Composicao Imobilizado Canastra`), e nome sem tipo nenhum virando empresa
  (`Relatorio Auditor Independente`, `Iv Rev3`). Medido nos 38 nomes do book: **32 entidades limpas,
  6 nulas** (essas vão ao fallback por conteúdo, que lê a entidade do documento) e **zero sujas**.
  A remoção de palavra de tipo usa a própria taxonomia como fonte, palavra a palavra, então cresce
  sozinha. ~~Fica anotado: `negativas`, `societario` e `parcelamentos` numa lista à mão~~ — **já
  resolvido**: os três viraram termos de `CERTIDOES`, `ORGANOGRAMA` e `SITUACAO_FISCAL` em
  `n8n/lib/taxonomia.mjs`, e a regra do vocabulário os remove sozinha. O que sobrou naquela lista é
  de outra natureza (ruído de nome de arquivo: `rev3`, `scan`, `anexo`) e não tem lugar na taxonomia.
- ~~**Fixture de extração do `book-canastra`**~~ — **fechado em 19/08 (sessão 52)**: existe
  `fixture_book_canastra.sql` (28 documentos, 1.264 linhas) e `canastra.test.sql` no `run.sh`, e a
  primeira rodada dela achou três defeitos na checagem de mútuos (`0123`). Ver "A FIXTURE DE
  EXTRAÇÃO DO BOOK-CANASTRA". **Fica anotado o que ela NÃO cobre:** ela prova a ingestão sobre
  documento difícil com extração FIEL — a extração real sobre os PDFs sujos (o que o modelo de
  verdade lê deles) continua sendo provada só pela rodada do dono.
- **Resumo dos três cenários lado a lado** — **parcialmente atacado em 19/08 (sessão 52)**, e o que
  ficou de fora está dimensionado. Entrou o painel `OS TRÊS CENÁRIOS SÃO TRÊS?`, que denuncia cenário
  não diferenciado (o Cliente Case nasce idêntico ao Base). NÃO entrou o bloco numérico lado a lado:
  a lista de métricas do §2.2 mistura o que uma cascata paralela alcança (receita, EBITDA) com o que
  exige replicar o modelo inteiro (DSCR mínimo, necessidade de pico), e a metade viável custa
  PARAMETRIZAR a cascata da aba de receita pelo cenário — refatoração da aba que produz os números do
  modelo, com um CHECK provando que a sombra do cenário ativo é igual à linha ativa. Ver "OS TRÊS
  CENÁRIOS SÃO TRÊS?".
- ~~**Proveniência completa na aba `Premissas`**~~ — **fechado em 19/08 (sessão 52)** e em todas as
  catorze abas, não só na `Premissas` (`0125`). Ver "A PROVENIÊNCIA VOLTA AO ARQUIVO DE COMITÊ".
- **Golden set** e concordância medida — sem isso o dial de autonomia não sobe, e a F4 do
  `docs/03` não começa.
- **Modo A do `f0/07`** (base viva consultável no portal) — ou a decisão escrita de que ele não vem.

## Os comandos que funcionam

```bash
# insumo dos testes (gera pdf/ + GABARITO.json, não versionados)
cd test-data/book-vertentes && PYTHONPATH=. python3 gerar.py && cd -

node --test 'n8n/test/*.test.mjs'                                      # da RAIZ do repo
./portal/node_modules/.bin/tsx portal/scripts/verificar-export.mts
PGHOST=/tmp PGUSER=postgres PGDATABASE=postgres db/test/run.sh
PGHOST=/tmp PGUSER=postgres PGDATABASE=postgres E2E_PSQL="psql" \
  ./portal/node_modules/.bin/tsx test/e2e/run.mts
```

> `E2E_PSQL` é o **comando** do psql, não um flag: com `E2E_PSQL=1` o arnês tenta executar um binário
> chamado `1`. E o `node --test` roda da raiz — de outro diretório o glob não casa nada e a suíte diz
> "0 testes" em vez de falhar.
