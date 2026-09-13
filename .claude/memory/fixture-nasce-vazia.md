---
name: fixture-nasce-vazia
description: fixture que passa com o bug LIGADO é o defeito mais comum de teste aqui — duas da sessão 18 nasceram assim
metadata:
  type: feedback
tipo: armadilha
toca: []
---

Um invariante novo só vale depois de **medido não-vazio**: desligue a correção, rode a suíte,
confirme que ela reprova, religue, e registre o número de asserts que reprovaram na mensagem do
commit.

Duas fixtures da sessão 18, escritas para provar a dupla contagem no total do grupo, **passavam
com o bug ligado** e ninguém notou:

- uma declarava `secao` — e aí `subsecaoAutoritativa` já acertava sozinha;
- a outra tinha `ordem` entre contas do Imobilizado — e o consenso de irmãos já acertava.

Nos dois casos a fixture não reproduzia o arranjo real; ela reproduzia um arranjo em que o bug
não acontece.

Duas regras que vêm junto:

- **invariante afirma COMPORTAMENTO, não mecanismo.** O invariante antigo das médias exigia
  `COUNT(` na fórmula — e o `COUNT` posicional era justamente o defeito. Um teste que descreve
  *como* o código faz protege o bug;
- **nunca inventar fixture para provar bug de produção.** Se você não consegue reproduzir o
  arranjo real, diga isso no comentário do teste e afirme só o que dá para provar. Registrar "não
  consegui, e estas foram as tentativas que nasceram vazias" é resultado válido; fixture inventada
  passa verde e engana.

E a armadilha do lado oposto, medida na v48: **20 das 27 pendências eram falsas.** A extração
estava certa e quem errava eram as checagens. Antes de corrigir a extração porque a checagem
acusou, confira a checagem — e lembre que **pendência falsa que muda de nome não é correção**
(`linha_exigida_ausente` virando `precondicao_nao_satisfeita`).
