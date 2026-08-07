# Book de teste — GRUPO CANASTRA (gerador)

Segundo book do repositório: **38 documentos, 6 empresas, 3 exercícios (2023, 2024, 2025)**, de um
grupo industrial fictício em deterioração progressiva.

```bash
pip install reportlab
PYTHONPATH=. python3 gerar.py    # escreve ./pdf/ (38 PDFs + GABARITO.json + METRICAS.json + GUIA_DE_TESTE.md)
node ../../n8n/medir-custo-book.mjs   # quanto o lote custaria na OpenAI, sem gastar nada
```

Leia o `pdf/GUIA_DE_TESTE.md` gerado: ele traz a história do grupo, o que cada documento estressa, o
gabarito e as 15 armadilhas deliberadas.

## Por que existe um segundo book

O `book-vertentes` continua valendo — ele é o insumo do `verificar-export`, do `db/test` e do e2e, e
representa o caso em que **a extração é fiel e nada deve abrir pendência**. O que ele não representa
é a dificuldade da produção, e a sessão 40 mostrou o preço disso: a fixture era mais fácil que o
arquivo real (custo positivo, uma conta por grupo, um exercício, nenhum total informado), e por isso
15 asserts passavam verdes enquanto o `.xlsx` entregue trazia a DRE dizendo o contrário do documento.

| | `book-vertentes` | `book-canastra` |
|---|---|---|
| Exercícios | 2 | **3** — o comparativo tem três colunas e a série do modelo, três pontos realizados |
| Empresas | 5 | **6**, uma delas fornecedora das outras (verticalização) |
| Documentos | 14 | **38** |
| Tipos documentais | 8 | **16** — aging AR/AP, estoque com quantidade, situação fiscal, contingências, folha, imobilizado, razão, certidões, organograma, parecer, contrato social |
| Conta que nasce/morre no meio do histórico | não | **sim** — antecipação de recebíveis, parcelamento, direito de uso, reserva consumida |
| Nomes de arquivo | todos na notação de f0/03 | **metade como o cliente manda** (ano solto, sem período, `Doc1.pdf`) |
| Lote cabe no teto de gasto | sim | **não — e é isso que ele mede** |

## Como os números se sustentam

Nenhum total é digitado. O `motor.py` soma as contas-folha e resolve a conta de resultados
acumulados para que **Ativo = Passivo + PL** nas seis empresas, nos três exercícios e no combinado
dos três — com `assert` em cada passo. A partir daí, cada documento anexo LÊ o balanço:

| Documento | O total dele é… |
|---|---|
| DRE | resultado = variação do PL do próprio balanço; depreciação, PECLD e provisões = variação das contas retificadoras |
| DFC | caixa final = subgrupo Disponível |
| DMPL | os três saldos = os três PLs |
| Mapa de dívida | soma dos saldos = dívida bancária; soma dos juros = despesa financeira da DRE |
| Aging AR / AP | duplicatas a receber brutas / fornecedores sem intragrupo |
| Estoques | subgrupo Estoques, provisão inclusa |
| Situação fiscal | contas de parcelamento do circulante e do não circulante |
| Contingências | provisões do não circulante (só o prognóstico *provável*) |
| Imobilizado | custo e depreciação acumulada, rateados por classe |
| Extrato bancário | subgrupo Disponível |
| Razão | saldo final = `Fornecedores nacionais` |

A **única** divergência é deliberada e está no gabarito: a planilha de mútuos traz R$ 240 mil a menos
que o balanço, para o sistema ter o que mostrar a um humano.

### Duas escolhas de projeto que diferem do primeiro book

1. **Não há calibração por PL-alvo.** No `book-vertentes` o passivo inteiro é multiplicado por um
   fator até o PL cair num alvo. Com dois exercícios isso passa; com três, o fator vira distorção
   ENTRE anos — uma conta que cresce no plano de contas pode decrescer no balanço só porque o fator
   daquele ano é menor, e o histórico é o insumo do modelo. Aqui o PL é o que a composição produz.
2. **Número quebrado vem de ruído determinístico pelo RÓTULO da conta**, não do fator. Como o hash é
   do rótulo e não do par (rótulo, ano), conta que não se mexe (terreno, capital social) fica com o
   mesmo saldo nos três exercícios, e conta que cresce continua crescendo. Saldos intragrupo ficam
   **fora** do ruído: as duas pernas têm de casar no centavo, senão a eliminação do combinado
   acusaria uma divergência que ninguém escreveu.

## Arquivos

| Arquivo | Papel |
|---|---|
| `dados.py` | Plano de contas por entidade, com os valores dos três exercícios (contas-folha; nenhum total) |
| `motor.py` | Subtotais, ruído determinístico, MEP, eliminações do combinado + **asserts** |
| `demonstracoes.py` | DRE, DFC, DMPL, DVA, faturamento, dívida, mútuos, aging, estoques, fiscal, contingências, imobilizado, folha, extratos, razão, balancete — todos amarrados ao balanço |
| `render.py` | Renderização em PDF (reportlab), e onde moram as bagunças de FORMATO (escala, sinal, locale, marca d'água) |
| `gerar.py` | Ponto de entrada: 38 PDFs + `GABARITO.json` + `METRICAS.json` + `GUIA_DE_TESTE.md` |
| `extrai.py` | Utilitário: extrai o texto de um PDF gerado (`python3 extrai.py pdf/01_....pdf`) |

## O que ainda não está ligado

O book gera os PDFs, o gabarito e a medição de custo. **Ele ainda não tem fixture de extração** —
isto é, o equivalente do `db/test/gerar_fixture.py`, que converte o book em linhas de
`campo_extraido` para o `db/test`, o `verificar-export` e o e2e rodarem contra ele. Essa é a fatia
seguinte, e ela é maior do que parece: a fixture do `book-vertentes` afirma extração FIEL (zero
pendência), enquanto a graça deste book é o contrário — as pendências que as escalas, o locale anglo
e os prognósticos de contingência DEVEM abrir são o resultado esperado, e cada uma precisa de assert
próprio.

## Ressalvas

- Os documentos são **sintéticos** e trazem essa marcação no rodapé. Nomes de empresas, pessoas,
  CNPJ, CRC e OAB são fictícios.
- A saída (`pdf/`) **não é versionada** — é determinística, basta rodar o gerador.
- Tudo sai em PDF, inclusive mapa de dívida, aging e faturamento, que na vida real chegariam em
  planilha. Quando o suporte a `.xlsx`/`.docx` entrar no `Preparar Conteudo`, vale gerar essas peças
  em `.xlsx` para exercitar aquele caminho.
