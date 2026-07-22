# Handoff — Tratamento de Dados Financeiros (Oria)

Nota de transição de contexto. Última atualização: 2026-07-22 (fim da sessão 7).

**Estado do repositório neste momento:** sessões 4, 5 e 6 já mergeadas no `main` (PRs #20-#28). A
sessão 7 achou e corrigiu um **bug crítico de dados** (não de classificação): ao testar com 2
documentos reais no MESMO upload em lote, o N8N lia o binário do item errado ao montar a chamada
de extração — o conteúdo de um arquivo era enviado pra IA com o NOME do outro arquivo (PR #29,
**mergeado**, `$itemIndex` em vez de `0` fixo + teste de regressão). Investigando os dados brutos
com o dono (query SQL no Supabase real dele), achamos uma SEGUNDA causa, independente: documentos
**combinados/multi-entidade** (várias colunas de empresa na mesma tabela, ex. Certsys Tecn/Part/
Com/Total) faziam a IA fabricar valores com confiança ALTA — o schema de extração só tinha um
`valor_num` por linha, sem dimensão de entidade. Duas fatias, ambas pedidas pelo dono (não são
excludentes): **(1) guarda de segurança** que detecta e sinaliza extração suspeita (padrão de
valores repetidos, ou confiança baixa) pra QUALQUER documento — não resolve a causa, torna visível;
**(2) `entidade_coluna` por linha** — ataca a causa raiz, deixando a IA representar corretamente
uma conta que aparece em várias colunas/entidades, sem inventar. Ver seção "Sessão 7 (cont.)"
abaixo. PR novo, pendente de revisão do dono no momento em que este arquivo foi escrito. **Ação
pendente do dono, fora do escopo de código:** existem documentos JÁ CONTAMINADOS no Supabase de
produção de uploads em lote anteriores ao fix do item errado — ver checklist de limpeza na seção
"Sessão 7". **Próximo passo (adiado duas vezes por causa destes achados): Reconciliação Classe
B** (achar inconsistências/incoerências nos números) — continua sendo o combinado, só ficou atrás
da urgência deste bug de integridade de dados.

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
  independente de qual `tipo_taxonomia` o documento levou.

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
Nenhuma no momento. O teste com caso real (sessão 7) já foi feito e achou o bug crítico do item
errado no lote (corrigido nesta sessão) — próximo passo natural é uma destas (perguntar ao dono
qual prioriza):
1. **Reforçar o prompt de extração** (`n8n/lib/extract.mjs`) com os 3 achados secundários da
   sessão 7: (a) não confundir contador/signatário com razão social quando não há entidade única
   óbvia (documento combinado de várias entidades); (b) não confundir saldo de ABERTURA (ex.:
   linha da DMPL) com o período de referência do documento; (c) diferenciar "múltiplas
   demonstrações no mesmo arquivo pra UMA entidade" (ainda é `BALANCO`/`DRE`/etc., já resolvido
   pelo roteamento por linha da sessão 6) de "demonstração combinada de um GRUPO de empresas"
   (`COMBINADO` de verdade, f0/03) — hoje a IA classificou o mesmo tipo de documento das duas
   formas em re-extrações diferentes.
2. **Construir a Reconciliação Classe B** (`docs/04`) — determinística, banda de materialidade,
   sem IA nem golden set — as duas checagens canônicas: (1) Receita da DRE vs. soma do
   faturamento mensal (`FATURAMENTO_24M`); (2) despesa financeira da DRE vs. juros do mapa de
   dívida (`MAPA_DIVIDA` — que hoje só tem schema genérico de linhas, então pode cair como
   "precondição não satisfeita" até a extração dele ser refinada). Segue o molde de
   `db/migrations/0009` (Classe A). Continua o combinado com o dono, só ficou atrás da urgência
   do bug de integridade de dados desta sessão.
3. **Refinar a granularidade do aceite** (hoje é por documento inteiro) para célula/linha
   individual — o bug da sessão 7 tornou isso mais urgente: um aceite em lote é especialmente
   perigoso quando a extração pode vir contaminada/alucinada em volume.
4. **Ação de resolução na fila do portal** para pendências de reconciliação (hoje só lista;
   não tem um "confirmar/ressalva" dedicado como `fn_revisar_documento` tem para classificação
   — as pendências de diagnóstico, ao contrário, JÁ passam pela fila existente).
5. **Mais checagens de Classe A** (ex.: soma das parcelas vs. saldo total do Mapa de Dívida —
   precisa de `MAPA_DIVIDA` sendo extraído, que hoje só tem schema genérico de linhas).
6. **Portão 2 formal do caso inteiro** (bloqueantes não-sobrepujáveis, teto de ressalva,
   `docs/07_STATUS_E_PENDENCIAS.md`) — hoje só existe o aceite mínimo por linha extraída.

**Validar com o time de análise** (ainda pendente): se as palavras-chave de seção
(`statement-templates.ts`) cobrem o vocabulário real dos clientes da Oria — a sessão 7 usou 2
documentos reais e a classificação por seção em si funcionou bem (ver diff PDF↔export); o
problema achado foi de PIPELINE (item errado), não de vocabulário de classificação.

### Itens adiados (documentados, não bloqueantes)
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
db/       — migrations SQL (0001-0014) + README com ordem de aplicação
n8n/      — build-workflow.mjs (gerador) + lib/ (lógica testável) + test/ + workflow.e1-ingestao.json (gerado)
portal/   — Next.js (App Router) + Supabase Auth — dashboard, fila de revisão, planilha+aceite, export Excel
f0/       — decisões estruturais da fundação (taxonomia, schema, output spec, build vs buy)
docs/     — doutrina de autonomia, arquitetura funcional, roadmap, reconciliação (E3 spec já existe aqui!)
```

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
