---
name: estagio-desligado-parece-limpo
description: um estágio que não rodou tem exatamente a mesma aparência de um que rodou e não achou nada — é o modo de falha que mais custou neste projeto
metadata:
  type: architecture
tipo: doutrina
toca: []
---

Ausência de achado não é evidência de execução. Este é o padrão por trás de quase todo defeito
caro do projeto, e todos eles rodaram **sem produzir um único erro**:

- a reconciliação ficou **onze dias parada em silêncio** (v47): o nó `Gravar Campos` do n8n
  substitui o item pelo resultado da query, então `documento_id` sumia e
  `fn_registrar_diagnostico` era chamada com NULL desde 13/08. Estágio parado não gera achado;
- o **fatiamento nunca ligou e a cobertura estava desligada** (sessão 74): `Montar Req Extracao`
  montava um item novo com cinco campos e descartava o que o `Medir Documento` tinha medido. Sem
  `linhas_do_texto` o `Fatiar Extracao` cai no fallback de UM bloco; sem `contas_no_documento` a
  guarda de extração incompleta — a régua que mede alucinação por omissão — **nunca dispara**. O
  sintoma foi uma coluna nula no painel, com o `Conferir Lote` verde;
- a tela dizia **"Tudo pronto" sobre uma execução morta**, porque o registro de falha dependia do
  Error Workflow do n8n, que é passo manual;
- o `book-araucaria` ficou **1h52 de pé sem gravar uma reconciliação**, zero linhas de `ERROR` no
  log do Postgres, nada no n8n, nada na tela.

**A consequência prática, e ela vale como regra:** todo estágio precisa de um sinal POSITIVO de
que rodou — um lote FECHADO, uma contagem, uma unidade declarada — e não da ausência de
pendência. Foi por isso que `pronto` passou a exigir o lote fechado, e por isso a `0154` fez a
pendência de cobertura dizer **em quantos blocos** o documento foi lido.

E o corolário na hora de investigar: **quando as três perguntas óbvias têm resposta certa, a
causa é estrutural.** No araucária a migration estava aplicada, o workflow estava publicado
corretamente e a cota nem chegou perto — e a causa era reconciliação quadrática duas vezes.
