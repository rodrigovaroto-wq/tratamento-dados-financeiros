---
name: hook-derivados-morre-calado-na-renomeacao
description: regra de hook que casa CAMINHO por regex não sobrevive a uma renomeação de diretório — e some em silêncio, porque lembrete ausente é idêntico a lembrete sem o que dizer. Medido em 16/09/2026: 3 das 4 regras de lembrar-derivados estavam mortas havia semanas, 4 das 5 entradas reais saíam mudas
tipo: armadilha
toca:
  - .claude/hooks/lembrar-derivados.mjs
  - .claude/hooks/test/lembrar-derivados.test.mjs
---

# Regra de hook que casa caminho morre calada na renomeação

`lembrar-derivados.mjs` roda no `PostToolUse(Edit|Write)` e lembra o que a edição acabou de tornar
desatualizado: os JSON do n8n depois de mexer no gerador, o `Supabase/schema.sql` depois de uma
migration, as três fixtures depois do gerador do book. Cada regra é um **regex sobre o
`file_path`** — e é aí que está a armadilha.

A renomeação de agosto (`db/` → `Supabase/`, `test-data/` → `Dados de Teste/`, `n8n/` → `N8N/`)
moveu os diretórios e ninguém releu as regexes. Elas continuaram sintaticamente válidas e
simplesmente pararam de casar. **MEDIDO em 16/09/2026**, com a implementação velha e os cinco
caminhos reais do repositório: **4 saíam em silêncio**; só a regra do portal disparava.

Duas coisas fazem isso ser invisível, e as duas são de propósito:

1. o hook é **fail-open** — qualquer problema vira silêncio, porque um hook que lança pode travar
   a sessão;
2. o que ele produz é um **lembrete**, não um erro. Lembrete que não veio é indistinguível de
   lembrete que não tinha o que dizer — o mesmo padrão de
   `.claude/memory/estagio-desligado-parece-limpo.md`.

E `N8N/` é o caso mais traiçoeiro dos três: a regex dizia `n8n/`, que é **a mesma palavra em
caixa diferente**. Passa numa leitura desatenta e nunca casa.

## A guarda, e por que ela é a parte que importa

Consertar as três regexes não impede a próxima renomeação de repetir tudo. O que impede é a
segunda asserção da suíte: **o caminho de exemplo de cada regra tem de EXISTIR no repositório.**
Sem ela, a suíte ficaria verde testando caminhos que ninguém mais usa — verde por vacuidade, que
é o defeito que ela existe para não ter.

Quem acrescentar regra ao hook acrescenta o caminho real correspondente em `CASOS`, dentro de
`.claude/hooks/test/lembrar-derivados.test.mjs`. O CI já roda a suíte pelo glob
`.claude/hooks/test/*.test.mjs`.

**Esta ficha não traz `prova:`, e a omissão é honesta, não descuido.** O portão exige que o
arquivo do `prova` seja executado LITERALMENTE pelo `suites.yml`, e a suíte que prova esta lição
roda por GLOB (`.claude/hooks/test/*.test.mjs`). Declarar o caminho reprova o `conferir.mjs` —
medido em 16/09/2026. Inventar outro `prova` seria pior: o briefing passaria a afirmar que existe
quem desminta isto, apontando para quem não desmente.
