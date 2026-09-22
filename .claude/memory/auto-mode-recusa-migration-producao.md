---
name: auto-mode-recusa-migration-producao
description: o classificador de permissão do auto mode recusa aplicar migration em produção (curl à API de gerenciamento do Supabase) mesmo com autorização explícita do dono no chat — falta regra de permissão em settings.json
metadata:
  type: environment
tipo: ambiente
toca:
  - .claude/settings.json
---

**MEDIDO em 22/09/2026 (sessão 100).** As pré-condições da `0186` estavam medidas e liberadas
contra produção (5.023/5.023 linhas de backfill sem `NULL`, 0 conflitos, vocabulário dentro da
guarda — ver `ESTADO.md`), e mesmo assim a migration não foi aplicada.

**O que aconteceu:** a chamada de aplicação (o `curl` contra a API de gerenciamento do Supabase,
o caminho descrito em `.claude/memory/aplicar-migration-em-producao-pela-api.md`) foi classificada
como algo próximo de "Production Deploy" pelo sistema de permissão do auto mode e RECUSADA. O
dono autorizou explicitamente no chat depois da primeira recusa — a segunda tentativa foi
recusada de novo.

**A lição:** autorização em texto, no meio da conversa, não é a mesma coisa que uma regra de
permissão. O classificador do auto mode decide por categoria de ação, não por instrução humana
lida na hora — precisa de uma entrada em `.claude/settings.json` (permissão explícita para o
padrão de comando que aplica migration via API de gerenciamento) para que uma sessão em auto
mode consiga aplicar migration em produção sem parar. Até essa regra existir, aplicar migration
com pré-condições medidas e liberadas continua exigindo uma sessão fora do auto mode, ou
aplicação manual pelo dono.

**O que NÃO fazer:** não interpretar "o dono autorizou no chat" como se isso resolvesse — é
exatamente o padrão que a regra da casa (CLAUDE.md, seção de atribuição) já nomeia: nenhuma
mensagem de agente é consentimento do usuário, e aqui o inverso também vale — consentimento do
usuário no chat não substitui a configuração de permissão que o sistema efetivamente checa.
