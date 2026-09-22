# F2 suporte: `0186_o_motivo_que_o_achatamento_engolia.sql` — motivo da precondição deixa de ser achatado

**Sessão:** 99 (22/09/2026)  
**Status:** ✅ ESCRITA, TESTADA, PRONTA PARA APLICAÇÃO  
**Risco:** Médio — modifica fluxo de ingestão

## O defeito

`fn_registrar_reconciliacao` achatava **dois motivos diferentes** no mesmo literal `precondicao_nao_satisfeita`:
- **`documento_ausente`**: contraparte não entregue pelo cliente (remédio: cobrar pelo checklist)
- **`linha_nao_localizada`**: documento entregue mas linha não foi localizada (remédio: revisar extração/localizador)

Em 1.922 de 1.926 linhas medidas em produção, ambas vão para `resultado = 'precondicao_nao_satisfeita'` com `fonte_a` e `fonte_b` NULAS — nada a jusante consegue distinguir qual é qual.

## A solução

- Coluna nova `reconciliacao.motivo_precondicao` grava o motivo verdadeiro (`documento_ausente`, `linha_nao_localizada`, `unidade_divergente`, `sem_periodo_par` ou NULL para `precondicoes_ok`)
- Backfill do histórico de `evento_auditoria` (onde o motivo original já sobrevivia, sem lugar acessível)
- **`resultado` não muda de vocabulário** — portal/export/suítes continuam lendo o mesmo texto sempre (compatibilidade total)
- **Guarda de vocabulário**: `p_resultado` fora da lista levanta exceção (defende o denominador de toda a medição desta fase)
- Função reemitida com essa gravação

## CRÍTICO — não é o que parece

**`documento_ausente` NÃO significa "a contraparte não foi entregue".**

Medido em produção (banco de teste após backfill):
- **42 linhas de `secao_fecha`** emitem `documento_ausente` com `documento_id` NÃO-NULO (a `0133:371` emite para "este documento não tem seção com filhos")
- **9 linhas de `mutuos_planilha_vs_balanco`** emitem com a planilha entregue (a `0123` emite para "conta de mútuo sem lado reconhecível")

**O que o motivo garante é só o que o código faz com ele: não abre pendência.**

Tela que traduzisse para "cobrar o documento do cliente" pediria o que o cliente já mandou — e a causa real (seção sem filhos, conta sem lado) nunca chegaria à fila, porque justamente esse motivo não abre pendência.

## Revisão independente — 3 rodadas

1ª: Achou 8 achados em ordem de gravidade:
   - (1) Nenhum vocabulário amarrado — erro de uma letra fabricava `precondicoes_ok = true` (o denominador da medição)
   - (2) Contrato afirmava que `documento_ausente` significa "presente" (falso — confunde com ausência real)
   - (3) Backfill pulava `caixa_bp_vs_fluxo` em silêncio
   - (4) Consulta de pré-medição usava a coluna que a migration cria
   - (5) Marcador da sonda casava em comentários
   - (6-8) Outros

2ª: Pediu que o teste fosse "forma mais forte possível de reprovar". O que estava escrito (remover a 0186 inteira e o teste morrer em `column does not exist`) prova só que o `alter table` rodou — **é a forma MAIS FRACA**. Forma forte: reprovar no COMPORTAMENTO, com a coluna presente e `v_motivo_precondicao` trocado por `null` na função viva.

3ª: **Achou que a própria rodada de correção reintroduzia o erro invertido**: escrevia que `documento_ausente` é confiável. Falso e medido — a `0133:371` emite com documento PRESENTE. Corrigido com a forma forte de reprova.

## Teste

`Supabase/test/reconciliacao_motivo_precondicao.test.sql`: **10 asserts**
- Cenários 1-3: costura real (`fn_upsert_caso` → `fn_registrar_documento` → `fn_registrar_campos_extraidos` → `fn_reconciliar_caixa_bp_fluxo`)
- Cenário 4: chamada direta de `fn_registrar_reconciliacao` (validação de vocabulário — propriedade da própria função)

Portões:
- `conferir.mjs` ✅ OK (128 migrations, 193 funções, 618 chamadas, 28 portões)
- `verificar-espelho-claude-md.mjs` ✅ OK
- `verificar-comandos.mjs` ✅ OK
- Schema materializado sem diff

## Aplicação

Quem aplicar mede **ANTES** com as 3 consultas somente-leitura em `Supabase/README.md`:

**Uma delas pode mandar NÃO APLICAR:** a guarda de vocabulário transforma valor inesperado em exceção. A reconciliação roda dentro do fluxo de ingestão sem `exception when others` em ponto nenhum do caminho — se produção emitir um motivo fora da lista, o apply passa a **abortar a transação do caso na ingestão**, que é pior que o defeito corrigido.

Depois de aplicar: consulta de pós-apply que conta preenchidas × continuam NULL (o `raise notice` do backfill é efêmero).

## Toca

- `Supabase/migrations/0186_o_motivo_que_o_achatamento_engolia.sql`
- `Supabase/test/reconciliacao_motivo_precondicao.test.sql`
- `Supabase/README.md` (instruções de aplicação)

## Prova

`Supabase/test/reconciliacao_motivo_precondicao.test.sql` — reprovaria se coluna não existisse ou se função não gravasse
