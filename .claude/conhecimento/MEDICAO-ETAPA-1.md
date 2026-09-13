# A medição da Etapa 1 — contra a linha de base, não contra a expectativa

**Medido em 13/09/2026**, logo depois de o `indexar.mjs` e o `buscar.mjs` existirem, com
`bash .claude/conhecimento/medir.sh`. As cinco perguntas são as mesmas de `BASELINE.md`.

| # | Pergunta | `grep` hoje | Briefing | Redução |
|---|---|---|---|---|
| 1 | Por que a cadência da extração é 73 s? | 1.442 B | 2.054 B | **pior (+42%)** |
| 2 | Quem chama `fn_reconciliar_caso`? | 5.152 B | 738 B | −86% |
| 3 | O que já se tentou no upload de lote grande? | 6.111 B | 3.022 B | −51% |
| 4 | Qual portão prova o invariante do Kit Básico? | 7.820 B | 2.701 B | −65% |
| 5 | Qual migration criou `fn_instalacao_conferir`? | 29.720 B | 686 B | −98% |
| | **soma** | **50.245 B** | **9.201 B** | **−82%** |

**O critério de pronto era "cada uma abaixo de 4.000 bytes, sem precisar abrir arquivo para
saber onde olhar".** As cinco passaram.

## A linha que ficou PIOR, e por que ela fica registrada

A pergunta 1 custa mais pelo briefing do que pelo `grep`. O motivo é honesto e vale mais do que
o número: **"73" e "cadência" casam em muitos nós, e nenhum deles carrega a CONTA.** A conta
(`TPM ÷ (entrada + reserva de saída)`) vive num comentário de `espera-do-lote.ts`, e o índice
sabe apontar o arquivo — não sabe responder.

Isso não é defeito do índice: é a fronteira exata entre o que se DERIVA e o que se ESCREVE.
O que responde a pergunta 1 é uma ficha `numero`, com a conta e a âncora em
`SEGUNDOS_POR_DOCUMENTO` — e é o que a Etapa 3 entrega. A medição volta a ser feita lá.

E o comparativo acima é conservador: ele compara só com o `grep`. As respostas 1, 3, 4 e 5
exigiam, além do `grep`, abrir arquivos que somam **60.178 bytes** (`BASELINE.md`). O briefing
não exige nenhum.

---

## O fecho, depois da Etapa 3 (mesmo dia)

A pergunta 1 ganhou a ficha que faltava (`fichas/cadencia-da-extracao-73s.md`, com a conta, as
três vezes em que ela errou, e o que a muda). O briefing passou a devolver **2.376 bytes** — e a
PRIMEIRA linha agora é a ficha que responde, não o arquivo que contém a resposta.

O número em bytes ficou parecido; o que mudou foi outra coisa, e é a que importa: antes era
preciso ler 21.372 bytes de `espera-do-lote.ts` para achar a conta, e agora são ~3.000 bytes de
ficha. **A comparação honesta da pergunta 1 é 21.372 → 3.000**, não 1.442 → 2.376.

### A âncora, medida não-vazia (regra 2)

Com `SEGUNDOS_POR_DOCUMENTO` trocado de 73 para 31, `conferir.mjs` reprova com **1 assert**,
nomeando a ficha e os dois hashes:

```
✗ fichas/cadencia-da-extracao-73s.md: SUSPEITA — a região
  portal/src/lib/espera-do-lote.ts#SEGUNDOS_POR_DOCUMENTO mudou desde a confirmação
  (c7a9e448b0e0 → 7fe7ba46540e)
```

Religado: 51 verificações, 0 falhas. **É este assert que torna o conhecimento auto-invalidante**
— o que nenhum vault de Markdown e nenhum banco de grafo entregam sozinhos.
