# 0.2 — Decisão Build-vs-Buy + Dono de Operação  ·  [DECISÃO REGISTRADA]

**Objetivo:** decidir conscientemente **construir** vs **adaptar ferramenta existente**, antes
de gastar esforço de engenharia. Uma boutique com poucas mãos pode transformar um sistema
bespoke em passivo operacional. Esta decisão é registrada e assinada.

> O usuário já sinalizou preferência por **construir**. Este documento existe para tornar a
> decisão explícita e defensável — não para reabri-la sem motivo.

## O que o mercado já resolve (referência)

Firmas de M&A/Reestruturação usam **data rooms / VDRs** (ex.: categoria de Virtual Data Room)
que entregam de fábrica: upload/organização, permissionamento, versionamento e trilha de
auditoria. **Não** entregam: motor de pendências determinístico, completude contra checklist
customizado, extração estruturada, reconciliação e a Doutrina de Autonomia.

## Matriz de decisão

| Capacidade | Buy (VDR/ferramenta) | Build (nosso workflow) |
|---|---|---|
| Upload, organização, permissão, auditoria de acesso | ✅ pronto | 🔨 construir |
| Versionamento documental | ✅ pronto | 🔨 construir |
| Checklist customizado + completude determinística | ⚠️ limitado | ✅ sob medida |
| Motor de pendências tipado | ❌ | ✅ |
| Extração estruturada + confiança | ❌ | ✅ |
| Reconciliação cruzada | ❌ | ✅ |
| Doutrina de Autonomia (dial por estágio) | ❌ | ✅ |
| Custo de operar/manter | 💰 assinatura | 🧑‍🔧 tempo de time |

## Opções

- **A — Build total:** tudo nosso (Supabase/N8N/Vercel). Máximo controle, máximo custo de
  manutenção. (Preferência atual.)
- **B — Híbrido:** VDR de mercado para storage/permissão/auditoria de acesso + nosso motor de
  triagem/pendências/reconciliação por cima. Reduz o que construímos; adiciona integração.
- **C — Buy + configurar:** aceitar o que um VDR faz e desistir da Camada B. **Rejeitada** —
  mata o valor central do projeto.

## Decisão (registrada)

- **Opção escolhida:** **B — Híbrido.**
- **Justificativa (3 linhas):** A Oria já usa **Microsoft SharePoint** como VDR pago, que já
  entrega storage, permissionamento, versionamento e auditoria de acesso. Não faz sentido
  reconstruir isso. Construímos apenas a **Camada B** (o valor central): motor de triagem,
  completude contra checklist, pendências tipadas, extração estruturada, reconciliação, a
  Doutrina de Autonomia e o **output curado para o analista** — que o VDR não faz.
- **Dono de operação nomeado:** **Rodrigo Varoto** (responsável por rodar, calibrar
  thresholds, manter taxonomia e prompts, cuidar de N8N/Supabase/Vercel).
- **Orçamento de tempo do dono / semana:** _a definir_.
- **Assinado por:** Rodrigo Varoto (sócio responsável)  **Data:** 2026-07-14

## Decisão de ingestão (início manual → integração depois)

Decorrência da Opção B, registrada para não gerar ambiguidade futura:

- **Início (F1):** ingestão por **upload manual em lote no portal**. O operador sobe **todos os
  arquivos brutos de uma vez**; o sistema interpreta e organiza automaticamente cada arquivo em
  **Mandato (caso) × Empresa (entidade) × Tipo de documento × Período**. "Manual" refere-se
  **apenas à porta de entrada** — o tratamento (classificação, extração, reconciliação) é
  automático; o humano só revisa/corrige sugestões (ver Doutrina de Autonomia).
- **Fase futura:** integração automática de busca dos arquivos no SharePoint (via Microsoft
  Graph API ou Power Automate). **Não** é pré-requisito do MVP — o valor do projeto está no
  tratamento dos dados, não na forma como o arquivo chega.
- **Segurança/LGPD:** o início manual mantém o risco de integração em **zero** na F1. A escolha
  do fornecedor de OCR/IA (ver `docs/08_RISCOS.md`, risco de dependência de modelo) fica para a
  F1, com critério: contrato/DPA, **sem retenção nem treino** nos dados dos clientes,
  preferencialmente dentro do perímetro Azure já confiado (ex.: Azure OpenAI). **Pendência
  paralela:** jurídico revisar os NDAs quanto a um novo processador de dados na cadeia.

**Critério de pronto (DoD):** ✅ opção escolhida com justificativa; ✅ **um** dono de operação
nomeado; ✅ decisão assinada pelo sócio responsável. *(Orçamento de tempo semanal a definir.)*
