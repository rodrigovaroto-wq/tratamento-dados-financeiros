# Plano — nenhuma linha faltando, nenhuma linha inventada

> Pedido do dono, 01/09/2026, depois da rodada do araucária: *"NÃO PODE PASSAR NENHUMA LINHA
> FALTANDO DADOS OU EXCEDENDO/CRIANDO DADOS, faça um planejamento de como acabar com esse
> problema de uma vez por todas."*

## 1. O que a rodada do araucária mediu, e o que ela NÃO mediu

A régua corrigida na sessão 77 fez o que prometia: **as pendências de cobertura caíram de 23
para 3**. As 20 que sumiram eram falsos positivos do denominador inflado pela fragmentação.

As 3 que sobraram, com os instrumentos da `0156` respondendo:

| Documento | linhas no texto | devolvidas | cobertura | blocos |
|---|---|---|---|---|
| `002_Balanco_Patrimonial_Araucaria_Serraria_2025x…x2021.pdf` | 97 | 68 | 70% | **3 de 3 chegaram** |
| `175_Demonstracoes_Contabeis_…_Serraria_2021_reemissao_2.pdf` | 150 | 102 | 68% | **2 de 2 chegaram** |
| `055_Balanco_Patrimonial_COMBINADO_Grupo_Araucaria_2023.pdf` | 20 | 13 | 65% | **1 de 1** |

**Zero `FALTOU BLOCO` no arquivo inteiro.** Não é bloco perdido e não é fatiamento que não
rodou — as duas hipóteses que a sessão 74 levantou estão descartadas. E não é teto do modelo:
o `055` tem 20 linhas de conta, que não chegam perto do teto de 16.384 tokens de saída, e ainda
assim devolveu 13.

**O QUE NÃO FOI MEDIDO, e é a primeira coisa do plano:** o araucária **não tem gabarito neste
repositório**. Os books versionados são o `book-canastra` e o `book-vertentes`; o araucária é
externo. Então os números 97, 150 e 20 vêm de `linhasDeConta` — uma régua calibrada contra 20
documentos do Canastra — e **ninguém conferiu se eles são verdade neste book**. Enquanto isso
não for feito, "sub-extração real" é hipótese bem-fundamentada, não fato medido. A regra 4 do
projeto é explícita: *nunca inventar fixture para provar bug de produção*.

## 2. A causa raiz não é o modelo — é o CONTRATO

O contrato de extração de hoje é **inverificável por construção**.

O modelo recebe um bloco de texto e a instrução *"Extraia TODAS as linhas financeiras"*, e
devolve uma lista de grupos com linhas. A linha extraída tem `k` (rótulo), `vt` (valor_texto),
`vn` (valor_num) e `cf` (confiança). **Não tem procedência.** `op` (origem_pagina) existe, e é
do GRUPO, não da linha.

Disso decorrem as duas falhas que o dono nomeou, e nenhuma delas é acidente:

| | Hoje | Por quê |
|---|---|---|
| **Linha faltando** | detectada como SUSPEITA (razão < 85%) | comparar duas contagens nunca prova completude; só levanta dúvida |
| **Linha inventada** | **não detectada de forma alguma** | nada liga a linha devolvida a um lugar do texto de origem |

Não existe sistema de coordenadas comum entre o texto que entra e as linhas que saem. Sem ele,
nenhuma afirmação da forma *"a linha 42 do documento virou esta conta"* pode ser feita — nem
pelo modelo, nem pela guarda. A régua, o limiar de 85% e o instrumento de blocos são todos
substitutos trabalhando em volta dessa coordenada que falta.

**E o projeto já provou a solução, no lugar ao lado.** O `SYSTEM_PROMPT` cobra dos `fatos`:

> *"REGRA DA EVIDÊNCIA, e ela é obrigatória: `tr` tem de ser o TRECHO LITERAL do documento —
> copiado, não reescrito, não resumido, com no mínimo 20 caracteres. […] Um item cujo `tr` seja
> um resumo seu, ou uma paráfrase, é DESCARTADO na gravação e o fato se perde."*

Isso existe para o fato material e **não existe para a linha financeira** — que é onde o dinheiro
mora.

## 3. A correção: uma coordenada, depois uma bijeção

### Fase 0 — Provar o denominador (bloqueia todo o resto) · **PARCIALMENTE FECHADA em 01/09**

> **O que já foi medido.** A régua era calibrada contra UM gerador: `linhas_de_conta_verdade`
> existia em 38 de 38 documentos do canastra e em **0 de 14** do vertentes. A contagem foi
> portada (sem reescrever a regra), e com a entrada certa a régua acerta **11 de 13 no
> vertentes, erro médio 1,3%** — ela **não** está viciada no canastra.
>
> **Mas ela conta A MENOS num conjunto identificável**, que é a direção que ESCONDE extração
> pela metade: `13`/`14_Balanco_COMBINADO` (−33% cada), `21_Mutuos` (−33%), `25_Situacao_Fiscal`
> (−30%), `10_Faturamento_24M` (−6%) e `11_Mapa_Divida` (−10%) do vertentes.
>
> **E o `055` do araucária, o pior dos três, É UM COMBINADO.** Se a régua o subconta como
> subconta os dois do canastra, o denominador dele não é 20 e sim da ordem de 30 — a cobertura
> não é 65% e sim perto de 43%. **A sub-extração seria pior do que a medida.** Hipótese
> transferida, não fato: só o texto de produção dos três documentos fecha esta fase.
>
> No caminho, um erro meu que vale como aviso: a primeira medição deu "93% de erro, contando a
> menos em 13 de 13" — e era eu medindo a entrada errada. Os dois books tinham extratores
> diferentes, e o do vertentes não agrupava os pedaços pela coordenada Y. Comportamento correto
> da régua sobre texto de outra forma, quase reportado como defeito.

O que ainda falta desta fase:

Sem isto, tudo abaixo é fé. Capturar o texto que o nó `Extrair Texto` produziu para os TRÊS
documentos e contar as linhas de conta **por um segundo método independente** da
`linhasDeConta` — no limite, à mão, que para 20/97/150 linhas é viável.

Três saídas possíveis, e as três são informação:

- a régua acertou → sub-extração real confirmada, segue o plano;
- a régua contou a mais → a correção é na régua, e as 3 pendências são falsas como as 20;
- a régua contou a menos → **é o caso perigoso**, e nunca foi observado (a sessão 77 mediu 0
  documentos contando a menos em 20).

**Critério de pronto:** os três números conferidos e o resultado escrito no `ESTADO.md`, com o
método usado.

### Fase 1 — A coordenada: um texto numerado AO LADO do PDF

> **CORREÇÃO DE PREMISSA, 01/09.** A primeira versão desta fase dizia "numerar as linhas do
> bloco enviado ao modelo". **Não existe bloco de texto sendo enviado.** O `Preparar Conteudo`
> monta o `content_part` com `parteDeArquivo`, e o modelo recebe o **PDF em si** — é o que o
> teste *"o PDF vai como ARQUIVO, não como texto"* trava, e por bom motivo: mandar só texto
> perderia layout, coluna e documento digitalizado. O fatiamento também não usa número de
> linha: usa **âncoras** (o texto da primeira e da última linha do bloco).

A coordenada continua sendo necessária, e o caminho que respeita o que já existe é **acrescentar
uma parte de TEXTO NUMERADO ao lado do arquivo**, não substituir o arquivo:

```
partes: [ parteDeTexto(prov, textoNumerado), item.content_part ]
```

```
L001: ATIVO CIRCULANTE                    44.022    41.310
L002:   Disponível                            825       790
L003:     Caixa                                800       770
```

O modelo lê o **PDF** para valor, coluna e layout — nada se perde — e usa o **texto numerado**
como sistema de coordenadas para declarar de onde cada linha veio. O texto já existe no
pipeline: é o mesmo que alimenta as âncoras do fatiamento e a régua da cobertura, produzido pelo
nó `Extrair Texto`.

E o schema da linha ganha **um campo obrigatório**: `ln` = o número da linha de origem.

**Duas coisas a medir antes de ligar**, e nenhuma é opinião:
- **Custo de entrada.** O texto numerado é token novo em toda chamada de extração. O
  `medir-custo-book.mjs` tem de continuar verde, e o número entra na mensagem do commit.
- **Divergência PDF × texto.** Se o `Extrair Texto` fragmentar (foi o que a sessão 77 achou), a
  numeração numera fragmentos, e o `ln` aponta para meia linha. A emenda
  (`juntarFragmentosDeLinha`) tem de rodar ANTES da numeração — e o número de linhas numeradas
  tem de bater com o denominador da régua, senão são duas coordenadas diferentes outra vez.

### Fase 2 — A bijeção: cada linha do texto tem de ter DESTINO

Esta é a fatia que muda a natureza da garantia. O modelo passa a devolver, além dos grupos, uma
lista `descartadas`: cada número de linha que ele NÃO transformou em conta, com um código do
motivo — `cabecalho`, `titulo_secao`, `nota`, `continuacao`, `assinatura`, `sem_valor`.

A guarda deixa de ser estatística e vira **aritmética**:

| condição | significado | severidade |
|---|---|---|
| `ln` não aparece nem nas linhas nem nas descartadas | **buraco**, nomeado pelo número | bloqueante |
| `ln` aparece duas vezes | **duplicação** | bloqueante |
| `ln` fora de `1..N` | **invenção de origem** | bloqueante |

Para os três documentos do araucária, a saída deixa de ser *"68 de 97, investigue"* e passa a
ser *"as linhas 23, 24, …, 51 não têm destino declarado"* — uma lista que alguém abre o PDF e
confere em minutos.

**E isto dissolve a briga do denominador da Fase 0.** Hoje a `linhasDeConta` decide sozinha
quais linhas são conta. Com a bijeção, **o modelo declara** quais são conta e quais são
cabeçalho, e a régua vira uma segunda opinião sobre a mesma linha. Duas opiniões independentes;
onde discordam é o sinal — que é exatamente como a `0146` e a `0151` já funcionam do lado do
banco.

### Fase 3 — A literalidade: a doutrina do `tr`, aplicada onde o dinheiro mora

`vt` (valor_texto) passa a ser cobrado como o `tr` dos fatos: **tem de ser trecho literal da
linha `ln` citada**. A conferência é mecânica — `linhaOrigem.includes(vt)` depois de normalizar
espaço.

Uma linha cujo `vt` não aparece na linha de origem é **invenção**, e segue o mesmo destino que
a paráfrase no `fatos`: descartada na gravação, com pendência nomeando a linha. É a primeira vez
que "criar dado" passa a ser detectável em vez de indetectável.

### Fase 4 — Re-perguntar só o buraco

Com os números em mãos, o retry deixa de ser "extrair o documento de novo" (caro, e pode voltar
com outro buraco) e passa a ser **"leia SÓ as linhas 23 a 51"**. Bloco pequeno, resposta
pequena, custo proporcional ao defeito. Teto de uma re-pergunta por documento, para a falha
cair no lado barato.

### Fase 5 — Medir cada guarda NÃO-VAZIA

Regra 2 do projeto, e vale para cada uma das guardas novas. Desligar, rodar, contar os asserts
que reprovam, religar, e o número vai na mensagem do commit. A prova mais forte disponível:
**com a guarda ligada, os três documentos do araucária têm de acusar buraco nomeado** — e o
número de linhas sem destino tem de bater com 97−68, 150−102 e 20−13.

## 4. O que este plano NÃO resolve, dito de propósito

- **Não garante que o modelo LEIA certo.** Garante que ele *declare* o destino de cada linha e
  que o valor seja literal. Um valor lido errado, mas literalmente copiado da linha certa,
  passa — e continua sendo trabalho das guardas de valor (o balanço que fecha, os subtotais da
  `0116`, os 716 invariantes do export).
- **Não elimina o julgamento humano.** Elimina o julgamento *invisível*: hoje um documento
  incompleto e um documento completo têm a mesma aparência até alguém abrir o PDF.
- **Não é barato.** Toca o `SYSTEM_PROMPT`, o schema, o fatiamento, uma migration para gravar
  `ln`, as guardas e as suítes. É trabalho de várias fatias, uma por commit.

## 5. Ordem, e o que destrava o quê

| Fase | Depende de | Critério de pronto |
|---|---|---|
| **0** provar o denominador | captura do texto dos 3 documentos | os 3 números conferidos por método independente, escrito no `ESTADO.md` |
| **1** coordenada (`ln`) | Fase 0 | `ln` obrigatório no schema; custo medido contra o teto; suíte verde |
| **2** bijeção (`descartadas`) | Fase 1 | guarda aritmética acusa buraco/duplicação/invenção de origem, medida não-vazia |
| **3** literalidade do `vt` | Fase 1 | `vt` não-literal é descartado e vira pendência, medida não-vazia |
| **4** re-perguntar o buraco | Fases 2 e 3 | re-pergunta cobre só as linhas sem destino, com teto de 1 |
| **5** medir tudo | todas | os 3 documentos do araucária acusam buraco com o número certo |

A Fase 0 é a única que não é engenharia — é medição, e ela **bloqueia tudo**. Começar pela Fase
1 sem ela é construir em cima de um número que ninguém conferiu, que é o defeito que a sessão 77
achou dentro do próprio instrumento de calibração.
