# Documentos de referência do dono

Material que o Rodrigo subiu como **fonte**, não como código: é insumo de leitura, e nada no
repositório lê estes arquivos por caminho. Estavam soltos na raiz e vieram para cá.

| Arquivo | O que é |
|---|---|
| `onboarding.pdf` | **O Onboarding do projeto**, 67 páginas. É o documento que o `HANDOFF.md` e o `db/README.md` citam por seção (§7.2, §7.4 …) para justificar prioridade e ordem das fases. Quando uma decisão aqui diverge dele, o `HANDOFF.md` registra a divergência e o motivo — ver "O Onboarding está desatualizado em dois pontos (decisão do dono)". |
| `modelo-base.xlsx` | **O "Modelo Base"**, a planilha de referência universal do dono. É o que `portal/src/lib/modelo-institucional.ts` reconstrói — mesmos nomes de aba e mesma estrutura de 14 abas. Serve para conferir o que o export gera contra o que o dono espera ver. |

## As extensões foram acrescentadas de propósito

Os dois chegaram **sem extensão** (`Modelo Base` e `Onboarding`, ambos na raiz). Não é detalhe
cosmético: sem `.xlsx`/`.pdf` o arquivo não abre com duplo clique, o navegador do GitHub não
mostra pré-visualização, e qualquer ferramenta que decida por extensão trata os dois como binário
opaco. O conteúdo não mudou — só o nome. Conferido antes de mover: o `.xlsx` é `Microsoft Excel
2007+` e o `.pdf` tem as **67 páginas** que o `HANDOFF.md` afirma.

**Nada foi renomeado às cegas:** `grep` no repositório inteiro antes do `git mv` confirmou que
nenhum script, teste ou código referencia estes arquivos por caminho — as menções em
`HANDOFF.md`, `db/README.md`, `f0/` e `portal/src/lib/modelo-institucional.ts` são citações ao
**documento** ("§7.4 do Onboarding", "reconstrução do Modelo Base"), não ao arquivo.
