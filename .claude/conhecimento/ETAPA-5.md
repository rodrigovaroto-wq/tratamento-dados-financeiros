# Etapa 5 — a extração do HANDOFF, e por que ela produziu ZERO fichas

**Rodada em 13/09/2026.** O plano previa "extrair fichas das 69 sessões já escritas, uma passada,
revisada por amostragem", com a ressalva de que só valeria se as etapas anteriores tivessem
provado ganho (provaram: −79% no custo de recuperação). Ela rodou. O resultado é **nenhuma ficha
nova**, e o motivo é o achado mais valioso desta camada.

## O critério, que era restritivo de propósito

Uma lição do HANDOFF só vira ficha se as três valerem:

1. não está em nenhuma das 25 fichas existentes;
2. **não dá para derivar lendo o código**;
3. uma sessão futura ficaria surpresa e grata de saber antes de começar.

## As oito candidatas, e onde o repositório já as carrega

Oito lições foram extraídas e escritas. As oito foram **descartadas no critério 2**, e cada
descarte tem um endereço:

| Lição candidata | Onde o repositório já a carrega |
|---|---|
| ZIP do .xlsx regravado sem compressão (0,3 MB → 4,3 MB, 14×) | `portal/src/lib/export.ts:3473` — *"COMPRESSÃO EXPLÍCITA. O default do JSZip é `STORE`…"*, com o número |
| Portal declara parada durante silêncio legítimo da extração | `portal/src/lib/espera-do-lote.ts:123-160` — 40 linhas com o cronômetro do lote de 190 (28min48s sem uma escrita) |
| Merge de entidade desempatava por ordem alfabética | `Supabase/migrations/0153_a_entidade_ambigua_nao_decide.sql:34` — *"BIOENERGIA vem antes de IMOBILIÁRIA, e foi só isso que decidiu"* |
| Estimador de custo plano errava 5× | `N8N/lib/custo.mjs` + o medidor `N8N/medir-custo-book.mjs`, que reprova no CI |
| Fixture é sistematicamente mais fácil que produção | `Verificação/variacoes.mts:1-20` + a ficha `portao-mede-a-entrada-de-producao` |
| Caractere invisível em rótulo quebra a soma | `Verificação/variacoes.mts` — é uma das variações que o arnês injeta |
| Texto em célula de referência propaga `#VALUE!` | `portal/src/lib/export-estilo.ts` |
| Nó Postgres em modo `single` | já coberto por `no-postgres-novo-vai-como-ramo-terminal` (e a versão escrita misturava três medições diferentes) |

## O achado

**A regra 5 desta casa funcionou.** *"Comentário explica POR QUÊ, com o número medido junto"* foi
seguida com tanta consistência que as lições do HANDOFF já vivem no artefato que as produziu — no
comentário da função, no nome e no corpo da migration, no cabeçalho da suíte. O que faltava nunca
foi registrar: era **encontrar**. E encontrar é exatamente o que a Etapa 1 resolveu, porque o
índice aponta para esses lugares.

Escrever as oito teria criado oito cópias de coisas verdadeiras — oito coisas a mais para
envelhecer, em desacordo com a fonte, sem nenhum portão capaz de acusar a divergência. Duas delas
já nasceram **erradas**: a do silêncio na extração citava a cadência de 8 s, que virou 73 s na
troca de provedor, e propunha uma correção que já está implementada há semanas
(`semProgressoMs(n)`, proporcional ao lote).

## O critério de pronto da Etapa 5, medido

> *"Pronto quando: as perguntas da Etapa 0 sobre história antiga forem respondidas sem abrir o
> HANDOFF."*

A pergunta histórica da linha de base — *"o que já se tentou no upload de lote grande?"* — é
respondida pelo briefing em 3.352 bytes, com a ficha do 413, os nós do n8n envolvidos, a sessão do
HANDOFF **com o número da linha** e os commits do assunto. Ela não exige abrir o HANDOFF. **Critério
cumprido sem escrever ficha nenhuma.**

## A regra que fica para a próxima sessão

**Antes de escrever uma ficha, rode `buscar.mjs` sobre o assunto dela.** Se o briefing já aponta
para o lugar onde a lição está escrita, a ficha não deve existir — o ponteiro já é a memória. É o
princípio 1 aplicado a quem escreve, e não só a quem indexa.
