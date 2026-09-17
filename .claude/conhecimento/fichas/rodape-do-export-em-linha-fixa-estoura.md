---
id: rodape-do-export-em-linha-fixa-estoura
tipo: armadilha
toca:
  - portal/src/lib/export-modelagem.ts
prova: portal/scripts/verificar-export.mts
substitui: []
---

# Armadilha: endereço fixo no rodapé do export estoura quando o caso cresce

**Achado em:** produção, mandato "AMO teste 00", 17/09/2026 — o dono abriu
`/casos/<id>/export` e recebeu erro em vez de arquivo.

**Sintoma:** `Modelagem: o modelo chegou à linha 1349 e o bloco de PARÂMETROS
começa em 186. Aumente LINHA_PARAM_INICIO (e LINHA_BASE_INICIO adiante)`.

**Causa raiz:** `LINHA_PARAM_INICIO` e `LINHA_BASE_INICIO` eram constantes (186
e 200). Elas precisam ser conhecidas ANTES de o modelo ser escrito, porque toda
fórmula de coluna cita `refEntidade`/`refCorte` — daí a escolha por linha fixa.
Só que o bloco "A CONFIGURAÇÃO DE MODELAGEM" escreve **uma linha por premissa
ativa e uma linha por linha com premissa vinculada**, e isso cresce com o
mandato. No caso que estourou: 1 título + 26 premissas + 1.188 linhas = 1.215
linhas, contra as ~134 de esqueleto que o 186 cobria com folga.

**O que a guarda fez de certo:** abortou em vez de sobrescrever linha de modelo.
Um arquivo com o rodapé por cima do modelo abriria normalmente e estaria errado
— exatamente o defeito que este projeto chama de lente central. A guarda fica.

**A correção:** o offset passa a somar o tamanho do único bloco que cresce, e
esse tamanho é conhecido antes de escrever (é `config.premissas.length` +
`config.linhas` com premissa). Caso sem configuração mantém 186/200 exatamente
como antes — o termo soma zero.

**Medição (regra 2):** invariante novo em `verificar-export.mts` com 1.200
linhas configuradas. Com a constante antiga religada, ele reproduz o erro de
produção palavra por palavra ("chegou à linha 1318 e o bloco de PARÂMETROS
começa em 186"); com a correção, 723 verificações OK / 0 falhas (eram 721).

**A lição que generaliza:** endereço fixo em planilha gerada é dívida que vence
quando o cliente fica grande. Se o bloco de baixo tem de ter endereço conhecido
de antemão, o endereço não precisa ser CONSTANTE — precisa ser CALCULÁVEL antes
da escrita. A pergunta certa não é "qual número é grande o bastante?", é "o que
faz este bloco crescer, e eu consigo contar isso antes?".
