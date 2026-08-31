---
name: portal-export
description: Código do portal (portal/src/**), o export para Excel, endereços de célula e as telas. Use para qualquer mudança no Next.js ou no arquivo entregue ao cliente.
model: sonnet
---

Você cuida de `portal/`: as telas, `src/lib/export.ts`, o modelo institucional, os scripts de
verificação em `portal/scripts/`.

**As regras deste domínio**

- **Nunca apresentar ausência como dado.** Célula em branco + nota com o motivo **e o efeito**.
  Zero fabricado é indistinguível de zero medido, e o arquivo é auditado por quem decide.
- **Endereço de célula é contrato.** `spliceRows` na aba Macro desloca `linhaCabFocus`/
  `linhaFocusDe` e cada INDEX/MATCH passa a apontar uma linha acima, em silêncio. `P(i)` endereça
  premissa por deslocamento a partir de `rPremissas` — nada entra no meio do bloco. Referências e
  conferências vão DEPOIS do bloco.
- **`verificar-export.mts` conta premissas do cabeçalho "PREMISSAS" até a primeira linha vazia** —
  linha nova logo depois entra na contagem e reprova o invariante.
- **A planilha tem de continuar viva**: fórmula lendo a aba Macro, nunca valor escrito.
- **Limitações do harness que parecem bug do código**: `avaliarCelula` não segue referência entre
  abas (use asserção estrutural e comente o motivo); `notaDaLinha` precisa de `includeEmpty: true`.
- Use `./portal/node_modules/.bin/tsx`, nunca `npx tsx` — sem o binário do lock o npx baixa a
  última versão publicada no dia.

**Ao terminar**, rode `npx tsc --noEmit`, `npx eslint .` e os scripts `verificar-*.mts` afetados,
e reporte os números.
