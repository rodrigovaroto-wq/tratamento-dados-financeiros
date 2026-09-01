# O texto que o `Extrair Texto` produziu no ARAUCÁRIA — 2 dos 190

## Por que estes dois arquivos existem

O `PLANO_LINHA_A_LINHA.md` põe a **Fase 0 — provar o denominador** como bloqueio de tudo:
a rodada de 01/09 deixou três pendências de cobertura (`002`, `175`, `055`), e os números que
as sustentam (97, 150 e 20 linhas de conta no texto) saem da régua `linhasDeConta`, **calibrada
contra o `book-canastra`**. O araucária é um book externo, sem gabarito neste repositório, e
ninguém tinha conferido se a régua vale nele.

Estes dois documentos são a primeira medição contra texto de produção do araucária.

## O que eles provaram

| documento | linhas brutas | depois da emenda | régua | conferência linha a linha |
|---|---|---|---|---|
| `020_Balanco_Patrimonial_Comparativo_Araucaria_Florestal_2025x2024` | 56 | 56 | **44** | **exato** — 44 contas |
| `090_Balancete_Analitico_Araucaria_Comercial_2023` | 82 | **36** | **24** | **exato** — 23 contas + a linha de TOTAIS |

**Zero falso positivo e zero falso negativo nos dois.** A régua excluiu corretamente o cabeçalho
de página, a razão social, o CNPJ, o título, a linha "(Valores expressos…)", o cabeçalho de
colunas `31/12/2025 31/12/2024`, a nota de rodapé e o bloco de assinatura.

E o `090` é o caso que importava: **ele chega FRAGMENTADO** — código, nome da conta e saldo em
pedaços separados —, que é a forma que a sessão 77 descobriu em produção e que inflava a régua
de 99 para 258 no Canastra. Aqui `juntarFragmentosDeLinha` fez o serviço: 82 linhas brutas
viraram 36, e as 23 contas saíram inteiras (`"1.1.01.001 Numerário disponível 2.880 D"`).

## O que eles NÃO provam, e é o que ainda falta

**Nenhum dos dois é um dos três documentos com pendência**, e nenhum é um **COMBINADO**.

Isso importa porque a Fase 0 mediu, no `book-canastra`, que a régua conta **A MENOS** justamente
em COMBINADO (`13`/`14_Balanco_COMBINADO`: verdade 15, régua 10, −33%) — e o
`055_Balanco_Patrimonial_COMBINADO_Grupo_Araucaria_2023` é o pior dos três (13 devolvidas para
20 no texto). Se o viés se repetir ali, o denominador dele não é 20 e sim da ordem de 30, e a
cobertura não é 65% mas perto de 43%.

Estes dois documentos **aumentam muito** a confiança de que 97 e 150 estão certos — são um
balanço e um balancete, as duas famílias dos documentos `002` e `175`. **Não dizem nada sobre o
`055`.**

Para fechar a Fase 0 faltam os textos de `002`, `175` e — o que mais importa — **`055`**.

## Procedência

| | |
|---|---|
| Book | araucária — externo, **não versionado aqui** |
| Rodada | 01/09/2026, 190 documentos, 13.703 linhas extraídas |
| Nó | `Extrair Texto` |
| Capturados | **2 de 190** |
| Como chegou | colados pelo dono no chat, a partir da saída do nó no n8n |

Os documentos se declaram sintéticos no próprio corpo (*"Documento sintético, gerado para teste
de sistema. Não corresponde a empresa, pessoa ou fato real."*), então versioná-los não expõe
dado de cliente.
