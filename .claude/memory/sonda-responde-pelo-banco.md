---
name: sonda-responde-pelo-banco
description: nenhum arquivo do repositório é autoridade sobre o estado do banco — só fn_instalacao_conferir(), contra o banco em que você está conectado
metadata:
  type: architecture
tipo: doutrina
toca:
  - Supabase/test/run.sh
prova: Supabase/test/run.sh
---

Em 21/08 o repositório dizia que a fila de migrations tinha zerado. A sonda mostrou que a
**`0133`** havia ficado para trás enquanto a `0134` e a `0135`, posteriores, entraram. Sem ela a
checagem de balanço fechava por construção e seção com buraco não abria pendência.

```sql
select chave, migration, tipo, objeto, presente, detalhe, porque
  from fn_instalacao_conferir() where not presente order by 1;
```

Se a sonda e qualquer recado em prosa deste repositório discordarem, **a sonda está certa**.

Duas ressalvas que a própria sonda publica:

- **"o objeto existe" não é "a migration foi aplicada corretamente"** — `create or replace` sobre
  um corpo velho deixa a assinatura idêntica. Desde a `0147` a sonda enxerga o **corpo** da
  função, que é o que distingue correção aplicada de função homônima velha. Mas a `0147` só
  responde depois de aplicada: num banco sem ela, a sonda continua sendo a de 13 marcadores;
- o que ela garante sem dúvida é o contrapositivo, e é a parte útil: **objeto ausente é migration
  ausente.**

`Supabase/test/run.sh` reprova quando o catálogo fica para trás da migration mais nova — é o que impede
a sonda de envelhecer calada.
