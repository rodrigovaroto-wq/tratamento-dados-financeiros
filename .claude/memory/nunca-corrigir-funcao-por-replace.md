---
name: nunca-corrigir-funcao-por-replace
description: migration que corrige função por replace de texto sobre pg_get_functiondef passa em toda suíte local e reprova em produção — reemita a função inteira com create or replace
metadata:
  type: architecture
---

A `0156` tentou acrescentar uma coluna ao `insert` de `fn_registrar_uso_lote`
lendo `pg_get_functiondef`, aplicando três `replace` de texto e executando o
resultado. Com guardas: conferia a âncora antes e recusava se a substituição não
mudasse nada.

**Passou em toda suíte local e reprovou em produção**, em 31/08:

```
ERROR: a substituição de fn_registrar_uso_lote não mudou nada —
       as âncoras não casaram e o carimbo de fechamento ficaria de fora
```

**Por que local nunca pegaria isso.** O `db/test/run.sh` monta o banco do zero a
partir dos próprios arquivos do repositório, então o corpo da função é, por
construção, byte a byte igual ao que o `replace` espera. Produção não tem essa
garantia — e é a doutrina da casa que **o banco é a autoridade e o repositório
não é**. Uma migration que depende dos bytes exatos do que está lá está
apostando contra a própria doutrina do projeto.

**A correção, e ela já estava escrita desde a `0103`:** `create or replace
function` com o corpo INTEIRO. Ela não pergunta nada sobre o que estava lá. É
por isso que o `db/README.md` registra que a duplicação de linhas em migration
de função é **inevitável e deliberada**, não desleixo — e o `.sonarcloud.properties`
exclui `db/` justamente porque o Sonar acusava essa duplicação.

**O que salvou:** o `begin`/`commit` da migration e o `raise` explícito. A
tentativa reverteu inteira, sem deixar metade aplicada — que é a diferença entre
uma falha honesta e o estado pela metade que custa uma sessão para desfazer.
Guarda que recusa alto vale mesmo quando a abordagem que ela protege está
errada.

**Regra:** migration que muda função **reemite a função**. Se a tentação de
"mudar só uma linha" aparecer, ela é sinal de que a fatia está sendo escrita
contra o banco em vez de contra o repositório.
