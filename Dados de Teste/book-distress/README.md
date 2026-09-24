# Book de teste — GRUPO PIRAQUARA (gerador, caso de DISTRESS)

Terceiro book do repositório (fatia F2.4 de `Arquitetura do Sistema/3 Estado e Execução/ARQUITETURA_ALVO_E_ROADMAP.md`):
**14 documentos, 3 empresas, 3 exercícios (2023, 2024, 2025)**, de um grupo fictício cuja
operacional entra em passivo a descoberto e rompe o covenant bancário no último exercício.

```bash
python3 -m pip install --quiet 'reportlab==5.0.1'
PYTHONPATH=. python3 gerar.py   # escreve ./pdf/ (14 PDFs + GABARITO.json + METRICAS.json + TEXTO_EXTRAIDO.json)
PYTHONPATH=. python3 motor.py   # só as amarrações, impressas
node ../../N8N/medir-custo-book.mjs "Dados de Teste/book-distress/pdf"   # rodando da raiz do repositório
```

## Por que existe um terceiro book

O `book-vertentes` é o caso em que a extração é fiel e nada abre pendência; o `book-canastra` é o
kit grande com as bagunças de formato (escala, locale, nome de arquivo). Nenhum dos dois tem como
caso **central** o que um mandato de reestruturação traz sempre, e é isso que este book cobre:

| | O que o book tem | Por que importa |
|---|---|---|
| PL negativo | Piraquara Metalúrgica: PL 10.641 → 11.006 → **(7.355)** | Indicador com denominador negativo, rótulo "Passivo a Descoberto", e a holding trocando investimento por **provisão** |
| Covenant rompido | Dívida Líquida/EBITDA 1,72x → 2,89x → **12,25x** (limite 3,00x) | O cálculo está no documento, parcela a parcela; 2024 passa **por pouco** |
| Consequência contábil | Todo o não circulante de empréstimos desce para o circulante em 2025 | A conta "não circulante" **não existe** em 2025 (célula vazia, não zero) |
| Aging itemizado | 12 fornecedores e 10 clientes, **rótulo = NOME do item** (`40117 - SIDERÚRGICA SERRA AZUL S.A.`), sem linha de "demais" | É o formato medido em produção — ver `.claude/memory/conceito-nao-esta-no-rotulo-de-relatorio-itemizado.md` |
| Extrato mensal | 12 meses de UMA conta, em **R$ com centavos** | O saldo final em reais arredonda para o caixa do BP em R$ mil — escala diferente de propósito |
| Despesa financeira bruta | DRE com RECEITAS FINANCEIRAS e DESPESAS FINANCEIRAS separadas, e 4 linhas de despesa | Um extrator que só pega o resultado financeiro líquido perde a despesa que o modelo projeta |
| Mútuos | 2 contratos (holding → operacional, irmã → operacional), juros capitalizados | O mesmo número nos DOIS balanços e nas DUAS DREs |
| Ressalva | Notas declaram covenant rompido e incerteza sobre continuidade; parecer **com ressalva** + parágrafo de incerteza relevante | Texto que o sistema tem de ler, não tabela |

## Como os números se sustentam

Nenhum total é digitado. O `motor.py` monta os balanços nesta ordem, e **cada passo é um `assert`**:

1. Contas declaradas + contas calculadas por contrato (empréstimos a partir de `CONTRATOS`, mútuos a partir de `MUTUOS`).
2. DRE das controladas **lida desse balanço**: depreciação, PECLD, perda em estoque, provisão para
   contingências e impairment são a variação da conta retificadora; juros bancários são a soma dos
   juros dos contratos; juros de mútuo são os da tabela de mútuos.
3. PL: 2023 é o balanço de abertura (o resultado acumulado fecha); em 2024 e 2025,
   **PL = PL anterior + resultado da DRE** (não há dividendo nem aumento de capital).
4. Disponível: 2023 declarado; em 2024 e 2025 é a conta que fecha Ativo = Passivo + PL.
5. Holding por último: MEP = PL da controlada; abaixo de zero, provisão para passivo a descoberto.

**A diferença de desenho em relação ao canastra, e por que ela é mais dura:** lá a DRE tem uma
linha de "outras receitas (despesas)" que absorve a diferença até a variação do PL. Aqui não há
linha de ajuste em lugar nenhum. A DRE é montada inteira, o PL sai dela, o caixa sai do balanço — e
aí a **DFC reconstrói a variação do caixa linha a linha**, com cada conta do balanço em exatamente um
bloco e nenhuma rubrica de "outras variações". Se alguma conta ficar de fora ou a DRE não bater com
o PL, a DFC não fecha e a geração para.

### As amarrações conferidas (números do gabarito)

> **Quais destas podem reprovar, e quais valem por construção.** "Ativo = Passivo + PL" e
> "Resultado DRE = ΔPL" são verdadeiras **por construção** (itens 3 e 4 acima: o acumulado fecha
> 2023 e o caixa fecha 2024/2025) — o `assert` delas protege o CÓDIGO do gerador, não os dados.
> Medido em 22/09/2026: somar +1 ao imobilizado de 2023 da Metalúrgica em `dados.py` NÃO reprova
> (o acumulado de 2023 absorve), e é o comportamento certo — é um book alternativo coerente. As
> amarrações que confrontam duas fontes independentes, e por isso reprovam quando uma delas
> mente, são a DFC (reconstrói o caixa conta a conta), o extrato, os agings, o mapa de dívida, os
> mútuos, a MEP e o covenant.

| Identidade | 2023 | 2024 | 2025 |
|---|---|---|---|
| Ativo = Passivo + PL — Metalúrgica | 68.321 | 74.813 | 64.045 |
| Ativo = Passivo + PL — Montagens | 12.107 | 15.067 | 17.950 |
| Ativo = Passivo + PL — Participações | 32.132 | 35.644 | 28.191 |
| Resultado DRE = ΔPL — Metalúrgica | 4.602 (sem BP 2022 para conferir) | 365 = 11.006 − 10.641 | (18.361) = (7.355) − 11.006 |
| Resultado DRE = ΔPL — Montagens | 2.946 | 3.052 | 2.985 |
| Resultado DRE = ΔPL — Participações | 7.693 | 3.499 | (14.819) |
| Caixa final da DFC = Disponível do BP | — | 1.668 (FCO 4.138 − FCI 9.357 + FCF 3.950 = −1.269) | 676 (2.218 − 1.200 − 2.010 = −992) |
| Extrato: saldo final (R$) → R$ mil = caixa do BP | — | abertura R$ 1.668.218,74 | **R$ 676.317,46 → 676** |
| Aging AP = Fornecedores do BP | — | — | 14.900 (acima de 90 dias: 3.282 = 22,0%) |
| Aging AR = Clientes brutos do BP | — | — | 24.917 (acima de 90 dias: 6.819; PECLD 4.386) |
| Mapa de dívida = empréstimos do BP | 30.100 | 31.050 | 26.040 (12.308 circulante + 13.732 reclassificado) |
| Juros do mapa = linha de juros bancários da DRE | 4.294 | 4.634 | 5.308 |
| Mútuo MUT-01/2021: ativo holding = passivo Metalúrgica | 5.403 | 7.991 | 11.079 |
| Mútuo MUT-02/2024: ativo Montagens = passivo Metalúrgica | — | 1.000 | 2.143 |
| Juros de mútuo: despesa Metalúrgica = receita holding + Montagens | 623 | 588 | 1.231 = 1.088 + 143 |
| MEP − provisão = PL da controlada (Metalúrgica) | 10.641 | 11.006 | 0 − 7.355 = (7.355) |

### Os asserts reprovam quando a história é quebrada (medido, regra 2)

Cinco mutações aplicadas ao gerador numa cópia em memória, uma por vez: **5 de 5 reprovaram**, e a
execução sem mutação passou.

| Mutação | Assert que reprovou |
|---|---|
| Tirar o impairment de 2025 (o PL vira +495) | "a Metalúrgica tem de fechar 2025 com PL negativo" |
| Mútuo da Montagens apontando para o contrato da holding | espelho do mútuo MUT-02/2024 entre os dois balanços |
| DFC sem a reversão da provisão para contingências | "DFC 2024 não fecha no caixa: -1928 != -1269" |
| Limite do covenant em 2,5x (romperia já em 2024) | covenant de 2023 e 2024 tem de estar cumprido |
| Extrato com R$ 90 mil a mais no fechamento | saldo final do extrato arredonda para o caixa do BP |

## Os 14 documentos e o que cada um testa

| # | Documento | O que testa |
|---|---|---|
| 01 | BP Metalúrgica 2025×2024×2023 | **PL negativo** com o rótulo "Passivo a Descoberto"; conta que **deixa de existir** (empréstimos não circulante em 2025) e contas que **nascem** (reclassificação, impairment, parcelamento) — célula vazia, não zero |
| 02 | DRE Metalúrgica 3 exercícios | **Despesa financeira bruta** (4 linhas) separada da receita financeira (2 linhas); impairment só em 2025; IR zero ("-") no ano de prejuízo; linha final "LUCRO (PREJUÍZO)" com sinais diferentes entre anos |
| 03 | DFC Metalúrgica 2025×2024 | Método indireto **sem linha de ajuste**; juros de mútuo capitalizados revertidos como item não caixa |
| 04–05 | BP e DRE Montagens | A irmã saudável que empresta para a operacional (mútuo ascendente entre irmãs) |
| 06–07 | BP e DRE Participações | MEP com investimento em **zero** e **provisão para passivo a descoberto**; equivalência pelo prejuízo inteiro |
| 08 | Mapa de dívida e covenant | 6 contratos com taxa contratual, custo efetivo, garantia, flag de covenant, saldo e juros; **página 2 com a apuração Dívida Líquida/EBITDA** dos três exercícios e a situação "ROMPIDO"; mútuos fora do índice por cláusula (armadilha) |
| 09 | Mútuos intragrupo | Saldo de abertura, captação, juros capitalizados e saldo final — o mesmo número nos dois balanços |
| 10 | Aging de contas a pagar | **Rótulo = fornecedor** (código + nome), 12 linhas sem "demais"; 22% acima de 90 dias, concentrado no maior credor |
| 11 | Aging de contas a receber | **Rótulo = cliente**; um cliente em recuperação judicial com 90% acima de 90 dias; total BRUTO (antes da PECLD) |
| 12 | Extrato bancário mensal | Uma conta, 12 meses, **R$ com centavos**; saldo inicial e final amarrados ao BP de 2024 e 2025 em R$ mil |
| 13 | Notas explicativas | Texto que **declara** o covenant rompido (com o índice), a incerteza sobre continuidade e o passivo a descoberto, mais um quadro de classificação dos empréstimos |
| 14 | Relatório do auditor | **Opinião com ressalva** (confirmação do maior fornecedor não obtida) + parágrafo de **incerteza relevante sobre continuidade**; sem valor monetário — verdade zero por declaração, como no canastra |

## Arquivos

| Arquivo | Papel |
|---|---|
| `dados.py` | Plano de contas das três entidades (contas-folha), contratos de dívida, mútuos, parâmetros das DREs |
| `demonstracoes.py` | DREs, covenant, mapa de dívida, mútuos, aging, extrato e DFC — todos lidos do balanço |
| `motor.py` | Monta os balanços na ordem de dependência e valida tudo por `assert` (`validar()`) |
| `render.py` | Renderização em PDF (reportlab) |
| `gerar.py` | Ponto de entrada: 14 PDFs + `GABARITO.json` + `METRICAS.json` + `TEXTO_EXTRAIDO.json` |
| `extrai.py` | Aponta para `Dados de Teste/comum/extrai.py`, a leitura de PDF compartilhada pelos books |

`METRICAS.json` e `TEXTO_EXTRAIDO.json` têm o mesmo formato dos do canastra (`"livro": "book-distress"`),
e a verdade das linhas de conta vem de `Dados de Teste/comum/contagem.py`, a mesma dos outros dois.
`node N8N/medir-regua-cobertura.mjs "<raiz>/Dados de Teste/book-distress/pdf"` já lê o book; os 14
documentos saem como **NÃO MEDIDO CONTRA PRODUÇÃO**, porque não há captura do n8n deles em
`Dados de Teste/capturas/` — isso não é "passa".

## Determinismo — ao byte

`render.py` liga `rl_config.invariant = 1`: data fixa no metadado (`D:20000101000000`) e `/ID`
derivado do conteúdo. **O canastra não faz isso**: medido em 22/09/2026, dois `gerar.py` seguidos
dele dão md5 diferente em todos os PDFs (o `/CreationDate` é a hora da execução), embora o
`METRICAS.json` fique igual. Aqui, dois `gerar.py` seguidos dão os **mesmos md5 nos 17 arquivos**
de `pdf/` (14 PDFs e os três JSON).

## O que ainda não está ligado

- **Não há fixture de extração** (o equivalente de `Supabase/test/gerar_fixture_canastra.py`), nem
  passo no CI. A integração é da sessão principal.
- Não há combinado do grupo, DMPL nem DVA: o book é deliberadamente pequeno, focado no distress. O
  canastra já cobre o combinado com eliminações.
- Tudo sai em PDF. Na vida real aging e mapa de dívida chegariam em planilha.

## Ressalvas

- Os documentos são **sintéticos** e trazem essa marcação no rodapé. Empresas, pessoas, bancos,
  CNPJ, CPF e CRC são fictícios.
- A saída (`pdf/`) **não é versionada** (`.gitignore`, igual ao canastra) — é determinística, basta rodar o gerador.
- Variações de 2023 (depreciação, PECLD, provisões) e o saldo de abertura dos contratos em 2022 são
  **declarados**, não medidos: o book não tem balanço de 2022. Estão em `dados.py` com esse aviso.
