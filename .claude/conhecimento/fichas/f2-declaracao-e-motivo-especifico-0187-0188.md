---
id: f2-declaracao-e-motivo-especifico-0187-0188
tipo: defeito
toca:
  - Supabase/migrations/0187_o_tipo_que_chegava_sem_leitor_declarado.sql
  - Supabase/migrations/0188_o_motivo_que_a_checagem_sabia_e_nao_dizia.sql
  - Supabase/test/cobertura_de_tipos.test.sql
  - Supabase/test/motivo_especifico.test.sql
  - Supabase/test/perguntas.test.sql
  - Arquitetura do Sistema/3 Estado e Execução/ARQUITETURA_ALVO_E_ROADMAP.md
prova: Supabase/test/run.sh
ancora: Supabase/migrations/0187_o_tipo_que_chegava_sem_leitor_declarado.sql#fn_cobertura_de_tipos()
ancora_sha: b5fa07c9914a
substitui: []
---

# 0187+0188: D6 por declaração, a suspeita MUTUOS/FAT_INTRAGRUPO confirmada, e o motivo que a checagem já sabia

**Escritas em 22/09/2026 (sessão 100). NENHUMA aplicada em produção** — a sonda segue em `0181`.
A `0186` (pré-requisito) tem as pré-condições MEDIDAS e LIBERADAS contra produção nesta mesma
sessão, mas a aplicação foi RECUSADA duas vezes pelo classificador de permissão do auto mode
(ver `.claude/memory/`). Ordem de aplicação: `0186` → `0187` → `0188`.

## `0187` — D6 deixa de ser contado por exigência lexical e passa a ser respondido por declaração

A `0185` (nove exigências lexicais para tipos itemizados) tinha sido REPROVADA na medição contra
produção da sessão 99: em relatório itemizado o conceito não está no rótulo (o rótulo é o item;
o conceito é o TIPO do documento) — ver
[a ficha da 0185](f2-localizador-chave-pendencia-falsa.md). Isso deixou D6 sem como ser
respondido sem inventar exigência que reprova o documento certo.

`0187` responde D6 por **declaração**, não por leitura de conteúdo. Dos **36 tipos ativos** da
taxonomia, 6 têm exigência viva e os **30 restantes são declarados** em `taxonomia_tipo_cobertura`:
`consumidor_nomeado` (2: MUTUOS→`fn_reconciliar_mutuos`, BALANCETE→`fn_reconciliar_arvore`) ou
`sem_consumidor` (28, sempre com motivo E efeito — regra 1). `fn_cobertura_de_tipos()` devolve o
veredito D6 estrito: `SEM_COBERTURA` (tipo ativo sem exigência viva e sem declaração) ou
`DECLARACAO_QUEBRADA`, que tem TRÊS causas: (1) o consumidor nomeado não existe mais em `pg_proc`;
(2) o **marcador** (trecho de uma linha que faz a leitura) sumiu do corpo publicado de
`marcador_em` — o consumidor ou o despachante que o chama; (3) **duplo registro**: o tipo ganhou
exigência viva e a declaração ficou. Roda igual em teste e em produção.

**Corrigido após revisão independente (22/09/2026, antes de qualquer apply):**
- *O nome não prova a leitura.* Tirar `'BALANCETE'` do `if v_tipo in (...)` de
  `fn_reconciliar_por_documento` desligava a leitura sem que nome nenhum sumisse de `pg_proc`, e a
  declaração seguia verde. Agora `marcador`/`marcador_em` são obrigatórios para
  `consumidor_nomeado` (check na tabela), comparados com `\r` removido dos dois lados (produção
  guarda corpo com CRLF — `.claude/memory/ancora-de-texto-quebra-com-crlf.md`).
- *DF_AUDITADA virou `sem_consumidor`.* O próprio efeito dizia "no caso típico ninguém lê a DF": só é
  lida como balanço SUBSTITUTO quando a entidade não tem BALANCO. Declarar consumidor deixava D6 verde
  sobre uma leitura que não acontece (regra 7).
- *O motivo de cada tipo diz o que foi medido PARA ELE*: GARANTIAS/AVAIS_FIANCAS/DEBITOS_TRIB têm zero
  documentos (nada medido — ficam sem exigência pela FORMA); CONTINGENCIAS tem 9 dos 17; os demais
  são "parte dos 17 da medição agregada" (a contagem por tipo não foi registrada).
- *O {saldo_mutuos} da pergunta 5.1 deixou de ler léxico.* A primeira versão só tirou `e.ativo` do
  léxico da exigência desativada, com um marcador de sonda tautológico
  (`(e.ativo or e.conceito = 'saldo_de_mutuo')`). A revisão mediu: no arranjo real da canastra (chave
  = par de empresas) a pergunta ao cliente dizia "(não localizado)"; item + total somava 300 em vez de
  150; matricial somava as colunas (20.158 em vez de 11.079). Agora `fn_saldo_mutuos_do_documento`
  (pura) + `fn_saldo_mutuos_texto`: o documento MUTUOS é o conceito; coluna do exercício mais
  recente; total geral estrutural se houver, senão soma dos itens; e "não foi possível apurar o
  saldo: <motivo>" quando não dá. A sonda EXECUTA a função sobre os quatro arranjos
  (`instalacao_sonda_saldo_mutuos`, 4 linhas) em vez de procurar texto.

Censo medido contra produção (banco na `0181`, 22/09/2026): **24 tipos com documento**, **6 com
exigência viva** (BALANCO, DRE, COMBINADO, FATURAMENTO_24M, MAPA_DIVIDA, FLUXO_CAIXA), **18
sem**.

## A suspeita da sessão 99, investigada e CONFIRMADA

A sessão 99 deixou aberta, sem investigar, a suspeita de que MUTUOS e FAT_INTRAGRUPO (exigências
`origem='proposta'` da `0113`, em produção desde então) tinham o MESMO defeito que reprovou a
`0185` — o rótulo é o item, não o conceito. Esta sessão investigou: as 5 pendências
`linha_exigida_ausente` ABERTAS em produção de MUTUOS (1), FAT_INTRAGRUPO (3) e CONTRATO_SOCIAL
(1) foram conferidas UMA A UMA, olhando o documento — **TODAS falsas**. `0187` corrige: MUTUOS e
FAT_INTRAGRUPO passam a `ativo=false`; CONTRATO_SOCIAL ganha um localizador de seção (só pode
FAZER PASSAR, nunca abrir pendência nova). Previsão medida do efeito, depois de aplicar: 5
pendências resolvidas, 0 abertas. A do CONTRATO_SOCIAL foi MEDIDA pela sessão principal (22/09/2026): na versão vigente do documento
`9ae9ca0b-7b6a-4fa1-bf23-ef3cc8805ffc` (GLOBAL STORE), 4 das 6 linhas têm `secao` com 'capital' e
'social'. A 1 pendência `aceita_com_ressalva` de MUTUOS fica intocada
pela migration — é o comportamento pré-existente para exigência desativada; só o próximo
recompute daquele caso a fecha.

`0185` e seu teste foram DESCARTADOS do repositório nesta sessão (nunca chegaram a produção); o
número `0185` fica como lacuna, explicado no `Supabase/README.md`.

## `0188` — o motivo que a checagem já sabia e achatava, e o recado da DRE líquida

`fn_registrar_reconciliacao` (a versão que a `0186` corrige) passa a receber motivo ESPECÍFICO
por checagem em vez de sempre `precondicao_nao_satisfeita` genérico — `ativo_passivo_pl`,
`caixa_bp_fluxo`, `despfin`, `receita` passam `linha_nao_localizada` / `sem_periodo_par` /
`unidade_divergente` onde o código JÁ SABIA a diferença e simplesmente não passava adiante.
Medido em fixtures perturbadas: 53 linhas ganham motivo específico (12 + 15 + 26).

**Armadilha evitada, e por que importa:** os despachantes escritos na `0152` fazem
`exit when resultado <> 'precondicao_nao_satisfeita'`. Se o novo motivo mudasse também
`resultado`, os três motivos novos parariam o laço no primeiro período. `0188` mantém `resultado`
achatado (o vocabulário que o portal/export já lê não muda) e só acrescenta o motivo verdadeiro
em `motivo_precondicao` — coluna que a `0186` já criou.

`taxonomia_linha_alternativa` dá o recado quando a ausência é real e legítima: para
DRE/despesa_financeira, a alternativa `['resultado','financeiro']` exceto `['antes']` — medida
contra produção, casa "resultado financeiro liquido" em **71 entidades**. E o localizador de
juros bancários `['juros','bancari']` exceto `['receita','aplicac']` — medido: casa "juros e
comissoes bancarias" em **8 linhas, 4 entidades**, sem casar "juros de aplicações" (que é
receita, não despesa — a armadilha que a sessão 99 já tinha registrado).

**Esperado em produção** (previsão, não medição — `0188` não foi aplicada): das 52 pendências
abertas de despesa financeira, ~50 mudam de texto (recado da DRE líquida); a 1 falsa de juros
bancários só resolve no próximo recompute do caso que a tem.

**Corrigido após revisão independente (22/09/2026):**
- *A 0188 exige a 0186 e agora diz isso na instalação.* Sem a 0186 ela instalava LIMPA (plpgsql só
  resolve coluna em runtime) e toda `fn_reconciliar_*` morria na primeira gravação — com o n8n em
  `continueRegularOutput`, zero reconciliações e nenhum erro visível. O bloco (0) aborta com "0188
  exige a 0186 aplicada antes" se faltar a coluna `reconciliacao.motivo_precondicao` ou o corpo da
  0186 em `fn_registrar_reconciliacao`.
- *A tolerância absoluta da despfin está na BASE.* Era `50.000 × fator` = R$ 50 MILHÕES numa DRE em
  milhar; medido em produção, 1 das 33 despfin 'ok' era falsa (R$ 12,4 mi "confere"). Receita (0023)
  e caixa (0031, `100 × fator`) têm o mesmo vício e **não foram corrigidas** — não medidas; a
  consulta de alcance está no `Supabase/README.md`.

## A medição (regra 2)

`0187`: 34 asserts em `cobertura_de_tipos.test.sql` (27 + 7 do bloco 3b) e 4 no bloco 13 de
`perguntas.test.sql`. Desligando: declaração 4 · desativação 2 (re-medida pela sessão principal,
banco reconstruído do zero: 2, os mesmos) · localizador de seção 4 · resolução dirigida 4.
Revisão: `{saldo_mutuos}` de volta ao léxico 5 (4 do bloco 13 + 1 da sonda de corpo) · total não
excluído dos itens 3 · coluna não escolhida 3 · ramo do marcador 3 (2 do bloco 3b + 1 sonda) ·
check do marcador 1 · DF_AUDITADA de volta a consumidor 1. Os textos do item 5 não têm assert (é
texto de declaração, não comportamento).

`0188`: 30 asserts em `motivo_especifico.test.sql` (28 + 2 do bloco 5). Desligando: motivo específico 8 · retorno
achatado 4 (re-medido pela sessão principal do zero: 4, os mesmos, incluindo os dois do
invariante) · alternativa 4 · atualização de descrição 1 · bancari código 1 · bancari seed 2 ·
reescrita dirigida 2. Revisão: guarda da 0186 — provada num banco descartável (0181 + 0187 sem 0186:
aborta; guarda desligada: instala com rc=0; com a 0186: passa) · tolerância na base 2 (bloco 5 +
sonda de corpo).

## O que ainda falta

- **Aplicar as três em produção, nesta ordem: `0186` → `0187` → `0188`.** Nenhuma foi aplicada —
  a `0186` está medida e liberada, mas o classificador de permissão do auto mode recusou a
  aplicação duas vezes, mesmo com autorização do dono no chat.
- **F2.3** (checagem real para FAT_INTRAGRUPO) segue como declaração `sem_consumidor`, não como
  checagem — desenho novo, não decidido.
- **F2.2** (MAPA_DIVIDA fino: taxa, vencimento, covenant) depende da F3.
