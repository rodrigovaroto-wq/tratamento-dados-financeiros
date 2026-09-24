---
name: impeccable-removido
description: a skill impeccable 4.1.1 (148 arquivos, 3,2 MB, design de frontend de terceiros) foi REMOVIDA do repositório em 24/09/2026 junto com os seus dois hooks — custava ~1,1 KB em toda sessão e 279 B a cada edição de .tsx, usava npx e telemetria; a fonte do design do portal é o DESIGN.md
tipo: doutrina
toca:
  - Arquitetura do Sistema/7 Marca/DESIGN.md
  - Arquitetura do Sistema/7 Marca/PRODUCT.md
---

# impeccable 4.1.1: removido do repositório

Entrou em 02/09/2026 no merge do PR #196 (`a1f010b`), como cópia inteira em
`.claude/skills/impeccable/` (148 arquivos, 3.255.891 bytes, Apache 2.0), mais dois hooks em
`.claude/settings.local.json` e a configuração em `.impeccable/`. Foi usado de verdade em
22–24/08 (as exceções de fonte do `config.json` e o `design.json`), e nada no repositório o
citava depois disso: 0 ocorrências no CI, no grafo, nas fichas e no `CLAUDE.md`.

## Por que saiu (auditoria de 24/09/2026, pedido do dono)

- **Custo fixo em toda sessão:** a `description` + `argument-hint` da skill (~1,1 KB) — cerca de
  60% de todo o texto sempre carregado de agentes e comandos juntos.
- **Custo por edição:** o hook `PostToolUse` rodava em todo Edit/Write (~85 ms) e injetava 279 B
  a cada `.tsx` editado, mesmo com o arquivo limpo; o `Stop` rodava ao fim de cada resposta.
- **Contradições com a casa:** `SKILL.md` liberava `Bash(npx impeccable *)` — a regra do `npx` no
  `CLAUDE.md` existe porque ele baixa a última versão publicada no dia; *"Go all out… Dream big and
  bold"* contra o degrau 7 da escada; `context.mjs` consultava `impeccable.style/api/version` a
  cada boot e `concept-seed.mjs` mandava telemetria.
- **Provável defeito:** o `context.mjs` procurava o `PRODUCT.md` na raiz, em `.agents/context` e
  em `docs`, nunca em `Arquitetura do Sistema/7 Marca/` — a skill provavelmente carregava sem o
  contexto do produto. Não confirmado rodando.

## O que ficou, e onde está o que ele guardava

- **A fonte do design do portal é `Arquitetura do Sistema/7 Marca/DESIGN.md`** (paleta papel /
  tinta / terracota, tipografia, componentes). O `.impeccable/design.json` era o arquivo auxiliar
  da ferramenta, derivado dele.
- As duas exceções de fonte do `config.json` (Fraunces e Inter Tight "são a marca de produção da
  Oria, medida em oriapartners.com") são identidade do cliente, e o `DESIGN.md` já a fixa.
- `PRODUCT.md` ficou; só saiu o marcador `<!-- impeccable:product-schema 1 -->`.

## Se alguém quiser de volta

Não copiar a pasta para dentro do repositório de novo. Instalar como plugin no escopo do usuário
e desligá-lo aqui em `enabledPlugins`, como o superpowers — ou ligar só na sessão que for fazer
trabalho de interface. Versão nova é caso de reauditoria contra as sete regras.
