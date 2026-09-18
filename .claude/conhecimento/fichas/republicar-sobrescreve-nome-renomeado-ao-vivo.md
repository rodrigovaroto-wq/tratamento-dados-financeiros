---
id: republicar-sobrescreve-nome-renomeado-ao-vivo
tipo: armadilha
toca:
  - N8N/preparar-republicacao.mjs
  - N8N/conferir-publicado.mjs
prova: N8N/test/*.test.mjs
substitui: []
---

# Armadilha: republicar sobrescreve um nome que o dono trocou no editor

**Achado em:** preparação da republicação da ingestão, 18/09/2026.

**Sintoma:** o workflow publicado (`na1AEv3m8fjDXlwM`) estava com `name`
"Oria — SARF (Sistema Automático de Reestruturação Financeira)" — um rebranding
do dono, feito direto no editor do n8n, sem registro em `ESTADO.md` nem em
`.claude/memory/`. O repositório ainda gerava o nome técnico de fatia
("E1 Ingestão + Diagnóstico + E2 Extração-Sombra + E3 Reconciliação Classe A
(Fatia 1)").

**Por que importa:** `preparar-republicacao.mjs:228` grava
`name: repo.name ?? vivo.name` — o nome do repositório sempre ganha, porque
nunca é `null`. Republicar sem perceber a divergência reverteria o rebranding
**em silêncio**: o PUT teria sucesso, `conferir-publicado.mjs` teria dado OK
(ele confere nós, não o `name` do topo), e o dono só notaria ao abrir o editor
e ver o nome antigo de volta.

**O que fez a armadilha aparecer ANTES de agir:** `conferir-publicado.mjs`
casa repositório↔publicado pelo `name` (é a chave declarada no próprio
script: "renomear o workflow no editor quebra esta ligação"). Antes de rodar
`republicar.sh`, uma leitura do nome ao vivo via API (`GET
/api/v1/workflows/<id>`) bastou para notar a divergência — não é preciso
adivinhar, o nome está ali.

**A correção:** perguntado ao dono qual nome preservar (não há como o
repositório saber sozinho se uma divergência de nome é rebranding deliberado
ou nome desatualizado do gerador). Resposta: preservar "SARF". O gerador
(`N8N/build-workflow.mjs`) passou a gravar o nome de marca; o nome técnico de
fatia foi para `meta.note`, para quem abre o JSON continuar sabendo o que o
workflow faz por dentro.

**A lição que generaliza:** antes de qualquer republicação, `GET` o `name` ao
vivo e compare com o do repositório — é um `curl` a mais, e evita reverter uma
decisão de produto tomada fora do repositório. Vale para qualquer campo que o
merge (`preparar-republicacao.mjs`) prefira o lado do repositório: o
repositório não é sempre a fonte da verdade para tudo que existe no artefato
publicado — só para o COMPORTAMENTO (nós, conexões, `jsCode`). Metadado de
apresentação (nome, descrição) pode ter sido decidido ao vivo, e precisa ser
conferido, não presumido.
