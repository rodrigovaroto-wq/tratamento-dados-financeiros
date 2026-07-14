# 0.5 — Schema Conceitual + Política LGPD  ·  [APROVADO]

**Objetivo:** modelo conceitual de dados (entidades, relações, atributos-chave) que
materializa taxonomia (0.3) e status/pendências (0.4). **Sem DDL** — é o desenho lógico que
guia o schema físico na F1. Fonte da verdade do estado = Postgres/Supabase.

> **Aprovado em 2026-07-14 (Rodrigo Varoto)** com um ajuste de storage (ver `documento_versao`
> abaixo) decorrente da decisão híbrida 0.2 (arquivos no SharePoint / upload manual na F1).

## Entidades e relações

```
caso 1─* entidade 1─* (documento por período)
caso 1─* periodo
caso 1─* checklist_item_status  (derivado da taxonomia × entidade × período)
documento 1─* documento_versao 1─* campo_extraido
caso 1─* reconciliacao
caso 1─* pendencia
caso 1─* decisao
* ─────  evento_auditoria (append-only, referencia qualquer entidade)
estagio_autonomia (config por caso ou global)
taxonomia_tipo_documento / taxonomia_contabil (versionadas, fonte da verdade)
```

## Dicionário conceitual (atributos-chave)

| Entidade | Atributos-chave | Notas |
|---|---|---|
| `caso` | id, nome, produto (`reestruturacao`), status, criado_em | Unidade de trabalho (mandato) |
| `entidade` | id, caso_id, razao_social, cnpj, papel_no_grupo | Empresas do grupo |
| `periodo` | id, caso_id, tipo (mês/ano/data-base), referencia | Eixo temporal |
| `documento` | id, caso_id, entidade_id, periodo_id, tipo_taxonomia_id, status, sensibilidade_lgpd | Ancorado à taxonomia |
| `documento_versao` | id, documento_id, n_versao, `origem_arquivo` (`supabase_storage` \| `sharepoint`), `arquivo_ref` (path no bucket **ou** ID do item no SharePoint), assinado (bool), hash, legibilidade, criada_em | Versionamento + integridade. **Storage em dois modos** (ver nota abaixo) |
| `checklist_item_status` | id, caso_id, entidade_id, periodo_id, tipo_taxonomia_id, status, obrigatoriedade | Base da completude |
| `campo_extraido` | id, documento_versao_id, chave, valor, confianca, origem (página/linha), nivel_autonomia, revisado_por | Extração com confiança + trilha |
| `reconciliacao` | id, caso_id, tipo, classe (A/B/C), fonte_a, fonte_b, precondicoes_ok, resultado, divergencia, materialidade | Ver `docs/04_RECONCILIACAO.md` |
| `pendencia` | id, caso_id, tipo, severidade, estado, alvo, motivo, sobrepujavel, expira_em, resolvida_por | Ver 0.4 |
| `decisao` | id, caso_id, tipo (aprovacao/override/ressalva/mudanca_dial), autor, timestamp, motivo, payload | Decisões humanas |
| `evento_auditoria` | id, timestamp, ator, acao, entidade_ref, antes, depois | **Append-only, imutável** |
| `estagio_autonomia` | estagio, nivel_atual (N0–N3), teto, atualizado_por, atualizado_em | O "dial" |
| `taxonomia_tipo_documento` | codigo, categoria, obrigatoriedade, granularidade, vigencia, sensibilidade, versao | Fonte da verdade da taxonomia |
| `taxonomia_contabil` | codigo, rótulo, versao | Enum fechado (`docs/05_...`) |

## Princípios de modelagem

1. **Estado no Postgres, nunca no N8N.** Toda entidade acima é persistida; N8N só lê/escreve.
   - **Storage em dois modos (decisão 0.2):** `documento_versao` guarda **de onde** o arquivo
     vem (`origem_arquivo`) e **o ponteiro** (`arquivo_ref`). Na **F1** (upload manual em lote),
     `origem_arquivo = supabase_storage` e o arquivo mora no bucket privado do Supabase Storage.
     Na **fase de integração futura**, `origem_arquivo = sharepoint` e `arquivo_ref` é o ID do
     item na biblioteca do SharePoint (arquivo permanece no VDR). O restante do modelo não muda.
   - `assinado` reflete o atributo `(Assinado)` da taxonomia (0.3) — flag de validação formal,
     não tipo de documento.
2. **Append-only para auditoria.** `evento_auditoria` e `decisao` não são atualizados nem
   apagados — só inseridos. Correções são novos eventos.
3. **Confiança e nível de autonomia são colunas**, não constantes de código — permitem o dial.
4. **Taxonomia versionada:** `campo_extraido`/`checklist_item_status` referenciam a versão da
   taxonomia usada, para rastreabilidade quando a taxonomia evoluir.
5. **Nada na base de modelagem (E4) sem `decisao` de aceite** ligada (anti-ancoragem).

## Política LGPD (desenhar agora, não depois)

| Item | Regra |
|---|---|
| Classificação de sensibilidade | Cada `documento` herda `sensibilidade_lgpd` do tipo (0.3); `PII sensível` para `DOCS_SOCIOS`, `AVAIS_FIANCAS`, `HEADCOUNT` |
| Controle de acesso | RLS por caso + restrição extra para documentos `PII sensível` (só papéis autorizados) |
| Minimização | Não extrair campos pessoais de `DOCS_SOCIOS` além do necessário para a garantia |
| Retenção | Política de expurgo por caso encerrado (definir prazo com jurídico) |
| Trilha de acesso | Todo acesso a documento `PII sensível` gera `evento_auditoria` |
| Storage | Arquivos no Supabase Storage com bucket privado; nunca URL pública |

> **Atenção à pegadinha do `clipping-news`:** RLS ligado sem policy tranca chaves públicas,
> mas a conexão direta do N8N ignora RLS — garantir que o portal (Vercel) acesse via camada
> que respeita RLS, não via credencial de serviço irrestrita.

**Critério de pronto (DoD):** modelo conceitual revisado pelo arquiteto; sensibilidade
mapeada por tipo de documento; regras LGPD acordadas (retenção com jurídico).
