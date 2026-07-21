# Handoff — Tratamento de Dados Financeiros (Oria)

Nota de transição de contexto. Última atualização: 2026-07-21 (sessão 4).

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
Nenhuma no momento. Próximo passo natural é uma destas (perguntar ao dono qual prioriza):
1. **Testar o export com um caso real** do dono (aplicar `0011`, subir documentos reais,
   aceitar algumas linhas na tela de planilha, baixar o `.xlsx` e abrir de verdade no
   Excel/LibreOffice — só foi testado reabrindo com `exceljs`, não com um programa de planilha
   de verdade; e a busca via Supabase da rota `/export` não foi exercitada contra um projeto
   real ainda, só a classificação/montagem do workbook em si). **Validar com o time de
   análise** se as palavras-chave de seção (`statement-templates.ts`) cobrem o vocabulário real
   dos clientes da Oria — foram montadas por bom senso contábil (CPC/prática de mercado) e
   testadas com nomenclaturas fictícias variadas, não com documentos reais de clientes.
   Vocabulário genuinamente novo (setor muito específico, gíria de outra região) pode cair em
   "Contas Não Classificadas" até alguém ampliar as listas de palavras-chave.
2. **Refinar a granularidade do aceite** (hoje é por documento inteiro) para célula/linha
   individual, se o dono achar o aceite em lote grosseiro demais na prática.
3. **Ação de resolução na fila do portal** para pendências de reconciliação (hoje só lista;
   não tem um "confirmar/ressalva" dedicado como `fn_revisar_documento` tem para classificação
   — as pendências de diagnóstico, ao contrário, JÁ passam pela fila existente).
4. **Mais checagens de Classe A** (ex.: soma das parcelas vs. saldo total do Mapa de Dívida —
   precisa de `MAPA_DIVIDA` sendo extraído, que hoje só tem schema genérico de linhas).
5. **Portão 2 formal do caso inteiro** (bloqueantes não-sobrepujáveis, teto de ressalva,
   `docs/07_STATUS_E_PENDENCIAS.md`) — hoje só existe o aceite mínimo por linha extraída.

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

### Git / PR workflow desta sessão
- Branch de trabalho desta sessão: `claude/ola-3a5wp0` (a anterior,
  `claude/project-workflow-overview-ga323d`, já foi mergeada — não empilhar mais nada nela).
- Todo PR é aberto como **draft**; o dono marca "ready for review" e mergeia pelo
  GitHub. Depois de cada merge, a próxima sessão deve restartar sua branch a partir do
  `main` atualizado antes de continuar.
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
db/       — migrations SQL (0001-0011) + README com ordem de aplicação
n8n/      — build-workflow.mjs (gerador) + lib/ (lógica testável) + test/ + workflow.e1-ingestao.json (gerado)
portal/   — Next.js (App Router) + Supabase Auth — dashboard, fila de revisão, planilha+aceite, export Excel
f0/       — decisões estruturais da fundação (taxonomia, schema, output spec, build vs buy)
docs/     — doutrina de autonomia, arquitetura funcional, roadmap, reconciliação (E3 spec já existe aqui!)
```

> **Nota para quem for continuar a E3:** `docs/04_RECONCILIACAO.md` tem o desenho conceitual
> das classes A/B/C. A Classe A (checagens 1 e 2 dos exemplos canônicos) já está construída em
> `db/migrations/0009_reconciliacao_e3.sql` — ler essa migration (e os testes ad hoc descritos
> em §1 desta sessão) antes de adicionar novas checagens ou atacar B/C do zero.

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
