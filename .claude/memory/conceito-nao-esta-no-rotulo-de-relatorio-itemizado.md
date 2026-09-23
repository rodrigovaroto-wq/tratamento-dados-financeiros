# Em relatório itemizado, o conceito não está no rótulo — o rótulo é o item

**Custou:** a fatia F2.1 inteira (migration `0185`), reprovada na medição de alcance contra
produção em 21/09/2026, depois de já ter passado por revisão independente e por uma correção.

## O que se tentou

Dar exigência de conteúdo (`taxonomia_linha_exigida`, mecanismo da `0113`) a nove tipos de
documento que nunca tiveram nenhuma: AGING_AP, AGING_AR, EXTRATO_BANCARIO, GARANTIAS,
AVAIS_FIANCAS, CONTINGENCIAS, DEBITOS_TRIB, ESTOQUE, HEADCOUNT. A forma do mecanismo é lexical:
"existe linha cujo rótulo casa estes termos".

## Por que não funciona, medido

Simulação somente-leitura do predicado de `fn_exigencias_do_caso` contra o banco real (que estava
na `0181` — a `0185` nunca foi aplicada): **190 documentos, 14 casos, 64 pares caso×tipo com
conteúdo, 17 abririam pendência — e os 17, olhados um a um, TÊM o dado.**

A causa não é escolha ruim de termo. É a forma do documento:

| tipo | o que a chave realmente é, em produção |
|---|---|
| AGING_AP (mandato real) | `41518 - WELLA BRASIL LTDA.`, `01453 - L'OREAL BRASIL…` — nome de fornecedor |
| ESTOQUE (mandato real) | 484 linhas, `2500 - ASSALA PRIME` — código e nome de produto |
| CONTINGENCIAS | `Reclamações de horas extras…`, `Nº 22 — AMARO FASHION LTDA` — descrição do processo; a seção é `Trabalhista`/`Cível`/`Tributário - DIFAL` |
| EXTRATO_BANCARIO | `Banco Meridional S.A.` — nome do banco |
| HEADCOUNT | `Produção - turno A` — nome do centro de custo |

**Num relatório itemizado o conceito é o TIPO do documento, e o rótulo é o ITEM.** Ninguém
escreve "contingência" dentro de um relatório de contingências, pela mesma razão que ninguém
escreve "este é um extrato" em cada linha do extrato.

## E o erro é simétrico, o que é pior

Dos 47 pares que "passavam", **22 passavam por uma única linha residual** — `Demais fornecedores
(184 credores)` / `Demais clientes (312 sacados)`. Isto é, o agregado que o aging justamente não
abre satisfazia a exigência, enquanto um aging com o detalhe completo e sem linha de resto
reprovaria. A checagem premiava o documento pior.

## A armadilha de método, que vale para qualquer portão

**`campo_extraido.secao` não é estável entre versões da extração.** O MESMO book canastra tem
`secao` NULA nas ingestões antigas (`teste - Canastra`, `teste Canastra`, `Teste comparativo`) e
preenchida nas novas (`V45`, `v47`, `v4x`). E a `fixture_book_canastra.sql` do repositório tem a
`secao` preenchida — então o teste que a revisão exigiu, medido contra a fixture, passava nos seis
tipos enquanto a fatia continuava falsa em produção.

É a terceira ocorrência de [portão calibra sobre a entrada de PRODUÇÃO](portao-mede-a-entrada-de-producao.md),
e a forma nova dela é: **localizador que depende de `secao` se apoia na versão do extrator, não no
documento.**

## O que fazer em vez disso

Para tipo itemizado, a pergunta certa é **estrutural**, não lexical: quantas linhas com valor; o
eixo que o relatório precisa ter (faixas de vencimento no aging, competência no headcount). Ou
nenhuma — `item_sem_conteudo` (`0036`) já cobre "chegou vazio", e uma exigência lexical por cima
disso só acrescenta ruído de fila.

## O que salvou a rodada

A ordem: revisão independente **e depois** medição contra produção, antes de aplicar. A revisão
pegou 13 das 30 pendências falsas (localizador `contra='secao'`); a medição pegou as 17 restantes
e mostrou que o desenho inteiro estava errado. Nenhuma das duas sozinha teria bastado — e a suíte
local ficou verde o tempo todo.
