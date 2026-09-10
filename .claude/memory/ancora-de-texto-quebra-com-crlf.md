---
name: ancora-de-texto-quebra-com-crlf
description: âncora multi-linha sem `\r?` casa contra corpo LF (toda suíte local) e acha ZERO contra corpo gravado em CRLF (produção) — o corpo que pg_get_functiondef devolve pode ter \r\n
metadata:
  type: architecture
---

A `0161` e a `0162` patcheavam `fn_registrar_diagnostico` por âncora sobre
`pg_get_functiondef`, com `regexp_matches`/`regexp_replace` e padrão
MULTI-LINHA — mas sem `\r?` antes do `\n` que separa os fragmentos.

**Passaram em toda suíte local e abortaram em produção**, em 10/09:

```
0161: o bloco do format() de periodo_incorreto não foi encontrado UMA
      vez (achei 0)
0162: o patch apagou o da 0161 — abortado
```

**Por que local nunca pegaria isso.** O `Supabase/test/run.sh` monta o corpo
da função do zero, sempre com `\n` (LF). Produção não tem essa garantia: o
corpo publicado (`pg_get_functiondef`) é o que está GRAVADO, e se o texto
passou por um editor ou colagem com terminador de linha do Windows uma vez —
mesmo antes de qualquer migration desta casa — ele fica em `\r\n` (CRLF) para
sempre. Uma âncora `'...linha 1\n linha 2...'` casa em LF e acha ZERO em
CRLF, porque o caractere entre as duas linhas não é o mesmo.

**A `0142` já sabia disso** (ver o cabeçalho dela: "produção guarda o corpo
com CRLF e o banco montado do zero guarda com LF") e por isso usa `\r?\n` —
o `?` torna o `\r` opcional, casando os dois. A `0143`, a `0145` e a `0160`
seguiram o mesmo hábito. A `0161`/`0162` não seguiram, e a lição não estava
em nenhum portão que acusasse a ausência.

**A correção, na `0163`:** parar de patchar por âncora e reemitir a função
INTEIRA (`create or replace function` com o corpo verbatim), pela mesma
razão de `nunca-corrigir-funcao-por-replace.md` — só que aqui, ADEMAIS,
qualquer âncora que a reemissão precisasse checar depois foi normalizada com
`replace(corpo, chr(13), '')` antes do `position()`, para a checagem em si
não repetir o mesmo raciocínio frágil.

**A guarda de repositório:** `Supabase/test/guarda_ancora_crlf.py` (ligado
no `run.sh`) varre `Supabase/migrations/*.sql` e reprova qualquer migration
que patcheie corpo de função (`pg_get_functiondef`) com `regexp_matches`/
`regexp_replace` e um padrão MULTI-LINHA sem `\r?` — antes de aplicar
migration nenhuma, sem precisar do banco de pé.

**Regra:** âncora que cruza linha de um corpo de função tem de tolerar
`\r?` antes de cada `\n` — ou, melhor ainda, não usar âncora nenhuma e
reemitir a função inteira.
