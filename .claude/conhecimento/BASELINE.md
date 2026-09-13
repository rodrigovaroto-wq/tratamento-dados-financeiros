# A linha de base — medida ANTES de existir índice nenhum

> Este arquivo existe por causa da regra 2 e da regra 7. Sem um número de ANTES, "o índice
> melhorou a recuperação" é opinião — e um índice que devolve pouco tem exatamente a mesma
> aparência de um índice que procurou e não achou.
>
> **Medido em 13/09/2026, no commit `7e9066a`.** Quem repetir a medição usa `medir.sh`, ao lado
> deste arquivo: ele roda os MESMOS comandos e imprime a mesma tabela.

## As cinco perguntas

Não são hipotéticas: as cinco já foram feitas em sessões passadas deste repositório, e as cinco
custaram tempo.

| # | Pergunta | Por que ela é cara |
|---|---|---|
| 1 | Por que a cadência da extração é 73 s? | A conta (TPM ÷ entrada + reserva de saída) vive só num comentário |
| 2 | Quem chama `fn_reconciliar_caso`? | Portal, workflow e testes citam o nome; nenhum índice liga os três |
| 3 | O que já se tentou no upload de lote grande? | A resposta está em prosa, em três arquivos, sem chave de busca |
| 4 | Qual portão prova o invariante do Kit Básico? | A ligação suíte↔invariante só existe dentro dos comentários do CI |
| 5 | Qual migration criou `fn_instalacao_conferir`? | 109 arquivos numerados até 0164, com buracos na numeração |

## O custo hoje, em bytes

`grep` é o que a sessão roda primeiro. "Arquivo a abrir" é o que ela precisa LER depois para de
fato responder — e é a parte que domina.

| # | Bytes do `grep` | Linhas | Arquivo que ainda precisa ser aberto | Bytes do arquivo |
|---|---|---|---|---|
| 1 | 1.442 | 13 | `portal/src/lib/espera-do-lote.ts` | 21.372 |
| 2 | 4.936 | 34 | — (o grep responde, mas só depois de ler 34 linhas de resultado) | — |
| 3 | 6.111 | 46 | `HANDOFF.md` (parcial) | 476.884 |
| 4 | 7.820 | 53 | `.github/workflows/suites.yml` | 22.759 |
| 5 | 29.564 | 45 | `Supabase/migrations/0131_instalacao_que_se_declara.sql` | 16.047 |

**Soma do `grep`: 49.873 bytes.** Somados os arquivos que as respostas exigem abrir (sem o
HANDOFF inteiro, que ninguém lê): **+ 60.178 bytes**.

## O critério de pronto da Etapa 1

`buscar.mjs` responde as cinco **em um comando cada**, e o resultado de cada uma cabe em
**menos de 4.000 bytes** — sem a sessão precisar abrir nenhum dos arquivos acima para saber
ONDE olhar. O número medido depois da Etapa 1 fica em `MEDICAO-ETAPA-1.md`.

Se a medição depois não bater essa marca, a decisão honesta é parar na Etapa 1 e dizer que
não valeu — não seguir para as etapas seguintes porque o plano dizia que sim.
