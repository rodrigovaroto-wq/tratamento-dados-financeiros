# Camada de banco (Supabase / Postgres) — Fatia 1

Materializa o schema conceitual (`f0/05_schema_conceitual.md`) no Postgres do Supabase, no
subconjunto necessário para a **Fatia 1 (E1 — Intake determinístico)** da F1.

> **Fonte da verdade do estado = Postgres** (ver `docs/02`, trava de stack nº 1). O N8N é
> stateless; o portal Vercel lê/escreve via camada que respeita RLS.

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
```

> ⚠️ **Se o N8N reportar `function ... does not exist` mesmo com a função existindo no banco**
> (ex.: após aplicar migrations parcialmente/mais de uma vez), a `0006` derruba qualquer versão
> divergente das 4 funções RPC e recria do zero — mas ela recria os corpos **da época dela**, e
> desde então quase todas foram redefinidas. Rodar a `0006` sozinha **REGRIDE o schema**: some a
> idempotência por hash (`0026`), somem `confianca`/`fonte`/`justificativa` no documento (`0008`),
> somem as guardas de extração (`0013`/`0016`) e o auto-aceite (`0019`), e volta o overload morto de
> 14 args que a `0026` removeu. Se precisar do reset, **continue aplicando 0007 → 0026 em ordem**
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
