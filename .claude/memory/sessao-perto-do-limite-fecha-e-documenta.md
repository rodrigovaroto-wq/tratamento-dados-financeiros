---
name: sessao-perto-do-limite-fecha-e-documenta
description: perto do limite de uso da sessão, a prioridade vira commitar o que está pronto e escrever o estado — nunca deixar trabalho pela metade sem rastro para a próxima sessão
metadata:
  type: process
tipo: doutrina
toca: []
---

Pedido explícito do dono (14/09/2026): quando a sessão passar de ~90% do limite de uso, a
prioridade deixa de ser avançar mais uma fatia e vira **fechar em segurança**:

1. **Commitar tudo que já está pronto e testado** — nenhuma fatia validada fica no working tree
   sem commit só porque a próxima ainda não começou.
2. **Nunca parar no meio de uma fatia** — se uma migration/mudança está pela metade (escrita mas
   não testada, ou testada mas não commitada), ou se termina ela (se couber no tempo/uso que
   resta) ou se reverte para o último estado limpo. Working tree sujo + sessão sem uso é o pior
   estado possível: a próxima sessão não sabe se aquilo é intenção ou acidente.
3. **Escrever o estado em `HANDOFF.md`/`ESTADO.md`** — não só "o que foi feito", mas **o que falta,
   em que ordem, e por quê** (a mesma doutrina do `MAPA_DE_EXECUCAO.md`). Uma sessão nova que abre
   sem isso reconstrói o raciocínio do zero, e reconstruir custa mais caro que documentar.
4. **Nomear o próximo passo exato** — não "continuar o plano", mas o comando/arquivo/linha por
   onde a próxima sessão recomeça. Ambiguidade aqui é o mesmo defeito que
   `estagio-desligado-parece-limpo.md` descreve: parecer que dá para continuar não é dar para
   continuar.

**Por que isto é memória e não só bom senso:** o custo de errar é assimétrico. Esquecer isto uma
vez custa uma sessão inteira de "onde eu estava mesmo?" — e numa tarefa multi-sessão como esta
(diagnóstico → plano → 6 fatias), cada sessão que perde contexto é uma sessão que paga de novo
por trabalho já pago.
