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
```

> **Se o N8N reportar `function ... does not exist` mesmo com a função existindo no banco**
> (ex.: após aplicar migrations parcialmente/mais de uma vez), rode direto a `0006` — ela
> derruba qualquer versão divergente das 4 funções e recria do zero. Não precisa reaplicar
> 0001-0005 antes; 0006 assume que as tabelas (criadas em 0001/0005) já existem.

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
