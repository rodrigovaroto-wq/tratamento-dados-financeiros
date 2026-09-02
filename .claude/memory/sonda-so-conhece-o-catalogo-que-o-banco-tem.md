---
name: sonda-so-conhece-o-catalogo-que-o-banco-tem
description: fn_instalacao_conferir() verde não significa que a rodada vai rodar — o catálogo dela mora DENTRO do banco, então um banco atrasado não sabe o que lhe falta; quem responde a outra ponta é Supabase/test/conferir-chamadas.mjs
metadata:
  type: architecture
---

A entrada [sonda-responde-pelo-banco](sonda-responde-pelo-banco.md) continua valendo inteira: a
sonda é a autoridade, e nenhum arquivo do repositório é. **Esta entrada é o limite dela**, e o
limite não é um defeito — é construção, e por isso não se conserta lá.

## O que foi medido (02/09/2026)

O `ESTADO.md` declarava produção na `0150`. Um banco montado parado exatamente aí:

| pergunta | resposta |
|---|---|
| `fn_instalacao_conferir()` acusa ausência? | **não** |
| os nós Postgres do `workflow.e1-ingestao.json` resolvem? | **três não** |

```
nó "Abrir Lote"            fn_abrir_lote_execucao(uuid, text, jsonb)    (0156)
nó "Reconciliar Lote"      fn_reconciliar_caso(uuid)                    (0152)
nó "Reconciliar (Classe A)" fn_reconciliar_por_documento(uuid, unknown) (0152)
```

`Abrir Lote` é o primeiro nó depois de o orçamento aprovar o lote: a rodada **morre no começo**.

## Por que a sonda não podia ver

O catálogo dela (`instalacao_requisito`) é **dado dentro do banco**, escrito pelas migrations. Um
banco na `0150` tem o catálogo da `0150` — ele não pode conhecer um requisito que só a `0156`
escreveu. A pergunta que a sonda responde é *"o que ESTE banco sabe que deveria ter, está aqui?"*.

A outra ponta — *"o que o REPOSITÓRIO chama, está aqui?"* — só o repositório pode perguntar,
porque só ele conhece o código que vai rodar. É `Supabase/test/conferir-chamadas.mjs`:

```bash
CONFERIR_PSQL="psql 'postgresql://…@…supabase.co:5432/postgres'" \
  node Supabase/test/conferir-chamadas.mjs
```

**0** = tudo resolve · **1** = achei chamada quebrada (nomeando o nó) · **2** = não consegui
perguntar, que não é "passou".

## E por que ele confere CHAMADA e não nome

`fn_reconciliar_por_documento` **existe** na `0150`; a `0152` só lhe acrescentou `p_escopo`. Um
conferidor de presença de nome a daria por presente e a rodada morreria nela igual. Por isso o
conferidor usa `PREPARE`, que faz o Postgres resolver nome **e tipos** — e que não executa nem
escreve nada, então é seguro apontar para produção.

## As duas coisas que continuam manuais, e a segunda ninguém detecta

1. **Aplicar as migrations** (`Supabase/README.md` tem a lista). Aplicação incremental sobre um
   banco atrasado foi ensaiada em 02/09 para as `0151`–`0156`: **0 falhas**. Vale ensaiar de novo
   quando a mudança alterar assinatura — a suíte monta do zero e nunca vê essa classe de erro.
2. **Reimportar o workflow no n8n.** O n8n executa o JSON **importado**; merge não reimporta, e
   **nada no CI acusa isso**. O sinal é por efeito: depois da `0156`, `lote_execucao` ganha linha
   com `fechado_em` nulo já no começo da rodada.
