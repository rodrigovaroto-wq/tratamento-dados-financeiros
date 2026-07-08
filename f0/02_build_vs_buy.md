# 0.2 — Decisão Build-vs-Buy + Dono de Operação  ·  [PREENCHER]

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

## Decisão (preencher)

- **Opção escolhida:** _______
- **Justificativa (3 linhas):** _______
- **Dono de operação nomeado:** _______ (responsável por rodar, calibrar thresholds, manter
  taxonomia e prompts, cuidar de N8N/Supabase/Vercel)
- **Orçamento de tempo do dono / semana:** _______
- **Assinado por:** _______  **Data:** _______

**Critério de pronto (DoD):** opção escolhida com justificativa; **um** dono de operação
nomeado com tempo alocado; decisão assinada pelo sócio responsável.
