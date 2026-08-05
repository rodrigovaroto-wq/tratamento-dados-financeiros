# Assets órfãos de uma captura que nunca chegou inteira

**Estes 15 arquivos não servem para nada no estado atual, e esta pasta existe para dizer isso em
vez de deixá-los parecendo conteúdo.**

## O que aconteceu

Em 05/08/2026 o dono salvou a tela de Modelagem pelo navegador e subiu os arquivos pelo
*Add files via upload* do GitHub (commit `9cdadc4`). O upload achatou tudo na **raiz do
repositório** e — o que inutiliza o conjunto — **o `.html` não veio**. Chegaram só os *bundles*
que o HTML referencia: 13 `.js.download` e 2 `.css`.

Sem o HTML não há o que renderizar: estes arquivos são o *estilo e o script* de uma página que não
está aqui. Também não contêm dado do caso — foi conferido, **nenhum dos 15 tem a string
`supabase`**, nem chave, nem URL de projeto.

É a **segunda vez** que o upload achata na raiz: na sessão 32 aconteceu o mesmo, e ali o HTML veio,
então os assets voltaram para a pasta `_files/` que o próprio HTML referencia e a captura funciona
— ver `test-data/capturas/2026-08-04-v35-modelagem/`.

## 10 dos 15 são duplicata exata

Comparado por `sha256` contra a captura de 04/08 que já está versionada: **10 arquivos são
byte-a-byte idênticos** aos que já existem em `2026-08-04-v35-modelagem/…_files/`. Os 5 exclusivos
desta pasta são `1f_g8kk-0p-x3.js.download`, `2u-nj-ic3ionp.js.download`,
`3pao8xybze-_k.js.download`, `turbopack-06bdk18vehoby.js.download` e `2h4-22nktctjm.css` — chunks
de um build mais novo do Next, e igualmente inúteis sem o HTML.

## O que fazer com esta pasta

**Apagar é a ação correta**, e ela ficou aqui só porque apagar arquivo do dono não é decisão de
quem organiza. São ~740 KB de JavaScript minificado que nenhum teste, script ou CI referencia
(conferido com `grep -rn "js.download"` fora de `test-data/capturas/`).

Duas saídas, nesta ordem de preferência:

1. **O dono subir o `.html` salvo.** Aí os assets voltam para a pasta `_files/` ao lado dele, a
   captura passa a abrir offline, e esta pasta some — vira uma captura de verdade, como a de 04/08.
   Para uma captura nova, o que importa é **o arquivo `.html`**; a pasta `_files/` sozinha não
   prova nada.
2. **Apagar a pasta inteira.** Nada se perde: 10 arquivos já existem versionados na captura de
   04/08, e os outros 5 são bundles de framework que o build regenera.

Para o que a próxima captura precisa provar, aliás, o `.html` renderizado pelo servidor basta — é
ele que traz o estado da tela (parâmetros, premissas, linhas com papel e unidade), que foi
exatamente o que permitiu reconstruir o caso real em
`db/test/fixture_modelagem_v35.sql`.
