---
id: f2-declaracao-e-motivo-especifico-0187-0188
tipo: defeito
toca:
  - Supabase/migrations/0187_o_tipo_que_chegava_sem_leitor_declarado.sql
  - Supabase/migrations/0188_o_motivo_que_a_checagem_sabia_e_nao_dizia.sql
  - Supabase/test/cobertura_de_tipos.test.sql
  - Supabase/test/motivo_especifico.test.sql
  - Arquitetura do Sistema/3 Estado e Execução/ARQUITETURA_ALVO_E_ROADMAP.md
prova: Supabase/test/run.sh
ancora: Supabase/migrations/0187_o_tipo_que_chegava_sem_leitor_declarado.sql#fn_cobertura_de_tipos()
ancora_sha: b68bdc3a5e7c
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

`0187` responde D6 por **declaração**, não por leitura de conteúdo: `taxonomia_tipo_cobertura` é
uma linha por tipo taxonômico ATIVO (30 no total), com `consumidor_nomeado` (3: MUTUOS→
`fn_reconciliar_mutuos`, BALANCETE→`fn_reconciliar_arvore`, DF_AUDITADA→
`fn_reconciliar_intragrupo` — cada um confirmado lendo o corpo vigente da função, não supondo
pelo nome) ou `sem_consumidor` (27, sempre com motivo E efeito — regra 1). `fn_cobertura_de_tipos()`
varre a tabela e devolve o veredito D6 estrito: `SEM_COBERTURA` (tipo ativo sem linha na
taxonomia) ou `DECLARACAO_QUEBRADA` (linha aponta um consumidor que não existe mais em
`pg_proc`). Roda igual em teste e em produção.

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
pendências resolvidas, 0 abertas. A 1 pendência `aceita_com_ressalva` de MUTUOS fica intocada
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

## A medição (regra 2)

`0187`: 27 asserts em `cobertura_de_tipos.test.sql`. Desligando: declaração 4 · desativação 2
(re-medida pela sessão principal, banco reconstruído do zero: 2, os mesmos) · localizador de
seção 4 · resolução dirigida 4 · `{saldo_mutuos}` 3+1.

`0188`: 28 asserts em `motivo_especifico.test.sql`. Desligando: motivo específico 8 · retorno
achatado 4 (re-medido pela sessão principal do zero: 4, os mesmos, incluindo os dois do
invariante) · alternativa 4 · atualização de descrição 1 · bancari código 1 · bancari seed 2 ·
reescrita dirigida 2.

## O que ainda falta

- **Aplicar as três em produção, nesta ordem: `0186` → `0187` → `0188`.** Nenhuma foi aplicada —
  a `0186` está medida e liberada, mas o classificador de permissão do auto mode recusou a
  aplicação duas vezes, mesmo com autorização do dono no chat.
- **F2.3** (checagem real para FAT_INTRAGRUPO) segue como declaração `sem_consumidor`, não como
  checagem — desenho novo, não decidido.
- **F2.2** (MAPA_DIVIDA fino: taxa, vencimento, covenant) depende da F3.
