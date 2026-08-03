# Handoff — Tratamento de Dados Financeiros (Oria)

Nota de transição de contexto — **leia isto primeiro, é o resumo pra retomar rápido em um chat
novo.** O histórico detalhado sessão-a-sessão está preservado abaixo (seção "Sessão 7 (cont.¹⁻¹⁶)")
só como referência — não precisa ler tudo pra continuar, comece por aqui.

**Última atualização:** 2026-08-01 (sessão 21). **Estado do `main`:** mergeado até o **PR #70**
(`main` em `60f2d26`). Migrations `0001`→**`0034`** (a `0033` o dono já aplicou; a **`0034` é NOVA e
não está aplicada**). Branch de trabalho: **`claude/handoff-next-steps-6k88f2-7pv76w`**.

**AS ETAPAS 1 A 6 DO PLANO DO DONO ESTÃO FEITAS** e aguardam a validação dele. O dono autorizou
explicitamente executar todas de uma vez nesta sessão ("execute tudo de uma vez, não pare para me
perguntar nada"), o que suspende — só para esta rodada — a regra de uma etapa por vez.

**Existe CI** (`.github/workflows/suites.yml`): quatro suítes + geradores + tsc/eslint/build, em todo
push e PR. Se o PR ficar vermelho, é regressão sua.

**Contadores atuais:** `node --test 'n8n/test/*.test.mjs'` = **162**; `verificar-export.mts` =
**352**; `db/test/run.sh` = **34 migrations**; `E2E_PSQL=... npx tsx test/e2e/run.mts` = **24**.

## Sessão 28 (2026-08-03) — Fase 7.4: o export dirigido pelas escolhas do portal

Última da série 7.x. O export completo passa a ser **consequência** do que foi decidido na tela de
Modelagem, em vez de o lugar onde a decisão é tomada.

### Cabeçalho: 11 linhas fixas → 4

Congelado em `ySplit: 4` — título, branco, Exercício, mês. As três células de input (entidade
modelada, último exercício realizado, índice macro) **saíram do topo** e vivem no bloco
**PARÂMETROS DO MODELO**, no rodapé, junto da BASE DO MODELO. Continuam editáveis: trocar a entidade
ali recalcula o modelo inteiro sem reexportar. O que muda é que a escolha de origem fica no banco,
com autor e data, e é ela que vale na próxima exportação.

**`Tipo` (Real/Projetado) e `Dado encontrado` NÃO foram deletadas**, embora a instrução permitisse.
Com o congelado em 4 elas simplesmente deixam de ficar fixas no topo — e apagá-las custaria o
diagnóstico "só Balanço"/"SEM DADO", que a sessão 12 registrou como o caso mais traiçoeiro (balanço
existe, receita não, projeção sai zerada parecendo empresa que vale zero).

### A armadilha nº 1 da sessão 12 voltou, e a guarda pegou

`sheet.getRow(N)` numa linha ALÉM do fim **cria** a linha, e todo `addRow` seguinte passa a
acrescentar depois dela. Peguei a célula do seletor de índice macro (linha 189) no meio do modelo, e
o modelo inteiro desceu: de ~200 para **291 linhas**. A guarda nova do bloco de parâmetros acusou na
hora, com a mensagem dizendo o número. A correção é o mesmo padrão da BASE DO MODELO: **escrita
adiada** — decide-se o conteúdo no lugar onde ele é conhecido, escreve-se no fim.

### PROJEÇÃO POR LINHA — o coração do pedido

Bloco novo, emitido **antes** do esqueleto agregado quando o caso tem configuração: uma linha por
linha extraída que tenha premissa vinculada, com as premissas do caso logo acima (uma linha cada, um
valor por exercício projetado) e as fórmulas citando aquelas células.

**Três primitivas desenhadas, quatro não** — e as quatro deixam a célula **VAZIA com nota dizendo
por quê**, nunca um número:

| Primitiva | Estado |
|---|---|
| `crescimento_composto` | ✅ anterior × (1 + premissa) |
| `indice_macro` | ✅ mesma matemática |
| `valor_por_ano` | ✅ a premissa É a linha |
| `pct_de_linha`, `dias_de_giro`, `preco_x_volume`, `curva_mensal` | ⛔ célula vazia + nota |

Preencher com zero, ou com uma fórmula aproximada, entregaria **projeção errada com cara de projeção
pronta**. Zero num modelo financeiro é um valor, não um vazio.

Só as colunas consolidadas (FY) recebem fórmula. Distribuir nos meses depende de `curva_mensal`
(sazonalidade), que não está desenhada — e mês preenchido por rateio uniforme seria um número que
ninguém escolheu.

**Ano sem valor de premissa fica vazio com nota**, e as linhas que dependem dela ficam sem projeção
naquele exercício. É a mesma disciplina do "SEM FOCUS".

**Sem configuração, o arquivo sai como sempre saiu:** o esqueleto agregado é o fallback, e há assert
disso. Esta fase não tira modelo de nenhum caso existente.

### Portão 2 no modo completo

`?modo=completo` pergunta a `fn_avaliar_portao2` e **recusa com 409** quando o caso não é elegível,
listando os motivos. O modo `dados` **não** passa por essa checagem, de propósito: ele é insumo de
conferência, e conferir é o que se faz antes de aprovar — bloqueá-lo criaria o impasse de precisar da
aprovação para poder conferir.

### Uma correção que o teste ditou

A fórmula do crescimento composto testava também a célula do exercício anterior com `=""`. Comparar
célula NUMÉRICA com string vazia é ambíguo, e o assert media **0** onde devia medir 1100. Agora a
guarda testa só a premissa: se ela está vazia não há projeção; se a anterior está vazia, a cadeia nem
começou, porque linha sem valor-base não é emitida.

### Contadores

| Suíte | Antes | Agora |
|---|---|---|
| `node --test n8n/test/*.test.mjs` | 176 | **176** |
| `verificar-export.mts` | 397 | **417** |
| `db/test/run.sh` | 39 migrations | **39** (nenhuma migration nesta fase) |
| `test/e2e/run.mts` | 27 | **27** |

### Defeito religado

- congelado de volta a 11 → `FALHOU: o congelado do topo é de 4 linhas (era 11) — 11`;
- primitiva não desenhada preenchendo zero → `FALHOU: primitiva não desenhada deixa a célula VAZIA
  (nada de zero inventado) — 0`.

### O que fica em aberto da modelagem

- **as quatro primitivas restantes**, com destaque para `pct_de_linha` (margem, % da receita) e
  `curva_mensal` (sazonalidade mensal) — são as mais pedidas na prática, e cada uma exige decidir
  QUAL linha é a base do percentual;
- os outros 11 setores do catálogo, se o dono quiser (é semente, não motor).

E então a **Fase 6 (calibração)**, que era o que estava em curso quando esta série começou.


## Sessão 27 (2026-08-03) — Fase 7.3: a tela onde linha e premissa se cruzam

`/casos/[id]/modelagem` (rota nova) + `db/migrations/0039`. É onde "cada caso é um caso" vira
operação: o analista escolhe as premissas do mandato e diz **onde cada uma entra na projeção**.

### Quatro passos, na ordem em que se pensa

1. **Parâmetros** — entidade modelada, último exercício realizado, índice macro, setor, anos
   projetados. São as três células que saíram do topo da aba Modelagem (decisão do dono), mais o
   setor, que filtra o passo 2.
2. **Premissas do caso** — o catálogo da `0038` **filtrado pelo setor**, agrupado por natureza, com
   uma coluna por ano projetado. Sem setor definido vem só a base comum — que é a resposta certa
   para "ainda não sei", e não uma lista de 90 premissas para escolher no escuro.
3. **Linhas × premissas** — as linhas do caso agrupadas por seção canônica, cada uma com sua
   premissa e sua sazonalidade, mais o **aplicar em lote por seção**.
4. **Conferência** — e ela está no **TOPO**, não no rodapé: quantas linhas ficariam sem projeção,
   qual premissa está ativa sem valor, quais vínculos apontam para linha que não existe. Pôr isso no
   fim seria pôr o resultado depois da decisão.

### Três coisas que a tela torna impossíveis

- **ano em branco virar zero.** O campo vazio fica **fora** do `jsonb` — ausência é ausência, e a
  `0038` trata premissa sem valor como "não projeta aquele ano". Escrever 0 ali seria inventar a
  premissa mais perigosa que existe.
- **lote silencioso.** Lote que não encontra nenhuma linha na seção **avisa** em vez de recarregar
  como se tivesse funcionado.
- **recusa passar por sucesso.** Toda ação lê `recusado` do payload: as funções da 0036/0037/0038
  devolvem recusa em vez de exceção (exceção desfaria o registro da tentativa), então `error` nulo
  **não** significa que salvou.

### O defeito que eu mesmo introduzi, e o que fiz com ele

A primeira versão da tela consultava `campo_extraido` direto para listar as linhas. **`campo_extraido`
não tem `caso_id`** — o vínculo é `campo_extraido → documento_versao → documento`. Com a RLS aberta a
qualquer autenticado (decisão do dono de 31/07), a consulta trazia as linhas de **todos os
mandatos** para a tela de um. Nada barraria isso em produção.

Corrigi primeiro com embed `!inner` e filtro no campo aninhado — funciona, e continua dependendo de
alguém escrever o join certo em **cada consulta nova** que a tela receber. Então virou função:
**`fn_linhas_para_modelagem(caso_id)`** (`0039`), com o escopo por caso num lugar só, coberto por
teste SQL que cria um caso vizinho e prova que a linha dele não aparece. Mesmo raciocínio de
`fn_aplicar_premissa_em_lote`: quem sabe quais linhas existem é o banco.

A função também resolve uma duplicação que eu tinha deixado passar: a tela normalizava o rótulo em JS
para casar com `caso_linha_premissa`. Duas definições de "mesma linha" divergem no primeiro
caractere que só uma das duas trate — agora o `rotulo_norm` vem do banco, de `fn_normalizar_texto`.

`valor_ultimo` é `max(abs())`, não soma: serve para o analista **reconhecer** a conta na lista, e
somar ocorrências de períodos diferentes daria um número que não existe em lugar nenhum — número
inexistente numa tela de modelagem é convite a erro.

### Contadores

| Suíte | Antes | Agora |
|---|---|---|
| `node --test n8n/test/*.test.mjs` | 176 | **176** |
| `verificar-export.mts` | 397 | **397** |
| `db/test/run.sh` | 38 migrations | **39** + 3 asserts novos em `premissas.test.sql` (31) |
| `test/e2e/run.mts` | 27 | **27** |

### Defeito religado

- função sem o join por caso → `FALHOU: a linha do caso vizinho NÃO aparece nas linhas deste caso`.

### O que falta da 7.x

- **7.4** export completo: cabeçalho da Modelagem reduzido a 4 linhas, as linhas do modelo passam a
  ser as do caso, projeção pelas 7 primitivas de `premissa_formula`, Portão 2 respeitado.
- Depois disso, a **Fase 6 (calibração)**.


## Sessão 26 (2026-08-03) — Fase 7.2: a premissa deixa de ser código e passa a ser dado

`db/migrations/0038`. O modelo tinha **15 premissas hardcoded** (`PR` em `export-modelagem.ts`)
sobre um esqueleto fixo de linhas (`LINHAS_BASE`). Não sobrevive ao que o dono descreveu: "cada caso
vai ser um caso, vai vir com linhas diferentes, contas diferentes, vai precisar de inputs e
premissas diferentes".

**A inversão:** premissa passa a ser **dado**. Acrescentar "RevPAR" ao vocabulário do sistema é uma
LINHA no catálogo, não um ramo de `if` no gerador — é o que impede um agregado de 20 setores de
virar 20 caminhos de código.

### Quatro tabelas, e por que quatro

| Tabela | O que guarda |
|---|---|
| `premissa_catalogo` | o vocabulário global: o que EXISTE como premissa |
| `caso_modelagem` | parâmetros do caso — entidade modelada, último exercício real, índice macro, **setor** |
| `caso_premissa` | quais premissas ESTE caso usa, com valor por ano (`jsonb`) |
| `caso_linha_premissa` | o vínculo linha↔premissa: **onde cada input entra na projeção** |

Separar catálogo de escolha é o que permite o catálogo crescer sem tocar em caso nenhum, e o caso
ser auditável sem depender do catálogo do futuro.

**A fronteira que os dois enums desenham:** `premissa_formula` (7 primitivas —
`crescimento_composto`, `pct_de_linha`, `dias_de_giro`, `valor_por_ano`, `preco_x_volume`,
`curva_mensal`, `indice_macro`) exige código novo no gerador; **premissa nova, não.**

**Como a linha é identificada:** por `(secao_canonica, rotulo_norm, entidade)`, **não** por
`campo_extraido.id` — aquele id morre a cada reextração, e a configuração de modelagem tem de
sobreviver a reenviar um arquivo. Índice de **expressão** com `coalesce(...,'')` porque em `unique`
normal NULL não colide com NULL, e duas configurações para a mesma linha passariam.

### O catálogo semeado

Base comum (30 premissas, `setores = '{}'`) + **20 setores**: indústria, varejo, serviços, agro,
construção, logística, saúde, energia, tecnologia, alimentos, educação, mineração, papel e celulose,
química, têxtil, automotivo, farma, telecom, hotelaria, imobiliário. **Sazonalidade está no catálogo
COMO premissa**, com natureza própria — o dono foi explícito, e ela muda caixa e necessidade de giro.

A descrição de cada premissa de setor diz **qual é a que manda** (a que o analista move primeiro):
SSS no varejo, produtividade × preço no agro, sinistralidade em saúde, churn em tecnologia, RevPAR
em hotelaria, produção do cliente em autopeças.

**Setor é sugestão, não restrição.** `fn_premissas_sugeridas(setor)` devolve base comum + as do
setor; `fn_vincular_linha_premissa` aceita **qualquer** premissa ativa. Em reestruturação o caso
atípico é a regra — há teste de que um caso de indústria pode usar RevPAR se o analista quiser.

### As guardas, e a que o teste descobriu

- **Premissa fora do catálogo é recusada** (recusa retornada, padrão das 0036/0037) — premissa nova
  entra por semente, não por caso.
- **Não se vincula linha a premissa que o caso não ativou.** Sem isso a linha sairia "projetada" por
  uma premissa sem valor nenhum — projetada com **zero**, que é a mesma armadilha do "SEM FOCUS" que
  o macro já combate. O motivo da recusa diz isso, em texto.
- **`fn_aplicar_premissa_em_lote` roda no BANCO**, não na tela: as linhas vêm de `campo_extraido`, e
  é ali que se sabe quais existem. Num balancete de 500 linhas, fazer isso no portal seria 500
  chamadas para uma decisão só. Devolve **quantas linhas pegou** — lote que pega zero não pode
  parecer sucesso.
- **`fn_conferir_modelagem` tinha um defeito que o teste pegou:** contava vínculos direto, e
  reprovou mostrando `linhas_com_premissa: 4` sobre `linhas_do_caso: 3`, com `linhas_sem_premissa`
  caindo a zero por subtração. Vínculo pode apontar para linha que não existe (configurada antes de
  o documento chegar, ou o arquivo foi reextraído com outro rótulo). Agora conta **por join**, e os
  órfãos ganham nome próprio no payload (`vinculos_orfaos`) — é a diferença entre "configurei" e
  "está coberto".

### Contadores

| Suíte | Antes | Agora |
|---|---|---|
| `node --test n8n/test/*.test.mjs` | 176 | **176** |
| `verificar-export.mts` | 397 | **397** |
| `db/test/run.sh` | 37 migrations | **38** + `premissas.test.sql` (28 asserts) |
| `test/e2e/run.mts` | 27 | **27** |

### Defeito religado

- guarda de premissa ativa desligada → `FALHOU: vincular a premissa não ativada no caso é recusado`,
  com o vínculo tendo sido criado;
- contagem sem o join → `FALHOU: conta como cobertas SÓ as que existem de fato`, mostrando
  `linhas_com_premissa: 4` e `linhas_sem_premissa: 0` sobre 3 linhas reais.

### O que vem

- **7.3** portal: `/casos/[id]/modelagem` — parâmetros, premissas do caso (catálogo filtrado pelo
  setor), **linhas × premissas com aplicar-em-lote**, e a conferência que `fn_conferir_modelagem`
  já devolve;
- **7.4** export completo: cabeçalho da Modelagem reduzido a 4 linhas, linhas do modelo passam a ser
  as do caso, projeção pelas 7 primitivas, e o completo respeitando o Portão 2;
- **Fase 6 (calibração)** depois.


## Sessão 25 (2026-08-03) — Fase 7.1: granularidade total e o export de dados

O dono interrompeu a Fase 6 (calibração) para acertar o **output**: "cada linha de cada documento
no excel, todos os valores, cada vírgula, cada tópico", premissas escolhidas no portal, e **dois
exports** — um só de dados e um completo com a modelagem. O plano inteiro (fases 7.1 a 7.4 + o
catálogo de premissas por setor) está no plano aprovado desta sessão. Esta é a 7.1.

### O achado: rótulo repetido COLAPSAVA

`bucket()` agrupava por `normalizar(campo.chave)` e `valorNumDoGrupo` devolvia `melhorCampo` — o de
maior confiança. Consequência: **duas linhas com o mesmo rótulo no mesmo documento viravam uma**, e
a outra desaparecia do arquivo. Num balancete com dois "Outros", duas "Diversos", ou "Fornecedores"
repetido em subgrupos diferentes, é perda silenciosa de linha **e de soma**.

A prova, ao religar o defeito: com três linhas (5.000 + 300 + 700) numa seção, o total saía
**5.300** em vez de 6.000. Note o formato da falha — o total continua *parecendo* consistente com o
que está visível, porque a linha que falta não está lá para contradizer. Não estava em nenhuma lista
de itens abertos.

**A correção:** a chave do grupo passa a incluir a **ocorrência** — o rank por `ordem`
(`db/migrations/0027`) dentro de cada versão e rótulo. Rótulo que aparece uma vez (a maioria) tem
rank 1 e se comporta como antes; repetido vira duas linhas, cada uma com sua proveniência. O rank é
por VERSÃO de propósito: num comparativo (2025 | 2024) a 1ª ocorrência de uma coluna alinha com a 1ª
da outra, que é o alinhamento entidade×período que o agrupamento por rótulo existe para garantir.

### Aba nova: `Dados (linha a linha)`

Espelho **1:1** do banco — uma linha de Excel por `campo_extraido`, ordenada por arquivo e pela
`ordem` do documento, com a proveniência inteira ao lado (arquivo, tipo, entidade, período, página,
ordem, seção, seção canônica, entidade/período da coluna, rótulo, valor texto, valor, escala, escala
original, **moeda**, confiança, aceite). Sem fórmula, sem template, com autofiltro.

Por que ela é diferente das abas classificadas: aquelas são uma **leitura** (agrupam, escolhem,
somam) — é o que as torna úteis para analisar e insuficientes para **conferir**. Não havia como
olhar a aba Balanço e saber se aquilo é tudo o que a extração trouxe. Agora há. Linha pendente de
aceite sai em itálico âmbar: nesta aba, mais que em qualquer outra, sugestão não pode parecer fato.

### Dois exports

`GET /casos/[id]/export?modo=dados` → todas as abas de dado, **sem Modelagem**; sem o parâmetro sai
o completo. Dois botões no dashboard, e o de dados **sempre disponível** (é insumo de conferência,
vale com pendência aberta). O nome do arquivo diz qual é (`-dados-` / `-completo-`): dois arquivos
com o mesmo nome na pasta de Downloads, um com modelo e outro sem, é confusão garantida.

**Um só builder, com um parâmetro** — não dois construtores. As abas de dado têm de ser idênticas
nos dois arquivos; dois caminhos divergiriam, e a divergência apareceria como "o número do completo
não bate com o de dados". Há assert comparando aba por aba.

**A Macro entra nos DOIS:** índice do BCB/IBGE é dado coletado, não modelagem — e foi exatamente uma
aba macro ausente que custou meia hora de investigação no v28.

### A fixture cobria 11 dos 14 documentos

Faltavam **DMPL, MUTUOS e NOTAS EXPLICATIVAS**. As abas `DMPL`/`Intragrupo`/`Outros` existiam no
código e **nenhum teste passava por elas com dado** — cobertura que parecia existir porque a fixture
afirmava os dois lados. Os três entraram em `db/test/gerar_fixture.py` com extração fiel ao que cada
PDF imprime:

- **DMPL** como matriz (`chave` = componente do PL, `secao` = movimento), sem inventar zero nas
  células que o PDF imprime como "-";
- **MUTUOS** com a divergência **deliberada de R$ 180 mil** contra o balanço — é o caso que a
  reconciliação existe para mostrar;
- **NOTAS** como prosa com números, com `secao` no formato "Nota 1"/"Nota 2" que
  `ehSecaoDeNotaExplicativa` reconhece. Há assert de que essas linhas **não** vão para o Balanço
  (nota detalha o que o BP já totaliza; somar as duas é dupla contagem vinda de complementar) e de
  que continuam no arquivo, na aba de dados crus.

O JSON da fixture passou a emitir `ordem` — sem ele a desambiguação de rótulo repetido não teria o
sinal de que depende.

### Contadores

| Suíte | Antes | Agora |
|---|---|---|
| `node --test n8n/test/*.test.mjs` | 176 | **176** (nada de lib mudou) |
| `verificar-export.mts` | 362 | **397** |
| `db/test/run.sh` | 37 migrations | **37** (nenhuma migration nesta fase) |
| `test/e2e/run.mts` | 27 | **27** |

Fixture: 11 → **14 documentos**, 744 → **767 linhas**.

### Defeito religado

- colapso de rótulo repetido de volta → `FALHOU: as DUAS linhas "Outros" aparecem — encontradas: 1`
  e `FALHOU: a soma da seção conta as duas — 5300`.

### O que vem (7.2 a 7.4, no plano aprovado)

- **7.2** banco: `premissa_catalogo` (o agregado por setor), `caso_modelagem`, `caso_premissa`,
  `caso_linha_premissa`, `fn_premissas_sugeridas(setor)`;
- **7.3** portal: `/casos/[id]/modelagem` — parâmetros, premissas do caso, **linhas × premissas com
  aplicar-em-lote**, conferência;
- **7.4** export completo: cabeçalho da Modelagem reduzido a 4 linhas (as 3-5 migram para o portal),
  linhas do modelo passam a ser as do caso, e o completo respeita o Portão 2.
- **Fase 6 (calibração)** fica depois disso, por decisão do dono.


## Sessão 24 (2026-08-03) — Fases 4 e 5: abas resolvidas, Portão 2 existe, roteiro do teste

O dono pediu as fases 4 e 5 juntas, e depois "1 vez a fase 6 de calibração" antes de testar na
prática. **Fase 3 (custo) foi PULADA por decisão dele** — consequência registrada no fim desta
seção.

### O achado desta sessão: o Portão 2 não existia

Fui conferir os "limites duros do Portão 2" (item da Fase 4) e encontrei o seguinte:

- `caso_status` tem `'aprovado'` e `'pronto_para_base'` desde a `0001` — e **nenhuma função
  transicionava** um caso para eles;
- **`pendencia.sobrepujavel` era gravado desde a `0001` e nunca lido por ninguém** (`grep`: só
  escrita). O flag que existe para dizer "nenhuma ressalva libera isto" não tinha consultante;
- não havia teto de ressalvas, nem conferência de expiração;
- `fn_aceitar_extracao` é o Portão 2 **por documento** (o comentário da `0011` diz isso). O portão
  **por caso** — o que decide se o mandato pode ser aprovado — não existia.

**Isso não estava em nenhuma lista de itens abertos** (nem no §7.4 do Onboarding), e a regra está
**especificada e aprovada em `f0/04` desde a F0**: três condições, teto de ressalvas **confirmado
em 3** pelo dono, lista fechada de não-sobrepujáveis. `docs/03` põe "Portão 2 com limites duros"
dentro do MVP. Então a `0037` implementa **a regra como ela está escrita**, sem inventar política.

`fn_avaliar_portao2` (só lê, `stable`) + `fn_aprovar_caso` (recusa retornada, mesmo padrão da
`0036`, pelo mesmo motivo: exceção desfaria o registro da tentativa). O portal mostra o portão com
os motivos e só oferece o botão quando a regra permite.

**Duas decisões de implementação que valem registro:**

1. **Ressalva expirada é avaliada NA LEITURA.** `f0/04` diz "ao expirar, a pendência reabre
   automaticamente". Reabrir por job seria a próxima falha silenciosa (job que ninguém observa);
   aqui uma `aceita_com_ressalva` com `expira_em` no passado **já conta como pendência de novo**,
   sem depender de cron nenhum estar vivo.
2. **Condição 3 usa estados DIFERENTES da condição 1 — e o teste é que descobriu.** A primeira
   versão copiou a lista `('aberta','em_correcao_interna','reenviada_ao_cliente')` para as duas.
   Resultado: mover uma **não-sobrepujável** para `aceita_com_ressalva` a tirava da contagem e **o
   portão liberava** — exatamente a porta dos fundos que a lista fechada existe para fechar, aberta
   na minha própria implementação por um copiar-e-colar de três valores de enum. Agora qualquer
   estado não-terminal conta: `aceita_com_ressalva` numa não-sobrepujável é **estado ilegítimo**,
   não caminho de saída.

### Fase 4 — a contradição das abas, resolvida

A Etapa 4 pedia auxiliares **ocultas**; no v28 o dono pediu o oposto ("quero todas as abas
juntas"), porque **aba oculta foi lida como dado ausente**. O §7.2 do Onboarding registra as duas.

As duas querem a mesma coisa: a Modelagem sendo o que se vê ao abrir, sem o resto parecer
inexistente. **Ordem entrega as duas; visibilidade só entregava uma** — quem recebe o arquivo não
sabe que há abas escondidas, e "reexibir é um clique" só vale para quem sabe que existe o que
reexibir. Agora: **Modelagem primeiro, nada oculto.**

**Armadilha do ExcelJS que custou um ciclo:** `workbook.worksheets` é um **getter** que devolve
`_worksheets.slice(1).sort(orderNo)` — um array descartável. A primeira versão fez `splice` nele e
**não mudou nada no arquivo**; o assert (11) pegou (`modelagem=9` depois de "mover para 0"). O
mecanismo real é `orderNo`, e `orderNo = 0` põe a aba à frente sem tocar no `orderNo` de ninguém.
`orderNo` existe no runtime mas **não nos tipos publicados** — daí o cast pontual, comentado.

### Fase 4 — o artefato para o dono olhar

Script novo: **`portal/scripts/gerar-export-fixture.mts`**. Grava em disco o `.xlsx` que o export
produz a partir da fixture do book sintético, usando o **mesmo** `buildExportWorkbook` que o portal
chama em produção. Custo zero, sem IA, sem banco. Data fixa (2026-07-27), como todo gerador daqui.

```bash
./portal/node_modules/.bin/tsx portal/scripts/gerar-export-fixture.mts /tmp/book.xlsx
```

### Fase 5 — o roteiro do teste ao vivo MÍNIMO (para quando o dono rodar)

O teste ao vivo é dele. O que esta sessão entrega é o roteiro, para a rodada **confirmar** em vez
de explorar — e para ninguém precisar reconstruir o raciocínio depois:

| # | Documento a enviar | O que exercita | Passou se |
|---|---|---|---|
| 1 | Uma **planilha de faturamento longa** (24–36 meses, CSV/XLSX) | Fase 1: teto de 2000 linhas e o aviso de truncamento | todas as linhas aparecem no book; nenhuma pendência de truncamento |
| 2 | Um documento **em moeda estrangeira** (ou com linhas em USD) | Fase 1: `campo_extraido.moeda` e a recusa de somar moedas | cabeçalho da coluna diz a moeda; coluna mista mostra "⚠ não somável" |
| 3 | **Reenvio do mesmo arquivo** do item 1 | `0026` (versão nova, não documento novo) | não duplica documento nem coluna no export |
| 4 | Um **.xlsx** qualquer (sem o Extract From File ligado) | Fase 1/2: XLSX não lido vira pendência + item `recebido_nao_valido` | pendência bloqueante e checklist âmbar, **não** verde |

Depois: conferir `fn_avaliar_portao2` do caso — com o item 4 no lote, ele **tem** de sair não
elegível, e o motivo tem de nomear a não-sobrepujável.

**Consequência de pular a Fase 3 (custo):** este teste custa hoje o mesmo que o v33 — duas chamadas
por documento, ambas em `gpt-4o`, com página como imagem. As três alavancas da Fase 3 (PDF como
texto, `gpt-4o-mini` na classificação, não pagar reprocessamento) estão desenhadas e não
implementadas. Se o orçamento estiver curto na hora de rodar, **fazer a Fase 3 antes é o que torna
esta rodada barata** — e o item 4 do roteiro (XLSX) só passa a ler o arquivo de verdade lá.

### Contadores

| Suíte | Antes | Agora |
|---|---|---|
| `node --test n8n/test/*.test.mjs` | 176 | **176** (nada de lib mudou) |
| `verificar-export.mts` | 361 | **362** |
| `db/test/run.sh` | 36 migrations | **37** + `portao2.test.sql` (24 asserts) |
| `test/e2e/run.mts` | 27 | **27** |

Nota honesta sobre o 362: os asserts de visibilidade das abas **mudaram de assunto**, não só de
número — três do comportamento antigo saíram, e entraram três do novo (nada oculto; Modelagem
primeiro; ordem relativa das auxiliares preservada). O `veryHidden` deixou de ter assert próprio
porque "nenhuma oculta" o cobre por construção.

### Defeito religado

- abas ocultas de novo → `FALHOU: NENHUMA aba fica oculta — ocultas: Resumo, Balanço, DRE, …`;
- condição 3 do Portão 2 com a lista de estados da condição 1 → `FALHOU: aceitar COM RESSALVA uma
  não-sobrepujável NÃO libera o portão`, com o payload mostrando `elegivel: true`.


## Sessão 23 (2026-08-03) — Fase 2: documento que chegou vazio para de contar

Itens **3 e 4** do §7.4 do Onboarding. O dono já aplicou a `0035` e reimportou o workflow da
Fase 1 antes desta sessão começar.

### O que o item #3 pedia, e por que a leitura literal não servia

O item diz: *"`completude_ok` só exige a linha do documento — 14 documentos com zero linhas
extraídas dão dashboard verde e book vazio."* A correção óbvia seria trocar a condição do Portão
1 por "existe documento COM linhas". **Duas coisas impedem, e as duas foram medidas no
repositório, não supostas:**

1. **Ordem do grafo.** `Registrar Documento` liga em **paralelo** para `Recomputar Completude` e
   para `Montar Req Extracao`. Quando a completude é calculada, a extração **ainda não rodou** —
   o número de linhas é zero para todo documento, sempre. A condição literal reprovaria o caso
   inteiro por um motivo que é só de sequência.
2. **Doutrina.** `docs/07` separa os dois status de propósito: *"Completude ≠ validade … para
   evitar falsa sensação de completude."* Colapsar as duas condições apagaria a distinção que
   existe justamente para impedir o que o item descreve.

**A 0036 usa o vocabulário que já existia**, em vez de redefinir o Portão 1:

- o documento continua **recebido** (a completude conta a chegada);
- o item vira **`recebido_nao_valido`** no `checklist_item_status` quando NENHUMA versão dele
  rendeu uma linha — a coluna já previa `invalido` desde a 0001;
- e abre pendência **`item_sem_conteudo`, BLOQUEANTE e NÃO-SOBREPUJÁVEL**, que é o que de fato
  trava o Portão 2 (`docs/07`: *"elegível ao Portão 2 se e somente se não há pendência bloqueante
  aberta"*, e a lista fechada inclui "arquivo ilegível de item essencial");
- **`fn_registrar_campos_extraidos` passa a recomputar a completude no fim** — é o único ponto do
  pipeline que roda com o resultado da extração na mão. Sem isso, o estado novo só apareceria
  quando alguém abrisse a fila de revisão, que é exatamente quem se está tentando avisar.
- o payload ganha `sem_conteudo` e **`pronto_para_revisao`** (= chegou tudo **E** tem conteúdo).
  `portao1_ok` continua significando "chegou tudo".

**No portal:** o Kit Básico tem **três** cores — verde só quando chegou e rendeu linha; **âmbar
"recebido, sem conteúdo extraído"**; e cinza para faltante. Âmbar e não "faltante" porque o
arquivo está lá: pedi-lo de novo ao cliente seria pedir o que ele mandou. A mensagem da tela do
documento também mudou: era *"Nenhuma linha extraída para este documento **ainda**"*, e o "ainda"
fazia parecer fila — quem lia esperava.

### Item #4 — o aceite formal de nada

`fn_aceitar_extracao` com zero campos não tocava nada (`v_n_aceitos = 0`) e **gravava, ainda
assim, uma `decisao` de tipo `aprovacao`**. Como `decisao` é append-only, esse registro — que faz
a trilha afirmar que um humano aprovou a extração daquele documento — não sai mais de lá.

- versão **sem nenhum campo** → recusa, com motivo que nomeia o arquivo e diz o que fazer;
- versão **com campos, todos já aceitos** → no-op declarado (`ja_estava_aceito`), sem `decisao`
  nova: antes, clicar duas vezes gravava **duas** aprovações.

**A recusa é RETORNADA, não `raise exception` — e a razão é técnica, descoberta pelo teste:**
exceção em plpgsql desfaz tudo o que a função fez, **inclusive o registro da tentativa em
`evento_auditoria`**. O primeiro rascunho levantava exceção, e o assert "a tentativa recusada fica
em evento_auditoria" reprovou. Postgres não tem transação autônoma: ou se tem a exceção, ou se tem
o rastro. Ficou o rastro, e `recusado: true` no payload para nenhum chamador confundir com sucesso
— **com a `actions.ts` do portal obrigada a ler esse campo**, senão a recusa passaria por sucesso
e trocaríamos "aceite de nada" por "sucesso de nada".

### Contadores

| Suíte | Antes | Agora |
|---|---|---|
| `node --test n8n/test/*.test.mjs` | 171 | **176** |
| `verificar-export.mts` | 361 | **361** (nada no export mudou) |
| `db/test/run.sh` | 35 migrations | **36** + `completude_conteudo.test.sql` (14 asserts) |
| `test/e2e/run.mts` | 27 | **27** |

### Defeito religado, um por um

- terceiro estado tirado da lib → **3 reprovações**;
- recomputação pós-extração removida da `0036` → `FALHOU: o item do checklist fica
  recebido_nao_valido, não presente — presente`;
- guarda do aceite removida → `FALHOU: a função declara a recusa no payload` devolvendo
  **`{"ja_estava_aceito": true, "n_campos_aceitos": 0}`** — isto é, sem a guarda o aceite do vazio
  responde **sucesso silencioso**, que é pior do que o diagnóstico original sugeria.

### O que fica para as próximas fases

- **#5** — poller de 12 min e recusa por estouro de orçamento visível só no log do n8n.
- **#6** — causa das 5 pré-condições que falharam no v33.
- **#7** — dupla contagem: decisão de doutrina, não correção silenciosa.
- **#8** — golden set físico, que bloqueia a F4 inteira.
- E a **fase de custo** (PDF como texto, `gpt-4o-mini` na classificação, não pagar
  reprocessamento), que também é o que permite pular a chamada do XLSX com um nó IF.


## Sessão 22 (2026-08-03) — Fase 1: os dois itens que perdiam dado em silêncio

O dono subiu no `main` o **`Onboarding`** (PDF de 67 páginas, commit `5edb89e`) e mandou usá-lo
como base para dividir o desenvolvimento em fases — **só a contextualização, do capítulo 1 ao 7;
o que é papel do estagiário, lista de documentos e banco de perguntas ficou fora por instrução
dele.**

### O §7.4 do Onboarding reordenou a prioridade — e eu estava errado

Eu tinha proposto começar pela dupla contagem. O §7.4 nomeia **8 itens abertos** e ordena por
risco/esforço: **itens 1 e 2 primeiro**, porque são os únicos que ainda **perdem ou corrompem
dado em silêncio**. A dupla contagem (item 7) **já é sinalizada no arquivo com as duas leituras
e não é corrigida automaticamente por doutrina** — corrigi-la calada seria violar a doutrina,
não cumprir o plano. Esta sessão fechou os itens **1 e 2**.

### Item 1 — truncamento de planilha (era 50 linhas)

`spreadsheetToText` cortava em **50 linhas × 25 colunas**. 50 é menos do que documento real tem:
faturamento de 24 meses × 5 entidades = 120 linhas; balancete analítico passa de 500. O resto ia
embora com uma nota **dentro do prompt** (`… (+N linhas omitidas)`) que só a IA lia — o banco
recebia a extração como completa e **nenhuma pendência existia**.

- Tetos agora **2000 × 60** (`MAX_LINHAS_PLANILHA`/`MAX_COLUNAS_PLANILHA`), que é ordem de
  grandeza de documento real. O teto continua existindo porque input é dinheiro.
- O que ainda passar do teto vira **`avisoTruncamentoPlanilha`** → `falha_motivo` → pendência
  `extracao_falhou` (a 0016 já fazia essa conversão; o que faltava era chegar lá).
- **Coluna pela UNIÃO das chaves**, não pelas da primeira linha: o "Extract From File" devolve
  objeto esparso, e célula vazia na linha 0 **apagava a coluna do documento inteiro**. Achado ao
  escrever o teste, não previsto no §7.4.
- **XLSX deixou de mentir:** o nó mandava a frase "(XLSX: habilitar Extract From File…)" **como
  se fosse o documento**, pagava a chamada e a pendência dizia que a *extração* falhou — não que
  o arquivo **nunca foi lido**. Agora o motivo real vira pendência. Pular a chamada exige nó IF
  (topologia = fase 3).
- O aviso **soma-se** ao motivo da chamada em vez de competir: planilha cortada **e** resposta
  truncada cabem no mesmo documento.

### Item 2 — moeda capturada e descartada (`db/migrations/0035`)

O caminho existia inteiro **menos o último metro**: o schema já pedia `moeda` à IA,
`normalizarMoeda` já convertia "US$"/"dolar" no ISO desde sempre, e o valor **morria no nó** —
nenhum campo o levava ao banco, porque **não havia coluna**. Com o erro de escala de ~496×
corrigido na Etapa 1, era o **último fator multiplicativo invisível**: dólar somado a real erra
**pelo câmbio inteiro** (~5x), num arquivo que fecha.

- **`campo_extraido.moeda`** (0035), herdada por linha pela **mesma regra da escala** — bloqueada
  em linha não-monetária, porque "margem 12%" com moeda BRL viraria doze reais.
- **Moeda desconhecida fica `null`, nunca BRL presumido.** Presumir é o mesmo erro com outra
  roupa.
- **`unidade` continua sendo a ESCALA.** O comentário da 0005 dizia `-- ex.: 'BRL', 'milhares'`,
  confundindo as duas numa coluna só; na prática sempre gravou escala. A 0035 **não migra nada** —
  separa as duas de agora em diante.
- **No book:** a moeda aparece no cabeçalho da coluna **quando discrimina** (mais de uma moeda no
  arquivo, ou coluna mista) — book todo em BRL não ganha "(BRL)" em cada coluna, porque rótulo
  redundante ensina a não ler o cabeçalho.
- **Coluna que mistura moedas NÃO recebe total.** Os 4 pontos de `SUM` passam por
  `escreverSomaOuRecusa`: a célula recebe "⚠ não somável" + nota nomeando as moedas. **Só a soma
  é recusada** — os valores individuais continuam todos visíveis. É a doutrina de sempre (mostrar
  as leituras, não consertar sozinho), sem a parte de emitir um número errado.

### Contadores (todos subiram, nenhum caiu)

| Suíte | Antes | Agora |
|---|---|---|
| `node --test n8n/test/*.test.mjs` | 162 | **171** |
| `verificar-export.mts` | 352 | **361** |
| `db/test/run.sh` | 34 migrations | **35** + `moeda.test.sql` (7 asserts) |
| `test/e2e/run.mts` | 24 | **27** |

### Cada correção teve o defeito RELIGADO para ver o teste reprovar

Não é formalidade — duas fixtures deste projeto nasceram vazias e passavam com o bug ligado.

- teto de volta a 50 → **3 reprovações**, incluindo o caso de 120 linhas fixas no teste;
- `moeda` fora do campo → **4 reprovações** na suíte n8n;
- `moeda` fora do insert da 0035 → **`ERROR: FALHOU: as duas linhas em USD gravaram moeda USD —
  esperado 2, veio 0`**;
- guarda do export desligada → **6 reprovações**, e a célula voltou a exibir `SUM(B4:B5)` = **7000
  somando BRL 5000 com USD 2000** — exatamente o total falso que a guarda existe para impedir.

### O Onboarding está desatualizado em dois pontos (decisão do dono)

O PDF foi gerado de um retrato **anterior ao merge dos PRs #70/#71**: o §7.2 e o §7.5 dizem que as
**Etapas 3 a 6 estão "Não iniciada"** e contam **33 migrations** com suítes de **160/273/18**. O
repositório diz outra coisa — as seis executadas na sessão 21, a Etapa 4 em
`portal/src/lib/export.ts`, e os contadores da tabela acima. **Não toquei no PDF**; corrigir esses
dois trechos e os contadores é decisão dele.

### O que fica para as próximas fases (do §7.4, na ordem que o Onboarding propõe)

- **#3 e #4** — `completude_ok` verde com book vazio e `fn_aceitar_extracao` aceitando versão com
  zero campos ("um aceite formal de nada"): **próxima fase**.
- **#5** — poller de 12 min e recusa por estouro de orçamento visível só no log do n8n.
- **#6** — causa das 5 pré-condições que falharam no v33, ainda desconhecida.
- **#7** — dupla contagem: **decisão de doutrina**, não correção silenciosa.
- **#8** — golden set físico, que é o que bloqueia a F4 inteira.


## Sessão 21 (2026-08-01) — Etapas 1 a 6, a partir do teste v35

O dono mandou o export do **v35** (o v34 tinha rodado com a API errada no nó da OpenAI) e pediu:
analisar, executar o que falta do plano de 6 etapas, e depois criticar a própria implementação.

### O v35 entregou a causa raiz de graça — a `0033` funcionou como projetada

A pendência dizia, literal: *"falta o Passivo+PL … Rótulos que a extração TROUXE e que poderiam ser
um total: "ATIVO", "Ativo Circulante", …, "PASSIVO E PATRIMÔNIO LÍQUIDO""*. Está tudo ali: **o
documento traz o total do grupo SEM a palavra "total"**, e a A.1 exigia o token. O rótulo certo
estava na base, com valor, e a busca não o via. É a convenção da maioria dos balanços brasileiros —
o classificador em TypeScript já sabia (`soEstrutural`); quem não sabia era o SQL.

**Segunda causa, no fallback:** `fn_soma_secao(['passivo','patrimonio'])` exige a SEÇÃO conter os
DOIS termos, e as seções reais são "Passivo Circulante" e "Patrimônio Líquido". O fallback era
**inalcançável desde que foi escrito**. → **`db/migrations/0034`**, com `fn_rotulo_estrutural`
(comparação por CONJUNTO, não substring) e duas somas que se juntam.

**E a guarda anti-alucinação acusava o balanço mais CORRETO possível:** "4 contas com o mesmo valor
material (14529)" eram ATIVO, TOTAL DO ATIVO, PASSIVO E PL e TOTAL DO PASSIVO E DO PL — iguais
**porque o balanço fecha**. Os totais de grupo saíram da contagem, usando o mesmo
`fn_rotulo_estrutural`.

### Etapa 3 — a Modelagem se basta (INVERSÃO da arquitetura da sessão 12)

Dois blocos no rodapé da Modelagem: **BASE DO MODELO** (números das demonstrações) e **BASE MACRO**
(espelho do histórico e do Focus, com as médias ainda em fórmula). Nenhuma fórmula da Modelagem cita
outra aba. O `INDEX/MATCH` permanece, agora local — é ele que mantém o dropdown de entidade vivo.

**O que se perde, e o arquivo diz:** a base é uma FOTO. Corrigir a aba Balanço não move mais o
modelo; tem de exportar de novo.

**Três armadilhas que custaram tempo:** (1) escrever o bloco antes do modelo cria as linhas 1..15 e
`addRow` passa a acrescentar DEPOIS — o modelo desce 15 linhas; (2) pôr o bloco em COLUNAS aumenta
`columnCount`, e o modelo é lido como "2 + nAnos × 13"; (3) `RefsMacro.prefixo` era o único ponto que
amarrava tudo à aba Macro — com ele vazio, todo o consumo virou local sem tocar no resto.

### Etapa 4 — auxiliares ocultas (reverte o v28), com guarda

`hidden`, nunca `veryHidden`. E se a Modelagem não existir, NADA é ocultado: um .xlsx sem aba visível
o Excel se recusa a abrir.

### Etapa 5 — o seletor, que nasceu DECORATIVO e foi consertado

Tabela de metodologias (Focus IPCA/IGP-M/Selic/PIB, médias 3a/5a/10a de IPCA e IGP-M, CAGR da
receita) nas colunas FY; a premissa a indexa. Acrescentar metodologia = acrescentar linha.

⚠️ **O seletor não movia nada, e só o invariante 40 pegou.** Trocar IPCA→IGP-M dava a MESMA receita
até a 12ª casa (43.776,1068). Causa aritmética: nominal = (1+índice)×(1+real) e real era
(1+observado)/(1+índice)−1 — **o índice cancelava**. Corrigido deflacionando pela metodologia
PADRÃO, não pela escolhida: o default fica idêntico e escolher IGP-M passa a valer o diferencial.

⚠️ **`N()` em toda leitura de premissa.** Com o seletor a premissa virou FÓRMULA, e fórmula que
devolve `""` NÃO é célula vazia: `(1+"")` é #VALUE! e contamina o modelo inteiro. `N("")` é 0.

### Etapa 6 — o modelo é RESOLVIDO, não inspecionado

**LibreOffice está quebrado neste container** (recusa um .xlsx mínimo de 3 células E o v35 que o dono
abriu no Excel). Então o avaliador do arnês foi estendido (INDEX/MATCH/IF/N/^/comparações/COUNT) e
**memoizado** — sem memória a avaliação é exponencial e 1.110 de 4.380 fórmulas davam "não sei".

**Resultado: 4.380 fórmulas, ZERO não resolvidas; as duas conferências fecham em 0,00 nos cinco
exercícios; Ativo = Passivo + PL bate nos cinco.**

### O CI achou um defeito no PRÓPRIO CI

`git diff --exit-code` reprovou por a janela do SGS vir de `new Date()`: o JSON mudava sozinho a cada
virada de mês, e o CI ficaria vermelho por não-motivo. Data de referência agora é fixa, com dois
testes prendendo a causa.

### Análise crítica da própria implementação (achado no artefato, não no código)

"Dado encontrado" dizia **"DRE+Balanço" para uma entidade sem DRE**, com receita zero ao lado. Duas
causas em sequência: checar só a COLUNA; e depois `ISNUMBER(INDEX(...))`, que é VERDADEIRO para
célula vazia porque **INDEX de vazio vale 0 no Excel**. O idioma correto é `COUNT(INDEX(...))`.

### ⚠️ PENDÊNCIAS DO DONO (sessão 21)

1. **Aplicar `db/migrations/0034`.**
2. **Reimportar `n8n/workflow.macro.json`** (a janela do SGS mudou de forma, não de valor).
3. **Validar as Etapas 1 a 6** — é o que o plano dele pede antes de qualquer coisa nova.

### O QUE FICOU ABERTO

Os cinco itens de "se sobrar fôlego" continuam **não tocados**: truncamento de CSV/XLSX em 50 linhas,
`moeda` capturada e descartada, `completude_ok` só exigindo a linha `documento`,
`fn_aceitar_extracao` aceitando versão vazia, e o poller que expira sem sinalizar.

**E dois limites conhecidos do que foi entregue:**
- A **BASE DO MODELO traz colunas de pseudo-entidades** do Combinado ("Eliminações — 2025"). São
  inofensivas (o dropdown de entidade as filtra) e auditáveis, mas são ruído.
- O avaliador do arnês lê **célula vazia como 0**, então `x=""` trata 0 e vazio igual. Para tudo que
  o export gera o resultado coincide; uma metodologia que rendesse exatamente 0,00% seria lida como
  ausente. Registrado no cabeçalho do arquivo.

### Armadilhas novas desta sessão

- **`$$` dentro de um COMENTÁRIO num bloco `do $$ … $$` FECHA o bloco.** O erro sai como
  "syntax error at or near" e não aponta o comentário.
- **`ISNUMBER(INDEX(...))` é verdadeiro para célula vazia** (INDEX de vazio = 0). Use `COUNT`.
- **Fórmula que devolve `""` não é célula vazia**: `(1+"")` é #VALUE!. Use `N()`.
- **Gerador que lê `new Date()` deixa o CI vermelho todo mês.**
- **LibreOffice não abre .xlsx neste container** — não é o arquivo, é o ambiente.

## Sessão 20 (2026-07-31, noite) — Etapa 2 FECHADA, dupla contagem sinalizada, e CI

Rodou sozinha, sem supervisão, a partir de `docs/PROMPT_CONTINUACAO.md`. Cinco frentes, todas
commitadas na branch acima.

### 1. Etapa 2 FECHADA — bloco "REFERÊNCIAS MACRO" na Modelagem (`a545c28`)

O placar que motivou, medido antes de escrever: das 15 premissas, **2** liam macro; das 6 séries
históricas, **0** alimentavam fórmula (as 18 células de média 3a/5a/10a não moviam nada).

Entrou o bloco que o dono aprovou: IGP-M, PIB e câmbio do Focus **por exercício** + as médias
3a/5a/10a por série, **tudo em fórmula lendo a aba Macro**, com nota dizendo a fonte, **o que a
linha deveria dirigir**, e que ela **não dirige nada hoje** porque o seletor é a Etapa 5. Cabeçalho
diz isso em linha visível: referência que parece premissa é pior que nenhuma.

**Duas armadilhas que o bloco teve de desarmar, e que a próxima sessão precisa conhecer:**
- **Câmbio é NÍVEL, não taxa.** O Focus publica câmbio em R$/US$ (5,40), as outras séries em % a.a..
  Dividir por 100 e formatar como % publicaria "5,4%" no lugar de "R$ 5,4000" — mesma família do
  erro de escala de ~496x da Etapa 1, e sem sinal nenhum na tela.
- **Célula de origem vazia vale 0 no Excel.** A média sem N exercícios completos fica LITERALMENTE
  vazia na aba Macro (fatia 3a, de propósito). Referência crua a ela publicaria "0,0%" como média de
  10 anos. Daí o `IF(origem="","",origem)` em cada uma das 18.

Invariante 35, 57 asserts. Não-vacuidade medida em 5 mutações.

### 2. Dupla contagem no total do grupo — o bug ABERTO mais caro, agora SINALIZADO (`37de0e5`)

**Reproduzi o arranjo real do v33** (Balanço da Componentes: 14.200 + 3.600 + 890 − 13.100 = 5.590,
com o 5.590 impresso): conta anotada com a seção de TOPO em vez da subseção cai em "Outros Ativos
Não Circulantes", irmã do Imobilizado, e o grupo a conta duas vezes.

O export agora escreve uma linha visível **nomeando a conta suspeita**, as duas seções e a diferença
medida, com nota trazendo **as duas leituras** — e **não corrige sozinho** (docs/04). Reportado UMA
vez, no grupo onde as duas seções são irmãs; repetir no ATIVO ensinaria o leitor a ignorar avisos.

**SOBRE A FIXTURE — leia antes de mexer.** A conta do v33 era "Ferramental e moldes" e ela NÃO serve
mais: a correção de vocabulário da sessão 18 (invariante 30) faz esse rótulo ser Imobilizado mesmo
sem seção declarada. MEDIDO:
```
classificarConta("balanco","Ativo Não Circulante","Ferramental e moldes",null) -> imobilizado
classificarConta("balanco","Ativo Não Circulante","Bens em comodato",null)     -> ativo_nao_circulante
```
A instância está fechada; a CLASSE não estava. A fixture usa "Bens em comodato" (conta de imobilizado
real, CPC 27, que o vocabulário genuinamente não reconhece), com a seção de TOPO declarada e a ordem
longe da vizinhança — que é o arranjo que a produção tinha.

**SEGUNDO DEFEITO, achado ao escrever o teste:** a marca de divergência no CABEÇALHO da seção
**nunca apareceu**. O cabeçalho é linha reservada e preenchida no fim com `row.fill = fill`, que no
ExcelJS repinta a linha inteira e apagava o destaque escrito antes. A pintura passou a ser adiada
(`pintarNoFim`) para depois de a aba inteira ser emitida. **Se você escrever destaque em célula de
cabeçalho de seção, use `pintarNoFim` — escrever direto não sobrevive.**

Invariante 36, 12 asserts, com contraprova. Não-vacuidade medida em 3 mutações.

### 3. Pré-condições de Ativo × Passivo+PL — `db/migrations/0033` (`1f95d62`)

**O que eu MEDI: a pré-condição NÃO é reproduzível pelo book.** Rodei a A.1 contra o book sintético
inteiro pelo arnês e2e (migrations reais, gravação pelas funções reais): as **7** entidades/períodos
dão `ok`. A falha do v33 veio do que a extração da OpenAI emitiu naquele lote, que não está
versionado aqui. **Não inventei fixture para "provar" uma causa que não tenho como medir.**

O que a `0033` entrega é a mensagem que teria dito a causa na hora: nomeia o LADO que faltou, o ano,
as colunas tentadas, e **LISTA os rótulos que a extração trouxe**. E, em qualquer resultado, declara
a ORIGEM dos dois lados (linha impressa × soma de seção do fallback) — porque "Ativo 158.801 vs
Passivo+PL 126.673" não diz se a divergência é do documento ou se uma seção não classificada sumiu
da soma, e são investigações diferentes.

**A lista de candidatos NÃO filtra por coluna, e isso é decisão medida.** Filtrar reproduziria o
defeito que se quer diagnosticar: quando a causa é o casamento de COLUNA (a família que a `0030`
corrigiu), o rótulo certo existe e some da lista. Escrevi a versão filtrada primeiro e o teste 7
reprovou com "nenhum rótulo … foi extraído" apesar de o rótulo existir — foi assim que apareceu.

**Nenhum critério de casamento foi afrouxado.** Alargar o `like` fabricaria um casamento.

Testes 6 (reescrito) e 7 (novo) em `db/test/reconciliacao.test.sql` — as duas condutas opostas que a
mensagem antiga não distinguia: "reextrair" × "mexer no padrão". Não-vacuidade medida trocando a
`0033` por `select 1;` e reconstruindo o banco.

### 4. CI (`75be07c`, `a7bfee5`) — e ele achou defeito na PRIMEIRA execução

`.github/workflows/suites.yml`: n8n, os três geradores **com `git diff --exit-code`**, export, db
contra serviço Postgres 16, e2e, tsc, eslint e `next build`. Em todo push e PR.

**A primeira execução real reprovou e achou dois defeitos, nenhum deles do workflow:**
1. **`verificar-export.mts` linha 810 tinha um CAMINHO ABSOLUTO** para o checkout de uma sessão
   (`/home/user/tratamento-dados-financeiros/...`). Os outros nove `readFileSync` do arquivo usam
   `new URL(..., import.meta.url)`. Funcionava por acidente — qualquer clone em outro diretório
   recebia ENOENT. **Nenhuma das quatro suítes pegaria isso**, porque todas rodavam no único
   diretório onde não dá erro.
2. **`npx tsx` baixa o tsx do registro mesmo com o `.bin` no PATH** ("package was not found and will
   be installed"). As suítes agora chamam `./portal/node_modules/.bin/tsx` por caminho, o binário
   pinado no lock. `tsx` entrou nas devDependencies do portal.

**CI VERIFICADO VERDE EM RUNNER REAL** (run `30668647822`, commit `a7bfee5`): os **14 passos**
passaram em 82 s, incluindo os que a primeira execução tinha pulado — `db/test/run.sh` contra o
serviço Postgres 16, o `e2e`, e o `next build`. Não é "o YAML é válido": é a coisa rodando.

### 5. Análise crítica da sessão 19 (`495ca68`) — pedido explícito do dono

**DEFEITO ENCONTRADO E CORRIGIDO: 12 meses NÃO bastam.** A `0032` fez a série de NÍVEL devolver
retorno NULL no primeiro exercício, mas `meses` continua 12 — e o export decidia "exercício completo"
olhando só `meses === 12`. O ano entrava em `completosDe`, a janela de 3 anos o NOMEAVA, e a média
virava `PRODUCT(1+B3/100, …)` com B3 resolvendo para `""` (a célula visível é
`IF(dados!X="","",dados!X)`, e **texto vazio não é célula vazia**: `""/100` é #VALUE!). A média 3a
saía **EM BRANCO com a nota afirmando "Média geométrica dos exercícios completos: 2023, 2024, 2025"**.
É alcançável, não teórico: basta a coleta do SGS começar em janeiro. Corrigido
(`meses === 12 && retorno != null`) + a nota do ano passa a dizer a causa. Invariante 37.

**AUDITADO E CORRETO, com a medição:**
- **`n8n/lib/hash.mjs`** — diferencial contra `node:crypto` em **619 casos**, todos idênticos: todos
  os comprimentos de 0 a 600, multi-bloco até 1.000.003 bytes, `Uint8Array` com **byteOffset
  não-zero** vindo de `subarray`, ArrayBuffer cru, Array comum, vetor da FIPS para entrada vazia.
  **Custo medido: 5 MB em 209 ms (23,9 MB/s)**; lote de 14 documentos de 5 MB = 2,9 s, contra dezenas
  de segundos de UMA chamada de IA. Irrelevante.
- **`0032`** — o recorte de leitura não muda o número. Medido com o filtro cortando exatamente o
  ano-base: sem filtro 2024 = 20,0000%; com `p_desde_ano=2024` → 20,0000%. Primeiro ano sai NULL.
- **Fatia 5** — não existe `spliceRows` nem `insertRow` em lugar nenhum do lib; todo `addRow` da aba
  Macro acontece antes do `return` que captura os endereços. Confirmado.
- **Fatia 4** — o vazio das premissas do Focus **não** produz #VALUE!: aquelas células são de verdade
  vazias, e vazio é 0 na aritmética do Excel. O único lugar onde "vazio" é `""` é a aba Macro — e é
  justamente ele que produziu o defeito acima.

**CORTE EM `export.ts`** (4.100 → 2.780 linhas). O acoplamento foi medido antes: exatamente **nove**
símbolos em comum, todos de apresentação → `export-estilo.ts` (38 linhas); o bloco Macro+Modelagem →
`export-modelagem.ts` (1.516). A condição "nenhum endereço de célula muda" foi **verificada, não
suposta**: dump completo do workbook (**7.485 células**, com valor, fórmula, formato, tamanho da nota
e preenchimento) gerado antes e depois — `diff` sem uma linha de diferença.

### ⚠️ PENDÊNCIAS DO DONO (sessão 20)

1. **Aplicar as migrations em ordem: `0032` (se ainda não aplicou) e `0033`.**
2. **Reimportar `n8n/workflow.e1-ingestao.json`** (hash em JS puro) **e `n8n/workflow.macro.json`**
   (`baseCalculo` do Focus) — continua pendente da sessão 19.
3. **Conferir o campo `hash` na saída de `Preparar Conteudo`** — tem de vir preenchido em qualquer
   sandbox. Se vier null de novo, o problema não é mais `crypto`.
4. **Validar a Etapa 2**, que agora está COMPLETA (é a regra dele: uma etapa por vez).

### O QUE FICOU ABERTO (nesta ordem, com o contexto detalhado mais abaixo)

1. **Truncamento de CSV/XLSX em 50 linhas antes de ir à IA** — faturamento de 24-36 meses perde o
   resto, em silêncio. **Não foi tocado.**
2. **`moeda` capturada e descartada** — não há coluna; USD indistinguível de BRL. Com o erro de
   escala corrigido, é o último fator multiplicativo invisível. **Não foi tocado.** (O bloco de
   REFERÊNCIAS MACRO agora ao menos NOMEIA isso na nota da linha do câmbio.)
3. **`completude_ok` só exige a linha `documento`** — 14 docs com zero linhas dão dashboard verde e
   book vazio. **Não foi tocado.**
4. **`fn_aceitar_extracao` aceita versão com zero campos.** **Não foi tocado.**
5. **Poller do upload expira em 12 min sem sinalizar**, e a recusa do orçamento só existe no log do
   n8n. **Não foi tocado.**

E a causa REAL das 5 pré-condições do v33 **continua desconhecida** — ver item 3 acima: a `0033`
garante que a PRÓXIMA ocorrência se explique, mas não explica a passada.

### Armadilhas novas desta sessão (além das que já estavam no fim deste arquivo)

- **`pintarNoFim`**: destaque escrito direto numa célula de cabeçalho de seção do Balanço é apagado
  pelo `row.fill = fill` que preenche a linha reservada depois. Use a lista adiada.
- **A aba Macro é o único lugar do export onde "vazio" é `""` e não célula vazia** — porque a célula
  visível é fórmula (`IF(dados!X="","",dados!X)`). Aritmética sobre isso é #VALUE!, não 0.
- **`npx tsx` baixa o tsx mesmo com o `.bin` no PATH.** Chame `./portal/node_modules/.bin/tsx`.
- **Caminho absoluto em teste passa despercebido para sempre** enquanto só existir um checkout. O CI
  é o que pega — e pegou na primeira execução.
- **Para medir não-vacuidade em SQL**: o `.test.sql` tem `ON_ERROR_STOP`, então a primeira falha
  aborta o resto. Para ver TODAS as falhas, neutralize os asserts já medidos um a um, ou rode blocos
  isolados contra um banco reconstruído com a migration trocada por `select 1;`.

## Sessão 19 (2026-07-31, tarde) — pendências do dono fechadas, Etapa 2 quase inteira (PR #69)

O dono voltou com as cinco pendências dele **resolvidas**, e uma das respostas virou trabalho:

1. PR #68 **mergeado** (o `main` está em `8109f2f`).
2. Migrations `0029`, `0030` e `0031` **aplicadas**.
3. Os dois workflows **reimportados**; **coleta macro confirmada** — o split do nó HTTP era real.
4. **`hash` veio NULL** → o sandbox de Code do n8n dele **não expõe `crypto`**. Virou fatia.
5. **RLS fica como está**: qualquer autenticado lê tudo; só time interno da Oria usa o portal.
   **Decisão registrada do dono — não reabrir sem ele pedir.**

### O que entrou no PR #69 (aberto, 4 commits)

- **`n8n/lib/hash.mjs` — SHA-256 em JS puro.** A abstenção anterior (`hash = null` quando não havia
  `crypto.subtle`) funcionou como projetada, mas o efeito era a idempotência da `0026` seguir
  **adormecida**: `p_hash is not null` nunca era verdade e todo reenvio duplicava o documento. Mesmo
  algoritmo (FIPS 180-4), zero dependência de ambiente; o caminho nativo ficou como atalho de
  velocidade. O harness de teste ganhou `semCrypto`, que sombreia o global dentro do corpo do nó —
  **o teste antigo passava verde com a produção quebrada** porque só exercitava o Node local.
- **Fatia 4 — Focus ausente virava 0,0% com nota afirmando procedência.** Agora a célula fica **em
  branco** (0 no Excel, mas lê como "falta preencher"), com **três camadas**: nota por exercício
  declarando a cobertura real, **linha VIVA** "cobertura do Focus" (a nota é da exportação; o
  exercício é input e a torna velha), e **aviso em linha visível** nomeando os anos e o efeito.
  `RefsMacro` passou a carregar a cobertura **por série** (o Focus publica horizontes diferentes por
  indicador).
- **Fatia 5 — o que degrada em silêncio passa a se declarar.** (a) falha PARCIAL do macro agora é
  escrita no topo da aba Macro — e a linha é escrita ANTES das outras, porque `spliceRows` depois do
  fato deslocaria a numeração que o modelo endereça por número; (b) `route.ts` NOMEIA a parte que
  falhou; (c) sem entidade reconhecida, a aba Modelagem **existe** dizendo a causa e para onde ir;
  (d) **Focus com `baseCalculo` fixado em 0** (a mediana dependia da ordem da resposta HTTP);
  (e) resíduos: `{ultimos:}`→`{mesesAtras:}` no seed, `$top` unificado em `FOCUS_TOP`.
- **Fatia 6a — `db/migrations/0032`: o câmbio perdia JANEIRO todo ano.** A base era `min(data_ref)`
  DENTRO do ano; agora é o último fechamento **anterior** ao ano (dez/n−1 → dez/n). Primeiro ano da
  série sai **NULL** (sem base não existe variação — e era aí que a versão antiga inventava uma).
  **A suíte protegia o bug**: `db/test/macro.test.sql` afirmava a convenção errada, corrigido junto.
  A migration tem verificação embutida e ela é **não-vazia**: com a base antiga religada, a própria
  migration se recusa a aplicar ("deveria ser 21%, veio 10").

**Todas as não-vacuidades foram MEDIDAS**, não estimadas: hash (1 reprova), fatia 4 (7), fatia 5 (3 +
o teste de `baseCalculo`, que testa as DUAS ordens de resposta), `0032` (a migration aborta).

### O que FALTA da Etapa 2 — uma coisa só, e o dono já decidiu como

**Bloco "REFERÊNCIAS MACRO" na Modelagem.** Medi o placar: das 15 premissas, **2** leem macro; das 6
séries históricas, **0** alimentam qualquer fórmula. Mas o modelo é dirigido por **percentual de
receita** (CPV = `RL × (1 − margem alvo)`, SG&A = `% da RL`), então **IGP-M, PIB e câmbio não têm
alavanca** hoje: trazê-los sem mais nada criaria mais células mortas, que é exatamente a crítica
registrada sobre as médias. Dar alavanca a eles é escolher qual índice corrige o quê — **isso é a
Etapa 5**.

**O dono escolheu (2026-07-31): bloco de REFERÊNCIA agora, seletor na Etapa 5.** Um bloco
"REFERÊNCIAS MACRO — não movem o modelo sozinhas" com IGP-M, PIB e câmbio do Focus **por exercício** e
as médias 3a/5a/10a, cada linha com nota dizendo o que ela **deveria** dirigir e que a escolha é o
seletor da Etapa 5.

**A infraestrutura já está pronta e commitada:** `RefsMacro` agora carrega `mediaDe`
(linha + colunas das médias, por série) e `janelasMedia`. Falta **só consumir** isso na
`construirAbaModelagem`. Onde colocar: **depois** da linha "cobertura do Focus", nunca no meio do
bloco de premissas — `P(i)` endereça premissa por deslocamento a partir de `rPremissas`, e uma linha
inserida no meio desloca todas as fórmulas do modelo em silêncio. A linha em branco depois das
premissas é o que ENCERRA o bloco para quem conta as 15 (invariante 15).

### ➡️ PRÓXIMA SESSÃO: `docs/PROMPT_CONTINUACAO.md`

O dono pediu um prompt único e auto-contido para a sessão seguinte rodar **de forma autônoma, sem
supervisão e sem fazer perguntas**. Ele está em **`docs/PROMPT_CONTINUACAO.md`** e cobre, em ordem:
fechar a Etapa 2 (bloco de REFERÊNCIAS MACRO), a dupla contagem no parente, as 5 pré-condições do
v33, montar CI, e uma **análise crítica do que a sessão 19 fez** (pedido explícito dele). Se este
handoff e aquele prompt divergirem, **este arquivo é a fonte da verdade** — o prompt é o roteiro.

### Armadilhas de execução da sessão 19 (não repetir)

- **`git checkout <arquivo>` apaga trabalho não commitado.** Usei para desfazer um patch de MEDIÇÃO
  de não-vacuidade e levei junto as mudanças legítimas do mesmo arquivo. Para medir: **copie o
  arquivo para o scratchpad e restaure com `cp`**, nunca com `git checkout`.
- **`sed -i '/marca/,$d'` depois de um `cat >>`** apaga o que você acabou de anexar (a marca estava
  ANTES do bloco novo). Para inserir antes do rodapé de um script, use Python com `str.index`.
- **O `verificar-export.mts` conta as premissas varrendo do cabeçalho "PREMISSAS" até a primeira
  linha vazia.** Qualquer linha nova adicionada logo depois do bloco entra na contagem e reprova os
  invariantes 14/15. A **linha em branco** é o que encerra o bloco — e ela é semanticamente certa:
  separa premissa (o que se digita) de conferência (o que o arquivo responde).
- **`spliceRows` na aba Macro quebra o modelo em silêncio**: `linhaCabFocus`/`linhaFocusDe` são
  números capturados na geração, e o INDEX/MATCH passa a apontar uma linha acima. Escreva avisos
  ANTES do resto da aba, nunca insira depois.
- **`test-data/book-vertentes/gerar.py` precisa de `PYTHONPATH=.`** e grava o `GABARITO.json` dentro
  de `pdf/`, não na raiz do diretório (a linha de uso do docstring está errada; o handoff anterior
  também dizia o lugar errado).
- **Não existe CI** — as quatro suítes só rodam quando alguém lembra. Continua sendo a alavanca mais
  barata contra regressão que existe neste repositório.

## ⚠️ COMECE AQUI — o 429 está RESOLVIDO; o plano agora é o do dono, etapa por etapa

**O 429 era TETO DE GASTO DO PROJETO na OpenAI** (`project_spend_limit_exceeded`), não crédito nem
cadência. O `neverError` da sessão 17 fez o corpo real da OpenAI chegar ao pipeline e a causa saiu
nomeada. O dono subiu o teto; o teste **v33 rodou os 14 documentos em 7m14s com sucesso**.

O dono definiu um plano de 6 etapas (estabilização → macro → automatizar modelagem → abas → seletor
de inputs → validação). **Regra dele: uma etapa por vez, e só avança depois da validação dele.**
O plano detalhado da etapa corrente vive em `/root/.claude/plans/` da sessão; se não existir, releia
esta seção e refaça.

### Etapa 1 — CONCLUÍDA e mergeada (PR #67, 7 fatias)

Não havia regressão: havia defeitos que rodavam sem erro e entregavam número errado. Os que mais
importam, todos com invariante e vacuidade medida:

- **A escala NUNCA era aplicada, em nenhuma aba.** `grep escala export.ts` dava zero. Balanço em
  milhar + fonte em unidade na mesma coluna = erro de **~496x**, sem uma marca. Corrigido no LIMITE
  DE NORMALIZAÇÃO (uma vez, na entrada), não célula por célula — assim `SUM`, AV%, indicadores e a
  Modelagem ficam certos sem serem tocados. **Confirmado em produção no v33: "20 linhas vinham em R$
  e foram convertidas".**
- **Conta de RESULTADO no Ativo Circulante:** `"mercadoria"` está em `ATIVO_CIRC_KW` (certo, é
  estoque), e por isso a top line da DRE era classificada ATIVAMENTE errada. `ehContaDeResultado`
  faz o classificador de balanço se ABSTER, e a abstenção reroteia para a DRE.
- **`0029`:** auto-aceite atropelava as guardas anti-fabricação (extração alucinada entrava como FATO
  ACEITO); extração vazia sem erro de API não gerava pendência; `extracao_falhou` nunca fechava;
  documento inexistente descartava o motivo da falha e a extração era PAGA.
- **`0030`:** entidade e período canônicos na ESCRITA. A duplicidade de entidade era **regressão do
  PR #65** (nome do arquivo sem acento × diagnóstico com acento).
- **`0031`** (no #68): o caixa estava na SEÇÃO e a reconciliação só olhava a chave.
- **Teto de gasto de US$ 3 por execução** em `n8n/lib/custo.mjs` + nó `Orcamento do Lote`.
- **`test/e2e/run.mts`:** a validação encadeada que não existia.

### Etapa 2 — EM ANDAMENTO (PR #68, 3 fatias de 6)

**A causa não era a que a etapa supunha.** RLS/GRANT estava fechado pela `0028`. Era a **COLETA**:

- **O nó HTTP do n8n EXPLODE resposta JSON que é array em N itens.** O SGS devolve 132 objetos e
  `Manter Contexto SGS` guardava `__corpo` = UM objeto ⇒ `!Array.isArray(corpo) continue` descartava
  **~792 itens das 6 séries mensais**. O ramo SIDRA já remontava o array; a assimetria era o sintoma.
  E ninguém viu porque o seed (920 obs) faz a aba **congelar** em vez de esvaziar.
- A coleta agora **falha alto** (zero nunca é legítimo: o SGS devolve 132 meses por chamada).
- **As médias 3a/5a/10a saíam em branco com 12 anos completos na base** — a janela era posicional e
  a última coluna é sempre o ano parcial. Agora nomeia os anos completos um a um.
- O último mirror manual (`numeroMacro` no Focus) passou a ser embutido por `toString()`.

**FALTA na Etapa 2** (fatias 4-6): Focus ausente vira **0,0% com nota afirmando procedência** (é o
defeito mais enganoso que resta); falha PARCIAL do macro descarta `macroErro`; sem entidade
reconhecida nem a aba de aviso é criada; **ligar IGP-M, PIB, câmbio e as médias às premissas** (o
dono decidiu que isso entra na Etapa 2 — hoje só 2 de 15 premissas leem macro); câmbio perde janeiro
todo ano (`0025:227`, e a fixture do teste CONSAGRA o erro); Focus sem filtro de `baseCalculo`.

### ABERTO e não resolvido — leia antes de mexer no Balanço

**Dupla contagem no total do grupo.** No v33, o Imobilizado usou o TOTAL INFORMADO (5.590, que já
inclui "Ferramental e moldes") e o Ferramental foi somado DE NOVO em "Outros Ativos Não Circulantes":
Ativo Não Circulante inflado em 3.600. O vocabulário foi corrigido, mas **a guarda no PARENTE
continua aberta**: sempre que uma conta de uma seção com total informado cai numa seção irmã, o grupo
conta duas vezes e nada detecta.

⚠️ **Duas fixtures minhas para provar isso nasceram VAZIAS** (passavam com o bug ligado): uma
declarava `secao` (e aí `subsecaoAutoritativa` já acertava), a outra tinha `ordem` entre contas do
Imobilizado (e o consenso de irmãos acertava). Fechar isso pede as linhas REAIS da extração do v33 —
não invente fixture, ela vai passar verde e te enganar.

**As 5 PRÉ-CONDIÇÃO de Ativo Total / Passivo+PL do v33 continuam.** A `0030` corrigiu o casamento de
COLUNA (combinado); estes são balanços individuais, onde o problema é o casamento de RÓTULO — caminho
diferente. E há uma DIVERGÊNCIA real (Ativo 158.801 vs Passivo+PL 126.673, diferença 32.128) que
pode ser a mesma família de dupla contagem.

 — o bloqueio de hoje é o 429 da OpenAI, e a causa dele NÃO está determinada

**O estado honesto, em uma frase:** no **teste v30** os **14 de 14** documentos falharam com HTTP 429,
e a resposta que chegou ao pipeline **não continha o corpo de erro da OpenAI** — então o código
classifica como `limite_indeterminado`, que é a verdade, e não como "cadência", que seria chute. Tudo
que a sessão 17 fez foi (a) tirar o chute da frente e (b) instrumentar para que a **próxima** execução
capture a causa real. **Não recomece inventando hipótese: leia §"Sessão 17" abaixo antes de agir.**

---

### PENDÊNCIAS DO DONO — as da sessão 18 estão TODAS fechadas (ver "Sessão 19")

As seis pendências anteriores (mergear o #68, aplicar `0029`-`0031`, reimportar os workflows,
confirmar a coleta macro, conferir o `hash`, decidir a lista de severidade) foram **respondidas pelo
dono em 2026-07-31**. O que ficou pendente dele agora:

1. **Aplicar `db/migrations/0032`** (câmbio) quando o PR #69 entrar.
2. **Reimportar `n8n/workflow.e1-ingestao.json`** (hash em JS puro) **e `n8n/workflow.macro.json`**
   (`baseCalculo` do Focus).
3. **Conferir de novo o campo `hash` na saída de `Preparar Conteudo`** — agora ele TEM de vir
   preenchido em qualquer sandbox. Se vier null outra vez, o problema não é mais `crypto`.
4. **Validar a Etapa 2** quando ela fechar (é a regra dele: uma etapa por vez).

### O PLANO DO DONO — 6 etapas, uma por vez

Regra dele, literal: *"Ao concluir uma etapa, aguarde minha validação antes de iniciar a seguinte"* e
*"não tente antecipar etapas futuras"*. Não avance sem o OK.

| Etapa | Objetivo | Estado |
|---|---|---|
| 1 | Estabilização da pipeline | **CONCLUÍDA** (PR #67) + correção pós-v33 no #68 |
| 2 | Dados macroeconômicos corretos na planilha | **COMPLETA** (sessão 20) — 3 fatias no #68, 3 no #69, o bloco de REFERÊNCIAS MACRO na sessão 20. **Aguardando validação do dono.** |
| 3 | Modelagem 100% automatizada, e **sem buscar valor de outras abas por fórmula** | **FEITA** (sessão 21) — aguardando validação |
| 4 | Todas as abas geradas; **auxiliares OCULTAS**, Modelagem visível | **FEITA** (sessão 21) — aguardando validação |
| 5 | **Seletor de inputs macro** (IPCA+, Selic, IGP-M, PIB, média histórica, CAGR) recalculando tudo | **FEITA** (sessão 21) — aguardando validação |
| 6 | Validação final ponta a ponta | **FEITA** (sessão 21) — modelo resolvido, conferências em zero |

⚠️ **A Etapa 4 CONTRADIZ uma decisão anterior do dono.** No teste v28 ele pediu explicitamente "quero
todas as abas juntas no exportável" porque abas ocultas leram como dado ausente, e o código hoje
**não oculta nada** de propósito (`export.ts`, comentário de `ABA_MACRO`). A Etapa 4 pede o oposto.
**Pergunte antes de ocultar** — pode ser que ele queira só a Modelagem em primeiro plano, não abas
escondidas.

⚠️ **A Etapa 3 pede que a Modelagem NÃO leia outras abas por fórmula** e receba os valores brutos já
preenchidos. Isso **desfaz** a arquitetura da sessão 12 (`INDEX/MATCH` contra as abas de dados, para a
planilha continuar viva: corrigiu a origem, o modelo acompanha). É uma troca real — perde-se o "vivo"
e ganha-se independência. **Confirme que é isso que ele quer** antes de reescrever.

### O QUE A ETAPA 2 AINDA DEVE — a lista abaixo está QUASE toda FEITA (sessão 19)

⚠️ **Não retrabalhe.** Cada item abaixo foi resolvido no PR #69, exceto o último. Mantido como
registro do que era o defeito, porque a descrição do defeito é o que explica o teste que ficou.

- ~~**Focus ausente vira 0,0% com nota AFIRMANDO procedência**~~ → **FEITO** (fatia 4). Célula em
  branco + nota por exercício + linha viva de cobertura + aviso visível. Invariantes 31 e 32.
- ~~**Falha PARCIAL do macro descarta `macroErro`**~~ → **FEITO** (fatia 5), declarado no topo da aba
  Macro, com a parte que falhou NOMEADA pelo `route.ts`. Invariante 33.
- ~~**Sem entidade reconhecida, nem a aba de aviso é criada**~~ → **FEITO** (fatia 5). Invariante 34.
- ~~**O câmbio perde JANEIRO todo ano**~~ e ~~**a fixture do teste CONSAGRA o erro**~~ → **FEITO**
  (fatia 6a, `db/migrations/0032`), os dois lados corrigidos na mesma fatia.
- ~~**Focus sem filtro de `baseCalculo`**~~ → **FEITO** (fatia 5): fixado em 0 (base de 30 dias, a da
  tabela principal do Boletim), na URL e no parse.
- ~~**Resíduos** (`{ultimos:}` × `{mesesAtras:}`, `top=40` × `top=80`)~~ → **FEITO** (fatia 5).
- **Ligar IGP-M, PIB, câmbio e as médias históricas às premissas** → **É O QUE FALTA.** O dono
  decidiu a forma: **bloco de REFERÊNCIAS MACRO agora, seletor na Etapa 5.** Ver a seção "Sessão 19"
  no topo — a infraestrutura (`RefsMacro.mediaDe`, `janelasMedia`) já está commitada e só falta
  consumir.

### PARA O DONO AVALIAR (média/baixa severidade — ele pediu que fosse trazido)

~~**O único que eu levantaria:** hoje toda policy é `for all to authenticated using (true)`~~ —
**DECIDIDO PELO DONO (2026-07-31): fica como está.** "Qualquer usuário pode visualizar, apenas o
pessoal interno da Oria vai ter acesso mesmo." Não reabrir sem ele pedir. O fato técnico continua
verdadeiro (não existe `caso_membro`, qualquer autenticado lê PII de sócios de qualquer mandato); o
que mudou é que é **risco aceito**, não pendência.

Perde dado de forma menos aguda: truncamento de CSV/XLSX em 50 linhas antes de ir à IA (faturamento de
24-36 meses perde o resto); `moeda` capturada e descartada (não há coluna — USD indistinguível de BRL);
`completude_ok` só exige a linha `documento` (14 docs com zero linhas ⇒ dashboard verde, book vazio);
`fn_aceitar_extracao` aceita versão com zero campos e grava decisão de aprovação; reconciliação A.1
pula anos em silêncio; `fn_valor_em_base` trata escala desconhecida como fator 1.

Atrito de uso: poller do upload expira em 12 min sem sinalizar nada — e a **recusa do orçamento** (o
`throw` do `Orcamento do Lote`) só existe no log do n8n, invisível para o dono; `status` compara nº de
arquivos com nº de linhas `documento` (com a `0026`, reenvio válido nunca fica "pronto"); fila não
pré-preenche a sugestão do diagnóstico; pendências de reconciliação/extração são listas só-leitura;
Kit Básico conta classificação não confirmada como "✓ presente"; upload sem `accept` nem validação de
tipo; parser de CSV ingênuo com aspas.

Exige n8n vivo: `.docx`/`.xlsx` via *Extract From File* (também a maior alavanca de custo, 60-80% do
input); chunking por página para `finish_reason=length`; confirmar se `retryOnFail` é decorativo com
`onError: continueRegularOutput`.

**Infra:** ~~não existe CI~~ → **RESOLVIDO na sessão 20** (`.github/workflows/suites.yml`). Ele achou
um defeito na primeira execução: caminho absoluto embutido no `verificar-export.mts`.

## Histórico: como o 429 foi diagnosticado (RESOLVIDO — mantido pelo método)

Fica aqui porque o **método** vale para o próximo mistério, não porque o problema esteja aberto.
A causa final foi `project_spend_limit_exceeded` — teto de gasto do PROJETO, invisível nas telas de
Billing e de Limits. Duas lições que se repetem: (1) uma frase de erro escrita pelo n8n em cima de
qualquer 429 não é evidência de cadência, e acreditar nela me fez subir o intervalo 6s→12s sem
evidência; (2) sem `neverError`, o corpo real da OpenAI nunca chega ao pipeline e o diagnóstico é
cego. Foi o `neverError` que fez a causa aparecer com nome no v31.

### O fato que refutou a hipótese mais fácil

O dono colou a saída do nó `OpenAI Extrair`. É **isto**, sem nada omitido:

```
message  Try spacing your requests out using the batching settings under 'Options'
name     AxiosError
stack    AxiosError: Request failed with status code 429 ...
code     ERR_BAD_REQUEST
status   429
```

Leia o que **não** está aí: nenhum `error.error`, nenhum `cause`, nenhum header de rate limit, nenhum
`insufficient_quota`. A frase do `message` é escrita pelo **próprio n8n** em cima de **qualquer** 429
(`HttpRequestV3.node.ts:850-853` sobrescreve `message`) — ela **não é evidência de cadência**, e foi
exatamente ela que me fez errar numa rodada anterior (subi o intervalo 6s→12s sem evidência; o 429
continuou). `ERR_BAD_REQUEST` é código de **transporte do axios**, não código da OpenAI.

Isso importa porque as causas de 429 pedem ações **OPOSTAS**: crédito esgotado → recarregar; **teto de
gasto** configurado → subir o teto (e ele **não aparece** nas telas de Billing nem de Limits); cota
diária → só reabre amanhã; **cadência** → o único caso em que espaçar resolve.

Backlog largo restante: **`docs/AUDITORIA_HARDENING_2026-07-24.md`** (45 findings priorizados, com
marcação do que já foi feito). Candidatos mais fortes agora, todos locais e testáveis aqui:

- ~~**Idempotência por hash + overload morto de 14 args**~~ e ~~**`reset-0006-regride-funcoes`**~~:
  **FEITOS na sessão 15** (`db/migrations/0026`, abaixo). O que sobrou dessa frente: **não PAGAR** a
  extração quando o arquivo é idêntico E a extração anterior usou o MESMO prompt/modelo. Exige (i)
  fingerprint de prompt+modelo gravado na versão e (ii) curto-circuito no grafo do N8N —
  `Montar Req Extracao` é `runOnceForEachItem` e não pode devolver zero itens; mudar o modo troca a
  resolução de contexto por item, a mesma classe de mudança que causou o bug do `itemIndex` fixo.
  **Fatia própria, com o N8N vivo do dono.**
- **`unidade-ignorada-em-abas-classificadas`:** a escala (`milhar`/`unidade`) é lida só nas abas de
  listagem simples; nas classificadas o `SUM` soma valor cru. Duas fontes em escalas diferentes na
  mesma coluna somam errado **em silêncio** — mínimo verificável: escala no cabeçalho da coluna +
  pintar divergência dentro da mesma coluna/aba.
- **`vocabulario-classificacao-contas-nao-classificadas`:** rótulos reais ("Receita de Vendas de
  Mercadorias" — a top line!, "Impostos sobre Vendas") caem em "Não Classificadas". Ampliar as listas
  de palavra-chave é aditivo e de baixo risco.
- **`periodo-fragmenta-e-quebra-reconciliacao`:** a referência de período é gravada CRUA, então o
  mesmo exercício em duas notações vira duas linhas em `periodo`. Canonicalizar no caminho de ESCRITA
  (a `0022` já canonicaliza na comparação).

## Sessão 18 (2026-07-31) — Etapa 1 completa + Etapa 2 começada; e dois invariantes MEUS nasceram vazios

Sessão longa, guiada pelo plano de 6 etapas do dono. Três PRs: **#67** (Etapa 1, 7 fatias, mergeado),
**#68** (Etapa 2, 3 fatias + correção pós-v33, aberto). O 429 foi resolvido no começo: era
`project_spend_limit_exceeded` — **teto de gasto do PROJETO**, invisível nas telas de Billing e de
Limits. O `neverError` da sessão 17 é que fez o corpo real da OpenAI chegar ao pipeline.

### O que o teste v33 provou (14 documentos, 7m14s, sucesso)

- **A escala funciona em produção:** o Resumo saiu com *"20 linha(s) vinham em R$ e foram convertidas"*.
  Era o mapa de dívida em reais somando com demonstrações em milhar — o erro de ~496x, evitado.
- Entidade preenchida em 14/14 (era `—` em todos no v31), 620 linhas, 14 abas visíveis.
- O teto de US$ 3 por execução não barrou o lote e não estourou.
- Renomear os arquivos para `12M25`/`L24M` eliminou a 2ª chamada `gpt-4o` por documento.

### O bug que o v33 revelou, e o que dele NÃO está fechado

No Balanço da Componentes: `Imobilizado = 5.590` (total informado, que **já inclui** "Ferramental e
moldes") e o Ferramental somado **de novo** em "Outros Ativos Não Circulantes" (3.600) ⇒ **Ativo Não
Circulante inflado em 3.600**, sem nada acusar no total do grupo. Confirmei no gabarito:
14.200 + 3.600 + 890 − 13.100 = 5.590.

Causa imediata: `IMOBILIZADO_KW` tinha `"ferramenta"` e o rótulo é `"Ferramental"` — o casamento por
token não aproxima. Corrigido (`ferramental`, `ferramentaria`, `molde`).

**NÃO FECHADO:** a guarda no PARENTE. Sempre que uma conta de uma seção com total informado cai numa
seção irmã, o grupo conta duas vezes e nada detecta. Ver "ABERTO" no topo.

### A lição mais cara da sessão: invariante vazio

**Duas fixtures minhas para provar a dupla contagem passaram verde COM O BUG LIGADO**, e eu só
descobri porque desliguei o fix e olhei:

1. Declarei `secao: "Imobilizado"` nas contas — com seção declarada, `subsecaoAutoritativa` já mandava
   o Ferramental ao lugar certo, independente do vocabulário.
2. Tirei a seção, mas deixei a `ordem` ENTRE contas do Imobilizado — o consenso de irmãos acertava
   sozinho, também sem depender do vocabulário.

Não consegui reconstruir o arranjo real da produção. Então o invariante que ficou afirma a
**classificação por rótulo** (4 asserts, provados não-vazios) e a dupla contagem ficou registrada como
aberta. **Se você for fechá-la: não invente fixture — ela passa verde e te engana. Use as linhas reais
da extração do v33.**

Mesma classe de erro em outro lugar: o invariante ANTIGO das médias macro exigia `COUNT(` na fórmula.
Ele travava o **mecanismo**, e o mecanismo era justamente o defeito — a faixa posicional. Invariante
que descreve *como* o código faz, em vez de *o que ele garante*, protege o bug.

### Armadilhas de execução que custaram tempo (não repetir)

- **Backtick dentro dos templates de código dos nós.** O gerador monta o `jsCode` como template
  literal, então um backtick num COMENTÁRIO fecha a string e o JS do nó sai quebrado — e o gerador
  não parseia, então só o teste pega. Aconteceu duas vezes.
- **Aspas simples em `'... e' resultado ...'`** dentro de string de nó: `e'` fecha a string.
- **Ordem de parâmetros:** `classificarConta(estrutura, secao, chave, secaoCanonica)` — estrutura
  PRIMEIRO; `classificarDemonstracao(secao, chave, secaoCanonica, estrutura)` — diferente.
- **`entidade` e `periodo` NÃO têm `criado_em`**; `periodo.tipo` é `text`, não enum; `caso` não tem
  `tipo_mandato`; `pendencia` usa `criada_em` (não `criado_em`).
- **`notaDaLinha` no harness precisa de `includeEmpty: true`** — nota de célula sem valor é pulada.
- **`avaliarCelula` NÃO segue referência entre abas.** Toda célula de ano da aba Macro é
  `IF('Macro (dados)'!X="","",…)`, então não dá para avaliar médias nem valores da Macro por ali. Foi
  o que me obrigou a trocar duas asserções por estruturais — com o motivo comentado no código.
- **`gerar_fixture.py` precisa de `PYTHONPATH=.`** (a linha de uso no docstring está errada).
- O `e2e` precisa de `E2E_PSQL="sudo -u postgres psql -h /tmp -p 5432"` por causa do peer auth.

### Uma regressão minha, corrigida na mesma sessão

O PR #65 fez a entidade sair do nome do arquivo — **sem acento**, porque `normalize.mjs` remove
diacríticos de propósito — enquanto o diagnóstico da IA traz `"Vertentes Metalúrgica Ltda."`. O
casamento no banco era `lower(razao_social)` ⇒ **duas entidades para a mesma empresa**. Corrigido na
`0030`, dos dois lados (escrita e `fn_coluna_entidade`). O export já mascarava o sintoma com
`consolidarNomesDeEntidade`, e é por isso que a duplicidade na base passou tanto tempo sem ser vista.

## Sessão 17 — Testes v29/v30: macro vazio por AUTORIZAÇÃO, e 429 sem causa conhecida (a causa saiu na sessão 18: teto de gasto do PROJETO)

Duas frentes. A primeira está **resolvida e mergeada**. A segunda está **instrumentada, não resolvida** —
e a distinção é o ponto mais importante desta seção.

### Frente 1 (RESOLVIDA, PR #61, `db/migrations/0028`) — "não veio os dados macro"

O dono aplicou a `0025`, ativou o workflow macro, rodou de novo, e as abas macro continuaram vazias.
A causa não era coleta: era **autorização**. A `0025` criou as tabelas `indice_macro_serie/obs/expectativa`
e a função `fn_indice_macro_anual` **sem RLS policy e sem grant** para `authenticated`. O portal lê com
a **anon key** + sessão do usuário, o que o Postgres vê como o papel `authenticated`. Dois efeitos, os
dois **silenciosos**:

- **RLS ligada sem policy devolve ZERO LINHAS** — não erro, não aviso. Zero.
- **função nova precisa de `grant execute ... to authenticated`** explícito no Supabase.

O n8n **não** era afetado (conecta por Postgres nativo via Session Pooler, fora do PostgREST), o que
explica o sintoma confuso: a coleta gravava, o portal não lia. A `0028` liga RLS com policy de leitura
e faz o grant, **com verificação embutida** que insere uma linha real e confere `COUNT(*)` já como
`authenticated`.

**O achado de método, que vale mais que a migration:** `db/test/run.sh` era **estruturalmente incapaz**
de pegar isso. Ele não replicava os privilégios default que o Supabase configura na criação do projeto,
então `set role authenticated` falharia para **qualquer** tabela — o teste acusaria falso positivo em
geral, e por isso ninguém testava como `authenticated`. O `run.sh` agora replica esse passo
(`grant usage on schema public`, `alter default privileges ... grant all on tables/sequences`) e
**deliberadamente NÃO** o lado de função — com comentário explicando que a abordagem de revogar execute
foi **medida** e não reproduz o comportamento do Supabase em Postgres puro. Sem isso, o próximo bug de
autorização passa igual.

Junto (PRs #59-#61): seed macro versionado com **920 observações reais** + 25 expectativas Focus (zero
divergências BCB×IBGE), correção da URL do BCB SGS (`ultimos/132` dava HTTP 400; série diária dava 406
→ passou a usar faixa de datas e a série 3698), e o export deixou de esconder abas — **todas visíveis**,
com aba de "sem dado" que declara o motivo em vez de sumir (o dono pediu explicitamente: "quero todas as
abas juntas no exportável").

### Frente 2 (NÃO RESOLVIDA — leia antes de mexer) — os 14/14 com 429 do v30

Cronologia, porque ela é o que impede repetir o erro:

1. **Rodada anterior:** subi o intervalo da extração de 6s → 12s supondo cadência. **Erro meu.** O 429
   continuou. Nenhuma evidência apoiava "cadência" — só a frase genérica do n8n.
2. **Esta sessão, hipótese:** o corpo de erro da OpenAI estaria em `error.error.error` (agentes leram o
   fonte do n8n e previram isso). Escrevi `diagnosticarErroApi` para cobrir esse caminho e vários outros.
3. **O dono colou a saída real do nó — e ela REFUTOU a previsão.** Não há corpo aninhado nenhum (ver o
   bloco em "COMECE AQUI"). Confirmei rodando: aquele payload exato classifica como
   `limite_indeterminado`, status 429, tipo `null`, código `null`.

**Conclusão que fica registrada como pendência, não como fato** (doutrina `docs/01`): a causa do v30 é
**desconhecida**. `limite_indeterminado` é a classificação honesta.

O que foi construído em cima disso:

- **`diagnosticarErroApi` (`n8n/lib/extract.mjs`)** — auto-contida de propósito, porque o gerador embute
  o `toString()` dela nos nós (Code node não importa arquivo). Emite causas com **ações diferentes**:
  `limite_de_gasto` (testado **primeiro**, porque tetos de projeto/org são invisíveis em Billing e
  Limits), `sem_credito`, `limite_diario`, `limite_cadencia`, `chave_invalida`, `modelo_indisponivel`,
  `limite_indeterminado`, `desconhecida`. Captura `x-ratelimit-*` e `retry-after` quando existem.
  **Terceiro mirror do repositório** (depois do prompt e dos ALIASES) — e os dois anteriores JÁ
  divergiram na prática, então há teste comparando nó × lib.
- **`neverError: true` nos dois nós OpenAI.** É o que faz a resposta 429 chegar ao parse **com o corpo
  da OpenAI** em vez de só o AxiosError. **É a instrumentação de que a próxima execução depende.**
- **Guarda contra pista falsa:** `ERR_BAD_REQUEST` (transporte axios) nunca é reportado como código da
  OpenAI — senão a sessão seguinte investigaria o campo errado. São **duas** guardas redundantes
  (uma em `CAMINHOS`, uma no cálculo de `codigo`) e **medi** que o teste só reprova com as **duas**
  removidas; está comentado no código para ninguém superestimar a cobertura.
- **A cadência agora é ARITMÉTICA, não opinião.** A OpenAI cobra do balde de TPM o **máximo** entre
  `max_tokens` e os tokens estimados do request — então cada extração **RESERVA** `MAX_OUTPUT_TOKENS`
  (16.384) por chamada, **independente do tamanho do PDF**. Logo:

  ```
  chamadas/min = TPM_CONTA / MAX_OUTPUT_TOKENS
  intervalo    = 60.000ms / chamadas por minuto
  ```

  No Tier 1 (30.000 TPM): 1,8 chamada/min → **32.768ms**. Os 12s que eu havia posto suportariam 5
  chamadas/min = **81.920 TPM**, quase **3× o teto do Tier 1** — ou seja, o lote de 14 documentos **não
  tinha como passar**, nem a 6s nem a 12s. `TPM_CONTA` vive em `lib/extract.mjs` (junto de
  `MAX_OUTPUT_TOKENS`) porque **três** lugares dependem do mesmo número — o gerador, o teste de cadência
  e o `diagnosticar-openai.mjs`; duplicado, o dono ajustaria um e os outros dois passariam a mentir.
- **`n8n/diagnosticar-openai.mjs`** — o experimento discriminante descrito em "COMECE AQUI". Já validado
  contra a API real (chave inválida → `chave_invalida`).

**Suspeita NÃO verificada, registrada como suspeita:** `retryOnFail` pode nunca disparar quando o nó tem
`onError: continueRegularOutput`. Se for verdade, `maxTries: 6` é decorativo nos nós OpenAI. Não medi.

### Ângulos ainda abertos nesta frente

1. **Consumo de tokens** — se a reserva de 16.384 por chamada é o que estoura o balde, reduzir
   `max_tokens` (ou cortar tokens de entrada, ver a fatia de *Extract From File*) vale mais que espaçar.
2. **Resiliência** — hoje uma 429 no meio do lote custa o documento; nada re-tenta o item depois de o
   balde reabrir.
3. **Observabilidade** — a pendência registra a causa, mas não há visão de "quantas 429 nesta execução".
4. **Modelo alternativo** para extração (TPM maior no mesmo tier).
5. **Comparar o banco de v29 × v30** — quantas linhas/documentos sobreviveram em cada, que é o que diz
   se algo além do 429 regrediu.

## Sessão 16 — Teste v28: aba ausente deixa de ser buraco silencioso

O dono mandou o `.xlsx` do v28 (14 documentos) com dois destaques: "os índices não vieram com os
dados" e "a aba de DRE não veio, e as demais abas também não vieram — quero todas as abas juntas".
As três causas são DIFERENTES, e **nenhuma era um número errado**: eram ausências indistinguíveis de
defeito. Também achei um defeito numérico que ninguém tinha pedido para procurar.

**Antes de tudo: havia uma SESSÃO PARALELA.** O `.xlsx` tinha uma aba Modelagem MENSAL que o código
que eu conhecia não produzia. O PR #57 (outra sessão, mesma conta) entrou entre o meu #56 e o #58 com
modelo mensal + **rollback da `0025`**. Lição registrada: quando o arquivo do dono não corresponde ao
código que você leu, o código errado é o SEU — confira `git ls-remote origin main` e a lista de PRs
antes de diagnosticar.

1. **"Os índices não vieram."** A `0025` foi aplicada no banco ERRADO e revertida (PR #57), então no
   projeto em uso as tabelas macro não existem. Sem dado, o export nem criava a aba — e aba ausente
   não distingue "coleta não rodou" de "defeito no export". Agora a aba **Macro existe sempre**,
   dizendo o que falta (aplicar a `0025` no projeto certo, ATIVAR o workflow — que roda dia 12 e não
   faz carga histórica sozinho) e **qual é o efeito** (as premissas de IPCA/Selic ficam em branco; dá
   para digitar por cima, mas aí o número é memória de quem digitou, não índice publicado).
2. **"A aba de DRE não veio."** A extração falhou: **429 da OpenAI**, junto com o Balanço da SPE — é
   por isso que também faltava a coluna da SPE. Agora Balanço/DRE/Fluxo **existem sempre**, e a aba
   sem dado **nomeia o arquivo** que chegou e não extraiu, distinguindo de "nenhum documento desta
   demonstração" (uma pede reprocessar, a outra pede cobrar o documento). O Resumo declara
   "Documentos SEM linha extraída: 2 de 14: …".
   **Na causa:** a cadência da extração foi separada da classificação (6s → 12s). O dado que decidiu:
   os dois que caíram são dois dos **menores** documentos do book — não foi o tamanho deles, foi o
   balde de TPM esvaziado pelos pesados que passaram antes. Quem esvazia o balde não é quem cai.
   Retry não resolve (o `waitBetweenTries` do N8N tem teto de 5s: 6 tentativas cabem na MESMA janela
   de TPM que acabou de recusar). Definitivo é gastar menos input — PDF como TEXTO, com o N8N vivo.
3. **"As demais abas não vieram."** Vieram: estavam **OCULTAS** (decisão do v27). Isso responde por si
   — aba oculta em arquivo de entrega lê-se como dado ausente. **Nada fica oculto agora**; a Modelagem
   continua sendo a aba ATIVA.

**O defeito numérico (não pedido):** a VT Logística saiu com **Ativo Circulante 7.254 onde o documento
diz 3.961** — "Contas a Receber" (3.293) somada JUNTO com "Fretes a receber" (3.562) e "(-) PECLD"
(−269), que são os componentes dela. O PDF **imprime** o total da seção, mas a extração daquele
arquivo não o trouxe, e **sem total informado não existe linha de checagem**: o número errado não
tinha como ser percebido. A detecção de subtotal depende de a extração anotar a SUBSEÇÃO em `secao`;
quando ela anota a seção de topo, passa.

> **PRÓXIMA FATIA, e é a mais valiosa que sobrou:** conserto de verdade exige a **ORDEM das linhas do
> documento** (o subtotal vem impresso ACIMA dos componentes — é assim que `render.py` do book e
> qualquer demonstração real imprimem). Ordem hoje **não é persistida**: `campo_extraido` não tem
> coluna de ordem e a query do export não ordena. Fatia = migration (`ordem int`) + n8n mandando o
> índice da linha + `.order("ordem")` na rota + detecção "subtotal seguido dos seus componentes" no
> export. Precisa de reprocessamento para valer no dado antigo.

Nesta rodada ficou o mínimo honesto: seção cujo número é a NOSSA soma (porque o documento não informou
o total) **carrega a ressalva na célula**, nomeando o risco de dupla contagem. Não conserta o número;
impede que ele passe por conferido.

**Conferido e OK no v28:** as 38 seções do Balanço das 4 empresas extraídas batem com o gabarito ao
centavo; consolidação de entidade funcionando (1 coluna por empresa, não 15); DMPL como matriz
correta; zero "Contas Não Classificadas"; notas explicativas fora das demonstrações.

**Ainda aberto na fila do dono** (reconciliação, não mexi): divergência de caixa com diferença de
**4.340.000** (é conversão de escala entre documentos em escalas diferentes); "Ativo 158.801 vs
Passivo+PL 150.232" no combinado; e o alerta de fabricação com **4 contas repetindo 14.529**, que é o
total do ativo da Componentes — vale conferir junto.

**Validação:** `verificar-export.mts` 105 → **113**; n8n **106**; `db/test/run.sh` 21+13+12;
`tsc`/`eslint`/`next build` limpos. Provados não-vazios (18a-18e, 19b-19c). **Três invariantes antigos
foram REESCRITOS em vez de deletados** — o 11 travava a ocultação, o 15 travava a aba oculta de dado
cru, e o 16h/16i usavam "a aba Balanço não existe" como proxy; cada um agora trava a intenção original
de outra forma. Teste que vira verde por deleção não protege nada.

## Sessão 15 — Reextração é versão nova, e substitui em vez de acumular (`db/migrations/0026`)

Veio de uma pergunta do dono: ele aplicou as migrations e reimportou os workflows, mas não entendeu a
pendência **"reextrair os documentos de DMPL/DVA já processados"**. Explicando, achei a armadilha —
**o caminho que eu tinha mandado ele seguir estava quebrado dos dois lados.**

**Reextrair é a única forma** de um documento já processado pegar prompt/taxonomia novos (migration e
prompt só valem para extração NOVA), e não existe botão de "reprocessar": reextrair é **reenviar o
mesmo arquivo no mesmo mandato**. Só que:

- **No banco:** `fn_registrar_documento` **nunca consultou o hash** — o comentário da `0004` dizia
  "idempotente-ish por hash", mas nenhum corpo (0004→0008) chegou a olhar. Todo reenvio inseria
  `documento` + `documento_versao` + `checklist_item_status` NOVOS: o mesmo arquivo virava dois
  documentos, duas linhas na fila, dois itens de checklist e colunas duplicadas da mesma empresa no
  export (o "15 colunas para 5 empresas" do v27 tem essa mesma família de causa).
- **No export:** ele lia **TODAS as versões** do documento. E duas extrações do mesmo arquivo não
  produzem as mesmas linhas — é o ponto de mudar o prompt. **Medi antes de escrever o fix:** com a
  conta renomeada entre as duas extrações, ela aparece DUAS vezes e a soma da seção somou as duas
  (1.000 + 1.500 = **2.500** onde o documento diz 1.500). Dupla contagem por um caminho novo, e do
  pior tipo: as duas linhas têm proveniência legítima, então nada parece errado ao abrir a planilha.

O que a fatia trava:

- **`(caso_id, hash)` → versão nova do MESMO documento** (`n_versao+1`), sem duplicar checklist nem
  pendência. **Hash nulo nunca casa**: dois desconhecidos não são o mesmo arquivo, e fundir documentos
  distintos é o erro mais caro que essa função pode cometer.
- **Máquina não sobrepõe humano.** Se alguém já revisou o documento na fila (`documento.fonte =
  'humano'`), a reextração não desfaz a correção — anti-ancoragem no sentido que importa aqui.
- **`versoesVigentes` no export: a mais recente COM DADO manda.** Não é "a mais recente", e a
  diferença é uma proteção real: reextração pode falhar e gravar `extracao_falhou` com ZERO linhas
  (`0016`); vigência cega ao dado APAGARIA do book tudo o que a versão anterior extraiu com sucesso.
  Trocar dupla contagem por perda silenciosa não é conserto. Empate sem `n_versao` declarada mantém as
  duas (chutar qual é a nova seria pior que o comportamento antigo).
- **Substituição declarada no Resumo** ("Linhas de versão substituída (fora deste export)") — a
  extração anterior continua no banco para auditoria, e o dono sabe que ela existe.
- **Overload morto de 14 args** (`fn-registrar-documento-overload-duplicado`) removido: ele ainda
  carregava o corpo da época da `0006` — sem `confianca`/`fonte`/`justificativa` e sem idempotência —
  e qualquer chamada posicional podia cair nele.
- **`reset-0006-regride-funcoes`** (armadilha de produção): o `db/README.md` mandava rodar a `0006`
  quando o N8N diz "function does not exist" — mas a `0006` recria os corpos DELA e regride tudo o que
  veio depois (sumiria a idempotência, as guardas `0013`/`0016`, o auto-aceite `0019`, e voltaria o
  overload morto). O aviso agora diz para continuar aplicando **0007 → 0026 em ordem** depois do reset.

**Validação:** `db/test/reextracao.test.sql` novo com **12 asserts**, incluindo os NEGATIVOS que
seguram a fronteira (hash diferente = documento próprio; hash nulo não casa; tipo revisado por humano
sobrevive). `verificar-export.mts` **79 → 85**. Provados não-vazios: sem a busca por hash, "mesmo hash
=> MESMO documento" falha; sem a vigência, 17a/17b/17c falham com `seção=2500 documento=1500` —
exatamente o número que eu havia medido. n8n 105/105, migrations 0001–**0026** limpas,
`tsc`/`eslint`/`next build` limpos.

**Precisa do dono:** aplicar a **`0026`**. Depois disso, reenviar o arquivo da DMPL no mesmo mandato é
seguro — vira versão 2 do mesmo documento e o export usa só ela. (Ainda **custa** uma extração; não
pagar exige a fatia do fingerprint + N8N vivo.) Alternativa sem custo, se o que importa é só a aba:
corrigir o **tipo** na fila de revisão — mas aí a matriz da DMPL pode sair achatada, porque as linhas
antigas foram extraídas sem o contrato `secao`=movimento / `chave`=componente.

## Sessão 14 — DF auditada: o conjunto num arquivo só é separado por demonstração

O `.xlsx` do próximo teste ainda não chegou. Rodei a suíte inteira primeiro (passo 1 do protocolo) —
verde de ponta a ponta: n8n 103/103, `verificar-export.mts` 69/69, `db/test/run.sh` 21 + 13 asserts
de macro, migrations 0001–0025 limpas, `tsc`/`eslint`/`next build` limpos — e ataquei o **único
`CRÍTICO` local que ainda restava** na auditoria (`df-auditada-bypassa-roteamento-linha`).

**O defeito.** Num mandato real o conjunto não chega em três arquivos: chega como **um PDF do
exercício** ("Demonstrações Contábeis 2025.pdf", "DF Auditadas 2025.pdf") com Balanço + DRE + DFC +
DMPL + **notas** dentro. Esse tipo (`DF_AUDITADA`) não pode ter aba própria — que aba seria? — e por
não estar em `ABA_POR_TIPO` caía em `"Outros"`, **onde o roteamento por linha nem rodava** (ele só
corria para documento de tipo estruturado). A entrega mais comum do cliente saía como listagem crua:
sem template, sem total de seção, sem AV%/Δ%, sem indicadores — e a aba **Modelagem** (que lê das abas
de demonstração) saía **zerada**. Mesmo padrão do achado central de v24/v25 e da sessão 11: com a
extração certa, o defeito está no nosso roteamento.

- **Duas portas para ser tratado como composto**, e a diferença entre elas é o que impede isto de
  virar dupla contagem: (a) o **tipo declara** o conjunto (`DF_AUDITADA`) — basta isso; (b) o
  documento **ainda não tem tipo** (nome que a taxonomia não reconhece, esperando a fila) — aí exige
  evidência **declarada** de duas demonstrações (`secao_canonica` de famílias diferentes). É o sinal
  que separa um conjunto de demonstrações de um **aging de recebíveis**, que é homogêneo.
- **Não se estende ao resto de "Outros"**, de propósito: aging, estoque, extrato, razão e notas
  **detalham** o que o balanço traz consolidado. Roteá-los somaria o detalhe DEBAIXO do total
  informado — a dupla contagem que o export levou três rodadas para eliminar. `ehSecaoDeNotaExplicativa`
  mantém a nota fora de qualquer demonstração **mesmo vindo dentro da DF auditada**; ela continua
  entregue, com proveniência, na listagem documental. (A regex exige "explicativa" ou um NÚMERO depois
  de "nota": "Notas promissórias a pagar" é conta legítima de passivo.)
- **Defeito meu, pego pelo invariante e não por leitura.** Sem estrutura própria para desambiguar, o
  fallback determinístico tenta **Fluxo primeiro** — e "Prejuízo líquido do exercício" é âncora da DRE
  **e** do Fluxo indireto. Resultado da primeira versão: a DRE inteira foi para a aba do Fluxo (Lucro
  Bruto 10.820 onde o documento diz 5.280; Fluxo operacional −41.175 onde diz 1.090). **Quem desempata
  é o próprio documento:** ele IMPRIME os blocos e a extração traz o cabeçalho em `secao`. A seção
  decide por **voto** das suas linhas, e a ordem de evidência virou: **o que a IA declarou para a
  linha → o bloco em que o documento a imprimiu → palavra-chave.**
- **DRIFT REAL no gerador**, achado ao ligar a ponta do intake: a cópia à mão de `ALIASES` em
  `build-workflow.mjs` **parava em `BALANCETE`**, então o nó que roda em PRODUÇÃO não conhecia
  `DF_AUDITADA`, `MAPA_DIVIDA`, `EXTRATO_BANCARIO`, `AGING_AR/AP`, `ESTOQUE`, `CERTIDOES`,
  `CONTINGENCIAS`, `SITUACAO_FISCAL`, `ORGANOGRAMA`, `RAZAO` nem `NOTAS_EXPL` — arquivos com esses
  nomes saíam do passe de nome **sem tipo**, que é justamente a chamada de IA que esse passe existe
  para evitar. Agora o gerador **importa** a lista de `lib/taxonomia.mjs` (fonte única, como já era com
  os enums e o prompt) e um teste compara as duas, **ordem inclusa** (a ordem é semântica: regra
  específica antes da genérica). Junto: `DF_AUDITADA` passou a reconhecer "demonstrações
  contábeis"/"demonstrações financeiras"/"DFs".
- **O que NÃO mexi, e por quê:** "Balanço Patrimonial DRE, DFC 2024.pdf" (arquivo real do dono) segue
  casando `FLUXO_CAIXA` pelo "dfc". Promovê-lo a `DF_AUDITADA` (complementar) tiraria dele a
  capacidade de satisfazer itens **obrigatórios** do Kit Básico e mudaria a completude de **todo caso
  já aberto** — decisão de produto do dono, não efeito colateral de uma fatia de export. E o
  roteamento por linha já separa esse arquivo aba por aba de qualquer jeito.

**Validação:** `verificar-export.mts` **69 → 79**; n8n **103 → 105**; `db/test/run.sh` 21 + 13;
migrations 0001–0025 limpas; `tsc`/`eslint`/`next build` limpos. Invariantes provados **não-vazios**:
desligando o roteamento composto a DF auditada volta a sair como `"Resumo, Outros"` (16a/16j falham e
8 checagens desaparecem); desligando a guarda de nota, as notas vazam para o Fluxo (16d/16e/16f);
mexendo em `ALIASES` sem regenerar, o anti-drift falha.

**Precisa do dono:** nada para o export. Para o passe de nome novo valer em produção, **reimportar**
`workflow.e1-ingestao.json`.

## Sessão 13 — Índices macro: histórico (BCB/IBGE) + Focus, e o modelo consumindo os dois

Pedido do dono: automatizar índices macro **validados e revisados**, com retorno médio de 3/5/10 anos,
e ligar isso à modelagem. `db/migrations/0025` + `n8n/workflow.macro.json` (workflow **separado**, roda
no relógio — falha dele não derruba a ingestão) + aba **Macro** no export.

**São duas coisas diferentes, e o modelo usa cada uma para o que ela serve:** `indice_macro_obs` é o
que **aconteceu** (série mensal publicada) e **calibra**; `indice_macro_expectativa` é o que o mercado
**espera** (Focus/BCB, por ano) e **projeta**. Média do passado não é previsão — projetar com ela é
dirigir pelo retrovisor, e era o caminho mais fácil de tomar ali.

- **Duas fontes para o mesmo número.** O IPCA é produzido pelo IBGE e espelhado pelo BCB; a observação
  é chaveada por `(serie, data_ref, FONTE)` para as duas coexistirem — sobrescrever uma com a outra
  destruiria a evidência que autoriza chamar o dado de conferido. `fn_divergencias_indice_macro`
  **aponta e não corrige** (não temos autoridade para decidir qual fonte está certa); tolerância de
  0,01 p.p. porque arredondamento de publicação não pode virar alerta semanal.
- **Composição, nunca soma nem média aritmética.** 12 meses de 1% dão 12,68%, não 12%; a média de 10%
  e 4% é 6,96%, não 7,00%. Vale no SQL, na lib e **na FÓRMULA da aba Macro** (`PRODUCT^(1/n)`, com
  teste **proibindo `AVERAGE`**). Série de **NÍVEL** (câmbio) varia entre fechamentos — compor nível
  seria erro conceitual, e por isso a natureza da série está no catálogo.
- **Ano incompleto não entra na média** (o corrente tem 5 meses): continua visível, com o nº de meses
  anotado, mas fora da janela.
- **Coleta no dia 12**, não no dia 1: o IBGE divulga o IPCA por volta do dia 10, e coletar antes faria
  a conferência acusar divergência todo mês por atraso de publicação.
- **Dois defeitos meus**, achados recalculando a planilha (não lendo o código): os anos do cabeçalho do
  Focus saíam como **TEXTO** e o `MATCH` do modelo compara com o exercício, que é **número** — nunca
  casava, o `IFERROR` devolvia 0 e a premissa de inflação aparecia **zerada sem nenhum sinal de erro**;
  e eu havia chamado de "necessidade de financiamento" o resíduo Ativo−Passivo−PL, que **não se move
  com premissa nenhuma** (um resultado pior derruba caixa e PL na mesma medida). A necessidade real é
  o **caixa negativo**: virou linha própria, e ela responde (14.249 → 20.803 com 50% de passivo
  oneroso).

**Validação:** n8n 86 → **103** (17 testes novos, com respostas REAIS das três APIs);
`verificar-export.mts` 57 → **69**; `db/test/macro.test.sql` com 13 asserts e **caso negativo em cada
checagem**. **Precisa do dono:** aplicar a `0025` e **importar `workflow.macro.json`** no N8N.

## Sessão 12 — Aba Modelagem: modelo pronto em fórmula + consolidação de entidade (v27)

Pedido do dono sobre o export do v27: uma aba de modelagem pronta para receber inputs, espelhando um
modelo de FP&A real, com a regra de que **tudo que não for input externo tem de ser FÓRMULA** puxando
das abas de dados — e as abas cruas ocultas ao final. Emenda registrada em `f0/07` (reabre o "output
não projeta"; é decisão do dono, e o que a emenda não afrouxa está escrito lá).

**Pré-requisito medido antes de construir: a base não estava consolidada.** O Balanço do v27 saiu com
**15 colunas de entidade** para 5 empresas, porque a mesma empresa chega por dois caminhos com grafias
diferentes (apelido da coluna do combinado × razão social do individual) e o mesmo exercício com dois
rótulos ("2025" × "31/12/2025"). Um modelo somando o grupo por cima disso conta cada empresa **duas
vezes** e fecha errado em silêncio. `consolidarNomesDeEntidade` promove o apelido à razão social **só
quando UMA ÚNICA** razão social do caso casa; ambíguo fica como está — fundir duas empresas diferentes
é pior que duas colunas. Balanço: 38 → 26 colunas, entidades 15 → 10.

**Quatro defeitos reais na revisão da própria aba, todos achados por teste:**

1. **PREMISSA MORTA** (o pior): as premissas eram escritas em todas as colunas, mas as fórmulas liam
   sempre `$C$n` — digitar a premissa do 2º ano projetado **não movia nada**. Agora a premissa é **por
   exercício** (coluna relativa), como um modelo de FP&A real.
2. **Modelo abria zerado.** As premissas nascem **derivadas do último exercício real, por fórmula,
   lendo as ABAS DE DADOS** (não as linhas do próprio modelo — isso fecharia **referência circular**).
   A célula continua input: digitar por cima sobrepõe.
3. **Balanço projetado não fechava**: não havia elo entre fluxo de caixa e ativo. O fluxo passou a vir
   ANTES do balanço e o caixa projetado entra no ativo circulante.
4. **Referência de coluna inteira** (`INDEX('Balanço'!$B:$BZ, …)`) — 77 colunas × 1M linhas por
   fórmula: derrubou por falta de memória um motor de fórmulas que abre a planilha inteira sem esforço.
   No Excel do usuário isso é a planilha "pensando" a cada digitação. Intervalos passaram a ser
   limitados ao tamanho real da aba.

Também: lista suspensa na célula de entidade, linha "Dado encontrado" (distingue "exercício sem
documento" de "entidade errada" — os dois davam o MESMO sintoma), sombreado das colunas projetadas por
formatação condicional, e "Dívida líquida / EBITDA" renomeada para "(Passivo total − caixa) / EBITDA"
(o export classifica por seção e **não isola dívida onerosa** — o nome anterior induziria a ler um
covenant que não é aquele).

**O invariante 14 é a tradução literal do critério do dono** ("alterar uma premissa tem de alterar o
modelo inteiro"): monta o **grafo de dependência** das fórmulas e exige que toda linha projetada
alcance as premissas **do seu exercício**, e que nenhuma premissa fique morta. Foi ele que pegou o
defeito 1. Recálculo de ponta a ponta com motor de fórmulas Excel: histórico bate com o gabarito
(Ativo 121.198 / 95.780) e a necessidade de financiamento dá **0,00** nas colunas reais.

## Sessão 11 — DMPL e DVA: código próprio na taxonomia e aba própria (`db/migrations/0024`)

O `.xlsx` do teste v26 ainda não chegou. Rodei a suíte inteira primeiro (passo 1 do protocolo) —
**verde de ponta a ponta**: n8n 83/83, `verificar-export.mts` 21/21, `db/test/run.sh` 21/21,
`tsc`/`eslint`/`next build` limpos — e ataquei a primeira fatia da lista de "diagnosticadas e não
feitas", que era a única inteiramente auto-contida (as outras duas exigem o N8N vivo ou são do
intake).

**O diagnóstico que importa: não era erro da IA nem do prompt.** A DMPL do book saía como `MUTUOS`
porque `tipo_sugerido` é um enum **fechado** nos códigos que EXISTEM na taxonomia
(`n8n/lib/openai.mjs` → `codigosConhecidos`) — sem código para DMPL, o modelo escolhe o vizinho mais
próximo. Mesmo padrão do achado central de v24/v25: **quando a extração está certa, o defeito está
no nosso vocabulário/agregação, não no modelo.**

- **`db/migrations/0024`** — DMPL e DVA como **complementares** (Nível 2). Não entram no Kit Básico:
  mexer na lista de 8 obrigatórios mudaria a completude de **todo caso já aberto**, e isso é decisão
  de produto do dono, não efeito colateral de uma migration de vocabulário.
- **Ordem dos aliases de nome importa e tem teste travando.** O caso comum de "DMPL" num nome de
  arquivo NÃO é a DMPL — é o PDF **composto** ("Balanço Patrimonial DRE, DFC, DMPL 2024.pdf", nome
  real do dono), em que o tipo é o da demonstração principal. Por isso DMPL/DVA vêm **depois** das
  principais em `n8n/lib/taxonomia.mjs`. (Nota honesta: esse arquivo hoje casa `FLUXO_CAIXA` pelo
  "dfc", comportamento anterior a esta fatia; o que o teste trava é que ele não vire DMPL — quem
  decide de fato é o diagnóstico por conteúdo.)
- **Roteamento por LINHA:** `SECAO_CANONICA_ENUM` ganhou `dmpl`/`dva`. Sem isso, a linha de uma DMPL
  embutida num PDF composto só tinha dois destinos, os dois ruins: `patrimonio_liquido` (o saldo de
  fechamento **repete** o total do PL — somá-lo INFLA o balanço, bug real do export do dono) ou
  `NAO_CLASSIFICAVEL`. A guarda `ehLinhaDMPL` continua, agora como rede de segurança e como
  fallback de roteamento para documento ANTIGO (sem `secao_canonica`), cedendo a vez quando o
  classificador do Fluxo reconhece a linha como saldo de caixa.
- **Aba DMPL = a MATRIZ** (linhas = movimentos do exercício, colunas = componentes do PL). Achatá-la
  numa listagem perderia justamente a leitura que a demonstração existe para dar. Isso exigiu um
  contrato no prompt: `secao` = movimento, `chave` = componente — e a **proibição explícita** de usar
  `entidade_coluna` para os componentes, que criaria uma "empresa" fantasma por componente no export.
- **Aba DVA sem template.** A DVA é padronizada pelo CPC 09, mas **não temos nenhum arquivo real
  para validar um template** — e template errado ordena o dado errado em silêncio. Sai o que o
  documento trouxe, na ordem dele, com a seção declarada em coluna própria. Quando aparecer uma DVA
  real, aí sim vale escrever a cascata.
- **Nada de subtotal calculado** em nenhuma das duas (anti-ancoragem, `f0/07`): a coluna "Total" da
  DMPL é a do documento, ou não existe.
- **Limpeza junto:** o separador de chave composta era um **byte NUL literal** no fonte de
  `export.ts` (caractere invisível). Virou a constante `CHAVE_SEP` — e o motivo não é cosmético: as
  chaves compostas novas que eu tinha escrito com espaço tinham exatamente a colisão que o NUL
  existe para evitar.

**Validação:** n8n **86/86** (3 testes novos); `verificar-export.mts` **34/34** (11 verificações
novas). Os invariantes novos foram **provados não-vazios**, como o protocolo exige: desligando o
roteamento por linha cai 1; desligando o mapa de abas caem 3 e somem 11. Migrations 0001–0024 limpas
em Postgres 16 local; `db/test/run.sh` 21/21; `tsc`/`eslint`/`next build` limpos.

**Precisa do dono:** aplicar a `0024`, **reimportar o workflow** (o enum de tipos e o prompt vivem no
JSON gerado) e **reextrair** os documentos de DMPL/DVA já processados — a regra de sempre: migration
e prompt só valem para extração NOVA.

## Sessão 10 — Teste v25: reconciliação sem ruído, export que fecha (PRs #49-#52)

Três rodadas encadeadas a partir do `.xlsx` do **teste v25** e do print da fila com **36 pendências
de reconciliação**. A lição transversal: **medir e reproduzir antes de mexer** — em duas das três
rodadas o que eu "sabia" estava errado.

### PR #50 — reconciliação: 36 pendências → 0 (`db/migrations/0023`)

Reproduzi as 36 num fixture de **extração fiel** dos 14 documentos (`db/test/gerar_fixture.py`, gerado
do próprio gerador do book) ANTES de mexer em qualquer linha. Deu exatamente 36 — o fixture é fiel.
A invariante que ele trava: **extração fiel não abre pendência nenhuma.** Cinco causas:

1. **Ausência de documento virava pendência** (20 das 36). O fato era VERDADEIRO — o book só tem DFC
   da Metalúrgica. Mas reconciliação não é o canal disso: documento que falta é cobrança do
   **checklist do Kit Básico** (`fn_recomputar_completude`), que já rastreia com estado próprio.
   Emitir aqui também duplica o sinal e enche a fila de itens que o humano **não tem como acionar** —
   não há correção a fazer, o arquivo não foi entregue. E escala com entidades × períodos × checagens.
   Agora a tentativa segue registrada em `reconciliacao` (auditoria intacta) sem abrir pendência.
2. **O COMBINADO não era aceito como balanço** (4 pendências "Nenhum Balanço classificado" para o
   grupo, sendo que o documento 06 É o balanço combinado dele). `fn_documento_balanco` aceita
   BALANCO → COMBINADO → BALANCETE.
3. **Coluna era ignorada.** `fn_valor_conceito` pegava `limit 1` na versão inteira: num comparativo
   isso compara o Ativo de um ano contra o Passivo de outro, e um desequilíbrio de 2024 passava
   batido. Novo `fn_valor_conceito_col` + `fn_coluna_entidade`/`fn_coluna_periodo_do_ano`, e a
   checagem roda **uma vez por ano declarado** — o comparativo agora é conferido nos dois.
4. **Total de seção sem linha de total** ("RECEITA OPERACIONAL BRUTA" é cabeçalho sem valor em
   demonstração BR). `fn_soma_secao` soma as contas-folha, excluindo o total da própria seção, as
   **seções irmãs** ("DEDUÇÕES DA RECEITA BRUTA" casa os mesmos termos) e as **âncoras de cascata**
   ("RECEITA OPERACIONAL LÍQUIDA" herda a `secao` do bloco anterior) — os dois só apareceram testando.
5. **Escala divergente recusava a comparação.** Com as duas escalas declaradas e conhecidas, converter
   é determinístico: `fn_fator_escala`/`fn_valor_em_base`. Recusa só escala ausente ou fora do
   vocabulário canônico.

Mais dois achados do próprio fixture: `fn_coluna_periodo_do_ano` distingue "documento sem coluna de
período" de "tem colunas mas nenhuma desse ano" (sem isso a DFC, que cobre só 2025, era comparada
contra o Disponível de **2024**); e a pendência é idempotente por período **compatível**, não igual,
porque a mesma checagem chega por dois documentos com granularidade diferente.

### PR #50 (2ª parte) — a dupla contagem do export NÃO estava corrigida

O invariante que escrevi no PR #48 passava verde enquanto **36 de 44 somas do Balanço divergiam**,
várias exatamente 2,00x — o fixture sintético não reproduzia os dois casos reais: a IA anotando a
seção de TOPO em vez da subseção, e o **mesmo rótulo sendo subtotal num documento e conta-folha em
outro** (o export junta os dois na mesma linha).

Correção que não depende de acertar a hierarquia: **quando o documento traz o total da seção, ELE é o
número da seção.** O cabeçalho aponta para a célula do valor extraído (`=<célula>`, fórmula — a
planilha segue viva e a proveniência fica a um clique) e a nossa soma vira `↳ soma das contas
listadas (checagem)`, pintada quando diverge. Errar a detecção passa a ser **ruído visível**, não
total silenciosamente errado — e AV%, Δ% e indicadores usam o número autoritativo.

### PR #52 — nenhuma linha 100% vazia, e categoria vem do documento

Pedido do dono. Medindo: 14 linhas sem valor em coluna nenhuma — nenhuma era falta de dado, era o
template emitido às cegas. **Princípio travado:** o template (CPC 26 / art. 178, cascata da DRE,
CPC 03) **ORDENA** o que o documento trouxe; nunca impõe linha que ele não tem nem inventa valor
(inclusive o `0` que nós escrevíamos quando o documento não disse *nada*).

Mas o que importava eram **dois defeitos escondidos atrás das linhas vazias**:

- **A cascata da DRE fechava em −27.550 onde o documento diz −17.901**: duas contas de Despesas
  Operacionais fora da seção, e a conta residual "Outras receitas (despesas) operacionais, líquidas"
  tratada como **A LINHA** de Receita Operacional Líquida.
- **No Fluxo, "Prejuízo líquido do exercício" era o Caixa Líquido das Atividades Operacionais** — a
  seção operacional saía sem o prejuízo, que é a primeira linha do método indireto (18.991 × 1.090).

Causa comum: a detecção de âncora recebia `secao + rótulo` juntos e casava por **conjunto de palavras,
sem ordem** — a conta herdava as palavras do cabeçalho e virava o total dele. Agora **âncora olha só o
rótulo** e tem de **parecer legenda de total** (`ehLegendaDeTotal`: não pode ser conta de detalhe
`(-) …`/`Outras …`/`Variação em …`, nem trazer muita palavra significativa além da legenda; palavras
de fraseado como "gerado pelas"/"aplicado nas"/"atividades" não contam — é assim que demonstração
brasileira escreve). E **a seção declarada pelo documento manda** na DRE e no Fluxo, como já era no
Balanço.

### PR #49 e #51 — housekeeping

#49 foi handoff. #51 reverteu `ca59311` ("Add files via upload"), 15 `.mp3` de outro projeto que o
dono subiu por engano na raiz. Os blobs seguem no histórico (revert não reescreve); apagar de vez
exige force-push no `main`, oferecido e não executado.

### Ferramentas novas que ficam

- **`db/test/run.sh`** — recria banco, aplica as 23 migrations, carrega o fixture do book e roda
  `db/test/reconciliacao.test.sql` (**21 asserts**). Cada checagem tem um caso **negativo** provando
  que ainda pega o erro real, e todos auto-resolvem quando o número é corrigido.
- **`portal/scripts/lib/avaliar-formula.mts`** — avaliador de `SUM`/refs/aritmética/`IFERROR`. Sem ele
  os invariantes mediam a coisa errada.
- **`verificar-export.mts` foi de 8 → 21 verificações**, incluindo dois end-to-end contra o
  `GABARITO.json`: as 60 seções do Balanço e a DRE 2025 linha a linha.

## Sessão 9 — Correções do teste v24 (PRs #47-#48)

Rodada curta e cirúrgica, disparada pelo `.xlsx` do **teste v24** (o primeiro rodado com o book
complexo). **Diagnóstico central: a extração estava excelente** — todos os "totais informados no
documento" batiam com o gabarito ao centavo (AC 67.878/45.440, PC 63.179, PNC 33.218, PL 24.801,
Ativo 121.198). O que estava quebrado eram **classificação e agregação**. Seis grupos de correção:

- **CRÍTICO — dupla contagem: todo total saía ~2x.** Demonstração real é hierárquica: sob "Ativo
  Circulante" vêm "Disponível", "Contas a Receber", "Estoques"…, **cada um com subtotal impresso**.
  Esses subtotais entravam no bucket como conta e o `SUM` da seção somava subtotal **+** componentes
  (`SUM(L4:L38) = 137.865` vs. informado `67.878`). Contaminava todo total, o AV% e todos os
  indicadores. **`detectarSubtotaisInformados`** (`portal/src/lib/export.ts`) reconhece o subtotal por
  dois sinais **estruturais do próprio documento** — (A) rótulo igual a uma `secao` que outras linhas
  declaram; (B) valor igual à soma dos irmãos da mesma seção **em todas as colunas com dado** — e o
  mantém **visível** (`↳ subtotal informado: X`), fora do range da soma. Não depende de vocabulário.
- **Conta sem vocabulário conhecido furava a soma.** A `secao` que a IA anota é o nome da
  **subseção** ("Estoques", "Outras Obrigações"), que não carrega sinal de Ativo/Passivo — "(-) PECLD"
  e "Produtos em elaboração" caíam em "Não Classificadas". Novo **passe de consenso de irmãos**: a
  linha herda a seção do agrupamento quando os irmãos são unânimes. Conservador por construção.
- **Conta no lado errado do balanço.** "Adiantamentos de clientes" (obrigação) ia pro **ATIVO** porque
  "cliente" é keyword de Contas a Receber e o ativo era testado primeiro. Pares ambíguos agora
  resolvem **antes** do passe genérico (`statement-templates.ts`): adiantamento+cliente, receita
  diferida, tributo a recolher/pagar.
- **Prefixo do nome do arquivo virando ano.** `13_Balancete_..._2025.pdf` saía como `multi 13,25`
  (o `13` virou 2013) em **4 dos 14 documentos** — fragmentava a tabela `periodo` e **impedia a
  reconciliação de casar documentos do mesmo exercício**. `parsePeriodo` (`n8n/lib/classifier.mjs` +
  espelho no `build-workflow.mjs`) descarta prefixo de ordenação, prioriza ano de 4 dígitos,
  entende `2025x2024`, ordena lista multi-ano.
- **`db/migrations/0022`** — três coisas: (a) **pendência de período falsa pela 3ª vez** — a
  comparação canônica da `0020` ainda acusava divergência entre o mesmo período em granularidades
  diferentes; agora compara **conjunto de anos** (`fn_anos_periodo`, `fn_periodos_equivalentes`,
  `fn_periodos_compativeis`) e só diverge quando os dois lados declaram anos e eles diferem; (b) **11
  pré-condições "documento ausente" com os documentos presentes** — as checagens casavam `periodo_id`
  **exato**; a tolerância teve de entrar **por lookup dentro de cada uma das 4 checagens**, não por
  checagem (tentar a checagem inteira com um período por vez nunca acha os dois lados, que podem estar
  em granularidades diferentes — essa foi a tentativa #1, que falhou); (c) **5 alertas falsos da
  guarda** de padrão suspeito — contava valor repetido no lote inteiro, e num combinado (5 empresas ×
  2 anos) valor pequeno coincide à toa; agora conta repetição **dentro da mesma coluna** e só em
  valores **materiais** (≥1% do maior do documento). Guarda que grita à toa é pior que guarda nenhuma.
- **Combinado: "Eliminações" e "Combinado" viravam empresa.** Ganhavam coluna de entidade e AV%
  calculado sobre coluna de ajuste. Agora são reconhecidas, **rotuladas** ("ajuste — não é entidade" /
  "total do documento — não somar com as demais"), vão pro fim e não recebem AV%/Δ%.

**Ferramenta nova que fica:** `portal/scripts/verificar-export.mts` (8 invariantes nesta sessão; 21
depois da sessão 10).
Validação da rodada: n8n **83/83**; migrations **0001–0022** limpas em Postgres 16 local com os
cenários do v24 exercitados (período equivalente → 0 pendências; divergência real 2025×2023 → 1;
reconciliação cross-granularidade → `ok`; guarda sem falso positivo mas ainda pegando fabricação
real); `verificar-export.mts` 8/8; `tsc`/`eslint`/`next build` limpos.

**PR #47** trouxe o gerador do book (`test-data/book-vertentes/`) e o handoff; **PR #48** as seis
correções acima. Ambos mergeados.

## Sessão 8 — Camada analítica + rodada de endurecimento (PRs #43-#46)

Partiu de dois pedidos do dono: (a) entregar a leitura analítica que um modelador espera pronta,
fundamentada na bibliografia que ele adicionou (`docs/Embasamento sobre Contabilidade`); (b) achar e
resolver TUDO que estava em aberto ou que quebra pela variação entre contratos. Uma **auditoria
multi-agente** produziu 45 findings priorizados, versionados em
**`docs/AUDITORIA_HARDENING_2026-07-24.md`** — é a fonte única do backlog restante, leia esse arquivo
antes de escolher o próximo passo.

- **PR #43 — camada analítica do export** (`f0/08_padrao_entrega_analitica.md` novo + emenda no
  `f0/07`): **AV%** (common-size: % do Ativo Total no Balanço, % da Receita Líquida na DRE), **Δ%**
  entre períodos comparáveis da mesma entidade, e bloco de **indicadores de liquidez/estrutura** no
  Balanço (Liquidez Corrente/Geral, Endividamento Geral, Composição do Endividamento, Participação de
  Capital de Terceiros, Imobilização do PL). Tudo em fórmula Excel com `IFERROR`; **nenhum índice é
  emitido sem o insumo real** (célula vazia, nunca estimada). Fundamentação: Fridson & Alvarez,
  Matarazzo/Assaf Neto, Penman, Schilit, Altman. O faseamento honesto do que ainda falta (liquidez
  seca, cobertura de juros, dívida líquida/EBITDA, ciclo de caixa, ROA/ROE, Altman Z'') está no `f0/08`.
- **PR #44 — período canônico + robustez de classificação**: `db/migrations/0020` (`fn_ano4`,
  `fn_periodo_canonico`) faz `fn_registrar_diagnostico` comparar período por **forma canônica** — o
  falso "PERÍODO PODE ESTAR INCORRETO" que o dono viu na fila (`2025-01-15` × `15/01/2025`, `2025` ×
  `12M25`) desapareceu, e as pendências falsas auto-resolvem. `formatarPeriodo` ficou robusto
  (`02,25` era exibido como "2002–2025"). Classificação: vocabulário muito ampliado, direção de
  empréstimo/mútuo ("concedido" → Ativo), `ehLinhaDMPL` restrito a data completa, agrupamento por
  conta normalizado.
- **PR #45 — prompt de extração endurecido + FONTE ÚNICA**: seção nova de **moeda/escala**
  (vocabulário fechado `unidade|milhar|milhao`; `moeda`/`unidade` eram `required` no schema mas o
  prompt não dizia nada sobre elas), **convenção de sinal e decimal BR** (parênteses = negativo;
  ponto é milhar), e **notação canônica de período na emissão**. O prompt tinha **três cópias que já
  haviam divergido** — o gerador agora importa `SYSTEM_PROMPT` de `lib/extract.mjs` e o embute
  literalmente; **dois testes travam isso** (nunca voltar a parafrasear).
- **PR #46 — escala por linha, Classe B com escala, ordem cronológica**: linha não-monetária (%,
  por ação, quantidade) **não herda** a escala do documento (`ehLinhaNaoMonetaria`) — evita
  mis-escala de 1000x, a custo zero de API; `db/migrations/0021` dá à **Classe B** a pré-condição de
  escala que a Classe A já tinha (comparava R$ mil contra R$ unidade); e o export passou a ordenar
  períodos **cronologicamente** (era alfabético: "Dez/2024" antes de "Jan/2024", o que fazia o **Δ%
  casar o par errado**) + colunas do mesmo período colapsadas.

**Custo (pergunta do dono "reduzir sem comprometer qualidade") — `docs/CUSTO_OPENAI.md`:** onde o
dinheiro vai (o PDF domina o input; output custa ~4x o input; documento mal nomeado paga o PDF duas
vezes) e as alavancas ranqueadas. Já feito: cache de prompt travado por teste (prefixo estático) e
`MODEL_CLASSIFICACAO`/`MODEL_EXTRACAO` como constantes (trocar o modelo da tarefa leve é uma linha).
As duas maiores alavancas — **PDF como texto em vez de imagem (60-80% do input)**, que o mesmo nó
resolve junto com o gap crítico de `.docx`/`.xlsx`, e **não enviar o PDF duas vezes** — exigem o N8N
vivo do dono e por isso NÃO foram implementadas às cegas.

**Book de teste novo (`test-data/book-vertentes/`):** gerador de um grupo fictício com 5 empresas em
distress severo (14 PDFs: balanços detalhados de 4 níveis, combinado com eliminações/MEP/participação
de não controladores, DRE/DFC/DMPL, faturamento 24M, mapa de dívida **em reais**, balancete D/C,
notas com going concern). Os números são **calculados e validados por assert** (balanço fecha em toda
entidade e no combinado; DRE amarra com a DMPL; DFC com o Disponível; faturamento com a receita).
Traz **10 armadilhas deliberadas** e um **gabarito**. O dono ia testar com ele e voltar com o
resultado — **se ele trouxer o resultado, é daí que a próxima rodada começa.**

## TL;DR pra quem está começando agora

O sistema é um pipeline de due diligence financeira: **N8N** (self-hosted) recebe upload →
classifica o tipo de documento → chama a **OpenAI** (multimodal) pra diagnosticar + extrair linha a
linha → grava no **Postgres/Supabase** → o **portal Next.js** (Vercel) mostra dashboard, fila de
revisão e exporta pra Excel. Princípio inegociável (`docs/01`): nada vira FATO sem aceite humano
explícito (anti-ancoragem) — a única exceção documentada é auto-aceite de linhas com confiança
extraída ≥95% (decisão explícita do dono, `db/migrations/0019`).

**O que está funcionando e testado** (kit de PDFs sintéticos + arquivos reais do dono):
classificação por tipo de documento, extração linha a linha com proveniência, classificação por
SEÇÃO contábil (Ativo Circulante, Despesas Operacionais etc. — `statement-templates.ts`), export em
Excel com FÓRMULAS (não valores estáticos), reconciliação Classe A/B, fila de revisão, auto-aceite
≥95%.

**Rodada de feedback do dono sobre o "teste v20" (PRs #39, #40, #41 — histórico, já mergeados):**
- **PR #39** (mergeado): fila de revisão com cards que não fechavam ao confirmar (`0018`); vazamento
  de linhas entre abas do export; `MUTUOS`/`FAT_INTRAGRUPO`/`CONTRATO_SOCIAL` sem aba própria
  fazendo sentido contábil; colunas técnicas demais nas abas simples (Faturamento/Dívida/...);
  auto-aceite ≥95% (`0019`).
- **PR #40** (mergeado): o dono perguntou por que o "total informado no documento" divergia do
  cálculo automático MESMO em arquivo de teste sintético — achamos **2 bugs reais de classificação**
  (não do arquivo de teste, de convenções comuns de demonstração brasileira): DRE contando um
  subtotal em cascata duas vezes, e cabeçalho combinado "Passivo e Patrimônio Líquido" jogando tudo
  pra Patrimônio Líquido. Ambos corrigidos em `statement-templates.ts`. Também: removida toda menção
  a tipo/versão de taxonomia da planilha, período padronizado (`formatarPeriodo`), notas de célula
  com fonte compacta + caixa ampliada via pós-processamento JSZip (ExcelJS não expõe isso).
- **PR #41** (mergeado): o `formatarTipoTaxonomia`/`formatarPeriodo` só rodavam no export em Excel —
  ligados também no dashboard, na planilha do documento e na fila de revisão (nada de código cru
  tipo "FATURAMENTO_24M" na tela); e o prompt de IA que gera o campo `resumo` do documento foi
  ajustado pra não repetir entidade/tipo/período (já aparecem em colunas próprias).

**Pendente agora — ver a seção "⚠️ COMECE AQUI" no topo deste arquivo.** Resumo: o dono aplica a
`0023`, a `0024` e a `0025` no Supabase, **reimporta** `workflow.e1-ingestao.json`, **importa**
`workflow.macro.json`, reextrai os DMPL/DVA já processados e manda o export novo. As fatias não feitas
são PDF-como-texto + `.docx`/`.xlsx` (exige o N8N vivo) e dois itens de resolução de entidade no
intake. Backlog largo em `docs/AUDITORIA_HARDENING_2026-07-24.md`; custo em `docs/CUSTO_OPENAI.md`.

**Além do export, já existem:** aba **Modelagem** (modelo de FP&A em fórmula, premissa por exercício —
sessão 12) e aba **Macro** (IPCA/Selic/câmbio: histórico do BCB/IBGE calibra, Focus projeta — sessão
13, `db/migrations/0025` + `n8n/workflow.macro.json`).

**Regra que vale pra qualquer reimportação/migration:** só afeta extrações **NOVAS** — documento já
extraído não muda retroativamente, precisa reextração explícita.

---

## 1. Estado atual

### Fundação (F0) — completa, mergeada
Todas as decisões estruturais estão travadas e documentadas em `f0/` (build vs. buy,
taxonomia v1, schema conceitual, spec de output, protocolo de golden set). Gate aberto
para a F1.

### F1 — Walking Skeleton

**Fatia 1 (E1 — Intake determinístico): construída, testada ao vivo, em produção.**
- N8N (self-hosted, PikaPods): Form Trigger → hash/integridade → classificação por
  nome+regras → fallback OpenAI (conteúdo, quando confiança baixa) → registro no
  Postgres → recomputa completude vs. Kit Básico.
- Confirmado rodando ponta a ponta com documentos reais (`BALANÇO ACUMULADO
  2025.pdf` e outros).
- **Portal (Vercel)** também construído e testado: login (Supabase Auth), dashboard
  do caso (checklist Kit Básico + lista de documentos), fila de revisão (humano
  confirma/corrige classificação).

**Fatia 2 (E2 — Extração de linhas financeiras): construída, rodando em N0 (sombra).**
- Mesma chamada da OpenAI (multimodal) já extrai linhas contábeis (rótulo + valor +
  página + confiança) e grava em `campo_extraido`. Nada disso é apresentado como fato
  ainda — é insumo para a reconciliação (Fatia 3).

**Diagnóstico de conteúdo (E1/E2) — construído e testado nesta sessão (feedback do dono:
"não está buscando a entidade e não está fazendo o diagnóstico/análise linha por linha").**
- Causa raiz: a IA só lia o CONTEÚDO do documento no fallback de baixa confiança do
  classificador por nome — como a maioria dos arquivos bem nomeados já batia confiança alta,
  o fallback quase nunca rodava, e só ele buscava entidade. Fix: a chamada que **já rodava
  sempre** (extração E2) passou a devolver, na MESMA chamada (não aumenta o nº de chamadas à
  OpenAI): um bloco `diagnostico` (entidade; confere tipo/período do nome contra o conteúdo
  real; legibilidade real do arquivo — antes hardcoded `'ok'`; resumo objetivo) + linhas
  extraídas com `secao` (agrupador que espelha a estrutura do documento — Ativo Circulante,
  Passivo Não Circulante, PL, etc. — a "planilha organizada" pedida pelo dono).
- `db/migrations/0010_diagnostico_e1e2.sql`: colunas novas (`campo_extraido.secao`,
  `documento.resumo`, `documento_versao.nota_legibilidade`) + `fn_registrar_diagnostico` —
  preenche `entidade` só quando ainda vazia (nunca sobrescreve), gera `pendencia` tipada
  (`tipo_incorreto`/`periodo_incorreto`/`entidade_incorreta`/`arquivo_ilegivel`) quando o
  conteúdo diverge do já registrado, idempotente (reaproveita pendência aberta) e auto-resolve
  quando a divergência some (ex.: humano já corrigiu na fila de revisão).
- N8N: novo node `Registrar Diagnostico` entre `Gravar Campos (Sombra)` e `Reconciliar (Classe
  A)` — roda antes da reconciliação de propósito, para ela já enxergar a entidade recém-
  preenchida. 53/53 testes (`workflow-sim` + `extract`) passando.
- Portal: nova rota `/casos/[id]/documentos/[docId]` — mostra a "planilha" (linhas agrupadas
  por seção, com valores formatados) + resumo + aviso de legibilidade ruim; dashboard do caso
  ganhou link "ver linhas →" por documento, badge de legibilidade, coluna de resumo, e uma
  seção "Qualidade dos arquivos" (pendências `arquivo_ilegivel`); fila de revisão ampliada para
  aceitar também `tipo_incorreto`/`entidade_incorreta`/`periodo_incorreto` (reaproveita
  `fn_revisar_documento`, que já corrige os três juntos — nenhuma UI nova precisou ser criada
  para isso).
- Testado contra Postgres 16 local (entidade nova, entidade conflitante + correção humana +
  auto-resolução, tipo/período divergente, arquivo ilegível, idempotência, integração completa
  com a reconciliação Classe A). **Confirmado rodando ao vivo no N8N/Supabase real do dono**
  (2026-07-21, depois de aplicar a migration `0010` que faltava — `Registrar Diagnostico`
  executou e achou a entidade certinho).

**Fatia 3 (E3 — Reconciliação): Classe A construída e testada (ainda não em produção real).**
- Dono escolheu começar direto pela Classe A (checagens aritméticas determinísticas), sem
  plano detalhado prévio.
- `db/migrations/0009_reconciliacao_e3.sql`: tabela `reconciliacao` (log append-only de cada
  checagem) + `fn_valor_conceito` (casa `campo_extraido.chave` — texto livre da IA — com um
  conceito canônico via termos obrigatórios/excludentes normalizados, sem LLM) + as duas
  checagens canônicas de `docs/04`: `fn_reconciliar_ativo_passivo_pl` (Ativo = Passivo + PL no
  Balanço; tenta a linha combinada "Total do Passivo e do PL" primeiro, senão soma Passivo +
  PL separados) e `fn_reconciliar_caixa_bp_fluxo` (Caixa do Balanço vs. saldo final do Fluxo de
  Caixa; **aborta se as unidades divergirem** — ex. "R$" vs "R$ mil" — em vez de comparar
  números incompatíveis). `fn_reconciliar_por_documento(documento_id)` é o ponto de entrada
  único chamado pelo N8N.
- Testado de ponta a ponta contra um Postgres 16 local efêmero (migrations 0001-0009 completas):
  checagem batendo, divergência real, documento faltante (precondição), unidades divergentes
  (precondição), auto-resolução de pendência quando a divergência some numa reextração, e
  idempotência (rodar a mesma checagem 2x não duplica pendência — reaproveita pela chave
  `motivo = 'reconciliacao:<tipo>'`).
- N8N: novo node `Reconciliar (Classe A)` no fim do fluxo (depois de `Gravar Campos (Sombra)`),
  chama `fn_reconciliar_por_documento` com o `documento_id` de `Registrar Documento`. 51/51
  testes do `workflow-sim` continuam passando.
- Portal: dashboard do caso (`portal/src/app/casos/[id]/page.tsx`) ganhou seção "Reconciliação
  (Classe A)" listando as pendências abertas de divergência/precondição — **só leitura**, ainda
  não tem uma ação de "confirmar/resolver" dedicada (usa o motor de pendências genérico).
- Opera em **N1** (doutrina): toda checagem gera `pendencia` tipada (`divergencia_reconciliacao`
  ou `precondicao_nao_satisfeita`), nunca escreve um número como fato aceito.
- **Confirmado rodando ao vivo no N8N/Supabase real do dono** (2026-07-21, mesma sessão da
  migration `0010` faltante — depois de aplicar a `0009`, `Reconciliar (Classe A)` executou).

**Fatia 4 (E4 — Output + Portão 2): primeira fatia construída e testada nesta sessão (pedido
direto do dono: "quero que seja extraído para o Excel em um modelo pronto para análise").**
- `db/migrations/0011_aceite_export_e4.sql`: Portão 2 **mínimo** — até aqui `campo_extraido`
  não tinha NENHUM mecanismo de aceite humano, o que violaria o princípio inegociável de
  `f0/07_output_spec.md` ("nenhum número entra no export sem uma `decisao` de aceite humano
  ligada") se o export saísse direto da sombra. `fn_aceitar_extracao(documento_versao_id,
  autor, motivo)` aceita **todas as linhas de uma versão de documento de uma vez** (granularidade
  v0 — a spec permite refinar o "layout fino" depois; não é aceite célula-a-célula ainda).
  Registra `decisao` (tipo `aprovacao`) + `evento_auditoria`. Idempotente.
- Portal: a tela de planilha (`/casos/[id]/documentos/[docId]`) ganhou o botão "Aceitar estes
  dados para a base" + badge de status (aceito/pendente) por linha.
- **Export Excel** (`src/lib/export.ts` + rota `/casos/[id]/export`, biblioteca `exceljs`):
  segue o schema-alvo travado em `f0/07` — uma aba por demonstração (`Balanço`, `DRE`, `Fluxo
  de Caixa`, `Combinado`, `Faturamento`, `Dívida`, `Fluxo Projetado`), aba `Resumo` com
  metadados do snapshot (data-base, contagem aceitas/pendentes, versões de taxonomia
  envolvidas). **Linhas pendentes aparecem junto com as aceitas** (nunca somem do export), mas
  com preenchimento âmbar + itálico — "sugestão pendente de revisão", nunca fato silencioso
  (mesmo princípio inegociável). O export **não modela nem projeta** (fora do escopo, mesma
  spec) — só organiza o dado curado e rastreável para o time levar ao modelo deles.
- **Duas revisões no mesmo dia** (feedback direto do dono).
  1. Primeira revisão: a versão inicial saiu como lista achatada — "quero formatado igual um
     balanço ou DRE... use o padrão do mercado". Isso deu o **layout padrão de mercado**
     (Ativo/Passivo/PL hierárquico no Balanço — CPC/prática brasileira; cascata Receita→Lucro
     Líquido na DRE; Atividades Operacionais/Investimento/Financiamento no Fluxo de Caixa —
     método indireto, CPC 03), colunas = entidade × período.
  2. **Segunda revisão (mais importante): o dono apontou o problema certo** — um template com
     ~15 nomes de conta FIXOS quebra na primeira empresa que nomeia a conta diferente (cada
     mandato tem um plano de contas diferente). Pediu explicitamente: nenhuma conta pode ficar
     de fora do Balanço/DRE/Fluxo de Caixa, e incluir também **Balancete**. Resposta:
     `src/lib/statement-templates.ts` foi **reescrito de "template de nomes fixos" para
     "classificador por SEÇÃO"** — cada conta extraída é classificada em Ativo Circulante /
     Ativo Não Circulante / Passivo Circulante / Passivo Não Circulante / Patrimônio Líquido
     (Balanço/Balancete/Combinado) ou nas seções da DRE/Fluxo de Caixa por **sinais amplos**
     (a `secao` que a IA já anota, `db/migrations/0010` + palavras-chave no rótulo), **mantendo
     o rótulo ORIGINAL de cada empresa** — nunca força um nome canônico. `Balancete` virou aba
     própria (reaproveita o classificador do Balanço — um balancete é, por natureza, o mesmo
     agrupamento por seção do plano de contas). O casamento por palavra-chave é tolerante a
     **plural/singular e conectivo diferente** ("Duplicatas a Receber" bate com a regra
     "duplicata a receber"; "Provisão PARA Férias" bate com "provisão DE férias") via
     singularização aproximada PT-BR + remoção de conectivos antes de comparar — não é mais
     substring exato. Contas que não são classificáveis com segurança vão para um bloco
     explícito "Contas Não Classificadas (revisar manualmente)" — nunca desaparecem, nunca são
     forçadas pro lugar errado. Nenhum subtotal/total é calculado por soma — só aparece se o
     próprio documento já trouxer aquela linha extraída (anti-ancoragem: não inventamos
     números). Proveniência (arquivo/página/confiança/status/versão da taxonomia) vai em
     **comentário da célula** (as colunas são entidade×período, não sobra espaço para colunas
     auxiliares). Faturamento/Dívida/Fluxo Projetado continuam em listagem simples (já são, por
     natureza, série/tabela).
- A lógica de classificação + montagem do workbook é uma **função pura** (`buildExportWorkbook`
  + `classificarConta`, sem Supabase/Next.js) — testada isoladamente nesta sessão com dados
  sintéticos via `tsx`, incluindo o teste que motivou a 2ª revisão: **duas empresas fictícias
  com nomenclatura de plano de contas totalmente diferente para as mesmas contas** ("Caixa e
  equivalentes de caixa" vs. "Disponibilidades"; "Imobilizado líquido" vs. "Bens do Ativo
  Imobilizado") — ambas classificadas na seção certa, cada uma com o rótulo original. **Achou e
  corrigiu dois bugs reais durante os testes**: (1) sobreposição de padrão — "Total do
  Patrimônio Líquido" também casava com a linha combinada "Total do Passivo e do Patrimônio
  Líquido"; (2) plural/conectivo — "Duplicatas a Receber"/"Reservas de Lucros Acumulados"
  (plural) e "Provisão PARA Férias" (conectivo diferente) não batiam com as regras escritas no
  singular/com "de", exatamente o tipo de variação entre empresas que o dono alertou. A rota em
  si (busca via Supabase) **não foi exercitada contra um projeto real** — só a classificação e
  montagem do Excel, com dados sintéticos.
- Botão "Exportar para Excel ↓" no dashboard do caso.

### Sessão 5 — Teste aprofundado do export (E4) com dados sintéticos mais realistas
Pedido do dono: "testar o export com um caso real". **Ressalva importante:** este ambiente de
execução remoto não tinha (e não tem) credenciais do Supabase/N8N reais do dono nem documentos
reais de clientes — então o que rodou aqui foi um teste **local, mais profundo que o da sessão
4** (que só usou 2 empresas fictícias mínimas), não um teste contra a infraestrutura de
produção. **Continua pendente**: o dono rodar de fato com um caso real (aplicar `0011` no
Supabase de produção, subir documentos reais, aceitar linhas na tela de planilha, baixar e abrir
o `.xlsx` de verdade no Excel/LibreOffice dele; a rota `/casos/[id]/export` — a busca via
Supabase — segue não exercitada contra um projeto real).

O que foi feito e achado:
- **Dataset sintético bem mais próximo de um caso real**: 3 empresas (mesmo grupo econômico,
  planos de contas com nomenclatura diferente entre si — o teste que motivou o classificador por
  seção na sessão 4), Balanço em 2 períodos, DRE em 2 períodos, Fluxo de Caixa (método indireto),
  Balancete, e uma série de Faturamento — 110 linhas extraídas com vocabulário contábil PT-BR
  realista (não mais só o punhado mínimo de contas fictícias da sessão 4). `buildExportWorkbook`
  é função pura (sem Supabase), então isso testa a lógica de classificação/montagem do Excel
  isoladamente, sem precisar de infraestrutura real.
- **Bug real encontrado e corrigido** em `portal/src/lib/statement-templates.ts`: quando a
  `secao` anotada pela IA não vem preenchida (fallback só por palavra-chave do rótulo), qualquer
  conta com "empréstimo"/"financiamento"/"mútuo" no nome caía sempre no **Passivo** — mesmo
  quando o rótulo dizia explicitamente "a receber" (ex.: "Mútuo a Receber de Coligada", comum em
  holdings/grupos econômicos — exatamente o tipo de estrutura societária que a Oria analisa em
  mandatos de M&A/reestruturação). Um mútuo/empréstimo CONCEDIDO pela empresa é um DIREITO (ativo),
  não uma dívida. Fix: o fallback agora verifica o token "receber" no rótulo e classifica pro lado
  do Ativo (circulante/não circulante conforme prazo) quando presente; mantém o comportamento
  anterior (Passivo) quando não há esse sinal. Também foi adicionado `"mutuo"` à lista de
  palavras-chave (antes só "emprestimo"/"financiamento"/"debenture"/"arrendamento" — "mútuo a
  receber" caía inteiro em "Contas Não Classificadas" por falta de cobertura, não por
  classificação errada). Confirmado com teste isolado de `classificarBalanco` antes/depois do
  fix (4 variações: empréstimo concedido com/sem "a receber" explícito, mútuo, e o caso de
  controle — empréstimo tomado de banco — que precisa continuar indo pro Passivo).
- **Validação estrutural do `.xlsx` gerado**: a tentativa de abrir de verdade num programa de
  planilha (LibreOffice headless, pré-instalado neste ambiente) **falhou por motivo do
  ambiente, não do arquivo** — confirmado com `strace` que o LibreOffice deste sandbox não
  carrega nem um `.xlsx`/`.csv` mínimo gerado do zero (`openpyxl`), então não é algo específico
  do nosso export. Como alternativa, a validação foi feita inspecionando o `.xlsx` estruturalmente
  com `openpyxl` (Python): todas as 6 abas presentes, valores/rótulos corretos por
  empresa×período, contas das duas empresas com plano de contas diferente alinhadas na seção
  certa mantendo o rótulo original de cada uma, linhas pendentes com preenchimento âmbar+itálico,
  comentário de proveniência em toda célula com valor, âncoras (totais) em negrito com borda,
  bloco "Contas Não Classificadas" só com as 2 contas genuinamente fora do vocabulário conhecido
  (um jargão de M&A bem específico de PPA/ágio, de propósito no teste). **Isso reduz mas não
  substitui** o dono abrir o arquivo de verdade no Excel/LibreOffice dele.
- **Migrations 0001-0011 reaplicadas contra um Postgres 16 local efêmero** (mesmo padrão de
  sessões anteriores): aplicam limpo, com a mesma ressalva já conhecida de `storage.buckets`
  (schema exclusivo do Supabase, não existe em Postgres vanilla — só afeta a parte de storage da
  `0003`, não trava o resto) e o overload morto de `fn_registrar_documento` já documentado em
  "Itens adiados" (confirmado presente: 2 assinaturas, 14 e 15 params).
- **Fluxo E1→E2→E4 testado de ponta a ponta** (`fn_registrar_documento` →
  `fn_registrar_campos_extraidos` → `fn_aceitar_extracao`): aceite muda `status_aceite` de
  `pendente` pra `aceito` corretamente, grava `aceito_por`/`aceito_em`, cria `decisao` (tipo
  `aprovacao`) + `evento_auditoria`. **Achado (não corrigido, é uma decisão de produto, não bug
  óbvio)**: chamar `fn_aceitar_extracao` de novo na mesma versão (idempotência) não re-aceita
  linhas já aceitas (`n_campos_aceitos: 0` na segunda chamada, confirmado) — mas AINDA ASSIM
  grava uma nova linha em `decisao` e `evento_auditoria` a cada chamada, mesmo quando nada mudou.
  Ou seja: "idempotente" (`db/migrations/0011`) vale pro estado de `campo_extraido`, não pro
  trilha de auditoria — um duplo-clique acidental no botão "Aceitar" do portal geraria uma
  segunda `decisao` com `n_campos_aceitos: 0` no log. Pode ser intencional (toda ação explícita
  de aceite fica registrada, mesmo sem efeito), mas vale confirmar com o dono se isso é desejado
  ou se `fn_aceitar_extracao` deveria pular o registro de decisão/evento quando `n_campos_aceitos
  = 0`.

### Sessão 6 — IA sugere a seção canônica (classificação do export, N1)
Pedido do dono: "podemos colocar uma IA para criar a planilha? Ela interpretaria melhor caso a
caso... preciso que 90% dos campos extraídos estejam dentro de tabelas e categorias condizentes."

**Decisão de desenho (importante — alinhada à doutrina, não a substitui):** NÃO se trocou o
classificador determinístico por uma "IA que monta a planilha". A doutrina (`docs/01`, assinada
pelo dono) trava: classificação contábil nasce N0, teto **N1** ("nunca vira número sem aceite
humano"), e a regra de ouro exige golden set + concordância medida antes de subir o dial — e o
golden set físico ainda não existe (só o protocolo `f0/06`). Então a IA entrou como **camada de
sugestão N1**, exatamente no padrão que o time já usou pro diagnóstico (0010):
- A MESMA chamada de extração (`n8n/lib/extract.mjs`) — que já roda pra todo documento — passou
  a devolver, por linha, uma **`secao_canonica`**: a IA classifica a conta pelo **significado
  contábil** (não só o nome literal) num enum fixo (`ativo_circulante`, `dre custos`,
  `atividades_investimento`, etc.; `NAO_CLASSIFICAVEL` como escape). **Não aumenta o nº de
  chamadas à OpenAI.**
- `db/migrations/0012_secao_canonica_e4.sql`: coluna `campo_extraido.secao_canonica` +
  `fn_registrar_campos_extraidos` (mesma assinatura) gravando-a.
- O classificador do export (`portal/src/lib/statement-templates.ts` → `classificarConta`) usa a
  sugestão **só como fallback**: se a regra determinística (âncora/seção-livre/palavra-chave) já
  classificou, ela prevalece; a sugestão da IA só entra quando a conta cairia em "Contas Não
  Classificadas", e só se a seção sugerida pertencer à estrutura do documento. Isso ataca direto
  o alvo de 90% sem regredir o que a regra já acerta e **sem depender de golden set**.
- **Continua N1/anti-ancoragem:** a seção afeta só ONDE a linha aparece no Excel; a linha
  continua PENDENTE/âmbar até o aceite humano (`fn_aceitar_extracao`). Nenhum número vira fato.
- **"Otimizar a cada output"** (pedido do dono): isso é o laço de golden set (`f0/06`) — medir
  concordância IA×humano e, quando alta, subir o dial (fazer a IA ter prioridade sobre a regra,
  ou auto-clear). O mecanismo está desenhado; é medição + ajuste de prompt, não código novo. O
  degrau para promover a IA acima da regra determinística é justamente ter esse golden set.
- Testes: 53/53 do N8N (`node --test`) seguem passando (schema/parse de `secao_canonica`
  cobertos em `extract.test.mjs` e no mirror do Code node em `workflow-sim.test.mjs`); classificador
  do portal validado isoladamente (7 casos: gap-filling, determinístico com prioridade, âncora com
  prioridade, sugestão inválida ignorada, DRE/Fluxo); export end-to-end confirmado (conta de
  jargão com sugestão vai pra seção certa; sem sugestão cai em "Não Classificadas"); `tsc --noEmit`
  limpo; migration 0012 aplicada contra Postgres 16 local (grava `secao_canonica`, inclusive null).
- **Limitação conhecida (follow-up):** não há ainda uma ação no portal pra CORRIGIR uma seção
  sugerida errada (o aceite hoje é por documento inteiro — ver item "Refinar granularidade do
  aceite"). Uma sugestão errada é visível (âmbar) mas só se corrige via reextração por enquanto.
- **Ainda pendente (só o dono consegue):** rodar com documentos reais no Supabase/N8N de produção
  e **medir de fato a taxa de "Não Classificadas"** com o vocabulário real dos clientes — é o
  sinal direto de se o alvo de 90% foi atingido, e o primeiro insumo do golden set.

### Sessão 6 (cont.) — Roteamento por linha: separar cada demonstração em sua aba
**Motivado por teste real do dono** (documento `GLOBAL ONE BRASIL REPRESENTAÇÃO LTDA`): ele rodou
o export e viu a DRE cair em "Contas Não Classificadas". O diagnóstico revelou um problema maior
que o aparente: o PDF era uma **Demonstração Contábil completa** (Balanço + DRE + Fluxo de Caixa +
DMPL num arquivo só), classificado como UM documento do tipo `BALANCO`. O export roteava **todas**
as linhas para a aba do tipo do documento, então: (1) a DRE caía em "Não Classificadas"; (2) pior,
as linhas de **Fluxo de Caixa vazavam para dentro do Ativo/Passivo do Balanço** (as linhas de
caixa casavam as palavras-chave "caixa"/"disponibilidade"/"empréstimo"); (3) linhas de DMPL
("SALDOS EM 31 DE DEZEMBRO...") iam parar no Patrimônio Líquido.
- **Fix (escopo escolhido pelo dono: Balanço + DRE + Fluxo de Caixa agora; DMPL/DVA como
  follow-up):** o export passou a **rotear cada LINHA para a aba da sua demonstração**, não para a
  do tipo do documento. `classificarDemonstracao(secao, chave, secao_canonica)` em
  `statement-templates.ts` decide a qual demonstração a linha pertence: prioridade para a
  `secao_canonica` que a IA **já anota por linha** (o `#27`; `ativo_*`→Balanço, `receita_*/custos/
  despesas_*/...`→DRE, `atividades_*`→Fluxo de Caixa), com fallback determinístico (ordem Fluxo →
  DRE → Balanço, porque o de Balanço casa "caixa" de forma gulosa) quando a IA não anotou. Isto é
  literalmente o pedido do dono ("o modelo identifica o que é DRE e o que é Balanço"): a IA já
  identifica; faltava o export obedecer, por linha.
- **Só reroteia entre abas ESTRUTURADAS** (Balanço/DRE/Fluxo). Abas de série (Faturamento/Dívida/
  Fluxo Projetado) não são tocadas. Um **Balancete/Combinado puro** (também família "balanco")
  mantém suas linhas na própria aba — o rerote só move o que "vaza" para uma família DIFERENTE.
  Continua N1/anti-ancoragem: a linha segue pendente/âmbar até o aceite; muda só EM QUAL ABA a
  sugestão aparece.
- **Reforço do classificador de Fluxo de Caixa** para o vocabulário real: saldos de caixa que
  **não usam a palavra "saldo"** ("Caixa e Equivalentes de Caixa no Final/Início do Período") e
  variação de caixa por "acréscimo/decréscimo" agora são reconhecidos como âncoras de Saldo
  Final/Inicial/Variação — sem casar a linha do Balanço "Caixa e Equivalentes de Caixa" (que não
  tem final/início/período).
- **Testes:** reproduzido o caso GLOBAL ONE isoladamente (via `tsx` + inspeção do `.xlsx` com
  `openpyxl`): com `secao_canonica`, as 3 demonstrações se separam em abas próprias com **zero
  "Não Classificadas"**; sem `secao_canonica` (documento antigo, fallback determinístico), ainda
  separa as 3 abas corretamente (só 1 linha ambígua — "ADMINISTRATIVAS" sem contexto — fica em
  "Não Classificadas", o que a `secao_canonica` da IA resolve). Balancete puro mantido na própria
  aba. `tsc --noEmit` e `eslint` limpos. (LibreOffice deste ambiente segue quebrado — validação
  estrutural via `openpyxl`, mesma ressalva das sessões anteriores.)
- **DMPL/DVA (deferido, escolha do dono):** separar Mutações do PL e DVA em abas próprias exige
  estender o `SECAO_CANONICA_ENUM` (novo schema/prompt no N8N + migration) e **reextrair** os
  documentos — não foi feito nesta fatia. Hoje linhas de DMPL provavelmente caem no PL do Balanço
  ou em "Não Classificadas".

### Sessão 7 — BUG CRÍTICO: item errado no upload em lote (conteúdo trocado entre documentos)
**Motivado por teste real do dono** com 2 documentos reais (`BALANÇO ACUMULADO 2025.pdf` — balanço
combinado de 3 entidades, Certsys Tecn/Part/Com — e `Balanço Patrimonial DRE, DFC, DMPL Global One
2024assinado.pdf`) enviados **juntos no mesmo upload do Form**. O export saiu com dezenas de contas
que não existem em NENHUM dos dois PDFs (ex.: "ADIANTAMENTO A CONSÓRCIOS", "ADIANTAMENTO A
COOPERATIVAS" com valores redondos repetidos — `1.000.000.000,00`, `1.234.567,00` — em várias
contas sem relação nenhuma) e entidade/período errados (pegou o nome do CONTADOR assinante em vez
da razão social num dos documentos; "anual 2023" em vez de "anual 2024" no outro).

**Diagnóstico (comparado linha a linha contra os 2 PDFs originais + consulta SQL no Supabase real
do dono):** não era só alucinação da IA. O `documento` do arquivo "Global One" tinha uma
`justificativa` da IA **descrevendo o conteúdo do Certsys** ("colunas para 'Certsys Teen', 'Certsys
Part', 'Certsys Com'...") — prova de que o CONTEÚDO enviado à IA pra esse item não era o do próprio
arquivo.

**Causa raiz** — `n8n/build-workflow.mjs`, node `Preparar Conteudo` (each-item mode, monta a parte
multimodal da chamada de extração): `this.helpers.getBinaryDataBuffer(0, 'data')` com o **índice
fixo em `0`**, comentário do código dizendo (errado) que "cada item roda isolado em each-item mode,
então o índice é sempre 0". Na prática, mesmo em each-item mode, `getBinaryDataBuffer(itemIndex,
propriedade)` resolve o buffer pelo índice do item **dentro do lote inteiro do node** (é assim que
a referência interna de binário vira bytes de verdade) — não pelo item que o código acha que está
processando. Com 2+ arquivos no mesmo upload, todo item diferente de 0 lia o **binário do item 0**:
o nome/mimeType usados na requisição eram os do próprio item (corretos, vêm do JSON), mas os BYTES
de fato enviados pra IA eram de outro arquivo. Com upload de 1 arquivo por vez isso nunca aparecia
(o único item É o item 0) — por isso passou despercebido em toda sessão anterior, incluindo as
verificações "confirmado rodando ao vivo" de sessões passadas (que sempre testaram 1 arquivo de
cada vez).
- **Fix:** troca do literal `0` por `$itemIndex` (global do N8N que dá o índice do item corrente
  em each-item mode).
- **O teste (`n8n/test/workflow-sim.test.mjs`) tinha o MESMO ponto cego** — o mock de
  `getBinaryDataBuffer` ignorava o `itemIndex` recebido e sempre lia do `item` passado
  explicitamente pela própria chamada de teste (por isso o parâmetro se chamava `_itemIndex`, com
  underscore de "não uso"), então nunca exercitava o cenário real de 2 itens competindo pelo mesmo
  binário resolvido por índice. Corrigido: o mock agora resolve pelo `itemIndex` dentro de um
  `binaryStore` (o lote inteiro, como o N8N faz de verdade); `chainFile(idx)` passa a fornecer esse
  lote completo. **Novo teste de regressão** reproduziu o bug (confirmado FALHANDO com o código
  antigo antes do fix — item 1 lia o binário `QUJD` do item 0 em vez do próprio `REVG` — e
  passando depois). 54/54 testes (`npm test` em `n8n/`).
- **Ação pendente do dono (fora do código, só ele consegue):** documentos processados em uploads
  em lote (2+ arquivos no mesmo Form) **antes** deste fix podem ter conteúdo trocado — qualquer
  `documento` cujo diagnóstico/entidade/valores pareçam não bater com o próprio arquivo é suspeito.
  Recomendação: reprocessar (reenviar) esses documentos depois do fix estar no N8N de produção, e
  **não aceitar** ("Aceitar estes dados para a base") nenhuma extração de upload em lote anterior a
  esta correção sem conferir contra o PDF original antes.
- **Achados secundários** (mesmo teste, менos graves, ainda reais — corrigir depois):
  1. Um documento que é, na prática, uma demonstração **combinada de 3 entidades** (colunas
     Certsys Tecn/Part/Com + Total, sem uma única razão social na página) teve a entidade
     preenchida com o **nome do contador que assinou** o documento — a IA não tem hoje uma
     instrução explícita pra não confundir signatário/contador com razão social quando não há uma
     entidade única óbvia. Vale reforçar o prompt (`n8n/lib/extract.mjs`).
  2. Um documento com Balanço+DRE+DFC+DMPL do mesmo exercício teve o período extraído como o ano
     ANTERIOR (2023 em vez de 2024) — provavelmente confundido pela linha "SALDOS EM 31 DE
     DEZEMBRO DE 2023" (saldo de ABERTURA da DMPL) no mesmo PDF. Também vale reforçar o prompt pra
     diferenciar saldo de abertura vs. o período de referência do documento.
  3. O mesmo tipo de documento (Balanço+DRE+DFC+DMPL de UMA entidade só) foi classificado ora como
     `BALANCO`, ora como `COMBINADO` em re-extrações diferentes — `COMBINADO` na taxonomia (f0/03)
     significa demonstrações **combinadas de um grupo de empresas**, não "múltiplas demonstrações
     no mesmo arquivo para uma entidade só". Vale clarificar essa distinção no prompt.
  4. **Achado à parte, não é bug:** o caso de teste do dono ("teste v7") acumulou **11 registros de
     `documento`** pra só 2 arquivos, de reprocessamentos em sessões anteriores — normal em uso
     iterativo de teste, mas reforça que uma limpeza/consolidação de dados de teste pode ajudar a
     não confundir qual é a versão "atual" ao depurar.

### Sessão 7 (cont.) — Causa raiz da fabricação de valores + guarda de segurança
Depois do fix do item errado (acima), pedi ao dono os dados brutos de `campo_extraido` via SQL
(o Supabase real dele) pra confirmar a causa exata da fabricação de valores. Achado decisivo: a
versão **correta** do Global One (documento simples, 1 entidade) veio **perfeita** — toda linha
batendo com o PDF real, confiança 0.95-0.99, `unidade` corretamente `null` (o documento diz "Reais",
não "mil"). Isso isolou o problema: o Certsys (`348c46b8`), mesmo recebendo o PRÓPRIO conteúdo (a
`justificativa` da IA o descreve corretamente — não é vítima do bug de item trocado), ainda assim
saiu quase todo fabricado (`1.234.567,00` repetido em ~20 contas, confiança declarada 0.99). Causa:
o Certsys é um balanço **combinado de 3 entidades** (colunas "Certsys Tecn | Part | Com | Total" na
mesma tabela) e o schema de extração só tinha **um** `valor_num` por linha, sem dimensão de
entidade/coluna — ao tentar espremer 4 colunas num valor só, o modelo fabricava.

O dono pediu as duas ações em paralelo (não são excludentes):

**1. Guarda de segurança (`db/migrations/0013_guarda_extracao_suspeita.sql`)** — não resolve a
causa raiz, torna o sintoma visível pra QUALQUER documento, já em produção assim que a migration
for aplicada (não depende de reextrair nada):
- `fn_registrar_campos_extraidos` (mesma assinatura de 0005/0006/0010/0012) passa a analisar o
  **próprio lote** que acabou de gravar (não relê extrações anteriores, pra não misturar com uma
  extração velha) e gerar `pendencia` tipada quando:
  - **`extracao_padrao_suspeito`** (tipo novo no enum `pendencia_tipo`): 4+ contas DISTINTAS com o
    EXATO mesmo valor não-zero — praticamente impossível em dado real, típico de fabricação. Exclui
    zero de propósito (repetir "0,00" em várias linhas vazias é normal, não é sinal de nada).
  - **`extracao_baixa_confianca`** (o enum já existia desde a `0001`, nunca tinha sido usado — só
    estava no catálogo do `f0/04`): ≥3 linhas E ≥30% do lote com confiança abaixo de 0.7.
  - Idempotente (reaproveita pendência aberta da mesma versão) e auto-resolve numa reextração que
    não repete o padrão — mesmo molde de `fn_registrar_diagnostico`/reconciliação.
- Testado contra Postgres 16 local: extração suspeita gera a pendência certa; reextração limpa
  auto-resolve; baixa confiança gera a pendência certa; chamar duas vezes com o mesmo padrão não
  duplica.

**2. Suporte a documentos multi-entidade (`db/migrations/0014_entidade_coluna_multi_entidade.sql`)**
— ataca a causa raiz, dando à IA uma forma estruturalmente correta de representar o dado em vez de
forçá-la a resumir/adivinhar:
- Coluna nova `campo_extraido.entidade_coluna` — nome da coluna/entidade da linha, quando o
  documento traz várias entidades lado a lado (null no caso comum, 1 entidade só).
- `n8n/lib/extract.mjs` (fonte da verdade) — schema (`entidade_coluna` novo, obrigatório-mas-
  nullable, mesmo padrão de `secao_canonica`) + prompt: quando o documento tem colunas de
  entidade lado a lado, gerar **uma linha por (conta × coluna)**, mesmo "chave", nunca somar/
  estimar um valor único. Mirror manual em `n8n/build-workflow.mjs` (schema JSON + prompt
  comprimido + parse) atualizado junto — mesmo padrão de manutenção de `secao_canonica` (0012).
  `n8n/test/extract.test.mjs` ganhou teste dedicado reproduzindo o Certsys (mesma chave, 4
  `entidade_coluna` diferentes → 4 linhas, não 1).
- Portal: `CampoExtraido`/rota `/export` passam a trazer `entidade_coluna`; `export.ts` usa
  `campo.entidade_coluna || ctx.entidade` para montar a coluna (entidade×período) — cada
  coluna/entidade do documento combinado vira sua PRÓPRIA coluna no export (em vez de forçar tudo
  na entidade principal do documento); a nota de proveniência da célula ganhou "Coluna de origem
  no documento" quando aplicável. Tela de planilha (`/casos/[id]/documentos/[docId]`) mostra a
  coluna de origem ao lado do rótulo quando presente (senão a mesma "chave" repetida N vezes
  pareceria duplicada sem explicação).
- Testado contra Postgres 16 local (grava `entidade_coluna` corretamente, sem falso positivo na
  guarda de padrão suspeito) e via `buildExportWorkbook` fim a fim com os valores REAIS do PDF do
  Certsys (`BENS NUMERÁRIOS`/`DEPÓSITOS BANCÁRIOS` batendo exatamente) — 3 colunas separadas no
  export ("Certsys Tecn", "Certsys Com", "Total"), sem nenhum valor inventado. 55/55 testes do
  N8N; `tsc --noEmit`/`eslint` do portal limpos.
- **Não resolvido nesta fatia:** a classificação `tipo_taxonomia` (BALANCO vs. COMBINADO) do
  documento continua uma decisão separada (achado secundário #3 acima) — `entidade_coluna` funciona
  independente de qual `tipo_taxonomia` o documento levou. (Endereçado logo abaixo, no reforço de
  prompt.)

### Sessão 7 (cont.²) — Reforço de prompt (3 achados secundários) + confirmação do multi-entidade
Com #29 e #30 mergeados e aplicados em produção, o dono **reprocessou os 2 documentos reais**
("teste v9") e mandou o dashboard + o `.xlsx`. Confirmação importante: **o multi-entidade
funcionou** — o Certsys agora sai na aba "Balanço" com 4 colunas separadas (Certsys Com / Part /
Tech / Total), internamente consistentes (as colunas somam o Total), sem os valores fabricados
(`1.234.567,00` repetido) de antes. As abas DRE e Fluxo de Caixa do Global One também vieram
separadas corretamente (roteamento por linha da #28). Um erro claro restava, exatamente o achado
secundário #3: a classificação **`BALANCO` vs `COMBINADO` saiu INVERTIDA** entre os dois documentos:
- `BALANÇO ACUMULADO 2025.pdf` (Certsys — 3 empresas em colunas → **deveria ser COMBINADO**) foi
  classificado como `BALANCO`.
- `Balanço Patrimonial DRE, DFC, DMPL Global One 2024assinado.pdf` (Global One — 1 empresa, várias
  demonstrações → **deveria ser BALANCO**) foi classificado como `COMBINADO`.
- Distinção oficial (taxonomia `f0/03` / seed `0002`): `BALANCO` = balanço de UMA entidade × período
  (vinculação `entidade_periodo`); `COMBINADO` = "Demonstrações combinadas (grupo consolidado)",
  vinculação por `periodo` (o grupo inteiro, não uma entidade).

Reforço aplicado no prompt de extração (`n8n/lib/extract.mjs`, fonte da verdade; mirror comprimido
em `n8n/build-workflow.mjs` regenerado) nos 3 achados secundários de uma vez:
1. **Entidade ≠ signatário:** não usar o nome de quem assinou (contador/administrador/sócio; bloco
   com CRC/CPF) como razão social — foi o que fez "ED ALVES DE AQUINO" (contador) virar a entidade
   do Certsys numa sessão anterior. Em documento de várias empresas, usar o nome do GRUPO ou null.
2. **BALANCO vs COMBINADO:** regra prática amarrada ao sinal que já temos — se as linhas têm
   `entidade_coluna` preenchido (várias empresas) → COMBINADO; se é uma entidade só (mesmo com
   Balanço+DRE+DFC+DMPL no mesmo arquivo) → o tipo da demonstração principal (normalmente BALANCO).
3. **Período ≠ saldo de abertura:** o período é o exercício ATUAL do documento; uma DMPL que mostra
   "Saldos em 31/12/2023" e "31/12/2024" é documento de 2024 (2023 é só o saldo inicial) — foi o que
   fez o Global One sair como "2023" numa sessão anterior.
- **Sem teste unitário determinístico** (é comportamento do LLM — o alvo do golden set `f0/06`, ainda
  não montado). 55/55 testes do N8N seguem passando (schema/parse cobertos); o novo texto foi
  confirmado presente no `workflow.e1-ingestao.json` gerado. **Validação real = o dono reprocessar**
  e conferir se o Certsys vira COMBINADO e o Global One vira BALANCO.

### Sessão 7 (cont.³) — Balanço/DRE/Fluxo completos com FÓRMULAS (reescrita do export)
Pedido do dono depois de reprocessar ("teste v9"): o export estava "horrível e faltando
informações" — sem totais, com a linha de total do documento ("NÃO CIRCULANTE") perdida no meio
das contas, e nomes iguais para valores diferentes ("CIRCULANTE" do Ativo vs. do Passivo). Pediu:
fórmulas calculando os totais por categoria (Ativo/Ativo Circulante/Não Circulante/Passivo/PL/…)
**no cabeçalho da seção**, balanço completo, e "buscar nas melhores fontes contábeis" como montar
Balanço/DRE/Fluxo. **Tensão de doutrina:** isso contradiz a anti-ancoragem de `f0/07` ("nenhum
subtotal calculado por soma"). Reconciliação escolhida pelo dono (via AskUserQuestion): usar
**fórmulas Excel transparentes** (`=SUM`), manter o total que o documento trouxe numa linha de
conferência, e **sinalizar divergência** formula×extraído. Emenda registrada em `f0/07`.
- **Fundamentação (WebSearch):** Lei 6.404/76 art. 178 + CPC 26 — Ativo em ordem de liquidez
  (Circulante; Não Circulante = Realizável a LP / Investimentos / Imobilizado / Intangível);
  Passivo (Circulante, Não Circulante) + PL. DRE em cascata; DFC método indireto (CPC 03).
- **`portal/src/lib/statement-templates.ts` reescrito:** `classificarBalanco` agora (1) reconhece
  linhas que são TOTAIS/cabeçalhos que o doc trouxe (rótulo "nu" — só palavras estruturais — ou com
  "total"/"soma") e as manda para o NÓ certo em vez de virarem "conta no meio" (resolve o "NÃO
  CIRCULANTE no meio" e o "nomes iguais": "CIRCULANTE" sob Ativo vs. Passivo viram os totais de cada
  seção, desambiguados pelo contexto `secao`); (2) sub-classifica o Ativo Não Circulante nos
  subgrupos CPC (Realizável LP/Investimentos/Imobilizado/Intangível), com bucket "Outros" pro que
  não casar. Nova árvore `BALANCO_OUTLINE` (grupo→seção→subseção).
- **`portal/src/lib/export.ts` — builder reescrito:** Balanço montado pela árvore; cada
  seção/grupo tem o subtotal como **FÓRMULA** por coluna (folha = `SUM` das contas; pai = soma dos
  cabeçalhos dos filhos; grupo ATIVO/PASSIVO+PL = soma das seções). DRE em **cascata** (cada
  subtotal = subtotal anterior + soma das contas da seção; referencia a célula anterior, nunca
  re-soma subtotais → sem dupla contagem). Fluxo: caixa líquido por seção = `SUM`; variação = soma
  dos 3; saldo final = inicial + variação. Total do documento vira linha "↳ total informado no
  documento"; se a soma calculada divergir (tolerância 0,5%/1 centavo), pinta ambos + nota
  (reconciliação embutida). Subseções CPC vazias não são emitidas (não polui). Funciona em
  multi-coluna (documento combinado: uma fórmula por empresa).
- **Bugs reais achados e corrigidos durante os testes** (validação via `openpyxl`, LibreOffice do
  ambiente segue quebrado): (1) `ATIVO.filhos` apontava para o bucket-folha errado — o nó pai
  "Ativo Não Circulante" não era emitido e a conta "Créditos com Pessoas Ligadas" SUMIA; (2)
  âncora do total "NÃO CIRCULANTE" caía no nó "Outros" em vez do nó-seção; (3) "PATRIMÔNIO LÍQUIDO"
  (total da seção) colidia com "TOTAL DO PASSIVO E PL" (total do grupo) — resolvido exigindo
  "passivo" no próprio rótulo pro grupo; (4) "Créditos c/Terceiros" não era Realizável LP.
- **Validação com os dados reais** (Global One + Certsys): o balanço agora FECHA — ATIVO = Passivo+
  PL = 12.086.571,06, com Realizável a LP somando as duas contas de crédito (12.080.078,23 =
  informado), Passivo Circulante e PL batendo o informado, zero divergência falsa. DRE em cascata e
  Fluxo com saldo final = inicial+variação, ambos conferidos. `tsc`/`eslint` limpos; 55/55 testes
  do N8N (inalterados — mudança é só no portal).
- **Pendente do dono:** reprocessar/baixar o `.xlsx` e abrir no Excel de verdade (recálculo das
  fórmulas na abertura — validei a ESTRUTURA/fórmulas via openpyxl, não a abertura no Excel real).

### Sessão 7 (cont.⁴) — Layout analítico (margens) inspirado num modelo de FP&A real
O dono mandou arquivos de referência (3 zips: balanços consolidados 2022–2025, DREs, 10
balancetes do grupo Embrepar/Fort Lub/SKY; + `ProjecoesDelendSummary.csv`) e pediu que o export
"entregue algo parecido". O `DelendSummary` é um **modelo de FP&A completo** (colunas mensais
Actual→projeções, KPIs de SaaS — ARR/MRR/BaaS —, Fluxo de Caixa indireto, P&L em cascata com
margens/crescimento %, Pro-forma). **Isso é modelagem/projeção — contradiz `f0/07` ("output NÃO
projeta, NÃO é modelagem")**. Perguntei o rumo (AskUserQuestion); o dono escolheu **"layout
analítico sobre o dado REAL, sem projetar"** (não o motor de projeção). Registrado.
- **Entregue nesta fatia:** linhas de **MARGEM** (% da Receita Líquida) na DRE, como FÓRMULA por
  coluna — Margem Bruta / Operacional / Líquida (estilo DelendSummary), com `IFERROR` (evita div/0).
  Só divide dois valores já extraídos; não projeta nem inventa. **EBITDA ficou de fora de
  propósito:** a DRE real (SKY GROUP consolidado, conferido no PDF) NÃO traz Depreciação/
  Amortização como linha isolada — viria das notas/Fluxo —, então calcular EBITDA exigiria
  inventar D&A. Não fizemos (anti-ancoragem).
- **Nota sobre a estrutura:** a DRE do grupo dobra o Resultado Financeiro DENTRO do "Lucro
  Operacional"; a nossa estrutura (padrão analítico) separa EBIT (antes do financeiro) do
  Resultado Financeiro. Isso faz a conferência do "Lucro Operacional informado" divergir do EBIT
  calculado — é uma diferença DEFINICIONAL esperada (a flag de divergência a torna visível), não
  um bug.
- **Deferido (natural, ainda SEM projeção):** (1) aba "Indicadores/Resumo" consolidada (KPIs por
  período referenciando as abas de demonstração — margens, e indicadores de balanço tipo liquidez/
  endividamento/capital de giro); (2) coluna de **Crescimento %** período-a-período (exige lógica
  de comparabilidade entre colunas da MESMA entidade). Ambos são presentation/fórmula sobre dado
  real. (3) O **motor de projeção/modelagem** (o que o DelendSummary realmente é) segue FORA do
  escopo pela decisão do dono + `f0/07` — só entraria com revisão explícita da doutrina.

### Sessão 7 (cont.⁵) — Ajustes no export após o teste v12 do dono
O dono reprocessou ("teste v12") e apontou "faltou algumas fórmulas". Ao inspecionar o `.xlsx`:
- **Seção só com total informado, sem itens de linha** (ex.: "Imobilizado" no balanço Certsys — o
  documento trouxe só o total do subgrupo, sem detalhar contas): o cabeçalho ficava EM BRANCO (não
  havia o que somar) e o valor ficava órfão na linha de conferência, quebrando o total do pai.
  **Fix:** nesse caso o cabeçalho usa o próprio valor informado como valor da seção (não há soma a
  fazer); a linha de conferência só aparece quando há de fato uma soma para comparar.
- **Seções padrão genuinamente vazias** (ex.: Passivo Não Circulante sem contas) mostravam célula
  em branco no meio do balanço. **Fix:** passam a mostrar `0` explícito (coluna completa).
- **PL inflado no Combinado (bug mais sério, o dono não tinha citado):** as linhas de **DMPL**
  ("SALDOS EM 31 DE DEZEMBRO DE 2023/2024") estavam sendo somadas como contas do PL — e o saldo de
  fechamento REPETE o próprio PL, então o total dobrava (~32 mi vs. ~11,8 mi reais). **Fix:**
  `ehLinhaDMPL()` em `statement-templates.ts` detecta linhas de saldo de abertura/fechamento de
  DMPL (contém "saldo" + ano/inicial/final) e as tira da classificação do Balanço → vão para
  "Contas Não Classificadas" (visíveis, sem somar). Bloqueia inclusive o fallback do
  `secao_canonica` (a IA tende a marcar essas linhas como `patrimonio_liquido`). Só afeta o
  Balanço/Combinado (no Fluxo, "saldo inicial/final de caixa" é tratado pelo classificador do
  Fluxo). Validado: PL fecha no informado, sem divergência falsa; Imobilizado com valor;
  DMPL em "Não Classificadas". `tsc`/`eslint` limpos.
- **Ainda deferido:** DMPL em aba própria (exige estender o enum da IA + reextração); é o passo
  que traria essas linhas de volta como uma demonstração de verdade, em vez de "Não Classificadas".

### Sessão 7 (cont.⁶) — Reconciliação Classe B (`db/migrations/0015`)
Próximo passo combinado com o dono desde a sessão 6, adiado 3x por bugs críticos de dados —
retomado agora que a extração está estável. Segue o desenho de `docs/04_RECONCILIACAO.md` e o
molde da Classe A (`0009`): mesma tabela `reconciliacao` (log append-only, `classe='B'`), mesma
função `fn_valor_conceito`/`fn_normalizar_texto`, mesma pendência idempotente com auto-resolução —
mas **travada em N1** (nunca sobe pra N2 como a A pode): Classe B é agregação/período, não
identidade aritmética pura, então **banda de materialidade** (mais folgada que a A: piso R$ 50k
**e** 5%, vs. R$ 100/0,5% da A) e qualquer divergência na zona cinzenta vira **revisão humana**,
nunca auto-clear.
- **Duas checagens canônicas** (os exemplos de `docs/04`): (1) `fn_reconciliar_receita_dre_vs_faturamento`
  — Receita Operacional Bruta da DRE vs. soma das linhas MENSAIS de `FATURAMENTO_24M` do MESMO
  ano (recorte pelo ano no rótulo — aceita "2024", "24", "12M24" — excluindo linhas de total/média/
  acumulado, que somariam duplicado); (2) `fn_reconciliar_despfin_dre_vs_divida` — Despesa
  Financeira da DRE vs. soma das linhas de juros/encargos do `MAPA_DIVIDA` (compara em módulo,
  já que despesa financeira normalmente vem negativa na DRE).
- **Novo helper de agregação** (diferente da 0009, que casa UMA linha): `fn_somar_conceito` (soma
  todas as linhas que casam termos, ex. todas as linhas de "juros") e `fn_somar_faturamento_ano`
  (soma as linhas mensais de um ano — cada mês não compartilha uma palavra-chave, então o recorte
  é pelo ANO no próprio rótulo). `fn_registrar_reconciliacao_b` fatora o log+pendência (mesmo
  padrão da 0009, reaproveitado pelas duas checagens B).
- **Pré-condição honesta:** como `FATURAMENTO_24M`/`MAPA_DIVIDA` ainda têm schema genérico de
  linhas (não um schema dedicado como a DRE/Balanço), é ESPERADO que estas checagens caiam em
  "precondição não satisfeita" com frequência real até essa extração ser refinada — vira
  pendência, nunca um "OK" falso-limpo (mesmo princípio da Classe A).
- **`fn_reconciliar_por_documento` redefinida** (mesma assinatura) para disparar A+B pelo tipo do
  documento processado — DRE dispara as duas checagens B; FATURAMENTO_24M/MAPA_DIVIDA disparam a
  checagem B correspondente (reaproveitando/auto-resolvendo a pendência quando o outro lado já
  existia).
- **Portal:** rótulo do card mudou de "Reconciliação (Classe A)" para "Reconciliação (Classe A/B)"
  — a lista já é genérica por `pendencia.tipo` (`PENDENCIA_TIPOS_RECONCILIACAO`), então as
  pendências B aparecem automaticamente, sem mudança de lógica.
- **Testado contra Postgres 16 local:** receita batendo (linha "Total" corretamente ignorada);
  precondição por documento faltante, com **auto-resolução** quando o Mapa de Dívida chega depois;
  zona cinzenta (divergência de 32%, acima da banda); casamento de ano com 2 e 4 dígitos.
  Migrations 0001-0015 aplicadas limpo (mesma ressalva de sempre: `storage.buckets` não existe em
  Postgres vanilla). `tsc`/`eslint` do portal limpos.
- **Achado de documentação:** a `0014` nunca tinha entrado na tabela do `db/README.md` (esquecida
  numa sessão anterior) — corrigido junto com a `0015`.
- **Próximo passo natural (não feito aqui):** ação de "confirmar/ressalva" dedicada na fila do
  portal pras pendências de reconciliação (hoje só listam, read-only — item já listado em
  "Próximos passos" há várias sessões).

### Sessão 7 (cont.⁷) — BUG CRÍTICO: extração silenciosamente vazia (`db/migrations/0016`)
Achado testando com um caso real do dono ("teste v14", 16 documentos): todos os documentos foram
**classificados com sucesso** (tipo/entidade/período gravados, confiança 90-95%, fonte
`openai_conteudo`) mas **0 linhas foram extraídas** para qualquer um deles — export saiu com
"Linhas totais extraídas: 0", Reconciliação (Classe A) só apontou pré-condição não satisfeita
(sem dado pra conferir). O N8N mostrava **sucesso em todos os nós**, e reprocessar **não mudava
nada** — sinal de causa determinística, não transitória (rate limit teria variado entre tentativas).
- **Causa raiz:** classificação e extração são DUAS chamadas OpenAI separadas e sequenciais por
  documento. A de extração pede um array `linhas` SEM limite de tamanho (documentos combinados
  grandes — grupo com várias entidades/demonstrações no mesmo PDF, ex. "Balanço Patrimonial DRE
  DFC DMPL 2025assinado.pdf" — podem exigir uma saída JSON enorme). Sem `max_tokens` explícito e
  sem checagem de `finish_reason`, uma resposta truncada (finish_reason=length) virava um JSON
  incompleto que falhava o `JSON.parse` — e `parseExtractionResponse` (`n8n/lib/extract.mjs`,
  mirror em `n8n/build-workflow.mjs`) devolvia `campos: []` **silenciosamente**, sem lançar exceção
  (por isso o node aparece verde no N8N: é um 200 OK truncado, não um erro HTTP). Como o node
  `OpenAI Extrair` também tem `onError: continueRegularOutput` (fail-safe pra um documento ruim
  não derrubar o lote inteiro), mesmo um erro de fato da API (429/500) passaria despercebido do
  mesmo jeito. `fn_registrar_campos_extraidos` (0013) tratava array vazio como "0 campos, sucesso"
  e retornava cedo — nada no pipeline detectava isso.
- **Fix (dois lados, precisam andar juntos):**
  1. `n8n/lib/extract.mjs` (+ mirror `n8n/build-workflow.mjs`): `buildExtractionRequest` agora
     manda `max_tokens: 16384` explícito (teto de saída do gpt-4o) — elimina a possibilidade de um
     default menor específico de conta/API. `parseExtractionResponse` agora captura
     `finish_reason` e `apiJson.error`, e devolve um novo campo `falhaMotivo` (null quando ok;
     motivo textual quando a API errou, veio truncada, ou o JSON é inválido) — nunca mais silêncio.
  2. `db/migrations/0016_guarda_extracao_falhou.sql`: novo tipo `extracao_falhou` no enum
     `pendencia_tipo`. `fn_registrar_campos_extraidos` (mesma assinatura de 0005/.../0013 +
     `p_falha_motivo text default null`) passa a resolver documento/caso **mesmo com 0 campos**
     (antes só rodava se `v_count > 0`) e gera pendência idempotente/auto-resolvível quando o N8N
     manda um motivo de falha — igual ao padrão dos outros dois sinais de guarda (0013).
  3. Node `Gravar Campos (Sombra)`: passa `$json.falha_motivo` como `p_falha_motivo=>$3::text`.
  4. Portal: novo agrupador `PENDENCIA_TIPOS_QUALIDADE_EXTRACAO` (`extracao_padrao_suspeito`,
     `extracao_baixa_confianca`, `extracao_falhou`) — os dois primeiros já existiam desde a 0013
     mas **nunca apareciam em lugar nenhum do portal** (lacuna descoberta agora); nova seção
     "Qualidade da extração" em `casos/[id]/page.tsx` fecha a lacuna pros três de uma vez.
- **Testado:** `npm test` do n8n (63/63, incluindo 6 testes novos — truncamento com JSON
  incompleto, erro de API, `max_tokens` no request, motivo passado pro Postgres). Migrations
  0001-0016 aplicadas limpo contra Postgres 16 local; exercitado ao vivo: extração vazia com
  motivo → pendência criada; reprocessar com o mesmo motivo → não duplica (idempotente);
  reprocessar com sucesso → auto-resolve; sinal 1 (padrão suspeito) continua funcionando sem
  regressão na restruturação da função. `tsc`/`eslint` do portal limpos.
- **Ainda por confirmar pelo dono:** REIMPORTAR o workflow no N8N (o fix de `max_tokens`/detecção
  vive no JSON gerado) + aplicar `0016` no Supabase + reprocessar "teste v14" pra confirmar que
  os dados saem certos dessa vez.

### Sessão 7 (cont.⁸) — Causa real da extração vazia: rate limit (429) no upload em lote
O fix da cont.⁷ (`0016` + `max_tokens`) foi aplicado pelo dono e **funcionou como projetado**:
reprocessando o "teste v15" (16 documentos), a falha deixou de ser silenciosa — o portal mostrou
16 pendências `extracao_falhou` na nova seção "Qualidade da extração", TODAS com o mesmo motivo:
**"Erro da API OpenAI: Try spacing your requests out using the batching settings under 'Options'"**.
Ou seja: a `max_tokens` não era a causa (era uma hipótese plausível); a causa real é **rate limit
(429)**. Num upload em lote de 16 documentos, o N8N dispara ~16 chamadas de extração multimodais
(cada uma pesada) quase simultâneas → estoura o limite de RPM/TPM da OpenAI → a API retorna 429
e TODAS as extrações falham. (A classificação por conteúdo dos mesmos arquivos funcionou porque é
uma chamada mais leve e nem todo documento aciona o fallback — só quem tem confiança de nome < 0.7.)
- **Hipótese do dono (formato de arquivo, ex. Word):** descartada para ESTE caso — os 16 são PDFs,
  a classificação leu o conteúdo de todos com sucesso (90%), e as 16 falhas têm a mensagem idêntica
  de rate limit (um problema de formato daria erros diferentes por arquivo). Word (.docx) É um gap
  real e separado (hoje cai em "conteudo nao suportado" no `Preparar Conteudo`), mas não é o que
  quebrou o teste v15.
- **Fix:** os dois nós HTTP da OpenAI (`OpenAI Classificar`, `OpenAI Extrair`) ganharam **batching**
  (`batchSize: 1`, `batchInterval: 3000` — 1 chamada por vez, 3s de intervalo, espalha RPM e TPM no
  tempo) + **retry no nível do node** (`retryOnFail`, `maxTries: 4`, `waitBetweenTries: 5000` — teto
  do N8N) pro 429 residual. É exatamente o que a própria mensagem de erro do N8N recomenda
  ("use the batching settings under 'Options'"). Helper `OPENAI_BATCHING` + extensão do helper
  `node()` pra aceitar as opções de retry.
- **Só workflow** (nenhuma migration): `n8n/build-workflow.mjs` + `workflow.e1-ingestao.json`
  regenerado. `npm test` 64/64 (1 teste novo trava batching+retry nos dois nós). **Precisa
  reimportar o workflow no N8N** e reprocessar o "teste v15".
- **Trade-off consciente:** com `batchSize 1` + 3s, 16 documentos levam ~1min só de espaçamento
  (+ o tempo de cada chamada). É lento mas confiável; se o volume crescer muito, dá pra afrouxar o
  intervalo conforme o tier da conta OpenAI (limites maiores) — deixado conservador de propósito.

### Sessão 7 (cont.⁹) — Documentos COMPARATIVOS: coluna de período (`db/migrations/0017`)
Pedido do dono: deixar o sistema "profissional a ponto de um modelador de 20 anos usar ativamente".
A maior lacuna de export mapeada (e um bug de PERDA DE DADO): demonstração comparativa — o padrão em
contabilidade, ex. o "Balanço consolidado 2023 x 2024.pdf" do teste v15 — tinha as duas colunas de
ano (2023, 2024) da MESMA entidade **coladas numa coluna só** no export. A chave de coluna era
`entidade × período-do-documento`, e o período do documento é único (`multi 23,24`), então a
extração emitia duas linhas "Caixa" (uma por ano) que caíam na MESMA coluna e uma sobrescrevia a
outra. Sem os anos lado a lado não há análise horizontal (Δ%) nem vertical — inutilizável pra
modelagem.
- **Fatia completa (mesmo padrão do `entidade_coluna`/0014):** coluna nova `campo_extraido.periodo_coluna`
  (rótulo da coluna de período da linha; null no caso comum de período único → cai no período do
  documento, sem regressão). É **ortogonal** a `entidade_coluna`: um documento pode ter várias
  empresas E vários anos → linha por (conta × empresa × período). Schema+prompt de extração
  (`n8n/lib/extract.mjs` + mirror `build-workflow.mjs`) pedem uma linha por (conta × período); o
  export (`portal/src/lib/export.ts`) usa `periodo_coluna` na chave de coluna; a tela de linhas do
  documento mostra `[período]` ao lado do `(entidade)`.
- **Limpeza de schema junto:** a `0016` tinha deixado DUAS sobrecargas de `fn_registrar_campos_extraidos`
  (3 e 4 params — `create or replace` com nº de params diferente cria overload novo, não substitui);
  uma chamada posicional de 2 args ficava AMBÍGUA ("is not unique") — só não estourava em produção
  porque o N8N chama com o param nomeado `p_falha_motivo=>`. A `0017` derruba a de 3 params e recria
  só a de 4. (Mesma classe do cruft de `fn_registrar_documento` ainda anotado em "Itens adiados".)
- **Testado:** `npm test` do n8n 66/66 (parse de comparativo, schema pede `periodo_coluna`, mirror
  propaga). Migrations 0001-0017 limpas no Postgres 16 local; provado no banco (comparativo grava 2
  linhas "Caixa" com períodos distintos, overload agora único) E no export (harness `tsx` com
  `buildExportWorkbook`: "Grupo X — 2023" e "Grupo X — 2024" viram colunas separadas). `tsc`/`eslint`
  do portal limpos.
- **Bundle consciente:** subiu na MESMA branch do batching (cont.⁸) — o dono reimporta o workflow UMA
  vez só e ganha os dois (fim do 429 + colunas comparativas). Precisa aplicar `0017` no Supabase.
- **Ainda por validar pelo dono:** reprocessar o v15 já com este workflow, e conferir se o LLM
  popula `periodo_coluna` corretamente nos documentos comparativos reais (o teste local prova o
  encanamento, não o comportamento do modelo).

### Sessão 7 (cont.¹⁰) — Upload pelo portal + mandato explícito (intake amigável)
Pedido do dono (OODA): input mais amigável dentro do HTML da Vercel (enviar/receber arquivos no
próprio portal) + um "campo de mandato" pra enviar arquivos em momentos diferentes e caírem no
mesmo checklist/export/reconciliação.
- **Observação-chave:** o "mandato" JÁ é o `caso` — `fn_upsert_caso(nome)` reusa por nome
  (`db/migrations/0006`), então reenviar no mesmo mandato já acumula. O que faltava era (a) tornar
  isso explícito/amigável e (b) permitir upload pelo portal. E o ponto crítico de arquitetura: o
  pipeline lê o binário do **Form do N8N** — reescrever isso pra ler do Storage seria uma fatia
  grande e não-testável.
- **Desenho de menor risco (pipeline intacto):** o portal ENCAMINHA os arquivos pra MESMA URL do
  Form do N8N, servidor-a-servidor. A OpenAI/extração/reconciliação continuam 100% no N8N; o portal
  é só um front-end de intake.
  - `portal/src/app/api/intake/route.ts` (runtime Node): recebe multipart, valida, e faz `fetch`
    POST multipart pra `N8N_INTAKE_FORM_URL` com os campos `Mandato (nome do caso)`/`Arquivos`
    (nomes overridáveis por env `N8N_INTAKE_FIELD_*`). Sem a env → 503 com aviso claro.
  - `portal/src/components/upload-form.tsx` (client): dropzone (drag-drop + clique), lista de
    arquivos com remover, campo de mandato, estados de envio/erro/sucesso. `travarMandato` quando
    é "adicionar a um mandato existente".
  - Páginas: `/casos/novo` (novo mandato) e `/casos/[id]/adicionar` (mandato travado, volta ao
    caso). Botões "+ Novo mandato" (lista) e "+ Adicionar arquivos" (dashboard). Copy do empty-state
    da lista corrigida (não diz mais "a ingestão roda pelo N8N").
- **Testado:** `tsc`/`eslint`/`next build` limpos — todas as rotas novas compilam
  (`/api/intake`, `/casos/novo`, `/casos/[id]/adicionar`). **Não testável aqui:** se o Form do N8N
  aceita o multipart encaminhado com esses nomes de campo exatos (depende da instância/versão) —
  por isso os nomes são overridáveis por env e o erro do route é explícito. O dono precisa setar
  `N8N_INTAKE_FORM_URL` (Production URL do node Intake Form) na Vercel e validar o primeiro envio.
- **Escopo consciente:** o polimento "de modelador" (análise horizontal/vertical Δ%/AV%) NÃO entrou
  aqui — fica pro próximo passo, e faz mais sentido depois do reprocesso real do v15 (com o
  batching+período já mergeados) mostrar dado de verdade. Documentos Word/.xlsx (gap de formato
  levantado pelo dono) também continuam pendentes (item nos próximos passos).

### Sessão 7 (cont.¹¹) — "Teste v18" (16 docs reais, US$3): 9/16 ok, 7 falharam — 2ª rodada de hardening
Pedido do dono: OODA — analisar o que ainda quebra/não está otimizado e executar. O dono rodou o
lote real de 16 documentos ("teste v18", já com o batching+período mergeados) e reportou o
resultado: **797 linhas extraídas com sucesso** (progresso real vs. 0 da cont.⁷), mas **7 de 16
documentos ainda falharam** — 3 com o MESMO 429 de rate limit da cont.⁸, 3 com truncamento
(`finish_reason=length`) mesmo com `max_tokens=16384` (cont.⁷), e 1 sinal de padrão suspeito
(guarda 0013 funcionando corretamente).
- **Padrão real identificado:** todos os 7 falhos são demonstrações CONSOLIDADAS COMPARATIVAS
  MULTI-ANO (ex. "Balanço Consolidado 2022 e 2023.pdf", "DRE Consolidado 2024.pdf") — o PIOR caso
  possível: mais tokens de ENTRADA (2-3 anos de dados no PDF) e mais tokens de SAÍDA (cada conta
  vira 2-3 linhas via `periodo_coluna`, cont.⁹). Os 9 documentos "Sky/Fort Lub/Embrepar" (multi-
  demonstração — Balanço+DRE+DFC+DMPL — mas de UM ano só) funcionaram bem, o que descarta a
  hipótese de "documento com várias demonstrações = sempre denso demais".
- **Fix 1 — chaves de fio curtas (`n8n/lib/extract.mjs` + mirror):** o array `linhas[]` é o único
  bloco repetido centenas de vezes por documento — cada caractere de nome de propriedade é gasto
  DE NOVO a cada linha na saída JSON. Renomeado `secao→s, secao_canonica→sc, entidade_coluna→ec,
  periodo_coluna→pc, chave→k, valor_texto→vt, valor_num→vn, origem_pagina→op, confianca→cf` SÓ na
  conversa com a OpenAI (com `description` em cada campo pra não perder a orientação do modelo);
  `parseExtractionResponse` remapeia de volta pros nomes completos — **nada gravado no banco
  muda**. Redução medida: ~30-40% de bytes por linha (teste trava >=15%). Mitigação PARCIAL e
  honesta: ajuda todo documento, mas documentos genuinamente enormes (300+ linhas) podem ainda
  passar de 16384 tokens mesmo compactado — a correção completa exigiria dividir a extração em
  múltiplas chamadas (por página ou por período), o que é uma mudança de topologia do grafo do N8N
  que **não dá pra validar sem uma instância N8N viva** (decisão consciente de NÃO implementar às
  cegas — ver "Itens adiados" abaixo).
- **Fix 2 — batching mais conservador (`OPENAI_BATCHING`, `maxTries`):** `batchInterval` 3s→6s,
  `maxTries` 4→6. Achado: 3s+4 tentativas (cont.⁸) reduziu o 429 de 16/16 pra 3/16, mas não
  eliminou pros documentos mais pesados (mais tokens de ENTRADA também consomem TPM, não só a
  cadência de requisições resolve). Trade-off consciente: processa mais devagar.
- **Workaround imediato pros 3 documentos que ainda truncam:** dividir o PDF em arquivos por ano
  antes de subir (ex. "Balanço 2022.pdf" + "Balanço 2023.pdf" separados) — cada ano sozinho tem
  volume comparável aos 9 documentos que já funcionaram bem.
- **Kit de PDFs sintéticos pra testar sem gastar dinheiro real** (pedido explícito do dono, que não
  quer "ficar testando infinitamente gastando tokens"): 9 arquivos pequenos (~2-3 KB cada, texto
  puro, nada escaneado) cobrindo os 8 itens do Kit Básico + Mapa de Dívida (bônus, fecha a
  checagem Classe B de despesa financeira). Números **deliberadamente consistentes entre
  arquivos** — Ativo = Passivo+PL (2024 e 2025), Caixa do Balanço = Saldo final do Fluxo, Receita
  Bruta da DRE = soma dos 12 meses de 2025 no Faturamento 24M, Despesas Financeiras da DRE = soma
  dos juros no Mapa de Dívida — pra que as reconciliações Classe A **e** Classe B tenham uma chance
  real de fechar limpo num teste de poucos centavos, não só "a extração rodou". Entregues ao dono
  fora do repo (são dado de teste, não código).
- **Testado:** `npm test` do n8n 68/68 (2 testes novos travando o batching endurecido e a redução
  de bytes por linha). Migrations não mudaram nesta fatia (só `n8n/lib/extract.mjs` +
  `build-workflow.mjs` + testes). `tsc`/`eslint` do portal inalterados (fatia é só n8n).
- **Observação à parte (não corrigida aqui):** os 9 documentos "Sky/Fort Lub/Embrepar" (1 entidade,
  4 demonstrações no mesmo PDF) vieram classificados como `COMBINADO` com a entidade preenchida —
  pela doutrina (`f0/03`, reforçada na cont.²) isso deveria ser a demonstração PRINCIPAL (ex.
  `BALANCO`), já que `COMBINADO` é reservado pra grupo de VÁRIAS empresas com colunas por empresa.
  Não corrigiu os dados (o `entidade_coluna` ficou null corretamente, o export separou por arquivo
  do jeito certo) — é só um rótulo de classificação errado, cosmético por ora. Vale reforçar o
  prompt de novo numa sessão futura se persistir.
- **Itens adiados (arquitetura maior, precisa de N8N vivo pra validar):**
  1. Dividir a extração em múltiplas chamadas por período/página pra documentos genuinamente
     enormes (a correção COMPLETA do truncamento) — muda a topologia do grafo (fan-out mid-
     pipeline), não é seguro de implementar sem testar contra uma instância N8N real.
  2. Reforçar de novo o prompt BALANCO×COMBINADO (achado acima) se o dono confirmar que persiste.

### Sessão 7 (cont.¹²) — BUG CRÍTICO: upload pelo portal "sucesso" mas workflow nunca rodava
Achado testando o upload novo (cont.¹⁰) contra o N8N real do dono: depois de corrigir o erro de
URL de teste vs. produção, o envio pelo portal mostrava sucesso, mas **20+ minutos depois nada
tinha aparecido no mandato e ZERO tokens tinham sido gastos na conta OpenAI** — ou seja, o workflow
nunca chegou a rodar de verdade, apesar do portal reportar "enviado com sucesso".
- **Causa raiz:** `/api/intake` montava o multipart usando os RÓTULOS visíveis do Form
  ("Mandato (nome do caso)"/"Arquivos") como nome de campo — mas o atributo `name` real gerado
  pelo N8N para aquele campo pode ser diferente do rótulo. O webhook do Form aceita o POST (HTTP
  200 — "deu certo" pro portal) ANTES de saber se o workflow vai ter dado pra processar; se o nome
  do campo não bate, o node `Listar Arquivos` lança seu erro explícito ("Nenhum arquivo recebido do
  formulario") e a execução morre ANTES de qualquer chamada à OpenAI — exatamente "sucesso na tela,
  0 tokens gastos, nada no mandato".
- **Fix — descoberta automática de nomes de campo** (`portal/src/lib/n8n-form.ts`): em vez de
  fixar/adivinhar os nomes, `/api/intake` agora faz um GET no próprio Form antes de enviar, faz o
  parsing (por regex, tolerante) dos `<input>` do HTML retornado, e usa os `name` REAIS
  encontrados (arquivo = primeiro `<input type="file">`; mandato = primeiro `<input>` de texto
  não-hidden/não-submit). As envs `N8N_INTAKE_FIELD_*` viram um **override manual opcional** (se
  setadas, usadas direto, pulando a descoberta) em vez do único caminho. Fallback gracioso: se o
  GET falhar ou não achar `<input>` reconhecível, cai nos nomes padrão de antes (nunca piora o
  comportamento anterior).
- **Pedido do dono (mesma sessão): pop-up elegante ao terminar + copy sem termos técnicos.** A
  mensagem "O N8N está processando (classificação + extração)" foi trocada por algo sem nomear
  nenhuma ferramenta/plataforma ("Estamos organizando tudo com cuidado — isso costuma levar alguns
  minutos"). Novo endpoint `GET /api/intake/status` (`portal/src/app/api/intake/status/route.ts`)
  combina dois sinais pra saber quando o pipeline "terminou de tentar" (não "terminou sem
  pendências" — isso continua no dashboard como sempre): `documento` criado para o caso desde o
  envio (classificação concluída) + `evento_auditoria` tipo `extracao_sombra` referenciando aquele
  `documento_versao` (extração tentou rodar — sucesso OU falha, sempre gravado por
  `fn_registrar_campos_extraidos` desde a `0016`). `upload-form.tsx` faz polling silencioso a cada
  ~8s por até ~12min e, quando pronto, mostra um pop-up modal ("Tudo pronto") com CTA pro mandato —
  sem precisar recarregar a página.
- **Testado:** parser de nomes de campo validado contra 4 cenários (rótulo=nome, nomes internos
  diferentes, campo hidden não confundido, HTML sem `<input>` reconhecível → fallback). `tsc`,
  `eslint` e **`next build`** limpos — as duas rotas novas (`/api/intake/status`) e o componente
  compilam. **Não testável aqui:** se o parsing por regex bate com o HTML real que o N8N do dono
  gera (não tenho acesso a uma instância viva) — por isso o fallback gracioso existe; se a
  descoberta não funcionar, o comportamento cai pro que já existia (nomes fixos, ajustáveis via
  env).

### Sessão 7 (cont.¹³) — "Teste v19" (9 arquivos pequenos, kit sintético): confirmação de tier + 2º bug crítico
Pedido do dono: corrigir "completamente" os erros que fizeram até os 9 PDFs sintéticos pequenos
(kit da cont.¹¹, ~2-3 KB cada) falharem — nenhuma linha extraída, e alguns arquivos nem aparecendo
no dashboard.
- **Contradição que motivou a investigação:** o "teste v18" (16 documentos REAIS, batching de 3s)
  teve 13/16 sucesso; o "teste v19" (9 arquivos pequenos, batching de 6s — mais conservador) teve
  0/6 sucesso nas extrações visíveis. Mais espaçamento resultando em MAIS falha é o oposto do
  esperado — indicava causa fora do código de batching.
- **Causa 1 confirmada pelo dono:** a conta OpenAI estava genuinamente no teto do rate limit (RPM)
  — ele confirmou e subiu o tier durante a sessão. Nenhum espaçamento de código resolve isso
  sozinho quando o teto real da conta é mais baixo que a cadência tentada; **"0 tokens gastos" no
  painel da OpenAI é exatamente o esperado num 429 genuíno** (a requisição é rejeitada antes de
  qualquer processamento, não cobra token nenhum) — não era evidência CONTRA a hipótese de rate
  limit, e sim a favor.
- **Causa 2 — bug real, achado investigando por que 3 dos 9 arquivos nunca apareceram no
  dashboard (nem "não classificado", nem pendência):** os 6 nós Postgres do pipeline
  (`Upsert Caso`, `Registrar Documento`, `Recomputar Completude`, `Gravar Campos (Sombra)`,
  `Registrar Diagnostico`, `Reconciliar (Classe A)`) não tinham NENHUM tratamento de erro — ao
  contrário dos nós OpenAI, que já tinham `onError:continueRegularOutput` desde a cont.⁸. Um erro
  transitório de conexão num ÚNICO item (mais provável sob a carga do lote, com o rate limit já no
  teto) **parava a execução inteira do N8N**, e todo item ainda na fila desaparecia sem nenhum
  rastro — exatamente o sintoma "3 de 9 arquivos somem". Corrigido: todos os 6 nós Postgres agora
  têm `onError:continueRegularOutput` + `retryOnFail` (3 tentativas, 3s entre elas) — o pior caso
  agora é "esse item específico fica incompleto" (nunca vira fato, segue N0/pendente, doutrina
  anti-ancoragem docs/01), não "o lote inteiro desaparece em silêncio".
- **Testado:** `npm test` do n8n 69/69 (1 teste novo travando onError+retryOnFail+maxTries nos 6
  nós Postgres). `tsc`/`eslint` do portal inalterados (fatia é só n8n).
- **Ainda por confirmar pelo dono:** reimportar o workflow (pega o retry dos nós Postgres) e
  reprocessar o kit de PDFs sintéticos de novo, agora com o tier da OpenAI já corrigido — deve
  extrair 100% das linhas dos 9 arquivos (são pequenos e simples de propósito, o "caso mais fácil
  possível" pro pipeline).

### Sessão 7 (cont.¹⁴) — "Teste v20" (kit sintético reprocessado): 2 bugs reais + auto-aceite + limpeza de export
O kit de PDFs sintéticos reprocessado ("teste v20", com o rate limit corrigido e os fixes de
extração/Postgres já mergeados) veio 100% classificado (Kit Básico inteiro "presente", 113 linhas
extraídas) — a extração em si funcionou. Análise do resultado (export + fila de revisão) achou 4
problemas reais, todos corrigidos nesta fatia.

- **BUG 1 — cards da fila de revisão não somem ao confirmar/salvar (confirmado ao vivo):** os
  prints do dono mostravam documentos já com `fonte=humano, confiança=100%` (ou seja, o "Confirmar/
  salvar" JÁ tinha rodado) mas o card continuava na fila com "PERÍODO PODE ESTAR INCORRETO". Lendo
  `fn_revisar_documento` (0008): ela só resolve pendências do tipo `classificacao_pendente` — as
  outras três (`tipo_incorreto`/`entidade_incorreta`/`periodo_incorreto`, introduzidas pela 0010
  MUITO depois e nunca conectadas de volta a esta função) nunca fecham, mesmo depois da revisão
  humana confirmar/corrigir. **`db/migrations/0018`**: mesma função, mesma assinatura, resolve os
  quatro tipos agora.
- **BUG 2 — vazamento entre abas do export:** a aba "Fluxo de Caixa" tinha uma coluna FANTASMA
  ("Teste Indústria Ltda — multi 02,25") com só a linha "Lucro Líquido do Exercício" (600.000) —
  vinda do arquivo da DRE, que não tem NENHUMA linha de fluxo de caixa. Causa:
  "Lucro Líquido do Exercício" é âncora TANTO da DRE (linha de fechamento) QUANTO do Fluxo de Caixa
  indireto (ponto de partida da reconciliação) — mesmo rótulo, dois sentidos legítimos — e
  `classificarDemonstracao` (`statement-templates.ts`) checava Fluxo de Caixa ANTES de checar a
  estrutura do próprio documento, então uma DRE isolada perdia a própria linha de fechamento pra
  aba errada. Fix: `classificarDemonstracao` agora recebe a estrutura do PRÓPRIO documento e
  prioriza mantê-la ali quando ela também reconhece a linha — só reroteia pra outra família quando a
  estrutura do documento não reconhece a linha (o caso genuíno de PDF combinado).
- **BUG/ACHADO 3 — "taxonomia estranha":** `MUTUOS` (categoria "Intragrupo" na própria taxonomia,
  `db/migrations/0002`) estava mapeado pra aba "Dívida" — um mútuo intragrupo não é dívida bancária
  externa (`MAPA_DIVIDA`/`CONTRATO_DIVIDA`), misturar os dois numa aba só não fazia sentido
  contábil. `FAT_INTRAGRUPO` e `CONTRATO_SOCIAL` nem tinham aba própria, caindo no genérico
  "Outros" junto com dado sem relação nenhuma. Fix (`portal/src/lib/export.ts`): `MUTUOS`/
  `FAT_INTRAGRUPO` → aba nova "Intragrupo"; `CONTRATO_SOCIAL` → aba nova "Societário".
- **Pedido 4 — colunas mais simples na listagem simples** (Faturamento/Dívida/Intragrupo/
  Societário/Fluxo Projetado): tinha 13 colunas, a maioria técnica/rastreabilidade (seção, página,
  unidade, confiança, aceito por/em, arquivo de origem, versão da taxonomia) — poluindo quem só
  quer ver conta × valor. Reduzido pra 5 (Entidade, Período, Rótulo, Valor, Status); as removidas
  NÃO somem — viram um comentário (`cell.note`) no rótulo, visível ao passar o mouse (mantém
  rastreabilidade sem poluir a grade, princípio de `f0/07_output_spec.md`).
- **Pedido 5 — auto-aceite >=95% de confiança:** decisão de produto explícita do dono, registrada
  com a ressalva honesta de que isto sobe a autonomia da extração além do que a doutrina padrão
  (`docs/01`) exigiria sem golden-set validado — a `confianca` é a autoavaliação do PRÓPRIO modelo,
  não verificada contra gabarito humano. Implementado mesmo assim (é uma escolha do dono, não da
  IA), com registro completo: `db/migrations/0019` grava `status_aceite='aceito'` já na extração
  quando `confianca >= 0.95`, com UM `decisao`(autor='sistema:auto_aceite')+`evento_auditoria` por
  chamada (resumo, não por linha) — auditável/reversível. Inclui backfill pras linhas já gravadas
  antes desta migration. Recomendação registrada: acompanhar a taxa de erro real nas linhas
  auto-aceitas e ajustar o limiar (hoje 0.95, hardcoded) se necessário.
- **Testado:** os dois fixes de SQL provados contra Postgres 16 local com dado real (pendência
  `periodo_incorreto` resolvendo corretamente; confiança 90% ficando pendente e 95%/97% auto-
  aceitando; backfill promovendo linha antiga; idempotência confirmada). Export validado com
  harness `tsx` reproduzindo o cenário exato do bug (DRE isolada não vaza mais pra Fluxo de Caixa;
  MUTUOS/FAT_INTRAGRUPO vão pra Intragrupo; CONTRATO_SOCIAL vai pra Societário; listagem simples
  com 5 colunas). `tsc`/`eslint`/`next build` limpos.
- **Precisa:** aplicar `0018`+`0019` no Supabase (sem mudança no N8N — esta fatia é só Postgres +
  export do portal). Re-exportar o "teste v20" pra conferir visualmente o resultado.

### Verificação de qualidade (rodada real, 2026-07-20)
Um ciclo completo de teste ao vivo no N8N/Supabase real do dono revelou e corrigiu 3
bugs reais em sequência (todos documentados em `n8n/README.md` → Troubleshooting):
1. Schema da OpenAI sem `enum` em `tipo_taxonomia`/`periodo_tipo` → IA inventava
   código inválido (`"BAL"` em vez de `"BALANCO"`).
2. Leitura de binário no Code node via `binary.data.data` direto → quebra em modo
   "filesystem" do N8N (o campo vira uma referência interna, não a base64).
3. Fix do item 2 usou `$helpers` (global que não existe no runtime de Task Runner) —
   corrigido para `this.helpers.getBinaryDataBuffer(...)`.

Resultado final confirmado: a IA classifica com confiança alta citando o **conteúdo
real** do documento (não mais o nome do arquivo), com justificativa objetiva.

### Sessão 7 (cont.¹⁵) — "Total informado × calculado" divergindo mesmo em arquivo de teste + limpeza final do export
O dono reportou que, mesmo em arquivos sintéticos próprios, a linha "↳ total informado no
documento" batia com o total informado mas divergia do SUM calculado em vários lugares — pediu pra
explicar por quê. Inspeção do export real ("teste v20") linha a linha achou 2 bugs de classificação
reais (não artefato do arquivo de teste — vêm de convenções bem comuns de demonstração financeira
brasileira), além de 3 pedidos de limpeza visual:

- **BUG 1 — DRE contava um subtotal duas vezes:** "Resultado antes do resultado financeiro" (mesmo
  valor do EBIT) e "Resultado Financeiro Líquido" (mesmo valor de Despesas+Receitas Financeiras já
  dentro da própria seção) são subtotais de apresentação em cascata — mas o rótulo compartilha
  vocabulário com a seção "Resultado Financeiro" onde a linha está, então caíam classificados como
  CONTA comum e eram somados de novo, dobrando o valor do total calculado (`SUM` incluía o EBIT e o
  próprio resultado financeiro líquido, além das contas que os compõem). Fix
  (`statement-templates.ts`): nova guarda `ehSubtotalRedundanteDRE` (mesmo padrão de `ehLinhaDMPL`)
  reconhece essas duas frases e as tira da soma — caem em "Contas Não Classificadas" (visíveis, sem
  distorcer nenhum subtotal).
- **BUG 2 — cabeçalho combinado "Passivo e Patrimônio Líquido" jogava tudo pra PL:** convenção
  padrão dos balanços brasileiros (Lei 6.404/76 art. 178) — mas em `classificarBalanco`, o check de
  seção pra "patrimonio liquido" rodava ANTES do check pra "passivo", e o cabeçalho combinado contém
  as duas palavras como substring. Resultado: toda conta sob esse cabeçalho (Fornecedores,
  Empréstimos e Financiamentos) caía em `patrimonio_liquido` em vez de `passivo_circulante`/
  `passivo_nao_circulante`, e as seções de Passivo ficavam zeradas — daí a divergência entre o total
  informado (que inclui essas contas) e o calculado (que não). Fix: "passivo" é checado primeiro;
  "patrimonio liquido" só entra como `else if` quando "passivo" não está combinado na mesma seção.
- **Pedido — remover toda menção a tipo/versão de taxonomia da planilha:** era detalhe interno de
  classificação, não algo que o time de análise precisa ver. Removido de: nota de proveniência de
  cada célula (`notaProveniencia`/`notaProvenienciaSimples`), aba Resumo (linha "Versão(ões) da
  taxonomia envolvidas" e o parâmetro inteiro `taxonomia`/`TaxonomiaParaExport` que só existia pra
  isso). Continua orientando o roteamento por aba internamente (`tipo_taxonomia`/`ABA_POR_TIPO`) —
  só sai da tela, não da lógica.
- **Pedido — padronizar a escrita de período:** convenções cifradas vindas da extração ("multi
  02,25", "data-base 2025-01-15", "12M25", "L24M", "1T25") viravam texto solto e técnico na
  planilha. Nova função `formatarPeriodo` (`export.ts`) traduz pra um modelo pronto e objetivo:
  "2023, 2024, 2025" / "15/01/2025" / "2025" (ano fiscal completo) / "9 meses/2024" / "Últimos 24
  meses" / "1º Tri/2025" / "2024–2025" (intervalo de 2). O que não reconhece devolve como veio
  (nunca pior que antes).
- **Pedido — anotações cortadas ao abrir:** a caixa de toda nota (`cell.note`) do ExcelJS vem com
  tamanho FIXO no XML VML (`width:97.8pt;height:59.1pt` ≈ 130×80px), hardcoded no próprio pacote
  (`lib/xlsx/xform/comment/vml-shape-xform.js`) — sem parâmetro público pra mudar (conferido lendo o
  fonte da lib, não só o `.d.ts`). Fix em duas partes: (1) fonte compacta (8pt, `comoNota()`) em toda
  nota; (2) nova função `ampliarNotasNoBuffer` pós-processa o `.xlsx` já gerado — ele é um .zip, abre
  com JSZip (dependência transitiva do próprio exceljs, agora explícita em `package.json`), troca a
  string de tamanho fixo por uma caixa bem maior (`340pt×170pt`) em toda parte
  `xl/drawings/vmlDrawing*.vml`, sem tocar `node_modules`. Chamada em `route.ts` logo após
  `workbook.xlsx.writeBuffer()`.
- **Testado:** harness `tsx` cobrindo os 9 formatos de período (todos passando), os dois fixes de
  classificação (já verificados em sessão anterior, confirmados intactos), e o round-trip do
  `ampliarNotasNoBuffer` (caixa de nota confirmada mudando de `97.8pt/59.1pt` pra `340pt/170pt` no
  XML gerado). `tsc --noEmit`, `eslint`, `next build` limpos.
- **Precisa:** re-exportar um caso real pra conferir visualmente — planilha sem nenhuma menção a
  taxonomia, período legível, notas abrindo sem corte, e as duas divergências de DRE/Combinado
  resolvidas.

### Sessão 7 (cont.¹⁶) — Tipo/período em texto natural no dashboard/planilha do documento + resumo menos redundante
Print do dono da tabela de documentos do dashboard mostrou `tipo_taxonomia` cru ("FATURAMENTO_24M",
"FLUXO_CAIXA") e período sem tradução ("outro Jan/2024 a Dez/2025", "anual 12M25") — a
`formatarPeriodo` de cont.¹⁵ só tinha sido ligada no export em Excel, não nas telas do portal.

- **Rótulo natural do tipo:** nova `formatarTipoTaxonomia` (`portal/src/lib/export.ts`) — mapa
  explícito pros 12 tipos do Kit Básico + Variáveis já usados no export (`TIPO_TAXONOMIA_LABEL`,
  igual ao pedido do dono: "Faturamento em 24 meses", "Fluxo de Caixa", "DRE", "Balanço",
  "Faturamento Intragrupo", "Contrato Social", "Mútuos", "Mapa da Dívida", "Demonstrações
  Combinadas", + Balancete/Contrato de Dívida/Fluxo Projetado no mesmo estilo); tipo fora desse mapa
  (documento complementar raro, ex. `EXTRATO_BANCARIO`) cai num fallback genérico que já tira o
  `_`/caixa alta ("Extrato Bancario") em vez do código cru — nunca pior que antes, já preparado pra
  quando entrar um tipo novo. Ligado em `casos/[id]/page.tsx` (tabela de documentos),
  `casos/[id]/documentos/[docId]/page.tsx` (cabeçalho da planilha do documento) e
  `casos/[id]/revisao/page.tsx` ("Sugestão atual").
- **Período nas mesmas telas:** `formatarPeriodo` (já existia, só usada no export em Excel) agora
  também roda nessas três telas — mesmo tratamento, um lugar só.
- **Resumo repetindo entidade/período/tipo:** o prompt da IA (`n8n/workflow.e1-ingestao.json`, nó
  "Montar Req Extração") só dizia `resumo = 2-3 frases objetivas do conteudo`, sem instruir a NÃO
  repetir o que já sai em campos próprios — daí frases como "...da Teste Indústria Ltda para os
  últimos 24 meses, de janeiro de 2024 a dezembro de 2025..." reafirmando entidade/período que já
  aparecem em colunas ao lado. Fix: instrução explícita no prompt pra focar só no conteúdo
  específico (colunas/tabelas, estrutura, achados) e nunca repetir entidade/tipo/período. **Só vale
  pra extrações novas** — resumos já gravados no banco não mudam retroativamente sem reprocessar o
  documento.
- **Testado:** harness `tsx` confirmando os 12 rótulos de tipo batendo exatamente com o pedido do
  dono, o fallback genérico, e os 6 casos de período do print reproduzidos batendo com o esperado.
  `tsc --noEmit`, `eslint`, `next build` limpos.
- **Precisa:** nenhuma migration nem redeploy do N8N automático — o workflow JSON precisa ser
  reimportado no N8N pra pegar o prompt novo (mesmo processo de sempre).

---

## 2. Decisões tomadas (por que as coisas são como são)

| Decisão | Onde está documentada |
|---|---|
| Build vs. buy: híbrido, reaproveitando infra do `clipping-news` (Supabase + N8N + Vercel) | `f0/02_build_vs_buy.md` |
| Ingestão: upload em lote via **N8N Form Trigger** (não pelo portal) | decisão explícita do dono na conversa; `n8n/README.md` |
| Motor de IA: **OpenAI API direta** (multimodal + Structured Outputs), classificação por nome primeiro (barato), fallback pra IA só quando confiança baixa | `f0/02_build_vs_buy.md` |
| Taxonomia v1: Kit Básico (8 obrigatórios) + 26 Variáveis (complementares) | `f0/03_taxonomia_reestruturacao.md` |
| Output final: **base viva + export Excel** — dado curado e rastreável, **NÃO modelagem com fórmulas prontas** (decisão reafirmada nesta sessão após dúvida do dono) | `f0/07_output_spec.md`, seção "Fora do escopo" |
| Doutrina de Autonomia: classificação nasce N1 (sugestão+revisão humana), extração nasce N0 (sombra), anti-ancoragem (nenhum número vira fato sem aceite humano explícito) | `docs/01_DOUTRINA_DE_AUTONOMIA.md` |
| RLS do Fatia 1: qualquer usuário `authenticated` vê tudo (ferramenta interna, um time) — restrição por caso é fatia futura | `db/migrations/0003_rls_e_storage.sql` |
| Upload Storage (N8N→Supabase Storage) desabilitado — bug de plataforma confirmado do node HTTP Request do N8N com binário | `n8n/README.md` § "Upload Storage — pendência conhecida" |
| E3 Classe A: casamento `chave` extraída → conceito canônico por **normalização + termos obrigatórios/excludentes** (determinístico, sem LLM); log append-only (`reconciliacao`) separado do estado acionável deduplicado (`pendencia`, chave `motivo='reconciliacao:<tipo>'`) | `db/migrations/0009_reconciliacao_e3.sql` |
| Diagnóstico de conteúdo (entidade/tipo/período/legibilidade) fundido na MESMA chamada de extração E2 (não uma chamada nova) para não aumentar custo; só preenche lacunas (entidade vazia) ou confere contra o já registrado — divergência sempre vira pendência revisável, nunca sobrescreve sozinho | `db/migrations/0010_diagnostico_e1e2.sql` |
| E4 aceite: granularidade v0 é por **documento_versao inteiro** (não célula-a-célula) — degrau mínimo que já satisfaz `status_aceite`/`aceito_por`/`aceito_em` por linha exigidos pela spec, sem construir UI de seleção linha-a-linha ainda | `db/migrations/0011_aceite_export_e4.sql` |
| Export Excel: linhas pendentes de aceite aparecem no export (visualmente distintas — âmbar+itálico), nunca são omitidas — "sugestão pendente de revisão" nunca é fato silencioso | `f0/07_output_spec.md`, `portal/src/lib/export.ts` |
| Export Excel — Balanço/Balancete/DRE/Fluxo de Caixa/Combinado: layout PADRÃO DE MERCADO com colunas entidade×período, mas classificação por SEÇÃO (não por template de nomes fixos) — cada conta mantém o rótulo original da empresa; casamento tolerante a plural/conectivo; nunca soma/calcula subtotal novo. Faturamento/Dívida/Fluxo Projetado continuam em listagem simples (já são série/tabela por natureza) | `portal/src/lib/statement-templates.ts` |

---

## 3. Próximos passos

### Decisão pendente (bloqueia o próximo passo de código)
**GATE ATUAL (atualizado pós-cont.¹⁶):** os problemas de REVISÃO/EXPORT achados no "teste v20"
(fila não fechando, vazamento entre abas, taxonomia confusa/crua na tela, período sem tradução,
2 bugs reais de classificação causando divergência de total, notas de célula cortadas, resumo
redundante) estão todos corrigidos e mergeados (PRs #39, #40, #41 — ver TL;DR no topo do arquivo).
**Falta o dono, antes de qualquer código novo:** (1) reimportar o workflow N8N atualizado (pega o
prompt novo do `resumo`); (2) re-exportar um caso real e conferir visualmente o resultado de tudo
isso junto. Depois disso, não há mais gate conhecido — a lista abaixo é de FEATURE nova, nenhuma
delas foi formalmente escolhida ainda pelo dono. Itens mais antigos da lista (reimportar pós
cont.¹³, reprocessar os 7 documentos do "teste v18", confirmar pop-up do upload) provavelmente já
foram resolvidos em sessões posteriores — confirmar com o dono antes de retrabalhar. Próximo passo
de feature é uma destas (perguntar ao dono qual prioriza):
1. **Ação de resolução na fila do portal** para pendências de reconciliação (hoje só lista;
   não tem um "confirmar/ressalva" dedicado como `fn_revisar_documento` tem para classificação
   — as pendências de diagnóstico, ao contrário, JÁ passam pela fila existente). Mais relevante
   agora que a Classe B dobrou o volume potencial de pendências de reconciliação.
2. **Análise horizontal/vertical no export** (Δ% ano-a-ano e % do total) — agora que os períodos
   viram colunas próprias (cont.⁹), é o passo seguinte pra "cara de modelo": colunas de variação
   entre anos adjacentes e % de cada conta sobre o total do grupo. Puramente aditivo ao export.
3. **Suporte a `.docx`/Word e `.xlsx` no `Preparar Conteudo`** (hoje caem em "conteudo nao
   suportado"/nota de texto) — ligar um nó *Extract From File* do N8N antes do `Preparar Conteudo`
   e mandar o texto extraído no lugar do binário. Gap real de "adaptação a arquivos diferentes"
   levantado pelo dono (não foi a causa do v15/v18, mas é legítimo).
4. **Dividir a extração por página/período pra documentos genuinamente enormes** (cont.¹¹) — a
   correção COMPLETA do truncamento residual; requer testar contra N8N vivo (mudança de topologia
   do grafo), por isso ficou fora desta rodada.
5. **Refinar a extração de `FATURAMENTO_24M`/`MAPA_DIVIDA`** (hoje schema genérico de linhas) —
   é o que faz as checagens de Classe B (e uma futura Classe A de dívida) pararem de cair em
   "precondição não satisfeita" com tanta frequência.
6. **Refinar a granularidade do aceite** (hoje é por documento inteiro) para célula/linha
   individual — o bug da sessão 7 tornou isso mais urgente: um aceite em lote é especialmente
   perigoso quando a extração pode vir contaminada/alucinada em volume.
7. **Reconciliação Classe C** (interpretativa — mapa de dívida vs. balanço, mútuos/intragrupo,
   `docs/04`) — "não reconcilia, aproxima para humano": mostra as duas fontes, humano decide.
   LLM só como hipótese explicativa de uma divergência já detectada, nunca decide.
8. **Portão 2 formal do caso inteiro** (bloqueantes não-sobrepujáveis, teto de ressalva,
   `docs/07_STATUS_E_PENDENCIAS.md`) — hoje só existe o aceite mínimo por linha extraída.

**Validar com o time de análise** (ainda pendente): se as palavras-chave de seção
(`statement-templates.ts`) cobrem o vocabulário real dos clientes da Oria — a sessão 7 usou 2
documentos reais e a classificação por seção em si funcionou bem (ver diff PDF↔export); o
problema achado foi de PIPELINE (item errado), não de vocabulário de classificação.

### Itens adiados (documentados, não bloqueantes)
- **Teto de ~4,5 MB no upload pelo portal (Vercel):** o `/api/intake` encaminha via Serverless
  Function, que limita o corpo da requisição. Lotes grandes precisam ir em levas ou pelo Form do
  N8N. Melhoria futura: upload direto do browser pro N8N/Storage (signed URL), contornando a
  Function — tira o limite e o processamento pesado da Vercel. Ver `portal/README.md`.
- **Overload morto de `fn_registrar_documento`:** achado ao testar 0009 contra Postgres local —
  a migration `0007` adicionou `p_justificativa` via `create or replace` com um parâmetro a
  mais, o que em Postgres **cria uma segunda função** (14 params) em vez de substituir a de
  `0006`, em vez de exigir `drop` antes (como `0005` fez corretamente para a mudança de tipo de
  retorno). Não quebra a produção porque o N8N sempre chama com o parâmetro nomeado
  `p_justificativa=>...`, que desambigua para a versão de 15 params — mas é lixo de schema
  (duas assinaturas da mesma função) e qualquer chamada só-posicional (ex.: um teste manual)
  fica ambígua. Limpar numa migration futura (`drop function` da assinatura de 14 params).
- **Upload Storage** ainda desabilitado — alternativas documentadas em
  `n8n/README.md`: community node `n8n-nodes-supabase`, ou mover upload pro portal via
  SDK JS do Supabase.
- **XLSX no fallback de conteúdo**: hoje só manda uma nota de texto avisando; falta
  ligar um nó *Extract From File* antes do `Preparar Conteudo`.
- **LGPD**: OpenAI API direta está fora do perímetro Azure preferido — antes de dados
  reais de cliente em produção, ativar zero-retention/DPA da OpenAI + revisão de NDA
  pelo jurídico. Migração para Azure OpenAI é trivial (mesma troca de baseURL/auth).
- **RLS por caso** (membership) — hoje é "todo autenticado vê tudo".
- **Verificação em Supabase real** dos embeds de foreign key nas queries do portal
  (`entidade`, `periodo`, `documento_versao`) — escritos conforme sintaxe documentada
  do PostgREST mas não exercitados contra um projeto real antes do deploy (agora já
  testado ao vivo pelo dono — funcionando).

---

## 4. Padrões relevantes (como este projeto é construído)

### Disciplina de teste
- Toda lógica de negócio do N8N vive em `n8n/lib/*.mjs` (testável, fonte da verdade) e
  é **espelhada manualmente** dentro das strings de código dos nós Code em
  `n8n/build-workflow.mjs` (porque nós Code do N8N não importam arquivos). Ao mudar
  lógica: mude `lib/`, rode `npm test`, regenere com `node build-workflow.mjs`.
  **Já causou um bug real** (schema sem enum) por o mirror manual ter ficado
  desatualizado — hoje o gerador importa constantes direto de `lib/` quando possível,
  em vez de copiar à mão.
- `n8n/test/workflow-sim.test.mjs` executa os códigos **reais** do JSON gerado com
  dados mock reproduzindo a semântica exata do N8N (`$input`, `$()`, `$json`,
  `this.helpers`) — pega bugs de fluxo de dados entre nós antes do dono testar ao vivo.
- Migrations SQL são sempre testadas contra um **Postgres 16 local efêmero** antes de
  entregar (rodar como usuário `postgres` do sistema via `sudo -u postgres`, criar role
  `authenticated` manualmente pra simular RLS do Supabase). Ver histórico de comandos
  nesta sessão para o padrão exato (`initdb`/cluster já vem provisionado no ambiente).

### Regras de fluxo do N8N aprendidas (não violar)
1. Node Postgres **não repassa binário** — quem precisa do arquivo lê do Form por
   referência (`$('Intake (Form)')`).
2. Node HTTP Request **substitui o item inteiro** pela resposta da API (perde
   json+binário) — contexto anterior se recupera via `$('Nome do Node').item`.
3. Code em `runOnceForEachItem` retorna **um objeto** `{json,binary?}`; em
   `runOnceForAllItems` retorna **array** (único modo que permite fan-out).
4. Binário em Code node: **nunca** ler `binary.<prop>.data` direto — usar
   `await this.helpers.getBinaryDataBuffer(itemIndex, propertyName)` (funciona em
   qualquer modo de armazenamento; ler direto só funciona por acaso no modo memória).
5. `$env` é bloqueado por padrão no N8N — não usar.
6. **`itemIndex` de `getBinaryDataBuffer` NUNCA pode ser um literal fixo** (ex.: `0`) — mesmo em
   `runOnceForEachItem`, o buffer é resolvido pelo índice do item **dentro do lote inteiro do
   node**, não por um índice "local" do item isolado. Usar `$itemIndex` (global do N8N em
   each-item mode). Um literal fixo funciona por acaso quando só há 1 item no lote (upload de 1
   arquivo por vez) e **quebra silenciosamente** com 2+ itens — cada item != 0 lê o binário do
   item 0 (nome/mimeType corretos, mas o CONTEÚDO enviado pra IA é de outro arquivo). Achado
   testando com upload de 2 arquivos reais no mesmo Form (sessão 7) — node `Preparar Conteudo` em
   `n8n/build-workflow.mjs` (plumbing do N8N, sem `lib/` próprio — não é lógica de negócio
   testável isoladamente, por isso o teste é contra o JSON gerado, `workflow-sim.test.mjs`).

### Git / PR workflow desta sessão
- Branch usada na sessão 4: `claude/ola-3a5wp0` — teve **5 PRs mergeados** a partir dela
  (#20-#24, ver acima), depois esgotada (já mergeada) — sessão 5 restartou a partir do `main`
  atualizado, como o padrão abaixo manda.
- Branch usada nas sessões 5 e 6: `claude/handoff-md-review-ywt57q`. O PR #26 (sessão 5) foi
  mergeado; a sessão 6 **restartou a branch do `main` atualizado** (`git checkout -B
  claude/handoff-md-review-ywt57q origin/main`) antes de commitar o trabalho novo — nunca empilhar
  em cima de branch cujo PR já foi mergeado. A **próxima sessão deve fazer o mesmo**: checar se o
  PR desta branch já foi mergeado e, se sim, restartar do `main`. Padrão no meio do trabalho:
  `git fetch origin main && git rebase origin/main` (ou `git checkout -B claude/<nome> origin/main`).
- Branch usada nas sessões 7-10: `claude/handoff-continuation-2oecw8` — **14 PRs mergeados** a partir
  dela (#39-#52), restartada de `origin/main` a cada vez que um PR fechava.
  **Padrão obrigatório**: quando o PR da branch é mergeado, restarte do `main` atualizado
  (`git fetch origin main && git checkout -B claude/handoff-continuation-2oecw8 origin/main`) — nunca
  empilhe em cima de histórico já mergeado.
- Branch das sessões 11-13: `claude/handoff-leitura-continuacao-jeifmd` — **2 PRs mergeados** (#54 na
  sessão 11; #55 com as sessões 12 e 13 juntas), restartada de `origin/main` a cada vez.
- Branch das sessões 14-15: `claude/handoff-continuation-orqkmn`, criada a partir do `main` já com o
  #55 mergeado; o #56 (sessão 14) saiu dela e a sessão 15 continuou na mesma branch. Mesmo padrão: quando o PR desta branch fechar, a próxima sessão restarta do `main`
  atualizado em vez de empilhar em cima de histórico já mergeado.
- **Aviso de leitura desta sessão:** ao retomar, confirme o estado do `main` com
  `git ls-remote origin main` **e** com a lista de PRs — o cabeçalho deste arquivo já ficou defasado
  duas vezes (na sessão 14 ele dizia "PR #54 em aberto" quando #54 e #55 já estavam mergeados, porque
  o commit de handoff viaja no próprio PR que muda o estado). O `git fetch origin main` do container
  pode devolver um `origin/main` velho; o `ls-remote` não mente.
- **Aviso prático desta sessão:** duas sessões editaram o mesmo cabeçalho do HANDOFF em paralelo
  (o #53 corrigiu o estado do `main` enquanto o #54 já estava aberto), e o #54 ficou em conflito.
  O cabeçalho deste arquivo é o ponto de conflito mais provável do repositório — ao retomar,
  `git fetch origin main` antes de escrever nele.
- O stop-hook local reclama dos **merge commits do próprio GitHub** (committer `noreply@github.com`),
  que aparecem na branch depois de cada merge. **Não reescreva**: já estão publicados no `main`, e
  reescrever trocaria um aviso cosmético por divergência real. Os commits de autoria própria passam.
- Todo PR é aberto como **draft**; o dono marca "ready for review" e mergeia pelo GitHub.
- O stop-hook local avisa sobre commits "Unverified" (merge commits do próprio
  GitHub) — **não são reescritos** (exigiria reescrever histórico compartilhado do
  `main`); é uma checagem esperada, não um problema real.

### Doutrina de Autonomia (aplicar em qualquer fatia nova)
- N0 = sombra (roda, mas nada é fato). N1 = sugestão + revisão humana obrigatória.
  N2 = determinístico auto-clear. N3 = autônomo.
- **Anti-ancoragem**: nenhum número/classificação sugerido por IA entra na base como
  fato sem uma `decisao` de aceite humano explícito, registrada em `decisao` +
  `evento_auditoria` (append-only).
- Todo passo de mutação de estado importante vira uma função Postgres testável (não
  lógica solta no N8N/portal) — ver `fn_registrar_documento`, `fn_recomputar_completude`,
  `fn_revisar_documento` como modelo a seguir para as funções da E3.

### Onde tudo mora
```
db/         — migrations SQL (0001-0028) + README com ordem de aplicação
              test/  — fixture do book + reconciliacao/macro/reextracao.test.sql + run.sh
n8n/        — build-workflow.mjs (gerador) + lib/ (lógica testável) + test/ + workflow.e1-ingestao.json (gerado)
              build-workflow-macro.mjs + lib/macro.mjs + workflow.macro.json — coleta de índices macro (0025),
              workflow SEPARADO que roda no relógio (dia 12); falha dele não derruba a ingestão
portal/     — Next.js (App Router) + Supabase Auth — dashboard, fila de revisão, planilha+aceite, export Excel
              src/lib/export.ts             — o motor do export (função pura buildExportWorkbook):
                                              abas de demonstração, DMPL/DVA, Macro, Modelagem, roteamento por linha
              src/lib/statement-templates.ts — classificador por seção contábil
              scripts/verificar-export.mts   — 126 invariantes de regressão do export
              scripts/lib/avaliar-formula.mts — avaliador de SUM/refs/aritmética/IFERROR
              scripts/fixtures/             — fixture do book em JSON (gerado, versionado)
f0/         — decisões estruturais da fundação (taxonomia, schema, output spec, padrão analítico)
docs/       — doutrina de autonomia, arquitetura, roadmap, reconciliação, auditoria, custo OpenAI
test-data/  — book-vertentes/ (gerador do book complexo + gabarito; PDFs não são versionados)
```

### Como validar (rodar SEMPRE antes de commitar)
```bash
node --test 'n8n/test/*.test.mjs'           # 160 testes: libs + nós REAIS do JSON gerado
node n8n/build-workflow.mjs                 # regenera workflow.e1-ingestao.json (commitar o gerado)
node n8n/build-workflow-macro.mjs           # regenera workflow.macro.json (idem)
node n8n/build-workflow-diagnostico.mjs     # regenera workflow.diagnostico-openai.json (idem)
npx tsx portal/scripts/verificar-export.mts # 198 invariantes do export
sudo -u postgres env PGHOST=/tmp PGPORT=5432 PGUSER=postgres db/test/run.sh
#   ^ reconciliação + macro + reextração + canonicalização (16) + seed macro
E2E_PSQL="sudo -u postgres psql -h /tmp -p 5432" npx tsx test/e2e/run.mts
#   ^ 18 asserts ENCADEANDO extração (nó real) -> banco (funções reais) -> export -> gabarito.
#     É a única suíte que cobre a COSTURA entre as três; as outras validam seu pedaço
#     contra fixture escrita à mão nas duas pontas, e as duas pontas podem errar juntas.
cd portal && npx tsc --noEmit && npx eslint . && npx next build
```

**Preparo de container novo** (a sessão 14 perdeu tempo nos três — rode antes de qualquer coisa):

```bash
cd portal && npm install && cd ..                    # node_modules NÃO vem no clone
cd test-data/book-vertentes && pip install reportlab && python3 gerar.py && cd ../..
# ↑ gera pdf/ + GABARITO.json, que NÃO são versionados. Sem isso o verificar-export.mts
#   morre com ENOENT no GABARITO.json — não é bug, é insumo faltando.
sudo -u postgres /usr/lib/postgresql/16/bin/pg_ctl -D /var/lib/postgresql/16/main \
  -o "-c config_file=/etc/postgresql/16/main/postgresql.conf -k /tmp -p 5432" -l /tmp/pg.log start
# ↑ o cluster já vem provisionado; sem o config_file explícito o pg_ctl falha
#   ("could not access postgresql.conf" — o Debian separa config de dados).
sudo -u postgres env PGHOST=/tmp PGPORT=5432 PGUSER=postgres db/test/run.sh
# ↑ como postgres, senão dá "Peer authentication failed" (o socket usa peer auth).
```

O `run.sh` cria os papéis `anon`/`authenticated`/`service_role` e o schema `storage` que as migrations
assumem do Supabase.

Migrations: aplicar `0001`→`0032` em ordem num Postgres 16 local antes de propor SQL novo — várias
funções são redefinidas por migrations posteriores e só a ordem completa revela o comportamento real.
O `.xlsx` do dono se lê com `python3` + `openpyxl` (`data_only=False` pra ver as fórmulas).

> **Nota para quem for continuar a E3:** `docs/04_RECONCILIACAO.md` tem o desenho conceitual
> das classes A/B/C. A Classe A (checagens 1 e 2 dos exemplos canônicos) já está construída em
> `db/migrations/0009_reconciliacao_e3.sql` — ler essa migration (e os testes ad hoc descritos
> em §1 desta sessão) antes de adicionar novas checagens ou atacar B/C do zero. **A Classe B é o
> próximo passo combinado com o dono** (sessão 6): determinística, banda de materialidade (piso
> R$ **E** % relativo, `docs/04`), teto N1; duas checagens canônicas (Receita DRE vs. soma do
> faturamento; despesa financeira vs. juros do mapa de dívida). Reaproveitar `fn_valor_conceito`
> e o padrão de pendência idempotente (`motivo='reconciliacao:<tipo>'`) da 0009.

> **Nota para quem for continuar a E4:** `f0/07_output_spec.md` é a spec travada (v0) do output
> — dois modos de entrega (base viva no portal + export Excel), schema-alvo com ordem de
> prioridade, proveniência por célula, e o princípio inegociável de anti-ancoragem. O aceite
> (`fn_aceitar_extracao`, `0011`), o export (`portal/src/lib/export.ts`) e o classificador por
> seção do Balanço/Balancete/DRE/Fluxo de Caixa (`portal/src/lib/statement-templates.ts`) já
> existem nessa primeira fatia — ler os três antes de mexer. **Importante:** não é mais um
> template de nomes de conta fixos — é um classificador por seção com palavras-chave +
> casamento tolerante a plural/conectivo (`contemFrase`/`tokensDe`). Para ampliar cobertura,
> adicionar palavras-chave nas listas (`ATIVO_CIRC_KW` etc.) em vez de tentar adivinhar nomes
> de conta exatos. Ver quantas linhas caem em "Contas Não Classificadas" com dados reais é o
> sinal mais direto de onde o vocabulário ainda precisa de mais cobertura.
>
> **Atualização sessão 6:** além das palavras-chave, o classificador agora tem um **fallback de
> IA** — a `secao_canonica` que a IA sugere na extração (`db/migrations/0012`, `n8n/lib/extract.mjs`)
> entra em `classificarConta` só quando a regra determinística abstém. Ao mexer, lembrar: o enum
> de `secao_canonica` (em `extract.mjs` → `SECAO_CANONICA_ENUM`) e as chaves de seção do
> classificador (`BALANCO_SECOES`/`DRE_SECOES`/`FLUXO_CAIXA_SECOES`) têm que permanecer IDÊNTICOS
> (não há import cruzado .mjs↔portal TS). Promover a IA a ter PRIORIDADE sobre a regra (ou
> auto-clear) é uma subida de dial que exige golden set + concordância medida (`docs/01`, `f0/06`)
> — não fazer sem isso.
