# Memória — o que já custou caro neste projeto

Índice sempre carregado. Regras de uso e política de crescimento em `INSTRUCTIONS.md`.
Uma linha por entrada; teto mole de 130 linhas não vazias.

## O padrão de erro central

- [Estágio desligado parece estágio limpo](estagio-desligado-parece-limpo.md) — o modo de falha
  que mais custou aqui: nada de erro, nada de pendência, e o estágio simplesmente não rodou

## Doutrina (viola isto e o defeito chega ao cliente)

- [Nunca apresentar ausência como dado](nunca-apresentar-ausencia-como-dado.md) — zero fabricado
  é indistinguível de zero medido; branco + nota com o EFEITO
- [Teto de autonomia por natureza do estágio](teto-de-autonomia-por-natureza.md) — nenhum volume
  de veredito sobe Classe B/C ou classificação contábil acima de N1
- [A sonda responde pelo banco, o documento não](sonda-responde-pelo-banco.md) — a `0133` ficou
  para trás enquanto a `0134` entrou, e o repositório dizia que estava tudo aplicado
- [E a sonda só conhece o catálogo que o banco tem](sonda-so-conhece-o-catalogo-que-o-banco-tem.md)
  — verde nela não é "a rodada vai rodar": num banco na `0150`, três nós do workflow não resolviam
  e ela não acusava nenhum. `Supabase/test/conferir-chamadas.mjs` faz a outra ponta
- [Nunca corrigir função por `replace` de texto](nunca-corrigir-funcao-por-replace.md) —
  passa em toda suíte local e reprova em produção; reemita a função inteira
- [Nó Postgres novo vai como ramo TERMINAL](no-postgres-novo-vai-como-ramo-terminal.md) —
  inline no fluxo por documento ele apaga o contexto de todos os seguintes (v47: 11 dias; 0156: 0 de 38)

## Armadilhas de teste e de portão

- [Fixture nasce vazia com mais frequência do que parece](fixture-nasce-vazia.md) — duas da
  sessão 18 passavam com o bug LIGADO
- [Derivado versionado precisa de `git diff --exit-code`](derivado-versionado-precisa-de-git-diff.md)
  — quem roda é o commitado, não a fonte que o gera
- [A medição reescreve o derivado](medicao-reescreve-derivado.md) — o `cp` do protocolo
  protege o arquivo alterado, não o `Supabase/schema.sql` que o `run.sh` regrava por baixo
- [Um portão pode reprovar por ruído](portao-pode-reprovar-por-ruido.md) — `FOR ROLE root` contra
  `FOR ROLE postgres`: schema idêntico, CI vermelho
- [Portão calibra sobre a entrada de PRODUÇÃO](portao-mede-a-entrada-de-producao.md) — o texto
  que o n8n extrai não é o de nenhum extrator local: +3% no portão, 161% de erro em produção

- [Agente interrompido deixa a correção DESLIGADA](agente-morto-deixa-a-correcao-desligada.md) —
  um `false and` no meio da expressão, o arquivo com cara de pronto; e não rode a suíte enquanto
  um agente tem a árvore (medi um arquivo e li outro, 43 segundos de diferença)

## Armadilhas de ferramenta (custaram tempo real)

- [`git checkout <arquivo>` apaga trabalho não commitado](git-checkout-apaga-trabalho.md) — copie
  para o scratchpad e restaure com `cp`
- [Backtick em comentário de nó Code quebra o `jsCode`](backtick-quebra-jscode.md) — aconteceu
  duas vezes; só o teste pega
- [`spliceRows` na aba Macro desloca endereços em silêncio](splicerows-desloca-enderecos.md)
- [`avaliarCelula` não segue referência entre abas](avaliarcelula-nao-cruza-abas.md)
- [A ordem dos parâmetros dos dois classificadores é diferente](ordem-dos-classificadores.md)

## Produção (não está em nenhum arquivo do repositório)

- [A republicação do n8n perde toggles](republicacao-do-n8n-perde-toggles.md) — `multipleFiles`,
  `onError` em 23 nós, `retryOnFail` em 11
- [A cota RPD 500 é o limite que aperta](cota-rpd-e-o-limite-do-dia.md) — 440/500 para 190
  documentos: um book por dia
- [`MATERIALIZED` não é enfeite](materialized-nao-e-enfeite.md) — sem ele o Postgres inlina a CTE
  e o agrupamento que matava o cartesiano vira o cartesiano
