---
name: portao-pode-reprovar-por-ruido
description: portão que reprova por ruído é pior que portão nenhum — o schema.sql saía com FOR ROLE root contra o FOR ROLE postgres do CI
metadata:
  type: feedback
---

Em 21/08 o `Supabase/schema.sql` reprovou no CI com o schema **idêntico**. Causa: `pg_dump --no-owner`
não cobre o DEFAULT ACL. `ALTER DEFAULT PRIVILEGES FOR ROLE <alguem>` carrega o nome do
superusuário que aplicou as migrations, e num container que só tem `root` a linha saía com
`FOR ROLE root`.

O `run.sh` passou a normalizar essa linha para `postgres` — o nome verdadeiro no Supabase — pela
mesma razão que já filtra a versão do `pg_dump` e o token aleatório do `\restrict`: **o portão tem
de medir o schema, não quem digitou o comando.**

O caso irmão, e ele é pior porque produz verde: em 06/08 o GitHub Actions ficou sem runner, a
execução no `main` foi cancelada sem nunca começar (`runner_name` vazio) e os pushes seguintes não
criaram execução nenhuma — e o GitHub **não** reexecuta retroativamente. Antes de tratar um
vermelho como regressão sua, confira a **contagem de passos do job**: vermelho sem nenhum passo
executado não é regressão, é infraestrutura. Existe `workflow_dispatch` para reconferir.
