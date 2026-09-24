---
id: f2-localizador-chave-pendencia-falsa
tipo: defeito
toca:
  - Supabase/migrations/0187_o_tipo_que_chegava_sem_leitor_declarado.sql
  - Supabase/test/cobertura_de_tipos.test.sql
  - Supabase/test/fixture_book_canastra.sql
  - Arquitetura do Sistema/3 Estado e Execução/ARQUITETURA_ALVO_E_ROADMAP.md
prova: Supabase/test/run.sh
substitui: []
---

# F2.1: a exigência lexical não serve para relatório itemizado (migration `0185`, REPROVADA)

**Descoberto em:** 21/09/2026, rodada F2.1. **Veredito final: a `0185` NÃO deve ser aplicada.**
A migration segue no repositório como registro; nunca entrou em banco de produção.
**Atualização 22/09/2026:** a `0185` foi DESCARTADA do repositório (o número fica como lacuna) e
D6 passou a ser respondido por DECLARAÇÃO na `0187` (`taxonomia_tipo_cobertura` +
`fn_cobertura_de_tipos`), que também desativou as exigências lexicais de MUTUOS e FAT_INTRAGRUPO
da 0113 — mesmo defeito, já no ar.

> **Esta ficha foi reescrita depois da medição contra produção.** A primeira versão concluía que o
> defeito era o localizador casar `chave` quando o termo mora em `secao`, e que a cascata
> `contra='secao'` resolvia. Isso está certo e é insuficiente: produção mostrou que o desenho
> inteiro está errado. Registrar a conclusão parcial como final teria mandado a próxima sessão
> aplicar uma migration reprovada.

## Camada 1 — o que a revisão independente pegou (verdadeiro, e não bastou)

Na primeira versão, os doze localizadores casavam `contra='chave'`. Medido contra
`Supabase/test/fixture_book_canastra.sql`, quatro tipos davam `satisfeita=false` em caso correto —
CONTINGENCIAS, HEADCOUNT, EXTRATO_BANCARIO e ESTOQUE — porque ali o termo do conceito mora na
`secao`. A cascata `contra='secao'` (mecanismo que existe desde a `0113` e nunca tinha sido usado)
levou o bloco de teste de 4-de-6-reprovando para 6-de-6-passando, e **evitou 13 pendências falsas
em produção** (seriam 30; ficaram 17). Mesmo padrão que causou a `0166`.

## Camada 2 — o que só a medição contra PRODUÇÃO pegou (e é o veredito)

Simulação somente-leitura do predicado de `fn_exigencias_do_caso` sobre o banco real (na `0181`):

| | medido |
|---|---|
| documentos dos nove tipos | 190, em 14 casos |
| pares caso × tipo com conteúdo | 64 |
| abririam `linha_exigida_ausente` | **17** |
| dos 17, quantos realmente não têm o dado | **zero** |

**A premissa está errada, não os termos.** Em relatório ITEMIZADO o conceito não aparece no
rótulo: o rótulo é o ITEM, e o conceito é o próprio TIPO do documento. No mandato real, o AGING_AP
tem chaves `41518 - WELLA BRASIL LTDA.` e o ESTOQUE tem 484 linhas como `2500 - ASSALA PRIME`. Em
CONTINGENCIAS (9 dos 17) as chaves são descrições de processo e as seções são
`Trabalhista`/`Cível`/`Tributário - DIFAL` — a palavra "contingência" não existe no documento.

**E o erro é simétrico:** 22 dos 47 pares que passam se satisfazem por UMA linha residual
(`Demais fornecedores (184 credores)`, `Demais clientes (312 sacados)`) — o agregado que o aging
justamente não abre. Um aging só com o resto passa; um aging completo sem linha de resto reprova.
A checagem premia o documento pior.

## Camada 3 — a armadilha de método, que vale para qualquer portão futuro

**`campo_extraido.secao` não é estável entre versões da extração.** O MESMO book canastra tem
`secao` nula nas ingestões antigas (`teste - Canastra`, `teste Canastra`, `Teste comparativo`) e
preenchida nas novas (`V45`, `v47`, `v4x`). A fixture do repositório tem `secao` preenchida — então
o teste que a revisão exigiu, medido contra ela, passava nos seis tipos enquanto a fatia continuava
falsa em produção. Terceira ocorrência de
[portão calibra sobre a entrada de PRODUÇÃO](../../memory/portao-mede-a-entrada-de-producao.md), na
forma nova: **localizador que depende de `secao` se apoia na versão do extrator, não no documento.**

Detalhe completo em
[o conceito não está no rótulo de relatório itemizado](../../memory/conceito-nao-esta-no-rotulo-de-relatorio-itemizado.md).

## O que fazer em vez disto

Para tipo itemizado a pergunta certa é **estrutural**, não lexical: quantas linhas com valor; o
eixo que o relatório precisa ter (faixas de vencimento no aging, competência no headcount). Ou
nenhuma — `item_sem_conteudo` (`0036`) já cobre "chegou vazio", e uma exigência lexical por cima
disso só acrescenta ruído de fila.

GARANTIAS, AVAIS_FIANCAS e DEBITOS_TRIB continuam **sem medição nenhuma**: não existem em fixture
nem em produção. Isso é NÃO MEDIDO, diferente de medido e OK.

## Decisão do dono, 21/09/2026

Os nove tipos ficam **complementares**, não sobem a bloqueante — fecha a pergunta que
`2 Especificação/f0/03_taxonomia_reestruturacao.md` deixava para a v2.

## Commits

- `6947e49` — fatia original (numerada 0182), com o defeito da camada 1
- `ead6434` — renumeração 0182→0185 (a 1.7 ocupa a faixa 0182–0184 em outra sessão)
- `1d207ab` — correção da camada 1, após revisão independente
- `0fc5d12` — correção de três afirmações falsas que o fechamento introduziu
