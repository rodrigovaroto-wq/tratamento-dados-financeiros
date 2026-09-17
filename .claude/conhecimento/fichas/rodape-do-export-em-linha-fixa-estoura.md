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

**O MESMO LIMITE FIXO APARECEU DUAS VEZES NA MESMA PASSADA.** Ao reproduzir o
caso real com `portal/scripts/gerar-export-do-banco.mts`, o `execFileSync`
estourou o `maxBuffer` PADRÃO DO NODE (1 MB): a consulta de `campo_extraido`
(7.670 linhas) devolve ~2 MB de JSON, e o `JSON.parse` recebia a string cortada
no meio, morrendo com erro de sintaxe que não diz nada sobre a causa. Corrigido
junto. Ferramenta de repro que só funciona em caso pequeno falta exatamente
quando é mais necessária — o caso grande é onde o defeito de layout aparece.

**VERIFICADO PONTA A PONTA no caso real** (não só na fixture): o book do "AMO
teste 00" foi gerado com 118 documentos, 7.670 campos, 26 premissas e 1.193
vínculos. Na aba Modelagem, o modelo termina na linha 1.332, PARÂMETROS cai em
1.401 e BASE DO MODELO em 1.415 — rodapé depois do modelo, sem sobreposição. O
modelo institucional montou inteiro (Capa, Output com três cenários, Income
Statement, Balance Sheet, Working Capital, Cash Flow), com zero avisos de
"NÃO ESTÁ PROJETÁVEL".
