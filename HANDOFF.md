# Handoff — Tratamento de Dados Financeiros (Oria)

Nota de transição de contexto. Última atualização: 2026-07-21.

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

**Fatia 3 (E3 — Reconciliação): NÃO iniciada.** Decisão pendente do dono sobre como
começar (ver §3).

**Fatia 4 (E4 — Output + Portão 2): NÃO iniciada.** Depende da E3.

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

---

## 3. Próximos passos

### Decisão pendente (bloqueia o próximo passo de código)
O dono foi perguntado como prefere começar a **Fatia 3 (E3 — Reconciliação)**:
1. Já começar direto pela **Classe A** (checagens aritméticas determinísticas — ex.:
   Ativo = Passivo + PL no Balanço, Receita − Custos = Resultado na DRE) — recomendação
   dada (maior valor, menor risco, gera pendências objetivas).
2. Ver um plano detalhado da E3 antes de qualquer código.

**Aguardando resposta do dono para prosseguir.**

### Depois da E3 (ordem sugerida)
- **Fatia 4 (E4 — Output + Portão 2):** base viva no portal com proveniência por
  célula (`f0/07_output_spec.md`) + export Excel + regra determinística do Portão 2
  (aceite humano formal antes de um número virar fato).

### Itens adiados (documentados, não bloqueantes)
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
- Branch de trabalho: `claude/project-workflow-overview-ga323d`.
- Todo PR é aberto como **draft**; o dono marca "ready for review" e mergeia pelo
  GitHub. Depois de cada merge: `git fetch origin main && git checkout -B
  claude/project-workflow-overview-ga323d origin/main` pra ressincronizar.
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
db/       — migrations SQL (0001-0008) + README com ordem de aplicação
n8n/      — build-workflow.mjs (gerador) + lib/ (lógica testável) + test/ + workflow.e1-ingestao.json (gerado)
portal/   — Next.js (App Router) + Supabase Auth — dashboard e fila de revisão
f0/       — decisões estruturais da fundação (taxonomia, schema, output spec, build vs buy)
docs/     — doutrina de autonomia, arquitetura funcional, roadmap, reconciliação (E3 spec já existe aqui!)
```

> **Nota para quem for atacar a E3:** `docs/04_RECONCILIACAO.md` já existe e
> provavelmente tem o desenho conceitual das classes A/B/C — ler antes de desenhar a
> migration/lógica do zero.
