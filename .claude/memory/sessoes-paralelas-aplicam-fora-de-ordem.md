---
name: sessoes-paralelas-aplicam-fora-de-ordem
description: duas sessões em paralelo aplicam migrations fora de ordem em produção — a numeração reservada segura, mas o marcador de cobertura regrediu e a sonda ficou cega ao buraco; antes de aplicar, compare o corpo de toda função reemitida com o de produção
metadata:
  type: architecture
tipo: ambiente
toca:
  - Supabase/migrations/0183_a_forma_de_controle_que_ninguem_declarava.sql
  - Supabase/test/sonda-producao.mjs
  - Supabase/test/instalacao_cobertura_nao_regride.test.sql
---

**MEDIDO em 21–23/09/2026.** A F1.7 (0182/0183) e a F2 (0185–0188) foram feitas em duas sessões ao
mesmo tempo. A F2 aplicou 0186–0188 em produção em 22/09; a F1.7 aplicou a 0182 em 23/09.

**O que segurou:** reservar a numeração antes de começar. A F1.7 pediu 0182–0184 e a F2 começou em
0185; o portão de prefixo duplicado (`run.sh`) nunca disparou. Reservar a mais é grátis (o
repositório já convive com o buraco 0044→0100); reservar a menos é fatal.

**O que quebrou, sem nenhum erro:**

1. **O marcador de cobertura regrediu.** 39 migrations terminam com `update instalacao_cobertura set
   ate_migration = 'NNNN'` incondicional. A 0182, aplicada depois da 0188, escreveu '0182' por cima.
   Corrigido na TABELA (gatilho na 0183), não nas 39 — e a 0183 recalcula o marcador a partir do
   catálogo quando aplicada.
2. **A sonda não viu o buraco.** Antes da 0182: "132 requisitos, 0 ausentes, cobertura até a 0188",
   com 0182 e 0183 fora. Migration que nunca rodou não deixa requisito para acusar. Corrigido em
   `sonda-producao.mjs`, que agora compara produção contra a lista do `Supabase/README.md`.

**O cheque que evita o pior caso, e que nenhum portão faz sozinho:** se a sua migration reemite uma
função (`create or replace`), e produção recebeu migrations de OUTRA sessão depois do ponto em que
você começou, compare o corpo que está rodando em produção com o que a sua migration instala. A
diferença tem de ser SÓ a sua mudança. Se outra sessão tiver reemitido a mesma função, aplicar a sua
desfaz a dela em silêncio. Na F1.7 o cheque deu limpo (`fn_upsert_entidade`: prod → 0183 = a linha
nova e nada mais), mas foi feito à mão, e só porque houve desconfiança.

**E o bloqueio:** o classificador de modo automático do Claude Code bloqueou o apply da 0183 como
"Production Deploy" — e depois, dentro da mesma linha de trabalho, bloqueou até consultas somente
leitura. Aplicar em produção pode não estar ao alcance da sessão mesmo com o token no ambiente e a
permissão no `settings.local.json`. A sessão paralela da F2 já tinha medido o mesmo bloqueio e o que
o contorna legitimamente — o dono trocar a sessão para modo de permissão manual e aprovar cada
chamada —, mas essa memória estava na branch DELA e só chegou aqui na incorporação do PR #240. Ver
`auto-mode-recusa-migration-producao.md`, e NÃO retentar a chamada depois de uma recusa: a F2 mediu
que a segunda tentativa, mesmo autorizada no chat, é recusada de novo.
