# Onda paralela

## Quando usar

Quando já existe uma lista de tarefas e você quer executá-las em paralelo com segurança, em vez de
uma sessão mastigando tarefa por tarefa.

## Por que funciona

As duas condições da etapa 2 são o que torna seguro rodar vários agentes ao mesmo tempo. Quebrar
qualquer uma gera conflito silencioso (dois agentes escrevendo por cima um do outro) ou uma onda
que não era independente. Na dúvida, a tarefa degrada para execução serial — o erro seguro é o
único permitido. E ninguém além do orquestrador comita, o que elimina a corrida por completo.

## Como adaptar

- **`[LISTA DE TAREFAS]`** — o plano ou o lote de correções que você já tem.

## O prompt

```
Quebre [LISTA DE TAREFAS] em ondas de execução paralela. Siga exatamente — a segurança depende das
regras abaixo, não de julgamento na hora.

## 1. Liste cada tarefa

- **ID** — `T01`, `T02`, ...
- **Descrição** — uma linha.
- **Files:** — todos os caminhos que a tarefa cria ou modifica. Na dúvida, liste mais, não menos.
  **Inclua os derivados**: quem toca `n8n/lib/` também toca os JSON gerados; quem escreve migration
  também toca `db/schema.sql`; quem mexe no gerador do book toca as três fixtures. Derivado
  esquecido é colisão de arquivo que a marcação não viu.
- **Depends-on:** — os IDs de que ela consome saída, ou `nenhuma`.
- **Owner:** — o especialista de `.claude/agents/`.

Qualquer incerteza real sobre `Files:` ou `Depends-on:` vira `Depends-on: tudo que já foi listado`.
É o padrão seguro, não um atalho para não preencher.

## 2. Agrupe em ondas

Duas tarefas entram na MESMA onda só se AS DUAS condições valerem:
1. nenhuma depende da outra, nem transitivamente;
2. os conjuntos de `Files:` são totalmente disjuntos — zero sobreposição, mesmo em seções
   diferentes do mesmo arquivo.

Falhou uma, a tarefa vai para uma onda posterior. Onda de uma tarefa só é o resultado correto
quando é isso que a regra dá.

Mostre a tabela: onda, tarefas, owner de cada uma.

## 3. Execute onda a onda

1. Despache todos os implementadores da onda **numa única mensagem** — é o único ponto onde o
   paralelismo acontece.
2. **Implementadores NÃO comitam.** Eles editam, verificam o próprio trabalho e reportam quais
   arquivos mudaram.
3. **Você comita**, uma tarefa por vez, em ordem fixa, capturando o `HEAD` fresco imediatamente
   antes de cada commit — nunca um `HEAD` capturado no início da onda.
4. Depois que os commits da onda existem, despache os revisores da onda juntos (revisão é só
   leitura, então é seguro).
5. Um único registro de progresso por onda, nunca um por tarefa.
6. Só então a próxima onda.

Antes de commitar qualquer onda que toque gerador, rode os geradores e confira
`git diff --exit-code`. Duas tarefas que geram o mesmo derivado nunca são independentes.
```
