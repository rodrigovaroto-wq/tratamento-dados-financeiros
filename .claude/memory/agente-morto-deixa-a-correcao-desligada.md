---
name: agente-morto-deixa-a-correcao-desligada
description: agente interrompido deixa a correção DESLIGADA — um `false and` no meio da expressão e o arquivo com cara de pronto; e não rode a suíte enquanto um agente tem a árvore
tipo: armadilha
toca: []
---

# Agente interrompido deixa a correção DESLIGADA, e o arquivo parece pronto

**Sessão 79, 02–03/09. Custou uma medição inteira e quase entrou um commit que não corrigia nada.**

A regra 2 do `CLAUDE.md` manda **desligar a correção, rodar a suíte, confirmar que reprova, religar**.
Quem executa isso é normalmente um subagente, e ele faz o desligamento **editando o arquivo da
migration**. Se o processo morrer entre o "desligar" e o "religar" — reinício do worker, estouro de
contexto, qualquer coisa — a árvore de trabalho fica assim:

```sql
or (false and p_tipo_taxonomia = 'COMBINADO' and fn_documento_de_varias_empresas(d.id))
```

Um `false and` no meio de uma expressão. **O arquivo tem 350 linhas de comentário certo, o teste
existe, a sonda tem entrada, o `git status` mostra tudo pronto — e a migration não corrige nada.**
É o padrão de erro central deste repositório (`estagio-desligado-parece-limpo.md`) aplicado ao
processo de trabalho em vez de ao código.

## O que tornou isto pior, e é meu erro de despacho

Rodei a suíte inteira (`run.sh`, 8 minutos) **enquanto o revisor mexia na mesma árvore**. As duas
coisas eram verdade e se contradiziam:

| | |
|---|---|
| meu log da suíte, 21:47:15 | `TODOS OS TESTES PASSARAM`, os 9 asserts nomeados |
| `stat` da migration | modificada às **21:47:58** — 43 segundos DEPOIS |

Passei um tempo bom tentando explicar como um teste podia passar com o bug ligado. Não podia: eu
tinha medido um arquivo, e estava lendo outro. O `CLAUDE.md` já dizia que despacho paralelo exige
**conjuntos de arquivos totalmente disjuntos**; a suíte lê a árvore inteira, então nada é disjunto
dela.

## As três regras que saem daqui

1. **Não rode a suíte enquanto um agente tem a árvore.** Uma coisa por vez, ou o log mede um estado
   que já não existe.
2. **Quem mede com a correção desligada desliga NO BANCO, não no arquivo** — `create or replace
   function` direto no psql, num banco descartável. Processo que morre no meio não deixa rastro no
   repositório.
3. **Antes de comitar fatia vinda de agente, procure o desligamento:**
   ```bash
   git diff -U0 -- Supabase/migrations | grep -nE '\b(false|true) and\b|--\s*(TODO|DESLIGA)'
   ```
   Custa um segundo. O que ele pega custa uma rodada.

O `stat -c '%y'` dos arquivos contra o horário do log é o que fecha o diagnóstico quando os dois
lados parecem certos. Use-o cedo.
