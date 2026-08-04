# Camada de banco (Supabase / Postgres) — Fatia 1

Materializa o schema conceitual (`f0/05_schema_conceitual.md`) no Postgres do Supabase, no
subconjunto necessário para a **Fatia 1 (E1 — Intake determinístico)** da F1.

> **Fonte da verdade do estado = Postgres** (ver `docs/02`, trava de stack nº 1). O N8N é
> stateless; o portal Vercel lê/escreve via camada que respeita RLS.

## Faixas de numeração — leia antes de criar uma migration

| Faixa | De quem |
|---|---|
| `0001`–`0034` | já aplicadas em produção, **não tocar** |
| `0035`–`0099` | reservada ao **dono** |
| `0100`+ | **estagiário / colaborador** |

**Nunca reaproveite um número existente**, e buraco na sequência (`0034` → `0100`) é o
estado esperado.

**Por que a faixa existe:** duas migrations com o mesmo prefixo **não geram conflito de
merge**. O git aceita `0035_a.sql` e `0035_b.sql` vindas de branches diferentes sem uma
palavra; o laço de aplicação (`db/test/run.sh`, e a tabela abaixo) as aplica na ordem
alfabética do **sufixo**, que é arbitrária — e a "ordem de aplicação" documentada aqui passa
a mentir em silêncio. `db/test/run.sh` reprova prefixo duplicado antes de aplicar qualquer
coisa, então a colisão morre no PR e não no banco; a faixa é o que evita chegar até lá. Quem
aplica migration em produção é só o dono (ver `CLAUDE.md`).

## Migrations (aplicar nesta ordem)

| Arquivo | O que faz |
|---|---|
| `migrations/0001_schema_fatia1.sql` | Tipos enumerados (máquinas de estado de `f0/04`) + tabelas: `caso`, `entidade`, `periodo`, `taxonomia_tipo_documento`, `documento`, `documento_versao`, `checklist_item_status`, `pendencia`, `decisao`, `evento_auditoria`, `estagio_autonomia`. |
| `migrations/0002_seed_taxonomia_e_dial.sql` | Seed da taxonomia v1 (`f0/03`: Kit Básico + Variáveis) e do dial de autonomia inicial (`f0/04`). Idempotente. |
| `migrations/0003_rls_e_storage.sql` | RLS por tabela + bucket privado `documentos` no Storage. |
| `migrations/0004_funcoes_e1.sql` | Coluna `nao_sobrepujavel` + funções RPC do E1 (`fn_upsert_caso`, `fn_registrar_documento`, `fn_recomputar_completude`). |
| `migrations/0005_extracao_e2.sql` | Tabela `campo_extraido` + `fn_registrar_campos_extraidos` (extração em **N0/sombra**); redefine `fn_registrar_documento` p/ retornar os dois ids. |
| `migrations/0006_reset_funcoes.sql` | **Reset forçado das 4 funções RPC.** Roda sempre que houver dúvida sobre o estado delas (ex.: aplicações parciais/repetidas deixaram assinatura divergente) — derruba qualquer sobrecarga existente e recria do zero. **Seguro de rodar a qualquer momento** (idempotente). |
| `migrations/0007_justificativa_pendencia.sql` | Adiciona `p_justificativa` (parâmetro trailing com default) a `fn_registrar_documento` — a pendência de classificação incerta passa a incluir a explicação objetiva da IA ("Motivo: ..."), não só o número de confiança. |
| `migrations/0008_portal_revisao.sql` | Suporte de banco para o **Portal**: coluna `confianca`/`fonte`/`justificativa` em `documento` (para o dashboard não precisar fazer parsing de `evento_auditoria.depois`); `fn_registrar_documento` passa a gravá-las (mesma assinatura de 0007). Nova função `fn_revisar_documento` — a fila de revisão do portal chama essa RPC para confirmar/corrigir a classificação: resolve a pendência, registra `decisao`+`evento_auditoria`, realoca o checklist, recomputa a completude. |
| `migrations/0009_reconciliacao_e3.sql` | **E3 — Reconciliação, Classe A** (primeira fatia, `docs/04_RECONCILIACAO.md`). Tabela `reconciliacao` (log append-only de cada checagem); `fn_valor_conceito` casa `campo_extraido.chave` (texto livre) com um conceito canônico por termos obrigatórios/excludentes normalizados; duas checagens — `fn_reconciliar_ativo_passivo_pl` (Ativo = Passivo + PL no Balanço) e `fn_reconciliar_caixa_bp_fluxo` (Caixa do Balanço vs. saldo final do Fluxo de Caixa, aborta se as unidades divergirem); `fn_reconciliar_por_documento(documento_id)` é o ponto de entrada chamado pelo N8N logo após a extração — dispara as checagens do tipo do documento. Opera em **N1**: gera `pendencia` tipada (`divergencia_reconciliacao` ou `precondicao_nao_satisfeita`), nunca escreve um número como fato. |
| `migrations/0010_diagnostico_e1e2.sql` | **Diagnóstico de conteúdo + planilha organizada (E1/E2).** Colunas novas: `campo_extraido.secao` (agrupador de planilha), `documento.resumo`, `documento_versao.nota_legibilidade`. `fn_registrar_campos_extraidos` (mesma assinatura) passa a gravar `secao`. Nova função `fn_registrar_diagnostico` — chamada pelo N8N logo após a extração, com o bloco `diagnostico` da MESMA chamada de IA (não aumenta o nº de chamadas): preenche `entidade` só quando ainda vazia (fecha uma lacuna, nunca sobrescreve), confere tipo/período contra o que já está registrado (gera `pendencia` tipada `tipo_incorreto`/`periodo_incorreto`/`entidade_incorreta` quando diverge — nunca corrige sozinha), grava a `legibilidade` real do arquivo (antes hardcoded `'ok'`) e gera `arquivo_ilegivel` quando o conteúdo está ilegível. Idempotente (reaproveita pendência aberta da mesma checagem) e auto-resolve quando a divergência some (ex.: humano já corrigiu). |
| `migrations/0011_aceite_export_e4.sql` | **E4 — Portão 2 mínimo + suporte ao Export Excel** (`f0/07_output_spec.md`). Colunas novas em `campo_extraido`: `status_aceite` (`pendente`/`aceito`/`com_ressalva`), `aceito_por`, `aceito_em` — sem isso nenhuma linha extraída tinha mecanismo de aceite humano (princípio inegociável da spec: "nenhum número entra no export sem uma `decisao` de aceite humano ligada"). Nova função `fn_aceitar_extracao(documento_versao_id, autor, motivo)` — aceita **todas as linhas de uma versão de documento de uma vez** (granularidade v0; a spec permite refinar o "layout fino" depois), registra `decisao` (tipo `aprovacao`) + `evento_auditoria`. Idempotente. |
| `migrations/0012_secao_canonica_e4.sql` | **Seção canônica sugerida pela IA (classificação do export, E4).** Coluna nova `campo_extraido.secao_canonica`. `fn_registrar_campos_extraidos` (mesma assinatura de 0005/0006/0010) passa a gravá-la. A IA já classifica cada linha, na MESMA chamada de extração (não aumenta o nº de chamadas), numa seção canônica pelo **significado contábil** da conta (`n8n/lib/extract.mjs`). O classificador do export (`portal/src/lib/statement-templates.ts`) usa essa sugestão só como **fallback** (quando âncora/seção-livre/palavra-chave não classificaram) — reduz o bloco "Contas Não Classificadas" sem sobrepor a regra determinística. **N1/advisory**: afeta só ONDE a linha aparece; a linha continua pendente/âmbar até o aceite humano (anti-ancoragem, `docs/01`). Subir a IA para prioridade/auto-clear exige golden set + concordância medida (`f0/06`). |
| `migrations/0013_guarda_extracao_suspeita.sql` | **Guarda de segurança contra extração suspeita (E2)** — achado testando com um documento real (sessão 7, `HANDOFF.md`): um balanço multi-entidade fez a IA fabricar ~20 contas com o MESMO valor repetido, confiança declarada ALTA (0.99). `fn_registrar_campos_extraidos` (mesma assinatura) passa a checar, depois de gravar o lote da própria chamada (não relê extrações anteriores): (1) `extracao_padrao_suspeito` (tipo novo no enum `pendencia_tipo`) — 4+ contas distintas com o EXATO mesmo valor não-zero; (2) `extracao_baixa_confianca` (enum já existia desde 0001, nunca tinha sido usado) — parcela relevante das linhas (≥3 e ≥30%) com confiança < 0.7. Gera `pendencia` tipada, idempotente (reaproveita pendência aberta pela mesma versão), auto-resolve numa reextração que não repete o padrão. **Não resolve a causa raiz** (documentos multi-entidade/combinados quebram a extração) — só torna o problema visível antes do aceite humano. |
| `migrations/0014_entidade_coluna_multi_entidade.sql` | **Suporte a documentos multi-entidade (E2)** — ataca a causa raiz da fabricação vista na `0013`: coluna nova `campo_extraido.entidade_coluna` (nome da coluna/entidade da linha, quando o documento traz várias empresas lado a lado, ex. balanço combinado "Tecn \| Part \| Com \| Total"; null no caso comum de 1 entidade só). `fn_registrar_campos_extraidos` (mesma assinatura) passa a gravá-la. `n8n/lib/extract.mjs` (schema+prompt) passa a pedir uma linha por (conta × coluna) em vez de resumir/adivinhar um valor único. O export (`portal/src/lib/export.ts`) usa `entidade_coluna` para separar cada empresa em sua própria coluna. |
| `migrations/0015_reconciliacao_classe_b.sql` | **E3 — Reconciliação, Classe B** (segunda fatia, `docs/04_RECONCILIACAO.md`). Semi-objetiva (agregação/período) — travada em **N1** (nunca sobe pra N2 como a Classe A pode): banda de materialidade mais folgada (piso R$ 50k **e** 5%), qualquer divergência na zona cinzenta vira revisão humana, nunca auto-clear. Duas checagens canônicas: `fn_reconciliar_receita_dre_vs_faturamento` (Receita Bruta da DRE vs. soma das linhas mensais de `FATURAMENTO_24M` do mesmo ano — recorte por ano no rótulo, exclui linhas de total/média) e `fn_reconciliar_despfin_dre_vs_divida` (Despesa Financeira da DRE vs. soma das linhas de juros/encargos do `MAPA_DIVIDA`). Novo helper `fn_somar_conceito`/`fn_somar_faturamento_ano` (agregação, não casamento de uma linha só como `fn_valor_conceito` da 0009) e `fn_registrar_reconciliacao_b` (log + pendência idempotente, mesmo padrão da 0009). `fn_reconciliar_por_documento` redefinida para disparar A+B pelo tipo do documento. Pré-condição não satisfeita (documento ausente, rótulo não casou, período não identificado) é o comportamento ESPERADO enquanto `FATURAMENTO_24M`/`MAPA_DIVIDA` só tiverem schema genérico de linhas — vira pendência, nunca "OK" falso. |
| `migrations/0016_guarda_extracao_falhou.sql` | **Guarda de segurança contra extração que falhou/veio vazia (E2)** — achado em produção (sessão 7 cont.⁷, `HANDOFF.md`): 16 documentos ("teste v14") foram classificados com sucesso mas tiveram 0 linhas extraídas; n8n mostrava sucesso em todo node, reprocessar não mudava nada. Causa: a chamada de extração (schema com array `linhas` sem limite de tamanho) não tinha `max_tokens` explícito nem checagem de `finish_reason` — uma resposta truncada virava JSON inválido, e `parseExtractionResponse` devolvia `campos: []` silenciosamente; `fn_registrar_campos_extraidos` tratava array vazio como "0 campos, sucesso" e retornava sem checar nada. `fn_registrar_campos_extraidos` (mesma assinatura de 0005/.../0013 + `p_falha_motivo text default null`) agora roda a checagem de documento/caso mesmo com 0 campos e gera `pendencia` tipada `extracao_falhou` (severidade importante, idempotente, auto-resolve numa reextração que vier ok) sempre que o n8n mandar um motivo de falha. O fix de `max_tokens` (16384) e a detecção de truncamento/erro de API ficam em `n8n/lib/extract.mjs` + mirror em `n8n/build-workflow.mjs` — **precisa reimportar o workflow no N8N** para ter efeito. |
| `migrations/0017_periodo_coluna.sql` | **Suporte a documentos COMPARATIVOS (colunas de período, E2/E4)** — lacuna achada testando o export (sessão 7 cont.⁹): uma demonstração comparativa (ex. "Balanço consolidado 2023 x 2024.pdf", 2023 e 2024 lado a lado da MESMA entidade) colapsava os dois anos numa coluna só no export — perda de dado, e inútil pra modelagem (análise horizontal/vertical exige os anos lado a lado). Coluna nova `campo_extraido.periodo_coluna` (rótulo da coluna de período da linha; null no caso comum de período único). É ORTOGONAL a `entidade_coluna` (0014): um documento pode ter várias empresas E vários anos → linha por (conta × empresa × período). `n8n/lib/extract.mjs` (schema+prompt) pede uma linha por (conta × período); o export (`portal/src/lib/export.ts`) usa `periodo_coluna` na chave de coluna. **Limpeza de schema junto:** a `0016` deixou DUAS sobrecargas de `fn_registrar_campos_extraidos` (3 e 4 params) porque `create or replace` com nº de params diferente cria overload novo — chamada posicional de 2 args ficava ambígua ("is not unique"); a `0017` derruba a de 3 params e recria só a de 4 (grava `periodo_coluna` também). **Precisa reimportar o workflow no N8N.** |
| `migrations/0018_fix_revisar_documento_pendencias.sql` | **Fix: `fn_revisar_documento` só resolvia UM dos 4 tipos de pendência da fila de revisão** — achado em produção (sessão 7 cont.¹⁴, "teste v20"): o dono confirmava/salvava na fila, o documento era corretamente atualizado (fonte='humano', confiança=100%), mas o CARD continuava aparecendo. Causa: a função (0008) só fechava `classificacao_pendente`; as outras três (`tipo_incorreto`/`entidade_incorreta`/`periodo_incorreto`, introduzidas pela 0010) nunca eram resolvidas pela mesma ação. `fn_revisar_documento` (mesma assinatura) agora resolve os quatro tipos. |
| `migrations/0019_auto_aceite_alta_confianca.sql` | **Auto-aceite de linhas com confiança >=95%** — pedido explícito do dono (decisão de produto, registrada com a ressalva honesta de que sobe a autonomia da extração além do que a doutrina padrão exigiria sem golden set). `fn_registrar_campos_extraidos` (mesma assinatura de 0017) grava `status_aceite='aceito'`/`aceito_por`/`aceito_em` já na inserção quando `confianca >= 0.95`, registrando UM `decisao`+`evento_auditoria` por chamada (resumo, não um por linha). Inclui backfill: linhas já gravadas antes desta migration, com confiança >=95% e ainda pendentes, são promovidas agora (um `decisao` por caso afetado). |
| `migrations/0020_periodo_canonico.sql` | **Comparação de período por FORMA CANÔNICA (elimina `periodo_incorreto` falso)** — achado no "teste v22": a fila de revisão marcava "período pode estar incorreto" quando o diagnóstico sugeria o MESMO período do registrado em NOTAÇÃO diferente (`2025-01-15` × `15/01/2025`; `anual 2025` × `anual 12M25`). `fn_registrar_diagnostico` (0010) comparava a string crua. Novas funções `fn_ano4` + `fn_periodo_canonico(tipo, referencia)` (mesma semântica de `formatarPeriodo` do portal) colapsam notações equivalentes; `fn_registrar_diagnostico` (mesma assinatura) só gera pendência quando os períodos são canonicamente DISTINTOS. Pendências falsas já abertas auto-resolvem na próxima passada. Sem mudança no N8N. |

| `migrations/0021_classe_b_checagem_unidade.sql` | **Classe B: pré-condição de UNIDADE/ESCALA entre os dois documentos** — achado na auditoria de endurecimento: as duas checagens B (0015) comparam valores de DOIS documentos diferentes (Receita da DRE × soma do FATURAMENTO_24M; Despesa Financeira × juros do MAPA_DIVIDA) **sem** conferir a escala — ao contrário da Classe A (0009). Se a DRE está em milhares e o mapa em unidades, a comparação é entre grandezas 1000x distintas (divergência sem sentido, ou pior, falso "ok"). Novas `fn_unidade_predominante(documento_versao_id)` (moda da escala entre as linhas que a declaram — linhas não-monetárias têm `unidade` null por construção e não distorcem) e `fn_motivo_escala_incomparavel(...)`; as duas checagens B (mesmas assinaturas de 0015) passam a devolver `precondicao_nao_satisfeita` com motivo explícito quando as escalas divergem. Escala ausente num dos lados não bloqueia (mesmo critério conservador da 0009). Sem mudança no N8N. |

| `migrations/0022_periodo_por_ano_e_guardas.sql` | **Período por CONJUNTO DE ANOS + reconciliação tolerante a granularidade + guarda sem falso positivo** — três achados do "teste v24" (book Vertentes, 14 documentos). (1) A comparação canônica da 0020 ainda acusava divergência entre o MESMO período em granularidades diferentes (`anual 2025` × `data-base 2025-12-31`; `L24M` × `janeiro/2024 a dezembro/2025`): novas `fn_anos_periodo` e `fn_periodos_equivalentes` comparam o conjunto de anos, e só divergem quando os dois lados declaram anos e eles diferem. (2) As 4 checagens A/B casavam documentos por `periodo_id` EXATO — como cada arquivo declara a granularidade que quer, deu 11 pré-condições "documento ausente" com todos os documentos presentes; agora cada lookup aceita períodos COMPATÍVEIS (`fn_periodos_compativeis`, anos que se intersectam). (3) A guarda de padrão suspeito contava valores repetidos no lote inteiro — num combinado (5 empresas × 2 anos) o mesmo valor reaparece por coluna e valores pequenos coincidem à toa (5 alertas falsos): agora conta repetições DENTRO da mesma coluna e só considera valores materiais. Assinaturas inalteradas. |
| `migrations/0023_reconciliacao_sem_ruido.sql` | **Reconciliação sem ruído — 36 pendências → 0** (achado do "teste v25": o portal listava 36 pendências de reconciliação com o book extraído corretamente; reproduzido em `db/test/`). Cinco causas: (1) **ausência de documento virava pendência** (20 das 36) — documento que falta é cobrança do CHECKLIST do Kit Básico (`fn_recomputar_completude`), não da fila de revisão: a tentativa segue registrada em `reconciliacao` para auditoria, mas não abre pendência que o humano não tem como acionar; (2) **o COMBINADO não era aceito como balanço** — as checagens só olhavam `tipo_taxonomia='BALANCO'`, agora aceitam BALANCO→COMBINADO→BALANCETE (`fn_documento_balanco`); (3) **coluna era ignorada** — `fn_valor_conceito` pegava `limit 1` na versão inteira, comparando o Ativo de um ano contra o Passivo de outro num comparativo; novo `fn_valor_conceito_col` + `fn_coluna_entidade`/`fn_coluna_periodo_do_ano`, e a checagem roda **uma vez por ano declarado**; (4) **total de seção sem linha de total** — "RECEITA OPERACIONAL BRUTA" é cabeçalho sem valor em demonstração BR; novo `fn_soma_secao` soma as contas-folha excluindo o total da seção, as seções irmãs e as âncoras de cascata; (5) **escala divergente recusava a comparação** — com as duas escalas declaradas e conhecidas, converter é determinístico: `fn_fator_escala`/`fn_valor_em_base` convertem e só recusam escala ausente ou fora do vocabulário. Novo registro unificado `fn_registrar_reconciliacao` (Classe A e B). Assinaturas preservadas — o N8N chama `fn_reconciliar_por_documento` e não muda. Testes: `db/test/run.sh`. |
| `migrations/0024_taxonomia_dmpl_dva.sql` | **DMPL e DVA na taxonomia** (achado do "teste v25": a DMPL do book Vertentes saía classificada como `MUTUOS`). Não era erro da IA: `tipo_sugerido` é um enum FECHADO nos códigos que existem na taxonomia (`n8n/lib/openai.mjs` → `codigosConhecidos`), e não havia código nenhum para DMPL — o modelo escolheu o vizinho mais próximo. Entram como **complementar** (Nível 2): mexer no Kit Básico mudaria a completude de todo caso já aberto, e isso é decisão de produto, não efeito colateral de migration de vocabulário. Acompanham a migration, fora do banco: aliases de nome (`n8n/lib/taxonomia.mjs` + espelho no gerador), os valores `dmpl`/`dva` em `SECAO_CANONICA_ENUM` (roteamento por LINHA, para a DMPL embutida num PDF composto não ser somada como conta do PL) e abas próprias no export. **Só afeta classificações NOVAS** — documento já registrado como MUTUOS continua MUTUOS até ser reextraído ou corrigido na fila de revisão. |
| `migrations/0025_indices_macro.sql` | **Índices macroeconômicos — histórico + expectativa.** Alimenta as premissas da aba de Modelagem (inflação que corrige receita e contratos, juro que precifica a dívida), que até aqui eram digitadas de memória. Duas tabelas porque são dois FATOS diferentes: `indice_macro_obs` (o que ACONTECEU — série mensal publicada) e `indice_macro_expectativa` (o que o mercado ESPERA — Focus/BCB, por ano). Misturá-los seria tratar previsão como histórico. A observação é chaveada por (serie, data_ref, **FONTE**): guardar BCB e IBGE lado a lado é o que permite `fn_divergencias_indice_macro` conferir — sobrescrever uma com a outra destruiria a evidência que autoriza chamar o dado de validado. `fn_indice_macro_anual` acumula o ano por **composição** (12 meses de 1% dão 12,68%, não 12%) para série de TAXA e por variação entre fechamentos para série de NÍVEL (câmbio), e devolve o nº de meses para que ano incompleto não entre numa média de 3/5/10 anos como se fosse cheio. Coleta pelo workflow `n8n/workflow.macro.json` (mensal, dia 12 — depois da divulgação do IPCA). Testes: `db/test/macro.test.sql`. |
| `migrations/0026_reextracao_por_hash.sql` | **Reextração é versão nova do mesmo documento (idempotência por hash) + limpeza do overload morto.** O comentário da `0004` dizia "idempotente-ish por hash", mas nenhum corpo (0004→0008) chegou a CONSULTAR o hash: todo reenvio do mesmo arquivo inseria `documento` + `documento_versao` + `checklist_item_status` novos. Duas consequências reais — o mesmo arquivo virava dois documentos (duas linhas na fila, dois itens de checklist, colunas duplicadas da mesma empresa no export) e **reextrair ficava impossível sem sujar o caso**, sendo que reextrair é a ÚNICA forma de um documento já processado pegar prompt/taxonomia novos (a DMPL registrada como `MUTUOS` antes da `0024`, por exemplo). Agora mesmo `(caso_id, hash)` → nova `documento_versao` sob o MESMO documento (`n_versao+1`), sem duplicar checklist nem pendência; hash NULO nunca casa (dois desconhecidos não são o mesmo arquivo, e fundir documentos distintos é o erro mais caro aqui); e a classificação da máquina **não sobrepõe revisão humana** (`documento.fonte='humano'`). O retorno ganha `n_versao`/`reaproveitou_documento` (aditivo — o N8N atual não muda). Do lado do export, `versoesVigentes` usa a versão mais recente **com dado** (reextração que falha e volta vazia, `0016`, não pode apagar do book o que a anterior extraiu). **Não deixa de PAGAR** a extração repetida: isso exige fingerprint de prompt+modelo e curto-circuito no grafo do N8N — fatia própria, com o N8N vivo. Testes: `db/test/reextracao.test.sql`. |
| `migrations/0027_ordem_da_linha.sql` | **ORDEM da linha no documento** — achado do teste v28: o Ativo Circulante da VT Logística saiu **7.254** onde o documento diz **3.961**, porque "Contas a Receber" (3.293) foi somada JUNTO com os seus componentes "Fretes a receber" (3.562) e "(-) PECLD" (−269). As duas detecções de subtotal que o export já tinha não pegam esse caso: uma exige que alguma linha declare `secao` com o nome do subtotal (a extração daquele arquivo anotou a seção de TOPO em todas), a outra exige que o valor bata com a soma dos irmãos da MESMA seção (ali os irmãos são o circulante inteiro) — e como o documento não trouxe linha de total, não havia nem conferência: o número errado não tinha como ser percebido. O sinal que sobra é o que toda demonstração publicada dá: **o subtotal vem impresso imediatamente ANTES dos seus componentes**. Coluna `campo_extraido.ordem` + índice `(documento_versao_id, ordem)`; assinatura de `fn_registrar_campos_extraidos` INALTERADA (o N8N chama do mesmo jeito), só o JSON de entrada passa a aceitar `ordem` por linha — que o `n8n/lib/extract.mjs` preenche com a POSIÇÃO NO ARRAY, não pedindo o campo ao modelo. Extração antiga fica `null` e nada muda para ela: **só reprocessamento traz o ganho**. Invariante 17 de `verificar-export.mts`, com caso negativo. |
| `migrations/0028_rls_e_grant_indices_macro.sql` | **RLS e GRANT dos índices macro, esquecidos na 0025.** O dono aplicou 0025 + o seed + reimportou os workflows, e o export continuava com a aba Macro vazia. Comparando com toda migration anterior que cria tabela/função chamada pelo portal, faltavam os dois passos que o resto do banco sempre faz: (1) `indice_macro_serie`/`indice_macro_obs`/`indice_macro_expectativa` sem `enable row level security` nem policy — RLS habilitado sem policy devolve **zero linhas sem erro nenhum**, indistinguível de "sem dado coletado"; (2) `fn_indice_macro_anual` (chamada pelo portal via `supabase.rpc()`, que resolve para o papel `authenticated`) sem `grant execute`, ao contrário de `fn_revisar_documento` (0008) e `fn_aceitar_extracao` (0011), as outras duas funções que o portal chama diretamente. Função chamada só pelo N8N não precisa disso porque o N8N conecta via Postgres NATIVO (Session Pooler), nunca pelo PostgREST. Verificação embutida na própria migration: insere linha real, troca para o papel `authenticated` (`set local role`) e confere por `COUNT(*)` — RLS sem policy não estoura exceção, só esconde a linha, e testar contra tabela vazia não prova nada. `db/test/run.sh` passou a replicar o GRANT de tabela que o Supabase provê por padrão a todo projeto nascente (sem isso, `set role authenticated` falharia para QUALQUER tabela local, não só a com o bug — é por isso que nenhum teste daqui tinha pego essa classe de defeito). Do lado do portal, `export/route.ts` parou de engolir `.error` das consultas macro (`?? []` sem olhar erro) — a aba Macro agora distingue "a consulta FALHOU" (pode haver dado) de "sem dado coletado" (a base está genuinamente vazia). |
| `migrations/0029_extracao_aceite_depois_das_guardas.sql` | **Quatro defeitos que faziam a extração parecer bem-sucedida quando não foi.** (1) **Auto-aceite atropelava as guardas** — o mais grave, porque furava a anti-ancoragem (`docs/01`, `f0/06`): a `0027` gravava `status_aceite='aceito'` DENTRO do loop para toda linha com confiança ≥95%, e só depois rodava as três guardas (padrão suspeito / baixa confiança / extração falhou); nenhuma guarda revertia o aceite. Uma extração alucinada — cujo padrão típico é justamente vir com confiança ALTA e o mesmo valor repetido em muitas contas — entrava como **fato aceito**, com o Sinal 1 abrindo uma pendência ao lado sem desfazer nada. Uma guarda que dispara depois do aceite não é guarda, é legenda. Agora toda linha entra `pendente` e a promoção acontece no fim, só se nenhuma guarda disparou; guarda que barra promoção vira `evento_auditoria`, para não parecer que o auto-aceite não rodou. (2) **Extração vazia sem erro de API não gerava pendência nenhuma** — a `0016` fechou "a chamada falhou", não "a chamada respondeu JSON válido com `linhas: []`": aí `p_falha_motivo` é nulo e `v_count` é zero, e os três sinais eram pulados. O documento ficava com tipo, confiança alta, `em_validacao`, zero linhas e zero pendências, indistinguível de um documento que legitimamente não tem números — e o pipeline produz esse estado de propósito, porque `.xlsx` e mime não previsto mandam para a IA uma string de aviso em vez do arquivo. (3) **`extracao_falhou` nunca fechava**: a chave era `'extracao:falhou:' || documento_versao_id`, então reenviar (que cria versão nova) abria/fechava uma chave diferente e a pendência antiga ficava aberta para sempre — e `fn_revisar_documento` (0018) não resolve nenhuma das quatro de extração, ou seja, não havia ação humana capaz de fechá-las. As três chaves passam a ser por `documento_id`, com migração das já gravadas (sem ela, a própria correção deixaria as pendências existentes órfãs). (4) **Documento inexistente descartava o motivo da falha**: `if v_documento_id is null then return v_count;` com o comentário "nunca deveria acontecer (FK)" — mas FK não dispara com `null`, e o caminho era real e caro: falha em `Registrar Documento` → `documento_versao_id` nulo → extração **executada** (dinheiro gasto) → função retorna 0 jogando fora o `p_falha_motivo` antes do Sinal 3. Agora registra em `evento_auditoria` + `warning`; a prevenção do gasto fica no pipeline, onde `Montar Req Extracao` recusa montar requisição sem versão. Verificação embutida com 5 asserts, todos provados não-vazios (desligando cada fix, o `run.sh` reprova com a mensagem específica). |
| `migrations/0030_entidade_e_periodo_canonicos.sql` | **Canonicalizar entidade e período no caminho de ESCRITA.** Três defeitos com a mesma forma: o dado é gravado cru, a comparação depois é mais esperta, e o descasamento produz duplicata ou "não achei" — em silêncio. (1) **Entidade duplicada** — regressão introduzida pelo PR #65: `fn_registrar_documento` casava por `lower(razao_social)`, e desde que a entidade passou a sair também do NOME DO ARQUIVO existem duas fontes que escrevem diferente (`Vertentes Metalurgica` sem acento, porque `normalize.mjs` remove diacríticos, × `Vertentes Metalúrgica Ltda.` do diagnóstico). `lower()` não aproxima as duas ⇒ duas linhas `entidade` para a mesma empresa ⇒ o export conta cada uma como coluna e toda soma do grupo duplica. O export já mascarava o sintoma (`consolidarNomesDeEntidade`), e é por isso que a duplicidade na base passou sem ser vista. (2) **`fn_coluna_entidade` casava por igualdade exata** — causa da pendência "não foi possível localizar Ativo Total / Passivo+PL" do teste v31: no balanço COMBINADO os cabeçalhos são apelidos curtos (`Metalúrgica`) e `razao_social` é a razão completa, então nunca casava, a função devolvia o sentinela `E'\x01'`, `fn_valor_conceito_col` e `fn_soma_secao` não retornavam nada e `v_n_anos` era 0. Os rótulos estavam certos desde sempre. O portal já resolvia isso com casamento por token com prefixo; o banco não tinha equivalente. (3) **Período gravado cru** fragmentava o exercício: `2025` e `12M25` viravam duas linhas em `periodo` — a `0022` canonicalizava só na comparação, então a reconciliação achava o par mas dashboard, checklist e export viam dois períodos. Introduz `fn_entidade_canonica` (sem acento, pontuação nem sufixo societário — `SPE` NÃO é descartado, faz parte do nome), `fn_mesma_entidade` (igualdade canônica ou token do nome curto como prefixo do longo, exigindo pelo menos um token de 4+ chars porque fundir empresas é pior que não casar), `fn_upsert_entidade` e `fn_upsert_periodo`. `fn_registrar_documento` é redefinida com o corpo EXATO da `0026` trocando só as duas buscas — extrair os passos em funções próprias é o que os torna testáveis sozinhos e o que evita repetir o erro da `0006`, que recriou um corpo antigo inteiro e regrediu funções. Testes em `db/test/canonico.test.sql` (13 asserts, todos provados não-vazios). **Limitação conhecida e fixada por teste:** o viés é para CONSOLIDAR — nome curto é absorvido pelo longo que o contenha por prefixo, e numeral romano não desempata (`SPE I` casa `SPE II`). É o mesmo comportamento do portal, que está em produção, e é o preço de fazer `Metalúrgica` casar `VERTENTES METALÚRGICA LTDA.`. Se aparecer caso real de fusão indevida, o desempate é CNPJ — a coluna já existe em `entidade` e ninguém preenche. |
| `migrations/0031_caixa_por_secao.sql` | **Reconciliação do caixa: usar a SEÇÃO, que o documento já declarava.** Segunda das duas pendências de PRÉ-CONDIÇÃO do teste v31 ("não foi possível localizar o Caixa/Disponível do Balanço"). A causa não era rótulo ruim nem extração falha: `fn_valor_conceito_col` exige que TODOS os termos apareçam como substring de `ce.chave` e **nunca olha `ce.secao`**. Contra os rótulos reais do book, duas das cinco empresas não casavam nenhuma das quatro tentativas — `VT Logística` tem chave `Bancos Conta Movimento` (e seção `Disponível`, onde o dado estava todo esse tempo) e a SPE tem chave `Caixa` puro, que as tentativas rejeitavam porque exigiam `equivalentes` ou `bancos` junto. Sem os dois lados, `continue` ⇒ `v_n = 0` ⇒ pendência: a reconciliação reclamava de dado que ela mesma não tinha procurado onde estava. Introduz `fn_valor_conceito_secao` (gêmea da original, casando contra `ce.secao`; função separada em vez de parâmetro novo, porque a original é chamada de muitos lugares e mudar a assinatura obrigaria a revisar todos) e três tentativas novas na cascata do caixa, **depois** das buscas por rótulo — rótulo é mais específico que seção, e documento que declara as duas coisas deve escolher a linha, não o grupo. O `EXCLUI` olha chave E seção, para seção que casou não salvar rótulo proibido. Nenhuma outra checagem muda. |
| `migrations/0032_cambio_perdia_janeiro.sql` | **A variação anual do câmbio perdia janeiro, todo ano.** `fn_indice_macro_anual` (0025) calculava série de NÍVEL comparando dezembro com dezembro do ano anterior por uma janela que descartava o primeiro mês. Corrige a janela e o teste trava o comportamento — a fixture anterior CONSAGRAVA o erro. |
| `migrations/0033_precondicao_que_nomeia_o_rotulo.sql` | **A pré-condição de Ativo × Passivo+PL dizia que falhou, nunca por quê.** No v33, cinco reconciliações A.1 saíram como "pré-condição não satisfeita" sem dizer qual lado faltou. A mensagem passa a listar os rótulos que a extração trouxe, o que transformou o diagnóstico seguinte (0034) em leitura, não em adivinhação. |
| `migrations/0034_total_do_grupo_sem_a_palavra_total.sql` | **O total do grupo raramente se chama "total", e a A.1 exigia a palavra.** Causa raiz achada no v35 pela mensagem que a 0033 passou a escrever. Introduz `fn_rotulo_estrutural` — a mesma função que a 0042 reaproveita para o papel da linha. |
| `migrations/0035_moeda_por_linha.sql` | **A moeda que a extração sempre soube e nunca gravou** (§7.4 #2 do Onboarding). Coluna `campo_extraido.moeda`; sem ela, linha em USD e linha em BRL somavam na mesma coluna sem uma marca. |
| `migrations/0036_completude_exige_conteudo.sql` | **Documento que chegou vazio para de contar como item cumprido** (§7.4 #3 e #4). Checklist exigia o arquivo, não o conteúdo: PDF ilegível fechava o item. Recusa RETORNADA (não exceção), porque exceção em plpgsql desfaria o registro da própria tentativa. |
| `migrations/0037_portao2.sql` | **O Portão 2 do caso existe** — era só um valor de enum. `caso_status` tinha `aprovado`/`pronto_para_base` desde a 0001 e nenhuma função transicionava para eles; `pendencia.sobrepujavel` era gravado e nunca lido. `fn_avaliar_portao2` (só lê) + `fn_aprovar_caso`, com teto de ressalvas em 3 e ressalva expirada avaliada NA LEITURA. |
| `migrations/0038_premissas_catalogo.sql` | **Catálogo de premissas, e a escolha de modelagem por caso.** As 15 premissas do modelo eram constantes de código; viram dado (`premissa_catalogo`, `caso_premissa`, `caso_linha_premissa`, `caso_modelagem`), com sugestão por setor e sete primitivas de fórmula. |
| `migrations/0039_linhas_para_modelagem.sql` | **As linhas do caso, para a tela de Modelagem.** `fn_linhas_para_modelagem` — função e não consulta no portal porque `campo_extraido` não tem `caso_id`: o escopo por caso mora aqui, uma vez só. |
| `migrations/0040_sazonalidade_do_caso.sql` | **Sazonalidade DERIVADA do histórico do próprio caso** (decisão do dono, 7.5). A curva mensal não é digitada: sai do faturamento do mandato. Sem 12 meses, não há curva — e o arquivo diz isso, em vez de ratear 1/12. |
| `migrations/0041_dial_manda.sql` | **O dial de autonomia volta a ser estado do sistema.** `estagio_autonomia` nascia na 0001 e não tinha um único leitor, enquanto o auto-aceite usava `0.95` hardcoded. `limiar_auto_clear` vira dado, `fn_dial`/`fn_mudar_dial` respeitam o teto e gravam `mudanca_dial`, e baixar a autonomia passa a ser UMA chamada em vez de um deploy. |
| `migrations/0042_papel_da_linha.sql` | **A linha diz o que ela é antes de ser projetada.** `fn_papel_linha` (conta/subtotal/derivado/serie_mensal, lista fechada); `fn_linhas_para_modelagem` reemitida com papel, valor COM SINAL, unidade/moeda, documentos e `sobreposicao_suspeita`; vínculo em linha que não é conta é recusado no banco. Corrige também `fn_mes_do_rotulo` (o `left(chave,3)` devolvia curva vazia com o rótulo real da extração). |
| `migrations/0043_reconferir_o_que_ja_esta_no_banco.sql` | **Reaplicar as regras de HOJE sobre o dado já gravado, sem gastar IA.** Pendência é estado gravado e nada a reavaliava quando a regra mudava — o portal mostrava, por tempo indeterminado, achado que a regra atual não faria mais. `fn_avaliar_guardas_extracao` vira fonte única dos três sinais; `fn_reconferir_caso` é o ponto de entrada. |
| `migrations/0044_valores_por_ano.sql` | **O valor de cada linha lógica por exercício.** `fn_valores_por_ano(caso, entidade)` — o filtro de entidade **não é opcional**: sem ele, "Ativo Circulante 2024" devolvia o de uma empresa do grupo e o passivo de outra. Ano vem de `periodo_coluna` primeiro (balanço comparativo traz dois anos no mesmo documento). |
| `migrations/0100_papel_por_secao.sql` | **O papel da linha é da SEÇÃO, não do rótulo solto no caso.** A tela agrupa por (seção, rótulo) e a guarda agrupava só por rótulo, resolvendo o empate pelo papel mais restritivo — então ela recusava a linha que a tela tinha acabado de oferecer, e o "aplicar em lote" caía inteiro na primeira recusa. A guarda passa a ler o papel da mesma seção que a tela mostrou; recusa por linha vai para `ignoradas` e o lote segue; recusa global (premissa não ativa) continua abortando. **Primeira migration na faixa `0100`+** (colaborador). |
| `migrations/0102_modelagem_versao_vigente.sql` | **A Modelagem lê a versão VIGENTE de cada documento.** A `0026` estabeleceu que reextrair cria `documento_versao` nova sem perder a anterior — e os cinco leitores por caso (`fn_linhas_para_modelagem`, `fn_papel_do_rotulo_no_caso`, `fn_sazonalidade_do_caso`, `fn_valores_por_ano`, `fn_linhas_do_tipo`) nunca mencionavam `n_versao`, então as ocorrências de TODAS as versões entravam no mesmo agrupamento. Medido: `Estoques` ia de 7 ocorrências/24.610 para 8/777.777 depois de UMA reextração — a versão superada somava e podia **ditar o valor que sai no Excel**. E cada rodada de reextração acrescentava um jogo inteiro de ocorrências, o que devolveria o caso ao `statement_timeout` que a `0101` acabou de destravar, sem ninguém mexer em código. A regra vive numa definição só, `fn_versao_com_extracao` — que difere de `fn_versao_atual` de propósito, porque `max(n_versao)` puro deixaria a tela em branco na janela entre registrar o documento e extrair. Traz também `fn_diagnostico_modelagem`, para responder "a correção está no banco?" sem adivinhar. |
| `migrations/0101_modelagem_dentro_do_tempo.sql` | **A tela de Modelagem cabe dentro do `statement_timeout`.** Medido num caso do tamanho do v35 (14 documentos, 770 ocorrências): `fn_conferir_modelagem` levava **9,3 s** — acima do teto de 8 s do Supabase —, era cancelada, e a tela mostrava isso como "este caso não tem linha extraída". Duas causas: `fn_conferir_modelagem` chamava `fn_linhas_para_modelagem` **cinco vezes**, duas delas dentro de `exists` correlacionado (uma execução completa **por vínculo**); e `fn_papel_linha`, que custa ~1,6 ms, era avaliada **por ocorrência** quando o papel é propriedade do RÓTULO. Agora a conferência é uma passada só, o papel é calculado uma vez por rótulo distinto e a marca de sobreposição virou join por igualdade. **9,3 s → 96 ms**, com resultado idêntico campo a campo. Traz também os `grant execute` dos auxiliares da 0042 que nasceram sem nenhum. |
| `seed/macro_carga_inicial.sql` | **Carga inicial dos índices macro** (dado REAL, gerado por `node n8n/gerar-seed-macro.mjs` das mesmas APIs e parsers que o workflow de coleta usa: BCB/SGS, IBGE/SIDRA e BCB/Focus). Existe porque o `workflow.macro.json` roda no RELÓGIO (dia 12) e **não faz carga histórica** — importar/ativar o workflow hoje não traz número nenhum até o próximo dia 12, e as médias de 3/5/10 anos e as premissas de Focus do modelo são inúteis vazias. Aplicar **depois da `0025`**, no mesmo banco. Seguro rodar mais de uma vez (as RPCs são idempotentes). É uma FOTO da data em que o arquivo foi gerado — a manutenção mês a mês continua sendo do workflow. Testes: `db/test/seed_macro.test.sql`, que confere as duas fontes do IPCA entre si. |

## Como aplicar

**Opção A — Supabase CLI (recomendado):**
```bash
supabase db push
# ou aplicar arquivo a arquivo:
supabase db execute --file db/migrations/0001_schema_fatia1.sql
supabase db execute --file db/migrations/0002_seed_taxonomia_e_dial.sql
supabase db execute --file db/migrations/0003_rls_e_storage.sql
supabase db execute --file db/migrations/0004_funcoes_e1.sql
supabase db execute --file db/migrations/0005_extracao_e2.sql
supabase db execute --file db/migrations/0006_reset_funcoes.sql
supabase db execute --file db/migrations/0007_justificativa_pendencia.sql
supabase db execute --file db/migrations/0008_portal_revisao.sql
supabase db execute --file db/migrations/0009_reconciliacao_e3.sql
supabase db execute --file db/migrations/0010_diagnostico_e1e2.sql
supabase db execute --file db/migrations/0011_aceite_export_e4.sql
supabase db execute --file db/migrations/0012_secao_canonica_e4.sql
supabase db execute --file db/migrations/0013_guarda_extracao_suspeita.sql
supabase db execute --file db/migrations/0014_entidade_coluna_multi_entidade.sql
supabase db execute --file db/migrations/0015_reconciliacao_classe_b.sql
supabase db execute --file db/migrations/0016_guarda_extracao_falhou.sql
supabase db execute --file db/migrations/0017_periodo_coluna.sql
supabase db execute --file db/migrations/0018_fix_revisar_documento_pendencias.sql
supabase db execute --file db/migrations/0019_auto_aceite_alta_confianca.sql
supabase db execute --file db/migrations/0020_periodo_canonico.sql
supabase db execute --file db/migrations/0021_classe_b_checagem_unidade.sql
supabase db execute --file db/migrations/0022_periodo_por_ano_e_guardas.sql
supabase db execute --file db/migrations/0023_reconciliacao_sem_ruido.sql
supabase db execute --file db/migrations/0024_taxonomia_dmpl_dva.sql
supabase db execute --file db/migrations/0025_indices_macro.sql
supabase db execute --file db/migrations/0026_reextracao_por_hash.sql
supabase db execute --file db/migrations/0027_ordem_da_linha.sql
supabase db execute --file db/migrations/0028_rls_e_grant_indices_macro.sql
supabase db execute --file db/migrations/0029_extracao_aceite_depois_das_guardas.sql
supabase db execute --file db/migrations/0030_entidade_e_periodo_canonicos.sql
supabase db execute --file db/migrations/0031_caixa_por_secao.sql
supabase db execute --file db/migrations/0032_cambio_perdia_janeiro.sql
supabase db execute --file db/migrations/0033_precondicao_que_nomeia_o_rotulo.sql
supabase db execute --file db/migrations/0034_total_do_grupo_sem_a_palavra_total.sql
supabase db execute --file db/migrations/0035_moeda_por_linha.sql
supabase db execute --file db/migrations/0036_completude_exige_conteudo.sql
supabase db execute --file db/migrations/0037_portao2.sql
supabase db execute --file db/migrations/0038_premissas_catalogo.sql
supabase db execute --file db/migrations/0039_linhas_para_modelagem.sql
supabase db execute --file db/migrations/0040_sazonalidade_do_caso.sql
supabase db execute --file db/migrations/0041_dial_manda.sql
supabase db execute --file db/migrations/0042_papel_da_linha.sql
supabase db execute --file db/migrations/0043_reconferir_o_que_ja_esta_no_banco.sql
supabase db execute --file db/migrations/0044_valores_por_ano.sql
# Faixa 0100+ (colaborador). O buraco 0044 → 0100 é o estado esperado, não erro:
supabase db execute --file db/migrations/0100_papel_por_secao.sql
supabase db execute --file db/migrations/0101_modelagem_dentro_do_tempo.sql
supabase db execute --file db/migrations/0102_modelagem_versao_vigente.sql

# Carga inicial dos índices macro (depois da 0025; não é migration, é dado):
supabase db execute --file db/seed/macro_carga_inicial.sql
```

> 🔎 **MERGE NÃO É APPLY — e da tela os dois são iguais.** O PR entrar no `main` não
> muda uma linha do Supabase; a migration só existe quando o comando acima roda. Foi
> exatamente aqui que a rodada da `0101` se perdeu: a migration estava na tabela deste
> arquivo e **não** na lista de comandos acima, o dono aplicou o que a lista mandava, e a
> tela de Modelagem seguiu mostrando o defeito antigo — parecendo que o PR não tinha
> funcionado. Para não precisar adivinhar, a `0102` traz um diagnóstico; rode no SQL
> Editor:
>
> ```sql
> select jsonb_pretty(fn_diagnostico_modelagem('<caso_id>'));
> ```
>
> `correcoes_instaladas` responde direto se as funções em pé no banco são as da
> `0101`/`0102`; `ocorrencias_superadas` diz quantas ocorrências vinham de versão
> superada de documento; `linhas` e `linhas_por_papel` dizem o que a tela **deve**
> mostrar, para comparar com o que ela está mostrando. `db/test/run.sh` agora reprova
> migration que exista e não esteja na lista acima, para o esquecimento não repetir.

> ⚠️ **DEPOIS DE APLICAR QUALQUER MIGRATION QUE CRIE OU DERRUBE FUNÇÃO, recarregue o
> cache de schema do PostgREST:**
>
> ```sql
> notify pgrst, 'reload schema';
> ```
>
> O PostgREST (a API que o portal usa) guarda um catálogo próprio das funções expostas.
> Função recém-criada **não existe para ele** até esse `notify` — e função derrubada
> continua existindo. Enquanto o cache está velho, a chamada volta erro de "função não
> encontrada", e a tela que não lê o `.error` mostra isso como **lista vazia**: foi
> exatamente assim que a Modelagem anunciou "este caso ainda não tem linha extraída"
> num caso com 203 linhas, logo depois da `0100`. A tela agora denuncia o erro em vez
> de engoli-lo, mas o `notify` continua sendo parte de aplicar a migration, não um
> extra.

> ⚠️ **Se o N8N reportar `function ... does not exist` mesmo com a função existindo no banco**
> (ex.: após aplicar migrations parcialmente/mais de uma vez), a `0006` derruba qualquer versão
> divergente das 4 funções RPC e recria do zero — mas ela recria os corpos **da época dela**, e
> desde então quase todas foram redefinidas. Rodar a `0006` sozinha **REGRIDE o schema**: some a
> idempotência por hash (`0026`), somem `confianca`/`fonte`/`justificativa` no documento (`0008`),
> somem as guardas de extração (`0013`/`0016`) e o auto-aceite (`0019`), e volta o overload morto de
> 14 args que a `0026` removeu. Se precisar do reset, **continue aplicando 0007 → 0031 em ordem**
> logo depois: cada migration posterior redefine o que é dela, e só a sequência completa devolve o
> estado atual. Não precisa reaplicar 0001-0005 antes (a `0006` assume as tabelas já criadas).
> (Achado da auditoria: `reset-0006-regride-funcoes`.)

**Opção B — psql direto** (usar o **Session Pooler**; herdar a pegadinha do `clipping-news`:
IPv4 + SSL, usuário do pooler com sufixo `.projectref`):
```bash
psql "$SUPABASE_DB_URL" -f db/migrations/0001_schema_fatia1.sql
psql "$SUPABASE_DB_URL" -f db/migrations/0002_seed_taxonomia_e_dial.sql
psql "$SUPABASE_DB_URL" -f db/migrations/0003_rls_e_storage.sql
```

## Notas de segurança (LGPD) — ler antes de conectar clientes

- **service_role ignora RLS** (é o que o N8N usa como orquestrador). O portal Vercel **nunca**
  deve usar a service_role — só chave `anon`/`authenticated`, que respeita RLS.
- Bucket `documentos` é **privado**; nunca gerar URL pública — usar signed URLs.
- **TODO de fatia posterior:** restringir RLS por caso (membership) e reforço para documentos
  `pii_sensivel` (`DOCS_SOCIOS`, `AVAIS_FIANCAS`, `HEADCOUNT`).

## Testes locais

```bash
PGHOST=/tmp PGPORT=5432 PGUSER=postgres db/test/run.sh
```

Recria um banco descartável, aplica as **23 migrations em ordem**, carrega o fixture do book
Vertentes (`db/test/fixture_book_vertentes.sql` — extração FIEL dos 14 documentos) e roda
`db/test/reconciliacao.test.sql`. A invariante central: **extração fiel não abre nenhuma pendência
de reconciliação**; cada checagem tem também um caso negativo provando que continua pegando o erro
real (balanço que não fecha, escala desconhecida, caixa que não bate, faturamento que não amarra,
rótulo irreconhecível). O fixture é gerado por `db/test/gerar_fixture.py` a partir do próprio
gerador do book — para regerá-lo:

```bash
cd test-data/book-vertentes
PYTHONPATH=. python3 ../../db/test/gerar_fixture.py > ../../db/test/fixture_book_vertentes.sql
```

## Verificação rápida (após aplicar)

```sql
-- Taxonomia populada? (esperado: 8 obrigatórios do Kit Básico)
select obrigatoriedade, count(*) from taxonomia_tipo_documento group by obrigatoriedade;

-- Dial de autonomia inicial? (esperado: 8 estágios)
select estagio, nivel_atual, teto from estagio_autonomia order by estagio;

-- RLS ligado em todas as tabelas de dados?
select relname, relrowsecurity from pg_class
where relname in ('caso','documento','pendencia','evento_auditoria') order by relname;
```

## O que NÃO está aqui (entra em fatias seguintes)

O refinamento de RLS por caso, e as Classes B/C de reconciliação (`docs/04_RECONCILIACAO.md`
— continuam N1/aproximação, não têm engine determinística ainda). O Portão 2 formal
(`docs/07_STATUS_E_PENDENCIAS.md`: bloqueantes não-sobrepujáveis, teto/expiração de ressalva)
também não está aqui — `fn_aceitar_extracao` (0011) é só o aceite mínimo por linha extraída,
não a regra de portão do caso inteiro. Ver o plano da F1 e `f0/05_schema_conceitual.md`.
(`campo_extraido` entrou em `0005`; `reconciliacao` — Classe A — entrou em `0009`; aceite/E4
entrou em `0011`.)
